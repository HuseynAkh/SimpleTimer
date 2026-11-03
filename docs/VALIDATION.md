# Validation

Checked with Xcode 27, an iOS 27 iPhone simulator and a paired watchOS 27 simulator.

## Automated

- 63 XCTest cases pass: timer transitions, deadline recovery, persistence, legacy history migration, pause exclusion, duplicate prevention, midnight and DST statistics, custom sessions, backup round-trip and additive import, name redaction, damaged-file recovery, Watch sync convergence (offline changes applied late, records saved once and acknowledged, newest change wins with the losing run saved as switched, ended or reset sessions never running again, shared deadlines, a pause, resume or End on one device beating a completion the other guessed at a missed deadline (timers and stopwatches, in both delivery orders), both devices starting the same ready session, phone-owned presets, legacy saves), old companion payloads and expired commands, and slow system-effect coalescing. Reset tests cover running/paused states, deadlines, relaunch persistence, old action aliases, saved-history preservation, explicit Start and Watch receipts. Suggestion tests cover short and long breaks, returning to the last focus session, and no suggestion for running, ended or reset sessions. Stopwatch tests cover mode switching only between sessions, counting active time across pauses, naming and renaming, a name set before Start surviving type changes and resets, the 12-hour limit, completion rates, backup and report output, legacy decoding and Watch commands.
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
- The Live Activity uses a near-opaque dark background and a stop symbol for End. Its legibility was checked on the simulator Lock Screen in light and dark mode, and its Pause button paused the saved iPhone timer. Physical devices and bright custom wallpapers were not checked. The simulator shows running seconds as dashes on the Lock Screen; paused times show in full. Times no longer zero-pad minutes, so pausing a running "4:" shows "4:40" in the same shape as the system-drawn running timer, which was seen in the Watch Smart Stack.
- The Activity page shows Sessions, Completed and Streak tiles, one Sessions card for the selected range, and All history in the toolbar. With Keep screen on enabled, a debugger read of the running simulator app showed the idle timer disabled only while a session runs: on while running, off while paused, and off while running with the setting off.

- On paired iPhone 17 and Apple Watch Ultra 4 simulators, starting from Watch and then picking another session asked before switching; Switch saved the running session as switched on the iPhone. Watch session lengths read "1 hr 30 min" like iPhone.
- The design update was installed over the network on both paired physical devices using installation commands only. Every pre-update iPhone history record, session type and setting matched after installation. No physical-device interaction test is claimed for this update.
- Activity and Settings scroll fully above the page dots; previously their last rows were cut off behind them.
- Stopwatch mode was checked on paired iPhone 17 and Apple Watch Ultra 4 simulators in dark mode: switching modes from both devices, naming before Start, renaming while running, the Watch showing the name and elapsed time, Lock Screen pause and end, and the saved history row. The 12-hour limit is covered by tests only.
- A stopwatch name typed before Start stayed after picking another session type and after relaunch. The page dots stay put while the keyboard is open.
- The Timer page no longer shows today's focus time; the Activity page has it. The page now ends at the session types, seen running and with the stopwatch on the iPhone 17 simulator.
- The stopwatch's optional name now sits under the time and status as a quiet "Add a name" line, and a name shows in secondary text. Checked on the iPhone 17 simulator in dark mode with six session types:
  - The ready and running stopwatch.
  - A name typed while running, which was saved.
  - The largest accessibility text size, where the status and name stay inside the ring.
- The Mac drop-down matches, with "Add a name" under the time. The Mac suite passed again on that build.
- Type stays on Apple system fonts. Countdown digits on iPhone and Watch roll between values with a numeric text transition, which was seen on paired simulators; the Reduce Motion fallback was not checked. The Activity total uses the New York serif, checked in dark mode. The session detail duration uses the same font call but was not opened. Watch countdown digits now use light SF Pro, matching iPhone and the Live Activity.
- Rebuilt Watch sync on paired iPhone 17 and Apple Watch Ultra 4 simulators: mode switches and Start applied on the Watch at once with no waiting state. With the iPhone app quit, a Watch Start woke it in the background and both saved the same running stopwatch. With the iPhone simulator shut down, Watch Pause, End, mode changes and Start all applied immediately, "Syncs with iPhone later" appeared, and after the iPhone came back both devices converged on the same session and change time, the offline session was saved once on the iPhone and the Watch cleared its outbox.
- The Watch widget showed the live session in the Smart Stack on the watchOS 27 simulator: a running stopwatch counting up with its name, Paused immediately after pausing in the app, and a countdown with its end time after starting a timer. A tap opened the app. A signed build with the free team carried the App Group entitlement on both the Watch app and the widget. The round, corner and inline face styles were not checked.
- Tapping the iPhone's mirrored Live Activity in the Watch Smart Stack opened the SimpleTimer Watch app on the paused session, not the "Open on iPhone" screen, on the watchOS 27 simulator.
- After a simulator reboot, the iPhone app needed one relaunch before WatchConnectivity delivered, and delivery then took up to about 25 seconds. Simulator checks do not prove physical Bluetooth or Wi-Fi latency.
- A full pass of the [simulator suite](TESTING.md) (S01 to S22) ran on paired iPhone 17 and Apple Watch Ultra 4 simulators in dark mode, restoring both apps' saved state afterwards. Everything passed except S19. With the Watch app suspended but still running, an iPhone pause reached the Watch, but the widget kept counting for over 2.5 minutes, until the app was opened. The mirrored Live Activity above it already showed Paused. With the Watch app not running, an iPhone change woke it within about 35 seconds. That may be simulator scheduling; it is unconfirmed on a device.
- That pass found these problems, now fixed and rechecked on the same simulators:
  - The page dots and background could follow a different page from the one showing after a touch interrupted a dot's scroll. They now follow the page it settles on; a touch during the animation returns to the starting page.
  - The Lock Screen card moved by about 6 pt between running and paused. Every edge now stays in place.
  - Session detail "Active time" rounded up: a stopwatch ended at 0:46 showed 0:47.
  - Durations under a minute read "<1 min" and "0 min" beside "25m". They now read "<1m" and "0m". The empty chart's middle tick reads "<1m".
  - The Watch now shows Ended and Complete, not only Paused.
  - Its Sessions button is now as wide as the controls.
  - "Syncs with iPhone later" now sits under the clock, so it shows without scrolling on the 49 mm Watch.
  - While the iPhone was away, the label disappeared for about 5 seconds after each tap, because the Watch trusted a stale `isReachable`. It now appears only after a send error or timeout, or when the phone reports itself unreachable. It stays until a reply arrives.
  - It no longer flashes on taps made 0.96 to 2.5 seconds after launch with the phone present. It first appears about 5 seconds after the phone leaves, and the buttons move down once.
- While a session runs, the Watch screen shows only the name, clock, status and controls, and Sessions is one scroll down. Checked on a 46 mm watchOS 27 simulator while running, paused, and with "Syncs with iPhone later" showing; nothing overlapped and Sessions still opened its list. Before a session starts, Sessions stays on screen.
- Not covered by that pass: completion alerts and sound, the Dynamic Island, circular, corner and inline complications, the 12-hour limit, accessibility text sizes, VoiceOver, Reduce Motion, export and import, and light mode beyond one screen. The Live Activity mirrored on the Watch shows the app name, symbol and time but not the session name; it has no Watch-specific layout.

## Mac

Checked on a Mac with a notched 1512 × 982 display, macOS 26.7 in dark mode and Xcode 27, with Thaw 2.0.1 running.

- Debug and Release builds succeed unsigned with `scripts/build-mac.sh`. The Release app is 2.1 MB.
- `scripts/test-mac-e2e.sh` passed all 77 checks in [the test suite](TESTING.md) (M01 to M77), and the overdue scenario passed again on a second relaunch. It runs the app's own controller, drop-down and SwiftUI view, sends mouse and key events to the real status item and drop-down, and checks the saved file after each step. The events are posted inside the process, not made with the pointer. Among other things it covers:
  - Opening and closing from the item, a repeated mouse up and ⌘-clicks ignored, the right-click and Control-click menu, accessibility presses and reopening from Finder.
  - The drop-down taking the keyboard while the frontmost app stays the same, at pop-up menu level with a system dialog subrole.
  - Start, Pause, Resume, End, Reset and switching types through Space and the buttons, with one record saved for End and Switch and none for Reset.
  - A steady item width while the time counts down, dimmed and not ticking while paused.
  - Stopwatch names typed before Start, renamed while running and saved on Quit. Space typing in the field but starting the stopwatch elsewhere.
  - A failed save refused with a notice that clears afterwards.
  - Relaunching running, paused, finishing, overdue and unreadable saves.
  - Ten open and close cycles leaving no drop-down alive.
- The menu bar icon is now a 15 pt semibold symbol, so the item is 35 pt idle and 76 pt with a timer running. A symbol image's alignment rect is only a thin band (10.5 pt of a 19 pt image), and the real menu bar clipped the item to it, cutting off the icon's top and bottom on macOS 26.7. The symbol is now redrawn into a plain image whose alignment rect is the whole image, and the button sits at the bar's 22 pt height instead of 4 pt below its window. Q12 and Q13 failed before this and pass now. An in-process render never showed the clipping, and macOS hosts status items so their live pixels can't be captured without Screen Recording, so the on-screen result rests on a person looking at it. The 13 background checks and the paused and overdue relaunch checks passed while the Mac was in use. The full suite has not had a clean run since this change: real clicks closed the drop-down during those attempts, and the best one passed 64 of 65 checks in its first scenario. M10 failed when the pointer moved, and now tolerates that, but that fix has not been run through a full pass either.
- That run found a timer that finished while the app was quit completing on launch but staying unsaved until the next action. Launch now saves it, once.
- The duration menu of a session type lists 15 min to 1 hr 30 min with the current length ticked, and choosing one saves it. The harness reads the menu from the view, because a posted right click does not pop it up.
- The installed Release build in Applications passed checks B01 to B05. It runs as one menu-bar-only process using 12 MB idle, 18 MB with the drop-down open, and 0.24 seconds of CPU from launch through opening the drop-down twice. Opening it again showed the drop-down at pop-up menu level, 6 pt below the 33 pt menu bar at the pointer, because Thaw keeps the item in its always-hidden section. A second copy handed over and quit. Thaw records the item as `<bundle ID>:SimpleTimer`.
- In a test harness running the same code earlier, ten open and close cycles kept the footprint near 26 MB once SwiftUI had loaded. Relaunching the real build on a saved running stopwatch widened its item to show the time.
- Placement checks pass for these cases: a visible item, clamping at the screen edges, an item hidden off screen or behind the notch, an auto-hidden menu bar, an item mirrored on another display, a hidden item overlapping a display on the left, and a pointer outside every screen.
- `docs/release-images/mac-panel.png` is drawn in-process by the Debug-only `--render-panel` argument from synthetic data: a Work session 26 minutes in, after a completed 90-minute Deep Work session. Its metadata was removed.

Not checked:

- Clicks with the real pointer, on the item or in the Thaw Bar. Computer use was not approved during this run.
- Ice and Bartender.
- Anchoring under a visible item: Thaw hid the test item, so placement was checked at the pointer.
- Clicking outside to close the drop-down. That listens for other apps' clicks, which posted events cannot produce.
- The real pop-up of a session type's duration menu.
- Launch at Login.
- Completion alerts. The harness counts the permission request instead of showing it, and permission for the installed build is still undecided.
- Full-screen Spaces and an auto-hidden menu bar. With two external displays and "Displays have separate Spaces" off, the drop-down opened at the pointer on an external display, which has no menu bar.
- Light mode, tiling window managers, and macOS 14, 15 or 27.
- A stopwatch name typed after End is held for the next Start but not saved before it, so quitting first drops it.

## Limits

Watch interface changes are checked on paired simulators; no full physical Watch interaction audit is claimed. Watch commands need a reachable phone. Fresh simulator installation required reopening the iPhone app once before its connectivity daemon completed registration. Notification permission requests no longer block timer acknowledgements; system effects run separately. A physical reconnect and latency audit still requires user interaction on the devices.

No full spoken VoiceOver audit or iOS 17–25 device run is claimed. Opaque fallbacks are implemented for Reduce Transparency and Increase Contrast. Live Activity and notification code is retained; physical Lock Screen controls, sound under Focus settings and device-reboot behaviour have not been revalidated for this release.

The single README gallery shows the timer, Activity, Watch and a paused Live Activity. Its Activity view uses a complete synthetic week (56 sessions, 20h 15m tracked, 91% completed, 17 day streak), with an earlier week for comparison. Repository screenshots contain synthetic simulator data, never personal history. Builds, local signing settings, device identifiers and development history are excluded from the public snapshot.

The clean public checkout builds with the anonymous example configuration. Gitleaks scans of the source and new Git history found no secrets; a separate tracked-file audit found no private signing values, email addresses, home-directory paths or device IDs. Screenshot metadata was removed without changing image pixels. These checks reduce accidental disclosure; they are not a security certification.

Publication checks also cover author, committer and tagger identities, commit messages, the actual Git index and all file versions in the pushed history. Eleven regression tests verify that unsafe identities, co-author trailers, staged private content, assigned signing teams in generated projects, old unsafe commits and nested annotated tags are rejected. The checks run locally before publication and again in CI.
