# vllm-strix's audio probe (the goal record's escalation 1): vLLM's ROCm image at the pin, by its
# digest, with the decoders of vLLM's audio extra it ships without. The image has no torchcodec,
# ffmpeg, av, soundfile, or soxr, so its audio loader fails every request with "Please install
# vllm[audio]"; the extra (av, scipy, soundfile, soxr, mistral_common[audio]) pins no versions, and
# of it only these three are missing, at the versions uv resolved on 2026-10-28, which change
# nothing already in the image. The suite never builds or serves it: it serves the official
# image, and whether it should carry this one is the answer task's.
FROM vllm/vllm-openai-rocm:v0.32.0@sha256:14f6a575e1fb0a580b0f633c09e06f648709d60405b85f6a7ff3f80d49f39905
RUN uv pip install --system av==19.0.2 soundfile==0.14.0 soxr==1.1.0
