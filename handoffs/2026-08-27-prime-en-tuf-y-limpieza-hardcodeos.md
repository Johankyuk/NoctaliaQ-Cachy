# PRIME offload en la TUF + limpieza de rutas hardcodeadas

**Fecha:** 2026-08-27
**Máquina:** TUF (`KyuCachy`, Ryzen + AMD Radeon 740M iGPU + NVIDIA RTX 4050 dGPU)
**Componente:** config/noctalia/config.toml, config/noctalia/kbd-color-sync.toml,
config/MangoHud/MangoHud.conf, install.sh, .gitignore
**Commits:** `48cf2f4`, `be12dd5`, `9f336d2`

## Contexto

El offload PRIME global se desarrolló y validó en la Alienware 17 R4
(Intel HD 630 + GTX 1070). Esta sesión lo trajo a la TUF. Al hacerlo
aparecieron dos cosas que en la Alienware no se habían visto: un evento
de batería que no dispara, y varias rutas hardcodeadas en archivos que
`install.sh` copiaba crudos.

## 1. Despliegue del offload en la TUF

El `install.sh` ya resolvía todo (scripts a `~/.local/bin`, expansión de
`HOME/` sobre `config.toml`), así que el despliegue fue mecánico. Dos
puntos que sí requirieron intervención:

**`launch_apps_custom_command` vive en las dos capas.** Estaba como `""`
explícito en `~/.local/state/noctalia/settings.toml`, que es la capa que
el daemon carga. Desplegar `config.toml` solo no alcanzaba — hubo que
editar el state con el daemon muerto. Mismo patrón que el bug del
launcher del 2026-08-18.

**Los hooks `battery_*` NO hacen falta en el state.** Contraintuitivo
después de lo anterior, pero el daemon mergea los hooks de `config.toml`:
`settings.toml` define 2 hooks y el arranque reporta
`hooks kinds with commands=6`. La diferencia es que `battery_*` no existe
como key en el state (Noctalia solo escribe lo modificado), mientras que
`launch_apps_custom_command` sí existía con valor vacío y por eso pisaba
la base. **Ausente = se hereda; presente = pisa.**

`ACAD` existe en la TUF con `type=Mains`, así que el `gpu-prime` escrito
para la Alienware funciona tal cual.

## 2. ⚠️ `battery_plugged` no dispara al conectar

**Síntoma:** desconectar el cargador disparaba `battery_discharging`
correctamente. Conectar no disparaba nada: `ACAD/online` daba `1`, el
estado seguía en `off`, y el journal de `noctaliaq-gpu-prime` vacío.

**Causa:** al conectar, UPower pasa por `pending-charge` y Noctalia emite
`battery_charging`, no `battery_plugged`. Es exactamente el escenario que
el comentario del script ya describía, pero el hook no estaba colgado de
ese evento.

**Fix (`48cf2f4`):** colgar `noctaliaq-gpu-prime on` también de
`battery_charging`. Es seguro porque el script ya verifica sysfs y toma
`flock`: el disparo redundante se descarta solo. Confirmado en vivo —
19:51:02 evento 'on' descartado, sysfs dice 'off' (sin cambio)
19:51:33 PRIME offload activado (AC) [sysfs verificado]

La primera línea es Noctalia mandando `on` durante la transición, cuando
sysfs todavía decía `off`. El script lo rechazó y aplicó el estado real
31s después. La verificación contra sysfs no es paranoia: es lo único
que evita que el estado quede invertido.

**Revisar en la Alienware:** puede tener el mismo agujero sin que se
notara.

## 3. Validación end-to-end

| Estado | `ACAD/online` | `gpu-prime-state` | `glxinfo -B` |
|---|---|---|---|
| AC | 1 | on | NVIDIA GeForce RTX 4050 Laptop GPU |
| Batería | 0 | off | AMD Radeon 740M Graphics (radeonsi) |

La rama `off` de `gpu-launch` (que arma `VK_ICD_FILENAMES` en runtime
descartando `nvidia` y `hasvk`) funciona igual en AMD que en Intel: en
`/usr/share/vulkan/icd.d/` quedan `nvidia_icd.json` y `radeon_icd.json`,
y descarta el primero. El fix que se hizo para la Alienware resultó
portable sin cambios.

## 4. Rutas hardcodeadas: tres categorías

El `sed` de `install.sh` (línea 41) cubre `/home/kyu/`, `HOOK` y `"HOME/`
**solo sobre `config.toml`**. Todo lo demás se copiaba crudo.

### Bugs reales de portabilidad (`be12dd5`)

- **`config/noctalia/kbd-color-sync.toml`** — dos rutas absolutas en
  `colors_changed`. En cualquier usuario que no fuera `kyu`, el hook de
  color no encontraba `kbd-color-sync` ni `mangohud-color-sync`.
- **`config/MangoHud/MangoHud.conf`** — `output_folder` a un directorio
  inexistente en otra máquina.

Ambos pasan a placeholder `HOME/` con su propio `sed` + guard en
`install.sh`. **MangoHud.conf no usa comillas**, así que necesita el
patrón `=HOME/` en vez de `"HOME/` — el `sed` genérico no lo habría
tocado.

### Cosmético

`config.toml:558` (directorio de screenshots) pasa a `HOME/` por
consistencia. El `sed` de `/home/kyu/` ya lo cubría.

### Falsos positivos

- Los `.bak.*` que ensuciaban el `grep` **nunca estuvieron trackeados**:
  `*.bak.*` ya estaba en `.gitignore` (dos veces). Un `git rm --cached`
  sobre ellos falla con `did not match any files`.
- `~` dentro de scripts de `bin/` **sí expande en bash**. No es bug.
  Aplica solo a TOML.

## 5. `settings.toml` fuera del tracking (`9f336d2`)

Las cuatro rutas `/home/kyu` restantes vivían ahí. En vez de parchearlas,
el archivo salió del repo. Razones:

- `install.sh` nunca lo desplegaba — no aportaba nada.
- La copia del repo estaba congelada en `a637b00` con
  `config_version = 12` (beta.8) contra `13` en vivo.
- Incluía el widget fantasma ya removido en `5a96205`.
- El resto del diff es estado de máquina: opacidades, apps pinneadas,
  wallpaper concreto, directorio de screenshots.
- Es la capa que el daemon reescribe solo: versionarla garantiza drift y
  churn de floats en cada commit.

**Nota:** `git rm --cached` borró también la copia del working tree. No
importa — la que vale es `~/.local/state/noctalia/settings.toml`, que
quedó intacta.

**Regla resultante:** `config.toml` es config portable y se versiona;
`settings.toml` es estado local y no.

## Verificación de cierre

```bash
grep -rn '/home/kyu\|/home/alquinterus' --exclude-dir=.git --exclude-dir=handoffs . \
  | grep -v '\.bak\.\|^./install.sh\|^./config/noctalia/settings.toml'
```

Vacío. Las únicas ocurrencias legítimas restantes son el propio patrón
del `sed` en `install.sh`.

Los tres archivos con placeholder reproducen exactamente lo desplegado:

```bash
diff <(sed "s|\"HOOK\"|\"$HOME/.config/noctalia/scripts/rgb-sync-hook.sh\"|g; s|/home/kyu/|$HOME/|g; s|\"HOME/|\"$HOME/|g" config/noctalia/config.toml) ~/.config/noctalia/config.toml
diff <(sed "s|\"HOME/|\"$HOME/|g" config/noctalia/kbd-color-sync.toml) ~/.config/noctalia/kbd-color-sync.toml
diff <(sed "s|=HOME/|=$HOME/|g" config/MangoHud/MangoHud.conf) ~/.config/MangoHud/MangoHud.conf
```

Los tres vacíos.

## Gotchas de la sesión

- **El estado de PRIME no se inicializa al login.** `gpu-prime-state`
  conserva el valor anterior hasta la primera transición. Si arrancás la
  sesión con el cargador ya puesto, puede quedar desfasado.
- **Una prueba de transición no se puede pegar en un solo bloque.** El
  primer intento dio un falso negativo porque los dos bloques (conectado
  / desconectado) corrieron seguidos sin tocar el cargador.
- **`bash -n` antes de commitear un patch a `install.sh`.** Las comillas
  anidadas del `sed` dentro de un heredoc de Python son lo más frágil.
- **`git rm --cached` borra del working tree.** Esperado, pero conviene
  saberlo antes de correrlo sobre un archivo que se quiere conservar.

## Pendientes

- [ ] **Relogin limpio**: confirmar que `gpu-prime-state` arranca
      coherente. Si no, `spawn-sh "$HOME/.local/bin/noctaliaq-gpu-prime on"`
      en `autostart.kdl` (el argumento da igual, el script corrige contra
      sysfs).
- [ ] **Lanzar una app desde el launcher de Noctalia** y confirmar que
      abre. El wrapper envuelve todo lo que lanza launcher/dock/taskbar —
      es el escenario del bug del 2026-08-18 y no se probó en esta sesión.
- [ ] **Alienware**: `git pull` + `install.sh` para llevarle el fix de
      `battery_charging` y los placeholders. Verificar si ahí también
      fallaba `battery_plugged`.
- [ ] Heredado: `noctalia completions` en `install.sh`.
- [ ] Heredado: confirmar `Mod+B`/Zen y `miri.service` en máquina nueva.
- [ ] Heredado: ciclo suspend/resume como vía del race de DRM.
