//! Script del linker (link.x) solo per il firmware RISC-V.

fn main() {
    println!("cargo:rerun-if-changed=link.x");
    if std::env::var("CARGO_CFG_TARGET_ARCH").as_deref() == Ok("riscv32") {
        let dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
        println!("cargo:rustc-link-arg-bin=paddws-mister-fw=-T{dir}/link.x");
    }
}
