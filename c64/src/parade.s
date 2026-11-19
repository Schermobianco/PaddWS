; Sfilata del finale di CHALLENGE con i ritratti (4.5.0), come rust/game/src/ending_ui.rs
; `draw_parade`: YOUR OPPONENTS, otto ritratti medi (8x9 celle) in due file da quattro nell'ordine
; della scala, uno al secondo; mezzo secondo dopo il ritratto sconfitto con il timbro DEFEATED e il
; nome grigio. L'ottavo è OMEGA: svelato se battuto, se no la sua sagoma con il "?" viola.
;
; Dove sta. Il finale (ending.s) ha già quasi tutta la RAM da $E000 (codice, la canzone a $EC00 e
; $FB00): la bitmap sta a $C000-$DF3F (sopra gli schermi, il set di caratteri del finale e, sotto
; l'I/O, gli sprite e il titolo dell'attract), i colori a $F000 e questo codice a $F400 (dove dopo
; arrivano i fuochi, ENDE: il finale li copia solo dopo la sfilata), da $F800 la pagina d'appoggio
; delle copie. parade_frame (ending.s) lo copia dalla cartuccia (banco KP_BANK + PR_BANK_REL,
; pagine $80-$83) a voce finita e gli passa ogni frame. I ritratti (tools/gen_c64_portraits.py)
; passano dall'appoggio: la cartuccia si legge con l'I/O acceso, la metà bassa della bitmap si
; scrive con l'I/O spento. Le scritte con i glifi letti dalla ROM dei caratteri ($01 = $31: le
; scritture a $D000-$DFFF vanno nella RAM). Il finale non ha effetti sonori (la terza voce della
; canzone è la batteria). Alla fine, a schermo spento: il set di caratteri del finale (dalla
; cartuccia, poi i glifi della ROM e le lettere 2x: e_glyphs), gli sprite del programma e il titolo
; dell'attract sotto l'I/O, poi la parte dopo.
;
; Il VIC: $D011 e $D018 si scrivono qui a ogni frame, dopo apply_shadows (che scrive quelli di
; sh_mode e i puntatori degli sprite a $C3F8, una cella del primo ritratto: sh_ptr ne tiene i byte).

PR_RUN    = $F400
PR_STAGE  = $F800               ; appoggio: un pannello (9 righe da 72 byte)
PR_COLORS = $F000
PR_BITMAP = $C000
PR_BANK   = KP_BANK + PR_BANK_REL
PR_D018   = (PR_COLORS - $C000) / $400 << 4
PR_STEP   = 25                  ; un ritratto al secondo, il timbro mezzo secondo dopo
PR_STAMP  = 12
PR_SHOW   = 6                   ; pr_step: caricamento (0-5), poi la sfilata
PR_RESTORE = 30                 ; frame alla fine per rimettere tutto, a schermo spento
.assert PR_STAGE + 9 * PR_ROW_BYTES <= $FB00, error, "sfilata: l'appoggio sopra la canzone"

.segment "PRCODE"
    jmp pr_tick                 ; PR_RUN: un frame della sfilata (parade_frame)

pr_step: .byte 0
pr_f:    .byte 0                ; frame dalla sfilata accesa
pr_r:    .byte 0                ; rimesse a posto (alla fine)
pr_i:    .byte 0                ; temporanee
pr_n:    .byte 0
pr_c:    .byte 0
pr_row:  .byte 0
pr_col:  .byte 0
pr_hi:   .byte 0
pr_ev:   .byte 0                ; 0 il ritratto, 1 il timbro

; ------------------------------------------------------------------------------------ frame

.proc pr_tick
    lda #0
    sta sh_enable
    ; gli ultimi PR_RESTORE frame: tutto a posto, a schermo spento
    lda e_t
    cmp #<(E_PARADE - PR_RESTORE)
    lda e_t+1
    sbc #>(E_PARADE - PR_RESTORE)
    bcc :+
    jmp pr_restore
:   lda pr_step
    cmp #PR_SHOW
    bcs show
    jmp pr_load
show:
    ; la bitmap a $C000, i colori a $F000
    lda #$3b
    sta $d011
    lda #$c8
    sta $d016
    lda #PR_D018
    sta $d018
    ; un ritratto ogni PR_STEP frame: al primo frame dalla cartuccia all'appoggio, al secondo e al
    ; terzo nella bitmap (5 righe, poi 4 e il nome); PR_STAMP frame dopo lo stesso con il ritratto
    ; sconfitto
    ldx #0
    lda pr_f
:   cmp #PR_STEP
    bcc :+
    sbc #PR_STEP
    inx
    cpx #8
    bne :-
    rts                         ; (finiti gli otto: pr_f resta, non ricomincia)
:   stx pr_i
    ldy #0                      ; 0 il ritratto, 1 il timbro
    cmp #PR_STAMP
    bcc :+
    sbc #PR_STAMP
    iny
:   cmp #3
    bcs done
    sty pr_n
    sty pr_ev
    tay
    bne blit
    ; il pannello nell'appoggio
    jsr pr_panel_page
    bcs done                    ; (OMEGA in sagoma: niente timbro)
    sta ef_src+2
    lda #PR_BANK
    ldx #3
    ldy #>PR_STAGE
    jsr ef_copy
    jmp done
blit:
    jsr pr_panel_page           ; (OMEGA in sagoma: niente timbro)
    bcs done
    dey                         ; 0: le prime 5 righe, 1: le altre 4 e il nome
    tya
    pha
    jsr pr_blit
    pla
    beq done
    lda pr_ev
    sta pr_n
    jsr pr_name
done:
    inc pr_f
    rts
.endproc

; Pagina del pannello del posto pr_i (ritratto se pr_n = 0, sconfitto se 1). C = 1: OMEGA in sagoma
; e pr_n = 1 (niente da fare).
.proc pr_panel_page
    lda pr_i
    cmp #7
    bcc kind
    lda ch_omega
    bne omega
    lda pr_n
    cmp #1                      ; (C = 1 con il timbro)
    lda #PR_LOCKED
    rts
omega:
    lda #7
    bne :+
kind:
    ldx pr_i                    ; tipo dell'avversario del livello
    lda rung_kind,x
:   asl a
    ora pr_n                    ; tipo * 2 + sconfitto, 3 pagine ciascuno
    sta pr_c
    asl a
    adc pr_c
    adc #PR_PAGE0               ; (C = 0)
    clc
    rts
.endproc

; Riga (A) e colonna (X) del posto pr_i: righe 3 e 14, colonne 1 + 10 * (posto % 4).
.proc pr_slot
    lda pr_i
    and #3
    tax
    lda pr_slot_col,x
    tax
    lda #3
    ldy pr_i
    cpy #4
    bcc :+
    lda #14
:   rts
.endproc
pr_slot_col: .byte 1, 11, 21, 31

; Metà del pannello dell'appoggio nella bitmap del posto pr_i (righe da 64 byte, poi 8 colori), con
; l'I/O spento: la metà bassa della bitmap è sotto. Poi i byte della cella sotto i puntatori degli
; sprite in sh_ptr (apply_shadows li riscrive a ogni frame).
; A: 0 le righe 0-4, 1 le 5-8.
.proc pr_blit
    pha
    jsr pr_slot
    sta pr_row
    stx pr_col
    lda #<PR_STAGE
    sta ptr2
    lda #>PR_STAGE
    sta ptr2+1
    lda #5
    sta pr_n
    pla
    beq :+
    lda pr_row
    clc
    adc #5
    sta pr_row
    lda #<(PR_STAGE + 5 * PR_ROW_BYTES)
    sta ptr2
    lda #>(PR_STAGE + 5 * PR_ROW_BYTES)
    sta ptr2+1
    lda #PR_H - 5
    sta pr_n
:
    php
    sei
    lda #$34
    sta $01
row:
    ; bitmap: $C000 + riga * 320 + colonna * 8
    ldx pr_row
    jsr pr_cell_addr
    ldy #PR_W * 8 - 1
:   lda (ptr2),y
    sta (ptr),y
    dey
    bpl :-
    ; colori: $F000 + riga * 40 + colonna
    jsr pr_color_addr
    ldy #PR_W * 8 + PR_W - 1
    ldx #PR_W - 1
:   lda (ptr2),y
    sta pr_cbuf,x
    dey
    dex
    bpl :-
    ldy #PR_W - 1
:   lda pr_cbuf,y
    sta (ptr),y
    dey
    bpl :-
    lda ptr2
    clc
    adc #PR_ROW_BYTES
    sta ptr2
    bcc :+
    inc ptr2+1
:   inc pr_row
    dec pr_n
    bne row
    lda #$35
    sta $01
    plp
    ldx #7
:   lda $c3f8,x
    sta sh_ptr,x
    dex
    bpl :-
    rts
.endproc
pr_cbuf: .res PR_W

; ptr = $C000 + riga X * 320 + colonna pr_col * 8 (le righe della bitmap dell'attract, a $E000,
; meno $2000). X resta.
.proc pr_cell_addr
    lda pr_col
    asl a
    asl a
    asl a
    sta ptr
    lda #0
    rol a
    sta pr_hi
    lda ptr
    clc
    adc cell_row_lo,x
    sta ptr
    lda cell_row_hi,x
    adc pr_hi
    sec
    sbc #>($E000 - PR_BITMAP)
    sta ptr+1
    rts
.endproc
.assert BITMAP = $E000, error, "sfilata: le righe della bitmap dell'attract altrove"

; ptr = $F000 + riga X * 40 + colonna pr_col (X resta).
.proc pr_color_addr
    lda row_lo,x                ; (SCREEN + riga * 40: SCREEN = $C000)
    clc
    adc pr_col
    sta ptr
    lda row_hi,x
    adc #>(PR_COLORS - SCREEN)
    sta ptr+1
    rts
.endproc
.assert <SCREEN = 0 .and <PR_COLORS = 0, error, "sfilata: righe dei colori"

; Nome del posto pr_i sotto il ritratto (pr_n: 0 bianco, 1 grigio, il timbro), centrato; OMEGA in
; sagoma: il "?" viola.
.proc pr_name
    jsr pr_slot
    clc
    adc #PR_H                   ; la riga sotto il ritratto
    sta pr_row
    stx pr_col
    lda pr_i
    cmp #7
    bcc kind
    lda ch_omega
    bne om
    lda #<pr_q
    ldy #>pr_q
    ldx #COL_PURPLE
    bne text
om:
    lda #<pr_omega
    ldy #>pr_omega
    jmp named
kind:
    tax
    lda rung_kind,x
    tax
    lda pr_name_lo,x
    ldy pr_name_hi,x
named:
    ldx #COL_WHITE
    pha
    lda pr_n
    beq :+
    ldx #COL_GRAY
:   pla
text:
    stx pr_c
    sta ptr2
    sty ptr2+1
    ; centrato sul ritratto (8 colonne): colonna + (8 - lunghezza) / 2
    ldy #0
:   lda (ptr2),y
    beq :+
    iny
    bne :-
:   sty pr_n
    lda #PR_W
    sec
    sbc pr_n
    lsr a
    clc
    adc pr_col
    sta pr_col
    ; colori della riga del nome
    ldx pr_row
    jsr pr_color_addr
    lda pr_c
    asl a
    asl a
    asl a
    asl a
    ldy pr_n
:   dey
    bmi :+
    sta (ptr),y
    bne :-
    sta (ptr),y
:   jmp pr_text
.endproc
pr_q:     .byte "?", 0
pr_omega: .byte "OMEGA", 0

; Stringa (ptr2) nella bitmap dalla colonna pr_col, riga pr_row, con i glifi della ROM dei caratteri
; (set maiuscolo: lettere A-Z ai codici 1-26, gli altri come l'ASCII): $01 = $31, la ROM a $D000 e
; le scritture lì nella RAM sotto.
.proc pr_text
    php
    sei
    lda #$31
    sta $01
    ldy #0
char:
    sty pr_n
    lda (ptr2),y
    beq done
    cmp #'A'
    bcc :+
    and #$1f                    ; lettere: 1-26
:   ldx #>($D000 / 8)           ; glifo: $D000 + codice * 8
    stx glyph+2
    asl a
    rol glyph+2
    asl a
    rol glyph+2
    asl a
    rol glyph+2
    sta glyph+1
    ldx pr_row
    jsr pr_cell_addr
    ldy #7
glyph:
    lda $ffff,y
    sta (ptr),y
    dey
    bpl glyph
    inc pr_col
    ldy pr_n
    iny
    bne char
done:
    lda #$35
    sta $01
    plp
    rts
.endproc

; ------------------------------------------------------------------------------------ caricamento

; Schermo spento: la bitmap pulita (8 pagine per frame; $D000 e dopo con l'I/O spento), poi i colori
; neri con il titolo, poi si accende.
.proc pr_load
    lda #MODE_OFF
    sta sh_mode
    lda #1                      ; sprite e titolo sotto l'I/O da rimettere (e_restore)
    sta e_io
    lda pr_step
    cmp #4
    bcs colors
    asl a
    asl a
    asl a
    adc #>PR_BITMAP             ; (C = 0) pagine $C0 + 8 * passo
    ldy #8
    php
    sei
    ldx #$34
    stx $01
page:
    sta c0+2                    ; (otto scritture per giro: circa 12.300 cicli per 8 pagine, nel
    sta c1+2                    ; frame NTSC con la musica)
    sta c2+2
    sta c3+2
    sta c4+2
    sta c5+2
    sta c6+2
    sta c7+2
    lda #0
    tax
:
c0: sta $ff00,x
c1: sta $ff20,x
c2: sta $ff40,x
c3: sta $ff60,x
c4: sta $ff80,x
c5: sta $ffa0,x
c6: sta $ffc0,x
c7: sta $ffe0,x
    inx
    cpx #32
    bne :-
    lda c0+2
    clc
    adc #1
    cmp #>(PR_BITMAP + 8000)
    beq last
    dey
    bne page
    beq :++
last:
    lda #0                      ; $DF00-$DF3F (dopo, oltre la bitmap)
    ldx #63
:   sta $df00,x
    dex
    bpl :-
:   lda #$35
    sta $01
    plp
    inc pr_step
    rts
colors:
    bne show
    ; colori neri, poi YOUR OPPONENTS giallo nella riga 1
    lda #0
    tax
:   sta PR_COLORS,x
    sta PR_COLORS + $100,x
    sta PR_COLORS + $200,x
    sta PR_COLORS + $300,x
    inx
    bne :-
    lda #1
    sta pr_row
    tax
    lda #13
    sta pr_col
    jsr pr_color_addr
    lda egg_yel
    asl a
    asl a
    asl a
    asl a
    ldy #13
:   sta (ptr),y
    dey
    bpl :-
    lda #<pr_title
    sta ptr2
    lda #>pr_title
    sta ptr2+1
    jsr pr_text
    ; la cella sotto i puntatori degli sprite: vuota finché non c'è il primo ritratto
    lda #0
    ldx #7
:   sta sh_ptr,x
    dex
    bpl :-
    inc pr_step
    rts
show:
    lda #MODE_TEXT              ; (apply_shadows: poi $D011 e $D018 da qui)
    sta sh_mode
    inc pr_step
    rts
.endproc
pr_title: .byte "YOUR OPPONENTS", 0

; ------------------------------------------------------------------------------------ fine

; Gli ultimi PR_RESTORE frame, a schermo spento: il set del finale dalla cartuccia (4 frame), il
; font dalla ROM e le lettere 2x (e_glyphs, qualche frame), gli sprite del programma e il titolo
; dell'attract sotto l'I/O (e_restore, 16 frame).
.proc pr_restore
    lda #MODE_OFF
    sta sh_mode
    lda pr_r
    cmp #4
    bcs glyphs
    ; il set di caratteri del finale (ENDCH): 2 pagine per frame
    asl a
    pha
    adc #$80 + EPG_CH .mod EPG_BANK     ; (C = 0)
    sta ef_src+2
    pla
    adc #>CHARSET
    tay
    lda #END_BANK + EPG_CH / EPG_BANK
    ldx #2
    jsr ef_copy
    inc pr_r
    lda pr_r
    cmp #4
    bne done
    lda #1                      ; poi i glifi (e_glyphs: prima il font, poi le lettere 2x da
    sta e_fix                   ; capo: all'inizio del finale le ha già fatte)
    lda #0
    sta e_bk
    lda #<(CHARSET + 8 * END_BIG_BASE)
    sta e_bp
    lda #>(CHARSET + 8 * END_BIG_BASE)
    sta e_bp+1
done:
    rts
glyphs:
    cmp #4
    bne under
    jsr e_glyphs
    bcc done
    inc pr_r
    rts
under:
    ; poi gli sprite e il titolo sotto l'I/O (e_restore, ending.s), finché e_io torna a 0
    lda e_io
    beq done
    jmp e_restore
.endproc

pr_name_lo: .lobytes pr_arcade, pr_titan, pr_hammer, pr_twist, pr_blaster, pr_rush, pr_guardian
pr_name_hi: .hibytes pr_arcade, pr_titan, pr_hammer, pr_twist, pr_blaster, pr_rush, pr_guardian
pr_arcade:   .byte "ARCADE", 0
pr_titan:    .byte "TITAN", 0
pr_hammer:   .byte "HAMMER", 0
pr_twist:    .byte "TWIST", 0
pr_blaster:  .byte "BLASTER", 0
pr_rush:     .byte "RUSH", 0
pr_guardian: .byte "GUARDIAN", 0

.segment "CODE"
