#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ $# != 1 ]]; then
  print -u2 'Usage: ./scripts/install-iphone.sh <device-identifier>'
  xcrun devicectl list devices
  exit 1
fi
simpletimer_device="$1"
xcodebuild -project SimpleTimer.xcodeproj -scheme SimpleTimer -configuration Debug -destination "id=$simpletimer_device" -derivedDataPath DeviceBuild -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device "$simpletimer_device" DeviceBuild/Build/Products/Debug-iphoneos/SimpleTimer.app
simpletimer_bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' DeviceBuild/Build/Products/Debug-iphoneos/SimpleTimer.app/Info.plist)
xcrun devicectl device process launch --device "$simpletimer_device" "$simpletimer_bundle"
