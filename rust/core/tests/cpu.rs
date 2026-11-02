use paddws_core::{Bonus, Cpu, Event, Input, Match, Params, Side, TICK_HZ, Tuning};

fn params(difficulty: u8) -> Params {
    Params::new(&Tuning {
        difficulty,
        ..Tuning::default()
    })
}

/// Partita di `seconds` secondi tra due CPU: restituisce colpi e punti.
fn duel(m: &mut Match, cpus: &mut [Cpu; 2], seconds: u32) -> (u32, u32) {
    let (mut hits, mut points) = (0, 0);
    for _ in 0..TICK_HZ * seconds {
        let mut input = Input::default();
        for cpu in cpus.iter_mut() {
            input.players[cpu.side() as usize] = cpu.input(m);
        }
        let events = m.step(&input);
        hits += events.has(Event::Hit) as u32 + events.has(Event::Boost) as u32;
        points += events.has(Event::Score) as u32;
    }
    (hits, points)
}

#[test]
fn stronger_cpu_misses_less() {
    let rate = |level: u8| {
        let p = params(1);
        let mut m = Match::new(p.clone(), 2, false, 7);
        let mut cpus = [Cpu::new(&p, level, Side::Left, 1), Cpu::new(&p, level, Side::Right, 2)];
        let (hits, points) = duel(&mut m, &mut cpus, 600);
        hits as f64 / points.max(1) as f64
    };
    let rates: Vec<f64> = (0..4).map(rate).collect();
    println!("colpi per punto per livello: {rates:.1?}");
    let (easy, expert) = (rates[0], rates[3]);
    assert!(
        expert > easy * 1.5,
        "colpi per punto: facile {easy:.1}, esperto {expert:.1}"
    );
}

#[test]
fn cpu_plays_next_and_uses_bonuses() {
    let p = params(1);
    let loadout = [Bonus::Smash, Bonus::Teleport, Bonus::Curve];
    let mut m = Match::new_next(p.clone(), [loadout, loadout], 3);
    let mut cpus = [Cpu::new(&p, 2, Side::Left, 1), Cpu::new(&p, 2, Side::Right, 2)];
    let mut activated = 0;
    let mut collected = 0;
    for _ in 0..TICK_HZ * 300 {
        let mut input = Input::default();
        for cpu in cpus.iter_mut() {
            input.players[cpu.side() as usize] = cpu.input(&m);
        }
        let events = m.step(&input);
        activated += events.has(Event::Activate) as u32;
        collected += events.has(Event::Collect) as u32;
    }
    assert!(collected > 10, "capsule raccolte: {collected}");
    assert!(activated > 5, "bonus attivati: {activated}");
}

#[test]
fn cpu_is_reproducible() {
    let run = || {
        let p = params(2);
        let mut m = Match::new(p.clone(), 2, true, 11);
        let mut cpus = [Cpu::new(&p, 2, Side::Left, 5), Cpu::new(&p, 2, Side::Right, 6)];
        duel(&mut m, &mut cpus, 60);
        m
    };
    assert_eq!(run(), run());
}
