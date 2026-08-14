function fish_greeting
    set -l marker "/tmp/.horus_greeting_shown_$USER"
    if test -f "$marker"
        return
    end
    touch "$marker"
    printf '%s\n' \
        ' ___           _               ___                  ___       _               ' \
        '  | |_   _    |_)  _   _ _|_    |   _   \\_/ _ _|_    |  _    /   _  ._ _   _  ' \
        '  | | | (/_   |_) (/_ _>  |_   _|_ _>    | (/_ |_    | (_)   \\_ (_) | | | (/_'
end
