# Porphyx Linux: en el primer login interactivo despliega el setup del repo (install.sh).
case $- in *i*) ;; *) return 0 ;; esac
[ "$(id -u)" -ge "${NOCTALIAQ_MINUID:-1000}" ] || return 0
[ -z "${NOCTALIAQ_SKIP:-}" ] || return 0
NQ_OPT="${NOCTALIAQ_OPT:-/opt/noctaliaq}"
NQ_MARK="$HOME/.local/state/noctaliaq/firstlogin.done"
[ -e "$NQ_MARK" ] && return 0
[ -d "$NQ_OPT/src" ] || return 0
[ -d "$HOME/NoctaliaQ-Cachy" ] || cp -R "$NQ_OPT/src" "$HOME/NoctaliaQ-Cachy"
echo "Porphyx Linux: primer inicio, desplegando el setup del repo (pedira tu contrasena de sudo)."
if (cd "$HOME/NoctaliaQ-Cachy" && bash ./install.sh); then
  mkdir -p "$(dirname "$NQ_MARK")"
  : > "$NQ_MARK"
  echo "Porphyx Linux: listo. Reinicia para entrar a la sesion grafica."
else
  echo "Porphyx Linux: install.sh fallo. Se reintenta en el proximo login (NOCTALIAQ_SKIP=1 lo omite)."
fi
