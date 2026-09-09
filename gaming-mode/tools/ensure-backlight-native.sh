#!/usr/bin/env bash
# ensure-backlight-native.sh — garantiza control de brillo nativo del panel.
#
# En equipos hibridos AMD+NVIDIA con panel cableado a la iGPU, el arbitraje de
# backlight del kernel puede elegir la ruta nvidia_wmi_ec. Cuando eso pasa,
# amdgpu se abstiene de registrar el suyo:
#
#   amdgpu 0000:XX:00.0: [drm] Skipping amdgpu DM backlight registration
#
# Con la dGPU presente el nodo EC funciona. Con la dGPU apagada por firmware
# (modo Integrada) el nodo sobrevive pero DEJA DE MOVER EL PANEL: acepta el
# valor, actual_brightness lo sigue, y la pantalla no cambia.
#
# 'acpi_backlight=native' hace que amdgpu registre su backlight (amdgpu_bl*,
# type=raw). Es una mejora valida en Hibrida tambien, no solo en Integrada.
#
# No toca nada si ya hay un amdgpu_bl* registrado o si el parametro ya esta.
# Requiere sudo. Requiere reinicio para aplicar.
#
#   ensure-backlight-native.sh          aplica si hace falta
#   ensure-backlight-native.sh --check  solo diagnostica, no escribe (rc=1 si falta)
#
set -uo pipefail

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; N='\033[0m'
ok(){   echo -e "${G}[+]${N} $1"; }
warn(){ echo -e "${Y}[i]${N} $1"; }
err(){  echo -e "${R}[x]${N} $1" >&2; }

CONF=/etc/sdboot-manage.conf
PARAM=acpi_backlight=native
SOLO_CHECK=0
[ "${1:-}" = "--check" ] && SOLO_CHECK=1

_tiene_amdgpu_bl(){
    local b
    for b in /sys/class/backlight/amdgpu_bl*; do
        [ -e "$b" ] && return 0
    done
    return 1
}

# --- 1. ¿hace falta? --------------------------------------------------------

if _tiene_amdgpu_bl; then
    ok "Backlight nativo ya presente: $(basename "$(echo /sys/class/backlight/amdgpu_bl*)")"
    exit 0
fi

if ! grep -q 'amdgpu' /proc/modules 2>/dev/null; then
    warn "Sin amdgpu cargado — este helper no aplica a este equipo."
    exit 0
fi

if grep -q "$PARAM" /proc/cmdline 2>/dev/null; then
    err "El parametro ya esta en la cmdline pero no hay amdgpu_bl*."
    err "Este panel no expone backlight nativo; el fix no sirve aqui."
    exit 1
fi

warn "Sin backlight nativo. amdgpu dice:"
journalctl -k -b --no-pager 2>/dev/null | grep -i 'backlight registration' | tail -1 | sed 's/^/    /'

[ "$SOLO_CHECK" = 1 ] && { warn "Falta $PARAM (--check, no se escribio nada)."; exit 1; }

# --- 2. bootloader ----------------------------------------------------------

if ! command -v sdboot-manage >/dev/null 2>&1; then
    err "sdboot-manage no esta instalado."
    err "Agrega '$PARAM' a la cmdline con la herramienta de tu bootloader y reinicia."
    exit 1
fi

[ -e "$CONF" ] || { err "No existe $CONF"; exit 1; }

# --- 3. escribir ------------------------------------------------------------

sudo cp "$CONF" "$CONF.bak.$(date +%Y%m%d-%H%M%S)" || { err "No se pudo respaldar $CONF"; exit 1; }

if ! grep -q '^LINUX_OPTIONS=' "$CONF"; then
    err "No hay linea LINUX_OPTIONS en $CONF — no se toca a ciegas."
    exit 1
fi

sudo sed -i "s/^LINUX_OPTIONS=\"\\(.*\\)\"\$/LINUX_OPTIONS=\"\\1 $PARAM\"/" "$CONF"

grep -q "$PARAM" "$CONF" || { err "El sed no aplico sobre $CONF."; exit 1; }
ok "$CONF: $(grep '^LINUX_OPTIONS' "$CONF")"

sudo sdboot-manage gen || { err "sdboot-manage gen fallo."; exit 1; }

# El ESP no es legible por el usuario: el glob va dentro del sudo, o zsh da un
# 'no matches found' que parece "no existe" y es "no puedo leer".
if ! sudo bash -c "grep -lq '$PARAM' /boot/loader/entries/*.conf"; then
    err "Las entradas generadas NO traen $PARAM. Editar el conf sin regenerar no sirve."
    exit 1
fi

ok "Entradas de arranque actualizadas:"
sudo bash -c 'grep -h "^options" /boot/loader/entries/*.conf' | sed 's/^/    /'
warn "Reinicia para aplicar. Verifica con los ojos, no con cat:"
echo "    brightnessctl set 10%   # debe oscurecer visiblemente"
