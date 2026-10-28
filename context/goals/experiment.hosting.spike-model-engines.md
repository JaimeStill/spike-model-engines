# goal · experiment.hosting.spike-model-engines

- **State:** building
- **Task:** vllm-strix
- **Branch:** vllm-strix

## Tasks

1. [x] llama-gb10-container
2. [x] vllm-gb10-container
3. [x] bench-gb10-container
4. [x] host-rename
5. [x] llama-gb10-native
6. [x] vllm-gb10-native
7. [x] llama-strix-rocm
8. [ ] vllm-strix
9. [ ] strix-native (dropped by llama-strix-rocm's verdict; leaves the manifest with the pending edit)
10. [ ] answer

## Task brief · vllm-strix

Approved 2026-10-28.

Problem
  vLLM has run only on gb10-1, in vLLM's CUDA image and natively. So the
  spike can't yet say whether vLLM serves the Framework's Strix Halo at
  all, or how it compares there with llama.cpp in ggml's Vulkan image,
  which led llama-strix-rocm (evidence 1, 2). This task applies the GB10
  vLLM standards to the Framework, changed only where AMD needs it. It
  proves first that vLLM's official ROCm image (this task's one new tool)
  serves gpt-oss-120b on gfx1151. It then measures vLLM there against
  llama.cpp's Vulkan image, cell for cell, in one session, with llama.cpp
  moved to its current pin, v0.8.0 (b11960). strix-native has dropped,
  and the answer task reads this task's finding. The session owns the
  Framework.

Behaviors
  1. llama.cpp's pin moves to v0.8.0 (b11960). The llama.cpp guide names
     it, currency then reports only held items, and the check passes. On
     the Framework, `host/engines llama update` at flavor vulkan serves
     the new build, and /props reads b11960.
  2. The Framework is brought current by the architect's `omarchy
     update`. An installed kernel newer than the running one is recorded
     as a pending reboot.
  3. The engines suite's vllm group gains a flavor: cuda on the GB10s,
     rocm on the Framework. With none given, it follows the GPU the host
     has: rocm on an AMD GPU, cuda otherwise.
     - The flavor picks three things: the image, vllm/vllm-openai:<release>
       or vllm/vllm-openai-rocm:<release>; the device flags, --gpus all,
       or /dev/kfd and /dev/dri with no group, seccomp or ptrace flags;
       and the default row.
     - Both flavors keep --ipc host. An unknown flavor is refused.
     - Install and update compare the whole image and command, so they
       refuse, replace and report as they do now.
     - A host with no AMD GPU resolves to today's image, flags and
       default row, so gb10-1 is unchanged.
  4. The Framework's default row is gpt-oss-120b. gb10-1's stays Gemma 4
     26B-A4B NVFP4. Every row keeps --gpu-memory-utilization 0.80 on both
     host classes, so the rows stay one set.
  5. The rows gain the shape set's ROCm-servable formats: Gemma 4
     26B-A4B BF16 with its vision encoder, and Gemma 4 31B QAT w4a16
     (Google's). E4B BF16, E4B QAT w4a16, 12B QAT w4a16, granite BF16 and
     gpt-oss-120b are already rows.
  6. The suite's shared messages name no host class. The one-engine-per-
     host reason reads in terms of any host's GPU memory. A unit's
     refusal hint names `sudo systemctl stop <unit> && sudo systemctl
     disable <unit>` without -n, which also holds where no NOPASSWD rule
     exists, as for spike-model-hosting's llama-router.
  7. Viability is the architect's first walk of vLLM's ROCm image.
     - A one-off run of vllm/vllm-openai-rocm:v0.32.0 with /dev/kfd and
       /dev/dri runs the image's `rocminfo`, which reads back the device
       as gfx1151 and its memory pool's size. vLLM's first start then
       logs the total it sizes against. Both are recorded beside the GTT
       ceiling. No Python is authored for the read-back.
     - `host/engines vllm install` then starts the gpt-oss-120b row on
       port 8000 of the tailnet address. Its first start, from an empty
       compile cache, reaches ready within 20 minutes with every weight
       on the GPU. It then serves warm anchor A from the laptop.
     - If any of these fails, the failure is recorded with its reason
       and log, and BUILD escalates at once, with no retry under
       --enforce-eager or any other setting.
  8. One engine per host holds on the Framework. vllm's install and
     update refuse while llama runs or any llama-router or vllm-server
     unit is active, and llama's refuse while vllm runs.
  9. Before any comparison cell or timed start, everything is staged in
     parallel through the hf host env on the Framework: every model the
     vLLM rows name, gpt-oss-120b staged so its start reads only the
     store; and the images, vllm/vllm-openai-rocm:v0.32.0 and ggml's
     b11960 Vulkan server image.
  10. vLLM's cold start is measured per row.
      - Each row's first start fills its compile cache and is recorded.
        Then one timed start runs from a dropped page cache with the
        compile cache warm.
      - Each start records MemAvailable, GTT and VRAM in use (sysfs, no
        root), before and after, beside the memory vLLM logs: weights,
        KV cache, and the total it sized against.
  11. vLLM's GuideLLM cells run per row, each model warmed first, at
      llama-strix-rocm's loads:
      - anchors A (1 x 8) and B (4 x 32) on gpt-oss-120b;
      - E4B BF16 and E4B QAT w4a16 at one stream, the quantization pair;
      - 12B QAT w4a16 at A and B;
      - 31B QAT w4a16 halved (1 x 4, 4 x 16);
      - 26B-A4B BF16 at A, B and vision;
      - granite BF16 at 1 and 16 streams;
      - E4B audio through chat.
      A cell vLLM can't serve on gfx1151 is marked unsupported, with its
      reason.
  12. llama.cpp's whole Vulkan set from llama-strix-rocm, each model's
      load and footprint and then its cells, reruns at b11960 in the
      same session from that finding's method. Its anchors A and B are
      set beside v0.7.0's 45.13 and 77.67 tok/s, and a move beyond run
      noise is a finding.
  13. The finding sets every vLLM cell beside its same-session llama.cpp
      Vulkan cell: output tok/s, TTFT, ITL, cold start or load, and
      footprint. It states no verdict, since the answer task decides.
  14. Every result records the engine version (vLLM's /version,
      llama.cpp's /props build_info), the flavor and image, and the host
      stack: Omarchy, kernel, Mesa, linux-firmware, Docker, the GTT
      ceiling, and each image's ROCm. It also records the laptop's path
      (tailscale ping) and the model state. No run exceeds 10 minutes,
      except vLLM's first start on gpt-oss-120b on the Framework, which
      has 20. Any other start past 10 minutes is an escalation.
  15. The vLLM guide gains Framework sections, not files:
      - setup: the root steps already in place, the first walk's
        read-back, and the flavor;
      - models: the ROCm rows and staging through hf on the Framework;
      - update and uninstall: the release, on each flavor.
      The README's "Running on the Framework" gains vLLM's practices, and
      the Path's task 7 states its result. The finding is vllm-strix's,
      under the findings.
  16. At the end, the vllm container and the llama container (at flavor
      vulkan, b11960) are stopped by hand, so neither starts at boot. The
      router stays stopped and disabled, nothing serves on 8000 or 8080,
      and the record's host line says so.
  17. At SHIP, one coordinator PR carries the goal's pending edits (the
      strix-native delete and the summary and ai-hosting.md edits) and
      vllm-strix's own, emptying Pending edits.

Test seams
  vLLM's HTTP API on framework:8000 and llama-server's on framework:8080,
  as GuideLLM and curl call them from the laptop, and the engines vllm
  and llama commands' output and Docker's state on the Framework.

Slices
  1. Upgrade (behavior 1). The session moves llama.cpp's pin to v0.8.0
     (b11960) and its guide's version, and runs check and currency. Once
     ggml publishes the b11960 images, it pulls the Vulkan server image
     and updates the Framework's llama at flavor vulkan; until then only
     the host step waits. Demo: currency reports only held items, and
     /props reads b11960.
  2. vLLM ROCm viable (behaviors 2–8). The architect runs `omarchy
     update`, then the first walk from the guide written on the branch:
     the rocminfo read-back, then the install and the first start. The
     session first writes the flavor, the rows and the messages. It
     stages gpt-oss-120b, reads each step back, checks the refusals,
     then warms the model and runs anchor A in the architect's view.
     Demo: vLLM's anchor A served from the laptop, or a recorded failure
     and an escalation.
  3. The comparison (behaviors 9–14, 16). The session stages every model
     and image in parallel. It then runs each vLLM row's first and timed
     starts, its read-outs and its cells, then llama.cpp's Vulkan set at
     b11960, printing each command first in the architect's view, then
     stops everything. Demo: the finding, with its paired served, cold-
     start and footprint tables.
  4. Walkthrough (behaviors 15, 17). The architect installs vLLM at
     flavor rocm from the guide and runs warm anchor A on vLLM and on
     llama.cpp's Vulkan from the finding's method. The architect leaves
     the end state, and SHIP opens the coordinator PR.

The split
  The architect: `omarchy update` and any root step; the first walk of
  vLLM's ROCm image (the read-back, the install, the first start); the
  last slice's walkthrough; every escalation's decision.
  The session, over Tailscale SSH without root: the pin move, image pulls
  and hf downloads, the engines install, update and uninstall, starts and
  their timing, page-cache drops through the existing sudoers rule, log
  and memory read-outs, and health and version checks. From the laptop,
  in the architect's view, it runs every GuideLLM cell, printing each
  command first.

Out of scope
  ROCm tuning settings: --enforce-eager, attention or MoE backends,
  memory shares other than 0.80. Native vLLM or llama.cpp on the
  Framework (strix-native dropped). llama.cpp's ROCm flavor and
  llama-bench. The concurrency sweep and the API probes on the Framework.
  NVFP4 on ROCm. Any host step on gb10-1 or gb10-2. Retiring the router
  (the answer task's). personal-agents' and spike-model-hosting's docs.
  Rewriting earlier findings.

Door
  Two-way. The pin moves back with an edit and an update. The flavor is
  resolved per host, so gb10-1 is unchanged. vLLM's image and container
  go with uninstall, and models with the typed delete. No root step is
  added. Nothing is released.

## Progress

slices 4/4 · standards done · spec done (two passes) · editor done

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
- vllm-gb10-native: the unit is `vllm-server`, the command group `vllm-native`, and /opt/vllm
  holds `<release>` virtualenvs, `current`, `row`, `python` (uv's CPython), and `cache` (uv's and
  the compile caches).
- vllm-gb10-native: v0.31.0 has no `vllm download-kernels`, so its kernel step runs FlashInfer's
  own `python -m flashinfer download-kernels`, which the vLLM command wraps.
- vllm-gb10-native: the caches move with TRITON_HOME and FLASHINFER_WORKSPACE_BASE; TRITON_CACHE_DIR
  stays unset, so each torch.compile cache keeps its own Triton cache, as in the container.
- vllm-gb10-native: the unit is Type=simple with no TimeoutStartSec, since vLLM sends systemd no
  readiness; the `engines` commands' 10-minute `/health` wait bounds the start.
- vllm-gb10-native: the uv preflight is `mise which uv`, which fails without the pinned uv;
  `mise exec -- uv --version` fell back to any uv on the PATH (standards fix).
- vllm-gb10-native: the Marlin row, `gemma-4-26B-A4B-NVFP4-marlin`, keeps vision (no
  `--language-model-only`), so only the MoE backend differs from the pin's row.
- vllm-gb10-native: the container guide's ready line reads only since the container's start: a
  restarted container's `grep -m 1` returned 2026-10-26's line. A defect found in the run, fixed
  though no behavior asked for it.
- vllm-gb10-native: the guides' uv read-backs set `UV_CACHE_DIR=/opt/vllm/cache/uv`; the two
  `~/.cache/uv` interpreter entries the earlier read-backs wrote on gb10-1 are left in place.
- vllm-gb10-native: the container's install hint names `engines vllm update` without the release
  install was given, where native's now names it; a standards-review note, left.
- vllm-gb10-native: native and container serve level: A' 29.4 against 29.8 and B' 102.7 against
  104.5 tok/s, 1.3 to 1.7% lower, within the container's own 1.0 to 1.4% move since 2026-10-26.
- vllm-gb10-native: native's warm start takes 334 s against the container's 197.4, both from a
  dropped page cache: native never saves FlashInfer's MoE autotune file and tunes again for 155 to
  179 s every start, where the container loads its 34 saved configs. The cause is not
  established; a candidate question for a later task.
- vllm-gb10-native: Marlin's A' ran 30.1 against 29.4 tok/s (+2.4%), within the A' runs' range,
  so the NVFP4 MoE kernel doesn't explain vLLM's slow NVFP4 decode on SM121.
- vllm-gb10-native: footprints are equal, 100.5 to 100.9 GiB of MemAvailable, with 18.13 GiB of
  weights on both.
- vllm-gb10-native: native's first start, from an empty compile cache and a dropped page cache,
  took 384 s and saved its AOT compile; the compile caches outlive a release's removal, so a
  rollback's start loads its compile (0.30 s against 27 s).
- vllm-gb10-native: the walkthrough reproduced native: `walk-a` 29.4 tok/s, ITL 33.21 ms; its
  four starts, 330 to 370 s, kept the walk's shape.
- vllm-gb10-native: `uninstall` empties `/opt/vllm/cache`, uv's cache with it, so a reinstall
  downloads all 199 packages and the kernel wheels again and compiles afresh.
- vllm-gb10-native: gb10-1 was current at the session's start (0 upgradable, no reboot pending),
  so no upgrade.
- vllm-gb10-native: gb10-1 left on 2026-10-27 with nothing serving: `vllm-server` inactive and
  disabled at v0.32.0 under /opt/vllm (the pin's row), `llama-router` inactive and disabled at
  v0.7.0 (b11669), the llama and vllm containers exited (server-cuda13-b11669, and
  vllm/vllm-openai:v0.32.0 on its pin), stopped by hand so neither starts at boot; clone at
  ~/repos/spike-model-engines on the vllm-gb10-native branch until the merge. Supersedes
  llama-gb10-native's "gb10-1 left on 2026-10-27 with nothing serving".
- llama-strix-rocm: the GB10 standards apply to the Framework, adapted only where AMD needs it;
  containerized llama.cpp's viability comes first; the baseline is the semver pin v0.7.0
  (b11669), movable by b-build; every strix session owns the Framework (architect, r1).
- llama-strix-rocm: the GB10 conventions carry to the Framework as-is or adapted (AMD devices for
  --gpus, an image flavor, the host stack record, "Running on the Framework"); llama-native, the
  CDI spec and the vLLM-only practices don't apply here.
- llama-strix-rocm: the page-cache drop is a sudoers rule for exactly /usr/bin/sysctl
  vm.drop_caches=3, as on gb10-1.
- llama-strix-rocm: the footprint adds GTT in use from sysfs (mem_info_gtt_used) to MemAvailable
  and the engine's logged buffers.
- llama-strix-rocm: the architect brings the Framework current with `omarchy update`; rejected
  `pacman -Syu`.
- llama-strix-rocm: jaime joins the docker group and docker is enabled at boot, as on gb10-1;
  rejected socket activation alone and rootless Docker.
- llama-strix-rocm: spike-model-hosting's llama-router is stopped and disabled for the session,
  and left so after it; retiring it belongs to strix-native, or the answer task if strix-native
  drops (r2 q3).
- llama-strix-rocm: ggml's ROCm image is compared against ggml's Vulkan image b11669 in the same
  llama container, plus llama-bench from ggml's native Vulkan prebuilt b11669 in jaime's home,
  since Vulkan's driver ships in the image (Ubuntu's Mesa 26.0 against the host's 26.2.5); Path
  task 6 reads "ggml's ROCm image against ggml's Vulkan image" (r2 q1).
- llama-strix-rocm: one llama group with a flavor setting (cuda13 on the GB10s, rocm or vulkan on
  the Framework, defaulting by the GPU found), switched by `LLAMA_FLAVOR=<flavor> host/engines
  llama update`; device flags follow the flavor; rejected llama-rocm and llama-vulkan groups
  (r2 q2). Update keeps the same build's other flavor, so a switch re-pulls nothing (decided at
  the brief's approval).
- llama-strix-rocm: if ggml's ROCm image doesn't run on gfx1151 (no device, gpt-oss-120b not fully
  on the GPU, or anchor A won't serve), the failure is recorded and BUILD escalates at slice 1;
  rejected measuring Vulkan alone (r2 q5).
- llama-strix-rocm: llama-bench is gb10-1's matrix (gpt-oss-120b MXFP4, Gemma 4 26B-A4B QAT Q4_0,
  pp512/tg256, 5 repetitions, flash attention on) plus depth 8192 (-d 0,8192) (r2 q6).
- llama-strix-rocm: GuideLLM runs anchors A and B plus bench-gb10-container's shape set on both
  flavors, about 28 cells (r2 q7).
- llama-strix-rocm: "ROCm leads" means both anchors' served output tok/s ahead of Vulkan's by
  more than 3%; a split or within 3% is no lead, strix-native drops, and vllm-strix compares with
  Vulkan (r2 q8).
- llama-strix-rocm: /srv/models is a plain jaime-owned directory on the Framework's root drive, as
  on the GB10, seeded by a local copy of gpt-oss-120b and E4B Q8_0 from /mnt/models/hf-cache;
  /mnt/models stays the router's, untouched; rejected a link to the router's cache and mounting
  the models drive at /srv/models (r2 q4, r3 q1).
- llama-strix-rocm: the GTT ceiling is all physical RAM, 125 GiB, as on the GB10 (amd-ttm --set
  125, ttm pages_limit 32768000; amdgpu gttsize=128000; limine-mkinitcpio; reboot), the
  architect's root step at BUILD's start; rejected 96 and 112 GiB, and clearing the options,
  which falls to the kernel's half of RAM (~62.5 GiB); personal-agents' preparation doc is the
  architect's to update (r3 q2, r4 q1).
- llama-strix-rocm: the GTT ceiling is 112 GiB, not 125 (architect, slice 1): amd-ttm warned that
  125 exceeds 90% of RAM (112.57 GB) and could destabilize the host, and the architect judged
  112 the safer setting, keeping ~13 GiB for the host; pages_limit 29360128, gttsize 114688.
  Supersedes the 125 GiB decision above.
- llama-strix-rocm: the laptop reaches a container's port 8080 on the Framework through a ufw route
  rule, `ufw route allow in on tailscale0 proto tcp to any port 8080`, since Omarchy's ufw with
  ufw-docker drops routed traffic to published ports; it names no container, so it holds across
  flavor switches; the architect also added the same rule for 8000, vLLM's container port, so
  this task's guide documents both; rejected `ufw-docker allow llama` (bound to one
  container) and `--network host` (changes the GB10's docker run) (architect, escalation, slice 1).
- llama-strix-rocm: slice 1's viability: full-rocm-b11669 lists ROCm0, Radeon 8060S gfx1151, with
  114688 MiB, the whole GTT ceiling; server-rocm-b11669 loaded gpt-oss-120b in 16 s with 37/37
  layers offloaded (ROCm0 model buffer 59852 MiB; GTT used 64.6 GB) and served warm anchor A
  (8/8 requests, 42.7 output tok/s, TTFT p95 679 ms, ITL median 20.9 ms; path direct 2 ms). The
  cell's before-metrics snapshot came back empty, so its server figures include the warm-up;
  slice 3 reruns the anchors on both flavors.
- llama-strix-rocm: slice 2's demo (2026-10-27): `host/engines llama install` picked rocm by the
  AMD vendor id and ran with /dev/kfd and /dev/dri; `LLAMA_FLAVOR=vulkan ... update` moved it to
  server-vulkan-b11669 with /dev/dri alone, which loaded gpt-oss-120b 37/37 on Vulkan0 (RADV
  STRIX_HALO, 115200 MiB, the GTT ceiling plus the 512 MiB carve-out), build b11669-620d2225c;
  update moved it back; install refused a flavor switch and an unknown flavor; all four b11669
  images kept. Staging 17:37–18:17: five models (~48 GB), the four images, and the native Vulkan
  prebuilt (sha256 OK, `Vulkan0 ... 115200 MiB`), every log `exit 0`.
- llama-strix-rocm: the session starts the Framework's background downloads with `setsid` and
  `< /dev/null` beside the guide's `nohup`, since a job launched over a non-interactive SSH
  command otherwise dies with it; and a `pgrep -f` run through `ssh host '...'` matches its own
  command line, so a wait loop checks the logs' `exit` lines instead.
- llama-strix-rocm: the verdict (2026-10-27): ROCm doesn't lead. Vulkan's container beat ROCm's on
  both anchors' output tok/s (A 45.13 vs 42.42, +6.39%; B 77.67 vs 73.83, +5.21%), so strix-native
  drops and vllm-strix compares with Vulkan, llama.cpp's leading Strix backend. ROCm led on every
  cold load, both vision cells and granite at 1 stream; Vulkan on all llama-bench rows, every text
  cell and granite at 16 streams (docs/findings/llama-strix-rocm.md).
- llama-strix-rocm: the Framework left on 2026-10-27 20:02 with nothing serving: `llama` at
  server-rocm-b11669, stopped by hand (unless-stopped, so it stays stopped at boot), llama-router
  inactive and disabled, port 8080 free; all four b11669 images, the native Vulkan prebuilt at
  ~/llama.cpp/b11669-vulkan, and every model in /srv/models kept; clone at
  ~/repos/spike-model-engines on llama-strix-rocm until the merge.
- llama-strix-rocm: the architect's walkthrough (2026-10-28, from the guide at 6eee651): install
  at rocm, `LLAMA_FLAVOR=vulkan ... update` (/dev/dri), llama-bench full-vulkan on 26B-A4B (pp512
  2055.80 ± 5.61, tg256 71.38 ± 0.07, against the slice's 2040.48 and 71.37), anchor A on Vulkan
  (8/8, 45.2 output tok/s, TTFT median 626.9 ms, ITL 19.7 ms, against 45.13), then back to rocm,
  stopped, router disabled, port 8080 free. Every step matched the guide; nothing to correct.
- llama-strix-rocm: strix-native drops. Neither condition in its summary holds: ROCm didn't lead
  on the Framework, and bare metal measured level with the container on gb10-1 for both engines
  (llama-gb10-native, vllm-gb10-native). Retiring spike-model-hosting's router falls to the answer
  task (r2 q3).
- llama-strix-rocm: personal-agents' preparation doc and spike-model-hosting's runbook describe the
  Framework's earlier settings (a 96 GiB GTT ceiling, the router serving); updating them is the
  architect's, outside the spike.
- llama-strix-rocm: for vllm-strix: `host/engines.sh` justifies one engine per host in GB10 terms
  ("most of the GB10's memory"), and a unit's refusal hint, `sudo -n systemctl stop <unit> &&
  sudo -n systemctl disable <unit>`, assumes gb10-1's NOPASSWD rules, which the Framework doesn't
  have for spike-model-hosting's `llama-router`. llama.cpp v0.8.0 (b11960) was released
  2026-10-28T12:47Z, after this task's measurements, so vllm-strix moves the pin and reruns one
  anchor per engine first (Comparisons rule).
- llama-strix-rocm: the editor split the notes' practices into "Running on every host", "Running
  on the GB10s", and "Running on the Framework", so a practice both host classes follow is
  written once.
- llama-strix-rocm: at the session brief, the architect kept the task on llama.cpp v0.7.0 (b11669)
  with no rerun, although v0.8.0 (b11960) was released 2026-10-28T12:47Z after the measurements;
  the architect asked the session to update personal-agents' preparation/framework-desktop.md and
  spike-model-hosting's runbook to the Framework's new settings, outside the spike's PR.
- vllm-strix: image vllm/vllm-openai-rocm:v0.32.0, the same release as gb10-1, gfx1151 in its
  PYTORCH_ROCM_ARCH; rejected its nightly and AMD's rocm/vllm, deprecated by vLLM, whose gfx1151
  tags stop at vLLM 0.19.1 (r1 q1).
- vllm-strix: the vllm group gains a flavor (cuda or rocm, by GPU vendor) picking the image, devices
  and default row, as llama's does; rejected a vllm-rocm group (r1 q2).
- vllm-strix: the rocm flavor runs with /dev/kfd and /dev/dri plus --ipc host only; rejected the
  docs' video group, seccomp unconfined and SYS_PTRACE, since the devices are 0666 (r1 q3).
- vllm-strix: viability is gfx1151 read back, gpt-oss-120b's first start with every weight on the
  GPU, and warm anchor A served; a failure is recorded and BUILD escalates at once; rejected a retry
  under --enforce-eager, a tuning setting (r1 q4).
- vllm-strix: the Framework's default row is gpt-oss-120b, the anchor model on both engines; gb10-1
  keeps Gemma 4 26B-A4B NVFP4, which ROCm can't serve (r1 q5).
- vllm-strix: every row keeps --gpu-memory-utilization 0.80 on both host classes, so the rows stay
  one set (r1 q6).
- vllm-strix: vLLM runs anchors A and B on gpt-oss-120b plus bench-gb10-container's shape set in
  ROCm-servable formats; rejected anchors only (r1 q7).
- vllm-strix: llama.cpp's whole Vulkan set (loads, footprints, cells) reruns at b11960 in this
  session, so every vLLM cell pairs with a same-session cell; rejected anchors only (r1 q8).
- vllm-strix: vLLM's cold start measured per row, from a dropped page cache with a warm compile
  cache, each row's first start recorded beside it; rejected gpt-oss-120b alone (r1 q9).
- vllm-strix: four slices: the llama.cpp v0.8.0 upgrade, vLLM's viability, the comparison, the
  walkthrough; rejected folding the pin move into staging (r1 q10).
- vllm-strix: vLLM's first start of gpt-oss-120b on the Framework has 20 minutes; every other start
  and run keeps 10 (r1 q11).
- vllm-strix: the architect's first walk reads back the device and memory pool through the image's
  rocminfo, and vLLM's logged total, then installs through the suite; rejected the install alone (r1
  q12).
- vllm-strix: the suite's one-engine reason names no host class, and the unit refusal hint drops -n,
  which fails for the Framework's llama-router; both engines (r1 q13).
- vllm-strix: the goal's pending edits and vllm-strix's own ship in one coordinator PR at this
  task's SHIP; rejected leaving them to the answer task (r1 q14).
- vllm-strix: escalation 1, during BUILD: vllm/vllm-openai-rocm:v0.32.0 ships no audio decoder
  (no torchcodec, ffmpeg, av, soundfile or librosa), so E4B BF16's audio cells return 500 and are
  unsupported on the official image. As the session's last step, after llama.cpp's Vulkan set and
  before the end state, a probe: a Dockerfile under host/ FROM the official image by digest, adding
  the packages of vLLM's audio extra the image lacks, pinned at the versions uv resolved on
  2026-10-28, av 19.0.2, soundfile 0.14.0 and soxr 1.1.0, since the extra pins none, built on
  framework without root, serving only E4B BF16's audio A and B, recorded beside the official
  image's result. The suite, the flavor and the pin are unchanged; whether the suite carries it is
  the answer task's. Rejected the suite carrying it now, a follow-on task, and no build.
- vllm-strix: the audio probe served every request: the derived image's E4B BF16 audio A served
  8 of 8 at 7.27 audio s/s and B 31 at 17.89, 64.2% and 88.4% of llama.cpp's Q8_0 cells (11.31
  and 20.24). B's JSON holds 31 requests against the scenario's 32, while the server counted 32
  finished; not looked into. The derived image is kept on the Framework.
- vllm-strix: `host/engines vllm install`'s update hint names the row given in `VLLM_MODEL`, as it
  names the flavor given (a518d1e, standards review): install refusing a row pointed at a plain
  `update`, which serves the flavor's default row. Native's install hint keeps the same gap, left
  for a later task.
- vllm-strix: vLLM's granite cell ran twice. GuideLLM stalled at the change from 1 stream to 16,
  wrote no JSON, and `timeout 10m` ended it (exit 124), while the server had served all 2,272
  requests of the 1-stream level and gone idle; one rerun of the same block completed, and the
  finding reads it and keeps the first run's files.
- vllm-strix: the walkthrough's llama.cpp anchor A reads 39.5 output tok/s by the finding's
  read-out, the successful mean over 7 of 8 requests: the client dropped the 8th request's stream
  at 244 of 256 tokens. GuideLLM's total mean, 44.89, counts the dropped request's tokens and sits
  0.2% below step 1's 44.98. vLLM's A read 10.0 (9.96), 1.0% below step 1's.
- vllm-strix: both client faults, the granite stall and the dropped stream, are GuideLLM 0.8.1's,
  since each server's log and `/metrics` showed no server error; with llama-gb10-container's B
  parse error and bench-gb10-container's 7-of-8 A, they make a practice in the notes: rerun a cell
  once when the server shows no error, keeping both runs. The walkthrough's dropped stream wasn't
  rerun.

## Pending edits

(PR #100, merged 2026-10-26, carried every edit tasks 1–3 owed until then. PR #104 carried the
`engines/` rename's roadmap edit.)

- coordinator · roadmap.toml: delete
  `[goals.experiment.hosting.spike-model-engines.tasks.strix-native]`. llama-strix-rocm's verdict
  is that ROCm doesn't lead, and the GB10 native tasks measured bare metal level with the
  container, so neither condition in its summary holds; the manifest holds only what remains.
- coordinator · roadmap.toml, `experiment.hosting.spike-model-engines.tasks.vllm-strix`'s summary
  (vllm-strix; supersedes llama-strix-rocm's edit to it): "vLLM's official ROCm image
  (vllm/vllm-openai-rocm) on gfx1151, serving or a recorded failure, against llama.cpp in ggml's
  Vulkan image, its leading Strix backend, cell for cell at llama.cpp v0.8.0. New tool: vLLM's
  ROCm image."
- coordinator · roadmap.toml, `experiment.hosting.spike-model-engines.tasks.answer`'s summary: add
  that it retires spike-model-hosting's `llama-router` on the Framework, which strix-native would
  have.
- coordinator · roadmap.toml, `experiment.hosting.spike-model-engines.tasks.llama-strix-rocm`'s
  summary: replace "against the native Vulkan router" with "against ggml's Vulkan image".
- coordinator · ai-hosting.md, "The existing setup: personal-agents", the Framework's
  "Hardware": replace "about 96GB of it exposed to the GPU" with "112 GiB of it reachable by the
  GPU as GTT (spike-model-engines, llama-strix-rocm)"; and "Serving": say the router is stopped
  and disabled while the spike-model-engines sessions own the Framework, until its answer task
  retires it. The "3.30 GiB of the 96GB GPU pool" line stays, as measured at that ceiling.
- coordinator · ai-hosting.md, "spike-model-engines" (vllm-strix): replace "vLLM's ROCm image"
  with "vLLM's official ROCm image (vllm/vllm-openai-rocm; AMD's rocm/vllm images are
  deprecated)".
