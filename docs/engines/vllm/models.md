# Models

## The pinned model

A vLLM server serves one model, named on its command line, and loads no other on demand. The
model is pinned beside the release in `engines/vllm.env`, as `VLLM_MODEL`:
`nvidia/Gemma-4-26B-A4B-NVFP4`, NVIDIA's NVFP4 quantization of Gemma 4 26B-A4B, a mixture of
experts with 4B of its 26B parameters active per token. It is 18.8 GB, ungated, so no token.

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

vLLM's models are each a whole repository. gpt-oss-120b's leaves out `original/` and `metal/`,
the same weights for OpenAI's reference and Metal implementations, which vLLM doesn't read:

| Shape | Repository | Size |
|---|---|---|
| dense small, BF16 | `google/gemma-4-E4B-it` | 16.02 GB |
| dense small, QAT w4a16 | `google/gemma-4-E4B-it-qat-w4a16-ct` | 11.55 GB |
| dense mid, QAT w4a16 | `google/gemma-4-12B-it-qat-w4a16-ct` | 10.30 GB |
| dense large, NVFP4 | `nvidia/Gemma-4-31B-IT-NVFP4` | 32.67 GB |
| MoE, NVFP4 | `nvidia/Gemma-4-26B-A4B-NVFP4` | 18.83 GB, in the store |
| embedding, BF16 | `google/embeddinggemma-2` | 1.53 GB |
| MoE, MXFP4 | `openai/gpt-oss-120b` | 65.28 GB, without `original/` and `metal/` |

The w4a16 models are Google's quantization-aware trained ones. The sizes are the
repositories', from Hugging Face's API.
The pinned model is already in the store, from its first download.

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

Changing the model is a pin edit and an update, not a request to the server. Edit `VLLM_MODEL`
in `engines/vllm.env`, and the model this guide quotes to match. The server's parser flags in
`engines/vllm.sh` are Gemma 4's, so a model of another family changes them too. Commit and push;
then, on each host, `git pull` and `engines/engines vllm update`
([Update](update.md#moving-to-the-pinned-release-or-model)). The new container downloads the new
model on its first start, a cold start to record, and the old model stays in the store until it
is deleted ([Uninstall](uninstall.md#deleting-the-model)).
