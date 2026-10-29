# llama.cpp's concurrency sweep on the Framework, in ggml's Vulkan image

To be recorded on the Framework, from the steps and cells the task's brief agreed (context/goals,
`answer`). llama.cpp v0.8.0 (b11960) serves gpt-oss-120b MXFP4 in ggml's Vulkan image, the
backend the Framework's answer names ([vllm-strix](vllm-strix.md)), and this finding measures how
its served output scales with concurrent streams: anchor A on the 4-slot section first, then
gb10-1's concurrency sweep exactly ([bench-gb10-container](bench-gb10-container.md#concurrency-sweep))
on the 16-slot section, 512 in, 256 out, at 1, 4, 16, and 32 streams, 60 s a level. Its result is
an initial setting for how many streams to serve the model at, a starting point tuned as the
stack is used; it is never a limit. The curve sits beside gb10-1's (b11669) as evidence, and no
figure is compared across the two sessions ([Comparisons](../../context/README.md#rules)).

The session runs each step on framework over Tailscale SSH, and each GuideLLM cell from the
laptop, in the architect's view, from the clone at TBD on `answer` on both machines, printing each
block before it runs.

## Host stack

To be recorded after the architect's `omarchy update` ([Host stack](#1-the-host-stack)).

| Item | framework |
|---|---|
| Recorded at | TBD |
| OS | Omarchy TBD (Arch Linux) |
| Kernel, running | TBD (`uname -r`) |
| Kernel, installed | `linux-omarchy` TBD; Arch's `linux` TBD, which the host doesn't boot |
| Reboot pending | TBD: yes when the installed `linux-omarchy` isn't the running kernel |
| Mesa, `vulkan-radeon` | TBD, TBD |
| linux-firmware | TBD |
| Docker | TBD (package), TBD (server) |
| GTT ceiling | TBD: ttm `pages_limit` TBD, `mem_info_gtt_total` TBD |
| RAM | TBD (`MemTotal`) |
| Other engines | `vllm` TBD; `llama-router` TBD |

## Engine versions

| Engine | Release | Build | Image | Devices |
|---|---|---|---|---|
| llama.cpp, Vulkan container | v0.8.0 | b11960; `/props` build_info TBD | `ghcr.io/ggml-org/llama.cpp:server-vulkan-b11960` (`host/llama.env`, flavor `vulkan`) | TBD (`/dev/dri` expected) |

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

On framework. The branch is pushed to origin first, so the host's clone can switch to it. The
clone moves to `answer` and prints the commit it is at; then `host/engines llama update` with the
flavor given as `LLAMA_FLAVOR=vulkan`, since the suite picks `rocm` on an AMD GPU when none is
given ([Update](../engines/llama.cpp/update.md#switching-the-flavor)). At b11960 already, the
update pulls nothing and, finding `llama` stopped, says so without starting it, so the block starts
it and waits for the router; the router runs with `--no-models-autoload`, so it holds no model.
Then its image and devices, which read `server-vulkan-b11960` and `/dev/dri`:

```sh
cd ~/repos/spike-model-engines && git fetch -q origin && git switch -q answer && git pull -q --ff-only && git log --oneline -1
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

On framework. Step 3's load block, with the 16-slot section in `model` and the 4-slot section in
`prev`, which it unloads first, so one copy of the model's weights is in memory:

```sh
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
| Each load | under 20 s (vllm-strix's Vulkan loads, 0.6 to 18.2 s, from a dropped cache) | TBD |
| Anchor A | under 1 min (8 requests of about 5.7 s) | TBD |
| The sweep | 4.5 min (four 60 s levels and setup) | TBD |

## Results

To be run on framework and the laptop, times UTC, from the files each step wrote. The client
figures are GuideLLM's, read with [the read-outs](#5-the-read-outs); the server figures are its
`awk`.

### Network path and model state

| Section | Load | Warm-up at | `tailscale ping` | `/props` build_info | Warm-up reply | `requests_processing` before |
|---|---|---|---|---|---|---|
| `ggml-org/gpt-oss-120b-GGUF:MXFP4`, 4 slots | TBD s; MemAvailable TBD, GTT in use TBD after | TBD | TBD | TBD | TBD | TBD |
| `gpt-oss-120b-MXFP4-16-slots`, 16 slots | TBD s; MemAvailable TBD, GTT in use TBD after | TBD | TBD | TBD | TBD | TBD |

### Anchor A

gpt-oss-120b on the 4-slot section, 1 stream, 8 requests, 512 in, 256 out.

| Completed | Errored | Output tok/s (successful mean) | Output tok/s (total mean) | TTFT median ms | TTFT p95 ms | ITL median ms | Latency median s |
|---|---|---|---|---|---|---|---|
| TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |

Beside vllm-strix's 44.97903 tok/s at b11960 on the same host: TBD%. vllm-strix read up to 0.7%
on this host, and 1.0 to 1.4% on gb10-1, as run noise ([Anchors](vllm-strix.md#anchors)); a move
beyond it is a finding. Server: TBD.

### Concurrency sweep

gpt-oss-120b MXFP4 on 16 slots, 512 in, 256 out, 60 s a level. Requests in flight when a level's
60 s end are cancelled and counted incomplete. Output tok/s and TTFT are GuideLLM's `total`, over
every request, completed or not; ITL and latency are the successful requests'
([bench-gb10-container](bench-gb10-container.md#concurrency-sweep)).

| Streams | Completed | Incomplete | Errored | Output tok/s (total) | Per stream, aggregate / N | Per stream, 1000 / ITL median | Gain on the level before | TTFT median ms (total) | TTFT p95 ms (total) | ITL median ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | TBD | TBD | TBD | TBD | TBD | TBD | — | TBD | TBD | TBD | TBD | TBD |
| 4 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| 16 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| 32 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |

Past the 16 slots, the sampler's gauges by level:

| Streams | Samples | `requests_processing`, most at once | `requests_deferred`, most at once | `requests_deferred`, mean |
|---|---|---|---|---|
| 1 | TBD | TBD | TBD | TBD |
| 4 | TBD | TBD | TBD | TBD |
| 16 | TBD | TBD | TBD | TBD |
| 32 | TBD | TBD | TBD | TBD |

Server figures over the whole sweep: TBD.

## Initial setting

The initial setting is the smaller of two readings of the curve above:

- **10 tok/s a stream:** the most streams at which each stream decodes at 10 tok/s or more, by both
  per-stream figures, the aggregate over N and 1000 over the ITL median. TBD.
- **The knee:** the level after which the aggregate gains under 10% a step; with no such step, the
  sweep's top level. TBD.

Initial setting for gpt-oss-120b MXFP4 on llama.cpp b11960 in ggml's Vulkan image on the
Framework, at 512 in and 256 out: TBD streams. It is where tuning starts for this model, workload,
and host, and moves as the stack is used.

gb10-1's curve, llama.cpp b11669 in ggml's CUDA 13 image, is the same sweep on the other host
class ([bench-gb10-container](bench-gb10-container.md#concurrency-sweep)), 2026-10-26. The two sit
side by side as evidence of each host's curve; they ran in different sessions, at different builds,
so no figure here is compared with one there.
