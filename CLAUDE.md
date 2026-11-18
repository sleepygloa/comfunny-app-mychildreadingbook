# CLAUDE.md — 나의 아이의 책읽기 (mychild-reading)

이 저장소는 **나의 아이의 책읽기 앱 하나만** 담는다. 본업·다른 프로젝트 코드는 여기 없다.
2026-11-18 `sleepygloa/comfunny-total-system` 의 `200-apps-games/apps/01-mychild-reading/`(커밋 `7fb5a69`)에서 옮겨 왔다.
규칙은 하네스(`sleepygloa/comfunny-standard-docs`)에서 이 앱에 필요한 것만 골라 옮겼다. 하네스 전체를 가져오지 않는다 —
필요한 규칙이 생기면 이 파일에 한 줄씩 더한다.

**앱 고유 규칙(스택 · 데이터 · 함정)은 [AGENTS.md](AGENTS.md) 가 정본이다.** 아래에서 함께 읽는다.

@AGENTS.md

## 0. 오너와 일하는 방식 — 가장 먼저 지킬 것

- 오너는 **휴대폰으로 지시**하고, 결과는 **휴대폰에서 보고** 확인한다. **코드는 읽지 않는다.**
- 그래서 기획 · 화면 작업의 끝은 **휴대폰에서 열리는 링크**다 — 화면 프로토타입은 [prototype/](prototype/README.md) 의 HTML 을 갱신해 링크로 보인다.
  실제 앱 동작(카메라 · 녹음 · 소리)은 APK 를 폰에 깔아 확인한다(`build-install-android.command`).
- 보고는 **짧은 한국어**로: 무엇이 바뀌었는지 · 어디를 눌러 보면 되는지 · 오너가 정할 것. 코드 · 파일명 나열 금지.
- 오너가 읽는 문서는 핵심만 보이게 쓴다. 이유 · 근거 · 세부는 `<details><summary>…</summary>` 로 접는다.
- 질문은 **결정이 필요한 것만**, 선택지와 추천을 붙여서 묻는다. 오너가 최종 결정권자다.

## 1. 하네스에서 가져온 규칙

| 규칙 | 내용 | 출처 |
| :--- | :--- | :--- |
| **아동 · 가족 데이터 특칙** | 아이 사진 · 부모 목소리 · 이름은 기기 밖으로 보내지 않는다. 클라우드 LLM · 클라우드 TTS 에 넣지 않는다. 아동 데이터는 예외가 없다 | `[A-06-7]` |
| **비용 0 원칙** | 유료 도구 · 에셋 · 구독 · 종량제 서비스는 쓰기 전에 오너에게 묻고 무료 대안을 같이 낸다 | `[A-01]` |
| **모바일 구조** | Flutter MVVM + Clean Architecture, `presentation → domain ← data`, 상태관리 `provider` | `[B-02]` |
| **주석 · FLOW** | 주석은 한국어로 "왜"를 쓴다. 상태전이 · 저장 메서드에 FLOW 고정번호(`1` 검증 / `2~7` 처리 / `9` 종료) | `[A-02-3.6.1.1]` |
| **에러 · 로그** | `print()` 금지, `AppLogger`, 에러코드 `E-MCR-*`, 로그에 가족 파일 경로 · 내용 금지 | `[A-08]` |
| **문서 동기화** | 코드를 바꾸면 `.project-docs/` 4종 · `STATUS.md` · `CHANGELOG.md` 를 같이 고친다 | `[A-09]` `[A-19]` |
| **AI 는 M3** | M1 · M2 에 AI 를 넣지 않는다. M3 는 GATE 통과 + 처리자 재설계 후 | `[A-22 §6]` |
| **배포 금지** | 에이전트는 배포 명령을 실행하지 않는다. 스토어 배포 안 함(가족 앱) | `[A-04]` |

## 2. 작업 절차 [A-19 요약]

1. 이 파일 → [AGENTS.md](AGENTS.md) → [.project-docs/INDEX.md](.project-docs/INDEX.md) → [STATUS](.project-docs/STATUS.md) 순서로 읽는다.
2. 큰 작업은 `.project-docs/specs/<작업명>/` 에 requirements → design → tasks 로 적고 진행한다(짧게).
3. 만든다 → `flutter analyze` · `flutter test` · `flutter build apk --debug` → 화면이 바뀌면 프로토타입도 맞춘다 → 링크로 보고한다.
4. 문서를 함께 갱신한다 — 최소 `STATUS.md`(한 일 / 할 일)와 `CHANGELOG.md`.
- 확인하지 못한 것은 **미확인**, 돌려 보지 않은 검증은 **미실행**이라고 적는다. 돌리지 않은 테스트를 통과라고 하지 않는다.
- 테스트 · 프로토타입에는 **합성 데이터만** 쓴다. 실제 아이 사진 · 목소리를 저장소에 넣지 않는다.

## 3. Git · 보안 [A-05 · A-06]

- 작업은 브랜치에서 하고 PR 로 올린다. 오너가 PR 을 확인하고 합친다.
- 커밋 메시지: `type(scope): subject` — type 은 feat · fix · docs · style · refactor · test · chore.
- 다른 작업의 변경을 되돌리거나 일괄 스테이징하지 않는다. force · reset · amend 를 편의로 쓰지 않는다.
- **비밀값(키 · 서명 키 · 토큰)은 코드 · 문서 · 커밋에 넣지 않는다.**
- 저장소는 private 유지.

## 4. 문서 위치

| 무엇 | 어디 |
| :--- | :--- |
| 지금 상태 · 할 일 | [.project-docs/STATUS.md](.project-docs/STATUS.md) |
| 문서 지도 · 마일스톤 | [.project-docs/INDEX.md](.project-docs/INDEX.md) |
| 설계 SSOT (ADR 14건) | [.project-docs/1_DESIGN.md](.project-docs/1_DESIGN.md) |
| 화면 설계 · 실행 단계 | [specs/astra-reading/](.project-docs/specs/astra-reading/tasks.md) |
| 화면 프로토타입 (휴대폰용 HTML) | [prototype/](prototype/README.md) |
| 변경 기록 | [CHANGELOG.md](CHANGELOG.md) |
