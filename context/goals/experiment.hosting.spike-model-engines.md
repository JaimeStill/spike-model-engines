# goal · experiment.hosting.spike-model-engines

- **State:** building
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

## Task brief · vllm-gb10-container

**Problem.** Only llama.cpp runs on the GB10s. The spike's question is llama.cpp or vLLM, and
NVFP4 is served only through vLLM, so this task brings in the second engine. It gives vLLM its
CUDA 13.0 arm64 image on both GB10s, its install, update, and uninstall steps, its guide, an
NVFP4 model served, and the anchor cells later tasks rerun for vLLM. Each engine's guide also
records whether it loads models on demand, which now joins evidence 1.

Proof: The architect installs, serves, updates, and uninstalls vLLM on both GB10s from the guide.

**Behaviors**

1. The architect brings both GB10s current at the session's start. Each host's stack is
   recorded with the date: DGX OS, driver, CUDA, kernel, Docker, the container toolkit, and
   whether a reboot is pending.
2. The pinned image runs on both GB10s with the GPU, prints its version, and finds the GB10 as a
   CUDA device. The pin is vLLM's latest release (v0.32.0), on its default CUDA 13.0
   multi-arch tag.
3. `mise run currency` reports the pinned vLLM release when it trails vLLM's latest GitHub
   release, and reports nothing for vLLM when they match. Its other lines are unchanged.
4. `engines vllm install` runs one `vllm` container with restart unless-stopped. It installs the
   pinned image, or a release given as an argument (the walkthrough uses that for v0.31.0). The
   container:
   - runs as the architect's user;
   - serves nvidia/Gemma-4-26B-A4B-NVFP4, the model pinned beside the release, with:
     - 4 concurrent sequences of 8192 tokens;
     - GPU memory utilization 0.80;
     - a BF16 KV cache;
     - the vision encoder loaded;
     - the model's own reasoning and tool-call parsing;
   - uses the shared model store as its Hugging Face cache, and keeps its compile cache in a
     directory in the architect's home;
   - serves on the host's tailnet address, port 8000.

   A second run changes nothing. It refuses, changing nothing, while `llama` runs, when the
   store is missing, or when the host has no tailnet address.
5. `engines llama install` and `engines llama update` refuse, changing nothing, while `vllm`
   runs. Their behavior is otherwise unchanged.
6. `engines vllm update` moves the container to the pinned release and model, and removes every
   previous vLLM image. It pulls before it removes anything, and changes nothing when the
   container already runs the pin. The walkthrough proves it by installing v0.31.0 and updating
   to v0.32.0.
7. `engines vllm uninstall` removes the container, every vLLM image, and the compile cache, and
   keeps the model store. A second run changes nothing.
8. The container fetches the NVFP4 model into gb10-1's store, and the architect copies it to
   gb10-2 over QSFP, so gb10-2 loads it without a download. From the laptop the model answers an
   OpenAI chat completion, with its reasoning separated. `/metrics` and `/version` answer, and
   the version matches the pin.
9. The vLLM guide has six pages: README, setup, models, api, update, and uninstall. It:
   - holds every command the architect types, exactly as typed, with no tailnet identifier;
   - states that vLLM serves one model per server and loads none on demand, so changing the
     model means editing the pin and running update;
   - records the cold start each time.

   The llama.cpp guide's README states that its router loads models on demand. The llama.cpp
   guide also says that llama refuses to install or update while `vllm` runs. The spike's
   evidence 1 gains on-demand loading.
10. GuideLLM 0.8.1 runs two anchor cells from the laptop against gb10-1 at v0.32.0, on the NVFP4
    model:
    - A' is 1 stream sending 8 requests; B' is 4 streams sending 32;
    - each request is 512 synthetic prompt tokens and exactly 256 output tokens;
    - both start from a warm model (one chat request after the server reports ready), A' then
      B';
    - each takes under 10 minutes.

    A dated finding records the release, the host stack, the network path (`tailscale ping`), and
    the figures. The client figures are GuideLLM's. The server figures are vLLM's own `/metrics`
    counters, differenced over each cell.
11. The architect installs, serves, updates, and uninstalls vLLM on both GB10s from the guide
    alone.

**Test seams.**
- The `engines` commands on each host.
- `mise run check` and `mise run currency` on the laptop.
- The guide, followed step by step.

**Slices**

1. **Hosts current, image proven** (behaviors 1–3). Both GB10s brought current, with their stacks
   recorded. The image's version and device check run on the GPU on both. The vLLM pin and its
   currency line land.
2. **vLLM served, and the guide** (behaviors 4–9). Install, update, and uninstall; the mutual
   refusal with llama; the store as the Hugging Face cache, and the compile cache; the NVFP4 model
   fetched on gb10-1 and copied to gb10-2; a chat request, `/metrics`, and `/version` from the
   laptop; the on-demand-loading lines. Walked on gb10-1.
3. **Anchor cells** (behavior 10). A' and B' on gb10-1, and the dated finding.
4. **Walkthrough** (behaviors 6, 11). The architect runs the whole procedure from the guide on
   both GB10s: install v0.31.0, update to v0.32.0, then uninstall.

Only Python trails, and it is held, so no upgrade slice comes first.

**Out of scope.**
- gpt-oss-120b and every other model on vLLM.
- Comparing the engines, which bench-gb10-container does, along with:
  - other shapes and quantizations;
  - the concurrency sweep;
  - the API-surface probes, Anthropic messages and tools included.
- Benchmarking on gb10-2.
- Sleep mode and every dev-mode endpoint.
- Serving a model on demand, through llama-swap or anything else.
- Native vLLM (vllm-gb10-native).
- The Framework.

**Door.** Two-way for the repository: the model store and llama.cpp's install survive every
step. The host OS updates in slice 1 are hard to reverse, but the experiment's rules require them,
and the architect runs them as root steps.

## Progress

- [x] 1. Hosts current, image proven (dd99119; walked on both GB10s: stack unchanged from task 1, v0.32.0 digest befccf0e, NVIDIA GB10 124544 MiB)
- [ ] 2. vLLM served, and the guide
- [ ] 3. Anchor cells
- [ ] 4. Walkthrough

Held: a pending edit to ai-hosting.md, GB10 "Memory reporting" (vLLM reads the OS's available
memory on integrated GPUs), owed only once the finding records vLLM's startup memory.

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
- vllm-gb10-container: BF16 KV cache; rejected the GB10 recipe's FP8 cache, so the cells measure
  only the weights' format.
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
