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
| DGX OS | 7.6.0 | 7.6.0 |
| Driver | 580.178.04 | 580.178.04 |
| CUDA | 13.0 | 13.0 |
| Kernel | 7.0.0-1019-nvidia | 7.0.0-1019-nvidia |
| Reboot pending | no | no |
| Docker | 29.6.2 | 29.6.2 |
| NVIDIA Container Toolkit | 1.20.1 | 1.20.1 |

## The pinned image on the GPU

```sh
docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669 --version
docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669 --list-devices
```

| Host | Build printed | CUDA device found |
|---|---|---|
| gb10-1 | 0.7.0-dev (build 11669, commit 620d2225c) | CUDA0: NVIDIA GB10 (124544 MiB, 119719 MiB free) |
| gb10-2 | 0.7.0-dev (build 11669, commit 620d2225c) | CUDA0: NVIDIA GB10 (124544 MiB, 119727 MiB free) |

The image's CUDA 13.4.1 runtime runs on the hosts' 580.178.04 driver, which reports CUDA 13.0.

On gb10-1 the first GPU run failed with `failed to fulfil mount request: open
/usr/lib/aarch64-linux-gnu/libnvidia-egl-wayland.so.1.1.21: no such file or directory`. The
upgrade had moved `libnvidia-egl-wayland1` from 1.1.21 to 1.1.23, and the toolkit's CDI spec,
`/var/run/cdi/nvidia.yaml`, generated at the last boot, still named 1.1.21. Regenerating the spec
with `sudo nvidia-ctk cdi generate --output=/var/run/cdi/nvidia.yaml` fixed it; a reboot would
have regenerated it too. gb10-2 ran the regeneration after its upgrade, from the guide, and
started the image first time.

## Serving and the model store

`engines/engines llama install` started the router at b11669 on both hosts, bound to each host's
tailnet address on port 8080; a second run changed nothing, and `/health` answered
`{"status":"ok"}`. The server warns that it has no API key and that CORS allows every origin; the
port is published on the tailnet address only, and access control belongs to spike-model-gateway.

gpt-oss-120b MXFP4 (63,387,346,248 bytes) downloaded from Hugging Face into gb10-1's store and
loaded on CUDA0, running as the architect's user. gb10-2's own download was cancelled with
`docker restart llama` and its partial files deleted; the model was then copied from gb10-1 over
QSFP and loaded on gb10-2 without a download:

| Copy | Bytes | Time | Rate |
|---|---|---|---|
| `rsync -a` over SSH, gb10-1 to gb10-2-qsfp | 63,387,346,248 | 1m50.6s | 549 MB/s |

The copy is one SSH stream, so it ran far below the link's RDMA bandwidth (about 185 Gb/s on
both halves of the port, per dotfiles).

From the laptop, gb10-1 answered an OpenAI chat completion ("Say hello in one sentence.") with
`content` "Hello!" and gpt-oss's reasoning in `reasoning_content`, and `/v1/models` listed the
model `loaded`.

`engines/engines llama update` on gb10-1, already at the pin, changed nothing. `engines/engines
llama uninstall` on gb10-2 removed the container and its image, a second run changed nothing, no
llama.cpp image remained, and `/srv/models` kept the model.
