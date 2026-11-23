//! Titoli disegnati a pixel (`assets/titles`, generati da tools/gen_title_assets.py): i nomi dei
//! sette avversari e di OMEGA nelle presentazioni della scalata, HERE COMES A NEW CHALLENGER!,
//! WARNING! (l'allarme prima di OMEGA), PERFECT e il logo del menu in NEXT (`menu_logo`).
//! Si disegnano con `Renderer::art_centered` alla grandezza delle scritte a 1x (un pixel della
//! grafica per pixel arcade), o a multipli interi nelle animazioni.
//!
//! Colori dei ruoli della palette (`paint`): bianco e giallo sono il bianco e l'accento della
//! configurazione (`colors.white`, `colors.accent`), come le scritte; il giallo scuro è l'accento
//! scurito (`DARK_YELLOW`), con la stessa tinta, così segue anche un accento diverso; nero, grigi e
//! rossi restano quelli della palette, che nella configurazione non hanno un corrispondente.

use macroquad::prelude::*;
use paddws_core::PaddleKind;

use crate::config::Colors;
use crate::render::{ART_ROLES, ArtPaint, ArtPart, PixelArt, Renderer};

/// Ruoli della palette (indici dei PNG, come in `assets/titles/titles.json`) e, per `ArtPaint`,
/// la sagoma.
pub const SILHOUETTE: usize = 0;
pub const BLACK_ROLE: usize = 1;
pub const WHITE_ROLE: usize = 2;
pub const YELLOW_ROLE: usize = 3;
pub const DARK_YELLOW_ROLE: usize = 4;
const GRAY_ROLE: usize = 5;
const DARK_GRAY_ROLE: usize = 6;
const RED_ROLE: usize = 7;
const DARK_RED_ROLE: usize = 8;

/// Nomi dei ruoli nell'ordine della palette, come in `titles.json`.
#[cfg(test)]
const ROLE_NAMES: [&str; ART_ROLES] =
    ["transparent", "black", "white", "yellow", "dark_yellow", "gray", "dark_gray", "red", "dark_red"];

/// Giallo scuro: l'accento moltiplicato per questo fattore (con l'accento di default viene circa
/// il giallo scuro della palette, 150, 105, 0).
const DARK_YELLOW: f32 = 0.55;

macro_rules! title_png {
    ($name:literal) => {
        include_bytes!(concat!("../../../assets/titles/", $name, ".png"))
    };
}

/// PNG del nome dell'avversario `kind`.
fn name_png(kind: PaddleKind) -> &'static [u8] {
    match kind {
        PaddleKind::Arcade => title_png!("name_arcade"),
        PaddleKind::Titan => title_png!("name_titan"),
        PaddleKind::Hammer => title_png!("name_hammer"),
        PaddleKind::Twist => title_png!("name_twist"),
        PaddleKind::Blaster => title_png!("name_blaster"),
        PaddleKind::Rush => title_png!("name_rush"),
        PaddleKind::Guardian => title_png!("name_guardian"),
    }
}

pub struct Titles {
    names: [PixelArt; PaddleKind::COUNT],
    /// il nome del boss segreto: sigillo omega con OMEGA sotto
    pub omega: PixelArt,
    pub challenger: PixelArt,
    /// WARNING!, la targa rossa dell'allarme prima di OMEGA
    pub warning: PixelArt,
    pub perfect: PixelArt,
    /// VS dello schermo VS, nello stile di PERFECT
    pub vs: PixelArt,
    /// PADD con tre strisce per lato (`menu_logo.png`): palette 0 trasparente, 1-5 l'accento
    /// sempre più scuro (`logo_paint`)
    pub menu_logo: PixelArt,
}

impl Titles {
    pub fn load() -> Self {
        Self {
            names: PaddleKind::ALL.map(|k| PixelArt::from_png(name_png(k))),
            omega: PixelArt::from_png(title_png!("name_omega")),
            challenger: PixelArt::from_png(title_png!("challenger")),
            warning: PixelArt::from_png(title_png!("warning")),
            perfect: PixelArt::from_png(title_png!("perfect")),
            vs: PixelArt::from_png(title_png!("vs")),
            menu_logo: PixelArt::from_png(title_png!("menu_logo")),
        }
    }

    /// Nome dell'avversario `kind`, come nelle presentazioni.
    pub fn name(&self, kind: PaddleKind) -> &PixelArt {
        &self.names[kind as usize]
    }
}

fn rgb(r: u8, g: u8, b: u8) -> Color {
    Color::from_rgba(r, g, b, 255)
}

/// Il riflesso di PERFECT e del VS: una banda in diagonale, colonna per colonna della grafica `art`
/// (centrata in `c`, a `times` pixel per pixel), sulle lettere e sul filetto (bianco, giallo e giallo
/// scuro) ma non sul bordo; i pixel (col, riga) con `0 <= col + riga - g < width` diventano `shine`.
#[allow(clippy::too_many_arguments)]
pub fn draw_glint(r: &Renderer, art: &PixelArt, times: f32, c: Vec2, paint: &ArtPaint, shine: Color, g: f32, width: f32) {
    let mut glint = only(paint, &[WHITE_ROLE, YELLOW_ROLE, DARK_YELLOW_ROLE]);
    for color in glint.iter_mut().flatten() {
        *color = shine;
    }
    for col in 0..art.w as i32 {
        let r0 = (g - col as f32).ceil().max(0.0);
        let r1 = (g + width - col as f32).ceil().min(art.h);
        if r1 > r0 {
            let src = Rect::new(col as f32, r0, 1.0, r1 - r0);
            r.art_centered(art, times, c.x, c.y, 0.0, ArtPart::Area(src), &glint);
        }
    }
}

/// Posizione della banda del riflesso `frame` frame dopo l'inizio della scritta: parte dopo `first`
/// frame, ogni `period` frame, a 4 righe a frame da `-20` (prima del bordo sinistro). None prima.
pub fn glint_offset(frame: f32, first: f32, period: f32) -> Option<f32> {
    (frame >= first).then(|| (frame - first) % period * 4.0 - 20.0)
}

/// Colori dei ruoli con i colori della configurazione (vedi l'inizio del modulo).
pub fn paint(colors: &Colors) -> ArtPaint {
    let accent = Color::from_rgba(colors.accent[0], colors.accent[1], colors.accent[2], 255);
    let mut p: ArtPaint = [None; ART_ROLES];
    p[BLACK_ROLE] = Some(BLACK);
    p[WHITE_ROLE] = Some(Color::from_rgba(colors.white[0], colors.white[1], colors.white[2], 255));
    p[YELLOW_ROLE] = Some(accent);
    p[DARK_YELLOW_ROLE] = Some(Color::new(accent.r * DARK_YELLOW, accent.g * DARK_YELLOW, accent.b * DARK_YELLOW, 1.0));
    p[GRAY_ROLE] = Some(rgb(110, 110, 110));
    p[DARK_GRAY_ROLE] = Some(rgb(55, 55, 55));
    p[RED_ROLE] = Some(rgb(200, 30, 30));
    p[DARK_RED_ROLE] = Some(rgb(90, 10, 10));
    p
}

/// I colori del VS: oro. Il VS usa gli stessi ruoli di PERFECT (le tre fasce e il bordo) ma qui
/// diventano le tre fasce dell'oro, dalla più chiara in alto, e un bordo marrone scuro.
pub fn vs_paint() -> ArtPaint {
    let mut p: ArtPaint = [None; ART_ROLES];
    p[WHITE_ROLE] = Some(rgb(245, 215, 120));
    p[YELLOW_ROLE] = Some(rgb(215, 165, 40));
    p[DARK_YELLOW_ROLE] = Some(rgb(140, 95, 15));
    p[DARK_RED_ROLE] = Some(rgb(60, 35, 5));
    p
}

/// Logo del menu: livelli del giallo d'accento dei colori 1-5 della sua palette e angolo in alto a
/// sinistra nel campo 320x240 (come `assets/titles/menu_logo.json`).
pub const LOGO_LEVELS: [f32; 5] = [1.0, 0.72, 0.48, 0.3, 0.16];
pub const LOGO_POSITION: (f32, f32) = (76.0, 32.0);

/// Colori del logo del menu: l'accento della configurazione per i livelli di `LOGO_LEVELS`.
pub fn logo_paint(colors: &Colors) -> ArtPaint {
    let accent = Color::from_rgba(colors.accent[0], colors.accent[1], colors.accent[2], 255);
    let mut p: ArtPaint = [None; ART_ROLES];
    for (i, k) in LOGO_LEVELS.iter().enumerate() {
        p[i + 1] = Some(Color::new(accent.r * k, accent.g * k, accent.b * k, 1.0));
    }
    p
}

/// Tutta la grafica in un colore solo (la sagoma).
pub fn solid(color: Color) -> ArtPaint {
    let mut p: ArtPaint = [None; ART_ROLES];
    p[SILHOUETTE] = Some(color);
    p
}

/// Solo i ruoli `roles`, nei colori di `paint`.
pub fn only(paint: &ArtPaint, roles: &[usize]) -> ArtPaint {
    let mut p: ArtPaint = [None; ART_ROLES];
    for &r in roles {
        p[r] = paint[r];
    }
    p
}

/// `paint` con bianco e giallo scambiati (i lampeggi).
pub fn swap_white_yellow(paint: &ArtPaint) -> ArtPaint {
    let mut p = *paint;
    p.swap(WHITE_ROLE, YELLOW_ROLE);
    p
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_palette_roles_match_titles_json() {
        let spec: serde_json::Value = serde_json::from_str(include_str!("../../../assets/titles/titles.json")).unwrap();
        let palette: Vec<&str> = spec["palette"].as_array().unwrap().iter().map(|v| v.as_str().unwrap()).collect();
        assert_eq!(palette, ROLE_NAMES);
        assert_eq!(ROLE_NAMES[WHITE_ROLE], "white");
        assert_eq!(ROLE_NAMES[YELLOW_ROLE], "yellow");
        assert_eq!(ROLE_NAMES[DARK_YELLOW_ROLE], "dark_yellow");
        assert_eq!(ROLE_NAMES[BLACK_ROLE], "black");
        assert_eq!(ROLE_NAMES[DARK_RED_ROLE], "dark_red");
        // ogni grafica dell'elenco è inclusa con il suo nome
        let titles = spec["titles"].as_object().unwrap();
        let names: Vec<String> = PaddleKind::ALL.iter().map(|k| format!("name_{}", k.name().to_lowercase())).collect();
        let others = ["name_omega", "challenger", "warning", "perfect", "vs"];
        for n in names.iter().map(String::as_str).chain(others) {
            assert!(titles.contains_key(n), "{n}");
        }
        assert_eq!(titles.len(), names.len() + others.len());
    }

    #[test]
    fn the_menu_logo_matches_its_json() {
        let spec: serde_json::Value = serde_json::from_str(include_str!("../../../assets/titles/menu_logo.json")).unwrap();
        let levels: Vec<f32> = spec["levels"].as_array().unwrap().iter().map(|v| v.as_f64().unwrap() as f32).collect();
        assert_eq!(levels, LOGO_LEVELS);
        let pos = (spec["position"]["x"].as_f64().unwrap() as f32, spec["position"]["y"].as_f64().unwrap() as f32);
        assert_eq!(pos, LOGO_POSITION);
        // centrato nel campo 320x240
        let w = spec["size"][0].as_f64().unwrap() as f32;
        assert!((LOGO_POSITION.0 + w / 2.0 - 160.0).abs() <= 0.5);
        let p = logo_paint(&Colors::default());
        assert!(p[SILHOUETTE].is_none() && p[0].is_none() && p[6].is_none());
        let (a, d) = (p[1].unwrap(), p[5].unwrap());
        assert!((d.r / a.r - 0.16).abs() < 1e-6);
    }

    #[test]
    fn the_dark_yellow_follows_the_accent() {
        let p = paint(&Colors::default());
        let (y, d) = (p[YELLOW_ROLE].unwrap(), p[DARK_YELLOW_ROLE].unwrap());
        assert!((d.r / y.r - DARK_YELLOW).abs() < 1e-6 && (d.g / y.g - DARK_YELLOW).abs() < 1e-6);
        // con l'accento di default, vicino al giallo scuro della palette
        assert!((d.r * 255.0 - 150.0).abs() < 15.0 && (d.g * 255.0 - 105.0).abs() < 15.0, "{d:?}");
        assert!(p[SILHOUETTE].is_none());
    }
}
