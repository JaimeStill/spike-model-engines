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

`install` pulls the pinned image and starts one container, `vllm`, running `vllm serve` on the
pin's default row, `gemma-4-26B-A4B-NVFP4`: the model `nvidia/Gemma-4-26B-A4B-NVFP4` and its
server flags. It runs as your account, with `--restart unless-stopped`, so Docker starts it again
after a reboot, and publishes port 8000 on the host's tailnet IPv4 address only. The row's flags
are in `host/vllm-rows` ([Models](models.md#the-rows)):

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
docker logs --timestamps vllm 2>&1 | grep -m 1 "Application startup complete"
```

The difference between the two times is the cold start. Record it, with the date, the release,
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

The `engines` commands point uv at `/opt/vllm`: `UV_PYTHON_INSTALL_DIR` at `/opt/vllm/python`,
for its Python, and `UV_CACHE_DIR` at `/opt/vllm/cache/uv`, for its cache.

#### What the native install runs

For each release, such as v0.31.0, `install` and `update` run three steps into
`/opt/vllm/<release>`:

1. `uv venv --python 3.12 --managed-python --seed /opt/vllm/v0.31.0` makes the release's
   virtualenv on uv-managed CPython 3.12 (`--managed-python` refuses the host's own Python), which
   uv downloads into `/opt/vllm/python` the first time. `--seed` installs pip into it, as
   FlashInfer's kernel install expects.
2. `uv pip install --python /opt/vllm/v0.31.0 vllm==0.31.0 --torch-backend=cu130` installs vLLM
   at the release, with every package it depends on, taking torch and the PyTorch packages from
   PyTorch's CUDA 13.0 index, as the image's torch comes, rather than PyPI's build.
3. `vllm download-kernels`, from the virtualenv, installs FlashInfer's precompiled kernels into
   it, the `flashinfer-cubin` and `flashinfer-jit-cache` wheels for its FlashInfer, so a start
   neither downloads nor compiles them. vLLM v0.31.0 has no `download-kernels`, so for it the
   step runs what the command runs, FlashInfer's own `python -m flashinfer download-kernels`.

The release's directory is marked whole only after the third step; a step that fails leaves it
unmarked, and the next `install` or `update` removes it and starts again.

#### Reading it back

On the host, from the clone, read uv's version, the Pythons uv has installed under
`/opt/vllm/python`, and the packages of the release `current` names:

```sh
MISE_ENV=host mise exec -- uv --version
MISE_ENV=host UV_PYTHON_INSTALL_DIR=/opt/vllm/python mise exec -- uv python list --only-installed --managed-python
MISE_ENV=host mise exec -- uv pip list --python /opt/vllm/current
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
torch's version with the CUDA version it was built for, which reads 13.0. With no release, it
installs the pin, v0.32.0; given `VLLM_MODEL=<row id>` before it, it serves that row instead of the
default ([Models](models.md#serving-another-row-for-one-run)).

A second run changes nothing and says `vllm-server already serves v0.31.0 with row
gemma-4-26B-A4B-NVFP4 (nvidia/Gemma-4-26B-A4B-NVFP4); nothing changed`; when `vllm-server` is
stopped, it enables and starts it again. It fails, changing nothing:

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

A cold start is timed from the unit's start to the `Application startup complete.` line, as the
container's is from its start ([6. Watch the cold start](#6-watch-the-cold-start-and-record-it)):

```sh
systemctl show vllm-server --property ActiveEnterTimestamp
journalctl -u vllm-server -o short-iso-precise --no-pager | grep "Application startup complete" | tail -n 1
```

### 5. Stop it

Native vLLM is enabled only while it serves, so stopping it also disables it, and a reboot
leaves it stopped. Both commands are ones the sudoers rule allows:

```sh
sudo -n systemctl stop vllm-server && sudo -n systemctl disable vllm-server
```

Install, given the release `current` names, enables and starts it again: with no release at the
pin, or `host/engines vllm-native install v0.31.0` at v0.31.0.
