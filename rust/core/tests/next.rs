use paddws_core::fixed::{self, ONE};
use paddws_core::{
    Bonus, Capsule, Event, Fx, GUARDIAN_SECTORS, GUARDIAN_WALL, Input, Match, PaddleKind, Params, PlayerInput, Side,
    SuperAnim, TICK_HZ, Tuning, guardian_sector,
};

const LOADOUTS: [[Bonus; 3]; 2] = [
    [Bonus::Smash, Bonus::Teleport, Bonus::Curve],
    [Bonus::Slow, Bonus::Ghost, Bonus::Smash],
];

fn make() -> Match {
    let params = Params::new(&Tuning {
        serve_delay: 0.0,
        ..Tuning::default()
    });
    Match::new_next(params, LOADOUTS, 1)
}

fn idle(m: &mut Match, ticks: u32) -> Vec<Event> {
    (0..ticks)
        .flat_map(|_| m.step(&Input::default()).iter().collect::<Vec<_>>())
        .collect()
}

fn press(m: &mut Match, side: Side, select: bool, activate: bool) -> Vec<Event> {
    let mut input = Input::default();
    input.players[side as usize] = PlayerInput {
        select,
        activate,
        ..Default::default()
    };
    m.step(&input).iter().collect()
}

/// Palla verso la racchetta di `side`, ferma al centro in altezza.
fn aim_at_paddle(m: &mut Match, side: Side) {
    let (w, h) = (m.params.width, m.params.height);
    m.paddles[side as usize].y = h / 2;
    m.ball.x = w / 2;
    m.ball.y = h / 2;
    let vx = fixed::from_f64(3.0 * 60.0 / TICK_HZ as f64);
    m.ball.vx = if side == Side::Left { -vx } else { vx };
    m.ball.vy = 0;
}

#[test]
fn capsule_is_collected_by_touching_it() {
    let mut m = make();
    let n = m.next.as_mut().unwrap();
    n.spawn_timer = u32::MAX; // niente capsule casuali
    let pad = &m.paddles[0];
    n.capsules[0] = Some(Capsule {
        x: pad.x + fixed::int(40),
        y: pad.y,
        vx: -m.params.capsule_speed,
        vy: 0,
        bonus: Bonus::Curve,
    });
    m.ball.vx = fixed::int(1); // la palla va dall'altra parte
    let events = idle(&mut m, TICK_HZ * 2);
    assert!(events.contains(&Event::Collect));
    let pl = &m.next.as_ref().unwrap().players[0];
    assert_eq!(pl.reserve, [Some(Bonus::Curve), None, None]);
}

/// Scatto di `side` (avanti o indietro) in un tick, senza altri comandi.
fn dash(m: &mut Match, side: Side) -> Vec<Event> {
    let mut input = Input::default();
    input.players[side as usize] = PlayerInput {
        forward: true,
        ..Default::default()
    };
    m.step(&input).iter().collect()
}

#[test]
fn dash_collects_the_capsules_it_jumps_over() {
    for back in [false, true] {
        let mut m = make();
        m.ball.vx = fixed::int(1); // la palla va dall'altra parte
        if back {
            dash(&mut m, Side::Left); // prima avanti, senza capsule
        }
        let n = m.next.as_mut().unwrap();
        n.spawn_timer = u32::MAX; // niente capsule casuali
        let pad = &m.paddles[0];
        // a metà del tratto dello scatto, che la racchetta salta in un tick
        n.capsules[0] = Some(Capsule {
            x: (pad.home_x + pad.fwd_x) / 2,
            y: pad.y,
            vx: -m.params.capsule_speed,
            vy: 0,
            bonus: Bonus::Curve,
        });
        let events = dash(&mut m, Side::Left);
        assert!(events.contains(&Event::Collect), "ritorno {back}");
        assert_eq!(m.paddles[0].x, if back { m.paddles[0].home_x } else { m.paddles[0].fwd_x });
        let n = m.next.as_ref().unwrap();
        assert_eq!(n.players[0].reserve, [Some(Bonus::Curve), None, None]);
        assert!(n.capsules[0].is_none());
    }
}

#[test]
fn dash_does_not_collect_capsules_going_to_the_opponent() {
    let mut m = make();
    m.ball.vx = fixed::int(1);
    let n = m.next.as_mut().unwrap();
    n.spawn_timer = u32::MAX;
    let pad = &m.paddles[0];
    n.capsules[0] = Some(Capsule {
        x: (pad.home_x + pad.fwd_x) / 2,
        y: pad.y,
        vx: m.params.capsule_speed, // verso destra
        vy: 0,
        bonus: Bonus::Curve,
    });
    let events = dash(&mut m, Side::Left);
    assert!(!events.contains(&Event::Collect));
    assert!(m.next.as_ref().unwrap().capsules[0].is_some());
}

#[test]
fn capsules_carry_the_receivers_bonuses() {
    let mut m = make();
    let mut seen = 0;
    for _ in 0..TICK_HZ * 120 {
        m.step(&Input::default());
        for c in m.next.as_ref().unwrap().capsules.iter().flatten() {
            let side = c.toward() as usize;
            assert!(c.bonus.rare() || LOADOUTS[side].contains(&c.bonus), "{c:?}");
            seen += 1;
        }
    }
    assert!(seen > 0);
}

#[test]
fn smash_lasts_one_shot() {
    let mut m = make();
    let n = m.next.as_mut().unwrap();
    n.spawn_timer = u32::MAX;
    n.players[0].reserve = [Some(Bonus::Smash), None, None];
    let events = press(&mut m, Side::Left, false, true);
    assert!(events.contains(&Event::Activate));
    assert_eq!(m.next.as_ref().unwrap().players[0].armed, Some(Bonus::Smash));

    aim_at_paddle(&mut m, Side::Left);
    idle(&mut m, TICK_HZ * 2);
    assert!(m.ball.vx > 0);
    assert_eq!(m.ball.boost, m.params.smash_mul);
    assert_eq!(m.next.as_ref().unwrap().players[0].armed, None);

    // la schiacciata è angolata: va lontano dalla racchetta avversaria
    assert_ne!(m.ball.vy, 0);
    // l'avversario la insegue e la ribatte: si torna alla velocità normale
    let mut hit = false;
    for _ in 0..TICK_HZ * 2 {
        m.paddles[1].y = m.ball.y;
        if m.step(&Input::default()).has(Event::Hit) {
            hit = true;
            break;
        }
    }
    assert!(hit);
    assert_eq!(m.ball.boost, ONE);
}

#[test]
fn one_bonus_at_a_time_with_cooldown() {
    let mut m = make();
    let n = m.next.as_mut().unwrap();
    n.players[0].reserve = [Some(Bonus::Slow), Some(Bonus::Smash), None];
    m.serve_timer = 0;
    assert!(press(&mut m, Side::Left, false, true).contains(&Event::Activate));
    assert!(m.next.as_ref().unwrap().slow_timer > 0);
    // subito dopo non si può: pausa tra due attivazioni
    assert!(!press(&mut m, Side::Left, false, true).contains(&Event::Activate));
    assert_eq!(
        m.next.as_ref().unwrap().players[0].reserve,
        [Some(Bonus::Smash), None, None]
    );
}

#[test]
fn slow_lasts_until_its_owner_hits_the_ball_then_the_speed_comes_back() {
    let mut m = make();
    m.next.as_mut().unwrap().spawn_timer = u32::MAX;
    m.serve_timer = 0;
    // palla veloce verso il giocatore destro, che usa SLOW
    aim_at_paddle(&mut m, Side::Right);
    m.ball.vx *= 2;
    let fast = m.ball.vx;
    m.next.as_mut().unwrap().players[1].reserve = [Some(Bonus::Slow), None, None];
    assert!(press(&mut m, Side::Right, false, true).contains(&Event::Activate));
    assert_eq!(m.next.as_ref().unwrap().slow, Some(Side::Right));
    assert!(m.ball.vx < fast, "rallentata");
    let slowed = m.ball.vx;
    // l'alone resta finché la palla è lenta, e la palla non accelera da sola
    idle(&mut m, TICK_HZ / 4);
    let n = m.next.as_ref().unwrap();
    assert_eq!(n.slow_timer, m.params.slow_ticks);
    assert_eq!(m.ball.vx, slowed);
    // al colpo di chi l'ha usato riparte alla velocità di prima (più l'accelerazione del colpo)
    let mut hit = false;
    for _ in 0..TICK_HZ * 4 {
        m.paddles[1].y = m.ball.y;
        if m.step(&Input::default()).has(Event::Hit) {
            hit = true;
            break;
        }
    }
    assert!(hit);
    let n = m.next.as_ref().unwrap();
    assert_eq!((n.slow, n.slow_timer), (None, 0));
    assert!(m.ball.vx < 0);
    let expected = fixed::mul(fixed::mul(-slowed, m.kspeed()), m.params.slow_back);
    assert!((m.ball.vx - expected).abs() <= 2, "{} invece di {expected}", m.ball.vx);
    assert!(-m.ball.vx > fast, "più veloce di prima del rallentamento");
}

#[test]
fn select_cycles_through_the_reserve() {
    let mut m = make();
    let n = m.next.as_mut().unwrap();
    n.players[1].reserve = [Some(Bonus::Slow), Some(Bonus::Ghost), Some(Bonus::Teleport)];
    for expected in [1, 2, 0] {
        press(&mut m, Side::Right, true, false);
        assert_eq!(m.next.as_ref().unwrap().players[1].selected, expected);
    }
}

#[test]
fn hit_stop_freezes_the_game() {
    let mut m = make();
    let n = m.next.as_mut().unwrap();
    n.spawn_timer = u32::MAX;
    n.players[0].armed = Some(Bonus::Super);
    n.players[0].super_anim = SuperAnim::HitStop;
    aim_at_paddle(&mut m, Side::Left);
    let mut ticks = 0;
    while !m.step(&Input::default()).has(Event::Super) {
        ticks += 1;
        assert!(ticks < TICK_HZ * 3);
    }
    let x = m.ball.x;
    let frozen = m.params.hitstop_ticks;
    idle(&mut m, frozen);
    assert_eq!(m.ball.x, x); // fermo
    idle(&mut m, 2);
    assert!(m.ball.x > x);
    assert_eq!(m.ball.boost, m.params.super_mul);
}

#[test]
fn next_matches_are_reproducible() {
    let run = || {
        let mut m = make();
        for t in 0..TICK_HZ * 60u32 {
            let mut input = Input::default();
            input.players[0].direction = if (t / 200) % 2 == 0 { 1 } else { -1 };
            input.players[1].activate = t % 500 == 0;
            input.players[0].activate = t % 700 == 0;
            m.step(&input);
        }
        m
    };
    assert_eq!(run(), run());
}

#[test]
fn teleport_jumps_at_the_centre_line_and_returns_the_ball() {
    let mut m = make();
    let (w, h) = (m.params.width, m.params.height);
    let n = m.next.as_mut().unwrap();
    n.spawn_timer = u32::MAX;
    n.players[0].armed = Some(Bonus::Teleport);
    // palla veloce dalla destra verso l'alto, racchetta sinistra in basso
    m.paddles[0].y = m.paddles[0].height / 2;
    m.ball.x = w * 3 / 4;
    m.ball.y = h * 3 / 4;
    m.ball.vx = -fixed::from_f64(20.0 * 60.0 / TICK_HZ as f64);
    m.ball.vy = fixed::from_f64(2.0 * 60.0 / TICK_HZ as f64);
    let start_y = m.paddles[0].y;
    let mut jumps = 0;
    while m.ball.vx < 0 {
        let past_half = m.ball.x < w / 2;
        let events: Vec<Event> = m.step(&Input::default()).iter().collect();
        jumps += events.iter().filter(|&&e| e == Event::Teleport).count();
        assert!(!events.contains(&Event::Score), "palla persa con TELEPORT");
        if !past_half {
            assert_eq!(m.paddles[0].y, start_y, "salto prima della metà campo");
        }
    }
    assert_eq!(jumps, 1);
    assert_eq!(m.next.as_ref().unwrap().players[0].armed, None);
}

#[test]
fn steer_guides_the_ball_until_three_quarters_with_the_paddle_still() {
    let mut m = make();
    let w = m.params.width;
    let n = m.next.as_mut().unwrap();
    n.spawn_timer = u32::MAX;
    n.players[0].armed = Some(Bonus::Steer);
    aim_at_paddle(&mut m, Side::Left);
    // la palla arriva dritta: dopo il colpo si tiene premuto su
    let mut up = Input::default();
    up.players[0].direction = 1;
    while !m.step(&Input::default()).has(Event::Hit) {}
    assert_eq!(m.next.as_ref().unwrap().steer, Some(Side::Left));
    let (pad_y, vy) = (m.paddles[0].y, m.ball.vy);
    let mut steered = false;
    while m.ball.x < w - w / 4 {
        m.step(&up);
        assert_eq!(m.paddles[0].y, pad_y, "racchetta mossa durante la guida");
        steered |= m.ball.vy != vy;
        // mai più ripida del doppio della velocità orizzontale
        assert!(m.ball.vy.abs() <= m.ball.vx.abs() * 2);
    }
    assert!(steered);
    // passati i 3/4 la guida finisce: la palla va dritta e la racchetta si muove di nuovo
    m.step(&up);
    assert_eq!(m.next.as_ref().unwrap().steer, None);
    let vy = m.ball.vy;
    idle(&mut m, 4);
    assert!(m.ball.vy == vy || m.ball.vy == -vy, "sterzata dopo i 3/4");
    m.step(&up);
    m.step(&up);
    assert!(m.paddles[0].y > pad_y);
}

#[test]
fn steer_ends_when_the_opponent_returns_the_ball() {
    let mut m = make();
    let n = m.next.as_mut().unwrap();
    n.spawn_timer = u32::MAX;
    n.players[0].armed = Some(Bonus::Steer);
    aim_at_paddle(&mut m, Side::Left);
    while !m.step(&Input::default()).has(Event::Hit) {}
    assert!(m.next.as_ref().unwrap().steer.is_some());
    let mut hit = false;
    for _ in 0..TICK_HZ * 4 {
        m.paddles[1].y = m.ball.y;
        if m.step(&Input::default()).has(Event::Hit) {
            hit = true;
            break;
        }
    }
    assert!(hit);
    assert_eq!(m.next.as_ref().unwrap().steer, None);
}

fn make_kinds(kinds: [Option<PaddleKind>; 2]) -> Match {
    let params = Params::new(&Tuning {
        serve_delay: 0.0,
        ..Tuning::default()
    });
    Match::new_next_paddles(params, LOADOUTS, kinds, 1)
}

#[test]
fn kinds_change_height_speed_and_dash() {
    let plain = make();
    // ARCADE: più capsule, pagate con una racchetta un po' più corta (stessa velocità)
    let arcade = make_kinds([Some(PaddleKind::Arcade); 2]);
    assert!(arcade.paddles[0].height < plain.paddles[0].height);
    assert_eq!(arcade.paddles[0].max_speed, plain.paddles[0].max_speed);
    let titan = make_kinds([Some(PaddleKind::Titan), None]);
    assert!(titan.paddles[0].height > plain.paddles[0].height);
    assert!(titan.paddles[0].max_speed < plain.paddles[0].max_speed);
    let rush = make_kinds([None, Some(PaddleKind::Rush)]);
    // scatto più lungo: la racchetta destra avanza di più verso il centro
    assert!(rush.paddles[1].fwd_x < plain.paddles[1].fwd_x);
}

#[test]
fn blaster_shot_steals_a_capsule_heading_to_the_opponent() {
    let mut m = make_kinds([Some(PaddleKind::Blaster), None]);
    let n = m.next.as_mut().unwrap();
    n.spawn_timer = u32::MAX;
    let y = m.paddles[0].y;
    n.capsules[0] = Some(Capsule {
        x: m.params.width / 2,
        y,
        vx: m.params.capsule_speed, // verso il giocatore destro
        vy: 0,
        bonus: Bonus::Ghost,
    });
    m.ball.vx = -fixed::int(1);
    m.ball.x = m.params.width - fixed::int(100);
    let mut input = Input::default();
    input.players[0].fire = true;
    assert!(m.step(&input).has(Event::Fire));
    assert!(m.paddles[0].at_home(), "sparare non fa scattare la racchetta");
    // subito dopo non si spara: pausa tra due colpi
    assert!(!m.step(&input).has(Event::Fire));
    let events = idle(&mut m, TICK_HZ);
    assert!(events.contains(&Event::Collect));
    let pl = &m.next.as_ref().unwrap().players[0];
    assert_eq!(pl.reserve, [Some(Bonus::Ghost), None, None]);
    assert!(pl.shots.iter().all(Option::is_none));
}

#[test]
fn blaster_fires_four_shots_in_a_row_then_reloads() {
    let mut m = make_kinds([Some(PaddleKind::Blaster), None]);
    m.next.as_mut().unwrap().spawn_timer = u32::MAX;
    m.ball.vx = -fixed::int(1);
    m.ball.x = m.params.width - fixed::int(100);
    let mut fire = Input::default();
    fire.players[0].fire = true;
    let gap = m.params.blaster_gap_ticks;
    let mut shots = 0;
    for _ in 0..5 * (gap + 1) {
        shots += m.step(&fire).has(Event::Fire) as u32;
    }
    assert_eq!(m.params.blaster_shots, 4);
    assert_eq!(shots, 4, "quattro colpi di fila, poi il caricatore è vuoto");
    let pl = &m.next.as_ref().unwrap().players[0];
    assert_eq!(pl.ammo, 0);
    assert!(
        pl.shots.iter().filter(|s| s.is_some()).count() >= 2,
        "più colpi in volo insieme"
    );
    // il caricatore torna pieno alla fine della ricarica, contata dal primo colpo
    let reload = m.params.blaster_reload_ticks;
    idle(&mut m, reload);
    assert_eq!(m.next.as_ref().unwrap().players[0].ammo, m.params.blaster_shots);
}

#[test]
fn arcade_gets_more_capsules() {
    // capsule partite in 10 minuti verso ciascun lato, a palla ferma lontana dalle racchette
    let count = |kinds| {
        let mut m = make_kinds(kinds);
        let mut toward = [0u32; 2];
        for _ in 0..TICK_HZ * 600 {
            m.serve_timer = 1;
            let before = m.next.as_ref().unwrap().spawned;
            m.step(&Input::default());
            let n = m.next.as_mut().unwrap();
            if n.spawned > before {
                let c = n
                    .capsules
                    .iter()
                    .flatten()
                    .find(|c| (c.x - m.params.width / 2).abs() <= c.vx.abs())
                    .unwrap();
                toward[c.toward() as usize] += 1;
            }
            n.capsules = [None; 4]; // nessun posto pieno
        }
        toward
    };
    let plain = count([None, None]);
    let arcade = count([Some(PaddleKind::Arcade), None]);
    assert!(arcade[0] as f64 > 1.5 * plain[0] as f64, "{arcade:?} contro {plain:?}");
    assert!(
        arcade[1] as f64 > 0.7 * plain[1] as f64,
        "l'avversario ne riceve poche meno: {arcade:?}"
    );
}

#[test]
fn guardian_wall_sector_returns_one_missed_ball_and_is_gone() {
    let mut m = make_kinds([Some(PaddleKind::Guardian), None]);
    m.next.as_mut().unwrap().spawn_timer = u32::MAX;
    assert_eq!(m.next.as_ref().unwrap().players[0].barrier, GUARDIAN_WALL);
    let h = m.params.height;
    // palla verso sinistra all'altezza `y`, lontana dalla racchetta
    let miss = |m: &mut Match, y: Fx| {
        m.paddles[0].y = if y < h / 2 { h - m.paddles[0].height / 2 } else { m.paddles[0].height / 2 };
        m.ball.x = m.params.width / 4;
        m.ball.y = y;
        m.ball.vx = -fixed::int(2);
        m.ball.vy = 0;
    };
    // in alto, nella banda delle riserve: è il primo settore
    let top = h - fixed::int(20);
    miss(&mut m, top);
    let events = idle(&mut m, TICK_HZ);
    assert!(events.contains(&Event::Barrier));
    assert!(!events.contains(&Event::Score));
    assert_eq!(m.next.as_ref().unwrap().players[0].barrier, GUARDIAN_WALL & !1);
    // lo stesso settore non c'è più: punto
    miss(&mut m, top);
    let events = idle(&mut m, TICK_HZ);
    assert!(events.contains(&Event::Score));
    assert_eq!(m.score, [0, 1]);
    // un altro settore rimanda ancora la palla
    let y = m.params.guardian_bounds[3] - fixed::int(5);
    assert_eq!(guardian_sector(&m.params, y), 4);
    miss(&mut m, y);
    m.serve_timer = 0;
    let events = idle(&mut m, TICK_HZ);
    assert!(events.contains(&Event::Barrier), "{events:?}");
    assert_eq!(m.next.as_ref().unwrap().players[0].barrier, GUARDIAN_WALL & !1 & !(1 << 4));
}

#[test]
fn guardian_wall_sectors_split_the_field_below_the_hud_band() {
    for (w, h) in [(800, 480), (320, 240), (320, 200)] {
        let p = Params::new(&Tuning {
            width: w,
            height: h,
            ..Tuning::default()
        });
        // la y cresce verso l'alto: il muro va dal fondo (0) a sotto la banda delle riserve
        let top = p.guardian_top;
        assert_eq!(top, p.height - p.capsule_margin_top);
        let mut edges = vec![top];
        edges.extend(p.guardian_bounds);
        edges.push(0);
        let sizes: Vec<Fx> = edges.windows(2).map(|e| e[0] - e[1]).collect();
        assert!(sizes.iter().all(|&s| (s - sizes[0]).abs() <= fixed::int(1)), "{w}x{h}: {sizes:?}");
        assert!(edges.iter().all(|&e| e & 0xFFFF == 0), "pixel interi");
        assert_eq!(guardian_sector(&p, p.height - 1), 0, "la banda è nel primo settore");
        assert_eq!(guardian_sector(&p, top), 0);
        assert_eq!(guardian_sector(&p, 0), GUARDIAN_SECTORS - 1);
    }
}

#[test]
fn guardian_wall_does_not_come_back_after_points() {
    let mut m = make_kinds([Some(PaddleKind::Guardian), None]);
    m.next.as_mut().unwrap().players[0].barrier = 0;
    for _ in 0..8 {
        m.ball.x = m.params.width - fixed::int(2);
        m.ball.vx = fixed::int(2);
        m.ball.vy = 0;
        m.paddles[1].y = m.params.height - m.paddles[1].height / 2;
        m.ball.y = fixed::int(20);
        assert!(m.step(&Input::default()).has(Event::Score));
        assert_eq!(m.next.as_ref().unwrap().players[0].barrier, 0);
    }
}

#[test]
fn hammer_shot_is_faster_and_leaves_the_opponent_dash() {
    let mut m = make_kinds([Some(PaddleKind::Hammer), None]);
    m.next.as_mut().unwrap().spawn_timer = u32::MAX;
    aim_at_paddle(&mut m, Side::Left);
    idle(&mut m, TICK_HZ * 2);
    assert!(m.ball.vx > 0);
    assert_eq!(m.ball.boost, m.params.hammer_mul);
    // lo scatto dell'avversario potenzia comunque la palla
    let pad = &m.paddles[1];
    m.ball.y = pad.y;
    m.ball.x = pad.left() - fixed::int(40);
    let mut input = Input::default();
    input.players[1].forward = true;
    assert!(m.step(&input).has(Event::Boost));
    assert_eq!(m.ball.boost, m.params.boost_fwd_mul);
}

#[test]
fn slow_paddle_follows_the_encoder_with_a_top_speed() {
    let mut plain = make();
    let mut titan = make_kinds([Some(PaddleKind::Titan), None]);
    let mut input = Input::default();
    input.players[0].top_offset = Some(0); // manopola tutta in alto
    plain.step(&input);
    titan.step(&input);
    let top = |m: &Match| m.params.height - m.paddles[0].height / 2;
    assert_eq!(plain.paddles[0].y, top(&plain), "senza tipo va subito alla manopola");
    assert!(titan.paddles[0].y < top(&titan));
    for _ in 0..TICK_HZ {
        titan.step(&input);
    }
    assert_eq!(titan.paddles[0].y, top(&titan));
}
