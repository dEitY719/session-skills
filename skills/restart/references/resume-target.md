# session:restart — Resume-target Selection (Step 1)

Everything Step 1 needs to decide *what* to resume. Read this before touching
the task; the SKILL.md body only routes here.

## Precedence

Use `TaskList` to read the current todo list, then pick by this order:

1. The single `in_progress` task — that is exactly where the prior turn died.
2. If no `in_progress`, the first `pending` task in order.
3. If both are empty, ask the user one short line:
   `재개할 작업이 분명하지 않습니다. 어디서 이어가면 될까요?` and stop.

Rule 3 is a hard stop, not a guess. Emit the hard-stop template from
`output-format.md` and wait.

## Do not re-invoke a process skill

`superpowers:brainstorming`, `superpowers:test-driven-development`,
`superpowers:systematic-debugging` and friends may appear earlier in the
conversation. Their output is already in context — re-running them burns the
window and produces nothing new. Resume from the implementation/edit step
those skills led to.

## Corroborate the pick against disk

Run `git status --short` once to confirm the working tree actually matches
what the picked task implies — self-reported TodoList status can lag disk
reality (e.g. a task marked `completed` whose files are still uncommitted).
If it contradicts the picked task, tell the user in one line before
proceeding; don't silently resume over a mismatch.

## When the todo is coarser than the interruption

If the picked task is coarser than the actual interruption point (e.g. a todo
like "구현 issue #N" when the prior turn died partway through it), don't
guess — use the last completed tool result already in the conversation to
pinpoint exactly where it died, then resume from there. If no completed tool
result exists in context (e.g. the turn died at session start), fall back to
rule 3 above and ask.
