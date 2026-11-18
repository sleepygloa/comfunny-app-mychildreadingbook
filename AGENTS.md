# mychild-reading — 로컬 에이전트 지침

> **상세 문서:** [.project-docs/INDEX.md](.project-docs/INDEX.md) → 설계 SSOT [1_DESIGN.md](.project-docs/1_DESIGN.md)
> **전사 표준:** 하네스 `sleepygloa/comfunny-standard-docs` 의 `claude/` (원문). 이 앱에 필요한 것만 [CLAUDE.md §1](CLAUDE.md) 에 옮겼다
>
> ⚠️ **아동 대상 앱이다.** `[A-06-7]` 아동·가족 개인정보 특칙이 설계의 근간이다 (§3).
> 🔄 **로컬 MVP 진행 중 — 코드가 있다.** 진행 현황은 [INDEX](.project-docs/INDEX.md#지금-어디까지-왔나), 테스트 수치는 [3_TEST §3.4](.project-docs/3_TEST.md#34-검증-기록) 가 정본이다(수치를 여기에 복제하지 않는다).
> 2026-11-18 `comfunny-total-system/200-apps-games/apps/01-mychild-reading/` 에서 이 독립 저장소로 옮겼다. 지금 상태는 [STATUS](.project-docs/STATUS.md).

## 1. 이 프로젝트는

집에 있는 종이책을 사진으로 찍어 디지털화하고, **부모 목소리로 읽어주는** 가족용 앱("작은 도서관").
보호자가 촬영·녹음하고 아이가 재생한다. 공개 서비스가 아니다.

- **스택:** Flutter 3.47.3 · **`provider`**(`ChangeNotifier`) · `get_it` · `go_router` · 로컬 JSON + 미디어 파일 · 기기 TTS(`flutter_tts`) · `audio_service`.
  **freezed·Riverpod·Firebase 없음** — Firebase 는 M2c 연동 계획이며 미도입
- **네트워크 0:** 네트워크 호출 코드가 없고 릴리스 매니페스트에 `INTERNET` 이 없다. 기기 밖 경로는 사용자가 저장 위치를 고르는 `.mcrb` 백업 파일뿐(Android)
- **구성:** Flutter 앱이 **모듈 루트에 직접** 있다 (`app/` 중첩 없음 — [ADR-10](.project-docs/1_DESIGN.md#14-설계-결정-adr))
- **AI(M3):** **처리자 미정** — 설계 당시 처리자(101 로컬 GPU 워커)는 2026-10-05 폐지됐다. M3 착수 시 처리자·잡 계약을 재설계한다

| M1 | M2 | M3 | M4 |
| :--- | :--- | :--- | :--- |
| 책장·촬영·부모녹음·기기TTS·플레이어 | 백업·OCR·다자녀·인증/동기화 | 부모목소리 AI (처리자 미정) | 동영상·6각형 통계 |

## 2. 로컬 실행

```bash
export PATH="/opt/homebrew/bin:$PATH"
# 저장소 루트에서

flutter pub get
flutter analyze            # 기대: No issues found!
flutter test               # 기대: All tests passed! (player_screen_test 14건 skip — 3_TEST 부채)
flutter build apk --debug  # 기대: ✓ Built build/app/outputs/flutter-apk/app-debug.apk
```

> 카메라·마이크·기기TTS·백그라운드 재생은 실기기에서만 진짜로 확인된다 — USB 설치는 `build-install-android.command`.
> iOS 빌드는 `xcode-select` 가 CLT 를 가리켜 이 맥에서 막혀 있다(Xcode.app 자체는 설치됨).

## 3. 이 프로젝트만의 규칙

| 규칙 | 내용 | 왜 |
| :--- | :--- | :--- |
| **상태관리 = `provider`** | `ChangeNotifier` + `MultiProvider`. 화면당 VM 1개. 저장소·서비스는 `get_it` | `[B-02]` `[현행]` 표준. **Riverpod 금지** — 과거 설계였으나 `[확장]` 항목이다 (ADR-2) |
| **기기 밖으로 보내지 않는다** | 네트워크·클라우드 기능을 넣으려면 먼저 ADR 로 결정한다(`INTERNET` 권한 추가 = 설계 변경) | 아동 사진·부모 목소리다 `[A-06-7]` (ADR-1) |
| **OS 클라우드 백업 차단 유지** | Android `allowBackup=false`·`dataExtractionRules`, iOS `AppDelegate.swift` 의 `isExcludedFromBackup` 을 지우지 않는다 | 2026-10-06 오너 결정 (ADR-11) |
| **클라우드 AI 금지** | 책 본문·목소리를 외부 AI·TTS 서비스로 보내지 않는다. AI 합성은 **로컬에서만** | 아동 앱이다. `[A-06-7]` 은 TTS 를 조건부 허용하지만 오너가 배제를 택했다 (ADR-4) |
| **AI 는 M3** | M1·M2 에 AI 를 넣지 않는다. M3 는 GATE + 처리자 재설계 후 | `[A-22 §6]` — 데이터 구조가 흔들리는 중에 음원을 만들면 전부 무효가 된다 (ADR-3) |
| **`AudioSource` 4종 선정의** | `deviceTts`·`parentRecording`·`aiClonedVoice`·`aiNarration`. 구현은 단계별 | 나중에 값 추가 = 포맷 마이그레이션 (ADR-6) |
| **`schemaVersion` 필수** | 모든 JSON 은 `{schemaVersion, data}` 봉투(현재 1). 미래 버전은 읽지도 덮어쓰지도 않는다 | 다운그레이드 시 데이터 유실 방지 |
| **`fromJson` 방어적으로** | 모르는 필드 무시 · 없는 필드 기본값 · enum 미지값은 폴백 | 구버전이 신버전 데이터를 만나도 죽지 않아야 한다 |
| **새 저장 루트 = 백업도 수정** | `AppPaths` 에 루트를 추가하면 백업 허용 루트·`RestoreValidator` 도 함께 고친다 | 빠뜨리면 백업에서 조용히 빠지거나 복원이 거절된다 |
| **`print()` 금지** | `AppLogger.d/i/w/e`. 에러코드 `E-MCR-*`. 로그에 가족 파일 경로·내용 금지 | `[A-08]` · `[A-06]` |
| **FLOW 주석** | 상태전이·저장소 변경 메서드에 `1` 검증 / `2~7` 처리 / `9` 종료 | `[A-02-3.6.1.1]` |

**도메인 용어**

| 용어 | 정의 |
| :--- | :--- |
| `Content` | 읽을 수 있는 것 하나. `type` 으로 책(`pagedBook`)·영상(`video`) 구분 |
| `Series` | 전집 (출판사 → 전집 → 책 번호 3단) |
| `BookPage` / `AudioTrack` | 펼친 면 사진 한 장 / 그 페이지의 오디오 하나. 페이지는 **여러 트랙을 동시 보유** |
| `BookDraft` | 만들던 책(초안). 게시 전까지 `drafts/` 에 있다 |
| `PlaybackQueue` | 앱 전체가 공유하는 현재 재생 큐. 저장 `Playlist` 와 독립 |
| `.mcrb` | 단일 백업 파일(`MCRB0001`). 암호화 없음 |
| `VoiceProfile` · `ChildProfile` · `GrowthDimensions` | M2~M4 선정의 — 화면 없음 |
| `ReadingEvent` | 재생 1회 기록. **M1 부터 쌓고** 화면은 M4 |

## 4. 함정

- **앱 삭제 = 가족 자료 삭제.** OS 백업을 막았으므로 `.mcrb` 가 유일한 백업이다. 서명 불일치로 설치가 거부돼도 앱을 지우지 않는다.
- **iOS 는 백업 경로가 없다**(백업 버튼 비활성 + iCloud 차단) — 기기 분실 = 데이터 손실. 오너 수용(ADR-14).
- **release 빌드는 debug 키로 서명된다**(템플릿 TODO, 알려진 부채 — [4_DEPLOYMENT §4.1](.project-docs/4_DEPLOYMENT.md#41-환경-변수--자격증명)). 전용 키로 바꾸면 업데이트 설치가 막힌다.
- **기기 TTS 트랙에는 파일이 없다** (`path = null`). 런타임 합성이라 백업에 담기지 않고 재생 길이를 미리 알 수 없다.
  Android 는 `network_required=0` 음성만 쓰고, iOS 는 오프라인 여부를 확인할 수 없어 쓰지 않는다(녹음 안내).
- **트랙 우선순위에서 `deviceTts` 가 마지막인 이유** — 텍스트만 있으면 항상 만들 수 있는 **최후의 폴백**이다.
- **`.restore-transaction/` 을 지우지 않는다.** 앱 시작 시 저장소 등록 **전에** 저널 복구가 돈다.
- **삭제 순서** — 메타데이터 먼저, 파일 나중. **JSON 쓰기는 임시파일 → rename.**
- **열리지 않는 화면을 만들지 않는다.** 2026-10-06 라우트가 없던 `LibraryScreen`·`ContentEditScreen` 을 지웠다 — 화면을 만들면 진입점과 테스트를 함께 단다.
- **구현하지 않은 것을 구현했다고 쓰지 않는다.** 미완은 `⚪ 미구현`, 실행하지 않은 검증은 미실행으로 표기한다.

## 5. AI 없을 때 체크리스트 (A-21 §4.2)

**AI 있을 때 (30초):** `code-reviewer` + `security-manager` 에이전트 호출 → 통합 리포트

**AI 없을 때 (15~20분):**
- [ ] [1_DESIGN](.project-docs/1_DESIGN.md) 데이터 모델과 코드가 일치 · 마일스톤 범위를 벗어나지 않았는가
- [ ] 계층 방향 단방향인가 — `presentation → domain ← data`. **`domain` 이 Flutter 를 모르는가**
- [ ] `provider` 규약 — `build()` 안에서 상태 변경 없음 · 콜백은 `read` · `dispose()` 해제
- [ ] FLOW 고정번호 주석 `[A-02-3.6.1.1]` · 한국어 "왜" 주석
- [ ] `print()` 없음 · 에러코드 `E-MCR-*` `[A-08]`
- [ ] **직렬화 round-trip 테스트**를 함께 썼는가 · `schemaVersion` 유지 · `fromJson` 방어적
- [ ] **릴리스 매니페스트에 `INTERNET` 이 없고, OS 백업 차단 속성·`AppDelegate` 호출이 남아 있는가** `[A-06-7]`
- [ ] **아이 이름·생일이 외부로 나가는 경로가 없는가** `[A-06-7]`
- [ ] 새 의존성을 넣었다면 **라이선스를 문서에 적었는가** `[A-01-2.6]`
- [ ] `flutter analyze` + `flutter test` + `flutter build apk --debug` · **실기기 확인 → [3_TEST §3.4](.project-docs/3_TEST.md#34-검증-기록) 기록**
- [ ] 4대 문서 + Mermaid 갱신 `[A-19]` 단계 4

## 6. 배포

⚠️ **에이전트는 배포 명령을 실행하지 않는다** (`[A-04]`).

- **스토어 배포 안 함** — 가족 단위 개인 앱. Android 는 **APK 직접 설치**(`build-install-android.command`), iOS 는 오너 기기 직접 빌드
- **서버·보안 규칙 배포 대상 없음** — Firebase 미도입
- **롤백:** 직전 APK `install -r` 재설치. ⚠️ **다운그레이드가 위험하다** — [4_DEPLOYMENT §4.4](.project-docs/4_DEPLOYMENT.md#44-롤백)
- **가족 자료 백업·파기** — [4_DEPLOYMENT §4.3](.project-docs/4_DEPLOYMENT.md#43-운영)
