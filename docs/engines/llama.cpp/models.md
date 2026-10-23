# Models

## The preset

The router serves the models its preset names, `engines/llama-preset/models.ini`, which the
container reads from the clone at `/etc/llama-preset/models.ini`. Each section is one model,
named as clients name it in `"model"`; its keys are `llama-server` arguments without the leading
dashes, and `[*]` holds the keys every model shares. `hf-repo` names the Hugging Face repository
and quantization the router downloads the model from.

| Key | Value | Why |
|---|---|---|
| `n-gpu-layers` (`[*]`) | `all` | Every layer on the GB10's GPU. |
| `dedup-cache-models` (`[*]`) | `true` | Once a model is downloaded, the router lists its preset alone, not the cache entry beside it. |
| `hf-repo` | `ggml-org/gpt-oss-120b-GGUF:MXFP4` | gpt-oss-120b in its native MXFP4, 63.4 GB, ungated, so no token. |
| `parallel` | `4` | 4 slots: four requests decode at once, and a fifth waits. |
| `c` | `32768` | The context, split evenly across the slots: 8192 tokens each. |
| `temp`, `top-p`, `top-k`, `min-p` | `1`, `1`, `0`, `0` | OpenAI's recommended sampling for gpt-oss, temperature 1.0 and top_p 1.0, with the server's other truncations off. |

The context is chosen for the spike's anchor request, 512 tokens in and 256 out: 768 tokens of
the 8192 each slot holds, which leaves room for gpt-oss's chat template, its reasoning, and longer
prompts later. The whole cache costs little: gpt-oss-120b's KV cache is about 36 KiB a token, so
32768 tokens is about 1.1 GiB beside about 59 GiB of weights, on a GB10's 119 GiB.

The router re-reads the preset when asked, without a restart, after the clone is updated with
`git pull`:

```sh
curl -s "http://$(tailscale ip -4):8080/models?reload=1" > /dev/null
```

## The host's address on the laptop

The commands below run on the laptop, against the host's tailnet IPv4 address. Print the address
on the host:

```sh
tailscale ip -4
```

Then, on the laptop, set `GB10` to it, typing the address the host printed in place of
`<tailnet address>`:

```sh
GB10=<tailnet address>
```

## Loading a model

The router starts no model by itself. Load gpt-oss-120b through its API:

```sh
curl -s -X POST "http://$GB10:8080/models/load" -H "Content-Type: application/json" -d '{"model": "ggml-org/gpt-oss-120b-GGUF:MXFP4"}'
```

It answers `{"success":true}` at once and loads in the background. The first load downloads the
model into `/srv/models` before loading it, which takes as long as 63.4 GB takes to download; a
later load reads it from the store. A restart of the container, by an update or a reboot, unloads
every model, so load it again after one.

## Watching the download

On the host, the store grows to about 60 GiB as the files arrive, and the router's log shows the
download and then the load:

```sh
du -sh /srv/models
docker logs --tail 20 llama
```

The model's files land in `/srv/models/models--ggml-org--gpt-oss-120b-GGUF`, in Hugging Face's
cache layout.

## Listing models

```sh
curl -s "http://$GB10:8080/models" | jq '.data[] | {id, status: .status.value}'
```

Each model the router knows is listed with its status: `unloaded`, `loading` (during the download
and the load), or `loaded`, when it answers requests. A load that failed shows `unloaded` with
`"failed": true` in its status; the router's log gives the reason.
