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
it before the next step:

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

v0.32.0 logs `Free memory on device` only when the reservation doesn't fit, so its line is
expected only from a failed start.

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
with `f` set to the cell's JSON. The server figures are task 2's read-out, with `p` set to the
snapshots' path without its suffix: vLLM labels each series with its engine and model, so it
drops the labels and adds up a name's series:

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
| A' | task 2 | 8 | 0 | 68.25 | 30.0 | 237 | 299 | 32.4 | 8.51 | 8.57 | 5061 | 30.4 |
| A' | this session | | | | | | | | | | | |
| B' | task 2 | 32 | 0 | 77.31 | 106.0 | 426 | 465 | 36.3 | 9.66 | 9.79 | 2261 | 27.1 |
| B' | this session | | | | | | | | | | | |

Task 1 ran over Tailscale's DERP relay (about 55 ms), and task 2 directly over the LAN (1 ms),
with A''s warm-up unconfirmed; this session's path is recorded with each model, and A' and B' run
from a confirmed warm start.

### The FlashInfer diagnostic

A' on step 2's row, FlashInfer attention and text only, beside this session's A' on Triton:

| Cell | Attention | Started | Completed | Errored | Duration s | Output tok/s | TTFT median ms | ITL median ms | Latency median s | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|
| A' | Triton, vision loaded | yes | | | | | | | | |
| A' | FlashInfer, text only | | | | | | | | | |

The attention backend vLLM logged at each start: to be recorded.

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
| dense small | gemma-4-E4B | vLLM | BF16 | A | 1 × 8 | | | | | | | | | | | |
| dense small | gemma-4-E4B | vLLM | BF16 | B | 4 × 32 | | | | | | | | | | | |
| dense mid | gemma-4-12B | vLLM | QAT w4a16 | A | 1 × 8 | | | | | | | | | | | |
| dense mid | gemma-4-12B | vLLM | QAT w4a16 | B | 4 × 32 | | | | | | | | | | | |
| dense large | gemma-4-31B | vLLM | NVFP4 | A | 1 × 4 | | | | | | | | | | | |
| dense large | gemma-4-31B | vLLM | NVFP4 | B | 4 × 16 | | | | | | | | | | | |
| MoE | gemma-4-26B-A4B | vLLM | NVFP4 | A' | 1 × 8 | the anchors, above | | | | | | | | | | |
| MoE | gemma-4-26B-A4B | vLLM | NVFP4 | B' | 4 × 32 | the anchors, above | | | | | | | | | | |
| MoE | gpt-oss-120b | vLLM | MXFP4 | A | 1 × 8 | | | | | | | | | | | |
| MoE | gpt-oss-120b | vLLM | MXFP4 | B | 4 × 32 | | | | | | | | | | | |

vLLM's gpt-oss-120b serves 16 sequences in A and B, where llama.cpp's serves 4 slots; the load is
the same.

### Quantization pairs

gemma-4-E4B, single stream, 1 × 8 (shape A):

| Engine | Format | Output tok/s | TTFT median ms | ITL median ms | Latency median s | Server gen tok/s | Footprint GiB |
|---|---|---|---|---|---|---|---|
| llama.cpp | Q8_0 | | | | | | |
| llama.cpp | QAT Q4_0 | | | | | | |
| vLLM | BF16 | | | | | | |
| vLLM | QAT w4a16 | | | | | | |

### Vision

gemma-4-26B-A4B, one synthetic 720p JPEG and 200 text tokens a request, 64 out:

| Engine | Cell | Streams × requests | Completed | Errored | Prompt tokens median | Output tok/s | TTFT median ms | TTFT p95 ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|---|
| llama.cpp | A | 1 × 8 | | | | | | | | |
| llama.cpp | B | 4 × 32 | | | | | | | | |
| vLLM | A | 1 × 8 | | | | | | | | |
| vLLM | B | 4 × 32 | | | | | | | | |

### Embeddings

EmbeddingGemma 2, 512 tokens a request, 30 s a level:

| Engine | Format | Streams | Completed | Errored | Requests/s | Prompt tokens median | Latency median ms | Latency p95 ms |
|---|---|---|---|---|---|---|---|---|
| llama.cpp | Q8_0 | 1 | | | | | | |
| llama.cpp | Q8_0 | 16 | | | | | | |
| vLLM | BF16 | 1 | | | | | | |
| vLLM | BF16 | 16 | | | | | | |

### ASR

gemma-4-E4B's audio through chat (llama.cpp Q8_0, vLLM BF16), one LibriSpeech clip a request
with the card's prompt:

| Engine | Cell | Streams × requests | Completed | Errored | Audio s/s | Output tokens median | TTFT median ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|
| llama.cpp | A | 1 × 8 | | | | | | | |
| llama.cpp | B | 4 × 32 | | | | | | | |
| vLLM | A | 1 × 8 | | | | | | | |
| vLLM | B | 4 × 32 | | | | | | | |

### Concurrency sweep

gpt-oss-120b MXFP4 on 16 slots (llama.cpp) or 16 sequences (vLLM), 512 in, 256 out, 60 s a
level. At 32 streams, 16 requests wait for a slot at a time. Requests in flight when a level's 60 s end are cancelled and counted incomplete.

| Engine | Streams | Completed | Incomplete | Errored | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|---|
| llama.cpp | 1 | | | | | | | | | |
| llama.cpp | 4 | | | | | | | | | |
| llama.cpp | 16 | | | | | | | | | |
| llama.cpp | 32 | | | | | | | | | |
| vLLM | 1 | | | | | | | | | |
| vLLM | 4 | | | | | | | | | |
| vLLM | 16 | | | | | | | | | |
| vLLM | 32 | | | | | | | | | |

Server figures over the whole sweep, each engine: to be recorded.

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

vLLM's, each start timed from a dropped page cache, from the container's start to `Application
startup complete.`, and its footprint MemAvailable before the start less after, beside what vLLM
logged: the weights (`Model loading took`), the KV cache's memory (`Available KV cache memory`)
and tokens (`KV cache size`), and the CUDA graphs (`Graph capturing finished`). Every row
reserves 0.80 of the GB10's memory, so the footprint is near the reservation whatever the model.

| Step | Row | Cache before → after drop | MemAvailable before GiB | MemAvailable after GiB | Footprint GiB | Weights GiB (logged) | KV cache GiB (logged) | KV cache tokens (logged) | CUDA graphs GiB (logged) | Compile cache | Cold start |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `gemma-4-26B-A4B-NVFP4` | | | | | | | | | | |
| 2 | `gemma-4-26B-A4B-NVFP4-flashinfer` | | | | | | | | | | |
| 3 | `gemma-4-E4B-it` | | | | | | | | | | |
| 4 | `gemma-4-E4B-it-qat-w4a16-ct` | | | | | | | | | | |
| 5 | `gemma-4-12B-it-qat-w4a16-ct` | | | | | | | | | | |
| 6 | `Gemma-4-31B-IT-NVFP4` | | | | | | | | | | |
| 7 | `embeddinggemma-2` | | | | | | | | | | |
| 8 | `gpt-oss-120b` | | | | | | | | | | |
| 9 | `gemma-4-26B-A4B-NVFP4`, the pin restored | | | | | | | | | | |

gpt-oss-120b's row fits the reservation on paper: 0.80 of 121.63 GiB is 97.30 GiB, its weights
are 65.28 GB (60.8 GiB) on disk, and its KV cache at 16 sequences of 8192 tokens needs 4.5 GiB in
BF16 for its 18 full-attention layers (8 KV heads of 64, 36 KiB a token), its 18 sliding-window
layers holding 128 tokens each; about 30 GiB is left for it and the activations. The logged
figures confirm or refute that.
### Network path and build, per model

| Engine | Model | `tailscale ping` | Build (`/props` build_info) |
|---|---|---|---|
| llama.cpp | each model in order | | |
| vLLM | each row in order | | (`/version`) |

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
