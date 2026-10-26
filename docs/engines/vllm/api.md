# API

The server serves vLLM's OpenAI-compatible API on port 8000 of the host's tailnet address. It
serves one model, its row's ([Models](models.md#the-rows)), so every request names that model in
`"model"`: at the pin's default row, `nvidia/Gemma-4-26B-A4B-NVFP4`.

These commands run on the laptop and name the host by its short name, `gb10-1`, which Tailscale's
MagicDNS resolves to its tailnet address (llama.cpp's
[Models](../llama.cpp/models.md#the-hosts-address-on-the-laptop)).

v0.32.0 no longer allows every origin for cross-origin requests by default, so a browser page on
another origin can't call the server. `curl` and other clients that aren't browsers aren't
affected.

## A chat completion

```sh
curl -s "http://gb10-1:8000/v1/chat/completions" -H "Content-Type: application/json" -d '{"model": "nvidia/Gemma-4-26B-A4B-NVFP4", "messages": [{"role": "user", "content": "Say hello in one sentence."}], "chat_template_kwargs": {"enable_thinking": true}}' | jq '.choices[0].message'
```

It prints the reply's message: its `content`, and Gemma 4's reasoning in `reasoning`, which the
server's `gemma4` reasoning parser separates. Gemma 4 reasons only when asked, which
`"chat_template_kwargs": {"enable_thinking": true}` does; without it, `reasoning` is `null`.

## Health

```sh
curl -s -o /dev/null -w '%{http_code}\n' "http://gb10-1:8000/health"
```

`200` means the server is up and its engine answers. Until the cold start finishes, it prints
`000`, since nothing answers on the port yet.

## Models

```sh
curl -s "http://gb10-1:8000/v1/models" | jq '.data[] | {id, max_model_len}'
```

The OpenAI-compatible model list: the one model the server serves, by the id clients send in
`"model"`, and the tokens a sequence holds, 8192 in every row. It shows which row's model the
server serves now.

## Version

```sh
curl -s "http://gb10-1:8000/version"
```

The vLLM version the server runs, `{"version":"0.32.0"}` at the pin; it matches `VLLM_RELEASE` in
`engines/vllm.env`, without the `v`.

## Metrics

```sh
curl -s "http://gb10-1:8000/metrics" | grep -E '^vllm:(prompt_tokens_total|generation_tokens_total|num_requests_running)'
```

The server's Prometheus counters, which vLLM serves without a flag. They run from the container's
start: `vllm:prompt_tokens_total` for the prompt tokens the server processed,
`vllm:generation_tokens_total` for the tokens it generated, and `vllm:num_requests_running` for
the requests in flight. The full list, without the `grep`, adds latency histograms such as
`vllm:time_to_first_token_seconds` and `vllm:inter_token_latency_seconds`.

## Probes of the API surface

One request per surface the spike's consumers need, each against one model, as
[llama.cpp's probes](../llama.cpp/api.md#probes-of-the-api-surface) are. The server serves one
row at a time, so each probe needs its row served first
([Models](models.md#serving-another-row-for-one-run)), and [Models](#models) confirms which.
Each prints only what shows whether the surface works. Tools, reasoning, Anthropic messages, and
responses use gpt-oss-120b (`VLLM_MODEL=gpt-oss-120b`); vision uses Gemma 4 26B-A4B, the pin's
default row; and embeddings granite-embedding-english-r2
(`VLLM_MODEL=granite-embedding-english-r2`). Transcription is recorded on paper.

### Chat with a tool

```sh
curl -s "http://gb10-1:8000/v1/chat/completions" -H "Content-Type: application/json" -d '{"model": "openai/gpt-oss-120b", "messages": [{"role": "user", "content": "What is the weather in Paris right now?"}], "tools": [{"type": "function", "function": {"name": "get_weather", "description": "Get the current weather in a city", "parameters": {"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]}}}]}' | jq '.choices[0] | {finish_reason, tool_calls: .message.tool_calls}'
```

A working surface ends with `finish_reason` `tool_calls` and one call to `get_weather`, its
`arguments` a JSON string naming Paris. The row's `--enable-auto-tool-choice --tool-call-parser
openai` turn gpt-oss's own tool-call format into OpenAI tool calls.

### Reasoning

```sh
curl -s "http://gb10-1:8000/v1/chat/completions" -H "Content-Type: application/json" -d '{"model": "openai/gpt-oss-120b", "messages": [{"role": "user", "content": "What is 17 times 23?"}], "reasoning_effort": "high"}' | jq '.choices[0].message | {content, reasoning}'
```

The reply's `content` holds the answer, 391, and `reasoning` gpt-oss's reasoning apart from it,
which the row's `openai_gptoss` reasoning parser separates; vLLM names the field `reasoning`, where
llama.cpp names it `reasoning_content`. `reasoning_effort` sets gpt-oss's reasoning level.

### Anthropic messages with a tool

```sh
curl -s "http://gb10-1:8000/v1/messages" -H "Content-Type: application/json" -H "anthropic-version: 2023-06-01" -d '{"model": "openai/gpt-oss-120b", "max_tokens": 1024, "messages": [{"role": "user", "content": "What is the weather in Paris right now?"}], "tools": [{"name": "get_weather", "description": "Get the current weather in a city", "input_schema": {"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]}}]}' | jq '{stop_reason, content}'
```

v0.32.0 serves Anthropic's Messages API at `/v1/messages` beside the OpenAI one. A working
surface ends with `stop_reason` `tool_use` and a `tool_use` block calling `get_weather` with
`input` naming Paris.

### Responses

```sh
curl -s "http://gb10-1:8000/v1/responses" -H "Content-Type: application/json" -d '{"model": "openai/gpt-oss-120b", "input": "Say hello in one sentence."}' | jq '{status, output: [.output[] | {type, content}]}'
```

For gpt-oss, vLLM serves Responses through gpt-oss's own Harmony format rather than through its
chat completions. A working surface is `completed`, with a `reasoning` item and a `message` item
whose content holds the reply.

### Vision

The image is llama.cpp's multimodal test picture, the one its probe sends, fetched once into the
untracked `.state/` (the `mkdir` and `curl` are llama.cpp's; skip them when it is there), and
sent inline as base64:

```sh
mkdir -p .state/probe
curl -sL -o .state/probe/test-1.jpeg "https://raw.githubusercontent.com/ggml-org/llama.cpp/b11669/tools/mtmd/test-1.jpeg"
base64 -w 0 .state/probe/test-1.jpeg > .state/probe/test-1.b64; jq -n --rawfile img .state/probe/test-1.b64 '{"model": "nvidia/Gemma-4-26B-A4B-NVFP4", "messages": [{"role": "user", "content": [{"type": "text", "text": "Describe this image in one sentence."}, {"type": "image_url", "image_url": {"url": ("data:image/jpeg;base64," + $img)}}]}]}' | curl -s "http://gb10-1:8000/v1/chat/completions" -H "Content-Type: application/json" -d @- | jq '{content: .choices[0].message.content, usage}'
```

A working surface describes the picture, and `usage.prompt_tokens` counts the image's tokens
beside the text's. The default row loads the vision encoder; the FlashInfer diagnostic's row,
`--language-model-only`, doesn't, and refuses the image.

### Embeddings

```sh
curl -s "http://gb10-1:8000/v1/embeddings" -H "Content-Type: application/json" -d '{"model": "ibm-granite/granite-embedding-english-r2", "input": ["The quick brown fox jumps over the lazy dog.", "A fast auburn fox leaps over a sleepy hound."]}' | jq '{model, usage, dimensions: [.data[].embedding | length], norms: [.data[].embedding | map(. * .) | add | sqrt]}'
```

The row runs vLLM's pooling runner, which serves `/v1/embeddings` and no chat. A working surface
returns one embedding an input, each 768 wide, granite's hidden size, and of norm about 30, not 1:
on gb10-1, 30.43 and 30.48 ([bench-gb10-container](../../findings/bench-gb10-container.md#embeddings)).
granite ships no `Normalize` module, its sentence-transformers modules being the encoder and CLS
pooling, and v0.32.0 returns its embeddings unnormalized, where llama.cpp normalizes each to unit
length by default. A cosine doesn't depend on the norm and a dot product does, so a client that
takes a dot product as a cosine normalizes vLLM's embeddings first.

### Transcription, on paper

v0.32.0 serves `/v1/audio/transcriptions`, but only for models that implement speech-to-text:
its supported-models list names Whisper, Granite Speech, and Voxtral among them, and not Gemma 4,
whose model class (`Gemma4ForConditionalGeneration`) doesn't. Gemma 4 E4B's audio reaches vLLM
through chat instead, as an `input_audio` part, which the finding's ASR cells send. No probe runs.
