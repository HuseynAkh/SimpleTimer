# SimpleTimer

A time tracker and focus app for iPhone, built to understand how you work. Optional Pomodoro sessions, an Apple Watch companion, and data export for AI analysis.

Pick a session. Start when you're ready. Nothing starts automatically.

![SimpleTimer on iPhone and Apple Watch: a 25-minute session ready to start](docs/release-images/overview.jpg)

### iPhone

<p>
  <img src="docs/release-images/dashboard-dark.png" alt="Dark timer dashboard" width="230">
  <img src="docs/release-images/activity.png" alt="Activity overview with sample history" width="230">
  <img src="docs/release-images/session-editor.png" alt="Duration and colour editor" width="230">
</p>

### Apple Watch

![Apple Watch gallery: running timer, paused timer and session chooser](docs/release-images/watch-gallery.jpg)

[View the full gallery](docs/GALLERY.md) · Simulator screens with sample data.

## What it does

- Custom sessions, colours and durations.
- Swipe between Activity, Timer and Settings, or tap the page dots.
- System, Light and Dark appearance options.
- Matching pause, end and restart controls. Restart keeps the elapsed session in history.
- Pause, resume and end from the app or a Live Activity.
- Activity charts and searchable history. Paused time doesn't count.
- A report you can attach to ChatGPT, Claude or another AI app.
- JSON history backup and import. Import skips duplicates.
- Apple Watch controls for the timer on your iPhone.

No account, analytics, ads, server or API key. Your history stays on your phone until you choose to export it.

## Build

You need a Mac, Xcode 26 or newer with iOS and watchOS platform support, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
The app supports iOS 17+ and watchOS 10+. Liquid Glass appears on iOS 26+.

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
xcodegen generate
open SimpleTimer.xcodeproj
```

For your own device, put your Apple team ID and a unique bundle ID in `Config/Local.xcconfig`. This file is ignored by Git. Select your iPhone in Xcode and run. Keep the same bundle ID when updating an existing install to keep its data.

A free Apple account requires renewing the app's signing every seven days. Paired devices can install over the same Wi-Fi network. Don't delete the app to renew it.

```sh
./scripts/test-core.sh
./scripts/build-simulator.sh
./scripts/install-iphone.sh YOUR_DEVICE_ID
```

## Export to AI

Open **Activity → Share** or **Settings → Export & backup**. Choose a range, preview the report, then share or save the Markdown file and attach it in your AI app. Session names are hidden by default. Dates and durations are included. Nothing is uploaded in the background.

Use **Save history backup** for a complete JSON copy of finished sessions. Import adds missing sessions; it does not change your current timer or settings. Keep backups private.

## Apple Watch

The companion is a remote, not a second timer. It shows the latest iPhone session and lets you start, pause, resume, end or choose a session. The phone owns the saved history. Changes require a reachable paired iPhone. Session selection responds immediately on the Watch while the phone confirms it, and updates sync in the background. Disconnected timer commands are never queued to run later. Open the iPhone app if the Watch asks you to reconnect.

Sessions use the same colours as iPhone. A checkmark marks your current choice without dimming its name or duration.

Build the `SimpleTimerWatch` scheme for a paired watch simulator or device. The watch app is also embedded in the iPhone build. See [validation](docs/VALIDATION.md) for tested behaviour and limits.

## How it's built

- `Core`: timer state, history, statistics, export and backup. Tested with Swift Package Manager.
- `App`: SwiftUI iPhone screens and local notifications.
- `LiveActivity` / `Shared`: Lock Screen controls and shared activity types.
- `Connectivity` / `WatchApp`: WatchConnectivity remote and watch interface.

See [architecture](docs/ARCHITECTURE.md) and [privacy](PRIVACY.md). MIT licensed.
