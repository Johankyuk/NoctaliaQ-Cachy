# iso/

ISO de Arch (archiso) con `porphyx-install` (archinstall modificado, online). Instala solo la base de Arch:
kernel, firmware, red, drivers de GPU, audio y bluetooth. El escritorio no va en la ISO.

Despues del primer reinicio, en la TTY: `porphyx setup` (ver `porphyx/`). Clona este repo y corre `install.sh`
adaptado: Umbriel, Noctalia, Luciole y noctalia-greeter, con la GPU hibrida solo en ASUS TUF y preguntando.

| Archivo | Que es |
|---|---|
| `target-packages.txt` | Paquetes oficiales de la base instalada |
| `gen-config.py` | Genera archinstall.json (teclado latam, hostname porphyx, systemd-boot) |
| `check-packages.sh` | Verifica que target-packages.txt resuelva en Arch puro |
| `build-iso.sh` | Arma la ISO en `out/` |
| `overlay/` | Archivos de la ISO: launcher porphyx-install, plugin de archinstall, motd, tema de consola |

Sin uso desde que la ISO es online: `aur-packages.txt`, `build-local-repo.sh`, `build-offline-mirror.sh`,
`offline-extra-packages.txt`.
