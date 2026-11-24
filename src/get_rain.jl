import Random
import Rasters

"""
Generate a synthetic multi-band rain raster and cache it to disk.

# Arguments
- `dem::Rasters.Raster`: elevation raster defining the grid.
- `n_bands::Int`: number of time bands.
- `peak::Float32`: peak rain rate.
- `radius::Float64`: storm radius as a fraction of the grid.
- `cache_dir::String`: directory to cache the output.

# Returns
The path of the cached rain GeoTIFF.
"""
function synthetic_rain(
        dem::Rasters.Raster;
        n_bands::Int,
        peak::Float32 = 40.0f0,
        radius::Float64 = 0.25,
        cache_dir::String = FSFS_CACHE_DIR,
    )::String
    name::String = "rain_peak$(peak)_bands$(n_bands).tif"
    path::String = joinpath(cache_dir, name)
    isfile(path) && return path
    cols::Int, rows::Int = size(dem)
    rain::Array{Float32, 3} =
        storm_rain_cells(Random.default_rng(), cols, rows, n_bands, peak, radius)
    rain_raster::Rasters.Raster = Rasters.Raster(
        rain,
        (
            Rasters.X(Rasters.lookup(dem, Rasters.X)),
            Rasters.Y(Rasters.lookup(dem, Rasters.Y)),
            Rasters.Band(1:n_bands),
        );
        crs = Rasters.EPSG(3857),
        missingval = NO_DATA,
    )
    return save_tif(rain_raster, name; outdir = cache_dir)
end

"""
Build a wandering Gaussian storm over a grid, one band per time step.

# Arguments
- `rng::Random.AbstractRNG`: random number generator.
- `cols::Int`, `rows::Int`: grid dimensions.
- `n_bands::Int`: number of time bands.
- `peak::Float32`: peak rain rate.
- `radius::Float64`: storm radius as a fraction of the grid.

# Returns
A `(cols, rows, n_bands)` `Float32` array of rain rates.
"""
function storm_rain_cells(
        rng::Random.AbstractRNG,
        cols::Int,
        rows::Int,
        n_bands::Int,
        peak::Float32,
        radius::Float64,
    )::Array{Float32, 3}
    rain::Array{Float32, 3} = zeros(Float32, cols, rows, n_bands)
    center::Vector{Float64} = Random.rand(rng, 2)
    xs = collect(1:cols) ./ cols
    ys = collect(1:rows) ./ rows
    for t::Int in 1:n_bands
        center .+= 0.2 .* Random.randn(rng, 2)
        center = clamp.(center, 0.0, 1.0)
        dist_sq = (xs .- center[1]) .^ 2 .+ (ys .- center[2])' .^ 2
        rain[:, :, t] = peak .* Float32.(exp.(-dist_sq ./ radius^2))
    end
    return rain
end
