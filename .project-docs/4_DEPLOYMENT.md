# 4_DEPLOYMENT — mychild-reading 배포 문서

> 설계 [1_DESIGN.md](1_DESIGN.md) · 개발 [2_DEVELOPMENT.md](2_DEVELOPMENT.md) · 검증 [3_TEST.md](3_TEST.md)
> 표준 `[A-04]` 배포 · `[A-06]` 보안. 전사 운영 진입점 = `comfunny-total-system` 루트 `OPERATIONS.md`
>
> ⚠️ **에이전트는 배포 명령을 실행하지 않는다** (`[A-04]`). 오너만 실행한다.
> **배포 형태 = 가족 기기에 APK 직접 설치.** 스토어 배포·서버·클라우드 배포 대상이 없다(2026-10-06).

<!-- toc -->

- [4.1 환경 변수 · 자격증명](#41-환경-변수--자격증명)
- [4.2 빌드 · 배포](#42-빌드--배포)
- [4.3 운영](#43-운영)
- [4.4 롤백](#44-롤백)

<!-- tocstop -->

---

## 4.1 환경 변수 · 자격증명

**앱은 환경 변수·API 키·비밀값을 쓰지 않는다.** 네트워크 코드가 없고 Firebase 도 미도입이다.

| 항목 | 현행 | 메모 |
| :--- | :--- | :--- |
| Firebase 설정 파일 3개(`android/app/google-services.json`·`ios/Runner/GoogleService-Info.plist`·`lib/firebase_options.dart`) | 없음 — 이미 `.gitignore` 에 등록돼 있다 | M2c 도입 시 **커밋 금지** `[A-06]`. 없으면 기동 실패(fail-closed)로 만든다 — 기본값으로 진행하면 잘못된 프로젝트에 쓴다 |
| 릴리스 서명 키 | ⚠️ **없음 — release 빌드가 debug 키로 서명된다** | `android/app/build.gradle.kts` 의 Flutter 템플릿 `TODO`(`signingConfig = signingConfigs.getByName("debug")`). **알려진 부채** — 아래 |
| 테스트 빌드 변수 | `MCR_TEST_FONT`·`MCR_ICON_FONT` (선택, 테스트 렌더 전용) | 앱 번들과 무관 |

**알려진 부채 — 릴리스 서명.** 스토어에 올리지 않는 가족 앱이라 지금은 debug 서명으로 설치·업데이트한다.
같은 서명이어야 `install -r` 이 데이터를 유지한다 — 나중에 전용 키로 바꾸면 **서명이 달라 업데이트 설치가 거부**되고,
앱을 지우면 로컬 책이 사라진다(OS 백업도 차단 — ADR-11). 전용 키를 도입할 때는 먼저 `.mcrb` 백업 → 재설치 → 복원 순서를 안내한다.
키 파일(`key.properties`·`*.jks`)은 커밋하지 않는다.

---

## 4.2 빌드 · 배포

### 배포 형태

| 대상 | 방법 |
| :--- | :--- |
| **Android** | **APK 직접 설치** — USB(`build-install-android.command`) 또는 `apk/mychild-reading-debug.apk` 전달(`apk/` 는 `.gitignore`) |
| **iOS** | 오너 기기 직접 빌드(`flutter run --release`, 무료 개인 팀 서명 7일). ❌ 이 맥에서는 빌드 불가 — [2_DEVELOPMENT §2.1](2_DEVELOPMENT.md#21-개발-환경) |
| 스토어 | 하지 않는다 — Zero-Cost `[A-01-2.6]` 상 개발자 계정 비용(Google $25·Apple $99/년)을 들이지 않는다. 필요해지면 ADR 로 승인받는다 |

### 빌드 절차

```bash
# 저장소 루트에서

# 1) 게이트 — 실패하면 빌드하지 않는다
flutter analyze                    # 기대: No issues found!
flutter test                       # 기대: All tests passed!

# 2) Android APK
flutter build apk --debug          # 현행 가족 설치본 (debug 서명)
flutter build apk --release        # 산출물 build/app/outputs/flutter-apk/app-release.apk — 서명은 위 부채 참고

# 3) 설치 — USB 휴대폰 1대 (빌드·전달본 갱신·install -r·실행을 한 번에)
./build-install-android.command
```

### 권한·매니페스트 (설치 전 확인)

| 플랫폼 | 선언 | 왜 |
| :--- | :--- | :--- |
| Android main | `CAMERA`·`RECORD_AUDIO`·`WAKE_LOCK`·`FOREGROUND_SERVICE`·`FOREGROUND_SERVICE_MEDIA_PLAYBACK`. **`INTERNET` 없음** | 촬영·녹음·백그라운드 재생만 필요하다 |
| Android `<application>` | `allowBackup="false"`·`fullBackupContent="false"`·`dataExtractionRules="@xml/data_extraction_rules"` | OS 클라우드 백업·기기 이전 차단 [ADR-11](1_DESIGN.md#14-설계-결정-adr) |
| iOS `Info.plist` | `NSCameraUsageDescription`·`NSMicrophoneUsageDescription`(한국어), `UIBackgroundModes=audio` | — |
| iOS `AppDelegate.swift` | 시작마다 Documents `isExcludedFromBackup=true` | iCloud 백업 차단 (컴파일 미검증 — 3_TEST §3.4) |

> 디버그·프로파일 매니페스트의 `INTERNET` 은 Flutter 개발 도구(핫 리로드)용 템플릿 기본값이다. 가족에게 전달하는 debug APK 에는 들어간다 —
> 앱 코드는 네트워크를 쓰지 않는다. release 로 바꾸면 이 권한이 빠진다.

### M2c 연동 시 (미도입 — 그때 갱신)

Firebase 콘솔 셋업 → `flutterfire configure`(설정 파일 커밋 금지) → `firestore.rules`·`storage.rules` 를 `users/{uid}/**` 본인만 허용으로 작성 → 오너가 규칙 배포.
`allow read: if true` 금지 `[A-06-7]`. 이 절은 도입 시점에 실제 파일 기준으로 다시 쓴다.

---

## 4.3 운영

| 주기 | 항목 | 확인 방법 |
| :--- | :--- | :--- |
| 설치 직후 | 실기기 스모크 | 책 만들기 → 촬영 → 목소리 넣기 → 재생 → 잠금화면 재생 ([3_TEST §3.3](3_TEST.md#33-배포-전-qa-체크리스트)) |
| 수시 | **가족 자료 백업** | 설정 → 백업 파일 → 저장 → 고른 위치의 `.mcrb` 를 다른 곳에 보관. **OS 백업이 막혀 이것이 유일한 백업이다** |
| 업데이트 전 | 백업 | 큰 변경·서명 변경 전 `.mcrb` 저장 |

### 백업 파일 취급

- `.mcrb` 는 **암호화되지 않은** 아이 사진·보호자 녹음 묶음이다. 클라우드 동기화 폴더·메신저로 보내면 그 서비스에 그대로 남는다 — 보관 위치를 사용자가 의식해서 고른다.
- 복원은 합치기가 아니라 **전체 교체**다. 현재 자료가 필요하면 먼저 저장한다. 확인 전 취소하면 바뀌지 않는다.
- 복원 실패 보호 안내가 뜨면 앱을 완전히 종료하고 다시 연다. 앱 시작 시 저널 복구가 먼저 돈다. **`.restore-transaction` 을 수동으로 지우지 않고, 앱을 지우거나 데이터를 초기화하지 않는다.**
- 저장공간은 현재 자료 + 가져온 백업 캐시 + 추출본을 수용해야 한다(원본 보관은 같은 볼륨 rename 이라 추가 복사 없음).
- **iOS 는 백업 경로가 없다** — 기기 분실 = 데이터 손실(ADR-14, 오너 수용 2026-10-06).

### 데이터 파기 `[A-06-7]`

| 대상 | 처리 |
| :--- | :--- |
| 기기 로컬 자료 | 앱 삭제 시 OS 가 앱 디렉토리째 지운다. OS 클라우드 백업에는 남지 않는다(ADR-11) |
| 사용자가 저장한 `.mcrb` | 앱이 관리하지 않는다 — 보관한 위치에서 사용자가 직접 지운다 |
| 클라우드 | 현재 없음. 옛 Firestore 유휴 컬렉션은 `comfunny-total-system` 의 `200-apps-games/apps/AGENTS.md` R-8 오너 결정 대기 |

---

## 4.4 롤백

배포 단위가 **APK 파일**이라 롤백이 단순하다. 위험은 오직 **로컬 데이터 호환성**이다.

| 상황 | 대응 |
| :--- | :--- |
| 새 버전이 오작동한다 | 직전 APK 를 `install -r` 로 다시 설치한다(같은 debug 서명). 오너가 버전별 APK 를 보관한다 |
| APK 가 없다 | 직전 정상 커밋으로 `git checkout` 후 `flutter build apk --debug` 재빌드 |
| 서명 불일치로 설치 거부 | 앱을 지우지 않는다. `.mcrb` 백업 → 재설치 → 복원 순서로 옮긴다 |

> ⚠️ **다운그레이드가 위험하다** — 신버전이 저장한 데이터를 구버전이 못 읽을 수 있다.

| 변경 유형 | 롤백 안전성 |
| :--- | :--- |
| 필드 추가만 | ✅ 안전 — 구버전은 모르는 필드를 무시한다 |
| 필드 삭제·타입 변경·enum 값 추가 | 🔴 위험 — enum 미지값은 폴백되지만 의미가 바뀔 수 있다 |
| `schemaVersion` 증가 | 🟡 구버전은 미래 버전 파일을 **읽지 않고 덮어쓰지 않는다** — 데이터는 보존되나 해당 책이 안 보인다 |

**규칙:** `fromJson` 은 방어적으로 · 스키마를 깨는 변경 전에 `.mcrb` 백업을 유도 · `schemaVersion` 은 M1 부터 유지(현재 1).

### 롤백 후 필수 조치

- [ ] 원인을 [3_TEST §3.4](3_TEST.md#34-검증-기록) 에 기록한다
- [ ] 로컬 데이터가 손상됐으면 `.mcrb` 복원을 안내한다
- [ ] 재설치 전 [3_TEST §3.3](3_TEST.md#33-배포-전-qa-체크리스트) 재통과
