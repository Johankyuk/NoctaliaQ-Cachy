# Greeter: teclado ES + logging + race DRM en boot

**Fecha:** 2026-08-18
**Componente:** greetd + noctalia-greeter

## 1. Layout de teclado en inglés

`noctalia-greeter-session` no exporta variables XKB antes de lanzar
`noctalia-greeter-compositor`; sin ellas, wlroots cae al layout US.

Fix en `/etc/greetd/config.toml`:
```toml
[default_session]
command = "env XKB_DEFAULT_LAYOUT=es /usr/bin/noctalia-greeter-session -- --session niri"
user = "greeter"
```

## 2. Logging del greeter

`NOCTALIA_GREETER_LOG=/ruta` falla en silencio si el archivo destino no
existe de antemano con dueño `greeter` (el proceso no tiene permiso para
crearlo en `/var/log`). Preparar manualmente:

```bash
sudo touch /var/log/greeter-debug.log
sudo chown greeter:greeter /var/log/greeter-debug.log
sudo chmod 644 /var/log/greeter-debug.log
```

Config final:
```toml
command = "env XKB_DEFAULT_LAYOUT=es NOCTALIA_GREETER_LOG=/var/log/greeter-debug.log /usr/bin/noctalia-greeter-session -- --session niri"
```

## 3. Race de DRM al re-lanzar el greeter (device busy)

Tras logout/reinicio con la sesión de usuario recién usando el iGPU AMD
(`/dev/dri/card2`), greetd puede arrancar la siguiente sesión del greeter
antes de que el device se libere:
[ERROR] Could not take device: Device or resource busy
[ERROR] Failed to open device: '/dev/dri/card2': Device or resource busy
[INFO] Found 1 GPUs

Con solo NVIDIA disponible (card1), no hay conector físico (eDP-2 vive en
el iGPU), así que no hay salida visual — greeter "colgado" / pantalla negra.

**Workaround aplicado:** TTY (`Ctrl+Alt+F2`..`F6`) + reinicio del servicio:
```bash
sudo systemctl restart greetd
```

**Sin fix permanente todavía.** A explorar en otra sesión: delay/retry en
el arranque (`ExecStartPre=sleep N`), o por qué la sesión de usuario no
libera `/dev/dri/card2` a tiempo antes de que systemd reinicie
`greetd.service`.

## Pendiente

No se confirmó explícitamente si `ñ`/`á` se pueden escribir en el campo
de password (el login username-only sí funcionó con el layout aplicado).
