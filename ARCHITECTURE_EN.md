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
│   ├── Services/       # StackDetector, ProjectScanner, ICloudMaterializer, VenvManager, GitService,
│   │                   # DirectoryMover, DirectoryCopying (+DittoCopier), NodeModulesInstaller,
│   │                   # SymlinkVerifier, ResidualPathScanner, DiskUsage, TemplateService,
│   │                   # InitScriptRunner, IndexGenerator
│   ├── Pipeline/       # TransferPipeline — actor, single entry point for the UI, exposes AsyncStream<TransferStep>
│   ├── Persistence/    # TransferHistoryStore (actor, JSON in Application Support), TransferRecord
│   ├── Settings/       # RootPathsSettings (@Observable, security-scoped bookmarks via NSOpenPanel)
│   └── Support/        # ProcessRunner, AsyncTimeout
├── MoveAppsUI/        # framework, depends on Core
│   ├── MainWindow/      # MainWindowView + MainWindowViewModel (Archive/Actif columns, stats+search header,
│   │                     # floating batch/progress pills, native Transferable drag & drop), TransferPlanView
│   │                     # (confirmation sheet), TransferHistoryView, BatchTransferView
│   ├── MenuBar/         # MenuBarIconView, MenuBarDashboardView, DashboardViewModel, NewProjectView
│   ├── Debug/           # DebugLogView — on-demand window tracing live TransferStep/TransferWarning activity
│   ├── Support/         # StackTagStyle (stack badge icon/tint), RootAccent (bespoke Archive/Actif colors),
│   │                     # DebugLogStore (@Observable ring buffer feeding the Debug window)
│   └── Settings/        # SettingsView, RootPathsController (NSOpenPanel + bookmarks)
└── MoveApps/          # thin app target — MoveAppsApp.swift (MenuBarExtra + Window(id:) incl. "debug" + Settings Scenes),
                       # AppDelegate (Dock visibility policy + Dock-icon-click reopen)
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
- **Documents access, revised**: `RootPathsController` (in `MoveAppsUI`) tries a `.withSecurityScope` bookmark first but falls back to a plain bookmark, because the app spawns `git`/`ditto` subprocesses via `Process` — forbidden under the App Sandbox, so it can never hold the entitlements a *true* security-scoped bookmark requires. Persistence/reconfiguration UX (`NSOpenPanel`, `UserDefaults`, stale/revoked detection surfaced as a "needs reconfiguration" flag) is otherwise exactly as originally planned.
- **`du`'s exit code is not a success signal**: `DiskUsage.sizeBytes(of:)` (via `ProcessRunner`) must not gate on `result.didSucceed`. `du -sk` exits non-zero (`1`) whenever it hits an unreadable or locked subdirectory (e.g. `"Resource deadlock avoided"` on some `.dSYM`/`.framework` bundles — common on real project trees), while still printing a valid total to stdout. Only `result.timedOut` means no answer was obtained; a non-zero exit with output must still be parsed.

## Dock icon reopen (2026-07-07)
`NSApplicationDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:)` is the only place a Dock-icon click reaches app code, but it's AppKit — it has no path to SwiftUI's `openWindow` environment action, which only exists on `App`/`Scene`/`View`. `AppDelegate` exposes `var openMainWindow: (() -> Void)?`, set once from `MoveAppsApp`'s `Window("main")` content's `.onAppear` (`appDelegate.openMainWindow = { openWindow(id: "main") }`) — the standard bridge for this class of AppKit↔SwiftUI problem. `applicationShouldHandleReopen` calls it when `hasVisibleWindows` is false, then activates the app.

## Main window: stats header, search, floating action pills (2026-07-07)
The main window gained a header strip (root counts + disk usage — reusing `DashboardViewModel`, previously menu-bar-only, now also injected into the `Window("main")` scene — and a name search filtering both columns) and replaced the full-width batch/progress bars with floating capsule "pills" overlaid at the bottom of the window instead of pushed inline in the column flow. `ProjectScanner.scan` also stopped surfacing genuinely empty container folders as fallback candidates (only non-empty, non-project folders still fall back, per its original "nothing silently disappears" contract), and `projectGroups` (in `MainWindowView`) now sorts loose projects and container folders into a single interleaved alphabetical list rather than two separately-sorted blocks.

## Root accent colors — bespoke, not system (2026-07-07)
Archive and Actif each get a dedicated adaptive `Color` (`RootAccent.swift`: a muted amber for Archive, a muted teal for Actif, both defined as dynamic `NSColor`s that switch shade between light/dark) instead of `.orange`/`Color.accentColor`. This was a deliberate fidelity call to an approved HTML design mockup: `.orange` and Vincent's system accent color are more saturated than the mockup's muted pair, and using the *system* accent for "Actif" specifically would make its intensity depend on Vincent's own accent-color choice rather than the considered two-tone identity chosen for this screen.

## Project index (`INDEX.md`) generation
`IndexGenerator` (MoveAppsCore, a pure `Sendable` struct) builds one unified Markdown index covering **both** roots and writes an **identical copy into each** (`<active>/INDEX.md` and `<archive>/INDEX.md`) — this is the app's answer to "keep a project catalog in both directories, generated by MoveApps itself". It reuses `ProjectScanner` to enumerate the individually-transferable projects per root (so it sees exactly the same project list the transfer UI does, container folders unpacked), groups them by root → category folder → root-level, and renders `**name** — \`path\` — stack — description` per entry. Descriptions are **extracted from each project's `README.md`** (first meaningful prose line, with a hardened filter that skips headings, badges, images, raw HTML/attribute lines, ASCII-art banners, multilingual nav bars and shell/install commands, decodes HTML entities, and falls back to the H1 title). Per-project disk size is deliberately omitted (one `du` per project is too slow for a regenerate-on-every-transfer action). Triggered two ways: the menu-bar dashboard's "Régénérer l'index" button (`DashboardViewModel.regenerateIndex`, with an inline success/failure banner) and automatically after every transfer/batch completes (`MainWindowViewModel.regenerateIndex`, fire-and-forget off the main actor). Both roots being identical means some relative links can only resolve from their own root's copy — so the location is rendered as a plain `\`container/name\`` path rather than a clickable link, avoiding broken links across the two identical copies.

## Test strategy for the `onyx`-style silent data-loss bug
`DirectoryCopying` is a protocol; production uses `DittoCopier` (wraps `/usr/bin/ditto`), tests use a `FaultInjectingCopier` that copies file-by-file over a real local git fixture (`git init`/`add`/`commit` via `Process`, not a mocked git) while deliberately dropping a tracked file yet keeping the total file count equal — reproducing exactly the "count matched, but a tracked file vanished" shape of the real `onyx` incident. The pipeline must detect this via the git dirty-count diff (a `D ` entry), classify it `.critical`, and — the critical safety invariant — **not delete the source**.

## Archive checkout lock (multi-Mac) + per-project size (2026-07-12)
The Archive root is shared (iCloud Drive) across Vincent's Macs, but until this point a project taken out of it (Archive→Active) simply vanished — another Mac had no way to tell "taken by someone" from "never existed". `CheckoutReference`/`CheckoutReferenceStore` (`MoveAppsCore`) close that gap: checking a project out leaves a marker at its original Archive slot recording which Mac took it and on which day, turning the slot into a reference instead of a full project. `TransferPipeline` refuses outright (hard block, no override) any plan against a project that already carries a checkout reference, and `ProjectScanner` recognizes the marker before its normal project-detection logic (both at root level and nested in a container folder) so a locked slot surfaces as such rather than being scanned as a real project or silently dropped as an empty folder. Checking a project back in (Active→Archive) clears the marker at the destination and sweeps for an orphaned one filed under a different container folder than the one it was taken from (`clearOrphans`). A "Libérer" action in the main window clears a stale/erroneous marker manually, behind a confirmation dialog, without touching any real content.

**iCloud content-eviction risk, and why the marker's filename carries the essential facts.** A naive hidden JSON marker would have a fatal flaw: the Archive is iCloud Drive-backed, and a file's *content* (not its directory entry) can be evicted locally, appearing as a `.name.icloud` placeholder whose body reads as nothing — a Mac reading it would see an "empty" slot and re-take an already-checked-out project, the exact failure mode the feature exists to prevent. This was caught via an advisor review before implementation, not discovered after the fact. The fix: the marker's **filename** — `MOVEAPPS-CHECKOUT__<sanitized-host>__<yyyy-MM-dd>.json` — encodes host and day directly, since names survive eviction (only wrapped as `.<name>.icloud`, still parseable by a regex accepting both forms: `^\.?MOVEAPPS-CHECKOUT__([A-Za-z0-9-]+)__(\d{4}-\d{2}-\d{2})\.json(\.icloud)?$`). The JSON body only adds bonus fields (`destinationPath`, `sizeBytes`) that degrade to `nil` when not yet materialized. Reading the marker directory must not use `.skipsHiddenFiles` — the evicted placeholder is dot-prefixed even though the real file isn't. `CheckoutReferenceStoreTests` constructs a real `.icloud`-suffixed placeholder file on disk to prove this holds, rather than asserting it as an assumption.

Host name: `Host.current().localizedName` (falling back to `ProcessInfo.processInfo.hostName` with `.local` stripped). The implementing agent found, by testing on the real machine before commit, that `ProcessInfo.hostName` alone resolves to an ISP reverse-DNS string on Vincent's actual network (`...ipv6.abo.wanadoo.fr`) rather than anything Mac-identifying — which would have silently defeated the whole point of the marker. Caught and fixed, not shipped.

Per-project disk size — deliberately omitted from `IndexGenerator` when it first shipped (see above) because a `du` per project was too slow for the auto-regenerate-after-transfer path — is now shown on every row in the main window and in `INDEX.md`, but without reintroducing that cost: `ProjectSizeCache` (`MoveAppsCore`, an in-memory-only actor, deliberately not persisted to disk) is warmed by `MainWindowViewModel` in a background task with bounded concurrency (~6 parallel `du`s) after each scan renders instantly, and `IndexGenerator.write` takes an optional size lookup — the auto-regenerate-after-transfer path passes the current cache snapshot (best-effort, falls back to `—` for anything not yet measured) rather than computing anything cold.

## Auto-update via Sparkle, and the private/public repo tradeoff (2026-07-12)
v1 shipped with no network auto-update because Sparkle's standard appcast pattern — an unauthenticated HTTP fetch of `appcast.xml` plus the DMG, typically served straight off `raw.githubusercontent.com`/GitHub Releases — only works against a **public** repo, and `MoveApps` was private. Embedding a GitHub token in the app to authenticate a private feed was considered and rejected: it's an extractable secret baked into a distributed binary, and not how Sparkle is designed to be used. Presented with the real options (make the source repo public / host just the appcast+DMG on a separate public surface while keeping source private / use the existing `vincentlauriat.github.io` Pages site), Vincent chose to make `vincentlauriat/MoveApps` public — the same setup `MarkdownViewer` already uses successfully, so the wiring here mirrors its actual (read, not guessed) `MarkdownViewerApp.swift` and `project.yml` closely.

`SPUStandardUpdaterController` (constructed once in `MoveAppsApp.swift`) is deliberately configured `automaticallyChecksForUpdates = true` but `automaticallyDownloadsUpdates = false` — background checks only, install always needs an explicit "Rechercher les mises à jour…" confirmation. This isn't just copied from `MarkdownViewer`; it matters more here, because MoveApps shells out to `git`/`ditto` mid-transfer via `TransferPipeline`, and Sparkle silently SIGKILL-ing and swapping the running app mid-operation would be a much worse failure mode than in a plain document viewer.

A dedicated Sparkle EdDSA keychain account, `MoveApps` (separate from `MarkdownViewer`'s own account — one key pair could in principle serve multiple apps, but per-app accounts keep a lost/rotated key's blast radius contained to one app), was generated once via `.sparkle-tools/bin/generate_keys --account MoveApps` and must **never be regenerated** — doing so would make every already-installed copy permanently reject future updates (this exact incident already happened once to `MarkdownViewer`, forcing a manual re-download for everyone on ≤ v0.8.0; see its `release-full.sh` header for the full story). `Scripts/release.sh` now Sparkle-signs the DMG and writes `appcast.xml` at the repo root as its final step, mirroring `release-full.sh`'s equivalent section.

One real bug caught before it could bite: `CFBundleVersion` — the build number Sparkle's comparator actually reads, not `MARKETING_VERSION` — had stayed hardcoded at `"1"` through both `0.1.0` and `0.2.0`. Harmless while no Sparkle feed existed, but two releases sharing the same build number are indistinguishable to Sparkle's version comparator, which would have silently broken update detection the moment auto-update went live. Bumped to `"2"` for `0.3.0`; every future release must bump `CURRENT_PROJECT_VERSION` in `project.yml` too, not just the marketing version — called out explicitly in `Scripts/release.sh`'s header comment now.

## On-demand Debug window (2026-07-14)
Vincent flagged that transfers can run long with only the compact progress pill for feedback, and asked for a debug window to trace everything happening — opened only on demand. Scope was narrowed with him via an explicit up-front choice: pipeline-step-level tracing (reusing the `TransferStep`s `TransferPipeline` already emits) versus also streaming live subprocess stdout/stderr from `git`/`ditto`/`npm install`. The latter would require reworking `ProcessRunner` — which currently buffers a process's output to completion via `Pipe.readDataToEndOfFile` rather than exposing a live callback — and every caller (`DirectoryMover`, `NodeModulesInstaller`, `VenvManager`, `GitService`). Vincent chose the pipeline-step level for a first version.

`DebugLogStore` (`MoveAppsUI/Support`) is a small `@Observable` ring buffer (bounded to the 500 most recent entries) created once in `MoveAppsApp.init` and injected via `.environment` into both the main window and a new `Window(id: "debug")` scene. `MainWindowViewModel` takes it as a constructor dependency and logs every `TransferStep` it already consumes off `TransferPipeline.run`'s `AsyncStream` (in both the single-transfer `run(_:)` and `runBatch(_:)` paths), plus each finished transfer's warnings broken onto their own line and colour-coded (info/warning/success/error, derived from `TransferResult.status`). Logging always happens — it costs nothing beyond re-rendering text the progress pill already computes — so the window shows full history immediately even when opened mid-transfer; only the *window* itself is opt-in, via a new toolbar button, never opened at launch.

`TransferHistoryView`'s private French warning-to-text mapping was extracted into `ProjectListing.describe(_ warning: TransferWarning)` so the history sheet and the new debug log render warnings identically instead of maintaining two copies.

**Not yet manually verified**: the actual GUI click-through (opening the window from the toolbar, watching it fill live during a real transfer, auto-scroll, the "Effacer" button) — only `xcodebuild` and `MoveAppsCoreTests` (49/49) were reverified green, neither of which exercises SwiftUI interaction.

