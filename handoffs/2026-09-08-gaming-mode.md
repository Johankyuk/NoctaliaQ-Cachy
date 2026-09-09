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
