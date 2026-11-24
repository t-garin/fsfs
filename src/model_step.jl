import Agents
import Rasters

"""
Current simulation time in seconds.

# Returns
The current time as a `Float64`.
"""
function current_time(model::Agents.ABM)::Float64
    return (Agents.abmtime(model) + 1) * model.temporal_resolution
end

"""
Interpolation index and fraction for time `t` in `times`.

# Returns
A `(idx, frac)` tuple with `idx` in `1:length(times) - 1`.
"""
function interp_factors(times::Vector{Float64}, t::Float64)::Tuple{Int, Float32}
    idx = clamp(searchsortedlast(times, t), 1, length(times) - 1)
    frac = clamp(Float32((t - times[idx]) / (times[idx + 1] - times[idx])), 0.0f0, 1.0f0)
    return (idx, frac)
end

"""
Interpolate a flood layer at time `t` into `dest`.

# Arguments
- `dest::Matrix{Float32}`: destination buffer.
- `stack::Rasters.RasterStack`: flood raster stack.
- `times::Vector{Float64}`: band times.
- `t::Float64`: target time.
- `name::Symbol`: layer name (`:depth`, `:xspeed`, `:yspeed`).

# Returns
The mutated `dest`.
"""
function field_grid!(
        dest::Matrix{Float32},
        stack::Rasters.RasterStack,
        times::Vector{Float64},
        t::Float64,
        name::Symbol,
    )
    field = parent(stack[name])
    idx, frac = interp_factors(times, t)
    if frac == 0.0f0
        copyto!(dest, @view field[:, :, idx])
    else
        @views dest .= field[:, :, idx] .* (1 - frac) .+ field[:, :, idx + 1] .* frac
    end
    return dest
end

"""
Update the pathfinder's water-walking penalty from the current depth field.

# Arguments
- `pathfinder::Agents.Pathfinding.AStar`: the model pathfinder.
- `depth_field::Matrix{Float32}`: current water depth.
- `penalty_walk_in_water::Int`: penalty per unit depth.

# Returns
The mutated `pathfinder`.
"""
function update_penalty!(
        pathfinder::Agents.Pathfinding.AStar,
        depth_field::Matrix{Float32},
        penalty_walk_in_water::Int,
    )
    pathfinder.cost_metric.depth_penalty .=
        round.(Int, penalty_walk_in_water .* depth_field)
    return pathfinder
end

"""
Update the wet mask and the water-in-view mask.

The wet mask marks cells currently deeper than the flood threshold; the
water-in-view mask dilates it by the agents' vision radius.

# Arguments
- `model::Agents.ABM`: the simulation model.

# Returns
The mutated `model`.
"""
function update_water_view!(model::Agents.ABM)
    model.wet_mask .= model.depth_field .> model.flood_threshold
    model.water_in_view .= box_dilation(model.wet_mask, model.vision_radius)
    return model
end

"""
Advance the flood fields and spawn rescue agents for one model step.

# Returns
The mutated `model`.
"""
function model_step!(model::Agents.ABM)
    t = current_time(model)
    t >= model.rescue_spawn_time && !model.rescue_spawned[] && spawn_rescue!(model)
    field_grid!(model.depth_field, model.flood, model.flood_times, t, :depth)
    field_grid!(model.xspeed_field, model.flood, model.flood_times, t, :xspeed)
    field_grid!(model.yspeed_field, model.flood, model.flood_times, t, :yspeed)
    update_penalty!(model.pathfinder, model.depth_field, model.penalty_walk_in_water)
    update_water_view!(model)
    return model
end
