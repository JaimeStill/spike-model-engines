# API

The server serves vLLM's OpenAI-compatible API on port 8000 of the host's tailnet address. It
serves one model, so every request names that model in `"model"`: `nvidia/Gemma-4-26B-A4B-NVFP4`.

These commands run on the laptop, with `GB10` set to the host's tailnet address as llama.cpp's
[Models](../llama.cpp/models.md#the-hosts-address-on-the-laptop) shows:

```sh
GB10=<tailnet address>
```

v0.32.0 no longer allows every origin for cross-origin requests by default, so a browser page on
another origin can't call the server. `curl` and other clients that aren't browsers aren't
affected.

## A chat completion

```sh
curl -s "http://$GB10:8000/v1/chat/completions" -H "Content-Type: application/json" -d '{"model": "nvidia/Gemma-4-26B-A4B-NVFP4", "messages": [{"role": "user", "content": "Say hello in one sentence."}], "chat_template_kwargs": {"enable_thinking": true}}' | jq '.choices[0].message'
```

It prints the reply's message: its `content`, and Gemma 4's reasoning in `reasoning`, which the
server's `gemma4` reasoning parser separates. Gemma 4 reasons only when asked, which
`"chat_template_kwargs": {"enable_thinking": true}` does; without it, `reasoning` is `null`.

## Health

```sh
curl -s -o /dev/null -w '%{http_code}\n' "http://$GB10:8000/health"
```

`200` means the server is up and its engine answers. Until the cold start finishes, it prints
`000`, since nothing answers on the port yet.

## Models

```sh
curl -s "http://$GB10:8000/v1/models" | jq '.data[] | {id, max_model_len}'
```

The OpenAI-compatible model list: the one model the server serves, by the id clients send in
`"model"`, and the tokens a sequence holds, 8192.

## Version

```sh
curl -s "http://$GB10:8000/version"
```

The vLLM version the server runs, `{"version":"0.32.0"}` at the pin; it matches `VLLM_RELEASE` in
`engines/vllm.env`, without the `v`.

## Metrics

```sh
curl -s "http://$GB10:8000/metrics" | grep -E '^vllm:(prompt_tokens_total|generation_tokens_total|num_requests_running)'
```

The server's Prometheus counters, which vLLM serves without a flag. They run from the container's
start: `vllm:prompt_tokens_total` for the prompt tokens the server processed,
`vllm:generation_tokens_total` for the tokens it generated, and `vllm:num_requests_running` for
the requests in flight. The full list, without the `grep`, adds latency histograms such as
`vllm:time_to_first_token_seconds` and `vllm:inter_token_latency_seconds`.
