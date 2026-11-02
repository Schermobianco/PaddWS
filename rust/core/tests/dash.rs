//! Scatto in avanti contro palle veloci in diagonale: non deve mai far perdere una palla che la
//! racchetta ferma avrebbe preso (EVO, stessa logica di NEXT).

use paddws_core::fixed;
use paddws_core::{Event, Input, Match, Params, TICK_HZ, Tuning};

/// Palla veloce verso la racchetta sinistra (a casa), con un angolo, puntata a `offset` mezze
/// racchette dal centro; scatto al tick `dash_tick`. Esito: la palla torna indietro, e se allo
/// scatto era nella fascia tra la faccia di casa e quella avanzata.
fn rally(vy_ratio: f64, offset: f64, dash_tick: Option<u32>) -> (bool, bool) {
    let params = Params::new(&Tuning { serve_delay: 0.0, ..Tuning::default() });
    let mut m = Match::new(params, 2, true, 1);
    m.serve_timer = 0;
    let pad = m.paddles[0].clone();
    let speed = fixed::from_f64(12.0 * 60.0 / TICK_HZ as f64);
    m.ball.vx = -speed;
    m.ball.vy = fixed::from_f64(12.0 * 60.0 / TICK_HZ as f64 * vy_ratio);
    // parte da lontano, puntata a `offset` (in mezze racchette) dal centro all'arrivo sulla faccia
    let start_dx = fixed::int(200);
    m.ball.x = pad.right() + m.ball.radius + start_dx;
    let arrive_y = pad.y + fixed::from_f64(offset * fixed::to_f32(pad.height) as f64 / 2.0);
    let ticks = start_dx / speed;
    m.ball.y = arrive_y - m.ball.vy * ticks;
    let mut in_band = false;
    for t in 0..TICK_HZ * 2 {
        let mut input = Input::default();
        input.players[0].forward = dash_tick == Some(t);
        if dash_tick == Some(t) {
            // palla tra la faccia di casa e quella avanzata, in arrivo
            let fwd_face = pad.fwd_x + pad.width / 2;
            in_band = m.ball.left() >= pad.right() && m.ball.left() <= fwd_face;
        }
        let e = m.step(&input);
        if e.has(Event::Score) {
            return (false, in_band);
        }
        if m.ball.vx > 0 {
            return (true, in_band);
        }
    }
    (false, in_band)
}

#[test]
fn a_dash_never_loses_a_ball_the_paddle_at_home_would_take() {
    let mut worse = 0;
    let mut total = 0;
    let mut examples = Vec::new();
    for vr in [0.5, 0.8, 1.0] {
        for off10 in -14..=14 {
            let off = off10 as f64 / 10.0;
            let (base, _) = rally(vr, off, None);
            for dt in 0..120 {
                let (with, band) = rally(vr, off, Some(dt));
                if !band {
                    continue;
                }
                total += 1;
                if base && !with {
                    worse += 1;
                    if examples.len() < 12 {
                        examples.push((vr, off, dt));
                    }
                }
            }
        }
    }
    assert!(total > 1000, "pochi scatti nella fascia: {total}");
    assert_eq!(worse, 0, "scatti che perdono la palla (inclinazione, punto, tick): {examples:?}");
}
