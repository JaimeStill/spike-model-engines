# Setting up vLLM

## GB10, in a container

Run these steps on each GB10, one host at a time. Docker needs no `sudo`, because the account is
in the `docker` group.

### 1. Bring the host current and record its stack

The host steps are llama.cpp's, and they stay in one place: run
[Bring the host current](../llama.cpp/setup.md#1-bring-the-host-current), including the
`nvidia-ctk cdi generate` step after every upgrade, then
[Record the host stack](../llama.cpp/setup.md#2-record-the-host-stack). Record each output, with
the date, in the task's finding.

### 2. Prove the pinned image runs on the GPU

Pull the pinned image (`engines/vllm.env`). The image's entrypoint is `vllm serve`, so each check
below replaces it with `--entrypoint`: first ask `vllm` for its version, then ask PyTorch, in the
image's Python, for the GPU it finds:

```sh
docker pull vllm/vllm-openai:v0.32.0
docker run --rm --gpus all --entrypoint vllm vllm/vllm-openai:v0.32.0 --version
docker run --rm --gpus all --entrypoint python3 vllm/vllm-openai:v0.32.0 -c \
  "import torch; p = torch.cuda.get_device_properties(0); print(torch.cuda.get_device_name(0), p.total_memory // 2**20, 'MiB')"
```

`--version` prints `0.32.0`. The second command prints the GB10's name and the memory CUDA sees
on it, in MiB; an error that no CUDA device is available means the container didn't reach the
GPU.
