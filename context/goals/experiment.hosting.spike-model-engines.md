# goal · experiment.hosting.spike-model-engines

- **State:** building
- **Task:** vllm-gb10-native
- **Branch:** vllm-gb10-native

## Tasks

1. [x] llama-gb10-container
2. [x] vllm-gb10-container
3. [x] bench-gb10-container
4. [x] host-rename
5. [x] llama-gb10-native
6. [ ] vllm-gb10-native
7. [ ] llama-strix-rocm
8. [ ] vllm-strix
9. [ ] strix-native
10. [ ] answer

## Task brief · vllm-gb10-native

Approved 2026-10-27.

Problem
  vLLM runs on gb10-1 only in its container, so the spike can't yet say
  whether the GB10 should host it in a container or on bare metal
  (evidence 6: install, update, rollback, startup, speed parity, GPU and
  memory access per hosting method). This task runs the same vLLM
  release natively from its aarch64 CUDA 13.0 wheel, installed with uv
  (this task's one new tool), under systemd, and measures it against
  the container in one session, through the served API (the anchors)
  and at startup. It also takes up the one question bench-gb10-container
  left open: vLLM's slow NVFP4 decode on SM121.

Behaviors
  1. Currency reports only held items, and the check passes. GuideLLM's
     Python stays held, and native vLLM's Python pin is reported held,
     so the task needs no upgrade slice.
  2. Each native vLLM release is its own uv virtualenv under a
     jaime-owned /opt/vllm. It runs on uv-managed CPython 3.12, the
     image's Python, with vLLM at the exact release and torch from
     PyTorch's cu130 index. After every install, update and rollback,
     FlashInfer's precompiled kernels are downloaded into that
     environment. uv is the host env's pinned version. torch reports
     CUDA 13.0.
  3. A `current` link names the release that serves, and only the
     latest release is kept. uv's Python and cache, and vLLM's, Triton's
     and FlashInfer's compile caches, all live under /opt/vllm, so
     removing either hosting method leaves the other's caches alone.
  4. A system unit, modeled on native llama.cpp's, runs `vllm serve` as
     jaime through `current`. It requires and follows tailscaled, binds
     the tailnet address at start on port 8000, restarts on failure,
     and uses /srv/models as its Hugging Face cache. It reads the row's
     model and server flags at start from a file under /opt/vllm that
     install and update write from the rows, so switching rows or
     changing a flag needs no root.
  5. The architect's one-time root steps are in the setup guide, with
     their removal: create and chown /opt/vllm, install the unit file
     and daemon-reload, and a sudoers rule for exactly start, stop,
     restart, enable and disable of the unit.
  6. The engines suite gains idempotent native install, update and
     uninstall steps. They take a release and VLLM_MODEL as the
     container's steps do, and they refuse while the llama container,
     the vllm container or llama-router serves. Both engines' container
     steps, and native llama.cpp's, refuse while the native vLLM unit
     is up. The unit is enabled only while native vLLM serves and
     disabled on stop.
  7. Native update compares the row file with the row, as the
     container's update compares its command. Two servers can't share
     the memory reservation, so update stops the old server before
     starting the new one. It keeps the old release until the new one
     answers /health, waiting up to 10 minutes. Native install waits the
     same way. Uninstall keeps the model store and leaves the root
     steps for the architect's removal procedure.
  8. New tool, uv: the setup guide says what uv is, how it is set up
     (pinned in the host env and installed there before first use), and
     what each uv step of the native install does. It also gives the
     read-back commands: uv's version, its Python list, and the package
     list of `current`.
  9. The install and rollback walk: native v0.31.0 installs and serves,
     then updates to v0.32.0. Rolling back to v0.31.0 re-points
     `current`, and an update moves it forward again. Each step shows
     /version and torch's CUDA.
  10. Container anchors A' (1 × 8) and B' (4 × 32), on Gemma 4 26B-A4B
      NVFP4's pin row at 512/256, rerun warm at v0.32.0 before native A'
      and B' at the same load. An anchor that moved beyond run noise is
      a finding.
  11. One timed cold start of the pin row per hosting method, from a
      dropped page cache with that method's compile cache warm. Native's
      first start, which compiles from scratch, is recorded beside them.
      Each start records MemAvailable before and after, and vLLM's
      logged weights, KV cache and CUDA graphs.
  12. One diagnostic native A', on the pin row with the Marlin MoE
      backend, after the native anchors. The native server then returns
      to the pin. A rate that differs from native A' beyond run noise is
      a finding about the NVFP4 MoE kernel on SM121.
  13. Every result records the engine version, the Python and torch
      versions, the host stack, the laptop's path (tailscale ping) and
      the model state. No run exceeds 10 minutes.
  14. At the end, native vLLM, the vllm container, native llama.cpp
      and the llama container are all stopped and disabled on gb10-1.
      The record's host line says so.

Test seams
  vllm serve's HTTP API on gb10-1, as GuideLLM and curl call it from
  the laptop, and the native unit's journal and state on gb10-1.

Slices
  1. Native install (behaviors 1–9). The architect runs the root steps
     and uv's first walk: native install at v0.31.0 from the guide, and
     the uv read-back. The session first installs the host env's pinned
     uv on gb10-1, then runs the update to v0.32.0, the rollback and the
     forward update, recording each output. Demo: native v0.32.0
     answers on 8000 over the tailnet, and torch reads CUDA 13.0.
  2. The comparison (10–14). The session runs the cold starts and the
     GuideLLM cells in the architect's view, printing each command
     first: container anchors, then native anchors, then the Marlin
     diagnostic, then everything stopped and disabled. Demo: the
     finding, with its served-speed, startup and memory tables and the
     diagnostic row.
  3. Walkthrough: the architect installs, updates, rolls back and
     uninstalls native vLLM from the guide, and runs one anchor cell
     from the finding's method.

Out of scope
  gb10-2; `vllm bench` (a second new tool); gpt-oss-120b and the other
  rows on native; FlashInfer b12x and other MoE backends beyond the one
  diagnostic; an offline guard for model loads; tuning; Python 3.14 for
  native; removing the container hosting method (the answer task's);
  rewriting earlier findings.

Door
  Two-way. The unit, the sudoers rule and /opt/vllm are removed by the
  setup guide's removal procedure, and the releases and caches by
  native uninstall.

## Progress

slices 1/3 committed (slice 1 code; walk pending) · standards — · spec — · editor —

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

- bench-gb10-container: held python at 3.14.10 in mise.bench.toml: torch 2.14.1, which GuideLLM
  0.8.1 needs, publishes no cp315 wheels; the latest Python is 3.15.2.
- bench-gb10-container: one diagnostic A' rerun on FlashInfer attention, text-only
  (`--attention-backend FLASHINFER --language-model-only`), after A''s warm rerun; rejected no
  diagnostic and an FP8 KV cache rerun, since at 768 tokens the KV dtype moves few bytes and on
  SM121 Triton is forced by vision and by vLLM disabling FA4.
- bench-gb10-container: shapes from the Gemma 4 family on both engines (E4B Q8_0 / BF16; 12B QAT
  Q4_0 / QAT w4a16; 31B QAT Q4_0 / NVFP4; 26B-A4B QAT Q4_0 with mmproj / NVFP4; EmbeddingGemma 2
  Q8_0 / BF16), plus gpt-oss-120b MXFP4 on both; rejected separate pool picks per engine.
  ggml-org's Gemma 4 Q4_0 is quantized from BF16, below the floor; Google's QAT Q4_0 is used.
- bench-gb10-container: gpt-oss-120b served on vLLM in this task, closing vllm-gb10-container's
  deferral.
- bench-gb10-container: every generative shape runs the anchors' load (512/256, 1 x 8 and 4 x 32),
  halved for the dense large model (1 x 4, 4 x 16); rejected single-stream only.
- bench-gb10-container: cold loads timed from a dropped page cache; rejected whatever the cache
  holds, which also skews vLLM's free-memory reading.
- bench-gb10-container: memory footprint from each engine's logged figures plus MemAvailable
  before and after the load; rejected the logs alone.
- bench-gb10-container: vLLM's per-model server flags live beside the model in the pin file, one
  row a model; rejected keeping them in the engines script.
- bench-gb10-container: gb10-2's reservation (coordinator PR #99) reaches README, Path, the
  practices, and both guides; the QSFP copy procedures stay, marked for a named borrow only.
  Supersedes setup's "install on both GB10s, benchmark on gb10-1 with a cross-check on gb10-2".
- bench-gb10-container: the walkthrough is the API probes from each API page plus one cell per
  engine from the finding's method; rejected probes alone.
- bench-gb10-container: concurrency swept on gpt-oss-120b, both engines, 16 slots, 1/4/16/32
  streams, 60 s a level; rejected gemma-4-26B-A4B.
- bench-gb10-container: quantization pairs on gemma-4-E4B, single stream (llama.cpp QAT Q4_0
  against Q8_0; vLLM QAT w4a16 against BF16); rejected no pairs.
- bench-gb10-container: a vision cell on gemma-4-26B-A4B, one synthetic 720p JPEG plus 200 text
  tokens, 64 out, 1 x 8 and 4 x 32, with GuideLLM's vision extra; rejected a probe alone.
- bench-gb10-container: an embedding cell on EmbeddingGemma 2, 512-token inputs, 1 and 16
  streams, 30 s each; rejected a probe alone.
- bench-gb10-container: vLLM's order is 26B-A4B (A', B', vision), the FlashInfer diagnostic, E4B
  BF16, E4B w4a16, 12B, 31B, EmbeddingGemma 2, gpt-oss-120b at 16 sequences (its cells and the
  sweep); gpt-oss serves at 16 sequences once, saving a cold start.
- bench-gb10-container: vLLM's pin ends on Gemma 4 26B-A4B NVFP4 with its anchor flags, so the
  pin and the anchor stay one thing for vllm-gb10-native.
- bench-gb10-container: API probes per surface on one model on both engines: tools, reasoning,
  Anthropic messages with a tool, and responses on gpt-oss-120b; vision on 26B-A4B; embeddings on
  EmbeddingGemma 2; transcription probed on llama.cpp with E4B and recorded on paper for vLLM,
  which implements it for Granite Speech, Whisper, and Voxtral but not Gemma 4.
- bench-gb10-container: the session runs routine host steps on gb10-1 over SSH, without root
  (downloads and image pulls, engines install, update, and uninstall, model loads, readiness
  waits, cold-start timing, log and memory read-outs, health and version checks, tailscale ping),
  and the administrative actions pre-staging brings; rejected the architect typing every host
  step. At the architect's request (2026-10-26).
- bench-gb10-container: the session runs GuideLLM cells from the laptop in the architect's view,
  printing each command first; rejected the architect typing each cell.
- bench-gb10-container: the architect installs once on gb10-1 a sudoers rule allowing exactly
  `/usr/sbin/sysctl vm.drop_caches=3` without a password; the setup guide gives its install and
  removal; rejected the architect typing it before every load.
- bench-gb10-container: the architect keeps root, a new tool's or concept's first walk, the final
  walkthrough, and every escalation's decision.
- bench-gb10-container: the session split lands in the coordinator from this session, on
  `plan-hosting-session-split` at BUILD's start, with no separate plan session; this Decision
  governs the spike until it merges. At the architect's request.
- bench-gb10-container: every command a session or the architect runs on a host appears in a
  guide or the finding's method exactly as run, and is run from that text; rejected unrecorded
  diagnostic commands.
- bench-gb10-container: hf pinned at an exact version, with uv, in a host mise env in the spike's
  clone on gb10-1, run as `hf download` into /srv/models, and covered by currency; this task's
  one new tool. Reverses llama-gb10-container's rejection of the hf CLI: it is installed by mise
  with no root, and works before any engine image is pulled and on llama.cpp-only hosts.
  Rejected running hf from vLLM's image, at the same download speed.
- bench-gb10-container: every model file and both images pre-staged in parallel at BUILD's first
  host step; no cell or timed load runs until all finish; rejected cells on present models
  during downloads, whose network, disk, and CPU load would add noise.
- bench-gb10-container: a vLLM model switch names the model to update for one run
  (`VLLM_MODEL=<id> engines/engines vllm update`), with no commit; the pin stays the host's
  default and the whole-command comparison stays. Amends vllm-gb10-container's "changing the
  model means a pin edit and an update". Rejected compose, which saves none of the 4–6 min cold
  start, can't refuse beside the other engine, and is a new tool, and rejected a commit per
  switch.
- bench-gb10-container: ASR measured as gemma-4-E4B's audio through chat on both engines, with
  GuideLLM's audio extra; rejected Granite Speech 4.1 2B through /v1/audio/transcriptions, which
  adds a model and a cold start for an endpoint set A's consumers don't use.
- bench-gb10-container: Gemma 4 as a cheaper chat tier beside gpt-oss-120b goes to
  spike-model-benchmarks (quality) and spike-model-gateway (routing); this task adds no cells for
  it, and the finding sets 26B-A4B beside gpt-oss-120b in one speed table.
- bench-gb10-container: the coordinator PR carries the session split, all six pending edits, the
  two tier edits, and this task's new tool, emptying Pending edits; rejected the rule change
  alone.
- bench-gb10-container: llama.cpp's preset sets `verbosity = 4`: b11669 logs no buffer sizes at
  its default of 3, so gpt-oss-120b's first load (47.7 s) was redone (47.6 s) to record them.
- bench-gb10-container: the sweep's levels at 4 streams and more complete only their first wave
  in 60 s, so the finding reads GuideLLM's `total` output rate and TTFT; the level length stays as
  agreed.
- bench-gb10-container: vLLM's EmbeddingGemma 2 row kept, though it doesn't start on GB10 at
  v0.32.0: Triton's encoder attention needs 160 KiB of shared memory and SM121 has 99 KiB. Marked
  unsupported per the brief; another attention backend not tried, as beyond the brief.
- bench-gb10-container: the FlashInfer diagnostic left NVFP4 decode unchanged (30.0 against 30.5
  tok/s), so the attention backend isn't the cause. The NVFP4 path on SM121 is the suspect,
  untested here; a candidate question for vllm-gb10-native's plan round.
- bench-gb10-container: vLLM decodes audio with the image's torchcodec, so no derived image; the
  brief's BUILD check settled it without an escalation.
- bench-gb10-container: the vision probe reads its base64 from a file with `--rawfile`; as a jq
  argument it exceeds the argument-list limit.
- bench-gb10-container: a file that failed twice under Xet completed with `HF_HUB_DISABLE_XET=1`;
  llama.cpp's models guide gives the fallback.
- bench-gb10-container: gpt-oss-120b's vLLM stage line excludes only the weights in `original/`
  and `metal/` (`--exclude "original/*.safetensors" --exclude "metal/*"`): the earlier
  `original/*` exclusion made vLLM fetch three config files (~57 KB) at its start. vLLM has no
  offline guard like llama.cpp's preset; adding one is left to a later task.
- bench-gb10-container: the walkthrough's instructions omitted the per-model warm-up, so
  llama.cpp's A ran cold (TTFT p95 735 against 436 ms, decode unchanged); the finding records it,
  and its walkthrough procedure names the warm-up.
- bench-gb10-container: behavior 21's Pending edits were emptied by PR #100. The `engines/`
  rename edit arrived after the brief, at spike-ai-pipeline's request, and stays pending for a
  later coordinator change; it isn't this task's.
- bench-gb10-container: gb10-1 left with llama.cpp serving gpt-oss-120b and vLLM stopped on its
  pin. Superseded by round 5's end state, below.

- bench-gb10-container: embeddings on granite-embedding-english-r2 (IBM, Apache-2.0, ModernBERT,
  head size 64), BF16 on both engines; rejected EmbeddingGemma 2, which didn't serve on vLLM
  v0.32.0 on SM121, and harrier-oss-v1-270m (community GGUFs only). This task ran only the row's
  default Triton backend, which failed with OutOfResources (shared memory 163840 against 101376).
  vLLM #60847 reports FLASH_ATTN failing with "head size not supported" on GB10 and FLASHINFER
  lacking encoder-only attention, and FLEX_ATTENTION failing on other GPUs, not reported on SM121;
  its fixes, #60631, #60848, and #60942, are open. Architect's redirect at the brief: no gap in the
  finding.
- bench-gb10-container: llama.cpp's embedding cell reruns on granite so both engines pair.
- bench-gb10-container: EmbeddingGemma 2 struck from the spike's model set, kept as a dated
  engine-limit note; at the architect's request, it should no longer be set A's embedding model
  (a coordinator note; spike-model-hosting and spike-ai-pipeline are not this spike's to change).
  Supersedes "vLLM's EmbeddingGemma 2 row kept".
- bench-gb10-container: the finding's cleanup covers the walkthrough's cold anchor A (rerun
  warm), vLLM's gpt-oss A 7 of 8 (rerun, cell A alone, per-request output kept), and the "not
  recorded" figures; vLLM transcription on paper, the NVFP4 cause, and vLLM's offline guard stay
  where the record put them.
- bench-gb10-container: granite's vLLM row runs its attention on FLASH_ATTN. vLLM returns
  granite's embeddings unnormalized (norm about 30; granite ships no Normalize module), and
  llama.cpp normalizes them by default; the finding and both API pages record it. Making vLLM
  normalize is a configuration change, left out as beyond the brief.
- bench-gb10-container: on granite, vLLM's embedding rate scales with streams (55.5 to 295.1
  requests/s, 5.3 times) and llama.cpp's doesn't (58.7 to 55.5).
- bench-gb10-container: the warm rerun of llama.cpp's anchor A confirms the walkthrough's 735 ms
  TTFT p95 was the cold first request (478 ms warm).
- bench-gb10-container: vLLM's gpt-oss-120b A recorded 7 of 8 because GuideLLM finalized with the
  eighth request in flight (`scheduler_state` processing 1); the rerun recorded 8 of 8, its decode
  identical.
- bench-gb10-container: round 5's reruns of llama.cpp's warm A and vLLM's gpt-oss-120b A took no
  `tailscale ping`; the finding marks their path "not taken", with the reason that every ping this
  session read direct, at 0 to 2 ms.
- bench-gb10-container: set A's embedding note landed as coordinator PR #103 (branch
  `plan-hosting-set-a-embedding`), worded to what vLLM #60847 and the run show.
- bench-gb10-container: gb10-1 left with vLLM serving its pin and llama.cpp stopped. Supersedes
  "gb10-1 left with llama.cpp serving gpt-oss-120b and vLLM stopped on its pin".
- llama-gb10-native: the `engines/` rename task is planned and run before this task, which waits
  with its approved brief; the rename's plan keeps this brief.
- llama-gb10-native: native llama.cpp is ggml's CUDA 13.4 arm64 Linux prebuilt with its CUDA
  runtime tarball, sha256-checked: the container's exact build, so only the hosting method
  differs; no cmake (strix-native's).
- llama-gb10-native: a system unit after personal-agents' "Run it as a service" (User=jaime,
  `current` link, requires tailscaled, tailnet address at start, port 8080), enabled only while
  native llama.cpp serves; a user unit can't depend on tailscaled.
- llama-gb10-native: builds under a jaime-owned /opt/llama.cpp, created once by the architect, so
  updates need no root.
- llama-gb10-native: a sudoers rule for exactly `systemctl start|stop|restart|enable|disable
  llama-router`; the architect installs the unit and runs daemon-reload.
- llama-gb10-native: native install, update and uninstall are idempotent `engines` steps sharing
  the container's preset, store and port.
- llama-gb10-native: pins and reports lead with semver (v0.6.0 install, update to v0.7.0); a
  b-build stays installable; container and native steps take the same version argument; earlier
  findings stay as written.
- llama-gb10-native: llama-bench pp512/tg256, 5 repetitions, on gpt-oss-120b and gemma-4-26B-A4B,
  native and in ggml's full-cuda13 image; container then native anchors A and B; one cold load of
  gpt-oss-120b per hosting method.
- llama-gb10-native: the task ends with native llama.cpp, the llama container and vLLM all stopped
  and disabled; the next task stands up what it needs.

- host-rename: the suite's directory becomes `host/`; rejected `suite/` and `sbin/`. Its
  scripts run only on the hosts, beside `mise.host.toml`, and spike-ai-pipeline's copy moves to
  `host/` too.
- host-rename: the findings' script paths are rewritten, each finding noting the rename commit,
  so their methods still run as written; rejected leaving them as run. No result changes.
- host-rename: hosts brought current at every session start, this task included though it
  measures nothing; rejected skipping it for a task without measurement. At the architect's
  request (2026-10-27).
- host-rename: gb10-1 brought current on 2026-10-27, CDI spec regenerated, no reboot pending:
  DGX OS 7.6.0, driver 580.178.04, CUDA 13.0, kernel 7.0.0-1019-nvidia, Docker 29.6.2, NVIDIA
  Container Toolkit 1.20.1.
- host-rename: the rename rebuilds gb10-1's stale llama container itself; rejected leaving it to
  llama-gb10-native, which stays native setup and benchmarking. At the architect's request.
- host-rename: llama's update also replaces a container whose preset mount isn't the clone's,
  without a pull; rejected uninstall then install, which re-pulls the image.
- host-rename: gb10-1 is left with llama and vLLM both stopped, for llama-gb10-native's
  bare-metal build; rejected leaving llama serving. At the architect's request.
- host-rename: takes uv 0.13.6, so llama-gb10-native's behavior 1 and slice 1 drop uv.
- host-rename: llama-gb10-native's approved brief (1985f98) is restored to Task brief at
  host-rename's SHIP; rejected recovering it from git history at its start.
- host-rename: spike-ai-pipeline's follow-up is its task `host-scripts`, after client-core, in
  the coordinator roadmap (PR #104); this spike doesn't touch spike-ai-pipeline or gb10-2.
- host-rename: llama's install checks the preset mount before the image, so a container stale in
  both gets the mount message; both messages point at update.
- host-rename: a container with no `/etc/llama-preset` mount counts as stale, printed as `none`.
- host-rename: update's replacement runs the new container even when the old one was stopped, as
  an image change already did; the update guide says so.
- host-rename: the mount check is an exact string match against `LLAMA_PRESET_DIR`, the string
  `llama_run` mounts, not symlink-resolved; gb10-1's second update read it as matching.
- host-rename: the old directory is named only in this record's history, the three findings'
  rename notes, and the update guide's stale-mount example (behavior 4 needs a concrete case);
  the scripts' comments describe the move generically. README.md and STANDARDS.md never named it.
- host-rename: each finding's rename note is one sentence, wrapped to 100 columns.
- host-rename: gb10-1 left on 2026-10-27 with llama and vLLM both stopped: llama rebuilt at b11669
  mounting the clone's `host/llama-preset` (clone at ~/repos/spike-model-engines, on the
  host-rename branch until the merge), vLLM stopped on its pin (v0.32.0). Supersedes
  bench-gb10-container's "gb10-1 left with vLLM serving its pin and llama.cpp stopped".

- llama-gb10-native: llama-bench is a section of the llama.cpp setup guide, not a page of its
  own, since STANDARDS.md fixes the guide's pages.
- llama-gb10-native: the unit reads models.ini through an `/opt/llama.cpp/preset` link to the
  clone's `host/llama-preset`, so the unit names neither a build nor the clone's path.
- llama-gb10-native: native install and update wait up to 60 s for `/health`, and update keeps
  the old build until the new one answers.
- llama-gb10-native: native install starts an installed but stopped `llama-router`.
- llama-gb10-native: the container steps, llama's and vLLM's, also refuse while `llama-router`
  is up.
- llama-gb10-native: the native fetch is quiet (`curl -fsSL`), like the repository's other curls.
- llama-gb10-native: the finding records `tailscale ping` as the path only, with the addresses
  left out, since tailnet and LAN addresses stay out of the public repository.
- llama-gb10-native: native and container measured level: llama-bench within its ±, anchor B
  identical, cold load 47.2 against 47.3 s, footprint within 28 MiB. Anchor A ran 2% lower
  natively in one run, which llama-bench didn't reproduce.
- llama-gb10-native: one laptop `/health` was refused right after the first update, unexplained;
  every later check answered ok.
- llama-gb10-native: native install and update read `api.github.com` on every fetch, whose
  unauthenticated limit is 60 requests an hour per IP; noted, not changed.
- llama-gb10-native: gb10-1 left on 2026-10-27 with nothing serving: `llama-router` inactive and
  disabled at v0.7.0 (b11669) under /opt/llama.cpp, the llama container stopped
  (server-cuda13-b11669), vLLM stopped on its pin (v0.32.0); full-cuda13-b11669 pulled.
  Supersedes host-rename's "gb10-1 left on 2026-10-27 with llama and vLLM both stopped".
- vllm-gb10-native: native vLLM is uv virtualenvs, one per release, under a jaime-owned
  /opt/vllm, with uv at the host env's pinned version; rejected mise's pipx backend, whose install
  path in the home directory the unit would have to name.
- vllm-gb10-native: torch from PyTorch's cu130 index (`--torch-backend=cu130`), the image's torch
  source; rejected uv's driver-detected `auto` and PyPI's separate torch build.
- vllm-gb10-native: native Python is uv-managed CPython 3.12, the image's, held with that reason
  and asked again when the image's Python moves; rejected 3.14.
- vllm-gb10-native: the unit reads the row's model and flags at start from a file under /opt/vllm
  that install and update write from the rows; rejected fixing the row in the unit, which would
  make every row switch a root step.
- vllm-gb10-native: uv's first walk is the architect's scripted native install of v0.31.0 from
  the guide plus a uv read-back, with a uv section in the setup guide; rejected building a venv by
  hand first.
- vllm-gb10-native: container A' and B' rerun warm at v0.32.0, then native A' and B' at the same
  load on the pin row; rejected A' alone.
- vllm-gb10-native: one cold start per hosting method on the pin row, from a dropped page cache
  with its compile cache warm, with native's first start recorded beside them; rejected empty
  compile caches and gpt-oss-120b (577 s, close to the 10-minute cap).
- vllm-gb10-native: one diagnostic native A' with `--moe-backend marlin` on the pin row; rejected
  flashinfer_b12x, which vLLM keeps out of auto-selection on SM121, and no diagnostic.

## Pending edits

(PR #100, merged 2026-10-26, carried every edit tasks 1–3 owed until then. PR #104 carried the
`engines/` rename's roadmap edit.)
