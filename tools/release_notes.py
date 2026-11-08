"""Note di una release di PADD WS su GitHub, prese dal CHANGELOG.

Uso:
    python tools/release_notes.py X.Y.Z[-beta.N] [--since TAG] [--output FILE]

Versione definitiva: la sua sezione del changelog. Anteprima (-alpha.N, -beta.N): le voci di
"Non rilasciato" nuove o cambiate rispetto al tag precedente, perché tools/release.py lascia lì le
voci delle anteprime fino alla versione definitiva; con --since il confronto parte da un altro tag
(per esempio quando l'anteprima precedente non è stata pubblicata). Senza un tag precedente le note
rimandano al changelog invece di copiarlo tutto. In testa il link per giocare online e quello
alla tabella dei pacchetti, in fondo i link al changelog completo e al confronto tra i tag.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHANGELOG = "CHANGELOG.md"
REPO_URL = "https://github.com/Schermobianco/PaddWS"
PAGES_URL = "https://schermobianco.github.io/PaddWS/"
UNRELEASED = "Non rilasciato"


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True,
                          encoding="utf-8").stdout


def section(text: str, name: str) -> str | None:
    """Il corpo della sezione `## [name]` (fino alla sezione successiva), o None se non c'è."""
    match = re.search(rf"^## \[{re.escape(name)}\][^\n]*\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    return match.group(1) if match else None


def entries(body: str) -> list[tuple[str, str]]:
    """Le voci di una sezione come (sottosezione, testo): una voce è una riga "- " di primo
    livello con le sue righe rientrate."""
    result: list[tuple[str, str]] = []
    heading = ""
    current: list[str] = []

    def close() -> None:
        if current:
            result.append((heading, "\n".join(current).rstrip()))
            current.clear()

    for line in body.splitlines():
        if line.startswith("### "):
            close()
            heading = line[4:].strip()
        elif line.startswith("- "):
            close()
            current.append(line)
        elif current and (line.startswith(" ") or not line.strip()):
            current.append(line)
        else:
            close()
    close()
    return result


def normalized(entry: str) -> str:
    return " ".join(entry.split())


def render(items: list[tuple[str, str]]) -> str:
    """Le voci raggruppate per sottosezione, nell'ordine in cui compaiono."""
    groups: dict[str, list[str]] = {}
    for heading, entry in items:
        groups.setdefault(heading, []).append(entry)
    return "\n\n".join(f"### {heading}\n\n" + "\n".join(group) if heading else "\n".join(group)
                       for heading, group in groups.items())


def previous_tag(tag: str) -> str | None:
    try:
        return git("describe", "--tags", "--abbrev=0", "--match", "v[0-9]*", f"{tag}^").strip()
    except subprocess.CalledProcessError:
        return None


def notes(version: str, since: str | None = None) -> str:
    tag = f"v{version}"
    try:
        text = git("show", f"{tag}:{CHANGELOG}")
    except subprocess.CalledProcessError:
        sys.exit(f"Il tag {tag} non c'è: prima python tools/release.py {version}")
    previous = since or previous_tag(tag)

    if "-" not in version:
        body = section(text, version)
        if body is None:
            sys.exit(f"Sezione [{version}] non trovata nel {CHANGELOG} del tag {tag}")
        changes = render(entries(body))
    elif previous:
        current = entries(section(text, UNRELEASED) or "")
        try:
            old = git("show", f"{previous}:{CHANGELOG}")
        except subprocess.CalledProcessError:
            sys.exit(f"Il tag {previous} non c'è")
        before = {normalized(e) for _, e in entries(section(old, UNRELEASED) or "")}
        changes = render([(h, e) for h, e in current if normalized(e) not in before])
    else:
        changes = ("Prima anteprima pubblicata: tutte le modifiche sono nel changelog qui sotto. / "
                   "First published preview: all the changes are in the changelog below.")

    head = (f"**Gioca online / Play online:** <{PAGES_URL}> · "
            f"[Quale file scaricare / Which file to download]({REPO_URL}/blob/main/README.en.md#versions)")
    if not changes.strip():
        changes = "Nessuna modifica nel changelog. / No changelog entries."
    links = [f"[CHANGELOG]({REPO_URL}/blob/{tag}/{CHANGELOG})"]
    if previous:
        links.append(f"[{previous}...{tag}]({REPO_URL}/compare/{previous}...{tag})")
    since = f" (dalla / since {previous})" if previous and "-" in version else ""
    return (f"{head}\n\n## Novità / What's new{since}\n\n"
            f"*Il changelog è in italiano. / The changelog is in Italian.*\n\n"
            f"{changes}\n\n---\n\n" + " · ".join(links) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("version", help="la versione, senza la v: X.Y.Z o X.Y.Z-beta.N")
    parser.add_argument("--since", metavar="TAG", help="tag da cui contare le novità di un'anteprima")
    parser.add_argument("--output", type=Path, help="scrive le note in questo file invece che a schermo")
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    text = notes(args.version, args.since)
    if args.output:
        args.output.write_bytes(text.encode("utf-8"))
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
