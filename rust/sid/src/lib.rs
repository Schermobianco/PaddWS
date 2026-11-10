//! SID di PADD WS, scritto da noi (licenza GPL v3 o successiva): il port in Rust del player della musica del
//! MiSTer e un SID semplificato che ha solo quello che usano le nostre musiche. Il gioco Rust (PC,
//! Raspberry e web) suona così le musiche in tempo reale, con il tempo che cambia al match point e
//! nel bullet time.
//!
//! - `rom`: la ROM della musica di `tools/gen_sid_music.py`, la stessa del MiSTer e del C64.
//! - `player`: il player, con le stesse scritture ai registri del player Verilog.
//! - `chip`: il SID (tre voci, quattro forme d'onda, ADSR, il filtro dell'8580).
//! - `engine`: player e SID insieme, ricampionati per il dispositivo audio; le regole di tempo.
//! - `voice`: le voci "da SID" del MiSTer (il nome dell'avversario con il trucco di $D418, le voci
//!   di partita sommate all'uscita), con la ROM delle voci di `tools/gen_voices.py`.

pub mod chip;
pub mod engine;
pub mod player;
pub mod rom;
pub mod voice;

pub use engine::Music;
pub use rom::Rom;
pub use voice::{Call, VoiceRom};
