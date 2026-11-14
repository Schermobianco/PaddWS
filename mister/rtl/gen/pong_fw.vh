// Generato da tools/gen_mister_fw.py: non modificare a mano.
// Firmware RISC-V (rust/mister-fw), impronta dei sorgenti 0f14dac36c4c6dab
localparam integer FW_RAM_BYTES = 65536;   // BRAM: codice, costanti, .bss e stack
localparam integer FW_IMAGE_WORDS = 13078;   // parole nei file pong_fw_b*.hex
localparam integer FW_BSS_END = 57240;   // fine di .bss: sopra c'è lo stack
