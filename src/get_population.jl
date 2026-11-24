import Extents
import HTTP
import JSON
import Rasters

const WORLDPOP_REST_URL = "https://hub.worldpop.org/rest/data/pop/wpgp?iso3="

"""
Fetch and cache a WorldPop population raster over the bounding box.

# Arguments
- `bbox::NTuple{4, Float64}`: `(lon_min, lat_min, lon_max, lat_max)`.
- `dem::Rasters.Raster`: elevation raster defining the grid.
- `iso3::String`: country ISO-3 code.
- `year::Int`: population year.
- `cache_dir::String`: directory to cache the output.

# Returns
The population `Raster`.
"""
function fetch_population(
        bbox::NTuple{4, Float64},
        dem::Rasters.Raster;
        iso3::String,
        year::Int,
        cache_dir::String = FSFS_CACHE_DIR,
    )::Rasters.Raster
    name::String = "population_$(iso3)_$(year).tif"
    path::String = joinpath(cache_dir, name)
    isfile(path) && return Rasters.Raster(path)
    url::String = worldpop_url(iso3, year)
    @info "fetching WorldPop population" url
    tile_path::String = tempname() * ".tif"
    write(tile_path, HTTP.get(url).body)
    population::Rasters.Raster =
        crop_resample_population(Rasters.Raster(tile_path), bbox, dem)
    save_tif(population, name; outdir = cache_dir)
    return population
end

"""
Resolve the WorldPop download URL for a country and year.

# Arguments
- `iso3::String`: country ISO-3 code.
- `year::Int`: population year.

# Returns
The URL of the matching population raster.
"""
function worldpop_url(iso3::String, year::Int)::String
    response::HTTP.Response = HTTP.get(WORLDPOP_REST_URL * iso3)
    data = JSON.parse(String(response.body))
    for entry in get(data, "data", Any[])
        parse(Int, entry["popyear"]) == year || continue
        return "https://data.worldpop.org/" * entry["data_file"]
    end
    error("WorldPop has no population raster for iso3=$iso3, year=$year")
end

"""
Crop and resample a population raster to the DEM grid, conserving total population.

# Arguments
- `source::Rasters.Raster`: source population raster.
- `bbox::NTuple{4, Float64}`: `(lon_min, lat_min, lon_max, lat_max)`.
- `dem::Rasters.Raster`: target grid.

# Returns
The resampled population `Raster`.
"""
function crop_resample_population(
        source::Rasters.Raster,
        bbox::NTuple{4, Float64},
        dem::Rasters.Raster,
    )::Rasters.Raster
    lon_min::Float64, lat_min::Float64, lon_max::Float64, lat_max::Float64 = bbox
    extent::Extents.Extent = Extents.Extent(X = (lon_min, lon_max), Y = (lat_min, lat_max))
    cropped::Rasters.Raster = Rasters.crop(source; to = extent)
    resampled::Rasters.Raster = Rasters.resample(cropped; to = dem, method = :nearest)
    total_input::Float64 = sum(coalesce.(read(cropped), 0.0f0))
    total_output::Float64 = sum(coalesce.(read(resampled), 0.0f0))
    scale::Float64 = total_output > 0 ? total_input / total_output : 1.0
    values::Matrix{Float32} = Float32.(coalesce.(read(resampled), 0.0f0) .* scale)
    return Rasters.Raster(
        values,
        Rasters.dims(resampled);
        crs = Rasters.crs(resampled),
        missingval = NO_DATA,
    )
end

"""
Load the population raster as a non-negative `Float32` matrix.

# Arguments
- `config::NamedTuple`: simulation options; uses `config.population`.
- `cache_dir::String`: directory containing the cached raster.
- `dem::Rasters.Raster`: elevation raster defining the grid.

# Returns
A population matrix, or `nothing` when no population is configured.
"""
function load_population(
        config::NamedTuple,
        cache_dir::String,
        dem::Rasters.Raster,
    )::Union{Matrix{Float32}, Nothing}
    config.population === nothing && return nothing
    pop::Rasters.Raster = fetch_population(
        config.bbox,
        dem;
        iso3 = config.population.iso3,
        year = config.population.year,
        cache_dir,
    )
    values::Matrix{Float32} = Float32.(coalesce.(read(pop), 0.0f0))
    return max.(values, 0.0f0)
end
