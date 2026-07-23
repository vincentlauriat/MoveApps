# MoveApps

App macOS native (+ script CLI legacy) pour migrer proprement des projets de développement entre `~/Documents/GitHub` (iCloud Drive, archive/inactif) et `~/DevApps` (local, actif), sans casser les dépôts git, les environnements virtuels Python, ni les projets Xcode/Node/Rust/Go.

## MoveApps.app (en cours de développement)

Réécriture SwiftUI native de `move-app.sh` : menu bar + fenêtre principale, transferts **bidirectionnels** (GitHub→DevApps et DevApps→GitHub), utilisable sur plusieurs Macs. Voir `PLAN.md` pour le phasage, `ARCHITECTURE.md`/`ARCHITECTURE_EN.md` pour la conception technique, `MEMORY.md` pour les décisions et l'état d'avancement.

**Index des projets** : MoveApps génère un `INDEX.md` unifié couvrant les deux racines (Actif + Archive) et en écrit une **copie identique dans chacune** (`~/DevApps/INDEX.md` et `~/Documents/GitHub/INDEX.md`). Chaque projet est listé avec son dossier-catégorie, sa stack détectée, sa taille disque et une description extraite de son `README.md`. Régénéré via le bouton « Régénérer l'index » du tableau de bord et automatiquement après chaque transfert.

**Dossier `Templates` copié, jamais déplacé** : le dossier de premier niveau `Templates` (scripts et squelettes partagés, référencés en chemin relatif depuis les deux racines) est traité comme une ressource partagée — listé comme une entrée unique, un transfert le **copie** vers l'autre racine sans toucher à l'original et sans poser de verrou de prise.

**Verrou de prise multi-Mac** : l'Archive (`~/Documents/GitHub`, iCloud Drive) est partagée entre les Macs de Vincent. Prendre un projet (Archive→Actif) laisse une trace à son emplacement d'origine — quel Mac l'a pris, quel jour — qui bloque toute nouvelle prise depuis un autre Mac tant que le projet n'est pas rendu (Actif→Archive). Un bouton « Libérer » permet d'effacer manuellement une trace périmée ou erronée. Voir `PLAN.md` Phase 6 / `ARCHITECTURE.md` pour le détail (notamment la résistance à l'éviction de contenu iCloud).

**Mises à jour automatiques** : depuis la 0.3.0, MoveApps vérifie les nouvelles versions au lancement via Sparkle (jamais d'installation sans confirmation explicite) — menu « Rechercher les mises à jour… ». Cela suppose que le repo GitHub soit public (c'est le cas depuis le 12/07/2026) : Sparkle lit `appcast.xml` et le DMG via `raw.githubusercontent.com`/GitHub Releases, sans identifiants. Le tout premier install sur un nouveau Mac reste manuel (Sparkle met à jour une installation existante, il n'en crée pas une) ; les releases suivantes se proposent ensuite automatiquement.

État actuel : Phases 0 à 5 terminées (logique métier, menu bar en tableau de bord, fenêtre principale, packaging/notarisation, cross-validation) — voir `PLAN.md`. Distribuable via DMG signé + notarisé + signé Sparkle (voir « Installation » ci-dessous). La fenêtre principale affiche désormais des listes hiérarchiques Archive/Actif avec en-têtes de dossier sélectionnables, un bandeau de compteurs/taille disque par racine + une recherche, et se rouvre au clic sur l'icône Dock ; le tableau de bord barre de menu propose la création de projet depuis un modèle. Phase 6 (verrou de prise + taille par projet) mergée sur `main` — voir `TODOS.md`. Une fenêtre **« Debug »** (bouton dédié dans la barre d'outils) trace en direct, à la demande, les étapes de chaque transfert en cours (utile quand un déplacement traîne en longueur) — voir `TODOS.md`. Chantier en cours par ailleurs : passe d'élégance visuelle sur la fenêtre principale (typographie, couleurs Archive/Actif sur mesure), pas encore confirmée par Vincent — voir `TODOS.md`.

## Installation

1. Téléchargez le DMG de la dernière version depuis la page **[Releases](https://github.com/vincentlauriat/MoveApps/releases)** du dépôt.
2. Ouvrez le DMG et glissez `MoveApps.app` dans le dossier **Applications**.
3. Lancez l'app depuis Applications (ou Spotlight). L'app est signée Developer ID et notariée par Apple : le premier lancement se fait normalement, sans avoir besoin de passer par un clic droit > Ouvrir pour contourner Gatekeeper.

**Prérequis** : macOS 26.0 ou ultérieur.

Une fois installée, MoveApps vérifie automatiquement les nouvelles versions (voir la note sur les mises à jour ci-dessus) : les releases suivantes n'ont plus besoin de repasser par cette page.

Voir aussi `USER_GUIDE.md` pour prendre en main l'app et `PRIVACY.md` pour la note de confidentialité.

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
│   ├── MoveAppsUI/        # framework UI (MainWindow/MenuBar/Debug/Settings)
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
