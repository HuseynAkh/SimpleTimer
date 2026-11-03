# Test suite

Seven suites with 199 named subtasks: 63 Core tests, 11 audit tests, 77 scripted Mac checks, 5 checks of the installed Mac app, 22 paired-simulator checks, 8 checks of the publishing setup and 13 Mac background checks. Results, and what has not been checked, are in [VALIDATION.md](VALIDATION.md).

| Suite | Subtasks | How it runs |
|---|---|---|
| 1. Core unit tests | 63 | `./scripts/test-core.sh` |
| 2. Publishing audit tests | 11 | `python3 scripts/test-public-guard.py` |
| 3. Mac end to end | 77 | `./scripts/test-mac-e2e.sh` |
| 4. Installed Mac app | 5 | Shell commands against the app in Applications |
| 5. iPhone and Watch end to end | 22 | By hand on paired simulators |
| 6. Publishing | 8 | `scripts/audit-public.py` and CI |
| 7. Mac background | 13 | `./scripts/test-mac-e2e.sh --background` |

## 1. Core unit tests (63)

XCTest in `Tests/TimerCoreTests`, with a fixed `now` and no wall clock.

| File | Tests | Covers |
|---|---|---|
| `TimerCoreTests.swift` | 12 | Transitions, deadline recovery, persistence, damaged-file recovery, legacy migration |
| `SyncTests.swift` | 12 | Watch merge: newest change wins, saved once, offline changes, a pause or End beating a guessed completion, shared Starts, deleted types |
| `StopwatchTests.swift` | 10 | Mode switching, active time across pauses, naming, the 12-hour limit, the clock shape |
| `HistoryTests.swift` | 9 | Pause exclusion, duplicates, midnight and DST statistics, custom sessions |
| `ExportTests.swift` | 6 | Backup round trip, additive import, name redaction, report output |
| `ResetTests.swift` | 6 | Reset from running and paused, deadlines, relaunch, the `restart` alias |
| `NextSessionTests.swift` | 4 | Short and long break suggestions, returning to focus |
| `WatchSyncTests.swift` | 4 | Old companion payloads, expired commands, effect coalescing |

## 2. Publishing audit tests (11)

`scripts/test-public-guard.py` checks that the audit rejects unsafe identities, co-author trailers, staged private content, assigned signing teams, old unsafe commits and nested annotated tags.

## 3. Mac end to end (77)

`scripts/test-mac-e2e.sh` builds `Tests/MacE2E/main.swift` with copies of the Mac and Core sources, so the real controller, drop-down and SwiftUI view run. It sends mouse and key events to the real status item and drop-down, reads the drop-down through accessibility and checks the saved file after each step. Each scenario has its own home folder; the overdue scenario runs twice to check a relaunch saves nothing twice. While it runs, a second SimpleTimer item sits in the menu bar, and a manager like Thaw may file it into a section. The permission prompt for alerts is counted, not shown. The drop-down takes the keyboard, so the run waits for 60 seconds without mouse or keyboard input and stops with exit code 4 as soon as either is used. To work at the same time, use [the background checks](#7-mac-background-13). The log names real clicks as `OUTSIDE`.

**Launch** (scenario `fresh`)

| ID | Check |
|---|---|
| M01 | Status item exists, no Dock icon, no window |
| M02 | Fixed autosave name and accessibility identifier, empty title |
| M03 | Icon only while idle, template image, no ticker |
| M04 | Nothing is saved before the first change |

**Menu bar item and drop-down**

| ID | Check |
|---|---|
| M05 | A left click opens the drop-down |
| M06 | It takes the keyboard while the frontmost app stays the same |
| M07 | Pop-up menu level, on all Spaces and over full-screen apps |
| M08 | System dialog subrole, so tiling window managers leave it alone |
| M09 | The keyboard starts on the view, not a text field |
| M10 | Placed 6 pt below the menu bar: under the item when it is visible, at the pointer when a manager hides it |
| M11 | A second left click closes it |
| M12 | Closing releases its view |
| M13 | A second mouse up within 0.3 s, as Thaw sends, is ignored |
| M14 | A ⌘-click, as managers use to move items, is ignored |
| M15 | A right click shows Launch at Login and Quit |
| M16 | The menu is detached afterwards, so a left click still opens the drop-down |
| M17 | A Control-click shows the same menu |
| M18 | An accessibility press, as managers send, opens the drop-down rather than the menu |
| M19 | A second accessibility press closes it |
| M20 | Opening the app again from Finder or Spotlight shows the drop-down |
| M21 | Opening it again while open keeps the one drop-down |

**Timer**

| ID | Check |
|---|---|
| M22 | No alert permission request before Start |
| M23 | Space starts the timer and saves it |
| M24 | Alert permission is asked after the first Start |
| M25 | The item shows the time while running, with a ticker |
| M26 | The item's width stays the same from second to second |
| M27 | The time counts down every second |
| M28 | The drop-down shows the clock and "Ends" time |
| M29 | Space pauses; the item dims and stops ticking |
| M30 | The drop-down shows Paused and Resume |
| M31 | Space resumes |
| M32 | End saves one ended record |
| M33 | The item returns to the icon after End |
| M34 | The drop-down shows Ended and offers Start |
| M35 | Start begins a new attempt |
| M36 | Reset stops at the full duration and saves nothing |
| M37 | Picking another type mid-session asks first |
| M38 | Cancel keeps the running session |
| M39 | Switch saves it as switched and selects the new type |
| M40 | Picking a type between sessions needs no confirmation |
| M41 | The footer shows the time focused today |
| M42 | A session type's right-click menu lists 15 min to 1 hr 30 min with the current one ticked |
| M43 | Choosing 30 min saves it and resizes the ready session |
| M44 | Esc closes the drop-down |
| M45 | Another window taking the keyboard closes it |

**Stopwatch and names**

| ID | Check |
|---|---|
| M46 | The mode button switches to a ready stopwatch |
| M47 | Reopening keeps the keyboard off the name field |
| M48 | Space starts the stopwatch instead of typing a space |
| M49 | The mode button hides while a session is active |
| M50 | The item counts up |
| M51 | A name typed after End is held for the next Start |
| M52 | Picking another type after End readies a stopwatch and keeps the name |
| M53 | Clicking the name field starts editing |
| M54 | Space inside the field types a space |
| M55 | Return saves the name on the ready session |
| M56 | The name survives a type change |
| M57 | Space after Return starts the named stopwatch |
| M58 | Closing the drop-down saves a rename made while running |
| M59 | Quit saves a name still being typed |
| M60 | End saves the named record |
| M61 | The name clears after End |
| M62 | The mode button returns to the timer |

**Saving and memory**

| ID | Check |
|---|---|
| M63 | When the save fails, the action is refused and "Could not save the timer." shows |
| M64 | The notice clears after the next successful save |
| M65 | Ten open and close cycles leave no drop-down alive |

**Relaunch** (scenarios `restore`, `paused`, `deadline`, `overdue`, `damaged`)

| ID | Check |
|---|---|
| M66 | A running named stopwatch comes back running with its name |
| M67 | The item shows its elapsed time and ticks |
| M68 | The drop-down shows the name and "Started" time |
| M69 | A paused timer comes back paused and dimmed, with no ticker |
| M70 | Its time does not move |
| M71 | A running timer counts down after launch |
| M72 | It completes at zero and saves one completed record |
| M73 | The item returns to the icon and stops ticking |
| M74 | The drop-down shows Complete with Start |
| M75 | A timer that finished while the app was quit completes on launch and is saved once, also after a second relaunch |
| M76 | An unreadable save shows "Saved data could not be read." |
| M77 | Start is then refused and the file is left untouched |

## 4. Installed Mac app (5)

Run against the Release build in Applications, with Thaw running. Window positions come from the window list, so no screen recording is needed.

| ID | Check | Command |
|---|---|---|
| B01 | One process, registered as a menu-bar-only app, nothing saved at launch | `lsappinfo info -only ApplicationType -app <bundle ID>` |
| B02 | Opening it again shows the drop-down at pop-up menu level, 6 pt below the menu bar, and saves nothing | `open -g /Applications/SimpleTimer.app`, then list windows |
| B03 | A second copy started directly hands over and quits; the first keeps its drop-down | Run the executable inside the app bundle directly |
| B04 | Memory footprint idle and with the drop-down open | `footprint <pid>` |
| B05 | Thaw keeps the item under a stable `<bundle ID>:SimpleTimer` identifier in its section | `defaults read com.stonerl.Thaw` |

## 5. iPhone and Watch end to end (22)

Paired iPhone and Apple Watch simulators in dark mode, using an ad-hoc signed Debug build so the App Group is present. Back up both apps' saved state first and restore it afterwards. The Watch keeps its state in its preferences, not `state.json`.

| ID | Check |
|---|---|
| S01 | iPhone Start, Pause and Resume |
| S02 | End saves exactly one ended record |
| S03 | Reset returns to the full duration with Start and saves nothing |
| S04 | Picking another type mid-session asks first: Cancel keeps it, Switch saves it as switched |
| S05 | A countdown finishing with the app open completes, saves once and suggests a break |
| S06 | A countdown finishing while the app is quit reconciles to one completed record on relaunch |
| S07 | Stopwatch: name before Start, rename while running, Pause and Resume, End, the name kept in history, mode hidden while active |
| S08 | Relaunch mid-run and mid-pause keeps the time and phase |
| S09 | Lock Screen Live Activity: Pause, Resume, End and Reset work, the paused clock keeps its shape and the card keeps its height |
| S10 | A Watch Start shows on iPhone |
| S11 | An iPhone Pause shows on Watch |
| S12 | A Watch End saves one record on iPhone |
| S13 | A named stopwatch started on Watch |
| S14 | Picking another type on Watch mid-session asks first |
| S15 | With the iPhone app quit, a Watch Start wakes it and both save the same session |
| S16 | With the iPhone off, Watch changes apply at once, "Syncs with iPhone later" shows without scrolling, and both converge once it returns |
| S17 | The Watch widget shows the live session in the Smart Stack |
| S18 | Tapping the mirrored Live Activity opens the Watch app |
| S19 | The Watch widget follows an iPhone change while the Watch app is suspended |
| S20 | Dark-mode sweep: page dots match the visible page after an interrupted scroll; nothing clipped, overlapping or cut off; no em dashes |
| S21 | Session detail "Active time" matches the clock, not rounded up |
| S22 | Short durations read "<1m" and "0m" like the rest of history; the Watch shows Paused, Ended and Complete |

## 6. Publishing (8)

| ID | Check |
|---|---|
| P01 | `python3 scripts/audit-public.py --identity --staged` passes for the public commit |
| P02 | `python3 scripts/audit-public.py --identity --staged --history HEAD` passes before a push |
| P03 | `git config core.hooksPath` prints `.githooks` in the public clone |
| P04 | Every commit is authored and committed by the GitHub no-reply identity, with no trailers |
| P05 | The project diff has no `DevelopmentTeam` value |
| P06 | Images carry no metadata |
| P07 | CI "Core tests" passes on `main` |
| P08 | The public snapshot builds with the example configuration |

## 7. Mac background (13)

`./scripts/test-mac-e2e.sh --background` is safe during other work. It opens no drop-down, keeps its item out of the menu bar and takes no focus, because it drives the store directly and reads the item's image and state. It also runs the two paused relaunch checks and the overdue check (M69, M70 and M75). It does not replace suite 3: nothing here tests clicks or the drop-down.

| ID | Check |
|---|---|
| Q01 | The idle icon is the 15 pt semibold timer template |
| Q02 | Running shows the time beside the icon, with a ticker |
| Q03 | The width stays the same each second |
| Q04 | The time counts down |
| Q05 | Pausing dims the item and stops the ticker |
| Q06 | Resuming ticks again |
| Q07 | End returns to the icon and saves one ended record |
| Q08 | The stopwatch icon is the same weight and within 2 pt in size |
| Q09 | The stopwatch counts up |
| Q10 | Reset returns to the icon and saves nothing more |
| Q11 | No drop-down or key window, and another app stays frontmost |
| Q12 | The timer image's alignment rect is the whole image, so the menu bar doesn't clip it |
| Q13 | The stopwatch image's alignment rect is the whole image too |
