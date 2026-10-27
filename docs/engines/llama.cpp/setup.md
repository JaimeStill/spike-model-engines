# Setting up llama.cpp

## GB10, in a container

Run these steps on gb10-1. gb10-2 is reserved for spike-ai-pipeline, and the spike installs
there only under a named borrow of it (`ai-hosting.md`, "Hosts and access"). Commands with `sudo`
are root steps, the architect's; Docker needs no `sudo`, because the account is in the `docker`
group.

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

Pull the pinned image (`host/llama.env`), ask its `llama-server` for its build, then list the
devices it finds with the GPU attached:

```sh
docker pull ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669
docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669 --version
docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669 --list-devices
```

`--version` prints `version: 0.7.0-dev (build 11669, commit 620d2225c)`. `--list-devices` lists
the GB10 as a CUDA device; an empty list means the container didn't reach the GPU.

### 4. Get the clone onto the host

The `engines` commands run from a clone of this repository, in the home directory; nothing is
installed:

```sh
git clone https://github.com/JaimeStill/spike-model-engines.git
cd spike-model-engines
```

Every later command on the host runs from `spike-model-engines`. With no arguments, `engines`
lists its commands, each with what it does:

```sh
host/engines
```

### 5. Create the model store

The models live in `/srv/models`, outside the container, so they survive an update or an
uninstall. Create it once, as a root step, owned by your account; the container writes to the
store as your account, not as root:

```sh
sudo install -d -o "$(id -un)" -g "$(id -gn)" /srv/models
```

### 6. Install

```sh
host/engines llama install
```

`install` pulls the pinned image and starts one container, `llama`, running `llama-server` in
router mode: no model on its command line, the models preset (`host/llama-preset/models.ini`)
mounted read-only, and `/srv/models` mounted as llama.cpp's download cache (`LLAMA_CACHE`). It
runs with `--restart unless-stopped`, so Docker starts it again after a reboot, and publishes port
8080 on the host's tailnet IPv4 address only. The router starts no model by itself
(`--no-models-autoload`); [Models](models.md) loads one.

It prints the image and the port it serves on, without the address. A second run changes
nothing and says so; when `llama` is stopped, it says `docker start llama` starts it, and leaves
it stopped. It fails, changing nothing, while vLLM's `vllm` container runs, since one
engine serves per host at a time (`docker stop vllm` stops it), when `/srv/models` is missing,
when the host has no tailnet IPv4 address, or when `llama` already runs another build;
[Update](update.md) moves a running build. Given a b-build, such as `b11429`, it installs that
build instead of the pin.

Check that the container is up and the router answers:

```sh
docker ps --filter name=llama
curl -s "http://$(tailscale ip -4):8080/health"
```

`docker ps` shows `llama` with status `Up`, and `(healthy)` once the image's health check passes;
`/health` prints `{"status":"ok"}`.

### 7. Allow the page-cache drop

A cold load is timed from an empty page cache: Linux keeps the files a load read in memory, so a
second load reads them from memory, not disk, and vLLM counts that cache as free memory. Dropping
the cache is a root command, which a session runs before every timed load. The architect allows
it once, as a root step, with a sudoers rule naming that one command exactly, so the session runs
it without a password and can run nothing else as root.

Write the rule into its own file. `visudo` opens it in your editor and checks it before saving:

```sh
sudo visudo -f /etc/sudoers.d/drop-caches
```

The file holds one line, with your account's name (`id -un` prints it) in place of `jaime`:

```text
jaime ALL=(root) NOPASSWD: /usr/sbin/sysctl vm.drop_caches=3
```

Check it without the password `visudo` just cached: `sudo -k` forgets it, and `sudo -n` fails
instead of asking for one. The drop prints `vm.drop_caches = 3`:

```sh
sudo -k
sudo -n /usr/sbin/sysctl vm.drop_caches=3
```

A session drops the cache as below: `sync` first writes any unwritten data to disk, so the drop
can free every cached page. `Cached` in `/proc/meminfo`, read before and after, falls by what the
drop freed:

```sh
grep ^Cached /proc/meminfo
sync && sudo -n /usr/sbin/sysctl vm.drop_caches=3
grep ^Cached /proc/meminfo
```

The rule goes when its file does, with a root step:

```sh
sudo rm /etc/sudoers.d/drop-caches
```
