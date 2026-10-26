#!/usr/bin/env bash
# The vLLM container, in one place: sourced by the engines-vllm-* commands so install and update
# start the same container. It runs `vllm serve` (the image's entrypoint) on one row of the rows
# file (vllm-rows): a model and its server flags, the pin's default row or the one VLLM_MODEL
# names for the run. The model store (/srv/models) is its Hugging Face cache, so the model lands
# in the same models--<org>--<name> layout llama.cpp's do. It runs as the invoking user, so the
# store's files stay that user's, and publishes port 8000 on the host's tailnet IPv4 address
# only.
#
# Run as a user the image's /etc/passwd doesn't name, the container has no writable home, so the
# compile cache directory (~/.cache/vllm on the host) is mounted as its home: vLLM's
# torch.compile cache, and the Triton and FlashInfer kernels it builds, land there and survive an
# update. USER is set too, since Python's getpass.getuser() otherwise fails on a uid with no
# passwd entry. This is what the image's own non-root variant does in its entrypoint.

# shellcheck source=engines/engines.sh
source "$(dirname "${BASH_SOURCE[0]}")/engines.sh"
# shellcheck source=engines/vllm.env
source "$(dirname "${BASH_SOURCE[0]}")/vllm.env"

VLLM_CONTAINER=vllm
VLLM_STORE=$ENGINES_STORE
VLLM_CACHE_DIR=$HOME/.cache/vllm
VLLM_HOME=/home/vllm

VLLM_ROWS_FILE=$(dirname "${BASH_SOURCE[0]}")/$VLLM_ROWS

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

# Reads the row VLLM_MODEL names into VLLM_ARGS, what the container serves after its image: the
# row's model, the address it listens on, and the row's flags. vllm_run starts the container with
# VLLM_ARGS, and vllm_running's comparison reads them back from the container's command, so the
# two can't drift. No element holds a space, so the command joined with spaces reads back
# unambiguously. Refuses an id with no row, listing the rows.
vllm_row() {
  local words
  mapfile -t words < <(vllm_row_words "$VLLM_MODEL")
  if ((${#words[@]} == 0)); then
    echo "vllm has no row $VLLM_MODEL in engines/$VLLM_ROWS; its rows are:" >&2
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

# The image for a release: the pinned image with its release swapped.
vllm_image() {
  echo "${VLLM_IMAGE%"$VLLM_RELEASE"}$1"
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

# Starts the container from the image given, serving the row, after vllm_row and vllm_preflight.
# It creates the compile cache directory first, so Docker doesn't create it as root.
vllm_run() {
  mkdir -p "$VLLM_CACHE_DIR"
  docker run --detach --name "$VLLM_CONTAINER" --restart unless-stopped --gpus all --ipc host \
    --user "$(id -u):$(id -g)" \
    --publish "$VLLM_ADDR:8000:8000" \
    --volume "$VLLM_STORE:$VLLM_STORE" --env "HF_HUB_CACHE=$VLLM_STORE" \
    --volume "$VLLM_CACHE_DIR:$VLLM_HOME" --env "HOME=$VLLM_HOME" --env "USER=$(id -un)" \
    "$1" "${VLLM_ARGS[@]}"
}

# Removes every vLLM image but the one given (none when given nothing), printing each. Stops at
# the first failure, so it never reports an image it did not remove.
vllm_remove_images() {
  local refs ref
  refs=$(docker image ls "${VLLM_IMAGE%%:*}" \
    --format '{{if eq .Tag "<none>"}}{{.ID}}{{else}}{{.Repository}}:{{.Tag}}{{end}}') || return
  for ref in $refs; do
    [[ $ref == "${1:-}" ]] && continue
    docker image rm "$ref" >/dev/null || return
    echo "removed image $ref"
  done
}
