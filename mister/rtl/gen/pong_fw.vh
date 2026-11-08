// Generato da tools/gen_mister_fw.py: non modificare a mano.
// Firmware RISC-V (rust/mister-fw), impronta dei sorgenti 2612a14bd5a1bcec
localparam integer FW_RAM_BYTES = 65536;   // BRAM: codice, costanti, .bss e stack
localparam integer FW_IMAGE_WORDS = 13026;   // parole nei file pong_fw_b*.hex
localparam integer FW_BSS_END = 57032;   // fine di .bss: sopra c'è lo stack
