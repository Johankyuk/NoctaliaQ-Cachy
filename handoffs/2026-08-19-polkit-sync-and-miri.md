# Sesión 2026-08-19 — Polkit sync sin prompt + Miri

## Resumen

Dos temas cerrados: el prompt de polkit en cada sync de apariencia al
greeter, y la pérdida del layout de mosaico de Miri tras cerrar sesión.
Ambos versionados y pusheados (`1bb8688`).

---

## ✅ Cerrado: prompt de polkit en wallpaper sync

### La pieza que faltaba de la sesión anterior

El pendiente #2 del handoff previo ("investigar si existe la opción
Privilege command en Noctalia Settings") queda **confirmado: sí existe**.

- Key: **`shell.greeter_sync.privilege_command`**
- Vive en **`~/.config/noctalia/config.toml`**, no en un `settings.json`
  (la sesión anterior buscaba el archivo equivocado)
- No aparecía con `grep` porque Noctalia solo escribe las keys
  modificadas; en su valor por defecto la key está ausente del archivo
- Se descubrió vía `/usr/share/noctalia/assets/translations/es.json`,
  donde el texto de ayuda da el ejemplo `ghostty -e pkexec`
- Es un **comando envolvente completo**, no un enum: Noctalia le
  concatena `noctalia-greeter-apply-appearance <ruta>`

### La solución

Fijar `privilege_command = "pkexec"` **no basta por sí solo**: la policy
`/usr/share/polkit-1/actions/org.noctalia.greeter.apply-appearance.policy`
trae `allow_active = auth_admin`, así que sigue pidiendo contraseña.

Hace falta también una regla, pero es mucho mejor que la anterior:

```javascript
polkit.addRule(function(action, subject) {
    if (action.id == "org.noctalia.greeter.apply-appearance" &&
        subject.isInGroup("wheel") && subject.local && subject.active) {
        return polkit.Result.YES;
    }
});
```

Comparación con la regla por PPID que se descartó:

| | Regla vieja (PPID) | Regla nueva |
|---|---|---|
| Action | `manage-units` (todo systemd) | solo la action de Noctalia |
| Alcance | cualquier unidad transitoria con padre `noctalia` | un binario, `exec.path` fijado en la policy |
| Costo | 2 `polkit.spawn` por llamada | cero spawns |
| Sujeto | `user == "kyu"` hardcodeado | `wheel` + `local` + `active`, portable |

La policy fija `exec.path=/usr/bin/noctalia-greeter-apply-appearance`, y
polkit verifica ese binario en el kernel de la comprobación — la regla no
puede ser secuestrada por otro ejecutable.

**Verificado en vivo: sync de apariencia sin prompt.**

### Deploy

Nuevo `greeter-setup/deploy-polkit-rules.sh` (requiere root). Cubre lo
que `install-greeter.sh` no toca porque vive en `/etc`:

- `/etc/polkit-1/rules.d/49-noctalia-greeter-sync.rules`
- `/etc/systemd/system/greetd.service.d/plymouth-race.conf`

Idempotente, con `backup_and_copy()` siguiendo el patrón del repo.
Probado contra el estado actual: `diff` idéntico en ambos archivos.

**Ojo con el nombre:** el drop-in se llama `plymouth-race.conf` en `/etc`
pero `greetd-plymouth-race.conf` en el repo. El script mapea entre los
dos. No renombrar sin ajustar el script, o quedan dos drop-ins.

Backup de la regla vieja en `/root/49-noctalia-wallpaper-sync.rules.bak.*`.

---

## ✅ Cerrado: Miri pierde el mosaico tras logout

**Miri ≠ niri.** Miri es un proyecto aparte que agrega tiling tipo
mosaico sobre niri (primera ventana fullscreen, las demás en mosaico).
Binario en `~/.local/bin/miri`, build manual, `static-pie` (ningún
update de sistema puede romperlo por libs).

**Síntoma:** tras cerrar sesión sin reiniciar, las ventanas dejaron de
acomodarse en mosaico. El servicio corría, el socket existía, los
eventos `[EVENT]: window changed` llegaban — pero no aplicaba layout.

**Causa:** el modo del workspace enfocado no se restaura al arrancar el
servicio. `default_workspace_mode = "master"` en
`~/.config/miri/config.toml` aplica solo a workspaces **nuevos**.

**Fix:** `ExecStartPost` en `~/.config/systemd/user/miri.service` que
fija el modo tras arrancar, con reintentos por si el socket tarda:

```ini
ExecStartPost=/bin/sh -c 'for i in 1 2 3 4 5; do sleep 1; /home/kyu/.local/bin/miri action set-focused-workspace-mode master && break; done'
```

### ⚠️ Gotcha importante de debugging

**`miri get focused-workspace-mode` no imprime nada a stdout.** Nunca.
Ni cuando el modo está correctamente fijado.

Esto costó dos iteraciones de "arreglar" algo que ya funcionaba: se
interpretó el output vacío como "estado perdido" y se construyó una
teoría entera encima. Verificar siempre por journal, no por `get`:

```bash
journalctl --user -u miri -b --no-pager | grep -i 'SetFocusedWorkspaceMode'
```

Si aparece `[ACTION]: SetFocusedWorkspaceMode to Master`, funcionó.

### Versionado

- `config/miri/config.toml`
- `config/systemd-user/miri.service`

Miri no aparece en ninguna config de niri; se lanza solo vía
`miri.service` con `WantedBy=niri.service`.

---

## ✅ Resuelto: pacman keyring

Los `signature is invalid` de `cachyos-znver4` eran **bases de datos
viejas en caché**, no un keyring roto. `pacman -Sy` las redescargó y el
`-Syu` terminó limpio. `pacman-key --populate cachyos` ayudó.

**Nota:** `noctalia-greeter: local (1.2.1-1) is newer than cachyos
(1.1.0-1)`. Instalado fuera de los repos — un `-Syu` no lo va a tocar, y
la documentación upstream puede no corresponder a esta versión.

---

## Pendientes abiertos

> **Actualización 2026-08-19 (cierre de sesión):** todos los pendientes
> de esta lista quedaron resueltos. Ver notas al final.

1. **`bc97a84` sin validar.** Fix del race de DRM en cold boot: añade
   `After=plymouth-quit.service` + `ExecStartPre=/usr/bin/sleep 1` vía
   drop-in. Razonamiento sólido (ventana de ~56ms medida en journal
   contra el `Device or resource busy`), drop-in desplegado y cargado en
   systemd — pero **no probado**, requiere **poweroff completo, no
   reboot**: un reboot no reinicializa el iGPU igual.
   Escape si cuelga: `Ctrl+Alt+F2` → `sudo systemctl restart greetd`.

2. **19 backups de `config.toml`** acumulados en `~/.config/noctalia/`
   por `backup_and_copy()`. Dejar los 3 más recientes y agregar rotación
   a la función.

3. Validar en el próximo cold boot: greeter sin cuelgue, teclado (XKB_DEFAULT_LAYOUT=latam),
   y sync sin prompt tras login.

---

## Notas de proceso

- **Nunca `set -e` en bloques copy-paste.** En zsh interactivo cierra la
  terminal al primer fallo. Pasó esta sesión, a media instalación de la
  regla polkit — dejó el sistema en estado intermedio (regla vieja
  borrada, nueva instalada, `sed` sin aplicar). Usar `&&` encadenado.
- **`sed` no falla cuando un rango no matchea.** Devuelve 0 en silencio.
  El `config.toml` de Noctalia tiene las secciones **indentadas**
  (`    [shell.greeter_sync]`), así que un patrón `^\[` no matchea.
  Usar python con verificación explícita para editar TOML.
- **Globs de zsh abortan la línea entera** si no matchean (`nomatch`).
  Un `ls /root/algo*` sin permiso de lectura da un falso negativo que
  parece "el archivo no existe".
- `/etc/polkit-1/rules.d/` es `750 root:polkitd` — requiere `sudo` hasta
  para listar.


---

## Cierre de sesión — todo validado

- **`bc97a84` VALIDADO.** Cold boot limpio, greeter sin pantalla negra,
  sin `Device or resource busy` en journal. El race de DRM está cerrado.
- **Backups rotados.** `bin/rotate-backups.sh` conserva los N más
  recientes por archivo base (default 3). Limpió 16 archivos.
- **`NOCTALIA_GREETER_LOG` removido** del `command=` de greetd tras
  validar. Era para debug del bug de teclado y del race, ambos cerrados;
  el log crecía sin rotación. Los eventos siguen en `journalctl -u greetd`.
- **Layout del greeter alineado a `latam`.** `localectl` reporta
  `X11 Layout=latam` y `VC Keymap=la-latin1`, pero el greeter usaba `es`
  (España). Difieren en `<`, `>`, `@` y teclas muertas.
- **foot: `alpha-mode=all`** para transparencia en apps TUI. `matching`
  no sirve porque el tema usa `1b0d30` y las apps pintan `000000`.
  Trade-off aceptado: celdas con fondo intermedio quedan como bloques
  visibles. Gotcha: **SIGUSR1 no recarga foot**, alterna a tema dark; los
  cambios solo aplican a ventanas nuevas.
- Duplicado `~/.config/foot/foot/` (de un `cp -r` mal hecho) movido a
  `.foot-duplicado.bak.*`. Borrar en unos días si nada falla.

**El proyecto queda sin pendientes abiertos.**

Posible tema futuro: el greeter se reinicia al despertar de suspensión
(`logind-resume` observa `PrepareForSleep`), así que un ciclo de
suspend/resume es otra vía por la que el race de DRM podría manifestarse.
No se ha probado.
