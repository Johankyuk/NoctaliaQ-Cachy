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

---

## 4. Fallbacks de apps del launcher no respetan defaults del sistema

**Terminal:** el binario `noctalia` trae una lista de fallback hardcodeada
para abrir terminal (`gnome-terminal → x-terminal-emulator → kitty →
alacritty → wezterm → foot`), sin key de config expuesta para forzar una
específica. Con `alacritty`/`kitty` instalados, siempre ganaban sobre
`foot` aunque `foot` fuera el terminal real en uso.

**Fix:**
```bash
sudo pacman -R alacritty kitty
```

**Browser (parte 1 — auto-open de Jupyter vía http://):** el módulo
`webbrowser` de Python tiene su propia lista de navegadores conocidos por
nombre y los busca directo en PATH — no pasa por `xdg-open` ni por
`~/.config/mimeapps.list`. Con `firefox` instalado (no usado, solo Zen),
siempre ganaba sobre Zen (`zen-bin`, no reconocido por el módulo).

**Fix:**
```bash
echo 'export BROWSER=xdg-open' >> ~/.zshrc
sudo pacman -R firefox
```

**Browser (parte 2 — redirect file .html):** aun con `$BROWSER=xdg-open`
seteado, abrir un `file://` (el `jpserver-*-open.html` que genera Jupyter)
dispara un bug distinto en `xdg-open`: su función `open_generic()`
detecta el DE como "generic" (Niri no está en su lista de DEs conocidos)
y en esa rama **sobrescribe** `$BROWSER` con su propia lista hardcodeada,
ignorando tanto la variable de entorno como `mimeapps.list`. Confirmado
con `bash -x /usr/bin/xdg-open <url>`.

**Fix:** evitar que Jupyter genere ese archivo intermedio, forzándolo a
abrir la URL `http://` directamente (que sí respeta `$BROWSER`):
```bash
jupyter notebook --generate-config
echo "c.ServerApp.use_redirect_file = False" >> ~/.jupyter/jupyter_notebook_config.py
```

## 5. Puertos de Jupyter acumulados

`jupyter notebook` no fallaba si el puerto 8888 estaba ocupado por una
instancia previa sin cerrar (terminal cerrada de golpe, proceso huérfano);
simplemente probaba 8889, 8890, etc. Confirmar antes de reportar "no
carga" que no haya instancias colgadas:
```bash
pkill -f jupyter-notebook
ss -tlnp | grep 888
```

---

## 6. Pantalla negra en boot en frío (race con plymouth)

**Síntoma:** arrancando de cero (no logout/relogin), el greeter no daba
imagen — había que entrar a una TTY y `systemctl restart greetd`
manualmente para que cargara.

**Root cause:** `greetd.service` declara `After=plymouth-quit-wait.service`,
pero ese unit solo confirma que el boot general llegó al punto de poder
cerrar plymouth — no espera a que `plymouthd` termine de soltar el DRM
master del framebuffer. En el boot fallido (`journalctl -b -2`), hubo solo
~56ms entre la señal de quit a plymouthd y el arranque de greetd, que ya
intentaba tomar `/dev/dri/card2` — coincide con el error
`Device or resource busy` visto en `greeter-debug.log`.

**Fix:** drop-in en `greeter-setup/systemd-overrides/greetd-plymouth-race.conf`,
instalar con:
```bash
sudo mkdir -p /etc/systemd/system/greetd.service.d
sudo cp greeter-setup/systemd-overrides/greetd-plymouth-race.conf \
  /etc/systemd/system/greetd.service.d/plymouth-race.conf
sudo systemctl daemon-reload
```

Agrega `After=plymouth-quit.service` explícito + `ExecStartPre=sleep 1`
como margen de seguridad. Validado con reboot en frío tras habilitar
greetd como default (`systemctl enable greetd`, `disable sddm`).
