# Update

## Moving to the pinned build

On the host, from the clone, bring the clone current, then update:

```sh
git pull
host/engines llama update
```

`update` pulls the pinned image, replaces the `llama` container with one running it, and removes every
image of every other build, server and full, and every untagged image, so only the pinned build's
images remain. It keeps the pinned build's images, server and full, in every flavor: its server
image in another flavor ([Switching the flavor](#switching-the-flavor)) and its full images, which
llama-bench runs ([Setup](setup.md#llama-bench)). It pulls before it removes anything, so a failed
pull leaves the old build serving. When `llama` already runs the pin and no other build's image is
left, it changes nothing and says so; when that `llama` is stopped, it
says `docker start llama` starts it, and leaves it stopped. It fails, changing nothing, when
llama.cpp isn't installed or while vLLM's `vllm` container runs (`docker stop vllm` stops it) or its
native `vllm-server` unit is active ([vLLM's Setup](../vllm/setup.md#5-stop-it)), and, before it
pulls, when `/srv/models` is missing or the host has no tailnet IPv4 address.

The new container starts with no model loaded; load the model again ([Models](models.md)), and
check the build it runs:

```sh
docker inspect --format '{{.Config.Image}}' llama
docker image ls ghcr.io/ggml-org/llama.cpp
```

The first prints the pinned image; the second lists it, and no image of another build. Once
the model is loaded, the laptop confirms the build the model itself runs ([API](api.md#build)),
which reads `b11669-620d2225c` at the pin, v0.7.0 (b11669).

`update` also replaces a `llama` container whose preset mount isn't the clone's preset
directory, `host/llama-preset`, such as one installed before the scripts moved from `engines/` to
`host/`, which still mounts the missing `engines/llama-preset`. When its image is already the
pin's, it pulls nothing and says

```text
llama restarted <pinned image> with its preset mount moved from <old directory> to <new directory>
```

When the image moves too, one replacement handles both, and it says `llama moved from <old
image> to <pinned image>, and its preset mount from <old directory> to <new directory>`. Either
way the new container runs, even when the old one was stopped. `install` changes nothing for
such a `llama`, whatever image it runs, and fails with

```text
llama's preset mount is <old directory>, not <new directory>; engines llama update moves it to the pin
```

## Switching the flavor

The image's flavor is the backend ggml built it for. `install` and `update` pick it from the GPU
the host has, or from `LLAMA_FLAVOR` when it is set, and give the container that backend's
devices:

| Flavor | Image | Devices | Picked on |
|---|---|---|---|
| `cuda13` | `server-cuda13-<build>` | `--gpus all` | a host without an AMD GPU: the GB10s |
| `rocm` | `server-rocm-<build>` | `--device /dev/kfd --device /dev/dri` | a host with an AMD GPU: the Framework |
| `vulkan` | `server-vulkan-<build>` | `--device /dev/dri` | only when `LLAMA_FLAVOR` names it |

A host has an AMD GPU when a card under `/sys/class/drm` reports AMD's PCI vendor ID, `0x1002`,
which any account can read:

```sh
cat /sys/class/drm/card*/device/vendor
```

On the Framework it prints `0x1002`; on gb10-1, NVIDIA's `0x10de`. Every flavor runs the same
build, the pin's or the version given.

On the Framework, from the clone, switch `llama` from ROCm to Vulkan:

```sh
LLAMA_FLAVOR=vulkan host/engines llama update
```

A flavor switch is a move to another image, as a build move is: `update` pulls
`ghcr.io/ggml-org/llama.cpp:server-vulkan-b11669` before it replaces anything, replaces `llama`
with one running it on `/dev/dri` alone, and says

```text
llama moved from ghcr.io/ggml-org/llama.cpp:server-rocm-b11669 to ghcr.io/ggml-org/llama.cpp:server-vulkan-b11669
```

It keeps `server-rocm-b11669`, the same build in the other flavor, so switching back pulls
nothing. The new container starts with no model loaded; load the model again
([Models](models.md)). Switch back with the Framework's own flavor, named or not:

```sh
LLAMA_FLAVOR=rocm host/engines llama update
```

The flavor holds for the one command it is given to. A later `update` without it, such as the
next move to the pin, moves a Vulkan `llama` back to ROCm, so give it again to stay on Vulkan.
`install` refuses a `llama` of another flavor, as it refuses another build, and names the update
that moves it:

```text
llama runs ghcr.io/ggml-org/llama.cpp:server-rocm-b11669, not ghcr.io/ggml-org/llama.cpp:server-vulkan-b11669; LLAMA_FLAVOR=vulkan engines llama update moves it to the pin
```

A flavor and a version combine, as in `LLAMA_FLAVOR=vulkan host/engines llama update b11429`. A
flavor that is none of the three fails before anything is read from Docker:

```text
LLAMA_FLAVOR is vulkn, which is none of cuda13, rocm, or vulkan
```

## Moving to another version

`update` and `install` take a version, which replaces the pin for that run: a semver release,
such as v0.6.0, or a b-build, such as b11429. A release runs the b-build its notes name ("Nightly
build:"), which the command reads from GitHub, so the host needs to reach `api.github.com`; a
b-build runs as given. Both of these move `llama` to v0.6.0 (b11429), the image
`ghcr.io/ggml-org/llama.cpp:server-cuda13-b11429`:

```sh
host/engines llama update v0.6.0
host/engines llama update b11429
```

It says `llama moved from <old image> to <new image>`, and removes every image of every other
build, the pin's among them, so only the version given's images remain. Run a second time, it
changes nothing and says so. With no version, `update` moves back to the pin:

```sh
host/engines llama update
```

A version that is neither fails before anything is read from Docker, such as

```text
0.6.0 is neither a semver release, such as v0.7.0, nor a b-build, such as b11669
```

and so does a release GitHub doesn't have, after curl's own error, or one whose notes name no
b-build:

```text
curl: (22) The requested URL returned error: 404
llama.cpp's release v9.9.9 can't be read from GitHub
```

## Rehearsing an update

To walk an update before the pin moves, install an older version, then update to the pin:

```sh
host/engines llama install v0.6.0
host/engines llama update
```

`install` refuses an older build while `llama` already runs another, so rehearse from a host
where it isn't installed, or after [uninstalling](uninstall.md).

## How the pin moves

The pin is `host/llama.env`: `LLAMA_RELEASE`, the latest semver release, and `LLAMA_BUILD`,
the b-build its notes name ("Nightly build:"), which every flavor's server image names, as
`server-<flavor>-<build>` in `LLAMA_REPOSITORY`. On the laptop,
`mise run currency` reports when a newer release names a newer build, reading the notes the same
way `update` and `install` read a release given (`host/llama-release.sh`):

```sh
mise run currency
```

A line beginning `host/llama.env: llama.cpp` means the pin is behind, and names the new build
and its release. Edit `LLAMA_RELEASE` and `LLAMA_BUILD` in `host/llama.env` to the release
and build it names, and the pin this guide quotes to match: the [README](README.md), and the
image and its `--version` output in [Setup](setup.md#3-prove-the-pinned-image-runs-on-the-gpu).
Commit and push; then, on each host, `git pull` and `host/engines llama update`, or
`host/engines llama-native update` where native llama.cpp serves ([Native](#native)).

## Native

Native llama.cpp ([Setup](setup.md#gb10-native)) updates with its own command, from the clone,
after `git pull`; with no version it moves to the pin, v0.7.0 (b11669):

```sh
git pull
host/engines llama-native update
```

`update` downloads the build's two tarballs and checks their digests, as `install` does, into
`/opt/llama.cpp/b11669`, points `current` at it, restarts `llama-router`, and waits for `/health`
to answer. Only once the new build serves does it remove every other build, so only the serving
build is kept. It prints the digests, then

```text
llama-router moved from b11429 to b11669
removed /opt/llama.cpp/b11429
```

When the start fails, `update` stops before removing anything, saying `journalctl -u
llama-router` shows why; the old build stays, and an update to its version moves back to it
without a download. The restart unloads every model, so load the model again
([Models](models.md)), and check the build:

```sh
readlink /opt/llama.cpp/current
/opt/llama.cpp/current/llama-server --version
command ls /opt/llama.cpp
```

`readlink` prints `b11669`; `--version` prints `build 11669, commit 620d2225c`; `ls` lists
`b11669`, `current`, and `preset`. Once a model is loaded, the laptop reads the build it runs
([API](api.md#build)), `b11669-620d2225c`.

Run a second time, `update` changes nothing and says `llama-router already serves b11669;
nothing changed`; when `llama-router` is stopped, it enables and starts it. It also re-points
`preset` when it names another directory than the clone's `host/llama-preset`, as after the clone
moves, and restarts `llama-router` on it. It fails, changing nothing, when native llama.cpp isn't
installed, and for the reasons `install` does: another engine's container running or
`vllm-server` active, the root steps not done, `/srv/models` missing, or no tailnet address
([Setup](setup.md#2-install)).

### Rolling back

A rollback is an update to the older version: it fetches the older build again, since only the
serving build is kept, re-points `current` at it, and removes the newer one:

```sh
host/engines llama-native update v0.6.0
```

It says `llama-router moved from b11669 to b11429` and `removed /opt/llama.cpp/b11669`. Forward
again is an update with no version, or the pin's:

```sh
host/engines llama-native update
```

The version is a semver release or a b-build, read as the container's update reads it
([Moving to another version](#moving-to-another-version)); `v0.6.0` and `b11429` are the same
build.
