; Attract: auto-test, strisce, logo e titolo, come nelle altre versioni (assets/attract,
; rust/game/src/attract.rs), riportati a 320x200 e 50 Hz da tools/gen_c64_assets.py.
;
; L'auto-test è a caratteri; strisce, logo e titolo sono una bitmap hires gialla e nera ($E000).
; Il titolo completo (strisce, WS, logo, copyright) è già pronto in gen/title.bin, che l'avvio
; decomprime a TITLE_BUF (unpack.s): le strisce si disegnano frame per frame, il logo si copia da
; lì riga per riga, e la pallina del titolo rimbalza sui pixel neri della bitmap stessa.

.segment "RODATA"
label_data:  .incbin "labels.bin"           ; INSERT COIN, PRESS START
credit_data: .incbin "credits.bin"          ; FREE PLAY, CREDIT 0-9
slide_left:  .byte AT_SLIDE_LEFT
slide_right: .byte AT_SLIDE_RIGHT
stripe_y:    .byte AT_STRIPE_Y0, AT_STRIPE_Y1, AT_STRIPE_Y2
ws_off:      .byte AT_WS_OFF
; indirizzo della riga y della bitmap (colonna 0)
bm_lo:
    .repeat 200, line
    .byte <(BITMAP + (line / 8) * 320 + (line .mod 8))
    .endrepeat
bm_hi:
    .repeat 200, line
    .byte >(BITMAP + (line / 8) * 320 + (line .mod 8))
    .endrepeat
mask_left:  .byte $00, $80, $c0, $e0, $f0, $f8, $fc, $fe   ; i primi n pixel di un byte
mask_right: .byte $ff, $7f, $3f, $1f, $0f, $07, $03, $01   ; tutti tranne i primi n

; righe dell'auto-test: colonna 5, righe 5, 7, ..., 15 (l'ultima volta il reticolo); come il
; codice dell'auto-test, solo all'accensione (segmento BOOTCODE, unpack.s: a $F800 finché le
; strisce non disegnano la bitmap)
.segment "BOOTCODE"
boot_lines: .word boot_0, 0, boot_2, boot_3, boot_4, boot_5
boot_0: .byte "PADD WS  V4.0", 0
boot_2: .byte "RAM ........ OK", 0
boot_3: .byte "ROM ........ OK", 0
boot_4: .byte "VIDEO PAL ... OK", 0
boot_5: .byte "AUDIO ...... OK", 0
.segment "RODATA"
BOOT_LINES = 6
BOOT_COL = 5
BOOT_ROW = 5

; title.bin (a TITLE_BUF) ha solo il blocco A (righe di caratteri del logo e di WS, colonne TITLE_A_C0 per
; TITLE_A_W) e il blocco B (righe del copyright, larghe tutto lo schermo): title_rows dà per ogni
; riga di caratteri l'indirizzo della colonna 0 (anche fuori dal blocco)
TITLE_A_SIZE = (TITLE_A_END - TITLE_A_ROW) * TITLE_A_W * 8

.segment "ZEROPAGE"
at_f:     .res 2                ; frame della fase
at_tmp:   .res 1
at_buf:   .res 11               ; byte di una riga di striscia

.segment "BSS"
.segment "ZEROPAGE"
at_shown:   .res 1              ; auto-test: righe a schermo; logo: righe copiate
.segment "BSS"
at_acc:     .res 1
at_clear:   .res 1              ; strisce: parti di bm_clear_part ancora da fare
at_target:  .res 1              ; logo: righe da mostrare in questo frame
at_label:   .res 1              ; scritta del titolo a schermo: 0 nessuna, 1 INSERT COIN, 2 PRESS START
at_credit:  .res 1              ; riga dei crediti a schermo (variante + 1, 0 = da ridisegnare)
at_ws:      .res 1              ; WS a schermo
ball_px:    .res 2              ; pallina del titolo: pixel * 64
ball_py:    .res 2
ball_vxa:   .res 2
ball_vya:   .res 2
at_x:       .res 2              ; prova della pallina: pixel
at_y:       .res 1

.segment "CODE"

; Suono dell'attract (A = eventi), se i suoni dell'attract sono accesi.
.proc at_sound
    ldx opt_asound
    beq :+
    jmp sid_fx
:   rts
.endproc

; at_f += 1
.proc at_tick
    inc at_f
    bne :+
    inc at_f+1
:   rts
.endproc

; ------------------------------------------------------------------------------------ auto-test

; Colore A per tutti i caratteri.
.proc color_text
    ldx #0
:   sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $dae8,x
    inx
    bne :-
    rts
.endproc

.segment "BOOTCODE"           ; solo all'accensione (unpack.s)
.proc boot_enter
    lda #0
    sta at_f
    sta at_f+1
    sta at_shown
    sta sh_enable
    sta sh_bg
    lda #MODE_TEXT
    sta sh_mode
    jsr clear_screen
    lda #COL_GREEN
    jmp color_text
.endproc

; Un frame dell'auto-test; C = 1 alla fine.
.proc boot_frame
    lda at_f+1
    jne grid
    lda at_f
    cmp #AT_BOOT_GRID_FROM
    jcs grid
    ; righe che compaiono una alla volta, con un suono
    ldx #0
    lda at_f
:   cmp #AT_BOOT_LINE_FRAMES
    bcc :+
    sbc #AT_BOOT_LINE_FRAMES
    inx
    jmp :-
:   inx                         ; righe da mostrare: f / passo + 1
    cpx #BOOT_LINES + 1
    bcc :+
    ldx #BOOT_LINES
:   cpx at_shown
    jeq cursor
    ; riga nuova (at_shown è l'indice)
    stx at_tmp
    lda at_shown
    jsr boot_line
    inc at_shown
    jmp cursor
grid:
    ; reticolo di test, ogni 16 pixel, e una riga in fondo
    lda at_f+1
    jne done
    lda at_f
    cmp #AT_BOOT_GRID_FROM
    jne done
    jsr draw_grid
    lda #EV_BOOST
    jsr at_sound
    jmp done
cursor:
    ; cursore a blocco che lampeggia dopo l'ultima riga
    ldx at_shown
    dex
    txa
    asl a
    tax
    lda boot_lines,x
    sta ptr2
    lda boot_lines+1,x
    sta ptr2+1
    ldy #0
    lda ptr2+1
    beq :++
:   lda (ptr2),y
    beq :+
    iny
    bne :-
:   tya
    clc
    adc #BOOT_COL
    tax                         ; X = colonna del cursore
    lda at_shown
    asl a
    adc #BOOT_ROW - 2
    tay                         ; Y = riga
    lda at_f
    and #AT_CURSOR_HALF
    beq :+
    lda #CH_BLANK
    jmp :++
:   lda #CH_CURSOR
:   jsr put_char
done:
    jsr at_tick
    lda at_f+1
    bne :+
    lda at_f
    cmp #AT_BOOT_FRAMES
    rts
:   sec
    rts
.endproc

; Riga A dell'auto-test (vuota se non c'è testo), con il suono.
.proc boot_line
    pha
    asl a
    tax
    lda boot_lines+1,x
    jeq empty
    sta ptr2+1
    lda boot_lines,x
    sta ptr2
    pla
    pha
    asl a
    adc #BOOT_ROW
    tay
    ldx #BOOT_COL
    jsr print_str
    ; il cursore della riga prima si spegne
    pla
    jeq first
    pha
    jsr erase_cursor
    pla
    lda #EV_WALL
    jmp at_sound
first:
    lda #EV_HIT
    jmp at_sound
empty:
    pla
    jmp erase_cursor
.endproc

; Toglie il cursore dalla riga prima di at_shown (cancella le colonne dopo il testo).
.proc erase_cursor
    lda at_shown
    jeq done
    asl a
    adc #BOOT_ROW - 2
    tay
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    ldy #BOOT_COL
:   lda (ptr),y
    cmp #CH_CURSOR
    bne :+
    lda #CH_BLANK
    sta (ptr),y
:   iny
    cpy #40
    bne :--
done:
    rts
.endproc

; Griglia dell'auto-test, bianca: nelle righe pari la linea in alto (e in basso nell'ultima), nelle
; colonne pari la linea a sinistra. Due passate srotolate: tutto lo schermo come le righe dispari
; (con i colori), poi le 13 righe pari a indirizzi fissi.
.proc draw_grid
    ldx #0
odd:
    lda #CH_GRID_L
    sta SCREEN,x
    sta SCREEN+$100,x
    sta SCREEN+$200,x
    sta SCREEN+$2e8,x
    lda #COL_WHITE
    sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $dae8,x
    inx
    lda #CH_BLANK
    sta SCREEN,x
    sta SCREEN+$100,x
    sta SCREEN+$200,x
    sta SCREEN+$2e8,x
    lda #COL_WHITE
    sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $dae8,x
    inx
    bne odd
even:
    lda #CH_GRID_TL
    .repeat 12, r
    sta SCREEN + r * 80,x
    .endrepeat
    lda #CH_GRID_TLB
    sta SCREEN + 24 * 40,x
    inx
    lda #CH_GRID_T
    .repeat 12, r
    sta SCREEN + r * 80,x
    .endrepeat
    lda #CH_GRID_TB
    sta SCREEN + 24 * 40,x
    inx
    cpx #40
    bne even
    rts
.endproc

.segment "CODE"

; ------------------------------------------------------------------------------------ bitmap

; Bitmap tutta gialla (nessun pixel nero) e colori nero su giallo, in BM_PARTS frame: l'intera
; pulizia (circa 48000 cicli) non sta in un frame. Parte A: 0-3 otto pagine della bitmap
; ciascuna (l'ultima pagina solo fino a $3F: oltre ci sono i vettori), 4 i colori.
BM_PARTS = 5

.macro clear_pages first, n
    .local loop
loop:
    .repeat n, p
    sta BITMAP + (first + p) * 256,x
    .endrepeat
    inx
    bne loop
.endmacro

.proc bm_clear_part
    asl a
    tay
    lda parts+1,y
    pha
    lda parts,y
    pha
    lda #0
    tax
    rts
parts:
    .word part0 - 1, part1 - 1, part2 - 1, part3 - 1, part4 - 1
part0:
    clear_pages 0, 8
    rts
part1:
    clear_pages 8, 8
    rts
part2:
    clear_pages 16, 8
    rts
part3:
    clear_pages 24, 7
    ldx #$3f
:   sta BITMAP + 31 * 256,x
    dex
    bpl :-
    rts
part4:
    lda egg_yel                 ; (COL_BLACK << 4) | COL_YELLOW, o il rosso con l'easter egg
.assert COL_BLACK = 0, error, "bitmap: il nero nel nibble alto"
:   sta SCREEN2,x
    sta SCREEN2+$100,x
    sta SCREEN2+$200,x
    sta SCREEN2+$2e8,x
    inx
    bne :-
    rts
.endproc

; Copia dal titolo le righe da A (y) per X righe, colonne di byte at_c0..at_c1 (at_cn = quante).
.proc copy_rows
    stx at_tmp
    tay
row:
    lda bm_lo,y
    clc
    adc at_c0x8
    sta ptr
    lda bm_hi,y
    adc at_c0x8+1
    sta ptr+1
    ; sorgente: title_rows[y / 8] + y % 8 + colonna * 8
    sty v_row
    tya
    lsr a
    lsr a
    lsr a
    tax
    tya
    and #7
    clc
    adc title_rows_lo,x
    sta ptr2
    lda title_rows_hi,x
    adc #0
    sta ptr2+1
    clc
    lda ptr2
    adc at_c0x8
    sta ptr2
    lda ptr2+1
    adc at_c0x8+1
    sta ptr2+1
    sty v_row
    ; il titolo è sotto l'I/O: per la riga I/O spento e niente interrupt
    php
    sei
    lda #$34
    sta $01
    ldy #0
    ldx at_cn
:   lda (ptr2),y
    sta (ptr),y
    tya
    clc
    adc #8
    tay
    dex
    bne :-
    lda #$35
    sta $01
    plp
    ldy v_row
    iny
    dec at_tmp
    jne row
    rts
.endproc

.segment "BSS"
at_c0x8: .res 2                 ; prima colonna di byte * 8
at_len:  .res 6                 ; lunghezza a schermo di ogni striscia ($ff = da disegnare)
at_cn:   .res 1                 ; colonne di byte
.segment "CODE"

.macro title_row r, part
  .if r >= TITLE_A_ROW .and r < TITLE_A_END
    .byte part(TITLE_BUF + (r - TITLE_A_ROW) * TITLE_A_W * 8 - TITLE_A_C0 * 8)
  .elseif r >= TITLE_B_ROW .and r < TITLE_B_END
    .byte part(TITLE_BUF + TITLE_A_SIZE + (r - TITLE_B_ROW) * 320)
  .else
    .byte 0
  .endif
.endmacro
title_rows_lo:
    .repeat 25, r
    title_row r, <
    .endrepeat
title_rows_hi:
    .repeat 25, r
    title_row r, >
    .endrepeat

; Colonne at_c0..at_c0 + X - 1 per copy_rows (A = prima colonna).
.proc set_cols
    stx at_cn
    ldx #0
    stx at_c0x8+1
    asl a
    rol at_c0x8+1
    asl a
    rol at_c0x8+1
    asl a
    rol at_c0x8+1
    sta at_c0x8
    rts
.endproc

; ------------------------------------------------------------------------------------ strisce

.proc stripes_enter
    jsr math_invalidate         ; la bitmap copre le tabelle dei quadrati
    lda #0
    sta at_f
    sta at_f+1
    sta sh_enable
    lda #$ff
    ldx #5
:   sta at_len,x
    dex
    bpl :-
    lda #MODE_OFF               ; schermo spento mentre si pulisce la bitmap, già tutto giallo
    sta sh_mode                 ; (bordo compreso, come poi con strisce, logo e titolo)
    lda egg_yel
    sta sh_bg
    lda #BM_PARTS
    sta at_clear
    rts
.endproc

; Un frame delle strisce: sei strisce che entrano una dopo l'altra; C = 1 alla fine. Prima,
; un frame per parte, la bitmap si pulisce a schermo spento.
.proc stripes_frame
    lda at_clear
    beq run
    eor #$ff
    sec
    adc #BM_PARTS               ; parte BM_PARTS - at_clear
    jsr bm_clear_part
    dec at_clear
    bne :+
    lda #MODE_BITMAP
    sta sh_mode
:   clc
    rts
run:
    ldx #0
stripe:
    stx at_tmp
    ; frame della striscia: f - i * passo (0 se non è ancora partita), al massimo l'ultimo
    lda at_f
    ldy at_tmp
sub:
    cpy #0
    jeq got
    sec
    sbc #AT_STRIPE_STEP
    jcc waiting
    dey
    jmp sub
waiting:
    lda #0
got:
    cmp #AT_SLIDE_LAST
    jcc frame
    jne full
    ; arrivata in questo frame: un colpo
    lda #EV_HIT
    jsr at_sound
full:
    lda #AT_SLIDE_LAST
frame:
    tay
    ldx at_tmp
    lda at_tmp
    and #1
    bne right
    lda slide_left,y
    cmp at_len,x
    jeq next                    ; stessa lunghezza: niente da rifare
    sta at_len,x
    jsr stripe_left
    jmp next
right:
    lda slide_right,y
    cmp at_len,x
    jeq next
    sta at_len,x
    jsr stripe_right
next:
    ldx at_tmp
    inx
    cpx #6
    jne stripe
    jsr at_tick
    lda at_f
    cmp #AT_STRIPES_FRAMES
    rts
.endproc

; Striscia sinistra lunga A pixel nella riga di at_tmp / 2.
.proc stripe_left
    sta v_n
    ldx #0
:   txa
    asl a
    asl a
    asl a                       ; inizio del byte
    sta v_col
    lda v_n
    sec
    sbc v_col
    bcc empty                   ; striscia finita prima
    cmp #8
    jcs full
    tay
    lda mask_left,y
    jmp store
full:
    lda #$ff
    jmp store
empty:
    lda #0
store:
    sta at_buf,x
    inx
    cpx #11
    bne :-
    lda #0
    jmp stripe_rows
.endproc

; Striscia destra lunga A pixel (fino al bordo destro) nella riga di at_tmp / 2.
.proc stripe_right
    ; primo pixel: 320 - A, contato dalla colonna di byte 29 (x = 232)
    sta v_n
    lda #320 - 232
    sec
    sbc v_n
    sta v_n
    ldx #0
:   txa
    asl a
    asl a
    asl a
    sta v_col
    lda v_n
    sec
    sbc v_col                   ; pixel spenti all'inizio del byte
    jcc full
    jeq full
    cmp #8
    jcs empty
    tay
    lda mask_right,y
    jmp store
full:
    lda #$ff
    jmp store
empty:
    lda #0
store:
    sta at_buf,x
    inx
    cpx #11
    bne :-
    lda #29
    jmp stripe_rows
.endproc

; Scrive at_buf (11 byte dalla colonna A) nelle 12 righe della striscia at_tmp / 2.
.proc stripe_rows
    asl a
    asl a
    asl a
    sta v_col
    lda at_tmp
    lsr a
    tax
    lda stripe_y,x
    sta v_row
    lda #AT_STRIPE_H
    sta v_n
row:
    ldy v_row
    lda bm_lo,y
    clc
    adc v_col
    sta ptr
    lda bm_hi,y
    adc #0
    sta ptr+1
    .repeat 11, k
    ldy #k * 8
    lda at_buf + k
    sta (ptr),y
    .endrepeat
    inc v_row
    dec v_n
    jne row
    rts
.endproc

; ------------------------------------------------------------------------------------ logo

.proc logo_enter
    lda #0
    sta at_f
    sta at_f+1
    sta at_shown
    sta at_acc
    ; strisce al loro posto, con WS
    jsr ws_on
    ; il raster: tre sprite da 48 pixel e uno da 8, bianchi, sopra il logo
    ldx #3
:   lda #COL_WHITE
    sta sh_col,x
    lda #SP_LINE24
    sta sh_ptr,x
    lda logo_line_x,x
    sta sh_x,x
    dex
    bpl :-
    lda #SP_LINE8
    sta sh_ptr+3
    lda #%0111                  ; tre sprite da 48 pixel (espansi) e uno da 8
    sta sh_xexp
    lda #0
    sta sh_yexp
    sta sh_mc
    lda logo_line_msb
    sta sh_msb
    lda #%1111
    sta sh_enable
    rts
.endproc

LOGO_SX = SPR_X0 + AT_LOGO_X
logo_line_x:   .byte <LOGO_SX, <(LOGO_SX + 48), <(LOGO_SX + 96), <(LOGO_SX + 144)
logo_line_msb: .byte ((LOGO_SX >> 8) & 1) | (((LOGO_SX + 48) >> 8) & 1) << 1 | (((LOGO_SX + 96) >> 8) & 1) << 2 | (((LOGO_SX + 144) >> 8) & 1) << 3

; WS nella striscia destra (copiato dal titolo).
.proc ws_on
    lda #AT_WS_C0
    ldx #AT_WS_C1 - AT_WS_C0 + 1
    jsr set_cols
    lda #AT_WS_Y
    ldx #AT_WS_H
    jsr copy_rows
    lda #1
    sta at_ws
    rts
.endproc

; WS spento: la striscia piena (una riga della striscia sopra WS, ripetuta).
.proc ws_off_draw
    lda #AT_WS_C0
    ldx #AT_WS_C1 - AT_WS_C0 + 1
    jsr set_cols
    ldy #AT_WS_Y
:   sty at_tmp
    lda bm_lo,y
    clc
    adc at_c0x8
    sta ptr
    lda bm_hi,y
    adc at_c0x8+1
    sta ptr+1
    ldy #AT_STRIPE_Y2
    lda bm_lo,y
    clc
    adc at_c0x8
    sta ptr2
    lda bm_hi,y
    adc at_c0x8+1
    sta ptr2+1
    ldy #0
    ldx at_cn
:   lda (ptr2),y
    sta (ptr),y
    tya
    clc
    adc #8
    tay
    dex
    bne :-
    ldy at_tmp
    iny
    cpy #AT_WS_Y + AT_WS_H
    bne :--
    lda #0
    sta at_ws
    rts
.endproc

; Un frame del logo: si scopre dall'alto con il raster bianco, poi un lampo; C = 1 alla fine.
.proc logo_frame
    lda at_f
    cmp #AT_WIPE_FRAMES
    jcs after
    ; righe da mostrare: floor(altezza * f / durata), senza divisioni
    lda at_acc
    clc
    adc #AT_LOGO_H
    sta at_acc
    ldx at_shown
:   lda at_acc
    cmp #AT_WIPE_FRAMES
    bcc :+
    sbc #AT_WIPE_FRAMES
    sta at_acc
    inx
    jmp :-
:   stx at_target               ; (copy_rows usa at_tmp)
    cpx at_shown
    jeq line
    ; righe nuove del logo
    lda #AT_LOGO_C0
    ldx #AT_LOGO_C1 - AT_LOGO_C0 + 1
    jsr set_cols
    lda at_target
    sec
    sbc at_shown
    tax
    lda at_shown
    clc
    adc #AT_LOGO_Y
    jsr copy_rows
    lda at_target
    sta at_shown
line:
    ; il raster: la riga sotto l'ultima scoperta
    lda at_shown
    clc
    adc #AT_LOGO_Y + 1 + SPR_Y0
    ldx #3
:   sta sh_y,x
    dex
    bpl :-
    jmp done
after:
    bne :+
    ; fine: il resto del logo (le righe non ancora scoperte), lampo e boost
    lda #AT_LOGO_C0
    ldx #AT_LOGO_C1 - AT_LOGO_C0 + 1
    jsr set_cols
    lda #AT_LOGO_H
    sec
    sbc at_shown
    beq whole
    bcc whole
    tax
    lda at_shown
    clc
    adc #AT_LOGO_Y
    jsr copy_rows
    lda #AT_LOGO_H
    sta at_shown
whole:
    lda #0
    sta sh_enable
    lda #EV_BOOST
    jsr at_sound
:   lda at_f
    sec
    sbc #AT_WIPE_FRAMES
    cmp #AT_FLASH_FRAMES
    bcs :+
    lda #MODE_OFF
    sta sh_mode
    lda #COL_WHITE
    sta sh_bg
    jmp done
:   lda #MODE_BITMAP
    sta sh_mode
    lda egg_yel
    sta sh_bg
done:
    jsr at_tick
    lda at_f
    cmp #AT_LOGO_FRAMES
    rts
.endproc

; ------------------------------------------------------------------------------------ titolo

.proc title_enter
    lda #0
    sta demo_prep
    ; copyright in basso (dal titolo), in due metà da 20 colonne
    lda #0
    ldx #20
    jsr set_cols
    lda #AT_COPYRIGHT_Y
    ldx #AT_COPYRIGHT_H
    jsr copy_rows
    lda #20
    ldx #20
    jsr set_cols
    lda #AT_COPYRIGHT_Y
    ldx #AT_COPYRIGHT_H
    jsr copy_rows
    lda #0
    sta at_f
    sta at_f+1
    sta at_label
    sta at_credit
    sta sh_xexp
    sta sh_yexp
    sta sh_mc
    sta sh_msb
    ; pallina nera di 4x4
    lda #COL_BLACK
    sta sh_col
    lda #SP_BALL4
    sta sh_ptr
    lda #1
    sta sh_enable
    lda #<AT_BALL_X
    sta ball_px
    lda #>AT_BALL_X
    sta ball_px+1
    lda #<AT_BALL_Y
    sta ball_py
    lda #>AT_BALL_Y
    sta ball_py+1
    lda #<AT_BALL_VX
    sta ball_vxa
    lda #>AT_BALL_VX
    sta ball_vxa+1
    lda #<AT_BALL_VY
    sta ball_vya
    lda #>AT_BALL_VY
    sta ball_vya+1
    rts
.endproc

; Un frame del titolo; C = 1 alla fine.
.proc title_frame
    ; WS lampeggia due volte all'inizio
    lda at_f+1
    jne ws_lit
    ldx #0
:   lda at_f
    cmp ws_off,x
    bcc :+
    cmp ws_off+1,x
    jcc ws_dark
:   inx
    inx
    cpx #4
    bne :--
ws_lit:
    lda at_ws
    jne label
    jsr ws_on
    jmp label
ws_dark:
    lda at_ws
    jeq label
    jsr ws_off_draw
label:
    ; INSERT COIN / PRESS START lampeggia (dopo i primi frame)
    ldx #0
    lda at_f+1
    bne :+
    lda at_f
    cmp #AT_LABEL_FROM + 1
    jcc show
:   jsr blink_on
    ldx #0
    jcc show
    ldx #2                      ; PRESS START
    jsr credit_variant
    jne show
    ldx #1                      ; senza crediti: INSERT COIN
show:
    cpx at_label
    jeq credit
    stx at_label
    jsr draw_label
credit:
    jsr credit_variant
    clc
    adc #1
    cmp at_credit
    jeq ball
    sta at_credit
    jsr draw_credit
ball:
    jsr title_ball
    jsr at_tick
    lda at_f+1
    beq :+
    lda at_f
    cmp #<AT_TITLE_FRAMES
    rts
:   clc
    rts
.endproc

; C = 1 se la scritta lampeggiante è accesa in questo frame: (f mod periodo) < acceso.
.proc blink_on
    lda at_f
    ldx at_f+1
    ; f mod periodo con sottrazioni (f < 1000)
:   cpx #0
    jne sub
    cmp #AT_BLINK_PERIOD
    bcc :+
sub:
    sec
    sbc #AT_BLINK_PERIOD
    bcs :-
    dex
    jmp :-
:   cmp #AT_BLINK_ON
    jcc on
    clc
    rts
on:
    sec
    rts
.endproc

; A = variante della riga dei crediti: 0 FREE PLAY, 1 + n CREDIT n; Z = 1 se senza crediti.
.proc credit_variant
    lda opt_free
    beq :+
    lda #0
    ldy #1                      ; Z = 0: in Free Play si può giocare
    rts
:   ldy credits
    tya
    clc
    adc #1
    cpy #0
    rts
.endproc

; Scritta at_label nelle sue celle (0 = vuota).
.proc draw_label
    lda at_label
    jeq clear
    sec
    sbc #1
    tax
    lda #<label_data
    sta ptr2
    lda #>label_data
    sta ptr2+1
    cpx #0
    beq :+
    lda ptr2
    clc
    adc #<(AT_LABEL_W * 16)
    sta ptr2
    lda ptr2+1
    adc #>(AT_LABEL_W * 16)
    sta ptr2+1
:   lda #AT_LABEL_R0
    jsr cells_row
    jsr copy_cells
    lda #AT_LABEL_R0 + 1
    jsr cells_row
    jmp copy_cells
clear:
    lda #AT_LABEL_R0
    jsr cells_row
    jsr zero_cells
    lda #AT_LABEL_R0 + 1
    jsr cells_row
    jmp zero_cells
.endproc

; ptr = cella della riga di celle A, colonna AT_LABEL_C0 (o AT_CREDIT_C0 con draw_credit).
.proc cells_row
    tay
    lda cell_row_lo,y
    clc
    adc #<(AT_LABEL_C0 * 8)
    sta ptr
    lda cell_row_hi,y
    adc #>(AT_LABEL_C0 * 8)
    sta ptr+1
    rts
.endproc

; AT_LABEL_W celle da (ptr2) a (ptr), poi ptr2 avanti.
.proc copy_cells
    ldy #0
:   lda (ptr2),y
    sta (ptr),y
    iny
    cpy #AT_LABEL_W * 8
    bne :-
    tya
    clc
    adc ptr2
    sta ptr2
    bcc :+
    inc ptr2+1
:   rts
.endproc

.proc zero_cells
    ldy #AT_LABEL_W * 8 - 1
    lda #0
:   sta (ptr),y
    dey
    bpl :-
    rts
.endproc

; Riga dei crediti, variante at_credit - 1.
.proc draw_credit
    lda #<credit_data
    sta ptr2
    lda #>credit_data
    sta ptr2+1
    ldx at_credit
    dex
skip:
    cpx #0
    jeq go
    clc
    lda ptr2
    adc #AT_CREDIT_W * 8
    sta ptr2
    lda ptr2+1
    adc #0
    sta ptr2+1
    dex
    jmp skip
go:
    ldy #AT_CREDIT_R0
    lda cell_row_lo,y
    clc
    adc #<(AT_CREDIT_C0 * 8)
    sta ptr
    lda cell_row_hi,y
    adc #>(AT_CREDIT_C0 * 8)
    sta ptr+1
    ldy #AT_CREDIT_W * 8 - 1
:   lda (ptr2),y
    sta (ptr),y
    dey
    bpl :-
    rts
.endproc

cell_row_lo:
    .repeat 25, r
    .byte <(BITMAP + r * 320)
    .endrepeat
cell_row_hi:
    .repeat 25, r
    .byte >(BITMAP + r * 320)
    .endrepeat

; ------------------------------------------------------------------------------------ pallina

; La pallina rimbalza contro i bordi e contro i pixel neri, un asse alla volta (attract.rs).
.proc title_ball
    ; già bloccata (una scritta le è comparsa sopra)? la si lascia uscire
    lda ball_px
    ldx ball_px+1
    ldy ball_py
    sty m_lo
    ldy ball_py+1
    jsr ball_blocked
    jcc free
    clc
    lda ball_px
    adc ball_vxa
    sta ball_px
    lda ball_px+1
    adc ball_vxa+1
    sta ball_px+1
    clc
    lda ball_py
    adc ball_vya
    sta ball_py
    lda ball_py+1
    adc ball_vya+1
    sta ball_py+1
    jsr clamp_ball
    jmp sprite
free:
    ; x
    clc
    lda ball_px
    adc ball_vxa
    sta at_nx
    lda ball_px+1
    adc ball_vxa+1
    sta at_nx+1
    lda at_nx
    ldx at_nx+1
    ldy ball_py
    sty m_lo
    ldy ball_py+1
    jsr ball_blocked
    bcc :+
    lda ball_px
    sta at_nx
    lda ball_px+1
    sta at_nx+1
    jsr flip_vx
:   ; y
    clc
    lda ball_py
    adc ball_vya
    sta at_ny
    lda ball_py+1
    adc ball_vya+1
    sta at_ny+1
    lda at_ny
    sta m_lo
    lda at_nx
    ldx at_nx+1
    ldy at_ny+1
    jsr ball_blocked
    bcc :+
    lda ball_py
    sta at_ny
    lda ball_py+1
    sta at_ny+1
    jsr flip_vy
:   lda at_nx
    sta ball_px
    lda at_nx+1
    sta ball_px+1
    lda at_ny
    sta ball_py
    lda at_ny+1
    sta ball_py+1
sprite:
    ; sprite 0: pixel arrotondato
    lda ball_px
    ldx ball_px+1
    jsr round64
    clc
    lda at_x
    adc #SPR_X0
    sta sh_x
    lda at_x+1
    adc #0
    and #1
    sta sh_msb
    lda ball_py
    ldx ball_py+1
    jsr round64
    lda at_x
    clc
    adc #SPR_Y0
    sta sh_y
    rts
.endproc

.segment "BSS"
at_nx: .res 2
at_ny: .res 2
.segment "CODE"

.proc flip_vx
    sec
    lda #0
    sbc ball_vxa
    sta ball_vxa
    lda #0
    sbc ball_vxa+1
    sta ball_vxa+1
    lda #EV_WALL
    jmp at_sound
.endproc

.proc flip_vy
    sec
    lda #0
    sbc ball_vya
    sta ball_vya
    lda #0
    sbc ball_vya+1
    sta ball_vya+1
    lda #EV_WALL
    jmp at_sound
.endproc

; Pallina dentro lo schermo (0..316, 0..196 pixel).
.proc clamp_ball
    lda ball_px+1
    bpl :+
    lda #0
    sta ball_px
    sta ball_px+1
:   lda ball_px+1
    cmp #>((W_PX - AT_BALL_SIZE) * 64)
    bcc :+
    jne big_x
    lda ball_px
    cmp #<((W_PX - AT_BALL_SIZE) * 64)
    bcc :+
big_x:
    lda #<((W_PX - AT_BALL_SIZE) * 64)
    sta ball_px
    lda #>((W_PX - AT_BALL_SIZE) * 64)
    sta ball_px+1
:   lda ball_py+1
    bpl :+
    lda #0
    sta ball_py
    sta ball_py+1
:   lda ball_py+1
    cmp #>((H_PX - AT_BALL_SIZE) * 64)
    bcc :+
    jne big_y
    lda ball_py
    cmp #<((H_PX - AT_BALL_SIZE) * 64)
    bcc :+
big_y:
    lda #<((H_PX - AT_BALL_SIZE) * 64)
    sta ball_py
    lda #>((H_PX - AT_BALL_SIZE) * 64)
    sta ball_py+1
:   rts
.endproc

W_PX = 320
H_PX = 200

; at_x (16 bit con segno) = round(A:X / 64)
.proc round64
    clc
    adc #32
    sta at_x
    txa
    adc #0
    sta at_x+1
    ldx #6
:   lda at_x+1
    cmp #$80
    ror at_x+1
    ror at_x
    dex
    bne :-
    rts
.endproc

; C = 1 se la pallina in (A:X, m_lo:Y) * 64 tocca un bordo o un pixel nero.
.proc ball_blocked
    sty at_ny_tmp
    jsr round64                 ; at_x = colonna
    lda at_x+1
    jmi yes
    cmp #>(W_PX - AT_BALL_SIZE)
    bcc :+
    jne yes
    lda at_x
    cmp #<(W_PX - AT_BALL_SIZE) + 1
    jcs yes
:   lda at_x
    sta at_bx
    lda at_x+1
    sta at_bx+1
    lda m_lo
    ldx at_ny_tmp
    jsr round64                 ; at_x = riga
    lda at_x+1
    bne yes                     ; negativa o oltre 255
    lda at_x
    cmp #H_PX - AT_BALL_SIZE + 1
    jcs yes
    sta at_y
    ; maschera dei 4 pixel a partire da x: byte della colonna e di quella dopo
    lda at_bx
    and #7
    tax
    lda ball_mask_hi,x
    sta m_t
    lda ball_mask_lo,x
    sta m_sign
    ; colonna di byte * 8
    lda at_bx
    and #$f8
    sta at_bc
    lda at_bx+1
    sta at_bc+1
    ldx #AT_BALL_SIZE
row:
    ldy at_y
    lda bm_lo,y
    clc
    adc at_bc
    sta ptr
    lda bm_hi,y
    adc at_bc+1
    sta ptr+1
    ldy #0
    lda (ptr),y
    and m_t
    jne yes
    lda m_sign
    beq :+
    ldy #8
    lda (ptr),y
    and m_sign
    jne yes
:   inc at_y
    dex
    jne row
    clc
    rts
yes:
    sec
    rts
.endproc

ball_mask_hi: .byte $f0, $78, $3c, $1e, $0f, $07, $03, $01
ball_mask_lo: .byte $00, $00, $00, $00, $00, $80, $c0, $e0

.segment "BSS"
at_bx: .res 2
at_bc: .res 2
at_ny_tmp: .res 1
.segment "CODE"
