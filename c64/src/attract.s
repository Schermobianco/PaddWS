; Attract: auto-test e titolo, come nelle altre versioni (assets/attract, rust/game/src/attract.rs),
; riportati a 320x200 e 50 Hz da tools/gen_c64_assets.py.
;
; L'auto-test è a caratteri; il titolo è una bitmap hires gialla e nera ($E000), ferma: strisce, WS,
; logo e simbolo del copyright. Il titolo completo è già pronto in gen/title.bin, che l'avvio
; decomprime a TITLE_BUF (unpack.s): prima del titolo, a schermo spento, si pulisce la bitmap, si
; disegnano le strisce e si copia il logo da lì (title_prep_frame). La pallina del titolo rimbalza sui
; pixel neri della bitmap stessa. In NEXT, sotto il logo, ci sono le lettere di NEXT e la loro riga
; (next_draw): sul C64 senza l'animazione del PC, la scritta c'è o non c'è.
; Le scritte del titolo (INSERT COIN, i crediti, il copyright) le scrive print_str nelle celle della
; bitmap, con i glifi del set di caratteri (il font della ROM).

.segment "RODATA"
s_label:     .byte "INSERT COIN", 0                      ; (FREE PLAY: s_free del menu)
s_credit:    .byte "CREDIT ", 0, 0              ; la cifra al posto del primo 0
s_copy:      .byte AT_COPYRIGHT_TEXT, 0
stripe_y:    .byte AT_STRIPE_Y0, AT_STRIPE_Y1, AT_STRIPE_Y2
mask_left:  .byte $00, $80, $c0, $e0, $f0, $f8, $fc, $fe   ; i primi n pixel di un byte
mask_right: .byte $ff, $7f, $3f, $1f, $0f, $07, $03, $01   ; tutti tranne i primi n
.assert mask_right = mask_left + 8, error, "mask_left + 1: i primi n + 1 pixel (l'ultimo è mask_right, $ff)"

; NEXT (gen_c64_assets.py): colonna di cella di ogni lettera e le lettere già spostate (per riga: il
; byte nella cella della lettera e quello nella cella dopo)
nx_cols:    .byte NX_COLS
nx_glyphs:  .byte NX_GLYPHS

; righe dell'auto-test: colonna 5, righe 5, 7, ..., 15 (l'ultima volta il reticolo); come il
; codice dell'auto-test, solo all'accensione (segmento BOOTCODE, unpack.s: a $F800 finché il
; titolo non pulisce la bitmap)
.segment "BOOTCODE"
boot_lines: .word boot_0, 0, boot_2, boot_3, boot_4, boot_5
boot_0: .byte "PADD WS  V4.7", 0
boot_2: .byte "RAM ........ OK", 0
boot_3: .byte "ROM ........ OK", 0
.ifdef NTSC
boot_4: .byte "VIDEO NTSC .. OK", 0
.else
boot_4: .byte "VIDEO PAL ... OK", 0
.endif
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
at_shown:   .res 1              ; auto-test: righe a schermo; titolo: righe del logo copiate
.segment "BSS"
at_acc:     .res 1              ; titolo: indice dopo l'ultima striscia da disegnare in questo frame
at_clear:   .res 1              ; titolo: parti di bm_clear_part ancora da fare
at_label:   .res 1              ; scritta del titolo a schermo: 0 nessuna, 1 INSERT COIN
at_credit:  .res 1              ; riga dei crediti a schermo (variante + 1, 0 = da ridisegnare)
nx_i:       .res 1              ; NEXT: lettera (o colonna della riga), riga (o prima colonna),
nx_r:       .res 1              ; ultimo pixel, primo pixel, ultima colonna
nx_thr:     .res 1
nx_idx:     .res 1
nx_y:       .res 1
nx_c8:      .res 1              ; colonna di cella * 8
nx_b0:      .res 1              ; i due byte di una riga di lettera, e la maschera della riga
nx_b1:      .res 1
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
    bne grid
    lda at_f
    cmp #AT_BOOT_GRID_FROM
    bcs grid
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
    beq cursor
    ; riga nuova (at_shown è l'indice)
    stx at_tmp
    lda at_shown
    jsr boot_line
    inc at_shown
    jmp cursor
grid:
    ; reticolo di test, ogni 16 pixel, e una riga in fondo
    lda at_f+1
    bne done
    lda at_f
    cmp #AT_BOOT_GRID_FROM
    bne :+
    jsr draw_grid
    lda #EV_BOOST
    jsr at_sound
    jmp done
:   cmp #AT_BOOT_GRID_FROM + 1  ; le linee in alto al frame dopo (tutta insieme la griglia non sta
    bne done                    ; nel frame NTSC)
    jsr draw_grid_even
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
    beq empty
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
    beq first
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
    beq done
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
; colonne pari la linea a sinistra. Due passate srotolate, in due frame: tutto lo schermo come le
; righe dispari (con i colori), poi le 13 righe pari a indirizzi fissi (draw_grid_even).
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
    rts
.endproc

.proc draw_grid_even
    ldx #0
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
    lda #COL_YELLOW                 ; (COL_BLACK << 4) | COL_YELLOW, o il rosso con l'easter egg
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
    jsr bm_row
    clc
    adc at_c0x8
    sta ptr
    txa
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
    bne row
    rts
.endproc

.segment "BSS"
at_c0x8: .res 2                 ; prima colonna di byte * 8
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

; ------------------------------------------------------------------------------------ preparazione

; Prepara il titolo a schermo spento: bitmap tutta gialla (BM_PARTS frame), le sei strisce (tre per
; frame, circa 2.400 cicli l'una), il logo in tre parti da 17 righe e WS; poi la bitmap si accende.
.proc title_prep_enter
    jsr math_invalidate         ; la bitmap copre le tabelle dei quadrati
    lda #0
    sta at_f
    sta at_f+1
    sta at_shown
    sta sh_enable
    lda #MODE_OFF               ; schermo spento mentre si prepara, già tutto giallo (bordo compreso)
    sta sh_mode
    lda #COL_YELLOW
    sta sh_bg
    lda #BM_PARTS
    sta at_clear
    rts
.endproc

LOGO_PART = 17
.assert AT_LOGO_H = 3 * LOGO_PART, error, "title_prep_frame: il logo in tre parti"

; Un frame della preparazione; C = 1 quando il titolo è pronto (e la bitmap accesa).
.proc title_prep_frame
    lda at_clear
    beq run
    eor #$ff
    sec
    adc #BM_PARTS               ; parte BM_PARTS - at_clear
    jsr bm_clear_part
    dec at_clear
    clc
    rts
run:
    ldx at_f
    cpx #2
    bcs logo
    ; strisce 3 * f .. 3 * f + 2: le pari a sinistra, le dispari a destra
    txa
    asl a
    adc at_f
    tax
    adc #3
    sta at_acc
stripe:
    stx at_tmp
    txa
    lsr a
    bcs right
    lda #AT_STRIPE_LEFT
    jsr stripe_left
    jmp next
right:
    lda #320 - AT_STRIPE_RIGHT
    jsr stripe_right
next:
    ldx at_tmp
    inx
    cpx at_acc
    bne stripe
    jmp tick
logo:
    cpx #5
    bcs done
    lda #AT_LOGO_C0
    ldx #AT_LOGO_C1 - AT_LOGO_C0 + 1
    jsr set_cols
    lda at_shown
    clc
    adc #AT_LOGO_Y
    ldx #LOGO_PART
    jsr copy_rows
    lda at_shown
    clc
    adc #LOGO_PART
    sta at_shown
tick:
    jsr at_tick
    clc
    rts
done:
    jsr ws_on
    lda #MODE_BITMAP
    sta sh_mode
    sec
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
    bcs full
    tay
    lda mask_left,y
    jmp store
full:
    lda #$ff
    bne store
empty:
    lda #0
store:
    sta at_buf,x
    inx
    cpx #11
    bne :-
    lda #0
    beq stripe_rows
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
    bcc full
    beq full
    cmp #8
    bcs empty
    tay
    lda mask_right,y
    jmp store
full:
    lda #$ff
    bne store
empty:
    lda #0
store:
    sta at_buf,x
    inx
    cpx #11
    bne :-
    lda #29
    bne stripe_rows
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
    ldy v_row
    jsr bm_row
    clc
    adc v_col
    sta ptr
    txa
    adc #0
    sta ptr+1
row:
    .repeat 11, k
    ldy #k * 8
    lda at_buf + k
    sta (ptr),y
    .endrepeat
    ; riga dopo: un byte avanti nella cella, o 313 alla fine della cella (la riga di celle dopo)
    inc v_row
    lda v_row
    and #7
    beq cell
    inc ptr
    bne next
    inc ptr+1
    bne next                    ; (sempre)
cell:
    lda ptr
    clc
    adc #<313
    sta ptr
    lda ptr+1
    adc #>313
    sta ptr+1
next:
    dec v_n
    bne row
    rts
.endproc

; WS nella striscia destra (copiato dal titolo).
.proc ws_on
    lda #AT_WS_C0
    ldx #AT_WS_C1 - AT_WS_C0 + 1
    jsr set_cols
    lda #AT_WS_Y
    ldx #AT_WS_H
    jmp copy_rows
.endproc

; ------------------------------------------------------------------------------------ titolo

.proc title_enter
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
    lda #0                      ; (la scritta del copyright al primo frame del titolo)
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
    ; al primo frame la scritta del copyright (con la copia delle righe in title_enter non ci sta
    ; nel frame NTSC)
    lda at_f
    ora at_f+1
    bne :+
    lda #<s_copy
    ldx #>s_copy
    ldy #AT_COPYRIGHT_Y / 8
    sty v_row
    ldy #AT_COPYRIGHT_C0
    jsr bm_print
:   ; NEXT: al secondo frame le lettere e la riga (il primo ha già il copyright)
    lda opt_mode
    cmp #2
    bne label
    lda at_f+1
    bne label
    lda at_f
    cmp #1
    bne label
    jsr next_draw
label:
    ; INSERT COIN lampeggia (dopo i primi frame): è l'unico invito, senza crediti e mai in NEXT
    ldx #0
    lda at_f+1
    bne :+
    lda at_f
    cmp #AT_LABEL_FROM + 1
    bcc show
:   jsr blink_on
    ldx #0
    bcc show
    lda opt_mode
    cmp #2
    beq show
    jsr credit_variant
    bne show
    ldx #1                      ; senza crediti: INSERT COIN
show:
    cpx at_label
    beq credit
    stx at_label
    jsr draw_label
credit:
    jsr credit_variant
    clc
    adc #1
    cmp at_credit
    beq ball
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
    bne sub
    cmp #AT_BLINK_PERIOD
    bcc :+
sub:
    sec
    sbc #AT_BLINK_PERIOD
    bcs :-
    dex
    jmp :-
:   cmp #AT_BLINK_ON
    bcc on
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
    lda #AT_LABEL_R0
    jsr cells_row
    jsr zero_cells
    ldx at_label
    beq done
    lda #<s_label               ; INSERT COIN
    ldx #>s_label
    ldy #AT_LABEL_R0
    sty v_row
    ldy #AT_LABEL_C0
    jmp bm_print
done:
    rts
.endproc

; ptr = cella della riga di celle A, colonna AT_LABEL_C0.
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

; AT_LABEL_W celle vuote da (ptr).
.proc zero_cells
    ldy #AT_LABEL_W * 8 - 1
    lda #0
:   sta (ptr),y
    dey
    bne :-
    sta (ptr),y
    rts
.endproc
.assert AT_LABEL_W * 8 <= 256, error, "zero_cells: oltre 256 byte"

; Riga dei crediti, variante at_credit - 1: FREE PLAY o CREDIT n.
.proc draw_credit
    ldy #AT_CREDIT_R0
    lda cell_row_lo,y
    clc
    adc #<(AT_FREE_C0 * 8)
    sta ptr
    lda cell_row_hi,y
    adc #>(AT_FREE_C0 * 8)
    sta ptr+1
    ldy #AT_CREDIT_W * 8 - 1
    lda #0
:   sta (ptr),y
    dey
    bpl :-
    ldy #AT_CREDIT_R0
    sty v_row
    ldx at_credit
    dex
    bne credit
    lda #<s_free
    ldx #>s_free
    ldy #AT_FREE_C0
    jmp bm_print
credit:
    dex
    txa
    ora #'0'
    sta s_credit + 7
    lda #<s_credit
    ldx #>s_credit
    ldy #AT_CREDIT_C0
    jmp bm_print
.endproc
.assert AT_CREDIT_W * 8 <= 128 .and AT_FREE_C0 <= AT_CREDIT_C0, error, "draw_credit: celle da pulire"

; Stringa A:X (byte basso e alto) nella bitmap dalla colonna Y, riga v_row, con i glifi del set
; (print_str).
.proc bm_print
    pha
    lda #$40
    sta v_big
    pla
    sta ptr2
    stx ptr2+1
    tya
    tax
    ldy v_row
    jsr print_str
    lda #0
    sta v_big
    rts
.endproc

; A = byte basso, X = byte alto dell'indirizzo della riga di pixel Y della bitmap (colonna 0): la
; riga di celle Y / 8 (byte bassi multipli di 64) più Y % 8. Y resta.
.proc bm_row
    tya
    lsr a
    lsr a
    lsr a
    tax
    tya
    and #7
    ora cell_row_lo,x
    pha
    lda cell_row_hi,x
    tax
    pla
    rts
.endproc
.assert <BITMAP .mod 64 = 0, error, "bm_row: le righe di celle non a multipli di 64"

cell_row_lo:
    .repeat 25, r
    .byte <(BITMAP + r * 320)
    .endrepeat
cell_row_hi:
    .repeat 25, r
    .byte >(BITMAP + r * 320)
    .endrepeat

; ------------------------------------------------------------------------------------ NEXT

; Le quattro lettere di NEXT e la riga larga come il logo (mezza larghezza NX_LINE_HALF).
.proc next_draw
    ldx #3
:   stx nx_i
    jsr nx_draw
    ldx nx_i
    dex
    bpl :-
    lda #NX_LINE_HALF
    jmp nx_line
.endproc

; Lettera `nx_i`, 10 righe: scrive i due byte di ogni riga nelle due celle della lettera.
.proc nx_draw
    ldx nx_i
    lda nx_cols,x
    asl a
    asl a
    asl a
    sta nx_c8                   ; colonna di cella * 8 (al più 22 * 8)
    lda #0
    sta nx_r                    ; riga
row:
    lda nx_i                    ; i due byte della lettera: 20 * lettera + 2 * riga
    asl a
    asl a
    sta nx_b0
    asl a
    asl a
    adc nx_b0
    sta nx_b0
    lda nx_r
    asl a
    adc nx_b0
    tax
    lda nx_glyphs,x
    sta nx_b0
    lda nx_glyphs+1,x
    sta nx_b1
    lda nx_r                    ; indirizzo della riga di pixel NX_Y + riga, nella colonna della lettera
    clc
    adc #NX_Y
    tay
    jsr bm_row
    clc
    adc nx_c8
    sta ptr
    bcc :+
    inx
:   stx ptr+1
    ldy #0
    lda nx_b0
    sta (ptr),y
    ldy #8
    lda nx_b1
    sta (ptr),y
    inc nx_r
    lda nx_r
    cmp #NX_ROWS
    bne row
    rts
.endproc

; Riga di NEXT lunga 2 * A pixel, centrata su NX_LINE_X, alta due righe di pixel.
.proc nx_line
    sta nx_i                    ; mezza larghezza
    lda #NX_LINE_X
    sec
    sbc nx_i
    sta nx_idx                  ; primo pixel
    lda #NX_LINE_X - 1
    clc
    adc nx_i
    sta nx_thr                  ; ultimo pixel
    lda nx_idx
    lsr a
    lsr a
    lsr a
    sta nx_r                    ; prima colonna di byte
    sta nx_i                    ; (la colonna in corso)
    lda nx_thr
    lsr a
    lsr a
    lsr a
    sta nx_y                    ; ultima
    ldy #NX_LINE_Y
    jsr bm_row                  ; prima riga di pixel, colonna 0
    sta ptr
    stx ptr+1
    lda nx_r
    asl a
    asl a
    asl a                       ; (al più la colonna 29: 232)
    clc
    adc ptr
    sta ptr
    bcc col
    inc ptr+1
col:
    lda #$ff
    ldy nx_i
    cpy nx_r
    bne :+
    lda nx_idx                  ; la prima colonna: da quel pixel in poi
    and #7
    tay
    lda mask_right,y
:   ldy nx_i
    cpy nx_y
    bne store
    sta nx_b0                    ; l'ultima: fino a quel pixel
    lda nx_thr
    and #7
    tay
    lda mask_left + 1,y
    and nx_b0
store:
    ldy #0
    sta (ptr),y
    iny
    sta (ptr),y
    lda nx_i
    cmp nx_y
    beq end
    inc nx_i
    lda ptr
    clc
    adc #8
    sta ptr
    bcc col
    inc ptr+1
    jmp col
end:
    rts
.endproc

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
    bcc free
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
    bne big_x
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
    bne big_y
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
    bne yes
    lda at_x
    cmp #<(W_PX - AT_BALL_SIZE) + 1
    bcs yes
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
    bcs yes
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
    txa                         ; (X: le righe che restano)
    pha
    ldy at_y
    jsr bm_row
    clc
    adc at_bc
    sta ptr
    txa
    adc at_bc+1
    sta ptr+1
    pla
    tax
    ldy #0
    lda (ptr),y
    and m_t
    bne yes
    lda m_sign
    beq :+
    ldy #8
    lda (ptr),y
    and m_sign
    bne yes
:   inc at_y
    dex
    bne row
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
