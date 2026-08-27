#!/usr/bin/env python3
"""Sincroniza el RGB del Alienware con la paleta resuelta de Noctalia."""
import os, sys, subprocess, colorsys

ALIENFX = os.path.expanduser("~/.local/bin/alienfx.py")
PALETTE = os.path.expanduser("~/.cache/noctalia/palette-raw.conf")

Z_TEC = [0x0008, 0x0004, 0x0002, 0x0001]   # izq -> der
Z_LOGO, Z_LETRAS = 0x0020, 0x0040
Z_LAT_IZQ, Z_LAT_DER, Z_MACROS = 0x1000, 0x2000, 0x4000

def read_palette():
    d = {}
    with open(PALETTE) as f:
        for line in f:
            if "=" in line:
                k, v = line.strip().split("=", 1)
                d[k] = v.lstrip("#")
    return d

# Calibracion por zona: multiplicadores (rojo, verde, azul).
# Cada zona tiene LEDs con eficiencias distintas por canal.
# Ajustes finos por zona, aplicados DESPUES de la saturacion.
POST = {
    #0x0040: (0.55, 1.0, 0.0),   # letras: rojo dominante
    #0x4000: (0.75, 1.0, 0.0),   # macros: rojo algo dominante
}

def post_ajuste(hexcolor, zona):
    if zona not in POST:
        return hexcolor
    fr, fg, fb = POST[zona]
    r = int(int(hexcolor[0:2], 16) * fr)
    g = int(int(hexcolor[2:4], 16) * fg)
    b = int(int(hexcolor[4:6], 16) * fb)
    return "{:02X}{:02X}{:02X}".format(min(r,255), min(g,255), min(b,255))

CALIB = {
    0x0001: (0.70, 0.70, 0.70),   # teclado der
    0x0002: (0.70, 0.70, 0.70),   # teclado centro-der
    0x0004: (0.70, 0.70, 0.70),   # teclado centro
    0x0008: (0.70, 0.70, 0.70),   # teclado izq
    0x4000: (1.0, 1.0, 0.55),   # macros: azul muy dominante
    0x0040: (0.40, 0.70, 0.70),   # letras ALIENWARE: rojo muy dominante
    0x1000: (0.70, 0.70, 0.70),    # lateral izq (ajustar si sigue saturada)
    0x2000: (0.70, 0.70, 0.70),    # lateral der
}

def calibrar(hexcolor, zona):
    """
    Este firmware normaliza el color al canal mas alto, asi que los colores
    con canales parecidos salen blancos. Para que se vean definidos hay que
    EXAGERAR la separacion: el canal mas alto se deja, los demas se bajan.
    """
    r = int(hexcolor[0:2], 16)
    g = int(hexcolor[2:4], 16)
    b = int(hexcolor[4:6], 16)
    alto = max(r, g, b)
    if alto == 0:
        return "000000"
    fuerza = 4.5   # subir = colores mas puros; bajar = mas mezclados
    def ajusta(v):
        if v == alto:
            return v
        prop = v / alto
        return int(alto * (prop ** fuerza))
    return "{:02X}{:02X}{:02X}".format(ajusta(r), ajusta(g), ajusta(b))

def boost(hexcolor, min_light=0.0, min_sat=0.0):
    r, g, b = (int(hexcolor[i:i+2], 16) / 255 for i in (0, 2, 4))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    r, g, b = colorsys.hls_to_rgb(h, max(l, min_light), max(s, min_sat))
    return "{:02X}{:02X}{:02X}".format(int(r*255), int(g*255), int(b*255))

def main():
    try:
        p = read_palette()
    except FileNotFoundError:
        print(f"falta {PALETTE} — corre: noctalia msg templates-apply", file=sys.stderr)
        return 1
    pri = boost(p.get("PRIMARY", "FFFFFF"))
    sec = boost(p.get("SECONDARY", p.get("PRIMARY", "FFFFFF")))
    ter = boost(p.get("TERTIARY", p.get("PRIMARY", "FFFFFF")))
    def swap_rg(h):
        return h[2:4] + h[0:2] + h[4:6]

    zonas = Z_TEC + [Z_LAT_IZQ, Z_LAT_DER, Z_MACROS, Z_LOGO, Z_LETRAS]
    pairs = [(z, pri) for z in zonas]
    pairs = [(z, calibrar(col, z)) for z, col in pairs]
    if "--test" in sys.argv:
        for z, c in pairs: print(f"  0x{z:04X} = #{c}")
        return 0
    r = subprocess.run([ALIENFX] + [f"0x{z:X}={c}" for z, c in pairs],
                       capture_output=True, text=True)
    if r.returncode: print(r.stderr.strip(), file=sys.stderr)
    return r.returncode

sys.exit(main())
