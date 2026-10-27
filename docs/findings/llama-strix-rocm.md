# llama.cpp on the Framework, ROCm against Vulkan

Recorded on 2026-10-27, on framework, from the steps and cells the task's brief agreed
(context/goals, `llama-strix-rocm`). The same llama.cpp build runs in ggml's ROCm image and in
ggml's Vulkan image, one after the other in one `llama` container in one session, so only the
backend differs ([Comparisons](../../context/README.md#rules)); llama-bench also runs from ggml's
native Vulkan prebuilt, to separate the image's Vulkan driver from the host's. It is evidence 1, 2,
and 3 for llama.cpp on Strix Halo ([The evidence](../../context/README.md#the-evidence)): install
and guides, raw speed, TTFT, footprint, and cold load by shape, and the quantization pair. It
records what was measured and the verdict the brief's rule gives; strix-native and vllm-strix act
on it.

The session ran each step on framework over Tailscale SSH, and each GuideLLM cell from the laptop,
from the clone at TBD on `llama-strix-rocm`.

## Host stack

Recorded on 2026-10-27 at 16:50 (-04:00), after the architect's `omarchy update` and the GTT
ceiling's reboot ([Setup](../engines/llama.cpp/setup.md#framework-in-a-container)).

| Item | framework |
|---|---|
| OS | Omarchy 4.0.6-1 (Arch Linux) |
| Kernel | 7.2.8-9-omarchy |
| Mesa, `vulkan-radeon` | 26.2.5-1, 26.2.5-1 |
| linux-firmware | 20260916-1 |
| Docker | 29.9.2 |
| ROCm | host `rocm-core` 7.2.4-1, unused by the container; the image's own ROCm 7.2.1 |
| GTT ceiling | 112 GiB: ttm `pages_limit` 29360128, amdgpu `gttsize` 114688, `mem_info_gtt_total` 120259084288 |
| Firmware carve-out (VRAM) | 512 MiB |
| RAM | 125.1 GiB |
| Firewall | ufw with ufw-docker, and the two route rules for 8080 and 8000 on `tailscale0` ([Setup](../engines/llama.cpp/setup.md#4-route-the-ports-through-ufw)) |
| Reboot pending | no (`uname -r` matches `pacman -Q linux-omarchy`) |

spike-model-hosting's `llama-router` is stopped and disabled for the task
([Setup](../engines/llama.cpp/setup.md#5-stop-the-router)), so nothing else serves on the host.

## Engine versions

Every backend runs llama.cpp v0.7.0 (b11669, commit 620d2225c), and the servers report `/props`
build_info `b11669-620d2225c`.

| Backend | Release | Build | Source | Devices |
|---|---|---|---|---|
| ROCm, container | v0.7.0 | b11669 | `ghcr.io/ggml-org/llama.cpp:server-rocm-b11669` (`host/llama.env`, flavor `rocm`), and for llama-bench `full-rocm-b11669` | `--device /dev/kfd --device /dev/dri` |
| Vulkan, container | v0.7.0 | b11669 | `ghcr.io/ggml-org/llama.cpp:server-vulkan-b11669` (flavor `vulkan`), and for llama-bench `full-vulkan-b11669`; Ubuntu's Mesa 26.0 in the image | `--device /dev/dri` |
| Vulkan, native prebuilt, llama-bench only | v0.7.0 | b11669 | ggml's `llama-b11669-bin-ubuntu-vulkan-x64.tar.gz`, unpacked in `~/llama.cpp/b11669-vulkan` ([Models](../engines/llama.cpp/models.md#on-the-framework)); the host's Mesa 26.2.5 | the host's own |

Both containers serve the same preset (`host/llama-preset/models.ini`), model store
(`/srv/models`), and router flags (`--no-models-autoload`), on port 8080 of the tailnet address;
`host/engines llama update` switches the flavor ([Update](../engines/llama.cpp/update.md#switching-the-flavor)).

The load tool is GuideLLM 0.8.1 on the laptop, in the spike's bench environment
(`mise.bench.toml`: Python 3.14.10, with the `vision` and `audio` extras). llama-bench is the
build's own ([llama-bench](../engines/llama.cpp/setup.md#llama-bench)).

## Viability

Slice 1's first walk of ggml's ROCm image, and slice 2's of the Vulkan image and the native
prebuilt, before any cell here ([Setup](../engines/llama.cpp/setup.md#9-prove-the-pinned-image-runs-on-the-gpu)):

- `full-rocm-b11669 --bench --list-devices` listed one ROCm device, the whole GTT ceiling:

  ```text
  ROCm0: Radeon 8060S Graphics (114688 MiB, 114683 MiB free)
  ```

  and its log named the target:

  ```text
  Device 0: Radeon 8060S Graphics, gfx1151 (0x1151), VMM: no, Wave Size: 32, VRAM: 114688 MiB
  ```

- `server-rocm-b11669` loaded gpt-oss-120b in 16 s with `offloaded 37/37 layers to GPU` and
  `ROCm0 model buffer size = 59851.68 MiB`; `mem_info_gtt_used` read 64627249152 bytes with it
  loaded.
- `server-vulkan-b11669` found
  `Vulkan0 : Radeon 8060S Graphics (RADV STRIX_HALO) (115200 MiB, 114498 MiB free)`, the GTT
  ceiling plus the 512 MiB carve-out, and loaded gpt-oss-120b with 37/37 layers offloaded and
  `Vulkan0 model buffer size = 59851.64 MiB`.
- The native prebuilt's `llama-bench --list-devices` found
  `Vulkan0: AMD Radeon 8060S Graphics (RADV STRIX_HALO) (115200 MiB, ...)`.

Slice 1 also served a warm anchor A on ROCm from the laptop: 8 of 8 requests, 42.7 output tok/s,
TTFT p95 679 ms, ITL median 20.9 ms, the path direct at 2 ms. That run was a viability check only,
not a comparison cell: its before-snapshot of `/metrics` came back empty, so its server figures
include the warm-up, and no Vulkan cell ran beside it. The anchors below rerun it on both flavors.

## Method

The session runs the steps in this order, each printed before it runs:

1. llama-bench, on framework, with no engine holding a model.
2. ROCm: on framework the `llama` container started at flavor `rocm`, then per model, the cold
   load on framework and the warm-up and cells on the laptop. Step 1's load, gpt-oss-120b, is
   the flavor's timed cold load.
3. The switch to `vulkan`, on framework, then the same steps as 2, in the same order.
4. The switch back to `rocm`, and the end state, on framework.

Each block below is self-contained, so it runs as one `ssh framework` command or at one prompt.
Blocks marked "on framework" run from `~/repos/spike-model-engines` and set it themselves; blocks
marked "on the laptop" run from the laptop's clone. `.state/` is untracked on both. The run cap is
10 minutes; [Run times](#run-times) gives each run's estimate.

### Once, before the first step

On framework, the clone brought to the branch's head, and the commit it is at:

```sh
cd ~/repos/spike-model-engines && git pull --ff-only && git log --oneline -1
```

On the laptop, the same, and the directories the cells write to, one per flavor:

```sh
git pull --ff-only && git log --oneline -1
mkdir -p .state/strix/rocm .state/strix/vulkan
```

### llama-bench

On framework. The `llama` container is stopped first, so no engine holds GPU memory; GTT and VRAM
in use then read the desktop's own share. The output goes to `.state/strix/bench/` in the
Framework's clone, the table to `<name>.md` and llama-bench's log to `<name>.err` beside it:

```sh
cd ~/repos/spike-model-engines && mkdir -p .state/strix/bench
docker stop llama >/dev/null; docker ps -a --filter name=llama --format "{{.Names}} {{.Image}} {{.Status}}"
echo "gtt_used $(cat /sys/class/drm/card1/device/mem_info_gtt_used) vram_used $(cat /sys/class/drm/card1/device/mem_info_vram_used)"
```

pp512 and tg256, at depths 0 and 8192, 5 repetitions, every layer on the GPU, and flash attention
on (`-fa 1`), as gb10-1's runs ([llama-gb10-native](llama-gb10-native.md#llama-bench)), in three
backends: `full-rocm-b11669` with `/dev/kfd` and `/dev/dri`, `full-vulkan-b11669` with `/dev/dri`
alone, and the native prebuilt. The full image's entrypoint runs llama-bench with `--bench`, as
`jaime`. `m` names the model's GGUF by its snapshot in the store, written out, not listed.

A run at depth 8192 fills the context with 8192 tokens before each repetition of each test, so it
runs 10 prefills of 8192 tokens; gpt-oss-120b's at an unknown Strix Halo prefill rate could near
the cap. So each backend, model, and depth is its own run, timed, and under `timeout 10m`, which
ends a run at the cap (`docker run` passes the signal to llama-bench); each prints its
llama-bench's exit status after it, 124 when the cap ended it. gpt-oss-120b MXFP4 first:

```sh
cd ~/repos/spike-model-engines
m=/srv/models/models--ggml-org--gpt-oss-120b-GGUF/snapshots/7200b74bea78b0a2964ef9f3897eefa401e890ff/gpt-oss-120b-MXFP4.gguf; mn=gptoss; o=.state/strix/bench
for d in 0 8192; do
echo "== rocm $mn d$d"; time timeout 10m docker run --rm --device /dev/kfd --device /dev/dri --user "$(id -u):$(id -g)" --volume /srv/models:/srv/models ghcr.io/ggml-org/llama.cpp:full-rocm-b11669 --bench -m "$m" -p 512 -n 256 -d $d -r 5 -ngl 99 -fa 1 -o md 2>$o/rocm-$mn-d$d.err | tee $o/rocm-$mn-d$d.md; echo "exit ${PIPESTATUS[0]}"
echo "== vulkan $mn d$d"; time timeout 10m docker run --rm --device /dev/dri --user "$(id -u):$(id -g)" --volume /srv/models:/srv/models ghcr.io/ggml-org/llama.cpp:full-vulkan-b11669 --bench -m "$m" -p 512 -n 256 -d $d -r 5 -ngl 99 -fa 1 -o md 2>$o/vulkan-$mn-d$d.err | tee $o/vulkan-$mn-d$d.md; echo "exit ${PIPESTATUS[0]}"
echo "== native $mn d$d"; time timeout 10m ~/llama.cpp/b11669-vulkan/llama-bench -m "$m" -p 512 -n 256 -d $d -r 5 -ngl 99 -fa 1 -o md 2>$o/native-$mn-d$d.err | tee $o/native-$mn-d$d.md; echo "exit ${PIPESTATUS[0]}"
done
```

Then gemma-4-26B-A4B QAT Q4_0, the same block with its own `m` and `mn`:

```sh
cd ~/repos/spike-model-engines
m=/srv/models/models--google--gemma-4-26B-A4B-it-qat-q4_0-gguf/snapshots/d1c082be9cf3c8a514acf63b8761f4b41935842e/gemma-4-26B_q4_0-it.gguf; mn=gemma26b; o=.state/strix/bench
for d in 0 8192; do
echo "== rocm $mn d$d"; time timeout 10m docker run --rm --device /dev/kfd --device /dev/dri --user "$(id -u):$(id -g)" --volume /srv/models:/srv/models ghcr.io/ggml-org/llama.cpp:full-rocm-b11669 --bench -m "$m" -p 512 -n 256 -d $d -r 5 -ngl 99 -fa 1 -o md 2>$o/rocm-$mn-d$d.err | tee $o/rocm-$mn-d$d.md; echo "exit ${PIPESTATUS[0]}"
echo "== vulkan $mn d$d"; time timeout 10m docker run --rm --device /dev/dri --user "$(id -u):$(id -g)" --volume /srv/models:/srv/models ghcr.io/ggml-org/llama.cpp:full-vulkan-b11669 --bench -m "$m" -p 512 -n 256 -d $d -r 5 -ngl 99 -fa 1 -o md 2>$o/vulkan-$mn-d$d.err | tee $o/vulkan-$mn-d$d.md; echo "exit ${PIPESTATUS[0]}"
echo "== native $mn d$d"; time timeout 10m ~/llama.cpp/b11669-vulkan/llama-bench -m "$m" -p 512 -n 256 -d $d -r 5 -ngl 99 -fa 1 -o md 2>$o/native-$mn-d$d.err | tee $o/native-$mn-d$d.md; echo "exit ${PIPESTATUS[0]}"
done
```

A table with only its header means llama-bench couldn't load the model; its `.err` says why. A run
the cap ends (exit 124) runs again as two, the pp512 alone (`-p 512 -n 0`) and the tg256 alone
(`-p 0 -n 256`), each in the same form with `-pp` or `-tg` added to its name, and the finding says
so.

### ROCm: the container started

On framework, after llama-bench: the container, still at flavor `rocm`, started with no model
loaded and waited for, then its image and devices:

```sh
cd ~/repos/spike-model-engines
docker start llama >/dev/null && until curl -fs "http://$(tailscale ip -4):8080/health" >/dev/null; do sleep 1; done
docker ps --filter name=llama --format "{{.Names}} {{.Image}} {{.Status}}"
docker inspect --format '{{.Config.Image}} {{range .HostConfig.Devices}}{{.PathOnHost}} {{end}}' llama
```

### Per model: the cold load and its footprint

On framework, with `model` set to the step's model and `prev` to the previous step's (empty at
step 1, on a router just started), as bench-gb10-container ran it
([Per model: the cold load and its footprint](bench-gb10-container.md#per-model-the-cold-load-and-its-footprint)),
with Arch's `/usr/bin/sysctl`, and the GPU's memory in use, GTT and VRAM, beside MemAvailable,
before and after. The block unloads the previous model and waits until it is unloaded, drops the
page cache, showing the cache before and after, times the load from the request to the first
`/models` poll that shows it `loaded` (or failed), polled every half second, then reads the
buffers the engine logged since the load began. Step 1's, gpt-oss-120b:

```sh
cd ~/repos/spike-model-engines
model=ggml-org/gpt-oss-120b-GGUF:MXFP4
prev=
[[ -z $prev ]] || curl -s -X POST "http://$(tailscale ip -4):8080/models/unload" -H "Content-Type: application/json" -d "{\"model\": \"$prev\"}"
[[ -z $prev ]] || until [[ $(curl -s "http://$(tailscale ip -4):8080/models" | jq -r --arg m "$prev" '.data[] | select(.id == $m) | .status.value') == unloaded ]]; do sleep 1; done
echo; grep ^Cached /proc/meminfo; sync && sudo -n /usr/bin/sysctl vm.drop_caches=3; grep ^Cached /proc/meminfo
grep ^MemAvailable /proc/meminfo; echo "gtt_used $(cat /sys/class/drm/card1/device/mem_info_gtt_used) vram_used $(cat /sys/class/drm/card1/device/mem_info_vram_used)"
since=$(date -u +%Y-%m-%dT%H:%M:%SZ); start=$(date +%s.%N)
curl -s -X POST "http://$(tailscale ip -4):8080/models/load" -H "Content-Type: application/json" -d "{\"model\": \"$model\"}"; echo
while :; do s=$(curl -s "http://$(tailscale ip -4):8080/models" | jq -r --arg m "$model" '.data[] | select(.id == $m) | if .status.failed then "failed" else .status.value end'); [[ $s == loaded || $s == failed ]] && break; sleep 0.5; done
echo "$s after $(awk -v a="$start" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1f", b - a }') s"
grep ^MemAvailable /proc/meminfo; echo "gtt_used $(cat /sys/class/drm/card1/device/mem_info_gtt_used) vram_used $(cat /sys/class/drm/card1/device/mem_info_vram_used)"
docker logs --since "$since" llama 2>&1 | grep -E "offloaded|buffer size|model size|flash_attn|Flash Attention|n_ctx |n_slots"
```

Each later step, the same block with its `model` and `prev` from [Order](#order). The preset logs
at verbosity 4, so the buffer sizes appear ([Models](../engines/llama.cpp/models.md#the-preset)).
`offloaded N/N layers to GPU` with N the model's whole count, and no CPU model buffer beyond a
small one for the token embeddings, shows every layer on the GPU.

### Per model: the build and the warm-up

On the laptop, with `flavor`, `model`, and `tok` set to the step's values, as bench-gb10-container
ran it ([Per model: the build and the warm-up](bench-gb10-container.md#per-model-the-build-and-the-warm-up)):
the time and the network path, the build the model runs, then one warm-up request, the API page's
chat completion. Step 1's:

```sh
flavor=rocm; model=ggml-org/gpt-oss-120b-GGUF:MXFP4; tok=openai/gpt-oss-120b
date -u +%FT%TZ; tailscale ping -c 3 framework
curl -sG "http://framework:8080/props" --data-urlencode "model=$model" --data-urlencode autoload=false | jq -r .build_info
curl -s "http://framework:8080/v1/chat/completions" -H "Content-Type: application/json" -d "{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one sentence.\"}]}" | jq '.choices[0].message.content'
```

For granite-embedding-english-r2, step 7, the last line is the embedding instead:

```sh
curl -s "http://framework:8080/v1/embeddings" -H "Content-Type: application/json" -d "{\"model\": \"$model\", \"input\": \"Say hello in one sentence.\"}" | jq -c '{model, usage}'
```

### Per cell

On the laptop. Each cell's files go to `.state/strix/<flavor>/`: its JSON, its GuideLLM log, and
the `/metrics` snapshots before and after it. The JSON's path is given on the command line
(`--output`), which replaces the scenario's, so no `bench/*.yaml` is edited or copied. Before each
cell the before-snapshot must be non-empty: the block fetches it up to five times, 2 s apart, and
when it is still empty prints so and runs no more of the step's cells. Its
`llamacpp:requests_processing` line prints, 0 when nothing else is using the model.

The anchors, step 1, run their own scenarios, which name their model and tokenizer, as
llama-gb10-native ran them ([Per cell](llama-gb10-native.md#per-cell)), A then B:

```sh
export GUIDELLM__SPEC__BACKEND__TARGET="http://framework:8080"; flavor=rocm; model=ggml-org/gpt-oss-120b-GGUF:MXFP4; o=.state/strix/$flavor
for cell in anchor-a anchor-b; do p=$o/$cell
for i in 1 2 3 4 5; do curl -sG "http://framework:8080/metrics" --data-urlencode "model=$model" --data-urlencode autoload=false > $p.before.metrics; test -s $p.before.metrics && break; sleep 2; done
if ! test -s $p.before.metrics; then echo "$flavor $cell: before-snapshot empty after 5 tries; not run"; break; fi
grep "^llamacpp:requests_processing" $p.before.metrics
MISE_ENV=bench mise exec -- guidellm run -c bench/$cell.yaml --output "kind=json,path=$p.json" > $p.log 2>&1; echo "$flavor $cell: guidellm exit $?"
curl -sG "http://framework:8080/metrics" --data-urlencode "model=$model" --data-urlencode autoload=false > $p.after.metrics; test -s $p.after.metrics || echo "$flavor $cell: after-snapshot empty"
done
```

Every other step's cells, with `model`, `tok`, and `cells` set from [Order](#order), each cell a
`scenario:cell` pair, the model and tokenizer given on the command line, as bench-gb10-container
ran them ([Per cell](bench-gb10-container.md#per-cell)). Step 2's:

```sh
export GUIDELLM__SPEC__BACKEND__TARGET="http://framework:8080"; flavor=rocm; o=.state/strix/$flavor
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
router's (`docker logs --tail 50 llama` on framework); a cell the flavor can't serve is marked
unsupported in the results, with that reason, and the step's next cell runs.

### Order

One model loaded at a time, each unloaded before the next, in the same order on both flavors.
Each row's values set the cold load's `model` and `prev`, and the laptop's `model`, `tok`, and
`cells`:

| Step | `model` | `tok` | `cells` |
|---|---|---|---|
| 1 | `ggml-org/gpt-oss-120b-GGUF:MXFP4` | `openai/gpt-oss-120b` | the anchors' block: `anchor-a`, `anchor-b` |
| 2 | `ggml-org/gemma-4-E4B-it-GGUF:Q8_0` | `google/gemma-4-E4B-it` | `(shape-a:e4b-q8-shape-a audio-a:e4b-q8-audio-a audio-b:e4b-q8-audio-b)` |
| 3 | `google/gemma-4-E4B-it-qat-q4_0-gguf:Q4_0` | `google/gemma-4-E4B-it` | `(shape-a:e4b-q4-shape-a)` |
| 4 | `google/gemma-4-12B-it-qat-q4_0-gguf:Q4_0` | `google/gemma-4-12B-it-qat-w4a16-ct` | `(shape-a:12b-shape-a shape-b:12b-shape-b)` |
| 5 | `google/gemma-4-31B-it-qat-q4_0-gguf:Q4_0` | `nvidia/Gemma-4-31B-IT-NVFP4` | `(shape-large-a:31b-large-a shape-large-b:31b-large-b)` |
| 6 | `google/gemma-4-26B-A4B-it-qat-q4_0-gguf:Q4_0` | `nvidia/Gemma-4-26B-A4B-NVFP4` | `(shape-a:26b-shape-a shape-b:26b-shape-b vision-a:26b-vision-a vision-b:26b-vision-b)` |
| 7 | `mrutkows/granite-embedding-english-r2-GGUF:BF16` | `ibm-granite/granite-embedding-english-r2` | `(embed:granite-embed)` |

`prev` at each step is the row above's `model`, empty at step 1. The scenarios' loads are
bench-gb10-container's ([The cells](bench-gb10-container.md#the-cells)): A and B 512 in and 256
out, 1 × 8 and 4 × 32; the 31B's halved, 1 × 4 and 4 × 16; vision one synthetic 720p JPEG and 200
text tokens, 64 out; ASR one LibriSpeech clip with the card's prompt, up to 256 out; embeddings 512
tokens at 1 then 16 streams, 30 s each. The tokenizers are its own, so the prompts match gb10-1's.
E4B Q8_0 and E4B QAT Q4_0 run at one stream only (shape A), the quantization pair.

### Model state

Each model is loaded fresh, from a dropped page cache, and warmed with one request before its
first cell; its cells then run in the order above. Every cell so starts from a model that has
served one request and the cells before it, the same on both flavors.

### Vulkan: the switch

On framework, after ROCm's step 7. The update replaces the container with one on
`server-vulkan-b11669` and `/dev/dri` alone; it pulls nothing, since the image is staged, and
ROCm's loaded model goes with the old container. Then wait for the router, and read its image and
devices:

```sh
cd ~/repos/spike-model-engines
LLAMA_FLAVOR=vulkan host/engines llama update 2>&1 | tail -3
until curl -fs "http://$(tailscale ip -4):8080/health" >/dev/null; do sleep 1; done
docker ps --filter name=llama --format "{{.Names}} {{.Image}} {{.Status}}"
docker inspect --format '{{.Config.Image}} {{range .HostConfig.Devices}}{{.PathOnHost}} {{end}}' llama
```

Then steps 1 to 7 again, every block as ROCm's with `flavor=vulkan` in place of `flavor=rocm` on
the laptop; the cold-load blocks on framework are unchanged. Step 1's load, with `prev` empty on
the router just started, is Vulkan's timed cold load.

### Reading the figures

bench-gb10-container's read-outs ([Reading the figures](bench-gb10-container.md#reading-the-figures)),
on the laptop, with `flavor` and `cell` set to each cell's, such as `rocm` and `anchor-a`. The
client figures, then each benchmark's duration, then the server's, the counters differenced
between the two snapshots:

```sh
f=.state/strix/$flavor/$cell.json
jq -c '.metadata as $v | .benchmarks[] | .metrics as $m | {streams: .config.strategy.streams, duration_s: (.duration|floor), requests: $m.request_totals, prompt_tokens: $m.prompt_token_count.successful.median, output_tokens: $m.output_token_count.successful.median, output_tok_s: ($m.output_tokens_per_second.successful.mean|.*10|round/10), ttft_ms: ($m.time_to_first_token_ms.successful | {median: (.median|round), p95: (.percentiles.p95|round)}), itl_ms: ($m.inter_token_latency_ms.successful | {median: (.median*100|round/100), p95: (.percentiles.p95*100|round/100)}), latency_s: ($m.request_latency.successful | {median: (.median*100|round/100), p95: (.percentiles.p95*100|round/100)}), audio_s_per_s: $m.audio.seconds.input_per_second.successful.mean}' "$f"
jq '.benchmarks[].duration' "$f"
p=.state/strix/$flavor/$cell
awk '{ d[$1] += (NR == FNR ? -$2 : $2) } END { m = "llamacpp:"; printf "prompt %d tokens, %.1f tok/s; generated %d tokens, %.1f tok/s\n", d[m "prompt_tokens_total"], d[m "prompt_tokens_total"] / d[m "prompt_seconds_total"], d[m "tokens_predicted_total"], d[m "tokens_predicted_total"] / d[m "tokens_predicted_seconds_total"] }' $p.before.metrics $p.after.metrics
```

The embedding cell generates no tokens, so the `awk` divides by zero there. Its requests per
second, input tokens per second, and latency in milliseconds, and its server's prompt counters:

```sh
jq -c '.benchmarks[] | {s: .config.strategy.streams, rps: (.metrics.requests_per_second.successful.mean*10|round/10), in_tok_s: (.metrics.prompt_tokens_per_second.successful.mean|round), lat_ms: (.metrics.request_latency.successful | {median: (.median*1000|round), p95: (.percentiles.p95*1000|round)})}' .state/strix/$flavor/granite-embed.json
diff <(grep -v '^#' .state/strix/$flavor/granite-embed.before.metrics) <(grep -v '^#' .state/strix/$flavor/granite-embed.after.metrics) | grep "prompt_"
```

The anchors' served output tok/s, the verdict's figure, is each anchor's `output_tok_s`; ROCm
against Vulkan is ROCm's less Vulkan's, over Vulkan's.

### End state

On framework, after Vulkan's step 7. The flavor goes back to `rocm`, the default the guides
install, then the container is stopped by hand, so `--restart unless-stopped` leaves it stopped at
boot. Then the container, the router unit, and port 8080, where `ss` prints only its header:

```sh
cd ~/repos/spike-model-engines
host/engines llama update 2>&1 | tail -3
docker stop llama >/dev/null
docker ps -a --filter name=llama --format "{{.Names}} {{.Image}} {{.Status}}"
systemctl is-enabled llama-router; systemctl is-active llama-router
ss -ltn 'sport = :8080'
```

### Run times

Estimated from slice 1's ROCm anchor A (42.7 output tok/s at 1 stream) and gb10-1's cells
([Run times](bench-gb10-container.md#run-times)), whose decode rates the Framework's similar
memory bandwidth should approach; each run must stay within 10 minutes.

| Run | Estimate, per flavor or backend |
|---|---|
| llama-bench, gpt-oss-120b, depth 0 | 1 to 1.5 min |
| llama-bench, gpt-oss-120b, depth 8192 | 4 to 8 min: 10 prefills of 8192 tokens at 200 to 400 tok/s, the slowest the run nearest the cap |
| llama-bench, gemma-4-26B-A4B, depth 0 | 0.5 to 1 min |
| llama-bench, gemma-4-26B-A4B, depth 8192 | 2 to 4 min |
| Anchors A, B | 1 min, 2.5 min |
| E4B Q8_0: shape A, ASR A, ASR B | 1 min, 0.5 min, 1 min |
| E4B QAT Q4_0: shape A | 1 min |
| 12B: shape A, B | 1.5 min, 2 min |
| 31B: large A, B | 2 min, 2.5 min |
| 26B-A4B: shape A, B, vision A, B | 1 min, 1.5 min, 0.5 min, 1 min |
| granite: embeddings | 1.5 min (two 30 s levels and setup) |
| Each cold load | under 1 min (gpt-oss-120b's 59 GiB from the drive) |

llama-bench's 12 runs total about 25 to 45 minutes; each flavor's 15 cells about 21 minutes, and
its 7 loads, warm-ups, and paths about 5, so about 50 minutes for both. With the switches and the
end state, the session runs about 1.5 to 2 hours. No GuideLLM cell nears the cap; gpt-oss-120b's
llama-bench runs at depth 8192 are the only runs that may, and `timeout 10m` holds them to it.

## Results

To be filled by the session: run on 2026-10-27 on framework, times -04:00 on framework and UTC on
the laptop, from the files each step wrote.

### Raw speed

llama-bench, pp512 and tg256 at depths 0 and 8192, 5 repetitions, `-ngl 99 -fa 1`; tokens per
second, the mean ± the standard deviation, from `.state/strix/bench/` on framework. ROCm against
Vulkan is the ROCm container's against the Vulkan container's.

| Model | Size | Params | Test | ROCm container t/s | Vulkan container t/s | Vulkan native t/s | ROCm against Vulkan |
|---|---|---|---|---|---|---|---|
| gpt-oss 120B MXFP4 MoE | | | pp512 | | | | |
| gpt-oss 120B MXFP4 MoE | | | tg256 | | | | |
| gpt-oss 120B MXFP4 MoE | | | pp512 @ d8192 | | | | |
| gpt-oss 120B MXFP4 MoE | | | tg256 @ d8192 | | | | |
| gemma4 26B.A4B Q4_0 | | | pp512 | | | | |
| gemma4 26B.A4B Q4_0 | | | tg256 | | | | |
| gemma4 26B.A4B Q4_0 | | | pp512 @ d8192 | | | | |
| gemma4 26B.A4B Q4_0 | | | tg256 @ d8192 | | | | |

Each run's real time and exit:

| Run | ROCm container | Vulkan container | Vulkan native |
|---|---|---|---|
| gpt-oss-120b, d0 | | | |
| gpt-oss-120b, d8192 | | | |
| gemma-4-26B-A4B, d0 | | | |
| gemma-4-26B-A4B, d8192 | | | |

### Cold load and footprint

Each load timed from a dropped page cache, from the load request to `loaded`. The footprint is
MemAvailable before less after, and GTT and VRAM in use after less before
(`mem_info_gtt_used`, `mem_info_vram_used`), beside the buffers the engine logged, in MiB, on the
GPU (ROCm0 or Vulkan0) and the host. gpt-oss-120b's rows are the flavors' timed cold loads; the
others are each step's load.

| Flavor | Model | Format | Cache before → after drop GiB | MemAvailable before → after GiB | Footprint GiB | GTT used before → after GiB | VRAM used before → after MiB | Offloaded | Weights MiB (logged, GPU + host) | KV cache MiB (logged) | Compute MiB (logged, GPU + host) | Projector MiB (logged) | Load s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ROCm | gpt-oss-120b | MXFP4 | | | | | | | | | | — | |
| Vulkan | gpt-oss-120b | MXFP4 | | | | | | | | | | — | |
| ROCm | gemma-4-E4B | Q8_0 | | | | | | | | | | | |
| Vulkan | gemma-4-E4B | Q8_0 | | | | | | | | | | | |
| ROCm | gemma-4-E4B | QAT Q4_0 | | | | | | | | | | | |
| Vulkan | gemma-4-E4B | QAT Q4_0 | | | | | | | | | | | |
| ROCm | gemma-4-12B | QAT Q4_0 | | | | | | | | | | | |
| Vulkan | gemma-4-12B | QAT Q4_0 | | | | | | | | | | | |
| ROCm | gemma-4-31B | QAT Q4_0 | | | | | | | | | | | |
| Vulkan | gemma-4-31B | QAT Q4_0 | | | | | | | | | | | |
| ROCm | gemma-4-26B-A4B | QAT Q4_0 | | | | | | | | | | | |
| Vulkan | gemma-4-26B-A4B | QAT Q4_0 | | | | | | | | | | | |
| ROCm | granite-embedding-english-r2 | BF16 | | | | | | | | — | | — | |
| Vulkan | granite-embedding-english-r2 | BF16 | | | | | | | | — | | — | |

### Anchors

gpt-oss-120b MXFP4, 4 slots, 512 in and 256 out, from a warm start.

| Cell | Flavor | Completed | Errored | Duration s | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | ITL p95 ms | Latency median s | Latency p95 s | Server prompt | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | ROCm | | | | | | | | | | | | |
| A | Vulkan | | | | | | | | | | | | |
| B | ROCm | | | | | | | | | | | | |
| B | Vulkan | | | | | | | | | | | | |

| Anchor | ROCm output tok/s | Vulkan output tok/s | ROCm against Vulkan |
|---|---|---|---|
| A | | | |
| B | | | |

### Shapes

| Shape | Model | Format | Cell | Streams × requests | Flavor | Completed | Errored | Duration s | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | Latency median s | Latency p95 s | Server prompt tok/s | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| dense small | gemma-4-E4B | Q8_0 | A | 1 × 8 | ROCm | | | | | | | | | | | |
| dense small | gemma-4-E4B | Q8_0 | A | 1 × 8 | Vulkan | | | | | | | | | | | |
| dense mid | gemma-4-12B | QAT Q4_0 | A | 1 × 8 | ROCm | | | | | | | | | | | |
| dense mid | gemma-4-12B | QAT Q4_0 | A | 1 × 8 | Vulkan | | | | | | | | | | | |
| dense mid | gemma-4-12B | QAT Q4_0 | B | 4 × 32 | ROCm | | | | | | | | | | | |
| dense mid | gemma-4-12B | QAT Q4_0 | B | 4 × 32 | Vulkan | | | | | | | | | | | |
| dense large | gemma-4-31B | QAT Q4_0 | A | 1 × 4 | ROCm | | | | | | | | | | | |
| dense large | gemma-4-31B | QAT Q4_0 | A | 1 × 4 | Vulkan | | | | | | | | | | | |
| dense large | gemma-4-31B | QAT Q4_0 | B | 4 × 16 | ROCm | | | | | | | | | | | |
| dense large | gemma-4-31B | QAT Q4_0 | B | 4 × 16 | Vulkan | | | | | | | | | | | |
| MoE | gemma-4-26B-A4B | QAT Q4_0 | A | 1 × 8 | ROCm | | | | | | | | | | | |
| MoE | gemma-4-26B-A4B | QAT Q4_0 | A | 1 × 8 | Vulkan | | | | | | | | | | | |
| MoE | gemma-4-26B-A4B | QAT Q4_0 | B | 4 × 32 | ROCm | | | | | | | | | | | |
| MoE | gemma-4-26B-A4B | QAT Q4_0 | B | 4 × 32 | Vulkan | | | | | | | | | | | |
| MoE | gpt-oss-120b | MXFP4 | A, B | | both | the anchors, above | | | | | | | | | | |

### Quantization pair

gemma-4-E4B, single stream, 1 × 8 (shape A). The footprint is from
[Cold load and footprint](#cold-load-and-footprint).

| Flavor | Format | Output tok/s | TTFT median ms | ITL median ms | Latency median s | Server gen tok/s | Footprint GiB |
|---|---|---|---|---|---|---|---|
| ROCm | Q8_0 | | | | | | |
| ROCm | QAT Q4_0 | | | | | | |
| Vulkan | Q8_0 | | | | | | |
| Vulkan | QAT Q4_0 | | | | | | |

### Vision

gemma-4-26B-A4B, one synthetic 720p JPEG and 200 text tokens a request, 64 out:

| Flavor | Cell | Streams × requests | Completed | Errored | Prompt tokens median | Output tok/s | TTFT median ms | TTFT p95 ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|---|
| ROCm | A | 1 × 8 | | | | | | | | |
| ROCm | B | 4 × 32 | | | | | | | | |
| Vulkan | A | 1 × 8 | | | | | | | | |
| Vulkan | B | 4 × 32 | | | | | | | | |

### Embeddings

granite-embedding-english-r2 BF16, 512 tokens a request, 30 s a level:

| Flavor | Streams | Completed | Incomplete | Errored | Requests/s | Input tok/s | Prompt tokens median | Latency median ms | Latency p95 ms |
|---|---|---|---|---|---|---|---|---|---|
| ROCm | 1 | | | | | | | | |
| ROCm | 16 | | | | | | | | |
| Vulkan | 1 | | | | | | | | |
| Vulkan | 16 | | | | | | | | |

### ASR

gemma-4-E4B Q8_0's audio through chat, one LibriSpeech clip a request with the card's prompt:

| Flavor | Cell | Streams × requests | Completed | Errored | Audio s/s | Output tokens median | TTFT median ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|
| ROCm | A | 1 × 8 | | | | | | | |
| ROCm | B | 4 × 32 | | | | | | | |
| Vulkan | A | 1 × 8 | | | | | | | |
| Vulkan | B | 4 × 32 | | | | | | | |

### Unsupported cells

Each cell a flavor couldn't serve, with its reason, or none.

| Flavor | Cell | Reason |
|---|---|---|
| | | |

### Network path, build, and model state, per flavor

| Flavor | Image and devices | Model | `tailscale ping` | Build | `requests_processing` before each cell |
|---|---|---|---|---|---|
| ROCm | | each model, steps 1 to 7 | | | |
| Vulkan | | each model, steps 1 to 7 | | | |

### framework's end state

The end state's read: the `llama` container's image and status, `llama-router`'s enabled and
active state, and port 8080.

## Verdict

The brief's rule: ROCm leads only when both anchors' served output tok/s, A's and B's, beat
Vulkan's by more than 3%. A split result, one anchor ahead and the other not, or one within 3%,
is no lead.

What follows from it: when ROCm leads, strix-native runs, and vllm-strix compares with ROCm.
Otherwise strix-native drops, and vllm-strix compares with Vulkan: the leading backend when Vulkan
beats ROCm on both anchors by more than 3%, and the comparison backend when nothing leads.

The verdict, from [Anchors](#anchors): to be stated by the session.
