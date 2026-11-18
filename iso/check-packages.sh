#!/usr/bin/env bash
# Verifica que todo target-packages.txt resuelva en core/extra/multilib de Arch puro.
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"
trap 'sudo rm -rf "$T"' EXIT
mkdir -p "$T/db" "$T/root"
cat > "$T/arch.conf" <<'EOC'
[options]
Architecture = auto
SigLevel = Required DatabaseOptional
[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
[multilib]
Include = /etc/pacman.d/mirrorlist
EOC
sudo pacman --config "$T/arch.conf" --dbpath "$T/db" -Sy >/dev/null
bad=0
while read -r p; do
  case "$p" in
    ''|'#'*) continue ;;
  esac
  if pacman --config "$T/arch.conf" --dbpath "$T/db" -r "$T/root" -Sp "$p" >/dev/null 2>&1; then
    :
  else
    echo "FALTA $p"
    bad=1
  fi
done < "$HERE/target-packages.txt"
if [[ "$bad" == 0 ]]; then
  echo "todos los paquetes resuelven en Arch"
else
  exit 1
fi
