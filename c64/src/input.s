; Comandi: joystick (porta 2 = giocatore sinistro, porta 1 = destro), paddle (una coppia sulla
; porta 1: POTX il sinistro, POTY il destro) e tastiera.
;
; Si leggono una volta per frame, subito dopo il vblank. I paddle si misurano di continuo sulla
; porta scelta con i bit 6-7 di $DC00: la lettura della tastiera la cambia per un attimo, e il
; valore torna buono ben prima del frame successivo.

CIA1_PRA = $dc00
CIA1_PRB = $dc01
SID_POTX = $d419
SID_POTY = $d41a

JOY_UP    = $01
JOY_DOWN  = $02
JOY_LEFT  = $04
JOY_RIGHT = $08
JOY_FIRE  = $10

PADDLE_SELECT = $7f             ; bit 6-7 = %01: paddle della porta 1
TAP_FRAMES = 10                 ; doppio tocco entro 200 ms = rapido, come sul MiSTer
SCROLL_FRAMES = 50              ; NEXT con il joystick: il bonus selezionato cambia da solo ogni secondo

; tasti: riga (bit azzerato in $DC00) e colonna (bit letto in $DC01)
; (riga * 8 + colonna)
KEY_RETURN = 0 * 8 + 1
KEY_CRSR_LR = 0 * 8 + 2
KEY_CRSR_UD = 0 * 8 + 7
KEY_5      = 2 * 8 + 0
KEY_F7     = 0 * 8 + 3
KEY_F1     = 0 * 8 + 4
KEY_F3     = 0 * 8 + 5
KEY_F5     = 0 * 8 + 6
KEY_1      = 7 * 8 + 0
KEY_SPACE  = 7 * 8 + 4
KEY_Q      = 7 * 8 + 6
KEY_STOP   = 7 * 8 + 7
KEY_C      = 2 * 8 + 4
KEY_F      = 2 * 8 + 5
KEY_MINUS  = 5 * 8 + 3
KEY_PERIOD = 5 * 8 + 4

.segment "BSS"
ctl_paddle: .res 1              ; 0 joystick, 1 paddle
joy:        .res 2              ; per giocatore: JOY_*, bit a 1 = premuto
joy_prev:   .res 2
fire_edge:  .res 2              ; fuoco (o pulsante del paddle) appena premuto
joy_edge:   .res 2              ; direzioni e fuoco appena premuti
dir_prev:   .res 2
fast:       .res 2
tap_age:    .res 4              ; frame dall'ultima pressione: giocatore * 2 + (0 su, 1 giù)
pot_raw:    .res 2
pot:        .res 2              ; filtrato
btn_prev:   .res 1              ; pulsanti dei paddle al frame prima
scroll_t:   .res 2              ; frame al prossimo cambio del bonus selezionato
keys:       .res 8              ; righe della tastiera, bit a 1 = premuto
keys_prev:  .res 8
keys_edge:  .res 8              ; appena premuti
keys_any:   .res 1              ; qualche tasto premuto all'ultima scansione

.segment "CODE"

.segment "BOOTCODE"           ; solo all'avvio (unpack.s)
.proc input_init
    lda #$ff
    sta CIA1_PRA
    sta $dc02                   ; porta A in uscita (righe della tastiera)
    lda #0
    sta $dc03                   ; porta B in ingresso
    ldx #7
:   sta keys,x
    sta keys_prev,x
    sta keys_edge,x
    dex
    bpl :-
    sta joy
    sta joy+1
    sta joy_prev
    sta joy_prev+1
    sta dir_prev
    sta dir_prev+1
    sta fast
    sta fast+1
    sta btn_prev
    lda #$ff
    sta tap_age
    sta tap_age+1
    sta tap_age+2
    sta tap_age+3
    lda #128
    sta pot
    sta pot+1
    rts
.endproc
.segment "CODE"

; Lettura di tutti i comandi del frame.
.proc read_input
    ; paddle: misurati durante il frame precedente
    lda SID_POTX
    sta pot_raw
    lda SID_POTY
    sta pot_raw+1
    ; joystick, senza righe della tastiera
    lda #$ff
    sta CIA1_PRA
    lda joy
    sta joy_prev
    lda joy+1
    sta joy_prev+1
    lda CIA1_PRA
    eor #$ff
    and #$1f
    sta joy
    lda CIA1_PRB
    eor #$ff
    and #$1f
    sta joy+1
    ldx #1
:   lda joy_prev,x
    eor #$ff
    and joy,x
    sta joy_edge,x
    and #JOY_FIRE
    sta fire_edge,x
    dex
    bpl :-
    ; pulsanti dei paddle (porta 1, bit 2 e 3): valgono come fuoco
    lda ctl_paddle
    beq keyboard
    lda joy+1
    and #JOY_LEFT | JOY_RIGHT
    tax
    eor btn_prev
    stx btn_prev
    and btn_prev
    tax
    and #JOY_LEFT
    beq :+
    lda #JOY_FIRE
    sta fire_edge
:   txa
    and #JOY_RIGHT
    beq keyboard
    lda #JOY_FIRE
    sta fire_edge+1
keyboard:
    ; con un joystick mosso la tastiera darebbe tasti fantasma: niente lettura
    lda joy
    ora joy+1
    beq scan
    lda #0
    ldx #7
:   sta keys_edge,x
    sta keys,x
    sta keys_prev,x
    dex
    bpl :-
    jmp done
scan:
    ; tutte le righe insieme: nessun tasto ora né all'ultima scansione, tutto resta a zero
    lda #0
    sta CIA1_PRA
    lda CIA1_PRB
    cmp #$ff
    bne full
    lda keys_any
    beq done
full:
    lda #0
    sta keys_any
    ldx #7
:   lda row_mask,x
    sta CIA1_PRA
    lda CIA1_PRB
    eor #$ff
    sta keys,x
    eor keys_prev,x
    and keys,x
    sta keys_edge,x
    lda keys,x
    sta keys_prev,x
    ora keys_any
    sta keys_any
    dex
    bpl :-
done:
    lda #$ff
    ldx ctl_paddle
    beq :+
    lda #PADDLE_SELECT
:   sta CIA1_PRA
    ; frame dall'ultima pressione su e giù (fino a 255)
    ldx #3
:   lda tap_age,x
    cmp #$ff
    beq :+
    inc tap_age,x
:   dex
    bpl :--
    rts
.endproc

row_mask: .byte $fe, $fd, $fb, $f7, $ef, $df, $bf, $7f

; C = 1 se il tasto A (KEY riga, colonna) è stato appena premuto.
.proc key_pressed
    pha
    lsr a
    lsr a
    lsr a
    tax
    pla
    and #7
    tay
    lda keys_edge,x
    and col_bit,y
    cmp #1
    rts
.endproc

col_bit: .byte $01, $02, $04, $08, $10, $20, $40, $80

; C = 1 se uno dei giocatori ha appena premuto il fuoco (o il pulsante del paddle).
.proc any_fire
    lda fire_edge
    ora fire_edge+1
    cmp #1
    rts
.endproc

; Comandi del tick per la logica (in_dir, in_flags, in_offset) dai comandi del frame.
.proc build_input
    ldy #0                      ; giocatore
player:
    tya
    asl a
    asl a
    tax                         ; X = giocatore * 4
    lda ctl_paddle
    beq joystick
    ; paddle: posizione assoluta, (pot * corsa) / 256 con la corsa = altezza del campo - racchetta
    lda pot_raw,y
    sec
    sbc pot,y
    bcs :+
    eor #$ff
    adc #1
:   cmp #2                      ; piccolo tremolio del potenziometro: si ignora
    bcc :+
    lda pot_raw,y
    sta pot,y
:   lda #<(P_HEIGHT >> 16)
    sec
    sbc pad_h+2,x
    sty v_n
    tay                         ; Y = corsa
    ldx v_n
    lda pot,x                   ; A = posizione del paddle
    jsr umul8                   ; m_t = (pot * corsa) / 256
    ldy v_n
    tya
    asl a
    asl a
    tax
    lda m_t
    sta in_offset,x
    lda #0
    sta in_dir,x
    lda fire_edge,y
    beq :+
    lda #IN_FORWARD
:   ora #IN_OFFSET
    sta in_flags,x
    jmp next
joystick:
    ; direzione: su +1, giù -1
    lda joy,y
    and #JOY_UP
    beq :+
    lda #1
    jmp dir
:   lda joy,y
    and #JOY_DOWN
    beq dir
    lda #$ff
dir:
    sta in_dir,x
    cmp dir_prev,y
    beq keep
    sta dir_prev,y
    ; direzione nuova: rapido se è il secondo tocco ravvicinato nella stessa direzione
    cmp #0
    bne :+
    sta fast,y
    jmp keep
:   sty v_n
    tya
    asl a
    sta v_col
    lda in_dir,x
    bmi :+
    lda #0
    jmp :++
:   lda #1
:   ora v_col
    tay                         ; Y = indice di tap_age
    lda #0
    ldx tap_age,y
    cpx #TAP_FRAMES + 1
    bcs :+
    lda #1
:   sta m_t
    lda #0
    sta tap_age,y
    ldy v_n
    lda m_t
    sta fast,y
    tya
    asl a
    asl a
    tax
keep:
    lda fast,y
    beq :+
    lda #IN_FAST
:   sta m_t
    ; scatto in avanti (sparo del BLASTER): joystick verso l'avversario con la racchetta a casa;
    ; per rientrare il joystick dalla parte opposta. Lo scatto della logica va e torna con lo
    ; stesso comando: qui la direzione sceglie quando mandarlo. Fuori da NEXT, dove il fuoco non ha
    ; bonus da attivare, anche il fuoco (va e torna)
    lda joy_edge,y
    and toward,y
    beq back
    beq32 {pad_x,x}, {pad_home,x}, forward
    jmp flags                   ; già avanti: verso l'avversario non fa niente
back:
    lda joy_edge,y
    and away,y
    beq fire
    beq32 {pad_x,x}, {pad_home,x}, flags   ; a casa: indietro non fa niente
    jmp forward
fire:
    lda m_next
    bne flags
    lda fire_edge,y
    beq flags
forward:
    lda m_t
    ora #IN_FORWARD
    sta m_t
flags:
    lda m_t
    sta in_flags,x
next:
    iny
    cpy #2
    beq :+
    jmp player
:   jmp next_keys
.endproc

; direzione del joystick verso l'avversario: destra per il giocatore sinistro, sinistra per il destro;
; e quella opposta, per rientrare
toward: .byte JOY_RIGHT, JOY_LEFT
away:   .byte JOY_LEFT, JOY_RIGHT

; NEXT: con il joystick il bonus selezionato cambia da solo ogni secondo e il fuoco lo usa (lo
; scatto è verso l'avversario: un solo pulsante basta); con i paddle (un solo pulsante, che
; scatta) i tasti dei bonus del PC: F e C il giocatore sinistro, punto e meno il destro. Con le
; mosse speciali il fuoco che completa il gesto del joystick diventa la mossa (sm_joy in
; supers.s); con i paddle nessun gesto.
.proc next_keys
    lda m_next
    beq done
    lda ctl_paddle
    bne paddles
    ldy #0
player:
    tya
    asl a
    asl a
    tax
    jsr sm_joy
    lda fire_edge,y
    beq :+
    lda in_flags,x
    ora #IN_ACTIVATE
    sta in_flags,x
:   lda scroll_t,y
    sec
    sbc #1
    bcs :+
    lda in_flags,x
    ora #IN_SELECT
    sta in_flags,x
    lda #SCROLL_FRAMES - 1
:   sta scroll_t,y
    iny
    cpy #2
    bne player
done:
    rts
paddles:
    ldx #0
:   stx v_n
    lda key_table,x
    jsr key_pressed
    ldx v_n
    bcc :+
    ldy flag_side,x
    lda in_flags,y
    ora flag_bit,x
    sta in_flags,y
:   inx
    cpx #4
    bne :--
    rts
key_table: .byte KEY_F, KEY_C, KEY_PERIOD, KEY_MINUS
flag_side: .byte 0, 0, 4, 4
flag_bit:  .byte IN_SELECT, IN_ACTIVATE, IN_SELECT, IN_ACTIVATE
.endproc
