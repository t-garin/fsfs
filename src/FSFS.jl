module FSFS

import DocStringExtensions: @template, SIGNATURES, DOCSTRING

@template (FUNCTIONS, METHODS, MACROS) =
"""
$(SIGNATURES)
$(DOCSTRING)
"""

include("agent_step.jl")
include("get_extraction_points.jl")
include("utils.jl")
include("get_rain.jl")
include("get_dem.jl")
include("get_population.jl")
include("get_data_from_osm.jl")
include("get_flood_from_torrent.jl")
include("model_step.jl")
include("add_initial_agents.jl")
include("build_model.jl")
include("run_model.jl")

end
