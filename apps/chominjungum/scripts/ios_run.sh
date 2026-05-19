#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/bin:$PATH"
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> CocoaPods 설치 확인 (brew)"
brew install cocoapods

echo "==> pod install"
(cd ios && pod install)

echo "==> flutter pub get"
flutter pub get

echo "==> iOS 실행 (시뮬레이터가 켜져 있거나 자동으로 뜹니다)"
exec flutter run -d ios "$@"
