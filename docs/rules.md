# The spike's rules

The rules this spike keeps beside the experiment's rules,
`standards-lab/docs/ai-hosting.md#experiment-rules`, which
[`context/README.md`](../context/README.md#rules) points to: how sessions are guided, how
benchmarks run, how llama.cpp is pinned, the load tools, and the root grants.

- **Guided sessions.** Sessions are guided where the architect is learning. Each slice's docs and
  scripts are written on the branch first. The session runs routine host steps that need no root
  itself, over Tailscale SSH, and records each output: downloads and image pulls, engine install,
  update, and uninstall, model loads, readiness waits, cold-start timing, log and memory
  read-outs, and health and version checks. The architect keeps root, a new tool's or concept's
  first walk, which the session walks them through, the last slice's walkthrough of the whole
  procedure from the docs, and every escalation's decision. Every command either side runs
  appears in a guide or the finding's method exactly as run.
- **Benchmarks.** Each benchmark is planned together in its task's plan round, then built and run
  a step at a time from the commands the brief agreed: the session runs the GuideLLM cells in the
  architect's view, printing each command first. A run takes at most 10 minutes unless the
  brief decides otherwise.
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
  ([setup](engines/llama.cpp/setup.md#7-allow-the-page-cache-drop)) and the Framework's
  ([setup](engines/llama.cpp/setup.md#11-allow-the-page-cache-drop)), or the five
  `systemctl` commands that start, stop, restart, enable, and disable native llama.cpp's
  `llama-router` unit, each named with its arguments
  ([setup](engines/llama.cpp/setup.md#1-the-architects-root-steps)), and native vLLM's
  `vllm-server` unit ([setup](engines/vllm/setup.md#1-the-architects-root-steps)).

