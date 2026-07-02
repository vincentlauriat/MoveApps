# MoveApps

App macOS native (+ script CLI legacy) pour migrer proprement des projets de développement entre `~/Documents/GitHub` (iCloud Drive, archive/inactif) et `~/DevApps` (local, actif), sans casser les dépôts git, les environnements virtuels Python, ni les projets Xcode/Node/Rust/Go.

## MoveApps.app (en cours de développement)

Réécriture SwiftUI native de `move-app.sh` : menu bar + fenêtre principale, transferts **bidirectionnels** (GitHub→DevApps et DevApps→GitHub), utilisable sur plusieurs Macs. Voir `PLAN.md` pour le phasage, `ARCHITECTURE.md`/`ARCHITECTURE_EN.md` pour la conception technique, `MEMORY.md` pour les décisions et l'état d'avancement.

État actuel : Phase 0 (scaffolding XcodeGen) terminée — build Debug + tests smoke verts. Prochaine étape : Phase 1 (portage de la logique métier + tests).

Le script `move-app.sh` documenté ci-dessous reste dans le repo comme référence/fallback CLI, non maintenu activement.

## `move-app.sh` (legacy CLI)

## Pourquoi
`~/Documents/Github` est synchronisé par iCloud Drive : les opérations fichier (git, mv) y sont plus lentes et parfois peu fiables (voir "Limitation connue" ci-dessous). `~/DevApps` est un répertoire local classique, non synchronisé.

## Usage

```bash
./move-app.sh                      # menu interactif (filtre par nom, ou fzf si installé)
./move-app.sh NomProjet ...        # déplace directement le(s) projet(s) nommé(s)
./move-app.sh --list               # liste tous les projets détectés avec leur stack
./move-app.sh --dry-run NomProjet  # simule sans rien modifier
```

### Options
| Option | Effet |
|---|---|
| `--dry-run` | N'effectue aucune modification, montre juste le plan |
| `--yes`, `-y` | Ne demande pas de confirmation par projet |
| `--keep-symlink` | Laisse un lien symbolique à l'ancien emplacement -> nouveau |
| `--reinstall-node` | Force la réinstallation de `node_modules` après déplacement |
| `--list` | Liste les projets disponibles avec leur type détecté |

## Ce que le script garantit
- [x] Détection du stack (git / node / python / xcode / rust / go)
- [x] Téléchargement forcé des fichiers iCloud non matérialisés avant déplacement
- [x] Recréation propre des environnements virtuels Python (un venv n'est pas relocalisable tel quel)
- [x] Vérification git avant/après (branche, HEAD, fichiers modifiés)
- [x] Détection des références résiduelles à l'ancien chemin et des liens symboliques cassés
- [x] Repli automatique `mv` → `ditto` en cas d'échec du déplacement natif (iCloud FileProvider)

## Limitation connue
Un simple `mv` entre `~/Documents/Github` et `~/DevApps` peut échouer avec `Operation timed out`, même si les deux chemins sont sur le même volume physique : l'extension FileProvider d'iCloud Drive intercepte l'opération. Le script bascule automatiquement sur `ditto` (copie + vérification du nombre de fichiers + suppression de la source seulement une fois la copie confirmée complète).

## État du projet (legacy)
- **Rollout complet** : les 121 projets de `~/Documents/Github` ont été migrés vers `~/DevApps` (2026-07-01 → 2026-07-02). Le dossier source ne contient plus aucun projet.
- Le script reste fonctionnel et disponible en fallback CLI, mais n'est plus activement maintenu — l'app SwiftUI (voir plus haut) prend le relais pour les transferts continus.

Voir `PLAN.md` / `TODOS.md` / `MEMORY.md` / `CHANGES.md` / `ARCHITECTURE.md` (`ARCHITECTURE_EN.md` en anglais) pour le détail.

## Structure du projet
```
MoveApps/
├── move-app.sh          # script legacy, fallback CLI non maintenu
├── project.yml           # spec XcodeGen de MoveApps.app
├── Sources/
│   ├── MoveAppsCore/      # framework logique pure (Models/Services/Pipeline/Persistence/Settings/Support)
│   ├── MoveAppsUI/        # framework UI (MainWindow/MenuBar/Settings/DragDrop/Components)
│   └── MoveApps/          # app target (MoveAppsApp.swift, Resources/Assets.xcassets)
├── Tests/MoveAppsCoreTests/
├── Scripts/               # fetch-sparkle-tools.sh, build.sh, release.sh
├── README.md
├── ARCHITECTURE.md       # FR
├── ARCHITECTURE_EN.md    # EN (source de vérité)
├── PLAN.md
├── TODOS.md
├── MEMORY.md
├── CHANGES.md
└── COMMANDS.md
```
