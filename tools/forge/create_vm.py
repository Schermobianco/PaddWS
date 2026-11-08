"""Crea da zero la macchina forge in VMware Workstation, senza domande e senza installare Debian a mano.

Passi:
  1. scarica l'immagine cloud di Debian 13 (generic, con cloud-init) e ne controlla lo SHA-512;
  2. ne fa il disco della VM (vmware-vdiskmanager), allargato alla dimensione chiesta;
  3. scrive un piccolo ISO "cidata" per cloud-init: utente con la chiave ssh di questo PC, sudo senza
     password, nome host forge, open-vm-tools;
  4. scrive il .vmx (EFI, NVMe, rete NAT con un indirizzo MAC fisso) e accende la VM senza finestra;
  5. trova l'indirizzo IP nei lease del DHCP di VMware, aspetta ssh e la fine di cloud-init;
  6. lancia tools/forge/setup.sh (Docker, console, comandi forge-*);
  7. con --deck prepara anche la cache dell'immagine del Deck (tools/forge/deck-cache.sh, ore);
  8. spegne la VM, toglie l'ISO, aggiunge "Host NOME" a ~/.ssh/config e scrive forge.local.psd1.

Poi build_onforge.bat la accende e la spegne da solo. Serve solo la libreria standard di Python, più
VMware Workstation e il client OpenSSH (in Windows 10 e 11 c'è già).

Uso:  create_forge.bat [--dir CARTELLA] [--name forge] [--cpus N] [--memory MB] [--disk GB]
                       [--user forge] [--key FILE.pub] [--console-password] [--deck]
"""

import argparse
import getpass
import hashlib
import os
import random
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IMAGES = "https://cloud.debian.org/images/cloud/trixie/latest/"
IMAGE = "debian-13-generic-amd64.tar.xz"
WINDOWS = os.name == "nt"


def say(msg):
    print(f"== {msg}", flush=True)


def fail(msg):
    print(f"ERRORE: {msg}", file=sys.stderr, flush=True)
    sys.exit(1)


def run(*cmd, check=True, capture=False, **kw):
    r = subprocess.run([str(c) for c in cmd], text=True, capture_output=capture, **kw)
    if check and r.returncode != 0:
        out = (r.stderr or r.stdout or "").strip() if capture else ""
        fail(f"{Path(str(cmd[0])).name} {' '.join(str(c) for c in cmd[1:3])}... non è riuscito {out}")
    return r


# ---------------------------------------------------------------- VMware

def vmware_tool(name, given):
    """vmrun o vmware-vdiskmanager: dalla cartella data, da quella standard o dal PATH."""
    exe = name + (".exe" if WINDOWS else "")
    dirs = [given] if given else []
    if WINDOWS:
        for env in ("ProgramFiles(x86)", "ProgramFiles"):
            if os.environ.get(env):
                dirs.append(os.path.join(os.environ[env], "VMware", "VMware Workstation"))
    for d in dirs:
        p = Path(d) / exe
        if p.is_file():
            return p
    p = shutil.which(name)
    if p:
        return Path(p)
    fail(f"{exe} non trovato: serve VMware Workstation (--vmware CARTELLA se non è nel posto standard)")


def leases_file():
    if WINDOWS:
        return Path(os.environ.get("ProgramData", r"C:\ProgramData")) / "VMware" / "vmnetdhcp.leases"
    return Path("/etc/vmware/vmnet8/dhcpd/dhcpd.leases")


def lease_ip(mac):
    """L'ultimo indirizzo dato dal DHCP di VMware alla scheda con questo MAC."""
    try:
        text = leases_file().read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    ip = None
    for m in re.finditer(r"lease (\d+\.\d+\.\d+\.\d+) \{(.*?)\}", text, re.S):
        if re.search(r"hardware ethernet " + re.escape(mac) + ";", m.group(2), re.I):
            ip = m.group(1)
    return ip


def running(vmrun, vmx):
    r = run(vmrun, "-T", "ws", "list", capture=True, check=False)
    return any(Path(l.strip()).resolve() == vmx.resolve() for l in r.stdout.splitlines()[1:] if l.strip())


# ---------------------------------------------------------------- immagine e disco

def download(url, dest):
    tmp = dest.with_suffix(dest.suffix + ".part")
    with urllib.request.urlopen(url) as r, open(tmp, "wb") as f:
        total = int(r.headers.get("Content-Length") or 0)
        done, shown = 0, -1
        while chunk := r.read(1 << 20):
            f.write(chunk)
            done += len(chunk)
            if total and done * 10 // total != shown:
                shown = done * 10 // total
                print(f"   {done >> 20} / {total >> 20} MB", flush=True)
    tmp.replace(dest)


def debian_image(cache):
    """L'archivio dell'immagine in cache, scaricato se manca o se lo SHA-512 non torna."""
    cache.mkdir(parents=True, exist_ok=True)
    sums = urllib.request.urlopen(IMAGES + "SHA512SUMS").read().decode()
    want = next((l.split()[0] for l in sums.splitlines() if l.endswith(" " + IMAGE)), None)
    if not want:
        fail(f"{IMAGE} non è in {IMAGES}SHA512SUMS")
    dest = cache / IMAGE

    def sha512():
        h = hashlib.sha512()
        with open(dest, "rb") as f:
            while chunk := f.read(1 << 20):
                h.update(chunk)
        return h.hexdigest()

    if dest.exists() and sha512() == want:
        say(f"immagine Debian già in {dest}")
        return dest
    say(f"scarico {IMAGES}{IMAGE}")
    download(IMAGES + IMAGE, dest)
    if sha512() != want:
        dest.unlink()
        fail("lo SHA-512 dell'immagine scaricata non torna")
    return dest


def make_disk(archive, vmdir, size_gb, vdisk):
    """disk.raw dall'archivio, poi un .vmdk che cresce da solo, allargato a size_gb."""
    say("disco della VM dall'immagine Debian")
    raw = vmdir / "debian-flat.vmdk"
    with tarfile.open(archive, "r:xz") as t:
        member = next((m for m in t if m.isfile() and m.name.endswith(".raw")), None)
        if member is None:
            fail(f"nessun disco .raw in {archive.name}")
        with t.extractfile(member) as src, open(raw, "wb") as dst:
            shutil.copyfileobj(src, dst, 1 << 20)
    sectors = raw.stat().st_size // 512
    # descrittore di un disco "flat": VMware legge il file raw così com'è
    desc = vmdir / "debian.vmdk"
    desc.write_text(
        "# Disk DescriptorFile\nversion=1\nCID=fffffffe\nparentCID=ffffffff\n"
        'createType="monolithicFlat"\n\n'
        f'RW {sectors} FLAT "{raw.name}" 0\n\n'
        'ddb.virtualHWVersion = "19"\nddb.adapterType = "lsilogic"\n'
        f'ddb.geometry.cylinders = "{min(sectors // (255 * 63), 65535)}"\n'
        'ddb.geometry.heads = "255"\nddb.geometry.sectors = "63"\n',
        encoding="ascii", newline="\n")
    disk = vmdir / "forge.vmdk"
    run(vdisk, "-r", desc, "-t", "0", disk, capture=True)
    desc.unlink()
    raw.unlink()
    run(vdisk, "-x", f"{size_gb}GB", disk, capture=True)
    return disk


# ---------------------------------------------------------------- cloud-init

def iso9660(path, label, files):
    """Un ISO 9660 minimo, una sola cartella: quanto basta al datasource NoCloud di cloud-init.

    Senza Rock Ridge Linux mostra i nomi in minuscolo e senza ";1" (user-data, meta-data)."""
    S = 2048
    both16 = lambda n: struct.pack("<H", n) + struct.pack(">H", n)
    both32 = lambda n: struct.pack("<I", n) + struct.pack(">I", n)
    now = datetime.now(timezone.utc)
    rec_date = bytes([now.year - 1900, now.month, now.day, now.hour, now.minute, now.second, 0])
    vol_date = now.strftime("%Y%m%d%H%M%S00").encode() + b"\0"

    def record(name, lba, size, is_dir):
        n = len(name)
        body = (bytes([0]) + both32(lba) + both32(size) + rec_date + bytes([2 if is_dir else 0, 0, 0])
                + both16(1) + bytes([n]) + name + (b"\0" if n % 2 == 0 else b""))
        return bytes([len(body) + 1]) + body

    names = sorted((n.upper().encode("ascii") + b";1", data) for n, data in files.items())
    root_lba, first = 20, 21
    entries, lba = [], first
    for name, data in names:
        entries.append((name, lba, data))
        lba += max(1, -(-len(data) // S))
    total = lba
    root = record(b"\0", root_lba, S, True) + record(b"\1", root_lba, S, True)
    for name, at, data in entries:
        root += record(name, at, len(data), False)
    assert len(root) <= S

    def pad(s, n):
        return s.encode("ascii").ljust(n, b" ")

    pvd = (bytes([1]) + b"CD001" + bytes([1, 0]) + pad("", 32) + pad(label.upper(), 32) + bytes(8)
           + both32(total) + bytes(32) + both16(1) + both16(1) + both16(S) + both32(10)
           + struct.pack("<I", 18) + bytes(4) + struct.pack(">I", 19) + bytes(4)
           + record(b"\0", root_lba, S, True) + pad("", 128) + pad("", 128) + pad("", 128)
           + pad("PADD WS forge", 128) + pad("", 37) + pad("", 37) + pad("", 37)
           + vol_date + vol_date + b"0" * 16 + b"\0" + vol_date + bytes([1, 0]))
    term = bytes([255]) + b"CD001" + bytes([1])
    ptl = bytes([1, 0]) + struct.pack("<I", root_lba) + struct.pack("<H", 1) + b"\0\0"
    ptm = bytes([1, 0]) + struct.pack(">I", root_lba) + struct.pack(">H", 1) + b"\0\0"
    with open(path, "wb") as f:
        f.write(bytes(16 * S))
        for block in (pvd, term, ptl, ptm, root):
            f.write(block.ljust(S, b"\0"))
        for _, _, data in entries:
            f.write(data.ljust(max(1, -(-len(data) // S)) * S, b"\0"))


def cloud_config(user, key, password):
    lines = [
        "#cloud-config",
        "hostname: forge",
        "manage_etc_hosts: true",
        "users:",
        f"  - name: {user}",
        "    gecos: forge",
        "    groups: [sudo]",
        "    shell: /bin/bash",
        '    sudo: "ALL=(ALL) NOPASSWD:ALL"',
        f"    lock_passwd: {'false' if password else 'true'}",
        "    ssh_authorized_keys:",
        f"      - {key}",
        "ssh_pwauth: false",
        "package_update: true",
        "packages: [open-vm-tools]",
    ]
    if password:
        quoted = password.replace("'", "''")
        lines += ["chpasswd:", "  expire: false", "  users:",
                  f"    - {{name: {user}, password: '{quoted}', type: text}}"]
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------- .vmx

def write_vmx(vmx, name, cpus, memory, mac):
    pairs = {
        ".encoding": "UTF-8",
        "config.version": "8",
        "virtualHW.version": "19",
        "displayName": f"PADD WS {name}",
        "guestOS": "debian12-64",
        "firmware": "efi",
        "numvcpus": str(cpus),
        "cpuid.coresPerSocket": str(cpus),
        "memsize": str(memory),
        "nvme0.present": "TRUE",
        "nvme0:0.present": "TRUE",
        "nvme0:0.fileName": "forge.vmdk",
        "sata0.present": "TRUE",
        "sata0:1.present": "TRUE",
        "sata0:1.deviceType": "cdrom-image",
        "sata0:1.fileName": "seed.iso",
        "ethernet0.present": "TRUE",
        "ethernet0.connectionType": "nat",
        "ethernet0.virtualDev": "vmxnet3",
        "ethernet0.addressType": "static",
        "ethernet0.address": mac,
        "pciBridge0.present": "TRUE",
        "vmci0.present": "TRUE",
        "floppy0.present": "FALSE",
        "tools.syncTime": "FALSE",
        "powerType.powerOff": "soft",
        "powerType.reset": "soft",
        "powerType.suspend": "soft",
    }
    for n in (4, 5, 6, 7):
        pairs[f"pciBridge{n}.present"] = "TRUE"
        pairs[f"pciBridge{n}.virtualDev"] = "pcieRootPort"
        pairs[f"pciBridge{n}.functions"] = "8"
    vmx.write_text("".join(f'{k} = "{v}"\n' for k, v in pairs.items()), encoding="utf-8", newline="\n")


def remove_seed(vmx):
    lines = vmx.read_text(encoding="utf-8").splitlines(keepends=True)
    vmx.write_text("".join(l for l in lines if not l.startswith("sata0")), encoding="utf-8", newline="\n")
    (vmx.parent / "seed.iso").unlink(missing_ok=True)


# ---------------------------------------------------------------- ssh

def ssh_key(given):
    if given:
        pub = Path(given).expanduser().resolve()
        if pub.suffix != ".pub" or not pub.is_file() or not pub.with_suffix("").is_file():
            fail(f"serve la chiave pubblica FILE.pub con accanto la privata FILE: {pub}")
        return pub
    pub = Path.home() / ".ssh" / "id_ed25519.pub"
    if not pub.exists():
        say(f"nessuna chiave ssh: la creo ({pub.with_suffix('')}, senza passphrase)")
        pub.parent.mkdir(exist_ok=True)
        run("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", pub.with_suffix(""))
    return pub


def ssh_base(ip, user, key):
    """ssh verso la VM appena creata, con la chiave privata e senza ~/.ssh/config."""
    return ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ServerAliveInterval=30", "-i", str(key.with_suffix("")), f"{user}@{ip}"]


def ssh_config(name, ip, user, key):
    """Il blocco "Host NOME" in ~/.ssh/config, aggiunto o sostituito (copia in config.bak)."""
    cfg = Path.home() / ".ssh" / "config"
    text = cfg.read_text(encoding="utf-8") if cfg.exists() else ""
    private = key.with_suffix("")
    ident = ("~/" + private.relative_to(Path.home()).as_posix() if private.is_relative_to(Path.home())
             else private.as_posix())
    block = (f"Host {name}\n    HostName {ip}\n    User {user}\n    IdentityFile {ident}\n"
             "    ServerAliveInterval 30\n")
    pattern = re.compile(rf"^Host {re.escape(name)}[ \t]*\n(?:(?![ \t]*Host[ \t]).*\n?)*", re.M)
    if pattern.search(text):
        shutil.copyfile(cfg, cfg.with_name("config.bak"))
        text = pattern.sub(lambda _: block + "\n", text, count=1)
        say(f"~/.ssh/config: Host {name} aggiornato (copia del vecchio in config.bak)")
    else:
        text = (text.rstrip("\n") + "\n\n" if text.strip() else "") + block
        say(f"~/.ssh/config: aggiunto Host {name}")
    cfg.write_text(text, encoding="utf-8", newline="\n")


# ---------------------------------------------------------------- main

def main():
    cores = os.cpu_count() or 4
    ap = argparse.ArgumentParser(description="Crea la VM forge in VMware Workstation (tools/forge/README.md).")
    default_dir = Path.home() / ("Documents/Virtual Machines" if WINDOWS else "vmware")
    ap.add_argument("--dir", type=Path, help=f"cartella della VM (predefinita: {default_dir}\\NOME)")
    ap.add_argument("--name", default="forge", help="nome ssh e della VM (predefinito: forge)")
    ap.add_argument("--cpus", type=int, default=min(8, max(2, cores // 2)),
                    help="processori (predefinito: metà di quelli del PC, al massimo 8)")
    ap.add_argument("--memory", type=int, default=16384, help="RAM in MB (predefinita: 16384, minimo 8192)")
    ap.add_argument("--disk", type=int, default=80, help="disco in GB (predefinito: 80)")
    ap.add_argument("--user", default="forge", help="utente sulla VM (predefinito: forge)")
    ap.add_argument("--key", help="chiave ssh pubblica (predefinita: ~/.ssh/id_ed25519.pub, creata se manca)")
    ap.add_argument("--console-password", action="store_true",
                    help="chiede una password per accedere dalla console della VM (senza: solo ssh)")
    ap.add_argument("--deck", action="store_true",
                    help="prepara anche la cache dell'immagine del Deck (qualche ora, si può fare dopo)")
    ap.add_argument("--vmware", help="cartella di vmrun e vmware-vdiskmanager, se non è quella standard")
    ap.add_argument("--cache", type=Path, help="dove tenere l'immagine Debian scaricata")
    a = ap.parse_args()

    if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", a.user):
        fail(f"nome utente non valido: {a.user}")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", a.name):
        fail(f"nome non valido: {a.name}")
    if a.memory < 8192:
        fail("con meno di 8 GB di RAM la sintesi Quartus del core MiSTer non ci sta")
    vmrun = vmware_tool("vmrun", a.vmware)
    vdisk = vmware_tool("vmware-vdiskmanager", a.vmware)
    for tool in ("ssh", "scp", "ssh-keygen", "git"):
        if not shutil.which(tool):
            fail(f"{tool} non trovato (client OpenSSH e git)")
    vmdir = (a.dir or default_dir / a.name).resolve()
    vmx = vmdir / f"{a.name}.vmx"
    if vmx.exists():
        fail(f"{vmx} esiste già: per rifarla, cancella la VM da VMware (o scegli un'altra --dir)")
    key = ssh_key(a.key)
    password = None
    if a.console_password:
        password = getpass.getpass("password per la console della VM: ")
        if password != getpass.getpass("ancora una volta: "):
            fail("le due password sono diverse")
    cache = a.cache or (Path(os.environ.get("LOCALAPPDATA", Path.home() / ".cache")) / "PaddWS" / "forge")

    started = time.time()
    archive = debian_image(cache)
    vmdir.mkdir(parents=True, exist_ok=True)
    make_disk(archive, vmdir, a.disk, vdisk)

    say("ISO di cloud-init")
    mac = "00:50:56:%02x:%02x:%02x" % (random.randint(0, 0x3F), random.randint(0, 255), random.randint(0, 255))
    pub = key.read_text(encoding="utf-8").strip()
    iso9660(vmdir / "seed.iso", "cidata", {
        "user-data": cloud_config(a.user, pub, password).encode(),
        "meta-data": f"instance-id: {a.name}-{int(started)}\nlocal-hostname: forge\n".encode(),
    })
    write_vmx(vmx, a.name, a.cpus, a.memory, mac)
    say(f"VM in {vmdir}: {a.cpus} processori, {a.memory} MB, disco da {a.disk} GB, MAC {mac}")

    say("accensione (senza finestra)")
    run(vmrun, "-T", "ws", "start", vmx, "nogui")
    ip = None
    for _ in range(120):
        ip = lease_ip(mac)
        if ip:
            break
        time.sleep(5)
    if not ip:
        fail("dopo 10 minuti la VM non ha ancora un indirizzo dal DHCP di VMware (rete NAT?)")
    say(f"indirizzo {ip}, aspetto ssh")
    run("ssh-keygen", "-R", ip, capture=True, check=False)
    ssh = ssh_base(ip, a.user, key)
    for _ in range(120):
        if run(*ssh, "true", check=False, capture=True).returncode == 0:
            break
        time.sleep(5)
    else:
        fail(f"ssh {a.user}@{ip} non risponde dopo 10 minuti")
    say("cloud-init (aggiornamenti e open-vm-tools)")
    r = run(*ssh, "cloud-init status --wait >/dev/null; cloud-init status", check=False, capture=True)
    print("   " + r.stdout.strip())
    if "done" not in r.stdout:
        fail("cloud-init non ha finito bene (sulla VM: sudo cloud-init status --long)")

    say("tools/forge/setup.sh")
    scp = ["scp", "-q", "-o", "BatchMode=yes", "-i", str(key.with_suffix(""))]
    run(*scp, ROOT / "tools" / "forge" / "setup.sh", f"{a.user}@{ip}:setup.sh")
    run(*ssh, "sudo DEBIAN_FRONTEND=noninteractive sh setup.sh && rm setup.sh")

    if a.deck:
        say("sorgenti del commit attuale su forge, poi la cache del Deck (qualche ora)")
        tar = vmdir / "src.tar"
        run("git", "-C", ROOT, "-c", "core.autocrlf=false", "archive", "--format=tar", "-o", tar, "HEAD")
        run(*scp, tar, f"{a.user}@{ip}:forge/src.tar")
        tar.unlink()
        run(*ssh, "set -e; cd ~/forge; rm -rf src; mkdir src; tar -xf src.tar -C src; rm src.tar; "
                  "echo 'commit (create_vm.py)' > src/.source")
        run(*ssh, "sh ~/forge/src/tools/forge/deck-cache.sh")

    say("spengo la VM e tolgo l'ISO di cloud-init")
    # cloud-init ha finito il suo lavoro: senza l'ISO non deve ripartire a ogni avvio
    run(*ssh, "sudo touch /etc/cloud/cloud-init.disabled", check=False, capture=True)
    run(vmrun, "-T", "ws", "stop", vmx, "soft", check=False)
    for _ in range(60):
        if not running(vmrun, vmx):
            break
        time.sleep(2)
    else:
        fail("la VM non si spegne: spegnila da VMware e togli a mano il CD seed.iso")
    remove_seed(vmx)

    ssh_config(a.name, ip, a.user, key)
    local = ROOT / "forge.local.psd1"
    psd = f"@{{\n    Host = '{a.name}'\n    Vmx  = '{vmx}'\n}}\n"
    if local.exists():
        say(f"{local.name} c'è già, non lo tocco; per usare questa VM:\n{psd}")
    else:
        local.write_text(psd, encoding="utf-8")
        say(f"scritto {local.name}")
    say(f"forge pronta in {int(time.time() - started) // 60} minuti: build_onforge.bat la accende da solo")
    if not a.deck:
        print("   Senza la cache del Deck la release salta l'immagine della SD del Deck. Per prepararla\n"
              f"   (qualche ora): build_onforge.bat -KeepVm, poi ssh {a.name} sh forge/src/tools/forge/deck-cache.sh")


if __name__ == "__main__":
    main()
