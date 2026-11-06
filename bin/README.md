# bin/

Scripts que `install.sh` copia a `~/.local/bin`.

| Script | Qué hace |
|---|---|
| `kbd-color-sync` | Sincroniza el RGB del teclado con el accent de Noctalia. Lo dispara el hook `colors_changed`. Uso: `kbd-color-sync [--sat=MULT] [--val=FLOOR] [--raw]` |
| `mangohud-color-sync` | Sincroniza los colores de MangoHud con el accent de Noctalia. Lo dispara el mismo hook |
| `noctaliaq-gpu-prime` | Estado de PRIME offload, dGPU física y gamer mode. Usa `gpu-setup/` para encender y apagar la dGPU |
| `noctaliaq-gpu-launch` | Wrapper de `launch_apps_custom_command`: antepone las variables de PRIME offload cuando el estado es on |
| `noctaliaq-gpu-flatpak-sync` | Aplica el estado de PRIME a los flatpaks con `flatpak override`, porque no heredan variables del host |
| `noctaliaq-hwprobe` | Solo lectura: lista que mecanismos de GPU hibrida, perfiles de energia y ventiladores ofrece el equipo. Sirve en cualquier portatil. Uso: `noctaliaq-hwprobe` |
| `rotate-backups.sh` | Deja solo los N respaldos más recientes por archivo base. Uso: `rotate-backups.sh [N]` (por defecto 3) |
| `umbriel-keybinds` | Editor TUI de la sección `[keybinds]` de la config de Umbriel (`UMBRIEL_CONFIG` cambia el archivo) |
| `alienware/` | RGB para Alienware. Sin soporte, ver [../alienware-setup/README.md](../alienware-setup/README.md) |
