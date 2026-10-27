# vLLM in a container on the GB10s

Recorded on 2026-10-23, from [the vLLM setup guide](../engines/vllm/setup.md), GB10, in a
container.

Its script paths were rewritten from `engines/` to `host/` by commit fe8bbeb, which renamed the suite's directory; nothing else changed.

The pinned release is v0.32.0, vLLM's latest GitHub release, run from `vllm/vllm-openai:v0.32.0`,
and the model it serves is `nvidia/Gemma-4-26B-A4B-NVFP4` (`host/vllm.env`).

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

`host/engines vllm install` started the server at v0.32.0 on each host, bound to its tailnet
address on port 8000, with 4 sequences of 8192 tokens and 0.80 of the GPU's memory
(`host/vllm.sh`). [Cold starts](#cold-starts) lists every start's time and how it was taken.

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

vLLM chose FlashInfer's CUTLASS kernels for the NVFP4 experts and Triton for attention (FA4 isn't
available), on its V2 model runner. It applied the model's shipped generation config:
temperature 1.0, top_k 64, top_p 0.95. `/health` answered 200, and a second install changed
nothing.

It warned that it quantized the FP8 KV cache with a scale of 1.0, since the checkpoint declares
FP8 but ships no k/v scales, and that the experts' `w1` and `w3` `weight_scale_2` differ. On the
first warning the architect chose a BF16 KV cache (`--kv-cache-dtype bfloat16`), and install and
update now compare the whole served command, flags included, not the image and model alone.

`host/engines vllm update` restarted the container under the BF16 flags, without a pull or a
download; a second update changed nothing. Before it, `docker inspect` showed the running
container's command with `--kv-cache-dtype auto`.

| Phase | Time |
|---|---|
| Weight load | 133.98 s |
| Model loading, in all | 137.6 s |
| Engine init | 82.18 s, compile 27.48 s |

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

On an integrated GPU, v0.32.0 reads the OS's available memory
(`psutil.virtual_memory().available`, in `vllm/utils/mem_utils.py`), which counts the page cache
as free. A start measured for it on gb10-1 on 2026-10-24 (the session ran it over SSH, after the
walkthrough) shows that: with the model's 18 GB read into the page cache first (`Cached` 18.2 GiB),
`/proc/meminfo` gave MemFree 99.7 GiB and MemAvailable 117.6 GiB before the start, and vLLM
reported `Free memory on device (113.42/121.63 GiB) on startup`. That is 13.7 GiB more than
MemFree, which only counting the page cache as free allows; the remaining 4 GiB below
MemAvailable went to the container and the process before the reading. The page cache also
didn't shorten the weight load: 113.65 s, against 134 s from a cold cache.

At the BF16 start, 0.80 of 121.63 GiB is 97.30 GiB, and 97.30 less the 22.07 consumed and the 0.8
of activation leaves 74.43, the KV cache's size.

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

While `vllm` ran on gb10-1, `host/engines llama install` refused, changing nothing: `vllm is
running, and one engine serves per host at a time; docker stop vllm stops it`. On 2026-10-24 `host/engines
llama update` refused the same way (exit 1).

### A stopped container

Found at the brief: install reported "already runs; nothing changed" for a stopped container.
After the fix, on gb10-1 on 2026-10-24, with `vllm` stopped by `docker stop vllm`, both
`host/engines vllm install` and `update` printed `vllm is installed with
vllm/vllm-openai:v0.32.0 and nvidia/Gemma-4-26B-A4B-NVFP4 but stopped; docker start vllm starts
it` (exit 0) and left it exited. After `docker start vllm`, both said `already runs …; nothing
changed`. From the laptop, `/version` answered `0.32.0`. The session then uninstalled vLLM again,
keeping the model.

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

After the pull, `host/engines vllm install` refused, as it should, since the running container
served other flags: `under other server flags; engines vllm update moves it to the pin`. Update
then restarted it under the BF16 flags:

| Phase | Time |
|---|---|
| Weight load | 126.12 s |
| Engine init | 76.59 s, compile 27.76 s, for the new flags |

It downloaded nothing; its BF16 KV cache holds 470,467 tokens, and a second install changed
nothing. gb10-2's store already held the model it had downloaded, so this start doesn't prove
that a copied model loads without a download.

### A copied model in an emptied store

During the walkthrough, gb10-2 proved it. After `host/engines vllm uninstall`, the architect
deleted the model with the guide's procedure
([Uninstall](../engines/vllm/uninstall.md#deleting-the-model)). The list of shared files held 3
blobs: the two weight shards and `tokenizer.json`. After the delete, the model's directory was
gone and the shared store, `/srv/models/blobs`, measured 32K. gb10-1 then copied the model again:

| Copy | Bytes | Files | Time | Rate |
|---|---|---|---|---|
| `rsync -a` over SSH, gb10-1 to gb10-2-qsfp | 18,825,681,731 | 20 | 0:00:40 | 447.34 MB/s |

`find -xtype l` printed nothing and `du -shL` of the model showed 18G. `host/engines vllm
install v0.31.0` then started the server with no download line in its log.

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

Cell A' ran in 68.25 s and B' in 77.31 s, within the 10-minute limit.

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
| A' | 1 | 8 | 8 | 0 | 68.25 | 30.0 | 237 | 299 | 32.4 | 8.51 | 8.57 | 5061 | 30.4 |
| B' | 4 | 32 | 32 | 0 | 77.31 | 106.0 | 426 | 465 | 36.3 | 9.66 | 9.79 | 2261 | 27.1 |

The read-out reported GuideLLM 0.8.1 on Python 3.14.9. The laptop reached gb10-1 directly over
the LAN (`tailscale ping`: 1 ms), so TTFT and request latency carry no relay's round trip. ITL's
p95 was 32.5 ms in A' and 36.7 ms in B'. The warm-up chat request before A' is not confirmed: it
was in the instructed sequence, but the walk's record doesn't show it and the architect doesn't
recall, so A''s TTFT may include a cold first request.

- Each request carried 528 prompt tokens: the 512 synthetic tokens plus Gemma 4's chat template.
  The server counted 4,224 prompt tokens in A' (8 × 528) and 16,896 in B' (32 × 528).
- The client and the server agree: A''s ITL of 32.4 ms is 30.8 tok/s, against the server's 30.4.
- The server's generation rate is per request, since it sums each request's decode time: in B',
  27.1 tok/s per stream, about 108 tok/s across the four, against the client's 106.0 output
  tok/s.
- In B' the server took 4,096 of its 16,896 prompt tokens from its prefix cache, 128 a request,
  and computed the rest at 2261 tok/s. The 128 are likely a prefix every request shares, from the
  chat template or the synthetic prompt; that is unverified. A' took none from the cache.
- A''s decode, 30 tok/s on a model with 4B parameters active a token, is slow against
  expectation. The server's log shows Triton attention, since FA4 isn't available, and the cells
  ran a BF16 KV cache. Why decode runs at this rate is an open question for
  bench-gb10-container. These cells are not compared with llama.cpp's A and B, which ran another
  model in another session ([Comparisons](../../context/README.md#rules)).

## Walkthrough

The architect ran the whole procedure on each GB10 from the guide alone: uninstall, install
v0.31.0, serve, update to v0.32.0, serve again, and uninstall. gb10-1's store held the model
throughout; gb10-2 deleted it and took a fresh copy before installing
([A copied model in an emptied store](#a-copied-model-in-an-emptied-store)).

| Step | gb10-1 | gb10-2 |
|---|---|---|
| `host/engines vllm uninstall` | removed the container, the v0.32.0 image, and the compile cache | the same |
| Second `uninstall` | `vllm is not installed; nothing changed`; no vLLM images; model kept, 18G | not recorded |
| Model | kept | deleted and copied again from gb10-1 |
| `host/engines vllm install v0.31.0` | digest `sha256:c1c9f6fd5c10…`; no download, empty compile cache; weight load 114.34 s, engine init 85.25 s (compile 27.96 s); BF16 KV cache 469,993 tokens | no download, empty compile cache; weight load 114.48 s, engine init 85.94 s (compile 27.64 s); KV cache 469,821 tokens |
| `/version` from the laptop | `0.31.0` | `0.31.0` |
| `host/engines vllm update` | pulled v0.32.0 (digest `befccf0e…`) before removing v0.31.0, and printed `moved from … to …`; the container's command shows `bfloat16` | pulled v0.32.0 first, printed `moved from … to …`, and removed v0.31.0 |
| Images left | v0.32.0 only (10.3 GB content, 35.3 GB on disk) | v0.32.0 only |
| Second `update` | nothing changed | nothing changed |
| `/version` from the laptop | not recorded (the container's command showed `vllm/vllm-openai:v0.32.0`) | `0.32.0` |
| Final `uninstall` | removed the container, the v0.32.0 image, and the compile cache | the same |
| Second `uninstall` | nothing changed; no images; model kept, 18G | nothing changed, run twice; no images; model kept, 18G |

## Cold starts

Every start of the container, in order. Each is timed from its start to the first of two signals:

- **Startup complete**: from `docker inspect`'s `StartedAt` to the log's `Application startup
  complete.` line, as [Setup](../engines/vllm/setup.md#6-watch-the-cold-start-and-record-it)
  records it.
- **`/health` 200**: from `StartedAt` to the first `/health` 200 of a poll every 5 s, so up to
  5 s late.

| Host | Start | Download | Started | Ready | Timed to | Cold start |
|---|---|---|---|---|---|---|
| gb10-1 | install v0.32.0, FP8 KV | 1373.9 s | 19:58:33, first log line | 20:25:41Z | startup complete | about 27 min |
| gb10-2 | install v0.32.0, FP8 KV | 735.8 s | 20:22:30Z | not captured | — | — |
| gb10-1 | update to the BF16 flags | none | 21:24:26Z | 21:28:31Z | `/health` 200 | about 4m05s |
| gb10-2 | update to the BF16 flags | none | 21:39:08Z | 21:42:57Z | `/health` 200 | about 3m49s |
| gb10-1 | install v0.31.0, empty compile cache | none | 22:20:56Z | 22:25:09Z | `/health` 200 | about 4m13s |
| gb10-1 | update to v0.32.0 | none | 22:36:48Z | 22:42:37Z | `/health` 200 | about 5m49s |
| gb10-2 | install v0.31.0, from the copy | none | 22:57:38Z | not captured; engine init done 23:01:44Z | — | — (about 4m06s to engine init) |
| gb10-2 | update to v0.32.0 | none | 23:30:47Z | 23:34:56Z | startup complete | 4m09s |

The first gb10-1 start is timed from the container's first log line, not `StartedAt`. Two polls
ran late, after the server was already up, and their times are discarded: gb10-2's v0.31.0
install (23:22:45Z) and its update to v0.32.0 (00:04:18Z). gb10-1's update from v0.31.0 to
v0.32.0 took about 5m49s, the longest start without a download; the record doesn't show why.
