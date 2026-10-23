# llama.cpp in a container on the GB10s

Recorded on 2026-10-23, from [the llama.cpp setup guide](../engines/llama.cpp/setup.md), GB10,
in a container.

The pinned build is b11669, the b-build named by llama.cpp's latest semver release, v0.7.0, run
from `ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669` (`engines/llama.env`).

## Host stack

Each host was brought current with `sudo apt update && sudo apt upgrade`, without a reboot, before
its stack was recorded; the stack is the one running.

| Item | gb10-1 | gb10-2 |
|---|---|---|
| DGX OS | 7.6.0 | _pending_ |
| Driver | 580.178.04 | _pending_ |
| CUDA | 13.0 | _pending_ |
| Kernel | 7.0.0-1019-nvidia | _pending_ |
| Reboot pending | no | _pending_ |
| Docker | 29.6.2 | _pending_ |
| NVIDIA Container Toolkit | 1.20.1 | _pending_ |

## The pinned image on the GPU

`docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669 --version`:

| Host | CUDA device found | Build printed |
|---|---|---|
| gb10-1 | _pending_ | _pending_ |
| gb10-2 | _pending_ | _pending_ |
