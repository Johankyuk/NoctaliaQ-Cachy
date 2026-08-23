# NoctaliaQ-Cachy

Setup completo de Noctalia v5 + niri en CachyOS (KyuCachy). Config, scripts de GPU PRIME,
color-sync de teclado/MangoHud, cursor Bibata, zsh (cachyos-zsh-config + p10k), foot y
overrides de MangoHud para flatpaks.

## Instalación rápida (cualquier máquina, sin llave SSH)

El repo es público — clonar por HTTPS no requiere configurar nada:

```bash
git clone https://github.com/Johankyuk/NoctaliaQ-Cachy.git ~/NoctaliaQ-Cachy && \
cd ~/NoctaliaQ-Cachy && \
./install.sh
```

`install.sh` es idempotente: si algo ya está instalado o configurado, lo detecta y lo omite.
Todo archivo que reemplaza se respalda como `archivo.bak.<timestamp>` antes de sobreescribirse.

> Si vas a contribuir cambios de vuelta al repo (no solo desplegar config), necesitás el
> remote por SSH y una llave agregada en https://github.com/settings/ssh/new — para solo
> instalar en una máquina, HTTPS basta.

## Qué instala `install.sh`

- **Cursor** Bibata-Modern-Classic (tamaño 32) vía gsettings.
- **Noctalia**: `config.toml` completo (bar, dock, hooks, tema) + `kbd-color-sync.toml`
  (sat=1.6 val=0.85).
- **MangoHud**: paquete + `MangoHud.conf` + overrides para Sober y mcpelauncher si están
  instalados (Vulkan layer vía Flatpak).
- **Dolphin**: paquete + color scheme Noctalia.
- **niri**: todos los `.kdl` de `config/niri/cfg/` + `config.kdl` (window-rules, blur).
- **Zsh**: paquete + `cachyos-zsh-config` + zoxide + eza + `.zshrc`/`.p10k.zsh`, y cambia la
  shell por defecto del usuario (`chsh`, pide password del usuario).
- **Foot**: paquete + config + tema dinámico Noctalia.
- **Zen Browser**: paquete `zen-browser-bin` (repo `cachyos`, sin AUR).
- **Miri**: `config.toml` + servicio `systemd --user` (habilitado, arranca junto con niri).
- **Scripts** de `bin/` → `~/.local/bin/` (kbd-color-sync, mangohud-color-sync,
  noctaliaq-gpu-prime, noctaliaq-gpu-launch, noctaliaq-gpu-flatpak-sync).

## Módulos manuales (no los corre `install.sh`)

Estos requieren pasos que no son seguros de automatizar de un tirón (compilar de AUR,
tocar el display manager del sistema, o dependen de contexto que varía por máquina):

- **`greeter-setup/`** — reemplaza SDDM por greetd + noctalia-greeter. Requiere compilar
  `noctalia-greeter` de AUR primero. Ver `greeter-setup/README.md` para el procedimiento
  y el rollback si falla.
- **`file-manager-fix/`** — fija Dolphin como manejador de `inode/directory` por sobre
  Nautilus sin desinstalarlo (es dependencia indirecta de niri). `./file-manager-fix/set-default-filemanager.sh`, idempotente.

## Estructura
config/ — dotfiles: noctalia, niri, foot, zsh, MangoHud
bin/ — scripts desplegados a ~/.local/bin
greeter-setup/ — módulo manual: SDDM → greetd
file-manager-fix/ — módulo manual: Dolphin default
handoffs/ — notas de sesiones de trabajo, no se despliegan
