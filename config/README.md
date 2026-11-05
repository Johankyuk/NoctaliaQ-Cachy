# config/

Dotfiles que `install.sh` despliega. Cada carpeta es un módulo independiente.

| Carpeta | Contenido | Estado |
|---|---|---|
| `noctalia/` | `config.toml` y `kbd-color-sync.toml` del repo, `noctalia-full-config.toml` (la config completa activa, `install.sh` ya no la pisa), `zz-noctaliaq.toml` (overlay con hooks de GPU/RGB y comando de lanzamiento, se carga al final), `palettes/`, `scripts/` | Vigente |
| `umbriel/` | `config.toml` de Umbriel (va a `~/.config/umbriel/`) y `drm-asus.toml` | Vigente |
| `foot/` | `foot.ini` | Vigente |
| `zsh/` | `zshrc` y `p10k.zsh` | Vigente |
| `MangoHud/` | `MangoHud.conf` | Vigente |
| `applications/` | Entradas de launcher: cava, cmatrix, lavat y `zen.desktop`. Van a `~/.local/share/applications` | Vigente |
| `environment.d/` | `10-path.conf` | Vigente |
| `systemd-user/` | `noctaliaq-gpu-boot.service` (servicio de usuario, va a `~/.config/systemd/user`) | Vigente |
| `niri/` | `config.kdl` y `cfg/` | Legado: niri solo es la base de CachyOS |

Noctalia carga todos los `*.toml` de `~/.config/noctalia/` en orden alfabético; por eso el overlay
se llama `zz-` y solo pisa lo que declara. Las reglas de placeholders de rutas están en
[../docs/instalacion-detalle.md](../docs/instalacion-detalle.md).
