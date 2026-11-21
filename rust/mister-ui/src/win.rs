//! Finestra della DDR3 (`mister/rtl/gfx_ddr.v` e `ui_render.v`): i ritratti grandi e medi e le
//! astronavi non stanno nella ROM grafica ma nel file `paddws_gfx.rom`, che il `.mra` carica nella
//! DDR3 all'avvio del core. Per disegnarne uno si copia nella finestra (immagini da
//! [`WIN_BASE`]) con il DMA di gfx_ddr e si disegna da lì.
//!
//! La finestra è divisa in posti, diversi per categoria (passo e numero: 4 grandi, 9 medi, una
//! astronave), che si sovrappongono perché le categorie non stanno mai nella stessa schermata. Una
//! copia si fa solo se l'immagine non c'è già, in un posto che non serve né al frame in costruzione
//! né a quello mostrato adesso: così non si vede mai un'immagine copiata a metà (per i grandi della
//! scelta, 2 mostrati e 2 liberi; per la sfilata, 8 mostrati e uno libero).

use crate::assets::WIN_BASE;
use crate::{Img, Port, map};

/// Copie tenute a mente: (parola nella finestra, base nel file, parole); 0 parole = vuoto.
const HELD: usize = 10;
/// Posti usati in un frame: (parola nella finestra, parole).
const USED: usize = 10;

pub struct Win {
    held: [(u16, u16, u16); HELD],
    used: [(u16, u16); USED],
    n_used: usize,
    prev: [(u16, u16); USED],
    n_prev: usize,
}

impl Default for Win {
    fn default() -> Self {
        Self::new()
    }
}

/// I due intervalli [a, a + aw) e [b, b + bw) si sovrappongono.
const fn overlap(a: u16, aw: u16, b: u16, bw: u16) -> bool {
    a < b + bw && b < a + aw
}

impl Win {
    pub const fn new() -> Self {
        Self {
            held: [(0, 0, 0); HELD],
            used: [(0, 0); USED],
            n_used: 0,
            prev: [(0, 0); USED],
            n_prev: 0,
        }
    }

    /// Inizio di un frame nuovo: i posti del frame appena costruito sono quelli che si vedranno.
    pub fn next_frame(&mut self) {
        self.prev = self.used;
        self.n_prev = self.n_used;
        self.n_used = 0;
    }

    fn busy(&self, at: u16, words: u16) -> bool {
        self.used[..self.n_used].iter().chain(&self.prev[..self.n_prev]).any(|&(a, w)| overlap(a, w, at, words))
    }

    fn mark(&mut self, at: u16, words: u16) {
        if self.n_used < USED {
            self.used[self.n_used] = (at, words);
            self.n_used += 1;
        }
    }

    /// L'immagine `img` della DDR3 (base nel file, `words` parole) in uno dei `count` posti a passo
    /// `stride` della finestra, pronta da disegnare; None se la grafica non è (ancora) caricata.
    #[inline(never)]
    pub fn place(&mut self, p: &mut dyn Port, img: &Img, words: u16, stride: u16, count: u16) -> Option<Img> {
        if p.read(map::STATUS) & map::GFX_OK == 0 {
            return None;
        }
        let at_slot = |at: u16| at.is_multiple_of(stride) && at / stride < count;
        // già nella finestra, in un posto di questa categoria
        let found = self
            .held
            .iter()
            .find(|&&(a, s, w)| w == words && s == img.base && at_slot(a))
            .map(|&(a, _, _)| a);
        let at = match found {
            Some(at) => at,
            None => {
                // un posto libero (né in questo frame né in quello mostrato), se no il primo non usato
                // in questo frame
                let free = (0..count).map(|i| i * stride).find(|&at| !self.busy(at, words));
                let at = free.or_else(|| {
                    (0..count).map(|i| i * stride).find(|&at| {
                        !self.used[..self.n_used].iter().any(|&(a, w)| overlap(a, w, at, words))
                    })
                })?;
                for h in self.held.iter_mut() {
                    if h.2 != 0 && overlap(h.0, h.2, at, words) {
                        *h = (0, 0, 0);
                    }
                }
                p.write(map::DMA, img.base as u32);
                p.write(map::DMA + 1, at as u32);
                p.write(map::DMA + 2, words as u32);
                while p.read(map::STATUS) & map::DMA_BUSY != 0 {}
                if let Some(h) = self.held.iter_mut().find(|h| h.2 == 0) {
                    *h = (at, img.base, words);
                }
                at
            }
        };
        self.mark(at, words);
        Some(Img { base: WIN_BASE + at, ..*img })
    }
}
