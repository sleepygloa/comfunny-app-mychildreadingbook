# 3_TEST — mychild-reading 테스트 문서

> 설계 [1_DESIGN.md](1_DESIGN.md) · 개발 규약 [2_DEVELOPMENT.md](2_DEVELOPMENT.md) · 배포 [4_DEPLOYMENT.md](4_DEPLOYMENT.md)
> 표준 `[A-07]`. **이 문서는 실측 기준이고 테스트 수치의 정본이다** — 있지도 않은 테스트를 있다고 쓰지 않는다.
>
> ✅ **2026-10-06: `flutter test` 304건 통과 / 14건 보류**, `flutter analyze` No issues, Android debug APK 빌드 성공.
> 🟡 보류 14건 — [알려진 부채](#알려진-부채와-결함). 실기기 E2E 는 남아 있다.

<!-- toc -->

- [3.1 테스트 전략](#31-테스트-전략)
- [3.2 실행 방법](#32-실행-방법)
- [3.3 배포 전 QA 체크리스트](#33-배포-전-qa-체크리스트)
- [3.4 검증 기록](#34-검증-기록)

<!-- tocstop -->

---

## 3.1 테스트 전략

### 무엇을 먼저 덮는가 — 직렬화와 저장

이 앱은 **로컬 우선**이고 기기 밖 백업도 사용자의 `.mcrb` 파일뿐이다. 모든 데이터가 `data.json`·`index/*.json` 으로 오간다.
따라서 **직렬화·원자 저장·복원 트랜잭션이 1순위 리스크**다 — 깨지면 사용자가 만든 책·녹음이 사라진다.
과거 코드 생성기 설정(`explicit_to_json`) 누락으로 중첩 리스트가 조용히 저장되지 않은 사고가 있어 round-trip 을 가장 먼저 쓴다.

| 층 | 도구 | 대상 | 자동화 |
| :--- | :--- | :--- | :--- |
| **정적** | `flutter analyze` | 타입·미사용·린트 | ✅ |
| **단위 — 도메인** | `flutter test test/domain` | 엔티티 JSON round-trip·방어적 파싱 | ✅ |
| **단위 — 데이터** | `flutter test test/data` | JsonStore·저장소·미디어·제작 게시·백업 번들·복원 검증/트랜잭션(별도 프로세스 `exit(73)` 포함)·TTS/오디오 수명 | ✅ 실제 임시 파일 IO |
| **VM·위젯** | `flutter test test/presentation` | 책장·제작·촬영·사진 보정·큐·백그라운드 재생·백업 VM·레이아웃(320/1024폭, 글자 확대) | ✅ (플레이어 위젯 14 보류) |
| **Android 빌드** | `flutter build apk --debug` | 매니페스트·네이티브·플러그인 | ✅ |
| **실기기·에뮬레이터 수동** | 사람 | 카메라·마이크·실제 소리·권한·백그라운드·SAF·OS 백업 차단 | ❌ 수동 (기록 의무) |
| **iOS** | — | 빌드·백업 제외·녹음 | ❌ 이 맥에서 빌드 불가 |

### 수동 검증이 남는 이유

카메라·마이크·기기 TTS·OS 미디어 세션·문서 선택기(SAF)는 **실기기에서만 진짜로 확인된다.** 단위 테스트의 채널 mock·FakeAudio 를 실제 동작 검증으로 간주하지 않는다.
그래서 **"실기기에서 해보기 → 결과를 §3.4 에 날짜와 함께 기록"** 을 검증 계약으로 삼는다(`[A-07]` `[현행]`).

### 단계별 테스트 목표

| 단계 | 필수 테스트 |
| :--- | :--- |
| M1 로컬 MVP | ✅ 자동 테스트 · ⚪ 실기기 한 권 제작→읽기→재시작, 비행기 모드 TTS |
| M2a 안정화 | ✅ 백업→복원 왕복·롤백·재시작 복구(에뮬레이터 실호출 포함) · ⚪ 가족 휴대전화 수락·저장공간 부족 |
| M2b~c | OCR 결과 저장 · 동기화 큐 FIFO·재시도 · 보안 규칙 격리 |
| M3 | 처리자 재설계 후 정의 — 최소: 신청 멱등성 · **처리자 부재 시 기기 TTS·녹음 폴백** `[A-21]` |
| M4 | 클립 구간 계산 · 6각형 집계 |

**커버리지 목표 70%** (`lib/domain`·`lib/data`). 측정은 아직 하지 않았다(`flutter test --coverage` 미실행).

---

## 3.2 실행 방법

```bash
export PATH="/opt/homebrew/bin:$PATH"
# 저장소 루트에서

flutter analyze              # 기대: No issues found!
flutter test                 # 기대: +304 ~14: All tests passed!  (2026-10-06 기준선)
flutter test test/domain     # 직렬화만
flutter build apk --debug    # 기대: ✓ Built build/app/outputs/flutter-apk/app-debug.apk
```

> ⚠️ `flutter test` 출력을 파이프로 넘기면 버퍼링돼 진행이 안 보인다. 멈춤을 진단할 때는
> `flutter test --reporter expanded > "$TMPDIR/mcr-test.log" 2>&1 &` 후 `tail` 로 본다. 좀비가 남으면 `pkill -9 -f flutter_tester`.
>
> 레이아웃 렌더 테스트는 선택적으로 `MCR_TEST_FONT`·`MCR_ICON_FONT` 환경변수로 로컬 한글·아이콘 폰트를 읽는다(앱 번들에는 넣지 않는다).

### 실기기 · 에뮬레이터

설치·실행 명령은 [2_DEVELOPMENT §2.1 개발용 실행 도구](2_DEVELOPMENT.md#21-개발-환경). 권한(카메라·마이크) 허용·거부 양쪽 UI 를 확인한다.
테스트에는 **합성 데이터만** 쓰고 실제 가족 책·목소리를 로그나 외부 도구로 수집하지 않는다.

**OS 백업 차단 확인(2026-10-06 추가, 미실행):**

```bash
# Android — 앱 백업 대상 여부 (기대: allowBackup=false 로 백업 대상 아님)
"$HOME/Library/Android/sdk/platform-tools/adb" shell dumpsys package com.comfunny.mychild_reading | grep -i backup
```

iOS 는 Xcode 로 실기기 빌드 후 설정 → Apple ID → iCloud → 저장 공간 관리 → 백업에서 "작은 도서관" 용량이 0 에 가까운지 본다.

---

## 3.3 배포 전 QA 체크리스트

`[A-07]` + 이 앱 특이사항. 배포 절차는 [4_DEPLOYMENT §4.2](4_DEPLOYMENT.md#42-빌드--배포).

### 정적·자동

- [ ] `flutter analyze` — No issues
- [ ] `flutter test` — 전건 통과(보류 수가 늘지 않았는가)
- [ ] `flutter build apk --debug` 성공

### 데이터 안전 (로컬 우선 앱의 최대 리스크)

- [ ] 직렬화 round-trip 전 엔티티 통과
- [ ] 앱 강제 종료 후 재실행 시 데이터가 남아 있는가
- [ ] **`.mcrb` 백업 저장 → 다른 기기/초기화 후 복원** 왕복으로 사진·녹음·플레이리스트가 온전한가
- [ ] 복원 확인창 취소 시 현재 책장이 그대로인가

### 실기기 기능

- [ ] 표지 촬영 · 본문 가로 연속 촬영 · 자르기/보정 · 순서 변경 · 삭제
- [ ] 목소리 넣기 → 녹음 → 재생 (녹음 중 앱 전환 처리)
- [ ] 기기 TTS — Android 오프라인 한국어 음성 설치 상태, 비행기 모드에서 재생
- [ ] 공통 큐 — 화면 잠금·홈 연속 재생, 알림 pause/play/이전·다음/stop, 통화·이어폰 분리 정지
- [ ] 권한 거부 상태의 안내·재시도

### 아동 개인정보 `[A-06-7]`

- [ ] 릴리스 매니페스트에 `INTERNET` 이 없는가 (네트워크 기능을 넣는 변경이면 ADR 로 결정했는가)
- [ ] `allowBackup="false"`·`dataExtractionRules` 가 병합 매니페스트에 남아 있는가 (`build/app/intermediates/merged_manifests/*/…/AndroidManifest.xml`)
- [ ] iOS `AppDelegate.swift` 의 백업 제외 호출이 남아 있는가
- [ ] 로그·오류 안내에 가족 파일 경로·내용이 없는가
- [ ] (M2c 이후) Firestore·Storage 경로가 전부 `users/{uid}/**`, `allow read: if true` 없음
- [ ] (M3 이후) 작업 페이로드에 아이 이름·생일 없음 · 목소리 샘플 전달 후 삭제

### 문서 `[A-19]` 단계 4

- [ ] `1_DESIGN` 데이터 모델·Mermaid 와 코드 일치 · `2_DEVELOPMENT` 폴더 구조 일치
- [ ] 이 문서 §3.4 에 수치·근거 기록

---

## 3.4 검증 기록

**이것이 회귀 방지 원장이다.** "통과했다"만 쓰지 않고 무엇을 어떻게 확인했는지 적는다. 2026-09 단계별 일지는 아래 표로 접었다(상세 로그는 당시 임시 파일이라 남아 있지 않다).

| 일자 | 대상 | 결과 | 근거·비고 |
| :--- | :--- | :--- | :--- |
| 2026-09-12 | 툴체인·첫 구현 | ✅ analyze clean · test 147 통과 | Flutter 3.47.3 / Dart 3.13.3 |
| 2026-09-15 | 플레이어 추가 · 첫 APK | ✅ 176 통과 / 🟡 14 보류 · `app-debug.apk` 159MB | JDK 17·cmdline-tools 설치. 라이선스 미승인 6건은 빌드 무관 |
| 2026-09-19 | Astra 1-1 · 1-2 · 1-4 | ✅ 200 → 217 → 235 통과 / 14 보류 · APK 성공 | 초안·읽던 위치 실제 IO 24건, 제작·게시 17건, 큐·플레이리스트 18건. SM-S938N USB 설치·시작만 확인 |
| 2026-09-20 | 1-5 · 2-1 · 공통 플레이어 · 책 등록·연속 촬영·사진 보정 | ✅ 238 → 262 → 280 → 282 → 287 → 292 통과 / 14 보류 · APK 성공 | 대비 5.63~12.94:1, 320×740·글자 1.6~1.8배. 에뮬레이터 `MyChildReading_API36` 설치·필수 입력 안내 확인. 실물 촬영·소리는 미검증 |
| 2026-09-22 | 2-2a 백업 파일 저장·검사 | ✅ 310 통과 / 14 보류 · APK 성공 | 번들 13 + VM 5. USB 기기 없음 → 실제 SAF 미검증 |
| 2026-09-28 | 2-2b 현재 책장 복원 | ✅ 353 통과 / 14 보류 · APK 성공 | 신규 43(트랜잭션 21·gate 3·validator 13·VM 6). 별도 Dart 프로세스를 7지점에서 `exit(73)` 후 복구 확인. 에뮬레이터 `MCR_Restore_Test_API36` 에서 합성 `.mcrb` SAF 저장·검사·복원·취소·재시작 실호출 |
| **2026-10-06** | **죽은 코드 정리 · OS 백업 차단** | ✅ **304 통과 / 14 보류** · analyze **No issues** · `flutter build apk --debug` 성공(Gradle 222초, 169MB) | 353 → 304: 삭제한 화면 테스트 3파일 49건(`library_screen`·`content_edit_screen`·`content_edit_view_model`). 병합 매니페스트에 `allowBackup="false"`·`fullBackupContent="false"`·`dataExtractionRules` 확인. 삭제 심볼 `git grep` 참조 0 |
| 2026-10-06 | iOS 백업 제외(`AppDelegate.swift`) | ⚪ **미실행** — Swift 컴파일·실기기 확인 안 됨 | 이 맥은 `xcode-select` 가 CLT 를 가리켜 iOS 빌드 불가. 표준 API(`URLResourceValues.isExcludedFromBackup`)만 사용 |
| 2026-10-06 | Android OS 백업 실제 차단 | ⚪ **미실행** | §3.2 `dumpsys` 확인 절차 — 기기 연결 시 |
| **2026-11-22** | **주제 · 즐겨찾기 · 모아보기 1차** | ✅ **318 통과 / 14 보류** · analyze **No issues** · APK ⚪ **미실행** | 신규 14건: 직렬화 · 방어 파싱 7(`book_tags_test`) · 꼬리표 · 모아보기 · 백업 검사 6(`catalog_tags_test`) · 화면 1(별 → 모아보기, ⚙ 거르기). 클라우드 리눅스 작업 환경 — Android SDK 없음. 이관 직후 기준 304 → 318. 화면 테스트 2건이 맥 경로 `/private/tmp` 에 스크린샷을 써서 리눅스에서는 그 폴더를 만들어야 통과한다 |
| — | 실기기 E2E(촬영·녹음·소리·비행기 모드·잠금화면·가족 기기 복원) | ⚪ **미검증** | 사용자 요청으로 보류 중 |

### 알려진 부채와 결함

**`player_screen_test.dart` 14건 보류 (2026-09-15~)**

| 항목 | 내용 |
| :--- | :--- |
| 증상 | 첫 케이스에서 러너가 끝나지 않는다. 테스트 타임아웃조차 뜨지 않는다 → 러너/플러그인 계층 멈춤으로 추정 |
| 시도 | `pumpAndSettle` → `pump(Duration)`, `dispose()` 의 `context.read` 제거 — 둘 다 옳은 수정이지만 멈춤은 남았다 |
| 조치 | `group(..., skip: ...)` (`player_screen_test.dart:324`). 화면 로직은 `PlayerViewModel`·큐 테스트가 덮는다 |
| 재개 조건 | 실기기 검증 단계에서 원인 재조사. `skip:` 만 지우면 복구된다 |

**이 부채에서 남긴 규칙:** `dispose()` 에서 `context.read` 를 쓰지 않는다 · `Image.file` 이 있는 화면 테스트에 `pumpAndSettle` 을 쓰지 않는다.

**도메인·데이터 테스트가 막는 사고**

| 검증 항목 | 막는 사고 |
| :--- | :--- |
| `jsonEncode`/`jsonDecode` 를 통과시킨 round-trip | JSON 표현 불가 값(DateTime 객체 등)이 섞여도 통과하는 함정 |
| 중첩 3단 보존 (`Content`→`BookPage`→`AudioTrack`) | 중첩 리스트가 조용히 저장되지 않는 사고 |
| 모르는 enum 값 → fallback · 미래 `schemaVersion` 거부 | 다운그레이드 시 책이 사라지거나 덮어써지는 사고 |
| 임시파일 → rename · 복원 저널 롤백 | 쓰는 중·교체 중 종료로 절반만 남는 사고 |
| 백업 manifest 경로 순회·심볼릭 링크·상한 거부 | 조작된 `.mcrb` 로 앱 밖 경로를 쓰는 사고 |
