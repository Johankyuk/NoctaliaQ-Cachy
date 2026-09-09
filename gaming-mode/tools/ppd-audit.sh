#!/usr/bin/env bash
# ppd-audit.sh — barre los tres perfiles de PPD y captura qué nodo cambió.
# Solo lectura salvo por los tres `powerprofilesctl set`; restaura el perfil
# original al terminar. No requiere root.
#
#   bash gaming-mode/tools/ppd-audit.sh            # a stdout
#   bash gaming-mode/tools/ppd-audit.sh > audit.txt

set -uo pipefail

CPU=/sys/devices/system/cpu
r() { [[ -r "$1" ]] && cat "$1" 2>/dev/null || echo "n/a"; }

first() {  # primer glob que exista, o vacío
  local p
  for p in $1; do [[ -e "$p" ]] && { printf '%s' "$p"; return; }; done
}

AMD_DPM="$(first '/sys/class/drm/card*/device/power_dpm_force_performance_level')"
ABM="$(first '/sys/class/drm/card*-eDP-*/amdgpu/panel_power_savings')"
FAN="$(first '/sys/devices/platform/asus-nb-wmi/hwmon/hwmon*/pwm1_enable')"
NV="$(first '/sys/bus/pci/devices/*/power/runtime_status')"
for d in /sys/bus/pci/devices/*; do
  [[ -r "$d/vendor" ]] && [[ "$(cat "$d/vendor")" == "0x10de" ]] && NV="$d"
done

snap() {
  printf '\n===== %s =====\n' "$1"
  printf '%-26s %s\n' 'platform_profile'  "$(r /sys/firmware/acpi/platform_profile)"
  printf '%-26s %s\n' 'throttle_thermal'  "$(r /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy)"
  printf '%-26s %s\n' 'scaling_driver'    "$(r $CPU/cpu0/cpufreq/scaling_driver)"
  printf '%-26s %s\n' 'scaling_governor'  "$(r $CPU/cpu0/cpufreq/scaling_governor)"
  printf '%-26s %s\n' 'EPP'               "$(r $CPU/cpu0/cpufreq/energy_performance_preference)"
  printf '%-26s %s / %s\n' 'scaling min/max kHz' \
         "$(r $CPU/cpu0/cpufreq/scaling_min_freq)" "$(r $CPU/cpu0/cpufreq/scaling_max_freq)"
  printf '%-26s %s\n' 'boost (global)'    "$(r $CPU/cpufreq/boost)"
  printf '%-26s %s\n' 'boost (policy0)'   "$(r $CPU/cpufreq/policy0/boost)"
  printf '%-26s %s\n' 'amd_pstate status' "$(r $CPU/amd_pstate/status)"
  [[ -n "$AMD_DPM" ]] && printf '%-26s %s\n' 'amdgpu dpm level'  "$(r "$AMD_DPM")"
  [[ -n "$ABM"     ]] && printf '%-26s %s\n' 'amdgpu panel ABM'  "$(r "$ABM")"
  [[ -n "$FAN"     ]] && printf '%-26s %s\n' 'pwm1_enable'       "$(r "$FAN")"
  if [[ -n "${NV:-}" && -d "$NV" ]]; then
    printf '%-26s %s / %s / %s\n' 'dGPU ctrl/status/pstate' \
      "$(r "$NV/power/control")" "$(r "$NV/power/runtime_status")" "$(r "$NV/power_state")"
  fi
}

printf '### entorno\n'
printf '%-26s %s\n' 'kernel' "$(uname -r)"
printf '%-26s %s\n' 'ppd'    "$(pacman -Qi power-profiles-daemon 2>/dev/null | awk -F': ' '/^Versi|^Version/{print $2}')"
printf '%-26s %s\n' 'ExecStart' "$(systemctl show power-profiles-daemon -p ExecStart --value 2>/dev/null | tr -s ' ')"
printf '%-26s %s\n' 'ac_online' "$(r "$(first '/sys/class/power_supply/A*/online')")"
printf '\n### drivers y acciones que PPD cargó\n'
powerprofilesctl 2>&1
printf '\n### acciones bloqueadas / cargadas segun el journal\n'
journalctl -u power-profiles-daemon -b --no-pager 2>/dev/null \
  | grep -iE 'driver|action|profile' | tail -25

ORIG="$(powerprofilesctl get 2>/dev/null)"
[[ -n "$ORIG" ]] || { echo "sin PPD activo, nada que barrer"; exit 1; }
echo; echo "### barrido (perfil original: $ORIG)"
for p in power-saver balanced performance; do
  powerprofilesctl set "$p" 2>/dev/null || { echo "no pude fijar $p"; continue; }
  sleep 2
  snap "$p"
done
powerprofilesctl set "$ORIG" 2>/dev/null
printf '\n### restaurado a %s\n' "$ORIG"
