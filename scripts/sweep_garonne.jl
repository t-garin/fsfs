import CSV
import DataFrames
import FSFS
include(joinpath(@__DIR__, "..", "garonne_1875.jl"))

summary::DataFrames.DataFrame = sweep_peak_flux()
summary_path::String = joinpath(garonne_1875_config().outdir, "sweep", "summary.csv")
CSV.write(summary_path, summary)
println(summary)
