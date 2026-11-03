#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -d "$DEVELOPER_DIR" ]]; then
  print -u2 'Install compatible Xcode from Apple first.'
  exit 1
fi
xcodebuild -project SimpleTimer.xcodeproj -scheme SimpleTimerMac -configuration "${CONFIGURATION:-Debug}" -destination 'generic/platform=macOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
