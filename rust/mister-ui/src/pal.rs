//! Tavolozza dello schermo a oggetti (scritta all'avvio): indici dei colori delle schermate.

/// trasparente
pub const NONE: u8 = 0;
/// nero "solido" della scena del titolo: la pallina ci rimbalza contro (pong_top lo riconosce)
pub const SOLID: u8 = 1;
pub const BLACK: u8 = 2;
pub const WHITE: u8 = 3;
/// giallo dell'attract, accento di NEXT
pub const YELLOW: u8 = 4;
pub const ACCENT: u8 = YELLOW;
/// verde dei fosfori dell'auto-test
pub const PHOSPHOR: u8 = 5;
pub const GRAY: u8 = 6;
pub const DIM: u8 = 7;
/// banda rossa del nuovo sfidante
pub const BAND: u8 = 8;
/// immagine gialla dietro al nome del RUSH
pub const GHOST: u8 = 9;
/// scia della palla, dalla più chiara
pub const TRAIL1: u8 = 10;
pub const TRAIL2: u8 = 11;
pub const TRAIL3: u8 = 12;
/// dettagli grigi delle racchette (canne del BLASTER, pesi dell'HAMMER)
pub const DETAIL: u8 = 13;
/// immagini del RUSH dietro la racchetta, dalla più scura
pub const PGHOST1: u8 = 14;
pub const PGHOST2: u8 = 15;
pub const PGHOST3: u8 = 49;
/// HOW TO PLAY: cornici, grigio, scia di RISING STRIKE; scritte (base: 1 bianco, 2 grigio, 3 giallo);
/// figurine (base: codici 1-15 di pong_howto.vh), spente e accese
pub const HT_FRAME: u8 = 50;
pub const HT_GRAY: u8 = 51;
pub const HT_TRAIL: u8 = 52;
pub const HT_TEXT: u8 = 52;
pub const HT_SPR: u8 = 56;
pub const HT_SPR_LIT: u8 = 71;
/// YOU WIN spento (prima della palla)
pub const WIN_DIM: u8 = 87;
/// grigio scuro delle racchette spente (next_render, diverso dal DIM delle schermate della scalata)
pub const NDIM: u8 = 88;
/// rosso del finale (KO)
pub const RED: u8 = 89;
/// racchette disegnate a rettangoli di prima (1 corpo, 2 segno, 3 dettaglio, 5-7 immagini del RUSH),
/// non più usate; da 98 i colori delle miniature di prima
pub const PAD: u8 = 90;
/// OMEGA con l'easter egg RED: la sua racchetta viola
pub const PURPLE: u8 = 106;
/// titoli disegnati tutti bianchi (il sigillo di OMEGA che lampeggia): ruoli 1-8 bianchi
pub const TL_WHITE: u8 = 106;

/// viola del punto di domanda di OMEGA (casella della scelta, sfilata del finale), come gli occhi
/// della sua sagoma
pub const OMEGA_Q: u8 = 115;
/// bordo delle caselle della griglia della scelta
pub const CELL_FRAME: u8 = 116;
/// Ritratti dei personaggi (assets::portraits, 4 bit per pixel: il ruolo + 1): la base della tavolozza
/// del personaggio k (i sette tipi, poi OMEGA) è PORTRAIT + 8 k; i colori li scrive `Ui::init`.
pub const PORTRAIT: u8 = 120;
/// Racchette dei personaggi fuori dalla partita (assets::pads, 8 bit per pixel: il colore è la base più
/// il valore del pixel, da 1 a `pads::PAL.len()`): PADS con il corpo bianco, PADS_OMEGA con quello di
/// OMEGA (rosso, viola con l'easter egg). I colori li scrive `Ui`.
pub const PADS: u8 = 183;
pub const PADS_OMEGA: u8 = PADS + crate::assets::pads::PAL.len() as u8;

/// Titoli disegnati (4 bit per pixel: il ruolo del colore, 0 trasparente): basi della tavolozza per
/// il ruolo 1-8 (nero, bianco, giallo, giallo scuro, grigio, grigio scuro, rosso, rosso scuro). HI:
/// il bianco diventa giallo (lampo); GHOST: tutto giallo scuro (immagine del RUSH); GLINT: il giallo
/// diventa bianco (riflesso di PERFECT).
pub const TL: u8 = 16;
pub const TL_HI: u8 = 24;
pub const TL_GHOST: u8 = 32;
pub const TL_GLINT: u8 = 40;

const K: u32 = 0x000000;
const W: u32 = 0xFFFFFF;
const Y: u32 = 0xFFD225;
const DY: u32 = 0x8A7114;
const TG: u32 = 0x6E6E6E;
const DG: u32 = 0x3A3A3A;
const R: u32 = 0xE62828;
const DR: u32 = 0x5A0A0A;
const GH: u32 = 0x7F6912;

/// Colori RGB a 24 bit, nell'ordine degli indici.
pub const COLORS: [u32; 117] = [
    0x000000, 0x000000, K, W, Y, 0xD4F7C8, 0xB4B4B4, DG, 0x8C1414, GH, 0x9A9A9A, 0x5E5E5E, 0x303030, 0xA9B0B8,
    0x2E2607, 0x5C4C0D, // TL
    0, K, W, Y, DY, TG, DG, R, // TL_HI (la voce 24 è il rosso scuro di TL)
    DR, K, Y, Y, DY, TG, DG, R, // TL_GHOST
    DR, GH, GH, GH, GH, GH, GH, GH, // TL_GLINT
    GH, K, W, W, W, TG, DG, R, DR, 0x8A7114, // 50: HOW TO PLAY
    0x464646, 0x969696, 0x735E11, W, 0x969696, Y, // 56: figurine spente (codici 1-15)
    0, 0x37373C, 0x191919, 0xBEBEC3, 0x8C1414, 0x5A5A5F, W, R, 0x8C1414, 0xFF6E6E, 0x1E1E23, 0x6E6E73, 0x505058,
    0x969696, K, // 71: figurine accese (la voce 71 è il codice 15 delle spente)
    K, 0x37373C, 0x191919, 0xBEBEC3, R, Y, W, R, 0x8C1414, 0xFF6E6E, 0x1E1E23, 0x6E6E73, 0x505058, Y, K, K,
    // 87
    0x4A4A4A, 0x3F3F3F, R, // 90: racchette della scelta
    0, W, Y, 0xA9B0B8, 0, 0x2E2607, 0x5C4C0D, 0x8A7114, 0, 0xB4B4B4, 0x3F3F3F, 0x3F3F3F, 0, 0x2E2607, 0x2E2607,
    0x5C4C0D, // 106: viola di OMEGA, poi TL_WHITE (ruoli 1-8)
    0xA040E0, W, W, W, W, W, W, W, W, // 115: punto di domanda di OMEGA, bordo delle caselle
    0xE040FF, 0x464646,
];
