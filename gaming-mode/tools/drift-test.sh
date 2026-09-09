#!/usr/bin/env bash
# drift-test.sh — comprueba si algo (amd-pmf, firmware, PPD) tira la curva
# personalizada mientras la máquina está bajo carga sostenida.
#
#   bash gaming-mode/tools/drift-test.sh [segundos]     (default 180)
#
# Pone el perfil en performance, carga todos los hilos, muestrea cada 10 s y
# restaura el perfil original al terminar. Solo lectura sobre sysfs.

set -uo pipefail

DUR="${1:-180}"
INTERVALO=10

first() { local p; for p in $1; do [[ -e "$p" ]] && { printf '%s' "$p"; return; }; done; }
FAN="$(first '/sys/devices/platform/asus-nb-wmi/hwmon/hwmon*/pwm1_enable')"
FAN2="${FAN/pwm1_enable/pwm2_enable}"
RPM="$(first '/sys/class/hwmon/hwmon*/fan1_input')"
TEMP="$(first '/sys/class/hwmon/hwmon*/temp1_input')"
for h in /sys/class/hwmon/hwmon*; do
  [[ -r "$h/name" && "$(cat "$h/name")" == k10temp ]] && TEMP="$h/temp1_input"
done

[[ -n "$FAN" ]] || { echo "no encontré pwm1_enable; ¿está instalado el módulo?"; exit 1; }

ORIG="$(powerprofilesctl get 2>/dev/null)" || { echo "sin PPD"; exit 1; }
echo "perfil original: $ORIG — pasando a performance"
powerprofilesctl set performance
sleep 3

# --- carga ---
NPROC="$(nproc)"
PIDS=()
if command -v stress-ng >/dev/null 2>&1; then
  stress-ng --cpu "$NPROC" --timeout "${DUR}s" >/dev/null 2>&1 &
  PIDS+=($!)
  echo "carga: stress-ng con $NPROC hilos"
else
  for _ in $(seq "$NPROC"); do
    ( while :; do :; done ) & PIDS+=($!)
  done
  echo "carga: $NPROC bucles de shell (instala stress-ng para algo más realista)"
fi

LIMPIO=0
limpiar() {
  # guardia de reentrada: sin esto, cada Ctrl+C relanza la limpieza entera
  [[ "$LIMPIO" == 1 ]] && return 0
  LIMPIO=1
  local p
  for p in "${PIDS[@]}"; do kill -9 "$p" 2>/dev/null; done
  wait 2>/dev/null
  powerprofilesctl set "$ORIG" 2>/dev/null
  echo "perfil restaurado: $ORIG"
}
# INT/TERM tienen que SALIR, no solo limpiar: si solo limpian, el bucle sigue
# y el sleep interrumpido devuelve al instante, disparando iteraciones locas
trap 'limpiar; exit 130' INT TERM
trap limpiar EXIT

# --- muestreo ---
printf '\n%-10s %-6s %-6s %-14s %-7s %s\n' HORA pwm1 pwm2 PERFIL TEMP RPM
fallos=0; n=0
fin=$(( $(date +%s) + DUR ))
while [[ $(date +%s) -lt $fin ]]; do
  p1="$(cat "$FAN" 2>/dev/null)"
  p2="$(cat "$FAN2" 2>/dev/null || echo -)"
  pf="$(cat /sys/firmware/acpi/platform_profile 2>/dev/null)"
  t="$(cat "$TEMP" 2>/dev/null || echo 0)"
  r="$(cat "$RPM" 2>/dev/null || echo -)"
  marca=""
  [[ "$p1" != 1 ]] && { marca=" <-- CURVA CAIDA"; fallos=$((fallos+1)); }
  printf '%-10s %-6s %-6s %-14s %-7s %s%s\n' \
    "$(date +%T)" "$p1" "$p2" "$pf" "$((t/1000))°C" "$r" "$marca"
  n=$((n+1))
  sleep "$INTERVALO"
done

printf '\n%d muestras, %d con la curva caída\n' "$n" "$fallos"
if [[ "$fallos" -eq 0 ]]; then
  echo "RESULTADO: sin deriva bajo carga. Nada tira la curva."
  exit 0
else
  echo "RESULTADO: algo desactivó la curva $fallos veces. Hace falta una red"
  echo "           (unidad path o timer que reaplique al detectar pwm1_enable != 1)."
  exit 1
fi
