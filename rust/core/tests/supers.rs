//! Mosse speciali di NEXT (`Next::super_moves`): barra, costo, STRAIGHT SHOT, RISING STRIKE,
//! opzione spenta, CPU e ripetibilità.

use paddws_core::fixed::{self, ONE};
use paddws_core::{Bonus, Cpu, Event, Events, Fx, Input, Match, Params, PlayerInput, Side, Special, TICK_HZ, Tuning};

const LOADOUTS: [[Bonus; 3]; 2] = [
    [Bonus::Smash, Bonus::Teleport, Bonus::Curve],
    [Bonus::Slow, Bonus::Ghost, Bonus::Smash],
];

/// Partita NEXT senza attesa della battuta e senza capsule, con le mosse accese o spente.
fn make(on: bool) -> Match {
    let params = Params::new(&Tuning {
        serve_delay: 0.0,
        ..Tuning::default()
    });
    let mut m = Match::new_next(params, LOADOUTS, 1);
    m.set_super_moves(on);
    m.next.as_mut().unwrap().spawn_timer = u32::MAX;
    m
}

fn meter(m: &Match, side: Side) -> u8 {
    m.next.as_ref().unwrap().players[side as usize].meter
}

fn set_meter(m: &mut Match, side: Side, v: u8) {
    m.next.as_mut().unwrap().players[side as usize].meter = v;
}

/// Barra per `moves` mosse.
fn fill(m: &mut Match, side: Side, moves: u8) {
    let v = m.params.super_cost * moves;
    set_meter(m, side, v);
}

fn special(m: &mut Match, side: Side, s: Special) -> Events {
    let mut input = Input::default();
    input.players[side as usize] = PlayerInput {
        special: Some(s),
        ..Default::default()
    };
    m.step(&input)
}

/// Avanza senza comandi fino al primo colpo (al massimo 3 s): gli eventi di quel tick.
fn until_hit(m: &mut Match) -> Events {
    for _ in 0..TICK_HZ * 3 {
        let e = m.step(&Input::default());
        if e.has(Event::Hit) || e.has(Event::Boost) {
            return e;
        }
        assert!(!e.has(Event::Score), "punto invece del colpo");
    }
    panic!("nessun colpo");
}

/// Palla verso la racchetta di `side`, dritta e al centro in altezza.
fn aim_at_paddle(m: &mut Match, side: Side) {
    let (w, h) = (m.params.width, m.params.height);
    m.paddles[side as usize].y = h / 2;
    m.ball.x = w / 2;
    m.ball.y = h / 2;
    let vx = fixed::from_f64(3.0 * 60.0 / TICK_HZ as f64);
    m.ball.vx = if side == Side::Left { -vx } else { vx };
    m.ball.vy = 0;
}

/// Palla che passa sotto la racchetta sinistra: punto per il destro.
fn concede_left(m: &mut Match) {
    m.paddles[0].y = m.params.height - m.paddles[0].height / 2;
    m.ball.x = m.params.width / 4;
    m.ball.y = fixed::int(20);
    m.ball.vx = -fixed::int(2);
    m.ball.vy = 0;
}

#[test]
fn events_fit_in_sixteen_bits() {
    assert_eq!(Event::Straight as u16, 1 << 10);
    assert_eq!(Event::Rise as u16, 1 << 11);
    assert_eq!(Event::SpecialHit as u16, 1 << 12);
}

#[test]
fn meter_grows_with_hits_dashes_and_conceded_points_up_to_the_max() {
    let mut m = make(true);
    let p = m.params.clone();
    // colpo normale
    aim_at_paddle(&mut m, Side::Left);
    until_hit(&mut m);
    assert_eq!(meter(&m, Side::Left), p.super_gain_hit);
    // scatto che intercetta la palla: la barra cresce di più
    let pad = &m.paddles[1];
    m.ball.y = pad.y;
    m.ball.x = pad.left() - fixed::int(40);
    m.ball.vx = fixed::int(1);
    let mut dash = Input::default();
    dash.players[1].forward = true;
    assert!(m.step(&dash).has(Event::Boost));
    assert_eq!(meter(&m, Side::Right), p.super_gain_dash);
    // punto subito: la barra di chi lo subisce cresce e resta da un punto all'altro
    let before = meter(&m, Side::Left);
    concede_left(&mut m);
    let mut scored = false;
    for _ in 0..TICK_HZ {
        if m.step(&Input::default()).has(Event::Score) {
            scored = true;
            break;
        }
    }
    assert!(scored);
    assert_eq!(meter(&m, Side::Left), before + p.super_gain_conceded);
    assert_eq!(meter(&m, Side::Right), p.super_gain_dash);
    // fino al massimo, non oltre
    set_meter(&mut m, Side::Left, p.super_meter_max - 1);
    m.serve_timer = 0;
    aim_at_paddle(&mut m, Side::Left);
    until_hit(&mut m);
    assert_eq!(meter(&m, Side::Left), p.super_meter_max);
}

#[test]
fn a_move_needs_the_cost_and_spends_it() {
    let mut m = make(true);
    let cost = m.params.super_cost;
    m.ball.vx = fixed::int(1); // la palla va dall'altra parte
    set_meter(&mut m, Side::Left, cost - 1);
    let y = m.paddles[0].y;
    m.ball.y = y + fixed::int(50);
    for s in Special::ALL {
        let e = special(&mut m, Side::Left, s);
        assert!(!e.has(Event::Straight) && !e.has(Event::Rise), "{s:?} senza barra");
    }
    let pl = &m.next.as_ref().unwrap().players[0];
    assert_eq!((pl.meter, pl.straight, pl.rise), (cost - 1, 0, 0));
    assert_eq!(m.paddles[0].y, y);
    // con un settore pieno parte al livello 1 e lo spende
    set_meter(&mut m, Side::Left, cost + 3);
    assert!(special(&mut m, Side::Left, Special::Straight).has(Event::Straight));
    assert_eq!(meter(&m, Side::Left), 3);
    assert_eq!(m.next.as_ref().unwrap().players[0].straight, 1);
    // con due settori pieni li spende tutti e due: livello 2
    let mut m = make(true);
    m.ball.vx = fixed::int(1);
    set_meter(&mut m, Side::Left, 2 * cost + 1);
    assert!(special(&mut m, Side::Left, Special::Straight).has(Event::Straight));
    assert_eq!(meter(&m, Side::Left), 1);
    assert_eq!(m.next.as_ref().unwrap().players[0].straight, 2);
    // non durante l'attesa della battuta
    let mut m = make(true);
    set_meter(&mut m, Side::Left, cost);
    m.serve_timer = 10;
    assert!(!special(&mut m, Side::Left, Special::Straight).has(Event::Straight));
    assert_eq!(meter(&m, Side::Left), cost);
}

/// STRAIGHT SHOT armato con `moves` settori e colpito.
fn straight_shot(moves: u8) -> Match {
    let mut m = make(true);
    fill(&mut m, Side::Left, moves);
    aim_at_paddle(&mut m, Side::Left);
    // colpita lontano dal centro della racchetta, che di solito dà angolo
    m.paddles[0].y -= fixed::int(15);
    assert!(special(&mut m, Side::Left, Special::Straight).has(Event::Straight));
    assert_eq!(m.next.as_ref().unwrap().players[0].straight, moves);
    let e = until_hit(&mut m);
    assert!(e.has(Event::SpecialHit));
    assert!(m.ball.vx > 0);
    assert_eq!(m.ball.vy, 0);
    let n = m.next.as_ref().unwrap();
    assert_eq!(n.players[0].straight, 0, "disarmato dopo il colpo");
    assert_eq!((n.special_flight, n.special_level), (Some(Special::Straight), moves));
    m
}

#[test]
fn straight_shot_is_one_and_a_half_or_twice_as_fast_with_one_or_two_bars() {
    assert_eq!(straight_shot(1).ball.boost, ONE + (ONE >> 1));
    assert_eq!(straight_shot(2).ball.boost, ONE * 2);
}

#[test]
fn straight_shot_is_flat_and_faster_for_one_shot() {
    let mut m = straight_shot(1);
    // l'avversario la ribatte: si torna alla velocità normale
    for _ in 0..TICK_HZ * 3 {
        m.paddles[1].y = m.ball.y;
        if m.step(&Input::default()).has(Event::Hit) {
            break;
        }
    }
    assert!(m.ball.vx < 0);
    assert_eq!(m.ball.boost, ONE);
    assert_eq!(m.next.as_ref().unwrap().special_flight, None);
}

#[test]
fn straight_shot_is_lost_at_a_point() {
    let mut m = make(true);
    fill(&mut m, Side::Left, 1);
    m.ball.vx = fixed::int(1);
    assert!(special(&mut m, Side::Left, Special::Straight).has(Event::Straight));
    concede_left(&mut m);
    while !m.step(&Input::default()).has(Event::Score) {}
    assert_eq!(m.next.as_ref().unwrap().players[0].straight, 0);
}

/// Arma RISING STRIKE con `moves` settori e la colpisce: la palla parte verso destra.
fn rising_shot(moves: u8) -> Match {
    let mut m = make(true);
    fill(&mut m, Side::Left, moves);
    aim_at_paddle(&mut m, Side::Left);
    m.paddles[0].y -= fixed::int(15);
    // l'avversario in basso (la y cresce verso l'alto): la palla s'impennerà verso l'alto
    m.paddles[1].y = m.paddles[1].height / 2;
    assert!(special(&mut m, Side::Left, Special::Rise).has(Event::Rise));
    assert_eq!(m.next.as_ref().unwrap().players[0].rise, moves);
    let e = until_hit(&mut m);
    assert!(e.has(Event::SpecialHit));
    let n = m.next.as_ref().unwrap();
    assert_eq!((n.special_flight, n.special_level), (Some(Special::Rise), moves));
    assert_eq!(n.players[0].rise, 0, "disarmato dopo il colpo");
    m
}

/// x della palla quando s'impenna (vy diventa diversa da zero).
fn rise_point(m: &mut Match) -> Fx {
    assert_eq!(m.ball.vy, 0, "parte orizzontale");
    for _ in 0..TICK_HZ * 6 {
        m.paddles[1].y = m.paddles[1].height / 2; // l'avversario resta in basso
        m.step(&Input::default());
        if m.ball.vy != 0 {
            return m.ball.x;
        }
    }
    panic!("non s'impenna");
}

#[test]
fn rising_strike_leaves_flat_and_breaks_at_45_degrees_late() {
    let mut m = rising_shot(1);
    let x = rise_point(&mut m);
    let w = m.params.width;
    let at = (w >> 1) + (w >> 3);
    assert!(x >= at && x < at + m.ball.dx.abs() + fixed::int(1), "s'impenna a 5/8: {x}");
    assert_eq!(m.ball.vy, m.ball.vx.abs(), "a 45 gradi, verso l'alto (lontano dall'avversario)");
    assert!(m.next.as_ref().unwrap().rise_break.is_none());
}

#[test]
fn full_bar_rising_strike_breaks_later() {
    let mut m = rising_shot(2);
    let x = rise_point(&mut m);
    let at = m.params.width - (m.params.width >> 3);
    assert!(x >= at && x < at + m.ball.dx.abs() + fixed::int(1), "s'impenna a 7/8: {x}");
    assert_eq!(meter(&m, Side::Left), m.params.super_gain_hit, "spesi entrambi i settori");
}

#[test]
fn rising_strike_breaks_away_from_where_the_opponent_is_at_the_break() {
    let mut m = rising_shot(1);
    // l'avversario si sposta in alto prima della soglia: la palla va verso il basso
    for _ in 0..TICK_HZ * 3 {
        m.paddles[1].y = m.params.height - m.paddles[1].height / 2;
        m.step(&Input::default());
        if m.ball.vy != 0 {
            break;
        }
    }
    assert_eq!(m.ball.vy, -m.ball.vx.abs());
}

#[test]
fn moves_and_bonuses_do_not_mix() {
    let mut m = make(true);
    let cost = m.params.super_cost;
    m.ball.vx = fixed::int(1);
    // con un bonus armato la mossa non parte
    set_meter(&mut m, Side::Left, cost);
    m.next.as_mut().unwrap().players[0].armed = Some(Bonus::Smash);
    assert!(!special(&mut m, Side::Left, Special::Straight).has(Event::Straight));
    assert_eq!(meter(&m, Side::Left), cost);
    // con una mossa in corso il bonus non si attiva
    m.next.as_mut().unwrap().players[1].reserve = [Some(Bonus::Smash), None, None];
    set_meter(&mut m, Side::Right, cost);
    assert!(special(&mut m, Side::Right, Special::Straight).has(Event::Straight));
    let mut activate = Input::default();
    activate.players[1].activate = true;
    assert!(!m.step(&activate).has(Event::Activate));
    // e nemmeno una seconda mossa
    set_meter(&mut m, Side::Right, cost);
    assert!(!special(&mut m, Side::Right, Special::Rise).has(Event::Rise));
}

#[test]
fn with_the_option_off_moves_do_nothing() {
    let mut m = make(false);
    assert!(!m.super_moves());
    aim_at_paddle(&mut m, Side::Left);
    until_hit(&mut m);
    assert_eq!(meter(&m, Side::Left), 0, "la barra non cresce");
    set_meter(&mut m, Side::Left, 64);
    for s in Special::ALL {
        let e = special(&mut m, Side::Left, s);
        assert!(!e.has(Event::Straight) && !e.has(Event::Rise));
    }
    assert_eq!(meter(&m, Side::Left), 64);
    // spente a partita in corso: la mossa armata finisce e non blocca i bonus
    let mut m = make(true);
    m.ball.vx = fixed::int(1);
    fill(&mut m, Side::Left, 1);
    assert!(special(&mut m, Side::Left, Special::Straight).has(Event::Straight));
    m.set_super_moves(false);
    m.next.as_mut().unwrap().players[0].reserve = [Some(Bonus::Smash), None, None];
    let mut activate = Input::default();
    activate.players[0].activate = true;
    assert!(m.step(&activate).has(Event::Activate));
    // fuori da NEXT l'opzione non c'è
    let mut classic = Match::new(m.params.clone(), 2, true, 1);
    classic.set_super_moves(true);
    assert!(!classic.super_moves());
}

#[test]
fn with_the_option_off_special_commands_leave_the_match_identical() {
    let run = |specials: bool| {
        let mut m = make(false);
        m.next.as_mut().unwrap().spawn_timer = 10; // anche le capsule
        let mut cpus = [Cpu::new(&m.params, 2, Side::Left, 1), Cpu::new(&m.params, 2, Side::Right, 2)];
        for t in 0..TICK_HZ * 120 {
            let mut input = Input::default();
            for cpu in &mut cpus {
                input.players[cpu.side() as usize] = cpu.input(&m);
            }
            if specials {
                input.players[(t % 2) as usize].special = Some(Special::ALL[(t / 7 % 2) as usize]);
            }
            m.step(&input);
        }
        m
    };
    assert_eq!(run(false), run(true));
}

/// Partita tra due CPU: (STRAIGHT SHOT, RISING STRIKE, colpi speciali, comandi di mossa).
fn cpu_duel(on: bool, level: u8, seconds: u32, seed: u32) -> ([u32; 4], Match) {
    let params = Params::new(&Tuning {
        difficulty: level.min(3),
        ..Tuning::default()
    });
    let mut m = Match::new_next(params, LOADOUTS, seed);
    m.set_super_moves(on);
    let mut cpus = [
        Cpu::new(&m.params, level, Side::Left, seed),
        Cpu::new(&m.params, level, Side::Right, seed ^ 1),
    ];
    let mut n = [0u32; 4];
    for _ in 0..TICK_HZ * seconds {
        let mut input = Input::default();
        for cpu in &mut cpus {
            let cmd = cpu.input(&m);
            n[3] += cmd.special.is_some() as u32;
            input.players[cpu.side() as usize] = cmd;
        }
        let e = m.step(&input);
        n[0] += e.has(Event::Straight) as u32;
        n[1] += e.has(Event::Rise) as u32;
        n[2] += e.has(Event::SpecialHit) as u32;
    }
    (n, m)
}

#[test]
fn cpu_uses_both_moves_only_when_they_are_on() {
    let (off, _) = cpu_duel(false, 3, 300, 5);
    assert_eq!(off, [0; 4], "mosse con l'opzione spenta");
    let (on, m) = cpu_duel(true, 3, 300, 5);
    assert!(on[0] > 0 && on[1] > 0, "STRAIGHT {} RISING {}", on[0], on[1]);
    assert!(on[2] > 0);
    let p = &m.params;
    assert!(m.next.as_ref().unwrap().players.iter().all(|pl| pl.meter <= p.super_meter_max));
}

#[test]
fn stronger_cpu_uses_moves_more_often() {
    let moves = |level| {
        (0..3)
            .map(|s| {
                let n = cpu_duel(true, level, 200, 20 + s).0;
                n[0] + n[1]
            })
            .sum::<u32>()
    };
    let (easy, expert) = (moves(0), moves(3));
    assert!(expert > easy, "mosse: facile {easy}, esperto {expert}");
}

#[test]
fn matches_with_moves_are_reproducible() {
    let (a, ma) = cpu_duel(true, 2, 120, 9);
    let (b, mb) = cpu_duel(true, 2, 120, 9);
    assert_eq!(a, b);
    assert_eq!(ma, mb);
}
