# Update

## Moving to the pinned release or model

On the host, from the clone, bring the clone current, then update:

```sh
git pull
engines/engines vllm update
```

`update` pulls the pinned image, replaces the `vllm` container with one running it on the pinned
model, and removes every other vLLM image, so only the pinned image remains. It compares the
container's whole command with the pin's, so it replaces the container when its image, its model,
or any server flag differs; when only a flag differs, the image is already the pin's, and it
replaces the container without pulling. It pulls before it removes anything, so a failed pull
leaves the old release serving. When `vllm` already runs the pinned release, model, and flags,
and no other vLLM image is left, it changes nothing and says so; when that `vllm` is stopped, it
says `docker start vllm` starts it, and leaves it stopped. It fails,
changing nothing, when vLLM isn't installed or while llama.cpp's `llama` runs, and, before it
pulls, when `/srv/models` is missing or the host has no tailnet IPv4 address.

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

The first prints the pinned image, then the model and the server flags the container serves;
the second lists the pinned image alone. The laptop confirms the version the server itself runs
([API](api.md#version)), which reads `0.32.0` at the pin.

## Rehearsing an update

To walk an update before the pin moves, install an older release, then update to the pin:

```sh
engines/engines vllm install v0.31.0
engines/engines vllm update
```

`install` refuses an older release while `vllm` already runs another, so rehearse from a host
where it isn't installed, or after [uninstalling](uninstall.md). Both starts are cold starts to
record; the second may compile again, under the new release.

## How the pin moves

The pin is `engines/vllm.env`: `VLLM_RELEASE`, the latest GitHub release, from which
`VLLM_IMAGE` follows, and `VLLM_MODEL`, the model the server serves. On the laptop,
`mise run currency` reports when a newer release is out:

```sh
mise run currency
```

A line beginning `engines/vllm.env: vLLM` means the pin is behind, and names the new release.
Edit `VLLM_RELEASE` in `engines/vllm.env` to it, and the pin this guide quotes to match: the
[README](README.md), the image and its `--version` output in
[Setup](setup.md#2-prove-the-pinned-image-runs-on-the-gpu), and the version in
[API](api.md#version). A model change edits `VLLM_MODEL` instead
([Models](models.md#changing-the-model)). Commit and push; then, on each host, `git pull` and
`engines/engines vllm update`.
