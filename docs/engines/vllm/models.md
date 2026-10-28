# Models

## The pinned model

A vLLM server serves one model, named on its command line, and loads no other on demand. The model
and its server flags are a row of `host/vllm-rows`, and the pin beside the release in
`host/vllm.env` names the row each flavor serves by default ([Update](update.md#the-flavor)). The
`cuda` flavor's, on the GB10s, is `VLLM_MODEL_CUDA`: `gemma-4-26B-A4B-NVFP4`. The `rocm` flavor's,
on the Framework, is `VLLM_MODEL_ROCM`: `gpt-oss-120b`, the model of llama.cpp's anchors,
`openai/gpt-oss-120b` in its native MXFP4, since NVFP4 is CUDA's alone.

The `cuda` flavor's model is `nvidia/Gemma-4-26B-A4B-NVFP4`, NVIDIA's NVFP4
quantization of Gemma 4 26B-A4B, a mixture of experts with 4B of its 26B parameters active per
token. It is 18.8 GB, ungated, so no token. The server serves another row for one run when it is
named ([Changing the model](#changing-the-model)).

It meets the spike's quantization floor. Its weights are NVFP4, the 4-bit format Blackwell
computes in natively, and its card's evaluations sit within 0.7 points of the BF16 model's on
every benchmark: GPQA Diamond, AIME 2025, MMLU Pro, LiveCodeBench, IFBench, and IFEval. vLLM's
Gemma 4 recipe lists it as validated on the GB10.

## Pre-staging models with hf

Every model vLLM serves in this spike is downloaded ahead with hf, Hugging Face's command line,
into the store, before any cell or timed load, so the container's start loads it without a
download. llama.cpp's guide says what hf is, sets it up, and gives the one procedure that
pre-stages both engines' models and pulls both images together
([Pre-staging models with hf](../llama.cpp/models.md#pre-staging-models-with-hf)). hf is the
client this image downloads with, so its files land as the container's own would: the model's
directory in Hugging Face's cache layout, and its weight files in the shared store
([The first download](#the-first-download)).

Each of vLLM's models is a whole repository, except two. granite-embedding-english-r2's leaves
out `pytorch_model.bin`, a second copy of `model.safetensors`'s weights. gpt-oss-120b's leaves
out the weights in `original/` and `metal/`, the same weights for OpenAI's reference and Metal
implementations, which vLLM doesn't read, and keeps `original/`'s three JSON files
(`config.json`, `dtypes.json`, `model.safetensors.index.json`, about 57 KB), which vLLM's start
fetches when they're missing:

| Shape | Repository | Size |
|---|---|---|
| dense small, BF16 | `google/gemma-4-E4B-it` | 16.02 GB |
| dense small, QAT w4a16 | `google/gemma-4-E4B-it-qat-w4a16-ct` | 11.55 GB |
| dense mid, QAT w4a16 | `google/gemma-4-12B-it-qat-w4a16-ct` | 10.30 GB |
| dense large, NVFP4 | `nvidia/Gemma-4-31B-IT-NVFP4` | 32.67 GB |
| dense large, QAT w4a16 | `google/gemma-4-31B-it-qat-w4a16-ct` | 23.30 GB |
| MoE, NVFP4 | `nvidia/Gemma-4-26B-A4B-NVFP4` | 18.83 GB, in the store |
| MoE, BF16 | `google/gemma-4-26B-A4B-it` | 51.64 GB |
| embedding, BF16 | `ibm-granite/granite-embedding-english-r2` | 0.30 GB, without `pytorch_model.bin` |
| MoE, MXFP4 | `openai/gpt-oss-120b` | 65.28 GB, without the weights in `original/` and `metal/` |

The w4a16 models are Google's quantization-aware trained ones. The sizes are the repositories', from
Hugging Face's API. The `cuda` flavor's default model is already in gb10-1's store, from its first
download.

### On the Framework

The session's step, from `~/repos/spike-model-engines`, once hf is set up there
([Setting up hf](../llama.cpp/models.md#setting-up-hf)). The Framework stages the models of the
rows the `rocm` flavor can serve ([The rows on the Framework](#the-rows-on-the-framework)),
seven repositories, about 178 GB, and vLLM's ROCm image. gpt-oss-120b's GGUF, seeded into the
store for llama.cpp ([llama.cpp's Models](../llama.cpp/models.md#seeding-the-frameworks-store)),
isn't the repository vLLM serves, so `openai/gpt-oss-120b` downloads too.

Set the exports and define the Framework's `stage`, as llama.cpp's Framework staging does
([On the Framework](../llama.cpp/models.md#on-the-framework)): each job starts with `setsid nohup
… < /dev/null &`, so it outlives a non-interactive `ssh framework '…'` command:

```sh
export MISE_ENV=host HF_HUB_CACHE=/srv/models HF_XET_HIGH_PERFORMANCE=1
mkdir -p ~/prestage
stage() { setsid nohup bash -c 'mise exec -- hf download "$@"; echo "exit $?"' stage "$@" > ~/prestage/"${1//\//--}".log 2>&1 < /dev/null & }
```

Before the first start, gpt-oss-120b alone, with the image, which step 2 of
[Setup](setup.md#2-read-the-gpu-back-through-the-image) pulls; a pull of an image already present
fetches nothing:

```sh
stage openai/gpt-oss-120b --exclude "original/*.safetensors" --exclude "metal/*"
setsid nohup bash -c 'docker pull vllm/vllm-openai-rocm:v0.32.0; echo "exit $?"' > ~/prestage/vllm-rocm-image.log 2>&1 < /dev/null &
```

Before any comparison cell or timed start, the rest, together, with the same exports and
`stage`:

```sh
stage google/gemma-4-E4B-it
stage google/gemma-4-E4B-it-qat-w4a16-ct
stage google/gemma-4-12B-it-qat-w4a16-ct
stage google/gemma-4-31B-it-qat-w4a16-ct
stage google/gemma-4-26B-A4B-it
stage ibm-granite/granite-embedding-english-r2 --exclude "*.bin"
```

The checks are llama.cpp's ([Checking that every download is
complete](../llama.cpp/models.md#checking-that-every-download-is-complete)), read from the logs,
since over SSH the `pgrep` check matches its own command line and never reads empty: every log
ends with `exit 0`, no `*.incomplete` file is left, and each model's size, following its links,
matches the one `du -shL` printed in vllm-strix's
[Staging](../../findings/vllm-strix.md#staging):

```sh
tail -qn 1 ~/prestage/*.log
find /srv/models -name "*.incomplete"
du -shL /srv/models/models--openai--gpt-oss-120b /srv/models/models--google--gemma-4-* /srv/models/models--ibm-granite--*
docker image ls vllm/vllm-openai-rocm
```

The last lists `v0.32.0`. `rm -r ~/prestage` then removes the logs.

## The first download

The container fetches the model when it first starts, into `/srv/models`, its Hugging Face cache,
before it loads it. The server's log shows the download and then the load, and on the host the
model grows to about 17.5 GiB as the files arrive:

```sh
du -shL /srv/models/models--nvidia--Gemma-4-26B-A4B-NVFP4
docker logs --tail 20 vllm
```

The model's directory, `/srv/models/models--nvidia--Gemma-4-26B-A4B-NVFP4`, is in Hugging
Face's cache layout, beside llama.cpp's models, but the Hugging Face client in vLLM's image keeps
the large weight files out of it. They land in a store shared by every model this client fetches,
at the cache's root: `/srv/models/blobs/<2 hex>/<sha256>`, named by their content. The model's
own `blobs/` holds the small files and a link into the shared store for each large one, and its
`snapshots/` link to its `blobs/`. A plain `du -sh` of the directory doesn't follow those links
and shows a few MB; `du -L` follows them, and counts a file reached by two links once. The shared
store also shows its size, `du -sh /srv/models/blobs`, and `readlink -f` shows where a weight
file lives:

```sh
readlink -f /srv/models/models--nvidia--Gemma-4-26B-A4B-NVFP4/snapshots/*/model-00001-of-00002.safetensors
```

It prints a path under `/srv/models/blobs/`. The client also leaves `.locks/` and
`CACHEDIR.TAG` at the cache's root. llama.cpp's downloads don't use the shared store:
gpt-oss-120b keeps its files in its own `blobs/`.

A later start reads the model from the store. A start that downloads is the longest cold start;
record it as one ([Setup](setup.md#6-watch-the-cold-start-and-record-it)).

## Copying the model to the other GB10

Only under a named borrow of gb10-2 (`ai-hosting.md`, "Hosts and access"): gb10-2 is reserved
for spike-ai-pipeline, and the spike runs on gb10-1 alone. Under a borrow, download the model
once, on gb10-1, and copy it to gb10-2 over the QSFP link instead of downloading it again. The
`gb10-N-qsfp` names and passwordless SSH between the nodes come from the GB10 setup in dotfiles.
Copy only once gb10-1's log shows `Application startup complete.`, so no partial file travels.
On gb10-1:

```sh
rsync -a --info=progress2 /srv/models/models--nvidia--Gemma-4-26B-A4B-NVFP4 /srv/models/blobs gb10-2-qsfp:/srv/models/
```

The model is two directories: its own, and the shared store its links point into
([The first download](#the-first-download)), so both travel. This copies the whole shared store,
any other vLLM model in it too; that is safe to repeat, since rsync skips the files gb10-2
already holds. `rsync -a` keeps the cache's links, relative as the client wrote them, and both
hosts run the container as the same user, so gb10-2 owns the copy. On gb10-2, check that every
link in the model resolves; this prints nothing when they all do:

```sh
find /srv/models/models--nvidia--Gemma-4-26B-A4B-NVFP4/snapshots -xtype l
```

Then, on gb10-2, run vLLM's [Setup](setup.md) through its install; the container finds the model
in the store and downloads none of its files. Its log shows no download, and its cold start is
the load and the compile alone; record it.

## Changing the model

### The rows

Every model the server serves is a row of `host/vllm-rows`: an id in brackets, the model's Hugging
Face repository, then its server flags. The file's comments give each flag's reason. The rows are
one set for both flavors. Every row serves sequences of 8192 tokens and reserves 0.80 of the host's
GPU memory, on every host (`--max-model-len 8192 --gpu-memory-utilization 0.80`), and the model's
own generation config sets its sampling. Beyond those:

| Row id | Model | Flags | Serves |
|---|---|---|---|
| `gemma-4-26B-A4B-NVFP4` | `nvidia/Gemma-4-26B-A4B-NVFP4` | `--max-num-seqs 4 --kv-cache-dtype bfloat16 --reasoning-parser gemma4 --enable-auto-tool-choice --tool-call-parser gemma4` | the `cuda` flavor's default; the anchors A' and B', vision |
| `gemma-4-26B-A4B-NVFP4-flashinfer` | `nvidia/Gemma-4-26B-A4B-NVFP4` | the default's, plus `--attention-backend FLASHINFER --language-model-only` | the FlashInfer diagnostic, text only |
| `gemma-4-26B-A4B-NVFP4-marlin` | `nvidia/Gemma-4-26B-A4B-NVFP4` | the default's, plus `--moe-backend marlin` | the Marlin MoE diagnostic, with vision |
| `gemma-4-26B-A4B-it` | `google/gemma-4-26B-A4B-it` | the default's | MoE, BF16, with its vision |
| `gemma-4-E4B-it` | `google/gemma-4-E4B-it` | the default's | dense small, BF16, with its vision and audio |
| `gemma-4-E4B-it-qat-w4a16-ct` | `google/gemma-4-E4B-it-qat-w4a16-ct` | the default's | dense small, QAT w4a16, with its vision and audio |
| `gemma-4-12B-it-qat-w4a16-ct` | `google/gemma-4-12B-it-qat-w4a16-ct` | the default's | dense mid, QAT w4a16 |
| `Gemma-4-31B-IT-NVFP4` | `nvidia/Gemma-4-31B-IT-NVFP4` | the default's | dense large, NVFP4 |
| `gemma-4-31B-it-qat-w4a16-ct` | `google/gemma-4-31B-it-qat-w4a16-ct` | the default's | dense large, QAT w4a16 |
| `granite-embedding-english-r2` | `ibm-granite/granite-embedding-english-r2` | `--runner pooling --max-num-seqs 16` | `/v1/embeddings` only |
| `gpt-oss-120b` | `openai/gpt-oss-120b` | `--max-num-seqs 16 --reasoning-parser openai_gptoss --enable-auto-tool-choice --tool-call-parser openai` | the `rocm` flavor's default; 16 sequences, its KV cache the checkpoint's |

granite-embedding-english-r2, a ModernBERT encoder with heads of 64, runs its encoder-only
attention on `FLASH_ATTN` on the GB10's SM121.

"The default's" is the `gemma-4-26B-A4B-NVFP4` row's flags.

A row's id is its repository's name without the organization, with a suffix for a second row of
the same model. The container's command is the row's model, `--host 0.0.0.0 --port 8000`, then
the row's flags, which `docker inspect` shows
([Update](update.md#moving-to-the-pinned-release-or-model)).

### The rows on the Framework

The `rocm` flavor serves the rows whose format ROCm runs, every one but the NVFP4 rows, which are
CUDA's alone. Every row serves on gfx1151 at v0.32.0, but the official image ships no audio
decoder, so an audio request returns 500
([vllm-strix](../../findings/vllm-strix.md#unsupported-cells)).

| Row id | Shape |
|---|---|
| `gpt-oss-120b` | MoE, MXFP4, the `rocm` flavor's default |
| `gemma-4-26B-A4B-it` | MoE, BF16, with its vision |
| `gemma-4-E4B-it` | dense small, BF16, with its vision and audio |
| `gemma-4-E4B-it-qat-w4a16-ct` | dense small, QAT w4a16, with its vision and audio |
| `gemma-4-12B-it-qat-w4a16-ct` | dense mid, QAT w4a16 |
| `gemma-4-31B-it-qat-w4a16-ct` | dense large, QAT w4a16 |
| `granite-embedding-english-r2` | embedding, BF16, `/v1/embeddings` only |

Every model is staged through hf before its row starts ([On the Framework](#on-the-framework)).
A row serves on the Framework as on the GB10, named in `VLLM_MODEL` before `update`
([Serving another row for one run](#serving-another-row-for-one-run)); the flavor is the host's
own, so the image stays `vllm/vllm-openai-rocm:v0.32.0` and only the row changes.

### Serving another row for one run

On the host, from the clone, name the row in `VLLM_MODEL` before `update`, in the same command,
so it applies to that run alone:

```sh
VLLM_MODEL=gpt-oss-120b host/engines vllm update
```

`update` compares the container's whole command, image, model, and flags, with the row's, so it
replaces the container when any of them differs. The image is already the pin's, so switching
rows pulls nothing and only starts the container again. Nothing is edited or committed: the pin
stays the host's default. The new container starts cold; time and record the start as
[Setup](setup.md#6-watch-the-cold-start-and-record-it) shows. A row whose model isn't in the
store downloads it on that start, so pre-stage it first ([Pre-staging models with
hf](#pre-staging-models-with-hf)).

An id with no row refuses, changing nothing, and lists the rows:

```sh
VLLM_MODEL=gemma-4-E2B-it host/engines vllm update
```

`install` takes the same `VLLM_MODEL` when `vllm` isn't installed; when it is, `install` refuses
any row it doesn't already serve and points at `update`. Both still refuse while llama.cpp's
`llama` container or `llama-router` unit runs, or native vLLM's `vllm-server` does.

Native vLLM takes the same `VLLM_MODEL` before `host/engines vllm-native install` or `update`,
which compare the row with the row file, `/opt/vllm/row`, as the container's compare its
command, and restart `vllm-server` on the row when they differ
([Update](update.md#native)).

### Returning to the default

`update` without `VLLM_MODEL` serves the flavor's default row again:

```sh
host/engines vllm update
```

On gb10-1 it prints `vllm moved from ... to vllm/vllm-openai:v0.32.0 with row gemma-4-26B-A4B-NVFP4
(nvidia/Gemma-4-26B-A4B-NVFP4)`, and on the Framework `... to vllm/vllm-openai-rocm:v0.32.0 with row
gpt-oss-120b (openai/gpt-oss-120b)`, another cold start to record. Leave every host on the default
row when a session ends. Use `VLLM_MODEL=...` only as the command's prefix, never `export` it: an
exported one would keep naming its row for every later command in that shell.

### Adding a row, or moving the default

A new model is a new row in `host/vllm-rows`, and moving a flavor's default is an edit of
`VLLM_MODEL_CUDA` or `VLLM_MODEL_ROCM` in `host/vllm.env`, with the model this guide,
[Setup](setup.md), and [API](api.md) quote to match. A Gemma 4 row takes the default row's parser
flags; a model of another family takes its own. Commit and push; then, on the host, `git pull` and
`host/engines vllm update` ([Update](update.md#moving-to-the-pinned-release-or-model)). A model the
store lacks downloads on its first start, a cold start to record, and an old model stays in the
store until it is deleted ([Uninstall](uninstall.md#deleting-the-model)).
