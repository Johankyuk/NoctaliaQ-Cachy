#!/usr/bin/env bash
# install.sh — despliegue completo del setup Noctalia/Umbriel de KyuCachy (CachyOS).
# Uso: clonar el repo y correr ./install.sh desde su raíz.
set -Eeuo pipefail
trap 'echo "ERROR: línea $LINENO: $BASH_COMMAND" >&2' ERR
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

backup_and_copy() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ]; then cp -r "$dst" "$dst.bak.$(date +%s)"; fi
  if [ -d "$src" ]; then
    mkdir -p "$dst"
    cp -rT "$src" "$dst"
  else
    cp "$src" "$dst"
  fi
}

echo "== RGB (Alienware) =="
if [ "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" = "Alienware" ]; then
  install -Dm755 "$REPO_DIR/bin/alienware/alienfx.py" "$HOME/.local/bin/alienfx.py"
  install -Dm755 "$REPO_DIR/bin/alienware/rgb-sync.py" "$HOME/.local/bin/rgb-sync.py"
  pacman -Qi python-pyusb >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm python-pyusb
  echo "Regla udev: ver alienware-setup/ (requiere root, no automatico)."
else
  echo "No es Alienware, se omite."
fi
backup_and_copy "$REPO_DIR/config/noctalia/scripts/rgb-sync-hook.sh" "$HOME/.config/noctalia/scripts/rgb-sync-hook.sh"
chmod +x "$HOME/.config/noctalia/scripts/rgb-sync-hook.sh"

echo "== Tema de cursor =="
# El tema y el tamaño los gobierna config/niri/cfg/cursor.kdl, fuente única.
# Acá solo se garantiza que el paquete esté instalado.
pacman -Qi capitaine-cursors >/dev/null 2>&1 || sudo pacman -S --needed capitaine-cursors

echo "== Config Noctalia =="
if [ -f "$HOME/.config/noctalia/noctalia-full-config.toml" ]; then
  echo "noctalia-full-config.toml presente: no se despliega config.toml del repo (los hooks van en el overlay zz-noctaliaq.toml)."
else
backup_and_copy "$REPO_DIR/config/noctalia/config.toml" "$HOME/.config/noctalia/config.toml"
# Noctalia no expande ~ ni $HOME en el TOML: las rutas se resuelven aca,
# sobre la copia desplegada. El archivo del repo queda portable.
_cfg="$HOME/.config/noctalia/config.toml"
sed -i "s|\"HOOK\"|\"$HOME/.config/noctalia/scripts/rgb-sync-hook.sh\"|g; s|/home/kyu/|$HOME/|g; s|\"HOME/|\"$HOME/|g" "$_cfg"
# /home/kyu es placeholder solo si $HOME es otro; para el usuario kyu es la ruta real.
_pat='HOOK\|"HOME/'
[ "$HOME" = "/home/kyu" ] || _pat="$_pat\|/home/kyu"
if grep -q "$_pat" "$_cfg"; then
  echo "ERROR: quedaron placeholders sin sustituir en $_cfg" >&2
  grep -n "$_pat" "$_cfg" >&2
  exit 1
fi
echo "config.toml: rutas resueltas para $USER."
fi

# KYU-PALETTE-INSTALL
# Paleta Kyu_Pallete y config completa de Noctalia (rutas /home/kyu resueltas a $HOME).
# KYU-ASSETS
# Imagenes propias en ~/.local/share/noctaliaq (no se toca ~/Pictures).
install -Dm644 "$REPO_DIR/assets/Kyu_PFP.png" "$HOME/.local/share/noctaliaq/Kyu_PFP.png"
install -Dm644 "$REPO_DIR/assets/wallpapers/Kyu_Wallpaper.png" "$HOME/.local/share/noctaliaq/wallpapers/Kyu_Wallpaper.png"
mkdir -p "$HOME/.config/noctalia/palettes"
backup_and_copy "$REPO_DIR/config/noctalia/palettes" "$HOME/.config/noctalia/palettes"
backup_and_copy "$REPO_DIR/config/noctalia/noctalia-full-config.toml" "$HOME/.config/noctalia/noctalia-full-config.toml"
sed -i "s|/home/kyu/|$HOME/|g" "$HOME/.config/noctalia/noctalia-full-config.toml"

# --- PATH de la sesión gráfica ---------------------------------------------
# systemd --user no incluye ~/.local/bin; sin esto, miri y cualquier binario
# propio son invisibles para el launcher.
# Overlay de hooks GPU/RGB: se carga al final (zz-) y solo pisa lo que declara,
# asi convive con una config completa propia en ~/.config/noctalia/.
backup_and_copy "$REPO_DIR/config/noctalia/zz-noctaliaq.toml" "$HOME/.config/noctalia/zz-noctaliaq.toml"
sed -i "s|\"HOOK\"|\"$HOME/.config/noctalia/scripts/rgb-sync-hook.sh\"|g; s|\"HOME/|\"$HOME/|g" "$HOME/.config/noctalia/zz-noctaliaq.toml"
if grep -q 'HOOK\|"HOME/' "$HOME/.config/noctalia/zz-noctaliaq.toml"; then
  echo "ERROR: placeholders sin sustituir en zz-noctaliaq.toml" >&2
  exit 1
fi

backup_and_copy "$REPO_DIR/config/environment.d/10-path.conf" "$HOME/.config/environment.d/10-path.conf"

backup_and_copy "$REPO_DIR/config/noctalia/kbd-color-sync.toml" "$HOME/.config/noctalia/kbd-color-sync.toml"
sed -i "s|\"HOME/|\"$HOME/|g" "$HOME/.config/noctalia/kbd-color-sync.toml"
grep -q '"HOME/' "$HOME/.config/noctalia/kbd-color-sync.toml" && { echo "ERROR: placeholder sin sustituir en kbd-color-sync.toml" >&2; exit 1; }

echo "== MangoHud (paquete + config) =="
if ! pacman -Qi mangohud &>/dev/null; then
  sudo pacman -S --needed --noconfirm mangohud
else
  echo "mangohud ya instalado, se omite pacman."
fi
backup_and_copy "$REPO_DIR/config/MangoHud/MangoHud.conf" "$HOME/.config/MangoHud/MangoHud.conf"
sed -i "s|=HOME/|=$HOME/|g" "$HOME/.config/MangoHud/MangoHud.conf"
grep -q '=HOME/' "$HOME/.config/MangoHud/MangoHud.conf" && { echo "ERROR: placeholder sin sustituir en MangoHud.conf" >&2; exit 1; }

echo "== MangoHud en flatpaks (Sober / mcpelauncher) =="
if flatpak info org.vinegarhq.Sober &>/dev/null || flatpak info io.mrarm.mcpelauncher &>/dev/null; then
  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install --user -y flathub org.freedesktop.Platform.VulkanLayer.MangoHud//25.08 || true
  flatpak override --user --filesystem=xdg-config/MangoHud:ro
  if flatpak info org.vinegarhq.Sober &>/dev/null; then
    # Sober renderiza por Vulkan: no necesita LD_PRELOAD/MANGOHUD_DLSYM, el layer implícito ya lo cubre.
    # device=input y el filesystem de Discord IPC sí son necesarios (los pide el propio Sober al abrir).
    flatpak override --user --device=input org.vinegarhq.Sober
    flatpak override --user --filesystem=xdg-run/app/com.discordapp.Discord:create org.vinegarhq.Sober
    flatpak override --user --filesystem=xdg-run/discord-ipc-0 org.vinegarhq.Sober
    flatpak override --user --env=MANGOHUD=1 org.vinegarhq.Sober
  fi
  if flatpak info io.mrarm.mcpelauncher &>/dev/null; then
    flatpak override --user --env=MANGOHUD=1 io.mrarm.mcpelauncher
    flatpak override --user --env=MANGOHUD_DLSYM=1 io.mrarm.mcpelauncher
    flatpak override --user --env=LD_PRELOAD=/usr/lib/extensions/vulkan/MangoHud/lib/x86_64-linux-gnu/libMangoHud_opengl.so io.mrarm.mcpelauncher
  fi
else
  echo "Ni Sober ni mcpelauncher están instalados, se omite."
fi

echo "== PRIME offload en flatpaks (extension GL de NVIDIA) =="
if command -v nvidia-smi &>/dev/null && flatpak info io.mrarm.mcpelauncher &>/dev/null; then
  DRV=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | tr "." "-")
  if [ -z "$DRV" ]; then echo "ERROR: no se pudo leer driver_version" >&2; exit 1; fi
  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  # La extension debe coincidir EXACTO con el driver del host; si no, flatpak no monta
  # el GL de NVIDIA dentro del sandbox y ninguna env var de PRIME tiene efecto.
  flatpak install -y flathub "org.freedesktop.Platform.GL.nvidia-$DRV" \
                            "org.freedesktop.Platform.GL32.nvidia-$DRV"
  if ! flatpak list --runtime | grep -q "GL.nvidia-$DRV"; then
    echo "ERROR: falta org.freedesktop.Platform.GL.nvidia-$DRV tras el install" >&2; exit 1
  fi
  # device=all: --device=dri NO expone /dev/nvidia*, que el offload necesita.
  flatpak override --user io.mrarm.mcpelauncher \
    --device=all \
    --env=__NV_PRIME_RENDER_OFFLOAD=1 \
    --env=__GLX_VENDOR_LIBRARY_NAME=nvidia \
    --env=__VK_LAYER_NV_optimus=NVIDIA_only
else
  echo "Sin NVIDIA o sin mcpelauncher, se omite PRIME en flatpaks."
fi

echo "== Gestor de archivos (nautilus) + iconos Papirus =="
# Revert del extinto file-manager-fix/ (Dolphin como inode/directory +
# .desktop de Nautilus ocultos). Idempotente: no hace nada si nunca se corrió.
rm -f "$HOME/.local/share/applications/org.gnome.Nautilus.desktop" \
      "$HOME/.local/share/applications/nautilus-autorun-software.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
if [ "$(xdg-mime query default inode/directory)" != "org.gnome.Nautilus.desktop" ]; then
  xdg-mime default org.gnome.Nautilus.desktop inode/directory
  if [ "$(xdg-mime query default inode/directory)" != "org.gnome.Nautilus.desktop" ]; then
    echo "ERROR: inode/directory sigue en $(xdg-mime query default inode/directory)" >&2
    exit 1
  fi
  echo "inode/directory reapuntado a Nautilus."
else
  echo "inode/directory ya en Nautilus, se omite."
fi
for pkg in nautilus papirus-icon-theme; do
  if ! pacman -Qi "$pkg" &>/dev/null; then
    sudo pacman -S --needed --noconfirm "$pkg"
  else
    echo "$pkg ya instalado, se omite pacman."
  fi
done

# KYU-NIRI-OPCIONAL
if command -v niri >/dev/null 2>&1; then
echo "== niri cfg =="
for f in "$REPO_DIR"/config/niri/cfg/*.kdl; do
  backup_and_copy "$f" "$HOME/.config/niri/cfg/$(basename "$f")"
done
fi

echo "== Zsh (paquetes + config + p10k) =="
if ! pacman -Qi zsh &>/dev/null; then
  sudo pacman -S --needed --noconfirm zsh
else
  echo "zsh ya instalado, se omite pacman."
fi
if ! pacman -Qi cachyos-zsh-config &>/dev/null; then
  sudo pacman -S --needed --noconfirm cachyos-zsh-config
else
  echo "cachyos-zsh-config ya instalado, se omite pacman."
fi
command -v zoxide &>/dev/null || sudo pacman -S --needed --noconfirm zoxide
command -v eza &>/dev/null || sudo pacman -S --needed --noconfirm eza
backup_and_copy "$REPO_DIR/config/zsh/zshrc" "$HOME/.zshrc"
backup_and_copy "$REPO_DIR/config/zsh/p10k.zsh" "$HOME/.p10k.zsh"
if [ "$(basename "$SHELL")" != "zsh" ]; then
  chsh -s "$(command -v zsh)" "$USER"
  echo "shell cambiada a zsh -- toma efecto en el proximo login"
else
  echo "zsh ya es la shell por defecto."
fi

echo "== Completions de zsh para noctalia =="
# Se generan del esquema vivo e incluyen subcomandos de los plugins instalados.
# Regenerar tras instalar/quitar plugins con el mismo comando.
if command -v noctalia &>/dev/null; then
  mkdir -p "$HOME/.local/share/zsh/site-functions"
  if noctalia completions zsh > "$HOME/.local/share/zsh/site-functions/_noctalia" 2>/dev/null \
     && head -1 "$HOME/.local/share/zsh/site-functions/_noctalia" | grep -q "^#compdef noctalia"; then
    echo "completions instaladas."
  else
    rm -f "$HOME/.local/share/zsh/site-functions/_noctalia"
    echo "WARN: noctalia completions fallo, se omite." >&2
  fi
else
  echo "WARN: noctalia no encontrado, se omiten completions." >&2
fi

echo "== Foot (paquete + config + tema Noctalia) =="
if ! pacman -Qi foot &>/dev/null; then
  sudo pacman -S --needed --noconfirm foot
else
  echo "foot ya instalado, se omite pacman."
fi
backup_and_copy "$REPO_DIR/config/foot" "$HOME/.config/foot"

# KYU-NIRI-OPCIONAL-2
if command -v niri >/dev/null 2>&1; then
echo "== niri config.kdl (window-rules, blur) =="
backup_and_copy "$REPO_DIR/config/niri/config.kdl" "$HOME/.config/niri/config.kdl"
fi

echo "== Zen Browser =="
if ! pacman -Qi zen-browser-bin &>/dev/null; then
  sudo pacman -S --needed --noconfirm zen-browser-bin
else
  echo "zen-browser-bin ya instalado, se omite pacman."
fi

systemctl --user daemon-reload

# dGPU: sesion siempre arranca en ahorro (estado offload off, gamer mode off).
# Encendido en caliente al conectar AC (hooks battery_*) o con Mod+Alt+G.
backup_and_copy "$REPO_DIR/config/systemd-user/noctaliaq-gpu-boot.service" "$HOME/.config/systemd/user/noctaliaq-gpu-boot.service"
systemctl --user daemon-reload
systemctl --user enable noctaliaq-gpu-boot.service

# Zen con EGL de Mesa: sin esto su proceso de video abre la NVIDIA y bloquea el apagado.
backup_and_copy "$REPO_DIR/config/applications/zen.desktop" "$HOME/.local/share/applications/zen.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

# Apagado fisico de la dGPU (solo laptops ASUS con dgpu_disable). Requiere root.
if [[ -e /sys/devices/platform/asus-nb-wmi/dgpu_disable ]]; then
    sudo "$REPO_DIR/gpu-setup/deploy-dgpu.sh" || echo "AVISO: deploy-dgpu.sh fallo"
fi


echo "== Umbriel (compositor principal) =="
command -v paru >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm paru
for pkg in umbriel-git xdg-desktop-portal-umbriel-git; do
  if pacman -Qi "$pkg" &>/dev/null; then
    echo "$pkg ya instalado, se omite."
  else
    paru -S --needed --noconfirm --skipreview "$pkg"
  fi
done
backup_and_copy "$REPO_DIR/config/umbriel/config.toml" "$HOME/.config/umbriel/config.toml"
if [[ -e /sys/devices/platform/asus-nb-wmi/dgpu_disable ]]; then
  backup_and_copy "$REPO_DIR/config/umbriel/drm-asus.toml" "$HOME/.config/umbriel/drm.toml"
else
  rm -f "$HOME/.config/umbriel/drm.toml"
fi
umbriel config validate

# KYU-PRINCIPAL-UMBRIEL
echo "== Umbriel como entorno principal =="
_otros=()
for _pkg in niri hyprland sway river labwc plasma-desktop plasma-workspace gnome-shell gnome-session xfce4-session cosmic-session cinnamon budgie-desktop mate-session-manager lxqt-session i3-wm bspwm awesome openbox qtile; do
  pacman -Qq "$_pkg" >/dev/null 2>&1 && _otros+=("$_pkg")
done
if [ "${#_otros[@]}" -gt 0 ]; then
  echo "Otros entornos o compositores instalados: ${_otros[*]}"
  if [ -r /dev/tty ]; then
    read -r -p "Eliminarlos y dejar Umbriel como principal? [s/N] " _resp </dev/tty
  else
    _resp=n
  fi
  case "$_resp" in
    s|S|y|Y) sudo pacman -Rns "${_otros[@]}" </dev/tty ;;
    *) echo "Se conservan." ;;
  esac
else
  echo "No hay otros entornos instalados."
fi

# KYU-POWERKEY
echo "== Boton de apagado (bloquear + suspender) =="
sudo install -Dm644 "$REPO_DIR/logind/50-noctaliaq-powerkey.conf" /etc/systemd/logind.conf.d/50-noctaliaq-powerkey.conf
sudo systemctl kill -s HUP systemd-logind

echo "== Scripts .local/bin =="
mkdir -p "$HOME/.local/bin"
for f in "$REPO_DIR"/bin/*; do
  backup_and_copy "$f" "$HOME/.local/bin/$(basename "$f")"
  chmod +x "$HOME/.local/bin/$(basename "$f")"
done

echo "✓ terminado — hacé logout/login y elegí Umbriel para que todo tome efecto"
