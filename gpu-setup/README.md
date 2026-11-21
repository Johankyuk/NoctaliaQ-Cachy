# gpu-setup/

Control de la dGPU en portátiles con GPU híbrida. `install.sh` lo despliega con
`sudo gpu-setup/deploy-dgpu.sh`.

| Archivo | Para qué |
|---|---|
| `deploy-dgpu.sh` | Instalador. Requiere root y es idempotente. Deja `nvidia-powerd` deshabilitado al arranque |
| `noctaliaq-dgpu` | Enciende o apaga la dGPU con el mejor backend disponible: `firmware-asus` (la quita del bus PCI y la corta por firmware; `off` verifica que nadie la use) o `runtime-pm` (genérico: deja el runtime PM en `auto`, mejor esfuerzo, sin probar fuera de ASUS). `noctaliaq-dgpu backend` imprime el elegido y se puede forzar con `BACKEND=` en `/etc/noctaliaq/dgpu.conf`. Corre como root vía pkexec o desde el servicio de arranque |
| `noctaliaq-dgpu-boot.service` | Servicio de sistema que apaga la dGPU al arrancar y otra vez al apagar el equipo, para que el siguiente arranque empiece sin dGPU (cachyos-drm-awaiter falla si la ve al inicio y nvidia no carga) |
| `org.noctaliaq.dgpu.policy` | Acción polkit `org.noctaliaq.dgpu` para usar pkexec sin contraseña de root |
| `49-noctaliaq-dgpu.rules` | Regla polkit; `deploy-dgpu.sh` la instala en `/etc/polkit-1/rules.d/` |

Lo usa `bin/noctaliaq-gpu-prime`. El modo juego (`gaming-mode/`) enciende la dGPU a través de este
módulo.
