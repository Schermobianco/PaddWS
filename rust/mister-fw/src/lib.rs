//! Firmware del core MiSTer di PADD WS: il processore RISC-V soft (VexRiscv, RV32IM) di
//! `mister/rtl/pong_logic_rv.v` esegue il core Rust (`paddws-core`) al posto della logica di
//! gioco e delle CPU avversarie scritte in Verilog.
//!
//! - [`map`]: indirizzi della memoria e dei registri MMIO, gli stessi di `pong_logic_rv.v`;
//! - [`words`]: parole di stato (il formato delle tracce di paddws-trace, vedi
//!   `words.rs`) e codifica dei comandi: un'unica codifica per le tracce e il firmware;
//! - [`engine`]: il ciclo del firmware (nuova partita, tick con le CPU), generico sul bus, così
//!   gira uguale nel firmware vero e nei banchi di prova sul PC.

#![no_std]

pub mod engine;
pub mod map;
pub mod words;
