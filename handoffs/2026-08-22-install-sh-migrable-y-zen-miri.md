# install.sh migrable (HTTPS, sin AUR) + zen-browser + miri

**Fecha:** 2026-08-22
**Componente:** install.sh, README, config/zsh, config/miri, systemd-user/miri.service

## Contexto

Objetivo: que `install.sh` funcione en cualquier máquina limpia (con o sin
llave SSH configurada) y sin depender de AUR. Validado en una laptop HP
ajena usada solo como banco de pruebas desechable (usuario `ale3061`, sin
git config, sin llaves, sin commits — todo el trabajo real se hizo y
quedó commiteado desde la TUF).

## 1. Foot no se instalaba, solo se copiaba el config

`install.sh` tenía `backup_and_copy "$REPO_DIR/config/foot" ...` sin el
chequeo de paquete que sí tenían mangohud/dolphin. En una máquina sin
foot preinstalado, el script dejaba el `.ini` sin el binario.

**Fix:** agregado `pacman -Qi foot || pacman -S --needed foot` antes del
copy, igual que el patrón de los demás paquetes.

## 2. Fish → Zsh

El repo instalaba `config/fish/` (config.fish + fish_greeting.fish), pero
la shell real en uso desde la migración es zsh. Fish nunca se usó tras
esa migración; zsh no estaba en `install.sh` en absoluto aunque el repo
ya traía `config/zsh/zshrc` y `p10k.zsh` sueltos sin referenciar.

**Fix:**
- Eliminado `config/fish/` del repo.
- Agregado a `install.sh`: paquetes `zsh` + `cachyos-zsh-config` (trae
  p10k/autosuggestions/syntax-highlighting como dependencias, mismo
  paquete que ya usa el zshrc real) + `zoxide` + `eza`.
- Copia `zshrc` → `~/.zshrc`, `p10k.zsh` → `~/.p10k.zsh`.
- `chsh -s $(command -v zsh) "$USER"` si la shell activa no es zsh ya.
  **Pide password del usuario (no sudo)** — interrumpe el script en ese
  punto, es esperado.

## 3. Zen Browser integrado

`Mod+B` en `keybinds.kdl` dispara `spawn "zen-browser"`, pero el paquete
nunca se instalaba desde `install.sh` — quedaba en el usuario tenerlo
puesto de antes. Confirmado que **no requiere AUR**:
pacman -Qi zen-browser-bin
Installed From : cachyos

Viene del repo `cachyos` (ya habilitado por defecto en `/etc/pacman.conf`
en cualquier instalación de CachyOS). Se agregó el bloque de instalación
estándar a `install.sh`.

## 4. Miri: integrado + bug de ruta hardcodeada corregido

`config/miri/config.toml` y `config/systemd-user/miri.service` estaban en
el repo desde antes pero `install.sh` nunca los desplegaba — quedó
detectado al repasar `Mod+*` y notar que faltaban piezas de la migración
completa.

**Bug encontrado al integrar:** `miri.service` usaba `%h` (correcto) en
`ExecStart`, pero el `ExecStartPost` tenía la ruta hardcodeada
`/home/kyu/.local/bin/miri` — en cualquier otra máquina/usuario el
servicio arranca pero el `ExecStartPost` nunca encuentra el binario.
Corregido a `%h/.local/bin/miri`.

**Fix en install.sh:**
- Copia `config/miri/config.toml` → `~/.config/miri/config.toml`.
- Copia `systemd-user/miri.service` → `~/.config/systemd/user/miri.service`.
- `systemctl --user daemon-reload && systemctl --user enable miri.service`
  (arranca junto con `niri.service` por el `PartOf=`/`WantedBy=`, no hace
  falta `--now`).

## 5. README reescrito

- Instalación documentada por **HTTPS**, no SSH — el repo es público,
  clonar/instalar no requiere llave. SSH solo hace falta para *contribuir*
  cambios de vuelta (documentado como nota aparte).
- Listado completo de qué instala `install.sh` (incluye zen-browser y
  miri ahora).
- Sección de "módulos manuales" separada: `greeter-setup/` (requiere
  compilar de AUR, toca el display manager del sistema) y
  `file-manager-fix/` — ninguno de los dos se corre automático desde
  `install.sh` a propósito, por depender de contexto o pasos no seguros
  de automatizar de un tirón.

## Commits de la sesión

- `b513b45` — foot con pacman, swap fish→zsh
- `f1cf6cb` — README reescrito (HTTPS + módulos manuales)
- `14d88d2` — zen-browser + miri integrados, fix ruta hardcodeada en miri.service
- `96ada7b` — README actualizado post-integración zen/miri

## Validación

Corrido `./install.sh` completo en la HP de prueba tras el patch de
foot/zsh — sin errores, sin git touch en esa máquina. zen-browser/miri
no se re-probaron ahí (se integraron después de descartar la sesión de
prueba); pendiente confirmar en próximo `./install.sh` desde cero en
la TUF o una máquina nueva que ambos bloques corran limpio.

## Pendiente

- Confirmar que `Mod+B` abre Zen sin fricción tras un `install.sh` desde
  cero (no solo en máquina donde ya estaba instalado).
- Confirmar que `miri.service` arranca y aplica
  `set-focused-workspace-mode master` en un login limpio, no solo en la
  máquina donde se desarrolló originalmente.
