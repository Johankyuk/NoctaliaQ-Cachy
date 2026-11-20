# Branding de la ISO sobre el perfil ya copiado. Uso: brand.sh <perfil> <repo>
set -Eeuo pipefail
P="$1"
SRC="$2"
sed -i 's/Arch Linux install medium/Porphyx Linux installer/g' "$P"/efiboot/loader/entries/*.conf "$P/grub/grub.cfg" "$P/grub/loopback.cfg" "$P"/syslinux/*.cfg
sed -i 's/^MENU TITLE Arch Linux/MENU TITLE Porphyx Linux/' "$P/syslinux/archiso_head.cfg"
sed -i 's/#9033ccff/#90d64ffd/; /MENU COLOR border/ s/#40ffffff/#60d64ffd/; /MENU COLOR sel/ s/#20ffffff/#a09900cc/' "$P/syslinux/archiso_head.cfg"
sed -i 's|^iso_publisher=.*|iso_publisher="Porphyx Linux <https://github.com/Johankyuk/NoctaliaQ-Cachy>"|' "$P/profiledef.sh"
grep -qx fastfetch "$P/packages.x86_64" || printf '\nfastfetch\n' >> "$P/packages.x86_64"
W="$SRC/assets/wallpapers/Kyu_Wallpaper.png"
if command -v magick >/dev/null 2>&1 && [[ -f "$W" ]]; then
  magick "$W" -resize 640x480^ -gravity center -extent 640x480 "$P/syslinux/splash.png"
else
  echo "AVISO: sin magick o sin wallpaper, se deja el splash original"
fi
echo "branding aplicado"

# KYU-BUILD-MIRRORS: el build usa mirrors rapidos (el primero del mirrorlist del host puede ser lento)
perl -pi -e 's|^Include = /etc/pacman\.d/mirrorlist$|Server = https://fastly.mirror.pkgbuild.com/\$repo/os/\$arch\nServer = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch|' "$P/pacman.conf"
