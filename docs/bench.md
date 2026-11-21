# The benchmark cells

The load, sizing, and requests of each GuideLLM scenario in [`bench/`](../bench/), one section per
file; each file's header points at its section with a `See` line, and its inline `See` lines at the
shared sections. GuideLLM runs from the bench environment ([Tools](tools.md#the-bench-environment)).

## How a cell is run

Every cell runs from the repository root. The target is the server's URL, which the architect sets
in `GUIDELLM__SPEC__BACKEND__TARGET`, so no address is committed. The anchor cells name their model
and tokenizer in the file. The engine-neutral cells name neither: the model, its tokenizer, and the
JSON's path are given on the command line, and the target in `GUIDELLM__SPEC__BACKEND__TARGET`, so
one file serves both engines and every model it fits
([bench-gb10-container](findings/bench-gb10-container.md), "Method"). The vision cells need
GuideLLM's vision extra and the audio cells its audio extra
([host practices](host-practices.md#running-on-every-host), "GuideLLM's extras").

## Output tokens

GuideLLM sends max_tokens (to llama.cpp's router) or max_completion_tokens (to vLLM and the
engine-neutral cells) with ignore_eos whenever `output_tokens` is set, so every request generates
its full count.

## Tokenizers

The router serves GGUF files, which carry no tokenizer GuideLLM reads: the prompt is cut to its 512
tokens by the model's upstream tokenizer, fetched from Hugging Face. On vLLM the served checkpoint
ships its own tokenizer, which cuts the prompt to its 512 tokens.

## Gemma 4's reasoning

Gemma 4 reasons only when its chat template is asked to, so every request to a Gemma 4 text cell
asks (`chat_template_kwargs.enable_thinking`), as gpt-oss reasons in anchor cells A and B: the 256
tokens are reasoning first, then the reply. The shape cells ask as vLLM's anchors A' and B' do.

## Vision requests

The two sources are read side by side, one row of each a request: the text, cut to its 200 tokens
by the tokenizer, and the image, which carries the request's output tokens. GuideLLM sends
max_completion_tokens with ignore_eos, so every request generates its full 64.

## Audio requests

The audio cells' requests, shared by [audio-a](#audio-a) and [audio-b](#audio-b):

- **The reply cap.** A transcript is as long as its clip, so no request sets output tokens or
  ignore_eos; `max_tokens` caps each reply, sent as max_completion_tokens, should the model not
  stop.
- **The sources.** The two sources are read side by side, one row of each a request, and the run
  stops when either runs out. Source 0 is the prompt, from Gemma 4's card ("Transcribe the
  following speech segment in {LANGUAGE} into {LANGUAGE} text. ... Only output the transcription,
  with no newlines."), once a request. Source 1 is hf-internal-testing/librispeech_asr_dummy, 73
  clips from LibriSpeech's clean validation split, about 9 MB fetched once from Hugging Face; the
  32 the cells read run 1.7 to 29.4 s, within the card's 30-second audio limit.
- **The columns.** Only the prompt and the clip: LibriSpeech's own text column is the reference
  transcript, which the mapper's defaults would otherwise send as the prompt.
- **The encoding.** Every clip is re-encoded as 16 kHz mono WAV, which both engines' input_audio
  accepts; the source is FLAC, which llama.cpp's doesn't.

## Levels

A level of the sweep stops sending at 60 s; the requests then in flight are cancelled and counted
incomplete, so each level's figures cover its 60 s.

## anchor-a

Anchor cell A: gpt-oss-120b MXFP4 on the llama.cpp router, 1 stream sending 8 requests back to
back, each 512 synthetic prompt tokens and exactly 256 output tokens
([llama-gb10-container](findings/llama-gb10-container.md)).

## anchor-b

Anchor cell B: gpt-oss-120b MXFP4 on the llama.cpp router, 4 streams sending 32 requests in all, 8
each back to back, each 512 synthetic prompt tokens and exactly 256 output tokens: one stream per
slot of the preset's 4 ([llama-gb10-container](findings/llama-gb10-container.md)).

## vllm-anchor-a

Anchor cell A': Gemma 4 26B-A4B NVFP4 on vLLM, 1 stream sending 8 requests back to back, each 512
synthetic prompt tokens and exactly 256 output tokens
([vllm-gb10-container](findings/vllm-gb10-container.md)).

## vllm-anchor-b

Anchor cell B': Gemma 4 26B-A4B NVFP4 on vLLM, 4 streams sending 32 requests in all, 8 each back to
back, each 512 synthetic prompt tokens and exactly 256 output tokens: one stream per sequence of
the server's `--max-num-seqs 4` ([vllm-gb10-container](findings/vllm-gb10-container.md)).

## shape-a

Shape cell A: one Gemma 4 model, 1 stream sending 8 requests back to back, each 512 synthetic
prompt tokens and exactly 256 output tokens: anchor cell A's load. Engine-neutral, so one file
serves both engines and every Gemma 4 shape, and the quantization pairs.

## shape-b

Shape cell B: one Gemma 4 model, 4 streams sending 32 requests in all, 8 each back to back, each
512 synthetic prompt tokens and exactly 256 output tokens: anchor cell B's load, one stream per
slot of the preset's 4 (vLLM: per sequence of its 4). Engine-neutral, like shape-a.

## shape-large-a

Large shape cell A: the dense large model (gemma-4-31B), 1 stream sending 4 requests back to back,
each 512 synthetic prompt tokens and exactly 256 output tokens: anchor cell A's load halved, since
a dense 31B decodes slowly enough that 8 requests would cost the session more than they tell.
Engine-neutral, like shape-a.

## shape-large-b

Large shape cell B: the dense large model (gemma-4-31B), 4 streams sending 16 requests in all, 4
each back to back, each 512 synthetic prompt tokens and exactly 256 output tokens: anchor cell B's
load halved, one stream per slot of the preset's 4 (vLLM: per sequence of its 4). Engine-neutral,
like shape-a.

## sweep

Concurrency sweep: gpt-oss-120b on 16 slots, 512 synthetic prompt tokens and exactly 256 output
tokens a request, at 1, 4, 16, and 32 streams, each level sending requests back to back for 60 s
([Levels](#levels)): four benchmarks in one run, one JSON. At 32 streams half the requests wait
for a slot, which is what the sweep records past the slots. Engine-neutral.

## vision-a

Vision cell A: gemma-4-26B-A4B, 1 stream sending 8 requests back to back, each one synthetic 720p
JPEG (1280 x 720, GuideLLM's default gradient at quality 85, different in every request) beside
200 synthetic text tokens, and exactly 64 output tokens ([Vision requests](#vision-requests)).
Engine-neutral; it needs GuideLLM's vision extra.

## vision-b

Vision cell B: gemma-4-26B-A4B, 4 streams sending 32 requests in all, 8 each back to back, each one
synthetic 720p JPEG (1280 x 720, GuideLLM's default gradient at quality 85, different in every
request) beside 200 synthetic text tokens, and exactly 64 output tokens: one stream per slot of
the preset's 4 ([Vision requests](#vision-requests)). Engine-neutral; it needs GuideLLM's vision
extra.

## audio-a

ASR cell A: gemma-4-E4B's audio through chat, 1 stream sending 8 requests back to back. Each
request is one LibriSpeech clip with the model card's transcription prompt, and the reply ends
when the model stops, at most 256 tokens ([Audio requests](#audio-requests)). Engine-neutral; it
needs GuideLLM's audio extra.

## audio-b

ASR cell B: gemma-4-E4B's audio through chat, 4 streams sending 32 requests in all, 8 each back to
back, one stream per slot of the preset's 4. Each request is one LibriSpeech clip with the model
card's transcription prompt, and the reply ends when the model stops, at most 256 tokens
([Audio requests](#audio-requests)). Engine-neutral; it needs GuideLLM's audio extra.

## embed

Embedding cell: granite-embedding-english-r2, 512 synthetic tokens a request to /v1/embeddings, at
1 stream and then 16, each level for 30 s: two benchmarks in one run, one JSON. An embedding has no
output tokens, streaming, TTFT, or ITL, so the figures are request latency and throughput.
Engine-neutral.
