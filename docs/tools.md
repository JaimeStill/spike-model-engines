# Tools

The reasoning behind the repository's tool configuration: the mise environments, marathon's
settings, and shellcheck's. Each file's header points at its section with a `See` line.

## The check and currency

[`mise.toml`](../mise.toml) pins the laptop's tools, jq and shellcheck, and defines the two tasks:
`mise run check` shellchecks every tracked shell script, reading no network and writing nothing,
and `mise run currency` reports every pin behind its latest, exiting nonzero if any. Tasks never
install a missing tool (`task.run_auto_install = false`); `mise install` is the one step that reads
the network.

Currency reports every mise tool pinned behind its latest, each host class's llama.cpp build
(`host/llama.env`) behind the newest b-build with that class's server image on ghcr.io
([llama.cpp's Update](engines/llama.cpp/update.md#how-the-pin-moves)), and the vLLM release
(`host/vllm.env`) behind vLLM's latest GitHub release
([vLLM's Update](engines/vllm/update.md#how-the-pin-moves)).

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
its currency command ([The check and currency](#the-check-and-currency)). It has no gate. Its
goals live in the coordinator's roadmap, `standards-lab/roadmap/index.toml`.

Its `[remote]` table names the remote platform and the commands that publish and merge a finished
branch. The spike has no CI, so the merge doesn't wait on pull-request checks.
