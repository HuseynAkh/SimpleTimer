#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -d "$DEVELOPER_DIR" ]]; then
  print -u2 'Install compatible Xcode from Apple and its iOS simulator runtime first.'
  exit 1
fi
xcodebuild -project SimpleTimer.xcodeproj -scheme SimpleTimer -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
