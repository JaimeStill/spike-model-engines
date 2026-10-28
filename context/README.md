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
  ([setup](../docs/engines/llama.cpp/setup.md#7-allow-the-page-cache-drop)) and the Framework's
  ([setup](../docs/engines/llama.cpp/setup.md#11-allow-the-page-cache-drop)), or the five
  `systemctl` commands that start, stop, restart, enable, and disable native llama.cpp's
  `llama-router` unit, each named with its arguments
  ([setup](../docs/engines/llama.cpp/setup.md#1-the-architects-root-steps)), and native vLLM's
  `vllm-server` unit ([setup](../docs/engines/vllm/setup.md#1-the-architects-root-steps)).

## Capabilities

- **Engine guides:** setup, models, APIs, updates, and uninstall, per engine, under
  `docs/engines/<engine>/`; llama.cpp's and vLLM's are written for the GB10s, and llama.cpp's has
  sections for the Framework.
- **The `engines` suite:** the scripted install, update, and uninstall steps, under `host/`;
  llama.cpp's and vLLM's, each in a container (`llama`, `vllm`) and natively (`llama-native`,
  `vllm-native`), are written. llama's container takes a flavor, `cuda13`, `rocm`, or `vulkan`,
  which picks its image and the devices it gets.
- **Served-load findings:** GuideLLM runs under `docs/findings/`.
  `bench-gb10-container.md` compares both engines on gb10-1 in containers by shape, quantization,
  concurrency, vision, ASR, and embeddings (granite-embedding-english-r2 on both engines), with
  each method's commands. `llama-strix-rocm.md` compares llama.cpp in ggml's ROCm and Vulkan
  images on the Framework by shape, quantization, vision, ASR, and embeddings, with each flavor's
  cold load and footprint. The anchor cells later
  tasks rerun are first in `llama-gb10-container.md` for llama.cpp and `vllm-gb10-container.md`
  for vLLM.
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
   container, and a Marlin MoE diagnostic on bench-gb10-container's question of vLLM's slow NVFP4
   decode on SM121, in `docs/findings/vllm-gb10-native.md` (evidence 1, 6).
6. `llama-strix-rocm`: llama.cpp in ggml's ROCm image against ggml's Vulkan image on the
   Framework, the `engines` suite's flavor, in `docs/findings/llama-strix-rocm.md` (evidence 1, 2,
   3).
7. `vllm-strix`: vLLM's ROCm image on gfx1151, serving or a recorded failure, compared with
   llama.cpp's Vulkan image, which led task 6 (evidence 1, 2).
8. `strix-native`: dropped. It ran only when task 6 showed ROCm leading or the GB10 native tasks
   showed bare metal winning; Vulkan led task 6, and bare metal measured level with the container
   on gb10-1 (evidence 6).
9. `answer`: the evidence, README "The answer", and the answer section.

## Running on every host

The practices every task follows, on the GB10s and the Framework, each with its reason:

- **Pre-staging.** Every model a task serves is downloaded, and both engines' images pulled,
  first, all in parallel, before any cell or timed load. A download loads the host's network,
  disk, and CPU, so a cell or load beside one would measure that noise too
  ([models](../docs/engines/llama.cpp/models.md#pre-staging-everything-at-once)).
- **Cold loads.** A cold load is timed from a dropped page cache: a model read before loads from
  memory instead of disk, and vLLM counts the cache as free memory. The session drops it with the
  architect's sudoers rule: `sync && sudo -n /usr/sbin/sysctl vm.drop_caches=3` on gb10-1
  ([setup](../docs/engines/llama.cpp/setup.md#7-allow-the-page-cache-drop)), and
  `sync && sudo -n /usr/bin/sysctl vm.drop_caches=3` on the Framework, since Arch keeps `sysctl`
  in `/usr/bin` ([setup](../docs/engines/llama.cpp/setup.md#11-allow-the-page-cache-drop)).
- **The shared blob store.** The Hugging Face client in vLLM's image keeps a model's weight files
  in `/srv/models/blobs`, outside the model's directory, which only links to them. Copy
  `/srv/models/blobs` with the model's directory, and measure a model with `du -shL`, since a
  plain `du -sh` doesn't follow the links and shows a few MB
  ([models](../docs/engines/vllm/models.md#the-first-download)).
- **One engine per host.** Each engine's install and update refuse while another engine serves:
  the other engine's container, or any `llama-router` or `vllm-server` unit, each of which serves
  on its engine's container's port. On the Framework that includes spike-model-hosting's router.
  Beside a second server, vLLM's memory reservation would fail and its container restart in a
  loop. Stop one before installing the other.
- **A restarted container's log.** A container started again keeps the log of its earlier
  starts, so a ready line is read only since the container's start
  ([setup](../docs/engines/vllm/setup.md#6-watch-the-cold-start-and-record-it)).
- **`ls` is eza.** Both host classes alias `ls` to eza (the GB10 setup in dotfiles, and Omarchy),
  whose flags differ from coreutils' (`ls -laL` failed: eza reads `-L` as a tree depth), so guide
  commands use `du -shL`, `stat`, `readlink -f`, or `command ls` instead.
- **Hosts by short name.** Laptop commands name a host by its short name (`http://gb10-1:8000`,
  `http://framework:8080`), which MagicDNS resolves, so no command carries a tailnet address.
- **Install messages.** The `engines` install messages print the port, never the host's address,
  so a pasted output keeps to `ai-hosting.md`'s "Visibility" rule as it stands.
- **A moved preset.** llama's container mounts the clone's `host/llama-preset` by its path, and
  native llama.cpp reads it through the `/opt/llama.cpp/preset` link, so moving the clone or its
  scripts leaves either on a stale preset. `host/engines llama update` rebuilds the container
  without a pull, and `host/engines llama-native update` re-points the link; each `install`
  refuses and points at its update
  ([update](../docs/engines/llama.cpp/update.md#moving-to-the-pinned-build)).
- **Network path.** When the architect is remote, the laptop can reach a host through a
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

## Running on the Framework

The practices every task on the Framework follows, each with its reason:

- **The session owns the Framework.** Nothing else serves on it while a task's session runs, so no
  other server holds port 8080 or the GTT while the task measures.
- **The GTT ceiling.** The GPU reaches up to 112 GiB of RAM as GTT, set by TTM's `pages_limit`
  and amdgpu's `gttsize`, built into the boot image. Above 90% of RAM, `amd-ttm` warns that a GPU
  filling memory can starve the host; clearing the options halves the ceiling to the kernel's
  default ([setup](../docs/engines/llama.cpp/setup.md#2-set-the-gtt-ceiling)).
- **The store and its snapshots.** `/srv/models` is on the root drive, a btrfs subvolume Snapper
  snapshots before each `omarchy update`, so a deleted model frees its space only once the last
  snapshot holding it ages out
  ([setup](../docs/engines/llama.cpp/setup.md#8-create-the-model-store)).
- **The docker group.** Joining it takes effect at the next login. A terminal on the Framework's
  desktop belongs to the desktop's earlier login, so it gets `permission denied` until the desktop
  logs in again or the terminal runs `newgrp docker`
  ([setup](../docs/engines/llama.cpp/setup.md#3-docker-for-jaime)).
- **ufw route rules.** Omarchy's ufw with ufw-docker drops routed traffic to a container's
  published port, so the laptop reaches ports 8080 and 8000 only through `ufw route allow` rules
  on `tailscale0`. A laptop request that times out while `/health` answers on the host means a
  rule is missing ([setup](../docs/engines/llama.cpp/setup.md#4-route-the-ports-through-ufw)).
- **spike-model-hosting's router.** Its `llama-router` holds port 8080 and most of the GTT, so it
  stays stopped and disabled, and the `engines` commands refuse while it is active
  ([setup](../docs/engines/llama.cpp/setup.md#5-stop-the-router)). Retiring it is the answer
  task's.
- **Flavors.** `host/engines llama` picks the `rocm` flavor on the Framework's AMD GPU, and
  `LLAMA_FLAVOR=vulkan host/engines llama update` switches to `vulkan`. Update keeps the same
  build's other flavor, so a switch pulls nothing
  ([update](../docs/engines/llama.cpp/update.md#switching-the-flavor)).
- **Sudoers files without an editor.** `sudo` drops an `EDITOR` set on its command line, so
  `visudo` opens vim, and vim inside another editor's terminal takes `visudo`'s `--` for a file
  name and saves nothing. The architect writes a rule with `tee`, checks it with `visudo -cf`, and
  installs it ([setup](../docs/engines/llama.cpp/setup.md#11-allow-the-page-cache-drop)).
- **Background jobs over SSH.** A `nohup … &` job started by a non-interactive `ssh framework '…'`
  dies when the command returns, so a session starts it with `setsid nohup … < /dev/null &`. A
  `pgrep -f` run through `ssh` matches its own command line, so a wait checks the jobs' logs
  instead ([models](../docs/engines/llama.cpp/models.md#on-the-framework)).
- **Two Mesas.** ggml's Vulkan image runs Ubuntu's Mesa 26.0, and the host runs 26.2.5. ggml's
  native Vulkan prebuilt, on the host's Mesa, led the image at prompt processing by 4.5 to 9.5%,
  likely from the Mesa versions, untested, so a Vulkan result records which Mesa it ran on
  ([llama-strix-rocm](../docs/findings/llama-strix-rocm.md#raw-speed)).
- **GTT and VRAM in use.** The GPU's memory in use reads from `mem_info_gtt_used` and
  `mem_info_vram_used` in `/sys/class/drm/card1/device`, with no root, and a footprint adds it to
  `MemAvailable`
  ([llama-strix-rocm](../docs/findings/llama-strix-rocm.md#per-model-the-cold-load-and-its-footprint)).

## References

The spike reads these repositories and never writes to them. Each is a key in the coordinator's
`references.toml`, with its local checkout in `references.local.toml`:

- `spike-model-hosting`: the Strix Halo runbook and llama.cpp build log, the baseline, and the
  model-card method.
- `personal-agents`: the Framework's preparation and its `outpost` admin scripts, the model for the
  `engines` suite.
- `dotfiles`: the GB10 setup pattern (`platforms/dgx/system-setup.sh`) and the QSFP link record.
  Two-node serving belongs to spike-model-layout.
