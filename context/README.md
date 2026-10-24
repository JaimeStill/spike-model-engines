# spike-model-engines

spike-model-engines is where the architect learns llama.cpp and vLLM by running them, on the GB10s
and then the Framework, in containers first and then on bare metal. Each engine is documented as a
guide to setup, models, APIs, updates, and removal, and each comparison is a benchmark planned and
run together. Together they are evidence for the engine and hosting method `v1.ai.hosting`
specifies per host class, as a general strategy for self-hosted model engines. The spike decides
nothing itself.

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

- **Guided sessions.** Sessions are slow and methodical. Each slice's docs and scripts are
  written on the branch, then the session walks the architect through the host steps one at a
  time from those docs, and records each output. The last slice is the architect running the
  whole procedure from the docs.
- **Benchmarks.** Each benchmark is planned together in its task's plan round, then built and run
  a step at a time, typed by the architect. A run takes at most 10 minutes unless the brief decides
  otherwise.
- **Current hosts and engines.** Every session starts by bringing the hosts current. llama.cpp
  follows its semver releases, running the b-build each one names; vLLM follows its releases.
  Every result records the engine version and the host stack.
- **Comparisons.** Only cells run in the same session on the same versions are compared. A task
  that compares with an earlier one first reruns one anchor cell per engine.
- **Quantization floor.** A format is accepted when its publisher evaluated it (native MXFP4, a
  QAT Q4_0, or an NVFP4 or FP8 checkpoint whose card evals are within about 1% of BF16).
  Otherwise nothing goes below Q5_K_M or FP8, and embedding, ASR, and dense models under 8B run at
  Q8_0 or FP8 or better.
- **Load tools.** GuideLLM 0.8.1, run from the laptop, for every served measurement; llama-bench
  for raw pp/tg per llama.cpp backend.
- **Root** stays the architect's, run from exact commands.

## Capabilities

- **Engine guides:** setup, models, APIs, updates, and uninstall, per engine, under
  `docs/engines/<engine>/`; llama.cpp's and vLLM's are written.
- **The `engines` suite:** the scripted install, update, and uninstall steps, under `engines/`;
  llama.cpp's and vLLM's are written.
- **Served-load findings:** GuideLLM runs by shape, quantization, and concurrency, under
  `docs/findings/`. The anchor cells later tasks rerun, with the commands that run them, are in
  `llama-gb10-container.md` for llama.cpp and `vllm-gb10-container.md` for vLLM.
- **Raw backend findings:** llama-bench pp/tg per llama.cpp backend.
- **API surface:** the matrix of what each engine serves.
- **Hosting method:** container against bare metal.
- **Quantization rule:** the floor every cell keeps.
- **The answer.**

## Path

The tasks, in the order they run; each cites the evidence it proves.

1. `llama-gb10-container`: llama.cpp in ggml's CUDA 13 image on both GB10s, the `engines` suite,
   the llama.cpp guide, two GuideLLM anchor cells (evidence 1, 2).
2. `vllm-gb10-container`: vLLM's CUDA 13.0 arm64 image on both GB10s, NVFP4 served, the vLLM guide
   (evidence 1, 3).
3. `bench-gb10-container`: the agreed cells on gb10-1, cross-checked on gb10-2, and the
   API-surface probes (evidence 2, 3, 4, 5). Its plan round takes up three questions from
   vllm-gb10-container:
   - vLLM's A' decoded at 30 tok/s on a 4B-active model, with Triton attention (FA4 not
     available) and a BF16 KV cache named in the log: whether one diagnostic A' rerun changing
     one of them precedes the comparison;
   - `free -g` on the host before a vLLM start, which proves or drops the held memory-reporting
     edit in the goal record;
   - `engines <engine> install` reports "already runs; nothing changed" for a stopped
     container (both engines), which engine switching hits.

   A' reruns as vLLM's anchor from a confirmed warm start.
4. `llama-gb10-native`: llama.cpp native under systemd, llama-bench, anchor cells against the
   container (evidence 1, 6).
5. `vllm-gb10-native`: vLLM's aarch64 wheel natively, anchor cells against the container
   (evidence 1, 6).
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
- **Models.** Download a model once, on gb10-1, and copy it to gb10-2 over QSFP
  ([models](../docs/engines/llama.cpp/models.md#copying-a-model-to-the-other-gb10)).
- **The shared blob store.** The Hugging Face client in vLLM's image keeps a model's weight files
  in `/srv/models/blobs`, outside the model's directory, which only links to them. Copy
  `/srv/models/blobs` with the model's directory, and measure a model with `du -shL`, since a
  plain `du -sh` doesn't follow the links and shows a few MB
  ([models](../docs/engines/vllm/models.md#the-first-download)).
- **One engine per host.** Each engine's install refuses while the other's container runs:
  beside a second server, vLLM's memory reservation would fail and its container restart in a
  loop. Stop one before installing the other.
- **`ls` on the GB10s.** The GB10 setup in dotfiles aliases `ls` to eza, whose flags differ from
  coreutils' (`ls -laL` failed: eza reads `-L` as a tree depth), so guide commands use `du -shL`,
  `stat`, `readlink -f`, or `command ls` instead.
- **Hosts by short name.** Laptop commands name a GB10 by its short name (`http://gb10-1:8000`),
  which MagicDNS resolves, so no command carries a tailnet address.
- **Install messages.** The `engines` install messages print the port, never the host's address,
  so a pasted output keeps to `ai-hosting.md`'s "Visibility" rule as it stands.
- **Network path.** When the architect is remote, the laptop can reach the GB10s through a
  Tailscale DERP relay. The relay adds its round trip to TTFT and request latency, but not to ITL
  or the server's `/metrics` figures, so every served run records its path with `tailscale ping`.
- **Model state.** The prompt cache changes TTFT and the prompt tokens the server processes: cell
  B's rerun, on a freshly loaded model, had a higher TTFT than its first run after cell A. Start
  each cell from the same model state, warmed or freshly loaded, so TTFT compares like with like.
- **GuideLLM's Python.** `mise.bench.toml` holds Python at 3.14, because torch publishes no 3.15
  wheels, so `mise run currency` reports Python behind until it does.

## References

The spike reads these repositories and never writes to them. Each is a key in the coordinator's
`references.toml`, with its local checkout in `references.local.toml`:

- `spike-model-hosting`: the Strix Halo runbook and llama.cpp build log, the baseline, and the
  model-card method.
- `personal-agents`: the Framework's preparation and its `outpost` admin scripts, the model for the
  `engines` suite.
- `dotfiles`: the GB10 setup pattern (`platforms/dgx/system-setup.sh`) and the QSFP link record.
  Two-node serving belongs to spike-model-layout.
