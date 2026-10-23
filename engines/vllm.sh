#!/usr/bin/env bash
# The vLLM container, in one place: sourced by the engines-vllm-* commands so install and update
# start the same container. It runs `vllm serve` (the image's entrypoint) on the one model pinned
# beside the release, with the model store (/srv/models) as its Hugging Face cache, so the model
# lands in the same models--<org>--<name> layout llama.cpp's do. It runs as the invoking user, so
# the store's files stay that user's, and publishes port 8000 on the host's tailnet IPv4 address
# only.
#
# Run as a user the image's /etc/passwd doesn't name, the container has no writable home, so the
# compile cache directory (~/.cache/vllm on the host) is mounted as its home: vLLM's
# torch.compile cache, and the Triton and FlashInfer kernels it builds, land there and survive an
# update. USER is set too, since Python's getpass.getuser() otherwise fails on a uid with no
# passwd entry. This is what the image's own non-root variant does in its entrypoint.
#
# The server flags: 4 sequences of 8192 tokens, mirroring llama.cpp's 4 slots of 8192; 0.80 of
# the GB10's memory, which leaves the rest to the host it shares it with; the KV cache the
# checkpoint ships, FP8 per its quantization config, which `auto` follows, so the model is served
# as its publisher evaluated it; and Gemma 4's own reasoning and tool-call parsers. The vision encoder loads (no
# --language-model-only), and the model's shipped generation config sets its sampling.

# shellcheck source=engines/engines.sh
source "$(dirname "${BASH_SOURCE[0]}")/engines.sh"
# shellcheck source=engines/vllm.env
source "$(dirname "${BASH_SOURCE[0]}")/vllm.env"

VLLM_CONTAINER=vllm
VLLM_STORE=$ENGINES_STORE
VLLM_CACHE_DIR=$HOME/.cache/vllm
VLLM_HOME=/home/vllm

# The image for a release: the pinned image with its release swapped.
vllm_image() {
  echo "${VLLM_IMAGE%"$VLLM_RELEASE"}$1"
}

# The image and the model the container runs, as "<image> <model>", or nothing when there is no
# container. Fails when Docker does, so an unreachable daemon is never read as "not installed".
vllm_running() {
  local id
  id=$(docker container ls --all --quiet --filter "name=^$VLLM_CONTAINER\$") || return
  [[ -z $id ]] ||
    docker container inspect --format '{{.Config.Image}} {{index .Config.Cmd 0}}' "$id"
}

# Checks what vllm_run needs before anything is pulled or removed (engines_preflight), and sets
# VLLM_ADDR to the tailnet address it publishes port 8000 on.
vllm_preflight() {
  engines_preflight 8000 && VLLM_ADDR=$ENGINES_ADDR
}

# Starts the container from the image given, serving the pinned model, after vllm_preflight. It
# creates the compile cache directory first, so Docker doesn't create it as root.
vllm_run() {
  mkdir -p "$VLLM_CACHE_DIR"
  docker run --detach --name "$VLLM_CONTAINER" --restart unless-stopped --gpus all --ipc host \
    --user "$(id -u):$(id -g)" \
    --publish "$VLLM_ADDR:8000:8000" \
    --volume "$VLLM_STORE:$VLLM_STORE" --env "HF_HUB_CACHE=$VLLM_STORE" \
    --volume "$VLLM_CACHE_DIR:$VLLM_HOME" --env "HOME=$VLLM_HOME" --env "USER=$(id -un)" \
    "$1" "$VLLM_MODEL" --host 0.0.0.0 --port 8000 \
    --max-num-seqs 4 --max-model-len 8192 --gpu-memory-utilization 0.80 \
    --kv-cache-dtype auto \
    --reasoning-parser gemma4 --enable-auto-tool-choice --tool-call-parser gemma4
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
