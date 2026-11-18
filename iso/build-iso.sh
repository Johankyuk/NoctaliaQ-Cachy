#!/usr/bin/env bash
# Arma la ISO: perfil releng de archiso + repo local + arbol git del repo (HEAD) en /opt/noctaliaq.
# Requisitos: haber corrido build-local-repo.sh y tener todo commiteado (se copia HEAD, no el working tree).
set -Eeuo pipefail
trap 'echo "ERROR: linea $LINENO: $BASH_COMMAND" >&2' ERR
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/.." && pwd)"
REPO_OUT="$HERE/repo/x86_64"
W="$HERE/work"
OUT="$HERE/out"
RELENG=/usr/share/archiso/configs/releng

[[ -f "$REPO_OUT/noctaliaq.db" ]] || { echo "ABORT: falta el repo local, corre iso/build-local-repo.sh"; exit 1; }

sudo rm -rf "$W"
mkdir -p "$W" "$OUT"
cp -r "$RELENG" "$W/profile"
sed -i 's|^iso_name=.*|iso_name="noctaliaq"|; s|^iso_application=.*|iso_application="NoctaliaQ Arch Live/Installer"|' "$W/profile/profiledef.sh"

A="$W/profile/airootfs/opt/noctaliaq"
mkdir -p "$A/repo" "$A/src"
cp -a "$REPO_OUT/." "$A/repo/"
git -C "$REPO_DIR" archive --format=tar HEAD | tar -x -C "$A/src"
# KYU-ISO-CFG
python3 "$HERE/gen-config.py" "$HERE" "$A/archinstall.json"
cp -a "$HERE/overlay/." "$W/profile/"
sed -i 's|^  \["/usr/local/bin/choose-mirror"\]="0:0:755"|&\n  ["/usr/local/bin/noctaliaq-install"]="0:0:755"|' "$W/profile/profiledef.sh"

# KYU-ISO-BRAND
bash "$HERE/brand.sh" "$W/profile" "$REPO_DIR"
sudo mkarchiso -v -w "$W/work" -o "$OUT" "$W/profile"
/usr/bin/ls -lh "$OUT"
