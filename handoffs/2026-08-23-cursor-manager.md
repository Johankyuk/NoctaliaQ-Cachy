# cursor-manager: repo nuevo + cursor con una sola fuente de verdad

**Fecha:** 2026-08-23
**Repos:** cursor-manager (nuevo), NoctaliaQ-Cachy
**Commits:** cursor-manager `fe75a6f` · NoctaliaQ-Cachy `47e2d16`, `8adee1c`

## Qué se hizo

Wizard `cursor-scale` para cambiar tamaño y tema del cursor desde el launcher,
publicado como repo aparte en `Johankyuk/cursor-manager` con `install.sh`,
`.desktop` y `environment.d`. Menú de una letra: `[n]` tamaño, `[t]` tema,
`[i]` instalar desde comprimido.

Catálogo que escanea `$XCURSOR_PATH`, `~/.local/share/icons`, `~/.icons`,
`/usr/local/share/icons` y `/usr/share/icons` (primero gana, igual que Xcursor),
mostrando origen, tamaños nominales reales parseados de la cabecera Xcursor, y
symlinks rotos.

Instalador que acepta tar/zip/7z y corrige tres defectos habituales de temas
empaquetados a mano: symlinks con ruta absoluta al home del empaquetador,
`cursor.theme` con `Inherits` que no resuelve, e `index.theme` sin fallback.

En NoctaliaQ-Cachy el cursor quedó con **una sola fuente**: `cfg/cursor.kdl`
versionado con su `include` en `config.kdl`. Se eliminaron las otras tres:
el bloque `cursor` duplicado en `misc.kdl`, las `XCURSOR_THEME`/`XCURSOR_SIZE`
del bloque `environment` (niri las deriva solo), y el `gsettings set ... 32`
con Bibata forzado en `install.sh`. Bibata vendorizado (28 MB, 147 archivos)
salió del repo; el tema ahora es `capitaine-cursors` por paquete.

## Gotchas

- **`Path.rglob` no desciende por symlinks de directorio.** Con `cfg/`
  apuntando al repo, un `rglob` ve solo los directorios reales que haya al
  lado —los backups— y opera sobre ellos creyendo que son el config vivo.
  Usar `os.walk(followlinks=True)` con corte de ciclos.
- **Ordenar rutas no distingue activo de backup:** `cfg.bak.N/` gana contra
  `cfg/` porque `.` (46) precede a `/` (47) en ASCII. Filtrar `.bak`, `.old`,
  `.orig`, `.save`, `.disabled` explícitamente.
- **greetd lanza niri por PAM, no lo activa el manager de usuario.** El manager
  sí lee `environment.d`, pero niri arranca por un camino paralelo y no hereda
  ese PATH — verificable con `tr '\0' '\n' < /proc/$(pgrep -x niri)/environ`.
  Regla: en `.desktop` propios, ruta vía `$HOME`, nunca confiar en el PATH.
- **"Versionado ≠ desplegado" otra vez.** `miri.service` tenía `%h` en el repo
  y `/home/kyu` hardcodeado en `~/.config`. Mismo patrón que el
  `privilege_command` del 2026-08-19. Cerrar sesión con `git status` limpio
  **y** `diff` explícito contra los archivos desplegados.
- El navegador sobrescribe descargas repetidas sin numerar: verificar el
  contenido (`grep -c` de algo distintivo) antes de instalar, no el nombre.

## Pendientes

Ninguno abierto.
