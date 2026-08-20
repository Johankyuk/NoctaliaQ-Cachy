#!/usr/bin/env bash
# Despliega a /etc lo que install-greeter.sh no cubre (necesita root).
#   - regla polkit: sync de apariencia al greeter sin prompt
#   - drop-in systemd: race de DRM entre plymouth y greetd en cold boot
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Ejecutar con sudo" >&2; exit 1; }

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS=$(date +%s)

backup_and_copy() {
    local src=$1 dst=$2 mode=$3
    [[ -f $dst ]] && cp -a "$dst" "$dst.bak.$TS" && echo "  backup: $dst.bak.$TS"
    install -D -o root -g root -m "$mode" "$src" "$dst"
    echo "  ✓ $dst"
}

echo "→ regla polkit"
backup_and_copy "$SRC/49-noctalia-greeter-sync.rules" \
    /etc/polkit-1/rules.d/49-noctalia-greeter-sync.rules 644

echo "→ drop-in de greetd"
backup_and_copy "$SRC/systemd-overrides/greetd-plymouth-race.conf" \
    /etc/systemd/system/greetd.service.d/plymouth-race.conf 644

systemctl daemon-reload
echo "✓ terminado — la regla polkit aplica de inmediato; el drop-in en el próximo arranque"
