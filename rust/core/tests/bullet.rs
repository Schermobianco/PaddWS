//! BULLET (bullet time): attesa della palla nella propria metà campo, rampa, cosa rallenta e cosa
//! no, fine alla ribattuta o al punto, un BULLET alla volta, rarità delle capsule e uso della CPU.

use paddws_core::fixed::{self, mul};
use paddws_core::{
    Bonus, Capsule, Cpu, Event, Input, Match, PaddleKind, Params, PlayerInput, Rng, Shot, Side, TICK_HZ, Tuning, slowed,
};

const LOADOUTS: [[Bonus; 3]; 2] = [
    [Bonus::Smash, Bonus::Teleport, Bonus::Curve],
    [Bonus::Slow, Bonus::Ghost, Bonus::Smash],
];

fn params() -> Params {
    Params::new(&Tuning {
        serve_delay: 0.0,
        ..Tuning::default()
    })
}

/// Partita NEXT in gioco, senza capsule casuali, con un BULLET nella riserva di `owner` e la palla
/// lenta verso di lui, appena entrata nella sua metà campo (il BULLET scatta subito).
fn make(kinds: [Option<PaddleKind>; 2], owner: Side) -> Match {
    let mut m = Match::new_next_paddles(params(), LOADOUTS, kinds, 1);
    m.serve_timer = 0;
    let n = m.next.as_mut().unwrap();
    n.spawn_timer = u32::MAX;
    n.players[owner as usize].reserve = [Some(Bonus::Bullet), None, None];
    let v = fixed::from_f64(1.0 * 60.0 / TICK_HZ as f64);
    m.ball.x = match owner {
        Side::Left => m.params.bullet_zone - fixed::ONE,
        Side::Right => m.params.width - m.params.bullet_zone + fixed::ONE,
    };
    m.ball.y = m.params.height / 2;
    m.ball.vx = if owner == Side::Left { -v } else { v };
    m.ball.vy = v / 3;
    m
}

fn activate(side: Side) -> Input {
    let mut input = Input::default();
    input.players[side as usize].activate = true;
    input
}

/// Tutti e due i giocatori tengono premuto su.
fn both_up(input: &mut Input) {
    for cmd in &mut input.players {
        cmd.direction = 1;
    }
}

#[test]
fn bullet_waits_for_the_ball_in_its_half_then_ramps_until_the_return() {
    let mut m = make([None, None], Side::Left);
    let p = m.params.clone();
    assert_eq!(p.bullet_ramp_ticks, TICK_HZ / 4);
    assert_eq!((p.bullet_shift, p.bullet_ramp_shift), (1, 2));
    // palla ancora nella metà avversaria, verso chi lo attiva: resta armato
    assert_eq!(p.bullet_zone, fixed::int(p.width / fixed::ONE / 2));
    m.ball.x = p.bullet_zone + fixed::int(5);
    let events = m.step(&activate(Side::Left));
    assert!(events.has(Event::Activate));
    let n = m.next.as_ref().unwrap();
    assert_eq!((n.bullet, n.bullet_on), (Some(Side::Left), false));
    assert!(n.players[0].reserve.iter().all(Option::is_none));
    assert_eq!(n.players[0].armed, None, "non è un bonus armato del giocatore");
    assert_eq!(n.bullet_shift(&p), 0, "armato non rallenta");

    // shift di ogni tick fino a ben dopo l'entrata della palla nella metà sinistra
    let mut shifts = Vec::new();
    let mut entered = None;
    for t in 0..TICK_HZ * 8 {
        m.step(&Input::default());
        let n = m.next.as_ref().unwrap();
        if entered.is_none() && n.bullet_on {
            entered = Some(t as usize);
            assert!(m.ball.x < p.bullet_zone + fixed::ONE, "scatta con la palla nella sua metà");
        }
        shifts.push(n.bullet_shift(&p));
    }
    let e = entered.expect("la palla entra nella metà sinistra");
    let r = p.bullet_ramp_ticks as usize;
    assert!(e > 0 && shifts[..e].iter().all(|&k| k == 0));
    assert!(shifts[e..e + r].iter().all(|&k| k == 2));
    assert!(shifts[e + r..].iter().all(|&k| k == 1), "nessuna durata: resta fino alla ribattuta");

    // la palla torna indietro (ribattuta): finisce al tick dopo
    m.ball.vx = -m.ball.vx;
    m.step(&Input::default());
    let n = m.next.as_ref().unwrap();
    assert_eq!((n.bullet, n.bullet_on, n.bullet_timer), (None, false, 0));
}

#[test]
fn ball_paddle_capsules_and_shots_slow_down_but_not_the_owner() {
    let kinds = [Some(PaddleKind::Blaster), Some(PaddleKind::Blaster)];
    let mut m = make(kinds, Side::Left);
    // riferimento: la stessa partita senza BULLET
    let mut plain = m.clone();
    plain.next.as_mut().unwrap().players[0].reserve = [None; 3];
    let p = m.params.clone();
    for g in [&mut m, &mut plain] {
        let n = g.next.as_mut().unwrap();
        let cap = Capsule {
            x: p.width / 2,
            y: p.height / 3,
            vx: p.capsule_speed,
            vy: p.capsule_drift,
            bonus: Bonus::Ghost,
        };
        n.capsules[0] = Some(cap);
        for side in Side::BOTH {
            let pad = &g.paddles[side as usize];
            let (x, vx) = match side {
                Side::Left => (pad.right(), p.blaster_shot_speed),
                Side::Right => (pad.left(), -p.blaster_shot_speed),
            };
            // colpi lontani dalle capsule e dalle racchette
            n.players[side as usize].shots[0] = Some(Shot {
                x,
                y: p.height - p.height / 8,
                vx,
            });
        }
    }
    let ball_v = (m.ball.vx, m.ball.vy);
    for t in 0..TICK_HZ {
        let mut input = if t == 0 { activate(Side::Left) } else { Input::default() };
        both_up(&mut input);
        let before = m.clone();
        let events = m.step(&input);
        plain.step(&{
            let mut i = Input::default();
            both_up(&mut i);
            i
        });
        if t == 0 {
            assert!(events.has(Event::Activate));
        }
        let n = m.next.as_ref().unwrap();
        let k = n.bullet_shift(&p);
        assert!(k > 0);
        // la racchetta di chi lo ha attivato va come senza BULLET, quella avversaria rallenta
        assert_eq!(m.paddles[0].y, plain.paddles[0].y, "tick {t}");
        let pad = &m.paddles[1];
        if pad.y < p.height - pad.height / 2 {
            assert_eq!(pad.y - before.paddles[1].y, slowed(pad.speed, k), "tick {t}");
        }
        if t == TICK_HZ / 4 {
            assert!(m.paddles[1].y < plain.paddles[1].y, "l'avversario resta indietro");
        }
        // palla: passo rallentato, velocità memorizzata invariata
        assert_eq!((m.ball.vx, m.ball.vy), ball_v);
        assert_eq!(m.ball.dx, slowed(mul(ball_v.0, m.ball.boost), k));
        assert_eq!(m.ball.y - before.ball.y, slowed(ball_v.1, k));
        // capsula e colpi: rallentano la capsula e il colpo dell'avversario, non quello di chi lo usa
        if let (Some(c), Some(c0)) = (n.capsules[0], before.next.as_ref().unwrap().capsules[0]) {
            assert_eq!(c.x - c0.x, slowed(c.vx, k));
            assert_eq!(c.y - c0.y, slowed(c.vy, k));
        }
        let shot = |g: &Match, side: usize| g.next.as_ref().unwrap().players[side].shots[0];
        if let (Some(s), Some(s0)) = (shot(&m, 0), shot(&before, 0)) {
            assert_eq!(s.x - s0.x, s.vx, "colpo di chi ha il BULLET a piena velocità");
        }
        if let (Some(s), Some(s0)) = (shot(&m, 1), shot(&before, 1)) {
            assert_eq!(s.x - s0.x, slowed(s.vx, k), "colpo avversario rallentato");
        }
    }
}

#[test]
fn speeds_are_unchanged_after_the_bullet() {
    let mut m = make([None, None], Side::Left);
    let v = (m.ball.vx, m.ball.vy);
    m.step(&activate(Side::Left));
    for _ in 0..TICK_HZ {
        m.step(&Input::default());
    }
    assert!(m.next.as_ref().unwrap().bullet_on);
    m.ball.vx = -m.ball.vx; // come una ribattuta
    m.step(&Input::default());
    assert_eq!(m.next.as_ref().unwrap().bullet, None);
    assert_eq!((m.ball.vx, m.ball.vy), (-v.0, v.1));
    assert_eq!(m.ball.dx, mul(-v.0, m.ball.boost), "di nuovo a piena velocità");
}

#[test]
fn the_return_ends_the_bullet_a_point_too() {
    let mut m = make([None, None], Side::Left);
    // palla vicina alla racchetta sinistra, che la ribatte durante il BULLET
    m.ball.x = m.paddles[0].right() + fixed::int(20);
    m.ball.y = m.paddles[0].y;
    m.ball.vy = 0;
    m.step(&activate(Side::Left));
    assert!(m.next.as_ref().unwrap().bullet_on);
    let mut hit = false;
    for _ in 0..TICK_HZ * 4 {
        hit |= m.step(&Input::default()).has(Event::Hit);
        if m.ball.vx > 0 {
            break;
        }
    }
    assert!(hit && m.ball.vx > 0);
    m.step(&Input::default());
    assert_eq!(m.next.as_ref().unwrap().bullet, None, "la ribattuta lo chiude");

    // palla che passa la racchetta sinistra: punto, e il BULLET in corso finisce
    let mut m = make([None, None], Side::Left);
    m.ball.x = fixed::int(10);
    m.ball.y = m.paddles[0].y + m.paddles[0].height;
    m.step(&activate(Side::Left));
    assert!(m.next.as_ref().unwrap().bullet_on);
    let mut scored = false;
    for _ in 0..TICK_HZ * 4 {
        scored |= m.step(&Input::default()).has(Event::Score);
        if scored {
            break;
        }
    }
    assert!(scored);
    let n = m.next.as_ref().unwrap();
    assert_eq!((n.bullet, n.bullet_on, n.bullet_timer), (None, false, 0));
}

#[test]
fn a_point_before_the_trigger_keeps_it_armed() {
    // il BULLET di sinistra è armato mentre la palla va a fare punto a destra
    let mut m = make([None, None], Side::Left);
    m.ball.vx = -m.ball.vx;
    m.ball.x = m.params.width - fixed::int(10);
    m.ball.y = m.paddles[1].y + m.paddles[1].height;
    m.step(&activate(Side::Left));
    assert_eq!(m.next.as_ref().unwrap().bullet, Some(Side::Left));
    let mut scored = false;
    for _ in 0..TICK_HZ * 4 {
        scored |= m.step(&Input::default()).has(Event::Score);
        if scored {
            break;
        }
    }
    assert!(scored);
    let n = m.next.as_ref().unwrap();
    assert_eq!((n.bullet, n.bullet_on), (Some(Side::Left), false), "ancora armato");
}

#[test]
fn one_bullet_at_a_time() {
    let mut m = make([None, None], Side::Left);
    m.next.as_mut().unwrap().players[1].reserve = [Some(Bonus::Bullet), Some(Bonus::Smash), None];
    m.step(&activate(Side::Left));
    // l'avversario non può attivare il suo: resta in riserva, senza pausa
    let events = m.step(&activate(Side::Right));
    assert!(!events.has(Event::Activate));
    let pl = &m.next.as_ref().unwrap().players[1];
    assert_eq!(pl.reserve, [Some(Bonus::Bullet), Some(Bonus::Smash), None]);
    assert_eq!(pl.cooldown, 0);
    // un altro bonus sì
    let mut input = activate(Side::Right);
    input.players[1].select = true;
    assert!(m.step(&input).has(Event::Activate));
    assert_eq!(m.next.as_ref().unwrap().players[1].armed, Some(Bonus::Smash));
}

#[test]
fn the_opponents_knob_is_slowed_too() {
    let mut m = make([None, None], Side::Left);
    let p = m.params.clone();
    m.step(&activate(Side::Left));
    let mut input = Input::default();
    input.players[1] = PlayerInput {
        top_offset: Some(0), // manopola tutta in alto
        ..PlayerInput::default()
    };
    let y = m.paddles[1].y;
    m.step(&input);
    let k = m.next.as_ref().unwrap().bullet_shift(&p);
    assert_eq!(m.paddles[1].y - y, slowed(p.encoder_hand_step, k));
}

#[test]
fn curve_keeps_its_shape_in_bullet_time() {
    let mut m = make([None, None], Side::Left);
    let p = m.params.clone();
    m.next.as_mut().unwrap().curve = p.curve_accel;
    m.ball.vy = 0;
    m.step(&activate(Side::Left));
    let k = m.next.as_ref().unwrap().bullet_shift(&p);
    assert_eq!(
        m.ball.vy,
        slowed(p.curve_accel, k),
        "accelerazione rallentata come il passo"
    );
}

#[test]
fn bullet_odds_one_capsule_in_sixteen_super_unchanged() {
    let p = params();
    assert_eq!((p.super_cut, p.bullet_cut), (8192, 12288));
    // stesso SUPER di `below(super_odds) == 0`, per qualunque super_odds
    for odds in [1u32, 3, 7, 8, 10, 16, 100] {
        let cut = 65535 / odds + 1;
        let (mut a, mut b) = (Rng::new(odds), Rng::new(odds));
        for _ in 0..20_000 {
            assert_eq!(a.below(odds) == 0, b.bits16() < cut, "super_odds {odds}");
        }
    }
    // in partita: circa 1 su 8 SUPER e 1 su 16 BULLET
    let mut m = Match::new_next(p.clone(), LOADOUTS, 5);
    let mut counts = [0u32; Bonus::COUNT];
    let mut total = 0;
    for _ in 0..TICK_HZ * 3600 {
        let before = m.next.as_ref().unwrap().spawned;
        m.step(&Input::default());
        let n = m.next.as_mut().unwrap();
        if n.spawned > before {
            // la capsula nuova è l'unica in volo
            let c = n.capsules.iter().flatten().next().unwrap();
            counts[c.bonus as usize] += 1;
            total += 1;
            n.capsules = [None; 4]; // così c'è sempre un posto libero
        }
    }
    let share = |b: Bonus| counts[b as usize] as f64 / total as f64;
    assert!(total > 600, "capsule: {total}");
    assert!(
        (share(Bonus::Super) - 1.0 / 8.0).abs() < 0.03,
        "SUPER {:.3}",
        share(Bonus::Super)
    );
    assert!(
        (share(Bonus::Bullet) - 1.0 / 16.0).abs() < 0.02,
        "BULLET {:.3}",
        share(Bonus::Bullet)
    );
    // senza BULLET (bullet_odds = 0) non ne arriva nessuno
    let mut t = Tuning::default();
    t.next.bullet_odds = 0;
    let q = Params::new(&t);
    assert_eq!(q.bullet_cut, q.super_cut);
}

#[test]
fn c64_bullet_parameters() {
    let p = Params::new(&Tuning::c64());
    assert_eq!(p.bullet_ramp_ticks, 13);
}

#[test]
fn cpu_uses_the_bullet_at_once_for_a_ball_it_would_miss() {
    // la CPU destra ha solo il BULLET; la palla veloce arriva lontano dalla racchetta: in
    // emergenza lo attiva subito (probabilità 16 volte più alta), altrimenti come un bonus normale
    let p = params();
    let setup = |far: bool| {
        let mut m = make([None, None], Side::Right);
        m.paddles[1].y = p.height / 4;
        let pad = &m.paddles[1];
        m.ball.vx = p.max_ball_speed_next;
        m.ball.vy = 0;
        m.ball.dx = m.ball.vx;
        m.ball.x = pad.left() - fixed::int(60);
        m.ball.y = if far { p.height - fixed::int(30) } else { pad.y };
        m
    };
    for far in [true] {
        let mut used = false;
        let mut m = setup(far);
        let mut cpu = Cpu::new(&m.params, 3, Side::Right, 9);
        // la CPU vede la palla in arrivo dopo il tempo di reazione: si parte con la palla lontana
        let x = m.ball.x;
        m.ball.x = m.params.width / 2;
        for _ in 0..TICK_HZ {
            cpu.input(&m);
        }
        m.ball.x = x;
        for _ in 0..60 {
            let mut input = Input::default();
            input.players[1] = cpu.input(&m);
            used |= m.step(&input).has(Event::Activate);
            if m.next.as_ref().unwrap().bullet.is_some() {
                break;
            }
            m.ball.x = x; // la palla resta a tiro
        }
        assert!(used, "palla lontana dalla racchetta: BULLET non usato");
    }
}

#[test]
fn cpu_with_a_reserve_full_of_bullets_still_uses_them() {
    // prima la CPU, con il BULLET selezionato fuori da un'emergenza, passava al bonus successivo:
    // con la riserva piena di BULLET non usava più niente
    let params = params();
    let mut m = Match::new_next(params, LOADOUTS, 3);
    m.next.as_mut().unwrap().players[1].reserve = [Some(Bonus::Bullet); 3];
    let mut cpus = [Cpu::new(&m.params, 1, Side::Left, 4), Cpu::new(&m.params, 1, Side::Right, 5)];
    let mut used = 0;
    for _ in 0..TICK_HZ * 60 {
        let mut input = Input::default();
        for cpu in &mut cpus {
            input.players[cpu.side() as usize] = cpu.input(&m);
        }
        let before = m.next.as_ref().unwrap().players[1].count();
        m.step(&input);
        used += (m.next.as_ref().unwrap().players[1].count() < before) as u32;
    }
    assert!(used >= 2, "BULLET usati in un minuto: {used}");
}
