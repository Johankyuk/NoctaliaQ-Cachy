#!/usr/bin/env python3
"""
alienfx.py - Control RGB para Alienware 17 R4 (AW1517, 187c:0530)

Standalone: solo necesita pyusb. Sin daemon, sin Pyro, sin systemd.
Protocolo extraido de AKBL (GPLv3) - perfil Alienware17R4.ini.

Uso:
    sudo ./alienfx.py --list
    sudo ./alienfx.py teclado=FF0000
    sudo ./alienfx.py teclado-izq=FF0000 teclado-der=0000FF barra=00FF00
    sudo ./alienfx.py todo=8000FF
    sudo ./alienfx.py --off
"""

import sys
import time
import argparse

import usb.core
import usb.util

VENDOR_ID = 0x187C
PRODUCT_ID = 0x0530

# --- Control transfer (Driver.py de AKBL) ---
SEND_REQUEST_TYPE = 0x21
SEND_REQUEST = 0x09
SEND_VALUE = 0x0202
SEND_INDEX = 0x00

READ_REQUEST_TYPE = 0xA1
READ_REQUEST = 0x01
READ_VALUE = 0x0101
READ_INDEX = 0x00
READ_LENGTH = 64  # bMaxPacketSize0 del device; pedir menos = Errno 75 Overflow

# --- Protocolo (seccion COMMON del .ini) ---
DATA_LENGTH = 9
START_BYTE = 0x02
FILL_BYTE = 0x00

STATE_BUSY = 17
STATE_READY = 16
STATE_UNKNOWN_COMMAND = 18

CMD_SET_COLOR = 3
CMD_LOOP_BLOCK_END = 4
CMD_TRANSMIT_EXECUTE = 5
CMD_GET_STATUS = 6
CMD_RESET = 7

RESET_ALL_LIGHTS_OFF = 3
RESET_ALL_LIGHTS_ON = 4

# --- Zonas (secciones [REGION ...] del .ini, campo BLOCK) ---
ZONES = {
    "teclado-izq":        (0x001, "Teclado: cuadrante izquierdo"),
    "teclado-centro-izq": (0x004, "Teclado: centro-izquierdo"),
    "teclado-centro-der": (0x002, "Teclado: centro-derecho"),
    "teclado-der":        (0x008, "Teclado: cuadrante derecho"),
    "altavoz-izq":        (0x020, "Altavoz izquierdo"),
    "altavoz-der":        (0x040, "Altavoz derecho"),
    "barra":              (0x1C00, "Media bar / tiras laterales de la pantalla"),
    "trackpad":           (0x200, "Borde del trackpad"),
    "alienhead":          (0x080, "Cabeza Alienware (tapa)"),
    "logo":               (0x100, "Logo Alienware"),
    "power":              (0x2000, "Boton de encendido"),
}

# Atajos: expanden a varias zonas reales
ALIASES = {
    "teclado": ["teclado-izq", "teclado-centro-izq",
                "teclado-centro-der", "teclado-der"],
    "altavoces": ["altavoz-izq", "altavoz-der"],
    "todo": ["teclado-izq", "teclado-centro-izq", "teclado-centro-der",
             "teclado-der", "altavoz-izq", "altavoz-der", "barra",
             "trackpad", "alienhead", "logo", "power"],
}


def split_area_id(area_id):
    """0x1C00 -> (0x00, 0x1C, 0x00). Tres bytes big-endian."""
    b0 = area_id // 65536
    b1 = area_id // 256 - b0 * 256
    b2 = area_id - b0 * 65536 - b1 * 256
    return b0, b1, b2


def pack_color(hex_color):
    """
    El AW1517 usa 4 bits por canal (4096 colores, no 16M).
    'FF8000' -> (0xF8, 0x00)
    """
    c = hex_color.replace("#", "").strip()
    if len(c) != 6:
        raise ValueError(f"color invalido: {hex_color!r} (se espera RRGGBB)")
    # Este firmware usa un byte completo por canal en cmd[6..8].
    return int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)


def make_cmd(*payload):
    """Arma un paquete de 9 bytes: start_byte + payload + relleno."""
    cmd = [FILL_BYTE] * DATA_LENGTH
    cmd[0] = START_BYTE
    for i, value in enumerate(payload, start=1):
        cmd[i] = value
    return cmd


class AlienFX:
    def __init__(self, verbose=False):
        self.verbose = verbose
        self.dev = usb.core.find(idVendor=VENDOR_ID, idProduct=PRODUCT_ID)
        if self.dev is None:
            raise RuntimeError(
                f"No encontre el controlador {VENDOR_ID:04x}:{PRODUCT_ID:04x}. "
                "Revisa 'lsusb' y que corras como root."
            )

    def _log(self, msg):
        if self.verbose:
            print(f"  [debug] {msg}", file=sys.stderr)

    def take_over(self):
        """Reclama el device. El AW1517 no es HID, normalmente no hay driver adherido."""
        try:
            self.dev.detach_kernel_driver(0)
            self._log("kernel driver desconectado")
        except (usb.core.USBError, NotImplementedError) as e:
            self._log(f"sin kernel driver que desconectar ({e})")
        try:
            self.dev.set_configuration()
        except usb.core.USBError as e:
            self._log(f"set_configuration omitido ({e})")

    def write(self, cmd):
        self._log(f"-> {' '.join(f'{b:02x}' for b in cmd)}")
        return self.dev.ctrl_transfer(
            SEND_REQUEST_TYPE, SEND_REQUEST, SEND_VALUE, SEND_INDEX, cmd
        )

    def read_status(self):
        try:
            msg = self.dev.ctrl_transfer(
                READ_REQUEST_TYPE, READ_REQUEST, READ_VALUE, READ_INDEX, READ_LENGTH
            )
        except usb.core.USBError as e:
            self._log(f"read fallo: {e}")
            return None
        self._log(f"<- {' '.join(f'{b:02x}' for b in msg[:4])} ...")
        return msg[0] if len(msg) else None

    def wait_ready(self, timeout=0.4):
        """Poll de estado. Si el device nunca contesta, seguimos igual."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            self.write(make_cmd(CMD_GET_STATUS))
            status = self.read_status()
            if status == STATE_READY:
                self._log("device listo")
                return True
            if status == STATE_UNKNOWN_COMMAND:
                self._log("device reporto comando desconocido")
            time.sleep(0.02)
        self._log("timeout esperando READY, sigo de todos modos")
        return False

    def reset(self, mode=RESET_ALL_LIGHTS_ON):
        self.write(make_cmd(CMD_RESET, mode))
        time.sleep(0.03)

    def set_zones(self, assignments):
        """assignments: lista de (area_id, 'RRGGBB')"""
        self.take_over()
        self.reset(RESET_ALL_LIGHTS_ON)
        self.wait_ready()

        for area_id, color in assignments:
            b0, b1, b2 = split_area_id(area_id)
            cr, cg, cb = pack_color(color)
            self.write(make_cmd(CMD_SET_COLOR, 1, b0, b1, b2, cr, cg, cb))

        self.write(make_cmd(CMD_LOOP_BLOCK_END))
        self.write(make_cmd(CMD_TRANSMIT_EXECUTE))

    def all_off(self):
        self.take_over()
        self.reset(RESET_ALL_LIGHTS_OFF)
        self.wait_ready()
        self.write(make_cmd(CMD_TRANSMIT_EXECUTE))


def resolve(name):
    """Devuelve la lista de zonas reales para un nombre (zona o alias)."""
    if name in ALIASES:
        return ALIASES[name]
    if name in ZONES:
        return [name]
    raise ValueError(f"zona desconocida: {name!r} (usa --list para ver las validas)")


def print_zones():
    print("Zonas:")
    for name, (area_id, desc) in ZONES.items():
        print(f"  {name:<20} 0x{area_id:04X}  {desc}")
    print("\nAtajos:")
    for name, members in ALIASES.items():
        print(f"  {name:<20} -> {', '.join(members)}")


def main():
    parser = argparse.ArgumentParser(
        description="Control RGB para Alienware 17 R4 (AW1517)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Ejemplo:\n  sudo ./alienfx.py teclado=FF0000 barra=0000FF trackpad=00FF00",
    )
    parser.add_argument("assignments", nargs="*", metavar="ZONA=RRGGBB",
                        help="asignaciones de color")
    parser.add_argument("--list", action="store_true", help="lista las zonas y sale")
    parser.add_argument("--off", action="store_true", help="apaga todas las luces")
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="muestra los paquetes USB en crudo")
    args = parser.parse_args()

    if args.list:
        print_zones()
        return 0

    if not args.off and not args.assignments:
        parser.print_help()
        return 1

    try:
        fx = AlienFX(verbose=args.verbose)

        if args.off:
            fx.all_off()
            print("Luces apagadas.")
            return 0

        pairs = []
        for item in args.assignments:
            if "=" not in item:
                raise ValueError(f"formato invalido: {item!r} (se espera ZONA=RRGGBB)")
            name, color = item.split("=", 1)
            pack_color(color)  # valida temprano
            name = name.strip()
            if name.lower().startswith("0x"):
                pairs.append((int(name, 16), color))
            else:
                for zone in resolve(name):
                    pairs.append((ZONES[zone][0], color))

        fx.set_zones(pairs)
        print(f"Aplicado a {len(pairs)} zona(s).")
        return 0

    except (usb.core.USBError, RuntimeError, ValueError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
