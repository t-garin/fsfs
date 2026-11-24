import JSON
import MapTiles
import Printf
import Rasters
import Torrent

"""
Assemble depth and velocity snapshots into a flood `RasterStack`.

# Arguments
- `outdir::String`: directory containing the Torrent snapshots.
- `dem::Rasters.Raster`: raster defining the grid.
- `n_steps::Int`: number of time steps.
- `temporal_resolution::Float64`: seconds per step.

# Returns
A `RasterStack` with `depth`, `xspeed` and `yspeed` layers.
"""
function load_flood(
        outdir::String,
        dem::Rasters.Raster,
        n_steps::Int,
        temporal_resolution::Float64,
    )::Rasters.RasterStack
    cols::Int, rows::Int = size(dem)
    depth = load_field_snapshots(outdir, cols, rows, n_steps, "depth")
    xspeed = load_field_snapshots(outdir, cols, rows, n_steps, "ux")
    yspeed = load_field_snapshots(outdir, cols, rows, n_steps, "uy")
    dims::Tuple = (
        Rasters.X(Rasters.lookup(dem, Rasters.X)),
        Rasters.Y(Rasters.lookup(dem, Rasters.Y)),
        Rasters.Ti(temporal_resolution .* (1:n_steps)),
    )
    layer(values::Array{Float32, 3})::Rasters.Raster =
        Rasters.Raster(values, dims; crs = Rasters.EPSG(3857))
    return Rasters.RasterStack(
        (
            depth = layer(depth),
            xspeed = layer(xspeed),
            yspeed = layer(yspeed),
        )
    )
end

"""
Load a sequence of per-step snapshot rasters into a 3-D array.

# Arguments
- `outdir::String`: directory containing the snapshots.
- `cols::Int`, `rows::Int`: grid dimensions.
- `n_steps::Int`: number of time steps.
- `file_prefix::String`: snapshot file prefix.

# Returns
A `(cols, rows, n_steps)` `Float32` array.
"""
function load_field_snapshots(
        outdir::String,
        cols::Int,
        rows::Int,
        n_steps::Int,
        file_prefix::String,
    )::Array{Float32, 3}
    field::Array{Float32, 3} = zeros(Float32, cols, rows, n_steps)
    for t::Int in 1:n_steps
        snapshot_tag::String = Printf.@sprintf("001-%05d", t)
        field[:, :, t] = Float32.(
            coalesce.(
                read(Rasters.Raster(joinpath(outdir, "$file_prefix-$snapshot_tag.tif"))),
                0.0f0,
            ),
        )
    end
    return field
end

"""
Build the Torrent `rain-multiband-geotiff` config section.

# Arguments
- `config::NamedTuple`: simulation options.
- `rain::String`: path to the rain GeoTIFF.
- `n_rain_bands::Int`: number of rain bands.

# Returns
A `Dict` ready to merge into the Torrent config.
"""
function rain_section(config::NamedTuple, rain::String, n_rain_bands::Int)::Dict{String, Any}
    return Dict{String, Any}(
        "rain-multiband-geotiff" => Dict(
            "filename" => rain,
            "min-index" => 1,
            "max-index" => n_rain_bands,
            "band-interval-seconds" => config.temporal_resolution,
        ),
    )
end

"""
Project a lon/lat point to Web Mercator.

# Arguments
- `lat::Float64`, `lon::Float64`: geographic coordinates.

# Returns
A `(x, y)` tuple in Web Mercator.
"""
function project_web_mercator(lat::Float64, lon::Float64)::Tuple{Float64, Float64}
    x::Float64, y::Float64 = MapTiles.project(
        (lon, lat),
        MapTiles.WGS84(),
        MapTiles.WebMercator(),
    )
    return (y, x)
end

"""
Write a Torrent river-source CSV with an asymmetric Gaussian flux time series.

The flood event sits on top of a constant base flow: a fast rise (width
`n_steps / 10`) to the peak at `0.3 n_steps`, then a slow recession (width
`n_steps / 5`) back to the base flow. Each limb is normalized so the series
is exactly `base_flux` at the first and last time steps.

# Arguments
- `river_source::NamedTuple`: river source parameters; requires `lat`,
  `lon`, `peak_flux` and `base_flux`.
- `outdir::String`: directory to write into.
- `n_steps::Int`: number of time steps.

# Returns
The path of the written CSV.
"""
function write_river_sources(
        river_source::NamedTuple,
        outdir::String,
        n_steps::Int,
    )::String
    lat::Float64, lon::Float64 = project_web_mercator(river_source.lat, river_source.lon)
    t_peak::Float64 = round(0.3 * n_steps)
    t::Vector{Float64} = collect(1.0:n_steps)
    rise::Vector{Float64} = normalized_gaussian_lobe(t, t_peak, n_steps / 10, 1.0)
    fall::Vector{Float64} = normalized_gaussian_lobe(t, t_peak, n_steps / 5, Float64(n_steps))
    bump::Vector{Float64} = ifelse.(t .<= t_peak, rise, fall)
    fluxes::Vector{Float64} =
        river_source.base_flux .+ (river_source.peak_flux - river_source.base_flux) .* bump
    path::String = joinpath(outdir, "river-sources.csv")
    open(path, "w") do io
        println(io, join((lat, lon, fluxes...), ","))
    end
    return path
end

"""
Normalize a Gaussian lobe to 0 at a boundary time step and 1 at the peak.

# Arguments
- `t::Vector{Float64}`: time steps.
- `t_peak::Float64`: peak time step.
- `width::Float64`: lobe width in time steps.
- `boundary::Float64`: boundary time step; the lobe is 0 there.

# Returns
The normalized lobe values, 0 at `boundary` and 1 at `t_peak`.
"""
function normalized_gaussian_lobe(
        t::Vector{Float64},
        t_peak::Float64,
        width::Float64,
        boundary::Float64,
    )::Vector{Float64}
    g::Vector{Float64} = exp.(-0.5 .* ((t .- t_peak) ./ width) .^ 2)
    c::Float64 = exp(-0.5 .* ((boundary - t_peak) ./ width) .^ 2)
    return (g .- c) ./ (1.0 - c)
end

"""
Build the Torrent `rain-nwm` config section for a river source.

# Arguments
- `config::NamedTuple`: simulation options.

# Returns
A `Dict`, or an empty `Dict` when no river source is configured.
"""
function river_section(config::NamedTuple)::Dict{String, Any}
    config.river_source === nothing && return Dict{String, Any}()
    return Dict{String, Any}(
        "rain-nwm" => Dict(
            "filename" =>
                write_river_sources(config.river_source, config.outdir, config.n_steps),
            "flux-interval-seconds" => config.temporal_resolution,
        ),
    )
end

"""
Build the Torrent `dam-failure` config section.

# Arguments
- `config::NamedTuple`: simulation options.

# Returns
A `Dict`, or an empty `Dict` when no dam failure is configured.
"""
function dam_section(config::NamedTuple)::Dict{String, Any}
    config.dam_failure === nothing && return Dict{String, Any}()
    dam::NamedTuple = config.dam_failure
    lat::Float64, lon::Float64 = project_web_mercator(dam.lat, dam.lon)
    return Dict{String, Any}(
        "dam-failure" => Dict(
            "latitude" => lat,
            "longitude" => lon,
            "breach-width-top" => dam.breach_width_top,
            "breach-width-bottom" => dam.breach_width_bottom,
            "reservoir-volume-initial" => dam.reservoir_volume_initial,
            "reservoir-depth-curve" => Float64(dam.reservoir_surface_area),
            "dam-height-initial" => dam.dam_height_initial,
            "dam-height-final" => dam.dam_height_final,
            "failure-period" => dam.failure_period,
        ),
    )
end

"""
Assemble and write the Torrent config JSON.

# Arguments
- `config::NamedTuple`: simulation options.
- `dem::String`: path to the DEM GeoTIFF.
- `rain::Union{String, Nothing}`: path to the rain GeoTIFF, or `nothing`.
- `manning::String`: path to the Manning GeoTIFF.

# Returns
The path of the written JSON file.
"""
function write_config(
        config::NamedTuple,
        dem::String,
        rain::Union{String, Nothing},
        manning::String,
    )::String
    n_rain_bands::Int = config.n_steps + 1
    torrent_config::Dict{String, Any} = Dict{String, Any}(
        "rivulet-thickness" => config.rivulet_thickness,
        "rivulet-length" => config.rivulet_length,
        "time-step-seconds" => config.temporal_resolution,
        "max-steps" => n_rain_bands,
        "save-every-steps" => 1,
        "compute-max-every-steps" => 10,
        "output-directory" => config.outdir * "/",
        "exclude-no-data-cells" => true,
        "num-realizations" => 1,
        "num-sources" => config.n_sources,
        "save-velocity-fields" => true,
        "dem" =>
            Dict("filename" => dem, "units" => "meters", "enforce-sea-level" => true),
        "manning-coef" => manning,
    )
    if rain !== nothing && config.river_source === nothing
        merge!(torrent_config, rain_section(config, rain, n_rain_bands))
    end
    merge!(torrent_config, river_section(config))
    merge!(torrent_config, dam_section(config))
    path::String = joinpath(config.outdir, "config.json")
    open(path, "w") do io
        JSON.print(io, torrent_config, 2)
    end
    return path
end

"""
Fetch the DEM, rain and Manning inputs required to run Torrent.

# Arguments
- `config::NamedTuple`: simulation options.
- `cache_dir::String`: directory to cache the inputs.
- `n_rain_bands::Int`: number of rain bands.

# Returns
A `NamedTuple` with `dem`, `rain` and `manning_path`.
"""
function fetch_flood_inputs(
        config::NamedTuple,
        cache_dir::String,
        n_rain_bands::Int,
    )::NamedTuple
    t0 = time()
    @info "flood: fetching DEM" cache_dir
    dem::Rasters.Raster = fetch_dem(
        config.bbox;
        dem_zoom_level = config.dem_zoom_level,
        spatial_resolution = config.spatial_resolution,
        cache_dir,
    )
    rain::Union{String, Nothing} = if config.rain === nothing
        nothing
    else
        @info "flood: synthetic rain" elapsed_s = round(time() - t0; digits = 1)
        synthetic_rain(
            dem;
            n_bands = n_rain_bands,
            peak = config.rain.peak,
            cache_dir,
        )
    end
    @info "flood: OSM manning" elapsed_s = round(time() - t0; digits = 1)
    manning_path::String = manning_from_osm(
        config.bbox,
        dem;
        cache_dir,
        manning = config.manning,
        default_manning = config.default_manning,
    )
    return (dem = dem, rain = rain, manning_path = manning_path)
end

"""
Run Torrent and load the resulting flood field.

# Arguments
- `config::NamedTuple`: simulation options.
- `cache_dir::String`: directory to cache the inputs.

# Returns
The flood `RasterStack`.
"""
function flood(config::NamedTuple, cache_dir::String)::Rasters.RasterStack
    mkpath(config.outdir)
    t0 = time()
    n_rain_bands::Int = config.n_steps + 1
    inputs::NamedTuple = fetch_flood_inputs(config, cache_dir, n_rain_bands)
    @info "flood: running Torrent" elapsed_s = round(time() - t0; digits = 1)
    config_path::String = write_config(
        config,
        joinpath(cache_dir, "dem.tif"),
        inputs.rain,
        inputs.manning_path,
    )
    Torrent.torrent(config_path)
    @info "flood: loading snapshots" elapsed_s = round(time() - t0; digits = 1)
    return load_flood(config.outdir, inputs.dem, config.n_steps, config.temporal_resolution)
end
