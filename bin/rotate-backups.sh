#!/usr/bin/env bash
# Deja solo los N backups más recientes por archivo base.
# Uso: rotate-backups.sh [N]   (default 3)
set -uo pipefail

KEEP=${1:-3}
if ! [[ $KEEP =~ ^[0-9]+$ ]]; then
    echo "error: N debe ser un entero, se recibio: $KEEP" >&2
    echo "uso: rotate-backups.sh [N]   (el script no acepta rutas)" >&2
    exit 2
fi
# raiz del repo, resuelta desde la ubicacion del script (bin/)
REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# desplegados + repo. config/niri/cfg del repo se omite: es el destino del symlink
# ~/.config/niri/cfg, ya cubierto arriba.
DIRS=("$HOME/.config/noctalia" "$HOME/.config/foot" "$HOME/.config/systemd/user" "$HOME/.local/state/noctalia" "$HOME/.config/niri/cfg" \
      "$REPO_DIR" "$REPO_DIR/bin" "$REPO_DIR/config/noctalia" "$REPO_DIR/config/systemd-user")

for dir in "${DIRS[@]}"; do
    [[ -d $dir ]] || continue
    # agrupa por nombre base, ignorando el sufijo .bak.<epoch> y variantes
    while IFS= read -r base; do
        mapfile -t files < <(ls -1t "$dir/$base".{bak,pre-*,corrupto,antes-*}.* 2>/dev/null)
        (( ${#files[@]} > KEEP )) || continue
        for f in "${files[@]:$KEEP}"; do
            rm -f "$f" && echo "  borrado: ${f#$HOME/}"
        done
    done < <(find -L "$dir" -maxdepth 1 -type f -name '*.*.*' -printf '%f\n' \
             | sed -E 's/\.(bak|pre-[^.]*|corrupto|antes-[^.]*)\.[0-9]+(-[0-9]+)?$//' \
             | sort -u)
done
echo "✓ terminado (conservados: $KEEP por archivo)"
