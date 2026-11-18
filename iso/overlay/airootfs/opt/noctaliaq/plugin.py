import shutil
from pathlib import Path

SRC = Path("/opt/noctaliaq")


class Plugin:
    def on_genfstab(self, installation):
        target = Path(installation.target)
        shutil.copytree(SRC, target / "opt" / "noctaliaq", symlinks=True, dirs_exist_ok=True)
        prof = target / "etc" / "profile.d"
        prof.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SRC / "firstlogin.sh", prof / "noctaliaq-firstlogin.sh")
        return None
