# llama.cpp and vLLM compared in containers on gb10-1

Recorded on 2026-10-26, on gb10-1, in containers, from the cells and probes the task's brief
agreed (context/goals, `bench-gb10-container`). llama.cpp's cells run first; vLLM's follow on the
same host stack and engine versions, so the two compare
([Comparisons](../../context/README.md#rules)).

## Host stack

gb10-1 was brought current with `sudo apt update && sudo apt upgrade` by the architect, which
found nothing new to install, and its stack recorded on 2026-10-26 at 11:02 -04:00. No reboot is
pending, and the CDI spec was regenerated after the upgrade
([setup](../engines/llama.cpp/setup.md#1-bring-the-host-current)).

| Item | gb10-1 |
|---|---|
| DGX OS | 7.6.0 |
| Driver | 580.178.04 |
| CUDA | 13.0 |
| Kernel | 7.0.0-1019-nvidia |
| Reboot pending | no |
| Docker | 29.6.2 |
| NVIDIA Container Toolkit | 1.20.1 |

## Engine versions

| Engine | Release | Build or image |
|---|---|---|
| llama.cpp | v0.7.0 | b11669, `ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669` (`engines/llama.env`) |
| vLLM | v0.32.0 | `vllm/vllm-openai:v0.32.0` (`engines/vllm.env`) |

The load tool is GuideLLM 0.8.1 on the laptop, in the spike's bench environment
(`mise.bench.toml`: Python 3.14.10, with the `vision` and `audio` extras).

## Pre-staging

Every model both engines serve, and both images, were staged on gb10-1 in parallel before any
cell or timed load, with the procedure in
[Models](../engines/llama.cpp/models.md#pre-staging-everything-at-once).

| Item | Size | Started | Finished | Exit |
|---|---|---|---|---|
| `ggml-org/gemma-4-E4B-it-GGUF` (Q8_0 + mmproj) | | | | |
| `google/gemma-4-E4B-it-qat-q4_0-gguf` | | | | |
| `google/gemma-4-12B-it-qat-q4_0-gguf` | | | | |
| `google/gemma-4-31B-it-qat-q4_0-gguf` | | | | |
| `google/gemma-4-26B-A4B-it-qat-q4_0-gguf` | | | | |
| `ggml-org/embeddinggemma-2-GGUF` | | | | |
| `google/gemma-4-E4B-it` | | | | |
| `google/gemma-4-E4B-it-qat-w4a16-ct` | | | | |
| `google/gemma-4-12B-it-qat-w4a16-ct` | | | | |
| `nvidia/Gemma-4-31B-IT-NVFP4` | | | | |
| `google/embeddinggemma-2` | | | | |
| `openai/gpt-oss-120b` (no `original/`, `metal/`) | | | | |
| llama.cpp image | | | | |
| vLLM image | | | | |

Completion checks (`*.incomplete` files, `hf cache ls`, `du -shL`): to be recorded.

## Method

### The cells

Each cell is a GuideLLM scenario under `bench/`, sending streaming OpenAI chat completions, or
embeddings, from the laptop. Every scenario but the anchors' is engine-neutral: the model, the
tokenizer that cuts its synthetic prompt, and the JSON's path are given on the command line, and
the target in `GUIDELLM__SPEC__BACKEND__TARGET`, so vLLM's cells reuse the same files. Every
request with output tokens set is sent with `ignore_eos`, so it generates exactly that many.

| Cell | Scenario | Load | Models |
|---|---|---|---|
| A, B | `bench/anchor-a.yaml`, `anchor-b.yaml` | 512 in, 256 out; 1 × 8, 4 × 32 | gpt-oss-120b, 4 slots |
| Shape A, B | `bench/shape-a.yaml`, `shape-b.yaml` | 512 in, 256 out; 1 × 8, 4 × 32 | E4B Q8_0, 12B, 26B-A4B |
| Large A, B | `bench/shape-large-a.yaml`, `shape-large-b.yaml` | 512 in, 256 out; 1 × 4, 4 × 16 | 31B |
| Quant pair | `bench/shape-a.yaml` | 512 in, 256 out; 1 × 8 | E4B Q8_0 (its shape A) and E4B QAT Q4_0 |
| Vision A, B | `bench/vision-a.yaml`, `vision-b.yaml` | one synthetic 720p JPEG + 200 text tokens, 64 out; 1 × 8, 4 × 32 | 26B-A4B |
| ASR A, B | `bench/audio-a.yaml`, `audio-b.yaml` | one LibriSpeech clip + the card's transcription prompt, up to 256 out; 1 × 8, 4 × 32 | E4B Q8_0 |
| Embeddings | `bench/embed.yaml` | 512 tokens; 1 then 16 streams, 30 s each | EmbeddingGemma 2 |
| Sweep | `bench/sweep.yaml` | 512 in, 256 out; 1, 4, 16, then 32 streams, 60 s each | gpt-oss-120b, 16 slots |

The Gemma 4 shape cells ask the model to reason (`chat_template_kwargs.enable_thinking`), as
vLLM's anchors A' and B' do; gpt-oss reasons in every request. The vision and ASR cells don't ask.

Each prompt is cut by the model's upstream tokenizer, fetched from Hugging Face, since GGUF files
carry none GuideLLM reads; the Gemma 4 models use the tokenizer of the checkpoint vLLM serves, so
both engines get the same prompts:

| Model (llama.cpp's preset section) | `model` | `tok` |
|---|---|---|
| gpt-oss-120b, 4 slots | `ggml-org/gpt-oss-120b-GGUF:MXFP4` | `openai/gpt-oss-120b` (in the anchors' scenarios) |
| gpt-oss-120b, 16 slots | `gpt-oss-120b-MXFP4-16-slots` | `openai/gpt-oss-120b` |
| E4B Q8_0 | `ggml-org/gemma-4-E4B-it-GGUF:Q8_0` | `google/gemma-4-E4B-it` |
| E4B QAT Q4_0 | `google/gemma-4-E4B-it-qat-q4_0-gguf:Q4_0` | `google/gemma-4-E4B-it` |
| 12B QAT Q4_0 | `google/gemma-4-12B-it-qat-q4_0-gguf:Q4_0` | `google/gemma-4-12B-it-qat-w4a16-ct` |
| 31B QAT Q4_0 | `google/gemma-4-31B-it-qat-q4_0-gguf:Q4_0` | `nvidia/Gemma-4-31B-IT-NVFP4` |
| 26B-A4B QAT Q4_0 | `google/gemma-4-26B-A4B-it-qat-q4_0-gguf:Q4_0` | `nvidia/Gemma-4-26B-A4B-NVFP4` |
| EmbeddingGemma 2 Q8_0 | `ggml-org/embeddinggemma-2-GGUF:Q8_0` | `google/embeddinggemma-2` |

The client figures are GuideLLM's, and the server figures llama.cpp's own `/metrics` counters,
differenced over each cell, as in [llama.cpp's anchor cells](llama-gb10-container.md#method).

### Model state

Each model is loaded fresh, from a dropped page cache, and warmed with one request before its
first cell; its cells then run in the order below, and its API probes after them. Every cell so
starts from a model that has served one request and the cells before it, the same on both engines.

### Order

llama.cpp, one model loaded at a time, each unloaded before the next:

| Step | `model` | Cells, then probes |
|---|---|---|
| 1 | `ggml-org/gpt-oss-120b-GGUF:MXFP4` | A, B; probes: tools, reasoning, Anthropic messages, responses |
| 2 | `gpt-oss-120b-MXFP4-16-slots` | sweep |
| 3 | `ggml-org/gemma-4-E4B-it-GGUF:Q8_0` | shape A (also the quant pair's Q8_0), shape B, ASR A, ASR B; probe: transcription |
| 4 | `google/gemma-4-E4B-it-qat-q4_0-gguf:Q4_0` | shape A (the quant pair's Q4_0) |
| 5 | `google/gemma-4-12B-it-qat-q4_0-gguf:Q4_0` | shape A, shape B |
| 6 | `google/gemma-4-31B-it-qat-q4_0-gguf:Q4_0` | large A, large B |
| 7 | `google/gemma-4-26B-A4B-it-qat-q4_0-gguf:Q4_0` | shape A, shape B, vision A, vision B; probe: vision |
| 8 | `ggml-org/embeddinggemma-2-GGUF:Q8_0` | embeddings; probe: embeddings |

vLLM's order is in its own section, to follow.

### Once, before the first model

On gb10-1, from the clone, the session pulls the branch, starts llama.cpp's router if it isn't
running (`vllm` stopped, since one engine serves at a time), and has the router re-read the
preset:

```sh
git pull --ff-only
engines/engines llama install
curl -s "http://$(tailscale ip -4):8080/models?reload=1" > /dev/null
curl -s "http://$(tailscale ip -4):8080/models" | jq '.data[] | {id, status: .status.value}'
```

On the laptop, from the clone: the network path, the target, and the directory the cells write
to, which `.state/` keeps untracked:

```sh
tailscale ping -c 3 gb10-1
export GUIDELLM__SPEC__BACKEND__TARGET="http://gb10-1:8080"
mkdir -p .state/bench
```

### Per model: the cold load and its footprint

On gb10-1, with `model` set to the step's model and `prev` to the previous step's (empty at step
1). Unload the previous model and wait until it is unloaded:

```sh
model=ggml-org/gpt-oss-120b-GGUF:MXFP4
prev=
[[ -z $prev ]] || curl -s -X POST "http://$(tailscale ip -4):8080/models/unload" -H "Content-Type: application/json" -d "{\"model\": \"$prev\"}"
[[ -z $prev ]] || until [[ $(curl -s "http://$(tailscale ip -4):8080/models" | jq -r --arg m "$prev" '.data[] | select(.id == $m) | .status.value') == unloaded ]]; do sleep 1; done
```

Drop the page cache, showing the cache before and after, and read the memory available before the
load:

```sh
grep ^Cached /proc/meminfo; sync && sudo -n /usr/sbin/sysctl vm.drop_caches=3; grep ^Cached /proc/meminfo
grep ^MemAvailable /proc/meminfo
```

Load the model through the router's API and time it, from the request to the first `/models`
poll that shows it `loaded` (or failed), polled every half second:

```sh
since=$(date -u +%Y-%m-%dT%H:%M:%SZ); start=$(date +%s.%N)
curl -s -X POST "http://$(tailscale ip -4):8080/models/load" -H "Content-Type: application/json" -d "{\"model\": \"$model\"}"; echo
while :; do s=$(curl -s "http://$(tailscale ip -4):8080/models" | jq -r --arg m "$model" '.data[] | select(.id == $m) | if .status.failed then "failed" else .status.value end'); [[ $s == loaded || $s == failed ]] && break; sleep 0.5; done
echo "$s after $(awk -v a="$start" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1f", b - a }') s"
```

Then the memory available after the load, and the buffers the engine logged for it since the load
began (weights, KV cache, compute, and the projector's):

```sh
grep ^MemAvailable /proc/meminfo
docker logs --since "$since" llama 2>&1 | grep -E "buffer size|model size"
```

### Per model: the build and the warm-up

On the laptop, with `model` and `tok` set to the step's values from the table above. The build
the model runs, the network path, then one warm-up request: the API page's chat completion, or
for EmbeddingGemma 2 one embedding:

```sh
model=ggml-org/gpt-oss-120b-GGUF:MXFP4
tok=openai/gpt-oss-120b
tailscale ping -c 3 gb10-1
curl -sG "http://gb10-1:8080/props" --data-urlencode "model=$model" --data-urlencode autoload=false | jq -r .build_info
curl -s "http://gb10-1:8080/v1/chat/completions" -H "Content-Type: application/json" -d "{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one sentence.\"}]}" | jq '.choices[0].message.content'
```

For EmbeddingGemma 2, the warm-up instead:

```sh
curl -s "http://gb10-1:8080/v1/embeddings" -H "Content-Type: application/json" -d "{\"model\": \"$model\", \"input\": \"Say hello in one sentence.\"}" | jq '{model, usage}'
```

### Per cell

On the laptop. The anchors run their own scenarios, which name their model and tokenizer, as
task 1 ran them, with `cell` set to `a`, then `b`. Only the JSON's path is given, which replaces
the scenario's, so task 1's files in `.state/anchor/` stay:

```sh
cell=a
curl -sG "http://gb10-1:8080/metrics" --data-urlencode "model=$model" --data-urlencode autoload=false > .state/bench/llama-anchor-$cell.before.metrics
MISE_ENV=bench mise exec -- guidellm run -c bench/anchor-$cell.yaml --output "kind=json,path=.state/bench/llama-anchor-$cell.json"
curl -sG "http://gb10-1:8080/metrics" --data-urlencode "model=$model" --data-urlencode autoload=false > .state/bench/llama-anchor-$cell.after.metrics
```

Every other cell, with `scenario` set to its file's name under `bench/` and `cell` to a name for
its output, the engine, model, and scenario together, such as `llama-e4b-q8-shape-a`:

```sh
scenario=shape-a
cell=llama-e4b-q8-shape-a
curl -sG "http://gb10-1:8080/metrics" --data-urlencode "model=$model" --data-urlencode autoload=false > .state/bench/$cell.before.metrics
MISE_ENV=bench mise exec -- guidellm run -c bench/$scenario.yaml --backend "kind=openai_http,model=$model" --tokenizer "kind=huggingface_auto,model=$tok" --output "kind=json,path=.state/bench/$cell.json"
curl -sG "http://gb10-1:8080/metrics" --data-urlencode "model=$model" --data-urlencode autoload=false > .state/bench/$cell.after.metrics
```

`llamacpp:requests_processing` in the first snapshot is 0 when nothing else is using the model.
The cells' names:

| Step | `scenario` | `cell` |
|---|---|---|
| 2 | `sweep` | `llama-gptoss-sweep` |
| 3 | `shape-a`, `shape-b`, `audio-a`, `audio-b` | `llama-e4b-q8-shape-a`, `llama-e4b-q8-shape-b`, `llama-e4b-q8-audio-a`, `llama-e4b-q8-audio-b` |
| 4 | `shape-a` | `llama-e4b-q4-shape-a` |
| 5 | `shape-a`, `shape-b` | `llama-12b-shape-a`, `llama-12b-shape-b` |
| 6 | `shape-large-a`, `shape-large-b` | `llama-31b-large-a`, `llama-31b-large-b` |
| 7 | `shape-a`, `shape-b`, `vision-a`, `vision-b` | `llama-26b-shape-a`, `llama-26b-shape-b`, `llama-26b-vision-a`, `llama-26b-vision-b` |
| 8 | `embed` | `llama-embed` |

### Reading the figures

The client figures, one object per benchmark in the JSON (the sweep has four, the embedding cell
two), with `f` set to the cell's JSON:

```sh
f=.state/bench/$cell.json
jq '.metadata as $v | .benchmarks[] | .metrics as $m | {guidellm: $v.guidellm_version, python: $v.python_version, streams: .config.strategy.streams, duration_s: .duration, requests: $m.request_totals, requests_per_s: $m.requests_per_second.successful.mean, prompt_tokens: $m.prompt_token_count.successful.median, output_tokens: $m.output_token_count.successful.median, output_tok_s: $m.output_tokens_per_second.successful.mean, ttft_ms: ($m.time_to_first_token_ms.successful | {median, p95: .percentiles.p95}), itl_ms: ($m.inter_token_latency_ms.successful | {median, p95: .percentiles.p95}), latency_s: ($m.request_latency.successful | {median, p95: .percentiles.p95}), audio_s_per_s: $m.audio.seconds.input_per_second.successful.mean}' "$f"
```

And the server figures, the counters differenced between the two snapshots, with `p` set to the
snapshots' path without its suffix:

```sh
p=.state/bench/$cell
awk '{ d[$1] += (NR == FNR ? -$2 : $2) } END { m = "llamacpp:"; printf "prompt %d tokens, %.1f tok/s; generated %d tokens, %.1f tok/s\n", d[m "prompt_tokens_total"], d[m "prompt_tokens_total"] / d[m "prompt_seconds_total"], d[m "tokens_predicted_total"], d[m "tokens_predicted_total"] / d[m "tokens_predicted_seconds_total"] }' $p.before.metrics $p.after.metrics
```

### API probes

From [llama.cpp's API page](../engines/llama.cpp/api.md#probes-of-the-api-surface), exactly as
written there, each after its model's cells (the order above).

### Run times

Estimated from task 1's anchors (gpt-oss-120b decoding about 54 tok/s at 1 stream) and the
models' sizes; each must stay within 10 minutes.

| Cell | Estimate |
|---|---|
| A, B | 45 s, 100 s (task 1: 42.0 s, 99.2 s) |
| Shape A, B, E4B | 1 min, 2 min |
| Shape A, B, 12B | 1.5 min, 2.5 min |
| Large A, B, 31B | 2 min, 2.5 min |
| Shape A, B, 26B-A4B | 1 min, 2 min |
| Quant pair, E4B Q4_0 | 1 min |
| Vision A, B | 0.5 min, 1 min |
| ASR A, B | 0.5 min, 1 min |
| Embeddings | 1.5 min (two 30 s levels and setup) |
| Sweep | 4.5 min (four 60 s levels and setup) |

## Results

### Anchors

Rerun first, from the warm start above, against task 1's
([llama.cpp's anchor cells](llama-gb10-container.md#results)). An anchor moved beyond run noise is
a finding.

| Cell | Run | Completed | Errored | Duration s | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | Latency median s | Latency p95 s | Server prompt tok/s | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | task 1 | 8 | 0 | 42.0 | 48.8 | 477 | 702 | 18.3 | 5.16 | 5.41 | 1485 | 54.0 |
| A | this session | | | | | | | | | | | |
| B | task 1, rerun | 32 | 0 | 101.3 | 80.9 | 1420 | 1974 | 43.2 | 12.51 | 12.85 | 1627 | 22.5 |
| B | this session | | | | | | | | | | | |

Task 1 ran over Tailscale's DERP relay (about 55 ms); this session's path is recorded with each
model.

### Shapes

| Shape | Model | Engine | Format | Cell | Streams × requests | Completed | Errored | Duration s | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | Latency median s | Latency p95 s | Server prompt tok/s | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| dense small | gemma-4-E4B | llama.cpp | Q8_0 | A | 1 × 8 | | | | | | | | | | | |
| dense small | gemma-4-E4B | llama.cpp | Q8_0 | B | 4 × 32 | | | | | | | | | | | |
| dense mid | gemma-4-12B | llama.cpp | QAT Q4_0 | A | 1 × 8 | | | | | | | | | | | |
| dense mid | gemma-4-12B | llama.cpp | QAT Q4_0 | B | 4 × 32 | | | | | | | | | | | |
| dense large | gemma-4-31B | llama.cpp | QAT Q4_0 | A | 1 × 4 | | | | | | | | | | | |
| dense large | gemma-4-31B | llama.cpp | QAT Q4_0 | B | 4 × 16 | | | | | | | | | | | |
| MoE | gemma-4-26B-A4B | llama.cpp | QAT Q4_0 | A | 1 × 8 | | | | | | | | | | | |
| MoE | gemma-4-26B-A4B | llama.cpp | QAT Q4_0 | B | 4 × 32 | | | | | | | | | | | |
| MoE | gpt-oss-120b | llama.cpp | MXFP4 | A | 1 × 8 | the anchors, above | | | | | | | | | | |
| MoE | gpt-oss-120b | llama.cpp | MXFP4 | B | 4 × 32 | the anchors, above | | | | | | | | | | |

vLLM's rows follow in slice 3.

### Quantization pairs

gemma-4-E4B, single stream, 1 × 8 (shape A):

| Engine | Format | Output tok/s | TTFT median ms | ITL median ms | Latency median s | Server gen tok/s | Footprint GiB |
|---|---|---|---|---|---|---|---|
| llama.cpp | Q8_0 | | | | | | |
| llama.cpp | QAT Q4_0 | | | | | | |

### Vision

gemma-4-26B-A4B, one synthetic 720p JPEG and 200 text tokens a request, 64 out:

| Engine | Cell | Streams × requests | Completed | Errored | Prompt tokens median | Output tok/s | TTFT median ms | TTFT p95 ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|---|
| llama.cpp | A | 1 × 8 | | | | | | | | |
| llama.cpp | B | 4 × 32 | | | | | | | | |

### Embeddings

EmbeddingGemma 2, 512 tokens a request, 30 s a level:

| Engine | Format | Streams | Completed | Errored | Requests/s | Prompt tokens median | Latency median ms | Latency p95 ms |
|---|---|---|---|---|---|---|---|---|
| llama.cpp | Q8_0 | 1 | | | | | | |
| llama.cpp | Q8_0 | 16 | | | | | | |

### ASR

gemma-4-E4B Q8_0's audio through chat, one LibriSpeech clip a request with the card's prompt:

| Engine | Cell | Streams × requests | Completed | Errored | Audio s/s | Output tokens median | TTFT median ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|
| llama.cpp | A | 1 × 8 | | | | | | | |
| llama.cpp | B | 4 × 32 | | | | | | | |

### Concurrency sweep

gpt-oss-120b MXFP4 on 16 slots, 512 in, 256 out, 60 s a level. At 32 streams, 16 requests wait for
a slot at a time. Requests in flight when a level's 60 s end are cancelled and counted incomplete.

| Engine | Streams | Completed | Incomplete | Errored | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|---|
| llama.cpp | 1 | | | | | | | | | |
| llama.cpp | 4 | | | | | | | | | |
| llama.cpp | 16 | | | | | | | | | |
| llama.cpp | 32 | | | | | | | | | |

Server figures over the whole sweep: to be recorded.

### Cold load and footprint

Each load timed from a dropped page cache, from the load request to `loaded`. The footprint is
MemAvailable before less after, beside the buffers the engine logged.

| Engine | Model | Format | Cache before → after drop | MemAvailable before GiB | MemAvailable after GiB | Footprint GiB | Weights (logged) | KV cache (logged) | Compute (logged) | Projector (logged) | Load s |
|---|---|---|---|---|---|---|---|---|---|---|---|
| llama.cpp | gpt-oss-120b, 4 slots | MXFP4 | | | | | | | | — | |
| llama.cpp | gpt-oss-120b, 16 slots | MXFP4 | | | | | | | | — | |
| llama.cpp | gemma-4-E4B | Q8_0 | | | | | | | | | |
| llama.cpp | gemma-4-E4B | QAT Q4_0 | | | | | | | | | |
| llama.cpp | gemma-4-12B | QAT Q4_0 | | | | | | | | | |
| llama.cpp | gemma-4-31B | QAT Q4_0 | | | | | | | | | |
| llama.cpp | gemma-4-26B-A4B | QAT Q4_0 | | | | | | | | | |
| llama.cpp | EmbeddingGemma 2 | Q8_0 | | | | | | | | | |

### Network path and build, per model

| Engine | Model | `tailscale ping` | Build (`/props` build_info) |
|---|---|---|---|
| llama.cpp | each model in order | | |

### API probes

| Surface | Model | llama.cpp | vLLM |
|---|---|---|---|
| Chat with a tool | gpt-oss-120b | | |
| Reasoning | gpt-oss-120b | | |
| Anthropic messages with a tool | gpt-oss-120b | | |
| Responses | gpt-oss-120b | | |
| Vision | gemma-4-26B-A4B | | |
| Embeddings | EmbeddingGemma 2 | | |
| Transcription | gemma-4-E4B | | on paper: v0.32.0 serves it for Granite Speech, Whisper, and Voxtral, not Gemma 4 |

### gemma-4-26B-A4B beside gpt-oss-120b

The same load on both engines: 512 in, 256 out, reasoning on.

| Model | Cell | llama.cpp format | llama.cpp output tok/s | llama.cpp TTFT median ms | llama.cpp ITL median ms | vLLM format | vLLM output tok/s | vLLM TTFT median ms | vLLM ITL median ms |
|---|---|---|---|---|---|---|---|---|---|
| gemma-4-26B-A4B | A, 1 × 8 | QAT Q4_0 | | | | NVFP4 | | | |
| gemma-4-26B-A4B | B, 4 × 32 | QAT Q4_0 | | | | NVFP4 | | | |
| gpt-oss-120b | A, 1 × 8 | MXFP4 | | | | MXFP4 | | | |
| gpt-oss-120b | B, 4 × 32 | MXFP4 | | | | MXFP4 | | | |
