# greeter-setup

Reemplaza SDDM por noctalia-greeter (greetd + compositor wlroots propio).

## Requisito de versión

Necesita `noctalia >= 5.0.0-beta.8`. Versiones anteriores tienen un bug
en el widget del clima: un lookup DNS colgado bloquea el loop principal
del greeter, causando "greeter exited without creating a session" ~2
min después de arrancar. El fix está en el changelog de Noctalia
(sección Weather/HTTP).

## Paquete

AUR: `noctalia-greeter` (estable, no el `-git`). Se compila con
`makepkg -si` — no correr `makepkg` como root.

## Archivos

- `config.toml` → `/etc/greetd/config.toml`

## Autorización (polkit)

El sync de apariencia greeter↔shell usa la acción
`org.noctalia.greeter.apply-appearance`, definida en
`/usr/share/polkit-1/actions/org.noctalia.greeter.apply-appearance.policy`.
Ese archivo lo instala el paquete `noctalia-greeter` — no hay que crear
ni versionar ninguna regla propia. Del lado del shell, solo hay que
poner `pkexec` como "Privilege command" en Noctalia Settings → Security.

## Uso

    ./install-greeter.sh

## Rollback

Pantalla en negro / timeout ~2 min sin crear sesión:

    sudo systemctl disable --now greetd
    sudo systemctl enable --now sddm
    sudo reboot

## Logs si algo falla

- `/var/log/noctalia-greeter.log` (compositor/sesión)
- `/var/lib/noctalia-greeter/greeter.log` (cliente)
- `journalctl -u greetd -b`
