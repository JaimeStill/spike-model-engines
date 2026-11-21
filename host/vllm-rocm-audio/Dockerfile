# The audio image: vLLM's ROCm image at the pin, by its digest, with the audio extra's missing
# decoders, for the Framework's audio row.
# See docs/engines/vllm/setup.md#the-audio-image
FROM vllm/vllm-openai-rocm:v0.34.0@sha256:3cb773d23f063afa86291ef75773cdd486154ddea94c213300f4ed7cc42b7af1
RUN uv pip install --system av==19.0.2 soundfile==0.14.0 soxr==1.1.0
