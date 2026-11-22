"""Server locale per l'editor di immagini del C64 (tools/c64_editor.html).

Serve la pagina e legge e scrive i PNG del repository, così l'editor funziona anche dove il
browser non lascia aprire e salvare file: nel Simple Browser di VS Code e nelle altre anteprime
incorporate. Ascolta solo su 127.0.0.1; scrive solo file .png dentro il repository, e solo con
l'intestazione X-C64Edit (una pagina di un altro sito non la può mandare senza un preflight, a cui
il server non risponde).

Uso:  .venv\\Scripts\\python tools\\c64_editor.py [--port 8064] [--no-browser]
Poi in VS Code: Ctrl+Maiusc+P, "Simple Browser: Show", http://127.0.0.1:8064/ (oppure il browser
che si apre da solo).
"""

from __future__ import annotations

import argparse
import json
import os
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent.parent
PAGE = ROOT / "tools" / "c64_editor.html"
SKIP = {".git", ".venv", "target", "node_modules", "dist", "build", "__pycache__", ".pytest_cache"}
READABLE = {".png", ".gif", ".bmp", ".jpg", ".jpeg", ".webp"}
MAX_BODY = 20 * 1024 * 1024
PNG_SIG = b"\x89PNG\r\n\x1a\n"


def repo_path(rel: str) -> Path | None:
    """Il percorso dentro il repository, o None se ne esce."""
    p = (ROOT / rel).resolve()
    return p if p.is_relative_to(ROOT) else None


def list_images(every: bool) -> list[str]:
    """I PNG del repository; con every anche le altre immagini (per Importa e converti)."""
    ext = READABLE if every else {".png"}
    out = []
    for dirpath, dirs, files in os.walk(ROOT):
        dirs[:] = sorted(d for d in dirs if d not in SKIP and not d.startswith("."))
        for f in sorted(files):
            if Path(f).suffix.lower() in ext:
                out.append(Path(dirpath, f).relative_to(ROOT).as_posix())
        if len(out) > 5000:
            break
    return out


class Handler(BaseHTTPRequestHandler):
    server_version = "c64edit"

    def log_message(self, fmt, *args):  # solo gli errori
        if args and str(args[1]).startswith(("4", "5")):
            super().log_message(fmt, *args)

    def send(self, code: int, body: bytes, ctype: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def json(self, obj, code: int = 200) -> None:
        self.send(code, json.dumps(obj).encode("utf-8"), "application/json; charset=utf-8")

    def host_ok(self) -> bool:
        # contro il DNS rebinding: solo richieste rivolte a questo server
        host = (self.headers.get("Host") or "").split(":")[0]
        if host in ("127.0.0.1", "localhost"):
            return True
        self.json({"error": "host non ammesso"}, 403)
        return False

    def do_GET(self):
        if not self.host_ok():
            return
        url = urlparse(self.path)
        q = parse_qs(url.query)
        if url.path in ("/", "/index.html", "/c64_editor.html"):
            self.send(200, PAGE.read_bytes(), "text/html; charset=utf-8")
        elif url.path == "/api/ping":
            self.json({"root": str(ROOT), "name": ROOT.name})
        elif url.path == "/api/files":
            self.json({"files": list_images(q.get("all", ["0"])[0] == "1")})
        elif url.path == "/api/file":
            p = repo_path(q.get("path", [""])[0])
            if not p or p.suffix.lower() not in READABLE or not p.is_file():
                self.json({"error": "file non trovato"}, 404)
                return
            self.send(200, p.read_bytes(), "application/octet-stream")
        else:
            self.json({"error": "non trovato"}, 404)

    def do_PUT(self):
        if not self.host_ok():
            return
        url = urlparse(self.path)
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0 or n > MAX_BODY:
            self.close_connection = True
            self.json({"error": "dimensione non valida"}, 400)
            return
        body = self.rfile.read(n)          # letto sempre: se no il client trova la connessione chiusa
        if url.path != "/api/file" or self.headers.get("X-C64Edit") != "1":
            self.json({"error": "richiesta non ammessa"}, 403)
            return
        rel = parse_qs(url.query).get("path", [""])[0]
        p = repo_path(rel)
        if not p or p.suffix.lower() != ".png" or p == ROOT:
            self.json({"error": "si scrivono solo file .png dentro il repository"}, 400)
            return
        if not p.parent.is_dir():
            self.json({"error": f"la cartella {p.parent.relative_to(ROOT).as_posix()} non esiste"}, 400)
            return
        if not body.startswith(PNG_SIG):
            self.json({"error": "non è un PNG"}, 400)
            return
        tmp = p.with_suffix(".png.tmp")
        tmp.write_bytes(body)
        os.replace(tmp, p)
        print(f"salvato {p.relative_to(ROOT).as_posix()}")
        self.json({"ok": True, "path": p.relative_to(ROOT).as_posix()})


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--port", type=int, default=8064)
    ap.add_argument("--no-browser", action="store_true", help="non aprire il browser")
    args = ap.parse_args()
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://127.0.0.1:{args.port}/"
    print(f"Editor C64: {url}  (in VS Code: Simple Browser: Show). Ctrl+C per fermarlo.")
    if not args.no_browser:
        webbrowser.open(url)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
