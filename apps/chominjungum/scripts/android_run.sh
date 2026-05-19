#!/usr/bin/env bash
# Lenovo 등 실기기에 학생 앱 실행. USB 디버깅·adb 연결 후 사용.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export PATH="$PATH:$ANDROID_HOME/platform-tools"

# Gradle이 android/를 projectDir로 쓰는 구조 보정 (최초 1회)
[[ -L android/pubspec.yaml ]] || ln -sf ../pubspec.yaml android/pubspec.yaml
[[ -L android/lib ]] || ln -sf ../lib android/lib
[[ -L android/assets ]] || ln -sf ../assets android/assets

flutter pub get

DEVICE="${1:-}"
ARGS=(run --flavor student)
if [[ -n "$DEVICE" ]]; then
  ARGS+=(-d "$DEVICE")
fi

flutter "${ARGS[@]}"
