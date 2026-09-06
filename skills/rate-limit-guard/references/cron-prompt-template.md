# Cron Prompt Template

Use this exact text for the `prompt:` argument of `CronCreate` in Step 3 of
the rate-limit-guard SKILL.md, **and** for the next-cycle cron registered
by `/session:resume-after-limit` (Step 4). Substitute `<PWD_NOW>`, `<BRANCH>`,
and `<command>` with the values captured at registration time.

```
[Auto-resume by /session:rate-limit-guard]
워크트리: <PWD_NOW>
브랜치: <BRANCH>
원본 명령: <command>

현재 워크트리·브랜치가 위와 같으면 `/session:resume-after-limit`을 호출하여
재개. 그 스킬이 state 파일에서 multi-cycle 정보(`cycles_remaining`,
`cycle_window_min`)를 읽어 다음 cycle을 자동 재무장한다. 워크트리/브랜치가
다르면 사용자에게 알리고 중단.
```

`/session:resume-after-limit` ships in the same `session` plugin, so it is
always present wherever this skill is — no fallback branch is needed.

## Why the same template for cycle 2..N

`/session:resume-after-limit` reuses this same template when registering the
next-cycle cron (Step 4). The cycle bookkeeping lives in the state file —
the prompt itself is cycle-agnostic, which keeps the cron payload uniform
and the template a single source of truth.
