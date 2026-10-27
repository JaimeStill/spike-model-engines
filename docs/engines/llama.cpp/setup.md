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

Pull the pinned image (`host/llama.env`), v0.7.0 (b11669), ask its `llama-server` for its
build, then list the devices it finds with the GPU attached:

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
[Update](update.md) moves a running build. Given a version, it installs that version's build
instead of the pin: a semver release, such as `v0.6.0`, runs the b-build its notes name
(`b11429`), and a b-build, such as `b11429`, runs as given
([Update](update.md#moving-to-another-version)).

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

## GB10, native

Native llama.cpp is the container's exact build, run on the host instead: ggml's CUDA 13.4 arm64
Linux prebuilt for the b-build, with its CUDA runtime tarball unpacked beside it, so only the
hosting method differs. llama-server runs under a system unit, `llama-router`, with the
container's preset, model store, and router flags, on the same port, 8080, of the tailnet
address. Run these steps on gb10-1 after the container's steps 1, 2, 4, and 5: the host current,
its stack recorded, the clone on the host, and `/srv/models` created.

Each build lives in its own directory, `/opt/llama.cpp/<b-build>`, and two links there name what
serves: `current`, the build, and `preset`, the clone's `host/llama-preset`, so the unit names
neither a build nor the clone's path. The binaries find the CUDA runtime's libraries beside them
(their runpath is `$ORIGIN`), so the unit sets no `LD_LIBRARY_PATH`. The host's driver supports
CUDA 13.0 and the runtime is 13.4, as in the container.

### 1. The architect's root steps

Three root steps, once, from the clone; [Uninstall](uninstall.md#removing-the-native-root-steps)
removes them. The unit file and the sudoers rule name the account `jaime`; on another account,
edit both to its name (`id -un` prints it) first.

Create `/opt/llama.cpp`, owned by your account, so installs and updates need no root:

```sh
sudo install -d -o "$(id -un)" -g "$(id -gn)" /opt/llama.cpp
```

Install the unit, `host/llama-router.service`, and have systemd read it:

```sh
sudo install -m 0644 host/llama-router.service /etc/systemd/system/llama-router.service
sudo systemctl daemon-reload
```

The unit runs `/opt/llama.cpp/current/llama-server` as your account, with `LLAMA_CACHE` set to
`/srv/models`, the preset `/opt/llama.cpp/preset/models.ini`, `--no-models-autoload`, and
`--host` set to `tailscale ip -4` as it starts, on `--port 8080`. It requires and follows
`tailscaled`, and restarts 5 seconds after a failure. It is installed but neither enabled nor
started; the `engines` commands enable and start it while native llama.cpp serves.

Allow the `engines` commands to run the unit's five `systemctl` commands, and nothing else, without
a password: a sudoers rule naming `systemctl start`, `stop`, `restart`, `enable`, and `disable
llama-router` exactly, as the page-cache rule names its one command
([7. Allow the page-cache drop](#7-allow-the-page-cache-drop)). The rule is
`host/llama-router.sudoers`; `visudo` checks it, and `install` copies it, read-only and root's,
only when the check passes:

```sh
sudo visudo -cf host/llama-router.sudoers && sudo install -m 0440 host/llama-router.sudoers /etc/sudoers.d/llama-router
```

`visudo` prints `host/llama-router.sudoers: parsed OK`. Check the rule without the password
`sudo` just cached: `sudo -k` forgets it, and `sudo -n` fails instead of asking for one. Stopping
the unit while it isn't running changes nothing, and prints nothing; without the rule, `sudo`
prints `sudo: a password is required`:

```sh
sudo -k
sudo -n systemctl stop llama-router
```

### 2. Install

This guide installs v0.6.0 (b11429), which [Update](update.md#native) then moves to the pin:

```sh
host/engines llama-native install v0.6.0
```

`install` reads the release's assets from GitHub, downloads
`llama-b11429-bin-ubuntu-cuda-13.4-arm64.tar.gz` and
`cudart-llama-b11429-bin-ubuntu-cuda-13.4-arm64.tar.gz`, checks each against the sha256 digest
GitHub lists for it, and unpacks both into `/opt/llama.cpp/b11429`, about 870 MB. It points
`current` and `preset`, enables and starts `llama-router`, and waits for `/health` to answer, for
at most a minute. It prints each file's digest, then `llama-router serves b11429 on port 8080 of
the tailnet address`. With no version, it installs the pin, v0.7.0 (b11669); the version is read
as the container's install reads it ([Update](update.md#moving-to-another-version)).

A second run changes nothing and says `llama-router already serves b11429; nothing changed`; when
`llama-router` is stopped, it enables and starts it again. It fails, changing nothing:

- while the `llama` or `vllm` container runs, since one engine serves per host at a time
  (`docker stop llama` or `docker stop vllm` stops it);
- before the root steps are done, naming the one missing: `/opt/llama.cpp`, the unit, or the
  sudoers rule;
- when `/srv/models` is missing, or the host has no tailnet IPv4 address;
- when native llama.cpp is already at another build, or its `preset` link names another
  directory, as after the clone moves; [Update](update.md#native) moves either.

A download or a digest that doesn't match stops it before anything is unpacked into place.

The container's steps refuse in turn while `llama-router` is active, saying how to stop it.

### 3. Check it serves

```sh
systemctl status llama-router --no-pager
readlink /opt/llama.cpp/current
/opt/llama.cpp/current/llama-server --version
ldd /opt/llama.cpp/current/libggml-cuda.so | grep -E "cudart|cublas"
curl -s "http://$(tailscale ip -4):8080/health"
```

`systemctl status` shows `enabled` and `active (running)`; `readlink` prints the build, `b11429`.
`--version` prints the build and its commit, `build 11429, commit d81235049`, as the container's
does. `ldd` lists `libcudart.so.13`, `libcublas.so.13`, and `libcublasLt.so.13`, each from
`/opt/llama.cpp/current`, since `ldd` resolves them through the link; `/health` prints `{"status":"ok"}`. Load and call models as in the
container ([Models](models.md), [API](api.md)): the port and the preset are the same. The
router's log, the container's `docker logs llama`, is the unit's journal:

```sh
journalctl -u llama-router -n 20 --no-pager
```

### 4. Stop it

Native llama.cpp is enabled only while it serves, so stopping it also disables it, and a reboot
leaves it stopped. Both commands are ones the sudoers rule allows:

```sh
sudo -n systemctl stop llama-router && sudo -n systemctl disable llama-router
```

Install, given the version `current` names, enables and starts it again: with no version at the
pin, or `host/engines llama-native install v0.6.0` at b11429.

## llama-bench

### What it is

`llama-bench` is llama.cpp's own benchmark of the engine itself, without the server: it loads a
GGUF model onto the backend (on the GB10, CUDA) and times two tests, with no HTTP, no
tokenization, and no sampling in the measure:

- **pp**, prompt processing: the model reads a prompt of the size given (`-p`, such as 512
  tokens) in batches, as prefill does.
- **tg**, text generation: the model generates the number of tokens given (`-n`, such as 256),
  one at a time, as decode does.

Each test runs the number of repetitions given (`-r`, 5 by default) after a warm-up run, and
reports tokens per second as the mean and standard deviation over the repetitions. Where GuideLLM
measures what a client sees through the server (TTFT, throughput, concurrency), llama-bench
measures the backend's raw rate for one stream, so the same build compares across hosting methods
and hosts with the server taken out.

### Setting it up

llama-bench ships with every llama.cpp build, so the spike installs nothing for it.

**Native.** It is in the native prebuilt, beside `llama-server`, under the build `current` names
([GB10, native](#gb10-native)):

```sh
/opt/llama.cpp/current/llama-bench --list-devices
```

`--list-devices` lists the GB10 as a CUDA device, as `llama-server`'s does.

**In a container.** The server image the spike runs, `server-cuda13-<build>`, holds only
`llama-server`. ggml's `full-cuda13-<build>` image holds every tool, llama-bench among them, for
the same build. Its entrypoint, `/app/tools.sh`, picks the tool from its first argument;
`--bench` (or `-b`) runs `./llama-bench` in `/app` with the rest. Pull it for the pin, v0.7.0
(b11669), and list the devices it finds with the GPU attached:

```sh
docker pull ghcr.io/ggml-org/llama.cpp:full-cuda13-b11669
docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:full-cuda13-b11669 --bench --list-devices
```

For arm64 the image downloads about 3.4 GB, against the server image's 2.5 GB, since it carries
Python and llama.cpp's conversion scripts too.

### Running it

llama-bench loads its own copy of the model, so run it while no engine has a model loaded, for
the memory and so no other load shares the GPU. It reads the model store directly: `-m` names a
GGUF file in `/srv/models` (a split model's first shard), or `-hf` names a repository and
quantization, as the preset's `hf-repo` does, which it resolves from `LLAMA_CACHE`. The general
form, natively:

```sh
LLAMA_CACHE=/srv/models /opt/llama.cpp/current/llama-bench -m <model.gguf> -p <prompt tokens> -n <generated tokens> -r <repetitions>
```

and in the container, as the invoking user, with the store mounted where it is on the host:

```sh
docker run --rm --gpus all --user "$(id -u):$(id -g)" --volume /srv/models:/srv/models --env LLAMA_CACHE=/srv/models ghcr.io/ggml-org/llama.cpp:full-cuda13-b11669 --bench -m <model.gguf> -p <prompt tokens> -n <generated tokens> -r <repetitions>
```

Other options set what the server's preset and log set: `-ngl` the layers on the GPU, `-fa` flash
attention (`on`, `off`, or `auto`), and `-b` and `-ub` the batch sizes. Each option takes a
comma-separated list, and llama-bench runs every combination. The exact commands each comparison
runs are in its finding's method, as gb10-1's native and container runs are in
[llama-gb10-native](../../findings/llama-gb10-native.md#llama-bench).

### What it reports

By default, a Markdown table with one row per test: the model, its size and parameters, the
backend, the options that differ from the defaults (such as `ngl`), the test (`pp512`, `tg256`),
and `t/s`, the mean ± the standard deviation over the repetitions. The last line names the build,
as `build: 620d2225c (11669)` at v0.7.0 (b11669), so every result carries its version.
`-o json` (or `jsonl`, `csv`) prints the same with every repetition's own sample, for a finding
that keeps the raw numbers.
