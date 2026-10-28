# vLLM on the Framework, beside llama.cpp's Vulkan image

Recorded on 2026-10-28, on framework, from the steps and cells the task's brief agreed
(context/goals, `vllm-strix`). vLLM v0.32.0 runs in its official ROCm image, one row at a time in
one `vllm` container, and llama.cpp v0.8.0 (b11960) in ggml's Vulkan image, the backend that led
llama-strix-rocm ([Verdict](llama-strix-rocm.md#verdict)), in the same session, so every vLLM cell
has a llama.cpp cell beside it ([Comparisons](../../context/README.md#rules)). It is evidence 1
and 2 for vLLM on Strix Halo ([The evidence](../../context/README.md#the-evidence)): install and
guides, raw speed, TTFT, footprint, and cold start by shape, and the quantization pair. It records
what was measured and states no verdict; the answer task reads it.

The session runs each step on framework over Tailscale SSH, and each GuideLLM cell from the
laptop, in the architect's view, from the clone at (to fill) on `vllm-strix` on both machines,
printing each block before it runs.

## Host stack

Recorded on 2026-10-28, after the architect's `omarchy update`, which moved `google-chrome` to
156.0.8078.73 and `mise-bin` to 2026.10.21 and nothing that touches the engines.

| Item | framework |
|---|---|
| OS | Omarchy 4.0.6 (Arch Linux) |
| Kernel | 7.2.8-9-omarchy (`linux-omarchy`) |
| Mesa | 26.2.5 |
| linux-firmware | 20260916 |
| Docker | 29.9.2 |
| ROCm | host `rocm-core` 7.2.4-1, unused by both containers; vLLM's image's own ROCm 7.2.3 (`/opt/rocm/.info/version`); llama.cpp's Vulkan image has none |
| GTT ceiling | 112 GiB: `mem_info_gtt_total` 120259084288 |
| Firmware carve-out (VRAM) | 512 MiB |
| RAM | 125.1 GiB |
| Firewall | ufw with ufw-docker, and the two route rules for 8080 and 8000 on `tailscale0` ([llama.cpp's Setup](../engines/llama.cpp/setup.md#4-route-the-ports-through-ufw)) |
| Reboot pending | no: the update installed no kernel, and the running `linux-omarchy` 7.2.8-9 is the one installed |

Arch's stock `linux` 7.2.11.arch1-1 is also installed, but it isn't the flavor the host boots, so
it is no pending reboot of the running kernel. spike-model-hosting's `llama-router` is stopped and
disabled for the task ([llama.cpp's Setup](../engines/llama.cpp/setup.md#5-stop-the-router)), so
nothing else serves on the host.

## Engine versions

| Engine | Release | Build | Image | Devices |
|---|---|---|---|---|
| vLLM, container | v0.32.0 | `vllm --version` `0.32.0+rocm723` | `vllm/vllm-openai-rocm:v0.32.0` (`host/vllm.env`, flavor `rocm`), digest `sha256:14f6a575e1fb0a580b0f633c09e06f648709d60405b85f6a7ff3f80d49f39905`, 46.65 GB unpacked; entrypoint `["vllm","serve"]` | `--device /dev/kfd --device /dev/dri`, with `--ipc host` |
| llama.cpp, Vulkan container | v0.8.0 | b11960; `/props` build_info `b11960-8642541b2` | `ghcr.io/ggml-org/llama.cpp:server-vulkan-b11960` (`host/llama.env`, flavor `vulkan`), digest `sha256:c9aba1a6…df62e` | `--device /dev/dri` |

vLLM serves one row of `host/vllm-rows` at a time on port 8000 of the tailnet address, the
flavor's default `gpt-oss-120b` or the one `VLLM_MODEL` names for a run
([Models](../engines/vllm/models.md#the-rows-on-the-framework)); every row reserves 0.80 of the
memory vLLM finds. llama.cpp serves the preset (`host/llama-preset/models.ini`) from the same
store, `/srv/models`, on port 8080, as in llama-strix-rocm. `host/engines llama update` moved the
`llama` container from `server-rocm-b11669` to `server-vulkan-b11960` at 15:28Z and removed the
b11669 images; `llama` was then stopped by hand.

The load tool is GuideLLM 0.8.1 on the laptop, in the spike's bench environment
(`mise.bench.toml`: Python 3.14.10, with the `vision` and `audio` extras).

## Viability

Slice 2's first walk of vLLM's ROCm image, the architect's, from
[the vLLM guide's Framework steps](../engines/vllm/setup.md#framework-in-a-container), before any
cell here.

- **The image reads the GPU.** `rocminfo`, at `/opt/rocm/bin/rocminfo` in the image, named the
  agent `gfx1151` (and the `gfx11-generic` ISA), with its `GLOBAL` coarse-grained and
  extended-fine-grained pools each 117440512 KB, 112 GiB: the whole GTT ceiling, 120259084288
  bytes, as llama.cpp's ROCm image counted it.
- **The state before the first start**, at 15:36:52Z: the compile cache absent, MemAvailable
  122145716 kB, `mem_info_gtt_used` 244002816 and `mem_info_vram_used` 491102208 bytes, and the
  session's unit checks `inactive inactive`.
- **The first start, gpt-oss-120b from an empty compile cache.** `host/engines vllm install`
  started the row; the container's StartedAt was 15:37:45Z, `Application startup complete.` about
  15:40:54Z, about 189 s, and `/health` answered 200 at 15:40:58Z, within the 20 minutes the
  brief allows this start alone. What it logged:

  | Figure | Value |
  |---|---|
  | MoE backend | TRITON, `OAITritonMxfp4ExpertsMonolithic` |
  | Free memory on device | 112.0/112.0 GiB; 0.80 of it, 89.6 GiB, reserved |
  | Model loading | 68.82 GiB, 16.1 s |
  | Consumed by the model | 69.2 GiB |
  | KV cache | 18.63 GiB, 357,622 tokens, 43.66 times 8192 |
  | Graph capture | 61 s (0.69 GiB) and 23 s (0.68 GiB), with no HIP timeout |
  | init engine | 139.86 s, compilation 11.81 s |
  | Compile cache after | 333M |

  After it, MemAvailable read 25096668 kB (23.9 GiB), GTT in use 95606444032 bytes (89.0 GiB),
  and VRAM in use 519749632 bytes.
- **Warm anchor A from the laptop**, about 15:45Z, after one warm-up request: the path direct at
  1 ms, `/version` `0.32.0`; 10.0 output tok/s, latency 25.5 s, TTFT 796.6 ms, ITL 97.1 ms, TPOT
  99.8 ms. Its files are the laptop's `.state/vllm-strix/anchor-a.{json,before.metrics,after.metrics}`.
  It is a viability check, not a comparison cell: no llama.cpp cell ran beside it, and
  llama.cpp's 45.13 tok/s is b11669's, from llama-strix-rocm. The anchors below rerun it.
- **One engine per host holds.** While `vllm` ran, `host/engines llama install` and `update` both
  exited 1 with `vllm is running, and one engine serves per host at a time, since each reserves
  most of the host's GPU memory; docker stop vllm stops it`.

## Method

The session runs the steps in this order, each printed before it runs:

1. vLLM, on framework and the laptop, one row at a time, in the order of
   [vLLM's order](#vllms-order): per row, its first start, its timed start, then its warm-up and
   cells.
2. llama.cpp's Vulkan set at b11960, after `vllm` is stopped by hand: the `llama` container
   started, then llama-strix-rocm's steps 1 to 7.
3. The end state, on framework.

Each block below is self-contained, so it runs as one `ssh framework` command or at one prompt.
Blocks marked "on framework" run from `~/repos/spike-model-engines` and set it themselves; blocks
marked "on the laptop" run from the laptop's clone. `.state/` is untracked on both. The run cap is
10 minutes; [Run times](#run-times) gives each run's estimate.

Every model the vLLM rows name, and both images, are staged before the first step, through hf on
the Framework ([Models](../engines/vllm/models.md#on-the-framework)), so no start downloads.

### Once, before the first step

On framework, the clone brought to the branch's head, and the commit it is at; then the two
containers, the command `vllm` serves, which is the `gpt-oss-120b` row's, the staged images, the
compile cache, and the router:

```sh
cd ~/repos/spike-model-engines && git pull --ff-only && git log --oneline -1
docker ps -a --filter name=vllm --filter name=llama --format "{{.Names}} {{.Image}} {{.Status}}"
docker inspect --format '{{.Config.Image}} {{join .Config.Cmd " "}}' vllm
docker image ls --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep -E 'vllm-openai-rocm|llama.cpp'
test -e ~/.cache/vllm && du -sh ~/.cache/vllm || echo absent
systemctl is-enabled llama-router; systemctl is-active llama-router
```

`llama` reads `Exited`, so it holds no GPU memory while vLLM runs. On the laptop, the same, and
the directories the cells write to, one per engine:

```sh
git pull --ff-only && git log --oneline -1
mkdir -p .state/vllm-strix/vllm .state/vllm-strix/vulkan
```

### vLLM, per row: the first start

On framework, with `row` set to the step's row from [vLLM's order](#vllms-order). Every row but
`gpt-oss-120b`, whose first start is [Viability](#viability)'s, runs this step. It stops the
running container, so the memory read before holds no model, reads the compile cache's size,
MemAvailable, and GTT and VRAM in use, then serves the row for one run
([Models](../engines/vllm/models.md#serving-another-row-for-one-run)); `update` replaces the
container and pulls nothing, since the image is the pin's. The start fills the compile cache for
the row's model, from the page cache as it is.

The block polls `/health` every 5 s for 10 minutes at most, and stops polling early when the
container has restarted. It then prints the time, in UTC, the last `/health` status, the
container's state and the command it serves, the start's time from StartedAt to `Application
startup complete.`, the memory after, the lines vLLM logged for this start, and the compile
cache's size after. The GPU's memory is read through a glob, `card*`, which matches only the one
GPU, as [the guide](../engines/vllm/setup.md#6-read-the-memory-it-sized-against) reads it. Step
2's, E4B BF16:

```sh
cd ~/repos/spike-model-engines
row=gemma-4-E4B-it
docker stop vllm >/dev/null; test -e ~/.cache/vllm && du -sh ~/.cache/vllm || echo absent
grep ^MemAvailable /proc/meminfo; echo "gtt_used $(cat /sys/class/drm/card*/device/mem_info_gtt_used) vram_used $(cat /sys/class/drm/card*/device/mem_info_vram_used)"
VLLM_MODEL=$row host/engines vllm update 2>&1 | tail -3
since=$(docker inspect --format '{{.State.StartedAt}}' vllm); cap=$((SECONDS + 600)); s=
until s=$(curl -s -o /dev/null -w '%{http_code}' "http://$(tailscale ip -4):8000/health"); [[ $s == 200 ]] || ((SECONDS >= cap)); do [[ $(docker inspect --format '{{.RestartCount}}' vllm) == 0 ]] || break; sleep 5; done
date -u +%FT%TZ; echo "health $s"; docker inspect --format '{{.State.Status}}, restarts {{.RestartCount}}' vllm
docker inspect --format '{{.Config.Image}} {{join .Config.Cmd " "}}' vllm
t=$(docker logs --timestamps --since "$since" vllm 2>&1 | grep -m 1 "Application startup complete" | cut -d' ' -f1)
echo "started $since, startup complete ${t:-not logged}"; [[ -z $t ]] || awk -v a="$(date -d "$since" +%s.%N)" -v b="$(date -d "$t" +%s.%N)" 'BEGIN { printf "first start %.1f s\n", b - a }'
grep ^MemAvailable /proc/meminfo; echo "gtt_used $(cat /sys/class/drm/card*/device/mem_info_gtt_used) vram_used $(cat /sys/class/drm/card*/device/mem_info_vram_used)"
docker logs --since "$since" vllm 2>&1 | grep -E "Free memory on device|Model loading took|Available KV cache memory|KV cache size|Graph capturing finished|init engine"
du -sh ~/.cache/vllm
```

Each later step, the same block with its `row`. `health 200` beside `running, restarts 0` means
the row serves. A start that fails, `health` not 200 beside restarts above 0 or a container not
running, is the row's result: read its log's end, record it, and stop the container, so it
doesn't restart; the row's timed start and cells are skipped and marked unsupported with that
reason, and the run goes on to the next row:

```sh
docker logs --tail 50 vllm
docker stop vllm
```

A start still running at 10 minutes, `health` not 200 beside `running, restarts 0`, is an
escalation: the session stops and reports it.

### vLLM, per row: the timed start

On framework, after the row's first start, with its compile cache warm. The block stops `vllm`,
drops the page cache through the existing sudoers rule
([llama.cpp's Setup](../engines/llama.cpp/setup.md#11-allow-the-page-cache-drop)), showing the
cache before and after, reads MemAvailable and GTT and VRAM in use, then starts the same
container and times the start from `docker start` to the first `/health` 200, polled every half
second for 10 minutes at most. It then prints the same read-outs as the first start, the time from
StartedAt to `Application startup complete.` among them. Step 1's, gpt-oss-120b, whose step is this
start alone:

```sh
cd ~/repos/spike-model-engines
docker stop vllm >/dev/null; docker ps -a --filter name=vllm --format "{{.Names}} {{.Image}} {{.Status}}"
echo; grep ^Cached /proc/meminfo; sync && sudo -n /usr/bin/sysctl vm.drop_caches=3; grep ^Cached /proc/meminfo
grep ^MemAvailable /proc/meminfo; echo "gtt_used $(cat /sys/class/drm/card*/device/mem_info_gtt_used) vram_used $(cat /sys/class/drm/card*/device/mem_info_vram_used)"
start=$(date +%s.%N); docker start vllm >/dev/null; cap=$((SECONDS + 600)); s=
until s=$(curl -s -o /dev/null -w '%{http_code}' "http://$(tailscale ip -4):8000/health"); [[ $s == 200 ]] || ((SECONDS >= cap)); do sleep 0.5; done
echo "health $s after $(awk -v a="$start" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1f", b - a }') s"; date -u +%FT%TZ
since=$(docker inspect --format '{{.State.StartedAt}}' vllm); docker inspect --format '{{.State.Status}}, restarts {{.RestartCount}}' vllm
docker inspect --format '{{.Config.Image}} {{join .Config.Cmd " "}}' vllm
t=$(docker logs --timestamps --since "$since" vllm 2>&1 | grep -m 1 "Application startup complete" | cut -d' ' -f1)
echo "started $since, startup complete ${t:-not logged}"; [[ -z $t ]] || awk -v a="$(date -d "$since" +%s.%N)" -v b="$(date -d "$t" +%s.%N)" 'BEGIN { printf "timed start %.1f s\n", b - a }'
grep ^MemAvailable /proc/meminfo; echo "gtt_used $(cat /sys/class/drm/card*/device/mem_info_gtt_used) vram_used $(cat /sys/class/drm/card*/device/mem_info_vram_used)"
docker logs --since "$since" vllm 2>&1 | grep -E "Free memory on device|Model loading took|Available KV cache memory|KV cache size|Graph capturing finished|init engine"
```

The block is the same for every row: it names none, since `docker start` starts the container the
row's first start left. The `docker inspect` of its command shows which row it is. A timed start
past 10 minutes is an escalation, as the first start's is.

### vLLM, per row: the version and the warm-up

On the laptop, with `model` set to the row's from [vLLM's order](#vllms-order), as
bench-gb10-container ran it
([vLLM: per row, the version and the warm-up](bench-gb10-container.md#vllm-per-row-the-version-and-the-warm-up)):
the time and the network path, the release the server runs and the model it serves, then one
warm-up request, the API page's chat completion, its reasoning cut to its first 80 characters,
and last the confirmation that the server is warm and idle. Step 1's, gpt-oss-120b:

```sh
model=openai/gpt-oss-120b
date -u +%FT%TZ; tailscale ping -c 3 framework
curl -s "http://framework:8000/version"; echo
curl -s "http://framework:8000/v1/models" | jq -c '.data[] | {id, max_model_len}'
curl -s "http://framework:8000/v1/chat/completions" -H "Content-Type: application/json" -d "{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one sentence.\"}]}" | jq -c '.choices[0].message | {content, reasoning: (.reasoning|tostring|.[0:80])}'
curl -s "http://framework:8000/metrics" | grep -E '^vllm:(request_success_total|num_requests_running)'
```

For the Gemma 4 rows, steps 2 to 6, the warm-up asks the model to reason, as their shape cells
do; the block is the same with this line in place of the chat completion:

```sh
curl -s "http://framework:8000/v1/chat/completions" -H "Content-Type: application/json" -d "{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one sentence.\"}], \"chat_template_kwargs\": {\"enable_thinking\": true}}" | jq -c '.choices[0].message | {content, reasoning: (.reasoning|tostring|.[0:80])}'
```

For granite-embedding-english-r2, step 7, the embedding instead:

```sh
curl -s "http://framework:8000/v1/embeddings" -H "Content-Type: application/json" -d "{\"model\": \"$model\", \"input\": \"Say hello in one sentence.\"}" | jq -c '{model, usage}'
```

The warm start is confirmed when the warm-up returned a reply, `vllm:request_success_total` counts
it, and `vllm:num_requests_running` is 0.

### vLLM, per cell

On the laptop. Each cell's files go to `.state/vllm-strix/vllm/`: its JSON, its GuideLLM log, and
the `/metrics` snapshots before and after it. vLLM serves `/metrics` for its one model, with no
model named. The before-snapshot guard is llama-strix-rocm's ([Per cell](llama-strix-rocm.md#per-cell)):
the block fetches it up to five times, 2 s apart, and when it is still empty prints so and runs no
more of the row's cells. Its `vllm:num_requests_running` line prints, 0 when nothing else is using
the server.

Every row's cells run in one form, each a `scenario:cell` pair, the model and tokenizer given on
the command line, as bench-gb10-container ran vLLM's
([vLLM: per cell](bench-gb10-container.md#vllm-per-cell)). gpt-oss-120b's anchors run
`bench/anchor-a.yaml` and `anchor-b.yaml`, llama.cpp's anchor scenarios with vLLM's model given
in place of theirs, as viability's anchor A and bench-gb10-container's gpt-oss-120b did:
`bench/vllm-anchor-a.yaml` and `vllm-anchor-b.yaml` are A' and B', which name NVIDIA's NVFP4
26B-A4B, a CUDA-only row, and ask Gemma 4 to reason. Each guidellm runs under `timeout 10m`,
which ends a cell at the cap and exits 124. Step 1's:

```sh
export GUIDELLM__SPEC__BACKEND__TARGET="http://framework:8000"; o=.state/vllm-strix/vllm
model=openai/gpt-oss-120b; tok=openai/gpt-oss-120b; cells=(anchor-a:anchor-a anchor-b:anchor-b)
for c in "${cells[@]}"; do scenario=${c%%:*}; cell=${c#*:}; p=$o/$cell
for i in 1 2 3 4 5; do curl -s "http://framework:8000/metrics" > $p.before.metrics; test -s $p.before.metrics && break; sleep 2; done
if ! test -s $p.before.metrics; then echo "vllm $cell: before-snapshot empty after 5 tries; not run"; break; fi
grep "^vllm:num_requests_running" $p.before.metrics
MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/$scenario.yaml --backend "kind=openai_http,model=$model" --tokenizer "kind=huggingface_auto,model=$tok" --output "kind=json,path=$p.json" > $p.log 2>&1; echo "vllm $cell: guidellm exit $?"
curl -s "http://framework:8000/metrics" > $p.after.metrics; test -s $p.after.metrics || echo "vllm $cell: after-snapshot empty"
done
```

Each later step, the same block with its `model`, `tok`, and `cells`. A cell whose guidellm exits
non-zero, or whose requests all error, is read from its log and the server's (`docker logs --tail
50 vllm` on framework); a cell vLLM can't serve on gfx1151 is marked unsupported in the results,
with that reason, and the row's next cell runs. A cell the cap ends (exit 124) is recorded as not
finished within 10 minutes, with what its log shows, and the run goes on.

### vLLM's order

One row served at a time, each a new container. Each row's values set the first start's `row` on
framework and the laptop's `model`, `tok`, and `cells`:

| Step | `row` (`VLLM_MODEL`) | `model` | `tok` | `cells` |
|---|---|---|---|---|
| 1 | `gpt-oss-120b` | `openai/gpt-oss-120b` | `openai/gpt-oss-120b` | `(anchor-a:anchor-a anchor-b:anchor-b)` |
| 2 | `gemma-4-E4B-it` | `google/gemma-4-E4B-it` | `google/gemma-4-E4B-it` | `(shape-a:e4b-bf16-shape-a audio-a:e4b-bf16-audio-a audio-b:e4b-bf16-audio-b)` |
| 3 | `gemma-4-E4B-it-qat-w4a16-ct` | `google/gemma-4-E4B-it-qat-w4a16-ct` | `google/gemma-4-E4B-it` | `(shape-a:e4b-w4a16-shape-a)` |
| 4 | `gemma-4-12B-it-qat-w4a16-ct` | `google/gemma-4-12B-it-qat-w4a16-ct` | `google/gemma-4-12B-it-qat-w4a16-ct` | `(shape-a:12b-shape-a shape-b:12b-shape-b)` |
| 5 | `gemma-4-31B-it-qat-w4a16-ct` | `google/gemma-4-31B-it-qat-w4a16-ct` | `nvidia/Gemma-4-31B-IT-NVFP4` | `(shape-large-a:31b-large-a shape-large-b:31b-large-b)` |
| 6 | `gemma-4-26B-A4B-it` | `google/gemma-4-26B-A4B-it` | `nvidia/Gemma-4-26B-A4B-NVFP4` | `(shape-a:26b-shape-a shape-b:26b-shape-b vision-a:26b-vision-a vision-b:26b-vision-b)` |
| 7 | `granite-embedding-english-r2` | `ibm-granite/granite-embedding-english-r2` | `ibm-granite/granite-embedding-english-r2` | `(embed:granite-embed)` |

Step 1 runs only the timed start, since its first start is viability's; steps 2 to 7 run both.
The steps follow llama.cpp's, so each vLLM cell pairs with the llama.cpp cell of the same model
and shape: E4B BF16's with E4B Q8_0's, and E4B QAT w4a16's with E4B QAT Q4_0's, the quantization
pair on each engine; the other cells share their names across `.state/vllm-strix/vllm/` and
`vulkan/`. The scenarios' loads are llama-strix-rocm's ([Order](llama-strix-rocm.md#order)), and
the audio cells are its E4B audio through chat. gpt-oss-120b's row holds 16 sequences, against
llama.cpp's 4 slots, so at anchor B's 4 streams 12 stand idle.

Each `tok` is llama-strix-rocm's for the same model, so both engines in this session cut the same
prompts, which are gb10-1's; for E4B, the 12B, and granite that is the served repository itself.

### Model state

Each vLLM row is served by a new container, which first starts once to fill its compile cache,
then is stopped and started again from a dropped page cache, the timed start, and is warmed with
one request before its first cell; its cells then run in the order above. Each llama.cpp model is
loaded fresh, from a dropped page cache, and warmed with one request, as in llama-strix-rocm
([Model state](llama-strix-rocm.md#model-state)). Every cell so starts from a model that has
served one request and the cells before it, the same on both engines.

### llama.cpp's Vulkan set: the container started

On framework, after vLLM's step 7. `vllm` is stopped by hand, so it holds no GPU memory and stays
stopped at boot; then `llama`, already at `server-vulkan-b11960`, is started with no model loaded
and waited for, and its image and devices read, which are `server-vulkan-b11960` and `/dev/dri`:

```sh
cd ~/repos/spike-model-engines
docker stop vllm >/dev/null; docker ps -a --filter name=vllm --format "{{.Names}} {{.Image}} {{.Status}}"
docker start llama >/dev/null && until curl -fs "http://$(tailscale ip -4):8080/health" >/dev/null; do sleep 1; done
docker ps --filter name=llama --format "{{.Names}} {{.Image}} {{.Status}}"
docker inspect --format '{{.Config.Image}} {{range .HostConfig.Devices}}{{.PathOnHost}} {{end}}' llama
```

Then llama-strix-rocm's steps 1 to 7, in [its order](llama-strix-rocm.md#order), with its
`model`, `prev`, `tok`, and `cells` for each step. No llama-bench runs: it is out of this task's
scope.

### llama.cpp, per model: the cold load and its footprint

On framework. llama-strix-rocm's block
([Per model: the cold load and its footprint](llama-strix-rocm.md#per-model-the-cold-load-and-its-footprint)),
with the GPU's memory read through the `card*` glob in place of `card1`, as vLLM's blocks read it.
Step 1's, gpt-oss-120b, with `prev` empty on the router just started, is the timed cold load:

```sh
cd ~/repos/spike-model-engines
model=ggml-org/gpt-oss-120b-GGUF:MXFP4
prev=
[[ -z $prev ]] || curl -s -X POST "http://$(tailscale ip -4):8080/models/unload" -H "Content-Type: application/json" -d "{\"model\": \"$prev\"}"
[[ -z $prev ]] || until [[ $(curl -s "http://$(tailscale ip -4):8080/models" | jq -r --arg m "$prev" '.data[] | select(.id == $m) | .status.value') == unloaded ]]; do sleep 1; done
echo; grep ^Cached /proc/meminfo; sync && sudo -n /usr/bin/sysctl vm.drop_caches=3; grep ^Cached /proc/meminfo
grep ^MemAvailable /proc/meminfo; echo "gtt_used $(cat /sys/class/drm/card*/device/mem_info_gtt_used) vram_used $(cat /sys/class/drm/card*/device/mem_info_vram_used)"
since=$(date -u +%Y-%m-%dT%H:%M:%SZ); start=$(date +%s.%N)
curl -s -X POST "http://$(tailscale ip -4):8080/models/load" -H "Content-Type: application/json" -d "{\"model\": \"$model\"}"; echo
while :; do s=$(curl -s "http://$(tailscale ip -4):8080/models" | jq -r --arg m "$model" '.data[] | select(.id == $m) | if .status.failed then "failed" else .status.value end'); [[ $s == loaded || $s == failed ]] && break; sleep 0.5; done
echo "$s after $(awk -v a="$start" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1f", b - a }') s"
grep ^MemAvailable /proc/meminfo; echo "gtt_used $(cat /sys/class/drm/card*/device/mem_info_gtt_used) vram_used $(cat /sys/class/drm/card*/device/mem_info_vram_used)"
docker logs --since "$since" llama 2>&1 | grep -E "offloaded|buffer size|model size|flash_attn|Flash Attention|n_ctx |n_slots"
```

Each later step, the same block with its `model` and `prev` from llama-strix-rocm's
[Order](llama-strix-rocm.md#order).

### llama.cpp, per model: the build and the warm-up

On the laptop. llama-strix-rocm's block, exactly
([Per model: the build and the warm-up](llama-strix-rocm.md#per-model-the-build-and-the-warm-up)),
with `flavor=vulkan` and the step's `model` and `tok`, and for granite, step 7, its embedding in
place of the chat completion. `/props` build_info prints `b11960-8642541b2`.

### llama.cpp, per cell

On the laptop. llama-strix-rocm's blocks ([Per cell](llama-strix-rocm.md#per-cell)), with the
files written to `.state/vllm-strix/vulkan/` in place of `.state/strix/<flavor>/`. The anchors,
step 1, run their own scenarios, A then B:

```sh
export GUIDELLM__SPEC__BACKEND__TARGET="http://framework:8080"; flavor=vulkan; model=ggml-org/gpt-oss-120b-GGUF:MXFP4; o=.state/vllm-strix/$flavor
for cell in anchor-a anchor-b; do p=$o/$cell
for i in 1 2 3 4 5; do curl -sG "http://framework:8080/metrics" --data-urlencode "model=$model" --data-urlencode autoload=false > $p.before.metrics; test -s $p.before.metrics && break; sleep 2; done
if ! test -s $p.before.metrics; then echo "$flavor $cell: before-snapshot empty after 5 tries; not run"; break; fi
grep "^llamacpp:requests_processing" $p.before.metrics
MISE_ENV=bench mise exec -- guidellm run -c bench/$cell.yaml --output "kind=json,path=$p.json" > $p.log 2>&1; echo "$flavor $cell: guidellm exit $?"
curl -sG "http://framework:8080/metrics" --data-urlencode "model=$model" --data-urlencode autoload=false > $p.after.metrics; test -s $p.after.metrics || echo "$flavor $cell: after-snapshot empty"
done
```

Every other step's cells, with `model`, `tok`, and `cells` set from llama-strix-rocm's
[Order](llama-strix-rocm.md#order). Step 2's:

```sh
export GUIDELLM__SPEC__BACKEND__TARGET="http://framework:8080"; flavor=vulkan; o=.state/vllm-strix/$flavor
model=ggml-org/gemma-4-E4B-it-GGUF:Q8_0; tok=google/gemma-4-E4B-it; cells=(shape-a:e4b-q8-shape-a audio-a:e4b-q8-audio-a audio-b:e4b-q8-audio-b)
for c in "${cells[@]}"; do scenario=${c%%:*}; cell=${c#*:}; p=$o/$cell
for i in 1 2 3 4 5; do curl -sG "http://framework:8080/metrics" --data-urlencode "model=$model" --data-urlencode autoload=false > $p.before.metrics; test -s $p.before.metrics && break; sleep 2; done
if ! test -s $p.before.metrics; then echo "$flavor $cell: before-snapshot empty after 5 tries; not run"; break; fi
grep "^llamacpp:requests_processing" $p.before.metrics
MISE_ENV=bench mise exec -- guidellm run -c bench/$scenario.yaml --backend "kind=openai_http,model=$model" --tokenizer "kind=huggingface_auto,model=$tok" --output "kind=json,path=$p.json" > $p.log 2>&1; echo "$flavor $cell: guidellm exit $?"
curl -sG "http://framework:8080/metrics" --data-urlencode "model=$model" --data-urlencode autoload=false > $p.after.metrics; test -s $p.after.metrics || echo "$flavor $cell: after-snapshot empty"
done
```

A cell whose guidellm exits non-zero, or whose requests all error, is read from its log and the
router's (`docker logs --tail 50 llama` on framework); a cell the build can't serve is marked
unsupported in the results, with that reason, and the step's next cell runs. llama.cpp's cells
took at most 128 s in llama-strix-rocm, so they run without `timeout`, as there.

### Reading the figures

On the laptop, with `engine` set to `vllm` or `vulkan` and `cell` to each cell's, such as `vllm`
and `anchor-a`. The client figures are llama-strix-rocm's read-out
([Reading the figures](llama-strix-rocm.md#reading-the-figures)), the same for both engines, since
GuideLLM's JSON is, with `f=.state/vllm-strix/$engine/$cell.json`; its embedding read-out takes
`granite-embed.json` from the same directory.

The server figures differ by engine. llama.cpp's are llama-strix-rocm's `awk`, with
`p=.state/vllm-strix/vulkan/$cell`. vLLM's are vllm-gb10-container's
([Reading the figures](vllm-gb10-container.md#reading-the-figures)), which drop vLLM's labels and
add up each name's series: the prompt tokens vLLM computed, less those from its prefix cache, and
the generation rate per request ([Method](vllm-gb10-container.md#method)):

```sh
p=.state/vllm-strix/vllm/$cell
awk '!/^#/ { k = $1; sub(/\{.*/, "", k); d[k] += (NR == FNR ? -$2 : $2) } END { m = "vllm:"; n = d[m "request_decode_time_seconds_count"]; p = d[m "prompt_tokens_total"]; c = d[m "prompt_tokens_cached_total"]; g = d[m "generation_tokens_total"]; printf "%d requests; prompt %d tokens, %d from the prefix cache, %.1f tok/s; generated %d tokens, %.1f tok/s\n", n, p, c, (p - c) / d[m "request_prefill_time_seconds_sum"], g, (g - n) / d[m "request_decode_time_seconds_sum"] }' $p.before.metrics $p.after.metrics
```

The embedding cell generates nothing, so only its prompt figure applies.

### End state

On framework, after llama.cpp's step 7. `llama` is stopped by hand, as `vllm` was before it, so
`--restart unless-stopped` leaves both stopped at boot; `llama` stays at flavor `vulkan`, b11960.
Then both containers, the router unit, and ports 8000 and 8080, where `ss` prints only its header:

```sh
cd ~/repos/spike-model-engines
docker stop llama >/dev/null
docker ps -a --filter name=vllm --filter name=llama --format "{{.Names}} {{.Image}} {{.Status}}"
docker inspect --format '{{.Config.Image}} {{join .Config.Cmd " "}}' vllm
systemctl is-enabled llama-router; systemctl is-active llama-router
ss -ltn '( sport = :8000 or sport = :8080 )'
```

Both containers read `Exited`, `llama-router` reads `disabled` and `inactive`. `vllm` is left on
step 7's row, granite-embedding-english-r2, which its command shows; `host/engines vllm update`
returns it to the flavor's default row, and this task doesn't run it.

### Run times

Estimated from viability's first start (about 189 s) and anchor A on vLLM (10.0 output tok/s,
25.5 s a request, about 4.5 times llama.cpp's Vulkan latency at b11669), and from
llama-strix-rocm's Vulkan cells ([Results](llama-strix-rocm.md#results)); each run must stay
within 10 minutes.

| Run | Estimate |
|---|---|
| vLLM gpt-oss-120b: timed start | 2 to 4 min (68.82 GiB of weights from a dropped cache, the graphs captured again) |
| vLLM E4B BF16, E4B w4a16, 12B, 31B, 26B-A4B: first start | 2 to 6 min each |
| vLLM E4B BF16, E4B w4a16, 12B, 31B, 26B-A4B: timed start | 1 to 4 min each |
| vLLM granite: first start, timed start | 1 to 2 min, under 1 min |
| vLLM anchors A, B | 3.5 min (8 × 25.5 s), 4 to 8 min |
| vLLM E4B BF16: shape A, ASR A, ASR B | 2 to 4 min, 0.5 to 2 min, 1 to 3 min |
| vLLM E4B QAT w4a16: shape A | 1 to 4 min |
| vLLM 12B: shape A, B | 2 to 6 min, 3 to 8 min |
| vLLM 31B: large A, B | 4 to 8 min, 6 to 10 min |
| vLLM 26B-A4B: shape A, B, vision A, B | 1 to 4 min, 2 to 5 min, 0.5 to 2 min, 1 to 3 min |
| vLLM granite: embeddings | 1.5 min (two 30 s levels and setup) |
| llama.cpp Vulkan: each cold load | under 1 min (gpt-oss-120b's 18.2 s at b11669) |
| llama.cpp Vulkan: each cell | as llama-strix-rocm's Vulkan cells, 0.5 to 2.5 min |

vLLM's 13 starts total about 25 to 50 minutes and its 17 cells about 35 to 75; llama.cpp's 7
loads, warm-ups, and paths about 5 minutes and its 15 cells about 21. With the steps between, the
session runs about 1.5 to 2.5 hours. The 31B's cells on vLLM are the runs nearest the cap, should
vLLM's w4a16 decode trail llama.cpp's as its gpt-oss-120b does; `timeout 10m` holds every vLLM
cell to it. Every start is held to it by its poll, and one past it escalates.

## Results

(to fill)

### Served

(to fill) Each vLLM cell beside its same-session llama.cpp Vulkan cell: output tok/s, TTFT, and
ITL, per cell.

### Cold start and footprint

(to fill) vLLM's first and timed start per row, and llama.cpp's cold load per model, each with
MemAvailable, GTT, and VRAM in use before and after, beside the memory each engine logged.

### Anchors

(to fill) vLLM's A and B on gpt-oss-120b beside llama.cpp's at b11960, and b11960's beside
v0.7.0's 45.13 and 77.67 tok/s ([Anchors](llama-strix-rocm.md#anchors)).

### Unsupported cells

(to fill)

### Network path and model state

(to fill)
