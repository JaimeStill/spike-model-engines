# API

The router serves llama.cpp's OpenAI-compatible API on port 8080 of the host's tailnet address.
Each request names its model in `"model"`, and the router forwards it to that model's process; a
model must be loaded first ([Models](models.md)), since the router loads none by itself.

These commands run on the laptop and name the host by its short name, as
[Models](models.md#the-hosts-address-on-the-laptop) shows; on gb10-2, put `gb10-2` in place of
`gb10-1`.

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

The build a loaded model runs, as `b<build>-<commit>`, such as `b11669-620d2225c`. In router mode
`/props` names its model in the `model` query parameter, and `autoload=false` keeps the request
from loading a model that isn't loaded.

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
