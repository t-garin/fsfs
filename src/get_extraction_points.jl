import Random

const FOUR_NEIGHBORS = ((1, 0), (-1, 0), (0, 1), (0, -1))

"""
Yield the four orthogonal neighbor indices of a cell.
"""
function orthogonal_neighbors(cell::CartesianIndex{2})
    return (cell + CartesianIndex(dc, dr) for (dc, dr) in FOUR_NEIGHBORS)
end

"""
Collect the connected component of building cells reachable from `start`.

# Arguments
- `buildings::AbstractMatrix{Bool}`: building mask.
- `start::CartesianIndex{2}`: starting cell.
- `visited::BitMatrix`: visited-cell bookkeeping, mutated in place.

# Returns
A `Vector` of `CartesianIndex` cells in the component.
"""
function building_component(
        buildings::AbstractMatrix{Bool},
        start::CartesianIndex{2},
        visited::BitMatrix,
    )
    component = [start]
    visited[start] = true
    frontier = [start]
    while !isempty(frontier)
        cur = pop!(frontier)
        for nb in orthogonal_neighbors(cur)
            checkbounds(Bool, visited, nb) || continue
            if buildings[nb] && !visited[nb]
                visited[nb] = true
                push!(component, nb)
                push!(frontier, nb)
            end
        end
    end
    return component
end

"""
Find the first walkable cell adjacent to a building component.

# Returns
A `(col, row)` tuple, or `nothing` when the component has no walkable neighbor.
"""
function entrance_of(
        component::Vector{CartesianIndex{2}},
        walkmap::AbstractMatrix{Bool},
    )::Union{Tuple{Int, Int}, Nothing}
    for cell in component
        for nb in orthogonal_neighbors(cell)
            checkbounds(Bool, walkmap, nb) || continue
            walkmap[nb] && return Tuple(nb)
        end
    end
    return nothing
end

"""
Mark one extraction point per building component, with probability `entrance_ratio`.

# Arguments
- `buildings::AbstractMatrix{Bool}`: building mask.
- `walkmap::AbstractMatrix{Bool}`: walkable-cell mask.
- `rng::Random.AbstractRNG`: random number generator.
- `entrance_ratio::Float64`: probability that a component keeps its entrance.

# Returns
A `BitMatrix` with `true` at the chosen extraction cells.
"""
function get_extraction_points(
        buildings::AbstractMatrix{Bool},
        walkmap::AbstractMatrix{Bool},
        rng::Random.AbstractRNG,
        entrance_ratio::Float64,
    )::BitMatrix
    extraction = falses(size(buildings))
    visited = falses(size(buildings))
    for start in CartesianIndices(buildings)
        buildings[start] && !visited[start] || continue
        component = building_component(buildings, start, visited)
        rand(rng) <= entrance_ratio || continue
        entrance = entrance_of(component, walkmap)
        entrance === nothing || (extraction[entrance...] = true)
    end
    return extraction
end
