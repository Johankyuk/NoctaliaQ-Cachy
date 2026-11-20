# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

[[ $(tty) == /dev/tty* ]] && setvtrgb /etc/porphyx-vtrgb 2>/dev/null
~/.automated_script.sh
command -v fastfetch >/dev/null 2>&1 && fastfetch
