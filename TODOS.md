# TODOs

## Done
- [x] Build `move-app.sh` (interactive picker, stack detection, iCloud stub handling, venv recreation, git verification)
- [x] Validate read-only paths (`--list`, `--dry-run`) against real projects
- [x] Fix `mv` iCloud timeout bug (ditto fallback)
- [x] End-to-end real test on `LinkManager` — passed

## Done (cont'd)
- [x] Remove the orphan empty venv at `~/DevApps/LinkManager/path/to/venv`
- [x] Migrate a first batch of 5 projects (`claude-code-setup`, `desktop-tutorial`, `googlecli`, `GartnerCIO`, `lauriat.fr`) via `move-app.sh -y`, all verified post-move

## Done (cont'd)
- [x] Batch 1/7 of the full bulk rollout (15 projects: `Chronos` → `ContextManager`) — migrated and independently re-verified

## Done (cont'd)
- [x] Batch 2/7 of the full bulk rollout (15 projects: `curl.md` → `headroom`) — migrated and independently re-verified

## Done (cont'd)
- [x] Batch 3/7 of the full bulk rollout (15 projects: `hermes` → `localhostmgr`) — migrated and independently re-verified, no warnings

## Done (cont'd)
- [x] Batch 4/7 of the full bulk rollout (15 projects: `LocalWebManager` → `NetDiscoWeb`) — migrated and independently re-verified
- [x] `NetCheck/.sparkle-tools`: broken cross-project symlink to old `MarkdownViewer` path — fixed, re-pointed to `~/DevApps/MarkdownViewer/.sparkle-tools`

## Done (cont'd)
- [x] Batch 5/7 of the full bulk rollout (15 projects: `NewsManager` → `printing-press-library`) — migrated and independently re-verified
- [x] `onyx`: **ditto silently dropped 3 tracked files** (`dropbox/__init__.py`, `dropbox/connector.py`, `.DS_Store`) during the move — recovered fully via `git restore` after confirming `.git` integrity. See CRITICAL finding in MEMORY.md.

## Done (cont'd)
- [x] Batch 6/7 of the full bulk rollout (15 projects: `prompts.chat` → `TeamsChat`) — migrated and independently re-verified

## Done (cont'd) — ROLLOUT COMPLETE
- [x] Batch 7/7, the FINAL batch of the full bulk rollout (18 projects: `TechDoc` → `zeroclaw`) — migrated and independently re-verified
- [x] `WifiManager/.sparkle-tools`: same broken cross-project symlink pattern as `NetCheck` — fixed, re-pointed to `~/DevApps/MarkdownViewer/.sparkle-tools`
- [x] **All 121 projects migrated. `~/Documents/Github` now empty of project folders** (only `CLAUDE.md` + 2 utility shell scripts remain, not migration targets).

## Done (cont'd) — venv cleanup
- [x] `glances/.venv`: reinstalled from `requirements.txt` (7 packages)
- [x] `Gatsby/GatbyViewer/venv`: reinstalled from `requirements.txt` (42 packages, incl. pandas/flask/ib_async)
- [x] `clarify`'s `bmad-story-automator` skill env: no runtime deps, installed `story-automator` itself editable (`pip install -e`) into `clarify/.venv` — `story-automator --help` confirmed working

## Open — cleanup items for Vincent (nothing urgent, nothing lost)
- [ ] `onyx`: **most important item** — `ditto` silently dropped 3 tracked files during the move, recovered via `git restore`, but worth Vincent double-checking `git log`/recent work on `onyx` just to be safe since this was a real (if rare) copy failure, not a hypothetical
- [ ] Tell Vincent: `MyTasks` and `symphony` had in-progress uncommitted work mid-migration — not caused by the tool, but worth him checking nothing else was writing to `~/Documents/Github` projects during the bulk rollout
- [ ] Not yet exercised in practice: the `.icloud` stub-file materialization path (no stub files existed at last scan) — worth watching the first time it actually triggers, though now moot since the rollout is done
- [ ] Optional: clean up the 3 leftover non-project files in `~/Documents/Github` (`CLAUDE.md`, `CommitTousLesDossiers.sh`, `MetsAJourLesGIT.sh`) if that folder should be fully retired

## MoveApps.app (SwiftUI native) — in progress
- [x] Plan approved (`~/.claude/plans/zesty-discovering-alpaca.md`) — menu bar + main window, native Swift reimplementation, bidirectional, private GitHub repo
- [x] Phase 0 — XcodeGen scaffolding, `git init`, Scripts, doc sync. Debug build + smoke test green.
- [ ] **Action requise de Vincent** : `gh repo create` a été bloqué par le garde-fou de sécurité (création de repo = geste humain explicite requis). Créer le repo privé `vincentlauriat/MoveApps` sur github.com/new, puis redonner la main pour `git remote add origin` + `git push`.
- [x] Phase 1 — Core logic (`MoveAppsCore`) + Swift Testing suite, including the `onyx` ditto-data-loss fault-injection test (17 tests / 8 suites, independently re-verified green)
- [x] Phase 2 — Menu bar UI (`MenuBarExtra`, Settings with root pickers + login item) — build green, tests untouched, **needs Vincent's interactive click-through** (agent had no screen/Accessibility access to verify visually)
- [ ] Phase 3 — Main window UI (two-column view, transfer plan/progress, history, drag & drop)
- [ ] Phase 4 — `Scripts/release.sh` full pipeline (codesign/notarize/DMG), manual multi-Mac distribution for v1 (no Sparkle feed yet — private repo)
- [ ] Phase 5 — Cross-validation vs `move-app.sh`: `--list`/`--dry-run` comparison, and the first-ever real DevApps→GitHub→DevApps round trip (reverse direction has zero prod mileage)
- [ ] Later (not blocking v1): private Sparkle feed for auto-update (GitHub Releases + PAT, or similar) once the app is stable
