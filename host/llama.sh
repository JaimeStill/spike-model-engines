#!/usr/bin/env bash
# The llama.cpp container: sourced by the engines-llama-* commands, so install and update start
# the same container, from the server image for the version given (llama-release.sh) and the
# flavor (llama_flavor). It runs llama-server in router mode, with no model on its command line,
# the models preset (llama-preset/models.ini) read-only, and the model store (/srv/models) as
# llama.cpp's download cache, as the invoking user, publishing port 8080 on the host's tailnet
# IPv4 address only.
#
# See docs/engines/llama.cpp/scripts.md#the-container

# shellcheck source=host/engines.sh
source "$(dirname "${BASH_SOURCE[0]}")/engines.sh"
# shellcheck source=host/llama-release.sh
source "$(dirname "${BASH_SOURCE[0]}")/llama-release.sh"

LLAMA_CONTAINER=llama
LLAMA_STORE=$ENGINES_STORE
LLAMA_PRESET_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/llama-preset" && pwd)

llama_flavor() {
  if [[ -z ${LLAMA_FLAVOR:-} ]]; then
    LLAMA_FLAVOR=cuda13
    if grep -qsx 0x1002 /sys/class/drm/card*/device/vendor; then
      LLAMA_FLAVOR=rocm
    fi
  fi
  case $LLAMA_FLAVOR in
    cuda13) LLAMA_CLASS=gb10 LLAMA_DEVICES=(--gpus all) ;;
    rocm) LLAMA_CLASS=strix-halo LLAMA_DEVICES=(--device /dev/kfd --device /dev/dri) ;;
    vulkan) LLAMA_CLASS=strix-halo LLAMA_DEVICES=(--device /dev/dri) ;;
    *)
      echo "LLAMA_FLAVOR is $LLAMA_FLAVOR, which is none of cuda13, rocm, or vulkan" >&2
      return 1
      ;;
  esac
}

llama_image() {
  echo "$LLAMA_REPOSITORY:server-$LLAMA_FLAVOR-$1"
}

llama_running_image() {
  local id
  id=$(docker container ls --all --quiet --filter "name=^$LLAMA_CONTAINER\$") || return
  [[ -z $id ]] || docker container inspect --format '{{.Config.Image}}' "$id"
}

llama_preset_mount() {
  docker container inspect --format \
    '{{range .Mounts}}{{if eq .Destination "/etc/llama-preset"}}{{.Source}}{{end}}{{end}}' \
    "$LLAMA_CONTAINER"
}

llama_preflight() {
  engines_preflight 8080 && LLAMA_ADDR=$ENGINES_ADDR
}

llama_run() {
  docker run --detach --name "$LLAMA_CONTAINER" --restart unless-stopped "${LLAMA_DEVICES[@]}" \
    --user "$(id -u):$(id -g)" \
    --publish "$LLAMA_ADDR:8080:8080" \
    --volume "$LLAMA_STORE:$LLAMA_STORE" --env "LLAMA_CACHE=$LLAMA_STORE" \
    --volume "$LLAMA_PRESET_DIR:/etc/llama-preset:ro" \
    "$1" --models-preset /etc/llama-preset/models.ini --no-models-autoload \
    --host 0.0.0.0 --port 8080
}

llama_remove_images() {
  local refs ref
  refs=$(docker image ls "$LLAMA_REPOSITORY" \
    --format '{{if eq .Tag "<none>"}}{{.ID}}{{else}}{{.Repository}}:{{.Tag}}{{end}}') || return
  for ref in $refs; do
    [[ -n $1 && $ref == "$LLAMA_REPOSITORY":*-"$1" ]] && continue
    docker image rm "$ref" >/dev/null || return
    echo "removed image $ref"
  done
}
