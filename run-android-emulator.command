#!/bin/bash
# macOS에서 더블클릭. 라이선스는 사용자가 직접 읽고 수락한다.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
SDKMANAGER="$SDK_DIR/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="$SDK_DIR/cmdline-tools/latest/bin/avdmanager"
EMULATOR="$SDK_DIR/emulator/emulator"
ADB="$SDK_DIR/platform-tools/adb"
IMAGE='system-images;android-36;google_apis;arm64-v8a'
AVD='MyChildReading_API36'
SERIAL='emulator-5556'
APK="$PROJECT_DIR/apk/mychild-reading-debug.apk"
LOG="${TMPDIR:-/tmp/}mychild-reading-emulator.log"

finish() {
  result=$?
  if [[ "$result" != 0 ]]; then
    echo "실행하지 못했습니다. 위 오류를 확인해 주세요. 로그: $LOG"
  fi
  echo 'Enter를 누르면 이 터미널 창의 작업을 마칩니다. 에뮬레이터는 계속 열려 있습니다.'
  read -r _ || true
}
trap finish EXIT

for executable in "$SDKMANAGER" "$AVDMANAGER" "$EMULATOR" "$ADB"; do
  [[ -x "$executable" ]] || { echo "도구가 없습니다: $executable"; exit 1; }
done
if [[ ! -f "$APK" ]]; then
  APK="$PROJECT_DIR/build/app/outputs/flutter-apk/app-debug.apk"
fi
[[ -f "$APK" ]] || { echo 'APK가 없습니다. 먼저 Android debug APK를 빌드해 주세요.'; exit 1; }
if [[ -x /opt/homebrew/opt/openjdk@17/bin/java ]]; then
  export JAVA_HOME=/opt/homebrew/opt/openjdk@17
fi

if [[ ! -f "$SDK_DIR/system-images/android-36/google_apis/arm64-v8a/system.img" ]]; then
  echo 'Android 시스템 이미지를 설치합니다. 표시되는 라이선스를 읽고 동의하면 직접 y를 입력하세요.'
  "$SDKMANAGER" "$IMAGE"
  [[ -f "$SDK_DIR/system-images/android-36/google_apis/arm64-v8a/system.img" ]] || {
    echo '시스템 이미지가 설치되지 않았습니다. 동의를 거절하면 여기서 종료합니다.'; exit 1;
  }
fi
if ! "$EMULATOR" -list-avds | grep -Fxq "$AVD"; then
  # no는 사용자 정의 하드웨어 프로필 질문의 답이며 라이선스 수락과 무관하다.
  printf 'no\n' | "$AVDMANAGER" create avd -n "$AVD" -k "$IMAGE" -d pixel_6
fi
"$ADB" start-server
if "$ADB" devices | grep -q "^$SERIAL[[:space:]]"; then
  running_avd="$("$ADB" -s "$SERIAL" emu avd name | tr -d '\r' | head -n 1)"
  [[ "$running_avd" == "$AVD" ]] || {
    echo "포트 5556에서 다른 가상 기기가 실행 중입니다: $running_avd"; exit 1;
  }
else
  echo '작은 도서관 테스트용 Pixel 6를 시작합니다.'
  nohup "$EMULATOR" -avd "$AVD" -port 5556 -camera-front none -camera-back emulated > "$LOG" 2>&1 &
fi

echo '가상 기기 부팅을 기다립니다(최대 3분).'
booted=false
for ((attempt=0; attempt<90; attempt++)); do
  if [[ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)" == 1 ]]; then
    booted=true
    break
  fi
  sleep 2
done
[[ "$booted" == true ]] || { echo "부팅 시간 초과. 로그: $LOG"; exit 1; }
# 실제 휴대전화에는 명령을 보내지 않는다. 삭제 없이 에뮬레이터에 업데이트 설치한다.
"$ADB" -s "$SERIAL" install -r "$APK"
"$ADB" -s "$SERIAL" shell input keyevent 82
"$ADB" -s "$SERIAL" shell am start -W -n com.comfunny.mychild_reading/.MainActivity
echo '작은 도서관을 실행했습니다. 에뮬레이터 화면에서 조작해 주세요.'
