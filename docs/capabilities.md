# Capabilities, path, and references

This page details the spike's built capabilities, the tasks it ran in order, and the repositories
it reads, for the map and the evidence in [`context/README.md`](../context/README.md).

## Capabilities

- **Engine guides:** setup, models, APIs, updates, and uninstall, per engine, under
  `docs/engines/<engine>/`; llama.cpp's and vLLM's are written for the GB10s, and each has
  sections for the Framework.
- **The `engines` suite:** the scripted install, update, and uninstall steps, under `host/`;
  llama.cpp's and vLLM's, each in a container (`llama`, `vllm`) and natively (`llama-native`,
  `vllm-native`), are written. Each container takes a flavor, which picks its image and the
  devices it gets: llama's is `cuda13`, `rocm`, or `vulkan`, and vllm's `cuda` or `rocm`, which
  also picks its default row.
- **Served-load findings:** GuideLLM runs under `docs/findings/`.
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
- **Raw backend findings:** llama-bench pp/tg per llama.cpp backend. `llama-gb10-native.md` has
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
  formats ([Rules](../context/README.md#rules)).
- **The answer:** llama.cpp in a container on both host classes, in ggml's CUDA image on the
  GB10s and its Vulkan image on the Framework. vLLM's leads and the measured concurrency curves
  are kept as evidence, and the answer sets no slot limit ([README](../README.md#the-answer)).

## Path

The tasks, in the order they run; each cites the evidence it proves.

1. `llama-gb10-container`: llama.cpp in ggml's CUDA 13 image on both GB10s, the `engines` suite,
   the llama.cpp guide, two GuideLLM anchor cells (evidence 1, 2).
2. `vllm-gb10-container`: vLLM's CUDA 13.0 arm64 image on both GB10s, NVFP4 served, the vLLM guide
   (evidence 1, 3).
3. `bench-gb10-container`: both engines' cells on gb10-1 and the API-surface probes, in
   `docs/findings/bench-gb10-container.md` (evidence 2, 3, 4, 5).
4. `llama-gb10-native`: llama.cpp native under systemd on gb10-1, llama-bench, anchor cells
   against the container, in `docs/findings/llama-gb10-native.md` (evidence 1, 6).
5. `vllm-gb10-native`: vLLM's aarch64 wheel natively on gb10-1, anchor cells against the
   container, and a Marlin MoE diagnostic on bench-gb10-container's question of vLLM's slow NVFP4
   decode on SM121, in `docs/findings/vllm-gb10-native.md` (evidence 1, 6).
6. `llama-strix-rocm`: llama.cpp in ggml's ROCm image against ggml's Vulkan image on the
   Framework, the `engines` suite's flavor, in `docs/findings/llama-strix-rocm.md` (evidence 1, 2,
   3).
7. `vllm-strix`: vLLM's official ROCm image on gfx1151 against llama.cpp's Vulkan image, which
   led task 6, cell for cell, in `docs/findings/vllm-strix.md` (evidence 1, 2). vLLM serves every
   ROCm row. The official image can't decode audio, so its audio cells are unsupported; a probe
   image that adds the missing packages serves them. llama.cpp's output tok/s is higher at every
   text, vision, and audio cell, and vLLM's request rate at both embedding cells.
8. `strix-native`: dropped. It ran only when task 6 showed ROCm leading or the GB10 native tasks
   showed bare metal winning; Vulkan led task 6, and bare metal measured level with the container
   on gb10-1 (evidence 6).
9. `answer`: llama.cpp in a container on both host classes, ggml's CUDA image on the GB10s and
   its Vulkan image on the Framework, in README "The answer" (evidence 1 to 6). The Framework's
   concurrency sweep, in `docs/findings/answer.md`, gives gpt-oss-120b an initial setting of 4
   streams. spike-model-hosting's router is retired, and the Framework serves set A.

## References

The spike reads these repositories and never writes to them. Each is a key in the coordinator's
`references.toml`, with its local checkout in `references.local.toml`:

- `spike-model-hosting`: the Strix Halo runbook and llama.cpp build log, the baseline, and the
  model-card method.
- `personal-agents`: the Framework's preparation and its `outpost` admin scripts, the model for the
  `engines` suite.
- `dotfiles`: the GB10 setup pattern (`platforms/dgx/system-setup.sh`) and the QSFP link record.
  Two-node serving belongs to spike-model-layout.
