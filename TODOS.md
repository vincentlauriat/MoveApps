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
- [x] Repo privé `vincentlauriat/MoveApps` créé sur GitHub, `origin` configuré, `main` poussée (3 commits) — https://github.com/vincentlauriat/MoveApps
- [x] Phase 1 — Core logic (`MoveAppsCore`) + Swift Testing suite, including the `onyx` ditto-data-loss fault-injection test (17 tests / 8 suites, independently re-verified green)
- [x] Phase 2 — Menu bar UI (`MenuBarExtra`, Settings with root pickers + login item) — build green, tests untouched, **needs Vincent's interactive click-through** (agent had no screen/Accessibility access to verify visually)
- [x] Phase 3 — Main window UI (two-column view, transfer plan/progress, history, drag & drop) — mergé sur `main` et poussé (`274428f`)
- [x] Phase 4 — `Scripts/release.sh` full pipeline (codesign/notarize/DMG). **Terminée 2026-07-03** : notarisation débloquée en réutilisant le profil trousseau générique `AppliMacVincentGithub` (déjà utilisé par `MarkdownViewer`/`RTKInfos`, même Apple ID/équipe — trouvé en s'inspirant du `Scripts/release.sh` de `MarkdownViewer`, aucune action manuelle de Vincent nécessaire finalement). `./Scripts/release.sh 0.1.0` exécuté pour de vrai : build Release → signature Developer ID + Hardened Runtime → DMG → notarisation Apple (`status: Accepted`) → stapling. Vérifié indépendamment : `spctl -a -t exec` → `source=Notarized Developer ID`, `stapler validate` → OK, `codesign --verify --deep --strict` → OK. DMG distribuable dans `release/MoveApps-0.1.0.dmg`.
- [ ] Optionnel, non bloquant : AppIcon réel (`Assets.xcassets/AppIcon.appiconset` n'a que des slots vides) — l'app build et se notarise sans, juste sans icône personnalisée
- [x] Phase 5 — comparaison stack detection bash vs Swift (`git node python` sur les deux), round-trip synthétique sur les vraies racines (deux legs `.ok`), round-trip réel sur `LinkManager` (choisi par Vincent) — checksums + git status identiques avant/après, venv fonctionnel
- [x] Bug trouvé + corrigé via le round-trip réel : `VenvManager.recreate()` perdait TOUS les paquets d'un venv si un seul pin exact devenait indisponible (ex. version retirée de PyPI) ; corrigé avec un repli paquet-par-paquet + test de régression déterministe. `LinkManager` réparé manuellement puis re-vérifié avec le correctif (2 legs `.ok`, 0 avertissement)
- [ ] Later (not blocking v1): private Sparkle feed for auto-update (GitHub Releases + PAT, or similar) once the app is stable
- [ ] Distribuer `release/MoveApps-0.1.0.dmg` sur les autres Macs de Vincent (AirDrop / iCloud Drive perso) — geste manuel

## MoveApps.app — retours d'usage de Vincent (2026-07-03)
- [x] Réglage « Afficher dans le Dock » ajouté (Settings) — `LSUIElement: true` statique + `NSApp.setActivationPolicy` piloté par `AppDelegate`/le toggle, persisté via `@AppStorage("showInDock")` (défaut `true`, comportement identique à avant si jamais touché). Vérifié au lancement (process bien présent dans le Dock par défaut) ; **le live-toggle depuis Settings reste à vérifier visuellement par Vincent** — les outils AppleScript/lsappinfo disponibles ici n'ont pas donné un signal fiable pour le confirmer par le code seul.
- [x] **Bug de scan corrigé** : les dossiers-conteneurs qui regroupent plusieurs projets (ex. `NetworkTools` contenant `NetCheck`/`WifiManager`/`NetDiscoPocket`/`NetDiscoWeb`/`InternetCheck`/`DiagnosticsReseau`) apparaissaient comme un seul élément non sélectionnable individuellement. Nouveau `ProjectScanner` (`MoveAppsCore`) : un dossier n'est listé tel quel que s'il est lui-même un projet (son propre `.git` ou un marker à sa racine directe) ; sinon ses sous-dossiers qui SONT des projets sont listés à sa place. Vérifié sur les vraies racines : 33 dossiers top-level → 91 projets réellement sélectionnables après décompactage, `NetworkTools` confirmé décomposé en ses 6 vrais projets. Test de régression `ProjectScannerTests.swift` avec le scénario exact.
- [x] Refonte visuelle Liquid Glass (macOS 26) de toute la surface UI (fenêtre principale, sheets, popup barre de menu, réglages) — déléguée à un agent designer, build + 21/21 tests revérifiés indépendamment. **Rendu visuel non vérifié par moi (pas d'accès écran) — à valider par Vincent à l'ouverture de l'app.**

## MoveApps.app — retours d'usage 2 (2026-07-03, après re-test visuel)
- [x] **Hiérarchie des dossiers-conteneurs visible** : nouveau champ `ProjectCandidate.containerName` rempli par `ProjectScanner`, affiché en sous-titre discret (icône dossier) sous le nom du projet dans les lignes de la fenêtre principale, de la popup barre de menu et de la sheet de confirmation. Test `ProjectScannerTests` étendu (`containerName == "Gatsby"` pour un sous-projet décompacté, `nil` sinon).
- [x] **Cinématique archiver/désarchiver unifiée** : la popup barre de menu ne transfère plus instantanément — elle ouvre désormais la même sheet de confirmation `TransferPlanView` que la fenêtre principale (rendue agnostique du view model via closures `onCancel`/`onConfirm`). `QuickPickViewModel` a gagné le flux `pendingPlan`/`prepareTransfer`/`confirmPending`/`cancelPending`.
- [x] **Popup en sections Actif/Archive** au lieu d'une liste plate mélangée (chaque section avec son compteur).

## MoveApps.app — refonte popup en tableau de bord (2026-07-03, fait)
- [x] Popup barre de menu transformée en **tableau de bord pur** (`MenuBarDashboardView`) : cartes par racine (compteurs Actif/Archive + espace disque), carte « dernier transfert » (nom/direction/date/statut), boutons « Nouveau projet » et « Ouvrir MoveApps ». Plus de liste ni de transfert dans la popup.
- [x] Bouton **« Nouveau projet »** depuis un **dossier de templates perso** (`templatesURL` dans `RootPathsSettings`, défaut `~/DevApps/.templates`, hors `RootKind`) : `TemplateService` liste les sous-dossiers-templates et copie le choisi via `DittoCopier` sous la racine Actif, `git init` optionnel. Sheet `NewProjectView`. Refuse noms vides/avec `/` et n'écrase jamais une destination existante.
- [x] Bouton **« Ouvrir MoveApps »** conservé dans le nouveau layout.
- [x] Service `DiskUsage` (`MoveAppsCore`, `du -sk`) + `ByteFormat`. Tests `DiskUsageTests`.
- [x] `TemplateService` + `ProjectTemplate` + `GitService.initRepository` + réglage du dossier de modèles dans Settings. Tests `TemplateServiceTests`. **29 tests / 11 suites verts, BUILD SUCCEEDED.**
- [x] `QuickPickViewModel` retiré → `ProjectListing` (statics `scanSync`/`describe` + `QuickProject`). Icône barre de menu pilotée par `mainWindow.isRunning`.
- [ ] **À valider visuellement par Vincent** : rendu du tableau de bord + flux « Nouveau projet » (pas d'accès écran ici).
