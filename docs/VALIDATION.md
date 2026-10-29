# Validation

Checked with Xcode 27, an iOS 27 iPhone simulator and a paired watchOS 27 simulator.

## Automated

- 27 XCTest cases pass: timer transitions, deadline recovery, persistence, legacy history migration, pause exclusion, duplicate prevention, midnight and DST statistics, custom sessions, backup round-trip and additive import, name redaction, damaged-file recovery and stale watch-command rejection.
- JSON import rejects unsupported versions, oversized input, invalid time bounds and overlapping run intervals.
- iPhone, Live Activity extension and embedded watch app build for simulator and physical device.

## Interface and integration

- Light and dark dashboards inspected. The timer keeps its ambient background; session choices and the primary action have distinct proportions and touch regions.
- Swipe pages and tappable dots with 44-point touch targets replace the dashboard's Activity and Settings buttons. The selected page has a wider indicator and an accessibility label.
- System, Light and Dark settings persist across relaunch. Live changes were checked on the dashboard, Settings and its session editor. Native scroll paging keeps destination screens in the same appearance.
- Start, Pause/Resume, End and Restart use equal control sizes. Restart archives the elapsed session once and starts a fresh timer; this was checked against the saved simulator state.
- The largest accessibility text size stacks running controls vertically; navigation remains visible. Offscreen pages are hidden from the accessibility tree.
- Activity range menu, filtered history and session details exercised using synthetic history.
- Duration quick choices and named colour selection saved successfully. Largest accessibility text size checked on dashboard, Activity and the session editor.
- AI report preview and native file-sharing sheet opened. Reports hide names by default; sharing requires an explicit destination.
- Saved a JSON backup through Files, reopened it through Import, and verified that reimporting the same records added zero duplicates.
- Paired simulator watch start, pause and end commands changed the iPhone timer. End produced one saved history record.
- Watch session cards share the iPhone colour palette. The current session keeps readable text and a checkmark. Switching between Work and Deep Work, and starting and pausing from Watch, were checked on paired simulators.
- Signed update installed and launched wirelessly over the existing iPhone app. Every pre-update history record and the saved presets matched after installation. A second check after launch confirmed the original history remained intact.

## Limits

Watch interface changes are checked on paired simulators; no full physical Watch interaction audit is claimed. Watch commands need a reachable phone. Simulator connectivity may require reopening both apps after pairing and responding to the iPhone's first notification permission prompt.

No full spoken VoiceOver audit or iOS 17–25 device run is claimed. Opaque fallbacks are implemented for Reduce Transparency and Increase Contrast. Live Activity and notification code is retained; physical Lock Screen controls, sound under Focus settings and device-reboot behaviour have not been revalidated for this release.

Repository screenshots contain synthetic simulator data, never personal history. Builds, local signing settings, device identifiers and development history are excluded from the public snapshot.

The clean public checkout builds with the anonymous example configuration. Gitleaks scans of the source and new Git history found no secrets; a separate tracked-file audit found no private signing values, email addresses, home-directory paths or device IDs. Screenshot metadata was removed without changing image pixels. These checks reduce accidental disclosure; they are not a security certification.

Publication checks also cover author, committer and tagger identities, commit messages, the actual Git index and all file versions in the pushed history. Ten regression tests verify that unsafe identities, co-author trailers, staged private content, old unsafe commits and nested annotated tags are rejected. The checks run locally before publication and again in CI.
