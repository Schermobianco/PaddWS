use paddws_core::fixed::{self, Fx};
use paddws_core::{DIFFICULTY_LEVELS, Event, Input, Match, Params, PlayerInput, Side, TICK_HZ, Tuning};

fn params() -> Params {
    Params::new(&Tuning {
        serve_delay: 0.0,
        ..Tuning::default()
    })
}

fn make(players: u8, evo: bool) -> Match {
    Match::new(params(), players, evo, 1)
}

/// Esegue `ticks` tick con lo stesso input e raccoglie tutti gli eventi.
fn run(m: &mut Match, ticks: u32, input: &Input) -> Vec<Event> {
    (0..ticks)
        .flat_map(|_| m.step(input).iter().collect::<Vec<_>>())
        .collect()
}

fn idle(m: &mut Match, ticks: u32) -> Vec<Event> {
    run(m, ticks, &Input::default())
}

/// Velocità in px per tick a 60 Hz (le unità della configurazione) -> unità interne.
fn speed60(v: f64) -> Fx {
    fixed::from_f64(v * 60.0 / TICK_HZ as f64)
}

fn aim_at_paddle(m: &mut Match, side: Side, vx60: f64, offset_y: i32) {
    let h = m.params.height;
    let w = m.params.width;
    m.paddles[side as usize].y = h / 2;
    m.ball.y = h / 2 + fixed::int(offset_y);
    m.ball.x = w / 2;
    let vx = speed60(vx60);
    m.ball.vx = if side == Side::Left { -vx } else { vx };
    m.ball.vy = 0;
}

#[test]
fn scaling_matches_reference_resolution() {
    let p = params();
    assert_eq!((p.width, p.height), (fixed::int(800), fixed::int(480)));
    assert_eq!(p.pad_height, fixed::int(80));
    assert_eq!(p.ball_radius, fixed::int(5));
}

#[test]
fn paddle_returns_ball_and_speeds_it_up() {
    let mut m = make(2, false);
    aim_at_paddle(&mut m, Side::Left, 3.0, 0);
    let events = idle(&mut m, 4 * 200);
    assert!(events.contains(&Event::Hit));
    assert_eq!(m.score, [0, 0]);
    assert!(m.ball.vx > 0);
    assert_eq!(m.ball.vx, fixed::mul(speed60(3.0), m.params.kspeed_2p));
}

#[test]
fn fast_ball_does_not_tunnel_through_paddle() {
    for side in Side::BOTH {
        let mut m = make(2, false);
        aim_at_paddle(&mut m, side, 240.0, 0); // 60 px per tick, molto più della racchetta larga 10 px
        let events = idle(&mut m, 20);
        assert!(events.contains(&Event::Hit), "{side:?}");
        assert!(!events.contains(&Event::Score), "{side:?}");
    }
}

#[test]
fn miss_gives_point_to_opponent_and_serves_to_loser() {
    let mut m = make(2, false);
    aim_at_paddle(&mut m, Side::Left, 4.0, 0);
    m.paddles[0].y = m.paddles[0].height / 2; // fuori traiettoria
    m.ball.y = m.params.height - fixed::int(50);
    let events = idle(&mut m, 4 * 200);
    assert!(events.contains(&Event::Score));
    assert_eq!(m.score, [0, 1]);
    assert!(m.ball.vx < 0); // la battuta successiva va verso chi ha subito il punto
}

#[test]
fn single_player_scores_on_wall_and_records_best() {
    let mut m = make(1, false);
    assert_eq!(m.paddles[1].height, m.params.height);
    aim_at_paddle(&mut m, Side::Right, 3.0, 0);
    idle(&mut m, 4 * 150);
    assert_eq!(m.score[0], 1);

    aim_at_paddle(&mut m, Side::Left, 4.0, 0);
    m.paddles[0].y = m.paddles[0].height / 2;
    m.ball.y = m.params.height - fixed::int(50);
    idle(&mut m, 4 * 200);
    assert_eq!(m.score[0], 0);
    assert_eq!(m.best, 1);
}

#[test]
fn single_player_wall_does_not_speed_up_ball() {
    let mut m = make(1, false);
    aim_at_paddle(&mut m, Side::Right, 3.0, 0);
    idle(&mut m, 4 * 150);
    assert!(m.ball.vx < 0);
    assert_eq!(m.ball.vx, -speed60(3.0));

    aim_at_paddle(&mut m, Side::Left, 3.0, 0);
    idle(&mut m, 4 * 150);
    assert_eq!(m.ball.vx, fixed::mul(speed60(3.0), m.params.kspeed_1p));
}

#[test]
fn difficulty_levels_grow_harder() {
    let levels: Vec<Params> = (0..DIFFICULTY_LEVELS)
        .map(|difficulty| {
            Params::new(&Tuning {
                difficulty,
                ..Tuning::default()
            })
        })
        .collect();
    for w in levels.windows(2) {
        assert!(w[0].kspeed_1p < w[1].kspeed_1p);
        assert!(w[0].max_ball_speed_1p < w[1].max_ball_speed_1p);
        assert!(w[0].kspeed_2p <= w[1].kspeed_2p);
        assert!(w[0].max_ball_speed_2p < w[1].max_ball_speed_2p);
    }
    // in due il livello normale è il gioco originale
    assert_eq!(levels[1].kspeed_2p, fixed::from_f64(1.25));
    assert_eq!(levels[1].max_ball_speed_2p, speed60(8.0));
    // oltre l'ultimo livello vale l'ultimo
    assert_eq!(
        Params::new(&Tuning {
            difficulty: 9,
            ..Tuning::default()
        }),
        levels[3]
    );
}

#[test]
fn evo_center_hit_boosts_and_shrinks_area() {
    let mut m = make(2, true);
    let area_before = m.paddles[0].boost_height;
    aim_at_paddle(&mut m, Side::Left, 3.0, 0);
    let events = idle(&mut m, 4 * 200);
    assert!(events.contains(&Event::Boost));
    assert_eq!(m.ball.boost, m.params.boost_mul);
    assert_eq!(m.paddles[0].boost_level, 1);
    assert!(m.paddles[0].boost_height < area_before);
}

#[test]
fn evo_requires_two_players() {
    assert!(!make(1, true).evo);
}

#[test]
fn forward_move_catches_ball() {
    let mut m = make(2, true);
    let pad = m.paddles[0].clone();
    m.ball.x = (pad.home_x + pad.fwd_x) / 2;
    m.ball.y = pad.y;
    m.ball.vx = -speed60(3.0);
    m.ball.vy = 0;

    let mut input = Input::default();
    input.players[0].forward = true;
    let events = m.step(&input);
    assert!(events.has(Event::Boost));
    assert!(m.ball.vx > 0);
    assert!(!m.paddles[0].at_home());
    // presa a metà strada riparte dalla faccia della racchetta avanzata, non da dietro
    assert!(m.ball.left() >= m.paddles[0].right(), "palla dietro la racchetta");

    let events = m.step(&input);
    assert!(!events.has(Event::Boost));
    assert!(m.paddles[0].at_home());
}

#[test]
fn ball_never_leaves_the_field_vertically() {
    let mut m = Match::new(params(), 2, false, 7);
    for _ in 0..20_000 {
        m.step(&Input::default());
        assert!(m.ball.bottom() >= 0 && m.ball.top() <= m.params.height);
    }
}

#[test]
fn paddle_acceleration_and_bounds() {
    let mut m = make(2, false);
    let up = Input {
        players: [
            PlayerInput {
                direction: 1,
                ..Default::default()
            },
            PlayerInput::default(),
        ],
    };
    run(&mut m, 2400, &up);
    assert_eq!(m.paddles[0].top(), m.params.height);
    assert_eq!(m.paddles[0].speed, 0);

    let down_fast = Input {
        players: [
            PlayerInput {
                direction: -1,
                fast: true,
                ..Default::default()
            },
            PlayerInput::default(),
        ],
    };
    run(&mut m, 2400, &down_fast);
    assert_eq!(m.paddles[0].bottom(), 0);
}

#[test]
fn serve_delay_holds_ball() {
    let mut m = Match::new(Params::new(&Tuning::default()), 2, false, 3);
    assert_eq!(m.serve_timer, TICK_HZ / 2);
    let x = m.ball.x;
    idle(&mut m, TICK_HZ / 4);
    assert_eq!(m.ball.x, x);
    idle(&mut m, TICK_HZ / 2);
    assert_ne!(m.ball.x, x);
}

#[test]
fn encoder_positions_paddle_from_top() {
    let mut m = make(2, false);
    let mut input = Input::default();
    input.players[0].top_offset = Some(0);
    m.step(&input);
    assert_eq!(m.paddles[0].top(), m.params.height);
    input.players[0].top_offset = Some(10_000);
    m.step(&input);
    assert_eq!(m.paddles[0].bottom(), 0);
}

#[test]
fn same_seed_and_inputs_give_identical_matches() {
    let script = |t: u64| {
        let mut input = Input::default();
        input.players[0].direction = if (t / 97).is_multiple_of(3) {
            1
        } else if (t / 97) % 3 == 1 {
            -1
        } else {
            0
        };
        input.players[1].direction = if (t / 61).is_multiple_of(2) { 1 } else { -1 };
        input.players[0].forward = t.is_multiple_of(503);
        input
    };
    let mut a = Match::new(params(), 2, true, 1234);
    let mut b = Match::new(params(), 2, true, 1234);
    for t in 0..50_000 {
        let input = script(t);
        assert_eq!(a.step(&input), b.step(&input));
    }
    assert_eq!(a, b);
    assert_ne!(Match::new(params(), 2, true, 1234), Match::new(params(), 2, true, 99));
}

#[test]
fn mirror_symmetry_between_players() {
    // stessa situazione specchiata: stesso esito per i due lati
    let mut l = make(2, false);
    let mut r = make(2, false);
    aim_at_paddle(&mut l, Side::Left, 3.7, 13);
    aim_at_paddle(&mut r, Side::Right, 3.7, 13);
    for _ in 0..400 {
        l.step(&Input::default());
        r.step(&Input::default());
    }
    assert_eq!(l.ball.vx, -r.ball.vx);
    assert_eq!(l.ball.vy, r.ball.vy);
    assert_eq!(l.ball.x - l.params.width / 2, r.params.width / 2 - r.ball.x);
}

#[test]
fn boost_area_table_follows_the_decay_rule() {
    // altezza 80, rapporti 4, 5, 6.25, 7.81, 9.77, 12.2, 15.26, 19.07, 20
    let p = params();
    let heights: Vec<i32> = p.boost_heights[..p.boost_levels as usize]
        .iter()
        .map(|h| fixed::floor(*h))
        .collect();
    assert_eq!(heights, [20, 16, 12, 10, 8, 6, 5, 4, 4]);
}

#[test]
fn arcade_resolution_keeps_distinct_ball_sizes() {
    let p = Params::new(&Tuning {
        width: 320,
        height: 240,
        ..Tuning::default()
    });
    let px = |v: Fx| fixed::floor(v);
    assert_eq!(
        (px(p.ball_radius), px(p.ball_radius_boost), px(p.ball_radius_boost_fwd)),
        (2, 4, 3)
    );
    assert_eq!(
        (
            px(p.pad_width),
            px(p.pad_height),
            px(p.pad_start_pos),
            px(p.pad_fwd_pos)
        ),
        (4, 40, 20, 80)
    );
}

#[test]
fn c64_preset_scales_time_to_one_tick_per_frame() {
    let c64 = Params::new(&Tuning::c64());
    let pc = Params::new(&Tuning {
        width: 320,
        height: 200,
        ..Tuning::default()
    });
    assert_eq!(c64.tick_hz, 50);
    assert_eq!((c64.width, c64.height), (fixed::int(320), fixed::int(200)));
    // stessi pixel, tempi in tick a 50 Hz, velocità per tick 240/50 volte più grandi
    assert_eq!(c64.pad_height, pc.pad_height);
    assert_eq!(c64.serve_ticks, 25);
    assert_eq!(pc.serve_ticks, 120);
    assert!((c64.pad_max_speed - pc.pad_max_speed * 24 / 5).abs() <= 2);
    // previsioni a passi di un tick con lo stesso orizzonte (1024 tick a 240 Hz); lampi del GHOST
    assert_eq!((c64.predict_step, c64.predict_max), (1, 213));
    assert_eq!((c64.arrival_step, c64.arrival_max), (1, 213));
    assert_eq!((pc.predict_step, pc.predict_max), (8, 128));
    assert_eq!((pc.arrival_step, pc.arrival_max), (4, 256));
    assert_eq!((c64.ghost_period, c64.ghost_visible), (20, 5));
    assert_eq!((pc.ghost_period, pc.ghost_visible), (96, 24));
}

#[test]
fn c64_match_plays_points() {
    let mut m = Match::new(Params::new(&Tuning::c64()), 2, true, 3);
    let events = idle(&mut m, 50 * 60);
    assert!(events.contains(&Event::Score));
    assert!(m.score[0] + m.score[1] > 0);
}
