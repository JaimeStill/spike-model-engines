#!/usr/bin/env bash
# The vLLM container, in one place: sourced by the engines-vllm-* commands so install and update
# start the same container, from the image for the release given and the flavor (vllm_flavor).
# It runs `vllm serve` (the image's entrypoint) on one row of the rows file (vllm-rows): a model
# and its server flags, the flavor's default row or the one VLLM_MODEL names for the run. The
# model store (/srv/models) is its Hugging Face cache, so the model lands in the same
# models--<org>--<name> layout llama.cpp's do. It runs as the invoking user, so the store's files
# stay that user's, and publishes port 8000 on the host's tailnet IPv4 address only.
#
# Run as a user the image's /etc/passwd doesn't name, the container has no writable home, so the
# compile cache directory (~/.cache/vllm on the host) is mounted as its home: vLLM's
# torch.compile cache, and the Triton and FlashInfer kernels it builds, land there and survive an
# update. USER is set too, since Python's getpass.getuser() otherwise fails on a uid with no
# passwd entry. This is what the image's own non-root variant does in its entrypoint.

# shellcheck source=host/engines.sh
source "$(dirname "${BASH_SOURCE[0]}")/engines.sh"
# shellcheck source=host/vllm.env
source "$(dirname "${BASH_SOURCE[0]}")/vllm.env"

VLLM_CONTAINER=vllm
VLLM_STORE=$ENGINES_STORE
VLLM_CACHE_DIR=$HOME/.cache/vllm
VLLM_HOME=/home/vllm

VLLM_ROWS_FILE=$(dirname "${BASH_SOURCE[0]}")/$VLLM_ROWS

# Resolves the flavor, the GPU platform vLLM's image is built for, into VLLM_FLAVOR; the image
# repository vllm_image names into VLLM_REPOSITORY; the docker run options that give the container
# the GPU into VLLM_DEVICES; and, when VLLM_MODEL names no row for the run, the flavor's default
# row into VLLM_MODEL. VLLM_FLAVOR, when set, names it: cuda, vLLM's CUDA image on the NVIDIA
# Container Toolkit's GPU (--gpus all); or rocm, vLLM's ROCm image on the kernel's AMD GPU driver,
# its compute device and its render nodes (/dev/kfd, /dev/dri), with no --group-add, seccomp, or
# ptrace options, since the device files are open to every account on the Framework. Unset or
# empty, it follows the GPU the host has, as llama_flavor does: rocm when any DRM card under
# /sys/class/drm has AMD's PCI vendor ID, 0x1002, as the Framework's Strix Halo does, and cuda
# otherwise, as on the GB10s. Reading the vendor ID needs no root and no Docker. Refuses any other
# flavor, before Docker is read.
vllm_flavor() {
  if [[ -z ${VLLM_FLAVOR:-} ]]; then
    VLLM_FLAVOR=cuda
    if grep -qsx 0x1002 /sys/class/drm/card*/device/vendor; then
      VLLM_FLAVOR=rocm
    fi
  fi
  case $VLLM_FLAVOR in
    cuda)
      VLLM_REPOSITORY=$VLLM_REPOSITORY_CUDA
      VLLM_DEVICES=(--gpus all)
      VLLM_MODEL=${VLLM_MODEL:-$VLLM_MODEL_CUDA}
      ;;
    rocm)
      VLLM_REPOSITORY=$VLLM_REPOSITORY_ROCM
      VLLM_DEVICES=(--device /dev/kfd --device /dev/dri)
      VLLM_MODEL=${VLLM_MODEL:-$VLLM_MODEL_ROCM}
      ;;
    *)
      echo "VLLM_FLAVOR is $VLLM_FLAVOR, which is neither cuda nor rocm" >&2
      return 1
      ;;
  esac
}

# The rows' ids, one a line, in the rows file's order.
vllm_rows() {
  sed -n 's/^\[\(.*\)\]$/\1/p' "$VLLM_ROWS_FILE"
}

# The words of the row given, one a line: its model, then its server flags. Prints nothing for an
# id the file has no row for.
vllm_row_words() {
  awk -v id="[$1]" '{ sub(/#.*/, "") } /^\[/ { inrow = ($1 == id); next }
    inrow { for (i = 1; i <= NF; i++) print $i }' "$VLLM_ROWS_FILE"
}

# Reads the row VLLM_MODEL names (after vllm_flavor, which sets the flavor's default) into
# VLLM_ARGS, what the container serves after its image: the row's model, the address it listens
# on, and the row's flags. vllm_run starts the container with VLLM_ARGS, and vllm_running's
# comparison reads them back from the container's command, so the two can't drift. No element
# holds a space, so the command joined with spaces reads back unambiguously. Refuses an id with
# no row, listing the rows.
vllm_row() {
  local words
  mapfile -t words < <(vllm_row_words "$VLLM_MODEL")
  if ((${#words[@]} == 0)); then
    echo "vllm has no row $VLLM_MODEL in host/$VLLM_ROWS; its rows are:" >&2
    vllm_rows | sed 's/^/  /' >&2
    return 1
  fi
  VLLM_ARGS=("${words[0]}" --host 0.0.0.0 --port 8000 "${words[@]:1}")
}

# The row, as "row <id> (<model>)", for messages, after vllm_row.
vllm_serves() {
  echo "row $VLLM_MODEL (${VLLM_ARGS[0]})"
}

# What a container serves the row as (after vllm_row), from the image given:
# "<image> <model> <flags...>", in the form vllm_running prints, so a container serving exactly
# the row compares equal.
vllm_served() {
  echo "$1 ${VLLM_ARGS[*]}"
}

# The image for a release, in the flavor vllm_flavor resolved.
vllm_image() {
  echo "$VLLM_REPOSITORY:$1"
}

# What the container serves, as "<image> <model> <flags...>" (vllm_served's form), or nothing when
# there is no container. Fails when Docker does, so an unreachable daemon is never read as "not
# installed". The whole command is read, not only the model, so a changed server flag shows.
vllm_running() {
  local id
  id=$(docker container ls --all --quiet --filter "name=^$VLLM_CONTAINER\$") || return
  [[ -z $id ]] ||
    docker container inspect --format '{{.Config.Image}} {{join .Config.Cmd " "}}' "$id"
}

# The image and the model of what vllm_served or vllm_running printed, as "<image> with <model>",
# for messages.
vllm_describe() {
  local image model
  read -r image model _ <<<"$1"
  echo "$image with $model"
}

# Checks what vllm_run needs before anything is pulled or removed (engines_preflight), and sets
# VLLM_ADDR to the tailnet address it publishes port 8000 on.
vllm_preflight() {
  engines_preflight 8000 && VLLM_ADDR=$ENGINES_ADDR
}

# Starts the container from the image given, with the flavor's devices, serving the row, after
# vllm_flavor, vllm_row, and vllm_preflight. It creates the compile cache directory first, so
# Docker doesn't create it as root.
vllm_run() {
  mkdir -p "$VLLM_CACHE_DIR"
  docker run --detach --name "$VLLM_CONTAINER" --restart unless-stopped "${VLLM_DEVICES[@]}" \
    --ipc host --user "$(id -u):$(id -g)" \
    --publish "$VLLM_ADDR:8000:8000" \
    --volume "$VLLM_STORE:$VLLM_STORE" --env "HF_HUB_CACHE=$VLLM_STORE" \
    --volume "$VLLM_CACHE_DIR:$VLLM_HOME" --env "HOME=$VLLM_HOME" --env "USER=$(id -un)" \
    "$1" "${VLLM_ARGS[@]}"
}

# Removes every vLLM image, in both flavors' repositories, but the one given (none when given
# nothing), printing each. Needs no flavor, so uninstall runs whatever VLLM_FLAVOR says. Stops at
# the first failure, so it never reports an image it did not remove.
vllm_remove_images() {
  local repository listed refs='' ref
  for repository in "$VLLM_REPOSITORY_CUDA" "$VLLM_REPOSITORY_ROCM"; do
    listed=$(docker image ls "$repository" \
      --format '{{if eq .Tag "<none>"}}{{.ID}}{{else}}{{.Repository}}:{{.Tag}}{{end}}') || return
    refs+=" $listed"
  done
  for ref in $refs; do
    [[ $ref == "${1:-}" ]] && continue
    docker image rm "$ref" >/dev/null || return
    echo "removed image $ref"
  done
}
