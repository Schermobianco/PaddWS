; Cartuccia EasyFlash: registri, banchi e RAM della cartuccia, comuni al programma (src/ef.s,
; challenge.s, pick.s), all'avvio (src/crt.s) e a tools/make_crt.py, che legge le costanti da qui.
;
; Banchi da 16 KB: ROML a $8000 (modi a 8K e a 16K, con $01 = $37; Ultimax), ROMH a $A000 (16K)
; o a $E000 (Ultimax). Le due metà sono due flash distinte (Am29F040: 8 settori da 64 KB, cioè da
; 8 banchi), che si scrivono solo nel modo Ultimax.

EF_BANK     = $DE00             ; banco (0-63)
EF_MODE     = $DE02             ; bit 2 = GAME dal bit 0, bit 1 = EXROM, bit 0 = GAME
EF_OFF      = $04               ; cartuccia spenta
EF_ULTIMAX  = $05               ; ROML a $8000 e ROMH a $E000, anche in scrittura; della RAM del C64
                                ; restano solo $0000-$0FFF
EF_8K       = $06
EF_16K      = $07
EF_RAM      = $DF00             ; 256 byte di RAM della cartuccia, visibili con l'I/O acceso

; Banchi (ROML)
PRG_BANK    = 1                 ; 1-4: il programma da $0800 a $CFFF, poi l'immagine di EF_RAM
VOICE_BANK0 = 5                 ; 5-11: la voce del tipo 0 (ARCADE), poi una per tipo
PICK_BANK   = 12                ; i caratteri della scelta dei bonus, la pagina $FF00 e il titolo
                                ; (gen/pick_bank.bin)
WIN_BANK    = 13                ; "YOU WIN!" con il player delle voci (voice.inc, WIN_RUN)
END_BANK    = 14                ; 14-15: il finale di CHALLENGE (src/ending.s)
HI_BANK     = 16                ; la classifica di CHALLENGE: settore 2 della ROML (banchi 16-23),
                                ; solo per lei; nella ROMH dello stesso banco i vettori (un RTI)
