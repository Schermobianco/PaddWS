/* Firmware del core MiSTer: una sola RAM (BRAM di pong_logic_rv.v) per codice, costanti, dati e
   stack. RAM_SIZE deve coincidere con map::RAM_SIZE e con FW_BYTES di rtl/gen/pong_fw.vh
   (tools/gen_mister_fw.py controlla che codice, dati e stack ci stiano). */
MEMORY { RAM : ORIGIN = 0x00000000, LENGTH = 64K }
ENTRY(_start)
SECTIONS {
  .text : { KEEP(*(.text.init)) *(.text .text.*) } > RAM
  .rodata : ALIGN(4) { *(.srodata .srodata.*) *(.rodata .rodata.*) } > RAM
  /* niente dati inizializzati in scrittura: la BRAM si carica una volta sola, alla sintesi */
  .data : ALIGN(4) { *(.sdata .sdata.*) *(.data .data.*) } > RAM
  ASSERT(SIZEOF(.data) == 0, "il firmware non deve avere .data")
  .bss (NOLOAD) : ALIGN(4) { __bss_start = .; *(.sbss .sbss.*) *(.bss .bss.*) *(COMMON) . = ALIGN(4); __bss_end = .; } > RAM
  __image_end = __bss_start;
  __stack_top = ORIGIN(RAM) + LENGTH(RAM);
  /DISCARD/ : { *(.eh_frame) *(.eh_frame_hdr) }
}
