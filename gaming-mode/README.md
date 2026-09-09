# gaming-mode

Modo gaming y sincronía térmica/GPU para ASUS TUF sobre CachyOS + niri + Noctalia,
sin asusctl, sin supergfxctl, sin optimus-manager. Solo sysfs, udev, polkit y systemd.

## Qué hace y qué no

| | Quién se encarga |
|---|---|
| CPU (EPP, governor) y `platform_profile` | **power-profiles-daemon** — este módulo no lo toca |
| Curvas de ventilador CPU/GPU | `noctaliaq-power` |
| Relojes / runtime PM de la dGPU | `noctaliaq-power` |
| Híbrido ↔ integrado | `noctaliaq-gpu-mode` |
| MUX / modo "ultimate" | **fuera de alcance a propósito** (exige reboot por ACPI y puede dejarte sin video) |

La regla de oro es no pelear con PPD. Noctalia cambia el perfil → PPD ajusta CPU y
`platform_profile` → el hook `power_profile_changed` dispara `noctaliaq-power apply`,
que pone encima lo que PPD no cubre.

### Por qué hay que reaplicar la curva en cada cambio de perfil

`asus-wmi` guarda las curvas por perfil térmico y, cuando `throttle_thermal_policy`
cambia, el driver **desactiva la curva personalizada** y vuelve al automático de
fábrica. Es decir: cada vez que PPD cambia de perfil, tu curva se cae sola. De ahí
que la sincronía no sea un lujo sino el único modo de que las curvas sobrevivan.

Lo mismo al despertar de suspensión: la EC vuelve a automático. Por eso hay un hook
en `/usr/lib/systemd/system-sleep/`.

## Criterio de las curvas

El kernel no valida nada de esto (`asus-wmi` lo dice explícito: *"no safety check of
the set fan curves — this must be done in userspace"*), así que la cordura vive en
`power.conf`.

Las curvas están pensadas **contra el ciclado térmico**, no para el número más bajo:

1. **Piso de 20 % en performance.** Una curva que deja el ventilador en 0 % lo obliga
   a arrancar y parar cada pocos segundos bajo carga intermitente. Ese arranque/paro
   es peor que el calor: mueve la temperatura de golpe y castiga el rodamiento.
2. **Sin acantilados.** Ningún salto mayor a ~20 puntos de PWM entre puntos contiguos
   salvo en el último tramo (el de emergencia). Un salto de 30 % a 80 % en 3 °C es lo
   que produce el efecto acordeón: enfría de más, el ventilador baja, sube la temp,
   vuelve a subir el ventilador.
3. **Techo en 90 %, no 100 %.** El último 10 % de PWM compra ~2 °C a cambio de mucho
   ruido y desgaste. El firmware conserva su corte térmico de emergencia por debajo.
4. **Se acepta estabilizar en 78-85 °C.** Un silicio que vive estable a 80 °C sufre
   menos que uno que oscila entre 55 y 88 todo el rato. El daño por fatiga de las
   uniones de soldadura depende del **ΔT del ciclo**, no de la temperatura absoluta
   mientras estés dentro de especificación (Tjmax de estas piezas está muy arriba).

### Tabla

Temperatura °C → PWM (0-255, el driver lo trata como porcentaje escalado).

**CPU (fan1)**

| Perfil | p1 | p2 | p3 | p4 | p5 | p6 | p7 | p8 |
|---|---|---|---|---|---|---|---|---|
| power-saver | 30→0 | 45→0 | 55→38 | 65→64 | 75→89 | 82→115 | 88→153 | 95→204 |
| balanced | 30→0 | 45→26 | 55→51 | 65→77 | 73→102 | 80→128 | 87→166 | 94→217 |
| performance | 30→51 | 45→64 | 55→89 | 63→115 | 70→140 | 78→166 | 85→191 | 92→230 |

**GPU (fan2)** — mismos PWM, pero el eje de temperatura corre unos grados más abajo
porque una RTX 4050 móvil empieza a recortar clocks cerca de 87 °C, no de 95.

| Perfil | p1 | p2 | p3 | p4 | p5 | p6 | p7 | p8 |
|---|---|---|---|---|---|---|---|---|
| power-saver | 30→0 | 45→0 | 55→38 | 62→64 | 70→89 | 76→115 | 82→153 | 88→204 |
| balanced | 30→0 | 45→26 | 55→51 | 62→77 | 68→102 | 74→128 | 80→166 | 87→217 |
| performance | 30→51 | 45→64 | 55→89 | 62→115 | 68→140 | 74→166 | 80→204 | 87→230 |

Si tras un par de sesiones de juego el CPU se queda pegado en 90 °C, sube 10-13 puntos
de PWM a los puntos 5 y 6 de performance — **no** muevas las temperaturas hacia abajo,
que es justo lo que reintroduce el acordeón.

## Piezas instaladas

| Ruta | Qué es |
|---|---|
| `/usr/local/bin/noctaliaq-power` | aplica curvas + política de dGPU; `apply`, `gaming on\|off`, `status`, `reset` |
| `/usr/local/bin/noctaliaq-gpu-mode` | `status`, `hybrid`, `integrated` (`--persist`, `--at-boot`) |
| `/etc/noctaliaq/power.conf` | las curvas y los límites de GPU |
| `/etc/udev/rules.d/60-noctaliaq-hwaccess.rules` | da escritura a `wheel` sobre hwmon y `power/control` |
| `/usr/share/polkit-1/actions/org.noctaliaq.gpu-mode.policy` | acción polkit del switch de GPU |
| `/etc/polkit-1/rules.d/49-noctaliaq-gpu-mode.rules` | opcional: sin contraseña para `wheel` local y activo |
| `/etc/systemd/system/noctaliaq-gpu-mode.service` | reaplica el modo integrado en el arranque |
| `/usr/lib/systemd/system-sleep/noctaliaq-power-resume` | reaplica la curva al despertar |

Los binarios van a `/usr/local/bin` y no a `~/.local/bin` porque greetd lanza niri vía
PAM y `~/.local/bin` nunca entra en el PATH heredado — el mismo problema documentado en
`learnings.md`. Además `pkexec` exige que su objetivo viva en una ruta root.

Ningún archivo contiene `/home/kyu`: la ruta del binario es absoluta y del sistema, así
que el hook de Noctalia es idéntico en el repo y en el desplegado (no hace falta el
placeholder `HOME/`).

## Uso

```bash
./gaming-mode/install-gaming-mode.sh --probe     # diagnóstico, no toca nada
./gaming-mode/install-gaming-mode.sh             # instala
./gaming-mode/install-gaming-mode.sh --uninstall

noctaliaq-power status
noctaliaq-power gaming on
noctaliaq-gpu-mode status
noctaliaq-gpu-mode integrated --persist
```

## En el launcher

`install-gaming-mode.sh` despliega cuatro entradas en
`~/.local/share/applications/`, que es de donde el launcher de Noctalia lee:

| Entrada | Qué hace | Acciones (clic derecho) |
|---|---|---|
| Modo Gaming | alterna el modo con un clic | Activar / Desactivar |
| Estado térmico y de energía | perfil, curvas vivas y dGPU | Reaplicar curvas / Ventiladores en automático |
| Modo de gráficos | estado de la GPU | Cambiar a híbrido / Cambiar a solo iGPU |
| Asistente gaming-mode | reinstala o diagnostica | Solo diagnosticar |

Las acciones de clic derecho requieren `show_app_actions` activo en el launcher
(existe desde beta.9). Sin eso las entradas siguen funcionando, solo pierdes el
submenú.

Las que abren terminal pasan por `noctaliaq-hold`, que espera un Enter antes de
cerrar: una entrada `.desktop` con `Terminal=true` cierra la ventana en cuanto
el proceso termina y no alcanzas a leer nada. El spec de `.desktop` no permite
`Terminal` dentro de un grupo `[Desktop Action]`, así que el wrapper es la única
forma de que las acciones también dejen ver su salida.

El `.desktop` del asistente es el único con una ruta al repo, y se genera en la
instalación expandiendo `@REPODIR@`. Nada de eso se versiona con la ruta dentro.

Keybinds sugeridos para `keybinds.kdl`:

```kdl
Mod+Shift+G { spawn "noctaliaq-power" "gaming" "toggle"; }
```

## Limitaciones conocidas

- **El modo integrado en caliente casi nunca funciona con la sesión abierta.** Si niri,
  Xwayland o cualquier proceso tiene abierto un `/dev/nvidia*`, `modprobe -r` falla. El
  script te dice exactamente quién lo retiene y te ofrece `--at-boot`. Desde un TTY
  (Ctrl+Alt+F2, sin sesión gráfica) sí funciona en caliente.
- **`nvidia-smi -pl` suele estar bloqueado en GPU móviles.** `--probe` te dice si tu
  4050 reporta rango min/max; si no, deja `NV_PL_*` vacío y usa `NV_LGC_*`.
- **Si `mkinitcpio.conf` tiene `nvidia` en `MODULES=`**, los módulos se cargan a la
  fuerza desde el initramfs y la blacklist no los detiene. `--probe` lo avisa.
- **`dgpu_disable` no está en todos los TUF.** Si falta, se cae a `remove` + `rescan`
  del bus PCI, que funciona pero es más brusco y a veces necesita dos intentos.
- La curva se pierde si algo más escribe `platform_profile` sin pasar por PPD. El hook
  `power_profile_changed` solo se entera de lo que ve Noctalia/UPower.

## Verificación

```bash
noctaliaq-power status                       # modo de cada fan + los 8 puntos vivos
journalctl -t noctaliaq-power -b --no-pager  # qué aplicó y cuándo
journalctl -t noctaliaq-gpu-mode -b --no-pager
watch -n1 'sensors | grep -iE "fan|tctl|edge"'
```

Que `pwm1_enable` valga `1` es la única prueba de que tu curva está viva; `2` significa
que el firmware retomó el control.
