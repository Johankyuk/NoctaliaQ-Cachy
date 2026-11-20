#!/usr/bin/env bash
# Baja los paquetes oficiales que necesita la instalacion (a fecha de hoy) y arma un mirror local
# core/extra/multilib (db + paquetes + firmas) en iso/mirror, para instalar sin internet.
# Uso: iso/build-offline-mirror.sh
set -Eeuo pipefail
trap 'echo "ERROR: linea $LINENO: $BASH_COMMAND" >&2' ERR
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="$HERE/mirror"
D="$HERE/work-mirror"
read_list() { grep -vE '^[[:space:]]*(#|$)' "$1" | awk '{print $1}'; }

sudo -v
sudo rm -rf "$D"
mkdir -p "$D/db/local" "$D/cache"
cat > "$D/pacman.conf" <<'CONF'
[options]
Architecture = x86_64
SigLevel = Optional TrustAll
[core]
Server = https://fastly.mirror.pkgbuild.com/$repo/os/$arch
[extra]
Server = https://fastly.mirror.pkgbuild.com/$repo/os/$arch
[multilib]
Server = https://fastly.mirror.pkgbuild.com/$repo/os/$arch
CONF
{ read_list "$HERE/target-packages.txt"; read_list "$HERE/offline-extra-packages.txt"; } | sort -u > "$D/all.txt"
read_list "$HERE/aur-packages.txt" | sort -u > "$D/aur.txt"
comm -23 "$D/all.txt" "$D/aur.txt" > "$D/official.txt"
echo "paquetes oficiales pedidos: $(wc -l < "$D/official.txt")  (AUR aparte: $(wc -l < "$D/aur.txt"))"
PAC=(pacman --config "$D/pacman.conf" --dbpath "$D/db" --cachedir "$D/cache" --logfile "$D/pacman.log")
sudo "${PAC[@]}" -Sy
"${PAC[@]}" -Sp --noconfirm --print-format '%r %f' $(cat "$D/official.txt") | sort -u > "$D/map.txt"
echo "paquetes con dependencias: $(wc -l < "$D/map.txt")"
sudo "${PAC[@]}" -Sw --noconfirm $(cat "$D/official.txt")
sudo chown -R "$(id -u):$(id -g)" "$D"
rm -rf "$M"
while read -r repo file; do
  d="$M/$repo/os/x86_64"
  mkdir -p "$d"
  cp -f "$D/cache/$file" "$d/"
  if [ -f "$D/cache/$file.sig" ]; then cp -f "$D/cache/$file.sig" "$d/"; else echo "sin firma: $file"; fi
done < "$D/map.txt"
for d in "$M"/*/os/x86_64; do
  r=$(basename "$(dirname "$(dirname "$d")")")
  find "$d" -maxdepth 1 -type f \( -name '*.pkg.tar.zst' -o -name '*.pkg.tar.xz' \) -print0 | xargs -0 repo-add -q "$d/$r.db.tar.gz"
done
rm -rf "$D"
echo "--- mirror listo:"
du -sh "$M"
find "$M" -maxdepth 4 -type f \( -name '*.pkg.tar.zst' -o -name '*.pkg.tar.xz' \) | wc -l
