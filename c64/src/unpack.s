; Avvio, prima delle variabili: tutto qui sta nel segmento INIT, che nel .prg occupa il loro posto.
; - Le routine che servono solo all'avvio (segmento BOOTCODE: clear_vars, math_init, irq_init,
;   video_init, input_init, sid_init e l'auto-test dell'accensione) vanno a $F800, nella bitmap
;   dell'attract, che fino alle strisce non serve: così non occupano il programma. Nel .prg sono
;   a $D100, dopo l'immagine della RAM della cartuccia: nella flash (banco 4, ROML da $8900), da
;   dove si copiano.
; - Il titolo dell'attract (gen/title.bin, 8 pagine nel banco PICK_BANK della cartuccia) passa per
;   $E000 e va nella RAM sotto l'I/O a TITLE_BUF, dove copy_rows lo legge con l'I/O spento.
; - La pagina $FF00 dalla cartuccia: il .prg non arriva alla RAM sotto il KERNAL, dove ci sono i
;   caratteri della capsula del BULLET e quelli che sostituisce (bullet_chars, video.s), l'RTS di
;   VOICE_COUNT e i caratteri che la barra delle mosse speciali prende in NEXT.
; - Le routine delle mosse speciali sempre in memoria (segmento LOWCODE, src/supers.s): nel .prg
;   dopo INIT, vanno nella pagina 2 prima che le variabili coprano INIT.

TITLE_BUF   = $d800
TITLE_PAGES = 8
TITLE_SRC   = $80 + $0900 / 256 ; pagina del titolo nel banco PICK_BANK (gen/pick_bank.bin)
BOOT_IMG    = $D100             ; routine dell'avvio nel .prg (paddws.cfg), poi nella flash:
BOOT_BANK   = PRG_BANK + (BOOT_IMG - $0800) / $4000
BOOT_SRC    = $80 + ((BOOT_IMG - $0800) .mod $4000) / 256
BOOT_RAM    = $F800
.assert ((BOOT_IMG - $0800) .mod $4000) + $0700 <= $2000, error, "routine dell'avvio oltre la ROML del banco"
.assert __BOOTCODE_LOAD__ = BOOT_IMG .and __BOOTCODE_RUN__ = BOOT_RAM, lderror, "routine dell'avvio fuori posto"

.assert TITLE_SIZE <= TITLE_PAGES * 256 .and TITLE_BUF + TITLE_PAGES * 256 <= $e000, error, "titolo oltre la RAM sotto l'I/O"

.import __BOOTCODE_LOAD__, __BOOTCODE_RUN__, __BOOTCODE_SIZE__
.import __LOWCODE_LOAD__, __LOWCODE_RUN__, __LOWCODE_SIZE__
.assert __LOWCODE_SIZE__ > 0 .and __LOWCODE_SIZE__ < 256, lderror, "LOWCODE: la copia conta in un byte"

.segment "INIT"

; Con gli interrupt spenti e $01 = $35 (start).
.proc title_unpack
    ; routine delle mosse speciali sempre in memoria (segmento LOWCODE, src/supers.s): da qui
    ; alla pagina 2, prima che le variabili prendano il posto di INIT
    ldx #<__LOWCODE_SIZE__
:   lda __LOWCODE_LOAD__ - 1,x
    sta __LOWCODE_RUN__ - 1,x
    dex
    bne :-
    ; animazione del colpo di una mossa (supers.s) ferma dall'accensione: NEXTBSS non si azzera
    lda #0
    sta sm_kick
    sta sm_kick + 4
    ; routine dell'avvio al loro posto, dalla flash
    lda #BOOT_SRC
    sta ef_src+2
    lda #BOOT_BANK
    ldx #>(__BOOTCODE_SIZE__ + 255)
    ldy #>BOOT_RAM
    jsr ef_copy
    ; titolo: dalla cartuccia a $E000, poi nella RAM sotto l'I/O
    lda #TITLE_SRC
    sta ef_src+2
    lda #PICK_BANK
    ldx #TITLE_PAGES
    ldy #>VOICE_BASE
    jsr ef_copy
    lda #<VOICE_BASE
    sta ptr2
    lda #>VOICE_BASE
    sta ptr2+1
    lda #<TITLE_BUF
    sta ptr
    lda #>TITLE_BUF
    sta ptr+1
    lda #$34                    ; RAM sotto l'I/O
    sta $01
    ldx #TITLE_PAGES
    jsr copy_pages
    lda #$35                    ; I/O: la RAM della cartuccia
    sta $01
    ; pagina $FF00
    lda #$80 + $0800 / 256
    sta ef_src+2
    lda #PICK_BANK
    ldx #1
    ldy #>bullet_tiles
    jmp ef_copy
.endproc

.segment "CODE"
