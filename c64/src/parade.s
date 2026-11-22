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
;
; Multicolor: i ritratti (righe 3-11 e 14-22) sono in bitmap multicolor, con il terzo colore nella
; Color RAM; titolo e nomi restano in hires. Lo split del raster (pr_irq) accende il multicolor
; nell'ultima riga di pixel prima di ogni fila e lo spegne nella prima riga dei nomi, vuote (i glifi
; si scrivono una riga più in basso: la loro ultima riga è vuota). pr_irq accende da sé l'I/O e
; rimette $01: le copie nella bitmap (l'I/O spento per la metà bassa) e le scritte (la ROM dei
; caratteri) non spengono gli interrupt. Li spegne ef_copy: le pagine dell'appoggio, una per frame,
; si copiano solo all'inizio del frame (PR_COPY_LATE), se no la sfilata aspetta un frame. Lo split
; si accende con il caricamento e si spegne a schermo spento alla fine (pr_restore) o con il salto
; del finale (close_enter, irq_normal di ending.s). Nella riga 0 della bitmap (nera) il codice di
; nomi e scritte (PRCODE2), copiato con i colori.

PR_RUN    = $F400
PR_STAGE  = $F800               ; appoggio: un pannello (9 righe da 72 byte)
PR_COLORS = $F000
PR_BITMAP = $C000
PR_BANK   = KP_BANK + PR_BANK_REL
PR_D018   = (PR_COLORS - $C000) / $400 << 4
PR_STEP   = 25                  ; un ritratto al secondo, il timbro mezzo secondo dopo
PR_STAMP  = 12
PR_PAGES  = 3                   ; pagine di un pannello nell'appoggio, una per frame
PR_PARTS  = 3                   ; pezzi della copia nella bitmap, 3 righe di celle per frame
.assert PR_PAGES + PR_PARTS <= PR_STAMP .and PR_STAMP + PR_PAGES + PR_PARTS <= PR_STEP, error, "sfilata: i passi di un ritratto"
.assert PR_PARTS * 3 = PR_H, error, "sfilata: i pezzi della copia"
; split del raster: righe di pixel vuote del cambio (prima delle due file, righe 3 e 14, e la prima
; riga dei nomi, 12 e 23)
PR_LINE_ON0  = 51 + 3 * 8 - 1
PR_LINE_OFF0 = 51 + 12 * 8
PR_LINE_ON1  = 51 + 14 * 8 - 1
PR_LINE_OFF1 = 51 + 23 * 8
; una pagina dalla cartuccia (circa 3.800 cicli, interrupt spenti) tra due cambi dello split
; (pr_copy_time): partita entro PR_COPY_EARLY dopo il giro del raster finisce prima di quello in alto,
; tra PR_LINE_ON0 + 1 e PR_COPY_MID prima del secondo
PR_COPY_LINES = 3900 / TV_LCYC + 1
PR_COPY_EARLY = PR_LINE_ON0 - 1 - PR_COPY_LINES
PR_COPY_MID   = PR_LINE_OFF0 - 1 - PR_COPY_LINES
.assert PR_COPY_EARLY > 0 .and PR_COPY_MID > PR_LINE_ON0 + 1, error, "sfilata: la copia tra due cambi"
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
pr_k:    .byte 0                ; passo del ritratto (pagine, poi pezzi della copia)

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
    ; la bitmap a $C000, i colori a $F000 ($D016 lo cambia lo split, pr_irq)
    lda #$3b
    sta $d011
    lda #PR_D018
    sta $d018
    ; un ritratto ogni PR_STEP frame: nei primi PR_PAGES dalla cartuccia all'appoggio (una pagina
    ; per frame), nei PR_PARTS dopo nella bitmap (3 righe per frame, all'ultimo il nome); PR_STAMP
    ; frame dopo lo stesso con il ritratto sconfitto
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
:   cmp #PR_PAGES + PR_PARTS
    bcs done
    sty pr_n
    sty pr_ev
    sta pr_k
    jsr pr_panel_page           ; (OMEGA in sagoma: niente timbro)
    bcs done
    ldx pr_k
    cpx #PR_PAGES
    bcs blit
    ; una pagina del pannello nell'appoggio, se il frame non è già avanti (se no la sfilata aspetta)
    adc pr_k                    ; (C = 0)
    sta ef_src+2
    jsr pr_copy_time
    bcs wait
    lda #>PR_STAGE
    adc pr_k                    ; (C = 0)
    tay
    lda #PR_BANK
    ldx #1
    jsr ef_copy
    jmp done
blit:
    txa
    sbc #PR_PAGES               ; (C = 1) il pezzo
    pha
    jsr pr_blit
    pla
    cmp #PR_PARTS - 1
    bne done
    lda pr_ev
    sta pr_n
    jsr pr_name
done:
    inc pr_f
wait:
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

; Pezzo A (3 righe) del pannello dell'appoggio nella bitmap del posto pr_i (righe da 64 byte, poi 8
; colori e 8 di Color RAM): la bitmap con l'I/O spento (la metà bassa è sotto), colori e Color RAM
; con l'I/O acceso; interrupt accesi (pr_irq). Poi i byte della cella sotto i puntatori degli
; sprite in sh_ptr (apply_shadows li riscrive a ogni frame).
.proc pr_blit
    sta pr_n
    jsr pr_slot
    sta pr_row
    stx pr_col
    lda #<PR_STAGE
    sta ptr2
    lda #>PR_STAGE
    sta ptr2+1
    ldx pr_n
    beq rows
:   lda pr_row
    clc
    adc #3
    sta pr_row
    lda ptr2
    adc #<(3 * PR_ROW_BYTES)    ; (C = 0)
    sta ptr2
    lda ptr2+1
    adc #>(3 * PR_ROW_BYTES)
    sta ptr2+1
    dex
    bne :-
rows:
    lda #3
    sta pr_n
row:
    ; bitmap: $C000 + riga * 320 + colonna * 8
    ldx pr_row
    jsr pr_cell_addr
    lda #$34
    sta $01
    ldy #PR_W * 8 - 1
:   lda (ptr2),y
    sta (ptr),y
    dey
    bpl :-
    lda #$35
    sta $01
    ; colori: $F000 + riga * 40 + colonna, poi la Color RAM, $D800 + riga * 40 + colonna
    jsr pr_color_addr
    ldy #PR_W * 8 + PR_W - 1
    jsr pr_copy8
    lda ptr+1
    sec
    sbc #>(PR_COLORS - $D800)
    sta ptr+1
    ldy #PR_W * 8 + 2 * PR_W - 1
    jsr pr_copy8
    lda ptr2
    clc
    adc #PR_ROW_BYTES
    sta ptr2
    bcc :+
    inc ptr2+1
:   inc pr_row
    dec pr_n
    bne row
    ldx #7
:   lda $c3f8,x
    sta sh_ptr,x
    dex
    bpl :-
    rts
.endproc
pr_cbuf: .res PR_W

; C = 0 se una pagina dalla cartuccia (interrupt spenti) si può copiare ora senza coprire un cambio
; dello split: prima del giro del raster o subito dopo (finisce prima del cambio in alto), o subito
; dopo il cambio in alto (finisce prima del secondo; poco prima di quel cambio si aspetta). C = 1:
; troppo avanti, al frame dopo.
.proc pr_copy_time
    lda $d011
    bmi ok                      ; righe 256 e oltre
    lda $d012
    cmp #RASTER_LINE
    bcs ok                      ; 250-255
    cmp #PR_COPY_EARLY
    bcc ok
    cmp #PR_LINE_ON0 + 1
    bcc wait
    cmp #PR_COPY_MID
    bcc ok
    rts                         ; (C = 1)
wait:
:   lda $d012
    cmp #PR_LINE_ON0 + 1
    bcc :-
ok:
    clc
    rts
.endproc

; Gli 8 byte dell'appoggio (ptr2) fino al Y in (ptr) (colori o Color RAM di una riga).
.proc pr_copy8
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
    rts
.endproc
.assert <PR_COLORS = 0 .and <($D800) = 0, error, "sfilata: Color RAM dai colori"

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

; ------------------------------------------------------------------------------------ caricamento

; Schermo spento: la bitmap pulita (8 pagine per frame; $D000 e dopo con l'I/O spento), poi i colori
; neri con il titolo, poi si accende.
.proc pr_load
    lda pr_step
    bne :+
    jsr pr_split_on             ; (schermo spento: lo split con le copie e le scritte di dopo)
:   lda #MODE_OFF
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
    ; il codice della riga 0 (PRCODE2, sulla bitmap appena pulita), colori neri, poi YOUR OPPONENTS
    ; giallo nella riga 1
    lda #PR_CODE2P
    sta ef_src+2
    lda #PR_BANK
    ldx #1
    ldy #>PR_BITMAP
    jsr ef_copy
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
    lda #COL_YELLOW
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

; ------------------------------------------------------------------------------------ fine

; Gli ultimi PR_RESTORE frame, a schermo spento: il set del finale dalla cartuccia (4 frame), il
; font dalla ROM e le lettere 2x (e_glyphs, qualche frame), gli sprite del programma e il titolo
; dell'attract sotto l'I/O (e_restore, 16 frame).
.proc pr_restore
    jsr irq_normal              ; (ending.s: lo split spento)
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

; Split del raster: alle righe PR_LINE_* - 1 aspetta la riga PR_LINE_* (vuota) e accende o spegne
; il multicolor, poi alla riga 250 quello che fa irq_handler. Con qualsiasi $01: accende l'I/O per i
; registri e rimette $01 (le copie nella bitmap e le scritte lo spengono).
.proc pr_irq
    pha
    txa
    pha
    lda $01
    pha
    lda #$35
    sta $01
    ldx pr_irq_n                ; 0 la riga 250, 1-4 i cambi
    beq vbl
:   lda $d012
    cmp pr_line,x
    bcc :-
    lda pr_d016,x
    sta $d016
    lda pr_next,x
    sta $d012
    inx
    cpx #5
    bcc :+
    ldx #0
:   stx pr_irq_n
ack:
    lda #$ff
    sta $d019
    pla
    sta $01
    pla
    tax
    pla
    rti
vbl:
    lda #PR_LINE_ON0 - 1
    sta $d012
    inc pr_irq_n
    inc frame_flag              ; (come irq_handler)
    inc frame_count
    bne ack
    inc frame_count+1
    jmp ack
.endproc
pr_irq_n: .byte 0
pr_line   = * - 1               ; (per pr_irq_n 1-4)
    .byte PR_LINE_ON0, PR_LINE_OFF0, PR_LINE_ON1, PR_LINE_OFF1
pr_d016   = * - 1
    .byte $c8 | $10, $c8, $c8 | $10, $c8
pr_next   = * - 1
    .byte PR_LINE_OFF0 - 1, PR_LINE_ON1 - 1, PR_LINE_OFF1 - 1, RASTER_LINE
.assert PR_LINE_OFF1 < RASTER_LINE, error, "sfilata: righe dello split"

; Lo split acceso: pr_irq al posto di irq_handler (lo rimette irq_normal di ending.s). L'interrupt
; dopo è quello della riga 250.
.proc pr_split_on
    sei
    lda #0
    sta pr_irq_n
    lda #<pr_irq
    sta $fffe
    lda #>pr_irq
    sta $ffff
    cli
    rts
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

pr_title: .byte "YOUR OPPONENTS", 0

; ------------------------------------------------------------------------------------ riga 0

; Codice nella riga 0 della bitmap (colonne 0-31, nera, segmento PRCODE2): pr_load lo copia dalla
; cartuccia con i colori (tools/make_crt.py lo mette nella pagina PR_CODE2P dei dati).
.segment "PRCODE2"

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
; le scritture lì nella RAM sotto; interrupt accesi (pr_irq). Ogni glifo una riga più in basso
; (l'ultima riga dei glifi è vuota): la prima riga di pixel resta vuota per lo split.
.proc pr_text
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
    ldy #6
glyph:
    lda $ffff,y
    iny
    sta (ptr),y
    dey
    dey
    bpl glyph
    lda #0
    tay
    sta (ptr),y
    inc pr_col
    ldy pr_n
    iny
    bne char
done:
    lda #$35
    sta $01
    rts
.endproc


.segment "CODE"
