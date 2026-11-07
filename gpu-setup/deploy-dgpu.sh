#!/usr/bin/env bash
# deploy-dgpu.sh — instala el control de la dGPU (backends: firmware ASUS, runtime-pm). Requiere root. Idempotente.
# nvidia-powerd queda deshabilitado al arranque: noctaliaq-dgpu lo arranca/para con la dGPU.
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "ABORT: correr con sudo"; exit 1; }
D="$(cd "$(dirname "$0")" && pwd)"
B="$(bash "$D/noctaliaq-dgpu" backend)"
[[ "$B" != none ]] || { echo "sin backend para la dGPU: nada que instalar en esta maquina"; exit 0; }
echo "backend de la dGPU: $B"
MAP=(
  "noctaliaq-dgpu:/usr/local/bin/noctaliaq-dgpu:755"
  "org.noctaliaq.dgpu.policy:/usr/share/polkit-1/actions/org.noctaliaq.dgpu.policy:644"
  "49-noctaliaq-dgpu.rules:/etc/polkit-1/rules.d/49-noctaliaq-dgpu.rules:644"
  "noctaliaq-dgpu-boot.service:/etc/systemd/system/noctaliaq-dgpu-boot.service:644"
)
for m in "${MAP[@]}"; do
  IFS=: read -r src dst mode <<< "$m"
  install -Dm"$mode" "$D/$src" "$dst" && cmp -s "$D/$src" "$dst" || { echo "ABORT: $dst"; exit 1; }
  echo "ok  $dst"
done
systemctl daemon-reload && systemctl enable noctaliaq-dgpu-boot.service && systemctl disable nvidia-powerd.service || { echo "ABORT: systemctl"; exit 1; }
echo "DGPU DEPLOY OK"
