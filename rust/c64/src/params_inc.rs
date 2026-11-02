//! Parametri della versione C64 come costanti ca65 (`c64/gen/params.inc`), da `Params::new` con
//! `Tuning::c64()`: tutto è in Fx (Q16.16) o in tick a 50 Hz. Le grandezze che dipendono dalla
//! difficoltà sono tabelle di 4 valori.

use std::fmt::Write as _;

use paddws_core::{CPU_LEVELS, CpuLevel, DIFFICULTY_LEVELS, Params, Tuning};

/// Parametri del C64 alla difficoltà `d`.
pub fn c64_params(d: u8) -> Params {
    Params::new(&Tuning {
        difficulty: d,
        ..Tuning::c64()
    })
}

fn hex(v: i32) -> String {
    format!("${:08X}", v as u32)
}

/// Tabella di valori a 32 bit (esadecimali) come `.define` per `.dword`.
fn table(s: &mut String, name: &str, values: &[i32], note: &str) {
    let list: Vec<String> = values.iter().map(|v| hex(*v)).collect();
    let _ = writeln!(s, "; {note}");
    let _ = writeln!(s, ".define {name} {}", list.join(", "));
}

/// Tabella di valori piccoli (decimali) come `.define` per `.byte`.
fn bytes(s: &mut String, name: &str, values: &[i32], note: &str) {
    let list: Vec<String> = values.iter().map(|v| v.to_string()).collect();
    let _ = writeln!(s, "; {note}");
    let _ = writeln!(s, ".define {name} {}", list.join(", "));
}

/// Testo di `params.inc`.
pub fn params_inc() -> String {
    let p = c64_params(1);
    // a parte le tabelle per difficoltà, i parametri non devono cambiare con la difficoltà
    for d in 0..DIFFICULTY_LEVELS {
        let mut q = c64_params(d);
        q.max_ball_speed_1p = p.max_ball_speed_1p;
        q.max_ball_speed_2p = p.max_ball_speed_2p;
        q.kspeed_1p = p.kspeed_1p;
        q.kspeed_2p = p.kspeed_2p;
        q.kspeed_next = p.kspeed_next;
        q.max_ball_speed_next = p.max_ball_speed_next;
        assert_eq!(q, p, "un parametro dipende dalla difficoltà");
    }
    let mut s = String::new();
    let _ = writeln!(s, "; Generato da paddws-c64 params (rust/c64): non modificare a mano.");
    let _ = writeln!(
        s,
        "; Parametri del core Rust con Tuning::c64(): Fx Q16.16, reciproci Q8.24, tick a {} Hz.",
        p.tick_hz
    );
    let mut c = |name: &str, v: i32, note: &str| {
        let _ = writeln!(s, "{name:<22} = {:<11} ; {note}", hex(v));
    };
    c("P_TICK_HZ", p.tick_hz as i32, "tick al secondo");
    c("P_WIDTH", p.width, "campo");
    c("P_HEIGHT", p.height, "");
    c("P_BALL_R", p.ball_radius, "raggio della palla");
    c("P_BALL_R_BOOST", p.ball_radius_boost, "con il boost EVO");
    c("P_BALL_R_FWD", p.ball_radius_boost_fwd, "con il boost dello scatto");
    c("P_SERVE_UNIT", p.serve_unit, "velocità unitaria della battuta");
    c("P_SERVE_TICKS", p.serve_ticks as i32, "attesa della battuta");
    c("P_PAD_HALF_W", p.pad_width / 2, "metà larghezza della racchetta");
    c("P_PAD_H", p.pad_height, "altezza della racchetta");
    c("P_PAD_START", p.pad_start_pos, "x della racchetta sinistra a casa");
    c("P_PAD_FWD", p.pad_fwd_pos, "x della racchetta sinistra avanzata");
    c("P_PAD_MAX", p.pad_max_speed, "velocità massima");
    c("P_PAD_ACC", p.pad_acceleration, "accelerazione");
    c("P_PAD_FACC", p.pad_fast_acceleration, "accelerazione rapida");
    c("P_PAD_DECEL", p.pad_deceleration, "frenata");
    c("P_PAD_STOP", p.pad_stop_speed, "sotto questa velocità si ferma");
    c("P_PAD_INV_HALF", p.pad_inv_half_height, "Q8.24: 1 / metà altezza");
    c(
        "P_WALL_INV_HALF",
        p.wall_inv_half_height,
        "Q8.24: 1 / metà altezza del muro",
    );
    c("P_BOOST_MUL", p.boost_mul, "boost EVO");
    c("P_BOOST_FWD_MUL", p.boost_fwd_mul, "boost dello scatto");
    c("P_BOOST_LEVELS", p.boost_levels as i32, "livelli dell'area boost");
    let levels = p.boost_levels as usize;
    table(
        &mut s,
        "T_BOOST_H",
        &p.boost_heights[..levels],
        "altezza dell'area boost per livello",
    );
    table(
        &mut s,
        "T_BOOST_INV",
        &p.boost_inv_half[..levels],
        "Q8.24: 1 / metà altezza dell'area boost per livello",
    );
    let by_d = |f: fn(&Params) -> i32| -> Vec<i32> { (0..DIFFICULTY_LEVELS).map(|d| f(&c64_params(d))).collect() };
    table(
        &mut s,
        "T_KSPEED_1P",
        &by_d(|p| p.kspeed_1p),
        "accelerazione della palla a ogni colpo, singolo, per difficoltà",
    );
    table(
        &mut s,
        "T_MAX_1P",
        &by_d(|p| p.max_ball_speed_1p),
        "velocità massima della palla, singolo",
    );
    table(&mut s, "T_KSPEED_2P", &by_d(|p| p.kspeed_2p), "in due");
    table(&mut s, "T_MAX_2P", &by_d(|p| p.max_ball_speed_2p), "");
    table(&mut s, "T_KSPEED_NEXT", &by_d(|p| p.kspeed_next), "NEXT");
    table(&mut s, "T_MAX_NEXT", &by_d(|p| p.max_ball_speed_next), "");

    // NEXT: capsule, bonus, tipi di racchetta (in tick a 50 Hz e Fx)
    assert!(!p.blaster_dash, "sul C64 il BLASTER spara con il tasto dello scatto");
    let _ = writeln!(s, "; NEXT");
    for (name, v, note) in [
        ("P_CAP_HALF", p.capsule_half, "metà lato della capsula"),
        ("P_CAP_SPEED", p.capsule_speed, "velocità orizzontale della capsula"),
        ("P_CAP_DRIFT", p.capsule_drift, "deriva verticale"),
        (
            "P_CAP_MARGIN",
            p.capsule_margin_top,
            "fascia in alto senza capsule (riserve)",
        ),
        ("P_SPAWN_TICKS", p.spawn_ticks as i32, "tick tra due capsule"),
        ("P_SPAWN_JITTER", p.spawn_jitter as i32, "più una parte casuale"),
        ("P_SUPER_ODDS", p.super_odds as i32, "una capsula su N è SUPER"),
        (
            "P_SUPER_CUT",
            p.super_cut as i32,
            "capsula: 16 bit casuali sotto questo valore = SUPER",
        ),
        ("P_BULLET_CUT", p.bullet_cut as i32, "sotto questo = BULLET, sopra = bonus scelto"),
        ("P_BULLET_RAMP", p.bullet_ramp_ticks as i32, "rampa di entrata del BULLET, dallo scatto"),
        ("P_BULLET_ZONE", p.bullet_zone, "BULLET: scatta con la palla nella metà campo di chi lo attiva"),
        ("P_BULLET_SHIFT", p.bullet_shift as i32, "passo v - (v >> shift) dopo la rampa"),
        ("P_BULLET_RSHIFT", p.bullet_ramp_shift as i32, "e nella rampa"),
        (
            "P_ENC_HAND_STEP",
            p.encoder_hand_step,
            "passo dell'encoder prima del rallentamento",
        ),
        ("P_SLOW_TICKS", p.slow_ticks as i32, "alone di SLOW"),
        ("P_COOLDOWN", p.bonus_cooldown_ticks as i32, "pausa tra due bonus"),
        ("P_HITSTOP", p.hitstop_ticks as i32, "fermo del SUPER con hit-stop"),
        ("P_SMASH_MUL", p.smash_mul, ""),
        ("P_SLOW_MUL", p.slow_mul, ""),
        ("P_SLOW_BACK", p.slow_back, "SLOW: al colpo di chi l'ha usato (inverso di P_SLOW_MUL)"),
        ("P_SUPER_MUL", p.super_mul, ""),
        ("P_CURVE_ACCEL", p.curve_accel, ""),
        ("P_STEER_ACCEL", p.steer_accel, ""),
        (
            "P_ARCADE_COOLDOWN",
            p.arcade_cooldown_ticks as i32,
            "ARCADE: pausa tra due bonus",
        ),
        (
            "P_ARCADE_SPAWN",
            p.arcade_spawn_ticks as i32,
            "ARCADE: tick tra due capsule",
        ),
        (
            "P_ARCADE_SHARE",
            p.arcade_share as i32,
            "ARCADE: capsule su 3 che vanno a lui",
        ),
        ("P_HAMMER_MUL", p.hammer_mul, ""),
        ("P_RUSH_MUL", p.rush_mul, "RUSH: tiro dalla posizione avanzata"),
        ("P_TWIST_TRANSFER", p.twist_transfer, ""),
        ("P_BLASTER_SHOTS", p.blaster_shots as i32, "colpi del caricatore"),
        ("P_BLASTER_GAP", p.blaster_gap_ticks as i32, "pausa tra due colpi"),
        (
            "P_BLASTER_RELOAD",
            p.blaster_reload_ticks as i32,
            "ricarica dal primo colpo",
        ),
        ("P_SHOT_SPEED", p.blaster_shot_speed, ""),
        ("P_BLASTER_BAND", p.blaster_band, "metà della fascia dei due colpi"),
        (
            "P_BARRIER_X",
            p.guardian_barrier_x,
            "GUARDIAN: x della barriera (lato sinistro)",
        ),
        (
            "P_PAD_MAX_SPEED",
            p.pad_max_speed,
            "velocità massima della racchetta (grafica di TWIST)",
        ),
        ("P_GUARDIAN_X", p.guardian_barrier_x, "barriera dal bordo"),
        ("P_GUARDIAN_TOP", p.guardian_top, "inizio del muro (sotto la banda delle riserve)"),
        ("P_GUARDIAN_B1", p.guardian_bounds[0], "confini tra i settori del muro"),
        ("P_GUARDIAN_B2", p.guardian_bounds[1], ""),
        ("P_GUARDIAN_B3", p.guardian_bounds[2], ""),
        ("P_GUARDIAN_B4", p.guardian_bounds[3], ""),
        (
            "P_SUPER_METER_MAX",
            p.super_meter_max as i32,
            "mosse speciali: barra piena (unità intere)",
        ),
        ("P_SUPER_COST", p.super_cost as i32, "costo di una mossa (un settore)"),
        ("P_SUPER_GAIN_HIT", p.super_gain_hit as i32, "barra: a ogni colpo"),
        (
            "P_SUPER_GAIN_DASH",
            p.super_gain_dash as i32,
            "con lo scatto che intercetta la palla",
        ),
        (
            "P_SUPER_GAIN_CONCEDED",
            p.super_gain_conceded as i32,
            "per un punto subito",
        ),
        (
            "P_SUPER_STRAIGHT_SHIFT",
            p.super_straight_shift as i32,
            "STRAIGHT SHOT: boost += boost >> (shift + 2 - livello)",
        ),
        (
            "P_GHOST_PERIOD",
            p.ghost_period as i32,
            "GHOST: si vede ghost_visible tick ogni ghost_period",
        ),
        ("P_GHOST_VISIBLE", p.ghost_visible as i32, ""),
    ] {
        let _ = writeln!(s, "{name:<22} = {:<11} ; {note}", hex(v));
    }
    // tipi di racchetta 0-6 come PaddleKind, 7 = senza tipo (la racchetta normale)
    let plain = paddws_core::PaddleParams {
        height: p.pad_height,
        inv_half_height: p.pad_inv_half_height,
        max_speed: p.pad_max_speed,
        acceleration: p.pad_acceleration,
        fast_acceleration: p.pad_fast_acceleration,
        fwd_pos: p.pad_fwd_pos,
        fwd_max_speed: p.pad_max_speed,
        fwd_acceleration: p.pad_acceleration,
        fwd_fast_acceleration: p.pad_fast_acceleration,
        encoder_step: 0,
    };
    let kinds: Vec<paddws_core::PaddleParams> = p.kinds.iter().copied().chain([plain]).collect();
    type KindField = fn(&paddws_core::PaddleParams) -> i32;
    for (name, f, note) in [
        (
            "T_KIND_H",
            (|k| k.height) as KindField,
            "tipi di racchetta (0-6, 7 senza tipo): altezza",
        ),
        ("T_KIND_INV", |k| k.inv_half_height, "Q8.24: 1 / metà altezza"),
        ("T_KIND_MAX", |k| k.max_speed, "velocità massima e accelerazioni"),
        ("T_KIND_ACC", |k| k.acceleration, ""),
        ("T_KIND_FACC", |k| k.fast_acceleration, ""),
        (
            "T_KIND_FWD",
            |k| k.fwd_pos,
            "x dello scatto in avanti (racchetta sinistra)",
        ),
        ("T_KIND_FMAX", |k| k.fwd_max_speed, "con la racchetta avanzata"),
        ("T_KIND_FWACC", |k| k.fwd_acceleration, ""),
        ("T_KIND_FWFACC", |k| k.fwd_fast_acceleration, ""),
        (
            "T_KIND_STEP",
            |k| k.encoder_step,
            "spostamento massimo con l'encoder (0 = nessun limite)",
        ),
    ] {
        table(&mut s, name, &kinds.iter().map(f).collect::<Vec<_>>(), note);
    }

    // CPU: livelli 0-3 della difficoltà e 4-10 di CHALLENGE; i reciproci della velocità massima
    // della palla dipendono dalla difficoltà della partita, il resto no
    let levels: Vec<CpuLevel> = (0..CPU_LEVELS).map(|l| CpuLevel::new(&p, l)).collect();
    for d in 0..DIFFICULTY_LEVELS {
        for l in 0..CPU_LEVELS {
            let mut q = CpuLevel::new(&c64_params(d), l);
            q.inv_speed = levels[l as usize].inv_speed;
            q.inv_speed_next = levels[l as usize].inv_speed_next;
            assert_eq!(q, levels[l as usize], "un valore della CPU dipende dalla difficoltà");
        }
    }
    assert!(
        p.predict_step == 1 && p.arrival_step == 1,
        "il C64 prevede a passi di un tick"
    );
    let _ = writeln!(
        s,
        "; CPU: previsione del punto d'arrivo a passi di un tick, al massimo:"
    );
    let _ = writeln!(s, "{:<22} = {}", "P_PREDICT_MAX", p.predict_max);
    let _ = writeln!(s, "{:<22} = {}", "P_ARRIVAL_MAX", p.arrival_max);
    let _ = writeln!(s, "{:<22} = {}", "P_CPU_LEVELS", CPU_LEVELS);
    let _ = writeln!(
        s,
        "{:<22} = {}   ; tick da avanzata, palla che si allontana, prima di tornare",
        "P_CPU_RETURN", levels[0].return_ticks
    );
    let _ = writeln!(
        s,
        "{:<22} = {}   ; BULLET con la palla a meno di |dx| << shift",
        "P_CPU_BULLET_SHIFT", levels[0].bullet_shift
    );
    let col = |f: fn(&CpuLevel) -> i32| -> Vec<i32> { levels.iter().map(f).collect() };
    for (name, f, note) in [
        (
            "T_CPU_REACTION",
            (|l: &CpuLevel| l.reaction_ticks as i32) as fn(&CpuLevel) -> i32,
            "tempo di reazione (tick)",
        ),
        ("T_CPU_FAST", |l| l.fast as i32, "usa il rapido"),
        ("T_CPU_PREDICT", |l| l.predict as i32, "prevede il punto d'arrivo"),
        (
            "T_CPU_FWD_ODDS",
            |l| l.forward_odds as i32,
            "scatto: una probabilità su N per tick (0 = mai)",
        ),
        (
            "T_CPU_BONUS_ODDS",
            |l| l.bonus_odds as i32,
            "NEXT: bonus, una probabilità su N per tick",
        ),
    ] {
        let v = col(f);
        assert!(v.iter().all(|&x| (0..256).contains(&x)), "{name}: valori oltre il byte");
        bytes(&mut s, name, &v, note);
    }
    table(
        &mut s,
        "T_CPU_MISS",
        &col(|l| l.miss_permille as i32),
        "CPU per livello: palle mancate apposta, per mille",
    );
    table(
        &mut s,
        "T_CPU_MAX_ERROR",
        &col(|l| l.max_error),
        "errore di mira massimo",
    );
    table(&mut s, "T_CPU_REACT", &col(|l| l.react), "distanza entro cui reagisce");
    table(
        &mut s,
        "T_CPU_INV_SPEED",
        &(0..DIFFICULTY_LEVELS)
            .map(|d| CpuLevel::new(&c64_params(d), 0).inv_speed)
            .collect::<Vec<_>>(),
        "Q8.24: 1 / velocità massima della palla in Classic ed EVO, per difficoltà",
    );
    table(
        &mut s,
        "T_CPU_INV_SPEED_NEXT",
        &(0..DIFFICULTY_LEVELS)
            .map(|d| CpuLevel::new(&c64_params(d), 0).inv_speed_next)
            .collect::<Vec<_>>(),
        "in NEXT",
    );
    challenge(&mut s);
    s
}

/// CHALLENGE: livelli (avversario, CPU, velocità, bonus, punti), punti arcade e classifica
/// iniziale, da `paddws_core::challenge`.
fn challenge(s: &mut String) {
    use paddws_core::challenge::{self as ch, RUNGS};
    let _ = writeln!(s, "; CHALLENGE (rust/core/src/challenge.rs)");
    for (name, v) in [
        ("CH_LEVELS", ch::LEVELS as u32),
        ("CH_HIT", ch::HIT_POINTS),
        ("CH_BOOST", ch::BOOST_POINTS),
        ("CH_SUPER", ch::SUPER_POINTS),
        ("CH_POINT", ch::POINT_POINTS),
        ("CH_WIN", ch::WIN_POINTS),
        ("CH_PERFECT", ch::PERFECT_POINTS),
        ("CH_RALLY_STEP", ch::RALLY_STEP as u32),
        ("CH_MAX_MULT", ch::MAX_MULTIPLIER),
        ("CH_TABLE", ch::TABLE_SIZE as u32),
    ] {
        let _ = writeln!(s, "{name:<22} = {v}");
    }
    let col = |f: fn(&ch::Rung) -> i32| RUNGS.iter().map(f).collect::<Vec<i32>>();
    bytes(
        s,
        "T_RUNG_KIND",
        &col(|r| r.kind as i32),
        "livelli: racchetta della CPU",
    );
    bytes(s, "T_RUNG_CPU", &col(|r| r.cpu as i32), "livello della CPU");
    bytes(
        s,
        "T_RUNG_SPEED",
        &col(|r| r.speed as i32),
        "velocità della palla (difficoltà con NORMAL)",
    );
    bytes(s, "T_RUNG_POINTS", &col(|r| r.points as i32), "punti per vincere");
    let lo: Vec<i32> = RUNGS.iter().flat_map(|r| r.loadout.map(|b| b as i32)).collect();
    bytes(s, "T_RUNG_LOADOUT", &lo, "bonus della CPU, 3 per livello");
    // classifica iniziale: per riga iniziali (3), punti (4, byte basso per primo), livello
    let t = ch::Table::default();
    let rows: Vec<i32> = t
        .entries
        .iter()
        .flat_map(|e| {
            let mut v: Vec<i32> = e.name.iter().map(|&c| c as i32).collect();
            v.extend(e.score.to_le_bytes().map(|b| b as i32));
            v.push(e.level as i32);
            v
        })
        .collect();
    bytes(
        s,
        "T_TABLE",
        &rows,
        "classifica iniziale: iniziali, punti (4 byte), livello",
    );
}
