# Update

## Moving to the pinned build

On the host, from the clone, bring the clone current, then update:

```sh
git pull
engines/engines llama update
```

`update` pulls the pinned image, replaces the `llama` container with one running it, and removes
every other llama.cpp image, so only the pinned image remains. It pulls before it removes
anything, so a failed pull leaves the old build serving. When `llama` already runs the pin and no
other llama.cpp image is left, it changes nothing and says so. It fails, changing nothing, when
llama.cpp isn't installed, and, before it pulls, when `/srv/models` is missing or the host has no
tailnet IPv4 address.

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
engines/engines llama install b11429
engines/engines llama update
```

`install` refuses an older build while `llama` already runs another, so rehearse from a host
where it isn't installed, or after [uninstalling](uninstall.md).

## How the pin moves

The pin is `engines/llama.env`: `LLAMA_RELEASE`, the latest semver release, and `LLAMA_BUILD`,
the b-build its notes name ("Nightly build:"), from which `LLAMA_IMAGE` follows. On the laptop,
`mise run currency` reports when a newer release names a newer build:

```sh
mise run currency
```

A line beginning `engines/llama.env: llama.cpp` means the pin is behind, and names the new build
and its release. Edit `LLAMA_RELEASE` and `LLAMA_BUILD` in `engines/llama.env` to the release
and build it names, and the pin this guide quotes to match: the [README](README.md), and the
image and its `--version` output in [Setup](setup.md#3-prove-the-pinned-image-runs-on-the-gpu).
Commit and push; then, on each host, `git pull` and `engines/engines llama update`.
