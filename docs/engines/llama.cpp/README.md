# llama.cpp

llama.cpp serves GGUF models through `llama-server`, an OpenAI-compatible HTTP server. This spike
runs it on the GB10s in ggml's CUDA 13 server image first, and natively later.

The spike follows llama.cpp's semver releases and runs the b-build each one names. The pin lives
in `engines/llama.env`: release v0.7.0, build b11669, image
`ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669`. `mise run currency` reports the build when a
newer semver release names a newer one.

## Pages

- [Setup](setup.md): bring a host current, record its stack, and run the pinned image.
- Models: to come.
- API: to come.
- Update: to come.
- Uninstall: to come.
