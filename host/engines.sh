#!/usr/bin/env bash
# What every engine shares, in one place: sourced by llama.sh and vllm.sh, and through them by
# llama-native.sh and vllm-native.sh. The model store (/srv/models) is one Hugging Face cache that
# every engine reads and writes, and one engine serves per host at a time, since each reserves
# most of the host's GPU memory, whatever the host.

ENGINES_STORE=/srv/models

# Refuses, naming the command that stops it, while the container named runs (or restarts, as a
# failing one does under --restart unless-stopped). Fails when Docker does, so an unreachable
# daemon is never read as "not running".
engines_refuse_running() {
  local id
  id=$(docker container ls --quiet --filter "name=^$1\$" \
    --filter status=running --filter status=restarting) || return
  if [[ -n $id ]]; then
    echo "$1 is running, and one engine serves per host at a time, since each reserves most of" \
      "the host's GPU memory; docker stop $1 stops it" >&2
    return 1
  fi
}

# Whether the system unit named is up: active, or activating, as a failing one is between restarts,
# or reloading. A host without the unit, or without systemd, reads as not up.
engines_unit_up() {
  local state
  state=$(systemctl is-active "$1" 2>/dev/null) || true
  [[ $state == active || $state == activating || $state == reloading ]]
}

# Refuses, naming the commands that stop it, while the system unit named is up (engines_unit_up):
# native llama.cpp's llama-router (llama-native.sh) and native vLLM's vllm-server
# (vllm-native.sh) each serve on the same port and memory as their engine's container would. The
# unit is read by name alone, so another project's unit of the same name, such as
# spike-model-hosting's llama-router on the Framework, refuses too. The commands it names use
# plain sudo, not sudo -n, since such a unit has no NOPASSWD rule and sudo asks for the password.
engines_refuse_unit() {
  if engines_unit_up "$1"; then
    echo "$1 is active, and one engine serves per host at a time, since each reserves most of" \
      "the host's GPU memory; sudo systemctl stop $1 && sudo systemctl disable $1 stops it" >&2
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

# Checks a native engine's root steps, the architect's, before anything is fetched or started:
# the directory given exists and the invoking user can write it, systemd has the unit given loaded
# (installed, then daemon-reload), and sudo -n allows each systemctl verb the commands run on it,
# without a password. sudo -l answers yes for an account that may run anything with its password,
# so the check reads the NOPASSWD rule's line itself. Each refusal names the guide section given,
# which holds the root steps.
engines_root_steps() {
  local dir=$1 unit=$2 steps=$3 listing verb
  if [[ ! -d $dir || ! -w $dir ]]; then
    echo "$dir is missing or not writable by $(id -un); the architect's root steps create it" \
      "($steps)" >&2
    return 1
  fi
  if [[ $(systemctl show --property LoadState --value "$unit") != loaded ]]; then
    echo "systemd has no $unit unit; the architect's root steps install it ($steps)" >&2
    return 1
  fi
  listing=$(sudo -n -l 2>/dev/null) || listing=
  for verb in start stop restart enable disable; do
    if ! grep -F 'NOPASSWD:' <<<"$listing" | grep -Fq "/usr/bin/systemctl $verb $unit"; then
      echo "sudo -n can't run systemctl $verb $unit; the architect's root steps allow it" \
        "($steps)" >&2
      return 1
    fi
  done
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
