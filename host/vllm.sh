#!/usr/bin/env bash
# The vLLM container: sourced by the engines-vllm-* commands, so install and update start the same
# container, from the image for the release given and the flavor (vllm_flavor). It runs `vllm
# serve` (the image's entrypoint) on one row of the rows file (vllm-rows): a model and its server
# flags, the flavor's default row or the one VLLM_MODEL names for the run. The row names the
# container too, vllm unless it says otherwise, and its port, 8000 unless it says otherwise. The
# container runs as the invoking user, with the model store (/srv/models) as its Hugging Face
# cache and the compile cache directory (~/.cache/vllm) as its home, publishing the row's port on
# the host's tailnet IPv4 address only. A run given VLLM_TRACE=on traces the row
# (docs/engines/vllm/models.md#tracing-a-row-for-one-run).
#
# See docs/engines/vllm/scripts.md#the-container

# shellcheck source=host/engines.sh
source "$(dirname "${BASH_SOURCE[0]}")/engines.sh"
# shellcheck source=host/vllm.env
source "$(dirname "${BASH_SOURCE[0]}")/vllm.env"

VLLM_CONTAINER_DEFAULT=vllm
VLLM_PORT_DEFAULT=8000
VLLM_STORE=$ENGINES_STORE
VLLM_CACHE_DIR=$HOME/.cache/vllm
VLLM_HOME=/home/vllm

VLLM_ROWS_FILE=$(dirname "${BASH_SOURCE[0]}")/$VLLM_ROWS

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

vllm_rows() {
  sed -n 's/^\[\(.*\)\]$/\1/p' "$VLLM_ROWS_FILE"
}

vllm_row_all_words() {
  awk -v id="[$1]" '{ sub(/#.*/, "") } /^\[/ { inrow = ($1 == id); next }
    inrow { for (i = 1; i <= NF; i++) print $i }' "$VLLM_ROWS_FILE"
}

VLLM_SETTING_RE='^(container|port|image)='

vllm_row_words() {
  vllm_row_all_words "$1" | grep -Ev "$VLLM_SETTING_RE" || true
}

vllm_row_setting() {
  vllm_row_all_words "$1" | sed -n "s/^$2=//p" | tail -n 1
}

vllm_containers() {
  local id
  {
    echo "$VLLM_CONTAINER_DEFAULT"
    for id in $(vllm_rows); do
      vllm_row_setting "$id" container
    done
  } | awk 'NF && !seen[$0]++'
}

vllm_refuse_running() {
  local name
  for name in $(vllm_containers); do
    engines_refuse_running "$name" || return
  done
}

vllm_row() {
  local words image
  mapfile -t words < <(vllm_row_words "$VLLM_MODEL")
  if ((${#words[@]} == 0)); then
    echo "vllm has no row $VLLM_MODEL in host/$VLLM_ROWS; its rows are:" >&2
    vllm_rows | sed 's/^/  /' >&2
    return 1
  fi
  VLLM_CONTAINER=$(vllm_row_setting "$VLLM_MODEL" container) || return
  VLLM_CONTAINER=${VLLM_CONTAINER:-$VLLM_CONTAINER_DEFAULT}
  VLLM_PORT=$(vllm_row_setting "$VLLM_MODEL" port) || return
  VLLM_PORT=${VLLM_PORT:-$VLLM_PORT_DEFAULT}
  VLLM_LOCAL=
  image=$(vllm_row_setting "$VLLM_MODEL" image) || return
  if [[ -n $image ]]; then
    VLLM_REPOSITORY=$image
    VLLM_LOCAL=yes
  fi
  VLLM_ARGS=("${words[0]}" --host 0.0.0.0 --port "$VLLM_PORT" "${words[@]:1}")
  case ${VLLM_TRACE:-} in
    '') ;;
    on)
      VLLM_ALIAS=$(printf '%s\n' "${words[@]}" | sed -n '/^--served-model-name$/{n;p;}') ||
        return
      VLLM_ALIAS=${VLLM_ALIAS:-$VLLM_MODEL}
      VLLM_ARGS+=(--otlp-traces-endpoint "grpc://$VLLM_TRACE_COLLECTOR")
      ;;
    *)
      echo "VLLM_TRACE is $VLLM_TRACE, which is neither on nor empty" >&2
      return 1
      ;;
  esac
}

vllm_serves() {
  echo "row $VLLM_MODEL (${VLLM_ARGS[0]})"
}

vllm_given() {
  local given=${VLLM_FLAVOR:+VLLM_FLAVOR=$VLLM_FLAVOR }${VLLM_MODEL:+VLLM_MODEL=$VLLM_MODEL }
  echo "$given${VLLM_TRACE:+VLLM_TRACE=$VLLM_TRACE }"
}

vllm_served() {
  echo "$1 ${VLLM_ARGS[*]}"
}

vllm_image() {
  echo "$VLLM_REPOSITORY:$1"
}

vllm_pull() {
  if [[ -z $VLLM_LOCAL ]]; then
    docker pull "$1"
  elif ! docker image inspect "$1" >/dev/null 2>&1; then
    echo "the host has no image $1, which row $VLLM_MODEL serves and the suite never pulls;" \
      "build it first (host/vllm-rocm-audio/Dockerfile)" >&2
    return 1
  fi
}

vllm_running() {
  local id
  id=$(docker container ls --all --quiet --filter "name=^$VLLM_CONTAINER\$") || return
  [[ -z $id ]] ||
    docker container inspect --format '{{.Config.Image}} {{join .Config.Cmd " "}}' "$id"
}

vllm_describe() {
  local image model
  read -r image model _ <<<"$1"
  echo "$image with $model"
}

vllm_preflight() {
  local host addr
  engines_preflight "$VLLM_PORT" && VLLM_ADDR=$ENGINES_ADDR || return
  VLLM_TRACE_OPTS=()
  [[ -n ${VLLM_TRACE:-} ]] || return 0
  host=${VLLM_TRACE_COLLECTOR%:*}
  if ! addr=$(tailscale ip -4 "$host") || [[ -z $addr ]]; then
    echo "the tailnet has no IPv4 address for $host, the trace collector's host" \
      "(VLLM_TRACE_COLLECTOR); is it up?" >&2
    return 1
  fi
  VLLM_TRACE_OPTS=(--add-host "$host:$addr" --env "OTEL_SERVICE_NAME=vllm-$VLLM_ALIAS")
}

vllm_run() {
  mkdir -p "$VLLM_CACHE_DIR"
  docker run --detach --name "$VLLM_CONTAINER" --restart unless-stopped "${VLLM_DEVICES[@]}" \
    --ipc host --user "$(id -u):$(id -g)" \
    --publish "$VLLM_ADDR:$VLLM_PORT:$VLLM_PORT" \
    --volume "$VLLM_STORE:$VLLM_STORE" --env "HF_HUB_CACHE=$VLLM_STORE" \
    --volume "$VLLM_CACHE_DIR:$VLLM_HOME" --env "HOME=$VLLM_HOME" --env "USER=$(id -un)" \
    "${VLLM_TRACE_OPTS[@]}" "$1" "${VLLM_ARGS[@]}"
}

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
