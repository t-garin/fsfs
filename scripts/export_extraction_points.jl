import CSV
import DataFrames
import FSFS
import Random
include(joinpath(@__DIR__, "..", "malpasset_dam.jl"))
include(joinpath(@__DIR__, "..", "garonne_1875.jl"))

"""
Load the cached building mask as a Boolean matrix.

# Arguments
- `cache_dir::String`: per-bbox cache directory.

# Returns
The building mask in `(col, row)` order.
"""
function load_cached_buildings(cache_dir::String)::Matrix{Bool}
    path::String = joinpath(cache_dir, "buildings.tif")
    return Bool.(coalesce.(read(FSFS.Rasters.Raster(path)), 0.0f0))
end

"""
Write the extraction points of a reference case to `extraction_points.csv`.

The points are deterministic: `get_extraction_points` draws from
`MersenneTwister(seed)` before any agent is spawned, so they depend only on
the cached building mask, `seed` and `entrance_ratio`.

# Arguments
- `config::NamedTuple`: reference-case simulation options; uses `bbox`,
  `dem_zoom_level`, `spatial_resolution`, `seed` and `entrance_ratio`.

# Returns
The path of the written CSV.
"""
function export_extraction_points(config::NamedTuple)::String
    cache_dir::String = FSFS.fsfs_cache_dir(
        config.bbox,
        config.dem_zoom_level,
        config.spatial_resolution,
    )
    buildings::Matrix{Bool} = load_cached_buildings(cache_dir)
    extraction::BitMatrix = FSFS.get_extraction_points(
        buildings,
        .!buildings,
        Random.MersenneTwister(config.seed),
        config.entrance_ratio,
    )
    cells::Vector{Tuple{Int, Int}} =
        [Tuple(ix.I) for ix in CartesianIndices(extraction) if extraction[ix]]
    table::DataFrames.DataFrame = DataFrames.DataFrame(
        (col = [cell[1] for cell in cells], row = [cell[2] for cell in cells]),
    )
    out::String = joinpath(cache_dir, "extraction_points.csv")
    CSV.write(out, table)
    return out
end

target::String = isempty(ARGS) ? "malpasset" : first(ARGS)
config::NamedTuple = if target == "malpasset"
    merge(malpasset_config(), (seed = 1312,))
elseif target == "garonne"
    merge(garonne_1875_config(), (seed = 1312,))
else
    error("unknown target: $target")
end
println(export_extraction_points(config))
