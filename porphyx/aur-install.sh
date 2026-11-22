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
  # dependencias que solo existen en el AUR: se instalan primero (cada una muestra su PKGBUILD)
  if [ -f "$d/.SRCINFO" ] && [ "${PORPHYX_AUR_DEPTH:-0}" -lt 4 ]; then
    deps="$(sed -n -E 's/^[[:space:]]*(depends|makedepends|checkdepends)(_[a-z0-9_]+)? = ([^<>=[:space:]]+).*/\3/p' "$d/.SRCINFO" | sort -u)"
    for dep in $deps; do
      pacman -T "$dep" >/dev/null 2>&1 && continue
      pacman -Sp "$dep" >/dev/null 2>&1 && continue
      echo "$p necesita $dep (solo AUR)"
      case ",${PORPHYX_AUR_STACK:-}," in *",$dep,"*) echo "ERROR: dependencia circular con $dep" >&2; rc=1; continue 2 ;; esac
      PORPHYX_AUR_STACK="${PORPHYX_AUR_STACK:-},$p" PORPHYX_AUR_DEPTH=$(( ${PORPHYX_AUR_DEPTH:-0} + 1 )) bash "$HERE/aur-install.sh" "$dep" || { echo "ERROR: la dependencia $dep de $p no se instalo" >&2; rc=1; continue 2; }
    done
  fi
  ( cd "$d" && makepkg -si --needed --noconfirm ) || { echo "ERROR: makepkg fallo en $p" >&2; rc=1; continue; }
done
exit $rc
