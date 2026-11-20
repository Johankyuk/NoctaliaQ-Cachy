# iso/

ISO de Arch (archiso) construida desde este mismo repo. El arbol git (HEAD) viaja dentro de la ISO en /opt/porphyx/src, asi que lo que se instala es lo que hay en el repo.

| Archivo | Que es |
|---|---|
| `aur-packages.txt` | Paquetes que no existen en Arch; se compilan al repo local |
| `target-packages.txt` | Paquetes oficiales del sistema instalado |
| `check-packages.sh` | Verifica que target-packages.txt resuelva en Arch puro |
| `build-local-repo.sh` | Compila aur-packages.txt en un chroot limpio y arma `repo/` |
| `build-iso.sh` | Arma la ISO en `out/` |

Orden: `check-packages.sh`, `build-local-repo.sh`, commitear, `build-iso.sh`.
Estado: esqueleto. Falta el instalador dentro de la ISO y adaptar install.sh a Arch.
