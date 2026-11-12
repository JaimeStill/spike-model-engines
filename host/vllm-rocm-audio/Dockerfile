# The audio image: vLLM's ROCm image at the pin, by its digest, with the decoders of vLLM's audio
# extra it ships without, which the Framework's audio row (vllm-rows,
# gemma-4-E4B-it-audio-framework) serves from. vllm-strix's audio probe found the official image
# with none of torchcodec, ffmpeg, av, soundfile, or soxr, so vLLM raises "Please install
# vllm[audio]" and every audio request returns 500 (docs/findings/vllm-strix.md, "The audio
# probe"). The extra (av, scipy, soundfile, soxr, mistral_common[audio]) pins no versions, and of
# it only these three were missing, pinned at the versions uv resolved on 2026-10-28.
#
# It builds on either of v0.33.0's ROCm builds, the one VLLM_ROCM_BUILD names, as the suite serves
# them (host/vllm.env): the default tag, ROCm 10.0 (the same image as -rocm100), unless
# VLLM_ROCM_BUILD=rocm72 names the fallback, ROCm 7.2. Each is pinned by the digest Docker Hub
# served for its tag on 2026-11-11. BuildKit, Docker's default builder, fetches only the build the
# last FROM names. The host builds it, tagged as the suite serves it, <repository>:<release>, or
# <repository>:<release>-rocm72 for the fallback, from the clone:
#
#   docker build -t spike-model-engines/vllm-openai-rocm-audio:v0.33.0 host/vllm-rocm-audio
#   docker build --build-arg VLLM_ROCM_BUILD=rocm72 \
#     -t spike-model-engines/vllm-openai-rocm-audio:v0.33.0-rocm72 host/vllm-rocm-audio
#
# The suite never pulls it, and never removes it (host/vllm.sh). Currency doesn't read it, so a
# release move leaves it behind: both digests move with VLLM_RELEASE, by hand.
ARG VLLM_ROCM_BUILD=

FROM vllm/vllm-openai-rocm:v0.33.0@sha256:4fcd39b758b660c4e9c345c021e2ea8f0ccdb31e3c32507d676cc3005ae83fba AS default
FROM vllm/vllm-openai-rocm:v0.33.0-rocm72@sha256:4fe7bc121cbe2f0791ebc38dcc2f0d615612233b4bfc0c1f4b9daeab05aba182 AS rocm72

FROM ${VLLM_ROCM_BUILD:-default}
RUN uv pip install --system av==19.0.2 soundfile==0.14.0 soxr==1.1.0
