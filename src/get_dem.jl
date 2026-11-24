import Chain: @chain
import Extents
import HTTP
import ImageInpainting
import MapTiles
import Rasters
import TileProviders

const DEM_PROVIDER = TileProviders.Provider(
    "https://s3.amazonaws.com/elevation-tiles-prod/geotiff/{z}/{x}/{y}.tif";
    name = :mapzen_terrain,
    max_zoom = 15,
)

"""
Download one terrain tile from the Mapzen provider.

# Arguments
- `dem_zoom_level::Int`: zoom level.
- `tx::Int`, `ty::Int`: tile coordinates.

# Returns
A path to the downloaded tile, or `nothing` when the tile is not found.
"""
function download_tile(dem_zoom_level::Int, tx::Int, ty::Int)::Union{String, Nothing}
    response::HTTP.Response = HTTP.get(
        TileProviders.geturl(DEM_PROVIDER, tx, ty, dem_zoom_level);
        status_exception = false,
    )
    response.status == 404 && return nothing
    tile_path::String = tempname() * ".tif"
    write(tile_path, response.body)
    return tile_path
end

"""
Fetch and cache a Digital Elevation Model over the bounding box.

# Arguments
- `bbox::NTuple{4, Float64}`: `(lon_min, lat_min, lon_max, lat_max)`.
- `dem_zoom_level::Int`: tile zoom level.
- `spatial_resolution::Float64`: target resolution in meters.
- `cache_dir::String`: directory to cache the output.

# Returns
The DEM `Raster`.
"""
function fetch_dem(
        bbox::NTuple{4, Float64};
        dem_zoom_level::Int = 13,
        spatial_resolution::Float64 = 10.0,
        cache_dir::String = FSFS_CACHE_DIR,
    )::Rasters.Raster
    path::String = joinpath(cache_dir, "dem.tif")
    isfile(path) && return Rasters.Raster(path)
    lon_min::Float64, lat_min::Float64, lon_max::Float64, lat_max::Float64 = bbox
    tile_grid::MapTiles.TileGrid = MapTiles.TileGrid(
        Extents.Extent(X = (lon_min, lon_max), Y = (lat_min, lat_max)),
        dem_zoom_level,
        MapTiles.WGS84(),
    )
    tile_paths::Vector{String} =
        [download_tile(tile.z, tile.x, tile.y) for tile in tile_grid]
    crop_extent::Extents.Extent = MapTiles.project_extent(
        Extents.Extent(X = (lon_min, lon_max), Y = (lat_min, lat_max)),
        MapTiles.WGS84(),
        MapTiles.WebMercator(),
    )
    dem_raster::Rasters.Raster =
        resample_dem_to_grid(tile_paths, crop_extent, spatial_resolution)
    save_tif(dem_raster, "dem.tif"; outdir = cache_dir)
    return dem_raster
end

"""
Mosaic, crop, resample and hole-fill a set of DEM tiles.

# Arguments
- `tile_paths::Vector{String}`: paths to the downloaded tiles.
- `crop_extent::Extents.Extent`: target extent.
- `spatial_resolution::Float64`: target resolution in meters.

# Returns
The resampled DEM `Raster`.
"""
function resample_dem_to_grid(
        tile_paths::Vector{String},
        crop_extent::Extents.Extent,
        spatial_resolution::Float64,
    )::Rasters.Raster
    return @chain Rasters.mosaic(
        first,
        Rasters.Raster.(filter(!isnothing, tile_paths));
        atol = 1.0e-3,
        progress = false,
    ) begin
        Rasters.crop(; to = crop_extent)
        Float32.(Rasters.replace_missing(_, NO_DATA))
        Rasters.resample(; res = spatial_resolution, method = :bilinear)
        fill_dem_holes(_)
    end
end

"""
Fill missing cells of a DEM raster by inpainting.

# Returns
A copy of the raster with missing cells filled.
"""
function fill_dem_holes(dem::Rasters.Raster)::Rasters.Raster
    raw = Rasters.read(dem)
    values = Float32.(Array(coalesce.(raw, 0.0f0)))
    missing = Float32.(Array(coalesce.(raw, NO_DATA))) .== NO_DATA
    all(.!missing) && return dem
    filled = ImageInpainting.inpaint(values, missing, ImageInpainting.Criminisi(3, 3))
    return Rasters.Raster(
        filled,
        Rasters.dims(dem);
        crs = Rasters.crs(dem),
        missingval = NO_DATA,
    )
end
