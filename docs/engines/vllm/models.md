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

## The first download

The container fetches the model when it first starts, into `/srv/models`, its Hugging Face cache,
before it loads it. On the host, the model's directory grows to about 17.5 GiB as the files
arrive, and the server's log shows the download and then the load:

```sh
du -sh /srv/models/models--nvidia--Gemma-4-26B-A4B-NVFP4
docker logs --tail 20 vllm
```

The files land in `/srv/models/models--nvidia--Gemma-4-26B-A4B-NVFP4`, in Hugging Face's cache
layout, beside llama.cpp's models. A later start reads them from the store. A start that
downloads is the longest cold start; record it as one
([Setup](setup.md#6-watch-the-cold-start-and-record-it)).

## Copying the model to the other GB10

Download the model once, on gb10-1, and copy it to gb10-2 over the QSFP link instead of
downloading it again. The `gb10-N-qsfp` names and passwordless SSH between the nodes come from
the GB10 setup in dotfiles. Copy only once gb10-1's log shows `Application startup complete.`,
so no partial file travels. On gb10-1:

```sh
rsync -a --info=progress2 /srv/models/models--nvidia--Gemma-4-26B-A4B-NVFP4 gb10-2-qsfp:/srv/models/
```

`rsync -a` keeps the cache's links between `snapshots/` and `blobs/`, and both hosts run the
container as the same user, so gb10-2 owns the copy. Then, on gb10-2, run vLLM's
[Setup](setup.md) through its install; the container finds the model in the store and downloads
none of its files. Its log shows no download, and its cold start is the load and the compile
alone; record it.

## Changing the model

Changing the model is a pin edit and an update, not a request to the server. Edit `VLLM_MODEL`
in `engines/vllm.env`, and the model this guide quotes to match. The server's parser flags in
`engines/vllm.sh` are Gemma 4's, so a model of another family changes them too. Commit and push;
then, on each host, `git pull` and `engines/engines vllm update`
([Update](update.md#moving-to-the-pinned-release-or-model)). The new container downloads the new
model on its first start, a cold start to record, and the old model stays in the store until it
is deleted ([Uninstall](uninstall.md#deleting-the-model)).
