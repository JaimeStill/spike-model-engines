#!/usr/bin/env bash
# What every engine shares: the model store, the one-engine-per-host refusals, and the preflight
# checks. Sourced by llama.sh and vllm.sh, and through them by llama-native.sh and vllm-native.sh.
#
# See docs/engines/llama.cpp/scripts.md#what-every-engine-shares

ENGINES_STORE=/srv/models

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

engines_unit_up() {
  local state
  state=$(systemctl is-active "$1" 2>/dev/null) || true
  [[ $state == active || $state == activating || $state == reloading ]]
}

engines_refuse_unit() {
  if engines_unit_up "$1"; then
    echo "$1 is active, and one engine serves per host at a time, since each reserves most of" \
      "the host's GPU memory; sudo systemctl stop $1 && sudo systemctl disable $1 stops it" >&2
    return 1
  fi
}

engines_stopped() {
  docker container ls --all --quiet --filter "name=^$1\$" \
    --filter status=exited --filter status=created
}

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
