__archinstall__version__ = 99.0
import re
import shutil
from pathlib import Path

SRC = Path("/opt/porphyx")

MOTD = (
    "Porphyx Linux\n\n"
    "Base instalada. Para instalar el escritorio (Umbriel, Noctalia, Luciole y greeter),\n"
    "conectate a internet (nmtui) y ejecuta:\n\n"
    "    porphyx setup\n\n"
)


class Plugin:
    def on_genfstab(self, installation):
        target = Path(installation.target)
        bindir = target / "usr" / "local" / "bin"
        bindir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SRC / "porphyx", bindir / "porphyx")
        (bindir / "porphyx").chmod(0o755)
        (target / "etc").mkdir(parents=True, exist_ok=True)
        (target / "etc" / "motd").write_text(MOTD)
        issue = Path("/etc/issue")
        if issue.exists():
            shutil.copy2(issue, target / "etc" / "issue")
        osr = Path("/etc/os-release")
        if osr.exists():
            dest = target / "etc" / "os-release"
            if dest.is_symlink() or dest.exists():
                dest.unlink()
            shutil.copy2(osr, dest)
        entries = target / "boot" / "loader" / "entries"
        if entries.is_dir():
            for entry in entries.glob("*.conf"):
                text = entry.read_text()
                renamed = re.sub(r"^(title\s+)Arch Linux(?: \(linux\))?", r"\1Porphyx Linux", text, flags=re.M)  # KYU-BRAND2
                if renamed == text:
                    continue
                entry.write_text(renamed)
        ff = Path("/root/.config/fastfetch")
        if ff.is_dir():
            fdest = target / "etc" / "xdg" / "fastfetch"
            fdest.mkdir(parents=True, exist_ok=True)
            for fl in ff.iterdir():
                if fl.is_file():
                    shutil.copy2(fl, fdest / fl.name)
            fcfg = fdest / "config.jsonc"
            if fcfg.exists():
                fcfg.write_text(fcfg.read_text().replace("/root/.config/fastfetch/", "/etc/xdg/fastfetch/"))
        return None
