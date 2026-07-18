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
- [x] AppIcon réel — fait le 2026-07-03 (squircle dégradé bleu + flèches bidirectionnelles, `Scripts/make-app-icon.swift`), DMG 0.1.0 régénéré avec l'icône le 2026-07-04. Cette ligne était restée cochée « optionnel » par erreur de synchro doc.
- [x] Phase 5 — comparaison stack detection bash vs Swift (`git node python` sur les deux), round-trip synthétique sur les vraies racines (deux legs `.ok`), round-trip réel sur `LinkManager` (choisi par Vincent) — checksums + git status identiques avant/après, venv fonctionnel
- [x] Bug trouvé + corrigé via le round-trip réel : `VenvManager.recreate()` perdait TOUS les paquets d'un venv si un seul pin exact devenait indisponible (ex. version retirée de PyPI) ; corrigé avec un repli paquet-par-paquet + test de régression déterministe. `LinkManager` réparé manuellement puis re-vérifié avec le correctif (2 legs `.ok`, 0 avertissement)
- [x] Auto-update feed — résolu autrement que prévu : repo `vincentlauriat/MoveApps` rendu public le 2026-07-12 (puis re-confirmé public le 2026-07-18 après deux retours mystérieux en privé), donc l'appcast public non-authentifié fonctionne ; pas besoin du feed privé + PAT envisagé ici
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
- [x] **Fenêtre « Nouveau projet »** : la sheet dans le popover disparaissait quand on ouvrait le Picker de modèles (popover éphémère qui perd le focus) → déplacée dans une vraie `Window("new-project")` indépendante.
- [x] **Choix du dossier de destination** : `TransferPlan.destinationContainer` + sélecteur dans `TransferPlanView` (Racine / dossiers existants / nouveau). Défaut = dossier source (`containerName`), donc la structure est conservée par défaut et modifiable. Le pipeline crée le dossier si absent. Symétrique dans les deux sens. Test pipeline `Outils/X`. **30 tests verts.** → corrige la perte de structure signalée par Vincent.
- [x] **Multi-sélection + transfert par lot** : case à cocher par ligne (sélection confinée à une racine), barre de lot « N sélectionnés · Transférer vers … », sheet `BatchTransferView` (liste + choix dossier « Conserver le dossier d'origine » par défaut ou tout forcer vers un dossier). Exécution séquentielle (`runBatch`), progression « Projet i/N ». Le bouton flèche par ligne reste pour un transfert unique. **30 tests verts, build OK.** → à valider visuellement par Vincent.

## MoveApps.app — génération de l'index des projets (2026-07-04)
- [x] **`IndexGenerator` (MoveAppsCore)** : construit un `INDEX.md` unifié couvrant les deux racines et en écrit une **copie identique dans chacune** (`~/DevApps/INDEX.md` + `~/Documents/GitHub/INDEX.md`). Réutilise `ProjectScanner`, groupe par racine → dossier-catégorie → racine, entrées `**nom** — chemin — stack — description`.
- [x] **Descriptions extraites des README** : première ligne de prose, filtre robuste (titres/badges/images/HTML/`="`/ASCII art/nav multilingue/commandes shell écartés, entités HTML décodées, repli sur le titre H1). Validé sur les vraies racines — plus aucune scorie.
- [x] **Deux déclencheurs** : bouton « Régénérer l'index » du tableau de bord + régénération auto après chaque transfert/lot.
- [x] **8 tests `IndexGeneratorTests`**, suite complète **39 tests / 12 suites verte**, `BUILD SUCCEEDED`. Vrais `INDEX.md` générés dans les deux racines (104 projets : 25 actifs + 79 archivés), fichiers byte-identiques.
- [ ] **À valider visuellement par Vincent** : le bouton « Régénérer l'index » du tableau de bord et le bandeau de résultat (pas d'accès écran ici).
- [ ] Optionnel : taille disque par projet dans l'index (volontairement omise pour l'instant — un `du` par projet ralentirait la régénération auto à chaque transfert).

## MoveApps.app — Archive checkout lock (multi-Mac) + taille par projet (2026-07-12)
- [x] Modèle `CheckoutReference` + service `CheckoutReferenceStore` (écrire/lire/effacer, format de marqueur résistant à l'éviction iCloud — nom de fichier porteur des faits essentiels, pas seulement le contenu JSON). Voir `PLAN.md` Phase 6 pour le détail.
- [x] `ProjectScanner` : détection du marqueur avant la logique normale (top-level + niveau conteneur), `ProjectCandidate.checkoutReference`
- [x] `TransferPipeline` : pose du marqueur (Archive→Actif), effacement + balayage des orphelins (Actif→Archive), refus défensif d'un plan sur un projet déjà pris, nouveau `TransferWarning.checkoutReferenceWriteFailed`
- [x] `ProjectSizeCache` (en mémoire, partagé) + calcul en tâche de fond dans `MainWindowViewModel.refresh()`, sans bloquer le scan
- [x] `IndexGenerator` : colonne taille par ligne (repli sur cache, pas de `du` sur le chemin auto-régénération)
- [x] UI `MainWindowView` : ligne verrouillée (badge, « Pris par X le Y », bouton désactivé), bouton « Libérer » + confirmation, taille sur chaque ligne
- [x] Tests : `CheckoutReferenceStoreTests` (dont un test simulant un placeholder évincé iCloud), extension `ProjectScannerTests`/`TransferPipelineTests` (5 nouveaux cas, y compris via `FaultInjectingCopier`), `IndexGeneratorTests` — **49 tests / 13 suites verts**
- [x] Build (`./Scripts/build.sh` → BUILD SUCCEEDED) — implémenté par un agent executor délégué sur `feature/archive-checkout-lock`, relu et vérifié avant commit (correction du nom d'hôte : `Host.current().localizedName` au lieu de `ProcessInfo.hostName`, qui renvoyait un reverse-DNS FAI illisible sur le réseau réel de Vincent)
- [x] Revue finale + merge sur `main` (`eebd5f2`, rebuild + 49 tests revérifiés après merge)
- [ ] À valider par Vincent : comportement réel multi-Mac (deux Macs, un vrai cycle prise/retour) une fois les deux Macs synchronisés sur le même Archive iCloud — pas encore exercé en pratique, seulement sur fixtures synthétiques

## MoveApps.app — Release 0.3.0 + auto-update Sparkle (2026-07-12)
- [x] Repo `vincentlauriat/MoveApps` rendu public (choix explicite de Vincent) — condition nécessaire pour que Sparkle lise `appcast.xml`/le DMG sans identifiants
- [x] Clé EdDSA Sparkle dédiée générée (compte trousseau `MoveApps`), sauvegarde de la clé privée dans `~/.sparkle-keys-backup/MoveApps-private-key-backup.txt` (hors dépôt, `chmod 600`)
- [x] Câblage `SPUStandardUpdaterController` dans `MoveAppsApp.swift` (vérif en arrière-plan uniquement, jamais d'install sans confirmation) + menu « Rechercher les mises à jour… », clés `SU*` dans `project.yml`
- [x] `Scripts/release.sh` : signature Sparkle EdDSA + génération `appcast.xml` en fin de pipeline
- [x] `CFBundleVersion` corrigé (`1`→`2`, était resté figé depuis 0.1.0 — aurait cassé la détection de mise à jour Sparkle silencieusement)
- [x] Release `v0.3.0` publiée : DMG signé Developer ID + notarisé (Accepted) + staplé + signé Sparkle, vérification indépendante OK, `appcast.xml` poussé sur `main`
- [x] `appcast.xml` + DMG confirmés accessibles publiquement sans authentification après push (`raw.githubusercontent.com` + asset de release)
- [ ] **Important — à faire par Vincent** : déplacer `~/.sparkle-keys-backup/MoveApps-private-key-backup.txt` vers un gestionnaire de mots de passe puis supprimer le fichier en clair
- [ ] Installer `MoveApps-0.3.0.dmg` manuellement une première fois sur chaque autre Mac (le premier install reste manuel — Sparkle met à jour une install existante, il n'en crée pas une)
- [ ] À valider : un vrai cycle de mise à jour Sparkle de bout en bout (Mac sur 0.2.0/0.3.0 détecte et installe une version suivante) — seule la mécanique appcast/signature a été vérifiée jusqu'ici

## MoveApps.app — ménage des versions locales (2026-07-12)
- [x] `/Applications/MoveApps.app` mis à jour 0.2.0 → 0.3.0 (re-vérifié notarisé après remplacement)
- [x] Anciens DMG locaux supprimés (`0.1.0`, `0.2.0` — conservés sur GitHub Releases), `release/` ne garde que `0.3.0`
- [x] `build/` local (427 Mo) + DerivedData Xcode globale MoveApps (162 Mo) supprimés — régénérables au prochain build
- [x] Vérifié : aucun DMG/DerivedData MoveApps oublié ailleurs sur la machine (Downloads, Desktop, autres racines), aucun process MoveApps résiduel

## MoveApps.app — fenêtre Debug à la demande (2026-07-14)
- [x] `DebugLogStore` (`MoveAppsUI/Support/DebugLogStore.swift`, `@Observable`, borné aux 500 dernières lignes) alimenté par `MainWindowViewModel` à chaque `TransferStep` consommé (transferts simples et batch), avec avertissements et statut final détaillés
- [x] `DebugLogView` (`MoveAppsUI/Debug/DebugLogView.swift`) : nouvelle fenêtre SwiftUI `Window(id: "debug")`, ouverte à la demande depuis la barre d'outils de la fenêtre principale (icône `ladybug`), jamais au lancement — auto-scroll, code couleur info/avertissement/succès/erreur, bouton « Effacer »
- [x] `ProjectListing.describe(_ warning:)` extrait de `TransferHistoryView` pour être partagé entre l'historique et le journal debug
- [x] Build (`xcodebuild -scheme MoveApps`) et tests (`MoveAppsCoreTests`, 49/49) revérifiés verts après les changements
- [ ] **Non vérifié manuellement** : ouverture réelle de la fenêtre depuis le bouton, remplissage en direct pendant un vrai transfert, auto-scroll, bouton Effacer — seuls le build et les tests unitaires ont été revérifiés (aucun test ne couvre le clic-à-travers GUI) ; à confirmer par Vincent lors du prochain usage réel

## MoveApps.app — Release 0.4.0 (2026-07-14)
- [x] Branche `feature/debug-window` committée (2 commits : feature + bump version) puis mergée sur `main` (merge commit, historique local, pas de PR GitHub — convention du projet)
- [x] Version bumpée `0.3.0`→`0.4.0` / build `2`→`3` dans `project.yml`, `xcodegen generate`, `Info.plist` régénéré
- [x] Build + `MoveAppsCoreTests` (49/49) revérifiés verts sur `main` avant release
- [x] `./Scripts/release.sh 0.4.0` : DMG signé Developer ID + notarisé (Accepted) + staplé + signé Sparkle EdDSA, `appcast.xml` réécrit
- [x] Vérification indépendante : `stapler validate`, `spctl -a -t exec` (accepted/Notarized Developer ID), `codesign --verify --deep --strict`, checksum SHA-256 de l'asset GitHub téléchargé (authentifié) identique au DMG local
- [x] Release GitHub `v0.4.0` publiée (DMG en asset), `appcast.xml` committé et poussé sur `main`
- [x] **Bloquant pour l'auto-update, résolu le 2026-07-18** : le repo `vincentlauriat/MoveApps` était repassé **privé** (trouvé en vérifiant l'accessibilité publique de l'appcast/l'asset — tous deux en 404 non-authentifiés). Rendu public le 12/07 exprès pour Sparkle ; Vincent avait choisi explicitement de le laisser privé et de s'en occuper lui-même — voir section ci-dessous pour la résolution.

## MoveApps.app — repo repassé public + ménage machine (2026-07-18)
- [x] Repo `vincentlauriat/MoveApps` repassé public (`gh repo edit --visibility public`), confirmé via `gh api` (`private: false`)
- [x] Accessibilité non-authentifiée revérifiée bout en bout : `appcast.xml` → 200 avec contenu correct (`sparkle:shortVersionString` 0.4.0), DMG de la release `v0.4.0` → 200
- [x] Ménage machine : `/Applications/MoveApps.app` (stale 0.3.0) remplacé par la vraie 0.4.0 (re-vérifié `spctl`/`codesign` après coup), `release/MoveApps-0.3.0.dmg` + notes supprimés, `~/Downloads/MoveApps-0.3.0.dmg` orphelin supprimé, `build/` + DerivedData Xcode nettoyés (~432 Mo)
- [ ] **À surveiller** : c'est la 2e fois (14/07 puis 18/07) que le repo est retrouvé repassé en privé sans qu'aucune session ne l'ait fait — cause inconnue, vérifier `gh api repos/vincentlauriat/MoveApps --jq .private` après chaque future release

## MoveApps.app — bug ProjectScanner : conteneur mixte perd ses enfants sans marqueur (2026-07-18)
- [x] Bug reproduit et root-causé : dans `Experimentations` (`ChromeUsage` avec `.git`, `ClaudeDeck` et `drawio-skill-1.34.0` sans marqueur reconnu), seul `ChromeUsage` apparaissait côté Actif — dès qu'un enfant qualifie comme projet, `ProjectScanner.scan()` laissait tomber silencieusement tous les autres enfants du même dossier-conteneur
- [x] Corrigé (`Sources/MoveAppsCore/Services/ProjectScanner.swift`) : un enfant sans marqueur mais avec du contenu réel est désormais surfacé lui aussi (sans tag de stack), au lieu d'être ignoré
- [x] Test de régression `surfacesMarkerLessSiblingInMixedContainer` ajouté (`ProjectScannerTests.swift`), reproduisant le scénario exact `Experimentations`. Suite complète revérifiée : **50/50 verts**. Build Release revérifié (`CODE_SIGNING_ALLOWED=NO`, `BUILD SUCCEEDED`)
- [x] Tentative de démo live sur un build de test (DerivedData) interrompue par une vraie boîte de dialogue TCC macOS (accès Documents) — volontairement pas cliquée à la place de Vincent, process de test tué à la place.
- [x] Vincent a tranché : commit + push + merge + release. Version bumpée `0.4.0`→`0.4.1` / build `3`→`4`.

## MoveApps.app — réouverture Dock + refonte visuelle fenêtre principale (2026-07-07)
- [x] **Réouverture au clic sur l'icône Dock** : `AppDelegate.applicationShouldHandleReopen` + closure `openMainWindow` câblée depuis `MoveAppsApp`. Build OK. **Réglage « Afficher dans le Dock » activé de façon définitive** (2026-07-07, décision explicite de Vincent — `defaults write com.vincent.MoveApps showInDock -bool true`) ; note technique : la fenêtre principale ne s'ouvre pas automatiquement au lancement pour cette app agent tant qu'aucune fenêtre n'a jamais été ouverte (la closure `openMainWindow` n'est capturée qu'au premier `.onAppear`) — un clic manuel (menu bar ou Dock) reste nécessaire au moins une fois par lancement ; pas de permission Accessibilité dans ce terminal pour l'automatiser.
- [x] **Piste A choisie parmi 4 mockups** : bandeau de stats Archive/Actif (compteur + taille disque, réutilise `DashboardViewModel`) + recherche filtrant les deux colonnes, barre de sélection/progression en pilule flottante.
- [x] **Bug `DiskUsage` corrigé** : `du -sk` sort en code 1 sur les sous-dossiers verrouillés/`.dSYM` alors que le total est valide — ne plus se fier à `didSucceed`, seulement à `timedOut`. Timeout 60→120s.
- [x] **Dossiers vides masqués** dans `ProjectScanner` (ex. `_En cours`).
- [x] **Tri alphabétique unifié** : dossiers-conteneurs et projets isolés entrelacés dans un seul ordre au lieu de deux blocs séparés.
- [x] **Passe d'élégance visuelle** (plusieurs rounds, contre le mockup approuvé) : couleurs Archive/Actif sur mesure (`RootAccent.swift`, ambre + teal désaturés adaptatifs clair/sombre) au lieu de `.orange`/`Color.accentColor`, New York pour les titres de colonne, suppression de `design: .rounded` partout, en-têtes de dossier en petites majuscules discrètes sans icône, rayon des cartes réduit (14→10), badges de stack neutralisés (tint forcé explicite).
- [ ] **À valider visuellement par Vincent** : dernière capture reçue datait d'avant les 2 derniers correctifs (teal « Actif » sur mesure + neutralisation forcée des badges) — session terminée sans nouvelle capture de confirmation. Reprendre par une capture fraîche avant d'aller plus loin sur le look. Release 0.2.0 sortie sans attendre cette validation (décision explicite de Vincent) — traiter tout retour visuel comme suivi, pas comme régression.
  - **Capture fraîche reçue le 2026-07-07** (app 0.2.0 installée depuis le DMG, fenêtre ouverte manuellement par Vincent) : couleurs ambre/teal, typographie New York, en-têtes de dossier, badges neutres — tout conforme point par point à l'analyse de Claude. **Confirmation explicite de Vincent sur le rendu final toujours en attente** — ne pas cocher tant qu'il ne l'a pas validé lui-même.

## Release 0.2.0 (2026-07-07)
- [x] `project.yml` bumpé `0.1.0` → `0.2.0`, build Release vérifié (`BUILD SUCCEEDED` après nettoyage d'un cache SPM référençant l'ancien chemin pré-déplacement `~/DevApps/MoveApps`).
- [x] DMG 0.2.0 signé + notarisé (Accepted) + staplé via `Scripts/release.sh 0.2.0` (1.9M). Vérification indépendante OK : `stapler validate`, `spctl -a -t exec` sur l'app montée du DMG → accepted/Notarized Developer ID, `codesign --verify --deep --strict` OK.
- [x] Release GitHub créée avec le DMG en asset : https://github.com/vincentlauriat/MoveApps/releases/tag/v0.2.0
