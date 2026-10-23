# Uninstall

## Removing vLLM

On the host, from the clone:

```sh
engines/engines vllm uninstall
```

`uninstall` removes the `vllm` container, every vLLM image, and the compile cache,
`~/.cache/vllm`, and keeps the model store, `/srv/models`, so a later install serves the same
model without downloading it again. A second run changes nothing and says so.

With `vllm` gone, llama.cpp's install and update no longer refuse. Start `llama` again, when it
was stopped for vLLM:

```sh
docker start llama
```

## Deleting the model

Deleting the model is a typed step, apart from the uninstall. It is one directory in the store,
in Hugging Face's cache layout:

```sh
rm -rf /srv/models/models--nvidia--Gemma-4-26B-A4B-NVFP4
```

The container writes the store as your account, so this needs no `sudo`. The store is llama.cpp's
too, so leave the rest of it; llama.cpp's [Uninstall](../llama.cpp/uninstall.md#deleting-models)
deletes its models and the store itself.
