# spike-model-engines

A spike for the Standards Lab reference architecture. It measures llama.cpp and vLLM on the
workstations, the two GB10s and then the Framework's Strix Halo, in containers and on bare metal.
`README.md` is the front page and gives the answer under "The answer". The repository is managed
with the marathon workflow, so start from `context/README.md`.

- **Rules:** sessions are guided. The architect runs every host step from the docs, and every
  benchmark is planned and run together. Read `context/README.md`, "Rules", and the experiment's
  rules in `standards-lab/context/ai-hosting.md`, "Experiment: experiment.hosting", before any
  host step.
- **Standards:** `STANDARDS.md`, with pointers into the architecture repository.
- **Check:** `mise run check`, which shellchecks every tracked shell script.
- **Currency:** `mise run currency`, which reports every pin behind its latest.
- **Goals:** this spike's tasks live in the coordinator's roadmap,
  `standards-lab/context/roadmap.toml`, under `experiment.hosting.spike-model-engines`. Its goal
  record is `context/goals/experiment.hosting.spike-model-engines.md`.
- **References:** the repositories this spike reads are keys in the coordinator's
  `references.toml` and `references.local.toml`. The spike reads them and never writes to them.
