# NoctaliaQ-Cachy

Setup completo de Noctalia v5 + niri en CachyOS (KyuCachy). Config, scripts de GPU PRIME,
color-sync de teclado/MangoHud, cursor Bibata y overrides de MangoHud para flatpaks.

## Instalación

```bash
git clone git@github.com:Johankyuk/NoctaliaQ-Cachy.git && cd NoctaliaQ-Cachy && ./install.sh
```

## Contenido
- `config/noctalia/config.toml` — config completa de Noctalia (bar, dock, hooks, tema).
- `config/MangoHud/MangoHud.conf`
- `config/alacritty/` — alacritty.toml + tema dinámico Noctalia.
- `config/niri/cfg/` — todos los `.kdl`.
- `config/noctalia/kbd-color-sync.toml` — config confirmada (sat=1.6 val=0.85).
- `bin/` — kbd-color-sync, mangohud-color-sync, noctaliaq-gpu-prime, noctaliaq-gpu-launch,
  noctaliaq-gpu-flatpak-sync.
- `icons/Bibata-Modern-Classic` — cursor vendorizado (tamaño 32).

## Pendientes

- **SDDM → greetd (Noctalia greeter):** reemplazar el display manager actual por greetd
  usando el greeter propio de Noctalia.
- **Gestor de archivos con sync de tema:** agregar uno que permita sincronizar su paleta
  con el color-sync existente (mismo patrón que kbd-color-sync/mangohud-color-sync).
- **Terminal:** evaluar alternativas a Alacritty; pendiente decidir cuál se agrega.
