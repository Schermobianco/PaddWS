//! Il player Rust contro quello Verilog: stesse scritture ai registri del SID, frame per frame,
//! dei riferimenti prodotti da `mister/sim/sid/writes.ps1`: `c64/test/sid_reference.txt` (lo
//! stesso che verifica il player in 6502 con `paddws-c64 sid`) e, per la musica dinamica (match
//! point, bullet time e le due cose insieme), `tests/writes_fast.txt`, `writes_slow.txt`,
//! `writes_both.txt`. Ci sono anche i comandi del filtro.

use paddws_sid::Rom;
use paddws_sid::player::Player;

/// Comandi di un frame (S canzone, X eventi, L bullet time) e scritture attese.
type Frame = (Vec<(char, u8)>, Vec<(u8, u8)>);

fn frames(path: &str) -> Vec<Frame> {
    let text = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{path}: {e}"));
    let mut frames: Vec<Frame> = Vec::new();
    for line in text.lines() {
        let mut parts = line.split_whitespace();
        let (Some(kind), Some(a)) = (parts.next(), parts.next()) else {
            continue;
        };
        match kind {
            "F" => frames.push((Vec::new(), Vec::new())),
            "S" | "X" | "L" => frames
                .last_mut()
                .unwrap()
                .0
                .push((kind.chars().next().unwrap(), a.parse().unwrap())),
            "W" => {
                let r = u8::from_str_radix(a, 16).unwrap();
                let v = u8::from_str_radix(parts.next().unwrap(), 16).unwrap();
                frames.last_mut().unwrap().1.push((r, v));
            }
            _ => {}
        }
    }
    frames
}

/// Scritture contate, canzoni suonate, effetti, scritture del filtro ($D415-$D417).
struct Stats {
    writes: usize,
    songs: std::collections::BTreeSet<u8>,
    effects: usize,
    filter: usize,
}

/// Il player Rust frame per frame contro il riferimento: un passo per frame (al match point il
/// "frame" del riferimento è il passo della canzone).
fn check(rom: Rom, path: &str) -> Stats {
    let frames = frames(path);
    let mut p = Player::new(rom);
    let mut st = Stats {
        writes: 0,
        songs: Default::default(),
        effects: 0,
        filter: 0,
    };
    for (n, (commands, expected)) in frames.iter().enumerate() {
        let mut got: Vec<(u8, u8)> = Vec::new();
        for &(kind, v) in commands {
            match kind {
                'S' => {
                    p.set_song(v);
                    st.songs.insert(v);
                }
                'L' => p.set_slow(v != 0),
                _ => {
                    p.effect(v, false, &mut |r, x| got.push((r, x)));
                    st.effects += 1;
                }
            }
        }
        p.tick(&mut |r, x| got.push((r, x)));
        let fmt = |w: &[(u8, u8)]| {
            w.iter()
                .map(|(r, v)| format!("{r:02x}={v:02x}"))
                .collect::<Vec<_>>()
                .join(" ")
        };
        assert_eq!(
            got,
            *expected,
            "{path}, frame {n}\n    Verilog {}\n    Rust    {}",
            fmt(expected),
            fmt(&got)
        );
        st.writes += expected.len();
        st.filter += expected.iter().filter(|(r, _)| (0x15..=0x17).contains(r)).count();
    }
    st
}

fn dir() -> &'static str {
    env!("CARGO_MANIFEST_DIR")
}

#[test]
fn scritture_come_il_player_verilog() {
    let st = check(Rom::builtin(), &format!("{}/../../c64/test/sid_reference.txt", dir()));
    // tutte le canzoni, con i temi di CHALLENGE, tanti effetti, e il filtro
    assert!(st.songs.len() >= 14, "{:?}", st.songs);
    assert!(st.writes > 10_000 && st.effects > 100, "{} {}", st.writes, st.effects);
    assert!(st.filter > 1000, "{} scritture del filtro", st.filter);
}

#[test]
fn musica_dinamica_come_il_player_verilog() {
    for mode in ["fast", "slow", "both"] {
        let st = check(Rom::builtin(), &format!("{}/tests/writes_{mode}.txt", dir()));
        assert!(
            st.writes > 3000 && st.filter > 100,
            "{mode}: {} {}",
            st.writes,
            st.filter
        );
    }
}
