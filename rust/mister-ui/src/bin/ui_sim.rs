//! Banco di prova delle schermate del core MiSTer: esegue il codice del firmware (`paddws_mister_ui`)
//! sugli stati fotografati dal simulatore dei frame (`PONG_UILOG` di mister/sim/frames) con un
//! modello in Rust del motore (`mister/rtl/ui_render.v`, stesse larghezze dei conti), e confronta
//! l'impronta FNV-1a di ogni frame con quella di un registro `PONG_HASHLOG` (per esempio della 4.3.0).
//! Si confrontano solo i frame dei modi indicati, quelli dove lo schermo a oggetti è tutto lo schermo.
//!
//! Uso: paddws-ui-sim UILOG HASHLOG [--modes 0,1,2,3] [--ppm CARTELLA] [--frames A-B]
//!   --ppm     scrive i frame diversi (o quelli di --frames) in CARTELLA/u<frame>.ppm

use std::collections::{BTreeSet, HashMap};
use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

use paddws_mister_ui::{Port, Ui, map};

const W: usize = 320;
const H: usize = 240;

/// Modello dei registri e delle memorie di ui_render.v (e dei registri dello stato di pong_top).
struct Model {
    obj: Vec<u32>,
    tile: Vec<u16>,
    lt: Vec<u16>,
    pal: [u32; 256],
    count: [u32; 2],
    front: usize,
    flip_req: bool,
    uis: [u32; 64],
    seq: u32,
    font: Vec<u8>,
    gfx: Vec<u32>,
    /// immagine scrivibile (map::GRAM)
    gram: Vec<u32>,
    /// grafica della DDR3 (paddws_gfx.rom), finestra e registri della copia (gfx_ddr.v): la copia
    /// qui è istantanea
    ddr: Vec<u32>,
    wram: Vec<u32>,
    dma: [u32; 2],
}

impl Port for Model {
    fn read(&mut self, word: u32) -> u32 {
        if word & 0x2000 != 0 {
            // oscilloscopi del SID: niente audio nel modello
            0
        } else if word & 0x1000 == 0 {
            (self.front as u32) | (self.flip_req as u32) << 1 | if self.ddr.is_empty() { 0 } else { map::GFX_OK }
        } else if word & 0x40 != 0 {
            self.seq
        } else {
            self.uis[(word & 63) as usize]
        }
    }

    fn write(&mut self, word: u32, v: u32) {
        let back = 1 - self.front;
        match word >> 10 {
            0 => self.obj[back << 10 | (word & 0x3FF) as usize] = v,
            1 => self.tile[back << 10 | (word & 0x3FF) as usize] = v as u16,
            2 if word & 0x200 == 0 => self.lt[back << 9 | (word & 0x1FF) as usize] = v as u16,
            2 if word & 0x300 == 0x200 => self.pal[(word & 0xFF) as usize] = v & 0xFF_FFFF,
            3 if word & 0x200 == 0 => self.gram[(word & 0x1FF) as usize] = v,
            3 if word & 3 < 2 => self.dma[(word & 3) as usize] = v,
            3 if word & 3 == 2 => {
                let (src, dst) = (self.dma[0] as usize, self.dma[1] as usize);
                for i in 0..v as usize {
                    if let (Some(&w), Some(slot)) = (self.ddr.get(src + i), self.wram.get_mut(dst + i)) {
                        *slot = w;
                    }
                }
            }
            2 if word == map::CTRL => {
                self.count[back] = v & 0xFF;
                if v & 0x100 != 0 {
                    self.flip_req = true;
                }
            }
            _ => {}
        }
    }
}

fn sext(v: u32, bits: u32) -> i32 {
    ((v << (32 - bits)) as i32) >> (32 - bits)
}

impl Model {
    /// Scambio dei banchi della riga 261.
    fn flip(&mut self) {
        if self.flip_req {
            self.front ^= 1;
            self.flip_req = false;
        }
    }

    /// Riga `line` del line buffer: {classe, colore} per pixel, come il motore.
    fn line(&self, line: i32, lb: &mut [u16; W]) {
        lb.fill(0);
        let f = self.front;
        for k in 0..self.count[f].min(128) as usize {
            let o = &self.obj[f << 10 | k << 3..(f << 10 | k << 3) + 8];
            let (ya, yb) = ((o[0] & 0x1FF) as i32, ((o[0] >> 9) & 0x1FF) as i32);
            if !(ya <= line && line < yb) {
                continue;
            }
            let x0 = sext(o[1] & 0x7FF, 11);
            let y0 = sext((o[1] >> 11) & 0x7FF, 11);
            let w = ((o[1] >> 22) & 0x3FF) as i32;
            let h = (o[2] & 0x3FF) as i32;
            let (fx, fy, swap) = (o[2] >> 10 & 1 != 0, o[2] >> 11 & 1 != 0, o[2] >> 12 & 1 != 0);
            let (sx, sy) = ((o[2] >> 13) & 3, (o[2] >> 15) & 3);
            let (lt_en, opq) = (o[2] >> 17 & 1 != 0, o[2] >> 18 & 1 != 0);
            let ltrow = o[2] >> 23 & 1 != 0;
            let kind = (o[2] >> 19) & 3;
            let class = ((o[2] >> 21) & 3) as u16;
            let (cx0, cx1) = ((o[3] & 0x1FF) as i32, ((o[3] >> 9) & 0x1FF) as i32);
            let base = o[4] & 0xFFFF;
            let ssh = (o[4] >> 16) & 15;
            let bpp = (o[4] >> 20) & 3;
            let (u0, v0) = (o[5] & 0x3FF, (o[5] >> 10) & 0x3FF);
            let (ca, cb) = ((o[6] & 0xFF) as u16, ((o[6] >> 8) & 0xFF) as u16);
            let ltb = o[7] & 0x1FF;
            let jj = line - y0;
            let lt_a = (ltb + (jj as u32 & 0x3FF)) & 0x1FF;
            let ltq = self.lt[f << 9 | lt_a as usize] as u32;
            let dx = if lt_en && !ltrow { sext(ltq & 0x3FF, 10) } else { 0 };
            let rowoff = if lt_en && ltrow { ltq } else { 0 };
            let xorg = x0 + dx;
            let jp = if fy {
                (h - 1 - jj) as u32 & 0x3FF
            } else {
                jj as u32 & 0x3FF
            };
            let xa = xorg.max(cx0);
            let xb = (xorg + w).min(cx1).min(320);
            if xa >= xb || xa < 0 {
                continue;
            }
            let bj = jp >> sy;
            let ii = xa - xorg;
            let mut ip = if fx {
                (w - 1 - ii) as u32 & 0x3FF
            } else {
                ii as u32 & 0x3FF
            };
            for x in xa..xb {
                let a = ip >> sx;
                let u = ((if swap { bj } else { a }) + u0) & 0x3FF;
                let v = ((if swap { a } else { bj }) + v0) & 0x3FF;
                let col = match kind {
                    0 => ca,
                    1 => {
                        let ta = (base + ((v >> 3) << ssh) + (u >> 3)) & 0x3FF;
                        let t = self.tile[f << 10 | ta as usize];
                        let row = self.font[((t & 0xFF) as usize) << 3 | (v & 7) as usize];
                        if row >> (7 - (u & 7)) & 1 != 0 {
                            t >> 8
                        } else if opq {
                            cb
                        } else {
                            0
                        }
                    }
                    _ => {
                        let row = if ltrow { rowoff } else { (v << ssh) & 0xFFFF };
                        let ga = (base + row + (u >> (5 - bpp))) & 0xFFFF;
                        let word = if ga & 0xC000 == 0xC000 {
                            self.gram[(ga as usize) & 0x1FF]
                        } else if ga & 0xC000 == 0x8000 {
                            self.wram.get((ga as usize) & 0x1FFF).copied().unwrap_or(0)
                        } else {
                            self.gfx.get(ga as usize).copied().unwrap_or(0)
                        };
                        let ub = ((u & 31) << bpp) & 31;
                        let bits = 1 << bpp;
                        let val = ((word << ub) >> (32 - bits)) as u16;
                        if val == 0 {
                            if opq { cb } else { 0 }
                        } else if bpp == 0 {
                            ca
                        } else {
                            (ca + val) & 0xFF
                        }
                    }
                };
                if col != 0 {
                    lb[x as usize] = class << 8 | col;
                }
                ip = if fx {
                    ip.wrapping_sub(1) & 0x3FF
                } else {
                    (ip + 1) & 0x3FF
                };
            }
        }
    }

    /// Frame a tutto schermo: il colore dell'oggetto o il nero, con lo scambio dell'easter egg.
    fn frame(&self, egg: bool) -> Vec<u8> {
        let mut out = vec![0u8; W * H * 3];
        let mut lb = [0u16; W];
        for y in 0..H {
            self.line(y as i32, &mut lb);
            for x in 0..W {
                let idx = (lb[x] & 0xFF) as usize;
                let mut c = if idx != 0 { self.pal[idx] } else { 0 };
                if egg {
                    c = egg_swap(c);
                }
                let p = &mut out[(y * W + x) * 3..][..3];
                p.copy_from_slice(&[(c >> 16) as u8, (c >> 8) as u8, c as u8]);
            }
        }
        out
    }
}

/// Giallo e rosso scambiati (egg_swap di pong_top.v).
fn egg_swap(c: u32) -> u32 {
    let scale = |c: u32, n: u32, d: u32| {
        let ch = |s: u32| ((c >> s & 0xFF) * n / d) << s;
        ch(16) | ch(8) | ch(0)
    };
    let (yellow, red) = (0xFFD225, 0xE62828);
    let mut pairs = vec![(yellow, red)];
    pairs.extend((1..=12).map(|i| (scale(yellow, i, 13), scale(red, i, 13))));
    pairs.extend((13..=34).map(|i| (scale(yellow, i - 12, 23), scale(red, i - 12, 23))));
    pairs.extend([
        (0x2E2607, 0x290707),
        (0x5C4C0D, 0x530E0E),
        (0x8A7114, 0x7C1616),
        (0x735E11, 0x681212),
        (red, yellow),
        (0x8C1414, 0x8C7414),
        (0xFF6E6E, 0xFFE26E),
        (0x5A0A0A, 0x5A4B0A),
    ]);
    let mut hit = false;
    let mut out = 0;
    for (a, b) in pairs {
        if c == a {
            hit = true;
            out |= b;
        }
    }
    if hit { out } else { c }
}

fn fnv(bytes: &[u8]) -> u64 {
    let mut h = 0xcbf29ce484222325u64;
    for &b in bytes {
        h = (h ^ b as u64).wrapping_mul(0x100000001b3);
    }
    h
}

fn read_hex<T: Copy>(path: &PathBuf, parse: fn(&str) -> T) -> Vec<T> {
    fs::read_to_string(path)
        .unwrap_or_else(|e| panic!("{}: {e}", path.display()))
        .lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| parse(l.trim()))
        .collect()
}

fn write_ppm(path: &PathBuf, rgb: &[u8]) {
    let mut b = format!("P6\n{W} {H}\n255\n").into_bytes();
    b.extend_from_slice(rgb);
    fs::write(path, b).unwrap();
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut pos = vec![];
    let mut modes: BTreeSet<u32> = [0, 1, 2, 3].into();
    let mut ppm: Option<PathBuf> = None;
    let mut only: Option<(i64, i64)> = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--modes" => {
                i += 1;
                modes = args[i].split(',').map(|m| m.parse().unwrap()).collect();
            }
            "--ppm" => {
                i += 1;
                ppm = Some(PathBuf::from(&args[i]));
            }
            "--frames" => {
                i += 1;
                let (a, b) = args[i].split_once('-').unwrap_or((&args[i], &args[i]));
                only = Some((a.parse().unwrap(), b.parse().unwrap()));
            }
            a => pos.push(a.to_string()),
        }
        i += 1;
    }
    if pos.len() != 2 {
        eprintln!("uso: paddws-ui-sim UILOG HASHLOG [--modes 0,1,2,3] [--ppm CARTELLA] [--frames A-B]");
        return ExitCode::FAILURE;
    }
    let rtl_gen = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../mister/rtl/gen");
    let mut m = Model {
        obj: vec![0; 2048],
        tile: vec![0; 2048],
        lt: vec![0; 1024],
        pal: [0; 256],
        count: [0; 2],
        front: 0,
        flip_req: false,
        uis: [0; 64],
        seq: 0,
        font: read_hex(&rtl_gen.join("ui_font.hex"), |s| u8::from_str_radix(s, 16).unwrap()),
        // la ROM grafica è in due file (le prime 32.768 parole e il resto)
        gfx: [rtl_gen.join("ui_gfx.hex"), rtl_gen.join("ui_gfx2.hex")]
            .iter()
            .flat_map(|f| read_hex(f, |s| u32::from_str_radix(s, 16).unwrap()))
            .collect(),
        gram: vec![0; map::GRAM_WORDS as usize],
        // grafica della DDR3 (paddws_gfx.rom, parole a 32 bit little endian)
        ddr: fs::read(rtl_gen.join("paddws_gfx.rom"))
            .map(|b| b.as_chunks::<4>().0.iter().map(|c| u32::from_le_bytes(*c)).collect())
            .unwrap_or_default(),
        wram: vec![0; paddws_mister_ui::assets::WIN_WORDS as usize],
        dma: [0; 2],
    };
    let refs: HashMap<i64, (u32, u64)> = fs::read_to_string(&pos[1])
        .expect("registro delle impronte")
        .lines()
        .filter_map(|l| {
            let v: Vec<&str> = l.split_whitespace().collect();
            (v.len() == 3).then(|| {
                (
                    v[0].parse().unwrap(),
                    (v[1].parse().unwrap(), u64::from_str_radix(v[2], 16).unwrap()),
                )
            })
        })
        .collect();
    let mut ui = Ui::new();
    ui.init(&mut m);
    if let Some(d) = &ppm {
        fs::create_dir_all(d).unwrap();
    }
    let (mut same, mut diff): (u32, Vec<(i64, u32, bool)>) = (0, vec![]);
    for line in fs::read_to_string(&pos[0]).expect("registro degli stati").lines() {
        let v: Vec<&str> = line.split_whitespace().collect();
        if v.len() < 2 || v[0] == "#" {
            continue;
        }
        let frame: i64 = v[0].parse().unwrap();
        for (k, s) in v[1..].iter().enumerate() {
            m.uis[k] = u32::from_str_radix(s, 16).unwrap();
        }
        m.seq = (m.seq + 1) & 0xFF;
        ui.poll(&mut m);
        m.flip();
        let mode = m.uis[0] & 15;
        let wanted = only.is_some_and(|(a, b)| frame >= a && frame <= b);
        if !modes.contains(&mode) && !wanted {
            continue;
        }
        let egg = m.uis[0] >> 27 & 1 != 0;
        let rgb = m.frame(egg);
        let h = fnv(&rgb);
        let ok = refs.get(&frame).map(|r| r.1 == h);
        match ok {
            Some(true) => same += 1,
            Some(false) => {
                // uguale al frame prima della 4.3.0: il cambiamento arrivato dopo la foto si vede un frame dopo
                let prev = refs.get(&(frame - 1)).is_some_and(|r| r.1 == h);
                diff.push((frame, mode, prev));
            }
            None => {}
        }
        if let Some(d) = &ppm
            && (ok == Some(false) || wanted)
            && (only.is_none() || wanted)
        {
            write_ppm(&d.join(format!("u{frame:05}.ppm")), &rgb);
        }
    }
    println!("frame uguali {same}, diversi {}", diff.len());
    // intervalli di frame diversi, con il modo
    let mut k = 0;
    while k < diff.len() {
        let (a, md, prev) = diff[k];
        let mut b = a;
        while k + 1 < diff.len() && diff[k + 1].0 == b + 1 && diff[k + 1].1 == md {
            k += 1;
            b += 1;
        }
        let note = if a == b && prev {
            " (come il frame prima della 4.3.0)"
        } else {
            ""
        };
        println!("  {a}-{b} modo {md}{note}");
        k += 1;
    }
    if diff.is_empty() {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}
