// Generato da tools/gen_mister_fw.py: non modificare a mano.
// Firmware RISC-V (rust/mister-fw), impronta dei sorgenti 131ed01b9fd6418c
localparam integer FW_RAM_BYTES = 163840;   // BRAM: codice, costanti, .bss e stack
localparam integer FW_IMAGE_WORDS = 29247;   // parole nei file pong_fw_b*.hex
localparam integer FW_BSS_END = 121928;   // fine di .bss: sopra c'è lo stack
