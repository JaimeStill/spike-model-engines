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
from the clone at ba21982 on `llama-strix-rocm` on both machines; slices 1 and 2 ran at earlier
commits. It ran each per-model block exactly as written, through two wrapper scripts kept in the
laptop's untracked `.state/strix/`: `cold.sh`, the cold-load block verbatim, and `step.sh`, which
runs `cold.sh` over `ssh framework`, then the warm-up and the cells blocks with the step's
variables, and prints a one-line `jq` summary after each cell. Steps 2 to 7 ran in one script per
flavor (`rest.sh`), and their console went to `rest.out` in each flavor's directory.

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

Run on 2026-10-27 on framework, times -04:00 on framework and UTC on the laptop, from the files
each step wrote: llama-bench from 19:04 to 19:11 (-04:00); ROCm's steps from step 1's cold load at
23:11Z to granite's cell, which ended at 23:31Z; Vulkan's from its step 1 warm-up at 23:43:01Z to
granite's cell, which ended at 00:02Z on 2026-10-28; and the end state at 20:02:50 (-04:00). The
client figures are GuideLLM's successful requests. Every cell's before-snapshot and
after-snapshot of `/metrics` was non-empty. No run neared the 10-minute cap: llama-bench's runs
took 21 to 45 s each, depth 8192 included, and the longest cell, the 31B's B on ROCm, 128 s.

### Raw speed

llama-bench, pp512 and tg256 at depths 0 and 8192, 5 repetitions, `-ngl 99 -fa 1`; tokens per
second, the mean ± the standard deviation, from `.state/strix/bench/` on framework. Every run
printed `build: 620d2225c (11669)`. ROCm against Vulkan is the ROCm container's less the Vulkan
container's, over the Vulkan container's; native against the container is the native prebuilt's
less the Vulkan container's, over the Vulkan container's.

| Model | Size | Params | Test | ROCm container t/s | Vulkan container t/s | Vulkan native t/s | ROCm against Vulkan | Native against Vulkan container |
|---|---|---|---|---|---|---|---|---|
| gpt-oss 120B MXFP4 MoE | 59.02 GiB | 116.83 B | pp512 | 1016.65 ± 13.34 | 1150.20 ± 10.90 | 1259.40 ± 8.89 | −11.61% | +9.49% |
| gpt-oss 120B MXFP4 MoE | 59.02 GiB | 116.83 B | tg256 | 51.23 ± 0.03 | 56.28 ± 0.05 | 55.11 ± 0.25 | −8.97% | −2.08% |
| gpt-oss 120B MXFP4 MoE | 59.02 GiB | 116.83 B | pp512 @ d8192 | 859.71 ± 17.13 | 923.54 ± 2.94 | 984.43 ± 9.90 | −6.91% | +6.59% |
| gpt-oss 120B MXFP4 MoE | 59.02 GiB | 116.83 B | tg256 @ d8192 | 46.08 ± 0.01 | 50.82 ± 0.37 | 51.12 ± 0.24 | −9.33% | +0.59% |
| gemma4 26B.A4B Q4_0 | 13.43 GiB | 25.23 B | pp512 | 1787.01 ± 27.68 | 2040.48 ± 8.45 | 2132.18 ± 6.89 | −12.42% | +4.49% |
| gemma4 26B.A4B Q4_0 | 13.43 GiB | 25.23 B | tg256 | 65.36 ± 0.05 | 71.37 ± 0.08 | 71.87 ± 0.10 | −8.42% | +0.70% |
| gemma4 26B.A4B Q4_0 | 13.43 GiB | 25.23 B | pp512 @ d8192 | 1284.73 ± 8.96 | 1430.10 ± 7.85 | 1522.68 ± 8.99 | −10.17% | +6.47% |
| gemma4 26B.A4B Q4_0 | 13.43 GiB | 25.23 B | tg256 @ d8192 | 55.65 ± 0.03 | 60.63 ± 0.04 | 61.33 ± 0.04 | −8.21% | +1.15% |

- **The Vulkan container leads the ROCm container on every row.** Prompt processing by 6.91 to
  12.42%, generation by 8.21 to 9.33%, at both depths, on both models. Put the other way, Vulkan's
  figures are 7.42 to 14.18% above ROCm's.
- **The native prebuilt leads the Vulkan container at prompt processing.** pp512 by 4.49 to 9.49%
  on all four rows, each beyond both standard deviations. Generation is within 1.2% at three rows,
  native ahead, and 2.08% behind at gpt-oss-120b's tg256 at depth 0. The native prebuilt runs on
  the host's Mesa 26.2.5 and the image on Ubuntu's Mesa 26.0, a likely cause of the gap; this task
  didn't test it.
- Each run logged its device: the ROCm image `ROCm0` as `gfx1151`, the Vulkan image and the native
  prebuilt `Vulkan0` as `Radeon 8060S Graphics (RADV STRIX_HALO)`, with `matrix cores:
  KHR_coopmat`. The native prebuilt's log reads fp16 `dot2` where the image's reads `1`.

Before the first run, `docker stop llama` left the container `Exited (0)`, and the GPU's memory in
use read `gtt_used 244002816 vram_used 491102208`. Each run's real time and exit:

| Run | ROCm container | Vulkan container | Vulkan native |
|---|---|---|---|
| gpt-oss-120b, d0 | 39.2 s, exit 0 | 42.1 s, exit 0 | 42.2 s, exit 0 |
| gpt-oss-120b, d8192 | 44.7 s, exit 0 | 42.1 s, exit 0 | 40.6 s, exit 0 |
| gemma-4-26B-A4B, d0 | exit 0 | exit 0 | exit 0 |
| gemma-4-26B-A4B, d8192 | exit 0 | exit 0 | exit 0 |

No run reached the cap, so none was split. In gpt-oss-120b's block, `time` printed to the console
out of order with the tables, stderr and stdout arriving apart over SSH, so each `real` above is
assigned by run order; the six sum to 250.9 s, the block's span from 19:04:03 to 19:08:14. The
gemma-4-26B-A4B block's console wasn't kept beyond its times: each of its six runs took 21 to 33 s
and exited 0. gpt-oss-120b's depth 8192 runs took about 40 s, well under the 4 to 8 minutes
[Run times](#run-times) estimated.

### Cold load and footprint

Each load timed from a dropped page cache, from the load request to `loaded`. The footprint is
MemAvailable before less after, and GTT and VRAM in use after less before
(`mem_info_gtt_used`, `mem_info_vram_used`, the change in brackets), beside the buffers the
engine logged, in MiB, on the GPU (ROCm0 or Vulkan0) and the host (ROCm_Host or Vulkan_Host). A KV
figure of two parts is the full-attention layers' and the sliding-window layers'. Each projector's
figure is its model size, then its compute buffers on the GPU. gpt-oss-120b's rows are the
flavors' timed cold loads, step 1 on a router just started; the others are each step's load.

| Flavor | Model | Format | Cache before → after drop GiB | MemAvailable before → after GiB | Footprint GiB | GTT used before → after GiB | VRAM used before → after MiB | Offloaded | Weights MiB (logged, GPU + host) | KV cache MiB (logged) | Compute MiB (logged, GPU + host) | Projector MiB (logged) | Load s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ROCm | gpt-oss-120b | MXFP4 | 72.17 → 0.38 | 118.28 → 55.75 | 62.53 | 0.23 → 60.19 (+59.96) | 468.40 → 470.46 (+2.06) | 37/37 | 59851.68 + 586.82 (output 3.07) | 1152.00 + 108.00 | 98.77 + 31.28 | — | 12.9 |
| Vulkan | gpt-oss-120b | MXFP4 | 1.62 → 0.37 | 118.35 → 56.06 | 62.29 | 0.23 → 60.61 (+60.38) | 468.36 → 470.70 (+2.34) | 37/37 | 59851.64 + 586.82 (output 3.07) | 1152.00 + 108.00 | 98.77 + 31.29 | — | 18.2 |
| ROCm | gemma-4-E4B | Q8_0 | 54.47 → 0.37 | 118.34 → 106.68 | 11.66 | 0.23 → 6.58 (+6.35) | 468.40 → 468.63 (+0.23) | 43/43 | 4788.12 + 3536.00 (output 4.00) | 512.00 + 160.00 | 136.02 + 50.03 | 533.83; compute 101.27 + 101.19 | 3.1 |
| Vulkan | gemma-4-E4B | Q8_0 | 54.37 → 0.37 | 118.41 → 107.01 | 11.40 | 0.23 → 9.92 (+9.69) | 468.36 → 469.75 (+1.38) | 43/43 | 4788.10 + 3536.00 (output 4.00) | 512.00 + 160.00 | 131.02 + 50.04 | 533.83; compute 101.27 + 101.19 | 4.2 |
| ROCm | gemma-4-E4B | QAT Q4_0 | 8.83 → 0.36 | 118.26 → 109.07 | 9.18 | 0.23 → 4.94 (+4.71) | 468.40 → 468.63 (+0.23) | 43/43 | 2696.06 + 2730.00 (output 4.00) | 512.00 + 160.00 | 136.02 + 50.03 | 945.51; compute 101.27 + 101.19 | 2.6 |
| Vulkan | gemma-4-E4B | QAT Q4_0 | 8.64 → 0.38 | 118.31 → 109.43 | 8.88 | 0.23 → 7.49 (+7.26) | 468.36 → 469.73 (+1.37) | 43/43 | 2696.04 + 2730.00 (output 4.00) | 512.00 + 160.00 | 131.02 + 50.04 | 945.51; compute 101.27 + 101.19 | 3.1 |
| ROCm | gemma-4-12B | QAT Q4_0 | 6.51 → 0.36 | 118.21 → 106.18 | 12.03 | 0.23 → 9.70 (+9.47) | 468.40 → 468.59 (+0.19) | 49/49 | 6637.69 + 787.50 (output 4.00) | 512.00 + 1920.00 | 129.52 + 39.53 | 167.00; compute 13.53 + 58.59 | 3.1 |
| Vulkan | gemma-4-12B | QAT Q4_0 | 6.36 → 0.37 | 118.19 → 106.48 | 11.71 | 0.23 → 10.34 (+10.12) | 468.36 → 487.93 (+19.56) | 49/49 | 6637.63 + 787.50 (output 4.00) | 512.00 + 1920.00 | 129.52 + 39.54 | 167.00; compute 18.03 + 58.59 | 3.6 |
| ROCm | gemma-4-31B | QAT Q4_0 | 7.59 → 0.37 | 118.17 → 89.92 | 28.25 | 0.23 → 25.44 (+25.21) | 468.40 → 468.66 (+0.26) | 61/61 | 16818.28 + 1102.50 (output 4.00) | 2560.00 + 4800.00 | 177.52 + 51.53 | 1145.08; compute 150.63 | 5.7 |
| Vulkan | gemma-4-31B | QAT Q4_0 | 7.48 → 0.38 | 118.22 → 90.15 | 28.07 | 0.23 → 26.42 (+26.19) | 468.36 → 470.40 (+2.04) | 61/61 | 16818.21 + 1102.50 (output 4.00) | 2560.00 + 4800.00 | 188.02 + 51.54 | 1145.08; compute 150.63 | 7.8 |
| ROCm | gemma-4-26B-A4B | QAT Q4_0 | 18.32 → 0.37 | 118.27 → 98.92 | 19.35 | 0.23 → 17.03 (+16.80) | 468.40 → 468.64 (+0.24) | 31/31 | 13755.42 + 577.50 (output 4.00) | 640.00 + 1200.00 | 152.52 + 31.53 | 1139.46; compute 150.63 | 4.7 |
| Vulkan | gemma-4-26B-A4B | QAT Q4_0 | 18.21 → 0.38 | 118.14 → 99.18 | 18.97 | 0.23 → 17.42 (+17.20) | 468.36 → 469.93 (+1.57) | 31/31 | 13755.36 + 577.50 (output 4.00) | 640.00 + 1200.00 | 108.52 + 31.54 | 1139.46; compute 150.63 | 5.7 |
| ROCm | granite-embedding-english-r2 | BF16 | 15.37 → 0.38 | 118.29 → 116.64 | 1.65 | 0.23 → 1.04 (+0.81) | 468.40 → 468.54 (+0.14) | 23/23 | 210.51 + 73.78 (output 3.12) | — | 460.13 + 352.19 | — | 0.6 |
| Vulkan | granite-embedding-english-r2 | BF16 | 15.27 → 0.38 | 118.38 → 117.01 | 1.37 | 0.23 → 1.30 (+1.07) | 468.36 → 468.80 (+0.44) | 23/23 | 210.51 + 73.78 (output 3.12) | — | 460.13 + 352.19 | — | 0.6 |

- **ROCm loaded every model faster.** gpt-oss-120b in 12.9 s against 18.2 s, and the others by 0.5
  to 2.1 s, granite level at 0.6 s.
- **The footprints match within 0.4 GiB.** MemAvailable fell by the same amount on both flavors,
  ROCm's slightly more for every model, and every layer of every model was on the GPU.
- **Vulkan's GTT in use rose more than ROCm's, for every model.** By about each model's host
  model buffer: 3.34 GiB more for E4B Q8_0, whose host buffer, its per-layer embeddings, is
  3536.00 MiB (3.45 GiB), 2.55 GiB more for E4B QAT Q4_0 (2730.00 MiB), and 0.42 GiB more for
  gpt-oss-120b (586.82 MiB). VRAM, the 512 MiB carve-out, held about
  468 MiB of the desktop's before each load, and rose under 3 MiB with each, except Vulkan's 12B,
  by 19.56 MiB.
- In kB, step 1's MemAvailable fell from 124,024,988 to 58,461,176 on ROCm and from 124,094,016 to
  58,779,592 on Vulkan. ROCm's step 1 cache before the drop held the model llama-bench had just
  read; Vulkan's step 1 came after the switch had replaced the container, its cache 1.62 GiB.
- Both flavors logged `n_ctx` 32768, `flash_attn` auto resolved to `Flash Attention enabled`, and 4
  slots of `n_ctx_slot` 8192 for every generative model; granite logged `n_ctx` 131072 and 16 slots
  of 8192. The logged buffers are the same on both flavors to within 0.07 MiB, except the compute
  buffers on the GPU: Vulkan's 5.00 MiB smaller for E4B, 10.50 larger for the 31B, 44.00 smaller
  for the 26B-A4B, and its 12B projector's 4.50 larger.
- Each projector also logged compute buffers on the CPU: 6.77 and 1.58 MiB for E4B's two, 6.75 and
  7.32 for the 12B's, and 6.77 for the 31B's and the 26B-A4B's.

### Anchors

gpt-oss-120b MXFP4, 4 slots, 512 in and 256 out, from a warm start. Every request carried 579
prompt tokens and generated 256, on both flavors.

| Cell | Flavor | Completed | Errored | Duration s | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | ITL p95 ms | Latency median s | Latency p95 s | Server prompt | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | ROCm | 8 | 0 | 48.28 | 42.4 | 657 | 681 | 20.99 | 21.52 | 6.01 | 6.17 | 4,138 tokens, 899.4 tok/s | 47.1 |
| A | Vulkan | 8 | 0 | 45.38 | 45.1 | 620 | 691 | 19.72 | 19.89 | 5.65 | 5.74 | 4,138 tokens, 941.5 tok/s | 50.2 |
| B | ROCm | 32 | 0 | 110.96 | 73.8 | 2231 | 2247 | 47.28 | 48.24 | 14.29 | 14.55 | 12,448 tokens, 975.6 tok/s | 20.9 |
| B | Vulkan | 32 | 0 | 105.47 | 77.7 | 2073 | 2094 | 44.92 | 46.69 | 13.53 | 14.00 | 12,448 tokens, 1049.3 tok/s | 22.0 |

The server computed 4,138 of A's 4,632 prompt tokens and 12,448 of B's 18,528 on both flavors,
reusing the cached template prefix. The verdict's figures, each anchor's mean output tok/s at full
precision from its JSON:

| Anchor | ROCm output tok/s | Vulkan output tok/s | ROCm against Vulkan |
|---|---|---|---|
| A | 42.41731 | 45.12570 | −6.00% |
| B | 73.82684 | 77.67444 | −4.95% |

Put the other way, Vulkan's A is 6.39% above ROCm's and its B 5.21%. Slice 1's viability A on ROCm,
42.7 tok/s at 17:25 (-04:00), lies within 0.3 tok/s of this session's 42.4; its before-snapshot was
empty, so it isn't a comparison cell ([Viability](#viability)).

### Shapes

| Shape | Model | Format | Cell | Streams × requests | Flavor | Completed | Errored | Duration s | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | ITL p95 ms | Latency median s | Latency p95 s | Server prompt tok/s | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| dense small | gemma-4-E4B | Q8_0 | A | 1 × 8 | ROCm | 8 | 0 | 57.15 | 35.8 | 374 | 443 | 26.45 | 26.55 | 7.12 | 7.21 | 1779.5 | 37.5 |
| dense small | gemma-4-E4B | Q8_0 | A | 1 × 8 | Vulkan | 8 | 0 | 55.18 | 37.1 | 360 | 443 | 25.57 | 25.72 | 6.90 | 7.00 | 1853.3 | 38.8 |
| dense mid | gemma-4-12B | QAT Q4_0 | A | 1 × 8 | ROCm | 8 | 0 | 81.01 | 25.3 | 734 | 769 | 36.75 | 36.78 | 10.11 | 10.14 | 876.6 | 27.0 |
| dense mid | gemma-4-12B | QAT Q4_0 | A | 1 × 8 | Vulkan | 8 | 0 | 79.67 | 25.7 | 731 | 764 | 36.12 | 36.22 | 9.95 | 9.98 | 893.2 | 27.5 |
| dense mid | gemma-4-12B | QAT Q4_0 | B | 4 × 32 | ROCm | 32 | 0 | 108.55 | 75.5 | 2362 | 2420 | 45.64 | 45.66 | 14.00 | 14.06 | 980.1 | 21.7 |
| dense mid | gemma-4-12B | QAT Q4_0 | B | 4 × 32 | Vulkan | 32 | 0 | 108.21 | 75.7 | 2347 | 2417 | 44.98 | 46.49 | 13.83 | 14.25 | 982.6 | 21.9 |
| dense large | gemma-4-31B | QAT Q4_0 | A | 1 × 4 | ROCm | 4 | 0 | 98.71 | 10.4 | 1912 | 1953 | 89.21 | 89.34 | 24.65 | 24.73 | 333.3 | 11.1 |
| dense large | gemma-4-31B | QAT Q4_0 | A | 1 × 4 | Vulkan | 4 | 0 | 94.92 | 10.8 | 1884 | 1888 | 85.68 | 85.71 | 23.73 | 23.75 | 344.5 | 11.6 |
| dense large | gemma-4-31B | QAT Q4_0 | B | 4 × 16 | ROCm | 16 | 0 | 128.77 | 31.8 | 5930 | 6025 | 107.83 | 107.85 | 33.43 | 33.52 | 387.0 | 9.2 |
| dense large | gemma-4-31B | QAT Q4_0 | B | 4 × 16 | Vulkan | 16 | 0 | 124.81 | 32.8 | 6065 | 6148 | 103.57 | 103.71 | 32.50 | 32.56 | 378.1 | 9.6 |
| MoE | gemma-4-26B-A4B | QAT Q4_0 | A | 1 × 8 | ROCm | 8 | 0 | 37.03 | 55.3 | 411 | 440 | 16.39 | 16.79 | 4.62 | 4.69 | 1539.3 | 60.1 |
| MoE | gemma-4-26B-A4B | QAT Q4_0 | A | 1 × 8 | Vulkan | 8 | 0 | 34.62 | 59.2 | 391 | 472 | 15.33 | 15.36 | 4.31 | 4.38 | 1590.0 | 64.7 |
| MoE | gemma-4-26B-A4B | QAT Q4_0 | B | 4 × 32 | ROCm | 32 | 0 | 67.82 | 120.8 | 1333 | 1383 | 28.90 | 29.24 | 8.71 | 8.84 | 1741.7 | 34.3 |
| MoE | gemma-4-26B-A4B | QAT Q4_0 | B | 4 × 32 | Vulkan | 32 | 0 | 65.83 | 124.4 | 1294 | 1321 | 27.92 | 28.64 | 8.44 | 8.60 | 1823.7 | 35.4 |
| MoE | gpt-oss-120b | MXFP4 | A, B | | both | the anchors, above | | | | | | | | | | | |

The prompt median was 528 tokens and the output median 256 in every cell, on both flavors. The
servers computed the same prompt tokens on both flavors: 4,159 in E4B's A, 4,173 in the 12B's and
the 26B-A4B's A, 12,448 in each B, and 2,105 and 6,224 in the 31B's A and B.

- **Vulkan's output tok/s is ahead or level on every shape cell.** By 3.5% at E4B Q8_0's A, 1.6%
  at the 12B's A, 0.3% at its B, 3.7% and 3.0% at the 31B's A and B, and 6.6% and 2.9% at the
  26B-A4B's A and B. Its ITL median is lower in every cell, by 0.63 to 4.26 ms.
- **TTFT is close.** Vulkan's median is lower in every cell but the 31B's B, where ROCm's is 135
  ms lower (5930 against 6065 ms) and ROCm's server prompt rate is higher (387.0 against 378.1
  tok/s). Vulkan's TTFT p95 is higher at the 26B-A4B's A, 472 against 440 ms, and at the 31B's B,
  6148 against 6025 ms.

### Quantization pair

gemma-4-E4B, single stream, 1 × 8 (shape A). The footprint is from
[Cold load and footprint](#cold-load-and-footprint).

| Flavor | Format | Output tok/s | TTFT median ms | ITL median ms | Latency median s | Server gen tok/s | Footprint GiB |
|---|---|---|---|---|---|---|---|
| ROCm | Q8_0 | 35.8 | 374 | 26.45 | 7.12 | 37.5 | 11.66 |
| ROCm | QAT Q4_0 | 53.9 | 317 | 17.30 | 4.73 | 57.3 | 9.18 |
| Vulkan | Q8_0 | 37.1 | 360 | 25.57 | 6.90 | 38.8 | 11.40 |
| Vulkan | QAT Q4_0 | 58.1 | 303 | 16.00 | 4.39 | 61.9 | 8.88 |

QAT Q4_0 served 50.6% more output tok/s than Q8_0 on ROCm and 56.6% more on Vulkan, in 2.48 and
2.52 GiB less memory. Its weights are 2696.06 MiB on the GPU and 2730.00 on the host against Q8_0's
4788.12 and 3536.00, and its projector 945.51 MiB against Q8_0's 533.83. Vulkan's lead is 3.5% at
Q8_0 and 7.2% at QAT Q4_0.

### Vision

gemma-4-26B-A4B, one synthetic 720p JPEG and 200 text tokens a request, 64 out:

| Flavor | Cell | Streams × requests | Completed | Errored | Prompt tokens median | Output tok/s | TTFT median ms | TTFT p95 ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|---|
| ROCm | A | 1 × 8 | 8 | 0 | 623 | 28.8 | 1204 | 1365 | 2.20 | 2.36 |
| ROCm | B | 4 × 32 | 32 | 0 | 623 | 50.8 | 4278 | 4307 | 6.00 | 6.03 |
| Vulkan | A | 1 × 8 | 8 | 0 | 623 | 24.8 | 1620 | 1774 | 2.56 | 2.70 |
| Vulkan | B | 4 × 32 | 32 | 0 | 623 | 40.9 | 5920 | 5948 | 7.62 | 7.67 |

ROCm leads both vision cells: output tok/s by 16.1% at A and 24.2% at B. The lead is in TTFT, which
includes each request's image encoding: ROCm's median is 416 ms lower at A and 1642 ms lower at B.
The servers' figures: ROCm computed 4,896 prompt tokens in A at 549.6 tok/s and 14,728 in B at
598.7 tok/s, Vulkan the same counts at 399.1 and 425.8 tok/s. Vulkan generated faster per request,
65.0 and 36.1 tok/s against ROCm's 61.1 and 35.6, and its ITL median was 14.80 and 26.83 ms
against ROCm's 15.74 and 27.21.

### Embeddings

granite-embedding-english-r2 BF16, 512 tokens a request, 30 s a level:

| Flavor | Streams | Completed | Incomplete | Errored | Requests/s | Input tok/s | Prompt tokens median | Latency median ms | Latency p95 ms |
|---|---|---|---|---|---|---|---|---|---|
| ROCm | 1 | 955 | 0 | 0 | 31.8 | 16,313 | 513 | 27 | 29 |
| ROCm | 16 | 832 | 16 | 0 | 27.7 | 14,227 | 513 | 571 | 574 |
| Vulkan | 1 | 728 | 0 | 0 | 24.2 | 12,432 | 513 | 37 | 40 |
| Vulkan | 16 | 1190 | 16 | 3 | 39.7 | 20,349 | 513 | 398 | 408 |

- **ROCm led at 1 stream and Vulkan at 16.** ROCm served 31.8 requests/s against 24.2 at 1 stream,
  31.4% more; Vulkan 39.7 against 27.7 at 16, 43.3% more. ROCm's rate fell from 1 stream to 16,
  and Vulkan's rose.
- The 16 incomplete requests at 16 streams were in flight when the level's 30 s ended, on both
  flavors.
- **Vulkan's 3 errors were the client's connect timeout.** Each is GuideLLM's
  `ConnectTimeout('')`, its 5 s connect timeout (`timeout_connect` 5.0), and the router logged no
  error. The server's counters show the 3 never reached it: Vulkan computed 992,142 prompt tokens
  over both levels, 513 for each of the 1,934 completed and incomplete requests, and ROCm 924,939,
  513 for each of its 1,803.
- The servers' prompt rates, by the snapshots' diff: ROCm 924,939 tokens in 52.58 s, 17,590.2
  tok/s; Vulkan 992,142 in 53.03 s, 18,710.5 tok/s.

### ASR

gemma-4-E4B Q8_0's audio through chat, one LibriSpeech clip a request with the card's prompt:

| Flavor | Cell | Streams × requests | Completed | Errored | Audio s/s | Output tokens median | TTFT median ms | Latency median s | Latency p95 s |
|---|---|---|---|---|---|---|---|---|---|
| ROCm | A | 1 × 8 | 8 | 0 | 11.36 | 19 | 240 | 0.72 | 2.70 |
| ROCm | B | 4 × 32 | 32 | 0 | 19.42 | 17 | 458 | 1.24 | 3.31 |
| Vulkan | A | 1 × 8 | 8 | 0 | 11.40 | 20 | 246 | 0.74 | 2.71 |
| Vulkan | B | 4 × 32 | 32 | 0 | 19.76 | 17 | 428 | 1.35 | 3.22 |

The ASR cells are level: audio seconds a second within 1.8%, Vulkan's higher on both, and output
tok/s 28.4 against 28.2 at A and 52.5 against 52.1 at B, ROCm's higher. GuideLLM warned on every
ASR cell, on both flavors, that the benchmark was likely bottlenecked by its data generation: its
mean generation delay was 104% of the mean TTFT at ROCm's A and 80% at Vulkan's, 16% and 15% at B,
and its p95 root dispatch delay 1.0 to 1.2 s. Both flavors' audio figures carry that client delay.
The servers computed 2,406 prompt tokens in A and 4,551 in B on both flavors, ROCm at
1267.9 and 532.9 tok/s, Vulkan at 1060.0 and 548.3.

### Unsupported cells

None: both flavors served every cell, and every guidellm exited 0.

| Flavor | Cell | Reason |
|---|---|---|
| — | — | none |

### Network path, build, and model state, per flavor

| Flavor | Image and devices | Model | `tailscale ping` | Build | `requests_processing` before each cell |
|---|---|---|---|---|---|
| ROCm | `ghcr.io/ggml-org/llama.cpp:server-rocm-b11669`, devices `/dev/kfd /dev/dri` | each model, steps 1 to 7 | direct on the LAN at every step, 0 to 1 ms (addresses left out) | `/props` build_info `b11669-620d2225c` at every step | 0 at every cell |
| Vulkan | `ghcr.io/ggml-org/llama.cpp:server-vulkan-b11669`, devices `/dev/dri` | each model, steps 1 to 7 | direct on the LAN at every step, 0 to 1 ms (addresses left out) | `/props` build_info `b11669-620d2225c` at every step | 0 at every cell |

The switch printed `llama moved from ghcr.io/ggml-org/llama.cpp:server-rocm-b11669 to
ghcr.io/ggml-org/llama.cpp:server-vulkan-b11669`. Every warm-up returned a greeting, ROCm's step 1
`"Hello!"`, Vulkan's `"Hello, I hope you’re having a wonderful day!"`, and granite's an embedding
of 8 prompt tokens. Step 1's warm-ups ran at 23:12:02Z on ROCm and 23:43:01Z on Vulkan.

### framework's end state

At 20:02:50 (-04:00), `host/engines llama update` moved the flavor from `vulkan` back to `rocm`,
and `docker stop llama` stopped the container, which read `Exited (137)`: llama-server, just
recreated, didn't exit on SIGTERM within Docker's 10 s, so Docker killed it. Its restart policy is
`unless-stopped`, so a container stopped by hand stays stopped at boot. `llama-router` read
`disabled` and `inactive`, and `ss` printed only its header: nothing listens on 8080.

## Verdict

The brief's rule: ROCm leads only when both anchors' served output tok/s, A's and B's, beat
Vulkan's by more than 3%. A split result, one anchor ahead and the other not, or one within 3%,
is no lead.

What follows from it: when ROCm leads, strix-native runs, and vllm-strix compares with ROCm.
Otherwise strix-native drops, and vllm-strix compares with Vulkan: the leading backend when Vulkan
beats ROCm on both anchors by more than 3%, and the comparison backend when nothing leads.

The verdict, from [Anchors](#anchors): **ROCm doesn't lead.** Its A is 6.00% below Vulkan's (42.4
against 45.1 tok/s) and its B 4.95% below (73.8 against 77.7). Vulkan beats ROCm on both anchors
by more than 3%, 6.39% and 5.21%, so Vulkan is llama.cpp's leading backend on Strix Halo:
strix-native drops, and vllm-strix compares with Vulkan.

## Findings

Dated 2026-10-27, on framework, llama.cpp v0.7.0 (b11669) in ggml's ROCm and Vulkan images and
ggml's native Vulkan prebuilt, on the host stack above. The spike decides nothing here; the answer
task does.

- **Vulkan leads the anchors and the engine.** Vulkan served gpt-oss-120b's A at 45.1 tok/s and B
  at 77.7, 6.39% and 5.21% above ROCm, and the Vulkan container led the ROCm container on every
  llama-bench row, prompt processing by 6.91 to 12.42% and generation by 8.21 to 9.33%.
- **Vulkan is ahead or level on every text cell.** Its output tok/s leads by 0.3 to 6.6% across
  E4B, the 12B, the 31B, and the 26B-A4B, and its ITL is lower in every one. ROCm's TTFT is lower
  only at the 31B's B.
- **ROCm loads faster.** It cold-loaded every model sooner: gpt-oss-120b in 12.9 s against 18.2 s,
  E4B Q8_0 3.1 against 4.2, E4B QAT Q4_0 2.6 against 3.1, the 12B 3.1 against 3.6, the 31B 5.7
  against 7.8, the 26B-A4B 4.7 against 5.7, and granite level at 0.6.
- **ROCm leads both vision cells.** By 16.1% at A and 24.2% at B in output tok/s, through TTFT,
  which includes the image's encoding: 1204 against 1620 ms at A, 4278 against 5920 ms at B.
- **Embeddings split by concurrency.** ROCm led at 1 stream, 31.8 against 24.2 requests/s, and
  Vulkan at 16, 39.7 against 27.7; Vulkan's 16-stream level had 3 client connect timeouts that
  never reached the server.
- **ASR is level**, within 1.8% on audio seconds a second, with GuideLLM's data generation
  delaying every cell on both flavors.
- **Memory is the same.** Footprints within 0.4 GiB, every layer on the GPU, the same buffers to
  within 0.07 MiB but the compute buffers. Vulkan's GTT in use rose more than ROCm's, by about each
  model's host buffer.
- **The native prebuilt is ahead of the Vulkan container at prompt processing.** pp512 by 4.49 to
  9.49% on all four rows, generation within 2.1%. The image's Ubuntu Mesa 26.0 against the host's
  26.2.5 is a likely cause, not tested.
- **The quantization pair.** E4B QAT Q4_0 served 50.6% more output tok/s than Q8_0 on ROCm and
  56.6% more on Vulkan, in about 2.5 GiB less memory.
- **framework's end state.** The `llama` container is at flavor `rocm` and stopped, so it stays
  stopped at boot, `llama-router` is disabled and inactive, and nothing listens on 8080.
