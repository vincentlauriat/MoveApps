# Architecture

## Vue d'ensemble
`move-app.sh` est un script bash unique et autonome (compatible bash 3.2 — la version livrée par défaut sur macOS) qui migre un répertoire de projet depuis `~/Documents/Github` (iCloud Drive) vers `~/DevApps` (local) sans le casser.

## Déroulé (par projet sélectionné)
1. **Sélection** — arguments CLI, ou interactif : `fzf -m` si installé, sinon un menu numéroté avec filtre par sous-chaîne (boucle jusqu'à obtenir une sélection non vide).
2. **Détection du stack** — présence de `package.json`, `requirements.txt`/`pyproject.toml`/`Pipfile`, `*.xcodeproj`/`*.xcworkspace`, `Cargo.toml`, `go.mod`, `.git` (via des appels `find` peu coûteux, maxdepth 2).
3. **Vérification iCloud** — `find -name '*.icloud'` ; si des fichiers sont trouvés, `brctl download` est déclenché et le script attend leur matérialisation (nombre de tentatives borné).
4. **Détection des venvs Python** — `find -name pyvenv.cfg` (et non une simple correspondance de nom de dossier, pour éviter les faux positifs), car un venv n'est pas relocalisable : ses scripts `bin/*` contiennent un shebang absolu codé en dur vers le chemin du venv lui-même. Pour chaque venv trouvé, `pip freeze` est capturé dans un fichier temporaire *avant* le déplacement, tant que l'ancien chemin absolu est encore valide.
5. **Snapshot git (avant)** — branche, HEAD, nombre de fichiers modifiés, le tout encapsulé dans une fonction `with_timeout` maison (aucun binaire GNU `timeout` sur cette machine), car les opérations git sur des arborescences gérées par iCloud peuvent être étonnamment lentes.
6. **Confirmation** — le plan est affiché et l'utilisateur confirme par projet, sauf avec `--yes`. `--dry-run` s'arrête ici.
7. **Déplacement (`move_dir`)** — essai de `mv` en premier (atomique et rapide quand ça fonctionne). En cas d'échec (en pratique : `Operation timed out`, car l'extension FileProvider d'iCloud intercepte `rename()` même entre chemins sur le même volume), repli sur `ditto` (l'outil d'Apple, qui matérialise/copie correctement le contenu iCloud) suivi d'une comparaison du nombre de fichiers entre source et destination. La source n'est supprimée (`rm -rf`) que lorsque les comptes correspondent — une copie non vérifiée n'est jamais supprimée.
8. **Recréation des venvs** — dans le nouvel emplacement, le dossier du venv déplacé (désormais cassé) est supprimé, un nouveau est créé avec `python3 -m venv`, puis les paquets sont réinstallés depuis le fichier freeze capturé à l'étape 4.
9. **Réinstallation node optionnelle** — uniquement avec `--reinstall-node` : détecte un lockfile pnpm/yarn/npm et réinstalle `node_modules` de zéro. Désactivé par défaut car un simple déplacement de répertoire ne casse généralement pas `node_modules` (ses symlinks/hardlinks sont soit relatifs, soit pointent vers des stores externes fixes, par ex. le store global pnpm).
10. **Lien symbolique de compatibilité optionnel** — `--keep-symlink` recrée l'ancien chemin comme lien symbolique vers le nouveau, pour les outils/IDE qui le référencent encore.
11. **Vérification (après)** — snapshot git comparé à l'étape 5 ; `grep -rl` sur l'arborescence déplacée (en excluant `.git`, `node_modules`, `.venv`, les dossiers de build/cache) à la recherche de toute référence résiduelle à l'ancien chemin absolu littéral ; `find -type l` + `readlink` pour repérer les liens symboliques pointant désormais vers une cible absolue inexistante.
12. **Rapport** — une ligne par projet OK / AVERTISSEMENT / ECHEC, plus un tableau récapitulatif final.

## Contraintes de conception
- **bash 3.2 uniquement** — pas de `mapfile`, pas de tableaux associatifs, pas de `${var,,}`. Les sélections sont construites avec des tableaux indexés classiques et des boucles `while IFS= read -r`.
- **Aucun coreutils GNU supposé présent** — il n'y a pas de binaire `timeout`/`gtimeout` sur cette machine ; remplacé par une fonction `with_timeout` maison (job en arrière-plan + watcher).
- **Sécurité avant vitesse** — n'écrase jamais une destination existante, ne supprime jamais une source avant qu'une copie soit vérifiée, les venvs Python sont toujours reconstruits à partir d'une liste de paquets capturée plutôt que d'être conservés tels quels après un déplacement.

## Point d'attention découvert en conditions réelles
Même si `~/Documents/Github` et `~/DevApps` rapportent le même identifiant de périphérique de système de fichiers (`stat -f "%d"`), un simple `mv` entre les deux n'est pas garanti d'être un renommage de métadonnées seul — l'extension FileProvider d'iCloud Drive intercepte l'opération et peut la faire expirer. Ceci a été découvert lors du premier test réel et n'est pas un cas limite théorique ; le repli `ditto` dans `move_dir` le gère de façon transparente.

---

# MoveApps.app — réécriture native SwiftUI (actuelle)

Le `move-app.sh` ci-dessus est désormais un fallback CLI non maintenu, gardé comme référence. L'outil actif est **MoveApps.app**, une app macOS native qui porte la même logique en Swift, ajoute une interface (menu bar + fenêtre principale), et rend les transferts bidirectionnels.

## Pourquoi une réécriture complète plutôt qu'un wrapper autour du script
Le rollout bash est terminé (121/121 projets), et c'est désormais un outil du quotidien piloté depuis une UI sur plusieurs Macs — un appel `Process` vers le script bash aurait fonctionné, mais Swift natif apporte la concurrence structurée pour un retour de progression en temps réel, des services testables derrière des protocoles (critique pour reproduire en sécurité des modes de défaillance comme le bug de perte de données `ditto` — voir plus bas — sans jamais toucher aux vrais dossiers de projets), et un modèle `TransferWarning`/`TransferResult` typé plutôt que le parsing de texte libre en sortie du script.

## Structure du projet
```
Sources/
├── MoveAppsCore/     # framework, logique pure, zéro import SwiftUI/AppKit
│   ├── Models/         # ProjectCandidate, StackTag, RootKind, TransferPlan, TransferStep,
│   │                    # TransferResult, TransferWarning, GitSnapshot, GitStatusEntry, VenvInfo
│   ├── Services/        # StackDetector, ICloudMaterializer, VenvManager, GitService,
│   │                    # DirectoryMover, DirectoryCopying (+DittoCopier), NodeModulesInstaller,
│   │                    # SymlinkVerifier, ResidualPathScanner
│   ├── Pipeline/        # TransferPipeline — actor, point d'entrée unique pour la UI, expose AsyncStream<TransferStep>
│   ├── Persistence/     # TransferHistoryStore (actor, JSON dans Application Support), TransferRecord
│   ├── Settings/        # RootPathsSettings (@Observable, security-scoped bookmarks via NSOpenPanel)
│   └── Support/         # ProcessRunner, AsyncTimeout
├── MoveAppsUI/         # framework, dépend de Core — MainWindow/, MenuBar/, Settings/, DragDrop/, Components/
└── MoveApps/           # app target mince — MoveAppsApp.swift (Scenes MenuBarExtra + Window(id:) + Settings)
```

## Logique portée depuis `move-app.sh` (doit reproduire exactement son comportement)
Détection de stack, matérialisation des stubs iCloud (`*.icloud`), détection de venv Python par présence de `pyvenv.cfg` (pas par nom de dossier) avec capture/recréation `pip freeze`, snapshot git avant/après (branche/HEAD/dirty-count), repli `mv`→`ditto` avec vérification avant suppression de la source, détection de symlinks cassés et cross-projet, scan des références résiduelles à l'ancien chemin absolu. Détail comportemental complet dans la section « legacy » ci-dessus.

## Décisions techniques spécifiques au port Swift
- **iCloud** : `FileManager.startDownloadingUbiquitousItem(at:)` + polling borné sur `ubiquitousItemDownloadingStatus`, derrière un protocole `ICloudMaterializing` — pas `brctl`/`NSMetadataQuery`.
- **Git & copie** : `Process` appelant `/usr/bin/git` et `/usr/bin/ditto` (même pattern que `TracerouteService` dans `~/DevApps/NetworkTools/NetCheck`), pas libgit2 — zéro divergence de comportement par rapport aux 121 exécutions validées de l'outil bash.
- **Retour de progression** : `actor TransferPipeline` exposant `AsyncStream<TransferStep>`, consommé par un view model `@MainActor @Observable`. Pas de Combine, pas de polling.
- **`TransferWarning` est un enum typé**, pas du texte libre — `gitDeletedFilesDetected` (le cas `onyx`) pilote un résultat `.critical` distinct de `.warning`, remonté comme une alerte non-fermable. Dans le script bash, ce n'était qu'une ligne noyée dans un message d'avertissement générique que Vincent devait lire attentivement pour la repérer ; le port ne doit pas reproduire cette fragilité.
- **Accès au dossier Documents** : `NSOpenPanel` (sélection explicite par l'utilisateur, defaults pré-remplis sur `~/Documents/GitHub`/`~/DevApps`) + security-scoped bookmarks persistés, plutôt que de compter sur le toggle TCC global Documents. Les bookmarks sont propres à chaque Mac et ne se synchronisent pas — chaque Mac fait sa propre sélection de racines au premier lancement.
- **Historique** : JSON simple via un `actor TransferHistoryStore`, pas SwiftData — le besoin (liste chronologique, pas de requêtes complexes) ne justifie pas la charge.
- **Distribution** : le repo est privé, donc le pattern habituel d'appcast Sparkle via `raw.githubusercontent.com` ne fonctionne pas sans authentification. Le v1 n'a pas d'auto-update réseau — DMG signé/notarisé via `Scripts/release.sh`, distribué manuellement entre les Macs de Vincent.

## Stratégie de test pour le bug de perte de données silencieuse façon `onyx`
`DirectoryCopying` est un protocole ; la prod utilise `DittoCopier` (encapsule `/usr/bin/ditto`), les tests utilisent un `FaultInjectingCopier` qui copie fichier par fichier sur un vrai dépôt git de fixture local (`git init`/`add`/`commit` via `Process`, pas un git mocké) tout en droppant délibérément un fichier tracké tout en gardant le nombre total de fichiers égal — reproduisant exactement la forme de l'incident réel `onyx` (« le comptage matchait, mais un fichier tracké a disparu »). Le pipeline doit détecter ce cas via le diff du dirty-count git (une entrée `D `), le classer `.critical`, et — invariant de sécurité critique — **ne pas supprimer la source**.

