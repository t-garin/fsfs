import FSFS
include(joinpath(@__DIR__, "..", "malpasset_dam.jl"))
include(joinpath(@__DIR__, "..", "garonne_1875.jl"))

"""
Fetch an Overpass-derived raster with backoff retries.

# Arguments
- `fetch::Function`: function returning the raster matrix.
- `attempts::Int`: number of attempts.

# Returns
The raster matrix, or the error after `attempts` failed attempts.
"""
function fetch_overpass_with_retry(fetch::Function, attempts::Int)::Matrix
    for attempt::Int in 1:attempts
        try
            return fetch()
        catch err
            attempt == attempts && rethrow()
            @warn "Overpass fetch failed ($err); retrying in $(10 * attempt) s"
            sleep(10 * attempt)
        end
    end
    error("unreachable")
end

"""
Warm the shared per-bbox cache so the sweep workers never race on downloads.

# Arguments
- `config::NamedTuple`: simulation options; uses `bbox`, `dem_zoom_level`,
  `spatial_resolution`, `rain`, `manning`, `default_manning` and `population`.

# Returns
`nothing`.
"""
function warm_cache!(config::NamedTuple)
    cache_dir::String = FSFS.fsfs_cache_dir(
        config.bbox,
        config.dem_zoom_level,
        config.spatial_resolution,
    )
    dem::FSFS.Rasters.Raster = FSFS.fetch_dem(
        config.bbox;
        dem_zoom_level = config.dem_zoom_level,
        spatial_resolution = config.spatial_resolution,
        cache_dir,
    )
    if config.rain !== nothing
        FSFS.synthetic_rain(
            dem;
            n_bands = config.n_steps + 1,
            peak = config.rain.peak,
            cache_dir,
        )
    end
    manning_path::String = joinpath(cache_dir, "manning.tif")
    if !isfile(manning_path)
        manning_array::Matrix{Float32} = fetch_overpass_with_retry(3) do
            FSFS.overpass_mask(
                config.bbox,
                dem;
                kind = :manning,
                manning = config.manning,
                default_manning = config.default_manning,
            )
        end
        FSFS.save_tif(FSFS.matrix_raster(manning_array, dem), "manning.tif"; outdir = cache_dir)
    end
    buildings_path::String = joinpath(cache_dir, "buildings.tif")
    if !isfile(buildings_path)
        buildings_mask::Matrix{Bool} = fetch_overpass_with_retry(3) do
            FSFS.overpass_mask(
                config.bbox,
                dem;
                kind = :buildings,
                manning = config.manning,
                default_manning = config.default_manning,
            )
        end
        FSFS.save_buildings(buildings_mask, dem, cache_dir)
    end
    FSFS.fetch_population(
        config.bbox,
        dem;
        iso3 = config.population.iso3,
        year = config.population.year,
        cache_dir,
    )
    return nothing
end

target::String = isempty(ARGS) ? "malpasset" : first(ARGS)
if target == "malpasset"
    warm_cache!(malpasset_config())
elseif target == "garonne"
    warm_cache!(garonne_1875_config())
else
    error("unknown target: $target")
end
println("warm_cache: done")
