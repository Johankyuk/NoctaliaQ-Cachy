# PRIME offload global + TERMINAL=foot (Alienware)

**Fecha:** 2026-08-27
**Máquina:** Alienware 17 R4, CachyOS, usuario `alquinterus` (Intel HD 630 + GTX 1070)
**Componente:** config/noctalia/config.toml, bin/noctaliaq-gpu-launch, config/environment.d/10-path.conf
**Commits:** `77f4af4`, `b960cff`
**Resultado:** offload global funcionando, alacritty removida, repo y desplegado alineados

## Resumen

La regresión del handoff previo ("las apps dejaron de abrir tras poner
`launch_apps_custom_command`") tenía una sola causa: **faltaba el placeholder
`$CMD`**. De paso se descubrió que los hooks de batería nunca habían corrido
(TOML no expande `~`), que el repo ya tenía la convención de placeholders para
resolverlo de forma universal, y que alacritty ganaba sobre foot por orden en
una lista compilada dentro del binario de Noctalia.

## 1. `launch_apps_custom_command` necesita `$CMD`

De la doc de Noctalia v5: la key envuelve toda app lanzada desde launcher, dock
y taskbar, y **el literal `$CMD` se reemplaza por el comando propio de la app**
(ej. `gamemoderun $CMD`). El valor que se había puesto era solo la ruta del
wrapper, así que Noctalia ejecutaba `noctaliaq-gpu-launch` sin argumentos → el
wrapper hacía `exec env VARS` sin comando → nada abría.

```toml
launch_apps_custom_command = "HOME/.local/bin/noctaliaq-gpu-launch $CMD"
```

También es **mutuamente excluyente con `launch_apps_as_systemd_services`**: si
el lanzador systemd está en efecto, el custom command se ignora en silencio.
Acá está en `false`, así que no aplica.

**Validación end-to-end:** SuperTuxKart lanzado *desde el launcher* (no desde
terminal) reporta `OpenGL renderer: NVIDIA GeForce GTX 1070`. Ojo: `stdout.log`
se sobrescribe en cada arranque, así que hay que verificar la marca de tiempo
con `stat -c '%y'` contra `date` para no leer la corrida anterior.

## 2. Los hooks de batería nunca corrieron: TOML no expande `~`

```toml
battery_discharging = [ "~/.local/bin/noctaliaq-gpu-prime off" ]   # NUNCA corrió
```

Ya estaba documentado como patrón heredado ("ante cualquier cosa rota en
Noctalia, revisar rutas con `~` o con `/home/kyu`"), pero seguía vivo en el
`config.toml` del repo.

### El repo ya tenía la solución: placeholders

`install.sh` (líneas 38-44) sustituye al desplegar, con guard de verificación:

```bash
sed -i "s|\"HOOK\"|\"$HOME/.config/noctalia/scripts/rgb-sync-hook.sh\"|g; \
        s|/home/kyu/|$HOME/|g; s|\"HOME/|\"$HOME/|g" "$_cfg"
if grep -q 'HOOK\|/home/kyu\|"HOME/' "$_cfg"; then ...aborta... fi
```

**Fix:** `~` → `HOME/` en las tres líneas. El patrón `s|\"HOME/|` exige comilla
antes, y tanto `[ "HOME/..." ]` como `= "HOME/..."` la tienen.

**Intento descartado:** primero se movieron los scripts a `/usr/local/bin` para
tener ruta fija portable. Innecesario — el mecanismo de placeholders ya resuelve
la portabilidad y `install.sh` ya instala los tres scripts en `~/.local/bin`
(líneas 146-149). Revertido.

**Verificación en seco antes de commitear** (el sed sin `-i`, sobre el archivo
del repo):

```bash
sed "s|\"HOOK\"|\"$HOME/.config/noctalia/scripts/rgb-sync-hook.sh\"|g; \
     s|/home/kyu/|$HOME/|g; s|\"HOME/|\"$HOME/|g" config/noctalia/config.toml \
  | grep -n -E 'noctaliaq-gpu|HOOK|/home/kyu|"HOME/'
```

No debe quedar ningún placeholder sin expandir.

## 3. `gpu-launch`: ICD hardcodeado

La rama `off` apuntaba a `/usr/share/vulkan/icd.d/radeon_icd.json`, inexistente
en esta máquina. Funcionaba por accidente (el loader no encontraba ICD válido y
caía a Intel). Cambiarlo a `intel_icd.json` habría sido el mismo bug al revés,
así que ahora se arma en runtime:

```bash
ICDS=""
for f in /usr/share/vulkan/icd.d/*.json; do
    case "$f" in *nvidia*|*hasvk*) continue;; esac
    ICDS="${ICDS}${ICDS:+:}$f"
done
[[ -n "$ICDS" ]] && exec env VK_ICD_FILENAMES="$ICDS" "$@" || exec "$@"
```

Se excluye `hasvk` (driver Vulkan legacy de Intel, para gen7-8) además de nvidia.

## 4. Alacritty: la lista está compilada en el binario

Ninguna key de terminal en `config.toml` ni en `settings.toml`, `$TERMINAL`
vacío, `xdg-terminal-exec` no instalado. `nvtop.desktop` solo declara
`Terminal=true` y delega. El orden vive dentro del binario:

```bash
strings /usr/bin/noctalia | grep -x -E 'alacritty|foot|kitty|wezterm|ghostty|xterm|konsole'
# ghostty kitty alacritty wezterm foot konsole xterm
```

alacritty va **antes** que foot, por eso ganaba. Fijar `TERMINAL=foot` en
`config/environment.d/10-path.conf` evita depender de ese orden en cualquier
máquina, esté o no alacritty instalada.

`pactree -r alacritty` salió vacío — solo era **optdepend** de niri, se removió
sin arrastrar nada. Snapper dejó snapshots 43/44.

**`environment.d` lo lee el systemd user manager: requiere logout/login.** Para
probar sin cerrar sesión: `systemctl --user set-environment TERMINAL=foot` +
relanzar noctalia.

## 5. SSH: el puerto 22 está bloqueado en la red UV

DNS `148.226.12.x` (Universidad Veracruzana). El 22 da timeout; el 443 funciona:

```
Host github.com
  HostName ssh.github.com
  Port 443
  User git
```

Va en `~/.ssh/config` (chmod 600). Esto va a reaparecer en cualquier máquina en
esa red — **no está versionado en el repo**, se resuelve a mano por máquina.

También: `git config user.name/user.email` local (sin `--global`) porque esta
máquina puede no ser permanente.

## ⚠️ Credencial expuesta (sin resolver)

`config/noctalia/settings.toml:200` tiene `password = "linuxmogs"` (SSID `Kyu`).
Entró en el commit **`a637b00`** y el repo es **público**. Ya está en el
historial de GitHub de forma permanente; borrar la línea ahora no lo saca.

**La única acción que cierra esto es rotar la contraseña del hotspot.**

Ya venía flaggeado desde el handoff del 2026-08-22 y sigue abierto.

## Gotchas de la sesión

- **El pager de git mata el resto del bloque pegado.** Un `git diff` a mitad de
  un copy-paste abre `less`; al salir, las líneas restantes se interpretan como
  comandos de less y luego como redirecciones de shell. Dejó tres archivos
  basura en el repo (`_custom_command`, `h`, `cartando nvidia y hasvk.`) que
  eran el output de `less --help`. Usar `export GIT_PAGER=cat` antes de
  cualquier bloque con diffs. Mismo patrón ya documentado ("un comando que
  aborta mata las líneas siguientes"), variante nueva.
- **Mensajes de commit multilínea con líneas en blanco** en un bloque pegado son
  frágiles. `git commit -F -` con heredoc funciona; `-m` con saltos, no.
- **`pacman db.lck` huérfano.** Verificar con `fuser -v /var/lib/pacman/db.lck`
  y `ps aux | grep pacman` antes de borrarlo. Acá no había proceso.
- **Autocorrect de zsh** intercepta `config/...` ofreciendo `.config/...`.
  Responder `n`. Ya documentado el 2026-08-22, volvió a aparecer varias veces.
- **`noctalia config validate` no ve `launch_apps_custom_command` roto** — un
  valor sin `$CMD` es TOML válido y pasa la validación. La verificación real es
  lanzar una app desde el launcher.

## Pendientes

- [ ] **Rotar el password del hotspot** (`a637b00`, repo público).
- [ ] Probar **nvtop desde el launcher** — quedó sin verificar que abra en foot.
- [ ] **Relogin limpio**: confirmar `echo $TERMINAL` y que el offload aplique
      desde cero. Todo se validó con el daemon relanzado a mano, no en un login
      real.
- [ ] `/home/kyu/Pictures/Screenshots` en `config.toml` del repo → `HOME/` por
      consistencia (el `sed` de `install.sh` ya lo cubre, pero es inconsistente).
- [ ] `gpu-prime` línea 42 encadena `~/.local/bin/noctaliaq-gpu-flatpak-sync`.
      Dentro de bash `~` sí expande, así que funciona, pero conviene absolutizar.
- [ ] `install.sh` no despliega `config/noctalia/settings.toml` aunque esté
      trackeado. Decidir si se despliega o se deja de trackear.
- [ ] Heredados: `noctalia completions` en `install.sh`, ciclo suspend/resume
      como vía del race de DRM.
