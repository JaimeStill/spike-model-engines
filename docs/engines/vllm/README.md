# vLLM

vLLM serves Hugging Face models through `vllm serve`, an OpenAI-compatible HTTP server. This spike
runs it on the GB10s in vLLM's CUDA 13.0 image first, and natively later. Unlike llama.cpp's
router, a vLLM server serves one model, named on its command line when it starts, and loads no
other on demand: changing the model means editing the pin and running `update`.

The spike follows vLLM's GitHub releases. The pin lives in `engines/vllm.env`: release v0.32.0,
image `vllm/vllm-openai:v0.32.0`, and the model it serves, `nvidia/Gemma-4-26B-A4B-NVFP4`, pinned
beside the release. `mise run currency` reports the release when a newer one is out.

The `engines vllm` commands that install, update, and uninstall it come later in this task.

## Pages

- [Setup](setup.md): bring a host current, record its stack, and prove the image.

To come in this task: Update (moving to the pinned release or model), Uninstall, API, and Models.
