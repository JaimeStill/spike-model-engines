#!/usr/bin/env bash
# The llama.cpp container, in one place: sourced by the engines-llama-* commands so install and
# update start the same container, from the server image for the version given (llama-release.sh)
# and the flavor (llama_flavor). It runs llama-server in router mode, with no model on its command
# line, the models preset (llama-preset/models.ini) read-only, and the model store (/srv/models)
# as llama.cpp's download cache. It runs as the invoking user, so the store's files stay that
# user's, and publishes port 8080 on the host's tailnet IPv4 address only.

# shellcheck source=host/engines.sh
source "$(dirname "${BASH_SOURCE[0]}")/engines.sh"
# shellcheck source=host/llama-release.sh
source "$(dirname "${BASH_SOURCE[0]}")/llama-release.sh"

LLAMA_CONTAINER=llama
LLAMA_STORE=$ENGINES_STORE
LLAMA_PRESET_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/llama-preset" && pwd)

# Resolves the flavor, the backend ggml built the server image for, into LLAMA_FLAVOR, and the
# docker run options that give its container the GPU into LLAMA_DEVICES. LLAMA_FLAVOR, when set,
# names it: cuda13, the NVIDIA Container Toolkit's GPU (--gpus all); rocm, the kernel's AMD GPU
# driver, its compute device and its render nodes (/dev/kfd, /dev/dri); or vulkan, the render
# nodes alone (/dev/dri). Unset or empty, it follows the GPU the host has: rocm when any DRM card
# under /sys/class/drm has AMD's PCI vendor ID, 0x1002, as the Framework's Strix Halo does, and
# cuda13 otherwise, as on the GB10s. Reading the vendor ID needs no root and no Docker. Refuses
# any other flavor, before Docker is read.
llama_flavor() {
  if [[ -z ${LLAMA_FLAVOR:-} ]]; then
    LLAMA_FLAVOR=cuda13
    if grep -qsx 0x1002 /sys/class/drm/card*/device/vendor; then
      LLAMA_FLAVOR=rocm
    fi
  fi
  case $LLAMA_FLAVOR in
    cuda13) LLAMA_DEVICES=(--gpus all) ;;
    rocm) LLAMA_DEVICES=(--device /dev/kfd --device /dev/dri) ;;
    vulkan) LLAMA_DEVICES=(--device /dev/dri) ;;
    *)
      echo "LLAMA_FLAVOR is $LLAMA_FLAVOR, which is none of cuda13, rocm, or vulkan" >&2
      return 1
      ;;
  esac
}

# The server image for a b-build, in the flavor llama_flavor resolved.
llama_image() {
  echo "$LLAMA_REPOSITORY:server-$LLAMA_FLAVOR-$1"
}

# The image the container runs, or nothing when there is no container. Fails when Docker does,
# so an unreachable daemon is never read as "not installed".
llama_running_image() {
  local id
  id=$(docker container ls --all --quiet --filter "name=^$LLAMA_CONTAINER\$") || return
  [[ -z $id ]] || docker container inspect --format '{{.Config.Image}}' "$id"
}

# The source of the container's preset mount (what /etc/llama-preset binds), or nothing when it has
# none, after llama_running_image finds a container. Update replaces a container whose source isn't
# LLAMA_PRESET_DIR, as when the clone's scripts move. Fails when Docker does, so an unreachable
# daemon is never read as a stale mount.
llama_preset_mount() {
  docker container inspect --format \
    '{{range .Mounts}}{{if eq .Destination "/etc/llama-preset"}}{{.Source}}{{end}}{{end}}' \
    "$LLAMA_CONTAINER"
}

# Checks what llama_run needs before anything is pulled or removed (engines_preflight), and sets
# LLAMA_ADDR to the tailnet address it publishes port 8080 on.
llama_preflight() {
  engines_preflight 8080 && LLAMA_ADDR=$ENGINES_ADDR
}

# Starts the container from the image given, with the flavor's devices, after llama_flavor and
# llama_preflight.
llama_run() {
  docker run --detach --name "$LLAMA_CONTAINER" --restart unless-stopped "${LLAMA_DEVICES[@]}" \
    --user "$(id -u):$(id -g)" \
    --publish "$LLAMA_ADDR:8080:8080" \
    --volume "$LLAMA_STORE:$LLAMA_STORE" --env "LLAMA_CACHE=$LLAMA_STORE" \
    --volume "$LLAMA_PRESET_DIR:/etc/llama-preset:ro" \
    "$1" --models-preset /etc/llama-preset/models.ini --no-models-autoload \
    --host 0.0.0.0 --port 8080
}

# Removes the suite's images, the server images (server-*) in LLAMA_REPOSITORY, but those of the
# b-build given, in every flavor, so a flavor switch keeps the build's other server image; given
# an empty build, it removes every server image. It leaves every other image in the repository: the
# full-<flavor> images llama-bench runs, which a session pulls itself, and an untagged image,
# whose tag no longer says what it is. Prints each image it removes, and stops at the first
# failure, so it never reports an image it did not remove.
llama_remove_images() {
  local tags tag
  tags=$(docker image ls "$LLAMA_REPOSITORY" --format '{{.Tag}}') || return
  for tag in $tags; do
    [[ $tag == server-* ]] || continue
    [[ -n $1 && $tag == *-"$1" ]] && continue
    docker image rm "$LLAMA_REPOSITORY:$tag" >/dev/null || return
    echo "removed image $LLAMA_REPOSITORY:$tag"
  done
}
