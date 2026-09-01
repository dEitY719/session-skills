# session:handoff — Final Report (Step 6)

## Success

```
[OK] session:handoff — #<N> handoff posted
  issue:    <issue URL>
  comment:  <comment URL | updated <comment URL> | memory-only>
  memory:   session-handoff-issue-<N>.md (updated)
  resume:   #<N> <next-step> 진행

Next: 새 세션에서 재개 문장을 첫 지시로 붙여넣으세요 —
      `#<N> <next-step> 진행`
      (같은 세션 중단 복구는 /session:restart, 토큰 리밋 크론 재개는
      /session:resume-after-limit)
```

`comment:` shows `updated <URL>` when the duplicate-handoff guard replaced
an earlier same-session comment, and `memory-only` when `--memory-only` was
given or the judge degraded to it.

## Soft-fail (comment post failed, memory saved)

```
[WARN] session:handoff — #<N> comment post failed, memory-only fallback
  reason:   <one-line API error>
  memory:   session-handoff-issue-<N>.md (updated)
  resume:   #<N> <next-step> 진행

Next: `gh issue comment <N> --body-file <artifact>` 를 수동 재시도하거나,
      새 세션에서 재개 문장으로 바로 이어가세요.
```

## Failure (no target, cannot proceed)

```
[FAIL] session:handoff — 트래킹 이슈를 결정할 수 없음
  tried:    arg=<none|N>, conversation=<n candidates>, branch=<branch>, gh=<n>
  reason:   <one line — e.g. GitHub unreachable and --memory-only not given>

Next: 이슈 번호를 명시해 재실행 (`/session:handoff <N>`) 하거나
      `--memory-only` 로 메모리 기록만 남기세요.
```

Every path ends with a `Next:` hint — the whole point of a handoff is that
the reader knows the next move without asking.
