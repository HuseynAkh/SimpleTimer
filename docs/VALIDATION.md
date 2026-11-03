# Validation

Checked with Xcode 27, an iOS 27 iPhone simulator and a paired watchOS 27 simulator.

## Automated

- 58 XCTest cases pass: timer transitions, deadline recovery, persistence, legacy history migration, pause exclusion, duplicate prevention, midnight and DST statistics, custom sessions, backup round-trip and additive import, name redaction, damaged-file recovery, Watch sync convergence (offline changes applied late, records saved once and acknowledged, newest change wins with the losing run saved as switched, ended or reset sessions never running again, shared deadlines, phone-owned presets, legacy saves), old companion payloads and expired commands, and slow system-effect coalescing. Reset tests cover running/paused states, deadlines, relaunch persistence, old action aliases, saved-history preservation, explicit Start and Watch receipts. Suggestion tests cover short and long breaks, returning to the last focus session, and no suggestion for running, ended or reset sessions. Stopwatch tests cover mode switching only between sessions, counting active time across pauses, naming and renaming, a name set before Start surviving type changes and resets, the 12-hour limit, completion rates, backup and report output, legacy decoding and Watch commands.
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
- The design update was installed over the network on both paired physical devices using installation commands only. Every pre-update iPhone history record, session type and setting matched after installation. No physical-device interaction test is claimed for this update.
- Activity and Settings scroll fully above the page dots; previously their last rows were cut off behind them.
- Stopwatch mode was checked on paired iPhone 17 and Apple Watch Ultra 4 simulators in dark mode: switching modes from both devices, naming before Start, renaming while running, the Watch showing the name and elapsed time, Lock Screen pause and end, and the saved history row. The 12-hour limit is covered by tests only.
- A stopwatch name typed before Start stayed after picking another session type and after relaunch. The page dots stay put while the keyboard is open.
- Type stays on Apple system fonts. Countdown digits on iPhone and Watch roll between values with a numeric text transition, which was seen on paired simulators; the Reduce Motion fallback was not checked. The Activity total uses the New York serif, checked in dark mode. The session detail duration uses the same font call but was not opened. Watch countdown digits now use light SF Pro, matching iPhone and the Live Activity.
- Rebuilt Watch sync on paired iPhone 17 and Apple Watch Ultra 4 simulators: mode switches and Start applied on the Watch at once with no waiting state. With the iPhone app quit, a Watch Start woke it in the background and both saved the same running stopwatch. With the iPhone simulator shut down, Watch Pause, End, mode changes and Start all applied immediately, "Syncs with iPhone later" appeared, and after the iPhone came back both devices converged on the same session and change time, the offline session was saved once on the iPhone and the Watch cleared its outbox.
- The Watch widget shows only large timer and stopwatch symbols. On the watchOS 27 simulator it appeared in the widget picker, was added to the Smart Stack, rendered as designed, and a tap opened SimpleTimer on the running session. Watch face complication slots were not checked.
- After a simulator reboot, the iPhone app needed one relaunch before WatchConnectivity delivered, and delivery then took up to about 25 seconds. Simulator checks do not prove physical Bluetooth or Wi-Fi latency.

## Mac

Checked on a Mac with a notched 1512 × 982 display, macOS 26.7 in dark mode and Xcode 27, with Thaw running.

- Debug and Release builds succeed unsigned with `scripts/build-mac.sh`. The Release app is 2.0 MB.
- Memory footprint is 12 MB idle, 12 MB with a stopwatch running and the drop-down closed, and 18 MB with the drop-down open, in Debug and Release. The running stopwatch used 0.18 seconds of CPU in its first 23 seconds, launch included. In a test harness running the same code, ten open and close cycles left no panel alive, and the footprint stayed near 26 MB once SwiftUI had loaded.
- Thaw put the new item in its always-hidden section, off screen at x = -9928. Opening the app again showed the drop-down under the menu bar at the pointer, 6 pt below the 33 pt bar, at pop-up menu level. A second copy handed over to the first and quit.
- A scratch harness ran the app's controller, panel and view in-process, with posted mouse and key events and its own home folder. It passed these checks:
  - Mouse events sent to the item's window open and close the drop-down. An extra mouse up and a ⌘-click are ignored, and a right click shows Launch at Login and Quit.
  - The item has a fixed autosave name and identifier and an empty title. It shows the icon alone when idle, adds the time while active, and dims when paused. Its width stays at 56 pt from second to second, and its timer runs only while a session runs.
  - Space starts and pauses, and Resume resumes.
  - Picking another type mid-session asks first: Cancel keeps the session, and Switch saves it as switched. End saves the session, and Reset does not.
  - In stopwatch mode, a name typed before Start is saved on Return, survives a type change, and Space inside the field types a space. The mode button hides while a session is active.
  - Esc, or another window taking key status, closes the drop-down and releases its view. A duration change is saved.
  - The drop-down takes the keyboard while the frontmost app stays the same. It grows down from a fixed top edge, and its accessibility subrole is `AXSystemDialog`.
- Relaunching the real build on that saved state restored the running named stopwatch, and its item widened from 31 to 72 pt to show the time.
- Placement checks pass for these cases: a visible item, clamping at the screen edges, an item hidden off screen or behind the notch, an auto-hidden menu bar, an item mirrored on another display, a hidden item overlapping a display on the left, and a pointer outside every screen.
- `docs/release-images/mac-panel.png` is drawn in-process by the Debug-only `--render-panel` argument from synthetic data: a Work session 26 minutes in, after a completed 90-minute Deep Work session. Its metadata was removed.

Not checked:

- Real clicks on the menu bar item or in the Thaw Bar.
- Ice and Bartender.
- Anchoring under a visible item after a real click.
- Launch at Login.
- Completion notifications: permission for the test build was still undecided.
- A session type's duration menu opened with a real right click.
- Full-screen Spaces, an auto-hidden menu bar and multiple displays.
- Light mode, tiling window managers, and macOS 14, 15 or 27.
- Running from Applications.

## Limits

Watch interface changes are checked on paired simulators; no full physical Watch interaction audit is claimed. Watch commands need a reachable phone. Fresh simulator installation required reopening the iPhone app once before its connectivity daemon completed registration. Notification permission requests no longer block timer acknowledgements; system effects run separately. A physical reconnect and latency audit still requires user interaction on the devices.

No full spoken VoiceOver audit or iOS 17–25 device run is claimed. Opaque fallbacks are implemented for Reduce Transparency and Increase Contrast. Live Activity and notification code is retained; physical Lock Screen controls, sound under Focus settings and device-reboot behaviour have not been revalidated for this release.

The single README gallery shows the timer, Activity, Watch and a paused Live Activity. Its Activity view uses a complete synthetic week (56 sessions, 20h 15m tracked, 91% completed, 17 day streak), with an earlier week for comparison. Repository screenshots contain synthetic simulator data, never personal history. Builds, local signing settings, device identifiers and development history are excluded from the public snapshot.

The clean public checkout builds with the anonymous example configuration. Gitleaks scans of the source and new Git history found no secrets; a separate tracked-file audit found no private signing values, email addresses, home-directory paths or device IDs. Screenshot metadata was removed without changing image pixels. These checks reduce accidental disclosure; they are not a security certification.

Publication checks also cover author, committer and tagger identities, commit messages, the actual Git index and all file versions in the pushed history. Eleven regression tests verify that unsafe identities, co-author trailers, staged private content, assigned signing teams in generated projects, old unsafe commits and nested annotated tags are rejected. The checks run locally before publication and again in CI.
