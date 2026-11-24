import Rasters

const NO_DATA = -9999.0f0
const FSFS_DATA_DIR = get(ENV, "FSFS_DATA_DIR", joinpath(homedir(), "fsfs_data"))
const FSFS_CACHE_DIR = joinpath(FSFS_DATA_DIR, "fsfs_cache")

const DEFAULT_MANNING = [
    ("natural", "wood", 0.36f0),
    ("natural", "scrub", 0.40f0),
    ("natural", "grassland", 0.368f0),
    ("natural", "wetland", 0.1825f0),
    ("natural", "water", 0.03f0),
    ("landuse", "forest", 0.40f0),
    ("landuse", "meadow", 0.325f0),
    ("landuse", "grass", 0.368f0),
    ("landuse", "farmland", 0.325f0),
    ("landuse", "residential", 0.0678f0),
    ("landuse", "commercial", 0.0404f0),
    ("landuse", "industrial", 0.0404f0),
    ("landuse", "quarry", 0.0113f0),
    ("leisure", "park", 0.0404f0),
    ("leisure", "garden", 0.0404f0),
    ("waterway", "river", 0.035f0),
    ("waterway", "stream", 0.04f0),
    ("waterway", "canal", 0.035f0),
]

"""
Build a 2-D raster on the DEM grid from a matrix of values.

# Arguments
- `values::AbstractMatrix`: cell values.
- `dem::Rasters.Raster`: raster defining the grid.

# Returns
A `Raster` in Web Mercator with the DEM's X/Y lookups.
"""
function matrix_raster(values::AbstractMatrix, dem::Rasters.Raster)::Rasters.Raster
    return Rasters.Raster(
        values,
        (
            Rasters.X(Rasters.lookup(dem, Rasters.X)),
            Rasters.Y(Rasters.lookup(dem, Rasters.Y)),
        );
        crs = Rasters.EPSG(3857),
        missingval = NO_DATA,
    )
end

"""
Write a raster to disk as a GeoTIFF in Web Mercator.

# Returns
The full path of the written file.
"""
function save_tif(raster::Rasters.Raster, name::String; outdir::String)::String
    mkpath(outdir)
    path::String = joinpath(outdir, name)
    write(path, raster; crs = Rasters.EPSG(3857), missingval = NO_DATA)
    return path
end
