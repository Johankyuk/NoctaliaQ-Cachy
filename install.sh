#!/usr/bin/env bash
# install.sh — despliegue completo del setup Noctalia/niri de KyuCachy (CachyOS).
# Uso: clonar el repo y correr ./install.sh desde su raíz.
set -euo pipefail
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
backup_and_copy "$REPO_DIR/config/noctalia/config.toml" "$HOME/.config/noctalia/config.toml"
# Noctalia no expande ~ ni $HOME en el TOML: las rutas se resuelven aca,
# sobre la copia desplegada. El archivo del repo queda portable.
_cfg="$HOME/.config/noctalia/config.toml"
sed -i "s|\"HOOK\"|\"$HOME/.config/noctalia/scripts/rgb-sync-hook.sh\"|g; s|/home/kyu/|$HOME/|g; s|\"HOME/|\"$HOME/|g" "$_cfg"
if grep -q 'HOOK\|/home/kyu\|"HOME/' "$_cfg"; then
  echo "ERROR: quedaron placeholders sin sustituir en $_cfg" >&2
  grep -n 'HOOK\|/home/kyu\|"HOME/' "$_cfg" >&2
  exit 1
fi
echo "config.toml: rutas resueltas para $USER."

# --- PATH de la sesión gráfica ---------------------------------------------
# systemd --user no incluye ~/.local/bin; sin esto, miri y cualquier binario
# propio son invisibles para el launcher.
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

echo "== Dolphin (paquete + color scheme) =="
if ! pacman -Qi dolphin &>/dev/null; then
  sudo pacman -S --needed --noconfirm dolphin
else
  echo "dolphin ya instalado, se omite pacman."
fi
kwriteconfig6 --file dolphinrc --group UiSettings --key ColorScheme noctalia

echo "== niri cfg =="
for f in "$REPO_DIR"/config/niri/cfg/*.kdl; do
  backup_and_copy "$f" "$HOME/.config/niri/cfg/$(basename "$f")"
done

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

echo "== niri config.kdl (window-rules, blur) =="
backup_and_copy "$REPO_DIR/config/niri/config.kdl" "$HOME/.config/niri/config.kdl"

echo "== Zen Browser =="
if ! pacman -Qi zen-browser-bin &>/dev/null; then
  sudo pacman -S --needed --noconfirm zen-browser-bin
else
  echo "zen-browser-bin ya instalado, se omite pacman."
fi

echo "== Miri (config + servicio systemd --user) =="
backup_and_copy "$REPO_DIR/config/miri/config.toml" "$HOME/.config/miri/config.toml"
backup_and_copy "$REPO_DIR/config/systemd-user/miri.service" "$HOME/.config/systemd/user/miri.service"
systemctl --user daemon-reload
systemctl --user enable miri.service

echo "== Scripts .local/bin =="
mkdir -p "$HOME/.local/bin"
for f in "$REPO_DIR"/bin/*; do
  backup_and_copy "$f" "$HOME/.local/bin/$(basename "$f")"
  chmod +x "$HOME/.local/bin/$(basename "$f")"
done

echo "✓ terminado — reiniciá niri o hacé logout/login para que todo tome efecto"
