# Dolphin fuera: Nautilus + plantilla papirus-icons

**Fecha:** 2026-09-13
**Componente:** install.sh, config/niri/cfg/{keybinds,rules}.kdl, config/noctalia/config.toml, README, file-manager-fix/
**Commit:** `9732913`

## Contexto

La plantilla community `papirus-icons` de Noctalia recolorea los iconos de
GNOME Files. Nautilus ya venía instalado como dep indirecta de niri (vía
`xdg-desktop-portal-gnome`), así que mantener Dolphin + el módulo que lo
forzaba como default dejó de tener sentido.

## Cambios

- `install.sh`: bloque de Dolphin (paquete + `kwriteconfig6` del color
  scheme) reemplazado por `nautilus` + `papirus-icon-theme`.
- `keybinds.kdl`: `Mod+E` → `spawn "nautilus"`.
- `rules.kdl`: regla de opacity de `^org\.kde\.dolphin$` →
  `^org\.gnome\.Nautilus$`. Confirmado en vivo con `niri msg windows`:
  el App ID real es `org.gnome.Nautilus`.
- `file-manager-fix/` eliminado del repo (script + README).
- README actualizado.

## Hallazgo: `community_ids` desincronizado

El repo tenía 8 templates y el state vivo 14. Faltaban `papirus-icons`,
`ytm-player`, `libreoffice`, `fcitx5`, `snappy-switcher`, `whitesur-icons`.
En una máquina limpia el recoloreo nunca se habría aplicado.

**Mismo patrón que `privilege_command` el 2026-08-22:** las plantillas se
eligen desde la GUI, que escribe en `settings.toml` (state); el
`config.toml` base del repo no se entera.

## Revertido a mano en la TUF

El módulo borrado ya había dejado estado aplicado en el sistema, que la
eliminación del repo no deshace:

- `.desktop` de Nautilus con `NoDisplay=true` en
  `~/.local/share/applications/` — borrados.
- `xdg-mime default` de `inode/directory` apuntando a Dolphin — reapuntado
  a `org.gnome.Nautilus.desktop`.

**Lección:** borrar un módulo del repo no revierte lo que ese módulo hizo.
Los módulos manuales necesitan documentar su propio undo.

## Desinstalación de Dolphin

`pacman -Rns dolphin` se llevó 58 paquetes (~250 MiB) de la cadena KF6/Qt6.
Uno era **`ripgrep-all`** (binario `rga`), que no tiene nada que ver con
Dolphin más allá de ser dep de `kio-extras`. Reinstalado suelto.

**Gotcha:** `pacman -Rns --print` no corre — `-n` (nosave) y `--print` son
incompatibles. Usar `pacman -Rs --print` para revisar la lista; los paquetes
son los mismos.

## Pendiente

- Aplicar en la Alienware: basta `git pull` + `./install.sh`; el revert del
  `xdg-mime` y los `.desktop` ocultos ya va dentro del script. Revisar el
  `diff` del `config.toml` desplegado antes, por drift local, y la lista de
  `pacman -Rs --print dolphin` allá antes de desinstalar.

## Hallazgo colateral: hook de RGB apuntando a un script ausente

El `diff` de cierre (repo vs. desplegado) salió limpio — solo expansión de
`HOME/` y `HOOK`. Pero un `ls` de los binarios referenciados reveló que
`~/.config/noctalia/scripts/rgb-sync-hook.sh` **no existía**, pese a que
cuatro hooks lo invocan (`colors_changed`, `started`, `theme_mode_changed`,
`wallpaper_changed`).

El script sí está versionado y `install.sh` sí lo despliega (líneas 28-29),
así que la copia se borró a mano en algún punto posterior al último
`install.sh`. Restaurado con `cp` + `chmod +x`.

**Lección:** un `diff` limpio de configs no prueba nada sobre los archivos
que esas configs *referencian*. Mismo modo de falla silenciosa que
`launch_apps_custom_command` en `60ea379`: la ruta parsea, el hook dispara,
el binario no está, nadie se entera.

Verificación end-to-end: `noctalia msg wallpaper-random` y comprobar el
mtime de `~/.cache/noctalia/palette-raw.conf`. Los hooks corren como hijos
del daemon y **no escriben a journald**, así que `journalctl` no sirve aquí.

## Pendiente derivado

- [ ] `install.sh` podría verificar la existencia de cada binario/script
      referenciado en los hooks del `config.toml` tras desplegarlo, con
      `exit 1` si falta alguno.
