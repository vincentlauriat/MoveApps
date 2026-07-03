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

## MoveApps.app — housekeeping (not urgent)
- [ ] Commit + push the Phase 3 work on `feature/phase3-main-window` and merge to `main` when Vincent is ready (deliberately left uncommitted per his instruction to keep moving on the app first)
- [ ] Update doc files' commit itself is also pending (`COMMANDS.md`/`TODOS.md` edits from the repo-creation step are still uncommitted on `main`)

## MoveApps.app (SwiftUI native) — in progress
- [x] Plan approved (`~/.claude/plans/zesty-discovering-alpaca.md`) — menu bar + main window, native Swift reimplementation, bidirectional, private GitHub repo
- [x] Phase 0 — XcodeGen scaffolding, `git init`, Scripts, doc sync. Debug build + smoke test green.
- [x] Repo privé `vincentlauriat/MoveApps` créé sur GitHub, `origin` configuré, `main` poussée (3 commits) — https://github.com/vincentlauriat/MoveApps
- [x] Phase 1 — Core logic (`MoveAppsCore`) + Swift Testing suite, including the `onyx` ditto-data-loss fault-injection test (17 tests / 8 suites, independently re-verified green)
- [x] Phase 2 — Menu bar UI (`MenuBarExtra`, Settings with root pickers + login item) — build green, tests untouched, **needs Vincent's interactive click-through** (agent had no screen/Accessibility access to verify visually)
- [x] Phase 3 — Main window UI (two-column view, transfer plan/progress, history, drag & drop) — committed on `feature/phase3-main-window` (`4cd5041`), not yet merged to `main`/pushed
- [ ] Phase 4 — `Scripts/release.sh` full pipeline (codesign/notarize/DMG). Build+codesign+DMG steps validated end-to-end via `SKIP_NOTARIZE=1` dry run (2026-07-03), independently re-verified (`codesign --verify --deep --strict`, `spctl -a -t exec` both pass). **Blocked on notarization credentials — action requise de Vincent** :
  ```
  xcrun notarytool store-credentials "MoveApps-Notary" --apple-id "vincent@lauriat.fr" --team-id "KFLACS69T9"
  ```
  Nécessite un mot de passe app-specific généré sur appleid.apple.com — geste manuel, impossible à scripter. Une fois fait, `./Scripts/release.sh 0.1.0` (sans `SKIP_NOTARIZE`) produit un DMG signé + notarisé + stapled, prêt à distribuer.
- [ ] Optionnel, non bloquant : AppIcon réel (`Assets.xcassets/AppIcon.appiconset` n'a que des slots vides) — l'app buildera et se notarisera sans, juste sans icône personnalisée
- [x] Phase 5 (partiel) — comparaison stack detection bash vs Swift (`git node python` sur les deux), round-trip synthétique sur les vraies racines `~/DevApps`⇄`~/Documents/GitHub` (deux legs `.ok`, intégrité git + historique confirmée, nettoyage fait)
- [ ] Phase 5 (reste) — **action requise de Vincent** : nommer un projet réel déjà migré, à faible enjeu, pour refaire le round-trip dessus en conditions réelles (le test synthétique valide la mécanique mais pas les cas particuliers d'un vrai projet — venv réel, historique git profond, symlinks)
- [ ] Phase 5 — Cross-validation vs `move-app.sh`: `--list`/`--dry-run` comparison, and the first-ever real DevApps→GitHub→DevApps round trip (reverse direction has zero prod mileage)
- [ ] Later (not blocking v1): private Sparkle feed for auto-update (GitHub Releases + PAT, or similar) once the app is stable
