//! Aritmetica a virgola fissa Q16.16 su `i32`.
//!
//! Tutte le grandezze della simulazione (posizioni, velocità, moltiplicatori)
//! sono `Fx`: 16 bit di parte intera con segno e 16 di parte frazionaria.
//! Le moltiplicazioni passano per un intermedio a 64 bit e troncano verso lo
//! zero, così il comportamento è simmetrico per i due giocatori (a sinistra le
//! velocità sono negative) ed è facile da replicare in hardware.

pub type Fx = i32;

pub const FRAC_BITS: u32 = 16;
pub const ONE: Fx = 1 << FRAC_BITS;

/// Intero -> Fx.
pub const fn int(v: i32) -> Fx {
    v << FRAC_BITS
}

/// Parte intera (arrotondata verso il basso).
pub const fn floor(v: Fx) -> i32 {
    v >> FRAC_BITS
}

/// Conversione da virgola mobile: usata solo in fase di configurazione, mai nella simulazione.
pub fn from_f64(v: f64) -> Fx {
    let scaled = v * ONE as f64;
    // arrotondamento al più vicino (i cast troncano; `round` non esiste in no_std)
    (if scaled >= 0.0 { scaled + 0.5 } else { scaled - 0.5 }) as Fx
}

/// Parte intera troncata verso lo zero, come `int()` in Python (solo configurazione).
pub fn trunc_f64(v: f64) -> f64 {
    v as i64 as f64
}

/// Per il rendering.
pub fn to_f32(v: Fx) -> f32 {
    v as f32 / ONE as f32
}

/// a * b
pub const fn mul(a: Fx, b: Fx) -> Fx {
    ((a as i64 * b as i64) / ONE as i64) as Fx
}

/// a * b / c, con un solo arrotondamento finale.
pub const fn muldiv(a: Fx, b: Fx, c: Fx) -> Fx {
    ((a as i64 * b as i64) / c as i64) as Fx
}

/// a / b
pub const fn div(a: Fx, b: Fx) -> Fx {
    muldiv(a, ONE, b)
}

/// Bit frazionari dei reciproci precalcolati (Q8.24): più precisi di Q16 perché
/// servono per dividere per grandezze fino all'altezza del campo.
pub const RECIP_BITS: u32 = 24;

/// Reciproco 1/v in Q8.24. Usa una divisione: solo in fase di configurazione.
pub const fn recip(v: Fx) -> i32 {
    // arrotondato al più vicino: un reciproco troncato per difetto perderebbe un
    // bit sui quozienti esatti (es. 5 * 1/20 = 0.24998)
    (((1i64 << (RECIP_BITS + FRAC_BITS)) + v as i64 / 2) / v as i64) as i32
}

/// a * r con r reciproco Q8.24: sostituisce la divisione nella simulazione
/// (in hardware è un moltiplicatore e uno shift).
pub const fn mul_recip(a: Fx, r: i32) -> Fx {
    ((a as i64 * r as i64) / (1i64 << RECIP_BITS)) as Fx
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn basic_operations() {
        assert_eq!(mul(int(3), from_f64(1.25)), from_f64(3.75));
        assert_eq!(div(int(3), int(4)), from_f64(0.75));
        assert_eq!(muldiv(int(6), int(5), int(3)), int(10));
        assert_eq!(floor(from_f64(-0.5)), -1);
    }

    #[test]
    fn reciprocal_replaces_division() {
        let r = recip(int(20));
        assert_eq!(mul_recip(int(5), r), from_f64(0.25));
        assert_eq!(mul_recip(-int(5), r), -mul_recip(int(5), r));
    }

    #[test]
    fn multiplication_is_symmetric_in_sign() {
        let a = from_f64(2.3);
        let k = from_f64(1.25);
        assert_eq!(mul(-a, k), -mul(a, k));
    }
}
