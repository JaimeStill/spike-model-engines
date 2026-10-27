# Update

## Moving to the pinned release or model

On the host, from the clone, bring the clone current, then update:

```sh
git pull
host/engines vllm update
```

`update` pulls the pinned image, replaces the `vllm` container with one running it on the pin's
default row, and removes every other vLLM image, so only the pinned image remains. With
`VLLM_MODEL=<row id>` before it, it serves that row instead, for one run
([Models](models.md#serving-another-row-for-one-run)); without, it returns to the default. It
compares the container's whole command with the row's, so it replaces the container when its image,
its model, or any server flag differs; when the image is already the pin's, as when only the row
changes, it replaces the container without pulling. It pulls before it removes anything, so a failed
pull leaves the old release serving. When `vllm` already runs the pinned release and the row's model
and flags, and no other vLLM image is left, it changes nothing and says so; when that `vllm` is
stopped, it says `docker start vllm` starts it, and leaves it stopped. It fails, changing nothing,
when vLLM isn't installed, when `VLLM_MODEL` names no row, or while llama.cpp's `llama` container or
`llama-router` unit runs, or native vLLM's `vllm-server` does, and, before it pulls, when
`/srv/models` is missing or the host has no tailnet IPv4 address.

The new container starts cold. Follow its log until `Application startup complete.`, then time
and record the cold start as [Setup](setup.md#6-watch-the-cold-start-and-record-it) shows:

```sh
docker logs -f vllm
docker inspect --format '{{.State.StartedAt}}' vllm
docker logs --timestamps vllm 2>&1 | grep -m 1 "Application startup complete"
```

Then check the release it runs:

```sh
docker inspect --format '{{.Config.Image}} {{join .Config.Cmd " "}}' vllm
docker image ls vllm/vllm-openai
```

The first prints the pinned image, then the row's model and server flags the container serves;
the second lists the pinned image alone. The laptop confirms the version the server itself runs
([API](api.md#version)), which reads `0.32.0` at the pin.

## Rehearsing an update

To walk an update before the pin moves, install an older release, then update to the pin:

```sh
host/engines vllm install v0.31.0
host/engines vllm update
```

`install` refuses an older release while `vllm` already runs another, so rehearse from a host
where it isn't installed, or after [uninstalling](uninstall.md). Both starts are cold starts to
record; the second may compile again, under the new release.

## How the pin moves

The pin is `host/vllm.env`: `VLLM_RELEASE`, the latest GitHub release, from which
`VLLM_IMAGE` follows, and `VLLM_MODEL`, the row of `host/vllm-rows` the server serves by
default. On the laptop, `mise run currency` reports when a newer release is out:

```sh
mise run currency
```

A line beginning `host/vllm.env: vLLM` means the pin is behind, and names the new release.
Edit `VLLM_RELEASE` in `host/vllm.env` to it, and the pin this guide quotes to match: the
[README](README.md), the image and its `--version` output in
[Setup](setup.md#2-prove-the-pinned-image-runs-on-the-gpu), and the version in
[API](api.md#version). A new default row edits `VLLM_MODEL` instead
([Models](models.md#adding-a-row-or-moving-the-default)). Commit and push; then, on the host,
`git pull` and `host/engines vllm update`, or `host/engines vllm-native update` where native vLLM
serves ([Native](#native)).

## Native

Native vLLM ([Setup](setup.md#gb10-native)) updates with its own command, from the clone, after
`git pull`; with no release it moves to the pin, v0.32.0, on the pin's default row:

```sh
git pull
host/engines vllm-native update
```

`update` compares the release `current` names with the pin, and the row file, `/opt/vllm/row`,
with the row, as the container's update compares the container's command, so it moves when the
release, the model, or a server flag differs. It builds the new release's virtualenv first, with
its kernels ([What the native install runs](setup.md#what-the-native-install-runs)), while the
old release still serves. Then, since two servers can't both reserve 0.80 of the GB10's memory,
it stops `vllm-server` before it points `current` at the new release, writes the row file, and
starts it again. It waits for `/health` to answer, for at most 10 minutes. Only once the new
release serves does it remove every other release, so only the serving release is kept. It prints
uv's and the kernel install's output, then what moved and what it removed, then the server's
`/version` and torch's version and CUDA, 13.0.

When the start fails, `update` stops before removing anything, saying `journalctl -u
vllm-server` shows why and that the old release stays, with the update that moves back to it,
which needs no build. Check the release:

```sh
readlink /opt/vllm/current
cat /opt/vllm/row
command ls /opt/vllm
curl -s "http://$(tailscale ip -4):8000/version"
/opt/vllm/current/bin/python -c "import torch; print(torch.__version__, torch.version.cuda)"
```

`readlink` prints the release; `ls` lists it beside `cache`, `current`, `python`, and `row`. The
laptop reads the version the server runs ([API](api.md#version)).

Run a second time, `update` changes nothing and says so; when `vllm-server` is stopped, it
enables and starts it. With `VLLM_MODEL=<row id>` before it, it serves that row, restarting
`vllm-server` on the release it is at, with no build; without, it returns to the default row. It
fails, changing nothing, when native vLLM isn't installed, and for the reasons `install` does:
another engine serving, the root steps or uv missing, `/srv/models` missing, no tailnet address,
or a release or row that isn't one ([Setup](setup.md#3-install)).

### Rolling back

A rollback is an update to the older release: it builds the older release again, since only the
serving release is kept, from uv's cache, which still holds its packages, runs its kernel install,
stops the server, re-points `current` at it, starts it, and removes the newer one:

```sh
host/engines vllm-native update v0.31.0
```

Forward again is an update with no release, or the pin's:

```sh
host/engines vllm-native update
```

### The walk

The native walk installs the older release, updates to the pin, rolls back, and moves forward
again, each step printing `/version` and torch's CUDA. From the clone, on a host where native
vLLM isn't installed:

```sh
host/engines vllm-native install v0.31.0
MISE_ENV=host mise exec -- uv pip list --python /opt/vllm/current
host/engines vllm-native update v0.32.0
host/engines vllm-native update v0.31.0
host/engines vllm-native update
```

Each start is a cold start; time and record it as [Setup](setup.md#4-check-it-serves) shows. The
first start of each release compiles from an empty compile cache for that release.
