# The spike's rules

The rules this spike keeps beside the experiment's rules,
`standards-lab/docs/ai-hosting.md#experiment-rules`, which
[`context/README.md`](../context/README.md#rules) points to: how llama.cpp is pinned, the load
tools, and the root grants.

- **Current hosts and engines.** Every session starts by bringing the hosts current. llama.cpp
  is pinned to one b-build per host class, which currency compares with the newest b-build that
  has the class's server image on ghcr.io; the guides name a build a semver release names by the
  release first, with the b-build beside it, as v0.7.0 (b11669); vLLM follows its releases.
  Every result records the engine version and the host stack.
- **Load tools.** GuideLLM 0.8.1, run from the laptop, for every served measurement; llama-bench
  for raw pp/tg per llama.cpp backend.
- **Root** stays the architect's, run from exact commands. A root command a session must repeat
  may be granted once, by the architect, as a sudoers rule naming that one command exactly, such
  as gb10-1's page-cache drop
  ([setup](../docs/engines/llama.cpp/setup.md#7-allow-the-page-cache-drop)) and the Framework's
  ([setup](../docs/engines/llama.cpp/setup.md#11-allow-the-page-cache-drop)), or the five
  `systemctl` commands that start, stop, restart, enable, and disable native llama.cpp's
  `llama-router` unit, each named with its arguments
  ([setup](../docs/engines/llama.cpp/setup.md#1-the-architects-root-steps)), and native vLLM's
  `vllm-server` unit ([setup](../docs/engines/vllm/setup.md#1-the-architects-root-steps)).

