# How the scripts work

This page explains what the `engines` commands' libraries leave unsaid in their code: why each
function reads, refuses, or waits as it does. Each library's header points at its section here.
The libraries shared with vLLM, the model store and the one-engine-per-host refusals, live in
this guide, since llama.cpp's [Setup](setup.md#5-create-the-model-store) creates the store; vLLM's
libraries are in [vLLM's scripts](../vllm/scripts.md).

## What every engine shares

`host/engines.sh` is sourced by `host/llama.sh` and `host/vllm.sh`, and through them by the native
libraries. The model store, `/srv/models`, is one Hugging Face cache that every engine reads and
writes. One engine serves per host at a time, since each reserves most of the host's GPU memory,
whatever the host.

- `engines_refuse_running <container>` refuses, naming the command that stops it, while the
  container runs, or restarts, as a failing one does under `--restart unless-stopped`. It fails
  when Docker does, so an unreachable daemon is never read as "not running".
- `engines_unit_up <unit>` says whether the system unit is up: active, activating, as a failing
  one is between restarts, or reloading. A host without the unit, or without systemd, reads as
  not up.
- `engines_refuse_unit <unit>` refuses, naming the commands that stop it, while the unit is up:
  native llama.cpp's `llama-router` and native vLLM's `vllm-server` each serve on the same port and
  memory as their engine's container would. The unit is read by name alone, so another project's
  unit of the same name, such as the `llama-router` spike-model-hosting ran on the Framework until
  its retirement ([Retire the router](setup.md#5-retire-the-router)), refuses too. The commands it
  names use plain `sudo`, not `sudo -n`, since such a unit has no `NOPASSWD` rule and `sudo` asks
  for the password.
- `engines_stopped <container>` prints the container's ID when it exists but is stopped (exited,
  or created and never started), and nothing otherwise, so install and update can say "stopped"
  rather than "already runs" after a `docker stop`. It fails when Docker does, so an unreachable
  daemon is never read as "not stopped".
- `engines_root_steps <dir> <unit> <section>` checks a native engine's root steps, the
  architect's, before anything is fetched or started: the directory exists and the invoking user
  can write it, systemd has the unit loaded (installed, then `daemon-reload`), and `sudo -n`
  allows each `systemctl` verb the commands run on it without a password. `sudo -l` answers yes
  for an account that may run anything with its password, so the check reads the `NOPASSWD`
  rule's line itself. Each refusal names the guide section given, which holds the root steps.
- `engines_preflight <port>` checks what an engine's container needs before anything is pulled or
  removed: the model store, and the host's tailnet IPv4 address, which it sets in `ENGINES_ADDR`.
  Without the address, Docker would publish the port on every interface.

## The versions

`host/llama-release.sh` resolves a version the same way for `scripts/currency.sh`,
`host/llama.sh`, and through it native llama.cpp. It reads release notes with curl and bash alone,
since the host's scripts run outside mise and can't count on its jq.

- `llama_release <tag>` prints the semver release's tag and the b-build its notes name, as
  `<tag> <build>`, such as `v0.7.0 b11669`. It reads the network, and fails, saying why, when the
  release can't be read or its notes name no b-build.
- `LLAMA_CLASSES` lists the host classes llama.cpp is pinned for, each with its own build in
  `host/llama.env` ([Where the pins stand](update.md#where-the-pins-stand)): `gb10`, the GB10s,
  whose flavor is cuda13, and `strix-halo`, the Framework's Strix Halo, whose flavors are rocm and
  vulkan. `llama_flavor` sets `LLAMA_CLASS` from the flavor; native llama.cpp, a CUDA arm64
  prebuilt, is gb10's.
- `llama_pin <class>` prints the class's pin, and refuses any other class.
- `llama_build [version]` prints the b-build for the version given: a b-build as given, a semver
  release's b-build from its notes (`llama_release`), and the pin of `LLAMA_CLASS`'s class
  (`llama_pin`) when given nothing. It refuses anything else.

## The container

`host/llama.sh` starts the `llama` container the same way for install and update. The container
runs as the invoking user, so the store's files stay that user's.

- `llama_flavor` resolves the flavor, the backend ggml built the server image for, into
  `LLAMA_FLAVOR`, and the `docker run` options that give its container the GPU into
  `LLAMA_DEVICES`. `LLAMA_FLAVOR`, when set, names it: `cuda13`, the NVIDIA Container Toolkit's GPU
  (`--gpus all`); `rocm`, the kernel's AMD GPU driver, its compute device and its render nodes
  (`/dev/kfd`, `/dev/dri`); or `vulkan`, the render nodes alone (`/dev/dri`). Unset or empty, it
  follows the GPU the host has: `rocm` when any DRM card under `/sys/class/drm` has AMD's PCI vendor
  ID, `0x1002`, as the Framework's Strix Halo does, and `cuda13` otherwise, as on the GB10s.
  Reading the vendor ID needs no root and no Docker. It sets `LLAMA_CLASS` to the flavor's host
  class, whose pin `llama_build` reads: gb10 for cuda13, strix-halo for rocm and vulkan. It refuses
  any other flavor, before Docker is read.
- `llama_image <build>` names the server image for a b-build, in the flavor `llama_flavor`
  resolved.
- `llama_running_image` prints the image the container runs, or nothing when there is no
  container. It fails when Docker does, so an unreachable daemon is never read as "not installed".
- `llama_preset_mount` prints the source of the container's preset mount (what
  `/etc/llama-preset` binds), or nothing when it has none. Update replaces a container whose source
  isn't `LLAMA_PRESET_DIR`, as when the clone's scripts move. It fails when Docker does, so an
  unreachable daemon is never read as a stale mount.
- `llama_preflight` runs `engines_preflight` on port 8080 and sets `LLAMA_ADDR` to the tailnet
  address the container publishes on.
- `llama_run <image>` starts the container from the image, with the flavor's devices, after
  `llama_flavor` and `llama_preflight`.
- `llama_remove_images <build>` removes the images in `LLAMA_REPOSITORY` but those of the b-build
  given: every tagged image whose tag names another build, `server-*` and `full-*`, in every
  flavor, and every untagged image, by ID, since its tag no longer says which build it is. It keeps
  the given build's images, server and full, in every flavor, so a flavor switch keeps the build's
  other server image and llama-bench keeps the build's full images; given an empty build, as
  uninstall gives it, it removes every llama.cpp image. It prints each image it removes, and stops
  at the first failure, so it never reports an image it did not remove.

## Native

`host/llama-native.sh` fetches, points at, and serves a build the same way for the
`llama-native` commands ([GB10, native](setup.md#gb10-native) says what a build and its links
are). The prebuilt is the GB10s', so native llama.cpp takes gb10's pin (`LLAMA_CLASS=gb10`).

- `llama_native_current` prints the build `current` names, and `llama_native_preset` the directory
  `preset` names; each prints nothing when there is no link.
- `llama_native_active`, `llama_native_enabled`, and `llama_native_serving` say whether
  `llama-router` is active, enabled, or both, as `systemctl` reports them; a host without the unit
  reads as neither.
- `llama_native_preflight` checks the architect's root steps before anything is fetched or started
  (`engines_root_steps`): `/opt/llama.cpp`, the unit, and its sudoers rule. Then it checks what
  serving needs (`engines_preflight`), and sets `LLAMA_ADDR` to the tailnet address the unit binds.
- `llama_native_fetch <build>` fetches the build into `/opt/llama.cpp/<build>`, unless it is there:
  it reads the release's assets from GitHub, downloads the prebuilt and the CUDA runtime tarballs,
  checks each against its sha256 digest, and unpacks both into one directory. Each asset's fields
  are read from its name to its download URL, which GitHub lists last. It works in a hidden staging
  directory and moves the build into place only once both are unpacked, so a failed or interrupted
  fetch never leaves a build that looks whole; the staging directory goes either way. It reads the
  assets with curl and bash alone, as `llama-release.sh` reads the notes. Its body is a subshell,
  so its trap and variables stay its own.
- `llama_native_response_held <json>` says what GitHub's response held when it lists no asset of
  that name. GitHub has answered once without the asset, and the retry found it, cause unknown
  ([llama-gb10-native](../../findings/llama-gb10-native.md), "Walkthrough"), so the error gives
  GitHub's message when it gave one, or else the response's size in bytes and the number of
  assets it listed, one download URL each. `LC_ALL=C` makes `${#}` count bytes, inside the
  function's own subshell.
- `llama_native_link <link> <target>` points `current` or `preset` at the target given.
- `llama_native_serve [restart]` brings `llama-router` up on the build `current` names, after
  `llama_native_preflight`: it enables it, so it starts at boot, when it isn't enabled; restarts it
  when given `restart`, as after `current` or `preset` moves, or else starts it when it isn't
  active; then waits until it answers `/health` on port 8080 of `LLAMA_ADDR`, for at most 60
  seconds. Each `systemctl` call is one the sudoers rule names exactly.
- `llama_native_remove_builds [build]` removes every build under `/opt/llama.cpp` but the one given
  (all of them when given nothing), and any staging directory a killed fetch left, printing each.
  It stops at the first failure, so it never reports a build it did not remove.
