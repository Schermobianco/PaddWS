//! Parole di stato della partita e codifica dei comandi di un tick.
//!
//! Le parole 0-76 sono quelle delle tracce di paddws-trace (`trace_state.hex`, formato qui
//! sotto): il firmware le scrive tutte, sempre, nei registri di `pong_logic_rv.v`, che le porta
//! sulle sue uscite verso `pong_top.v` e i renderer. Fuori da NEXT, o senza tipi di racchetta, le
//! parole che mancano nelle tracce hanno valori fissi (capsula al primo intervallo, riserve vuote,
//! nessun tipo).
//! Seguono alcune parole che non sono nelle tracce ma escono da `pong_logic_rv.v` (altezze,
//! `Ball::dx`, tick, modalità) e i comandi effettivi del tick, per i banchi di prova.
//!
//! # Formato delle tracce
//!
//! Ogni traccia ha `pong_params.vh`, `trace_config.vh` (`P_SEED`, `P_PLAYERS`, `P_EVO`,
//! `P_DIFFICULTY`, `P_CPU_SIDES`, `P_CONTROL`, `P_KINDS` con 3 bit per lato e 7 = nessuno,
//! `P_SUPERS`), `trace_input.hex` e `trace_state.hex` (lo stato dopo ogni tick).
//!
//! Comandi, 32 bit per tick: bit 0-7 il sinistro, 8-15 il destro (0 su, 1 giù, 2 rapido, 3 scatto
//! per un tick, 4 seleziona, 5 attiva il bonus, 6 posizione dall'encoder in questo tick, 7 sparo
//! del BLASTER); 16-23 e 24-31 la posizione dell'encoder (pixel dal bordo alto, `top_offset`). Con
//! `--supers` 40 bit: mossa del sinistro nei bit 32-33, del destro nei 34-35 (1 STRAIGHT, 2 RISING).
//!
//! Stato, parole da 32 bit:
//! - 0-5 palla x, y, vx, vy, boost, raggio; 6-9 e 10-13 racchette x, y, velocità, flag (bit 0-7
//!   direzione int8, 8 rapido, 16-23 livello dell'area boost); 14 punteggi (sinistro 0-15, destro
//!   16-31); 15 record del singolo; 16 attesa della battuta; 17 eventi; 18 RNG.
//! - Eventi: 0 muro, 1 colpo, 2 boost, 3 punto, 4 capsula, 5 bonus attivato, 6 SUPER, 7 salto del
//!   TELEPORT, 8 sparo del BLASTER, 9 rimbalzo sul muro del GUARDIAN (in `pong_top`, nei
//!   `sound_events`, anche 10 Straight e 11 Rise).
//! - NEXT (19-44): 19 tick alla prossima capsula; 20 bit 0-15 alone di SLOW, 16-31 rampa del
//!   BULLET; 21 accelerazione di CURVE; 22 effetti (0 fantasma, 1 suo lato, 2 SUPER in volo, 3-4
//!   animazione, 5 STEER, 6 lato di chi guida, 7 su, 8 giù, 9-10 tiro della mossa, 11 BULLET
//!   armato o in corso, 12 attivato dal destro, 13 BULLET scattato, 16-31 fermo); 23-24 giocatori
//!   (riserva 3×4 bit con 8 = vuoto, 12-13 selezionato, 14-15 animazione del SUPER, 16-19 armato
//!   con 8 = nessuno, 20-31 pausa); 25-44 capsule 0-3: x, y, vx, vy, flag (bit 3 presente, 0-2
//!   bonus; BULLET = 15).
//! - Tipi di racchetta (45-74): 45-46 bit 0-2 tipo, 3 muro del GUARDIAN in piedi, 4-7 colpi in
//!   volo, 8-10 caricatore, 16-31 ricarica; 47-48 bit 0-7 settori del muro (bit 0 in alto, 5
//!   settori), 16-31 pausa; 49-72 colpi del BLASTER, 4 per lato (prima il sinistro): x, y, vx;
//!   73-74 `Paddle::motion`.
//! - Mosse speciali (75-76): bit 0-7 barra, 8-9 STRAIGHT armato, 10-11 RISING armata (2 = MAX);
//!   solo nel sinistro 12-13 livello del tiro in volo, 14 impennata ancora da arrivare.
//! - Bonus: 0 TELEPORT, 1 SMASH, 2 SLOW, 3 CURVE, 4 GHOST, 5 SUPER, 6 STEER, 7 BULLET
//!   (`bonus_code`). Tipi: 0 ARCADE, 1 TITAN, 2 HAMMER, 3 TWIST, 4 BLASTER, 5 RUSH, 6 GUARDIAN.

use paddws_core::next::MAX_SHOTS;
use paddws_core::{Bonus, Input, Match, PlayerInput, Side, Special};

/// Parole delle tracce: 19 sempre, 26 di NEXT, 30 dei tipi di racchetta (4, più 3 per ogni colpo
/// del BLASTER, più il movimento delle due racchette), 2 delle mosse speciali.
pub const BASE_WORDS: usize = 19;
pub const NEXT_WORDS: usize = 26;
pub const KIND_WORDS: usize = 4 + 3 * 2 * MAX_SHOTS + 2;
pub const SUPER_WORDS: usize = 2;
/// Prima parola di ogni gruppo nella codifica completa (quella del firmware).
pub const NEXT_AT: usize = BASE_WORDS;
pub const KINDS_AT: usize = NEXT_AT + NEXT_WORDS;
pub const SUPERS_AT: usize = KINDS_AT + KIND_WORDS;
/// Parole al massimo in una traccia.
pub const TRACE_WORDS: usize = SUPERS_AT + SUPER_WORDS;

/// Parole in più, fuori dalle tracce.
pub const W_BOOST_H0: usize = TRACE_WORDS; // altezza dell'area boost (Paddle::boost_height)
pub const W_BOOST_H1: usize = TRACE_WORDS + 1;
pub const W_HEIGHT0: usize = TRACE_WORDS + 2; // altezza della racchetta (o del muro)
pub const W_HEIGHT1: usize = TRACE_WORDS + 3;
pub const W_BALL_DX: usize = TRACE_WORDS + 4; // Ball::dx
pub const W_TICK: usize = TRACE_WORDS + 5; // Match::tick, 32 bit bassi
/// bit 0 due giocatori, 1 EVO, 2 NEXT, 3 mosse speciali accese, 4 palla nascosta dal GHOST
/// (`Next::ball_hidden`: in HDL sarebbe un modulo a 32 bit del tick, troppo lento per il clock)
pub const W_MODE: usize = TRACE_WORDS + 6;
/// comandi effettivi del tick (CPU comprese): `encode_input` e `encode_specials`
pub const W_INPUT: usize = TRACE_WORDS + 7;
pub const W_SPECIALS: usize = TRACE_WORDS + 8;
/// Parole scritte dal firmware.
pub const WORDS: usize = TRACE_WORDS + 9;

/// Codice a 4 bit di un bonus nelle parole di stato: 0-7 come `Bonus` (7 = BULLET), 8 = posto
/// vuoto (bit 3 acceso). Prima del BULLET era a 3 bit con 7 = vuoto: con 8 bonus non basta più.
pub const BONUS_NONE: u32 = 8;

pub fn bonus_code(b: Option<Bonus>) -> u32 {
    b.map_or(BONUS_NONE, |b| b as u32)
}

/// Codice a 3 bit del tipo di racchetta, 7 = senza tipo.
pub const KIND_NONE: u32 = 7;

/// Gruppi di parole presenti nella traccia di questa partita.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Layout {
    pub next: bool,
    pub kinds: bool,
    pub supers: bool,
}

impl Layout {
    pub fn of(m: &Match) -> Self {
        let n = m.next.as_ref();
        Self {
            next: n.is_some(),
            kinds: n.is_some_and(|n| n.players.iter().any(|pl| pl.kind.is_some())),
            supers: n.is_some_and(|n| n.super_moves),
        }
    }

    /// Parole della traccia.
    pub const fn trace_len(self) -> usize {
        let mut n = BASE_WORDS;
        if self.next {
            n += NEXT_WORDS;
            if self.kinds {
                n += KIND_WORDS;
            }
            if self.supers {
                n += SUPER_WORDS;
            }
        }
        n
    }
}

/// Dove vanno le parole di stato: un array (tracce, banchi di prova) o i registri dell'HDL.
pub trait Sink {
    fn put(&mut self, i: usize, v: u32);

    #[inline(always)]
    fn put_all(&mut self, at: usize, v: &[u32]) {
        for (k, &x) in v.iter().enumerate() {
            self.put(at + k, x);
        }
    }
}

impl Sink for [u32; WORDS] {
    fn put(&mut self, i: usize, v: u32) {
        self[i] = v;
    }
}

/// Stato dopo un tick: scrive una volta ciascuna tutte le parole tranne i comandi (`W_INPUT`,
/// `W_SPECIALS`). Nel firmware ogni parola è una scrittura in un registro dell'HDL.
///
/// Novità del BULLET rispetto alla prima versione del formato:
///
/// - parola 20: bit 0-15 tick dell'alone di SLOW, bit 16-31 tick di rampa rimasti del BULLET
///   (`Next::bullet_timer`);
/// - parola 22 (effetti): bit 11 BULLET armato o in corso, bit 12 attivato dal giocatore destro,
///   bit 13 scattato (`Next::bullet_on`);
/// - parole 23-24 (giocatori): bit 0-3, 4-7 e 8-11 riserva (codici a 4 bit, `bonus_code`, 8 =
///   vuoto), 12-13 selezionato, 14-15 animazione del SUPER, 16-19 bonus armato (4 bit, 8 =
///   nessuno; mai SLOW né BULLET, che agiscono subito), 20-31 pausa tra le attivazioni (12 bit);
/// - capsule: flag come prima (bit 3 presente, 0-2 bonus): il BULLET è 15.
#[inline(always)]
pub fn encode_state<S: Sink>(m: &Match, events: u16, w: &mut S) {
    let b = &m.ball;
    w.put_all(
        0,
        &[
            b.x as u32,
            b.y as u32,
            b.vx as u32,
            b.vy as u32,
            b.boost as u32,
            b.radius as u32,
        ],
    );
    for (i, pad) in m.paddles.iter().enumerate() {
        let flags = (pad.direction as u8 as u32) | (pad.fast as u32) << 8 | (pad.boost_level as u32) << 16;
        w.put_all(6 + 4 * i, &[pad.x as u32, pad.y as u32, pad.speed as u32, flags]);
    }
    w.put(14, m.score[0] as u32 | (m.score[1] as u32) << 16);
    w.put(15, m.best as u32);
    w.put(16, m.serve_timer);
    w.put(17, events as u32);
    w.put(18, m.rng.state());

    // NEXT: timer, effetti, riserve e capsule (vedi il formato in testa al file). Fuori da NEXT valori fissi:
    // capsula al primo intervallo, riserve vuote, nessun tipo
    let none_player = 0x888 | BONUS_NONE << 16;
    match &m.next {
        None => {
            for i in NEXT_AT..KINDS_AT + KIND_WORDS - 2 {
                w.put(i, 0);
            }
            w.put_all(SUPERS_AT, &[0, 0]);
            w.put(NEXT_AT, m.params.spawn_ticks);
            w.put_all(NEXT_AT + 4, &[none_player, none_player]);
            w.put_all(KINDS_AT, &[KIND_NONE, KIND_NONE]);
        }
        Some(n) => {
            let flags = n.ghost.is_some() as u32
                | ((n.ghost == Some(Side::Right)) as u32) << 1
                | (n.super_flight.is_some() as u32) << 2
                | (n.super_flight.map_or(0, |a| a as u32)) << 3
                | (n.steer.is_some() as u32) << 5
                | ((n.steer == Some(Side::Right)) as u32) << 6
                | ((n.steer_dir > 0) as u32) << 7
                | ((n.steer_dir < 0) as u32) << 8
                | n.special_flight.map_or(0, |s| s as u32) << 9 // mosse speciali: 0 senza
                | (n.bullet.is_some() as u32) << 11
                | ((n.bullet == Some(Side::Right)) as u32) << 12
                | (n.bullet_on as u32) << 13
                | (n.freeze & 0xFFFF) << 16;
            w.put_all(
                NEXT_AT,
                &[
                    n.spawn_timer,
                    (n.slow_timer & 0xFFFF) | (n.bullet_timer & 0xFFFF) << 16,
                    n.curve as u32,
                    flags,
                ],
            );
            for (i, pl) in n.players.iter().enumerate() {
                let reserve =
                    bonus_code(pl.reserve[0]) | bonus_code(pl.reserve[1]) << 4 | bonus_code(pl.reserve[2]) << 8;
                w.put(
                    NEXT_AT + 4 + i,
                    reserve
                        | (pl.selected as u32) << 12
                        | (pl.super_anim as u32) << 14
                        | bonus_code(pl.armed) << 16
                        | pl.cooldown << 20,
                );
            }
            for (i, c) in n.capsules.iter().enumerate() {
                let at = NEXT_AT + 6 + 5 * i;
                match c {
                    Some(c) => w.put_all(
                        at,
                        &[c.x as u32, c.y as u32, c.vx as u32, c.vy as u32, 8 | c.bonus as u32],
                    ),
                    None => w.put_all(at, &[0; 5]),
                }
            }
            // tipi di racchetta
            for (i, pl) in n.players.iter().enumerate() {
                let flying: u32 = (0..MAX_SHOTS).map(|k| (pl.shots[k].is_some() as u32) << k).sum();
                w.put(
                    KINDS_AT + i,
                    pl.kind.map_or(KIND_NONE, |k| k as u32)
                        | ((pl.barrier != 0) as u32) << 3
                        | flying << 4
                        | (pl.ammo as u32 & 7) << 8
                        | (pl.reload & 0xFFFF) << 16,
                );
                w.put(KINDS_AT + 2 + i, pl.barrier as u32 | (pl.gap & 0xFFFF) << 16);
                for (k, shot) in pl.shots.iter().enumerate() {
                    let at = KINDS_AT + 4 + 3 * (MAX_SHOTS * i + k);
                    match shot {
                        Some(s) => w.put_all(at, &[s.x as u32, s.y as u32, s.vx as u32]),
                        None => w.put_all(at, &[0; 3]),
                    }
                }
            }
            // mosse speciali: barra nei bit 0-7, livello di STRAIGHT SHOT armato nei bit 8-9 e di
            // RISING STRIKE nei bit 10-11; nella parola del primo giocatore anche il livello del
            // tiro in volo (bit 12-13) e l'impennata di RISING STRIKE che deve ancora arrivare
            // (bit 14)
            for (i, pl) in n.players.iter().enumerate() {
                let flight = if i == 0 {
                    (n.special_level as u32 & 3) << 12 | (n.rise_break.is_some() as u32) << 14
                } else {
                    0
                };
                w.put(
                    SUPERS_AT + i,
                    pl.meter as u32 | (pl.straight as u32 & 3) << 8 | (pl.rise as u32 & 3) << 10 | flight,
                );
            }
        }
    }
    // Paddle::motion (serve a TWIST), in tutte le modalità
    w.put_all(KINDS_AT + KIND_WORDS - 2, &[m.paddles[0].motion as u32, m.paddles[1].motion as u32]);

    w.put_all(
        W_BOOST_H0,
        &[
            m.paddles[0].boost_height as u32,
            m.paddles[1].boost_height as u32,
            m.paddles[0].height as u32,
            m.paddles[1].height as u32,
            m.ball.dx as u32,
            m.tick as u32,
            (m.players == 2) as u32
                | (m.evo as u32) << 1
                | (m.next.is_some() as u32) << 2
                | (m.next.as_ref().is_some_and(|n| n.super_moves) as u32) << 3
                | (m.next.as_ref().is_some_and(|n| n.ball_hidden(&m.params, m.tick)) as u32) << 4,
        ],
    );
}

/// Parole della traccia (`trace_state.hex`): i gruppi presenti in questa partita, in ordine.
/// Restituisce quante sono. Controlla che i valori stiano nei campi del formato.
pub fn trace_words(m: &Match, events: u16, out: &mut [u32; TRACE_WORDS]) -> usize {
    if let Some(n) = &m.next {
        assert!(
            n.slow_timer <= 0xFFFF && n.bullet_timer <= 0xFFFF,
            "timer di SLOW o BULLET oltre i 16 bit"
        );
        for pl in &n.players {
            assert!(pl.cooldown <= 0xFFF, "pausa tra i bonus oltre i 12 bit della traccia");
        }
    }
    let mut w = [0; WORDS];
    encode_state(m, events, &mut w);
    pack(&w, Layout::of(m), out)
}

/// Dalle parole del firmware a quelle della traccia con i gruppi di `layout`; restituisce quante sono.
pub fn pack(w: &[u32; WORDS], layout: Layout, out: &mut [u32; TRACE_WORDS]) -> usize {
    let mut n = BASE_WORDS;
    out[..n].copy_from_slice(&w[..n]);
    let mut take = |from: usize, len: usize| {
        out[n..n + len].copy_from_slice(&w[from..from + len]);
        n += len;
    };
    if layout.next {
        take(NEXT_AT, NEXT_WORDS);
        // tipi di racchetta e mosse speciali solo nelle partite che li hanno, così le altre
        // tracce non cambiano
        if layout.kinds {
            take(KINDS_AT, KIND_WORDS);
        }
        if layout.supers {
            take(SUPERS_AT, SUPER_WORDS);
        }
    }
    n
}

// ------------------------------------------------------------------------------ comandi

/// Comandi di un giocatore -> 8 bit: 0 su, 1 giù, 2 rapido, 3 avanti, 4 seleziona e 5 attiva
/// (NEXT), 6 posizione da encoder in questo tick, 7 sparo del BLASTER (NEXT).
pub fn encode_player(p: &PlayerInput) -> u32 {
    (p.direction > 0) as u32
        | ((p.direction < 0) as u32) << 1
        | (p.fast as u32) << 2
        | (p.forward as u32) << 3
        | (p.select as u32) << 4
        | (p.activate as u32) << 5
        | (p.top_offset.is_some() as u32) << 6
        | (p.fire as u32) << 7
}

/// Posizione dell'encoder (pixel dal bordo alto) negli 8 bit della parola, se c'è.
pub fn offset_byte(p: &PlayerInput) -> Option<u32> {
    p.top_offset.map(|o| o as u32 & 0xFF)
}

/// Comandi del tick -> 32 bit: tasti nei bit 0-15 (byte basso = sinistro), posizioni
/// dell'encoder nei bit 16-23 (sinistro) e 24-31 (destro).
pub fn encode_input(input: &Input) -> u32 {
    let [l, r] = &input.players;
    let off = |p: &PlayerInput| offset_byte(p).unwrap_or(0);
    encode_player(l) | encode_player(r) << 8 | off(l) << 16 | off(r) << 24
}

/// Mosse speciali del tick: codice a 2 bit (`Special`, 0 = nessuna), bit 0-1 il sinistro.
pub fn encode_specials(input: &Input) -> u32 {
    let code = |p: &PlayerInput| p.special.map_or(0, |s| s as u32);
    code(&input.players[0]) | code(&input.players[1]) << 2
}

/// L'inverso di `encode_input` ed `encode_specials`, come li legge il firmware dai registri:
/// su vince su giù, il codice 3 della mossa non fa nulla.
pub fn decode_input(word: u32, specials: u32) -> Input {
    let mut input = Input::default();
    for (i, p) in input.players.iter_mut().enumerate() {
        let bits = word >> (8 * i);
        p.direction = if bits & 1 != 0 {
            1
        } else if bits & 2 != 0 {
            -1
        } else {
            0
        };
        p.fast = bits & 4 != 0;
        p.forward = bits & 8 != 0;
        p.select = bits & 16 != 0;
        p.activate = bits & 32 != 0;
        p.top_offset = (bits & 64 != 0).then_some((word >> (16 + 8 * i)) as i32 & 0xFF);
        p.fire = bits & 128 != 0;
        p.special = match (specials >> (2 * i)) & 3 {
            1 => Some(Special::Straight),
            2 => Some(Special::Rise),
            _ => None,
        };
    }
    input
}
