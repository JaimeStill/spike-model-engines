# Uninstall

## Removing llama.cpp

On the host, from the clone:

```sh
host/engines llama uninstall
```

`uninstall` removes the `llama` container and every llama.cpp image, of every build and flavor:
the server images, ggml's full images, which llama-bench runs ([Setup](setup.md#llama-bench)), and
any untagged one. It keeps the model store, `/srv/models`, so a later install serves the same models
without downloading them again. A second run changes nothing and says so.

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
command ls /srv/models
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

## The Framework

On the Framework, `host/engines llama uninstall` removes the `llama` container, started by hand or
by `install`, of either flavor, and every llama.cpp image, the ROCm and Vulkan server and full images
([Removing llama.cpp](#removing-llamacpp)). It keeps `/srv/models`.

The native Vulkan prebuilt that pre-staging fetched for llama-bench
([Models](models.md#on-the-framework)) isn't an image, so it is the session's to remove:

```sh
rm -r ~/llama.cpp/b11960-vulkan
```

The Framework holds the build its llama-bench runs used,
[llama-strix-rocm](../../findings/llama-strix-rocm.md#llama-bench)'s b11669, unpacked in
`~/llama.cpp/b11669-vulkan`, with its tarball in `~/prestage`; the pin's was never fetched. The
answer task removes both, then `~/llama.cpp`, which `rmdir` removes only when nothing else is
left in it, and lists what remains, which prints `No such file or directory` for each:

```sh
rm -r ~/llama.cpp/b11669-vulkan ~/prestage/llama-b11669-bin-ubuntu-vulkan-x64.tar.gz
rmdir ~/llama.cpp
command ls -d ~/llama.cpp ~/prestage/llama-b11669-bin-ubuntu-vulkan-x64.tar.gz
```

ggml's release rebuilds it: the pre-staging block fetches the pin's prebuilt, checks its digest,
and unpacks it in `~/llama.cpp/<build>-vulkan` ([Models](models.md#on-the-framework)); b11669's
asset is `llama-b11669-bin-ubuntu-vulkan-x64.tar.gz`, whose SHA-256 is
`e8709e5ba6c1b093dea7f3de57f4aba842f9a188fba6b465782d65d6fcfa4d9f`.

The vLLM audio probe's image, `spike-model-engines/vllm-openai-rocm-audio:v0.32.0`, is vLLM's
official ROCm image with three audio decoders added, which
[vllm-strix](../../findings/vllm-strix.md#the-audio-probe) built on the Framework. The suite never
builds or serves it, so neither `host/engines vllm uninstall` nor llama.cpp's removes it; the
session does, and the image list then shows no `vllm-openai-rocm-audio`. It shares its layers
with `vllm/vllm-openai-rocm:v0.32.0`, which stays, so only the added layer's space comes back:

```sh
docker rmi spike-model-engines/vllm-openai-rocm-audio:v0.32.0
docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
```

Its Dockerfile stays in the repository, `host/vllm-rocm-audio/Dockerfile`, and rebuilds it, as
the probe did, from the clone:

```sh
docker build -q -t spike-model-engines/vllm-openai-rocm-audio:v0.32.0 host/vllm-rocm-audio
```

### Removing the Framework's root steps

After `uninstall`, the architect undoes the root steps of
[Setup](setup.md#framework-in-a-container), each with a root step. `jaime` leaves the `docker`
group, which takes effect at the next login, and, when nothing else on the host uses Docker, Docker
stops and no longer starts at boot:

```sh
sudo gpasswd -d jaime docker
sudo systemctl disable --now docker
```

The ufw rules that route the tailnet's traffic to the containers' ports, llama.cpp's and vLLM's:

```sh
sudo ufw route delete allow in on tailscale0 proto tcp to any port 8080
sudo ufw route delete allow in on tailscale0 proto tcp to any port 8000
```

Each deletes its IPv4 and IPv6 rule; `sudo ufw status verbose` then lists no `ALLOW FWD` rule on
`tailscale0`.

The page-cache rule:

```sh
sudo rm /etc/sudoers.d/drop-caches
```

The model store, with the models seeded into it. Their originals stay on the models drive, in
`/mnt/models/hf-cache`, which seeding never changed:

```sh
sudo rm -rf /srv/models
```

The space comes back once the last Omarchy snapshot holding the models ages out
([Setup](setup.md#framework-in-a-container), step 8).

The GTT ceiling, back to its earlier 96 GiB: TTM's `pages_limit` to 25165824 and amdgpu's
`gttsize` to 98304, rebuilt into the boot images, then a reboot. `amd-ttm` asks whether to reboot:
answer `n`, and reboot last:

```sh
sudo amd-ttm --set 96
echo 'options amdgpu gttsize=98304' | sudo tee /etc/modprobe.d/amdgpu.conf
sudo limine-mkinitcpio
sudo reboot
```

After the reboot, `cat /sys/module/ttm/parameters/pages_limit` prints `25165824`, and `cat
/sys/class/drm/card*/device/mem_info_gtt_total` prints `103079215104`.

Last, spike-model-hosting's router, stopped by the setup, starts again and at every boot. It
holds port 8080, so the `llama` container must be gone first:

```sh
sudo systemctl enable --now llama-router
```

`systemctl is-active llama-router` prints `active`.
