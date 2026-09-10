# gaming-mode: curvas de ventilador, sincronía con PPD y switch de GPU

**Fecha:** 2026-09-08
**Componente:** `gaming-mode/`, `config/noctalia/config.toml`
**Sistema:** TUF Gaming A16 FA607NUG, CachyOS, kernel 7.2.2, Noctalia
`5.0.0_beta.10-1-dirty`, PPD 0.30-3
**Resultado:** instalado y validado; sincronía probada en ambos sentidos

## Resumen

Módulo nuevo que da modo gaming, curvas de ventilador conservadoras y switch
híbrido/integrado sin asusctl ni supergfxctl. Solo sysfs, udev, polkit y
systemd. La pieza central no es la curva sino la **reaplicación**: asus-wmi
descarta la curva personalizada en cada cambio de perfil térmico, así que sin
sincronía las curvas no sobreviven ni un cambio de perfil.

## 1. Noctalia no gestiona energía

Su selector de perfiles es un cliente D-Bus puro de
`org.freedesktop.UPower.PowerProfiles`. Los IPC `power-set` / `power-cycle`
escriben `ActiveProfile` y nada más; la pestaña del Control Center se oculta
entera si no hay PPD. **Cero lógica de CPU, ventiladores o GPU.**

La pregunta útil no es qué hace Noctalia, es qué hace PPD.

## 2. Qué hace PPD en esta máquina (auditado, no supuesto)

`gaming-mode/tools/ppd-audit.sh` barre los tres perfiles y captura cada nodo.
Resultado del 2026-09-08, **con batería** (`ac_online 0`):

| | power-saver | balanced | performance |
|---|---|---|---|
| platform_profile | quiet | balanced | performance |
| throttle_thermal_policy | 2 | 0 | 1 |
| EPP | power | balance_power | performance |
| governor | powersave | powersave | **performance** |
| scaling min/max kHz | 412250 / 3201000 | 1091250 / 4753000 | 1091250 / 4753000 |
| boost (policy0) | **0** | 1 | 1 |
| amdgpu dpm level | auto | auto | auto |
| panel ABM | 0 | 0 | 0 |
| pwm1_enable | 2 | 2 | 2 |
| dGPU | auto/suspended/D3hot | igual | igual |

Lecturas:

- **Dos drivers cargados**, `CpuDriver: amd_pstate` + `PlatformDriver:
  platform_profile`. Ningún `placeholder`, así que la sincronía por perfil es
  un punto de enganche válido.
- **Dos handlers de platform_profile**: `amd-pmf` y `asus-wmi`. PPD escribe en
  el agregado `/sys/firmware/acpi/platform_profile` y ambos se mueven juntos.
  Riesgo teórico: que amd-pmf cambie el perfil por su cuenta sin pasar por
  D-Bus, con lo que el hook no se enteraría. Ver Validación.
- **power-saver limita de verdad**, no solo sugiere: apaga boost y baja el
  techo de 4753 a 3201 MHz.
- **PPD no toca la dGPU en ningún perfil.** Ese espacio es del módulo.
- **`amdgpu_dpm` no está actuando**: `auto` en los tres, incluso en power-saver
  con batería, que es justo cuando debería dispararse. No hay conflicto, pero
  por eso `AMDGPU_DPM_LEVEL` quedó vacío (escribir `auto` sería ruido).
- **El ABM del panel está en 0** con batería en power-saver, cuando PPD debería
  subirlo. O hay `amdgpu.abmlevel=0` en la cmdline o esa acción no está viva.
  Ahorro de batería sin aprovechar. Sin investigar.

## 3. Por qué hay que reaplicar la curva

`asus-wmi` guarda las curvas por perfil térmico y, cuando
`throttle_thermal_policy` cambia, **desactiva la curva personalizada** y vuelve
al automático de fábrica. El kernel además no valida nada: *"there is no safety
check of the set fan curves — this must be done in userspace"*.

O sea que cada cambio de perfil de PPD te tira la curva. La sincronía no es
comodidad, es la única forma de que sobreviva. Igual al despertar de
suspensión, de ahí el hook en `/usr/lib/systemd/system-sleep/`.

## 4. Criterio de las curvas

Diseñadas contra el ciclado térmico, no para la temperatura mínima. El daño por
fatiga de las uniones depende del ΔT del ciclo, no de la temperatura absoluta
mientras estés en especificación.

1. **Piso de 20 % en performance.** Sin piso el ventilador arranca y para bajo
   carga intermitente, y cada arranque mueve la temperatura de golpe.
2. **Sin acantilados.** Ningún salto mayor a ~20 puntos de PWM entre puntos
   contiguos salvo el tramo de emergencia. Los saltos grandes producen efecto
   acordeón: enfría de más, baja el ventilador, rebota la temp.
3. **Techo en 90 %, no 100 %.** El último 10 % compra ~2 °C a cambio de mucho
   ruido y desgaste. El corte térmico del firmware sigue por debajo.
4. **Se acepta estabilizar en 78-85 °C.** Estable a 80 sufre menos que oscilando
   entre 55 y 88.

La GPU usa los mismos PWM con el eje de temperatura unos grados abajo: la 4050
móvil recorta clocks cerca de 87 °C, no de 95.

Si el CPU se queda pegado en 90 bajo carga, subir 10-13 puntos de PWM a los
puntos 5 y 6 de performance. **No** bajar las temperaturas, que es lo que
reintroduce el acordeón.

## 5. Piezas

| Ruta | Qué es |
|---|---|
| `/usr/local/bin/noctaliaq-power` | `apply`, `gaming on\|off`, `status`, `reset` |
| `/usr/local/bin/noctaliaq-gpu-mode` | `status`, `hybrid`, `integrated` (`--persist`, `--at-boot`) |
| `/etc/noctaliaq/power.conf` | curvas y límites de GPU |
| `/etc/udev/rules.d/60-noctaliaq-hwaccess.rules` | escritura a `wheel` sobre hwmon y `power/control` |
| `/usr/share/polkit-1/actions/org.noctaliaq.gpu-mode.policy` | acción del switch de GPU |
| `/etc/polkit-1/rules.d/49-noctaliaq-gpu-mode.rules` | sin contraseña para wheel local+activo |
| `/etc/systemd/system/noctaliaq-gpu-mode.service` | reaplica el modo integrado al arrancar |
| `/usr/lib/systemd/system-sleep/noctaliaq-power-resume` | reaplica la curva al despertar |

Los binarios van a `/usr/local/bin` y no a `~/.local/bin`: greetd lanza niri por
PAM y `~/.local/bin` nunca entra en el PATH heredado. Además pkexec exige que su
objetivo viva en ruta root. Efecto secundario: cero `/home/kyu` en el módulo, y
el hook es idéntico en repo y desplegado sin necesidad del placeholder `HOME/`.

**PPD se queda con CPU y `platform_profile`; el módulo solo cubre lo que PPD no
toca.** No pelear con él fue la decisión de diseño principal.

## 6. Hallazgos de hardware

- `dgpu_disable` **sí está expuesto** (valor 0). Camino limpio para el modo
  integrado sin tocar el MUX.
- `gpu_mux_mode = 1` (Optimus). Fuera de alcance a propósito: exige reboot por
  ACPI y puede dejar el equipo sin video.
- La 4050 **acepta `nvidia-smi -pl` con rango 5-140 W**, cosa rara en móviles.
  Control de TGP real disponible.
- La dGPU duerme en **D3hot, no D3cold**. Con
  `options nvidia NVreg_DynamicPowerManagement=0x02` bajaría a D3cold. Sin
  probar; tiene historial de ser quisquilloso.
- **El brillo va por `nvidia_wmi_ec_backlight`**, no por amdgpu. Apagar la dGPU
  probablemente deja sin control de brillo. Probar el modo integrado solo con
  un TTY a mano y sin prisa.

## Gotchas de la sesión

- **`/etc/polkit-1/rules.d/` es 750 root:polkitd.** El `cmp` de verificación
  corría como usuario, no podía leer el destino y reportaba "difiere" sobre un
  archivo idéntico. Verificar bajo `sudo` cualquier cosa que se escriba ahí.
  Ya estaba documentado el 2026-08-19 y volvió a costar tiempo.
- **Los hooks de este config son arrays, no strings.** El instalador vio
  `power_profile_changed = []`, decidió no pisar la clave existente y dejó la
  sincronía muerta. Hay que fusionar dentro del array, no reemplazar.
- **`verify()` dio falso positivo**: hace `grep power_profile_changed` y un
  array vacío también matchea. Debe buscar `noctaliaq-power`.
- **`noctalia msg config reload` no existe.** Un `cmd || pkill -9` con ese
  comando inventado mató el daemon. Verificar la sintaxis del IPC antes de
  encadenar un fallback destructivo.
- **`nvidia-smi -lgc` y `-pl` requieren root**, aunque consultarlos no. El
  script corre como usuario a propósito, así que fallaban siempre. Además sin
  persistence mode el reloj bloqueado se pierde al suspender la GPU, y activar
  persistence impide que duerma. `-lgc` en power-saver es doblemente inútil:
  `NV_LGC_POWERSAVER` quedó vacío.
- **`sed` sigue devolviendo 0 sin matchear.** Todo `sed -i` de esta sesión fue
  seguido de un `grep -c` con conteo esperado.

## Validación

- Journal con la cadena completa: `started` aplica POWERSAVER al relanzar el
  daemon, y `power_profile_changed` aplica PERFORMANCE al cambiar de perfil.
- `noctaliaq-power status` confirma `fan1/fan2 modo 1` con la curva correcta en
  cada perfil (performance arranca en `30°/51`, power-saver en `30°/0`).
- **Deriva de amd-pmf: 30 muestras en 5 minutos, `pwm=1` en todas.** No
  interfiere. Matiz: la prueba corrió en `quiet` y probablemente en idle. La
  confirmación fuerte es revisar `status` después de la primera sesión de juego.

## Pendientes

- [ ] `install-gaming-mode.sh` no fusiona arrays en `[hooks]`: en cualquier
      máquina con hooks preexistentes deja la sincronía muerta sin avisar. Va
      contra el objetivo de instalar en cualquier máquina. Portar la lógica del
      parche que se aplicó a mano.
- [ ] Arreglar el falso positivo de `verify()`.
- [ ] Cap de TGP a ~105 W dentro de `gaming on`, vía pkexec como el switch de
      GPU. Ahí la GPU está despierta, así que ni persistence ni suspensión
      estorban. Sirve además para cerrar el pendiente de medir con MangoHud si
      `performance` mejora fps de verdad.
- [ ] Confirmar `status` tras una sesión de juego real (deriva bajo carga).
- [ ] Probar el modo integrado, con TTY a mano por lo del brillo.
- [ ] Investigar el ABM en 0: revisar `amdgpu.abmlevel` en la cmdline.
- [ ] Evaluar `NVreg_DynamicPowerManagement=0x02` para D3cold.
- [ ] Heredado: ciclo suspend/resume como vía del race de DRM. El hook de
      `system-sleep` es otra pieza que ahora corre en ese camino.

---

## Añadido 2026-09-08 (cierre) — launcher y bloqueo de faillock

### Entradas en el launcher de Noctalia

Cuatro `.desktop` en `~/.local/share/applications/`: Modo Gaming (toggle,
con acciones Activar/Desactivar), Estado térmico, Modo de gráficos y el
Asistente. Se añadió el subcomando `noctaliaq-power gaming toggle` porque dos
entradas separadas para encender y apagar es incómodo, y `notify-send` para
tener confirmación sin terminal.

Dos detalles del formato `.desktop`:

- `Terminal=true` cierra la ventana en cuanto el proceso termina, así que no
  se alcanza a leer nada. De ahí `noctaliaq-hold`, que espera un Enter.
- El spec **no permite la clave `Terminal` dentro de `[Desktop Action]`**, así
  que el wrapper es la única forma de que las acciones muestren su salida.

El único `.desktop` con ruta al repo es el del asistente, y se genera en la
instalación expandiendo `@REPODIR@` con verificación de que no quede sin
expandir. Las acciones de clic derecho necesitan `show_app_actions` en el
launcher (existe desde beta.9).

### Pendientes cerrados

- `install-gaming-mode.sh` ahora **fusiona dentro de los arrays** de `[hooks]`.
  Probado contra cuatro casos: arrays existentes, sin sección `[hooks]`, hooks
  como string suelto, y segunda corrida. TOML válido en todos.
- `verify()` cuenta ocurrencias de `noctaliaq-power` en vez de buscar el nombre
  de la clave, que un array vacío también matcheaba.

### ⚠️ Gotcha grave: sudo en sustitución de procesos bloquea la cuenta

Un `diff <(sudo cat ...) archivo` dejó tres procesos `sudo` (PIDs 141557,
141284, 141467) peleándose el mismo tty en cuatro segundos. PAM no llega a
comparar nada y falla con:

```
pam_unix(sudo:auth): conversation failed
pam_unix(sudo:auth): auth could not identify password for [kyu]
pam_faillock(sudo:auth): Consecutive login failures ... account temporarily locked
```

Tres de esos disparan `faillock` (`deny=3`). El síntoma parece contraseña
equivocada y no lo es. Costó 17 minutos.

**La columna `Valid` de `faillock` no sirve** para saber si el bloqueo sigue
activo: refleja `fail_interval` (900 s), no `unlock_time` (600 s), y aquí se
quedó en `V` mucho más allá de ambos. El dato confiable es el journal:

```bash
journalctl -b --no-pager | grep -iE 'faillock|pam_unix\(sudo|authentication failure' | tail -20
```

Regla: si un comando necesita `sudo`, que `sudo` sea la primera palabra de la
línea. Nunca dentro de `<(...)`, de un pipe ni de una subshell.

### Regresión de la sesión

Sobrescribir `/etc/noctaliaq/power.conf` desde un paquete nuevo revirtió
`NV_LGC_POWERSAVER=""` a `"0,900"`: el arreglo se había aplicado solo en la
máquina, no en el origen. Todo cambio en caliente tiene que volver al repo el
mismo día o el siguiente despliegue lo pisa.

### Añadido 2026-09-08 — unificación con gpu-prime (composición)

El offload de PRIME lo decide **`noctaliaq-gpu-prime` y solo él**: verifica el
cargador contra sysfs porque los hooks de Noctalia disparan mal en las
transiciones, con `flock` y debounce. Escribe `gpu-prime-state`, que leen
`noctaliaq-gpu-launch` (nativas, vía `launch_apps_custom_command`) y
`noctaliaq-gpu-flatpak-sync` (flatpaks, vía `flatpak override` porque flatpak
no hereda env vars del host).

Se descartó darle un override al modo gaming: sería romper la premisa que hace
fiable a ese script. En su lugar, `noctaliaq-power` **lee y nunca escribe**:

- `status` reporta PRIME y marca ⚠ si no concuerda con el cargador.
- `status` reporta el techo de TGP actual contra el máximo.
- `gaming on` avisa con batería, porque ahí `gpu-launch` oculta el ICD de
  NVIDIA al loader de Vulkan y las apps Vulkan-nativas correrían sobre la iGPU.

**El TGP no se toca.** Default 55 W, máximo 140, y `nvidia-powerd` lo mueve en
vivo: observado en 115 bajo performance y en 55 en power-saver idle. Fijarlo
con `-pl` sería competir con Dynamic Boost, que lo hace mejor que un número
fijo. Se descarta el cap de 105 W que se había propuesto.

### Dos bugs corregidos en el camino

- **SIGPIPE + `pipefail`.** `nvidia-smi | awk '...{print; exit}'`: awk cierra la
  tubería, nvidia-smi muere con 141 y `pipefail` marca la función como fallida
  aunque el dato ya estaba impreso. Reproducido: con `exit` da 141, sin `exit`
  da 0. Solución: acumular y volcar en `END`, sin `exit`.
- **`gaming on` repetido pisaba el perfil previo** con `performance`, así que
  `off` caía al fallback. Ahora solo guarda si el fichero de estado no existe.

### Añadido 2026-09-08 — cierre de pendientes

**Deriva bajo carga: no existe.** `tools/drift-test.sh` con 12 hilos al 100 %
en performance: `pwm1_enable` se mantuvo en 1 a 85-87 °C sostenidos. Las RPM
suben en rampa (3106 → 4053 → 4889 → 5600), sin acantilados, que era el
objetivo del diseño. amd-pmf no interfiere.

De paso el test capturó el ciclo completo en dos muestras consecutivas:
`pwm1=2` al cambiar el perfil a quiet, `pwm1=1` dos segundos después cuando el
hook la repuso. La premisa del módulo, demostrada en vivo.

**Race de DRM por suspensión: no se manifiesta.** Ciclo suspend/resume sin
`Device or resource busy` en el journal. Cierra el pendiente heredado.

**La EC no resetea la curva al despertar.** Tras el resume, fan1 y fan2 seguían
en modo 1 aunque el hook de `system-sleep` había fallado. El hook es red de
seguridad, no requisito. (En cambio el reset por cambio de perfil sí es real y
está demostrado arriba.)

**ABM: no accionable.** Sin `amdgpu.abmlevel` en la cmdline, el nodo existe en
`card2-eDP-2`, PPD sin acciones bloqueadas, y aun así 0 con batería en
power-saver. Lo más probable es que la acción de panel de PPD (progresiva
desde 0.22) solo escale con la batería más baja que el 50 % de la prueba.
Observación, no pendiente.

### Tres bugs corregidos

- **`$HOME` sin proteger en `resolve_conf`.** `systemd-sleep` ejecuta los hooks
  sin `HOME`; con `set -u` eso abortaba la función antes de llegar al candidato
  de `/etc`, y el `2>/dev/null` del hook ocultaba el error real de bash. El
  síntoma era un 'no encontré power.conf' sobre un archivo que sí existía.
  Cualquier `$HOME` en código que pueda correr desde systemd va como `${HOME:-}`.
- **`trap` reentrante en drift-test.** Un trap de INT que limpia pero no sale
  deja el bucle vivo, y el `sleep` interrumpido devuelve al instante: cascada de
  iteraciones. Guardia de reentrada + `exit` en el trap.
- **RPM leídas del hwmon equivocado.** `fan1_input` no vive junto a
  `pwm1_enable`; hay que buscarlo en `/sys/class/hwmon/hwmon*/`.

Nota de método: un simulacro de trap con el script en background no vale, un
proceso asíncrono hereda SIGINT ignorado y el trap queda inerte. Probar con TERM.

### Añadido 2026-09-08 — modo integrado: camino de error validado

`noctaliaq-gpu-mode integrated` desde la sesión gráfica falla como debe y
restaura el estado. Quienes retienen los módulos en esta máquina: `niri`,
`noctalia` y el `RDD Process` del navegador. Hace falta cerrar sesión de
verdad, no basta con cerrar ventanas.

**Bug corregido: rearranque asimétrico de servicios NVIDIA.**
`stop_nv_services` solo paraba lo que estaba activo (aquí, `nvidia-powerd`),
pero `start_nv_services` arrancaba los dos a ciegas. Resultado:
`nvidia-persistenced` quedaba corriendo aunque no lo estuviera antes, y
persistence mode impide que la dGPU duerma — fuga de batería silenciosa.
Ahora solo se rearranca lo que este script paró.

Regla general: un script que para servicios para hacer su trabajo debe
restaurar el estado previo, no un estado que asuma correcto.

### Añadido 2026-09-08 — por qué la dGPU nunca duerme

Investigación que salió al intentar activar D3cold. El hallazgo invalida la
recomendación que se había dado antes en este mismo documento.

**La dGPU no duerme nunca.** En un arranque de ~6 h:

```
runtime_active_time    : 21898939 ms  (~6 h)
runtime_suspended_time :     2600 ms  (2.6 s)
```

**Culpable: niri.** Por eliminación, en batería, con el navegador cerrado:
se paró `nvidia-powerd` (soltó, sigue D0), se mató `noctalia` (soltó, sigue
D0), y quedó solo `niri` con `/dev/nvidia0`, `/dev/nvidiactl` y
`/dev/nvidia-modeset` (este con mmap). Con `nvidia_drm.modeset=1` la dGPU se
presenta como dispositivo DRM y el compositor la enumera al arrancar aunque
renderice sobre la Radeon 740M. Es el precio de tener PRIME en Wayland: un
trueque, no un bug.

**Coste medido: 2.08 W** (`nvidia-smi`, 43 °C, 0 % de uso) sobre 11.46 W de
consumo total en batería. Un 18 %, unos 20-30 min de autonomía.

#### Dos vías probadas y descartadas

- **`NVreg_DynamicPowerManagement=0x02` (D3cold).** Nunca se llegó a aplicar:
  es una política para cuando la GPU está ociosa, y aquí jamás lo está. No
  habría cambiado nada. Descartado antes de tocar `modprobe.d`.
- **`render-drm-device` en el bloque `debug` de niri.** `niri validate` la
  acepta (niri 26.04), pero tras reiniciar sesión `niri` seguía con
  `/dev/nvidia-modeset` abierto y la GPU en D0. **Solo elige dónde renderiza,
  no impide la enumeración.** `prime-run` siguió funcionando. Revertido.

**Queda el modo integrado como única vía real** para recuperar esos 2 W: saca
la GPU del bus y ningún cliente puede abrirla. Sigue con el riesgo del brillo
por `nvidia_wmi_ec_backlight`.

#### Notas sueltas

- `~/.config/niri/cfg/` es un **symlink al repo**: editar el repo es editar lo
  desplegado, no hay paso de despliegue. Explica que `find` sin `-L` se lo salte.
- `BAT1` no expone `power_now`; hay que calcular con `current_now` ×
  `voltage_now` / 1e12.
- Medir watts justo después de un `pkill -9` da basura (16.31 W frente a
  11.46 W reales): la pantalla se redibuja y contamina la lectura.

### Pendiente único

- [ ] **Probar el modo integrado.** Camino de error ya validado. Falta la ruta
      feliz: cerrar sesión desde Noctalia, Ctrl+Alt+F2, `sudo systemctl stop
      greetd`, `sudo fuser -v /dev/nvidia*` hasta que salga vacío,
      `noctaliaq-gpu-mode integrated` **sin `--persist`**, `status`,
      `sudo systemctl start greetd`, entrar y probar el brillo. Cualquier
      reinicio revierte. Decidir después si compensa 2.08 W.

### Cerrado 2026-09-09 — modo integrado validado

**El camino era por firmware, no por descarga de modulos en vivo.** El repo
viejo `Johankyuk/NoctaliaQ` (`scripts/noctaliaq-gpu.sh`) ya lo resolvia asi:
escribir `dgpu_disable` en `/sys/class/firmware-attributes/asus-armoury/`
y reiniciar. El firmware apaga la dGPU en el arranque, antes de que exista
niri.

**Precondicion no documentada en ningun lado: los modulos NVIDIA deben estar
descargados al escribir el nodo.** Con la sesion grafica viva el write falla
con `-EIO` y el journal solo dice `asus_armoury: Failed to set current_value:
(result): 0x0`. Mismo comportamiento que supergfxd, que espera a que todas
las sesiones terminen antes de cambiar de modo. Estar en AC no basta ni hace
falta: el primer intento fue en bateria y fallo igual con cargador puesto.

**Gotcha grave: el nodo miente tras un write fallido.** `current_value` y el
nodo legacy `asus-nb-wmi/dgpu_disable` leen `1` aunque `tee` haya devuelto
`-EIO` y `pending_reboot` siga en `0`. Verificar las TRES cosas: codigo de
salida del write, relectura, y `pending_reboot`. Con dos de las tres se
reinicia a ciegas con estado sucio.

**Procedimiento validado** (desde TTY, greetd abajo):

```bash
sudo systemctl stop greetd
sudo modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia
echo 1 | sudo tee /sys/class/firmware-attributes/asus-armoury/attributes/dgpu_disable/current_value
systemctl reboot
```

Reversion: mismo write con `0` desde cualquier sesion (no necesita TTY ni
descargar modulos, porque no hay modulos cargados) + reinicio.

**Medicion: 7.66 W en bateria contra 11.46 W en Hibrida.** 3.8 W, casi el
doble de los 2.08 W que reportaba `nvidia-smi` — la dGPU costaba mas de lo
que ella misma declaraba.

**El brillo sobrevive.** `nvidia_wmi_ec_backlight` sigue funcionando con la
dGPU fuera del bus: el nodo WMI cuelga de `PNP0C14:00` (plataforma ACPI), no
del dispositivo PCI. `amdgpu` sigue emitiendo `Skipping amdgpu DM backlight
registration` — el arbitraje no cambia al apagar la dGPU. `acpi_backlight=native`
queda como pendiente opcional, ya no como bloqueo.

`noctaliaq-gpu-mode status` degrada limpio sin dGPU (reporta `dGPU en bus: no`,
`modulos: ninguno`, y el fallo de `nvidia-smi` como texto informativo).

### Cerrado 2026-09-09 — modo integrado validado + brillo nativo

**El camino era por firmware, no descargando modulos en vivo.** El repo
viejo `Johankyuk/NoctaliaQ` (`scripts/noctaliaq-gpu.sh`) ya lo resolvia asi:
escribir `dgpu_disable` en `/sys/class/firmware-attributes/asus-armoury/` y
reiniciar. El firmware apaga la dGPU en el arranque, antes de que exista niri.
Toda la ingenieria de descargar modulos con la sesion viva sobraba.

**Precondicion no documentada: los modulos NVIDIA deben estar descargados al
escribir el nodo.** Con la sesion grafica viva el write falla con `-EIO` y el
journal solo dice `asus_armoury: Failed to set current_value: (result): 0x0`.
Mismo comportamiento que supergfxd, que espera a que terminen todas las
sesiones. El AC no influye: fallo igual en bateria y con cargador puesto.

**Gotcha grave: el nodo miente tras un write fallido.** `current_value` y el
legacy `asus-nb-wmi/dgpu_disable` leen `1` aunque `tee` devuelva `-EIO` y
`pending_reboot` siga en `0`. Verificar las TRES cosas: codigo de salida,
relectura y `pending_reboot`. Con dos de las tres se reinicia con estado sucio.

**Procedimiento validado** (TTY, greetd abajo):

```bash
sudo systemctl stop greetd
sudo modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia
echo 1 | sudo tee /sys/class/firmware-attributes/asus-armoury/attributes/dgpu_disable/current_value
systemctl reboot
```

Reversion: mismo write con `0` desde cualquier sesion (sin TTY ni modprobe,
porque ya no hay modulos cargados) + reinicio.

**Medicion: 7.66 W en bateria contra 11.46 W en Hibrida.** 3.8 W, casi el
doble de los 2.08 W que reportaba `nvidia-smi`. La dGPU costaba mas de lo que
ella misma declaraba.

#### El brillo: el bloqueo real, y su fix

El nodo WMI sobrevive al apagado (cuelga de `PNP0C14:00`, plataforma ACPI, no
del dispositivo PCI) — pero **deja de mover el panel**: el numero cambia,
`brightness` acepta el valor, y la pantalla no responde. Verificar brillo con
los ojos, nunca con `cat`.

**Fix: `acpi_backlight=native` en la cmdline.** amdgpu se abstenia de
registrar su backlight (`Skipping amdgpu DM backlight registration`) porque el
arbitraje del kernel elegia la ruta `nvidia_wmi_ec`. Con `native` registra
`amdgpu_bl1` (`type=raw`, escala 0-65535) y mueve el panel de verdad.
Teclas de brillo, `brightnessctl` y el slider de Noctalia responden.

El brillo queda independiente de NVIDIA de forma permanente — mejora valida
en Hibrida tambien, no solo en Integrada.

**Punto de edicion de la cmdline: `LINUX_OPTIONS` en `/etc/sdboot-manage.conf`
+ `sudo sdboot-manage gen`.** `/etc/kernel/cmdline` es un archivo muerto en
este sistema (ademas de tener el bloque `splash rw rootflags root=UUID`
duplicado): `sdboot-manage` nunca lo lee — su linea 199 es
`options ${sdoptions} ${LINUX_OPTIONS}`. Editar ahi no habria hecho nada.

Verificar siempre con `sudo bash -c 'grep -h "^options" /boot/loader/entries/*.conf'`:
el ESP no es legible por el usuario, y un glob sobre `/boot` sin sudo da
`zsh: no matches found`, que parece "no existe" y es "no puedo leer".

`noctaliaq-gpu-mode status` degrada limpio sin dGPU.

#### Pendientes derivados

- [ ] Portar al modulo el camino de firmware (`dgpu_disable` + reinicio) en
      lugar del unbind en vivo, con la verificacion de tres puntos.
- [ ] Portar la distincion modo real vs. modo pendiente de `noctaliaq-gpu.sh`.
- [ ] Evaluar el tercer modo (Ultimate, `gpu_mux_mode=0`) + `refresh-lock/`
      del repo viejo. Ojo: el valor `1` para volver de Ultimate nunca se
      confirmo en una corrida real.
- [ ] `acpi_backlight=native` a `install.sh` (aplica a cualquier maquina con
      este arbitraje, no solo a la TUF).

---

## Añadido 2026-09-09 — el criterio de verificación era el bug

Sesión abierta por un fallo aparente del wizard: se pulsó `1` (Híbrida) desde
Integrada y el script reportó

```
[x] Write aceptado y el nodo lee '0', pero pending_reboot sigue en 0.
[i] El firmware no encolo el cambio. Reiniciar no serviria de nada.
```

El cambio **sí se había aplicado**. Tres bugs distintos, uno peligroso.

### 1. `pending_reboot` no es criterio de fallo — esta firmware nunca lo levanta

Estado inmediatamente después del supuesto fallo:

```
dgpu_disable  = 0        gpu_mux_mode = 1 (Optimus)
lspci         → 01:00.0 RTX 4050 presente
lsmod         → nvidia con 40 referencias
prime-run glxinfo → NVIDIA GeForce RTX 4050 Laptop GPU
```

`last-apply.log` cierra el caso con dos corridas del mismo día, en el sentido
contrario:

```
13:28  DUDOSO leido=1 pending=0; devolviendo a 0     ← revirtió un cambio bueno
13:31  OK dgpu_disable=1 (pending_reboot=0)          ← mismo pending=0, funcionó
```

`pending_reboot` **nunca se ha observado en 1** en esta máquina, en ninguno de
los dos sentidos, ni siquiera con cambios que se aplicaron correctamente. No es
una señal débil: es una señal inexistente.

`cmd_apply_shutdown` ya lo había descubierto el 2026-09-08 y lo documentaba en
un comentario propio — pero el hallazgo **nunca se portó a `_escribir_dgpu`**,
que es el camino interactivo. La verificación de tres puntos del encabezado
queda: código de salida + relectura + **estado real del bus PCI**.

### 2. Integrada → Híbrida se aplica en vivo, sin reinicio

El encabezado afirmaba que *todo* cambio requiere reinicio. Falso en un sentido:
escribir `dgpu_disable=0` dispara un **hotplug ACPI**, la dGPU reaparece en el
bus y udev carga los módulos sola, en la misma sesión. Verificado en el journal:

```
21:35  boot → actual=Integrada, lspci=0, modulos=no
22:06  tecla 1 → escribiendo dgpu_disable=0 (nodo lee 1)
22:08  lspci → RTX 4050 presente | lsmod → 40 refs | prime-run → 4050
```

La asimetría tiene sentido: apagar la dGPU exige que el firmware lo haga en el
arranque, antes de que exista niri; encenderla no tiene esa restricción.

`_escribir_dgpu` ahora verifica con reintentos contra `_modo_actual` (el hotplug
tarda unos segundos) y fija `APLICADO_EN_VIVO`, que `cmd_hybrid` y
`cmd_apply_now` usan para no ofrecer un reinicio innecesario.

El early return también cambió: `nodo == destino` solo prueba "ya aplicado" si
el **hardware** coincide. Tras un write rechazado el nodo conserva el valor que
no se aplicó, así que el nodo solo nunca basta.

### 3. ⚠️ Grave: `_modulos_cargados` daba falso negativo por SIGPIPE

`status` reportaba `Modulos NVIDIA: ninguno` con `nvidia` cargado y 45
referencias. Reproducido en limpio:

```bash
bash -c 'set -uo pipefail; lsmod | grep -q "^nvidia_drm "; echo "rc=$?"'  # rc=141
bash -c 'lsmod | grep -q "^nvidia_drm "; echo "rc=$?"'                    # rc=0
```

Con `set -o pipefail`, `grep -q` cierra la tubería al primer match y `lsmod`
muere con SIGPIPE (141), que `pipefail` propaga como fallo de la función.

**Por qué es grave:** `_modulos_cargados` es la precondición que impide escribir
`dgpu_disable=1` con la sesión gráfica viva. Con el falso negativo el write
llega al firmware, responde `-EIO`, y se cae justo en el escenario del nodo que
miente — sin ningún guardrail restante. Es exactamente contra lo que se escribió
esa precondición.

Es el mismo bug ya corregido en `nvidia-smi | awk` el 2026-09-08. Volvió a
aparecer en otra función.

**Fix:** leer `/proc/modules` directamente, sin tubería (mismo dato que lee
`lsmod`, sin proceso intermedio).

**Barrido del resto del módulo.** Dos supervivientes más del mismo patrón:

- `_modo_actual`: `lspci | grep -qi nvidia`. Hoy no rompe porque el rc que manda
  es el del `grep`, pero es la rama de fallback que decide el modo cuando
  `/proc/driver/nvidia/gpus` no existe — justo el caso Integrada→Híbrida recién
  aplicada. Frágil por accidente, no por diseño. Materializa `lspci` y usa `case`.
- `test-gpu-apply.sh` (dos sitios): ahí el rc del `grep` **sí** decide si el test
  pasa. Cambiado a `grep -i ... >/dev/null`, que consume la entrada en vez de
  cortarla.

**Regla:** `cmd | grep -q` es incompatible con `pipefail`. Usar `>/dev/null`, o
leer el archivo directamente cuando exista.

### Decisión: no unificar `cmd_apply_shutdown` con `_escribir_dgpu`

Con `pending_reboot` fuera del criterio, los dos convergieron: ya no hay
divergencia de comportamiento, solo duplicación. Unificar tiene coste real —
`_escribir_dgpu` escribe con `sudo tee`, y el camino de apagado corre como root
desde `ExecStop`, sin tty y con el sistema bajando. Meter `sudo` ahí introduce
una dependencia nueva en la ruta más difícil de probar del módulo, ya validada
en vivo. Queda un comentario en el código para que no se "arregle" después.

### Commits

- `b674deb` — pending_reboot informativo + detección de hotplug en vivo
- `5f2eef8` — eliminado `cmd | grep -q` del resto del módulo

### Nota sobre este documento

La sección *"Cerrado 2026-09-09 — modo integrado validado"* aparece **duplicada
casi entera** más arriba (dos veces la medición de 3.8 W, el gotcha del nodo que
miente y el procedimiento validado). No se edita en sitio por la convención
append-only del repo; queda anotado para quien lo consolide.

### Pendientes

- [ ] Probar `cmd_hybrid` desde Integrada real con el parche puesto: debe
      reportar "activo ahora" y no ofrecer reinicio. El early return nuevo
      tampoco se ha ejercitado (`cmd_hybrid` corta antes con su propio chequeo).
- [ ] `_escribir_dgpu` sigue sin verificar el bus cuando el destino es
      Integrada — ahí el cambio no es en vivo, así que `APLICADO_EN_VIVO=no` es
      correcto, pero el bucle de 10 s se gasta para nada. Cortar temprano si
      `destino=1`.
- [ ] Heredados: `acpi_backlight=native` a `install.sh`; evaluar el tercer modo
      (Ultimate, `gpu_mux_mode=0`).
