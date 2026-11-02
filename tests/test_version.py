import re
from pathlib import Path

import paddws

ROOT = Path(__file__).resolve().parent.parent
CHANGELOG = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
PRERELEASE = "-" in paddws.__version__


def test_version_is_semver():
    assert re.fullmatch(r"\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?", paddws.__version__)


def test_python_and_rust_share_the_version():
    """Python, Rust e core MiSTer escono nella stessa release (vedi tools/release.py)."""
    cargo = (ROOT / "rust" / "Cargo.toml").read_text(encoding="utf-8")
    assert re.search(r'^version = "([^"]+)"$', cargo, flags=re.M).group(1) == paddws.__version__


def test_changelog_documents_current_version():
    """Ogni versione definitiva ha la sua sezione nel changelog; le anteprime stanno in "Non rilasciato"."""
    if not PRERELEASE:
        assert f"## [{paddws.__version__}] - " in CHANGELOG


def test_changelog_has_unreleased_section_first():
    sections = re.findall(r"^## \[([^\]]+)\]", CHANGELOG, flags=re.M)
    assert sections[0] == "Non rilasciato"
    if not PRERELEASE:
        assert sections[1] == paddws.__version__
