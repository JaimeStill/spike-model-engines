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

`update` also replaces a `llama` whose preset mount isn't the clone's preset directory,
`host/llama-preset`, as after the clone's scripts moved from `engines/` to `host/`: the old
container still mounts `engines/llama-preset`, which no longer exists. When its image is already
the pin's, it pulls nothing, and says

```text
llama restarted <pinned image> with its preset mount moved from <old directory> to <new directory>
```

When the image moves too, one replacement handles both, and it says `llama moved from <old
image> to <pinned image>, and its preset mount from <old directory> to <new directory>`. Either
way the new container runs, even when the old one was stopped. `install`, finding such a
`llama`, changes nothing, whatever image it runs, and fails with

```text
llama's preset mount is <old directory>, not <new directory>; engines llama update moves it to the pin
```

The new container starts with no model loaded; load the model again ([Models](models.md)), and
check the build it runs:

```sh
docker inspect --format '{{.Config.Image}}' llama
docker image ls ghcr.io/ggml-org/llama.cpp
```

The first prints the pinned image; the second lists it alone. Once the model is loaded, the
laptop confirms the build the model itself runs ([API](api.md#build)), which reads
`b11669-620d2225c` at the pin.

## Rehearsing an update

To walk an update before the pin moves, install an older build, then update to the pin. b11429
is the build v0.6.0 names:

```sh
host/engines llama install b11429
host/engines llama update
```

`install` refuses an older build while `llama` already runs another, so rehearse from a host
where it isn't installed, or after [uninstalling](uninstall.md).

## How the pin moves

The pin is `host/llama.env`: `LLAMA_RELEASE`, the latest semver release, and `LLAMA_BUILD`,
the b-build its notes name ("Nightly build:"), from which `LLAMA_IMAGE` follows. On the laptop,
`mise run currency` reports when a newer release names a newer build:

```sh
mise run currency
```

A line beginning `host/llama.env: llama.cpp` means the pin is behind, and names the new build
and its release. Edit `LLAMA_RELEASE` and `LLAMA_BUILD` in `host/llama.env` to the release
and build it names, and the pin this guide quotes to match: the [README](README.md), and the
image and its `--version` output in [Setup](setup.md#3-prove-the-pinned-image-runs-on-the-gpu).
Commit and push; then, on each host, `git pull` and `host/engines llama update`.
