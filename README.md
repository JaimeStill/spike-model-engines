# spike-model-engines

Which engine, llama.cpp or vLLM, serves each of the workstations, the two GB10s and the
Framework's Strix Halo, and is it hosted in a container or on bare metal? This spike measures both
engines' raw capability by model shape, quantization, and concurrency, on gb10-1 (gb10-2 is
reserved for spike-ai-pipeline) and on the Framework, and documents how each is set up,
configured, called, updated, and removed. Its answer is evidence for standards-lab's
`experiment.hosting` intake, which decides the engine strategy `v1.ai.hosting` specifies.

- The engine guides: `docs/engines/` (written by the install tasks).
- The measured results: `docs/findings/` (written by the benchmark tasks).

## The answer

**The question:** which engine serves each host class, and is it hosted in a container or on
bare metal?

**The answer:** by default, llama.cpp in a container on both host classes, in ggml's CUDA image
on the GB10s and in ggml's Vulkan image on the Framework.

The strategy is drawn from two host classes, NVIDIA's GB10 and AMD's Strix Halo, so it is stated
as rules keyed by a host's traits, with the GB10s and the Framework as worked instances. Each item
names the finding that proves it, with the build and the date. Every comparison is within one
finding's session; no figure is compared across sessions or versions.

### GPU vendor and its backend

1. **On NVIDIA, llama.cpp on CUDA; vLLM's lead from 4 streams on gpt-oss-120b is evidence.** On
   gb10-1, llama.cpp led gpt-oss-120b at 1 stream (50.0 against 34.0 output tok/s) and the
   Gemma 4 shapes at 4 streams, the 12B level; vLLM led gpt-oss-120b from 4 streams (86.7
   against 80.9 at B, 168 against 129 at 16 streams). One engine serves a host at a time, and a
   host split between them wasn't measured
   ([bench-gb10-container](docs/findings/bench-gb10-container.md#findings): llama.cpp b11669,
   vLLM v0.32.0, 2026-10-26).
2. **vLLM's NVFP4 decodes slowly on SM121.** Its NVFP4 rows decode at about half llama.cpp's QAT
   Q4_0 rate on the same model (26B-A4B 30.5 against 70.8 tok/s). Neither the attention backend
   ([bench-gb10-container](docs/findings/bench-gb10-container.md#the-flashinfer-diagnostic):
   v0.32.0, 2026-10-26) nor the MoE kernel
   ([vllm-gb10-native](docs/findings/vllm-gb10-native.md#the-marlin-diagnostic): v0.32.0,
   2026-10-27) is the cause.
3. **On AMD, llama.cpp on Vulkan, not ROCm; ROCm's leads in cold load and vision are evidence.**
   On the Framework, ggml's Vulkan image led its ROCm image at both anchors (by 6.39% and 5.21%)
   and on every llama-bench row. ROCm cold-loaded every model sooner (gpt-oss-120b in 12.9 against
   18.2 s) and led both vision cells (by 16.1% and 24.2%)
   ([llama-strix-rocm](docs/findings/llama-strix-rocm.md#verdict): b11669, 2026-10-27).
4. **vLLM's ROCm image trails llama.cpp's Vulkan image in every generative cell.** It served
   22.4% of llama.cpp's output at anchor A and 20.6% at B
   ([vllm-strix](docs/findings/vllm-strix.md#served): vLLM v0.32.0, llama.cpp b11960,
   2026-10-28).

### Unified memory

5. **llama.cpp takes the model's memory; vLLM takes its reservation.** On a pool the GPU and the
   host share, vLLM reserves 0.80 of the memory whatever the model, and llama.cpp only the model's
   buffers, so one llama.cpp router holds several models. On gb10-1, vLLM left 15.9 to 19.1 GiB
   available at every generative start, and llama.cpp took 1.6 to 65.5 GiB
   ([bench-gb10-container](docs/findings/bench-gb10-container.md#cold-load-and-footprint): vLLM
   v0.32.0, llama.cpp v0.7.0 (b11669), 2026-10-26). On the Framework, vLLM reserved 89.6 of the
   112 GiB GTT ceiling at every generative row, and llama.cpp took 8.95 to 62.23 GiB
   ([vllm-strix](docs/findings/vllm-strix.md#cold-start-and-footprint): vLLM v0.32.0, llama.cpp
   v0.8.0 (b11960), 2026-10-28); set A's four models hold 92.1 GiB of GTT
   ([answer](docs/findings/answer.md#set-a-served): b11960, 2026-10-29).

### Workload: streams, embeddings, models on demand

6. **Streams: the measured curves are the evidence, and set no limit** (see
   [Concurrency](#concurrency)). gpt-oss-120b on 16 slots, 512 in, 256 out:
   - gb10-1 served 48.5, 77.1, 129.0, and 126.2 output tok/s at 1, 4, 16, and 32 streams
     ([bench-gb10-container](docs/findings/bench-gb10-container.md#concurrency-sweep): b11669,
     2026-10-26);
   - the Framework served 43.6, 69.5, 81.6, and 80.1, over a DERP relay
     ([answer](docs/findings/answer.md#concurrency-sweep): b11960, 2026-10-29).

   The two ran in different sessions, at different builds, over different paths, and are not
   compared. Each finding's shape cells, A at 1 stream and B at 4, add the same curve's first two
   points by model.
7. **Embeddings at concurrency: vLLM's lead is evidence.** vLLM's embedding rate scales with
   streams and llama.cpp's doesn't. On granite-embedding-english-r2 at 16 streams, vLLM served
   295.1 requests/s against llama.cpp's 55.5 on gb10-1
   ([bench-gb10-container](docs/findings/bench-gb10-container.md#embeddings): vLLM v0.32.0,
   llama.cpp v0.7.0 (b11669), 2026-10-26), and 215.3 against 40.5 on the Framework
   ([vllm-strix](docs/findings/vllm-strix.md#served): vLLM v0.32.0, llama.cpp v0.8.0 (b11960),
   2026-10-28). vLLM's embeddings come unnormalized, llama.cpp's of unit norm.
8. **Models on demand: llama.cpp's router.** It loads and unloads models through its API in
   seconds; vLLM serves one model a start, in minutes. On gb10-1, gpt-oss-120b loaded in 48 s
   against vLLM's 577 s cold start
   ([bench-gb10-container](docs/findings/bench-gb10-container.md#findings): llama.cpp v0.7.0
   (b11669), vLLM v0.32.0, 2026-10-26). On the Framework, llama.cpp's generative models
   cold-loaded in 2.6 to 18.2 s, and vLLM's timed starts took 70.0 to 160.9 s
   ([vllm-strix](docs/findings/vllm-strix.md#cold-start-and-footprint): llama.cpp v0.8.0
   (b11960), vLLM v0.32.0, 2026-10-28).

### Hosting method

9. **A container on both host classes.** On gb10-1, llama.cpp ran at the same speed, startup,
   and memory in ggml's container and natively
   ([llama-gb10-native](docs/findings/llama-gb10-native.md#findings): b11669, 2026-10-27), and
   vLLM at parity within run noise, its container starting 137 s sooner, since only the container
   keeps FlashInfer's MoE tuning
   ([vllm-gb10-native](docs/findings/vllm-gb10-native.md#findings): v0.32.0, 2026-10-27).
10. **The Framework's bare metal is unproven.** ggml's native Vulkan build led the Vulkan image
    at prompt processing (pp512 by 4.49 to 9.49%, generation within 2.1%), likely from the host's
    newer Mesa, untested; no server ran natively
    ([llama-strix-rocm](docs/findings/llama-strix-rocm.md#findings): b11669, 2026-10-27).

### Concurrency

The measured curves, gb10-1's sweep, the Framework's sweep, and each finding's 1- and 4-stream
shape cells, are evidence, and the answer sets no slot limit. Slots are a per-scenario tuning
setting that depends on the model, the workload, and the host, tuned as the stack is used. The
Framework sweep gives gpt-oss-120b an initial setting of 4 streams, read off synthetic prompts
over a DERP relay ([answer](docs/findings/answer.md#initial-setting): b11960, 2026-10-29), and set
A starts there. Tuning is an open item, owned by the backlog goal model-evaluation and by
spike-model-layout.

### Open items

Gaps in the answer:

- **The Framework's API probes:** not measured. Tools, reasoning, the Anthropic and Responses
  APIs, vision, embeddings, and transcription were probed on gb10-1 only
  ([bench-gb10-container](docs/findings/bench-gb10-container.md#api-probes-1)).
- **The Framework's bare metal:** not measured as a server; the native build's lead at prompt
  processing is measured, its cause, likely Mesa, open (item 10).
- **vLLM's slow NVFP4 decode on SM121:** cause open (item 2).

Requirements for experiment.hosting's intake to route:

- **Workload-based tuning:** not measured; slots and context tuned per model, workload, and
  host, owned by model-evaluation and spike-model-layout ([Concurrency](#concurrency)).
- **Request priority:** not measured. llama-server queues past its slots first come, first
  served, with no limit, priority, or 429: the Framework sweep's 32-stream level held 16 deferred,
  with no errors ([answer](docs/findings/answer.md#past-16-slots)). vLLM has
  `--scheduling-policy priority`.
- **Model management separated from inference and held by an admin:** not measured.
  llama-server's router exposes load, unload, download, and delete to any client that reaches it,
  and `?autoload=true` overrides `--no-models-autoload`; every API key has the same access, and
  downloads likely ignore offline mode (both by the source, untested). Today the tailnet, ufw, and
  `tag:inference` bound it.

Also open:

- **Native vLLM re-tunes FlashInfer every start:** cause open
  ([vllm-gb10-native](docs/findings/vllm-gb10-native.md#startup)).
- **EmbeddingGemma 2 unserved on vLLM on SM121:** Triton's encoder attention ran out of shared
  memory, and vLLM #60847 reports no other backend that works there, by the source, untested
  ([bench-gb10-container](docs/findings/bench-gb10-container.md#engine-limits)).
- **vLLM's Gemma 4 transcription:** on paper; v0.32.0 serves it for Granite Speech, Whisper, and
  Voxtral, not Gemma 4, by the source, untested.
- **vLLM's ROCm audio:** probe only, the suite doesn't build it
  ([vllm-strix](docs/findings/vllm-strix.md#the-audio-probe)).

### The Framework's end state

The Framework serves set A from the `llama` container in ggml's Vulkan image, at b11960:
gpt-oss-120b on 4 slots, Gemma 4 26B-A4B QAT Q4_0 and E4B Q8_0 with their projectors, and
granite-embedding-english-r2, on `framework:8080`
([setup](docs/engines/llama.cpp/setup.md#12-serve-set-a)). The `vllm` container is installed and
stopped. spike-model-hosting's router, `llama-router`, is retired, on 2026-10-29: its unit,
presets, builds, and 82G of models are gone, and the models drive stays mounted, empty
([setup](docs/engines/llama.cpp/setup.md#5-retire-the-router);
[answer's Walkthrough](docs/findings/answer.md#walkthrough), where Pi ran against set A from the
laptop).
