# Update

## Moving to the pinned build

On the host, from the clone, bring the clone current, then update:

```sh
git pull
host/engines llama update
```

`update` pulls the pinned image, replaces the `llama` container with one running it, and removes
every other llama.cpp image, so only the pinned image remains. It pulls before it removes
anything, so a failed pull leaves the old build serving. When `llama` already runs the pin and no
other llama.cpp image is left, it changes nothing and says so; when that `llama` is stopped, it
says `docker start llama` starts it, and leaves it stopped. It fails, changing nothing, when
llama.cpp isn't installed or while vLLM's `vllm` container runs (`docker stop vllm` stops it),
and, before it pulls, when `/srv/models` is missing or the host has no tailnet IPv4 address.

The new container starts with no model loaded; load the model again ([Models](models.md)), and
check the build it runs:

```sh
docker inspect --format '{{.Config.Image}}' llama
docker image ls ghcr.io/ggml-org/llama.cpp
```

The first prints the pinned image; the second lists it alone. Once the model is loaded, the
laptop confirms the build the model itself runs ([API](api.md#build)), which reads
`b11669-620d2225c` at the pin, v0.7.0 (b11669).

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

It says `llama moved from <old image> to <new image>`, and removes every other llama.cpp image,
the pin's among them, so only the version given remains. Run a second time, it changes nothing
and says so. With no version, `update` moves back to the pin:

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
the b-build its notes name ("Nightly build:"), from which `LLAMA_IMAGE` follows. On the laptop,
`mise run currency` reports when a newer release names a newer build, reading the notes the same
way `update` and `install` read a release given (`host/llama-release.sh`):

```sh
mise run currency
```

A line beginning `host/llama.env: llama.cpp` means the pin is behind, and names the new build
and its release. Edit `LLAMA_RELEASE` and `LLAMA_BUILD` in `host/llama.env` to the release
and build it names, and the pin this guide quotes to match: the [README](README.md), and the
image and its `--version` output in [Setup](setup.md#3-prove-the-pinned-image-runs-on-the-gpu).
Commit and push; then, on each host, `git pull` and `host/engines llama update`.
