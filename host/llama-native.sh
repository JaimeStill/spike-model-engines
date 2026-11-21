#!/usr/bin/env bash
# Native llama.cpp: sourced by the engines-llama-native-* commands, so install and update fetch,
# point at, and serve a build the same way. A build is ggml's CUDA 13.4 arm64 Linux prebuilt with
# its CUDA runtime tarball unpacked beside it, in /opt/llama.cpp/<b-build>, each tarball checked
# against the sha256 digest GitHub lists for it. /opt/llama.cpp/current names the build that
# serves, and /opt/llama.cpp/preset the clone's preset directory (llama-preset).
#
# The unit, llama-router (llama-router.service), runs llama-server through current as the
# container does (llama.sh), on port 8080 of the host's tailnet IPv4 address. /opt/llama.cpp, the
# unit, and its sudoers rule (llama-router.sudoers) are the architect's root steps, which the
# commands check and never make.
#
# See docs/engines/llama.cpp/setup.md#gb10-native
# See docs/engines/llama.cpp/scripts.md#native

# shellcheck source=host/llama.sh
source "$(dirname "${BASH_SOURCE[0]}")/llama.sh"

LLAMA_NATIVE_DIR=/opt/llama.cpp
LLAMA_UNIT=llama-router
LLAMA_PLATFORM=bin-ubuntu-cuda-13.4-arm64
LLAMA_CLASS=gb10
LLAMA_ROOT_STEPS='docs/engines/llama.cpp/setup.md, "GB10, native"'

llama_native_current() {
  local target
  target=$(readlink -- "$LLAMA_NATIVE_DIR/current") || return 0
  echo "${target##*/}"
}

llama_native_preset() {
  readlink -- "$LLAMA_NATIVE_DIR/preset" || true
}

llama_native_active() {
  [[ $(systemctl is-active "$LLAMA_UNIT") == active ]]
}
llama_native_enabled() {
  [[ $(systemctl is-enabled "$LLAMA_UNIT" 2>/dev/null) == enabled ]]
}
llama_native_serving() {
  llama_native_active && llama_native_enabled
}

llama_native_preflight() {
  engines_root_steps "$LLAMA_NATIVE_DIR" "$LLAMA_UNIT" "$LLAMA_ROOT_STEPS" &&
    engines_preflight 8080 && LLAMA_ADDR=$ENGINES_ADDR
}

llama_native_response_held() (
  message_re='"message": *"([^"]*)"'
  url_key='"browser_download_url"'
  if [[ $1 =~ $message_re ]]; then
    echo "GitHub answered \"${BASH_REMATCH[1]}\""
  else
    LC_ALL=C
    rest=${1//"$url_key"/}
    echo "GitHub's response had ${#1} bytes and listed" \
      "$(((${#1} - ${#rest}) / ${#url_key})) assets"
  fi
)

llama_native_fetch() (
  build=$1
  [[ ! -d $LLAMA_NATIVE_DIR/$build ]] || exit 0
  url=https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$build
  digest_re='"digest": *"sha256:([0-9a-f]{64})"'
  if ! json=$(curl -fsSL "$url"); then
    echo "llama.cpp's release $build can't be read from GitHub" >&2
    exit 1
  fi
  stage=$(mktemp -d "$LLAMA_NATIVE_DIR/.fetch-$build-XXXXXX") || return
  trap 'rm -rf -- "$stage"' EXIT
  mkdir -- "$stage/$build"
  for asset in "llama-$build-$LLAMA_PLATFORM.tar.gz" "cudart-llama-$build-$LLAMA_PLATFORM.tar.gz"
  do
    entry=${json#*"\"name\": \"$asset\""}
    if [[ $entry == "$json" ]]; then
      held=$(llama_native_response_held "$json") || return
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

llama_native_link() {
  ln -sfn -- "$2" "$LLAMA_NATIVE_DIR/$1"
}

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

llama_native_remove_builds() {
  local path
  for path in "$LLAMA_NATIVE_DIR"/b[0-9]* "$LLAMA_NATIVE_DIR"/.fetch-*; do
    [[ -d $path && ${path##*/} != "${1:-}" ]] || continue
    rm -rf -- "$path" || return
    echo "removed $path"
  done
}
