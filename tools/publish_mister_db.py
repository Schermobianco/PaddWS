"""Pubblica il core MiSTer come database di Downloader, per scaricarlo con update_all.

Chi ha un MiSTer aggiunge in fondo a /media/fat/downloader.ini:

    [Schermobianco/PaddWS]
    db_url = https://raw.githubusercontent.com/Schermobianco/PaddWS/db/db.json.zip

e update_all (o downloader) installa e aggiorna PADD WS in _Arcade, togliendo il .rbf vecchio.

Lo script prende dist/PaddWS_MiSTer_*.zip (build_onforge.bat) e lo pubblica nel ramo db di GitHub:
un commit con i file del core alle stesse posizioni che hanno sulla SD, e sopra un commit che
aggiunge db.json.zip (formato: docs/custom-databases.md di MiSTer-devel/Downloader_MiSTer). Il
database punta ai file del primo commit, che non cambia più (come fa il modello DB-Template_MiSTer).
Il ramo riparte da zero a ogni pubblicazione (push --force): le versioni vecchie non pesano sul
repository. Il ramo attuale e i file di lavoro non cambiano.

Lo chiama build_onforge.bat -Publish/-PublishOnly dopo la release; si può lanciare anche da solo.
Uso:  .venv\\Scripts\\python tools\\publish_mister_db.py [--dry-run]
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
# non cambiarlo mai: Downloader lega a questo nome i file che ha installato (e la loro pulizia),
# e la sezione di downloader.ini deve essere uguale
DB_ID = "Schermobianco/PaddWS"
RAW = "https://raw.githubusercontent.com/Schermobianco/PaddWS"
BRANCH = "db"
DB_URL = f"{RAW}/{BRANCH}/db.json.zip"


def git(*args: str, env: dict | None = None) -> str:
    out = subprocess.run(["git", "-c", "core.autocrlf=false", *args], cwd=ROOT, env=env,
                         check=True, capture_output=True, text=True)
    return out.stdout.strip()


def tree_of(folder: Path) -> str:
    """L'albero git del contenuto di folder, con un indice temporaneo (l'indice vero non cambia)."""
    with tempfile.TemporaryDirectory() as tmp:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(tmp) / "index"))
        git(f"--work-tree={folder}", "add", "-A", ".", env=env)
        return git("write-tree", env=env)


def database(files_dir: Path, base_url: str) -> dict:
    files, folders = {}, {}
    for p in sorted(files_dir.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(files_dir).as_posix()
        data = p.read_bytes()
        files[rel] = {"hash": hashlib.md5(data).hexdigest(), "size": len(data)}
        parent = Path(rel).parent
        while parent != Path("."):
            folders[parent.as_posix()] = {}
            parent = parent.parent
    return {"v": 1, "db_id": DB_ID, "db_url": DB_URL, "base_files_url": base_url,
            "timestamp": int(time.time()), "files": files, "folders": dict(sorted(folders.items()))}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dry-run", action="store_true", help="prepara i commit ma non fa il push")
    args = ap.parse_args()

    zips = sorted(DIST.glob("PaddWS_MiSTer_*.zip"))
    if len(zips) != 1:
        sys.exit(f"ERRORE: in {DIST} serve uno e un solo PaddWS_MiSTer_*.zip (trovati {len(zips)})")
    work = Path(tempfile.mkdtemp(prefix="paddws-db-"))
    try:
        files_dir = work / "sd"
        with zipfile.ZipFile(zips[0]) as z:
            z.extractall(files_dir)
        day = zips[0].stem.split("_")[-1]          # la data del .rbf

        # 1) i file del core, alle posizioni della SD
        files_commit = git("commit-tree", tree_of(files_dir), "-m", f"Core MiSTer {day}")
        db = database(files_dir, f"{RAW}/{files_commit}/")

        # 2) sopra, il database compresso
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("db.json", json.dumps(db, indent=2) + "\n")
        (files_dir / "db.json.zip").write_bytes(buf.getvalue())
        db_commit = git("commit-tree", tree_of(files_dir), "-p", files_commit,
                        "-m", f"Database di Downloader per il core MiSTer {day}")
        print(f"{len(db['files'])} file, core {day}: commit {db_commit[:7]} (file in {files_commit[:7]})")
        if args.dry_run:
            print("--dry-run: niente push")
            return
        git("push", "-q", "--force", "origin", f"{db_commit}:refs/heads/{BRANCH}")
        print(f"ramo {BRANCH} pubblicato: {DB_URL}")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
