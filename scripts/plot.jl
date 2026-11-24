import ArchGDAL
import Rasters
import CSV
import DataFrames
import Printf
import Downloads
import MapTiles
import Tyler
import TileProviders
import CairoMakie
import Makie
import ProgressBars: ProgressBar
import FSFS

const OSM_TILE_CACHE = joinpath(FSFS.FSFS_CACHE_DIR, "osm_tiles")
const OSM_USER_AGENT = "FSFS/0.1.0 (flood evacuation simulation; https://github.com/t-garin/fsfs)"
const WATER_THRESHOLD = 0.01  # m; cells shallower than this are not drawn
const DEM_ALPHA = 0.5  # ghosts the terrain relief over the OSM basemap

struct DiskBackedDownloader <: Tyler.AbstractDownloader
    cache_dir::String
    inner::Tyler.ByteDownloader
end

DiskBackedDownloader(cache_dir::String) = DiskBackedDownloader(cache_dir, Tyler.ByteDownloader())

function Tyler.download_tile_data(
        dl::DiskBackedDownloader,
        provider::TileProviders.AbstractProvider,
        url::String,
    )
    path = joinpath(dl.cache_dir, string(hash(url)) * splitext(url)[2])
    isfile(path) && return read(path)
    mkpath(dl.cache_dir)
    temp = path * ".part"
    Downloads.download(
        url,
        temp;
        downloader = dl.inner.downloader,
        timeout = dl.inner.timeout,
        headers = ["User-Agent" => OSM_USER_AGENT],
    )
    mv(temp, path; force = true)
    return read(path)
end

Tyler.get_downloader(::TileProviders.AbstractProvider) = DiskBackedDownloader(OSM_TILE_CACHE)

function find_dem(depth::Rasters.Raster)::Rasters.Raster
    for dir in readdir(FSFS.FSFS_CACHE_DIR; join = true)
        path = joinpath(dir, "dem.tif")
        isfile(path) || continue
        candidate = Rasters.Raster(path)
        size(candidate) == size(depth) && return candidate
    end
    error("no dem.tif in fsfs_cache matches the depth grid $(size(depth))")
end

function plot_step(
        map::Tyler.Map,
        step::Int,
        data::DataFrames.DataFrame,
        xs::Vector,
        ys::Vector,
        dem::Rasters.Raster,
        depths::Dict{Int, Matrix{Float32}},
        max_depth::Float32,
        colors::Dict{Symbol, Makie.RGBf},
    )
    Makie.heatmap!(
        map.axis,
        xs,
        ys,
        Matrix(read(dem));
        colormap = Makie.cgrad(:viridis),
        alpha = DEM_ALPHA,
    )
    water = copy(depths[step])
    water[water .< WATER_THRESHOLD] .= NaN
    Makie.heatmap!(
        map.axis,
        xs,
        ys,
        water;
        colormap = Makie.cgrad(:deep),
        colorrange = (0.0, max_depth),
        alpha = 0.6,
    )
    for status in (:safe, :danger, :dead)
        rows = [r for r in DataFrames.eachrow(data) if r.time == step && r.status == string(status)]
        isempty(rows) && continue
        Makie.scatter!(
            map.axis,
            [xs[r.col] for r in rows],
            [ys[r.row] for r in rows];
            color = colors[status],
            markersize = 10,
        )
    end
    return nothing
end

for outdir in [joinpath(FSFS.FSFS_DATA_DIR, "sim_out", "malpasset")] # ["sim_out/dam", "sim_out/rain", "sim_out/river"]

    data = CSV.read(joinpath(outdir, "data.csv"), DataFrames.DataFrame)
    steps = sort(
        collect(
            parse(Int, match(r"depth-001-(\d+).tif", file).captures[1])
                for file in readdir(outdir) if occursin("depth-001-", file)
        )
    )
    depth_first = Rasters.Raster(joinpath(outdir, Printf.@sprintf("depth-001-%05d.tif", first(steps))))
    xs = collect(Rasters.lookup(depth_first, Rasters.X))
    ys = collect(Rasters.lookup(depth_first, Rasters.Y))
    dem = find_dem(depth_first)
    extent = Rasters.extent(depth_first)

    depths = Dict(
        step => Matrix(Float32.(coalesce.(read(Rasters.Raster(joinpath(outdir, Printf.@sprintf("depth-001-%05d.tif", step)))), 0.0f0)))
            for step in steps
    )
    max_depth = isempty(depths) ? 1.0f0 : maximum(maximum(v) for v in values(depths))

    colors = Dict(:safe => Makie.RGBf(0.2, 0.8, 0.2), :danger => Makie.RGBf(0.9, 0.6, 0.1), :dead => Makie.RGBf(0.7, 0.1, 0.1))
    for step in ProgressBar(steps)
        map = Tyler.Map(
            extent,
            MapTiles.web_mercator;
            axis = (; title = "flood step $step", aspect = Makie.DataAspect()),
        )
        plot_step(map, step, data, xs, ys, dem, depths, max_depth, colors)
        path = joinpath(outdir, Printf.@sprintf("plot-step-%d.png", step))
        Makie.save(path, map.figure)
        Base.close(map)
        println("wrote ", path)
    end
end
