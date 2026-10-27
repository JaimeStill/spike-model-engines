# Uninstall

## Removing llama.cpp

On the host, from the clone:

```sh
host/engines llama uninstall
```

`uninstall` removes the `llama` container and every llama.cpp image, and keeps the model store,
`/srv/models`, so a later install serves the same models without downloading them again. A
second run changes nothing and says so.

## Deleting models

Deleting a model is a typed step, apart from the uninstall. Each model is one directory in the
store, in Hugging Face's cache layout.

A model hf pre-staged ([Models](models.md#pre-staging-models-with-hf)) keeps its files in the
shared store, `/srv/models/blobs`, which hf tracks, so delete it with hf, from the clone. Name it
as `model/<repository>`; the first command shows what goes, and the second deletes it:

```sh
MISE_ENV=host HF_HUB_CACHE=/srv/models mise exec -- hf cache rm model/google/gemma-4-31B-it-qat-q4_0-gguf --dry-run
MISE_ENV=host HF_HUB_CACHE=/srv/models mise exec -- hf cache rm model/google/gemma-4-31B-it-qat-q4_0-gguf -y
```

hf removes the model's directory and every file of the shared store no other model in it uses.
The same command deletes vLLM's pre-staged models.

A model the router downloaded itself keeps its files in its own directory; delete gpt-oss-120b
with:

```sh
rm -rf /srv/models/models--ggml-org--gpt-oss-120b-GGUF
```

The container writes the store as your account, so this needs no `sudo`. List what is left with:

```sh
ls /srv/models
```

Once vLLM has fetched its model, the store also holds vLLM's model directory, the shared store
its weight files live in, `blobs/`, and `CACHEDIR.TAG`; `ls` hides the client's `.locks/`
([vLLM's Models](../vllm/models.md#the-first-download)).

To remove the store itself, with anything left in it, undo its creation with a root step. This
also deletes vLLM's model and the shared `/srv/models/blobs`:

```sh
sudo rm -rf /srv/models
```

## Removing native llama.cpp

On the host, from the clone:

```sh
host/engines llama-native uninstall
```

`uninstall` stops `llama-router` when it runs, disables it when it is enabled, and removes every
build under `/opt/llama.cpp` with the `current` and `preset` links. It keeps the model store,
`/srv/models`, as the container's uninstall does. A second run changes nothing and says so. Every
run ends by saying the architect's root steps stay: `/opt/llama.cpp`, the unit, and its sudoers
rule, which the next section removes.

### Removing the native root steps

After `uninstall`, the architect removes the three root steps of
[Setup](setup.md#1-the-architects-root-steps), each with a root step: the sudoers rule, the unit
(and systemd's copy of it), and the empty `/opt/llama.cpp`:

```sh
sudo rm /etc/sudoers.d/llama-router
sudo rm /etc/systemd/system/llama-router.service
sudo systemctl daemon-reload
sudo rmdir /opt/llama.cpp
```

`rmdir` fails when anything is left in `/opt/llama.cpp`, such as a build from before an uninstall;
`host/engines llama-native uninstall` removes it while the rule is still in place. Then
`systemctl status llama-router` says `Unit llama-router.service could not be found.`
