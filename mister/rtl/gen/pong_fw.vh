// Generato da tools/gen_mister_fw.py: non modificare a mano.
// Firmware RISC-V (rust/mister-fw), impronta dei sorgenti 2804444f4d49603a
localparam integer FW_RAM_BYTES = 65536;   // BRAM: codice, costanti, .bss e stack
localparam integer FW_IMAGE_WORDS = 12974;   // parole nei file pong_fw_b*.hex
localparam integer FW_BSS_END = 56784;   // fine di .bss: sopra c'è lo stack
