# Standards

The judgement calls the check can't enforce, one line each, for the standards-reviewer. What
`mise run check` enforces is never restated here.

The architecture pages that apply, in the architecture repository:

- `principles/minimal-footprint.md`
- `principles/rolling-currency.md`
- `principles/validation-first.md`

## Scripts

- Only a step that must be idempotent is scripted: install, update, uninstall. Anything else is a
  documented command the architect types.
- Scripts are `engines-<group>-<verb>` commands behind one `engines` dispatcher, each with a
  one-line `# engines:summary=` header, run from the clone on each host and never installed.
- A script is short and does one step; a script that grows past that is split, not extended.
- No Python is authored, and a mise task runs one script or one command.

## Docs

- Each engine's guide is a directory, `docs/engines/<engine>/`: a README that indexes it, and
  `setup.md`, `models.md`, `api.md`, `update.md`, and `uninstall.md`. A host class or hosting
  method adds a section, not a file.
- A guide says how the engine runs now; a finding, under `docs/findings/<task>.md`, says what was
  measured, when, on which engine version and host stack, and stays dated.
- Every command the architect runs appears in the guide exactly as it is typed. No host name or
  tailnet identifier is committed.
