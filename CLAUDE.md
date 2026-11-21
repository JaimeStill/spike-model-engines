# spike-model-engines

A spike for the Standards Lab reference architecture. It measures llama.cpp and vLLM on the
workstations, a GB10 (gb10-1; gb10-2 is reserved for spike-ai-pipeline) and then the Framework's
Strix Halo, in containers and on bare metal. `README.md` is the front page and gives the answer
under "The answer". The repository is managed with the marathon workflow, so start from
`context/README.md`.

- **Rules:** sessions are guided where the architect is learning. The session runs routine host
  steps that need no root over Tailscale SSH, and the GuideLLM cells in the architect's view, from
  the commands the brief agreed; the architect keeps root, a new tool's or concept's first walk,
  the last slice's walkthrough, and every escalation's decision. Every benchmark is planned
  together. Read `context/README.md`, "Rules", and the experiment's rules,
  `standards-lab/docs/ai-hosting.md#experiment-rules`, before any host step.
- **Standards:** `STANDARDS.md`, with pointers into the architecture repository.
- **Check:** `mise run check`, which shellchecks every tracked shell script.
- **Currency:** `mise run currency`, which reports every pin behind its latest.
- **Goals:** the coordinator's roadmap, `standards-lab/roadmap/index.toml`, holds this spike's
  work.
- **References:** the repositories this spike reads are keys in the coordinator's
  `references.toml` and `references.local.toml`. The spike reads them and never writes to them.
