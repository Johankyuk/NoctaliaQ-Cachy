# Handoff — Fix launcher de Noctalia (NoctaliaQ-Cachy)

**Fecha:** 2026-08-18
**Repo:** `NoctaliaQ-Cachy`
**Commit:** `60ea379`
**Sistema:** CachyOS, Niri + Noctalia v5.0.0 (`5.0.0_beta.8-1-dirty`)

---

## Síntoma inicial

El launcher de Noctalia (`Mod+Space` / `Mod+Ctrl+Return`) mostraba las apps correctamente en la búsqueda, pero **ningún click o Enter lanzaba nada** — ni apps GUI ni apps de terminal (vim, micro, btop).

---

## Root cause

`~/.config/noctalia/config.toml` (trackeado en el repo) tenía:

```toml
launch_apps_custom_command = "noctaliaq-gpu-launch $CMD"
```

Este setting envuelve **globalmente** todo lo que el launcher/dock/taskbar lanza (no es selectivo por app). El binario `noctaliaq-gpu-launch` referenciado **nunca existió** en `~/.local/bin` ni en el PATH — quedó como remanente de una idea de offload de GPU (PRIME) que no se completó. No confundir con `noctaliaq-gpu-prime`, que sí existe y funciona correctamente vía los hooks `battery_plugged`/`battery_unplugged`.

Resultado: cada click en el launcher intentaba correr `noctaliaq-gpu-launch firefox` (por ejemplo), fallaba con `command not found`, y no pasaba nada visible para el usuario.

**No tiene relación con el trabajo de greetd/SDDM.**

---

## Por qué costó diagnosticar

Noctalia v5 mergea dos capas de config:

| Archivo | Rol |
|---|---|
| `~/.config/noctalia/config.toml` | Config base, trackeada en el repo |
| `~/.local/state/noctalia/settings.toml` | Estado runtime, editado por la GUI de Settings |

El daemon vivo (`noctalia`, PID persistente) mantiene el valor en memoria y **reescribe `settings.toml` con lo que tiene cargado**. Editar `settings.toml` con `sed` mientras el daemon seguía corriendo no servía — el archivo se regeneraba con el valor viejo. Hubo que:

1. Matar el proceso real con `kill -9` (no `pkill -f noctalia-shell`, ese patrón no matchea nada).
2. Confirmar que el binario se llama `noctalia`, no `qs`/`quickshell` (ese setup no tiene `qs` instalado; es el binario standalone `/usr/bin/noctalia -d`).
3. Editar **ambos** archivos (`config.toml` del repo + `settings.toml` del state).
4. Relanzar el daemon limpio y verificar contra la config viva con `noctalia config export`.

---

## Fix aplicado

- `launch_apps_custom_command = ""` en `config/noctalia/config.toml` (repo) y `~/.local/state/noctalia/settings.toml` (state).
- Commit `60ea379`:
fix(noctalia): clear launch_apps_custom_command pointing to nonexistent binary

Root cause: launch_apps_custom_command wrapped ALL app launches globally
with 'noctaliaq-gpu-launch $CMD'. That binary never existed in PATH or
.local/bin, silently breaking the entire launcher for both GUI and
terminal apps (apps listed correctly, nothing launched on click/enter).

Unrelated to greetd/sddm setup. GPU offload via PRIME should be
per-app in .desktop Exec= lines, not via this global setting.

---

## Descartado en el camino (falsa pista)

Se sospechó inicialmente que btop se cerraba solo al lanzarse desde el launcher por falta de `$TERMINAL`. Se agregó temporalmente un bloque `environment { TERMINAL "foot" }` en `config/niri/cfg/autostart.kdl`. **Se confirmó que btop ya funcionaba correctamente una vez resuelto el bug del launcher** — el cierre inmediato era efecto colateral del mismo bug (btop nunca llegaba a ejecutarse, solo el wrapper fallaba). El bloque `environment` se revirtió con `sed` y el archivo quedó sin cambios netos.

---

## Lección para el repo

Si se retoma la idea de offload de GPU (PRIME) al lanzar apps específicas, el wrapper va en el `Exec=` de cada `.desktop` individual:
Exec=prime-run steam

**No** en `launch_apps_custom_command`, que aplica de forma global e indiscriminada a todo lo que lanza el launcher/dock/taskbar.

---

## Actualización 2026-08-27

**La lección de arriba quedó revertida a propósito.** El commit `77f4af4`
(*feat(gpu): activar offload PRIME global via launch_apps_custom_command*)
reactivó el wrapper global, esta vez con `noctaliaq-gpu-launch` ya existiendo
en `~/.local/bin`. O sea: el setting sí se usa hoy, y ver
`launch_apps_custom_command` con valor **no** es una regresión de este bug.

El bug original era que el binario no existía, no el mecanismo en sí.

Gotcha de rastreo: `git log -S` cuenta *ocurrencias* de la cadena, así que no
detecta un cambio de valor de una key TOML — la key aparece una vez antes y
después. Usar `-G` (regex sobre el diff).
