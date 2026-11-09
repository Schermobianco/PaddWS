; Avvio della cartuccia EasyFlash (paddws.crt, tools/make_crt.py): all'accensione copia il
; programma in RAM e lo avvia, poi si spegne. Nella flash restano le voci, i caratteri della
; scelta dei bonus, il finale, la HOW TO PLAY e la classifica: le routine del programma che li
; leggono e la scrivono (src/ef.s) stanno nella RAM della cartuccia, dove le copia la fine di
; questo avvio.
;
; Banchi da 16 KB (nel modo a 16K ROML a $8000, ROMH a $A000; costanti in src/ef.inc):
;   0      ROMH: questo avvio (a $E000 nel modo Ultimax dell'accensione), il nome e i vettori
;   1-4    il programma (paddws.prg, da $0800 a $CFFF: 200 pagine), poi l'immagine delle routine
;          di src/ef.s (da $D000 nel .prg, nella ROML del banco 4 a $8800)
;   5-11   ROML: il file voce di ogni tipo di racchetta (voice.s, senza l'indirizzo di caricamento;
;          da VOICE_RES la parte che resta del file del primo livello)
;   12     ROML: il set di caratteri della scelta dei bonus, la pagina $FF00 e il titolo (gen/pick_bank.bin)
;   13     ROML: il banco della vittoria, "YOU WIN!" e "PERFECT!" con il player delle voci
;   14-15  ROML: il finale di CHALLENGE (src/ending.s)
;   16     ROML: la classifica (si scrive); ROMH: i vettori, per gli NMI durante la scrittura
;   24-25  ROML: la HOW TO PLAY delle mosse speciali (gen/howto.bin)
;
; A $DF00-$DFFF 256 byte di RAM, sempre visibili con l'I/O acceso: prima il caricatore (che gira
; mentre i banchi cambiano), poi le routine di src/ef.s. La loro copia, l'ultima cosa che fa il
; caricatore, gira nella pagina dello stack ($0110), dove l'avvio l'ha messa.

.setcpu "6502"
.include "ef.inc"

PRG_START = $0800               ; il .prg da $0801, con uno zero davanti: pagine intere
PRG_END   = $d000               ; poi l'immagine di EF_RAM (256 byte)
PRG_ENTRY = 2061                ; SYS 2061 dello stub BASIC (main.s)
EF_IMG_BANK = PRG_BANK + (PRG_END - PRG_START) / $4000
EF_IMG      = $8000 + (PRG_END - PRG_START) .mod $4000
TAIL        = $0110             ; fine del caricamento: copia l'immagine a EF_RAM (non a $0100:
                                ; il caricatore azzera da $0002 a $0101)

.import __EFRAM_LOAD__, __TAIL_LOAD__, __TAIL_SIZE__

.segment "BOOT"

reset:
    sei
    ldx #$ff
    txs
    cld
    ; il caricatore nella RAM dell'EasyFlash (nel modo a 16K a $E000 c'è il KERNAL), la sua fine
    ; nella pagina dello stack
    ldx #0
:   lda __EFRAM_LOAD__,x
    sta EF_RAM,x
    inx
    bne :-
    ldx #<(__TAIL_SIZE__ - 1)
:   lda __TAIL_LOAD__,x
    sta TAIL,x
    dex
    bpl :-
    jmp loader

nmi:
    rti

.segment "EFRAM"

; Come il reset del KERNAL, senza il BASIC e senza la prova della RAM: CIA, pagine 0, 2 e 3 a
; zero, vettori, VIC e schermo. Poi il programma, pagina per pagina.
.proc loader
    lda #EF_16K
    sta EF_MODE
    jsr $ff84                   ; IOINIT
    lda #0
    tay
:   sta $0002,y
    sta $0200,y
    sta $0300,y
    iny
    bne :-
    lda #>$0400                 ; schermo per CINT
    sta $0288
    jsr $ff8a                   ; RESTOR
    jsr $ff81                   ; CINT
    sei
    ldx #PRG_BANK
    stx EF_BANK
    ldy #0
copy:
src:
    lda $8000,y
dst:
    sta PRG_START,y
    iny
    bne copy
    inc dst+2
    lda dst+2
    cmp #>PRG_END
    beq done
    inc src+2
    lda src+2
    cmp #$c0
    bne copy
    lda #$80                    ; banco dopo
    sta src+2
    inx
    stx EF_BANK
    bne copy
done:
    jmp TAIL
.endproc

.assert * - EF_RAM <= 256, error, "caricatore oltre la RAM dell'EasyFlash"

.segment "TAIL"

; Le routine di src/ef.s al posto del caricatore, poi la cartuccia si spegne e parte il programma
; (come il RUN dello stub BASIC).
.proc tail
    lda #EF_IMG_BANK
    sta EF_BANK
    ldx #0
:   lda EF_IMG,x
    sta EF_RAM,x
    inx
    bne :-
    lda #EF_OFF
    sta EF_MODE
    jmp PRG_ENTRY
.endproc

.segment "VECTORS"
    .addr nmi, reset, nmi
