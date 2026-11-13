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

/// Font di macroquad più le metriche dei glifi, per centrare sull'inchiostro visibile
/// (la larghezza di macroquad è la somma degli avanzamenti, spazi laterali compresi).
pub struct GameFont {
    pub font: Font,
    metrics: fontdue::Font,
}

impl GameFont {
    pub fn from_bytes(bytes: &'static [u8]) -> Self {
        let mut font = load_ttf_font_from_bytes(bytes).expect("font incluso nell'eseguibile");
        font.set_filter(FilterMode::Nearest);
        let metrics =
            fontdue::Font::from_bytes(bytes, fontdue::FontSettings::default()).expect("font incluso nell'eseguibile");
        Self { font, metrics }
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

    /// Testo centrato su (cx, cy) in coordinate di disegno, eventualmente ruotato (radianti, orario).
    /// La dimensione è in unità del campo; la rasterizzazione avviene alla risoluzione
    /// reale dello schermo, così il testo resta nitido a ogni scala. Niente dimensioni che cambiano
    /// a ogni frame: ogni dimensione finisce nell'atlante di macroquad, che crescerebbe senza fine
    /// (fino a superare le texture che un telefono regge) e, quando raddoppia, cancella la texture
    /// già usata dai disegni del frame ("glBindTexture called with an already deleted texture").
    #[allow(clippy::too_many_arguments)] // posizione, dimensione, rotazione e colore sono tutti necessari
    pub fn text_centered(&self, text: &str, font: &GameFont, size: f32, cx: f32, cy: f32, rotation: f32, color: Color) {
        self.draw_centered(text, font, self.font_params(size), cx, cy, rotation, color);
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

    /// Larghezza di un testo in coordinate di disegno.
    pub fn text_width(&self, text: &str, font: &GameFont, size: f32) -> f32 {
        let (font_size, font_scale) = self.font_params(size);
        measure_text(text, Some(&font.font), font_size, font_scale).width
    }

    /// Estensione orizzontale dell'inchiostro di ogni carattere di `text` (sinistra, destra) in
    /// coordinate di disegno, rispetto al centro dell'inchiostro di tutto il testo: quello su cui
    /// `text_centered` lo centra. None per i caratteri senza inchiostro (gli spazi).
    pub fn ink_boxes(&self, text: &str, font: &GameFont, size: f32) -> Vec<Option<(f32, f32)>> {
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
        let (font_size, font_scale) = self.font_params(size);
        measure_text(text, Some(&font.font), font_size, font_scale).height
    }

    /// Testo allineato in basso a destra su (x, y) in coordinate di disegno.
    pub fn text_bottom_right(&self, text: &str, font: &GameFont, size: f32, x: f32, y: f32, color: Color) {
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
