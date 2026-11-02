; Cartuccia EasyFlash: routine che leggono la flash e ci scrivono (src/ef.inc).
;
; Mentre la cartuccia è accesa copre la RAM del C64 a $8000-$9FFF (nei modi a 8K e a 16K) o quasi
; tutta (nel modo Ultimax restano $0000-$0FFF e l'I/O): queste routine girano quindi nella RAM della
; cartuccia (EF_RAM, $DF00). Nel .prg l'immagine sta a $D000, dopo l'area del VIC; il caricatore
; della cartuccia (src/crt.s) la copia al suo posto prima di avviare il programma. Non costano byte
; del programma.
;
; Copie (ef_voice, ef_pick): modo a 8K con $01 = $37, la ROML a $8000; le scritture vanno nella
; RAM anche sotto le ROM. Interrupt spenti, $01 di nuovo $35 alla fine.
;
; Classifica (ef_hi_write, ef_hi_erase): nella ROML del banco HI_BANK, primo banco di un settore
; della flash che serve solo a lei. Si scrive nel modo Ultimax, l'unico in cui il C64 manda alla
; cartuccia anche le scritture, con i comandi dell'Am29F040 della EasyFlash: sblocco ($AA a $555,
; $55 a $2AA: le righe più alte dell'indirizzo non contano), poi $A0 e il byte, oppure $80, di
; nuovo lo sblocco e $30 per cancellare il settore. Finché lavora la flash dà lo stato; poi il dato
; scritto ($FF dopo la cancellazione). I dati vengono da ch_table, a $0200 (nel modo Ultimax del
; C64 si vede solo $0000-$0FFF), seguita da HI_MAGIC e dal controllo (hi_tail). Un NMI (RESTORE) intanto trova i vettori della ROMH dello stesso
; banco, che puntano a un RTI (tools/make_crt.py).

HI_SLOTS = 32                   ; posti da 128 byte nei primi 4 KB del banco: uno per salvataggio,
HI_SLOT  = 128                  ; poi si cancella il settore e si ricomincia
HI_REC   = CH_TABLE * CH_ENTRY + 3  ; la classifica, HI_MAGIC (2 byte) e il controllo
HI_MAGIC = $5048                ; "HP": un posto scritto dal programma
HI_SEED  = $A5                  ; l'EOR di tutti i byte del posto, controllo compreso
HI_SCAN  = VOICE_BASE           ; all'avvio i posti si leggono qui (ef_voice, VOICE_PAGES pagine)
.assert HI_SLOTS * HI_SLOT = VOICE_PAGES * 256, error, "i posti della classifica non sono una voce"
.assert HI_REC <= HI_SLOT, error, "classifica più lunga di un posto"

; il set di caratteri del programma nella flash (src/crt.s: dal banco PRG_BANK, da $0800)
CHARSET_BANK = PRG_BANK + (CHARSET - $0800) / $4000
.assert (CHARSET - $0800) .mod $4000 = 0, error, "set di caratteri non all'inizio della ROML"
; caratteri della scelta dei bonus (gen/pick_bank.bin): le metà delle lettere al posto delle
; scritte grandi, PICK_PAGES pagine da PICK_FIRST (assets.inc)
PICK_TOP   = PICK_FIRST - FONT_FIRST    ; codice del font + PICK_TOP: metà alta, abbassata
PICK_BOTTOM = PICK_TOP + FONT_CHARS     ; codice del font + PICK_BOTTOM: metà bassa, in alto
.assert PICK_BOTTOM + FONT_FIRST + FONT_CHARS <= PICK_FIRST + PICK_PAGES * 32, error, "metà delle lettere oltre le pagine copiate"

.segment "EFCODE"
ef_ram:

; Voce del tipo A (VOICE_BANK0 + A) a VOICE_BASE: VOICE_PAGES pagine, circa 60.000 cicli. Con
; A = HI_BANK - VOICE_BANK0 i posti della classifica.
.proc ef_voice
    clc
    adc #VOICE_BANK0
    ldx #$80
    stx ef_src+2
    ldx #VOICE_PAGES
    ldy #>VOICE_BASE
    bne ef_copy
.endproc

; C = 0: i caratteri della scelta dei bonus (banco PICK_BANK, gen/pick_bank.bin); C = 1: di nuovo
; quelli originali
; (dal programma nella flash). PICK_PAGES pagine, circa 11.000 cicli.
.proc ef_pick
    lda #CHARSET_BANK
    bcs :+
    lda #PICK_BANK
:   ldx #$80 + PICK_FIRST * 8 / 256
    stx ef_src+2
    ldx #PICK_PAGES
    ldy #>(CHARSET + PICK_FIRST * 8)
.endproc
; (prosegue)
; X pagine dalla ROML del banco A, dalla pagina in ef_src+2, alla pagina Y.
.proc ef_copy
    sta EF_BANK
    stx pages
    sty dst+2
    php
    sei
    lda #$37
    sta $01
    lda #EF_8K
    sta EF_MODE
    ldy #0
loop:
    lda $8000,y
    sta $ff00,y
    iny
    bne loop
    inc ef_src+2
    inc dst+2
    dec pages
    bne loop
    lda #EF_OFF
    sta EF_MODE
    lda #$35
    sta $01
    plp
    rts
.endproc
ef_src = ef_copy::loop
dst = ef_copy::loop + 3
pages: .res 1

; Scrive i HI_REC byte da ch_table nel posto a X:Y (byte basso e alto, $8000-$9FFF). C = 1 se un
; byte del posto non era cancellato o non si scrive.
.proc ef_hi_write
    stx rd+1
    sty rd+2
    stx wr+1
    sty wr+2
    php
    jsr ultimax
    ldx #0
byte:
    jsr rd
    cmp #$ff
    bne fail
    jsr unlock
    lda #$a0
    sta $8555
    lda ch_table,x
wr: sta $8000,x
    ldy #1                      ; circa 2 s: un byte ci mette pochi microsecondi
    jsr poll
    bne fail
    inx
    cpx #HI_REC
    bne byte
    clc
    bcc ef_end
fail:
    sec
    bcs ef_end
.endproc

; Cancella il settore di HI_BANK (circa 1 s). C = 1 se non si cancella.
.proc ef_hi_erase
    php
    jsr ultimax
    jsr unlock
    lda #$80
    sta $8555
    jsr unlock
    lda #$30
    sta $8000
    ldx #0
    stx rd+1
    lda #$80
    sta rd+2
    lda #$ff
    ldy #5                      ; circa 10 s
    jsr poll
    clc
    beq ef_end
    sec
.endproc
; (prosegue)
; Fine della scrittura (C resta): comando di uscita (dopo un errore la flash torna a dare i dati),
; cartuccia spenta, interrupt come prima.
.proc ef_end
    lda #$f0
    sta $8000
    lda #EF_OFF
    sta EF_MODE
    pla
    and #$04
    bne :+
    cli
:   rts
.endproc

; Interrupt spenti, banco della classifica, modo Ultimax.
.proc ultimax
    sei
    lda #HI_BANK
    sta EF_BANK
    lda #EF_ULTIMAX
    sta EF_MODE
    rts
.endproc

.proc unlock
    lda #$aa
    sta $8555
    lda #$55
    sta $82aa
    rts
.endproc

; Aspetta che il byte a rd (indice X) valga A, al più Y volte 65.536 letture (circa 2 s ciascuna).
; Z = 1 se ci è arrivato.
.proc poll
    sta want
loop:
    jsr rd
    cmp want
    beq done
    inc count
    bne loop
    inc count+1
    bne loop
    dey
    bne loop
    iny                         ; Z = 0
done:
    rts
.endproc

rd: lda $8000,x
    rts

want:  .res 1
count: .res 2

.assert * - ef_ram <= 256, error, "routine oltre la RAM dell'EasyFlash"

.segment "CODE"
