# Mod+M toggle de miri, sync de Noctalia beta.9 y tres bugs en rotate-backups

**Fecha:** 2026-08-24
**Componente:** config/niri/cfg/keybinds.kdl, config/noctalia/config.toml, bin/rotate-backups.sh
**Commits:** `499637d`, `cd2e8ad`, `2d08755`, `5a96205`, `4468d9b`
**Resultado:** repo, desplegado y state alineados; Noctalia arranca sin warnings

## 1. Mod+M cicla el modo de workspace de miri

`miri` trae `cycle-focused-workspace-mode`. Con solo dos modos (`master` y
`scroll`, siendo `scroll` el comportamiento nativo de niri) funciona como
toggle. Reemplazó `maximize-window-to-edges`, que no se usaba.

```kdl
Mod+M { spawn-sh "$HOME/.local/bin/miri action cycle-focused-workspace-mode"; }
```

**`spawn-sh`, no `spawn`.** greetd lanza niri vía PAM sin pasar por el systemd
user manager, así que `~/.local/bin` nunca está en el PATH heredado. Un
`spawn "miri" "action" ...` falla en silencio desde el bind aunque funcione en
la terminal. `spawn-sh` corre vía `sh -c` y expande `$HOME`, así que queda
migrable sin hardcodear `/home/kyu`.

Verificación por journal (`miri get focused-workspace-mode` no imprime nada,
nunca):

```bash
journalctl --user -u miri -b --no-pager | grep -i 'WorkspaceMode' | tail
```

El `ExecStartPost` del service fija `master` al arrancar, así que el toggle es
por sesión: cada login vuelve a master.

## 2. config.toml sincronizado con el estado vivo de beta.9

Bajaron al repo los 10 plugins habilitados, los widgets de barra (`recorder`,
`keybinds`, `gamermode`, `bar_2`, `bar_3`), shortcuts de control_center y
`plugin_settings`. Cierra el pendiente del 2026-08-22.

**El `config export` de beta.9 salió mucho más limpio que el de beta.8:** hooks
como arrays, `[[plugins.source]]` conserva `enabled = true`, y solo 5 líneas de
churn de floats. Ya es viable versionarlo quitando la credencial, sin
cherry-pick manual línea por línea.

La contraseña del hotspot se excluyó (repo público). `git log -S` confirmó que
nunca estuvo en el historial, así que rotarla queda opcional.

### Gotcha: no revertir floats mapeando por nombre de key

Un intento de revertir el churn mapeando `key -> valor` sin considerar la
sección colapsó valores homónimos: `background_opacity` existe en 5 secciones
distintas y todas quedaron con el mismo valor, además de perder la
indentación. **El churn de 5 líneas no vale el riesgo — dejarlo.**

Verificación barata post-edición de TOML, detecta ese daño exacto:

```bash
python3 -c "import tomllib,pathlib; tomllib.loads(pathlib.Path('config/noctalia/config.toml').read_text()); print('OK')"
```

### Archivo obsoleto neutralizado

`~/Documents/noctalia-full-config.toml` (16 de agosto) traía
`launch_apps_custom_command = "noctaliaq-gpu-launch $CMD"` — el bug del
launcher cerrado en `60ea379` — más el widget fantasma. Renombrado a
`.stale-20260816`. El bueno es el de `~/Downloads` (24 de agosto).

## 3. ⚠️ `noctalia config validate` NO detecta referencias colgantes

Tras el sync, el arranque tiró:
[WRN] [shell] widget factory: unknown widget "widget"

La sección `[widget.widget]` con `yuuto/arch-updater` se quitó el 2026-08-22,
pero la barra seguía listando `"widget"` en su array `start`. `validate` da
limpio porque la key es sintácticamente válida; **solo el runtime avisa.**

Existía en las tres capas: `settings.toml` (state), `config.toml` desplegado y
`config.toml` del repo.

**Lección:** verificar un upgrade requiere `validate` **más** un arranque con
salida capturada:

```bash
noctalia -d > /tmp/noctalia-start.log 2>&1 & sleep 3
grep -i -E 'WRN|ERR' /tmp/noctalia-start.log
```

Ese warning llevaba dos días saliendo en cada arranque sin que nada lo
reportara.

## 4. Tres bugs en bin/rotate-backups.sh

### `find` sin `-L` no atraviesa symlinks de directorio

`~/.config/niri/cfg` es symlink al repo, así que sus backups nunca se rotaban:
17 acumulados. **Tercer lugar donde muerde el mismo gotcha** (ya visto con
`Path.rglob`, resuelto con `os.walk(followlinks=True)`).

La señal de que falta la bandera: un conteo en cero donde `ls` sí ve archivos.

### El `sed` de agrupación esperaba epoch

Patrón `\.[0-9]+$` — dígitos puros. Pero `backup_and_copy()` y los scripts de
sesión generan `.bak.YYYYMMDD-HHMMSS`, con guion. Solo rotaba backups de
formato viejo. Corregido a `\.[0-9]+(-[0-9]+)?$`.

### `KEEP` sin validar podía borrar TODO

`KEEP=${1:-3}` aceptaba cualquier string. Pasarle una ruta por error hacía que
bash evaluara `${files[@]:$KEEP}` con un string no numérico como 0, y el slice
devolvía **todos** los archivos: el `rm -f` habría borrado todos los backups,
no los sobrantes. La guarda `(( ${#files[@]} > KEEP ))` también evaluaba a 0.

No llegó a disparar porque el glob interno no matcheó, pero el bug estaba
armado. Agregada guarda numérica con `exit 2`.

`DIRS` también ganó `.local/state/noctalia` y `.config/niri/cfg`.

## 5. cursor.kdl

Versionado `Skyrim-by-ru5tyshark-cursors`. Requiere descarga manual de
gnome-look, no está en pacman ni en `install.sh`; en una máquina sin el tema,
niri cae al cursor por defecto **sin error visible**. No se documenta aparte
aquí: el tema y su gestión viven en el repo `cursor-manager`.

## Pendientes

- [ ] `hooks.colors_changed` usa `/home/kyu` hardcodeado mientras los hooks de
      batería usan `~`. Mismo patrón de portabilidad que el `ExecStartPost` de
      `miri.service`.
- [ ] Evaluar `noctalia completions` como bloque de `install.sh`.
- [ ] Confirmar que `Mod+B` abre Zen tras `install.sh` desde cero.
- [ ] Confirmar `miri.service` en login limpio en máquina nueva.
- [ ] Heredado: ciclo suspend/resume como vía del race de DRM.
