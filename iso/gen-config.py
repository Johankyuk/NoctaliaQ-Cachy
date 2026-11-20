import json, sys
from pathlib import Path

here = Path(sys.argv[1])
out = Path(sys.argv[2])


def read_list(name):
    pkgs = []
    for line in (here / name).read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            pkgs.extend(line.split())
    return pkgs


pkgs = []
for p in read_list("target-packages.txt") + read_list("aur-packages.txt"):
    if p not in pkgs and p not in ("base", "linux", "linux-firmware"):
        pkgs.append(p)

cfg = {
    "version": "4.5",
    "archinstall-language": "Spanish",
    "hostname": "porphyx",
    "kernels": ["linux"],
    "ntp": True,
    "timezone": "America/Mexico_City",
    "swap": {"enabled": True, "algorithm": "zstd"},
    "bootloader_config": {"bootloader": "Systemd-boot", "uki": False, "removable": False},
    "locale_config": {"kb_layout": "la-latin1", "sys_enc": "UTF-8", "sys_lang": "es_MX"},
    "network_config": {"type": "nm"},
    "mirror_config": {
        "optional_repositories": ["multilib"],
        "custom_servers": [{"url": "file:///opt/noctaliaq-mirror/$repo/os/$arch"}],
        "custom_repositories": [
            {
                "name": "noctaliaq",
                "url": "file:///opt/noctaliaq/repo",
                "sign_check": "Optional",
                "sign_option": "TrustAll",
            }
        ]
    },
    "packages": pkgs,
    "services": ["bluetooth", "keyd", "switcheroo-control", "power-profiles-daemon", "upower"],
}
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(cfg, indent=2) + "\n")
print("config escrita:", out, "-", len(pkgs), "paquetes")
