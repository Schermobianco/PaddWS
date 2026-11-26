; Presentazione dell'avversario di CHALLENGE, come rust/game/src/challenge_ui.rs (Intro e Stage), in
; due parti. Qui la prima, a celle, mentre la voce dice il nome: in cima la scala dei sette livelli
; (trattini che compaiono uno ogni due frame: battuti bianchi, quello di adesso giallo che
; lampeggia, gli altri grigi), sotto il livello e il nome dell'avversario, fermo; per OMEGA la sua
; parte speciale (forme e sigillo). Poi, finita la voce, lo schermo VS in bitmap (kvs.s, dalla
; 4.5.0 al posto delle entrate animate dei singoli avversari), che copre il file voce: in_tick salta
; a vs_enter.
;
; Il codice sta nella cartuccia: la parte comune (segmento INCODE, quattro pagine) gira nel secondo
; schermo (le mosse speciali le ricopia intro_scene alla fine), i dati del nome dell'avversario e
; l'entrata di OMEGA (segmenti INV0-INV7 per tipo di racchetta K_*, due pagine ciascuno, nel .prg da
; INV_IMG; OMEGA nel suo banco) sulle tabelle dei quadrati, che nella presentazione non servono:
; enter_intro le dà per pronte (math_step non le tocca), e si rifanno quando la presentazione
; finisce; la partita aspetta che siano pronte. Le copia enter_intro insieme al file voce (un
; caricamento). Ogni entrata comincia con un salto alla sua parte di ogni frame (inv_tick) e con
; quella del disegno (inv_init); quelle dei tipi hanno solo il nome (in_static).
;
; Il nome è la grafica dell'avversario (assets/titles) in caratteri hires: i caratteri (TN_FIRST, una
; pagina di titles.bin) li copia in_draw sullo schermo appena pulito, la mappa e i colori stanno
; all'inizio dell'entrata (TN_HDR), la riga a INV_RUN + 1.
;
; Tempi in frame a 50 Hz dall'inizio della presentazione (quelli del PC sono a 60); le x degli
; sprite in unità di 2 pixel dal centro verso la metà campo dell'avversario.
IN_RUN    = SCREEN2
INV_RUN   = square1_lo
IN_IMG    = $EE00
INV_IMG   = $F200               ; poi due pagine per tipo (K_*), fino a $FFFF
IN_DONE   = 180                 ; frame dopo l'ultima cosa delle entrate: le tabelle da rifare
IN_LAST   = 127                 ; ultimo frame delle entrate (in_f con il segno giusto)
IN_VS     = 30                  ; primo frame dello schermo VS, se la voce è finita (parte a 25)
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
in_step: .byte 0                ; in_draw: frame del disegno (0-2)

; Disegno (ch_draw), sullo schermo pulito, in tre frame (ch_more; insieme non ci stanno nel frame
; NTSC). Il primo è vuoto: è il terzo della presentazione, in cui il file voce del primo livello
; copia GO (VOICE_TICK, circa 12.900 cicli). Poi i caratteri del nome dalla cartuccia (prima della
; voce, come le copie), punteggio, record e duelli vinti (intro_hud, non nell'allenamento); poi
; l'immagine della racchetta dell'avversario (prima della voce: dopo l'I/O resta acceso) e
; l'entrata.
.proc in_draw
    lda in_step
    inc in_step
    cmp #2
    beq second
    inc ch_more
    cmp #1
    beq first
    rts
first:
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
    rts
second:
.ifdef ROTATED
    lda #0                      ; (campo girato: l'astronave della partita, in_pad la copia)
    sta ship_part
    jmp inv_init
.else
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
.endif
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
    ; lo schermo VS (kvs.s) da IN_VS, finita la voce (il vettore dell'NMI non è più nel player:
    ; la bitmap copre il file voce)
    lda in_f
vs_op:
    cmp #IN_VS                  ; (OMEGA, più lunga, cambia il limite: inv_omega)
    bcc :+
    bit $fffb
    bmi :+
    jmp vs_enter
:   jmp inv_tick
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
    lda #COL_YELLOW
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

; Le righe del nome da Y vuote, poi il nome spostato di A colonne (con il segno), del colore X
; (COL_WHITE: i suoi colori; 0: solo le righe vuote).
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

; Il nome fermo, nella sua riga (INV_RUN + 1): il disegno delle entrate dei tipi.
.proc in_static
    lda #0
    ldx #COL_WHITE
    ldy INV_RUN + 1
    jmp in_name
.endproc

; La colonna di celle X del nome dalla riga in_y, spostata di in_dx colonne, del colore in_t
; (COL_WHITE: i suoi colori; altri già con l'easter egg; 0: le celle della colonna vuote); le celle
; vuote del nome restano come sono, salvo con il colore 0.
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

; La racchetta dell'avversario accesa: A unità dal centro, centro alla y degli sprite Y, colore X.
; Nel campo girato l'astronave della partita (solo OMEGA, al centro: A non conta), con la posa del
; lato dell'avversario: prima una parte al frame nella serie 0 (ship_copy, quando la voce lascia
; spegnere l'I/O), poi accesa.
.proc in_pad
.ifdef ROTATED
    stx in_t
    sty in_dx
    lda ship_part
    cmp #4
    bcs show
    lda in_k
    ldx #0
    ldy in_opp
    jmp ship_copy
show:
    lda #<(IN_CX - 24)
    sta ship_x
    ldx in_k
    lda in_dx
    sec
    sbc #14                     ; (la posa in alto: il disegno finisce alla riga 20)
    ldy in_opp
    bne :+
    clc
    adc rp_dy,x
:   sta ship_y
    ldx #0
    ldy #0
    lda in_k
    jsr ship_regs
    lda in_t
    sta sh_col+2
    sta sh_col+3
    rts
.else
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
.endif
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

; ------------------------------------------------------------------------------------ entrate
; Dalla 4.5.0 lo schermo VS (kvs.s) prende il posto delle entrate animate degli avversari: di ogni
; tipo restano qui la riga, la mappa e i colori del nome (TN_k_*), che in_static disegna fermo nella
; prima parte della presentazione, con la voce.
.segment "INV0"                ; ARCADE
    rts                         ; ogni frame: niente
    .byte TN_0_ROW
    .res 1
    jmp in_static               ; disegno: il nome fermo
    inv_title TN_0_W, TN_0_H, TN_0_COL, {TN_0_MAP}, {TN_0_CLR}
.segment "INV1"                ; TITAN
    rts                         ; ogni frame: niente
    .byte TN_1_ROW
    .res 1
    jmp in_static               ; disegno: il nome fermo
    inv_title TN_1_W, TN_1_H, TN_1_COL, {TN_1_MAP}, {TN_1_CLR}
.segment "INV2"                ; HAMMER
    rts                         ; ogni frame: niente
    .byte TN_2_ROW
    .res 1
    jmp in_static               ; disegno: il nome fermo
    inv_title TN_2_W, TN_2_H, TN_2_COL, {TN_2_MAP}, {TN_2_CLR}
.segment "INV3"                ; TWIST
    rts                         ; ogni frame: niente
    .byte TN_3_ROW
    .res 1
    jmp in_static               ; disegno: il nome fermo
    inv_title TN_3_W, TN_3_H, TN_3_COL, {TN_3_MAP}, {TN_3_CLR}
.segment "INV4"                ; BLASTER
    rts                         ; ogni frame: niente
    .byte TN_4_ROW
    .res 1
    jmp in_static               ; disegno: il nome fermo
    inv_title TN_4_W, TN_4_H, TN_4_COL, {TN_4_MAP}, {TN_4_CLR}
.segment "INV5"                ; RUSH
    rts                         ; ogni frame: niente
    .byte TN_5_ROW
    .res 1
    jmp in_static               ; disegno: il nome fermo
    inv_title TN_5_W, TN_5_H, TN_5_COL, {TN_5_MAP}, {TN_5_CLR}
.segment "INV6"                ; GUARDIAN
    rts                         ; ogni frame: niente
    .byte TN_6_ROW
    .res 1
    jmp in_static               ; disegno: il nome fermo
    inv_title TN_6_W, TN_6_H, TN_6_COL, {TN_6_MAP}, {TN_6_CLR}
.segment "CODE"

; ------------------------------------------------------------------------------------ OMEGA
; Diventa tutti gli altri (challenge_ui.rs, Stage::omega), la sua parte prima dello schermo VS: la
; racchetta rossa (viola con l'easter egg) lampeggia bianca una volta per forma della scala, poi
; una volta più lunga e resta; il sigillo lampeggia e resta; poi il VS (kvs.s) con il suo ritratto,
; il motto, i bonus e i punti, agli stessi secondi del PC. L'entrata va oltre IN_LAST (in_f senza
; segno: qui e nelle routine comuni che usa nessun confronto con il segno): init cambia i limiti
; di in_tick, che la presentazione rimette a ogni copia. Sul PC la racchetta cambia anche forma:
; qui l'immagine non si rifà durante la voce (vedi sopra), resta quella di ARCADE. Il nome lo copia
; init (in_draw ha copiato quello del tipo, ARCADE); SECRET LEVEL prende il posto di FINAL LEVEL, e
; il trattino che in_tick accende oltre la scala per il livello CH_OMEGA si toglie. Nella cartuccia
; sta nel banco di OMEGA (paddws.cfg, OMINV), alla pagina che enter_intro prende per un tipo 7
; (INV_SRC + 14).
.segment "INV7"
.scope inv_omega
    jmp tick
    jmp init
    inv_title TN_7_W, TN_7_H, TN_7_COL, {TN_7_MAP}, {TN_7_CLR}
OM_FORMS_AT = 5                 ; prima forma, poi una ogni OM_FORM_F frame (sul PC 14 a 60 Hz)
OM_FORM_F   = 12
OM_SEAL_AT  = 92                ; sigillo (110), 20 frame a tratti
OM_VS_AT    = 125               ; lo schermo VS (150)
OM_LAST     = OM_VS_AT + 60     ; ultimo frame dell'entrata (se la voce dura di più)
OM_DONE     = OM_LAST + 8
.assert OM_FORMS_AT + CH_LEVELS * OM_FORM_F < OM_SEAL_AT .and OM_SEAL_AT + 20 < OM_VS_AT, error, "OMEGA: forme, sigillo e VS in ordine"
.assert OM_DONE + 2 < 256 .and OM_DONE + 2 < CH_INTRO_FRAMES, error, "OMEGA: entrata troppo lunga"
init:
    lda #OM_LAST + 3            ; i limiti di in_tick per questa entrata
    sta in_tick::last_op + 1
    lda #OM_DONE + 2
    sta in_tick::done_op + 1
    lda #OM_VS_AT
    sta in_tick::vs_op + 1
    jsr om_glyphs               ; (i caratteri della rete per la partita)
    lda #TTL_OMEGA
    jmp title_copy
.ifdef ROTATED
; Campo girato: i sei caratteri della rete di OMEGA sono la mezzeria (trattini di 4 pixel, due
; righe) spostata in su di 3, 2, 1 e in giù di 1, 2, 3 righe.
.proc om_glyphs
    ldx #5
:   txa
    asl a
    asl a
    asl a
    tay
    lda #0
    .repeat 8, i
    sta OM_CHARS + i,y
    .endrepeat
    tya
    clc
    adc om_gr,x
    tay
    lda #$F0
    sta OM_CHARS,y
    sta OM_CHARS+1,y
    dex
    bpl :-
    rts
.endproc
om_gr:   .byte 0, 1, 2, 4, 5, 6     ; prima riga del trattino: 3 + spostamento
.else
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
.endif
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
    ldx #COL_PURPLE
:   ldy #IN_PADY
    lda #0
    jsr in_pad
name:
    ; il sigillo dal frame OM_SEAL_AT: lampeggia (3 frame acceso, 3 spento) per 20 frame
    lda in_f
    sec
    sbc #OM_SEAL_AT
    bcc done
    cmp #20
    bcc :+
    bne done
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
    jmp in_name
done:
    rts
.endscope
.assert INV_SRC + 2 * OMEGA_KIND = $80 + (OM_INV_OFF / 256), error, "entrata di OMEGA non alla pagina di un tipo 7"
.segment "CODE"
