# llama-bench

## What llama-bench is

`llama-bench` is llama.cpp's own benchmark of the engine itself, without the server: it loads a
GGUF model onto the backend (on the GB10, CUDA) and times two tests, with no HTTP, no
tokenization, and no sampling in the measure:

- **pp**, prompt processing: the model reads a prompt of the size given (`-p`, such as 512
  tokens) in batches, as prefill does.
- **tg**, text generation: the model generates the number of tokens given (`-n`, such as 256),
  one at a time, as decode does.

Each test runs the number of repetitions given (`-r`, 5 by default) after a warm-up run, and
reports tokens per second as the mean and standard deviation over the repetitions. Where GuideLLM
measures what a client sees through the server (TTFT, throughput, concurrency), llama-bench
measures the backend's raw rate for one stream, so the same build compares across hosting methods
and hosts with the server taken out.

## Setting it up

llama-bench ships with every llama.cpp build, so the spike installs nothing for it.

**Native.** It is in the native prebuilt, beside `llama-server`, under the build `current` names
([Setup](setup.md#gb10-native)):

```sh
/opt/llama.cpp/current/llama-bench --list-devices
```

`--list-devices` lists the GB10 as a CUDA device, as `llama-server`'s does.

**In a container.** The server image the spike runs, `server-cuda13-<build>`, holds only
`llama-server`. ggml's `full-cuda13-<build>` image holds every tool, llama-bench among them, for
the same build. Its entrypoint, `/app/tools.sh`, picks the tool from its first argument;
`--bench` (or `-b`) runs `./llama-bench` in `/app` with the rest. Pull it for the pin, v0.7.0
(b11669), and list the devices it finds with the GPU attached:

```sh
docker pull ghcr.io/ggml-org/llama.cpp:full-cuda13-b11669
docker run --rm --gpus all ghcr.io/ggml-org/llama.cpp:full-cuda13-b11669 --bench --list-devices
```

For arm64 the image downloads about 3.4 GB, against the server image's 2.5 GB, since it carries
Python and llama.cpp's conversion scripts too.

## Running it

llama-bench loads its own copy of the model, so run it while no engine has a model loaded, for
the memory and so no other load shares the GPU. It reads the model store directly: `-m` names a
GGUF file in `/srv/models` (a split model's first shard), or `-hf` names a repository and
quantization, as the preset's `hf-repo` does, which it resolves from `LLAMA_CACHE`. The general
form, natively:

```sh
LLAMA_CACHE=/srv/models /opt/llama.cpp/current/llama-bench -m <model.gguf> -p <prompt tokens> -n <generated tokens> -r <repetitions>
```

and in the container, as the invoking user, with the store mounted where it is on the host:

```sh
docker run --rm --gpus all --user "$(id -u):$(id -g)" --volume /srv/models:/srv/models --env LLAMA_CACHE=/srv/models ghcr.io/ggml-org/llama.cpp:full-cuda13-b11669 --bench -m <model.gguf> -p <prompt tokens> -n <generated tokens> -r <repetitions>
```

Other options set what the server's preset and log set: `-ngl` the layers on the GPU, `-fa` flash
attention (`on`, `off`, or `auto`), and `-b` and `-ub` the batch sizes. Each option takes a
comma-separated list, and llama-bench runs every combination. The exact commands each comparison
runs are in its finding's method.

## What it reports

By default, a Markdown table with one row per test: the model, its size and parameters, the
backend, the options that differ from the defaults (such as `ngl`), the test (`pp512`, `tg256`),
and `t/s`, the mean ± the standard deviation over the repetitions. The last line names the build,
as `build: 620d2225c (11669)` at v0.7.0 (b11669), so every result carries its version.
`-o json` (or `jsonl`, `csv`) prints the same with every repetition's own sample, for a finding
that keeps the raw numbers.
