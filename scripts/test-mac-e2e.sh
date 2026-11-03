#!/bin/zsh
# Drives the Mac menu bar app end to end. A harness built from the current sources sends mouse and key events to
# its real status item and drop-down. Each scenario uses its own home folder, so saved timers are never touched.
# A second SimpleTimer item appears in the menu bar while it runs. Results and drop-down images go to DerivedData/MacE2E/out.
set -eu
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
work=DerivedData/MacE2E; app=$work/Harness.app
rm -rf $work; mkdir -p $work/src $work/out $app/Contents/MacOS
cp Core/*.swift Shared/Palette.swift Mac/*.swift Tests/MacE2E/main.swift $work/src/

# Open MenuBarApp's state to the harness, and count the alert permission request instead of showing it.
sed -i '' -e 's/^@main @MainActor final class MenuBarApp/@MainActor final class MenuBarApp/' \
  -e 's/^    private let store = /    let store = /' -e 's/^    private var item: /    var item: /' \
  -e 's/^    private var panel: /    var panel: /' -e 's/^    private var ticker: /    var ticker: /' $work/src/MenuBarApp.swift
sed -i '' 's/_ = try? await center.requestAuthorization(options: \[\.alert, \.sound\])/Hooks.askedForAlerts += 1/' $work/src/MacStore.swift
for pattern in '^@MainActor final class MenuBarApp' '^    let store = ' '^    var item: ' '^    var panel: ' '^    var ticker: '; do
  grep -q "$pattern" $work/src/MenuBarApp.swift || { print -u2 "MenuBarApp.swift changed: update the patches in ${0:t}"; exit 1 }
done
grep -q 'Hooks.askedForAlerts' $work/src/MacStore.swift || { print -u2 "MacStore.swift changed: update the patches in ${0:t}"; exit 1 }

cat > $app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.example.SimpleTimer.mac.harness</string>
<key>CFBundleExecutable</key><string>Harness</string>
<key>CFBundleName</key><string>SimpleTimer Harness</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
xcrun swiftc -swift-version 5 -O -target "$(uname -m)-apple-macos14.0" -sdk "$(xcrun --sdk macosx --show-sdk-path)" $work/src/*.swift -o $app/Contents/MacOS/Harness
codesign -s - --force $app 2>/dev/null

failed=0
run() {
  local scenario=$1 home=$work/home-$1
  [[ -n "${HARNESS_KEEP:-}" ]] || { rm -rf $home; mkdir -p "$home/Library/Application Support" }
  local log=$work/out/$scenario${HARNESS_KEEP:+-again}.log
  CFFIXED_USER_HOME=$PWD/$home HARNESS_SCENARIO=$scenario HARNESS_OUT=$PWD/$work/out $app/Contents/MacOS/Harness > $log 2>&1 || failed=1
  grep -E '^(PASS|FAIL|SUMMARY|TIMEOUT|refusing)' $log || true
}
for scenario in fresh restore paused deadline overdue damaged; do run $scenario; done
# Relaunching after an overdue completion must not save it twice.
HARNESS_KEEP=1 run overdue
exit $failed
