#!/usr/bin/env bash
# Compila los paquetes de aur-packages.txt en un chroot limpio de Arch y arma el repo local.
# Uso: iso/build-local-repo.sh   (FORCE=1 para reconstruir todo)
set -Eeuo pipefail
trap 'echo "ERROR: linea $LINENO: $BASH_COMMAND" >&2' ERR
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
B="$HERE/work-aur"
C="$B/chroot"
SRC="$B/src"
REPO="$HERE/repo/x86_64"
FORCE="${FORCE:-0}"
mkdir -p "$SRC" "$REPO"

if [[ -d "$C/root" ]]; then
  sudo arch-nspawn "$C/root" pacman -Syu --noconfirm
else
  mkdir -p "$C"
  sudo mkarchroot "$C/root" base-devel
fi

while read -r p; do
  case "$p" in
    ''|'#'*) continue ;;
  esac
  if [[ "$FORCE" == 0 ]] && compgen -G "$REPO/$p-[0-9]*.pkg.tar.*" >/dev/null; then
    echo "ya construido: $p"
    continue
  fi
  echo "== construyendo $p =="
  rm -rf "$SRC/$p"
  git clone --depth 1 "https://aur.archlinux.org/$p.git" "$SRC/$p"
  extra=()
  if [[ "$p" == umbriel-git ]]; then
    for f in "$REPO"/xdg-desktop-portal-umbriel-git-[0-9]*.pkg.tar.*; do
      extra+=(-I "$f")
    done
  fi
  (cd "$SRC/$p" && makechrootpkg -c -r "$C" "${extra[@]}")
  for f in "$SRC/$p"/*.pkg.tar.*; do
    case "$f" in
      *-debug-*) continue ;;
    esac
    cp "$f" "$REPO/"
  done
done < "$HERE/aur-packages.txt"

rm -f "$REPO"/noctaliaq.db* "$REPO"/noctaliaq.files*
repo-add "$REPO/noctaliaq.db.tar.gz" "$REPO"/*.pkg.tar.*
echo "repo listo: $REPO"
