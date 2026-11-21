#!/usr/bin/env bash
# aur-install.sh pkg... — clona del AUR, muestra el PKGBUILD y compila con makepkg. Sin helper.
set -uo pipefail
[ "$(id -u)" -ne 0 ] || { echo "ERROR: no correr como root (makepkg lo rechaza)" >&2; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="${PORPHYX_AUR_CACHE:-$HOME/.cache/porphyx/aur}"
mkdir -p "$CACHE"
rc=0
for p in "$@"; do
  if pacman -Qi "$p" >/dev/null 2>&1; then echo "$p ya instalado, se omite."; continue; fi
  d="$CACHE/$p"
  rm -rf "$d"
  git clone -q "https://aur.archlinux.org/$p.git" "$d" || { echo "ERROR: no se pudo clonar $p" >&2; rc=1; continue; }
  pin="$(awk -v p="$p" '$1 == p { print $2 }' "$HERE/aur-pins.txt" 2>/dev/null | head -n 1)"
  if [ -n "$pin" ]; then
    git -C "$d" checkout -q "$pin" || { echo "ERROR: pin $pin de $p no existe" >&2; rc=1; continue; }
    echo "$p fijado en $pin"
  fi
  [ -f "$d/PKGBUILD" ] || { echo "ERROR: $p no tiene PKGBUILD" >&2; rc=1; continue; }
  if [ -z "${PORPHYX_ASSUME_YES:-}" ]; then
    echo "--- PKGBUILD de $p (sal del visor con q)"
    "${PAGER:-less}" "$d/PKGBUILD"
    read -r -p "Compilar e instalar $p? [S/n] " r </dev/tty
    case "${r:-s}" in n|N) echo "omitido: $p"; rc=1; continue ;; esac
  fi
  ( cd "$d" && makepkg -si --needed --noconfirm ) || { echo "ERROR: makepkg fallo en $p" >&2; rc=1; continue; }
done
exit $rc
