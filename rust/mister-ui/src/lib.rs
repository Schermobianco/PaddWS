//! Schermate e scritte del core MiSTer di PADD WS, disegnate dallo schermo a oggetti
//! (`mister/rtl/ui_render.v`).
//!
//! A ogni frame pong_top fotografa lo stato delle schermate (registri `UI_*`, [`regs`]); il firmware
//! se ne accorge dal contatore [`map::SEQ`] e scrive nel banco nascosto del motore la lista degli
//! oggetti del frame dopo ([`dl`]), poi chiede lo scambio, che il motore fa all'inizio della riga 261.
//! Ogni frame si ricostruisce da zero: una schermata è una funzione dello stato (più poche variabili
//! sue in [`Ui`]), così si prova da sola (banco `paddws-ui-sim`).

#![no_std]

#[rustfmt::skip] // generato da tools/gen_mister_ui.py così com'è
pub mod assets;
mod attract;
mod cast;
mod challenge;
pub mod dl;
mod ending;
mod game;
mod howto;
mod intro;
mod jukebox;
mod omega;
pub mod pal;
mod pick;
mod space;
pub mod regs;
pub mod win;

use dl::Dl;
use regs::Regs;

/// Accesso ai registri dello schermo a oggetti e dello stato delle schermate: indirizzi in parole
/// dalla base della regione (nel firmware `0xF001_0000`).
pub trait Port {
    fn read(&mut self, word: u32) -> u32;
    fn write(&mut self, word: u32, value: u32);
    /// Scrive parole consecutive da `word` (nel firmware un ciclo di scritture, senza una chiamata
    /// per parola).
    fn write_block(&mut self, word: u32, values: &[u32]) {
        for (k, v) in values.iter().enumerate() {
            self.write(word + k as u32, *v);
        }
    }
}

/// Immagine della ROM grafica (`tools/gen_mister_ui.py`): prima parola, misure, bit per pixel
/// (scorrimento: 0 = 1 bit) e passo delle righe in parole (scorrimento).
#[derive(Clone, Copy, Debug)]
pub struct Img {
    pub base: u16,
    pub w: u16,
    pub h: u16,
    pub bpp_sh: u8,
    pub stride_sh: u8,
}

/// Indirizzi (in parole) della regione dello schermo a oggetti, come `ui_render.v` e pong_top.
pub mod map {
    /// oggetti del banco nascosto: 8 parole per oggetto
    pub const OBJ: u32 = 0x000;
    /// caratteri del banco nascosto: [7:0] codice del font, [15:8] colore
    pub const TILE: u32 = 0x400;
    /// tabella delle righe del banco nascosto: scostamento in x con segno (10 bit)
    pub const LT: u32 = 0x800;
    /// tavolozza: 256 colori RGB a 24 bit (0 = trasparente)
    pub const PAL: u32 = 0xA00;
    /// fine del frame: [7:0] numero di oggetti, [8] scambio dei banchi
    pub const CTRL: u32 = 0xB00;
    /// lettura: [0] banco mostrato, [1] scambio in attesa, [2] copia dalla DDR3 in corso
    /// (`DMA_BUSY`), [3] grafica della DDR3 caricata (`GFX_OK`)
    pub const STATUS: u32 = 0x000;
    pub const DMA_BUSY: u32 = 4;
    pub const GFX_OK: u32 = 8;
    /// copia dalla DDR3 nella finestra (gfx_ddr.v): sorgente (parola nel file paddws_gfx.rom),
    /// destinazione (parola nella finestra), parole (la scrittura fa partire la copia)
    pub const DMA: u32 = 0xE00;
    /// lettura: registri dello stato delle schermate (pong_top, `uis`)
    pub const UIS: u32 = 0x1000;
    /// lettura: [7:0] numero della foto dello stato
    pub const SEQ: u32 = 0x1040;
    pub const MAX_OBJ: u32 = 128;
    pub const MAX_TILE: u32 = 1024;
    pub const MAX_LT: u32 = 512;
    /// OMEGA: spostamento dei 30 trattini della rete, 10 per parola (3 bit con segno, il primo nei
    /// bit bassi), in tre parole (pong_top)
    pub const NET: u32 = 0xB02;
    /// immagine scrivibile (GRAM_WORDS parole): un'immagine con la base da GRAM_BASE la legge qui
    pub const GRAM: u32 = 0xC00;
    pub const GRAM_WORDS: u32 = 512;
    pub const GRAM_BASE: u16 = 0xC000;
    /// lettura: oscilloscopi delle voci del SID (sid_scope), parola {campione, voce, posto} con il
    /// segno esteso (0 la media di 1 ms, 1 il campione)
    pub const SCOPE: u32 = 0x2000;
}

/// Stato del disegno delle schermate (in .bss nel firmware).
pub struct Ui {
    seq: u32,
    game: game::GameState,
    /// illustrazione isometrica caricata in `pal::SHIP` (durante `THE END`), None = ritratti attivi
    ship_pal: Option<usize>,
    /// finestra della DDR3: ritratti grandi e medi e astronavi copiati
    win: win::Win,
}

impl Default for Ui {
    fn default() -> Self {
        Self::new()
    }
}

impl Ui {
    pub const fn new() -> Self {
        Self {
            seq: 0,
            game: game::GameState { glint_ph: 0 },
            ship_pal: None,
            win: win::Win::new(),
        }
    }

    /// Avvio: la tavolozza.
    #[inline(never)]
    pub fn init(&mut self, p: &mut dyn Port) {
        for (i, c) in pal::COLORS.iter().enumerate() {
            p.write(map::PAL + i as u32, *c);
        }
        // i colori dei ruoli dei ritratti, personaggio per personaggio
        for (k, roles) in assets::portraits::PAL.iter().enumerate() {
            for (j, c) in roles.iter().enumerate() {
                p.write(map::PAL + pal::PORTRAIT as u32 + 8 * k as u32 + 1 + j as u32, *c);
            }
        }
        // le racchette dei personaggi: due copie, la seconda con i segni nel viola di OMEGA (quelli dei
        // sette tipi diventano i suoi tre toni)
        for base in [pal::PADS, pal::PADS_OMEGA] {
            for (j, c) in assets::pads::PAL.iter().enumerate() {
                let c = if base == pal::PADS_OMEGA && j >= assets::pads::MARKS_AT {
                    assets::pads::OMEGA_MARKS[(j - assets::pads::MARKS_AT) % 3]
                } else {
                    *c
                };
                p.write(map::PAL + base as u32 + 1 + j as u32, c);
            }
        }
    }

    /// Se pong_top ha fotografato uno stato nuovo, costruisce il frame dopo e chiede lo scambio.
    /// Restituisce `true` se ha lavorato.
    #[inline(never)]
    pub fn poll(&mut self, p: &mut dyn Port) -> bool {
        let seq = p.read(map::SEQ) & 0xFF;
        if seq == self.seq {
            return false;
        }
        self.seq = seq;
        // il frame di prima non è ancora stato mostrato (non deve succedere): si salta questa foto
        if p.read(map::STATUS) & 2 != 0 {
            return true;
        }
        let r = Regs::read(p);
        // illustrazione isometrica della nave vincitrice su THE END: carica i 15 colori in pal::SHIP
        // (i primi 15 di PORTRAIT, liberi su THE END) e ripristina i ritratti all'uscita
        let om_peek = regs::Omega::new(&r);
        let want_ship = (r.mode == regs::M_ENDING
            && !(om_peek.won && om_peek.shatter < omega::SHATTER)
            && regs::field(r.w[41], 11, 3) == 5)
            .then(|| regs::field(r.w[47], 9, 3).min(6) as usize);
        if self.ship_pal != want_ship {
            self.ship_pal = want_ship;
            if let Some(k) = want_ship {
                for (j, &c) in assets::ships::PAL[k].iter().enumerate() {
                    p.write(map::PAL + pal::SHIP as u32 + 1 + j as u32, c);
                }
            } else {
                for k in 0..2 {
                    for (j, &c) in assets::portraits::PAL[k].iter().enumerate() {
                        p.write(map::PAL + pal::PORTRAIT as u32 + 8 * k as u32 + 1 + j as u32, c);
                    }
                }
            }
        }
        self.win.next_frame();
        let mut d = Dl::new(p, &mut self.win);
        Self::draw(&r, &mut self.game, &mut d);
        d.finish();
        true
    }

    fn draw(r: &Regs, game_state: &mut game::GameState, d: &mut Dl) {
        let om = regs::Omega::new(r);
        // OMEGA: la rete che segue la voce 2 (anche fuori da OMEGA: azzerata)
        omega::net(r, &om, d);
        if om.jukebox {
            jukebox::draw(r, &om, d);
            return;
        }
        // scritte sopra il campo (e lo stato che va avanti a ogni frame)
        game::draw(r, game_state, d);
        d.dx = 0;
        challenge::hud(r, d);
        if matches!(r.mode, regs::M_GAME | regs::M_GAME_OVER) {
            // OMEGA: il nome della forma nuova (la CPU sta dalla parte opposta del campione)
            omega::morph_name(r, &om, d, regs::field(r.w[2], 15, 1) != 0);
        }
        match r.mode {
            regs::M_BOOT..=regs::M_TITLE => attract::draw(r, d),
            regs::M_INTRO => intro::draw(r, d),
            regs::M_PICK => pick::draw(r, d),
            regs::M_HOWTO => howto::draw(r, d),
            regs::M_ENDING if om.won && om.shatter < omega::SHATTER => omega::shatter(&om, d),
            regs::M_ENDING => ending::draw(r, &om, d),
            regs::M_CLEAR | regs::M_CONT | regs::M_INITIALS | regs::M_SCORES | regs::M_CHALLENGER => {
                challenge::screen(r, d)
            }
            _ => {}
        }
    }
}
