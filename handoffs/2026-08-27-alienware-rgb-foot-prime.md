# Alienware 17 R4: RGB versionado, foot transparente, PRIME verificado

**Fecha:** 2026-08-27
**Maquina:** Alienware 17 R4 ("PlvsUltra"), usuario `alquinterus`
**Commits:** `45aa6bd`, `abef745`, `a36c156`, `c4daaa5` (sin push)

## Contexto

Instalacion de NoctaliaQ-Cachy en una Alienware recien formateada. Tres
sintomas reportados: foot sin transparencia, dudas sobre PRIME offload, y
sospecha de que la pantalla estaba limitada a 60Hz.

## 1. Pantalla: no hay nada que arreglar

El EDID del panel (AU Optronics 0x109D) solo expone `1920x1080@60.002` y
`@48.069`. `Variable refresh rate: not supported`. Es un panel de 60Hz.
`display.kdl` esta entero comentado, asi que niri usa el modo preferido.

Si hubiera un modo alto oculto apareceria en `Available modes` aunque niri
no lo tomara — que no aparezca cierra el tema a nivel EDID.

## 2. foot: el ini desplegado estaba truncado

`~/.config/foot/foot.ini` eran 46 bytes (solo `[main]` + `include`) contra
las 12 lineas del repo. Nunca se desplegó completo.

- `alpha=0.85` + `alpha-mode=all` bajo **`[colors-dark]`**.
- **Gotcha:** foot **deprecó `[colors]`** a favor de `[colors-dark]`. Usar
  `[colors]` tira warnings. Al reves de lo que uno esperaria.
- `alpha` va en `foot.ini`, **no** en el tema: Noctalia regenera
  `themes/noctalia` en cada cambio de color y se lo llevaria.
- `config/foot/themes/` **destrackeado** (`.gitignore`). Costo: en maquina
  nueva el `include` falla hasta el primer `templates-apply`; foot avisa y
  arranca igual.
- Recordatorio: la transparencia solo aplica a **ventanas nuevas**.

## 3. PRIME offload: funciona, verificado
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia glxinfo -> GTX 1070
glxinfo (sin vars) -> Intel HD 630

`prime-run` presente. `launch_apps_custom_command = ""` es **correcto** — es
el fix de `60ea379`. Para apps concretas: `prime-run` en el `Exec=` del
`.desktop`, nunca en el setting global.

**Confirmado: Noctalia SI expande `~` en los hooks `battery_*`.** Test del
cargador dio las dos transiciones en journal (13:12:45 off, 13:13:08 on).
Las lineas 198/200 con `~/.local/bin/noctaliaq-gpu-prime` no necesitan
ruta absoluta. Esto cierra un pendiente que venia abierto.

## 4. Bug real: `backup_and_copy` anidaba directorios

```bash
cp -r "$src" "$dst"   # con $dst existente -> copia $src DENTRO de $dst
```

**Este es el origen de `~/.config/foot/foot/`**, que el 2026-08-19 se
atribuyo a un `cp -r` manual mal hecho. No lo fue: `install.sh` lo
reproduce solo en cada segunda corrida, en cualquier maquina, para
cualquier directorio. Corregido con `cp -rT`.

Segundo arreglo en la misma funcion: `[ -e "$dst" ] && cp ...` devuelve 1
cuando el destino no existe y bajo `set -e` mata el script. No explotaba
por ser la ultima expresion antes de un `if`; cualquier linea agregada
despues lo activaba. Reemplazado por `if` explicito.

## 5. RGB de Alienware versionado

`alienfx.py` (219 lineas, protocolo USB extraido de AKBL) y `rgb-sync.py`
vivian **sueltos en `$HOME`**, sin versionar, en un disco recien
formateado. Era lo mas fragil de todo el estado.

Estructura nueva:

- `bin/alienware/{alienfx.py,rgb-sync.py}` -> `~/.local/bin/`
- `config/noctalia/scripts/rgb-sync-hook.sh` -> despachador por
  `/sys/class/dmi/id/sys_vendor`: `Alienware` -> `rgb-sync.py`; resto ->
  `kbd-color-sync` + `mangohud-color-sync`.
- `alienware-setup/99-alienfx.rules` -> udev, `MODE=0660 GROUP=wheel`
  (era `0666`). Requiere root, no automatizado en `install.sh`.
- `install.sh`: bloque condicional por vendor + `python-pyusb`.

`rgb-sync.py` buscaba `~/alienfx.py`; corregido a `~/.local/bin/alienfx.py`
al mover.

### Patron de placeholders para rutas

**Noctalia no expande `~` ni `$HOME` en el TOML.** El repo no puede llevar
rutas de usuario. Solucion: placeholders en el repo, resueltos por
`install.sh` sobre la **copia desplegada**.

| Repo | Desplegado |
|---|---|
| `"HOOK"` | ruta absoluta del hook |
| `"HOME/..."` | `$HOME/...` |
| `/home/kyu/...` | `$HOME/...` |

Con verificacion `grep -q` explicita y `exit 1` si sobrevive algun
placeholder — `sed` devuelve 0 en silencio cuando no matchea.

Cuatro rutas `/home/kyu` eliminadas del repo, incluida
`directory = "/home/kyu/Pictures/Screenshots"` (rota en vivo en esta
maquina hasta hoy).

**Hallazgo del diff final:** `started = []` en el repo contra el hook
poblado en el desplegado. En maquina nueva el RGB no sincronizaba hasta el
primer cambio de color. Solo salio porque se hizo el diff explicito
repo-vs-desplegado antes de cerrar.

## 6. Zona de macros en azul: es firmware, no es bug

Al conectar **y** al desconectar el cargador, la zona de macros parpadea en
azul y luego vuelve al color correcto.

- `rgb-sync.py --test` da el mismo color en las nueve zonas
  (`0x4000 = #EA260F`): el calculo es correcto.
- Que vuelva al color bueno prueba que el sync **si corre**.
- El controlador AlienFX reimpone su perfil interno en la transicion de
  estado de energia, antes de que el SO se entere. El sync corrige despues.

**Decision: se deja como esta.** Es cosmetico y no hay forma de ganarle al
firmware desde el espacio de usuario. Tocar el `sleep 0.3` de debounce en
`gpu-prime` reintroduciria el bug de estado erroneo de UPower documentado
en el propio script (~9s de `pending-charge` -> `discharging`).

## Pendientes

- [ ] **Push.** Cuatro commits locales. Remoto es HTTPS: GitHub pide un
      personal access token (scope `repo`) como password, no la del sitio.
- [ ] `rgb-sync.py` no loguea a journal. Agregar `logger` para tener
      evidencia si el RGB falla de nuevo.
- [ ] `noctalia completions` en `install.sh` (heredado).
- [ ] `Mod+B`/Zen y `miri.service` en login limpio (heredado).
- [ ] Ciclo suspend/resume como via del race de DRM (heredado).

## Estado final

`git status` limpio. Diff explicito repo-vs-desplegado hecho: `foot.ini`,
`rgb-sync-hook.sh`, `alienfx.py`, `rgb-sync.py` identicos; `config.toml`
difiere solo en los placeholders, verificado en seco con el `sed` de
`install.sh` (`diff` identico al desplegado).
`noctalia config validate` -> `✓ Config is valid`.
