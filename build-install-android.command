#!/bin/bash
# Mac Finder에서 더블클릭: 최신 APK 빌드 → USB 휴대폰 업데이트 → 앱 실행.
set -euo pipefail

finish() {
  local result=$?
  trap - EXIT
  if (( result != 0 )); then
    echo
    echo "작업을 완료하지 못했습니다. 위 오류를 확인해 주세요. 앱을 삭제하지는 않습니다."
  fi
  if [[ -t 0 ]]; then
    echo
    read -r -p "Enter를 누르면 마칩니다. " _answer || true
  fi
  exit "$result"
}
trap finish EXIT

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ "${1:-}" == "--help" ]]; then
  echo "USB 디버깅을 허용한 Android 휴대폰 한 대를 연결하고 이 파일을 더블클릭하세요."
  echo "최신 debug APK 빌드 → apk/mychild-reading-debug.apk 갱신 → 데이터 유지 설치 → 실행"
  echo "에뮬레이터는 설치 대상에서 제외합니다. 빌드/설치 실패 시 중단합니다."
  exit 0
fi

sdk_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
adb_bin="$sdk_dir/platform-tools/adb"
if [[ ! -x "$adb_bin" ]]; then
  echo "Android SDK의 adb를 찾지 못했습니다: $adb_bin"
  exit 1
fi
flutter_bin="$(command -v flutter || true)"
if [[ -z "$flutter_bin" && -x /opt/homebrew/bin/flutter ]]; then
  flutter_bin=/opt/homebrew/bin/flutter
fi
if [[ -z "$flutter_bin" && -x /opt/homebrew/share/flutter/bin/flutter ]]; then
  flutter_bin=/opt/homebrew/share/flutter/bin/flutter
fi
if [[ -z "$flutter_bin" ]]; then
  echo "Flutter를 찾지 못했습니다. Flutter 설치 경로를 확인해 주세요."
  exit 1
fi
# Finder에서 실행해도 Flutter가 Homebrew git 등의 도구를 찾을 수 있게 한다.
export PATH="$(dirname -- "$flutter_bin"):/opt/homebrew/bin:/usr/local/bin:$PATH"

echo "1/4 USB 휴대폰을 확인합니다. 잠금을 풀고 USB 디버깅을 허용해 주세요."
if ! "$adb_bin" -d get-state; then
  echo "USB 휴대폰 한 대만 연결해 주세요. 휴대폰의 디버깅 허용 창도 확인해 주세요."
  exit 1
fi
# 빌드 중 연결 대상이 바뀌어도 다른 휴대폰에 설치하지 않는다.
device_serial="$("$adb_bin" -d get-serialno)"
if [[ -z "$device_serial" || "$device_serial" == unknown ]]; then
  echo "설치할 휴대폰을 확인하지 못했습니다."
  exit 1
fi

echo "2/4 최신 앱을 빌드합니다."
"$flutter_bin" build apk --debug
mkdir -p apk
cp build/app/outputs/flutter-apk/app-debug.apk apk/mychild-reading-debug.apk

echo "3/4 기존 데이터를 유지하면서 업데이트 설치합니다."
"$adb_bin" -s "$device_serial" install -r apk/mychild-reading-debug.apk

echo "4/4 휴대폰에서 작은 도서관을 엽니다."
"$adb_bin" -s "$device_serial" shell am start -W -n com.comfunny.mychild_reading/.MainActivity

echo
echo "완료! 휴대폰에서 확인하세요. USB를 빼도 앱을 사용할 수 있습니다."
echo "APK: $PWD/apk/mychild-reading-debug.apk"
