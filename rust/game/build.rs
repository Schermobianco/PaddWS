//! Solo per Windows:
//! - incorpora l'icona (assets/icons/paddws.ico) nell'eseguibile;
//! - esporta i simboli che chiedono ai driver NVIDIA (Optimus) e AMD (PowerXpress)
//!   di usare la GPU dedicata sui portatili ibridi.

use std::path::PathBuf;

fn main() {
    let target = std::env::var("TARGET").unwrap_or_default();
    if !target.contains("windows") {
        return;
    }
    let dir = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));

    // risorsa con l'icona: il file .rc va generato con il percorso assoluto dell'.ico
    let ico = dir
        .join("../../assets/icons/paddws.ico")
        .canonicalize()
        .expect("assets/icons/paddws.ico");
    let ico = ico.to_string_lossy().trim_start_matches(r"\\?\").replace('\\', "/");
    let rc = PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR")).join("paddws.rc");
    std::fs::write(&rc, format!("1 ICON \"{ico}\"\n")).expect("scrittura del file .rc");
    embed_resource::compile(&rc, embed_resource::NONE)
        .manifest_optional()
        .expect("compilazione dell'icona");
    println!("cargo:rerun-if-changed=../../assets/icons/paddws.ico");

    if target.contains("msvc") {
        println!("cargo:rustc-link-arg-bins=/EXPORT:NvOptimusEnablement");
        println!("cargo:rustc-link-arg-bins=/EXPORT:AmdPowerXpressRequestHighPerformance");
    } else {
        // linker GNU: le esportazioni si dichiarano con un file .def
        println!("cargo:rustc-link-arg-bins={}/gpu_exports.def", dir.display());
        println!("cargo:rerun-if-changed=gpu_exports.def");
    }
}
