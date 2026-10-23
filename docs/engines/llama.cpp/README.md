# llama.cpp

llama.cpp serves GGUF models through `llama-server`, an OpenAI-compatible HTTP server. This spike
runs it on the GB10s in ggml's CUDA 13 server image first, and natively later. In the container,
one `llama-server` runs in router mode: it holds no model itself, and loads each model named in
its models preset, as a child process, when asked over its API.

The spike follows llama.cpp's semver releases and runs the b-build each one names. The pin lives
in `engines/llama.env`: release v0.7.0, build b11669, image
`ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669`. `mise run currency` reports the build when a
newer semver release names a newer one.

The `engines` commands install, update, and uninstall it. They run from a clone of this
repository on each host, as `engines/engines llama <verb>`:

| Command | What it does |
|---|---|
| `engines/engines llama install` | Runs the router at the pin, or at the b-build given |
| `engines/engines llama update` | Moves the router to the pin and removes every other llama.cpp image |
| `engines/engines llama uninstall` | Removes the router and every llama.cpp image, keeping `/srv/models` |

Each changes nothing, and says so, when run a second time.

## Pages

- [Setup](setup.md): bring a host current, record its stack, prove the image, and install.
- [Models](models.md): the preset, loading a model, watching its download, and listing models.
- [API](api.md): a chat completion from the laptop, `/health`, and `/v1/models`.
- [Update](update.md): moving to the pinned build, and how the pin moves.
- [Uninstall](uninstall.md): removing llama.cpp, and deleting models.
