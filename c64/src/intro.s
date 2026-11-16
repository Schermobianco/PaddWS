; Presentazione dell'avversario di CHALLENGE animata, come rust/game/src/challenge_ui.rs (Intro e
; Stage), a celle e sprite: in cima la scala dei sette livelli (trattini che compaiono uno ogni
; due frame: battuti bianchi, quello di adesso giallo che lampeggia, gli altri grigi), sotto il
; livello; poi l'avversario entra a modo suo, con la sua racchetta (sprite, a grandezza reale e
; rivolta al giocatore), e porta nome, motto, bonus e punti da fare.
;
; Il codice sta nella cartuccia: la parte comune (segmento INCODE, quattro pagine) gira nel secondo
; schermo (le mosse speciali le ricopia intro_scene alla fine), l'entrata dell'avversario (segmenti
; INV0-INV6 per tipo di racchetta K_*, due pagine ciascuno, nel .prg da INV_IMG) sulle tabelle dei
; quadrati, che nella presentazione non servono: enter_intro le dà per pronte (math_step non le
; tocca), in_tick le fa rifare a IN_DONE, quando l'entrata è finita, e intro_scene prima se si
; salta o entra uno sfidante; la partita aspetta che siano pronte. Le copia enter_intro insieme al
; file voce (un caricamento). Ogni entrata comincia con un salto alla sua parte di ogni frame (inv_tick) e con
; quella del disegno (inv_init).
;
; Il nome è la grafica dell'avversario (assets/titles) in caratteri hires: i caratteri (TN_FIRST, una
; pagina di titles.bin) li copia in_draw sullo schermo appena pulito, la mappa e i colori stanno
; all'inizio dell'entrata (TN_HDR). Le entrate muovono il nome a blocchi di celle: tutto, oppure
; una colonna di celle alla volta al posto delle lettere (BLASTER, GUARDIAN).
;
; Semplificazioni rispetto al PC: tutto a celle (il motto nel font di sempre), le racchette non
; si inclinano (le immagini si rifanno solo prima della voce, che tiene acceso l'I/O), la polvere e
; le capsule colpite al volo non ci sono, il TITAN esce dal pavimento invece di allungarsi.
;
; Tempi in frame a 50 Hz dall'inizio della presentazione (quelli del PC sono a 60); le x degli
; sprite in unità di 2 pixel dal centro verso la metà campo dell'avversario.
IN_RUN    = SCREEN2
INV_RUN   = square1_lo
IN_IMG    = $EE00
INV_IMG   = $F200               ; poi due pagine per tipo (K_*), fino a $FFFF
IN_DONE   = 180                 ; frame dopo l'ultima cosa delle entrate: le tabelle da rifare
IN_LAST   = 127                 ; ultimo frame delle entrate (in_f con il segno giusto)
IN_BANK   = PRG_BANK + (IN_IMG - $0800) / $4000
IN_SRC    = $80 + ((IN_IMG - $0800) .mod $4000) / 256
INV_SRC   = $80 + ((INV_IMG - $0800) .mod $4000) / 256
.assert (INV_IMG + 7 * $200 - $0800 - 1) / $4000 = (IN_IMG - $0800) / $4000, error, "presentazione su due banchi"
.import __INCODE_LOAD__, __INCODE_RUN__, __INCODE_SIZE__
.assert __INCODE_LOAD__ = IN_IMG .and __INCODE_RUN__ = IN_RUN .and __INCODE_SIZE__ <= $400, lderror, "presentazione: parte comune fuori posto o oltre il secondo schermo"
inv_tick = INV_RUN
inv_init = INV_RUN + 3

IN_LADDER = 1                   ; righe: la scala, il livello
IN_LEVEL  = 3
IN_PADY   = SPR_Y0 + 62         ; y degli sprite del centro della racchetta
IN_TAG    = 15                  ; motto (il nome nelle righe 10-14, TN_*_ROW), capsule (2 righe)
IN_CAP    = 17                  ; e i loro nomi, punti da fare, punteggio
IN_FIRST  = 21
IN_SCORE  = 23
IN_CX     = SPR_X0 + 160        ; x degli sprite del centro dello schermo
IN_CAPC   = 9                   ; prima colonna della prima capsula, poi una ogni 10
IN_CAPY   = SPR_Y0 + IN_CAP * 8 + 8
; il nome dell'avversario (gen/assets.inc), all'inizio dell'entrata: larghezza e altezza in celle,
; prima colonna, celle, poi i codici dei caratteri (0: cella vuota) e i colori, riga per riga
TN_HDR    = INV_RUN + 6
tn_w      = TN_HDR
tn_h      = TN_HDR + 1
tn_col    = TN_HDR + 2
tn_n      = TN_HDR + 3
tn_map    = TN_HDR + 4
.macro inv_title w, h, col, map, clr
    .assert * = TN_HDR, error, "entrata: il nome non dove lo cerca in_name"
    .byte w, h, col, w * h
    .byte map
    .byte clr
.endmacro

.segment "INCODE"
; variabili della presentazione (si ricopiano con il codice)
in_f:    .byte 0                ; frame dall'inizio
in_k:    .byte 0                ; tipo dell'avversario (K_*)
in_opp:  .byte 0                ; lato dell'avversario: 0 sinistra, 1 destra
in_n:    .byte 0                ; righe dell'immagine della racchetta
in_dx:   .byte 0                ; temporanee
in_y:    .byte 0
in_t:    .byte 0
in_hi:   .byte 0
in_tagn: .byte 0                ; lettere del motto a schermo
in_inval: .byte 0               ; 1: tabelle dei quadrati già da rifare (in_tick, o il via)
in_mode: .byte 0                ; IM_* (intro_hud)
in_c:    .byte 0                ; nome: colonna di celle, cella, riga (in_col)
in_i:    .byte 0
in_r:    .byte 0

; Disegno (ch_draw), sullo schermo pulito: i caratteri del nome dalla cartuccia (prima della voce,
; come le copie), punteggio, record e duelli vinti (intro_hud, non nell'allenamento), l'immagine
; della racchetta dell'avversario (prima della voce: dopo l'I/O resta acceso), poi l'entrata.
.proc in_draw
    ldx ch_level
    lda rung_kind,x
    sta in_k
    .assert TTL_NAMES = 0, error, "in_draw: la pagina del nome è il tipo"
    jsr title_copy
    lda ch_side                 ; l'avversario dall'altra parte di chi gioca
    eor #4
    lsr a
    lsr a
    sta in_opp
    jsr intro_hud
    sta in_mode
    ; l'immagine della racchetta, dritta (BLASTER con il caricatore pieno)
    ldx in_k
    stx pi_kind
    lda pv_rows,x
    sta pi_n
    sta in_n
    lda #3                      ; TWIST dritta
    cpx #K_TWIST
    beq :+
    lda pv_var,x
:   sta pi_var
    cpx #K_BLASTER
    bne :+
    lda #P_BLASTER_SHOTS
    jsr mag_setup
:   lda in_opp
    sta pi_side
    jsr pad_image
    ldy in_opp
    lda #1
    sta pd_dirty,y
    lda #$ff                    ; in partita l'immagine si rifà
    sta pd_n,y
    jmp inv_init
.endproc
.assert INV_RUN = $F000, error, "entrate della presentazione: le tabelle dei quadrati altrove"

; Un frame (intro_scene, dopo il disegno): la scala, il livello, l'entrata.
.proc in_tick
    ldx ch_elapsed              ; (fino a 255)
done_op:
    cpx #IN_DONE + 2            ; (OMEGA, più lunga, cambia i due limiti: inv_omega)
    jcs tables
    cpx #2                      ; il primo frame dopo il disegno no: il file voce del primo livello
    jcc out                     ; ci copia GO, circa 14.000 cicli
last_op:
    cpx #IN_LAST + 3            ; l'entrata si ferma al frame IN_LAST (in_f con il segno giusto):
                                ; motto, capsule e FIRST TO di ogni avversario arrivano prima
    jcs out
    dex
    dex
    stx in_f
    txa
    lsr a                       ; il trattino f / 2, ai frame pari
    bcs blink
    cmp #CH_LEVELS
    bcs blink
    tax
    jsr rung
blink:
    lda in_f                    ; poi quello del livello lampeggia
    cmp #2 * CH_LEVELS
    bcc level
    ldx ch_level
    jsr rung
level:
    lda in_f
    cmp #12
    bcc go
    bne final
    lda in_mode                 ; LEVEL n OF 7, FINAL LEVEL o TRAINING
    beq :++
    lsr a
    bcc :+
    jsr print_at
    .byte 14, IN_LEVEL, "FINAL LEVEL", 0
    jmp yellow
:   jsr print_at
    .byte 16, IN_LEVEL, "TRAINING", 0
    jmp yellow
:   jsr print_at
    .byte 14, IN_LEVEL, "LEVEL   OF 7", 0
    lda ch_level
    clc
    adc #'1'
    ldx #20
    ldy #IN_LEVEL
    sty v_row
    jsr put_ascii
yellow:
    lda #COL_YELLOW
    bne color
final:
    ldx in_mode                 ; FINAL LEVEL lampeggia
    dex                         ; (IM_FINAL)
    bne go
    lda in_f
    and #7
    bne go
    lda in_f
    and #8
    beq yellow
    lda #COL_BLACK
color:
    ldy #IN_LEVEL
    jsr color_row
go:
    jmp inv_tick
tables:
    lda in_inval                ; l'entrata finita: le tabelle dei quadrati di nuovo da fare, una
    bne out                     ; volta (math_step le rifà sopra l'entrata, che non gira più)
    inc in_inval
    jmp math_invalidate
out:
    rts
; trattino X della scala: due celle piene ogni cinque colonne
rung:
    stx in_t
    txa
    asl a
    asl a
    adc in_t
    adc #4
    tay
    lda #CH_SOLID
    sta SCREEN + IN_LADDER * 40,y
    sta SCREEN + IN_LADDER * 40 + 1,y
    cpx ch_level
    bcc beaten
    bne gray
    lda in_f                    ; quello di adesso: giallo e grigio, 8 frame ciascuno
    and #8
    bne gray
    lda egg_yel
    bne set
beaten:
    lda in_mode                 ; (nell'allenamento nessuno battuto)
    cmp #IM_TRAIN
    beq gray
    lda #COL_WHITE
    bne set
gray:
    lda #COL_DGRAY
set:
    sta $d800 + IN_LADDER * 40,y
    sta $d800 + IN_LADDER * 40 + 1,y
    rts
.endproc

; Le righe del nome da Y vuote, poi il nome come in_name_nc (X = 0: solo le righe vuote).
.proc in_name
    sta in_dx
    stx in_t
    sty in_y
    lda tn_h
    sta v_n
    lda #40
    ldx #0
    jsr blank_box
draw:
    lda in_t
    beq done
    ldx #0
:   stx in_c
    jsr in_col
    ldx in_c
    inx
    cpx tn_w
    bne :-
done:
    rts
.endproc

; Il nome dell'avversario dalla riga Y, spostato di A colonne (con il segno), del colore X
; (COL_WHITE: i suoi colori), sopra quello che c'è: le sue celle vuote lasciano quello che c'era.
.proc in_name_nc
    sta in_dx
    stx in_t
    sty in_y
    jmp in_name::draw
.endproc

; La colonna di celle X del nome dalla riga Y, al suo posto, del colore A (COL_WHITE: i suoi; altri
; già con l'easter egg; 0: le celle della colonna vuote).
.proc in_letter
    sta in_t
    sty in_y
    lda #0
    sta in_dx
.endproc
; (prosegue)
; La colonna di celle X del nome dalla riga in_y, spostata di in_dx colonne, del colore in_t (come
; in_letter); le celle vuote del nome restano come sono, salvo con il colore 0.
.proc in_col
    stx in_i
    txa
    clc
    adc tn_col
    adc in_dx
    sta in_hi                   ; colonna sullo schermo
    lda in_y
    sta in_r
cell:
    ldy in_r
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    ldx in_i
    lda in_t
    beq put                     ; (A = CH_BLANK)
    lda tn_map,x
    beq next
put:
    ldy in_hi
    sta (ptr),y
    lda in_t
    beq next
    cmp #COL_WHITE
    bne color
    txa                         ; i suoi colori: dopo i codici
    clc
    adc tn_n
    tax
    lda tn_map,x
    jsr egg_color
color:
    pha
    lda ptr+1
    clc
    adc #>($d800 - SCREEN)
    sta ptr+1
    pla
    sta (ptr),y
next:
    inc in_r
    lda in_i
    clc
    adc tn_w
    sta in_i
    cmp tn_n
    bcc cell
    rts
.endproc
.assert CH_BLANK = 0, error, "in_col: la cella vuota è il carattere 0"

; Il motto scritto una lettera ogni X frame dal frame A, grigio.
.proc in_tag_at
    stx in_t
    eor #$ff
    sec
    adc in_f
    bcc done
    ldy #0
:   iny
    sec
    sbc in_t
    bcs :-
    tya
    cmp #17
    bcc :+
    lda #16
:   cmp in_tagn                 ; solo quando cresce
    beq done
    sta in_tagn
    sta in_t
    lda in_k
    asl a
    tay
    lda kind_tags,y
    sta ptr2
    lda kind_tags+1,y
    sta ptr2+1
    lda #IN_TAG
    sta v_row
    ldy #0
:   cpy in_t
    beq :+
    sty v_n
    tya
    clc
    adc #12
    tax
    lda (ptr2),y
    jsr put_ascii
    ldy v_n
    iny
    bne :-
:   lda #COL_GRAY
    ldy #IN_TAG
    jmp color_row
done:
    rts
.endproc

; Le tre capsule al loro posto con il nome sotto, gialle: la X-esima al frame A + X * Y.
.proc in_caps_at
    sta in_t
    sty in_dx
    ldx #0
:   lda in_t
    cmp in_f
    beq cap
    clc
    adc in_dx
    sta in_t
    inx
    cpx #3
    bne :-
    rts
cap:
    stx in_t
    lda ch_level
    asl a
    adc ch_level
    adc in_t
    tay
    lda rung_loadout,y
    sta in_dx
    asl a
    asl a
    asl a
    tay                         ; capsula normale: bonus * 8
    lda in_t
    asl a
    asl a
    adc in_t
    asl a                       ; X * 10
    adc #IN_CAPC
    sta in_y
    tax
    lda #IN_CAP
    sta v_row
    jsr put_cap
    lda in_dx
    asl a
    tay
    lda bonus_names,y
    sta ptr2
    lda bonus_names+1,y
    sta ptr2+1
    ldy #0                      ; nome centrato sotto: lunghezza fino allo spazio (o allo 0)
:   lda (ptr2),y
    beq :+
    cmp #' '
    beq :+
    iny
    bne :-
:   tya
    lsr a
    eor #$ff
    sec
    adc in_y
    tax
    inx
    ldy #IN_CAP + 2
    jsr print_str
    ldx #IN_CAP + 2
:   stx in_t
    lda #10
    sta v_n
    lda in_y
    sec
    sbc #4
    tay
    lda #COL_YELLOW
    jsr color_span
    ldx in_t
    dex
    cpx #IN_CAP - 1
    bne :-
    rts
.endproc

; FIRST TO n al frame A.
.proc in_first
    cmp in_f
    bne done
    jsr print_at
    .byte 15, IN_FIRST, "FIRST TO", 0
    ldx ch_level
    lda rung_points,x
    cmp #10
    bcc :+
    ldx #24
    ldy #IN_FIRST
    jsr print_num2
    jmp :++
:   adc #'0'
    ldx #24
    ldy #IN_FIRST
    sty v_row
    jsr put_ascii
:   lda #COL_GRAY
    ldy #IN_FIRST
    jmp color_row
done:
    rts
.endproc

; La racchetta dell'avversario accesa: A unità dal centro, centro alla y degli sprite Y, colore X.
.proc in_pad
    sta in_dx
    stx in_t
    tya
    sec
    sbc in_n                    ; l'immagine dall'alto, a righe doppie
    ldy in_opp
    sta sh_y+SPN_PAD,y
    lda in_t
    sta sh_col+SPN_PAD,y
    lda #SP_PAD0
    clc
    adc in_opp
    sta sh_ptr+SPN_PAD,y
    lda bit_of+SPN_PAD,y
    tax
    ora sh_enable
    sta sh_enable
    txa
    ora sh_mc
    sta sh_mc
    txa
    ora sh_yexp
    sta sh_yexp
    tya
    clc
    adc #SPN_PAD
    tax
    lda in_dx
    ldy #12
.endproc
; (prosegue)
; Sprite X a A unità (2 pixel, con il segno) dal centro verso la metà campo dell'avversario, con il
; centro dell'immagine Y pixel dal suo bordo sinistro. X resta.
.proc in_x
    sty in_t
    ldy #0
    cmp #$80
    bcc :+
    dey
:   sty in_hi
    asl a
    rol in_hi
    ldy in_opp
    bne add
    eor #$ff                    ; avversario a sinistra: verso di lui le x calano
    clc
    adc #1
    pha
    lda in_hi
    eor #$ff
    adc #0
    sta in_hi
    pla
add:
    clc
    adc #<IN_CX
    pha
    lda in_hi
    adc #>IN_CX
    sta in_hi
    pla
    sec
    sbc in_t
    sta sh_x,x
    lda in_hi
    sbc #0
    lsr a                       ; C = bit 8 della x
    lda bit_of,x
    eor #$ff
    and sh_msb
    bcc :+
    ora bit_of,x
:   sta sh_msb
    rts
.endproc

; La palla (sprite 0, 6 pixel, bianca) a A unità dal centro, alla y degli sprite Y.
.proc in_ball
    pha
    sty sh_y
    ldx #0
    lda #SP_BALL6
    ldy #COL_WHITE
    jsr in_small
    pla
    ldy #3
    jmp in_x
.endproc

; Sprite X acceso con l'immagine A del colore Y, a pixel singoli e non espanso. X resta.
.proc in_small
    sta sh_ptr,x
    tya
    sta sh_col,x
    lda bit_of,x
    ora sh_enable
    sta sh_enable
    lda bit_of,x
    eor #$ff
    tay
    and sh_mc
    sta sh_mc
    tya
    and sh_xexp
    sta sh_xexp
    tya
    and sh_yexp
    sta sh_yexp
    rts
.endproc

; Sprite X spento. X resta.
.proc in_off
    lda bit_of,x
    eor #$ff
    and sh_enable
    sta sh_enable
    rts
.endproc

; Scossa: scroll fine del testo A (x, di solito 0) e Y (y, di solito 3) in questo frame
; (apply_shadows rimette la y; ch_screen la x).
.proc in_scroll
    ora #$c8
    sta $d016
    tya
    ora #$18
    sta $d011
    rts
.endproc

; ------------------------------------------------------------------------------------ ARCADE
; Più bonus: una raffica di capsule parte dalla parte del giocatore e la racchetta le prende tutte
; andandole incontro, contandole e lampeggiando gialla; il nome lampeggia come INSERT COIN, poi
; motto, capsule, punti.
.segment "INV0"
.scope inv_arcade
    jmp tick
    rts
    .res 2
    inv_title TN_0_W, TN_0_H, TN_0_COL, {TN_0_MAP}, {TN_0_CLR}
ARC_N = 10
caught: .byte 0
flash:  .byte 0
found:  .byte 0
target: .byte 0
py:     .byte 0                 ; la racchetta dal centro (pixel, con il segno)
k:      .byte 0
s:      .byte 0
t:      .byte 0
arc_dy:  .byte <-12, 8, <-3, 13, <-15, 2, 10, <-8, 5, <-2
arc_cap: .byte 0, 1, 2, 0, 1, 2, 0, 1, 2, 0
tick:
    lda #0
    sta caught
    sta flash
    sta found
    sta target
    ldx #0
cap:
    ; la capsula k parte al frame 8 + 5k, 45 unità di qua dal centro, 5 a frame: presa dopo 9
    stx k
    txa
    asl a
    asl a
    adc k
    adc #8
    sta s
    lda in_f
    sec
    sbc s
    bcc next
    cmp #9
    bcc fly
    inc caught
    cmp #11
    bcs :+
    inc flash
:   cmp #9
    bne next
    jsr spr                     ; presa: via
    jsr in_off
    jmp next
fly:
    sta t
    ldy k
    lda found
    bne :+
    inc found
    lda arc_dy,y
    sta target
:   lda ch_level
    asl a
    adc ch_level
    adc arc_cap,y
    tay
    lda rung_loadout,y
    clc
    adc #SP_CAP0
    pha
    jsr spr
    pla
    ldy egg_yel
    jsr in_small
    ldy k
    lda #IN_PADY - 3
    clc
    adc arc_dy,y
    sta sh_y,x
    lda t
    asl a
    asl a
    adc t
    sec
    sbc #45
    ldy #6
    jsr in_x
next:
    ldx k
    inx
    cpx #ARC_N
    jne cap
    ; la racchetta va incontro alla capsula che arriva, poi torna al centro
    jsr chase
    jsr chase
    jsr chase
    lda #IN_PADY
    clc
    adc py
    tay
    ldx #COL_WHITE
    lda flash
    beq :+
    ldx egg_yel
:   lda #0
    jsr in_pad
    ; +n accanto alla racchetta fino al frame 80
    ldx #14
    lda in_opp
    beq :+
    ldx #23
:   stx s
    lda in_f
    cmp #80
    bcs erase
    lda caught
    beq name
    lda #7
    sta v_row
    ldx s
    lda #'+'
    jsr put_ascii
    lda caught
    cmp #10
    bcc :+
    ldx s
    inx
    ldy #7
    jsr print_num2
    jmp yellow
:   adc #'0'
    ldx s
    inx
    jsr put_ascii
yellow:
    lda #3
    sta v_n
    ldy s
    ldx #7
    lda #COL_YELLOW
    jsr color_span
    jmp name
erase:
    bne name
    lda #1
    sta v_n
    lda #3
    ldx s
    ldy #7
    jsr blank_box
name:
    ; il nome dal frame 70: lampeggia (3 frame acceso, 3 spento) fino al 90
    lda in_f
    sec
    sbc #70
    bcc tag
    cmp #20
    bcc :+
    bne tag
    ldx #COL_WHITE
    bne draw
:   cmp #6
    bcc :+
    sbc #6
    bcs :-
:   ldx #COL_WHITE
    cmp #3
    bcc draw
    ldx #0
draw:
    lda #0
    ldy #TN_0_ROW
    jsr in_name
tag:
    lda #83
    ldx #1
    jsr in_tag_at
    lda #100
    ldy #7
    jsr in_caps_at
    lda #125                    ; (tutto entro IN_LAST: dopo l'entrata non c'è più)
    jmp in_first
spr:
    lda k                       ; sprite della capsula k: 5 o 6
    and #1
    clc
    adc #5
    tax
    rts
chase:
    lda py
    sec
    sbc target
    beq :++
    bmi :+
    dec py
    rts
:   inc py
:   rts
.endscope

; ------------------------------------------------------------------------------------ TITAN
; Alto ma lento: esce dal pavimento a scatti che fanno tremare lo schermo (sprite dietro una
; fascia di celle piene nere, la priorità del VIC), si accende gialla; il nome fra le sue travi,
; il motto piano, le capsule per ultime.
.segment "INV1"
.scope inv_titan
    jmp tick
    jmp init
    inv_title TN_1_W, TN_1_H, TN_1_COL, {TN_1_MAP}, {TN_1_CLR}
step:  .byte 0
row0:  .byte 0
t:     .byte 0
floor: .byte 0
init:
    ; il pavimento: la prima riga di caratteri sotto la racchetta intera, poi 5 di celle nere
    lda in_n
    clc
    adc #62 + 7
    lsr a
    lsr a
    lsr a
    sta row0
    tay
    ldx #6
:   lda #CH_SOLID
    cpx #6
    bne :+
    lda #CH_GRID_T
:   jsr mask
    iny
    dex
    bne :--
    lda in_opp                  ; la racchetta dietro le celle
    tay
    lda bit_of+SPN_PAD,y
    sta $d01b
    rts
; celle 17-22 della riga Y del carattere A: la prima riga grigia (la terra), le altre nere
mask:
    stx t
    sty floor
    pha
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    pla
    pha
    ldy #17
:   sta (ptr),y
    iny
    cpy #23
    bne :-
    lda ptr+1
    clc
    adc #>($d800 - SCREEN)
    sta ptr+1
    lda #COL_BLACK
    cpx #6
    bne :+
    lda #COL_GRAY
:   ldy #17
:   sta (ptr),y
    iny
    cpy #23
    bne :-
    pla
    ldx t
    ldy floor
    rts
tick:
    ; scatto (f - 5) / 3 + 1, al più 20: salita in_n * scatto / 10 pixel
    lda in_f
    sec
    sbc #5
    jcc name
    cmp #66 - 5
    bcs done
    ldx #0
:   inx
    sec
    sbc #3
    bcs :-
    cpx #21
    bcc :+
    ldx #20
:   cpx step
    beq :+
    stx step
    txa
    and #3
    bne :+
    lda #0                      ; un colpo sordo ogni quattro scatti
    ldy #5
    jsr in_scroll
:   lda #0
    sta t
    ldy step
:   clc
    adc in_n
    bcc :+
    inc t
:   dey
    bne :--
    ldy #0
:   sec                         ; / 10
    sbc #10
    pha
    lda t
    sbc #0
    sta t
    pla
    bcc :+
    iny
    bne :-
:   sty floor
    lda #IN_PADY
    clc
    adc in_n
    adc in_n
    sec
    sbc floor
    tay
    ldx #COL_WHITE
    lda in_f
    cmp #62
    bcc :+
    ldx egg_yel                 ; intera: gialla per un attimo
:   lda #0
    jmp in_pad
done:
    bne name
    ; finita: via la fascia (e la priorità), la racchetta bianca
    lda #0
    sta $d01b
    lda #6
    sta v_n
    lda #6
    ldx #17
    ldy row0
    jsr blank_box
    lda #0
    ldx #COL_WHITE
    ldy #IN_PADY
    jsr in_pad
name:
    ; il nome, a racchetta ferma (sotto c'era la fascia)
    lda in_f
    cmp #70
    bne tag
    lda #0
    ldx #COL_WHITE
    ldy #TN_1_ROW
    jsr in_name
tag:
    lda #95
    ldx #2
    jsr in_tag_at
    lda #104
    ldy #8
    jsr in_caps_at
    lda #IN_LAST
    jmp in_first
.endscope

; ------------------------------------------------------------------------------------ HAMMER
; Colpi potenti: la palla arriva piano, il martello carica e la ribatte fortissimo (con la scia),
; lo schermo trema; il nome cade come un peso e lo fa tremare di nuovo, le capsule arrivano.
.segment "INV2"
.scope inv_hammer
    jmp tick
    rts
    .res 2
    inv_title TN_2_W, TN_2_H, TN_2_COL, {TN_2_MAP}, {TN_2_CLR}
d:    .byte 0
prev: .byte 0
hx:   .byte 5, 1, 5, 1, 5, 2, 4, 3   ; scossa del colpo (scroll fine, 3 al centro)
hy:   .byte 3, 5, 1, 4, 2, 3, 3, 3
ly:   .byte 5, 1, 5, 2, 4, 3         ; dell'atterraggio del nome
R = TN_2_ROW
fall: .byte R - 6, R - 5, R - 4, R - 3, R - 2, R - 1, R - 1, R, R
gh:   .byte 3, 6, 10                ; la scia: unità dietro la palla
tick:
    ; la racchetta: indietro (33-40), poi il colpo in avanti (41-45)
    lda in_f
    cmp #33
    bcc zero
    cmp #41
    bcs fwd
    sec
    sbc #32
    lsr a
    jmp pad
fwd:
    cmp #46
    bcs zero
    sbc #45                     ; (C = 1)
    jmp pad
zero:
    lda #0
pad:
    ldx #COL_WHITE
    ldy #IN_PADY
    jsr in_pad
    ; la palla: piano fino al colpo (frame 41), poi fortissimo con la scia grigia
    lda in_f
    cmp #10
    bcc shake
    cmp #41
    bcs fly
    eor #$ff
    sec
    adc #41
    sta d
    lsr a
    adc d
    adc #4
    eor #$ff
    clc
    adc #1
    ldy #IN_PADY - 3
    jsr in_ball
    jmp shake
fly:
    sbc #41                     ; (C = 1)
    cmp #9
    bcs gone
    asl a
    asl a
    asl a
    adc #4
    sta d
    eor #$ff
    clc
    adc #1
    ldy #IN_PADY - 3
    jsr in_ball
    ldx #5
ghost:
    lda #SP_BALL6
    ldy #COL_MGRAY
    jsr in_small
    lda #IN_PADY - 3
    sta sh_y,x
    lda d
    sec
    sbc gh - 5,x
    eor #$ff
    clc
    adc #1
    ldy #3
    jsr in_x
    inx
    cpx #8
    bne ghost
    beq shake
gone:
    bne shake
    ldx #0
    jsr in_off
    ldx #5
    jsr in_off
    inx
    jsr in_off
    inx
    jsr in_off
shake:
    lda in_f
    sec
    sbc #41
    bcc name
    cmp #9
    bcs land
    tax
    lda #0
    ldy #3
    cpx #8
    beq :+
    lda hx,x
    ldy hy,x
:   jsr in_scroll
    jmp name
land:
    sbc #60 - 41                ; (C = 1)
    bcc name
    cmp #6
    bcs name
    tax
    ldy ly,x
    lda #0
    jsr in_scroll
name:
    ; il nome cade da sei righe più su alla sua (52-60)
    lda in_f
    sec
    sbc #52
    bcc tag
    cmp #9
    bcs tag
    tax
    lda fall,x
    cmp prev
    beq tag
    pha
    ldy prev
    beq :+
    lda #0
    tax
    jsr in_name
:   pla
    sta prev
    tay
    lda #0
    ldx #COL_WHITE
    jsr in_name
tag:
    lda #73
    ldx #1
    jsr in_tag_at
    lda #88
    ldy #8
    jsr in_caps_at
    lda #125
    jmp in_first
.endscope

; ------------------------------------------------------------------------------------ TWIST
; S'inclina con la velocità: corre su e giù sempre meno, ribatte la palla di sbieco; il nome
; oscilla di lato finché non si ferma.
.segment "INV3"
.scope inv_twist
    jmp tick
    rts
    .res 2
    inv_title TN_3_W, TN_3_H, TN_3_COL, {TN_3_MAP}, {TN_3_CLR}
t:  .byte 0
osc: .byte 0, 7, 13, 16, 16, 14, 9, 3, <-3, <-9, <-13, <-14, <-13, <-10, <-5, 0, 5, 9, 11, 11
     .byte 9, 6, 2, <-2, <-6, <-8, <-9, <-8, <-6, <-3, 0, 3, 5, 6, 6, 5, 3, 1, <-1, <-2
     .byte <-3, <-3, <-3, <-2, <-1, 0, 1, 1, 1, 0
nm:  .byte 2, 1, 0, <-1, <-1, <-1, 0, 0, 1, 1, 0, 0, 0, <-1, 0, 0, 0, 0, 0, 0, 0
tick:
    ; la racchetta su e giù per 50 frame dal 5
    ldy #IN_PADY
    lda in_f
    sec
    sbc #5
    bcc pad
    cmp #50
    bcs pad
    tax
    lda #IN_PADY
    clc
    adc osc,x
    tay
pad:
    lda #0
    ldx #COL_WHITE
    jsr in_pad
    ; la palla dal giocatore (12-24), poi via di sbieco in alto
    lda in_f
    sec
    sbc #12
    bcc name
    cmp #13
    bcs back
    sta t
    asl a
    asl a
    adc t
    sec
    sbc #66
    ldy #IN_PADY + 9 - 3
    jsr in_ball
    jmp name
back:
    sbc #13                     ; (C = 1)
    sta t
    asl a
    asl a
    eor #$ff
    sec
    adc #IN_PADY + 6
    bcc off
    cmp #SPR_Y0 - 8
    bcc off
    tay
    lda t                       ; 2 + 3,5 unità a frame verso il giocatore
    asl a
    asl a
    asl a
    sec
    sbc t
    lsr a
    adc #2
    eor #$ff
    clc
    adc #1
    jsr in_ball
    jmp name
off:
    ldx #0
    jsr in_off
name:
    ; il nome dal 55: oscilla di lato per 20 frame
    lda in_f
    sec
    sbc #55
    bcc tag
    cmp #21
    bcs tag
    tax
    lda nm,x
    ldx #COL_WHITE
    ldy #TN_3_ROW
    jsr in_name
tag:
    lda #77
    ldx #1
    jsr in_tag_at
    lda #93
    ldy #10
    jsr in_caps_at
    lda #125
    jmp in_first
.endscope

; ------------------------------------------------------------------------------------ BLASTER
; Spara alle capsule: dalla sua parte spara, e ogni colpo accende una lettera del nome, dalla
; più vicina; poi scende e le capsule arrivano una dopo l'altra.
.segment "INV4"
.scope inv_blaster
    jmp tick
    rts
    .res 2
    inv_title TN_4_W, TN_4_H, TN_4_COL, {TN_4_MAP}, {TN_4_CLR}
NAMEY = SPR_Y0 + TN_4_CY        ; y degli sprite del centro del nome
n:    .byte 0
k:    .byte 0
t:    .byte 0
j:    .byte 0
lit:  .byte $ff                 ; ultima lettera accesa (gialla): bianca al colpo dopo
tick:
    ; la racchetta da parte, all'altezza del nome; dal frame 53 scende alle capsule
    lda in_f
    cmp #3
    bcc shots
    ldy #NAMEY
    sec
    sbc #53
    bcc pad
    cmp #6
    bcs low
    sta t                       ; 7 pixel a frame
    asl a
    asl a
    asl a
    sec
    sbc t
    clc
    adc #NAMEY
    cmp #IN_CAPY
    bcc :+
low:
    lda #IN_CAPY
:   tay
pad:
    lda #50
    ldx #COL_WHITE
    jsr in_pad
shots:
    ; il colpo k parte al frame 10 + 4k verso la colonna di celle j del nome, 24 unità a frame
    lda #TN_4_W
    sta n
    lda in_f
    sec
    sbc #10
    jcc tag
    ldx #0
:   cmp #4
    bcc :+
    sbc #4
    inx
    bne :-
:   sta t
    stx k
    cmp #0
    bne :+
    ldx lit                     ; al colpo dopo la colonna di prima torna dei suoi colori
    bmi :+
    lda #COL_WHITE
    ldy #TN_4_ROW
    jsr in_letter
    lda #$ff
    sta lit
:   ldx k
    cpx n
    bcs tag
    stx j
    lda in_opp
    beq :+
    lda n                       ; dalla più vicina alla racchetta
    clc
    sbc k
    sta j
:   ; x della colonna (unità dal centro verso l'avversario)
    lda #TN_4_COL
    clc
    adc j
    asl a
    asl a
    adc #2                      ; (colonna * 8 + 4) / 2
    sec
    sbc #80
    ldx in_opp
    bne :+
    eor #$ff
    clc
    adc #1
:   sta d
    lda lit
    bpl tag                     ; già presa
    ldx t                       ; il colpo: 24 unità a frame dalla bocca
    lda sdx,x
    sta t
    sec
    sbc d
    bvc :+
    eor #$80
:   bmi hit
    beq hit
    lda #SP_BALL4
    ldy egg_yel
    ldx #0
    jsr in_small
    lda #NAMEY - 2
    sta sh_y
    lda t
    ldy #2
    jsr in_x
    jmp tag
hit:
    ldx #0
    jsr in_off
    ldx j
    stx lit
    lda egg_yel
    ldy #TN_4_ROW
    jsr in_letter
tag:
    lda #47
    ldx #1
    jsr in_tag_at
    lda #80
    ldy #12
    jsr in_caps_at
    lda #125
    jmp in_first
d:  .byte 0
sdx: .byte 46, 22, <-2, <-26     ; (fino alla prima colonna dall'altra parte)
.endscope

; ------------------------------------------------------------------------------------ RUSH
; Scatto lungo: tutto veloce; lampeggia sul bordo e scatta al centro con le immagini gialle, e
; nome, motto e capsule entrano allo stesso modo.
.segment "INV5"
.scope inv_rush
    jmp tick
    rts
    .res 2
    inv_title TN_5_W, TN_5_H, TN_5_COL, {TN_5_MAP}, {TN_5_CLR}
gx: .byte 43, 29, 14            ; le immagini dello scatto
dash: .byte 43, 28, 13, 0
tick:
    lda in_f
    cmp #3
    jcc name
    cmp #13
    bcs go
    ; sul bordo, a lampi
    ldx #SPN_PAD
    ldy in_opp
    beq :+
    inx
:   lda #0
    sta in_t
    lda in_f
    ldy #0
:   iny
    sec
    sbc #3
    bcs :-
    tya
    lsr a
    bcs :+                      ; acceso nei frame (f / 3) pari
    jmp in_off
:   lda #58
    jmp place
go:
    sbc #13                     ; (C = 1)
    cmp #4
    bcc :+
    lda #3
:   tax
    lda dash,x
place:
    ldx #COL_WHITE
    ldy #IN_PADY
    jsr in_pad
    ; le immagini gialle dello scatto (13-24), sprite 5-7 come la racchetta
    lda in_f
    cmp #13
    bcc name
    cmp #25
    bcs fade
    ldx #5
:   ldy in_opp
    lda sh_ptr+SPN_PAD,y
    ldy egg_yel
    jsr in_small
    lda bit_of,x
    ora sh_mc
    sta sh_mc
    lda bit_of,x
    ora sh_yexp
    sta sh_yexp
    ldy in_opp
    lda sh_y+SPN_PAD,y
    sta sh_y,x
    lda gx - 5,x
    ldy #12
    jsr in_x
    inx
    cpx #8
    bne :-
    beq name
fade:
    bne name
    ldx #5
:   jsr in_off
    inx
    cpx #8
    bne :-
name:
    ; il nome scatta dal bordo (25-28) con le immagini gialle, poi bianco
    lda in_f
    sec
    sbc #25
    bcc tag
    cmp #4
    bcs final
    asl a
    asl a
    eor #$ff
    sec
    adc #12                     ; 12, 8, 4 colonne
    ldx in_opp
    bne :+
    eor #$ff
    clc
    adc #1
:   ldx egg_yel
    ldy #TN_5_ROW
    jsr in_name_nc
    jmp tag
final:
    bne tag
    lda #0
    ldx #COL_WHITE
    ldy #TN_5_ROW
    jsr in_name
tag:
    ldx #1
    lda in_f
    cmp #37
    bcc caps
    lda #37 - 15                ; il motto scatta: tutto insieme
    jsr in_tag_at
caps:
    lda #51
    ldy #5
    jsr in_caps_at
    lda #75
    jmp in_first
.endscope

; ------------------------------------------------------------------------------------ GUARDIAN
; Muro a cinque pezzi, l'ultimo livello: i pezzi del muro cadono uno sull'altro dietro la
; racchetta, una palla passa sopra e il muro la rimanda; il nome si posa lettera per lettera.
.segment "INV6"
.scope inv_guardian
    jmp tick
    rts
    .res 2
    inv_title TN_6_W, TN_6_H, TN_6_COL, {TN_6_MAP}, {TN_6_CLR}
col: .byte 0
s:   .byte 0
s2:  .byte 0
t:   .byte 0
tick:
    lda #18                     ; il muro dietro la racchetta, dalla parte dell'avversario
    ldx in_opp
    beq :+
    lda #21
:   sta col
    lda in_f
    cmp #3
    bcc wall
    lda #<-4
    ldx #COL_WHITE
    ldy #IN_PADY
    jsr in_pad
wall:
    ; il pezzo s (dal basso) si posa al frame 8 + 7s: una riga sopra, poi al suo posto (righe 5-9)
    ldx #0
pieces:
    stx s
    txa
    asl a
    asl a
    asl a
    sec
    sbc s
    clc
    adc #8
    eor #$ff
    sec
    adc in_f
    cmp #0
    beq up
    cmp #2
    bne next
    lda #9 - 1                  ; via dalla riga sopra, con un colpo sordo
    sec
    sbc s
    tay
    lda #CH_BLANK
    jsr put
    lda #0
    ldy #5
    jsr in_scroll
    lda #9
    bne piece
up:
    lda #9 - 1
piece:
    sec
    sbc s
    tay
    lda #CH_WALL
    jsr put
next:
    ldx s
    inx
    cpx #5
    bne pieces
    ; il pezzo in alto lampeggia quando lo colpisce la palla (68-75)
    lda in_f
    sec
    sbc #68
    bcc ball
    cmp #8
    bcs ball
    and #2
    beq :+
    lda egg_yel
    .byte $2c                   ; (bit: salta il lda)
:   lda #COL_WHITE
    ldy col
    sta $d800 + 5 * 40,y
ball:
    ; la palla passa sopra la racchetta (43-67) e il muro la rimanda
    lda in_f
    sec
    sbc #43
    bcc name
    cmp #25
    bcs back
    sta t
    asl a
    adc t
    sec
    sbc #68
    jmp fly
back:
    sbc #25                     ; (C = 1)
    sta t
    cmp #28
    bcs off
    asl a
    adc t
    eor #$ff
    sec
    adc #6
fly:
    ldy #SPR_Y0 + 5 * 8 + 1
    jsr in_ball
    lda in_f                    ; il colpo: lo schermo di lato per un frame
    cmp #68
    bne name
    lda #1
    ldy #3
    jsr in_scroll
    jmp name
off:
    ldx #0
    jsr in_off
name:
    lda in_f                    ; (la x di nuovo dritta)
    cmp #69
    bne :+
    lda #0
    ldy #3
    jsr in_scroll
:   ; le colonne di celle del nome, una ogni 2,5 frame dall'80: cadono di due righe
    lda #TN_6_W
    sta s
    ldx #0
letter:
    stx t
    txa
    asl a
    asl a
    adc t
    lsr a
    adc #80
    eor #$ff
    sec
    adc in_f
    ldy #TN_6_ROW - 2
    cmp #0
    beq draw
    cmp #2
    beq down
    cmp #4
    bne skip
down:
    lsr a                       ; via dalla riga di prima, una sotto
    clc
    adc #TN_6_ROW - 3
    sta s2
    tay
    ldx t
    lda #0
    jsr in_letter
    ldy s2
    iny
draw:
    ldx t
    lda #COL_WHITE
    jsr in_letter
skip:
    ldx t
    inx
    cpx s
    bne letter
    lda #108
    ldx #1
    jsr in_tag_at
    lda #110
    ldy #5
    jsr in_caps_at
    lda #IN_LAST
    jmp in_first
; il carattere A nella colonna del muro, riga Y, giallo (Y resta)
put:
    sty v_row
    pha
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    pla
    ldy col
    sta (ptr),y
    lda ptr+1
    clc
    adc #>($d800 - SCREEN)
    sta ptr+1
    lda egg_yel
    sta (ptr),y
    ldy v_row
    rts
.endscope
.segment "CODE"

; ------------------------------------------------------------------------------------ OMEGA
; Diventa tutti gli altri (challenge_ui.rs, Stage::omega): la racchetta rossa (viola con l'easter
; egg) lampeggia bianca una volta per forma della scala (0,4 s ciascuna), poi una volta più lunga e
; resta; il sigillo lampeggia e resta, poi motto, i bonus di ARCADE e i punti, agli stessi secondi
; del PC. La presentazione dura OM_INTRO_FRAMES invece di CH_INTRO_FRAMES, e l'entrata va oltre
; IN_LAST (in_f senza segno: qui e nelle routine comuni che usa nessun confronto con il segno):
; init cambia la durata e i limiti di in_tick, che la presentazione rimette a ogni copia. Sul PC la racchetta cambia
; anche forma: qui l'immagine non si rifà durante la voce (vedi sopra), resta quella di ARCADE.
; Il nome lo copia init (in_draw ha copiato quello del tipo, ARCADE); SECRET LEVEL prende il posto
; di FINAL LEVEL, e il trattino che in_tick accende oltre la scala per il livello CH_OMEGA si toglie.
; Nella cartuccia sta nel banco di OMEGA (paddws.cfg, OMINV), alla pagina che enter_intro prende per
; un tipo 7 (INV_SRC + 14).
.segment "INV7"
.scope inv_omega
    jmp tick
    jmp init
    inv_title TN_7_W, TN_7_H, TN_7_COL, {TN_7_MAP}, {TN_7_CLR}
OM_FORMS_AT = 5                 ; prima forma, poi una ogni OM_FORM_F frame (0,4 s)
OM_FORM_F   = 20
OM_SEAL_AT  = 150               ; sigillo (3 s; sul PC 180 a 60 Hz), 20 frame a tratti
OM_TAG_AT   = 163               ; motto (196), una lettera a frame
OM_CAPS_AT  = 188               ; capsule (226), una ogni 7 frame
OM_FIRST_AT = 220               ; FIRST TO (264)
OM_INTRO_FRAMES = 262           ; 5,25 s (OMEGA_INTRO_SECONDS del PC)
OM_LAST     = OM_FIRST_AT       ; ultimo frame dell'entrata
OM_DONE     = OM_LAST + 8       ; poi le tabelle dei quadrati di nuovo (sopra c'è l'entrata)
.assert OM_FORMS_AT + CH_LEVELS * OM_FORM_F < OM_SEAL_AT, error, "OMEGA: il sigillo prima dell'ultima forma"
.assert OM_DONE + 2 < 256 .and OM_DONE + 2 + 20 < OM_INTRO_FRAMES, error, "OMEGA: entrata troppo lunga"
tag:    .byte "IT BECOMES THEM ALL"
TAG_LEN = * - tag
init:
    lda #OM_LAST + 3            ; i limiti di in_tick per questa entrata
    sta in_tick::last_op + 1
    lda #OM_DONE + 2
    sta in_tick::done_op + 1
    lda ch_timer                ; e la durata (ch_screen ha messo quella di sempre)
    clc
    adc #<(OM_INTRO_FRAMES - CH_INTRO_FRAMES)
    sta ch_timer
    lda ch_timer + 1
    adc #>(OM_INTRO_FRAMES - CH_INTRO_FRAMES)
    sta ch_timer + 1
    jsr om_glyphs               ; (i caratteri della rete per la partita)
    lda #TTL_OMEGA
    jmp title_copy
; I sei caratteri della rete di OMEGA: trattini di 2 pixel spostati di -3, -2, -1 (colonna 19) e
; +1, +2, +3 (colonna 20) dalla mezzeria, nelle prime 4 righe come quelli di sempre.
.proc om_glyphs
    ldx #5
:   txa
    asl a
    asl a
    asl a
    tay
    lda om_gv,x
    sta OM_CHARS,y
    sta OM_CHARS+1,y
    sta OM_CHARS+2,y
    sta OM_CHARS+3,y
    lda #0
    sta OM_CHARS+4,y
    sta OM_CHARS+5,y
    sta OM_CHARS+6,y
    sta OM_CHARS+7,y
    dex
    bpl :-
    rts
.endproc
om_gv:   .byte $0C, $06, $03, $C0, $60, $30
tick:
    lda #CH_BLANK
    sta SCREEN + IN_LADDER * 40 + CH_LEVELS * 5 + 4
    sta SCREEN + IN_LADDER * 40 + CH_LEVELS * 5 + 5
    lda in_f
    cmp #12
    bne pad
    lda in_mode                 ; (nell'allenamento resta TRAINING)
    cmp #IM_TRAIN
    beq pad
    jsr print_at
    .byte 14, IN_LEVEL, "SECRET LEVEL", 0
pad:
    ; la racchetta dal frame OM_FORMS_AT: bianca 3 frame a ogni forma (6 all'ultima)
    lda in_f
    sec
    sbc #OM_FORMS_AT
    bcc name
    ldx #0
:   cmp #OM_FORM_F
    bcc :+
    sbc #OM_FORM_F
    inx
    cpx #CH_LEVELS
    bne :-
:   ldy #3
    cpx #CH_LEVELS
    bne :+
    ldy #6
:   sty in_t
    ldx #COL_WHITE
    cmp in_t
    bcc :+
    ldx #COL_RED
    lda egg_x
    beq :+
    ldx #COL_PURPLE
:   ldy #IN_PADY
    lda #0
    jsr in_pad
name:
    ; il sigillo dal frame OM_SEAL_AT: lampeggia (3 frame acceso, 3 spento) per 20 frame
    lda in_f
    sec
    sbc #OM_SEAL_AT
    bcc motto
    cmp #20
    bcc :+
    bne motto
    ldx #COL_WHITE
    bne draw
:   cmp #6
    bcc :+
    sbc #6
    bcs :-
:   ldx #COL_WHITE
    cmp #3
    bcc draw
    ldx #0
draw:
    lda #0
    ldy #TN_7_ROW
    jsr in_name
motto:
    ; IT BECOMES THEM ALL (più lungo dei motti di in_tag_at), una lettera a frame da OM_TAG_AT
    lda in_f
    sec
    sbc #OM_TAG_AT
    bcc caps
    cmp #TAG_LEN
    bcs caps
    tay
    adc #(40 - TAG_LEN) / 2     ; (C = 0)
    tax
    lda #IN_TAG
    sta v_row
    lda tag,y
    jsr put_ascii
    lda #COL_GRAY
    ldy #IN_TAG
    jsr color_row
caps:
    lda #OM_CAPS_AT
    ldy #7
    jsr in_caps_at
    lda #OM_FIRST_AT
    jmp in_first
.endscope
.assert INV_SRC + 2 * OMEGA_KIND = $80 + (OM_INV_OFF / 256), error, "entrata di OMEGA non alla pagina di un tipo 7"
.segment "CODE"
