# session:restart — Chunking & Delegation Rules

## 1-tool-call splitting

When resuming an interrupted task, split the next concrete action into
single-tool-call increments so the next flake costs less:

- **One `Read` per file.** No batch reads of 5 files in a single turn.
- **One `Edit` per logical change.** No multi-file `replace_all` sweeps.
- **One `Bash` per command.** Avoid long `&&` chains that re-run from
  the start on retry.
- **One subagent per investigation.** Don't fan out 4 in parallel here —
  the whole point is to reduce blast radius on the next flake.

## Subagent delegation thresholds

Anything that would dump > ~200 lines into the main context MUST be
delegated to a subagent — a turn that dies mid-dump re-runs the whole
dump. Triggers:

- Broad code search across the repo (unscoped `grep` / `rg`).
- `find` over the whole tree.
- Reading a 1k-line file when only a slice is needed.
- Multi-file conformance / consistency checks.

Routing:

- Broad code search / cross-file consistency → `Agent(subagent_type="Explore")`.
- Multi-step research or "go figure out X" →
  `Agent(subagent_type="general-purpose")`.

Brief the agent with the resume target and cap the response at ~200 words.
