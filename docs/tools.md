# Tools

This page gives the reasoning behind the repository's tool configuration and scripts: the mise
environments, the check and currency scripts, marathon's settings, the untracked files, and
shellcheck's settings. Each file's header points at its section with a `See` line.

## The check and currency

[`mise.toml`](../mise.toml) pins the laptop's tools, jq, shellcheck, and marathon (whose release
carries lint-context and lint-references), and defines the two tasks: `mise run check` shellchecks
every tracked shell script and runs lint-context and lint-references, reading no network and
writing nothing, and `mise run currency` reports every pin behind its latest, exiting nonzero if
any. Both lints run before the check fails on either, and a lint missing from PATH fails the check
with `FAIL: <lint> is not on PATH; run mise install`. Tasks never install a missing tool
(`task.run_auto_install = false`); `mise install` is the one step that reads the network.

Currency reports every mise tool pinned behind its latest, each host class's llama.cpp build
(`host/llama.env`) behind the newest b-build with that class's server image on ghcr.io
([llama.cpp's Update](engines/llama.cpp/update.md#how-the-pin-moves)), and the vLLM release
(`host/vllm.env`) behind vLLM's latest GitHub release
([vLLM's Update](engines/vllm/update.md#how-the-pin-moves)).

`scripts/currency.sh` reads each mise environment, bench and host, on its own, since both pin uv
and one would hide the other's pin; `mise.toml`'s tools, which both read, are listed once. mise
lists a tool not installed here, such as hf on the laptop, with no bump, so its pin is compared
with its latest instead. A failed read stops the script.

llama.cpp's latest is not its newest release, since llama.cpp publishes images only nightly and on
manual runs, so its newest release often has none and `engines llama update` couldn't pull it. One
flavor's image stands for each class's: gb10's `server-cuda13-<build>`, and strix-halo's
`server-vulkan-<build>`. The builds are read newest first, stopping at the first whose image
exists (200); a 404 means none yet, and any other answer is a failed read. A class is reported
only when its pin is lower. Native vLLM's Python is a minor version, whose latest is the minor
version of CPython's latest release, as mise reads it. A pin held on purpose, as GuideLLM's Python
and native vLLM's Python are, is reported like any other, and the comment beside the pin says why
it is held.

## The bench environment

[`mise.bench.toml`](../mise.bench.toml) holds the load tool the spike measures with from the
laptop, GuideLLM, and the runtimes it needs. It lives in its own environment, not `mise.toml`, so
`mise run check` never installs it. Activate it with `MISE_ENV=bench`:

```sh
MISE_ENV=bench mise install
MISE_ENV=bench mise exec -- guidellm
```

mise's pipx backend installs GuideLLM through uv, with its vision and audio extras, which the
vision cells' image requests and the audio-chat cells' audio requests need
([The benchmark cells](bench.md)). Python's hold reason stays beside its pin.

## The host environment

`mise.host.toml` holds hf, the download tool the spike runs on a host, and the uv that installs it
([llama.cpp's Models](engines/llama.cpp/models.md#setting-up-hf)).

## marathon's settings

[`.claude/marathon.toml`](../.claude/marathon.toml) sets the project's kind, `code`: this spike
holds shell scripts and engine guides, checked by `mise run check`, with `mise run currency` as
its currency command ([The check and currency](#the-check-and-currency)). It has no gate. The
spike answered for experiment.hosting, which is complete; `standards-lab/roadmap/v1.ai.hosting.toml`
builds from its answer.

Its `[remote]` table names the remote platform and the commands that publish and merge a finished
branch. The spike has no CI, so the merge doesn't wait on pull-request checks.

## Untracked files

[`.gitignore`](../.gitignore) leaves marathon's working files (`.claude/plans/`, `.claude/briefs/`)
untracked, and benchmark scratch output under `.state/` before its findings are committed.

## Shellcheck's settings

[`.shellcheckrc`](../.shellcheckrc) sets `external-sources=true`, so shellcheck follows the files a
script sources, such as `host/llama.env`, and checks their use.
