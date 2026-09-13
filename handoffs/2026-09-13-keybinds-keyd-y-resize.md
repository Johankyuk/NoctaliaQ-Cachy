# Keybinds: tap de Super vía keyd, resize por presets y limpieza

**Fecha:** 2026-09-13
**Componente:** config/niri/cfg/keybinds.kdl, config/niri/cfg/layout.kdl, keyd/, install.sh, README
**Commits:** `846c4b1`, `b4db713`, `93d4be0`, `0376c14`, `5a2a0b0`, `2f82348`, `31b7f48`

## Contexto

Objetivo inicial: que el tap de Super solo abriera el control center de Noctalia y
que las configuraciones bajaran de `Mod+Shift+S` a `Mod+S`. Derivó en una limpieza
general de keybinds y en el primer módulo de `keyd` del repo.

## 1. niri no soporta binds de modificador solo

`Mod` a secas no valida. Existe el truco `Mod+Super_L` (usar el nombre XKB del
modificador como tecla), pero es el bug [niri#605], **abierto**, con PR #2456 sin
mergear: ese bind dispara con *cualquier* combinación que incluya el modificador,
así que `Mod+S` también abriría el control center. Inservible.

La ruta viable es `keyd`, que intercepta a nivel evdev por debajo del compositor.

## 2. ⚠️ `KEY_F13` llega a XKB como `XF86Tools`

Esto costó una iteración completa. `keyd monitor` reportaba `f13 down/up`
correctamente, pero el bind `F13` en niri nunca disparaba. `niri validate` daba
limpio — acepta `F13` como nombre válido aunque tu layout no lo entregue nunca.

`wev` fue lo que lo resolvió:

```
sym: XF86Tools    (269025153), utf8: ''
```

**El bind en niri es `XF86Tools`, no `F13`.** Regla general: `niri validate` valida
la *sintaxis* del nombre de tecla, no que tu layout lo produzca. Verificar siempre
con `wev` antes de dar por bueno un bind de tecla exótica.

## 3. ⚠️ El timeout de `overloadt2` es el mismo para el tap y para Super+click

`leftmeta = overloadt2(meta, f13, N)`: el tap se emite si sueltas antes de `N` ms;
si te pasas, sale `leftmeta` normal.

Lo no obvio: **ese mismo umbral retrasa el `leftmeta` del hold**, y eso rompe el
arrastre de ventanas flotantes con Super+click. Con `N=500`, un click antes de los
500 ms llegaba sin modificador y la flotante no se movía. Diagnóstico: sostener
Super un segundo completo antes de hacer click — si así sí funciona, es el timeout.

Trade-off irreducible con `overloadt2`:

| N | Tap de Super | Super+click |
|---|---|---|
| 200 | falla (tap típico se pasa) | instantáneo |
| 250 | funciona | funciona — **elegido** |
| 500 | funciona | falla (medio segundo de espera) |

`overload(meta, f13)` sin timeout da hold instantáneo, pero entonces cualquier Super
largo sin combinar dispara el tap al soltarlo. Se descartó.

## 4. Falsa pista: el `Control_L` fantasma

Durante el debug, `wev` mostraba `Control_L` pegado a cada `Super_L`, lo que hacía
pensar que `Mod+X` llegaba como `Mod+Ctrl+X`. Se probó una capa `[supermod:M]`
explícita para "arreglarlo".

**No era keyd.** Con `keyd monitor` y pulsaciones controladas (solo Super, nada más)
la salida es limpia: `f13 down/up` sin `leftcontrol`. Los `Control_L` de `wev` eran
teclas propias mezcladas en la captura. Verificar con `keyd monitor` y pulsaciones
aisladas antes de teorizar sobre la config de keyd.

## 5. ⚠️ `~/.config/niri/cfg` es symlink al repo

Para todo lo que vive bajo `config/niri/cfg/`, el `cp` de deploy y el `diff`
repo-vs-desplegado son no-ops (`cp: are the same file`). La verificación real ahí es
`niri validate`, no el diff. Ojo con la conclusión falsa "SIN DRIFT".

Corolario: un `.bak` creado en ese directorio queda dentro del árbol del repo.
Aparecieron `keybinds.kdl.bak.*` y tres `bin/rotate-backups.sh.bak.*` (estos últimos
sí trackeados, y `install.sh` los copiaba a `~/.local/bin` porque el `for f in bin/*`
no filtra). Borrados.

## 6. `Equal` no existe en layout latam

`Mod+Shift+Equal` nunca disparaba mientras `Mod+Shift+Minus` sí. Causa: en latam `=`
es `Shift+0`, no tiene tecla propia. La tecla física `+` es `plus` en XKB.

Mismo caso que el `XF86Tools`: `niri validate` aceptaba `Equal` sin chistar.

## Cambios aplicados

### keyd (nuevo módulo)

`keyd/default.conf`:

```
[ids]
*

[main]
leftmeta = overloadt2(meta, f13, 250)
```

Desplegado desde `install.sh` (bloque nuevo antes de "Scripts .local/bin"): instala el
paquete, respalda `/etc/keyd/default.conf` si existe, copia, verifica con `cmp` y
`exit 1` si difiere, `systemctl enable --now keyd` + `keyd reload`.

Es el primer bloque de `install.sh` que escribe en `/etc`. Se metió ahí y no en un
módulo manual aparte porque el script ya usa `sudo` en todos sus bloques de `pacman`,
y el requisito era replicabilidad completa de un tiro.

**Escape si keyd deja el teclado inutilizable:** sostener `backspace+escape+enter`.

### Keybinds

| Antes | Ahora | Acción |
|---|---|---|
| `Mod+S` | `XF86Tools` (tap de Super) | `panel-toggle control-center` |
| `Mod+Shift+S` | `Mod+S` | `settings-toggle` |
| `Mod+CTRL+Return` + `Mod+Space` | solo `Mod+Space` | `panel-toggle launcher` |
| `Mod+Equal` | `Mod+Plus` | `set-column-width +10%` → *eliminado después* |
| `Mod+R` / `Mod+Shift+R` | `Mod+W` / `Mod+Shift+W` | `switch-preset-column-width[-back]` |
| `Mod+Ctrl+Shift+R` | `Mod+L` / `Mod+Shift+L` | `switch-preset-window-height[-back]` |
| `Mod+W` | `Mod+Shift+T` | `toggle-column-tabbed-display` |

Eliminados: `Mod+L` (alias vim de `focus-column-right`, duplicaba `Mod+Right`),
`Mod+Ctrl+F` (`expand-column-to-available-width`), y los cuatro binds de resize por
pasos (`set-column-width ±10%`, `set-window-height ±10%`).

Intactos: `Mod+F` (`maximize-column`), `Mod+Shift+F` (`fullscreen-window`),
`Mod+Ctrl+R` (`reset-window-height`), `Mod+ALT+L` (lock).

### layout.kdl

`preset-column-widths` y `preset-window-heights` pasan a diez pasos: `0.1` … `0.9`,
`1.0`. `preset-window-heights` no existía, así que `switch-preset-window-height`
ciclaba los defaults de niri — de ahí la impresión de que "solo cambia el ancho".

`switch-preset-*` cicla en anillo: tras el 100% vuelve al 10%. Diez presets significa
hasta 9 pulsaciones para cruzar de punta a punta.

## Descartado: snap de columna a media pantalla

Se intentó `Mod+Alt+←/→` con `spawn-sh "set-column-width 50% && move-column-to-first|last"`.
Funciona con dos o más columnas, pero **con una sola columna no hace nada**: en niri
las columnas viven en una tira horizontal y `move-column-to-first/last` reordena
dentro de esa tira; con una sola no hay posición que cambiar y siempre queda pegada a
la izquierda. No existe un "snap a la mitad de la pantalla" en el modelo de niri.

Alternativas identificadas, no implementadas:

- `center-focused-column "always"` en `layout.kdl` (global, no por tecla; hoy en `"never"`)
- Sacar la ventana del tiling (`Mod+T`) y usar `move-floating-window -x/-y` en píxeles

Los binds se quitaron.

## Notas de proceso

- `niri msg action move-window` / `resize-window` **no existen**. El arrastre de
  flotantes con Mod+click es comportamiento integrado de niri, no un bind — intentar
  declararlo rompe el parseo del KDL con `expected quit, suspend, or one of 133 others`.
- El script de patch se corrió dos veces por accidente y metió binds duplicados
  además del error de parseo. El guard de duplicados del verificador (construir un
  dict de tokens y abortar si se repite alguno) atrapó el estado sucio en el
  siguiente intento. Vale la pena mantenerlo en todo patch de `keybinds.kdl`.
- `ls` aliaseado a `eza` volvió a dar un falso "error de argumento" con `ls bin/`.
  Usar `command ls`. Ya documentado dos veces antes.
- Un `cd` en un bloque de copy-paste no persiste al siguiente bloque: un
  `git ls-files ... || echo "no trackeado"` corrido desde `~` dio un falso negativo
  (git falló por no estar en el repo, y el `||` se comió el error).

## Verificado

- Tap de Super abre el control center; hold de Super sigue funcionando para todos los
  `Mod+X`; Super+click arrastra flotantes.
- `Mod+W`/`Mod+Shift+W` y `Mod+L`/`Mod+Shift+L` ciclan los presets en ambos sentidos.
- `niri validate` limpio tras cada patch.
- `git status` limpio y pusheado.

## Pendiente

- [ ] `keyd` no se ha probado en un `install.sh` desde cero en máquina limpia. En
      particular, `XF86Tools` depende del layout XKB de esa máquina — reverificar con
      `wev` en la Alienware antes de dar por replicable el tap de Super.
- [ ] El alto de ventana solo se mueve si la columna tiene más de una ventana; con una
      sola, `Mod+L` no muestra efecto visible. Es comportamiento de niri, no un bug.
- [ ] Heredados: `hooks.colors_changed` hardcodea `/home/kyu`; screenshot path en
      `config.toml` sin placeholder `HOME/`; `logger` faltante en `rgb-sync.py`;
      `noctalia completions` en `install.sh`; ciclo suspend/resume como vía del race
      de DRM.
