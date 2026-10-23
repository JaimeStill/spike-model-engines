# llama.cpp in a container on the GB10s

Recorded on 2026-10-23, from [the llama.cpp setup guide](../engines/llama.cpp/setup.md), GB10,
in a container.

The pinned build is b11669, the b-build named by llama.cpp's latest semver release, v0.7.0, run
from `ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669` (`engines/llama.env`).

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
| NVIDIA Container Toolkit | 1.20.1 | 1.20.1 |

## The pinned image on the GPU

```sh
docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669 --version
docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669 --list-devices
```

| Host | Build printed | CUDA device found |
|---|---|---|
| gb10-1 | 0.7.0-dev (build 11669, commit 620d2225c) | CUDA0: NVIDIA GB10 (124544 MiB, 119719 MiB free) |
| gb10-2 | 0.7.0-dev (build 11669, commit 620d2225c) | CUDA0: NVIDIA GB10 (124544 MiB, 119727 MiB free) |

The image's CUDA 13.4.1 runtime runs on the hosts' 580.178.04 driver, which reports CUDA 13.0.

On gb10-1 the first GPU run failed with `failed to fulfil mount request: open
/usr/lib/aarch64-linux-gnu/libnvidia-egl-wayland.so.1.1.21: no such file or directory`. The
upgrade had moved `libnvidia-egl-wayland1` from 1.1.21 to 1.1.23, and the toolkit's CDI spec,
`/var/run/cdi/nvidia.yaml`, generated at the last boot, still named 1.1.21. Regenerating the spec
with `sudo nvidia-ctk cdi generate --output=/var/run/cdi/nvidia.yaml` fixed it; a reboot would
have regenerated it too. gb10-2 ran the regeneration after its upgrade, from the guide, and
started the image first time.

## Serving and the model store

`engines/engines llama install` started the router at b11669 on both hosts, bound to each host's
tailnet address on port 8080; a second run changed nothing, and `/health` answered
`{"status":"ok"}`. The server warns that it has no API key and that CORS allows every origin; the
port is published on the tailnet address only, and access control belongs to spike-model-gateway.

gpt-oss-120b MXFP4 (63,387,346,248 bytes) downloaded from Hugging Face into gb10-1's store and
loaded on CUDA0, running as the architect's user. gb10-2's own download was cancelled with
`docker restart llama` and its partial files deleted; the model was then copied from gb10-1 over
QSFP and loaded on gb10-2 without a download:

| Copy | Bytes | Time | Rate |
|---|---|---|---|
| `rsync -a` over SSH, gb10-1 to gb10-2-qsfp | 63,387,346,248 | 1m50.6s | 549 MB/s |

The copy is one SSH stream, so it ran far below the link's RDMA bandwidth (about 185 Gb/s on
both halves of the port, per dotfiles).

From the laptop, gb10-1 answered an OpenAI chat completion ("Say hello in one sentence.") with
`content` "Hello!" and gpt-oss's reasoning in `reasoning_content`, and `/v1/models` listed the
model `loaded`.

`engines/engines llama update` on gb10-1, already at the pin, changed nothing. `engines/engines
llama uninstall` on gb10-2 removed the container and its image, a second run changed nothing, no
llama.cpp image remained, and `/srv/models` kept the model.

## Anchor cells

Run on 2026-10-23, against gb10-1 at b11669, with the host stack [above](#host-stack). These are
the cells a later task reruns before it compares with this one.

### Method

GuideLLM 0.8.1 drives the router from the laptop, through the spike's bench environment
(`mise.bench.toml`: Python 3.14.9, uv 0.13.5). Each cell is a scenario under `bench/`: streaming
OpenAI chat completions to gpt-oss-120b MXFP4 (`ggml-org/gpt-oss-120b-GGUF:MXFP4`), each request
512 synthetic prompt tokens and exactly 256 output tokens. The prompt is cut to its 512 by the
model's upstream tokenizer, `openai/gpt-oss-120b`, fetched from Hugging Face, and gpt-oss's chat
template adds its own tokens to what the server counts. GuideLLM sends `max_tokens` with
`ignore_eos`, so every request generates its full 256, reasoning included, whatever the model
would have said. Each stream sends its requests back to back:

| Cell | Scenario | Streams | Requests |
|---|---|---|---|
| A | `bench/anchor-a.yaml` | 1 | 8 |
| B | `bench/anchor-b.yaml` | 4 | 32 |

Cell B runs one stream per slot of the preset's 4. The client figures are GuideLLM's: output
throughput across the cell, all streams together; TTFT, to the first streamed token; ITL, between
tokens after the first; and request latency, start to last token. The server figures are
llama.cpp's own counters from the model's `/metrics` ([API](../engines/llama.cpp/api.md#metrics)),
differenced over the cell: prompt tokens over prompt seconds, and generated tokens over generation
seconds. The server sums those seconds per slot, so at 4 streams they are one request's rate, not
the cell's; the client's output throughput is the aggregate.

### Running the cells

`/metrics` needs the preset's `metrics = true`, which a loaded model only takes when it is loaded
again. On gb10-1, from `spike-model-engines`, take the preset and reload it, which unloads
gpt-oss-120b:

```sh
git pull
curl -s "http://$(tailscale ip -4):8080/models?reload=1" > /dev/null
```

The rest runs on the laptop, from the root of this repository's clone. Install the bench
environment once; it downloads GuideLLM and its dependencies, torch among them:

```sh
MISE_ENV=bench mise install
```

Set `GB10` to gb10-1's tailnet address ([Models](../engines/llama.cpp/models.md#the-hosts-address-on-the-laptop)),
load the model, and list the models until it shows `loaded`:

```sh
GB10=<tailnet address>
curl -s -X POST "http://$GB10:8080/models/load" -H "Content-Type: application/json" -d '{"model": "ggml-org/gpt-oss-120b-GGUF:MXFP4"}'
curl -s "http://$GB10:8080/models" | jq '.data[] | {id, status: .status.value}'
```

Record the build the model runs and the network path to the host, since every client figure
carries the round trip:

```sh
curl -sG "http://$GB10:8080/props" --data-urlencode "model=ggml-org/gpt-oss-120b-GGUF:MXFP4" --data-urlencode autoload=false | jq -r .build_info
tailscale ping -c 3 "$GB10"
```

Point GuideLLM at the router, which it reads from its environment, and make the directory the
cells write to; `.state/` is untracked:

```sh
export GUIDELLM__SPEC__BACKEND__TARGET="http://$GB10:8080"
mkdir -p .state/anchor
```

Run each cell with its letter in `cell`: first `cell=a`, then the same four commands with
`cell=b`. Each takes a `/metrics` snapshot, runs the cell, which writes GuideLLM's JSON to
`.state/anchor/$cell.json`, and takes a second snapshot:

```sh
cell=a
curl -sG "http://$GB10:8080/metrics" --data-urlencode "model=ggml-org/gpt-oss-120b-GGUF:MXFP4" --data-urlencode autoload=false > .state/anchor/$cell.before.metrics
MISE_ENV=bench mise exec -- guidellm run -c bench/anchor-$cell.yaml
curl -sG "http://$GB10:8080/metrics" --data-urlencode "model=ggml-org/gpt-oss-120b-GGUF:MXFP4" --data-urlencode autoload=false > .state/anchor/$cell.after.metrics
```

`llamacpp:requests_processing` in the first snapshot is 0 when nothing else is using the model.

### Reading the figures

For each cell, with `cell` set to its letter, the client figures, with GuideLLM's and Python's
versions and the cell's duration:

```sh
jq '.metadata as $v | .benchmarks[0] | .metrics as $m | {guidellm: $v.guidellm_version, python: $v.python_version, duration_s: .duration, requests: $m.request_totals, prompt_tokens: $m.prompt_token_count.successful.median, output_tokens: $m.output_token_count.successful.median, output_tok_s: $m.output_tokens_per_second.successful.mean, ttft_ms: ($m.time_to_first_token_ms.successful | {median, p95: .percentiles.p95}), itl_ms: ($m.inter_token_latency_ms.successful | {median, p95: .percentiles.p95}), latency_s: ($m.request_latency.successful | {median, p95: .percentiles.p95})}' .state/anchor/$cell.json
```

And the server figures, the counters differenced between the two snapshots:

```sh
awk '{ d[$1] += (NR == FNR ? -$2 : $2) } END { m = "llamacpp:"; printf "prompt %d tokens, %.1f tok/s; generated %d tokens, %.1f tok/s\n", d[m "prompt_tokens_total"], d[m "prompt_tokens_total"] / d[m "prompt_seconds_total"], d[m "tokens_predicted_total"], d[m "tokens_predicted_total"] / d[m "tokens_predicted_seconds_total"] }' .state/anchor/$cell.before.metrics .state/anchor/$cell.after.metrics
```

### Results

| Cell | Streams | Requests | Completed | Errored | Duration s | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | Latency median s | Latency p95 s | Server prompt tok/s | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | 1 | 8 | 8 | 0 | 42.0 | 48.8 | 477 | 702 | 18.3 | 5.16 | 5.41 | 1485 | 54.0 |
| B | 4 | 32 | 31 | 1 | 99.2 | 80.0 | 1239 | 1413 | 44.5 | 12.60 | 12.79 | 1348 | 22.1 |
| B, rerun | 4 | 32 | 32 | 0 | 101.3 | 80.9 | 1420 | 1974 | 43.2 | 12.51 | 12.85 | 1627 | 22.5 |

Run on 2026-10-23 from the laptop against gb10-1 at b11669 (`/props` build_info
`b11669-620d2225c`), GuideLLM 0.8.1 on Python 3.14.9. The laptop reached gb10-1 through Tailscale's
DERP relay in New York (`tailscale ping`: 92, 55, 57 ms; `tailscale netcheck`: UDP true), not
directly, so TTFT and request latency include the relay's round trip. ITL and the server figures
do not depend on the path: cell A's ITL of 18.3 ms is 54.5 tok/s, against the server's 54.0.

- Each request carried 579 prompt tokens: the 512 synthetic tokens plus gpt-oss's chat template.
  The server processed fewer prompt tokens than were sent (cell A 4,198 of 4,632), because it
  reused the cached template prefix.
- The server's generation rate is per request, since `tokens_predicted_seconds_total` adds up
  each request's decode time: with 4 streams, 22.1 tok/s per stream, about 88 tok/s across the
  four, against the client's 80.0 output tok/s.
- Cell B's errored request failed in the client: GuideLLM could not parse one streamed chunk
  (`JSONDecodeError('Unterminated string starting at: line 1 column 64 (char 63)')`). The server
  generated 240 of its 256 tokens (8,176 generated against 31 × 256 = 7,936), so the engine kept
  serving; the error is between the stream and the client, over the relay.
- Cell B was rerun the same day on the same build, after the walkthrough and a fresh install,
  over the same relay (DERP nyc, about 55 ms): 32 of 32 completed, so the parse
  error did not recur. Output tok/s, ITL, and latency agree with the first run within 3%. TTFT is
  higher (median 1420 against 1239 ms) and the server processed 16,792 prompt tokens against
  12,448: the rerun started on a freshly loaded model, with no prompt cache from cell A.

## Walkthrough

The architect ran the whole procedure on each GB10 from the guide alone: install at v0.6.0's
b11429, serve, update to v0.7.0's b11669, serve again, and uninstall. Both stores already held
gpt-oss-120b, so no step downloaded it.

| Step | gb10-2 | gb10-1 |
|---|---|---|
| `engines/engines llama install b11429`, `/props` build_info | `b11429-d81235049` | `b11429-d81235049` |
| Chat completion at b11429 | "Hello! I hope your day is wonderful." | "Hello! Hope you’re having a wonderful day." |
| `engines/engines llama update`, images left | `server-cuda13-b11669` only | `server-cuda13-b11669` only; it printed `llama moved from …b11429 to …b11669` and `removed image …b11429` |
| Second `engines/engines llama update` | nothing changed | nothing changed |
| Model reloaded from the store, `/props` build_info | `b11669-620d2225c` | `b11669-620d2225c` |
| Chat completion at b11669 | "Hello! I’m glad you’re here." | "Hello, I hope your day is going spectacularly well!" |
| `engines/engines llama uninstall`, images left, store | container and b11669 image removed; none left; model kept | container and b11669 image removed; none left; model kept |

After the walkthrough, the standards review changed the scripts (a preflight before any pull or
removal, Docker errors passed up, and the container found by an exact name filter). The cell B
rerun's install still ran the earlier scripts, so gb10-1 then ran the final scripts against its
running container: `install` and `update` each said `llama already runs …b11669; nothing changed`,
`uninstall` removed the container and the b11669 image, and a second `uninstall` said `llama is not
installed; nothing changed`.
