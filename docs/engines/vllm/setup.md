# Setting up vLLM

## GB10, in a container

Run these steps on gb10-1. gb10-2 is reserved for spike-ai-pipeline, and the spike installs
there only under a named borrow of it (`ai-hosting.md`, "Hosts and access"). Docker needs no
`sudo`, because the account is in the `docker` group.

### 1. Bring the host current and record its stack

The host steps are llama.cpp's, and they stay in one place: run
[Bring the host current](../llama.cpp/setup.md#1-bring-the-host-current), including the
`nvidia-ctk cdi generate` step after every upgrade, then
[Record the host stack](../llama.cpp/setup.md#2-record-the-host-stack). Record each output, with
the date, in the task's finding.

### 2. Prove the pinned image runs on the GPU

Pull the pinned image (`host/vllm.env`). The image's entrypoint is `vllm serve`, so each check
below replaces it with `--entrypoint`: first ask `vllm` for its version, then ask PyTorch, in the
image's Python, for the GPU it finds:

```sh
docker pull vllm/vllm-openai:v0.32.0
docker run --rm --gpus all --entrypoint vllm vllm/vllm-openai:v0.32.0 --version
docker run --rm --gpus all --entrypoint python3 vllm/vllm-openai:v0.32.0 -c \
  "import torch; p = torch.cuda.get_device_properties(0); print(torch.cuda.get_device_name(0), p.total_memory // 2**20, 'MiB')"
```

`--version` prints `0.32.0`. The second command prints the GB10's name and the memory CUDA sees
on it, in MiB; an error that no CUDA device is available means the container didn't reach the
GPU.

### 3. Get the clone onto the host

The `engines` commands run from the clone of this repository that llama.cpp's setup made in the
home directory ([Get the clone onto the host](../llama.cpp/setup.md#4-get-the-clone-onto-the-host)).
Bring it current:

```sh
cd spike-model-engines
git pull
```

Every later command on the host runs from `spike-model-engines`.

### 4. Check the model store

vLLM shares llama.cpp's model store, `/srv/models`, as its Hugging Face cache. llama.cpp's setup
creates it ([Create the model store](../llama.cpp/setup.md#5-create-the-model-store)); check that
it is there and owned by your account; this prints your account's name:

```sh
stat -c %U /srv/models
```

### 5. Install

`install` refuses while llama.cpp's `llama` container runs or its native `llama-router` unit is
active, or native vLLM's `vllm-server` is ([GB10, native](#gb10-native)), since one engine serves
per host at a time. See whether the container runs:

```sh
docker ps --filter name=llama
```

When it lists `llama`, stop it. `docker stop` keeps it stopped across a reboot, and `docker start
llama` brings it back once `vllm` is stopped:

```sh
docker stop llama
```

When native llama.cpp serves instead, stop `llama-router` as its
[Setup](../llama.cpp/setup.md#4-stop-it) does, and when native vLLM serves, stop `vllm-server` as
[5. Stop it](#5-stop-it) does. Then install:

```sh
host/engines vllm install
```

`install` pulls the pinned image and starts one container, `vllm`, running `vllm serve` on the pin's
default row, `gemma-4-26B-A4B-NVFP4`: the model `nvidia/Gemma-4-26B-A4B-NVFP4` and its server flags.
That is the `cuda` flavor, which it picks on a host without an AMD GPU
([Update](update.md#the-flavor)): vLLM's CUDA image, with `--gpus all`. It runs as your account,
with `--restart unless-stopped`, so Docker starts it again after a reboot, and publishes port 8000
on the host's tailnet IPv4 address only. The row's flags are in `host/vllm-rows`
([Models](models.md#the-rows)):

| Flag | Value | Why |
|---|---|---|
| `--max-num-seqs` | `4` | 4 sequences decode at once, and a fifth waits, as llama.cpp's 4 slots. |
| `--max-model-len` | `8192` | 8192 tokens a sequence, as each of llama.cpp's slots. |
| `--gpu-memory-utilization` | `0.80` | vLLM reserves 0.80 of the GB10's memory for the weights and the KV cache, and leaves the rest to the host. |
| `--kv-cache-dtype` | `bfloat16` | A BF16 KV cache. The checkpoint declares a static FP8 KV cache but ships no calibrated k/v scales, so vLLM would quantize it with a scale of 1.0 (it warns `Using KV cache scaling factor 1.0 for fp8_e4m3`); BF16 avoids that. |
| `--reasoning-parser` | `gemma4` | The reply's reasoning comes back apart from its content ([API](api.md#a-chat-completion)). |
| `--enable-auto-tool-choice`, `--tool-call-parser` | `gemma4` | Tool calls come back as OpenAI tool calls. |

Gemma 4's vision encoder loads too, and the model's own generation config sets its sampling:
temperature 1.0, top_p 0.95, top_k 64. Two directories are mounted:

- `/srv/models`, as the Hugging Face cache (`HF_HUB_CACHE`), so the model lands in
  `/srv/models/models--nvidia--Gemma-4-26B-A4B-NVFP4`, with its weight files in the shared
  store at `/srv/models/blobs` ([Models](models.md#the-first-download)).
- `~/.cache/vllm`, the compile cache, as the container's home. vLLM's torch.compile cache and the
  kernels it builds land there, so a later start skips compiling them again.

It prints the image, the model, and the port it serves on, without the address. A second run changes
nothing and says so; when `vllm` is stopped, it says `docker start vllm` starts it, and leaves it
stopped. It fails, changing nothing, while `llama`, `llama-router`, or `vllm-server` runs, when
`/srv/models` is missing, when the host has no tailnet IPv4 address, or when `vllm` already runs
another release, another model, or other server flags; [Update](update.md) moves a running one.
Given a release, such as `v0.31.0`, it installs that release instead of the pin; given
`VLLM_MODEL=<row id>` before it, it serves that row instead of the default
([Models](models.md#serving-another-row-for-one-run)).

### 6. Watch the cold start, and record it

A timed cold start begins from an empty page cache, dropped just before `install` or `update`
starts the container, with the command llama.cpp's setup allows
([Allow the page-cache drop](../llama.cpp/setup.md#7-allow-the-page-cache-drop)).

Unless the model is pre-staged ([Models](models.md#pre-staging-models-with-hf)), the first start
downloads it into the store ([Models](models.md#the-first-download)), then loads and compiles
it. Follow the log until the server is ready; it prints `Application startup complete.` once it
answers. Stop following with Ctrl-C, which leaves the container running:

```sh
docker logs -f vllm
```

Instead of following the log, you can poll `/health` every 5 s until it answers 200; the poll
then prints the time, in UTC, so you know the timing lines below are ready to read:

```sh
until [ "$(curl -s -o /dev/null -w '%{http_code}' "http://$(tailscale ip -4):8000/health")" = 200 ]; do sleep 5; done; date -u
```

Then time the cold start, from the container's start to the `Application startup complete.`
line:

```sh
docker inspect --format '{{.State.StartedAt}}' vllm
docker logs --timestamps --since "$(docker inspect --format '{{.State.StartedAt}}' vllm)" vllm 2>&1 | grep -m 1 "Application startup complete"
```

The log is read only since the container's start, because a container started again, with
`docker start`, `docker restart`, or a reboot, keeps the log of every earlier start: without
`--since`, `grep -m 1` finds the first start's line, not this one's
([vllm-gb10-native](../../findings/vllm-gb10-native.md#1-the-containers-cold-start)). The
difference between the two times is the cold start. Record it, with the date, the release,
and whether the start downloaded the model or compiled from an empty compile cache, in the
task's finding. Record every cold start this way: each install, update, restart, or reboot.

Check that the container is up and the server answers:

```sh
docker ps --filter name=vllm
curl -s -o /dev/null -w '%{http_code}\n' "http://$(tailscale ip -4):8000/health"
```

`docker ps` shows `vllm` with status `Up`; `/health` prints `200` once the server is ready.

### 7. Check that llama.cpp refuses

While `vllm` runs, llama.cpp's install refuses, naming `docker stop vllm`, and changes nothing:

```sh
host/engines llama install
```

## GB10, native

Native vLLM is the container's exact release, run on the host instead: vLLM's aarch64 wheel for
the release, built for CUDA 13.0, with torch from PyTorch's cu130 index, as the image's is, on
CPython 3.12, the image's Python, so only the hosting method differs. `vllm serve` runs under a
system unit, `vllm-server`, on the container's row, model store, and port, 8000, of the tailnet
address. Run these steps on gb10-1 after the container's steps 1, 3, and 4: the host current, its
stack recorded, the clone current, and `/srv/models` there.

Each release lives in its own Python virtualenv, `/opt/vllm/<release>`, and two names there say
what serves: `current`, a link to the release, and `row`, a file holding the row the server
serves, its model on the first line and then its server flags, one word a line, written from
`host/vllm-rows` by `install` and `update`. The unit names neither a release nor a row; it reads
both as it starts, so switching rows or changing a flag needs no root. Everything else native
vLLM writes stays under `/opt/vllm` too: uv's Python in `/opt/vllm/python`, and uv's package
cache and vLLM's, Triton's, and FlashInfer's compile caches in `/opt/vllm/cache`. None of it is
in the home directory, where the container's compile cache is (`~/.cache/vllm`), so uninstalling
either hosting method leaves the other's caches alone.

### 1. The architect's root steps

Three root steps, once, from the clone; [Uninstall](uninstall.md#removing-the-native-root-steps)
removes them. The unit file and the sudoers rule name the account `jaime`; on another account,
edit both to its name (`id -un` prints it) first.

Create `/opt/vllm`, owned by your account, so installs and updates need no root:

```sh
sudo install -d -o "$(id -un)" -g "$(id -gn)" /opt/vllm
```

Install the unit, `host/vllm-server.service`, and have systemd read it:

```sh
sudo install -m 0644 host/vllm-server.service /etc/systemd/system/vllm-server.service
sudo systemctl daemon-reload
```

The unit runs `/opt/vllm/current/bin/vllm serve` as your account, on the model and flags in
`/opt/vllm/row`, with `--host` set to `tailscale ip -4` as it starts, on `--port 8000`, the order
the container's command has. It sets `HF_HUB_CACHE` to `/srv/models`, and points the compile
caches into `/opt/vllm/cache`: `XDG_CACHE_HOME`, `VLLM_CACHE_ROOT`, `TRITON_HOME`, and
`FLASHINFER_WORKSPACE_BASE`. It requires and follows `tailscaled`, as `llama-router` does, and
restarts 5 seconds after a failure. A start takes minutes, but vLLM tells systemd nothing when it
is ready, so systemd counts the unit started at once and the `engines` commands wait on `/health`
instead. It is installed but neither enabled nor started; the `engines` commands enable and start
it while native vLLM serves.

Allow the `engines` commands to run the unit's five `systemctl` commands, and nothing else,
without a password: a sudoers rule naming `systemctl start`, `stop`, `restart`, `enable`, and
`disable vllm-server` exactly, as llama.cpp's native rule does
([llama.cpp's root steps](../llama.cpp/setup.md#1-the-architects-root-steps)). The rule is
`host/vllm-server.sudoers`; `visudo` checks it, and `install` copies it, read-only and root's,
only when the check passes:

```sh
sudo visudo -cf host/vllm-server.sudoers && sudo install -m 0440 host/vllm-server.sudoers /etc/sudoers.d/vllm-server
```

Check the rule without the password `sudo` just cached: `sudo -k` forgets it, and `sudo -n` fails
instead of asking for one. Stopping the unit while it isn't running changes nothing; without the
rule, `sudo` prints `sudo: a password is required`:

```sh
sudo -k
sudo -n systemctl stop vllm-server
```

### 2. uv

#### What it is

uv is Astral's Python package and project manager, one binary that does what pip, venv, and
pyenv do. Native vLLM uses three of its parts:

- **Managed Python.** uv downloads a standalone CPython build of the version asked for and keeps
  it in a directory of its own, apart from the host's Python, which it never touches.
- **Virtualenvs.** `uv venv` makes a Python virtualenv, a directory with its own `bin/python` and
  `site-packages`, so each vLLM release has its own packages and two releases never share one.
- **Package installs.** `uv pip install` installs packages into a virtualenv, as pip does, and
  keeps each package it downloads in its cache, so installing the same package again, as a
  rollback does, links it from the cache rather than downloading it.

#### How it is set up

uv is pinned in the host environment, `mise.host.toml`, at 0.13.6, beside hf
([Pre-staging models with hf](models.md#pre-staging-models-with-hf)), and the `engines` commands
run it through mise from the clone, as hf runs. They never install it: on the host, from the
clone, install the host environment's tools once before the first native install, and again
after a pull that moves a pin:

```sh
MISE_ENV=host mise install
```

The first time, it installs uv, `uv@0.13.6`, and ends `installed 1 tool`; once uv is there, it
prints `mise all tools are installed`.

The `engines` commands point uv at `/opt/vllm`: `UV_PYTHON_INSTALL_DIR` at `/opt/vllm/python`,
for its Python, and `UV_CACHE_DIR` at `/opt/vllm/cache/uv`, for its cache.

#### What the native install runs

For each release, such as v0.31.0, `install` and `update` run the phases below, in order, and each
prints as it runs. The output shown is v0.31.0's first install on gb10-1, as `host/engines
vllm-native install v0.31.0` printed it, with uv's package lists cut to the lines worth reading.

1. **Preflight.** The checks `install` lists under [3. Install](#3-install): no other engine
   serving, the root steps done, uv installed, `/srv/models` there, a tailnet address. It prints
   nothing unless it refuses, and a refusal changes nothing.

2. **The virtualenv.** `uv venv --python 3.12 --managed-python --seed /opt/vllm/v0.31.0` makes the
   release's virtualenv on uv-managed CPython 3.12 (`--managed-python` refuses the host's own
   Python), which uv downloads into `/opt/vllm/python` the first time. `--seed` installs pip into
   it, as FlashInfer's kernel install expects:

   ```text
   Using CPython 3.12.16
   Creating virtual environment with seed packages at: /opt/vllm/v0.31.0
    + pip==26.2.2
   Activate with: source /opt/vllm/v0.31.0/bin/activate
   ```

   The `Activate` line is uv's own; nothing activates the virtualenv, since the unit and the
   `engines` commands run its `bin/` directly.

3. **vLLM and its packages.** `uv pip install --python /opt/vllm/v0.31.0 vllm==0.31.0
   --torch-backend=cu130` installs vLLM at the release, with every package it depends on, taking
   torch and the PyTorch packages from PyTorch's CUDA 13.0 index, as the image's torch comes,
   rather than PyPI's build:

   ```text
   Using Python 3.12.16 environment at: /opt/vllm/v0.31.0
   Resolved 199 packages in 1.50s
   Prepared 199 packages in 1m 52s
   Installed 199 packages in 117ms
    + agent-detector==2.0.0
   ```

   and then a `+` line for each of the 199 packages, in alphabetical order. `Prepared` is the
   download into uv's cache, about 2 minutes on a first install; a package the cache already
   holds isn't downloaded again ([Rolling back](update.md#rolling-back)). In the list, read these:

   ```text
    + cuda-toolkit==13.0.3.0
    + flashinfer-python==0.7.0.post1
    + torch==2.13.0+cu130
    + torchaudio==2.11.0+cu130
    + torchvision==0.28.0+cu130
    + transformers==5.17.0
    + triton==3.7.1
    + vllm==0.31.0
   ```

   `vllm` is the release. `+cu130` on torch and its companions marks PyTorch's CUDA 13.0 build; a
   torch without it came from PyPI. `flashinfer-python` is the FlashInfer whose kernels the next
   phase installs. v0.32.0 installs 198 packages, with `vllm==0.32.0` and `transformers==5.19.0`,
   on the same torch and FlashInfer.

4. **FlashInfer's kernels.** `vllm download-kernels`, from the virtualenv, installs FlashInfer's
   precompiled kernels into it, so a start neither downloads nor compiles them. vLLM v0.31.0 has
   no `download-kernels`, so for it the step runs what the command runs, FlashInfer's own `python
   -m flashinfer download-kernels`. Either way FlashInfer installs two wheels for its version,
   each under a `===` header, printing the uv command it runs and then uv's output. First the
   cubin wheel, its precompiled kernels:

   ```text
   === Cubin Wheel Install ===
   FlashInfer version: 0.7.0.post1
   Wheel index: https://flashinfer.ai/whl
   Requirement: flashinfer-cubin==0.7.0.post1
   Command: /home/jaime/.local/share/mise/installs/uv/0.13.6/.mise-bins/uv pip install --python /opt/vllm/v0.31.0/bin/python --upgrade --no-deps --index-url https://flashinfer.ai/whl flashinfer-cubin==0.7.0.post1
   Using Python 3.12.16 environment at: /opt/vllm/v0.31.0
   Resolved 1 package in 322ms
   Prepared 1 package in 45.24s
   Installed 1 package in 594ms
    + flashinfer-cubin==0.7.0.post1
   ✅ flashinfer-cubin installed successfully.
   ```

   then the JIT cache, the kernels FlashInfer would otherwise compile on first use, for CUDA 13.0,
   as one wheel and a wheel for each GPU architecture it builds for. `sm121a` is the GB10's:

   ```text
   === JIT Cache Wheel Install ===
   FlashInfer version: 0.7.0.post1
   CUDA version: 13.0
   Wheel CUDA label: cu130
   Install mode: all
   Wheel index: https://flashinfer.ai/whl/cu130
   Requirement: flashinfer-jit-cache==0.7.0.post1+cu130
   Command: /home/jaime/.local/share/mise/installs/uv/0.13.6/.mise-bins/uv pip install --python /opt/vllm/v0.31.0/bin/python --upgrade --index-url https://flashinfer.ai/whl/cu130 flashinfer-jit-cache==0.7.0.post1+cu130
   Using Python 3.12.16 environment at: /opt/vllm/v0.31.0
   Resolved 9 packages in 43.07s
   Prepared 9 packages in 47.45s
   Installed 9 packages in 112ms
    + flashinfer-jit-cache==0.7.0.post1+cu130
    + flashinfer-jit-cache-sm100a==0.7.0.post1+cu130
    + flashinfer-jit-cache-sm103a==0.7.0.post1+cu130
    + flashinfer-jit-cache-sm110a==0.7.0.post1+cu130
    + flashinfer-jit-cache-sm120f==0.7.0.post1+cu130
    + flashinfer-jit-cache-sm121a==0.7.0.post1+cu130
    + flashinfer-jit-cache-sm80==0.7.0.post1+cu130
    + flashinfer-jit-cache-sm89==0.7.0.post1+cu130
    + flashinfer-jit-cache-sm90a==0.7.0.post1+cu130
   ✅ flashinfer-jit-cache installed successfully.
   ```

   On v0.32.0, `vllm download-kernels` prints one line more first, before `=== Cubin Wheel
   Install ===`:

   ```text
   FlashInfer kernels are disabled: flashinfer-cubin is not installed and nvcc (CUDA_HOME, CUDA_PATH, PATH or /usr/local/cuda) or ninja (PATH) is missing. Set CUDA_HOME to a CUDA toolkit and put ninja on PATH, or run `vllm download-kernels`.
   ```

   It isn't a failure. The command imports vLLM, and vLLM checks at import whether FlashInfer's
   kernels can be had; before the install they can't, so it says so, and the command then
   installs them. v0.31.0's step runs FlashInfer's command, which doesn't import vLLM, and prints
   no such line, and no server start prints it once the kernels are in.

5. **Built.** The release's directory is marked whole, and `install` or `update` says so:

   ```text
   built /opt/vllm/v0.31.0
   ```

   A phase that fails leaves the directory unmarked, and the next `install` or `update` removes
   it, saying `removed /opt/vllm/v0.31.0, a build that didn't finish`, and starts again.

6. **The row and the link.** The row file, `/opt/vllm/row`, is written from `host/vllm-rows`,
   and `current` is pointed at the release, silently. `update` stops `vllm-server` first
   ([Update](update.md#native)).

7. **The start.** `vllm-server` is enabled, when it isn't, and started. Enabling it is the one
   line systemd prints:

   ```text
   Created symlink /etc/systemd/system/multi-user.target.wants/vllm-server.service → /etc/systemd/system/vllm-server.service.
   ```

   and then nothing, for minutes, while the server loads the model, compiles it, and captures
   its CUDA graphs, until `/health` answers (at most 10 minutes). To watch the start, follow the
   unit's journal from a second terminal on the host; it reaches `Application startup
   complete.` when the server answers, and Ctrl-C stops following it:

   ```sh
   journalctl -fu vllm-server
   ```

8. **What serves.** `install` names the release, the row, and its model, then reads what the
   server reports: its `/version`, and torch's version with the CUDA version it was built for:

   ```text
   vllm-server serves v0.31.0 with row gemma-4-26B-A4B-NVFP4 (nvidia/Gemma-4-26B-A4B-NVFP4) on port 8000 of the tailnet address
   /version answers {"version":"0.31.0"}; torch 2.13.0+cu130, CUDA 13.0
   ```

   `update` prints what moved and what it removed in place of the first line
   ([Update](update.md#native)).

#### Reading it back

On the host, from the clone, read uv's version, the Pythons uv has installed under
`/opt/vllm/python`, and the packages of the release `current` names. The last two read an
interpreter, and uv caches what it learns of one, so they point uv's cache at `/opt/vllm/cache/uv`,
as the `engines` commands do; without it, uv writes those entries to `~/.cache/uv`, outside
`/opt/vllm`, where `uninstall` doesn't reach:

```sh
MISE_ENV=host mise exec -- uv --version
MISE_ENV=host UV_CACHE_DIR=/opt/vllm/cache/uv UV_PYTHON_INSTALL_DIR=/opt/vllm/python mise exec -- uv python list --only-installed --managed-python
MISE_ENV=host UV_CACHE_DIR=/opt/vllm/cache/uv mise exec -- uv pip list --python /opt/vllm/current
```

At v0.31.0 the first prints `uv 0.13.6 (aarch64-unknown-linux-gnu)`, and the second the one
Python uv installed:

```text
cpython-3.12.16-linux-aarch64-gnu    /opt/vllm/python/cpython-3.12-linux-aarch64-gnu/bin/python3.12
```

The third prints `Using Python 3.12.16 environment at: /opt/vllm/current`, then a `Package` and
`Version` table of every package phases 3 and 4 installed. Read these rows in it: `vllm`
`0.31.0`; `torch` `2.13.0+cu130`; `pip` `26.2.2`; `flashinfer-python` and `flashinfer-cubin`
`0.7.0.post1`; and `flashinfer-jit-cache` `0.7.0.post1+cu130`, with its eight `sm*` variants,
`flashinfer-jit-cache-sm121a` among them. Then read the layout, what `/opt/vllm` holds, the
release `current` names, and the row:

```sh
command ls /opt/vllm; readlink /opt/vllm/current; cat /opt/vllm/row
```

`ls` lists `cache  current  python  row  v0.31.0`. `readlink` prints `v0.31.0`: `current` is a
relative link, to the release beside it, not an absolute path. `cat` prints the row's model, then
its flags, one word a line:

```text
nvidia/Gemma-4-26B-A4B-NVFP4
--max-num-seqs
4
--max-model-len
8192
--gpu-memory-utilization
0.80
--kv-cache-dtype
bfloat16
--reasoning-parser
gemma4
--enable-auto-tool-choice
--tool-call-parser
gemma4
```

### 3. Install

This guide installs v0.31.0, which [Update](update.md#native) then moves to the pin:

```sh
host/engines vllm-native install v0.31.0
```

`install` builds the release's virtualenv ([What the native install
runs](#what-the-native-install-runs)), writes the pin's default row, `gemma-4-26B-A4B-NVFP4`, into
`/opt/vllm/row`, points `current` at the release, enables and starts `vllm-server`, and waits for
`/health` to answer, for at most 10 minutes. It prints uv's and the kernel install's output, then
the release, the row, and the port it serves on, then what the server reports: its `/version`, and
torch's version with the CUDA version it was built for, which reads 13.0; [What the native install
runs](#what-the-native-install-runs) shows each phase's output. With no release, it
installs the pin, v0.32.0; given `VLLM_MODEL=<row id>` before it, it serves that row instead of the
default ([Models](models.md#serving-another-row-for-one-run)).

A second run changes nothing and says `vllm-server already serves v0.31.0 with row
gemma-4-26B-A4B-NVFP4 (nvidia/Gemma-4-26B-A4B-NVFP4); nothing changed`, at once, with no build
([4. Check it serves](#4-check-it-serves)); when `vllm-server` is stopped, it enables and starts it
again. It fails, changing nothing:

- while the `llama` or `vllm` container runs, or `llama-router` is active, since one engine
  serves per host at a time;
- before the root steps are done, naming the one missing: `/opt/vllm`, the unit, or the sudoers
  rule; or before the host environment's uv is installed ([How it is set up](#how-it-is-set-up));
- when `/srv/models` is missing, or the host has no tailnet IPv4 address;
- when native vLLM is already at another release, or its row file holds another row or other
  flags; [Update](update.md#native) moves either;
- for a release that isn't one, such as `0.31`, or a `VLLM_MODEL` with no row, before it reads
  anything on the host.

The other engines' steps refuse in turn while `vllm-server` is active, saying how to stop it:
both containers', and native llama.cpp's.

### 4. Check it serves

```sh
systemctl status vllm-server --no-pager
readlink /opt/vllm/current
cat /opt/vllm/row
/opt/vllm/current/bin/vllm --version
/opt/vllm/current/bin/python -c "import torch; print(torch.__version__, torch.version.cuda)"
curl -s "http://$(tailscale ip -4):8000/version"
```

`systemctl status` shows `enabled` and `active (running)`; `readlink` prints the release;
`cat` prints the row's model and flags; `--version` and `/version` print the release without its
`v`; torch prints its version and `13.0`. Call the server as the container's
([API](api.md)): the port and the row are the same. The server's log, the container's `docker
logs vllm`, is the unit's journal:

```sh
journalctl -u vllm-server -n 20 --no-pager
```

Install again, at the release that serves, and it changes nothing. At the pin, after the walk
([Update](update.md#the-walk)):

```sh
host/engines vllm-native install
```

```text
vllm-server already serves v0.32.0 with row gemma-4-26B-A4B-NVFP4 (nvidia/Gemma-4-26B-A4B-NVFP4); nothing changed
```

From the laptop, the server answers on the host's tailnet name ([API](api.md#version)):

```sh
curl -s -m5 http://gb10-1:8000/version
```

It prints `{"version":"0.32.0"}` at the pin.

A cold start is timed from the unit's start to the `Application startup complete.` line, as the
container's is from its start ([6. Watch the cold start](#6-watch-the-cold-start-and-record-it)):

```sh
systemctl show vllm-server --property ActiveEnterTimestamp
journalctl -u vllm-server -o short-iso-precise --no-pager | grep "Application startup complete" | tail -n 1
```

On gb10-1 a native start takes longer than the container's, 334 s against 197 s, both from a
dropped page cache with a warm compile cache. Nearly all the difference is FlashInfer tuning its
MoE kernels, which native vLLM does again at every start
([vllm-gb10-native](../../findings/vllm-gb10-native.md#startup)).

### 5. Stop it

Native vLLM is enabled only while it serves, so stopping it also disables it, and a reboot
leaves it stopped. Both commands are ones the sudoers rule allows:

```sh
sudo -n systemctl stop vllm-server && sudo -n systemctl disable vllm-server
```

Install, given the release `current` names, enables and starts it again: with no release at the
pin, or `host/engines vllm-native install v0.31.0` at v0.31.0.

## Framework, in a container

Run these steps on the Framework, `framework`: Omarchy on an AMD Strix Halo whose GPU is gfx1151
([llama.cpp's Setup](../llama.cpp/setup.md#framework-in-a-container)). vLLM runs there in its
official ROCm image, `vllm/vllm-openai-rocm:v0.32.0`, the same release as the GB10's CUDA image.
The image brings its own ROCm runtime; the host gives it only the kernel's GPU driver, through
two device files, `/dev/kfd` and `/dev/dri`, in place of the NVIDIA Container Toolkit's `--gpus
all`, with no `--group-add`, seccomp, or ptrace options, since the device files are open to every
account on this host. The `engines` commands pick that image, the `rocm` flavor, on any host with
an AMD GPU, and with it the flavor's default row, `gpt-oss-120b`
([Update](update.md#the-flavor)).

Each step says whose it is. Commands with `sudo` are root steps, the architect's; the rest the
session runs, as `jaime`. Each Framework session owns the host: nothing else serves on it while
one runs.

### 1. The root steps already in place

vLLM adds no root step on the Framework. llama.cpp's Framework setup made every one it needs,
and they hold for vLLM's container too:

- [Bring the host current](../llama.cpp/setup.md#1-bring-the-host-current-1), `omarchy update`, the
  architect's at every session's start, with a newer installed kernel than the running one
  recorded as a pending reboot;
- [the GTT ceiling](../llama.cpp/setup.md#2-set-the-gtt-ceiling), 112 GiB;
- [Docker for jaime](../llama.cpp/setup.md#3-docker-for-jaime), the `docker` group;
- [the ufw rule](../llama.cpp/setup.md#4-route-the-ports-through-ufw) that routes the tailnet's
  traffic to port 8000, vLLM's, beside 8080;
- [the router stopped](../llama.cpp/setup.md#5-stop-the-router), spike-model-hosting's
  `llama-router`;
- [the model store](../llama.cpp/setup.md#8-create-the-model-store), `/srv/models`;
- [the page-cache drop](../llama.cpp/setup.md#11-allow-the-page-cache-drop), the sudoers rule.

The session checks them without root. In order: `jaime` is in the `docker` group (prints
`docker`), the page-cache rule is in place (prints its line), the GTT ceiling in bytes (prints
`120259084288`), the router is stopped (prints `inactive`), and the store is `jaime`'s (prints
`jaime`):

```sh
id -nG | tr ' ' '\n' | grep -x docker
sudo -n -l | grep drop_caches
cat /sys/class/drm/card*/device/mem_info_gtt_total
systemctl is-active llama-router
stat -c %U /srv/models
```

ufw's rules are root's to read; the architect checks that `sudo ufw status verbose` lists
`8000/tcp ALLOW FWD Anywhere on tailscale0`. Then the session records the host stack, as
llama.cpp's [Record the host stack](../llama.cpp/setup.md#6-record-the-host-stack) does, and
brings the clone, `~/repos/spike-model-engines`, to the task's branch
([Get the clone onto the host](../llama.cpp/setup.md#7-get-the-clone-onto-the-host)).

### 2. Read the GPU back through the image

The architect's first walk of vLLM's ROCm image; the session walks them through it. Pull the
image, ask `vllm` for its version, then run the image's `rocminfo`, which lists the GPU as ROCm
sees it from inside the container. The image's entrypoint is `vllm serve`, so each check replaces
it with `--entrypoint`, as on the GB10
([2. Prove the pinned image runs on the GPU](#2-prove-the-pinned-image-runs-on-the-gpu)):

```sh
docker pull vllm/vllm-openai-rocm:v0.32.0
docker run --rm --device /dev/kfd --device /dev/dri --entrypoint vllm vllm/vllm-openai-rocm:v0.32.0 --version
docker run --rm --device /dev/kfd --device /dev/dri --entrypoint rocminfo vllm/vllm-openai-rocm:v0.32.0 | awk '/^Agent [0-9]+/ { gpu = 0 } /Name: +gfx1151/ { gpu = 1 } gpu && /Name:|Segment:|Size:/'
cat /sys/class/drm/card*/device/mem_info_gtt_total
```

`rocminfo` lists every agent, the CPU and the GPU, each under an `Agent <n>` header; `awk` keeps
only the agent whose `Name:` is `gfx1151`, and of it the lines that name it and its memory pools,
each pool's `Segment:` and `Size:`. Read two things and record them, with the date, in the
task's finding:

- the agent's `Name:`, which reads `gfx1151` when the image's ROCm knows the GPU;
- the `Size:` of its `GLOBAL` pool, in KB, the memory ROCm gives the GPU. Record it also in GiB
  (KB / 1048576), beside the GTT ceiling the last command prints, in bytes (112 GiB). llama.cpp's
  ROCm image counted the whole ceiling as the GPU's memory
  ([llama.cpp's Setup](../llama.cpp/setup.md#9-prove-the-pinned-image-runs-on-the-gpu)).

On the Framework, v0.32.0's `vllm --version` prints `0.32.0+rocm723`, and `rocminfo` names the
agent `gfx1151`, with its `GLOBAL` coarse-grained and extended-fine-grained pools each 117440512
KB, 112 GiB: the whole GTT ceiling, 120259084288 bytes, as llama.cpp's ROCm image counts it.
vLLM's first start logs `Free memory on device (112.0/112.0 GiB)` and reserves 0.80 of it
([the finding's Viability](../../findings/vllm-strix.md#viability)).

When `awk` prints nothing, no agent is gfx1151: the container didn't reach the GPU, or the
image's ROCm doesn't know it. Run the `rocminfo` command without the `awk` to keep its whole
output. If Docker says `rocminfo` isn't found on the image's `PATH`, name it by ROCm's own
directory, `--entrypoint /opt/rocm/bin/rocminfo`. A read-back that still names no gfx1151 is a
failure: record it with its output, and the session escalates at once, with no retry under
another setting.

### 3. Stage gpt-oss-120b

The session's step. The first start reads the model only from the store, so gpt-oss-120b is
staged through hf first, with the image already pulled in step 2
([Models](models.md#on-the-framework)). The store holds llama.cpp's GGUF of gpt-oss-120b, seeded
from the models drive, but not the Hugging Face repository vLLM serves, `openai/gpt-oss-120b`.

### 4. Install

On the first walk the architect's step; later the session's. `install` refuses while
llama.cpp's `llama` container runs or any `llama-router` unit is active, spike-model-hosting's
included, or native vLLM's `vllm-server` is, since one engine serves per host at a time. See
whether `llama` runs, and stop it when it does:

```sh
docker ps --filter name=llama
docker stop llama
```

`docker start llama` brings the container back once `vllm` is stopped, but its router serves no
model until one is loaded, since it runs with `--no-models-autoload`. Load one through its API, as
[llama.cpp's Models](../llama.cpp/models.md#loading-a-model) does, such as gpt-oss-120b:

```sh
curl -s -X POST "http://$(tailscale ip -4):8080/models/load" -H "Content-Type: application/json" -d '{"model": "ggml-org/gpt-oss-120b-GGUF:MXFP4"}'
```

The first start compiles from an empty compile cache. `~/.cache/vllm` is absent before the first
install, and goes with [Uninstall](uninstall.md#removing-vllm); this prints `absent` when it is:

```sh
test -e ~/.cache/vllm && du -sh ~/.cache/vllm || echo absent
```

Then install, from the clone:

```sh
host/engines vllm install
```

`install` runs as on gb10-1 ([5. Install](#5-install)), with the `rocm` flavor, which it picks
on a host with an AMD GPU: it pulls `vllm/vllm-openai-rocm:v0.32.0` and starts `vllm` with
`--device /dev/kfd --device /dev/dri` in place of `--gpus all`, keeping `--ipc host` and every
other option, on the flavor's default row, `gpt-oss-120b`. It prints

```text
vllm runs vllm/vllm-openai-rocm:v0.32.0 with row gpt-oss-120b (openai/gpt-oss-120b) on port 8000 of the tailnet address; docker logs -f vllm shows its start
```

The row's flags are in `host/vllm-rows` ([Models](models.md#the-rows)):

| Flag | Value | Why |
|---|---|---|
| `--max-num-seqs` | `16` | 16 sequences decode at once, as llama.cpp's 16-slot gpt-oss-120b section. |
| `--max-model-len` | `8192` | 8192 tokens a sequence, as each of llama.cpp's slots. |
| `--gpu-memory-utilization` | `0.80` | vLLM reserves 0.80 of the GPU memory it finds, as on the GB10, and leaves the rest to the host. |
| `--reasoning-parser` | `openai_gptoss` | The reply's reasoning comes back apart from its content. |
| `--enable-auto-tool-choice`, `--tool-call-parser` | `openai` | Tool calls come back as OpenAI tool calls. |

### 5. Watch the first start, up to 20 minutes

The first start of gpt-oss-120b on the Framework loads its weights, compiles from the empty
compile cache, and captures its graphs before it answers, and has up to 20 minutes, the one
start allowed past 10. Poll `/health` every 5 s until it answers 200, for 20 minutes at most;
the poll prints the time, in UTC, once it does, and prints nothing when the 20 minutes pass:

```sh
timeout 20m sh -c 'until [ "$(curl -s -o /dev/null -w "%{http_code}" "http://$(tailscale ip -4):8000/health")" = 200 ]; do sleep 5; done' && date -u
```

`docker logs -f vllm` follows the start meanwhile, in another terminal. Time the start as on the
GB10 ([6. Watch the cold start](#6-watch-the-cold-start-and-record-it)), from the container's
start to `Application startup complete.`, and record it as the first start, from an empty
compile cache.

A start that hasn't answered in 20 minutes, or a container that exits or restarts (`docker ps
--filter name=vllm` shows `Restarting` or no `Up`), is a failure. Record it with its reason and
its log, `docker logs vllm 2>&1 | tail -n 100`, and the session escalates at once, with no retry
under `--enforce-eager` or any other setting.

### 6. Read the memory it sized against

The session's step, once `/health` answers. vLLM logs the memory it planned with during its
start. Read the lines of this start only, then the host's own view, with no root:

```sh
docker logs --since "$(docker inspect --format '{{.State.StartedAt}}' vllm)" vllm 2>&1 | grep -E "Free memory on device|Model loading took|Available KV cache memory|KV cache size|Graph capturing finished"
grep ^MemAvailable /proc/meminfo
cat /sys/class/drm/card*/device/mem_info_gtt_used /sys/class/drm/card*/device/mem_info_vram_used
```

Read each and record it beside step 2's read-back and the GTT ceiling:

- the total it sized against: `Free memory on device`, when the start logs it, names the
  device's free and total memory at the start, of which `--gpu-memory-utilization` reserves 0.80;
  when the start logs no line naming a total, record that it logged none;
- the weights: `Model loading took` gives the memory the weights took on the device and the load
  time. vLLM offloads no weight to the CPU unless asked, so every weight is on the GPU when the
  model loaded;
- the KV cache: `Available KV cache memory` gives its memory, and `KV cache size` its tokens;
- the graphs: `Graph capturing finished` gives their time and memory, when the start captured any.

`MemAvailable` is the host's memory left, and the last command prints the GTT and the VRAM
carve-out in use, in bytes; GTT in use holds the weights and the KV cache.

### 7. Warm anchor A from the laptop

The session's step, in the architect's view, from the laptop's clone, with the bench environment
installed ([vllm-gb10-container](../../findings/vllm-gb10-container.md#running-the-cells)). The
network path, the release the server runs, then one warm-up request, the API page's chat
completion without Gemma 4's `chat_template_kwargs`, its reasoning cut to its first 80
characters:

```sh
tailscale ping -c 3 framework
curl -s "http://framework:8000/version"; echo
curl -s "http://framework:8000/v1/chat/completions" -H "Content-Type: application/json" -d '{"model": "openai/gpt-oss-120b", "messages": [{"role": "user", "content": "Say hello in one sentence."}]}' | jq -c '.choices[0].message | {content, reasoning: (.reasoning|tostring|.[0:80])}'
```

A request that times out while `/health` answers on the host is ufw dropping the routed port
([llama.cpp's Setup](../llama.cpp/setup.md#4-route-the-ports-through-ufw)). Then anchor A,
llama.cpp's scenario with vLLM's model named on the command line, between two `/metrics`
snapshots:

```sh
export GUIDELLM__SPEC__BACKEND__TARGET="http://framework:8000"
mkdir -p .state/vllm-strix
curl -s "http://framework:8000/metrics" > .state/vllm-strix/anchor-a.before.metrics
MISE_ENV=bench mise exec -- guidellm run -c bench/anchor-a.yaml --backend "kind=openai_http,model=openai/gpt-oss-120b" --output "kind=json,path=.state/vllm-strix/anchor-a.json"
curl -s "http://framework:8000/metrics" > .state/vllm-strix/anchor-a.after.metrics
```

The scenario's tokenizer is already `openai/gpt-oss-120b`. Read the client figures with
[vllm-gb10-container's read-out](../../findings/vllm-gb10-container.md#reading-the-figures), its
`$cell.json` the file above, and the server's from the two snapshots as that finding does.

### 8. Check that llama.cpp refuses

While `vllm` runs, llama.cpp's install refuses at the Framework's flavor, naming `docker stop
vllm`, and changes nothing:

```sh
LLAMA_FLAVOR=vulkan host/engines llama install
```

It prints

```text
vllm is running, and one engine serves per host at a time, since each reserves most of the host's GPU memory; docker stop vllm stops it
```
