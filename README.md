# NoctaliaQ-Cachy

Setup personal de Noctalia v5 sobre Umbriel en CachyOS, para un portátil ASUS TUF con GPU NVIDIA.
Es sobre todo un recordatorio de cómo quedó el sistema, organizado por módulos para poder
revisar cada parte por separado.

## Requisitos

- CachyOS con niri ya instalado. niri solo sirve de base: Umbriel todavía no es opción en el
  instalador de CachyOS.
- Portátil ASUS con dGPU NVIDIA. `install.sh` solo cubre este equipo.

No hace falta nada más: `install.sh` instala el resto.

## Instalación

El repo es público, clonar por HTTPS no requiere configurar nada:

```bash
git clone https://github.com/Johankyuk/NoctaliaQ-Cachy.git ~/NoctaliaQ-Cachy && \
cd ~/NoctaliaQ-Cachy && \
./install.sh
```

`install.sh` es idempotente: lo que ya está instalado o configurado se omite. Todo archivo que
reemplaza se respalda como `archivo.bak.<timestamp>`. Al terminar, cierra sesión y elige Umbriel
en SDDM.

El detalle de cada sección (placeholders de rutas, completions, keyd, etc.) está en
[docs/instalacion-detalle.md](docs/instalacion-detalle.md).

## Mapa del repo

| Ruta | Qué es | Estado |
|---|---|---|
| [`install.sh`](install.sh) | Instalador principal, por secciones | Vigente |
| [`config/`](config/README.md) | Dotfiles: Noctalia, Umbriel, foot, zsh, MangoHud, launcher | Vigente (`config/niri` es legado) |
| [`bin/`](bin/README.md) | Scripts que se despliegan a `~/.local/bin` | Vigente |
| [`gpu-setup/`](gpu-setup/README.md) | Control físico de la dGPU ASUS (la llama `install.sh`) | Vigente |
| [`gaming-mode/`](gaming-mode/README.md) | Modo juego: perfiles de energía, dGPU y PRIME | Opcional, con wizard propio |
| `logind/` | Botón de apagado: pulsación corta bloquea y suspende, larga apaga | Vigente |
| `assets/` | Imagen de perfil y wallpaper | Vigente |
| [`greeter-setup/`](greeter-setup/README.md) | SDDM a greetd + noctalia-greeter | Manual, sin uso hoy |
| [`alienware-setup/`](alienware-setup/README.md) | RGB para un Alienware | Sin soporte |
| [`handoffs/`](handoffs/README.md) | Notas de sesiones de trabajo | Historial |

## Qué hace install.sh

En este orden: RGB (Alienware), tema de cursor, config de Noctalia, MangoHud (paquete y config),
MangoHud en flatpaks, PRIME offload en flatpaks, Nautilus con iconos Papirus, niri cfg, zsh
(paquetes, config y p10k), completions de zsh para noctalia, foot, niri config.kdl, Zen Browser,
Umbriel (compositor principal), Umbriel como entorno principal, botón de apagado, apps de
terminal (cava, cmatrix, playerctl) y scripts a `~/.local/bin`.

## Stack actual

- Sesión: Umbriel, con SDDM como display manager.
- Shell: Noctalia v5. La barra incluye visualizador de audio y el plugin lyrics.
- Terminal foot, archivos Nautilus con Papirus, navegador Zen, cursor `capitaine-cursors`.
- Gráficos: PRIME offload; el modo juego enciende la dGPU y PRIME para apps nativas y flatpaks.
- Apps de terminal en el launcher: cava, cmatrix y lavat.

## Notas y pendientes

- Falta agregar el greeter de Noctalia. Hoy se usa SDDM; `greeter-setup/` es manual y no está en uso.
- `config/niri` es legado: niri solo es la base de CachyOS.
- Lo de Alienware fue una adaptación para un compañero y no tiene soporte.
