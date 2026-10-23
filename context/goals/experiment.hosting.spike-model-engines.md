# goal · experiment.hosting.spike-model-engines

- **State:** building
- **Task:** llama-gb10-container
- **Branch:** llama-gb10-container

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

## Task brief · llama-gb10-container

**Problem.** No engine runs on the GB10s yet. Every later task compares against llama.cpp served
from ggml's CUDA 13 image, so this task gives the spike its first engine, its first scripted
steps, its first guide, and the anchor cells later tasks rerun.

**Behaviors**

1. Both GB10s are brought current by the architect, and each host's stack (DGX OS, driver, CUDA,
   kernel, Docker, container toolkit) is recorded with the date.
2. The pinned image, the b-build llama.cpp's latest semver release names (v0.7.0 → b11669), runs
   on both GB10s with the GPU and prints that build.
3. `mise run currency` reports the pinned llama.cpp build when it trails the build the latest
   semver release names, and stays silent when it matches.
4. `engines` with no arguments lists its commands, each with its one-line summary.
5. `engines llama install` runs llama-server in router mode in the pinned image, or in the
   b-build it is given as an argument (as the walkthrough's b11429 install), with restart
   unless-stopped: the model store and the models preset are bind-mounted, it serves on the
   host's tailnet address on port 8080 with 4 slots, and a second run changes nothing.
6. `engines llama update` moves the container to the pinned build and removes every previous
   llama.cpp image, so only the pinned image remains; when it already runs that build, it
   changes nothing. Proven by installing v0.6.0's b11429 and updating to v0.7.0's b11669.
7. `engines llama uninstall` removes the container and its image and keeps the model store; a
   second run changes nothing.
8. gpt-oss-120b MXFP4 is fetched by the container into the model store and answers an OpenAI
   chat completion sent from the laptop.
9. The llama.cpp guide (README, setup, models, api, update, uninstall) holds every command the
   architect types, exactly as typed, with no host name or tailnet identifier.
10. GuideLLM 0.8.1 runs from the laptop through the spike's own pinned env. The two anchor cells
    run against gb10-1 at b11669, each under 10 minutes, and a dated finding records the build,
    the host stack, and the client and server figures.
11. The architect installs, serves, updates, and uninstalls llama.cpp on both GB10s from the
    guide alone.

**Test seams.** The `engines` commands on each host; `mise run check` and `mise run currency`
on the laptop; the guide, followed step by step.

**Slices**

1. Hosts current, image proven. The architect brings both GB10s current and records their
   stacks, runs the pinned image's version check on the GPU on both, and the pin and its
   currency line land. (Behaviors 1–3.)
2. The `engines` suite and the llama.cpp guide: dispatcher, install, update, uninstall, preset,
   model store, served chat request from the laptop, walked on gb10-1. (Behaviors 4–9.)
3. The anchor cells: GuideLLM's env, the two cells on gb10-1, the dated finding. (Behavior 10.)
4. Walkthrough: the architect runs the whole procedure from the guide on both GB10s, installing
   b11429 and updating to b11669. (Behaviors 6, 11.)

**Out of scope.** vLLM and its currency line; benchmarking on gb10-2; the concurrency sweep,
other shapes, and quantizations (bench-gb10-container); native llama.cpp and llama-bench; the
Framework.

**Door.** Two-way for the repository. The host OS updates in slice 1 are hard to reverse, but
the experiment's rules require them and the architect runs them as root steps.

## Progress

slices 1/4 committed · standards — · spec — · editor —

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
- llama-gb10-container: currency gains the llama.cpp line only; vLLM's waits for its task.

## Pending edits

(none)
