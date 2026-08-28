# NoctaliaQ-Cachy

Setup completo de Noctalia v5 + niri en CachyOS (KyuCachy). Config, scripts de GPU PRIME,
color-sync de teclado/MangoHud, cursor, zsh (cachyos-zsh-config + p10k), foot y
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

- **Cursor**: paquete `capitaine-cursors`. El tema y el tamaño los gobierna
  `config/niri/cfg/cursor.kdl` (fuente única). El tema activo es
  `Skyrim-by-ru5tyshark-cursors`, instalación manual desde el repo `cursor-manager`.
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

## Placeholders de rutas

Los archivos de `config/` no llevan rutas absolutas: `install.sh` las sustituye al
desplegar, para que el repo funcione con cualquier usuario. Tres formas, cada una con
su `sed` y su guardia que aborta si algo queda sin sustituir:

| Placeholder | Archivos | Se reemplaza por |
|---|---|---|
| `"HOME/` | `noctalia/config.toml`, `noctalia/kbd-color-sync.toml` | `"$HOME/` |
| `=HOME/` | `MangoHud/MangoHud.conf` | `=$HOME/` |
| `"HOOK"` | `noctalia/config.toml` | ruta a `rgb-sync-hook.sh` |

**Al editar estos archivos, nunca commitear rutas absolutas.** El `sed` de `config.toml`
tiene además una red de seguridad (`s|/home/kyu/|$HOME/|g`) que los otros dos no tienen.

Consecuencia para diagnóstico: un `diff` crudo entre `config/noctalia/config.toml` y
`~/.config/noctalia/config.toml` siempre muestra estas líneas y no indica drift. Para
comparar de verdad hay que normalizar primero con el mismo `sed` que aplica `install.sh`.

Si se agrega un archivo nuevo con rutas, agregar las tres piezas: placeholder en el
archivo, `sed` en `install.sh`, y `grep` que aborte.

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
