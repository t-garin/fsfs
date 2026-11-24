import CSV
import DataFrames
import FSFS
include(joinpath(@__DIR__, "..", "malpasset_dam.jl"))
include(joinpath(@__DIR__, "..", "garonne_1875.jl"))

"""
Reference case for the Malpasset warning sweep: full collapse.

# Returns
A `NamedTuple` with the warning-sweep base configuration.
"""
function malpasset_warning_config()::NamedTuple
    config = malpasset_config()
    return merge(
        config,
        (seed = 1312, dam_failure = merge(config.dam_failure, (dam_height_final = 0.0,))),
    )
end

"""
Reference case for the Garonne warning sweep: the 8,000 m³/s flood.

# Returns
A `NamedTuple` with the warning-sweep base configuration.
"""
function garonne_warning_config()::NamedTuple
    return merge(garonne_1875_config(), (seed = 1312,))
end

"""
Run the warning-lead-time sweep for a site and write its summary CSV.

# Arguments
- `target::String`: `"malpasset"` or `"garonne"`.

# Returns
The summary `DataFrame`.
"""
function run_warning_sweep(target::String)::DataFrames.DataFrame
    config::NamedTuple, values::Vector{Float64} = if target == "malpasset"
        (malpasset_warning_config(), collect(range(0.0, 7200.0; length = 10)))
    elseif target == "garonne"
        (garonne_warning_config(), collect(range(0.0, 172800.0; length = 10)))
    else
        error("unknown target: $target")
    end
    outdir_root::String = joinpath(config.outdir, "sweep_warning")
    summary::DataFrames.DataFrame =
        FSFS.sweep_parameter(config, (:warning_lead_time,), values; outdir_root)
    CSV.write(joinpath(outdir_root, "summary.csv"), summary)
    return summary
end

target::String = isempty(ARGS) ? "malpasset" : first(ARGS)
println(run_warning_sweep(target))
