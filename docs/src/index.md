# _Flooding Sims© For Science_

> ⚠️ WARNING: PROTOTYPE ⚠️
>
> Intended as a proof-of-concept and not a production-ready software, use with care (and fun)!

## Overview

`FSFS` is an agent-based flood-evacuation simulation. It couples a
hydrodynamic flood model (driven by [Torrent.jl](https://github.com/DOE-ICoM/Torrent.jl))
with an agent-based population model ([Agents.jl](https://juliadynamics.github.io/Agents.jl/stable/)).

The simulation:

1. Fetches a DEM, population, and OSM-derived land-cover inputs.
2. Runs a flood scenario (rain, river, or dam break).
3. Builds an agent-based model of civilians and rescue agents.
4. Steps the model and writes agent and metrics tables to CSV.

## Quickstart

Run the full pipeline on a scenario:

```julia
import FSFS

config = (
    bbox = (9.90, 51.51, 9.96, 51.55),
    spatial_resolution = 10.0,
    dem_zoom_level = 13,
    temporal_resolution = 60.0,
    n_steps = 10,
    outdir = "/tmp/fsfs_out",
)
result = FSFS.simulate(; config)
```

Or build the model directly from precomputed inputs:

```julia
inputs = FSFS.pipeline_inputs(; config)
model = FSFS.build_model(
    inputs.stack,
    inputs.dem,
    inputs.buildings,
    inputs.population,
    config,
    inputs.flooded,
)
```

## Scenarios

- **Rain**: `rain = (peak = 500.0f0,)`
- **River**: `river_source = (lat = ..., lon = ..., peak_flux = 2000.0)`
- **Dam break**: `dam_failure = (lat = ..., lon = ..., breach_width_top = ..., ...)`

## API

The API reference is split by source file in the navigation bar.
