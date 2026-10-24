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

Deleting the model is a typed step, apart from the uninstall. The model is its own directory in
the store, in Hugging Face's cache layout, and its weight files in the shared store at the
cache's root, `/srv/models/blobs`, which its directory links into
([Models](models.md#the-first-download)). Deleting the directory alone leaves the weight files
behind, so first list the shared files its links point to, keeping only paths under
`/srv/models/blobs/`, and read the list:

```sh
find /srv/models/models--nvidia--Gemma-4-26B-A4B-NVFP4/blobs -type l -exec readlink -f {} + | grep '^/srv/models/blobs/' > /tmp/gemma-blobs
cat /tmp/gemma-blobs
```

Then remove those files, the shared store's directories they leave empty, and the model's
directory:

```sh
xargs -r rm -f -- < /tmp/gemma-blobs
find /srv/models/blobs -mindepth 1 -type d -empty -delete
rm -rf /srv/models/models--nvidia--Gemma-4-26B-A4B-NVFP4
rm /tmp/gemma-blobs
```

The shared store is named by content, so a file that another model in it contains byte for byte
is one file, and goes with this model; that model's client downloads it again on its next
start. llama.cpp's models keep their files in their own directories, so this touches none of
them.

The container writes the store as your account, so this needs no `sudo`. The store is llama.cpp's
too, so leave the rest of it; llama.cpp's [Uninstall](../llama.cpp/uninstall.md#deleting-models)
deletes its models and the store itself.
