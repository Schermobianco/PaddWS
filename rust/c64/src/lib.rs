//! Banco di prova della versione C64: un emulatore del 6502 esegue il programma assemblato in
//! `c64/` e lo confronta con il core Rust, chiamandone le routine per etichetta.

pub mod cpu6502;
pub mod params_inc;

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use cpu6502::{Cpu, EF_HALF, EasyFlash};

/// Nel .prg da qui c'è l'immagine della RAM della cartuccia (c64/src/ef.s), che va a $DF00.
const EF_IMAGE: usize = 0xD000;
const EF_RAM: usize = 0xDF00;
/// Segmenti del .prg che girano a un altro indirizzo (simboli `__NOME_LOAD__`, `RUN__`, `SIZE__`).
pub const MOVED_SEGMENTS: [&str; 4] = ["BOOTCODE", "LOWCODE", "SMCODE", "HSCODE"];

/// Cartella della versione C64 (`c64/`), accanto a `rust/`.
pub fn c64_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../c64")
}

/// Cartella di build della versione C64 (`c64/build`).
pub fn default_build_dir() -> PathBuf {
    c64_dir().join("build")
}

/// Il programma C64 caricato in memoria, con le sue etichette.
pub struct Machine {
    pub cpu: Cpu,
    labels: HashMap<String, u16>,
    /// tutte le etichette (anche quelle con lo stesso nome), ordinate per indirizzo
    all_labels: Vec<(u16, String)>,
    /// cartella di build (anche i file voce, `voiceN.prg`)
    pub build: PathBuf,
    /// il .prg com'era caricato (da $0801): le routine dell'avvio (segmento INIT) le coprono poi
    /// le variabili
    pub image: Vec<u8>,
    /// segmenti che girano altrove (`MOVED_SEGMENTS`): nome, indirizzo dove girano, byte
    pub moved: Vec<(String, u16, Vec<u8>)>,
}

impl Machine {
    /// Carica `paddws.prg` (con le routine della RAM della cartuccia al loro posto, come fa
    /// l'avvio della cartuccia), le etichette `paddws.lbl` (formato VICE di ld65 `-Ln`) e la
    /// cartuccia `paddws.crt`, con la flash della classifica cancellata.
    pub fn load(build: &Path) -> Result<Self, String> {
        let prg_path = build.join("paddws.prg");
        let prg = std::fs::read(&prg_path)
            .map_err(|e| format!("{}: {e} (assemblare prima con c64/build.ps1)", prg_path.display()))?;
        if prg.len() < 3 {
            return Err(format!("{}: file troppo corto", prg_path.display()));
        }
        let mut cpu = Cpu::new();
        let start = u16::from_le_bytes([prg[0], prg[1]]) as usize;
        let data = &prg[2..];
        if start != 0x0801 {
            return Err(format!("{}: si carica a ${start:04X}", prg_path.display()));
        }
        let split = (EF_IMAGE - start).min(data.len());
        cpu.load(start as u16, &data[..split]);
        cpu.load(EF_RAM as u16, &data[split..(split + 256).min(data.len())]);
        cpu.mem[1] = 0x35; // come dopo l'avvio: BASIC e KERNAL spenti, I/O acceso
        cpu.ef = Some(Box::new(load_crt(&build.join("paddws.crt"))?));
        let lbl_path = build.join("paddws.lbl");
        let text = std::fs::read_to_string(&lbl_path).map_err(|e| format!("{}: {e}", lbl_path.display()))?;
        let mut labels = HashMap::new();
        let mut all_labels = Vec::new();
        // segmenti che girano altrove (nome, LOAD/RUN/SIZE)
        let mut moved: HashMap<(String, String), usize> = HashMap::new();
        for line in text.lines() {
            // al 000A98 .rng_below
            let mut parts = line.split_whitespace();
            let (Some("al"), Some(addr), Some(name)) = (parts.next(), parts.next(), parts.next()) else {
                continue;
            };
            let name = name.trim_start_matches('.');
            let addr = u32::from_str_radix(addr, 16).map_err(|e| format!("{lbl_path:?}: {line}: {e}"))?;
            for seg in MOVED_SEGMENTS {
                if let Some(what) = name.strip_prefix(&format!("__{seg}_")) {
                    moved.insert((seg.to_string(), what.to_string()), addr as usize);
                }
            }
            if name.starts_with('@') || name.starts_with("LOCAL_") || name.starts_with("__") {
                continue;
            }
            labels.insert(name.to_string(), addr as u16);
            all_labels.push((addr as u16, name.to_string()));
        }
        all_labels.sort();
        // le routine dell'avvio (segmento BOOTCODE) e quelle delle mosse speciali sempre in memoria
        // (LOWCODE) al loro posto, come le copia title_unpack; il codice delle mosse speciali della
        // cartuccia (SMCODE) come lo copia la scelta di NEXT (nel programma vero l'attract poi lo
        // copre: il banco di prova frames controlla che la scelta lo rimetta); quello della
        // classifica (HSCODE) come lo copia hs_load (l'avvio poi lo copre con il titolo)
        let mut images = Vec::new();
        for seg in MOVED_SEGMENTS {
            let get = |what: &str| moved.get(&(seg.to_string(), what.to_string())).copied();
            if let (Some(from), Some(to), Some(n)) = (get("LOAD__"), get("RUN__"), get("SIZE__")) {
                let bytes = data[from - start..from - start + n].to_vec();
                cpu.load(to as u16, &bytes);
                images.push((seg.to_string(), to as u16, bytes));
            }
        }
        Ok(Self {
            cpu,
            labels,
            all_labels,
            build: build.to_path_buf(),
            image: data.to_vec(),
            moved: images,
        })
    }

    /// Segmento che gira altrove (`MOVED_SEGMENTS`): indirizzo dove gira e byte del .prg.
    pub fn moved_segment(&self, name: &str) -> Option<(u16, &[u8])> {
        self.moved
            .iter()
            .find(|(n, _, _)| n == name)
            .map(|(_, a, b)| (*a, b.as_slice()))
    }

    /// Etichetta, se c'è.
    pub fn try_addr(&self, name: &str) -> Option<u16> {
        self.labels.get(name).copied()
    }

    /// Indirizzo di un'etichetta.
    pub fn addr(&self, name: &str) -> u16 {
        *self
            .labels
            .get(name)
            .unwrap_or_else(|| panic!("etichetta {name} non trovata in paddws.lbl"))
    }

    /// Etichette ordinate per indirizzo: l'istruzione a un indirizzo appartiene all'ultima
    /// etichetta che lo precede.
    pub fn sorted_labels(&self) -> &[(u16, String)] {
        &self.all_labels
    }

    /// Chiama una routine; restituisce i cicli spesi (JSR e RTS compresi).
    pub fn call(&mut self, name: &str) -> u64 {
        let addr = self.addr(name);
        self.cpu.call(addr, 2_000_000).unwrap_or_else(|e| panic!("{name}: {e}"))
    }

    /// Byte del .prg com'era caricato (anche dove poi ci sono le variabili, come i dati di INIT).
    pub fn image_u8(&self, name: &str, offset: u16) -> u8 {
        self.image[(self.addr(name).wrapping_add(offset) as usize).wrapping_sub(0x0801)]
    }

    pub fn read_u8(&self, name: &str, offset: u16) -> u8 {
        self.cpu.read(self.addr(name).wrapping_add(offset))
    }

    /// File voce del tipo di racchetta `kind` (c64/src/voice.s): indirizzo di caricamento e byte.
    pub fn voice_file(&self, kind: u8) -> Result<(u16, Vec<u8>), String> {
        let path = self.build.join(format!("voice{kind}.prg"));
        let data = std::fs::read(&path).map_err(|e| format!("{}: {e} (assemblare con c64/build.ps1)", path.display()))?;
        if data.len() < 3 {
            return Err(format!("{}: file troppo corto", path.display()));
        }
        Ok((u16::from_le_bytes([data[0], data[1]]), data[2..].to_vec()))
    }

    pub fn write_u8(&mut self, name: &str, offset: u16, v: u8) {
        let a = self.addr(name).wrapping_add(offset);
        self.cpu.write(a, v);
    }

    /// Valore a 32 bit (byte basso per primo) a `name + offset`.
    pub fn read_i32(&self, name: &str, offset: u16) -> i32 {
        let a = self.addr(name).wrapping_add(offset);
        i32::from_le_bytes(std::array::from_fn(|i| self.cpu.read(a.wrapping_add(i as u16))))
    }

    pub fn write_i32(&mut self, name: &str, offset: u16, v: i32) {
        let a = self.addr(name).wrapping_add(offset);
        for (i, b) in v.to_le_bytes().into_iter().enumerate() {
            self.cpu.write(a.wrapping_add(i as u16), b);
        }
    }
}

/// Flash di una cartuccia EasyFlash (.crt, pacchetti CHIP da 8 KB: banco, $8000 ROML o $A000 ROMH).
pub fn load_crt(path: &Path) -> Result<EasyFlash, String> {
    let data = std::fs::read(path).map_err(|e| format!("{}: {e} (assemblare prima con c64/build.ps1)", path.display()))?;
    if data.len() < 0x40 || &data[..16] != b"C64 CARTRIDGE   " {
        return Err(format!("{}: non è una cartuccia .crt", path.display()));
    }
    let mut ef = EasyFlash::new();
    let mut p = u32::from_be_bytes([data[0x10], data[0x11], data[0x12], data[0x13]]) as usize;
    while p + 16 <= data.len() {
        let be16 = |i: usize| u16::from_be_bytes([data[p + i], data[p + i + 1]]) as usize;
        let len = u32::from_be_bytes([data[p + 4], data[p + 5], data[p + 6], data[p + 7]]) as usize;
        let (bank, addr, size) = (be16(10), be16(12), be16(14));
        if &data[p..p + 4] != b"CHIP" || size != EF_HALF || bank >= 64 || p + 16 + size > data.len() {
            return Err(format!("{}: pacchetto CHIP non valido a {p}", path.display()));
        }
        let chip = match addr {
            0x8000 => &mut ef.roml,
            0xA000 | 0xE000 => &mut ef.romh,
            _ => return Err(format!("{}: CHIP a ${addr:04X}", path.display())),
        };
        chip[bank * EF_HALF..(bank + 1) * EF_HALF].copy_from_slice(&data[p + 16..p + 16 + size]);
        p += len;
    }
    Ok(ef)
}
