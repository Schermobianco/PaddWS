use paddws_core::challenge::{
    BOOST_POINTS, Entry, HIT_POINTS, LEVELS, POINT_POINTS, RUNGS, Score, TABLE_SIZE, Table, WIN_POINTS,
};
use paddws_core::{Event, Input, Match, PaddleKind, Params, Side, Tuning};

#[test]
fn every_level_has_a_different_paddle() {
    for (i, a) in RUNGS.iter().enumerate() {
        for b in &RUNGS[i + 1..] {
            assert_ne!(a.kind, b.kind);
        }
    }
    assert_eq!(RUNGS.len(), LEVELS);
    assert_eq!(LEVELS, PaddleKind::COUNT);
    // la difficoltà non scende mai
    for w in RUNGS.windows(2) {
        assert!(w[1].cpu + w[1].speed > w[0].cpu + w[0].speed);
    }
}

#[test]
fn hits_count_with_the_rally_multiplier() {
    let params = Params::new(&Tuning::default());
    let mut m = Match::new_next(params, [RUNGS[0].loadout; 2], 1);
    let mut score = Score::new(Side::Left);
    let mut events = paddws_core::Events::default();
    events.add(Event::Hit);
    // colpo del giocatore sinistro: la palla va a destra
    m.ball.vx = 1 << 16;
    assert_eq!(score.on_tick(&m, m.score, events), HIT_POINTS);
    // colpo della CPU: niente punti, ma lo scambio si allunga
    m.ball.vx = -(1 << 16);
    for _ in 0..6 {
        score.on_tick(&m, m.score, events);
    }
    assert_eq!(score.rally, 7);
    m.ball.vx = 1 << 16;
    let mut boost = paddws_core::Events::default();
    boost.add(Event::Boost);
    // ottavo colpo: moltiplicatore 3 (sale ogni 4 colpi)
    assert_eq!(score.on_tick(&m, m.score, boost), HIT_POINTS * 3 + BOOST_POINTS);
    // punto del giocatore: moltiplicatore dello scambio, poi lo scambio riparte
    let before = m.score;
    m.score[0] += 1;
    let mut point = paddws_core::Events::default();
    point.add(Event::Score);
    assert_eq!(score.on_tick(&m, before, point), POINT_POINTS * 3);
    assert_eq!(score.rally, 0);
    assert_eq!(
        score.total,
        HIT_POINTS + HIT_POINTS * 3 + BOOST_POINTS + POINT_POINTS * 3
    );
}

#[test]
fn table_keeps_the_best_ten() {
    let mut t = Table::default();
    assert!(t.entries.windows(2).all(|w| w[0].score >= w[1].score));
    assert_eq!(t.rank(0), None);
    let low = t.entries[TABLE_SIZE - 1].score;
    // a parità di punti il nuovo va sotto: non entra
    assert_eq!(t.rank(low), None);
    let e = Entry {
        name: *b"ABC",
        score: t.entries[0].score + 1,
        level: 3,
    };
    assert_eq!(t.insert(e), Some(0));
    assert_eq!(t.entries[0], e);
    assert_eq!(t.entries[TABLE_SIZE - 1].score, 2 * low);
}

#[test]
fn a_short_match_ends_at_the_rung_points() {
    // partita CHALLENGE completa giocata da due CPU: finisce, e i punti arcade crescono
    let rung = RUNGS[0];
    let params = Params::new(&Tuning {
        difficulty: rung.speed,
        ..Tuning::default()
    });
    let mut m = Match::new_next_paddles(
        params.clone(),
        [RUNGS[1].loadout, rung.loadout],
        [None, Some(rung.kind)],
        7,
    );
    let mut cpus = [
        paddws_core::Cpu::new(&params, 3, Side::Left, 7),
        paddws_core::Cpu::new(&params, rung.cpu, Side::Right, 8),
    ];
    let mut score = Score::new(Side::Left);
    for _ in 0..paddws_core::TICK_HZ * 60 * 20 {
        let mut input = Input::default();
        for c in &mut cpus {
            input.players[c.side() as usize] = c.input(&m);
        }
        let before = m.score;
        let events = m.step(&input);
        score.on_tick(&m, before, events);
        if m.score.iter().any(|&s| s >= rung.points) {
            break;
        }
    }
    assert!(m.score.iter().any(|&s| s >= rung.points));
    assert!(score.total >= m.score[0] as u32 * POINT_POINTS);
}

#[test]
fn the_duel_winner_keeps_going_with_the_bonus() {
    // il premio della sfida vale quanto la vittoria del livello
    for level in 0..LEVELS {
        assert_eq!(Score::duel_bonus(level), Score::win_bonus(level, 1).0);
    }
    assert_eq!(Score::duel_bonus(2), 3 * WIN_POINTS);
    // il campione tiene il suo punteggio, lo sfidante parte da 0
    assert_eq!(Score::after_duel(12_345, true, 2), 12_345 + 3 * WIN_POINTS);
    assert_eq!(Score::after_duel(12_345, false, 2), 3 * WIN_POINTS);
    assert_eq!(Score::after_duel(u32::MAX, true, 6), u32::MAX);
}

#[test]
fn the_cpu_takes_the_other_side() {
    let rung = RUNGS[3];
    let mine = RUNGS[0].loadout;
    let kind = Some(PaddleKind::Rush);
    assert_eq!(
        rung.sides(Side::Left, mine, kind),
        ([mine, rung.loadout], [kind, Some(rung.kind)])
    );
    assert_eq!(
        rung.sides(Side::Right, mine, kind),
        ([rung.loadout, mine], [Some(rung.kind), kind])
    );
}

#[test]
fn a_human_on_the_right_scores_on_the_right() {
    // il campione a destra: i suoi colpi mandano la palla a sinistra
    let params = Params::new(&Tuning::default());
    let rung = RUNGS[0];
    let (loadouts, kinds) = rung.sides(Side::Right, RUNGS[1].loadout, None);
    let mut m = Match::new_next_paddles(params, loadouts, kinds, 3);
    let mut score = Score::new(Side::Right);
    let mut hit = paddws_core::Events::default();
    hit.add(Event::Hit);
    m.ball.vx = -(1 << 16);
    assert_eq!(score.on_tick(&m, m.score, hit), HIT_POINTS);
    m.ball.vx = 1 << 16;
    assert_eq!(score.on_tick(&m, m.score, hit), 0);
    let before = m.score;
    m.score[1] += 1;
    let mut point = paddws_core::Events::default();
    point.add(Event::Score);
    assert_eq!(score.on_tick(&m, before, point), POINT_POINTS);
}
