---
name: handoff
description: >-
  세션 경계에서 *미완* 작업을 트래킹 이슈 코멘트로 인계하고 auto-memory 와 재개 문장을 남긴다 —
  퇴근·인수인계·컨텍스트 임계 어느 쪽이든. Use for /session:handoff, "핸드오프", "세션 넘겨",
  "컨텍스트 다 찼어", "hand off this session".
  *완료* 기록은 gh-issue:create, 재개는 session:restart /
  session:resume-after-limit.
allowed-tools: Bash, Read, Write, Grep, TaskList
license: MIT
metadata:
  model_recommendation:
    tier: sonnet
    reason: "conversation synthesis + tracking-issue resolution judgment; writes are two low-risk artifacts (issue comment, memory file)"
    claude: prefer
    non_claude: advisory-only
---

# session:handoff — Handoff Comment + Resume Sentence

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No API calls.

**Stop-on-error policy** — HARD-stop: Step 2 when no tracking issue can be
resolved AND GitHub is unreachable without `--memory-only` (ask, don't
guess). Soft-fail: Step 4 comment post (fall back to memory-only + warn);
Step 5 memory write never blocks — warn and continue.

## Step 1: Parse Args

| Option | Description | Default |
|---|---|---|
| `[issue-number]` | 트래킹 이슈 번호 (양의 정수) | auto-resolve (Step 2) |
| `[remote]` | git remote 이름 | `origin` |
| `--memory-only` | 이슈 코멘트 생략, 메모리에만 기록 | off |
| `--new-issue` | 기존 후보 무시, 신규 트래킹 이슈 강제 생성 | off |
| `-h`/`--help`/`help` | usage 출력 후 정지 | — |

Resolve `TARGET_REPO=<owner>/<repo>` from the remote URL (same procedure as
gh-issue:read); unknown remote → list `git remote -v` and stop.

## Step 2: Resolve the Tracking Issue

Follow `references/issue-resolution.md`: explicit arg → conversation
`#N` mentions → branch `wt/issue-N-*` → recent `gh` activity. Multiple
candidates → pick the most-referenced or ask. No candidate → judge:
substantive multi-session work gets a new tracking issue via
Skill(gh-issue:create); trivial work degrades to `--memory-only`. The
duplicate-handoff guard also lives there — `bash
"${SKILL_DIR}/lib/find-handoff-comment.sh" "$TARGET_REPO" <N> "$SESSION_ID"`
prints THIS session's handoff comment id to PATCH, or nothing → POST a new
one; being session-scoped it can never return another session's comment.

## Step 3: Compose the Handoff Artifact

Build the comment body per `references/handoff-template.md`, honouring its
"Honesty rules (non-negotiable)" section — that is the one model-facing
statement of what may be called done, and it is not restated here. Pull
remaining work from the session TodoList (TaskList) when one exists.

## Step 4: Post the Comment

`gh issue comment <N> --repo "$TARGET_REPO" --body-file <artifact>` — skip
entirely when `--memory-only`. On API failure: one `[WARN]` line, continue —
the Step 5 memory copy still preserves the handoff.

## Step 5: Update Auto-memory (always)

Write or update one `project`-type memory file recording issue number,
branch, worktree, next step, and the resume sentence; refresh the memory
index line. Format in `references/handoff-template.md` → "Memory record".
Runs even when Step 4 posted successfully (issue = team-visible, memory =
agent-local).

## Step 6: Resume Sentence + Report

Print the copy-paste resume sentence (`#<N> <next-step> 진행` — must map to
the real tracking issue and its actual next step; never fabricate), then the
`[OK]`/`[FAIL]` structured report per `references/report-template.md`,
ending with the `Next:` hint.

## Constraints

- Writes are exactly two artifacts: one issue comment, one memory file.
  Never commit, push, edit code, or close/relabel issues.
- Never invent a resume sentence that doesn't map to the tracking issue.
- Reuses gh-issue:create (new tracking issue) and gh-issue:read
  (candidate validation).

## Related Skills

- Resumers this handoff feeds — `session:restart` (같은 세션 중단 직후 재개) ·
  `session:resume-after-limit` (토큰 리밋 리셋 후 크론 재개). 재개 문장은 이들을
  구동하는 사람이 그대로 읽을 수 있어야 한다.
- 본 스킬은 *미완* 작업의 세션 연속성 전용이다. 일회성 *완료* 기록은
  `gh-issue:create` / `gh-issue:discussion-create`, 완료 세션의 vault Inbox 노트는
  `pkm:obsidian-session-clip` 몫이다.
