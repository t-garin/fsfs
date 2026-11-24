import FSFS

data_dir = FSFS.FSFS_DATA_DIR

base_config = (
    bbox = (9.90, 51.51, 9.96, 51.55),
    spatial_resolution = 10.0,
    dem_zoom_level = 13,
    temporal_resolution = 60.0,
    n_steps = 10,
    flood_threshold = 0.01f0,
    speed = 1.4,
    low_risk_perception = 0.3,
    death_depth = 1.65,
    death_time = 300.0,
    max_crowd_density = 6,
    entrance_ratio = 0.1,
    penalty_walk_in_water = 10,
    penalty_per_elevation = 10,
    vision_range = 100.0,
    population = (iso3 = "DEU", year = 2020),
    population_ratio = 1,
    rescue_ratio = 0.1,
    rescue_spawn_time = 300.0,
    n_sources = 500,
    rivulet_thickness = 0.1,
    rivulet_length = 10,
    default_manning = 0.018f0,
    manning = FSFS.DEFAULT_MANNING,
    data_dir = data_dir,
    outdir = joinpath(data_dir, "sim_out"),
    rain = nothing,
    river_source = nothing,
    dam_failure = nothing,
)

rain_config = (
    base_config..., 
    outdir = joinpath(base_config.outdir, "rain"),
    rain = (peak = 500.0f0,)
)

river_config = (
    base_config...,
    outdir = joinpath(base_config.outdir, "river"),
    river_source = (lat = 51.545, lon = 9.93, peak_flux = 2000.0, base_flux = 0.0),
)

dam_config = (
    base_config...,
    outdir = joinpath(base_config.outdir, "dam"),
    rain = (peak = 500.0f0,),
    dam_failure = (
        lat = 51.52,
        lon = 9.92,
        breach_width_top = 60.0,
        breach_width_bottom = 20.0,
        reservoir_volume_initial = 5.0e6,
        reservoir_surface_area = 2.0e5,
        dam_height_initial = 8.0,
        dam_height_final = 3.0,
        failure_period = 3600.0,
    ),
)

for (name, config) in
        ("rain" => rain_config, "river" => river_config, "dam" => dam_config)
    rm(config.outdir; recursive = true, force = true)
    result = FSFS.simulate(; config)
    println(name, ": ", result.metrics)
end
