import Agents
import FSFS
import Profile
import Random
import Rasters

const BENCH_SNAPSHOT_STEPS = 120
const BENCH_WARMUP_STEPS = 30
const BENCH_OUTDIR = joinpath(
    FSFS.FSFS_DATA_DIR,
    "sim_out",
    "malpasset",
    "sweep",
    "dam_failure_dam_height_final_0.0",
)

function bench_config(n_steps::Int, population_ratio::Float64)::NamedTuple
    return (
        bbox=(6.70, 43.38, 6.82, 43.54),
        spatial_resolution=30.0,
        dem_zoom_level=12,
        temporal_resolution=60.0,
        n_steps=n_steps,
        flood_threshold=0.01f0,
        speed=1.4,
        low_risk_perception=0.3,
        death_depth=1.65,
        death_time=300.0,
        max_crowd_density=0.5,
        entrance_ratio=0.5,
        penalty_walk_in_water=10,
        penalty_per_elevation=10,
        vision_range=100.0,
        population=(iso3="FRA", year=2020),
        population_ratio=population_ratio,
        rescue_ratio=0.01,
        rescue_spawn_time=300.0,
        n_sources=500,
        rivulet_thickness=0.1,
        rivulet_length=10,
        default_manning=0.04f0,
        manning=FSFS.DEFAULT_MANNING,
        outdir=BENCH_OUTDIR,
        rain=(peak=100.0f0,),
        river_source=nothing,
        dam_failure=nothing,
    )
end

function build_benchmark_model(config::NamedTuple)::Agents.ABM
    cache_dir = FSFS.fsfs_cache_dir(config.bbox, config.dem_zoom_level, config.spatial_resolution)
    dem = Rasters.Raster(joinpath(cache_dir, "dem.tif"))
    dem_matrix::Matrix{Float32} = Float32.(coalesce.(read(dem), 0.0f0))
    stack = FSFS.load_flood(config.outdir, dem, BENCH_SNAPSHOT_STEPS, config.temporal_resolution)
    buildings = FSFS.load_buildings(cache_dir, dem, config.bbox, config.manning, config.default_manning)
    population::Union{Matrix{Float32}, Nothing} = FSFS.load_population(config, cache_dir, dem)
    flooded = FSFS.flooded_mask(stack, Float32(config.flood_threshold))
    counts = FSFS.agent_counts(config, population, flooded)
    println(
        "benchmark: ",
        counts.n_agents,
        " agents on grid ",
        size(dem_matrix, 1),
        " x ",
        size(dem_matrix, 2),
    )
    rng = Random.MersenneTwister(42)
    return FSFS.build_model(
        stack,
        dem_matrix,
        buildings,
        population,
        (config..., rng = rng),
        flooded,
    )
end

function benchmark(; n_steps::Int, population_ratio::Float64)
    config = bench_config(n_steps, population_ratio)
    isfile(joinpath(config.outdir, "depth-001-00001.tif")) || error(
        "no cached Torrent output at $(config.outdir); run `julia malpasset_dam.jl` first",
    )
    model = build_benchmark_model(config)
    Agents.run!(
        model,
        BENCH_WARMUP_STEPS;
        adata = [:status, :pos, :action],
        mdata = [model.metrics.n_safe, model.metrics.n_danger, model.metrics.n_dead],
        showprogress = false,
    )
    Profile.clear()
    elapsed = @elapsed Profile.@profile Agents.run!(
        model,
        config.n_steps;
        adata = [:status, :pos, :action],
        mdata = [model.metrics.n_safe, model.metrics.n_danger, model.metrics.n_dead],
        showprogress = false,
    )
    println(
        "benchmark: ",
        round(elapsed; digits = 2),
        " s over ",
        config.n_steps,
        " steps (",
        round(1000 * elapsed / config.n_steps; digits = 2),
        " ms/step)",
    )
    Profile.print(format = :flat, sortedby = :count, mincount = 10)
    return nothing
end

benchmark(
    ;
    n_steps = isempty(ARGS) ? 10 : parse(Int, ARGS[1]),
    population_ratio = length(ARGS) < 2 ? 0.1 : parse(Float64, ARGS[2]),
)
