import Agents
import Agents: ABM, GridAgent
import DocStringExtensions: TYPEDFIELDS

"""
    FloodAgent

An agent in the flood-evacuation model, either a civilian or a rescue agent.

# Fields
$(TYPEDFIELDS)
"""
Agents.@agent struct FloodAgent(GridAgent{2})
    # id    <: herited from Agents.GridAgent{2}
    # cell  <: herited from Agents.GridAgent{2}
    role::Symbol
    status::Symbol
    risk_perception::Float64
    vulnerability_factor::Float64
    death_time::Float64
    sees_extraction_point::Bool
    sees_water::Bool
    will_evacuate::Bool
    evacuate_at::Float64
    endangered_ids::Vector{Int}
    destination::Union{Tuple{Int, Int}, Nothing}
    action::Symbol
end

"""
Whether an agent can enter the given cell without overcrowding it.

# Returns
`true` when the cell is below the maximum crowd density.
"""
function can_move_to_cell(col::Int, row::Int, model::Agents.ABM)::Bool
    return length(Agents.ids_in_position((col, row), model)) < model.max_agents_per_cell
end

"""
Find the nearest extraction point by expanding Manhattan rings.

# Arguments
- `model::Agents.ABM`: the simulation model.
- `pos::Tuple{Int, Int}`: origin cell.

# Returns
The nearest safe cell, or `nothing` when none is reachable.
"""
function nearest_safe_cell(model::Agents.ABM, pos::Tuple{Int, Int})::Union{Tuple{Int, Int}, Nothing}
    max_manhattan = size(model.extraction_points, 1) + size(model.extraction_points, 2) - 2
    for r in 1:max_manhattan
        for cell in Agents.nearby_positions(pos, model, r)
            abs(cell[1] - pos[1]) + abs(cell[2] - pos[2]) == r || continue
            model.extraction_points[cell...] && return cell
        end
    end
    return nothing
end

"""
Find the nearest never-flooding walkable cell around `pos`.

An agent that must evacuate heads to the closest cell that never floods, so it
does not wait inside the floodplain.

# Arguments
- `model::Agents.ABM`: the simulation model.
- `pos::Tuple{Int, Int}`: origin cell.

# Returns
The nearest never-flooding walkable cell, or `pos` when it is already safe, or
`nothing` when none exists.
"""
function nearest_refuge(model::Agents.ABM, pos::Tuple{Int, Int})::Union{Tuple{Int, Int}, Nothing}
    !isfinite(model.first_flood_time[pos...]) && return pos
    max_manhattan = size(model.pathfinder.walkmap, 1) + size(model.pathfinder.walkmap, 2) - 2
    for r in 1:max_manhattan
        for cell in Agents.nearby_positions(pos, model, r)
            abs(cell[1] - pos[1]) + abs(cell[2] - pos[2]) == r || continue
            model.pathfinder.walkmap[cell...] && !isfinite(model.first_flood_time[cell...]) && return cell
        end
    end
    return nothing
end

"""
Find the nearest cell satisfying `predicate` around `pos`, ring by ring.

# Arguments
- `predicate::Function`: cell test, takes a `(col, row)` tuple.
- `model::Agents.ABM`: the simulation model.
- `pos::Tuple{Int, Int}`: origin cell.
- `max_radius::Int`: Chebyshev search radius.

# Returns
The nearest matching cell, or `nothing` when none is found.
"""
function nearest_chebyshev_cell(
        predicate::Function,
        model::Agents.ABM,
        pos::Tuple{Int, Int},
        max_radius::Int,
    )::Union{Tuple{Int, Int}, Nothing}
    for r in 1:max_radius
        for cell in Agents.nearby_positions(pos, model, r)
            max(abs(cell[1] - pos[1]), abs(cell[2] - pos[2])) == r || continue
            predicate(cell) && return cell
        end
    end
    return nothing
end

"""
Farthest walkable cell along a ray from `pos` in direction `dir`.

# Arguments
- `model::Agents.ABM`: the simulation model.
- `pos::Tuple{Int, Int}`: origin cell.
- `dir::Tuple{Int, Int}`: unit direction.
- `radius::Int`: ray length in cells.

# Returns
A `(col, row)` tuple, or `nothing` when no cell on the ray is walkable.
"""
function ray_walkable(
        model::Agents.ABM,
        pos::Tuple{Int, Int},
        dir::Tuple{Int, Int},
        radius::Int,
    )::Union{Tuple{Int, Int}, Nothing}
    for t in radius:-1:1
        cell = pos .+ dir .* t
        checkbounds(Bool, model.pathfinder.walkmap, cell...) || continue
        model.pathfinder.walkmap[cell...] && return cell
    end
    return nothing
end

"""
Whether `cell` is a flee reference for an agent standing in `in_water`.

An agent in water targets dry walkable cells; an agent on dry ground targets
wet cells.

# Arguments
- `model::Agents.ABM`: the simulation model.
- `cell::Tuple{Int, Int}`: candidate cell.
- `in_water::Bool`: whether the agent stands in water.

# Returns
`true` when the cell is a valid flee reference.
"""
function is_flee_reference(model::Agents.ABM, cell::Tuple{Int, Int}, in_water::Bool)::Bool
    return in_water ?
        model.pathfinder.walkmap[cell...] && !model.wet_mask[cell...] :
        model.wet_mask[cell...]
end

"""
Pick a destination away from the nearest water, or toward the nearest dry land.

An agent on dry ground flees opposite the nearest wet cell; an agent in water
heads toward the nearest dry walkable cell.

# Returns
A `(col, row)` destination, or `nothing` when no direction is found.
"""
function flee_destination(
        agent::FloodAgent,
        model::Agents.ABM,
    )::Union{Tuple{Int, Int}, Nothing}
    wet = model.wet_mask[agent.pos...]
    reference = nearest_chebyshev_cell(model, agent.pos, model.vision_radius) do cell
        is_flee_reference(model, cell, wet)
    end
    reference === nothing && return nothing
    dir = wet ? sign.(reference .- agent.pos) : sign.(agent.pos .- reference)
    return ray_walkable(model, agent.pos, dir, model.vision_radius)
end

"""
Update an agent's perception of water, extraction points and endangered neighbors.

# Returns
The mutated `agent`.
"""
function perceive!(agent::FloodAgent, model::Agents.ABM)
    agent.sees_water = model.water_in_view[agent.pos...]
    agent.sees_extraction_point = model.extraction_in_view[agent.pos...]
    empty!(agent.endangered_ids)
    for id in Agents.nearby_ids(agent, model, model.vision_radius)
        model[id].status === :danger && push!(agent.endangered_ids, id)
    end
    return agent
end

"""
Update an agent's flood status based on local water depth.

# Returns
`:safe`, `:danger` or `:dead`.
"""
function flood_status!(agent::FloodAgent, model::Agents.ABM)::Symbol
    depth = model.depth_field[agent.pos...]
    if depth <= model.death_depth
        agent.death_time = 0.0
        return :safe
    end
    agent.death_time += model.temporal_resolution
    agent.death_time >= model.death_time && return :dead
    return :danger
end

"""
An agent's effective walking speed in meters per second.

# Returns
The agent's speed as a `Float64`.
"""
function agent_speed(agent::FloodAgent, model::Agents.ABM)::Float64
    return model.speed * (1 - agent.vulnerability_factor)
end

"""
Cells an agent can cover in one time step at a given speed.

# Returns
The number of cells, at least one.
"""
function cells_for_speed(speed::Float64, model::Agents.ABM)::Int
    return max(1, round(Int, speed * model.temporal_resolution / model.cell_size))
end

"""
Cells an agent can cover in one time step.

# Returns
The number of cells, at least one.
"""
function cells_per_step(agent::FloodAgent, model::Agents.ABM)::Int
    return cells_for_speed(agent_speed(agent, model), model)
end

"""
Move an agent to a random adjacent walkable cell.

# Returns
`true` when the agent moved, `false` otherwise.
"""
function move_around!(agent::FloodAgent, model::Agents.ABM)::Bool
    options =
        [
        pos for pos in
            Agents.Pathfinding.nearby_walkable(agent.pos, model, model.pathfinder, 1)
            if can_move_to_cell(pos..., model)
    ]
    isempty(options) && return false
    Agents.move_agent!(agent, rand(Agents.abmrng(model), options), model)
    delete!(model.pathfinder.agent_paths, agent.id)
    return true
end

"""
Move an agent along a planned route toward a destination.

# Arguments
- `agent::FloodAgent`: the agent.
- `destination::Tuple{Int, Int}`: target cell.
- `model::Agents.ABM`: the simulation model.

# Returns
The mutated `agent`.
"""
function move!(agent::FloodAgent, destination::Tuple{Int, Int}, model::Agents.ABM)
    if agent.destination != destination || isempty(agent.id, model.pathfinder)
        Agents.Pathfinding.plan_route!(agent, destination, model.pathfinder)
        agent.destination = destination
    end
    for _ in 1:cells_per_step(agent, model)
        isempty(agent.id, model.pathfinder) && break
        next = first(model.pathfinder.agent_paths[agent.id])
        if can_move_to_cell(next..., model)
            Agents.Pathfinding.move_along_route!(agent, model, model.pathfinder)
        else
            agent.destination = nothing
            move_around!(agent, model)
            break
        end
    end
    return agent
end

"""
Move an agent toward a random walkable cell within vision range.

# Returns
The mutated `agent`.
"""
function move_random!(agent::FloodAgent, model::Agents.ABM)
    radius = model.vision_radius
    walkable =
        collect(Agents.Pathfinding.nearby_walkable(agent.pos, model, model.pathfinder, radius))
    dest =
        isempty(walkable) ? Agents.Pathfinding.random_walkable(model, model.pathfinder) :
        rand(Agents.abmrng(model), walkable)
    return move!(agent, dest, model)
end

"""
Cells covered per step when escorting another agent.

# Arguments
- `agent::FloodAgent`: the escorting agent.
- `target::FloodAgent`: the escorted agent.
- `model::Agents.ABM`: the simulation model.

# Returns
The number of cells, at least one.
"""
function steps_to_escort(agent::FloodAgent, target::FloodAgent, model::Agents.ABM)::Int
    escort_speed = (agent_speed(agent, model) + agent_speed(target, model)) / 2
    return cells_for_speed(escort_speed, model)
end

"""
Move an agent up to `n` cells along its current path.

# Returns
The mutated `agent`.
"""
function move_along_path!(agent::FloodAgent, n::Int, model::Agents.ABM)
    for _ in 1:n
        isempty(agent.id, model.pathfinder) && break
        Agents.Pathfinding.move_along_route!(agent, model, model.pathfinder)
    end
    return agent
end

"""
Escort the nearest endangered agent toward a safe cell.

# Returns
The mutated `agent`.
"""
function help!(agent::FloodAgent, model::Agents.ABM)
    isempty(agent.endangered_ids) && return agent
    target = model[first(agent.endangered_ids)]
    dest = nearest_safe_cell(model, target.pos)
    dest === nothing && return agent
    n = steps_to_escort(agent, target, model)
    Agents.Pathfinding.plan_route!(target, dest, model.pathfinder)
    target.destination = dest
    move_along_path!(target, n, model)
    Agents.Pathfinding.plan_route!(agent, target.pos, model.pathfinder)
    agent.destination = target.pos
    move_along_path!(agent, n, model)
    return agent
end

"""
Whether an agent is idle: dead, or safe with nothing to do.

A safe civilian is busy when water is in view or a warned evacuation is due.

# Returns
`true` when the agent is `:dead`, or `:safe` on dry ground without a pending evacuation.
"""
function is_idle(agent::FloodAgent, model::Agents.ABM)::Bool
    agent.status === :dead && return true
    agent.status === :safe || return false
    return !agent.sees_water && !evacuation_due(agent, model)
end

"""
Whether a warned civilian should start evacuating now.

# Returns
`true` when the agent was warned and the evacuation time has come.
"""
function evacuation_due(agent::FloodAgent, model::Agents.ABM)::Bool
    return agent.will_evacuate && current_time(model) >= agent.evacuate_at
end

"""
Whether an agent should help endangered neighbors.

# Returns
`true` when the agent is low-risk and sees endangered agents.
"""
function wants_to_help(agent::FloodAgent, model::Agents.ABM)::Bool
    return agent.risk_perception < model.low_risk_perception &&
        !isempty(agent.endangered_ids)
end

"""
Displacement in cells from the flood velocity at the agent's position.

The velocity components follow the geographic convention: `xspeed` is
positive eastward and `yspeed` is positive northward. Grid rows increase
southward, so the row displacement is the negated northward component.

# Returns
A `(dcol, drow)` tuple.
"""
function velocity_to_cell_delta(
        xspeed::Real,
        yspeed::Real,
        temporal_resolution::Real,
        cell_size::Real,
    )::Tuple{Int, Int}
    return (
        round(Int, xspeed * temporal_resolution / cell_size),
        -round(Int, yspeed * temporal_resolution / cell_size),
    )
end

"""
Displacement in cells from the flood velocity at the agent's position.

# Returns
A `(dcol, drow)` tuple.
"""
function advection_drift(agent::FloodAgent, model::Agents.ABM)::Tuple{Int, Int}
    return velocity_to_cell_delta(
        model.xspeed_field[agent.pos...],
        model.yspeed_field[agent.pos...],
        model.temporal_resolution,
        model.cell_size,
    )
end

"""
Move an agent by a cell delta when the target is walkable and free.

# Returns
`true` when the agent moved.
"""
function try_move!(agent::FloodAgent, delta::Tuple{Int, Int}, model::Agents.ABM)::Bool
    delta == (0, 0) && return false
    dest = agent.pos .+ delta
    checkbounds(Bool, model.pathfinder.walkmap, dest...) || return false
    model.pathfinder.walkmap[dest...] || return false
    can_move_to_cell(dest..., model) || return false
    Agents.move_agent!(agent, dest, model)
    return true
end

"""
Advect an agent by the local flood velocity when it stands in water.

# Returns
The mutated `agent`.
"""
function advect!(agent::FloodAgent, model::Agents.ABM)
    model.depth_field[agent.pos...] <= 0 && return agent
    drift = advection_drift(agent, model)
    drift == (0, 0) && return agent
    moved = try_move!(agent, drift, model) ||
        try_move!(agent, (drift[1], 0), model) ||
        try_move!(agent, (0, drift[2]), model)
    moved && delete!(model.pathfinder.agent_paths, agent.id)
    return agent
end

"""
Dispatch an agent's decision to its role-specific method.

# Returns
The chosen action as a `Symbol`.
"""
function decide(agent::FloodAgent, model::Agents.ABM)::Symbol
    return decide(Val(agent.role), agent, model)
end

"""
Choose the rescue agent's action for this step.

# Returns
The action to execute this step.
"""
function decide(::Val{:rescue}, agent::FloodAgent, model::Agents.ABM)::Symbol
    agent.destination = nothing
    isempty(agent.endangered_ids) && return :move
    target = model[first(agent.endangered_ids)]
    Agents.chebyshev_distance(agent.pos, target.pos, model) <= 1 && return :help
    agent.destination = target.pos
    return :move
end

"""
Choose the civilian agent's action for this step.

# Returns
The action to execute this step.
"""
function decide(::Val{:civilian}, agent::FloodAgent, model::Agents.ABM)::Symbol
    agent.destination = nothing
    is_idle(agent, model) && return :wait
    wants_to_help(agent, model) && return :help
    if evacuation_due(agent, model)
        refuge = nearest_refuge(model, agent.pos)
        agent.destination = refuge === nothing ? nearest_safe_cell(model, agent.pos) : refuge
    elseif agent.sees_extraction_point
        agent.destination = nearest_safe_cell(model, agent.pos)
    elseif agent.sees_water
        agent.destination = flee_destination(agent, model)
    end
    return :move
end

"""
Execute an agent's `:wait` action.

# Returns
The unchanged `agent`.
"""
function execute!(agent::FloodAgent, ::Val{:wait}, model::Agents.ABM)
    return agent
end

"""
Execute an agent's `:move` action toward its destination, or randomly.

# Returns
The mutated `agent`.
"""
function execute!(agent::FloodAgent, ::Val{:move}, model::Agents.ABM)
    agent.destination === nothing && return move_random!(agent, model)
    return move!(agent, agent.destination, model)
end

"""
Execute an agent's `:help` action.

# Returns
The mutated `agent`.
"""
function execute!(agent::FloodAgent, ::Val{:help}, model::Agents.ABM)
    return help!(agent, model)
end

"""
Advance one agent for a single step.

# Returns
The mutated `agent`.
"""
function agent_step!(agent::FloodAgent, model::Agents.ABM)
    agent.status === :dead && return agent
    agent.status = flood_status!(agent, model)
    agent.status === :dead && return agent
    perceive!(agent, model)
    if agent.role === :civilian && is_idle(agent, model)
        agent.action = :wait
        return agent
    end
    agent.action = decide(agent, model)
    execute!(agent, Val(agent.action), model)
    advect!(agent, model)
    return agent
end
