import Agents
import DocStringExtensions: TYPEDFIELDS
import Rasters

"""
    Model

The shared model properties carried by every agent.

# Fields
$(TYPEDFIELDS)
"""
struct Model
    temporal_resolution::Float64
    vision_range::Float64
    flood::Rasters.RasterStack
    flood_times::Vector{Float64}
    depth_field::Matrix{Float32}
    xspeed_field::Matrix{Float32}
    yspeed_field::Matrix{Float32}
    flood_threshold::Float32
    wet_mask::BitMatrix
    water_in_view::BitMatrix
    first_flood_time::Matrix{Float64}
    warning::NamedTuple
    pathfinder::Agents.Pathfinding.AStar
    buildings::AbstractMatrix{Bool}
    extraction_points::BitMatrix
    extraction_in_view::BitMatrix
    vision_radius::Int
    cell_size::Float64
    speed::Float64
    low_risk_perception::Float64
    death_depth::Float64
    death_time::Float64
    max_agents_per_cell::Float64
    penalty_walk_in_water::Int
    rescue_spawn_time::Float64
    rescue_cells::Vector{Tuple{Int, Int}}
    n_rescue::Int
    rescue_spawned::Ref{Bool}
    metrics::NamedTuple
end

"""
    SlopePenalty{D}

A pathfinding cost metric that adds depth and elevation penalties.

# Fields
$(TYPEDFIELDS)
"""
struct SlopePenalty{D} <: Agents.Pathfinding.CostMetric{D}
    base_metric::Agents.Pathfinding.CostMetric{D}
    depth_penalty::Matrix{Int}
    dem::Matrix{Float32}
    penalty_per_elevation::Int
end

function Agents.Pathfinding.delta_cost(
        pathfinder::Agents.Pathfinding.GridPathfinder{D},
        metric::SlopePenalty{D},
        from::Dims{D},
        to::Dims{D},
    ) where {D}
    @inbounds begin
        base = Agents.Pathfinding.delta_cost(pathfinder, metric.base_metric, from, to)
        depth = abs(metric.depth_penalty[from[1], from[2]] - metric.depth_penalty[to[1], to[2]])
        climb = metric.penalty_per_elevation * max(0, metric.dem[to[1], to[2]] - metric.dem[from[1], from[2]])
        return base + depth + round(Int, climb)
    end
end

"""
Dilate a mask by a square structuring element of the given radius.

# Returns
The dilated mask.
"""
function box_dilation(mask::BitMatrix, radius::Int)::BitMatrix
    dilated = falses(size(mask))
    for idx in findall(mask)
        for dc in -radius:radius, dr in -radius:radius
            col = idx[1] + dc
            row = idx[2] + dr
            checkbounds(Bool, dilated, col, row) && (dilated[col, row] = true)
        end
    end
    return dilated
end

"""
First time each cell exceeds the flood-depth threshold.

# Arguments
- `stack::Rasters.RasterStack`: flood raster stack.
- `times::Vector{Float64}`: band times.
- `threshold::Float32`: depth threshold in meters.

# Returns
A `(cols, rows)` `Float64` matrix with the arrival time per cell, `Inf` for
cells that never flood.
"""
function first_flood_times(
        stack::Rasters.RasterStack,
        times::Vector{Float64},
        threshold::Float32,
    )::Matrix{Float64}
    cols, rows, _ = size(stack[:depth])
    first_time = fill(Inf, cols, rows)
    seen = falses(cols, rows)
    for t in 1:length(times)
        wet = parent(stack[:depth])[:, :, t] .> threshold
        newly_wet = .!seen .& wet
        first_time[newly_wet] .= times[t]
        seen .= seen .| wet
    end
    return first_time
end

"""
Assemble the warning options from a simulation config.

# Arguments
- `config::NamedTuple`: simulation options.

# Returns
A `NamedTuple` with `lead_time`, `compliance` and `response_delay`.
"""
function warning_config(config::NamedTuple)::NamedTuple
    return (
        lead_time = get(config, :warning_lead_time, 0.0),
        compliance = get(config, :warning_compliance, 1.0),
        response_delay = get(config, :warning_response_delay, 0.0),
    )
end

"""
Build the flood-evacuation agent-based model.

# Arguments
- `stack::Rasters.RasterStack`: flood raster stack.
- `dem::Matrix{Float32}`: elevation matrix.
- `buildings::AbstractMatrix{Bool}`: building mask.
- `population::Union{Matrix{Float32}, Nothing}`: population density.
- `config::NamedTuple`: simulation options.
- `flooded::BitMatrix`: flooded-cell mask.

# Returns
The built `Agents.StandardABM`.
"""
function build_model(
        stack::Rasters.RasterStack,
        dem::Matrix{Float32},
        buildings::AbstractMatrix{Bool},
        population::Union{Matrix{Float32}, Nothing},
        config::NamedTuple,
        flooded::BitMatrix,
    )
    space, pathfinder = build_flood_space(
        stack,
        dem;
        buildings,
        penalty_per_elevation = config.penalty_per_elevation,
    )
    cell_size = raster_cell_size(stack)
    cols, rows, _ = size(stack[:depth])

    function n_safe(model::Agents.ABM)::Int
        return count(a -> a.status === :safe, Agents.allagents(model))
    end

    function n_danger(model::Agents.ABM)::Int
        return count(a -> a.status === :danger, Agents.allagents(model))
    end

    function n_dead(model::Agents.ABM)::Int
        return count(a -> a.status === :dead, Agents.allagents(model))
    end

    metrics = (n_safe = n_safe, n_danger = n_danger, n_dead = n_dead)
    counts::NamedTuple = agent_counts(config, population, flooded)
    rescue_cells::Vector{Tuple{Int, Int}} =
        flooded_rescue_cells(pathfinder.walkmap, flooded)
    extraction_points::BitMatrix = get_extraction_points(
        buildings,
        pathfinder.walkmap,
        config.rng,
        config.entrance_ratio,
    )
    vision_radius::Int = max(1, ceil(Int, config.vision_range / cell_size))
    flood_times::Vector{Float64} = collect(Rasters.lookup(stack, Rasters.Ti))
    properties = Model(
        config.temporal_resolution,
        config.vision_range,
        stack,
        flood_times,
        zeros(Float32, cols, rows),
        zeros(Float32, cols, rows),
        zeros(Float32, cols, rows),
        Float32(config.flood_threshold),
        falses(cols, rows),
        falses(cols, rows),
        first_flood_times(stack, flood_times, Float32(config.flood_threshold)),
        warning_config(config),
        pathfinder,
        buildings,
        extraction_points,
        box_dilation(extraction_points, vision_radius),
        vision_radius,
        cell_size,
        config.speed,
        config.low_risk_perception,
        config.death_depth,
        config.death_time,
        config.max_crowd_density * cell_size^2,
        config.penalty_walk_in_water,
        config.rescue_spawn_time,
        rescue_cells,
        counts.n_rescue,
        Ref(false),
        metrics,
    )
    model = Agents.StandardABM(
        FloodAgent,
        space;
        properties,
        scheduler = Agents.Schedulers.Randomly(),
        agent_step! = agent_step!,
        model_step! = model_step!,
        agents_first = false,
        rng = config.rng,
    )
    add_initial_agents!(
        model,
        counts.n_agents - counts.n_rescue;
        population,
        flooded,
    )
    return model
end

"""
Compute the number of agents and rescue agents from the population.

# Arguments
- `config::NamedTuple`: simulation options.
- `population::Union{Matrix{Float32}, Nothing}`: population density.
- `flooded::BitMatrix`: flooded-cell mask.

# Returns
A `NamedTuple` with `n_agents` and `n_rescue`.
"""
function agent_counts(
        config::NamedTuple,
        population::Union{Matrix{Float32}, Nothing},
        flooded::BitMatrix,
    )::NamedTuple
    population === nothing &&
        error("a population raster is required to size the agent population")
    flooded_population::Float32 = sum(population[flooded])
    total::Float32 = flooded_population > 0 ? flooded_population : sum(population)
    n_agents::Int = max(1, round(Int, total * config.population_ratio))
    n_rescue::Int = max(1, round(Int, n_agents * config.rescue_ratio))
    n_rescue = min(n_rescue, n_agents - 1)
    return (n_agents = n_agents, n_rescue = n_rescue)
end

"""
Cell size in meters derived from the raster X lookup.

# Returns
The cell size as a `Float64`.
"""
function raster_cell_size(stack::Rasters.RasterStack)::Float64
    xs = collect(Rasters.lookup(stack, Rasters.X))
    return Float64(abs(xs[2] - xs[1]))
end

"""
Build the grid space and A* pathfinder for the model.

# Arguments
- `stack::Rasters.RasterStack`: flood raster stack.
- `dem::Matrix{Float32}`: elevation matrix.
- `buildings::AbstractMatrix{Bool}`: building mask.
- `penalty_per_elevation::Int`: climb penalty per meter of elevation.

# Returns
A `(space, pathfinder)` tuple.
"""
function build_flood_space(
        stack::Rasters.RasterStack,
        dem::Matrix{Float32};
        buildings::AbstractMatrix{Bool},
        penalty_per_elevation::Int = 0,
    )::Tuple{Agents.GridSpace, Agents.Pathfinding.AStar}
    cols, rows, _ = size(stack[:depth])
    space = Agents.GridSpace((cols, rows); periodic = false)
    walkmap::BitMatrix = .!buildings
    cost_metric = SlopePenalty{2}(
        Agents.Pathfinding.DirectDistance{2}(),
        zeros(Int, cols, rows),
        dem,
        penalty_per_elevation,
    )
    pathfinder = Agents.Pathfinding.AStar(space; walkmap, cost_metric)
    return (space, pathfinder)
end
