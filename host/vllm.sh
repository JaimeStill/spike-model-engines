#!/usr/bin/env bash
# The vLLM container, in one place: sourced by the engines-vllm-* commands so install and update
# start the same container, from the image for the release given and the flavor (vllm_flavor).
# It runs `vllm serve` (the image's entrypoint) on one row of the rows file (vllm-rows): a model
# and its server flags, the flavor's default row or the one VLLM_MODEL names for the run. The row
# names the container too, vllm unless it says otherwise, so a host runs one container per row it
# serves, each with its own memory fraction, and every command acts on the row's container alone.
# The model store (/srv/models) is its Hugging Face cache, so the model lands in the same
# models--<org>--<name> layout llama.cpp's do. It runs as the invoking user, so the store's files
# stay that user's, and publishes the row's port, 8000 unless it says otherwise, on the host's
# tailnet IPv4 address only.
#
# Run as a user the image's /etc/passwd doesn't name, the container has no writable home, so the
# compile cache directory (~/.cache/vllm on the host) is mounted as its home: vLLM's
# torch.compile cache, and the Triton and FlashInfer kernels it builds, land there and survive an
# update. USER is set too, since Python's getpass.getuser() otherwise fails on a uid with no
# passwd entry. This is what the image's own non-root variant does in its entrypoint. Every
# container on the host shares the one directory: vLLM keys its compile cache by the model and its
# configuration, so the rows don't overwrite each other's.

# shellcheck source=host/engines.sh
source "$(dirname "${BASH_SOURCE[0]}")/engines.sh"
# shellcheck source=host/vllm.env
source "$(dirname "${BASH_SOURCE[0]}")/vllm.env"

# The container and the port a row serves from when it names neither (vllm_row).
VLLM_CONTAINER_DEFAULT=vllm
VLLM_PORT_DEFAULT=8000
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
#
# The rocm flavor's image is the release's default tag, which on v0.33.0 is its ROCm 10.0 build
# (the same image as its -rocm100 tag). VLLM_ROCM_BUILD, set for one run to the pin's fallback,
# VLLM_ROCM_FALLBACK (rocm72), names that build instead, and vllm_image then names the tag
# <release>-<build>, for the row's own image too. It refuses any other VLLM_ROCM_BUILD, and any on
# the cuda flavor, whose images have no such builds.
vllm_flavor() {
  if [[ -z ${VLLM_FLAVOR:-} ]]; then
    VLLM_FLAVOR=cuda
    if grep -qsx 0x1002 /sys/class/drm/card*/device/vendor; then
      VLLM_FLAVOR=rocm
    fi
  fi
  case $VLLM_FLAVOR in
    cuda)
      if [[ -n ${VLLM_ROCM_BUILD:-} ]]; then
        echo "VLLM_ROCM_BUILD is $VLLM_ROCM_BUILD, but the flavor is cuda, which has no ROCm" \
          "builds" >&2
        return 1
      fi
      VLLM_REPOSITORY=$VLLM_REPOSITORY_CUDA
      VLLM_DEVICES=(--gpus all)
      VLLM_MODEL=${VLLM_MODEL:-$VLLM_MODEL_CUDA}
      ;;
    rocm)
      if [[ -n ${VLLM_ROCM_BUILD:-} && $VLLM_ROCM_BUILD != "$VLLM_ROCM_FALLBACK" ]]; then
        echo "VLLM_ROCM_BUILD is $VLLM_ROCM_BUILD; the only ROCm build the pin names besides" \
          "the default is $VLLM_ROCM_FALLBACK" >&2
        return 1
      fi
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

# Every word of the row given, one a line, in the file's order: its model, its settings, and its
# server flags. Prints nothing for an id the file has no row for.
vllm_row_all_words() {
  awk -v id="[$1]" '{ sub(/#.*/, "") } /^\[/ { inrow = ($1 == id); next }
    inrow { for (i = 1; i <= NF; i++) print $i }' "$VLLM_ROWS_FILE"
}

# A row's settings are its words of the form container=<name>, port=<port>, or
# image=<repository>, which the suite reads and vllm serve never sees (vllm_row). The pattern
# matches one.
VLLM_SETTING_RE='^(container|port|image)='

# The words of the row given, one a line: its model, then its server flags, without its settings.
# Prints nothing for an id the file has no row for.
vllm_row_words() {
  vllm_row_all_words "$1" | grep -Ev "$VLLM_SETTING_RE" || true
}

# The value of the row's setting given (container, port, or image), or nothing when the row names
# none.
vllm_row_setting() {
  vllm_row_all_words "$1" | sed -n "s/^$2=//p" | tail -n 1
}

# The containers every row names, one a line, each once, the default's among them: every vLLM
# container the suite may have started on a host.
vllm_containers() {
  local id
  {
    echo "$VLLM_CONTAINER_DEFAULT"
    for id in $(vllm_rows); do
      vllm_row_setting "$id" container
    done
  } | awk 'NF && !seen[$0]++'
}

# Refuses, as engines_refuse_running does, while any vLLM container (vllm_containers) runs, so
# llama.cpp, in its container or native, never starts beside one.
vllm_refuse_running() {
  local name
  for name in $(vllm_containers); do
    engines_refuse_running "$name" || return
  done
}

# Reads the row VLLM_MODEL names (after vllm_flavor, which sets the flavor's default) into
# VLLM_ARGS, what the container serves after its image: the row's model, the address and port it
# listens on, and the row's flags. vllm_run starts the container with VLLM_ARGS, and vllm_running's
# comparison reads them back from the container's command, so the two can't drift; the port is in
# the command, so a row whose port changes compares unequal. No element holds a space, so the
# command joined with spaces reads back unambiguously. Reads the row's settings too: its container
# into VLLM_CONTAINER and its port into VLLM_PORT, each the default when the row names none; and,
# when it names an image, that repository into VLLM_REPOSITORY in place of the flavor's, with
# VLLM_LOCAL set, since such an image is built on the host and never pulled (vllm_pull). Refuses an
# id with no row, listing the rows.
vllm_row() {
  local words image
  mapfile -t words < <(vllm_row_words "$VLLM_MODEL")
  if ((${#words[@]} == 0)); then
    echo "vllm has no row $VLLM_MODEL in host/$VLLM_ROWS; its rows are:" >&2
    vllm_rows | sed 's/^/  /' >&2
    return 1
  fi
  VLLM_CONTAINER=$(vllm_row_setting "$VLLM_MODEL" container)
  VLLM_CONTAINER=${VLLM_CONTAINER:-$VLLM_CONTAINER_DEFAULT}
  VLLM_PORT=$(vllm_row_setting "$VLLM_MODEL" port)
  VLLM_PORT=${VLLM_PORT:-$VLLM_PORT_DEFAULT}
  VLLM_LOCAL=
  image=$(vllm_row_setting "$VLLM_MODEL" image)
  if [[ -n $image ]]; then
    VLLM_REPOSITORY=$image
    VLLM_LOCAL=yes
  fi
  VLLM_ARGS=("${words[0]}" --host 0.0.0.0 --port "$VLLM_PORT" "${words[@]:1}")
}

# The row, as "row <id> (<model>)", for messages, after vllm_row.
vllm_serves() {
  echo "row $VLLM_MODEL (${VLLM_ARGS[0]})"
}

# The settings the run was given in the environment, VLLM_FLAVOR, VLLM_MODEL, and
# VLLM_ROCM_BUILD, as "NAME=value " each, read before vllm_flavor resolves them, so a message can
# name the command that repeats the run.
vllm_given() {
  local given=${VLLM_FLAVOR:+VLLM_FLAVOR=$VLLM_FLAVOR }${VLLM_MODEL:+VLLM_MODEL=$VLLM_MODEL }
  echo "$given${VLLM_ROCM_BUILD:+VLLM_ROCM_BUILD=$VLLM_ROCM_BUILD }"
}

# What a container serves the row as (after vllm_row), from the image given:
# "<image> <model> <flags...>", in the form vllm_running prints, so a container serving exactly
# the row compares equal.
vllm_served() {
  echo "$1 ${VLLM_ARGS[*]}"
}

# The image for a release, in the repository vllm_flavor resolved, or the row's own (vllm_row):
# <repository>:<release>, or <repository>:<release>-<build> when VLLM_ROCM_BUILD names a build.
vllm_image() {
  echo "$VLLM_REPOSITORY:$1${VLLM_ROCM_BUILD:+-$VLLM_ROCM_BUILD}"
}

# Fetches the image given before the container is started: docker pull for an official image, and
# for a row's own image (VLLM_LOCAL), which no registry holds, only a check that the host has
# built it, refusing with the build it needs (host/vllm-rocm-audio/Dockerfile says how).
vllm_pull() {
  if [[ -z $VLLM_LOCAL ]]; then
    docker pull "$1"
  elif ! docker image inspect "$1" >/dev/null 2>&1; then
    echo "the host has no image $1, which row $VLLM_MODEL serves and the suite never pulls;" \
      "build it first (host/vllm-rocm-audio/Dockerfile)" >&2
    return 1
  fi
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
# VLLM_ADDR to the tailnet address it publishes the row's port on, after vllm_row.
vllm_preflight() {
  engines_preflight "$VLLM_PORT" && VLLM_ADDR=$ENGINES_ADDR
}

# Starts the row's container from the image given, with the flavor's devices, serving the row on
# its port, after vllm_flavor, vllm_row, and vllm_preflight. The server listens on the row's port
# inside the container too, so the port reads back from its command. It creates the compile cache
# directory first, so Docker doesn't create it as root.
vllm_run() {
  mkdir -p "$VLLM_CACHE_DIR"
  docker run --detach --name "$VLLM_CONTAINER" --restart unless-stopped "${VLLM_DEVICES[@]}" \
    --ipc host --user "$(id -u):$(id -g)" \
    --publish "$VLLM_ADDR:$VLLM_PORT:$VLLM_PORT" \
    --volume "$VLLM_STORE:$VLLM_STORE" --env "HF_HUB_CACHE=$VLLM_STORE" \
    --volume "$VLLM_CACHE_DIR:$VLLM_HOME" --env "HOME=$VLLM_HOME" --env "USER=$(id -un)" \
    "$1" "${VLLM_ARGS[@]}"
}

# Removes every vLLM image, in both flavors' official repositories, but the one given (none when
# given nothing) and any a container on the host was created from, such as another row's, printing
# each. A row's own image, built on the host, is never removed. Needs no flavor. Stops at the first
# failure, so it never reports an image it did not remove.
vllm_remove_images() {
  local repository listed refs='' ref used id
  used=$(docker container ls --all --quiet |
    xargs -r docker container inspect --format '{{.Image}}') || return
  for repository in "$VLLM_REPOSITORY_CUDA" "$VLLM_REPOSITORY_ROCM"; do
    listed=$(docker image ls "$repository" \
      --format '{{if eq .Tag "<none>"}}{{.ID}}{{else}}{{.Repository}}:{{.Tag}}{{end}}') || return
    refs+=" $listed"
  done
  for ref in $refs; do
    [[ $ref == "${1:-}" ]] && continue
    id=$(docker image inspect --format '{{.Id}}' "$ref") || return
    [[ -n $used ]] && grep -qxF "$id" <<<"$used" && continue
    docker image rm "$ref" >/dev/null || return
    echo "removed image $ref"
  done
}
