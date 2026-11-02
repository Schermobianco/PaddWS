"""Percorsi su disco, indipendenti dalla directory di lavoro corrente."""

import sys
from pathlib import Path

# PyInstaller estrae i dati inclusi sotto sys._MEIPASS
ROOT = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent.parent))
ASSETS = ROOT / "assets"
FONTS = ASSETS / "fonts"
IMAGES = ASSETS / "images"
# effetti della versione Python (tools/gen_sounds.py e tools/gen_coin_sound.py): li usa solo lei
SOUNDS = ROOT / "paddws" / "sounds"
ICONS = ASSETS / "icons"
ATTRACT = ASSETS / "attract"
DEFAULT_CONFIG = ROOT / "padd_config.json"


def migrate_old_name(path: Path, old_name: str) -> None:
    """Prima del cambio di nome il file si chiamava `old_name`: se c'è ancora solo quello, lo rinomina."""
    old = path.with_name(old_name)
    if not path.exists() and old.exists():
        try:
            old.rename(path)
        except OSError:
            pass
