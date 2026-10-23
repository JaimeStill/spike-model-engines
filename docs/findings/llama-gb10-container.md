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

```sh
docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669 --version
docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669 --list-devices
```

| Host | Build printed | CUDA device found |
|---|---|---|
| gb10-1 | 0.7.0-dev (build 11669, commit 620d2225c) | CUDA0: NVIDIA GB10 (124544 MiB, 119719 MiB free) |
| gb10-2 | _pending_ | _pending_ |

The image's CUDA 13.4.1 runtime runs on the hosts' 580.178.04 driver, which reports CUDA 13.0.

On gb10-1 the first GPU run failed with `failed to fulfil mount request: open
/usr/lib/aarch64-linux-gnu/libnvidia-egl-wayland.so.1.1.21: no such file or directory`. The
upgrade had moved `libnvidia-egl-wayland1` from 1.1.21 to 1.1.23, and the toolkit's CDI spec,
`/var/run/cdi/nvidia.yaml`, generated at the last boot, still named 1.1.21. Regenerating the spec
with `sudo nvidia-ctk cdi generate --output=/var/run/cdi/nvidia.yaml` fixed it; a reboot would
have regenerated it too.
