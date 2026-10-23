# llama.cpp in a container on the GB10s

Recorded on 2026-10-23, from [the llama.cpp setup guide](../engines/llama.cpp/setup.md), GB10,
in a container.

The pinned build is b11669, the b-build named by llama.cpp's latest semver release, v0.7.0, run
from `ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669` (`engines/llama.env`).

## Host stack

Each host was brought current (`apt full-upgrade`, then a reboot) before its stack was recorded.

| Item | gb10-1 | gb10-2 |
|---|---|---|
| DGX OS | _pending_ | _pending_ |
| Driver | _pending_ | _pending_ |
| CUDA | _pending_ | _pending_ |
| Kernel | _pending_ | _pending_ |
| Docker | _pending_ | _pending_ |
| NVIDIA Container Toolkit | _pending_ | _pending_ |

## The pinned image on the GPU

`docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669 --version`:

| Host | CUDA device found | Build printed |
|---|---|---|
| gb10-1 | _pending_ | _pending_ |
| gb10-2 | _pending_ | _pending_ |
