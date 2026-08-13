#!/usr/bin/env bash
# install.sh — despliegue completo del setup Noctalia/niri de KyuCachy (CachyOS).
# Uso: clonar el repo y correr ./install.sh desde su raíz.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

backup_and_copy() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  [ -e "$dst" ] && cp -r "$dst" "$dst.bak.$(date +%s)"
  cp -r "$src" "$dst"
}

echo "== Cursor Bibata-Modern-Classic (tamaño 32) =="
backup_and_copy "$REPO_DIR/icons/Bibata-Modern-Classic" "$HOME/.local/share/icons/Bibata-Modern-Classic"
gsettings set org.gnome.desktop.interface cursor-theme "Bibata-Modern-Classic" 2>/dev/null || true
gsettings set org.gnome.desktop.interface cursor-size 32 2>/dev/null || true

echo "== Config Noctalia =="
backup_and_copy "$REPO_DIR/config/noctalia/config.toml" "$HOME/.config/noctalia/config.toml"

echo "== MangoHud (paquete + config) =="
if ! pacman -Qi mangohud &>/dev/null; then
  sudo pacman -S --needed --noconfirm mangohud
else
  echo "mangohud ya instalado, se omite pacman."
fi
backup_and_copy "$REPO_DIR/config/MangoHud/MangoHud.conf" "$HOME/.config/MangoHud/MangoHud.conf"

echo "== MangoHud en flatpaks (Sober / mcpelauncher) =="
if flatpak info org.vinegarhq.Sober &>/dev/null || flatpak info io.mrarm.mcpelauncher &>/dev/null; then
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

echo "== Alacritty =="
backup_and_copy "$REPO_DIR/config/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"
backup_and_copy "$REPO_DIR/config/alacritty/themes" "$HOME/.config/alacritty/themes"

echo "== niri cfg =="
for f in "$REPO_DIR"/config/niri/cfg/*.kdl; do
  backup_and_copy "$f" "$HOME/.config/niri/cfg/$(basename "$f")"
done

echo "== Scripts .local/bin =="
mkdir -p "$HOME/.local/bin"
for f in "$REPO_DIR"/bin/*; do
  backup_and_copy "$f" "$HOME/.local/bin/$(basename "$f")"
  chmod +x "$HOME/.local/bin/$(basename "$f")"
done

echo "✓ terminado — reiniciá niri o hacé logout/login para que todo tome efecto"
