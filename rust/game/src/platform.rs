//! Funzioni dipendenti dal sistema operativo (e dal browser, nella versione web).

use std::fs;

/// Versione web (WebAssembly nel browser): niente file, processi né orologio di sistema.
pub const WEB: bool = cfg!(target_arch = "wasm32");

#[cfg(not(target_arch = "wasm32"))]
pub use std::time::Instant;

/// Nel browser `std::time::Instant` non c'è: stesso uso con l'orologio di miniquad (secondi).
#[cfg(target_arch = "wasm32")]
#[derive(Clone, Copy, Debug, PartialEq, PartialOrd)]
pub struct Instant(f64);

#[cfg(target_arch = "wasm32")]
mod web_instant {
    use super::Instant;
    use std::time::Duration;

    impl Instant {
        pub fn now() -> Self {
            Self(macroquad::miniquad::date::now())
        }

        pub fn elapsed(&self) -> Duration {
            Self::now() - *self
        }

        pub fn checked_duration_since(&self, earlier: Instant) -> Option<Duration> {
            (self.0 >= earlier.0).then(|| Duration::from_secs_f64(self.0 - earlier.0))
        }
    }

    impl std::ops::Sub for Instant {
        type Output = Duration;
        fn sub(self, earlier: Instant) -> Duration {
            Duration::from_secs_f64((self.0 - earlier.0).max(0.0))
        }
    }

    impl std::ops::Add<Duration> for Instant {
        type Output = Instant;
        fn add(self, d: Duration) -> Instant {
            Instant(self.0 + d.as_secs_f64())
        }
    }
}

/// Testo di un file di dati del gioco (configurazione, classifica); None se manca. Nel browser i
/// file non ci sono: lo stesso testo sta nel `localStorage`, con il nome del file come chiave
/// (`rust/web/storage.js`).
pub fn read_text(path: &std::path::Path) -> Option<String> {
    #[cfg(not(target_arch = "wasm32"))]
    return fs::read_to_string(path).ok();
    #[cfg(target_arch = "wasm32")]
    return web_storage::get(&web_storage::key(path));
}

/// Scrive un file di dati del gioco (nel browser nel `localStorage`, come `read_text`).
pub fn write_text(path: &std::path::Path, text: &[u8]) -> Result<(), String> {
    #[cfg(not(target_arch = "wasm32"))]
    return fs::write(path, text).map_err(|e| e.to_string());
    #[cfg(target_arch = "wasm32")]
    return web_storage::set(&web_storage::key(path), text);
}

#[cfg(target_arch = "wasm32")]
mod web_storage {
    unsafe extern "C" {
        /// Valore della chiave nel `localStorage`, copiato in `out` se ci sta: la sua lunghezza in
        /// byte (UTF-8), -1 se la chiave non c'è o il `localStorage` non si può usare.
        fn paddws_storage_get(key: *const u8, key_len: u32, out: *mut u8, out_len: u32) -> i32;
        /// Salva il valore; false se il browser lo rifiuta (navigazione privata, spazio finito).
        fn paddws_storage_set(key: *const u8, key_len: u32, value: *const u8, value_len: u32) -> bool;
    }

    /// Chiave del file: il suo nome, con il prefisso del gioco (es. `paddws/padd_config.json`).
    pub fn key(path: &std::path::Path) -> String {
        let name = path.file_name().map_or_else(|| path.to_string_lossy(), |n| n.to_string_lossy());
        format!("paddws/{name}")
    }

    pub fn get(key: &str) -> Option<String> {
        let mut buf = vec![0u8; 8192];
        loop {
            let len = unsafe { paddws_storage_get(key.as_ptr(), key.len() as u32, buf.as_mut_ptr(), buf.len() as u32) };
            let len = usize::try_from(len).ok()?;
            if len <= buf.len() {
                buf.truncate(len);
                return String::from_utf8(buf).ok();
            }
            buf.resize(len, 0); // non ci stava: si richiede con lo spazio giusto
        }
    }

    pub fn set(key: &str, value: &[u8]) -> Result<(), String> {
        let ok = unsafe { paddws_storage_set(key.as_ptr(), key.len() as u32, value.as_ptr(), value.len() as u32) };
        if ok { Ok(()) } else { Err("localStorage non disponibile".into()) }
    }

    /// Versione del plugin JavaScript che si aspetta il gioco (controllata da miniquad).
    #[unsafe(no_mangle)]
    pub extern "C" fn paddws_storage_crate_version() -> u32 {
        1
    }
}

/// Nel browser: la pagina è a schermo intero (anche aperta da "Aggiungi a Home"). Fuori dal
/// browser non serve: vale l'impostazione della configurazione.
#[cfg(target_arch = "wasm32")]
pub fn web_fullscreen() -> bool {
    unsafe { web_screen::paddws_is_fullscreen() }
}

#[cfg(not(target_arch = "wasm32"))]
pub fn web_fullscreen() -> bool {
    false
}

/// Nel browser: chiede o lascia lo schermo intero (`rust/web/fullscreen.js`); con OFF il tocco
/// non lo richiede più da sé.
#[cfg(target_arch = "wasm32")]
pub fn set_web_fullscreen(on: bool) {
    unsafe { web_screen::paddws_set_fullscreen(on) }
}

#[cfg(not(target_arch = "wasm32"))]
pub fn set_web_fullscreen(_on: bool) {}

#[cfg(target_arch = "wasm32")]
mod web_screen {
    unsafe extern "C" {
        pub fn paddws_is_fullscreen() -> bool;
        pub fn paddws_set_fullscreen(on: bool);
    }

    /// Versione del plugin JavaScript che si aspetta il gioco (controllata da miniquad).
    #[unsafe(no_mangle)]
    pub extern "C" fn paddws_screen_crate_version() -> u32 {
        1
    }
}

/// Seme diverso a ogni avvio, dall'orologio (funziona anche nel browser).
pub fn clock_seed() -> u32 {
    let now = macroquad::miniquad::date::now();
    ((now.fract() * 1e9) as u32) ^ (now as u32) | 1
}

/// Tempi dell'avvio, solo con la variabile d'ambiente PADDWS_STARTUP_TIMES: millisecondi dalla
/// prima chiamata (all'inizio di main) e dalla precedente, su stderr. Per capire dove va il
/// tempo sulle macchine lente (il Raspberry Pi 2 del Deck).
#[cfg(not(target_arch = "wasm32"))]
pub fn startup_mark(step: &str) {
    use std::sync::{Mutex, OnceLock};
    static ENABLED: OnceLock<bool> = OnceLock::new();
    static TIMES: Mutex<Option<(Instant, Instant)>> = Mutex::new(None);
    if !*ENABLED.get_or_init(|| std::env::var_os("PADDWS_STARTUP_TIMES").is_some()) {
        return;
    }
    let now = Instant::now();
    let mut t = TIMES.lock().unwrap_or_else(|e| e.into_inner());
    let (start, last) = t.get_or_insert((now, now));
    eprintln!(
        "avvio: {step:<16} {:6.0} ms (+{:4.0})",
        (now - *start).as_secs_f64() * 1000.0,
        (now - *last).as_secs_f64() * 1000.0
    );
    *last = now;
}

#[cfg(target_arch = "wasm32")]
pub fn startup_mark(_step: &str) {}

pub fn is_raspberry_pi() -> bool {
    fs::read_to_string("/proc/device-tree/model")
        .map(|m| m.contains("Raspberry Pi"))
        .unwrap_or(false)
}

pub fn shutdown_system() {
    let _ = std::process::Command::new("sudo")
        .args(["shutdown", "-h", "now"])
        .spawn();
}

/// Priorità del processo e del thread di gioco: riduce i frame persi quando altri
/// programmi lavorano in background. Su Windows il thread viene registrato nello
/// scheduler multimediale (MMCSS) come "Games", come fanno i giochi.
#[cfg(windows)]
pub fn boost_priority() {
    use windows_sys::Win32::System::Threading::{
        ABOVE_NORMAL_PRIORITY_CLASS, AvSetMmThreadCharacteristicsW, GetCurrentProcess, SetPriorityClass,
    };
    let task: Vec<u16> = "Games\0".encode_utf16().collect();
    let mut index = 0u32;
    unsafe {
        SetPriorityClass(GetCurrentProcess(), ABOVE_NORMAL_PRIORITY_CLASS);
        AvSetMmThreadCharacteristicsW(task.as_ptr(), &mut index);
    }
}

#[cfg(not(windows))]
pub fn boost_priority() {}

/// La finestra del gioco è quella in primo piano (serve per liberare il mouse catturato).
#[cfg(windows)]
pub fn window_focused() -> bool {
    use windows_sys::Win32::System::Threading::GetCurrentProcessId;
    use windows_sys::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId};
    unsafe {
        let window = GetForegroundWindow();
        let mut pid = 0u32;
        !window.is_null() && GetWindowThreadProcessId(window, &mut pid) != 0 && pid == GetCurrentProcessId()
    }
}

/// Libera subito il cursore bloccato nella finestra (all'uscita: la richiesta a miniquad non
/// arriverebbe più al ciclo dei messaggi).
#[cfg(windows)]
pub fn release_cursor() {
    use windows_sys::Win32::UI::WindowsAndMessaging::ClipCursor;
    unsafe {
        ClipCursor(std::ptr::null());
    }
}

#[cfg(not(windows))]
pub fn release_cursor() {}

/// Fuori da Windows non si controlla: nel browser il Pointer Lock lo rilascia il browser stesso
/// (Esc o cambio di scheda); su Linux il mouse si libera spegnendo l'opzione dal menu.
#[cfg(not(windows))]
pub fn window_focused() -> bool {
    true
}

/// Risoluzione del monitor principale (serve solo il rapporto d'aspetto).
#[cfg(windows)]
pub fn monitor_size() -> Option<(u32, u32)> {
    use windows_sys::Win32::UI::WindowsAndMessaging::{GetSystemMetrics, SM_CXSCREEN, SM_CYSCREEN};
    let (w, h) = unsafe { (GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)) };
    (w > 0 && h > 0).then_some((w as u32, h as u32))
}

/// Risoluzione del primo display collegato, letta da DRM/KMS (funziona anche senza X).
#[cfg(not(windows))]
pub fn monitor_size() -> Option<(u32, u32)> {
    let mut connectors: Vec<_> = fs::read_dir("/sys/class/drm")
        .ok()?
        .flatten()
        .map(|e| e.path())
        .collect();
    connectors.sort();
    connectors.into_iter().find_map(|dir| {
        let connected = fs::read_to_string(dir.join("status")).ok()?.trim() == "connected";
        let modes = fs::read_to_string(dir.join("modes")).ok()?;
        let (w, h) = modes.lines().next()?.split_once('x')?;
        let h = h.trim_end_matches(|c: char| !c.is_ascii_digit());
        connected.then_some((w.parse().ok()?, h.parse().ok()?))
    })
}

/// Frequenza di refresh del monitor principale in Hz.
#[cfg(windows)]
pub fn refresh_rate() -> Option<f64> {
    use windows_sys::Win32::Graphics::Gdi::{GetDC, GetDeviceCaps, ReleaseDC, VREFRESH};
    unsafe {
        let dc = GetDC(std::ptr::null_mut());
        let hz = GetDeviceCaps(dc, VREFRESH as _);
        ReleaseDC(std::ptr::null_mut(), dc);
        (hz > 1).then_some(hz as f64)
    }
}

#[cfg(not(windows))]
pub fn refresh_rate() -> Option<f64> {
    None
}
