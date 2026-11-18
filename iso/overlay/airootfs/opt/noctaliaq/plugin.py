__archinstall__version__ = 99.0
import shutil
from pathlib import Path

SRC = Path("/opt/noctaliaq")


def dedupe_section(path, name):
    """Deja una sola seccion [name] en pacman.conf (archinstall la escribe en el live y otra vez en el destino)."""
    lines = path.read_text().splitlines(keepends=True)
    out = []
    seen = False
    skipping = False
    for line in lines:
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            skipping = False
            if s[1:-1] == name:
                if seen:
                    skipping = True
                seen = True
        if not skipping:
            out.append(line)
    path.write_text("".join(out))


class Plugin:
    def on_genfstab(self, installation):
        target = Path(installation.target)
        shutil.copytree(SRC, target / "opt" / "noctaliaq", symlinks=True, dirs_exist_ok=True)
        prof = target / "etc" / "profile.d"
        prof.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SRC / "firstlogin.sh", prof / "noctaliaq-firstlogin.sh")
        conf = target / "etc" / "pacman.conf"
        if conf.exists():
            dedupe_section(conf, "noctaliaq")
        issue = Path("/etc/issue")
        if issue.exists():
            shutil.copy2(issue, target / "etc" / "issue")
        return None
