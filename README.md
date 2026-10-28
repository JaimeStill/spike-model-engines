# spike-model-engines

Which engine, llama.cpp or vLLM, serves each of the workstations, the two GB10s and the
Framework's Strix Halo, and is it hosted in a container or on bare metal? This spike measures both
engines' raw capability by model shape, quantization, and concurrency, on gb10-1 (gb10-2 is
reserved for spike-ai-pipeline) and on the Framework, and documents how each is set up,
configured, called, updated, and removed. Its answer is evidence for standards-lab's
`experiment.hosting` intake, which decides the engine strategy `v1.ai.hosting` specifies.

- The engine guides: `docs/engines/` (written by the install tasks).
- The measured results: `docs/findings/` (written by the benchmark tasks).

## The answer

Not answered yet. The spike's `answer` task writes it here.
