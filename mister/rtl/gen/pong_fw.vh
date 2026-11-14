// Generato da tools/gen_mister_fw.py: non modificare a mano.
// Firmware RISC-V (rust/mister-fw), impronta dei sorgenti 68d55d7fb769e7fc
localparam integer FW_RAM_BYTES = 65536;   // BRAM: codice, costanti, .bss e stack
localparam integer FW_IMAGE_WORDS = 13064;   // parole nei file pong_fw_b*.hex
localparam integer FW_BSS_END = 57184;   // fine di .bss: sopra c'è lo stack
