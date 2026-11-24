import Agents
import FSFS
import JSON
import Rasters
import Test

const TEST_BBOX = (6.734928921956988, 43.47522993110841, 6.788827839004159, 43.533870843462516)
const TEST_RESOLUTION = 30.0
const TEST_ZOOM = 12
const TEST_STEPS = 30
const TEST_SEED = 42
const FIXTURES_DIR = joinpath(@__DIR__, "fixtures")
const KGO_PATH = joinpath(@__DIR__, "kgo.json")

const DAM_FAILURE = (
    lat = 43.5120778,
    lon = 6.7565,
    breach_width_top = 222.0,
    breach_width_bottom = 180.0,
    reservoir_volume_initial = 5.0e7,
    reservoir_surface_area = 7.6e5,
    dam_height_initial = 66.0,
    dam_height_final = 0.0,
    failure_period = 300.0,
)

const SCENARIOS = (
    rain = (rain = (peak = 100.0f0,),),
    river = (river_source = (lat = 43.533, lon = 6.757, peak_flux = 2000.0, base_flux = 0.0),),
    dam = (rain = (peak = 100.0f0,), dam_failure = DAM_FAILURE),
)

function base_config(; outdir::String, cache_root::String)::NamedTuple
    return (
        bbox = TEST_BBOX,
        spatial_resolution = TEST_RESOLUTION,
        dem_zoom_level = TEST_ZOOM,
        temporal_resolution = 60.0,
        n_steps = TEST_STEPS,
        flood_threshold = 0.01f0,
        speed = 1.4,
        low_risk_perception = 0.3,
        death_depth = 1.65,
        death_time = 300.0,
        max_crowd_density = 0.5,
        entrance_ratio = 0.5,
        penalty_walk_in_water = 10,
        penalty_per_elevation = 10,
        vision_range = 100.0,
        population = (iso3 = "FRA", year = 2020),
        population_ratio = 0.1,
        rescue_ratio = 0.1,
        n_sources = 500,
        rivulet_thickness = 0.1,
        rivulet_length = 10,
        default_manning = 0.018f0,
        manning = FSFS.DEFAULT_MANNING,
        warning_lead_time = 900.0,
        warning_compliance = 0.8,
        warning_response_delay = 300.0,
        outdir = outdir,
        cache_root = cache_root,
        seed = TEST_SEED,
        rain = nothing,
        river_source = nothing,
        dam_failure = nothing,
    )
end

function scenario_config(name::Symbol; outdir::String, cache_root::String)::NamedTuple
    return merge(base_config(; outdir, cache_root), SCENARIOS[name])
end

function populate_cache!(cache_root::String)::String
    cache_dir = FSFS.fsfs_cache_dir(
        TEST_BBOX,
        TEST_ZOOM,
        TEST_RESOLUTION;
        cache_root,
    )
    for name in ["dem.tif", "manning.tif", "buildings.tif", "population_FRA_2020.tif"]
        cp(joinpath(FIXTURES_DIR, name), joinpath(cache_dir, name))
    end
    return cache_dir
end

function signature(result::NamedTuple, config::NamedTuple)::NamedTuple
    metrics = result.metrics
    flooded = FSFS.flooded_mask(result.model.flood, Float32(config.flood_threshold))
    final_depth = read(result.model.flood[:depth])[:, :, end]
    return (
        n_agents = length(Agents.allagents(result.model)),
        n_safe = Int(metrics.n_safe[end]),
        n_danger = Int(metrics.n_danger[end]),
        n_dead = Int(metrics.n_dead[end]),
        peak_danger = Int(maximum(metrics.n_danger)),
        flooded_cells = count(flooded),
        final_depth_sum = round(sum(final_depth); digits = 2),
    )
end

function run_scenario(name::Symbol)::NamedTuple
    return mktempdir() do workdir
        cache_root = joinpath(workdir, "cache")
        mkpath(cache_root)
        populate_cache!(cache_root)
        config = scenario_config(name; outdir = joinpath(workdir, "out"), cache_root)
        result = FSFS.simulate(; config)
        return signature(result, config)
    end
end

function run_all()::Dict{Symbol, NamedTuple}
    results = Dict{Symbol, NamedTuple}()
    for name in keys(SCENARIOS)
        println("running scenario: ", name)
        results[name] = run_scenario(name)
        println("  ", name, ": ", results[name])
    end
    return results
end

function to_dict(sig::NamedTuple)::Dict{String, Any}
    return Dict(string(k) => v for (k, v) in pairs(sig))
end

function write_kgo(signatures::Dict{String, Any})
    open(KGO_PATH, "w") do io
        JSON.print(io, signatures, 2)
    end
    return nothing
end

function compare_signature(got::NamedTuple, expected::Dict{String, Any})
    for key in keys(got)
        got_value = got[key]
        want_value = expected[string(key)]
        if key === :final_depth_sum
            Test.@test isapprox(got_value, want_value; atol = 0.5)
        else
            Test.@test got_value == want_value
        end
    end
    return nothing
end

function main()
    results = run_all()
    if "--update-kgo" in ARGS
        kgo = Dict{String, Any}(string(name) => to_dict(sig) for (name, sig) in results)
        return write_kgo(kgo)
    end
    expected = Dict{String, Any}(
        string(name) => Dict{String, Any}(signature) for (name, signature) in JSON.parsefile(KGO_PATH)
    )
    Test.@testset "FSFS regression" begin
        for name in keys(SCENARIOS)
            compare_signature(results[name], expected[string(name)])
        end
    end
    return nothing
end

main()
