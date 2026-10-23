# goal · experiment.hosting.spike-model-engines

- **State:** idle
- **Task:** none
- **Branch:** none

## Tasks

1. [ ] llama-gb10-container
2. [ ] vllm-gb10-container
3. [ ] bench-gb10-container
4. [ ] llama-gb10-native
5. [ ] vllm-gb10-native
6. [ ] llama-strix-rocm
7. [ ] vllm-strix
8. [ ] strix-native
9. [ ] answer

## Decisions

- setup: evidence is six items (install and guides; capability by shape, vision included;
  quantization; concurrency; API surface; container against bare metal); IL6 dropped from the
  spike's scope.
- setup: guided sessions — the architect runs every host step from the docs, the session walks
  each step and records it; experiment-wide, recorded in ai-hosting.md.
- setup: benchmarks planned together in each task's plan round, built and run a step at a time.
- setup: hosts brought current at every session start, replacing the freeze; every result records
  engine version and host stack.
- setup: only same-session cells compare; a later comparison reruns one anchor cell per engine.
- setup: scripts are a minimal `engines-<group>-<verb>` suite behind outpost's small dispatcher,
  only idempotent install, update, and uninstall; rejected omarchy's metadata router as too large.
- setup: one guide directory per engine (README, setup, models, api, update, uninstall); findings
  per benchmark task under docs/findings/.
- setup: llama.cpp tracks its semver releases, running the b-build each names; rejected tracking
  the latest b-build every session.
- setup: engines kept current, not pinned and held.
- setup: load tools GuideLLM 0.8.1 plus llama-bench; rejected `vllm bench serve`, which needs vLLM
  on the laptop and only re-covers GuideLLM's endpoints.
- setup: GB10s first, containers first, then bare metal; the Framework follows, containers plus
  bare metal only where the GB10 results call for it.
- setup: install on both GB10s, benchmark on gb10-1 with a cross-check on gb10-2.
- setup: llama.cpp's ROCm build measured on Strix Halo, through ggml's ROCm image first.
- setup: quantization floor — publisher-evaluated formats, else nothing below Q5_K_M or FP8, and
  Q8_0 or FP8 for embedding, ASR, and dense models under 8B.
- setup: QSFP link already measured in dotfiles; two-node serving stays with spike-model-layout.
- setup: kind code, check shellcheck over tracked scripts, currency over mise tools, no gate, no
  CI; public remote; references spike-model-hosting, personal-agents, dotfiles.

## Pending edits

(none)
