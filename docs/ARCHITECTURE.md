# Architecture

The iPhone is the single writer for timer state. `TimerStore` serializes actions on the main actor and guards asynchronous effects with a busy flag. Core types depend only on Foundation. There is no backend or third-party runtime SDK.

## Timing and history

A running timer stores a deadline. Pauses close a running interval; resume opens a new one. Completion is reconciled against the deadline, including after relaunch. History snapshots preserve session names, colours and durations even when a preset changes or is deleted. Existing JSON without history remains readable. Updates keep the same on-device state path.

The state file is written atomically. The previous decodable save is kept beside it. A damaged primary file can fall back to that save. If both fail, the UI blocks writes instead of replacing history with an empty state. A previous save is a recovery aid, not a substitute for exporting backups.

Notifications and Live Activities are system-managed presentations. Neither guarantees app execution at the deadline. The app reconciles overdue sessions when it runs again. Focus/Silent Mode and notification permissions affect alerts.

## Export

The Markdown report contains finished sessions, UTC timestamps, active/planned seconds, pauses and outcomes. Names are opt-in. Time ranges select sessions by start date and include their complete active duration. JSON backups use a versioned schema with ISO-8601 dates. Import validates the schema and bounds, skips duplicate IDs and the current session ID, and never replaces preferences or an active timer. Import is additive, not full-device restore.

A share sheet is the only AI integration. The user picks the destination. This avoids credentials, a hosted MCP endpoint and background uploads. A future MCP service would require a separate authenticated bridge, explicit data scope and revocable access; none is exposed here.

## Watch

The watch receives only the current session, preset list and snapshot timestamp. `updateApplicationContext` carries the latest state. Interactive commands use `sendMessage` with a reply; the phone validates the action and expected session UUID before changing anything. Commands are never queued for later. The watch accepts only non-older snapshots and times out requests with an explicit reconnect message. No history is duplicated on the watch. A disconnected watch can show a cached countdown, but needs the phone for actions.

## Signing and publishing

The public project has no team ID, private bundle identifier, device ID or signing material. Developers supply an ignored local xcconfig. The initial public release is a clean snapshot, not the private development Git history. Simulator screenshots must use synthetic data. Never commit build directories, app containers, backups, signing files or local credentials.
