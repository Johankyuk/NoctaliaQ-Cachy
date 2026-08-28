# Verificación de pendientes, completions de zsh y cobertura de rotate-backups

**Fecha:** 2026-08-27/28
**Componente:** README, install.sh, config/zsh/zshrc, bin/rotate-backups.sh, handoffs
**Commits:** `c8cf18b`, `f9cd550`, `66ca9ae`, `fac72ae`, `45e8403`
**Resultado:** relogin validado, sin pendientes locales

## Resumen

Sesión de verificación que destapó tres cosas no documentadas: el mecanismo de
placeholders de `install.sh`, que `install.sh` no instala Noctalia, y que
`rotate-backups.sh` no cubría los `.bak` del repo. Dos pendientes del handoff del 24
se cerraron (uno era falso positivo), y las completions de zsh quedaron integradas.

## 1. El `diff` crudo de `config.toml` no sirve para detectar drift

`install.sh` (líneas 41-44) sustituye placeholders con `sed` al desplegar. Un `diff`
entre `config/noctalia/config.toml` y `~/.config/noctalia/config.toml` **siempre**
muestra ~14 líneas de diferencia que no son drift.

Comparación correcta:

```bash
sed "s|\"HOOK\"|\"$HOME/.config/noctalia/scripts/rgb-sync-hook.sh\"|g; s|\"HOME/|\"$HOME/|g" \
  config/noctalia/config.toml > /tmp/cfg-norm.toml
diff /tmp/cfg-norm.toml ~/.config/noctalia/config.toml
```

Documentado en el README, sección *Placeholders de rutas*, con la tabla de las tres
formas (`"HOME/`, `=HOME/`, `"HOOK"`) y la regla de que un archivo nuevo con rutas
necesita las tres piezas: placeholder, `sed`, y `grep` que aborte.

## 2. `launch_apps_custom_command` NO es una regresión

Ver el setting con valor parecía el bug de `60ea379` (2026-08-18) reintroducido. Falso:
`77f4af4` lo reactivó a propósito, ya con `noctaliaq-gpu-launch` existiendo. El bug
original era el binario faltante, no el mecanismo. Nota agregada al handoff del 18,
que decía explícitamente lo contrario.

### Gotcha: `git log -S` no detecta cambios de valor

`-S` cuenta **ocurrencias** de la cadena. Cambiar el valor de una key TOML deja la key
apareciendo una vez antes y después, así que `-S` no lo ve. Usar `-G` (regex sobre el
diff). Con `-S` solo salió el commit inicial y se construyó una hipótesis falsa encima.

## 3. Completions de noctalia en zsh

`noctalia completions zsh` genera 1663 líneas desde el esquema vivo, incluyendo
subcomandos de los plugins instalados. Se instalan en
`~/.local/share/zsh/site-functions/_noctalia` desde `install.sh`, con verificación de
`#compdef noctalia` en la primera línea y `rm -f` si falla — un archivo truncado rompe
la completion de toda la shell, peor que no tenerlo.

### El `fpath` hacía falta y un grep mal hecho lo ocultó

`grep -c '.local/share/zsh/site-functions'` devolvió 1, pero era **subcadena** de
`/usr/local/share/zsh/site-functions`. El directorio del usuario no estaba en `fpath`.
Verificar con `print $_comps[noctalia]`, no contando paths.

El `zshrc` delega todo a `cachyos-config.zsh`, que corre `compinit` adentro. El `fpath`
se agrega **antes** de ese `source`; si se mueve después, las completions dejan de
cargar en silencio.

### Gotcha: la completion de comandos parece completion del subcomando

Sin `_noctalia` cargado, `noctalia <Tab>` lista binarios del PATH que empiezan con
`noctalia` (incluidos `.bak.*` de `~/.local/bin`) o archivos del directorio actual. Se
parece a que funciona. Verificar con `print $_comps[noctalia]`.

Además `compinit` ya corrió al escribir el archivo: hay que `rm -f ~/.zcompdump*` antes
de relanzar la shell.

## 4. `rotate-backups.sh` no cubría el repo

`DIRS` solo tenía rutas desplegadas. Se agregaron `$REPO_DIR`, `$REPO_DIR/bin`,
`$REPO_DIR/config/noctalia` y `$REPO_DIR/config/systemd-user`, con `REPO_DIR` resuelto
desde `BASH_SOURCE`, no hardcodeado.

`config/niri/cfg` del repo se omite a propósito: es el destino del symlink
`~/.config/niri/cfg`, ya cubierto, y `find -L` lo sigue. De hecho el rotate ya borraba
backups del repo por esa vía sin que se hubiera notado.

Los `.bak.*` del repo están cubiertos por `.gitignore` (`*.bak.*`, duplicado en las
líneas 1 y 3). No hay riesgo de commit accidental.

### Falsas alarmas descartadas

- **`ls -1t` ordena por mtime**, así que la mezcla de formatos de timestamp
  (`1787420459` epoch vs `20260824-075415`) no afecta qué backup se conserva.
- **El brace expansion de la línea 18** (`{bak,pre-*,corrupto,antes-*}`) funciona: bajo
  bash los globs sin match pasan literales y `ls` los ignora con `2>/dev/null`. El
  `no matches found` al probarlo era zsh interactivo (`nomatch`), no el script.

## 5. `install.sh` no instala Noctalia

`grep 'pacman.*noctalia' install.sh` → `rc=1`. Noctalia se asume preinstalado. El
bloque de completions lo maneja con un `command -v` y un WARN, pero conviene decidir si
es intencional o un hueco real de la instalación desde cero.

## Pendientes cerrados

- **`hooks.colors_changed` con `/home/kyu`**: falso positivo. En el repo es el
  placeholder `"HOOK"`; `install.sh` lo sustituye. Tachado en el handoff del 24.
- **`noctalia completions` en `install.sh`**: integrado y validado en relogin.

## Validación del relogin

- `miri.service` activo, `ExecStartPost` status 0, `SetFocusedWorkspaceMode to Master`
  en el journal. `Mod+M` verificado (`CycleFocusedWorkspaceMode`).
- `noctalia config validate` → limpio, sin `WRN`/`ERR` en el journal.
- `print $_comps[noctalia]` → `_noctalia` en shell de login.
- `Mod+B` (Zen) y lanzar app desde el launcher: verificados a mano.

### Gotcha: `systemctl status` expande `%h`

El `ExecStartPost` se muestra como `/home/kyu/.local/bin/miri` en `systemctl status`
aunque la unidad use `%h`. No es evidencia de ruta hardcodeada — comparar contra el
archivo, no contra la salida de systemd.

## Nota de proceso

Los heredocs de texto multilínea pegados a la terminal **pierden las líneas en blanco**,
lo que rompe el render de markdown (tablas y encabezados necesitan separación). El
patrón que funciona es lista de líneas en Python con `"\n".join()`.

Además, `cat -A | grep -c '^\$'` cuenta líneas en blanco correctamente — se leyó al
revés una vez y llevó a revertir un archivo que estaba bien.

## Pendientes

- [ ] Confirmar que `Mod+B` abre Zen tras `install.sh` desde cero (máquina limpia).
- [ ] Confirmar `miri.service` en login limpio en máquina nueva.
- [ ] Decidir si `install.sh` debe instalar Noctalia o asumirla preinstalada.
- [ ] Heredado: ciclo suspend/resume como vía del race de DRM.
