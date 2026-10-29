# vllm-strix's audio probe (docs/findings/vllm-strix.md, "The audio probe"): vLLM's ROCm image at
# the pin, by its digest, with the decoders of vLLM's audio extra it ships without. The image has
# none of torchcodec, ffmpeg, av, soundfile, or soxr, so vLLM raises "Please install vllm[audio]"
# and every audio request returns 500. The extra (av, scipy, soundfile, soxr,
# mistral_common[audio]) pins no versions, and of it only these three are missing, pinned at the
# versions uv resolved on 2026-10-28, which change nothing already in the image. The suite never
# builds or serves it: it serves the official image, and the answer task settled that it doesn't
# carry this one. The image stays a probe, removed from the Framework on 2026-10-29, at v0.32.0,
# the release it probed, and currency doesn't read it, so a release move leaves it behind.
FROM vllm/vllm-openai-rocm:v0.32.0@sha256:14f6a575e1fb0a580b0f633c09e06f648709d60405b85f6a7ff3f80d49f39905
RUN uv pip install --system av==19.0.2 soundfile==0.14.0 soxr==1.1.0
