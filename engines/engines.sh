#!/usr/bin/env bash
# What every engine's container shares, in one place: sourced by llama.sh and vllm.sh. The model
# store (/srv/models) is one Hugging Face cache that every engine reads and writes, and one
# engine serves per host at a time, since each reserves most of the GB10's memory.

ENGINES_STORE=/srv/models

# Refuses, naming the command that stops it, while the container named runs (or restarts, as a
# failing one does under --restart unless-stopped). Fails when Docker does, so an unreachable
# daemon is never read as "not running".
engines_refuse_running() {
  local id
  id=$(docker container ls --quiet --filter "name=^$1\$" \
    --filter status=running --filter status=restarting) || return
  if [[ -n $id ]]; then
    echo "$1 is running, and one engine serves per host at a time; docker stop $1 stops it" >&2
    return 1
  fi
}

# Prints the ID of the container named when it exists but is stopped (exited, or created and never
# started), and nothing otherwise, so install and update can say "stopped" rather than "already
# runs" after a docker stop. Fails when Docker does, so an unreachable daemon is never read as
# "not stopped".
engines_stopped() {
  docker container ls --all --quiet --filter "name=^$1\$" \
    --filter status=exited --filter status=created
}

# Checks what an engine's container needs before anything is pulled or removed: the model store,
# and the host's tailnet IPv4 address, which it sets in ENGINES_ADDR. Without the address, docker
# would publish the port given on every interface.
engines_preflight() {
  if [[ ! -d $ENGINES_STORE ]]; then
    echo "$ENGINES_STORE does not exist; create it first (docs/engines/llama.cpp/setup.md)" >&2
    return 1
  fi
  if ! ENGINES_ADDR=$(tailscale ip -4) || [[ -z $ENGINES_ADDR ]]; then
    echo "the host has no tailnet IPv4 address to publish port $1 on; is Tailscale up?" >&2
    return 1
  fi
}
