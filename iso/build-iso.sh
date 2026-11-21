#!/usr/bin/env bash
# Arma la ISO: perfil releng de archiso + instalador porphyx-install (online). El escritorio se instala despues con porphyx setup.
# Requisito: tener todo commiteado (se copia porphyx/porphyx de HEAD, no del working tree).
set -Eeuo pipefail
trap 'echo "ERROR: linea $LINENO: $BASH_COMMAND" >&2' ERR
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/.." && pwd)"
W="$HERE/work"
OUT="$HERE/out"
RELENG=/usr/share/archiso/configs/releng

sudo rm -rf "$W"
mkdir -p "$W" "$OUT"
cp -r "$RELENG" "$W/profile"
sed -i 's|^iso_name=.*|iso_name="porphyx"|; s|^iso_application=.*|iso_application="Porphyx Linux Arch Live/Installer"|' "$W/profile/profiledef.sh"

A="$W/profile/airootfs/opt/porphyx"
mkdir -p "$A"
git -C "$REPO_DIR" archive --format=tar HEAD porphyx/porphyx | tar -x -C "$A" --strip-components=1
# KYU-ISO-CFG
python3 "$HERE/gen-config.py" "$HERE" "$A/archinstall.json"
cp -a "$HERE/overlay/." "$W/profile/"
sed -i 's|^  \["/usr/local/bin/choose-mirror"\]="0:0:755"|&\n  ["/usr/local/bin/porphyx-install"]="0:0:755"|' "$W/profile/profiledef.sh"

# KYU-ISO-BRAND
bash "$HERE/brand.sh" "$W/profile" "$REPO_DIR"
sudo mkarchiso -v -w "$W/work" -o "$OUT" "$W/profile"
/usr/bin/ls -lh "$OUT"
