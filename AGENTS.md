# Agent guide

Shared instructions for every coding agent in this repository (Codex reads this file; Claude Code reads it through `CLAUDE.md`). Keep agent-specific files as pointers to this one.

SimpleTimer is a public, MIT-licensed iPhone time tracker with a Live Activity and an Apple Watch remote. Read these before changing behaviour; don't restate them here:

- [README.md](README.md): features, build and install.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): timer, history, export and Watch sync design.
- [docs/VALIDATION.md](docs/VALIDATION.md): what has been tested, and what hasn't.
- [PRIVACY.md](PRIVACY.md): data handling and publishing setup.
- [docs/GALLERY.md](docs/GALLERY.md): how release screenshots are made.

## Layout

- `Core`: Foundation-only timer state, history, export, backup and Watch sync types. Swift package `TimerCore`, tested in `Tests/TimerCoreTests`.
- `App`: SwiftUI iPhone screens. `TimerStore` owns state, saving and system effects.
- `LiveActivity`, `Shared`: widget extension and types shared with it.
- `Connectivity`, `WatchApp`: WatchConnectivity on the phone, and the Watch app.
- `project.yml`: XcodeGen spec. `SimpleTimer.xcodeproj` is generated from it and committed.
- `scripts`: test, build, install and publishing-audit scripts.

## Commands

```sh
./scripts/test-core.sh          # swift test for Core
./scripts/build-simulator.sh    # iPhone + Live Activity + embedded Watch app, unsigned
python3 scripts/audit-public.py --identity --staged   # what the pre-commit hook runs
python3 scripts/test-public-guard.py                   # tests for the audit itself
```

The scripts default `DEVELOPER_DIR` to `/Applications/Xcode.app`, so they work when `xcode-select` points at the Command Line Tools. Plain `xcodebuild` may not.

After editing `project.yml`, run `xcodegen generate` with `Config/Local.xcconfig` copied from the example (empty team). Commit `project.pbxproj` with it, and check its diff contains no `DevelopmentTeam` value. Never commit `Config/Local.xcconfig`.

## Invariants

- The iPhone is the single writer. All surfaces (app, Live Activity, Watch) go through `TimerState.perform`. Keep `restart` as a reset-only alias for older clients.
- `TimerStore.apply` validates, mutates and saves in one main-actor turn with no suspension. Notifications and ActivityKit run afterwards through `LatestEffectsQueue`. Acknowledgements never wait for them.
- Watch commands carry an expected session UUID, a command ID and an expiry. Never queue, replay or auto-retry a timer command. The Watch persists only confirmed phone state and keeps no history.
- Reset discards the current attempt without archiving it. End saves elapsed time. Only an explicit Start begins an attempt.
- A stopwatch is an untimed `Session` with a 12-hour limit that reuses every timer action. Mode switches only between sessions. New fields stay optional so older saves, backups and companions still decode.
- Saved state and backup JSON must stay readable by older and newer builds. Import is additive and never touches preferences or the active timer.
- No backend, analytics, third-party SDK or network calls. Export goes only through the share sheet.

## Private development, public release

There are two Git repositories:

- This one: private development history, no remote. It still tracks old dev-only files (`docs/screenshots`) that fail the audit, so its hooks are off.
- `PublicRelease/` (ignored here): a separate clean clone that pushes to the public GitHub repository, with hooks on. Publishable files are copied into it and committed there as a curated snapshot. Its history is not this repository's history.

Publishing (committing or pushing in `PublicRelease`) is outward-facing: do it only when the user explicitly asks, and show them what will go out first. Before any push, run `python3 scripts/audit-public.py --identity --staged --history HEAD` there and confirm `git config core.hooksPath` prints `.githooks`. Never use `--no-verify` or rewrite public history without being asked.

The audit (hooks and CI) fails on:

- any email address in commit messages or identities other than a GitHub no-reply address,
- home-directory paths, device identifiers, team IDs, keys and tokens in tracked files,
- signing files, `Local.xcconfig`, `.env*`, `.private-backups`, and image text or EXIF metadata.

So, in both repositories:

- Don't add `Co-Authored-By` or other trailers with an email address to commits. Public commits are rejected with them; leave AI attribution out.
- Use relative paths in docs and code. Never write an absolute home-directory path.
- Screenshots use synthetic simulator data only, with metadata stripped (see GALLERY.md). Personal device backups and logs belong in `.private-backups/`, never in tracked files.

## Working conventions

- Match the existing Swift: compact, few comments, short lines joined with `;` where the surrounding code does. A comment explains a non-obvious constraint, not what the line does.
- New Core behaviour gets XCTest coverage that uses a fixed `now`, never the wall clock.
- Commit subjects are one imperative, sentence-case line with no prefix, e.g. "Make Reset stop without saving and refresh the app gallery".
- Keep docs in step with behaviour. When tests or validated behaviour change, update the test count and claims in VALIDATION.md. Claim only what was actually run. Simulator checks are not physical-device checks.
- User-facing copy is short and plain, in Canadian/British spelling ("colour").
