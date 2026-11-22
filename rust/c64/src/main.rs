//! paddws-c64: verifica il programma C64 (c64/build/paddws.prg) contro il core Rust.
//!
//! Uso:  paddws-c64 [--build DIR] math [PROVE]       aritmetica e generatore contro fixed.rs e rng.rs
//!       paddws-c64 [--build DIR] game [--ticks N]   partite intere, stato confrontato a ogni tick
//!       paddws-c64 [--build DIR] sid                player del SID contro quello Verilog
//!       paddws-c64 [--build DIR] ui                 scene e menu: nessun ciclo infinito
//!       paddws-c64 [--build DIR] frames             cicli di ogni frame (attract, partita)
//!       paddws-c64 params [--check]                 scrive (o controlla) c64/gen/params.inc

use std::collections::HashMap;
use std::path::PathBuf;
use std::process::ExitCode;

use paddws_c64::params_inc::{c64_params, params_inc};
use paddws_c64::cpu6502::{EF_HALF, EF_OFF, EasyFlash};
use paddws_c64::{Machine, c64_dir, default_build_dir, frame_budget, ntsc, set_ntsc};
use paddws_core::fixed::{self, mul, mul_recip};
use paddws_core::challenge::{OMEGA, OMEGA_LEVEL, RUNGS, Score, TABLE_SIZE, Table};
use paddws_core::{Bonus, Cpu, Input, Match, PaddleKind, PlayerInput, Rng, Side, Special};

const USAGE: &str =
    "Uso: paddws-c64 [--ntsc] [--build DIR] math [PROVE] | game [--ticks N] | sid | ui | frames | ending | profile | paddles | params [--check]";

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let mut build = None;
    let mut command = Vec::new();
    while let Some(a) = args.next() {
        match a.as_str() {
            "--build" => build = Some(PathBuf::from(args.next().unwrap_or_default())),
            // la versione NTSC: parametri a 60 Hz, c64/build/ntsc, budget e raster NTSC
            "--ntsc" => set_ntsc(true),
            "-h" | "--help" => {
                println!("{USAGE}");
                return ExitCode::SUCCESS;
            }
            _ => command.push(a),
        }
    }
    let build = build.unwrap_or_else(default_build_dir);
    let ok = match command.first().map(String::as_str) {
        Some("params") => params(command.iter().any(|a| a == "--check")),
        Some("math") => with_machine(&build, |m| {
            math(m, command.get(1).and_then(|n| n.parse().ok()).unwrap_or(100_000))
        }),
        Some("sid") => with_machine(&build, sid),
        Some("ui") => with_machine(&build, ui),
        Some("frames") => with_machine(&build, |m| {
            let ok = frames(m);
            print_heavy(m);
            ok
        }),
        Some("ending") => with_machine(&build, ending_alone),
        Some("profile") => with_machine(&build, profile),
        Some("paddles") => with_machine(&build, paddles),
        Some("game") => {
            let ticks = command
                .iter()
                .position(|a| a == "--ticks")
                .and_then(|i| command.get(i + 1))
                .and_then(|n| n.parse().ok())
                .unwrap_or(50 * 60 * 5);
            with_machine(&build, |m| game(m, ticks))
        }
        _ => {
            eprintln!("{USAGE}");
            false
        }
    };
    if ok { ExitCode::SUCCESS } else { ExitCode::FAILURE }
}

fn with_machine(build: &std::path::Path, f: impl FnOnce(&mut Machine) -> bool) -> bool {
    match Machine::load(build) {
        Ok(mut m) => f(&mut m),
        Err(e) => {
            eprintln!("{e}");
            false
        }
    }
}

/// Scene e menu: ogni routine di avvio, attract, menu e partita deve tornare entro un
/// milione di cicli (nessun ciclo infinito), anche frame dopo frame e con tutti i valori del menu.
fn ui(m: &mut Machine) -> bool {
    let run = |m: &mut Machine, name: &str, x: u8, times: u32| -> Result<u64, String> {
        let mut worst = 0;
        for _ in 0..times {
            m.cpu.x = x;
            let addr = m.addr(name);
            worst = worst.max(m.cpu.call(addr, 1_000_000).map_err(|e| format!("{name}: {e}"))?);
        }
        Ok(worst)
    };
    // il titolo compresso, decompresso sotto l'I/O, deve essere identico a title.bin
    let cycles = m.call("title_unpack");
    let title = std::fs::read(c64_dir().join("gen/title.bin")).unwrap_or_default();
    let buf = 0x800; // TITLE_BUF in c64/src/unpack.s ($D800), nella RAM sotto l'I/O
    if title.is_empty() || m.cpu.under_io[buf..buf + title.len()] != title[..] {
        println!("FAIL: title_unpack non dà title.bin");
        return false;
    }
    println!("  title_unpack     x1    cicli max {cycles} ({} byte)", title.len());
    m.call("clear_vars");
    let steps: &[(&str, u8, u32)] = &[
        ("math_init", 0, 1),
        ("video_init", 0, 1),
        ("input_init", 0, 1),
        ("sid_init", 0, 1),
        ("boot_enter", 0, 1),
        ("boot_frame", 0, 260),
        ("go_stripes", 0, 1),
        ("stripes_frame", 0, 130),
        ("logo_enter", 0, 1),
        ("logo_frame", 0, 120),
        ("title_enter", 0, 1),
        ("title_frame", 0, 420),
        ("enter_menu", 0, 1),
        ("draw_menu", 0, 1),
        ("start_game", 0, 1),
        ("compute_sprites", 0, 1),
        ("enter_over", 0, 1),
        ("apply_shadows", 0, 1),
    ];
    for &(name, x, times) in steps {
        match run(m, name, x, times) {
            Ok(c) => println!("  {name:<16} x{times:<4} cicli max {c}"),
            Err(e) => {
                println!("FAIL: {e}");
                return false;
            }
        }
    }
    // il font e le lettere 2x dalla ROM dei caratteri (video_init)
    if let Err(e) = check_glyphs(m, &program_glyphs(m), "dopo l'avvio") {
        println!("FAIL: {e}");
        return false;
    }
    println!("  video_init: font 1x e lettere 2x dalla ROM dei caratteri (finta)");
    // la tendina del logo scopre le righe man mano: a metà, circa metà del logo
    m.call("logo_enter");
    for _ in 0..35 {
        m.call("logo_frame");
    }
    let shown = m.read_u8("at_shown", 0);
    if !(20..=30).contains(&shown) {
        println!("FAIL: dopo 35 frame del logo {shown} righe scoperte invece di circa 25");
        return false;
    }
    // tutte le voci del menu, avanti e indietro (il codice del menu dalla cartuccia: lì c'è stato
    // il GAME OVER)
    m.call("enter_menu");
    for sel in 0..9u8 {
        for dir in [1u8, 0xFF] {
            for _ in 0..4 {
                m.write_u8("menu_sel", 0, sel);
                m.cpu.a = dir;
                if let Err(e) = run(m, "change_value", 0, 1).and_then(|_| run(m, "draw_menu", 0, 1)) {
                    println!("FAIL: voce {sel}: {e}");
                    return false;
                }
            }
        }
    }
    if let Err(e) = volume_ui(m) {
        println!("FAIL: VOLUME: {e}");
        return false;
    }
    // joystick del giocatore sinistro (porta 2): verso l'avversario (destra) lo scatto con la
    // racchetta a casa, dalla parte opposta il rientro con la racchetta avanzata, altrimenti niente
    let forward = |m: &mut Machine, joy: u8| -> bool {
        m.cpu.joy_port2 = 0xFF;
        m.call("read_input");
        m.cpu.joy_port2 = joy;
        m.call("read_input");
        m.call("build_input");
        m.cpu.joy_port2 = 0xFF;
        m.read_u8("in_flags", 0) & 0x02 != 0 // IN_FORWARD
    };
    m.write_u8("ctl_paddle", 0, 0);
    let home = m.read_i32("pad_home", 0);
    for (at_home, joy, want, what) in [
        (true, !0x08u8, true, "a casa, verso l'avversario: scatto"),
        (false, !0x08, false, "avanti, verso l'avversario: niente"),
        (false, !0x04, true, "avanti, dalla parte opposta: rientro"),
        (true, !0x04, false, "a casa, dalla parte opposta: niente"),
    ] {
        m.write_i32("pad_x", 0, if at_home { home } else { home + 0x0004_0000 });
        if forward(m, joy) != want {
            println!("FAIL: joystick, {what}");
            return false;
        }
    }
    m.write_i32("pad_x", 0, home);
    println!("  joystick: scatto verso l'avversario, rientro dalla parte opposta");
    // immagini preparate delle racchette di NEXT (pad_prep), per ogni tipo e tutti e due i lati:
    // vanno nei loro sprite e lasciano com'erano i due schermi ($C000-$C7FF)
    let screens: Vec<u8> = m.cpu.mem[0xC000..0xC800].to_vec();
    m.write_u8("nx_morph", 0, 0xFF); // (nessun OMEGA)
    for kind in 0..7u8 {
        for side in 0..2u16 {
            m.write_u8("nx_kind", side * 4, kind);
            m.write_u8("pd_cur_n", side, 17);
        }
        m.write_u8("pp_side", 0, 0);
        m.write_u8("pp_var", 0, 0);
        let first = 0xC000 + m.read_u8("prep_base", 0) as usize * 64;
        m.cpu.mem[first..first + 14 * 64].fill(0);
        for _ in 0..40 {
            if m.read_u8("pp_side", 0) >= 2 {
                break;
            }
            m.cpu.frame_start = Some(m.cpu.cycles); // inizio del frame: c'è tempo
            m.write_u8("pd_made", 0, 0); // (nessuna immagine dinamica in questo frame)
            m.call("pad_prep");
            m.cpu.frame_start = None;
        }
        if m.read_u8("pp_side", 0) < 2 {
            println!("FAIL: pad_prep non finisce con il tipo {kind}");
            return false;
        }
        if m.cpu.mem[0xC000..0xC800] != screens[..] {
            println!("FAIL: pad_prep con il tipo {kind} scrive negli schermi");
            return false;
        }
        for side in 0..2u16 {
            for var in 0..m.read_u8("prep_count", kind as u16) as usize {
                let slot = m.read_u8("prep_base", side) as usize + var;
                let a = 0xC000 + slot * 64;
                if m.cpu.mem[a..a + 63].iter().all(|&b| b == 0) {
                    println!("FAIL: pad_prep con il tipo {kind}: immagine {var} del lato {side} vuota");
                    return false;
                }
            }
        }
    }
    // contro OMEGA (a destra): per il suo lato le 7 forme dritte, le 6 altre inclinazioni della
    // TWIST e i caricatori non pieni del BLASTER (om_slot di video.s, nel codice delle mosse
    // speciali, qui rimesso come in partita); a sinistra il tipo del giocatore
    let sm = m.moved_segment("SMCODE").map(|(a, b)| (a, b.to_vec()));
    let saved_sm = sm.as_ref().map(|(a, b)| m.cpu.mem[*a as usize..*a as usize + b.len()].to_vec());
    if let Some((a, b)) = &sm {
        m.cpu.load(*a, b);
    }
    let screens2: Vec<u8> = m.cpu.mem[0xC000..0xC800].to_vec();
    m.write_u8("nx_morph", 0, 4);
    m.write_u8("nx_kind", 0, 3);
    m.write_u8("pp_side", 0, 0);
    m.write_u8("pp_var", 0, 0);
    let first = 0xC000 + m.read_u8("prep_base", 0) as usize * 64;
    m.cpu.mem[first..first + 30 * 64].fill(0);
    let omx = m.read_u8("prep_base", 0) as usize + 14 + 21; // SP_OMX
    m.cpu.mem[0xC000 + omx * 64..0xC000 + (omx + 3) * 64].fill(0);
    for _ in 0..60 {
        if m.read_u8("pp_side", 0) >= 2 {
            break;
        }
        m.cpu.frame_start = Some(m.cpu.cycles);
        m.write_u8("pd_made", 0, 0);
        m.call("pad_prep");
        m.cpu.frame_start = None;
    }
    let spin = m.read_u8("prep_base", 0) as usize + 14;
    let mut slots: Vec<usize> = (0..7).map(|k| m.read_u8("prep_base", 1) as usize + k).collect();
    slots.extend([0, 1, 2, 4, 5, 6, 7].iter().map(|i| spin + 8 + i));
    slots.extend(omx..omx + 3);
    let empty: Vec<usize> = slots.iter().copied().filter(|&sl| m.cpu.mem[0xC000 + sl * 64..0xC000 + sl * 64 + 63].iter().all(|&b| b == 0)).collect();
    let omega_ok = m.read_u8("pp_side", 0) >= 2 && empty.is_empty() && m.cpu.mem[0xC000..0xC800] == screens2[..];
    if let (Some((a, _)), Some(b)) = (&sm, &saved_sm) {
        m.cpu.load(*a, b);
    }
    m.write_u8("nx_morph", 0, 0xFF); // (poi partite NEXT senza OMEGA, come dopo match_new)
    if !omega_ok {
        println!("FAIL: pad_prep contro OMEGA: lato {} alla fine, sprite vuoti {empty:?} (o schermi cambiati)", m.read_u8("pp_side", 0));
        return false;
    }
    println!("  pad_prep: immagini preparate di tutti i tipi al loro posto; contro OMEGA 7 forme, 6 inclinazioni della TWIST e 4 caricatori del BLASTER");
    match voice(m) {
        Ok(n) => println!("  voci di CHALLENGE: senza file niente; una scala con i 7 file: {n} campioni in $D418 nell'ordine (nomi, READY al primo frame del conto, GO al via; al 50% del VOLUME scalati, a 0 nessuna voce), tema a $F800"),
        Err(e) => {
            println!("FAIL: voce di CHALLENGE: {e}");
            return false;
        }
    }
    match pick_chars_ui(m) {
        Ok(s) => println!("  {s}"),
        Err(e) => {
            println!("FAIL: pick_chars: {e}");
            return false;
        }
    }
    match hiscore(m) {
        Ok(s) => println!("  {s}"),
        Err(e) => {
            println!("FAIL: classifica nella flash: {e}");
            return false;
        }
    }
    if let Err(e) = challenger(m) {
        println!("FAIL: CHALLENGE, nuovo sfidante: {e}");
        return false;
    }
    println!("  CHALLENGE: entrata dello sfidante, sfida, cambio di lato, premio e iniziali del perdente");
    for (what, f) in [
        ("menu", next_menu_ui as fn(&mut Machine) -> Result<String, String>),
        ("duelli vinti di fila (WINS)", wins_ui),
        ("allenamento", training_ui),
        ("sblocco dell'allenamento", unlock_ui),
    ] {
        match f(m) {
            Ok(s) => println!("  {s}"),
            Err(e) => {
                println!("FAIL: {what}: {e}");
                return false;
            }
        }
    }
    match ending_ui(m) {
        Ok(s) => println!("  {s}"),
        Err(e) => {
            println!("FAIL: finale di CHALLENGE: {e}");
            return false;
        }
    }
    match perfect_ui(m) {
        Ok(s) => println!("  {s}"),
        Err(e) => {
            println!("FAIL: PERFECT nel GAME OVER: {e}");
            return false;
        }
    }
    // GHOST (Next::ball_hidden): palla nascosta nei tick in cui non si vede, e mai la coda, che la
    // tradirebbe; senza GHOST, con il boost, la coda c'è
    m.write_u8("m_next", 0, 1);
    m.write_u8("nx_morph", 0, 0xFF); // (una partita NEXT senza OMEGA: l'allenamento contro OMEGA prima)
    m.write_u8("sh_bg", 0, 0);
    m.write_i32("serve_timer", 0, 0x100);
    m.write_i32("ball_boost", 0, 0x18000);
    // fasi dai parametri (in tick: a 60 Hz più che a 50): la prima e l'ultima in cui si vede, la
    // prima e l'ultima in cui no
    let (visible, period) = (c64_params(1).ghost_visible as u8, c64_params(1).ghost_period as u8);
    for (ghost, phase, ball, trail) in [
        (1u8, 0u8, true, false),
        (1, visible - 1, true, false),
        (1, visible, false, false),
        (1, period - 1, false, false),
        (0, period / 2, true, true),
    ] {
        m.write_u8("nx_ghost", 0, ghost);
        m.write_u8("ghost_phase", 0, phase);
        m.write_u8("tr_want", 0, 0);
        m.call("compute_sprites");
        let (shown, wanted) = (m.read_u8("sh_enable", 0) & 1 != 0, m.read_u8("tr_want", 0) != 0);
        if (shown, wanted) != (ball, trail) {
            println!("FAIL: GHOST {ghost}, fase {phase}: palla {shown}, coda {wanted} invece di {ball}, {trail}");
            return false;
        }
    }
    println!("  GHOST: palla a lampi senza coda (la coda solo senza GHOST)");
    match supers_ui(m) {
        Ok(s) => println!("  {s}"),
        Err(e) => {
            println!("FAIL: mosse speciali: {e}");
            return false;
        }
    }
    match egg_ui(m) {
        Ok(s) => println!("  {s}"),
        Err(e) => {
            println!("FAIL: easter egg: {e}");
            return false;
        }
    }
    println!("PASS: scene e menu tornano tutte");
    true
}

/// Voce VOLUME del menu (play.s, sid.s): i passi da 0% a 100% con il giro dopo il 100%, il testo
/// del valore, il volume del SID (vol_levels) scritto subito in $D418, con il modo del filtro della
/// canzone se c'è.
fn volume_ui(m: &mut Machine) -> Result<(), String> {
    const LEVELS: [u8; 11] = [0, 1, 2, 3, 4, 5, 7, 8, 10, 12, 15];
    const MI_VOLUME: u8 = 6;
    let text = |m: &Machine| -> String { (0..4).map(|i| m.read_u8("vol_text", i) as char).collect() };
    m.write_u8("menu_sel", 0, MI_VOLUME);
    m.cpu.watch = Some((0xD418, 0xD418));
    for (rf, vm) in [(0u8, 0x1Fu8), (0xF1, 0x1F)] {
        m.write_u8("sid_rf", 0, rf);
        m.write_u8("sid_vm", 0, vm);
        m.write_u8("opt_volume", 0, 0);
        // giù dallo 0% resta 0%, poi su fino al 100% e il giro
        for (dir, step) in [(0xFFu8, 0u8)].into_iter().chain((1..=10).map(|s| (1, s))).chain([(1, 0)]) {
            m.cpu.writes.clear();
            m.cpu.a = dir;
            m.call("change_value");
            let (got, vol) = (m.read_u8("opt_volume", 0), m.read_u8("sid_vol", 0));
            if got != step || vol != LEVELS[step as usize] {
                return Err(format!("passo {got} (atteso {step}), volume del SID {vol}"));
            }
            let mode = if rf != 0 { vm & 0xF0 } else { 0 };
            if m.cpu.writes.last() != Some(&(0xD418, mode | vol)) {
                return Err(format!("passo {step}: $D418 {:?}", m.cpu.writes));
            }
            m.call("draw_menu");
            let want = format!("{:<4}", format!("{}%", 10 * step as u32));
            if text(m) != want {
                return Err(format!("passo {step}: testo {:?} invece di {want:?}", text(m)));
            }
        }
    }
    m.cpu.watch = None;
    m.cpu.writes.clear();
    m.write_u8("opt_volume", 0, 10);
    m.write_u8("sid_vol", 0, 15);
    Ok(())
}

/// Mosse speciali (supers.s) nel banco ui: il codice dalla cartuccia con sm_page (l'attract l'ha
/// coperto), nessuna voce del menu che le spenga, i gesti del joystick letti come in partita
/// (read_input, build_input) per tutti e due i giocatori, la scritta e la barra.
fn supers_ui(m: &mut Machine) -> Result<String, String> {
    // sempre accese: nessuna voce del menu le cambia (il menu gira dove poi vanno le mosse)
    m.call("enter_menu");
    m.write_u8("cfg_super", 0, 1);
    for sel in 0..9u8 {
        for dir in [1u8, 0xFF] {
            m.write_u8("menu_sel", 0, sel);
            m.cpu.a = dir;
            m.call("change_value");
        }
    }
    if m.read_u8("cfg_super", 0) != 1 {
        return Err("una voce del menu spegne le mosse speciali".into());
    }
    let (run, code) = m.moved_segment("SMCODE").map(|(a, c)| (a, c.to_vec())).ok_or("niente SMCODE")?;
    m.cpu.mem[run as usize..run as usize + code.len()].fill(0);
    let pages = code.len().div_ceil(256);
    for page in 0..pages {
        m.cpu.a = page as u8;
        m.call("sm_page");
    }
    if m.cpu.mem[run as usize..run as usize + code.len()] != code[..] {
        return Err("sm_page non copia il codice delle mosse dalla cartuccia".into());
    }
    // gesti: partita NEXT con le mosse, palla in gioco, niente di armato
    let (up, down, left, right, fire) = (0x01u8, 0x02u8, 0x04u8, 0x08u8, 0x10u8);
    m.write_u8("m_next", 0, 1);
    m.write_u8("sm_on", 0, 1);
    m.write_u8("ctl_paddle", 0, 0);
    m.write_i32("serve_timer", 0, 0);
    m.call("sm_init");
    m.cpu.write(0xDC00, 0xFF);
    m.cpu.write(0xDC01, 0xFF);
    let run_joy = |m: &mut Machine, side: usize, seq: &[u8], meter: u8| -> u8 {
        for o in [0u16, 4] {
            m.write_u8("sm_arm", o, 0);
            m.write_u8("nx_armed", o, 8);
            m.write_u8("sm_meter", o, meter);
        }
        let mut got = 0;
        for &bits in seq.iter().chain([0u8; 30].iter()) {
            let port = !bits;
            if side == 0 {
                m.cpu.joy_port2 = port;
            } else {
                m.cpu.joy_port1 = port;
            }
            m.call("read_input");
            m.call("build_input");
            if bits & fire != 0 {
                got = m.read_u8("in_flags", side as u16 * 4);
            }
        }
        m.cpu.joy_port1 = 0xFF;
        m.cpu.joy_port2 = 0xFF;
        got & 0x68 // IN_ACTIVATE, IN_STRAIGHT, IN_RISE
    };
    let (straight, rise, activate) = (0x20u8, 0x40u8, 0x08u8);
    let mut n = 0;
    for side in 0..2 {
        let fwd = if side == 0 { right } else { left };
        let back = if side == 0 { left } else { right };
        let hold = |dir: u8, frames: usize| vec![dir; frames];
        let qcf = [hold(down, 2), hold(down | fwd, 2), hold(fwd, 1), vec![fwd | fire]].concat();
        let dp = [hold(fwd, 2), hold(down, 2), hold(down | fwd, 1), vec![down | fwd | fire]].concat();
        let after_f = [hold(fwd, 2), qcf.clone()].concat();
        let slow = [hold(down, 2), hold(0, 20), hold(down | fwd, 2), hold(fwd, 1), vec![fwd | fire]].concat();
        let late = [hold(down, 2), hold(down | fwd, 2), hold(fwd, 2), hold(0, 16), vec![fire]].concat();
        let back_dir = [hold(down, 2), hold(down | back, 2), hold(back, 1), vec![back | fire]].concat();
        let up_dir = [hold(up, 2), hold(up | fwd, 2), hold(fwd, 1), vec![fwd | fire]].concat();
        for (seq, meter, want, what) in [
            (&qcf, 32, straight, "giù, giù-avanti, avanti + fuoco: STRAIGHT SHOT"),
            (&dp, 64, rise, "avanti, giù, giù-avanti + fuoco: RISING STRIKE"),
            (&after_f, 32, straight, "avanti, poi giù, giù-avanti, avanti + fuoco: STRAIGHT SHOT"),
            (&qcf, 31, activate, "gesto con la barra sotto il costo: il bonus"),
            (&dp, 0, activate, "gesto con la barra vuota: il bonus"),
            (&slow, 64, activate, "gesto troppo lento: il bonus"),
            (&late, 64, activate, "fuoco troppo tardi: il bonus"),
            (&back_dir, 64, activate, "mezzaluna all'indietro: il bonus"),
            (&up_dir, 64, activate, "mezzaluna in su: il bonus"),
        ] {
            let got = run_joy(m, side, seq, meter);
            if got != want {
                return Err(format!("giocatore {side}, {what}: comandi {got:#04x} invece di {want:#04x}"));
            }
            n += 1;
        }
    }
    // durante la battuta il gesto attiva il bonus
    let qcf = [vec![down; 2], vec![down | right; 2], vec![right], vec![right | fire]].concat();
    m.write_i32("serve_timer", 0, 10);
    let got = run_joy(m, 0, &qcf, 64);
    m.write_i32("serve_timer", 0, 0);
    if got != activate {
        return Err(format!("gesto durante la battuta: comandi {got:#04x}"));
    }
    let font = m.addr("font_map");
    let ch = |m: &Machine, c: u8| m.cpu.read(font + (c - 32) as u16);
    let inc = std::fs::read_to_string(c64_dir().join("gen/assets.inc")).unwrap_or_default();
    let solid = inc_const(&inc, "CH_SOLID").unwrap_or(0) as u8;
    // scritte delle mosse (sm_labels), nella metà di chi la fa, righe 4 (lettere) e 5 (trattini):
    // P2 arma una MAX RISING STRIKE con la palla a metà campo che va verso di lui, i trattini (due
    // righe: BAR_C0) arrivano dal suo lato e poi si accendono; al colpo i blocchi, la scritta gialla,
    // via dopo un secondo. P1 arma una mossa e la perde (punto): via i trattini.
    let bar_c0 = assets_supers().0;
    let frames = |m: &mut Machine, n: u32| {
        for _ in 0..n {
            m.cpu.frame_start = Some(m.cpu.cycles);
            m.call("sm_labels");
            m.cpu.frame_start = None;
        }
    };
    m.call("clear_screen");
    for (name, o, v) in [("sm_on", 0u16, 1u8), ("mv_st", 0, 0), ("mv_st", 1, 0), ("sm_arm", 0, 0), ("sm_arm", 4, 4), ("sm_fl", 0, 0)] {
        m.write_u8(name, o, v);
    }
    m.write_i32("ball_vx", 0, 0x0002_0000);
    m.write_i32("ball_x", 0, 160 << 16);
    let title = "MAX RISING STRIKE";
    let (r4, r5) = (0xC000 + 4 * 40 + 21, 0xC000 + 5 * 40 + 21);
    frames(m, 3);
    let drawn = |m: &Machine| (0..title.len()).filter(|&i| m.cpu.mem[r5 + i] == bar_c0).count();
    let first = drawn(m);
    if first == 0 || first > 3 || m.cpu.mem[r5 + title.len() - 1] != bar_c0 {
        return Err(format!("mossa armata: dopo 3 frame {first} trattini, non dal lato destro"));
    }
    frames(m, 40);
    let yellow = (0..title.len()).filter(|&i| m.cpu.read((0xD800 + 5 * 40 + 21 + i) as u16) & 15 == 7).count();
    let gaps_ok = title.bytes().enumerate().all(|(i, c)| (c == b' ') == (m.cpu.mem[r5 + i] != bar_c0));
    if drawn(m) != 15 || !gaps_ok || !(6..=8).contains(&yellow) || m.cpu.mem[r4..r4 + title.len()].iter().any(|&c| c != 0) {
        return Err(format!(
            "mossa armata: {} trattini, {yellow} gialli (con la palla a metà campo): riga 5 {:?}, colori {:?}",
            drawn(m),
            &m.cpu.mem[r5..r5 + title.len()],
            (0..title.len()).map(|i| m.cpu.read((0xD800 + 5 * 40 + 21 + i) as u16) & 15).collect::<Vec<_>>()
        ));
    }
    // il colpo: la mossa in volo, la palla che va verso P1
    m.write_u8("sm_arm", 4, 0);
    m.write_u8("sm_fl", 0, 2 + 4);
    m.write_i32("ball_vx", 0, -0x0002_0000);
    frames(m, 1);
    let letters: Vec<usize> = title.bytes().enumerate().filter(|&(_, c)| c != b' ').map(|(i, _)| i).collect();
    if !letters.iter().all(|&i| m.cpu.mem[r4 + i] == solid) {
        return Err("colpo della mossa: niente blocchi al posto delle lettere".into());
    }
    frames(m, 5);
    let want: Vec<u8> = title.bytes().map(|c| ch(m, c)).collect();
    if m.cpu.mem[r4..r4 + title.len()] != want[..] || letters.iter().any(|&i| m.cpu.read((0xD800 + 4 * 40 + 21 + i) as u16) & 15 != 7) {
        return Err("colpo della mossa: la scritta non è \"MAX RISING STRIKE\" gialla a destra".into());
    }
    frames(m, tv_frames(50));
    if m.read_u8("mv_st", 1) != 0 || m.cpu.mem[r4..r4 + title.len()].iter().chain(&m.cpu.mem[r5..r5 + title.len()]).any(|&c| c != 0) {
        return Err("colpo della mossa: la scritta resta dopo un secondo".into());
    }
    m.write_u8("sm_arm", 0, 1);
    m.write_u8("sm_fl", 0, 0);
    frames(m, 30);
    let l5 = 0xC000 + 5 * 40 + 4;
    if m.cpu.mem[l5..l5 + 13].iter().filter(|&&c| c as usize == ch_grid_t()).count() != 12 {
        return Err("STRAIGHT SHOT di P1 armata: non 12 trattini a sinistra".into());
    }
    m.write_u8("sm_arm", 0, 0);
    frames(m, 1);
    if m.read_u8("mv_st", 0) != 0 || m.cpu.mem[l5..l5 + 13].iter().any(|&c| c != 0) {
        return Err("mossa persa senza colpo: i trattini restano".into());
    }
    // mossa armata e colpo nello stesso tick (racchetta avanti): la mossa armata non si vede mai,
    // la scritta parte dall'evento del colpo (EV_SPECIAL) con la mossa in volo
    m.write_u8("sm_fl", 0, 1); // STRAIGHT SHOT di livello 1
    m.write_i32("ball_vx", 0, 0x0002_0000); // la palla lascia P1
    m.write_u8("events", 1, 0x10);
    frames(m, 1);
    m.write_u8("events", 1, 0);
    let l4 = 0xC000 + 4 * 40 + 4;
    if m.read_u8("mv_st", 0) != 2 || m.read_u8("mv_kind", 0) != 1 || m.cpu.mem[l4..l4 + 13].iter().filter(|&&c| c == solid).count() != 12 {
        return Err("colpo con la mossa nello stesso tick dell'armata: niente scritta STRAIGHT SHOT di P1".into());
    }
    m.write_u8("sm_on", 0, 0);
    // barra: 40 su 64, cioè la prima metà gialla (un settore pieno), poi 8 su 16 (4 pixel) e vuota
    let c0 = assets_supers().0;
    m.write_u8("sm_meter", 4, 40);
    m.write_u8("sm_shown", 4, 0);
    m.cpu.x = 4;
    m.cpu.frame_start = Some(m.cpu.cycles);
    m.call("bar");
    m.cpu.frame_start = None;
    let cells: Vec<u8> = (0..4).map(|k| m.cpu.mem[0xC000 + 40 + 30 + k]).collect();
    let colors: Vec<u8> = (0..4).map(|k| m.cpu.read((0xD800 + 40 + 30 + k) as u16) & 15).collect();
    if cells != [c0 + 4, c0 + 4, c0 + 2, c0] || colors != [7, 7, 15, 15] {
        return Err(format!("barra a 40: caratteri {cells:?}, colori {colors:?}"));
    }
    m.write_u8("m_next", 0, 0);
    m.write_u8("sm_on", 0, 0);
    // effetti 6 e 7 del player (fx_start): le tracce MOVE e SPECIAL della ROM della musica, come
    // tools/gen_c64_assets.py
    let dir = c64_dir().join("../mister/rtl/gen");
    let (hex, vh) = (
        std::fs::read_to_string(dir.join("sid_music.hex")).map_err(|e| format!("sid_music.hex: {e}"))?,
        std::fs::read_to_string(dir.join("sid_music.vh")).map_err(|e| format!("sid_music.vh: {e}"))?,
    );
    let rom: Vec<u8> = hex.split_whitespace().filter_map(|v| u8::from_str_radix(v, 16).ok()).collect();
    // indirizzi della ROM: "sid_song_start = 13'd320;" (la larghezza segue la ROM)
    let addr = |l: &str| -> Option<usize> {
        let (_, rest) = l.split_once("_start = ")?;
        rest.split_once("'d")?.1.trim_end_matches(';').parse().ok()
    };
    let starts: Vec<usize> = vh.lines().filter_map(addr).collect();
    let fx_start = |fx: usize| -> Option<usize> {
        vh.lines()
            .find(|l| l.contains("sid_fx_start =") && l.contains(&format!("4'd{fx}:")))
            .and_then(addr)
    };
    let table = m.addr("fx_start");
    // BOUNCE sta nel codice del continue (CLCODE, a $C400-$C6FF solo in quella schermata): qui solo
    // il posto; la traccia la carica e la suona il banco sid
    let bounce = m.cpu.read16(table + 2 * 9);
    if !(0xC400..0xC700).contains(&bounce) {
        return Err(format!("effetto 9 (BOUNCE) a ${bounce:04X}, fuori da CLCODE"));
    }
    for (fx, name) in [(6usize, "MOVE"), (7, "SPECIAL"), (8, "LASER")] {
        let id = vh_param(&vh, &format!("SID_FX_{name}")).ok_or(format!("SID_FX_{name} non c'è"))?;
        let start = fx_start(id).ok_or(format!("inizio di SID_FX_{name} non trovato"))?;
        let end = starts.iter().copied().filter(|&a| a > start).min().unwrap_or(rom.len()).min(rom.len());
        let at = m.cpu.read16(table + 2 * fx as u16);
        let got: Vec<u8> = (0..(end - start) as u16).map(|i| m.cpu.read(at + i)).collect();
        if id != fx || got != rom[start..end] {
            return Err(format!("effetto {fx} ({name}) diverso dalla traccia della ROM della musica"));
        }
    }
    Ok(format!(
        "mosse speciali: codice dalla cartuccia ({pages} pagine), voce del menu, {n} gesti del joystick dai due lati, scritta, barra, effetti MOVE, SPECIAL e LASER"
    ))
}

/// Cicli di un frame: PAL 312 righe da 63 cicli, NTSC 263 da 65.
fn frame_cycles() -> u64 {
    if ntsc() { 263 * 65 } else { 312 * 63 }
}
/// Voci di CHALLENGE (c64/src/voice.inc): dove si carica il file voce (VOICE_TICK, poi
/// VOICE_STOP), dove comincia la parte che resta del file del primo livello, il salto del conto
/// alla rovescia e i frame del conto.
const VOICE_BASE: u16 = 0xE000;
const VOICE_RES: u16 = 0xEB20;
const VOICE_COUNT: u16 = 0xFFC0;
/// COUNT_FRAMES di voice.inc: 3 secondi a 60 frame al secondo sull'NTSC (il conto alla rovescia
/// va un frame alla volta, play.s).
fn count_frames() -> u8 {
    if ntsc() { 180 } else { 150 }
}
/// voice.s: frame dell'attacco del DC prima dei campioni e del rilascio dopo, un NMI ciascuno
const ATTACK_FRAMES: u64 = 4;
const RELEASE_FRAMES: u64 = 6;
/// Immagini degli effetti di NEXT ($E000-$E93F), rifatte a ogni partita sopra il file voce
const FX_IMAGES: std::ops::Range<usize> = 0xE000..0xE940;
/// Tema dell'avversario di CHALLENGE (c64/gen/sid_music.inc): dove il file voce copia le tracce e
/// la canzone del player che le suona.
const THEME_BASE: u16 = 0xF800;
const SID_SONG_THEME: u8 = 7;
/// canzone del C64 che suona una sezione di OMEGA a THEME_BASE (sid.s: la prima traccia nella
/// prima pagina, la seconda dalla pagina dopo, la terza nell'ultimo byte della prima)
const SID_SONG_OMEGA: u8 = 10;
/// prima canzone di OMEGA nella ROM del MiSTer (SID_SONG_OMEGA0 di sid_music.vh), una per forma
const OMEGA_SECTIONS: usize = 7;

/// Le tracce di una sezione di OMEGA (o di un tema, nel jukebox) dove le legge SID_SONG_OMEGA.
fn load_omega(m: &mut Machine, tracks: &[&[u8]]) -> Result<(), String> {
    let [t0, t1, t2] = tracks else {
        return Err(format!("{} tracce invece di 3", tracks.len()));
    };
    if t0.len() > 255 || t1.len() > 3 * 256 || t2 != &[0xFF] {
        return Err(format!("tracce di {}, {} e {} byte: non stanno a THEME_BASE", t0.len(), t1.len(), t2.len()));
    }
    m.cpu.load(THEME_BASE, t0);
    m.cpu.load(THEME_BASE + 0xFF, t2);
    m.cpu.load(THEME_BASE + 0x100, t1);
    Ok(())
}

/// Un frame della voce: VOICE_TICK, poi gli NMI fino alla fine del frame.
fn voice_frame(m: &mut Machine) -> Result<(), String> {
    let start = m.cpu.cycles;
    m.cpu.call(VOICE_BASE, 100_000)?;
    m.cpu.idle(start + frame_cycles())
}

/// Un frame del conto alla rovescia con `left` frame rimasti: VOICE_COUNT come count_scene, poi
/// gli NMI fino alla fine del frame.
fn count_frame(m: &mut Machine, left: u8) -> Result<(), String> {
    let start = m.cpu.cycles;
    m.cpu.a = left;
    m.cpu.call(VOICE_COUNT, 100_000)?;
    m.cpu.idle(start + frame_cycles())
}

/// Un frame senza chiamate alla voce: solo i suoi NMI.
fn idle_frame(m: &mut Machine) -> Result<(), String> {
    let start = m.cpu.cycles;
    m.cpu.idle(start + frame_cycles())
}

/// Il SID e l'NMI sono di nuovo del programma: vettore, timer A del CIA2 fermo, voci spente.
fn voice_off(m: &Machine, nmi: u16, what: &str) -> Result<(), String> {
    let ctrl = [m.cpu.mem[0xD404], m.cpu.mem[0xD40B], m.cpu.mem[0xD412]];
    if m.cpu.read16(0xFFFA) != nmi || m.cpu.cia2.running || ctrl != [0; 3] {
        return Err(format!(
            "{what}: vettore dell'NMI ${:04X}, timer acceso {}, controllo delle voci {ctrl:02X?}",
            m.cpu.read16(0xFFFA),
            m.cpu.cia2.running
        ));
    }
    Ok(())
}

/// Scritture attese in $D418 per una voce: 8 (il silenzio, con l'attacco del DC), i campioni di
/// `file` in c64/gen (prima il nibble alto), 8 (il rilascio) e 15; poi quanti sono i campioni.
fn voice_writes(file: &str) -> Result<(Vec<u8>, usize), String> {
    voice_writes_at(file, 15)
}

/// Le scritture attese in $D418 per la voce `file` con il VOLUME del menu al livello del SID
/// `level` (1-15, sid_vol): ogni campione n scalato attorno al silenzio, 8 + round((n - 8) *
/// level / 15) (vol_tab di voice.s; a 15 i campioni del file), e alla fine il volume del menu.
fn voice_writes_at(file: &str, level: u8) -> Result<(Vec<u8>, usize), String> {
    let raw = std::fs::read(c64_dir().join("gen").join(file)).map_err(|e| format!("{file}: {e}"))?;
    let scale = |n: u8| ((n as i32 - 8) * level as i32 + 127).div_euclid(15) as u8;
    let mut want = vec![8u8];
    want.extend(raw.iter().flat_map(|b| [scale(b >> 4), scale(b & 15)]));
    want.extend([8, level]);
    Ok((want, 2 * raw.len()))
}

/// Confronta le scritture in $D418 con quelle attese.
fn same_writes(got: &[u8], want: &[u8], what: &str) -> Result<(), String> {
    if got != want {
        let at = got.iter().zip(want).position(|(a, b)| a != b).unwrap_or(got.len().min(want.len()));
        return Err(format!(
            "{what}: {} scritture in $D418 invece di {}, diverse dalla {at}",
            got.len(),
            want.len()
        ));
    }
    Ok(())
}

/// Conto alla rovescia di CHALLENGE con il file voce del primo livello già arrivato, poi 40 frame
/// di partita. Al primo frame il SID è già della voce (READY), che finisce prima del bip dei due
/// secondi; GO prende il SID ATTACK_FRAMES frame prima del via, nessun campione prima del via e i
/// primi nel frame del via. Restituisce i campioni controllati.
fn countdown_voice(m: &mut Machine, nmi: u16, what: &str) -> Result<usize, String> {
    let level = m.read_u8("sid_vol", 0);
    let (ready, n_ready) = voice_writes_at("ready.bin", level)?;
    let (go, n_go) = voice_writes_at("go.bin", level)?;
    m.cpu.watch = Some((0xD418, 0xD418));
    m.cpu.writes.clear();
    let nmis = m.cpu.nmis;
    let mut before = Vec::new(); // scritture prima di ogni frame del conto, poi alla fine
    for left in (1..=count_frames()).rev() {
        before.push(m.cpu.writes.len());
        count_frame(m, left)?;
        if left == count_frames() && m.cpu.read(0xFFFB) & 0x80 == 0 {
            return Err(format!("{what}: al primo frame del conto il SID non è della voce (READY)"));
        }
    }
    before.push(m.cpu.writes.len());
    for _ in 0..40 {
        idle_frame(m)?;
    }
    let got: Vec<u8> = m.cpu.writes.iter().map(|w| w.1).collect();
    // READY finita prima del bip dei due secondi (50 frame dopo l'inizio)
    let ready_end = before[50];
    same_writes(&got[..ready_end], &ready, &format!("{what}, READY"))?;
    // GO: l'8 dell'attacco ATTACK_FRAMES frame prima del via, poi niente fino al frame del via
    let via = count_frames() as usize - 1;
    let go_at = via - ATTACK_FRAMES as usize;
    if before[go_at] != ready_end || (go_at + 1..=via).any(|f| before[f] != ready_end + 1) {
        return Err(format!(
            "{what}, GO: scritture in $D418 prima dei frame dell'attacco e del via {:?} invece di solo l'8 dell'attacco",
            &before[go_at..=via]
        ));
    }
    if before[via + 1] < ready_end + 3 {
        return Err(format!("{what}, GO: nessun campione nel frame del via"));
    }
    same_writes(&got[ready_end..], &go, &format!("{what}, GO"))?;
    let want_nmis = (n_ready + n_go) as u64 + 2 * (ATTACK_FRAMES + RELEASE_FRAMES);
    if m.cpu.nmis - nmis != want_nmis {
        return Err(format!("{what}: {} NMI invece di {want_nmis}", m.cpu.nmis - nmis));
    }
    voice_off(m, nmi, &format!("{what}, dopo GO"))?;
    m.cpu.watch = None;
    Ok(n_ready + n_go)
}

/// Bitmap com'è dopo l'attract: qualcosa, non zeri.
fn scribble_bitmap(m: &mut Machine) {
    for a in 0xE000..0xFF40usize {
        m.cpu.mem[a] = (a as u8).wrapping_mul(37) ^ 0x5A;
    }
}

/// Voci di CHALLENGE (c64/src/voice.s). Senza file voce (due RTS) VOICE_COUNT resta l'RTS di
/// start_game: niente scritture nel SID, niente NMI, nella presentazione e nel conto alla
/// rovescia. Poi una scala intera, i file copiati dalla cartuccia (ef_voice) nell'ordine dei
/// livelli, uguali ai file voce: ogni nome nel volume ($D418) nell'ordine, un campione per NMI, e
/// il tema a $F800; nel conto alla rovescia READY al primo frame e GO al via, con le immagini degli
/// effetti sopra il file voce (il player e le due voci del file del primo livello restano).
/// VOICE_STOP a metà ferma subito la voce, sid_song (VOICE_HUSH) anche GO; senza il file del primo
/// livello gli altri non dicono niente. Restituisce i campioni controllati.
fn voice(m: &mut Machine) -> Result<usize, String> {
    let nmi = m.addr("nmi_handler");
    m.cpu.write(0xFFFA, nmi as u8);
    m.cpu.write(0xFFFB, (nmi >> 8) as u8);
    let saved = m.cpu.mem[0xD400..0xD419].to_vec();
    for r in [0xD404, 0xD40B, 0xD412] {
        m.cpu.mem[r] = 0;
    }
    // start_game mette l'RTS a VOICE_COUNT (READY e GO solo dopo il file del primo livello)
    m.cpu.write(VOICE_COUNT, 0x4C);
    m.call("start_game");
    if m.cpu.read(VOICE_COUNT) != 0x60 {
        return Err("start_game non mette l'RTS a VOICE_COUNT".into());
    }
    m.cpu.write(VOICE_BASE, 0x60);
    m.cpu.write(VOICE_BASE + 3, 0x60);
    m.cpu.watch = Some((0xD400, 0xD418));
    m.cpu.writes.clear();
    let nmis = m.cpu.nmis;
    for _ in 0..100 {
        voice_frame(m)?;
    }
    m.cpu.a = 0;
    m.cpu.call(VOICE_BASE + 3, 1000)?;
    if m.cpu.a != 0 {
        return Err("senza file VOICE_STOP cambia A (la musica della partita)".into());
    }
    for left in (1..=count_frames()).rev() {
        count_frame(m, left)?;
    }
    if !m.cpu.writes.is_empty() || m.cpu.nmis != nmis {
        return Err(format!("senza file {} scritture nel SID e {} NMI", m.cpu.writes.len(), m.cpu.nmis - nmis));
    }
    voice_off(m, nmi, "senza file")?;
    scribble_bitmap(m);
    let mut total = 0;
    for level in 0..7u16 {
        let kind = m.read_u8("rung_kind", level);
        let (addr, data) = m.voice_file(kind)?;
        if addr != VOICE_BASE {
            return Err(format!("voice{kind}.prg si carica a ${addr:04X}"));
        }
        if (level == 0) != (VOICE_BASE as usize + data.len() > VOICE_RES as usize) {
            return Err(format!("voice{kind}.prg: solo il file del primo livello arriva oltre VOICE_RES"));
        }
        // dalla cartuccia: lo stesso file, con il player e READY del primo livello
        m.cpu.a = kind;
        m.call("ef_voice");
        let at = VOICE_BASE as usize;
        if m.cpu.mem[at..at + data.len()] != data[..] {
            return Err(format!("tipo {kind}: la voce copiata dalla cartuccia non è voice{kind}.prg"));
        }
        if level == 0 && m.cpu.read(VOICE_COUNT) != 0x60 {
            return Err("VOICE_COUNT non è un RTS prima del file del primo livello".into());
        }
        let (want, n) = voice_writes(&format!("voice{kind}.bin"))?;
        m.cpu.watch = Some((0xD418, 0xD418));
        m.cpu.writes.clear();
        let nmis = m.cpu.nmis;
        for _ in 0..120 {
            voice_frame(m)?;
        }
        let got: Vec<u8> = m.cpu.writes.iter().map(|w| w.1).collect();
        same_writes(&got, &want, &format!("tipo {kind}"))?;
        let want_nmis = n as u64 + ATTACK_FRAMES + RELEASE_FRAMES;
        if m.cpu.nmis - nmis != want_nmis {
            return Err(format!("tipo {kind}: {} NMI invece di {want_nmis}", m.cpu.nmis - nmis));
        }
        voice_off(m, nmi, &format!("tipo {kind}, alla fine"))?;
        // il tema dell'avversario a THEME_BASE (dal primo frame), una traccia per pagina, come i
        // file del generatore (la terza, vuota, è scritta dal player); VOICE_STOP dà la sua canzone
        m.cpu.a = 0;
        m.cpu.call(VOICE_BASE + 3, 10_000)?;
        if m.cpu.a != SID_SONG_THEME {
            return Err(format!("tipo {kind}: VOICE_STOP dà la canzone {} invece del tema", m.cpu.a));
        }
        for v in 0..3usize {
            let track =
                std::fs::read(c64_dir().join(format!("gen/theme{kind}_{v}.bin"))).map_err(|e| e.to_string())?;
            let at = THEME_BASE as usize + v * 0x100;
            if track.is_empty() || m.cpu.mem[at..at + track.len()] != track[..] {
                return Err(format!("tipo {kind}: traccia {v} del tema non copiata a ${at:04X}"));
            }
        }
        voice_off(m, nmi, &format!("tipo {kind}, dopo VOICE_STOP"))?;
        total += n;
        // la partita: immagini degli effetti sopra il file, READY e GO nel conto alla rovescia
        for a in FX_IMAGES {
            m.cpu.mem[a] = 0x55;
        }
        total += countdown_voice(m, nmi, &format!("livello {}, conto alla rovescia", level + 1))?;
    }
    // il VOLUME del menu: al 50% (livello del SID 5) i campioni scalati attorno al silenzio; a 0
    // nessuna voce, né l'8 dell'attacco (che si sentirebbe come un colpo), né NMI
    let vol = m.read_u8("sid_vol", 0);
    m.write_u8("sid_vol", 0, 5);
    total += countdown_voice(m, nmi, "conto alla rovescia al 50%")?;
    m.write_u8("sid_vol", 0, 0);
    m.cpu.watch = Some((0xD400, 0xD418));
    m.cpu.writes.clear();
    let nmis = m.cpu.nmis;
    for left in (1..=count_frames()).rev() {
        count_frame(m, left)?;
    }
    if !m.cpu.writes.is_empty() || m.cpu.nmis != nmis {
        return Err(format!("volume a 0: {} scritture nel SID e {} NMI nel conto alla rovescia", m.cpu.writes.len(), m.cpu.nmis - nmis));
    }
    voice_off(m, nmi, "volume a 0")?;
    m.write_u8("sid_vol", 0, vol);
    // fermata a metà: volume subito a 15, niente più NMI
    let (addr, data) = m.voice_file(m.read_u8("rung_kind", 0))?;
    m.cpu.load(addr, &data);
    m.cpu.watch = Some((0xD418, 0xD418));
    for _ in 0..40 {
        voice_frame(m)?;
    }
    m.cpu.writes.clear();
    m.cpu.call(VOICE_BASE + 3, 10_000)?;
    let nmis = m.cpu.nmis;
    for _ in 0..40 {
        voice_frame(m)?;
    }
    if m.cpu.writes.iter().map(|w| w.1).collect::<Vec<_>>() != [15] || m.cpu.nmis != nmis {
        return Err(format!(
            "fermata a metà: scritture in $D418 {:?}, {} NMI dopo",
            m.cpu.writes,
            m.cpu.nmis - nmis
        ));
    }
    voice_off(m, nmi, "fermata a metà")?;
    // GO interrotto da una scena nuova (sid_song: VOICE_HUSH), che cambia canzone; X resta
    for left in (1..=ATTACK_FRAMES as u8 + 3).rev() {
        count_frame(m, left)?;
    }
    m.cpu.writes.clear();
    m.write_u8("sid_song_n", 0, 1);
    m.cpu.a = 0;
    m.cpu.x = 0x77;
    m.call("sid_song");
    let nmis = m.cpu.nmis;
    for _ in 0..10 {
        idle_frame(m)?;
    }
    // (un NMI della voce può ancora capitare durante sid_song, prima di VOICE_HUSH)
    if m.cpu.writes.last().map(|w| w.1) != Some(15) || m.cpu.nmis != nmis || m.cpu.x != 0x77 {
        return Err(format!(
            "GO fermato da sid_song: scritture in $D418 {:?}, {} NMI dopo, X = ${:02X}",
            m.cpu.writes,
            m.cpu.nmis - nmis,
            m.cpu.x
        ));
    }
    voice_off(m, nmi, "GO fermato da sid_song")?;
    if m.read_u8("sid_song_n", 0) != 0 {
        return Err("sid_song con la voce in corso non cambia canzone".into());
    }
    // senza il file del primo livello (VOICE_COUNT resta l'RTS di start_game) gli altri copiano il
    // tema ma non dicono niente, e il conto alla rovescia nemmeno
    m.cpu.write(VOICE_COUNT, 0x60);
    scribble_bitmap(m);
    let kind = m.read_u8("rung_kind", 1);
    let (addr, data) = m.voice_file(kind)?;
    m.cpu.load(addr, &data);
    m.cpu.watch = Some((0xD400, 0xD418));
    m.cpu.writes.clear();
    let nmis = m.cpu.nmis;
    for _ in 0..120 {
        voice_frame(m)?;
    }
    for left in (1..=count_frames()).rev() {
        count_frame(m, left)?;
    }
    if !m.cpu.writes.is_empty() || m.cpu.nmis != nmis {
        return Err(format!(
            "senza il file del primo livello {} scritture nel SID e {} NMI",
            m.cpu.writes.len(),
            m.cpu.nmis - nmis
        ));
    }
    m.cpu.watch = None;
    m.cpu.writes.clear();
    m.cpu.mem[0xD400..0xD419].copy_from_slice(&saved);
    Ok(total)
}

/// Classifica di CHALLENGE nella flash della cartuccia (c64/src/ef.s, hi_load e hi_save in
/// challenge.s): con la flash cancellata resta quella iniziale; ogni salvataggio va nel posto dopo
/// e torna uguale all'avvio; finiti i posti si cancella il settore (una volta) e si ricomincia; un
/// posto scritto a metà (spegnimento) non conta; dati di prima nel settore si cancellano; una
/// cartuccia che non si scrive non si blocca. Mai un accesso alla RAM che nel modo Ultimax non c'è.
fn hiscore(m: &mut Machine) -> Result<String, String> {
    const HI_BANK: usize = 16;
    const TABLE: usize = 80;
    let table = m.addr("ch_table");
    let saved_flash = m.cpu.ef.as_ref().map(|ef| ef.roml.clone()).unwrap_or_default();
    let saved_table: Vec<u8> = (0..TABLE as u16).map(|i| m.cpu.read(table + i)).collect();
    let init: Vec<u8> = (0..TABLE as u16).map(|i| m.image_u8("table_init", i)).collect();
    fn ef(m: &mut Machine) -> &mut EasyFlash {
        m.cpu.ef.as_mut().expect("cartuccia")
    }
    let bank = HI_BANK * EF_HALF;
    let read_table = |m: &Machine| -> Vec<u8> { (0..TABLE as u16).map(|i| m.cpu.read(table + i)).collect() };
    let write_table = |m: &mut Machine, seed: u8| {
        for i in 0..TABLE as u16 {
            m.cpu.write(table + i, seed.wrapping_mul(31).wrapping_add(i as u8 * 7) & 0x7F);
        }
    };
    // hi_load è nel segmento INIT (solo all'avvio, poi lì ci sono le variabili): lo si rimette dal
    // .prg per la chiamata, e poi le variabili com'erano
    let boot = |m: &mut Machine| -> Result<Vec<u8>, String> {
        for i in 0..TABLE as u16 {
            m.cpu.write(table + i, 0xEE);
        }
        m.write_u8("hi_open", 0, 0xEE);
        let init = 0xBC00..0xC000;
        let vars = m.cpu.mem[init.clone()].to_vec();
        let from = init.start - 0x0801;
        m.cpu.mem[init.clone()].copy_from_slice(&m.image[from..from + init.len()]);
        let a = m.addr("hi_load");
        let r = m.cpu.call(a, 2_000_000).map_err(|e| format!("hi_load: {e}"));
        m.cpu.mem[init].copy_from_slice(&vars);
        r?;
        Ok(read_table(m))
    };
    let save = |m: &mut Machine| -> Result<u64, String> {
        let a = m.addr("hi_save");
        m.cpu.call(a, 40_000_000).map_err(|e| format!("hi_save: {e}"))
    };
    ef(m).roml[bank..bank + 0x10000].fill(0xFF);
    // flash cancellata: la classifica iniziale, il primo posto per il prossimo salvataggio
    if boot(m)? != init || m.read_u8("hi_next", 0) != 0 || m.read_u8("hi_open", 0) != 0xFF {
        return Err("con la flash cancellata non c'è la classifica iniziale nel primo posto, bloccata".into());
    }
    // un posto scritto prima dello sblocco (83 byte: classifica, HI_MAGIC, controllo; poi la flash
    // cancellata): vale, con l'allenamento bloccato
    let old: Vec<u8> = (0..TABLE).map(|i| (i as u8).wrapping_mul(5) & 0x7F).collect();
    let mut slot = old.clone();
    slot.extend([0x48, 0x50]);
    slot.push(slot.iter().fold(0xA5u8, |a, &b| a ^ b));
    ef(m).roml[bank..bank + slot.len()].copy_from_slice(&slot);
    if boot(m)? != old || m.read_u8("hi_next", 0) != 1 || m.read_u8("hi_open", 0) != 0xFF {
        return Err("un posto di prima dello sblocco non vale, o sblocca l'allenamento".into());
    }
    ef(m).roml[bank..bank + 0x10000].fill(0xFF);
    boot(m)?;
    // salvataggi uno dopo l'altro, oltre i 32 posti: ogni volta all'avvio torna l'ultimo; dal 40
    // (dopo la prima cancellazione) con l'allenamento sbloccato, che poi resta anche dopo la seconda
    let mut worst = 0;
    for n in 0..70u8 {
        write_table(m, n);
        if n == 40 {
            m.write_u8("hi_open", 0, 0);
        }
        let want = read_table(m);
        worst = worst.max(save(m)?);
        if boot(m)? != want {
            return Err(format!("salvataggio {n}: all'avvio non torna"));
        }
        let open = m.read_u8("hi_open", 0);
        if open != if n >= 40 { 0 } else { 0xFF } {
            return Err(format!("salvataggio {n}: sblocco dell'allenamento ${open:02X} all'avvio"));
        }
    }
    let (erases, dirty) = (ef(m).erases, ef(m).dirty_programs);
    if erases != 2 || dirty != 0 {
        return Err(format!("70 salvataggi: {erases} cancellazioni invece di 2, {dirty} byte scritti non cancellati"));
    }
    // posto scritto a metà (l'ultimo byte, il controllo, non scritto): vale quello di prima
    let next = m.read_u8("hi_next", 0) as usize;
    let before = read_table(m);
    write_table(m, 200);
    save(m)?;
    let last = bank + next * 128 + TABLE + 2;
    ef(m).roml[last] = 0xFF;
    ef(m).roml[last + 1] = 0xFF;
    if boot(m)? != before || m.read_u8("hi_next", 0) as usize != next + 1 {
        return Err("un posto scritto a metà conta, o il prossimo salvataggio ci va sopra".into());
    }
    // dati di prima nel settore (un'altra cartuccia): classifica iniziale, poi il salvataggio
    // cancella e scrive nel primo posto
    for (i, b) in ef(m).roml[bank..bank + 0x10000].iter_mut().enumerate() {
        *b = (i as u8).wrapping_mul(13) ^ 0x24;
    }
    let erases = ef(m).erases;
    if boot(m)? != init || m.read_u8("hi_open", 0) != 0xFF {
        return Err("con dati di prima nella flash non c'è la classifica iniziale, bloccata".into());
    }
    write_table(m, 77);
    let want = read_table(m);
    save(m)?;
    if ef(m).erases != erases + 1 || boot(m)? != want || m.read_u8("hi_next", 0) != 1 {
        return Err("con dati di prima il salvataggio non cancella e scrive nel primo posto".into());
    }
    // cartuccia che non si scrive (la flash non cambia): il salvataggio finisce, poi non ci prova più
    ef(m).roml[bank..bank + 0x10000].fill(0x00);
    ef(m).locked = true;
    m.write_u8("hi_next", 0, 5);
    save(m)?;
    let locked = m.read_u8("hi_next", 0);
    let t = save(m)?;
    ef(m).locked = false;
    if locked & 0x80 == 0 || t > 100 {
        return Err(format!("con la flash che non si scrive hi_next = ${locked:02X}, poi {t} cicli"));
    }
    let faults = ef(m).faults.get();
    if faults != 0 {
        return Err(format!("{faults} accessi alla RAM che nel modo Ultimax non c'è (o comandi sbagliati)"));
    }
    // com'era
    ef(m).roml = saved_flash;
    for (i, &b) in saved_table.iter().enumerate() {
        m.cpu.write(table + i as u16, b);
    }
    m.write_u8("hi_next", 0, 0);
    m.write_u8("hi_open", 0, 0xFF);
    Ok(format!(
        "classifica nella flash: 70 salvataggi con 2 cancellazioni, ognuno torna all'avvio (al più {worst} cicli), con lo sblocco dell'allenamento (anche dopo la cancellazione); posto di prima dello sblocco valido e bloccato; posto a metà ignorato, dati di prima cancellati, flash che non si scrive lasciata"
    ))
}

/// Menu (play.s, MENUCODE): GAME in giro CLASSIC, EVO, NEXT con PLAYERS valido per il gioco (in
/// NEXT sempre la scala, OPT_CHALLENGE); la riga di PLAYERS in NEXT è vuota e il cursore la salta,
/// o con l'allenamento sbloccato (hi_open = 0) è OPPONENT: LADDER e gli avversari nell'ordine della
/// scala, in giro nei due versi.
fn next_menu_ui(m: &mut Machine) -> Result<String, String> {
    const MI_GAME: u8 = 0;
    const MI_PLAYERS: u8 = 1;
    const ROW: u16 = 6; // MENU_ROW0 + 2 * MI_PLAYERS
    quiet_inputs(m);
    let saved_open = m.read_u8("hi_open", 0);
    m.write_u8("hi_open", 0, 0xFF);
    m.write_u8("opt_mode", 0, 0);
    m.write_u8("opt_players", 0, 1);
    m.write_u8("opt_opp", 0, 0);
    m.call("enter_menu");
    let row = |m: &Machine, name: &str, value: &str| text_at(m, 0xC000, ROW, 8, name) && text_at(m, 0xC000, ROW, 25, value);
    let change = |m: &mut Machine, sel: u8, dir: u8| {
        m.write_u8("menu_sel", 0, sel);
        m.cpu.a = dir;
        m.call("change_value");
        m.call("draw_menu");
    };
    let cursor = |m: &mut Machine, from: u8, joy: u8| -> u8 {
        m.write_u8("menu_sel", 0, from);
        m.write_u8("joy_edge", 0, joy);
        m.call("menu_scene");
        m.write_u8("joy_edge", 0, 0);
        m.read_u8("menu_sel", 0)
    };
    if !row(m, "PLAYERS ", "ONE     ") {
        let codes: Vec<u8> = (0..40).map(|c| m.cpu.mem[0xC000 + 6 * 40 + c]).collect();
        return Err(format!("CLASSIC: la riga non è PLAYERS ONE: {codes:?}"));
    }
    // GAME avanti: EVO (ONE non c'è: TWO), NEXT (la scala), CLASSIC (ONE); poi indietro
    for (dir, mode, players, name, value) in [
        (1u8, 1u8, 2u8, "PLAYERS ", "TWO     "),
        (1, 2, 4, "        ", "        "),
        (1, 0, 1, "PLAYERS ", "ONE     "),
        (0xFF, 2, 4, "        ", "        "),
        (0xFF, 1, 3, "PLAYERS ", "VS CPU  "),
    ] {
        change(m, MI_GAME, dir);
        let (got_mode, got_players) = (m.read_u8("opt_mode", 0), m.read_u8("opt_players", 0));
        if (got_mode, got_players) != (mode, players) || !row(m, name, value) {
            return Err(format!(
                "GAME: modo {got_mode}, giocatori {got_players} invece di {mode}, {players}, o la riga non è \"{name}\" \"{value}\""
            ));
        }
    }
    // in EVO PLAYERS va solo fra TWO e VS CPU
    for (dir, want) in [(1u8, 2u8), (1, 3), (0xFF, 2), (0xFF, 3)] {
        change(m, MI_PLAYERS, dir);
        if m.read_u8("opt_players", 0) != want {
            return Err(format!("EVO: PLAYERS {} invece di {want}", m.read_u8("opt_players", 0)));
        }
    }
    // NEXT bloccato: il cursore salta la riga vuota nei due versi
    change(m, MI_GAME, 1);
    if cursor(m, MI_GAME, 0x02) != 2 || cursor(m, 2, 0x01) != MI_GAME {
        return Err("NEXT senza allenamento: il cursore si ferma sulla riga vuota".into());
    }
    // sbloccato: OPPONENT, e il cursore ci si ferma
    m.write_u8("hi_open", 0, 0);
    m.call("draw_menu");
    if !row(m, "OPPONENT", "LADDER  ") || cursor(m, MI_GAME, 0x02) != MI_PLAYERS {
        return Err("NEXT con l'allenamento: niente OPPONENT LADDER, o il cursore non ci si ferma".into());
    }
    let names: Vec<&str> = std::iter::once("LADDER").chain(RUNGS.iter().map(|r| r.kind.name())).collect();
    for step in 1..=names.len() * 2 {
        change(m, MI_PLAYERS, 1);
        let i = step % names.len();
        if m.read_u8("opt_opp", 0) as usize != i || !row(m, "OPPONENT", &format!("{:<8}", names[i])) {
            return Err(format!("OPPONENT avanti, passo {step}: {} invece di {}", m.read_u8("opt_opp", 0), names[i]));
        }
    }
    change(m, MI_PLAYERS, 0xFF);
    if m.read_u8("opt_opp", 0) as usize != names.len() - 1 || !row(m, "OPPONENT", &format!("{:<8}", names[names.len() - 1])) {
        return Err("OPPONENT indietro da LADDER: non l'ultimo avversario".into());
    }
    // OMEGA sbloccato (hi_omega = 0): dopo il GUARDIAN, poi di nuovo LADDER; il JUKEBOX solo
    // sbloccato (hi_juke = 0), dopo PLAY, e il cursore ci arriva dal fondo
    let saved_unlocks = (m.read_u8("hi_omega", 0), m.read_u8("hi_juke", 0));
    m.write_u8("hi_omega", 0, 0);
    m.write_u8("opt_opp", 0, names.len() as u8 - 1);
    change(m, MI_PLAYERS, 1);
    if m.read_u8("opt_opp", 0) != CH_OMEGA + 1 || !row(m, "OPPONENT", "OMEGA   ") {
        return Err(format!("OPPONENT dopo il GUARDIAN con OMEGA sbloccato: {}", m.read_u8("opt_opp", 0)));
    }
    change(m, MI_PLAYERS, 1);
    if m.read_u8("opt_opp", 0) != 0 {
        return Err("OPPONENT dopo OMEGA: non LADDER".into());
    }
    change(m, MI_PLAYERS, 0xFF);
    if m.read_u8("opt_opp", 0) != CH_OMEGA + 1 {
        return Err("OPPONENT indietro da LADDER con OMEGA sbloccato: non OMEGA".into());
    }
    let juke_row = |m: &Machine| text_at(m, 0xC000, 4 + 2 * 9, 8, "JUKEBOX");
    if juke_row(m) || cursor(m, 0, 0x01) != 8 {
        return Err("JUKEBOX nel menu senza lo sblocco".into());
    }
    m.write_u8("hi_juke", 0, 0);
    m.call("draw_menu");
    if !juke_row(m) || cursor(m, 0, 0x01) != 9 || cursor(m, 9, 0x02) != 0 {
        return Err("JUKEBOX sbloccato: la voce non c'è o il cursore non ci arriva".into());
    }
    m.write_u8("hi_omega", 0, saved_unlocks.0);
    m.write_u8("hi_juke", 0, saved_unlocks.1);
    m.write_u8("opt_opp", 0, 0);
    m.call("draw_menu");
    // tornando a CLASSIC, PLAYERS
    change(m, MI_GAME, 1);
    if !row(m, "PLAYERS ", "ONE     ") {
        return Err("da NEXT a CLASSIC la riga non torna PLAYERS ONE".into());
    }
    m.write_u8("opt_opp", 0, 0);
    m.write_u8("hi_open", 0, saved_open);
    Ok("menu: GAME e PLAYERS validi per il gioco, in NEXT la riga vuota saltata, o OPPONENT (LADDER e i 7 avversari, in giro, e OMEGA se sbloccato) con l'allenamento sbloccato; JUKEBOX solo sbloccato".into())
}

/// Frame interi (`each` prima di ognuno) finché `done`, al più `max`; errore con `what` se non
/// succede. Restituisce i cicli del frame più pesante, senza quelli che caricano un file voce
/// dalla cartuccia (copie di almeno 50.000 cicli, fuori dal budget come in `frames`).
fn frames_until(
    m: &mut Machine,
    max: u32,
    what: &str,
    mut each: impl FnMut(&mut Machine),
    done: impl Fn(&Machine) -> bool,
) -> Result<u64, String> {
    let mut worst = 0;
    for f in 0..max {
        if done(m) {
            return Ok(worst);
        }
        each(m);
        let ef = m.cpu.ef_cycles;
        let c = full_frame(m).map_err(|e| format!("{what}, frame {f} (stato {}): {e}", m.read_u8("state", 0)))?;
        if m.cpu.ef_cycles - ef < 50_000 {
            worst = worst.max(c);
        }
    }
    if done(m) { Ok(worst) } else { Err(format!("{what}: non succede in {max} frame (stato {})", m.read_u8("state", 0))) }
}

/// Fuoco della porta 1 (il lato destro) premuto un frame sì e uno no.
fn fire_port1(m: &mut Machine) {
    m.cpu.joy_port1 = if m.cpu.joy_port1 == 0xFF { !0x10 } else { 0xFF };
}

/// Duelli vinti di fila (WINS, challenge.s): il campione ne aggiunge uno (fino a 99), lo sfidante
/// che vince riparte da 1; "n WINS" dal lato del vincitore nel GAME OVER della sfida (riga 24) e
/// dal lato del campione nella presentazione che riprende (riga 0).
fn wins_ui(m: &mut Machine) -> Result<String, String> {
    for (side, wins, winner, want) in [(0u8, 0u8, 0u8, 1u8), (0, 2, 0, 3), (0, 2, 4, 1), (4, 98, 4, 99), (4, 99, 4, 99), (4, 5, 0, 1)] {
        m.write_u8("ch_side", 0, side);
        m.write_u8("ch_wins", 0, wins);
        m.cpu.x = winner;
        m.call("wins_after");
        if m.cpu.a != want {
            return Err(format!("campione {side}, {wins} vinti, vince {winner}: {} invece di {want}", m.cpu.a));
        }
    }
    m.call("clear_screen");
    for (n, side, row, col, text) in [(12u8, 4u8, 24u16, 32u16, "12 WINS"), (1, 0, 0, 1, "1 WINS"), (7, 4, 0, 33, "7 WINS")] {
        m.cpu.a = n;
        m.cpu.x = side;
        m.cpu.y = row as u8;
        m.call("print_wins");
        if !text_at(m, 0xC000, row, col, text) || m.cpu.mem[0xD800 + (row * 40 + col) as usize] & 15 != COL_YELLOW {
            return Err(format!("\"{text}\" non alla riga {row}, colonna {col}, in giallo"));
        }
    }
    // fine di una sfida, poi la presentazione: lato del campione, vinti, punti a sinistra e a
    // destra, colonna di "n WINS" nel GAME OVER, lato del campione e colonna nella presentazione
    let mut seen = Vec::new();
    for (side, wins, left, right, col, text, after, intro_col) in
        [(0u8, 2u8, 11u8, 3u8, 1u16, "3 WINS", 0u8, 1u16), (0, 3, 3, 11, 33, "1 WINS", 4, 33)]
    {
        quiet_inputs(m);
        m.call("math_ensure");
        for (name, v) in [
            ("cg_active", 2u8),
            ("ch_side", side),
            ("ch_wins", wins),
            ("ch_level", 2),
            ("cpu_side", 0xFF),
            ("m_players", 2),
            ("m_next", 0),
            ("ch_phase", 0),
            ("opt_free", 1),
            ("ch_loser", 0),
        ] {
            m.write_u8(name, 0, v);
        }
        m.write_i32("ch_best", 0, 0);
        for (o, v) in [(0u16, left), (1, 0), (4, right), (5, 0)] {
            m.write_u8("score", o, v);
        }
        m.call("clear_screen");
        m.write_u8("state", 0, ST_PLAY);
        m.write_u8("over_next", 0, 1);
        let shown = std::cell::Cell::new(false);
        frames_until(
            m,
            600,
            "GAME OVER della sfida",
            |m| shown.set(shown.get() || text_at(m, 0xC000, 24, col, text)),
            |m| m.read_u8("state", 0) == ST_INTRO,
        )?;
        if !shown.get() {
            return Err(format!("GAME OVER della sfida senza \"{text}\" alla colonna {col}"));
        }
        if m.read_u8("ch_wins", 0) != text.as_bytes()[0] - b'0' || m.read_u8("ch_side", 0) != after {
            return Err(format!(
                "dopo la sfida {} vinti dal lato {} invece di {text} dal lato {after}",
                m.read_u8("ch_wins", 0),
                m.read_u8("ch_side", 0)
            ));
        }
        frames_until(m, 10, "presentazione", |_| {}, |m| m.read_u8("ch_phase", 0) == 0)?;
        if !text_at(m, 0xC000, 0, intro_col, text) {
            return Err(format!("presentazione dopo la sfida senza \"{text}\" alla colonna {intro_col}"));
        }
        seen.push(text);
    }
    quiet_inputs(m);
    m.write_u8("cg_active", 0, 0);
    m.write_u8("ch_wins", 0, 0);
    Ok(format!(
        "duelli vinti di fila: il campione +1 (fino a 99), lo sfidante da 1; {} nel GAME OVER della sfida dal lato di chi vince e nella presentazione dal lato del campione",
        seen.join(" e ")
    ))
}

/// Allenamento (OPPONENT del menu, cg_active = CG_TRAIN): la scelta con l'avversario del livello a
/// destra (racchetta e bonus), il file voce del primo livello prima della presentazione (READY e
/// GO), TRAINING al posto del livello e niente punti; nessuno sfidante; la partita con racchetta,
/// bonus, CPU, velocità e punti del livello; niente punti arcade; GAME OVER con la sua musica, poi
/// l'attract, senza classifica né salvataggi.
fn training_ui(m: &mut Machine) -> Result<String, String> {
    let mut lines = Vec::new();
    // (e OMEGA, sbloccato, come livello CH_OMEGA)
    for level in 0..=RUNGS.len() {
        lines.push(training_level(m, level).map_err(|e| format!("livello {}: {e}", level + 1))?);
    }
    Ok(format!("allenamento contro ogni avversario: {}", lines.join("; ")))
}

/// Il nome di un avversario nella presentazione (intro.s): la grafica TN_k_* di gen/assets.inc,
/// con i suoi colori, e la pagina k di titles.bin nei caratteri da TN_FIRST.
struct IntroName {
    /// la pagina di titles.bin della grafica TN_k_* (k: tipo, 7 OMEGA)
    page: usize,
    map: Vec<u8>,
    colors: Vec<u8>,
    w: usize,
    row: usize,
    col: usize,
    first: usize,
}

impl IntroName {
    fn new(kind: usize) -> Result<Self, String> {
        let inc = std::fs::read_to_string(c64_dir().join("gen/assets.inc")).map_err(|e| format!("assets.inc: {e}"))?;
        let get = |n: String| inc_const(&inc, &n).ok_or(format!("assets.inc: manca {n}"));
        let page = if kind == 7 { get("TTL_OMEGA".into())? } else { kind };
        Ok(Self {
            page,
            map: assets_list(&format!("TN_{kind}_MAP")),
            colors: assets_list(&format!("TN_{kind}_CLR")),
            w: get(format!("TN_{kind}_W"))?,
            row: get(format!("TN_{kind}_ROW"))?,
            col: get(format!("TN_{kind}_COL"))?,
            first: get("TN_FIRST".into())?,
        })
    }

    fn shown(&self, m: &Machine) -> bool {
        !self.map.is_empty()
            && title_at(m, &self.map, Some(&self.colors), self.w, self.row, self.col)
            && title_chars(m, self.page, 1, self.first, "nome").is_ok()
    }
}

/// Un allenamento contro l'avversario del livello `level` (da 0), per `training_ui`.
fn training_level(m: &mut Machine, level: usize) -> Result<String, String> {
    const CG_TRAIN: u8 = 3;
    const SID_SONG_GAME_OVER: u8 = 5;
    let rung = if level == OMEGA_LEVEL { OMEGA } else { RUNGS[level] };
    quiet_inputs(m);
    let table: Vec<u8> = (0..80).map(|i| m.read_u8("ch_table", i)).collect();
    let hi_next = m.read_u8("hi_next", 0);
    for (name, v) in [
        ("opt_mode", 2u8),
        ("opt_players", 4),
        ("opt_opp", level as u8 + 1),
        ("opt_level", 1),
        ("opt_free", 1),
        ("credits", 0),
        ("ctl_paddle", 0),
        ("hi_open", 0),
        ("hi_omega", 0),
        ("ch_wins", 5),
        ("state", ST_MENU),
    ] {
        m.write_u8(name, 0, v);
    }
    m.write_i32("ch_score", 0, 0);
    m.call("start_game");
    let loadout: Vec<u8> = rung.loadout.iter().map(|b| *b as u8).collect();
    let picked: Vec<u8> = (3..6).map(|i| m.read_u8("pk_chosen", i)).collect();
    if m.read_u8("ch_level", 0) as usize != level || picked != loadout || m.read_u8("pk_cursor", 1) != rung.kind as u8 {
        return Err(format!(
            "scelta: livello {}, bonus a destra {picked:?}, racchetta {} invece di quelli del livello {level}",
            m.read_u8("ch_level", 0),
            m.read_u8("pk_cursor", 1)
        ));
    }
    // niente tempo nelle scelte: il giocatore (porta 2) preme a turno fuoco e giù (conferma la
    // racchetta, poi prende tre bonus diversi), per due frame (sull'NTSC fuori partita la scena
    // salta un frame su sei)
    let mut tick = 0u32;
    let pick = |m: &mut Machine| {
        m.cpu.joy_port2 = match tick % 8 {
            0 | 1 => !0x10,
            4 | 5 => !0x02,
            _ => 0xFF,
        };
        tick += 1;
    };
    let mut worst = frames_until(m, 3000, "dalla scelta alla presentazione", pick, |m| m.read_u8("state", 0) == ST_INTRO)?;
    m.cpu.joy_port2 = 0xFF;
    if m.read_u8("cg_active", 0) != CG_TRAIN || m.cpu.read(VOICE_COUNT) != 0x4C {
        return Err(format!(
            "presentazione: cg_active {}, VOICE_COUNT ${:02X} (il player del primo livello)",
            m.read_u8("cg_active", 0),
            m.cpu.read(VOICE_COUNT)
        ));
    }
    // il fuoco del lato libero (porta 1) non porta uno sfidante
    frames_until(m, 30, "presentazione", fire_port1, |m| m.read_u8("state", 0) != ST_INTRO).ok();
    m.cpu.joy_port1 = 0xFF;
    if m.read_u8("state", 0) != ST_INTRO {
        return Err(format!("nella presentazione il fuoco della porta 1 porta allo stato {}", m.read_u8("state", 0)));
    }
    if !text_at(m, 0xC000, 3, 16, "TRAINING")
        || text_at(m, 0xC000, 23, 7, "SCORE")
        || text_at(m, 0xC000, 0, 1, "5 WINS")
        || text_at(m, 0xC000, 0, 26, "2")
    {
        return Err("presentazione: non TRAINING, o con i punti, i duelli vinti o l'invito per lo sfidante".into());
    }
    // il nome dell'avversario: la sua grafica, con i suoi caratteri dalla cartuccia (in un frame
    // almeno, a entrata finita)
    let joined = std::cell::Cell::new(false);
    let name = IntroName::new(if level == OMEGA_LEVEL { 7 } else { rung.kind as usize })?;
    let named = std::cell::Cell::new(false);
    worst = worst.max(frames_until(
        m,
        1500,
        "verso la partita",
        |m| {
            joined.set(joined.get() || m.read_u8("state", 0) == ST_CHALLENGER);
            named.set(named.get() || (m.read_u8("state", 0) == ST_INTRO && name.shown(m)));
        },
        |m| m.read_u8("state", 0) == ST_PLAY,
    )?);
    if !named.get() {
        return Err(format!("presentazione senza la grafica del nome di {}", rung.kind.name()));
    }
    let kind = m.read_u8("cfg_kinds", 4);
    let lo: Vec<u8> = (4..7).map(|i| m.read_u8("cfg_loadout", i)).collect();
    let (cpu, diff, points) = (m.read_u8("bm_cpu", 0), m.read_u8("bm_diff", 0), m.read_u8("win_points", 0));
    if joined.get()
        || kind != rung.kind as u8
        || lo != loadout
        || cpu != rung.cpu_at(1)
        || diff != rung.speed_at(1)
        || points as u16 != rung.points
        || m.read_u8("cpu_side", 0) != 4
    {
        return Err(format!(
            "partita: racchetta {kind}, bonus {lo:?}, CPU {cpu}, velocità {diff}, punti {points}, CPU al lato {} (sfidante {})",
            m.read_u8("cpu_side", 0),
            joined.get()
        ));
    }
    frames_until(m, 300, "partita", fire_port1, |m| m.read_u8("state", 0) != ST_PLAY).ok();
    m.cpu.joy_port1 = 0xFF;
    if m.read_u8("state", 0) != ST_PLAY || m.read_i32("ch_score", 0) != 0 {
        return Err(format!("partita: stato {}, punti arcade {}", m.read_u8("state", 0), m.read_i32("ch_score", 0)));
    }
    // la CPU vince: GAME OVER con la sua musica, poi l'attract
    m.write_u8("score", 4, points);
    frames_until(m, 10, "GAME OVER", |_| {}, |m| m.read_u8("state", 0) == ST_OVER)?;
    if m.read_u8("sid_song_n", 0) != SID_SONG_GAME_OVER {
        return Err(format!("GAME OVER dell'allenamento con la canzone {}", m.read_u8("sid_song_n", 0)));
    }
    worst = worst.max(frames_until(m, 600, "dopo il GAME OVER", |_| {}, |m| m.read_u8("state", 0) != ST_OVER)?);
    if worst > FRAME_BUDGET() {
        return Err(format!("un frame di {worst} cicli, oltre il budget"));
    }
    let after: Vec<u8> = (0..80).map(|i| m.read_u8("ch_table", i)).collect();
    if m.read_u8("state", 0) != 1 || m.read_u8("cg_active", 0) != 0 || after != table || m.read_u8("hi_next", 0) != hi_next {
        return Err(format!(
            "dopo il GAME OVER lo stato {} (cg_active {}), o la classifica cambiata",
            m.read_u8("state", 0),
            m.read_u8("cg_active", 0)
        ));
    }
    m.write_u8("opt_opp", 0, 0);
    m.write_u8("ch_wins", 0, 0);
    m.write_u8("hi_omega", 0, 0xFF);
    Ok(format!("{} {worst}", if level == OMEGA_LEVEL { "OMEGA" } else { rung.kind.name() }))
}

/// Sblocco dell'allenamento: il primo arrivo al finale lo salva nella flash con la classifica
/// (byte HI_OPEN del posto a $00), gli altri non salvano più.
fn unlock_ui(m: &mut Machine) -> Result<String, String> {
    const HI_BANK: usize = 16;
    const HI_OPEN: usize = 83;
    let close = |m: &mut Machine| -> Result<(), String> {
        frames_until(m, 100, "finale", |_| {}, |m| m.read_u8("e_part", 0) != 0)?;
        m.call("close_enter");
        frames_until(m, 100, "uscita dal finale", |_| {}, |m| m.read_u8("state", 0) != ST_ENDING)?;
        Ok(())
    };
    m.write_u8("hi_open", 0, 0xFF);
    let next = m.read_u8("hi_next", 0) as usize;
    ending_start(m, 1000)?;
    let slot = HI_BANK * EF_HALF + next * 128;
    let byte = m.cpu.ef.as_ref().map(|ef| ef.roml[slot + HI_OPEN]).unwrap_or(0xFF);
    if m.read_u8("hi_open", 0) != 0 || m.read_u8("hi_next", 0) as usize != next + 1 || byte != 0 {
        return Err(format!(
            "al finale: hi_open ${:02X}, hi_next {}, byte dello sblocco ${byte:02X}",
            m.read_u8("hi_open", 0),
            m.read_u8("hi_next", 0)
        ));
    }
    close(m)?;
    let after = m.read_u8("hi_next", 0);
    ending_start(m, 1000)?;
    if m.read_u8("hi_next", 0) != after {
        return Err("al secondo finale si salva di nuovo".into());
    }
    close(m)?;
    m.write_u8("hi_open", 0, 0xFF);
    Ok(format!("sblocco dell'allenamento salvato nella flash al primo finale (posto {next}, byte {HI_OPEN} a $00), poi non più"))
}

/// Scene del programma C64 (`state` in play.s).
const ST_MENU: u8 = 5;
const ST_COUNT: u8 = 6;
const ST_PLAY: u8 = 7;
const ST_PICK: u8 = 9;
const ST_INTRO: u8 = 10;
const ST_CLEAR: u8 = 11;
const ST_INITIALS: u8 = 13;
const ST_SCORES: u8 = 14;
const ST_CHALLENGER: u8 = 15;

/// Nuovo sfidante in CHALLENGE (challenge_ui.rs): entra il lato libero con il suo fuoco e un
/// credito (o in Free Play) nella presentazione, nel livello superato (non l'ultimo) e in partita;
/// sceglie solo lui; dopo la sfida il vincitore riprende dal suo lato con `Score::after_duel` punti
/// e la partita del livello mette bonus e racchette come `Rung::sides`, con la CPU dall'altro lato;
/// il campione battuto con un record mette le iniziali con il suo joystick.
fn challenger(m: &mut Machine) -> Result<(), String> {
    // un frame: comandi a riposo, le tabelle dei quadrati (la scelta della racchetta le copre: la
    // partita le aspetta), poi la scena
    let step = |m: &mut Machine, n: u32| {
        for _ in 0..n {
            m.cpu.joy_port1 = 0xFF;
            m.cpu.joy_port2 = 0xFF;
            m.call("read_input");
            m.call("math_step");
            m.call("run_scene");
        }
    };
    // una schermata della scala appena entrata: fino alla fine di pulizia e disegno (ch_phase, in
    // più frame), poi un frame
    let settle = |m: &mut Machine| {
        for _ in 0..8 {
            if m.read_u8("ch_phase", 0) == 0 {
                break;
            }
            step(m, 1);
        }
        step(m, 1);
    };
    // un frame con un comando appena premuto sul joystick di un lato (porta 2 a sinistra, 1 a
    // destra): `bits` del registro, 0x10 il fuoco, 0x02 giù
    let press = |m: &mut Machine, right: bool, bits: u8| {
        m.cpu.joy_port1 = 0xFF;
        m.cpu.joy_port2 = 0xFF;
        m.call("read_input");
        if right {
            m.cpu.joy_port1 = !bits;
        } else {
            m.cpu.joy_port2 = !bits;
        }
        m.call("read_input");
        m.call("run_scene");
        m.cpu.joy_port1 = 0xFF;
        m.cpu.joy_port2 = 0xFF;
    };
    let fire = |m: &mut Machine, right: bool| press(m, right, 0x10);
    let state = |m: &Machine| m.read_u8("state", 0);
    let expect = |what: &str, got: i64, want: i64| -> Result<(), String> {
        if got == want {
            Ok(())
        } else {
            Err(format!("{what}: {got} invece di {want}"))
        }
    };
    let u32_at = |m: &Machine, name: &str| m.read_i32(name, 0) as u32;
    let set_u32 = |m: &mut Machine, name: &str, v: u32| m.write_i32(name, 0, v as i32);
    let bonus = |c: u8| Bonus::PICKABLE.into_iter().find(|b| *b as u8 == c);
    // classifica iniziale (flash cancellata) e tastiera a riposo
    for i in 0..80 {
        let b = m.image_u8("table_init", i);
        m.write_u8("ch_table", i, b);
    }
    m.cpu.write(0xDC00, 0xFF);
    m.cpu.write(0xDC01, 0xFF);
    // posto in classifica come Table::rank (CH_TABLE se non entra)
    let table = Table::default();
    for best in [0, 1999, 2000, 2001, 9_999, 15_000, 20_000, 20_001, 300_000] {
        set_u32(m, "ch_best", best);
        m.call("table_rank");
        expect(
            &format!("posto in classifica di {best}"),
            m.cpu.a as i64,
            table.rank(best).unwrap_or(TABLE_SIZE) as i64,
        )?;
    }
    for (name, v) in [
        ("opt_mode", 2),
        ("opt_players", 4),
        ("opt_level", 1),
        ("opt_free", 0),
        ("credits", 0),
        ("ctl_paddle", 0),
    ] {
        m.write_u8(name, 0, v);
    }
    // il campione ha scelto a sinistra; la scala dal primo livello
    let champ = [Bonus::Smash, Bonus::Steer, Bonus::Ghost];
    for (k, b) in champ.iter().enumerate() {
        m.write_u8("pk_chosen", k as u16, *b as u8);
    }
    m.write_u8("cfg_kinds", 0, PaddleKind::Blaster as u8);
    m.call("ch_start");
    step(m, 3);
    expect("scena della presentazione", state(m) as i64, ST_INTRO as i64)?;
    // l'invito dal secondo frame dopo il disegno (ch_elapsed)
    settle(m);
    // invito sul lato libero (a destra), quando è acceso
    m.write_u8("frame_count", 0, 0x20);
    step(m, 1);
    if m.cpu.mem[0xC000 + 25] == 0 {
        return Err("nella presentazione manca P2 PRESS START in alto a destra".into());
    }
    // senza credito il fuoco del lato libero non fa entrare nessuno; il fuoco di chi gioca nemmeno
    fire(m, true);
    fire(m, false);
    expect("senza credito: scena", state(m) as i64, ST_INTRO as i64)?;
    m.write_u8("credits", 0, 1);
    fire(m, false);
    expect("fuoco del campione: scena", state(m) as i64, ST_INTRO as i64)?;
    fire(m, true);
    expect("con un credito: scena", state(m) as i64, ST_CHALLENGER as i64)?;
    expect("credito speso", m.read_u8("credits", 0) as i64, 0)?;
    // HERE COMES A NEW CHALLENGER!: pulizia, due copie dalla cartuccia (caratteri e codice della
    // targa), il disegno; poi la scelta del solo sfidante
    step(m, 5);
    let inc = std::fs::read_to_string(c64_dir().join("gen/assets.inc")).unwrap_or_default();
    let solid = inc_const(&inc, "CH_SOLID").unwrap_or(256) as u8;
    let screen = &m.cpu.mem[0xC000..0xC000 + 1000];
    if !screen.contains(&solid) {
        return Err("schermata del nuovo sfidante senza le bande".into());
    }
    plate_ok(m, &inc)?;
    step(m, 160);
    if m.read_u8("sh_xexp", 0) & 0x0F != 0 || m.cpu.mem[0xD01B] != 0 {
        return Err("nelle scelte dopo la targa i suoi sprite espansi o dietro i caratteri".into());
    }
    expect("dopo HERE COMES A NEW CHALLENGER!", state(m) as i64, ST_PICK as i64)?;
    expect("lato che non sceglie", m.read_u8("pk_fixed", 0) as i64, 0)?;
    expect("bonus del campione", m.read_u8("pk_count", 0) as i64, 3)?;
    // prima la racchetta (quella del campione già confermata), poi i bonus
    expect("prima scelta dello sfidante: la racchetta", m.read_u8("pk_kind", 0) as i64, 1)?;
    expect("racchetta del campione", m.read_u8("pk_cursor", 0) as i64, PaddleKind::Blaster as i64)?;
    // niente tempo: lo sfidante conferma la racchetta con il fuoco (finché non risulta scelta)
    let mut frames = 0;
    while m.read_u8("pk_kind", 0) != 0 && frames < 1000 {
        if frames % 10 == 9 && m.read_u8("pk_ok", 1) == 0 {
            fire(m, true);
        }
        step(m, 1);
        frames += 1;
    }
    // colonne: quelli del campione accesi (bianchi), dello sfidante solo la riga del cursore
    step(m, 5);
    for (i, b) in Bonus::PICKABLE.iter().enumerate() {
        for (side, lit) in [(0u16, champ.contains(b)), (1, i == 0)] {
            let color = m.cpu.read(0xD800 + (8 + 2 * i as u16) * 40 + 7 + 20 * side) & 0x0F;
            expect(
                &format!("colore di {} nella colonna {side} della scelta", b.name()),
                color as i64,
                if lit { 1 } else { 15 },
            )?;
        }
    }
    // lo sfidante prende i primi tre bonus (fuoco, giù, fuoco, giù, fuoco)
    for (k, bits) in [0x10, 0x02, 0x10, 0x02, 0x10].into_iter().enumerate() {
        press(m, true, bits);
        step(m, 3);
        let _ = k;
    }
    expect("bonus presi dallo sfidante", m.read_u8("pk_count", 1) as i64, 3)?;
    // dopo le scelte lo schermo VS della sfida (kvs.s, nella presentazione), poi la partita
    let (mut frames, mut vs) = (0, false);
    while (state(m) == ST_PICK || state(m) == ST_INTRO) && frames < 3000 {
        vs |= state(m) == ST_INTRO && m.read_u8("in_vs", 0) == 1;
        step(m, 1);
        frames += 1;
    }
    expect("schermo VS della sfida", vs as i64, 1)?;
    expect("scena dopo le scelte dello sfidante e il VS", state(m) as i64, ST_COUNT as i64)?;
    for (k, b) in champ.iter().enumerate() {
        expect("bonus del campione nella sfida", m.read_u8("cfg_loadout", k as u16) as i64, *b as i64)?;
    }
    expect(
        "racchetta del campione nella sfida",
        m.read_u8("cfg_kinds", 0) as i64,
        PaddleKind::Blaster as i64,
    )?;
    expect("CPU nella sfida", m.read_u8("cpu_side", 0) as i64, 0xFF)?;
    expect("musica della sfida: il tema di un avversario", m.read_u8("sid_song_n", 0) as i64, SID_SONG_THEME as i64)?;
    expect("punti della sfida", m.read_u8("win_points", 0) as i64, RUNGS[0].points as i64)?;
    let chal: Vec<Bonus> = (0..3).filter_map(|k| bonus(m.read_u8("cfg_loadout", 4 + k))).collect();
    let chal_kind = PaddleKind::ALL[m.read_u8("cfg_kinds", 4) as usize % 7];
    if chal.len() != 3 {
        return Err("bonus dello sfidante non validi".into());
    }
    // lo sfidante (destra) vince; il campione non entra in classifica
    let set_scores = |m: &mut Machine, left: u8, right: u8| {
        m.write_u8("score", 0, left);
        m.write_u8("score", 1, 0);
        m.write_u8("score", 4, right);
        m.write_u8("score", 5, 0);
    };
    set_u32(m, "ch_score", 1000);
    set_u32(m, "ch_best", 1000);
    set_scores(m, 2, 5);
    m.call("ch_after");
    expect("dopo la sfida vinta dallo sfidante", state(m) as i64, ST_INTRO as i64)?;
    expect("lato di chi gioca", m.read_u8("ch_side", 0) as i64, 4)?;
    expect("punti dello sfidante", u32_at(m, "ch_score") as i64, Score::after_duel(1000, false, 0) as i64)?;
    expect("miglior punteggio dello sfidante", u32_at(m, "ch_best") as i64, Score::duel_bonus(0) as i64)?;
    // la partita del livello con chi gioca a destra: come Rung::sides, la CPU a sinistra
    m.call("ch_begin");
    expect("CPU della partita", m.read_u8("cpu_side", 0) as i64, 0)?;
    let chal: [Bonus; 3] = [chal[0], chal[1], chal[2]];
    let (loadouts, kinds) = RUNGS[0].sides(Side::Right, chal, Some(chal_kind));
    let seed = u32_at(m, "cfg_seed");
    let g = Match::new_next_paddles(c64_params(RUNGS[0].speed_at(1)), loadouts, kinds, seed);
    if let Some(d) = mismatch(m, &g, 0) {
        return Err(format!("partita con chi gioca a destra diversa dal core:
    {d}"));
    }
    // un'altra sfida: il campione (ora a destra) vince al livello 4
    m.write_u8("cg_active", 0, 2);
    m.write_u8("ch_level", 0, 3);
    set_u32(m, "ch_score", 5000);
    set_scores(m, 1, 5);
    m.call("ch_after");
    expect("lato del campione che vince", m.read_u8("ch_side", 0) as i64, 4)?;
    expect("punti del campione", u32_at(m, "ch_score") as i64, Score::after_duel(5000, true, 3) as i64)?;
    // il campione perde con un record: iniziali con il suo joystick (destra), poi riprende lo
    // sfidante da sinistra
    m.write_u8("cg_active", 0, 2);
    set_u32(m, "ch_score", 30_000);
    set_u32(m, "ch_best", 30_000);
    set_scores(m, 5, 3);
    m.call("ch_after");
    expect("campione battuto con un record", state(m) as i64, ST_INITIALS as i64)?;
    step(m, 1);
    settle(m);
    for _ in 0..3 {
        fire(m, false);
    }
    expect("iniziali con il joystick del vincitore", m.read_u8("ch_pos", 0) as i64, 0)?;
    for _ in 0..3 {
        fire(m, true);
    }
    expect("dopo le iniziali del perdente", state(m) as i64, ST_INTRO as i64)?;
    expect("record del perdente", m.read_i32("ch_table", 3) as i64, 30_000)?;
    expect("lato dello sfidante che ha vinto", m.read_u8("ch_side", 0) as i64, 0)?;
    expect("punti dello sfidante", u32_at(m, "ch_score") as i64, Score::duel_bonus(3) as i64)?;
    // livello superato: entra lo sfidante, la sfida è al livello dopo (in Free Play)
    m.write_u8("opt_free", 0, 1);
    m.write_u8("cg_active", 0, 1);
    m.write_u8("ch_level", 0, 2);
    set_scores(m, 5, 1);
    m.call("ch_after");
    expect("livello superato", state(m) as i64, ST_CLEAR as i64)?;
    step(m, 1);
    settle(m);
    fire(m, true);
    expect("sfidante nel livello superato", state(m) as i64, ST_CHALLENGER as i64)?;
    expect("livello della sfida", m.read_u8("ch_level", 0) as i64, 3)?;
    // dopo l'ultimo livello no: c'è il finale (poi chiuso)
    m.write_u8("cg_active", 0, 1);
    m.write_u8("ch_level", 0, 6);
    set_scores(m, 5, 0);
    m.call("ch_after");
    step(m, 1);
    settle(m);
    fire(m, true);
    expect("sfidante dopo l'ultimo livello", state(m) as i64, ST_ENDING as i64)?;
    while m.read_u8("e_part", 0) == 0 {
        step(m, 1);
    }
    m.call("close_enter");
    for _ in 0..10 {
        step(m, 1);
    }
    m.call("math_ensure");
    // in partita contro la CPU: la partita si interrompe, i punti fatti restano
    m.write_u8("cg_active", 0, 1);
    m.write_u8("ch_level", 0, 1);
    m.call("ch_begin");
    set_u32(m, "ch_score", 777);
    set_u32(m, "ch_best", 0);
    step(m, 2);
    fire(m, true);
    expect("sfidante in partita", state(m) as i64, ST_CHALLENGER as i64)?;
    expect("punti fatti prima della sfida", u32_at(m, "ch_best") as i64, 777)?;
    expect("livello raggiunto", m.read_u8("ch_best_lv", 0) as i64, 2)?;
    // nella sfida non entra nessun altro
    m.write_u8("cg_active", 0, 2);
    m.call("ch_begin");
    m.write_u8("cg_active", 0, 2);
    step(m, 2);
    fire(m, true);
    expect("sfidante durante la sfida", state(m) as i64, ST_COUNT as i64)?;
    m.write_u8("opt_free", 0, 1);
    Ok(())
}

/// Cicli utili di un frame: PAL 312 righe da 63 cicli, NTSC 263 da 65, meno le righe dei caratteri e
/// gli sprite (`paddws_c64::frame_budget`).
const FRAME_BUDGET: fn() -> u64 = frame_budget;
/// Set di caratteri del programma (CHARSET di video.s) e due suoi caratteri (gen/assets.inc,
/// controllati in `frames`)
const CHARSET: usize = 0xC800;
const CH_WALL: usize = 3;

/// CH_GRID_T di gen/assets.inc.
fn ch_grid_t() -> usize {
    static V: std::sync::OnceLock<usize> = std::sync::OnceLock::new();
    *V.get_or_init(|| {
        let inc = std::fs::read_to_string(c64_dir().join("gen/assets.inc")).unwrap_or_default();
        inc_const(&inc, "CH_GRID_T").expect("assets.inc: manca CH_GRID_T")
    })
}

/// Codice nella ROM dei caratteri (set maiuscolo) del carattere ASCII `c` (32-95).
fn rom_code(c: u8) -> usize {
    if c >= 64 { (c - 64) as usize } else { c as usize }
}

/// Quattro pixel doppi: i bit del nibble `n` (bit 3 a sinistra) ciascuno due volte.
fn double_nibble(n: u8) -> u8 {
    (0..4).fold(0, |acc, b| if n >> b & 1 != 0 { acc | 3 << (2 * b) } else { acc })
}

/// I glifi che il programma deve prendere dalla ROM dei caratteri (qui la finta del banco di
/// prova, `fake_char_rom`), per codice del set: il font 1x (FONT_MAP di gen/assets.inc, il glifo
/// della ROM del suo carattere ASCII, trovato qui senza FONT_ROM) e le lettere 2x da `big_first`
/// (quattro caratteri per lettera, dal carattere del font `big_src`, ogni pixel 2x2).
fn rom_glyphs(m: &Machine, big_src: &[u8], big_first: usize) -> Vec<(usize, [u8; 8])> {
    let rom = &m.cpu.char_rom;
    let mut out: Vec<(usize, [u8; 8])> = Vec::new();
    for (i, &code) in assets_list("FONT_MAP").iter().enumerate() {
        if code != 0 {
            let a = rom_code(32 + i as u8) * 8;
            out.push((code as usize, rom[a..a + 8].try_into().unwrap()));
        }
    }
    for (k, &src) in big_src.iter().enumerate() {
        let g = out.iter().find(|(c, _)| *c == src as usize).map(|(_, g)| *g).unwrap_or([0; 8]);
        for q in 0..4 {
            let glyph = std::array::from_fn(|r| {
                let b = g[(q / 2) * 4 + r / 2];
                double_nibble(if q % 2 == 0 { b >> 4 } else { b & 15 })
            });
            out.push((big_first + 4 * k + q, glyph));
        }
    }
    out
}

/// I glifi della ROM del set del programma (font e lettere 2x di BIG2_SRC).
fn program_glyphs(m: &Machine) -> Vec<(usize, [u8; 8])> {
    let inc = std::fs::read_to_string(c64_dir().join("gen/assets.inc")).unwrap_or_default();
    rom_glyphs(m, &assets_list("BIG2_SRC"), inc_const(&inc, "BIG2_FIRST").unwrap_or(0))
}

/// Errore se nel set di caratteri a $C800 un glifo di `glyphs` non è quello giusto.
fn check_glyphs(m: &Machine, glyphs: &[(usize, [u8; 8])], what: &str) -> Result<(), String> {
    if glyphs.is_empty() {
        return Err(format!("{what}: nessun glifo della ROM in gen/assets.inc"));
    }
    match glyphs.iter().find(|(c, g)| m.cpu.mem[CHARSET + 8 * c..CHARSET + 8 * c + 8] != g[..]) {
        Some((c, _)) => Err(format!("{what}: il carattere {c} non ha il glifo della ROM dei caratteri")),
        None => Ok(()),
    }
}

/// Il set di caratteri del programma come deve essere: gen/charset.bin (nel .prg) con i glifi della ROM.
fn program_charset(m: &Machine) -> Vec<u8> {
    let at = m.addr("charset_data") as usize - 0x0801;
    let mut cs = m.image[at..at + 0x800].to_vec();
    for (c, g) in program_glyphs(m) {
        cs[8 * c..8 * c + 8].copy_from_slice(&g);
    }
    cs
}

/// Racchette in partita NEXT: le immagini preparate a inizio partita diventano pronte per tutti e
/// due i lati e la racchetta sinistra (sprite 3) ha sempre un'immagine non vuota, letta nella RAM
/// che vede il VIC (anche sotto l'I/O), salvo il lampo del punto e il salto del TELEPORT.
#[derive(Default)]
struct PadCheck {
    frames: u32,
    hidden: u32,
    ready: bool,
}

impl PadCheck {
    fn check(&mut self, m: &Machine) {
        self.ready |= m.read_u8("pp_ready", 0) == 1 && m.read_u8("pp_ready", 1) == 1;
        if m.read_u8("sh_bg", 0) != 0 || m.read_u8("wp_on", 0) != 0 {
            return;
        }
        let ptr = m.read_u8("sh_ptr", 3) as usize;
        let lit = (0..63).any(|i| {
            let a = 0xC000 + ptr * 64 + i;
            let v = if (0xD000..0xE000).contains(&a) {
                m.cpu.under_io[a - 0xD000]
            } else {
                m.cpu.mem[a]
            };
            v != 0
        });
        self.frames += 1;
        self.hidden += (m.read_u8("sh_enable", 0) & 0b1000 == 0 || !lit) as u32;
    }

    fn ok(&self, what: &str) -> bool {
        if !self.ready {
            println!("FAIL: {what}: le immagini preparate delle racchette non sono mai pronte");
        }
        if self.hidden > 0 {
            println!(
                "FAIL: {what}: racchetta sinistra assente in {} frame su {}",
                self.hidden, self.frames
            );
        }
        self.ready && self.hidden == 0
    }
}

/// Salto del TELEPORT in partita NEXT: in ogni frame del salto c'è almeno un'astronave (quella che si
/// scompone nella racchetta o quella che si ricompone nello sprite dell'icona), accesa e con il suo
/// puntatore; all'inizio della scomposizione (wp_sunk sotto 8: tutte le righe ancora piene o in
/// luce) e alla fine della ricomposizione (wp_out da 30: tutte piene) la sua immagine ha dei pixel.
/// Prima il disegno aspettava un frame che non arrivava mai (frame_late era sempre vero a quel
/// punto del frame) e la racchetta spariva.
#[derive(Default)]
struct WarpCheck {
    frames: u32,
    shown: u32,
    jumps: u32,
    active: bool,
    bad: Vec<String>,
}

impl WarpCheck {
    const SPN_PAD: u16 = 3;
    const SPN_ICON: u16 = 1;

    fn check(&mut self, m: &Machine) {
        if m.read_u8("wp_on", 0) == 0 {
            self.active = false;
            return;
        }
        if m.read_u8("sh_bg", 0) != 0 {
            return;
        }
        if !self.active {
            self.active = true;
            self.jumps += 1;
        }
        self.frames += 1;
        let side = m.read_u8("wp_side", 0) as u16;
        let enable = m.read_u8("sh_enable", 0);
        let drawn = |bytes: &[u8]| bytes.iter().any(|&b| b != 0);
        // senza un'immagine da cui partire (wp_src 0) le astronavi sono vuote: sparisce e ricompare
        let src = m.read_u8("wp_src", 0) != 0;
        let mut any = false;
        if m.read_u8("wp_en", 0) != 0 {
            any = true;
            let base = m.read_u8("img_base", side);
            let img: Vec<u8> = (0..63).map(|i| m.read_u8("sh_img", base as u16 + i)).collect();
            let empty = src && m.read_u8("wp_sunk", 0) < 8 && !drawn(&img);
            if enable & (1 << (Self::SPN_PAD + side)) == 0 || empty {
                let why = if empty { "vuoto" } else { "spento" };
                self.bad.push(format!("astronave che sparisce (lato {side}): sprite {why}"));
            }
            if m.read_u8("sh_ptr", Self::SPN_PAD + side) != m.read_u8("pad_slot", side) {
                self.bad
                    .push(format!("astronave che sparisce (lato {side}): puntatore sbagliato"));
            }
        }
        if m.read_u8("wp_ex", 0) != 0 {
            any = true;
            let ptr = m.read_u8("sh_ptr", Self::SPN_ICON + side) as usize;
            let img: Vec<u8> = (0..63).map(|i| m.cpu.mem[0xC000 + ptr * 64 + i]).collect();
            let empty = src && m.read_u8("wp_out", 0) >= 30 && !drawn(&img);
            if enable & (1 << (Self::SPN_ICON + side)) == 0 || empty {
                let why = if empty { "vuoto" } else { "spento" };
                self.bad.push(format!("astronave che compare (lato {side}): sprite {why}"));
            }
        }
        self.shown += any as u32;
    }

    fn ok(&self) -> bool {
        if self.frames == 0 {
            println!("FAIL: NEXT: il salto del TELEPORT non capita mai");
            return false;
        }
        // i frame troppo carichi tengono l'immagine di prima: al massimo il primo frame di ogni
        // salto resta senza pezzi (con il salto in dash accelerato un salto dura circa 6 frame)
        if self.shown + self.jumps < self.frames {
            println!(
                "FAIL: NEXT: salto del TELEPORT disegnato in {} frame su {} ({} salti)",
                self.shown, self.frames, self.jumps
            );
            return false;
        }
        if let Some(b) = self.bad.first() {
            println!("FAIL: NEXT: salto del TELEPORT: {b} ({} frame)", self.bad.len());
            return false;
        }
        true
    }
}

/// Cometa del SUPER in partita NEXT: la palla è uno sprite della coda (cache a $E000), hires ed
/// espanso, con la testa (5x5 pixel doppi) e almeno in metà dei frame anche la coda dietro, in
/// quasi tutti i frame del volo tranne quelli dopo un rimbalzo in cui la cometa nuova non è ancora
/// disegnata (lì la palla semplice): il primo, e quelli dopo un frame troppo carico per disegnarla
/// (trail_end la disegna solo se comincia entro TRAIL_LATE, circa 12.500 cicli). Mai uno sprite
/// della coda con la palla nell'angolo di un'altra direzione: la coda finirebbe davanti alla palla.
#[derive(Default)]
struct CometCheck {
    frames: u32,
    shown: u32,
    tailed: u32,
    /// palla semplice dopo un cambio di direzione (sprite della coda di un'altra direzione)
    waiting: u32,
    /// di questi, quelli dopo un frame già in attesa che aveva il tempo per disegnarla
    missed: u32,
    prev_waiting: bool,
    /// sprite della coda con la palla nell'angolo di un'altra direzione
    wrong: u32,
    /// frame con uno sprite della coda (grigia o cometa) e quelli nell'angolo sbagliato
    trails: u32,
    trails_wrong: u32,
    /// cicli del frame controllato
    cur: u64,
}

/// L'angolo della palla nello sprite della coda (trail_dir di video.s): bit 7 il segno di vx, bit
/// 0-1 vy (0 sale, 1 orizzontale, 2 scende).
fn trail_dir(m: &Machine) -> u8 {
    let vy = (0..4).fold(0u32, |v, i| v | (m.read_u8("ball_vy", i) as u32) << (8 * i)) as i32;
    let y = if vy < 0 { 2 } else if vy == 0 { 1 } else { 0 };
    y | (m.read_u8("ball_vx", 3) & 0x80)
}

impl CometCheck {
    /// SP_TRAIL0 e TRAIL_BUFS di video.s: sprite della coda a $E000
    const SP_TRAIL0: u8 = 128;
    const TRAIL_BUFS: u8 = 4;
    /// cicli del frame sotto i quali trail_end ha avuto il tempo di disegnare (TRAIL_LATE di video.s:
    /// comincia entro il budget meno circa 5.500 cicli; PAL 12.000)
    fn light() -> u64 {
        frame_budget() - 6_000
    }
    /// KEEP_SPRITES_LINE di play.s in cicli: oltre, gli sprite possono restare quelli del frame prima
    /// (il budget meno KEEP_SPRITES_CYC)
    fn keep_sprites() -> u64 {
        keep_sprites()
    }

    /// `prev`: cicli del frame prima (è lì che trail_end disegna la cometa che si vede in questo).
    fn check(&mut self, m: &Machine, prev: u64) {
        let waited = std::mem::replace(&mut self.prev_waiting, false);
        let ptr = m.read_u8("sh_ptr", 0);
        if m.read_u8("sh_enable", 0) & 1 != 0 && (Self::SP_TRAIL0..Self::SP_TRAIL0 + Self::TRAIL_BUFS).contains(&ptr) {
            self.trails += 1;
            // (in un frame oltre KEEP_SPRITES di play.s gli sprite possono essere quelli del frame
            // prima, con la palla dov'era: lì l'angolo è quello di prima, e va bene)
            self.trails_wrong += (m.read_u8("tr_shdir", 0) != trail_dir(m) && self.cur <= Self::keep_sprites()) as u32;
        }
        if m.read_u8("nx_super", 0) == 0
            || m.read_u8("nx_super_a", 0) != 2
            || m.read_u8("sh_bg", 0) != 0
            || m.read_u8("sh_enable", 0) & 1 == 0
        {
            return;
        }
        self.frames += 1;
        let expanded = m.read_u8("sh_xexp", 0) & m.read_u8("sh_yexp", 0) & 1 != 0;
        let hires = m.read_u8("sh_mc", 0) & 1 == 0;
        let same_dir = m.read_u8("tr_shdir", 0) == trail_dir(m);
        if !(Self::SP_TRAIL0..Self::SP_TRAIL0 + Self::TRAIL_BUFS).contains(&ptr) || !expanded || !hires {
            // in attesa anche al lancio del SUPER, finché non c'è una cometa (lo sprite che si vede è
            // la coda grigia: sull'NTSC la prima cometa arriva in due metà, trail_end)
            if !same_dir || m.read_u8("tr_shcm", 0) == 0 {
                self.waiting += 1;
                self.missed += (waited && prev < Self::light()) as u32;
                self.prev_waiting = true;
            }
            return;
        }
        if !same_dir {
            self.wrong += 1;
            return;
        }
        let bits: u32 = (0..63)
            .map(|i| m.cpu.mem[0xC000 + ptr as usize * 64 + i].count_ones())
            .sum();
        if bits >= 25 {
            self.shown += 1;
            self.tailed += (bits > 25) as u32;
        }
    }

    fn ok(&self) -> bool {
        if self.frames == 0 {
            println!("FAIL: NEXT: la cometa del SUPER non vola mai");
            return false;
        }
        if self.trails_wrong > 0 {
            println!(
                "FAIL: NEXT: coda della palla dalla parte sbagliata (palla nell'angolo di un'altra direzione) in {} frame su {}",
                self.trails_wrong, self.trails
            );
            return false;
        }
        let flying = self.frames - self.waiting;
        // (e in almeno metà del volo: non sempre in attesa). Sull'NTSC no: i frame del SUPER costano
        // circa 13.000 cicli, oltre light(), e dopo un rimbalzo la cometa nuova aspetta un frame
        // leggero, che in un volo lungo può non arrivare per più di un secondo (budget NTSC in
        // sospeso); resta il controllo sui frame che avevano il tempo (missed)
        if self.wrong > 0
            || self.shown * 10 < flying * 9
            || (!ntsc() && self.shown * 2 < self.frames)
            || self.tailed * 2 < flying
            || self.missed * 10 > self.frames
        {
            println!(
                "FAIL: NEXT: cometa del SUPER in {} frame su {} ({} in attesa dopo un rimbalzo, {} con il tempo per disegnarla), con la coda in {}, con la palla nell'angolo sbagliato in {}",
                self.shown, self.frames, self.waiting, self.missed, self.tailed, self.wrong
            );
            return false;
        }
        println!(
            "  coda della palla: {} frame, mai dalla parte sbagliata; cometa del SUPER in {} frame su {} (palla semplice in {} dopo un rimbalzo, finché la cometa nuova non è disegnata; {} con il tempo per disegnarla)",
            self.trails, self.shown, self.frames, self.waiting, self.missed
        );
        true
    }
}

/// Gesto del joystick per il giocatore sinistro nel banco frames: con la palla in arrivo, ogni
/// tanto una delle due mezzelune (come `JoySim`), poi tutto rilasciato. Bit a 1 = premuto; None
/// fuori da un gesto.
fn gesture_joy(m: &Machine, rng: &mut Rng, queue: &mut std::collections::VecDeque<u8>) -> Option<u8> {
    if let Some(bits) = queue.pop_front() {
        return Some(bits);
    }
    let coming = m.read_i32("ball_vx", 0) < 0;
    if m.read_u8("state", 0) != ST_PLAY || !coming || rng.below(20) != 0 {
        return None;
    }
    let (down, fwd, fire) = (JoySim::DOWN, JoySim::RIGHT, JoySim::FIRE);
    let steps = if rng.below(2) == 1 {
        [fwd, down, down | fwd]
    } else {
        [down, down | fwd, fwd]
    };
    for (k, dir) in steps.into_iter().enumerate() {
        let n = 1 + rng.below(3) as usize;
        for f in 0..n {
            queue.push_back(if k == 2 && f == n - 1 { dir | fire } else { dir });
        }
    }
    queue.push_back(0);
    Some(0)
}

/// Barra e icone delle mosse speciali da c64/gen/assets.inc: primo carattere della barra
/// (BAR_C0) e le quattro icone (SUPER_ICONS, 8 righe ciascuna).
fn assets_supers() -> &'static (u8, Vec<u8>) {
    static ASSETS: std::sync::OnceLock<(u8, Vec<u8>)> = std::sync::OnceLock::new();
    ASSETS.get_or_init(|| {
        let inc = std::fs::read_to_string(c64_dir().join("gen/assets.inc")).unwrap_or_default();
        let c0 = inc_const(&inc, "BAR_C0").unwrap_or(0) as u8;
        let icons = inc
            .lines()
            .find_map(|l| l.strip_prefix(".define SUPER_ICONS "))
            .map(|l| {
                l.split(',')
                    .filter_map(|v| u8::from_str_radix(v.trim().trim_start_matches('$'), 16).ok())
                    .collect()
            })
            .unwrap_or_default();
        (c0, icons)
    })
}

/// Mosse speciali a schermo nelle partite del banco frames (supers.s): codice delle mosse al suo
/// posto, mosse armate (e quelle del giocatore sinistro), barre (caratteri e colori), icone e
/// racchetta gialla, scritta, palla gialla, effetti del SID partiti; frame con le mosse e il più
/// pesante.
#[derive(Default)]
struct SuperFrames {
    frames: u32,
    worst: u64,
    code_bad: u32,
    armed: u32,
    by_p1: u32,
    bars: u32,
    icons: u32,
    yellow_pad: u32,
    labels: u32,
    yellow_ball: u32,
    sounds: u32,
    last_arm: [u8; 2],
    last_fxp: u8,
}

impl SuperFrames {
    /// BAR_ROW, BAR_COL_L e BAR_COL_R di supers.s
    const BAR: [u16; 2] = [0xC000 + 40 + 6, 0xC000 + 40 + 30];

    fn check(&mut self, m: &Machine, cycles: u64) {
        if m.read_u8("state", 0) != ST_PLAY || m.read_u8("m_next", 0) == 0 || m.read_u8("sm_on", 0) == 0 {
            return;
        }
        self.frames += 1;
        self.worst = self.worst.max(cycles);
        if self.frames % 50 == 1
            && let Some((at, code)) = m.moved_segment("SMCODE")
            && code.iter().enumerate().any(|(i, &b)| m.cpu.mem[at as usize + i] != b)
        {
            self.code_bad += 1;
        }
        let (c0, icons) = assets_supers();
        let c0 = *c0;
        let bars = Self::BAR
            .iter()
            .all(|&a| (0..4).all(|k| (c0..c0 + 5).contains(&m.cpu.mem[a as usize + k])));
        self.bars += bars as u32;
        for side in 0..2usize {
            let arm = m.read_u8("sm_arm", side as u16 * 4);
            if arm != 0 && self.last_arm[side] == 0 {
                self.armed += 1;
                self.by_p1 += (side == 0 && m.read_u8("cpu_side", 0) != 0) as u32;
            }
            self.last_arm[side] = arm;
            // l'icona della mossa (righe 0-7 della prima colonna dello sprite dell'icona), per
            // mossa e lato
            let sprite = 1 + side as u16;
            let img = 0xC000 + m.read_u8("sh_ptr", sprite) as usize * 64;
            let want = &icons[((arm >= 3) as usize * 2 + side) * 8..][..8];
            if arm != 0
                && m.read_u8("sh_enable", 0) & (1 << sprite) != 0
                && (0..8).all(|r| m.cpu.mem[img + 3 * r] == want[r])
            {
                self.icons += 1;
            }
            if arm != 0 && arm & 1 == 0 && m.read_u8("sh_col", 3 + side as u16) & 15 == 7 {
                self.yellow_pad += 1;
            }
        }
        if m.read_u8("mv_st", 0) | m.read_u8("mv_st", 1) != 0 {
            self.labels += 1;
        }
        if m.read_u8("sm_fl", 0) != 0 && m.read_u8("sh_col", 0) & 15 == 7 {
            self.yellow_ball += 1;
        }
        let fxp = m.read_u8("sm_fxp", 0);
        if fxp == 0 && self.last_fxp != 0 {
            let ptr = m.read_u8("ch_start_lo", 3) as u16 | (m.read_u8("ch_start_hi", 3) as u16) << 8;
            self.sounds += [m.addr("sid_track_move"), m.addr("sid_track_special")].contains(&ptr) as u32;
        }
        self.last_fxp = fxp;
    }

    fn line(&self) -> String {
        format!(
            "{} frame (cicli max {}), {} mosse armate ({} di P1 con il gesto), barre in {} frame, icona in {}, racchetta gialla in {}, scritta in {}, palla gialla in {}, {} effetti del SID",
            self.frames,
            self.worst,
            self.armed,
            self.by_p1,
            self.bars,
            self.icons,
            self.yellow_pad,
            self.labels,
            self.yellow_ball,
            self.sounds
        )
    }

    fn ok(&self) -> Result<(), String> {
        if self.code_bad > 0 {
            return Err(format!(
                "codice delle mosse diverso da quello del .prg in {} controlli",
                self.code_bad
            ));
        }
        let all = [
            self.armed,
            self.by_p1,
            self.icons,
            self.yellow_pad,
            self.labels,
            self.yellow_ball,
            self.sounds,
        ];
        if all.contains(&0) || self.bars * 10 < self.frames * 9 {
            return Err(format!("qualcosa non compare: {}", self.line()));
        }
        Ok(())
    }
}

/// Le scene del C64 (`state`), per nome.
const SCENES: [&str; 12] = [
    "boot",
    "strisce",
    "logo",
    "titolo",
    "partita, cometa del SUPER", // (4 libero: nel profilo, i frame della partita con la cometa in volo)
    "menu",
    "conto",
    "partita",
    "game over",
    "scelta NEXT",
    "CHALLENGE",
    "finale",
];

/// Profilo dei frame pesanti di `frames`, per scena: frame, cicli, cicli per indirizzo di
/// istruzione, cicli inclusivi per subroutine.
type Heavy = (u32, u64, Vec<u64>, Vec<u64>, Vec<u64>);

thread_local! {
    static HEAVY: std::cell::RefCell<Vec<Heavy>> = std::cell::RefCell::new(vec![(0, 0, Vec::new(), Vec::new(), Vec::new()); 12]);
    /// Per scena, i cicli di ogni frame fino a `mark_label` (scene_done: la parte del frame che non
    /// si rimanda, cioè comandi, tick, CPU).
    static FIRM: std::cell::RefCell<Vec<Vec<u64>>> = std::cell::RefCell::new(vec![Vec::new(); 12]);
    /// la chiamata più lunga per subroutine in tutti i frame profilati
    static LONGEST: std::cell::RefCell<Vec<u64>> = const { std::cell::RefCell::new(Vec::new()) };
}

/// KEEP_SPRITES_LINE di play.s in cicli: oltre, il frame tiene gli sprite del frame prima (il budget
/// meno KEEP_SPRITES_CYC: PAL 3.900, NTSC 1.700, dove sprite e HUD si fanno anche sforando).
fn keep_sprites() -> u64 {
    frame_budget() - if ntsc() { 1_700 } else { 3_900 }
}

/// Parte del frame che non si rimanda oltre la quale il tick è pesantissimo: sprite, HUD e il resto
/// (fino a circa 4.500 cicli) non ci stanno più nel budget, e il frame può sforare (spill_max).
fn heavy_tick_from() -> u64 {
    frame_budget() - 4_500
}

/// Cicli oltre il budget ammessi a un frame di partita con un tick pesantissimo (`frames`): il
/// frame dopo parte subito, ancora nel bordo in alto, scrive gli sprite prima della prima riga
/// visibile (la 51) e ha meno tempo per il suo lavoro rimandabile (le soglie contano le righe
/// dall'interrupt); il ritardo si somma finché un frame lo recupera. Nessun frame perso. Solo
/// NTSC, dove il tick più pesante non sta sempre nel frame (sul PAL 0). Nelle schermate no: lì
/// il lavoro si divide, e un frame in ritardo cambierebbe per esempio i colori dei titoli di coda
/// con il raster già sul testo.
fn spill_max() -> u64 {
    if ntsc() { 2_500 } else { 0 }
}

/// PADDWS_C64_HEAVY=N: profilo dei frame oltre N cicli, scena per scena, per cercare i cicli da
/// togliere (i tempi dell'NTSC).
fn heavy_limit() -> Option<u64> {
    std::env::var("PADDWS_C64_HEAVY").ok().and_then(|v| v.parse().ok())
}

/// PADDWS_C64_MARK=etichetta: dove finisce la parte del frame contata in FIRM (scene_done se manca;
/// per esempio trail_layout, dove trail_end comincia la coda della palla).
fn mark_label() -> String {
    std::env::var("PADDWS_C64_MARK").unwrap_or_else(|_| "scene_done".into())
}

/// Soglie di FIRM: il budget meno 4.000, 2.500 e 500 cicli (PAL 14.000, 15.500, 17.500).
fn firm_limits() -> [u64; 3] {
    let b = frame_budget();
    [b - 4_000, b - 2_500, b - 500]
}

/// Con il profilo inclusivo: le 12 subroutine più pesanti del frame appena eseguito, con quelle che
/// chiamano.
fn frame_parts(m: &Machine) -> Option<String> {
    let inc = m.cpu.inclusive.as_ref()?;
    let mut rows: Vec<(u64, usize)> = inc.cycles.iter().enumerate().filter(|r| *r.1 > 0).map(|(a, &c)| (c, a)).collect();
    rows.sort_by_key(|r| std::cmp::Reverse(r.0));
    let labels = m.sorted_labels();
    // PADDWS_C64_PARTS=N: le N subroutine più pesanti (12 se manca)
    let n = std::env::var("PADDWS_C64_PARTS").ok().and_then(|v| v.parse().ok()).unwrap_or(12);
    let parts: Vec<String> = rows
        .iter()
        .take(n)
        .map(|&(c, a)| {
            let name = labels.iter().find(|l| l.0 as usize == a).map_or_else(|| format!("${a:04X}"), |l| l.1.clone());
            format!("{name} {c}")
        })
        .collect();
    Some(parts.join(", "))
}

/// Stampa il profilo raccolto da `frames` (anche quando un controllo è fallito prima della fine).
fn print_heavy(m: &mut Machine) {
    let Some(limit) = heavy_limit() else { return };
    m.cpu.profile = None;
    if let Some(inc) = m.cpu.inclusive.take() {
        LONGEST.set(inc.longest);
    }
    // PADDWS_C64_LONGEST=etichetta,...: la chiamata più lunga di quelle subroutine
    if let Ok(list) = std::env::var("PADDWS_C64_LONGEST") {
        for l in list.split(',') {
            let long = LONGEST.with_borrow(|v| v.get(m.addr(l) as usize).copied().unwrap_or(0));
            println!("  chiamata più lunga di {l}: {long} cicli");
        }
    }
    let labels: Vec<(u16, String)> = m.sorted_labels().to_vec();
    let routine = |pc: usize| match labels.binary_search_by_key(&(pc as u16), |l| l.0) {
        Ok(i) => i,
        Err(i) => i.saturating_sub(1),
    };
    FIRM.with_borrow(|firm| {
        for (scene, f) in firm.iter().enumerate() {
            if f.is_empty() {
                continue;
            }
            let mut f = f.clone();
            f.sort_unstable();
            let at = |q: usize| f[(f.len() - 1) * q / 100];
            let over: Vec<String> = firm_limits()
                .iter()
                .map(|&lim| format!("{lim} in {}", f.iter().filter(|&&c| c > lim).count()))
                .collect();
            println!(
                "  {}: fino a {} {} frame, cicli da {} a {} (mediana {}, 90% {}); oltre {}",
                SCENES[scene],
                mark_label(),
                f.len(),
                f[0],
                at(100),
                at(50),
                at(90),
                over.join(", ")
            );
        }
    });
    HEAVY.with_borrow(|heavy| {
        for (scene, (n, sum, p, inc, calls)) in heavy.iter().enumerate() {
            if *n == 0 {
                continue;
            }
            println!("  frame oltre {limit} in {}: {n}, media {} cicli", SCENES[scene], sum / u64::from(*n));
            let mut by = vec![0u64; labels.len()];
            for (a, &c) in p.iter().enumerate() {
                if c > 0 {
                    by[routine(a)] += c;
                }
            }
            let mut rows: Vec<(u64, &(u16, String))> = by.into_iter().zip(&labels).collect();
            rows.sort_by_key(|r| std::cmp::Reverse(r.0));
            for (c, (addr, name)) in rows.iter().take(18).filter(|r| r.0 > 0) {
                println!("    ${addr:04X} {name:<20} {:6} cicli per frame", c / u64::from(*n));
            }
            // inclusivo: le subroutine con quelle che chiamano
            println!("    con le subroutine chiamate:");
            let mut inc_rows: Vec<(u64, u16)> = inc.iter().enumerate().filter(|r| *r.1 > 0).map(|(a, &c)| (c, a as u16)).collect();
            inc_rows.sort_by_key(|r| std::cmp::Reverse(r.0));
            for (c, addr) in inc_rows.iter().take(70) {
                let name = labels.iter().find(|l| l.0 == *addr).map_or("?", |l| l.1.as_str());
                let k = calls[*addr as usize];
                let long = LONGEST.with_borrow(|l| l.get(*addr as usize).copied().unwrap_or(0));
                let each = if k > 0 { format!(", {} chiamate di {} cicli (al più {long})", k, c / k) } else { String::new() };
                println!("    ${addr:04X} {name:<20} {:6} cicli per frame{each}", c / u64::from(*n));
            }
        }
    });
}

/// Budget del frame: il programma parte come all'accensione e gioca l'attract intero (con la
/// classifica), poi una partita contro la CPU; per ogni scena cicli per frame (massimo e media) e frame
/// oltre il budget, che non ce ne devono essere (i lavori lunghi si dividono su più frame).
/// Nessun comando: joystick e tastiera a riposo.
fn frames(m: &mut Machine) -> bool {
    const NAMES: [&str; 12] = SCENES;
    let inc = std::fs::read_to_string(c64_dir().join("gen/assets.inc")).unwrap_or_default();
    if inc_const(&inc, "CH_GRID_T") != Some(ch_grid_t()) || inc_const(&inc, "CH_WALL") != Some(CH_WALL) {
        println!("FAIL: CH_GRID_T o CH_WALL diversi da gen/assets.inc");
        return false;
    }
    let mut stats = [(0u64, 0u64, 0u32, 0u32); 12]; // massimo, somma, frame, oltre il budget
    // presentazioni di CHALLENGE con la voce: file caricati, frame con gli NMI, il più pesante;
    // poi i frame di partita con il tema dell'avversario e il più pesante
    let mut voiced = (0u32, 0u32, 0u64, 0u32, 0u64);
    // partita con il tema imposto dal banco di prova (fuori da CHALLENGE): niente controllo
    let theme_forced = std::cell::Cell::new(false);
    // tick della musica rimandati al frame dopo (scene_done, frame già avanti) su quelli delle
    // scene di gioco
    let late_ticks = std::cell::Cell::new((0u32, 0u32));
    // frame di gioco che tengono gli sprite del frame prima (tick pesantissimo), su quelli di gioco
    let kept_sprites = std::cell::Cell::new((0u32, 0u32));
    // racchette GUARDIAN: immagine dei settori persi in ritardo (vedi guardian_image)
    let guardian = std::cell::Cell::new(GuardianLag::default());
    // immagini delle racchette a schermo contro quelle giuste per tipo e stato (paddle_shown)
    let expected = paddle_images(m);
    let shown = std::cell::RefCell::new(ShownLag::default());
    // tabelle dei quadrati dopo math_init: in partita devono essere quelle (presentazioni, YOU WIN,
    // HOW TO PLAY e finale ci scrivono sopra e le fanno rifare prima)
    let squares: std::cell::RefCell<Vec<u8>> = std::cell::RefCell::new(Vec::new());
    // tempo della musica: frame al match point, frame nel bullet time, credito massimo di passi
    // in più ancora da fare (non deve crescere)
    let tempo = std::cell::Cell::new((0u32, 0u32, 0u8));
    // conti alla rovescia di CHALLENGE: quanti, con READY al primo frame, via, con GO al via (nessun
    // campione nel frame prima, i primi in quello del via); frame dall'ultimo via, scritture nel
    // volume ($D418) nel frame prima
    let counts = std::cell::Cell::new((0u32, 0u32, 0u32, 0u32));
    let since_via = std::cell::Cell::new(u32::MAX);
    // bordo con BORDER GRAY (border_game): frame di partita grigio scuro, giallo (SUPER o mossa MAX
    // in volo), rosso (match point: qui frame_count non avanza, quindi resta spento, vedi
    // border_logic), grigio pulsante (bullet time); bordi sbagliati (fuori dalla partita sh_brd deve
    // essere 0, in partita un colore della partita)
    let border = std::cell::Cell::new([0u32; 5]);
    let last_writes = std::cell::Cell::new(0usize);
    // PADDWS_C64_HEAVY=N: profilo dei frame oltre N cicli, scena per scena (frame, cicli, cicli per
    // indirizzo), per cercare i cicli da togliere (i tempi dell'NTSC)
    let heavy_limit = heavy_limit();
    let heavy_firm = std::env::var_os("PADDWS_C64_HEAVY_FIRM").is_some();
    let scene_done_at = m.addr(&mark_label());
    let rom_glyphs_now = program_glyphs(m);
    m.cpu.watch = Some((0xD418, 0xD418));
    let nmi = m.addr("nmi_handler");
    // NTSC: un frame di partita può finire dopo l'interrupt del frame dopo, di poco (spill_max): il
    // frame dopo parte subito, con il raster già avanti, e recupera (vedi spill_max). Ritardo del
    // prossimo frame, sforamenti ammessi (quanti, il più lungo)
    let carry = std::cell::Cell::new(0u64);
    let spills = std::cell::Cell::new((0u32, 0u64));
    m.cpu.frame_flag_at = Some(m.addr("frame_flag"));
    let pick_raw = std::env::var_os("PADDWS_C64_PICK_RAW").is_some();
    let frame = |m: &mut Machine,
                 stats: &mut [(u64, u64, u32, u32); 12],
                 voiced: &mut (u32, u32, u64, u32, u64)|
     -> Result<u64, String> {
        let state = m.read_u8("state", 0) as usize;
        let ch = m.read_u8("cg_active", 0) != 0;
        let first_count = state == ST_COUNT as usize && m.read_u8("timer", 0) == count_frames();
        // nella griglia delle racchette (pick.s, pk_kind) su e giù casuali come destra e sinistra,
        // che scorrono i tipi: le racchette scelte restano distribuite su tutti e sette (su e giù
        // cambiano riga, e con i comandi a caso si sceglierebbero quasi solo ARCADE e BLASTER).
        // PADDWS_C64_PICK_RAW: senza, per provare le partite BLASTER (le più pesanti con il TELEPORT)
        if state == ST_PICK as usize && m.read_u8("pk_kind", 0) != 0 && !pick_raw {
            for port in [&mut m.cpu.joy_port1, &mut m.cpu.joy_port2] {
                let held = !*port;
                let lr = (held & 0x01) << 2 | (held & 0x02) << 2;
                *port = !(held & !0x0F | lr);
            }
        }
        m.cpu.writes.clear();
        let addr = m.addr("frame");
        let (start, nmis) = (m.cpu.cycles, m.cpu.nmis);
        let phase = m.read_u8("sid_phase", 0);
        let voice_before = m.cpu.read(0xFFFB) & 0x80 != 0;
        // $D012 dà la riga del raster, contata dall'interrupt (prima, se il frame prima ha sforato)
        let late = carry.get();
        m.cpu.frame_start = Some(start - late);
        m.write_u8("frame_flag", 0, 0); // play_main lo azzera prima del frame
        let ef = m.cpu.ef_cycles;
        let flash = m.cpu.ef.as_ref().map_or(0, |e| e.programs + e.erases);
        // sentinella: compute_sprites azzera pd_made; se resta, il frame ha tenuto gli sprite di
        // prima (scene_done, dopo un tick pesantissimo). Non nel GAME OVER (8): lì gli sprite li
        // tiene il suo codice (play.s, ov_scene)
        m.write_u8("pd_made", 0, 0xAA);
        // fine della parte del frame che non si rimanda (scene_done; con PADDWS_C64_MARK un'altra)
        m.cpu.mark_at = Some(scene_done_at);
        m.cpu.mark = None;
        if heavy_limit.is_some() {
            match &mut m.cpu.profile {
                Some(p) => p.fill(0),
                None => m.cpu.profile = Some(vec![0; 0x10000]),
            }
            match &mut m.cpu.inclusive {
                Some(inc) => {
                    inc.cycles.fill(0);
                    inc.calls.fill(0);
                    inc.open.clear();
                }
                None => m.cpu.inclusive = Some(Box::default()),
            }
        }
        // cicli dall'interrupt: quelli del frame più il ritardo con cui è partito
        let c = m.cpu.call(addr, 1_000_000)? + late;
        let spill = c.saturating_sub(FRAME_BUDGET());
        // solo in partita dopo un tick pesantissimo: la parte che non si rimanda oltre
        // KEEP_SPRITES_LINE di play.s, quando il frame tiene gli sprite di prima (il lavoro
        // rimandabile, code, immagini e scritte, non deve mai far sforare)
        let heavy_tick = mark_label() != "scene_done"
            || m.cpu.mark.is_some_and(|at| at - start + late >= heavy_tick_from());
        let allowed = spill > 0 && state == ST_PLAY as usize && spill <= spill_max() && heavy_tick;
        carry.set(if allowed { spill } else { 0 });
        if allowed {
            let (n, worst) = spills.get();
            spills.set((n + 1, worst.max(spill)));
        }
        // nel profilo, i frame della partita con la cometa del SUPER in volo a parte (scena 4)
        let scene = if state == 7 && m.read_u8("nx_super", 0) != 0 && m.read_u8("nx_super_a", 0) == 2 {
            4
        } else {
            state
        };
        // PADDWS_C64_HEAVY_FIRM: i frame si scelgono per la parte fino a mark_label, non per il totale
        let weight = if heavy_firm { m.cpu.mark.map_or(0, |at| at - start) } else { c };
        if let (Some(limit), Some(p)) = (heavy_limit, &m.cpu.profile)
            && weight > limit
            && state < 12
        {
            HEAVY.with_borrow_mut(|h| {
                let e = &mut h[scene];
                e.0 += 1;
                e.1 += c;
                if e.2.is_empty() {
                    e.2 = vec![0; 0x10000];
                    e.3 = vec![0; 0x10000];
                    e.4 = vec![0; 0x10000];
                }
                for (a, &n) in p.iter().enumerate() {
                    e.2[a] += n;
                }
                if let Some(inc) = &m.cpu.inclusive {
                    for (a, &n) in inc.cycles.iter().enumerate() {
                        e.3[a] += n;
                    }
                    for (a, &n) in inc.calls.iter().enumerate() {
                        e.4[a] += u64::from(n);
                    }
                }
            });
        }
        // cicli fino a scene_done: dal profilo per istruzione, quelli spesi prima del primo passaggio
        // (il profilo non ha l'ordine: si usa il ciclo segnato da `mark`)
        if heavy_limit.is_some()
            && state < 12
            && let Some(at) = m.cpu.mark
        {
            FIRM.with_borrow_mut(|fm| fm[scene].push(at - start));
        }
        // CH_GRID_T e il muro (righe e trattini delle scritte animate, pavimento del continue,
        // entrate di TITAN e GUARDIAN) devono restare i loro: la capsula del BULLET prende altri
        // caratteri (bullet_chars), che dopo una partita NEXT restano scambiati
        if m.read_u8("state", 0) == 7 && m.cpu.mem[0xF000..0xF800] != squares.borrow()[..] {
            let sq = squares.borrow();
            let wrong: Vec<usize> = (0..0x800).filter(|&i| m.cpu.mem[0xF000 + i] != sq[i]).collect();
            return Err(format!(
                "partita con le tabelle dei quadrati non pronte (math_ready {}, {} byte diversi da ${:04X} a ${:04X}, dal stato {state}, livello {})",
                m.read_u8("math_ready", 0),
                wrong.len(),
                0xF000 + wrong[0],
                0xF000 + wrong[wrong.len() - 1],
                m.read_u8("ch_level", 0)
            ));
        }
        if matches!(m.read_u8("state", 0), 7 | 8 | 10 | 12) {
            let glyph = |c: usize| &m.cpu.mem[CHARSET + 8 * c..CHARSET + 8 * c + 8];
            if glyph(ch_grid_t()) != [0xFF, 0, 0, 0, 0, 0, 0, 0] || glyph(CH_WALL) != [0x3C; 8] {
                return Err(format!("caratteri della riga o del muro cambiati (stato {})", m.read_u8("state", 0)));
            }
            // il font e le lettere 2x della ROM dei caratteri: anche dopo le scelte, il GAME OVER
            // e il finale (non nello schermo VS della presentazione, kvs.s: al posto delle lettere 2x
            // c'è il suo codice, e le rifà alla fine)
            if !(m.read_u8("state", 0) == 10 && m.read_u8("in_vs", 0) != 0) {
                check_glyphs(m, &rom_glyphs_now, &format!("stato {}", m.read_u8("state", 0)))?;
            }
        }
        if matches!(m.read_u8("state", 0), 6 | 7) {
            let (kept, all) = kept_sprites.get();
            kept_sprites.set((kept + (m.read_u8("pd_made", 0) == 0xAA) as u32, all + 1));
        }
        if m.read_u8("state", 0) == ST_PLAY && m.read_u8("m_next", 0) != 0 {
            guardian_image(m, &guardian);
            paddle_shown(m, &expected, &mut shown.borrow_mut(), m.cpu.read(0xFFFB) & 0x80 != 0);
        }
        m.cpu.frame_start = None;
        // presentazione nuova, o la sfida dopo le scelte dello sfidante (il tema di un avversario a
        // caso): la copia del file voce dalla cartuccia (circa 60.000 cicli, tre frame a schermo
        // fermo) è un caricamento, fuori dal budget
        let now = m.read_u8("state", 0);
        let file = m.cpu.ef_cycles - ef >= 50_000;
        // la classifica salvata nella flash (hi_save): a schermo fermo, come un caricamento (la
        // cancellazione di un settore dura circa un secondo), fuori dal budget
        let saved = m.cpu.ef.as_ref().map_or(0, |e| e.programs + e.erases) != flash;
        // (un caricamento dura comunque più frame: anche il lavoro che il file voce fa subito dopo,
        // circa 11.000 cicli, fuori dal budget)
        let c = if saved || file {
            if file {
                voiced.0 += 1;
            }
            0
        } else if now == ST_INTRO && state != ST_INTRO as usize {
            voiced.0 += 1;
            c - (m.cpu.ef_cycles - ef)
        } else {
            c
        };
        if m.cpu.nmis != nmis {
            voiced.1 += 1;
            voiced.2 = voiced.2.max(c);
        }
        // il resto del frame, con gli NMI della voce
        m.cpu.idle(start + frame_cycles())?;
        // (con la voce di CHALLENGE il player aspetta: non è un tick rimandato; sull'NTSC nemmeno
        // il frame su sei senza il passo, tv_skip)
        let voice = voice_before || m.cpu.read(0xFFFB) & 0x80 != 0;
        let no_step = ntsc() && m.read_u8("tv_skip", 0) & 0x80 != 0;
        if matches!(m.read_u8("state", 0), 6..=8) && !voice && !no_step {
            let (late, all) = late_ticks.get();
            late_ticks.set((late + (m.read_u8("sid_phase", 0) == phase) as u32, all + 1));
        }
        let (fast, slow, extra) = tempo.get();
        tempo.set((
            fast + (m.read_u8("sid_fast", 0) != 0) as u32,
            slow + (m.read_u8("sid_slow", 0) != 0) as u32,
            extra.max(m.read_u8("sid_extra", 0)),
        ));
        // il tema suona solo in CHALLENGE (contro la CPU quello dell'avversario, nella sfida tra due
        // giocatori quello di un avversario a caso), e lì sempre; mai nelle altre partite
        // (contro OMEGA la sua canzone, muta mentre la sezione nuova si copia)
        let song = m.read_u8("sid_song_n", 0);
        let theme = song == SID_SONG_THEME
            || (m.read_u8("ch_level", 0) == CH_OMEGA
                && (song == SID_SONG_OMEGA || (song == 0 && m.read_u8("om_left", 0) != 0)));
        let ch_cpu = m.read_u8("cg_active", 0) != 0;
        if m.read_u8("state", 0) == 7 && !theme_forced.get() {
            if theme != ch_cpu {
                return Err(format!(
                    "partita {} il tema di CHALLENGE",
                    if theme { "fuori da CHALLENGE con" } else { "di CHALLENGE senza" }
                ));
            }
            if theme {
                voiced.3 += 1;
                voiced.4 = voiced.4.max(c);
            }
        }
        let s = &mut stats[if state == ST_ENDING as usize { 11 } else { state.min(10) }];
        s.0 = s.0.max(c);
        s.1 += c;
        s.2 += 1;
        s.3 += (c > FRAME_BUDGET() && !allowed) as u32;
        let now = m.read_u8("state", 0);
        if c > FRAME_BUDGET() && !allowed {
            println!(
                "  frame oltre il budget: stato {state} -> {now}, {c} cicli ({} NMI, tabelle {}, partito {late} cicli in ritardo, battuta {})",
                m.cpu.nmis - nmis,
                if m.read_u8("math_ready", 0) != 0 { "pronte" } else { "da rifare" },
                m.read_u8("serve_timer", 0)
            );
            // con PADDWS_C64_HEAVY: le parti del frame (cicli con le subroutine chiamate)
            if let Some(parts) = frame_parts(m) {
                let mark = m.cpu.mark.map_or(String::new(), |at| format!("; {} a {}", mark_label(), at - start));
                println!("    {parts}{mark}");
            }
        }
        let mut b = border.get();
        let brd = m.read_u8("sh_brd", 0);
        if now == ST_OVER && brd == 0 {
            // GAME OVER: nero dalla chiusura da televisore (ov_close)
        } else if brd == 0 && now as usize != state {
            // primo frame di una scena di partita (begin_match, pesante): border_game lo colora al
            // prossimo, quando il frame ha tempo
        } else if matches!(now, 4 | 6 | 7 | 8) {
            // (nel bullet time il grigio pulsante comincia dallo scuro: qui frame_count è fermo)
            let bullet = m.read_u8("sid_slow", 0) & 0x80 != 0;
            let k = match brd {
                COL_DGRAY | COL_MGRAY | COL_GRAY if bullet => 3,
                COL_DGRAY => 0,
                COL_YELLOW => 1,
                COL_RED => 2,
                _ => 4,
            };
            // fuori da PLAY gli eventi non contano (un frame già avanti tiene il colore di prima)
            if now == ST_PLAY || k == 4 {
                b[k] += 1;
            }
        } else if brd != 0 {
            b[4] += 1;
        }
        border.set(b);
        // READY al primo frame del conto alla rovescia di CHALLENGE, GO al via
        let (mut n, mut ready, mut vias, mut go) = counts.get();
        // (sull'NTSC non il frame senza scena: il conto comincia in quello dopo)
        if ch && first_count && now == ST_COUNT && !scene_skipped(m) {
            n += 1;
            ready += (m.cpu.read(0xFFFB) & 0x80 != 0) as u32;
        }
        since_via.set(since_via.get().saturating_add(1));
        if ch && state == ST_COUNT as usize && now == ST_PLAY {
            vias += 1;
            go += (last_writes.get() == 0 && m.cpu.writes.len() >= 2) as u32;
            since_via.set(0);
        }
        counts.set((n, ready, vias, go));
        last_writes.set(m.cpu.writes.len());
        let voice_ok = now == ST_COUNT || (now == ST_PLAY && since_via.get() <= 40);
        // (YOU WIN nel GAME OVER contro la CPU e nel finale)
        let voice_ok = voice_ok || now == ST_OVER || now == ST_ENDING;
        if now != ST_INTRO && !voice_ok && (m.cpu.read16(0xFFFA) != nmi || m.cpu.cia2.running) {
            return Err(format!("voce accesa fuori dalla presentazione e dal conto alla rovescia (stato {now})"));
        }
        Ok(c)
    };
    // frame di partita NEXT con il bullet time acceso: quanti e il più pesante
    let mut bullet = (0u32, 0u64);
    let bullet_frame = |m: &Machine, c: u64, bullet: &mut (u32, u64)| {
        if m.read_u8("state", 0) == 7 && m.read_u8("m_next", 0) != 0 && m.read_u8("nx_btimer", 0) != 0 {
            bullet.0 += 1;
            bullet.1 = bullet.1.max(c);
        }
    };
    for r in ["title_unpack", "clear_vars", "math_init", "video_init", "input_init", "sid_init"] {
        m.call(r);
    }
    *squares.borrow_mut() = m.cpu.mem[0xF000..0xF800].to_vec();
    // vettore dell'NMI del programma (irq_init)
    m.cpu.write(0xFFFA, nmi as u8);
    m.cpu.write(0xFFFB, (nmi >> 8) as u8);
    // joystick e tastiera a riposo (le linee dei CIA a 1)
    m.cpu.write(0xDC00, 0xFF);
    m.cpu.write(0xDC01, 0xFF);
    for (name, v) in [
        ("opt_mode", 1),
        ("opt_level", 1),
        ("opt_free", 1),
        ("opt_asound", 1),
        ("opt_players", 3),
        ("opt_border", 1),
    ] {
        m.write_u8(name, 0, v);
    }
    m.call("boot_enter");
    m.write_u8("state", 0, 0);
    m.call("attract_song");
    let attract = 240 + 120 + 110 + 400 + 1000 + 5;
    for _ in 0..attract {
        if let Err(e) = frame(m, &mut stats, &mut voiced) {
            println!("FAIL: attract: {e}");
            return false;
        }
    }
    m.call("start_game");
    let mut pad_on = true;
    for _ in 0..50 * 60 * 3 {
        if let Err(e) = frame(m, &mut stats, &mut voiced) {
            println!("FAIL: partita: {e}");
            return false;
        }
        // in partita la racchetta sinistra (sprite 3) è sempre accesa, salvo il lampo del punto
        if m.read_u8("state", 0) == 7 && m.read_u8("sh_bg", 0) == 0 {
            pad_on &= m.read_u8("sh_enable", 0) & 0b1000 != 0;
        }
    }
    if !pad_on {
        println!("FAIL: in partita la racchetta sinistra non compare");
        return false;
    }
    // NEXT contro la CPU dal menu, con P1 al joystick (porta 2): insegue la palla (non con il
    // TELEPORT armato, così il salto è lungo e si vede), ogni tanto scatta (destra, verso
    // l'avversario) e usa il bonus selezionato, che cambia da solo (fuoco); nelle scelte sposta il
    // cursore e prende a caso
    m.write_u8("opt_mode", 0, 2);
    m.write_u8("opt_players", 0, 3);
    m.call("start_game");
    let mut next_on = false;
    let mut next_pads = PadCheck::default();
    let mut warp = WarpCheck::default();
    let mut comet = CometCheck::default();
    let mut rings = 0; // immagini degli aloni di SLOW pronte in partita
    let mut rng = Rng::new(0x1234_5678);
    let joy = |m: &mut Machine, rng: &mut Rng| {
        let mut joy = 0xFFu8;
        let diff = fixed::floor(m.read_i32("ball_y", 0)) - fixed::floor(m.read_i32("pad_y", 0));
        // a partita finita (attract, menu e classifica) il joystick resta fermo: il fuoco nelle
        // strisce o nella classifica aprirebbe il menu, che qui non si misura
        if m.read_u8("state", 0) <= ST_MENU || m.read_u8("state", 0) == ST_SCORES {
            return joy;
        }
        if m.read_u8("state", 0) >= 9 {
            joy &= match rng.below(40) {
                37 => !0x01,
                38 => !0x02,
                39 => !0x10,
                _ => 0xFF,
            };
        } else if m.read_u8("nx_armed", 0) == 0 {
            // TELEPORT armato (B_TELEPORT = 0): la racchetta resta dov'è
        } else if diff > 4 {
            joy &= !0x01;
        } else if diff < -4 {
            joy &= !0x02;
        }
        for (odds, bit) in [(40, 0x08), (60, 0x10)] {
            if rng.below(odds) == 0 {
                joy &= !bit;
            }
        }
        // il TELEPORT selezionato si usa subito (B_TELEPORT = 0): il salto deve capitare a
        // prescindere da come va la partita
        if m.read_u8("state", 0) == 7 && m.read_u8("nx_res", m.read_u8("nx_sel", 0) as u16) == 0 {
            joy &= !0x10;
        }
        joy
    };
    let mut prev_cycles = 0;
    for f in 0..50 * 30 + 50 * 60 * 3 {
        // le capsule raccolte dipendono da come va la partita: se il salto non è ancora capitato,
        // ogni 10 secondi un TELEPORT nella riserva vuota di P1, come preso da una capsula
        if f % 500 == 499
            && warp.frames == 0
            && m.read_u8("state", 0) == 7
            && m.read_u8("m_next", 0) != 0
            && m.read_u8("nx_res", 0) == 8
        {
            m.write_u8("nx_res", 0, 0);
        } else if f % 500 == 499
            && comet.frames == 0
            && m.read_u8("state", 0) == 7
            && m.read_u8("m_next", 0) != 0
            && m.read_u8("nx_armed", 0) == 8
        {
            // come per il TELEPORT: se la cometa del SUPER non è ancora capitata, un SUPER (cometa) armato su P1
            m.write_u8("nx_armed", 0, 5);
            m.write_u8("nx_anim", 0, 2);
        }
        m.cpu.joy_port2 = joy(m, &mut rng);
        let c = match frame(m, &mut stats, &mut voiced) {
            Ok(c) => {
                bullet_frame(m, c, &mut bullet);
                c
            }
            Err(e) => {
                println!("FAIL: NEXT: {e}");
                return false;
            }
        };
        if m.read_u8("state", 0) == 7 && m.read_u8("m_next", 0) != 0 {
            next_on = true;
            next_pads.check(m);
            warp.check(m);
            comet.cur = c;
            comet.check(m, prev_cycles);
            rings = rings.max(m.read_u8("fx_pages", 0));
        }
        prev_cycles = c;
    }
    m.cpu.joy_port2 = 0xFF;
    if !next_on {
        println!("FAIL: dopo le scelte la partita NEXT non parte");
        return false;
    }
    if !next_pads.ok("NEXT") || !warp.ok() || !comet.ok() {
        return false;
    }
    if rings < 2 {
        println!("FAIL: NEXT: le immagini degli aloni di SLOW non sono mai pronte ({rings} su 2)");
        return false;
    }
    // NEXT contro la CPU con le mosse speciali (SUPER MOVES): P1 insegue la palla e, con la palla
    // in arrivo, fa i gesti del joystick; la CPU usa le mosse. Il codice delle mosse nella RAM del
    // secondo schermo deve essere quello del .prg (l'attract l'ha coperto, la scelta lo rimette);
    // barre, icone, racchetta gialla, scritta, palla gialla ed effetti del SID devono comparire
    m.write_u8("cfg_super", 0, 1);
    m.call("start_game");
    let mut moves = SuperFrames::default();
    let mut queue = std::collections::VecDeque::new();
    for f in 0..50 * 30 + 50 * 60 * 3 {
        // la barra si riempie piano: ogni 10 secondi quella di P1 piena, come caricata da due mosse,
        // così capitano anche le mosse MAX (racchetta gialla)
        if f % 500 == 499 && m.read_u8("state", 0) == ST_PLAY && m.read_u8("sm_arm", 0) == 0 {
            m.write_u8("sm_meter", 0, 64);
        }
        m.cpu.joy_port2 = match gesture_joy(m, &mut rng, &mut queue) {
            Some(bits) => !bits,
            None => joy(m, &mut rng),
        };
        match frame(m, &mut stats, &mut voiced) {
            Ok(c) => moves.check(m, c),
            Err(e) => {
                println!("FAIL: NEXT con le mosse speciali: {e}");
                return false;
            }
        }
    }
    m.cpu.joy_port2 = 0xFF;
    if let Err(e) = moves.ok() {
        println!("FAIL: NEXT con le mosse speciali: {e}");
        return false;
    }
    println!("  mosse speciali: {}", moves.line());
    // ancora NEXT contro la CPU, con il BULLET sempre in gioco: appena non c'è torna per chi
    // riceve la palla, una volta armato (scatta da solo nella sua metà campo) e una volta già
    // scattato, con la rampa da capo; finisce alla ribattuta come in partita. Così anche i frame
    // più pesanti della partita (colpi, bonus, previsioni) capitano con il BULLET; e con il tema più
    // carico di CHALLENGE (BLASTER: note brevi, arpeggi e scivolate), messo dove lo mette il file
    // voce, come nella partita contro la CPU di CHALLENGE. Solo il budget: la partita non è più
    // quella del core. Due volte: senza e con le mosse speciali
    let mut forced = (0u32, 0u64, 0u32, 0u64);
    let mut forced_moves = SuperFrames::default();
    let bullet_ramp = c64_params(1).bullet_ramp_ticks as u8;
    for supers in [0u8, 1] {
        for v in 0..3u16 {
            let track = std::fs::read(c64_dir().join(format!("gen/theme{}_{v}.bin", PaddleKind::Blaster as u8)))
                .unwrap_or_default();
            m.cpu.load(THEME_BASE + v * 0x100, &track);
        }
        m.write_u8("match_song", 0, SID_SONG_THEME);
        m.write_u8("cfg_super", 0, supers);
        theme_forced.set(true);
        m.call("start_game");
        for _ in 0..50 * 30 + 50 * 60 * 2 {
            m.cpu.joy_port2 = joy(m, &mut rng);
            if m.read_u8("state", 0) == 7
                && m.read_u8("m_next", 0) != 0
                && m.read_u8("serve_timer", 0) == 0
                && m.read_u8("nx_bside", 0) & 0x80 != 0
            {
                let toward = if m.read_i32("ball_vx", 0) < 0 { 0 } else { 4 };
                m.write_u8("nx_bside", 0, toward);
                m.write_u8("nx_btimer", 0, if rng.below(2) == 0 { 0 } else { bullet_ramp + 1 });
            }
            match frame(m, &mut stats, &mut voiced) {
                Ok(c) => {
                    let mut b = (forced.0, forced.1);
                    bullet_frame(m, c, &mut b);
                    (forced.0, forced.1) = b;
                    if m.read_u8("state", 0) == 7 && m.read_u8("sid_song_n", 0) == SID_SONG_THEME {
                        forced.2 += 1;
                        forced.3 = forced.3.max(c);
                    }
                    if supers == 1 {
                        forced_moves.check(m, c);
                    }
                }
                Err(e) => {
                    println!("FAIL: NEXT con il BULLET: {e}");
                    return false;
                }
            }
        }
    }
    theme_forced.set(false);
    println!(
        "  mosse speciali con il BULLET sempre in gioco: {}",
        forced_moves.line()
    );
    m.cpu.joy_port2 = 0xFF;
    if forced.2 == 0 {
        println!("FAIL: NEXT con il BULLET: il tema imposto non suona");
        return false;
    }
    // CHALLENGE (con le mosse speciali, che la CPU usa): P1 gioca finché supera un livello, poi
    // lascia la racchetta e non continua; le iniziali si scelgono a caso, la classifica torna
    // all'attract
    m.write_u8("opt_players", 0, 4);
    m.call("start_game");
    let mut ch_moves = SuperFrames::default();
    let mut seen = [false; 15];
    let mut play = true;
    let mut ch_pads = PadCheck::default();
    for f in 0..50 * 60 * 12 {
        let state = m.read_u8("state", 0) as usize;
        seen[state.min(14)] = true;
        play &= !seen[11];
        if state == 7 {
            ch_pads.check(m);
            // ogni 10 secondi la barra della CPU piena (come quella di P1 nella partita NEXT sopra):
            // le sue mosse capitano sempre, non solo se la partita la riempie
            let cpu = m.read_u8("cpu_side", 0);
            if f % 500 == 499 && cpu < 8 && m.read_u8("sm_arm", cpu as u16) == 0 {
                m.write_u8("sm_meter", cpu as u16, 64);
            }
        }
        m.cpu.joy_port2 = match state {
            7 | 9 if play => joy(m, &mut rng),
            9 | 13 => joy(m, &mut rng),
            _ => 0xFF,
        };
        match frame(m, &mut stats, &mut voiced) {
            Ok(c) => {
                bullet_frame(m, c, &mut bullet);
                ch_moves.check(m, c);
            }
            Err(e) => {
                println!("FAIL: CHALLENGE: {e}");
                return false;
            }
        }
        if seen[14] && m.read_u8("state", 0) < 4 {
            break;
        }
    }
    m.cpu.joy_port2 = 0xFF;
    let missing: Vec<_> = (10..15).filter(|&s| !seen[s]).collect();
    if !missing.is_empty() {
        println!("FAIL: CHALLENGE non passa dagli stati {missing:?}");
        return false;
    }
    if !ch_pads.ok("CHALLENGE") {
        return false;
    }
    if ch_moves.armed == 0 || ch_moves.code_bad > 0 {
        println!("FAIL: CHALLENGE con le mosse speciali: {}", ch_moves.line());
        return false;
    }
    println!("  mosse speciali in CHALLENGE: {}", ch_moves.line());
    // CHALLENGE con un nuovo sfidante: P2 (porta 1) entra nella prima presentazione e sceglie a
    // caso; nella sfida P1 lascia la racchetta, così vince P2, che riprende il livello da destra
    // contro la CPU (a sinistra)
    let joy_right = |m: &mut Machine, rng: &mut Rng| {
        let mut joy = 0xFFu8;
        let diff = fixed::floor(m.read_i32("ball_y", 0)) - fixed::floor(m.read_i32("pad_y", 4));
        if m.read_u8("state", 0) >= 9 {
            joy &= match rng.below(40) {
                37 => !0x01,
                38 => !0x02,
                39 => !0x10,
                _ => 0xFF,
            };
        } else if diff > 4 {
            joy &= !0x01;
        } else if diff < -4 {
            joy &= !0x02;
        }
        for (odds, bit) in [(40, 0x04), (60, 0x10)] {
            if rng.below(odds) == 0 {
                joy &= !bit;
            }
        }
        joy
    };
    m.write_u8("opt_players", 0, 4);
    m.call("start_game");
    let mut seen = [false; 16];
    let (mut joined, mut right_frames, mut t) = (false, 0, 0u32);
    for _ in 0..50 * 60 * 8 {
        t += 1;
        let state = m.read_u8("state", 0) as usize;
        seen[state.min(15)] = true;
        joined |= state == 15;
        let duel = m.read_u8("cg_active", 0) == 2;
        let (p2, p1) = match state {
            9 if !joined => (joy(m, &mut rng), 0xFF),
            10 if !joined && t % 2 == 0 => (0xFF, !0x10u8),
            9 => (0xFF, joy_right(m, &mut rng)),
            6 | 7 if duel => (0xFF, joy_right(m, &mut rng)),
            6 | 7 if joined && m.read_u8("ch_side", 0) == 4 => (0xFF, joy_right(m, &mut rng)),
            _ => (0xFF, 0xFF),
        };
        m.cpu.joy_port2 = p2;
        m.cpu.joy_port1 = p1;
        match frame(m, &mut stats, &mut voiced) {
            Ok(c) => bullet_frame(m, c, &mut bullet),
            Err(e) => {
                println!("FAIL: CHALLENGE con lo sfidante: {e}");
                return false;
            }
        }
        if state == 7 && !duel && m.read_u8("cpu_side", 0) == 0 && m.read_u8("ch_side", 0) == 4 {
            right_frames += 1;
            if right_frames > 50 * 60 {
                break;
            }
        }
    }
    m.cpu.joy_port1 = 0xFF;
    m.cpu.joy_port2 = 0xFF;
    if !seen[15] {
        println!("FAIL: CHALLENGE: lo sfidante non entra");
        return false;
    }
    if right_frames == 0 {
        println!("FAIL: CHALLENGE: dopo la sfida chi ha vinto da destra non gioca contro la CPU");
        return false;
    }
    println!("  CHALLENGE con lo sfidante: {right_frames} frame di P2, che ha vinto la sfida, a destra contro la CPU");
    match ending_frames(m) {
        Ok(s) => println!("  {s}"),
        Err(e) => {
            println!("FAIL: finale di CHALLENGE: {e}");
            return false;
        }
    }
    // OMEGA: battuto il GUARDIAN 5 a 0 con la scala fatta tutta a HARD (il file voce del primo
    // livello in memoria, come dopo una scala), l'allarme, la presentazione di OMEGA e la partita,
    // con P1 al joystick e ogni tanto un punto suo messo dal banco di prova (la palla oltre la
    // racchetta di OMEGA), così OMEGA cambia forma; a 6 punti la partita finisce (7 a 0, PERFECT);
    // poi premi, finale speciale, iniziali e classifica. Il budget, e che tutto succeda.
    let omega_ok = (|| -> Result<String, String> {
        quiet_inputs(m);
        m.cpu.watch = Some((0xD418, 0xD418)); // (il finale l'ha tolta)
        m.cpu.a = m.read_u8("rung_kind", 0);
        m.call("ef_voice");
        for _ in 0..3 {
            m.cpu.call(VOICE_BASE, 100_000)?;
        }
        m.cpu.call(VOICE_BASE + 3, 100_000)?;
        m.cpu.a = 0;
        m.call("sid_song");
        for (name, v) in [
            ("cg_active", 1u8),
            ("ch_level", 6),
            ("ch_side", 0),
            ("ch_best_lv", 1),
            ("ch_clean", 1),
            ("ch_omega", 0),
            ("opt_level", 2),
            ("hi_omega", 0xFF),
            ("hi_juke", 0xFF),
            ("state", ST_OVER),
        ] {
            m.write_u8(name, 0, v);
        }
        for (o, v) in [(0u16, 5u8), (1, 0), (4, 0), (5, 0)] {
            m.write_u8("score", o, v);
        }
        m.write_i32("ch_score", 0, 100_000);
        m.write_i32("ch_best", 0, 0);
        m.call("ch_after");
        if m.read_u8("state", 0) != ST_WARNING {
            return Err(format!("dopo il GUARDIAN la scena {} invece dell'allarme", m.read_u8("state", 0)));
        }
        let mut seen = [false; 19];
        let (mut morphs, mut flash, mut loads, mut net, mut red, mut worst) = (0u32, 0u32, 0u32, 0u32, 0u32, 0u64);
        // nome della forma nuova a schermo (nm_on), e mai nella prima forma
        let mut named = 0u32;
        let mut instant = 0u32;
        let mut late_morph = false;
        // forme TWIST e BLASTER: frame con un'immagine preparata delle varianti (inclinata, caricatore
        // non pieno: om_slot di video.s) e frame con l'immagine dinamica (che contro OMEGA arriva tardi)
        let (mut tilted, mut loaded, mut dynamic, mut low) = (0u32, 0u32, 0u32, 0u32);
        let full_mag = c64_params(1).blaster_shots as u32;
        let mut shot = false;
        let mut kind = 0u8;
        let mut ended = false;
        for f in 0..50 * 60 * 6 {
            let state = m.read_u8("state", 0) as usize;
            seen[state.min(18)] = true;
            m.cpu.joy_port2 = if state == 7 || state == 13 { joy(m, &mut rng) } else { 0xFF };
            if state == 7 && m.read_u8("serve_timer", 0) == 0 && f % 200 == 0 && m.read_u8("score", 0) < 6 {
                m.write_i32("ball_x", 0, 316 << 16);
                m.write_i32("ball_vx", 0, 4 << 16);
            }
            // (la fine dopo la musica dell'ultima forma, e dopo che la forma si è vista: late_morph)
            if state == 7 && m.read_u8("score", 0) == 6 && m.read_u8("om_left", 0) == 0 && !late_morph && !ended {
                ended = true;
                m.write_u8("score", 0, 7);
                m.write_u8("over_next", 0, 1);
            }
            let c = frame(m, &mut stats, &mut voiced).map_err(|e| format!("stato {state}: {e}"))?;
            worst = worst.max(c);
            if m.read_u8("state", 0) == 7 {
                let k = m.read_u8("nx_kind", 4);
                morphs += (k != kind) as u32;
                // la forma nuova nello sprite nel frame stesso del tick: l'immagine preparata nel
                // conto alla rovescia per quella forma (pad_prep, prep_slot)
                // (in un frame così pesante da tenere gli sprite del frame prima, pd_made, anche il
                // lampo e il nome arrivano al frame dopo, e con gli sprite spenti si guarda quando
                // tornano)
                let pad_on = m.read_u8("sh_enable", 0) & 0x10 != 0;
                if (k != kind || late_morph) && (m.read_u8("pd_made", 0) == 0xAA || !pad_on) {
                    late_morph = true;
                } else if k != kind || std::mem::take(&mut late_morph) {
                    let ptr = m.read_u8("sh_ptr", 4);
                    let spin = m.read_u8("prep_base", 0) + 14; // SP_SPIN0
                    // (con il salto del TELEPORT in corso l'immagine è quella del salto)
                    let jump = m.read_u8("wp_on", 0) != 0 && m.read_u8("wp_side", 0) == 1;
                    let ready = ptr == m.read_u8("prep_base", 1) + k
                        || (spin + 8..spin + 16).contains(&ptr)
                        || (spin + 21..spin + 24).contains(&ptr)
                        || (jump && ptr == m.read_u8("pad_slot", 1));
                    instant += ready as u32;
                }
                kind = k;
                let ptr = m.read_u8("sh_ptr", 4);
                let spin = m.read_u8("prep_base", 0) + 14; // SP_SPIN0
                let variant = (spin + 8..spin + 16).contains(&ptr) || (spin + 21..spin + 24).contains(&ptr);
                tilted += (k == 3 && variant) as u32;
                loaded += (k == 4 && variant) as u32;
                low += (k == 4 && (m.read_u8("nx_ammo", 4) as u32) < full_mag) as u32;
                // (OMEGA della prova spara poco: due colpi nel caricatore messi dal banco di prova,
                // una volta, per vedere l'immagine nel frame dopo)
                if k == 4 && low == 0 && !shot {
                    shot = true;
                    m.write_u8("nx_ammo", 4, 2);
                }
                dynamic += ((k == 3 || k == 4) && ptr == m.read_u8("pad_slot", 1) && m.read_u8("wp_on", 0) == 0) as u32;
                flash += (m.read_u8("om_flash", 0) != 0) as u32;
                red += (m.read_u8("sh_col", 4) == COL_PURPLE) as u32;
                net += (m.cpu.mem[0xC000 + 12 * 40 + 19] != 1) as u32;
                loads += (m.read_u8("om_left", 0) != 0) as u32;
                if m.read_u8("om_on", 0) >= 4 && m.read_u8("nm_on", 0) != 0 {
                    named += 1;
                    if k == 0 {
                        return Err("il nome della forma nuova con OMEGA ancora ARCADE".into());
                    }
                }
            }
            if seen[14] && m.read_u8("state", 0) < 4 {
                break;
            }
        }
        m.cpu.joy_port2 = 0xFF;
        let missing: Vec<_> = [ST_WARNING, ST_INTRO, ST_COUNT, ST_PLAY, ST_OVER, ST_CLEAR, ST_ENDING, ST_SCORES]
            .into_iter()
            .filter(|&s| !seen[s as usize])
            .collect();
        if !missing.is_empty() {
            return Err(format!("non passa dagli stati {missing:?}"));
        }
        // (il lampo dell'ultima trasformazione lo taglia la fine della partita)
        if tilted == 0 || (low > 0 && loaded == 0) {
            return Err(format!(
                "TWIST inclinata in {tilted} frame, BLASTER con il caricatore non pieno in {loaded} su {low} (immagini preparate delle varianti mai usate)"
            ));
        }
        if morphs < 6 || instant < morphs || flash < 5 * 7 || red == 0 || net == 0 || loads == 0 || named < 6 * 35 {
            return Err(format!(
                "{morphs} trasformazioni ({instant} con la forma nuova nel frame stesso), {flash} frame di lampo, {named} con il nome della forma, {red} con la racchetta rossa, {net} con la rete spostata, {loads} di copia della musica"
            ));
        }
        let best = m.read_i32("ch_best", 0) as u32;
        let (win, perfect) = Score::omega_bonus(0);
        if m.read_u8("ch_best_lv", 0) != SCORE_LEVEL_OMEGA || best < 100_000 + win + perfect {
            return Err(format!("in classifica livello {} e {best} punti", m.read_u8("ch_best_lv", 0)));
        }
        if m.read_u8("hi_omega", 0) != 0 || m.read_u8("hi_juke", 0) != 0 {
            return Err("OMEGA nell'allenamento e il jukebox non sbloccati".into());
        }
        m.write_u8("ch_omega", 0, 0);
        Ok(format!(
            "OMEGA: allarme, presentazione, {morphs} trasformazioni (tutte con la forma nuova nel frame del tick, o nel primo con gli sprite rifatti e accesi, {flash} frame di lampo, {named} con il nome della forma), TWIST inclinata in {tilted} frame e BLASTER con il caricatore non pieno in {loaded} su {low} dalle immagini preparate ({dynamic} con l'immagine dinamica), musica copiata in {loads} frame, rete spostata in {net}, premi ({best} punti, ALL+), finale speciale e sblocchi; cicli max {worst}"
        ))
    })();
    match omega_ok {
        Ok(s) => println!("  {s}"),
        Err(e) => {
            println!("FAIL: OMEGA: {e}");
            return false;
        }
    }
    // JUKEBOX: i brani uno dopo l'altro (giù ogni 3 s), poi OMEGA per 70 s (cambia sezione ogni due
    // giri), poi RUN/STOP: il menu. Il budget, e che OMEGA passi alle sezioni dopo.
    let juke_ok = (|| -> Result<String, String> {
        quiet_inputs(m);
        m.write_u8("hi_juke", 0, 0);
        m.call("enter_jukebox");
        let (mut worst, mut sections, mut songs) = (0u64, std::collections::BTreeSet::new(), std::collections::BTreeSet::new());
        for f in 0..50 * 3 * 8 + 50 * 70 {
            if m.read_u8("state", 0) != ST_JUKEBOX {
                return Err(format!("frame {f}: scena {} invece del jukebox", m.read_u8("state", 0)));
            }
            m.cpu.joy_port2 = if f < 50 * 3 * 8 && f % 150 == 149 { !0x02 } else { 0xFF };
            let c = frame(m, &mut stats, &mut voiced)?;
            m.cpu.joy_port2 = 0xFF;
            worst = worst.max(c);
            songs.insert(m.read_u8("sid_song_n", 0));
            if m.read_u8("track", 0) == 8 {
                sections.insert(m.read_u8("osec", 0));
            }
        }
        if sections.len() < 3 || !songs.contains(&SID_SONG_EGG) || !songs.contains(&SID_SONG_OMEGA) {
            return Err(format!("canzoni {songs:?}, sezioni di OMEGA {sections:?}"));
        }
        // RUN/STOP: il menu, con il player com'era (sta SID,y in wr) e le scritte nello schermo
        let store = m.addr("sid_wr_store");
        if m.cpu.read(store) != 0x4C || m.read_u8("v_big", 0) & 0x40 == 0 {
            return Err("il jukebox non devia wr o non scrive nella bitmap".into());
        }
        m.write_u8("keys_edge", 7, 0x80);
        m.call("jbscene");
        m.write_u8("keys_edge", 7, 0);
        if m.read_u8("state", 0) != ST_MENU
            || m.cpu.read(store) != 0x99
            || m.cpu.read16(store + 1) != 0xD400
            || m.read_u8("v_big", 0) & 0x40 != 0
            || m.read_u8("math_ready", 0) != 0
        {
            return Err(format!("uscita dal jukebox: scena {}, wr non rimesso o tabelle dei quadrati non da rifare", m.read_u8("state", 0)));
        }
        // nel menu math_step rifà le tabelle dei quadrati (servono alle prove dopo)
        for _ in 0..400 {
            if m.read_u8("math_ready", 0) != 0 {
                break;
            }
            frame(m, &mut stats, &mut voiced)?;
        }
        if m.read_u8("math_ready", 0) == 0 || m.cpu.mem[0xF000..0xF800] != squares.borrow()[..] {
            let diff = (0..0x800).filter(|&i| m.cpu.mem[0xF000 + i] != squares.borrow()[i]).count();
            return Err(format!("dopo il jukebox le tabelle dei quadrati non tornano (math_ready {}, {diff} byte diversi, stato {})", m.read_u8("math_ready", 0), m.read_u8("state", 0)));
        }
        Ok(format!("JUKEBOX: i 9 brani, OMEGA in {} sezioni, uscita con RUN/STOP; cicli max {worst}", sections.len()))
    })();
    match juke_ok {
        Ok(s) => println!("  {s}"),
        Err(e) => {
            println!("FAIL: {e}");
            return false;
        }
    }
    let (n, worst) = spills.get();
    if spill_max() > 0 {
        println!("  frame di partita finiti dopo l'interrupt del frame dopo, ripresi da quelli dopo: {n} (al più {worst} cicli oltre, ammessi {})", spill_max());
    }
    let mut over = 0;
    for (i, s) in stats.iter().enumerate() {
        if s.2 > 0 {
            println!(
                "  {:<10} {:5} frame: cicli max {:6}, media {:6}, oltre {}: {}",
                NAMES[i],
                s.2,
                s.0,
                s.1 / s.2 as u64,
                FRAME_BUDGET(),
                s.3
            );
            over += s.3;
        }
    }
    println!(
        "  bullet time: {} frame nelle partite (cicli max {}), {} con il BULLET sempre in gioco (cicli max {})",
        bullet.0, bullet.1, forced.0, forced.1
    );
    println!(
        "  voce di CHALLENGE: {} presentazioni (il file dalla cartuccia fuori dal budget), {} frame con gli NMI (cicli max {}, NMI compresi)",
        voiced.0, voiced.1, voiced.2
    );
    println!(
        "  tema di CHALLENGE: {} frame di partita contro la CPU con il tema (cicli max {}), {} con il BULLET sempre in gioco e il tema del BLASTER (cicli max {})",
        voiced.3, voiced.4, forced.2, forced.3
    );
    let (n, ready, vias, go) = counts.get();
    println!(
        "  conto alla rovescia di CHALLENGE: READY al primo frame in {ready} su {n}, GO al via in {go} su {vias}"
    );
    if n == 0 || ready != n || vias == 0 || go != vias {
        println!("FAIL: READY e GO non sempre al loro frame");
        return false;
    }
    m.cpu.watch = None;
    let (late, all) = late_ticks.get();
    println!("  musica in partita: {late} tick rimandati al frame dopo su {all} frame");
    let (kept, all) = kept_sprites.get();
    println!("  sprite del frame prima (dopo un tick pesantissimo) in {kept} frame su {all}");
    let g = guardian.get();
    println!(
        "  racchette GUARDIAN: {} frame con i settori persi, {} con l'immagine in ritardo (al più {} di fila), {} con il pezzo del TELEPORT rimasto",
        g.frames, g.stale, g.worst, g.warp_left
    );
    // (le partite dell'NTSC, con i tempi diversi, e quelle con PADDWS_C64_PICK_RAW, quasi solo
    // ARCADE e BLASTER, non hanno un GUARDIAN che perde dei settori)
    let sh = shown.borrow();
    println!("  immagini delle racchette a schermo in partita NEXT (tipo: frame provati, sbagliati, al più di fila):");
    for (k, name) in KIND_NAMES.iter().enumerate() {
        let (n, bad, worst) = sh.per_kind[k];
        println!("    {name:<9} {n:>6} {bad:>5} {worst:>5}");
    }
    if sh.per_kind.iter().any(|&(_, _, worst)| worst > GUARDIAN_LAG_MAX) {
        println!("FAIL: racchetta a schermo diversa dall'immagine giusta per oltre {GUARDIAN_LAG_MAX} frame di fila");
        return false;
    }
    if (g.frames == 0 && !ntsc() && !pick_raw) || g.worst > GUARDIAN_LAG_MAX || g.warp_left > 0 {
        println!(
            "FAIL: racchetta GUARDIAN non provata, immagine dei settori persi oltre {GUARDIAN_LAG_MAX} frame in ritardo o pezzo del TELEPORT rimasto nello sprite"
        );
        return false;
    }
    // (sull'NTSC i tick più pesanti non stanno nel frame nemmeno sforando: lo scatto accettato, fino
    // allo 0,5%)
    let (limit, pct) = if ntsc() { (200, "0,5%") } else { (500, "0,2%") };
    if kept * limit > all {
        println!("FAIL: troppi frame con gli sprite del frame prima (oltre lo {pct})");
        return false;
    }
    let (fast, slow, extra) = tempo.get();
    println!("  tempo della musica: {fast} frame al match point, {slow} nel bullet time, al più {extra} passi in più in sospeso");
    if fast == 0 || slow == 0 || extra > 2 {
        println!("FAIL: tempo della musica non provato (match point o bullet time) o passi in più che si accumulano");
        return false;
    }
    // limite all'1%: la quota cambia con le partite che il giocatore simulato sceglie (con un altro
    // seme la 4.4.1 arrivava allo 0,68%, la 4.5.0 con questo allo 0,74%)
    if late * 100 > all {
        println!("FAIL: troppi tick della musica rimandati (oltre l'1%)");
        return false;
    }
    if voiced.1 == 0 {
        println!("FAIL: la voce di CHALLENGE non suona mai");
        return false;
    }
    if voiced.3 == 0 {
        println!("FAIL: il tema di CHALLENGE non suona mai");
        return false;
    }
    if forced.0 == 0 {
        println!("FAIL: nessun frame con il bullet time");
        return false;
    }
    let [gray, yellow, _, pulse, wrong] = border.get();
    println!(
        "  bordo GRAY in partita: {gray} frame grigio scuro, {yellow} giallo (SUPER o mossa MAX), {pulse} grigio pulsante (bullet time); {wrong} sbagliati"
    );
    if gray == 0 || yellow == 0 || pulse == 0 || wrong > 0 {
        println!("FAIL: bordo della partita non provato o sbagliato (fuori dalla partita deve tornare quello dello sfondo)");
        return false;
    }
    match border_logic(m) {
        Ok(s) => println!("  {s}"),
        Err(e) => {
            println!("FAIL: bordo della partita: {e}");
            return false;
        }
    }
    match scores_border(m) {
        Ok(s) => println!("  {s}"),
        Err(e) => {
            println!("FAIL: classifica: {e}");
            return false;
        }
    }
    match scores_rows(m) {
        Ok(s) => println!("  {s}"),
        Err(e) => {
            println!("FAIL: classifica: {e}");
            return false;
        }
    }
    match guardian_fast(m) {
        Ok(s) => println!("  {s}"),
        Err(e) => {
            println!("FAIL: {e}");
            return false;
        }
    }
    if over > 0 {
        println!("FAIL: {over} frame oltre il budget");
        return false;
    }
    println!("PASS: nessun frame oltre il budget");
    true
}

/// Classifica dall'attract (challenge.s), frame per frame: il bordo resta nero (niente effetti nel
/// bordo), ogni frame nel budget, la scena finisce. Il codice viene dalla cartuccia (hs_load),
/// quindi prima lo si cancella.
fn scores_border(m: &mut Machine) -> Result<String, String> {
    let (run, code) = m.moved_segment("HSCODE").map(|(a, c)| (a, c.len())).ok_or("niente HSCODE")?;
    m.cpu.mem[run as usize..run as usize + code].fill(0);
    m.write_u8("ch_hl", 0, 0xFF);
    m.call("enter_scores");
    let watch = m.cpu.watch.replace((0xD020, 0xD020));
    let frame = m.addr("frame");
    let (mut frames, mut worst) = (0u32, 0u64);
    let mut after = None;
    let mut applied = false;
    for f in 0..600 {
        m.cpu.writes.clear();
        // l'interrupt della riga 250 (qui non c'è): un frame in più
        let n = m.read_u8("frame_count", 0);
        m.write_u8("frame_count", 0, n.wrapping_add(1));
        let start = m.cpu.cycles;
        m.cpu.frame_start = Some(start);
        let before = m.read_u8("state", 0);
        let c = m.cpu.call(frame, 1_000_000)?;
        m.cpu.frame_start = None;
        m.cpu.idle(start + frame_cycles())?;
        // (al primo frame con la scena apply_shadows mette ancora il bordo della scena di prima;
        // sull'NTSC il frame senza scena non lo scrive e lo rimanda al frame dopo)
        let first = !applied;
        applied |= !scene_skipped(m);
        if before == ST_SCORES && !first {
            frames += 1;
            worst = worst.max(c);
            if let Some(&(_, v)) = m.cpu.writes.iter().find(|w| w.1 & 15 != 0) {
                return Err(format!("frame {f}: bordo non nero ({})", v & 15));
            }
        }
        if before == ST_SCORES && m.read_u8("state", 0) != ST_SCORES {
            after = Some(f);
            break;
        }
    }
    m.cpu.watch = watch;
    let Some(left) = after else {
        return Err("la classifica non finisce".into());
    };
    if frames < 300 || worst > FRAME_BUDGET() {
        return Err(format!("{frames} frame, cicli max {worst}"));
    }
    Ok(format!("classifica: {frames} frame con il bordo nero, cicli max {worst}; uscita al frame {left}"))
}

/// Righe della classifica (challenge.s, HS_ROWS = 8 dei 10 posti), come Scores::draw del PC: i
/// primi 8 posti, ma con il posto nuovo al 9° o 10° posto l'ultima riga è la sua, con il suo
/// numero; il posto nuovo giallo, gli altri bianchi, a tabella ferma.
fn scores_rows(m: &mut Machine) -> Result<String, String> {
    const ENTRY: u16 = 8;
    let saved: Vec<u8> = (0..10 * ENTRY).map(|i| m.read_u8("ch_table", i)).collect();
    // iniziali diverse per posto: AAA, BBB, ...
    for i in 0..10u16 {
        for c in 0..3 {
            m.write_u8("ch_table", i * ENTRY + c, b'A' + i as u8);
        }
    }
    let frame = m.addr("frame");
    let mut cases = 0;
    for (hl, last) in [(0xFFu8, 7u8), (3, 7), (7, 7), (8, 8), (9, 9)] {
        m.write_u8("ch_hl", 0, hl);
        m.call("enter_scores");
        for _ in 0..260 {
            let n = m.read_u8("frame_count", 0);
            m.write_u8("frame_count", 0, n.wrapping_add(1));
            m.cpu.frame_start = Some(m.cpu.cycles);
            m.cpu.call(frame, 1_000_000)?;
            m.cpu.frame_start = None;
            if m.read_u8("state", 0) != ST_SCORES {
                return Err(format!("posto nuovo {hl}: la classifica finisce prima del controllo"));
            }
        }
        for row in 0..8u16 {
            let place = if row == 7 { last } else { row as u8 };
            let rank = format!("{:>2}", place + 1);
            let name: String = std::iter::repeat_n((b'A' + place) as char, 3).collect();
            let y = 4 + 2 * row;
            if !text_at(m, 0xC000, y, 8, &rank) || !text_at(m, 0xC000, y, 13, &name) {
                return Err(format!("posto nuovo {hl}: la riga {row} non è il posto {}", place + 1));
            }
            let color = m.cpu.mem[0xD800 + (y * 40 + 13) as usize] & 15;
            let want = if place == hl { COL_YELLOW } else { 1 };
            if color != want {
                return Err(format!("posto nuovo {hl}: la riga {row} del colore {color}"));
            }
        }
        cases += 1;
    }
    for (i, v) in saved.into_iter().enumerate() {
        m.write_u8("ch_table", i as u16, v);
    }
    m.write_u8("ch_hl", 0, 0xFF);
    Ok(format!("classifica: 8 righe in {cases} casi, il 9° e il 10° posto nuovi nell'ultima riga con il loro numero"))
}

/// Bordo della partita (border_game, play.s) caso per caso: BLACK sempre 0 (quello dello sfondo),
/// GRAY grigio scuro, in PLAY con priorità giallo (SUPER o mossa di livello 2 in volo, solo in NEXT),
/// grigio pulsante (bullet time), rosso a tratti lenti (match point); fuori da PLAY grigio scuro.
fn border_logic(m: &mut Machine) -> Result<String, String> {
    let saved: Vec<(&str, u8)> = ["state", "opt_border", "m_next", "nx_super", "sm_fl", "sid_slow", "sid_fast", "frame_count"]
        .iter()
        .map(|&n| (n, m.read_u8(n, 0)))
        .collect();
    let mut cases = 0;
    // (stato, BORDER, NEXT, SUPER, sm_fl, bullet time, match point, frame) -> colori ammessi
    for state in [ST_PLAY, ST_COUNT] {
        for border in [0u8, 1] {
            for next in [0u8, 1] {
                for (sup, fl) in [(0u8, 0u8), (1, 0), (0, 1), (0, 5)] {
                    for slow in [0u8, 0x80] {
                        for fast in [0u8, 1] {
                            for frame in [0u8, 0x08, 0x10, 0x20, 0x38] {
                                for (n, v) in [("state", state), ("opt_border", border), ("m_next", next), ("nx_super", sup), ("sm_fl", fl), ("sid_slow", slow), ("sid_fast", fast), ("frame_count", frame)] {
                                    m.write_u8(n, 0, v);
                                }
                                m.call("border_game");
                                let got = m.read_u8("sh_brd", 0);
                                let pulse = [COL_DGRAY, COL_MGRAY, COL_GRAY, COL_MGRAY][(frame as usize >> 3) & 3];
                                let want = if border == 0 {
                                    0
                                } else if state != ST_PLAY {
                                    COL_DGRAY
                                } else if next != 0 && (sup != 0 || fl & 4 != 0) {
                                    COL_YELLOW
                                } else if slow != 0 {
                                    pulse
                                } else if fast != 0 && frame & 0x20 != 0 {
                                    COL_RED
                                } else {
                                    COL_DGRAY
                                };
                                if got != want {
                                    return Err(format!(
                                        "stato {state}, BORDER {border}, NEXT {next}, SUPER {sup}, sm_fl {fl}, bullet {slow}, match point {fast}, frame {frame}: {got} invece di {want}"
                                    ));
                                }
                                cases += 1;
                            }
                        }
                    }
                }
            }
        }
    }
    for (n, v) in saved {
        m.write_u8(n, 0, v);
    }
    Ok(format!("bordo della partita: {cases} casi di border_game come previsto"))
}

const KIND_NAMES: [&str; 7] = ["ARCADE", "TITAN", "HAMMER", "TWIST", "BLASTER", "RUSH", "GUARDIAN"];

/// Immagini giuste delle racchette (pad_image), per lato, tipo e variante come pad_variant: BLASTER
/// livello del caricatore * 32 (0-4), GUARDIAN settori persi (0-31), TWIST inclinazione + 3 (0-6),
/// gli altri 0. Fatte su una copia dello stato della CPU, che poi torna com'era.
fn paddle_images(m: &mut Machine) -> HashMap<(u8, u8, u8), Vec<u8>> {
    let saved = m.cpu.clone();
    let rows = m.addr("pv_rows");
    let base = m.addr("sh_img");
    let mut out = HashMap::new();
    for side in 0..2u8 {
        for kind in 0..7u8 {
            let n = m.cpu.read(rows + u16::from(kind));
            let vars: Vec<u8> = match kind {
                3 => (0..7).collect(),
                4 => (0..=4).collect(),
                6 => (0..32).collect(),
                _ => vec![0],
            };
            for var in vars {
                m.write_u8("pi_side", 0, side);
                m.write_u8("pi_kind", 0, kind);
                m.write_u8("pi_n", 0, n);
                m.write_u8("pi_var", 0, if kind == 4 { var * 32 } else { var });
                if kind == 4 {
                    m.cpu.a = var;
                    m.call("mag_vis");
                }
                m.call("pad_image");
                let img = base + 63 * u16::from(side);
                let key = (side, kind, if kind == 4 { var * 32 } else { var });
                out.insert(key, (0..63).map(|i| m.cpu.read(img + i)).collect());
            }
        }
    }
    m.cpu = saved;
    out
}

/// Racchette a schermo in partita NEXT, frame per frame: per tipo frame provati, frame con lo
/// sprite diverso dall'immagine giusta per lo stato del tick, il più lungo di fila.
#[derive(Default)]
struct ShownLag {
    per_kind: [(u32, u32, u32); 7],
    run: [u32; 2],
}

/// Lo sprite di ogni racchetta come si vedrà al prossimo vblank (l'immagine dinamica: sh_img se da
/// copiare, se no la RAM degli sprite sotto l'I/O; le preparate a $E000) contro paddle_images.
/// Non contano: il salto del TELEPORT, la rotazione del SUPER, la racchetta spenta, i frame che
/// tengono gli sprite di prima, altezze diverse da quella del tipo (OMEGA appena trasformato vicino
/// al bordo). Il lato di OMEGA sì, con la forma del momento (stesse immagini, colore a parte).
fn paddle_shown(m: &Machine, expected: &HashMap<(u8, u8, u8), Vec<u8>>, s: &mut ShownLag, voice: bool) {
    const SPN_PAD: u16 = 3;
    if m.read_u8("pd_made", 0) == 0xAA {
        return;
    }
    let (wp_on, wp_side) = (m.read_u8("wp_on", 0) != 0, m.read_u8("wp_side", 0));
    let enable = m.read_u8("sh_enable", 0);
    for side in 0..2u8 {
        let x = u16::from(side) * 4;
        let i = usize::from(side);
        let kind = m.read_u8("nx_kind", x);
        let skip = kind > 6
            || enable & (1 << (SPN_PAD + u16::from(side))) == 0
            || (wp_on && wp_side == side)
            || (m.read_u8("nx_armed", x) == 5 && m.read_u8("nx_anim", x) == 0)
            || m.read_u8("pd_cur_n", u16::from(side)) != m.cpu.read(m.addr("pv_rows") + u16::from(kind));
        if skip {
            s.run[i] = 0;
            continue;
        }
        let ptr = m.read_u8("sh_ptr", SPN_PAD + u16::from(side));
        let at = 0xC000 + u16::from(ptr) * 64;
        let img: Vec<u8> = if ptr == m.read_u8("pad_slot", u16::from(side)) && m.read_u8("pd_dirty", u16::from(side)) != 0 && !voice {
            let b = m.addr("sh_img") + 63 * u16::from(side);
            (0..63).map(|k| m.cpu.read(b + k)).collect()
        } else if (0xD000..0xE000).contains(&at) {
            m.cpu.under_io[usize::from(at - 0xD000)..usize::from(at - 0xD000) + 63].to_vec()
        } else {
            (0..63).map(|k| m.cpu.read(at + k)).collect()
        };
        let ok = match kind {
            3 => (0..7).any(|v| expected[&(side, 3, v)] == img),
            4 => expected[&(side, 4, m.read_u8("bl_vis", u16::from(m.read_u8("nx_ammo", x))) * 32)] == img,
            6 => expected[&(side, 6, !m.read_u8("nx_barrier", x) & 0x1F)] == img,
            _ => expected[&(side, kind, 0)] == img,
        };
        let e = &mut s.per_kind[usize::from(kind)];
        e.0 += 1;
        if ok {
            s.run[i] = 0;
        } else {
            e.1 += 1;
            s.run[i] += 1;
            e.2 = e.2.max(s.run[i]);
        }
    }
}

/// Frame di fila al più con l'immagine del GUARDIAN che non segue i settori persi (il frame del
/// tick che perde il settore può essere già avanti, e allora la rifà il frame dopo).
const GUARDIAN_LAG_MAX: u32 = 3;

/// Racchette GUARDIAN in partita NEXT (pad_sprite di video.s): frame con dei settori persi, frame
/// con l'immagine in ritardo (lo sprite non è l'immagine dinamica fatta con quei settori), il
/// ritardo più lungo di fila; per ogni tipo, frame con lo sprite dinamico della racchetta a schermo
/// che dopo il salto del TELEPORT ha ancora il pezzo del salto (pd_n = $FF: immagine da rifare).
#[derive(Clone, Copy, Default)]
struct GuardianLag {
    frames: u32,
    stale: u32,
    worst: u32,
    run: [u32; 2],
    warp_left: u32,
}

fn guardian_image(m: &Machine, g: &std::cell::Cell<GuardianLag>) {
    const SPN_PAD: u16 = 3;
    const K_GUARDIAN: u8 = 6;
    const B_SUPER: u8 = 5;
    let mut s = g.get();
    let (wp_on, wp_side) = (m.read_u8("wp_on", 0) != 0, m.read_u8("wp_side", 0));
    let enable = m.read_u8("sh_enable", 0);
    for side in 0..2u16 {
        let x = side * 4;
        let shown = enable & (1 << (SPN_PAD + side)) != 0;
        let warping = wp_on && u16::from(wp_side) == side;
        let ptr = m.read_u8("sh_ptr", SPN_PAD + side);
        let dynamic = ptr == m.read_u8("pad_slot", side);
        // (con il SUPER armato e la rotazione la racchetta è l'immagine dell'angolo)
        let spin = m.read_u8("nx_armed", x) == B_SUPER && m.read_u8("nx_anim", x) == 0;
        if shown && !warping && dynamic && m.read_u8("pd_n", side) == 0xFF {
            s.warp_left += 1;
        }
        let lost = !m.read_u8("nx_barrier", x) & 0x1F;
        if m.read_u8("nx_kind", x) != K_GUARDIAN || lost == 0 || warping || spin || !shown {
            s.run[side as usize] = 0;
            continue;
        }
        s.frames += 1;
        let ok = dynamic
            && m.read_u8("pd_kind", side) == K_GUARDIAN
            && m.read_u8("pd_var", side) == lost
            && m.read_u8("pd_n", side) == m.read_u8("pd_cur_n", side);
        let run = &mut s.run[side as usize];
        if ok {
            *run = 0;
        } else {
            s.stale += 1;
            *run += 1;
            s.worst = s.worst.max(*run);
        }
    }
    g.set(s);
}

/// L'immagine del GUARDIAN con dei settori persi fatta dal muro intero preparato (pad_sprite::guard):
/// per ogni lato e ogni combinazione di settori persi uguale byte per byte a quella di pad_image.
fn guardian_fast(m: &mut Machine) -> Result<String, String> {
    const K_GUARDIAN: u8 = 6;
    const IMG_BYTES: u16 = 63;
    let n = m.cpu.read(m.addr("pv_rows") + u16::from(K_GUARDIAN));
    let base = m.addr("sh_img");
    // il muro intero nel primo posto delle immagini preparate (a $E000, sotto il KERNAL spento)
    let slot = m.read_u8("prep_base", 0);
    let at = 0xC000 + usize::from(slot) * 64;
    let saved = m.cpu.mem[at..at + 64].to_vec();
    let next = m.read_u8("m_next", 0);
    m.write_u8("m_next", 0, 0); // (guard finisce in pad_spin: fuori da NEXT non fa niente)
    let mut worst = (0, 0);
    let mut result = Ok(());
    'sides: for side in 0..2u8 {
        let img = base + IMG_BYTES * u16::from(side);
        let read = |m: &Machine| (0..IMG_BYTES).map(|i| m.cpu.read(img + i)).collect::<Vec<u8>>();
        let image = |m: &mut Machine, var: u8| {
            m.write_u8("pi_side", 0, side);
            m.write_u8("pi_kind", 0, K_GUARDIAN);
            m.write_u8("pi_n", 0, n);
            m.write_u8("pi_var", 0, var);
            m.call("pad_image")
        };
        image(m, 0);
        let wall = read(m);
        m.cpu.mem[at..at + wall.len()].copy_from_slice(&wall);
        for lost in 1..32u8 {
            let slow = image(m, lost);
            let want = read(m);
            for i in 0..IMG_BYTES {
                m.cpu.write(img + i, 0x55);
            }
            m.write_u8("pi_side", 0, side);
            m.write_u8("pi_var", 0, lost);
            m.cpu.a = slot;
            m.cpu.y = side;
            let fast = m.call("guard");
            if read(m) != want {
                result = Err(format!("GUARDIAN lato {side}, settori persi {lost:05b}: l'immagine dal muro intero non è quella di pad_image"));
                break 'sides;
            }
            worst = (worst.0.max(fast), worst.1.max(slow));
        }
    }
    m.cpu.mem[at..at + 64].copy_from_slice(&saved);
    m.write_u8("m_next", 0, next);
    result.map(|()| {
        format!(
            "GUARDIAN con dei settori persi: le 31 immagini per lato dal muro intero come pad_image, al più {} cicli (pad_image {})",
            worst.0, worst.1
        )
    })
}

/// Le immagini delle racchette dei tipi (pad_image) come le prepara la scelta, a caratteri: una
/// cella dello sprite multicolore per carattere ("." niente, "-" grigio $D025, "o" colore dedicato
/// $D027+i, "#" bianco $D026); in più TWIST inclinata nei due versi e il GUARDIAN con due settori persi.
fn paddles(m: &mut Machine) -> bool {
    const NAMES: [&str; 7] = ["ARCADE", "TITAN", "HAMMER", "TWIST", "BLASTER", "RUSH", "GUARDIAN"];
    let (rows, vars) = (m.addr("pv_rows"), m.addr("pv_var"));
    let mut images = Vec::new();
    let mut cases: Vec<(String, u8, u8)> = (0..7u8).map(|k| (NAMES[k as usize].to_string(), k, m.cpu.read(vars + u16::from(k)))).collect();
    cases.push(("TWIST giù".into(), 3, 0));
    cases.push(("TWIST su".into(), 3, 6));
    cases.push(("GUARDIAN 1, 3".into(), 6, 0b01010));
    for (name, kind, var) in cases {
        let n = m.cpu.read(rows + u16::from(kind));
        m.write_u8("pi_side", 0, 0);
        m.write_u8("pi_kind", 0, kind);
        m.write_u8("pi_n", 0, n);
        m.write_u8("pi_var", 0, var);
        if kind == 4 {
            m.cpu.a = 4;
            m.call("mag_setup");
        }
        let c = m.call("pad_image");
        let base = m.addr("sh_img");
        let img: Vec<String> = (0..21u16)
            .map(|r| {
                (0..12u16)
                    .map(|cell| {
                        let b = m.cpu.read(base + 3 * r + cell / 4);
                        [".", "-", "o", "#"][usize::from((b >> (6 - 2 * (cell % 4))) & 3)]
                    })
                    .collect()
            })
            .collect();
        images.push((format!("{name} ({n} righe, {c} cicli)"), img));
    }
    for chunk in images.chunks(5) {
        println!("{}", chunk.iter().map(|(t, _)| format!("{t:<26}")).collect::<String>());
        for r in 0..21 {
            println!("{}", chunk.iter().map(|(_, img)| format!("{:<26}", img[r])).collect::<String>());
        }
        println!();
    }
    true
}

/// Colori del VIC-II (video.s)
const COL_RED: u8 = 2;
const COL_PURPLE: u8 = 4;
const COL_YELLOW: u8 = 7;
const COL_DGRAY: u8 = 11;
const COL_MGRAY: u8 = 12;
const COL_GRAY: u8 = 15;

/// Profilo: cicli per routine (solo le istruzioni della routine, non quelle che chiama) in una
/// partita EVO contro la CPU, su tutti i frame e su quelli oltre PROFILE_HEAVY.
fn profile(m: &mut Machine) -> bool {
    const PROFILE_HEAVY: u64 = 14_000;
    for r in ["title_unpack", "clear_vars", "math_init", "video_init", "input_init", "sid_init"] {
        m.call(r);
    }
    m.cpu.write(0xDC00, 0xFF);
    m.cpu.write(0xDC01, 0xFF);
    for (name, v) in [
        ("opt_mode", 1),
        ("opt_level", 1),
        ("opt_free", 1),
        ("opt_asound", 1),
        ("opt_players", 3),
    ] {
        m.write_u8(name, 0, v);
    }
    let labels: Vec<(u16, String)> = m.sorted_labels().to_vec();
    let routine = |pc: u16| match labels.binary_search_by_key(&pc, |l| l.0) {
        Ok(i) => i,
        Err(i) => i.saturating_sub(1),
    };
    let frame = m.addr("frame");
    let mut all = vec![0u64; labels.len()];
    let mut heavy = vec![0u64; labels.len()];
    let (mut frames, mut heavy_frames, mut total, mut heavy_total, mut worst) = (0u64, 0u64, 0u64, 0u64, 0u64);
    for part in ["start_game"] {
        m.call(part);
        for _ in 0..50 * 60 * 2 {
            m.cpu.profile = Some(vec![0; 0x10000]);
            let c = match m.cpu.call(frame, 1_000_000) {
                Ok(c) => c,
                Err(e) => {
                    println!("FAIL: {part}: {e}");
                    return false;
                }
            };
            let p = m.cpu.profile.take().unwrap_or_default();
            // solo i frame della partita: ci si ferma quando la partita finisce
            if m.read_u8("state", 0) == ST_OVER {
                break;
            }
            frames += 1;
            total += c;
            worst = worst.max(c);
            let is_heavy = c > PROFILE_HEAVY;
            if is_heavy {
                heavy_frames += 1;
                heavy_total += c;
            }
            for (pc, &n) in p.iter().enumerate() {
                if n > 0 {
                    let r = routine(pc as u16);
                    all[r] += n;
                    if is_heavy {
                        heavy[r] += n;
                    }
                }
            }
        }
    }
    let table = |title: &str, v: &[u64], n: u64, sum: u64| {
        println!("{title}: {n} frame, media {} cicli", sum / n.max(1));
        // le etichette locali si ripetono (skip, store...): l'indirizzo le distingue
        let mut rows: Vec<(u64, &(u16, String))> = v.iter().copied().zip(&labels).collect();
        rows.sort_by_key(|r| std::cmp::Reverse(r.0));
        for (c, (addr, name)) in rows.iter().take(25).filter(|r| r.0 > 0) {
            println!(
                "  ${addr:04X} {name:<20} {:6} cicli per frame {:5.1}%",
                c / n.max(1),
                *c as f64 * 100.0 / sum.max(1) as f64
            );
        }
    };
    table("tutti i frame", &all, frames, total);
    table(
        &format!("frame oltre {PROFILE_HEAVY}"),
        &heavy,
        heavy_frames,
        heavy_total,
    );
    println!("frame più pesante: {worst} cicli");

    // NEXT con due CPU del 6502 (ARCADE contro BLASTER, con TELEPORT): solo i tick, senza grafica
    m.write_u8("cfg_next", 0, 1);
    for (side, (loadout, kind)) in [([1u8, 0, 3], 0u8), ([2, 4, 6], 4)].into_iter().enumerate() {
        let o = (side * 4) as u16;
        for (k, b) in loadout.into_iter().enumerate() {
            m.write_u8("cfg_loadout", o + k as u16, b);
        }
        m.write_u8("cfg_kinds", o, kind);
    }
    m.write_u8("cfg_players", 0, 2);
    m.write_u8("cfg_diff", 0, 2);
    m.write_i32("cfg_seed", 0, 44);
    m.call("match_new");
    for side in 0..2u8 {
        m.cpu.a = 2;
        m.cpu.x = side * 4;
        m.call("cpu_init");
    }
    let (ci, ms) = (m.addr("cpu_input"), m.addr("match_step"));
    let (mut ticks, mut sum, mut worst_tick) = (0u64, 0u64, 0u64);
    let mut next = vec![0u64; labels.len()];
    for _ in 0..50 * 60 * 3 {
        m.cpu.profile = Some(vec![0; 0x10000]);
        let mut c = 0;
        for side in 0..2u8 {
            m.cpu.x = side * 4;
            c += match m.cpu.call(ci, 1_000_000) {
                Ok(c) => c,
                Err(e) => {
                    println!("FAIL: NEXT: {e}");
                    return false;
                }
            };
        }
        c += match m.cpu.call(ms, 1_000_000) {
            Ok(c) => c,
            Err(e) => {
                println!("FAIL: NEXT: {e}");
                return false;
            }
        };
        let p = m.cpu.profile.take().unwrap_or_default();
        ticks += 1;
        sum += c;
        worst_tick = worst_tick.max(c);
        for (pc, &n) in p.iter().enumerate() {
            if n > 0 {
                next[routine(pc as u16)] += n;
            }
        }
    }
    table("NEXT, due CPU, tick senza grafica", &next, ticks, sum);
    println!("tick NEXT più pesante: {worst_tick} cicli");
    true
}

/// Un frame del riferimento del SID: comandi (S canzone, X eventi) e scritture (registro, valore).
type SidFrame = (Vec<(char, u16)>, Vec<(u16, u8)>);

/// Valore di `localparam NOME = n;` in un file .vh generato.
fn vh_param(vh: &str, name: &str) -> Option<usize> {
    vh.lines().find_map(|l| {
        let rest = l.trim().strip_prefix("localparam ")?.strip_prefix(name)?;
        rest.trim_start().strip_prefix('=')?.split(';').next()?.trim().parse().ok()
    })
}

/// Inizi delle tracce nella ROM del MiSTer, da `sid_song_start` in sid_music.vh: per canzone
/// (da 1) gli indirizzi delle voci 0-2.
fn vh_song_starts(vh: &str) -> Vec<[usize; 3]> {
    let mut songs: Vec<[usize; 3]> = Vec::new();
    for l in vh.lines() {
        // {4'd7, 2'd1}: sid_song_start = 12'd901;
        let Some(rest) = l.trim().strip_prefix('{') else {
            continue;
        };
        let Some((key, value)) = rest.split_once("}: sid_song_start = ") else {
            continue;
        };
        let num = |s: &str| {
            s.split_once('d')
                .and_then(|(_, n)| n.trim().trim_end_matches(';').parse::<usize>().ok())
        };
        let Some((song, voice)) = key.split_once(',') else {
            continue;
        };
        let (Some(song), Some(voice), Some(addr)) = (num(song), num(voice), num(value)) else {
            continue;
        };
        if songs.len() < song {
            songs.resize(song, [0; 3]);
        }
        songs[song - 1][voice.min(2)] = addr;
    }
    songs
}

/// Costante `NOME = $hex` o `NOME = n` di un .inc generato (c64/gen), con il commento dopo `;`.
fn inc_const(inc: &str, name: &str) -> Option<usize> {
    inc.lines().find_map(|l| {
        let v = l.trim().strip_prefix(name)?.trim_start().strip_prefix('=')?;
        let v = v.split(';').next()?.trim();
        match v.strip_prefix('$') {
            Some(h) => usize::from_str_radix(h, 16).ok(),
            None => v.parse().ok(),
        }
    })
}

/// Player del SID: le scritture nei registri, frame per frame, devono essere quelle del player
/// Verilog registrate in c64/test/sid_reference.txt (mister/sim/sid/writes.ps1). Per il confronto
/// la ROM delle musiche è quella del MiSTer (frequenze per il clock a 1 MHz), senza i temi di
/// CHALLENGE (SID_ROM_BASE_SIZE byte, quanti ne ha sid_rom); per i temi (canzoni dalla
/// SID_SONG_THEME in poi) le tre tracce si copiano dalla ROM a THEME_BASE, una per pagina, come fa
/// il file voce, e il player suona la canzone SID_SONG_THEME.
fn sid(m: &mut Machine) -> bool {
    let root = c64_dir().join("..");
    let read = |p: PathBuf| std::fs::read_to_string(&p).map_err(|e| format!("{}: {e}", p.display()));
    let (hex, vh, inc) = match (
        read(root.join("mister/rtl/gen/sid_music.hex")),
        read(root.join("mister/rtl/gen/sid_music.vh")),
        read(c64_dir().join("gen/sid_music.inc")),
    ) {
        (Ok(h), Ok(v), Ok(i)) => (h, v, i),
        (h, v, i) => {
            for e in [h.err(), v.err(), i.err()].into_iter().flatten() {
                eprintln!("{e}");
            }
            return false;
        }
    };
    let rom: Vec<u8> = hex
        .split_whitespace()
        .map(|b| u8::from_str_radix(b, 16).unwrap())
        .collect();
    let starts = vh_song_starts(&vh);
    let (Some(base_size), Some(rom_size), Some(theme_song), Some(theme_base)) = (
        vh_param(&vh, "SID_ROM_BASE_SIZE"),
        vh_param(&vh, "SID_ROM_SIZE"),
        inc_const(&inc, "SID_SONG_THEME"),
        inc_const(&inc, "THEME_BASE"),
    ) else {
        eprintln!("sid_music.vh o sid_music.inc senza SID_ROM_BASE_SIZE, SID_ROM_SIZE, SID_SONG_THEME o THEME_BASE");
        return false;
    };
    if theme_song != SID_SONG_THEME as usize || theme_base != THEME_BASE as usize {
        eprintln!("SID_SONG_THEME o THEME_BASE di sid_music.inc diversi da quelli del banco di prova");
        return false;
    }
    let c64_rom = std::fs::read(c64_dir().join("gen/sid_music.bin")).unwrap_or_default();
    if c64_rom.len() != base_size || starts.len() < theme_song || rom.len() < rom_size {
        eprintln!(
            "sid_music.bin di {} byte invece di {base_size}, o {} canzoni nella ROM del MiSTer",
            c64_rom.len(),
            starts.len()
        );
        return false;
    }
    // tracce di un tema: dal suo inizio a quello della traccia dopo (o alla fine della ROM)
    let theme_tracks = |song: usize| -> Vec<&[u8]> {
        let mut bounds: Vec<usize> = starts.iter().flatten().copied().filter(|&a| a > 0).collect();
        bounds.push(rom_size);
        bounds.sort_unstable();
        starts[song - 1]
            .iter()
            .map(|&a| {
                let end = bounds.iter().copied().find(|&b| b > a).unwrap_or(rom_size);
                &rom[a..end]
            })
            .collect()
    };
    let base = m.addr("sid_rom");
    m.cpu.load(base, &rom[..base_size]);
    let reference = match std::fs::read_to_string(c64_dir().join("test/sid_reference.txt")) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("sid_reference.txt: {e}");
            return false;
        }
    };
    m.call("sid_init");
    // il rimbalzo del continue (effetto 9): la sua traccia sta in CLCODE, che il C64 copia a $C400
    // solo nella schermata del continue; qui la si mette al suo posto, presa dalla ROM della musica
    if let Some(id) = vh_param(&vh, "SID_FX_BOUNCE") {
        let start = vh
            .lines()
            .find(|l| l.contains("sid_fx_start =") && l.contains(&format!("4'd{id}:")))
            .and_then(|l| l.split_once("'d").and_then(|(_, r)| r.split_once("'d")).map(|(_, a)| a))
            .and_then(|a| a.trim_end_matches(';').trim().parse::<usize>().ok());
        let Some(start) = start else {
            println!("FAIL: inizio di SID_FX_BOUNCE non trovato in sid_music.vh");
            return false;
        };
        let end = rom[start..].iter().position(|&b| b == 0xFF).map_or(rom.len(), |i| start + i + 1);
        let at = m.cpu.read16(m.addr("fx_start") + 2 * id as u16);
        m.cpu.load(at, &rom[start..end]);
    }
    m.cpu.watch = Some((0xD400, 0xD418));
    // frame: comandi (S canzone, X eventi) e scritture attese
    let mut frames: Vec<SidFrame> = Vec::new();
    for line in reference.lines() {
        let mut parts = line.split_whitespace();
        let (Some(kind), Some(a)) = (parts.next(), parts.next()) else {
            continue;
        };
        match kind {
            "F" => frames.push((Vec::new(), Vec::new())),
            "S" | "X" => {
                let f = frames.last_mut().unwrap();
                f.0.push((kind.chars().next().unwrap(), a.parse().unwrap()));
            }
            "W" => {
                let v = u8::from_str_radix(parts.next().unwrap(), 16).unwrap();
                let r = u16::from_str_radix(a, 16).unwrap();
                frames.last_mut().unwrap().1.push((0xD400 + r, v));
            }
            _ => {}
        }
    }
    let mut worst = 0;
    let mut writes = 0;
    let mut themes = std::collections::BTreeSet::new();
    let mut omegas = std::collections::BTreeSet::new();
    let Some(omega0) = vh_param(&vh, "SID_SONG_OMEGA0") else {
        eprintln!("sid_music.vh senza SID_SONG_OMEGA0");
        return false;
    };
    for (n, (commands, expected)) in frames.iter().enumerate() {
        m.cpu.writes.clear();
        let mut cycles = 0;
        for &(kind, v) in commands {
            let mut v = v;
            if kind == 'S' && v as usize >= omega0 {
                // OMEGA: la sezione a THEME_BASE (omegaK_V.bin, le tracce della ROM: dopo l'ultima
                // la ROM continua), poi come per i temi
                let k = v as usize - omega0;
                let mut bins = Vec::new();
                for (i, t) in theme_tracks(v as usize).into_iter().enumerate() {
                    let bin = std::fs::read(c64_dir().join(format!("gen/omega{k}_{i}.bin"))).unwrap_or_default();
                    if bin.is_empty() || !t.starts_with(&bin) {
                        println!("FAIL: gen/omega{k}_{i}.bin diverso dalla traccia {i} della canzone {v}");
                        return false;
                    }
                    bins.push(bin);
                }
                let tracks: Vec<&[u8]> = bins.iter().map(Vec::as_slice).collect();
                if let Err(e) = load_omega(m, &tracks) {
                    println!("FAIL: canzone {v}: {e}");
                    return false;
                }
                if m.read_u8("sid_song_n", 0) == SID_SONG_OMEGA {
                    m.cpu.a = 0;
                    cycles += m.call("sid_song");
                }
                omegas.insert(v);
                v = SID_SONG_OMEGA as u16;
            } else if kind == 'S' && v as usize >= theme_song {
                // tema: le tracce a THEME_BASE; da un tema all'altro la canzone del C64 resta la
                // stessa, quindi prima il silenzio (nello stesso frame: riparte da capo come sul
                // MiSTer)
                for (i, t) in theme_tracks(v as usize).into_iter().enumerate() {
                    if t.len() > 256 {
                        println!("FAIL: traccia {i} della canzone {v} di {} byte, oltre una pagina", t.len());
                        return false;
                    }
                    m.cpu.load((theme_base + i * 0x100) as u16, t);
                }
                if m.read_u8("sid_song_n", 0) as usize == theme_song {
                    m.cpu.a = 0;
                    cycles += m.call("sid_song");
                }
                themes.insert(v);
                v = theme_song as u16;
            }
            if kind == 'X' && v & 0xFF == 0 && v & 0x100 != 0 {
                // rimbalzo del continue (bit 8): non ha un bit negli eventi di sid_fx, il C64 lo fa
                // partire per numero
                m.cpu.x = vh_param(&vh, "SID_FX_BOUNCE").unwrap_or(9) as u8;
                cycles += m.call("sid_fx_start");
                continue;
            }
            m.cpu.a = v as u8;
            cycles += m.call(if kind == 'S' { "sid_song" } else { "sid_fx" });
        }
        cycles += m.call("sid_tick");
        worst = worst.max(cycles);
        writes += expected.len();
        if &m.cpu.writes != expected {
            let fmt = |w: &[(u16, u8)]| {
                w.iter()
                    .map(|(a, v)| format!("{:02x}={v:02x}", a - 0xD400))
                    .collect::<Vec<_>>()
                    .join(" ")
            };
            println!(
                "FAIL: frame {n}\n    Verilog {}\n    6502    {}",
                fmt(expected),
                fmt(&m.cpu.writes)
            );
            return false;
        }
    }
    if themes.len() < 2 || omegas.len() < OMEGA_SECTIONS {
        println!(
            "FAIL: il riferimento suona {} temi di CHALLENGE invece di almeno 2 e {} sezioni di OMEGA invece di {OMEGA_SECTIONS}",
            themes.len(),
            omegas.len()
        );
        return false;
    }
    println!(
        "PASS: {} frame, {writes} scritture identiche al player Verilog, {} temi di CHALLENGE e {} sezioni di OMEGA (cicli per frame max {worst})",
        frames.len(),
        themes.len(),
        omegas.len()
    );
    // tempo della canzone (match point, bullet time) contro il player Rust (rust/sid), verificato
    // a sua volta contro il Verilog: a ogni passo del 6502 lo stesso passo del player Rust, con lo
    // stesso stato del bullet time; al match point 5 passi ogni 4 frame
    const TEMPO_FRAMES: usize = 600;
    let bullet = |n: usize| (90..240).contains(&n) || n == 300 || (330..331).contains(&n) || (400..520).contains(&n);
    let mut tempo_writes = 0;
    let mut tempo_worst = 0;
    for song in [1usize, 2, 7, 9, 11, 13, omega0, omega0 + 5] {
        for (fast, slow) in [(false, true), (true, false), (true, true)] {
            m.call("sid_init");
            m.cpu.a = 0;
            m.call("sid_tempo");
            let c64_song = if song >= omega0 {
                let k = song - omega0;
                let bins: Vec<Vec<u8>> =
                    (0..3).map(|i| std::fs::read(c64_dir().join(format!("gen/omega{k}_{i}.bin"))).unwrap_or_default()).collect();
                let tracks: Vec<&[u8]> = bins.iter().map(Vec::as_slice).collect();
                if let Err(e) = load_omega(m, &tracks) {
                    println!("FAIL: canzone {song}: {e}");
                    return false;
                }
                SID_SONG_OMEGA
            } else if song >= theme_song {
                for (i, t) in theme_tracks(song).into_iter().enumerate() {
                    m.cpu.load((theme_base + i * 0x100) as u16, t);
                }
                theme_song as u8
            } else {
                song as u8
            };
            m.cpu.a = c64_song;
            m.call("sid_song");
            let mut player = paddws_sid::player::Player::new(paddws_sid::Rom::builtin());
            player.set_song(song as u8);
            let mut steps = 0;
            for n in 0..TEMPO_FRAMES {
                let on = slow && bullet(n);
                m.cpu.a = fast as u8 | if on { 0x80 } else { 0 };
                m.call("sid_tempo");
                for routine in ["sid_tick", "sid_more"] {
                    let extra = m.read_u8("sid_extra", 0);
                    m.cpu.writes.clear();
                    let c = m.call(routine);
                    tempo_worst = tempo_worst.max(c);
                    if routine == "sid_more" && extra == 0 {
                        if !m.cpu.writes.is_empty() {
                            println!("FAIL: canzone {song}, frame {n}: sid_more senza passi in sospeso scrive");
                            return false;
                        }
                        continue;
                    }
                    let mut want: Vec<(u16, u8)> = Vec::new();
                    player.set_slow(on);
                    player.tick(&mut |r: u8, v: u8| want.push((0xD400 + r as u16, v)));
                    steps += 1;
                    tempo_writes += want.len();
                    if m.cpu.writes != want {
                        let fmt = |w: &[(u16, u8)]| {
                            w.iter().map(|(a, v)| format!("{:02x}={v:02x}", a - 0xD400)).collect::<Vec<_>>().join(" ")
                        };
                        println!(
                            "FAIL: canzone {song} (match point {fast}, bullet time {slow}), frame {n}, {routine}
    Rust {}
    6502 {}",
                            fmt(&want),
                            fmt(&m.cpu.writes)
                        );
                        return false;
                    }
                }
            }
            let want_steps = if fast { TEMPO_FRAMES * 5 / 4 } else { TEMPO_FRAMES };
            if steps != want_steps {
                println!("FAIL: canzone {song}, match point {fast}: {steps} passi in {TEMPO_FRAMES} frame invece di {want_steps}");
                return false;
            }
        }
    }
    println!(
        "PASS: tempo della canzone (match point, bullet time e tutte e due, 8 canzoni con 2 di OMEGA) identico al player Rust: {tempo_writes} scritture (cicli max {tempo_worst})"
    );
    // cicli del player in partita (dopo il primo passo, che fa partire la canzone): i temi e le
    // sezioni di OMEGA, al match point (passo in più con sid_more), per SID_TICK_MAX di play.s
    let mut tick_worst = [0u64; 2];
    for song in (theme_song..theme_song + 7).chain(omega0..omega0 + OMEGA_SECTIONS) {
        let omega = song >= omega0;
        m.call("sid_init");
        m.cpu.a = 1;
        m.call("sid_tempo");
        if omega {
            let k = song - omega0;
            let bins: Vec<Vec<u8>> =
                (0..3).map(|i| std::fs::read(c64_dir().join(format!("gen/omega{k}_{i}.bin"))).unwrap_or_default()).collect();
            let tracks: Vec<&[u8]> = bins.iter().map(Vec::as_slice).collect();
            if load_omega(m, &tracks).is_err() {
                return false;
            }
            m.cpu.a = SID_SONG_OMEGA;
        } else {
            for (i, t) in theme_tracks(song).into_iter().enumerate() {
                m.cpu.load((theme_base + i * 0x100) as u16, t);
            }
            m.cpu.a = theme_song as u8;
        }
        m.call("sid_song");
        m.call("sid_tick");
        for _ in 0..1500 {
            let c = m.call("sid_tick");
            tick_worst[omega as usize] = tick_worst[omega as usize].max(c);
        }
    }
    println!(
        "PASS: player in partita: cicli per passo al più {} con i temi, {} con le sezioni di OMEGA",
        tick_worst[0], tick_worst[1]
    );
    // il finale di CHALLENGE (ENDING del MiSTer, SID_SONG_ENDING del C64): le tracce di
    // gen/ending.bin, uguali a quelle della ROM, dove le copia il finale (ending.s); una volta e
    // mezza la canzone, che ricomincia, contro il player Rust, con il filtro di tutte e due le voci
    // e la stessa canzone letta dalla cartuccia (SID_SONG_EGG, l'easter egg delle iniziali), con la
    // bitmap dell'attract dove il finale mette le tracce
    for egg in [false, true] {
        match ending_song(m, &rom, &vh, egg) {
            Ok(line) => println!("PASS: {line}"),
            Err(e) => {
                println!("FAIL: canzone del finale{}: {e}", if egg { " dalla cartuccia" } else { "" });
                return false;
            }
        }
    }
    m.cpu.watch = None;
    true
}

/// Canzone del finale di CHALLENGE contro il player Rust (vedi `sid`). Con `egg` è SID_SONG_EGG,
/// la canzone che l'easter egg delle iniziali mette al posto di quella del titolo: le tracce restano
/// nella cartuccia (egg_stage le legge comando per comando), mentre dove le copia il finale c'è
/// altro (la bitmap dell'attract); ogni volta la cartuccia di nuovo spenta e $01 = $35.
fn ending_song(m: &mut Machine, rom: &[u8], vh: &str, egg: bool) -> Result<String, String> {
    let ending = vh_param(vh, "SID_SONG_ENDING").ok_or("sid_music.vh senza SID_SONG_ENDING")?;
    let starts = vh_song_starts(vh);
    let bin = std::fs::read(c64_dir().join("gen/ending.bin")).map_err(|e| format!("ending.bin: {e}"))?;
    let [bass, lead, arp] = starts[ending - 1];
    if rom.get(bass..bass + bin.len()) != Some(&bin[..]) || lead - bass >= arp - bass {
        return Err("gen/ending.bin diverso dalle tracce di ENDING nella ROM".into());
    }
    // (sid_init è tra le routine dell'avvio, dove nel finale c'è la canzone: rimesse e chiamata
    // prima) e i frame di rilascio delle canzoni di prima a zero, come nel player Rust nuovo
    if let Some((at, code)) = m.moved_segment("BOOTCODE").map(|(a, c)| (a, c.to_vec())) {
        m.cpu.load(at, &code);
    }
    m.call("sid_init");
    for c in 0..4 {
        m.write_u8("ch_rel", c, 0);
    }
    for (label, from, to) in [("end_bass", bass, lead), ("end_lead", lead, arp), ("end_arp", arp, bass + bin.len())] {
        let at = m.addr(label) as usize;
        if egg {
            m.cpu.mem[at..at + to - from].fill(0x55);
        } else {
            m.cpu.load(at as u16, &rom[from..to]);
        }
    }
    m.cpu.a = 0;
    m.call("sid_tempo");
    m.cpu.a = if egg { SID_SONG_EGG } else { SID_SONG_ENDING };
    m.call("sid_song");
    let mut player = paddws_sid::player::Player::new(paddws_sid::Rom::builtin());
    player.set_song(ending as u8);
    let (mut writes, mut worst, mut filter) = (0, 0, 0);
    for n in 0..4800 {
        m.cpu.writes.clear();
        worst = worst.max(m.call("sid_tick"));
        if m.cpu.mem[1] != 0x35 || m.cpu.ef.as_ref().is_some_and(|ef| ef.mode != EF_OFF) {
            return Err(format!("frame {n}: cartuccia accesa o $01 = {:02x} dopo il passo", m.cpu.mem[1]));
        }
        let mut want: Vec<(u16, u8)> = Vec::new();
        player.tick(&mut |r: u8, v: u8| want.push((0xD400 + r as u16, v)));
        writes += want.len();
        filter += want.iter().filter(|w| (0xD415..=0xD418).contains(&w.0)).count();
        if m.cpu.writes != want {
            let fmt = |w: &[(u16, u8)]| w.iter().map(|(a, v)| format!("{:02x}={v:02x}", a - 0xD400)).collect::<Vec<_>>().join(" ");
            return Err(format!("frame {n}
    Rust {}
    6502 {}", fmt(&want), fmt(&m.cpu.writes)));
        }
    }
    if filter == 0 {
        return Err("la canzone del finale non usa il filtro".into());
    }
    if egg {
        return Ok(format!(
            "canzone del finale letta dalla cartuccia (SID_SONG_EGG, l'easter egg) identica al player Rust per 4800 frame: {writes} scritture (cicli max {worst})"
        ));
    }
    Ok(format!(
        "canzone del finale (SID_SONG_ENDING, tracce di ending.bin) identica al player Rust per 4800 frame: {writes} scritture, {filter} al filtro (cicli max {worst})"
    ))
}

/// Scrive c64/gen/params.inc, o con `check` verifica che sia aggiornato.
/// Parametri del core per il C64: `c64/gen/params.inc` (PAL, 50 Hz) e `c64/gen/ntsc/params.inc` (NTSC, 60
/// Hz), che la build NTSC trova prima (`c64/build.ps1 -Ntsc`). Con `check` solo il confronto.
fn params(check: bool) -> bool {
    let was = ntsc();
    let mut ok = true;
    for (tv_ntsc, file) in [(false, "gen/params.inc"), (true, "gen/ntsc/params.inc")] {
        set_ntsc(tv_ntsc);
        let path = c64_dir().join(file);
        let text = params_inc();
        if check {
            let current = std::fs::read_to_string(&path).unwrap_or_default().replace("\r\n", "\n");
            if current != text {
                println!("{} non è aggiornato: rigenerarlo con paddws-c64 params", path.display());
                ok = false;
            } else {
                println!("{} aggiornato", path.display());
            }
            continue;
        }
        if let Err(e) = std::fs::create_dir_all(path.parent().unwrap()).and_then(|_| std::fs::write(&path, text)) {
            eprintln!("{}: {e}", path.display());
            ok = false;
        } else {
            println!("{}", path.display());
        }
    }
    set_ntsc(was);
    ok
}

// ------------------------------------------------------------------------------------ aritmetica

/// Valori di prova: estremi, piccoli, della grandezza di posizioni e velocità, qualsiasi.
fn sample(rng: &mut Rng) -> i32 {
    let x = rng.next_u32() as i32;
    match rng.next_u32() % 8 {
        0 => [0, 1, -1, i32::MIN, i32::MAX, 65536, -65536, 0x7FFF][(rng.next_u32() % 8) as usize],
        1 => x >> 24,
        2 => x >> 16,
        3 => x >> 12,
        4 => x >> 8,
        5 => x >> 4,
        _ => x,
    }
}

/// Aritmetica a 32 bit e generatore: ogni routine 6502 contro la funzione del core.
fn math(m: &mut Machine, trials: u32) -> bool {
    m.call("math_init");
    let mut rng = Rng::new(12345);
    let mut fails = 0;
    let mut worst = [0u64; 4];
    for i in 0..trials {
        let (a, b) = (sample(&mut rng), sample(&mut rng));
        for (k, (routine, expect)) in [("mul_q16", mul(a, b)), ("mul_q24", mul_recip(a, b))]
            .into_iter()
            .enumerate()
        {
            m.write_i32("m_a", 0, a);
            m.write_i32("m_b", 0, b);
            let cycles = m.call(routine);
            worst[k] = worst[k].max(cycles);
            let got = m.read_i32("m_a", 0);
            if got != expect && fails < 10 {
                println!("{routine}({a}, {b}) = {got}, atteso {expect}");
                fails += 1;
            }
        }
        // generatore: stato qualsiasi diverso da zero
        let seed = (rng.next_u32() | 1) as i32;
        let mut r = Rng::new(seed as u32);
        let expect = r.next_u32() as i32;
        m.write_i32("rng", 0, seed);
        worst[2] = worst[2].max(m.call("rng_next"));
        let got = m.read_i32("rng", 0);
        if got != expect && fails < 10 {
            println!("rng_next({seed:#x}) = {got:#x}, atteso {expect:#x}");
            fails += 1;
        }
        let n = if i % 2 == 0 {
            rng.next_u32() & 0xFFFF
        } else {
            [1, 2, 3, 8, 60, 240, 1000, 65535][i as usize / 2 % 8]
        };
        let mut r = Rng::new(seed as u32);
        let expect = r.below(n);
        m.write_i32("rng", 0, seed);
        m.write_i32("m_b", 0, n as i32);
        worst[3] = worst[3].max(m.call("rng_below"));
        let got = m.cpu.a as u32 | (m.cpu.x as u32) << 8;
        if got != expect && fails < 10 {
            println!("rng_below({seed:#x}, {n}) = {got}, atteso {expect}");
            fails += 1;
        }
    }
    println!(
        "{trials} prove: cicli al massimo mul_q16 {}, mul_q24 {}, rng_next {}, rng_below {}",
        worst[0], worst[1], worst[2], worst[3]
    );
    if fails == 0 {
        println!("PASS: aritmetica e generatore identici al core Rust");
    } else {
        println!("FAIL");
    }
    fails == 0
}

// ------------------------------------------------------------------------------------ partite

/// Chi gioca una partita di prova.
#[derive(Clone, Copy)]
enum Drive {
    /// giocatori simulati con il joystick (come le tracce del MiSTer)
    Script,
    /// come Script, ma il giocatore sinistro usa la manopola (posizione assoluta)
    Encoder,
    /// due CPU del core, comandi confrontati con quelle del 6502
    Cpu,
    /// come Script, con selezione, attivazione e sparo a caso (NEXT)
    ScriptNext,
    /// come ScriptNext, con il giocatore sinistro alla manopola
    EncoderNext,
    /// CHALLENGE dopo una sfida vinta da destra: la CPU del core a sinistra (comandi confrontati
    /// con quella del 6502), il giocatore simulato a destra, con i suoi punti arcade
    CpuLeft,
    /// mosse speciali: il giocatore sinistro al joystick (porta 2) con i gesti (`JoySim`), letto
    /// dal 6502 (read_input, build_input) e dato al core così; a destra la CPU
    Joy,
    /// come Joy, con tutti e due i giocatori al joystick (il destro sulla porta 1)
    Joy2,
}

/// NEXT: bonus scelti e tipi di racchetta (sinistra, destra).
type NextSetup = ([[Bonus; 3]; 2], [Option<PaddleKind>; 2]);

/// Bonus delle tracce NEXT del MiSTer: i due giocatori ne hanno di diversi.
const LOADOUTS: [[Bonus; 3]; 2] = [
    [Bonus::Smash, Bonus::Teleport, Bonus::Curve],
    [Bonus::Slow, Bonus::Ghost, Bonus::Steer],
];

struct Scenario {
    name: &'static str,
    players: u8,
    evo: bool,
    difficulty: u8,
    seed: u32,
    drive: Drive,
    /// livelli delle CPU (Drive::Cpu): sinistra, destra
    levels: [u8; 2],
    /// partita NEXT
    next: Option<NextSetup>,
    /// mosse speciali accese (SUPER MOVES)
    supers: bool,
    /// OMEGA (`Match::set_morph`): il lato che cambia forma a ogni punto subito, quello della
    /// CPU di CHALLENGE al livello CH_OMEGA (dall'altro lato chi gioca)
    morph: Option<Side>,
}

/// Scenario di prova: nome, giocatori, EVO, difficoltà, seme, chi gioca, livelli delle CPU.
const fn sc(
    name: &'static str,
    players: u8,
    evo: bool,
    difficulty: u8,
    seed: u32,
    drive: Drive,
    levels: [u8; 2],
) -> Scenario {
    Scenario {
        name,
        players,
        evo,
        difficulty,
        seed,
        drive,
        levels,
        next: None,
        supers: false,
        morph: None,
    }
}

/// Scenario NEXT: nome, difficoltà, seme, chi gioca, livelli delle CPU, tipi di racchetta.
const fn nx(
    name: &'static str,
    difficulty: u8,
    seed: u32,
    drive: Drive,
    levels: [u8; 2],
    kinds: [Option<PaddleKind>; 2],
) -> Scenario {
    Scenario {
        name,
        players: 2,
        evo: false,
        difficulty,
        seed,
        drive,
        levels,
        next: Some((LOADOUTS, kinds)),
        supers: false,
        morph: None,
    }
}

/// Scenario NEXT con le mosse speciali (come `nx`).
const fn sx(
    name: &'static str,
    difficulty: u8,
    seed: u32,
    drive: Drive,
    levels: [u8; 2],
    kinds: [Option<PaddleKind>; 2],
) -> Scenario {
    Scenario {
        supers: true,
        ..nx(name, difficulty, seed, drive, levels, kinds)
    }
}

/// CHALLENGE con chi gioca a destra (ha vinto una sfida da quel lato): bonus e racchette come
/// `Rung::sides`, la CPU del livello a sinistra, la velocità della palla del livello.
const fn challenge_right(name: &'static str, level: usize, seed: u32, kind: PaddleKind) -> Scenario {
    let rung = RUNGS[level];
    let (loadouts, kinds) = rung.sides(Side::Right, LOADOUTS[1], Some(kind));
    Scenario {
        name,
        players: 2,
        evo: false,
        difficulty: rung.speed_at(1),
        seed,
        drive: Drive::CpuLeft,
        levels: [rung.cpu, 0],
        next: Some((loadouts, kinds)),
        supers: false,
        morph: None,
    }
}

/// OMEGA: CPU contro CPU con le mosse speciali, la racchetta del lato `morph` in ARCADE con i
/// bonus di OMEGA (quelli di ARCADE), l'altra del tipo `kind`, alla velocità di OMEGA a HARD.
const fn omega(name: &'static str, seed: u32, morph: Side, levels: [u8; 2], kind: PaddleKind) -> Scenario {
    let (loadouts, kinds) = match morph {
        Side::Right => ([LOADOUTS[0], OMEGA.loadout], [Some(kind), Some(OMEGA.kind)]),
        Side::Left => ([OMEGA.loadout, LOADOUTS[1]], [Some(OMEGA.kind), Some(kind)]),
    };
    Scenario {
        morph: Some(morph),
        next: Some((loadouts, kinds)),
        ..sx(name, OMEGA.speed_at(2), seed, Drive::Cpu, levels, [None, None])
    }
}

const SCENARIOS: [Scenario; 36] = [
    sc("evo", 2, true, 1, 1, Drive::Script, [0, 0]),
    sc("evo_s2", 2, true, 1, 2, Drive::Script, [0, 0]),
    sc("evo_d0", 2, true, 0, 5, Drive::Script, [0, 0]),
    sc("evo_d3", 2, true, 3, 6, Drive::Script, [0, 0]),
    sc("classic", 2, false, 1, 7, Drive::Script, [0, 0]),
    sc("single", 1, false, 1, 4, Drive::Script, [0, 0]),
    sc("single_d3", 1, false, 3, 8, Drive::Script, [0, 0]),
    sc("encoder", 2, true, 1, 31, Drive::Encoder, [0, 0]),
    sc("cpu_evo", 2, true, 2, 21, Drive::Cpu, [2, 2]),
    sc("cpu_classic", 2, false, 3, 22, Drive::Cpu, [3, 3]),
    sc("cpu_easy", 2, true, 0, 23, Drive::Cpu, [0, 1]),
    sc("cpu_ladder", 2, true, 1, 24, Drive::Cpu, [4, 10]),
    sc("cpu_zero", 2, false, 1, 0, Drive::Cpu, [7, 9]),
    nx("next", 1, 9, Drive::Cpu, [1, 1], [None, None]),
    nx("next_d2", 2, 13, Drive::Cpu, [2, 2], [None, None]),
    nx(
        "kinds_bg",
        1,
        41,
        Drive::Cpu,
        [1, 1],
        [Some(PaddleKind::Blaster), Some(PaddleKind::Guardian)],
    ),
    nx(
        "kinds_tt",
        1,
        42,
        Drive::Cpu,
        [1, 1],
        [Some(PaddleKind::Titan), Some(PaddleKind::Twist)],
    ),
    nx(
        "kinds_hr",
        3,
        43,
        Drive::Cpu,
        [3, 3],
        [Some(PaddleKind::Hammer), Some(PaddleKind::Rush)],
    ),
    nx(
        "kinds_ab",
        2,
        44,
        Drive::Cpu,
        [2, 2],
        [Some(PaddleKind::Arcade), Some(PaddleKind::Blaster)],
    ),
    nx(
        "ladder",
        2,
        46,
        Drive::Cpu,
        [3, 10],
        [Some(PaddleKind::Rush), Some(PaddleKind::Guardian)],
    ),
    nx(
        "next_script",
        1,
        51,
        Drive::ScriptNext,
        [0, 0],
        [Some(PaddleKind::Blaster), Some(PaddleKind::Twist)],
    ),
    nx(
        "next_knob",
        1,
        52,
        Drive::EncoderNext,
        [0, 0],
        [Some(PaddleKind::Titan), Some(PaddleKind::Arcade)],
    ),
    nx(
        "next_steer",
        1,
        53,
        Drive::EncoderNext,
        [0, 0],
        [None, Some(PaddleKind::Guardian)],
    ),
    challenge_right("ch_right_l2", 1, 61, PaddleKind::Titan),
    challenge_right("ch_right_l7", 6, 62, PaddleKind::Blaster),
    // mosse speciali: CPU contro CPU con i tipi di racchetta (STRAIGHT SHOT sul boost di HAMMER,
    // RUSH e dello scatto, RISING STRIKE contro TELEPORT, GUARDIAN, BLASTER), poi i gesti
    sx("super", 1, 71, Drive::Cpu, [1, 1], [None, None]),
    sx(
        "super_d3",
        3,
        72,
        Drive::Cpu,
        [3, 3],
        [Some(PaddleKind::Hammer), Some(PaddleKind::Rush)],
    ),
    sx(
        "super_bg",
        2,
        73,
        Drive::Cpu,
        [2, 6],
        [Some(PaddleKind::Blaster), Some(PaddleKind::Guardian)],
    ),
    sx(
        "super_at",
        0,
        74,
        Drive::Cpu,
        [0, 10],
        [Some(PaddleKind::Arcade), Some(PaddleKind::Titan)],
    ),
    sx("super_tw", 2, 75, Drive::Cpu, [5, 8], [Some(PaddleKind::Twist), None]),
    sx("super_joy", 1, 76, Drive::Joy, [0, 2], [None, Some(PaddleKind::Rush)]),
    sx(
        "super_joy2",
        1,
        77,
        Drive::Joy2,
        [0, 0],
        [Some(PaddleKind::Hammer), None],
    ),
    sx(
        "super_joy_d3",
        3,
        78,
        Drive::Joy,
        [0, 6],
        [Some(PaddleKind::Titan), Some(PaddleKind::Arcade)],
    ),
    // OMEGA: la racchetta che cambia forma a ogni punto subito, da tutti e due i lati
    omega("omega", 81, Side::Right, [10, 11], PaddleKind::Rush),
    omega("omega_left", 82, Side::Left, [11, 10], PaddleKind::Blaster),
    omega("omega_g", 84, Side::Right, [11, 11], PaddleKind::Guardian),
];

/// Giocatori simulati come quelli di paddws-trace: inseguono la palla con un errore che cambia
/// di tanto in tanto, a volte esitano e ogni tanto scattano in avanti.
struct Script {
    rng: Rng,
    hold: [u32; 2],
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

    fn next(&mut self, m: &Match, encoder: bool) -> Input {
        let mut input = Input::default();
        for i in 0..2 {
            if self.hold[i] == 0 {
                self.aim[i] = self.rng.range(-15, 16);
                self.idle[i] = if self.rng.range(0, 5) == 0 {
                    self.rng.range(2, 12) as u32
                } else {
                    0
                };
                self.hold[i] = self.rng.range(6, 40) as u32;
            }
            self.hold[i] -= 1;
            let cmd = &mut input.players[i];
            if self.idle[i] > 0 {
                self.idle[i] -= 1;
            } else {
                let target = fixed::floor(m.ball.y) + self.aim[i];
                let diff = target - fixed::floor(m.paddles[i].y);
                cmd.direction = diff.signum() as i8 * (diff.abs() > 2) as i8;
                cmd.fast = diff.abs() > 30;
                if encoder && i == 0 {
                    // manopola: verso il bersaglio, al massimo 12 pixel per tick
                    let half = fixed::floor(m.paddles[0].height / 2);
                    let h = fixed::floor(m.params.height);
                    let knob = h - half - fixed::floor(m.paddles[0].y) - diff.clamp(-12, 12);
                    cmd.top_offset = Some(knob.clamp(0, h - 2 * half));
                    cmd.direction = 0;
                }
            }
            cmd.forward = self.rng.range(0, 80) == 0;
        }
        input
    }

    /// Come `next`, con selezione, attivazione e sparo a caso (NEXT).
    fn next_next(&mut self, m: &Match, encoder: bool) -> Input {
        let mut input = self.next(m, encoder);
        for cmd in &mut input.players {
            cmd.select = self.rng.range(0, 90) == 0;
            cmd.activate = self.rng.range(0, 60) == 0;
            cmd.fire = self.rng.range(0, 40) == 0;
        }
        input
    }
}

/// Giocatori al joystick simulati per le mosse speciali (porta 2 il sinistro, porta 1 il destro):
/// inseguono la palla con su e giù e, con la palla in arrivo, fanno i gesti del C64 (giù,
/// giù-avanti, avanti + fuoco = STRAIGHT SHOT; avanti, giù, giù-avanti + fuoco = RISING STRIKE),
/// ogni direzione tenuta 1-4 frame; a volte troppo lenti o con la barra vuota (allora il fuoco
/// attiva il bonus). Ogni tanto rientrano dallo scatto o premono il fuoco da soli.
struct JoySim {
    rng: Rng,
    /// joystick dei prossimi frame (bit JOY_* a 1 = premuto), per giocatore
    queue: [std::collections::VecDeque<u8>; 2],
    /// gesti finiti con il fuoco: (giocatore, frame da cui è premuto)
    fired: Vec<usize>,
}

impl JoySim {
    const UP: u8 = 0x01;
    const DOWN: u8 = 0x02;
    const LEFT: u8 = 0x04;
    const RIGHT: u8 = 0x08;
    const FIRE: u8 = 0x10;

    fn new(seed: u32) -> Self {
        Self {
            rng: Rng::new(seed ^ 0x0607_7E57),
            queue: Default::default(),
            fired: Vec::new(),
        }
    }

    /// Joystick del giocatore `side` per il prossimo frame (bit a 1 = premuto).
    fn frame(&mut self, g: &Match, side: usize) -> u8 {
        self.fired.retain(|&s| s != side);
        if let Some(bits) = self.queue[side].pop_front() {
            if bits & Self::FIRE != 0 && bits & !Self::FIRE != 0 {
                self.fired.push(side);
            }
            return bits;
        }
        let (fwd, back) = if side == 0 {
            (Self::RIGHT, Self::LEFT)
        } else {
            (Self::LEFT, Self::RIGHT)
        };
        let coming = (g.ball.vx < 0) == (side == 0);
        if coming && self.rng.below(12) == 0 {
            // un gesto: tre direzioni, il fuoco con l'ultima, poi tutto rilasciato
            let rise = self.rng.below(2) == 1;
            let steps = if rise {
                [fwd, Self::DOWN, Self::DOWN | fwd]
            } else {
                [Self::DOWN, Self::DOWN | fwd, fwd]
            };
            let slow = self.rng.below(6) == 0;
            for (k, dir) in steps.into_iter().enumerate() {
                let n = 1 + self.rng.below(4) as usize;
                for f in 0..n {
                    let last = k == 2 && f == n - 1;
                    self.queue[side].push_back(if last { dir | Self::FIRE } else { dir });
                }
                if slow && k == 1 {
                    for _ in 0..17 + self.rng.below(4) {
                        self.queue[side].push_back(0);
                    }
                }
            }
            self.queue[side].push_back(0);
            return 0;
        }
        let mut bits = 0;
        let diff = fixed::floor(g.ball.y) - fixed::floor(g.paddles[side].y);
        if diff > 4 {
            bits |= Self::UP;
        } else if diff < -4 {
            bits |= Self::DOWN;
        }
        if !g.paddles[side].at_home() && self.rng.below(30) == 0 {
            bits |= back;
        }
        if self.rng.below(90) == 0 {
            bits |= Self::FIRE;
        }
        bits
    }
}

/// Comandi del giocatore `side` come li ha letti il 6502 (in_dir, in_flags), per il core.
fn read_input(m: &Machine, side: usize) -> PlayerInput {
    let o = (side * 4) as u16;
    let flags = m.read_u8("in_flags", o);
    PlayerInput {
        direction: m.read_u8("in_dir", o) as i8,
        fast: flags & 0x01 != 0,
        forward: flags & 0x02 != 0,
        select: flags & 0x04 != 0,
        activate: flags & 0x08 != 0,
        fire: flags & 0x10 != 0,
        special: special_of(flags),
        top_offset: (flags & 0x80 != 0).then(|| m.read_u8("in_offset", o) as i32),
    }
}

/// Mossa speciale dei bit IN_STRAIGHT ($20) e IN_RISE ($40) di in_flags.
fn special_of(flags: u8) -> Option<Special> {
    match flags & 0x60 {
        0x20 => Some(Special::Straight),
        0x40 => Some(Special::Rise),
        _ => None,
    }
}

/// Bit IN_STRAIGHT e IN_RISE di una mossa speciale.
fn special_bits(special: Option<Special>) -> u8 {
    match special {
        Some(Special::Straight) => 0x20,
        Some(Special::Rise) => 0x40,
        None => 0,
    }
}

/// Comandi di un tick nella memoria del C64.
fn write_input(m: &mut Machine, input: &Input) {
    for (i, p) in input.players.iter().enumerate() {
        let o = (i * 4) as u16;
        m.write_u8("in_dir", o, p.direction.signum() as u8);
        let flags = p.fast as u8
            | (p.forward as u8) << 1
            | (p.select as u8) << 2
            | (p.activate as u8) << 3
            | (p.fire as u8) << 4
            | special_bits(p.special)
            | if p.top_offset.is_some() { 0x80 } else { 0 };
        m.write_u8("in_flags", o, flags);
        m.write_u8("in_offset", o, p.top_offset.unwrap_or(0) as u8);
    }
}

/// Stato confrontato: (nome, valore del core, valore del C64).
fn compare(m: &Machine, g: &Match, events: u16) -> Vec<(String, i64, i64)> {
    let mut v: Vec<(String, i64, i64)> = Vec::new();
    let mut f = |name: &str, rust: i64, c64: i64| v.push((name.to_string(), rust, c64));
    let b = &g.ball;
    for (name, rust) in [
        ("ball_x", b.x),
        ("ball_y", b.y),
        ("ball_vx", b.vx),
        ("ball_vy", b.vy),
        ("ball_boost", b.boost),
        ("ball_r", b.radius),
        ("ball_dx", b.dx),
    ] {
        f(name, rust as i64, m.read_i32(name, 0) as i64);
    }
    for (i, p) in g.paddles.iter().enumerate() {
        let o = (i * 4) as u16;
        for (name, rust) in [
            ("pad_x", p.x),
            ("pad_y", p.y),
            ("pad_h", p.height),
            ("pad_speed", p.speed),
            ("pad_motion", p.motion),
            ("pad_bh", p.boost_height),
        ] {
            f(&format!("{name}[{i}]"), rust as i64, m.read_i32(name, o) as i64);
        }
        f(
            &format!("pad_dir[{i}]"),
            p.direction as i64,
            m.read_u8("pad_dir", o) as i8 as i64,
        );
        f(
            &format!("pad_fast[{i}]"),
            p.fast as i64,
            m.read_u8("pad_fast", o) as i64,
        );
        f(
            &format!("pad_level[{i}]"),
            p.boost_level as i64,
            m.read_u8("pad_level", o) as i64,
        );
        let score = m.read_u8("score", o) as i64 | (m.read_u8("score", o + 1) as i64) << 8;
        f(&format!("score[{i}]"), g.score[i] as i64, score);
    }
    let best = m.read_u8("best", 0) as i64 | (m.read_u8("best", 1) as i64) << 8;
    f("best", g.best as i64, best);
    f(
        "serve_timer",
        g.serve_timer as i64,
        m.read_i32("serve_timer", 0) as u32 as i64,
    );
    f("rng", g.rng.state() as i64, m.read_i32("rng", 0) as u32 as i64);
    f("tick", g.tick as u32 as i64, m.read_i32("tick", 0) as u32 as i64);
    let ev = m.read_u8("events", 0) as i64 | (m.read_u8("events", 1) as i64) << 8;
    f("events", events as i64, ev);
    if let Some(n) = &g.next {
        compare_next(m, n, g.params.blaster_shot_speed, &mut f);
    }
    v
}

/// Stato di NEXT: giocatori, colpi del BLASTER, capsule, effetti.
fn compare_next(m: &Machine, n: &paddws_core::Next, shot_speed: i32, f: &mut impl FnMut(&str, i64, i64)) {
    let u8_at = |name: &str, o: u16| m.read_u8(name, o) as i64;
    let u16_at = |name: &str, o: u16| m.read_u8(name, o) as i64 | (m.read_u8(name, o + 1) as i64) << 8;
    // nel 6502 il posto vuoto è B_NONE = 8 (7 è il BULLET)
    let code = |b: Option<Bonus>| b.map_or(8, |b| b as i64);
    for (i, pl) in n.players.iter().enumerate() {
        let o = (i * 4) as u16;
        for k in 0..3 {
            f(
                &format!("riserva[{i}][{k}]"),
                code(pl.reserve[k]),
                u8_at("nx_res", o + k as u16),
            );
            f(
                &format!("bonus scelti[{i}][{k}]"),
                pl.loadout[k] as i64,
                u8_at("nx_load", o + k as u16),
            );
        }
        f(&format!("selezionato[{i}]"), pl.selected as i64, u8_at("nx_sel", o));
        f(&format!("armato[{i}]"), code(pl.armed), u8_at("nx_armed", o));
        f(&format!("animazione[{i}]"), pl.super_anim as i64, u8_at("nx_anim", o));
        f(&format!("pausa[{i}]"), pl.cooldown as i64, u16_at("nx_cool", o));
        f(
            &format!("tipo[{i}]"),
            pl.kind.map_or(7, |k| k as i64),
            u8_at("nx_kind", o),
        );
        f(&format!("caricatore[{i}]"), pl.ammo as i64, u8_at("nx_ammo", o));
        f(&format!("pausa colpi[{i}]"), pl.gap as i64, u16_at("nx_gap", o));
        f(&format!("ricarica[{i}]"), pl.reload as i64, u16_at("nx_reload", o));
        f(&format!("muro[{i}]"), pl.barrier as i64, u8_at("nx_barrier", o));
        for (k, shot) in pl.shots.iter().enumerate() {
            let slot = (i * pl.shots.len() + k) as u16;
            f(
                &format!("colpo[{i}][{k}]"),
                shot.is_some() as i64,
                u8_at("shot_on", slot),
            );
            if let Some(sh) = shot {
                f(
                    &format!("colpo[{i}][{k}].x"),
                    sh.x as i64,
                    m.read_i32("shot_x", slot * 4) as i64,
                );
                f(
                    &format!("colpo[{i}][{k}].y"),
                    sh.y as i64,
                    m.read_i32("shot_y", slot * 4) as i64,
                );
                // il 6502 non tiene la velocità: +P_SHOT_SPEED a sinistra, -P_SHOT_SPEED a destra
                // (move_shots)
                f(
                    &format!("colpo[{i}][{k}].vx"),
                    sh.vx as i64,
                    if i == 0 { shot_speed } else { -shot_speed } as i64,
                );
            }
        }
    }
    for (k, c) in n.capsules.iter().enumerate() {
        let o = k as u16;
        f(&format!("capsula[{k}]"), c.is_some() as i64, u8_at("cap_on", o));
        if let Some(c) = c {
            f(
                &format!("capsula[{k}].x"),
                c.x as i64,
                m.read_i32("cap_x", o * 4) as i64,
            );
            f(
                &format!("capsula[{k}].y"),
                c.y as i64,
                m.read_i32("cap_y", o * 4) as i64,
            );
            f(
                &format!("capsula[{k}].vx"),
                c.vx as i64,
                m.read_i32("cap_vx", o * 4) as i64,
            );
            f(
                &format!("capsula[{k}].vy"),
                c.vy as i64,
                m.read_i32("cap_vy", o * 4) as i64,
            );
            f(&format!("capsula[{k}].bonus"), c.bonus as i64, u8_at("cap_bonus", o));
        }
    }
    f("prossima capsula", n.spawn_timer as i64, u16_at("nx_spawn", 0));
    f("alone di SLOW", n.slow_timer as i64, u16_at("nx_slow", 0));
    f("curva", n.curve as i64, m.read_i32("nx_curve", 0) as i64);
    let side = |s: Option<paddws_core::Side>| s.map_or(-1, |s| s as i64 * 4);
    let on_side = |on: &str, side_name: &str| {
        if m.read_u8(on, 0) != 0 {
            m.read_u8(side_name, 0) as i64
        } else {
            -1
        }
    };
    f("fantasma", side(n.ghost), on_side("nx_ghost", "nx_ghost_s"));
    f("guidata", side(n.steer), on_side("nx_steer", "nx_steer_s"));
    f(
        "verso della guida",
        n.steer_dir as i64,
        m.read_u8("nx_steer_dir", 0) as i8 as i64,
    );
    f(
        "SUPER in volo",
        n.super_flight.map_or(-1, |a| a as i64),
        if m.read_u8("nx_super", 0) != 0 {
            m.read_u8("nx_super_a", 0) as i64
        } else {
            -1
        },
    );
    f("fermo", n.freeze as i64, u16_at("nx_freeze", 0));
    // SLOW: chi l'ha usato in nx_slow_s, con il bit 7 acceso se nessuno
    let slow = u8_at("nx_slow_s", 0);
    f("SLOW di", side(n.slow), if slow & 0x80 != 0 { -1 } else { slow });
    // BULLET: nx_bside con il bit 7 acceso se nessuno l'ha; nx_btimer 0 se armato e non ancora
    // scattato, altrimenti i tick di rampa rimasti + 1
    let owner = u8_at("nx_bside", 0);
    let timer = u8_at("nx_btimer", 0);
    f("BULLET", side(n.bullet), if owner & 0x80 != 0 { -1 } else { owner });
    f("BULLET scattato", n.bullet_on as i64, (timer != 0) as i64);
    f(
        "rampa del BULLET",
        if n.bullet_on { n.bullet_timer as i64 + 1 } else { n.bullet_timer as i64 },
        timer,
    );
    f("capsule partite", n.spawned as i64 & 0xFFFF, u16_at("nx_spawned", 0));
    // mosse speciali (supers.s): barra e mossa armata (sm_arm: 1-2 STRAIGHT SHOT, 3-4 RISING
    // STRIKE, di livello 1-2), tiro in volo (sm_fl: la mossa, + 4 al livello 2), soglia
    // dell'impennata (sm_rise: indice in rise_lo e rise_hi, la parte intera)
    f("mosse speciali", n.super_moves as i64, u8_at("sm_on", 0));
    for (i, pl) in n.players.iter().enumerate() {
        let o = (i * 4) as u16;
        f(&format!("barra[{i}]"), pl.meter as i64, u8_at("sm_meter", o));
        let arm = u8_at("sm_arm", o);
        f(
            &format!("STRAIGHT SHOT armato[{i}]"),
            pl.straight as i64,
            if (1..=2).contains(&arm) { arm } else { 0 },
        );
        f(
            &format!("RISING STRIKE armato[{i}]"),
            pl.rise as i64,
            if (3..=4).contains(&arm) { arm - 2 } else { 0 },
        );
    }
    let fl = u8_at("sm_fl", 0);
    f("tiro della mossa", n.special_flight.map_or(0, |s| s as i64), fl & 3);
    f(
        "livello del tiro",
        n.special_level as i64,
        match fl {
            0 => 0,
            _ if fl & 4 != 0 => 2,
            _ => 1,
        },
    );
    let rise = m.read_u8("sm_rise", 0) as u16;
    let at = if rise == 0 {
        -1
    } else {
        (u8_at("rise_lo", rise - 1) | u8_at("rise_hi", rise - 1) << 8) << 16
    };
    f("impennata di RISING STRIKE", n.rise_break.map_or(-1, |x| x as i64), at);
}

/// Prima differenza tra core e C64, se c'è.
fn mismatch(m: &Machine, g: &Match, events: u16) -> Option<String> {
    let diffs: Vec<String> = compare(m, g, events)
        .into_iter()
        .filter(|(_, r, c)| r != c)
        .map(|(n, r, c)| format!("{n}: core {r:#x} ({r}), C64 {c:#x} ({c})"))
        .collect();
    (!diffs.is_empty()).then(|| diffs.join("\n    "))
}

/// Partite di prova: il 6502 e il core giocano con gli stessi comandi; lo stato deve coincidere
/// dopo ogni tick.
/// Livello di CHALLENGE di OMEGA (ch_level).
const CH_OMEGA: u8 = OMEGA_LEVEL as u8;

fn game(m: &mut Machine, ticks: u32) -> bool {
    m.call("math_init");
    let mut all_ok = true;
    let mut worst_all = 0;
    // OMEGA: trasformazioni per forma d'arrivo (indice di PaddleKind), quelle rimaste GUARDIAN
    // e quelle dal BLASTER con dello stato da azzerare (colpi in volo, caricatore non pieno,
    // pausa o ricarica in corso)
    let mut morph_all = ([0u32; 7], 0u32, 0u32);
    // BULLET in tutte le partite: armati, scattati, finiti alla ribattuta, rimasti armati a un punto
    let mut bullet_all = [0u32; 4];
    // mosse speciali nelle partite che le hanno
    let mut moves_all = SuperStats::default();
    for (i, s) in SCENARIOS.iter().enumerate() {
        let params = c64_params(s.difficulty);
        let mut g = match s.next {
            Some((loadouts, kinds)) => Match::new_next_paddles(params.clone(), loadouts, kinds, s.seed),
            None => Match::new(params.clone(), s.players, s.evo, s.seed),
        };
        if let Some(side) = s.morph {
            g.set_morph(side);
        }
        m.write_u8("cfg_next", 0, s.next.is_some() as u8);
        if let Some((loadouts, kinds)) = s.next {
            for side in 0..2 {
                let o = (side * 4) as u16;
                for (k, bonus) in loadouts[side].iter().enumerate() {
                    m.write_u8("cfg_loadout", o + k as u16, *bonus as u8);
                }
                m.write_u8("cfg_kinds", o, kinds[side].map_or(7, |k| k as u8));
            }
        }
        m.write_u8("cfg_players", 0, s.players);
        m.write_u8("cfg_evo", 0, s.evo as u8);
        m.write_u8("cfg_diff", 0, s.difficulty);
        m.write_i32("cfg_seed", 0, s.seed as i32);
        m.write_u8("cfg_super", 0, s.supers as u8);
        g.set_super_moves(s.supers);
        // punti arcade di CHALLENGE (ch_tick dopo ogni tick) per chi gioca a destra con la CPU a
        // sinistra, e un'altra partita sì e una no anche negli altri scenari; contro OMEGA chi
        // gioca è dall'altra parte della racchetta che cambia forma
        let human = if let Some(side) = s.morph {
            side.opponent()
        } else if matches!(s.drive, Drive::CpuLeft) || i % 2 == 1 {
            Side::Right
        } else {
            Side::Left
        };
        m.write_u8("cg_active", 0, 1);
        m.write_u8("ch_side", 0, human as u8 * 4);
        // OMEGA: next_init (da match_new) mette nx_morph dal livello di CHALLENGE e da ch_side
        m.write_u8("ch_level", 0, if s.morph.is_some() { CH_OMEGA } else { 0 });
        m.call("match_new");
        if let Some(d) = mismatch(m, &g, 0) {
            println!("FAIL {}: dopo match_new\n    {d}", s.name);
            all_ok = false;
            continue;
        }
        let mut script = Script::new(s.seed);
        let mut cpus = [Side::Left, Side::Right].map(|side| Cpu::new(&params, s.levels[side as usize], side, s.seed));
        // le CPU del 6502, che devono dare gli stessi comandi di quelle del core
        let cpu_sides: &[usize] = match s.drive {
            Drive::Cpu => &[0, 1],
            Drive::CpuLeft => &[0],
            Drive::Joy => &[1],
            _ => &[],
        };
        // joystick a riposo, poi quelli dei giocatori simulati (Joy, Joy2)
        let mut joys = JoySim::new(s.seed);
        m.write_u8("ctl_paddle", 0, 0);
        m.cpu.write(0xDC00, 0xFF);
        m.cpu.write(0xDC01, 0xFF);
        m.cpu.joy_port1 = 0xFF;
        m.cpu.joy_port2 = 0xFF;
        let mut moves = SuperStats::default();
        for &side in cpu_sides {
            m.cpu.a = s.levels[side];
            m.cpu.x = (side * 4) as u8;
            m.call("cpu_init");
        }
        let mut arcade = Score::new(human);
        for (name, n) in [("ch_score", 4), ("ch_rally", 2), ("ch_before", 2)] {
            for k in 0..n {
                m.write_u8(name, k, 0);
            }
        }
        let (mut worst, mut total, mut points, mut hits) = (0u64, 0u64, 0u32, 0u32);
        // BULLET come bullet_all, e tick di bullet time (le partite NEXT devono passarci)
        let (mut bullets, mut bullet_ticks) = ([0u32; 4], 0u32);
        let mut failed = false;
        for t in 1..=ticks {
            // con lo script, ogni tanto un BULLET nella riserva vuota, uguale nel core e nel 6502:
            // più BULLET attivati in momenti qualsiasi, anche armati quando poi c'è un punto
            if matches!(s.drive, Drive::ScriptNext | Drive::EncoderNext)
                && t % 400 == 0
                && let Some(n) = g.next.as_mut()
            {
                let side = (t / 400 % 2) as usize;
                let pl = &mut n.players[side];
                if pl.reserve.iter().all(Option::is_none) && pl.selected == 0 {
                    pl.reserve[0] = Some(Bonus::Bullet);
                    m.write_u8("nx_res", side as u16 * 4, Bonus::Bullet as u8);
                }
            }
            let input = match s.drive {
                Drive::Script => script.next(&g, false),
                Drive::Encoder => script.next(&g, true),
                Drive::Cpu => Input {
                    players: [cpus[0].input(&g), cpus[1].input(&g)],
                },
                Drive::ScriptNext => script.next_next(&g, false),
                Drive::EncoderNext => script.next_next(&g, true),
                Drive::CpuLeft => {
                    let mut input = script.next_next(&g, false);
                    input.players[0] = cpus[0].input(&g);
                    input
                }
                Drive::Joy | Drive::Joy2 => {
                    // il 6502 legge i joystick (read_input, build_input con next_keys e il gesto);
                    // il core riceve i comandi così come li ha letti
                    let left = joys.frame(&g, 0);
                    let right = if matches!(s.drive, Drive::Joy2) {
                        joys.frame(&g, 1)
                    } else {
                        0
                    };
                    m.cpu.joy_port2 = !left;
                    m.cpu.joy_port1 = !right;
                    m.call("read_input");
                    m.call("build_input");
                    let mut input = Input {
                        players: [read_input(m, 0), read_input(m, 1)],
                    };
                    if matches!(s.drive, Drive::Joy) {
                        input.players[1] = cpus[1].input(&g);
                    }
                    moves.gesture(&joys, &input, &g);
                    input
                }
            };
            let input = Input {
                players: input.players.map(|p| PlayerInput {
                    direction: p.direction.signum(),
                    ..p
                }),
            };
            let mut cycles = 0;
            if !cpu_sides.is_empty() {
                // il giocatore simulato (se c'è), poi le CPU del 6502 al loro posto
                write_input(m, &input);
                for &side in cpu_sides {
                    m.cpu.x = (side * 4) as u8;
                    cycles += m.call("cpu_input");
                }
                let o = |i: usize| (i * 4) as u16;
                let got: Vec<(i8, u8)> = cpu_sides
                    .iter()
                    .map(|&i| (m.read_u8("in_dir", o(i)) as i8, m.read_u8("in_flags", o(i))))
                    .collect();
                let want: Vec<(i8, u8)> = cpu_sides
                    .iter()
                    .map(|&i| &input.players[i])
                    .map(|p| {
                        let flags = p.fast as u8
                            | (p.forward as u8) << 1
                            | (p.select as u8) << 2
                            | (p.activate as u8) << 3
                            | (p.fire as u8) << 4
                            | special_bits(p.special);
                        (p.direction, flags)
                    })
                    .collect();
                if got != want {
                    println!(
                        "FAIL {}: tick {t}, comandi delle CPU: core {want:?}, C64 {got:?}",
                        s.name
                    );
                    failed = true;
                    break;
                }
            } else {
                write_input(m, &input);
            }
            cycles += m.call("match_step");
            cycles += m.call("ch_tick");
            worst = worst.max(cycles);
            total += cycles;
            let before = g.score;
            let bullet_before = g.next.as_ref().map_or((None, false), |n| (n.bullet, n.bullet_on));
            let moves_before = g.next.clone();
            let morph_before = s.morph.map(|side| {
                let pl = &g.next.as_ref().expect("OMEGA senza NEXT").players[side as usize];
                let busy = pl.shots.iter().any(Option::is_some)
                    || pl.ammo != params.blaster_shots
                    || pl.gap != 0
                    || pl.reload != 0;
                (g.paddle_kind(side), busy && pl.kind == Some(PaddleKind::Blaster), g.score)
            });
            let events = g.step(&input);
            if let (Some(side), Some((kind, shots, score))) = (s.morph, morph_before)
                && g.score[side.opponent() as usize] != score[side.opponent() as usize]
            {
                let now = g.paddle_kind(side).expect("OMEGA senza tipo");
                morph_all.0[now as usize] += 1;
                morph_all.1 += (kind == Some(PaddleKind::Guardian)) as u32;
                morph_all.2 += shots as u32;
            }
            moves.tick(moves_before.as_ref(), &g, events, cpu_sides);
            arcade.on_tick(&g, before, events);
            let ch_score = m.read_i32("ch_score", 0) as u32;
            if ch_score != arcade.total {
                println!(
                    "FAIL {}: tick {t}, punti CHALLENGE: core {}, C64 {ch_score}",
                    s.name, arcade.total
                );
                failed = true;
                break;
            }
            points += events.has(paddws_core::Event::Score) as u32;
            if let Some(n) = &g.next {
                let scored = events.has(paddws_core::Event::Score);
                bullet_ticks += n.bullet_on as u32;
                bullets[0] += (bullet_before.0.is_none() && n.bullet.is_some()) as u32;
                bullets[1] += (!bullet_before.1 && n.bullet_on) as u32;
                bullets[2] += (bullet_before.1 && n.bullet.is_none() && !scored) as u32;
                bullets[3] += (scored && n.bullet.is_some() && !n.bullet_on) as u32;
            }
            hits += (events.has(paddws_core::Event::Hit) || events.has(paddws_core::Event::Boost)) as u32;
            if let Some(d) = mismatch(m, &g, events.bits()) {
                println!("FAIL {}: tick {t}\n    {d}", s.name);
                // comandi del tick come li ha letti il 6502
                for i in 0..2u16 {
                    println!(
                        "    comandi[{i}]: core {:?}, C64 dir {} flags {:#04x} offset {}",
                        input.players[i as usize],
                        m.read_u8("in_dir", i * 4) as i8,
                        m.read_u8("in_flags", i * 4),
                        m.read_u8("in_offset", i * 4)
                    );
                }
                failed = true;
                break;
            }
        }
        if failed {
            all_ok = false;
            continue;
        }
        worst_all = worst_all.max(worst);
        for (a, b) in bullet_all.iter_mut().zip(bullets) {
            *a += b;
        }
        let bullet = if s.next.is_some() {
            let [armed, on, back, kept] = bullets;
            format!(", BULLET {armed} armati, {on} scattati ({bullet_ticks} tick), {back} ribattuti, {kept} armati a un punto")
        } else {
            String::new()
        };
        println!(
            "PASS {:<12} {ticks} tick, {hits} colpi, {points} punti{bullet}: cicli per tick max {worst}, media {}",
            s.name,
            total / ticks as u64
        );
        if s.supers {
            println!("     mosse: {}", moves.line());
            moves_all.add(&moves);
        }
    }
    if all_ok && bullet_all.contains(&0) {
        let [armed, on, back, kept] = bullet_all;
        println!(
            "FAIL: il BULLET non passa per tutti i casi: {armed} armati, {on} scattati, {back} finiti alla ribattuta, {kept} rimasti armati a un punto"
        );
        all_ok = false;
    }
    let (forms, stay, shots) = morph_all;
    let line = format!(
        "{} trasformazioni (ARCADE..GUARDIAN {forms:?}), {stay} rimaste GUARDIAN, {shots} da un BLASTER che aveva sparato",
        forms.iter().sum::<u32>()
    );
    // tutte le forme della scala dopo ARCADE, e il GUARDIAN che resta
    let ladder_forms = RUNGS[1..].iter().all(|r| forms[r.kind as usize] > 0);
    if all_ok && (!ladder_forms || stay == 0 || shots == 0) {
        println!("FAIL: OMEGA non passa per tutti i casi: {line}");
        all_ok = false;
    } else {
        println!("     OMEGA: {line}");
    }
    if all_ok && let Some(missing) = moves_all.missing() {
        println!(
            "FAIL: le mosse speciali non passano per tutti i casi ({missing}): {}",
            moves_all.line()
        );
        all_ok = false;
    }
    match dash(m) {
        Ok(s) => println!("{s}"),
        Err(e) => {
            println!("FAIL scatto: {e}");
            all_ok = false;
        }
    }
    if all_ok {
        println!("Tutte le partite coincidono con il core Rust (max {worst_all} cicli per tick)");
    }
    all_ok
}

/// Mosse speciali nelle partite di prova: quante armate (per mossa e livello), da chi (CPU, gesto
/// del giocatore sinistro e del destro), colpi con la mossa, impennate di RISING STRIKE, mosse
/// perse al punto, fuochi che chiudono un gesto (e di questi quanti attivano un bonus perché la
/// mossa non può partire).
#[derive(Default)]
struct SuperStats {
    /// [STRAIGHT SHOT livello 1, livello 2, RISING STRIKE livello 1, livello 2]
    armed: [u32; 4],
    by_cpu: u32,
    by_gesture: [u32; 2],
    hits: u32,
    breaks: u32,
    lost: u32,
    gestures: u32,
    fallback: u32,
}

impl SuperStats {
    /// Il fuoco che chiude un gesto in questo tick: la mossa, o il bonus se non può partire.
    fn gesture(&mut self, joys: &JoySim, input: &Input, g: &Match) {
        for &side in &joys.fired {
            self.gestures += 1;
            let p = &input.players[side];
            let ready = g
                .next
                .as_ref()
                .is_some_and(|n| n.players[side].special_ready(&g.params))
                && !g.serving();
            if p.special.is_none() && p.activate && !ready {
                self.fallback += 1;
            }
        }
    }

    fn tick(
        &mut self,
        before: Option<&paddws_core::Next>,
        g: &Match,
        events: paddws_core::Events,
        cpu_sides: &[usize],
    ) {
        let (Some(b), Some(n)) = (before, g.next.as_ref()) else {
            return;
        };
        use paddws_core::Event;
        for side in 0..2 {
            let (was, now) = (&b.players[side], &n.players[side]);
            let k = if now.straight > was.straight {
                Some(now.straight as usize - 1)
            } else if now.rise > was.rise {
                Some(now.rise as usize + 1)
            } else {
                None
            };
            if let Some(k) = k {
                self.armed[k] += 1;
                if cpu_sides.contains(&side) {
                    self.by_cpu += 1;
                } else {
                    self.by_gesture[side] += 1;
                }
            }
            if events.has(Event::Score) && !was.special_idle() && now.special_idle() {
                self.lost += 1;
            }
        }
        self.hits += events.has(Event::SpecialHit) as u32;
        let touched = [Event::Score, Event::Hit, Event::Boost, Event::Super, Event::Barrier]
            .iter()
            .any(|&e| events.has(e));
        self.breaks += (b.rise_break.is_some() && n.rise_break.is_none() && !touched) as u32;
    }

    fn add(&mut self, o: &Self) {
        for (a, b) in self.armed.iter_mut().zip(o.armed) {
            *a += b;
        }
        self.by_cpu += o.by_cpu;
        self.by_gesture[0] += o.by_gesture[0];
        self.by_gesture[1] += o.by_gesture[1];
        self.hits += o.hits;
        self.breaks += o.breaks;
        self.lost += o.lost;
        self.gestures += o.gestures;
        self.fallback += o.fallback;
    }

    fn line(&self) -> String {
        let [s1, s2, r1, r2] = self.armed;
        format!(
            "STRAIGHT SHOT {s1} + {s2} MAX, RISING STRIKE {r1} + {r2} MAX (CPU {}, gesti {} a sinistra e {} a destra), {} colpi, {} impennate, {} perse al punto; {} gesti con il fuoco, {} diventati bonus",
            self.by_cpu,
            self.by_gesture[0],
            self.by_gesture[1],
            self.hits,
            self.breaks,
            self.lost,
            self.gestures,
            self.fallback
        )
    }

    /// Il primo caso che manca, se ne manca uno.
    fn missing(&self) -> Option<&'static str> {
        let cases = [
            (self.armed[0], "STRAIGHT SHOT"),
            (self.armed[1], "STRAIGHT SHOT MAX"),
            (self.armed[2], "RISING STRIKE"),
            (self.armed[3], "RISING STRIKE MAX"),
            (self.by_cpu, "mosse della CPU"),
            (self.by_gesture[0], "gesto a sinistra"),
            (self.by_gesture[1], "gesto a destra"),
            (self.hits, "colpo con la mossa"),
            (self.breaks, "impennata"),
            (self.lost, "mossa persa al punto"),
            (self.fallback, "fuoco del gesto che attiva il bonus"),
        ];
        cases.into_iter().find(|&(n, _)| n == 0).map(|(_, what)| what)
    }
}

/// Scatto in EVO (`Match::ball_in_forward_area` e `forward_boost`): palle a caso intorno alla
/// fascia tra la faccia di casa e quella avanzata, in arrivo, con ogni inclinazione (anche vy = 0)
/// e velocità fino a quelle della battuta; un tick con lo scatto sul 6502 e sul core, poi lo stato
/// confrontato. Restituisce quante palle lo scatto ha preso, e i cicli del tick più pesante.
fn dash(m: &mut Machine) -> Result<String, String> {
    let params = c64_params(1);
    let mut seed = 0x1234_5678u32;
    let mut next = move || {
        seed ^= seed << 13;
        seed ^= seed >> 17;
        seed ^= seed << 5;
        seed
    };
    let (mut caught, mut worst) = (0u32, 0u64);
    const TRIALS: u32 = 4000;
    for trial in 0..TRIALS {
        let mut g = Match::new(params.clone(), 2, true, 7);
        m.write_u8("cfg_next", 0, 0);
        m.write_u8("cfg_players", 0, 2);
        m.write_u8("cfg_evo", 0, 1);
        m.write_u8("cfg_diff", 0, 1);
        m.write_i32("cfg_seed", 0, 7);
        m.call("match_new");
        let side = (trial & 1) as usize;
        let pad = g.paddles[side].clone();
        let px = |v: f64| fixed::from_f64(v);
        // vx da circa 1 px per tick (la battuta più lenta) a 6, verso la racchetta; vy anche 0
        let speed = 0.9 + (next() % 5000) as f64 / 1000.0;
        let vy = if next() % 8 == 0 { 0.0 } else { ((next() % 2001) as f64 - 1000.0) / 200.0 };
        let face = pad.home_x + if side == 0 { pad.width / 2 } else { -pad.width / 2 };
        let travel = (pad.fwd_x - pad.home_x).abs();
        let into = (next() % 1000) as f64 / 1000.0 * (fixed::to_f32(travel) as f64 + 8.0) - 2.0;
        let dy = ((next() % 2001) as f64 - 1000.0) / 1000.0 * 70.0;
        g.serve_timer = 0;
        g.ball.vx = if side == 0 { -px(speed) } else { px(speed) };
        g.ball.vy = px(vy);
        g.ball.x = if side == 0 { face + g.ball.radius + px(into) } else { face - g.ball.radius - px(into) };
        g.ball.y = pad.y + px(dy);
        for (name, v) in [("ball_x", g.ball.x), ("ball_y", g.ball.y), ("ball_vx", g.ball.vx), ("ball_vy", g.ball.vy)] {
            m.write_i32(name, 0, v);
        }
        m.write_i32("serve_timer", 0, 0);
        if let Some(d) = mismatch(m, &g, 0) {
            return Err(format!("prova {trial}, prima dello scatto:
    {d}"));
        }
        let mut input = Input::default();
        input.players[side].forward = true;
        write_input(m, &input);
        worst = worst.max(m.call("match_step"));
        let events = g.step(&input);
        caught += (events.has(paddws_core::Event::Boost) || events.has(paddws_core::Event::Hit)) as u32;
        if let Some(d) = mismatch(m, &g, events.bits()) {
            return Err(format!("prova {trial} (lato {side}, vx {speed:.2}, vy {vy:.2}, dentro {into:.1}, dy {dy:.1}):
    {d}"));
        }
    }
    if caught == 0 || caught == TRIALS {
        return Err(format!("{caught} prese su {TRIALS}: le prove non coprono i due esiti"));
    }
    Ok(format!("PASS scatto       {TRIALS} palle a caso nella fascia, {caught} prese: tick max {worst} cicli"))
}

// ------------------------------------------------------------------------------------ finale

/// Finale di CHALLENGE (c64/src/ending.s): la scena, la canzone del player del C64, la canzone
/// delle iniziali dopo, le parti dei fuochi e dei titoli.
const ST_ENDING: u8 = 16;
const ST_WARNING: u8 = 17;
const ST_JUKEBOX: u8 = 18;
/// livello in classifica con OMEGA battuto ("ALL+")
const SCORE_LEVEL_OMEGA: u8 = paddws_core::challenge::SCORE_LEVEL_OMEGA;
const ST_OVER: u8 = 8;
const ST_CONT: u8 = 12;
const SID_SONG_ENDING: u8 = 8;
/// canzone del titolo e quella dell'easter egg delle iniziali (il finale letto dalla cartuccia)
const SID_SONG_EGG: u8 = 9;
const SID_SONG_CHAMPION: u8 = 6;
const EP_CHAMP: u8 = 4;
const EP_CREDITS: u8 = 5;
/// Premi dell'ultimo livello vinto 5 a 0: (CH_WIN + CH_PERFECT) * 7.
const ENDING_BONUS: u32 = (1000 + 2000) * 7;
/// Cicli dall'interrupt della riga 250 a quando il raster arriva alla prima riga di caratteri:
/// i colori dei titoli scritti allo scambio degli schermi devono arrivare prima (poi le righe dopo
/// non si raggiungono più: 8 righe del raster per riga di caratteri contro circa 300 cicli per i
/// colori di una riga).
fn colors_before() -> u64 {
    if ntsc() { (263 - 250 + 51) * 65 } else { (312 - 250 + 51) * 63 }
}

/// Un frame intero: `frame` con il raster, poi gli NMI fino alla fine del frame. Restituisce i
/// cicli di `frame` (NMI compresi).
fn full_frame(m: &mut Machine) -> Result<u64, String> {
    let start = m.cpu.cycles;
    m.cpu.frame_start = Some(start);
    m.write_u8("frame_flag", 0, 0); // play_main lo azzera prima del frame
    let heavy = heavy_limit().is_some();
    if heavy {
        m.cpu.inclusive = Some(Box::default());
    }
    let addr = m.addr("frame");
    let c = m.cpu.call(addr, 1_000_000);
    m.cpu.frame_start = None;
    let c = c?;
    if heavy && c > FRAME_BUDGET() {
        println!("  frame oltre il budget: stato {}, {c} cicli", m.read_u8("state", 0));
        if let Some(parts) = frame_parts(m) {
            println!("    {parts}");
        }
    }
    if heavy {
        m.cpu.inclusive = None;
    }
    m.cpu.idle(start + frame_cycles())?;
    Ok(c)
}

/// Joystick e tastiera a riposo, vettore dell'NMI del programma.
fn quiet_inputs(m: &mut Machine) {
    let nmi = m.addr("nmi_handler");
    m.cpu.write(0xFFFA, nmi as u8);
    m.cpu.write(0xFFFB, (nmi >> 8) as u8);
    m.cpu.joy_port1 = 0xFF;
    m.cpu.joy_port2 = 0xFF;
    m.cpu.write(0xDC00, 0xFF);
    m.cpu.write(0xDC01, 0xFF);
    m.call("read_input");
    m.call("read_input");
}

/// Quante volte YOU WIN! (gen/you_win.bin) compare intera nelle scritture in $D418.
fn you_win_count(got: &[u8]) -> Result<usize, String> {
    voice_count(got, "you_win.bin")
}

/// Quante volte la voce `file` (in c64/gen) compare intera nelle scritture in $D418.
fn voice_count(got: &[u8], file: &str) -> Result<usize, String> {
    let (want, _) = voice_writes(file)?;
    Ok(got.windows(want.len()).filter(|w| *w == &want[..]).count())
}

/// Una scala all'ultimo livello appena vinta contro la CPU, 5 a 0, con `score` punti arcade e il
/// player delle voci del file del primo livello in memoria, come dopo una scala vera (la copia
/// dalla cartuccia e i primi tre frame della presentazione, che mettono gli NMI del player a
/// VOICE_GO): ch_after deve portare al finale.
fn ending_start(m: &mut Machine, score: u32) -> Result<(), String> {
    quiet_inputs(m);
    m.cpu.a = m.read_u8("rung_kind", 0);
    m.call("ef_voice");
    for _ in 0..3 {
        m.cpu.call(VOICE_BASE, 100_000)?;
    }
    m.cpu.call(VOICE_BASE + 3, 100_000)?;
    m.cpu.a = 0;
    m.call("sid_song");
    for (name, v) in [("cg_active", 1u8), ("ch_level", 6), ("ch_side", 0), ("ch_best_lv", 1), ("state", ST_OVER)] {
        m.write_u8(name, 0, v);
    }
    for (o, v) in [(0u16, 5u8), (1, 0), (4, 0), (5, 0)] {
        m.write_u8("score", o, v);
    }
    m.write_i32("ch_score", 0, score as i32);
    m.write_i32("ch_best", 0, 0);
    m.call("ch_after");
    if m.read_u8("state", 0) != ST_ENDING {
        return Err(format!("dopo l'ultimo livello la scena {} invece del finale", m.read_u8("state", 0)));
    }
    Ok(())
}

/// Il testo `text` (font del programma, FONT_MAP) è nello schermo `screen`, riga `row`, dalla
/// colonna `col`.
fn text_at(m: &Machine, screen: u16, row: u16, col: u16, text: &str) -> bool {
    text.bytes()
        .enumerate()
        .all(|(i, c)| m.cpu.mem[(screen + row * 40 + col + i as u16) as usize] == m.image_u8("font_map", c as u16 - 32))
}

/// La scritta grande (scala 2, big_at di ending.s) `text` è nel primo schermo dalla colonna `col`,
/// righe `row` e `row` + 1: i caratteri dalle tabelle del finale.
fn big_text_at(m: &Machine, text: &str, col: u16, row: u16) -> bool {
    text.bytes().enumerate().all(|(i, c)| {
        let g = m.read_u8("big_idx", c as u16 - 32) as u16;
        let at = 0xC000 + row as usize * 40 + col as usize + 2 * i;
        let cells = [at, at + 1, at + 40, at + 41];
        ["big_tl", "big_tr", "big_bl", "big_br"]
            .iter()
            .zip(cells)
            .all(|(t, a)| m.cpu.mem[a] == m.read_u8(t, g))
    })
}

/// Esito del finale giocato da capo.
#[derive(Default)]
struct EndingRun {
    frames: u32,
    worst: u64,
    worst_part: u8,
    /// frame per parte (0-7) e il più pesante di ognuna (con il frame dall'inizio della parte)
    parts: [u32; 8],
    part_worst: [(u64, u32); 8],
    /// YOU WIN! intere in $D418
    you_win: usize,
    /// frame con i fuochi a schermo, con i razzi, tipi scoppiati (bit), scambi dei titoli, colori
    /// dei titoli scritti tardi, celle e sprite di un colore che non c'è
    fireworks: u32,
    rockets: u32,
    kinds: u8,
    flips: u32,
    late: u32,
    bad_colors: u32,
    /// controlli di contenuto falliti
    errors: Vec<String>,
    /// colori a schermo alla fine di ogni frame (`screen_colors`)
    colors: Vec<Vec<u8>>,
}

/// Il finale da capo (ending_start), frame per frame con `frame`, finché finisce; con `fire_at`
/// il fuoco di chi gioca a quel frame (dall'inizio), che lo salta. Controlla a ogni frame i colori
/// a schermo (solo bianco, giallo e rosso, scambiati con l'easter egg: egg_yel ed egg_red) e,
/// senza salto, le parti: scritte, racchette e timbri
/// della sfilata, numeri del punteggio, fuochi, titoli, THE END. Alla fine le iniziali (o la
/// classifica) con tutto com'era: set di caratteri del programma, registri, sprite, NMI, la
/// canzone CHAMPION, le tabelle dei quadrati da rifare.
fn ending_run(m: &mut Machine, score: u32, fire_at: Option<u32>) -> Result<EndingRun, String> {
    ending_start(m, score)?;
    let (yel, red) = (COL_YELLOW, COL_RED);
    // bianco, giallo, rosso, ciano, viola, verde, blu e il cielo multicolore dei fuochi
    let allowed = [
        1,
        COL_RED,
        COL_YELLOW,
        8 | red,
        8 | 3, // COL_CYAN
        8 | 4, // COL_PURPLE
        8 | 5, // COL_GREEN
        8 | 6, // COL_BLUE
        8 | yel,
    ];
    let nmi = m.addr("nmi_handler");
    let charset = program_charset(m);
    // il set del finale: il font e le sue lettere 2x dalla ROM (gen/ending.inc)
    let einc = std::fs::read_to_string(c64_dir().join("gen/ending.inc")).unwrap_or_default();
    let end_src: Vec<u8> = einc
        .lines()
        .find_map(|l| l.strip_prefix(".define END_BIG_SRC "))
        .map(|l| l.split(',').filter_map(|v| v.trim().parse().ok()).collect())
        .unwrap_or_default();
    let end_glyphs = rom_glyphs(m, &end_src, inc_const(&einc, "END_BIG_BASE").unwrap_or(0));
    let mut r = EndingRun::default();
    let mut d418 = Vec::new();
    m.cpu.watch = Some((0xD418, 0xDBE7));
    m.cpu.stamp = true;
    let mut f = 0u32;
    while m.read_u8("state", 0) == ST_ENDING {
        if f > 4000 {
            return Err("il finale non finisce in 4000 frame".into());
        }
        // (il fuoco per due frame: sull'NTSC un frame su sei di scena è saltato, comandi compresi)
        m.cpu.joy_port2 = if fire_at.is_some_and(|a| f == a || f == a + 1) { !0x10 } else { 0xFF };
        m.cpu.writes.clear();
        m.cpu.write_cycles.clear();
        let part = m.read_u8("e_part", 0);
        let rows_before = m.read_u8("e_R", 0);
        let start = m.cpu.cycles;
        let c = full_frame(m).map_err(|e| format!("frame {f}, parte {part}, t {}: {e}", m.read_u8("e_t", 0)))?;
        f += 1;
        r.frames += 1;
        let pw = &mut r.part_worst[part.min(7) as usize];
        if c > pw.0 {
            *pw = (c, r.parts[part.min(7) as usize]);
        }
        r.parts[part.min(7) as usize] += 1;
        if c > r.worst {
            r.worst = c;
            r.worst_part = part;
        }
        d418.extend(m.cpu.writes.iter().filter(|w| w.0 == 0xD418).map(|w| w.1));
        r.colors.push(screen_colors(m));
        // titoli: allo scambio degli schermi i colori prima che il raster arrivi al testo
        if part == EP_CREDITS && m.read_u8("e_R", 0) != rows_before {
            r.flips += 1;
            let late = m
                .cpu
                .writes
                .iter()
                .zip(&m.cpu.write_cycles)
                .any(|(w, &cy)| {
                    // la riga dei colori scritta prima che il raster ci arrivi (8 righe del raster
                    // per riga di testo, dalla prima, colors_before)
                    let row = (w.0.wrapping_sub(0xD800) / 40) as u64;
                    (0xD800..0xDBE8).contains(&w.0) && cy - start > colors_before() + row * 8 * paddws_c64::raster_cycles()
                });
            r.late += late as u32;
        }
        let now = m.read_u8("e_part", 0);
        // (a schermo spento, MODE_OFF nel frame dopo, non si vede niente)
        if m.read_u8("state", 0) != ST_ENDING || now == 0 || now == 7 || m.read_u8("sh_mode", 0) == 2 {
            continue;
        }
        // colori: celle non vuote dello schermo che si vede, sprite accesi, bordo e sfondo (la
        // sfilata è in bitmap, con i ritratti: lì solo sprite, bordo e sfondo)
        let screen: u16 = if m.cpu.mem[0xD018] & 0xF0 == 0x10 { 0xC400 } else { 0xC000 };
        let bitmap = m.cpu.mem[0xD011] & 0x20 != 0;
        for i in (0..1000u16).filter(|_| !bitmap) {
            let cell = m.cpu.mem[(screen + i) as usize];
            if cell != 0 && !allowed.contains(&(m.cpu.mem[0xD800 + i as usize] & 15)) {
                r.bad_colors += 1;
            }
        }
        let on = m.cpu.mem[0xD015];
        for s in 0..8 {
            if on >> s & 1 != 0 {
                let col = m.cpu.mem[0xD027 + s] & 15;
                // razzi (0-2): bianco; astronave vincitrice (3): colore del tipo, ciano o bianco
                if s < 3 && col != 1 {
                    r.bad_colors += 1;
                }
            }
        }
        let d025_ok = m.cpu.mem[0xD025] & 15 == if now == 6 { COL_GRAY } else { yel };
        if on & m.cpu.mem[0xD01C] != 0 && (!d025_ok || m.cpu.mem[0xD026] & 15 != 1) {
            r.bad_colors += 1;
        }
        if m.cpu.mem[0xD016] & 0x10 != 0 && (m.cpu.mem[0xD022] & 15 != 1 || m.cpu.mem[0xD023] & 15 != yel) {
            r.bad_colors += 1;
        }
        if m.cpu.mem[0xD020] & 15 != 0 || m.cpu.mem[0xD021] & 15 != 0 {
            r.bad_colors += 1;
        }
        if m.read_u8("e_new", 0) == 0 && m.read_u8("sid_song_n", 0) != SID_SONG_ENDING {
            r.errors.push(format!("parte {now}: canzone {} invece del finale", m.read_u8("sid_song_n", 0)));
        }
        // fuochi: punti nel cielo, razzi, tipi scoppiati
        if now == EP_CHAMP {
            let sky = (0..18 * 40u16).any(|i| (0xC0..0xF0).contains(&m.cpu.mem[(screen + i) as usize]));
            r.fireworks += sky as u32;
            r.rockets += (on & 7 != 0) as u32;
            for s in 0..4 {
                if m.read_u8("sl_on", s) != 0 {
                    r.kinds |= 1 << m.read_u8("sl_kind", s);
                }
            }
        }
        if fire_at.is_some() {
            continue;
        }
        let t = m.read_u8("e_t", 0) as u16 | (m.read_u8("e_t", 1) as u16) << 8;
        let filled =
            |m: &Machine, row: u16| (0..40).filter(|&c| m.cpu.mem[(screen + row * 40 + c) as usize] != 0).count();
        let mut errors = Vec::new();
        let mut check = |ok: bool, what: &str| {
            if !ok {
                errors.push(what.to_string());
            }
        };
        match (now, t) {
            (1, 10) => {
                check(text_at(m, 0xC000, 10, 12, "CONGRATULATIONS!"), "CONGRATULATIONS! non a schermo");
                check(!end_src.is_empty() && check_glyphs(m, &end_glyphs, "finale").is_ok(), "set del finale senza i glifi della ROM");
            }
            (1, 60) => check(big_text_at(m, "YOU WIN!", 12, 15), "YOU WIN! non a schermo"),
            (2, 400) => {
                // sfilata con i ritratti (parade.s): bitmap a $C000 (sotto l'I/O dalla riga 13), colori a
                // $F000; otto posti 8x9 celle (colonne 1 + 10k, righe 3 e 14), il nome sotto, il
                // timbro rosso (righe 6-7 del ritratto) sui sette avversari, OMEGA in sagoma senza
                let bm = |i: usize| if i >= 0x1000 { m.cpu.under_io[i - 0x1000] } else { m.cpu.mem[0xC000 + i] };
                let cell = |row: usize, col: usize| (0..8).any(|y| bm((row * 40 + col) * 8 + y) != 0);
                check(m.cpu.mem[0xD011] & 0x20 != 0 && m.cpu.mem[0xD018] == 0xC0, "sfilata: non in bitmap a $C000");
                check((13..27).filter(|&c| cell(1, c)).count() >= 12, "sfilata: YOUR OPPONENTS non a schermo");
                for k in 0..8usize {
                    let (row, col) = (if k < 4 { 3 } else { 14 }, 1 + 10 * (k % 4));
                    let shown = (0..9).map(|r| (0..8).filter(|&c| cell(row + r, col + c)).count()).sum::<usize>();
                    check(shown > 20, "sfilata: manca un ritratto");
                    check((col..col + 8).any(|c| cell(row + 9, c)), "sfilata: manca un nome");
                    let red = (row + 6..row + 8).all(|r| (col..col + 8).all(|c| m.cpu.mem[0xF000 + r * 40 + c] >> 4 == COL_RED));
                    check(red == (k < 7), "sfilata: timbro rosso sbagliato");
                }
            }
            (3, 440) => {
                check(
                    text_at(m, 0xC000, 8, 11, "SCORE") && text_at(m, 0xC000, 8, 24, &format!("{score:07}")),
                    "punteggio: SCORE sbagliato",
                );
                check(
                    text_at(m, 0xC000, 11, 6, &format!("CHAMPION BONUS   +{ENDING_BONUS:06}")),
                    "punteggio: CHAMPION BONUS sbagliato",
                );
                check(text_at(m, 0xC000, 4, 14, "FINAL SCORE"), "punteggio: FINAL SCORE non a schermo");
                let total = format!("{:07}", score + ENDING_BONUS);
                check(
                    text_at(m, 0xC000, 15, 11, "TOTAL") && text_at(m, 0xC000, 15, 24, &total),
                    "punteggio: TOTAL non a schermo",
                );
            }
            (4, 100) => check(
                text_at(m, 0xC000, 21, 12, "PADD WS CHAMPION") && text_at(m, 0xC000, 19, 14, "YOU ARE THE"),
                "YOU ARE THE PADD WS CHAMPION non a schermo",
            ),
            (6, 20) => check(text_at(m, 0xC000, 17, 16, "THE END"), "THE END non a schermo"),
            _ => {}
        }
        if now == EP_CREDITS && m.read_u8("e_hold", 0) == 50 {
            check(
                filled(m, 12) >= 9 && m.cpu.mem[0xD800 + 12 * 40 + 20] & 15 == yel,
                "titoli: alla fine FOR PLAYING non è al centro",
            );
        }
        r.errors.extend(errors);
    }
    m.cpu.joy_port2 = 0xFF;
    m.cpu.watch = None;
    m.cpu.stamp = false;
    r.you_win = you_win_count(&d418)?;
    // uscita pulita
    let state = m.read_u8("state", 0);
    let mut wrong = Vec::new();
    if state != ST_INITIALS && state != ST_SCORES {
        wrong.push(format!("scena {state} dopo il finale"));
    }
    if m.cpu.mem[0xC800..0xD000] != charset[..] {
        wrong.push("set di caratteri del programma non rimesso (con i glifi della ROM)".into());
    }
    for (what, got, want) in [
        ("$D016", m.cpu.mem[0xD016], 0xC8),
        // (lo split del raster della sfilata spento: parade.s, irq_normal di ending.s)
        ("vettore dell'interrupt, byte basso", m.cpu.mem[0xFFFE], m.addr("irq_handler") as u8),
        ("vettore dell'interrupt, byte alto", m.cpu.mem[0xFFFF], (m.addr("irq_handler") >> 8) as u8),
        ("riga dell'interrupt", m.cpu.mem[0xD012], 250),
        ("$D025", m.cpu.mem[0xD025] & 15, COL_GRAY),
        ("$D01B", m.cpu.mem[0xD01B], 0),
        ("sprite accesi", m.read_u8("sh_enable", 0), 0),
        ("tabelle dei quadrati pronte", m.read_u8("math_ready", 0), 0),
        // (i fuochi usano anche i byte alti dei puntatori dei quadrati, che tornano come all'avvio)
        ("puntatore sq1_lo", m.read_u8("sq1_lo", 1), (m.addr("square1_lo") >> 8) as u8),
        ("puntatore sq1_hi", m.read_u8("sq1_hi", 1), (m.addr("square1_hi") >> 8) as u8),
        ("puntatore sq2_lo", m.read_u8("sq2_lo", 1), (m.addr("square2_lo") >> 8) as u8),
        ("puntatore sq2_hi", m.read_u8("sq2_hi", 1), (m.addr("square2_hi") >> 8) as u8),
        ("canzone", m.read_u8("sid_song_n", 0), SID_SONG_CHAMPION),
    ] {
        if got != want {
            wrong.push(format!("{what} {got:#04x} invece di {want:#04x}"));
        }
    }
    if m.cpu.read16(0xFFFA) != nmi || m.cpu.cia2.running {
        wrong.push("NMI della voce ancora acceso".into());
    }
    // sotto l'I/O gli sprite del programma (salvo i due posti delle racchette, che la partita
    // rifà) e il titolo dell'attract: la bitmap della sfilata li copre, il finale li rimette
    let sprites = &m.image[0xC000 - 0x0801..0xC800 - 0x0801];
    let title = std::fs::read(c64_dir().join("gen/title.bin")).unwrap_or_default();
    if (0..0x800).any(|i| !(128..256).contains(&i) && m.cpu.under_io[i] != sprites[i])
        || title.is_empty()
        || m.cpu.under_io[0x800..0x800 + title.len()] != title[..]
    {
        wrong.push("sprite o titolo dell'attract sotto l'I/O non rimessi".into());
    }
    if !wrong.is_empty() {
        return Err(format!("uscita dal finale: {}", wrong.join(", ")));
    }
    // (le tabelle dei quadrati le rifà math_step nelle schermate dopo)
    m.call("math_ensure");
    Ok(r)
}

/// Il finale da capo nel banco `frames`: ogni frame nel budget, le parti nei loro tempi, YOU WIN
/// una volta, i fuochi di tutti i tipi, i titoli con i colori in tempo, l'uscita pulita.
fn ending_frames(m: &mut Machine) -> Result<String, String> {
    // (un punteggio con il resto della divisione per i 150 frame del conto oltre 255)
    let r = ending_run(m, 123_456, None)?;
    if !r.errors.is_empty() {
        let mut e = r.errors.clone();
        e.dedup();
        return Err(format!("{} ({} controlli falliti)", e.join("; "), r.errors.len()));
    }
    if r.worst > FRAME_BUDGET() {
        return Err(format!("frame di {} cicli nella parte {} (per parte cicli e frame: {:?})", r.worst, r.worst_part, r.part_worst));
    }
    if r.you_win != 1 {
        return Err(format!("YOU WIN! detta {} volte", r.you_win));
    }
    if r.kinds != 0x3F || r.fireworks < 250 || r.rockets == 0 {
        return Err(format!(
            "fuochi: tipi {:06b}, {} frame con le scintille, {} con i razzi",
            r.kinds, r.fireworks, r.rockets
        ));
    }
    if r.flips < 70 || r.late > 0 {
        return Err(format!("titoli: {} scambi, {} con i colori in ritardo", r.flips, r.late));
    }
    if r.bad_colors > 0 {
        return Err(format!("{} colori fuori da bianco, giallo e rosso", r.bad_colors));
    }
    let p = r.parts;
    Ok(format!(
        "finale: {} frame ({:.1} s: copia {}, CONGRATULATIONS {}, sfilata {}, punteggio {}, fuochi {}, titoli {}, THE END {}, uscita {}), cicli max {} (parte {}); YOU WIN una volta, scintille in {} frame (6 tipi), titoli con {} scambi e i colori prima del raster, solo bianco, giallo e rosso, uscita pulita",
        r.frames,
        r.frames as f64 / 50.0,
        p[0],
        p[1],
        p[2],
        p[3],
        p[4],
        p[5],
        p[6],
        p[7],
        r.worst,
        r.worst_part,
        r.fireworks,
        r.flips
    ))
}

/// Scritte grandi del GAME OVER (OV_* di play.s, tabelle over_*)
const OV_GAME_OVER: u8 = 0;
const OV_YOU_WIN: u8 = 1;
const OV_P2_WINS: u8 = 3;
const OV_CPU_WINS: u8 = 4;

/// Frame di nero alla fine del GAME OVER con GAME OVER in alto (AT_GAME_OVER_BLACK di
/// c64/gen/assets.inc, da attract.json).
fn over_black_frames() -> u32 {
    let inc = std::fs::read_to_string(c64_dir().join("gen/assets.inc")).unwrap_or_default();
    scene_frames(inc_const(&inc, "AT_GAME_OVER_BLACK").unwrap_or(0) as u32)
}

/// N frame a 50 Hz in frame del televisore in partita (le durate del C64 in partita: (n * TV_HZ + 25)
/// / 50 di tv.inc; sul PAL n).
fn tv_frames(n: u32) -> u32 {
    if ntsc() { (n * 60 + 25) / 50 } else { n }
}

/// Il frame appena eseguito era quello senza la scena (NTSC: tv_skip, play.s).
fn scene_skipped(m: &Machine) -> bool {
    let state = m.read_u8("state", 0);
    ntsc() && m.read_u8("tv_skip", 0) & 0x80 != 0 && state != ST_PLAY && state != ST_COUNT
}

/// N frame di una scena fuori dalla partita in frame del televisore: sull'NTSC la scena va a
/// 50 Hz (frame di play.s: uno su sei saltato), cioè 6/5 di frame in più.
fn scene_frames(n: u32) -> u32 {
    if ntsc() { (n * 6 + 2) / 5 } else { n }
}

/// Un GAME OVER animato (play.s, ov_scene), guardato frame per frame: le scritte `labels` (dalla
/// riga `top`) devono essere tutte a schermo insieme in almeno un frame. Con GAME OVER in alto la
/// mezzeria è già spenta quando le scritte sono finite, gli sprite si spengono e alla fine lo
/// schermo resta tutto nero per circa AT_GAME_OVER_BLACK frame; senza, mai tutto nero. Dopo la
/// scossa di PERFECT lo scroll fine torna quello di sempre.
struct OverWatch {
    labels: Vec<u8>,
    top: u16,
    seen: bool,
    black: u32,
    frames: u32,
}

impl OverWatch {
    fn new(labels: &[u8], top: u16) -> Self {
        Self { labels: labels.to_vec(), top, seen: false, black: 0, frames: 0 }
    }

    fn title(&self) -> bool {
        self.labels[0] == OV_GAME_OVER
    }

    /// Dopo ogni frame in cui lo stato è ancora ST_OVER.
    fn frame(&mut self, m: &Machine) -> Result<(), String> {
        self.frames += 1;
        // (finché le pagine non sono tutte copiate la mappa di PERFECT in memoria non c'è)
        if m.read_u8("ov_pg", 0) < 4 {
            return Ok(());
        }
        if over_labels_at(m, &self.labels, self.top).is_ok() {
            if !self.seen && self.title() {
                // la mezzeria fuori dal riquadro (righe 9-15) già spenta
                let net = (0..25u16).filter(|r| !(9..16).contains(r)).any(|r| {
                    let a = 0xC000 + r as usize * 40;
                    m.cpu.mem[a + 19] == 1 || m.cpu.mem[a + 20] == 2
                });
                if net {
                    return Err(format!("frame {}: scritte finite con la mezzeria ancora accesa", self.frames));
                }
                if m.read_u8("sh_enable", 0) != 0 {
                    return Err(format!("frame {}: scritte finite con gli sprite ancora accesi", self.frames));
                }
            }
            self.seen = true;
        }
        // (prima delle scritte lo schermo può essere vuoto: nei banchi di prova non c'è il campo)
        if self.seen && m.cpu.mem[0xC000..0xC3E8].iter().all(|&c| c == 0) {
            self.black += 1;
        }
        Ok(())
    }

    fn finish(&self, m: &Machine) -> Result<String, String> {
        if !self.seen {
            return Err(format!("scritte {:?} mai tutte a schermo in {} frame", self.labels, self.frames));
        }
        let want = over_black_frames();
        if self.title() && (self.black + 3 < want || self.black > want + 1) {
            return Err(format!("{} frame di schermo nero alla fine invece di circa {want}", self.black));
        }
        if !self.title() && self.black > 0 {
            return Err(format!("{} frame di schermo nero senza GAME OVER in alto", self.black));
        }
        if m.cpu.mem[0xD016] & 7 != 0 {
            return Err(format!("scroll fine rimasto a {}", m.cpu.mem[0xD016] & 7));
        }
        Ok(format!("{} frame, {} neri", self.frames, self.black))
    }
}

/// Le scritte grandi `labels` del GAME OVER, la prima dalla riga `top` e la seconda tre righe sotto,
/// centrate (colonna (40 - larghezza) / 2); con una sola, nelle righe 13-14 nessuna.
fn over_labels_at(m: &Machine, labels: &[u8], top: u16) -> Result<(), String> {
    let label_at = |k: u8, row: u16| -> Result<bool, String> {
        if k == OV_PERFECT {
            // (la grafica, dalla riga sopra: perfect_at)
            return Ok(row == 10 && perfect_at(m, false));
        }
        let w = m.image_u8("over_w", k as u16) as u16;
        let col = (40 - w) / 2;
        if m.image_u8("over_col", k as u16) as u16 != col {
            return Err(format!("scritta {k} non centrata"));
        }
        let at = (m.image_u8("over_lo", k as u16) as u16) | (m.image_u8("over_hi", k as u16) as u16) << 8;
        Ok((0..w).all(|c| {
            (0..2).all(|r| m.cpu.mem[(0xC000 + (row + r) * 40 + col + c) as usize] == m.cpu.mem[(at + r * w + c) as usize])
        }))
    };
    for (i, &k) in labels.iter().enumerate() {
        let row = top + 3 * i as u16;
        if !label_at(k, row)? {
            return Err(format!("scritta {k} non a schermo nelle righe {row}-{}", row + 1));
        }
    }
    if labels.len() == 1 {
        for k in [OV_GAME_OVER, OV_YOU_WIN, OV_P2_WINS, OV_CPU_WINS] {
            if label_at(k, 13)? {
                return Err(format!("scritta {k} di troppo nelle righe 13-14"));
            }
        }
    }
    Ok(())
}

/// Il finale saltato con il fuoco di chi gioca: prima del mezzo secondo (non salta), durante la
/// voce, nella sfilata, nei fuochi e nei titoli; ogni volta l'uscita pulita, la voce ferma. Poi
/// YOU WIN nel GAME OVER: contro la CPU quando vince chi gioca (Classic, un livello di CHALLENGE),
/// non quando vince la CPU né all'ultimo livello (la dice il finale). A schermo, centrate: solo
/// YOU WIN quando vince chi gioca, solo CPU WINS a un livello perso di CHALLENGE (si può ancora
/// continuare), se no GAME OVER e sotto CPU WINS (o P1/P2 WINS in due). Poi il continue lasciato
/// scadere: GAME OVER, e dopo le iniziali o la classifica.
fn ending_ui(m: &mut Machine) -> Result<String, String> {
    let mut lines = Vec::new();
    for (at, what) in [
        (20u32, "prima del mezzo secondo"),
        (80, "durante la voce"),
        (700, "nella sfilata"),
        (1450, "nei fuochi"),
        (1800, "nei titoli"),
    ] {
        let r = ending_run(m, 54_321, Some(at))?;
        let skipped = r.frames < 2500;
        if skipped == (at < 25) {
            return Err(format!("fuoco {what} (frame {at}): {} frame", r.frames));
        }
        if r.bad_colors > 0 {
            return Err(format!("fuoco {what}: {} colori fuori da bianco, giallo e rosso", r.bad_colors));
        }
        lines.push(format!("{what} {}", r.frames));
    }
    // YOU WIN nel GAME OVER (il finale ha coperto il codice delle mosse speciali, che la scelta di
    // NEXT ricopia sempre: qui lo si rimette)
    if let Some((at, bytes)) = m.moved_segment("SMCODE").map(|(a, b)| (a, b.to_vec())) {
        m.cpu.load(at, &bytes);
    }
    for (cg, level, cpu, left, right, want, labels, what) in [
        (0u8, 0u8, 4u8, 11u8, 3u8, 1usize, &[OV_YOU_WIN][..], "Classic vinta"),
        (0, 0, 4, 4, 11, 0, &[OV_GAME_OVER, OV_CPU_WINS][..], "Classic persa"),
        (0, 0, 0xFF, 4, 11, 0, &[OV_GAME_OVER, OV_P2_WINS][..], "Classic in due"),
        (1, 2, 4, 5, 1, 1, &[OV_YOU_WIN][..], "livello 3 di CHALLENGE"),
        (1, 2, 4, 1, 5, 0, &[OV_CPU_WINS][..], "livello 3 perso"),
        (1, 6, 4, 5, 1, 0, &[OV_YOU_WIN][..], "ultimo livello"),
    ] {
        quiet_inputs(m);
        m.cpu.a = m.read_u8("rung_kind", 0);
        m.call("ef_voice");
        for (name, v) in [("cg_active", cg), ("ch_level", level), ("ch_side", 0), ("cpu_side", cpu), ("m_players", 2), ("m_next", cg)] {
            m.write_u8(name, 0, v);
        }
        for (o, v) in [(0u16, left), (1, 0), (4, right), (5, 0)] {
            m.write_u8("score", o, v);
        }
        m.call("clear_screen"); // (le scritte del caso prima)
        m.call("enter_over");
        m.cpu.watch = Some((0xD418, 0xD418));
        m.cpu.writes.clear();
        let mut n = 0;
        let mut watch = OverWatch::new(labels, 10);
        while m.read_u8("state", 0) == ST_OVER && n < 300 {
            full_frame(m).map_err(|e| format!("GAME OVER, {what}, frame {n} (win_pg {}): {e}", m.read_u8("win_pg", 0)))?;
            if m.read_u8("state", 0) == ST_OVER {
                watch.frame(m).map_err(|e| format!("GAME OVER, {what}: {e}"))?;
            }
            n += 1;
        }
        watch.finish(m).map_err(|e| format!("GAME OVER, {what}: {e}"))?;
        let got: Vec<u8> = m.cpu.writes.iter().map(|w| w.1).collect();
        m.cpu.watch = None;
        let said = you_win_count(&got)?;
        if said != want {
            return Err(format!("GAME OVER, {what}: YOU WIN detta {said} volte invece di {want}"));
        }
        if want == 1 && m.read_u8("math_ready", 0) != 0 {
            return Err(format!("GAME OVER, {what}: dopo la voce le tabelle dei quadrati non si rifanno"));
        }
        if m.cpu.read16(0xFFFA) != m.addr("nmi_handler") || m.cpu.cia2.running {
            return Err(format!("GAME OVER, {what}: NMI della voce ancora acceso"));
        }
        // dall'ultimo livello si va al finale: lo si chiude (dopo la copia)
        if m.read_u8("state", 0) == ST_ENDING {
            while m.read_u8("e_part", 0) == 0 {
                full_frame(m)?;
            }
            m.call("close_enter");
            while m.read_u8("state", 0) == ST_ENDING {
                full_frame(m)?;
            }
        }
        m.call("math_ensure");
    }
    // continue con Start dopo un quarto di secondo (con il 9 a schermo): la presentazione
    quiet_inputs(m);
    let free = m.read_u8("opt_free", 0);
    for (name, v) in [("cg_active", 1u8), ("ch_level", 2), ("ch_side", 0), ("opt_free", 1)] {
        m.write_u8(name, 0, v);
    }
    m.call("enter_cont");
    // Start una volta, al primo frame in cui vale (CONT_SKIP_FRAMES di challenge.s dalla fine del
    // disegno, ch_elapsed); sull'NTSC non nel frame su sei senza il passo (tv_beat: tv_six a 0), che
    // non legge i comandi (sul C64 il tasto resta premuto anche nel frame dopo)
    const CONT_SKIP_FRAMES: u8 = 13;
    let mut pressed = false;
    for n in 0..30u32 {
        let skip = ntsc() && m.read_u8("tv_six", 0) == 0;
        let now = !pressed && !skip && m.read_u8("ch_phase", 0) == 0 && m.read_u8("ch_elapsed", 0) >= CONT_SKIP_FRAMES;
        pressed |= now;
        m.cpu.joy_port2 = if now { !0x10 } else { 0xFF };
        full_frame(m).map_err(|e| format!("continue con Start, frame {n}: {e}"))?;
        if m.read_u8("state", 0) != ST_CONT {
            break;
        }
    }
    m.cpu.joy_port2 = 0xFF;
    if m.read_u8("state", 0) != ST_INTRO {
        return Err(format!("continue: Start dopo un quarto di secondo non vale (stato {})", m.read_u8("state", 0)));
    }
    m.write_u8("opt_free", 0, free);
    // (la presentazione appena cominciata: le tabelle dei quadrati sotto l'entrata, intro.s)
    m.call("math_invalidate");
    m.call("math_ensure");
    // continue lasciato scadere: la pallina rimbalza accanto alla cifra (tocca terra a ogni
    // secondo, gialla negli ultimi tre), poi il GAME OVER animato, poi iniziali o classifica
    quiet_inputs(m);
    for (name, v) in [("cg_active", 1u8), ("ch_level", 2), ("ch_side", 0)] {
        m.write_u8(name, 0, v);
    }
    m.call("enter_cont");
    let (mut floor, mut lowest, mut yellow, mut white) = (0u32, 0u8, 0u32, 0u32);
    let mut n = 0u32;
    while m.read_u8("state", 0) == ST_CONT && n < scene_frames(600) {
        full_frame(m).map_err(|e| format!("continue, frame {n}: {e}"))?;
        n += 1;
        // (sull'NTSC solo i frame in cui la scena è andata avanti: scene_frames)
        if m.read_u8("state", 0) != ST_CONT || m.read_u8("ch_phase", 0) != 0 || scene_skipped(m) {
            continue;
        }
        if m.read_u8("sh_enable", 0) & 1 == 0 {
            return Err(format!("continue, frame {n}: pallina spenta"));
        }
        let y = m.read_u8("sh_y", 0);
        lowest = lowest.max(y);
        floor += (y == lowest) as u32;
        match m.read_u8("sh_col", 0) & 15 {
            1 => white += 1,
            7 => yellow += 1,
            c => return Err(format!("continue, frame {n}: pallina del colore {c}")),
        }
    }
    if m.read_u8("state", 0) != ST_OVER || !(8..=12).contains(&floor) || !(140..=160).contains(&yellow) || white < 300 {
        return Err(format!(
            "continue: dopo {n} frame lo stato {}; pallina a terra {floor} volte, gialla {yellow} frame, bianca {white}",
            m.read_u8("state", 0)
        ));
    }
    let mut watch = OverWatch::new(&[OV_GAME_OVER], 10);
    let mut over = 0u32;
    while m.read_u8("state", 0) == ST_OVER && over < 300 {
        full_frame(m).map_err(|e| format!("continue scaduto, frame {over}: {e}"))?;
        over += 1;
        if m.read_u8("state", 0) == ST_OVER {
            watch.frame(m).map_err(|e| format!("continue scaduto: {e}"))?;
        }
    }
    let seen = watch.finish(m).map_err(|e| format!("continue scaduto: {e}"))?;
    if ![ST_INITIALS, ST_SCORES].contains(&m.read_u8("state", 0)) {
        return Err(format!("continue scaduto: dopo il GAME OVER lo stato {}", m.read_u8("state", 0)));
    }
    m.call("math_ensure");
    Ok(format!(
        "finale saltato con il fuoco (frame giocati: {}), sempre con l'uscita pulita; YOU WIN nel GAME OVER solo se vince chi gioca contro la CPU (da sola e centrata), detta non all'ultimo livello; CPU WINS da sola a un livello perso; continue con Start dopo un quarto di secondo, pallina che tocca terra a ogni secondo (gialla negli ultimi tre), GAME OVER animato quando scade ({seen}, poi iniziali o classifica)",
        lines.join(", ")
    ))
}

/// PERFECT del GAME OVER (play.s, OV_PERFECT): la grafica (TP_MAP di gen/assets.inc, i caratteri
/// da TN_FIRST), che il codice del GAME OVER copia dalla cartuccia e disegna dalla riga 9.
const OV_PERFECT: u8 = 5;

/// La grafica di PERFECT a schermo dalla riga 9, centrata; con `colors` anche i colori delle fasce
/// (fuori dal riflesso).
fn perfect_at(m: &Machine, colors: bool) -> bool {
    let inc = std::fs::read_to_string(c64_dir().join("gen/assets.inc")).unwrap_or_default();
    let (map, rows) = (assets_list("TP_MAP"), assets_list("TP_ROWC"));
    let w = inc_const(&inc, "TP_W").unwrap_or(1);
    let k: Vec<u8> = (0..map.len()).map(|i| rows.get(i / w).copied().unwrap_or(0)).collect();
    !map.is_empty() && title_at(m, &map, colors.then_some(&k[..]), w, 9, (40 - w) / 2)
}
const OV_P1_WINS: u8 = 2;
/// win_pg a voce finita, con le tabelle dei quadrati da rifare (WIN_SAID di play.s).
const WIN_SAID: u8 = 19;

/// Lista `.define NOME ...` di c64/gen/assets.inc (numeri decimali o `$` esadecimali).
fn assets_list(name: &str) -> Vec<u8> {
    let inc = std::fs::read_to_string(c64_dir().join("gen/assets.inc")).unwrap_or_default();
    let prefix = format!(".define {name} ");
    inc.lines()
        .find_map(|l| l.strip_prefix(prefix.as_str()))
        .map(|l| {
            l.split(',')
                .filter_map(|v| {
                    let v = v.trim();
                    match v.strip_prefix('$') {
                        Some(h) => u8::from_str_radix(h, 16).ok(),
                        None => v.parse().ok(),
                    }
                })
                .collect()
        })
        .unwrap_or_default()
}

/// Titoli disegnati (tools/gen_c64_assets.py: gen/titles.bin, mappe in gen/assets.inc): le pagine
/// da `page` di titles.bin nel set di caratteri da `first`, una o due (`pages`).
fn title_chars(m: &Machine, page: usize, pages: usize, first: usize, what: &str) -> Result<(), String> {
    let bin = std::fs::read(c64_dir().join("gen/titles.bin")).map_err(|e| format!("titles.bin: {e}"))?;
    let want = bin.get(256 * page..256 * (page + pages)).ok_or("titles.bin troppo corto")?;
    let at = CHARSET + 8 * first;
    if m.cpu.mem[at..at + 256 * pages] != want[..] {
        return Err(format!("{what}: caratteri da {first} diversi da titles.bin (pagina {page})"));
    }
    Ok(())
}

/// I codici `map` di un titolo (`w` celle per riga; 0 = cella vuota) nel primo schermo dalla riga
/// `row`, colonna `col`; con `colors` anche i colori delle celle non vuote (giallo e rosso già
/// scambiati per l'easter egg, se c'è).
fn title_at(m: &Machine, map: &[u8], colors: Option<&[u8]>, w: usize, row: usize, col: usize) -> bool {
    map.iter().enumerate().all(|(i, &c)| {
        let a = (row + i / w) * 40 + col + i % w;
        m.cpu.mem[0xC000 + a] == c
            && colors.is_none_or(|k| c == 0 || m.cpu.mem[0xD800 + a] & 15 == k[i])
    })
}

/// La targa di HERE COMES A NEW CHALLENGER! (challenge.s, CHCODE): caratteri dalla cartuccia, la
/// mappa dalla riga 9, bianca e da TC_YEL0 gialla, i quattro sprite del rosso espansi dietro i
/// caratteri con l'immagine giusta.
fn plate_ok(m: &Machine, inc: &str) -> Result<(), String> {
    let get = |n: &str| inc_const(inc, n).ok_or(format!("assets.inc: manca {n}"));
    let (w, first, yel0, sprite, page) = (get("TC_W")?, get("TC_FIRST")?, get("TC_YEL0")?, get("TC_SPRITE")?, get("TTL_PLATE")?);
    title_chars(m, page, 2, first, "targa")?;
    let map = assets_list("TC_MAP");
    let colors: Vec<u8> = map.iter().map(|&c| if c as usize >= yel0 { COL_YELLOW } else { 1 }).collect();
    if map.is_empty() || !title_at(m, &map, Some(&colors), w, 9, (40 - w) / 2) {
        return Err("targa: caratteri o colori fuori posto".into());
    }
    let ptr = ((CHARSET + 8 * sprite - 0xC000) / 64) as u8;
    for i in 0..4u16 {
        if m.read_u8("sh_ptr", i) != ptr || m.read_u8("sh_col", i) & 15 != COL_RED {
            return Err(format!("targa: sprite {i} con l'immagine o il colore sbagliato"));
        }
    }
    if m.read_u8("sh_enable", 0) & 0x0F != 0x0F || m.read_u8("sh_xexp", 0) & 0x0F != 0x0F || m.cpu.mem[0xD01B] & 0x0F != 0x0F {
        return Err("targa: sprite del rosso spenti, non espansi o davanti ai caratteri".into());
    }
    Ok(())
}

/// Caratteri della scelta dei bonus (pick_chars, C = 0): da PICK_FIRST le metà alte dei glifi del
/// font abbassate di 4 pixel, poi le metà basse in cima; il resto del set com'era. Poi (C = 1, A = 0
/// e 1) di nuovo le lettere 2x: il set come all'avvio. Ogni chiamata nel budget di un frame.
fn pick_chars_ui(m: &mut Machine) -> Result<String, String> {
    let inc = std::fs::read_to_string(c64_dir().join("gen/assets.inc")).map_err(|e| format!("assets.inc: {e}"))?;
    let (Some(first), Some(font_first), Some(n)) =
        (inc_const(&inc, "PICK_FIRST"), inc_const(&inc, "FONT_FIRST"), inc_const(&inc, "FONT_CHARS"))
    else {
        return Err("assets.inc: manca PICK_FIRST, FONT_FIRST o FONT_CHARS".into());
    };
    let before: Vec<u8> = m.cpu.mem[CHARSET..CHARSET + 0x800].to_vec();
    if before != program_charset(m) {
        return Err("set di caratteri diverso da quello dell'avvio".into());
    }
    let mut want = before.clone();
    for i in 0..n {
        let g = &before[8 * (font_first + i)..8 * (font_first + i) + 8];
        let (top, bot) = (8 * (first + i), 8 * (first + n + i));
        want[top..top + 4].fill(0);
        want[top + 4..top + 8].copy_from_slice(&g[..4]);
        want[bot..bot + 4].copy_from_slice(&g[4..]);
        want[bot + 4..bot + 8].fill(0);
    }
    m.cpu.p &= !1;
    let mut worst = m.call("pick_chars");
    if m.cpu.mem[CHARSET..CHARSET + 0x800] != want[..] {
        return Err("metà delle lettere sbagliate".into());
    }
    for half in 0..2u8 {
        m.cpu.p |= 1;
        m.cpu.a = half;
        worst = worst.max(m.call("pick_chars"));
    }
    if m.cpu.mem[CHARSET..CHARSET + 0x800] != before[..] {
        return Err("dopo la scelta le lettere 2x non sono quelle di prima".into());
    }
    if worst > FRAME_BUDGET() - 3_000 {
        return Err(format!("{worst} cicli"));
    }
    Ok(format!("pick_chars: metà delle lettere della scelta dei bonus dai glifi del font, poi di nuovo le lettere 2x (al più {worst} cicli)"))
}

/// PERFECT nel GAME OVER, come sul PC e sul MiSTer: vinta da un giocatore (non dalla CPU) con chi
/// perde a 0 punti, PERFECT da sola al posto di YOU WIN contro la CPU, al posto di GAME OVER sopra
/// P1 / P2 WINS in due; la voce PERFECT una volta al posto di YOU WIN (anche in due, non
/// all'ultimo livello di CHALLENGE). Le altre partite come prima. Ogni GAME OVER dal frame con
/// l'ultimo punto (enter_over copia il suo codice dalla cartuccia), nel budget; cambia solo la
/// pagina del set di caratteri con PERFECT, e solo con PERFECT; finita la voce le tabelle dei
/// quadrati si rifanno già nel GAME OVER. Poi, dopo un PERFECT, l'attract fino al titolo con
/// INSERT COIN (nella bitmap: i caratteri di PERFECT restano, non si vedono più altrove).
fn perfect_ui(m: &mut Machine) -> Result<String, String> {
    let inc = std::fs::read_to_string(c64_dir().join("gen/assets.inc")).map_err(|e| format!("assets.inc: {e}"))?;
    let (Some(tn_first), Some(tp_page)) = (inc_const(&inc, "TN_FIRST"), inc_const(&inc, "TTL_PERFECT")) else {
        return Err("assets.inc: manca TN_FIRST o TTL_PERFECT".into());
    };
    let glyphs = program_glyphs(m);
    const CHARSET: usize = 0xC800;
    const OV_RUN: usize = 0xC400;
    m.call("math_ensure");
    let squares: Vec<u8> = m.cpu.mem[0xF000..0xF800].to_vec();
    let (mut worst_enter, mut worst) = (0u64, 0u64);
    for (cg, level, cpu, players, left, right, next, labels, voice, what) in [
        (0u8, 0u8, 4u8, 2u8, 11u8, 0u8, 0u8, &[OV_PERFECT][..], Some("perfect.bin"), "contro la CPU 11 a 0"),
        (0, 0, 0, 2, 0, 11, 1, &[OV_PERFECT][..], Some("perfect.bin"), "NEXT contro la CPU, chi gioca a destra, 0 a 11"),
        (0, 0, 0xFF, 2, 0, 11, 0, &[OV_PERFECT, OV_P2_WINS][..], Some("perfect.bin"), "in due 0 a 11"),
        (0, 0, 0xFF, 2, 11, 0, 1, &[OV_PERFECT, OV_P1_WINS][..], Some("perfect.bin"), "NEXT in due 11 a 0"),
        (0, 0, 4, 2, 11, 3, 0, &[OV_YOU_WIN][..], Some("you_win.bin"), "contro la CPU 11 a 3"),
        (0, 0, 4, 2, 0, 11, 0, &[OV_GAME_OVER, OV_CPU_WINS][..], None, "la CPU vince 11 a 0"),
        (0, 0, 0xFF, 2, 3, 11, 0, &[OV_GAME_OVER, OV_P2_WINS][..], None, "in due 3 a 11"),
        (0, 0, 0xFF, 1, 0, 0, 0, &[OV_GAME_OVER][..], None, "in singolo"),
        (1, 2, 4, 2, 5, 0, 1, &[OV_PERFECT][..], Some("perfect.bin"), "livello 3 di CHALLENGE 5 a 0"),
        (1, 2, 4, 2, 0, 5, 1, &[OV_CPU_WINS][..], None, "livello 3 di CHALLENGE perso 0 a 5"),
        (2, 6, 0xFF, 2, 5, 0, 1, &[OV_PERFECT, OV_P1_WINS][..], Some("perfect.bin"), "sfida di CHALLENGE all'ultimo livello 5 a 0"),
        (1, 6, 4, 2, 5, 0, 1, &[OV_PERFECT][..], None, "ultimo livello di CHALLENGE 5 a 0"),
    ] {
        quiet_inputs(m);
        m.cpu.a = m.read_u8("rung_kind", 0);
        m.call("ef_voice");
        m.call("math_ensure");
        for (name, v) in [
            ("cg_active", cg),
            ("ch_level", level),
            ("ch_side", 0),
            ("cpu_side", cpu),
            ("m_players", players),
            ("m_next", next),
            ("ch_phase", 0),
            ("lives", 0),
            ("om_on", 0), // (una partita qualsiasi, non contro OMEGA: begin_match lo azzera)
        ] {
            m.write_u8(name, 0, v);
        }
        for (o, v) in [(0u16, left), (1, 0), (4, right), (5, 0)] {
            m.write_u8("score", o, v);
        }
        m.call("clear_screen");
        // il codice del GAME OVER cancellato (BRK): deve copiarlo enter_over
        m.cpu.mem[OV_RUN..OV_RUN + 0x400].fill(0);
        let before: Vec<u8> = m.cpu.mem[CHARSET..CHARSET + 0x800].to_vec();
        // il frame dopo l'ultimo punto
        m.write_u8("state", 0, ST_PLAY);
        m.write_u8("over_next", 0, 1);
        m.cpu.watch = Some((0xD418, 0xD418));
        m.cpu.writes.clear();
        let c = full_frame(m).map_err(|e| format!("{what}: frame del GAME OVER: {e}"))?;
        if m.read_u8("state", 0) != ST_OVER || c > FRAME_BUDGET() {
            return Err(format!("{what}: frame del GAME OVER con lo stato {} e {c} cicli", m.read_u8("state", 0)));
        }
        worst_enter = worst_enter.max(c);
        let shown = labels[0] == OV_PERFECT;
        let mut frames = 0;
        let mut rebuilt = None;
        let mut watch = OverWatch::new(labels, 10);
        while m.read_u8("state", 0) == ST_OVER && frames < 300 {
            if m.read_u8("timer", 0) == 1 {
                rebuilt = Some(m.read_u8("math_ready", 0) != 0 && m.cpu.mem[0xF000..0xF800] == squares[..]);
                // all'ultimo frame: PERFECT a schermo (con GAME OVER in alto lo schermo è già nero),
                // il set di caratteri com'era, con i glifi della ROM, salvo con PERFECT la sua
                // pagina (TN_FIRST, caratteri che lì non si vedono)
                if shown != perfect_at(m, false) {
                    return Err(format!("{what}: PERFECT {} nelle righe 9-12", if shown { "non" } else { "di troppo" }));
                }
                let page = CHARSET + 8 * tn_first;
                if shown {
                    title_chars(m, tp_page, 1, tn_first, what)?;
                }
                let same = |a: usize, b: usize| m.cpu.mem[a..b] == before[a - CHARSET..b - CHARSET];
                if !same(CHARSET, page) || !same(page + 256, CHARSET + 0x800) || (!shown && !same(page, page + 256)) {
                    return Err(format!("{what}: set di caratteri cambiato dal GAME OVER"));
                }
                check_glyphs(m, &glyphs, what)?;
            }
            let ef = m.cpu.ef_cycles;
            let c = full_frame(m).map_err(|e| format!("{what}, frame {frames} (win_pg {}): {e}", m.read_u8("win_pg", 0)))?;
            // (dopo la sfida la presentazione: la copia del file voce è un caricamento, come in frames)
            let c = if m.read_u8("state", 0) == ST_INTRO { c - (m.cpu.ef_cycles - ef) } else { c };
            if c > FRAME_BUDGET() {
                return Err(format!("{what}: frame {frames} del GAME OVER di {c} cicli"));
            }
            worst = worst.max(c);
            frames += 1;
            if m.read_u8("state", 0) == ST_OVER {
                watch.frame(m).map_err(|e| format!("{what}: {e}"))?;
            }
        }
        watch.finish(m).map_err(|e| format!("{what}: {e}"))?;
        let got: Vec<u8> = m.cpu.writes.iter().map(|w| w.1).collect();
        m.cpu.watch = None;
        for file in ["perfect.bin", "you_win.bin"] {
            let said = voice_count(&got, file)?;
            let want = (voice == Some(file)) as usize;
            if said != want {
                return Err(format!("{what}: {file} detta {said} volte invece di {want}"));
            }
        }
        if m.cpu.read16(0xFFFA) != m.addr("nmi_handler") || m.cpu.cia2.running {
            return Err(format!("{what}: NMI della voce ancora acceso"));
        }
        // con la voce (campioni sulle tabelle dei quadrati) le tabelle rifatte prima della fine;
        // senza, mai toccate
        if rebuilt != Some(true) || (voice.is_some() && m.read_u8("win_pg", 0) != WIN_SAID) {
            return Err(format!(
                "{what}: tabelle dei quadrati {} all'ultimo frame del GAME OVER (win_pg {})",
                if rebuilt.is_none() { "non viste" } else { "non pronte" },
                m.read_u8("win_pg", 0)
            ));
        }
        // dall'ultimo livello si va al finale: lo si chiude (dopo la copia)
        if m.read_u8("state", 0) == ST_ENDING {
            while m.read_u8("e_part", 0) == 0 {
                full_frame(m)?;
            }
            m.call("close_enter");
            while m.read_u8("state", 0) == ST_ENDING {
                full_frame(m)?;
            }
        }
    }
    // dopo un PERFECT l'attract, fino al titolo con INSERT COIN (senza crediti)
    quiet_inputs(m);
    m.call("math_ensure");
    let free = m.read_u8("opt_free", 0);
    for (name, v) in [("cg_active", 0u8), ("cpu_side", 4), ("m_players", 2), ("m_next", 0), ("ch_phase", 0), ("opt_free", 0), ("credits", 0)] {
        m.write_u8(name, 0, v);
    }
    for (o, v) in [(0u16, 11u8), (1, 0), (4, 0), (5, 0)] {
        m.write_u8("score", o, v);
    }
    m.write_u8("state", 0, ST_PLAY);
    m.write_u8("over_next", 0, 1);
    let mut stamped = false;
    for _ in 0..60 {
        full_frame(m)?;
        stamped |= perfect_at(m, true);
    }
    if !stamped {
        return Err("prima dell'attract: PERFECT non a schermo con i colori delle fasce".into());
    }
    let mut frames = 0u32;
    let mut coin = false;
    while frames < 12_000 && !coin {
        full_frame(m).map_err(|e| format!("verso il titolo, frame {frames} (stato {}): {e}", m.read_u8("state", 0)))?;
        frames += 1;
        coin = m.read_u8("state", 0) == 3 && m.read_u8("at_label", 0) == 1;
    }
    if !coin {
        return Err(format!("titolo senza INSERT COIN dopo {frames} frame (stato {})", m.read_u8("state", 0)));
    }
    m.write_u8("opt_free", 0, free);
    m.call("math_ensure");
    Ok(format!(
        "PERFECT nel GAME OVER da solo contro la CPU e sopra P1 / P2 WINS in due, con la voce (non all'ultimo livello di CHALLENGE); YOU WIN, CPU WINS, GAME OVER come prima; la grafica di PERFECT con i colori delle fasce e i suoi caratteri dalla cartuccia, il resto del set non cambia (glifi della ROM); frame dell'ultimo punto al più {worst_enter} cicli, GAME OVER al più {worst}; poi l'attract fino al titolo con INSERT COIN (dopo {frames} frame)"
    ))
}

/// Solo il finale (`paddws-c64 ending`), dopo l'avvio: quello che `frames` fa alla fine.
fn ending_alone(m: &mut Machine) -> bool {
    for r in ["title_unpack", "clear_vars", "math_init", "video_init", "input_init", "sid_init"] {
        m.call(r);
    }
    match ending_frames(m) {
        Ok(s) => {
            println!("PASS: {s}");
            true
        }
        Err(e) => {
            println!("FAIL: finale di CHALLENGE: {e}");
            false
        }
    }
}

// ------------------------------------------------------------------------------- easter egg (BAS) + colori racchette

/// Verifica: "!" nelle lettere delle iniziali, $D026 bianco (scafo) e colori dedicati `kind_col`
/// per tutte le 7 astronavi + OMEGA, e BAS con il joystick che sblocca il JUKEBOX.
fn egg_ui(m: &mut Machine) -> Result<String, String> {
    let letters: Vec<u8> = (0..38).map(|i| m.read_u8("letters", i)).collect();
    if letters != b"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 !" {
        return Err(format!("lettere delle iniziali {:?}", String::from_utf8_lossy(&letters)));
    }
    if m.cpu.mem[0xD026] & 15 != 1 {
        return Err(format!("$D026 = {} invece di 1 (bianco scafo)", m.cpu.mem[0xD026] & 15));
    }
    let want_cols = [7u8, 8, 2, 4, 5, 3, 14, 4];
    let got_cols: Vec<u8> = (0..8).map(|i| m.read_u8("kind_col", i)).collect();
    if got_cols != want_cols {
        return Err(format!("kind_col = {got_cols:?} invece di {want_cols:?}"));
    }
    // BAS con il joystick (B, A, S): il JUKEBOX sbloccato, salvato con la classifica
    for i in 0..80 {
        let b = m.image_u8("table_init", i);
        m.write_u8("ch_table", i, b);
    }
    m.cpu.write(0xDC00, 0xFF);
    m.cpu.write(0xDC01, 0xFF);
    let saved_juke = m.read_u8("hi_juke", 0);
    m.write_u8("hi_juke", 0, 0xFF);
    m.write_i32("ch_best", 0, 400_000);
    m.write_u8("ch_best_lv", 0, 3);
    m.write_u8("ch_loser", 0, 0);
    m.write_u8("cg_active", 0, 0);
    m.call("table_rank");
    let rank = m.cpu.a;
    m.write_u8("ch_rank", 0, rank);
    m.call("enter_initials");
    let frame = |m: &mut Machine, joy: u8| {
        m.cpu.joy_port2 = joy;
        m.call("read_input");
        m.call("run_scene");
    };
    for _ in 0..3 {
        frame(m, 0xFF);
    }
    for (moves, bit) in [(1, 0x02u8), (1, 0x01), (18, 0x02)] {
        for b in std::iter::repeat_n(bit, moves).chain([0x10]) {
            frame(m, 0xFF);
            frame(m, !b);
        }
    }
    m.cpu.joy_port2 = 0xFF;
    let name: Vec<u8> = (0..3).map(|i| m.read_u8("ch_table", i)).collect();
    if rank != 0 || name != b"BAS" || m.read_u8("hi_juke", 0) != 0 || m.read_u8("state", 0) != ST_SCORES {
        return Err(format!(
            "BAS con il joystick: posto {rank}, nome {:?}, hi_juke {:02x}, scena {}",
            String::from_utf8_lossy(&name),
            m.read_u8("hi_juke", 0),
            m.read_u8("state", 0)
        ));
    }
    m.write_u8("hi_juke", 0, saved_juke);
    Ok("colori dedicati 7 astronavi + OMEGA ($D026 bianco, kind_col); BAS sblocca il JUKEBOX".into())
}

/// Colori a schermo alla fine di un frame: i registri di colore del VIC ($D020-$D02E) che si
/// vedono (gli altri a zero: $D022-$D024 solo con i caratteri multicolore, $D025-$D026 solo con
/// uno sprite multicolore acceso, i colori degli sprite accesi), la RAM dei colori, i colori della
/// bitmap (solo nel modo bitmap: nello schermo che dice $D018, $C400 nell'attract e $C000 nella
/// HOW TO PLAY; lì la RAM dei colori a zero, non si vede; non nelle schermate dei personaggi) e in fondo i modi (bit 0 bitmap, bit 1 caratteri
/// multicolore). A schermo spento ($D011 bit 4 a zero) c'è solo il bordo.
fn screen_colors(m: &Machine) -> Vec<u8> {
    let mem = &m.cpu.mem;
    if mem[0xD011] & 0x10 == 0 {
        let mut v = vec![0; 1016];
        v[0] = mem[0xD020] & 15;
        return v;
    }
    let (on, mc_text) = (mem[0xD015], mem[0xD016] & 0x10 != 0);
    let mut v: Vec<u8> = (0xD020..=0xD02Eusize)
        .map(|a| {
            let seen = match a {
                0xD020 | 0xD021 => true,
                0xD022..=0xD024 => mc_text,
                0xD025 | 0xD026 => on & mem[0xD01C] != 0,
                _ => on >> (a - 0xD027) & 1 != 0,
            };
            if seen { mem[a] & 15 } else { 0 }
        })
        .collect();
    let bitmap = mem[0xD011] & 0x20 != 0;
    // (nella bitmap hires la RAM dei colori non si vede: conta solo a caratteri o in multicolore;
    // a caratteri non sotto quelli vuoti, CH_BLANK = 0: la pulizia dello schermo vuota prima i
    // caratteri e poi, al frame dopo, i colori, ch_phases)
    let text = 0xC000 + (mem[0xD018] as usize >> 4) * 0x400;
    v.extend((0xD800..0xDBE8).map(|a| {
        if (bitmap && !mc_text) || (!bitmap && mem[text + a - 0xD800] == 0) { 0 } else { mem[a] & 15 }
    }));
    // (le schermate dei personaggi, 4.5.0: scelta della racchetta, VS, sfilata, hanno i colori dei
    // ritratti e delle scritte nei dati, come sul PC senza scambio: lì i colori della bitmap no;
    // nella scelta l'unica altra bitmap è la HOW TO PLAY, con hw_pg)
    let portraits = (m.read_u8("state", 0) == ST_PICK && m.read_u8("hw_pg", 0) == 0)
        || (m.read_u8("state", 0) == ST_INTRO && m.read_u8("in_vs", 0) == 1)
        || mem[0xD018] == 0xC0;
    if bitmap && !portraits {
        let matrix = 0xC000 + (mem[0xD018] as usize >> 4) * 0x400;
        v.extend_from_slice(&mem[matrix..matrix + 1000]);
    }
    v.push(bitmap as u8 | (mc_text as u8) << 1);
    v
}
