#!/usr/bin/env bash
# Native llama.cpp, in one place: sourced by the engines-llama-native-* commands, so install and
# update fetch, point at, and serve a build the same way. A build is ggml's CUDA 13.4 arm64 Linux
# prebuilt with its CUDA runtime tarball unpacked beside it, in /opt/llama.cpp/<b-build>, where
# the binaries' $ORIGIN runpath finds the runtime's libraries; each tarball is checked against
# the sha256 digest GitHub lists for it. /opt/llama.cpp/current names the build that serves, and
# /opt/llama.cpp/preset the clone's preset directory (llama-preset), so the unit names neither a
# build nor the clone's path.
#
# The unit, llama-router (llama-router.service), runs llama-server through current as the
# container does (llama.sh): router mode, the same preset and flags, /srv/models as LLAMA_CACHE,
# as the invoking user, on port 8080 of the host's tailnet IPv4 address. /opt/llama.cpp, the unit,
# and the sudoers rule that lets these commands start, stop, restart, enable, and disable it
# (llama-router.sudoers) are the architect's root steps (docs/engines/llama.cpp/setup.md, "GB10,
# native"), which the commands check and never make.

# shellcheck source=host/llama.sh
source "$(dirname "${BASH_SOURCE[0]}")/llama.sh"

LLAMA_NATIVE_DIR=/opt/llama.cpp
LLAMA_UNIT=llama-router
LLAMA_PLATFORM=bin-ubuntu-cuda-13.4-arm64
LLAMA_ROOT_STEPS='docs/engines/llama.cpp/setup.md, "GB10, native"'

# The build current names, or nothing when there is no link.
llama_native_current() {
  local target
  target=$(readlink -- "$LLAMA_NATIVE_DIR/current") || return 0
  echo "${target##*/}"
}

# The directory /opt/llama.cpp/preset names, or nothing when there is no link.
llama_native_preset() {
  readlink -- "$LLAMA_NATIVE_DIR/preset" || true
}

# Whether llama-router is active, enabled, or either, as systemctl reports them; a host without the
# unit reads as neither.
llama_native_active() {
  [[ $(systemctl is-active "$LLAMA_UNIT") == active ]]
}
llama_native_enabled() {
  [[ $(systemctl is-enabled "$LLAMA_UNIT" 2>/dev/null) == enabled ]]
}
llama_native_serving() {
  llama_native_active && llama_native_enabled
}

# Checks the architect's root steps before anything is fetched or started (engines_root_steps):
# /opt/llama.cpp, the unit, and its sudoers rule. Then checks what serving needs
# (engines_preflight), and sets LLAMA_ADDR to the tailnet address the unit binds.
llama_native_preflight() {
  engines_root_steps "$LLAMA_NATIVE_DIR" "$LLAMA_UNIT" "$LLAMA_ROOT_STEPS" &&
    engines_preflight 8080 && LLAMA_ADDR=$ENGINES_ADDR
}

# Fetches the build given into /opt/llama.cpp/<build>, unless it is there: reads the release's
# assets from GitHub, downloads the prebuilt and the CUDA runtime tarballs, checks each against
# its sha256 digest, and unpacks both into one directory. It works in a hidden staging directory
# and moves the build into place only once both are unpacked, so a failed or interrupted fetch
# never leaves a build that looks whole; the staging directory goes either way. It reads the
# assets with curl and bash alone, as llama-release.sh reads the notes. A subshell, so its trap
# and variables stay its own.
llama_native_fetch() (
  build=$1
  [[ ! -d $LLAMA_NATIVE_DIR/$build ]] || exit 0
  url=https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$build
  digest_re='"digest": *"sha256:([0-9a-f]{64})"'
  message_re='"message": *"([^"]*)"'
  if ! json=$(curl -fsSL "$url"); then
    echo "llama.cpp's release $build can't be read from GitHub" >&2
    exit 1
  fi
  stage=$(mktemp -d "$LLAMA_NATIVE_DIR/.fetch-$build-XXXXXX")
  trap 'rm -rf -- "$stage"' EXIT
  mkdir -- "$stage/$build"
  for asset in "llama-$build-$LLAMA_PLATFORM.tar.gz" "cudart-llama-$build-$LLAMA_PLATFORM.tar.gz"
  do
    # The asset's own fields, from its name to its download URL, which GitHub lists last.
    entry=${json#*"\"name\": \"$asset\""}
    if [[ $entry == "$json" ]]; then
      # GitHub has answered once without the asset, and the retry found it, cause unknown
      # (docs/findings/llama-gb10-native.md, "Walkthrough"), so the error says what the response
      # held: GitHub's message when it gave one, or else its size in bytes (LC_ALL=C makes ${#}
      # count bytes; the subshell exits next) and the assets it listed, one download URL each.
      if [[ $json =~ $message_re ]]; then
        held="GitHub answered \"${BASH_REMATCH[1]}\""
      else
        LC_ALL=C
        url_key='"browser_download_url"'
        rest=${json//"$url_key"/}
        held="GitHub's response had ${#json} bytes and listed"
        held+=" $(((${#json} - ${#rest}) / ${#url_key})) assets"
      fi
      echo "llama.cpp's release $build has no asset $asset; $held; a retry may succeed" >&2
      exit 1
    fi
    entry=${entry%%\"browser_download_url\"*}
    if [[ ! $entry =~ $digest_re ]]; then
      echo "GitHub lists no sha256 digest for $asset" >&2
      exit 1
    fi
    digest=${BASH_REMATCH[1]}
    curl -fsSL --output "$stage/$asset" \
      "https://github.com/ggml-org/llama.cpp/releases/download/$build/$asset"
    if ! echo "$digest  $stage/$asset" | sha256sum --check --status; then
      echo "$asset doesn't match its sha256 digest on GitHub, $digest" >&2
      exit 1
    fi
    tar -xzf "$stage/$asset" -C "$stage/$build" --strip-components=1
    rm -- "$stage/$asset"
    echo "fetched $asset, sha256 $digest"
  done
  mv -- "$stage/$build" "$LLAMA_NATIVE_DIR/$build"
)

# Points the link named under /opt/llama.cpp (current or preset) at the target given.
llama_native_link() {
  ln -sfn -- "$2" "$LLAMA_NATIVE_DIR/$1"
}

# Brings llama-router up on the build current names, after llama_native_preflight: enables it, so
# it starts at boot, when it isn't enabled; restarts it when given restart (as after current or
# preset moves), or else starts it when it isn't active; then waits until it answers /health on
# port 8080 of LLAMA_ADDR, for at most 60 seconds. Each systemctl call is one the sudoers rule
# names exactly.
llama_native_serve() {
  local i
  if ! llama_native_enabled; then
    sudo -n systemctl enable "$LLAMA_UNIT" || return
  fi
  if [[ ${1:-} == restart ]]; then
    sudo -n systemctl restart "$LLAMA_UNIT" || return
  elif ! llama_native_active; then
    sudo -n systemctl start "$LLAMA_UNIT" || return
  fi
  for ((i = 0; i < 60; i++)); do
    curl -fs --output /dev/null "http://$LLAMA_ADDR:8080/health" && return
    sleep 1
  done
  echo "$LLAMA_UNIT doesn't answer /health on port 8080 after 60 seconds;" \
    "journalctl -u $LLAMA_UNIT shows why" >&2
  return 1
}

# Removes every build under /opt/llama.cpp but the one given (none when given nothing), and any
# staging directory a killed fetch left, printing each. Stops at the first failure, so it never
# reports a build it did not remove.
llama_native_remove_builds() {
  local path
  for path in "$LLAMA_NATIVE_DIR"/b[0-9]* "$LLAMA_NATIVE_DIR"/.fetch-*; do
    [[ -d $path && ${path##*/} != "${1:-}" ]] || continue
    rm -rf -- "$path" || return
    echo "removed $path"
  done
}
