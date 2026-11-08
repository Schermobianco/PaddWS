//! Parametri di gioco.
//!
//! `Tuning` contiene i valori come nel file di configurazione: riferiti alla
//! risoluzione 800x480 e a un tick di 60 Hz, come nella versione Python.
//! `Params::new` li scala sulla dimensione del campo e li converte in Fx per
//! il tick della simulazione (`Tuning::tick_hz`, di solito `TICK_HZ`). È l'unico
//! punto che usa la virgola mobile: nel core FPGA e sul C64 questi valori
//! diventano costanti.

use crate::fixed::{self, Fx};
use crate::next::PaddleKind;

/// Numero massimo di livelli di restringimento dell'area boost.
pub const MAX_BOOST_LEVELS: usize = 32;

/// Frequenza della simulazione: input applicato entro ~4 ms. È quella di PC, web e MiSTer;
/// il C64 gioca a un tick per frame (`C64_TICK_HZ`).
pub const TICK_HZ: u32 = 240;
/// Frequenza della simulazione sul C64 PAL: un tick per frame.
pub const C64_TICK_HZ: u32 = 50;
/// Campo del C64: tutto lo schermo del VIC-II.
pub const C64_WIDTH: u32 = 320;
pub const C64_HEIGHT: u32 = 200;

pub const BASE_WIDTH: u32 = 800;
pub const BASE_HEIGHT: u32 = 480;

/// Livelli di difficoltà: 0 facile, 1 normale (default), 2 difficile, 3 esperto.
pub const DIFFICULTY_LEVELS: u8 = 4;

/// Per ogni livello: accelerazione della palla a ogni colpo e velocità massima
/// (px per tick a 60 Hz, a 800x480), per il singolo e per la partita in due.
/// In due il livello normale è il gioco originale.
const SPEEDS_1P: [(f64, f64); DIFFICULTY_LEVELS as usize] = [(1.05, 8.0), (1.10, 10.0), (1.15, 12.0), (1.25, 15.0)];
const SPEEDS_2P: [(f64, f64); DIFFICULTY_LEVELS as usize] = [(1.15, 6.0), (1.25, 8.0), (1.25, 10.0), (1.30, 12.0)];
/// Valori della modalità NEXT a 800x480 e 60 Hz, come il resto di `Tuning`. I default
/// sono quelli del core MiSTer: cambiandoli il gioco su PC non coincide più con l'FPGA.
#[derive(Clone, Debug, PartialEq)]
pub struct NextTuning {
    /// per livello di difficoltà: accelerazione della palla a ogni colpo e velocità massima
    /// (px per tick a 60 Hz). La palla cresce piano e resta più lenta che in Classic, così gli
    /// scambi durano abbastanza da raccogliere e usare i bonus.
    pub ball_speedup: [f64; DIFFICULTY_LEVELS as usize],
    pub ball_max_speed: [f64; DIFFICULTY_LEVELS as usize],
    /// lato della capsula (px)
    pub capsule_size: f64,
    /// velocità orizzontale e deriva verticale della capsula (px per tick a 60 Hz)
    pub capsule_speed: f64,
    pub capsule_drift: f64,
    /// fascia in alto riservata alla riserva dei bonus (px)
    pub hud_band: f64,
    /// secondi tra due capsule, più una parte casuale
    pub spawn_seconds: f64,
    pub spawn_jitter_seconds: f64,
    /// una capsula su `super_odds` contiene il SUPER
    pub super_odds: u32,
    /// una capsula su `bullet_odds` contiene il BULLET (0 = mai)
    pub bullet_odds: u32,
    /// BULLET (dura dallo scatto alla ribattuta o al punto): rampa di entrata (s), velocità del
    /// resto del gioco e velocità durante la rampa. Le velocità valgono 1 - 2^-k (0,5, 0,75,
    /// 0,875, ...) perché il core le applica con uno shift e una sottrazione; gli altri valori
    /// vanno al più vicino
    pub bullet_ramp_seconds: f64,
    pub bullet_speed: f64,
    pub bullet_ramp_speed: f64,
    /// pausa minima tra due attivazioni dello stesso giocatore (s)
    pub cooldown_seconds: f64,
    /// moltiplicatori della velocità orizzontale per un tiro
    pub smash_multiplier: f64,
    pub super_multiplier: f64,
    /// SLOW: velocità che resta alla palla fino alla fine del punto, e durata dell'alone (s)
    pub slow_multiplier: f64,
    pub slow_seconds: f64,
    /// accelerazione verticale della palla a effetto ((px/tick)/tick a 60 Hz)
    pub curve_accel: f64,
    /// sterzata della palla guidata (STEER) con su o giù premuti ((px/tick)/tick a 60 Hz)
    pub steer_accel: f64,
    /// fermo del gioco del SUPER con hit-stop (s)
    pub hitstop_seconds: f64,
    /// mosse speciali (`Next::super_moves`, spente di default): barra per giocatore da 0 a
    /// `super_meter_max`, che cresce di `super_gain_hit` a ogni colpo (`super_gain_dash` se il
    /// colpo è lo scatto che intercetta la palla) e di `super_gain_conceded` per chi subisce un
    /// punto; ogni mossa costa `super_cost`
    pub super_meter_max: u32,
    pub super_gain_hit: u32,
    pub super_gain_dash: u32,
    pub super_gain_conceded: u32,
    pub super_cost: u32,
    /// STRAIGHT SHOT: moltiplicatore della velocità orizzontale per il tiro, 1 + 2^-k (2, 1,5,
    /// 1,25, ...) perché il core lo applica con uno shift e una somma; gli altri valori vanno al
    /// più vicino
    pub super_straight_multiplier: f64,
    /// velocità orizzontale minima della palla al colpo di una mossa, in frazione della massima della
    /// difficoltà (`ball_max_speed`): sotto, la palla la raggiunge prima del boost della mossa. Così
    /// la mossa conta anche a inizio scambio, con la palla ancora lenta; lo scambio poi continua da lì
    pub super_min_speed_straight: f64,
    pub super_min_speed_rise: f64,
    /// tipi di racchetta
    pub paddles: PaddleTuning,
}

/// Valori dei tipi di racchetta di NEXT, come il resto di `NextTuning`: altezze e velocità sono
/// moltiplicatori di quelle della racchetta normale (`Tuning::pad_height`, `pad_max_speed`).
#[derive(Clone, Debug, PartialEq)]
pub struct PaddleTuning {
    /// ARCADE: pausa tra due attivazioni di bonus (s), al posto di `cooldown_seconds`
    pub arcade_cooldown_seconds: f64,
    /// ARCADE: secondi tra due capsule quando gioca (al posto di `spawn_seconds`, stessa parte
    /// casuale) e capsule su 3 che vanno a lui se l'avversario non è ARCADE
    pub arcade_spawn_seconds: f64,
    pub arcade_share: u32,
    /// ARCADE: altezza (più capsule, ma un po' più corta)
    pub arcade_height: f64,
    pub titan_height: f64,
    pub titan_speed: f64,
    /// HAMMER: moltiplicatore della velocità orizzontale per un tiro, se non c'è già un boost
    pub hammer_multiplier: f64,
    pub hammer_speed: f64,
    /// TWIST: parte della velocità della racchetta che passa alla palla al colpo
    pub twist_transfer: f64,
    pub blaster_height: f64,
    pub blaster_speed: f64,
    /// BLASTER: colpi del caricatore, pausa minima tra due colpi (s), ricarica del caricatore
    /// dal primo colpo (s), velocità del colpo (px per tick a 60 Hz) e metà della fascia coperta
    /// dai due colpi paralleli (px)
    pub blaster_shots: u32,
    pub blaster_gap_seconds: f64,
    pub blaster_reload_seconds: f64,
    pub blaster_shot_speed: f64,
    pub blaster_band: f64,
    /// BLASTER: ha lo scatto in avanti e spara con un comando a parte; senza scatto spara con
    /// il tasto dello scatto
    pub blaster_dash: bool,
    pub rush_height: f64,
    /// RUSH: lunghezza dello scatto in avanti rispetto a quella normale, e velocità della
    /// racchetta quando è avanzata
    pub rush_dash: f64,
    pub rush_forward_speed: f64,
    /// RUSH: moltiplicatore della velocità orizzontale per un tiro dalla posizione avanzata (anche
    /// lo scatto che intercetta la palla), se non c'è SMASH o SUPER
    pub rush_ball_multiplier: f64,
    pub guardian_height: f64,
    /// GUARDIAN: distanza del muro dal bordo del campo (px). Il muro, a settori uguali
    /// (`next::GUARDIAN_SECTORS`), va dalla banda delle riserve (`NextTuning::hud_band`) al fondo
    pub guardian_barrier_x: f64,
    /// velocità di una mano veloce sulla manopola (px per tick a 60 Hz): con l'encoder i tipi
    /// più lenti della racchetta normale seguono la manopola al massimo a questa velocità per il
    /// loro fattore di velocità (gli altri vanno subito alla manopola)
    pub encoder_max_speed: f64,
}

impl Default for PaddleTuning {
    fn default() -> Self {
        Self {
            arcade_cooldown_seconds: 1.5,
            arcade_spawn_seconds: 3.0,
            arcade_height: 0.8,
            arcade_share: 2,
            titan_height: 1.2,
            titan_speed: 0.8,
            hammer_multiplier: 1.25,
            hammer_speed: 0.75,
            twist_transfer: 0.5,
            blaster_height: 1.1,
            blaster_speed: 1.0,
            blaster_shots: 4,
            blaster_gap_seconds: 0.2,
            blaster_reload_seconds: 3.0,
            blaster_shot_speed: 14.0,
            blaster_band: 6.0,
            blaster_dash: false,
            rush_height: 0.85,
            rush_dash: 1.5,
            rush_forward_speed: 1.15,
            rush_ball_multiplier: 1.15,
            guardian_height: 0.8,
            guardian_barrier_x: 20.0,
            encoder_max_speed: 18.0,
        }
    }
}

impl Default for NextTuning {
    fn default() -> Self {
        Self {
            ball_speedup: [1.06, 1.10, 1.14, 1.18],
            ball_max_speed: [7.0, 10.0, 11.0, 13.0],
            capsule_size: 26.0,
            capsule_speed: 2.5,
            capsule_drift: 0.3,
            hud_band: 48.0,
            spawn_seconds: 4.0,
            spawn_jitter_seconds: 1.0,
            super_odds: 8,
            bullet_odds: 16,
            bullet_ramp_seconds: 0.25,
            bullet_speed: 0.5,
            bullet_ramp_speed: 0.75,
            cooldown_seconds: 2.0,
            smash_multiplier: 2.2,
            super_multiplier: 3.2,
            slow_multiplier: 0.65,
            slow_seconds: 1.0,
            curve_accel: 0.3,
            steer_accel: 0.3,
            hitstop_seconds: 1.0 / 6.0,
            // con 8/16/16 a colpo, scatto e punto subito (e x1,5) le mosse partivano 30-60 volte a
            // partita e STRAIGHT SHOT vinceva poco più di un tiro normale (simulazioni di paddws-trace
            // --super-stats): così sono 5-25 a partita e STRAIGHT SHOT (x2) vale circa uno SMASH
            super_meter_max: 64,
            super_gain_hit: 2,
            super_gain_dash: 4,
            super_gain_conceded: 8,
            super_cost: 32,
            super_straight_multiplier: 2.0,
            // MAX STRAIGHT SHOT almeno alla velocità massima dello scambio (0,5 x 2); RISING STRIKE
            // vale per la sorpresa più che per la velocità e ha una soglia più bassa
            super_min_speed_straight: 0.5,
            super_min_speed_rise: 0.375,
            paddles: PaddleTuning::default(),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Tuning {
    pub width: u32,
    pub height: u32,
    pub ball_radius: f64,
    pub ball_radius_boost: f64,
    pub ball_radius_boost_fwd: f64,
    /// livello di difficoltà (0..DIFFICULTY_LEVELS, oltre vale l'ultimo)
    pub difficulty: u8,
    pub pad_width: f64,
    pub pad_height: f64,
    pub pad_start_pos: f64,
    pub pad_forward_pos: f64,
    pub pad_max_speed: f64,
    pub pad_acceleration: f64,
    pub pad_fast_acceleration: f64,
    pub pad_deceleration: f64,
    pub boost_multiplier: f64,
    pub boost_area_ratio: f64,
    pub boost_forward_multiplier: f64,
    pub boost_decay: bool,
    pub boost_decay_rate: f64,
    pub boost_min_area_ratio: f64,
    /// secondi di attesa della palla al centro dopo un punto
    pub serve_delay: f64,
    /// frequenza della simulazione (tick al secondo)
    pub tick_hz: u32,
    pub next: NextTuning,
}

impl Tuning {
    /// Valori della versione C64: campo 320x200 e un tick per frame a 50 Hz.
    pub fn c64() -> Self {
        Self {
            width: C64_WIDTH,
            height: C64_HEIGHT,
            tick_hz: C64_TICK_HZ,
            ..Self::default()
        }
    }
}

impl Default for Tuning {
    fn default() -> Self {
        Self {
            width: BASE_WIDTH,
            height: BASE_HEIGHT,
            ball_radius: 5.0,
            ball_radius_boost: 8.0,
            ball_radius_boost_fwd: 6.0,
            difficulty: 1,
            pad_width: 10.0,
            pad_height: 80.0,
            pad_start_pos: 50.0,
            pad_forward_pos: 200.0,
            pad_max_speed: 15.0,
            pad_acceleration: 0.3,
            pad_fast_acceleration: 1.0,
            pad_deceleration: 2.0,
            boost_multiplier: 2.0,
            boost_area_ratio: 4.0,
            boost_forward_multiplier: 1.5,
            boost_decay: true,
            boost_decay_rate: 0.8,
            boost_min_area_ratio: 20.0,
            serve_delay: 0.5,
            tick_hz: TICK_HZ,
            next: NextTuning::default(),
        }
    }
}

/// Valori di una racchetta che dipendono dal tipo (NEXT), pronti per la simulazione.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PaddleParams {
    pub height: Fx,
    /// reciproco (Q8.24) di metà altezza
    pub inv_half_height: i32,
    pub max_speed: Fx,
    pub acceleration: Fx,
    pub fast_acceleration: Fx,
    /// posizione dello scatto in avanti (racchetta sinistra)
    pub fwd_pos: Fx,
    /// velocità massima e accelerazioni con la racchetta avanzata
    pub fwd_max_speed: Fx,
    pub fwd_acceleration: Fx,
    pub fwd_fast_acceleration: Fx,
    /// spostamento massimo per tick con l'encoder (0 = nessun limite)
    pub encoder_step: Fx,
}

/// Parametri pronti per la simulazione: tutti in Fx, velocità per tick a `tick_hz`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Params {
    /// frequenza della simulazione (tick al secondo)
    pub tick_hz: u32,
    pub width: Fx,
    pub height: Fx,
    /// media dei fattori di scala x/y rispetto a 800x480
    pub scale: Fx,

    pub ball_radius: Fx,
    pub ball_radius_boost: Fx,
    pub ball_radius_boost_fwd: Fx,
    /// velocità massima e accelerazione a ogni colpo, dal livello di difficoltà
    pub max_ball_speed_1p: Fx,
    pub max_ball_speed_2p: Fx,
    pub kspeed_1p: Fx,
    pub kspeed_2p: Fx,
    /// velocità iniziale unitaria della palla (1 px per tick a 60 Hz, scalato)
    pub serve_unit: Fx,

    pub pad_width: Fx,
    pub pad_height: Fx,
    pub pad_start_pos: Fx,
    pub pad_fwd_pos: Fx,
    pub pad_max_speed: Fx,
    pub pad_acceleration: Fx,
    pub pad_fast_acceleration: Fx,
    pub pad_deceleration: Fx,
    /// sotto questa velocità la racchetta si ferma
    pub pad_stop_speed: Fx,

    /// reciproci (Q8.24) di metà altezza della racchetta e del muro del singolo giocatore
    pub pad_inv_half_height: i32,
    pub wall_inv_half_height: i32,

    pub boost_mul: Fx,
    pub boost_fwd_mul: Fx,
    /// altezze dell'area boost (pixel interi) a ogni livello di restringimento,
    /// con i reciproci di metà altezza: la simulazione non divide mai
    pub boost_heights: [Fx; MAX_BOOST_LEVELS],
    pub boost_inv_half: [i32; MAX_BOOST_LEVELS],
    pub boost_levels: u8,

    pub serve_ticks: u32,

    /// modalità NEXT (vedi il modulo `next`)
    pub kspeed_next: Fx,
    pub max_ball_speed_next: Fx,
    /// metà del lato della capsula
    pub capsule_half: Fx,
    pub capsule_speed: Fx,
    pub capsule_drift: Fx,
    pub capsule_margin_top: Fx,
    pub spawn_ticks: u32,
    pub spawn_jitter: u32,
    pub super_odds: u32,
    /// estrazione del bonus di una capsula: 16 bit del generatore (`Rng::bits16`), sotto
    /// `super_cut` SUPER, sotto `bullet_cut` BULLET, altrimenti uno dei 3 bonus scelti (con
    /// un'altra estrazione). `super_cut = 65535 / super_odds + 1` dà lo stesso SUPER di
    /// `below(super_odds) == 0`; `bullet_cut = super_cut + 65536 / bullet_odds` (arrotondato)
    pub super_cut: u32,
    pub bullet_cut: u32,
    pub bullet_odds: u32,
    /// BULLET: scatta con la palla nella metà campo di chi l'ha attivato (x < `bullet_zone` a
    /// sinistra, x > `width - bullet_zone` a destra), in pixel interi. Nell'ultimo terzo il bullet
    /// time durava troppo poco per servire
    pub bullet_zone: Fx,
    /// BULLET: rampa di entrata in tick, shift del passo (`v - (v >> k)`) dopo e nella rampa
    pub bullet_ramp_ticks: u32,
    pub bullet_shift: u32,
    pub bullet_ramp_shift: u32,
    /// passo per tick di una mano veloce sulla manopola (`PaddleTuning::encoder_max_speed`): con
    /// l'encoder e il BULLET dell'avversario la racchetta lo segue rallentato
    pub encoder_hand_step: Fx,
    pub slow_ticks: u32,
    pub bonus_cooldown_ticks: u32,
    pub hitstop_ticks: u32,
    pub smash_mul: Fx,
    pub slow_mul: Fx,
    /// SLOW: inverso di `slow_mul`, per tornare alla velocità di prima al colpo di chi l'ha usato
    pub slow_back: Fx,
    pub super_mul: Fx,
    pub curve_accel: Fx,
    pub steer_accel: Fx,
    /// mosse speciali (vedi `NextTuning::super_meter_max`): valori della barra in unità intere
    /// (massimo 127, così una somma non esce dagli 8 bit)
    pub super_meter_max: u8,
    pub super_gain_hit: u8,
    pub super_gain_dash: u8,
    pub super_gain_conceded: u8,
    pub super_cost: u8,
    /// STRAIGHT SHOT: boost += boost >> shift (0 = doppio, 1 = una volta e mezza, ...)
    pub super_straight_shift: u32,
    /// velocità orizzontale minima al colpo di STRAIGHT SHOT e di RISING STRIKE (vedi
    /// `NextTuning::super_min_speed_straight`), già per la difficoltà
    pub super_min_vx_straight: Fx,
    pub super_min_vx_rise: Fx,

    /// tipi di racchetta di NEXT, nell'ordine di `PaddleKind`
    pub kinds: [PaddleParams; PaddleKind::COUNT],
    pub arcade_cooldown_ticks: u32,
    pub arcade_spawn_ticks: u32,
    pub arcade_share: u32,
    pub hammer_mul: Fx,
    /// RUSH: tiro dalla posizione avanzata
    pub rush_mul: Fx,
    pub twist_transfer: Fx,
    pub blaster_shots: u8,
    pub blaster_gap_ticks: u32,
    pub blaster_reload_ticks: u32,
    pub blaster_shot_speed: Fx,
    pub blaster_band: Fx,
    pub blaster_dash: bool,
    pub guardian_barrier_x: Fx,
    /// GUARDIAN: y dell'estremo alto del muro (sotto la banda delle riserve, la y cresce verso
    /// l'alto) e confini tra i settori dall'alto verso il basso, in pixel interi; il centro della
    /// palla sopra il primo confine è nel primo settore, anche nella banda
    pub guardian_top: Fx,
    pub guardian_bounds: [Fx; crate::next::GUARDIAN_SECTORS - 1],

    /// GHOST: la palla si vede `ghost_visible` tick ogni `ghost_period`
    pub ghost_period: u32,
    pub ghost_visible: u32,
    /// previsione del punto d'arrivo della palla della CPU e del TELEPORT: tick per passo e
    /// passi al massimo. A 240 Hz passi di 8 e 4 tick; a frequenze basse (il C64, un tick per
    /// frame) passi di un tick, così la previsione non cambia lungo un tratto rettilineo e si
    /// può calcolare una volta per tratto. L'orizzonte è lo stesso, 1024 tick a 240 Hz.
    pub predict_step: Fx,
    pub predict_max: u32,
    pub arrival_step: Fx,
    pub arrival_max: u32,
}

impl Params {
    pub fn new(t: &Tuning) -> Self {
        assert!(
            t.width > 0 && t.height > 0,
            "world size not resolved: {}x{}",
            t.width,
            t.height
        );
        let sx = t.width as f64 / BASE_WIDTH as f64;
        let sy = t.height as f64 / BASE_HEIGHT as f64;
        let s = (sx + sy) / 2.0;
        assert!(t.tick_hz >= 1, "tick_hz must be positive");
        // tick della simulazione per ogni tick di riferimento a 60 Hz
        let substeps = t.tick_hz as f64 / 60.0;
        // dimensioni arrotondate al pixel più vicino (a 320x240 la troncatura
        // renderebbe uguali palla normale e palla potenziata)
        let px = |v: f64| fixed::int((v + 0.5) as i32);
        // velocità: px per tick a 60 Hz -> px per tick della simulazione (in Fx, senza troncare)
        let speed = |v: f64| fixed::from_f64(v / substeps);
        // accelerazioni: (px/tick60)/tick60 -> (px/tick)/tick
        let accel = |v: f64| fixed::from_f64(v / (substeps * substeps));
        let pad_height = px(t.pad_height * sy);
        let (boost_heights, boost_inv_half, boost_levels) = boost_table(t, pad_height);
        let level = t.difficulty.min(DIFFICULTY_LEVELS - 1) as usize;
        let ((k1, max1), (k2, max2)) = (SPEEDS_1P[level], SPEEDS_2P[level]);
        let n = &t.next;
        let (kn, maxn) = (n.ball_speedup[level], n.ball_max_speed[level]);
        let ticks = |seconds: f64| (seconds * t.tick_hz as f64 + 0.5) as u32;
        let guardian_top = t.height as i32 - (n.hud_band * sy + 0.5) as i32;
        let horizon = (1024 * t.tick_hz + TICK_HZ / 2) / TICK_HZ;
        let (predict_step, arrival_step) = if t.tick_hz >= TICK_HZ {
            (8 * t.tick_hz / TICK_HZ, 4 * t.tick_hz / TICK_HZ)
        } else {
            (1, 1)
        };
        let k = &n.paddles;
        // il k di 1 - 2^-k più vicino, da 1 (metà) a 8 (no_std: niente log2)
        let speed_shift = |v: f64| {
            (1..=8u32)
                .min_by(|&a, &b| {
                    let off = |k: u32| (1.0 - 1.0 / (1u32 << k) as f64 - v).abs();
                    off(a).total_cmp(&off(b))
                })
                .unwrap_or(1)
        };
        let kind = |kind: PaddleKind| {
            let (height, pace, dash) = match kind {
                PaddleKind::Titan => (k.titan_height, k.titan_speed, 1.0),
                PaddleKind::Hammer => (1.0, k.hammer_speed, 1.0),
                PaddleKind::Blaster => (k.blaster_height, k.blaster_speed, 1.0),
                PaddleKind::Rush => (k.rush_height, 1.0, k.rush_dash),
                PaddleKind::Guardian => (k.guardian_height, 1.0, 1.0),
                PaddleKind::Arcade => (k.arcade_height, 1.0, 1.0),
                PaddleKind::Twist => (1.0, 1.0, 1.0),
            };
            let h = px(t.pad_height * height * sy);
            let fwd_pace = if kind == PaddleKind::Rush {
                k.rush_forward_speed
            } else {
                1.0
            };
            PaddleParams {
                height: h,
                inv_half_height: fixed::recip(h / 2),
                max_speed: speed(t.pad_max_speed * pace * s),
                acceleration: accel(t.pad_acceleration * pace * s),
                fast_acceleration: accel(t.pad_fast_acceleration * pace * s),
                fwd_pos: px((t.pad_start_pos + (t.pad_forward_pos - t.pad_start_pos) * dash) * sx),
                fwd_max_speed: speed(t.pad_max_speed * pace * fwd_pace * s),
                fwd_acceleration: accel(t.pad_acceleration * pace * fwd_pace * s),
                fwd_fast_acceleration: accel(t.pad_fast_acceleration * pace * fwd_pace * s),
                encoder_step: if pace < 1.0 {
                    speed(k.encoder_max_speed * pace * s)
                } else {
                    0
                },
            }
        };
        Self {
            tick_hz: t.tick_hz,
            width: fixed::int(t.width as i32),
            height: fixed::int(t.height as i32),
            scale: fixed::from_f64(s),
            ball_radius: px(t.ball_radius * s),
            ball_radius_boost: px(t.ball_radius_boost * s),
            ball_radius_boost_fwd: px(t.ball_radius_boost_fwd * s),
            max_ball_speed_1p: speed(max1 * s),
            max_ball_speed_2p: speed(max2 * s),
            kspeed_1p: fixed::from_f64(k1),
            kspeed_2p: fixed::from_f64(k2),
            serve_unit: speed(s),
            pad_width: px(t.pad_width * sx),
            pad_height,
            pad_start_pos: px(t.pad_start_pos * sx),
            pad_fwd_pos: px(t.pad_forward_pos * sx),
            pad_max_speed: speed(t.pad_max_speed * s),
            pad_acceleration: accel(t.pad_acceleration * s),
            pad_fast_acceleration: accel(t.pad_fast_acceleration * s),
            pad_deceleration: accel(t.pad_deceleration * s),
            pad_stop_speed: speed(0.1),
            pad_inv_half_height: fixed::recip(pad_height / 2),
            wall_inv_half_height: fixed::recip(fixed::int(t.height as i32) / 2),
            boost_mul: fixed::from_f64(t.boost_multiplier),
            boost_fwd_mul: fixed::from_f64(t.boost_forward_multiplier),
            boost_heights,
            boost_inv_half,
            boost_levels,
            serve_ticks: ticks(t.serve_delay),
            kspeed_next: fixed::from_f64(kn),
            max_ball_speed_next: speed(maxn * s),
            capsule_half: px(n.capsule_size * s / 2.0),
            capsule_speed: speed(n.capsule_speed * s),
            capsule_drift: speed(n.capsule_drift * s),
            capsule_margin_top: px(n.hud_band * sy),
            spawn_ticks: ticks(n.spawn_seconds).max(1),
            spawn_jitter: ticks(n.spawn_jitter_seconds),
            super_odds: n.super_odds.max(1),
            super_cut: 65535 / n.super_odds.max(1) + 1,
            bullet_cut: (65535 / n.super_odds.max(1) + 1
                + (65536 + n.bullet_odds / 2).checked_div(n.bullet_odds).unwrap_or(0))
            .min(65536),
            bullet_odds: n.bullet_odds,
            bullet_zone: fixed::int(t.width as i32 / 2),
            bullet_ramp_ticks: ticks(n.bullet_ramp_seconds),
            bullet_shift: speed_shift(n.bullet_speed),
            bullet_ramp_shift: speed_shift(n.bullet_ramp_speed),
            encoder_hand_step: speed(k.encoder_max_speed * s),
            slow_ticks: ticks(n.slow_seconds),
            bonus_cooldown_ticks: ticks(n.cooldown_seconds),
            hitstop_ticks: ticks(n.hitstop_seconds),
            smash_mul: fixed::from_f64(n.smash_multiplier),
            slow_mul: fixed::from_f64(n.slow_multiplier),
            slow_back: fixed::from_f64(1.0 / n.slow_multiplier.max(0.01)),
            super_mul: fixed::from_f64(n.super_multiplier),
            curve_accel: accel(n.curve_accel * s),
            steer_accel: accel(n.steer_accel * s),
            super_meter_max: n.super_meter_max.clamp(1, 127) as u8,
            super_gain_hit: n.super_gain_hit.min(127) as u8,
            super_gain_dash: n.super_gain_dash.min(127) as u8,
            super_gain_conceded: n.super_gain_conceded.min(127) as u8,
            super_cost: n.super_cost.clamp(1, 127) as u8,
            // il k di 1 + 2^-k più vicino (no_std: niente log2)
            super_straight_shift: (0..=8u32)
                .min_by(|&a, &b| {
                    let off = |k: u32| (1.0 + 1.0 / (1u32 << k) as f64 - n.super_straight_multiplier).abs();
                    off(a).total_cmp(&off(b))
                })
                .unwrap_or(0),
            // in virgola fissa dalla velocità massima: nel firmware del MiSTer, che calcola i
            // parametri di ogni difficoltà, la virgola mobile emulata costerebbe centinaia di byte
            super_min_vx_straight: fixed::mul(speed(maxn * s), fixed::from_f64(n.super_min_speed_straight)),
            super_min_vx_rise: fixed::mul(speed(maxn * s), fixed::from_f64(n.super_min_speed_rise)),
            kinds: PaddleKind::ALL.map(kind),
            arcade_cooldown_ticks: ticks(k.arcade_cooldown_seconds),
            arcade_spawn_ticks: ticks(k.arcade_spawn_seconds).max(1),
            arcade_share: k.arcade_share.min(3),
            hammer_mul: fixed::from_f64(k.hammer_multiplier),
            rush_mul: fixed::from_f64(k.rush_ball_multiplier),
            twist_transfer: fixed::from_f64(k.twist_transfer),
            blaster_shots: k.blaster_shots.clamp(1, crate::next::MAX_SHOTS as u32) as u8,
            blaster_gap_ticks: ticks(k.blaster_gap_seconds),
            blaster_reload_ticks: ticks(k.blaster_reload_seconds).max(1),
            blaster_shot_speed: speed(k.blaster_shot_speed * s),
            blaster_band: px(k.blaster_band * sy),
            blaster_dash: k.blaster_dash,
            guardian_barrier_x: px(k.guardian_barrier_x * sx),
            guardian_top: fixed::int(guardian_top),
            guardian_bounds: core::array::from_fn(|i| {
                fixed::int(guardian_top - guardian_top * (i as i32 + 1) / crate::next::GUARDIAN_SECTORS as i32)
            }),
            ghost_period: ticks(0.4).max(1),
            ghost_visible: ticks(0.1),
            predict_step: predict_step as Fx,
            predict_max: horizon / predict_step,
            arrival_step: arrival_step as Fx,
            arrival_max: horizon / arrival_step,
        }
    }
}

/// Altezze dell'area boost per ogni livello: il rapporto altezza/area parte da
/// `area_ratio` e a ogni boost si divide per `decay_rate`, fino a `min_area_ratio`.
fn boost_table(t: &Tuning, pad_height: Fx) -> ([Fx; MAX_BOOST_LEVELS], [i32; MAX_BOOST_LEVELS], u8) {
    let mut heights = [0; MAX_BOOST_LEVELS];
    let mut inv_half = [0; MAX_BOOST_LEVELS];
    let mut ratio = t.boost_area_ratio;
    let mut levels = 0;
    while levels < MAX_BOOST_LEVELS {
        let h = fixed::int((fixed::floor(pad_height) as f64 / ratio) as i32);
        heights[levels] = h;
        inv_half[levels] = if h > 0 { fixed::recip(h / 2) } else { 0 };
        levels += 1;
        if !t.boost_decay || ratio >= t.boost_min_area_ratio {
            break;
        }
        ratio = (ratio / t.boost_decay_rate).min(t.boost_min_area_ratio);
    }
    (heights, inv_half, levels as u8)
}
