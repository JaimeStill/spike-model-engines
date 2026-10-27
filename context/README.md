# spike-model-engines

spike-model-engines is where the architect learns llama.cpp and vLLM by running them, on a GB10,
gb10-1, and then the Framework, in containers first and then on bare metal. Each engine is
documented as a guide to setup, models, APIs, updates, and removal, and each comparison is a
benchmark planned and run together. Together they are evidence for the engine and hosting method
`v1.ai.hosting` specifies per host class, as a general strategy for self-hosted model engines. The
spike decides nothing itself.

The spike is the sub-goal `experiment.hosting.spike-model-engines` in the coordinator's roadmap,
`standards-lab/context/roadmap.toml`, where its tasks live. Its question is framed in
`standards-lab/context/ai-hosting.md`, under "Experiment: experiment.hosting", which holds the
experiment's rules and spike-model-hosting's answer. IL6 is out of this spike's scope.

## The question

Which engine, llama.cpp or vLLM, serves each workstation (the GB10s, then the Framework's Strix
Halo), and is it hosted in a container or on bare metal?

## The evidence

1. Each engine installs, updates, and uninstalls on each host class from a few named, idempotent
   scripted steps, and its guide documents setup, models, APIs, updates, and uninstall, and
   whether the engine loads models on demand.
2. Raw speed, TTFT, unified-memory footprint, and cold load per engine and host class, by shape:
   dense small, mid, and large; MoE; embedding; ASR; vision. Each cell is measured, or marked
   unsupported with its reason.
3. The same for each quantization format an engine serves natively, within the quantization
   floor. NVFP4 only through vLLM.
4. Scaling from 1 to N concurrent streams, and what each engine does past its slots.
5. The API surface the consumers need: OpenAI chat with tools and reasoning, Anthropic messages,
   embeddings, transcription, and vision, each probed or marked on paper.
6. Container against bare metal for each engine kept, per host class: install, update, rollback,
   startup, speed parity, and GPU and memory access.

## Rules

The experiment's rules, in `ai-hosting.md`, govern every session. In short:

- **Guided sessions.** Sessions are guided where the architect is learning. Each slice's docs and
  scripts are written on the branch first. The session runs routine host steps that need no root
  itself, over Tailscale SSH, and records each output: downloads and image pulls, engine install,
  update, and uninstall, model loads, readiness waits, cold-start timing, log and memory
  read-outs, and health and version checks. The architect keeps root, a new tool's or concept's
  first walk, which the session walks them through, the last slice's walkthrough of the whole
  procedure from the docs, and every escalation's decision. Every command either side runs
  appears in a guide or the finding's method exactly as run.
- **Benchmarks.** Each benchmark is planned together in its task's plan round, then built and run
  a step at a time from the commands the brief agreed: the session runs the GuideLLM cells in the
  architect's view, printing each command first. A run takes at most 10 minutes unless the
  brief decides otherwise.
- **Current hosts and engines.** Every session starts by bringing the hosts current. llama.cpp
  follows its semver releases, running the b-build each one names, and the guides name its
  version by release first, with the b-build beside it, as v0.7.0 (b11669); vLLM follows its
  releases. Every result records the engine version and the host stack.
- **Comparisons.** Only cells run in the same session on the same versions are compared. A task
  that compares with an earlier one first reruns one anchor cell per engine.
- **Quantization floor.** A format is accepted when its publisher evaluated it (native MXFP4, a
  QAT Q4_0, or an NVFP4 or FP8 checkpoint whose card evals are within about 1% of BF16).
  Otherwise nothing goes below Q5_K_M or FP8, and embedding, ASR, and dense models under 8B run at
  Q8_0 or FP8 or better.
- **Load tools.** GuideLLM 0.8.1, run from the laptop, for every served measurement; llama-bench
  for raw pp/tg per llama.cpp backend.
- **Root** stays the architect's, run from exact commands. A root command a session must repeat
  may be granted once, by the architect, as a sudoers rule naming that one command exactly, such
  as gb10-1's page-cache drop
  ([setup](../docs/engines/llama.cpp/setup.md#7-allow-the-page-cache-drop)), or the five
  `systemctl` commands that start, stop, restart, enable, and disable native llama.cpp's
  `llama-router` unit, each named with its arguments
  ([setup](../docs/engines/llama.cpp/setup.md#1-the-architects-root-steps)).

## Capabilities

- **Engine guides:** setup, models, APIs, updates, and uninstall, per engine, under
  `docs/engines/<engine>/`; llama.cpp's and vLLM's are written.
- **The `engines` suite:** the scripted install, update, and uninstall steps, under `host/`;
  llama.cpp's, in a container (`llama`) and natively (`llama-native`), and vLLM's are written.
- **Served-load findings:** GuideLLM runs under `docs/findings/`.
  `bench-gb10-container.md` compares both engines on gb10-1 in containers by shape, quantization,
  concurrency, vision, ASR, and embeddings (granite-embedding-english-r2 on both engines), with
  each method's commands. The anchor cells later
  tasks rerun are first in `llama-gb10-container.md` for llama.cpp and `vllm-gb10-container.md`
  for vLLM.
- **Raw backend findings:** llama-bench pp/tg per llama.cpp backend. `llama-gb10-native.md` has
  gb10-1's CUDA build, natively and in ggml's full-cuda13 image, on gpt-oss-120b and
  gemma-4-26B-A4B.
- **API surface:** the matrix of what each engine serves, probed on both engines from each API
  page's probes (`bench-gb10-container.md`, "API probes").
- **Hosting method:** container against bare metal. `llama-gb10-native.md` compares llama.cpp
  on gb10-1 in ggml's container and natively under systemd: install, update, rollback, cold load,
  footprint, llama-bench, and the anchor cells.
- **Quantization rule:** the floor every cell keeps, applied in `bench-gb10-container.md`'s
  formats ([Rules](#rules)).
- **The answer.**

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
   container (evidence 1, 6). Its plan round may take up one question from
   bench-gb10-container: vLLM's NVFP4 rows decode at about half llama.cpp's QAT Q4_0 rate, and
   FlashInfer attention didn't change that, so the NVFP4 path on SM121 is the suspect, untested
   ([Findings](../docs/findings/bench-gb10-container.md#findings)).
6. `llama-strix-rocm`: llama.cpp ROCm in ggml's ROCm image against the native Vulkan router
   (evidence 1, 2, 3).
7. `vllm-strix`: vLLM's ROCm image on gfx1151, serving or a recorded failure (evidence 1, 2).
8. `strix-native`: a native ROCm build, only when task 6 shows ROCm leading or the GB10 native
   tasks show bare metal winning (evidence 6).
9. `answer`: the evidence, README "The answer", and the answer section.

## Running on the GB10s

The practices every task on the GB10s follows, each with its reason:

- **CDI spec.** An `apt upgrade` without a reboot can leave the NVIDIA Container Toolkit's CDI spec
  naming a library that is gone, and every GPU container then fails to start. Regenerate it after
  each upgrade ([setup](../docs/engines/llama.cpp/setup.md#1-bring-the-host-current)).
- **gb10-1 alone.** gb10-2 is reserved for spike-ai-pipeline, so every task installs, downloads,
  and measures on gb10-1 alone; gb10-2 is used only under a named borrow (`ai-hosting.md`,
  "Hosts and access").
- **Models.** Download a model once, on gb10-1, with hf
  ([models](../docs/engines/llama.cpp/models.md#pre-staging-models-with-hf)). Copy it to gb10-2
  over QSFP only under a named borrow of gb10-2
  ([models](../docs/engines/llama.cpp/models.md#copying-a-model-to-the-other-gb10)).
- **Pre-staging.** Every model a task serves is downloaded, and both engines' images pulled,
  first, all in parallel, before any cell or timed load. A download loads the host's network,
  disk, and CPU, so a cell or load beside one would measure that noise too
  ([models](../docs/engines/llama.cpp/models.md#pre-staging-everything-at-once)).
- **Cold loads.** A cold load is timed from a dropped page cache: a model read before loads from
  memory instead of disk, and vLLM counts the cache as free memory. The session drops it with
  `sync && sudo -n /usr/sbin/sysctl vm.drop_caches=3`, which the architect's sudoers rule allows
  ([setup](../docs/engines/llama.cpp/setup.md#7-allow-the-page-cache-drop)).
- **The shared blob store.** The Hugging Face client in vLLM's image keeps a model's weight files
  in `/srv/models/blobs`, outside the model's directory, which only links to them. Copy
  `/srv/models/blobs` with the model's directory, and measure a model with `du -shL`, since a
  plain `du -sh` doesn't follow the links and shows a few MB
  ([models](../docs/engines/vllm/models.md#the-first-download)).
- **One engine per host.** Each engine's install and update refuse while another engine serves:
  the other engine's container, or native llama.cpp's `llama-router` unit, which serves on the
  container's port. Beside a second server, vLLM's memory reservation would fail and its
  container restart in a loop. Stop one before installing the other.
- **`ls` on the GB10s.** The GB10 setup in dotfiles aliases `ls` to eza, whose flags differ from
  coreutils' (`ls -laL` failed: eza reads `-L` as a tree depth), so guide commands use `du -shL`,
  `stat`, `readlink -f`, or `command ls` instead.
- **Hosts by short name.** Laptop commands name a GB10 by its short name (`http://gb10-1:8000`),
  which MagicDNS resolves, so no command carries a tailnet address.
- **Install messages.** The `engines` install messages print the port, never the host's address,
  so a pasted output keeps to `ai-hosting.md`'s "Visibility" rule as it stands.
- **A moved preset.** llama's container mounts the clone's `host/llama-preset` by its path, and
  native llama.cpp reads it through the `/opt/llama.cpp/preset` link, so moving the clone or its
  scripts leaves either on a stale preset. `host/engines llama update` rebuilds the container
  without a pull, and `host/engines llama-native update` re-points the link; each `install`
  refuses and points at its update
  ([update](../docs/engines/llama.cpp/update.md#moving-to-the-pinned-build)).
- **Network path.** When the architect is remote, the laptop can reach the GB10s through a
  Tailscale DERP relay. The relay adds its round trip to TTFT and request latency, but not to ITL
  or the server's `/metrics` figures, so every served run records its path with `tailscale ping`.
- **Model state.** The prompt cache changes TTFT and the prompt tokens the server processes: cell
  B's rerun, on a freshly loaded model, had a higher TTFT than its first run after cell A. Start
  each cell from the same model state, warmed or freshly loaded, so TTFT compares like with like.
- **Warm-up.** Send each model one request before its first cell. A cold first request raised
  llama.cpp's anchor A's TTFT p95 from 436 to 735 ms, with decode unchanged
  ([bench-gb10-container](../docs/findings/bench-gb10-container.md#walkthrough)).
- **Embeddings normalize differently.** llama.cpp returns each embedding at unit length by
  default; vLLM returns granite-embedding-english-r2's unnormalized, of norm about 30, since the
  model ships no normalization. A client that takes a dot product as a cosine normalizes vLLM's
  embeddings first ([vLLM's API](../docs/engines/vllm/api.md#embeddings)).
- **Store-only loads.** llama.cpp's preset sets `offline = true`, so a load never downloads. vLLM
  has no such guard: a start fetches any small file missing from the store without a word, as
  gpt-oss-120b's did for three JSON files from `original/`. Stage every file a model's start reads
  ([Pre-staging](../docs/findings/bench-gb10-container.md#pre-staging)).
- **Buffer sizes.** llama.cpp's preset sets `verbosity = 4`, since v0.7.0 (b11669) logs a load's
  weight, KV cache, and compute buffers only above its default of 3
  ([models](../docs/engines/llama.cpp/models.md#the-preset)).
- **Base64 from a file.** The vision probes read the image's base64 with `jq --rawfile`, since
  the base64 passed as a jq argument exceeds the shell's argument-list limit
  ([API](../docs/engines/llama.cpp/api.md#vision)).
- **GuideLLM's Python.** `mise.bench.toml` holds Python at 3.14, because torch publishes no 3.15
  wheels, so `mise run currency` reports Python behind until it does.
- **GuideLLM's extras.** The bench environment installs GuideLLM with its `vision` and `audio`
  extras, for the image and audio requests. mise counts an install made before the extras were
  added as current, so that install gains them only when forced:
  `MISE_ENV=bench mise install --force pipx:guidellm`.

## References

The spike reads these repositories and never writes to them. Each is a key in the coordinator's
`references.toml`, with its local checkout in `references.local.toml`:

- `spike-model-hosting`: the Strix Halo runbook and llama.cpp build log, the baseline, and the
  model-card method.
- `personal-agents`: the Framework's preparation and its `outpost` admin scripts, the model for the
  `engines` suite.
- `dotfiles`: the GB10 setup pattern (`platforms/dgx/system-setup.sh`) and the QSFP link record.
  Two-node serving belongs to spike-model-layout.
