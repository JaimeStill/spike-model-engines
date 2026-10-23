# Setting up llama.cpp

## GB10, in a container

Run these steps on each GB10, one host at a time. Commands with `sudo` are root steps; Docker
needs no `sudo`, because the account is in the `docker` group.

### 1. Bring the host current

DGX OS is Ubuntu with NVIDIA's apt repositories, so the driver, CUDA, Docker, and the NVIDIA
Container Toolkit all update through apt:

```sh
sudo apt update && sudo apt upgrade
```

A new kernel or driver takes effect only after a reboot, so the stack recorded next is the one
running. When the upgrade leaves `/var/run/reboot-required`, record that the host is waiting on a
reboot.

The NVIDIA Container Toolkit mounts the driver's libraries into a GPU container from a list it
generates at boot, `/var/run/cdi/nvidia.yaml`. An upgrade that moves one of those libraries
leaves the list naming a file that is gone, and every GPU container then fails to start with
`failed to fulfil mount request`. Without a reboot, regenerate the list after every upgrade:

```sh
sudo nvidia-ctk cdi generate --output=/var/run/cdi/nvidia.yaml
```

### 2. Record the host stack

Each command prints one item of the stack. Record each output, with the date, in the task's
finding.

```sh
grep DGX_OTA_VERSION /etc/dgx-release
nvidia-smi --query-gpu=driver_version --format=csv,noheader
nvidia-smi | grep -o "CUDA Version: [0-9.]*"
uname -r
docker version --format "{{.Server.Version}}"
nvidia-ctk --version
```

In order, they print DGX OS, the driver, CUDA, the kernel, Docker, and the NVIDIA Container
Toolkit. The CUDA line is the CUDA version the driver supports, which is what a CUDA 13 image
needs.

### 3. Prove the pinned image runs on the GPU

Pull the pinned image (`engines/llama.env`), ask its `llama-server` for its build, then list the
devices it finds with the GPU attached:

```sh
docker pull ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669
docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669 --version
docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669 --list-devices
```

`--version` prints `version: 0.7.0-dev (build 11669, commit 620d2225c)`. `--list-devices` lists
the GB10 as a CUDA device; an empty list means the container didn't reach the GPU.
