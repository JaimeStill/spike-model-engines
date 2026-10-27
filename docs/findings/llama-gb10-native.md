# llama.cpp in a container and natively on gb10-1

Recorded on 2026-10-27, on gb10-1, from the steps and cells the task's brief agreed
(context/goals, `llama-gb10-native`). The same llama.cpp build runs in ggml's container and
natively under systemd, one after the other in one session, so only the hosting method differs
([Comparisons](../../context/README.md#rules)). It is evidence 6 for llama.cpp on the GB10
([The evidence](../../context/README.md#the-evidence)): install, update, rollback, startup, speed
parity, and GPU and memory access, container against bare metal. It records what was measured;
the spike's `answer` task chooses the hosting method.

The session ran each step on gb10-1 over Tailscale SSH, and each GuideLLM cell from the laptop,
from the clone at 6be0589 on `llama-gb10-native`.

## Host stack

| Item | gb10-1 |
|---|---|
| OS | Ubuntu 24.04.5 LTS |
| Kernel | 7.0.0-1019-nvidia |
| Driver | 580.178.04 |
| CUDA | 13.0 |
| Docker | 29.6.2 (build dfc4efb) |
| NVIDIA Container Toolkit | 1.20.1 |
| DGX OS | `DGX_SWBUILD_VERSION` 7.4.0, `DGX_OTA_VERSION` 7.6.0 |
| Reboot pending | no (no `/var/run/reboot-required`) |

gb10-1 had been brought current earlier on 2026-10-27, by the host-rename task, so this session
made no upgrade: at its start `apt list --upgradable` listed 0 packages.

## Engine versions

Both methods run llama.cpp v0.7.0 (b11669, commit 620d2225c), and both report `/props`
build_info `b11669-620d2225c`.

| Method | Release | Build | Source |
|---|---|---|---|
| Container | v0.7.0 | b11669 | `ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669` (`host/llama.env`), and for llama-bench `ghcr.io/ggml-org/llama.cpp:full-cuda13-b11669` |
| Native | v0.7.0 | b11669 | ggml's `llama-b11669-bin-ubuntu-cuda-13.4-arm64` prebuilt and its `cudart` tarball, under `/opt/llama.cpp/b11669`, served by the `llama-router` unit ([Setup](../engines/llama.cpp/setup.md#gb10-native)) |

Both run the CUDA 13.4 runtime on the host's 580.178.04 driver, which reports CUDA 13.0: the
container's from its image, native's from the `cudart` tarball unpacked beside the binaries. Both
serve the same preset (`host/llama-preset/models.ini`), model store (`/srv/models`), and router
flags (`--no-models-autoload`), on port 8080 of the tailnet address.

The load tool is GuideLLM 0.8.1 on the laptop, in the spike's bench environment
(`mise.bench.toml`: Python 3.14.10). llama-bench is the build's own
([llama-bench](../engines/llama.cpp/setup.md#llama-bench)).

## Method

### Native install, update, and rollback

On gb10-1, from `~/repos/spike-model-engines`. The architect's root steps, exactly as in the setup
guide ([1. The architect's root steps](../engines/llama.cpp/setup.md#1-the-architects-root-steps)):

```sh
sudo install -d -o "$(id -un)" -g "$(id -gn)" /opt/llama.cpp
sudo install -m 0644 host/llama-router.service /etc/systemd/system/llama-router.service
sudo systemctl daemon-reload
sudo visudo -cf host/llama-router.sudoers && sudo install -m 0440 host/llama-router.sudoers /etc/sudoers.d/llama-router
sudo -k
sudo -n systemctl stop llama-router
```

Then the session's install at v0.6.0 and update to the pin, on gb10-1, each followed by the setup
guide's checks ([3. Check it serves](../engines/llama.cpp/setup.md#3-check-it-serves)) or the
update's ([Native](../engines/llama.cpp/update.md#native)). `grep -v "#"` filters out the progress
bars curl prints while it fetches:

```sh
time host/engines llama-native install v0.6.0
time host/engines llama-native update 2>&1 | grep -v "#"
```

After each, from the laptop:

```sh
curl -s http://gb10-1:8080/health
```

The rollback to v0.6.0 and forward to the pin, from the laptop, each update followed by the
build, its version, the builds kept, and the time and `/health` from the laptop:

```sh
for v in v0.6.0 ""; do ssh gb10-1 "cd ~/repos/spike-model-engines && host/engines llama-native update $v 2>&1 | grep -v '#'; readlink /opt/llama.cpp/current; /opt/llama.cpp/current/llama-server --version 2>&1 | head -1; command ls /opt/llama.cpp | tr '\n' ' '; echo"; date +%T.%N; curl -sS -m5 http://gb10-1:8080/health; echo " exit=$?"; done
```

Then, on gb10-1, a second install and both containers' installs while native serves:

```sh
host/engines llama-native install; echo "exit=$?"; host/engines llama install; echo "exit=$?"; host/engines vllm install; echo "exit=$?"
```

It printed `exit=0`, `exit=1`, and `exit=1`.

### Switching between the methods

Before the container's cells, on gb10-1 from the clone, native llama.cpp stopped and disabled,
and the container started, waited for, and listed:

```sh
sudo -n systemctl stop llama-router && sudo -n systemctl disable llama-router && systemctl is-active llama-router
host/engines llama install
docker start llama >/dev/null && until curl -fs "http://$(tailscale ip -4):8080/health" >/dev/null; do sleep 1; done
docker ps --format "{{.Names}} {{.Image}} {{.Status}}"
```

Before native's, the container stopped and native llama.cpp enabled and started:

```sh
docker stop llama >/dev/null && docker ps -a --format "{{.Names}} {{.Status}}" | grep llama
host/engines llama-native install
```

### Per method: the cold load and its footprint

On gb10-1, from the clone, on a router just started, so no model was loaded. The container's
load, with bench-gb10-container's drop, load, and poll commands
([Per model: the cold load and its footprint](bench-gb10-container.md#per-model-the-cold-load-and-its-footprint)):

```sh
model=ggml-org/gpt-oss-120b-GGUF:MXFP4
echo; grep ^Cached /proc/meminfo; sync && sudo -n /usr/sbin/sysctl vm.drop_caches=3; grep ^Cached /proc/meminfo
grep ^MemAvailable /proc/meminfo
since=$(date -u +%Y-%m-%dT%H:%M:%SZ); start=$(date +%s.%N)
curl -s -X POST "http://$(tailscale ip -4):8080/models/load" -H "Content-Type: application/json" -d "{\"model\": \"$model\"}"; echo
while :; do s=$(curl -s "http://$(tailscale ip -4):8080/models" | jq -r --arg m "$model" '.data[] | select(.id == $m) | if .status.failed then "failed" else .status.value end'); [[ $s == loaded || $s == failed ]] && break; sleep 0.5; done
echo "$s after $(awk -v a="$start" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1f", b - a }') s"
grep ^MemAvailable /proc/meminfo
docker logs --since "$since" llama 2>&1 | grep -E "buffer size|model size|flash_attn|n_ctx |n_slots|n_parallel" | head -20
```

A later read confirmed the container's flash attention:

```sh
docker logs --since 5m llama 2>&1 | grep -i "flash attention\|flash_attn" | head -3
```

Native's, the same lines, but with `since` in the form `journalctl` reads, and the buffers read
from the unit's journal:

```sh
since=$(date "+%F %T"); start=$(date +%s.%N)
journalctl -u llama-router --since "$since" --no-pager -o cat | grep -E "buffer size|n_ctx  |flash_attn|Flash Attention|n_slots" | head -14
```

### Per method: the build, the path, and the warm-up

On the laptop, from the clone, after each method's load. Before the container's, the directory
the cells write to, which `.state/` keeps untracked:

```sh
mkdir -p .state/bench
```

Then, for each method, the time and the network path:

```sh
date -u +%FT%TZ; tailscale ping -c 3 gb10-1
```

and the build and the warm-up, as bench-gb10-container ran them
([Per model: the build and the warm-up](bench-gb10-container.md#per-model-the-build-and-the-warm-up)):

```sh
model=ggml-org/gpt-oss-120b-GGUF:MXFP4
tok=openai/gpt-oss-120b
curl -sG "http://gb10-1:8080/props" --data-urlencode "model=$model" --data-urlencode autoload=false | jq -r .build_info
curl -s "http://gb10-1:8080/v1/chat/completions" -H "Content-Type: application/json" -d "{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one sentence.\"}]}" | jq '.choices[0].message.content'
```

### Per cell

On the laptop, the anchor scenarios A (`bench/anchor-a.yaml`, 1 stream × 8 requests) and B
(`bench/anchor-b.yaml`, 4 streams × 32), as task 1 defined them
([Method](llama-gb10-container.md#method)): gpt-oss-120b MXFP4, 512 synthetic prompt tokens and
exactly 256 output tokens a request. Each method's cells ran as one block, A then B; the
container's:

```sh
export GUIDELLM__SPEC__BACKEND__TARGET="http://gb10-1:8080"; model=ggml-org/gpt-oss-120b-GGUF:MXFP4
for cell in a b; do
curl -sG "http://gb10-1:8080/metrics" --data-urlencode "model=$model" --data-urlencode autoload=false > .state/bench/llama-container-anchor-$cell.before.metrics
MISE_ENV=bench mise exec -- guidellm run -c bench/anchor-$cell.yaml --output "kind=json,path=.state/bench/llama-container-anchor-$cell.json" > .state/bench/llama-container-anchor-$cell.log 2>&1; echo "llama-container-anchor-$cell: guidellm exit $?"
curl -sG "http://gb10-1:8080/metrics" --data-urlencode "model=$model" --data-urlencode autoload=false > .state/bench/llama-container-anchor-$cell.after.metrics
done
```

Native's, the same block with `llama-native-anchor-$cell` in place of
`llama-container-anchor-$cell` throughout.

### Model state

Each method's cells start from the same state: gpt-oss-120b freshly loaded from a dropped page
cache, then the one warm-up request, then A, then B, with A's prompt cache. `llamacpp:requests_processing`
was 0 in every cell's first snapshot.

### Reading the figures

bench-gb10-container's read-outs ([Reading the figures](bench-gb10-container.md#reading-the-figures)),
with `cell` set to each cell's file name, such as `llama-native-anchor-a`:

```sh
f=.state/bench/$cell.json
jq -c '.metadata as $v | .benchmarks[] | .metrics as $m | {streams: .config.strategy.streams, duration_s: (.duration|floor), requests: $m.request_totals, prompt_tokens: $m.prompt_token_count.successful.median, output_tokens: $m.output_token_count.successful.median, output_tok_s: ($m.output_tokens_per_second.successful.mean|.*10|round/10), ttft_ms: ($m.time_to_first_token_ms.successful | {median: (.median|round), p95: (.percentiles.p95|round)}), itl_ms: ($m.inter_token_latency_ms.successful | {median: (.median*100|round/100), p95: (.percentiles.p95*100|round/100)}), latency_s: ($m.request_latency.successful | {median: (.median*100|round/100), p95: (.percentiles.p95*100|round/100)}), audio_s_per_s: $m.audio.seconds.input_per_second.successful.mean}' "$f"
jq '.benchmarks[].duration' "$f"
p=.state/bench/$cell
awk '{ d[$1] += (NR == FNR ? -$2 : $2) } END { m = "llamacpp:"; printf "prompt %d tokens, %.1f tok/s; generated %d tokens, %.1f tok/s\n", d[m "prompt_tokens_total"], d[m "prompt_tokens_total"] / d[m "prompt_seconds_total"], d[m "tokens_predicted_total"], d[m "tokens_predicted_total"] / d[m "tokens_predicted_seconds_total"] }' $p.before.metrics $p.after.metrics
```

### llama-bench

On gb10-1, after native's cells, with the container stopped, native llama.cpp stopped and
disabled, so no engine held a model:

```sh
sudo -n systemctl stop llama-router && sudo -n systemctl disable llama-router; systemctl is-active llama-router
mkdir -p ~/bench
```

pp512 and tg256, 5 repetitions, every layer on the GPU, and flash attention on (`-fa 1`), since
both servers logged `Flash Attention enabled` for gpt-oss-120b's load. `m` names the model's GGUF
in the store. gpt-oss-120b MXFP4 first, each run timed:

```sh
m=/srv/models/models--ggml-org--gpt-oss-120b-GGUF/snapshots/7200b74bea78b0a2964ef9f3897eefa401e890ff/gpt-oss-120b-MXFP4.gguf
echo "== native"; time /opt/llama.cpp/current/llama-bench -m "$m" -p 512 -n 256 -r 5 -ngl 99 -fa 1 -o md 2>/dev/null | tee ~/bench/native-gptoss.md
time docker run --rm --gpus all --user "$(id -u):$(id -g)" --volume /srv/models:/srv/models ghcr.io/ggml-org/llama.cpp:full-cuda13-b11669 --bench -m "$m" -p 512 -n 256 -r 5 -ngl 99 -fa 1 -o md 2>/dev/null | tee ~/bench/container-gptoss.md
```

Then gemma-4-26B-A4B QAT Q4_0, untimed:

```sh
m=/srv/models/models--google--gemma-4-26B-A4B-it-qat-q4_0-gguf/snapshots/$(ls /srv/models/models--google--gemma-4-26B-A4B-it-qat-q4_0-gguf/snapshots)/gemma-4-26B_q4_0-it.gguf
/opt/llama.cpp/current/llama-bench -m "$m" -p 512 -n 256 -r 5 -ngl 99 -fa 1 -o md 2>/dev/null | tee ~/bench/native-gemma26b.md
docker run --rm --gpus all --user "$(id -u):$(id -g)" --volume /srv/models:/srv/models ghcr.io/ggml-org/llama.cpp:full-cuda13-b11669 --bench -m "$m" -p 512 -n 256 -r 5 -ngl 99 -fa 1 -o md 2>/dev/null | tee ~/bench/container-gemma26b.md
```

The snapshot resolves to `d1c082be9cf3c8a514acf63b8761f4b41935842e`.

### End state

On gb10-1, after llama-bench:

```sh
systemctl is-active llama-router; systemctl is-enabled llama-router; docker ps -a --format "{{.Names}} {{.Status}} {{.Image}}"
```

## Results

Run on 2026-10-27 on gb10-1, all times -04:00, from the files each step wrote: the container's
cells from 09:19:59 to 09:22:45, native's from 09:23:57 to 09:26:47, and llama-bench from 09:27
to 09:29 (its files written at 09:27:49, 09:28:24, 09:29:01, and 09:29:20, in the order above).
No run took over 10 minutes: A ran 41 to 42 s, B 101 s, and gpt-oss-120b's llama-bench runs
37.8 s natively and 35.9 s in the container, real.

### Install, update, and rollback

Native's walk, from v0.6.0 (b11429) to v0.7.0 (b11669), back, and forward again:

| Step | Time | Printed | Checks |
|---|---|---|---|
| Root steps | — | `sudo -n systemctl stop llama-router` printed nothing | — |
| `install v0.6.0` | 28.8 s real | both sha256 digests matched (`9c76d072…`, `ad62e46c…`); `llama-router serves b11429 on port 8080 of the tailnet address` | `--version` `0.6.0-dev (build 11429, commit d81235049)`; `ldd` lists `libcudart.so.13`, `libcublas.so.13`, and `libcublasLt.so.13` from `/opt/llama.cpp/current`; `/health` ok on gb10-1 and from the laptop |
| `update` | 26.9 s real | `llama-router moved from b11429 to b11669`; `removed /opt/llama.cpp/b11429` | `/opt/llama.cpp` lists `b11669`, `current`, and `preset`; `/health` from the laptop, see below |
| `update v0.6.0`, the rollback | `/health` at 09:17:30.98 | `llama-router moved from b11669 to b11429`; `removed /opt/llama.cpp/b11669` | `/health` ok from the laptop |
| `update`, forward again | `/health` at 09:18:00.48 | `llama-router moved from b11429 to b11669` | `/health` ok from the laptop |
| `install`, a second time | — | `llama-router already serves b11669; nothing changed` | — |
| `host/engines llama install`, `host/engines vllm install` | — | each refused: `llama-router is active, and one engine serves per host at a time; sudo -n systemctl stop llama-router && sudo -n systemctl disable llama-router stops it` | — |

- Install and update each took 27 to 29 s, most of it the download of the build's two tarballs,
  about 700 MB. Update keeps the old build until the new one answers `/health`, and only then
  removes it, so a rollback downloads the older build again.
- The first laptop `/health` after the update, `curl -s http://gb10-1:8080/health` run right after
  it, exited 7 (connection refused), at about 09:16:36 to 09:16:37, while the unit's journal
  shows the server listening at 09:16:36.08. The next check, seconds later, answered ok, and so
  did every later one. Recorded as observed; not explained.
- Switching to the container, `host/engines llama install` printed `llama is installed with
  ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669 but stopped; docker start llama starts it`, and
  `docker start llama` started it. The container's own install, update, and rollback are task 1's
  ([Walkthrough](llama-gb10-container.md#walkthrough)).

### Anchors

Each method's A and B, beside bench-gb10-container's warm container anchors of 2026-10-26
([Anchors](bench-gb10-container.md#anchors)), which this session's container rows rerun.

| Cell | Run | Completed | Errored | Duration s | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | ITL p95 ms | Latency median s | Latency p95 s | Server prompt | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | container, 2026-10-26 | 8 | 0 | 40.98 | 50.0 | 422 | 436 | 18.35 | — | 5.09 | 5.18 | 1528.0 tok/s | 53.8 |
| A | container | 8 | 0 | 41.56 | 49.3 | 417 | 473 | 18.69 | 18.73 | 5.18 | 5.24 | 4,138 tokens, 1529.9 tok/s | 53.0 |
| A | native | 8 | 0 | 42.44 | 48.3 | 423 | 435 | 19.06 | 19.37 | 5.30 | 5.35 | 4,138 tokens, 1543.7 tok/s | 51.8 |
| B | container, 2026-10-26 | 32 | 0 | 101.27 | 80.9 | 1254 | 1262 | 45.47 | — | 12.75 | 13.31 | 1799.7 tok/s | 21.8 |
| B | container | 32 | 0 | 101.44 | 80.8 | 1259 | 1347 | 45.36 | 46.38 | 12.81 | 13.18 | 12,448 tokens, 1746.9 tok/s | 21.8 |
| B | native | 32 | 0 | 101.64 | 80.6 | 1262 | 1272 | 45.28 | 47.32 | 12.81 | 13.34 | 12,448 tokens, 1783.4 tok/s | 21.7 |

Every request carried 579 prompt tokens and generated 256, on both methods; the server computed
4,138 of A's 4,632 prompt tokens and 12,448 of B's 18,528, reusing the cached template prefix, on
both.

- **No anchor moved.** The container's A and B match 2026-10-26's within run noise: output tok/s
  49.3 against 50.0 and 80.8 against 80.9, ITL 18.69 against 18.35 and 45.36 against 45.47 ms.
- **B is level.** Native's B matches the container's: 80.6 against 80.8 tok/s, ITL 45.28 against
  45.36 ms, the same request latency, and 21.7 against 21.8 tok/s on the server.
- **A ran 1 tok/s lower natively.** 48.3 against 49.3 output tok/s (2%), ITL 19.06 against 18.69
  ms (+0.37), and 51.8 against 53.0 tok/s on the server. llama-bench doesn't reproduce it: its tg256
  is level, natively 0.11 tok/s ahead ([Raw speed](#raw-speed)). Each A is one run of 8 requests,
  and the container's A moved 0.7 tok/s between 2026-10-26 and this session, so this session
  can't separate the gap from run noise.

### Raw speed

llama-bench, pp512 and tg256, 5 repetitions, `-ngl 99 -fa 1`, on CUDA; tokens per second, the mean
± the standard deviation. Every run printed `build: 620d2225c (11669)`.

| Model | Size | Params | Test | Native t/s | Container t/s | Native against container |
|---|---|---|---|---|---|---|
| gpt-oss 120B MXFP4 MoE | 59.02 GiB | 116.83 B | pp512 | 2021.93 ± 27.11 | 2006.80 ± 30.08 | +0.75% |
| gpt-oss 120B MXFP4 MoE | 59.02 GiB | 116.83 B | tg256 | 58.13 ± 0.04 | 58.02 ± 0.04 | +0.19% |
| gemma4 26B.A4B Q4_0 | 13.43 GiB | 25.23 B | pp512 | 3319.00 ± 73.46 | 3303.30 ± 86.34 | +0.48% |
| gemma4 26B.A4B Q4_0 | 13.43 GiB | 25.23 B | tg256 | 79.66 ± 0.13 | 79.42 ± 0.08 | +0.30% |

Every native row is within its standard deviation of the container's: prompt processing within
0.8%, generation within 0.3%.

### Cold load and footprint

gpt-oss-120b, 4 slots, each load timed from a dropped page cache, from the load request to
`loaded`. The footprint is MemAvailable before less after, beside the buffers the engine logged, in
MiB, on the GPU (CUDA0) and the host (CUDA_Host).

| Method | Cache before → after drop GiB | MemAvailable before GiB | MemAvailable after GiB | Footprint GiB | Weights MiB (logged, GPU + host) | KV cache MiB (logged) | Compute MiB (logged, GPU + host) | Load s |
|---|---|---|---|---|---|---|---|---|
| Container | 21.25 → 0.40 | 117.48 | 55.72 | 61.76 | 59851.68 + 586.82 (output 3.07) | 1152.00 + 108.00 | 98.77 + 31.28 | 47.2 |
| Native | 54.25 → 0.37 | 117.48 | 55.75 | 61.73 | 59851.68 + 586.82 (output 3.07) | 1152.00 + 108.00 | 98.77 + 31.28 | 47.3 |

In kB, MemAvailable fell from 123,185,060 to 58,427,572 in the container and from 123,184,140 to
58,455,668 natively, 28 MiB apart. Both loads logged `n_ctx` 32768, `flash_attn` auto resolved to
`Flash Attention enabled`, and 4 slots of `n_ctx_slot` 8192. The native cache before the drop held
the model the container had just read. Both methods' logs carry llama-server's line `models will
be automatically loaded on-demand` although both run with `--no-models-autoload`; it was read in
native's journal, and the container runs the same flags. Recorded as the line appears; this task
didn't test the behavior.

### Network path and build, per method

| Method | `tailscale ping` | Build |
|---|---|---|
| Container | 09:19:49: direct on the LAN, 1 ms (`tailscale ping`; addresses left out) | `/props` build_info `b11669-620d2225c` |
| Native | 09:23:56: direct on the LAN, 1 ms (`tailscale ping`; addresses left out) | `/props` build_info `b11669-620d2225c` |

### gb10-1's end state

After llama-bench, the end-state read printed `inactive`, `disabled`, `llama` `Exited (0)`, and
`vllm` `Exited (0)`: the `llama` container on `server-cuda13-b11669`, with restart
`unless-stopped`, stopped by hand so it stays stopped at boot, and `vllm` on v0.32.0. Nothing
serves on gb10-1.

## Walkthrough

On 2026-10-27, after the results above, the architect walked native llama.cpp from the guides,
on gb10-1 from `~/repos/spike-model-engines` at a174558, and on the laptop. Times are -04:00 on
gb10-1 and UTC on the laptop. Each command is as the architect ran it.

### Uninstall, install, update, and rollback

| Step | Printed | Checks |
|---|---|---|
| `host/engines llama-native uninstall` | removed `/opt/llama.cpp/current`, the preset link, and `b11669`; `the architect's root steps stay: …` | — |
| `host/engines llama-native install v0.6.0` | both sha256 digests matched (`9c76d072…`, `ad62e46c…`); the `current` link created; `llama-router serves b11429 on port 8080 of the tailnet address` | setup's [3. Check it serves](../engines/llama.cpp/setup.md#3-check-it-serves): status `enabled`, `active (running)` since 09:56:31 EDT; `readlink` `b11429`; `--version` `0.6.0-dev (build 11429, commit d81235049)`; `ldd` lists `libcudart.so.13`, `libcublas.so.13`, and `libcublasLt.so.13` from `/opt/llama.cpp/current`; `/health` `{"status":"ok"}` |
| `host/engines llama-native update`, at about 10:00 | failed: `llama.cpp's release b11669 has no asset llama-b11669-bin-ubuntu-cuda-13.4-arm64.tar.gz` | `current` stayed `b11429` |
| `host/engines llama-native update v0.6.0` | `llama-router already serves b11429; nothing changed` | — |
| `host/engines llama-native update` | both b11669 sha256 digests matched; `llama-router moved from b11429 to b11669`; `removed /opt/llama.cpp/b11429` | `command ls /opt/llama.cpp` lists `b11669`, `current`, and `preset` |
| `host/engines llama-native update v0.6.0`, the rollback | `llama-router moved from b11669 to b11429`; `removed /opt/llama.cpp/b11669` | `readlink` `b11429` |
| `host/engines llama-native update`, forward again | `llama-router moved from b11429 to b11669`; `removed /opt/llama.cpp/b11429` | `command ls /opt/llama.cpp` lists `b11669`, `current`, and `preset` |

The failed update changed nothing, and the retry right after it succeeded. Six later reads of the
same API URL from gb10-1 each returned 80,497 bytes with the asset listed, and GitHub's rate limit
had 51 of 60 requests left, so the cause is unknown. The fetch now says, on that failure, what the
response held: GitHub's `message`, or else its size and the number of assets it listed, and that a
retry may succeed.

### llama-bench

Two attempts, at about 10:03 and 10:09, ran the method's gemma-4-26B-A4B lines
([llama-bench](#llama-bench)): `m=…/snapshots/$(ls …/snapshots)/gemma-4-26B_q4_0-it.gguf`, then
native's llama-bench with `2>/dev/null`. Each printed only the table's header. The architect's
interactive shell on gb10-1 aliases `ls` to eza, so `$(ls …)` returned eza's output, llama-bench
got a wrong path, and `2>/dev/null` discarded the error that said so. The 10:03 attempt
overwrote `~/bench/native-gemma26b.md`, the raw table of the native run above; its figures are
already in [Raw speed](#raw-speed).

The run that worked:

```sh
m=/srv/models/models--google--gemma-4-26B-A4B-it-qat-q4_0-gguf/snapshots/d1c082be9cf3c8a514acf63b8761f4b41935842e/gemma-4-26B_q4_0-it.gguf
ls -lL "$m"
/opt/llama.cpp/current/llama-bench -m "$m" -p 512 -n 256 -r 5 -ngl 99 -fa 1 -o md 2>~/bench/walk-native-gemma26b.err | tee ~/bench/walk-native-gemma26b.md
```

`ls -lL` failed under eza (`invalid value … for '--level <DEPTH>'`, eza reading `-L` as its
`--level`). llama-bench printed `build: 620d2225c (11669)` and:

| Test | Walkthrough t/s | Native, above, t/s |
|---|---|---|
| pp512 | 3343.04 ± 75.65 | 3319.00 ± 73.46 |
| tg256 | 80.18 ± 0.13 | 79.66 ± 0.13 |

The `.err` file shows the GB10 found (124544 MiB) and the backends loaded from
`/opt/llama.cpp/b11669`.

### Cold load

On gb10-1, native's cold-load lines from the method
([Per method: the cold load and its footprint](#per-method-the-cold-load-and-its-footprint)), with
`command grep` in place of `grep`, each entered at its own prompt:

- `Cached` fell from 73,991,828 to 392,036 kB, and MemAvailable from 123,304,996 to
  58,462,648 kB, a footprint of 61.8 GiB.
- It printed `loaded after 55.0 s`. That isn't comparable with the 47.3 s above: the timer runs
  from `start=` to the `echo`, and with each line entered at its own prompt it includes the time
  between prompts.
- The buffers are identical to the morning's: weights 59851.68 + 586.82 MiB, KV cache 1152 + 108
  MiB, compute 98.77 + 31.28 MiB. Flash Attention enabled, and 4 slots of 8192.

### From the laptop

At 14:18:07Z, `tailscale ping` went direct, 2 ms (addresses left out); `/props` build_info
`b11669-620d2225c`; the warm-up answered. Then one cell, `walk-a`, on `bench/anchor-a.yaml`:
`cell=walk-a` and the method's three lines ([Per cell](#per-cell)) with `llama-native-$cell`.

| Cell | Completed | Output tok/s | TTFT median / p95 ms | ITL median / p95 ms |
|---|---|---|---|---|
| `walk-a` | 8 of 8 | 48.5 | 421 / 440 | 19.00 / 19.27 |
| Native A, above | 8 of 8 | 48.3 | 423 / 435 | 19.06 / 19.37 |

guidellm exited 0.

### Stop and end state

```sh
sudo -n systemctl stop llama-router && sudo -n systemctl disable llama-router
```

removed the unit's `wants` symlink, and `systemctl is-active` and `is-enabled` printed `inactive`
and `disabled`. The end state is otherwise unchanged: the `llama` and `vllm` containers exited.

## Findings

Dated 2026-10-27, on gb10-1, llama.cpp v0.7.0 (b11669) in ggml's container and natively, on the
host stack above, from 09:19 to 09:29 (-04:00).

- **The engine runs at the same speed in both methods.** llama-bench puts native within each
  row's standard deviation of the container: tg256 within 0.3% and pp512 within 0.8%, on
  gpt-oss-120b MXFP4 and gemma-4-26B-A4B QAT Q4_0, native slightly ahead on every row. The
  container costs nothing measurable at the engine.
- **Served speed is level at 4 streams; at 1 stream, a 2% gap within run noise.** B is the same on
  both methods (80.6 against 80.8 tok/s, ITL 45.28 against 45.36 ms). Native's A ran 48.3 against
  49.3 tok/s, ITL +0.37 ms, which llama-bench doesn't reproduce; one run of 8 requests can't
  separate it from noise.
- **Startup and memory are the same.** gpt-oss-120b cold-loaded in 47.2 s in the container and
  47.3 s natively, with identical logged buffers on CUDA0 and the host and footprints 28 MiB apart
  (61.8 GiB each). Both reach the GPU as CUDA0 through the CUDA 13.4 runtime on the host's
  580.178.04 driver: the container through `--gpus all`, native through the runtime unpacked
  beside its binaries.
- **Native install, update, and rollback are each one command.** Install and update took 28.8
  and 26.9 s, most of it the download of about 700 MB. Update keeps the old build until the new
  one answers `/health`, then removes it; a rollback is an update to the older version and
  downloads it again. A second install changed nothing, and while native serves, both
  containers' installs refuse. Native adds the architect's three one-time root steps
  ([Setup](../engines/llama.cpp/setup.md#1-the-architects-root-steps)).
- **One `/health` refused right after an update.** The first laptop check after `update` exited 7
  while the journal showed the server listening; every later check answered. Observed once, not
  explained.
- **One native update failed without a cause found, and changed nothing.** In the walkthrough,
  the first `update` to b11669 said the release had no asset for the prebuilt, though six later
  reads of the same API URL listed it and the rate limit had room; it left `current` on b11429,
  and the retry right after it succeeded. The fetch now reports what GitHub's response held, so a
  repeat can be read.
- **A shell alias can feed llama-bench a wrong path.** On gb10-1 the architect's `ls` is eza, so
  `$(ls …/snapshots)` named no file, and with its stderr discarded llama-bench printed only its
  header. The setup guide now lists with `command ls` and writes llama-bench's log to a `.err` file
  beside its table, to read when the table has only its header.
- **The walkthrough reproduced native within run noise.** Its anchor A ran 48.5 tok/s, ITL 19.00
  ms, against native's 48.3 and 19.06, and llama-bench's gemma-4-26B-A4B 3343.04 and 80.18 t/s
  against 3319.00 and 79.66: pp512 within its standard deviation, tg256 0.52 t/s (0.7%) ahead.
  The cold load logged identical buffers.
- **gb10-1's end state.** Native llama.cpp, the llama container, and vLLM are all stopped, and
  none starts at boot.
