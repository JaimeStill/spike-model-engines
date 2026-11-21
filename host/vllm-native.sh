#!/usr/bin/env bash
# Native vLLM: sourced by the engines-vllm-native-* commands, so install and update build, point
# at, and serve a release the same way. A release is its own uv virtualenv, /opt/vllm/<release>,
# on uv-managed CPython at the pin's Python (VLLM_NATIVE_PYTHON in vllm.env), holding vLLM at the
# release and torch from PyTorch's cu130 index, with FlashInfer's precompiled kernels downloaded
# into it. /opt/vllm/current names the release that serves, and /opt/vllm/row the row it serves
# (vllm-rows), one word a line, as vllm_row_words prints it. uv is the host env's pinned uv
# (mise.host.toml), run through mise from the clone.
#
# The unit, vllm-server (vllm-server.service), runs `vllm serve` through current as the container
# does (vllm.sh), on port 8000 of the host's tailnet IPv4 address. /opt/vllm, the unit, and its
# sudoers rule (vllm-server.sudoers) are the architect's root steps, which the commands check and
# never make.
#
# See docs/engines/vllm/setup.md#gb10-native
# See docs/engines/vllm/scripts.md#native

# shellcheck source=host/vllm.sh
source "$(dirname "${BASH_SOURCE[0]}")/vllm.sh"

VLLM_MODEL=${VLLM_MODEL:-$VLLM_MODEL_CUDA}

VLLM_NATIVE_DIR=/opt/vllm
VLLM_NATIVE_ROW=$VLLM_NATIVE_DIR/row
VLLM_NATIVE_PYTHON_DIR=$VLLM_NATIVE_DIR/python
VLLM_NATIVE_CACHE=$VLLM_NATIVE_DIR/cache
VLLM_UNIT=vllm-server
VLLM_ROOT_STEPS='docs/engines/vllm/setup.md, "GB10, native"'
VLLM_CLONE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VLLM_NATIVE_WAIT=600
VLLM_NATIVE_BUILT=.engines-built

VLLM_NATIVE_ENV=(
  "UV_PYTHON_INSTALL_DIR=$VLLM_NATIVE_PYTHON_DIR"
  "UV_CACHE_DIR=$VLLM_NATIVE_CACHE/uv"
  "XDG_CACHE_HOME=$VLLM_NATIVE_CACHE"
  "VLLM_CACHE_ROOT=$VLLM_NATIVE_CACHE/vllm"
  "TRITON_HOME=$VLLM_NATIVE_CACHE"
  "FLASHINFER_WORKSPACE_BASE=$VLLM_NATIVE_CACHE"
  "HF_HUB_CACHE=$VLLM_STORE"
)

vllm_native_release() {
  local release=${1:-$VLLM_RELEASE}
  if [[ ! $release =~ ^v[0-9]+\.[0-9]+\.[0-9]+(rc[0-9]+|\.post[0-9]+)?$ ]]; then
    echo "$release is not a vLLM release, such as $VLLM_RELEASE" >&2
    return 1
  fi
  echo "$release"
}

vllm_native_exec() (
  cd "$VLLM_CLONE" &&
    MISE_ENV=host MISE_EXEC_AUTO_INSTALL=false mise exec -- env "${VLLM_NATIVE_ENV[@]}" "$@"
)

vllm_native_current() {
  local target
  target=$(readlink -- "$VLLM_NATIVE_DIR/current") || return 0
  echo "${target##*/}"
}

vllm_native_row() {
  [[ ! -f $VLLM_NATIVE_ROW ]] || cat -- "$VLLM_NATIVE_ROW"
}

vllm_native_active() {
  [[ $(systemctl is-active "$VLLM_UNIT") == active ]]
}
vllm_native_enabled() {
  [[ $(systemctl is-enabled "$VLLM_UNIT" 2>/dev/null) == enabled ]]
}
vllm_native_serving() {
  vllm_native_active && vllm_native_enabled
}

vllm_native_preflight() {
  engines_root_steps "$VLLM_NATIVE_DIR" "$VLLM_UNIT" "$VLLM_ROOT_STEPS" || return
  if ! (cd "$VLLM_CLONE" && MISE_ENV=host mise which uv >/dev/null 2>&1); then
    echo "the host env's uv isn't installed; MISE_ENV=host mise install, from the clone," \
      "installs it (docs/engines/vllm/setup.md, \"uv\")" >&2
    return 1
  fi
  engines_preflight 8000 && VLLM_ADDR=$ENGINES_ADDR
}

vllm_native_kernels() {
  if compgen -G "$1/lib/python*/site-packages/vllm/entrypoints/cli/download_kernels.py" >/dev/null
  then
    vllm_native_exec "$1/bin/vllm" download-kernels
  else
    vllm_native_exec FLASHINFER_DISABLE_VERSION_CHECK=1 "$1/bin/python" -m flashinfer \
      download-kernels
  fi
}

vllm_native_build() {
  local dir=$VLLM_NATIVE_DIR/$1
  [[ ! -f $dir/$VLLM_NATIVE_BUILT ]] || return 0
  if [[ -e $dir ]]; then
    rm -rf -- "$dir" || return
    echo "removed $dir, a build that didn't finish"
  fi
  vllm_native_exec uv venv --python "$VLLM_NATIVE_PYTHON" --managed-python --seed "$dir" &&
    vllm_native_exec uv pip install --python "$dir" "vllm==${1#v}" --torch-backend=cu130 &&
    vllm_native_kernels "$dir" &&
    touch -- "$dir/$VLLM_NATIVE_BUILT" &&
    echo "built $dir"
}

vllm_native_link() {
  ln -sfn -- "$1" "$VLLM_NATIVE_DIR/current"
}

vllm_native_write_row() {
  vllm_row_words "$VLLM_MODEL" >"$VLLM_NATIVE_ROW.new" &&
    mv -- "$VLLM_NATIVE_ROW.new" "$VLLM_NATIVE_ROW"
}

vllm_native_stop() {
  if engines_unit_up "$VLLM_UNIT"; then
    sudo -n systemctl stop "$VLLM_UNIT"
  fi
}

vllm_native_serve() {
  local i
  if ! vllm_native_enabled; then
    sudo -n systemctl enable "$VLLM_UNIT" || return
  fi
  if [[ ${1:-} == restart ]]; then
    sudo -n systemctl restart "$VLLM_UNIT" || return
  elif ! vllm_native_active; then
    sudo -n systemctl start "$VLLM_UNIT" || return
  fi
  for ((i = 0; i < VLLM_NATIVE_WAIT; i += 5)); do
    curl -fs --max-time 5 --output /dev/null "http://$VLLM_ADDR:8000/health" && return
    sleep 5
  done
  echo "$VLLM_UNIT doesn't answer /health on port 8000 after $((VLLM_NATIVE_WAIT / 60))" \
    "minutes; journalctl -u $VLLM_UNIT shows why" >&2
  return 1
}

vllm_native_versions() {
  local version torch
  version=$(curl -fs --max-time 5 "http://$VLLM_ADDR:8000/version") || return
  torch=$(env "${VLLM_NATIVE_ENV[@]}" "$VLLM_NATIVE_DIR/current/bin/python" -c \
    'import torch; print(f"torch {torch.__version__}, CUDA {torch.version.cuda}")') || return
  echo "/version answers $version; $torch"
}

vllm_native_remove_releases() {
  local path
  rm -f -- "$VLLM_NATIVE_ROW.new" || return
  for path in "$VLLM_NATIVE_DIR"/v[0-9]*; do
    [[ -d $path && ${path##*/} != "${1:-}" ]] || continue
    rm -rf -- "$path" || return
    echo "removed $path"
  done
}
