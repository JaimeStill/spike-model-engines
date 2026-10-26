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

Every `stage` line and both pulls started together at 11:15:04 (-04:00), and every check passed
at 14:04. The logs weren't timed one by one, so the table gives each item's size and exit; the
sizes are the guide's, from Hugging Face's API.

| Item | Size | Exit |
|---|---|---|
| `ggml-org/gemma-4-E4B-it-GGUF` (Q8_0 + mmproj) | 8.59 GB | 1 at 11:59 and again at 12:33 (Xet); 0 with `HF_HUB_DISABLE_XET=1` |
| `google/gemma-4-E4B-it-qat-q4_0-gguf` | 6.15 GB | 0 |
| `google/gemma-4-12B-it-qat-q4_0-gguf` | 7.15 GB | 0 |
| `google/gemma-4-31B-it-qat-q4_0-gguf` | 18.85 GB | 0 |
| `google/gemma-4-26B-A4B-it-qat-q4_0-gguf` | 15.63 GB | 0 |
| `ggml-org/embeddinggemma-2-GGUF` | 0.86 GB | 0 |
| `google/gemma-4-E4B-it` | 16.02 GB | 0 |
| `google/gemma-4-E4B-it-qat-w4a16-ct` | 11.55 GB | 0 |
| `google/gemma-4-12B-it-qat-w4a16-ct` | 10.30 GB | 0 |
| `nvidia/Gemma-4-31B-IT-NVFP4` | 32.67 GB | 0 |
| `google/embeddinggemma-2` | 1.53 GB | 0 |
| `openai/gpt-oss-120b` (no `original/`, `metal/`) | 65.28 GB | 0 |
| llama.cpp image | not recorded | 0 |
| vLLM image | not recorded | 0 |

About 195 GB of models was new, with vLLM's image, in about 3 hours. The aggregate rate was 23 to
27 MB/s while many downloads ran and about 14 MB/s once few were left, with gb10-1 otherwise idle,
so the cap is upstream.

E4B's Q8_0 GGUF failed twice on the same file, each time with Xet's `File reconstruction error:
CAS Client Error: … error decoding response body`. Its `stage` line was run again after the first
failure, resuming; after the second, it was run with `HF_HUB_DISABLE_XET=1`, which downloads over
plain HTTP instead of Xet, for that repository only, and completed
([Models](../engines/llama.cpp/models.md#checking-that-every-download-is-complete)).

The completion checks passed: every log ends with `exit 0`, no `*.incomplete` file is left, `hf
cache ls` lists 14 repositories, 276.7G, and both images are present.

## Method

### The cells

Each cell is a GuideLLM scenario under `bench/`, sending streaming OpenAI chat completions, or
embeddings, from the laptop. Every scenario but the anchors' is engine-neutral: the model, the
tokenizer that cuts its synthetic prompt, and the JSON's path are given on the command line, and
the target in `GUIDELLM__SPEC__BACKEND__TARGET`, so vLLM's cells reuse the same files. Every
request with output tokens set is sent with `ignore_eos`, so it generates exactly that many.

| Cell | Scenario | Load | Models |
|---|---|---|---|
| A, B | `bench/anchor-a.yaml`, `anchor-b.yaml` | 512 in, 256 out; 1 × 8, 4 × 32 | llama.cpp: gpt-oss-120b, 4 slots; vLLM: gpt-oss-120b, 16 sequences, its model given on the command line |
| A', B' | `bench/vllm-anchor-a.yaml`, `vllm-anchor-b.yaml` | 512 in, 256 out, reasoning on; 1 × 8, 4 × 32 | vLLM: 26B-A4B NVFP4, which are also its MoE shape A and B; A' again on FlashInfer |
| Shape A, B | `bench/shape-a.yaml`, `shape-b.yaml` | 512 in, 256 out; 1 × 8, 4 × 32 | llama.cpp: E4B Q8_0, 12B, 26B-A4B; vLLM: E4B BF16, 12B |
| Large A, B | `bench/shape-large-a.yaml`, `shape-large-b.yaml` | 512 in, 256 out; 1 × 4, 4 × 16 | 31B, both engines |
| Quant pair | `bench/shape-a.yaml` | 512 in, 256 out; 1 × 8 | llama.cpp: E4B Q8_0 (its shape A) and E4B QAT Q4_0; vLLM: E4B BF16 (its shape A) and E4B QAT w4a16 |
| Vision A, B | `bench/vision-a.yaml`, `vision-b.yaml` | one synthetic 720p JPEG + 200 text tokens, 64 out; 1 × 8, 4 × 32 | 26B-A4B, both engines |
| ASR A, B | `bench/audio-a.yaml`, `audio-b.yaml` | one LibriSpeech clip + the card's transcription prompt, up to 256 out; 1 × 8, 4 × 32 | llama.cpp: E4B Q8_0; vLLM: E4B BF16 |
| Embeddings | `bench/embed.yaml` | 512 tokens; 1 then 16 streams, 30 s each | EmbeddingGemma 2, both engines |
| Sweep | `bench/sweep.yaml` | 512 in, 256 out; 1, 4, 16, then 32 streams, 60 s each | gpt-oss-120b, 16 slots (llama.cpp) or 16 sequences (vLLM) |

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

vLLM serves each model from its own checkpoint, which ships its tokenizer, so `tok` is the served
model, except for E4B's QAT row, which takes the BF16 model's, as llama.cpp's E4B sections do:

| vLLM row (`VLLM_MODEL`) | `model` | `tok` |
|---|---|---|
| `gemma-4-26B-A4B-NVFP4`, and its `-flashinfer` row | `nvidia/Gemma-4-26B-A4B-NVFP4` | `nvidia/Gemma-4-26B-A4B-NVFP4` (in A''s and B''s scenarios) |
| `gemma-4-E4B-it` | `google/gemma-4-E4B-it` | `google/gemma-4-E4B-it` |
| `gemma-4-E4B-it-qat-w4a16-ct` | `google/gemma-4-E4B-it-qat-w4a16-ct` | `google/gemma-4-E4B-it` |
| `gemma-4-12B-it-qat-w4a16-ct` | `google/gemma-4-12B-it-qat-w4a16-ct` | `google/gemma-4-12B-it-qat-w4a16-ct` |
| `Gemma-4-31B-IT-NVFP4` | `nvidia/Gemma-4-31B-IT-NVFP4` | `nvidia/Gemma-4-31B-IT-NVFP4` |
| `embeddinggemma-2` | `google/embeddinggemma-2` | `google/embeddinggemma-2` |
| `gpt-oss-120b` | `openai/gpt-oss-120b` | `openai/gpt-oss-120b` |

The rows' flags are in `engines/vllm-rows` ([vLLM's Models](../engines/vllm/models.md#the-rows)).

The client figures are GuideLLM's, and the server figures each engine's own `/metrics` counters,
differenced over each cell, as in [llama.cpp's anchor cells](llama-gb10-container.md#method) and
[vLLM's](vllm-gb10-container.md#method).

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

vLLM, after llama.cpp's last step, one row served at a time, each a new container started cold:

| Step | `row` (`VLLM_MODEL`) | Cells, then probes |
|---|---|---|
| 1 | `gemma-4-26B-A4B-NVFP4`, by `install` | A', B' (the anchors, and the MoE shape's A and B), vision A, vision B; probe: vision |
| 2 | `gemma-4-26B-A4B-NVFP4-flashinfer` | A' on FlashInfer, the diagnostic |
| 3 | `gemma-4-E4B-it` | shape A (also the quant pair's BF16), shape B, ASR A, ASR B |
| 4 | `gemma-4-E4B-it-qat-w4a16-ct` | shape A (the quant pair's w4a16) |
| 5 | `gemma-4-12B-it-qat-w4a16-ct` | shape A, shape B |
| 6 | `Gemma-4-31B-IT-NVFP4` | large A, large B |
| 7 | `embeddinggemma-2` | embeddings; probe: embeddings |
| 8 | `gpt-oss-120b` | A, B, sweep; probes: tools, reasoning, Anthropic messages, responses |
| 9 | the default, no `VLLM_MODEL` | none: the pin restored, its start timed |

gpt-oss-120b serves at 16 sequences once, for A, B, and the sweep, saving a cold start; at 1 and 4
streams the other sequences stand idle. Transcription is recorded on paper for vLLM
([vLLM's API](../engines/vllm/api.md#transcription-on-paper)). The FlashInfer diagnostic's result
is its decode against A''s, about 30 tok/s; should its row fail to start, the failure is the
result.

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

b11669 logs the buffer sizes only at verbosity 4, above its default of 3, which the preset sets
(`verbosity = 4`, [Models](../engines/llama.cpp/models.md#the-preset)). Step 1's first load, at
the default, logged none and was redone after the preset changed.

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

The embedding cell generates no tokens, so that read-out divides by zero there. Its server
figure is the prompt alone:

```sh
p=.state/bench/llama-embed
awk '{ d[$1] += (NR == FNR ? -$2 : $2) } END { m = "llamacpp:"; printf "prompt %d tokens in %.1f s, %.1f tok/s\n", d[m "prompt_tokens_total"], d[m "prompt_seconds_total"], d[m "prompt_tokens_total"] / d[m "prompt_seconds_total"] }' $p.before.metrics $p.after.metrics
```

The sweep's levels at 4 streams and more end with requests in flight, which the successful-only
figures leave out ([Concurrency sweep](#concurrency-sweep)), so its read-out takes the output rate
and TTFT over every request, GuideLLM's `total`:

```sh
f=.state/bench/$cell.json
jq '.benchmarks[] | .metrics as $m | {streams: .config.strategy.streams, requests: $m.request_totals, out_tok_s_total: $m.output_tokens_per_second.total.mean, ttft_ms_total: ($m.time_to_first_token_ms.total | {median, p95: .percentiles.p95}), itl_ms: ($m.inter_token_latency_ms.successful | {median, p95: .percentiles.p95}), latency_s: ($m.request_latency.successful | {median, p95: .percentiles.p95})}' "$f"
```

### API probes

From [llama.cpp's API page](../engines/llama.cpp/api.md#probes-of-the-api-surface), exactly as
written there, each after its model's cells (the order above).

### vLLM: once, before the first row

On gb10-1, from the clone, after llama.cpp's last step: pull the branch and stop llama.cpp's
router, since one engine serves at a time. `vllm` isn't installed (task 2 ended with its
uninstall), so step 1 installs it; the last command lists no `vllm`:

```sh
git pull --ff-only
docker stop llama
docker ps --all --filter name=vllm
```

On the laptop, the network path and the target, now vLLM's port:

```sh
tailscale ping -c 3 gb10-1
export GUIDELLM__SPEC__BACKEND__TARGET="http://gb10-1:8000"
mkdir -p .state/bench
```

### vLLM: per row, the switch, the cold start, and its footprint

On gb10-1, with `row` set to the step's row. Stop the running container first, so the memory
available before the start holds no model (step 1 has none to stop; step 9 leaves `row` unset).
Then drop the page cache, showing the cache before and after, and read the memory available:

```sh
row=gemma-4-26B-A4B-NVFP4
docker stop vllm
grep ^Cached /proc/meminfo; sync && sudo -n /usr/sbin/sysctl vm.drop_caches=3; grep ^Cached /proc/meminfo
grep ^MemAvailable /proc/meminfo
```

Switch to the row. Step 1 installs the default row, steps 2 to 8 serve the step's row for one
run, and step 9 returns to the default:

```sh
engines/engines vllm install
VLLM_MODEL=$row engines/engines vllm update
engines/engines vllm update
```

Each prints the row it serves and pulls nothing, since the image is already the pin's. Then wait
for the server, polling `/health` every 5 s for up to 10 minutes, and print the time, in UTC, and
the container's state:

```sh
for i in $(seq 120); do [ "$(curl -s -o /dev/null -w '%{http_code}' "http://$(tailscale ip -4):8000/health")" = 200 ] && break; sleep 5; done; date -u; docker inspect --format '{{.State.Status}}, restarts {{.RestartCount}}' vllm
```

`running, restarts 0` beside a time under the 10 minutes means the server answers. A row that
fails to start restarts under `--restart unless-stopped`; read its log's end, record it, and stop
it before the next step. Step 7's row ran this way: the poll ran its 10 minutes, the container had
restarted 12 times, and its cell and probe were skipped:

```sh
docker logs --tail 50 vllm
docker stop vllm
```

Time the cold start as task 2 did, from the container's start to the log's `Application startup
complete.` line ([Setup](../engines/vllm/setup.md#6-watch-the-cold-start-and-record-it)), and
check the command the container serves, which is the row's:

```sh
docker inspect --format '{{.State.StartedAt}}' vllm
docker logs --timestamps vllm 2>&1 | grep -m 1 "Application startup complete"
docker inspect --format '{{.Config.Image}} {{join .Config.Cmd " "}}' vllm
```

Then the memory available after the start, and the memory and compile lines vLLM logged for it:
the weights, the KV cache's memory and tokens, the CUDA graphs, and whether the compile was read
from the compile cache:

```sh
grep ^MemAvailable /proc/meminfo
docker logs vllm 2>&1 | grep -E "Model loading took|Available KV cache memory|KV cache size|Graph capturing finished|Directly load the compiled graph|Free memory on device"
```

v0.32.0 logs `Free memory on device` when the reservation doesn't fit, and step 1's start, which
succeeded, logged it too ([Cold load and footprint](#cold-load-and-footprint)).

### vLLM: per row, the version and the warm-up

On the laptop, with `model` and `tok` set to the row's values from the table above. The network
path, the release the server runs, the model it serves, then one warm-up request: the API page's
chat completion, which asks Gemma 4 to reason; for gpt-oss-120b without the `chat_template_kwargs`;
for EmbeddingGemma 2 one embedding. Last, the confirmation that the server is warm and idle:

```sh
model=nvidia/Gemma-4-26B-A4B-NVFP4
tok=nvidia/Gemma-4-26B-A4B-NVFP4
tailscale ping -c 3 gb10-1
curl -s "http://gb10-1:8000/version"
curl -s "http://gb10-1:8000/v1/models" | jq '.data[] | {id, max_model_len}'
curl -s "http://gb10-1:8000/v1/chat/completions" -H "Content-Type: application/json" -d "{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one sentence.\"}], \"chat_template_kwargs\": {\"enable_thinking\": true}}" | jq '.choices[0].message'
curl -s "http://gb10-1:8000/metrics" | grep -E '^vllm:(request_success_total|num_requests_running)'
```

For gpt-oss-120b, the warm-up instead:

```sh
curl -s "http://gb10-1:8000/v1/chat/completions" -H "Content-Type: application/json" -d "{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one sentence.\"}]}" | jq '.choices[0].message'
```

For EmbeddingGemma 2:

```sh
curl -s "http://gb10-1:8000/v1/embeddings" -H "Content-Type: application/json" -d "{\"model\": \"$model\", \"input\": \"Say hello in one sentence.\"}" | jq '{model, usage}'
```

The warm start is confirmed when the warm-up returned a reply, `vllm:request_success_total` counts
it, and `vllm:num_requests_running` is 0. A' and B' run only from a confirmed warm start, which
task 2's didn't record ([vLLM's anchor cells](vllm-gb10-container.md#results)).

### vLLM: per cell

On the laptop. A' and B' run their own scenarios, which name their model and tokenizer, with
`cell` set to `a`, then `b`; the JSON's path replaces the scenario's, so task 2's files in
`.state/vllm-anchor/` stay:

```sh
cell=a
curl -s "http://gb10-1:8000/metrics" > .state/bench/vllm-anchor-$cell.before.metrics
MISE_ENV=bench mise exec -- guidellm run -c bench/vllm-anchor-$cell.yaml --output "kind=json,path=.state/bench/vllm-anchor-$cell.json"
curl -s "http://gb10-1:8000/metrics" > .state/bench/vllm-anchor-$cell.after.metrics
```

The FlashInfer diagnostic is A' again, on step 2's row, under its own name:

```sh
curl -s "http://gb10-1:8000/metrics" > .state/bench/vllm-flashinfer-anchor-a.before.metrics
MISE_ENV=bench mise exec -- guidellm run -c bench/vllm-anchor-a.yaml --output "kind=json,path=.state/bench/vllm-flashinfer-anchor-a.json"
curl -s "http://gb10-1:8000/metrics" > .state/bench/vllm-flashinfer-anchor-a.after.metrics
```

Every other cell, with `scenario` and `cell` set as for llama.cpp's; gpt-oss-120b's A and B run
llama.cpp's anchor scenarios, with the model given on the command line in place of theirs:

```sh
scenario=vision-a
cell=vllm-26b-vision-a
curl -s "http://gb10-1:8000/metrics" > .state/bench/$cell.before.metrics
MISE_ENV=bench mise exec -- guidellm run -c bench/$scenario.yaml --backend "kind=openai_http,model=$model" --tokenizer "kind=huggingface_auto,model=$tok" --output "kind=json,path=.state/bench/$cell.json"
curl -s "http://gb10-1:8000/metrics" > .state/bench/$cell.after.metrics
```

`vllm:num_requests_running` in the first snapshot is 0 when nothing else is using the server.
The cells' names:

| Step | `scenario` | `cell` |
|---|---|---|
| 1 | `vision-a`, `vision-b` | `vllm-26b-vision-a`, `vllm-26b-vision-b` |
| 3 | `shape-a`, `shape-b`, `audio-a`, `audio-b` | `vllm-e4b-bf16-shape-a`, `vllm-e4b-bf16-shape-b`, `vllm-e4b-bf16-audio-a`, `vllm-e4b-bf16-audio-b` |
| 4 | `shape-a` | `vllm-e4b-w4a16-shape-a` |
| 5 | `shape-a`, `shape-b` | `vllm-12b-shape-a`, `vllm-12b-shape-b` |
| 6 | `shape-large-a`, `shape-large-b` | `vllm-31b-large-a`, `vllm-31b-large-b` |
| 7 | `embed` | `vllm-embed` |
| 8 | `anchor-a`, `anchor-b`, `sweep` | `vllm-gptoss-a`, `vllm-gptoss-b`, `vllm-gptoss-sweep` |

### vLLM: reading the figures

The client figures are read as llama.cpp's are ([Reading the figures](#reading-the-figures)),
with `f` set to the cell's JSON, adding `out_tok_s_total: $m.output_tokens_per_second.total.mean`
beside `output_tok_s`, and the sweep's with its read-out. The server figures are task 2's
read-out, with `p` set to the snapshots' path without its suffix: vLLM labels each series with its
engine and model, so it drops the labels and adds up a name's series:

```sh
p=.state/bench/$cell
awk '!/^#/ { k = $1; sub(/\{.*/, "", k); d[k] += (NR == FNR ? -$2 : $2) } END { m = "vllm:"; n = d[m "request_decode_time_seconds_count"]; p = d[m "prompt_tokens_total"]; c = d[m "prompt_tokens_cached_total"]; g = d[m "generation_tokens_total"]; printf "%d requests; prompt %d tokens, %d from the prefix cache, %.1f tok/s; generated %d tokens, %.1f tok/s\n", n, p, c, (p - c) / d[m "request_prefill_time_seconds_sum"], g, (g - n) / d[m "request_decode_time_seconds_sum"] }' $p.before.metrics $p.after.metrics
```

Its prompt figure is the tokens vLLM computed, less the ones it took from its prefix cache; its
generated figure is per request, since vLLM sums each request's decode time
([vLLM's anchor cells](vllm-gb10-container.md#method)). The embedding cell generates nothing, so
only its prompt tokens apply.

### vLLM: API probes

From [vLLM's API page](../engines/vllm/api.md#probes-of-the-api-surface), exactly as written
there, each after its row's cells (the order above): vision on step 1, embeddings on step 7, and
tools, reasoning, Anthropic messages, and responses on step 8.

### vLLM: back to the default

Step 9 ends the session on the pin, Gemma 4 26B-A4B NVFP4 with its anchor flags, which the guides
quote. Its start is timed and its footprint read like every other row's, and on the laptop
`/version` and `/v1/models` show `0.32.0` and `nvidia/Gemma-4-26B-A4B-NVFP4`; it runs no cell. On
gb10-1, a second update changes nothing and says so:

```sh
engines/engines vllm update
```

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

vLLM's, from task 2's A' and B' (Gemma 4 26B-A4B decoding about 30 tok/s at 1 stream) and the
models' sizes:

| Cell | Estimate |
|---|---|
| A', B', and A' on FlashInfer | 70 s, 80 s, 70 s (task 2: 68.25 s, 77.31 s) |
| Vision A, B, 26B-A4B | 0.5 min, 1 min |
| Shape A, B, E4B BF16 | 2 min, 2.5 min |
| Quant pair, E4B w4a16 | 1.5 min |
| ASR A, B, E4B BF16 | 0.5 min, 1 min |
| Shape A, B, 12B w4a16 | 1.5 min, 2.5 min |
| Large A, B, 31B NVFP4 | 2 min, 2.5 min |
| Embeddings | 1.5 min |
| A, B, gpt-oss-120b | 1 min, 2 min |
| Sweep | 4.5 min |
| Each cold start | 4 to 6 min (task 2: 3m49s to 5m49s without a download) |

## Results

Run on 2026-10-26 from the laptop against gb10-1, GuideLLM 0.8.1 on Python 3.14.10: llama.cpp's
steps from 14:08 to 14:40 (-04:00), vLLM's from 18:39Z to 19:57Z. The client figures are
GuideLLM's successful requests, except the sweep's output tok/s and TTFT
([Concurrency sweep](#concurrency-sweep)).

### Anchors

Rerun first, from the warm start above, against task 1's
([llama.cpp's anchor cells](llama-gb10-container.md#results)) and task 2's
([vLLM's](vllm-gb10-container.md#results)). An anchor moved beyond run noise is a finding.

| Cell | Run | Completed | Errored | Duration s | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | Latency median s | Latency p95 s | Server prompt tok/s | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | task 1 | 8 | 0 | 42.0 | 48.8 | 477 | 702 | 18.3 | 5.16 | 5.41 | 1485 | 54.0 |
| A | this session | 8 | 0 | 40.98 | 50.0 | 422 | 436 | 18.35 | 5.09 | 5.18 | 1528.0 | 53.8 |
| B | task 1, rerun | 32 | 0 | 101.3 | 80.9 | 1420 | 1974 | 43.2 | 12.51 | 12.85 | 1627 | 22.5 |
| B | this session | 32 | 0 | 101.27 | 80.9 | 1254 | 1262 | 45.47 | 12.75 | 13.31 | 1799.7 | 21.8 |
| A' | task 2 | 8 | 0 | 68.25 | 30.0 | 237 | 299 | 32.4 | 8.51 | 8.57 | 5061 | 30.4 |
| A' | this session | 8 | 0 | 68.10 | 30.1 | 241 | 320 | 32.33 | 8.49 | 8.56 | 5001.0 | 30.5 |
| B' | task 2 | 32 | 0 | 77.31 | 106.0 | 426 | 465 | 36.3 | 9.66 | 9.79 | 2261 | 27.1 |
| B' | this session | 32 | 0 | 77.53 | 105.7 | 433 | 447 | 36.41 | 9.69 | 9.79 | 2206.9 | 27.0 |

Task 1 ran over Tailscale's DERP relay (about 55 ms), and task 2 directly over the LAN (1 ms),
with A''s warm-up unconfirmed. This session's path was direct at every model, 0 to 2 ms, and A'
and B' ran from a confirmed warm start (the warm-up's reply, `vllm:request_success_total` 1,
`vllm:num_requests_running` 0).

- Every anchor held. Output tok/s is within 3% of the earlier runs on both engines, and so are
  ITL and the server's generation rate, except B's against task 1's rerun (ITL 45.47 against
  43.2 ms, generation 21.8 against 22.5 tok/s), which lie within 3% of task 1's first B (44.5 ms,
  22.1 tok/s).
- llama.cpp's TTFT fell (A's median 477 to 422 ms, B's 1420 to 1254 ms), as the relay's round
  trip left the path; ITL and the server figures, which don't depend on the path, held.
- The server took 4,138 of A's 4,632 prompt tokens and 12,448 of B's 18,528 to compute,
  reusing the cached template prefix, as in task 1. vLLM computed all of A''s 4,224 and took
  4,096 of B''s 16,896 from its prefix cache, as in task 2.

### The FlashInfer diagnostic

A' on step 2's row, FlashInfer attention and text only, beside this session's A' on Triton:

| Cell | Attention | Started | Completed | Errored | Duration s | Output tok/s | TTFT median ms | ITL median ms | Latency median s | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|
| A' | Triton, vision loaded | yes | 8 | 0 | 68.10 | 30.1 | 241 | 32.33 | 8.49 | 30.5 |
| A' | FlashInfer, text only | yes | 8 | 0 | 68.86 | 29.7 | 214 | 32.86 | 8.60 | 30.0 |

Step 2's start logged `Disabled mm_prefix attention mode because multimodal inputs are
configuration-disabled`, and FlashInfer resolved its decode backend to `xqa` and its prefill to
FlashInfer's native kernels, for a BF16 KV cache on SM121. Both rows logged NVFP4's MoE backend as
`FLASHINFER_CUTLASS`. Text only, the weights loaded 17.05 GiB against the default row's 18.13 GiB
([Cold load and footprint](#cold-load-and-footprint)).

### Shapes

| Shape | Model | Engine | Format | Cell | Streams × requests | Completed | Errored | Duration s | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | Latency median s | Latency p95 s | Server prompt tok/s | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| dense small | gemma-4-E4B | llama.cpp | Q8_0 | A | 1 × 8 | 8 | 0 | 49.82 | 41.1 | 264 | 344 | 23.30 | 6.21 | 6.31 | 2811.7 | 42.6 |
| dense small | gemma-4-E4B | llama.cpp | Q8_0 | B | 4 × 32 | 32 | 0 | 58.39 | 140.3 | 650 | 672 | 26.39 | 7.38 | 7.56 | 3818.8 | 37.5 |
| dense mid | gemma-4-12B | llama.cpp | QAT Q4_0 | A | 1 × 8 | 8 | 0 | 70.30 | 29.1 | 504 | 534 | 32.37 | 8.77 | 8.85 | 1619.8 | 30.6 |
| dense mid | gemma-4-12B | llama.cpp | QAT Q4_0 | B | 4 × 32 | 32 | 0 | 90.39 | 90.6 | 1597 | 1754 | 38.51 | 11.42 | 11.66 | 1748.5 | 25.7 |
| dense large | gemma-4-31B | llama.cpp | QAT Q4_0 | A | 1 × 4 | 4 | 0 | 91.02 | 11.3 | 1320 | 1330 | 84.08 | 22.75 | 22.77 | 610.5 | 11.8 |
| dense large | gemma-4-31B | llama.cpp | QAT Q4_0 | B | 4 × 16 | 16 | 0 | 112.64 | 36.4 | 4085 | 4465 | 96.59 | 28.72 | 29.13 | 706.0 | 10.3 |
| MoE | gemma-4-26B-A4B | llama.cpp | QAT Q4_0 | A | 1 × 8 | 8 | 0 | 31.15 | 65.7 | 298 | 417 | 13.97 | 3.88 | 3.98 | 2423.6 | 70.8 |
| MoE | gemma-4-26B-A4B | llama.cpp | QAT Q4_0 | B | 4 × 32 | 32 | 0 | 59.84 | 136.9 | 963 | 1060 | 25.85 | 7.52 | 7.67 | 2889.5 | 38.4 |
| MoE | gpt-oss-120b | llama.cpp | MXFP4 | A | 1 × 8 | the anchors, above | | | | | | | | | | |
| MoE | gpt-oss-120b | llama.cpp | MXFP4 | B | 4 × 32 | the anchors, above | | | | | | | | | | |
| dense small | gemma-4-E4B | vLLM | BF16 | A | 1 × 8 | 8 | 0 | 103.65 | 19.8 | 255 | 262 | 49.67 | 12.96 | 12.98 | 5834.3 | 19.8 |
| dense small | gemma-4-E4B | vLLM | BF16 | B | 4 × 32 | 32 | 0 | 91.65 | 89.4 | 462 | 466 | 43.25 | 11.49 | 11.56 | 2142.3 | 22.8 |
| dense mid | gemma-4-12B | vLLM | QAT w4a16 | A | 1 × 8 | 8 | 0 | 85.26 | 24.0 | 391 | 396 | 40.12 | 10.62 | 10.84 | 2049.0 | 24.6 |
| dense mid | gemma-4-12B | vLLM | QAT w4a16 | B | 4 × 32 | 32 | 0 | 90.85 | 90.2 | 1085 | 1103 | 41.02 | 11.48 | 11.67 | 913.0 | 23.6 |
| dense large | gemma-4-31B | vLLM | NVFP4 | A | 1 × 4 | 4 | 0 | 149.84 | 6.8 | 763 | 769 | 143.87 | 37.45 | 37.49 | 1678.6 | 6.9 |
| dense large | gemma-4-31B | vLLM | NVFP4 | B | 4 × 16 | 16 | 0 | 160.78 | 25.5 | 1570 | 1580 | 152.17 | 40.38 | 40.40 | 546.5 | 6.5 |
| MoE | gemma-4-26B-A4B | vLLM | NVFP4 | A' | 1 × 8 | the anchors, above | | | | | | | | | | |
| MoE | gemma-4-26B-A4B | vLLM | NVFP4 | B' | 4 × 32 | the anchors, above | | | | | | | | | | |
| MoE | gpt-oss-120b | vLLM | MXFP4 | A | 1 × 8 | 7 | 0 | 52.72 | 34.0 | 330 | 332 | 28.21 | 7.52 | 7.54 | 2217.5 | 35.0 |
| MoE | gpt-oss-120b | vLLM | MXFP4 | B | 4 × 32 | 32 | 0 | 94.53 | 86.7 | 733 | 752 | 43.70 | 11.76 | 12.28 | 1238.0 | 22.4 |

vLLM's gpt-oss-120b serves 16 sequences in A and B, where llama.cpp's serves 4 slots; the load is
the same.

- Each Gemma 4 request carried 528 prompt tokens and each gpt-oss request 579: the 512 synthetic
  tokens plus the chat template.
- vLLM's gpt-oss-120b A recorded 7 requests in GuideLLM, none errored or incomplete, where the
  server counted 8 (`request_decode_time_seconds_count`); the scenario sends 8. The record doesn't
  show why.
- vLLM's prompt rate counts only the tokens it computed: it took 4,096 of 16,896 prompt tokens in
  each Gemma 4 B from its prefix cache, 2,048 of 8,448 in the 31B's B, and 512 and 6,144 in
  gpt-oss-120b's A and B.
- vLLM's warm-up on E4B returned no reasoning text with `enable_thinking` set.

### Quantization pairs

gemma-4-E4B, single stream, 1 × 8 (shape A). The footprint is MemAvailable's fall over the load;
vLLM's reserves 0.80 of the memory whatever the model, so its row adds what vLLM logged it
consumed ([Cold load and footprint](#cold-load-and-footprint)).

| Engine | Format | Output tok/s | TTFT median ms | ITL median ms | Latency median s | Server gen tok/s | Footprint GiB |
|---|---|---|---|---|---|---|---|
| llama.cpp | Q8_0 | 41.1 | 264 | 23.30 | 6.21 | 42.6 | 10.5 |
| llama.cpp | QAT Q4_0 | 63.1 | 207 | 14.98 | 4.03 | 66.1 | 8.0 |
| vLLM | BF16 | 19.8 | 255 | 49.67 | 12.96 | 19.8 | 101.7 (17.77 consumed) |
| vLLM | QAT w4a16 | 51.6 | 172 | 18.68 | 4.94 | 52.7 | 102.0 (14.29 consumed) |

E4B QAT Q4_0's TTFT p95 was 312 ms and its latency p95 4.20 s; the server computed 4,159 prompt
tokens at 3369.6 tok/s. E4B w4a16's were 176 ms and 5.08 s; the server computed 4,224 at
5105.2 tok/s.

### Vision

gemma-4-26B-A4B, one synthetic 720p JPEG and 200 text tokens a request, 64 out:

| Engine | Cell | Streams × requests | Completed | Errored | Prompt tokens median | Output tok/s | TTFT median ms | TTFT p95 ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|---|
| llama.cpp | A | 1 × 8 | 8 | 0 | 623 | 36.6 | 869 | 1206 | 1.70 | 2.04 |
| llama.cpp | B | 4 × 32 | 32 | 0 | 623 | 64.5 | 3012 | 3115 | 4.55 | 4.62 |
| vLLM | A | 1 × 8 | 8 | 0 | 479 | 26.2 | 321 | 793 | 2.38 | 2.84 |
| vLLM | B | 4 × 32 | 32 | 0 | 479 | 82.7 | 1018 | 1038 | 3.25 | 3.29 |

The prompt token counts are the client's, which counts the image as its tokenizer sees it. The
servers' figures: llama.cpp computed 4,896 prompt tokens in A at 827.3 tok/s and 14,728 in B at
904.4 tok/s, and generated at 72.9 and 39.9 tok/s a request; vLLM computed 3,831 in A at 1453.7
tok/s and 15,325 in B, 3,584 of them from its prefix cache, at 538.9 tok/s, and generated at 30.6
and 27.8 tok/s a request.

### Embeddings

EmbeddingGemma 2, 512 tokens a request, 30 s a level:

| Engine | Format | Streams | Completed | Incomplete | Errored | Requests/s | Prompt tokens median | Latency median ms | Latency p95 ms |
|---|---|---|---|---|---|---|---|---|---|
| llama.cpp | Q8_0 | 1 | 1105 | 0 | 0 | 36.8 | 513 | 23 | 25 |
| llama.cpp | Q8_0 | 16 | 1552 | 16 | 0 | 51.7 | 513 | 306 | 313 |
| vLLM | BF16 | 1 | unsupported: the row doesn't start on GB10 at v0.32.0 | | | | | | |
| vLLM | BF16 | 16 | unsupported: the row doesn't start on GB10 at v0.32.0 | | | | | | |

llama.cpp's input rate was 18,896 tokens/s at 1 stream and 26,539 at 16. Its server computed
1,371,252 prompt tokens over both levels in 47.1 s, 29.1k tok/s, by the prompt-only read-out
([Reading the figures](#reading-the-figures)). The 16 incomplete requests at 16 streams were in
flight when the level's 30 s ended.

vLLM's `embeddinggemma-2` row crash-looped at step 7: `/health` never answered 200 within the
10 minutes, and the container had restarted 12 times by 19:36Z. Its log ended in Triton's
encoder attention (`_forward_encoder_attention`, then `context_attention_fwd`):

```text
triton.runtime.errors.OutOfResources: out of resource: shared memory, Required: 163840, Hardware limit: 101376
```

The kernel needs 160 KiB of shared memory, and the GB10's SM121 has 99 KiB. EmbeddingGemma 2's
model config defaults to Triton attention. The container was stopped, and the embedding cell and
probe were not run. Another attention backend was not tried.

### ASR

gemma-4-E4B's audio through chat (llama.cpp Q8_0, vLLM BF16), one LibriSpeech clip a request
with the card's prompt:

| Engine | Cell | Streams × requests | Completed | Errored | Audio s/s | Output tokens median | TTFT median ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|
| llama.cpp | A | 1 × 8 | 8 | 0 | 13.05 | 19 | 200 | 0.68 | 2.29 |
| llama.cpp | B | 4 × 32 | 32 | 0 | 22.34 | 16 | 392 | 1.08 | 2.77 |
| vLLM | A | 1 × 8 | 8 | 0 | 7.21 | 20 | 170 | 1.13 | 4.39 |
| vLLM | B | 4 × 32 | 32 | 0 | 26.44 | 16 | 168 | 0.95 | 2.49 |

vLLM's image carries none of `av`, `soundfile`, `soxr`, or `librosa`, but has `torchcodec`
0.17.0+cu130, `torchaudio` 2.11.0+cu130, and `ffmpeg`; v0.32.0's audio loader tries torchcodec
first, so the audio decoded without a derived image, as both cells show. The check, on gb10-1:

```sh
docker run --rm --entrypoint python3 vllm/vllm-openai:v0.32.0 -c "import importlib; ..."
docker run --rm --entrypoint sh vllm/vllm-openai:v0.32.0 -c "command -v ffmpeg"
```

The first command tried to import `av`, `soundfile`, `soxr`, `librosa`, `mistral_common`,
`torchcodec`, and `torchaudio`; the record keeps the module list, not the whole script.

### Concurrency sweep

gpt-oss-120b MXFP4 on 16 slots (llama.cpp) or 16 sequences (vLLM), 512 in, 256 out, 60 s a
level. At 32 streams, 16 requests wait for a slot at a time. Requests in flight when a level's 60 s
end are cancelled and counted incomplete.

At 4 streams and more, a 60 s level completes little more than its first wave of requests, so
GuideLLM's successful-only output rate is the successful requests' tokens over the level's
duration (llama.cpp at 16 streams: 16 × 256 / 60 = 68.3 tok/s) and leaves out every token the
incomplete requests produced. Output tok/s and TTFT here are GuideLLM's `total`, over every
request, completed or not; ITL and latency are the successful requests'.

| Engine | Streams | Completed | Incomplete | Errored | Output tok/s (total) | TTFT median ms (total) | TTFT p95 ms (total) | ITL median ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|---|
| llama.cpp | 1 | 11 | 1 | 0 | 48.5 | 418 | 476 | 18.89 | 5.24 | 5.30 |
| llama.cpp | 4 | 16 | 4 | 0 | 77.1 | 1318 | 1651 | 46.19 | 13.17 | 13.43 |
| llama.cpp | 16 | 16 | 16 | 0 | 129.0 | 5440 | 5976 | 104.70 | 32.59 | 34.17 |
| llama.cpp | 32 | 16 | 32 | 0 | 126.2 | 5791 | 37926 | 108.22 | 33.22 | 34.79 |
| vLLM | 1 | 8 | 1 | 0 | 34.7 | 135 | 140 | 28.34 | 7.36 | 7.37 |
| vLLM | 4 | 16 | 4 | 0 | 83.4 | 708 | 717 | 44.86 | 12.15 | 12.29 |
| vLLM | 16 | 32 | 16 | 0 | 168.2 | 2083 | 2160 | 87.04 | 24.28 | 24.68 |
| vLLM | 32 | 32 | 32 | 0 | 168.7 | 25537 | 26362 | 87.72 | 25.35 | 49.11 |

Server figures over the whole sweep: llama.cpp computed 52,568 prompt tokens at 1564.0 tok/s and
generated 23,192 at 11.9 tok/s a slot; vLLM served 88 requests, computed 72,375 prompt tokens,
12,608 of them from its prefix cache, at 935.4 tok/s, and generated 27,430 at 15.9 tok/s a
request.

### Cold load and footprint

Each load timed from a dropped page cache, from the load request to `loaded`. The footprint is
MemAvailable before less after, beside the buffers the engine logged, in MiB, on the GPU (CUDA0)
and the host (CUDA_Host); a KV figure of two parts is the full-attention layers' and the
sliding-window layers'. Each projector's line gives its model size and, for E4B Q8_0, its compute
buffers.

| Engine | Model | Format | Cache before → after drop GiB | MemAvailable before GiB | MemAvailable after GiB | Footprint GiB | Weights MiB (logged, GPU + host) | KV cache MiB (logged) | Compute MiB (logged, GPU + host) | Projector MiB (logged) | Load s |
|---|---|---|---|---|---|---|---|---|---|---|---|
| llama.cpp | gpt-oss-120b, 4 slots | MXFP4 | 54.1 → 0.35 | 117.4 | 55.6 | 61.8 | 59851.68 + 586.82 (output 3.07) | 1152.00 + 108.00 | 98.77 + 31.28 | — | 47.6 |
| llama.cpp | gpt-oss-120b, 16 slots | MXFP4 | 53.5 → 0.36 | 117.3 | 51.8 | 65.5 | 59851.68 + 586.82 (output 12.27) | 4608.00 + 432.00 | 98.77 + 31.28 | — | 47.8 |
| llama.cpp | gemma-4-E4B | Q8_0 | 47.2 → 0.36 | 117.4 | 106.9 | 10.5 | 4788.12 + 3536.00 (output 4.00) | 512.00 + 160.00 | 136.02 + 50.03 | 533.83; compute 101.27 + 101.19 | 9.1 |
| llama.cpp | gemma-4-E4B | QAT Q4_0 | 8.6 → 0.36 | 117.3 | 109.3 | 8.0 | 2696.06 + 2730.00 | 512.00 + 160.00 | 136.02 + 50.03 | 945.51 (BF16) | 6.5 |
| llama.cpp | gemma-4-12B | QAT Q4_0 | 6.3 → 0.36 | 117.3 | 106.3 | 11.0 | 6637.69 + 787.50 | 512.00 + 1920.00 | 129.52 + 39.53 | not recorded | 7.6 |
| llama.cpp | gemma-4-31B | QAT Q4_0 | 7.2 → 0.36 | 117.3 | 90.1 | 27.2 | 16818.28 + 1102.50 | 2560.00 + 4800.00 | 177.52 + 51.53 | 1145.08 | 16.9 |
| llama.cpp | gemma-4-26B-A4B | QAT Q4_0 | 18.1 → 0.36 | 117.3 | 99.1 | 18.1 | 13755.42 + 577.50 | 640.00 + 1200.00 | 152.52 + 31.53 | 1139.46 | 13.3 |
| llama.cpp | EmbeddingGemma 2 | Q8_0 | 15.2 → 0.36 | 117.1 | 114.0 | 3.1 | 144.44 + 136.00 (output 16.05) | — | 1088.66 + 320.72 | 529.05 | 2.9 |

gpt-oss-120b's first load, at 14:08, took 47.7 s and logged no buffer sizes: b11669 logs them only
at verbosity 4, above its default of 3. The preset gained `verbosity = 4` (commit 81ccb00), and
the load was redone at 14:10:37, the row above; its cache before the drop held 108.2 GiB, and
MemAvailable fell by the same 61.8 GiB. E4B's host buffer is its per-layer embeddings.
EmbeddingGemma 2's compute buffers are for its 8192-token micro-batch.

vLLM's, each start timed from a dropped page cache, from the container's start to `Application
startup complete.`, and its footprint MemAvailable before the start less after, beside what vLLM
logged: the weights and their load time (`Model loading took`), the KV cache's memory (`Available
KV cache memory`) and tokens (`KV cache size`), the CUDA graphs (`Graph capturing finished`), and
the memory its profile consumed. Every row reserves 0.80 of the GB10's memory, so the footprint is
near the reservation whatever the model.

| Step | Row | Cache before → after drop GiB | MemAvailable before GiB | MemAvailable after GiB | Footprint GiB | Weights GiB (logged), load s | KV cache GiB (logged) | KV cache tokens (logged) | CUDA graphs GiB (logged) | Consumed GiB (logged) | Cold start s |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `gemma-4-26B-A4B-NVFP4` | 1.4 → 0.22 | 117.8 | 18.0 | 99.8 | 18.13, 142.1 | 74.9 | 469,557 | 0.10 + 0.06 | 21.58 | 261.6 |
| 2 | `gemma-4-26B-A4B-NVFP4-flashinfer` | 17.6 → 0.18 | 117.9 | 18.7 | 99.3 | 17.05 (text only), 117.0 | 74.89 | 540,099 | 1.98 + 0.06 | not recorded | 211.5 |
| 3 | `gemma-4-E4B-it` | 18.1 → 0.19 | 117.9 | 16.2 | 101.7 | 15.08, 123.0 | 78.96 | 2,141,714 | 0.06 + 0.03 | 17.77 | 223.2 |
| 4 | `gemma-4-E4B-it-qat-w4a16-ct` | 16.1 → 0.18 | 117.9 | 15.9 | 102.0 | 11.04, 79.8 | 82.51 | 2,238,084 | not recorded | 14.29 | 176.7 |
| 5 | `gemma-4-12B-it-qat-w4a16-ct` | 12.9 → 0.18 | 117.9 | 16.5 | 101.4 | 8.28, 82.3 | 85.82 | 357,611 | not recorded | 11.15 | 190.3 |
| 6 | `Gemma-4-31B-IT-NVFP4` | 12.1 → 0.20 | 117.9 | 16.8 | 101.1 | 31.19, 216.4 | 61.68 | 96,666 | not recorded | 34.82 | 353.3 |
| 7 | `embeddinggemma-2` | not recorded | | | | | | | | | did not start: 12 restarts by 19:36Z |
| 8 | `gpt-oss-120b` | 3.5 → 0.19 | 117.4 | 19.1 | 98.4 | 66.14, 503.4 | 25.71 | 493,523 | 3.58 + 0.13 | 67.08 | 576.5 |
| 9 | `gemma-4-26B-A4B-NVFP4`, the pin restored | 18.5 → 0.17 | 118.0 | 17.6 | 100.4 | 18.13, 120.5 | 74.36 | 466,125 | not recorded | 22.13 | 176.2 |

- Step 1's start compiled afresh: its log had no `Directly load the compiled graph` line. It also
  logged `Free memory on device` (113.76 of 121.63 GiB at startup) on a start that succeeded.
- The peak activation memory vLLM logged was 0.81 GiB at step 1, 3.33 at step 2, 0.57 at step 3,
  0.51 at step 4, 0.34 at step 5, 0.8 at step 6, and 4.5 at step 8.
- gpt-oss-120b's row fit the reservation, as the arithmetic below expected: 66.14 GiB of weights,
  25.71 GiB of KV cache, 493,523 tokens. Its weights loaded in 503.4 s, where llama.cpp's MXFP4
  file loaded 58.4 GiB onto the GPU in 47.6 s.

gpt-oss-120b's row fits the reservation on paper: 0.80 of 121.63 GiB is 97.30 GiB, its weights
are 65.28 GB (60.8 GiB) on disk, and its KV cache at 16 sequences of 8192 tokens needs 4.5 GiB in
BF16 for its 18 full-attention layers (8 KV heads of 64, 36 KiB a token), its 18 sliding-window
layers holding 128 tokens each; about 30 GiB is left for it and the activations.

### Network path and build, per model

| Engine | Model | `tailscale ping` | Build |
|---|---|---|---|
| llama.cpp | each model, steps 1 to 8 | direct, 0 to 2 ms | `/props` build_info `b11669-620d2225c` |
| vLLM | each row, steps 1 to 9 | direct, 0 to 2 ms | `/version` `0.32.0` |

### API probes

| Surface | Model | llama.cpp | vLLM |
|---|---|---|---|
| Chat with a tool | gpt-oss-120b | works: `tool_calls`, `get_weather` naming Paris | works: `tool_calls`, `get_weather` naming Paris |
| Reasoning | gpt-oss-120b | works: 391, reasoning apart in `reasoning_content` | works: 391, reasoning apart in `reasoning` |
| Anthropic messages with a tool | gpt-oss-120b | works: a `tool_use` block and a thinking block | works: a `tool_use` block and a thinking block with a signature |
| Responses | gpt-oss-120b | works: `completed`, a `reasoning` and a `message` item | works: `completed`, a `reasoning` and a `message` item |
| Vision | gemma-4-26B-A4B | works: "A front page of The New York Times from July 21, 1969, featuring the historic headline "MEN WALK ON MOON."", 155 prompt and 505 completion tokens | works: the front page of The New York Times from Monday, July 21, 1969, "MEN WALK ON MOON", Apollo 11; 288 prompt and 49 completion tokens |
| Embeddings | EmbeddingGemma 2 | works: two embeddings of 768, each of norm 1.0; 25 prompt tokens | unsupported: the row doesn't start on GB10 at v0.32.0 ([Embeddings](#embeddings)) |
| Transcription | gemma-4-E4B | works: "And so my fellow Americans ask not what your country can do for you ask what you can do for your country", without punctuation; 298 prompt and 23 completion tokens | on paper: v0.32.0 serves it for Granite Speech, Whisper, and Voxtral, not Gemma 4 |

The vision probe's first form, `jq --arg img "$(base64 ...)"`, failed on the laptop with
`Argument list too long`; both API pages now read the base64 from a file with `--rawfile`, and
the probe ran in that form.

### gemma-4-26B-A4B beside gpt-oss-120b

The same load on both engines: 512 in, 256 out, reasoning on.

| Model | Cell | llama.cpp format | llama.cpp output tok/s | llama.cpp TTFT median ms | llama.cpp ITL median ms | vLLM format | vLLM output tok/s | vLLM TTFT median ms | vLLM ITL median ms |
|---|---|---|---|---|---|---|---|---|---|
| gemma-4-26B-A4B | A, 1 × 8 | QAT Q4_0 | 65.7 | 298 | 13.97 | NVFP4 | 30.1 | 241 | 32.33 |
| gemma-4-26B-A4B | B, 4 × 32 | QAT Q4_0 | 136.9 | 963 | 25.85 | NVFP4 | 105.7 | 433 | 36.41 |
| gpt-oss-120b | A, 1 × 8 | MXFP4 | 50.0 | 422 | 18.35 | MXFP4 | 34.0 | 330 | 28.21 |
| gpt-oss-120b | B, 4 × 32 | MXFP4 | 80.9 | 1254 | 45.47 | MXFP4 | 86.7 | 733 | 43.70 |

llama.cpp serves gpt-oss-120b on 4 slots here, vLLM on 16 sequences.

## Findings

Dated 2026-10-26, on gb10-1 in containers, llama.cpp b11669 and vLLM 0.32.0, on the host stack
above.

- **The anchors held on both engines.** llama.cpp's A and B and vLLM's A' and B' match tasks 1
  and 2 within 3% in output rate, ITL, and the server's generation rate; B's ITL and generation
  rate lie within 3% of task 1's first B, not of its rerun. Task 1's TTFT ran over a DERP relay;
  this session's path was direct, and llama.cpp's TTFT fell with it.
- **The attention backend is not the cause of vLLM's slow NVFP4 decode.** A' decoded at 30.5
  tok/s on Triton and 30.0 on FlashInfer, text only. Both NVFP4 rows decode at about half
  llama.cpp's QAT Q4_0 rate on the same model (26B-A4B 30.5 against 70.8 tok/s; 31B 6.9 against
  11.8), while vLLM's w4a16 rows reach about 80% of it (E4B 52.7 against llama.cpp's Q4_0 66.1;
  12B 24.6 against 30.6), in the servers' generation rates at 1 stream. The NVFP4 path, its MoE
  on `FLASHINFER_CUTLASS`, on SM121 is the remaining suspect; this task didn't test it.
- **vLLM's EmbeddingGemma 2 doesn't start on GB10 at v0.32.0.** Triton's encoder attention needs
  160 KiB of shared memory, and SM121 has 99 KiB (`OutOfResources: out of resource: shared memory,
  Required: 163840, Hardware limit: 101376`). Its embedding cell and probe are marked unsupported.
- **vLLM's audio through chat works from the pinned image.** The image has no `av`, `soundfile`,
  or `librosa`, but its audio loader decodes with `torchcodec`; no derived image is needed.
- **On gpt-oss-120b, llama.cpp leads a single stream and loads faster; vLLM leads from 4
  streams.** llama.cpp's single stream ran at 50.0 output tok/s against vLLM's 34.0, and it
  loaded in 48 s against vLLM's 577 s cold start. From 4 streams vLLM leads: 86.7 against 80.9 in
  B, 83.4 against 77.1 in the sweep, 168 against 129 at 16 streams, and 169 against 126 at 32.
  Past its slots, llama.cpp queues requests (TTFT p95 37.9 s at 32 streams), as vLLM's 16
  sequences do (26.4 s); neither errors. On the Gemma 4 shapes, in their own formats, llama.cpp
  led at 4 streams too (B: E4B 140.3 against 89.4, 26B-A4B 136.9 against 105.7, 31B 36.4 against
  25.5; 12B even, 90.6 against 90.2).
- **Embeddings on llama.cpp batch little.** EmbeddingGemma 2 went from 36.8 requests/s at 1
  stream to 51.7 at 16, while its median latency rose from 23 to 306 ms.
- **Quantization pairs.** On E4B at 1 stream, llama.cpp's QAT Q4_0 generated 66.1 tok/s against
  Q8_0's 42.6, and vLLM's QAT w4a16 52.7 against BF16's 19.8.
- **vLLM's footprint is its reservation; llama.cpp's is the model's.** vLLM reserves 0.80 of the
  memory whatever the row, so MemAvailable fell to 15.9 to 19.1 GiB at every start, from E4B to
  gpt-oss-120b. llama.cpp takes only the model's buffers: 3.1 GiB for EmbeddingGemma 2 to 65.5
  GiB for gpt-oss-120b at 16 slots.
- **Pre-staging took about 3 hours, capped upstream.** About 195 GB of new models and vLLM's image
  downloaded in parallel from 11:15 to 14:04 (-04:00): 23 to 27 MB/s in aggregate while many
  streams ran, about 14 MB/s with few, with the host otherwise idle. One file failed twice under
  Xet and completed over plain HTTP ([Pre-staging](#pre-staging)).
