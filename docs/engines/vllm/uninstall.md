# Uninstall

## Removing vLLM

On the host, from the clone:

```sh
host/engines vllm uninstall
```

`uninstall` removes the `vllm` container, every vLLM image of either flavor, `vllm/vllm-openai`'s
and `vllm/vllm-openai-rocm`'s, and the compile cache, `~/.cache/vllm`, and keeps the model store,
`/srv/models`, so a later install serves the same model without downloading it again. A second run
changes nothing and says so. It reads no flavor, so it runs the same on every host.

With `vllm` gone, llama.cpp's install and update no longer refuse. Start `llama` again, when it
was stopped for vLLM:

```sh
docker start llama
```

Its router serves no model until one is loaded, since it runs with `--no-models-autoload`; load
one through its API, as [llama.cpp's Models](../llama.cpp/models.md#loading-a-model) does.

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

## The Framework

On the Framework, `host/engines vllm uninstall` removes the `vllm` container and the ROCm image of
every release, `vllm/vllm-openai-rocm:<release>`, as on gb10-1 it removes the CUDA image's
([Removing vLLM](#removing-vllm)), and the compile cache, `~/.cache/vllm`. It keeps `/srv/models`;
with `vllm` gone, llama.cpp's install and update no longer refuse, and `docker start llama` brings
back a `llama` stopped for vLLM. Its router serves no model until one is loaded, since it runs
with `--no-models-autoload`:

```sh
curl -s -X POST "http://$(tailscale ip -4):8080/models/load" -H "Content-Type: application/json" -d '{"model": "ggml-org/gpt-oss-120b-GGUF:MXFP4"}'
```

[llama.cpp's Models](../llama.cpp/models.md#loading-a-model) loads any other.

Every model vLLM serves on the Framework was staged through hf
([Models](models.md#on-the-framework)), so each is deleted with hf, as llama.cpp's are ([Deleting
models](../llama.cpp/uninstall.md#deleting-models)), such as `openai/gpt-oss-120b`'s repository,
which llama.cpp's GGUF of the same model doesn't share.

vLLM added no root step on the Framework ([Setup](setup.md#1-the-root-steps-already-in-place)). The
root steps it uses, the `docker` group, the ufw rule for port 8000, the page-cache rule, the store,
and the GTT ceiling, are llama.cpp's, and go with [Removing the Framework's root
steps](../llama.cpp/uninstall.md#removing-the-frameworks-root-steps), once neither engine is
installed.

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
