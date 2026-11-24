# Display this message
help:
	@just --list

# Check src/ formatting with Runic (fails if unformatted)
lint:
	@julia --project=. -m Runic --check src/

# Format src/ in place with Runic
format:
	@julia --project=. -m Runic --inplace src/

[private]
env:
	@julia --project=. -e 'using Pkg; Pkg.resolve(); Pkg.instantiate()'

# Run the hermetic regression test (rain, river, dam break) against the KGO
test: env
	@JULIA_NUM_THREADS=1 julia --project=. test/runtests.jl

# Re-generate test/kgo.json from a fresh run (commit after deliberate changes)
update-kgo: env
	@JULIA_NUM_THREADS=1 julia --project=. test/runtests.jl --update-kgo

# Run the full flood evacuation simulation (fetches DEM, rain, OSM manning, Torrent)
run: env
	@julia --project=. main.jl

plot: env
	@julia --project=. scripts/plot.jl

# Profile the ABM loop for bottlenecks (reuses cached Torrent output)
benchmark: env
	@julia --project=. scripts/benchmark.jl

graph: env
	@julia --project=. -e 'using MermaidCallGraph; mermaid_call_graph()'

# Build the documentation (writes HTML to docs/build)
docs: env graph
	@julia --project=. docs/make.jl
