# vLLM

vLLM serves Hugging Face models through `vllm serve`, an OpenAI-compatible HTTP server. This spike
runs it on gb10-1 in vLLM's CUDA 13.0 image, and natively, from vLLM's CUDA 13.0 wheel of the
same release in a uv virtualenv, under a system unit, `vllm-server`. Unlike llama.cpp's
router, a vLLM server serves one model, named on its command line when it starts, and loads no
other on demand: changing the model means starting the server again, with `update`, on another
row of model and flags.

The spike follows vLLM's GitHub releases. The pin lives in `host/vllm.env`: release v0.32.0,
image `vllm/vllm-openai:v0.32.0`, and the row the host serves by default,
`gemma-4-26B-A4B-NVFP4`: `nvidia/Gemma-4-26B-A4B-NVFP4` with its server flags. Every model the
server can serve is a row in `host/vllm-rows`, its model and its flags, and
`VLLM_MODEL=<row id>` before `install` or `update` serves another row for one run
([Models](models.md#changing-the-model)). `mise run currency` reports the release when a newer
one is out.

The `engines` commands install, update, and uninstall it. They run from a clone of this
repository on the host, as `host/engines vllm <verb>`:

| Command | What it does |
|---|---|
| `host/engines vllm install` | Runs the server on the pinned row, or `VLLM_MODEL`'s, at the pinned release or the release given |
| `host/engines vllm update` | Moves the server to the pinned release and row, or `VLLM_MODEL`'s, and removes every other vLLM image |
| `host/engines vllm uninstall` | Removes the server, every vLLM image, and the compile cache, keeping `/srv/models` |
| `host/engines vllm-native install [release]` | Serves native vLLM on the pinned row, or `VLLM_MODEL`'s, at the pinned release or the release given |
| `host/engines vllm-native update [release]` | Moves native vLLM to the pinned release and row, or the given release or `VLLM_MODEL`'s, and removes every other release |
| `host/engines vllm-native uninstall` | Stops and disables native vLLM and removes every release and its caches, keeping `/srv/models` |

Each changes nothing, and says so, when run a second time. One engine serves per host at a time:
vLLM's install and update refuse while llama.cpp serves, in its `llama` container or natively
under its `llama-router` unit, or while vLLM's other hosting method serves, and llama.cpp's
refuse while `vllm` or `vllm-server` runs. The native commands need the architect's root steps
first ([Setup](setup.md#1-the-architects-root-steps)), and uv, this spike's tool for native
vLLM's Python, installed from the host environment ([Setup](setup.md#2-uv)).

Every start of the server, in the container or under the unit, is a cold start: the server loads the
model, compiles it, and captures its CUDA graphs before it answers. Each page that starts it says
how to time the start, and each time is recorded in the task's finding. The container and native
vLLM on gb10-1, compared for install, update, rollback, startup, speed, and memory, are in
[vllm-gb10-native](../../findings/vllm-gb10-native.md).

## Pages

- [Setup](setup.md): bring a host current, record its stack, prove the image, and install;
  natively, the architect's root steps, uv, install, and stop.
- [Models](models.md): the pinned model, the models pre-staged with hf, its first download into
  the store, copying it to gb10-2 under a borrow, and changing the model: the rows and the
  override.
- [API](api.md): a chat completion from the laptop with its reasoning apart, `/health`,
  `/v1/models`, `/version`, `/metrics`, and the probes of the API surface.
- [Update](update.md): moving to the pinned release or model, how the pin moves, and the native
  update, rollback, and walk.
- [Uninstall](uninstall.md): removing vLLM, deleting models, with hf or by hand, and removing
  native vLLM and its root steps.
