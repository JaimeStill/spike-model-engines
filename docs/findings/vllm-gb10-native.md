# vLLM in a container and natively on gb10-1

Recorded on 2026-10-27, on gb10-1, from the steps and cells the task's brief agreed
(context/goals, `vllm-gb10-native`). The same vLLM release runs in vLLM's image and natively, from
its aarch64 CUDA 13.0 wheel in a uv virtualenv under systemd, one after the other in one session,
so only the hosting method differs ([Comparisons](../../context/README.md#rules)). It is evidence 6
for vLLM on the GB10 ([The evidence](../../context/README.md#the-evidence)): install, update,
rollback, startup, speed parity, and GPU and memory access, container against bare metal. It also
takes up the question bench-gb10-container left open, vLLM's slow NVFP4 decode on SM121, with one
diagnostic run on another MoE kernel. It records what was measured; the spike's `answer` task
chooses the hosting method.

The native install, update, and rollback walk ran first, as slice 1, from 11:47 to 12:20 (-04:00).
The comparison followed: the session ran each step on gb10-1 over Tailscale SSH, and each GuideLLM
cell from the laptop in the architect's view, from the clone at c7a1e63 on `vllm-gb10-native`. After
the walkthrough, from the clone at 483e2b5, the session measured native's first start from an empty
compile cache, from 18:22Z to 18:28Z ([8. Native's first start](#8-natives-first-start)).

## Host stack

| Item | gb10-1 |
|---|---|
| OS | Ubuntu 24.04.5 LTS |
| Kernel | 7.0.0-1019-nvidia |
| Driver | 580.178.04 |
| CUDA | 13.0 |
| Docker | 29.6.2 (build dfc4efb) |
| Tailscale | 1.104.2 |
| NVIDIA Container Toolkit | 1.20.1 |
| DGX OS | `DGX_SWBUILD_VERSION` 7.4.0, `DGX_OTA_VERSION` 7.6.0 |
| Reboot pending | no (no `/var/run/reboot-required`) |
| Upgradable packages | 0 |

The session read the kernel, driver, Docker, and Tailscale at the comparison's start, and the
rest after the runs, at about 16:55Z ([7. The host stack and both methods' Python and
torch](#7-the-host-stack-and-both-methods-python-and-torch)). gb10-1 had been brought current
earlier on 2026-10-27, by the host-rename task; `apt list --upgradable` listed 0 packages, so this
session made no upgrade.

## Engine versions

Both methods run vLLM v0.32.0 and answer `/version` with `{"version":"0.32.0"}`. Both log FlashInfer
0.7.0.post1 for SM121 (`121a` in its autotune cache's path) and choose `FLASHINFER_CUTLASS` for
NVFP4's MoE experts on the pin's row.

| Method | Release | Python | torch | Source |
|---|---|---|---|---|
| Container | v0.32.0 | the image's CPython 3.12.3 | 2.13.0+cu130, CUDA 13.0 | `vllm/vllm-openai:v0.32.0` (`host/vllm.env`) |
| Native | v0.32.0 | uv-managed CPython 3.12.16 | 2.13.0+cu130, CUDA 13.0 | the `vllm==0.32.0` wheel with torch from PyTorch's cu130 index and FlashInfer's kernels, in `/opt/vllm/v0.32.0`, built by uv 0.13.6 and served by the `vllm-server` unit ([Setup](../engines/vllm/setup.md#gb10-native)) |

Both methods' Python and torch were read after the runs, in the image and in `current`
([7. The host stack and both methods' Python and
torch](#7-the-host-stack-and-both-methods-python-and-torch)), and native's match the line every
native start prints (`/version answers {"version":"0.32.0"}; torch 2.13.0+cu130, CUDA 13.0`) and
uv's `Using CPython 3.12.16`. Both run torch 2.13.0+cu130 on CUDA 13.0, and both run CPython 3.12,
the minor version the brief held native to; only the patch differs, 3.12.3 in the image against
uv's 3.12.16. Both serve the pin's row,
`gemma-4-26B-A4B-NVFP4`, from the same model store (`/srv/models`), on port 8000 of the tailnet
address: `nvidia/Gemma-4-26B-A4B-NVFP4 --max-num-seqs 4 --max-model-len 8192
--gpu-memory-utilization 0.80 --kv-cache-dtype bfloat16 --reasoning-parser gemma4
--enable-auto-tool-choice --tool-call-parser gemma4`. The container's command adds `--host 0.0.0.0
--port 8000` inside the container, whose port 8000 Docker publishes on the tailnet address; the
unit binds the tailnet address itself.

The load tool is GuideLLM 0.8.1 on the laptop, in the spike's bench environment
(`mise.bench.toml`: Python 3.14.10).

## Method

### The clone on gb10-1

Before the walk, the session installed the host environment's tools on gb10-1 and read uv's
version, from wherever the clone was:

```sh
cd ~/experiments/spike-model-engines 2>/dev/null || cd "$(dirname "$(find ~ -maxdepth 3 -name mise.host.toml -path "*spike-model-engines*" | head -1)")"; pwd; git branch --show-current; MISE_ENV=host mise install 2>&1 | tail -5; MISE_ENV=host mise exec -- uv --version
```

It printed the clone, `~/repos/spike-model-engines`, on `main`; `mise ✓ uv@0.13.6` and `installed 1
tool · 29 already installed`; and `uv 0.13.6 (aarch64-unknown-linux-gnu)`. At 10:58:20 (-04:00, from
the clone's reflog, as the times below) it moved the clone to the task's branch, then read what was
serving and whether `/opt/vllm` was there:

```sh
cd ~/repos/spike-model-engines && git fetch -q && git checkout -q vllm-gb10-native && git log --oneline -1 | cat; docker ps --format "{{.Names}} {{.Status}}"; systemctl is-active llama-router; ls -ld /opt/vllm 2>&1
```

It printed `278993b native vLLM: engines vllm-native steps, unit, sudoers rule, guides`, no running
container, `inactive`, and `ls: cannot access '/opt/vllm': No such file or directory`. It pulled the
branch at 12:25:48, to c7a1e63, before the comparison, and at 13:05:37, to abfbe1f, before the
walkthrough:

```sh
cd ~/repos/spike-model-engines && git pull -q && git log --oneline -1 | cat
```

and at 14:18:09, to 483e2b5, before native's first start, reading the uv mise runs and that the
preflight is defined; it printed the uv under mise's `uv/0.13.6` install, `exit 0`, and `defined`:

```sh
cd ~/repos/spike-model-engines && git pull -q && git log --oneline -1 | cat && (MISE_ENV=host mise which uv; echo "exit $?") && bash -c "set -e; source host/engines.sh 2>/dev/null; source host/vllm-native.sh; type vllm_native_preflight >/dev/null && echo defined"
```

### Native install, update, and rollback

On gb10-1, from `~/repos/spike-model-engines`, after the architect's root steps
([1. The architect's root steps](../engines/vllm/setup.md#1-the-architects-root-steps)) and uv's
install in the host environment ([How it is set up](../engines/vllm/setup.md#how-it-is-set-up)).
The architect's install at v0.31.0 and uv's read-back, uv's first walk, from the guide as it then
read:

```sh
host/engines vllm-native install v0.31.0
MISE_ENV=host mise exec -- uv pip list --python /opt/vllm/current
```

The read-back set no `UV_CACHE_DIR`, so uv cached what it read of the interpreter in `~/.cache/uv`, as
[Findings](#findings) records; the guide's read-backs now point uv's cache at `/opt/vllm/cache/uv`
([Reading it back](../engines/vllm/setup.md#reading-it-back)).

After the install, from the home directory, the session read the start's time and lines and the
memory available, then kept the unit's journal so far in a local file:

```sh
systemctl show vllm-server --property ActiveEnterTimestamp; journalctl -u vllm-server -o short-iso --no-pager | grep -E "Application startup complete|Model loading took|Loading weights took|torch.compile takes|compil|Available KV cache|KV cache|CUDA graph|Graph capturing|backend|MoE" | head -40; grep MemAvailable /proc/meminfo
```

```sh
journalctl -u vllm-server -o short-iso --no-pager
```

Then the session's update to the pin, the rollback, and the forward update, each run as `cd
~/repos/spike-model-engines && host/engines vllm-native update …`, each output kept in a local
file:

```sh
host/engines vllm-native update v0.32.0
host/engines vllm-native update v0.31.0
host/engines vllm-native update
```

Before the rollback, from the home directory, the previous start's time and lines:

```sh
systemctl show vllm-server --property ActiveEnterTimestamp; journalctl -u vllm-server -o short-iso --no-pager --since "-15min" | grep -E "Application startup complete|Loading weights took|torch.compile took|init engine|Available KV|NvFp4 MoE backend"
```

Before the forward update, the same read without `|Available KV|NvFp4 MoE backend`, its output cut
on the laptop (`| cut -c1-200 | tail -5`):

```sh
systemctl show vllm-server --property ActiveEnterTimestamp; journalctl -u vllm-server -o short-iso --no-pager --since "-15min" | grep -E "Application startup complete|Loading weights took|torch.compile took|init engine"
```

After it, in one command from the home directory, that read again, then the layout and a second
install from the clone, its output cut on the laptop (`| cut -c1-200 | tail -9`):

```sh
systemctl show vllm-server --property ActiveEnterTimestamp; journalctl -u vllm-server -o short-iso --no-pager --since "-15min" | grep -E "Application startup complete|Loading weights took|torch.compile took|init engine"; cd ~/repos/spike-model-engines; command ls /opt/vllm; readlink /opt/vllm/current; host/engines vllm-native install
```

Then, from the laptop, at about 16:20Z, the version, with no `tailscale ping` beside it:

```sh
curl -s -m5 http://gb10-1:8000/version
```

The four starts' figures in [Startup](#startup) are read from the unit's whole journal, kept after
the walk in a local file, `walk.journal`, and read on the laptop:

```sh
journalctl -u vllm-server -o short-iso --no-pager
```

```sh
grep -E 'Started vllm-server|Stopped vllm-server|Application startup complete|Loading weights took|torch.compile took|init engine|Available KV|Model loading took' walk.journal | sed -E 's/gb10-1 (bash|systemd)\[[0-9]+\]: //' | cut -c1-170
```

### 1. The container's cold start

On gb10-1, from the clone: the host stack, native vLLM stopped and disabled, the page cache dropped
with its size before and after, the memory available, the container's install (which reports a
stopped container and starts nothing), its start, the `/health` poll of
bench-gb10-container ([vLLM: per row, the switch, the cold start, and its
footprint](bench-gb10-container.md#vllm-per-row-the-switch-the-cold-start-and-its-footprint)), the
start time, the ready line, the command it serves, the memory available after, and the lines vLLM
logged:

```sh
uname -r; nvidia-smi --query-gpu=driver_version --format=csv,noheader; docker --version; tailscale version | head -1
sudo -n systemctl stop vllm-server && sudo -n systemctl disable vllm-server
grep ^Cached /proc/meminfo; sync && sudo -n /usr/sbin/sysctl vm.drop_caches=3; grep ^Cached /proc/meminfo
grep ^MemAvailable /proc/meminfo
host/engines vllm install 2>&1 | tail -3
docker start vllm
for i in $(seq 120); do [ "$(curl -s -o /dev/null -w "%{http_code}" "http://$(tailscale ip -4):8000/health")" = 200 ] && break; sleep 5; done; date -u; docker inspect --format "{{.State.Status}}, restarts {{.RestartCount}}" vllm
docker inspect --format "{{.State.StartedAt}}" vllm
docker logs --timestamps vllm 2>&1 | grep -m 1 "Application startup complete"
docker inspect --format "{{.Config.Image}} {{join .Config.Cmd \" \"}}" vllm
grep ^MemAvailable /proc/meminfo
docker logs vllm 2>&1 | grep -E "Model loading took|Available KV cache memory|KV cache size|Graph capturing finished|Directly load the compiled graph|Directly load AOT|torch.compile took|init engine|NvFp4 MoE backend|Free memory on device"
```

The ready line's `grep -m 1` returned the previous day's line, `2026-10-26T21:29:08.640822844Z`: a
container started again keeps its earlier starts' log, and this one last started on 2026-10-26
(bench-gb10-container's round 5). The session read it again from this start only, at the start
time `docker inspect` printed:

```sh
docker logs --timestamps --since 2026-10-27T16:26:09Z vllm 2>&1 | grep -m 1 "Application startup complete"
```

The setup guide's command now reads only since the container's start
([6. Watch the cold start](../engines/vllm/setup.md#6-watch-the-cold-start-and-record-it)).
`docker logs vllm` without `--since`, the last line above, printed both days' starts; the figures in
[Startup](#startup) are this start's, at 10-27 16:26 to 16:29 (UTC).

### 2. The container's cells

On the laptop, from the clone: the time and the network path, the target, the release, the model,
the warm-up, and the confirmation that the server is warm and idle, as bench-gb10-container ran
them ([vLLM: per row, the version and the
warm-up](bench-gb10-container.md#vllm-per-row-the-version-and-the-warm-up)), then A'
(`bench/vllm-anchor-a.yaml`, 1 stream × 8 requests) and B' (`bench/vllm-anchor-b.yaml`, 4
streams × 32), as task 2 defined them ([Anchor cells](vllm-gb10-container.md#anchor-cells)): Gemma
4 26B-A4B NVFP4, 512 synthetic prompt tokens and exactly 256 output tokens a request, with
reasoning on:

```sh
date -u +%FT%TZ; tailscale ping -c 3 gb10-1
export GUIDELLM__SPEC__BACKEND__TARGET="http://gb10-1:8000"
mkdir -p .state/bench
model=nvidia/Gemma-4-26B-A4B-NVFP4
curl -s "http://gb10-1:8000/version"; echo
curl -s "http://gb10-1:8000/v1/models" | jq -c '.data[] | {id, max_model_len}'
curl -s "http://gb10-1:8000/v1/chat/completions" -H "Content-Type: application/json" -d "{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one sentence.\"}], \"chat_template_kwargs\": {\"enable_thinking\": true}}" | jq -c '.choices[0].message | {content, reasoning: (.reasoning|tostring|.[0:80])}'
curl -s "http://gb10-1:8000/metrics" | grep -E '^vllm:(request_success_total|num_requests_running)'
for cell in a b; do
  curl -s "http://gb10-1:8000/metrics" > .state/bench/vllm-container-anchor-$cell.before.metrics
  MISE_ENV=bench mise exec -- guidellm run -c bench/vllm-anchor-$cell.yaml --output "kind=json,path=.state/bench/vllm-container-anchor-$cell.json" > .state/bench/vllm-container-anchor-$cell.log 2>&1; echo "vllm-container-anchor-$cell: guidellm exit $?"
  curl -s "http://gb10-1:8000/metrics" > .state/bench/vllm-container-anchor-$cell.after.metrics
done
```

### 3. Native's cold start

On gb10-1, from the clone: the container stopped, the page cache dropped, the memory available,
native's install (which enables and starts the stopped unit at the release `current` names), the
unit's start time, the ready line from this start's journal, the row it serves, the memory
available after, and the lines vLLM logged for this start. `install` waits for `/health` itself, for
at most 10 minutes:

```sh
docker stop vllm
grep ^Cached /proc/meminfo; sync && sudo -n /usr/sbin/sysctl vm.drop_caches=3; grep ^Cached /proc/meminfo
grep ^MemAvailable /proc/meminfo
host/engines vllm-native install 2>&1 | tail -3
systemctl show vllm-server --property ActiveEnterTimestamp
journalctl -u vllm-server -o short-iso --since "$(systemctl show vllm-server --property ActiveEnterTimestamp --value)" | grep -m 1 "Application startup complete"
cat /opt/vllm/row | paste -sd" "
grep ^MemAvailable /proc/meminfo
journalctl -u vllm-server --since "$(systemctl show vllm-server --property ActiveEnterTimestamp --value)" | grep -E "Model loading took|Available KV cache memory|KV cache size|Graph capturing finished|Directly load AOT|torch.compile took|init engine|NvFp4 MoE backend|Free memory on device"
```

### The autotune reads

Native's start took 137 s longer than the container's, nearly all of it in one silent stretch of
the journal ([Startup](#startup)). On gb10-1, after native's start, the session read that stretch
and the container's matching one, both autotune caches, and the code that saves them. Each line ran
as written; the `python3` read failed, since FlashInfer's `autotuner.py` is in a subdirectory, and
the next read found it:

```sh
journalctl -u vllm-server -o short-iso --since "2026-10-27 12:36:02" --until "2026-10-27 12:38:57" | cut -c1-300 | head -40
docker logs --timestamps --since 2026-10-27T16:29:11Z --until 2026-10-27T16:29:25Z vllm 2>&1 | cut -c1-250 | head -30
```

```sh
find /opt/vllm/cache/vllm/flashinfer_autotune_cache -maxdepth 5 2>&1 | head; journalctl -u vllm-server --since "2026-10-27 12:33:24" | grep -iE "autotun.*(end|sav|writ|cache|error|fail|perm)|Permission" | cut -c1-300 | tail -8; docker exec vllm true 2>/dev/null; docker run --rm --entrypoint ls -v $HOME/.cache/vllm:/home/vllm/.cache/vllm vllm/vllm-openai:v0.32.0 -la /home/vllm/.cache/vllm/flashinfer_autotune_cache/0.7.0.post1/121a/ 2>&1 | head; ls -la ~/.cache/vllm/flashinfer_autotune_cache/0.7.0.post1/121a/*/ 2>&1 | head
```

```sh
ls -la ~/.cache/vllm/.cache/vllm/flashinfer_autotune_cache/0.7.0.post1/121a/*/ 2>&1|head; ls -la /opt/vllm/cache/vllm/flashinfer_autotune_cache/0.7.0.post1/121a/*/; f=/opt/vllm/current/lib/python3.12/site-packages/vllm/model_executor/warmup/kernel_warmup.py; grep -n "autotune_cache\|save\|dump\|json\|VLLM_\|envs\." $f | head -40
```

```sh
f=/opt/vllm/current/lib/python3.12/site-packages/vllm/model_executor/warmup/kernel_warmup.py; sed -n 440,515p $f; grep -n "def \|environ\|getenv\|world\|leader\|rank" /opt/vllm/current/lib/python3.12/site-packages/vllm/model_executor/warmup/flashinfer_autotune_cache.py | head -30
```

```sh
journalctl -u vllm-server -o cat --since "2026-10-27 12:36:16" --until "2026-10-27 12:38:57" --all | grep -v "Skipped .* unsupported tactic" | cut -c1-260 | grep -v "^$" | head -40; python3 - <<EOF
import re,glob
p=glob.glob("/opt/vllm/current/lib/python3.12/site-packages/flashinfer/autotuner.py")[0]
s=open(p).read()
i=s.find("def save_configs"); print(s[i:i+1800])
EOF
```

```sh
journalctl -u vllm-server -o cat --since "2026-10-27 12:38:50" --until "2026-10-27 12:38:57" --all | grep -v "Tuning trtllm" | cut -c1-300; p=$(find /opt/vllm/current/lib/python3.12/site-packages/flashinfer -name "autotuner.py" | head -1); echo $p; grep -n "def save_configs" -A40 $p | head -60
```

The container mounts `~/.cache/vllm` as its home, `/home/vllm` (`host/vllm.sh`), so its
`/home/vllm/.cache/vllm/…` is the host's `~/.cache/vllm/.cache/vllm/…`; the `docker run` read
mounted it elsewhere and listed nothing.

### 4. Native's cells

On the laptop, the container's block with three changes: no `mkdir`, the `/metrics` line counting
only the `stop` series, and `vllm-native-anchor-$cell` in place of `vllm-container-anchor-$cell`
throughout:

```sh
date -u +%FT%TZ; tailscale ping -c 3 gb10-1
export GUIDELLM__SPEC__BACKEND__TARGET="http://gb10-1:8000"
model=nvidia/Gemma-4-26B-A4B-NVFP4
curl -s "http://gb10-1:8000/version"; echo
curl -s "http://gb10-1:8000/v1/models" | jq -c '.data[] | {id, max_model_len}'
curl -s "http://gb10-1:8000/v1/chat/completions" -H "Content-Type: application/json" -d "{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one sentence.\"}], \"chat_template_kwargs\": {\"enable_thinking\": true}}" | jq -c '.choices[0].message | {content, reasoning: (.reasoning|tostring|.[0:80])}'
curl -s "http://gb10-1:8000/metrics" | grep -E '^vllm:(request_success_total\{.*stop|num_requests_running)'
for cell in a b; do
  curl -s "http://gb10-1:8000/metrics" > .state/bench/vllm-native-anchor-$cell.before.metrics
  MISE_ENV=bench mise exec -- guidellm run -c bench/vllm-anchor-$cell.yaml --output "kind=json,path=.state/bench/vllm-native-anchor-$cell.json" > .state/bench/vllm-native-anchor-$cell.log 2>&1; echo "vllm-native-anchor-$cell: guidellm exit $?"
  curl -s "http://gb10-1:8000/metrics" > .state/bench/vllm-native-anchor-$cell.after.metrics
done
```

### 5. The Marlin diagnostic

On gb10-1, from the clone, native vLLM switched for one run to the row
`gemma-4-26B-A4B-NVFP4-marlin`: the pin's row plus `--moe-backend marlin`, so only the kernel for
NVFP4's MoE experts changes ([Models](../engines/vllm/models.md#the-rows)). Marlin is weight-only:
it runs the activations in 16 bits. The update restarts the unit on the release it is at, with no
build; the page cache wasn't dropped, since the start isn't timed against another. Then the start
time and the lines the start logged:

```sh
VLLM_MODEL=gemma-4-26B-A4B-NVFP4-marlin host/engines vllm-native update 2>&1 | tail -3
systemctl show vllm-server --property ActiveEnterTimestamp
journalctl -u vllm-server -o short-iso --since "$(systemctl show vllm-server --property ActiveEnterTimestamp --value)" | grep -E "MoE backend|Model loading took|torch.compile took|init engine|Application startup complete|Autotun.*(Loaded|ends)" | cut -c1-260
```

On the laptop, the path, the warm-up and its confirmation, and A' under its own name:

```sh
export GUIDELLM__SPEC__BACKEND__TARGET="http://gb10-1:8000"; model=nvidia/Gemma-4-26B-A4B-NVFP4
date -u +%FT%TZ; tailscale ping -c 3 gb10-1
curl -s "http://gb10-1:8000/v1/chat/completions" -H "Content-Type: application/json" -d "{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one sentence.\"}], \"chat_template_kwargs\": {\"enable_thinking\": true}}" | jq -c '.choices[0].message | {content, reasoning: (.reasoning|tostring|.[0:80])}'
curl -s "http://gb10-1:8000/metrics" | grep -E '^vllm:(request_success_total\{.*stop|num_requests_running)'
curl -s http://gb10-1:8000/metrics > .state/bench/vllm-native-marlin-anchor-a.before.metrics
MISE_ENV=bench mise exec -- guidellm run -c bench/vllm-anchor-a.yaml --output "kind=json,path=.state/bench/vllm-native-marlin-anchor-a.json" > .state/bench/vllm-native-marlin-anchor-a.log 2>&1; echo "vllm-native-marlin-anchor-a: guidellm exit $?"
curl -s http://gb10-1:8000/metrics > .state/bench/vllm-native-marlin-anchor-a.after.metrics
```

### 6. Back to the pin, and the end state

On gb10-1, from the clone: native vLLM back on the pin's row, then stopped and disabled, and the
end state read:

```sh
host/engines vllm-native update 2>&1 | tail -3
sudo -n systemctl stop vllm-server && sudo -n systemctl disable vllm-server
docker ps --all --filter name=vllm --filter name=llama --format "{{.Names}} {{.Status}}"; docker inspect --format "{{.Name}} restart={{.HostConfig.RestartPolicy.Name}}" vllm llama
systemctl is-active vllm-server llama-router; systemctl is-enabled vllm-server llama-router
readlink /opt/vllm/current; command ls /opt/vllm
```

### 7. The host stack and both methods' Python and torch

On gb10-1, after the runs, at about 16:55Z, with nothing serving: the rest of the host stack, then
Python, torch, and torch's CUDA in the image and in native's `current`:

```sh
. /etc/os-release; echo "$PRETTY_NAME"; nvidia-ctk --version | head -1; grep -E 'DGX_(SWBUILD|OTA)_VERSION' /etc/dgx-release; ls /var/run/reboot-required 2>&1; apt list --upgradable 2>/dev/null | grep -c upgradable
docker run --rm --gpus all --entrypoint python3 vllm/vllm-openai:v0.32.0 -c "import sys, torch; print(sys.version.split()[0], torch.__version__, torch.version.cuda)"
/opt/vllm/current/bin/python -c "import sys, torch; print(sys.version.split()[0], torch.__version__, torch.version.cuda)"
```

They printed `Ubuntu 24.04.5 LTS`, `NVIDIA Container Toolkit CLI version 1.20.1`,
`DGX_SWBUILD_VERSION="7.4.0"` and `DGX_OTA_VERSION="7.6.0"`, `ls: cannot access
'/var/run/reboot-required': No such file or directory`, and `0`; then `3.12.3 2.13.0+cu130 13.0`
from the image, after the image's start-up warning lines, which the session left out when it
displayed the output, and `3.12.16 2.13.0+cu130 13.0` natively.

### 8. Native's first start

The walk's first v0.32.0 start compiled from an empty compile cache but followed no page-cache
drop. So after the [Walkthrough](#walkthrough), from 18:22Z to 18:28Z, from the clone at 483e2b5,
the session measured native's first start as step 3 measured its warm one, with native's own
torch.compile cache, `/opt/vllm/cache/vllm/torch_compile_cache`, removed first; the container's
compile cache, `~/.cache/vllm`, wasn't touched. Before it, the session read where the install
script loads its steps from, and ran the preflight:

```sh
cd ~/repos/spike-model-engines && grep -n "^source\|^\. \|source " host/engines-vllm-native-install | head -5; bash -c "cd ~/repos/spike-model-engines; source host/vllm-native.sh && vllm_native_preflight && echo preflight-ok; vllm_native_versions 2>&1 | head -2" 2>&1 | tail -3
```

It printed line 17's `source …/vllm-native.sh` and `preflight-ok`. Then, on gb10-1 from the clone:
what was serving, the compile cache removed, the page cache dropped with its size before and after,
the memory available, native's install, the unit's start time, the ready line, the memory available
after, the lines vLLM logged for this start, and native stopped and disabled again:

```sh
cd ~/repos/spike-model-engines
systemctl is-active vllm-server llama-router; docker ps --format "{{.Names}}"
rm -rf /opt/vllm/cache/vllm/torch_compile_cache
grep ^Cached /proc/meminfo; sync && sudo -n /usr/sbin/sysctl vm.drop_caches=3; grep ^Cached /proc/meminfo
grep ^MemAvailable /proc/meminfo
host/engines vllm-native install 2>&1 | tail -3
systemctl show vllm-server --property ActiveEnterTimestamp
journalctl -u vllm-server -o short-iso --since "$(systemctl show vllm-server --property ActiveEnterTimestamp --value)" | grep -m 1 "Application startup complete"
grep ^MemAvailable /proc/meminfo
journalctl -u vllm-server --since "$(systemctl show vllm-server --property ActiveEnterTimestamp --value)" | grep -E "Model loading took|Available KV cache memory|KV cache size|Graph capturing finished|CUDA graph pool memory|torch.compile took|init engine|Directly load AOT"
sudo -n systemctl stop vllm-server && sudo -n systemctl disable vllm-server
systemctl is-active vllm-server; systemctl is-enabled vllm-server
```

It printed `inactive` and `inactive`, and no container; `Cached` 14,989,800 kB, then 187,632 kB;
MemAvailable 123,745,204 kB; the unit's `Created symlink …` line, `vllm-server serves v0.32.0 with
row gemma-4-26B-A4B-NVFP4 (nvidia/Gemma-4-26B-A4B-NVFP4) on port 8000 of the tailnet address`, and
`/version answers {"version":"0.32.0"}; torch 2.13.0+cu130, CUDA 13.0`; `ActiveEnterTimestamp=Tue
2026-10-27 14:22:06 EDT`; the ready line at `2026-10-27T14:28:30-04:00`; MemAvailable 17,931,360 kB;
vLLM's lines, with no `Directly load AOT`, since the start compiled; then `Removed
"/etc/systemd/system/multi-user.target.wants/vllm-server.service".`, `inactive`, and `disabled`. Its
figures are in [Startup](#startup) and [Footprint](#footprint).

### Model state

Each method's cells start from the same state: a cold start from a dropped page cache with that
method's compile cache warm, then the one warm-up request, then A', then B', with A''s prefix
cache. The Marlin diagnostic starts from a restart without the drop, then the warm-up, then A'.
Native's first start ([8. Native's first start](#8-natives-first-start)) is from a dropped page
cache with native's torch.compile cache removed, and no cell ran on it.
Before every set of cells the warm-up returned a reply (`Hello!`, with its reasoning),
`vllm:request_success_total` for `stop` read 1, and `vllm:num_requests_running` read 0: a
confirmed warm start, as bench-gb10-container required. `vllm:num_requests_running` was 0 in every
cell's first snapshot.

### Reading the figures

On the laptop, from the clone. The client figures come from bench-gb10-container's read-out
([Reading the figures](bench-gb10-container.md#reading-the-figures)) without its audio figure, in a
local script, `res.sh`, that reads each JSON file it is given:

```sh
for f in "$@"; do echo "== $f"; jq -c '.metadata as $v | .benchmarks[] | .metrics as $m | {streams: .config.strategy.streams, duration_s: (.duration|floor), requests: $m.request_totals, prompt_tokens: $m.prompt_token_count.successful.median, output_tokens: $m.output_token_count.successful.median, output_tok_s: ($m.output_tokens_per_second.successful.mean|.*10|round/10), ttft_ms: ($m.time_to_first_token_ms.successful | {median: (.median|round), p95: (.percentiles.p95|round)}), itl_ms: ($m.inter_token_latency_ms.successful | {median: (.median*100|round/100), p95: (.percentiles.p95*100|round/100)}), latency_s: ($m.request_latency.successful | {median: (.median*100|round/100), p95: (.percentiles.p95*100|round/100)})}' "$f"; done
```

The session ran it after each set of cells: after the container's, after native's (the last line
of step 4's block), and after the Marlin diagnostic's:

```sh
bash res.sh .state/bench/vllm-container-anchor-{a,b}.json
bash res.sh .state/bench/vllm-native-anchor-{a,b}.json
bash res.sh .state/bench/vllm-native-marlin-anchor-a.json
```

For the tables, it read all five again, with each cell's duration and start time:

```sh
bash res.sh .state/bench/vllm-container-anchor-{a,b}.json .state/bench/vllm-native-anchor-{a,b}.json .state/bench/vllm-native-marlin-anchor-a.json; for f in vllm-container-anchor-a vllm-container-anchor-b vllm-native-anchor-a vllm-native-anchor-b vllm-native-marlin-anchor-a; do echo "== $f"; jq '.benchmarks[].duration' .state/bench/$f.json; jq -r '.benchmarks[0].start_time? // empty' .state/bench/$f.json ; done
```

The server figures, bench-gb10-container's vLLM read-out
([vLLM: reading the figures](bench-gb10-container.md#vllm-reading-the-figures)), over the five
cells, with each cell's first `num_requests_running` and its start and end times:

```sh
for cell in vllm-container-anchor-a vllm-container-anchor-b vllm-native-anchor-a vllm-native-anchor-b vllm-native-marlin-anchor-a; do p=.state/bench/$cell; echo -n "$cell: "; awk '!/^#/ { k = $1; sub(/\{.*/, "", k); d[k] += (NR == FNR ? -$2 : $2) } END { m = "vllm:"; n = d[m "request_decode_time_seconds_count"]; p = d[m "prompt_tokens_total"]; c = d[m "prompt_tokens_cached_total"]; g = d[m "generation_tokens_total"]; printf "%d requests; prompt %d tokens, %d from the prefix cache, %.1f tok/s; generated %d tokens, %.1f tok/s\n", n, p, c, (p - c) / d[m "request_prefill_time_seconds_sum"], g, (g - n) / d[m "request_decode_time_seconds_sum"] }' $p.before.metrics $p.after.metrics; grep -h '^vllm:num_requests_running' $p.before.metrics; done; for f in vllm-container-anchor-a vllm-container-anchor-b vllm-native-anchor-a vllm-native-anchor-b vllm-native-marlin-anchor-a; do jq -r '.benchmarks[] | [.start_time, .end_time] | map(todate) | join(" ")' .state/bench/$f.json 2>/dev/null || jq '.benchmarks[0] | keys' .state/bench/$f.json; done
```

## Results

Run on 2026-10-27 on gb10-1: the walk from 11:47 to 12:20 (-04:00), and the comparison from 12:26 to
about 12:50 (-04:00), its cells from the laptop from 16:30:10Z to 16:48:07Z: the container's from
16:30:10Z to 16:32:49Z, native's from 16:40:11Z to 16:42:53Z, and the Marlin diagnostic's from
16:46:59Z to 16:48:07Z; and native's first start, after the walkthrough, from 14:22 to 14:28
(-04:00). No run took over 10 minutes: A' ran 68 to 70 s, B' 78 to 80 s, and the longest start
387 s.

### Install, update, and rollback

Native's walk, from v0.31.0 to v0.32.0, back, and forward again. Each step printed `/version` and
torch's CUDA; the builds' output is the guides' ([What the native install
runs](../engines/vllm/setup.md#what-the-native-install-runs),
[Native](../engines/vllm/update.md#native)).

| Step | Ran it | Printed | `/version`, torch |
|---|---|---|---|
| `install v0.31.0` | the architect | the build's phases; `vllm-server serves v0.31.0 with row gemma-4-26B-A4B-NVFP4 (nvidia/Gemma-4-26B-A4B-NVFP4) on port 8000 of the tailnet address` | `0.31.0`; `2.13.0+cu130`, CUDA 13.0 |
| `update v0.32.0` | the session | `built /opt/vllm/v0.32.0`; `vllm-server moved from v0.31.0 to v0.32.0`; `removed /opt/vllm/v0.31.0` | `0.32.0`; `2.13.0+cu130`, CUDA 13.0 |
| `update v0.31.0`, the rollback | the session | `built /opt/vllm/v0.31.0`; `vllm-server moved from v0.32.0 to v0.31.0`; `removed /opt/vllm/v0.32.0` | `0.31.0`; `2.13.0+cu130`, CUDA 13.0 |
| `update`, forward again | the session | `built /opt/vllm/v0.32.0`; `vllm-server moved from v0.31.0 to v0.32.0`; `removed /opt/vllm/v0.31.0` | `0.32.0`; `2.13.0+cu130`, CUDA 13.0 |
| `install`, a second time | the session | `vllm-server already serves v0.32.0 with row gemma-4-26B-A4B-NVFP4 (nvidia/Gemma-4-26B-A4B-NVFP4); nothing changed` | `{"version":"0.32.0"}` from the laptop, at about 16:20Z, with no `tailscale ping` beside it |

- After the forward update, `/opt/vllm` held `cache`, `current`, `python`, `row`, and `v0.32.0`,
  and `current` named `v0.32.0`: only the serving release is kept.
- The update downloaded only the 17 packages v0.31.0's install hadn't left in uv's cache; the
  rollback and the forward rebuilt their release from the cache (`Prepared 5 packages`), and each
  build's FlashInfer kernels came from the cache too
  ([Rolling back](../engines/vllm/update.md#rolling-back)).
- Every step waited out its start before it printed `moved`: the starts in [Startup](#startup),
  386, 361, and 335 s, each within the 10 minutes `update` waits.
- Switching for the comparison, `host/engines vllm install` printed `vllm is installed with
  vllm/vllm-openai:v0.32.0 and row gemma-4-26B-A4B-NVFP4 (nvidia/Gemma-4-26B-A4B-NVFP4) but stopped;
  docker start vllm starts it`, and `docker start vllm` started it. Native's `install` after the
  container stopped printed the unit's `Created symlink …` line, `vllm-server serves v0.32.0 with
  row gemma-4-26B-A4B-NVFP4 …`, and `/version answers {"version":"0.32.0"}; torch 2.13.0+cu130,
  CUDA 13.0`. The container's own install, update, and rollback are task 2's
  ([vllm-gb10-container](vllm-gb10-container.md)).

### Anchors

Each method's A' and B', beside bench-gb10-container's warm container anchors of 2026-10-26
([Anchors](bench-gb10-container.md#anchors)), which this session's container rows rerun.

| Cell | Run | Completed | Errored | Duration s | Output tok/s | TTFT median ms | TTFT p95 ms | ITL median ms | ITL p95 ms | Latency median s | Latency p95 s | Server prompt | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A' | container, 2026-10-26 | 8 | 0 | 68.10 | 30.1 | 241 | 320 | 32.33 | — | 8.49 | 8.56 | 5001.0 tok/s | 30.5 |
| A' | container | 8 | 0 | 68.70 | 29.8 | 215 | 228 | 32.79 | 32.87 | 8.58 | 8.60 | 4,224 tokens, 5051.4 tok/s | 30.1 |
| A' | native | 8 | 0 | 69.76 | 29.4 | 220 | 227 | 33.30 | 33.37 | 8.72 | 8.73 | 4,224 tokens, 4925.5 tok/s | 29.7 |
| B' | container, 2026-10-26 | 32 | 0 | 77.53 | 105.7 | 433 | 447 | 36.41 | — | 9.69 | 9.79 | 2206.9 tok/s | 27.0 |
| B' | container | 32 | 0 | 78.37 | 104.5 | 433 | 466 | 36.91 | 37.03 | 9.85 | 9.88 | 12,800 tokens, 2230.9 tok/s | 26.7 |
| B' | native | 32 | 0 | 79.77 | 102.7 | 445 | 481 | 37.48 | 37.78 | 9.99 | 10.08 | 12,800 tokens, 2166.6 tok/s | 26.3 |

Every request carried 528 prompt tokens and generated 256, on both methods; every guidellm run
exited 0. vLLM computed all of A''s 4,224 prompt tokens and took 4,096 of B''s 16,896 from its
prefix cache, on both, as in task 2.

- **The container's anchors held.** A' and B' match 2026-10-26's within run noise: output tok/s
  29.8 against 30.1 and 104.5 against 105.7 (1.0% and 1.1% lower), ITL 32.79 against 32.33 and
  36.91 against 36.41 ms (1.4% higher), and the server's generation 30.1 against 30.5 and 26.7
  against 27.0 tok/s. TTFT fell at A' (median 241 to 215 ms); the path was direct both days.
- **Native ran 1.3 to 1.7% below the container, about as far as the container moved since
  2026-10-26.** A' 29.4 against 29.8 output tok/s (1.3%), ITL 33.30 against 32.79 ms (+1.6%);
  B' 102.7 against 104.5 (1.7%), ITL 37.48 against 36.91 ms (+1.5%); the server's generation 29.7
  against 30.1 and 26.3 against 26.7 tok/s. Native is lower in both cells and on every rate, but
  each cell is one run, and the container's own A' and B' moved 1.0 to 1.4% between yesterday and
  today, so this session can't separate the gap from run noise.

### Startup

Every start of the pin's row on gb10-1 this day, from the start (the container's `StartedAt`, the
unit's `ActiveEnterTimestamp`) to `Application startup complete.`, with what vLLM logged: the
weights and their load time (`Model loading took`), the torch.compile time, FlashInfer's autotune
from `Autotuning process starts` to `ends`, the engine's init (`init engine (profile, create kv
cache, warmup model) took`), and the KV cache. The walk's starts weren't preceded by a page-cache
drop; the comparison's two timed starts were, and so was native's first start, measured after the
walkthrough with native's torch.compile cache removed ([8. Native's first
start](#8-natives-first-start)).

| Start | Method | Release | Page cache | Compile cache | Weights s | torch.compile s | FlashInfer autotune s | Init engine s | KV cache GiB, tokens | Cold start s |
|---|---|---|---|---|---|---|---|---|---|---|
| `install v0.31.0`, 11:47:09 | native | v0.31.0 | not dropped | empty | 138.9 | 27.42 | 155.0 | 221.44 | 75.84, 475,411 | 387 |
| `update v0.32.0`, 12:00:38 | native | v0.32.0 | not dropped | empty for v0.32.0: compiled from scratch, without a page-cache drop | 140.7 | 27.00 | 156.7 | 222.32 | 75.02, 470,295 | 386 |
| `update v0.31.0`, 12:07:36 | native | v0.31.0 | not dropped | warm (`Directly load AOT compilation`) | 120.9 | 0.30 | 178.7 | 211.57 | 74.18, 465,027 | 361 |
| `update`, 12:14:13 | native | v0.32.0 | not dropped | warm | 120.4 | 0.71 | 161.8 | 194.37 | 74.59, 467,617 | 335 |
| step 1, 12:26:09 | container | v0.32.0 | dropped | warm | 141.1 | 0.23 | 0.5 (`Loaded 34 configs`) | 34.45 | 74.64, 467,896 | 197.4 |
| step 3, 12:33:24 | native | v0.32.0 | dropped | warm | 122.2 | 0.25 | 161.9 | 193.96 | 74.34, 466,021 | 334 |
| step 5, Marlin, 12:43:12 | native | v0.32.0 | not dropped | empty for the row's flags | 118.7 | 26.73 | not read | 62.94 | not read | 197 |
| step 8, native's first start, 14:22:06 | native | v0.32.0 | dropped | empty (`torch_compile_cache` removed; no `Directly load AOT`) | 143.8 | 26.24 | not read | 221.06 | 74.95, 469,859 | 384 |

Times are -04:00; the container's start is 16:26:09.224Z, and it was ready at 16:29:26.662Z, 197.4
s. The native starts' times come from the journal to the second; native's first start was ready at
14:28:30, 384 s after 14:22:06.

- **Native's warm start took 334 s against the container's 197.4 s, and the difference is
  FlashInfer's MoE autotune.** Weights loaded in 122 s natively and 141 s in the container, and
  torch.compile loaded each method's saved compile in under a second; the init then took 193.96 s
  natively against 34.45 s in the container. In the container, FlashInfer logged `Loaded 34 configs
  from /home/vllm/.cache/vllm/flashinfer_autotune_cache/0.7.0.post1/121a/24be0327…/autotune_configs_dp0_rank0.json`
  and `Config cache hit` for `trtllm::fused_moe::gemm1` and `gemm2`, and its autotune ended 0.5 s
  after it started. Natively, vLLM logged `Using FlashInfer autotune cache file:
  /opt/vllm/cache/vllm/flashinfer_autotune_cache/0.7.0.post1/121a/24be0327…/autotune_configs_dp0_rank0.json`,
  loaded nothing, and tuned `gemm1` and `gemm2` over 17 token buckets, from 12:36:13 to 12:38:55,
  each `gemm1` pass logging `Skipped 16 unsupported tactic(s)`. The same hash names both
  directories, so both methods look for the same tuning.
- **Native never saves its tuning.** After every native start, its v0.32.0 directory,
  `/opt/vllm/cache/vllm/flashinfer_autotune_cache/0.7.0.post1/121a/24be0327…/`, was empty (made
  12:04, at v0.32.0's first start). The container's file is 9,635 bytes, written 2026-10-26 at 14:43
  (-04:00), during bench-gb10-container's first vLLM start, at
  `~/.cache/vllm/.cache/vllm/flashinfer_autotune_cache/0.7.0.post1/121a/24be0327…/`. v0.32.0's
  `kernel_warmup.py` saves only when FlashInfer's tuner records a change (`if tuner._dirty:
  tuner.save_configs(str(cache_path))`, beside the comment `Skip the rewrite when nothing was tuned
  this start`), and FlashInfer's `save_configs` skips a save whose file belongs to another
  environment. v0.31.0's start writes `autotune_configs.json` in another hash's directory, 505
  bytes, and its rollback start logged `Loaded 0 configs` from it, then tuned for 178.7 s. Why
  native's 160 s of tuning leaves no file, where the container's did, isn't established here.
- **Native's first start took 384 s, 50 s more than its warm start.** From a dropped page cache
  and an empty compile cache, it loaded the weights in 143.8 s (122.2 warm), compiled in 26.24 s
  (0.25 warm), and took 221.06 s for the engine's init (193.96 warm), as the walk's first v0.32.0
  start did without the drop (386 s, 27.00 s, 222.32 s). Its grep read no autotune line, but the
  init's 195 s outside torch.compile matches the walk's tuning starts.
- **Every native start tunes for 155 to 179 s, whichever release and compile cache.** So native's
  first start, which compiled from scratch, took 384 s, and its warm starts 334 to 361 s; the
  compile cache saves about 27 s, and the tuning costs about 160 s each start.
- **The Marlin start tuned no MoE GEMMs.** Its init took 62.94 s, 26.73 of them torch.compile,
  which compiled afresh for the row's flags; its autotune ended at 12:46:24, 16 s after
  torch.compile finished. It was ready 197 s after the restart, without a page-cache drop.

### Footprint

The comparison's two timed starts and native's first start, each from a dropped page cache. The
footprint is MemAvailable before the start less after it, beside what vLLM logged; each reserves
0.80 of the GB10's memory.

| Method | Cache before → after drop GiB | MemAvailable before GiB | MemAvailable after GiB | Footprint GiB | Weights GiB (logged) | KV cache GiB (logged) | CUDA graphs GiB (logged) | Consumed GiB (logged) | Free memory at startup GiB (logged) |
|---|---|---|---|---|---|---|---|---|---|
| Container | 15.26 → 0.18 | 117.99 | 17.38 | 100.61 | 18.13 | 74.64 | 0.10 + 0.07 | 21.85 | 114.03 of 121.63 |
| Native | 17.19 → 0.19 | 118.01 | 17.47 | 100.54 | 18.13 | 74.34 | 0.09 + 0.07 | 22.15 | 114.24 of 121.63 |
| Native's first start | 14.30 → 0.18 | 118.01 | 17.10 | 100.91 | 18.13 | 74.95 | 0.05 + 0.06 | not read | not read |

In kB, MemAvailable fell from 123,721,272 to 18,222,428 in the container and from 123,746,944 to
18,321,568 natively, 72 MiB apart. Both logged a peak activation of 0.81 GiB, the same 0.80
reservation of 97.3 GiB, and the same FLASHINFER_CUTLASS MoE backend. Native's consumed memory is
0.30 GiB more, and its KV cache 0.30 GiB less; the walk's starts logged KV caches from 74.18 to
75.84 GiB on the same row, so the KV cache moves start to start by more than the methods differ.
Both reach the GPU as the one CUDA device through CUDA 13.0 on the host's 580.178.04 driver: the
container through `--gpus all`, native through the cu130 wheels in its virtualenv.

Native's first start fell from 123,745,204 to 17,931,360 kB, 105,813,844 kB: 379 MiB more than
native's warm start and 308 MiB more than the container's, with a KV cache 0.61 GiB larger than the
warm start's. Its CUDA graph pool logged 0.06 GiB actual against 0.07 GiB estimated. Its consumed
memory and free memory at startup weren't in its grep.

### The Marlin diagnostic

A' on the Marlin row, natively, beside native's A' on FLASHINFER_CUTLASS and the day's container A':

| Cell | MoE backend | Completed | Errored | Duration s | Output tok/s | TTFT median / p95 ms | ITL median / p95 ms | Latency median / p95 s | Server prompt | Server gen tok/s |
|---|---|---|---|---|---|---|---|---|---|---|
| A' | FLASHINFER_CUTLASS, container | 8 | 0 | 68.70 | 29.8 | 215 / 228 | 32.79 / 32.87 | 8.58 / 8.60 | 4,224 tokens, 5051.4 tok/s | 30.1 |
| A' | FLASHINFER_CUTLASS, native | 8 | 0 | 69.76 | 29.4 | 220 / 227 | 33.30 / 33.37 | 8.72 / 8.73 | 4,224 tokens, 4925.5 tok/s | 29.7 |
| A' | MARLIN, native | 8 | 0 | 68.11 | 30.1 | 222 / 226 | 32.45 / 32.59 | 8.50 / 8.53 | 4,224 tokens, 4771.2 tok/s | 30.4 |

The start logged `Using 'MARLIN' NvFp4 MoE backend`, and its weights 18.12 GiB.

- **Marlin decoded 2.4% faster than FLASHINFER_CUTLASS, within the A' runs' spread.** 30.1 against
  29.4 output tok/s, ITL 32.45 against 33.30 ms, and 30.4 against 29.7 tok/s on the server. Five A'
  runs on FLASHINFER_CUTLASS, in task 2, bench-gb10-container (Triton and FlashInfer attention), and
  this session's two, ran 29.4 to 30.1 tok/s; Marlin's 30.1 is the top of that range, and level
  with the container's A' of 2026-10-26 (30.1 tok/s, ITL 32.33 ms).
- **The MoE kernel doesn't explain vLLM's slow NVFP4 decode on SM121.** llama.cpp serves the same
  model, gemma-4-26B-A4B in QAT Q4_0, at 65.7 output tok/s, ITL 13.97 ms, and 70.8 tok/s on the
  server at 1 stream ([Shapes](bench-gb10-container.md#shapes)); on Marlin vLLM reaches 30.1, 32.45
  ms, and 30.4, still under half. Marlin's prompt rate was 3% below FLASHINFER_CUTLASS's, 4771.2
  against 4925.5 tok/s.

### Network path and version, per method

| Run | `tailscale ping` | `/version` |
|---|---|---|
| Container | 16:29:55Z: direct, 1 ms (`tailscale ping`; addresses left out) | `0.32.0`; `/v1/models` `nvidia/Gemma-4-26B-A4B-NVFP4`, `max_model_len` 8192 |
| Native | 16:39:56Z: direct, 2 ms (`tailscale ping`; addresses left out) | `0.32.0`; the same model and length |
| Marlin diagnostic | 16:46:43Z: direct, 2 ms (`tailscale ping`; addresses left out) | `0.32.0`, from `update`'s own line on gb10-1 |
| The walk's second install | none run | `{"version":"0.32.0"}`, from the laptop at about 16:20Z |

### gb10-1's end state

Back on the pin, `update` printed `vllm-server restarted under the server flags of row
gemma-4-26B-A4B-NVFP4 (nvidia/Gemma-4-26B-A4B-NVFP4)` and `/version answers {"version":"0.32.0"};
torch 2.13.0+cu130, CUDA 13.0`; that start wasn't timed. The stop removed the unit's `wants`
symlink. The end-state read printed `llama` `Exited (0) 4 hours ago` and `vllm` `Exited (0) 20
minutes ago`, each with restart `unless-stopped`, stopped by hand so it stays stopped at boot;
`inactive` and `inactive`, then `disabled` and `disabled`, for `vllm-server` and `llama-router`;
`current` naming `v0.32.0`; and `/opt/vllm` holding `cache`, `current`, `python`, `row`, and
`v0.32.0`. Native vLLM, the vllm container, native llama.cpp, and the llama container are all
stopped, and none starts at boot.

## Walkthrough

On 2026-10-27, after the results above, the architect walked native vLLM from the guides, on
gb10-1 from `~/repos/spike-model-engines` at abfbe1f, and on the laptop. Times are -04:00 on gb10-1
and UTC on the laptop. Each command is as the architect ran it.

### Uninstall, install, update, and rollback

On gb10-1: the uninstall and its check, the install at v0.31.0 and setup's checks
([4. Check it serves](../engines/vllm/setup.md#4-check-it-serves)) with uv's read-back
([Reading it back](../engines/vllm/setup.md#reading-it-back)), the update to the pin, the
rollback, and forward again, each with its check, then a second install and the last start's
time and ready line:

```sh
host/engines vllm-native uninstall
command ls /opt/vllm
host/engines vllm-native install v0.31.0
systemctl status vllm-server --no-pager
readlink /opt/vllm/current
cat /opt/vllm/row
/opt/vllm/current/bin/vllm --version
/opt/vllm/current/bin/python -c "import torch; print(torch.__version__, torch.version.cuda)"
curl -s "http://$(tailscale ip -4):8000/version"
MISE_ENV=host mise exec -- uv pip list --python /opt/vllm/current | grep -E "^(vllm|torch|flashinfer)"
host/engines vllm-native update v0.32.0
readlink /opt/vllm/current; command ls /opt/vllm
host/engines vllm-native update v0.31.0
readlink /opt/vllm/current
host/engines vllm-native update
readlink /opt/vllm/current; command ls /opt/vllm
host/engines vllm-native install
systemctl show vllm-server --property ActiveEnterTimestamp
journalctl -u vllm-server -o short-iso-precise --no-pager | grep "Application startup complete" | tail -n 1
```

| Step | Printed | Checks |
|---|---|---|
| `host/engines vllm-native uninstall` | removed `/opt/vllm/current`, `/opt/vllm/v0.32.0`, `/opt/vllm/row`, `/opt/vllm/python`, and `/opt/vllm/cache`; `the architect's root steps stay: …` | `command ls /opt/vllm` printed nothing |
| `host/engines vllm-native install v0.31.0` | `Using CPython 3.12.16`; `Resolved 199 packages in 1.54s`, `Prepared 199 packages in 1m 53s`, `Installed 199 packages in 94ms`, `vllm==0.31.0` and `torch==2.13.0+cu130` among them; the cubin `Prepared 1 package in 46.16s`; the jit-cache `Resolved 9 packages in 43.99s`, `Prepared 9 packages in 42.37s`, its eight `sm*` wheels with `sm121a`; `built /opt/vllm/v0.31.0`; the unit's `Created symlink …`; `vllm-server serves v0.31.0 with row gemma-4-26B-A4B-NVFP4 (nvidia/Gemma-4-26B-A4B-NVFP4) on port 8000 of the tailnet address`; `/version answers {"version":"0.31.0"}; torch 2.13.0+cu130, CUDA 13.0` | setup's [4. Check it serves](../engines/vllm/setup.md#4-check-it-serves): status `enabled`, `active (running)` since 13:30:36 EDT, the main process `/opt/vllm/v0.31.0/bin/python /opt/vllm/current/bin/vllm serve nvidia/Gemma-4-26B-A4B-NVFP4 --host <addr> --port 8000 …`, `Memory: 5.7G (peak: 13.5G swap: 1.5G swap peak: 1.5G)`, and the journal's last lines `Application startup complete.` at 13:36:46 and `/health` and `/version` answering 200; `readlink` `v0.31.0`; `cat` the pin's row, its model and then its flags one a line; `--version` `0.31.0`; torch `2.13.0+cu130 13.0`; `/version` `{"version":"0.31.0"}`; uv's list, after `Using Python 3.12.16 environment at: /opt/vllm/current`, `flashinfer-cubin` `0.7.0.post1`, `flashinfer-jit-cache` `0.7.0.post1+cu130` and its eight `sm*` variants, `flashinfer-python` `0.7.0.post1`, `torch` `2.13.0+cu130`, `torch-c-dlpack-ext` `0.1.5`, `torchaudio` `2.11.0+cu130`, `torchcodec` `0.17.0+cu130`, `torchvision` `0.28.0+cu130`, and `vllm` `0.31.0` |
| `host/engines vllm-native update v0.32.0` | `Resolved 198 packages in 639ms`, `Prepared 17 packages in 17.19s`, `Installed 198 packages in 111ms`; the `FlashInfer kernels are disabled: …` line; the cubin prepared in 259ms; the jit-cache resolved in 652ms and prepared in 113ms; `built /opt/vllm/v0.32.0`; `vllm-server moved from v0.31.0 to v0.32.0`; `removed /opt/vllm/v0.31.0`; `/version answers {"version":"0.32.0"}; torch 2.13.0+cu130, CUDA 13.0` | `readlink` `v0.32.0`; `command ls /opt/vllm` lists `cache`, `current`, `python`, `row`, and `v0.32.0` |
| `host/engines vllm-native update v0.31.0`, the rollback | `Resolved 199 packages in 332ms`, `Prepared 5 packages in 18ms`, `Installed 199 packages in 124ms`; the cubin prepared in 250ms; the jit-cache resolved in 598ms and prepared in 100ms; `built /opt/vllm/v0.31.0`; `vllm-server moved from v0.32.0 to v0.31.0`; `removed /opt/vllm/v0.32.0`; `/version answers {"version":"0.31.0"}; torch 2.13.0+cu130, CUDA 13.0` | `readlink` `v0.31.0` |
| `host/engines vllm-native update`, forward again | `Resolved 198 packages in 540ms`, `Prepared 5 packages in 20ms`, `Installed 198 packages in 124ms`; the `FlashInfer kernels are disabled: …` line; the cubin prepared in 165ms; the jit-cache resolved in 694ms and prepared in 113ms; `built /opt/vllm/v0.32.0`; `vllm-server moved from v0.31.0 to v0.32.0`; `removed /opt/vllm/v0.31.0`; `/version answers {"version":"0.32.0"}; torch 2.13.0+cu130, CUDA 13.0` | `readlink` `v0.32.0`; `command ls /opt/vllm` lists `cache`, `current`, `python`, `row`, and `v0.32.0` |
| `host/engines vllm-native install`, a second time | `vllm-server already serves v0.32.0 with row gemma-4-26B-A4B-NVFP4 (nvidia/Gemma-4-26B-A4B-NVFP4); nothing changed` | `ActiveEnterTimestamp` `Tue 2026-10-27 13:53:51 EDT`; the ready line `2026-10-27T13:59:21.029659-04:00 … Application startup complete.` |

The uninstall removed `/opt/vllm/cache`, uv's package cache with it
([Removing native vLLM](../engines/vllm/uninstall.md#removing-native-vllm)), so the install
downloaded everything again: 199 packages in 1m 53s, and the kernel wheels in 46 and 42 s. The
update to the pin then downloaded the 17 packages v0.31.0 doesn't share, and the rollback and the
forward update rebuilt from the cache, as in the walk above ([Install, update, and
rollback](#install-update-and-rollback)).

### The four starts

The session read the four starts from the unit's journal after the walk; these reads aren't among
the architect's commands. On gb10-1, the journal since the walkthrough began, kept in a local file,
`walkthrough.journal`:

```sh
journalctl -u vllm-server -o short-iso --no-pager --since "2026-10-27 13:25"
```

then, on the laptop, its starts' lines:

```sh
grep -E 'Started vllm-server|Stopped vllm-server|Application startup complete|Loading weights took|torch.compile took|init engine|Autotuning process ends|Loaded [0-9]+ configs' walkthrough.journal | sed -E 's/gb10-1 (bash|systemd)\[[0-9]+\]: //; s/\(EngineCore pid=[0-9]+\) //' | cut -c1-150
```

From each start to `Application startup complete.`, with the weights' load time, torch.compile's
time, the engine's init, and when FlashInfer's autotune ended:

| Start | Release | Started | Ready | Cold start s | Weights s | torch.compile s | Init engine s | FlashInfer autotune |
|---|---|---|---|---|---|---|---|---|
| `install v0.31.0` | v0.31.0 | 13:30:36 | 13:36:46 | 370 | 114.56 | 26.76 | 219.31 | ends 13:36:34 |
| `update v0.32.0` | v0.32.0 | 13:39:53 | 13:46:01 | 368 | 124.51 | 26.30 | 219.61 | ends 13:45:56 |
| `update v0.31.0`, the rollback | v0.31.0 | 13:46:39 | 13:52:27 | 348 | 118.38 | 0.34 | 199.14 | `Loaded 0 configs` at 13:49:35; ends 13:52:20 |
| `update`, forward again | v0.32.0 | 13:53:51 | 13:59:21 | 330 | 116.11 | 0.74 | 189.76 | ends 13:59:17 |

The walk above started in 387, 386, 361, and 335 s ([Startup](#startup)); the walkthrough's starts
have the same shape. Each release's first start compiles, in about 27 s, since the uninstall
emptied the compile caches too; its later start loads that compile in under a second; and every
start tunes FlashInfer's MoE kernels again, the rollback's after loading 0 configs, so each start's
init takes 190 to 220 s.

### From the laptop

From the clone, each line at its own prompt: the path, the release, and the warm-up, then one
cell, `walk-a`, on `bench/vllm-anchor-a.yaml`, and its read-out:

```sh
mkdir -p .state/bench
date -u +%FT%TZ; tailscale ping -c 3 gb10-1
curl -s -m5 http://gb10-1:8000/version; echo
model=nvidia/Gemma-4-26B-A4B-NVFP4
curl -s "http://gb10-1:8000/v1/chat/completions" -H "Content-Type: application/json" -d "{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one sentence.\"}], \"chat_template_kwargs\": {\"enable_thinking\": true}}" | jq -c '.choices[0].message | {content, reasoning: (.reasoning|tostring|.[0:80])}'
export GUIDELLM__SPEC__BACKEND__TARGET="http://gb10-1:8000"
cell=walk-a
curl -s "http://gb10-1:8000/metrics" > .state/bench/vllm-native-$cell.before.metrics
MISE_ENV=bench mise exec -- guidellm run -c bench/vllm-anchor-a.yaml --output "kind=json,path=.state/bench/vllm-native-$cell.json" > .state/bench/vllm-native-$cell.log 2>&1; echo "vllm-native-$cell: guidellm exit $?"
curl -s "http://gb10-1:8000/metrics" > .state/bench/vllm-native-$cell.after.metrics
jq -c '.benchmarks[] | .metrics as $m | {streams: .config.strategy.streams, requests: $m.request_totals, output_tok_s: ($m.output_tokens_per_second.successful.mean|.*10|round/10), ttft_ms: ($m.time_to_first_token_ms.successful | {median: (.median|round), p95: (.percentiles.p95|round)}), itl_ms: ($m.inter_token_latency_ms.successful | {median: (.median*100|round/100), p95: (.percentiles.p95*100|round/100)})}' .state/bench/vllm-native-walk-a.json
```

At 2026-10-27T18:09:23Z, `tailscale ping` went direct on the LAN, 2 ms (addresses left out);
`/version` `{"version":"0.32.0"}`; the warm-up answered `Hello!`, with its reasoning. guidellm
exited 0:

| Cell | Completed | Output tok/s | TTFT median / p95 ms | ITL median / p95 ms |
|---|---|---|---|---|
| `walk-a` | 8 of 8 | 29.4 | 218 / 226 | 33.21 / 33.26 |
| Native A', above | 8 of 8 | 29.4 | 220 / 227 | 33.30 / 33.37 |

For the finding, the session read `walk-a`'s duration, token counts, and latency:

```sh
ls .state/bench/ | grep walk; jq -c '.benchmarks[] | {d: .duration, p: .metrics.prompt_token_count.successful.median, o: .metrics.output_token_count.successful.median, lat: .metrics.request_latency.successful | {median, p95: .percentiles.p95}}' .state/bench/vllm-native-walk-a.json; git ls-files .state | head -2
```

Every request carried 528 prompt tokens and generated 256, as in the cells above.

### Stop and end state

On gb10-1, from the home directory:

```sh
sudo -n systemctl stop vllm-server && sudo -n systemctl disable vllm-server
systemctl is-active vllm-server llama-router; systemctl is-enabled vllm-server llama-router
```

The first line removed the unit's `wants` symlink, and the second printed `inactive` and
`inactive`, then `disabled` and `disabled`, for `vllm-server` and `llama-router`. The end state is
otherwise unchanged: the `llama` and `vllm` containers exited. Native vLLM stays installed at
v0.32.0 under `/opt/vllm`, stopped and disabled.

Nothing in the walkthrough failed. The one request for clearer guidance came in slice 1's walk,
for more detail on uv's first install, and is folded into setup's [What the native install
runs](../engines/vllm/setup.md#what-the-native-install-runs).

## Findings

Dated 2026-10-27, on gb10-1, vLLM v0.32.0 in vLLM's image (CPython 3.12.3) and natively from its
cu130 wheel on uv-managed CPython 3.12.16, both with torch 2.13.0+cu130 on CUDA 13.0, on the host
stack above, the comparison from 12:26 to about 12:50 (-04:00), with the walk before it from 11:47
to 12:20.

What it means for evidence 6, vLLM on the GB10, container against bare metal:

- **Speed: parity within run noise.** Native served A' and B' 1.3 to 1.7% below the container,
  ITL 1.5 to 1.6% higher, the server's generation rate 1.3 to 1.5% lower: about as far as the
  container's own anchors moved between 2026-10-26 and this session (1.0 to 1.4%). The gap is in
  the same direction in both cells, and one run each can't separate it from noise; neither method
  gives a reason to choose it for speed.
- **GPU and memory: the same.** Both load the same 18.13 GiB of weights, reserve the same 0.80, and
  take 100.6 and 100.5 GiB of MemAvailable, 72 MiB apart; their KV caches differ by less than one
  method's moves from start to start. Both reach the GB10 through CUDA 13.0 on the host driver,
  with the same FlashInfer 0.7.0.post1 for SM121 and the same NVFP4 MoE backend.
- **Startup: the container starts 137 s faster, because only it keeps FlashInfer's MoE tuning.**
  The container's warm start took 197.4 s and native's 334 s, both from a dropped page cache with
  a warm compile cache. Native spends 155 to 179 s of every start tuning FlashInfer's MoE GEMMs and
  never writes the file its next start would load; the container loads its 34 configs, saved on
  2026-10-26, in under a second. Native's first start, from a dropped page cache and compiling from
  scratch, took 384 s (386 s in the walk, without the drop). The cause of the missing save isn't
  established; until it is, native's every start pays the tuning.
- **Install, update, and rollback: one command each, natively, as in the container.** Install
  builds a release's virtualenv with uv; update builds the new release while the old serves, stops
  it, starts the new one, and only once it answers removes the old; a rollback is an update to the
  older release, rebuilt from uv's cache; a second install changes nothing. Each step printed the
  version and torch's CUDA 13.0, and only the serving release stays. Native adds the architect's
  one-time root steps and uv ([Setup](../engines/vllm/setup.md#gb10-native)), and its compile
  caches outlive a release, so a release that comes back starts on its saved compile.

And the question bench-gb10-container left open:

- **The NVFP4 MoE kernel is not the cause of vLLM's slow NVFP4 decode on SM121.** On Marlin, A' ran
  30.1 tok/s against 29.4 on FLASHINFER_CUTLASS, +2.4%, at the top of the A' runs' range (29.4 to
  30.1) and still under half of llama.cpp's 65.7 on the same model in QAT Q4_0. With the attention
  backend ruled out before (bench-gb10-container) and the MoE kernel now, the gap's cause is
  neither; this task tested nothing further.

Also:

- **A container started again keeps its earlier log.** `docker logs --timestamps vllm | grep -m 1
  "Application startup complete"` returned 2026-10-26's line for this day's start. The setup and
  update guides now read the line from the container's start only
  ([6. Watch the cold start](../engines/vllm/setup.md#6-watch-the-cold-start-and-record-it)).
- **The walkthrough reproduced native within run noise.** Its A' ran 29.4 tok/s, TTFT 218 / 226
  ms, ITL 33.21 / 33.26 ms, against native's 29.4, 220 / 227, and 33.30 / 33.37. Its four starts,
  370, 368, 348, and 330 s, kept the walk's shape (387, 386, 361, 335 s): each release's first
  start compiles in about 27 s, a later one loads the compile, and every start tunes FlashInfer's
  MoE kernels again.
- **uv's read-backs left two entries in `~/.cache/uv`.** The guide's `uv pip list --python
  /opt/vllm/current` set no `UV_CACHE_DIR`, so uv cached what it read of the interpreter in the
  home directory's cache: on gb10-1, `~/.cache/uv/interpreter-v4/7b48229e3f1ca7d0/4a08f68991786be6.msgpack`
  at 11:58:52, from the walk's read-back, and `…/ef54843d1dbeff6d.msgpack` at 13:38:51, from the
  walkthrough's, naming `/opt/vllm/python` and `/opt/vllm/current`. They are small, and left in
  place; native's `uninstall` removes only what is under `/opt/vllm`, so it doesn't remove them. The
  guides' read-backs now point uv's cache at `/opt/vllm/cache/uv`, as the `engines` commands do
  ([Reading it back](../engines/vllm/setup.md#reading-it-back)), so they write no more there.
- **A reinstall after `uninstall` downloads everything again.** `uninstall` removes
  `/opt/vllm/cache`, uv's cache and the compile caches with it, so the next install fetched all 199
  packages (1m 53s) and the kernel wheels (46 and 42 s) and compiled each release afresh.
- **gb10-1's end state.** After the walkthrough and native's first start, native vLLM, the vllm
  container, native llama.cpp, and the llama container are all stopped and disabled, and none
  starts at boot; native vLLM stays installed at v0.32.0 under `/opt/vllm`. The first start's
  removal deleted native's own torch.compile cache, under `/opt/vllm/cache`, and that start
  compiled again; its grep read no save line, where each first start in the walk logged `saved AOT
  compiled function` and the release's next start loaded it.
