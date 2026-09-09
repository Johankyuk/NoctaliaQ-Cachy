#!/usr/bin/env bash
# install-gaming-mode.sh — wizard del módulo gaming-mode de NoctaliaQ-Cachy.
#
#   ./install-gaming-mode.sh --probe       solo diagnostica, no toca nada
#   ./install-gaming-mode.sh               diagnostica, pregunta e instala
#   ./install-gaming-mode.sh --uninstall   revierte todo
#
# Sin set -e a propósito: cada paso aborta explícito con die().

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SELF_DIR/.." && pwd)"
WMI=/sys/devices/platform/asus-nb-wmi
STAMP="$(date +%Y%m%d-%H%M%S)"

C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_0=$'\033[0m'
ok()   { printf '%s  ok %s %s\n' "$C_OK" "$C_0" "$*"; }
info() { printf '   ·   %s\n' "$*"; }
warn() { printf '%s  !  %s %s\n' "$C_WARN" "$C_0" "$*"; }
die()  { printf '%s ERR %s %s\n' "$C_ERR" "$C_0" "$*" >&2; exit 1; }
head2(){ printf '\n%s── %s ──%s\n' "$C_DIM" "$*" "$C_0"; }

ask() {  # ask "pregunta" [s|n]  -> 0 si sí
  local q=$1 def=${2:-s} r
  read -r -p "   ${q} [$( [[ $def == s ]] && echo 'S/n' || echo 's/N' )] " r
  r="${r:-$def}"
  [[ "${r,,}" == s || "${r,,}" == y ]]
}

backup_and_copy() {  # src dst [modo]
  local src=$1 dst=$2 mode=${3:-0644}
  [[ -r "$src" ]] || die "no existe el origen: $src"
  # sudo para leer: /etc/polkit-1/rules.d es 750 root:polkitd y ni listar se puede
  if sudo test -e "$dst" && ! sudo cmp -s "$src" "$dst"; then
    sudo cp -a "$dst" "${dst}.bak.${STAMP}" || die "no pude respaldar $dst"
    info "respaldo: ${dst}.bak.${STAMP}"
  fi
  sudo install -Dm"$mode" "$src" "$dst" || die "no pude instalar $dst"
  sudo cmp -s "$src" "$dst" || die "verificación falló: $dst difiere del origen"
  ok "$dst"
}

# ===========================================================================
# 1. Sondeo
# ===========================================================================
PROBE_FAN_HWMON=""; PROBE_FANS=""; PROBE_DGPU_DISABLE=no; PROBE_NV=""; PROBE_PPD=no

probe() {
  head2 "Máquina"
  info "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) $(cat /sys/class/dmi/id/product_name 2>/dev/null)"
  info "kernel $(uname -r)"

  head2 "asus-nb-wmi"
  if [[ -d "$WMI" ]]; then
    ok "módulo cargado ($WMI)"
    if [[ -r "$WMI/dgpu_disable" ]]; then
      PROBE_DGPU_DISABLE=yes
      ok "dgpu_disable expuesto (valor actual: $(<"$WMI/dgpu_disable"))"
    else
      warn "sin dgpu_disable — se usará remove/rescan del bus PCI (funciona, algo más brusco)"
    fi
    [[ -r "$WMI/gpu_mux_mode" ]] && info "gpu_mux_mode = $(<"$WMI/gpu_mux_mode") (no se toca)"
    [[ -r "$WMI/throttle_thermal_policy" ]] && info "throttle_thermal_policy = $(<"$WMI/throttle_thermal_policy")"
  else
    die "no hay $WMI — este módulo asume una ASUS con asus-nb-wmi"
  fi

  head2 "Curvas de ventilador"
  local d
  for d in "$WMI"/hwmon/hwmon*; do
    [[ -r "$d/name" ]] || continue
    if [[ "$(<"$d/name")" == "asus_custom_fan_curve" ]]; then PROBE_FAN_HWMON="$d"; break; fi
  done
  if [[ -n "$PROBE_FAN_HWMON" ]]; then
    ok "hwmon asus_custom_fan_curve: $PROBE_FAN_HWMON"
    local f
    for f in 1 2; do
      if [[ -e "$PROBE_FAN_HWMON/pwm${f}_enable" ]]; then
        PROBE_FANS+="$f "
        local w="solo root"; [[ -w "$PROBE_FAN_HWMON/pwm${f}_enable" ]] && w="escribible"
        ok "fan$f presente (modo $(<"$PROBE_FAN_HWMON/pwm${f}_enable"), $w)"
      fi
    done
    [[ -n "$PROBE_FANS" ]] || warn "el hwmon existe pero no expone pwm1/pwm2"
  else
    warn "sin hwmon de curvas: este modelo/BIOS no soporta curvas personalizadas."
    warn "El resto del módulo (GPU + sincronía de perfiles) sí funciona."
  fi

  head2 "Perfiles de energía"
  if [[ -r /sys/firmware/acpi/platform_profile ]]; then
    ok "platform_profile = $(</sys/firmware/acpi/platform_profile)"
    info "opciones: $(cat /sys/firmware/acpi/platform_profile_choices 2>/dev/null)"
  fi
  for d in /sys/class/platform-profile/platform-profile-*; do
    [[ -r "$d/name" ]] && info "handler $(<"$d/name") -> $(cat "$d/profile" 2>/dev/null)"
  done
  if systemctl is-active --quiet power-profiles-daemon 2>/dev/null; then
    PROBE_PPD=yes
    ok "power-profiles-daemon activo (perfil: $(powerprofilesctl get 2>/dev/null))"
  else
    warn "power-profiles-daemon inactivo — Noctalia no podrá cambiar de perfil"
  fi

  head2 "GPU"
  local dev
  for dev in /sys/bus/pci/devices/*; do
    [[ -r "$dev/vendor" && -r "$dev/class" ]] || continue
    [[ "$(<"$dev/class")" == 0x0300* ]] || continue
    case "$(<"$dev/vendor")" in
      0x10de) PROBE_NV="$dev"
              ok "NVIDIA ${dev##*/}  runtime=$(cat "$dev/power/control" 2>/dev/null)/$(cat "$dev/power/runtime_status" 2>/dev/null)" ;;
      0x1002) ok "AMD ${dev##*/}  dpm=$(cat "$dev/power_dpm_force_performance_level" 2>/dev/null)" ;;
      *)      info "otra GPU ${dev##*/}" ;;
    esac
  done
  if [[ -n "$PROBE_NV" ]] && command -v nvidia-smi >/dev/null 2>&1; then
    if [[ "$(cat "$PROBE_NV/power/runtime_status" 2>/dev/null)" == suspended ]]; then
      info "dGPU dormida; no la despierto solo para sondear"
    else
      info "$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null)"
      local pmin pmax
      pmin=$(nvidia-smi --query-gpu=power.min_limit --format=csv,noheader,nounits 2>/dev/null)
      pmax=$(nvidia-smi --query-gpu=power.max_limit --format=csv,noheader,nounits 2>/dev/null)
      if [[ -n "${pmin:-}" && "$pmin" != "[N/A]" ]]; then
        ok "acepta -pl : rango ${pmin}-${pmax} W  -> puedes llenar NV_PL_* en power.conf"
      else
        info "no reporta rango de -pl (normal en móviles): deja NV_PL_* vacío"
      fi
      nvidia-smi -q -d SUPPORTED_CLOCKS >/dev/null 2>&1 \
        && ok "acepta -lgc (bloqueo de reloj gráfico)" \
        || info "sin relojes soportados reportados: -lgc puede fallar"
    fi
  fi
  if grep -qE '^MODULES=.*nvidia' /etc/mkinitcpio.conf 2>/dev/null; then
    warn "mkinitcpio.conf tiene nvidia en MODULES=: el modo integrado persistente"
    warn "no funcionará hasta quitarlos de ahí y correr 'sudo mkinitcpio -P'"
  fi

  head2 "Noctalia"
  command -v noctalia >/dev/null 2>&1 && ok "binario noctalia presente" || warn "no encontré 'noctalia' en PATH"
  [[ -f "$HOME/.config/noctalia/config.toml" ]] && ok "config desplegado" || warn "sin ~/.config/noctalia/config.toml"
  [[ -f "$REPO_DIR/config/noctalia/config.toml" ]] && ok "config del repo: $REPO_DIR/config/noctalia/config.toml" \
                                                   || warn "no detecté el repo (¿corriendo fuera de NoctaliaQ-Cachy?)"
  id -nG | tr ' ' '\n' | grep -qx wheel && ok "estás en el grupo wheel" || die "no estás en 'wheel': las reglas udev/polkit no te servirían"
}

# ===========================================================================
# 2. Instalación
# ===========================================================================
install_all() {
  head2 "Binarios"
  backup_and_copy "$SELF_DIR/bin/noctaliaq-power"    /usr/local/bin/noctaliaq-power    0755
  backup_and_copy "$SELF_DIR/bin/noctaliaq-gpu-mode" /usr/local/bin/noctaliaq-gpu-mode 0755
  info "van a /usr/local/bin y no a ~/.local/bin a propósito: greetd lanza niri por"
  info "PAM y ~/.local/bin nunca entra en el PATH heredado."

  head2 "Configuración"
  if [[ -f /etc/noctaliaq/power.conf ]] && ! cmp -s "$SELF_DIR/config/power.conf" /etc/noctaliaq/power.conf; then
    if ask "ya existe /etc/noctaliaq/power.conf con cambios. ¿Sobrescribir (se respalda)?" n; then
      backup_and_copy "$SELF_DIR/config/power.conf" /etc/noctaliaq/power.conf 0644
    else
      info "se conserva el existente"
    fi
  else
    backup_and_copy "$SELF_DIR/config/power.conf" /etc/noctaliaq/power.conf 0644
  fi

  head2 "Permisos (udev)"
  backup_and_copy "$SELF_DIR/system/60-noctaliaq-hwaccess.rules" /etc/udev/rules.d/60-noctaliaq-hwaccess.rules 0644
  sudo udevadm control --reload || die "udevadm control --reload falló"
  sudo udevadm trigger --subsystem-match=hwmon --action=add
  sudo udevadm trigger --subsystem-match=pci --action=add
  sudo udevadm settle
  if [[ -n "$PROBE_FAN_HWMON" ]]; then
    [[ -w "$PROBE_FAN_HWMON/pwm1_enable" ]] \
      && ok "pwm1_enable ya escribible sin root" \
      || warn "pwm1_enable sigue sin permiso de escritura; revisa 'udevadm test'"
  fi

  head2 "Switch de GPU (polkit)"
  backup_and_copy "$SELF_DIR/system/org.noctaliaq.gpu-mode.policy" \
                  /usr/share/polkit-1/actions/org.noctaliaq.gpu-mode.policy 0644
  if ask "¿instalar la regla que evita el prompt de contraseña (wheel + sesión local activa)?" n; then
    backup_and_copy "$SELF_DIR/system/49-noctaliaq-gpu-mode.rules" \
                    /etc/polkit-1/rules.d/49-noctaliaq-gpu-mode.rules 0644
  else
    info "sin regla: pkexec pedirá contraseña (auth_admin_keep, la recuerda un rato)"
  fi

  head2 "Persistencia"
  backup_and_copy "$SELF_DIR/system/noctaliaq-gpu-mode.service" \
                  /etc/systemd/system/noctaliaq-gpu-mode.service 0644
  backup_and_copy "$SELF_DIR/system/noctaliaq-power-resume" \
                  /usr/lib/systemd/system-sleep/noctaliaq-power-resume 0755
  sudo systemctl daemon-reload || die "daemon-reload falló"
  info "la unidad se habilita sola cuando uses 'noctaliaq-gpu-mode integrated --persist'"

  head2 "Hook de Noctalia"
  install_hook
}

install_hook() {
  local deployed="$HOME/.config/noctalia/config.toml"
  local repo="$REPO_DIR/config/noctalia/config.toml"
  local f
  for f in "$repo" "$deployed"; do
    [[ -f "$f" ]] || { warn "no existe $f — se omite"; continue; }
    cp -a "$f" "${f}.bak.${STAMP}" || die "no pude respaldar $f"
    python3 - "$f" <<'PY' || die "no pude insertar el hook en $f"
import re, sys

path = sys.argv[1]
hooks = {
    "power_profile_changed": '"/usr/local/bin/noctaliaq-power apply \\"$NOCTALIA_POWER_PROFILE\\""',
    "started":               '"/usr/local/bin/noctaliaq-power apply"',
}
src = open(path, encoding="utf-8").read()
lines = src.split("\n")

# [hooks] puede venir indentado: el config de Noctalia indenta secciones.
idx = next((i for i, l in enumerate(lines) if re.match(r"^\s*\[hooks\]\s*$", l)), None)
if idx is None:
    lines += ["", "[hooks]"]
    idx = len(lines) - 1
indent = re.match(r"^(\s*)", lines[idx]).group(1)

# fin de la sección: la siguiente cabecera [..] al mismo o menor nivel
end = len(lines)
for i in range(idx + 1, len(lines)):
    if re.match(r"^\s*\[", lines[i]):
        end = i
        break

changed = []
for key, value in hooks.items():
    pat = re.compile(r"^\s*" + key + r"\s*=")
    hit = next((i for i in range(idx + 1, end) if pat.match(lines[i])), None)
    new = indent + "  " + key + " = " + value
    if hit is None:
        lines.insert(end, new)
        end += 1
        changed.append(key + " (nuevo)")
    elif lines[hit].strip() != new.strip():
        print("  ! ya existe y difiere, NO se toca: " + lines[hit].strip())
    else:
        changed.append(key + " (sin cambios)")

if end < len(lines) and lines[end - 1].strip() and re.match(r"^\s*\[", lines[end]):
    lines.insert(end, "")

open(path, "w", encoding="utf-8").write("\n".join(lines))

# relectura: nunca confiar en el buffer de escritura
check = open(path, encoding="utf-8").read()
for key in hooks:
    if key not in check:
        sys.exit("  ERR " + key + " no quedó escrito en " + path)
print("  ok  " + path + " -> " + ", ".join(changed or ["nada que hacer"]))
PY
  done
  command -v noctalia >/dev/null 2>&1 && { noctalia config validate || warn "noctalia config validate reporta problemas"; }
}

verify() {
  head2 "Verificación"
  local p
  for p in /usr/local/bin/noctaliaq-power /usr/local/bin/noctaliaq-gpu-mode \
           /etc/noctaliaq/power.conf /etc/udev/rules.d/60-noctaliaq-hwaccess.rules \
           /usr/share/polkit-1/actions/org.noctaliaq.gpu-mode.policy \
           /etc/systemd/system/noctaliaq-gpu-mode.service \
           /usr/lib/systemd/system-sleep/noctaliaq-power-resume; do
    sudo test -e "$p" || die "falta $p"
  done
  ok "todos los archivos en su sitio"
  bash -n /usr/local/bin/noctaliaq-power    || die "noctaliaq-power tiene error de sintaxis"
  bash -n /usr/local/bin/noctaliaq-gpu-mode || die "noctaliaq-gpu-mode tiene error de sintaxis"
  ok "sintaxis de los scripts correcta"
  grep -q 'power_profile_changed' "$HOME/.config/noctalia/config.toml" 2>/dev/null \
    && ok "hook presente en el config desplegado" \
    || warn "el hook no aparece en ~/.config/noctalia/config.toml"
}

uninstall_all() {
  head2 "Desinstalando"
  sudo systemctl disable --now noctaliaq-gpu-mode.service 2>/dev/null
  sudo rm -f /usr/local/bin/noctaliaq-power /usr/local/bin/noctaliaq-gpu-mode \
             /etc/udev/rules.d/60-noctaliaq-hwaccess.rules \
             /etc/polkit-1/rules.d/49-noctaliaq-gpu-mode.rules \
             /usr/share/polkit-1/actions/org.noctaliaq.gpu-mode.policy \
             /etc/systemd/system/noctaliaq-gpu-mode.service \
             /usr/lib/systemd/system-sleep/noctaliaq-power-resume \
             /etc/modprobe.d/noctaliaq-gpu-mode.conf
  sudo udevadm control --reload; sudo systemctl daemon-reload
  warn "no toco /etc/noctaliaq/ ni los hooks del config.toml — quítalos a mano si quieres"
  warn "los ventiladores siguen con tu última curva: corre 'noctaliaq-power reset' antes,"
  warn "o escribe 3 en pwm1_enable, para devolverlos al automático de fábrica"
  ok "desinstalado"
}

# ===========================================================================
case "${1:-}" in
  --probe)     probe; printf '\n'; exit 0 ;;
  --uninstall) uninstall_all; exit 0 ;;
  "")          ;;
  *)           die "uso: ${0##*/} [--probe|--uninstall]" ;;
esac

probe
printf '\n'
ask "¿Instalo el módulo con lo detectado arriba?" s || { info "cancelado, no se tocó nada"; exit 0; }
install_all
verify

head2 "Aplicando por primera vez"
/usr/local/bin/noctaliaq-power apply || warn "la primera aplicación falló; revisa 'journalctl -t noctaliaq-power'"
printf '\n'
/usr/local/bin/noctaliaq-power status

cat <<'FIN'

Listo. Atajos sugeridos para keybinds.kdl:

    Mod+Shift+G { spawn "noctaliaq-power" "gaming" "on"; }
    Mod+Shift+N { spawn "noctaliaq-power" "gaming" "off"; }

Cambiar de GPU (cierra sesión primero para el modo integrado):

    noctaliaq-gpu-mode status
    noctaliaq-gpu-mode integrated --persist
    noctaliaq-gpu-mode hybrid --persist

Las curvas están en /etc/noctaliaq/power.conf. Tras editarlas:

    noctaliaq-power apply && noctaliaq-power status
FIN
