# Models

## The preset

The router serves the models its preset names, `engines/llama-preset/models.ini`, which the
container reads from the clone at `/etc/llama-preset/models.ini`. Each section is one model,
named as clients name it in `"model"`; its keys are `llama-server` arguments without the leading
dashes, and `[*]` holds the keys every model shares. `hf-repo` names the Hugging Face repository
and quantization the model comes from: the router picks the repository's GGUF whose name carries
the quantization, such as `gemma-4-E4B_q4_0-it.gguf` for `:Q4_0`, and attaches the repository's
projector (`mmproj`) beside it, which carries a Gemma 4 model's vision encoder, and E4B's audio
encoder too. The store is Hugging Face's cache layout, which llama.cpp reads as hf writes it
(`models--<org>--<repo>`, its `refs/main` naming the snapshot), so a section names no file path or
snapshot hash and resolves the same model hf pre-staged
([Pre-staging models with hf](#pre-staging-models-with-hf)).

| Key | Value | Why |
|---|---|---|
| `n-gpu-layers` (`[*]`) | `all` | Every layer on the GB10's GPU. |
| `dedup-cache-models` (`[*]`) | `true` | Once a model is downloaded, the router lists its preset alone, not the cache entry beside it. |
| `metrics` (`[*]`) | `true` | Each model serves `/metrics`, its Prometheus counters ([API](api.md#metrics)), which the benchmarks read for the server's own figures. |
| `offline` (`[*]`) | `true` | Each model resolves from the store alone, with no request to Hugging Face: a load never downloads, and a timed cold load reads only the disk. A model not in the store fails to load; pre-stage it first. |
| `hf-repo` | `ggml-org/gpt-oss-120b-GGUF:MXFP4` | gpt-oss-120b in its native MXFP4, 63.4 GB, ungated, so no token. |
| `parallel` | `4` | 4 slots: four requests decode at once, and a fifth waits. |
| `c` | `32768` | The context, split evenly across the slots: 8192 tokens each. |
| `temp`, `top-p`, `top-k`, `min-p` | `1`, `1`, `0`, `0` | OpenAI's recommended sampling for gpt-oss, temperature 1.0 and top_p 1.0, with the server's other truncations off. |

The sections, each one model the router lists:

| Section | Slots × context | Sampling | Other keys |
|---|---|---|---|
| `ggml-org/gpt-oss-120b-GGUF:MXFP4` | 4 × 8192 | gpt-oss's, above | the anchor cells' model |
| `gpt-oss-120b-MXFP4-16-slots` | 16 × 8192 (`c = 131072`) | gpt-oss's | the same file, for the concurrency sweep; load one of the two gpt-oss sections at a time |
| `ggml-org/gemma-4-E4B-it-GGUF:Q8_0` | 4 × 8192 | Gemma 4's | dense small; projector with vision and audio |
| `google/gemma-4-E4B-it-qat-q4_0-gguf:Q4_0` | 4 × 8192 | Gemma 4's | E4B's quantization pair, Google's QAT Q4_0 |
| `google/gemma-4-12B-it-qat-q4_0-gguf:Q4_0` | 4 × 8192 | Gemma 4's | dense mid |
| `google/gemma-4-31B-it-qat-q4_0-gguf:Q4_0` | 4 × 8192 | Gemma 4's | dense large |
| `google/gemma-4-26B-A4B-it-qat-q4_0-gguf:Q4_0` | 4 × 8192 | Gemma 4's | MoE; projector with vision |
| `ggml-org/embeddinggemma-2-GGUF:Q8_0` | 16 × 8192 | none | `embeddings = true`; `batch-size` and `ubatch-size` 8192 |

Gemma 4's sampling is the configuration its cards standardize for every use, temperature 1.0,
top_p 0.95, top_k 64, which vLLM applies from the checkpoint's generation config; `min-p = 0`
turns off llama.cpp's other truncation, which vLLM doesn't apply. Every Gemma 4 section attaches
its projector, as vLLM loads the encoders with the model, so the footprints compare. EmbeddingGemma
2 serves only `/v1/embeddings`, with the pooling its GGUF declares. It reads each input whole, not
causally, so one input must fit one physical batch, whose default of 512 tokens is below the
embedding cell's 512 plus the model's own; the batch is raised to a whole slot.

The context is chosen for the spike's anchor request, 512 tokens in and 256 out: 768 tokens of
the 8192 each slot holds, which leaves room for gpt-oss's chat template, its reasoning, and longer
prompts later. The whole cache costs little: gpt-oss-120b's KV cache is about 36 KiB a token, so
32768 tokens is about 1.1 GiB beside about 59 GiB of weights, on a GB10's 119 GiB.

The router re-reads the preset when asked, without a restart, after the clone is updated with
`git pull`:

```sh
curl -s "http://$(tailscale ip -4):8080/models?reload=1" > /dev/null
```

A model already loaded keeps the arguments it was started with. When the preset changes it, the
reload unloads it, so load it again ([Loading a model](#loading-a-model)) to start it with the new
arguments.

## Pre-staging models with hf

The router downloads a model the first time it loads it, so that load waits on the download, and
the download loads the host's network, disk, and CPU while it runs. Pre-staging downloads every
model first, all at once, into the store, before any cell or timed load; each model then loads
from the store without a download.

### What hf is

`hf` is Hugging Face's command line, from its Python client, `huggingface_hub`: the same client
vLLM's image downloads with. `hf download <repo>` fetches a repository, or only the files
`--include` names, into a Hugging Face cache, in the layout both engines read:
`models--<org>--<name>`, with its `snapshots/` linking to the files, which it fetches over
Hugging Face's Xet storage. `hf cache ls` lists what the cache holds and `hf cache rm` deletes a
model from it ([Uninstall](uninstall.md#deleting-models)).

The client keeps the large files in the store shared by every model it fetches,
`/srv/models/blobs`, as vLLM's does, so a model's own directory holds only links; measure it with
`du -shL` ([vLLM's Models](../vllm/models.md#the-first-download)).

### Setting up hf

hf is pinned, with the uv that installs it, in the clone's host environment, `mise.host.toml`
(huggingface_hub 2.3.0, uv 0.13.5), which `mise run currency` covers. It installs into your
account's mise directory, with no root. On gb10-1, from the clone, after a `git pull`:

```sh
MISE_ENV=host mise install
MISE_ENV=host mise exec -- hf version
```

`mise install` also installs the clone's check tools, jq and shellcheck, from `mise.toml`. When
mise asks whether to trust the clone's config files, answer yes. `hf version` prints its
version, 2.3.0. hf runs as `MISE_ENV=host mise exec -- hf`, from the clone, and installs
nothing outside mise's directory.

Every model below is ungated, so no token is needed. hf warns that its requests are
unauthenticated, which only lowers Hugging Face's rate limit.

### The models this spike stages

llama.cpp's models, each the model's file and the projector (`mmproj`) the router fetches beside
it, which carries the model's vision encoder, and E4B's its audio encoder too:

| Shape | Repository | Files | Size |
|---|---|---|---|
| dense small, Q8_0 | `ggml-org/gemma-4-E4B-it-GGUF` | `gemma-4-E4B-it-Q8_0.gguf`, `mmproj-gemma-4-E4B-it-Q8_0.gguf` | 8.59 GB |
| dense small, QAT Q4_0 | `google/gemma-4-E4B-it-qat-q4_0-gguf` | `gemma-4-E4B_q4_0-it.gguf`, `gemma-4-E4B-it-mmproj.gguf` | 6.15 GB |
| dense mid, QAT Q4_0 | `google/gemma-4-12B-it-qat-q4_0-gguf` | `gemma-4-12b-it-qat-q4_0.gguf`, `mmproj-gemma-4-12b-it-qat-q4_0.gguf` | 7.15 GB |
| dense large, QAT Q4_0 | `google/gemma-4-31B-it-qat-q4_0-gguf` | `gemma-4-31B_q4_0-it.gguf`, `gemma-4-31B-it-mmproj.gguf` | 18.85 GB |
| MoE, QAT Q4_0 | `google/gemma-4-26B-A4B-it-qat-q4_0-gguf` | `gemma-4-26B_q4_0-it.gguf`, `gemma-4-26B-it-mmproj.gguf` | 15.63 GB |
| embedding, Q8_0 | `ggml-org/embeddinggemma-2-GGUF` | `embeddinggemma-2-Q8_0.gguf`, `mmproj-embeddinggemma-2-Q8_0.gguf` | 0.86 GB |
| MoE, MXFP4 | `ggml-org/gpt-oss-120b-GGUF` | `gpt-oss-120b-MXFP4.gguf` | 63.39 GB, in the store |

The Q4_0 files are Google's quantization-aware trained ones, which meet the quantization floor;
ggml-org's Gemma 4 Q4_0 is quantized from BF16 and doesn't. Each `mmproj` named is the one
Hugging Face's manifest gives the router for that repository and quantization. The sizes are the
files', from Hugging Face's API.

vLLM's models are listed in [vLLM's Models](../vllm/models.md#pre-staging-models-with-hf), and
the procedure below stages both engines' together. The two models already in the store,
gpt-oss-120b's GGUF and vLLM's pinned NVFP4 model, stay as they are; the rest of both engines'
is about 195 GB.

### Pre-staging everything at once

On gb10-1, from the clone. First set what every download shares: hf's environment, the store as
its cache, and Xet's high-performance mode, which uses more of the host's CPU, memory, and
connections to download faster. Then define `stage`, which runs one `hf download` in the
background, apart from the SSH session, writing its output and then its exit status to a log in
`~/prestage`:

```sh
export MISE_ENV=host HF_HUB_CACHE=/srv/models HF_XET_HIGH_PERFORMANCE=1
mkdir -p ~/prestage
stage() { nohup bash -c 'mise exec -- hf download "$@"; echo "exit $?"' stage "$@" > ~/prestage/"${1//\//--}".log 2>&1 & }
```

Then start every download, and both engines' pinned images (`engines/llama.env`,
`engines/vllm.env`), together:

```sh
stage ggml-org/gemma-4-E4B-it-GGUF --include gemma-4-E4B-it-Q8_0.gguf --include mmproj-gemma-4-E4B-it-Q8_0.gguf
stage google/gemma-4-E4B-it-qat-q4_0-gguf --include gemma-4-E4B_q4_0-it.gguf --include gemma-4-E4B-it-mmproj.gguf
stage google/gemma-4-12B-it-qat-q4_0-gguf --include gemma-4-12b-it-qat-q4_0.gguf --include mmproj-gemma-4-12b-it-qat-q4_0.gguf
stage google/gemma-4-31B-it-qat-q4_0-gguf --include gemma-4-31B_q4_0-it.gguf --include gemma-4-31B-it-mmproj.gguf
stage google/gemma-4-26B-A4B-it-qat-q4_0-gguf --include gemma-4-26B_q4_0-it.gguf --include gemma-4-26B-it-mmproj.gguf
stage ggml-org/embeddinggemma-2-GGUF --include embeddinggemma-2-Q8_0.gguf --include mmproj-embeddinggemma-2-Q8_0.gguf
stage google/gemma-4-E4B-it
stage google/gemma-4-E4B-it-qat-w4a16-ct
stage google/gemma-4-12B-it-qat-w4a16-ct
stage nvidia/Gemma-4-31B-IT-NVFP4
stage google/embeddinggemma-2
stage openai/gpt-oss-120b --exclude "original/*" --exclude "metal/*"
nohup bash -c 'docker pull ghcr.io/ggml-org/llama.cpp:server-cuda13-b11669; echo "exit $?"' > ~/prestage/llama-image.log 2>&1 &
nohup bash -c 'docker pull vllm/vllm-openai:v0.32.0; echo "exit $?"' > ~/prestage/vllm-image.log 2>&1 &
```

Each log is named for its repository, such as `~/prestage/google--gemma-4-E4B-it.log`. The
downloads and pulls keep running when the SSH session ends.

### Checking that every download is complete

While any download runs, this lists it; it prints nothing once all have finished:

```sh
pgrep -af "hf download|docker pull"
```

Then check each one. Every log ends with `exit 0`, and no partial file, which hf names
`*.incomplete`, is left in the store; the second command prints nothing when none is:

```sh
tail -qn 1 ~/prestage/*.log
find /srv/models -name "*.incomplete"
```

Each model's size, following its links, matches its table row, in GiB (the tables give GB):

```sh
du -shL /srv/models/models--*
```

hf lists every model it finds in the store, with its size, and both images are present:

```sh
mise exec -- hf cache ls
docker image ls --format "{{.Repository}}:{{.Tag}}" | grep -E "llama.cpp|vllm-openai"
```

A download that ends in an error, or stops early, resumes from what it fetched: run its `stage`
line again. A complete model fetches nothing again. When every check passes, `rm -r ~/prestage`
removes the logs; a new shell starts without the exports and `stage`.

## The host's address on the laptop

The commands below run on the laptop and name the host by its short name, `gb10-1`, which
Tailscale's MagicDNS resolves to its tailnet address. Check that the name resolves:

```sh
curl -s http://gb10-1:8080/health
```

## Loading a model

The router starts no model by itself. Load gpt-oss-120b through its API:

```sh
curl -s -X POST "http://gb10-1:8080/models/load" -H "Content-Type: application/json" -d '{"model": "ggml-org/gpt-oss-120b-GGUF:MXFP4"}'
```

It answers `{"success":true}` at once and loads in the background. The preset's `offline = true`
loads every model from the store, so a model must be pre-staged first
([Pre-staging models with hf](#pre-staging-models-with-hf)); one that isn't fails to load, and
shows `"failed": true` in [the model list](#listing-models). A restart of the container, by an
update or a reboot, unloads every model, so load it again after one.

## Watching the download

The preset's `offline = true` keeps the router from downloading anything, so this and the next
section apply only to a preset without it, which lets a load download its model. On the host, the
store grows by about 60 GiB as the files arrive, and the router's log shows the
download and then the load:

```sh
du -sh /srv/models
docker logs --tail 20 llama
```

The model's files land in `/srv/models/models--ggml-org--gpt-oss-120b-GGUF`, in Hugging Face's
cache layout.

## Cancelling a download

A load that is still downloading stops when the container restarts, and the restarted router
loads nothing. On the host, restart it, then delete the model's partial files:

```sh
docker restart llama
rm -rf /srv/models/models--ggml-org--gpt-oss-120b-GGUF
```

## Copying a model to the other GB10

Only under a named borrow of gb10-2 (`ai-hosting.md`, "Hosts and access"): gb10-2 is reserved
for spike-ai-pipeline, and the spike runs on gb10-1 alone. Under a borrow, download a model once,
on gb10-1, and copy it to gb10-2 over the QSFP link instead of downloading it again. The
`gb10-N-qsfp` names and passwordless SSH between the nodes come from the GB10 setup in dotfiles.
Copy only once the model shows `loaded` on gb10-1, so no partial file travels. On gb10-1:

```sh
rsync -a --info=progress2 /srv/models/models--ggml-org--gpt-oss-120b-GGUF gb10-2-qsfp:/srv/models/
```

`rsync -a` keeps the cache's links between `snapshots/` and `blobs/`, and both hosts run the
container as the same user, so gb10-2 owns the copy. Then load the model on gb10-2 as above; the
router finds it in the store and downloads nothing. This copies a model the router downloaded
itself, whose files stay in its own directory. A model hf pre-staged keeps its files in the shared
`/srv/models/blobs`, so copy it as vLLM's model is copied, with the shared store beside it
([vLLM's Models](../vllm/models.md#copying-the-model-to-the-other-gb10)).

## Listing models

```sh
curl -s "http://gb10-1:8080/models" | jq '.data[] | {id, status: .status.value}'
```

Each model the router knows is listed with its status: `unloaded`, `loading` (during the download
and the load), or `loaded`, when it answers requests. A load that failed shows `unloaded` with
`"failed": true` in its status; the router's log gives the reason.
