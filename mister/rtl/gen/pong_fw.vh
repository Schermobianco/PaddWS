// Generato da tools/gen_mister_fw.py: non modificare a mano.
// Firmware RISC-V (rust/mister-fw), impronta dei sorgenti 07531d266732af1c
localparam integer FW_RAM_BYTES = 163840;   // BRAM: codice, costanti, .bss e stack
localparam integer FW_IMAGE_WORDS = 28205;   // parole nei file pong_fw_b*.hex
localparam integer FW_BSS_END = 117976;   // fine di .bss: sopra c'è lo stack
