# spike-model-engines

A spike for the Standards Lab reference architecture. It measures llama.cpp and vLLM on the
workstations, a GB10 (gb10-1; gb10-2 is reserved for spike-ai-pipeline) and then the Framework's
Strix Halo, in containers and on bare metal. `README.md` is the front page and gives the answer
under "The answer". The repository is managed with the marathon workflow, so start from
`context/README.md`.

- **Rules:** read `docs/rules.md` and `standards-lab/docs/ai-hosting.md#experiment-rules` before
  any host step.
- **Standards:** `STANDARDS.md`, with pointers into the architecture repository.
- **Check:** `mise run check`, which shellchecks every tracked shell script and runs lint-context
  and lint-references.
- **Currency:** `mise run currency`, which reports every pin behind its latest.
- **Goals:** the spike answered for experiment.hosting, which is complete;
  `standards-lab/roadmap/v1.ai.hosting.toml` builds from its answer.
- **References:** the repositories this spike reads are keys in the coordinator's
  `references.toml` and `references.local.toml`. The spike reads them and never writes to them.
