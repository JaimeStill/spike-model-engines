# Host practices

The practices every task follows on the hosts, each with its reason: on every host, then on the
GB10s and on the Framework, for the map in [`context/README.md`](../context/README.md).

## Running on every host

The practices every task follows, on the GB10s and the Framework, each with its reason:

- **Pre-staging.** Every model a task serves is downloaded, and both engines' images pulled,
  first, all in parallel, before any start, cell, or timed load. A download loads the host's
  network, disk, and CPU, so a cell or load beside one would measure that noise too
  ([models](engines/llama.cpp/models.md#pre-staging-everything-at-once)).
- **Cold loads.** A cold load is timed from a dropped page cache: a model read before loads from
  memory instead of disk, and vLLM counts the cache as free memory. The session drops it with the
  architect's sudoers rule: `sync && sudo -n /usr/sbin/sysctl vm.drop_caches=3` on gb10-1
  ([setup](engines/llama.cpp/setup.md#7-allow-the-page-cache-drop)), and
  `sync && sudo -n /usr/bin/sysctl vm.drop_caches=3` on the Framework, since Arch keeps `sysctl`
  in `/usr/bin` ([setup](engines/llama.cpp/setup.md#11-allow-the-page-cache-drop)).
- **The shared blob store.** The Hugging Face client in vLLM's image keeps a model's weight files
  in `/srv/models/blobs`, outside the model's directory, which only links to them. Copy
  `/srv/models/blobs` with the model's directory, and measure a model with `du -shL`, since a
  plain `du -sh` doesn't follow the links and shows a few MB
  ([models](engines/vllm/models.md#the-first-download)).
- **One engine per host.** Each engine's install and update refuse while another engine serves:
  the other engine's container, or any `llama-router` or `vllm-server` unit, each of which serves
  on its engine's container's port. Beside a second server, vLLM's memory reservation would fail
  and its container restart in a loop. Stop one before installing the other.
- **vLLM's compile cache.** A row's first start compiles into the compile cache, and later starts
  load it, so a timed start runs from a warm compile cache and the first start is recorded apart.
  On the Framework, the generative rows' first starts took 163 to 189 s and their warm starts 70
  to 161 s ([vllm-strix](findings/vllm-strix.md#cold-start-and-footprint)).
- **A started router serves no model.** llama.cpp's router runs with `--no-models-autoload`, so
  after `docker start llama` or a reboot, as at a handover from vLLM, it serves nothing until a
  model is loaded through `/models/load`
  ([models](engines/llama.cpp/models.md#loading-a-model)).
- **A restarted container's log.** A container started again keeps the log of its earlier
  starts, so a ready line is read only since the container's start
  ([setup](engines/vllm/setup.md#6-watch-the-cold-start-and-record-it)).
- **`ls` is eza.** Both host classes alias `ls` to eza (the GB10 setup in dotfiles, and Omarchy),
  whose flags differ from coreutils' (`ls -laL` failed: eza reads `-L` as a tree depth), so guide
  commands use `du -shL`, `stat`, `readlink -f`, or `command ls` instead.
- **Hosts by short name.** Laptop commands name a host by its short name (`http://gb10-1:8000`,
  `http://framework:8080`), which MagicDNS resolves, so no command carries a tailnet address.
- **Install messages.** The `engines` install messages print the port, never the host's address,
  so a pasted output commits no tailnet identifier ([`STANDARDS.md`](../STANDARDS.md#docs)).
- **A moved preset.** llama's container mounts the clone's `host/llama-preset` by its path, and
  native llama.cpp reads it through the `/opt/llama.cpp/preset` link, so moving the clone or its
  scripts leaves either on a stale preset. `host/engines llama update` rebuilds the container
  without a pull, and `host/engines llama-native update` re-points the link; each `install`
  refuses and points at its update
  ([update](engines/llama.cpp/update.md#moving-to-the-pinned-build)).
- **Network path.** When the architect is remote, the laptop can reach a host through a
  Tailscale DERP relay. The relay adds its round trip to TTFT and request latency, but not to ITL
  or the server's `/metrics` figures, so every served run records its path with `tailscale ping`.
- **Model state.** The prompt cache changes TTFT and the prompt tokens the server processes: cell
  B's rerun, on a freshly loaded model, had a higher TTFT than its first run after cell A. Start
  each cell from the same model state, warmed or freshly loaded, so TTFT compares like with like.
- **Warm-up.** Send each model one request before its first cell. A cold first request raised
  llama.cpp's anchor A's TTFT p95 from 436 to 735 ms, with decode unchanged
  ([bench-gb10-container](findings/bench-gb10-container.md#walkthrough)).
- **Embeddings normalize differently.** llama.cpp returns each embedding at unit length by
  default; vLLM returns granite-embedding-english-r2's unnormalized, of norm about 30, since the
  model ships no normalization. A client that takes a dot product as a cosine normalizes vLLM's
  embeddings first ([vLLM's API](engines/vllm/api.md#embeddings)).
- **Store-only loads.** llama.cpp's preset sets `offline = true`, so a load never downloads. vLLM
  has no such guard: a start fetches any small file missing from the store without a word, as
  gpt-oss-120b's did for three JSON files from `original/`. Stage every file a model's start reads
  ([Pre-staging](findings/bench-gb10-container.md#pre-staging)).
- **Buffer sizes.** llama.cpp's preset sets `verbosity = 4`, since v0.7.0 (b11669) logs a load's
  weight, KV cache, and compute buffers only above its default of 3
  ([models](engines/llama.cpp/models.md#the-preset)).
- **Base64 from a file.** The vision probes read the image's base64 with `jq --rawfile`, since
  the base64 passed as a jq argument exceeds the shell's argument-list limit
  ([API](engines/llama.cpp/api.md#vision)).
- **Held pins.** `mise run currency` reports a held pin like any other, and the pin's comment says
  why it is held. Two are held: `mise.bench.toml` holds GuideLLM's Python at 3.14, because
  torchcodec 0.17.0, which GuideLLM's audio extra needs, publishes no 3.15 wheel; and
  `host/vllm.env` holds native vLLM's Python at 3.12, because native vLLM is retired on both hosts.
  spike-model-gateway's priority task ended the llama.cpp hold on b12098 (both classes moved to
  b12464, now b12602, inert and unverified there, and Google's QAT sections may still not resolve:
  llama.cpp #31620 and #31639) and moved vLLM to v0.34.0.
- **GuideLLM's client faults.** GuideLLM 0.8.1 has failed on the client while the server served:
  it stalled between an embedding cell's 1- and 16-stream levels, and it dropped a request's
  stream before the request finished, which llama.cpp logged as the client's read error. When the
  server's log and `/metrics` show no server error and the server idle, the fault is GuideLLM's:
  the cell reruns once, and both runs are kept
  ([vllm-strix](findings/vllm-strix.md#a-note-on-the-granite-stall)).
- **GuideLLM's extras.** The bench environment installs GuideLLM with its `vision` and `audio`
  extras, for the image and audio requests. mise counts an install made before the extras were
  added as current, so that install gains them only when forced:
  `MISE_ENV=bench mise install --force pipx:guidellm`.

## Running on the GB10s

The practices every task on the GB10s follows, each with its reason:

- **CDI spec.** An `apt upgrade` without a reboot can leave the NVIDIA Container Toolkit's CDI spec
  naming a library that is gone, and every GPU container then fails to start. Regenerate it after
  each upgrade ([setup](engines/llama.cpp/setup.md#1-bring-the-host-current)).
- **gb10-1 alone.** gb10-2 is reserved for spike-ai-pipeline, so every task installs, downloads,
  and measures on gb10-1 alone; gb10-2 is used only under a named borrow (`ai-hosting.md`,
  "Hosts and access").
- **Models.** Download a model once, on gb10-1, with hf
  ([models](engines/llama.cpp/models.md#pre-staging-models-with-hf)). Copy it to gb10-2
  over QSFP only under a named borrow of gb10-2
  ([models](engines/llama.cpp/models.md#copying-a-model-to-the-other-gb10)).

## Running on the Framework

The practices every task on the Framework follows, each with its reason:

- **A measuring session owns the Framework.** Nothing else serves on it while a session measures,
  so no other server holds port 8080 or the GTT during a measurement.
- **Set A between tasks.** The Framework serves set A from the `llama` container between tasks
  ([setup](engines/llama.cpp/setup.md#12-serve-set-a)). vLLM's install and update refuse
  while `llama` runs, so a task stops it (`docker stop llama`) before installing vLLM, and the
  setup's step serves set A again.
- **The GTT ceiling.** The GPU reaches up to 112 GiB of RAM as GTT, set by TTM's `pages_limit`
  and amdgpu's `gttsize`, built into the boot image. Above 90% of RAM, `amd-ttm` warns that a GPU
  filling memory can starve the host; clearing the options drops the ceiling to the kernel's
  default of half of RAM, about 62.5 GiB ([setup](engines/llama.cpp/setup.md#2-set-the-gtt-ceiling)).
- **The store and its snapshots.** `/srv/models` is on the root drive, a btrfs subvolume Snapper
  snapshots before each `omarchy update`, so a deleted model frees its space only once the last
  snapshot holding it ages out
  ([setup](engines/llama.cpp/setup.md#8-create-the-model-store)).
- **The docker group.** Joining it takes effect at the next login. A terminal on the Framework's
  desktop belongs to the desktop's earlier login, so it gets `permission denied` until the desktop
  logs in again or the terminal runs `newgrp docker`
  ([setup](engines/llama.cpp/setup.md#3-docker-for-jaime)).
- **ufw route rules.** Omarchy's ufw with ufw-docker drops routed traffic to a container's
  published port, so the laptop reaches ports 8080 and 8000 only through `ufw route allow` rules
  on `tailscale0`. A laptop request that times out while `/health` answers on the host means a
  rule is missing ([setup](engines/llama.cpp/setup.md#4-route-the-ports-through-ufw)).
- **Flavors.** `host/engines llama` picks the `rocm` flavor on the Framework's AMD GPU, and
  `LLAMA_FLAVOR=vulkan host/engines llama update` switches to `vulkan`. Update keeps the same
  build's other flavor, so switching back pulls nothing
  ([update](engines/llama.cpp/update.md#switching-the-flavor)). `host/engines vllm` picks
  its `rocm` flavor the same way: `vllm/vllm-openai-rocm`, with gpt-oss-120b as its default row
  ([update](engines/vllm/update.md#the-flavor)).
- **vLLM's reservation.** vLLM counts the whole 112 GiB GTT ceiling as the GPU's memory and
  reserves 0.80 of it, 89.6 GiB, at every generative row, so MemAvailable falls to about 21 to 24
  GiB whatever the model; the KV cache takes what the weights leave. The embedding row logs no
  reservation and leaves about 114 GiB ([vllm-strix](findings/vllm-strix.md#cold-start-and-footprint)).
- **vLLM's audio.** vLLM's official ROCm image ships no audio decoder, so an audio request returns
  500. The probe image that `host/vllm-rocm-audio/Dockerfile` builds adds the audio extra's
  missing packages and serves audio; the `engines` suite doesn't build it
  ([vllm-strix](findings/vllm-strix.md#the-audio-probe)).
- **Sudoers files without an editor.** `sudo` drops an `EDITOR` set on its command line, so
  `visudo` opens vim, and vim inside another editor's terminal takes `visudo`'s `--` for a file
  name and saves nothing. The architect writes a rule with `tee`, checks it with `visudo -cf`, and
  installs it ([setup](engines/llama.cpp/setup.md#11-allow-the-page-cache-drop)).
- **Background jobs over SSH.** A `nohup … &` job started by a non-interactive `ssh framework '…'`
  dies when the command returns, so a session starts it with `setsid nohup … < /dev/null &`. A
  `pgrep -f` run through `ssh` matches its own command line, so a wait checks the jobs' logs
  instead ([models](engines/llama.cpp/models.md#on-the-framework)).
- **Two Mesas.** ggml's Vulkan image runs Ubuntu's Mesa 26.0, and the host runs 26.2.5. ggml's
  native Vulkan prebuilt, on the host's Mesa, led the image at prompt processing by 4.5 to 9.5%,
  likely from the Mesa versions, untested, so a Vulkan result records which Mesa it ran on
  ([llama-strix-rocm](findings/llama-strix-rocm.md#raw-speed)).
- **GTT and VRAM in use.** The GPU's memory in use reads from `mem_info_gtt_used` and
  `mem_info_vram_used` in `/sys/class/drm/card1/device`, with no root, and a footprint adds it to
  `MemAvailable`
  ([llama-strix-rocm](findings/llama-strix-rocm.md#per-model-the-cold-load-and-its-footprint)).

