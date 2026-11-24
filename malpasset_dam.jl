import FSFS

"""
    malpasset_config()

Reproduces the 2 December 1959 Malpasset Dam breach. The dam sat at
43.5120778°N, 6.7565°E on the Reyran river, north of Fréjus. Every flood
parameter below is anchored to the historical record; quoted text is from
Wikipedia's "Malpasset Dam" article.

## Domain

bbox = (6.70, 43.38, 6.82, 43.54). The dam is at "43°30'43.48″N 6°45'23.40″E".
The flood wave, "destroying two small villages, Malpasset and Bozon, the
highway construction site, and in 20 minutes, still standing 3 m high,
reaching Fréjus", ended with "water flooding the western half of Fréjus and
finally reaching the sea". The bbox therefore spans the dam, the Reyran
valley, Fréjus and the coast (~10 km * ~18 km).

## Resolution

spatial_resolution = 30 m keeps the ~190k-cell corridor tractable for Torrent
and the ABM. temporal_resolution = 60 s over n_steps = 120 (2 hours) brackets
the event: the wave reached Fréjus "in 20 minutes" and the reservoir drained
within the hour ("with a discharge rate of 40 m3/s, it was not enough to empty
the reservoir in time" — the breach emptied it far faster).

## Breach geometry

"The dam was 222 m (728 ft) in width and 66 m (217 ft) high". "The entire wall
then collapsed with only a few blocks remaining on the right bank."

- breach_width_top = 222, breach_width_bottom = 180: the breach spans nearly
  the full crest; Torrent requires a trapezoid (bottom < top).
- dam_height_initial = 66, dam_height_final = 0: "66 m high" with total
  collapse reducing the dam in the breach to nothing.
- failure_period = 300 s: the collapse was sudden ("The dam was breached at
  21:13 on 2 December 1959"); 5 minutes is the fastest physically meaningful
  linear breach at a 60 s time step.

## Reservoir

- reservoir_volume_initial = 5.0e7 m³: the dam was built "to store 50 million
  cubic metres of water".
- reservoir_surface_area = 7.6e5 m²: Torrent's rectangular-bathymetry depth
  curve gives a full-pool depth of ~65.8 m, matching the account that "The
  water level in the dam was only 28 cm (11 in) away from the edge" of the
  66 m dam.

## Rain

peak = 100 mm/h represents the storm that caused the failure. "Between 19
November and 2 December, 50 cm (20 in) of rain fell, with 13 cm (5.1 in) in
24 hours before the breach"; the listed cause was "Excess water level due to
heavy rainfall". (Torrent's precipitation is in mm/h, so the 24 h average of
5.4 mm/h is scaled up to a Mediterranean downpour peak.)

## Population

population = (iso3 = "FRA", year = 2020): WorldPop only covers 2000-2020, so
the 1959 valley population is approximated with present-day France and agents
are spawned proportionally to it. The historical benchmark: "The death toll of
the dam breach was reported as 423".
"""
function malpasset_config(; data_dir::String = FSFS.FSFS_DATA_DIR)::NamedTuple
    return (
        bbox=(6.70, 43.38, 6.82, 43.54),
        spatial_resolution=30.0,
        dem_zoom_level=12,
        temporal_resolution=60.0,
        n_steps=120,
        flood_threshold=0.01f0,
        speed=1.4,
        low_risk_perception=0.3,
        death_depth=1.65,
        death_time=300.0,
        max_crowd_density=6,
        entrance_ratio=0.1,
        penalty_walk_in_water=10,
        penalty_per_elevation=10,
        vision_range=100.0,
        population=(iso3="FRA", year=2020),
        population_ratio=1,
        rescue_ratio=0.01,
        warning_compliance=0.9,
        warning_response_delay=60.0,
        n_sources=500,
        rivulet_thickness=0.1,
        rivulet_length=10,
        default_manning=0.018f0,
        manning=FSFS.DEFAULT_MANNING,
        data_dir=data_dir,
        outdir=joinpath(data_dir, "sim_out", "malpasset"),
        rain=(peak=100.0f0,),
        river_source=nothing,
        dam_failure=(
            lat=43.5120778,
            lon=6.7565,
            breach_width_top=222.0,
            breach_width_bottom=180.0,
            reservoir_volume_initial=5.0e7,
            reservoir_surface_area=7.6e5,
            dam_height_initial=66.0,
            dam_height_final=0.0,
            failure_period=300.0,
        ),
    )
end

function sweep_dam_height_final()
    config = merge(malpasset_config(), (seed = 1312,))
    values = collect(range(config.dam_failure.dam_height_initial, 0.0; length=10))
    return FSFS.sweep_parameter(
        config,
        (:dam_failure, :dam_height_final),
        values;
        outdir_root=joinpath(config.outdir, "sweep"),
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = sweep_dam_height_final()
    println(summary)
end
