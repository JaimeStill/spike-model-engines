#!/usr/bin/env bash
# The llama.cpp container, in one place: sourced by the engines-llama-* commands so install and
# update start the same container. It runs llama-server in router mode, with no model on its
# command line, the models preset (llama-preset/models.ini) read-only, and the model store
# (/srv/models) as llama.cpp's download cache. It runs as the invoking user, so the store's files
# stay that user's, and publishes port 8080 on the host's tailnet IPv4 address only.

# shellcheck source=engines/llama.env
source "$(dirname "${BASH_SOURCE[0]}")/llama.env"

LLAMA_CONTAINER=llama
LLAMA_STORE=/srv/models
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

# Checks what llama_run needs before anything is pulled or removed: the model store, and the
# host's tailnet IPv4 address, which it sets in LLAMA_ADDR. Without the address, docker would
# publish the port on every interface.
llama_preflight() {
  if [[ ! -d $LLAMA_STORE ]]; then
    echo "$LLAMA_STORE does not exist; create it first (docs/engines/llama.cpp/setup.md)" >&2
    return 1
  fi
  if ! LLAMA_ADDR=$(tailscale ip -4) || [[ -z $LLAMA_ADDR ]]; then
    echo "the host has no tailnet IPv4 address to publish port 8080 on; is Tailscale up?" >&2
    return 1
  fi
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
