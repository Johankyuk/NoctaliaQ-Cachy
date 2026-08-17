#!/bin/bash
# install-greeter.sh
# Instala y configura noctalia-greeter + greetd como reemplazo de SDDM.
# Requiere noctalia >= 5.0.0-beta.8 (incluye el fix de timeout DNS del
# widget del clima que causaba "greeter exited without creating a session").
set -e

echo "Verificando dependencias..."
pacman -Qi greetd >/dev/null 2>&1 || sudo pacman -S --needed greetd
pacman -Qi noctalia-greeter >/dev/null 2>&1 || {
    echo "noctalia-greeter no está instalado. Compilar desde AUR primero:"
    echo "  git clone https://aur.archlinux.org/noctalia-greeter.git /tmp/noctalia-greeter"
    echo "  cd /tmp/noctalia-greeter && makepkg -si"
    exit 1
}

echo "Copiando config de greetd..."
sudo install -Dm644 "$(dirname "$0")/config.toml" /etc/greetd/config.toml

echo "Corriendo setup del sistema para noctalia-greeter..."
sudo /usr/share/noctalia-greeter/setup_greeter_system.sh

echo "Deshabilitando SDDM, habilitando greetd..."
sudo systemctl disable --now sddm.service
sudo systemctl enable greetd.service

echo "Listo. Reiniciá para probar."
echo "Rollback si falla: sudo systemctl disable --now greetd && sudo systemctl enable --now sddm"
