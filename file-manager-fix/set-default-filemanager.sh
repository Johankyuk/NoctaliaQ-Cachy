#!/bin/bash
# set-default-filemanager.sh
# Dolphin como gestor de archivos por defecto. Nautilus no se desinstala
# porque xdg-desktop-portal-gnome depende de él, y ese portal es
# dependencia indirecta de niri y lutris en CachyOS. En su lugar se
# oculta del launcher a nivel usuario.
set -e

DOLPHIN_DESKTOP=$(find /usr/share/applications -maxdepth 1 -iname "*dolphin*.desktop" ! -iname "*settings*" | head -1 | xargs -n1 basename)

if [ -z "$DOLPHIN_DESKTOP" ]; then
    echo "ERROR: no se encontró el .desktop de Dolphin."
    exit 1
fi

echo "Estableciendo $DOLPHIN_DESKTOP como gestor de archivos por defecto..."
xdg-mime default "$DOLPHIN_DESKTOP" inode/directory

echo "Ocultando entradas de Nautilus del launcher..."
mkdir -p ~/.local/share/applications
for f in org.gnome.Nautilus.desktop nautilus-autorun-software.desktop; do
    if [ -f "/usr/share/applications/$f" ]; then
        \cp -f "/usr/share/applications/$f" ~/.local/share/applications/"$f"
        if grep -q "^NoDisplay=" ~/.local/share/applications/"$f"; then
            sed -i 's/^NoDisplay=.*/NoDisplay=true/' ~/.local/share/applications/"$f"
        else
            echo "NoDisplay=true" >> ~/.local/share/applications/"$f"
        fi
    fi
done
update-desktop-database ~/.local/share/applications 2>/dev/null || true

echo "Default actual: $(xdg-mime query default inode/directory)"
