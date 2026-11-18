//! Rendering: scaling letterbox del campo, testo nitido a ogni risoluzione, filtro CRT.
//!
//! Si disegna in coordinate mondo (pixel del campo, y verso il basso come lo
//! schermo); il core usa y verso l'alto, la conversione è in `screen_y`.

use macroquad::miniquad::{BlendFactor, BlendState, BlendValue, Equation, PipelineParams};
use macroquad::prelude::*;

use crate::config::Crt;

/// Oltre questo numero di pixel il CRT lavora a risoluzione ridotta e poi ingrandisce:
/// le scanline emulate sono ~240, quindi 720p bastano e il costo resta nel budget del frame.
const CRT_MAX_PIXELS: f32 = 1280.0 * 720.0;

/// Grandezze delle scritte in pixel arcade (lo schermo 320x240 del core MiSTer): Press Start 2P
/// è disegnato su una griglia di 8x8 pixel ed è netto solo a multipli interi di 8, quindi le
/// scritte sono a 1x o a 2x, mai in mezzo. A 2x solo GAME OVER e YOU WIN (le bitmap della fine
/// partita, `attract`, e YOU WIN! del finale); tutto il resto a 1x. I titoli disegnati a pixel
/// (`PixelArt`: i nomi degli avversari, HERE COMES A NEW CHALLENGER!, PERFECT) hanno un pixel
/// della grafica per pixel arcade, come le scritte a 1x.
pub const TEXT_1X: f32 = 8.0;
pub const TEXT_2X: f32 = 16.0;

/// Font delle scritte: un font TTF qualsiasi disegnato da macroquad (il punteggio) oppure un font
/// a pixel (`PixelFont`, le scritte), con le metriche dei glifi per centrare sull'inchiostro
/// visibile (la larghezza di macroquad è la somma degli avanzamenti, spazi laterali compresi).
pub struct GameFont {
    font: Font,
    metrics: fontdue::Font,
    pixel: Option<PixelFont>,
}

impl GameFont {
    pub fn from_bytes(bytes: &'static [u8]) -> Self {
        let mut font = load_ttf_font_from_bytes(bytes).expect("font incluso nell'eseguibile");
        font.set_filter(FilterMode::Nearest);
        let metrics =
            fontdue::Font::from_bytes(bytes, fontdue::FontSettings::default()).expect("font incluso nell'eseguibile");
        Self {
            font,
            metrics,
            pixel: None,
        }
    }

    /// Font a pixel disegnato su una griglia di `em` pixel (8 per Press Start 2P): vedi `PixelFont`.
    pub fn pixel_from_bytes(bytes: &'static [u8], em: u32) -> Self {
        let mut font = Self::from_bytes(bytes);
        font.pixel = Some(PixelFont::new(&font.metrics, em));
        font
    }

    /// Estensione orizzontale dell'inchiostro (sinistra, destra) in pixel rasterizzati.
    fn ink_span(&self, text: &str, px: f32) -> (f32, f32) {
        let mut pen = 0.0;
        let (mut left, mut right) = (f32::MAX, f32::MIN);
        for ch in text.chars() {
            let m = self.metrics.metrics(ch, px);
            if m.width > 0 {
                left = left.min(pen + m.xmin as f32);
                right = right.max(pen + m.xmin as f32 + m.width as f32);
            }
            pen += m.advance_width;
        }
        if left > right { (0.0, pen) } else { (left, right) }
    }
}

/// Font a pixel (Press Start 2P), netto a ogni risoluzione.
///
/// Il metodo: i glifi si rasterizzano una volta sola alla grandezza di disegno del font (`em`
/// pixel, 8), con la copertura portata a 0 o 1, in una texture con il filtro Nearest; a schermo
/// ogni pixel del font diventa un quadrato di `k` x `k` pixel fisici con `k` intero (la grandezza
/// chiesta, arrotondata al multiplo intero più vicino, per difetto a metà strada: con il campo a
/// 4,5 pixel fisici per pixel arcade la 1x è a 4), e l'origine della scritta cade su un pixel
/// fisico. Così i pixel del font restano quadrati e pieni, senza grigi sui bordi, anche quando la
/// scala del campo non è intera (1080/240 = 4,5), con l'HiDPI, nel browser e sul Deck, e anche nel
/// buffer del CRT (che ha la sua scala). Rispetto al testo di macroquad (rasterizzato a ogni
/// grandezza) non c'è un atlante che cresce: la texture è una, piccola, fatta all'avvio, e qualunque
/// grandezza (anche una che cambia a ogni frame) costa uguale. Il prezzo è che la scritta può
/// venire fino a un quarto più piccola o più grande del previsto quando la scala non è intera: le
/// schermate lasciano margine.
struct PixelFont {
    texture: Texture2D,
    /// pixel del font per em (la grandezza a cui è disegnato)
    em: f32,
    /// glifi da ' ' a '~'; gli altri caratteri diventano '?'
    glyphs: Vec<Glyph>,
}

/// Glifo nella texture del font a pixel; misure in pixel del font, con y verso il basso e
/// l'origine all'inizio della linea di base.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct Glyph {
    src: Rect,
    left: f32,
    top: f32,
    advance: f32,
}

/// Primo e ultimo carattere del font a pixel.
const PIXEL_FIRST: char = ' ';
const PIXEL_LAST: char = '~';

/// Glifi rasterizzati: l'immagine in alfa (larghezza, altezza, un byte per pixel, 0 o 255) e i
/// glifi. A parte dalla texture per i test, che non hanno un contesto grafico.
fn rasterize_pixel_font(metrics: &fontdue::Font, em: u32) -> (u32, u32, Vec<u8>, Vec<Glyph>) {
    // pixel accesi di ogni glifo (copertura almeno a metà) e il loro riquadro: fontdue lascia
    // righe e colonne vuote attorno, che non devono contare nell'inchiostro
    let shapes: Vec<_> = (PIXEL_FIRST..=PIXEL_LAST)
        .map(|ch| {
            let (m, cover) = metrics.rasterize(ch, em as f32);
            let lit: Vec<(i32, i32)> = (0..cover.len())
                .filter(|&j| cover[j] >= 128)
                .map(|j| ((j % m.width) as i32, (j / m.width) as i32))
                .collect();
            let x0 = lit.iter().map(|p| p.0).min().unwrap_or(0);
            let y0 = lit.iter().map(|p| p.1).min().unwrap_or(0);
            let x1 = lit.iter().map(|p| p.0 + 1).max().unwrap_or(0);
            let y1 = lit.iter().map(|p| p.1 + 1).max().unwrap_or(0);
            // la riga 0 della bitmap di fontdue è a ymin + height sopra la linea di base
            let glyph = Glyph {
                src: Rect::new(0.0, 0.0, (x1 - x0) as f32, (y1 - y0) as f32),
                left: (m.xmin + x0) as f32,
                top: (y0 - m.ymin - m.height as i32) as f32,
                advance: m.advance_width,
            };
            (glyph, lit.into_iter().map(move |(x, y)| ((x - x0) as u32, (y - y0) as u32)))
        })
        .collect();
    // celle con un pixel vuoto attorno: il filtro Nearest non prende mai i vicini
    let cell = shapes.iter().map(|(g, _)| g.src.w.max(g.src.h)).fold(1.0, f32::max) as u32 + 2;
    let cols = 16;
    let rows = (shapes.len() as u32).div_ceil(cols);
    // lati a potenze di 2: le GPU GLES2 più vecchie (il Pi 2 del Deck) le vogliono così
    let (w, h) = ((cols * cell).next_power_of_two(), (rows * cell).next_power_of_two());
    let mut alpha = vec![0u8; (w * h) as usize];
    let glyphs = shapes
        .into_iter()
        .enumerate()
        .map(|(i, (mut g, lit))| {
            let (x0, y0) = ((i as u32 % cols) * cell + 1, (i as u32 / cols) * cell + 1);
            for (x, y) in lit {
                alpha[((y0 + y) * w + x0 + x) as usize] = 255;
            }
            (g.src.x, g.src.y) = (x0 as f32, y0 as f32);
            g
        })
        .collect();
    (w, h, alpha, glyphs)
}

impl PixelFont {
    fn new(metrics: &fontdue::Font, em: u32) -> Self {
        let (w, h, alpha, glyphs) = rasterize_pixel_font(metrics, em);
        let rgba: Vec<u8> = alpha.iter().flat_map(|&a| [255, 255, 255, a]).collect();
        let texture = Texture2D::from_rgba8(w as u16, h as u16, &rgba);
        texture.set_filter(FilterMode::Nearest);
        Self {
            texture,
            em: em as f32,
            glyphs,
        }
    }

    fn glyph(&self, ch: char) -> Glyph {
        let ch = if (PIXEL_FIRST..=PIXEL_LAST).contains(&ch) { ch } else { '?' };
        self.glyphs[ch as usize - PIXEL_FIRST as usize]
    }

    /// Glifi di `text` con la posizione della penna, in pixel del font.
    fn layout<'a>(&'a self, text: &'a str) -> impl Iterator<Item = (Glyph, f32)> + 'a {
        let mut pen = 0.0;
        text.chars().map(move |ch| {
            let g = self.glyph(ch);
            let at = pen;
            pen += g.advance;
            (g, at)
        })
    }

    fn advance(&self, text: &str) -> f32 {
        self.layout(text).map(|(g, _)| g.advance).sum()
    }

    /// Riquadro dell'inchiostro (sinistra, alto, destra, basso) in pixel del font; None se il
    /// testo non ha inchiostro (vuoto o solo spazi).
    fn ink(&self, text: &str) -> Option<(f32, f32, f32, f32)> {
        self.layout(text)
            .filter(|(g, _)| g.src.w > 0.0)
            .map(|(g, pen)| (pen + g.left, g.top, pen + g.left + g.src.w, g.top + g.src.h))
            .reduce(|a, b| (a.0.min(b.0), a.1.min(b.1), a.2.max(b.2), a.3.max(b.3)))
    }
}

/// Ruoli dei colori di una grafica a pixel (`PixelArt`): l'indice della palette dei PNG di
/// `assets/titles` (0 è il trasparente). In `ArtPaint` l'indice 0 vale invece per la sagoma.
pub const ART_ROLES: usize = 9;

/// Colore di ogni ruolo di una grafica a pixel (None: quei pixel non si disegnano). L'indice 0 è la
/// sagoma: tutti i pixel non trasparenti in un colore solo (le immagini fantasma, i lampi).
pub type ArtPaint = [Option<Color>; ART_ROLES];

/// Che cosa disegnare di una grafica a pixel: tutta o un rettangolo (in pixel della grafica), al suo
/// posto nella grafica.
#[derive(Clone, Copy, Debug)]
pub enum ArtPart {
    Whole,
    Area(Rect),
}

/// Grafica a pixel a palette (le scritte disegnate di `assets/titles`), netta come `PixelFont`:
/// ogni pixel della grafica diventa un quadrato di `k` x `k` pixel fisici con `k` intero e
/// l'origine cade su un pixel fisico (`Renderer::art_centered`).
///
/// L'indice della palette è il ruolo del colore, non il colore: la texture è un atlante di
/// maschere bianche, una per ruolo (più la sagoma), che si disegnano ciascuna nel suo colore. Così
/// bianco e giallo seguono i colori della configurazione e la stessa grafica si disegna anche in
/// un colore solo.
pub struct PixelArt {
    pub w: f32,
    pub h: f32,
    texture: Texture2D,
    /// celle dell'atlante, una per ruolo
    cells: Vec<Option<Rect>>,
}

/// Pixel di una grafica a palette: indici riga per riga. A parte dalla texture per i test.
struct ArtPixels {
    w: usize,
    h: usize,
    index: Vec<u8>,
}

/// Un PNG a palette (modo P, 1-8 bit per pixel), così com'è: larghezza, altezza e gli indici riga
/// per riga, senza colori.
pub(crate) fn decode_indexed(bytes: &[u8]) -> (usize, usize, Vec<u8>) {
    let mut decoder = png::Decoder::new(bytes);
    decoder.set_transformations(png::Transformations::IDENTITY);
    let mut reader = decoder.read_info().expect("PNG incluso nell'eseguibile");
    let mut buf = vec![0; reader.output_buffer_size()];
    let info = reader.next_frame(&mut buf).expect("PNG incluso nell'eseguibile");
    assert_eq!(info.color_type, png::ColorType::Indexed, "grafica a palette");
    let bits = info.bit_depth as usize;
    assert!(bits <= 8, "grafica a palette");
    let (w, h) = (info.width as usize, info.height as usize);
    let mask = ((1u16 << bits) - 1) as u8;
    let index = (0..h)
        .flat_map(|y| {
            let row = &buf[y * info.line_size..(y + 1) * info.line_size];
            (0..w).map(move |x| {
                let bit = x * bits;
                (row[bit / 8] >> (8 - bits - bit % 8)) & mask
            })
        })
        .collect();
    (w, h, index)
}

impl ArtPixels {
    /// Un PNG a palette (modo P, 1-8 bit per pixel), così com'è: gli indici, senza colori.
    fn decode(bytes: &[u8]) -> Self {
        let (w, h, index) = decode_indexed(bytes);
        assert!(index.iter().all(|&i| (i as usize) < ART_ROLES), "ruolo sconosciuto nella grafica");
        Self { w, h, index }
    }

    /// Atlante delle maschere: (larghezza, altezza, alfa di ogni pixel, celle). Una cella per ogni
    /// ruolo che ha pixel, una sotto l'altra, con un pixel vuoto attorno (il filtro
    /// Nearest non prende mai i vicini); i lati a potenze di 2 come in `rasterize_pixel_font`.
    fn atlas(&self) -> (u32, u32, Vec<u8>, Vec<Option<Rect>>) {
        let lit = |role: usize, i: usize| {
            let p = self.index[i];
            p != 0 && (role == 0 || p as usize == role)
        };
        let used: Vec<bool> = (0..ART_ROLES).map(|role| (0..self.index.len()).any(|i| lit(role, i))).collect();
        let (cw, ch) = (self.w + 2, self.h + 2);
        let tw = cw.next_power_of_two();
        let th = (used.iter().filter(|u| **u).count() * ch).max(1).next_power_of_two();
        let mut alpha = vec![0u8; tw * th];
        let mut y0 = 0;
        let cells = used
            .iter()
            .enumerate()
            .map(|(c, &used)| {
                if !used {
                    return None;
                }
                for i in (0..self.index.len()).filter(|&i| lit(c, i)) {
                    let (x, y) = (i % self.w, i / self.w);
                    alpha[(y0 + 1 + y) * tw + 1 + x] = 255;
                }
                let cell = Rect::new(1.0, (y0 + 1) as f32, self.w as f32, self.h as f32);
                y0 += ch;
                Some(cell)
            })
            .collect();
        (tw as u32, th as u32, alpha, cells)
    }
}

impl PixelArt {
    pub fn from_png(bytes: &[u8]) -> Self {
        let pixels = ArtPixels::decode(bytes);
        let (tw, th, alpha, cells) = pixels.atlas();
        let rgba: Vec<u8> = alpha.iter().flat_map(|&a| [255, 255, 255, a]).collect();
        let texture = Texture2D::from_rgba8(tw as u16, th as u16, &rgba);
        texture.set_filter(FilterMode::Nearest);
        Self {
            w: pixels.w as f32,
            h: pixels.h as f32,
            texture,
            cells,
        }
    }

    fn cell(&self, role: usize) -> Option<Rect> {
        self.cells.get(role).copied().flatten()
    }
}

pub struct Renderer {
    pub world_w: f32,
    pub world_h: f32,
    keep_aspect: bool,
    /// area del campo sullo schermo, in pixel fisici: (x, y, w, h)
    viewport_px: (i32, i32, i32, i32),
    screen_px: (u32, u32),
    crt: Option<CrtPass>,
    /// sfocatura del bullet time (None se gli shader non si caricano: resta solo il grigio)
    blur: Option<BlurPass>,
    /// scambio di giallo e rosso (`set_color_swap`): il materiale, caricato alla prima accensione
    /// (None se lo shader non si carica), e se è acceso
    swap: Option<Material>,
    swap_on: bool,
}

/// Sfocatura di uno strato del campo (il bullet time): si disegna lo strato in `scene`, grande
/// quanto il bersaglio del campo (lo schermo o il buffer del CRT), lo si riduce a `BLUR_ROWS`
/// righe in `low`, lo si sfoca in orizzontale in `mid` e in verticale di nuovo in `low`, togliendo
/// il colore; infine `low` torna sul bersaglio, ingrandito con il filtro lineare, sopra lo strato
/// nitido con opacità pari all'intensità della rampa. Il CRT viene dopo: le scanline restano nitide.
struct BlurPass {
    /// un materiale per passaggio: le uniform di un materiale usato due volte nello stesso frame
    /// valgono per entrambi i disegni
    down: Material,
    horz: Material,
    vert: Material,
    scene: RenderTarget,
    low: RenderTarget,
    mid: RenderTarget,
    size: Vec2,
    low_size: Vec2,
}

/// Righe dei buffer ridotti della sfocatura: quelle dello schermo arcade (320x240), così un texel
/// vale un pixel arcade a ogni risoluzione e il costo dei due passaggi resta minimo.
const BLUR_ROWS: f32 = 240.0;
/// Distanza tra i campioni della gaussiana, in texel ridotti: 1,25 dà un raggio di circa 4 pixel
/// arcade, fuori fuoco ma con palla e racchetta avversaria ancora da seguire.
const BLUR_SPREAD: f32 = 1.25;

struct CrtPass {
    material: Material,
    world: RenderTarget,
    /// il campo ridotto alle righe emulate (un texel per pixel emulato) con la media dei texel
    /// che copre: il CRT ne prendeva uno solo e le linee sottili (le celle vuote della riserva)
    /// sparivano quando cadevano tra due campioni
    down: Material,
    source: RenderTarget,
    source_size: Vec2,
    /// uscita a risoluzione ridotta, se serve
    reduced: Option<RenderTarget>,
    out_size: Vec2,
}

impl Renderer {
    pub fn new(world_w: u32, world_h: u32, keep_aspect: bool) -> Self {
        Self {
            world_w: world_w as f32,
            world_h: world_h as f32,
            keep_aspect,
            viewport_px: (0, 0, 1, 1),
            screen_px: (0, 0),
            crt: None,
            blur: None,
            swap: None,
            swap_on: false,
        }
    }

    /// Accende o spegne lo scambio di giallo e rosso in tutto quello che si disegna (vedi
    /// `swap_color`): testi, rettangoli e immagini passano per lo shader `SWAP_FRAGMENT`, prima
    /// della sfocatura e del CRT.
    pub fn set_color_swap(&mut self, on: bool) {
        self.swap_on = on;
        if on && self.swap.is_none() {
            match load_material(
                ShaderSource::Glsl {
                    vertex: SWAP_VERTEX,
                    fragment: &swap_fragment(),
                },
                MaterialParams {
                    pipeline_params: PipelineParams {
                        color_blend: Some(BlendState::new(
                            Equation::Add,
                            BlendFactor::Value(BlendValue::SourceAlpha),
                            BlendFactor::OneMinusValue(BlendValue::SourceAlpha),
                        )),
                        ..Default::default()
                    },
                    ..Default::default()
                },
            ) {
                Ok(m) => self.swap = Some(m),
                Err(err) => eprintln!("Color swap unavailable: {err:?}"),
            }
        }
    }

    /// Materiale dei disegni del campo: quello dello scambio dei colori se è acceso.
    fn use_scene_material(&self) {
        match (&self.swap, self.swap_on) {
            (Some(m), true) => gl_use_material(m),
            _ => gl_use_default_material(),
        }
    }

    /// Pixel fisici per unità del campo.
    pub fn pixels_per_unit(&self) -> f32 {
        match &self.crt {
            Some(crt) => crt.out_size.x / self.world_w, // si disegna nel buffer del CRT
            None => self.viewport_px.2 as f32 / self.world_w,
        }
    }

    /// Punto dello schermo (coordinate logiche di macroquad, come mouse e touch) in coordinate
    /// di disegno del campo, con y dall'alto; fuori dal campo i valori escono dai bordi.
    pub fn to_world(&self, p: Vec2) -> Vec2 {
        let dpi = screen_dpi_scale();
        let (x, y, w, h) = self.viewport_px;
        vec2(
            (p.x * dpi - x as f32) / w.max(1) as f32 * self.world_w,
            (p.y * dpi - y as f32) / h.max(1) as f32 * self.world_h,
        )
    }

    /// Nuova larghezza del campo: il prossimo `update_layout` rifà letterbox e buffer.
    pub fn set_world_width(&mut self, width: u32) {
        self.world_w = width as f32;
        self.screen_px = (0, 0);
    }

    /// Da chiamare a ogni frame: ricalcola il letterbox se la finestra è cambiata.
    pub fn update_layout(&mut self, crt: &Crt) {
        let dpi = screen_dpi_scale();
        let screen = (
            (screen_width() * dpi).round() as u32,
            (screen_height() * dpi).round() as u32,
        );
        let crt_wanted = crt.enabled;
        if screen == self.screen_px && crt_wanted == self.crt.is_some() {
            return;
        }
        self.screen_px = screen;
        let (sw, sh) = (screen.0.max(1) as f32, screen.1.max(1) as f32);
        let (vw, vh) = if self.keep_aspect {
            let s = (sw / self.world_w).min(sh / self.world_h);
            ((self.world_w * s).round(), (self.world_h * s).round())
        } else {
            (sw, sh)
        };
        self.viewport_px = (((sw - vw) / 2.0) as i32, ((sh - vh) / 2.0) as i32, vw as i32, vh as i32);
        self.crt = if crt_wanted {
            CrtPass::new(crt, vw as u32, vh as u32, self.world_h)
        } else {
            None
        };
        // la sfocatura lavora alla risoluzione del bersaglio del campo
        let target = self.crt.as_ref().map_or(vec2(vw, vh), |c| c.out_size);
        self.blur = BlurPass::new(target);
    }

    /// Bersaglio del campo: il buffer del CRT, se c'è, altrimenti lo schermo nel letterbox.
    fn world_target(&self) -> Option<RenderTarget> {
        self.crt.as_ref().map(|c| c.world.clone())
    }

    /// Inizia uno strato sfocato (il bullet time): da qui si disegna in un buffer a parte, con le
    /// stesse coordinate e la stessa scala del testo. Restituisce false (e non cambia niente) se la
    /// sfocatura non è disponibile; altrimenti va chiuso con `end_blur`.
    pub fn begin_blur(&self) -> bool {
        let Some(blur) = &self.blur else { return false };
        set_camera(&self.world_camera(Some(blur.scene.clone())));
        clear_background(BLACK);
        true
    }

    /// Chiude lo strato di `begin_blur`: lo sfoca e lo posa sul campo con opacità `k` (0..1,
    /// sopra lo strato nitido durante la rampa), poi si torna a disegnare sul campo.
    pub fn end_blur(&self, k: f32) {
        let Some(blur) = &self.blur else { return };
        let k = k.clamp(0.0, 1.0);
        let low = blur.low_size;
        let src_texel = vec2(1.0 / blur.size.x, 1.0 / blur.size.y);
        let low_texel = vec2(1.0 / low.x, 1.0 / low.y);

        // riduzione a BLUR_ROWS righe: 4 campioni bilineari coprono il blocco di pixel di ogni
        // texel, così le linee sottili non spariscono
        let step = (blur.size / low / 4.0).max(vec2(0.25, 0.25));
        blur.down.set_uniform("Step", step * src_texel);
        pass(&blur.down, &blur.scene, &blur.low, low);
        // gaussiana in due passaggi; nel secondo il colore sfuma nel grigio (luminanza) con `k`
        blur.horz.set_uniform("Gray", 0.0f32);
        blur.horz.set_uniform("Dir", vec2(low_texel.x * BLUR_SPREAD, 0.0));
        pass(&blur.horz, &blur.low, &blur.mid, low);
        blur.vert.set_uniform("Gray", k);
        blur.vert.set_uniform("Dir", vec2(0.0, low_texel.y * BLUR_SPREAD));
        pass(&blur.vert, &blur.mid, &blur.low, low);

        // sul campo: lo strato nitido (solo durante la rampa) e sopra quello sfocato
        let target = self.world_target();
        let dest = match &target {
            Some(_) => Rect::new(0.0, 0.0, blur.size.x, blur.size.y),
            None => {
                let dpi = screen_dpi_scale();
                let (x, y, w, h) = self.viewport_px;
                Rect::new(x as f32 / dpi, y as f32 / dpi, w as f32 / dpi, h as f32 / dpi)
            }
        };
        match &target {
            Some(rt) => set_camera(&Camera2D {
                target: blur.size / 2.0,
                zoom: vec2(2.0 / blur.size.x, 2.0 / blur.size.y),
                render_target: Some(rt.clone()),
                ..Default::default()
            }),
            None => set_default_camera(),
        }
        // dal buffer al buffer l'orientamento resta, verso lo schermo si capovolge
        let flip_y = target.is_none();
        let params = DrawTextureParams {
            dest_size: Some(dest.size()),
            flip_y,
            ..Default::default()
        };
        if k < 1.0 {
            draw_texture_ex(&blur.scene.texture, dest.x, dest.y, WHITE, params.clone());
        }
        draw_texture_ex(&blur.low.texture, dest.x, dest.y, Color::new(1.0, 1.0, 1.0, k), params);
        set_camera(&self.world_camera(target));
        // gli strati sono già scambiati: lo scambio dei colori riprende solo da qui
        self.use_scene_material();
    }

    fn world_camera(&self, render_target: Option<RenderTarget>) -> Camera2D {
        let viewport = if render_target.is_some() {
            None
        } else {
            Some(self.viewport_px)
        };
        // macroquad inverte l'asse y tra schermo e render target: y verso il basso in
        // entrambi i casi (la texture del render target viene poi disegnata con flip_y)
        let flip = if render_target.is_some() { -1.0 } else { 1.0 };
        Camera2D {
            target: vec2(self.world_w / 2.0, self.world_h / 2.0),
            zoom: vec2(2.0 / self.world_w, flip * 2.0 / self.world_h),
            viewport,
            render_target,
            ..Default::default()
        }
    }

    /// Inizia il disegno del campo.
    pub fn begin(&self) {
        set_default_camera();
        clear_background(BLACK);
        match &self.crt {
            Some(crt) => {
                set_camera(&self.world_camera(Some(crt.world.clone())));
                clear_background(BLACK);
            }
            None => set_camera(&self.world_camera(None)),
        }
        self.use_scene_material();
    }

    /// Termina il disegno: applica il CRT (se attivo), porta il risultato a schermo e lo
    /// scurisce secondo `white_level` (percento del bianco).
    pub fn end(&self, white_level: u8) {
        let dpi = screen_dpi_scale();
        let (x, y, w, h) = self.viewport_px;
        let dest = Rect::new(x as f32 / dpi, y as f32 / dpi, w as f32 / dpi, h as f32 / dpi);
        gl_use_default_material(); // il campo è già scambiato (`set_color_swap`)
        self.end_crt(dest);
        // un velo nero sopra tutto moltiplica ogni colore per lo stesso fattore
        let veil = 1.0 - (white_level.min(100) as f32 / 100.0);
        if veil > 0.0 {
            draw_rectangle(dest.x, dest.y, dest.w, dest.h, Color::new(0.0, 0.0, 0.0, veil));
        }
    }

    fn end_crt(&self, dest: Rect) {
        let Some(crt) = &self.crt else {
            set_default_camera();
            return;
        };
        // campo -> righe emulate, con la media dei texel di ogni pixel emulato
        crt.down.set_uniform("Step", crt.source_size.recip() * 0.25);
        pass(&crt.down, &crt.world, &crt.source, crt.source_size);
        crt.material.set_uniform("OutputSize", crt.out_size);
        crt.material.set_uniform("SourceSize", crt.source_size);

        match &crt.reduced {
            Some(reduced) => {
                // passo CRT nella texture ridotta, poi ingrandimento lineare a schermo
                let size = crt.out_size;
                set_camera(&Camera2D {
                    target: size / 2.0,
                    zoom: vec2(2.0 / size.x, 2.0 / size.y),
                    render_target: Some(reduced.clone()),
                    ..Default::default()
                });
                clear_background(BLACK);
                gl_use_material(&crt.material);
                draw_texture_ex(
                    &crt.source.texture,
                    0.0,
                    0.0,
                    WHITE,
                    DrawTextureParams {
                        dest_size: Some(size),
                        ..Default::default()
                    },
                );
                gl_use_default_material();
                set_default_camera();
                draw_texture_ex(
                    &reduced.texture,
                    dest.x,
                    dest.y,
                    WHITE,
                    DrawTextureParams {
                        dest_size: Some(dest.size()),
                        flip_y: true,
                        ..Default::default()
                    },
                );
            }
            None => {
                set_default_camera();
                gl_use_material(&crt.material);
                draw_texture_ex(
                    &crt.source.texture,
                    dest.x,
                    dest.y,
                    WHITE,
                    DrawTextureParams {
                        dest_size: Some(dest.size()),
                        flip_y: true,
                        ..Default::default()
                    },
                );
                gl_use_default_material();
            }
        }
    }

    // ---------------------------------------------------------------- disegno

    /// y del core (verso l'alto) -> y di disegno (verso il basso).
    pub fn screen_y(&self, y: f32) -> f32 {
        self.world_h - y
    }

    pub fn fill(&self, color: Color) {
        draw_rectangle(0.0, 0.0, self.world_w, self.world_h, color);
    }

    /// Rettangolo dato dal centro in coordinate del core.
    pub fn rect_centered(&self, cx: f32, cy: f32, w: f32, h: f32, color: Color) {
        draw_rectangle(cx - w / 2.0, self.screen_y(cy) - h / 2.0, w, h, color);
    }

    /// Lato di un pixel arcade (lo schermo 320x240 del core MiSTer) in unità del campo.
    pub fn arcade_px(&self) -> f32 {
        self.world_h / 240.0
    }

    /// Grandezza delle scritte a 1x (8 pixel arcade) in unità del campo.
    pub fn text_1x(&self) -> f32 {
        TEXT_1X * self.arcade_px()
    }

    /// Grandezza delle scritte a 2x (16 pixel arcade) in unità del campo.
    pub fn text_2x(&self) -> f32 {
        TEXT_2X * self.arcade_px()
    }

    /// Pixel fisici per unità del campo in orizzontale e in verticale, nel bersaglio in cui si
    /// disegna il campo (lo schermo nel letterbox o il buffer del CRT).
    fn physical_per_unit(&self) -> Vec2 {
        match &self.crt {
            Some(crt) => vec2(crt.out_size.x / self.world_w, crt.out_size.y / self.world_h),
            None => vec2(
                self.viewport_px.2 as f32 / self.world_w,
                self.viewport_px.3 as f32 / self.world_h,
            ),
        }
    }

    /// Il punto del campo più vicino a `p` che cade sull'angolo di un pixel fisico: il bersaglio
    /// del campo comincia su un pixel fisico, quindi basta arrotondare nella sua scala.
    fn snap(&self, p: Vec2) -> Vec2 {
        let k = self.physical_per_unit();
        vec2((p.x * k.x).round() / k.x, (p.y * k.y).round() / k.y)
    }

    /// Font a pixel: unità del campo per pixel del font (x, y), con un pixel del font che vale
    /// un numero intero di pixel fisici (vedi `PixelFont`). La grandezza chiesta si porta prima al
    /// multiplo intero più vicino della grandezza di disegno in pixel arcade (1x, 2x...): le
    /// schermate che scalano le misure a modo loro (`App::scale`) restano comunque a 1x o 2x, e
    /// due scritte a 1x vengono sempre uguali.
    fn pixel_unit(&self, font: &PixelFont, size: f32) -> Vec2 {
        let times = (size / (font.em * self.arcade_px())).round().max(1.0);
        self.unit_times(times)
    }

    /// Unità del campo (x, y) per un pixel che vale `times` pixel arcade (intero), portato a un
    /// numero intero di pixel fisici: il più vicino, per difetto a metà strada.
    fn unit_times(&self, times: f32) -> Vec2 {
        let k = self.physical_per_unit();
        let n = (times * self.arcade_px() * k.y - 0.5).ceil().max(1.0);
        vec2(n / k.x, n / k.y)
    }

    /// Grandezza (larghezza, altezza) in unità del campo di una grafica a pixel disegnata a `times`
    /// (1: un pixel della grafica per pixel arcade, come le scritte a 1x).
    pub fn art_size(&self, art: &PixelArt, times: f32) -> Vec2 {
        let u = self.unit_times(times);
        vec2(art.w * u.x, art.h * u.y)
    }

    /// Grafica a pixel a `times` (intero, 1 come le scritte a 1x) centrata su (cx, cy) di disegno,
    /// ruotata attorno al centro (radianti, orario), con i colori `paint`; `part` ne disegna solo
    /// un pezzo, al suo posto. Come `PixelFont`: pixel interi e origine su un pixel fisico.
    #[allow(clippy::too_many_arguments)] // posizione, grandezza, rotazione, pezzo e colori sono tutti necessari
    pub fn art_centered(&self, art: &PixelArt, times: f32, cx: f32, cy: f32, rotation: f32, part: ArtPart, paint: &ArtPaint) {
        let u = self.unit_times(times);
        let (vx, vy) = (art.w * u.x / 2.0, art.h * u.y / 2.0);
        let (sin, cos) = rotation.sin_cos();
        let origin = self.snap(vec2(cx - (vx * cos - vy * sin), cy - (vx * sin + vy * cos)));
        let whole = Rect::new(0.0, 0.0, art.w, art.h);
        let area = match part {
            ArtPart::Whole => whole,
            ArtPart::Area(r) => {
                let (x0, y0) = (r.x.clamp(0.0, art.w), r.y.clamp(0.0, art.h));
                let (x1, y1) = ((r.x + r.w).clamp(x0, art.w), (r.y + r.h).clamp(y0, art.h));
                Rect::new(x0, y0, x1 - x0, y1 - y0)
            }
        };
        if area.w <= 0.0 || area.h <= 0.0 {
            return;
        }
        for (role, color) in paint.iter().enumerate() {
            let (Some(color), Some(cell)) = (color, art.cell(role)) else { continue };
            draw_texture_ex(
                &art.texture,
                origin.x + area.x * u.x,
                origin.y + area.y * u.y,
                *color,
                DrawTextureParams {
                    dest_size: Some(vec2(area.w * u.x, area.h * u.y)),
                    source: Some(Rect::new(cell.x + area.x, cell.y + area.y, area.w, area.h)),
                    rotation,
                    pivot: Some(origin),
                    ..Default::default()
                },
            );
        }
    }

    /// Testo centrato su (cx, cy) in coordinate di disegno, eventualmente ruotato (radianti, orario).
    /// La dimensione è in unità del campo (per il font delle scritte `text_1x` o `text_2x`). Il
    /// font a pixel segue `PixelFont`; gli altri si rasterizzano alla risoluzione reale dello
    /// schermo, così il testo resta nitido a ogni scala. Per questi ultimi niente dimensioni che
    /// cambiano a ogni frame: ogni dimensione finisce nell'atlante di macroquad, che crescerebbe
    /// senza fine (fino a superare le texture che un telefono regge) e, quando raddoppia, cancella
    /// la texture già usata dai disegni del frame ("glBindTexture called with an already deleted
    /// texture").
    #[allow(clippy::too_many_arguments)] // posizione, dimensione, rotazione e colore sono tutti necessari
    pub fn text_centered(&self, text: &str, font: &GameFont, size: f32, cx: f32, cy: f32, rotation: f32, color: Color) {
        match &font.pixel {
            Some(pixel) => self.pixel_centered(text, pixel, size, cx, cy, rotation, color),
            None => self.draw_centered(text, font, self.font_params(size), cx, cy, rotation, color),
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn pixel_centered(&self, text: &str, font: &PixelFont, size: f32, cx: f32, cy: f32, rotation: f32, color: Color) {
        let Some((l, t, r, b)) = font.ink(text) else { return };
        let u = self.pixel_unit(font, size);
        // centro dell'inchiostro rispetto all'origine, ruotato; poi l'origine su un pixel fisico
        let (vx, vy) = ((l + r) / 2.0 * u.x, (t + b) / 2.0 * u.y);
        let (sin, cos) = rotation.sin_cos();
        let origin = self.snap(vec2(cx - (vx * cos - vy * sin), cy - (vx * sin + vy * cos)));
        self.pixel_glyphs(text, font, u, origin, rotation, color);
    }

    /// Glifi del font a pixel con l'origine (inizio della linea di base) in `origin`, ruotati
    /// attorno all'origine.
    fn pixel_glyphs(&self, text: &str, font: &PixelFont, u: Vec2, origin: Vec2, rotation: f32, color: Color) {
        for (g, pen) in font.layout(text).filter(|(g, _)| g.src.w > 0.0) {
            draw_texture_ex(
                &font.texture,
                origin.x + (pen + g.left) * u.x,
                origin.y + g.top * u.y,
                color,
                DrawTextureParams {
                    dest_size: Some(vec2(g.src.w * u.x, g.src.h * u.y)),
                    source: Some(g.src),
                    rotation,
                    pivot: Some(origin),
                    ..Default::default()
                },
            );
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn draw_centered(
        &self,
        text: &str,
        font: &GameFont,
        (font_size, font_scale): (u16, f32),
        cx: f32,
        cy: f32,
        rotation: f32,
        color: Color,
    ) {
        let dims = measure_text(text, Some(&font.font), font_size, font_scale);
        // centro dell'inchiostro rispetto all'origine (inizio della linea di base), poi ruotato
        let dpi = screen_dpi_scale();
        let raster = (font_size as f32 * dpi).ceil(); // come la rasterizzazione di macroquad
        let (left, right) = font.ink_span(text, raster);
        let vx = (left + right) / 2.0 * font_scale / dpi;
        let vy = dims.height / 2.0 - dims.offset_y;
        let (sin, cos) = rotation.sin_cos();
        let (rx, ry) = (vx * cos - vy * sin, vx * sin + vy * cos);
        draw_text_ex(
            text,
            cx - rx,
            cy - ry,
            TextParams {
                font: Some(&font.font),
                font_size,
                font_scale,
                rotation,
                color,
                ..Default::default()
            },
        );
    }

    /// Larghezza di un testo in coordinate di disegno (la somma degli avanzamenti).
    pub fn text_width(&self, text: &str, font: &GameFont, size: f32) -> f32 {
        if let Some(pixel) = &font.pixel {
            return pixel.advance(text) * self.pixel_unit(pixel, size).x;
        }
        let (font_size, font_scale) = self.font_params(size);
        measure_text(text, Some(&font.font), font_size, font_scale).width
    }

    /// Estensione orizzontale dell'inchiostro di ogni carattere di `text` (sinistra, destra) in
    /// coordinate di disegno, rispetto al centro dell'inchiostro di tutto il testo: quello su cui
    /// `text_centered` lo centra. None per i caratteri senza inchiostro (gli spazi).
    pub fn ink_boxes(&self, text: &str, font: &GameFont, size: f32) -> Vec<Option<(f32, f32)>> {
        if let Some(pixel) = &font.pixel {
            let k = self.pixel_unit(pixel, size).x;
            let mid = pixel.ink(text).map_or(0.0, |(l, _, r, _)| (l + r) / 2.0);
            return pixel
                .layout(text)
                .map(|(g, pen)| {
                    let x0 = pen + g.left - mid;
                    (g.src.w > 0.0).then_some((x0 * k, (x0 + g.src.w) * k))
                })
                .collect();
        }
        let (font_size, font_scale) = self.font_params(size);
        let dpi = screen_dpi_scale();
        let raster = (font_size as f32 * dpi).ceil(); // come `draw_centered`
        let (left, right) = font.ink_span(text, raster);
        let (mid, k) = ((left + right) / 2.0, font_scale / dpi);
        let mut pen = 0.0;
        text.chars()
            .map(|ch| {
                let m = font.metrics.metrics(ch, raster);
                let x0 = pen + m.xmin as f32 - mid;
                pen += m.advance_width;
                (m.width > 0).then_some((x0 * k, (x0 + m.width as f32) * k))
            })
            .collect()
    }

    /// Altezza dell'inchiostro di un testo in coordinate di disegno (quella che `text_centered`
    /// centra in verticale).
    pub fn text_height(&self, text: &str, font: &GameFont, size: f32) -> f32 {
        if let Some(pixel) = &font.pixel {
            return pixel.ink(text).map_or(0.0, |(_, t, _, b)| (b - t) * self.pixel_unit(pixel, size).y);
        }
        let (font_size, font_scale) = self.font_params(size);
        measure_text(text, Some(&font.font), font_size, font_scale).height
    }

    /// Testo allineato in basso a destra su (x, y) in coordinate di disegno: l'avanzamento
    /// finisce in x, l'inchiostro in y.
    pub fn text_bottom_right(&self, text: &str, font: &GameFont, size: f32, x: f32, y: f32, color: Color) {
        if let Some(pixel) = &font.pixel {
            let Some((_, _, _, bottom)) = pixel.ink(text) else { return };
            let u = self.pixel_unit(pixel, size);
            let origin = self.snap(vec2(x - pixel.advance(text) * u.x, y - bottom * u.y));
            self.pixel_glyphs(text, pixel, u, origin, 0.0, color);
            return;
        }
        let (font_size, font_scale) = self.font_params(size);
        let dims = measure_text(text, Some(&font.font), font_size, font_scale);
        draw_text_ex(
            text,
            x - dims.width,
            y - (dims.height - dims.offset_y),
            TextParams {
                font: Some(&font.font),
                font_size,
                font_scale,
                color,
                ..Default::default()
            },
        );
    }

    fn font_params(&self, size: f32) -> (u16, f32) {
        // macroquad rasterizza a font_size * dpi pixel: si sceglie font_size perché
        // i pixel rasterizzati coincidano con quelli dello schermo
        let raster = size * self.pixels_per_unit() / screen_dpi_scale();
        let font_size = raster.round().max(1.0) as u16;
        (font_size, size / font_size as f32)
    }
}

impl CrtPass {
    fn new(cfg: &Crt, w: u32, h: u32, world_h: f32) -> Option<Self> {
        let material = match load_material(
            ShaderSource::Glsl {
                vertex: CRT_VERTEX,
                fragment: CRT_FRAGMENT,
            },
            MaterialParams {
                uniforms: vec![
                    UniformDesc::new("OutputSize", UniformType::Float2),
                    UniformDesc::new("SourceSize", UniformType::Float2),
                    UniformDesc::new("HardScan", UniformType::Float1),
                    UniformDesc::new("HardPix", UniformType::Float1),
                    UniformDesc::new("Warp", UniformType::Float2),
                    UniformDesc::new("MaskDark", UniformType::Float1),
                    UniformDesc::new("MaskLight", UniformType::Float1),
                ],
                pipeline_params: PipelineParams {
                    color_blend: Some(BlendState::new(
                        Equation::Add,
                        BlendFactor::Value(BlendValue::SourceAlpha),
                        BlendFactor::OneMinusValue(BlendValue::SourceAlpha),
                    )),
                    ..Default::default()
                },
                ..Default::default()
            },
        ) {
            Ok(m) => m,
            Err(err) => {
                eprintln!("CRT filter unavailable: {err:?}");
                return None;
            }
        };
        material.set_uniform("HardScan", cfg.hard_scan);
        material.set_uniform("HardPix", cfg.hard_pix);
        material.set_uniform("Warp", vec2(cfg.warp_x, cfg.warp_y));
        material.set_uniform("MaskDark", cfg.mask_dark);
        material.set_uniform("MaskLight", cfg.mask_light);

        let scale = (CRT_MAX_PIXELS / (w * h) as f32).sqrt().min(1.0);
        let out = ((w as f32 * scale).round().max(1.0), (h as f32 * scale).round().max(1.0));
        // il CRT campiona solo ~240 righe: il campo basta disegnarlo alla risoluzione d'uscita
        let world = render_target(out.0 as u32, out.1 as u32);
        world.texture.set_filter(FilterMode::Linear);
        // righe emulate fisse rispetto al campo (3 * altezza / resolution_scale: 576 con il
        // default 2.5, 240 con 6.0), così l'aspetto è lo stesso in finestra e a schermo intero
        let down_scale = out.1 * cfg.resolution_scale / (3.0 * world_h);
        let source_size = vec2((out.0 / down_scale).round().max(1.0), (out.1 / down_scale).round().max(1.0));
        let source = render_target(source_size.x as u32, source_size.y as u32);
        source.texture.set_filter(FilterMode::Nearest);
        let down = match load_material(
            ShaderSource::Glsl {
                vertex: CRT_VERTEX,
                fragment: BLUR_DOWN_FRAGMENT,
            },
            MaterialParams {
                uniforms: vec![UniformDesc::new("Step", UniformType::Float2)],
                ..Default::default()
            },
        ) {
            Ok(m) => m,
            Err(err) => {
                eprintln!("CRT filter unavailable: {err:?}");
                return None;
            }
        };
        let reduced = (scale < 1.0).then(|| {
            let rt = render_target(out.0 as u32, out.1 as u32);
            rt.texture.set_filter(FilterMode::Linear);
            rt
        });
        Some(Self {
            material,
            world,
            down,
            source,
            source_size,
            reduced,
            out_size: vec2(out.0, out.1),
        })
    }
}

impl BlurPass {
    fn new(size: Vec2) -> Option<Self> {
        let load = |fragment: &str, uniforms: Vec<UniformDesc>| {
            load_material(
                ShaderSource::Glsl {
                    vertex: CRT_VERTEX,
                    fragment,
                },
                MaterialParams {
                    uniforms,
                    ..Default::default()
                },
            )
        };
        let gauss = || {
            load(
                BLUR_GAUSS_FRAGMENT,
                vec![
                    UniformDesc::new("Dir", UniformType::Float2),
                    UniformDesc::new("Gray", UniformType::Float1),
                ],
            )
        };
        let materials = load(BLUR_DOWN_FRAGMENT, vec![UniformDesc::new("Step", UniformType::Float2)])
            .and_then(|down| Ok((down, gauss()?, gauss()?)));
        let (down, horz, vert) = match materials {
            Ok(m) => m,
            Err(err) => {
                eprintln!("Bullet time blur unavailable: {err:?}");
                return None;
            }
        };
        let size = vec2(size.x.round().max(1.0), size.y.round().max(1.0));
        let rows = BLUR_ROWS.min(size.y);
        let low_size = vec2((size.x * rows / size.y).round().max(1.0), rows);
        let target = |s: Vec2| {
            let rt = render_target(s.x as u32, s.y as u32);
            rt.texture.set_filter(FilterMode::Linear);
            rt
        };
        Some(Self {
            down,
            horz,
            vert,
            scene: target(size),
            low: target(low_size),
            mid: target(low_size),
            size,
            low_size,
        })
    }
}

/// Un passaggio della sfocatura: `src` intero, con `material`, dentro `dst` grande `size`.
fn pass(material: &Material, src: &RenderTarget, dst: &RenderTarget, size: Vec2) {
    set_camera(&Camera2D {
        target: size / 2.0,
        zoom: vec2(2.0 / size.x, 2.0 / size.y),
        render_target: Some(dst.clone()),
        ..Default::default()
    });
    gl_use_material(material);
    draw_texture_ex(
        &src.texture,
        0.0,
        0.0,
        WHITE,
        DrawTextureParams {
            dest_size: Some(size),
            ..Default::default()
        },
    );
    gl_use_default_material();
}

// ------------------------------------------------------------ scambio di giallo e rosso

/// Asse dello scambio: la tinta (in gradi) a metà tra il rosso (0°) e il giallo dell'accento
/// (circa 48°), che quindi si scambiano.
const SWAP_CENTER: f32 = 24.0;
/// Entro questi gradi dall'asse la tinta si riflette: dal rosso porpora (-24°) al giallo
/// verdastro (72°), arancioni compresi (diventano l'arancione dall'altra parte).
const SWAP_FULL: f32 = 48.0;
/// Oltre `SWAP_FULL`, in questi gradi la riflessione sfuma fino a sparire: verdi, azzurri, blu
/// e viola (e il verde fosforo dell'auto-test) restano come sono.
const SWAP_EDGE: f32 = 12.0;

/// Il colore con giallo e rosso scambiati (l'easter egg delle iniziali, `set_color_swap`). La
/// tinta si riflette attorno a `SWAP_CENTER`; massimo e minimo dei canali restano, quindi anche
/// luminosità e saturazione: bianchi, grigi e neri non cambiano. Stessa formula, passo per
/// passo, dello shader (`swap_fragment`); qui serve ai test.
#[cfg(test)]
fn swap_color(c: Color) -> Color {
    let hi = c.r.max(c.g).max(c.b);
    let lo = c.r.min(c.g).min(c.b);
    let chroma = hi - lo;
    if chroma <= 0.0 {
        return c;
    }
    let h = if hi == c.r {
        ((c.g - c.b) / chroma).rem_euclid(6.0)
    } else if hi == c.g {
        (c.b - c.r) / chroma + 2.0
    } else {
        (c.r - c.g) / chroma + 4.0
    } * 60.0;
    let d = (h - SWAP_CENTER + 180.0).rem_euclid(360.0) - 180.0;
    let k = ((d.abs() - SWAP_FULL) / SWAP_EDGE).clamp(0.0, 1.0);
    let h = (d * (2.0 * k - 1.0) + SWAP_CENTER).rem_euclid(360.0) / 60.0;
    let ch = |n: f32| lo + chroma * (((h + n).rem_euclid(6.0) - 3.0).abs() - 1.0).clamp(0.0, 1.0);
    Color::new(ch(0.0), ch(4.0), ch(2.0), c.a)
}

/// Vertici come lo shader di macroquad, con il colore dei vertici.
const SWAP_VERTEX: &str = r#"#version 100
attribute vec3 position;
attribute vec2 texcoord;
attribute vec4 color0;
varying lowp vec2 uv;
varying lowp vec4 color;
uniform mat4 Model;
uniform mat4 Projection;
void main() {
    gl_Position = Projection * Model * vec4(position, 1.0);
    color = color0 / 255.0;
    uv = texcoord;
}
"#;

/// Lo shader di macroquad (colore per texture) più lo scambio di `swap_color`, con le stesse
/// costanti. In GLSL `mod` dà sempre un resto positivo, come `rem_euclid`.
fn swap_fragment() -> String {
    format!(
        r#"#version 100
precision mediump float;
varying lowp vec4 color;
varying lowp vec2 uv;
uniform sampler2D Texture;
void main() {{
    vec4 c = color * texture2D(Texture, uv);
    float hi = max(c.r, max(c.g, c.b));
    float lo = min(c.r, min(c.g, c.b));
    float chroma = hi - lo;
    if (chroma > 0.0) {{
        float h;
        if (hi == c.r) h = mod((c.g - c.b) / chroma, 6.0);
        else if (hi == c.g) h = (c.b - c.r) / chroma + 2.0;
        else h = (c.r - c.g) / chroma + 4.0;
        float d = mod(h * 60.0 - {center:.1} + 180.0, 360.0) - 180.0;
        float k = clamp((abs(d) - {full:.1}) / {edge:.1}, 0.0, 1.0);
        h = mod(d * (2.0 * k - 1.0) + {center:.1}, 360.0) / 60.0;
        vec3 n = clamp(abs(mod(vec3(h) + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
        c.rgb = vec3(lo) + chroma * n;
    }}
    gl_FragColor = c;
}}
"#,
        center = SWAP_CENTER,
        full = SWAP_FULL,
        edge = SWAP_EDGE,
    )
}

// Shader della sfocatura in GLSL 100 (WebGL1, GLES2 del Raspberry): precisione media, che basta
// per buffer di poche centinaia di texel.

// Riduzione: media di 4 campioni bilineari attorno al centro del texel ridotto.
const BLUR_DOWN_FRAGMENT: &str = r#"#version 100
precision mediump float;
varying highp vec2 uv;
uniform sampler2D Texture;
uniform vec2 Step;
void main() {
    vec3 c = texture2D(Texture, uv + vec2(-Step.x, -Step.y)).rgb
           + texture2D(Texture, uv + vec2(Step.x, -Step.y)).rgb
           + texture2D(Texture, uv + vec2(-Step.x, Step.y)).rgb
           + texture2D(Texture, uv + vec2(Step.x, Step.y)).rgb;
    gl_FragColor = vec4(c * 0.25, 1.0);
}
"#;

// Gaussiana a 9 prese con 5 campioni bilineari (pesi e distanze della gaussiana discreta);
// `Gray` porta il colore verso la sua luminanza e rialza appena i picchi, che la sfocatura
// abbassa (la palla resta da seguire).
const BLUR_GAUSS_FRAGMENT: &str = r#"#version 100
precision mediump float;
varying highp vec2 uv;
uniform sampler2D Texture;
uniform vec2 Dir;
uniform float Gray;
void main() {
    vec3 c = texture2D(Texture, uv).rgb * 0.2270270270;
    c += (texture2D(Texture, uv + Dir * 1.3846153846).rgb + texture2D(Texture, uv - Dir * 1.3846153846).rgb) * 0.3162162162;
    c += (texture2D(Texture, uv + Dir * 3.2307692308).rgb + texture2D(Texture, uv - Dir * 3.2307692308).rgb) * 0.0702702703;
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    gl_FragColor = vec4(min(mix(c, vec3(l), Gray) * (1.0 + 0.3 * Gray), vec3(1.0)), 1.0);
}
"#;

const CRT_VERTEX: &str = r#"#version 100
attribute vec3 position;
attribute vec2 texcoord;
varying highp vec2 uv;
uniform mat4 Model;
uniform mat4 Projection;
void main() {
    gl_Position = Projection * Model * vec4(position, 1.0);
    uv = texcoord;
}
"#;

// Shader CRT di Timothy Lottes (pubblico dominio, https://www.shadertoy.com/view/XsjSzR),
// portato in GLSL 100: coordinate dalla uv del quad invece che da gl_FragCoord.
const CRT_FRAGMENT: &str = r#"#version 100
precision highp float;
varying highp vec2 uv;
uniform sampler2D Texture;
uniform vec2 OutputSize;
uniform vec2 SourceSize;
uniform float HardScan;
uniform float HardPix;
uniform vec2 Warp;
uniform float MaskDark;
uniform float MaskLight;

// la texture è già alle righe emulate: un texel per pixel emulato
vec2 res() { return SourceSize; }

// sRGB approssimato con gamma 2.0: 11 campioni per pixel con pow() costavano troppo
// sulle GPU integrate a schermo intero; a occhio la differenza è nulla
vec3 ToLinear(vec3 c) { return c * c; }
vec3 ToSrgb(vec3 c) { return sqrt(c); }

vec3 Fetch(vec2 pos, vec2 off) {
    pos = (floor(pos * res() + off) + 0.5) / res();
    if (max(abs(pos.x - 0.5), abs(pos.y - 0.5)) > 0.5) return vec3(0.0);
    return ToLinear(texture2D(Texture, pos).rgb);
}

vec2 Dist(vec2 pos) { pos = pos * res(); return -((pos - floor(pos)) - vec2(0.5)); }
float Gaus(float pos, float scale) { return exp2(scale * pos * pos); }

vec3 Horz3(vec2 pos, float off) {
    vec3 b = Fetch(pos, vec2(-1.0, off));
    vec3 c = Fetch(pos, vec2(0.0, off));
    vec3 d = Fetch(pos, vec2(1.0, off));
    float dst = Dist(pos).x;
    float wb = Gaus(dst - 1.0, HardPix);
    float wc = Gaus(dst, HardPix);
    float wd = Gaus(dst + 1.0, HardPix);
    return (b * wb + c * wc + d * wd) / (wb + wc + wd);
}

vec3 Horz5(vec2 pos, float off) {
    vec3 a = Fetch(pos, vec2(-2.0, off));
    vec3 b = Fetch(pos, vec2(-1.0, off));
    vec3 c = Fetch(pos, vec2(0.0, off));
    vec3 d = Fetch(pos, vec2(1.0, off));
    vec3 e = Fetch(pos, vec2(2.0, off));
    float dst = Dist(pos).x;
    float wa = Gaus(dst - 2.0, HardPix);
    float wb = Gaus(dst - 1.0, HardPix);
    float wc = Gaus(dst, HardPix);
    float wd = Gaus(dst + 1.0, HardPix);
    float we = Gaus(dst + 2.0, HardPix);
    return (a * wa + b * wb + c * wc + d * wd + e * we) / (wa + wb + wc + wd + we);
}

float Scan(vec2 pos, float off) { return Gaus(Dist(pos).y + off, HardScan); }

vec3 Tri(vec2 pos) {
    return Horz3(pos, -1.0) * Scan(pos, -1.0) + Horz5(pos, 0.0) * Scan(pos, 0.0) + Horz3(pos, 1.0) * Scan(pos, 1.0);
}

vec2 WarpPos(vec2 pos) {
    pos = pos * 2.0 - 1.0;
    pos *= vec2(1.0 + (pos.y * pos.y) * Warp.x, 1.0 + (pos.x * pos.x) * Warp.y);
    return pos * 0.5 + 0.5;
}

vec3 Mask(vec2 pos) {
    pos.x += pos.y * 3.0;
    vec3 mask = vec3(MaskDark);
    pos.x = fract(pos.x / 6.0);
    if (pos.x < 0.333) mask.r = MaskLight;
    else if (pos.x < 0.666) mask.g = MaskLight;
    else mask.b = MaskLight;
    return mask;
}

void main() {
    vec2 frag = uv * OutputSize;
    vec3 color = Tri(WarpPos(uv)) * Mask(floor(frag));
    gl_FragColor = vec4(ToSrgb(color), 1.0);
}
"#;

#[cfg(test)]
mod swap_tests {
    use super::*;

    fn rgb(r: u8, g: u8, b: u8) -> Color {
        Color::from_rgba(r, g, b, 255)
    }

    fn close(a: Color, b: Color) -> bool {
        [(a.r, b.r), (a.g, b.g), (a.b, b.b), (a.a, b.a)].iter().all(|(x, y)| (x - y).abs() < 1e-4)
    }

    #[test]
    fn yellow_and_red_trade_places() {
        // il giallo dell'accento (e dell'attract) diventa rosso
        let y = swap_color(rgb(255, 210, 37));
        assert!(y.r > 0.99 && y.g < 0.2 && y.b < 0.2, "{y:?}");
        // il rosso del timbro, dei fuochi e dei pulsanti diventa giallo, come l'accento
        let r = swap_color(rgb(230, 40, 40));
        assert!(r.r > 0.85 && r.g > 0.7 && r.b < 0.2, "{r:?}");
        assert!((r.g / r.r - 210.0 / 255.0).abs() < 0.03, "{r:?}");
        // rossi chiari e scuri restano chiari e scuri
        let light = swap_color(rgb(255, 110, 110));
        let dark = swap_color(rgb(140, 20, 20));
        assert!(light.g > 0.85 && dark.g > 0.4 && dark.r < 0.6, "{light:?} {dark:?}");
        // l'arancione resta arancione
        let o = swap_color(rgb(255, 140, 0));
        assert!(o.r > 0.99 && o.g > 0.2 && o.g < 0.5, "{o:?}");
    }

    #[test]
    fn swapping_twice_gives_the_colour_back() {
        for c in [rgb(255, 210, 37), rgb(230, 40, 40), rgb(255, 140, 0), rgb(240, 190, 150), rgb(255, 255, 0)] {
            assert!(close(swap_color(swap_color(c)), c), "{c:?}");
        }
    }

    #[test]
    fn other_colours_stay() {
        for c in [
            rgb(255, 255, 255),
            rgb(0, 0, 0),
            rgb(180, 180, 180),
            rgb(55, 55, 60),
            rgb(212, 247, 200), // verde fosforo dell'auto-test
            rgb(0, 255, 0),
            rgb(0, 200, 255),
            rgb(0, 0, 255),
            rgb(160, 0, 255),
        ] {
            assert!(close(swap_color(c), c), "{c:?}");
        }
        // la trasparenza resta
        assert_eq!(swap_color(Color::new(1.0, 0.0, 0.0, 0.25)).a, 0.25);
    }

    #[test]
    fn the_shader_uses_the_same_constants() {
        let f = swap_fragment();
        for v in [SWAP_CENTER, SWAP_FULL, SWAP_EDGE] {
            assert!(f.contains(&format!("{v:.1}")), "{v}");
        }
        assert!(!f.contains("{{") && f.contains("gl_FragColor = c;"));
    }
}

#[cfg(test)]
mod pixel_font_tests {
    use super::*;

    fn press_start() -> fontdue::Font {
        let bytes = include_bytes!("../../../assets/fonts/PressStart2P-Regular.ttf");
        fontdue::Font::from_bytes(&bytes[..], fontdue::FontSettings::default()).unwrap()
    }

    #[test]
    fn press_start_has_only_full_pixels_at_8() {
        let font = press_start();
        for ch in PIXEL_FIRST..=PIXEL_LAST {
            let (m, cover) = font.rasterize(ch, 8.0);
            assert!(cover.iter().all(|&c| c == 0 || c == 255), "{ch:?}: {cover:?}");
            assert_eq!(m.advance_width, 8.0, "{ch:?}");
        }
    }

    #[test]
    fn glyphs_sit_on_the_8x8_grid() {
        let (w, h, alpha, glyphs) = rasterize_pixel_font(&press_start(), 8);
        assert_eq!(alpha.len(), (w * h) as usize);
        assert_eq!(glyphs.len(), (PIXEL_LAST as usize) - (PIXEL_FIRST as usize) + 1);
        let g = |ch: char| glyphs[ch as usize - PIXEL_FIRST as usize];
        // tutto nella cella di 8x8 sopra la linea di base (il font non ha discendenti sotto);
        // maiuscole e cifre alte 7, con la riga in basso vuota
        for (i, g) in glyphs.iter().enumerate() {
            assert!(g.left >= 0.0 && g.left + g.src.w <= 8.0, "{i} {g:?}");
            assert!(g.src.w == 0.0 || (g.top >= -8.0 && g.top + g.src.h <= 0.0), "{i} {g:?}");
        }
        for ch in ['A', 'M', 'W', '0', '8'] {
            let g = g(ch);
            assert_eq!((g.top, g.top + g.src.h), (-8.0, -1.0), "{ch:?} {g:?}");
        }
        // lo spazio non ha inchiostro
        assert_eq!(g(' ').src.w, 0.0);
        // ogni glifo nella texture ha un pixel vuoto attorno
        for g in &glyphs {
            let (x0, y0) = (g.src.x as u32 - 1, g.src.y as u32 - 1);
            for x in x0..x0 + g.src.w as u32 + 2 {
                for y in [y0, y0 + g.src.h as u32 + 1] {
                    assert_eq!(alpha[(y * w + x) as usize], 0, "{g:?}");
                }
            }
        }
    }
}

#[cfg(test)]
mod pixel_art_tests {
    use super::*;

    fn titles() -> Vec<(String, ArtPixels, (usize, usize))> {
        let spec: serde_json::Value = serde_json::from_str(include_str!("../../../assets/titles/titles.json")).unwrap();
        let png = |name: &str| -> &'static [u8] {
            match name {
                "name_arcade" => include_bytes!("../../../assets/titles/name_arcade.png"),
                "name_titan" => include_bytes!("../../../assets/titles/name_titan.png"),
                "name_hammer" => include_bytes!("../../../assets/titles/name_hammer.png"),
                "name_twist" => include_bytes!("../../../assets/titles/name_twist.png"),
                "name_blaster" => include_bytes!("../../../assets/titles/name_blaster.png"),
                "name_rush" => include_bytes!("../../../assets/titles/name_rush.png"),
                "name_guardian" => include_bytes!("../../../assets/titles/name_guardian.png"),
                "name_omega" => include_bytes!("../../../assets/titles/name_omega.png"),
                "challenger" => include_bytes!("../../../assets/titles/challenger.png"),
                "warning" => include_bytes!("../../../assets/titles/warning.png"),
                "perfect" => include_bytes!("../../../assets/titles/perfect.png"),
                other => panic!("{other}"),
            }
        };
        spec["titles"]
            .as_object()
            .unwrap()
            .iter()
            .map(|(name, t)| {
                let size = (t["size"][0].as_u64().unwrap() as usize, t["size"][1].as_u64().unwrap() as usize);
                (name.clone(), ArtPixels::decode(png(name)), size)
            })
            .collect()
    }

    #[test]
    fn the_pngs_decode_to_their_size_with_known_roles() {
        for (name, art, size) in titles() {
            assert_eq!((art.w, art.h), size, "{name}");
            assert_eq!(art.index.len(), art.w * art.h, "{name}");
            // ritagliate ai pixel usati: niente righe o colonne vuote ai bordi
            let lit = |x: usize, y: usize| art.index[y * art.w + x] != 0;
            assert!((0..art.w).any(|x| lit(x, 0)) && (0..art.w).any(|x| lit(x, art.h - 1)), "{name}");
            assert!((0..art.h).any(|y| lit(0, y)) && (0..art.h).any(|y| lit(art.w - 1, y)), "{name}");
            // bianco o giallo in ogni grafica
            assert!(art.index.iter().any(|&i| i == 2 || i == 3), "{name}");
        }
    }

    /// Il logo del menu in NEXT: la sua palette ha solo i livelli dell'accento (1-5).
    #[test]
    fn the_menu_logo_has_only_the_accent_levels() {
        let art = ArtPixels::decode(include_bytes!("../../../assets/titles/menu_logo.png"));
        assert_eq!((art.w, art.h), (167, 25));
        assert!(art.index.iter().all(|&i| i <= 5));
        assert!(art.index.contains(&1) && art.index.contains(&5));
    }

    #[test]
    fn the_atlas_has_one_cell_per_used_role_with_an_empty_border() {
        for (name, art, _) in titles() {
            let (w, h, alpha, cells) = art.atlas();
            assert!(w.is_power_of_two() && h.is_power_of_two() && w <= 2048 && h <= 2048, "{name}: {w}x{h}");
            // la sagoma ha tanti pixel quanti la grafica, e ogni ruolo i suoi
            let count = |c: Rect| {
                let mut n = 0;
                for y in c.y as u32..(c.y + c.h) as u32 {
                    for x in c.x as u32..(c.x + c.w) as u32 {
                        n += (alpha[(y * w + x) as usize] == 255) as usize;
                    }
                }
                n
            };
            let whole = cells[0].expect("sagoma");
            assert_eq!(count(whole), art.index.iter().filter(|&&i| i != 0).count(), "{name}");
            for (role, cell) in cells.iter().enumerate().take(ART_ROLES).skip(1) {
                let n = art.index.iter().filter(|&&i| i as usize == role).count();
                assert_eq!(cell.map_or(0, count), n, "{name}: ruolo {role}");
            }
            for c in cells.iter().flatten() {
                let (x0, y0) = (c.x as u32 - 1, c.y as u32 - 1);
                for x in x0..x0 + c.w as u32 + 2 {
                    for y in [y0, y0 + c.h as u32 + 1] {
                        assert_eq!(alpha[(y * w + x) as usize], 0, "{name}");
                    }
                }
                for y in y0..y0 + c.h as u32 + 2 {
                    for x in [x0, x0 + c.w as u32 + 1] {
                        assert_eq!(alpha[(y * w + x) as usize], 0, "{name}");
                    }
                }
            }
        }
    }
}
