#!/usr/bin/env bash
# Native vLLM, in one place: sourced by the engines-vllm-native-* commands, so install and update
# build, point at, and serve a release the same way. A release is its own uv virtualenv,
# /opt/vllm/<release>, on uv-managed CPython at the pin's Python (VLLM_NATIVE_PYTHON in vllm.env,
# the image's), holding vLLM at the release and torch from PyTorch's cu130 index, with
# FlashInfer's precompiled kernels downloaded into it. /opt/vllm/current names the release that
# serves, and /opt/vllm/row the row it serves (vllm-rows): the model, then its server flags, one
# word a line, as vllm_row_words prints them. The unit reads the row file as it starts, so
# switching rows or changing a flag needs no root, and the unit names neither a release nor a row.
#
# uv is the host env's pinned uv (mise.host.toml), run through mise from the clone, as hf is; mise
# never installs it here (MISE_EXEC_AUTO_INSTALL=false), since `MISE_ENV=host mise install` is the
# one step that does. uv's Python and its cache, and vLLM's, Triton's, and FlashInfer's compile
# caches, all live under /opt/vllm, never in the home directory, where the container's compile
# cache is (~/.cache/vllm, vllm.sh): removing either hosting method leaves the other's alone.
#
# The unit, vllm-server (vllm-server.service), runs `vllm serve` through current as the container
# does (vllm.sh): the row's model, then --host and --port, then its flags, with /srv/models as
# HF_HUB_CACHE, as the invoking user, on port 8000 of the host's tailnet IPv4 address.
# /opt/vllm, the unit, and the sudoers rule that lets these commands start, stop, restart,
# enable, and disable it (vllm-server.sudoers) are the architect's root steps
# (docs/engines/vllm/setup.md, "GB10, native"), which the commands check and never make.

# shellcheck source=host/vllm.sh
source "$(dirname "${BASH_SOURCE[0]}")/vllm.sh"

# Native vLLM is CUDA's alone, its torch from PyTorch's cu130 index, so it resolves no flavor
# (vllm_flavor) and serves the cuda flavor's default row unless VLLM_MODEL names another.
VLLM_MODEL=${VLLM_MODEL:-$VLLM_MODEL_CUDA}

VLLM_NATIVE_DIR=/opt/vllm
VLLM_NATIVE_ROW=$VLLM_NATIVE_DIR/row
VLLM_NATIVE_PYTHON_DIR=$VLLM_NATIVE_DIR/python
VLLM_NATIVE_CACHE=$VLLM_NATIVE_DIR/cache
VLLM_UNIT=vllm-server
VLLM_ROOT_STEPS='docs/engines/vllm/setup.md, "GB10, native"'
VLLM_CLONE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# A start loads the model, compiles it (from scratch on a release's first start), and captures
# its CUDA graphs before /health answers: minutes, so the commands wait up to 10.
VLLM_NATIVE_WAIT=600
# The marker a release's directory gains only once it is whole: its virtualenv built, vLLM and
# torch installed, and FlashInfer's kernels downloaded. A virtualenv names its own path inside it,
# so it is built in place rather than staged and moved, and a directory without the marker is a
# failed or interrupted build, which the next build removes first.
VLLM_NATIVE_BUILT=.engines-built

# Where uv and the engine keep what they write, for the commands that run in a release's
# environment. The unit (vllm-server.service) sets the same compile-cache variables, so a cache
# the commands fill is the one the server reads:
# - UV_PYTHON_INSTALL_DIR and UV_CACHE_DIR, uv's Python installs and its package cache;
# - XDG_CACHE_HOME, the cache root of every library that follows XDG, as torch's does, so none
#   writes to ~/.cache, and VLLM_CACHE_ROOT, vLLM's own, named outright though it follows XDG;
# - TRITON_HOME, under which Triton keeps its cache (.triton/cache); TRITON_CACHE_DIR is left
#   unset, since vLLM then gives each torch.compile cache its own Triton cache, as in the
#   container, where setting it would put every compile's kernels in one;
# - FLASHINFER_WORKSPACE_BASE, under which FlashInfer 0.7 keeps its JIT and cubin cache
#   (.cache/flashinfer); it reads no variable that names that cache itself.
VLLM_NATIVE_ENV=(
  "UV_PYTHON_INSTALL_DIR=$VLLM_NATIVE_PYTHON_DIR"
  "UV_CACHE_DIR=$VLLM_NATIVE_CACHE/uv"
  "XDG_CACHE_HOME=$VLLM_NATIVE_CACHE"
  "VLLM_CACHE_ROOT=$VLLM_NATIVE_CACHE/vllm"
  "TRITON_HOME=$VLLM_NATIVE_CACHE"
  "FLASHINFER_WORKSPACE_BASE=$VLLM_NATIVE_CACHE"
  "HF_HUB_CACHE=$VLLM_STORE"
)

# The release given, or the pin's when given nothing, after checking it is a vLLM release tag,
# such as v0.31.0, before anything reads the host. A tag with no release fails at the install.
vllm_native_release() {
  local release=${1:-$VLLM_RELEASE}
  if [[ ! $release =~ ^v[0-9]+\.[0-9]+\.[0-9]+(rc[0-9]+|\.post[0-9]+)?$ ]]; then
    echo "$release is not a vLLM release, such as $VLLM_RELEASE" >&2
    return 1
  fi
  echo "$release"
}

# Runs the command given in the host env, from the clone, with uv on its PATH and VLLM_NATIVE_ENV
# set; mise's own cache stays where it is, since the variables apply only inside.
vllm_native_exec() (
  cd "$VLLM_CLONE" &&
    MISE_ENV=host MISE_EXEC_AUTO_INSTALL=false mise exec -- env "${VLLM_NATIVE_ENV[@]}" "$@"
)

# The release current names, or nothing when there is no link.
vllm_native_current() {
  local target
  target=$(readlink -- "$VLLM_NATIVE_DIR/current") || return 0
  echo "${target##*/}"
}

# The row file's words, one a line, as vllm_row_words prints a row's, or nothing when there is
# none; command substitution drops the trailing newline of either, so the two compare equal.
vllm_native_row() {
  [[ ! -f $VLLM_NATIVE_ROW ]] || cat -- "$VLLM_NATIVE_ROW"
}

# Whether vllm-server is active, enabled, or either, as systemctl reports them; a host without the
# unit reads as neither.
vllm_native_active() {
  [[ $(systemctl is-active "$VLLM_UNIT") == active ]]
}
vllm_native_enabled() {
  [[ $(systemctl is-enabled "$VLLM_UNIT" 2>/dev/null) == enabled ]]
}
vllm_native_serving() {
  vllm_native_active && vllm_native_enabled
}

# Checks the architect's root steps before anything is built or started (engines_root_steps):
# /opt/vllm, the unit, and its sudoers rule. Then checks that the host env's uv is installed, and
# what serving needs (engines_preflight), and sets VLLM_ADDR to the tailnet address the unit
# binds. uv is checked with `mise which`, which fails when the pinned uv isn't installed, since
# `mise exec` would then run any uv on the PATH instead, or install the pin through mise's shims.
vllm_native_preflight() {
  engines_root_steps "$VLLM_NATIVE_DIR" "$VLLM_UNIT" "$VLLM_ROOT_STEPS" || return
  if ! (cd "$VLLM_CLONE" && MISE_ENV=host mise which uv >/dev/null 2>&1); then
    echo "the host env's uv isn't installed; MISE_ENV=host mise install, from the clone," \
      "installs it (docs/engines/vllm/setup.md, \"uv\")" >&2
    return 1
  fi
  engines_preflight 8000 && VLLM_ADDR=$ENGINES_ADDR
}

# Downloads FlashInfer's precompiled kernels into the release's environment given:
# `vllm download-kernels`, which installs the flashinfer-cubin and flashinfer-jit-cache wheels
# matching its FlashInfer, so a start neither downloads nor compiles them. A release older than
# that command (v0.31.0 has none) runs what it runs, FlashInfer's own `download-kernels` with
# FlashInfer's version check off. FlashInfer installs the wheels with uv when uv made the
# environment and is on the PATH, as it is here, into uv's cache under /opt/vllm.
vllm_native_kernels() {
  if compgen -G "$1/lib/python*/site-packages/vllm/entrypoints/cli/download_kernels.py" >/dev/null
  then
    vllm_native_exec "$1/bin/vllm" download-kernels
  else
    vllm_native_exec FLASHINFER_DISABLE_VERSION_CHECK=1 "$1/bin/python" -m flashinfer \
      download-kernels
  fi
}

# Builds the release given into /opt/vllm/<release>, unless it is there whole: removes what a
# failed build left, then makes the virtualenv on uv-managed CPython (uv downloads it into
# /opt/vllm/python the first time), with pip seeded, as FlashInfer's kernel install wants;
# installs vLLM at the release, with torch and its companions from PyTorch's cu130 index; and
# downloads FlashInfer's kernels (vllm_native_kernels). It marks the directory whole last.
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

# Points current at the release given.
vllm_native_link() {
  ln -sfn -- "$1" "$VLLM_NATIVE_DIR/current"
}

# Writes the row VLLM_MODEL names into the row file, after vllm_row: written beside it and moved
# into place, so the unit never reads half a file.
vllm_native_write_row() {
  vllm_row_words "$VLLM_MODEL" >"$VLLM_NATIVE_ROW.new" &&
    mv -- "$VLLM_NATIVE_ROW.new" "$VLLM_NATIVE_ROW"
}

# Stops vllm-server when it is up (engines_unit_up), so its memory is free before another start:
# two servers can't both reserve 0.80 of the GB10's memory.
vllm_native_stop() {
  if engines_unit_up "$VLLM_UNIT"; then
    sudo -n systemctl stop "$VLLM_UNIT"
  fi
}

# Brings vllm-server up on the release current names and the row file, after
# vllm_native_preflight: enables it, so it starts at boot, when it isn't enabled; restarts it when
# given restart, or else starts it when it isn't active; then waits until it answers /health on
# port 8000 of VLLM_ADDR, for at most 10 minutes. Each systemctl call is one the sudoers rule
# names exactly.
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

# Prints what the serving release reports, after vllm_native_serve: the server's /version, and
# the CUDA version torch was built for in current's environment, 13.0 from the cu130 index, with
# VLLM_NATIVE_ENV set, as for every command run in a release's environment.
vllm_native_versions() {
  local version torch
  version=$(curl -fs --max-time 5 "http://$VLLM_ADDR:8000/version") || return
  torch=$(env "${VLLM_NATIVE_ENV[@]}" "$VLLM_NATIVE_DIR/current/bin/python" -c \
    'import torch; print(f"torch {torch.__version__}, CUDA {torch.version.cuda}")') || return
  echo "/version answers $version; $torch"
}

# Removes every release under /opt/vllm but the one given (none when given nothing), and any
# row file a killed write left, printing each release. Stops at the first failure, so it never
# reports a release it did not remove.
vllm_native_remove_releases() {
  local path
  rm -f -- "$VLLM_NATIVE_ROW.new" || return
  for path in "$VLLM_NATIVE_DIR"/v[0-9]*; do
    [[ -d $path && ${path##*/} != "${1:-}" ]] || continue
    rm -rf -- "$path" || return
    echo "removed $path"
  done
}
