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
laptop, in the architect's view, from the clone at 2ca4f48 on `vllm-strix` on both machines,
printing each block before it runs; the audio probe ran at 3118182, the commit that adds its
Dockerfile. Each block ran as written, the per-row blocks through wrapper scripts in the session's
scratch directory that ran them in order over `ssh framework` and on the laptop.

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
  most of the host's GPU memory; docker stop vllm stops it`. The other side, checked by the
  session at 20:15Z from the clone at 6e09aae, after the walkthrough: with `llama` running,
  `host/engines vllm install` and `update` both exited 1 with `llama is running, and one engine
  serves per host at a time, since each reserves most of the host's GPU memory; docker stop llama
  stops it`. `llama` was then stopped again.

## Staging

Every model the rows name was staged through hf on framework before the first step
([Models](../engines/vllm/models.md#on-the-framework)): gpt-oss-120b earlier the same day, at
snapshot `b5c939de8f754692c1647ca79fbf85e8c1e70f8a`, and the six Gemma 4 and granite rows from
about 15:50 to 16:55Z, all unauthenticated, since the architect's `hf` login came after they had
finished. The session read the staging back at 17:58Z, over `ssh framework`, with the guide's
checks (`tail -qn 1 ~/prestage/*.log`, `find /srv/models -name "*.incomplete"`, `du -shL`):

- every log in `~/prestage` ended `exit 0`, none failed: `google--gemma-4-E4B-it`,
  `-E4B-it-qat-w4a16-ct`, `-12B-it-qat-w4a16-ct`, `-31B-it-qat-w4a16-ct`, `-26B-A4B-it`,
  `ibm-granite--granite-embedding-english-r2`, and `openai--gpt-oss-120b`;
- `find` printed nothing: no `*.incomplete` file was left in the store;
- both images were present, `server-vulkan-b11960` and `vllm-openai-rocm:v0.32.0`;
- the root drive had 540G free.

The store's size for each model, following its links (`du -shL`):

| Model | Size |
|---|---|
| openai/gpt-oss-120b | 61G |
| google/gemma-4-26B-A4B-it | 49G |
| google/gemma-4-E4B-it | 15G |
| google/gemma-4-E4B-it-qat-w4a16-ct | 11G |
| google/gemma-4-12B-it-qat-w4a16-ct | 9.6G |
| google/gemma-4-31B-it-qat-w4a16-ct | 22G |
| ibm-granite/granite-embedding-english-r2 | 288M |

## Method

The session runs the steps in this order, each printed before it runs:

1. vLLM, on framework and the laptop, one row at a time, in the order of
   [vLLM's order](#vllms-order): per row, its first start, its timed start, then its warm-up and
   cells.
2. llama.cpp's Vulkan set at b11960, after `vllm` is stopped by hand: the `llama` container
   started, then llama-strix-rocm's steps 1 to 7.
3. The audio probe, the goal record's escalation 1: E4B BF16's audio cells on a derived image
   ([The audio probe's blocks](#the-audio-probes-blocks)).
4. The end state, on framework.

Each block below is self-contained, so it runs as one `ssh framework` command or at one prompt.
Blocks marked "on framework" run from `~/repos/spike-model-engines` and set it themselves; blocks
marked "on the laptop" run from the laptop's clone. `.state/` is untracked on both. The run cap is
10 minutes; [Run times](#run-times) gives each run's time.

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

granite's cell ended at the cap once. Its first run served 30 s at 1 stream, every request 200,
then GuideLLM stalled at the change from 1 stream to 16 and wrote no JSON, so `timeout 10m` ended
it (exit 124). The server's log shows it idle from 19:00:56Z, so the stall was GuideLLM's, not a
server fault. Its log and snapshots are kept as `granite-embed.run1.*`, and the same block ran once
more, which completed ([A note on the granite stall](#a-note-on-the-granite-stall)).

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

### The audio probe's blocks

The goal record's escalation 1, after llama.cpp's step 7: vLLM's official ROCm image ships no
audio decoder, so E4B BF16's audio cells are unsupported on it
([Unsupported cells](#unsupported-cells)), and this step serves the same row from an image derived
from it, `host/vllm-rocm-audio/Dockerfile`, which 3118182 adds:

```dockerfile
FROM vllm/vllm-openai-rocm:v0.32.0@sha256:14f6a575e1fb0a580b0f633c09e06f648709d60405b85f6a7ff3f80d49f39905
RUN uv pip install --system av==19.0.2 soundfile==0.14.0 soxr==1.1.0
```

On framework, the clone brought to the commit; the image built, without root, and listed; its
three modules imported; `llama` stopped, so one engine serves; then the E4B BF16 row served from
the derived image through the suite's own `vllm_run`, with the row's exact flags, as a second
container, `vllm-audio`, which leaves `vllm` and its command as step 7 left them. The block waits
for `/health` as the first start's does:

```sh
cd ~/repos/spike-model-engines && git pull -q --ff-only && git log --oneline -1
docker build -q -t spike-model-engines/vllm-openai-rocm-audio:v0.32.0 host/vllm-rocm-audio
docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}' spike-model-engines/vllm-openai-rocm-audio
docker run --rm --entrypoint python3 spike-model-engines/vllm-openai-rocm-audio:v0.32.0 -c "import av, soundfile, soxr; print('av', av.__version__, 'soundfile', soundfile.__version__, 'soxr', soxr.__version__)"
docker stop llama >/dev/null; docker ps -a --filter name=llama --filter name=vllm --format "{{.Names}} {{.Image}} {{.Status}}"
( source host/vllm.sh; export VLLM_FLAVOR=rocm VLLM_MODEL=gemma-4-E4B-it; vllm_flavor; vllm_row; vllm_preflight; VLLM_CONTAINER=vllm-audio vllm_run spike-model-engines/vllm-openai-rocm-audio:v0.32.0 >/dev/null )
docker inspect --format '{{.Config.Image}} {{join .Config.Cmd " "}}' vllm-audio
cap=$((SECONDS + 600)); until s=$(curl -s -o /dev/null -w '%{http_code}' "http://$(tailscale ip -4):8000/health"); [[ $s == 200 ]] || ((SECONDS >= cap)); do sleep 5; done
echo "health $s"; date -u +%FT%TZ; docker inspect --format '{{.State.Status}}, restarts {{.RestartCount}}' vllm-audio
```

On the laptop, the Gemma rows' warm-up ([the version and the warm-up](#vllm-per-row-the-version-and-the-warm-up))
with `model=google/gemma-4-E4B-it`, then the audio cells, the per-cell block with the files written
to their own directory, `.state/vllm-strix/vllm-audio/`:

```sh
export GUIDELLM__SPEC__BACKEND__TARGET="http://framework:8000"; o=.state/vllm-strix/vllm-audio
model=google/gemma-4-E4B-it; tok=google/gemma-4-E4B-it; cells=(audio-a:e4b-bf16-audio-a audio-b:e4b-bf16-audio-b)
for c in "${cells[@]}"; do scenario=${c%%:*}; cell=${c#*:}; p=$o/$cell
for i in 1 2 3 4 5; do curl -s "http://framework:8000/metrics" > $p.before.metrics; test -s $p.before.metrics && break; sleep 2; done
if ! test -s $p.before.metrics; then echo "vllm $cell: before-snapshot empty after 5 tries; not run"; break; fi
grep "^vllm:num_requests_running" $p.before.metrics
MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/$scenario.yaml --backend "kind=openai_http,model=$model" --tokenizer "kind=huggingface_auto,model=$tok" --output "kind=json,path=$p.json" > $p.log 2>&1; echo "vllm $cell: guidellm exit $?"
curl -s "http://framework:8000/metrics" > $p.after.metrics; test -s $p.after.metrics || echo "vllm $cell: after-snapshot empty"
done
```

The figures are read as every vLLM cell's, with `p=.state/vllm-strix/vllm-audio/$cell`. Then, on
framework, `vllm-audio` is removed with `docker rm -f vllm-audio`, and the derived image kept; `docker rmi
spike-model-engines/vllm-openai-rocm-audio:v0.32.0` removes it. The suite, the flavor and the pin
are unchanged: whether the suite carries the derived image is the answer task's.

### End state

On framework, after the audio probe. `llama` is stopped by hand, as `vllm` was before it, so
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

Both containers read `Exited`, `llama-router` reads `disabled` and `inactive`. Run at about 19:37Z,
it found `vllm` on step 7's row, granite-embedding-english-r2, which its command showed; the
walkthrough's `host/engines vllm update` then moved it back to the flavor's default row
([Walkthrough](#walkthrough)), where [framework's end state](#frameworks-end-state) records it.

### Run times

The plan estimated each run from viability's first start (about 189 s) and anchor A on vLLM (10.0
output tok/s, 25.5 s a request), and from llama-strix-rocm's Vulkan cells
([Results](llama-strix-rocm.md#results)), each held to 10 minutes. The actuals: each vLLM start
from its container's StartedAt to `Application startup complete.`, each llama.cpp load from the
load request to `loaded`, and each cell from its before-snapshot to its after-snapshot, by the
laptop's file times.

| Run | Actual |
|---|---|
| vLLM gpt-oss-120b: timed start | 160.9 s |
| vLLM E4B BF16, E4B w4a16, 12B, 31B, 26B-A4B: first start | 166.6, 163.5, 168.7, 163.3, 167.3 s |
| vLLM E4B BF16, E4B w4a16, 12B, 31B, 26B-A4B: timed start | 97.6, 70.0, 84.5, 93.9, 73.9 s |
| vLLM granite: first start, timed start | 32.8 s, 21.2 s |
| vLLM anchors A, B | 216 s, 533 s |
| vLLM E4B BF16: shape A, ASR A, ASR B | 107 s, 9 s, 10 s (every ASR request errored at once) |
| vLLM E4B QAT w4a16: shape A | 56 s |
| vLLM 12B: shape A, B | 110 s, 162 s |
| vLLM 31B: large A, B | 128 s, 203 s |
| vLLM 26B-A4B: shape A, B, vision A, B | 107 s, 196 s, 41 s, 70 s |
| vLLM granite: embeddings | 600 s, the cap (exit 124); the rerun 78 s |
| llama.cpp Vulkan: each cold load | 0.6 to 18.2 s |
| llama.cpp Vulkan: each cell | 18 to 138 s |
| The audio probe: ASR A, B | 25 s, 23 s |

vLLM's steps ran from step 1's timed start at 17:59:20Z to granite's rerun, which ended at
19:11:48Z, about 72 minutes; llama.cpp's Vulkan set from its container's start at about 19:12Z to
granite's cell, which ended at 19:32:07Z, about 20 minutes; and the probe from 3118182's commit at
19:33:08Z to its last cell, which ended at 19:36:49Z. The end state read at 19:37Z, about 1 hour
38 minutes after step 1's start, within the 1.5 to 2.5 hours estimated. No start neared the cap.
vLLM's anchor B, at 533 s (its benchmark 518.56 s), was the run nearest it beside granite's
stalled first run, and longer than its 4 to 8 minute estimate; the 31B's cells, estimated nearest
the cap, took 128 and 203 s.

## Results

Run on 2026-10-28 on framework and the laptop, times UTC, from the files each step wrote, as
[Run times](#run-times) spans them. The client figures are GuideLLM's successful requests, read
with llama-strix-rocm's `jq` ([Reading the figures](#reading-the-figures)); the server figures are
each engine's read-out, vLLM's vllm-gb10-container's `awk` and llama.cpp's llama-strix-rocm's.
vLLM's server generation rate is per request, since it sums each request's decode time
([vllm-gb10-container's Results](vllm-gb10-container.md#results)). Every cell's before-snapshot
and after-snapshot was non-empty, `vllm:num_requests_running` and `llamacpp:requests_processing`
read 0 before every cell, and every guidellm exited 0 but vLLM granite's first run
([A note on the granite stall](#a-note-on-the-granite-stall)).

### Served

Each vLLM cell beside its same-session llama.cpp Vulkan b11960 cell, paired as
[vLLM's order](#vllms-order) pairs them. Every text request carried 528 prompt tokens and
generated 256 on both engines, but gpt-oss-120b's, which carried 579. The server prompt is the
tokens counted, those vLLM took from its prefix cache, and the rate of the rest.

**Anchors**, gpt-oss-120b (vLLM's MXFP4 checkpoint, llama.cpp's MXFP4 GGUF):

| Cell | Streams × requests | Engine | Completed | Errored | Duration s | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | ITL p95 ms | Latency median s | Latency p95 s | Server prompt | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | 1 × 8 | vLLM | 8 | 0 | 203.67 | 10.1 | 794 | 798 | 96.70 | 96.71 | 25.45 | 25.46 | 4,632 tokens, 512 cached, 1037.1 tok/s | 10.2 |
| A | 1 × 8 | llama.cpp | 8 | 0 | 45.53 | 45.0 | 637 | 702 | 19.78 | 19.91 | 5.67 | 5.75 | 4,138 tokens, 917.4 tok/s | 50.1 |
| B | 4 × 32 | vLLM | 32 | 0 | 518.56 | 15.8 | 2278 | 2486 | 245.97 | 252.79 | 64.46 | 66.95 | 18,528 tokens, 6,144 cached, 417.8 tok/s | 4.0 |
| B | 4 × 32 | llama.cpp | 32 | 0 | 106.67 | 76.8 | 2145 | 2166 | 45.56 | 46.38 | 13.61 | 13.99 | 12,448 tokens, 1011.5 tok/s | 21.8 |

**Shapes**, gemma-4-12B and gemma-4-26B-A4B at A and B. vLLM serves the 12B as Google's QAT w4a16
and the 26B-A4B as BF16, llama.cpp both as Google's QAT Q4_0:

| Model | Cell | Streams × requests | Engine | Format | Completed | Errored | Duration s | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | ITL p95 ms | Latency median s | Latency p95 s | Server prompt | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| gemma-4-12B | A | 1 × 8 | vLLM | QAT w4a16 | 8 | 0 | 95.39 | 21.5 | 823 | 1135 | 43.34 | 43.39 | 11.88 | 12.19 | 4,224 tokens, 0 cached, 724.9 tok/s | 22.8 |
| gemma-4-12B | A | 1 × 8 | llama.cpp | QAT Q4_0 | 8 | 0 | 79.63 | 25.7 | 739 | 773 | 36.10 | 36.36 | 9.95 | 10.01 | 4,173 tokens, 888.7 tok/s | 27.5 |
| gemma-4-12B | B | 4 × 32 | vLLM | QAT w4a16 | 32 | 0 | 148.86 | 55.0 | 2748 | 2861 | 64.13 | 64.17 | 19.10 | 19.21 | 16,896 tokens, 4,096 cached, 240.2 tok/s | 15.1 |
| gemma-4-12B | B | 4 × 32 | llama.cpp | QAT Q4_0 | 32 | 0 | 110.08 | 74.4 | 2441 | 2465 | 46.10 | 46.95 | 14.20 | 14.42 | 12,448 tokens, 954.7 tok/s | 21.5 |
| gemma-4-26B-A4B | A | 1 × 8 | vLLM | BF16 | 8 | 0 | 94.62 | 21.6 | 482 | 483 | 44.47 | 44.50 | 11.82 | 11.83 | 4,224 tokens, 0 cached, 1543.6 tok/s | 22.2 |
| gemma-4-26B-A4B | A | 1 × 8 | llama.cpp | QAT Q4_0 | 8 | 0 | 34.78 | 58.9 | 408 | 482 | 15.36 | 15.42 | 4.33 | 4.40 | 4,173 tokens, 1533.1 tok/s | 64.5 |
| gemma-4-26B-A4B | B | 4 × 32 | vLLM | BF16 | 32 | 0 | 183.55 | 44.6 | 1286 | 1504 | 85.32 | 85.69 | 23.07 | 23.25 | 16,896 tokens, 4,096 cached, 528.1 tok/s | 11.5 |
| gemma-4-26B-A4B | B | 4 × 32 | llama.cpp | QAT Q4_0 | 32 | 0 | 66.77 | 122.7 | 1346 | 1375 | 28.25 | 28.78 | 8.55 | 8.69 | 12,448 tokens, 1739.6 tok/s | 35.1 |

**Quantization pair**, gemma-4-E4B at shape A, 1 × 8: E4B BF16 with Q8_0, and E4B QAT w4a16 with
QAT Q4_0:

| Pair | Engine | Format | Completed | Errored | Duration s | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | ITL p95 ms | Latency median s | Latency p95 s | Server prompt | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| higher precision | vLLM | BF16 | 8 | 0 | 94.37 | 21.7 | 436 | 439 | 44.52 | 44.56 | 11.79 | 11.80 | 4,224 tokens, 0 cached, 1794.7 tok/s | 22.2 |
| higher precision | llama.cpp | Q8_0 | 8 | 0 | 55.26 | 37.1 | 365 | 445 | 25.55 | 25.66 | 6.90 | 6.97 | 4,159 tokens, 1820.9 tok/s | 38.8 |
| QAT 4-bit | vLLM | QAT w4a16 | 8 | 0 | 43.20 | 47.4 | 351 | 802 | 19.55 | 19.58 | 5.34 | 5.79 | 4,224 tokens, 0 cached, 1548.1 tok/s | 50.5 |
| QAT 4-bit | llama.cpp | QAT Q4_0 | 8 | 0 | 35.24 | 58.1 | 311 | 383 | 15.98 | 16.04 | 4.39 | 4.47 | 4,173 tokens, 2055.1 tok/s | 62.0 |

**Large**, gemma-4-31B halved, 1 × 4 and 4 × 16 (vLLM QAT w4a16, llama.cpp QAT Q4_0):

| Cell | Streams × requests | Engine | Completed | Errored | Duration s | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | ITL p95 ms | Latency median s | Latency p95 s | Server prompt | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | 1 × 4 | vLLM | 4 | 0 | 115.43 | 8.9 | 2235 | 2263 | 104.36 | 104.37 | 28.85 | 28.88 | 2,112 tokens, 0 cached, 274.5 tok/s | 9.5 |
| A | 1 × 4 | llama.cpp | 4 | 0 | 95.11 | 10.8 | 1900 | 1905 | 85.79 | 85.87 | 23.77 | 23.79 | 2,105 tokens, 340.6 tok/s | 11.6 |
| B | 4 × 16 | vLLM | 16 | 0 | 190.12 | 21.5 | 7235 | 7255 | 163.93 | 164.02 | 49.05 | 49.06 | 8,448 tokens, 2,048 cached, 93.4 tok/s | 5.9 |
| B | 4 × 16 | llama.cpp | 16 | 0 | 125.54 | 32.6 | 6237 | 6346 | 103.66 | 103.83 | 32.69 | 32.79 | 6,224 tokens, 365.9 tok/s | 9.6 |

**Vision**, gemma-4-26B-A4B (vLLM BF16, llama.cpp QAT Q4_0), one synthetic 720p JPEG and 200 text
tokens a request, 64 out:

| Cell | Streams × requests | Engine | Completed | Errored | Prompt tokens median | Duration s | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | ITL p95 ms | Latency median s | Latency p95 s | Server prompt | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | 1 × 8 | vLLM | 8 | 0 | 479 | 28.18 | 18.2 | 551 | 1979 | 43.47 | 43.49 | 3.29 | 4.72 | 3,831 tokens, 0 cached, 634.4 tok/s | 23.0 |
| A | 1 × 8 | llama.cpp | 8 | 0 | 623 | 20.56 | 24.9 | 1599 | 1873 | 14.78 | 14.85 | 2.53 | 2.80 | 4,896 tokens, 401.2 tok/s | 65.2 |
| B | 4 × 32 | vLLM | 32 | 0 | 479 | 56.30 | 36.4 | 1961 | 1987 | 83.26 | 92.40 | 7.18 | 7.23 | 15,325 tokens, 3,584 cached, 243.6 tok/s | 11.8 |
| B | 4 × 32 | llama.cpp | 32 | 0 | 623 | 49.58 | 41.3 | 5839 | 5882 | 26.90 | 27.49 | 7.50 | 7.60 | 14,728 tokens, 432.0 tok/s | 36.1 |

**ASR**, gemma-4-E4B's audio through chat (vLLM BF16 on the official image, llama.cpp Q8_0), one
LibriSpeech clip a request with the card's prompt. vLLM's rows are on the official image; the same
row's cells on the derived image are [The audio probe](#the-audio-probe)'s:

| Cell | Streams × requests | Engine | Completed | Errored | Duration s | Audio s/s | Output tokens median | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | ITL p95 ms | Latency median s | Latency p95 s | Server prompt | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | 1 × 8 | vLLM | 0 | 8 | 0.12 | — | — | — | — | — | — | — | — | — | none counted | — |
| A | 1 × 8 | llama.cpp | 8 | 0 | 8.50 | 11.31 | 20 | 27.8 | 250 | 665 | 25.08 | 25.67 | 0.75 | 2.77 | 2,406 tokens, 1045.4 tok/s | 39.9 |
| B | 4 × 32 | vLLM | 0 | 32 | 0.13 | — | — | — | — | — | — | — | — | — | none counted | — |
| B | 4 × 32 | llama.cpp | 32 | 0 | 12.39 | 20.24 | 17 | 53.9 | 429 | 771 | 52.75 | 74.36 | 1.17 | 3.22 | 4,561 tokens, 561.0 tok/s | 20.2 |

**Embeddings**, granite-embedding-english-r2 BF16 on both engines, 512 tokens a request, 30 s a
level; vLLM's from its rerun:

| Engine | Streams | Completed | Incomplete | Errored | Requests/s | Input tok/s | Prompt tokens median | Latency median ms | Latency p95 ms |
|---|---|---|---|---|---|---|---|---|---|
| vLLM | 1 | 2367 | 0 | 0 | 78.9 | 40,459 | 513 | 11 | 12 |
| vLLM | 16 | 6468 | 8 | 0 | 215.3 | 110,466 | 513 | 72 | 74 |
| llama.cpp | 1 | 722 | 0 | 0 | 24.0 | 12,329 | 513 | 37 | 40 |
| llama.cpp | 16 | 1216 | 16 | 0 | 40.5 | 20,794 | 513 | 387 | 397 |

- **Output tok/s.** vLLM's is lower than llama.cpp's in every generative cell: 22.4% of
  llama.cpp's at anchor A and 20.6% at B; 58.5% at E4B BF16 against Q8_0 and 81.6% at E4B QAT
  w4a16 against QAT Q4_0; 83.7% and 73.9% at the 12B's A and B; 82.4% and 66.0% at the 31B's A and
  B; 36.7% and 36.3% at the 26B-A4B's A and B, BF16 against QAT Q4_0; and 73.1% and 88.1% at
  vision A and B. ITL follows it: vLLM's median is higher in every cell.
- **TTFT.** vLLM's median is higher at every text cell but the 26B-A4B's B, 1286 against 1346 ms.
  At vision it is lower: 551 against 1599 ms at A and 1961 against 5839 ms at B.
- **Vision's prompt counts differ by engine.** vLLM counted 479 prompt tokens a request, llama.cpp
  623, from the same scenario and tokenizer; the counts are each server's, and this task didn't
  look further.
- **Embeddings.** vLLM served 78.9 requests/s at 1 stream against llama.cpp's 24.0, and 215.3
  against 40.5 at 16. The incomplete requests, 8 on vLLM and 16 on llama.cpp, were in flight when
  the 16-stream level's 30 s ended. vLLM's server counted 8,835 finished requests, 4,532,355 prompt
  tokens, 513 each, none from the prefix cache, 17,720.2 tok/s by its per-request prefill time;
  llama.cpp's 1,002,402 prompt tokens, 513 for each of its 1,954 completed and incomplete
  requests, in 53.21 s, 18,837.0 tok/s. Both engines' `awk` divides by zero at the generation
  figure, since the cell generates nothing, so vLLM's prompt figure is its read-out's prompt
  expression alone.
- **The prefix cache.** vLLM took 4,096 of each 4-stream text cell's 16,896 prompt tokens from
  its cache (2,048 of the 31B's B's 8,448, 3,584 of vision B's 15,325), and 512 of anchor A's
  4,632 and 6,144 of anchor B's 18,528; llama.cpp computed 4,138 of A's and 12,448 of B's, as in
  llama-strix-rocm.

### Cold start and footprint

vLLM's starts per row. The first start fills the compile cache from the page cache as it was; the
timed start runs from a dropped page cache with the compile cache warm. gpt-oss-120b's first start
is [Viability](#viability)'s.

| Step | Row | First start s | First: init engine s (compilation s) | Compile cache before → after | Timed start s | Timed: `/health` 200 after s | Timed: init engine s (compilation s) | Timed: graph capture s |
|---|---|---|---|---|---|---|---|---|
| 1 | gpt-oss-120b | about 189 | 139.86 (11.81) | absent → 333M | 160.9 | 161.4 | 125.96 (0.11) | 61 + 22 |
| 2 | E4B BF16 | 166.6 | 118.39 (55.95) | 456M → 710M | 97.6 | 98.1 | 55.56 (0.22) | 6 + 1 |
| 3 | E4B QAT w4a16 | 163.5 | 121.37 (58.94) | 767M → 963M | 70.0 | 70.3 | 26.03 (0.22) | 1 + 1 |
| 4 | 12B QAT w4a16 | 168.7 | 115.19 (51.06) | 966M → 1.1G | 84.5 | 84.7 | 36.44 (0.15) | 7 + 1 |
| 5 | 31B QAT w4a16 | 163.3 | 115.12 (43.68) | 1.2G → 1.3G | 93.9 | 94.2 | 43.92 (0.17) | 7 + 2 |
| 6 | 26B-A4B BF16 | 167.3 | 126.69 (49.11) | 1.3G → 1.5G | 73.9 | 74.4 | 34.55 (0.16) | 5 + 1 |
| 7 | granite BF16 | 32.8 | 9.09 (6.00) | 1.5G → 1.5G | 21.2 | 21.6 | 3.07 (0.08) | 1 |

The memory at each timed start: what vLLM logged, then the page cache dropped, and MemAvailable,
GTT, and VRAM in use before and after (`mem_info_gtt_used`, `mem_info_vram_used`):

| Row | Weights GiB, load s | Consumed GiB (weights + non-torch) | KV cache GiB | KV cache tokens (× 8192) | Cache before → after drop GiB | MemAvailable before → after GiB | GTT used before → after GiB | VRAM used before → after MiB |
|---|---|---|---|---|---|---|---|---|
| gpt-oss-120b | 68.82, 14.9 | 69.2 | 19.42 | 372,709 (45.50) | 25.75 → 0.24 | 118.11 → 23.53 | 0.26 → 89.83 | 425.48 → 440.74 |
| E4B BF16 | 15.08, 5.9 | 15.41 | 73.48 | 1,993,132 (243.30) | 24.74 → 0.14 | 118.93 → 21.37 | 0.26 → 90.05 | 425.48 → 427.14 |
| E4B QAT w4a16 | 11.07, 8.1 | 11.54 | 77.38 | 2,098,860 (256.21) | 23.35 → 0.14 | 118.56 → 20.73 | 0.26 → 90.04 | 425.48 → 427.21 |
| 12B QAT w4a16 | 8.3, 12.9 | 9.0 | 80.12 | 333,869 (40.76) | 22.60 → 0.14 | 118.42 → 21.23 | 0.26 → 90.23 | 425.48 → 427.18 |
| 31B QAT w4a16 | 19.89, 28.0 | 20.36 | 68.34 | 107,108 (13.07) | 23.35 → 0.13 | 118.98 → 21.88 | 0.26 → 89.87 | 425.48 → 428.32 |
| 26B-A4B BF16 | 48.54, 17.0 | 49.12 | 39.78 | 249,371 (30.44) | 25.83 → 0.12 | 118.48 → 21.46 | 0.26 → 90.09 | 425.48 → 485.37 |
| granite BF16 | 0.29, 2.3 | not logged | not logged | not logged | 23.61 → 0.14 | 118.55 → 114.40 | 0.26 → 0.85 | 425.48 → 425.86 |

- **vLLM saw the whole GTT ceiling.** Every start of every generative row logged `Free memory on
  device (112.0/112.0 GiB) on startup` and `Desired GPU memory utilization is (0.8, 89.6 GiB)`:
  0.80 of 112.0 GiB, the GTT ceiling's 120259084288 bytes, as `rocminfo` read the pools
  ([Viability](#viability)). GTT in use after each generative start was 89.04 to 90.23 GiB, 0.2 to
  0.6 GiB above the 89.6 reserved at the timed starts, and MemAvailable 20.73 to 23.93 GiB, at
  every row, whatever its weights: the KV cache takes what the weights leave of the 89.6 GiB.
  granite, run by the pooling runner, logged no free-memory, KV cache, or reservation line, and
  left MemAvailable at 114.40 GiB after its timed start.
- **The first starts' figures.** Their weights loaded in 5.9, 8.0, 12.8, 28.0, 17.0, and 2.3
  s, and their KV caches matched the timed starts' within 0.05 GiB: 1,993,146, 2,098,873, 333,678
  (80.07 GiB), 107,108, and 249,375 tokens. gpt-oss-120b's first start logged 18.63 GiB and
  357,622 tokens. Their memory before and after, read as at the timed starts but with the page
  cache as it was, not dropped; gpt-oss-120b's is [Viability](#viability)'s:

  | Row | MemAvailable before → after GiB | GTT used before → after GiB | VRAM used before → after MiB |
  |---|---|---|---|
  | gpt-oss-120b | 116.49 → 23.93 | 0.23 → 89.04 | 468.35 → 495.67 |
  | E4B BF16 | 117.09 → 22.11 | 0.26 → 90.05 | 425.48 → 446.90 |
  | E4B QAT w4a16 | 117.02 → 21.32 | 0.26 → 90.04 | 425.48 → 433.38 |
  | 12B QAT w4a16 | 116.82 → 21.05 | 0.26 → 90.19 | 425.48 → 427.45 |
  | 31B QAT w4a16 | 116.91 → 21.82 | 0.26 → 89.87 | 425.48 → 443.66 |
  | 26B-A4B BF16 | 117.66 → 23.91 | 0.26 → 90.09 | 425.48 → 471.34 |
  | granite BF16 | 117.16 → 114.31 | 0.26 → 0.89 | 425.48 → 425.84 |
- **The warm compile cache shortens the start.** Each Gemma row's first start compiled for 43.68
  to 58.94 s; its timed start, from a dropped page cache, for 0.15 to 0.22 s, and took 70.0 to
  97.6 s against 163.3 to 168.7. gpt-oss-120b's timed start took 160.9 s, and its two graph
  captures 61 and 22 s, as at its first start (61 and 23).
- **Compile cache and graph memory.** The compile cache grew from 333M after viability to 1.5G
  after granite. Each Gemma row's graphs took 0.17 to 0.20 GiB and 0.25 to 0.28 GiB, granite's
  0.07, and gpt-oss-120b's 0.69 and 0.68.

llama.cpp's cold load per model, at b11960, from a dropped page cache, from the load request to
`loaded`; gpt-oss-120b's is the timed cold load on a router just started. The columns are
llama-strix-rocm's: the footprint is MemAvailable before less after, beside the buffers the
engine logged in MiB on the GPU (Vulkan0) and the host (Vulkan_Host).

| Model | Format | Cache before → after drop GiB | MemAvailable before → after GiB | Footprint GiB | GTT used before → after GiB | VRAM used before → after MiB | Offloaded | Weights MiB (logged, GPU + host) | KV cache MiB (logged) | Compute MiB (logged, GPU + host) | Projector MiB (logged) | Load s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| gpt-oss-120b | MXFP4 | 3.93 → 0.24 | 118.50 → 56.26 | 62.23 | 0.26 → 60.64 (+60.38) | 425.49 → 427.77 (+2.28) | 37/37 | 59851.64 + 586.82 (output 3.07) | 1152.00 + 108.00 | 98.77 + 31.29 | — | 18.2 |
| gemma-4-E4B | Q8_0 | 55.17 → 0.24 | 118.68 → 107.25 | 11.43 | 0.26 → 9.94 (+9.69) | 425.49 → 426.88 (+1.38) | 43/43 | 4788.10 + 3536.00 (output 4.00) | 512.00 + 160.00 | 131.02 + 50.04 | 533.83; compute 101.27 + 101.19 | 4.2 |
| gemma-4-E4B | QAT Q4_0 | 8.56 → 0.23 | 118.60 → 109.65 | 8.95 | 0.26 → 7.52 (+7.26) | 425.49 → 426.86 (+1.37) | 43/43 | 2696.04 + 2730.00 (output 4.00) | 512.00 + 160.00 | 131.02 + 50.04 | 945.51; compute 101.27 + 101.19 | 2.6 |
| gemma-4-12B | QAT Q4_0 | 6.23 → 0.23 | 118.58 → 106.83 | 11.75 | 0.26 → 10.31 (+10.06) | 425.49 → 503.66 (+78.17) | 49/49 | 6637.63 + 787.50 (output 4.00) | 512.00 + 1920.00 | 129.52 + 39.54 | 167.00; compute 18.03 + 58.59 | 3.7 |
| gemma-4-31B | QAT Q4_0 | 7.38 → 0.24 | 118.58 → 90.56 | 28.01 | 0.26 → 26.45 (+26.19) | 425.49 → 427.53 (+2.04) | 61/61 | 16818.21 + 1102.50 (output 4.00) | 2560.00 + 4800.00 | 188.02 + 51.54 | 1145.08; compute 150.63 | 7.8 |
| gemma-4-26B-A4B | QAT Q4_0 | 18.08 → 0.23 | 118.60 → 99.51 | 19.08 | 0.26 → 17.45 (+17.20) | 425.49 → 427.06 (+1.57) | 31/31 | 13755.36 + 577.50 (output 4.00) | 640.00 + 1200.00 | 108.52 + 31.54 | 1139.46; compute 150.63 | 5.8 |
| granite-embedding-english-r2 | BF16 | 15.10 → 0.23 | 118.61 → 117.31 | 1.30 | 0.26 → 1.33 (+1.07) | 425.49 → 425.93 (+0.44) | 23/23 | 210.51 + 73.78 (output 3.12) | — | 460.13 + 352.19 | — | 0.6 |

- **b11960 loads and logs as b11669 did.** Every layer of every model was on the GPU. The logged
  buffers match llama-strix-rocm's Vulkan figures exactly, the load times within 0.5 s (gpt-oss-120b
  18.2 s on both, E4B QAT Q4_0 2.6 against 3.1), and the GTT rises within 0.06 GiB. The 12B's VRAM
  rose by 78.17 MiB, against 19.56 at b11669; every other model's by under 2.3 MiB.
- Every generative model logged `n_ctx` 32768, `flash_attn` auto resolved to `Flash Attention
  enabled`, and 4 slots of `n_ctx` 8192; granite `n_ctx` 131072 and 16 slots. The projectors also
  logged CPU compute buffers: 6.77 and 1.58 MiB for E4B's two, 6.75 and 7.32 for the 12B's, and
  6.77 for the 31B's and the 26B-A4B's.
- **The engines' footprints by row.** vLLM's MemAvailable fell by 94.58 to 97.83 GiB at every
  generative row, its reservation; llama.cpp's by each model's size, 8.95 to 62.23 GiB. vLLM's
  timed starts took 70.0 to 160.9 s and llama.cpp's loads 2.6 to 18.2 s; granite 21.2 s against
  0.6 s.

### Anchors

gpt-oss-120b, each anchor's mean output tok/s at full precision from its JSON:

| Anchor | vLLM v0.32.0 | llama.cpp b11960 | llama.cpp v0.7.0 (b11669, [llama-strix-rocm](llama-strix-rocm.md#anchors)) | b11960 against b11669 |
|---|---|---|---|---|
| A | 10.05551 | 44.97903 | 45.12570 | −0.33% |
| B | 15.79771 | 76.79873 | 77.67444 | −1.13% |

- **vLLM against llama.cpp at b11960.** vLLM served 22.4% of llama.cpp's output tok/s at A and
  20.6% at B. Its ITL median was 96.70 against 19.78 ms at A and 245.97 against 45.56 ms at B,
  and its TTFT median 794 against 637 ms and 2278 against 2145 ms. vLLM's row holds 16 sequences
  to llama.cpp's 4 slots, so at B's 4 streams 12 stood idle.
- **b11960 against b11669.** A moved −0.33% and B −1.13%; ITL 19.78 against 19.72 ms and 45.56
  against 44.92, TTFT 637 against 620 ms and 2145 against 2073, and the server computed the same
  4,138 and 12,448 prompt tokens. The earlier findings recorded these movements between runs: on
  this host, llama-strix-rocm's ROCm A moved 0.7% (42.7 against 42.4 tok/s) between its slice 1
  and its session, and recorded no repeat of B; on gb10-1, the same build's anchors moved up to
  1.4% between sessions (llama-gb10-native's A, 49.3 against 50.0; vllm-gb10-native's A' and B',
  1.0 and 1.1%), each read there as run noise. A's −0.33% is within the 0.7% this host recorded;
  B's −1.13% has no repeat on this host to set it against, and is within the 1.0 to 1.4% the GB10
  findings recorded.
- **Viability's anchor A beside step 1's.** Viability's A, at about 15:45Z from vLLM's first
  start, served 10.02 output tok/s (10.0 at one decimal), TTFT median 797 ms, ITL median 97.06 ms,
  latency median 25.55 s; step 1's, at 18:02Z after the timed start, 10.06, 794 ms, 96.70 ms, and
  25.45 s, 0.36% higher.

### Unsupported cells

| Engine | Cell | Reason |
|---|---|---|
| vLLM, official image | E4B BF16 audio A | Every request returned 500, and vLLM logged `ImportError: Please install vllm[audio] for audio support` |
| vLLM, official image | E4B BF16 audio B | The same |

Both guidellm runs exited 0 within 10 s, every request errored with `500 Internal Server Error` on
`/v1/chat/completions`, and the server's counters counted none of them. `vllm/vllm-openai-rocm:v0.32.0`
carries none of torchcodec, ffmpeg, av, soundfile, or soxr, so v0.32.0's audio loader has nothing to
decode with. vLLM's CUDA image decodes through torchcodec 0.17.0+cu130 and ffmpeg, which it ships
([bench-gb10-container's ASR](bench-gb10-container.md#asr)), so its audio cells needed no derived
image. Every other cell, on both engines, was served.

### The audio probe

The goal record's escalation 1, as [its blocks](#the-audio-probes-blocks) ran it after llama.cpp's
step 7.

- **The Dockerfile.** `host/vllm-rocm-audio/Dockerfile`, at 3118182: the official image at the pin
  by its digest, and `uv pip install --system av==19.0.2 soundfile==0.14.0 soxr==1.1.0`, the
  packages of vLLM's audio extra the image lacks, at the versions uv resolved on 2026-10-28.
- **The dry run.** The whole extra, resolved against the official image before the build, in a
  throwaway container (`docker run --rm --entrypoint sh vllm/vllm-openai-rocm:v0.32.0 -c "uv pip
  install --system --dry-run av scipy soundfile soxr \"mistral_common[audio]\""`), resolved 28
  packages and would install only av 19.0.2, soundfile 0.14.0, and soxr 1.1.0, changing nothing
  already in the image.
- **The build.** On framework, without root: `sha256:4d63a2268f06…`, listed as
  `spike-model-engines/vllm-openai-rocm-audio:v0.32.0 4d63a2268f06 47GB`, and the import check
  printed `av 19.0.2 soundfile 0.14.0 soxr 1.1.0`.
- **The run.** `llama` stopped and `vllm` already `Exited`, the suite's `vllm_run` served the E4B
  BF16 row as container `vllm-audio`, whose command read the row's exact flags:
  `google/gemma-4-E4B-it --host 0.0.0.0 --port 8000 --max-num-seqs 4 --max-model-len 8192
  --gpu-memory-utilization 0.80 --kv-cache-dtype bfloat16 --reasoning-parser gemma4
  --enable-auto-tool-choice --tool-call-parser gemma4`. `/health` answered 200 at 19:35:54Z,
  `running, restarts 0`. It was warmed with one request before the cells; that block's console
  wasn't kept, and the server's counters show it: one request, 22 prompt tokens and 3 generated,
  as the official image's E4B warm-up counted. The cells ran from 19:36:01Z to 19:36:49Z.

The probe's cells beside llama.cpp's E4B Q8_0 audio cells, from the same session's Vulkan set:

| Cell | Streams × requests | Engine | Completed | Errored | Duration s | Audio s/s | Output tokens median | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | ITL p95 ms | Latency median s | Latency p95 s | Server prompt | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | 1 × 8 | vLLM, derived image | 8 | 0 | 15.53 | 7.27 | 20 | 14.9 | 334 | 2763 | 43.18 | 44.67 | 1.18 | 4.29 | 2,424 tokens, 0 cached, 470.0 tok/s | 22.4 |
| A | 1 × 8 | llama.cpp | 8 | 0 | 8.50 | 11.31 | 20 | 27.8 | 250 | 665 | 25.08 | 25.67 | 0.75 | 2.77 | 2,406 tokens, 1045.4 tok/s | 39.9 |
| B | 4 × 32 | vLLM, derived image | 31 | 0 | 13.51 | 17.89 | 16 | 47.9 | 313 | 552 | 65.89 | 86.69 | 1.36 | 3.81 | 6,945 tokens, 2,272 cached, 551.9 tok/s | 14.9 |
| B | 4 × 32 | llama.cpp | 32 | 0 | 12.39 | 20.24 | 17 | 53.9 | 429 | 771 | 52.75 | 74.36 | 1.17 | 3.22 | 4,561 tokens, 561.0 tok/s | 20.2 |

- **The derived image served every request.** No request errored, and both guidellm runs exited
  0. vLLM's audio seconds a second were 64.2% of llama.cpp's at A and 88.4% at B.
- **B's JSON holds 31 requests, not 32.** GuideLLM's run ended `completed | successful=31`, and its
  JSON records 31 in all, none errored or incomplete, against the scenario's `max_requests` of 32.
  The server's counters, differenced over the cell, count 32 finished requests
  (`vllm:request_success_total` 9 to 41). This task didn't look further.
- GuideLLM warned on every ASR cell that the benchmark was likely bottlenecked by its data
  generation: its mean generation delay was 40% of the mean TTFT at the probe's A and 21% at its
  B, 81% and 14% at llama.cpp's, and its p95 root dispatch delay 1.05 to 1.17 s on all four.
  Both engines' audio figures carry that client delay, as in llama-strix-rocm.
- **Afterwards.** `vllm-audio` was removed (`docker rm -f vllm-audio` printed `vllm-audio`), and
  the derived image kept; `docker rmi
  spike-model-engines/vllm-openai-rocm-audio:v0.32.0` removes it. The end state's container list,
  filtered on `vllm`, shows no `vllm-audio`.

### Network path and model state

| Engine | Step | Model | Warm-up at | `tailscale ping` | Version or build | Warm-up reply | Reasoning |
|---|---|---|---|---|---|---|---|
| vLLM | 1 | gpt-oss-120b | 18:02:20Z | direct, 1 ms | `/version` `0.32.0` | `"Hello! I hope you’re having a wonderful day."` | reasoned |
| vLLM | 2 | E4B BF16 | 18:20:13Z | direct, 1 ms | `0.32.0` | `"Hello!"` | `null` |
| vLLM | 3 | E4B QAT w4a16 | 18:26:54Z | direct, under 1 ms | `0.32.0` | `"Hello!"` | `null` |
| vLLM | 4 | 12B QAT w4a16 | 18:32:26Z | direct, 1 ms | `0.32.0` | `"Hello."` | reasoned |
| vLLM | 5 | 31B QAT w4a16 | 18:41:43Z | direct, under 1 ms | `0.32.0` | `"Hello!"` | reasoned |
| vLLM | 6 | 26B-A4B BF16 | 18:51:51Z | direct, under 1 ms | `0.32.0` | `"Hello!"` | reasoned |
| vLLM | 7 | granite BF16 | 19:00:06Z | direct, under 1 ms | `0.32.0` | an embedding of 8 prompt tokens | — |
| llama.cpp | 1 | gpt-oss-120b MXFP4 | 19:12:49Z | direct, 1 ms | `/props` `b11960-8642541b2` | `"Hello!"` | — |
| llama.cpp | 2 | E4B Q8_0 | 19:15:53Z | direct, 1 ms | `b11960-8642541b2` | `"Hello there!"` | — |
| llama.cpp | 3 | E4B QAT Q4_0 | 19:17:45Z | direct, 1 ms | `b11960-8642541b2` | `"Hello!"` | — |
| llama.cpp | 4 | 12B QAT Q4_0 | 19:18:45Z | direct, under 1 ms | `b11960-8642541b2` | `"Hello!"` | — |
| llama.cpp | 5 | 31B QAT Q4_0 | 19:22:35Z | direct, under 1 ms | `b11960-8642541b2` | `"Hello!"` | — |
| llama.cpp | 6 | 26B-A4B QAT Q4_0 | 19:26:56Z | direct, 1 ms | `b11960-8642541b2` | `"Hello!"` | — |
| llama.cpp | 7 | granite BF16 | 19:30:49Z | direct, under 1 ms | `b11960-8642541b2` | an embedding of 8 prompt tokens | — |

- **The path was direct on the LAN at every step,** 0 to 1 ms (`tailscale ping` printed `0s` for
  under a millisecond; addresses left out), so TTFT and latency carry no relay's round trip.
- **Every warm start was confirmed.** Each vLLM warm-up returned a reply, `vllm:request_success_total`
  counted it (`stop` 1), and `vllm:num_requests_running` read 0, before every row's first cell;
  `vllm:num_requests_running` and `llamacpp:requests_processing` read 0 before every cell.
- **E4B didn't reason.** Both E4B rows returned `reasoning` `null` to the warm-up, with
  `enable_thinking` true, while the 12B, the 31B, and the 26B-A4B returned reasoning through the
  same `--reasoning-parser gemma4`. The shape cells ask every Gemma 4 row to reason, so E4B's
  cells generated without it.
- The `llama` container served `ghcr.io/ggml-org/llama.cpp:server-vulkan-b11960` with `/dev/dri`
  alone; `vllm` read `Exited (0)` as it started.

### A note on the granite stall

vLLM's first granite cell, at 19:00:08Z, ran its 1-stream level for 30 s, and the server counted
2,272 requests, every one 200 (`finished_reason` `stop`, none errored). GuideLLM then stalled at the
change from 1 stream to 16: it logged no further progress, wrote no JSON, and `timeout 10m` ended
it at 19:10:08Z, exit 124. The server's log shows it idle from 19:00:56Z, with
`vllm:num_requests_running` 0 in the after-snapshot, so the stall was GuideLLM's, not a server
fault. The run's log and snapshots are `.state/vllm-strix/vllm/granite-embed.run1.*`. A single
rerun of the same block, at 19:10:30Z, completed in 78 s and exited 0; its figures are the
Embeddings table's. Its before-snapshot already counted the warm-up and the first run, 2,273
requests, so the differenced server figures are the rerun's alone.

### framework's end state

At 20:15:50Z, after the walkthrough and the vLLM-side refusals ([Viability](#viability)), both
containers read `Exited (0)`. `vllm`, which the walkthrough's `update` had moved back to the
flavor's default row, serves
`vllm/vllm-openai-rocm:v0.32.0 openai/gpt-oss-120b --host 0.0.0.0 --port 8000 --max-num-seqs 16
--max-model-len 8192 --gpu-memory-utilization 0.80 --reasoning-parser openai_gptoss
--enable-auto-tool-choice --tool-call-parser openai`, and `llama` stays at flavor `vulkan`,
`ghcr.io/ggml-org/llama.cpp:server-vulkan-b11960`. Their restart policy is `unless-stopped`, so
neither starts at boot. `llama-router` is disabled and inactive, and `ss` printed only its header:
nothing listens on 8000 or 8080.

The end state's block, run at about 19:37Z after the probe, recorded the state before the
walkthrough: `vllm` then on step 7's row,
`ibm-granite/granite-embedding-english-r2 --host 0.0.0.0 --port 8000 --runner pooling
--max-num-seqs 16 --max-model-len 8192 --gpu-memory-utilization 0.80`, `llama` stopped 2 minutes
before by the probe's block, `llama-router` `disabled` and `inactive`, and nothing on 8000 or
8080.

## Walkthrough

After the audio probe, from about 19:53 to 20:06Z, the architect walked slice 4: vLLM's refusal of
the wrong row, an anchor on each engine, and the handover between them, to see that the method
reproduces in other hands. Each anchor ran after the engine's warm-up, as at the steps, and wrote
under `.state/vllm-strix/walk/`, so the steps' files are unchanged.

| Cell | Completed | Errored | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | ITL p95 ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|
| A, vLLM, the default row | 8 | 0 | 10.0 | 799 | 813 | 97.67 | 97.67 | 25.71 | 25.71 |
| A, llama.cpp b11960, gpt-oss-120b | 7 | 1 | 39.5 | 640 | 671 | 19.75 | 19.82 | 5.69 | 5.71 |

In order:

1. On framework, with `vllm` stopped on step 7's granite row, `host/engines vllm install`
   refused, as the run log records it, with the image names elided: `vllm runs ... with
   ibm-granite/granite-embedding-english-r2, not ... with row gpt-oss-120b ...; engines vllm
   update moves it to the row`. `host/engines vllm update` then moved `vllm` back to the default
   row, and `/health` answered 200 at 19:55:31Z.
2. On the laptop, vLLM's warm-up, then A, from 19:56:52 to 20:00:17Z: 8 of 8, 10.0 output tok/s
   (9.96 by the read-out, the successful mean), TTFT median 799 ms, ITL 97.67 ms.
3. The handover, on framework: `docker stop vllm`, then `docker start llama`. The router runs
   with `--no-models-autoload`, so it served no model until gpt-oss-120b was loaded through its
   `/models/load` ([llama.cpp's Models](../engines/llama.cpp/models.md#loading-a-model)).
4. On the laptop, llama.cpp's warm-up, then A, from 20:04:07 to 20:04:52Z: 7 of 8 successful and
   1 errored, 39.5 output tok/s by the read-out, TTFT median 640 ms, ITL median 19.75 ms.

**The 8th request.** The client dropped its stream at 244 of its 256 tokens: llama.cpp logged
`http client error: Failed to read connection`, then `cancel task`, and GuideLLM had entered its
compile stage before the request finished. GuideLLM's JSON records it as errored, with
`JSONDecodeError('Unterminated string starting at: line 1 column 64 (char 63)')`. It is a
GuideLLM client fault, not the server's. The read-out's successful mean counts the 7 requests'
1,792 output tokens over the run; GuideLLM's total mean, 44.89 tok/s, counts the dropped
request's 244 too, 2,036 tokens.

**Beside slice 3's anchors** ([Anchors](#anchors)). vLLM's A served 9.96 against step 1's 10.06
tok/s, 1.0% lower, with TTFT median 799 against 794 ms and ITL median 97.67 against 96.70 ms.
llama.cpp's A served 39.51 by the read-out against step 1's 44.98, 12.2% lower, because the
read-out leaves out the dropped request's tokens; its total mean, 44.89, is 0.2% below 44.98, its
TTFT median 640 against 637 ms, and its ITL median 19.75 against 19.78 ms.

The figures are the read-out of [Reading the figures](#reading-the-figures), run against the
walkthrough's files, with the total mean and the output tokens beside it:

```sh
for f in .state/vllm-strix/walk/*.json; do
  echo "$f"
  jq -c '.metadata as $v | .benchmarks[] | .metrics as $m | {streams: .config.strategy.streams, duration_s: (.duration|floor), requests: $m.request_totals, prompt_tokens: $m.prompt_token_count.successful.median, output_tokens: $m.output_token_count.successful.median, output_tok_s: ($m.output_tokens_per_second.successful.mean|.*10|round/10), ttft_ms: ($m.time_to_first_token_ms.successful | {median: (.median|round), p95: (.percentiles.p95|round)}), itl_ms: ($m.inter_token_latency_ms.successful | {median: (.median*100|round/100), p95: (.percentiles.p95*100|round/100)}), latency_s: ($m.request_latency.successful | {median: (.median*100|round/100), p95: (.percentiles.p95*100|round/100)}), audio_s_per_s: $m.audio.seconds.input_per_second.successful.mean}' "$f"
  jq -c '.benchmarks[].metrics | {successful_mean: .output_tokens_per_second.successful.mean, total_mean: .output_tokens_per_second.total.mean, output_tokens: (.output_token_count | {successful: .successful.total_sum, errored: .errored.total_sum})}' "$f"
done
```

The walkthrough ended with `vllm` and `llama` both stopped, `vllm` on the default row
([framework's end state](#frameworks-end-state)).
