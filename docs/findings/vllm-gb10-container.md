# vLLM in a container on the GB10s

Recorded on 2026-10-23, from [the vLLM setup guide](../engines/vllm/setup.md), GB10, in a
container.

The pinned release is v0.32.0, vLLM's latest GitHub release, run from `vllm/vllm-openai:v0.32.0`,
and the model it serves is `nvidia/Gemma-4-26B-A4B-NVFP4` (`engines/vllm.env`).

## Host stack

Each host was brought current with `sudo apt update && sudo apt upgrade`, without a reboot, before
its stack was recorded; the stack is the one running.

| Item | gb10-1 | gb10-2 |
|---|---|---|
| DGX OS | 7.6.0 | 7.6.0 |
| Driver | 580.178.04 | 580.178.04 |
| CUDA | 13.0 | 13.0 |
| Kernel | 7.0.0-1019-nvidia | 7.0.0-1019-nvidia |
| Reboot pending | no | no |
| Docker | 29.6.2 | 29.6.2 |
| NVIDIA Container Toolkit | 1.20.1 (commit dffc40b) | 1.20.1 (commit dffc40b) |

The stack is the one llama.cpp's finding recorded. On gb10-1 the upgrade installed nothing that
touches the engine. On gb10-2 it moved `dgx-dashboard` from 0.39.3-4 to 0.39.3-5 only, kept back
`cloud-init` and `lldpd`, which apt's phased updates held, and left the kernel as it was;
needrestart deferred restarting `docker.service`, whose binary hadn't changed.

## The pinned image on the GPU

Both hosts pulled the same image:

| Item | gb10-1 | gb10-2 |
|---|---|---|
| Digest | `sha256:befccf0e7e4089aa23926bb6f887a85c0d46c2a99e6de5c5ffdf5cb7957c5b34` | the same |
| `vllm --version` | 0.32.0 | 0.32.0 |
| CUDA device found | NVIDIA GB10, 124544 MiB | NVIDIA GB10, 124544 MiB |

## Serving and the model store

`engines/engines vllm install` started the server at v0.32.0 on each host, bound to its tailnet
address on port 8000, with 4 sequences of 8192 tokens and 0.80 of the GPU's memory
(`engines/vllm.sh`). Each start below is timed from the container's first log line, or its start,
to `Application startup complete.`

### gb10-1

The first install served the checkpoint's KV cache type (`--kv-cache-dtype auto`, FP8), and its
cold start downloaded the model:

| Phase | Time |
|---|---|
| Download, unauthenticated | 1373.9 s |
| Weight load | 137.6 s (68.7 s a shard) |
| Model loading, in all | 1514.9 s |
| Engine init | 92.55 s, compile 33.96 s |
| Multimodal warmup | 37.8 s |
| Cold start, first log 19:58:33 to startup complete 20:25:41Z | about 27 min |

vLLM chose FlashInfer's CUTLASS kernels for the NVFP4 experts and Triton for attention (FA4 isn't
available), on its V2 model runner. It applied the model's shipped generation config:
temperature 1.0, top_k 64, top_p 0.95. `/health` answered 200, and a second install changed
nothing.

It warned that it quantized the FP8 KV cache with a scale of 1.0, since the checkpoint declares
FP8 but ships no k/v scales, and that the experts' `w1` and `w3` `weight_scale_2` differ. On the
first warning the architect chose a BF16 KV cache (`--kv-cache-dtype bfloat16`), and install and
update now compare the whole served command, flags included, not the image and model alone.

`engines/engines vllm update` restarted the container under the BF16 flags, without a pull or a
download; a second update changed nothing. Before it, `docker inspect` showed the running
container's command with `--kv-cache-dtype auto`.

| Phase | Time |
|---|---|
| Weight load | 133.98 s |
| Model loading, in all | 137.6 s |
| Engine init | 82.18 s, compile 27.48 s |
| Warm restart, started 21:24:26Z to `/health` 200 by 21:28:31Z | about 4m05s (polled every 5 s) |

The BF16 start printed no FP8 or scale warnings, and its KV cache holds half the FP8 one's tokens,
as BF16's two bytes a value against FP8's one predict:

| KV cache | Size | Tokens |
|---|---|---|
| FP8 (`auto`) | 75.16 GiB | 942,397 |
| BF16 | 74.43 GiB | 466,576 |

Either holds the 4 sequences of 8192 tokens (32,768) many times over.

The memory vLLM reported at each start:

| Figure | FP8 start | BF16 start |
|---|---|---|
| Free on startup | `Free memory on device (113.08/121.63 GiB) on startup` | 113.54/121.63 GiB |
| Weights | 18.13 GiB | 18.13 GiB |
| Consumed by the model | 21.45 GiB | 22.07 GiB |
| Peak activation | not recorded | 0.8 GiB |
| KV cache | 75.16 GiB | 74.43 GiB |

The FP8 start's free figure was read with a warm page cache: the model had just been downloaded
and read. At the BF16 start, 0.80 of 121.63 GiB is 97.30 GiB, and 97.30 less the 22.07 consumed
and the 0.8 of activation leaves 74.43, the KV cache's size.

After the download, `du -sh` of the model's directory showed 4.9M and `~/.cache/vllm` 358M: the
Hugging Face client in vLLM's image keeps the weight files in a shared store at the cache's root,
`/srv/models/blobs`, which the guide now describes
([Models](../engines/vllm/models.md#the-first-download)).

### From the laptop

Against gb10-1 under the BF16 flags, by its short name, which MagicDNS resolves:

| Check | Result |
|---|---|
| `tailscale ping` | direct over the LAN, 1 ms (llama.cpp's cells ran over Tailscale's DERP relay) |
| `/version` | `{"version":"0.32.0"}` |
| Chat completion ([API](../engines/vllm/api.md#a-chat-completion)) | `content` "Hello!", with Gemma 4's reasoning apart in `reasoning` |
| `/metrics` | `vllm:num_requests_running` 0, `vllm:prompt_tokens_total` 22, `vllm:generation_tokens_total` 188 |
| `/v1/models` | id `nvidia/Gemma-4-26B-A4B-NVFP4`, `max_model_len` 8192 |

### llama.cpp refuses

While `vllm` ran on gb10-1, `engines/engines llama install` refused, changing nothing: `vllm is
running, and one engine serves per host at a time; docker stop vllm stops it`.

### The copy to gb10-2

The model went from gb10-1 to gb10-2 over QSFP, its directory and the shared store together
([Models](../engines/vllm/models.md#copying-the-model-to-the-other-gb10)):

| Copy | Bytes | Files | Time | Rate |
|---|---|---|---|---|
| `rsync -a` over SSH, gb10-1 to gb10-2-qsfp | 18,825,682,060 | 22 | 0:00:28 | 624.52 MB/s |

On gb10-2, `find -xtype l` over the model's snapshots printed nothing, so every link resolved, and
`du -shL` of the model showed 18G. As with llama.cpp's copy, one SSH stream runs far below the
link's bandwidth.

### gb10-2

An earlier install on gb10-2, during the guide's step 6, had started `vllm` at 20:22:30Z under
the FP8 flags, before the copy, and downloaded the model itself in 735.8 s. Its FP8 KV cache held
945,745 tokens; weight load took 140.2 s and engine init 87.34 s (compile 34.03 s).

After the pull, `engines/engines vllm install` refused, as it should, since the running container
served other flags: `under other server flags; engines vllm update moves it to the pin`. Update
then restarted it under the BF16 flags:

| Phase | Time |
|---|---|
| Weight load | 126.12 s |
| Engine init | 76.59 s, compile 27.76 s, for the new flags |
| Warm restart, started 21:39:08Z to `/health` 200 by 21:42:57Z | about 3m49s |

It downloaded nothing; its BF16 KV cache holds 470,467 tokens, and a second install changed
nothing. Since gb10-2's store already held the model it had downloaded, this start doesn't prove
that a copied model loads without a download from a store that held none; the walkthrough, on a
store emptied first, proves it.

## Anchor cells

Run on 2026-10-23, against gb10-1 at v0.32.0 under the BF16 flags, with the host stack
[above](#host-stack). These are vLLM's anchor cells, A' and B', which a later task reruns before
it compares with this one. They mirror llama.cpp's A and B
([llama.cpp in a container](llama-gb10-container.md#anchor-cells)) on vLLM's own model.

### Method

GuideLLM 0.8.1 drives the server from the laptop, through the spike's bench environment
(`mise.bench.toml`: Python 3.14.9, uv 0.13.5). Each cell is a scenario under `bench/`: streaming
OpenAI chat completions to `nvidia/Gemma-4-26B-A4B-NVFP4`, each request 512 synthetic prompt
tokens and exactly 256 output tokens. The prompt is cut to its 512 by the served checkpoint's own
tokenizer, fetched from Hugging Face, and Gemma 4's chat template adds its own tokens to what the
server counts. GuideLLM sends `max_completion_tokens` with `ignore_eos`, both of which v0.32.0's
chat completions accept, so every request generates its full 256, whatever the model would have
said. Each stream sends its requests back to back:

| Cell | Scenario | Streams | Requests |
|---|---|---|---|
| A' | `bench/vllm-anchor-a.yaml` | 1 | 8 |
| B' | `bench/vllm-anchor-b.yaml` | 4 | 32 |

Cell B' runs one stream per sequence of the server's 4. Every request asks Gemma 4 to reason, with
`"chat_template_kwargs": {"enable_thinking": true}` added to its body, as the API page's chat
completion does: gpt-oss reasons in every request of llama.cpp's cells, and Gemma 4 reasons only
when asked. Since `ignore_eos` fixes each request at 256 tokens either way, this changes what the
tokens say, not how many there are. GuideLLM counts the reasoning the server streams in
`reasoning` as output, and its first token starts TTFT.

The client figures are GuideLLM's: output throughput across the cell, all streams together; TTFT,
to the first streamed token; ITL, between tokens after the first; and request latency, start to
last token. The server figures are vLLM's own counters from `/metrics`
([API](../engines/vllm/api.md#metrics)), differenced over the cell:

- prompt: the prompt tokens the server computed, `vllm:prompt_tokens_total` less
  `vllm:prompt_tokens_cached_total`, which it took from its prefix cache, over
  `vllm:request_prefill_time_seconds_sum`, each request's time from being scheduled to its first
  token;
- generated: the tokens generated after each request's first, `vllm:generation_tokens_total`
  less one a request (`vllm:request_decode_time_seconds_count`), over
  `vllm:request_decode_time_seconds_sum`, each request's time from its first token to its last.

vLLM counts every prompt token in `vllm:prompt_tokens_total`, cached or not, where llama.cpp
counted the ones it processed, hence the subtraction; and the first token comes with the prefill,
outside the decode time, hence one a request less. The server sums those seconds per request, so
at 4 streams, whose requests run at once, they are one request's rate, not the cell's; the
client's output throughput is the aggregate.

Each cell should take a minute or two: llama.cpp's cell A ran in 42 s and B in 99 s on
gpt-oss-120b, about 5B of 117B parameters active a token, and Gemma 4 26B-A4B activates 4B of
26B in NVFP4.

### Running the cells

The server needs no change: vLLM serves `/metrics` without a flag. Everything runs on the laptop,
from the root of this repository's clone. Install the bench environment once, if llama.cpp's cells
haven't; it downloads GuideLLM and its dependencies, torch among them:

```sh
MISE_ENV=bench mise install
```

Record the network path to gb10-1, by its short name, which MagicDNS resolves, since every client
figure carries the round trip, and the release the server runs:

```sh
tailscale ping -c 3 gb10-1
curl -s "http://gb10-1:8000/version"
```

`/version` prints `{"version":"0.32.0"}`. Warm the model with one chat request, the API page's
own, which asks it to reason as the cells do:

```sh
curl -s "http://gb10-1:8000/v1/chat/completions" -H "Content-Type: application/json" -d '{"model": "nvidia/Gemma-4-26B-A4B-NVFP4", "messages": [{"role": "user", "content": "Say hello in one sentence."}], "chat_template_kwargs": {"enable_thinking": true}}' | jq '.choices[0].message'
```

Point GuideLLM at the server, which it reads from its environment, and make the directory the
cells write to; `.state/` is untracked:

```sh
export GUIDELLM__SPEC__BACKEND__TARGET="http://gb10-1:8000"
mkdir -p .state/vllm-anchor
```

Run each cell with its letter in `cell`: first `cell=a`, then the same four commands with
`cell=b`. Each takes a `/metrics` snapshot, runs the cell, which writes GuideLLM's JSON to
`.state/vllm-anchor/$cell.json`, and takes a second snapshot. The first run fetches the
tokenizer from Hugging Face:

```sh
cell=a
curl -s "http://gb10-1:8000/metrics" > .state/vllm-anchor/$cell.before.metrics
MISE_ENV=bench mise exec -- guidellm run -c bench/vllm-anchor-$cell.yaml
curl -s "http://gb10-1:8000/metrics" > .state/vllm-anchor/$cell.after.metrics
```

`vllm:num_requests_running` in the first snapshot is 0 when nothing else is using the server.

### Reading the figures

For each cell, with `cell` set to its letter, the client figures, with GuideLLM's and Python's
versions and the cell's duration; this is llama.cpp's read-out, since GuideLLM's JSON is the same:

```sh
jq '.metadata as $v | .benchmarks[0] | .metrics as $m | {guidellm: $v.guidellm_version, python: $v.python_version, duration_s: .duration, requests: $m.request_totals, prompt_tokens: $m.prompt_token_count.successful.median, output_tokens: $m.output_token_count.successful.median, output_tok_s: $m.output_tokens_per_second.successful.mean, ttft_ms: ($m.time_to_first_token_ms.successful | {median, p95: .percentiles.p95}), itl_ms: ($m.inter_token_latency_ms.successful | {median, p95: .percentiles.p95}), latency_s: ($m.request_latency.successful | {median, p95: .percentiles.p95})}' .state/vllm-anchor/$cell.json
```

And the server figures, the counters differenced between the two snapshots. vLLM labels each
series with its engine and model, so the read-out drops the labels and adds up a name's series:

```sh
awk '!/^#/ { k = $1; sub(/\{.*/, "", k); d[k] += (NR == FNR ? -$2 : $2) } END { m = "vllm:"; n = d[m "request_decode_time_seconds_count"]; p = d[m "prompt_tokens_total"]; c = d[m "prompt_tokens_cached_total"]; g = d[m "generation_tokens_total"]; printf "%d requests; prompt %d tokens, %d from the prefix cache, %.1f tok/s; generated %d tokens, %.1f tok/s\n", n, p, c, (p - c) / d[m "request_prefill_time_seconds_sum"], g, (g - n) / d[m "request_decode_time_seconds_sum"] }' .state/vllm-anchor/$cell.before.metrics .state/vllm-anchor/$cell.after.metrics
```

### Results

| Cell | Streams | Requests | Completed | Errored | Duration s | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | Latency median s | Latency p95 s | Server prompt tok/s | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A' | 1 | 8 | | | | | | | | | | | |
| B' | 4 | 32 | | | | | | | | | | | |
