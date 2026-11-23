// Generato da tools/gen_mister_fw.py: non modificare a mano.
// Firmware RISC-V (rust/mister-fw), impronta dei sorgenti 3e600181e27222a1
localparam integer FW_RAM_BYTES = 163840;   // BRAM: codice, costanti, .bss e stack
localparam integer FW_IMAGE_WORDS = 28667;   // parole nei file pong_fw_b*.hex
localparam integer FW_BSS_END = 119816;   // fine di .bss: sopra c'è lo stack
