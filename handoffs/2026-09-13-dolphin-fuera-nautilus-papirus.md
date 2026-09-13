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

- Aplicar en la Alienware (`git pull` + `install.sh`): allá también hay que
  revertir a mano el `xdg-mime` y los `.desktop` ocultos si se corrió el
  módulo.
