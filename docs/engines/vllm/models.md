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
setsid nohup bash -c 'docker pull vllm/vllm-openai-rocm:v0.34.0; echo "exit $?"' > ~/prestage/vllm-rocm-image.log 2>&1 < /dev/null &
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

The last lists `v0.34.0`. `rm -r ~/prestage` then removes the logs.

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

Only under a named borrow of gb10-2: gb10-2 is reserved for spike-ai-pipeline, and the spike runs on
gb10-1 alone. Under a borrow, download the model once, on gb10-1, and copy it to gb10-2 over the
QSFP link instead of downloading it again. The `gb10-N-qsfp` names and passwordless SSH between the
nodes come from the GB10 setup in dotfiles. Copy only once gb10-1's log shows `Application startup
complete.`, so no partial file travels. On gb10-1:

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
Face repository, then its server flags; [The rows file](#the-rows-file) gives its format, and [Each
row's reasons](#each-rows-reasons) and [The standing rows](#the-standing-rows) each flag's reason.
The flags leave out `--max-model-len 8192`, which every row but the agent rows names, and
`--gpu-memory-utilization 0.80` where a row names no other fraction; "the default's" is the
`gemma-4-26B-A4B-NVFP4` row's flags. The rows a run names:

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
| `gpt-oss-120b-agent` | `openai/gpt-oss-120b` | `--max-num-seqs 8 --max-model-len 131072`, and `gpt-oss-120b`'s parsers | the agent; 8 sessions of 131,072 tokens, its KV cache the checkpoint's |

The standing rows, the ones each host stands on:

| Row id | Model | Flags | Serves |
|---|---|---|---|
| `gpt-oss-120b-agent-fp8` | `openai/gpt-oss-120b` | `--served-model-name agent --max-num-seqs 12 --max-model-len 131072 --gpu-memory-utilization 0.80 --max-num-queued-reqs 24 --scheduling-policy priority --kv-cache-dtype fp8 --kv-cache-memory-bytes 32993476982`, and `gpt-oss-120b`'s parsers | `agent` on gb10-1, alone; 12 sessions of 131,072 tokens on an FP8 KV cache |
| `gemma-4-26B-A4B-NVFP4-vision-gb10` | `nvidia/Gemma-4-26B-A4B-NVFP4` | `container=vllm-vision port=8000`, then `--served-model-name vision --max-num-seqs 16 --gpu-memory-utilization 0.40 --max-num-queued-reqs 32 --scheduling-policy priority`, and the default's KV cache and parsers | `vision` on gb10-2, alone |
| `gemma-4-E4B-it-audio-framework` | `google/gemma-4-E4B-it` | `container=vllm-audio port=8001 image=spike-model-engines/vllm-openai-rocm-audio`, then `--served-model-name audio --max-num-seqs 4 --gpu-memory-utilization 0.18 --max-num-queued-reqs 8`, and the default's KV cache and parsers | `audio` on the Framework, from the audio image the host builds |
| `granite-embedding-english-r2-framework` | `ibm-granite/granite-embedding-english-r2` | `container=vllm-embed port=8002`, then `--served-model-name embedding --runner pooling --max-num-seqs 128 --gpu-memory-utilization 0.03 --max-num-batched-tokens 65536` | `embedding` on the Framework, beside audio; no queue limit, since the gateway's rate limit holds it |

### The rows file

`host/vllm-rows` holds vLLM's rows, one a model the server can serve, each the model and its server
flags, named by the pin (`VLLM_ROWS` in `host/vllm.env`). The pin names each flavor's default row,
`VLLM_MODEL_CUDA`'s on the GB10s and `VLLM_MODEL_ROCM`'s on the Framework;
`VLLM_MODEL=<row id> host/engines vllm update` serves another for one run
([Serving another row for one run](#serving-another-row-for-one-run)). The rows are one set for
both flavors, though not every row serves on both: NVFP4 is CUDA's alone.

A row is its id in brackets, then the model's Hugging Face repository, then its settings and its
server flags, over as many lines as read well. The container's command is the row's model,
`--host 0.0.0.0 --port <the row's port>`, then the row's flags, which `docker inspect` shows
([Update](update.md#moving-to-the-pinned-release-or-model)), so a row never names `--host` or
`--port`. An id is the repository's name without its organization, with a suffix for a second row of
the same model; each is unique. No flag or value holds a space or a `#`, since the served command is
compared joined with spaces and `#` starts a comment. A row serves under its repository, which
`/v1/models` lists and requests name in `"model"`, unless it names one other name with
`--served-model-name`; it names exactly one, since vLLM lists every name it is given.

A row's settings are the suite's, which `vllm serve` never sees (`vllm.sh`, `vllm_row`), each a
word `<key>=<value>`: `container=<name>`, the container it serves from, `vllm` when it names none;
`port=<port>`, the host port it publishes on the tailnet address and listens on, 8000 when it
names none; and `image=<repository>`, an image the host builds, served in place of the flavor's
official one at the same tag (`vllm_image`), and never pulled. Rows with distinct containers and
ports serve side by side on one host, one process each; rows that share a container replace each
other in it.

Each row reserves the fraction of the GPU's memory its `--gpu-memory-utilization` names, which
leaves the rest to the host it shares it with. A row that serves alone on its host reserves 0.80.
Rows that serve together on one host each reserve a share, and their fractions' sum is what vLLM
takes of the host, so each set of them is sized for its host. A row that sizes its KV cache in bytes
(`--kv-cache-memory-bytes`) keeps its fraction, and vLLM takes the bytes in place of what the
fraction would leave the cache. Every row serves sequences of 8192 tokens, as each of llama.cpp's
slots does, except the agent rows, which serve the agent's 131,072. The model's own generation
config sets its sampling (vLLM's default, `--generation-config auto`).

Gemma 4's rows hold 4 sequences, mirroring llama.cpp's 4 slots, except the standing rows, which hold
the count their cells met the floors at. They keep a BF16 KV cache: the NVFP4 checkpoints declare a
static FP8 one but ship no calibrated k/v scales, so vLLM would quantize it with a scale of 1.0, and
every Gemma 4 row matches the NVFP4 rows. They use Gemma 4's own reasoning and tool-call parsers.
Their vision encoder loads (no `--language-model-only`), and E4B's and 12B's audio encoder too: vLLM
allows every modality the model has without `--limit-mm-per-prompt`.

### Each row's reasons

- `gemma-4-26B-A4B-NVFP4`: the `cuda` flavor's default: Gemma 4 26B-A4B, MoE, NVIDIA's NVFP4. The
  anchors A' and B', and vision.
- `gemma-4-26B-A4B-NVFP4-flashinfer`: the FlashInfer diagnostic: the pin's row on FlashInfer
  attention, text-only. Without a backend named, vLLM forces Triton for Gemma 4's mixed head sizes
  on the GB10, where FA4 isn't available; `--language-model-only` leaves the vision encoder out,
  so only the text model's attention runs.
- `gemma-4-26B-A4B-NVFP4-marlin`: the Marlin MoE diagnostic: the pin's row on Marlin's kernels for
  the NVFP4 experts. Without a backend named, vLLM v0.32.0 chooses `FLASHINFER_CUTLASS` for them
  on the GB10's SM121, out of the backends its journal lists, `MARLIN` among them; Marlin is the
  fallback in vLLM's own list, a weight-only kernel that runs the activations in 16 bits. The row
  asks whether the MoE kernel explains vLLM's slow NVFP4 decode, so only the MoE backend changes.
- `gemma-4-26B-A4B-it`: Gemma 4 26B-A4B, MoE, Google's BF16, with its vision encoder: the MoE shape
  in a format ROCm serves, where the NVFP4 rows are CUDA's alone. The anchors and vision on the
  Framework.
- `gemma-4-E4B-it`: Gemma 4 E4B, dense small, BF16.
- `gemma-4-E4B-it-qat-w4a16-ct`: Gemma 4 E4B, Google's quantization-aware trained w4a16: the
  quantization pair beside BF16.
- `gemma-4-12B-it-qat-w4a16-ct`: Gemma 4 12B, dense mid, Google's QAT w4a16.
- `Gemma-4-31B-IT-NVFP4`: Gemma 4 31B, dense large, NVIDIA's NVFP4; it declares the static FP8 KV
  cache too.
- `gemma-4-31B-it-qat-w4a16-ct`: Gemma 4 31B, dense large, Google's QAT w4a16: the dense large
  shape in a format ROCm serves.
- `granite-embedding-english-r2`: IBM's granite-embedding-english-r2, BF16, served for
  `/v1/embeddings` only: vLLM's pooling runner, which its architecture selects anyway, named so the
  row says what it serves. A ModernBERT encoder with heads of 64, whose encoder-only attention runs
  on `FLASH_ATTN` on the GB10's SM121. 16 sequences, one a stream of the embedding cell's 16. No
  parsers: it generates nothing.
- `gpt-oss-120b`: OpenAI's gpt-oss-120b in its native MXFP4, the `rocm` flavor's default, at 16
  sequences, mirroring llama.cpp's 16-slot section: its anchor-load cells and the concurrency sweep
  run on this one start. Its KV cache stays the checkpoint's (BF16), and its parsers are gpt-oss's:
  `openai_gptoss` for the reasoning, which vLLM would choose for gpt-oss anyway, and `openai` for
  the tool calls.
- `gpt-oss-120b-agent`: gpt-oss-120b for the agent (spike-model-layout's agent-vllm task,
  spike-model-layout's docs/findings/agent-vllm.md): the gpt-oss-120b row at the agent's sessions,
  131,072 tokens each. Its KV cache stays the checkpoint's (BF16), sized by the 0.80, and no
  attention or MoE backend is named, so vLLM chooses its own. It holds 8 at once, the highest level
  of the agent sweep at which it met the agent's floor (an ITL median of at most 100 ms; agent-vllm
  F, "Meets the floor through"), set by spike-model-layout's vllm-layout task: past 8 a session
  queues rather than slowing the others.

### The standing rows

The capability rows (spike-model-layout's capability-vllm task, spike-model-layout's
docs/findings/capability-vllm.md), placed by its vllm-layout task: vision on 8000, audio on 8001,
embedding on 8002, each in its own container on its own port at its own fraction. Each serves
sequences of 8192 tokens, and names no attention or MoE backend, so vLLM chooses its own and the
start log records it.

vllm-layout keeps the purposes apart by placement. The standing layout: gb10-1 serves the agent
(`gpt-oss-120b-agent-fp8`) alone; gb10-2 serves vision alone; the Framework serves audio and
embedding, the embedding rate-limited by the gateway. On gb10-2 audio missed its floor beside
vision at every pair level, 2 to 8 streams each (an RTFx median of 2.86 to 3.36 against 5), while
vision met its own at every pair but 8 + 8; on the Framework audio held beside embedding sent at a
constant 8.4 and 34 requests a second (RTFx 6.43 and 5.84), and missed beside it run flat out at
16 streams (2.44). The rows file has no list of a host's standing rows: these are the rows each
host stands on.

Each standing row serves under its purpose alias, its one name, for spike-model-gateway's
agentgateway, whose per-purpose routes pass requests through unchanged (spike-model-gateway's
docs/findings/agentgateway.md), so a request names the alias in `"model"`. What each admits in
flight and how it schedules is from spike-model-gateway's docs/findings/priority.md.

- `gpt-oss-120b-agent-fp8`: the agent row on an FP8 KV cache (`fp8`, which vLLM reads as e4m3 on
  CUDA), sized in bytes to hold llama.cpp's agent-only pool of 1,179,648 tokens: 32993476982
  bytes, about 30.73 GiB. The bytes size the cache in place of the 0.80, which the row keeps for
  the rest. No backend is named, so the start log records the attention backend vLLM chooses for
  gpt-oss's sinks on an FP8 cache. It holds 12 at once, the highest level at which it met the
  agent's floor (agent-vllm F), set by vllm-layout as the BF16 row's cap is. It serves under its
  purpose alias, `agent`. It admits 24 in flight, running and waiting, twice its cap, and answers
  503 past that (`--max-num-queued-reqs`, counted in the API server), so the gateway can send what
  a full row refuses to its overflow where vLLM would otherwise queue without bound; and it
  schedules by each request's priority, lower first, arrival breaking ties, so the gateway can rank
  its keys' work.
- `gemma-4-26B-A4B-NVFP4-vision-gb10`: gb10-2's vision: Gemma 4 26B-A4B in NVIDIA's NVFP4, 0.40,
  gb10-2's one row. It holds 16 at once: alone on gb10-2 it met vision's floor (a request latency
  median of at most 10 s) at 16 streams (9.64 s; vllm-layout's cell
  vllm-layout-g2-vision-capacity), the row's cap. It serves under its purpose alias, `vision`. It
  admits 32 in flight, twice its cap, answers 503 past that, and schedules by priority, as the
  agent row does.
- `gemma-4-E4B-it-audio-framework`: the Framework's audio: Gemma 4 E4B, BF16, 0.18, from the audio
  image ([The audio image](setup.md#the-audio-image)), since the official ROCm image ships none of
  the audio extra's decoders, and every audio request on it returns 500. The host builds the
  image, at the pinned release's tag. It holds 4 at once: beside granite at 34 requests a second it
  met audio's floor (an RTFx median of at least 5) at 4 streams (5.84; vllm-layout-fw-pair-a4r34)
  and missed at 8 (4.94; vllm-layout-fw-stress-a8r34). It serves under its purpose alias, `audio`.
  It admits 8 in flight, twice its cap, and answers 503 past that, as the agent row does; it
  schedules first come, first served.
- `granite-embedding-english-r2-framework`: the Framework's embedding: granite-embedding-english-r2,
  on vLLM's pooling runner, 0.03. 128 sequences and 65,536 batched tokens a step: vLLM's default of
  8,192 tokens batches only 16 of the embedding cells' 512-token inputs a step (capability-vllm G),
  and a document pipeline sends more. Alone, its throughput stops rising at 16 streams of 512
  tokens (98,325 prompt tok/s) and holds to 128 (vllm-layout-fw-embed-sweep); beside audio, the
  gateway holds it to at most 34 requests a second, the rate audio was measured to hold beside. It
  serves under its purpose alias, `embedding`. It admits any number in flight: the gateway's rate
  limit is what holds it back, so it has no `--max-num-queued-reqs`.

### The rows on the Framework

The `rocm` flavor serves the rows whose format ROCm runs, every one but the NVFP4 rows, which are
CUDA's alone. Every row served on gfx1151 at v0.32.0, in vllm-strix, but the official image ships no
audio decoder, so an audio request on it returns 500
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
own, so the image stays `vllm/vllm-openai-rocm:v0.34.0` and only the row changes.

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

### Tracing a row for one run

Per-row tracing is off unless `VLLM_TRACE=on` is given for one run, as `VLLM_MODEL` names its row:

```sh
VLLM_TRACE=on VLLM_MODEL=<row id> host/engines vllm update
```

With it, the row's container exports a span per request over OTLP gRPC to the OpenTelemetry
Collector at `VLLM_TRACE_COLLECTOR` (`host/vllm.env`), the one in spike-model-gateway's compose
stack on gb10-2, under the service name `vllm-<alias>`: the alias is the row's
`--served-model-name`, the gateway's name for it (agent, vision, audio, embedding), or the row's id
when it names none. The collector's host is resolved to its tailnet address when the command runs,
never written down (`host/vllm.sh`, `vllm_preflight`). Detailed traces
(`--collect-detailed-traces`) stay off. Without it, a row exports nothing, and since the endpoint is
a server flag, `update` moves a traced row back to untraced, and back again, by restarting it. Use
it only as the command's prefix, never `export` it, as `VLLM_MODEL`. The container path only:
native vLLM, retired, never traces.

### Returning to the default

`update` without `VLLM_MODEL` serves the flavor's default row again:

```sh
host/engines vllm update
```

On gb10-1 it prints `vllm moved from ... to vllm/vllm-openai:v0.34.0 with row gemma-4-26B-A4B-NVFP4
(nvidia/Gemma-4-26B-A4B-NVFP4)`, and on the Framework `... to vllm/vllm-openai-rocm:v0.34.0 with row
gpt-oss-120b (openai/gpt-oss-120b)`, another cold start to record. Use `VLLM_MODEL=...` only as the
command's prefix, never `export` it: an exported one would keep naming its row for every later
command in that shell.

### Adding a row, or moving the default

A new model is a new row in `host/vllm-rows`, and moving a flavor's default is an edit of
`VLLM_MODEL_CUDA` or `VLLM_MODEL_ROCM` in `host/vllm.env`, with the model this guide,
[Setup](setup.md), and [API](api.md) quote to match. A Gemma 4 row takes the default row's parser
flags; a model of another family takes its own. Commit and push; then, on the host, `git pull` and
`host/engines vllm update` ([Update](update.md#moving-to-the-pinned-release-or-model)). A model the
store lacks downloads on its first start, a cold start to record, and an old model stays in the
store until it is deleted ([Uninstall](uninstall.md#deleting-the-model)).
