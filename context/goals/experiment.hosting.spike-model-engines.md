# goal · experiment.hosting.spike-model-engines

- **State:** brief ready
- **Task:** vllm-gb10-container
- **Branch:** vllm-gb10-container

## Tasks

1. [x] llama-gb10-container
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
- llama-gb10-container: router mode, one llama-server with a models preset; rejected one model
  per container start, so the container-vs-native comparison changes only the hosting method.
- llama-gb10-container: model store /srv/models on each GB10, created once by the architect,
  bind-mounted; rejected a home directory, so vLLM and native llama.cpp reuse the same files.
- llama-gb10-container: the container downloads models from Hugging Face; rejected the hf CLI, a
  second new tool needing Python.
- llama-gb10-container: lifecycle is `docker run --restart unless-stopped`; rejected a systemd unit
  (task 4's native method) and compose.
- llama-gb10-container: the walkthrough installs v0.6.0's b11429 and updates to v0.7.0's b11669;
  update keeps only the latest image, removing the previous ones.
- llama-gb10-container: uninstall removes the container and image, keeping the model store;
  deleting models is a separate typed command.
- llama-gb10-container: GuideLLM 0.8.1 pinned in this spike's own mise env for the laptop;
  rejected reusing spike-model-hosting's env, which the spike only reads.
- llama-gb10-container: anchor model gpt-oss-120b MXFP4; rejected gpt-oss-20b.
- llama-gb10-container: two anchor cells, 512/256 synthetic, 1 stream x 8 and 4 streams x 32,
  with 4 slots; departs from the roadmap's one cell.
- llama-gb10-container: hosts brought current with `sudo apt update && sudo apt upgrade`, no
  reboot (the architect is remote) and no firmware update; a pending reboot is recorded; the CDI
  spec is regenerated after each upgrade, since without a reboot it goes stale.
- llama-gb10-container: the task branch is pushed to origin before its PR so the hosts can clone it;
  the walk adds one `git switch`.
- llama-gb10-container: a model is downloaded once, on gb10-1, and copied to gb10-2 over QSFP with
  rsync (63.4 GB in 1m50s); rejected a second download.
- llama-gb10-container: Python held at 3.14.9 in mise.bench.toml, since GuideLLM 0.8.1 needs torch
  and torch 2.14.1 has no cp315 wheels; the latest Python is 3.15.1.
- llama-gb10-container: hosts go by short name (`gb10-1`, `gb10-2-qsfp`); only tailnet
  addresses and the MagicDNS suffix stay out, matching ai-hosting.md "Visibility".
- llama-gb10-container: the preset turns on `metrics = true` so each cell differences the server's
  own /metrics counters; the guide gains /metrics and the /props build check.
- llama-gb10-container: bench commands (GuideLLM env, cells, read-outs) live in the finding's
  method, not the engine guide: they are behavior 10's measurement, not how the engine runs.
- llama-gb10-container: cell B rerun at the architect's request after one client-side parse error
  over the relay; 32/32, both runs kept in the finding.
- llama-gb10-container: currency gains the llama.cpp line only; vLLM's waits for its task.
- llama-gb10-container: every served run records the laptop's path to the host with `tailscale
  ping`; the cells ran over a DERP relay, which inflates TTFT and latency but not ITL or /metrics.

- vllm-gb10-container: image `vllm/vllm-openai:v<release>`, the default CUDA 13.0 multi-arch tag,
  vLLM's primary image; rejected `-ubuntu2404`, which changes only the container's base OS. (Round
  1 claimed v0.31.0 had no `-ubuntu2404` tag; it has one, and the architect kept the default.)
- vllm-gb10-container: NVFP4 model nvidia/Gemma-4-26B-A4B-NVFP4. It is 18.8 GB, within 0.7 pt of
  BF16 on its card's evals, recipe-validated on GB10, and the same model as the Framework
  baseline's Gemma 4 26B-A4B. Rejected Nemotron-3-Super-120B-A12B-NVFP4 (three evals more than
  1 pt below BF16) and Qwen3.5-122B-A10B-NVFP4 (evals against FP8).
- vllm-gb10-container: gpt-oss-120b MXFP4 on vLLM left to bench-gb10-container; tasks 1–2 set the
  engines up, and comparing them starts in task 3. Rejected serving it now as a second model: a
  65.2 GB download and a model switch, on a pairing not verified on GB10.
- vllm-gb10-container: one `vllm` container serves the model pinned beside the release
  (`docker run --restart unless-stopped`); changing the model means a pin edit and an update.
  Rejected a swap verb, a script kind STANDARDS.md doesn't allow. Rejected one container per
  model with split memory, which decides placement ahead of spike-model-layout. Rejected
  llama-swap, a second new tool.
- vllm-gb10-container: vLLM's install refuses while `llama` runs, so one engine serves per host at
  a time. Rejected running both at once: vLLM's reservation would fail and restart in a loop.
- vllm-gb10-container: llama's install and update refuse while `vllm` runs, matching vLLM;
  rejected leaving task 1's scripts unchanged.
- vllm-gb10-container: 4 sequences of 8192 tokens, mirroring llama's 4 slots of 8192; rejected
  vLLM's defaults. bench-gb10-container widens it.
- vllm-gb10-container: GPU memory utilization 0.80 (about 97 of 121 GiB); rejected the default
  0.92.
- vllm-gb10-container: a BF16 KV cache (`--kv-cache-dtype bfloat16`); rejected the checkpoint's
  FP8 KV cache (`auto`), since the checkpoint declares a static FP8 KV cache but ships no
  calibrated k/v scales, so vLLM falls back to a scale of 1.0 (v0.32.0 on gb10-1 warned "Using KV
  cache scaling factor 1.0 for fp8_e4m3"). Reopened twice: round 2 chose BF16, the architect
  reopened it for the checkpoint's FP8 KV, and the gb10-1 walk's warning reopened it back to BF16.
- vllm-gb10-container: install and update compare the container's image and whole command
  (model and server flags) with the pin's, both built from one list in `engines/vllm.sh`, so a
  changed flag reaches a running container: update replaces it, without a pull when the image is
  unchanged, and install refuses and points at update, as it does for another release. Rejected
  comparing only image and model, which the gb10-1 walk found let a flag change go unserved, and
  comparing the container's env and mounts, which the image's own env makes noisy and which
  don't change with the pin.
- vllm-gb10-container: Gemma 4's vision encoder loaded; rejected `--language-model-only`, since
  task 3 probes vision.
- vllm-gb10-container: compile cache bind-mounted from the architect's home and removed by
  uninstall; rejected a throwaway directory in the container.
- vllm-gb10-container: the walkthrough installs v0.31.0 and updates to v0.32.0, and update keeps
  only the latest image.
- vllm-gb10-container: two anchor cells, A' and B', on the NVFP4 model: 512/256 synthetic, 1 stream
  x 8 and 4 streams x 32, warm model. This departs from the roadmap, which names no cell for
  this task. They are vLLM's anchors; the rule of one anchor per engine doesn't need the same
  model on both engines.
- vllm-gb10-container: currency gains vLLM's line, the pinned release against GitHub's latest,
  read like llama.cpp's.
- vllm-gb10-container: whether an engine loads models on demand joins evidence 1 for every
  engine; rejected recording it as a guide fact only.
- vllm-gb10-container: port 8000, vLLM's default, on the tailnet address; rejected sharing
  llama's 8080.
- vllm-gb10-container: the container runs as the architect's user, with the shared store as its
  Hugging Face cache.
- vllm-gb10-container: the model's own parsers (`gemma4` reasoning and tool calls) and its
  shipped generation config (temperature 1.0, top_p 0.95, top_k 64).
- vllm-gb10-container: laptop commands name hosts by short name (`http://gb10-1:8000`), which
  MagicDNS resolves, in both guides and the anchor method; rejected a `GB10=<tailnet address>`
  variable re-set per host. At the architect's request, during the gb10-1 walk.
- vllm-gb10-container: install messages print the port, never the tailnet address (both
  engines), after the architect's visibility request during the walk; llama's message change is
  outside behavior 5's "otherwise unchanged" by that request.
- vllm-gb10-container: at the brief, the architect redirected: the session ran the remaining
  small checks itself over SSH on gb10-1 (no root): the stopped-container fix, the memory reading
  behind the memory-reporting edit (now owed), llama's update refusal, and `/version` after an
  install. One question stays for bench-gb10-container's plan round (context/README.md, Path): a
  diagnostic A' rerun for vLLM's slow decode; A' reruns there from a confirmed warm start.
- vllm-gb10-container: the guided-session rule bent once, for these checks, by the architect's
  request; root steps stay the architect's (sudo needs their password).
- vllm-gb10-container: install and update report a stopped container as stopped (docker start
  <name>) instead of "already runs"; both engines, fixed at the architect's request after
  acceptance; rejected starting it, which would change state on a check.

## Pending edits

- coordinator · ai-hosting.md, the GB10 host class, "Stack": replace "DGX OS reports 7.4.0 but
  carries a newer stack: driver 580.178.04, CUDA 13.0, kernel 7.0, Docker 29.6.2, and
  nvidia-container-toolkit 1.20.1" with "DGX OS 7.6.0, driver 580.178.04, CUDA 13.0, kernel
  7.0.0-1019-nvidia, Docker 29.6.2, and nvidia-container-toolkit 1.20.1"
  (spike-model-engines, docs/findings/llama-gb10-container.md).
- coordinator · ai-hosting.md, the GB10 host class: add "**CDI spec**: an apt upgrade without a
  reboot can leave the container toolkit's CDI spec (`/var/run/cdi/nvidia.yaml`) naming a moved
  driver library, and GPU containers then fail to start until `sudo nvidia-ctk cdi generate
  --output=/var/run/cdi/nvidia.yaml` regenerates it."
- coordinator · ai-hosting.md, "Experiment: experiment.hosting", "Hosts and access": extend the
  last sentence to "every measurement records the engine version, the host's stack, and the
  laptop's network path to the host (`tailscale ping`): a DERP relay adds its round trip to TTFT
  and request latency, but not to inter-token latency or the server's own counters."
- coordinator · roadmap.toml, spike-model-layout's summary (or spike-model-gateway's, as the
  coordinator places it): weigh serving models on demand, where an engine loads none itself,
  against keeping them resident; llama-swap in front of vLLM is the existing tool (drives Docker,
  ships arm64 builds) (spike-model-engines, the vLLM guide).
- coordinator · ai-hosting.md, "Experiment: experiment.hosting", the spike-model-engines
  paragraph: after "documents each engine as a guide to setup, models, APIs, updates, and
  uninstall", add ", and whether it loads models on demand".
- coordinator · ai-hosting.md, the GB10 host class, "Memory reporting": after "`cudaMemGetInfo`
  counts the page cache as used." add "On the integrated GPU, vLLM reads the OS's available memory
  instead, which counts the page cache as free: with 18 GiB cached and 99.7 GiB MemFree, v0.32.0
  reported 113.42 of 121.63 GiB free at startup." (spike-model-engines,
  docs/findings/vllm-gb10-container.md, "Serving and the model store").
