# Uninstall

## Removing llama.cpp

On the host, from the clone:

```sh
engines/engines llama uninstall
```

`uninstall` removes the `llama` container and every llama.cpp image, and keeps the model store,
`/srv/models`, so a later install serves the same models without downloading them again. A
second run changes nothing and says so.

## Deleting models

Deleting a model is a typed step, apart from the uninstall. Each model is one directory in the
store, in Hugging Face's cache layout; delete gpt-oss-120b with:

```sh
rm -rf /srv/models/models--ggml-org--gpt-oss-120b-GGUF
```

The container writes the store as your account, so this needs no `sudo`. List what is left with:

```sh
ls /srv/models
```

To remove the store itself, with anything left in it, undo its creation with a root step:

```sh
sudo rm -rf /srv/models
```
