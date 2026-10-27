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
compares the container's whole command with the row's, so it replaces the container when its
image, its model, or any server flag differs; when the image is already the pin's, as when only
the row changes, it replaces the container without pulling. It pulls before it removes anything,
so a failed pull leaves the old release serving. When `vllm` already runs the pinned release and
the row's model and flags, and no other vLLM image is left, it changes nothing and says so; when
that `vllm` is stopped, it says `docker start vllm` starts it, and leaves it stopped. It fails,
changing nothing, when vLLM isn't installed, when `VLLM_MODEL` names no row, or while llama.cpp's
`llama` container or `llama-router` unit runs, and, before it pulls, when `/srv/models` is
missing or the host has no tailnet IPv4 address.

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
`git pull` and `host/engines vllm update`.
