#!/usr/bin/env bash
# test-gpu-apply.sh — prueba en seco de noctaliaq-gpu-apply.service.
#
# Lanza la unidad SIN intencion registrada: debe terminar la sesion, abortar
# antes de tocar el nodo, y devolver greetd. Valida el camino de fallo, que es
# el que de verdad importa — el de exito ya cambia el modo de la GPU.
#
# Se corre DOS veces, la misma orden:
#   1a vez: verifica precondiciones y lanza (te saca de la sesion).
#   2a vez: tras volver a entrar, muestra el veredicto.
#
# El marcador vive en /run (tmpfs): sobrevive al cierre de sesion, no al
# reinicio. Que es exactamente la vida util que necesita.
#
set -uo pipefail

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; C='\033[0;36m'; D='\033[2m'; N='\033[0m'
ok(){   echo -e "${G}[+]${N} $1"; }
warn(){ echo -e "${Y}[i]${N} $1"; }
err(){  echo -e "${R}[x]${N} $1" >&2; }

UNIDAD=noctaliaq-gpu-apply.service
MARCA=/run/noctaliaq/test-en-curso
INTENT=/run/noctaliaq/gpu-mode-intent

# =============================================================== FASE 2 =====
if [ -f "$MARCA" ]; then
    echo -e "${C}Veredicto de la prueba en seco${N}"
    echo -e "${D}────────────────────────────────────────────${N}"
    fallos=0

    echo ""
    echo "— journal de la unidad —"
    journalctl -t noctaliaq-gpu-apply -t noctaliaq-gpu-mode \
        --since "$(cat "$MARCA")" --no-pager | sed 's/^/    /' || true

    echo ""
    if journalctl -t noctaliaq-gpu-apply --since "$(cat "$MARCA")" --no-pager 2>/dev/null \
         | grep -i "unbound variable\|command not found\|No such file" >/dev/null; then
        err "El script murio por un error de shell, no por la guardia."
        fallos=$((fallos+1))
    else
        ok "Sin errores de shell."
    fi

    if journalctl -t noctaliaq-gpu-apply --since "$(cat "$MARCA")" --no-pager 2>/dev/null \
         | grep -i "Sin intencion" >/dev/null; then
        ok "Abortó por la guardia de intencion, como debe."
    else
        warn "No se vio el mensaje de la guardia — revisa el journal de arriba."
        fallos=$((fallos+1))
    fi

    if [ "$(systemctl is-active greetd)" = active ]; then
        ok "greetd volvio (active)."
    else
        err "greetd NO esta activo."; fallos=$((fallos+1))
    fi

    # pgrep -c ya imprime 0 y sale con 1: el '|| echo 0' duplicaba la salida.
n=$(pgrep -cx niri 2>/dev/null); n=${n:-0}
    if [ "$n" = 1 ]; then ok "Un solo niri corriendo."
    else err "Hay $n procesos niri — quedaron huerfanos."; fallos=$((fallos+1)); fi

    nodo=$(cat /sys/class/firmware-attributes/asus-armoury/attributes/dgpu_disable/current_value 2>/dev/null)
    if [ "$nodo" = 0 ]; then ok "El nodo sigue en 0: no se toco nada."
    else err "El nodo quedo en '$nodo' — la prueba no debia escribir."; fallos=$((fallos+1)); fi

    echo ""
    if [ "$fallos" = 0 ]; then
        ok "PRUEBA SUPERADA. El camino de fallo es seguro."
        echo -e "  ${D}Ya puedes usar el boton real: noctaliaq-gpu-mode -> 2 -> s${N}"
    else
        err "$fallos comprobacion(es) fallaron. No uses el boton todavia."
    fi

    sudo rm -f "$MARCA" 2>/dev/null
    exit "$([ "$fallos" = 0 ] && echo 0 || echo 1)"
fi

# =============================================================== FASE 1 =====
echo -e "${C}Prueba en seco de $UNIDAD${N}"
echo -e "${D}────────────────────────────────────────────${N}"
abortar=0

systemctl list-unit-files "$UNIDAD" >/dev/null 2>&1 \
    && ok "Unidad instalada." \
    || { err "La unidad no esta instalada."; abortar=1; }

systemd-analyze verify "/etc/systemd/system/$UNIDAD" >/dev/null 2>&1 \
    && ok "Unidad valida." \
    || { err "systemd-analyze verify falla."; abortar=1; }

[ -x /usr/local/bin/noctaliaq-gpu-mode ] \
    && ok "Binario desplegado." \
    || { err "Falta /usr/local/bin/noctaliaq-gpu-mode"; abortar=1; }

if [ -s "$INTENT" ]; then
    err "Hay una intencion registrada ($(cat "$INTENT")). La prueba en seco la aplicaria de verdad."
    err "Limpiala con: sudo rm -f $INTENT"
    abortar=1
else
    ok "Sin intencion registrada: la unidad abortara sin escribir."
fi

# pgrep -c ya imprime 0 y sale con 1: el '|| echo 0' duplicaba la salida.
n=$(pgrep -cx niri 2>/dev/null); n=${n:-0}
[ "$n" = 1 ] && ok "Un solo niri ($n)." || { warn "Hay $n procesos niri antes de empezar."; }

echo -e "    ${D}uptime: $(uptime -p 2>/dev/null || echo '?')${N}"
echo -e "    ${D}sesiones: $(loginctl list-sessions --no-legend 2>/dev/null | wc -l)${N}"

[ "$abortar" = 1 ] && { echo ""; err "Corrige lo de arriba antes de continuar."; exit 1; }

echo ""
warn "Esto CIERRA tu sesion grafica. Guarda lo que tengas abierto."
echo -e "  Escape si algo se atasca: ${C}Ctrl+Alt+F2${N} y ${C}sudo systemctl start greetd${N}"
echo ""
read -rp "  ¿Lanzar la prueba? [s/N] " r
case "$r" in [sS]) ;; *) echo "  Cancelado."; exit 0 ;; esac

sudo install -d -m 0755 /run/noctaliaq
date '+%Y-%m-%d %H:%M:%S' | sudo tee "$MARCA" >/dev/null

echo ""
ok "Lanzando. Vuelve a entrar y corre esta misma orden para ver el veredicto."
sleep 2
sudo systemctl start --no-block "$UNIDAD"
