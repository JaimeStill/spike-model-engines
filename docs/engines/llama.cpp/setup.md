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

Pull the pinned image (`engines/llama.env`), then run its `llama-server` with the GPU attached
and ask it for its version:

```sh
docker pull ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669
docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669 --version
```

The output lists the CUDA device it found (the GB10, compute capability 12.1) and ends with the
build, `version: 11669` and its commit. A missing device line means the container didn't reach
the GPU.
