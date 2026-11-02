//! Generatore pseudo-casuale xorshift32: tre shift e tre xor, banale da
//! realizzare in hardware e identico bit per bit su ogni piattaforma.

use crate::fixed::{Fx, ONE};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Rng(u32);

impl Rng {
    pub const fn new(seed: u32) -> Self {
        // lo stato zero è un punto fisso di xorshift: va evitato
        Self(if seed == 0 { 0x2545_F491 } else { seed })
    }

    pub fn next_u32(&mut self) -> u32 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.0 = x;
        x
    }

    /// Intero in `lo..hi` (hi escluso).
    pub fn range(&mut self, lo: i32, hi: i32) -> i32 {
        lo + (self.next_u32() % (hi - lo) as u32) as i32
    }

    /// +1 o -1.
    pub fn sign(&mut self) -> i32 {
        if self.next_u32() >> 31 == 0 { 1 } else { -1 }
    }

    /// Valore uniforme in `[-1, 1)` come Fx.
    pub fn unit(&mut self) -> Fx {
        (self.next_u32() >> 15) as Fx - ONE
    }

    /// Intero in `0..n` (n < 65536) senza divisioni: (16 bit casuali * n) >> 16.
    pub fn below(&mut self, n: u32) -> u32 {
        ((self.next_u32() >> 16) * n) >> 16
    }

    /// 16 bit casuali (i più alti dello stato), in `0..65536`: `below(n) == 0` equivale a
    /// `bits16() < 65535 / n + 1`.
    pub fn bits16(&mut self) -> u32 {
        self.next_u32() >> 16
    }

    /// Frazione casuale in `[0, 1)` come Fx.
    pub fn frac(&mut self) -> Fx {
        (self.next_u32() >> 16) as Fx
    }

    pub fn state(&self) -> u32 {
        self.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_sequence() {
        // valori di riferimento di xorshift32 con seme 1 (Marsaglia 2003)
        let mut rng = Rng::new(1);
        assert_eq!(rng.next_u32(), 270_369);
        assert_eq!(rng.next_u32(), 67_634_689);
    }

    #[test]
    fn ranges_are_respected() {
        let mut rng = Rng::new(42);
        for _ in 0..10_000 {
            assert!((2..4).contains(&rng.range(2, 4)));
            let u = rng.unit();
            assert!((-ONE..ONE).contains(&u));
        }
    }
}
