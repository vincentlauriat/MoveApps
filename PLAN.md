# Plan

## Phase 1 (legacy, `move-app.sh`) — Build the tool (done)
Design and implement `move-app.sh`: interactive selection, stack detection, iCloud stub handling, Python venv-safe recreation, git-safe move, post-move verification.

## Phase 2 (legacy) — Validate (done)
Dry-run against real projects (read-only), then one real end-to-end migration (`LinkManager`) to catch real-world issues. Found and fixed the `mv`/iCloud timeout bug during this phase.

## Phase 3 (legacy) — Rollout (done, 2026-07-02)
Migrated all 126 (121 net) projects from `~/Documents/Github` to `~/DevApps`. `move-app.sh` now kept as an unmaintained CLI fallback/reference — see MEMORY.md's "FINAL ROLLOUT SUMMARY".

---

## MoveApps.app — SwiftUI native rewrite (current focus)

Full plan detail: `~/.claude/plans/zesty-discovering-alpaca.md` (context, architecture, decisions). Summary below, kept in sync as phases complete.

**Goal**: replace the one-shot CLI (`move-app.sh`) with a native macOS app (menu bar + main window) for ongoing, bidirectional GitHub⇄DevApps transfers, usable across Vincent's Macs.

### Phase 0 — Scaffolding (done, 2026-07-02)
XcodeGen `project.yml`, target skeletons (`MoveAppsCore`/`MoveAppsUI`/`MoveApps`/`MoveAppsCoreTests`), `Scripts/{fetch-sparkle-tools,build,release}.sh`, `git init`, doc sync. Debug build + smoke test green.

### Phase 1 — Core logic + tests (done, 2026-07-02)
Ported `move-app.sh`'s logic natively to `MoveAppsCore` (`StackDetector`, `ICloudMaterializer`, `VenvManager`, `GitService`, `DirectoryMover`/`DirectoryCopying`, `NodeModulesInstaller`, `SymlinkVerifier`, `ResidualPathScanner`, `TransferPipeline` actor + `AsyncStream<TransferStep>`, `TransferHistoryStore`, `RootPathsSettings`). 17 tests / 8 suites, all green (independently re-verified), including the `onyx` fault-injection reproduction (`.critical` + source preserved). See MEMORY.md for implementation-level findings (`Process.waitUntilExit()` hang risk, deferred-deletion safety decision).

### Phase 2 — UI menu bar
`MoveAppsApp.swift` (3 Scenes), `MenuBarQuickPickView`, `SettingsView` (root pickers via `NSOpenPanel` + security-scoped bookmarks, login item toggle).

### Phase 3 — UI main window + history
`MainWindowView` (two-column GitHub/DevApps), `TransferPlanView` (confirmation step), `TransferProgressView`, `TransferHistoryView`, drag & drop.

### Phase 4 — Packaging & multi-Mac distribution
`Scripts/release.sh` full pipeline (codesign, notarize, DMG). v1: manual distribution (private repo, no Sparkle network feed yet). Validate first-launch flow on a fresh Mac (`NSOpenPanel` root selection, bookmarks are per-Mac).

### Phase 5 — Cross-validation against `move-app.sh`
Compare `--list`/`--dry-run` bash output vs the app's plan view on a real project. Most important test: a round trip (DevApps→GitHub→DevApps) on a low-stakes already-migrated project — the reverse direction has zero production mileage, unlike forward (121 real runs).
