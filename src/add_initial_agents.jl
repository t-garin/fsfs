import Agents
import Rasters
import Random

"""
Plan a civilian's warning-based evacuation.

The warning reaches the cell `lead_time` seconds before its first flood; the
agent starts evacuating after a uniform response delay, with probability
scaled by its risk perception.

# Arguments
- `model::Agents.ABM`: the simulation model.
- `pos::Tuple{Int, Int}`: spawn cell.
- `risk_perception::Float64`: the agent's risk perception.

# Returns
A `(evacuate_at, will_evacuate)` tuple; `(Inf, false)` without a warning.
"""
function warning_plan(
        model::Agents.ABM,
        pos::Tuple{Int, Int},
        risk_perception::Float64,
    )::Tuple{Float64, Bool}
    lead_time = model.warning.lead_time
    first_time = model.first_flood_time[pos...]
    (lead_time <= 0 || !isfinite(first_time)) && return (Inf, false)
    evacuate_at = max(0.0, first_time - lead_time) + rand(Agents.abmrng(model)) * model.warning.response_delay
    will_evacuate = rand(Agents.abmrng(model)) < model.warning.compliance * risk_perception
    return (evacuate_at, will_evacuate)
end

"""
Create and place a single agent at `pos`.

# Arguments
- `model::Agents.ABM`: the simulation model.
- `role::Symbol`: agent role (`:civilian` or `:rescue`).
- `pos::Tuple{Int, Int}`: cell to place the agent at.
- `t::Float64`: initial time used to assess flood risk.

# Returns
The created `FloodAgent`.
"""
function _add_agent!(
        model::Agents.ABM,
        role::Symbol,
        pos::Tuple{Int, Int},
        t::Float64 = 0.0,
    )::FloodAgent
    status = risk_level(model, t, pos...)
    risk_perception = rand(Agents.abmrng(model))
    vulnerability_factor = rand(Agents.abmrng(model))
    evacuate_at, will_evacuate = warning_plan(model, pos, risk_perception)
    agent = FloodAgent(
        model,
        pos,
        role,
        status,
        risk_perception,
        vulnerability_factor,
        0.0,
        false,
        false,
        will_evacuate,
        evacuate_at,
        Int[],
        nothing,
        :wait,
    )
    Agents.add_agent!(agent, pos, model)
    return agent
end

"""
Select walkable, populated and flooded cells for civilian spawning.

# Arguments
- `walkable::Vector{Tuple{Int, Int}}`: walkable cells.
- `population::Matrix{Float32}`: population density.
- `flooded::BitMatrix`: flooded-cell mask.

# Returns
A `Vector` of cell coordinates, falling back to the whole populated map.
"""
function populated_cells(
        walkable::Vector{Tuple{Int, Int}},
        population::Matrix{Float32},
        flooded::BitMatrix,
    )::Vector{Tuple{Int, Int}}
    cells::Vector{Tuple{Int, Int}} =
        [(c, r) for (c, r) in walkable if population[c, r] > 0 && flooded[c, r]]
    isempty(cells) || return cells
    @warn "no populated cells in the flooded area; spawning civilians over the whole map"
    return [(c, r) for (c, r) in walkable if population[c, r] > 0]
end

"""
Build a population-weighted spawn sampler over the flooded area.

# Arguments
- `model::Agents.ABM`: the simulation model.
- `population::Union{Matrix{Float32}, Nothing}`: population density.
- `flooded::BitMatrix`: flooded-cell mask.

# Returns
A `NamedTuple` with `cells` and `cumulative` weights, or `nothing`.
"""
function build_spawn_sampler(
        model::Agents.ABM,
        population::Union{Matrix{Float32}, Nothing},
        flooded::BitMatrix,
    )::Union{NamedTuple, Nothing}
    population === nothing && return nothing
    walkmap::BitMatrix = model.pathfinder.walkmap
    size(population) == size(walkmap) || return nothing
    walkable::Vector{Tuple{Int, Int}} =
        [Tuple(ix.I) for ix in CartesianIndices(walkmap) if walkmap[ix]]
    populated::Vector{Tuple{Int, Int}} = populated_cells(walkable, population, flooded)
    isempty(populated) && return nothing
    weights::Vector{Float64} = [Float64(population[c, r]) for (c, r) in populated]
    return (cells = populated, cumulative = cumsum(weights))
end

"""
Draw a cell from a cumulative-weight spawn sampler.

# Arguments
- `rng::Random.AbstractRNG`: random number generator.
- `sampler::NamedTuple`: sampler with `cells` and `cumulative`.

# Returns
A randomly chosen cell.
"""
function weighted_walkable(rng::Random.AbstractRNG, sampler::NamedTuple)::Tuple{Int, Int}
    total::Float64 = sampler.cumulative[end]
    index::Int = searchsortedfirst(sampler.cumulative, rand(rng) * total)
    return sampler.cells[index]
end

"""
Pick a random spawn position, weighted when a sampler is available.

# Arguments
- `model::Agents.ABM`: the simulation model.
- `sampler::Union{NamedTuple, Nothing}`: optional weighted sampler.

# Returns
A cell coordinate.
"""
function random_spawn_pos(model::Agents.ABM, sampler::Union{NamedTuple, Nothing})::Tuple{Int, Int}
    sampler === nothing && return Agents.Pathfinding.random_walkable(model, model.pathfinder)
    return weighted_walkable(Agents.abmrng(model), sampler)
end

"""
Select walkable, flooded cells as rescue spawn positions.

# Returns
A `Vector` of cell coordinates.
"""
function flooded_rescue_cells(
        walkmap::BitMatrix,
        flooded::BitMatrix,
    )::Vector{Tuple{Int, Int}}
    cells::Vector{Tuple{Int, Int}} =
        [Tuple(ix.I) for ix in CartesianIndices(walkmap) if walkmap[ix] && flooded[ix]]
    isempty(cells) || return cells
    @warn "no walkable cells in the flooded area; spawning rescue over the whole map"
    return [Tuple(ix.I) for ix in CartesianIndices(walkmap) if walkmap[ix]]
end

"""
Spawn the initial civilian population into the model.

# Arguments
- `model::Agents.ABM`: the simulation model.
- `n_civilians::Int`: number of civilians to spawn.
- `population::Union{Matrix{Float32}, Nothing}`: population density.
- `flooded::BitMatrix`: flooded-cell mask.

# Returns
The mutated `model`.
"""
function add_initial_agents!(
        model::Agents.ABM,
        n_civilians::Int;
        population::Union{Matrix{Float32}, Nothing},
        flooded::BitMatrix,
    )
    sampler::Union{NamedTuple, Nothing} = build_spawn_sampler(model, population, flooded)
    for _ in 1:n_civilians
        _add_agent!(model, :civilian, random_spawn_pos(model, sampler))
    end
    return model
end

"""
Spawn the rescue agents at the current time.

# Returns
The mutated `model`.
"""
function spawn_rescue!(model::Agents.ABM)
    for _ in 1:model.n_rescue
        _add_agent!(model, :rescue, rand(Agents.abmrng(model), model.rescue_cells), current_time(model))
    end
    model.rescue_spawned[] = true
    return model
end

"""
Interpolate the flood depth at a cell and time.

# Arguments
- `stack::Rasters.RasterStack`: flood raster stack.
- `times::Vector{Float64}`: band times.
- `t::Float64`: target time.
- `col::Int`, `row::Int`: cell coordinates.

# Returns
The depth as a `Float32`.
"""
function depth_at(
        stack::Rasters.RasterStack,
        times::Vector{Float64},
        t::Float64,
        col::Int,
        row::Int,
    )::Float32
    cols::Int, rows::Int, _ = size(stack[:depth])
    col = clamp(col, 1, cols)
    row = clamp(row, 1, rows)
    idx, frac = interp_factors(times, t)
    field = parent(stack[:depth])
    return (1 - frac) * field[col, row, idx] + frac * field[col, row, idx + 1]
end

"""
Classify a cell as `:safe` or `:danger` at a given time.

# Returns
`:danger` when the depth exceeds `death_depth`, otherwise `:safe`.
"""
function risk_level(model, t::Float64, col::Int, row::Int)::Symbol
    return depth_at(model.flood, model.flood_times, t, col, row) > model.death_depth ?
        :danger : :safe
end
