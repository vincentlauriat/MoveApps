# Architecture

## Overview
`move-app.sh` is a single self-contained bash script (bash 3.2 compatible — the version macOS ships) that migrates a project directory from `~/Documents/Github` (iCloud Drive) to `~/DevApps` (local) without breaking it.

## Flow (per selected project)
1. **Selection** — CLI args, or interactive: `fzf -m` if installed, else a substring-filter numbered menu (loops until a non-empty selection is made).
2. **Stack detection** — presence of `package.json`, `requirements.txt`/`pyproject.toml`/`Pipfile`, `*.xcodeproj`/`*.xcworkspace`, `Cargo.toml`, `go.mod`, `.git` (maxdepth 2, cheap `find` calls).
3. **iCloud stub check** — `find -name '*.icloud'`; if any are found, `brctl download` is triggered and the script polls until they're materialized (bounded retries).
4. **Python venv discovery** — `find -name pyvenv.cfg` (not folder-name matching, to avoid false positives), since a venv is not relocatable: its `bin/*` scripts hardcode an absolute shebang to the venv's own path. For each venv found, `pip freeze` is captured to a temp file *before* the move, while the old absolute path is still valid.
5. **Git snapshot (before)** — branch, HEAD, dirty-file count, all wrapped in a hand-rolled `with_timeout` function (no GNU `timeout` binary on this machine), since git operations on iCloud-backed trees can be unexpectedly slow.
6. **Confirmation** — the plan is printed and the user confirms per project unless `--yes`. `--dry-run` stops here.
7. **Move (`move_dir`)** — try `mv` first (atomic and fast when it works). If it fails (in practice: `Operation timed out`, because iCloud's FileProvider extension intercepts `rename()` even across paths on the same device), fall back to `ditto` (Apple's own tool, which correctly materializes/copies iCloud content) followed by a file-count comparison between source and destination. The source is only `rm -rf`'d once the counts match — an unverified copy is never deleted.
8. **Venv recreation** — inside the new location, the moved (now broken) venv directory is removed, a fresh one is created with `python3 -m venv`, then packages are reinstalled from the freeze file captured in step 4.
9. **Optional node reinstall** — only with `--reinstall-node`: detects a pnpm/yarn/npm lockfile and reinstalls `node_modules` from scratch. Off by default because a plain directory move usually does not break `node_modules` (its symlinks/hardlinks are either relative or point to fixed external stores, e.g. the pnpm global store).
10. **Optional compatibility symlink** — `--keep-symlink` recreates the old path as a symlink to the new one, for tools/IDEs that still reference it.
11. **Verification (after)** — git snapshot compared against step 5; `grep -rl` over the moved tree (excluding `.git`, `node_modules`, `.venv`, build/cache dirs) for any leftover reference to the literal old absolute path; `find -type l` + `readlink` to catch symlinks that now point to a non-existent absolute target.
12. **Report** — a per-project OK / AVERTISSEMENT / ECHEC line, plus a final summary table.

## Design constraints
- **bash 3.2 only** — no `mapfile`, no associative arrays, no `${var,,}`. Selections are built with plain indexed arrays and `while IFS= read -r` loops.
- **No GNU coreutils assumed** — there is no `timeout`/`gtimeout` binary on this machine; replaced by a background-job-plus-watcher `with_timeout` function.
- **Safety over speed** — never overwrites an existing destination, never deletes a source before a copy is verified, Python venvs are always rebuilt from a captured package list rather than trusted as-is after a move.

## Known real-world caveat
Even though `~/Documents/Github` and `~/DevApps` report the same filesystem device ID (`stat -f "%d"`), a plain `mv` between them is not a guaranteed metadata-only rename — iCloud Drive's FileProvider extension mediates the operation and can time it out. This was discovered during the first real test run and is not a hypothetical edge case; the `ditto` fallback in `move_dir` handles it transparently.

---

# MoveApps.app — SwiftUI native rewrite (current)

`move-app.sh` above is now an unmaintained CLI fallback/reference. The active tool is **MoveApps.app**, a native macOS app that ports the same logic to Swift, adds a UI (menu bar + main window), and makes transfers bidirectional.

## Why a full rewrite instead of wrapping the script
The bash rollout is done (121/121 projects), and this is now a day-to-day tool used from a GUI across multiple Macs — a `Process` call into a bash script would work, but native Swift gives structured concurrency for live progress reporting, testable services behind protocols (critical for safely reproducing failure modes like the `ditto` data-loss bug — see below — without ever touching real project folders), and a properly typed `TransferWarning`/`TransferResult` model instead of parsing free-text script output.

## Project layout
```
Sources/
├── MoveAppsCore/     # framework, pure logic, zero SwiftUI/AppKit import
│   ├── Models/        # ProjectCandidate, StackTag, RootKind, TransferPlan, TransferStep,
│   │                   # TransferResult, TransferWarning, GitSnapshot, GitStatusEntry, VenvInfo
│   ├── Services/       # StackDetector, ICloudMaterializer, VenvManager, GitService,
│   │                   # DirectoryMover, DirectoryCopying (+DittoCopier), NodeModulesInstaller,
│   │                   # SymlinkVerifier, ResidualPathScanner
│   ├── Pipeline/       # TransferPipeline — actor, single entry point for the UI, exposes AsyncStream<TransferStep>
│   ├── Persistence/    # TransferHistoryStore (actor, JSON in Application Support), TransferRecord
│   ├── Settings/       # RootPathsSettings (@Observable, security-scoped bookmarks via NSOpenPanel)
│   └── Support/        # ProcessRunner, AsyncTimeout
├── MoveAppsUI/        # framework, depends on Core — MainWindow/, MenuBar/, Settings/, DragDrop/, Components/
└── MoveApps/          # thin app target — MoveAppsApp.swift (MenuBarExtra + Window(id:) + Settings Scenes)
```

## Logic ported from `move-app.sh` (must match its behavior exactly)
Stack detection, iCloud stub (`*.icloud`) materialization, Python venv detection by `pyvenv.cfg` presence (not folder name) with `pip freeze` capture/recreate, git snapshot before/after (branch/HEAD/dirty-count), `mv`→`ditto` fallback with verification before deleting the source, broken-symlink and cross-project-symlink detection, residual absolute-path scanning. Full behavioral detail in the "legacy" section above.

## Technical decisions specific to the Swift port
- **iCloud**: `FileManager.startDownloadingUbiquitousItem(at:)` + bounded polling on `ubiquitousItemDownloadingStatus`, behind an `ICloudMaterializing` protocol — not `brctl`/`NSMetadataQuery`.
- **Git & copy**: `Process` calling `/usr/bin/git` and `/usr/bin/ditto` (same pattern as `TracerouteService` in `~/DevApps/NetworkTools/NetCheck`), not libgit2 — zero behavioral divergence from the bash tool's 121 validated runs.
- **Progress reporting**: `actor TransferPipeline` exposing `AsyncStream<TransferStep>`, consumed by a `@MainActor @Observable` view model. No Combine, no polling.
- **`TransferWarning` is a typed enum**, not free-text — `gitDeletedFilesDetected` (the `onyx` case) drives a `.critical` result distinct from `.warning`, surfaced as a non-dismissable alert. In the bash script this was just another line in a generic warning message that Vincent had to read carefully to catch; the port must not repeat that fragility.
- **Documents folder access**: `NSOpenPanel` (explicit user selection, defaults pre-filled to `~/Documents/GitHub`/`~/DevApps`) + persisted security-scoped bookmarks, rather than relying on the global TCC Documents toggle. Bookmarks are per-Mac and don't sync — each Mac does its own first-run root selection.
- **History**: plain JSON via an `actor TransferHistoryStore`, not SwiftData — the need (chronological list, no complex queries) doesn't justify the overhead.
- **Distribution**: repo is private, so Sparkle's usual `raw.githubusercontent.com` appcast pattern doesn't work without auth. v1 has no network auto-update — signed/notarized DMG via `Scripts/release.sh`, distributed manually between Vincent's Macs.

## Test strategy for the `onyx`-style silent data-loss bug
`DirectoryCopying` is a protocol; production uses `DittoCopier` (wraps `/usr/bin/ditto`), tests use a `FaultInjectingCopier` that copies file-by-file over a real local git fixture (`git init`/`add`/`commit` via `Process`, not a mocked git) while deliberately dropping a tracked file yet keeping the total file count equal — reproducing exactly the "count matched, but a tracked file vanished" shape of the real `onyx` incident. The pipeline must detect this via the git dirty-count diff (a `D ` entry), classify it `.critical`, and — the critical safety invariant — **not delete the source**.

