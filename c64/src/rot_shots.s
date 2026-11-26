; Campo girato (ROTATED): i colpi del BLASTER, al posto di next_shots e compagni di pick.s.
;
; Ogni colpo sono due fasci verticali di 2x7 pixel nelle colonne delle bocche dei cannoni
; (ROT_SHOT_A dalla prima colonna della racchetta, la seconda ROT_SHOT_D più in là), dalla riga
; ROT_W - 4 - int(x) (la x del colpo, verso l'alto per chi gioca in basso), a passi di 2 pixel come
; oggi. Un fascio prende la cella in alto e, se non comincia in cima alla cella, quella sotto: i
; caratteri sono quelli di oggi (SHOT_CHARS, posizione nella cella * 8 + riga * 2, alto e basso)
; con il tratto in verticale. Si disegna per colpo: quando cambia riga si rimette quello che c'era
; sotto (sv_c, sv_k: posto colpo * 4 + fascio * 2 + cella) e si disegna il tratto nuovo, prima
; tutte le cancellazioni (dall'ultimo colpo) e poi i disegni. Se sotto c'è già un fascio (due colpi
; che si incrociano) al frame dopo si toglie e si ridisegna tutto. Sulla mezzeria il carattere è
; fuso (SHOT_P0 + posto: la mezzeria con il tratto sopra, nel suo colore); altrove il fascio copre.
; Il posto di una cella è colpo * 4 + fascio * 2 + riga di celle & 1: una cella che resta del
; fascio tiene il suo posto (e il suo carattere fuso) anche quando il fascio si sposta.
;
; Un colpo che ha solo cambiato riga non si toglie e ridisegna: rs_move rimette le celle lasciate,
; salva e disegna quelle nuove e in quelle che restano cambia solo il carattere del tratto. Vale se
; nessun altro fascio è vicino (RS_NEAR_Y righe e RS_NEAR_X colonne, su tutte le coppie dei colpi a
; schermo) e se al frame prima non c'erano sovrapposizioni: se no chi si è mosso si toglie e si
; ridisegna, come prima. Lo schermo è lo stesso nei due modi.
; Variabili di pick.s con un altro uso: sd_y la riga in alto del fascio a schermo, sd_cw la colonna
; del primo fascio ($FF niente a schermo), sd_on i colpi con celle a schermo, sv_la e sv_ha la riga
; e la colonna di adesso dei colpi da disegnare (rs_vis).

RS_KX = HALF_PX - 1 - ((ROT_BL_HALF - ROT_SHOT_A) << 16)   ; colonna del primo fascio: y + RS_KX, byte 2
RS_NEAR_Y = 26                  ; fasci vicini: righe (un colpo si sposta al più di 6 pixel a frame:
RS_STEP   = 6                   ; due colpi a meno di 6 + 6 + 6 + 8 righe possono toccare la stessa
RS_NEAR_X = 30                  ; cella) e colonne (i due fasci di un colpo sono a ROT_SHOT_D)
.assert (P_SHOT_SPEED >> 16) + 2 <= RS_STEP .and ROT_SHOT_D + 8 <= RS_NEAR_X .and 3 * RS_STEP + 8 <= RS_NEAR_Y, error, "colpi: soglie dei fasci vicini"
rs_k    = m_b                   ; colpo
rs_r    = m_b + 1               ; (rs_fuse)
rs_c    = m_b + 2               ; colonna del fascio (pixel)
rs_slot = m_b + 3               ; posto delle celle del fascio (colpo * 4 + fascio * 2)
rs_row  = m_a                   ; riga di caratteri della cella in alto (con il segno)
rs_f    = m_a + 1               ; riga del tratto nella cella (0, 2, 4, 6)
rs_g    = m_a + 2               ; carattere del tratto (indice in shot_chars)
rs_mode = m_a + 3               ; bit 7: rimette
rs_vis  = n_t                   ; colpi da disegnare (bit k: colpo k)
rs_n    = n_t + 1               ; quanti sono
rs_gen  = n_t + 2               ; bit 7: fasci vicini, chi si è mosso si toglie e si ridisegna
rs_w    = n_t + 3               ; (maschera che scorre, indice)
rs_o    = m_p                   ; rs_move: righe di celle di prima da rs_row (bit k: rs_row + k)
rs_nw   = m_p + 1               ; e di adesso
rs_tr   = m_p + 2               ; riga della cella in alto di adesso
rs_c0   = m_p + 3               ; carattere del tratto nella riga di celle in esame: fascio sinistro,
rs_c1   = m_p + 4               ; destro
rs_l0   = m_p + 5               ; e nella cella sotto
rs_l1   = m_p + 6
ptr3    = fz_s                  ; rs_move: cella del fascio destro e il suo colore (pagina zero di
ptr4    = fz_hi                 ; bd_fuse, che il campo girato non ha)
.assert fz_new = fz_hi + 1, error, "rs_move: ptr4 in fz_hi e fz_new"
.segment "NEXTBSS"
rs_ls:  .res 2 * MAX_SHOTS      ; colpi da disegnare, in fila: il colpo,
rs_ly:  .res 2 * MAX_SHOTS      ; la sua riga
rs_lx:  .res 2 * MAX_SHOTS      ; e la sua colonna
.segment "CODE"

.proc next_shots
    ; fuori dalla partita, come oggi: i colpi si dimenticano, i caratteri presi tornano vuoti e nel
    ; GAME OVER le lettere 2x si rifanno, metà per frame
    lda state
    cmp #ST_COUNT
    bcc out_game
    cmp #ST_PLAY + 1
    bcc in_game
out_game:
    lda sg_on
    beq leave
    cmp #SG_GLYPHS
    bne relet
    ldx #8 * SHOT_BN
    lda #0
blank:
    sta SG_DST - 1,x
    dex
    bne blank
    beq step                    ; (sempre)
relet:
    ldx state
    cpx #ST_OVER
    bne leave
    ldy #0
    cmp #SG_BLANK
    beq :+
    ldy #BIG2_N / 2
:   ldx #BIG2_N / 2
    jsr big2_build
step:
    inc sg_on
leave:
    lda #0
    sta sv_n
    rts
in_game:
    lda m_next
    beq none
    ; colpi in volo (bit k: colpo k)
    lda shot_on+7
    .repeat 7, k
    asl a
    ora shot_on+6-k
    .endrepeat
    bne some
none:
    jmp shots_erase             ; (via quelli rimasti)
some:
    sta rs_w
    lda sv_n                    ; niente a schermo che conti (schermo nuovo: hud_reset, shots_erase)
    bne :++
    sta sd_on
    lda #$FF
    ldx #2 * MAX_SHOTS - 1
:   sta sd_cw,x
    dex
    bpl :-
:   ; riga e colonna di adesso dei colpi in volo che si vedono, in fila (rs_ls, rs_ly, rs_lx)
    lda #0
    sta rs_vis
    sta rs_n
    ldx #$FF
geo:
    inx
    lsr rs_w
    bcs fly
    bne geo
    beq geo_done                ; (sempre)
fly:
    txa
    asl a
    asl a
    tay
    lda shot_x+3,y
    bne geo_next                ; (fuori dal campo)
    lda shot_x+2,y              ; passato l'alto del campo di più di 8 pixel: niente da disegnare
    cmp #ROT_W + 4              ; (la riga resta tra -8 e ROT_W - 4)
    bcs geo_next
    lda #ROT_W - 4
    sec
    sbc shot_x+2,y
    and #$FE
    sta sv_la,x
    clc
    lda shot_y,y
    adc #<RS_KX
    lda shot_y+1,y
    adc #>RS_KX
    lda shot_y+2,y
    adc #^RS_KX
    and #$FE
    sta sv_ha,x
    ldy rs_n
    sta rs_lx,y
    lda sv_la,x
    sta rs_ly,y
    txa
    sta rs_ls,y
    inc rs_n
    lda bit_of,x
    ora rs_vis
    sta rs_vis
geo_next:
    lda rs_w
    bne geo
geo_done:
    ; due colpi vicini (o sovrapposti al frame prima): niente aggiornamenti sul posto
    lda sv_n
    and #$80
    sta rs_gen
    bmi pass1
    ldx rs_n
    cpx #2
    bcc pass1
    dex
pair_i:
    txa
    tay
pair_j:
    dey
    bmi pair_next
    lda rs_ly,x
    sec
    sbc rs_ly,y
    clc
    adc #RS_NEAR_Y - 1
    cmp #2 * RS_NEAR_Y - 1
    bcs pair_j                  ; lontani in riga
    lda rs_lx,x
    sec
    sbc rs_lx,y
    clc
    adc #RS_NEAR_X - 1
    cmp #2 * RS_NEAR_X - 1
    bcs pair_j                  ; lontani in colonna
    dec rs_gen                  ; ($FF)
    bne pass1                   ; (sempre)
pair_next:
    dex
    bne pair_i
pass1:
    ; via i colpi a schermo che non si vedono più o che vanno ridisegnati da capo (tutti dopo una
    ; sovrapposizione), dall'ultimo
    lda sd_on
    beq pass2
    ldx #2 * MAX_SHOTS
era:
    dex
    asl a
    bcs era_hit
    bne era
    beq pass2                   ; (sempre)
era_hit:
    pha
    bit sv_n
    bmi era_go
    lda bit_of,x
    and rs_vis
    beq era_go                  ; non si vede più
    lda sv_ha,x
    cmp sd_cw,x
    bne era_go                  ; (un altro colpo nello stesso posto)
    lda sv_la,x
    sec
    sbc sd_y,x
    beq era_keep                ; fermo
    bit rs_gen
    bmi era_go
    clc
    adc #RS_STEP
    cmp #2 * RS_STEP + 1
    bcc era_keep                ; un passo: resta, lo sposta rs_move
era_go:
    jsr erase_shot
era_keep:
    pla
    bne era
pass2:
    ; poi i disegni, in ordine: i colpi nuovi (o tolti) per intero, quelli spostati sul posto
    lda #0
    sta sv_n
    sta rs_w
draw:
    ldy rs_w
    cpy rs_n
    bcs drawn
    ldx rs_ls,y
    lda sd_cw,x
    cmp #$FF
    bne :+
    jsr draw_shot
    jmp draw_next
:   lda sv_la,x
    cmp sd_y,x
    beq draw_next
    jsr rs_move
draw_next:
    inc rs_w
    bne draw                    ; (sempre)
drawn:
    lda rs_n
    beq :+
    lda sv_n
    ora #1
    sta sv_n
:   rts
.endproc

; Disegna il colpo X dalla riga sv_la e dalla colonna sv_ha (poi sd_y e sd_cw). X resta.
.proc draw_shot
    lda sv_la,x
    sta sd_y,x
    lda sv_ha,x
    sta sd_cw,x
    lda bit_of,x
    ora sd_on
    sta sd_on
    clc
    jmp shot_cells
.endproc

; Rimette le celle del colpo X a schermo (riga sd_y, colonna sd_cw) e lo segna senza celle. X resta.
.proc erase_shot
    sec
    jsr shot_cells
    lda #$FF
    sta sd_cw,x
    lda bit_of,x
    eor #$FF
    and sd_on
    sta sd_on
    rts
.endproc

; Le celle del colpo X (riga sd_y, colonna sd_cw): con C = 0 il tratto (salvando quello che c'è
; sotto), con C = 1 quello che c'era. Per fascio i puntatori una volta, la cella sotto 40 byte più
; in là. X resta.
.proc shot_cells
    ror rs_mode
    stx rs_k
    lda sd_y,x
    and #6
    sta rs_f
    lda sd_y,x                  ; riga di caratteri della cella in alto (-1..24): sd_y va da -8 a
    cmp #$F0                    ; ROT_W - 4, negativo solo da $F0 (la metà in basso è oltre 127)
    bcc :+
    lda #$FF
    bne :++
:   lsr a
    lsr a
    lsr a
:   sta rs_row
    txa
    asl a
    asl a
    sta rs_slot                 ; posto: colpo * 4 + fascio * 2 + riga & 1
    lda sd_cw,x
    sta rs_c
    jsr beam
    lda rs_c
    clc
    adc #ROT_SHOT_D
    sta rs_c
    inc rs_slot
    inc rs_slot
    jsr beam
    ldx rs_k
    rts
beam:
    ; carattere: posizione nella cella ((c >> 1) & 3) * 8 + riga
    lda rs_c
    lsr a
    and #3
    asl a
    asl a
    asl a
    ora rs_f
    sta rs_g
    ; puntatori della prima riga a schermo (la cella in alto, o la sotto con quella fuori)
    ldy rs_row
    bpl :+
    ldy #0
:   lda rs_c
    lsr a
    lsr a
    lsr a
    clc
    adc row_lo,y
    sta ptr
    sta ptr2
    lda row_hi,y
    adc #0
    sta ptr+1
    adc #>($d800 - SCREEN)
    sta ptr2+1
    lda rs_row
    bmi lower                   ; (sopra lo schermo)
    sta v_row
    and #1
    ora rs_slot
    tax
    ldy rs_g
    lda shot_chars,y
    ldy #0
    jsr cell
lower:
    ldx rs_row
    inx
    cpx #25
    bcs done                    ; (sotto lo schermo)
    stx v_row
    txa
    and #1
    ora rs_slot
    tax
    ldy rs_g
    lda shot_chars+1,y
    beq done                    ; (una cella sola)
    ldy #40
    bit rs_row
    bpl cell
    ldy #0
; A = carattere del tratto nella cella (ptr),Y della riga v_row, posto X
cell:
    bit rs_mode
    bmi restore
    sta v_n
    lda (ptr),y                 ; salva
    sta sv_c,x
    jsr rs_over
    lda (ptr2),y
    sta sv_k,x
    lda v_row                   ; sulla mezzeria: il carattere fuso, nel colore di sotto
    cmp #ROT_LINE_ROW
    bne green
    lda sv_c,x
    cmp #CH_LINE_L
    bne green
    jsr rs_fuse
    sta (ptr),y
done:
    rts
green:
    lda v_n
    sta (ptr),y
    lda #COL_GREEN
    sta (ptr2),y
    rts
restore:
    lda sv_c,x
    sta (ptr),y
    lda sv_k,x
    sta (ptr2),y
    rts
.endproc

; Il colpo X ha solo cambiato riga (sv_la invece di sd_y: al più RS_STEP pixel, quindi al più una
; riga di celle più su o più giù; stessa colonna, nessun altro fascio vicino): i due fasci insieme,
; riga di celle per riga di celle (al più tre da rs_row). Le celle lasciate tornano com'erano, le
; nuove si salvano e diventano verdi, in tutte quelle di adesso va il carattere del tratto (sulla
; mezzeria quello fuso). X resta.
.proc rs_move
    stx rs_k
    lda sd_y,x                  ; righe di celle di prima: quella in alto e, se il tratto non
    and #6                      ; comincia in cima alla cella, quella sotto (%01 o %11)
    cmp #1
    lda #0
    rol a
    sec
    rol a
    sta rs_o
    lda sv_la,x                 ; e di adesso
    tay
    and #6
    sta rs_f
    cmp #1
    lda #0
    rol a
    sec
    rol a
    sta rs_nw
    tya                         ; riga di caratteri della cella in alto di adesso (-1..24)
    cmp #$F0
    bcc :+
    lda #$FF
    bne :++
:   lsr a
    lsr a
    lsr a
:   sta rs_tr
    sta rs_row
    tya
    eor sd_y,x
    and #$F8
    beq placed                  ; stessa riga di celle
    tya
    sec
    sbc sd_y,x
    bmi up
    asl rs_nw                   ; in giù: la prima è quella di prima, una sopra
    dec rs_row
    .byte $2c                   ; (bit: salta l'asl)
up: asl rs_o                    ; in su: quelle di prima una sotto
    .assert rs_o < $100, error, "rs_move: asl di pagina zero, due byte"
placed:
    ldy rs_row                  ; via le righe fuori dallo schermo
    bmi clip_top
    cpy #23
    bcc clipped
    lda #%011
    cpy #24
    bcc clip
    lda #%001
    bne clip                    ; (sempre)
clip_top:
    lda #%110
clip:
    tay
    and rs_o
    sta rs_o
    tya
    and rs_nw
    sta rs_nw
clipped:
    lda sv_la,x
    sta sd_y,x
    txa
    asl a
    asl a
    sta rs_slot
    ; caratteri del tratto dei due fasci (posizione nella cella * 8 + riga): cella in alto, sotto
    lda sd_cw,x
    sta rs_c
    lsr a
    and #3
    asl a
    asl a
    asl a
    ora rs_f
    tay
    lda shot_chars,y
    sta rs_c0
    lda shot_chars+1,y
    sta rs_l0
    lda rs_c
    clc
    adc #ROT_SHOT_D
    lsr a
    and #3
    asl a
    asl a
    asl a
    ora rs_f
    tay
    lda shot_chars,y
    sta rs_c1
    lda shot_chars+1,y
    sta rs_l1
    ; puntatori della riga rs_row (quella sopra lo schermo: 40 celle prima), fascio sinistro
    lda rs_c
    lsr a
    lsr a
    lsr a
    ldy rs_row
    bmi above
    clc
    adc row_lo,y
    sta ptr
    lda row_hi,y
    bne high                    ; (sempre)
above:
    clc
    adc #<(SCREEN - 40)
    sta ptr
    lda #>(SCREEN - 40)
high:
    adc #0
    sta ptr+1
    lda rs_c                    ; e destro: (c & 7 + ROT_SHOT_D) / 8 celle più in là
    and #7
    clc
    adc #ROT_SHOT_D
    lsr a
    lsr a
    lsr a
    clc
    adc ptr
    sta ptr3
    sta ptr4
    lda ptr+1
    adc #0
    sta ptr3+1
    adc #>($d800 - SCREEN)
    sta ptr4+1
    lda ptr
    sta ptr2
    lda ptr+1
    adc #>($d800 - SCREEN)      ; (C = 0)
    sta ptr2+1
    ldy #0
row:
    lda rs_row                  ; posto delle celle della riga (il fascio destro due più in là)
    and #1
    ora rs_slot
    tax
    lsr rs_nw
    bcs now
    lsr rs_o
    bcc next
    lda sv_c,x                  ; lasciata: com'era
    sta (ptr),y
    lda sv_k,x
    sta (ptr2),y
    lda sv_c+2,x
    sta (ptr3),y
    lda sv_k+2,x
    sta (ptr4),y
    bcs next                    ; (sempre)
now:
    lsr rs_o
    bcs chars                   ; c'era già: cambia solo il carattere
    lda (ptr),y                 ; nuova: salva carattere e colore, poi verde
    sta sv_c,x
    lda (ptr2),y
    sta sv_k,x
    lda (ptr3),y
    sta sv_c+2,x
    lda (ptr4),y
    sta sv_k+2,x
    lda #COL_GREEN
    sta (ptr2),y
    sta (ptr4),y
chars:
    lda rs_row
    cmp #ROT_LINE_ROW
    beq line
    lda rs_c0
    sta (ptr),y
    lda rs_c1
    sta (ptr3),y
lower:
    lda rs_l0                   ; la prossima cella di adesso è quella sotto
    sta rs_c0
    lda rs_l1
    sta rs_c1
next:
    inc rs_row
    lda rs_o
    ora rs_nw
    beq done
    tya
    clc
    adc #40
    tay
    bne row                     ; (sempre)
done:
    ldx rs_k
    rts
line:
    ; sulla mezzeria: dove sotto c'è la rete il carattere fuso, nel colore di sotto
    lda rs_c0
    jsr fuse
    sta (ptr),y
    bcc :+
    lda sv_k,x
    sta (ptr2),y
:   inx
    inx
    lda rs_c1
    jsr fuse
    sta (ptr3),y
    bcc lower
    lda sv_k,x
    sta (ptr4),y
    bcs lower                   ; (sempre)
; A = carattere del tratto, X = posto: A = il carattere da scrivere, C = 1 se è quello fuso
fuse:
    sta v_n
    lda sv_c,x
    cmp #CH_LINE_L
    bne :+
    jsr rs_fuse
    sec
    rts
:   lda v_n
    clc
    rts
.endproc

; A = carattere sotto una cella nuova: se è di un fascio (o fuso), sovrapposizione (sv_n bit 7: al
; frame dopo da capo). A, X e Y restano. Sotto lo stack (STKCODE, come i puntatori dei fasci di
; oggi), copiata da title_unpack.
.segment "STKCODE"
.proc rs_over
    cmp #SH_LO
    bcc ok
    cmp #SH_HI
    bcc hit
    cmp #SH2_LO
    bcc ok
    cmp #SH2_HI
    bcs ok
hit:
    pha
    lda #$80
    ora sv_n
    sta sv_n
    pla
ok: rts
.endproc
.segment "CODE"

; Carattere fuso del posto X: il glifo della mezzeria (NET_CH) con il tratto v_n sopra. A = il
; carattere; X e Y restano. In fondo alla RAM bassa (FZCODE, come bd_fuse di oggi).
.segment "FZCODE"
.proc rs_fuse
    txa
    pha
    asl a
    asl a
    asl a
    tax                         ; posto * 8
    lda v_n
    sta rs_r                    ; (puntatore al glifo del tratto in fz_g)
    lda #0
    sta fz_g+1
    lda rs_r
    asl a
    rol fz_g+1
    asl a
    rol fz_g+1
    asl a
    rol fz_g+1
    sta fz_g
    lda fz_g+1
    clc
    adc #>CHARSET
    sta fz_g+1
    tya
    pha
    ldy #0
:   lda NET_CH,y
    ora (fz_g),y
    sta CHARSET + 8 * SHOT_P0,x
    inx
    iny
    cpy #8
    bne :-
    pla
    tay
    pla
    tax
    clc
    adc #SHOT_P0
    rts
.endproc
.segment "CODE"
.assert <CHARSET = 0 .and SHOT_PN = 8 * MAX_SHOTS, error, "colpi: un carattere fuso per cella di fascio"

; Toglie i colpi disegnati (dall'ultimo: con due fasci sovrapposti il carattere salvato da uno è
; quello dell'altro). X resta.
.proc shots_erase
    lda sv_n
    beq done
    txa
    pha
    ldx #2 * MAX_SHOTS - 1
:   lda sd_cw,x
    cmp #$FF
    beq :+
    jsr erase_shot
:   dex
    bpl :--
    lda #0
    sta sv_n
    pla
    tax
done:
    rts
.endproc

; (campo girato: i fasci non arrivano mai nella fascia dell'HUD)
.proc shots_off_hud
    rts
.endproc

; Nel conto alla rovescia di NEXT: i glifi delle posizioni 0-2 nei caratteri presi in prestito
; (da SHOT_B0, 7 per posizione), dal tratto dei caratteri del set (posizione 3, pixel 6-7)
; spostato a sinistra di 2 pixel per posizione.
.proc shot_glyphs
    lda #SG_GLYPHS
    sta sg_on
    ldx #0
    ldy #0                      ; byte del glifo della posizione 3
pos:
    lda CHARSET + 8 * SHOT_OWN,y
    sta m_lo
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    sta SG_DST,x                ; posizione 0: pixel 0-1
    lda m_lo
    asl a
    asl a
    asl a
    asl a
    sta SG_DST + 8 * 7,x        ; 1: pixel 2-3
    lda m_lo
    asl a
    asl a
    sta SG_DST + 8 * 14,x       ; 2: pixel 4-5
    inx
    iny
    cpy #8 * 7
    bne pos
    rts
.endproc
.assert SHOT_BN = 3 * 7, error, "shot_glyphs: tre posizioni prese (0-2)"

