# How the scripts work

This page explains what the `engines` commands' libraries for vLLM leave unsaid in their code: why
each function reads, refuses, or waits as it does. Each library's header points at its section
here. What every engine shares, the model store and the one-engine-per-host refusals, is in
[llama.cpp's scripts](../llama.cpp/scripts.md#what-every-engine-shares).

## The container

`host/vllm.sh` starts a row's container the same way for install and update. A host runs one
container per row it serves, each with its own memory fraction, and every command acts on the
row's container alone; a row that names no container or port serves from `vllm` on 8000
(`VLLM_CONTAINER_DEFAULT`, `VLLM_PORT_DEFAULT`). The model store is the container's Hugging Face
cache, so the model lands in the same `models--<org>--<name>` layout llama.cpp's do, and the
container runs as the invoking user, so the store's files stay that user's.

Run as a user the image's `/etc/passwd` doesn't name, the container has no writable home, so the
compile cache directory, `~/.cache/vllm` on the host, is mounted as its home: vLLM's torch.compile
cache, and the Triton and FlashInfer kernels it builds, land there and survive an update. `USER` is
set too, since Python's `getpass.getuser()` otherwise fails on a uid with no passwd entry. This is
what the image's own non-root variant does in its entrypoint. Every container on the host shares
the one directory: vLLM keys its compile cache by the model and its configuration, so the rows
don't overwrite each other's. Tracing ([Tracing a row for one run](models.md#tracing-a-row-for-one-run))
is the same on both flavors and on a row's own image, which all run here.

- `vllm_flavor` resolves the flavor, the GPU platform vLLM's image is built for, into
  `VLLM_FLAVOR`; the image repository `vllm_image` names into `VLLM_REPOSITORY`; the `docker run`
  options that give the container the GPU into `VLLM_DEVICES`; and, when `VLLM_MODEL` names no row
  for the run, the flavor's default row into `VLLM_MODEL`. `VLLM_FLAVOR`, when set, names it:
  `cuda`, vLLM's CUDA image on the NVIDIA Container Toolkit's GPU (`--gpus all`); or `rocm`, vLLM's
  ROCm image on the kernel's AMD GPU driver, its compute device and its render nodes (`/dev/kfd`,
  `/dev/dri`), with no `--group-add`, seccomp, or ptrace options, since the device files are open
  to every account on the Framework. Unset or empty, it follows the GPU the host has, as
  llama.cpp's `llama_flavor` does: `rocm` when any DRM card under `/sys/class/drm` has AMD's PCI
  vendor ID, `0x1002`, as the Framework's Strix Halo does, and `cuda` otherwise, as on the GB10s.
  Reading the vendor ID needs no root and no Docker. It refuses any other flavor, before Docker is
  read. The rocm image is the release's default tag
  ([The release on each flavor](update.md#the-release-on-each-flavor)).
- `vllm_rows` prints the rows' ids, one a line, in the rows file's order.
- `vllm_row_all_words <id>` prints every word of the row, one a line, in the file's order: its
  model, its settings, and its server flags; nothing for an id the file has no row for.
- `VLLM_SETTING_RE` matches one of a row's settings, the words the suite reads and `vllm serve`
  never sees ([The rows file](models.md#the-rows-file)).
- `vllm_row_words <id>` prints the row's model, then its server flags, one a line, without its
  settings; nothing for an id the file has no row for.
- `vllm_row_setting <id> <key>` prints the value of the row's setting (`container`, `port`, or
  `image`), or nothing when the row names none.
- `vllm_containers` prints the containers every row names, one a line, each once, the default's
  among them: every vLLM container the suite may have started on a host.
- `vllm_refuse_running` refuses, as `engines_refuse_running` does, while any of those containers
  runs, so llama.cpp, in its container or native, never starts beside one.
- `vllm_row` reads the row `VLLM_MODEL` names, after `vllm_flavor` sets the flavor's default, into
  `VLLM_ARGS`, what the container serves after its image: the row's model, the address and port it
  listens on, and the row's flags. `vllm_run` starts the container with `VLLM_ARGS`, and
  `vllm_running`'s comparison reads them back from the container's command, so the two can't
  drift; the port is in the command, so a row whose port changes compares unequal. No element
  holds a space, so the command joined with spaces reads back unambiguously. It reads the row's
  settings too: its container into `VLLM_CONTAINER` and its port into `VLLM_PORT`, each the default
  when the row names none; and, when it names an image, that repository into `VLLM_REPOSITORY` in
  place of the flavor's, with `VLLM_LOCAL` set, since such an image is built on the host and never
  pulled. When the run is traced (`VLLM_TRACE=on`), the collector's endpoint ends `VLLM_ARGS` as
  `--otlp-traces-endpoint`, `grpc://` over the collector's host and port, so tracing on or off reads
  back from the command and update moves a row between the two; and `VLLM_ALIAS` holds the row's
  alias, its `--served-model-name`, or its id when it names none, which the service name is built
  from. It refuses an id with no row, listing the rows, and a `VLLM_TRACE` other than `on` or empty.
- `vllm_serves` prints the row as `row <id> (<model>)`, for messages, after `vllm_row`.
- `vllm_given` prints the settings the run was given in the environment, `VLLM_FLAVOR`,
  `VLLM_MODEL`, and `VLLM_TRACE`, as `NAME=value ` each. Install reads them before `vllm_flavor`
  resolves them, so its refusal can name the update that repeats the run.
- `vllm_served <image>` prints what a container serves the row as, `<image> <model> <flags...>`,
  in the form `vllm_running` prints, so a container serving exactly the row compares equal.
- `vllm_image <release>` names the image for a release, `<repository>:<release>`, in the
  repository `vllm_flavor` resolved, or the row's own (`vllm_row`).
- `vllm_pull <image>` fetches the image before the container is started: `docker pull` for an
  official image, and for a row's own image (`VLLM_LOCAL`), which no registry holds, only a check
  that the host has built it, refusing with the build it needs
  ([The audio image](setup.md#the-audio-image)).
- `vllm_running` prints what the container serves, in `vllm_served`'s form, or nothing when there
  is no container. It fails when Docker does, so an unreachable daemon is never read as "not
  installed". The whole command is read, not only the model, so a changed server flag shows.
- `vllm_describe <served>` prints the image and the model of what `vllm_served` or `vllm_running`
  printed, as `<image> with <model>`, for messages.
- `vllm_preflight` runs `engines_preflight` on the row's port, after `vllm_row`, and sets
  `VLLM_ADDR` to the tailnet address the container publishes on. It sets `VLLM_TRACE_OPTS` to the
  `docker run` options a traced run adds, and to none otherwise: the collector's host added to the
  container's hosts file at its tailnet IPv4 address, since the resolver Docker gives a container
  doesn't know the tailnet's short names, and the service name. The address is looked up here,
  before update removes the running container, so a collector's host the tailnet doesn't know
  refuses with the row still serving.
- `vllm_run <image>` starts the row's container from the image, with the flavor's devices, serving
  the row on its port, after `vllm_flavor`, `vllm_row`, and `vllm_preflight`, with a traced run's
  options. The server listens on the row's port inside the container too, so the port reads back
  from its command. It creates the compile cache directory first, so Docker doesn't create it as
  root.
- `vllm_remove_images [image]` removes every vLLM image in both flavors' official repositories but
  the one given and any a container on the host was created from, such as another row's, printing
  each. A row's own image, built on the host, is never removed. It needs no flavor, and stops at
  the first failure, so it never reports an image it did not remove.

## Native

`host/vllm-native.sh` builds, points at, and serves a release the same way for the `vllm-native`
commands ([GB10, native](setup.md#gb10-native) says what a release, `current`, and the row file
are, and where uv and the caches live). uv runs through mise from the clone with
`MISE_EXEC_AUTO_INSTALL=false`, since `MISE_ENV=host mise install` is the one step that installs it
([How it is set up](setup.md#how-it-is-set-up)).

Native vLLM is CUDA's alone, its torch from PyTorch's cu130 index, so it resolves no flavor and
serves the cuda flavor's default row unless `VLLM_MODEL` names another. A start loads the model,
compiles it, from scratch on a release's first start, and captures its CUDA graphs before
`/health` answers: minutes, so the commands wait up to 10 (`VLLM_NATIVE_WAIT`). A release's
directory gains its marker, `.engines-built` (`VLLM_NATIVE_BUILT`), only once it is whole: its
virtualenv built, vLLM and torch installed, and FlashInfer's kernels downloaded. A virtualenv names
its own path inside it, so it is built in place rather than staged and moved, and a directory
without the marker is a failed or interrupted build, which the next build removes first.

`VLLM_NATIVE_ENV` holds where uv and the engine keep what they write, for the commands that run in
a release's environment. The unit, `vllm-server.service`, sets the same compile-cache variables, so
a cache the commands fill is the one the server reads:

- `UV_PYTHON_INSTALL_DIR` and `UV_CACHE_DIR`, uv's Python installs and its package cache;
- `XDG_CACHE_HOME`, the cache root of every library that follows XDG, as torch's does, so none
  writes to `~/.cache`, and `VLLM_CACHE_ROOT`, vLLM's own, named outright though it follows XDG;
- `TRITON_HOME`, under which Triton keeps its cache (`.triton/cache`); `TRITON_CACHE_DIR` is left
  unset, since vLLM then gives each torch.compile cache its own Triton cache, as in the container,
  where setting it would put every compile's kernels in one;
- `FLASHINFER_WORKSPACE_BASE`, under which FlashInfer 0.7 keeps its JIT and cubin cache
  (`.cache/flashinfer`); it reads no variable that names that cache itself.

The functions:

- `vllm_native_release [release]` prints the release given, or the pin's when given nothing,
  after checking it is a vLLM release tag, such as `v0.31.0`, before anything reads the host. A
  tag with no release fails at the install.
- `vllm_native_exec <command...>` runs the command in the host env, from the clone, with uv on its
  `PATH` and `VLLM_NATIVE_ENV` set; mise's own cache stays where it is, since the variables apply
  only inside.
- `vllm_native_current` prints the release `current` names, or nothing when there is no link.
- `vllm_native_row` prints the row file's words, one a line, as `vllm_row_words` prints a row's, or
  nothing when there is none; command substitution drops the trailing newline of either, so the two
  compare equal.
- `vllm_native_active`, `vllm_native_enabled`, and `vllm_native_serving` say whether `vllm-server`
  is active, enabled, or both, as `systemctl` reports them; a host without the unit reads as
  neither.
- `vllm_native_preflight` checks the architect's root steps before anything is built or started
  (`engines_root_steps`): `/opt/vllm`, the unit, and its sudoers rule. Then it checks that the host
  env's uv is installed, and what serving needs (`engines_preflight`), and sets `VLLM_ADDR` to the
  tailnet address the unit binds. uv is checked with `mise which`, which fails when the pinned uv
  isn't installed, since `mise exec` would then run any uv on the `PATH` instead, or install the
  pin through mise's shims.
- `vllm_native_kernels <dir>` downloads FlashInfer's precompiled kernels into the release's
  environment: `vllm download-kernels`, which installs the `flashinfer-cubin` and
  `flashinfer-jit-cache` wheels matching its FlashInfer, so a start neither downloads nor compiles
  them. A release older than that command (v0.31.0 has none) runs what it runs, FlashInfer's own
  `download-kernels` with FlashInfer's version check off. FlashInfer installs the wheels with uv
  when uv made the environment and is on the `PATH`, as it is here, into uv's cache under
  `/opt/vllm`.
- `vllm_native_build <release>` builds the release into `/opt/vllm/<release>`, unless it is there
  whole: it removes what a failed build left, then makes the virtualenv on uv-managed CPython (uv
  downloads it into `/opt/vllm/python` the first time), with pip seeded, as FlashInfer's kernel
  install wants; installs vLLM at the release, with torch and its companions from PyTorch's cu130
  index; and downloads FlashInfer's kernels. It marks the directory whole last.
- `vllm_native_link <release>` points `current` at the release.
- `vllm_native_write_row` writes the row `VLLM_MODEL` names into the row file, after `vllm_row`:
  written beside it and moved into place, so the unit never reads half a file.
- `vllm_native_stop` stops `vllm-server` when it is up (`engines_unit_up`), so its memory is free
  before another start: two servers can't both reserve 0.80 of the GB10's memory.
- `vllm_native_serve [restart]` brings `vllm-server` up on the release `current` names and the row
  file, after `vllm_native_preflight`: it enables it, so it starts at boot, when it isn't enabled;
  restarts it when given `restart`, or else starts it when it isn't active; then waits until it
  answers `/health` on port 8000 of `VLLM_ADDR`, for at most 10 minutes. Each `systemctl` call is
  one the sudoers rule names exactly.
- `vllm_native_versions` prints what the serving release reports, after `vllm_native_serve`: the
  server's `/version`, and the CUDA version torch was built for in `current`'s environment, 13.0
  from the cu130 index, with `VLLM_NATIVE_ENV` set, as for every command run in a release's
  environment.
- `vllm_native_remove_releases [release]` removes every release under `/opt/vllm` but the one
  given (all of them when given nothing), and any row file a killed write left, printing each
  release. It stops at the first failure, so it never reports a release it did not remove.
