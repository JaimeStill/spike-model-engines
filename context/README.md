# spike-model-engines

spike-model-engines is where the architect learns llama.cpp and vLLM by running them, on a GB10,
gb10-1, and then the Framework, in containers first and then on bare metal. Each engine is
documented as a guide to setup, models, APIs, updates, and removal, and each comparison is a
benchmark planned and run together. Together they are evidence for the engine and hosting method
`v1.ai.hosting` specifies per host class, as a general strategy for self-hosted model engines. The
spike decides nothing itself.

The spike answers for experiment.hosting, and the coordinator's roadmap,
`standards-lab/roadmap/index.toml`, holds its work. The coordinator records its
answer in `standards-lab/docs/ai-hosting.md`, "The spikes' answers". IL6 is out of this spike's scope. Each capability in
detail, the tasks in the order they ran, and the repositories the spike reads are in
[`docs/capabilities.md`](../docs/capabilities.md); the practices every task follows on the hosts
are in [`docs/host-practices.md`](../docs/host-practices.md).

## The question

Which engine, llama.cpp or vLLM, serves each workstation (the GB10s, then the Framework's Strix
Halo), and is it hosted in a container or on bare metal?

## The answer

The answer is in the top-level [`README.md`](../README.md#the-answer). standards-lab's
`docs/ai-hosting.md` records that vLLM superseded it on every workstation: vLLM supersedes the
engine; the container stands, since on gb10-1 both engines ran at native speed in their
containers.

## The evidence

1. Each engine installs, updates, and uninstalls on each host class from a few named, idempotent
   scripted steps, and its guide documents setup, models, APIs, updates, and uninstall, and
   whether the engine loads models on demand. Finding:
   [`llama-gb10-container.md`](../docs/findings/llama-gb10-container.md),
   [`vllm-gb10-container.md`](../docs/findings/vllm-gb10-container.md),
   [`llama-gb10-native.md`](../docs/findings/llama-gb10-native.md),
   [`vllm-gb10-native.md`](../docs/findings/vllm-gb10-native.md),
   [`llama-strix-rocm.md`](../docs/findings/llama-strix-rocm.md),
   [`vllm-strix.md`](../docs/findings/vllm-strix.md).
2. Raw speed, TTFT, unified-memory footprint, and cold load per engine and host class, by shape:
   dense small, mid, and large; MoE; embedding; ASR; vision. Each cell is measured, or marked
   unsupported with its reason. Finding:
   [`llama-gb10-container.md`](../docs/findings/llama-gb10-container.md),
   [`bench-gb10-container.md`](../docs/findings/bench-gb10-container.md),
   [`llama-strix-rocm.md`](../docs/findings/llama-strix-rocm.md),
   [`vllm-strix.md`](../docs/findings/vllm-strix.md).
3. The same for each quantization format an engine serves natively, within the quantization
   floor. NVFP4 only through vLLM. Finding:
   [`vllm-gb10-container.md`](../docs/findings/vllm-gb10-container.md),
   [`bench-gb10-container.md`](../docs/findings/bench-gb10-container.md),
   [`llama-strix-rocm.md`](../docs/findings/llama-strix-rocm.md).
4. Scaling from 1 to N concurrent streams, and what each engine does past its slots. Finding:
   [`bench-gb10-container.md`](../docs/findings/bench-gb10-container.md),
   [`answer.md`](../docs/findings/answer.md).
5. The API surface the consumers need: OpenAI chat with tools and reasoning, Anthropic messages,
   embeddings, transcription, and vision, each probed or marked on paper. Finding:
   [`bench-gb10-container.md`](../docs/findings/bench-gb10-container.md).
6. Container against bare metal for each engine kept, per host class: install, update, rollback,
   startup, speed parity, and GPU and memory access. Finding:
   [`llama-gb10-native.md`](../docs/findings/llama-gb10-native.md),
   [`vllm-gb10-native.md`](../docs/findings/vllm-gb10-native.md).

## Capability map

- **Engine guides** (built): [`docs/engines/llama.cpp/`](../docs/engines/llama.cpp/README.md) and
  [`docs/engines/vllm/`](../docs/engines/vllm/README.md), each for the GB10s with sections for
  the Framework.
- **The `engines` suite** (built): [`host/engines`](../host/engines) and its
  `engines-<group>-<verb>` commands under [`host/`](../host/), reasoning in each guide's
  scripts page, [llama.cpp's](../docs/engines/llama.cpp/scripts.md) and
  [vLLM's](../docs/engines/vllm/scripts.md).
- **The benchmark cells** (built): the GuideLLM scenarios in [`bench/`](../bench/), sized in
  [`docs/bench.md`](../docs/bench.md); the measured results in
  [`docs/findings/`](../docs/findings/).
- **Tools, check, and currency** (built): [`mise.toml`](../mise.toml), the bench and host
  environments, and [`scripts/`](../scripts/), reasoning in [`docs/tools.md`](../docs/tools.md).
- **Host practices** (built): [`docs/host-practices.md`](../docs/host-practices.md).
- **The spike's rules** (built): [`docs/rules.md`](../docs/rules.md).

## Rules

The experiment's rules, `standards-lab/docs/ai-hosting.md#experiment-rules`, govern every session.
The rules this spike keeps beside them, how llama.cpp is pinned, the load tools, and the root
grants, are in [`docs/rules.md`](../docs/rules.md).
