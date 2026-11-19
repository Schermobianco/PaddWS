//! Stato delle schermate fotografato da pong_top (`uis` in fondo a `pong_top.v`), una parola per
//! registro.
//!
//! - 0: [3:0] modo, [14:4] frame dall'inizio del modo, [20:15] frame % 60, [24:21] crediti,
//!   [25] Free Play, [26] scritte dritte, [27] easter egg
//! - 1: pallina del titolo, [8:0] x e [17:9] y dell'angolo in alto a sinistra
//! - 2: scalata: [2:0] livello, [5:3] tipo dell'avversario, [14:6] i suoi bonus, [15] campione a
//!   destra, [16] scalata in corso, [17] sfida tra due, [18] allenamento, [19] livello vinto senza
//!   punti dell'avversario, [20] continue scaduto, [24:21] secondi del continue, [30:25] frame del secondo
//! - 3: [23:0] punti arcade, [27:24] moltiplicatore; 4: [23:0] miglior punteggio, [27:24] posto nuovo
//!   in classifica (15 = nessuno)
//! - 5: iniziali: [17:0] lettere scelte, [19:18] lettera in corso, [25:20] codice di quella sotto il
//!   cursore; [30:26] punti per vincere il livello
//! - 6: [7:0] duelli vinti (BCD), [8] n WINS nella presentazione, [9] alla fine del duello, [10] lato
//!   del vincitore del duello, [15:12] cifra che gira nella classifica
//! - 7: scelta: [2:0] e [5:3] cursori dei bonus, [11:6] e [17:12] bonus presi, [21:18] secondi rimasti,
//!   [22] READY!, [23] a destra la CPU, [25:24] lati bloccati, [26] scelta della racchetta, [28:27]
//!   controllo dell'OSD (HOW TO PLAY)
//! - 8 + 2 i, 9 + 2 i: posto i della classifica: [17:0] iniziali, [21:18] livello; [27:0] punti in BCD
//! - 28: [2:0] e [5:3] cursori delle racchette, [7:6] racchette confermate, [9:8] modalità della demo,
//!   [10] in due, [11] NEXT, [14:12] chi ha vinto, [15] da solo, [16] PERFECT, [17] giocatore a
//!   destra, [19:18] conto alla rovescia, [21:20] palle rimaste, [22] bullet time
//! - 29: punteggi (sinistro nei bit bassi); 30: record del singolo
//! - 31-36: x disegnata e y delle racchette sinistra e destra, altezze (Q16.16, come pong_render)
//! - 37: scritta del bonus o della mossa (label_* di pong_top); 38, 39: punti e premio del finale
//! - 40: next_flags (hit-stop del SUPER); 41: finale ([10:0] frame della parte, [13:11] parte, [18:14]
//!   battute della sfilata, [20:19] scritte a comparsa, [21] lampeggio); 42, 43: SCORE e premio che
//!   salgono; 44: scorrimento dei titoli di coda
//! - 45: OMEGA e JUKEBOX: [7:0] prossimo posto degli oscilloscopi (sid_scope), [8] JUKEBOX acceso, [9]
//!   contro OMEGA (livello 7), [10] allarme, [11] OMEGA battuto (finale speciale), [14:12] forma della
//!   racchetta di OMEGA, [22:15] frame dall'ultima trasformazione (255 = nessuna), [26:23] brano del
//!   JUKEBOX, [29:27] sezione di OMEGA, [30] il brano suona, [31] musica a 0%
//! - 46: [8:0] frame della racchetta di OMEGA che si spezza (prima del finale), [12:9] volume della
//!   musica (passo dell'OSD, 0 = 100%)
//! - 47: schermo VS: [8:0] bonus e [11:9] racchetta del giocatore della scalata; bonus dei due nella
//!   sfida, [20:12] il sinistro e [29:21] il destro (3 bit per bonus, il primo nei bit bassi)

use crate::{Port, map};

pub const M_BOOT: u32 = 0;
pub const M_STRIPES: u32 = 1;
pub const M_LOGO: u32 = 2;
pub const M_TITLE: u32 = 3;
pub const M_DEMO: u32 = 4;
pub const M_GAME: u32 = 5;
pub const M_GAME_OVER: u32 = 6;
pub const M_PICK: u32 = 7;
pub const M_INTRO: u32 = 8;
pub const M_CLEAR: u32 = 9;
pub const M_CONT: u32 = 10;
pub const M_INITIALS: u32 = 11;
pub const M_SCORES: u32 = 12;
pub const M_HOWTO: u32 = 13;
pub const M_CHALLENGER: u32 = 14;
pub const M_ENDING: u32 = 15;

/// Stato di OMEGA e del JUKEBOX (registri 45 e 46).
pub struct Omega {
    pub scope_wptr: u32,
    pub jukebox: bool,
    pub level: bool,
    pub warn: bool,
    pub won: bool,
    pub kind: u32,
    pub morph_age: i32,
    pub track: u32,
    pub section: u32,
    pub playing: bool,
    pub music_off: bool,
    pub shatter: i32,
    pub music_vol: u32,
}

impl Omega {
    pub fn new(r: &Regs) -> Self {
        let (a, b) = (r.w[45], r.w[46]);
        Self {
            scope_wptr: field(a, 0, 8),
            jukebox: field(a, 8, 1) != 0,
            level: field(a, 9, 1) != 0,
            warn: field(a, 10, 1) != 0,
            won: field(a, 11, 1) != 0,
            kind: field(a, 12, 3),
            morph_age: field(a, 15, 8) as i32,
            track: field(a, 23, 4),
            section: field(a, 27, 3),
            playing: field(a, 30, 1) != 0,
            music_off: field(a, 31, 1) != 0,
            shatter: field(b, 0, 9) as i32,
            music_vol: field(b, 9, 4),
        }
    }
}

/// Registri letti in una volta.
pub const WORDS: usize = 64;

pub struct Regs {
    pub w: [u32; WORDS],
    pub mode: u32,
    pub frame: i32,
    pub blink: i32,
    pub credits: i32,
    pub free_play: bool,
    pub upright: bool,
    pub egg: bool,
    pub ball_x: i32,
    pub ball_y: i32,
}

/// Campo di `bits` bit dal bit `at` della parola `w`.
pub fn field(w: u32, at: u32, bits: u32) -> u32 {
    (w >> at) & ((1 << bits) - 1)
}

impl Regs {
    pub fn read(p: &mut dyn Port) -> Self {
        let mut w = [0u32; WORDS];
        for (i, v) in w.iter_mut().enumerate() {
            *v = p.read(map::UIS + i as u32);
        }
        Self::decode(w)
    }

    pub fn decode(w: [u32; WORDS]) -> Self {
        Self {
            mode: w[0] & 15,
            frame: ((w[0] >> 4) & 0x7FF) as i32,
            blink: ((w[0] >> 15) & 63) as i32,
            credits: ((w[0] >> 21) & 15) as i32,
            free_play: w[0] >> 25 & 1 != 0,
            upright: w[0] >> 26 & 1 != 0,
            egg: w[0] >> 27 & 1 != 0,
            ball_x: (w[1] & 0x1FF) as i32,
            ball_y: ((w[1] >> 9) & 0x1FF) as i32,
            w,
        }
    }
}
