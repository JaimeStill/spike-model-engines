# Uninstall

## Removing vLLM

On the host, from the clone:

```sh
host/engines vllm uninstall
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

Deleting the model is a typed step, apart from the uninstall. The models hf pre-staged
([Models](models.md#pre-staging-models-with-hf)) are deleted with hf, as llama.cpp's are
([Deleting models](../llama.cpp/uninstall.md#deleting-models)).

The pinned model, which the container downloaded, is deleted by hand. The model is its own
directory in the store, in Hugging Face's cache layout, and its weight files in the shared store
at the cache's root, `/srv/models/blobs`, which its directory links into
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

## Removing native vLLM

On the host, from the clone:

```sh
host/engines vllm-native uninstall
```

`uninstall` stops `vllm-server` when it runs, disables it when it is enabled, and removes
everything native vLLM keeps under `/opt/vllm`: every release with the `current` link, the row
file, uv's Python, and `/opt/vllm/cache`, uv's cache and the compile caches. It keeps the model
store, `/srv/models`, as the container's uninstall does, and the container's compile cache,
`~/.cache/vllm`, which the container's uninstall removes. A second run changes nothing and says
so. Every run ends by saying the architect's root steps stay: `/opt/vllm`, the unit, and its
sudoers rule, which the next section removes.

### Removing the native root steps

After `uninstall`, the architect removes the three root steps of
[Setup](setup.md#1-the-architects-root-steps), each with a root step: the sudoers rule, the unit
(and systemd's copy of it), and the empty `/opt/vllm`:

```sh
sudo rm /etc/sudoers.d/vllm-server
sudo rm /etc/systemd/system/vllm-server.service
sudo systemctl daemon-reload
sudo rmdir /opt/vllm
```

`rmdir` fails when anything is left in `/opt/vllm`; `host/engines vllm-native uninstall` removes
it while the rule is still in place. Then `systemctl status vllm-server` says `Unit
vllm-server.service could not be found.`
