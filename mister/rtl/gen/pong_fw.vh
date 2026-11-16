// Generato da tools/gen_mister_fw.py: non modificare a mano.
// Firmware RISC-V (rust/mister-fw), impronta dei sorgenti f1a7d1794c36ec46
localparam integer FW_RAM_BYTES = 163840;   // BRAM: codice, costanti, .bss e stack
localparam integer FW_IMAGE_WORDS = 29271;   // parole nei file pong_fw_b*.hex
localparam integer FW_BSS_END = 122024;   // fine di .bss: sopra c'è lo stack
