# Validation

Checked with Xcode 27, an iOS 27 iPhone simulator and a paired watchOS 27 simulator.

## Automated

- 46 XCTest cases pass: timer transitions, deadline recovery, persistence, legacy history migration, pause exclusion, duplicate prevention, midnight and DST statistics, custom sessions, backup round-trip and additive import, name redaction, damaged-file recovery and stale watch-command rejection, lost replies, late acknowledgements/errors, out-of-order revisions, rapid selection coalescing, expired commands, old companion compatibility and slow system-effect coalescing. Reset tests cover running/paused states, deadlines, relaunch persistence, old action aliases, saved-history preservation, explicit Start and Watch receipts. Suggestion tests cover short and long breaks, returning to the last focus session, and no suggestion for running, ended or reset sessions.
- JSON import rejects unsupported versions, oversized input, invalid time bounds and overlapping run intervals.
- iPhone, Live Activity extension and embedded watch app build for simulator and physical device.

## Interface and integration

- Light and dark dashboards inspected. The timer keeps its ambient background; session choices and the primary action have distinct proportions and touch regions.
- Swipe pages and tappable dots with 44-point touch targets replace the dashboard's Activity and Settings buttons. The selected page has a wider indicator and an accessibility label.
- System, Light and Dark settings persist across relaunch. Live changes were checked on the dashboard, Settings and its session editor. Native scroll paging keeps destination screens in the same appearance.
- Start, Pause and Resume use one large capsule. End and Reset appear beside it as 64-point round buttons only while a session is active, and as labelled buttons at accessibility text sizes. Running and ready states were checked in dark mode, running in light mode, and paused at the largest accessibility text size on an iOS 27 simulator. Reset restores the full duration and waits for Start. Reset from the iPhone, Watch and Live Activity was checked on simulators. Each returned to the full duration with Start available and left all 100 sample history records unchanged. The Watch keeps End and Reset together in 44-point controls.
- The largest accessibility text size stacks running controls vertically; navigation remains visible. Offscreen pages are hidden from the accessibility tree.
- Activity range menu, filtered history and session details exercised using synthetic history.
- Duration quick choices and named colour selection saved successfully. Largest accessibility text size checked on dashboard, Activity and the session editor.
- AI report preview and native file-sharing sheet opened. Reports hide names by default; sharing requires an explicit destination.
- Saved a JSON backup through Files, reopened it through Import, and verified that reimporting the same records added zero duplicates.
- Paired simulator watch start, pause and end commands changed the iPhone timer. End produced one saved history record.
- Watch session cards share the iPhone colour palette. The current session keeps readable text and a checkmark. Switching between Work and Deep Work, and starting and pausing from Watch, were checked on paired simulators.
- Reset update installed on both paired physical devices using installation commands only. Every pre-update iPhone history record and saved preset matched after installation. Physical screen sharing stayed off; no physical-device interaction test is claimed for this patch.

- Tapping another session while a timer runs asks before switching; dismissing the prompt keeps the running session. The suggested break appeared after a foreground completion and started with one tap.
- A timer that reaches zero while the app is open now completes and saves. Previously the completion check could run inside the final second and leave the timer at 00:00.
- The Live Activity uses a near-opaque dark background and a stop symbol for End. Its legibility was checked on the simulator Lock Screen in light and dark mode, and its Pause button paused the saved iPhone timer. Physical devices and bright custom wallpapers were not checked. The simulator shows running seconds as dashes on the Lock Screen; paused times show in full.
- The Activity page shows Sessions, Completed and Streak tiles, one Sessions card for the selected range, and All history in the toolbar. With Keep screen on enabled, a debugger read of the running simulator app showed the idle timer disabled only while a session runs: on while running, off while paused, and off while running with the setting off.

- On paired iPhone 17 and Apple Watch Ultra 4 simulators, starting from Watch and then picking another session asked before switching; Switch saved the running session as switched on the iPhone. Watch session lengths read "1 hr 30 min" like iPhone.
- Type stays on Apple system fonts. Countdown digits on iPhone and Watch roll between values with a numeric text transition, which was seen on paired simulators; the Reduce Motion fallback was not checked. The Activity total uses the New York serif, checked in dark mode. The session detail duration uses the same font call but was not opened. Watch countdown digits now use light SF Pro, matching iPhone and the Live Activity.
- Rapid Watch changes (Work → Deep Work → Short Break) converged to the same confirmed session on both simulators. Changes made on iPhone also updated the already-open Watch Sessions screen.
- Watch Start and Pause produced matching saved session IDs and phases on both simulators. The confirmed paused session survived companion relaunch.
- A demo iPhone shutdown/reconnect left the confirmed paused timer unchanged; an offline Resume was not replayed.
- Command receipts and stale/late transport responses are exercised by deterministic tests; simulator checks do not prove physical-device latency.

## Limits

Watch interface changes are checked on paired simulators; no full physical Watch interaction audit is claimed. Watch commands need a reachable phone. Fresh simulator installation required reopening the iPhone app once before its connectivity daemon completed registration. Notification permission requests no longer block timer acknowledgements; system effects run separately. A physical reconnect and latency audit still requires user interaction on the devices.

No full spoken VoiceOver audit or iOS 17–25 device run is claimed. Opaque fallbacks are implemented for Reduce Transparency and Increase Contrast. Live Activity and notification code is retained; physical Lock Screen controls, sound under Focus settings and device-reboot behaviour have not been revalidated for this release.

The single README gallery shows the timer, Activity, Watch and a paused Live Activity. Its Activity view uses a complete synthetic week (56 sessions, 20h 15m tracked, 91% completed, 17 day streak), with an earlier week for comparison. Repository screenshots contain synthetic simulator data, never personal history. Builds, local signing settings, device identifiers and development history are excluded from the public snapshot.

The clean public checkout builds with the anonymous example configuration. Gitleaks scans of the source and new Git history found no secrets; a separate tracked-file audit found no private signing values, email addresses, home-directory paths or device IDs. Screenshot metadata was removed without changing image pixels. These checks reduce accidental disclosure; they are not a security certification.

Publication checks also cover author, committer and tagger identities, commit messages, the actual Git index and all file versions in the pushed history. Eleven regression tests verify that unsafe identities, co-author trailers, staged private content, assigned signing teams in generated projects, old unsafe commits and nested annotated tags are rejected. The checks run locally before publication and again in CI.
