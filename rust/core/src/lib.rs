//! Logica di gioco di PADD WS.
//!
//! - `no_std`, nessuna allocazione, solo aritmetica intera (Q16.16, vedi [`fixed`]);
//! - tick fisso a [`TICK_HZ`] (sul C64 a [`C64_TICK_HZ`], un tick per frame), input esplicito
//!   per ogni tick ([`Input`]);
//! - generatore casuale [`Rng`] (xorshift32) con seme esplicito.
//!
//! A parità di parametri, seme e sequenza di input il risultato è identico bit
//! per bit: questo crate è il modello di riferimento per il core MiSTer FPGA e per la
//! versione C64.

#![cfg_attr(not(test), no_std)]

pub mod challenge;
pub mod cpu;
pub mod fixed;
pub mod game;
pub mod next;
pub mod params;
pub mod rng;

pub use cpu::{CPU_LEVELS, Control, Cpu, CpuLevel, cpu_seed};
pub use fixed::Fx;
pub use game::{Ball, Event, Events, Input, Match, Paddle, PlayerInput, Side};
pub use next::{
    Bonus, Capsule, GUARDIAN_SECTORS, GUARDIAN_WALL, MAX_SPECIAL_LEVEL, Next, NextPlayer, PaddleKind, Shot, Special, SuperAnim,
    guardian_sector, slowed,
};
pub use params::{C64_TICK_HZ, DIFFICULTY_LEVELS, NextTuning, PaddleParams, PaddleTuning, Params, TICK_HZ, Tuning};
pub use rng::Rng;
