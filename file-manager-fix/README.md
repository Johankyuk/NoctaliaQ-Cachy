# file-manager-fix

Dolphin como gestor de archivos por defecto en NoctaliaQ-Cachy.

## Por qué Nautilus sigue instalado

`pactree -r nautilus` muestra que `xdg-desktop-portal-gnome` depende de
`nautilus`, y ese portal es dependencia indirecta de `niri` (vía el
meta-paquete `cachyos-niri-noctalia`) y de `lutris`/`cachyos-gaming-applications`.
Desinstalarlo arrastraría niri. En vez de eso:

1. Fija Dolphin como manejador de `inode/directory` vía `xdg-mime`.
2. Oculta las entradas `.desktop` de Nautilus (`NoDisplay=true` a nivel
   usuario) para que no aparezcan en el launcher de Noctalia.

## Uso

    ./set-default-filemanager.sh

Idempotente.
