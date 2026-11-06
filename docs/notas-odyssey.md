# Notas para migrar a Odyssey

Cosas aprendidas en CachyOS que hay que reproducir o revisar al migrar.

## Flatpaks con NVIDIA: extension GL del driver

- Sintoma: con el modo juego encendido, Sober abre y muestra "Crash: Sober couldn't find a supported graphics device".
- Causa: flatpak no tenia instalada la extension `org.freedesktop.Platform.GL.nvidia-<version>` que coincide con el driver del host (host 615.78.08). Sin ella el flatpak no puede usar la RTX.
- Solucion: `flatpak update`, con la dGPU encendida (modo juego), porque flatpak elige la extension segun el driver cargado. Instalo `GL.nvidia-615-78-08` y `VAAPI.nvidia` (instalacion system).
- Recurrencia: cada vez que se actualiza el driver NVIDIA del host, los flatpaks pierden la extension hasta repetir `flatpak update`. Por ahora queda como nota; el repo no trae hook de pacman.
- Comprobacion: con un flatpak abierto, `nvidia-smi` lista su proceso (Sober, tipo C+G, unos 441 MiB) en la RTX, y umbriel, noctalia y Zen quedan en la iGPU.
- Para Odyssey: repetir este paso despues de instalar o actualizar el driver NVIDIA, y decidir alli si se automatiza.

Verificacion rapida:

    flatpak list --runtime --columns=application,branch,installation | grep -i nvidia
    nvidia-smi | sed -n '/Processes/,$p'

## dGPU apagada por firmware y pantalla azul de drm-awaiter

- Sintoma: "Failed to load your GPU driver(s)" al arrancar (cachyos-drm-awaiter), sin acceso al escritorio.
- Causa: el arranque empezaba con la dGPU encendida tras apagar con `off` pospuesto; nvidia no la encontraba (NVRM: No NVIDIA GPU found) y el awaiter fallaba. Es una inferencia del log, confirmada porque el parche lo resolvio.
- Solucion: `noctaliaq-dgpu-boot.service` con RemainAfterExit y ExecStop, para que tambien apague la dGPU al apagar el equipo.
- Salida de emergencia: enter, contrasena de root, `noctaliaq-dgpu on` (o `/usr/local/bin/noctaliaq-dgpu on`) y `exit` solo si imprime "dGPU encendida".
- Para Odyssey: si se usa el mismo esquema de dGPU apagada, desplegar la unidad con ExecStop y revisar si ese sistema trae un awaiter equivalente.

## Consumo medido de la dGPU: ahorro vs hibrido (6 nov 2026)

- Equipo: ASUS TUF A16 FA607NUG (Ryzen 7 7445HS, RTX 4050 Max-Q), CachyOS con kernel 7.
- Metodo: `power_now` de la bateria en descarga, 30 muestras cada 2 s, brillo 200/200, perfil `power-saver` (platform `quiet`), modo juego apagado, sin tocar el equipo durante la corrida. Los logs quedaron en `~/mediciones-gpu/`, fuera del repo.
- Resultados con el mismo perfil:

| Estado | Promedio | Rango | Nota |
|---|---|---|---|
| Ahorro (`dgpu_disable=1`) | 8.97 W | 8.88 a 9.08 W | dGPU fuera del bus, muy estable |
| Hibrido sin `nvidia-powerd` | 23.05 W | 20.5 a 25.9 W | dGPU en `active` durante toda la medicion |

- Diferencia ahorro contra hibrido: unos 14 W con la dGPU despierta y sin carga. Una sola corrida por estado, bateria entre 50% y 52%.
- Una corrida de hibrido con `nvidia-powerd` activo dio 24.5 W, pero a perfil `balanced`: no es comparable con las anteriores.
- Las primeras mediciones (modo juego ON, o recien despues de `noctaliaq-power gaming off`) no sirven: tras cambiar perfil y curvas el consumo baja de unos 21 W a unos 14 W durante el primer minuto. Esperar unos 2 min antes de medir.
- Procedimiento: `noctaliaq-power gaming off`; para ahorro `sudo noctaliaq-dgpu off`, para hibrido `sudo noctaliaq-dgpu on` (con espera a que la dGPU se suspenda); cargador desconectado; mismo perfil y brillo en las dos corridas.

## dGPU en hibrido: no llega a quedar suspendida

- El driver reporta `Runtime D3 status: Enabled (fine-grained)`, `power/control=auto` y la funcion de audio 01:00.1 queda suspendida. Aun asi la dGPU (01:00.0) se mantiene en `active`.
- `nvidia-powerd` (root) mantiene abiertos `/dev/nvidia0` y `/dev/nvidiactl`. Detenerlo con `sudo systemctl stop nvidia-powerd` permite suspensiones breves, pero no basta.
- Sin `nvidia-powerd` la dGPU se suspende unos 0.85 s cada unos 25 s (`runtime_suspended_time` sube 1.7 a 2.6 s por cada 60 s) y vuelve a `active`.
- Descartado: Noctalia (pausado con SIGSTOP: 1.7 s contra 2.6 s por 60 s) y el sondeo de conectores `drm_kms_helper.poll` (con `N`: 2.4 s, con `Y`: 1.9 s). Nadie abre `card0` ni `renderD129`, que son los nodos DRM de la dGPU. No hay timers que la consulten, y `noctaliaq-power` no llama a `nvidia-smi` si la dGPU esta suspendida.
- Opciones de modulo vistas: `NVreg_PreserveVideoMemoryAllocations=1` y `NVreg_InitializeSystemMemoryAllocations=0`. No se vio `NVreg_DynamicPowerManagement` en `modprobe.d`.
- Causa encontrada con `ftrace` (eventos `rpm_resume`, `rpm_suspend` y `rpm_idle` filtrados a 01:00.0 y su bridge 00:01.1, con stack por evento, 100 s, sin `nvidia-powerd`): la despierta una notificacion ACPI de NVPCF que atiende el propio driver. Stack: `acpi_ev_notify_dispatch` > `rm_acpi_nvpcf_notify` > `os_ref_dynamic_power` > `nv_indicate_not_idle` > `__pm_runtime_resume`. No es un proceso de usuario: nadie tenia abierto `/dev/nvidia*` y los demas resumes fueron kworkers y `nv_queue` del driver.
- Ciclo medido: periodo de 23.1 s (suspending 1 s, suspended 1 s, resuming 1 s, active unos 20 s), asi que la dGPU pasa cerca del 90% del tiempo activa. Hipotesis sin probar: el firmware manda esa notificacion periodicamente (NVPCF es el canal de Dynamic Boost) y no se conoce opcion de usuario para evitarla. Log: `~/mediciones-gpu/rpm-trace-20261106-131815.txt`.
- Conclusion practica: en bateria usar ahorro (dGPU apagada); hibrido solo con el modo juego.
- En la config de Noctalia `gpu_poll_seconds = 5.0` quedo intacto: el widget de la barra no muestra stats de GPU.
- Estado al terminar las mediciones: `nvidia-powerd` detenido a mano y dGPU apagada con `sudo noctaliaq-dgpu off`. `noctaliaq-dgpu on` o el modo juego la reactivan.

## Port a Void Linux (kernel 6.x): puntos por verificar

Nada de esto esta probado en Void. Segun Kyu su kernel es 6.x, no el 7 de CachyOS. Se atacara despues; aqui queda la lista de lo que puede romperse.

- Init: Void usa runit, no systemd. Lo del repo que depende de systemd: `noctaliaq-dgpu-boot.service` (con `ExecStop`), `noctaliaq-gpu-apply.service`, `noctaliaq-gpu-mode.service`, el hook `noctaliaq-power-resume` (hook de systemd-sleep), las reglas de `logind/` del boton de apagado, SDDM o greetd y el servicio `nvidia-powerd`. Hay que decidir el equivalente en runit y elogind.
- Control de la dGPU por firmware: la cabecera de `noctaliaq-gpu-mode` usa `/sys/class/firmware-attributes/asus-armoury/attributes/dgpu_disable`, mientras que las mediciones leen `/sys/devices/platform/asus-nb-wmi/dgpu_disable`. En este equipo con kernel 7 existen las dos rutas. Verificar cual existe en el kernel de Void y adaptar el script.
- Curvas de ventilador por hwmon de `asus-nb-wmi` (`noctaliaq-power` reporta "modo 1 (curva propia)"), `platform_profile` y `powerprofilesctl`: comprobar soporte en ese kernel.
- Driver NVIDIA: version en Void, si es el modulo open o el propietario, D3 fine-grained y `nvidia-powerd`. La extension GL de flatpak debe coincidir con la version del host (ver la primera seccion).
- Paquetes: `install.sh` instala con el gestor de CachyOS. En Void es `xbps`. Comprobar que Umbriel y Noctalia v5 existan como paquete o haya que compilarlos.
- Repetir en Void el procedimiento de medicion de arriba para comparar con estas cifras.
