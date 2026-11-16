//! Oscilloscopi delle voci del SID (`music::SidMusic::scope_window`): la rete di OMEGA, che segue
//! il basso della voce 2, e i tre oscilloscopi del JUKEBOX.
//!
//! Come i visualizzatori delle musiche chiptune: una finestra di `WINDOW` secondi agganciata al
//! primo passaggio per lo zero in salita (con isteresi: prima il segnale deve scendere sotto
//! `-HYSTERESIS` volte il suo picco), cercato nei primi `SEARCH` secondi, così la forma d'onda sta
//! ferma; senza la media della finestra (niente scostamenti lenti dallo zero).

use crate::music::SidMusic;

/// Finestra mostrata (s).
pub const WINDOW: f64 = 0.12;
/// Dove si cerca il passaggio per lo zero, prima della finestra (s).
pub const SEARCH: f64 = 0.05;
const HYSTERESIS: f32 = 0.1;

/// Rete di OMEGA: i trattini della rete di sempre (2x4 pixel a 240 righe, uno ogni 8 righe), e lo
/// spostamento massimo di ciascuno (pixel).
pub const NET_DASHES: usize = 30;
pub const NET_STEP: usize = 8;
pub const NET_REACH: f32 = 3.0;
/// Ampiezza della voce 2 nelle canzoni di OMEGA che porta un trattino a `NET_REACH`, con la musica
/// a volume 1: il 99,5° percentile del basso (media su 1 ms, senza la media di 120 ms), misurato
/// con `paddws_sid::Music` sulle sette sezioni (da circa 0,2 a 0,25 secondo il tratto; vedi il
/// test).
pub const NET_PEAK: f32 = 0.245;
/// Scala piena degli oscilloscopi del JUKEBOX (volume 1): una voce a inviluppo pieno senza filtro
/// arriva a circa 0,233; con il filtro e la risonanza un po' di più (fino a 0,3 nel basso di
/// HAMMER e di OMEGA).
pub const SCOPE_FULL: f32 = 0.35;

/// Campioni della finestra, con la ricerca dell'aggancio, alla frequenza `rate`.
fn lengths(rate: u32) -> (usize, usize) {
    ((SEARCH * rate as f64) as usize, (WINDOW * rate as f64) as usize)
}

/// La voce `voice` (0-2) intorno a quello che si sente: la ricerca dell'aggancio più la finestra,
/// centrate sull'adesso. None senza audio.
pub fn read(music: &SidMusic, voice: usize) -> Option<(Vec<f32>, u32)> {
    let rate = music.scope_rate();
    if rate == 0 {
        return None;
    }
    let (search, window) = lengths(rate);
    let mut out = vec![0.0; search + window];
    music.scope_window(voice, -((search + window) as i64) / 2, &mut out);
    Some((out, rate))
}

/// Media mobile su `n` campioni (centrata), meno la media di tutto: la traccia ammorbidita come
/// quella di un oscilloscopio.
fn smooth(x: &[f32], n: usize) -> Vec<f32> {
    if x.is_empty() {
        return Vec::new();
    }
    let mean = x.iter().sum::<f32>() / x.len() as f32;
    let half = n / 2;
    // somme prefisse: la media di ogni tratto in tempo costante
    let mut acc = Vec::with_capacity(x.len() + 1);
    acc.push(0.0f64);
    for &v in x {
        acc.push(acc.last().copied().unwrap_or(0.0) + v as f64);
    }
    (0..x.len())
        .map(|i| {
            let (a, b) = (i.saturating_sub(half), (i + half + 1).min(x.len()));
            ((acc[b] - acc[a]) / (b - a) as f64) as f32 - mean
        })
        .collect()
}

/// Primo passaggio per lo zero in salita nei primi `search` campioni, con l'isteresi (0 se non
/// c'è).
fn trigger(x: &[f32], search: usize) -> usize {
    let peak = x.iter().fold(0.0f32, |m, v| m.max(v.abs()));
    let th = HYSTERESIS * peak;
    let mut armed = false;
    for (i, &v) in x.iter().enumerate().take(search) {
        if v < -th {
            armed = true;
        } else if armed && v >= 0.0 {
            return i;
        }
    }
    0
}

/// Rete di OMEGA dai campioni della voce 2 (`read`): lo spostamento di ogni trattino, da
/// `-NET_REACH` a `NET_REACH` pixel, con `peak` l'ampiezza che porta al massimo.
pub fn net_offsets(x: &[f32], rate: u32, peak: f32) -> [i32; NET_DASHES] {
    let mut out = [0; NET_DASHES];
    let (search, window) = lengths(rate);
    if peak <= 0.0 || x.len() < search + window {
        return out;
    }
    let sm = smooth(x, (rate / 1000).max(1) as usize);
    let i0 = trigger(&sm, search);
    let rows = NET_DASHES * NET_STEP;
    for (k, o) in out.iter_mut().enumerate() {
        // il centro del trattino, alla sua riga della finestra
        let i = i0 + (k * NET_STEP + 2) * window / rows;
        let v = sm.get(i).copied().unwrap_or(0.0);
        *o = ((v / peak).clamp(-1.0, 1.0) * NET_REACH).round() as i32;
    }
    out
}

/// Oscilloscopio del JUKEBOX: `points` valori da -1 a 1 lungo la finestra agganciata, con `full`
/// la scala piena.
pub fn trace(x: &[f32], rate: u32, full: f32, points: usize) -> Vec<f32> {
    let (search, window) = lengths(rate);
    if full <= 0.0 || x.len() < search + window || points < 2 {
        return vec![0.0; points];
    }
    let sm = smooth(x, 1);
    let i0 = trigger(&sm, search);
    (0..points)
        .map(|p| {
            let i = i0 + p * (window - 1) / (points - 1);
            (sm.get(i).copied().unwrap_or(0.0) / full).clamp(-1.0, 1.0)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const RATE: u32 = 44_100;

    fn sine(freq: f32, amp: f32, phase: f32) -> Vec<f32> {
        let (s, w) = lengths(RATE);
        (0..s + w)
            .map(|i| amp * (std::f32::consts::TAU * freq * i as f32 / RATE as f32 + phase).sin())
            .collect()
    }

    #[test]
    fn the_net_follows_the_wave_and_stays_within_three_pixels() {
        // 25 Hz: tre periodi nella finestra, agganciati alla salita
        let x = sine(25.0, 0.5, 2.0);
        let net = net_offsets(&x, RATE, NET_PEAK);
        assert!(net.iter().all(|d| d.abs() <= NET_REACH as i32));
        assert!(net.contains(&3) && net.contains(&-3), "{net:?}");
        // agganciata: il primo trattino è vicino allo zero e la forma sale
        assert!(net[0].abs() <= 1 && net[1] >= net[0], "{net:?}");
        // la stessa forma con un'altra fase di partenza: la stessa rete (a meno degli arrotondamenti)
        let other = net_offsets(&sine(25.0, 0.5, 4.0), RATE, NET_PEAK);
        assert!(net.iter().zip(other).all(|(a, b)| (a - b).abs() <= 1), "{net:?} {other:?}");
        // silenzio, o senza musica: la rete di sempre
        assert_eq!(net_offsets(&vec![0.0; x.len()], RATE, NET_PEAK), [0; NET_DASHES]);
        assert_eq!(net_offsets(&x, RATE, 0.0), [0; NET_DASHES]);
        // un basso piano si muove meno
        let soft = net_offsets(&sine(25.0, 0.1, 2.0), RATE, NET_PEAK);
        assert!(soft.iter().all(|d| d.abs() <= 2), "{soft:?}");
    }

    #[test]
    fn the_trace_is_triggered_and_scaled() {
        let t = trace(&sine(100.0, SCOPE_FULL / 2.0, 1.0), RATE, SCOPE_FULL, 64);
        assert_eq!(t.len(), 64);
        assert!(t[0].abs() < 0.1 && t[1] > t[0], "{t:?}");
        let peak = t.iter().fold(0.0f32, |m, v| m.max(v.abs()));
        assert!((peak - 0.5).abs() < 0.05, "{peak}");
    }

    /// `NET_PEAK` è l'ampiezza del basso di OMEGA misurata come la rete la legge.
    #[test]
    fn the_net_peak_matches_the_omega_bass() {
        let rom = paddws_sid::Rom::builtin();
        for k in 0..7 {
            let mut m = paddws_sid::Music::new(RATE);
            m.set_scope(true);
            m.set_song(rom.song_number(&format!("omega{k}")).unwrap());
            // 6 secondi, a blocchi più corti del buffer degli oscilloscopi
            let mut x = Vec::new();
            for _ in 0..30 {
                let mut buf = vec![0.0; RATE as usize / 5];
                m.render(&mut buf);
                let s = m.scope().unwrap();
                let n = s.written();
                x.extend((n - buf.len() as u64..n).map(|i| s.sample(1, i)));
            }
            let (_, w) = lengths(RATE);
            let mut a: Vec<f32> = x.chunks(w).flat_map(|c| smooth(c, 44)).map(f32::abs).collect();
            a.sort_by(f32::total_cmp);
            let p = a[a.len() * 995 / 1000];
            assert!((p / NET_PEAK - 1.0).abs() < 0.2, "omega{k}: {p}");
        }
    }
}
