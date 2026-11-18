; Scelta della racchetta di NEXT con i ritratti dei personaggi (4.5.0), come
; rust/game/src/paddle_ui.rs `PaddlePick::draw`: bitmap hires a $E000 con i colori a $C000 (il modo
; MODE_HOWTO della HOW TO PLAY), ritratti grandi ai lati (quello di destra specchiato) con il nome
; sotto, griglia delle caselle con quella di OMEGA, campo con le due racchette vere (gli sprite
; dell'anteprima, pick_preview), cursori gialli con la sigla del giocatore, frasi del tipo,
; comandi, tempo e READY!.
;
; Dove sta. Il codice gira a $C400 (segmento KPCODE, al posto delle mosse speciali, che la scelta dei
; bonus ricopia a READY): kind_enter (pick.s) lo copia dalla cartuccia, banco KP_BANK, pagine
; $80-$83. Dopo ci sono i dati di tools/gen_c64_portraits.py (gen/kpick.bin): lo sfondo (bitmap e
; colori, le scritte senza pixel) e i pannelli dei sette tipi per lato (ritratto e nome, 11x17
; celle). La bitmap copre le tabelle dei quadrati: math_ready resta a 1 finché si vede (math_step
; non ci scrive), poi math_invalidate le fa rifare nella scelta dei bonus.
;
; Lavoro per frame: la copia dello sfondo, 3 pagine per frame a schermo spento; un pannello in tre
; pezzi da 6 righe di celle (circa 9.000 cicli l'uno), un pezzo per frame; le scritte con i glifi del
; set (text_cell). Sprite: le sigle 0 e 1, i loro riquadri neri 2 e 5, le racchette 3 e 4, le
; cornici dei cursori 6 e 7 (davanti c'è il numero più basso: sigla, riquadro, cornice, come sul
; PC). Le immagini stanno nella riga 23 della bitmap, vuota e nera su nero: cornice e riquadri
; nello sfondo, le sigle le scrive kp_text_img con i glifi del set. La CPU sta sempre a destra.

.include "kpick.inc"

KP_RUN    = $C400
KP_BG     = $84                 ; pagina dello sfondo nella finestra a 16K, dopo il codice
KP_LOADED = KP_BG_PAGES + KP_COL_PAGES + 2      ; kp_pg: sfondo copiato, scritte, poi i pannelli
KP_PART_ROWS = 6                ; righe di celle di un pezzo di pannello
KP_ROW_BYTES = KP_PANEL_W * 9   ; per riga del pannello: bitmap e colori
KP_TEXT_IMG = $C000 + (KP_SPRITE + 3) * 64      ; immagini delle due sigle
.assert KP_PANEL_H <= 3 * KP_PART_ROWS, error, "pannello in più di tre pezzi"

.segment "KPCODE"
    jmp kp_tick                 ; KP_RUN: un frame della scelta
    jmp kp_sprites              ; KP_RUN + 3: cursori (da pick_preview)

kp_pg:     .byte 0              ; caricamento: pagina dello sfondo da copiare, poi le fasi fino a
                                ; KP_LOADED (il codice arriva fresco dalla cartuccia: si parte da 0)
kp_shown:  .byte $ff, $ff       ; tipo nel pannello di ciascun lato
kp_part:   .byte 3, 3           ; pezzo del pannello da copiare (3: fatto)
kp_label:  .byte 0, 0           ; OK da ridisegnare
kp_n:      .byte 0              ; temporanee
kp_r:      .byte 0
kp_c:      .byte 0
kp_x:      .byte 0

; ------------------------------------------------------------------------------------ frame

.proc kp_tick
    lda #KEY_STOP               ; RUN/STOP: il menu (le tabelle dei quadrati da rifare)
    jsr key_pressed
    bcc :+
    jsr math_invalidate
    jmp enter_menu
:   lda kp_pg
    cmp #KP_LOADED
    bcs live
    jmp kp_load
live:
    jsr kp_job
    lda pk_ready
    beq choosing
    dec pk_ready
    beq go
    ; READY! a tratti (6 volte al secondo, come sul PC)
    lda pk_ready
    and #7
    jne done
    ldx #<ks_ready
    lda pk_ready
    and #8
    bne :+
    ldx #<(ks_blank + 8)
:   txa
    ldx #KP_READY_COL
    ldy #KP_HINT_ROW
    jmp kp_print
go:
    jmp bonus_enter             ; (le tabelle dei quadrati le fa rifare la scelta dei bonus)
choosing:
    lda pk_frames
    bne :+
    dec pk_frames+1
:   dec pk_frames
    jsr kp_secs
    lda pk_fixed                ; chi non sceglie (la CPU o il campione) non ha comandi
    beq :+
    ldx #0
    jsr pick_player
:   lda pk_fixed
    cmp #1
    beq :+
    ldx #1
    jsr pick_player
:   jsr kp_dirty
    ; fine: tutti hanno scelto o il tempo è scaduto
    lda pk_frames
    ora pk_frames+1
    beq finish
    lda pk_ok
    and pk_ok+1
    beq done
finish:
    lda #1
    sta pk_ok
    sta pk_ok+1
    sta kp_label
    sta kp_label+1
    lda #READY_FRAMES
    sta pk_ready
    lda #EV_BOOST
    jsr sid_fx
    ; via i comandi
    ldx #KP_HINT_COL0
    jsr hint_off
    ldx #KP_HINT_COL1
hint_off:
    lda #<ks_blank
    ldy #KP_HINT_ROW
    jmp kp_print
done:
    rts
.endproc

; Secondi rimasti: draw_secs (pick.s) scrive le cifre del punteggio, 3x3 caratteri, nello schermo
; di testo, che qui sono i colori della bitmap; quando cambiano, i loro glifi vanno nella bitmap e i
; colori tornano bianchi.
.proc kp_secs
    lda pk_secs
    pha
    jsr draw_secs
    pla
    cmp pk_secs
    beq done
    lda #KP_TIMER_ROW
    sta v_row
row:
    ldy v_row
    lda row_lo,y
    sta ptr2
    lda row_hi,y
    sta ptr2+1
    ldy #KP_TIMER_COL
    sty p_col
cell:
    lda (ptr2),y
    pha
    lda #COL_WHITE << 4
    sta (ptr2),y
    pla
    jsr text_cell               ; (p_col + 1)
    ldy p_col
    cpy #KP_TIMER_COL + 6
    bne cell
    inc v_row
    lda v_row
    cmp #KP_TIMER_ROW + 3
    bne row
done:
    rts
.endproc

; Stringa (A: byte basso tra le stringhe di questo file, KS_PAGE) nella bitmap alla colonna X,
; riga Y.
.proc kp_print
    sta ptr2
    lda #>ks_p1
    sta ptr2+1
    lda #$40
    sta v_big
    jsr print_str
    lda #0
    sta v_big
    rts
.endproc

; Comandi cambiati da pick_player (pk_dirty): il pannello se il tipo è cambiato, poi l'OK.
.proc kp_dirty
    ldx #1
side:
    lda pk_dirty
    and pk_bit,x
    beq next
    eor pk_dirty
    sta pk_dirty
    lda #1
    sta kp_label,x
    lda pk_cursor,x
    cmp kp_shown,x
    beq next
    sta kp_shown,x
    lda #0
    sta kp_part,x
next:
    dex
    bpl side
    rts
.endproc

; Il lavoro in sospeso: gli OK, un pezzo di pannello (finito il pannello, la frase del tipo).
.proc kp_job
    ldx #1
label:
    lda kp_label,x
    beq next
    lda #0
    sta kp_label,x
    stx kp_x
    lda #<ks_ok                 ; OK (pk_ok) o il posto vuoto
    ldy pk_ok,x
    bne :+
    lda #<(ks_blank + 12)
:   ldy kp_ok_col,x
    sty kp_c
    ldx kp_c
    ldy #KP_LABEL_ROW
    jsr kp_print
    ldx kp_x
next:
    dex
    bpl label
    ; un pezzo di pannello: prima il lato sinistro
    ldx #0
    lda kp_part
    cmp #3
    bcc :+
    inx
    lda kp_part+1
    cmp #3
    bcs done
:   stx kp_x
    jsr kp_panel
    ldx kp_x
    inc kp_part,x
    lda kp_part,x
    cmp #3
    bne done
    ; la frase del tipo (kind_tags, pick.s), centrata nella metà
    lda kp_shown,x
    asl a
    tay
    lda kind_tags,y
    sta ptr2
    lda kind_tags+1,y
    sta ptr2+1
    lda kp_tag_col,x
    tax
    ldy #KP_TAG_ROW
    lda #$40
    sta v_big
    jsr print_str
    lda #0
    sta v_big
done:
    rts
.endproc

; ------------------------------------------------------------------------------------ caricamento

; Schermo spento: lo sfondo dalla cartuccia, 3 pagine per frame; poi le scritte fisse e le sigle;
; poi i due pannelli (kp_job) e si accende.
.proc kp_load
    lda #MODE_OFF
    sta sh_mode
    lda #1                      ; niente math_step nella bitmap
    sta math_ready
    lda kp_pg
    cmp #KP_BG_PAGES + KP_COL_PAGES
    bcs texts
    lda #3
    sta kp_n
page:
    lda kp_pg
    clc
    adc #KP_BG
    sta ef_src+2
    lda kp_pg
    ldy #>$E000
    cmp #KP_BG_PAGES
    bcc :+
    sbc #KP_BG_PAGES            ; (C = 1) i colori
    ldy #>SCREEN
:   sty kp_r
    clc
    adc kp_r
    tay
    lda #KP_BANK
    ldx #1
    jsr ef_copy
    inc kp_pg
    lda kp_pg
    cmp #KP_BG_PAGES + KP_COL_PAGES
    beq :+
    dec kp_n
    bne page
:   rts
texts:
    bne panels
    ; le ultime 8 celle della bitmap ($FF00-$FF3F: dopo ci sono le variabili) non si copiano
    lda #0
    ldx #63
:   sta $ff00,x
    dex
    bpl :-
    lda #<ks_title
    ldx #12
    ldy #0
    jsr kp_print
    ; nomi dei lati, sigle dei cursori, comandi di chi sceglie
    ldx #1
side:
    stx kp_x
    jsr kp_cpu                  ; Y = 1 per la CPU
    lda kp_name_lo,y
    pha
    lda kp_label_col,x
    tax
    pla
    ldy #KP_LABEL_ROW
    jsr kp_print
    ldx kp_x
    jsr kp_cpu
    lda kp_tag_lo,y
    jsr kp_text_img
    ldx kp_x
    cpx pk_fixed
    beq :+
    lda kp_hint_col,x
    tax
    lda #<ks_hint
    ldy #KP_HINT_ROW
    jsr kp_print
:   ldx kp_x
    dex
    bpl side
    lda #3                      ; i due pannelli (kp_job) e gli OK
    sta pk_dirty
    jsr kp_dirty
    inc kp_pg
    rts
panels:
    jsr kp_job
    lda kp_part
    and kp_part+1
    cmp #3
    bne :+
    lda #MODE_HOWTO
    sta sh_mode
    lda #PH_NONE                ; le anteprime delle racchette (pick_preview)
    sta pk_phase
    inc kp_pg
:   rts
.endproc

; Y = X + 1 se il lato X è la CPU (il destro), se no Y = X: indice di kp_name_lo, kp_tag_lo,
; kp_box_dx.
.proc kp_cpu
    txa
    tay
    beq :+
    lda pk_cpu
    beq :+
    iny
:   rts
.endproc


; ------------------------------------------------------------------------------------ pannelli

; Pezzo kp_part,X del pannello del lato X (tipo kp_shown,X): KP_PART_ROWS righe di celle, per riga
; 88 byte di bitmap e 11 di colori, dalla cartuccia (modo a 16K, $01 = $37, interrupt spenti; le
; scritture vanno nella RAM anche sotto il KERNAL).
.proc kp_panel
    ; pannello lato * 7 + tipo: banco e pagina
    txa
    beq :+
    lda #7
:   clc
    adc kp_shown,x
    tay
    lda kp_panel_bank,y
    clc
    adc #KP_BANK
    sta bank+1
    lda kp_panel_page,y
    sta src+2
    lda #0
    sta src+1
    ; prima riga del pezzo: kp_part * 6; sorgente + riga * 99
    sta kp_r
    ldy kp_part,x
    beq first
:   lda kp_r
    clc
    adc #KP_PART_ROWS
    sta kp_r
    dey
    bne :-
    tay
:   lda src+1
    clc
    adc #KP_ROW_BYTES
    sta src+1
    bcc :+
    inc src+2
:   dey
    bne :--
first:
    ; righe: KP_PART_ROWS o quelle che restano
    lda #KP_PANEL_H
    sec
    sbc kp_r
    cmp #KP_PART_ROWS
    bcc :+
    lda #KP_PART_ROWS
:   sta kp_n
    ; destinazioni della prima riga (con le tabelle del programma: a cartuccia accesa a $8000-$BFFF
    ; c'è la ROM), poi + 320 e + 40 a ogni riga
    lda kp_r
    clc
    adc #KP_PANEL_ROW
    tay
    lda kp_panel_col,x
    asl a
    asl a
    asl a
    adc cell_row_lo,y           ; (C = 0)
    sta dst+1
    lda cell_row_hi,y
    adc #0
    sta dst+2
    lda kp_panel_col,x
    adc row_lo,y                ; (C = 0)
    sta cdst+1
    lda row_hi,y
    adc #0
    sta cdst+2
    sei
bank:
    lda #KP_BANK
    sta EF_BANK
    lda #$37
    sta $01
    lda #EF_16K
    sta EF_MODE
row:
    ldy #KP_PANEL_W * 8 - 1
src:
    lda $ff00,y
dst:
    sta $ffff,y
    dey
    bpl src
    lda src+1
    clc
    adc #KP_PANEL_W * 8
    sta src+1
    sta csrc+1
    lda src+2
    adc #0
    sta src+2
    sta csrc+2
    ldy #KP_PANEL_W - 1
csrc:
    lda $ffff,y
cdst:
    sta $ffff,y
    dey
    bpl csrc
    lda src+1                   ; sorgente + 11
    clc
    adc #KP_PANEL_W
    sta src+1
    bcc :+
    inc src+2
:   lda dst+1                   ; bitmap + 320
    clc
    adc #<320
    sta dst+1
    lda dst+2
    adc #>320
    sta dst+2
    lda cdst+1                  ; colori + 40
    clc
    adc #40
    sta cdst+1
    bcc :+
    inc cdst+2
:   dec kp_n
    bne row
    lda #EF_OFF
    sta EF_MODE
    lda #$35
    sta $01
    cli
    rts
.endproc

; ------------------------------------------------------------------------------------ sprite

; Cursori e sigle (kp_cursors, nella riga 1 della bitmap): prima che lo schermo si veda, nessuno
; sprite.
.proc kp_sprites
    lda kp_pg
    cmp #KP_LOADED
    bcs :+
    lda #0
    sta sh_enable
    rts
:   jmp kp_cursors
.endproc
.assert SPR_X0 + KP_GRID_X + 4 * 32 < 256, error, "cursori: bit alto della x"

; ------------------------------------------------------------------------------------ dati

kp_label_col: .byte KP_LABEL_COL0, KP_LABEL_COL1
kp_cur_spr:   .byte 6, 7        ; sprite delle cornici (kp_cursors)
kp_ok_col:    .byte KP_OK_COL0, KP_OK_COL1
kp_hint_col:  .byte KP_HINT_COL0, KP_HINT_COL1
kp_tag_col:   .byte KP_TAG_COL0, KP_TAG_COL1
kp_panel_col: .byte KP_PANEL_COL0, KP_PANEL_COL1
; per indice kp_cpu (sinistro, destro, destro della CPU): nome e sigla
kp_name_lo:   .byte <ks_p1, <ks_p2, <ks_cpu
kp_tag_lo:    .byte <ks_1p, <ks_2p, <ks_cpu
kp_panel_bank: .byte KP_PANEL_BANK
kp_panel_page: .byte KP_PANEL_PAGE
ks_p1:    .byte "P1 ", 0
ks_p2:    .byte "P2 ", 0
ks_cpu:   .byte "CPU", 0
ks_1p:    .byte "1P", 0
ks_2p:    .byte "2P", 0
ks_ok:    .byte "OK", 0
ks_ready: .byte "READY!", 0
ks_title: .byte "PICK YOUR PADDLE", 0
ks_hint:  .byte "UP DOWN + FIRE", 0
ks_blank: .byte "              ", 0
.assert >ks_p1 = >(ks_blank + 14), error, "stringhe in pagine diverse (kp_print)"

; ------------------------------------------------------------------------------------ riga 1

; Codice nella riga 1 della bitmap, vuota e nera su nero (segmento KPCODE2): tools/make_crt.py lo
; mette nello sfondo della cartuccia, quindi c'è solo dopo la copia dello sfondo.
.segment "KPCODE2"

; Cursori e sigle sulle caselle; finché si sceglie lampeggiano (spenti un quarto di secondo ogni
; secondo, come sul PC).
.proc kp_cursors
    ldx #1
side:
    stx kp_x
    lda pk_ok,x
    ora pk_ready
    bne on
    cpx pk_fixed
    beq on
    lda frame_count
    and #63
    cmp #48
    bcs next
on:
    ; angolo della casella negli sprite: kp_c (x), kp_r (y)
    lda pk_cursor,x
    and #3
    asl a
    asl a
    asl a
    asl a
    asl a
    adc #<(SPR_X0 + KP_GRID_X)  ; (C = 0)
    sta kp_c
    lda pk_cursor,x
    and #4
    asl a
    asl a
    asl a
    adc #<(SPR_Y0 + KP_GRID_Y)
    sta kp_r
    ; cornice, espansa anche in y
    ldy kp_cur_spr,x
    lda #KP_SPRITE
    ldx #0
    jsr spr
    lda bit_of,y
    ora sh_yexp
    sta sh_yexp
    ; riquadro nero, due pixel dentro la casella (CPU, a destra, più largo)
    ldx kp_x
    jsr kp_cpu
    lda kp_box_img,y
    sta kp_n
    lda kp_box_dx,y
    ldy kp_box_spr,x
    tax
    lda kp_n
    jsr spr
    lda #COL_BLACK
    sta sh_col,y
    ; sigla, un pixel più a destra e una riga più in basso, non espansa
    ldy kp_x
    lda #KP_SPRITE + 3
    adc kp_x                    ; (C = 0)
    pha
    lda kp_box_spr,y
    tay
    ldx sh_x,y
    inx
    pla
    ldy kp_x
    jsr spr_xy
    lda bit_of,y
    eor #$ff
    and sh_xexp
    sta sh_xexp
    ldx kp_x
next:
    dex
    jpl side
    rts
; sprite Y con l'immagine A, alla x kp_c + X e alla y kp_r + 22 (o kp_r per la cornice, X = 0)
spr:
    pha
    txa
    clc
    adc kp_c
    tax
    pla
    sta sh_ptr,y
    lda kp_r
    cpx kp_c
    beq :+
    clc
    adc #22
:   sta sh_y,y
    txa
    jmp place
; sprite Y con l'immagine A alla x X e alla y kp_r + 23 (la sigla)
spr_xy:
    sta sh_ptr,y
    lda kp_r
    clc
    adc #23
    sta sh_y,y
    txa
place:
    sta sh_x,y
    lda egg_yel                 ; (rosso con l'easter egg)
    sta sh_col,y
    lda bit_of,y
    ora sh_enable
    sta sh_enable
    lda bit_of,y
    ora sh_xexp
    sta sh_xexp
    lda bit_of,y
    eor #$ff
    pha
    and sh_mc
    sta sh_mc
    pla
    pha
    and sh_msb
    sta sh_msb
    pla
    and sh_yexp
    sta sh_yexp
    clc
    rts
.endproc
; Immagine della sigla del lato X (stringa A, byte basso) nello sprite KP_SPRITE + 3 + X: i glifi
; del set, un carattere per byte di ogni riga.
.proc kp_text_img
    sta ptr2
    lda #>ks_p1
    sta ptr2+1
    lda kp_img_lo,x
    sta dst+1
    ldy #0
char:
    sty kp_c
    lda (ptr2),y
    beq done
    tay
    lda font_map - 32,y         ; glifo: CHARSET + carattere * 8
    ldx #>(CHARSET / 8)
    stx src+2
    asl a
    rol src+2
    asl a
    rol src+2
    asl a
    rol src+2
    sta src+1
    ldx #0
    ldy #0
row:
src:
    lda $ffff,y
dst:
    sta KP_TEXT_IMG,x
    inx
    inx
    inx
    iny
    cpy #8
    bne row
    inc dst+1
    ldy kp_c
    iny
    bne char
done:
    rts
.endproc
.assert >KP_TEXT_IMG = >(KP_TEXT_IMG + 127), error, "sigle a cavallo di pagina"

kp_box_spr:   .byte 2, 5        ; e dei riquadri delle sigle
kp_img_lo:    .byte <KP_TEXT_IMG, <(KP_TEXT_IMG + 64)
; per indice kp_cpu: riquadro e sua x nella casella (2 pixel dal bordo; a destra la sigla di 18 o
; 26 pixel)
kp_box_img:   .byte KP_SPRITE + 1, KP_SPRITE + 1, KP_SPRITE + 2
kp_box_dx:    .byte 2, 32 - 2 - 18, 32 - 2 - 26

.segment "CODE"
