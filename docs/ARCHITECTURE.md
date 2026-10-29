# Architecture

The iPhone is the single writer for timer state. `TimerStore` validates, changes and atomically saves a timer action in one main-actor turn. It then schedules notifications and Live Activities through a serial, coalescing effects queue. Watch acknowledgements and UI interaction never wait for those system effects or notification permission dialogs. Core types depend only on Foundation. There is no backend or third-party runtime SDK.

## Timing and history

A running timer stores a deadline. Pauses close a running interval; resume opens a new one. Completion is reconciled against the deadline, including after relaunch. History snapshots preserve session names, colours and durations even when a preset changes or is deleted. Existing JSON without history remains readable. Updates keep the same on-device state path.

All timer surfaces use the same core action handler. Reset replaces the current attempt with a fresh, stopped session at its full configured duration. It does not reconcile or archive that attempt; existing saved history, including legacy reset records, stays intact. The old `restart` action is a reset-only compatibility alias. Only an explicit Start begins a new attempt. End still saves elapsed time, and switching to a different session saves the interrupted attempt. Pending completion alerts and Live Activities are cleared when resetting.

The state file is written atomically. The previous decodable save is kept beside it. A damaged primary file can fall back to that save. If both fail, the UI blocks writes instead of replacing history with an empty state. A previous save is a recovery aid, not a substitute for exporting backups.

Notifications and Live Activities are system-managed presentations. Neither guarantees app execution at the deadline. The app reconciles overdue sessions when it runs again. Focus/Silent Mode and notification permissions affect alerts.

## Export

The Markdown report contains finished sessions, UTC timestamps, active/planned seconds, pauses and outcomes. Names are opt-in. Time ranges select sessions by start date and include their complete active duration. JSON backups use a versioned schema with ISO-8601 dates. Import validates the schema and bounds, skips duplicate IDs and the current session ID, and never replaces preferences or an active timer. Import is additive, not full-device restore.

A share sheet is the only AI integration. The user picks the destination. This avoids credentials, a hosted MCP endpoint and background uploads. A future MCP service would require a separate authenticated bridge, explicit data scope and revocable access; none is exposed here.

## Watch

The Watch caches only confirmed phone state: the current session, presets, snapshot time, a persisted phone revision and the most recent command receipt. The iPhone activates WatchConnectivity at app startup, including background launches. A reachable Watch gets immediate state messages; `updateApplicationContext` also carries the latest state for background delivery. Both companions refresh when reachability returns.

Timer commands use `sendMessage` with an expected session UUID, unique command ID and eight-second expiry. The phone validates the command and saves the timer before acknowledging it. The acknowledgement travels in both the direct reply and state broadcasts, so a lost reply does not leave the Watch waiting after a successful change. Duplicate delivery of the most recently acknowledged command is harmless; older commands cannot affect a replacement session. Every rejection includes the latest state.

The Watch orders snapshots by phone revision, accepts command receipts independently of delivery order, and ignores late errors for already-confirmed commands. Background refreshes do not lock controls. Selection is previewed locally; rapid taps keep only the latest unsent selection, sent against the confirmed session after the previous selection completes. A timeout drops that unsent selection and triggers a read-only refresh. Timer commands are never automatically retried or stored for disconnected delivery. Only confirmed snapshots are persisted, and the Sessions screen observes them directly.

No history is duplicated on the Watch. A disconnected Watch can show a cached countdown, but needs the phone for changes. This keeps one timer and one history without competing offline writers. System reachability and background execution still depend on watchOS/iOS. Simulator tests do not establish a latency guarantee for physical Bluetooth or Wi-Fi.

Apple references: [interactive messages](https://developer.apple.com/documentation/watchconnectivity/wcsession/sendmessage(_:replyhandler:errorhandler:)), [application context](https://developer.apple.com/documentation/watchconnectivity/wcsession/updateapplicationcontext(_:)), [reachability changes](https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate/sessionreachabilitydidchange(_:)).

## Signing and publishing

The public project has no team ID, private bundle identifier, device ID or signing material. Developers supply an ignored local xcconfig. The initial public release is a clean snapshot, not the private development Git history. Simulator screenshots must use synthetic data. Never commit build directories, app containers, backups, signing files or local credentials.
