//! Presentazione dell'avversario della scalata (`Intro` e `Stage` di challenge_ui.rs): in cima la scala
//! dei sette livelli e il livello, poi lo schermo VS. I due ritratti scivolano dentro dai lati e si
//! posano con un colpo, VS si stampa grande e si posa, poi il campo con le due racchette a grandezza
//! reale, i nomi disegnati, i motti scritti una lettera per frame, le icone dei bonus di tutti e due e
//! FIRST TO. Ognuno dalla parte in cui gioca: il giocatore sul suo lato, l'avversario sull'altro. Anche
//! prima della sfida tra due giocatori, con P1 e P2 al posto della scala e CHALLENGE.
//!
//! OMEGA (livello 7, dopo l'allarme di omega.rs): prima la sua parte speciale, SECRET LEVEL, la
//! racchetta rossa che passa per le sette forme della scala con un lampo bianco a ogni cambio e torna
//! ARCADE, il sigillo che arriva bianco e lampeggia; poi lo schermo VS con il suo ritratto svelato, la
//! racchetta rossa e IT BECOMES THEM ALL.
//!
//! Disposizione sulle righe di caratteri del C64 come la scelta della racchetta (cast.rs); i suoni
//! (il colpo e il punto del VS) li fa pong_top.

use crate::assets::game::KIND_TAGS;
use crate::assets::{IMG_ICON, IMG_NAME, IMG_NAME_OMEGA, IMG_VS3, portraits};
use crate::cast::{Cast, HALF_X, OMEGA, PADDLE_X, PORTRAIT_W, PORTRAIT_X, TOP, line, name_x, paddle, plain_paddle};
use crate::challenge::Ch;
use crate::dl::{CLASS_A, Dl, Obj, code, text_w};
use crate::pal::{ACCENT, BLACK, DIM, GRAY, TL, TL_WHITE, WHITE};
use crate::regs::{Omega, Regs, field};

const W: i32 = 320;
const C: i32 = 8;
/// OMEGA: livello, motto, forme della scala (PaddleKind nell'ordine dei livelli), tempi in frame
const OMEGA_LEVEL: u32 = 7;
const OMEGA_TAG: &[u8] = b"IT BECOMES THEM ALL";
const K_ARCADE: u32 = 0;
const LADDER: [u32; 7] = [0, 3, 2, 1, 4, 5, 6];
const OMEGA_FORMS_AT: i32 = 6;
const OMEGA_FORM_FRAMES: i32 = 14;
const OMEGA_FLASH: i32 = 8;
const OMEGA_NAME_AT: i32 = 110;
/// OMEGA: da qui lo schermo VS (i tempi del VS contati da qui)
const OMEGA_VS_AT: i32 = 150;
/// OMEGA: centro della racchetta e fondo del sigillo (il motto, che qui non c'è, starebbe sotto)
const OMEGA_PAD_Y: i32 = 82;
const OMEGA_NAME_BOTTOM: i32 = 139;
/// scala e livello in cima
const LADDER_Y: i32 = 19;
const LEVEL_Y: i32 = 34;
/// Schermo VS, in frame dal suo inizio (Stage::vs): ritratti da VS_SLIDE_AT per VS_SLIDE frame, VS da
/// VS_STAMP_AT (4x, poi 3x, poi a 2x da VS_STAMP_SETTLE frame dopo), la rete da VS_COURT_AT (una
/// riga di trattini per frame), le racchette da VS_PADDLES_AT, nome e motto del giocatore da
/// VS_NAME_AT e VS_TAG_AT e dell'avversario VS_THEIRS frame dopo, le icone da VS_ICONS_AT una ogni
/// VS_ICON_GAP, FIRST TO da VS_FIRST_AT.
const VS_SLIDE_AT: i32 = 6;
const VS_SLIDE: i32 = 16;
const VS_LAND: i32 = VS_SLIDE_AT + VS_SLIDE;
const VS_STAMP_AT: i32 = 24;
const VS_STAMP_SETTLE: i32 = 7;
const VS_COURT_AT: i32 = 34;
const VS_PADDLES_AT: i32 = 42;
const VS_NAME_AT: i32 = 44;
const VS_THEIRS: i32 = 6;
const VS_TAG_AT: i32 = 54;
const VS_ICONS_AT: i32 = 74;
const VS_ICON_GAP: i32 = 6;
const VS_FIRST_AT: i32 = 100;
/// posizioni: ritratti righe 1-13 (scesi fino alla riga comune ART_BASE), VS alla 4, campo righe 6-14,
/// nomi a metà fra il fondo dei ritratti e il motto (vs_name_y), motti 19, icone 20-21, FIRST TO 22
const VS_PORTRAIT_Y: i32 = TOP + 8;
const VS_Y: i32 = TOP + 4 * 8;
const VS_COURT_Y: i32 = TOP + 6 * 8;
const VS_COURT_H: i32 = 9 * 8;
const VS_TAG_ROW: i32 = 19;
/// Centro verticale del nome disegnato: a metà fra il fondo comune dei ritratti (`ART_BASE`) e il
/// motto (le maiuscole cominciano 3 pixel e mezzo sopra il centro della riga 19), come `vs_name_y` di
/// challenge_ui.rs.
fn vs_name_y() -> i32 {
    TOP + (portraits::ART_BASE + 161) / 2
}
const VS_ICON_Y: i32 = TOP + 20 * 8 + 8;
const VS_FIRST_ROW: i32 = 22;
const CAP: i32 = 13;
/// riga del punteggio in fondo
const SCORE_Y: i32 = 221;

/// Scossa dello schermo al frame `f` (pixel): i cambi di forma di OMEGA, i ritratti e il VS che si posano.
#[inline(never)]
fn shake(omega: bool, f: i32, vs_at: i32) -> (i32, i32) {
    if omega && f < OMEGA_VS_AT {
        let since = f - OMEGA_FORMS_AT;
        return if (0..=7 * OMEGA_FORM_FRAMES).contains(&since) && since % OMEGA_FORM_FRAMES == 0 {
            (2, 0)
        } else {
            (0, 0)
        };
    }
    match f - vs_at {
        VS_LAND => (0, 3),
        v if v == VS_LAND + 1 => (0, -2),
        v if v == VS_STAMP_AT + VS_STAMP_SETTLE => (2, 0),
        v if v == VS_STAMP_AT + VS_STAMP_SETTLE + 1 => (-1, 0),
        _ => (0, 0),
    }
}

/// Oggetto spostato della scossa (anche il ritaglio: quello che esce dallo schermo resta nero).
#[inline(never)]
fn sh(o: Obj, s: (i32, i32)) -> Obj {
    let mut o = o;
    o.x += s.0;
    o.y += s.1;
    o.clip = [o.clip[0] + s.0, o.clip[1] + s.0, o.clip[2] + s.1, o.clip[3] + s.1];
    o
}

/// Scritta centrata in (cx, cy), con la scossa.
#[inline(never)]
fn text_c(d: &mut Dl, s: &[u8], cx: i32, cy: i32, c: u8, k: (i32, i32)) {
    let base = d.tiles(s, c);
    let o = d.text_obj(cx - text_w(s) / 2, cy - 4, base, s.len(), 0);
    d.push(&sh(o, k));
}

#[inline(never)]
fn rect(d: &mut Dl, x: i32, y: i32, w: i32, h: i32, c: u8, k: (i32, i32)) {
    d.rect(x + k.0, y + k.1, w, h, c);
}

/// Una presentazione al frame `f` dall'inizio.
struct Stage {
    ch: Ch,
    omega: bool,
    f: i32,
    k: (i32, i32),
}

#[inline(never)]
pub fn draw(r: &Regs, d: &mut Dl) {
    if Omega::new(r).warn {
        crate::omega::warning(r, d);
        return;
    }
    let ch = Ch::new(r);
    let omega = ch.level == OMEGA_LEVEL && !ch.duel;
    let f = r.frame.min(511);
    let vs_at = if omega { OMEGA_VS_AT } else { 0 };
    let st = Stage {
        k: shake(omega, f, vs_at),
        ch,
        omega,
        f,
    };
    d.class = CLASS_A;
    if omega && f < OMEGA_VS_AT {
        d.rect(0, 0, W, 240, BLACK);
    } else {
        // lo sfondo è la griglia in prospettiva (rtl/ui_render.v), con l'impulso del colore dello
        // sfidante: l'avversario del campione (OMEGA viola)
        let me = st.ch.side as usize;
        let challenger = if omega {
            OMEGA
        } else if st.ch.duel {
            field(r.w[28], if me == 0 { 3 } else { 0 }, 3) as usize
        } else {
            st.ch.kind as usize
        };
        d.grid = Some(portraits::PAL[challenger][5]);
    }
    header(d, &st);
    if omega && f < OMEGA_VS_AT {
        omega_part(d, &st);
    } else {
        vs(r, d, &st, f - vs_at);
    }
    hud(r, d, &st.ch);
}

/// In cima: la scala dei livelli (sette trattini: battuti bianchi, quello di adesso giallo che
/// lampeggia, gli altri spenti, uno ogni due frame) e il livello (FINAL LEVEL e SECRET LEVEL
/// lampeggiano); nella sfida P1 e P2 sopra i ritratti e CHALLENGE.
#[inline(never)]
fn header(d: &mut Dl, st: &Stage) {
    let (ch, f, k) = (&st.ch, st.f, st.k);
    if ch.duel {
        for (side, x) in PORTRAIT_X.iter().enumerate() {
            let s: &[u8] = if side == 0 { b"P1" } else { b"P2" };
            text_c(d, s, x + PORTRAIT_W / 2, line(0), WHITE, (0, 0));
        }
        if f >= 14 {
            text_c(d, b"CHALLENGE", W / 2, LEVEL_Y, ACCENT, k);
        }
        return;
    }
    for i in 0..7i32 {
        if f < 2 * i {
            break;
        }
        let c = if (i as u32) < ch.level && !ch.train {
            WHITE
        } else if i as u32 == ch.level && (f / 8) % 2 == 0 {
            ACCENT
        } else {
            DIM
        };
        rect(d, 80 + 24 * i, LADDER_Y, 16, 5, c, k);
    }
    let last = (ch.level == 6 || st.omega) && !ch.train;
    if f >= 14 && (!last || (f / 10) % 2 == 0) {
        let lv = [b'L', b'E', b'V', b'E', b'L', b' ', b'1' + ch.level as u8, b' ', b'O', b'F', b' ', b'7'];
        let t: &[u8] = if ch.train {
            b"TRAINING"
        } else if st.omega {
            b"SECRET LEVEL"
        } else if last {
            b"FINAL LEVEL"
        } else {
            &lv
        };
        text_c(d, t, W / 2, LEVEL_Y, ACCENT, k);
    }
}

/// Capsula di un bonus (lato 13, icona 9x9) centrata in (cx, cy): in negativo appena arriva.
#[inline(never)]
fn capsule(d: &mut Dl, bonus: u32, cx: i32, cy: i32, inverted: bool, k: (i32, i32)) {
    let (x, y) = (cx - CAP / 2, cy - CAP / 2);
    let icon = &IMG_ICON[bonus as usize];
    // le icone dei bonus sono bianche
    if inverted {
        rect(d, x, y, CAP, CAP, WHITE, k);
        let o = d.img_obj(x + 2, y + 2, icon, BLACK);
        d.push(&sh(o, k));
    } else {
        crate::cast::frame(d, x + k.0, y + k.1, CAP, CAP, 1, WHITE);
        let o = d.img_obj(x + 2, y + 2, icon, WHITE);
        d.push(&sh(o, k));
    }
}

/// Lo schermo VS al frame `f` dal suo inizio.
#[inline(never)]
fn vs(r: &Regs, d: &mut Dl, st: &Stage, f: i32) {
    let (ch, k) = (&st.ch, st.k);
    let w = r.w[47];
    let me = ch.side as usize;
    let mut kinds = [field(w, 9, 3); 2];
    let mut bonuses = [field(w, 0, 9); 2];
    if ch.duel {
        // la sfida: tutti e due con quello che hanno scelto
        kinds = [field(r.w[28], 0, 3), field(r.w[28], 3, 3)];
        bonuses = [field(w, 12, 9), field(w, 21, 9)];
    } else {
        kinds[1 - me] = ch.kind;
        bonuses[1 - me] = ch.loadout;
    }
    let theirs = |side: usize| if ch.duel { side == 1 } else { side != me };
    let mut cast = Cast::new();

    // i ritratti, da fuori dello schermo al loro posto, frenando (1 - (1 - t)^3)
    if f >= VS_SLIDE_AT {
        let n = (f - VS_SLIDE_AT).min(VS_SLIDE);
        let ease = 4096 - (VS_SLIDE - n).pow(3);
        for (side, &end) in PORTRAIT_X.iter().enumerate() {
            let start = if side == 0 { -PORTRAIT_W } else { W };
            let x = start + (end - start) * ease / 4096;
            let who = if st.omega && side != me { OMEGA } else { kinds[side] as usize };
            // tutti i personaggi finiscono sulla stessa riga: scendono fino a ART_BASE
            let drop = portraits::ART_BASE - portraits::ART_BOTTOM[who];
            cast.big(d, who, x + k.0, VS_PORTRAIT_Y + drop + k.1, side == 1);
        }
    }
    // VS: a 4x, poi 3x, poi si posa a 2x
    if f >= VS_STAMP_AT {
        let t = f - VS_STAMP_AT;
        let ink = text_w(b"VS");
        if (4..VS_STAMP_SETTLE).contains(&t) {
            let o = d.img_obj(W / 2 - 3 * ink / 2, VS_Y - 12, &IMG_VS3, ACCENT);
            d.push(&sh(o, k));
        } else {
            let s = if t < 4 { 2 } else { 1 };
            let base = d.tiles(b"VS", ACCENT);
            let o = d.text_obj(W / 2 - (ink << s) / 2, VS_Y - (4 << s), base, 2, s);
            d.push(&sh(o, k));
        }
    }
    // il campo: la rete si disegna dall'alto, una riga di trattini per frame, poi le due racchette
    if f >= VS_COURT_AT {
        let last = VS_COURT_Y + ((f - VS_COURT_AT + 1) * 8).min(VS_COURT_H);
        let mut y = VS_COURT_Y + 2;
        while y < last {
            rect(d, W / 2 - 1, y, 2, 5, WHITE, k);
            y += 8;
        }
    }
    if f >= VS_PADDLES_AT {
        let cy = VS_COURT_Y + VS_COURT_H / 2 + k.1;
        for side in 0..2usize {
            let cx = PADDLE_X[side] + k.0;
            if st.omega && side != me {
                plain_paddle(d, K_ARCADE, cx, cy, side == 0, true);
            } else {
                paddle(d, kinds[side], cx, cy, side == 0);
            }
        }
    }
    // nomi, motti e bonus: prima il giocatore, poi l'avversario VS_THEIRS frame dopo
    for side in 0..2usize {
        let them = theirs(side);
        let delay = if them { VS_THEIRS } else { 0 };
        let rival = them && !ch.duel;
        if f >= VS_NAME_AT + delay {
            let img = if rival && st.omega { &IMG_NAME_OMEGA } else { &IMG_NAME[kinds[side] as usize] };
            let (iw, ih) = (img.w as i32, img.h as i32);
            let cx = name_x(PORTRAIT_X[side] + PORTRAIT_W / 2, iw);
            let cy = vs_name_y();
            let o = d.img_obj(cx - iw / 2, cy - ih / 2, img, TL);
            d.push(&sh(o, k));
        }
        let t0 = VS_TAG_AT + delay;
        if f >= t0 {
            // la parte scritta, allineata dove starà il motto intero
            let tag = if rival && st.omega { OMEGA_TAG } else { KIND_TAGS[kinds[side] as usize] };
            let n = ((f - t0 + 1) as usize).min(tag.len());
            let x = HALF_X[side] - text_w(tag) / 2;
            let base = d.tiles(&tag[..n], if rival { GRAY } else { WHITE });
            let o = d.text_obj(x, line(VS_TAG_ROW) - 4, base, n, 0);
            d.push(&sh(o, k));
        }
        for i in 0..3i32 {
            let s = VS_ICONS_AT + delay / 2 + VS_ICON_GAP * i;
            if f >= s {
                let b = (bonuses[side] >> (3 * i)) & 7;
                capsule(d, b, HALF_X[side] + (i - 1) * 20, VS_ICON_Y, f < s + 4, k);
            }
        }
    }
    if f >= VS_FIRST_AT {
        // FIRST TO n: le cifre sono celle del font
        let pts = ch.points.min(99) as u8;
        let mut s = *b"FIRST TO 00";
        let n = if pts >= 10 {
            s[9] = b'0' + pts / 10;
            s[10] = b'0' + pts % 10;
            11
        } else {
            s[9] = b'0' + pts;
            10
        };
        text_c(d, &s[..n], W / 2, line(VS_FIRST_ROW), GRAY, k);
    }
}

/// OMEGA prima del VS: la racchetta rossa che da OMEGA_FORMS_AT passa per le sette forme della scala,
/// una ogni OMEGA_FORM_FRAMES con un lampo bianco a ogni cambio (metà per le forme, intero all'ultimo),
/// poi resta ARCADE; il sigillo bianco per qualche frame, poi un lampeggio, poi i suoi colori.
#[inline(never)]
fn omega_part(d: &mut Dl, st: &Stage) {
    let (f, k) = (st.f, st.k);
    let since = f - OMEGA_FORMS_AT;
    if since >= 0 {
        let step = since / OMEGA_FORM_FRAMES;
        let kind = if step < 7 { LADDER[step as usize] } else { K_ARCADE };
        let changed = since - step.min(7) * OMEGA_FORM_FRAMES;
        let flash = if step < 7 { OMEGA_FLASH / 2 } else { OMEGA_FLASH };
        plain_paddle(d, kind, W / 2 + k.0, OMEGA_PAD_Y + k.1, st.ch.side, changed >= flash);
    }
    if f >= OMEGA_NAME_AT {
        let t = f - OMEGA_NAME_AT;
        let white = t < 4 || (t < 20 && (t / 4) % 2 == 1);
        let img = &IMG_NAME_OMEGA;
        let o = d.img_obj(W / 2 - img.w as i32 / 2, OMEGA_NAME_BOTTOM - img.h as i32, img, if white { TL_WHITE } else { TL });
        d.push(&sh(o, k));
    }
}

/// In fondo SCORE e HI (non nell'allenamento né nella sfida), l'invito per lo sfidante, i duelli vinti.
#[inline(never)]
fn hud(r: &Regs, d: &mut Dl, ch: &Ch) {
    if ch.train {
        return;
    }
    let coin = !r.free_play && r.credits == 0;
    if !ch.duel {
        // "SCORE 0000000    HI 0000000", centrata: le cifre sono celle del font
        let x = (W - text_w(b"SCORE 0000000    HI 0000000")) / 2;
        d.text(x, SCORE_Y, b"SCORE", WHITE, 0);
        d.text(x + 17 * C, SCORE_Y, b"HI", WHITE, 0);
        let sd = dec7(ch.score);
        let hi = bcd7(r.w[9] & 0x0FFF_FFFF);
        let sc: [(u8, u8); 7] = core::array::from_fn(|j| (sd[j], WHITE));
        let hc: [(u8, u8); 7] = core::array::from_fn(|j| (hi[j], WHITE));
        d.cells(x + 6 * C, SCORE_Y, &sc);
        d.cells(x + 20 * C, SCORE_Y, &hc);
        // contro OMEGA non entrano sfidanti
        let join = ch.active && ch.level != OMEGA_LEVEL && r.blink < 30;
        let side = ch.side;
        if join && coin {
            d.text(if side { 80 - 43 } else { 240 - 43 }, 2, b"INSERT COIN", WHITE, 0);
        }
        if join && !coin {
            let join_x = if side { 80 - 55 } else { 240 - 55 };
            d.text(join_x + 3 * C, 2, b"PRESS START", WHITE, 0);
            d.cells(join_x, 2, &[(code(b'P'), WHITE), (if side { 1 } else { 2 }, WHITE)]);
        }
    }
    crate::challenge::wins(ch, d);
}

#[inline(never)]
fn dec7(v: u32) -> [u8; 7] {
    let mut d = [0u8; 7];
    let mut n = v;
    for k in (0..7).rev() {
        d[k] = (n % 10) as u8;
        n /= 10;
    }
    d
}

#[inline(never)]
fn bcd7(v: u32) -> [u8; 7] {
    core::array::from_fn(|i| ((v >> (4 * (6 - i))) & 15) as u8)
}
