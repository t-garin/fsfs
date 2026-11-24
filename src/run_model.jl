import Agents
import CSV
import DataFrames
import Distributed
import Printf
import Random
import Rasters

"""
Build (and create) the cache directory for a simulation configuration.

# Arguments
- `bbox::NTuple{4, Float64}`: `(lon_min, lat_min, lon_max, lat_max)`.
- `dem_zoom_level::Int`: DEM zoom level.
- `spatial_resolution::Float64`: spatial resolution in meters.
- `cache_root::String`: root cache directory.

# Returns
The cache directory path.
"""
function fsfs_cache_dir(
        bbox::NTuple{4, Float64},
        dem_zoom_level::Int,
        spatial_resolution::Float64;
        cache_root::String = FSFS_CACHE_DIR,
    )::String
    tag::String = join(round.(bbox; digits = 4), "_") *
        "_z$(dem_zoom_level)_res$(spatial_resolution)"
    dir::String = joinpath(cache_root, tag)
    mkpath(dir)
    return dir
end

"""
Mark cells that ever exceed the flood-depth threshold.

# Arguments
- `stack::Rasters.RasterStack`: flood raster stack.
- `threshold::Float32`: depth threshold in meters.

# Returns
A `BitMatrix` of flooded cells.
"""
function flooded_mask(stack::Rasters.RasterStack, threshold::Float32)::BitMatrix
    peak_depth = maximum(read(stack[:depth]); dims = 3)
    return dropdims(peak_depth .> threshold; dims = 3)
end

"""
Resolve the cache root directory from a simulation config.

The cache lives under `data_dir/fsfs_cache` unless `cache_root` is set
explicitly.

# Arguments
- `config::NamedTuple`: simulation options.

# Returns
The cache root as a `String`.
"""
function cache_root_for(config::NamedTuple)::String
    return get(config, :cache_root, joinpath(get(config, :data_dir, FSFS_DATA_DIR), "fsfs_cache"))
end

"""
Fetch or load all simulation inputs needed to build the model.

# Arguments
- `config::NamedTuple`: simulation options.

# Returns
A `NamedTuple` with `stack`, `dem`, `buildings`, `population` and `flooded`.
"""
function pipeline_inputs(; config::NamedTuple)::NamedTuple
    cache_root::String = cache_root_for(config)
    cache_dir::String = fsfs_cache_dir(
        config.bbox,
        config.dem_zoom_level,
        config.spatial_resolution;
        cache_root,
    )
    stack = flood(config, cache_dir)
    dem = Rasters.Raster(joinpath(cache_dir, "dem.tif"))
    dem_matrix::Matrix{Float32} = Float32.(coalesce.(read(dem), 0.0f0))
    @info "simulate: OSM buildings mask" cache_dir
    buildings = load_buildings(cache_dir, dem, config.bbox, config.manning, config.default_manning)
    population = load_population(config, cache_dir, dem)
    flooded = flooded_mask(stack, Float32(config.flood_threshold))
    return (
        stack = stack,
        dem = dem_matrix,
        buildings = buildings,
        population = population,
        flooded = flooded,
    )
end

"""
Write the initial agent states to `agents_init.csv`.

# Returns
`nothing`.
"""
function write_agents_init(model::Agents.ABM, outdir::String)
    init_df = DataFrames.DataFrame(
        (
            id = a.id,
            role = a.role,
            risk_perception = a.risk_perception,
            vulnerability = a.vulnerability_factor,
        ) for a in Agents.allagents(model)
    )
    CSV.write(joinpath(outdir, "agents_init.csv"), init_df)
    return nothing
end

"""
Write agent and metrics tables to `data.csv` and `metrics.csv`.

# Arguments
- `data::DataFrames.DataFrame`: agent-step data.
- `metrics::DataFrames.DataFrame`: model metrics.
- `outdir::String`: directory to write into.

# Returns
`nothing`.
"""
function write_step_outputs(data::DataFrames.DataFrame, metrics::DataFrames.DataFrame, outdir::String)
    csv_data = copy(data)
    csv_data.col = [p[1] for p in csv_data.pos]
    csv_data.row = [p[2] for p in csv_data.pos]
    DataFrames.select!(csv_data, DataFrames.Not(:pos))
    CSV.write(joinpath(outdir, "data.csv"), csv_data)
    CSV.write(joinpath(outdir, "metrics.csv"), metrics)
    return nothing
end

"""
Build the model, run the simulation and write the outputs.

# Arguments
- `config::NamedTuple`: simulation options.
- `inputs::NamedTuple`: simulation inputs from `pipeline_inputs`.

# Returns
A `NamedTuple` with `model`, `data` and `metrics`.
"""
function build_and_run!(config::NamedTuple, inputs::NamedTuple)::NamedTuple
    model = build_model(
        inputs.stack,
        inputs.dem,
        inputs.buildings,
        inputs.population,
        config,
        inputs.flooded,
    )
    write_agents_init(model, config.outdir)
    @info "simulate: stepping $(config.n_steps) turns"
    data, metrics = Agents.run!(
        model,
        config.n_steps;
        adata = [:status, :pos, :action],
        mdata = [model.metrics.n_safe, model.metrics.n_danger, model.metrics.n_dead],
        showprogress = true,
    )
    @info "simulate: writing CSVs" config.outdir
    write_step_outputs(data, metrics, config.outdir)
    return (model = model, data = data, metrics = metrics)
end

"""
Run the full flood-evacuation simulation pipeline.

# Arguments
- `config::NamedTuple`: simulation options.

# Returns
A `NamedTuple` with the built model, agent data, and metrics.
"""
function simulate(; config::NamedTuple)::NamedTuple
    seed = get(config, :seed, nothing)
    rng = seed === nothing ? Random.default_rng() : Random.MersenneTwister(seed)
    seed === nothing || Random.seed!(seed)
    cfg = (
        config...,
        population = get(config, :population, nothing),
        population_ratio = get(config, :population_ratio, 0.001),
        rescue_ratio = get(config, :rescue_ratio, 0.1),
        rescue_spawn_time = get(config, :rescue_spawn_time, 300.0),
        rng = rng,
        penalty_per_elevation = get(config, :penalty_per_elevation, 0),
        entrance_ratio = get(config, :entrance_ratio, 1.0),
        penalty_walk_in_water = get(config, :penalty_walk_in_water, 0),
        flood_threshold = get(config, :flood_threshold, 0.01f0),
        cache_root = cache_root_for(config),
        warning_lead_time = get(config, :warning_lead_time, 0.0),
        warning_compliance = get(config, :warning_compliance, 1.0),
        warning_response_delay = get(config, :warning_response_delay, 0.0),
    )
    cfg.rescue_spawn_time > cfg.n_steps * cfg.temporal_resolution &&
        @warn "rescue spawn time beyond the simulation horizon; rescue agents will never spawn"
    inputs = pipeline_inputs(; config = cfg)
    mkpath(cfg.outdir)
    @info "simulate: building ABM" counts = agent_counts(cfg, inputs.population, inputs.flooded)
    result = build_and_run!(cfg, inputs)
    println(
        "simulate: ",
        DataFrames.nrow(result.data),
        " agent-steps, ",
        DataFrames.nrow(result.metrics),
        " model steps",
    )
    return result
end

"""
Set a nested config value along a dotted path.

# Arguments
- `config::NamedTuple`: simulation options.
- `path::Tuple`: sequence of keys.
- `value`: value to set.

# Returns
The updated config.
"""
function set_config_value(config::NamedTuple, path::Tuple, value)::NamedTuple
    key, rest = first(path), Base.tail(path)
    isempty(rest) && return merge(config, (; key => value))
    inner = getfield(config, key)
    return merge(config, (; key => set_config_value(inner, rest, value)))
end

"""
Run a single parameter-sweep case and summarize the outcome.

# Arguments
- `config::NamedTuple`: base simulation options.
- `path::Tuple`: key path of the swept parameter.
- `value`: swept value.
- `outdir_root::String`: root output directory.
- `run_simulation`: function to run a simulation.

# Returns
A one-row `DataFrame` summarizing the case.
"""
function run_sweep_case(
        config::NamedTuple,
        path::Tuple,
        value,
        outdir_root::String,
        run_simulation,
    )::DataFrames.DataFrame
    param_name::Symbol = last(path)
    label::String = Printf.@sprintf("%s_%s", join(string.(path), "_"), value)
    cfg::NamedTuple = (
        set_config_value(config, path, value)...,
        outdir = joinpath(outdir_root, label),
    )
    rm(cfg.outdir; recursive = true, force = true)
    result::NamedTuple = run_simulation(; config = cfg)
    last_row = result.metrics[end, :]
    row = (
        (; (param_name => value), outdir = cfg.outdir),
        (
            n_dead = last_row.n_dead, n_safe = last_row.n_safe,
            peak_danger = maximum(result.metrics.n_danger),
        ),
    )
    return DataFrames.DataFrame([merge(row...)])
end

"""
Run a parameter sweep in parallel and summarize each case.

# Arguments
- `config::NamedTuple`: base simulation options.
- `path::Tuple`: key path of the swept parameter.
- `values::Vector`: values to sweep over.
- `outdir_root::String`: root output directory.
- `run_simulation`: function to run a simulation.

# Returns
A `DataFrame` with one row per swept value.
"""
function sweep_parameter(
        config::NamedTuple,
        path::Tuple,
        values::Vector;
        outdir_root::String,
        run_simulation = simulate,
    )::DataFrames.DataFrame
    Distributed.remotecall_eval(Distributed.Main, Distributed.procs(), :(import FSFS))
    summaries = Distributed.pmap(values) do value
        run_sweep_case(config, path, value, outdir_root, run_simulation)
    end
    return reduce(vcat, summaries)
end
