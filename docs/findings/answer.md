# llama.cpp's concurrency sweep on the Framework, in ggml's Vulkan image

Recorded on 2026-10-29, on the Framework, from the steps and cells the task's brief agreed
(context/goals, `answer`). llama.cpp v0.8.0 (b11960) serves gpt-oss-120b MXFP4 in ggml's Vulkan
image, the backend the Framework's answer names ([vllm-strix](vllm-strix.md)), and this finding
measures how its served output scales with concurrent streams: anchor A on the 4-slot section
first, then gb10-1's concurrency sweep exactly
([bench-gb10-container](bench-gb10-container.md#concurrency-sweep)) on the 16-slot section, 512
in, 256 out, at 1, 4, 16, and 32 streams, 60 s a level. Its result is an initial setting for how
many streams to serve the model at, a starting point tuned as the stack is used. The curve sits
beside gb10-1's (b11669) as evidence, and no figure is compared across the two sessions
([Comparisons](../../context/README.md#rules)).

**Every cell ran over Tailscale's DERP relay (iad), at about 51 to 66 ms**, not directly: the
laptop was on another network, behind a NAT that kept Tailscale from a direct connection, and the
architect chose to run over the relay ([Network path and model state](#network-path-and-model-state)).
Every earlier cell on the Framework ran directly over the LAN, at about 1 ms. TTFT and latency
include the path's round trip; ITL and the server's figures don't.

The session ran each step on framework over Tailscale SSH, and each GuideLLM cell from the laptop,
in the architect's view, printing each block before it ran. The laptop's clone was at f0ffb9c on
`answer`. Framework's clone was at bde06a4 on `main` for steps 1 to 3, since `answer` wasn't
pushed yet, and `host/` is the same on both; once the architect had it pushed, the clone moved to
`answer` at f0ffb9c at the start of step 4 ([The 16-slot section: the load](#4-the-16-slot-section-the-load)).

## Host stack

The architect brought the Framework current with `omarchy update` on 2026-10-29. It updated only
mise tools and installed no kernel, so no reboot is pending. The stack was then read with
[step 1](#1-the-host-stack).

| Item | framework |
|---|---|
| Recorded at | 2026-10-29T14:46:40Z |
| OS | Omarchy 4.0.6-1 (Arch Linux) |
| Kernel, running | 7.2.8-9-omarchy (`uname -r`) |
| Kernel, installed | `linux-omarchy` 7.2.8-9; Arch's `linux` 7.2.11.arch1-1, which the host doesn't boot |
| Reboot pending | no: the installed `linux-omarchy` is the running kernel |
| Mesa, `vulkan-radeon` | 1:26.2.5-1, 1:26.2.5-1 |
| linux-firmware | 20260916-1 |
| Docker | 1:29.9.2-1 (package), 29.9.2 (server) |
| GTT ceiling | 112 GiB: ttm `pages_limit` 29360128, `mem_info_gtt_total` 120259084288 |
| RAM | 131149568 kB (`MemTotal`), 125.1 GiB; `MemAvailable` 122459820 kB |
| Other engines | `vllm` (`vllm/vllm-openai-rocm:v0.32.0`) and `llama` (`server-vulkan-b11960`) both `Exited (0) 19 hours ago`; `llama-router` disabled and inactive |
| Laptop's path | **Tailscale's DERP relay (iad), 51 to 66 ms**, "direct connection not established"; the laptop on 10.150.43.182/19, framework on 192.168.1.0/24 |

## Engine versions

| Engine | Release | Build | Image | Devices |
|---|---|---|---|---|
| llama.cpp, Vulkan container | v0.8.0 | b11960; `/props` build_info `b11960-8642541b2` | `ghcr.io/ggml-org/llama.cpp:server-vulkan-b11960` (`host/llama.env`, flavor `vulkan`) | `/dev/dri` |

The router serves the preset (`host/llama-preset/models.ini`) from the store, `/srv/models`, on
port 8080 of the tailnet address. Two of its sections are measured, both the same gpt-oss-120b
MXFP4 file, each with 8192 tokens a slot: `ggml-org/gpt-oss-120b-GGUF:MXFP4`, 4 slots (`c =
32768`), for anchor A, and `gpt-oss-120b-MXFP4-16-slots`, 16 slots (`c = 131072`), for the sweep.
The file is in the store, so no load downloads (the preset sets `offline = true`).

The load tool is GuideLLM 0.8.1 on the laptop, in the spike's bench environment
(`mise.bench.toml`: Python 3.14.10, with the `vision` and `audio` extras).

## Method

The session runs the steps in this order, each printed before it runs:

1. The host stack, on framework.
2. The `llama` container at flavor `vulkan`, on framework.
3. The 4-slot section loaded on framework, its build and warm-up on the laptop, then anchor A on
   the laptop.
4. The 16-slot section loaded on framework, in the 4-slot section's place, its build and warm-up
   on the laptop, then the sweep on the laptop.
5. The read-outs, on the laptop.
6. The end state, on framework.

Each block below is self-contained, so it runs as one `ssh framework` command or at one laptop
prompt. Blocks marked "on framework" run from `~/repos/spike-model-engines` and set it themselves;
blocks marked "on the laptop" run from the laptop's clone. Every cell's files go to the laptop's
`.state/answer/`, which `.state/` keeps untracked. The run cap is 10 minutes: each GuideLLM run
is under `timeout 10m`, which ends it with exit 124 at the cap. [Run times](#run-times) gives each
run's estimate.

No page cache is dropped: neither load is a cold-load measurement, and every cell runs from a model
that has served one warm-up request ([Model state](#model-state)).

### 1. The host stack

On framework, after the architect's `omarchy update`. The time, Omarchy's version, the running
kernel, then the installed kernels, Mesa and its Vulkan driver for Radeon, the GPU's firmware, and
Docker; Docker's server, the GTT ceiling as TTM's page count and as amdgpu reads it in bytes, the
host's RAM, and the other engines, which must both be stopped for the `llama` container to serve:

```sh
date -u +%FT%TZ; omarchy version; uname -r
pacman -Q linux-omarchy linux mesa vulkan-radeon linux-firmware docker
docker version --format "{{.Server.Version}}"
echo "pages_limit $(cat /sys/module/ttm/parameters/pages_limit) gtt_total $(cat /sys/class/drm/card*/device/mem_info_gtt_total)"
grep -E "^(MemTotal|MemAvailable)" /proc/meminfo
docker ps -a --filter name=vllm --filter name=llama --format "{{.Names}} {{.Image}} {{.Status}}"
systemctl is-enabled llama-router; systemctl is-active llama-router
```

The host boots `linux-omarchy`, so a pending reboot is its installed version differing from
`uname -r` ([llama.cpp's Setup](../engines/llama.cpp/setup.md#1-bring-the-host-current)); Arch's
`linux` is installed beside it and isn't the one that boots.

### 2. The container at flavor vulkan

On framework. The clone fetches and prints its branch and the commit it is at. `answer` wasn't
pushed yet, so the clone stayed on `main` at bde06a4, whose `host/` is the same as `answer`'s;
the switch to `answer` ran at the start of step 4's load, once the architect had it pushed. Then
`host/engines llama update` with the
flavor given as `LLAMA_FLAVOR=vulkan`, since the suite picks `rocm` on an AMD GPU when none is
given ([Update](../engines/llama.cpp/update.md#switching-the-flavor)). At b11960 already, the
update pulls nothing and, finding `llama` stopped, says so without starting it, so the block starts
it and waits for the router; the router runs with `--no-models-autoload`, so it holds no model.
Then its image and devices, which read `server-vulkan-b11960` and `/dev/dri`:

```sh
cd ~/repos/spike-model-engines && git fetch -q origin && git status -sb | head -1 && git log --oneline -1
LLAMA_FLAVOR=vulkan host/engines llama update 2>&1 | tail -3
docker start llama >/dev/null && until curl -fs "http://$(tailscale ip -4):8080/health" >/dev/null; do sleep 1; done
docker ps --filter name=llama --format "{{.Names}} {{.Image}} {{.Status}}"
docker inspect --format '{{.Config.Image}} {{range .HostConfig.Devices}}{{.PathOnHost}} {{end}}' llama
curl -s "http://$(tailscale ip -4):8080/models" | jq -c '[.data[] | {id, status: .status.value}]'
```

The build is read from `/props` once a model is loaded, in each section's warm-up (steps 3 and 4).

### 3. The 4-slot section: the load

On framework, with `model` set to the section and `prev` to the model loaded before it, empty on
the router just started. The block unloads `prev` and waits until it is unloaded, reads the memory
before, loads the model through the router's API and times it, from the request to the first
`/models` poll that shows it `loaded` (or failed), then reads the memory after and the buffers and
slots the engine logged since the load began. It is
[vllm-strix's](vllm-strix.md#llamacpp-per-model-the-cold-load-and-its-footprint) block without the
page-cache drop:

```sh
cd ~/repos/spike-model-engines
model=ggml-org/gpt-oss-120b-GGUF:MXFP4
prev=
[[ -z $prev ]] || curl -s -X POST "http://$(tailscale ip -4):8080/models/unload" -H "Content-Type: application/json" -d "{\"model\": \"$prev\"}"
[[ -z $prev ]] || until [[ $(curl -s "http://$(tailscale ip -4):8080/models" | jq -r --arg m "$prev" '.data[] | select(.id == $m) | .status.value') == unloaded ]]; do sleep 1; done
echo; grep ^MemAvailable /proc/meminfo; echo "gtt_used $(cat /sys/class/drm/card*/device/mem_info_gtt_used) vram_used $(cat /sys/class/drm/card*/device/mem_info_vram_used)"
since=$(date -u +%Y-%m-%dT%H:%M:%SZ); start=$(date +%s.%N)
curl -s -X POST "http://$(tailscale ip -4):8080/models/load" -H "Content-Type: application/json" -d "{\"model\": \"$model\"}"; echo
while :; do s=$(curl -s "http://$(tailscale ip -4):8080/models" | jq -r --arg m "$model" '.data[] | select(.id == $m) | if .status.failed then "failed" else .status.value end'); [[ $s == loaded || $s == failed ]] && break; sleep 0.5; done
echo "$s after $(awk -v a="$start" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1f", b - a }') s"
grep ^MemAvailable /proc/meminfo; echo "gtt_used $(cat /sys/class/drm/card*/device/mem_info_gtt_used) vram_used $(cat /sys/class/drm/card*/device/mem_info_vram_used)"
docker logs --since "$since" llama 2>&1 | grep -E "offloaded|buffer size|model size|flash_attn|Flash Attention|n_ctx |n_slots"
```

`offloaded 37/37 layers to GPU` shows every layer on the GPU, and `n_slots` the section's 4.

### 3. The 4-slot section: the build and the warm-up

On the laptop, as [llama-strix-rocm](llama-strix-rocm.md#per-model-the-build-and-the-warm-up)
ran it: the commit, the cells' directory, the time and the network path, the build the model runs,
which prints `b11960-8642541b2`, then one warm-up request, the API page's chat completion:

```sh
git log --oneline -1; mkdir -p .state/answer
model=ggml-org/gpt-oss-120b-GGUF:MXFP4
date -u +%FT%TZ; tailscale ping -c 3 framework
curl -sG "http://framework:8080/props" --data-urlencode "model=$model" --data-urlencode autoload=false | jq -r .build_info
curl -s "http://framework:8080/v1/chat/completions" -H "Content-Type: application/json" -d "{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one sentence.\"}]}" | jq '.choices[0].message.content'
```

### 3. Anchor A

On the laptop. vllm-strix's llama.cpp anchor block ([llama.cpp, per cell](vllm-strix.md#llamacpp-per-cell)),
A alone, under `timeout 10m`, with the files written to `.state/answer/`. The scenario,
`bench/anchor-a.yaml`, names its model and tokenizer: 1 stream, 8 requests, 512 in, 256 out. The
before-snapshot must be non-empty: the block fetches it up to five times, 2 s apart, and when it
is still empty prints so and runs nothing. Its `llamacpp:requests_processing` line prints, 0 when
nothing else is using the model:

```sh
export GUIDELLM__SPEC__BACKEND__TARGET="http://framework:8080"; model=ggml-org/gpt-oss-120b-GGUF:MXFP4; cell=anchor-a; p=.state/answer/$cell
for i in 1 2 3 4 5; do curl -sG "http://framework:8080/metrics" --data-urlencode "model=$model" --data-urlencode autoload=false > $p.before.metrics; test -s $p.before.metrics && break; sleep 2; done
if ! test -s $p.before.metrics; then echo "$cell: before-snapshot empty after 5 tries; not run"; else
grep "^llamacpp:requests_processing" $p.before.metrics
MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/$cell.yaml --output "kind=json,path=$p.json" > $p.log 2>&1; echo "$cell: guidellm exit $?"
curl -sG "http://framework:8080/metrics" --data-urlencode "model=$model" --data-urlencode autoload=false > $p.after.metrics; test -s $p.after.metrics || echo "$cell: after-snapshot empty"; fi
```

A run whose guidellm exits non-zero, or whose requests error, is read from its log and the
router's (`docker logs --tail 50 llama` on framework).

### 4. The 16-slot section: the load

On framework. First the clone's switch to `answer`, now pushed, which prints f0ffb9c (step 2 ran
on `main`). Then step 3's load block, with the 16-slot section in `model` and the 4-slot section
in `prev`, which it unloads first, so one copy of the model's weights is in memory:

```sh
cd ~/repos/spike-model-engines && git fetch -q origin && git switch -q answer && git pull -q --ff-only && git log --oneline -1
cd ~/repos/spike-model-engines
model=gpt-oss-120b-MXFP4-16-slots
prev=ggml-org/gpt-oss-120b-GGUF:MXFP4
[[ -z $prev ]] || curl -s -X POST "http://$(tailscale ip -4):8080/models/unload" -H "Content-Type: application/json" -d "{\"model\": \"$prev\"}"
[[ -z $prev ]] || until [[ $(curl -s "http://$(tailscale ip -4):8080/models" | jq -r --arg m "$prev" '.data[] | select(.id == $m) | .status.value') == unloaded ]]; do sleep 1; done
echo; grep ^MemAvailable /proc/meminfo; echo "gtt_used $(cat /sys/class/drm/card*/device/mem_info_gtt_used) vram_used $(cat /sys/class/drm/card*/device/mem_info_vram_used)"
since=$(date -u +%Y-%m-%dT%H:%M:%SZ); start=$(date +%s.%N)
curl -s -X POST "http://$(tailscale ip -4):8080/models/load" -H "Content-Type: application/json" -d "{\"model\": \"$model\"}"; echo
while :; do s=$(curl -s "http://$(tailscale ip -4):8080/models" | jq -r --arg m "$model" '.data[] | select(.id == $m) | if .status.failed then "failed" else .status.value end'); [[ $s == loaded || $s == failed ]] && break; sleep 0.5; done
echo "$s after $(awk -v a="$start" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1f", b - a }') s"
grep ^MemAvailable /proc/meminfo; echo "gtt_used $(cat /sys/class/drm/card*/device/mem_info_gtt_used) vram_used $(cat /sys/class/drm/card*/device/mem_info_vram_used)"
docker logs --since "$since" llama 2>&1 | grep -E "offloaded|buffer size|model size|flash_attn|Flash Attention|n_ctx |n_slots"
```

`n_slots` reads 16.

### 4. The 16-slot section: the build and the warm-up

On the laptop. Step 3's block with the 16-slot section's `model`:

```sh
git log --oneline -1; mkdir -p .state/answer
model=gpt-oss-120b-MXFP4-16-slots
date -u +%FT%TZ; tailscale ping -c 3 framework
curl -sG "http://framework:8080/props" --data-urlencode "model=$model" --data-urlencode autoload=false | jq -r .build_info
curl -s "http://framework:8080/v1/chat/completions" -H "Content-Type: application/json" -d "{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one sentence.\"}]}" | jq '.choices[0].message.content'
```

### 4. The sweep

On the laptop. gb10-1's sweep exactly, as bench-gb10-container ran it
([Per cell](bench-gb10-container.md#per-cell), cell `llama-gptoss-sweep`): `bench/sweep.yaml`,
unchanged, at 1, 4, 16, and 32 streams, 60 s a level, four benchmarks in one run and one JSON,
with the model and its tokenizer given on the command line and the JSON's path in `--output`,
under `timeout 10m`. The before-snapshot is fetched as anchor A's.

The counters a snapshot holds are totals, but `llamacpp:requests_processing` and
`llamacpp:requests_deferred` are gauges, read at the instant of the snapshot, and both read 0
before and after the sweep. So, for what llama.cpp does past its 16 slots, a sampler in the
background reads both gauges every 5 s while GuideLLM runs, each line the epoch second and the two
gauges, to `$p.gauges`; the block stops it when GuideLLM exits. A request llama.cpp defers is one
it accepted with every slot busy and queued until a slot frees:

```sh
export GUIDELLM__SPEC__BACKEND__TARGET="http://framework:8080"; model=gpt-oss-120b-MXFP4-16-slots; tok=openai/gpt-oss-120b; cell=sweep; p=.state/answer/$cell
for i in 1 2 3 4 5; do curl -sG "http://framework:8080/metrics" --data-urlencode "model=$model" --data-urlencode autoload=false > $p.before.metrics; test -s $p.before.metrics && break; sleep 2; done
if ! test -s $p.before.metrics; then echo "$cell: before-snapshot empty after 5 tries; not run"; else
grep -E "^llamacpp:requests_(processing|deferred)" $p.before.metrics
( while :; do printf '%s ' "$(date +%s)"; curl -sG "http://framework:8080/metrics" --data-urlencode "model=$model" --data-urlencode autoload=false | awk '/^llamacpp:requests_(processing|deferred) / { printf "%s %s ", $1, $2 } END { print "" }'; sleep 5; done ) > $p.gauges & sampler=$!
MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/$cell.yaml --backend "kind=openai_http,model=$model" --tokenizer "kind=huggingface_auto,model=$tok" --output "kind=json,path=$p.json" > $p.log 2>&1; echo "$cell: guidellm exit $?"
kill $sampler
curl -sG "http://framework:8080/metrics" --data-urlencode "model=$model" --data-urlencode autoload=false > $p.after.metrics; test -s $p.after.metrics || echo "$cell: after-snapshot empty"; fi
```

A run whose guidellm exits non-zero is read from its log and the router's (`docker logs --tail 50
llama` on framework).

### 5. The read-outs

On the laptop, after the sweep. Each figure is GuideLLM's or the server's own, read from the files
the cells wrote.

**Anchor A.** llama-strix-rocm's client read-out ([Reading the figures](llama-strix-rocm.md#reading-the-figures)),
then the mean output tok/s at full precision over the successful requests, the figure vllm-strix's
44.97903 is ([Anchors](vllm-strix.md#anchors)), and over all requests, GuideLLM's `total`, which
also counts any request the client dropped ([vllm-strix's Walkthrough](vllm-strix.md#walkthrough)),
then the benchmark's duration and the server's figures, the counters differenced between the two
snapshots:

```sh
f=.state/answer/anchor-a.json; p=.state/answer/anchor-a
jq -c '.metadata as $v | .benchmarks[] | .metrics as $m | {streams: .config.strategy.streams, duration_s: (.duration|floor), requests: $m.request_totals, prompt_tokens: $m.prompt_token_count.successful.median, output_tokens: $m.output_token_count.successful.median, output_tok_s: ($m.output_tokens_per_second.successful.mean|.*10|round/10), ttft_ms: ($m.time_to_first_token_ms.successful | {median: (.median|round), p95: (.percentiles.p95|round)}), itl_ms: ($m.inter_token_latency_ms.successful | {median: (.median*100|round/100), p95: (.percentiles.p95*100|round/100)}), latency_s: ($m.request_latency.successful | {median: (.median*100|round/100), p95: (.percentiles.p95*100|round/100)}), audio_s_per_s: $m.audio.seconds.input_per_second.successful.mean}' "$f"
jq -c '.benchmarks[].metrics | {successful_mean: .output_tokens_per_second.successful.mean, total_mean: .output_tokens_per_second.total.mean, output_tokens: (.output_token_count | {successful: .successful.total_sum, errored: .errored.total_sum})}' "$f"
jq '.benchmarks[].duration' "$f"
awk '{ d[$1] += (NR == FNR ? -$2 : $2) } END { m = "llamacpp:"; printf "prompt %d tokens, %.1f tok/s; generated %d tokens, %.1f tok/s\n", d[m "prompt_tokens_total"], d[m "prompt_tokens_total"] / d[m "prompt_seconds_total"], d[m "tokens_predicted_total"], d[m "tokens_predicted_total"] / d[m "tokens_predicted_seconds_total"] }' $p.before.metrics $p.after.metrics
```

Anchor A against vllm-strix's is this run's successful mean less 44.97903, over 44.97903.

**The sweep, by level.** As bench-gb10-container read its own
([Reading the figures](bench-gb10-container.md#reading-the-figures)): first the cell's read-out,
one line per level, for ITL and latency over the successful requests; then the sweep's, for the
output rate over successful, incomplete, and all requests, and TTFT over all requests, GuideLLM's
`total`; then each level's duration:

```sh
f=.state/answer/sweep.json
jq -c '.metadata as $v | .benchmarks[] | .metrics as $m | {streams: .config.strategy.streams, duration_s: (.duration|floor), requests: $m.request_totals, prompt_tokens: $m.prompt_token_count.successful.median, output_tokens: $m.output_token_count.successful.median, output_tok_s: ($m.output_tokens_per_second.successful.mean|.*10|round/10), ttft_ms: ($m.time_to_first_token_ms.successful | {median: (.median|round), p95: (.percentiles.p95|round)}), itl_ms: ($m.inter_token_latency_ms.successful | {median: (.median*100|round/100), p95: (.percentiles.p95*100|round/100)}), latency_s: ($m.request_latency.successful | {median: (.median*100|round/100), p95: (.percentiles.p95*100|round/100)}), audio_s_per_s: $m.audio.seconds.input_per_second.successful.mean}' "$f"
jq -c '.benchmarks[] | {s: .config.strategy.streams, otps: (.metrics.output_tokens_per_second | {succ: .successful.mean, inc: .incomplete.mean, tot: .total.mean}), tps: (.metrics.tokens_per_second | {tot: .total.mean}), ttft_tot: (.metrics.time_to_first_token_ms.total | {median, p95: .percentiles.p95, max})}' "$f"
jq '.benchmarks[].duration' "$f"
```

**Per stream, and the initial setting.** From the same JSON, per level: the aggregate, GuideLLM's
total output tok/s; the per-stream rate two ways, the aggregate over the level's N streams, and
1000 over the successful requests' ITL median, one stream's decode rate while it is served; and the
aggregate's gain on the level before. Then the two readings and the initial setting, the smaller of
them ([Initial setting](#initial-setting)):

```sh
f=.state/answer/sweep.json
jq -r '[.benchmarks[] | .metrics as $m | {n: .config.strategy.streams, agg: $m.output_tokens_per_second.total.mean, itl: $m.inter_token_latency_ms.successful.median}] | sort_by(.n) as $l
| ($l | to_entries | map(.value + {per_agg: (.value.agg / .value.n), per_itl: (1000 / .value.itl), gain: (if .key == 0 then null else (.value.agg / $l[.key - 1].agg - 1) * 100 end)})) as $r
| ($r[] | "\(.n) streams: aggregate \(.agg*10|round/10) tok/s, per stream \(.per_agg*10|round/10) (aggregate / N) and \(.per_itl*10|round/10) (1000 / ITL median), gain on the level before \(if .gain == null then "-" else "\(.gain*10|round/10)%" end)"),
  ([$r[] | select(.per_agg >= 10 and .per_itl >= 10) | .n] | max) as $s
| ([range(0; $r|length) | select(. + 1 < ($r|length) and $r[. + 1].gain < 10) | $r[.].n] | first // ($r | last | .n)) as $k
| "10 tok/s reading: \($s // "no level") streams; knee: \($k) streams; initial setting: \(if $s == null then "no level decodes 10 tok/s a stream" else "\([$s, $k] | min) streams" end)"' "$f"
```

**Past the 16 slots.** The gauges the sampler read, per level, within each level's start and end
time from the JSON: the samples, and the most requests processing and deferred at once, and the
mean deferred. Then the server's figures over the whole sweep, the counters differenced between
the two snapshots, as bench-gb10-container gave them:

```sh
f=.state/answer/sweep.json; p=.state/answer/sweep
jq -r '.benchmarks[] | "\(.config.strategy.streams) \(.start_time) \(.end_time)"' "$f" | while read -r n a b; do awk -v n="$n" -v a="$a" -v b="$b" '$1 >= a && $1 <= b { k++; if ($3 > pr) pr = $3; if ($5 > de) de = $5; sd += $5 } END { printf "%s streams: %d samples, requests_processing at most %d, requests_deferred at most %d, mean %.1f\n", n, k, pr, de, (k ? sd / k : 0) }' $p.gauges; done
awk '{ d[$1] += (NR == FNR ? -$2 : $2) } END { m = "llamacpp:"; printf "prompt %d tokens, %.1f tok/s; generated %d tokens, %.1f tok/s\n", d[m "prompt_tokens_total"], d[m "prompt_tokens_total"] / d[m "prompt_seconds_total"], d[m "tokens_predicted_total"], d[m "tokens_predicted_total"] / d[m "tokens_predicted_seconds_total"] }' $p.before.metrics $p.after.metrics
```

The server's generated rate is per slot, since its seconds are summed per slot
([API](../engines/llama.cpp/api.md)).

### 6. The end state

On framework, after the read-outs. The 16-slot section is unloaded, so the router holds no model,
and `llama` keeps running at flavor `vulkan`, b11960, for the next slice's set A. Then the
container, the router's models, the router unit, and port 8080, held by the container:

```sh
cd ~/repos/spike-model-engines
curl -s -X POST "http://$(tailscale ip -4):8080/models/unload" -H "Content-Type: application/json" -d '{"model": "gpt-oss-120b-MXFP4-16-slots"}'; echo
until [[ $(curl -s "http://$(tailscale ip -4):8080/models" | jq -r '.data[] | select(.id == "gpt-oss-120b-MXFP4-16-slots") | .status.value') == unloaded ]]; do sleep 1; done
docker ps -a --filter name=vllm --filter name=llama --format "{{.Names}} {{.Image}} {{.Status}}"
curl -s "http://$(tailscale ip -4):8080/models" | jq -c '[.data[] | {id, status: .status.value}]'
systemctl is-enabled llama-router; systemctl is-active llama-router
ss -ltn 'sport = :8080'
```

### Model state

Each section is loaded once, with the other unloaded, and warmed with one request before its cell;
the page cache is left as the host has it. Anchor A so runs from a model that has served one
request, as vllm-strix's did, and the sweep from a model that has served one request, as
bench-gb10-container's did.

### Run times

Each run held to 10 minutes. The estimates, from vllm-strix's llama.cpp Vulkan b11960 anchor A and
bench-gb10-container's sweep:

| Run | Estimate | Actual |
|---|---|---|
| Each load | under 20 s (vllm-strix's Vulkan loads, 0.6 to 18.2 s, from a dropped cache) | 9.3 s (4 slots), 9.8 s (16 slots) |
| Anchor A | under 1 min (8 requests of about 5.7 s) | 46.18 s benchmarked; 14:56:53 to 14:57:55Z |
| The sweep | 4.5 min (four 60 s levels and setup) | four 60.0 s levels; 14:58:58 to 15:03:30Z, 4 min 32 s |

## Results

Run on framework and the laptop on 2026-10-29, times UTC, from the files each step wrote, **over
Tailscale's DERP relay (iad)**. The client figures are GuideLLM's, read with
[the read-outs](#5-the-read-outs); the server figures are its `awk`.

### Network path and model state

| Section | Load | Warm-up at | `tailscale ping` | `/props` build_info | Warm-up reply | `requests_processing` before |
|---|---|---|---|---|---|---|
| `ggml-org/gpt-oss-120b-GGUF:MXFP4`, 4 slots | loaded after 9.3 s; MemAvailable 59338352 kB, GTT in use 65111457792 after | 14:47:17Z | via DERP(iad), 52 to 57 ms, "direct connection not established" | `b11960-8642541b2` | answered | 0 |
| `gpt-oss-120b-MXFP4-16-slots`, 16 slots | loaded after 9.8 s; MemAvailable 55668900 kB, GTT in use 69084729344 after | 14:58:46Z | via DERP(iad), 51 to 66 ms | `b11960-8642541b2` | answered | 0, and `requests_deferred` 0 |

**The relay.** At step 3's warm-up the laptop was on 10.150.43.182/19, a network other than
framework's 192.168.1.0/24, and `tailscale netcheck` read `MappingVariesByDestIP: true`, a NAT
that maps each destination to its own port, which can keep Tailscale from a direct connection. Ten
more pings stayed on DERP(iad) at 54 to 64 ms, one at 302 ms. The session stopped and put it to
the architect, who chose to run over the relay: "it will be interesting to see how / if the
latency impacts the results". Anchor A's pings, before it ran, read 60 to 61 ms via DERP. Every
earlier cell on the Framework ran directly over the LAN, at about 1 ms
([vllm-strix](vllm-strix.md), [llama-strix-rocm](llama-strix-rocm.md)). The relay adds its round
trip to each request's TTFT and latency; ITL and the server's figures don't depend on the path.

The session read the path with these two blocks, on the laptop, before putting it to the
architect:

```sh
tailscale ping -c 10 framework; tailscale status | grep -i framework; tailscale netcheck 2>&1 | head -12
```

```sh
ip -4 addr show | grep -E 'inet ' | grep -v 127.0.0.1; ssh framework 'ip -4 addr show | grep "inet " | grep -v 127.0.0.1'
```

**The loads.** Neither is a cold load: the 4-slot load read the file from the page cache, and the
16-slot load the same file after it. Each footprint, MemAvailable before less after and GTT in use
after less before, matches the buffers the engine logged, in MiB:

| Section | MemAvailable before, kB | MemAvailable drop, MiB | GTT in use, after less before, MiB | VRAM in use, after less before, MiB | Logged buffers, MiB | Slots |
|---|---|---|---|---|---|---|
| 4 slots, `c = 32768` | 122432308 | 61615.2 | 61833.3 | 2.2 | 61797.23: model 59851.64 (Vulkan0), Vulkan_Host 586.82, KV 1152.00 + 108.00, compute 98.77 | `n_slots` 4, `n_ctx_slot` 8192, `kv_unified` false |
| 16 slots, `c = 131072` | 122834572 | 65591.5 | 65622.5 | 5.1 | 65589.50: model 59851.64 (Vulkan0), Vulkan_Host 586.82, KV 4608.00 + 432.00, output 12.27, compute 98.77 | `n_slots` 16, `n_ctx_slot` 8192, `kv_unified` false |

Both logged `offloaded 37/37 layers to GPU`. GTT in use before each load was 274538496 bytes, and
VRAM in use 446160896.

### Anchor A

gpt-oss-120b on the 4-slot section, 1 stream, 8 requests, 512 in, 256 out, from 14:56:53 to
14:57:55Z, over the relay; guidellm exited 0.

| Completed | Errored | Duration s | Output tok/s (successful mean) | Output tok/s (total mean) | TTFT median ms | TTFT p95 ms | ITL median ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|
| 8 | 0 | 46.18 | 44.344396 | 44.344396 | 716 | 734 | 19.54 | 5.69 | 5.73 |

Server: computed 4,138 prompt tokens at 930.5 tok/s and generated 2,048 at 50.7 tok/s.

Beside vllm-strix's 44.97903 tok/s at b11960 on the same host: −1.41%. vllm-strix read up to 0.7%
on this host, and 1.0 to 1.4% on gb10-1, as run noise, and its own reruns of A and B at b11960
against b11669 moved −0.33% and −1.13% ([Anchors](vllm-strix.md#anchors)). The move is beyond what
this host recorded, so it is a finding, and its cause reads as the path, not the engine:

- The output rate is the run's output tokens over its duration, and the run took 46.18 s against
  vllm-strix's 45.53 s, 0.65 s more for the same 2,048 tokens.
- The requests themselves took 45.60 s in all against 45.50 s, 0.10 s more. TTFT median was 716
  against 637 ms, 79 ms higher, about one relay round trip; ITL median was 19.54 against 19.78
  ms, so decode held.
- The other 0.55 s, about 70 ms a request, fell between one request's end and the next one's
  start, which also crosses the path: 0.58 s in all here, against 0.03 s in vllm-strix's run.
- The server's figures, which don't depend on the path, held: the same 4,138 prompt tokens
  computed, and generation at 50.7 against 50.1 tok/s
  ([vllm-strix's Results](vllm-strix.md#results)).

The durations and the requests' summed latency are read from the two JSONs, vllm-strix's from its
Vulkan cells' files:

```sh
for f in .state/vllm-strix/vulkan/anchor-a.json .state/answer/anchor-a.json; do echo "$f"; jq -c '.benchmarks[0] | {d: .duration, lat: .metrics.request_latency.successful | {total_sum, mean}, o: .metrics.output_tokens_per_second.successful.mean}' "$f"; done
```

That reading rests on one run over the relay; no run directly over the LAN was taken in this
session to set beside it.

### Concurrency sweep

gpt-oss-120b MXFP4 on 16 slots, 512 in, 256 out, 60 s a level, from 14:58:58 to 15:03:30Z, over
the relay; guidellm exited 0. Requests in flight when a level's 60 s end are cancelled and counted
incomplete. Output tok/s and TTFT are GuideLLM's `total`, over every request, completed or not; ITL
and latency are the successful requests' ([bench-gb10-container](bench-gb10-container.md#concurrency-sweep)).

| Streams | Completed | Incomplete | Errored | Output tok/s (total) | Per stream, aggregate / N | Per stream, 1000 / ITL median | Gain on the level before | TTFT median ms (total) | TTFT p95 ms (total) | ITL median ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 10 | 1 | 0 | 43.6 | 43.6 | 51.0 | — | 726 | 761 | 19.61 | 5.73 | 5.80 |
| 4 | 16 | 4 | 0 | 69.5 | 17.4 | 22.0 | +59.4% | 2288 | 2894 | 45.55 | 14.15 | 14.46 |
| 16 | 16 | 16 | 0 | 81.6 | 5.1 | 7.1 | +17.4% | 8540 | 10210 | 140.28 | 45.91 | 47.82 |
| 32 | 16 | 32 | 0 | 80.1 | 2.5 | 6.8 | −1.8% | 9442 | 54683 | 147.71 | 46.96 | 49.43 |

At 16 and 32 streams a request takes about 46 to 47 s, so each 60 s level completes only its
first wave, 16 requests. GuideLLM's successful-only output rate is then those requests' tokens
over the level's 60 s, 16 × 256 / 60 = 68.3 tok/s at 4, 16, and 32 streams alike, and leaves out
every token the incomplete requests produced; the total figures are the ones to read, as
bench-gb10-container read its sweep.

The 1-stream level reads with anchor A, the same section's model in the same session: 43.6 against
44.3 tok/s, TTFT median 726 against 716 ms, ITL median 19.61 against 19.54 ms.

The relay's round trip is in every request's TTFT and latency, and in the gap before each next
request. At 1 stream it moved anchor A's rate by 1.41%, above; from 4 streams it is small beside
TTFT medians of 2.3 to 9.4 s.

Server figures over the whole sweep: computed 49,987 prompt tokens at 919.0 tok/s and generated
16,717 at 9.4 tok/s a slot.

### End state

After the read-outs, [step 6](#6-the-end-state) unloaded the 16-slot section. `llama` runs at
`server-vulkan-b11960`, up and healthy, and `vllm` stays exited; every model in the preset reads
unloaded; `llama-router` is disabled and inactive; and port 8080 listens on the tailnet address,
held by the container.

### Set A, served

As run on 2026-10-29, on framework from about 15:12Z, with
[step 12, Serve set A](../engines/llama.cpp/setup.md#12-serve-set-a), then the removals with
[Uninstall's Framework blocks](../engines/llama.cpp/uninstall.md#the-framework), each block
exactly as the guides give it:

| Block | Printed |
|---|---|
| The clone, the update, the reload | the clone on `answer...origin/answer` at 810ac56; `llama already runs ghcr.io/ggml-org/llama.cpp:server-vulkan-b11960; nothing changed`; the image `server-vulkan-b11960` on `/dev/dri`; after the reload `/models` lists `gpt-oss-120b-MXFP4-set-a`, `unloaded`, beside the other eight sections |
| The loads | before: `MemAvailable` 122814868 kB, `gtt_used` 274538496; `gpt-oss-120b-MXFP4-set-a` loaded after 9.3 s, `google/gemma-4-26B-A4B-it-qat-q4_0-gguf:Q4_0` after 6.3 s, `ggml-org/gemma-4-E4B-it-GGUF:Q8_0` after 3.1 s, `mrutkows/granite-embedding-english-r2-GGUF:BF16` after 0.5 s; after: `MemAvailable` 25803672 kB, `gtt_used` 98896084992 |
| The models and the containers | set A's four `loaded`, every other section `unloaded`; `vllm` (`vllm/vllm-openai-rocm:v0.32.0`) `Exited (0) 19 hours ago`, `llama` `Up 26 minutes (healthy)` |
| `/health`, from the laptop | `{"status":"ok"}` from `http://framework:8080/health` |
| The native Vulkan b11669 prebuilt | `rm` and `rmdir` succeeded; `command ls -d` printed `cannot access` for both `/home/jaime/llama.cpp` and `/home/jaime/prestage/llama-b11669-bin-ubuntu-vulkan-x64.tar.gz` and exited 2, the expected read-back that both are gone |
| The vLLM audio probe's image | `Untagged: spike-model-engines/vllm-openai-rocm-audio:v0.32.0`, then `Deleted: sha256:4d63a2268f06…`; the images left, `server-vulkan-b11960` (c9aba1a67338, 1.21GB) and `vllm/vllm-openai-rocm:v0.32.0` (14f6a575e1fb, 46.7GB) |

No load was cold: all four read their files from the page cache. Set A's four took 94737.5 MiB
of `MemAvailable` (122814868 less 25803672 kB) and 94052.8 MiB of GTT (98896084992 less
274538496 bytes), leaving 24.6 GiB available on the host and 92.1 GiB of the 112 GiB GTT ceiling
in use. The Framework ends serving set A from `llama` at b11960 in ggml's Vulkan image, `vllm`
installed and stopped.

## Past 16 slots

The sampler's gauges by level, read every 5 s while GuideLLM ran:

| Streams | Samples | `requests_processing`, most at once | `requests_deferred`, most at once | `requests_deferred`, mean |
|---|---|---|---|---|
| 1 | 11 | 1 | 0 | 0.0 |
| 4 | 12 | 4 | 0 | 0.0 |
| 16 | 12 | 16 | 0 | 0.0 |
| 32 | 12 | 16 | 16 | 15.7 |

At 32 streams llama.cpp served 16 requests at once, one a slot, and deferred the other 16: it
accepted them, queued them until a slot freed, and refused or errored none. A deferred request
started only when the first wave finished, about 46 s in, so its TTFT includes that wait, and
TTFT's p95 over every request reads 54.7 s, against a median of 9.4 s. The aggregate held, 80.1
against 16 streams' 81.6 tok/s, and the successful requests' ITL median, 147.71 against 140.28 ms,
moved little. Past its slots, llama.cpp gives no more output; each request beyond them waits in
the queue, first come, first served, with no bound on its length.

## Initial setting

The initial setting is the smaller of two readings of the curve above:

- **10 tok/s a stream:** the most streams at which each stream decodes at 10 tok/s or more, by both
  per-stream figures, the aggregate over N and 1000 over the ITL median. 4 streams: 17.4 and 22.0
  tok/s; at 16 streams they read 5.1 and 7.1.
- **The knee:** the level after which the aggregate gains under 10% a step; with no such step, the
  sweep's top level. 16 streams: 4 to 16 gained 17.4%, and 16 to 32 −1.8%.

Initial setting for gpt-oss-120b MXFP4 on llama.cpp b11960 in ggml's Vulkan image on the
Framework, read off this sweep's synthetic prompts, 512 in and 256 out: **4 streams**. It is where
tuning starts for this model, workload, and host, and moves as the stack is used. Set A's
gpt-oss-120b section starts at 4 slots whatever this reads (the brief's behavior 5), and here the
two agree.

gb10-1's curve, llama.cpp b11669 in ggml's CUDA 13 image, is the same sweep on the other host
class, run on 2026-10-26 directly over the LAN at 0 to 2 ms
([bench-gb10-container](bench-gb10-container.md#concurrency-sweep)):

| Streams | Completed | Incomplete | Errored | Output tok/s (total) | TTFT median ms (total) | TTFT p95 ms (total) | ITL median ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 11 | 1 | 0 | 48.5 | 418 | 476 | 18.89 | 5.24 | 5.30 |
| 4 | 16 | 4 | 0 | 77.1 | 1318 | 1651 | 46.19 | 13.17 | 13.43 |
| 16 | 16 | 16 | 0 | 129.0 | 5440 | 5976 | 104.70 | 32.59 | 34.17 |
| 32 | 16 | 32 | 0 | 126.2 | 5791 | 37926 | 108.22 | 33.22 | 34.79 |

The two sit side by side as evidence of each host's curve. They ran in different sessions, at
different builds, over different paths, so no figure here is compared with one there.

## Walkthrough

After set A was served, on 2026-10-29 from about 15:25 to 15:33Z, the architect walked slice 4:
spike-model-hosting's router retired with every step from
[5. Retire the router](../engines/llama.cpp/setup.md#5-retire-the-router), at f8e34a4, the session
reading the state back before and after, then Pi against set A from the laptop. Nothing here is a
measurement; the walkthrough shows the guide's retirement runs in the architect's hands and that
Pi works against set A unchanged.

### The router's retirement

In order:

1. **The read-back before**, the session's, the guide's first block exactly, at about 15:25Z. It
   matched the guide's table on every row:

   | Read | Printed |
   |---|---|
   | `systemctl show llama-router` | `LoadState=loaded`, `ActiveState=inactive`, `FragmentPath=/etc/systemd/system/llama-router.service`, `DropInPaths` empty, `UnitFileState=disabled` |
   | `/etc/llama-router` | 8 files: `llama-router.service.b11669`, `llama-router.service.b11715`, `models.ini`, `models.ini.a65fd306` (`jaime`'s), `models.ini.b11669`, `models.ini.b11715`, `models.ini.f98d9faf`, `models.ini.pre-sets`; the directory `root:jaime`, `0775` |
   | `/opt/llama.cpp` | `b11715`, `b11734`, and `current -> b11734`, all root's |
   | `findmnt`, `df` | `/mnt/models` on `/dev/nvme1n1p1`, ext4, `rw,noatime`; 916G size, 82G used, 788G available, 10% |
   | `du` | `models--ggml-org--embeddinggemma-2-GGUF` 296M, `models--ggml-org--gemma-4-26B-A4B-it-GGUF` 15G, `models--ggml-org--gemma-4-E4B-it-GGUF` 8.1G, `models--ggml-org--gpt-oss-120b-GGUF` 60G |
   | Home and the models directory | `~/llama-router.service.83b0a95c`, the link `~/models -> /mnt/models/gguf`, `~/models.ini.039c5fa7`, `.96732ef9`, `.9c983739`, and `.9eeb9f04`; `/mnt/models/gguf` empty |
   | `find ~/.local/bin` | `outpost*`, `outpost`, `outpost-preset-install`, `outpost-service-restart`, `outpost-service-status` |
   | Port 8080 | `ss`: `LISTEN` on `<tailnet address>:8080`; `docker port llama`: `8080/tcp -> <tailnet address>:8080` |

2. **The architect's steps**, at the Framework's own prompt, exactly as the guide gives them: the
   four root commands (`systemctl disable --now`, the unit file's `rm`, `daemon-reload`, and the
   `rm -r` of `/etc/llama-router` and `/opt/llama.cpp`), then the four as `jaime` (the cache's
   `rm -r`, the `rmdir` of `/mnt/models/gguf`, the link and render copies' `rm`, and outpost's
   links' `rm`). Each printed nothing.

3. **The read-back after**, the session's, the guide's second block exactly, ending at
   15:31:46Z:

   | Read | Printed |
   |---|---|
   | `systemctl show llama-router -p LoadState` | `LoadState=not-found` |
   | `command ls -d` | `cannot access '/etc/llama-router'` and `cannot access '/opt/llama.cpp'`: `No such file or directory` |
   | `df` | 916G size, 36K used, 870G available, 1% |
   | `du` | `16K /mnt/models/lost+found`, with `du: cannot read directory '/mnt/models/lost+found': Permission denied` |
   | Home | `cannot access` for `/home/jaime/models`, `/home/jaime/models.ini.*`, and `/home/jaime/llama-router.service.*` |
   | `find ~/.local/bin` | nothing |
   | Port 8080 | `ss`: `LISTEN` on `<tailnet address>:8080`; `docker port llama`: `8080/tcp -> <tailnet address>:8080` |

No `llama-router` unit is left; `/etc/llama-router` and `/opt/llama.cpp` are gone; the models
drive stays mounted, holding only `lost+found`, with 82G freed; and port 8080 is still the `llama`
container's. No step touches what the retirement keeps: the ufw route rules, the `docker` group,
and `/srv/models`. The router is retired as of 2026-10-29.

### Pi against set A

From the laptop at about 15:33Z (its clock read 11:33 local), with `LLAMA_BASE_URL` unchanged at
`http://framework:8080`, the architect ran Pi from the laptop's clone of this repository on
`answer`:

1. **The model.** The architect selected `gpt-oss-120b-MXFP4-set-a`, which Pi showed as the model
   in its header and status bar. Its context read 20.7%/131k, the section's `c = 131072`, which
   its 4 slots share through the unified KV cache
   ([12. Serve set A](../engines/llama.cpp/setup.md#12-serve-set-a)).
2. **The prompt**, one that needs tools: "List the files in this directory and tell me which is
   largest".
3. **The tool calls.** Pi showed the model's reasoning, then three bash tool calls:
   `ls -lR --block-size=K . | sort -k5 -h | tail -n 10`, `find . -type f -printf "%p %s\n" | sort
   -k2 -n`, and `ls -lA`.
4. **The answer.** A listing of the clone's top level, and its largest file,
   `.state/bench/vllm-granite-embed.json`, at 63,874,534 bytes (about 63.9 MiB).
5. **The status bar** read `↑29k ↓870`, `R28k`, and `CH98.3%`, Pi's cache hit.

**`/llama`'s list wasn't captured.** The architect's screenshots don't show Pi's `/llama` list of
set A's four models as loaded. Selecting the new section's id, `gpt-oss-120b-MXFP4-set-a`, and
the `/models` read-back with all four `loaded` ([Set A, served](#set-a-served)) stand for it.
