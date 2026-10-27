# API

The router serves llama.cpp's OpenAI-compatible API on port 8080 of the host's tailnet address.
Each request names its model in `"model"`, and the router forwards it to that model's process; a
model must be loaded first ([Models](models.md)), since the router loads none by itself.

These commands run on the laptop and name the host by its short name, `gb10-1`, as
[Models](models.md#the-hosts-address-on-the-laptop) shows.

## A chat completion

```sh
curl -s "http://gb10-1:8080/v1/chat/completions" -H "Content-Type: application/json" -d '{"model": "ggml-org/gpt-oss-120b-GGUF:MXFP4", "messages": [{"role": "user", "content": "Say hello in one sentence."}]}' | jq '.choices[0].message'
```

It prints the reply's message: its `content`, and gpt-oss's reasoning in `reasoning_content`.
When the model isn't loaded, the router answers with an error instead.

## Health

```sh
curl -s "http://gb10-1:8080/health"
```

`{"status":"ok"}` means the router is up. It says nothing about the models; their status is in
[the model list](models.md#listing-models).

## Models

```sh
curl -s "http://gb10-1:8080/v1/models" | jq '.data[] | {id, status: .status.value}'
```

The OpenAI-compatible model list; in router mode it is the same list as `/models`: the ids clients
send in `"model"`, each with its status.

## Build

```sh
curl -sG "http://gb10-1:8080/props" --data-urlencode "model=ggml-org/gpt-oss-120b-GGUF:MXFP4" --data-urlencode autoload=false | jq -r .build_info
```

The build a loaded model runs, as `b<build>-<commit>`, such as `b11669-620d2225c` at v0.7.0. In
router mode `/props` names its model in the `model` query parameter, and `autoload=false` keeps
the request from loading a model that isn't loaded.

## Metrics

```sh
curl -sG "http://gb10-1:8080/metrics" --data-urlencode "model=ggml-org/gpt-oss-120b-GGUF:MXFP4" --data-urlencode autoload=false
```

A loaded model's Prometheus counters, which the preset's `metrics = true` turns on
([Models](models.md#the-preset)). It takes the same query parameters as `/props`. The counters
run from the model's load: `llamacpp:prompt_tokens_total` and `llamacpp:prompt_seconds_total`
for the prompts the server processed, `llamacpp:tokens_predicted_total` and
`llamacpp:tokens_predicted_seconds_total` for the tokens it generated, and
`llamacpp:requests_processing` for the requests in flight. The seconds are summed per slot, so
tokens over seconds is one request's rate, not the server's total when slots run together.

## Probes of the API surface

One request per surface the spike's consumers need, each against one model, which must be loaded
first ([Models](models.md#loading-a-model)); the router serves one model's request only while it
is loaded. Each prints only what shows whether the surface works. Tools, reasoning, Anthropic
messages, and responses use gpt-oss-120b; vision uses Gemma 4 26B-A4B, embeddings
granite-embedding-english-r2, and transcription Gemma 4 E4B, each by its preset section
([Models](models.md#the-preset)).

### Chat with a tool

```sh
curl -s "http://gb10-1:8080/v1/chat/completions" -H "Content-Type: application/json" -d '{"model": "ggml-org/gpt-oss-120b-GGUF:MXFP4", "messages": [{"role": "user", "content": "What is the weather in Paris right now?"}], "tools": [{"type": "function", "function": {"name": "get_weather", "description": "Get the current weather in a city", "parameters": {"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]}}}]}' | jq '.choices[0] | {finish_reason, tool_calls: .message.tool_calls}'
```

A working surface ends with `finish_reason` `tool_calls` and one call to `get_weather`, its
`arguments` a JSON string naming Paris.

### Reasoning

```sh
curl -s "http://gb10-1:8080/v1/chat/completions" -H "Content-Type: application/json" -d '{"model": "ggml-org/gpt-oss-120b-GGUF:MXFP4", "messages": [{"role": "user", "content": "What is 17 times 23?"}], "reasoning_effort": "high"}' | jq '.choices[0].message | {content, reasoning_content}'
```

The reply's `content` holds the answer, 391, and `reasoning_content` gpt-oss's reasoning apart
from it; `reasoning_effort` reaches gpt-oss's chat template, which sets its reasoning level.

### Anthropic messages with a tool

```sh
curl -s "http://gb10-1:8080/v1/messages" -H "Content-Type: application/json" -H "anthropic-version: 2023-06-01" -d '{"model": "ggml-org/gpt-oss-120b-GGUF:MXFP4", "max_tokens": 1024, "messages": [{"role": "user", "content": "What is the weather in Paris right now?"}], "tools": [{"name": "get_weather", "description": "Get the current weather in a city", "input_schema": {"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]}}]}' | jq '{stop_reason, content}'
```

The router converts an Anthropic Messages request to a chat completion. A working surface ends
with `stop_reason` `tool_use` and a `tool_use` block calling `get_weather` with `input` naming
Paris.

### Responses

```sh
curl -s "http://gb10-1:8080/v1/responses" -H "Content-Type: application/json" -d '{"model": "ggml-org/gpt-oss-120b-GGUF:MXFP4", "input": "Say hello in one sentence."}' | jq '{status, output: [.output[] | {type, content}]}'
```

The router converts a Responses request to a chat completion too. A working surface is
`completed`, with a `reasoning` item and a `message` item whose content holds the reply.

### Vision

The image is llama.cpp's own multimodal test picture at the pinned build, fetched once into the
untracked `.state/`, and sent inline as base64:

```sh
mkdir -p .state/probe
curl -sL -o .state/probe/test-1.jpeg "https://raw.githubusercontent.com/ggml-org/llama.cpp/b11669/tools/mtmd/test-1.jpeg"
base64 -w 0 .state/probe/test-1.jpeg > .state/probe/test-1.b64; jq -n --rawfile img .state/probe/test-1.b64 '{"model": "google/gemma-4-26B-A4B-it-qat-q4_0-gguf:Q4_0", "messages": [{"role": "user", "content": [{"type": "text", "text": "Describe this image in one sentence."}, {"type": "image_url", "image_url": {"url": ("data:image/jpeg;base64," + $img)}}]}]}' | curl -s "http://gb10-1:8080/v1/chat/completions" -H "Content-Type: application/json" -d @- | jq '{content: .choices[0].message.content, usage}'
```

A working surface describes the picture, and `usage.prompt_tokens` counts the image's tokens
beside the text's.

### Embeddings

```sh
curl -s "http://gb10-1:8080/v1/embeddings" -H "Content-Type: application/json" -d '{"model": "mrutkows/granite-embedding-english-r2-GGUF:BF16", "input": ["The quick brown fox jumps over the lazy dog.", "A fast auburn fox leaps over a sleepy hound."]}' | jq '{model, usage, dimensions: [.data[].embedding | length], norms: [.data[].embedding | map(. * .) | add | sqrt]}'
```

A working surface returns one embedding an input, each 768 wide, granite's hidden size, and of
norm 1 to within float rounding. The model doesn't normalize its own output (its
sentence-transformers modules are the encoder and CLS pooling, with no normalization); llama.cpp
normalizes each embedding to unit length by default (`embd_normalize` 2, Euclidean). vLLM
v0.32.0 returns the same model's embeddings unnormalized, of norm about 30
([vLLM's API](../vllm/api.md#embeddings)): a cosine doesn't depend on the norm, and a dot product
does.

### Transcription

The clip is whisper.cpp's 11-second sample of John F. Kennedy's inaugural address, fetched once,
and sent as a multipart upload, as OpenAI's API takes it:

```sh
mkdir -p .state/probe
curl -sL -o .state/probe/jfk.wav "https://raw.githubusercontent.com/ggml-org/whisper.cpp/v1.7.6/samples/jfk.wav"
curl -s "http://gb10-1:8080/v1/audio/transcriptions" -F model=ggml-org/gemma-4-E4B-it-GGUF:Q8_0 -F response_format=json -F file=@.state/probe/jfk.wav | jq .
```

The router converts the upload to a chat completion with the model's own transcription prompt,
and accepts only `response_format` `json`. A working surface returns `text` with the speech: "And
so my fellow Americans, ask not what your country can do for you, ask what you can do for your
country." A model whose projector has no audio encoder answers `The current model does not
support audio input.`
