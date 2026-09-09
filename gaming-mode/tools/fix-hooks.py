#!/usr/bin/env python3
"""Inserta los hooks de noctaliaq-power dentro de los arrays [hooks] existentes.

Idempotente. Respalda con timestamp. Verifica releyendo el archivo.
Uso: python3 gaming-mode/tools/fix-hooks.py
"""
import os
import re
import shutil
import sys
import time

CMDS = {
    "power_profile_changed": '"/usr/local/bin/noctaliaq-power apply \\"$NOCTALIA_POWER_PROFILE\\""',
    "started": '"/usr/local/bin/noctaliaq-power apply"',
}
STAMP = time.strftime("%Y%m%d-%H%M%S")


def logical_span(lines, i):
    """Devuelve (fin, texto) del valor que empieza en la linea i.

    Soporta arrays multilinea: sigue leyendo hasta cerrar los corchetes.
    """
    depth = lines[i].count("[") - lines[i].count("]")
    # la cabecera [hooks] no cuenta; aqui i siempre es una linea 'clave ='
    j = i
    while depth > 0 and j + 1 < len(lines):
        j += 1
        depth += lines[j].count("[") - lines[j].count("]")
    return j, "\n".join(lines[i:j + 1])


def patch(path):
    if not os.path.isfile(path):
        print("  -- no existe, se omite: " + path)
        return True

    original = open(path, encoding="utf-8").read()
    lines = original.split("\n")

    inicio = next((k for k, l in enumerate(lines)
                   if re.match(r"^\s*\[hooks\]\s*$", l)), None)
    if inicio is None:
        print("  ERR sin seccion [hooks] en " + path)
        return False

    fin = len(lines)
    for k in range(inicio + 1, len(lines)):
        if re.match(r"^\s*\[", lines[k]):
            fin = k
            break

    cambios = []
    for clave, cmd in CMDS.items():
        pat = re.compile(r"^(\s*)" + clave + r"\s*=\s*(.*)$")
        hit = None
        for k in range(inicio + 1, fin):
            m = pat.match(lines[k])
            if m:
                hit = (k, m.group(1), m.group(2))
                break

        if hit is None:
            lines.insert(fin, "  " + clave + " = [ " + cmd + " ]")
            fin += 1
            cambios.append(clave + ": creado")
            continue

        k, sangria, _ = hit
        ultima, bloque = logical_span(lines, k)
        if "noctaliaq-power" in bloque:
            cambios.append(clave + ": ya presente")
            continue

        valor = bloque.split("=", 1)[1].strip()
        if valor.startswith("["):
            interior = valor[valor.index("[") + 1:valor.rindex("]")].strip()
            nuevo_interior = (interior + ", " + cmd) if interior else cmd
        else:
            # era un string suelto: se convierte en array de dos
            nuevo_interior = valor.strip() + ", " + cmd
        lines[k:ultima + 1] = [sangria + clave + " = [ " + nuevo_interior + " ]"]
        fin -= (ultima - k)
        cambios.append(clave + ": fusionado")

    shutil.copy2(path, path + ".bak." + STAMP)
    open(path, "w", encoding="utf-8").write("\n".join(lines))

    # relectura: nunca confiar en el buffer de escritura
    check = open(path, encoding="utf-8").read()
    if check.count("/usr/local/bin/noctaliaq-power apply") < 2:
        print("  ERR no quedaron las dos entradas en " + path)
        return False
    print("  ok  " + path + " -> " + ", ".join(cambios))
    print("      respaldo: " + path + ".bak." + STAMP)
    return True


home = os.path.expanduser("~")
objetivos = [
    os.path.join(home, "NoctaliaQ-Cachy/config/noctalia/config.toml"),
    os.path.join(home, ".config/noctalia/config.toml"),
]
if not all(patch(p) for p in objetivos):
    sys.exit(1)
print("\nlisto. revisa con:  grep -n noctaliaq-power ~/.config/noctalia/config.toml")
