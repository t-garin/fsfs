import CSV
import DataFrames
import FSFS
include(joinpath(@__DIR__, "..", "malpasset_dam.jl"))

summary::DataFrames.DataFrame = sweep_dam_height_final()
summary_path::String = joinpath(malpasset_config().outdir, "sweep", "summary.csv")
CSV.write(summary_path, summary)
println(summary)
