#!/usr/bin/env bash
# Deja solo los N backups más recientes por archivo base.
# Uso: rotate-backups.sh [N]   (default 3)
set -uo pipefail

KEEP=${1:-3}
DIRS=("$HOME/.config/noctalia" "$HOME/.config/foot" "$HOME/.config/systemd/user")

for dir in "${DIRS[@]}"; do
    [[ -d $dir ]] || continue
    # agrupa por nombre base, ignorando el sufijo .bak.<epoch> y variantes
    while IFS= read -r base; do
        mapfile -t files < <(ls -1t "$dir/$base".{bak,pre-*,corrupto,antes-*}.* 2>/dev/null)
        (( ${#files[@]} > KEEP )) || continue
        for f in "${files[@]:$KEEP}"; do
            rm -f "$f" && echo "  borrado: ${f#$HOME/}"
        done
    done < <(find "$dir" -maxdepth 1 -type f -name '*.*.*' -printf '%f\n' \
             | sed -E 's/\.(bak|pre-[^.]*|corrupto|antes-[^.]*)\.[0-9]+$//' \
             | sort -u)
done
echo "✓ terminado (conservados: $KEEP por archivo)"
