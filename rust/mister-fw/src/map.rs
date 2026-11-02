//! Mappa della memoria e dei registri tra il firmware e `mister/rtl/pong_logic_rv.v`.
//!
//! - RAM (BRAM) da `RAM_BASE`: codice, costanti, dati e stack, caricata dalla sintesi
//!   (`mister/rtl/gen/pong_fw_b*.hex`). Il bit 31 dell'indirizzo a zero: la cache dati del
//!   VexRiscv la tratta come memoria.
//! - Registri da `IO_BASE` (bit 31 a uno: accessi senza cache), una parola da 32 bit ciascuno.
//!   Le letture danno i comandi dell'HDL, le scritture lo stato della partita.
//!
//! Protocollo: l'HDL conta le nuove partite (`reset` di `pong_logic_rv`) in `STATUS[7:0]` e segna
//! un tick da eseguire in `STATUS[8]` (`step`); in entrambi i casi tiene alto `busy`. Il firmware
//! scrive le parole di stato in `WORD0 + 4 * i` e poi in `DONE` il numero della partita che ha
//! servito: l'HDL abbassa `busy` solo se coincide con il conteggio attuale. Così una nuova partita
//! arrivata durante un tick annulla quel tick: `busy` resta alto finché il firmware non ha
//! preparato la nuova partita.

/// Inizio della RAM.
pub const RAM_BASE: u32 = 0x0000_0000;
/// Dimensione della RAM in byte (codice, dati e stack): la stessa di `pong_logic_rv.v`.
pub const RAM_SIZE: u32 = 64 * 1024;
/// Inizio dei registri.
pub const IO_BASE: u32 = 0xF000_0000;

// ---------------------------------------------------------------- letture (HDL -> firmware)

/// bit 0-7 numero della partita (sale a ogni `reset`), bit 8 tick da eseguire.
pub const R_STATUS: u32 = 0x000;
pub const STATUS_EPOCH: u32 = 0xFF;
pub const STATUS_STEP: u32 = 1 << 8;
/// Partita, letta all'ultimo `reset`: bit 0 due giocatori, 1 EVO, 2 NEXT, 3 mosse speciali,
/// 4-5 difficoltà, 6-14 e 15-23 bonus scelti (3 codici da 3 bit per giocatore), 24-29 tipi di
/// racchetta (3 bit per lato, 7 = senza tipo). Come gli ingressi di `pong_logic_rv`.
pub const R_CONFIG: u32 = 0x004;
/// Seme della partita.
pub const R_SEED: u32 = 0x008;
/// CPU, lette all'ultimo `reset`: bit 0-3 e 4-7 livello della CPU di sinistra e di destra
/// (0-3 la difficoltà, 4-10 CHALLENGE), 8-9 e 10-11 come comandano la racchetta (0 joystick,
/// 1 spinner, 2 tastiera).
pub const R_CPU: u32 = 0x00C;
/// Semi delle due CPU (`Cpu::new`).
pub const R_CPU_SEED0: u32 = 0x010;
pub const R_CPU_SEED1: u32 = 0x014;
/// Comandi del tick (all'ultimo `step`): bit 0-15 tasti (byte basso = sinistro), 16-31
/// posizioni dell'encoder. Come la parola di `trace_input.hex`.
pub const R_INPUT: u32 = 0x018;
/// bit 0-3 mosse speciali (2 bit per giocatore), 4-5 lati comandati dalla CPU in questo tick.
pub const R_INPUT2: u32 = 0x01C;
/// Frequenza della simulazione (parametro dell'HDL: 240 nel core, altre nelle tracce di prova).
pub const R_TICK_HZ: u32 = 0x020;
/// Campo di gioco in pixel: bit 0-15 larghezza, 16-31 altezza (parametro dell'HDL).
pub const R_FIELD: u32 = 0x024;

/// Modifiche di prova allo stato (solo simulazione: nella sintesi i registri restano a zero).
/// Il simulatore dei frame (`mister/sim/frames`) scrive fino a `PATCH_MAX` voci e il loro numero;
/// il firmware le applica all'inizio del tick successivo e le conferma con `W_PATCH_ACK`.
pub const R_PATCH_N: u32 = 0x040;
/// Voce `k`: `R_PATCH0 + 8 * k` campo (bit 0-7, `PATCH_*`) e indice (bit 8-15), poi il valore.
pub const R_PATCH0: u32 = 0x080;
pub const PATCH_MAX: u32 = 16;
/// Campi modificabili: indice = lato (posto della riserva: 3 * lato + posto; capsula: 0-3).
pub const PATCH_SCORE: u32 = 1;
/// bonus armato: codice a 4 bit, 8 = nessuno
pub const PATCH_ARMED: u32 = 2;
/// posto della riserva: codice a 4 bit, 8 = vuoto
pub const PATCH_RESERVE: u32 = 3;
pub const PATCH_SELECTED: u32 = 4;
pub const PATCH_COOLDOWN: u32 = 5;
/// barra delle mosse speciali
pub const PATCH_METER: u32 = 6;
/// capsula: bonus (8 o più = nessuna capsula), poi posizione e velocità
pub const PATCH_CAPSULE: u32 = 7;
pub const PATCH_CAPSULE_X: u32 = 8;
pub const PATCH_CAPSULE_Y: u32 = 9;
pub const PATCH_CAPSULE_VX: u32 = 10;
pub const PATCH_CAPSULE_VY: u32 = 11;

// ---------------------------------------------------------------- scritture (firmware -> HDL)

/// Fine del lavoro: il valore è il numero della partita servita (bit 0-7).
pub const W_DONE: u32 = 0x000;
/// Errore fatale del firmware (panic): il codice resta nel registro, `busy` resta alto.
pub const W_PANIC: u32 = 0x004;
/// Modifiche di prova applicate: l'HDL azzera `R_PATCH_N`.
pub const W_PATCH_ACK: u32 = 0x008;
/// Parole di stato: `WORD0 + 4 * i`, `i` < [`crate::words::WORDS`].
pub const W_WORD0: u32 = 0x100;
