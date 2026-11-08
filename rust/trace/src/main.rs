//! Genera, dal core Rust, i file che servono al core MiSTer:
//!
//! - `pong_params.vh`: i parametri di gioco come `localparam` Verilog;
//! - `trace_config.vh`: seme, giocatori e modalità della partita registrata;
//! - `trace_input.hex`: una parola di input a 32 bit per tick;
//! - `trace_state.hex`: lo stato completo della partita dopo ogni tick.
//!
//! Le prove del firmware (`paddws-fw-sim`, `mister/sim/rv`) rigiocano input e stato e confrontano,
//! tick per tick, il proprio stato con quello atteso: devono coincidere bit per bit.
//! Il formato è descritto in `mister/README.md`, tranne le novità del BULLET, documentate qui in
//! `state_words` (riserva a 4 bit per posto, timer e lato del BULLET).

use std::fmt::Write as _;
use std::fs;
use std::path::PathBuf;

mod human;
use human::{Human, PROFILES};

use paddws_core::fixed;
use paddws_core::{
    CPU_LEVELS, Control, Cpu, DIFFICULTY_LEVELS, Fx, Input, Match, PaddleKind, Params, PlayerInput, Rng,
    Side, TICK_HZ, Tuning,
};
use paddws_mister_fw::words;

const USAGE: &str = "\
Uso: paddws-trace [--out DIR] [--width 320] [--height 240] [--seed N] [--ticks N] [--players 1|2] [--evo] [--next] [--cpu-play] [--difficulty 0-3]
                    [--tick-hz N]   (frequenza della simulazione, default 240)
                    [--c64]         (versione C64: campo 320x200, un tick per frame a 50 Hz; vale anche per le statistiche)
                    [--control spinner|joystick[,...]]   (spinner: il giocatore sinistro, o la CPU, usa l'encoder)
       paddws-trace --next-stats PARTITE [--seed N] [--difficulty 0-3] [--cpu]   (durata degli scambi, Classic e NEXT)
       paddws-trace --bonus-stats PARTITE [--seed N] [--difficulty 0-3]   (efficacia di ogni bonus, CPU contro CPU; BULLET: palle e punti salvati)
       paddws-trace --teleport-stats PROVE [--seed N] [--difficulty 0-3]   (palle prese con TELEPORT, per velocità)
       con --next: --paddles TIPO[,TIPO] (arcade, titan, ..., none) gioca con i tipi di racchetta
       paddws-trace --paddle-stats PARTITE [--seed N] [--difficulty 0-3]   (tipi di racchetta contro ARCADE, CPU contro CPU)
       con --paddle-stats: --set nome=valore (anche piu' volte) cambia un valore di PaddleTuning, es. --set titan_speed=0.75,
                             o delle mosse speciali (super_cost, super_gain_hit, ...: vale per tutte le statistiche e le tracce),
                             --kinds titan,hammer misura solo quei tipi
       con --cpu e --bonus-stats: --control spinner|joystick|keyboard[,spinner|joystick|keyboard] (sinistra,destra)
       con --next-stats, --bonus-stats e --paddle-stats: --human gioca con giocatori umani simulati invece della CPU,
                             --skill principiante|medio|esperto ne sceglie il profilo (--paddle-stats: tutti se manca)
       paddws-trace --human-stats PARTITE [--seed N] [--next] [--skill ...] [--control ...]   (umani simulati contro la CPU)
       paddws-trace --challenge-stats PARTITE [--seed N] [--difficulty 0-3] [--skill ...] [--control ...]   (umani simulati sui livelli di CHALLENGE)
       con --next e con --next-stats, --bonus-stats, --paddle-stats, --human-stats: --supers accende le mosse speciali
       paddws-trace --super-stats PARTITE [--seed N] [--difficulty 0-3] [--human [--skill ...]] [--control ...]
                             (mosse speciali spente e accese: usi, tiri vincenti, durata degli scambi)";

struct Args {
    out: PathBuf,
    width: u32,
    height: u32,
    seed: u32,
    ticks: u32,
    players: u8,
    evo: bool,
    difficulty: u8,
    /// traccia di una partita NEXT (sempre in due)
    next: bool,
    /// traccia giocata da due CPU (sempre in NEXT): le prove verificano anche i loro comandi
    cpu_play: bool,
    /// partite simulate per le statistiche di NEXT (0 = genera le tracce)
    next_stats: u32,
    /// statistiche giocate dalla CPU del gioco invece che dai giocatori simulati
    cpu: bool,
    /// partite simulate per bonus nelle statistiche dei bonus (0 = no)
    bonus_stats: u32,
    /// prove per velocità nelle statistiche di TELEPORT (0 = no)
    teleport_stats: u32,
    /// come comandano la racchetta le due CPU (sinistra, destra)
    control: [Control; 2],
    /// partite per casella nelle statistiche dei tipi di racchetta (0 = no)
    paddle_stats: u32,
    /// --difficulty passato: le statistiche dei tipi di racchetta usano solo quel livello
    difficulty_set: bool,
    /// valori dei tipi di racchetta cambiati da riga di comando (`--set nome=valore`)
    set: Vec<(String, f64)>,
    /// tipi da misurare nelle statistiche delle racchette (vuoto = tutti)
    kinds: Vec<String>,
    /// tipi di racchetta della traccia NEXT (sinistra, destra)
    paddles: [Option<PaddleKind>; 2],
    /// livello della CPU di destra nelle tracce (default: la difficoltà; 4-10 = CHALLENGE)
    cpu_level: Option<u8>,
    /// statistiche giocate da umani simulati invece che dalla CPU
    human: bool,
    /// profilo degli umani simulati (indice in `PROFILES`; `None` = medio, o tutti dove ha senso)
    skill: Option<usize>,
    /// partite per casella tra umani simulati e CPU (0 = no)
    human_stats: u32,
    /// partite per livello di CHALLENGE con gli umani simulati (0 = no)
    challenge_stats: u32,
    /// frequenza della simulazione (tick al secondo)
    tick_hz: u32,
    /// mosse speciali accese nelle partite NEXT (tracce e statistiche)
    supers: bool,
    /// partite per caso nelle statistiche delle mosse speciali (0 = no)
    super_stats: u32,
}

fn parse_args() -> Args {
    let mut a = Args {
        out: "trace".into(),
        width: 320,
        height: 240,
        seed: 1,
        ticks: 0,
        players: 2,
        evo: true,
        difficulty: 1,
        next: false,
        cpu_play: false,
        next_stats: 0,
        cpu: false,
        bonus_stats: 0,
        teleport_stats: 0,
        control: [Control::Joystick; 2],
        paddle_stats: 0,
        difficulty_set: false,
        set: Vec::new(),
        kinds: Vec::new(),
        paddles: [None; 2],
        cpu_level: None,
        human: false,
        skill: None,
        human_stats: 0,
        challenge_stats: 0,
        tick_hz: TICK_HZ,
        supers: false,
        super_stats: 0,
    };
    let mut it = std::env::args().skip(1);
    while let Some(arg) = it.next() {
        let mut value = || it.next().unwrap_or_else(|| fail(&format!("{arg} richiede un valore")));
        match arg.as_str() {
            "--out" => a.out = value().into(),
            "--width" => a.width = value().parse().unwrap_or_else(|_| fail("--width non valido")),
            "--height" => a.height = value().parse().unwrap_or_else(|_| fail("--height non valido")),
            "--seed" => a.seed = value().parse().unwrap_or_else(|_| fail("--seed non valido")),
            "--ticks" => a.ticks = value().parse().unwrap_or_else(|_| fail("--ticks non valido")),
            "--tick-hz" => {
                a.tick_hz = value().parse().unwrap_or_else(|_| fail("--tick-hz non valido"));
                if a.tick_hz == 0 {
                    fail("--tick-hz deve essere positivo");
                }
            }
            "--c64" => {
                let c = Tuning::c64();
                (a.width, a.height, a.tick_hz) = (c.width, c.height, c.tick_hz);
            }
            "--players" => a.players = value().parse().unwrap_or_else(|_| fail("--players non valido")),
            "--evo" => a.evo = true,
            "--classic" => a.evo = false,
            "--cpu" => a.cpu = true,
            "--next" => a.next = true,
            "--cpu-play" => a.cpu_play = true,
            "--control" => {
                let v = value();
                let parse = |name: &str| match name {
                    "spinner" => Control::Spinner,
                    "joystick" => Control::Joystick,
                    "keyboard" => Control::Keyboard,
                    _ => fail(&format!("--control: {name} non valido")),
                };
                let parts: Vec<&str> = v.split(',').collect();
                a.control = [parse(parts[0]), parse(parts.get(1).copied().unwrap_or(parts[0]))];
            }
            "--bonus-stats" => a.bonus_stats = value().parse().unwrap_or_else(|_| fail("--bonus-stats non valido")),
            "--teleport-stats" => {
                a.teleport_stats = value().parse().unwrap_or_else(|_| fail("--teleport-stats non valido"))
            }
            "--next-stats" => a.next_stats = value().parse().unwrap_or_else(|_| fail("--next-stats non valido")),
            "--difficulty" => {
                a.difficulty = value().parse().unwrap_or_else(|_| fail("--difficulty non valido"));
                a.difficulty_set = true;
            }
            "--kinds" => a.kinds = value().split(',').map(str::to_string).collect(),
            "--paddles" => {
                let v = value();
                let parse = |name: &str| match name {
                    "none" => None,
                    _ => Some(
                        PaddleKind::ALL
                            .into_iter()
                            .find(|k| k.name().eq_ignore_ascii_case(name))
                            .unwrap_or_else(|| fail(&format!("--paddles: {name} non valido"))),
                    ),
                };
                let parts: Vec<&str> = v.split(',').collect();
                a.paddles = [parse(parts[0]), parse(parts.get(1).copied().unwrap_or(parts[0]))];
            }
            "--set" => {
                let v = value();
                let (name, x) = v.split_once('=').unwrap_or_else(|| fail("--set vuole nome=valore"));
                let x = x
                    .parse()
                    .unwrap_or_else(|_| fail(&format!("--set {name}: valore non valido")));
                a.set.push((name.to_string(), x));
            }
            "--human" => a.human = true,
            "--cpu-level" => {
                let l: u8 = value().parse().unwrap_or_else(|_| fail("--cpu-level non valido"));
                if l >= CPU_LEVELS {
                    fail(&format!("--cpu-level: da 0 a {}", CPU_LEVELS - 1));
                }
                a.cpu_level = Some(l);
            }
            "--skill" => {
                let v = value();
                a.skill = Some(human::profile(&v).unwrap_or_else(|| fail(&format!("--skill: {v} non valido"))));
            }
            "--challenge-stats" => {
                a.challenge_stats = value().parse().unwrap_or_else(|_| fail("--challenge-stats non valido"))
            }
            "--human-stats" => a.human_stats = value().parse().unwrap_or_else(|_| fail("--human-stats non valido")),
            "--paddle-stats" => a.paddle_stats = value().parse().unwrap_or_else(|_| fail("--paddle-stats non valido")),
            "--supers" => a.supers = true,
            "--super-stats" => a.super_stats = value().parse().unwrap_or_else(|_| fail("--super-stats non valido")),
            "-h" | "--help" => {
                println!("{USAGE}");
                std::process::exit(0);
            }
            other => fail(&format!("Opzione sconosciuta: {other}\n{USAGE}")),
        }
    }
    if a.ticks == 0 {
        a.ticks = a.tick_hz * 60; // un minuto di gioco
    }
    a
}

/// Codice a 2 bit del comando di una CPU, come lo legge il firmware del core MiSTer.
fn control_code(c: Control) -> u32 {
    match c {
        Control::Joystick => 0,
        Control::Spinner => 1,
        Control::Keyboard => 2,
    }
}

fn fail(message: &str) -> ! {
    eprintln!("{message}");
    std::process::exit(2);
}

/// Posizione dell'encoder (pixel dal bordo alto) in 8 bit: nelle tracce resta tra 0 e 255.
fn check_offset(p: &PlayerInput) {
    if let Some(o) = p.top_offset {
        assert!((0..=255).contains(&o), "posizione dell'encoder fuori dagli 8 bit: {o}");
    }
}

/// Bonus usati nelle tracce NEXT: i due giocatori ne hanno di diversi, così le capsule li coprono tutti.
const TRACE_LOADOUTS: [[paddws_core::Bonus; 3]; 2] = {
    use paddws_core::Bonus::*;
    [[Smash, Teleport, Curve], [Slow, Ghost, Steer]]
};

/// Riga di `trace_input.hex`. Con le mosse speciali la parola diventa di 40 bit (10 cifre): sopra i
/// 32 bit di `encode_input` il codice a 2 bit della mossa (`Special`, 0 = nessuna) del sinistro nei
/// bit 32-33 e del destro nei bit 34-35, bit 36-39 a zero. Senza mosse resta di 8 cifre, come prima:
/// un `$readmemh` in un registro di 40 bit legge tutte e due le forme.
fn input_line(input: &Input, supers: bool) -> String {
    input.players.iter().for_each(check_offset);
    let word = words::encode_input(input);
    if supers {
        format!("{:010x}", word as u64 | (words::encode_specials(input) as u64) << 32)
    } else {
        format!("{word:08x}")
    }
}

/// Giocatori simulati: inseguono la palla con un errore casuale che cambia di
/// tanto in tanto, a volte esitano e ogni tanto scattano in avanti; usano un
/// generatore separato da quello della partita, così tutto resta riproducibile.
struct Script {
    rng: Rng,
    hold: [u32; 2],
    /// errore di mira in pixel e pausa (tick) per ogni giocatore
    aim: [i32; 2],
    idle: [u32; 2],
}

impl Script {
    fn new(seed: u32) -> Self {
        Self {
            rng: Rng::new(seed ^ 0x5EED_1234),
            hold: [0; 2],
            aim: [0; 2],
            idle: [0; 2],
        }
    }

    /// Con `encoder` il giocatore sinistro porta la racchetta con la manopola (posizione assoluta).
    fn next(&mut self, m: &Match, encoder: bool) -> Input {
        let mut input = Input::default();
        for i in 0..2 {
            if self.hold[i] == 0 {
                self.aim[i] = self.rng.range(-30, 31);
                self.idle[i] = if self.rng.range(0, 5) == 0 {
                    self.rng.range(10, 60) as u32
                } else {
                    0
                };
                self.hold[i] = self.rng.range(30, 200) as u32;
            }
            self.hold[i] -= 1;
            let cmd = &mut input.players[i];
            if self.idle[i] > 0 {
                self.idle[i] -= 1;
            } else {
                let target = fixed::floor(m.ball.y) + self.aim[i];
                let diff = target - fixed::floor(m.paddles[i].y);
                cmd.direction = if diff > 3 {
                    1
                } else if diff < -3 {
                    -1
                } else {
                    0
                };
                cmd.fast = diff.abs() > 60;
                if encoder && i == 0 {
                    // manopola: verso il bersaglio, al massimo 6 pixel per tick
                    let half = fixed::floor(m.paddles[0].height / 2);
                    let h = fixed::floor(m.params.height);
                    let knob = h - half - fixed::floor(m.paddles[0].y) - diff.clamp(-6, 6);
                    cmd.top_offset = Some(knob.clamp(0, h - 2 * half));
                    cmd.direction = 0;
                }
            }
            cmd.forward = self.rng.range(0, 400) == 0;
        }
        input
    }
}

/// Stato dopo un tick: parole a 32 bit nell'ordine documentato in mister/README.md. La codifica
/// è quella del firmware del core MiSTer (`paddws_mister_fw::words`), con le novità del BULLET.
fn state_words(m: &Match, events: u16) -> Vec<u32> {
    let mut w = [0; words::TRACE_WORDS];
    let n = words::trace_words(m, events, &mut w);
    w[..n].to_vec()
}

fn tuning(a: &Args, difficulty: u8) -> Tuning {
    let mut t = Tuning {
        width: a.width,
        height: a.height,
        difficulty,
        tick_hz: a.tick_hz,
        ..Tuning::default()
    };
    for (name, v) in &a.set {
        // mosse speciali (NextTuning): interi per la barra, px e secondi per RISING STRIKE
        let n = &mut t.next;
        let count = match name.as_str() {
            "super_meter_max" => Some(&mut n.super_meter_max),
            "super_gain_hit" => Some(&mut n.super_gain_hit),
            "super_gain_dash" => Some(&mut n.super_gain_dash),
            "super_gain_conceded" => Some(&mut n.super_gain_conceded),
            "super_cost" => Some(&mut n.super_cost),
            "super_straight_multiplier" => {
                n.super_straight_multiplier = *v;
                continue;
            }
            "super_min_speed_straight" => {
                n.super_min_speed_straight = *v;
                continue;
            }
            "super_min_speed_rise" => {
                n.super_min_speed_rise = *v;
                continue;
            }
            _ => None,
        };
        if let Some(c) = count {
            *c = *v as u32;
            continue;
        }
        let k = &mut t.next.paddles;
        let field = match name.as_str() {
            "arcade_cooldown_seconds" => &mut k.arcade_cooldown_seconds,
            "arcade_spawn_seconds" => &mut k.arcade_spawn_seconds,
            "arcade_height" => &mut k.arcade_height,
            "blaster_gap_seconds" => &mut k.blaster_gap_seconds,
            "titan_height" => &mut k.titan_height,
            "titan_speed" => &mut k.titan_speed,
            "hammer_multiplier" => &mut k.hammer_multiplier,
            "hammer_speed" => &mut k.hammer_speed,
            "twist_transfer" => &mut k.twist_transfer,
            "blaster_height" => &mut k.blaster_height,
            "blaster_speed" => &mut k.blaster_speed,
            "blaster_reload_seconds" => &mut k.blaster_reload_seconds,
            "blaster_shot_speed" => &mut k.blaster_shot_speed,
            "blaster_band" => &mut k.blaster_band,
            "rush_height" => &mut k.rush_height,
            "rush_dash" => &mut k.rush_dash,
            "rush_forward_speed" => &mut k.rush_forward_speed,
            "rush_ball_multiplier" => &mut k.rush_ball_multiplier,
            "guardian_height" => &mut k.guardian_height,
            "guardian_barrier_x" => &mut k.guardian_barrier_x,
            "encoder_max_speed" => &mut k.encoder_max_speed,
            "blaster_dash" => {
                k.blaster_dash = *v != 0.0;
                continue;
            }
            "arcade_share" => {
                k.arcade_share = *v as u32;
                continue;
            }
            "blaster_shots" => {
                k.blaster_shots = *v as u32;
                continue;
            }
            other => fail(&format!(
                "--set: {other} non e' un valore dei tipi di racchetta ne' delle mosse speciali"
            )),
        };
        *field = *v;
    }
    t
}

fn verilog_params(p: &Params, a: &Args) -> String {
    let mut out = String::new();
    let _ = writeln!(out, "// Generato da paddws-trace: non modificare a mano.");
    let _ = writeln!(
        out,
        "// Valori Q16.16 (reciproci Q8.24) per un campo {}x{}, tick a 240 Hz: quelli dei renderer e di pong_top",
        a.width, a.height
    );
    let _ = writeln!(out, "// (la logica: il core Rust sul processore di pong_logic_rv).");
    let mut param = |name: &str, v: i64| {
        let _ = writeln!(out, "localparam signed [31:0] {name} = {};", v);
    };
    param("P_WIDTH", p.width as i64);
    param("P_HEIGHT", p.height as i64);
    param("P_SCALE", p.scale as i64);
    param("P_PAD_WIDTH", p.pad_width as i64);
    param("P_PAD_HEIGHT", p.pad_height as i64);
    param("P_PAD_START_POS", p.pad_start_pos as i64);
    param("P_PAD_FWD_POS", p.pad_fwd_pos as i64);
    param("P_PAD_MAX_SPEED", p.pad_max_speed as i64);
    param("P_PAD_ACCELERATION", p.pad_acceleration as i64);
    param("P_PAD_FAST_ACCELERATION", p.pad_fast_acceleration as i64);
    param("P_PAD_INV_HALF_HEIGHT", p.pad_inv_half_height as i64);
    // NEXT
    param("P_CAPSULE_HALF", p.capsule_half as i64);
    param("P_CAPSULE_SPEED", p.capsule_speed as i64);
    param("P_CAPSULE_DRIFT", p.capsule_drift as i64);
    param("P_HITSTOP_TICKS", p.hitstop_ticks as i64);
    param("P_SUPER_ODDS", p.super_odds as i64);
    // BULLET: rampa d'entrata in tick
    param("P_BULLET_RAMP_TICKS", p.bullet_ramp_ticks as i64);
    // mosse speciali (opzione della partita, P_SUPERS in trace_config.vh): barra in unità intere
    param("P_SUPER_METER_MAX", p.super_meter_max as i64);
    param("P_SUPER_COST", p.super_cost as i64);
    // BLASTER: colpi nel caricatore (munizioni nella presentazione di CHALLENGE)
    param("P_BLASTER_SHOTS", p.blaster_shots as i64);
    if p.blaster_dash {
        fail("il core MiSTer ha solo il BLASTER senza scatto (spara con il tasto dello scatto)");
    }
    param("P_GUARDIAN_BARRIER_X", p.guardian_barrier_x as i64);
    // muro del GUARDIAN: inizio e confini tra i settori (pixel interi), per il disegno
    param("P_GUARDIAN_TOP", p.guardian_top as i64);
    for (i, b) in p.guardian_bounds.iter().enumerate() {
        param(&format!("P_GUARDIAN_BOUND{}", i + 1), *b as i64);
    }
    // disegno dei tipi (pixel interi, codice 0-6 come `PaddleKind`, 7 = senza tipo): altezza e
    // salto del TELEPORT a ogni pixel della palla nel passo di 32 pixel (altezza * k / 32)
    let kind_px = |i: usize| fixed::floor(p.kinds.get(i).map_or(p.pad_height, |k| k.height));
    let _ = writeln!(out, "function [9:0] kind_px_h(input [2:0] kind);");
    let _ = writeln!(out, "    case (kind)");
    for i in 0..paddws_core::PaddleKind::COUNT {
        let _ = writeln!(out, "        3'd{i}: kind_px_h = {};", kind_px(i));
    }
    let _ = writeln!(out, "        default: kind_px_h = {};", kind_px(7));
    let _ = writeln!(out, "    endcase");
    let _ = writeln!(out, "endfunction");
    let _ = writeln!(
        out,
        "function signed [11:0] kind_warp_shift(input [2:0] kind, input [5:0] k);"
    );
    let _ = writeln!(out, "    case ({{kind, k}})");
    for i in 0..8 {
        for k in 0..=32 {
            let _ = writeln!(
                out,
                "        {{3'd{i}, 6'd{k}}}: kind_warp_shift = {};",
                kind_px(i) * k / 32
            );
        }
    }
    let _ = writeln!(out, "        default: kind_warp_shift = 0;");
    let _ = writeln!(out, "    endcase");
    let _ = writeln!(out, "endfunction");
    out.push_str(&challenge_params());
    out
}

/// CHALLENGE (core/src/challenge.rs): livelli, punti arcade e classifica iniziale.
fn challenge_params() -> String {
    use paddws_core::challenge::{
        BOOST_POINTS, HIT_POINTS, LEVELS, MAX_MULTIPLIER, PERFECT_POINTS, POINT_POINTS, RALLY_STEP, RUNGS,
        SUPER_POINTS, Score, TABLE_SIZE, Table, WIN_POINTS,
    };
    let mut out = String::new();
    let _ = writeln!(out, "localparam integer CH_LEVELS = {LEVELS};");
    let _ = writeln!(out, "localparam integer CH_HIT = {HIT_POINTS};");
    let _ = writeln!(out, "localparam integer CH_BOOST = {BOOST_POINTS};");
    let _ = writeln!(out, "localparam integer CH_SUPER = {SUPER_POINTS};");
    let _ = writeln!(out, "localparam integer CH_POINT = {POINT_POINTS};");
    let _ = writeln!(out, "localparam integer CH_WIN = {WIN_POINTS};");
    let _ = writeln!(out, "localparam integer CH_PERFECT = {PERFECT_POINTS};");
    let _ = writeln!(out, "localparam integer CH_RALLY_STEP = {RALLY_STEP};");
    let _ = writeln!(out, "localparam integer CH_MAX_MULT = {MAX_MULTIPLIER};");
    // l'hardware moltiplica per i punti con shift e somme: devono essere quelli attesi
    assert_eq!(
        (HIT_POINTS, POINT_POINTS, RALLY_STEP, MAX_MULTIPLIER),
        (10, 100, 4, 8),
        "punti di CHALLENGE cambiati: aggiornare pong_top.v"
    );
    // un livello per riga: tipo della CPU, livello della CPU, velocità, bonus (3 bit ciascuno),
    // righe della scelta dei bonus (STEER, codice 6, è la riga 5), punti per vincere
    type RungField = fn(&paddws_core::challenge::Rung) -> (u32, u32);
    let fields: [(&str, RungField); 6] = [
        ("rung_kind", |r| (r.kind as u32, 3)),
        ("rung_cpu", |r| (r.cpu as u32, 4)),
        ("rung_speed", |r| (r.speed as u32, 2)),
        ("rung_loadout", |r| {
            (
                r.loadout.iter().enumerate().map(|(k, b)| (*b as u32) << (3 * k)).sum(),
                9,
            )
        }),
        ("rung_pick", |r| {
            let row = |b: paddws_core::Bonus| if b as u32 == 6 { 5 } else { b as u32 };
            (r.loadout.iter().map(|b| 1 << row(*b)).sum(), 6)
        }),
        ("rung_points", |r| (r.points as u32, 5)),
    ];
    for (name, f) in fields {
        let bits = f(&RUNGS[0]).1;
        let _ = writeln!(out, "function [{}:0] {name}(input [2:0] lvl);", bits - 1);
        let _ = writeln!(out, "    case (lvl)");
        for (i, r) in RUNGS.iter().enumerate() {
            let _ = writeln!(out, "        3'd{i}: {name} = {bits}'d{};", f(r).0);
        }
        let _ = writeln!(out, "        default: {name} = {bits}'d{};", f(&RUNGS[LEVELS - 1]).0);
        let _ = writeln!(out, "    endcase");
        let _ = writeln!(out, "endfunction");
    }
    // premi della vittoria per livello: (vittoria, partita perfetta)
    for (name, perfect) in [("ch_win_bonus", false), ("ch_perfect_bonus", true)] {
        let _ = writeln!(out, "function [15:0] {name}(input [2:0] lvl);");
        let _ = writeln!(out, "    case (lvl)");
        for i in 0..LEVELS {
            let (w, p) = Score::win_bonus(i, 0);
            let _ = writeln!(out, "        3'd{i}: {name} = 16'd{};", if perfect { p } else { w });
        }
        let _ = writeln!(out, "        default: {name} = 16'd0;");
        let _ = writeln!(out, "    endcase");
        let _ = writeln!(out, "endfunction");
    }
    // classifica iniziale: punti e livello di ogni posto
    let t = Table::default();
    let _ = writeln!(out, "localparam integer CH_TABLE_SIZE = {TABLE_SIZE};");
    let _ = writeln!(out, "function [23:0] ch_default_score(input [3:0] i);");
    let _ = writeln!(out, "    case (i)");
    for (i, e) in t.entries.iter().enumerate() {
        let _ = writeln!(out, "        4'd{i}: ch_default_score = 24'd{};", e.score);
    }
    let _ = writeln!(out, "        default: ch_default_score = 24'd0;");
    let _ = writeln!(out, "    endcase");
    let _ = writeln!(out, "endfunction");
    // gli stessi punti in BCD (7 cifre), per il disegno
    let _ = writeln!(out, "function [27:0] ch_default_bcd(input [3:0] i);");
    let _ = writeln!(out, "    case (i)");
    for (i, e) in t.entries.iter().enumerate() {
        let _ = writeln!(out, "        4'd{i}: ch_default_bcd = 28'h{:07};", e.score);
    }
    let _ = writeln!(out, "        default: ch_default_bcd = 28'h0;");
    let _ = writeln!(out, "    endcase");
    let _ = writeln!(out, "endfunction");
    let _ = writeln!(out, "function [3:0] ch_default_level(input [3:0] i);");
    let _ = writeln!(out, "    case (i)");
    for (i, e) in t.entries.iter().enumerate() {
        let _ = writeln!(out, "        4'd{i}: ch_default_level = 4'd{};", e.level);
    }
    let _ = writeln!(out, "        default: ch_default_level = 4'd1;");
    let _ = writeln!(out, "    endcase");
    let _ = writeln!(out, "endfunction");
    out
}

/// Chi gioca nelle statistiche: la CPU del gioco o un umano simulato.
enum Player {
    Cpu(Cpu),
    Human(Box<Human>),
}

impl Player {
    fn input(&mut self, m: &Match) -> PlayerInput {
        match self {
            Player::Cpu(c) => c.input(m),
            Player::Human(h) => h.input(m),
        }
    }

    fn side(&self) -> Side {
        match self {
            Player::Cpu(c) => c.side(),
            Player::Human(h) => h.side(),
        }
    }
}

/// I due giocatori della partita `game`: umani simulati del profilo `skill` con `--human`,
/// altrimenti CPU al livello `level`.
fn players(a: &Args, game: &Match, level: u8, skill: usize, control: [Control; 2], seed: u32) -> [Player; 2] {
    let one = |side: Side, seed: u32| {
        let c = control[side as usize];
        if a.human {
            Player::Human(Box::new(Human::new(game, skill, c, side, seed)))
        } else {
            Player::Cpu(Cpu::new(&game.params, level, side, seed).with_control(c))
        }
    };
    [one(Side::Left, seed), one(Side::Right, seed ^ 1)]
}

/// Statistiche di uno stile di gioco: scambi (tick in gioco, colpi) e bonus.
#[derive(Default)]
struct Stats {
    matches: u32,
    ticks: u64,
    rallies: Vec<(u32, u32)>,
    spawned: u32,
    collected: u32,
    activated: u32,
    supers: u32,
    bullets: u32,
}

impl Stats {
    fn print(&self, label: &str, hz: u32) {
        let n = self.rallies.len().max(1) as f64;
        let mut secs: Vec<f64> = self.rallies.iter().map(|r| r.0 as f64 / hz as f64).collect();
        secs.sort_by(f64::total_cmp);
        let at = |q: f64| {
            secs.get(((secs.len() as f64 - 1.0) * q) as usize)
                .copied()
                .unwrap_or(0.0)
        };
        let hits: f64 = self.rallies.iter().map(|r| r.1 as f64).sum::<f64>() / n;
        println!(
            "{label:8} {} partite, {} scambi | scambio: media {:.1} s, mediana {:.1} s, 90% sotto {:.1} s, {:.1} colpi | partita {:.1} min",
            self.matches,
            self.rallies.len(),
            secs.iter().sum::<f64>() / n,
            at(0.5),
            at(0.9),
            hits,
            self.ticks as f64 / hz as f64 / 60.0 / self.matches.max(1) as f64,
        );
        if self.spawned > 0 {
            println!(
                "         per scambio: {:.1} capsule partite, {:.1} raccolte, {:.1} bonus usati ({:.2} SUPER, {:.2} BULLET)",
                self.spawned as f64 / n,
                self.collected as f64 / n,
                self.activated as f64 / n,
                self.supers as f64 / n,
                self.bullets as f64 / n,
            );
        }
    }
}

/// Partite a 11 tra giocatori simulati, in Classic e in NEXT: per regolare la velocità di NEXT.
fn next_stats(a: &Args) {
    use paddws_core::{Bonus, Event};
    let params = Params::new(&tuning(a, a.difficulty));
    let loadouts = [
        [Bonus::Smash, Bonus::Teleport, Bonus::Curve],
        [Bonus::Slow, Bonus::Ghost, Bonus::Smash],
    ];
    for next in [false, true] {
        let mut st = Stats::default();
        for i in 0..a.next_stats {
            let seed = a.seed.wrapping_add(i.wrapping_mul(7919));
            let mut game = if next {
                Match::new_next(params.clone(), loadouts, seed)
            } else {
                Match::new(params.clone(), 2, false, seed)
            };
            game.set_super_moves(a.supers);
            let mut script = Script::new(seed);
            let mut bonus_rng = Rng::new(seed ^ 0xB0_0057);
            let mut cpus = players(a, &game, a.difficulty, a.skill.unwrap_or(1), a.control, seed);
            let (mut rally_ticks, mut rally_hits) = (0u32, 0u32);
            // al massimo 30 minuti di gioco per partita
            for _ in 0..a.tick_hz * 60 * 30 {
                let mut input = script.next(&game, false);
                if a.cpu || a.human {
                    for cpu in &mut cpus {
                        input.players[cpu.side() as usize] = cpu.input(&game);
                    }
                } else if next {
                    for cmd in &mut input.players {
                        cmd.select = bonus_rng.below(200) == 0;
                        cmd.activate = bonus_rng.below(120) == 0;
                    }
                }
                let idle = game.next.as_ref().is_none_or(|n| n.bullet.is_none());
                let events = game.step(&input);
                st.bullets += (idle && game.next.as_ref().is_some_and(|n| n.bullet.is_some())) as u32;
                st.ticks += 1;
                if !game.serving() {
                    rally_ticks += 1;
                }
                rally_hits += (events.has(Event::Hit) || events.has(Event::Boost)) as u32;
                st.collected += events.has(Event::Collect) as u32;
                st.activated += events.has(Event::Activate) as u32;
                st.supers += events.has(Event::Super) as u32;
                if events.has(Event::Score) {
                    st.rallies.push((rally_ticks, rally_hits));
                    (rally_ticks, rally_hits) = (0, 0);
                    if game.score.iter().any(|&s| s >= 11) {
                        break;
                    }
                }
            }
            st.spawned += game.next.as_ref().map_or(0, |n| n.spawned);
            st.matches += 1;
        }
        st.print(if next { "NEXT" } else { "CLASSIC" }, a.tick_hz);
    }
}

/// Efficacia di ogni bonus in partite NEXT tra due CPU in cui tutte le capsule portano quel
/// bonus. Per i tiri (SMASH, SUPER, CURVE, GHOST): quante volte l'avversario non rimanda il
/// tiro col bonus, rispetto a un tiro normale. TELEPORT: palle ribattute con il bonus attivo.
/// SLOW: punti vinti da chi lo attiva.
fn bonus_stats(a: &Args) {
    use paddws_core::{Bonus, Event};
    let params = Params::new(&tuning(a, a.difficulty));
    println!(
        "{} partite per bonus, difficolta {}, campo {}x{}",
        a.bonus_stats, a.difficulty, a.width, a.height
    );
    // riferimento: partite NEXT in cui nessuno attiva bonus
    let mut base = (0u32, 0u32);
    let mut points = [0u32; 2];
    for i in 0..a.bonus_stats {
        let seed = a.seed.wrapping_add(i.wrapping_mul(7919));
        let mut game = Match::new_next(params.clone(), [[Bonus::Teleport; 3]; 2], seed);
        game.set_super_moves(a.supers);
        let mut cpus = players(a, &game, a.difficulty, a.skill.unwrap_or(1), a.control, seed);
        let mut last: Option<usize> = None;
        for _ in 0..a.tick_hz * 60 * 30 {
            let mut input = Input::default();
            for cpu in &mut cpus {
                let mut cmd = cpu.input(&game);
                cmd.activate = false;
                input.players[cpu.side() as usize] = cmd;
            }
            if std::env::var_os("SENZA_CAPSULE").is_some() {
                game.next.as_mut().unwrap().spawn_timer = u32::MAX;
            }
            let before = game.score;
            let events = game.step(&input);
            if events.has(Event::Hit) || events.has(Event::Boost) {
                base.0 += 1;
                last = Some(if game.ball.vx > 0 { 0 } else { 1 });
            }
            if events.has(Event::Score) {
                let scorer = if game.score[0] > before[0] { 0 } else { 1 };
                points[scorer] += 1;
                base.1 += (last == Some(scorer)) as u32;
                last = None;
                if game.score.iter().any(|&s| s >= 11) {
                    break;
                }
            }
        }
    }
    println!(
        "comandi {:?} contro {:?} | senza bonus: tiro vincente {:.1}% ({} tiri), punti vinti a sinistra {:.1}%",
        a.control[0],
        a.control[1],
        100.0 * base.1 as f64 / base.0.max(1) as f64,
        base.0,
        100.0 * points[0] as f64 / (points[0] + points[1]).max(1) as f64
    );
    for bonus in Bonus::PICKABLE {
        // contatori: tiri normali e vincenti, tiri col bonus e vincenti, attivazioni e successi
        let (mut shots, mut winners, mut bonus_shots, mut bonus_winners) = (0u32, 0u32, 0u32, 0u32);
        let (mut uses, mut wins) = (0u32, 0u32);
        let mut supers = (0u32, 0u32);
        let mut rallies = 0u32;
        for i in 0..a.bonus_stats {
            let seed = a.seed.wrapping_add(i.wrapping_mul(7919));
            let mut game = Match::new_next(params.clone(), [[bonus; 3]; 2], seed);
            game.set_super_moves(a.supers);
            let mut cpus = players(a, &game, a.difficulty, a.skill.unwrap_or(1), a.control, seed);
            // ultimo tiro: (chi l'ha fatto, bonus usato) e SLOW attivo: chi l'ha attivato
            let mut last_shot: Option<(usize, Option<Bonus>)> = None;
            let mut slow_by: Vec<usize> = Vec::new();
            let mut teleport_waiting = [false; 2];
            for _ in 0..a.tick_hz * 60 * 30 {
                let mut input = Input::default();
                for cpu in &mut cpus {
                    input.players[cpu.side() as usize] = cpu.input(&game);
                }
                let n = game.next.as_ref().unwrap();
                let armed_before = [n.players[0].armed, n.players[1].armed];
                let bullet_before = n.bullet;
                let counts_before = [n.players[0].count(), n.players[1].count()];
                let score_before = game.score;
                let events = game.step(&input);
                let n = game.next.as_ref().unwrap();
                if events.has(Event::Activate) {
                    for side in 0..2 {
                        // SLOW non resta armato (il BULLET nemmeno, ma accende il bullet time)
                        let bullet = n.bullet.is_some_and(|s| s as usize == side) && bullet_before.is_none();
                        if n.players[side].count() < counts_before[side] && n.players[side].armed.is_none() && !bullet {
                            slow_by.push(side);
                            uses += 1;
                        }
                        if n.players[side].armed == Some(Bonus::Teleport) {
                            teleport_waiting[side] = true;
                        }
                    }
                }
                if events.has(Event::Hit) || events.has(Event::Boost) || events.has(Event::Super) {
                    let hitter = if game.ball.vx > 0 { 0 } else { 1 };
                    let used = armed_before[hitter].filter(|_| n.players[hitter].armed.is_none());
                    match used {
                        Some(Bonus::Teleport) => {
                            teleport_waiting[hitter] = false;
                            uses += 1;
                            wins += 1; // ribattuta con TELEPORT
                        }
                        Some(b) => {
                            bonus_shots += 1;
                            if events.has(Event::Super) {
                                supers.0 += 1;
                            }
                            last_shot = Some((hitter, Some(b)));
                        }
                        None => {
                            shots += 1;
                            last_shot = Some((hitter, None));
                        }
                    }
                }
                if events.has(Event::Score) {
                    rallies += 1;
                    let scorer = if game.score[0] > score_before[0] { 0 } else { 1 };
                    match last_shot {
                        Some((who, Some(Bonus::Super))) if who == scorer => {
                            bonus_winners += 1;
                            supers.1 += 1;
                        }
                        Some((who, Some(_))) if who == scorer => bonus_winners += 1,
                        Some((who, None)) if who == scorer => winners += 1,
                        _ => {}
                    }
                    wins += slow_by.iter().filter(|&&who| who == scorer).count() as u32;
                    slow_by.clear();
                    let loser = 1 - scorer;
                    if teleport_waiting[loser] && armed_before[loser] == Some(Bonus::Teleport) {
                        uses += 1; // TELEPORT attivo ma palla persa
                        teleport_waiting[loser] = false;
                    }
                    last_shot = None;
                    if game.score.iter().any(|&s| s >= 11) {
                        break;
                    }
                }
            }
        }
        let pct = |a: u32, b: u32| 100.0 * a as f64 / b.max(1) as f64;
        let base = pct(winners, shots);
        match bonus {
            Bonus::Teleport => println!(
                "{:8} ribattute con TELEPORT {:5.1}% ({} usi) | tiro normale vincente {:4.1}%",
                bonus.name(),
                pct(wins, uses),
                uses,
                base
            ),
            Bonus::Slow => println!(
                "{:8} punti vinti da chi lo usa {:5.1}% ({} usi) | tiro normale vincente {:4.1}%",
                bonus.name(),
                pct(wins, uses),
                uses,
                base
            ),
            _ => println!(
                "{:8} tiro col bonus vincente {:5.1}% ({} tiri) | tiro normale {:4.1}% | SUPER {:5.1}% ({} tiri) | {:.1} scambi a partita",
                bonus.name(),
                pct(bonus_winners - supers.1, bonus_shots - supers.0),
                bonus_shots - supers.0,
                base,
                pct(supers.1, supers.0),
                supers.0,
                rallies as f64 / a.bonus_stats.max(1) as f64
            ),
        }
    }
    bullet_stats(a, &params);
}

/// BULLET: partite in cui tutte le capsule portano il BULLET (più i SUPER), giocate due volte con
/// gli stessi semi, una con il BULLET e una togliendo le sue attivazioni. Un'emergenza è la prima
/// volta in un punto che il giocatore (la CPU, o l'umano simulato che ne usa le decisioni) vuole
/// attivarlo per una palla in arrivo: si conta se la ribatte (palla salvata) e se vince il punto.
fn bullet_stats(a: &Args, params: &Params) {
    use paddws_core::{Bonus, Event};
    let mut rows = Vec::new();
    for allowed in [true, false] {
        let (mut cases, mut saved, mut won) = (0u32, 0u32, 0u32);
        for i in 0..a.bonus_stats {
            let seed = a.seed.wrapping_add(i.wrapping_mul(7919));
            let mut game = Match::new_next(params.clone(), [[Bonus::Bullet; 3]; 2], seed);
            game.set_super_moves(a.supers);
            let mut cpus = players(a, &game, a.difficulty, a.skill.unwrap_or(1), a.control, seed);
            // emergenza in corso per lato: la palla è stata già ribattuta
            let mut pending: [Option<bool>; 2] = [None; 2];
            for _ in 0..a.tick_hz * 60 * 30 {
                let mut input = Input::default();
                for cpu in &mut cpus {
                    input.players[cpu.side() as usize] = cpu.input(&game);
                }
                let n = game.next.as_ref().unwrap();
                let idle = n.bullet.is_none();
                for ((cmd, pl), pending) in input.players.iter_mut().zip(&n.players).zip(&mut pending) {
                    if !allowed && cmd.activate && idle && pl.selected_bonus() == Some(Bonus::Bullet) {
                        cmd.activate = false;
                        if pending.is_none() {
                            *pending = Some(false);
                            cases += 1;
                        }
                    }
                }
                let score_before = game.score;
                let events = game.step(&input);
                let n = game.next.as_ref().unwrap();
                // come senza BULLET, conta solo la prima emergenza di ogni punto
                if allowed
                    && idle
                    && let Some(side) = n.bullet
                    && pending[side as usize].is_none()
                {
                    pending[side as usize] = Some(false);
                    cases += 1;
                }
                if events.has(Event::Hit) || events.has(Event::Boost) || events.has(Event::Super) {
                    let hitter = if game.ball.vx > 0 { 0 } else { 1 };
                    if let Some(back) = &mut pending[hitter] {
                        *back = true;
                    }
                }
                if events.has(Event::Score) {
                    let scorer = if game.score[0] > score_before[0] { 0 } else { 1 };
                    for (side, p) in pending.iter_mut().enumerate() {
                        if let Some(back) = p.take() {
                            saved += back as u32;
                            won += (side == scorer) as u32;
                        }
                    }
                    if game.score.iter().any(|&s| s >= 11) {
                        break;
                    }
                }
            }
        }
        rows.push((cases, saved, won));
    }
    let pct = |a: u32, b: u32| 100.0 * a as f64 / b.max(1) as f64;
    let ((c1, s1, w1), (c0, s0, w0)) = (rows[0], rows[1]);
    println!(
        "{:8} palle salvate {:5.1}% ({} casi, {:.1} a partita) | senza BULLET {:5.1}% ({} casi) | punto vinto {:4.1}% contro {:4.1}% | punti in più {:.1} ogni 100 casi",
        Bonus::Bullet.name(),
        pct(s1, c1),
        c1,
        c1 as f64 / a.bonus_stats.max(1) as f64,
        pct(s0, c0),
        c0,
        pct(w1, c1),
        pct(w0, c0),
        pct(w1, c1) - pct(w0, c0),
    );
}

/// TELEPORT contro palle sempre più veloci: la palla parte dalla racchetta destra con
/// angolo casuale, quella sinistra ha TELEPORT armato, parte da un punto casuale e non
/// viene mossa dal giocatore. Si conta quante volte la ribatte.
fn teleport_stats(a: &Args) {
    use paddws_core::{Bonus, Event};
    let params = Params::new(&tuning(a, a.difficulty));
    let max = fixed::to_f32(params.max_ball_speed_next) as f64;
    let mul = |m: Fx| fixed::to_f32(m) as f64;
    let cases = [
        ("meta' della massima", max * 0.5),
        ("massima", max),
        ("SMASH", max * mul(params.smash_mul)),
        ("SUPER", max * mul(params.super_mul)),
    ];
    println!(
        "{} prove per velocita', difficolta {}, campo {}x{}",
        a.teleport_stats, a.difficulty, a.width, a.height
    );
    let mut rng = Rng::new(a.seed);
    for (name, speed) in cases {
        let mut caught = 0u32;
        for i in 0..a.teleport_stats {
            let mut game = Match::new_next(params.clone(), [[Bonus::Teleport; 3]; 2], a.seed.wrapping_add(i));
            game.serve_timer = 0;
            let n = game.next.as_mut().unwrap();
            n.spawn_timer = u32::MAX;
            n.players[0].armed = Some(Bonus::Teleport);
            let h = fixed::to_f32(params.height) as f64;
            let r = &game.paddles[1];
            game.ball.x = r.x - r.width / 2 - game.ball.radius;
            game.ball.y = fixed::from_f64(h * (0.05 + 0.9 * fixed::to_f32(rng.frac()) as f64));
            game.ball.vx = fixed::from_f64(-speed);
            game.ball.vy = fixed::from_f64(speed * 0.75 * (2.0 * fixed::to_f32(rng.frac()) as f64 - 1.0));
            let half = fixed::to_f32(game.paddles[0].height) as f64 / 2.0;
            game.paddles[0].y = fixed::from_f64(half + (h - 2.0 * half) * fixed::to_f32(rng.frac()) as f64);
            for _ in 0..a.tick_hz * 10 {
                let events = game.step(&Input::default());
                if events.has(Event::Hit) || events.has(Event::Boost) || game.ball.vx > 0 {
                    caught += 1;
                    break;
                }
                if events.has(Event::Score) {
                    break;
                }
            }
        }
        println!(
            "{:20} {:5.1} px/tick: prese {:5.1}%",
            name,
            speed * 4.0 * 800.0 / a.width as f64,
            100.0 * caught as f64 / a.teleport_stats.max(1) as f64
        );
    }
}

/// Tipi di racchetta: ogni tipo contro la racchetta senza tipo (ARCADE non è più neutra: ha più
/// capsule), metà delle partite a sinistra e metà a destra, due CPU con lo stesso livello e
/// comando e 3 bonus a caso ciascuna. Per ogni livello e comando: punti vinti dal tipo (percentuale).
fn paddle_stats(a: &Args) {
    use paddws_core::{Bonus, Event, PaddleKind};
    let controls = [Control::Spinner, Control::Joystick, Control::Keyboard];
    // gruppi di colonne: (difficoltà, profilo degli umani simulati, etichetta)
    let difficulties: Vec<(u8, usize, String)> = if a.human {
        let skills: Vec<usize> = a.skill.map_or((0..PROFILES.len()).collect(), |s| vec![s]);
        skills
            .into_iter()
            .map(|s| (a.difficulty, s, PROFILES[s].name[..3].to_string()))
            .collect()
    } else if a.difficulty_set {
        vec![(a.difficulty, 1, format!("d{}", a.difficulty))]
    } else {
        (0..DIFFICULTY_LEVELS).map(|d| (d, 1, format!("d{d}"))).collect()
    };
    println!(
        "{} partite a 11 per casella (meta' per lato), campo {}x{}{}: punti vinti dal tipo, in %",
        a.paddle_stats,
        a.width,
        a.height,
        if a.human {
            format!(", umani simulati, difficolta {}", a.difficulty)
        } else {
            String::new()
        }
    );
    let mut header = format!("{:9}", "");
    for (_, _, label) in &difficulties {
        for c in controls {
            let _ = write!(header, " {:>8}", format!("{label}-{}", &format!("{c:?}")[..3]));
        }
    }
    println!("{header}  {:>6} {:>6}", "media", "match");

    // una riga per tipo, calcolate in parallelo
    let rows: Vec<String> = std::thread::scope(|s| {
        let handles: Vec<_> = PaddleKind::ALL
            .iter()
            .filter(|k| a.kinds.is_empty() || a.kinds.iter().any(|n| n.eq_ignore_ascii_case(k.name())))
            .map(|&kind| {
                let difficulties = &difficulties;
                s.spawn(move || {
                    let rival = None;
                    let mut row = format!("{:9}", kind.name());
                    let (mut sum, mut cells, mut won, mut played) = (0.0, 0, 0u32, 0u32);
                    // abilità usate: spari del BLASTER e barriere del GUARDIAN
                    let mut uses = [0u32; 2];
                    for &(d, skill, _) in difficulties {
                        let params = Params::new(&tuning(a, d));
                        for control in controls {
                            let mut points = [0u32; 2]; // tipo, avversario
                            for i in 0..a.paddle_stats {
                                let seed = a.seed.wrapping_add(i.wrapping_mul(7919));
                                let mut rng = Rng::new(seed ^ 0x9AD_D1E5);
                                let mut loadout = || {
                                    let mut pool = Bonus::PICKABLE;
                                    for k in 0..3 {
                                        let j = k + rng.below((pool.len() - k) as u32) as usize;
                                        pool.swap(k, j);
                                    }
                                    [pool[0], pool[1], pool[2]]
                                };
                                let loadouts = [loadout(), loadout()];
                                let me = (i % 2) as usize; // lato del tipo
                                let mut kinds = [rival; 2];
                                kinds[me] = Some(kind);
                                let mut game = Match::new_next_paddles(params.clone(), loadouts, kinds, seed);
                                game.set_super_moves(a.supers);
                                let mut cpus = players(a, &game, d, skill, [control; 2], seed);
                                for _ in 0..a.tick_hz * 60 * 30 {
                                    let mut input = Input::default();
                                    for cpu in &mut cpus {
                                        input.players[cpu.side() as usize] = cpu.input(&game);
                                    }
                                    let events = game.step(&input);
                                    uses[0] += events.has(Event::Fire) as u32;
                                    uses[1] += events.has(Event::Barrier) as u32;
                                    if game.score.iter().any(|&s| s >= 11) {
                                        break;
                                    }
                                }
                                points[0] += game.score[me] as u32;
                                points[1] += game.score[1 - me] as u32;
                                won += (game.score[me] > game.score[1 - me]) as u32;
                                played += 1;
                            }
                            let pct = 100.0 * points[0] as f64 / (points[0] + points[1]).max(1) as f64;
                            let _ = write!(row, " {pct:8.1}");
                            sum += pct;
                            cells += 1;
                        }
                    }
                    let _ = write!(
                        row,
                        "  {:6.1} {:6.1}",
                        sum / cells as f64,
                        100.0 * won as f64 / played.max(1) as f64
                    );
                    if uses.iter().any(|&u| u > 0) {
                        let per = |u: u32| u as f64 / played.max(1) as f64;
                        let _ = write!(
                            row,
                            "  | a partita: spari {:.1}, barriera {:.1}",
                            per(uses[0]),
                            per(uses[1])
                        );
                    }
                    row
                })
            })
            .collect();
        handles.into_iter().map(|h| h.join().unwrap()).collect()
    });
    for row in rows {
        println!("{row}");
    }
}

/// Umani simulati contro la CPU del gioco: per ogni profilo (righe) e livello della CPU (colonne,
/// alla stessa difficoltà della partita) i punti vinti dall'umano, metà delle partite per lato.
/// Sotto: durata media di scambi e partite, e quante palle in arrivo l'umano manca.
fn human_stats(a: &Args) {
    use paddws_core::{Bonus, Event};
    let skills: Vec<usize> = a.skill.map_or((0..PROFILES.len()).collect(), |s| vec![s]);
    println!(
        "{} partite a 11 per casella, {}, umano con {:?}, CPU con {:?}, campo {}x{}: punti vinti dall'umano, in %",
        a.human_stats,
        if a.next { "NEXT" } else { "EVO" },
        a.control[0],
        a.control[1],
        a.width,
        a.height
    );
    let mut header = format!("{:13}", "");
    for d in 0..DIFFICULTY_LEVELS {
        let _ = write!(header, " {:>7}", format!("CPU d{d}"));
    }
    println!("{header}   scambio  partita  palle mancate");
    for skill in skills {
        let mut row = format!("{:13}", PROFILES[skill].name);
        let (mut rally_ticks, mut rallies, mut match_ticks, mut matches) = (0u64, 0u32, 0u64, 0u32);
        let (mut faced, mut missed) = (0u32, 0u32);
        for d in 0..DIFFICULTY_LEVELS {
            let params = Params::new(&tuning(a, d));
            let mut points = [0u32; 2]; // umano, CPU
            for i in 0..a.human_stats {
                let seed = a.seed.wrapping_add(i.wrapping_mul(7919));
                let me = (i % 2) as usize;
                let mut game = if a.next {
                    let loadouts = [
                        [Bonus::Smash, Bonus::Teleport, Bonus::Curve],
                        [Bonus::Slow, Bonus::Ghost, Bonus::Super],
                    ];
                    Match::new_next(params.clone(), loadouts, seed)
                } else {
                    Match::new(params.clone(), 2, true, seed)
                };
                game.set_super_moves(a.supers);
                let human_side = if me == 0 { Side::Left } else { Side::Right };
                let mut human = Human::new(&game, skill, a.control[0], human_side, seed);
                let mut cpu = Cpu::new(&params, d, human_side.opponent(), seed ^ 1).with_control(a.control[1]);
                let mut rally = 0u64;
                for _ in 0..a.tick_hz * 60 * 30 {
                    let mut input = Input::default();
                    input.players[me] = human.input(&game);
                    input.players[1 - me] = cpu.input(&game);
                    let before = game.score;
                    let toward_me = (game.ball.vx < 0) == (me == 0);
                    let events = game.step(&input);
                    match_ticks += 1;
                    rally += !game.serving() as u64;
                    if (events.has(Event::Hit) || events.has(Event::Boost)) && toward_me {
                        faced += 1;
                    }
                    if events.has(Event::Score) {
                        if game.score[1 - me] > before[1 - me] {
                            faced += 1;
                            missed += 1;
                        }
                        rally_ticks += rally;
                        rally = 0;
                        rallies += 1;
                        if game.score.iter().any(|&s| s >= 11) {
                            break;
                        }
                    }
                }
                points[0] += game.score[me] as u32;
                points[1] += game.score[1 - me] as u32;
                matches += 1;
            }
            let _ = write!(
                row,
                " {:7.1}",
                100.0 * points[0] as f64 / (points[0] + points[1]).max(1) as f64
            );
        }
        let _ = write!(
            row,
            "   {:5.1} s  {:5.1} min  {:5.1}%",
            rally_ticks as f64 / a.tick_hz as f64 / rallies.max(1) as f64,
            match_ticks as f64 / a.tick_hz as f64 / 60.0 / matches.max(1) as f64,
            100.0 * missed as f64 / faced.max(1) as f64
        );
        println!("{row}");
    }
}

/// CHALLENGE: per ogni profilo di umano simulato (righe) e livello (colonne) le partite vinte
/// dall'umano, che gioca a sinistra con bonus e racchetta a caso; sotto, durata media delle
/// partite e punti arcade a partita vinta.
fn challenge_stats(a: &Args) {
    use paddws_core::Bonus;
    use paddws_core::challenge::{RUNGS, Score};
    let skills: Vec<usize> = a.skill.map_or((0..PROFILES.len()).collect(), |s| vec![s]);
    println!(
        "{} partite per livello, difficolta {}, umano con {:?}, campo {}x{}: partite vinte dall'umano, in %",
        a.challenge_stats, a.difficulty, a.control[0], a.width, a.height
    );
    let mut header = format!("{:13}", "");
    for (i, r) in RUNGS.iter().enumerate() {
        let _ = write!(header, " {:>9}", format!("{}-{}", i + 1, &r.kind.name()[..3]));
    }
    println!("{header}   partita  punti/vittoria");
    for skill in skills {
        let mut row = format!("{:13}", PROFILES[skill].name);
        let (mut ticks, mut matches, mut won_points, mut won) = (0u64, 0u32, 0u64, 0u32);
        for (level, rung) in RUNGS.iter().enumerate() {
            let params = Params::new(&tuning(a, rung.speed_at(a.difficulty)));
            let mut wins = 0u32;
            for i in 0..a.challenge_stats {
                let seed = a.seed.wrapping_add(i.wrapping_mul(7919));
                let mut rng = Rng::new(seed ^ 0xC4A1_1E6E);
                let mut pool = Bonus::PICKABLE;
                for k in 0..3 {
                    let j = k + rng.below((pool.len() - k) as u32) as usize;
                    pool.swap(k, j);
                }
                let mine = PaddleKind::ALL[rng.below(PaddleKind::COUNT as u32) as usize];
                let mut game = Match::new_next_paddles(
                    params.clone(),
                    [[pool[0], pool[1], pool[2]], rung.loadout],
                    [Some(mine), Some(rung.kind)],
                    seed,
                );
                let mut human = Human::new(&game, skill, a.control[0], Side::Left, seed);
                let mut cpu = Cpu::new(&params, rung.cpu, Side::Right, seed ^ 1).with_control(a.control[1]);
                let mut score = Score::new(Side::Left);
                for _ in 0..a.tick_hz * 60 * 30 {
                    let mut input = Input::default();
                    input.players[0] = human.input(&game);
                    input.players[1] = cpu.input(&game);
                    let before = game.score;
                    let events = game.step(&input);
                    score.on_tick(&game, before, events);
                    ticks += 1;
                    if game.score.iter().any(|&s| s >= rung.points) {
                        break;
                    }
                }
                matches += 1;
                if game.score[0] > game.score[1] {
                    wins += 1;
                    won += 1;
                    let (w, p) = Score::win_bonus(level, game.score[1]);
                    won_points += (score.total + w + p) as u64;
                }
            }
            let _ = write!(row, " {:9.1}", 100.0 * wins as f64 / a.challenge_stats.max(1) as f64);
        }
        let _ = write!(
            row,
            "   {:5.1} min  {:8.0}",
            ticks as f64 / a.tick_hz as f64 / 60.0 / matches.max(1) as f64,
            won_points as f64 / won.max(1) as f64
        );
        println!("{row}");
    }
}

/// Mosse speciali: partite NEXT a 11 con le mosse spente e accese, stessi semi e stessi giocatori
/// (CPU contro CPU, o umani simulati con `--human`), riserve con SMASH, CURVE e TELEPORT. Per ogni
/// livello e caso: durata degli scambi, mosse usate a partita (e RISING STRIKE finiti in un colpo)
/// e, per ogni tipo di tiro, quante volte l'avversario non lo rimanda (tiro vincente).
fn super_stats(a: &Args) {
    use paddws_core::{Bonus, Event, Special};
    const SHOTS: [&str; 6] = ["normale", "SMASH", "CURVE", "SUPER", "STRAIGHT", "RISING"];
    let levels: Vec<u8> = if a.difficulty_set {
        vec![a.difficulty]
    } else {
        (0..DIFFICULTY_LEVELS).collect()
    };
    let skill = a.skill.unwrap_or(1);
    println!(
        "{} partite a 11 per caso, {}, comandi {:?} contro {:?}, campo {}x{}: tiri vincenti in % (tiri)",
        a.super_stats,
        if a.human {
            format!("umani simulati {}", PROFILES[skill].name)
        } else {
            "CPU contro CPU".to_string()
        },
        a.control[0],
        a.control[1],
        a.width,
        a.height
    );
    let cases: Vec<(u8, bool)> = levels.iter().flat_map(|&d| [(d, false), (d, true)]).collect();
    let rows: Vec<String> = std::thread::scope(|s| {
        let handles: Vec<_> = cases
            .iter()
            .map(|&(d, on)| {
                s.spawn(move || {
                    let params = Params::new(&tuning(a, d));
                    let loadouts = [[Bonus::Smash, Bonus::Curve, Bonus::Teleport]; 2];
                    let (mut shots, mut winners) = ([0u32; 6], [0u32; 6]);
                    let (mut uses, mut rise_hits) = ([0u32; 2], 0u32);
                    let (mut rally_ticks, mut rallies, mut hits, mut ticks) = (0u64, 0u32, 0u32, 0u64);
                    for i in 0..a.super_stats {
                        let seed = a.seed.wrapping_add(i.wrapping_mul(7919));
                        let mut game = Match::new_next(params.clone(), loadouts, seed);
                        game.set_super_moves(on);
                        let mut cpus = players(a, &game, d, skill, a.control, seed);
                        // ultimo tiro: chi l'ha fatto e di che tipo (indice in SHOTS)
                        let mut last: Option<(usize, usize)> = None;
                        let mut rally = 0u64;
                        for _ in 0..a.tick_hz * 60 * 30 {
                            let mut input = Input::default();
                            for cpu in &mut cpus {
                                input.players[cpu.side() as usize] = cpu.input(&game);
                            }
                            let n = game.next.as_ref().unwrap();
                            let armed = [n.players[0].armed, n.players[1].armed];
                            let before = game.score;
                            let events = game.step(&input);
                            ticks += 1;
                            rally += !game.serving() as u64;
                            uses[0] += events.has(Event::Straight) as u32;
                            uses[1] += events.has(Event::Rise) as u32;
                            let n = game.next.as_ref().unwrap();
                            if events.has(Event::Hit) || events.has(Event::Boost) || events.has(Event::Super) {
                                let hitter = if game.ball.vx > 0 { 0 } else { 1 };
                                let used = armed[hitter].filter(|_| n.players[hitter].armed.is_none());
                                let kind = match (events.has(Event::SpecialHit), n.special_flight, used) {
                                    (true, Some(Special::Straight), _) => 4,
                                    (true, Some(Special::Rise), _) => 5,
                                    (_, _, Some(Bonus::Smash)) => 1,
                                    (_, _, Some(Bonus::Curve)) => 2,
                                    (_, _, Some(Bonus::Super)) => 3,
                                    _ => 0, // anche TELEPORT, che non cambia il tiro
                                };
                                rise_hits += (kind == 5) as u32;
                                shots[kind] += 1;
                                hits += 1;
                                last = Some((hitter, kind));
                            }
                            if events.has(Event::Score) {
                                let scorer = if game.score[0] > before[0] { 0 } else { 1 };
                                if let Some((who, kind)) = last
                                    && who == scorer
                                {
                                    winners[kind] += 1;
                                }
                                last = None;
                                rallies += 1;
                                rally_ticks += rally;
                                rally = 0;
                                if game.score.iter().any(|&s| s >= 11) {
                                    break;
                                }
                            }
                        }
                    }
                    let hz = a.tick_hz as f64;
                    let per = |x: u32| x as f64 / a.super_stats.max(1) as f64;
                    let mut row = format!(
                        "d{d} {:6} scambio {:4.1} s {:4.1} colpi | partita {:4.1} min |",
                        if on { "accese" } else { "spente" },
                        rally_ticks as f64 / hz / rallies.max(1) as f64,
                        hits as f64 / rallies.max(1) as f64,
                        ticks as f64 / hz / 60.0 / a.super_stats.max(1) as f64
                    );
                    for (k, name) in SHOTS.iter().enumerate() {
                        if shots[k] > 0 {
                            let pct = 100.0 * winners[k] as f64 / shots[k] as f64;
                            let _ = write!(row, " {name} {pct:4.1} ({})", shots[k]);
                        }
                    }
                    if on {
                        let _ = write!(
                            row,
                            " | a partita: STRAIGHT {:.1}, RISING {:.1} (colpite {:.0}%)",
                            per(uses[0]),
                            per(uses[1]),
                            100.0 * rise_hits as f64 / uses[1].max(1) as f64
                        );
                    }
                    row
                })
            })
            .collect();
        handles.into_iter().map(|h| h.join().unwrap()).collect()
    });
    for row in rows {
        println!("{row}");
    }
}

fn main() {
    let a = parse_args();
    if a.super_stats > 0 {
        super_stats(&a);
        return;
    }
    if a.challenge_stats > 0 {
        challenge_stats(&a);
        return;
    }
    if a.human_stats > 0 {
        human_stats(&a);
        return;
    }
    if a.paddle_stats > 0 {
        paddle_stats(&a);
        return;
    }
    if a.teleport_stats > 0 {
        teleport_stats(&a);
        return;
    }
    if a.bonus_stats > 0 {
        bonus_stats(&a);
        return;
    }
    if a.next_stats > 0 {
        next_stats(&a);
        return;
    }
    let params = Params::new(&tuning(&a, a.difficulty));
    // con lo spinner a sinistra i bonus si scambiano: così chi usa l'encoder ha anche STEER
    let loadouts = if a.control[0] == Control::Spinner {
        [TRACE_LOADOUTS[1], TRACE_LOADOUTS[0]]
    } else {
        TRACE_LOADOUTS
    };
    if a.supers && !a.next {
        fail("--supers: le mosse speciali ci sono solo in NEXT (--next)");
    }
    let mut game = if a.next {
        Match::new_next_paddles(params.clone(), loadouts, a.paddles, a.seed)
    } else {
        Match::new(params.clone(), a.players, a.evo, a.seed)
    };
    game.set_super_moves(a.supers);
    let mut script = Script::new(a.seed);
    // NEXT: giocano due CPU, che raccolgono le capsule e usano i bonus
    let mut cpus = [
        Cpu::new(&params, a.difficulty, Side::Left, a.seed).with_control(a.control[0]),
        Cpu::new(&params, a.cpu_level.unwrap_or(a.difficulty), Side::Right, a.seed ^ 1).with_control(a.control[1]),
    ];
    let encoder = a.control[0] == Control::Spinner;

    let mut inputs = String::new();
    let mut states = String::new();
    let mut counts = [0u32; 13];
    for _ in 0..a.ticks {
        let mut input = script.next(&game, encoder);
        if a.next || a.cpu_play {
            for cpu in &mut cpus {
                input.players[cpu.side() as usize] = cpu.input(&game);
            }
            // la CPU spara un colpo alla volta: raffiche dal tasto di sparo (bit 7, che la CPU
            // non comanda) per provare il caricatore da 4 colpi
            for side in Side::BOTH {
                if game.paddle_kind(side) == Some(paddws_core::PaddleKind::Blaster) && game.tick % 600 < 120 {
                    input.players[side as usize].fire = true;
                }
            }
        }
        let events = game.step(&input);
        for (i, count) in counts.iter_mut().enumerate() {
            *count += (events.bits() >> i & 1) as u32;
        }
        let _ = writeln!(inputs, "{}", input_line(&input, a.supers));
        let words: Vec<String> = state_words(&game, events.bits())
            .iter()
            .map(|w| format!("{w:08x}"))
            .collect();
        let _ = writeln!(states, "{}", words.join(""));
    }

    fs::create_dir_all(&a.out).unwrap_or_else(|e| fail(&format!("{}: {e}", a.out.display())));
    let write = |name: &str, text: &str| {
        fs::write(a.out.join(name), text).unwrap_or_else(|e| fail(&format!("{name}: {e}")));
    };
    write("pong_params.vh", &verilog_params(&params, &a));
    let loadout_code = |i: usize| -> u32 { (0..3).map(|k| (loadouts[i][k] as u32) << (3 * k)).sum() };
    // configurazione della partita registrata: serve solo al testbench
    write(
        "trace_config.vh",
        &format!(
            "// Generato da paddws-trace: partita della traccia.\n\
             localparam signed [31:0] P_SEED = {};\n\
             localparam signed [31:0] P_PLAYERS = {};\n\
             localparam signed [31:0] P_EVO = {};\n\
             localparam signed [31:0] P_DIFFICULTY = {};\n\
             localparam signed [31:0] P_NEXT = {};\n\
             localparam [8:0] P_LOADOUT0 = 9'd{};\n\
             localparam [8:0] P_LOADOUT1 = 9'd{};\n\
             localparam [3:0] P_CPU_LEVEL1 = 4'd{};   // livello della CPU di destra\n\
             localparam [5:0] P_KINDS = 6'd{};   // tipi di racchetta, 3 bit per lato (7 = senza tipo)\n\
             localparam signed [31:0] P_SUPERS = {};   // mosse speciali: input a 40 bit e 2 parole di stato in coda\n\
             // per il firmware del core (paddws-fw-sim, sim/rv/tb_rv)\n\
             localparam signed [31:0] P_TICK_HZ = {};\n\
             localparam [1:0] P_CPU_SIDES = 2'd{};   // lati giocati dalla CPU Rust: bit 0 sinistra, 1 destra\n\
             localparam [3:0] P_CPU_LEVEL0 = 4'd{};   // livello della CPU di sinistra\n\
             localparam [3:0] P_CONTROL = 4'd{};   // comandi delle CPU, 2 bit per lato: 0 joystick, 1 spinner, 2 tastiera\n",
            a.seed,
            if a.next { 2 } else { a.players },
            (a.evo && !a.next) as u8,
            a.difficulty,
            a.next as u8,
            loadout_code(0),
            loadout_code(1),
            a.cpu_level.unwrap_or(a.difficulty),
            a.paddles[0].map_or(7, |k| k as u32) | a.paddles[1].map_or(7, |k| k as u32) << 3,
            a.supers as u8,
            a.tick_hz,
            if a.next || a.cpu_play { 3 } else { 0 },
            a.difficulty,
            control_code(a.control[0]) | control_code(a.control[1]) << 2
        ),
    );
    write("trace_input.hex", &inputs);
    write("trace_state.hex", &states);
    println!(
        "{} tick, eventi: muro {} colpi {} boost {} punti {} capsule {} bonus {} super {} teleport {} spari {} barriera {}{} - punteggio finale {}-{} -> {}",
        a.ticks,
        counts[0],
        counts[1],
        counts[2],
        counts[3],
        counts[4],
        counts[5],
        counts[6],
        counts[7],
        counts[8],
        counts[9],
        if a.supers {
            format!(
                " straight {} rising {} colpi speciali {}",
                counts[10], counts[11], counts[12]
            )
        } else {
            String::new()
        },
        game.score[0],
        game.score[1],
        a.out.display()
    );
}
