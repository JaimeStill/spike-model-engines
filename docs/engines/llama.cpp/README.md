# llama.cpp

llama.cpp serves GGUF models through `llama-server`, an OpenAI-compatible HTTP server. This spike
runs it on gb10-1 in ggml's CUDA 13 server image first, and natively later. In the container,
one `llama-server` runs in router mode: it holds no model itself, and loads each model named in
its models preset, as a child process, when asked over its API. The router loads models on
demand, so one server serves every model in the preset.

The spike follows llama.cpp's semver releases and runs the b-build each one names. The pin lives
in `host/llama.env`: v0.7.0 (b11669), image `ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669`.
`mise run currency` reports the build when a newer semver release names a newer one.

The `engines` commands install, update, and uninstall it. They run from a clone of this
repository on the host, as `host/engines llama <verb>`:

| Command | What it does |
|---|---|
| `host/engines llama install [version]` | Runs the router at the pin, or at the version given |
| `host/engines llama update [version]` | Moves the router to the pin, or to the version given, and removes every other llama.cpp image |
| `host/engines llama uninstall` | Removes the router and every llama.cpp image, keeping `/srv/models` |

Each changes nothing, and says so, when run a second time. One engine serves per host at a time:
install and update refuse while vLLM's `vllm` container runs ([vLLM](../vllm/README.md)). The
version install and update take is a semver release, such as `v0.6.0`, which runs the b-build its
notes name, or a b-build, such as `b11429`, which runs as given
([Update](update.md#moving-to-another-version)).

## Pages

- [Setup](setup.md): bring a host current, record its stack, prove the image, install, and allow
  the session's page-cache drop.
- [Models](models.md): the preset, pre-staging every model with hf, loading a model, watching or
  cancelling its download, copying it to gb10-2 under a borrow, and listing models.
- [API](api.md): a chat completion from the laptop, `/health`, `/v1/models`, the build a model
  runs (`/props`), and `/metrics`.
- [Update](update.md): moving to the pinned build or another version, rehearsing an update, and
  how the pin moves.
- [Uninstall](uninstall.md): removing llama.cpp, and deleting models, with hf or by hand.
