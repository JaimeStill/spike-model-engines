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

Pull the pinned image (`engines/vllm.env`). The image's entrypoint is `vllm serve`, so each check
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

`install` refuses while llama.cpp's `llama` container runs, since one engine serves per host at
a time. See whether it runs:

```sh
docker ps --filter name=llama
```

When it lists `llama`, stop it. `docker stop` keeps it stopped across a reboot, and `docker start
llama` brings it back once `vllm` is stopped:

```sh
docker stop llama
```

Then install:

```sh
engines/engines vllm install
```

`install` pulls the pinned image and starts one container, `vllm`, running `vllm serve` on the
pin's default row, `gemma-4-26B-A4B-NVFP4`: the model `nvidia/Gemma-4-26B-A4B-NVFP4` and its
server flags. It runs as your account, with `--restart unless-stopped`, so Docker starts it again
after a reboot, and publishes port 8000 on the host's tailnet IPv4 address only. The row's flags
are in `engines/vllm-rows` ([Models](models.md#the-rows)):

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

It prints the image, the model, and the port it serves on, without the address. A second run
changes nothing and says so; when `vllm` is stopped, it says `docker start vllm` starts it, and
leaves it stopped. It fails, changing nothing, while `llama` runs, when `/srv/models`
is missing, when the host has no tailnet IPv4 address, or when `vllm` already runs another
release, another model, or other server flags; [Update](update.md) moves a running one. Given a
release, such as `v0.31.0`, it installs that release instead of the pin; given
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
engines/engines llama install
```
