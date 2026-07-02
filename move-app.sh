#!/bin/bash
# move-app.sh — déplace proprement un ou plusieurs projets de
#   ~/Documents/Github/  (iCloud Drive)  vers  ~/DevApps/
# en les rendant utilisables immédiatement, sans casser les venvs Python,
# les repos git, les projets Xcode/Node/Rust/Go, ni les symlinks.
#
# Compatible bash 3.2 (bash livré par défaut sur macOS) : pas de mapfile,
# pas de tableaux associatifs, pas de dépendance à `timeout`/`fzf`/`gnu coreutils`.
#
# NB: pas de `set -u` ici volontairement -- bash 3.2 traite "${array[@]}" sur un
# tableau vide comme une variable non liée sous nounset (bug corrigé seulement en
# bash >= 4.4), ce qui ferait planter le script sur tout projet sans venv Python.

SRC_ROOT="${SRC_ROOT:-$HOME/Documents/Github}"
DEST_ROOT="${DEST_ROOT:-$HOME/DevApps}"

DRY_RUN=0
ASSUME_YES=0
KEEP_SYMLINK=0
REINSTALL_NODE=0
DO_LIST=0
NAMES=()

RESULTS_FILE=$(mktemp /tmp/move-app-results.XXXXXX)
trap 'rm -f "$RESULTS_FILE"' EXIT

# ---------- couleurs / affichage ----------
c_reset="\033[0m"; c_bold="\033[1m"; c_green="\033[32m"; c_yellow="\033[33m"; c_red="\033[31m"; c_blue="\033[34m"
info()  { printf "%b\n" "${c_blue}➜${c_reset} $*"; }
ok()    { printf "%b\n" "${c_green}✔${c_reset} $*"; }
warn()  { printf "%b\n" "${c_yellow}⚠${c_reset} $*"; }
err()   { printf "%b\n" "${c_red}✘${c_reset} $*" >&2; }
title() { printf "\n%b\n" "${c_bold}== $* ==${c_reset}"; }

usage() {
  cat <<EOF
Usage: $0 [options] [nom_app ...]

Sans argument : sélection interactive parmi les dossiers de $SRC_ROOT

Options:
  --list              Liste les projets disponibles (avec type détecté) et quitte
  --dry-run           N'effectue aucune modification, montre juste le plan
  --yes, -y           Ne demande pas de confirmation par projet
  --keep-symlink      Laisse un lien symbolique à l'ancien emplacement -> nouveau
  --reinstall-node    Force la réinstallation de node_modules (pnpm/yarn/npm)
                      après le déplacement (par défaut node_modules est conservé
                      tel quel, ce qui est sûr dans l'immense majorité des cas)
  -h, --help          Affiche cette aide

Exemples:
  $0                          # menu interactif
  $0 --dry-run AuditViewer    # simule le déplacement d'un seul projet
  $0 -y rtk graphify          # déplace deux projets sans confirmation
EOF
}

# ---------- timeout maison (pas de coreutils `timeout` sur cette machine) ----------
with_timeout() {
  # with_timeout <secondes> <commande...>
  local secs="$1"; shift
  "$@" &
  local pid=$!
  ( sleep "$secs" 2>/dev/null; kill -9 "$pid" 2>/dev/null ) &
  local watcher=$!
  wait "$pid" 2>/dev/null
  local status=$?
  kill "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  return $status
}

confirm() {
  # confirm "question" -> 0 si oui
  [ "$ASSUME_YES" -eq 1 ] && return 0
  local reply
  printf "%b" "${c_bold}$* [o/N] ${c_reset}"
  read -r reply
  case "$reply" in
    o|O|oui|Oui|y|Y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

human_size() {
  du -sh "$1" 2>/dev/null | awk '{print $1}'
}

# ---------- liste des projets ----------
list_apps() {
  find "$SRC_ROOT" -mindepth 1 -maxdepth 1 -type d ! -name ".*" -exec basename {} \; | sort
}

# ---------- détection du stack d'un projet ----------
detect_stack() {
  local dir="$1"
  local tags=""
  [ -d "$dir/.git" ] && tags="$tags git"
  [ -n "$(find "$dir" -maxdepth 2 -name package.json 2>/dev/null)" ] && tags="$tags node"
  [ -n "$(find "$dir" -maxdepth 2 \( -name requirements.txt -o -name pyproject.toml -o -name Pipfile \) 2>/dev/null)" ] && tags="$tags python"
  [ -n "$(find "$dir" -maxdepth 2 -name '*.xcodeproj' -o -maxdepth 2 -name '*.xcworkspace' 2>/dev/null)" ] && tags="$tags xcode"
  [ -n "$(find "$dir" -maxdepth 2 -name Cargo.toml 2>/dev/null)" ] && tags="$tags rust"
  [ -n "$(find "$dir" -maxdepth 2 -name go.mod 2>/dev/null)" ] && tags="$tags go"
  echo "$tags" | sed 's/^ *//'
}

cmd_list() {
  title "Projets détectés dans $SRC_ROOT"
  local n=0
  while IFS= read -r name; do
    n=$((n+1))
    local dir="$SRC_ROOT/$name"
    local tags
    tags=$(detect_stack "$dir")
    printf "%3d) %-35s [%s]\n" "$n" "$name" "${tags:-?}"
  done < <(list_apps)
}

# ---------- sélection interactive ----------
pick_apps() {
  if command -v fzf >/dev/null 2>&1; then
    NAMES=()
    while IFS= read -r line; do
      [ -n "$line" ] && NAMES+=("$line")
    done < <(list_apps | fzf -m --prompt="Sélection (Tab = multi, Entrée = valider) > ")
    return
  fi

  info "fzf non installé -> sélection par filtre texte."
  while true; do
    printf "%b" "${c_bold}Filtre (partie du nom, vide = tout afficher) : ${c_reset}"
    read -r filt
    local matches=()
    while IFS= read -r line; do
      matches+=("$line")
    done < <(list_apps | grep -i -- "${filt:-.}")

    if [ ${#matches[@]} -eq 0 ]; then
      warn "Aucun résultat pour '$filt'."
      continue
    fi

    local i=0
    for m in "${matches[@]}"; do
      i=$((i+1))
      printf "%3d) %s\n" "$i" "$m"
    done

    printf "%b" "${c_bold}Numéros à déplacer (ex: 1 3 5), 'all', ou vide pour refiltrer : ${c_reset}"
    read -r sel
    [ -z "$sel" ] && continue

    if [ "$sel" = "all" ]; then
      NAMES=("${matches[@]}")
      break
    fi

    NAMES=()
    for tok in $sel; do
      case "$tok" in
        ''|*[!0-9]*) continue ;;
      esac
      local idx=$((tok-1))
      if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#matches[@]}" ]; then
        NAMES+=("${matches[$idx]}")
      fi
    done
    [ ${#NAMES[@]} -gt 0 ] && break
    warn "Sélection vide, réessaie."
  done
}

# ---------- iCloud : forcer le téléchargement des fichiers non matérialisés ----------
materialize_icloud() {
  local dir="$1"
  local stubs
  stubs=$(find "$dir" -name "*.icloud" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$stubs" -gt 0 ]; then
    warn "$stubs fichier(s) encore dans le cloud (non téléchargés) dans $dir -> téléchargement forcé..."
    brctl download "$dir" >/dev/null 2>&1
    local tries=0
    while [ "$tries" -lt 30 ]; do
      stubs=$(find "$dir" -name "*.icloud" 2>/dev/null | wc -l | tr -d ' ')
      [ "$stubs" -eq 0 ] && break
      sleep 2
      tries=$((tries+1))
    done
    if [ "$stubs" -gt 0 ]; then
      warn "$stubs fichier(s) toujours non téléchargés après 60s -- ils seront copiés tels quels (macOS les matérialisera à l'usage)."
    else
      ok "Tous les fichiers sont maintenant téléchargés localement."
    fi
  fi
}

# ---------- détection des venvs Python (par pyvenv.cfg, pas juste le nom du dossier) ----------
find_venvs() {
  local dir="$1"
  find "$dir" -maxdepth 4 -name pyvenv.cfg 2>/dev/null | while IFS= read -r f; do
    dirname "$f"
  done
}

# ---------- snapshot git avant/après ----------
git_snapshot() {
  local dir="$1"
  [ -d "$dir/.git" ] || { echo "none||"; return; }
  local head branch dirty
  head=$(with_timeout 20 git -C "$dir" rev-parse HEAD 2>/dev/null)
  branch=$(with_timeout 20 git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  dirty=$(with_timeout 25 git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  echo "git|${branch:-?}|${head:-?}|${dirty:-?}"
}

# ---------- déplacement robuste d'un répertoire (iCloud-safe) ----------
# `mv` fait un rename() natif qui peut expirer (Operation timed out) quand la
# source est gérée par le FileProvider iCloud Drive, même sur le même volume.
# On tente mv d'abord (rapide quand ça marche), puis on bascule sur `ditto`
# (outil Apple, gère correctement la matérialisation iCloud) + vérification
# du nombre de fichiers + suppression de la source seulement si la copie est
# confirmée complète.
move_dir() {
  local src="$1" dest="$2"
  local mv_err
  mv_err=$(mktemp /tmp/move-app-mverr.XXXXXX)

  if mv "$src" "$dest" 2>"$mv_err"; then
    rm -f "$mv_err"
    return 0
  fi
  warn "mv direct a échoué ($(cat "$mv_err" 2>/dev/null)) -- repli sur copie via ditto..."
  rm -f "$mv_err"

  if ! with_timeout 1800 ditto "$src" "$dest"; then
    err "ditto a échoué ou a expiré."
    return 1
  fi

  local n_src n_dest
  n_src=$(find "$src" 2>/dev/null | wc -l | tr -d ' ')
  n_dest=$(find "$dest" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n_src" != "$n_dest" ]; then
    err "Copie incomplète (source: $n_src éléments, destination: $n_dest éléments) -- $dest conservé pour inspection, $src NON supprimé par sécurité."
    return 1
  fi

  if ! rm -rf "$src"; then
    warn "Copie OK mais suppression de l'ancien emplacement $src a échoué -- à nettoyer manuellement."
  fi
  return 0
}

# ---------- déplacement d'un projet ----------
move_one() {
  local name="$1"
  local src="$SRC_ROOT/$name"
  local dest="$DEST_ROOT/$name"

  title "$name"

  if [ ! -d "$src" ]; then
    err "Introuvable: $src"
    echo "$name|ECHEC|introuvable" >> "$RESULTS_FILE"
    return
  fi
  if [ -e "$dest" ]; then
    if ! confirm "$dest existe déjà. Écraser (fusion via mv impossible, il faut d'abord le supprimer/renommer) ? Annuler ce projet sinon."; then
      warn "Ignoré (destination déjà existante)."
      echo "$name|IGNORE|destination existante" >> "$RESULTS_FILE"
      return
    fi
    err "Suppression manuelle requise de $dest avant de continuer -- projet ignoré par sécurité."
    echo "$name|IGNORE|destination existante" >> "$RESULTS_FILE"
    return
  fi

  local tags
  tags=$(detect_stack "$src")
  local size
  size=$(human_size "$src")

  info "Stack détecté: ${tags:-inconnu}   Taille: ${size:-?}"

  materialize_icloud "$src"

  # venvs python : on capture l'état AVANT le déplacement (chemins encore valides)
  local venv_list=()
  while IFS= read -r v; do
    [ -n "$v" ] && venv_list+=("$v")
  done < <(find_venvs "$src")

  local freeze_files=()
  if [ ${#venv_list[@]} -gt 0 ]; then
    warn "${#venv_list[@]} environnement(s) virtuel(s) Python détecté(s) -- ils seront recréés après déplacement (un venv n'est pas relocalisable tel quel : ses scripts bin/* ont l'ancien chemin absolu en shebang)."
    local vi=0
    for v in "${venv_list[@]}"; do
      vi=$((vi+1))
      local ff
      ff=$(mktemp /tmp/move-app-freeze.XXXXXX)
      if [ -x "$v/bin/pip" ]; then
        with_timeout 30 "$v/bin/pip" freeze > "$ff" 2>/dev/null
      fi
      freeze_files+=("$ff")
      info "  venv: ${v#$src/} (${v})"
    done
  fi

  local before
  before=$(git_snapshot "$src")

  echo
  info "Plan: mv \"$src\" -> \"$dest\""
  [ ${#venv_list[@]} -gt 0 ] && info "      puis recréation de ${#venv_list[@]} venv(s) Python"
  [ "$REINSTALL_NODE" -eq 1 ] && echo "$tags" | grep -q node && info "      puis réinstallation node_modules"
  [ "$KEEP_SYMLINK" -eq 1 ] && info "      puis lien symbolique $src -> $dest"

  if [ "$DRY_RUN" -eq 1 ]; then
    warn "DRY-RUN : rien n'a été modifié."
    echo "$name|DRY-RUN|" >> "$RESULTS_FILE"
    return
  fi

  if ! confirm "Confirmer le déplacement de '$name' ?"; then
    warn "Ignoré par l'utilisateur."
    echo "$name|IGNORE|annulé par l'utilisateur" >> "$RESULTS_FILE"
    return
  fi

  if ! move_dir "$src" "$dest"; then
    err "Échec du déplacement -- voir détails ci-dessus."
    echo "$name|ECHEC|déplacement a échoué" >> "$RESULTS_FILE"
    return
  fi
  ok "Déplacé vers $dest"

  # recréation des venvs (dans dest, chemins relatifs préservés)
  local vi=0
  local venv_warns=""
  for v in "${venv_list[@]}"; do
    vi=$((vi+1))
    local rel="${v#$src/}"
    local newv="$dest/$rel"
    local ff="${freeze_files[$((vi-1))]}"
    info "Recréation venv: $rel"
    local pybin="python3"
    rm -rf "$newv"
    if ! "$pybin" -m venv "$newv" >/dev/null 2>&1; then
      warn "  échec création venv $rel"
      venv_warns="$venv_warns $rel(creation-echouee)"
      continue
    fi
    if [ -s "$ff" ]; then
      if ! with_timeout 300 "$newv/bin/pip" install -r "$ff" >/tmp/move-app-pip-$$.log 2>&1; then
        warn "  certains paquets n'ont pas pu être réinstallés dans $rel (voir /tmp/move-app-pip-$$.log)"
        venv_warns="$venv_warns $rel(install-partiel)"
      else
        ok "  paquets réinstallés dans $rel"
      fi
    else
      warn "  pas de liste de paquets capturée pour $rel (venv vide recréé) -- réinstalle manuellement depuis requirements.txt/pyproject.toml"
      venv_warns="$venv_warns $rel(vide)"
    fi
  done

  # réinstallation node optionnelle
  local node_warn=""
  if [ "$REINSTALL_NODE" -eq 1 ] && echo "$tags" | grep -q node; then
    if [ -f "$dest/pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
      info "Réinstallation node_modules via pnpm..."
      rm -rf "$dest/node_modules"
      ( cd "$dest" && with_timeout 600 pnpm install >/tmp/move-app-pnpm-$$.log 2>&1 ) || node_warn="pnpm install a échoué (voir /tmp/move-app-pnpm-$$.log)"
    elif [ -f "$dest/yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
      info "Réinstallation node_modules via yarn..."
      rm -rf "$dest/node_modules"
      ( cd "$dest" && with_timeout 600 yarn install >/tmp/move-app-yarn-$$.log 2>&1 ) || node_warn="yarn install a échoué (voir /tmp/move-app-yarn-$$.log)"
    elif command -v npm >/dev/null 2>&1; then
      info "Réinstallation node_modules via npm..."
      rm -rf "$dest/node_modules"
      ( cd "$dest" && with_timeout 600 npm install >/tmp/move-app-npm-$$.log 2>&1 ) || node_warn="npm install a échoué (voir /tmp/move-app-npm-$$.log)"
    fi
    [ -n "$node_warn" ] && warn "$node_warn"
  fi

  # symlink de compatibilité
  if [ "$KEEP_SYMLINK" -eq 1 ]; then
    ln -s "$dest" "$src"
    ok "Lien symbolique créé: $src -> $dest"
  fi

  # vérification git avant/après
  local after
  after=$(git_snapshot "$dest")
  local git_warn=""
  if [ "${before%%|*}" = "git" ]; then
    local b_branch b_head b_dirty a_branch a_head a_dirty
    b_branch=$(echo "$before" | cut -d'|' -f2); b_head=$(echo "$before" | cut -d'|' -f3); b_dirty=$(echo "$before" | cut -d'|' -f4)
    a_branch=$(echo "$after" | cut -d'|' -f2); a_head=$(echo "$after" | cut -d'|' -f3); a_dirty=$(echo "$after" | cut -d'|' -f4)
    if [ "$b_head" != "$a_head" ] || [ "$b_branch" != "$a_branch" ]; then
      git_warn="branche/HEAD différent après déplacement (avant: $b_branch@$b_head, après: $a_branch@$a_head)"
    elif [ "$b_dirty" != "$a_dirty" ]; then
      git_warn="nombre de fichiers modifiés différent avant/après ($b_dirty -> $a_dirty)"
    else
      ok "git OK: branche $a_branch, HEAD inchangé, $a_dirty fichier(s) modifié(s) (identique à avant)"
    fi
  fi
  [ -n "$git_warn" ] && warn "$git_warn"

  # recherche de références résiduelles à l'ancien chemin absolu
  local leftover
  leftover=$(grep -rIl --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.build \
    --exclude-dir=target --exclude-dir=DerivedData --exclude-dir=.venv --exclude-dir=venv \
    -- "$src" "$dest" 2>/dev/null)
  local leftover_warn=""
  if [ -n "$leftover" ]; then
    leftover_warn="références à l'ancien chemin trouvées dans: $(echo "$leftover" | tr '\n' ' ')"
    warn "$leftover_warn"
  fi

  # symlinks cassés
  local broken_links
  broken_links=$(find "$dest" -type l 2>/dev/null | while IFS= read -r l; do
    t=$(readlink "$l")
    if [ "${t:0:1}" = "/" ] && [ ! -e "$t" ]; then
      echo "$l -> $t"
    fi
  done)
  [ -n "$broken_links" ] && warn "lien(s) symbolique(s) cassé(s):
$broken_links"

  local status="OK"
  local detail=""
  if [ -n "$venv_warns" ] || [ -n "$node_warn" ] || [ -n "$git_warn" ] || [ -n "$leftover_warn" ] || [ -n "$broken_links" ]; then
    status="AVERTISSEMENT"
    detail="venv:[$venv_warns] node:[$node_warn] git:[$git_warn] chemins:[$leftover_warn]"
  fi
  echo "$name|$status|$detail" >> "$RESULTS_FILE"
  ok "Terminé: $name -> $status"
}

# ---------- main ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --keep-symlink) KEEP_SYMLINK=1; shift ;;
    --reinstall-node) REINSTALL_NODE=1; shift ;;
    --list) DO_LIST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) err "Option inconnue: $1"; usage; exit 1 ;;
    *) NAMES+=("$1"); shift ;;
  esac
done

if [ "$DO_LIST" -eq 1 ]; then
  cmd_list
  exit 0
fi

if [ ! -d "$SRC_ROOT" ]; then
  err "$SRC_ROOT introuvable."
  exit 1
fi
mkdir -p "$DEST_ROOT"

if [ ${#NAMES[@]} -eq 0 ]; then
  pick_apps
fi

if [ ${#NAMES[@]} -eq 0 ]; then
  warn "Aucun projet sélectionné."
  exit 0
fi

for n in "${NAMES[@]}"; do
  move_one "$n"
done

title "Résumé"
while IFS='|' read -r n status detail; do
  case "$status" in
    OK) printf "%b %-35s\n" "${c_green}✔${c_reset}" "$n" ;;
    AVERTISSEMENT) printf "%b %-35s %s\n" "${c_yellow}⚠${c_reset}" "$n" "$detail" ;;
    DRY-RUN) printf "%b %-35s (simulation)\n" "${c_blue}➜${c_reset}" "$n" ;;
    *) printf "%b %-35s %s\n" "${c_red}✘${c_reset}" "$n" "$detail" ;;
  esac
done < "$RESULTS_FILE"
