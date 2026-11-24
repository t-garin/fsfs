import FSFS
import Rasters
import MapTiles

const FIXTURE_COLS = 130:330
const FIXTURE_ROWS = 32:332

function crop_fixture(raster::Rasters.Raster, cols::UnitRange, rows::UnitRange)::Rasters.Raster
    values = read(raster)[cols, rows]
    dims = (
        Rasters.X(Rasters.lookup(raster, Rasters.X)[cols]),
        Rasters.Y(Rasters.lookup(raster, Rasters.Y)[rows]),
    )
    return Rasters.Raster(values, dims; crs = Rasters.crs(raster), missingval = Rasters.missingval(raster))
end

function main(cache_dir::String, fixtures_dir::String)
    names = ["dem.tif", "manning.tif", "buildings.tif", "population_FRA_2020.tif"]
    for name in names
        raster = Rasters.Raster(joinpath(cache_dir, name))
        fixture = crop_fixture(raster, FIXTURE_COLS, FIXTURE_ROWS)
        FSFS.save_tif(fixture, name; outdir = fixtures_dir)
    end
    dem = Rasters.Raster(joinpath(fixtures_dir, "dem.tif"))
    x = Rasters.lookup(dem, Rasters.X)
    y = Rasters.lookup(dem, Rasters.Y)
    lon_min, lat_max = MapTiles.project((first(x), first(y)), MapTiles.WebMercator(), MapTiles.WGS84())
    lon_max, lat_min = MapTiles.project((last(x), last(y)), MapTiles.WebMercator(), MapTiles.WGS84())
    println("fixtures: ", size(dem), " cells at ", round((last(x) - first(x)) / (length(x) - 1); digits = 1), " m")
    println("fixtures: bbox = (", lon_min, ", ", lat_min, ", ", lon_max, ", ", lat_max, ")")
    return nothing
end

source_cache = isempty(ARGS) ?
    joinpath(FSFS.FSFS_CACHE_DIR, "6.7_43.38_6.82_43.54_z12_res30.0") : ARGS[1]
fixtures_dir = length(ARGS) < 2 ? joinpath(@__DIR__, "..", "test", "fixtures") : ARGS[2]
main(source_cache, fixtures_dir)
