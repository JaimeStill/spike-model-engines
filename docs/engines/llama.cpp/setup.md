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

Pull the pinned image (`host/llama.env`), v0.8.0 (b11960), ask its `llama-server` for its
build, then list the devices it finds with the GPU attached:

```sh
docker pull ghcr.io/ggml-org/llama.cpp:server-cuda13-b11960
docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:server-cuda13-b11960 --version
docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:server-cuda13-b11960 --list-devices
```

`--version` prints `version: 0.8.0-dev (build 11960, commit 8642541b2)`. `--list-devices` lists
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

It prints the image and the port it serves on, without the address. A second run changes nothing and
says so; when `llama` is stopped, it says `docker start llama` starts it, and leaves it stopped. It
fails, changing nothing, while vLLM's `vllm` container runs or native vLLM's `vllm-server` unit is
active, since one engine serves per host at a time (`docker stop vllm` stops the container, and
vLLM's [Setup](../vllm/setup.md#5-stop-it) the unit), when `/srv/models` is missing, when the host
has no tailnet IPv4 address, or when `llama` already runs another build; [Update](update.md) moves a
running build. Given a version, it installs that version's build instead of the pin: a semver
release, such as `v0.6.0`, runs the b-build its notes name (`b11429`), and a b-build, such as
`b11429`, runs as given ([Update](update.md#moving-to-another-version)). Its image's flavor is
`cuda13`, which it picks on a host without an AMD GPU ([Update](update.md#switching-the-flavor)).

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
the tailnet address`. With no version, it installs the pin, v0.8.0 (b11960); the version is read
as the container's install reads it ([Update](update.md#moving-to-another-version)).

A second run changes nothing and says `llama-router already serves b11429; nothing changed`; when
`llama-router` is stopped, it enables and starts it again. It fails, changing nothing:

- while the `llama` or `vllm` container runs, or native vLLM's `vllm-server` unit is active,
  since one engine serves per host at a time (`docker stop llama` or `docker stop vllm` stops a
  container, and vLLM's [Setup](../vllm/setup.md#5-stop-it) the unit);
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

## Framework, in a container

Run these steps on the Framework, `framework`: Omarchy, which is Arch Linux, on an AMD Strix Halo
whose GPU is gfx1151, with 125 GiB of RAM. ggml's ROCm image runs the pinned build, v0.8.0
(b11960), as on the GB10. The image brings its own ROCm runtime; the host gives it only the
kernel's GPU driver, through two device files, `/dev/kfd` and `/dev/dri`, in place of the NVIDIA
Container Toolkit's `--gpus all`. The `engines` commands pick that image, the `rocm` flavor, on
any host with an AMD GPU; ggml's Vulkan image, the `vulkan` flavor, runs the same build with
`/dev/dri` alone ([Update](update.md#switching-the-flavor)).

Each step says whose it is. Commands with `sudo` are root steps, the architect's; the rest the
session runs, as `jaime`. Each Framework session owns the host: nothing else serves on it while
one runs.

### 1. Bring the host current

The architect's step. Omarchy updates the whole host with one command, which takes a Snapper
snapshot of the root filesystem first, then updates every package, the kernel, Mesa, and
Docker among them. It restarts no service:

```sh
omarchy update
```

When the kernel changed, it ends by offering a reboot. Decline it; step 2 reboots, after its own
changes.

A new kernel takes effect only after a reboot. The host boots the `linux-omarchy` kernel, so
compare the running kernel with that package. `uname -r` prints the running one, such as
`7.2.8-9-omarchy`, and `pacman -Q` the installed one, such as `linux-omarchy 7.2.8-9`:

```sh
uname -r
pacman -Q linux-omarchy
```

When the two differ, the host is waiting on a reboot, which step 2's reboot takes. Arch's own
kernel, `linux`, is installed beside it and isn't the one that boots.

### 2. Set the GTT ceiling

The architect's root step. The GPU shares the host's RAM. The firmware carves out only 512 MiB
of it as the GPU's own memory; the rest the GPU reaches as GTT, system RAM it maps on demand and
frees when a model unloads. The GTT size is a ceiling, not a reservation: memory the GPU isn't
using stays the host's. With no option set, the kernel's TTM limit, and amdgpu's GTT with it,
defaults to half of RAM, about 62.5 GiB.

The Framework was set to 96 GiB earlier: TTM's `pages_limit` to 25165824 pages of 4 KiB, with
`amd-ttm --set 96`, and amdgpu's `gttsize` to 98304 MiB, in `/etc/modprobe.d/amdgpu.conf`. Set
both to 112 GiB, close to the GB10, whose GPU can allocate nearly its whole memory, while keeping
about 13 GiB of the 125 GiB for the host. 112 GiB is `amd-ttm`'s own limit before it warns: it
asks before setting more than 90% of RAM, since a GPU that fills memory can starve the host.

`amd-ttm` writes `options ttm pages_limit=29360128` to `/etc/modprobe.d/ttm.conf`:

```sh
sudo amd-ttm --set 112
```

It looks for initramfs images in `/boot` to rebuild, finds none, since Limine keeps them
elsewhere, and asks whether to reboot: answer `n`, since amdgpu's option and the boot images
come next. amdgpu's `gttsize` is in MiB, 112 × 1024:

```sh
echo 'options amdgpu gttsize=114688' | sudo tee /etc/modprobe.d/amdgpu.conf
```

The initramfs loads amdgpu, and TTM with it (its `kms` hook), and carries `/etc/modprobe.d`
(its `modconf` hook), so the options apply only once they are built into it. Rebuild the boot
images with Omarchy's Limine hook, then reboot:

```sh
sudo limine-mkinitcpio
sudo reboot
```

After the reboot, check each value. TTM's limit, in 4 KiB pages, prints `29360128`; amdgpu's
parameter, readable only by root, prints `114688`; and the GTT the GPU reports, in bytes, prints
`120259084288`:

```sh
cat /sys/module/ttm/parameters/pages_limit
sudo cat /sys/module/amdgpu/parameters/gttsize
cat /sys/class/drm/card*/device/mem_info_gtt_total
```

The reboot also takes step 1's new kernel, if there was one: `uname -r` now matches `pacman -Q
linux-omarchy`.

Going back sets the earlier values and rebuilds the same way
([Uninstall](uninstall.md#the-framework)).

### 3. Docker for jaime

The architect's root step, as on gb10-1: `jaime` joins the `docker` group, so Docker needs no
`sudo`, and Docker starts now and at every boot:

```sh
sudo usermod -aG docker jaime
sudo systemctl enable --now docker
```

The group takes effect at the next login: a new SSH session, or `newgrp docker` in this one. A
terminal on the Framework's desktop belongs to the desktop's login, from before the group, so it
gets `permission denied` until the desktop logs in again or the terminal runs `newgrp docker`.
Then, as `jaime`, `docker info` prints the server's details, not `permission denied`:

```sh
docker info
```

The GPU's device files, `/dev/kfd` and `/dev/dri/renderD128`, are readable and writable by every
account on this host (`0666`), so a container running as `jaime` reaches the GPU with no
`--group-add`. Check with:

```sh
command ls -l /dev/kfd /dev/dri/renderD128
```

### 4. Route the ports through ufw

The architect's root step. Omarchy runs ufw with ufw-docker, which drops routed traffic to a
container's published port: the laptop's requests to `framework:8080` time out, though the
container answers on the host. A native server needs no rule, since ufw doesn't filter the host's
own input on `tailscale0`; a container's port is routed, through Docker's forwarding. Allow the
routed traffic that arrives over the tailnet to llama.cpp's port, 8080, and vLLM's, 8000:

```sh
sudo ufw route allow in on tailscale0 proto tcp to any port 8080
sudo ufw route allow in on tailscale0 proto tcp to any port 8000
```

Each adds a rule for IPv4 and one for IPv6. Check them:

```sh
sudo ufw status verbose
```

It lists `8080/tcp ALLOW FWD Anywhere on tailscale0`, the same for `8000/tcp`, and both again
with `(v6)`. The rules name a port, not a container, so they hold for any container published
there: a flavor switch, an update, or vLLM's container. They go with
[Uninstall](uninstall.md#removing-the-frameworks-root-steps).

<a id="5-stop-the-router"></a>

### 5. Retire the router

The architect runs every step of the retirement; the session reads the state back before and
after. spike-model-hosting's native router, `llama-router`, served on the Framework before this
spike: it held port 8080 and, with its set A loaded, most of the GTT, and the `engines` commands
refuse while any `llama-router` unit is active. The spike's answer task retired it on
2026-10-29, and the Framework serves set A from the `llama` container instead
([12. Serve set A](#12-serve-set-a)).
The retirement removes everything only the router used, read on 2026-10-29 with the router
disabled and inactive:

| What | Where | Owner |
|---|---|---|
| The unit | `/etc/systemd/system/llama-router.service`, with no drop-ins | root |
| Its presets | `/etc/llama-router`: `models.ini` and 7 earlier copies, 8 files | root; one copy, `models.ini.a65fd306`, `jaime`'s |
| Its builds | `/opt/llama.cpp`: `b11715`, `b11734`, and `current`, a link to `b11734` | root |
| Its models | `/mnt/models/hf-cache`, the unit's `HF_HOME`: four repositories under `hub/`, 82G (`gpt-oss-120b-GGUF` 60G, `gemma-4-26B-A4B-it-GGUF` 15G, `gemma-4-E4B-it-GGUF` 8.1G, `embeddinggemma-2-GGUF` 296M, all ggml-org's) | `jaime` |
| Its models directory | `/mnt/models/gguf`, empty, the unit's `--models-dir` through the link `~/models` | `jaime` |
| The render copies | `~/models.ini.039c5fa7`, `.96732ef9`, `.9c983739`, `.9eeb9f04`, and `~/llama-router.service.83b0a95c` | `jaime` |
| outpost's links | `~/.local/bin`: `outpost`, `outpost-preset-install`, `outpost-service-restart`, `outpost-service-status`, and a stray link named `outpost*`, each into `~/personal-agents/admin/bin` | `jaime` |

It keeps the models drive, mounted at `/mnt/models` and holding no model; the ufw route rules
([4](#4-route-the-ports-through-ufw)); the `docker` group ([3](#3-docker-for-jaime)); and
`/srv/models` ([8](#8-create-the-model-store)), whose seeded models are copies of their own
([Models](models.md#seeding-the-frameworks-store)). No sudoers rule names the router.

The session reads the state back first. The unit is found, disabled and inactive, the two root
directories list their files, the drive holds the cache, the home directory holds the link and
the render copies, `find` names outpost's five links, and port 8080 is the `llama` container's:

```sh
systemctl show llama-router -p LoadState -p FragmentPath -p DropInPaths -p UnitFileState -p ActiveState
command ls -la /etc/llama-router /opt/llama.cpp
findmnt /mnt/models; df -h /mnt/models; du -sh /mnt/models/hf-cache/hub/*
command ls -la ~/models ~/models.ini.* ~/llama-router.service.* /mnt/models/gguf
find ~/.local/bin -maxdepth 1 -lname '*personal-agents/admin/bin*' -printf '%f\n'
ss -ltn 'sport = :8080'; docker port llama
```

Then the architect's root steps. `disable --now` stops the unit when it runs and disables it when
it is enabled; on a host where it is already both, it changes nothing. The unit file goes, systemd
forgets it, and the presets and the builds go with it:

```sh
sudo systemctl disable --now llama-router
sudo rm /etc/systemd/system/llama-router.service
sudo systemctl daemon-reload
sudo rm -r /etc/llama-router /opt/llama.cpp
```

The cache is `jaime`'s, so it needs no root. The architect removes the rest as `jaime`: the
cache with its four repositories, the empty models directory, the link to it and the render
copies, and outpost's links. `rm ~/models` removes the link, not the directory it names; quoting
`'outpost*'` removes the stray link by its name alone:

```sh
rm -r /mnt/models/hf-cache
rmdir /mnt/models/gguf
rm ~/models ~/models.ini.039c5fa7 ~/models.ini.96732ef9 ~/models.ini.9c983739 ~/models.ini.9eeb9f04 ~/llama-router.service.83b0a95c
rm ~/.local/bin/outpost ~/.local/bin/'outpost*' ~/.local/bin/outpost-preset-install ~/.local/bin/outpost-service-restart ~/.local/bin/outpost-service-status
```

The session reads the state back after. `LoadState=not-found` means no `llama-router` unit is
left; `command ls -d` prints `cannot access` for both directories and exits 2, the read-back that
they are gone; the drive holds only `lost+found`, which `du` can't read as `jaime` and says so;
`find` prints nothing; and port 8080 still listens on the tailnet address, published by `llama`:

```sh
systemctl show llama-router -p LoadState
command ls -d /etc/llama-router /opt/llama.cpp
df -h /mnt/models; du -sh /mnt/models/*
command ls -la ~/models ~/models.ini.* ~/llama-router.service.*
find ~/.local/bin -maxdepth 1 -lname '*personal-agents/admin/bin*' -printf '%f\n'
ss -ltn 'sport = :8080'; docker port llama
```

On a host where `llama` doesn't run yet, as in a setup from scratch, which retires the router
before [10. Install](#10-install), the last line prints only `ss`'s header and `docker port`'s
error.

As run on 2026-10-29, from about 15:25 to 15:31Z, the architect's steps at the Framework's own
prompt and the session's read-backs, each block exactly as given: both read-backs matched what
this step says, the drive went from 82G used to 36K, and port 8080 stayed the `llama` container's ([the answer finding's Walkthrough](../../findings/answer.md#the-routers-retirement)).

The `engines` commands still refuse beside any active `llama-router` unit, by its name alone:
native llama.cpp's on gb10-1 ([GB10, native](#gb10-native)), or one a host rebuilds. Nothing here
brings the router back. spike-model-hosting's profile would rebuild it: its tasks re-render the
unit and the presets from `devices/strix-halo/profile.toml`, the architect installs them, and the
builds and the 82G of models download again, by its Strix Halo runbook.

### 6. Record the host stack

The session's step. Each command prints one item of the stack. Record each output, with the
date, in the task's finding.

```sh
omarchy version
uname -r
pacman -Q mesa vulkan-radeon linux-firmware docker rocm-core
docker version --format "{{.Server.Version}}"
cat /sys/class/drm/card*/device/mem_info_gtt_total
```

In order, they print Omarchy's version, the kernel, the packages (Mesa, its Vulkan driver for
Radeon, the GPU's firmware, Docker, and the host's ROCm), Docker's server, and the GTT ceiling, in
bytes. The container doesn't use the host's ROCm, `rocm-core`; it is recorded beside the image's
own, ROCm 7.2.1, for any native ROCm build.

### 7. Get the clone onto the host

The session's step. The `engines` commands run from a clone of this repository, in
`~/repos`; nothing is installed:

```sh
mkdir -p ~/repos
git clone https://github.com/JaimeStill/spike-model-engines.git ~/repos/spike-model-engines
cd ~/repos/spike-model-engines
```

The clone's default branch holds these steps and the scripts they run. A session running a task
that hasn't merged checks out that task's branch instead, which is named for the task, such as:

```sh
git switch llama-strix-rocm
```

Every later command on the host runs from `~/repos/spike-model-engines`.

### 8. Create the model store

The architect's root step. The models live in `/srv/models`, outside the container, as on gb10-1:
a plain directory on the root drive, owned by `jaime`, since the container writes the store as
`jaime`, not as root:

```sh
sudo install -d -o "$(id -un)" -g "$(id -gn)" /srv/models
```

The root drive is the subvolume Omarchy snapshots before every update, so a snapshot taken after
the models arrive keeps them: a model deleted from the store frees its space only once the last
snapshot holding it ages out. Snapper keeps five.

The session then seeds the store from the models drive, with no download
([Models](models.md#seeding-the-frameworks-store)).

### 9. Prove the pinned image runs on the GPU

The architect's first walk of ggml's ROCm image; the session walks them through it. The pin
(`host/llama.env`) is v0.8.0 (b11960), and the ROCm image of that build carries gfx1151 among
its targets.

First, the full image, which holds every tool of the build, llama-bench among them. Its
entrypoint picks the tool from its first argument ([llama-bench](#llama-bench)): `--server` runs
`llama-server`, and `--bench` runs `llama-bench`. Pull it, ask `llama-server` for its build, then
list the devices llama-bench finds with the GPU attached, running as `jaime`:

```sh
docker pull ghcr.io/ggml-org/llama.cpp:full-rocm-b11960
docker run --rm --device /dev/kfd --device /dev/dri --user "$(id -u):$(id -g)" ghcr.io/ggml-org/llama.cpp:full-rocm-b11960 --server --version
docker run --rm --device /dev/kfd --device /dev/dri --user "$(id -u):$(id -g)" ghcr.io/ggml-org/llama.cpp:full-rocm-b11960 --bench --list-devices
```

`--version` prints `version: 0.8.0-dev (build 11960, commit 8642541b2)`, as on the GB10.
`--list-devices` lists one ROCm device:

```text
ROCm0: Radeon 8060S Graphics (114688 MiB, 114683 MiB free)
```

ROCm counts the whole GTT ceiling, 112 GiB, as the GPU's memory, not the 512 MiB carve-out, so a
model may hold up to it. The log before it names the GPU and its target:

```text
Device 0: Radeon 8060S Graphics, gfx1151 (0x1151), VMM: no, Wave Size: 32, VRAM: 114688 MiB
```

An empty list means the container didn't reach the GPU.

Then the server image, started by hand as the `llama` container, with the arguments
`host/llama.sh` passes: the clone's preset read-only, the store mounted as llama.cpp's download
cache (`LLAMA_CACHE`), port 8080 published on the host's tailnet address only, the router started
with no model, and the device files in place of `--gpus all`. The hand start checks whether ggml's
ROCm image serves on the host at all, before the `engines` commands run it; a host already known
to serve skips it, since [10. Install](#10-install) starts the same container. It names the preset by
the clone's full path, so it runs from any directory; a relative path, run from elsewhere, makes
Docker create the missing directory, owned by root, and the router exits with `preset file does
not exist`:

```sh
docker run --detach --name llama --restart unless-stopped --device /dev/kfd --device /dev/dri --user "$(id -u):$(id -g)" --publish "$(tailscale ip -4):8080:8080" --volume /srv/models:/srv/models --env LLAMA_CACHE=/srv/models --volume "$HOME/repos/spike-model-engines/host/llama-preset:/etc/llama-preset:ro" ghcr.io/ggml-org/llama.cpp:server-rocm-b11960 --models-preset /etc/llama-preset/models.ini --no-models-autoload --host 0.0.0.0 --port 8080
```

### 10. Install

The session's step, from the clone:

```sh
host/engines llama install
```

`install` runs as on gb10-1 ([6. Install](#6-install)), with the `rocm` flavor, which it picks
on a host with an AMD GPU: it pulls `ghcr.io/ggml-org/llama.cpp:server-rocm-b11960` and starts
`llama` with `--device /dev/kfd --device /dev/dri` in place of `--gpus all`. It prints

```text
llama runs ghcr.io/ggml-org/llama.cpp:server-rocm-b11960 on port 8080 of the tailnet address
```

It refuses while any `llama-router` unit is active, native llama.cpp's or spike-model-hosting's
until its retirement ([5. Retire the router](#5-retire-the-router)), or vLLM's `vllm` container
runs or its `vllm-server` unit is active.

A `llama` started by hand, as in step 9, stays in place. When it runs the same image with the
clone's preset, `install` counts it as installed and says `llama already runs
ghcr.io/ggml-org/llama.cpp:server-rocm-b11960; nothing changed`; on another image or preset
mount, it refuses. To have `install` start its own, remove the hand-started one first, which
unloads its models:

```sh
docker rm --force llama
host/engines llama install
```

Check that the container is up and the router answers:

```sh
docker ps --filter name=llama
curl -s "http://$(tailscale ip -4):8080/health"
```

`docker ps` shows `llama` with status `Up`, and `(healthy)` once the image's health check passes;
`/health` prints `{"status":"ok"}`.

Load gpt-oss-120b over the API ([Models](models.md#loading-a-model)), from the laptop, naming the
host `framework`, and list the models until it shows `loaded`:

```sh
curl -s -X POST "http://framework:8080/models/load" -H "Content-Type: application/json" -d '{"model": "ggml-org/gpt-oss-120b-GGUF:MXFP4"}'
curl -s "http://framework:8080/models" | jq '.data[] | {id, status: .status.value}'
```

A request from the laptop that times out, while `/health` answers on the host, is ufw dropping
the routed port ([4. Route the ports through ufw](#4-route-the-ports-through-ufw)).

On the host, the router's log shows where the layers went:

```sh
docker logs llama 2>&1 | grep -E "gfx1151|offloaded|buffer size"
```

It shows `offloaded 37/37 layers to GPU`, every layer on the GPU, and `ROCm0 model buffer size =
59851.68 MiB`, the weights; the other `ROCm0` buffers hold the KV cache and the compute buffer. A
`CPU` model buffer beyond a small one for the token embeddings would mean layers stayed on the
CPU.

The build the model runs, from the laptop, prints `b11960-8642541b2` ([API](api.md#build)):

```sh
curl -sG "http://framework:8080/props" --data-urlencode "model=ggml-org/gpt-oss-120b-GGUF:MXFP4" --data-urlencode autoload=false | jq -r .build_info
```

The warm-up request and the anchor A cell follow the GB10's methods, with `framework` in place
of `gb10-1`: the warm-up as in
[bench-gb10-container](../../findings/bench-gb10-container.md#per-model-the-build-and-the-warm-up),
and anchor A as in [llama-gb10-container](../../findings/llama-gb10-container.md#running-the-cells).

### 11. Allow the page-cache drop

The architect's root step, as on the GB10
([7. Allow the page-cache drop](#7-allow-the-page-cache-drop)), which explains the drop: a sudoers
rule naming that one command exactly. Arch keeps `sysctl` in `/usr/bin`; its `/usr/sbin` is a
link to `/usr/bin`, so the rule names `/usr/bin/sysctl`.

Write the rule into its own file without an editor. `sudo` drops an `EDITOR` set on its command
line, so `visudo` opens vim regardless, and inside another editor's terminal vim takes `visudo`'s
`--` for a file name and saves nothing. Instead, write the rule under a name with a dot, which
`sudo` skips in `/etc/sudoers.d`, check it with `visudo`, which prints `parsed OK`, and install it
as root's, read-only, only when it parses:

```sh
echo 'jaime ALL=(root) NOPASSWD: /usr/bin/sysctl vm.drop_caches=3' | sudo tee /etc/sudoers.d/drop-caches.new >/dev/null
sudo visudo -cf /etc/sudoers.d/drop-caches.new && sudo install -m 0440 -o root -g root /etc/sudoers.d/drop-caches.new /etc/sudoers.d/drop-caches
sudo rm /etc/sudoers.d/drop-caches.new
```

Check it without the password `visudo` just cached: `sudo -k` forgets it, and `sudo -n -l` lists
the rules `sudo -n` may run, which include the one line above:

```sh
sudo -k
sudo -n -l | grep drop_caches
```

A session drops the cache as below. The drop prints `vm.drop_caches = 3`, and `Cached` in
`/proc/meminfo` falls by what it freed:

```sh
grep ^Cached /proc/meminfo
sync && sudo -n /usr/bin/sysctl vm.drop_caches=3
grep ^Cached /proc/meminfo
```

The rule goes when its file does ([Uninstall](uninstall.md#the-framework)).

### 12. Serve set A

The session's step. Between tasks the Framework serves set A, the four models Pi and the
personal agents call, from the `llama` container in ggml's Vulkan image, at the pin. Set A is four
sections of the preset ([Models](models.md#the-preset)), each already in `/srv/models` and within
the quantization floor, so nothing downloads:

| Section | Model | Role |
|---|---|---|
| `gpt-oss-120b-MXFP4-set-a` | OpenAI's gpt-oss-120b, MXFP4, `c = 131072` in one KV cache its 4 slots share | the harness model, with tools |
| `google/gemma-4-26B-A4B-it-qat-q4_0-gguf:Q4_0` | Google's Gemma 4 26B-A4B, QAT Q4_0, with its projector | vision |
| `ggml-org/gemma-4-E4B-it-GGUF:Q8_0` | Google's Gemma 4 E4B, Q8_0, with its projector | audio |
| `mrutkows/granite-embedding-english-r2-GGUF:BF16` | IBM's granite-embedding-english-r2, BF16 | embeddings |

Set A starts at 4 slots for gpt-oss-120b. A session that measures owns the host: it stops `llama`
first (`docker stop llama`), and the next session that serves set A runs this step again.

On the host, the clone fetches the branch that carries the preset, here the task's, `answer`, and
`update` runs the pin at flavor `vulkan`, since the suite picks `rocm` on an AMD GPU when none is
given ([Update](update.md#switching-the-flavor)). When `llama` already runs the pin, `update`
changes nothing and says so, and the router re-reads the preset so it lists the new section
([Models](models.md#the-preset)). Then the container's image and devices, which read
`server-vulkan-b11960` and `/dev/dri`, and the models, every one `unloaded`:

```sh
cd ~/repos/spike-model-engines && git switch -q answer && git pull -q --ff-only && git status -sb | head -1 && git log --oneline -1
LLAMA_FLAVOR=vulkan host/engines llama update 2>&1 | tail -3
docker start llama >/dev/null && until curl -fs "http://$(tailscale ip -4):8080/health" >/dev/null; do sleep 1; done
curl -s "http://$(tailscale ip -4):8080/models?reload=1" > /dev/null
docker inspect --format '{{.Config.Image}} {{range .HostConfig.Devices}}{{.PathOnHost}} {{end}}' llama
curl -s "http://$(tailscale ip -4):8080/models" | jq -c '[.data[] | {id, status: .status.value}]'
```

Load set A through the router's API, one model at a time, each with the
[answer finding's](../../findings/answer.md#3-the-4-slot-section-the-load) wait: the load request,
then a `/models` poll until the model reads `loaded` (or failed), timed from the request. The
memory is read before the first load and after the last: `MemAvailable`, the host's, and
`gtt_used`, the GPU's GTT in use, in bytes:

```sh
cd ~/repos/spike-model-engines
grep ^MemAvailable /proc/meminfo; echo "gtt_used $(cat /sys/class/drm/card*/device/mem_info_gtt_used)"
for model in gpt-oss-120b-MXFP4-set-a google/gemma-4-26B-A4B-it-qat-q4_0-gguf:Q4_0 ggml-org/gemma-4-E4B-it-GGUF:Q8_0 mrutkows/granite-embedding-english-r2-GGUF:BF16; do
start=$(date +%s.%N)
curl -s -X POST "http://$(tailscale ip -4):8080/models/load" -H "Content-Type: application/json" -d "{\"model\": \"$model\"}"; echo
while :; do s=$(curl -s "http://$(tailscale ip -4):8080/models" | jq -r --arg m "$model" '.data[] | select(.id == $m) | if .status.failed then "failed" else .status.value end'); [[ $s == loaded || $s == failed ]] && break; sleep 0.5; done
echo "$model $s after $(awk -v a="$start" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1f", b - a }') s"
done
grep ^MemAvailable /proc/meminfo; echo "gtt_used $(cat /sys/class/drm/card*/device/mem_info_gtt_used)"
```

Each load prints `{"success":true}`, then the model, `loaded`, and its time. The router holds up
to 4 models at once (`--models-max`, whose default, 4, the suite leaves as it is), so set A's four
load side by side.

Then the router's models, set A's four `loaded` and the rest `unloaded`, and the containers,
`llama` up and `vllm` exited:

```sh
curl -s "http://$(tailscale ip -4):8080/models" | jq -c '[.data[] | {id, status: .status.value}]'
docker ps -a --filter name=vllm --filter name=llama --format "{{.Names}} {{.Image}} {{.Status}}"
```

From the laptop, the router answers on the tailnet; it prints `{"status":"ok"}`:

```sh
curl -s http://framework:8080/health
```

The router runs with `--no-models-autoload`, and the suite keeps it so. After `llama` starts, by
an update, a `docker start`, or a reboot, which `--restart unless-stopped` brings it back from, the
router serves nothing until a model is loaded: run the load block above again, or load each model
from Pi's `/llama`.

What the spike no longer runs on the Framework, the vLLM audio probe's image and ggml's native
Vulkan prebuilt, is removed with [Uninstall](uninstall.md#the-framework)'s two blocks.

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

**In a container.** The server image the spike runs, `server-<flavor>-<build>`, holds only
`llama-server`. ggml's `full-<flavor>-<build>` image holds every tool, llama-bench among them, for
the same build. Its entrypoint, `/app/tools.sh`, picks the tool from its first argument;
`--bench` (or `-b`) runs `./llama-bench` in `/app` with the rest. On the GB10, pull
`full-cuda13` for the pin, v0.8.0 (b11960), and list the devices it finds with the GPU attached
(the Framework's flavors are under [On the Framework](#on-the-framework)):

```sh
docker pull ghcr.io/ggml-org/llama.cpp:full-cuda13-b11960
docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:full-cuda13-b11960 --bench --list-devices
```

For arm64 the image downloads about 3.4 GB, against the server image's 2.5 GB, since it carries
Python and llama.cpp's conversion scripts too.

### Running it

llama-bench loads its own copy of the model, so run it while no engine has a model loaded, for
the memory and so no other load shares the GPU. It reads the model store directly: `-m` names a
GGUF file in `/srv/models` (a split model's first shard), or `-hf` names a repository and
quantization, as the preset's `hf-repo` does, which it resolves from `LLAMA_CACHE`. A model's
GGUF is under its repository's `snapshots/<commit>/`; list the commit with `command ls`, which runs
`ls` itself where the shell aliases it (to eza, say, whose output and options differ):

```sh
command ls /srv/models/models--<owner>--<repository>/snapshots
```

The general form, natively, with the table written to `~/bench/<name>.md` and llama-bench's log
to `~/bench/<name>.err` beside it (`mkdir -p ~/bench` first):

```sh
LLAMA_CACHE=/srv/models /opt/llama.cpp/current/llama-bench -m <model.gguf> -p <prompt tokens> -n <generated tokens> -r <repetitions> -o md 2>~/bench/<name>.err | tee ~/bench/<name>.md
```

and in the container, as the invoking user, with the store mounted where it is on the host:

```sh
docker run --rm --gpus all --user "$(id -u):$(id -g)" --volume /srv/models:/srv/models --env LLAMA_CACHE=/srv/models ghcr.io/ggml-org/llama.cpp:full-cuda13-b11960 --bench -m <model.gguf> -p <prompt tokens> -n <generated tokens> -r <repetitions> -o md 2>~/bench/<name>.err | tee ~/bench/<name>.md
```

When the table has only its header, llama-bench couldn't load the model, and the `.err` file says
why (a wrong path, say). When it runs, the file shows the device it found and the backends it
loaded.

Other options set what the server's preset and log set: `-ngl` the layers on the GPU, `-fa` flash
attention (`on`, `off`, or `auto`), and `-b` and `-ub` the batch sizes. Each option takes a
comma-separated list, and llama-bench runs every combination. The exact commands each comparison
runs are in its finding's method, as gb10-1's native and container runs are in
[llama-gb10-native](../../findings/llama-gb10-native.md#llama-bench).

### On the Framework

The Framework runs llama-bench from three builds of the same b-build, to compare the backends
with the server taken out: ggml's `full-rocm-<build>` image, with the ROCm flavor's devices,
`/dev/kfd` and `/dev/dri`, in place of `--gpus all`; `full-vulkan-<build>`, with `/dev/dri` alone;
and ggml's native Vulkan prebuilt, unpacked in `~/llama.cpp/b11960-vulkan`
([Models](models.md#on-the-framework)), which runs on the host's Mesa where the Vulkan image runs
its own. The full images are about 34 GB (ROCm) and 3.6 GB (Vulkan), uncompressed. Each lists the
GPU it finds:

```sh
docker run --rm --device /dev/kfd --device /dev/dri --user "$(id -u):$(id -g)" ghcr.io/ggml-org/llama.cpp:full-rocm-b11960 --bench --list-devices
docker run --rm --device /dev/dri --user "$(id -u):$(id -g)" ghcr.io/ggml-org/llama.cpp:full-vulkan-b11960 --bench --list-devices
~/llama.cpp/b11960-vulkan/llama-bench --list-devices
```

ROCm lists `ROCm0: Radeon 8060S Graphics` with the GTT ceiling, 114688 MiB; both Vulkan builds
list `Vulkan0` as `RADV STRIX_HALO` with 115200 MiB, the ceiling plus the firmware's 512 MiB.
The `llama` container holds the GPU's memory while it serves, so stop it first (`docker stop
llama`) and start it again after. A run then takes the general form above, the container's with
its flavor's devices in place of `--gpus all`, or the prebuilt's path in place of
`/opt/llama.cpp/current`. The matrix and the exact commands, at depths 0 and 8192 and each run
held to the 10-minute cap, are in
[llama-strix-rocm](../../findings/llama-strix-rocm.md#llama-bench).

### What it reports

By default, a Markdown table with one row per test: the model, its size and parameters, the
backend, the options that differ from the defaults (such as `ngl`), the test (`pp512`, `tg256`),
and `t/s`, the mean ± the standard deviation over the repetitions. The last line names the build,
as `build: 8642541b2 (11960)` at v0.8.0 (b11960), so every result carries its version.
`-o json` (or `jsonl`, `csv`) prints the same with every repetition's own sample, for a finding
that keeps the raw numbers.
