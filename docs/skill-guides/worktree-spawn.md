# session:worktree-spawn — 격리된 git 워크트리 생성

> **한 줄 요약** — 같은 저장소에서 병렬로 도는 다른 에이전트와 충돌하지 않도록 `../<project>-<agent>-<N>` 워크트리와 `wt/<agent>/<N>` 브랜치를 산출한다.

## 언제 쓰나

- 병렬 작업을 시작할 때 ("새로운 작업 시작", "격리된 작업 공간 만들어줘")
- 한 저장소에 여러 AI 에이전트를 동시에 띄울 때

## 언제 안 쓰나

| 상황 | 대신 쓸 것 |
|---|---|
| 작업이 끝나 워크트리를 정리한다 | `session:worktree-teardown` |
| 이미 워크트리 안에 있다 | 스킬이 **차단한다**. 메인 저장소에서 실행할 것 |

## 호출 형식

```
/session:worktree-spawn [--ai <name>] [--task <slug>] [--base <ref>] [<branch>]
/session:worktree-spawn -h
```

| 인자 | 설명 | 기본값 |
|---|---|---|
| `--ai <name>` | 에이전트 이름 강제 지정 | 자동 감지 |
| `--task <slug>` | 브랜치에 붙일 작업 슬러그 | 없음 |
| `--base <ref>` | 베이스 ref 강제 지정 | 자동 해석 |
| `<branch>` | 명시 브랜치명 (그대로 사용) | `wt/<agent>/<N>` |

한국어 `--task` 는 영문 슬러그로 변환한다 (소문자, 하이픈, 최대 30자).
예: "로그인 기능" -> `login-feature`.

## 동작 단계

1. **사전 조건 검증** — git 저장소인지, **워크트리 안이 아닌지**(맞으면 차단),
   dirty 상태 경고, 부모 디렉터리 쓰기 권한.
2. **git-crypt 탐지 (1.5)** — `filter.git-crypt.smudge` 설정 여부와 키 파일 해석
   (`$GIT_CRYPT_KEY_FILE` → `~/.config/git-crypt/<project>.key` → `default.key`).
3. **에이전트 감지** — `--ai` > `$AI_AGENT_NAME` > 에이전트별 env var
   (`CLAUDECODE`, `AGY_CLI`, `CODEX_CLI`, ...) > `agent`.
4. **프로젝트명·인덱스 계산** — 부모 디렉터리에서 `{project}-{agent}-N` 패턴을 훑어
   max(N)+1.
5. **락 획득 (3.5)** — `mkdir` 기반 원자적 락 (`ai-worktree-spawn.lock`). stale 락은
   10초 후 제거, 3회 재시도.
6. **브랜치명 결정** — 인자 없음 → `wt/{agent}/{N}`, `--task` → `wt/{agent}/{N}-{slug}`,
   명시 브랜치 → 그대로.
7. **베이스 ref 결정** — `--base` > `origin/main` > `main`/`master` > 현재 `HEAD`.
8. **워크트리 생성** — 키가 있으면 자동 unlock 4단계, 없으면 bypass 경로(필터 비활성,
   암호화 파일은 바이너리 유지).
9. **로그 기록** — `$(git rev-parse --git-common-dir)/ai-worktree-spawn.log` 에 append.
10. **리포트 후 이동** — 결과를 찍고 새 워크트리로 `cd`.

## 주의사항 / 제약

- **워크트리 안에서 실행하면 거부한다.** 메인 저장소에서만 돈다.
- **git-crypt 저장소에서는 명시적 `git add <path>` 를 쓴다** — `-A` 나 `.` 은 금지.
  자동 unlock 된 파일이 raw-byte 대 textconv 불일치로 수정된 것처럼 보일 수 있다.
- 키 파일이 해석되지 않으면 추측하지 않고 bypass 경로로 물러난다.
- 로그·락 파일명은 `ai-worktree-spawn.{log,lock}` 로 **유지된다**. 명령 이름이 아니라
  런타임 데이터 경로이며, 이름을 바꾸면 기존 로그가 고아가 되고 락이 갈라진다.
- 스크립트는 호출자의 cwd 를 바꿀 수 없다. `cd` 명령을 안내로 출력하고, 에이전트가 직접
  수행한다.
