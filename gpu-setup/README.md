# gpu-setup/

Control físico de la dGPU en portátiles ASUS (`dgpu_disable`). `install.sh` lo despliega con
`sudo gpu-setup/deploy-dgpu.sh`.

| Archivo | Para qué |
|---|---|
| `deploy-dgpu.sh` | Instalador. Requiere root y es idempotente. Deja `nvidia-powerd` deshabilitado al arranque |
| `noctaliaq-dgpu` | Enciende o apaga la dGPU físicamente. Corre como root vía pkexec o desde el servicio de arranque. `off` verifica que nadie la use antes de quitarla del bus PCI |
| `noctaliaq-dgpu-boot.service` | Servicio de sistema que apaga la dGPU al arrancar |
| `org.noctaliaq.dgpu.policy` | Acción polkit `org.noctaliaq.dgpu` para usar pkexec sin contraseña de root |
| `49-noctaliaq-dgpu.rules` | Regla polkit; `deploy-dgpu.sh` la instala en `/etc/polkit-1/rules.d/` |

Lo usa `bin/noctaliaq-gpu-prime`. El modo juego (`gaming-mode/`) enciende la dGPU a través de este
módulo.
