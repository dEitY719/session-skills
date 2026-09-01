# session:handoff — Handoff Artifact + Memory Record (Steps 3, 5)

## Comment body template

ALWAYS use this exact section skeleton (no emojis — CLAUDE.md repo policy):

```markdown
<!-- session-handoff -->
## Session handoff — <YYYY-MM-DD HH:MM>

### 완료 (검증됨)
- <merged PR / green test / deployed artifact — one line each, with links>

### 미검증 (작성됨, 확인 안 됨)
- <edits made this session whose tests/review have not run — omit section if empty>

### 남은 작업
- <next track + concrete sub-items, each with file/spec pointers>

### 재개 환경
- branch: `<branch>` / worktree: `<path>`
- test: `<command>` (기타 DSN/DB/실행법이 있으면 한 줄씩)

### 설계·스펙 링크
- <issue/PR/doc links the next session needs — omit if none>

### 미결 결정·블로커
- <open decisions or blockers — omit if none>

### 재개 포인터
`#<N> <next-step> 진행`
```

### Honesty rules (non-negotiable)

- "완료 (검증됨)" holds ONLY merged PRs, tests that ran green in this
  session, and artifacts verified end-to-end. Everything else is 미검증.
- Never round "code written" up to "done". The next session trusts this
  comment; an overstated handoff wastes its first hour re-verifying.
- Remaining-work items come from the session TodoList (TaskList) when one
  exists, plus anything discussed but not yet queued.

## Resume sentence

Format: `#<N> <next-step> 진행` — e.g. `#1767 P5b 진행`, `#1076 리뷰 반영
진행`. Rules:

- `<N>` is the tracking issue actually posted to (or recorded in memory).
- `<next-step>` names the first item under "남은 작업" — a track label
  (P5b), a phase, or a short verb phrase. It must appear in the handoff
  body; never invent a key the issue doesn't contain.
- One line, copy-paste ready, printed both in the comment (재개 포인터) and
  as the skill's final output.

## Memory record (Step 5)

Write one `project`-type memory file (auto-memory conventions of the
running agent; for Claude Code, the session memory directory):

```markdown
---
name: session-handoff-issue-<N>
description: Resume state for #<N> — <one-line next step>
metadata:
  type: project
---

Issue #<N> (<repo>) handoff — <YYYY-MM-DD>.
Resume: `#<N> <next-step> 진행`
Branch `<branch>`, worktree `<path>`.
Done (verified): <one line>. Remaining: <one line>.
Handoff comment: <comment URL, or "memory-only">
```

Update the existing `session-handoff-issue-<N>` file if one exists (one
live handoff per issue), and refresh its index line in `MEMORY.md`. A
memory-write failure is a `[WARN]`, never a stop — the issue comment
already carries the handoff when Step 4 ran.
