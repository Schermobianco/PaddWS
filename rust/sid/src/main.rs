//! Strumento del SID Rust: registra una canzone in WAV, la confronta con una registrazione del SID
//! del core MiSTer simulato, misura la CPU.
//!
//! ```text
//! paddws-sid render CANZONE OUT.wav [--fast] [--slow] [--seconds S] [--rate HZ]
//! paddws-sid compare CANZONE RIF.wav [--save OUT.wav]
//! paddws-sid bench
//! ```
//!
//! CANZONE è il numero (da 1) o il nome di `sid_music.vh` in minuscolo (`title`, `theme_hammer`...).
//! Le registrazioni di riferimento (mono, 16 bit, 44,1 kHz, dall'inizio della canzone) le fa
//! `mister/sim/sid/render.ps1 CARTELLA`. Il confronto misura il livello complessivo, l'RMS per frame
//! da 20 ms (l'inviluppo), lo spettro grossolano per ottave e la correlazione delle forme d'onda.

use std::process::ExitCode;
use std::time::Instant;

use paddws_sid::Music;

const RATE: u32 = 44_100;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let flag = |name: &str| args.iter().any(|a| a == name);
    let value = |name: &str| {
        args.iter()
            .position(|a| a == name)
            .and_then(|i| args.get(i + 1))
            .cloned()
    };
    let result = match args.first().map(String::as_str) {
        Some("render") if args.len() >= 3 => render(
            &args[1],
            &args[2],
            flag("--fast"),
            flag("--slow"),
            value("--seconds").and_then(|s| s.parse().ok()),
            value("--rate").and_then(|s| s.parse().ok()).unwrap_or(RATE),
        ),
        Some("compare") if args.len() >= 3 => compare(&args[1], &args[2], value("--save")),
        Some("bench") => bench(),
        _ => Err(
            "uso: paddws-sid render CANZONE OUT.wav [--fast] [--slow] [--seconds S] [--rate HZ]\n\
                  \x20     paddws-sid compare CANZONE RIF.wav [--save OUT.wav]\n\
                  \x20     paddws-sid bench"
                .into(),
        ),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("{e}");
            ExitCode::FAILURE
        }
    }
}

fn song(music: &Music, name: &str) -> Result<u8, String> {
    music.rom().song_number(name).filter(|&n| n > 0).ok_or(format!(
        "canzone {name:?} sconosciuta: {}",
        music.rom().names.join(", ")
    ))
}

fn render(name: &str, out: &str, fast: bool, slow: bool, seconds: Option<f64>, rate: u32) -> Result<(), String> {
    let mut music = Music::new(rate);
    let n = song(&music, name)?;
    music.set_song(n);
    music.set_fast(fast);
    music.set_slow(slow);
    let seconds = seconds.unwrap_or(20.0);
    let mut buf = vec![0.0; (seconds * rate as f64) as usize];
    music.render(&mut buf);
    write_wav(out, &buf, rate)?;
    println!(
        "{out}: {} {seconds:.1} s{}{}",
        name,
        if fast { ", veloce" } else { "" },
        if slow { ", rallentata" } else { "" }
    );
    Ok(())
}

// ------------------------------------------------------------------------------------ WAV

fn write_wav(path: &str, samples: &[f32], rate: u32) -> Result<(), String> {
    let data = samples.len() as u32 * 2;
    let mut b = Vec::with_capacity(44 + data as usize);
    b.extend_from_slice(b"RIFF");
    b.extend_from_slice(&(36 + data).to_le_bytes());
    b.extend_from_slice(b"WAVEfmt ");
    b.extend_from_slice(&16u32.to_le_bytes());
    b.extend_from_slice(&1u16.to_le_bytes()); // PCM
    b.extend_from_slice(&1u16.to_le_bytes()); // mono
    b.extend_from_slice(&rate.to_le_bytes());
    b.extend_from_slice(&(rate * 2).to_le_bytes());
    b.extend_from_slice(&2u16.to_le_bytes());
    b.extend_from_slice(&16u16.to_le_bytes());
    b.extend_from_slice(b"data");
    b.extend_from_slice(&data.to_le_bytes());
    for s in samples {
        b.extend_from_slice(&((s * 32768.0).round().clamp(-32768.0, 32767.0) as i16).to_le_bytes());
    }
    std::fs::write(path, b).map_err(|e| format!("{path}: {e}"))
}

/// WAV PCM a 16 bit: campioni del primo canale in [-1, 1] e frequenza.
fn read_wav(path: &str) -> Result<(Vec<f32>, u32), String> {
    let b = std::fs::read(path).map_err(|e| format!("{path}: {e}"))?;
    if b.len() < 12 || &b[0..4] != b"RIFF" || &b[8..12] != b"WAVE" {
        return Err(format!("{path}: non è un WAV"));
    }
    let (mut at, mut fmt) = (12, None);
    while at + 8 <= b.len() {
        let size = u32::from_le_bytes([b[at + 4], b[at + 5], b[at + 6], b[at + 7]]) as usize;
        let body = &b[at + 8..(at + 8 + size).min(b.len())];
        if &b[at..at + 4] == b"fmt " && body.len() >= 16 {
            let u16_at = |i: usize| u16::from_le_bytes([body[i], body[i + 1]]);
            fmt = Some((
                u16_at(2) as usize,
                u32::from_le_bytes([body[4], body[5], body[6], body[7]]),
                u16_at(14),
            ));
        } else if &b[at..at + 4] == b"data" {
            let (channels, rate, bits) = fmt.ok_or(format!("{path}: data prima di fmt"))?;
            if bits != 16 {
                return Err(format!("{path}: {bits} bit invece di 16"));
            }
            let s = body
                .chunks_exact(2 * channels)
                .map(|c| i16::from_le_bytes([c[0], c[1]]) as f32 / 32768.0)
                .collect();
            return Ok((s, rate));
        }
        at += 8 + size + (size & 1);
    }
    Err(format!("{path}: senza dati"))
}

// ------------------------------------------------------------------------------------ confronto

fn rms(x: &[f32]) -> f64 {
    if x.is_empty() {
        return 0.0;
    }
    (x.iter().map(|&s| (s as f64) * (s as f64)).sum::<f64>() / x.len() as f64).sqrt()
}

fn db(x: f64) -> f64 {
    20.0 * x.max(1e-9).log10()
}

fn pearson(a: &[f64], b: &[f64]) -> f64 {
    let n = a.len().min(b.len()) as f64;
    let (ma, mb) = (a.iter().sum::<f64>() / n, b.iter().sum::<f64>() / n);
    let (mut sab, mut saa, mut sbb) = (0.0, 0.0, 0.0);
    for (x, y) in a.iter().zip(b) {
        sab += (x - ma) * (y - mb);
        saa += (x - ma) * (x - ma);
        sbb += (y - mb) * (y - mb);
    }
    sab / (saa * sbb).sqrt().max(1e-30)
}

/// FFT complessa sul posto (lunghezza potenza di 2).
fn fft(re: &mut [f64], im: &mut [f64]) {
    let n = re.len();
    let mut j = 0;
    for i in 1..n {
        let mut bit = n >> 1;
        while j & bit != 0 {
            j ^= bit;
            bit >>= 1;
        }
        j |= bit;
        if i < j {
            re.swap(i, j);
            im.swap(i, j);
        }
    }
    let mut len = 2;
    while len <= n {
        let ang = -2.0 * std::f64::consts::PI / len as f64;
        for start in (0..n).step_by(len) {
            for k in 0..len / 2 {
                let (wr, wi) = ((ang * k as f64).cos(), (ang * k as f64).sin());
                let (a, b) = (start + k, start + k + len / 2);
                let (xr, xi) = (re[b] * wr - im[b] * wi, re[b] * wi + im[b] * wr);
                re[b] = re[a] - xr;
                im[b] = im[a] - xi;
                re[a] += xr;
                im[a] += xi;
            }
        }
        len <<= 1;
    }
}

/// Potenza media per banda d'ottava (centri da 31 Hz a 16 kHz), con finestre di Hann da 4096.
fn octave_bands(x: &[f32], rate: u32) -> Vec<(f64, f64)> {
    const N: usize = 4096;
    let centers: Vec<f64> = (0..10).map(|i| 31.25 * 2f64.powi(i)).collect();
    let mut power = vec![0.0; centers.len()];
    let mut windows = 0;
    let mut at = 0;
    while at + N <= x.len() {
        let mut re: Vec<f64> = (0..N)
            .map(|i| x[at + i] as f64 * (0.5 - 0.5 * (2.0 * std::f64::consts::PI * i as f64 / N as f64).cos()))
            .collect();
        let mut im = vec![0.0; N];
        fft(&mut re, &mut im);
        for k in 1..N / 2 {
            let f = k as f64 * rate as f64 / N as f64;
            if let Some(b) = centers
                .iter()
                .position(|&c| f >= c / 2f64.sqrt() && f < c * 2f64.sqrt())
            {
                power[b] += re[k] * re[k] + im[k] * im[k];
            }
        }
        windows += 1;
        at += N / 2;
    }
    centers
        .into_iter()
        .zip(power.into_iter().map(|p| p / windows.max(1) as f64))
        .collect()
}

fn compare(name: &str, reference: &str, save: Option<String>) -> Result<(), String> {
    let (want, rate) = read_wav(reference)?;
    let mut music = Music::new(rate);
    let n = song(&music, name)?;
    // come mister/sim/sid/render.cpp: due passi dopo il reset, poi la canzone dal passo dopo
    // (conta per la fase degli arpeggi)
    let mut preroll = vec![0.0; 2 * rate as usize / 50];
    music.render(&mut preroll);
    music.set_song(n);
    let mut got = vec![0.0; want.len()];
    music.render(&mut got);
    if let Some(path) = &save {
        write_wav(path, &got, rate)?;
    }
    let (rw, rg) = (rms(&want), rms(&got));
    println!("{name}: {:.2} s a {rate} Hz", want.len() as f64 / rate as f64);
    println!(
        "  livello RMS: riferimento {:.1} dBFS, Rust {:.1} dBFS, differenza {:+.2} dB",
        db(rw),
        db(rg),
        db(rg / rw)
    );
    let (pw, pg) = (
        want.iter().fold(0f32, |m, s| m.max(s.abs())),
        got.iter().fold(0f32, |m, s| m.max(s.abs())),
    );
    println!(
        "  picco: riferimento {:.1} dBFS, Rust {:.1} dBFS",
        db(pw as f64),
        db(pg as f64)
    );
    // inviluppo: RMS per frame da 20 ms, sui frame non silenziosi
    let frame = rate as usize / 50;
    let (fw, fg): (Vec<f64>, Vec<f64>) = want
        .chunks(frame)
        .zip(got.chunks(frame))
        .map(|(a, b)| (db(rms(a)), db(rms(b))))
        .unzip();
    let loud: Vec<usize> = (0..fw.len()).filter(|&i| fw[i] > -50.0 || fg[i] > -50.0).collect();
    let mut diffs: Vec<f64> = loud.iter().map(|&i| (fg[i] - fw[i]).abs()).collect();
    diffs.sort_by(|a, b| a.total_cmp(b));
    let pick = |q: f64| {
        diffs
            .get(((diffs.len() as f64 - 1.0) * q) as usize)
            .copied()
            .unwrap_or(0.0)
    };
    let (lw, lg): (Vec<f64>, Vec<f64>) = loud.iter().map(|&i| (fw[i], fg[i])).unzip();
    println!(
        "  inviluppo (RMS per frame da 20 ms, {} frame): correlazione {:.4}, differenza media {:.2} dB, mediana {:.2} dB, 95° percentile {:.2} dB",
        loud.len(),
        pearson(&lw, &lg),
        diffs.iter().sum::<f64>() / diffs.len().max(1) as f64,
        pick(0.5),
        pick(0.95)
    );
    // spettro grossolano
    let (bw, bg) = (octave_bands(&want, rate), octave_bands(&got, rate));
    let total: f64 = bw.iter().map(|b| b.1).sum();
    print!("  spettro per ottave (Rust - riferimento, dB; bande sopra -40 dB dal totale):");
    for ((c, p), (_, q)) in bw.iter().zip(&bg) {
        if *p > total * 1e-4 {
            print!(
                " {}:{:+.1}",
                if *c >= 1000.0 {
                    format!("{:.0}k", c / 1000.0)
                } else {
                    format!("{c:.0}")
                },
                10.0 * (q / p).log10()
            );
        }
    }
    println!();
    // forme d'onda: correlazione con il miglior ritardo entro ±2 ms
    let a: Vec<f64> = want.iter().map(|&s| s as f64).collect();
    let b: Vec<f64> = got.iter().map(|&s| s as f64).collect();
    let max_lag = rate as usize / 500;
    let (mut best, mut best_lag) = (f64::MIN, 0i64);
    for lag in -(max_lag as i64)..=max_lag as i64 {
        let (x, y) = if lag >= 0 {
            (&a[lag as usize..], &b[..b.len() - lag as usize])
        } else {
            (&a[..a.len() - (-lag) as usize], &b[(-lag) as usize..])
        };
        let r = pearson(x, y);
        if r > best {
            (best, best_lag) = (r, lag);
        }
    }
    println!("  forma d'onda: correlazione {best:.4} (ritardo {best_lag} campioni)");
    Ok(())
}

// ------------------------------------------------------------------------------------ CPU

fn bench() -> Result<(), String> {
    let mut music = Music::new(RATE);
    let seconds = 60usize;
    let mut buf = vec![0.0; RATE as usize];
    let mut total = 0.0;
    // i temi di CHALLENGE (le tre voci del titolo sono il caso peggiore), 60 s di musica
    for (i, song) in [1u8, 9, 11, 13].iter().cycle().take(seconds).enumerate() {
        if i % 15 == 0 {
            music.set_song(*song);
        }
        let t = Instant::now();
        music.render(&mut buf);
        total += t.elapsed().as_secs_f64();
    }
    println!(
        "{seconds} s di musica in {:.1} ms: {:.2} ms per secondo, {:.2}% di un core",
        total * 1e3,
        total * 1e3 / seconds as f64,
        total * 100.0 / seconds as f64
    );
    Ok(())
}
