# Handoff — Port a Odyssey (Void/runit): control genérico de dGPU híbrida

**Fecha:** 2026-11-07
**Repo:** `Johankyuk/NoctaliaQ-Cachy`, rama `main`
**Último commit al escribir esto:** `77025d6`
**Para quién:** un agente con contexto de Odyssey (Void Linux, runit). Este documento no asume nada de la conversación que lo generó. Lo marcado como **no verificado** lo dijo Kyu o es una hipótesis, no se comprobó en esa sesión.

---

## 1. Qué se busca

Kyu quiere que **cualquier portátil con GPU híbrida** (iGPU + dGPU dedicada) se use bien, no solo su ASUS. Hoy todo funciona en su equipo con CachyOS; la idea es extrapolarlo.

- CachyOS queda como **respaldo pulido**. Kyu arrancará Odyssey cuando lo necesite para seguir desarrollando ahí los scripts que falten.
- No tiene otro portátil para probar por ahora. Todo lo probado es en una sola máquina.
- Quiere contribuir a Odyssey. Un diseño genérico y documentado le sirve más a la distro que scripts atados a ASUS.

Modos objetivo (palabras de Kyu):

| Modo | dGPU | Consumo buscado |
|---|---|---|
| Ahorro | apagada | unos 8 W |
| Gaming ligero | encendida | unos 20 W |
| Conectado a corriente | lo que pida el equipo | sin tope |

En CachyOS el modo gaming mantiene la capa NVIDIA activa para todo lo que se lanza. **No verificado:** según Kyu, en Odyssey solo se puede lanzar una aplicación con NVIDIA a la vez, eligiendo la app y lanzándola, es decir offload por aplicación y no un estado global.

## 2. Equipo de referencia (donde se probó todo)

- ASUS TUF Gaming A16 FA607NUG: iGPU AMD `0000:65:00.0` (amdgpu, `boot_vga=1`), dGPU NVIDIA RTX 4050 Laptop `0000:01:00.0` (audio HDMI `01:00.1`, bridge `0000:00:01.1`).
- CachyOS, kernel 7.3.1, systemd, driver NVIDIA 615.78.08, Umbriel + Noctalia v5, polkit, power-profiles-daemon, flatpak.
- Handlers de `platform_profile`: `amd-pmf` y `asus-wmi`. Opciones `quiet balanced performance`.
- Destino: Odyssey (Void, runit). Kyu dice kernel 6.x. **No verificado:** versión de driver NVIDIA, módulo open o propietario, init de sesión (elogind/seatd) y greeter en Odyssey.

## 3. Piezas del repo y su acoplamiento

| Pieza | Qué hace | ASUS | systemd |
|---|---|---|---|
| `gpu-setup/noctaliaq-dgpu` | `on`, `off`, `status`, `backend` de la dGPU. Salidas: 0 ok, 1 fallo, 2 sin backend, 3 en uso | solo el backend `firmware-asus` | llama a `systemctl` y `logger` |
| `gpu-setup/deploy-dgpu.sh` | instala el script, polkit y la unidad de arranque; sale sin instalar si el backend es `none` | no | `daemon-reload`, `enable`, `disable`: **falla en runit tal cual** |
| `gpu-setup/noctaliaq-dgpu-boot.service` | apaga la dGPU al arrancar y otra vez al apagar | no | sí, ver sección 5 |
| `org.noctaliaq.dgpu.policy` y `49-noctaliaq-dgpu.rules` | `pkexec` sin contraseña para `wheel` con sesión local activa | no | depende de polkit y de logind/elogind |
| `bin/noctaliaq-gpu-prime` | dueño del estado de PRIME y de la dGPU física (vía `pkexec noctaliaq-dgpu`); verbos de modo gaming | no | no |
| `bin/noctaliaq-gpu-launch` | wrapper de `launch_apps_custom_command` de Noctalia: antepone las variables de PRIME offload si el estado es on | no | no |
| `bin/noctaliaq-gpu-flatpak-sync` | mantiene los flatpaks alineados con el estado de PRIME (ver el script) | no | no |
| `gaming-mode/bin/noctaliaq-power` | `apply`: perfil PPD, runtime PM NVIDIA por perfil, límites `-pl`/`-lgc` opcionales, curvas de ventilador, lectura de TGP | curvas de ventilador (opcionales, se omiten sin hwmon) | no |
| `gaming-mode/bin/noctaliaq-gpu-mode` | modo de GPU por firmware con atributos de `asus-armoury` (`pending_reboot`), persistente | sí | `noctaliaq-gpu-mode.service` |
| `gaming-mode/install-gaming-mode.sh` | wizard: binarios en `/usr/local/bin`, udev, polkit, unidades, hook de Noctalia. `--probe` solo lee | solo avisa sin `asus-nb-wmi` | `systemctl`, `udevadm` |
| `gaming-mode/system/60-noctaliaq-hwaccess.rules` y `noctaliaq-power-resume` | permisos del hwmon de curvas ASUS y reaplicar al despertar | sí, existen por las curvas | hook de `systemd-sleep` |
| `bin/kbd-color-sync` | RGB del teclado por `asus::kbd_backlight` | sí | no |
| `bin/noctaliaq-hwprobe` | sondeo de solo lectura: GPUs PCI, backends posibles, NVIDIA, perfiles, hwmon, batería | detecta, no depende | no |
| `docs/notas-odyssey.md` | lo aprendido y puntos por verificar en Void | | |

`noctaliaq-dgpu` elige backend en este orden y se puede forzar con `BACKEND=firmware-asus|runtime-pm|none` en `/etc/noctaliaq/dgpu.conf`:

1. `firmware-asus`: `dgpu_disable` de `asus-nb-wmi`. `off` verifica que nadie use la dGPU (`/dev/nvidia*`, `/dev/dri/by-path/pci-<addr>-*`), la quita del bus PCI y escribe `dgpu_disable=1`. `on` escribe 0, hace rescan, carga `nvidia_drm` y arranca `nvidia-powerd`.
2. `runtime-pm`: genérico. No corta la dGPU: deja `power/control=auto` en la GPU y sus funciones hermanas y detiene `nvidia-powerd`. Mejor esfuerzo.
3. `none`: sale con 2 y el llamador sigue solo con estado.

## 4. Hallazgos que condicionan el diseño

**4.1 El híbrido en reposo cuesta ~14 W por el NVPCF (ASUS, kernel 7).** Medición en batería, perfil `power-saver`, brillo 200/200, una corrida por estado: ahorro (`dgpu_disable=1`) 8.97 W, híbrido sin `nvidia-powerd` 23.05 W (rango 20.5 a 25.9 W). Con `ftrace` (eventos `rpm_resume`, `rpm_suspend`, `rpm_idle` filtrados a la dGPU y su bridge, con stack) la causa es una notificación ACPI de NVPCF (`NVDA0820:00`) que atiende el propio driver: `acpi_ev_notify_dispatch` > `rm_acpi_nvpcf_notify` > `os_ref_dynamic_power` > `nv_indicate_not_idle` > `__pm_runtime_resume`. Periodo de 23.1 s: ~20 s en `active`, 1 s `suspending`, 1 s `suspended`, 1 s `resuming`. Nadie tiene `/dev/nvidia*` abierto. Se repitió igual en corriente y con modo gaming activo.
- Hipótesis sin probar: el firmware manda esa notificación periódicamente y no hay opción de usuario para evitarla.
- En equipos **sin** `NVDA0820` el runtime PM podría bastar para suspender la dGPU del todo. **No verificado en ningún otro equipo.** El sondeo imprime `ACPI NVDA*` para detectarlo.
- Runtime PM en este equipo: `Runtime D3 status: Enabled (fine-grained)`, `power/control=auto`, `d3cold_allowed=1`.

**4.2 Pantalla azul al arrancar.** "Failed to load your GPU driver(s)" de `cachyos-drm-awaiter` cuando el arranque empezaba con la dGPU encendida tras un `off` pospuesto (NVRM: No NVIDIA GPU found). Se resolvió con `noctaliaq-dgpu-boot.service` con `RemainAfterExit` y `ExecStop`. La causa es una inferencia del log confirmada porque el parche la resolvió. Revisar si Odyssey trae un awaiter equivalente. Salida de emergencia: consola, contraseña de root, `noctaliaq-dgpu on`.

**4.3 Apagar la dGPU exige que nadie la use.** El script original asume un compositor con `ignore-drm-device` sobre la dGPU (documentado para niri); si el compositor la abre, `off` siempre sale con 3. **No verificado** si Umbriel en Odyssey la abre.

**4.4 Flatpaks con NVIDIA.** Necesitan la extensión `org.freedesktop.Platform.GL.nvidia-<versión del driver del host>` (más `VAAPI.nvidia`). Se instala con `flatpak update` con la dGPU encendida y hay que repetirlo cada vez que cambia el driver. No hay hook automático.

**4.5 Capas de config de Noctalia v5.** Archivo base (`config.toml` o `noctalia-full-config.toml` en `~/.config/noctalia/`), overlay `zz-noctaliaq.toml` (los hooks de `noctaliaq-power` viven aquí) y estado de runtime en `~/.local/state/noctalia/settings.toml`. Los plugins se gestionan en la instancia en marcha con `noctalia msg plugins list|enable|disable`. Descartados por Kyu: `lyrics` (no le gusta), `asus-fan` y `asus-gpu-mode` (`noctaliaq-power` y `noctaliaq-dgpu` ya cubren esas funciones).

**4.6 Ruta de `dgpu_disable`.** `noctaliaq-dgpu` usa `/sys/devices/platform/asus-nb-wmi/dgpu_disable`; `noctaliaq-gpu-mode` usa `/sys/class/firmware-attributes/asus-armoury/attributes/dgpu_disable/current_value`. En el equipo de referencia con kernel 7 existen las dos. **No verificado** cuál existe con el kernel 6.x de Odyssey.

## 5. Dependencias de systemd o Arch y qué falta en runit

Las hipótesis de la columna derecha no se comprobaron contra la documentación de Void ni de Odyssey. Decide el agente.

| Hoy en CachyOS | Qué necesita en Odyssey |
|---|---|
| `noctaliaq-dgpu-boot.service`: oneshot, `After=systemd-modules-load.service`, `Before=display-manager.service greetd.service`, `ExecStart=noctaliaq-dgpu off`, `RemainAfterExit=yes`, `ExecStop=-noctaliaq-dgpu off`, `TimeoutStopSec=20` | Ejecutar `noctaliaq-dgpu off` con los módulos de GPU ya cargados y **antes** del greeter, y otra vez al apagar. Hipótesis: `/etc/rc.local` y `/etc/rc.shutdown`, o un script de core-services |
| `noctaliaq-power-resume` (hook de `systemd-sleep`, `post`: reaplica `noctaliaq-power apply`) | Un gancho de resume. Hipótesis: `zzz.d` o el de elogind |
| `noctaliaq-gpu-apply.service` | No se revisó en esta sesión |
| `noctaliaq-gpu-mode.service` (`ConditionPathExists=/etc/noctaliaq/gpu-mode`, `boot-apply`) | Solo aplica a ASUS con armoury; decidir si se porta |
| `noctaliaq-dgpu` llama a `systemctl stop/start nvidia-powerd` | En runit habría que usar `sv`, si `nvidia-powerd` existe como paquete. Con `2>/dev/null` hoy falla en silencio y no maneja el daemon |
| `deploy-dgpu.sh` usa `systemctl daemon-reload`, `enable`, `disable` | Reescribir el despliegue para runit (por ejemplo `/etc/sv/<nombre>` y enlace en `/var/service`) o una rama por init |
| `install.sh` usa `pacman`, `paru` | `xbps` |
| Reglas polkit con `subject.local && subject.active` | Depende de que elogind/logind mantenga sesión activa |
| `power-profiles-daemon` y D-Bus | Servicio runit del daemon y comprobar `powerprofilesctl` |

## 6. Preguntas para el agente de Odyssey

1. ¿Cómo engancha Odyssey tareas de arranque y de apagado (core-services, `rc.local`, `rc.shutdown`, servicios `runsv`)? ¿Cuál es la convención de la distro?
2. ¿Qué gestor de sesión usa (elogind o seatd) y qué greeter? ¿Las reglas polkit por `subject.active` funcionan igual?
3. ¿Hay un equivalente del `cachyos-drm-awaiter` que falle si la dGPU aparece o desaparece al arrancar?
4. ¿Qué driver NVIDIA ofrece Odyssey (módulo open o propietario, versión) y está `nvidia-powerd` como paquete con servicio?
5. ¿Qué compositor lanza Odyssey y abre o no la dGPU? ¿Existe `ignore-drm-device` o equivalente?
6. ¿Cómo manejan resume y suspensión (elogind, `zzz`) y dónde van los ganchos?
7. ¿Qué atributos de firmware expone el kernel 6.x en el equipo de Kyu (`asus-nb-wmi/dgpu_disable`, `asus-armoury`)?
8. ¿Prefiere Odyssey incluir esto como paquete genérico con backends declarados, y qué formato espera una contribución?

## 7. Cómo verificar en cualquier equipo

```sh
noctaliaq-hwprobe                   # solo lectura
noctaliaq-dgpu backend              # backend elegido
noctaliaq-dgpu status               # on u off
```

Seguimiento de despertares de la dGPU (como root; adaptar la dirección PCI y la del bridge):

```sh
T=/sys/kernel/tracing
for e in rpm_resume rpm_suspend rpm_idle; do
  echo 'name == "0000:01:00.0" || name == "0000:00:01.1"' > $T/events/rpm/$e/filter
  echo 1 > $T/events/rpm/$e/enable
done
echo 1 > $T/options/stacktrace; echo 1 > $T/tracing_on
sleep 100; echo 0 > $T/tracing_on; cat $T/trace
```

El sondeo en el equipo de referencia con la dGPU apagada: solo aparece la iGPU y `ACPI NVDA*: NVDA0820:00`. Con la dGPU encendida: `0000:01:00.0 vendor=0x10de driver=nvidia boot_vga=0 control=auto runtime=active d3cold=1` y `Runtime D3 status: Enabled (fine-grained)`. Los reportes completos y los logs de medición están en `~/mediciones-gpu/` de Kyu en CachyOS y **no están versionados**: pedírselos si hacen falta.

## 8. Cómo trabaja Kyu

- Todo en **bloques copy-paste** que se ejecutan tal cual: nada de editar archivos a mano ni navegar menús. Idempotentes, con respaldo previo, con `assert` o verificación que aborte claro y restaure si algo falla, y terminando con `echo "✓ terminado"`.
- Un bloque por mensaje cuando se pueda. Diagnóstico de solo lectura antes de parchar. Lo crítico o lo que debe decidir él va al final y en negrita. Si una opción es claramente mejor, se toma y se declara en una línea.
- Español neutro, sin emojis, sin relleno. Honestidad sobre lo que no se probó.
- En bloques que pega en zsh, evitar el signo de exclamación por la expansión de historial: para un shebang usar `printf '\043\041/usr/bin/env bash\n'`. `ls` está aliasado a `eza --icons`: usar `command ls` o `find`.
- Antes de desplegar algo que corre al arrancar (como el servicio de la dGPU), probar el ciclo real y dejar rollback.

## 9. Estado y límites

**Probado en el equipo de referencia:** corrección de la pantalla azul, ciclo real `off`/`on` del script nuevo con el backend firmware (`fa59006`), backend `runtime-pm` forzado durante 70 s (`power/control=auto`, ciclo de 23 s), sondeo con la dGPU apagada y encendida, mediciones de consumo, causa del despertar por `ftrace`.

**No probado:** cualquier cosa en Void o runit, el backend `runtime-pm` elegido automáticamente en un equipo no ASUS, `deploy-dgpu.sh` genérico fuera de ASUS, el instalador del gaming-mode sin `asus-nb-wmi`, y el comportamiento de `noctaliaq-dgpu-boot` en un equipo no ASUS (llamaría a `off` con `runtime-pm`).

**Commits de esta línea de trabajo:** `a4bf1e6`, `03c4822`, `dd07bc2` (sesión del 5-6 nov: pantalla azul, notas y README), `d32768f`, `eebb188`, `7c0a525`, `eb077f8`, `d5a7034` (`noctaliaq-hwprobe`), `fa59006` (`noctaliaq-dgpu` con backends y despliegue genérico), `ed83784`, `ae325b8`, `77025d6`.

**Orden de trabajo sugerido:**

1. Responder la sección 6 con lo que sepa Odyssey.
2. Portar el servicio de arranque de la dGPU a runit y probar el ciclo real con salida de emergencia a mano.
3. Adaptar `deploy-dgpu.sh` e `install.sh` (init y paquetes).
4. Gancho de resume equivalente.
5. Repetir el procedimiento de medición de `docs/notas-odyssey.md` en Odyssey para comparar con 8.97 W y 23.05 W.
