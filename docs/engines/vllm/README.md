# vLLM

vLLM serves Hugging Face models through `vllm serve`, an OpenAI-compatible HTTP server. This spike
runs it on gb10-1 in vLLM's CUDA 13.0 image first, and natively later. Unlike llama.cpp's
router, a vLLM server serves one model, named on its command line when it starts, and loads no
other on demand: changing the model means starting the server again, with `update`, on another
row of model and flags.

The spike follows vLLM's GitHub releases. The pin lives in `engines/vllm.env`: release v0.32.0,
image `vllm/vllm-openai:v0.32.0`, and the row the host serves by default,
`gemma-4-26B-A4B-NVFP4`: `nvidia/Gemma-4-26B-A4B-NVFP4` with its server flags. Every model the
server can serve is a row in `engines/vllm-rows`, its model and its flags, and
`VLLM_MODEL=<row id>` before `install` or `update` serves another row for one run
([Models](models.md#changing-the-model)). `mise run currency` reports the release when a newer
one is out.

The `engines` commands install, update, and uninstall it. They run from a clone of this
repository on the host, as `engines/engines vllm <verb>`:

| Command | What it does |
|---|---|
| `engines/engines vllm install` | Runs the server on the pinned row, or `VLLM_MODEL`'s, at the pinned release or the release given |
| `engines/engines vllm update` | Moves the server to the pinned release and row, or `VLLM_MODEL`'s, and removes every other vLLM image |
| `engines/engines vllm uninstall` | Removes the server, every vLLM image, and the compile cache, keeping `/srv/models` |

Each changes nothing, and says so, when run a second time. One engine serves per host at a time:
vLLM's install and update refuse while llama.cpp's `llama` container runs, and llama.cpp's
refuse while `vllm` runs.

Every start of the container is a cold start: the server loads the model, compiles it, and
captures its CUDA graphs before it answers. Each page that starts it says how to time the start,
and each time is recorded in the task's finding.

## Pages

- [Setup](setup.md): bring a host current, record its stack, prove the image, and install.
- [Models](models.md): the pinned model, the models pre-staged with hf, its first download into
  the store, copying it to gb10-2 under a borrow, and changing the model: the rows and the
  override.
- [API](api.md): a chat completion from the laptop with its reasoning apart, `/health`,
  `/v1/models`, `/version`, `/metrics`, and the probes of the API surface.
- [Update](update.md): moving to the pinned release or model, and how the pin moves.
- [Uninstall](uninstall.md): removing vLLM, and deleting models, with hf or by hand.
