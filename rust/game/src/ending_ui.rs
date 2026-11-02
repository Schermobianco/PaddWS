//! Finale della CHALLENGE, quando si batte l'ultimo avversario: CONGRATULATIONS e la voce "YOU
//! WIN!", la sfilata dei sette avversari battuti con il timbro DEFEATED, il punteggio finale che
//! sale, "YOU ARE THE PADD WS CHAMPION" con i fuochi d'artificio, i titoli di coda e THE END; poi
//! le iniziali della classifica. Start salta tutto e va dritto alle iniziali.
//!
//! Colori: solo bianco, giallo (l'accento) e rosso, senza sfumature: le scintille dei fuochi si
//! diradano invece di scurirsi. Tempi e disegni come le anteprime approvate (`ending.py`,
//! `fireworks.py`), con le misure di uno schermo alto 480 scalate con `App::scale`.

use macroquad::prelude::*;
use paddws_core::challenge::{LEVELS, Score};
use paddws_core::fixed::to_f32;
use paddws_core::{Event, PaddleKind, Rng};

use crate::challenge_ui;
use crate::input;
use crate::next_ui::unit;
use crate::paddle_ui::{Look, Shape, TWIST_MAX_TILT, draw_paddle};
use crate::scenes::{App, START_KEYS, Scene};
use crate::touch;

/// Durata di ogni parte (s): congratulazioni, sfilata, punteggio, campione con i fuochi; i titoli
/// durano quanto serve a farli scorrere (`Credits`), poi THE END.
const CONGRATS: f64 = 3.5;
const PARADE: f64 = 9.0;
const SCORE: f64 = 9.0;
const CHAMPION: f64 = 7.0;
const THE_END: f64 = 3.0;
/// "YOU WIN!" (e la sua voce) un secondo dopo CONGRATULATIONS.
const YOU_WIN_AT: f64 = 1.0;
/// Sfilata: un avversario al secondo, il timbro mezzo secondo dopo.
const PARADE_STEP: f64 = 1.0;
const STAMP_AFTER: f64 = 0.5;
/// Punteggio: SCORE sale in 3 s, poi il premio del campione in 1 s, poi il totale.
const SCORE_COUNT: f64 = 3.0;
const BONUS_COUNT: f64 = 1.0;
const TOTAL_AT: f64 = 4.5;
/// Titoli di coda: velocità (unità a 480 righe al secondo) e sosta con l'ultima riga al centro.
const CREDITS_SPEED: f32 = 70.0;
const CREDITS_HOLD: f64 = 2.0;
/// Start salta il finale solo dopo questo tempo (non lo salta il tasto della partita).
const SKIP_AFTER: f64 = 0.5;

/// Il rosso del timbro e dei fuochi (lo stesso dei pulsanti arcade della HOW TO PLAY).
const RED: Color = Color::new(230.0 / 255.0, 40.0 / 255.0, 40.0 / 255.0, 1.0);

/// Righe dei titoli di coda.
#[derive(Clone, Copy, PartialEq)]
enum Line {
    /// titolo grande, giallo
    Title(&'static str),
    /// titolo di una sezione, giallo
    Head(&'static str),
    /// voce, bianca
    Text(&'static str),
    Gap,
}

const CREDITS: &[Line] = &[
    Line::Title("PADD WS"),
    Line::Head("GAME DESIGN AND PROGRAMMING"),
    Line::Text("SCHERMOBIANCO"),
    Line::Head("PLATFORMS"),
    Line::Text("PC  WEB  RASPBERRY PI"),
    Line::Text("MISTER FPGA"),
    Line::Text("COMMODORE 64"),
    Line::Head("MUSIC AND SOUND"),
    Line::Text("ORIGINAL SID MUSIC"),
    Line::Text("SID SOUND EFFECTS"),
    Line::Text("ANNOUNCER VOICES"),
    Line::Head("THE CHALLENGERS"),
    Line::Text("ARCADE   TITAN   HAMMER"),
    Line::Text("TWIST   BLASTER   RUSH"),
    Line::Text("AND GUARDIAN"),
    // i lavori di altri usati nel gioco (THIRD_PARTY.md)
    Line::Head("THIRD-PARTY WORKS"),
    Line::Text("MUNRO FONT  ED MERRITT"),
    Line::Text("PONG SCORE FONT  PWNZOR.AK"),
    Line::Text("MISTER FRAMEWORK  SORGELIG"),
    Line::Text("SID EMULATION  DAG LEM  A. MELNIKOV"),
    Line::Text("VEXRISCV  SPINALHDL"),
    Line::Text("MACROQUAD  FEDOR LOGACHEV"),
    Line::Text("GILRS  SDL GAMECONTROLLERDB"),
    Line::Text("PYTHON ARCADE  PIGPIO"),
    Line::Head("SPECIAL THANKS"),
    Line::Text("THE MISTER FPGA COMMUNITY"),
    Line::Text("THE COMMODORE 64 SCENE"),
    Line::Gap,
    Line::Title("THANK YOU FOR PLAYING"),
];

impl Line {
    /// Spazio prima della riga (unità a 480 righe).
    fn advance(self) -> f32 {
        match self {
            Line::Title(_) | Line::Head(_) => 70.0,
            Line::Text(_) => 38.0,
            Line::Gap => 60.0,
        }
    }
}

/// y di ogni riga dei titoli rispetto all'inizio (unità a 480 righe).
fn credits_layout() -> Vec<(Line, f32)> {
    let mut y = 0.0;
    CREDITS
        .iter()
        .map(|&l| {
            y += l.advance();
            (l, y)
        })
        .collect()
}

/// Durata dello scorrimento dei titoli: dall'ingresso dal basso finché l'ultima riga arriva al
/// centro dello schermo.
fn credits_seconds() -> f64 {
    let last = credits_layout().last().map_or(0.0, |&(_, y)| y);
    ((20.0 + 240.0 + last) / CREDITS_SPEED) as f64
}

/// Parti del finale, in ordine.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Part {
    Congrats,
    Parade,
    Score,
    Champion,
    Credits,
    TheEnd,
}

/// Inizio di ogni parte (s) e fine del finale.
fn schedule() -> [(Part, f64); 7] {
    let credits = credits_seconds() + CREDITS_HOLD;
    let starts = [CONGRATS, PARADE, SCORE, CHAMPION, credits, THE_END];
    let parts = [
        Part::Congrats,
        Part::Parade,
        Part::Score,
        Part::Champion,
        Part::Credits,
        Part::TheEnd,
    ];
    let mut out = [(Part::TheEnd, 0.0); 7];
    let mut t = 0.0;
    for (i, (part, len)) in parts.into_iter().zip(starts).enumerate() {
        out[i] = (part, t);
        t += len;
    }
    out[6] = (Part::TheEnd, t); // fine
    out
}

/// Parte al tempo `t` e da quanto è cominciata; None a finale concluso.
fn part_at(t: f64) -> Option<(Part, f64)> {
    let s = schedule();
    (t < s[6].1).then(|| {
        let i = s[..6].iter().rposition(|&(_, start)| t >= start).unwrap_or(0);
        (s[i].0, t - s[i].1)
    })
}

// ------------------------------------------------------------------ fuochi

/// Fuochi d'artificio di `fireworks.py`, a 15 frame al secondo: il razzo sale per `RISE` frame,
/// poi lo scoppio con la gravità `G` (pixel a 480 righe per frame al quadrato).
const FW_FPS: f64 = 15.0;
const RISE: i32 = 14;
const G: f32 = 0.12;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Kind {
    Ring,
    Willow,
    Palm,
    Chrysanthemum,
    Crackle,
    Crossette,
}

const KINDS: [Kind; 6] = [
    Kind::Ring,
    Kind::Willow,
    Kind::Palm,
    Kind::Chrysanthemum,
    Kind::Crackle,
    Kind::Crossette,
];

#[derive(Clone, Copy, Debug)]
struct Firework {
    kind: Kind,
    /// punto dello scoppio: x in frazione della larghezza oltre i margini, y a 480 righe
    x: f32,
    y: f32,
    /// frame del lancio e seme delle scintille a caso
    start: i32,
    seed: u32,
}

/// Le scintille non si scuriscono: si diradano, sempre di più man mano che `k` scende.
fn alive(k: f32, i: i32, t: i32) -> bool {
    k > 0.0 && ((i * 7 + t * 3).rem_euclid(10) as f32) < k * 10.0
}

/// Lo spettacolo: un fuoco dopo l'altro, i sei tipi a turno, fino a poco prima della fine.
fn show() -> Vec<Firework> {
    let mut rng = Rng::new(0xF1AE_2026);
    let last = (CHAMPION * FW_FPS) as i32 - 30;
    let mut out = Vec::new();
    let mut start = 0;
    while start < last {
        out.push(Firework {
            kind: KINDS[out.len() % KINDS.len()],
            x: rng.below(1000) as f32 / 1000.0,
            y: 70.0 + rng.below(160) as f32,
            start,
            seed: rng.next_u32() | 1,
        });
        start += 6 + rng.below(8) as i32;
    }
    out
}

/// Pennello dei fuochi: coordinate a 480 righe portate nel campo.
struct Sky {
    sc: f32,
    /// x dello scoppio nel campo, y a 480 righe
    cx: f32,
    cy: f32,
}

impl Sky {
    /// Quadrato di lato 2s+1 pixel centrato in (x, y), coordinate a 480 righe dal centro dello
    /// scoppio.
    fn dot(&self, dx: f32, dy: f32, size: f32, c: Color) {
        let side = (2.0 * size + 1.0) * self.sc;
        draw_rectangle(
            self.cx + dx * self.sc - side / 2.0,
            (self.cy + dy) * self.sc - side / 2.0,
            side,
            side,
            c,
        );
    }

    /// `n` scintille in cerchio a velocità `speed`, con la resistenza dell'aria `drag`, la scia di
    /// `trail` punti e la vita di `life` frame.
    #[allow(clippy::too_many_arguments)] // i parametri dello scoppio, come in fireworks.py
    fn particles(&self, t: i32, n: i32, speed: f32, color: Color, life: f32, size: f32, trail: i32, drag: f32) {
        for a in 0..n {
            let ang = a as f32 * std::f32::consts::TAU / n as f32;
            for back in 0..=trail {
                let tt = (t - back * 2).max(0);
                let dist = speed * (1.0 - drag.powi(tt)) / (1.0 - drag);
                let x = dist * ang.cos();
                let y = dist * ang.sin() + G * (tt * tt) as f32 / 2.0;
                let k = (1.0 - tt as f32 / life).max(0.0) * (1.0 - back as f32 / (trail + 1) as f32);
                if alive(k, a + back, tt) {
                    self.dot(x, y, if back == 0 { size } else { 1.0 }, color);
                }
            }
        }
    }
}

impl Firework {
    /// Il fuoco al frame `f` dello spettacolo; `white`, `yellow` dalla configurazione.
    fn draw(&self, app: &App, f: i32, white: Color, yellow: Color) {
        let age = f - self.start;
        if age < 0 {
            return;
        }
        let sc = app.scale();
        let w = app.renderer.world_w / sc; // larghezza a 480 righe
        let margin = 130.0_f32.min(w / 4.0);
        let sky = Sky {
            sc,
            cx: (margin + self.x * (w - 2.0 * margin)) * sc,
            cy: self.y,
        };
        if age < RISE {
            // razzo: un punto che sale dal fondo con una scia corta
            let k = age as f32 / RISE as f32;
            let ry = 480.0 - (480.0 - self.y) * (1.0 - (1.0 - k).powi(2)) - self.y;
            sky.dot(0.0, ry, 2.0, white);
            for t in 1..3 {
                sky.dot(0.0, ry + t as f32 * 6.0, 1.0, yellow);
            }
            return;
        }
        let t = age - RISE;
        match self.kind {
            Kind::Ring => sky.particles(t, 20, 4.0, yellow, 26.0, 2.0, 0, 0.97),
            // salice: scie lunghe dorate che ricadono piano
            Kind::Willow => sky.particles(t, 24, 2.6, yellow, 50.0, 1.0, 6, 0.95),
            // palma: pochi rami grossi
            Kind::Palm => sky.particles(t, 7, 4.5, RED, 34.0, 3.0, 4, 0.97),
            // crisantemo: due anelli, bianco dentro e rosso fuori
            Kind::Chrysanthemum => {
                sky.particles(t, 16, 2.2, white, 28.0, 2.0, 0, 0.97);
                sky.particles(t, 28, 4.2, RED, 30.0, 2.0, 0, 0.97);
            }
            // crepitio: scintille sparse che sfarfallano
            Kind::Crackle => {
                let mut rng = Rng::new(self.seed);
                for i in 0..60 {
                    let ang = rng.below(6283) as f32 / 1000.0;
                    let v = 0.5 + rng.below(3500) as f32 / 1000.0;
                    let dist = v * t.min(18) as f32;
                    let x = dist * ang.cos();
                    let y = dist * ang.sin() + G * (t * t) as f32 / 3.0;
                    if t < 40 && (t + i) % 3 != 0 {
                        sky.dot(x, y, 1.0, if (t + i) % 2 == 1 { white } else { yellow });
                    }
                }
            }
            // cometa che si divide: quattro rami che dopo un po' si aprono di nuovo in quattro
            Kind::Crossette => {
                const SPLIT: i32 = 12;
                for a in 0..4 {
                    let ang = a as f32 * std::f32::consts::FRAC_PI_2 + std::f32::consts::FRAC_PI_4;
                    let tt = t.min(SPLIT) as f32;
                    let bx = 4.5 * tt * ang.cos();
                    let by = 4.5 * tt * ang.sin() + G * tt * tt / 2.0;
                    if t < SPLIT {
                        sky.dot(bx, by, 2.0, white);
                        continue;
                    }
                    let u = t - SPLIT;
                    for b in 0..4 {
                        let ang2 = ang + (b as f32 - 1.5) * 0.5;
                        let x = bx + 2.5 * u as f32 * ang2.cos();
                        let y = by + 2.5 * u as f32 * ang2.sin() + G * (u * u) as f32 / 2.0;
                        let k = (1.0 - u as f32 / 22.0).max(0.0);
                        if alive(k, a * 4 + b, u) {
                            sky.dot(x, y, 2.0, yellow);
                        }
                    }
                }
            }
        }
    }
}

// ------------------------------------------------------------------ scena

/// Il finale della CHALLENGE.
pub struct Ending {
    t: f64,
    /// punti prima del premio del campione, il premio (vittoria e partita perfetta dell'ultimo
    /// livello) e il totale
    score: u32,
    bonus: u32,
    total: u32,
    fireworks: Vec<Firework>,
    credits: Vec<(Line, f32)>,
    /// voce "YOU WIN!" detta, timbri e avversari già annunciati con il loro suono
    voiced: bool,
    sounds: usize,
}

impl Ending {
    /// Il giocatore ha battuto l'ultimo avversario, che ha fatto `opponent_points` punti: il
    /// premio del livello come a ogni livello vinto (`Score::win_bonus`), qui il premio del
    /// campione.
    pub fn new(app: &mut App, opponent_points: u16) -> Self {
        let run = app.run.as_mut().expect("finale senza CHALLENGE");
        let (win, perfect) = Score::win_bonus(run.level, opponent_points);
        let score = run.score;
        run.score = run.score.saturating_add(win + perfect);
        run.remember(LEVELS as u8 + 1);
        Self {
            t: 0.0,
            score,
            bonus: win + perfect,
            total: run.score,
            fireworks: show(),
            credits: credits_layout(),
            voiced: false,
            sounds: 0,
        }
    }

    /// Per la verifica automatica: porta il finale all'inizio della parte `part`, più `after` s.
    pub fn skip_to(&mut self, part: Part, after: f64) {
        let start = schedule().iter().find(|(p, _)| *p == part).map_or(0.0, |&(_, s)| s);
        self.t = start + after;
        self.voiced = self.t > YOU_WIN_AT;
        self.sounds = usize::MAX;
    }

    pub fn update(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
        self.t += dt;
        let skip = self.t >= SKIP_AFTER
            && (input::any_pressed(&START_KEYS) || !touch::taps(&app.renderer).is_empty() || app.knob_clicked());
        if input::pressed(KeyCode::Escape) || skip {
            return Some(challenge_ui::finish(app));
        }
        if !self.voiced && self.t >= YOU_WIN_AT {
            self.voiced = true;
            app.say(&app.assets.you_win);
        }
        // sfilata: un colpo per ogni avversario che entra e per ogni timbro
        if let Some((Part::Parade, at)) = part_at(self.t) {
            let due = (0..PaddleKind::COUNT)
                .map(|i| i as f64 * PARADE_STEP)
                .flat_map(|s| [s, s + STAMP_AFTER])
                .take_while(|&s| at >= s)
                .count();
            while self.sounds < due {
                app.play(if self.sounds.is_multiple_of(2) { Event::Wall } else { Event::Hit });
                self.sounds += 1;
            }
        }
        part_at(self.t).is_none().then(|| challenge_ui::finish(app))
    }

    pub fn draw(&self, app: &App) {
        app.renderer.fill(BLACK);
        let Some((part, at)) = part_at(self.t) else { return };
        let colors = &app.cfg.colors;
        let (white, yellow) = (App::color(colors.white), App::color(colors.accent));
        let flash = |period: f64| if (at / period) as i64 % 2 == 0 { yellow } else { white };
        match part {
            Part::Congrats => {
                text(app, "CONGRATULATIONS!", 60.0, 220.0, flash(0.5));
                if at >= YOU_WIN_AT {
                    text(app, "YOU WIN!", 40.0, 290.0, white);
                }
            }
            Part::Parade => self.draw_parade(app, at, white, yellow),
            Part::Score => self.draw_score(app, at, white, yellow),
            Part::Champion => {
                let f = (at * FW_FPS) as i32;
                for fw in &self.fireworks {
                    fw.draw(app, f, white, yellow);
                }
                text(app, "YOU ARE THE", 30.0, 360.0, white);
                text(app, "PADD WS CHAMPION", 50.0, 410.0, yellow);
            }
            Part::Credits => self.draw_credits(app, at, white, yellow),
            Part::TheEnd => text(app, "THE END", 60.0, 240.0, flash(0.66)),
        }
    }

    /// I sette avversari, uno al secondo, con le racchette vere e il timbro DEFEATED.
    fn draw_parade(&self, app: &App, at: f64, white: Color, yellow: Color) {
        let r = &app.renderer;
        let (sc, u) = (app.scale(), unit(app));
        let p = &app.params;
        text(app, "YOUR OPPONENTS", 40.0, 50.0, yellow);
        let zoom = 1.2;
        let look = Look {
            body: white,
            mark: yellow,
            detail: yellow,
        };
        for (i, kind) in PaddleKind::ALL.into_iter().enumerate() {
            let age = at - i as f64 * PARADE_STEP;
            if age < 0.0 {
                break;
            }
            let x = r.world_w * (i as f32 + 0.5) / PaddleKind::COUNT as f32;
            let cy = 185.0 * sc; // dall'alto
            let shape = Shape {
                kind: Some(kind),
                x,
                y: r.world_h - cy, // y del core, verso l'alto
                w: to_f32(p.pad_width) * zoom,
                h: to_f32(p.kinds[kind as usize].height) * zoom,
                front: 1.0,
                tilt: if kind == PaddleKind::Twist { TWIST_MAX_TILT } else { 0.0 },
                dash: None,
                preview: true,
            };
            draw_paddle(r, &shape, u * zoom, look);
            r.text_centered(kind.name(), &app.assets.font_text, 22.0 * sc, x, 290.0 * sc, 0.0, white);
            if age >= STAMP_AFTER {
                stamp(app, x - 2.0 * sc, cy + 15.0 * sc);
            }
        }
    }

    /// SCORE che sale, il premio del campione, poi il totale.
    fn draw_score(&self, app: &App, at: f64, white: Color, yellow: Color) {
        text(app, "FINAL SCORE", 40.0, 80.0, yellow);
        let k = (at / SCORE_COUNT).min(1.0);
        let row = |label: &str, value: String, size: f32, y: f32, color: Color| {
            let sc = app.scale();
            let (r, font) = (&app.renderer, &app.assets.font_text);
            let cx = r.world_w / 2.0;
            r.text_centered(label, font, size * sc, cx - 110.0 * sc, y * sc, 0.0, color);
            r.text_centered(&value, font, size * sc, cx + 110.0 * sc, y * sc, 0.0, color);
        };
        row("SCORE", format!("{:07}", (self.score as f64 * k) as u32), 30.0, 160.0, white);
        if at >= SCORE_COUNT {
            let b = ((at - SCORE_COUNT) / BONUS_COUNT).min(1.0);
            row(
                "CHAMPION BONUS",
                format!("+{:06}", (self.bonus as f64 * b) as u32),
                30.0,
                210.0,
                yellow,
            );
        }
        if at >= TOTAL_AT {
            row("TOTAL", format!("{:07}", self.total), 40.0, 290.0, white);
        }
    }

    /// I titoli che salgono dal basso.
    fn draw_credits(&self, app: &App, at: f64, white: Color, yellow: Color) {
        let sc = app.scale();
        let h = app.renderer.world_h / sc;
        let scroll = (at as f32 * CREDITS_SPEED).min((credits_seconds() as f32) * CREDITS_SPEED);
        let top = h + 20.0 - scroll;
        for &(line, y) in &self.credits {
            let y = top + y;
            if y < -30.0 || y > h + 30.0 {
                continue;
            }
            match line {
                Line::Title(s) => text(app, s, 50.0, y, yellow),
                Line::Head(s) => text(app, s, 30.0, y, yellow),
                Line::Text(s) => text(app, s, 30.0, y, white),
                Line::Gap => {}
            }
        }
    }
}

/// Testo centrato in orizzontale sulla riga `y` (unità a 480 righe dall'alto).
fn text(app: &App, s: &str, size: f32, y: f32, color: Color) {
    let sc = app.scale();
    let r = &app.renderer;
    r.text_centered(s, &app.assets.font_text, size * sc, r.world_w / 2.0, y * sc, 0.0, color);
}

/// Timbro rosso inclinato "DEFEATED" centrato in (x, y), coordinate di disegno.
fn stamp(app: &App, x: f32, y: f32) {
    let sc = app.scale();
    let angle: f32 = -18f32.to_radians(); // in salita verso destra
    let (sin, cos) = angle.sin_cos();
    let (hw, hh) = (55.0 * sc, 15.0 * sc);
    let corner = |dx: f32, dy: f32| vec2(x + dx * cos - dy * sin, y + dx * sin + dy * cos);
    let pts = [corner(-hw, -hh), corner(hw, -hh), corner(hw, hh), corner(-hw, hh)];
    for i in 0..4 {
        let (a, b) = (pts[i], pts[(i + 1) % 4]);
        draw_line(a.x, a.y, b.x, b.y, 2.0 * sc, RED);
    }
    app.renderer
        .text_centered("DEFEATED", &app.assets.font_text, 20.0 * sc, x, y, angle, RED);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_parts_follow_each_other_and_the_ending_lasts_about_a_minute() {
        assert_eq!(part_at(0.0), Some((Part::Congrats, 0.0)));
        assert_eq!(part_at(CONGRATS + 0.5).map(|p| p.0), Some(Part::Parade));
        assert_eq!(part_at(CONGRATS + PARADE).map(|p| p.0), Some(Part::Score));
        assert_eq!(part_at(CONGRATS + PARADE + SCORE + 1.0).map(|p| p.0), Some(Part::Champion));
        let end = schedule()[6].1;
        assert_eq!(part_at(end - 0.1).map(|p| p.0), Some(Part::TheEnd));
        assert_eq!(part_at(end), None);
        // titoli lenti: un paio di righe al secondo, il finale tra i 45 s e il minuto
        assert!((45.0..62.0).contains(&end), "{end}");
    }

    #[test]
    fn sparks_thin_out_instead_of_fading() {
        // piene all'inizio, sempre meno man mano che la vita finisce, nessuna alla fine
        let count = |k: f32| (0..100).filter(|&i| alive(k, i, 3)).count();
        assert_eq!(count(1.0), 100);
        assert!(count(0.5) < 70 && count(0.5) > 30);
        assert_eq!(count(0.0), 0);
    }

    #[test]
    fn the_show_uses_all_six_kinds_and_ends_before_the_part() {
        let show = show();
        for kind in KINDS {
            assert!(show.iter().any(|f| f.kind == kind));
        }
        assert!(show.iter().all(|f| f.start < (CHAMPION * FW_FPS) as i32 - 30));
    }
}
