# The audio image: vLLM's ROCm image at the pin, by its digest, with the decoders of vLLM's audio
# extra it ships without, which the Framework's audio row (vllm-rows,
# gemma-4-E4B-it-audio-framework) serves from. vllm-strix's audio probe found the official image
# with none of torchcodec, ffmpeg, av, soundfile, or soxr, so vLLM raises "Please install
# vllm[audio]" and every audio request returns 500 (docs/findings/vllm-strix.md, "The audio
# probe"). The extra (av, scipy, soundfile, soxr, mistral_common[audio]) pins no versions, and of
# it only these three were missing, pinned at the versions uv resolved on 2026-10-28.
#
# It builds on v0.34.0's one ROCm build, its default tag, ROCm 10.0 (the same image as -rocm100),
# as the suite serves it (host/vllm.env), pinned by the index digest Docker Hub served for the tag
# on 2026-11-17. v0.34.0's audio extra is v0.33.0's, so the same three are installed. The host
# builds it, tagged as the suite serves it, <repository>:<release>, from the clone:
#
#   docker build -t spike-model-engines/vllm-openai-rocm-audio:v0.34.0 host/vllm-rocm-audio
#
# The suite never pulls it, and never removes it (host/vllm.sh). Currency doesn't read it, so a
# release move leaves it behind: the digest moves with VLLM_RELEASE, by hand.
FROM vllm/vllm-openai-rocm:v0.34.0@sha256:3cb773d23f063afa86291ef75773cdd486154ddea94c213300f4ed7cc42b7af1
RUN uv pip install --system av==19.0.2 soundfile==0.14.0 soxr==1.1.0
