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
