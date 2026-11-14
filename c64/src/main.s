; PADD WS per Commodore 64: punto d'ingresso.
;
; Un solo modulo assemblato: i file degli altri sottosistemi sono inclusi qui. La logica di gioco
; è la traduzione del core Rust (rust/core), verificata tick per tick dal banco di prova
; rust/c64 (paddws-c64), che chiama le stesse routine per etichetta. Gira dalla cartuccia
; EasyFlash (src/crt.s), che lo copia in RAM e lo avvia con il SYS dello stub BASIC.

.setcpu "6502"
.macpack longbranch

.include "params.inc"
.include "assets.inc"
.include "sid_music.inc"
.include "voice.inc"
.include "ef.inc"

.segment "LOADADDR"
    .export __LOADADDR__ = *
    .addr *+2

; 10 SYS 2061
.segment "EXEHDR"
    .word @next
    .word 10
    .byte $9E, "2061", 0
@next:
    .word 0

.segment "CODE"

start:
    cld
    sei
    ldx #$ff
    txs
    ; BASIC e KERNAL spenti, I/O acceso
    lda #$35
    sta $01
    jsr title_unpack            ; prima di tutto: il segmento INIT diventa spazio delle variabili
    jsr hi_load                 ; classifica dalla cartuccia (anche hi_load è in INIT)
    jsr clear_vars
.ifdef HITEST
    ; prova della classifica nella flash, per VICE (-Define HITEST=n): n salvataggi, ognuno con il
    ; primo posto a nome VIC e un punto in più
    ldx #HITEST
:   txa
    pha
    lda #'V'
    sta ch_table
    lda #'I'
    sta ch_table+1
    lda #'C'
    sta ch_table+2
    inc ch_table+3
    bne :+
    inc ch_table+4
:   jsr hi_save
    pla
    tax
    dex
    bne :--
.endif
    jsr math_init
    jsr irq_init
    jsr video_init
    jsr input_init
    jsr sid_init
    cli
    jmp play_main

.include "math.s"
.include "game.s"
.include "next.s"
.include "cpu.s"
.include "video.s"
.include "input.s"
.include "play.s"
.include "pick.s"
.include "challenge.s"
.include "intro.s"
.include "ef.s"
.include "unpack.s"

; Variabili (BSS) a zero, come quando nel .prg al loro posto c'erano zeri: prima ci sono i dati
; di INIT.
.import __BSS_RUN__, __BSS_SIZE__
.segment "BOOTCODE"           ; solo all'avvio (unpack.s)
.proc clear_vars
    lda #<__BSS_RUN__
    sta ptr
    lda #>__BSS_RUN__
    sta ptr+1
    ldx #>__BSS_SIZE__          ; pagine intere
    lda #0
    tay
    cpx #0
    beq last
page:
    sta (ptr),y
    iny
    bne page
    inc ptr+1
    dex
    bne page
last:
    ldy #<__BSS_SIZE__          ; il resto
    beq done
:   dey
    sta (ptr),y
    bne :-
done:
    rts
.endproc
.segment "CODE"
.include "attract.s"
.include "sid.s"
.include "supers.s"
.include "ending.s"
