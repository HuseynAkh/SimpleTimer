#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
if xcrun --find xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
  swift test --disable-sandbox
else
  mkdir -p .build
  swiftc -parse-as-library -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" Core/*.swift Tests/TimerCoreTests/TimerCoreTests.swift -o .build/core-tests
  .build/core-tests
fi
