#!/usr/bin/env python3
"""Cattura da VICE (x64sc) lo stato e i cicli veri dei frame della versione C64.

Avvia VICE senza finestra con il monitor binario, lascia girare la cartuccia per un po' e poi, per
ogni frame, salva la memoria all'ingresso di `frame` (play.s) e la posizione del raster all'ingresso
e all'uscita. Il banco di prova (`paddws-c64 vice FILE`) riesegue ogni frame dallo stesso stato e
confronta i suoi cicli con quelli di VICE: serve a tarare il modello dei cicli rubati dal VIC-II
(badline e sprite), vedi rust/c64/src/cpu6502.rs.

Con --frametest conta invece i frame oltre il tempo di una build di prova con FRAMETEST
(c64/build.ps1 -Define ...,FRAMETEST): VICE gira per --cycles cicli e a ogni frame contato da
ft_check (play.s) lo script annota la scena (`state`) e la riga del raster; alla fine stampa quanti
sono, per scena.

Uso:
  python tools/c64_vice_frames.py OUT.bin [--prg NOME] [--ntsc] [--wait SECONDI] [--frames N]
                                          [--every K] [--state S] [--port P]
  python tools/c64_vice_frames.py --frametest [--prg NOME] [--ntsc] [--cycles N] [--port P]
  --prg     nome della build (c64/build.ps1 -Name ...), "paddws" se manca
  --wait    secondi di orologio da lasciar passare in warp prima di catturare (10)
  --frames  frame da catturare (300)
  --every   uno ogni K frame (1)
  --state   solo i frame con questo valore di `state` (7 = partita); -1 tutti

Formato di OUT.bin: "PWSF", un byte NTSC, due byte per l'indirizzo di `frame`; poi per ogni frame
riga e ciclo del raster all'ingresso e all'uscita (4 x u16), interrupt passati durante il frame
(u16), A X Y SP P e un byte libero, 64 KB di memoria vista dal processore, 4 KB di RAM sotto
l'I/O, e gli stessi 68 KB all'uscita.
"""

import argparse
import os
import socket
import struct
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMPILERS = os.environ.get("PADDWS_COMPILERS", r"C:\DEV\@Compiler")


class Monitor:
    """Monitor binario di VICE (API 2)."""

    def __init__(self, port):
        deadline = time.time() + 30
        while True:
            try:
                self.sock = socket.create_connection(("127.0.0.1", port), timeout=2)
                break
            except OSError:
                if time.time() > deadline:
                    raise
                time.sleep(0.2)
        self.sock.settimeout(60)
        self.next_id = 1
        self.events = []

    def _read(self, n):
        buf = b""
        while len(buf) < n:
            part = self.sock.recv(n - len(buf))
            if not part:
                raise ConnectionError("VICE ha chiuso il monitor")
            buf += part
        return buf

    def _message(self):
        head = self._read(12)
        stx, _api, length, kind, error, req = struct.unpack("<BBIBBI", head)
        if stx != 2:
            raise ValueError("risposta del monitor non valida")
        return kind, error, req, self._read(length)

    def command(self, kind, body=b""):
        """Manda un comando e restituisce il corpo della sua risposta; gli eventi arrivati
        intanto restano in `events`."""
        req = self.next_id
        self.next_id += 1
        self.sock.sendall(struct.pack("<BBIIB", 2, 2, len(body), req, kind) + body)
        while True:
            k, error, r, data = self._message()
            if r == req:
                if error:
                    raise RuntimeError(f"comando {kind:#x}: errore {error:#x}")
                return data
            self.events.append((k, data))

    def wait_checkpoint(self):
        """Aspetta un checkpoint raggiunto; restituisce il suo numero."""
        while True:
            while self.events:
                k, data = self.events.pop(0)
                if k == 0x11 and data[4]:
                    return struct.unpack_from("<I", data)[0]
            k, _error, _r, data = self._message()
            self.events.append((k, data))

    def banks(self):
        data = self.command(0x82)
        out, p = {}, 2
        for _ in range(struct.unpack_from("<H", data)[0]):
            size = data[p]
            bank = struct.unpack_from("<H", data, p + 1)[0]
            n = data[p + 3]
            out[data[p + 4:p + 4 + n].decode()] = bank
            p += 1 + size
        return out

    def register_ids(self):
        data = self.command(0x83, b"\x00")
        out, p = {}, 2
        for _ in range(struct.unpack_from("<H", data)[0]):
            size = data[p]
            n = data[p + 3]
            out[data[p + 4:p + 4 + n].decode()] = data[p + 1]
            p += 1 + size
        return out

    def registers(self):
        data = self.command(0x31, b"\x00")
        out, p = {}, 2
        for _ in range(struct.unpack_from("<H", data)[0]):
            size = data[p]
            out[data[p + 1]] = struct.unpack_from("<H", data, p + 2)[0]
            p += 1 + size
        return out

    def memory(self, start, end, bank):
        data = self.command(0x01, struct.pack("<BHHBH", 0, start, end, 0, bank))
        return data[2:]

    def checkpoint(self, addr):
        data = self.command(0x12, struct.pack("<HHBBBB", addr, addr, 1, 1, 4, 0))
        return struct.unpack_from("<I", data)[0]

    def resume(self):
        self.command(0xAA)

    def quit(self):
        try:
            self.command(0xBB)
        except (OSError, RuntimeError, ConnectionError):
            pass


def labels(path):
    out = []
    with open(path, encoding="ascii", errors="replace") as f:
        for line in f:
            parts = line.split()
            if len(parts) == 3 and parts[0] == "al":
                out.append((parts[2].lstrip("."), int(parts[1], 16)))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("out", nargs="?")
    ap.add_argument("--frametest", action="store_true")
    ap.add_argument("--cycles", type=int, default=300_000_000)
    ap.add_argument("--prg", default="paddws")
    ap.add_argument("--ntsc", action="store_true")
    ap.add_argument("--wait", type=float, default=10)
    ap.add_argument("--frames", type=int, default=300)
    ap.add_argument("--every", type=int, default=1)
    ap.add_argument("--state", type=int, default=7)
    ap.add_argument("--port", type=int, default=6502)
    args = ap.parse_args()

    build = os.path.join(ROOT, "c64", "build", "ntsc" if args.ntsc else "")
    names = labels(os.path.join(build, args.prg + ".lbl"))
    one = dict(names)
    # `frame` di play.s: l'ultima etichetta con quel nome prima di scene_done
    frame = max(a for n, a in names if n == "frame" and a < one["scene_done"])
    with open(os.path.join(build, args.prg + ".prg"), "rb") as f:
        prg = f.read()[2:]
    # il ritorno in play_main: l'istruzione dopo `jsr frame`
    at = prg.find(bytes([0x20, frame & 0xFF, frame >> 8]), one["play_main"] - 0x0801)
    leave = 0x0801 + at + 3
    state_at, flag_at = one["state"], one["frame_flag"]

    vice = os.path.join(COMPILERS, "vice", "bin", "x64sc.exe")
    cmd = [vice, "-default", "-warp", "-sounddev", "dummy"]
    if args.ntsc:
        cmd += ["-model", "ntsc"]
    cmd += ["-binarymonitor", "-binarymonitoraddress", f"ip4://127.0.0.1:{args.port}",
            "-cartcrt", os.path.join(build, args.prg + ".crt")]
    if args.frametest:
        return frametest(args, cmd, names)
    if not args.out:
        ap.error("manca OUT.bin")
    hide = None
    if os.name == "nt":
        hide = subprocess.STARTUPINFO()
        hide.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        hide.wShowWindow = 0
    proc = subprocess.Popen(cmd, startupinfo=hide, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    mon = None
    try:
        mon = Monitor(args.port)
        time.sleep(args.wait)
        banks = mon.banks()
        ids = mon.register_ids()
        lin, cyc = ids["LIN"], ids["CYC"]
        enter_cp = mon.checkpoint(frame)
        leave_cp = mon.checkpoint(leave)
        done, seen = 0, 0
        with open(args.out, "wb") as out:
            out.write(b"PWSF" + bytes([1 if args.ntsc else 0]) + struct.pack("<H", frame))
            mon.resume()
            while done < args.frames:
                if mon.wait_checkpoint() != enter_cp:
                    mon.resume()
                    continue
                seen += 1
                r0 = mon.registers()
                cpu0 = mon.memory(0, 0xFFFF, banks["cpu"])
                take = seen % args.every == 0 and (args.state < 0 or cpu0[state_at] == args.state)
                if not take:
                    mon.resume()
                    continue
                ram0 = mon.memory(0xD000, 0xDFFF, banks["ram"])
                mon.resume()
                while mon.wait_checkpoint() != leave_cp:
                    mon.resume()
                r1 = mon.registers()
                cpu1 = mon.memory(0, 0xFFFF, banks["cpu"])
                ram1 = mon.memory(0xD000, 0xDFFF, banks["ram"])
                out.write(struct.pack("<HHHHH", r0[lin], r0[cyc], r1[lin], r1[cyc], cpu1[flag_at]))
                out.write(bytes([r0[ids["A"]] & 0xFF, r0[ids["X"]] & 0xFF, r0[ids["Y"]] & 0xFF,
                                 r0[ids["SP"]] & 0xFF, r0[ids["FL"]] & 0xFF, 0]))
                out.write(cpu0 + ram0 + cpu1 + ram1)
                done += 1
                mon.resume()
        print(f"{args.out}: {done} frame su {seen} (frame a ${frame:04X}, uscita a ${leave:04X})")
    finally:
        if mon:
            mon.quit()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


def frametest(args, cmd, names):
    """Conta i frame oltre il tempo di una build con FRAMETEST: un checkpoint su ft_inc (ft_check
    di play.s), che ogni frame contato esegue."""
    one = dict(names)
    if "ft_inc" not in one:
        print("la build non ha FRAMETEST (manca ft_inc)")
        return 1
    cmd += ["-limitcycles", str(args.cycles)]
    hide = None
    if os.name == "nt":
        hide = subprocess.STARTUPINFO()
        hide.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        hide.wShowWindow = 0
    proc = subprocess.Popen(cmd, startupinfo=hide, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    hits = []
    try:
        mon = Monitor(args.port)
        ids = mon.register_ids()
        banks = mon.banks()
        mon.checkpoint(one["ft_inc"])
        mon.resume()
        while True:
            mon.wait_checkpoint()
            r = mon.registers()
            page = mon.memory(0, 0xFF, banks["cpu"])
            hits.append((page[one["state"]], r[ids["LIN"]], page[one["frame_count"]] | page[one["frame_count"] + 1] << 8))
            mon.resume()
    except (ConnectionError, OSError):
        pass                    # VICE è uscito: fine dei cicli
    finally:
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
    by = {}
    for state, _line, _frame in hits:
        by[state] = by.get(state, 0) + 1
    what = ", ".join(f"scena {s}: {n}" for s, n in sorted(by.items())) or "nessuno"
    tv = "NTSC" if args.ntsc else "PAL"
    print(f"{args.prg} {tv}, {args.cycles} cicli: {len(hits)} frame oltre il tempo ({what})")
    for state, line, frame in hits[:20]:
        print(f"  scena {state}, riga {line}, frame_count {frame}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
