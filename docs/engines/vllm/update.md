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
docker logs --timestamps --since "$(docker inspect --format '{{.State.StartedAt}}' vllm)" vllm 2>&1 | grep -m 1 "Application startup complete"
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
uv's and the kernel install's output, phase by phase as `install` does ([What the native install
runs](setup.md#what-the-native-install-runs)), then what moved and what it removed, then the
server's `/version` and torch's version and CUDA, 13.0. From v0.31.0 to the pin, `update v0.32.0`
in [the walk](#the-walk), uv's install reads:

```text
Using Python 3.12.16 environment at: /opt/vllm/v0.32.0
Resolved 198 packages in 675ms
Downloading vllm (306.5MiB)
```

then seven more `Downloading` lines, transformers and NVIDIA's CUTLASS DSL libraries among them,
their `Downloaded` lines, and

```text
Prepared 17 packages in 17.45s
Installed 198 packages in 200ms
```

uv downloads only the 17 packages v0.31.0's install didn't leave in its cache; the other 181
come from the cache. The kernel install starts with the line `vllm download-kernels` prints
before it installs anything ([What the native install runs](setup.md#what-the-native-install-runs)),
`FlashInfer kernels are disabled: …`, and since v0.32.0 has v0.31.0's FlashInfer, 0.7.0.post1,
both wheels come from the cache too (`Prepared 9 packages in 150ms`). It ends:

```text
built /opt/vllm/v0.32.0
vllm-server moved from v0.31.0 to v0.32.0
removed /opt/vllm/v0.31.0
/version answers {"version":"0.32.0"}; torch 2.13.0+cu130, CUDA 13.0
```

Between `built` and `moved` it waits, silent, for minutes, while the new release starts; follow
`journalctl -fu vllm-server` in a second terminal to watch it. Stopping v0.31.0 before the
start writes `ERROR` lines to the journal, an `EngineDeadError` traceback from vLLM's API server
once its engine is killed on `SIGTERM`; that is v0.31.0 shutting down, not a failure, and
v0.32.0's stop logs none.

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

The build is the cache's: uv resolves the 199 packages and downloads almost none, against 199 in
about 2 minutes on the first install, and the kernel wheels come from the cache as well:

```text
Using Python 3.12.16 environment at: /opt/vllm/v0.31.0
Resolved 199 packages in 325ms
Prepared 5 packages in 1ms
Installed 199 packages in 151ms
```

It ends:

```text
built /opt/vllm/v0.31.0
vllm-server moved from v0.32.0 to v0.31.0
removed /opt/vllm/v0.32.0
/version answers {"version":"0.31.0"}; torch 2.13.0+cu130, CUDA 13.0
```

Forward again is an update with no release, or the pin's:

```sh
host/engines vllm-native update
```

It builds v0.32.0 from the cache in the same way (`Prepared 5 packages in 18ms`), prints the
`FlashInfer kernels are disabled: …` line before its kernel install, as v0.32.0 does, and ends:

```text
built /opt/vllm/v0.32.0
vllm-server moved from v0.31.0 to v0.32.0
removed /opt/vllm/v0.31.0
/version answers {"version":"0.32.0"}; torch 2.13.0+cu130, CUDA 13.0
```

Removing a release removes its virtualenv only. The compile caches in `/opt/vllm/cache` stay, so
a release that comes back starts on the torch.compile it saved the first time: the rollback's
start logged `Directly load AOT compilation from path …` and `torch.compile took 0.30 s in total`,
and the forward's `0.71 s`, against 27 s on each release's first start.

### The walk

The native walk installs the older release, updates to the pin, rolls back, and moves forward
again, each step printing `/version` and torch's CUDA. From the clone, on a host where native
vLLM isn't installed:

```sh
host/engines vllm-native install v0.31.0
MISE_ENV=host UV_CACHE_DIR=/opt/vllm/cache/uv mise exec -- uv pip list --python /opt/vllm/current
host/engines vllm-native update v0.32.0
host/engines vllm-native update v0.31.0
host/engines vllm-native update
```

Each start is a cold start; time and record it as [Setup](setup.md#4-check-it-serves) shows. The
first start of each release compiles from an empty compile cache for that release; a later start
of it, the rollback's and the forward's, loads what that first start saved
([Rolling back](#rolling-back)). The walk's starts on gb10-1, timed, are in
[vllm-gb10-native](../../findings/vllm-gb10-native.md#startup).
