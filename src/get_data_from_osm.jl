import GeoInterface
import HTTP
import JSON
import MapTiles
import Rasters

"""
Look up the Manning coefficient for an OSM tag set.

# Arguments
- `tags::AbstractDict`: OSM tags.
- `manning`: list of `(key, value, n)` tuples.

# Returns
The matching Manning `n`, or `nothing` when no rule matches.
"""
function manning_value(tags::AbstractDict, manning)::Union{Float32, Nothing}
    for (osm_key::String, osm_value::String, manning_n::Float32) in manning
        get(tags, osm_key, "") == osm_value && return manning_n
    end
    return nothing
end

"""
Rasterize an OSM feature kind into a mask over the DEM grid.

# Arguments
- `bbox::NTuple{4, Float64}`: `(lon_min, lat_min, lon_max, lat_max)`.
- `dem::Rasters.Raster`: target grid.
- `kind::Symbol`: `:buildings` or `:manning`.
- `manning`: Manning coefficient rules.
- `default_manning::Float32`: fallback value.

# Returns
A matrix of filled values (`Bool` for buildings, `Float32` for manning).
"""
function overpass_mask(
        bbox::NTuple{4, Float64},
        dem::Rasters.Raster;
        kind::Symbol,
        manning,
        default_manning::Float32,
    )::Matrix
    filter_clause, feature_value, fallback =
        overpass_query_spec(Val(kind), manning, default_manning)
    geoms, fills = fetch_overpass_elements(bbox, filter_clause, feature_value, fallback)
    isempty(geoms) && return fill(fallback, size(dem))
    raster::Rasters.Raster = Rasters.rasterize(
        last,
        geoms;
        to = dem,
        fill = fills,
        missingval = missing,
        progress = false,
    )
    return coalesce.(read(raster), fallback)
end

"""
Build the Overpass query spec for building footprints.
"""
function overpass_query_spec(::Val{:buildings}, manning, default_manning::Float32)
    return ("way[\"building\"];", (_ -> true), false)
end

"""
Build the Overpass query spec for Manning coefficient features.
"""
function overpass_query_spec(::Val{:manning}, manning, default_manning::Float32)
    filter_clause = join(("way[\"$k\"=\"$v\"];" for (k, v, _) in manning), "")
    feature_value = (tags) -> manning_value(tags, manning)
    return (filter_clause, feature_value, default_manning)
end

"""
Query Overpass and return the matching polygons and fill values.

# Arguments
- `bbox::NTuple{4, Float64}`: `(lon_min, lat_min, lon_max, lat_max)`.
- `filter_clause::String`: Overpass element filter.
- `feature_value::Function`: maps tags to a fill value.
- `fallback`: value used when a feature has no match.

# Returns
A `(geoms, fills)` tuple of polygon geometries and fill values.
"""
function fetch_overpass_elements(
        bbox::NTuple{4, Float64},
        filter_clause::String,
        feature_value::Function,
        fallback,
    )::Tuple{Vector{Any}, Vector}
    lon_min::Float64, lat_min::Float64, lon_max::Float64, lat_max::Float64 = bbox
    query::String = "[out:json][timeout:30][bbox:$lat_min,$lon_min,$lat_max,$lon_max];($filter_clause);out geom;"
    url::String = "https://overpass-api.de/api/interpreter?data=" * HTTP.escapeuri(query)
    response::HTTP.Response = HTTP.get(url)
    data = JSON.parse(String(response.body))
    geoms::Vector{Any} = Any[]
    fills = Vector{typeof(fallback)}()
    for element in get(data, "elements", Any[])
        value = feature_value(get(element, "tags", Dict{String, Any}()))
        value === nothing && continue
        geometry = get(element, "geometry", Any[])
        length(geometry) >= 3 || continue
        ring::Vector{Tuple{Float64, Float64}} =
            [(Float64(point["lon"]), Float64(point["lat"])) for point in geometry]
        push!(geoms, osm_ring_polygon(ring))
        push!(fills, value)
    end
    return (geoms, fills)
end

"""
Build a Web-Mercator `GeoInterface` polygon from a lon/lat ring.

# Arguments
- `ring::Vector{Tuple{Float64, Float64}}`: `(lon, lat)` vertices.

# Returns
The projected polygon.
"""
function osm_ring_polygon(ring::Vector{Tuple{Float64, Float64}})::GeoInterface.Polygon
    return GeoInterface.Polygon(
        [
            GeoInterface.LinearRing(
                [
                    MapTiles.project((lon, lat), MapTiles.WGS84(), MapTiles.WebMercator()) for
                        (lon, lat) in ring
                ]
            ),
        ]
    )
end

"""
Cache a building mask to disk as a GeoTIFF.

# Arguments
- `mask::AbstractMatrix{Bool}`: building mask.
- `dem::Rasters.Raster`: raster defining the grid.
- `cache_dir::String`: directory to write into.

# Returns
The path of the written file.
"""
function save_buildings(mask::AbstractMatrix{Bool}, dem::Rasters.Raster, cache_dir::String)::String
    ras = matrix_raster(Float32.(mask), dem)
    return save_tif(ras, "buildings.tif"; outdir = cache_dir)
end

"""
Load or fetch the building mask over the DEM grid.

# Arguments
- `cache_dir::String`: directory containing the cached raster.
- `dem::Rasters.Raster`: raster defining the grid.
- `bbox::NTuple{4, Float64}`: `(lon_min, lat_min, lon_max, lat_max)`.
- `manning`: Manning coefficient rules.
- `default_manning::Float32`: fallback value.

# Returns
The building mask as a `BitMatrix`.
"""
function load_buildings(
        cache_dir::String,
        dem::Rasters.Raster,
        bbox::NTuple{4, Float64},
        manning,
        default_manning::Float32,
    )::BitMatrix
    buildings_path = joinpath(cache_dir, "buildings.tif")
    isfile(buildings_path) &&
        return Bool.(coalesce.(read(Rasters.Raster(buildings_path)), 0.0f0))
    mask = try
        overpass_mask(bbox, dem; kind = :buildings, manning, default_manning)
    catch err
        @warn "buildings mask failed ($err); treating the map as open"
        falses(size(dem))
    end
    save_buildings(mask, dem, cache_dir)
    return mask
end

"""
Load or fetch the Manning coefficient raster and cache it.

# Arguments
- `bbox::NTuple{4, Float64}`: `(lon_min, lat_min, lon_max, lat_max)`.
- `dem::Rasters.Raster`: raster defining the grid.
- `cache_dir::String`: directory to cache the output.
- `manning`: Manning coefficient rules.
- `default_manning::Float32`: fallback value.

# Returns
The path of the cached Manning GeoTIFF.
"""
function manning_from_osm(
        bbox::NTuple{4, Float64},
        dem::Rasters.Raster;
        cache_dir::String = FSFS_CACHE_DIR,
        manning,
        default_manning::Float32,
    )::String
    path::String = joinpath(cache_dir, "manning.tif")
    isfile(path) && return path
    manning_array::Matrix{Float32} = try
        overpass_mask(bbox, dem; kind = :manning, manning, default_manning)
    catch err
        @warn "Overpass manning rasterization failed ($err); using homogeneous n = $default_manning"
        fill(default_manning, size(dem))
    end
    ras = matrix_raster(manning_array, dem)
    return save_tif(ras, "manning.tif"; outdir = cache_dir)
end
