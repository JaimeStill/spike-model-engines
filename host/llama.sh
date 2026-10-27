#!/usr/bin/env bash
# The llama.cpp container, in one place: sourced by the engines-llama-* commands so install and
# update start the same container, from the image for the version given (llama-release.sh). It
# runs llama-server in router mode, with no model on its command line, the models preset
# (llama-preset/models.ini) read-only, and the model store (/srv/models) as llama.cpp's download
# cache. It runs as the invoking user, so the store's files stay that user's, and publishes port
# 8080 on the host's tailnet IPv4 address only.

# shellcheck source=host/engines.sh
source "$(dirname "${BASH_SOURCE[0]}")/engines.sh"
# shellcheck source=host/llama-release.sh
source "$(dirname "${BASH_SOURCE[0]}")/llama-release.sh"

LLAMA_CONTAINER=llama
LLAMA_STORE=$ENGINES_STORE
LLAMA_PRESET_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/llama-preset" && pwd)

# The image for a b-build: the pinned image with its build swapped.
llama_image() {
  echo "${LLAMA_IMAGE%"$LLAMA_BUILD"}$1"
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

# Starts the container from the image given, after llama_preflight.
llama_run() {
  docker run --detach --name "$LLAMA_CONTAINER" --restart unless-stopped --gpus all \
    --user "$(id -u):$(id -g)" \
    --publish "$LLAMA_ADDR:8080:8080" \
    --volume "$LLAMA_STORE:$LLAMA_STORE" --env "LLAMA_CACHE=$LLAMA_STORE" \
    --volume "$LLAMA_PRESET_DIR:/etc/llama-preset:ro" \
    "$1" --models-preset /etc/llama-preset/models.ini --no-models-autoload \
    --host 0.0.0.0 --port 8080
}

# Removes every llama.cpp image but the one given (none when given nothing), printing each. Stops
# at the first failure, so it never reports an image it did not remove.
llama_remove_images() {
  local refs ref
  refs=$(docker image ls "${LLAMA_IMAGE%%:*}" \
    --format '{{if eq .Tag "<none>"}}{{.ID}}{{else}}{{.Repository}}:{{.Tag}}{{end}}') || return
  for ref in $refs; do
    [[ $ref == "${1:-}" ]] && continue
    docker image rm "$ref" >/dev/null || return
    echo "removed image $ref"
  done
}
