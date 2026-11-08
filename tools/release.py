"""Crea una nuova versione di PADD WS (Python, Rust e core MiSTer hanno lo stesso numero).

Uso:
    python tools/release.py patch|minor|major|X.Y.Z|X.Y.Z-alpha.N [--dry-run] [--trailer TESTO]

Passi: controlla che il repository sia pulito e che il changelog abbia voci
"Non rilasciato", aggiorna `python/paddws/__init__.py`, `rust/Cargo.toml` e `rust/Cargo.lock`,
crea il commit "Versione X.Y.Z" e il tag annotato vX.Y.Z. Per una versione definitiva
sposta le voci "Non rilasciato" nella nuova sezione del changelog con la data di oggi;
le anteprime (X.Y.Z-alpha.N) le lasciano dove sono. I pacchetti li costruiscono
build_onforge.bat (in locale) o build_ongithub.bat (Action avviate sul tag). La pubblicazione resta
manuale: git push --follow-tags
"""

from __future__ import annotations

import argparse
import datetime
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSION_FILE = ROOT / "python" / "paddws" / "__init__.py"
CARGO_TOML = ROOT / "rust" / "Cargo.toml"
CARGO_LOCK = ROOT / "rust" / "Cargo.lock"
RUST_CRATES = ("paddws", "paddws-core", "paddws-trace", "paddws-c64", "paddws-mister-fw", "paddws-sid")
CHANGELOG = ROOT / "CHANGELOG.md"
REPO_URL = "https://github.com/Schermobianco/PaddWS"
UNRELEASED = "## [Non rilasciato]"

VERSION = r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?"
VERSION_RE = re.compile(rf'^__version__ = "({VERSION})"$', re.M)
CARGO_RE = re.compile(rf'^version = "({VERSION})"$', re.M)


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout


def numbers(version: str) -> tuple[int, int, int]:
    major, minor, patch = version.split("-")[0].split(".")
    return int(major), int(minor), int(patch)


def current_version() -> str:
    match = VERSION_RE.search(VERSION_FILE.read_text(encoding="utf-8"))
    if not match:
        sys.exit(f"__version__ non trovata in {VERSION_FILE}")
    cargo = CARGO_RE.search(CARGO_TOML.read_text(encoding="utf-8"))
    if not cargo or cargo.group(1) != match.group(1):
        sys.exit(f"Versioni diverse: {VERSION_FILE.name} {match.group(1)}, Cargo.toml {cargo and cargo.group(1)}")
    return match.group(1)


def next_version(current: str, bump: str) -> str:
    major, minor, patch = numbers(current)
    if bump == "major":
        return f"{major + 1}.0.0"
    if bump == "minor":
        return f"{major}.{minor + 1}.0"
    if bump == "patch":
        return f"{major}.{minor}.{patch + 1}"
    if re.fullmatch(VERSION, bump):
        if bump == current or numbers(bump) < numbers(current):
            sys.exit(f"{bump} non è successiva a {current}")
        return bump
    sys.exit(f"Incremento non valido: {bump}")


def release_changelog(text: str, old: str, new: str, today: str) -> str:
    """Sposta le voci di "Non rilasciato" nella sezione della nuova versione e aggiorna i link."""
    start = text.find(UNRELEASED)
    if start < 0:
        sys.exit(f"Sezione '{UNRELEASED}' non trovata in {CHANGELOG.name}")
    body_start = start + len(UNRELEASED)
    end = text.find("\n## ", body_start)
    body = text[body_start:end if end >= 0 else len(text)]
    if not body.strip():
        sys.exit("Nessuna voce in 'Non rilasciato': niente da rilasciare")
    if "-" in new:
        return text  # anteprima: le voci restano in "Non rilasciato" fino alla versione definitiva

    rest = text[end:] if end >= 0 else ""
    text = text[:body_start] + f"\n\n## [{new}] - {today}\n\n" + body.strip("\n") + "\n" + rest
    text = re.sub(r"^\[Non rilasciato\]: .*$", f"[Non rilasciato]: {REPO_URL}/compare/v{new}...HEAD", text, flags=re.M)
    link = f"[{new}]: {REPO_URL}/compare/v{old}...v{new}"
    return re.sub(r"^(\[Non rilasciato\]: .*)$", rf"\1\n{link}", text, count=1, flags=re.M)


def set_versions(new: str) -> None:
    VERSION_FILE.write_text(VERSION_RE.sub(f'__version__ = "{new}"', VERSION_FILE.read_text(encoding="utf-8")),
                            encoding="utf-8")
    CARGO_TOML.write_text(CARGO_RE.sub(f'version = "{new}"', CARGO_TOML.read_text(encoding="utf-8"), count=1),
                          encoding="utf-8")
    lock = CARGO_LOCK.read_text(encoding="utf-8")
    for crate in RUST_CRATES:
        lock = re.sub(rf'(name = "{crate}"\nversion = )"[^"]*"', rf'\1"{new}"', lock)
    CARGO_LOCK.write_text(lock, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("bump", help="patch, minor, major oppure una versione esplicita (anche X.Y.Z-alpha.N)")
    parser.add_argument("--dry-run", action="store_true", help="mostra cosa cambierebbe senza scrivere")
    parser.add_argument("--trailer", help="riga aggiunta in fondo al messaggio di commit")
    args = parser.parse_args()

    if git("status", "--porcelain").strip() and not args.dry_run:
        sys.exit("Ci sono modifiche non committate: completale prima del rilascio")

    old = current_version()
    new = next_version(old, args.bump)
    today = datetime.date.today().isoformat()
    changelog = release_changelog(CHANGELOG.read_text(encoding="utf-8"), old, new, today)

    print(f"PADD WS {old} -> {new} ({today})")
    if args.dry_run:
        return

    set_versions(new)
    CHANGELOG.write_text(changelog, encoding="utf-8")
    message = f"Versione {new}" + (f"\n\n{args.trailer}" if args.trailer else "")
    git("add", str(VERSION_FILE), str(CARGO_TOML), str(CARGO_LOCK), str(CHANGELOG))
    git("commit", "-q", "-m", message)
    git("tag", "-a", f"v{new}", "-m", f"PADD WS {new}")
    print(f"Creati commit e tag v{new}. Per pubblicare: git push --follow-tags")


if __name__ == "__main__":
    main()
