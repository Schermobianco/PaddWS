//! ROM della musica: gli stessi byte che leggono il player Verilog del MiSTer
//! (`mister/rtl/pong_sid.v`) e quello in 6502 del C64 (`c64/src/sid.s`), generati da
//! `tools/gen_sid_music.py` (formato delle tracce nel suo docstring).
//!
//! La ROM è `mister/rtl/gen/sid_music.hex` (un byte esadecimale per riga), gli indirizzi sono in
//! `mister/rtl/gen/sid_music.vh`: la tabella delle frequenze (per il clock del SID a 1 MHz), gli
//! strumenti, l'inizio delle tracce di ogni canzone e di ogni effetto.

/// ROM del player e indirizzi delle sue tabelle.
#[derive(Clone, Debug)]
pub struct Rom {
    pub data: Vec<u8>,
    /// tabella delle frequenze: byte basso e alto di ogni nota (0 = C0)
    pub freq_base: u16,
    /// strumenti: 8 byte ciascuno (forma d'onda, attacco/decadimento, sostegno/rilascio, impulso
    /// basso e alto, frame di rilascio)
    pub instr_base: u16,
    /// inizio delle tracce delle voci 0-2 per canzone (da 1: `songs[0]` è la canzone 1)
    pub songs: Vec<[u16; 3]>,
    /// inizio della traccia di ogni effetto (da 1)
    pub effects: Vec<u16>,
    /// nomi delle canzoni in minuscolo (`title`, `theme_hammer`...), nell'ordine di `songs`
    pub names: Vec<String>,
}

impl Rom {
    /// La ROM inclusa nell'eseguibile.
    pub fn builtin() -> Rom {
        Rom::parse(
            include_str!("../../../mister/rtl/gen/sid_music.hex"),
            include_str!("../../../mister/rtl/gen/sid_music.vh"),
        )
        .expect("sid_music.hex o sid_music.vh non validi")
    }

    /// ROM da `sid_music.hex` e indirizzi da `sid_music.vh`.
    pub fn parse(hex: &str, vh: &str) -> Result<Rom, String> {
        let data = hex
            .split_whitespace()
            .map(|b| u8::from_str_radix(b, 16).map_err(|e| format!("byte {b:?}: {e}")))
            .collect::<Result<Vec<u8>, String>>()?;
        let param = |name: &str| -> Result<u16, String> {
            vh.lines()
                .find_map(|l| {
                    let rest = l.trim().strip_prefix("localparam ")?.strip_prefix(name)?;
                    rest.trim_start()
                        .strip_prefix('=')?
                        .split(';')
                        .next()?
                        .trim()
                        .parse()
                        .ok()
                })
                .ok_or(format!("{name} non trovato in sid_music.vh"))
        };
        // numero decimale dopo "'d" (es. 4'd7 o 12'd901;)
        let num = |s: &str| -> Option<usize> {
            s.split_once('d')
                .and_then(|(_, n)| n.trim().trim_end_matches(';').trim().parse().ok())
        };
        let mut songs: Vec<[u16; 3]> = Vec::new();
        let mut effects: Vec<u16> = Vec::new();
        for l in vh.lines() {
            let l = l.trim();
            // {4'd7, 2'd1}: sid_song_start = 12'd941;
            if let Some(rest) = l.strip_prefix('{')
                && let Some((key, value)) = rest.split_once("}: sid_song_start = ")
                && let Some((song, voice)) = key.split_once(',')
                && let (Some(song), Some(voice), Some(addr)) = (num(song), num(voice), num(value))
                && song >= 1
                && voice < 3
            {
                if songs.len() < song {
                    songs.resize(song, [0; 3]);
                }
                songs[song - 1][voice] = addr as u16;
            }
            // 3'd1: sid_fx_start = 12'd785;
            if let Some((key, value)) = l.split_once(": sid_fx_start = ")
                && let (Some(fx), Some(addr)) = (num(key), num(value))
                && fx >= 1
            {
                if effects.len() < fx {
                    effects.resize(fx, 0);
                }
                effects[fx - 1] = addr as u16;
            }
        }
        // nomi: localparam SID_SONG_TITLE = 1;  (SID_SONG_THEME0 è solo il primo tema)
        let mut names = vec![String::new(); songs.len()];
        for l in vh.lines() {
            let Some(rest) = l.trim().strip_prefix("localparam SID_SONG_") else {
                continue;
            };
            let Some((name, value)) = rest.split_once('=') else {
                continue;
            };
            let name = name.trim();
            if name == "THEME0" {
                continue;
            }
            if let Some(n) = value.split(';').next().and_then(|v| v.trim().parse::<usize>().ok())
                && (1..=songs.len()).contains(&n)
            {
                names[n - 1] = name.to_lowercase();
            }
        }
        if songs.is_empty() || effects.is_empty() {
            return Err("sid_music.vh senza canzoni o senza effetti".into());
        }
        Ok(Rom {
            freq_base: param("SID_FREQ_BASE")?,
            instr_base: param("SID_INSTR_BASE")?,
            data,
            songs,
            effects,
            names,
        })
    }

    /// Byte all'indirizzo `a` (12 bit come nel player Verilog); fuori dalla ROM 0.
    pub fn byte(&self, a: u16) -> u8 {
        self.data.get((a & 0xFFF) as usize).copied().unwrap_or(0)
    }

    /// Numero della canzone (da 1) dal nome (`title`, `theme_hammer`...) o dal numero.
    pub fn song_number(&self, name: &str) -> Option<u8> {
        if let Ok(n) = name.parse::<u8>() {
            return (n as usize <= self.songs.len()).then_some(n);
        }
        let name = name.to_lowercase();
        self.names.iter().position(|n| *n == name).map(|i| i as u8 + 1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rom_inclusa() {
        let rom = Rom::builtin();
        assert!(rom.data.len() > 1000);
        assert_eq!(rom.freq_base, 0);
        assert!(rom.songs.len() >= 13);
        assert!(rom.effects.len() >= 7);
        assert_eq!(rom.song_number("title"), Some(1));
        assert_eq!(rom.song_number("theme_arcade"), Some(7));
        assert_eq!(rom.song_number("theme_guardian"), Some(13));
        // A4 = 440 Hz con il clock a 1 MHz: 440 * 2^24 / 1e6 = 7382
        let a4 = 57 * 2;
        assert_eq!(rom.byte(a4) as u16 | (rom.byte(a4 + 1) as u16) << 8, 7382);
    }
}
