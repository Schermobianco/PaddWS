//! Firmware RV32IM del core MiSTer: avvio, registri MMIO e ciclo di `Engine`.
//!
//! Si compila solo per `riscv32im-unknown-none-elf` (`python tools/gen_mister_fw.py`); sulle
//! altre piattaforme resta un eseguibile vuoto, così il workspace si compila e si prova come prima.

#![cfg_attr(target_arch = "riscv32", no_std)]
#![cfg_attr(target_arch = "riscv32", no_main)]

#[cfg(target_arch = "riscv32")]
mod rv {
    use core::mem::MaybeUninit;
    use core::ptr::{addr_of_mut, read_volatile, write_volatile};

    use paddws_mister_fw::engine::{Bus, Engine};
    use paddws_mister_fw::map::{IO_BASE, W_PANIC};

    struct Mmio;

    impl Bus for Mmio {
        #[inline(always)]
        fn read(&mut self, reg: u32) -> u32 {
            // SAFETY: registri di pong_logic_rv, allineati, sempre presenti
            unsafe { read_volatile((IO_BASE + reg) as *const u32) }
        }

        #[inline(always)]
        fn write(&mut self, reg: u32, value: u32) {
            // SAFETY: come sopra
            unsafe { write_volatile((IO_BASE + reg) as *mut u32, value) }
        }
    }

    // Avvio: stack in cima alla RAM, .bss a zero (non c'è .data: lo script del linker lo vieta).
    core::arch::global_asm!(
        ".section .text.init, \"ax\"",
        ".global _start",
        "_start:",
        "  la sp, __stack_top",
        "  la t0, __bss_start",
        "  la t1, __bss_end",
        "1: bgeu t0, t1, 2f",
        "  sw zero, 0(t0)",
        "  addi t0, t0, 4",
        "  j 1b",
        "2: call fw_main",
        "3: j 3b",
    );

    /// Stato del firmware, in .bss (azzerato all'avvio, poi costruito sul posto da `Engine::init`).
    static mut ENGINE: MaybeUninit<Engine> = MaybeUninit::uninit();

    unsafe extern "C" {
        /// fine di .bss (script del linker): sopra c'è lo stack, che scende dalla fine della RAM
        static __bss_end: u32;
    }

    /// Sentinella sul fondo dello stack: se cambia, lo stack ha invaso .bss.
    const CANARY: u32 = 0x5AFE_57AC;

    #[unsafe(no_mangle)]
    extern "C" fn fw_main() -> ! {
        let mut bus = Mmio;
        let canary = (&raw const __bss_end) as *mut u32;
        // SAFETY: la prima parola sopra .bss è libera (lo stack la raggiunge solo se trabocca)
        unsafe { write_volatile(canary, CANARY) };
        // SAFETY: unico riferimento a ENGINE, preso una volta sola (non ci sono interruzioni)
        let engine = Engine::init(unsafe { &mut *addr_of_mut!(ENGINE) }, &mut bus);
        loop {
            engine.poll(&mut bus);
            // SAFETY: come sopra
            if unsafe { read_volatile(canary) } != CANARY {
                panic!();
            }
        }
    }

    #[panic_handler]
    fn panic(_: &core::panic::PanicInfo) -> ! {
        // busy resta alto: la partita si ferma invece di andare avanti con uno stato sbagliato
        Mmio.write(W_PANIC, 0xDEAD);
        loop {}
    }
}

#[cfg(not(target_arch = "riscv32"))]
fn main() {
    eprintln!("paddws-mister-fw è il firmware RISC-V del core MiSTer: si compila con tools/gen_mister_fw.py");
}
