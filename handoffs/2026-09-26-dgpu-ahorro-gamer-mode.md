# dGPU en ahorro al arrancar + encendido en caliente + gamer mode con AC

**Fecha:** 2026-09-26
**Máquina:** TUF (RTX 4050, asus-nb-wmi). Alienware: sin cambios de hardware (helper sale con 2).

## Comportamiento final

- Al encender: dGPU **físicamente apagada** (`dgpu_disable=1`, fuera del bus PCI), aunque esté conectada.
- Conectar AC → dGPU on + offload on + gamer mode on. Desconectar → todo off.
- `Mod+Alt+G` → toggle manual. Gamer mode solo si hay AC. El toggle se respeta hasta el próximo conectar/desconectar real.
- Si algo usa la dGPU al apagar, offload queda off y el apagado se reintenta cada 30s (máx 1h).

## Piezas

| Archivo | Rol |
|---|---|
| `bin/noctaliaq-gpu-prime` | Estado + filtro de eventos por `last-ac` + gamer mode vía `noctalia msg plugin` |
| `gpu-setup/noctaliaq-dgpu` | Helper root on/off/status (remove PCI + `dgpu_disable`, rescan, nvidia-powerd) |
| `gpu-setup/org.noctaliaq.dgpu.policy` + `49-noctaliaq-dgpu.rules` | pkexec sin prompt: wheel + local + active, `exec.path` fijo |
| `gpu-setup/noctaliaq-dgpu-boot.service` | Sistema, antes de greetd: `noctaliaq-dgpu off` |
| `config/systemd-user/noctaliaq-gpu-boot.service` | Sesión: estado off, gamer off, registra AC |
| `config/niri/cfg/misc.kdl` | `ignore-drm-device` sobre la dGPU (by-path) |
| `config/applications/zen.desktop` + keybind `Mod+B` | Zen con `__EGL_VENDOR_LIBRARY_FILENAMES` = Mesa |

## Por qué RTD3 no bastó (opción descartada)

Con dGPU presente, `runtime_status` nunca llegaba a `suspended` bajo niri (97% activa aun sin holders). Se fueron quitando retenedores:

1. niri abría la dGPU → `ignore-drm-device`.
2. Zen `RDD Process` → libglvnd enumera el EGL de NVIDIA; `libva-nvidia-driver` desinstalado + EGL Mesa para Zen.
3. noctalia (NVML) → `gpu_poll_seconds = 0` en config **y** en state (el state pisa la base).

Aun así seguía despierta. Se optó por apagado físico. supergfxctl descartado: exige logout por cada cambio y no detecta la sesión de greetd (`manager is an invalid variant`).

## Gotchas

- `dgpu_disable` persiste en firmware entre reinicios; ya estaba en 1 al inicio de la sesión y parecía "dGPU dormida".
- Leer `/proc/driver/nvidia/gpus/*/power` **despierta** la GPU. Medir con `runtime_active_time`/`runtime_suspended_time` en sysfs.
- Los números `cardN`/`renderD12X` cambian entre arranques: usar siempre `/dev/dri/by-path/`.
- pkexec no funciona desde el systemd de usuario (fuera de la sesión logind): el apagado al arrancar va en un servicio de **sistema**.
- `nvidia-powerd` quedó deshabilitado al arranque; el helper lo arranca/para con la dGPU.
- Gamer mode: `targets` **reemplaza** la lista integrada. Se generó desde `buildDefaults()` sin `system-*` (173 → 103) para evitar el prompt de `pkexec systemctl`.

## Costos aceptados

- Sin métricas de GPU en la barra (`gpu_poll_seconds = 0`).
- Monitor externo por HDMI probablemente no funcione (niri ignora la dGPU). No probado.

## Pendientes

- [ ] `targets` del gamer mode vive solo en `settings.toml` (local). Decidir si se versiona.
- [ ] Alienware: `ignore-drm-device` apunta a `pci-0000:01:00.0`; verificar que no rompa su salida externa antes de `git pull`.
- [ ] Probar el apagado diferido (juego abierto al desconectar).
- [ ] Heredado: suspend/resume como vía del race de DRM; ahora también verificar que la dGPU siga apagada tras resume.
