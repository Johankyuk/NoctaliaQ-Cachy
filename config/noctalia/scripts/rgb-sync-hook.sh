#!/usr/bin/env bash
# Despacha al sincronizador de RGB segun el hardware.
# Noctalia NO expande ~ en los hooks del config.toml: toda ruta se resuelve aca.
[ -f "$HOME/.cache/noctalia/palette-raw.conf" ] || {
    noctalia msg templates-apply >/dev/null 2>&1
    sleep 1
}
case "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" in
  Alienware) exec "$HOME/.local/bin/rgb-sync.py" ;;
  *)
    [ -x "$HOME/.local/bin/kbd-color-sync" ] && "$HOME/.local/bin/kbd-color-sync"
    [ -x "$HOME/.local/bin/mangohud-color-sync" ] && exec "$HOME/.local/bin/mangohud-color-sync"
    ;;
esac
