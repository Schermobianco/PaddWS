//! Generato da tools/gen_mister_ui.py: non modificare a mano.
//! Codici del font 8x8 e immagini della ROM grafica dello schermo a oggetti.

use crate::Img;

/// Codice del font di ogni carattere ASCII (quelli che mancano diventano spazi; 0x7F è "©").
pub const FONT_MAP: [u8; 128] = [
    36, 36, 36, 36, 36, 36, 36, 36, 36, 36, 36, 36, 36, 36, 36, 36,
    36, 36, 36, 36, 36, 36, 36, 36, 36, 36, 36, 36, 36, 36, 36, 36,
    36, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 37, 50, 51, 38, 52,
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 53, 54, 55, 56, 57, 58,
    59, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
    25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 60, 61, 62, 63, 64,
    65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80,
    81, 82, 83, 84, 85, 86, 87, 88, 39, 89, 90, 91, 92, 93, 94, 95,
];
/// Codice di "©".
pub const CODE_COPY: u8 = 95;
/// Colonne con l'inchiostro di ogni codice del font (bit 7 = colonna 0): le lettere delle
/// scritte animate sono gruppi di colonne accese, come `verilog_letters` di gen_attract_assets.py.
pub const FONT_COLS: [u8; 256] = [
    254, 126, 254, 254, 254, 254, 254, 254, 254, 254, 254, 254, 254, 254, 254, 254,
    254, 254, 126, 254, 254, 126, 254, 254, 254, 254, 254, 254, 254, 126, 254, 254,
    254, 254, 126, 254, 0, 126, 48, 254, 56, 108, 254, 254, 254, 254, 48, 60,
    120, 254, 112, 126, 254, 48, 112, 124, 254, 124, 254, 254, 60, 254, 120, 124,
    254, 24, 254, 254, 254, 254, 254, 126, 254, 254, 126, 124, 254, 126, 254, 254,
    254, 254, 254, 126, 254, 126, 254, 126, 254, 254, 254, 60, 24, 120, 254, 255,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
];

pub const IMG_LOGO: Img = Img { base: 0, w: 152, h: 51, bpp_sh: 0, stride_sh: 3 };
pub const IMG_WS: Img = Img { base: 408, w: 22, h: 8, bpp_sh: 0, stride_sh: 0 };
pub const IMG_SCORE_0: Img = Img { base: 416, w: 22, h: 22, bpp_sh: 0, stride_sh: 0 };
pub const IMG_SCORE_1: Img = Img { base: 438, w: 22, h: 22, bpp_sh: 0, stride_sh: 0 };
pub const IMG_SCORE_2: Img = Img { base: 460, w: 22, h: 22, bpp_sh: 0, stride_sh: 0 };
pub const IMG_SCORE_3: Img = Img { base: 482, w: 22, h: 22, bpp_sh: 0, stride_sh: 0 };
pub const IMG_SCORE_4: Img = Img { base: 504, w: 22, h: 22, bpp_sh: 0, stride_sh: 0 };
pub const IMG_SCORE_5: Img = Img { base: 526, w: 22, h: 22, bpp_sh: 0, stride_sh: 0 };
pub const IMG_SCORE_6: Img = Img { base: 548, w: 22, h: 22, bpp_sh: 0, stride_sh: 0 };
pub const IMG_SCORE_7: Img = Img { base: 570, w: 22, h: 22, bpp_sh: 0, stride_sh: 0 };
pub const IMG_SCORE_8: Img = Img { base: 592, w: 22, h: 22, bpp_sh: 0, stride_sh: 0 };
pub const IMG_SCORE_9: Img = Img { base: 614, w: 22, h: 22, bpp_sh: 0, stride_sh: 0 };
pub const IMG_ICON_0: Img = Img { base: 636, w: 9, h: 9, bpp_sh: 0, stride_sh: 0 };
pub const IMG_ICON_1: Img = Img { base: 645, w: 9, h: 9, bpp_sh: 0, stride_sh: 0 };
pub const IMG_ICON_2: Img = Img { base: 654, w: 9, h: 9, bpp_sh: 0, stride_sh: 0 };
pub const IMG_ICON_3: Img = Img { base: 663, w: 9, h: 9, bpp_sh: 0, stride_sh: 0 };
pub const IMG_ICON_4: Img = Img { base: 672, w: 9, h: 9, bpp_sh: 0, stride_sh: 0 };
pub const IMG_ICON_5: Img = Img { base: 681, w: 9, h: 9, bpp_sh: 0, stride_sh: 0 };
pub const IMG_ICON_6: Img = Img { base: 690, w: 9, h: 9, bpp_sh: 0, stride_sh: 0 };
pub const IMG_ICON_7: Img = Img { base: 699, w: 9, h: 9, bpp_sh: 0, stride_sh: 0 };
pub const IMG_CHALLENGER: Img = Img { base: 708, w: 192, h: 38, bpp_sh: 2, stride_sh: 5 };
pub const IMG_PERFECT: Img = Img { base: 1924, w: 114, h: 25, bpp_sh: 2, stride_sh: 4 };
pub const IMG_NAME_ARCADE: Img = Img { base: 2324, w: 58, h: 15, bpp_sh: 2, stride_sh: 3 };
pub const IMG_NAME_TITAN: Img = Img { base: 2444, w: 44, h: 26, bpp_sh: 2, stride_sh: 3 };
pub const IMG_NAME_HAMMER: Img = Img { base: 2652, w: 80, h: 16, bpp_sh: 2, stride_sh: 4 };
pub const IMG_NAME_TWIST: Img = Img { base: 2908, w: 46, h: 20, bpp_sh: 2, stride_sh: 3 };
pub const IMG_NAME_BLASTER: Img = Img { base: 3068, w: 86, h: 14, bpp_sh: 2, stride_sh: 4 };
pub const IMG_NAME_RUSH: Img = Img { base: 3292, w: 50, h: 14, bpp_sh: 2, stride_sh: 3 };
pub const IMG_NAME_GUARDIAN: Img = Img { base: 3404, w: 77, h: 14, bpp_sh: 2, stride_sh: 4 };
pub const IMG_WARNING: Img = Img { base: 3628, w: 192, h: 38, bpp_sh: 2, stride_sh: 5 };
pub const IMG_NAME_OMEGA: Img = Img { base: 4844, w: 80, h: 33, bpp_sh: 2, stride_sh: 4 };
pub const IMG_PAD_PREVIEW_0: Img = Img { base: 5372, w: 10, h: 33, bpp_sh: 3, stride_sh: 2 };
pub const IMG_PAD_PREVIEW_1: Img = Img { base: 5504, w: 21, h: 51, bpp_sh: 3, stride_sh: 3 };
pub const IMG_PAD_PREVIEW_2: Img = Img { base: 5912, w: 18, h: 41, bpp_sh: 3, stride_sh: 3 };
pub const IMG_PAD_PREVIEW_3: Img = Img { base: 6240, w: 22, h: 41, bpp_sh: 3, stride_sh: 3 };
pub const IMG_PAD_PREVIEW_4: Img = Img { base: 6568, w: 19, h: 45, bpp_sh: 3, stride_sh: 3 };
pub const IMG_PAD_PREVIEW_5: Img = Img { base: 6928, w: 34, h: 35, bpp_sh: 3, stride_sh: 4 };
pub const IMG_PAD_PREVIEW_6: Img = Img { base: 7488, w: 17, h: 33, bpp_sh: 3, stride_sh: 3 };
pub const IMG_PAD_PLAIN_3: Img = Img { base: 7752, w: 14, h: 41, bpp_sh: 3, stride_sh: 2 };
pub const IMG_PAD_PLAIN_5: Img = Img { base: 7916, w: 17, h: 35, bpp_sh: 3, stride_sh: 3 };
pub const IMG_PICK_NET: Img = Img { base: 8196, w: 2, h: 160, bpp_sh: 0, stride_sh: 0 };
pub const IMG_CAP_FRAME: Img = Img { base: 8356, w: 12, h: 12, bpp_sh: 0, stride_sh: 0 };
pub const IMG_VS3: Img = Img { base: 8368, w: 48, h: 24, bpp_sh: 0, stride_sh: 1 };
pub const IMG_HT_SPRITE_0: Img = Img { base: 10276, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_HT_SPRITE_1: Img = Img { base: 10404, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_HT_SPRITE_2: Img = Img { base: 10532, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_HT_SPRITE_3: Img = Img { base: 10660, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_HT_SPRITE_4: Img = Img { base: 10788, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_HT_SPRITE_5: Img = Img { base: 10916, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_HT_SPRITE_6: Img = Img { base: 11044, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_HT_SPRITE_7: Img = Img { base: 11172, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_HT_SPRITE_8: Img = Img { base: 11300, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_HT_SPRITE_9: Img = Img { base: 11428, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_HT_ARROW: Img = Img { base: 11556, w: 5, h: 7, bpp_sh: 0, stride_sh: 0 };
pub const IMG_PT_BIG_ARCADE: Img = Img { base: 14553, w: 88, h: 104, bpp_sh: 2, stride_sh: 0 };
pub const IMG_PT_BIG_TITAN: Img = Img { base: 15697, w: 88, h: 104, bpp_sh: 2, stride_sh: 0 };
pub const IMG_PT_BIG_HAMMER: Img = Img { base: 16841, w: 88, h: 104, bpp_sh: 2, stride_sh: 0 };
pub const IMG_PT_BIG_TWIST: Img = Img { base: 17985, w: 88, h: 104, bpp_sh: 2, stride_sh: 0 };
pub const IMG_PT_BIG_BLASTER: Img = Img { base: 19129, w: 88, h: 104, bpp_sh: 2, stride_sh: 0 };
pub const IMG_PT_BIG_RUSH: Img = Img { base: 20273, w: 88, h: 104, bpp_sh: 2, stride_sh: 0 };
pub const IMG_PT_BIG_GUARDIAN: Img = Img { base: 21417, w: 88, h: 104, bpp_sh: 2, stride_sh: 0 };
pub const IMG_PT_BIG_OMEGA: Img = Img { base: 22561, w: 88, h: 104, bpp_sh: 2, stride_sh: 0 };
pub const IMG_PT_SMALL_ARCADE: Img = Img { base: 23705, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_PT_SMALL_TITAN: Img = Img { base: 23833, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_PT_SMALL_HAMMER: Img = Img { base: 23961, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_PT_SMALL_TWIST: Img = Img { base: 24089, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_PT_SMALL_BLASTER: Img = Img { base: 24217, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_PT_SMALL_RUSH: Img = Img { base: 24345, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_PT_SMALL_GUARDIAN: Img = Img { base: 24473, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_PT_SMALL_OMEGA: Img = Img { base: 24601, w: 32, h: 32, bpp_sh: 2, stride_sh: 2 };
pub const IMG_PT_MID_ARCADE: Img = Img { base: 24729, w: 64, h: 72, bpp_sh: 2, stride_sh: 3 };
pub const IMG_PT_MID_ARCADE_DEFEATED: Img = Img { base: 25305, w: 64, h: 72, bpp_sh: 2, stride_sh: 3 };
pub const IMG_PT_MID_TITAN: Img = Img { base: 25881, w: 64, h: 72, bpp_sh: 2, stride_sh: 3 };
pub const IMG_PT_MID_TITAN_DEFEATED: Img = Img { base: 26457, w: 64, h: 72, bpp_sh: 2, stride_sh: 3 };
pub const IMG_PT_MID_HAMMER: Img = Img { base: 27033, w: 64, h: 72, bpp_sh: 2, stride_sh: 3 };
pub const IMG_PT_MID_HAMMER_DEFEATED: Img = Img { base: 27609, w: 64, h: 72, bpp_sh: 2, stride_sh: 3 };
pub const IMG_PT_MID_TWIST: Img = Img { base: 28185, w: 64, h: 72, bpp_sh: 2, stride_sh: 3 };
pub const IMG_PT_MID_TWIST_DEFEATED: Img = Img { base: 28761, w: 64, h: 72, bpp_sh: 2, stride_sh: 3 };
pub const IMG_PT_MID_BLASTER: Img = Img { base: 29337, w: 64, h: 72, bpp_sh: 2, stride_sh: 3 };
pub const IMG_PT_MID_BLASTER_DEFEATED: Img = Img { base: 29913, w: 64, h: 72, bpp_sh: 2, stride_sh: 3 };
pub const IMG_PT_MID_RUSH: Img = Img { base: 30489, w: 64, h: 72, bpp_sh: 2, stride_sh: 3 };
pub const IMG_PT_MID_RUSH_DEFEATED: Img = Img { base: 31065, w: 64, h: 72, bpp_sh: 2, stride_sh: 3 };
pub const IMG_PT_MID_GUARDIAN: Img = Img { base: 31641, w: 64, h: 72, bpp_sh: 2, stride_sh: 3 };
pub const IMG_PT_MID_GUARDIAN_DEFEATED: Img = Img { base: 32217, w: 64, h: 72, bpp_sh: 2, stride_sh: 3 };
pub const IMG_PT_MID_OMEGA: Img = Img { base: 32793, w: 64, h: 72, bpp_sh: 2, stride_sh: 3 };
pub const IMG_PT_MID_OMEGA_DEFEATED: Img = Img { base: 33369, w: 64, h: 72, bpp_sh: 2, stride_sh: 3 };
pub const IMG_PT_MID_OMEGA_LOCKED: Img = Img { base: 33945, w: 64, h: 72, bpp_sh: 2, stride_sh: 3 };
pub const IMG_SHIP_ARCADE: Img = Img { base: 34521, w: 160, h: 90, bpp_sh: 2, stride_sh: 0 };
pub const IMG_SHIP_TITAN: Img = Img { base: 36321, w: 160, h: 90, bpp_sh: 2, stride_sh: 0 };
pub const IMG_SHIP_HAMMER: Img = Img { base: 38121, w: 160, h: 90, bpp_sh: 2, stride_sh: 0 };
pub const IMG_SHIP_TWIST: Img = Img { base: 39921, w: 160, h: 90, bpp_sh: 2, stride_sh: 0 };
pub const IMG_SHIP_BLASTER: Img = Img { base: 41721, w: 160, h: 90, bpp_sh: 2, stride_sh: 0 };
pub const IMG_SHIP_RUSH: Img = Img { base: 43521, w: 160, h: 90, bpp_sh: 2, stride_sh: 0 };
pub const IMG_SHIP_GUARDIAN: Img = Img { base: 45321, w: 160, h: 90, bpp_sh: 2, stride_sh: 0 };

/// Attract (assets/attract/attract.json, come pong_attract.vh).
pub mod at {
    pub const BOOT_X: i32 = 40;
    pub const BOOT_Y: i32 = 60;
    pub const BOOT_STEP: i32 = 14;
    pub const BOOT_GRID_FROM: i32 = 228;
    pub const BOOT_LINE_RECIP: i32 = 2185;
    pub const STRIPE_START_STEP: i32 = 12;
    pub const SLIDE_LAST: i32 = 42;
    pub const STRIPE_H: i32 = 12;
    pub const LOGO_X: i32 = 82;
    pub const LOGO_Y: i32 = 94;
    pub const WIPE_FRAMES: i32 = 84;
    pub const FLASH_FRAMES: i32 = 3;
    pub const WS_X: i32 = 241;
    pub const WS_Y: i32 = 136;
    pub const LABEL_Y: i32 = 172;
    pub const CREDIT_Y: i32 = 204;
    pub const COPYRIGHT_Y: i32 = 222;
    pub const LABEL_FROM: i32 = 54;
    pub const BLINK_ON: i32 = 37;
    pub const DEMO_LABEL_Y: i32 = 112;
    pub const GAME_OVER_Y: i32 = 112;
    pub const WINNER_Y: i32 = 132;
    pub const STRIPE_ROWS: [i32; 3] = [96, 115, 134];
    pub const WS_OFF: [(i32, i32); 2] = [(0, 15), (30, 45)];
    pub const BOOT_LINES: [&[u8]; 6] = [b"PADD WS  V4.6", b"", b"RAM ........ OK", b"ROM ........ OK", b"VIDEO 240P .. OK", b"AUDIO ...... OK"];
    pub const STRIPE_LEFT_END: [i32; 43] = [0, 8, 15, 22, 29, 35, 40, 45, 50, 55, 58, 62, 65, 68, 71, 73, 75, 76, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 77, 77, 76, 76, 76, 75, 75, 75];
    pub const STRIPE_RIGHT_START: [i32; 43] = [320, 312, 304, 296, 290, 283, 277, 272, 267, 263, 258, 255, 251, 248, 246, 243, 241, 239, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 238, 239, 240, 240, 240, 241, 241, 241];
}
/// Cifre dei punteggi (22x22), dalla 0 alla 9.
pub const IMG_SCORE: [Img; 10] = [IMG_SCORE_0, IMG_SCORE_1, IMG_SCORE_2, IMG_SCORE_3, IMG_SCORE_4, IMG_SCORE_5, IMG_SCORE_6, IMG_SCORE_7, IMG_SCORE_8, IMG_SCORE_9];

/// Misure del gioco (mister/rtl/gen/pong_params.vh) e scritte di NEXT (tools/gen_next_assets.py).
pub mod game {
    /// altezza in pixel delle racchette di ogni tipo (PaddleKind)
    pub const KIND_H: [i32; 7] = [32, 48, 40, 40, 44, 34, 32];
    pub const PW: i32 = 4;
    pub const BLASTER_SHOTS: i32 = 6;
    /// lato delle capsule in partita (e nella scelta dei bonus)
    pub const CAP: i32 = 12;
    pub const BONUS_NAMES: [&[u8]; 8] = [b"TELEPORT", b"SMASH", b"SLOW", b"CURVE", b"GHOST", b"SUPER", b"STEER", b"BULLET"];
    pub const KIND_NAMES: [&[u8]; 7] = [b"ARCADE", b"TITAN", b"HAMMER", b"TWIST", b"BLASTER", b"RUSH", b"GUARDIAN"];
    pub const KIND_TAGS: [&[u8]; 7] = [b"MORE BONUSES", b"TALL BUT SLOW", b"POWER SHOTS", b"TILTS WITH SPEED", b"SHOOTS CAPSULES", b"LONG DASH", b"FIVE-PIECE WALL"];
    pub const MOVE_NAMES: [&[u8]; 2] = [b"STRAIGHT SHOT", b"RISING STRIKE"];
    /// GUARDIAN: prima colonna di ogni lettera del nome disegnato
    pub const GUARDIAN_X: [i32; 8] = [0, 10, 20, 30, 40, 51, 60, 70];
    /// BLASTER (in corsivo): lettera j dalla colonna BLASTER_X0 + BLASTER_STEP j, riga v spostata di
    /// BLASTER_SLANT[v]
    pub const BLASTER_X0: i32 = 22;
    pub const BLASTER_STEP: i32 = 9;
    pub const BLASTER_LETTERS: i32 = 7;
    pub const BLASTER_SLANT: [i32; 14] = [4, 4, 3, 3, 3, 2, 2, 2, 1, 1, 1, 0, 0, 0];
    pub const BLASTER_CX0: i32 = 27;
    /// seno in Q8 (sin_q8 di pong_next.vh)
    pub const SIN_Q8: [i32; 64] = [0, 25, 50, 74, 98, 121, 142, 162, 181, 198, 213, 226, 237, 245, 251, 255, 256, 255, 251, 245, 237, 226, 213, 198, 181, 162, 142, 121, 98, 74, 50, 25, 0, -25, -50, -74, -98, -121, -142, -162, -181, -198, -213, -226, -237, -245, -251, -255, -256, -255, -251, -245, -237, -226, -213, -198, -181, -162, -142, -121, -98, -74, -50, -25];
}

/// HOW TO PLAY (mister/rtl/gen/pong_howto.vh e i suoi file).
pub mod howto {
    pub const TEXT_ROWS: i32 = 92;
    pub const SPRITES: i32 = 10;
    pub const SKIP_Y0: i32 = 228;
    pub const SKIP_Y1: i32 = 235;
    pub const BOX0_Y: i32 = 42;
    pub const BOX1_Y: i32 = 112;
    pub const CY0: i32 = 86;
    pub const CY1: i32 = 156;
    pub const AX: i32 = 11;
    pub const AY: i32 = 16;
    pub const SLOT_W: i32 = 26;
    pub const JOY_S0: i32 = 30;
    pub const JOY_S1: i32 = 64;
    pub const JOY_S2: i32 = 98;
    pub const JOY_A: i32 = 146;
    pub const KNOB_S0: i32 = 30;
    pub const KNOB_S1: i32 = 64;
    pub const KNOB_A: i32 = 112;
    pub const ARROW_DX: i32 = 15;
    pub const LEG_CY: i32 = 205;
    pub const LEG_X0: i32 = 22;
    pub const LEG_X1: i32 = 88;
    pub const LEG_X2: i32 = 170;
    /// prima parola delle righe delle scritte (20 parole per riga; la riga 92 è vuota)
    pub const TEXT_BASE: u32 = 8416;
    /// riga delle scritte di ogni riga dello schermo, per controllo (joystick, paddle, spinner)
    pub const ROWS: [[u8; 240]; 3] = [
        [92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 0, 1, 2, 3, 4, 5, 6, 92, 92, 92, 92, 92, 92, 92, 7, 8, 9, 10, 11, 12, 13, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 14, 15, 16, 17, 18, 19, 20, 92, 92, 92, 92, 92, 92, 92, 21, 22, 23, 24, 25, 26, 27, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 28, 29, 30, 31, 32, 33, 34, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 35, 36, 37, 38, 39, 40, 41, 92, 92, 92, 92, 92, 92, 92, 42, 43, 44, 45, 46, 47, 48, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 28, 29, 30, 31, 32, 33, 34, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 49, 50, 51, 52, 53, 54, 55, 56, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 57, 58, 59, 60, 61, 62, 63, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 64, 65, 66, 67, 68, 69, 70, 92, 92, 92, 92, 92],
        [92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 0, 1, 2, 3, 4, 5, 6, 92, 92, 92, 92, 92, 92, 92, 71, 72, 73, 74, 75, 76, 77, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 14, 15, 16, 17, 18, 19, 20, 92, 92, 92, 92, 92, 92, 92, 21, 22, 23, 24, 25, 26, 27, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 78, 79, 80, 81, 82, 83, 84, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 35, 36, 37, 38, 39, 40, 41, 92, 92, 92, 92, 92, 92, 92, 42, 43, 44, 45, 46, 47, 48, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 78, 79, 80, 81, 82, 83, 84, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 49, 50, 51, 52, 53, 54, 55, 56, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 57, 58, 59, 60, 61, 62, 63, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 64, 65, 66, 67, 68, 69, 70, 92, 92, 92, 92, 92],
        [92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 0, 1, 2, 3, 4, 5, 6, 92, 92, 92, 92, 92, 92, 92, 85, 86, 87, 88, 89, 90, 91, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 14, 15, 16, 17, 18, 19, 20, 92, 92, 92, 92, 92, 92, 92, 21, 22, 23, 24, 25, 26, 27, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 78, 79, 80, 81, 82, 83, 84, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 35, 36, 37, 38, 39, 40, 41, 92, 92, 92, 92, 92, 92, 92, 42, 43, 44, 45, 46, 47, 48, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 78, 79, 80, 81, 82, 83, 84, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 49, 50, 51, 52, 53, 54, 55, 56, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 57, 58, 59, 60, 61, 62, 63, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 92, 64, 65, 66, 67, 68, 69, 70, 92, 92, 92, 92, 92],
    ];
}

/// Racchette fuori dalla partita: immagine, prima colonna t (0 = retro del corpo) e prima riga r.
pub mod pads {
    use crate::Img;
    pub const PREVIEW: [(Img, i32, i32); 7] = [
        (Img { base: 5372, w: 10, h: 33, bpp_sh: 3, stride_sh: 2 }, -6, 0),
        (Img { base: 5504, w: 21, h: 51, bpp_sh: 3, stride_sh: 3 }, -17, 0),
        (Img { base: 5912, w: 18, h: 41, bpp_sh: 3, stride_sh: 3 }, -14, 0),
        (Img { base: 6240, w: 22, h: 41, bpp_sh: 3, stride_sh: 3 }, -11, 0),
        (Img { base: 6568, w: 19, h: 45, bpp_sh: 3, stride_sh: 3 }, -12, 0),
        (Img { base: 6928, w: 34, h: 35, bpp_sh: 3, stride_sh: 4 }, -30, 0),
        (Img { base: 7488, w: 17, h: 33, bpp_sh: 3, stride_sh: 3 }, -13, 0),
    ];
    pub const PLAIN: [(Img, i32, i32); 7] = [
        (Img { base: 5372, w: 10, h: 33, bpp_sh: 3, stride_sh: 2 }, -6, 0),
        (Img { base: 5504, w: 21, h: 51, bpp_sh: 3, stride_sh: 3 }, -17, 0),
        (Img { base: 5912, w: 18, h: 41, bpp_sh: 3, stride_sh: 3 }, -14, 0),
        (Img { base: 7752, w: 14, h: 41, bpp_sh: 3, stride_sh: 2 }, -10, 0),
        (Img { base: 6568, w: 19, h: 45, bpp_sh: 3, stride_sh: 3 }, -12, 0),
        (Img { base: 7916, w: 17, h: 35, bpp_sh: 3, stride_sh: 3 }, -13, 0),
        (Img { base: 7488, w: 17, h: 33, bpp_sh: 3, stride_sh: 3 }, -13, 0),
    ];
    /// Colori dei valori 1..=33 dei pixel (a partire da pal::PADS + 1).
    pub const PAL: [u32; 33] = [
        0xFFFFFF, 0xD4D6E0, 0xB4B4B4, 0xE2E2E6, 0x5C5C62, 0x34343C, 0x000000, 0xFFD225,
        0x30303A, 0x0B2428, 0x16484F, 0x206C77, 0xFFD21E, 0x997E12, 0xFFE683, 0xE67828,
        0x8A4818, 0xF1B589, 0xE62828, 0x8A1818, 0xF18989, 0x9646C8, 0x5A2A78, 0xC599E1,
        0x46BE46, 0x2A722A, 0x99DB99, 0x3CC8DC, 0x247884, 0x94E1EC, 0x5A96FF, 0x365A99,
        0xA4C5FF,
    ];
    /// Corpo e corpo in ombra di OMEGA (valori 1 e 2): viola (anche con l'easter egg).
    pub const OMEGA_BODY: [[u32; 2]; 2] = [
        [0xA040E0, 0x8536C5],
        [0xA040E0, 0x8536C5],
    ];
}

/// Finale della scalata (mister/rtl/gen/pong_ending.vh e i suoi file).
pub mod ending {
    pub const LEN0: i32 = 210;
    pub const LEN1: i32 = 540;
    pub const LEN2: i32 = 540;
    pub const LEN3: i32 = 420;
    pub const LEN4: i32 = 1526;
    pub const LEN5: i32 = 270;
    pub const TOTAL: i32 = 3506;
    pub const YOU_WIN_AT: i32 = 60;
    pub const SKIP_AFTER: i32 = 30;
    pub const BEAT: i32 = 30;
    pub const SCORE_COUNT: i32 = 180;
    pub const BONUS_END: i32 = 240;
    pub const TOTAL_AT: i32 = 270;
    pub const FLASH0: i32 = 30;
    pub const FLASH5: i32 = 40;
    pub const TEXT_ROWS: i32 = 299;
    pub const TEXT_BYTES: i32 = 11960;
    pub const MAP_SIZE: i32 = 833;
    pub const FW_SIZE: i32 = 11812;
    pub const GLYPH_H: i32 = 8;
    pub const CELL: i32 = 8;
    pub const STRIP_ROW0: i32 = 0;
    pub const STAMP_ROW0: i32 = 8;
    pub const STAMP_W: i32 = 76;
    pub const STAMP_H: i32 = 26;
    pub const DIG_X0: i32 = 199;
    pub const PARADE_X0: i32 = 8;
    pub const PARADE_DX: i32 = 80;
    pub const PARADE_W: i32 = 64;
    pub const PARADE_H: i32 = 72;
    pub const PARADE_ROW0: i32 = 44;
    pub const PARADE_ROW1: i32 = 132;
    pub const PARADE_NAME0: i32 = 120;
    pub const PARADE_NAME1: i32 = 208;
    pub const PARADE_STAMP_UP: i32 = 14;
    pub const WIN0_TOP: i32 = 106;
    pub const WIN0_H: i32 = 36;
    pub const WIN0_BASE: i32 = 0;
    pub const WIN1_TOP: i32 = 28;
    pub const WIN1_H: i32 = 7;
    pub const WIN1_BASE: i32 = 36;
    pub const WIN2_TOP: i32 = 46;
    pub const WIN2_H: i32 = 98;
    pub const WIN2_BASE: i32 = 43;
    pub const WIN3_TOP: i32 = 180;
    pub const WIN3_H: i32 = 23;
    pub const WIN3_BASE: i32 = 141;
    pub const WIN5_TOP: i32 = 174;
    pub const WIN5_H: i32 = 7;
    pub const WIN5_BASE: i32 = 164;
    pub const CRED_C0: i32 = 281;
    pub const CRED_LEN: i32 = 662;
    pub const CRED_BASE: i32 = 171;
    pub const CRED_SMAX: i32 = 820;
    pub const FWS: i32 = 15;
    pub const FW_STRIDE: i32 = 80;
    /// prima parola delle righe di bitmap (10 parole per riga)
    pub const TEXT_BASE: u32 = 11563;
    /// mappa delle righe: [8:0] riga, [12:9] riga del glifo, [21:13] x, [23:22] scala, [25:24] colore,
    /// [27:26] gruppo, [29:28] riga del punteggio
    pub const MAP: [u32; 833] = [
        0x034C0022, 0x034C0223, 0x034C0424, 0x034C0625, 0x034C0826, 0x034C0A27, 0x034C0C28, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x048C2029, 0x048C2029,
        0x048C222A, 0x048C222A, 0x048C242B, 0x048C242B, 0x048C262C, 0x048C262C, 0x048C282D, 0x048C282D,
        0x048C2A2E, 0x048C2A2E, 0x048C2C2F, 0x048C2C2F, 0x014D0030, 0x014D0231, 0x014D0432, 0x014D0633,
        0x014D0834, 0x014D0A35, 0x014D0C36, 0x014E8037, 0x014E8238, 0x014E8439, 0x014E863A, 0x014E883B,
        0x014E8A3C, 0x014E8C3D, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x1049403E, 0x1049423F, 0x10494440, 0x10494641, 0x10494842,
        0x10494A43, 0x10494C44, 0x10494E45, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x2544C046,
        0x2544C247, 0x2544C448, 0x2544C649, 0x2544C84A, 0x2544CA4B, 0x2544CC4C, 0x2544CE45, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x3849404D, 0x3849424E, 0x3849444F,
        0x3849464F, 0x38494850, 0x38494A4F, 0x38494C51, 0x38494E45, 0x004E8052, 0x004E8253, 0x004E8454,
        0x004E8655, 0x004E8856, 0x004E8A57, 0x004E8C58, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x014C0059, 0x014C025A, 0x014C045B,
        0x014C065C, 0x014C085D, 0x014C0A5E, 0x014C0C5F, 0x03508060, 0x03508261, 0x03508462, 0x03508663,
        0x03508864, 0x03508A65, 0x03508C66, 0x01508067, 0x01508268, 0x01508469, 0x0150866A, 0x0150886B,
        0x01508A6C, 0x01508C6D, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x0146806E, 0x0146826F,
        0x01468470, 0x01468671, 0x01468872, 0x01468A73, 0x01468C74, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x004D8075, 0x004D8276, 0x004D8477, 0x004D8678, 0x004D8879, 0x004D8A7A, 0x004D8C7B,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x014F807C, 0x014F827D, 0x014F847E, 0x014F867F,
        0x014F8880, 0x014F8A81, 0x014F8C82, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00498083,
        0x00498284, 0x00498485, 0x00498686, 0x00498887, 0x00498A88, 0x00498C89, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x004E808A, 0x004E828B, 0x004E848C, 0x004E868D, 0x004E888E, 0x004E8A8F,
        0x004E8C90, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x004E0091, 0x004E0292, 0x004E0493,
        0x004E0694, 0x004E0895, 0x004E0A96, 0x004E0C97, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x014C8098, 0x014C8299, 0x014C849A, 0x014C869B, 0x014C889C, 0x014C8A9D, 0x014C8C9E, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x004B009F, 0x004B02A0, 0x004B04A1, 0x004B06A2, 0x004B08A3,
        0x004B0AA4, 0x004B0CA5, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x004B80A6, 0x004B82A7,
        0x004B84A8, 0x004B86A9, 0x004B88AA, 0x004B8AAB, 0x004B8CAC, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x004C00AD, 0x004C02AE, 0x004C04AF, 0x004C06B0, 0x004C08B1, 0x004C0AB2, 0x004C0CB3,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x014C80B4, 0x014C82B5, 0x014C84B6, 0x014C86B7,
        0x014C88B8, 0x014C8AB9, 0x014C8CBA, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x004880BB,
        0x004882BC, 0x004884BD, 0x004886BE, 0x004888BF, 0x00488AC0, 0x00488CC1, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x004900C2, 0x004902C3, 0x004904C4, 0x004906C5, 0x004908C6, 0x00490AC7,
        0x00490CC8, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x004E00C9, 0x004E02CA, 0x004E04CB,
        0x004E06CC, 0x004E08CD, 0x004E0ACE, 0x004E0CCF, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x014B80D0, 0x014B82D1, 0x014B84D2, 0x014B86D3, 0x014B88D4, 0x014B8AD5, 0x014B8CD6, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x004500D7, 0x004502D8, 0x004504D9, 0x004506DA, 0x004508DB,
        0x00450ADC, 0x00450CDD, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x004700DE, 0x004702DF,
        0x004704E0, 0x004706E1, 0x004708E2, 0x00470AE3, 0x00470CE4, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x004700E5, 0x004702E6, 0x004704E7, 0x004706E8, 0x004708E9, 0x00470AEA, 0x00470CEB,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x004280EC, 0x004282ED, 0x004284EE, 0x004286EF,
        0x004288F0, 0x00428AF1, 0x00428CF2, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x004A80F3,
        0x004A82F4, 0x004A84F5, 0x004A86F6, 0x004A88F7, 0x004A8AF8, 0x004A8CF9, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x004780FA, 0x004782FB, 0x004784FC, 0x004786FD, 0x004788FE, 0x00478AFF,
        0x00478D00, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00468101, 0x00468302, 0x00468503,
        0x00468704, 0x00468905, 0x00468B06, 0x00468D07, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00498108, 0x00498309, 0x0049850A, 0x0049870B, 0x0049890C, 0x00498B0D, 0x00498D0E, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x014D010F, 0x014D0310, 0x014D0511, 0x014D0712, 0x014D0913,
        0x014D0B14, 0x014D0D15, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00478116, 0x00478317,
        0x00478518, 0x00478719, 0x0047891A, 0x00478B1B, 0x00478D1C, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x0049011D, 0x0049031E, 0x0049051F, 0x00490720, 0x00490921, 0x00490B22, 0x00490D23,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x01498124, 0x01498325, 0x01498526, 0x01498727, 0x01498928, 0x01498B29,
        0x01498D2A,
    ];
}

/// Ritratti dei personaggi (assets/characters/portraits, tools/gen_portraits.py): 4 bit per pixel,
/// il ruolo del colore + 1; i tipi nell'ordine di PaddleKind, poi OMEGA.
pub mod portraits {
    use crate::Img;
    use crate::assets::*;
    /// grandi: righe di BIG_ROW_WORDS parole una dopo l'altra (tabella delle righe); OMEGA svelato
    pub const BIG: [Img; 8] = [IMG_PT_BIG_ARCADE, IMG_PT_BIG_TITAN, IMG_PT_BIG_HAMMER, IMG_PT_BIG_TWIST, IMG_PT_BIG_BLASTER, IMG_PT_BIG_RUSH, IMG_PT_BIG_GUARDIAN, IMG_PT_BIG_OMEGA];
    pub const BIG_ROW_WORDS: i32 = 11;
    /// caselle della griglia; OMEGA in sagoma
    pub const SMALL: [Img; 8] = [IMG_PT_SMALL_ARCADE, IMG_PT_SMALL_TITAN, IMG_PT_SMALL_HAMMER, IMG_PT_SMALL_TWIST, IMG_PT_SMALL_BLASTER, IMG_PT_SMALL_RUSH, IMG_PT_SMALL_GUARDIAN, IMG_PT_SMALL_OMEGA];
    /// sfilata del finale: normale e sconfitto
    pub const MID: [[Img; 2]; 8] = [[IMG_PT_MID_ARCADE, IMG_PT_MID_ARCADE_DEFEATED], [IMG_PT_MID_TITAN, IMG_PT_MID_TITAN_DEFEATED], [IMG_PT_MID_HAMMER, IMG_PT_MID_HAMMER_DEFEATED], [IMG_PT_MID_TWIST, IMG_PT_MID_TWIST_DEFEATED], [IMG_PT_MID_BLASTER, IMG_PT_MID_BLASTER_DEFEATED], [IMG_PT_MID_RUSH, IMG_PT_MID_RUSH_DEFEATED], [IMG_PT_MID_GUARDIAN, IMG_PT_MID_GUARDIAN_DEFEATED], [IMG_PT_MID_OMEGA, IMG_PT_MID_OMEGA_DEFEATED]];
    pub const MID_LOCKED: Img = IMG_PT_MID_OMEGA_LOCKED;
    /// colori RGB dei ruoli 1-7 di ogni personaggio
    pub const PAL: [[u32; 7]; 8] = [[0x000000, 0xFFFFFF, 0xC3C3C3, 0x828282, 0x464646, 0xFFD21E, 0x8C7411], [0x000000, 0xFFFFFF, 0xC3C3C3, 0x828282, 0x464646, 0xE67828, 0x7F4216], [0x000000, 0xFFFFFF, 0xC3C3C3, 0x828282, 0x464646, 0xE62828, 0x7F1616], [0x000000, 0xFFFFFF, 0xC3C3C3, 0x828282, 0x464646, 0x9646C8, 0x53276E], [0x000000, 0xFFFFFF, 0xC3C3C3, 0x828282, 0x464646, 0x46BE46, 0x276927], [0x000000, 0xFFFFFF, 0xC3C3C3, 0x828282, 0x464646, 0x3CC8DC, 0x216E79], [0x000000, 0xFFFFFF, 0xC3C3C3, 0x828282, 0x464646, 0x5A96FF, 0x32538C], [0x000000, 0xFFFFFF, 0xC3C3C3, 0x828282, 0x464646, 0xE040FF, 0x7B238C]];
}

/// Illustrazioni isometriche delle astronavi (assets/ships/*.png, 160x90 a 4 bpp) per THE END.
pub mod ships {
    use crate::Img;
    use crate::assets::*;
    pub const ART: [Img; 7] = [IMG_SHIP_ARCADE, IMG_SHIP_TITAN, IMG_SHIP_HAMMER, IMG_SHIP_TWIST, IMG_SHIP_BLASTER, IMG_SHIP_RUSH, IMG_SHIP_GUARDIAN];
    pub const ROW_WORDS: i32 = 20;
    /// Tavolozza 1..=15 di ciascuna astronave (caricata in pal::SHIP durante THE END).
    pub const PAL: [[u32; 15]; 7] = [
        [0xEAECF0, 0x7E828E, 0xA8ACB6, 0x585C68, 0xCED2DA, 0x363A44, 0xFFFFFF, 0x523610, 0x825614, 0xFFD22A, 0xB68016, 0xFFEA76, 0xE2AA1C, 0xFFF8C4, 0x1C1E26],
        [0xEAECF0, 0xCED2DA, 0xA8ACB6, 0x7E828E, 0x585C68, 0xFFFFFF, 0xE67A28, 0x363A44, 0xBC5A1A, 0xFCA448, 0x883E12, 0x54260E, 0xFFD07C, 0xFFEEBA, 0x1C1E26],
        [0xEAECF0, 0xCED2DA, 0xA8ACB6, 0x585C68, 0xE6302C, 0x7E828E, 0x363A44, 0xFFFFFF, 0xBA2222, 0xFC6C4C, 0x84181A, 0xFFB27A, 0x4E1012, 0xFFE8BA, 0x1C1E26],
        [0xFFFFFF, 0xEAECF0, 0xCED2DA, 0xA8ACB6, 0x9C4ED4, 0x7E828E, 0x585C68, 0x7A36AC, 0x54247C, 0xC07EEE, 0xE0B4FC, 0x30144A, 0x363A44, 0x1C1E26, 0x000000],
        [0xFFFFFF, 0xCED2DA, 0xA8ACB6, 0x7E828E, 0xEAECF0, 0x585C68, 0x38A234, 0x52D244, 0x363A44, 0x226E24, 0x90F680, 0xCEFFC4, 0x123E18, 0x1C1E26, 0xEAFFE4],
        [0xEAECF0, 0xCED2DA, 0x3CC8DE, 0xFFFFFF, 0xBAF8FE, 0xA8ACB6, 0x76E8F4, 0x7E828E, 0x186A7E, 0x269AB2, 0x585C68, 0x0E3E4C, 0x363A44, 0x1C1E26, 0x000000],
        [0xEAECF0, 0xA8ACB6, 0xCED2DA, 0xFFFFFF, 0x585C68, 0x3A70D0, 0x8CBCFF, 0x363A44, 0x7E828E, 0x5A96FF, 0x244A96, 0x142A5C, 0xC0DEFF, 0x1C1E26, 0x000000],
    ];
}
/// Icone 9x9 dei bonus (codici dei bonus).
pub const IMG_ICON: [Img; 8] = [IMG_ICON_0, IMG_ICON_1, IMG_ICON_2, IMG_ICON_3, IMG_ICON_4, IMG_ICON_5, IMG_ICON_6, IMG_ICON_7];
/// Nomi disegnati degli avversari (PaddleKind).
pub const IMG_NAME: [Img; 7] = [IMG_NAME_ARCADE, IMG_NAME_TITAN, IMG_NAME_HAMMER, IMG_NAME_TWIST, IMG_NAME_BLASTER, IMG_NAME_RUSH, IMG_NAME_GUARDIAN];
