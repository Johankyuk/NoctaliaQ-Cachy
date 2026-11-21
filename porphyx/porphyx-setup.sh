#!/usr/bin/env bash
# porphyx-setup.sh — segunda etapa: Umbriel + Noctalia + Luciole + noctalia-greeter + dotfiles (install.sh).
set -Eeuo pipefail
trap 'echo "ERROR: linea $LINENO: $BASH_COMMAND" >&2' ERR
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
export PORPHYX=1
die() { echo "ABORT: $*" >&2; exit 1; }
[ "$(id -u)" -ne 0 ] || die "corre como tu usuario, no como root"
command -v sudo >/dev/null 2>&1 || die "falta sudo"

echo "== Red =="
if ping -c1 -W5 archlinux.org >/dev/null 2>&1; then
  echo "ok"
else
  echo "Sin conexion. Conectate (nmtui) y vuelve a correr: porphyx setup" >&2
  exit 1
fi

echo "== Paquetes oficiales =="
mapfile -t PKGS < <(sed "s/#.*//" "$HERE/official-packages.txt" | tr -s " \t" "\n" | grep -v "^$")
sudo pacman -Syu --needed --noconfirm base-devel git less xdg-utils desktop-file-utils "${PKGS[@]}"

echo "== AUR: Umbriel (PKGBUILD a revision, compila local) =="
bash "$HERE/aur-install.sh" umbriel-git || die "umbriel-git no se instalo; sin el no hay sesion"
echo "== AUR: resto =="
for p in oh-my-zsh-git zsh-theme-powerlevel10k-git lavat zen-browser-bin luciole-git xdg-desktop-portal-umbriel-git; do
  bash "$HERE/aur-install.sh" "$p" || echo "AVISO: $p no se instalo" >&2
done

# install.sh llama a paru y a pacman -S paru (CachyOS); en Arch puro paru no existe: shim que usa aur-install.sh
TMPBIN="$(mktemp -d)"
trap 'rm -rf "$TMPBIN"' EXIT
{
  printf '\043\041/usr/bin/env bash\n'
  printf 'args=()\nfor a in "$@"; do case "$a" in -*) ;; *) args+=("$a") ;; esac; done\n'
  printf 'bash "%s/aur-install.sh" "${args[@]}" || echo "AVISO: aur-install fallo (se continua)" >&2\nexit 0\n' "$HERE"
} > "$TMPBIN/paru"
chmod +x "$TMPBIN/paru"

echo "== Dotfiles, Noctalia y Umbriel (install.sh) =="
PATH="$TMPBIN:$PATH" bash "$REPO/install.sh"

echo "== noctalia-greeter =="
bash "$REPO/greeter-setup/install-greeter.sh"

echo "✓ porphyx setup terminado — reinicia para entrar por el greeter"
