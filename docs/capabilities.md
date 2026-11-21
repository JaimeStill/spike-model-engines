# Capabilities and references

This page details the spike's built capabilities and the repositories it reads, behind the map
and the evidence in [`context/README.md`](../context/README.md).

## Capabilities

- **Engine guides:** setup, models, APIs, updates, and uninstall, per engine, under
  `docs/engines/<engine>/`. llama.cpp's and vLLM's are written for the GB10s, and each has
  sections for the Framework.
- **The `engines` suite:** the scripted install, update, and uninstall steps, under `host/`, for
  llama.cpp and vLLM, each in a container (`llama`, `vllm`) and natively (`llama-native`,
  `vllm-native`). Each container takes a flavor, which picks its image and the
  devices it gets: llama's is `cuda13`, `rocm`, or `vulkan`, and vllm's `cuda` or `rocm`, which
  also picks its default row. vLLM serves one container per row, each with its own port and memory
  fraction; the standing rows and per-row tracing are in
  [Models](engines/vllm/models.md#the-standing-rows).
- **Served-load findings:** the GuideLLM runs, under `docs/findings/`.
  `bench-gb10-container.md` compares both engines on gb10-1 in containers by shape, quantization,
  concurrency, vision, ASR, and embeddings (granite-embedding-english-r2 on both engines), with
  each method's commands. `llama-strix-rocm.md` compares llama.cpp in ggml's ROCm and Vulkan
  images on the Framework by shape, quantization, vision, ASR, and embeddings, with each flavor's
  cold load and footprint. [`vllm-strix.md`](findings/vllm-strix.md) compares vLLM in its
  official ROCm image with llama.cpp in ggml's Vulkan image on the Framework, cell for cell, by
  shape, quantization, vision, ASR, and embeddings, with each row's cold start and footprint and
  an audio probe on a derived image. `answer.md` runs gb10-1's concurrency sweep on the Framework,
  llama.cpp in ggml's Vulkan image, and reads gpt-oss-120b's initial setting from it. The anchor
  cells later tasks rerun are first in `llama-gb10-container.md` for llama.cpp and
  `vllm-gb10-container.md` for vLLM.
- **Raw backend findings:** llama-bench's pp/tg per llama.cpp backend. `llama-gb10-native.md` has
  gb10-1's CUDA build, natively and in ggml's full-cuda13 image, on gpt-oss-120b and
  gemma-4-26B-A4B. `llama-strix-rocm.md` has the Framework's ROCm and Vulkan images and ggml's
  native Vulkan prebuilt, on the same two models at depths 0 and 8192.
- **API surface:** the matrix of what each engine serves, probed on both engines from each API
  page's probes (`bench-gb10-container.md`, "API probes").
- **Hosting method:** container against bare metal. `llama-gb10-native.md` compares llama.cpp
  on gb10-1 in ggml's container and natively under systemd: install, update, rollback, cold load,
  footprint, llama-bench, and the anchor cells. `vllm-gb10-native.md` compares vLLM on gb10-1 in
  vLLM's image and natively from its cu130 wheel under systemd: install, update, rollback, cold
  start, footprint, the anchor cells, and the Marlin MoE diagnostic.
- **Quantization rule:** the floor every cell keeps, applied in `bench-gb10-container.md`'s
  formats (`standards-lab/docs/ai-hosting.md#experiment-rules`).
- **The answer:** llama.cpp in a container on both host classes, in ggml's CUDA image on the
  GB10s and its Vulkan image on the Framework. vLLM's leads and the measured concurrency curves
  are kept as evidence, and the answer sets no slot limit ([README](../README.md#the-answer)).

## References

The spike reads these repositories and never writes to them. Each is a key in the coordinator's
`references.toml`, with its local checkout in `references.local.toml`:

- `spike-model-hosting`: the Strix Halo runbook and llama.cpp build log, the baseline, and the
  model-card method.
- `personal-agents`: the Framework's preparation and its `outpost` admin scripts, the model for the
  `engines` suite.
- `dotfiles`: the GB10 setup pattern (`platforms/dgx/system-setup.sh`) and the QSFP link record.
  Two-node serving belongs to spike-model-layout.
