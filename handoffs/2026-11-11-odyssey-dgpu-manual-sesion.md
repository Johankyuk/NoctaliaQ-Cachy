# Handoff — dGPU manual en Odyssey: alcance del paquete, hwprobe/wizard y acoplamiento con Cachy

**Fecha:** 2026-11-11
**Repo:** `Johankyuk/NoctaliaQ-Cachy`, rama `main`
**Commits de la sesión:** `743052d` (hwprobe), `936b667` (wizard), `06942ab` (handoff 2026-11-07: sección 10), más los de esta nota. No se hizo push en la sesión; `git status -sb` dice si ya se subieron.
**Continúa:** [2026-11-07-odyssey-port-generico.md](2026-11-07-odyssey-port-generico.md); su sección 10 es el detalle del alcance.
**Para quién:** tres lectores. Con contexto de Odyssey: secciones 1, 3, 4 y 6. Con contexto de CachyOS o de este repo: 3 a 5 y 7. Sin contexto de ninguno: todo, empezando por 2 y 8. Lo marcado como **no verificado** es hipótesis o lo dijo Kyu; no se comprobó.

---

## 1. Resumen (para pasar tal cual al agente de Odyssey)

1. En Odyssey la dGPU es manual: sin servicio de arranque, sin apagado automático y sin regla polkit; el usuario ejecuta `noctaliaq-dgpu on|off|status` (o el comando de 10.1) a mano.
2. El paquete es `noctaliaq-dgpu`, `noctaliaq-hwprobe`, el sondeo del wizard y una nota corta; todo lo demás (servicio de arranque, `noctaliaq-gpu-prime`, polkit, `ExecStop`, Noctalia, gaming-mode, teclado) queda fuera.
3. `noctaliaq-hwprobe --report` y el wizard (solo lectura, en inglés) avisan "NVIDIA oculta por firmware" y muestran el comando de encendido; ese comando y el atributo `asus-nb-wmi/dgpu_disable` **no están verificados** en el kernel 6.x de Odyssey (podría ser el de `asus-armoury`).
4. De la sección 6 del handoff 2026-11-07 siguen vigentes las preguntas 3, 4, 5, 7 y 8; pide a Kyu la salida de `noctaliaq-hwprobe --report` ejecutado en Odyssey.
5. Si la dGPU queda encendida al apagar, Cachy puede fallar en el siguiente arranque; por decisión de Kyu no es asunto del paquete y no hay que automatizar nada por eso. Este repo no se toca desde Odyssey.

## 2. Contexto mínimo

- **Qué es el repo:** dotfiles y scripts de Kyu para CachyOS (niri + Noctalia). Incluye `noctaliaq-dgpu`, que enciende y apaga la GPU dedicada (dGPU) de un portátil híbrido para ahorrar batería. El objetivo es llevar eso a Odyssey (Void Linux, runit), la distro de comunidad a la que Kyu quiere contribuir.
- **`dgpu_disable`:** atributo de firmware (ASUS) que apaga la dGPU. `1` = apagada y fuera del bus PCI; `0` = encendida. El valor sobrevive a reinicios y a cambios de distro.
- **Apagar** (`noctaliaq-dgpu off`) = comprobar que nadie usa la dGPU, quitarla del bus PCI y escribir `dgpu_disable=1`. **Encender** = escribir 0, rescan del bus PCI y cargar `nvidia_drm`. **Manual** = alguien ejecuta eso a mano; ningún servicio, hook ni regla polkit lo hace por él.
- **Equipos:** referencia ASUS TUF Gaming A16 FA607NUG con CachyOS (kernel 7.3.1, systemd); destino Odyssey (kernel 6.x según Kyu, no verificado). No hay otro portátil de prueba: se espera que ambas distros convivan en la misma máquina.
- **Cómo trabaja Kyu:** sección 8 del handoff 2026-11-07 (bloques copy-paste, diagnóstico antes de parchar, español neutro).

## 3. Decisiones

- **Kyu, 2026-11-10: la dGPU en Odyssey es solo manual.** Motivo: en CachyOS el `ExecStop` de `noctaliaq-dgpu-boot.service` fuerza `dgpu_disable=1` en cada apagado, y otra distro instalada o arrancada después no ve la NVIDIA ni carga el driver sin piezas extra.
- **Dentro del paquete:** `noctaliaq-dgpu` (`on`, `off`, `status` manuales), `noctaliaq-hwprobe`, el wizard (aquí: el sondeo `--probe` de `gaming-mode/install-gaming-mode.sh`) y una nota corta.
- **Fuera del paquete:** `noctaliaq-dgpu-boot.service`, `noctaliaq-gpu-prime` (disparo por AC), la regla polkit, cualquier `ExecStop`, y todo lo de Noctalia, gaming-mode (salvo el sondeo del wizard) y teclado.
- **Kyu, 2026-11-11: "Odyssey deja la dGPU encendida y luego arranca Cachy" no se prueba ni se resuelve en el paquete.** Lo considera responsabilidad de quien enciende la dGPU a mano. Queda como advertencia en la sección 10.3 del handoff 2026-11-07; el mecanismo, en la sección 5 de esta nota.

## 4. Qué se hizo

| Commit | Archivo | Cambio |
|---|---|---|
| `743052d` | `bin/noctaliaq-hwprobe` | Reescrito en inglés. Sección nueva "dGPU state"; opción `--report` (esa sección va primero, para pegarla en un reporte); `-h/--help`; una opción desconocida muestra el uso y sale con 2; `NOCTALIAQ_SYSFS` reemplaza `/sys` (misma convención que `noctaliaq-dgpu`; sirve para probar con un árbol falso). Sigue siendo solo lectura. |
| `936b667` | `gaming-mode/install-gaming-mode.sh` | `probe()` (la usan `--probe` y el inicio de la instalación completa) imprime el mismo estado y aviso. Solo el bloque nuevo está en inglés; el resto del wizard sigue en español. |
| `06942ab` | `handoffs/2026-11-07-odyssey-port-generico.md` | Aviso de actualización en la cabecera, orden de trabajo de la sección 9 reescrito y sección 10 nueva (default manual, alcance, encendido, detección, acoplamiento). |
| los de esta nota | ese handoff y `handoffs/README.md` | 10.3 reducida a advertencia; esta nota y su fila en el índice. |

**Qué informan hwprobe y el wizard:** `dgpu_disable` (lee `asus-nb-wmi` primero y el `current_value` de `asus-armoury` después; `n/a` si no hay ninguno), cuál atributo usó, `nvidia_visible`, `nvidia_driver_loaded` (existe `/sys/module/nvidia` o `/sys/module/nouveau`) y `nvidia_hidden_by_firmware`. "Oculta por firmware" = ningún dispositivo NVIDIA de clase 0x03xx en el bus PCI (equivale a `lspci` sin NVIDIA, leído de sysfs) y `dgpu_disable=1`. En ese caso avisan de que la dGPU está apagada por firmware y muestran el comando manual, marcado como no verificado en el kernel de Odyssey:

~~~sh
echo 0 > /sys/devices/platform/asus-nb-wmi/dgpu_disable && sleep 1 && echo 1 > /sys/bus/pci/rescan && modprobe nvidia_drm
~~~

## 5. Hallazgos técnicos (CachyOS, un arranque medido con `dgpu_disable=1`)

- `cachyos-drm-awaiter` es un paquete, no una unidad: trae el generador de systemd `drm-module-awaiter-generator`, `drm-failure-handler` y `drm-failure-handler.service`.
- El generador corre una vez al iniciar systemd, antes que cualquier servicio. Lee `/sys/bus/pci/devices` y, por cada GPU (clase `0x030?00`, VGA/3D), decide qué módulo esperar: NVIDIA da `nvidia_drm` (o `nouveau`), AMD `amdgpu`, Intel `i915` o `xe`. Con eso escribe `drm-module-load.target`, que espera los `sys-module-<módulo>.device` correspondientes, y las reglas udev que los crean. También escribe softdeps de modprobe para que NVIDIA cargue después de la iGPU.
- `drm-module-load.target`: `Before=display-manager.service`, `getty@tty1` y `kmsconvt@tty1`; `After=plymouth-quit.service`; `JobTimeoutSec=30s`; `OnFailure=emergency.target drm-failure-handler.service`. El handler guarda un reporte en `/var/log/drm-awaiter/` y registra "Failed to load your GPU driver(s)": es la pantalla azul de la sección 4.2 del handoff 2026-11-07.
- Con la dGPU oculta, el target solo espera `amdgpu`. Con la NVIDIA visible al arrancar esperaría `sys-module-nvidia_drm.device`.
- `noctaliaq-dgpu-boot.service` (`After=systemd-modules-load.service`, `Before=display-manager.service greetd.service`) no tiene relación de orden con ese target ni con los `sys-module-*.device`.
- Tiempos medidos (µs desde el arranque del kernel): servicio 7392609 a 7447434; `sys-module-amdgpu.device` 7850467; `plymouth-quit` 8709308; `drm-module-load.target` 8710153; `sddm` 8711252.
- **No verificado (hipótesis):** con `dgpu_disable=0` hay una carrera entre `noctaliaq-dgpu-boot` (hacia los 7.4 s) y la carga de `nvidia`. Si el servicio quita la dGPU antes de que `nvidia` la enlace, el módulo falla (`NVRM: No NVIDIA GPU found`), `nvidia_drm` no carga y el target vence a los 30 s. Si ya cargó, el servicio no debería afectar al target; y si algo tiene la dGPU abierta, `off` sale con 3 y la deja encendida. No se probó: con la dGPU oculta no se puede observar, y Kyu decidió no probarlo.
- **Ojo si alguien intenta arreglarlo del lado Cachy (hipótesis):** una unidad "más temprana" no ayuda, porque el generador ya fijó lo que espera, y quitar la dGPU antes de que `nvidia` cargue es justo la ruta de fallo. Las direcciones razonables serían ordenar el `off` después de la carga de `nvidia_drm` o hacer que el generador deje de esperar NVIDIA; ninguna se evaluó.
- **Si pasa y Cachy cae en emergencia (no probado en este escenario):** consola, contraseña de root, `echo 1 > /sys/devices/platform/asus-nb-wmi/dgpu_disable` y `reboot`.
- En el equipo de referencia existen `asus-nb-wmi/dgpu_disable` (legible sin root) y `asus-armoury/attributes/dgpu_disable/` (directorio con `current_value`); su semántica no se comparó.

## 6. Si tienes contexto de Odyssey

- Este repo no se toca desde Odyssey: Kyu pasa las salidas y los cambios de ida y vuelta.
- Preguntas vigentes de la sección 6 del handoff 2026-11-07: 3 (equivalente del awaiter), 4 (driver NVIDIA y `nvidia-powerd`), 5 (si el compositor abre la dGPU; si lo hace, `off` sale con 3), 7 (atributos de firmware del kernel 6.x) y 8 (formato de contribución). La 1, la 2 y la 6 dejan de aplicar.
- Pide a Kyu, ejecutado en Odyssey: `noctaliaq-hwprobe --report`, `noctaliaq-dgpu backend` y `noctaliaq-dgpu status`. Con eso se sabe si existe `asus-nb-wmi/dgpu_disable` o solo el de `asus-armoury`, el valor actual y qué backend elige. Para confirmar el comando de 10.1: que la NVIDIA aparezca tras el rescan y cargue el driver.
- Empaqueta solo lo de la sección 3. `deploy-dgpu.sh` no sirve tal cual (instala la unidad de arranque y polkit). `noctaliaq-dgpu` llama `systemctl stop/start nvidia-powerd` con `2>/dev/null`; en runit eso no hace nada, así que si `nvidia-powerd` existe como servicio hay que usar `sv`.
- Avisa a Kyu de todo lugar donde hwprobe o `noctaliaq-dgpu` asuman systemd o ASUS.

## 7. Si tienes contexto de CachyOS (este repo)

- Nada de Cachy cambió: `noctaliaq-dgpu-boot.service`, `noctaliaq-gpu-prime`, polkit, `noctaliaq-dgpu` y gaming-mode quedan como estaban. Solo cambiaron hwprobe, el sondeo del wizard y los handoffs.
- **No cambies el `ExecStop` de `noctaliaq-dgpu-boot.service` sin hablar con Kyu:** es lo que deja `dgpu_disable=1` al apagar y, por tanto, lo que ve Odyssey al arrancar.
- No agregues al paquete de Odyssey nada de lo que está fuera (sección 3).
- Pendientes: el push de los commits (no se hizo) y, solo si Kyu lo pide, el escenario Odyssey a Cachy (sección 5, con la advertencia sobre la "unidad más temprana").
- Para probar hwprobe sin tocar el hardware: `NOCTALIAQ_SYSFS=<árbol> bash bin/noctaliaq-hwprobe --report`, con un árbol que tenga `bus/pci/devices/<dir>/{vendor,class,boot_vga}`, `devices/platform/asus-nb-wmi/dgpu_disable` y, si aplica, `module/nvidia/`.
- El wizard sigue en español salvo el bloque nuevo: traducirlo entero no se hizo ni se pidió. Fue una decisión del agente de la sesión; Kyu puede vetarla.

## 8. Si no tienes contexto de ninguno

- Lee, en este orden: la sección 2 de esta nota; las secciones 1 a 3 y 8 del handoff 2026-11-07; su sección 10.
- Es seguro (solo lectura): `bash bin/noctaliaq-hwprobe --report`, `bash gaming-mode/install-gaming-mode.sh --probe` y `cat /sys/devices/platform/asus-nb-wmi/dgpu_disable`.
- No ejecutes sin Kyu: `noctaliaq-dgpu on|off`, el comando de encendido manual, ni nada que escriba `dgpu_disable` o quite dispositivos del bus PCI. En la máquina de referencia puede dejar el arranque en la consola de emergencia. Tampoco corras el wizard sin `--probe`: instala cosas.
- No hagas push ni commits sin que Kyu lo pida. Estilo de commits: `área: descripción`, en español y sin acentos.
- Toda entrega a Kyu va como bloques copy-paste (sección 8 del handoff 2026-11-07).

## 9. Verificación

~~~sh
bash bin/noctaliaq-hwprobe --report | sed -n 1,18p
bash gaming-mode/install-gaming-mode.sh --probe | sed -n '/── GPU ──/,/── Noctalia ──/p'
~~~

Con la dGPU apagada por firmware: `nvidia_hidden_by_firmware : yes` y el aviso con el comando manual; el wizard imprime `dGPU state: dgpu_disable=1 nvidia_visible=no nvidia_driver_loaded=no`. Con la dGPU encendida: `nvidia_visible : yes`, `nvidia_hidden_by_firmware : no` y sin aviso.

## 10. Estado

**Probado:** hwprobe `--report` y wizard `--probe` en el equipo de referencia con la dGPU apagada; hwprobe contra árboles sysfs falsos (apagada, encendida con módulo, NVIDIA clase 0x030200, sin ASUS ni NVIDIA, solo `asus-armoury`, opción inválida); idempotencia del parche y `bash -n`.
**No probado:** hwprobe y wizard con la dGPU encendida en el equipo real; cualquier cosa en Odyssey; el comando de encendido manual en el kernel 6.x; el escenario Odyssey a Cachy.
**Pendiente:** push; respuestas del agente de Odyssey (sección 6); salida de hwprobe ejecutado en Odyssey.

## 11. Notas de proceso

- La instrucción original pedía reemplazar un "default propuesto" y quitar una pregunta pendiente sobre el default; el handoff 2026-11-07 no tenía ese texto. Se agregó la sección 10 y se ajustó el orden de trabajo de la sección 9, que mandaba portar el servicio de arranque y el resume a runit.
- "El wizard" se tomó como `gaming-mode/install-gaming-mode.sh` (único wizard del repo y el que el handoff 2026-11-07 llama así), aunque gaming-mode quede fuera del paquete. `--report` no existía: se agregó a hwprobe, no al wizard.
- Cada parche guardó un respaldo en `/tmp/odyssey-bak-*` (se pierde al reiniciar); el historial real está en git.
