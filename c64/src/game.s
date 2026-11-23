; Logica di gioco: traduzione di `Match` (rust/core/src/game.rs), un tick per chiamata.
;
; Stessa sequenza di operazioni del Rust, stessa aritmetica (Q16.16 a 32 bit, math.s): a parità
; di parametri, seme e input lo stato coincide bit per bit (paddws-c64 game). Coordinate con
; l'origine in basso a sinistra e la y verso l'alto, come nel core.
;
; Le grandezze delle racchette sono vettori di 2 elementi da 4 byte (anche quelle da un byte),
; indicizzati con X = lato * 4 (0 sinistra, 4 destra).

ONE          = $00010000
REVERSE_KEEP = 19660        ; ONE * 3 / 10: slancio che resta invertendo la direzione
DAMP_BOOST   = 13107        ; ONE / 5: riflessione smorzata nell'area boost
FWD_PUSH     = 78643        ; ONE * 6 / 5: spinta dello scatto che intercetta la palla
HALF_W_FLOOR = P_PAD_HALF_W & $FFFF0000

; eventi del tick (Event in game.rs)
EV_WALL  = $01
EV_HIT   = $02
EV_BOOST = $04
EV_SCORE = $08

; flag dei comandi (in_flags; quelli di NEXT, mosse speciali comprese, in next.s)
IN_FAST    = $01
IN_FORWARD = $02
IN_OFFSET  = $80

.segment "RODATA"
boost_h_tab:   .dword T_BOOST_H
boost_inv_tab: .dword T_BOOST_INV
kspeed1_tab:   .dword T_KSPEED_1P
max1_tab:      .dword T_MAX_1P
kspeed2_tab:   .dword T_KSPEED_2P
max2_tab:      .dword T_MAX_2P

.segment "ZEROPAGE"
side:   .res 1          ; lato in esame * 4
scorer: .res 1
t0:     .res 4
t1:     .res 4
t2:     .res 4
t_start: .res 4
t_rel:  .res 4
prev_x: .res 4          ; x prima dello spostamento (contact la rifà da ball_dx)
prev_y: .res 4
cy:     .res 4          ; y del contatto
old_x:  .res 4
in_area: .res 1         ; la palla è dentro l'area boost (reflection)
; stato della partita più usato (in pagina zero: istruzioni più corte e più veloci)
events:      .res 2
score:       .res 8     ; punteggio (16 bit) per lato
serve_timer: .res 4
ball_x:     .res 4
ball_y:     .res 4
ball_r:     .res 4
ball_vx:    .res 4
ball_vy:    .res 4
ball_boost: .res 4
pad_x:      .res 8
pad_y:      .res 8
pad_half:   .res 8      ; metà altezza
pad_speed:  .res 8

.segment "BSS"
; configurazione, da impostare prima di match_new
cfg_players: .res 1     ; 1 o 2
cfg_evo:     .res 1     ; EVO (vale solo in due)
cfg_diff:    .res 1     ; difficoltà 0-3
cfg_seed:    .res 4
; comandi del tick, per giocatore (indice X = lato * 4)
in_dir:     .res 8      ; 1 su, $FF giù, 0 ferma
in_flags:   .res 8      ; IN_FAST, IN_FORWARD, IN_OFFSET
in_offset:  .res 8      ; posizione dell'encoder: pixel tra il bordo alto e la racchetta

; stato della partita
.segment "ZEROPAGE"
m_players:   .res 1
.segment "BSS"
m_evo:       .res 1
tick:        .res 4
best:        .res 2     ; record del singolo
max_ball:    .res 4     ; velocità massima della palla e accelerazione a ogni colpo
kspeed:      .res 4

ball_dx:    .res 4
; prodotto di |vx| per kspeed - ONE tenuto da parte per il prossimo colpo (kc_fill, kspeed_mul)
kc_v:       .res 4      ; |vx| del prodotto (byte 3 = $FF: nessuno)
kc_p:       .res 4      ; (|vx| * (kspeed - ONE)) >> 16
kc_wait:    .res 1      ; tick che mancano a kc_fill (0: niente)

pad_h:      .res 8
pad_home:   .res 8
pad_fwd:    .res 8
pad_inv:    .res 8      ; Q8.24: 1 / metà altezza
pad_bh:     .res 8      ; altezza dell'area boost
pad_level:  .res 8      ; livello dell'area boost (byte)
pad_dir:    .res 8      ; direzione (byte con segno)
pad_fast:   .res 8      ; rapido (byte)
pad_max:    .res 8
pad_acc:    .res 8
pad_facc:   .res 8
pad_fmax:   .res 8      ; con la racchetta avanzata
pad_fwacc:  .res 8
pad_fwfacc: .res 8
pad_motion: .res 8
pad_step:   .res 8      ; spostamento massimo per tick con l'encoder (0 = nessun limite)
pad_before: .res 8      ; y all'inizio del tick + motion (update_motion)

.segment "CODE"

; eventi |= valore
.macro event ev
    lda events
    ora #ev
    sta events
.endmacro

; ------------------------------------------------------------------------------------ partita

; Match::new: nuova partita con la configurazione cfg_*, poi la prima battuta.
.proc match_new
    lda cfg_players
    sta m_players
    ldx #0
    cmp #2
    bne :+
    ldx cfg_evo
:   stx m_evo
    ; NEXT: solo in due, è Classic con lo scatto in avanti
    ldx #0
    cmp #2
    bne :+
    ldx cfg_next
:   stx m_next
    txa
    beq :+
    lda #0
    sta m_evo
:   ; velocità della palla per modo e difficoltà
    lda cfg_diff
    asl a
    asl a
    tay
    lda m_players
    cmp #2
    beq _two
    mov32 max_ball, {max1_tab,y}
    mov32 kspeed, {kspeed1_tab,y}
    jmp _pads
_two:
    lda m_next
    beq :+
    mov32 max_ball, {max_next_tab,y}
    mov32 kspeed, {kspeed_next_tab,y}
    jmp _pads
:   mov32 max_ball, {max2_tab,y}
    mov32 kspeed, {kspeed2_tab,y}
_pads:
    lda #$FF                    ; kspeed nuovo: il prodotto tenuto da parte non vale più
    sta kc_v+3
    ; racchette: da pad_h a pad_step i valori di pad_init, uguali per i due lati (casa, avanzata e
    ; area boost si scrivono dopo)
    ldx #0
    ldy #0
:   lda pad_init,y
    sta pad_h,x
    sta pad_h+4,x
    inx
    iny
    tya
    and #3
    bne :-
    txa
    clc
    adc #4
    tax
    cpy #PAD_INIT_END - pad_init
    bne :-
    jsr boost_reset
    ; ferme a metà campo, a casa
    lda #0
    ldx #7
:   sta pad_speed,x
    sta pad_y,x
    lda pad_home_init,x
    sta pad_home,x
    sta pad_x,x
    lda pad_fwd_init,x
    sta pad_fwd,x
    lda #0
    dex
    bpl :-
    lda #^(P_HEIGHT / 2)
    sta pad_y+2
    sta pad_y+4+2
    ; in singolo la racchetta destra è un muro alto quanto il campo
    lda m_players
    cmp #1
    bne :+
    mov32 pad_h+4, {#P_HEIGHT}
    mov32 pad_inv+4, {#P_WALL_INV_HALF}
:   ldx #0
    jsr half_height
    ldx #4
    jsr half_height
    ; la palla la mette serve (sotto)
    lda #0
    ldx #3
:   sta tick,x
    dex
    bpl :-
    ldx #7
:   sta score,x
    dex
    bpl :-
    sta best
    sta best+1
    sta events
    sta events+1
    sta nx_btimer               ; BULLET spento (pad_update lo guarda in tutte le partite)
    sta nx_lslow                ; nessun rallentamento da laser
    sta nx_lslow+4
    sta sm_on                   ; mosse speciali spente (next_init le accende in NEXT)
    ; generatore dal seme (lo zero è un punto fisso di xorshift)
    mov32 rng, cfg_seed
    or32 rng
    bne :+
    mov32 rng, {#$2545F491}
    ; la prima battuta va a sinistra se rng.sign() > 0
:   jsr rng_next
    lda #0
    ldx rng+3
    bpl :+
    lda #4
:   jsr serve
    lda m_next
    bne :+
    rts
:   jmp next_init
.endproc

.segment "RODATA"
; valori iniziali delle racchette, un elemento per vettore da pad_h a pad_step
pad_init:
    .dword P_PAD_H, 0, 0, P_PAD_INV_HALF, 0, 0, 0, 0
    .dword P_PAD_MAX, P_PAD_ACC, P_PAD_FACC, P_PAD_MAX, P_PAD_ACC, P_PAD_FACC, 0, 0
PAD_INIT_END:
pad_home_init: .dword P_PAD_START, P_WIDTH - P_PAD_START
pad_fwd_init:  .dword P_PAD_FWD, P_WIDTH - P_PAD_FWD
.segment "CODE"
.assert pad_step = pad_h + 15 * 8, error, "pad_init: un elemento per vettore da pad_h a pad_step"
.assert pad_inv = pad_h + 3 * 8 .and pad_max = pad_h + 8 * 8 .and pad_fwfacc = pad_h + 13 * 8, error, "pad_init: ordine dei vettori"
.assert (P_HEIGHT / 2) & $FF00FFFF = 0, error, "match_new: metà altezza in un byte"

; Area boost intera (livello 0) per le due racchette: a inizio partita e a ogni punto in due.
.proc boost_reset
    lda #0
    sta pad_level
    sta pad_level+4
    ldx #3
:   lda boost_h_tab,x
    sta pad_bh,x
    sta pad_bh+4,x
    dex
    bpl :-
    rts
.endproc

; pad_half = pad_h / 2 (altezze positive)
.proc half_height
    mov32 {pad_half,x}, {pad_h,x}
    asr32 {pad_half,x}
    rts
.endproc

; Match::serve: palla al centro verso il lato A (0 sinistra, 4 destra; in singolo sempre a
; sinistra), con la velocità a caso e l'attesa della battuta.
.proc serve
    ldy m_players
    cpy #1
    bne :+
    lda #0
:   sta scorer              ; qui: lato verso cui va la palla
    ; vx = serve_unit * range(2, 4)
    jsr rng_next
    mov32 t0, {#P_SERVE_UNIT}
    asl32 t0
    lda rng
    lsr a
    bcc :+
    add32 t0, t0, {#P_SERVE_UNIT}
    ; vy = serve_unit * range(1, 3) * sign()
:   jsr rng_next
    mov32 t1, {#P_SERVE_UNIT}
    lda rng
    lsr a
    bcc :+
    asl32 t1
:   jsr rng_next
    lda rng+3
    bpl :+
    neg32 t1, t1
:   mov32 ball_x, {#P_WIDTH / 2}
    mov32 ball_y, {#P_HEIGHT / 2}
    mov32 ball_r, {#P_BALL_R}
    lda scorer
    bne :+
    neg32 ball_vx, t0
    jmp _vy
:   mov32 ball_vx, t0
_vy:
    mov32 ball_vy, t1
    mov32 ball_boost, {#ONE}
    mov32 ball_dx, {#0}
    mov32 serve_timer, {#P_SERVE_TICKS}
    lda #KC_WAIT                ; vx nuovo: il suo prodotto per il primo colpo (kc_fill)
    sta kc_wait
    rts
.endproc

; ------------------------------------------------------------------------------------ tick

; Match::step: un tick con i comandi in in_*; eventi in `events`.
.proc match_step
    lda #0
    sta events
    sta events+1
    sta nx_bmoved
    inc32 tick
.ifdef GHOSTTEST
    ; prova del GHOST per VICE (-Define GHOSTTEST): palla fantasma sempre, con la coda del boost
    lda m_next
    sta nx_ghost
    beq :+
    mov32 ball_boost, {#P_BOOST_FWD_MUL}
:
.endif
    ; lampi della palla fantasma: tick % periodo
    inc ghost_phase
    lda ghost_phase
    cmp #P_GHOST_PERIOD
    bcc :+
    lda #0
    sta ghost_phase
:   ; fermo del gioco dopo un SUPER con hit-stop: il tick salta
    lda m_next
    beq _go
    lda nx_freeze
    ora nx_freeze+1
    beq :+
    dec16_sat nx_freeze
    rts
:   ; BULLET: scatta, scende la rampa o finisce all'inizio del tick (non durante il fermo)
    jsr bullet_step
_go:
    ; y + motion all'inizio del tick, per update_motion
    add32 pad_before, pad_y, pad_motion
    add32 pad_before+4, pad_y+4, pad_motion+4
    jsr apply_input
    ldx #0
    jsr pad_update              ; (con update_motion)
    ldx #4
    jsr pad_update
    lda m_next
    beq :+
    jsr next_tick
:   or32 serve_timer
    beq _play
    sub32 serve_timer, serve_timer, {#1}
    rts
_play:
    jmp ball_tick
.endproc

; Paddle::update: accelerazione o frenata, poi il movimento entro il campo. Con il BULLET
; dell'avversario il passo è rallentato (la velocità no). Prosegue in update_motion.
;
; Velocità massime e accelerazioni stanno in vettori consecutivi (pad_max, pad_acc, pad_facc, poi
; gli stessi con la racchetta avanzata): Y = X, + PAD_FWD_OFS se avanzata, + 8 con il rapido.
PAD_FWD_OFS = pad_fmax - pad_max
.assert pad_acc = pad_max + 8 .and pad_facc = pad_acc + 8, error, "pad_update: vettori consecutivi"
.assert pad_fwacc = pad_fmax + 8 .and pad_fwfacc = pad_fwacc + 8, error, "pad_update: vettori consecutivi"
.assert P_HEIGHT & $FFFF = 0, error, "pad_update: altezza del campo intera"

.proc pad_update
    lda pad_dir,x
    jeq _nodir
    ; a casa o avanzata: valori diversi (RUSH). Prima la parte intera, quella che cambia
    lda pad_x+2,x
    cmp pad_home+2,x
    bne _fwd
    lda pad_x+3,x
    cmp pad_home+3,x
    bne _fwd
    lda pad_x+1,x
    cmp pad_home+1,x
    bne _fwd
    lda pad_x,x
    cmp pad_home,x
    bne _fwd
    txa
    bcs _sel                    ; (uguali: C = 1)
_fwd:
    txa
    clc
    adc #PAD_FWD_OFS
_sel:
    sta t1                      ; Y del massimo
    ldy pad_fast,x
    beq :+
    clc
    adc #pad_facc - pad_acc
:   tay
    ; velocità +/- accelerazione
    lda pad_dir,x
    bmi _down
    clc
    .repeat 4, k
    lda pad_speed+k,x
    adc pad_acc+k,y
    sta pad_speed+k,x
    .endrepeat
    jmp _clamp
_down:
    sec
    .repeat 4, k
    lda pad_speed+k,x
    sbc pad_acc+k,y
    sta pad_speed+k,x
    .endrepeat
_clamp:
    ; clamp(-max, max) con max >= 0 (il core lo richiede): una velocità >= 0 non è sotto -max e una
    ; negativa non è sopra max, e le due differenze qui sotto non traboccano. N dal byte alto.
    bmi _below
    ldy t1
    sec
    .repeat 4, k
    lda pad_max+k,y
    sbc pad_speed+k,x
    .endrepeat
    bpl _move                   ; max - v >= 0
    .repeat 4, k
    lda pad_max+k,y
    sta pad_speed+k,x
    .endrepeat
    jmp _move
_below:
    ldy t1
    clc
    .repeat 4, k
    lda pad_speed+k,x
    adc pad_max+k,y
    .endrepeat
    bpl _move                   ; v + max >= 0
    sec
    .repeat 4, k
    lda #0
    sbc pad_max+k,y
    sta pad_speed+k,x
    .endrepeat
_move:
    lda nx_btimer
    ora nx_lslow,x
    jne _slow
    add32 {pad_y,x}, {pad_y,x}, {pad_speed,x}   ; la y nuova (fuori dal campo si corregge sotto)
_moved:
    ; scarto veloce sulle parti intere (con segno, 16 bit): se y_int > metà_int la y non è sotto
    ; metà, e se y_int + metà_int + 2 <= H_int non è oltre H - metà; se no il confronto intero
    lda pad_half+2,x
    cmp pad_y+2,x
    lda pad_half+3,x
    sbc pad_y+3,x
    bvc :+
    eor #$80
:   bpl _full
    clc
    lda pad_y+2,x
    adc pad_half+2,x
    tay
    lda pad_y+3,x
    adc pad_half+3,x
    bvs _full
    cpy #<((P_HEIGHT >> 16) - 1)
    sbc #>((P_HEIGHT >> 16) - 1)
    bvc :+
    eor #$80
:   bpl _full
    jmp update_motion
_full:
    cmp32 {pad_y,x}, {pad_half,x}
    bpl :+
    mov32 {pad_y,x}, {pad_half,x}
    jmp _stop
:   sub32 t1, {#P_HEIGHT}, {pad_half,x}
    cmp32 t1, {pad_y,x}
    jpl update_motion
    mov32 {pad_y,x}, t1
_stop:
    lda #0
    sta pad_speed,x
    sta pad_speed+1,x
    sta pad_speed+2,x
    sta pad_speed+3,x
    jmp update_motion
_slow:
    mov32 s_v, {pad_speed,x}
    jsr pad_slow_shift_x
    jsr slow_v
    add32 {pad_y,x}, {pad_y,x}, s_v
    jmp _moved
_nodir:
    ; senza comando frena, e sotto la soglia si ferma. |v| <= max: v non è mai i32::MIN, e le
    ; differenze con la soglia non traboccano
    lda pad_speed+3,x
    bmi _neg
    sec                         ; v >= 0: si ferma se soglia - v >= 0
    .repeat 4, k
    lda #<(P_PAD_STOP >> (8 * k))
    sbc pad_speed+k,x
    .endrepeat
    bpl _zero
    sec
    .repeat 4, k
    lda pad_speed+k,x
    sbc #<(P_PAD_DECEL >> (8 * k))
    sta pad_speed+k,x
    .endrepeat
    bmi _zero
    jmp _move
_neg:
    clc                         ; v < 0: si ferma se v + soglia >= 0
    .repeat 4, k
    lda pad_speed+k,x
    adc #<(P_PAD_STOP >> (8 * k))
    .endrepeat
    bpl _zero
    clc
    .repeat 4, k
    lda pad_speed+k,x
    adc #<(P_PAD_DECEL >> (8 * k))
    sta pad_speed+k,x
    .endrepeat
    bpl _zero
    jmp _move
_zero:
    lda #0
    sta pad_speed,x
    sta pad_speed+1,x
    sta pad_speed+2,x
    sta pad_speed+3,x
    jmp _move
.endproc

; Paddle::motion += (y - y all'inizio del tick - motion) >> 2 (da pad_update, X = lato * 4). La
; somma di y all'inizio del tick e motion è già in pad_before (match_step).
.proc update_motion
    sec
    .repeat 3, k
    lda pad_y+k,x
    sbc pad_before+k,x
    sta t0+k
    .endrepeat
    lda pad_y+3,x
    sbc pad_before+3,x
    ; >> 2 con il segno, il byte alto in A
    .repeat 2
    cmp #$80
    ror a
    ror t0+2
    ror t0+1
    ror t0
    .endrepeat
    sta t0+3
    ora t0+2                    ; zero (racchetta ferma con motion tra -3 e 0): niente da sommare
    ora t0+1
    ora t0
    beq :+
    add32 {pad_motion,x}, {pad_motion,x}, t0
:   rts
.endproc

; Match::apply_input: comandi dei due giocatori (in singolo il muro non si muove).
.proc apply_input
    ldx #0
    jsr input_side
    lda m_players
    cmp #1
    beq :+
    ldx #4
    jsr input_side
:   rts
.endproc

.proc input_side
    stx side
    ; STEER: la racchetta resta ferma e su e giù guidano la palla
    lda m_next
    beq _normal
    lda nx_steer
    beq _normal
    lda nx_steer_s
    cmp side
    bne _normal
    jsr steer_store
    jmp _blaster
_normal:
    ; direzione cambiata, o rapido cambiato con la direzione premuta
    lda in_dir,x
    cmp pad_dir,x
    bne _set
    tay
    beq _offset
    lda in_flags,x
    and #IN_FAST
    cmp pad_fast,x
    beq _offset
_set:
    jsr set_direction           ; (X resta)
_offset:
    ; senza altri comandi che il rapido il resto non fa niente
    lda in_flags,x
    and #<~IN_FAST
    beq _done
    asl a                       ; IN_OFFSET
    bcc _blaster
    jsr set_paddle_top
_blaster:
    ; il BLASTER non ha lo scatto: spara con quel tasto (o con il comando di sparo)
    ldx side
    lda m_next
    beq _forward
    lda nx_kind,x
    cmp #K_BLASTER
    bne _forward
    lda in_flags,x
    and #IN_FIRE | IN_FORWARD
    beq _command
    stx n_side_x
    jsr next_fire
    jmp _command
_forward:
    lda in_flags,x
    and #IN_FORWARD
    beq _command
    jsr toggle_forward
_command:
    ; NEXT: seleziona e attiva i bonus
    ldx side
    lda m_next
    beq _done
    lda in_flags,x
    and #IN_SELECT | IN_ACTIVATE
    beq _done
    jsr next_command
_done:
    rts
.endproc

; Paddle::set_direction: invertendo la direzione resta un po' di slancio.
.proc set_direction
    or32 {pad_speed,x}
    beq _store
    lda in_dir,x
    beq _store
    eor pad_speed+3,x
    bpl _store
    mulq16 {#REVERSE_KEEP}, {pad_speed,x}   ; la costante (2 byte) come primo fattore
    ldx side
    mov32 {pad_speed,x}, m_a
_store:
    lda in_dir,x
    sta pad_dir,x
    lda in_flags,x
    and #IN_FAST
    sta pad_fast,x
    rts
.endproc

; Match::set_paddle_top: posizione dall'encoder (distanza in pixel dal bordo alto). Con il BULLET
; dell'avversario la racchetta segue la manopola rallentata, al massimo al passo del suo tipo o a
; quello di una mano veloce (P_ENC_HAND_STEP).
.proc set_paddle_top
    ; goal = (H - offset - metà altezza).clamp(metà, H - metà); H - offset tocca solo la parte
    ; intera (H è intera)
    sec
    lda #<(P_HEIGHT >> 16)
    sbc in_offset,x
    sta t0+2
    lda #>(P_HEIGHT >> 16)
    sbc #0
    sta t0+3
    lda #0
    sta t0
    sta t0+1
    sub32 t0, t0, {pad_half,x}
    cmp32 t0, {pad_half,x}
    bpl :+
    mov32 t0, {pad_half,x}
:   sub32 t1, {#P_HEIGHT}, {pad_half,x}
    cmp32 t1, t0
    bpl :+
    mov32 t0, t1
    ; i tipi lenti seguono la manopola con una velocità massima
:   mov32 s_v, {pad_step,x}
    lda nx_btimer
    ora nx_lslow,x
    beq _step
    jsr pad_slow_shift_x
    beq _step
    pha
    or32 s_v
    bne :+
    mov32 s_v, {#P_ENC_HAND_STEP}
:   pla
    jsr slow_v
_step:
    or32 s_v
    jeq _direct
    sub32 t0, t0, {pad_y,x}
    cmp32 s_v, t0
    bpl :+
    mov32 t0, s_v
    jmp _add
:   neg32 t1, s_v
    cmp32 t0, t1
    bpl _add
    mov32 t0, t1
_add:
    add32 t0, t0, {pad_y,x}
_direct:
    mov32 {pad_y,x}, t0
    lda #0
    sta pad_speed,x
    sta pad_speed+1,x
    sta pad_speed+2,x
    sta pad_speed+3,x
    rts
.endproc

; Match::toggle_forward: scatto in avanti (EVO) o ritorno a casa; se intercetta la palla la
; potenzia. In NEXT, avanti o indietro, segna nx_dash: le capsule di questo tick toccano tutto il
; tratto saltato (move_capsules).
.proc toggle_forward
    lda m_evo
    ora m_next
    bne :+
    rts
:   lda m_next
    beq :+
    sta nx_dash,x
:   beq32 {pad_x,x}, {pad_home,x}, _home
    mov32 {pad_x,x}, {pad_home,x}
    rts
_home:
    mov32 old_x, {pad_x,x}
    mov32 {pad_x,x}, {pad_fwd,x}
    jsr ball_in_forward_area
    bcc :+
    jsr forward_boost
    ; NEXT: lo scatto che intercetta la palla vale come colpo
    lda m_next
    beq :+
    ldx side
    sec
    jmp next_on_hit
:   rts
.endproc

; Match::ball_in_forward_area: C = 1 se lo scatto (da old_x a pad_x) prende la palla: è in arrivo
; tra la faccia di casa e quella avanzata e, nel tratto fino al retro della racchetta di casa
; percorso un tick alla volta (al massimo 64 passi, senza rimbalzi), passa all'altezza della
; racchetta: lo scatto non fa perdere le palle che la racchetta ferma avrebbe preso.
BIF_STEPS = 6                   ; passi del ciclo prima della forma chiusa
.proc ball_in_forward_area
    cpx #0
    jne _right
    ; sinistra: old_x + w/2 <= palla.sinistra <= x + w/2, palla verso sinistra
    lda ball_vx+3
    jpl _no
    sub32 t0, ball_x, ball_r
    add32 t1, old_x, {#HALF_W_FLOOR}
    cmp32 t0, t1
    jmi _no
    add32 t1, {pad_x,x}, {#HALF_W_FLOOR}
    cmp32 t1, t0
    jmi _no
    ; tratto: palla.destra - (old_x - w/2)
    add32 t0, ball_x, ball_r
    sub32 t0, t0, old_x
    jmp _path
_right:
    ; destra: x - w/2 <= palla.destra <= old_x - w/2, palla verso destra
    lda ball_vx+3
    jmi _no
    or32 ball_vx
    jeq _no
    add32 t0, ball_x, ball_r
    sub32 t1, {pad_x,x}, {#HALF_W_FLOOR}
    cmp32 t0, t1
    jmi _no
    sub32 t1, old_x, {#HALF_W_FLOOR}
    cmp32 t1, t0
    jmi _no
    ; tratto: (old_x + w/2) - palla.sinistra
    sub32 t0, old_x, ball_x
    add32 t0, t0, ball_r
_path:
    clc                         ; + w/2 (solo la parte intera)
    lda t0+2
    adc #<(HALF_W_FLOOR >> 16)
    sta t0+2
    lda t0+3
    adc #>(HALF_W_FLOOR >> 16)
    sta t0+3
    abs32 t2, ball_vx           ; passo
    ; all'altezza della racchetta: y - r <= alto e y + r >= basso, cioè (h + r) - (y - yr) e
    ; (h + r) + (y - yr) non negativi. Lungo il tratto uno dei due cresce di |vy| a ogni passo
    ; (t1), l'altro cala ed è 2(h + r) meno il primo: basta seguire t1. Come nel core, con lo
    ; stesso esito: al primo passo con t1 >= 0 la palla è presa se anche l'altro è >= 0, se no
    ; non lo sarà più; con vy = 0 t1 non cambia.
    add32 t_start, {pad_half,x}, ball_r
    sub32 t_rel, ball_y, {pad_y,x}
    abs32 cy, ball_vy
    lda ball_vy+3
    bmi :+
    add32 t1, t_start, t_rel
    jmp :++
:   sub32 t1, t_start, t_rel
:   asl32 t_start               ; 2(h + r)
    lda #64                     ; passi al massimo
    sta t_rel
    or32 cy                     ; vy = 0: t1 non cambia, conta solo il primo passo
    bne _loop
    lda #1
    sta t_rel
_loop:
    lda t1+3
    bmi _next
_band:
    sub32 t1, t_start, t1
    lda t1+3
    bmi _no
    sec
    rts
_no:
    clc
    rts
_next:
    lda t0+3                    ; tratto finito (<= 0)
    bmi _no
    ora t0+2
    ora t0+1
    ora t0
    beq _no
    sub32 t0, t0, t2
    add32 t1, t1, cy
    dec t_rel
    beq _no
    lda t_rel
    cmp #64 - BIF_STEPS
    bne _loop
    jmp bif_closed              ; (cpu.s, accanto a div8)
.endproc

; Match::forward_boost: lo scatto rilancia la palla più veloce (o annulla un boost più forte).
.proc forward_boost
    cmp32 ball_boost, {#P_BOOST_FWD_MUL}
    bpl _cancel
    mov32 ball_boost, {#P_BOOST_FWD_MUL}
    mov32 ball_r, {#P_BALL_R_FWD}
    event EV_BOOST
    jmp _push
_cancel:
    mov32 ball_boost, {#ONE}
    mov32 ball_r, {#P_BALL_R}
    event EV_HIT
_push:
    ; mul(|vx|, 6/5) = |vx| + (|vx| * (6/5 - ONE)) >> 16 (|vx| >= 0, il prodotto per ONE è esatto):
    ; un prodotto senza segno con il fattore di due byte, |vx| sulle righe (umul32 lascia m_b)
    abs32 m_b, ball_vx
    lda #<(FWD_PUSH - ONE)
    sta m_a
    lda #>(FWD_PUSH - ONE)
    sta m_a+1
    lda #0
    sta m_a+2
    sta m_a+3
    jsr umul32
    clc
    .repeat 4, k
    lda m_b+k
    adc m_p+2+k
    sta ball_vx+k
    .endrepeat
    lda #KC_WAIT                ; vx nuovo: il suo prodotto per il prossimo colpo (kc_fill)
    sta kc_wait
    ldx side
    beq _vy
    neg32 ball_vx, ball_vx
    ; vy += mul(rng.unit(), serve_unit)
    ; unit = u - (0 o ONE), u = i 16 bit bassi di t0; serve_unit < ONE. P = serve_unit * u (32 bit,
    ; in t1). Con unit >= 0 il prodotto è P >> 16; con unit < 0 è -((serve_unit * (ONE - u)) >> 16)
    ; = ceil(P / ONE) - serve_unit (tra -serve_unit e 0)
_vy:
    jsr rng_unit
    lda #<P_SERVE_UNIT          ; tabelle sul byte basso di serve_unit
    sta sq1_lo
    sta sq1_hi
    eor #$ff
    sta sq2_lo
    sta sq2_hi
    ldy t0                      ; s0 * u0: byte 0 e 1
    sec
    lda (sq1_lo),y
    sbc (sq2_lo),y
    sta t1
    lda (sq1_hi),y
    sbc (sq2_hi),y
    sta t1+1
    ldy t0+1                    ; s0 * u1: byte 1 e 2
    sec
    lda (sq1_lo),y
    sbc (sq2_lo),y
    tax
    lda (sq1_hi),y
    sbc (sq2_hi),y
    sta t1+2
    txa
    clc
    adc t1+1
    sta t1+1
    bcc :+
    inc t1+2                    ; (alto al più $FE)
:   lda #>P_SERVE_UNIT          ; tabelle sul byte alto
    sta sq1_lo
    sta sq1_hi
    eor #$ff
    sta sq2_lo
    sta sq2_hi
    ldy t0                      ; s1 * u0: byte 1 e 2 (riporto nel 3)
    sec
    lda (sq1_lo),y
    sbc (sq2_lo),y
    tax
    lda (sq1_hi),y
    sbc (sq2_hi),y
    sta t1+3
    txa
    clc
    adc t1+1
    sta t1+1
    lda t1+3
    adc t1+2
    sta t1+2
    lda #0
    rol a
    sta t1+3
    ldy t0+1                    ; s1 * u1: byte 2 e 3
    sec
    lda (sq1_lo),y
    sbc (sq2_lo),y
    tax
    lda (sq1_hi),y
    sbc (sq2_hi),y
    tay
    txa
    clc
    adc t1+2
    sta t1+2
    tya
    adc t1+3
    sta t1+3
    lda t0+3
    bmi _neg
    clc                         ; vy += P >> 16
    lda ball_vy
    adc t1+2
    sta ball_vy
    lda ball_vy+1
    adc t1+3
    sta ball_vy+1
    lda #0
    tay                         ; (estensione: 0)
    beq _hi
_neg:
    lda t1                      ; C = 1 se P non è multiplo di ONE
    ora t1+1
    cmp #1
    lda t1+2                    ; + ceil(P / ONE) + (ONE - serve_unit), a 16 bit
    adc #<(ONE - P_SERVE_UNIT)
    tax
    lda t1+3
    adc #>(ONE - P_SERVE_UNIT)
    tay
    lda #0                      ; riporto: valore 0, altrimenti negativo ($FF)
    sbc #0
    pha
    clc
    txa
    adc ball_vy
    sta ball_vy
    tya
    adc ball_vy+1
    sta ball_vy+1
    pla
    tay
_hi:
    tya
    adc ball_vy+2
    sta ball_vy+2
    tya
    adc ball_vy+3
    sta ball_vy+3
    ; la palla presa tra la posizione di casa e quella avanzata riparte dalla faccia della
    ; racchetta (già avanzata), non da dietro: a sinistra x = max(x, destra + r), a destra
    ; x = min(x, sinistra - r). Racchetta, metà larghezza e raggio sono interi: il bordo F (in
    ; t1+2, t1+3) è un pixel intero e il confronto con x si fa sulla parte intera (a destra con la
    ; frazione: x > F)
    lda ball_r+2
    clc
    adc #<(P_PAD_HALF_W >> 16)
    sta m_t                     ; r + w/2
    ldx side
    bne _right
    clc
    lda pad_x+2
    adc m_t
    sta t1+2
    lda pad_x+3
    adc #0
    sta t1+3
    sec                         ; int(x) < F: x = F
    lda ball_x+2
    sbc t1+2
    lda ball_x+3
    sbc t1+3
    bvc :+
    eor #$80
:   bmi _face
    rts
_right:
    sec
    lda pad_x+4+2
    sbc m_t
    sta t1+2
    lda pad_x+4+3
    sbc #0
    sta t1+3
    sec                         ; F - x < 0: x = F
    lda #0
    sbc ball_x
    lda #0
    sbc ball_x+1
    lda t1+2
    sbc ball_x+2
    lda t1+3
    sbc ball_x+3
    bvc :+
    eor #$80
:   bpl _done
_face:
    lda #0
    sta ball_x
    sta ball_x+1
    lda t1+2
    sta ball_x+2
    lda t1+3
    sta ball_x+3
_done:
    rts
.endproc
.assert FWD_PUSH > ONE .and FWD_PUSH - ONE < $10000, error, "forward_boost: 6/5 - ONE in due byte"
.assert P_SERVE_UNIT > 0 .and P_SERVE_UNIT < ONE, error, "forward_boost: serve_unit in due byte"

; t0 = Rng::unit(): (x >> 15) - ONE, valore in [-1, 1)
.proc rng_unit
    jsr rng_next
    lda rng+1
    asl a
    lda rng+2
    rol a
    sta t0
    lda rng+3
    rol a
    sta t0+1
    lda #0
    rol a                       ; bit 31 (C = 0)
    sbc #0                      ; - ONE: bit - 1, cioè 0 o $FF, anche nel byte alto
    sta t0+2
    sta t0+3
    rts
.endproc

; ------------------------------------------------------------------------------------ palla

; Scarti veloci di ball_tick sulle parti intere: con la parte intera della y tra Y_LOW e Y_HIGH la
; palla (raggio al più BALL_R_MAX) non tocca i bordi alto e basso, con quella della x tra X_LOW e
; X_HIGH non è oltre i bordi sinistro e destro.
Y_LOW  = ((ONE + BALL_R_MAX) >> 16) + 1
Y_HIGH = ((P_HEIGHT - ONE - BALL_R_MAX) >> 16) - 1
X_LOW  = (BALL_R_MAX >> 16) + 1
X_HIGH = ((P_WIDTH - BALL_R_MAX) >> 16) - 1
.assert Y_LOW <= Y_HIGH .and Y_HIGH < 255 .and X_LOW < 256 .and X_HIGH >= 256 .and X_HIGH < $7FFF, error, "ball_tick: soglie"

; Parte del tick dopo l'attesa della battuta: movimento, bordi, contatto o punto.
.proc ball_tick
    ; il prodotto di vx per il prossimo colpo, KC_WAIT tick dopo il colpo o la battuta (kc_fill)
    lda kc_wait
    beq :+
    dec kc_wait
    bne :+
    jsr kc_fill
:   ; dx = mul(vx, boost): con boost 1 è vx; altrimenti il prodotto tenuto da parte se vx e boost
    ; sono quelli dell'ultima volta (vx_boost)
    beq32 ball_boost, {#ONE}, _unit
    jsr vx_boost_mul
    mov32 t0, m_a
    jmp _move
_unit:
    mov32 t0, ball_vx
_move:
    lda m_next
    beq _plain
    jsr next_ball_motion
    lda nx_btimer
    beq _plain
    mov32 prev_y, ball_y
    jsr ball_slowed             ; BULLET: passo rallentato
    jmp _x
_plain:
    clc                         ; y += vy, con la y di prima in prev_y
    .repeat 4, k
    lda ball_y+k
    sta prev_y+k
    adc ball_vy+k
    sta ball_y+k
    .endrepeat
_x:
    clc                         ; x += dx, e ball_dx = dx
    .repeat 4, k
    lda t0+k
    sta ball_dx+k
    adc ball_x+k
    sta ball_x+k
    .endrepeat
    ; bordo alto e basso: lontano da tutti e due niente rimbalzo (né curva da invertire)
    lda ball_y+3
    bne _walls
    lda ball_y+2
    cmp #Y_LOW
    bcc _walls
    cmp #Y_HIGH + 1
    jcc _pick
_walls:
    add32 t1, ball_y, ball_r
    cmp32 t1, {#P_HEIGHT - ONE}
    bmi _bottom
    sub32 ball_y, {#P_HEIGHT - ONE}, ball_r
    abs32 t1, ball_vy
    neg32 ball_vy, t1
    event EV_WALL
    jmp _side
_bottom:
    sub32 t1, ball_y, ball_r
    cmp32 {#ONE}, t1
    bmi _side
    add32 ball_y, {#ONE}, ball_r
    abs32 ball_vy, ball_vy
    event EV_WALL
_side:
    ; NEXT: al rimbalzo sul bordo la curva si inverte con la palla
    lda m_next
    beq :+
    lda events
    and #EV_WALL
    beq :+
    neg32 nx_curve, nx_curve
:
_pick:
    ; racchetta verso cui va la palla
    ldx #0
    lda ball_vx+3
    bmi :+
    ldx #4
:   stx side
    jsr contact
    bcc _miss
    mov32 ball_y, cy
    jsr bounce
    lda m_next
    bne :+
    rts
:   ldx side
    clc
    jmp next_on_hit
_miss:
    ; NEXT: la barriera del GUARDIAN rimanda la palla mancata
    lda m_next
    beq _points
    ldx side
    jsr next_barrier
    bcc _points
    event_hi EV_BARRIER_HI
    rts
_points:
    ; palla oltre il bordo sinistro o destro: punto. Prima lo scarto veloce sulla parte intera
    lda ball_x+3
    bmi _edge
    bne :+
    lda ball_x+2
    cmp #X_LOW
    bcs _none                   ; (X_HIGH oltre 255)
    bcc _edge
:   lda ball_x+2
    cmp #<(X_HIGH + 1)
    lda ball_x+3
    sbc #>(X_HIGH + 1)
    bcc _none
_edge:
    sub32 t0, ball_x, ball_r
    lda t0+3
    bmi _right_scores
    or32 t0
    beq _right_scores
    add32 t0, ball_x, ball_r
    cmp32 t0, {#P_WIDTH}
    bmi :+
    lda #0
    jmp point
_right_scores:
    lda #4
    jmp point
:
_none:
    rts
.endproc

; Raggio massimo della palla: ball_r prende solo questi valori.
BALL_R_MAX = .max(.max(P_BALL_R, P_BALL_R_BOOST), P_BALL_R_FWD)
; Scarto veloce di contact: con parti intere (x della palla, x della racchetta) che distano almeno
; C_FAR, la distanza vera supera (C_FAR - 1) * ONE >= BALL_R_MAX + P_PAD_HALF_W e la palla sta
; tutta davanti alla faccia: né attraversata né sovrapposta.
C_FAR = ((BALL_R_MAX + P_PAD_HALF_W + ONE - 1) >> 16) + 1
.assert C_FAR < 256, error, "contact: C_FAR in un byte"

; N = 1 se a < b, con a e b a 16 bit con il segno (byte basso e alto)
.macro cmp16 alo, ahi, blo, bhi
    .local ok
    lda alo
    cmp blo
    lda ahi
    sbc bhi
    bvc ok
    eor #$80
ok:
.endmacro

; N = 1 se K < v, con K un numero intero di pixel (16 bit con il segno) e v a 32 bit: il segno di
; K * ONE - v, dove la frazione di v dà solo il prestito
.macro cmpk16 klo, khi, v
    .local ok
    sec
    lda #0
    sbc v
    lda #0
    sbc v+1
    lda klo
    sbc v+2
    lda khi
    sbc v+3
    bvc ok
    eor #$80
ok:
.endmacro

; Match::contact: C = 1 se la palla tocca la racchetta X nell'ultimo spostamento, con la y del
; contatto in cy (punto medio dello spostamento se il bordo della palla ha attraversato la
; faccia, altrimenti la y della palla). Con C = 0 non lascia niente che altri leggano.
; Racchetta (x), metà larghezza e raggio sono pixel interi: i confronti sulla x si fanno sulle
; parti intere (16 bit), con la frazione solo dove decide (v > K: K - v < 0).
.proc contact
    cpx #0
    jne _right
    ; sinistra: palla lontana davanti alla faccia (parti intere, 16 bit con segno)
    sec
    lda ball_x+2
    sbc pad_x+2
    tay
    lda ball_x+3
    sbc pad_x+3
    bvs :++
    bmi :++
    bne :+
    cpy #C_FAR
    bcc :++
:   clc
    rts
:   ; se la palla era già dietro la racchetta niente
    sub32 prev_x, ball_x, ball_dx           ; x prima dello spostamento
    cmp16 prev_x+2, prev_x+3, pad_x+2, pad_x+3
    jmi _no                                 ; (la racchetta è intera)
    jsr reach                               ; K = faccia + r
    cmpk16 t2, t2+1, ball_x
    jmi _no                                 ; tutta davanti (x > K): né attraversata né sovrapposta
    cmp16 prev_x+2, prev_x+3, t2, t2+1
    jmi _overlap                            ; prima era già oltre la faccia (x di prima < K)
    cmp16 ball_x+2, ball_x+3, t2, t2+1
    jpl _overlap                            ; bordo sulla faccia (x >= K): non attraversata
    jmp _crossed
_right:
    sec
    lda pad_x+4+2
    sbc ball_x+2
    tay
    lda pad_x+4+3
    sbc ball_x+3
    bvs :++
    bmi :++
    bne :+
    cpy #C_FAR
    bcc :++
:   clc
    rts
:   sub32 prev_x, ball_x, ball_dx
    cmpk16 pad_x+4+2, pad_x+4+3, prev_x
    jmi _no                                 ; x di prima oltre la racchetta
    jsr reach                               ; K = faccia - r
    cmp16 ball_x+2, ball_x+3, t2, t2+1
    jmi _no                                 ; x < K
    cmpk16 t2, t2+1, prev_x
    jmi _overlap                            ; x di prima > K
    cmpk16 t2, t2+1, ball_x
    jpl _overlap                            ; x <= K
_crossed:
    add32 cy, prev_y, ball_y
    asr32 cy
    ; alto e basso della racchetta allargati del raggio, una volta per i due controlli:
    ; y - r <= alto e y + r >= basso sono y <= alto + r e y >= basso - r
    jsr band
    cmp32 t_start, cy
    bmi _side
    cmp32 cy, t_rel
    bmi _side
    sec
    rts
_overlap:
    ; sovrapposizione semplice: il bordo verso la faccia non la supera
    jsr band
_side:
    ; l'altro bordo della palla e l'altro lato della racchetta: a sinistra x + r < racchetta - w/2,
    ; cioè int(x) < racchetta - (w/2 + r); a destra x > racchetta + w/2 + r
    cpx #0
    bne :+
    sec
    lda pad_x+2
    sbc m_t
    sta t2
    lda pad_x+3
    sbc #0
    sta t2+1
    cmp16 ball_x+2, ball_x+3, t2, t2+1
    jmi _no
    jmp _y
:   clc
    lda pad_x+4+2
    adc m_t
    sta t2
    lda pad_x+4+3
    adc #0
    sta t2+1
    cmpk16 t2, t2+1, ball_x
    jmi _no
_y:
    cmp32 t_start, ball_y
    jmi _no
    cmp32 ball_y, t_rel
    jmi _no
    mov32 cy, ball_y
    sec
    rts
reach:
    ; m_t = w/2 + r; K (t2, 16 bit) = racchetta + m_t a sinistra, - m_t a destra (pixel interi)
    lda ball_r+2
    clc
    adc #<(P_PAD_HALF_W >> 16)
    sta m_t
    cpx #0
    bne :+
    clc
    lda pad_x+2
    adc m_t
    sta t2
    lda pad_x+3
    adc #0
    sta t2+1
    rts
:   sec
    lda pad_x+4+2
    sbc m_t
    sta t2
    lda pad_x+4+3
    sbc #0
    sta t2+1
    rts
band:
    ; t_start = y racchetta + (metà + r), t_rel = y racchetta - (metà + r) (r intero: byte 2 e 3)
    clc
    lda pad_half+2,x
    adc ball_r+2
    sta t0+2
    lda pad_half+3,x
    adc #0
    sta t0+3
    lda pad_half,x
    sta t0
    lda pad_half+1,x
    sta t0+1
    add32 t_start, {pad_y,x}, t0
    sub32 t_rel, {pad_y,x}, t0
    rts
_no:
    clc
    rts
.endproc

; Match::reflection: velocità verticale data dalla racchetta X, sommata subito a vy (b.vy +=
; reflection: solo bounce la chiama); in_area = 1 se la palla è dentro l'area boost EVO.
.proc reflection
    lda #0
    sta in_area
    lda m_evo
    bne :+
    jmp _plain
    ; EVO: nell'area boost la riflessione è smorzata
:   or32 {pad_bh,x}
    bne :+
    jmp _plain
:   sub32 t0, {pad_h,x}, {pad_bh,x}
    asr32 t0
    floor32 t_start, t0
    mov32 t0, {pad_h,x}
    asr32 t0
    floor32 t0, t0
    sub32 t0, {pad_y,x}, t0
    sub32 t_rel, ball_y, t0
    cmp32 t_rel, t_start
    bpl :+
    jmp _plain
:   add32 t0, t_start, {pad_bh,x}
    cmp32 t0, t_rel
    bpl :+
    jmp _plain
    ; centro dell'area
:   mov32 t0, {pad_bh,x}
    asr32 t0
    floor32 t0, t0
    add32 t0, t_start, t0
    sub32 m_b, t_rel, t0        ; fattori del prodotto direttamente in m_a e m_b
    lda pad_level,x
    asl a
    asl a
    tay
    mov32 t1, {boost_inv_tab,y}
    lda #1
    sta in_area
    abs32 m_a, ball_vx          ; velocità
    jsr mul_q16
    mov32 m_b, t1
    jsr mul_q24
    ; * ONE / 5: la costante (2 byte) come primo fattore, il prodotto salta due righe
    mov32 m_b, m_a
    mov32 m_a, {#DAMP_BOOST}
    jsr mul_q16
    add32 ball_vy, ball_vy, m_a
    ldx side
    rts
_plain:
    ; mul_recip(mul(|vx|, dy), inv) con un solo segno, quello di dy: |vx| e inv sono positivi, e
    ; con il troncamento verso lo zero il valore assoluto del primo prodotto è (|vx| |dy|) >> 16
    ; (se è zero anche il risultato lo è, con qualunque segno)
    abs32 m_a, ball_vx          ; velocità
    sec
    .repeat 4, k
    lda ball_y+k
    sbc pad_y+k,x
    sta m_b+k
    .endrepeat
    sta m_sign
    bpl :+
    neg32 m_b, m_b
:   jsr umul32
    mov32 m_a, {m_p+2}
    ldx side
    mov32 m_b, {pad_inv,x}
    jsr umul32
    ldx side
    lda m_sign                  ; vy + reflection: + o - (|vx| |dy| >> 16) * inv >> 24
    bmi :+
    add32 ball_vy, ball_vy, {m_p+3}
    rts
:   sub32 ball_vy, ball_vy, {m_p+3}
    rts
.endproc

; Match::bounce: la racchetta X respinge la palla.
.proc bounce
    jsr reflection              ; (vy += reflection)
    ; mai più ripida di 45 gradi
    abs32 t0, ball_vx
    abs32 t1, ball_vy
    cmp32 t0, t1
    bpl _angle
    lda ball_vy+3
    bmi :+
    mov32 ball_vy, t0
    jmp _angle
:   neg32 ball_vy, t0
_angle:
    ; EVO: la palla normale colpita dentro l'area boost (la banda grigia) parte potenziata
    lda m_evo
    beq _hit
    lda in_area
    beq _hit
    beq32 ball_boost, {#ONE}, :+
    jmp _hit
:   mov32 ball_boost, {#P_BOOST_MUL}
    mov32 ball_r, {#P_BALL_R_BOOST}
    ; l'area si restringe
    lda pad_level,x
    clc
    adc #1
    cmp #P_BOOST_LEVELS
    bcc :+
    lda #P_BOOST_LEVELS - 1
:   sta pad_level,x
    asl a
    asl a
    tay
    mov32 {pad_bh,x}, {boost_h_tab,y}
    event EV_BOOST
    jmp _place
_hit:
    mov32 ball_boost, {#ONE}
    mov32 ball_r, {#P_BALL_R}
    event EV_HIT
_place:
    ; (t0 resta |vx|, che il cambio di segno non tocca: serve sotto). Racchetta, metà larghezza e
    ; raggio (appena scritto) sono interi: la x nuova è un pixel intero
    lda ball_r+2
    clc
    adc #<(P_PAD_HALF_W >> 16)
    sta m_t
    lda #0
    sta ball_x
    sta ball_x+1
    cpx #0
    bne :+
    clc
    lda pad_x+2
    adc m_t
    sta ball_x+2
    lda pad_x+3
    adc #0
    sta ball_x+3
    jmp _flip
:   sec
    lda pad_x+4+2
    sbc m_t
    sta ball_x+2
    lda pad_x+4+3
    sbc #0
    sta ball_x+3
_flip:
    neg32 ball_vx, ball_vx
    ; in singolo il muro rimanda la palla senza accelerarla e vale un punto
    lda m_players
    cmp #1
    bne _speed
    cpx #4
    bne _speed
    lda score
    and score+1
    cmp #$FF
    beq :+
    inc score
    bne :+
    inc score+1
:   rts
_speed:
    cmp32 t0, max_ball          ; |vx|
    bpl :+
    jsr kspeed_mul              ; vx e vy
    lda #KC_WAIT                ; vx nuovo: il suo prodotto per il prossimo colpo (kc_fill)
    sta kc_wait
:   ldx side
    rts
.endproc

; v = mul(v, kspeed) per v = ball_vx e ball_vy (X = 0 e 4 in one). kspeed è tra ONE e 2 ONE (tabelle
; sotto), e con il troncamento verso lo zero mul(v, k) = v + mul(v, k - ONE) = v +/- (|v| * (k - ONE))
; >> 16 (come mul_q16: i 32 bit bassi del valore assoluto, col segno di v). Il fattore k - ONE ha due
; byte e, primo fattore di umul32 (che lo lascia: si mette una volta), fa saltare due righe del
; prodotto.
;
; Nel colpo (bounce) |vx| è in t0 e il prodotto di vx è quasi sempre già pronto: kc_fill lo fa
; KC_WAIT tick dopo il colpo di prima o la battuta, in un tick leggero (nel primo dopo il colpo la
; CPU che riceve rifà velocità e soglia della mancata, nel secondo l'errore di mira), e lo tiene
; con il suo |vx| (kc_v; match_new lo annulla, perché cambia kspeed). Con un altro |vx| (un bonus
; ha cambiato la palla) si calcola qui. Lo stesso prodotto, lo stesso risultato: il tick del colpo
; risparmia una moltiplicazione.
KC_WAIT = 3
.proc kspeed_mul
    lda kspeed
    sta m_a
    lda kspeed+1
    sta m_a+1
    lda #0
    sta m_a+2
    sta m_a+3
    .repeat 4, k
    lda t0+k                    ; |vx|
    cmp kc_v+k
    bne calc
    .endrepeat
    lda ball_vx+3
    bmi :+
    clc
    .repeat 4, k
    lda ball_vx+k
    adc kc_p+k
    sta ball_vx+k
    .endrepeat
    jmp vy
:   sec
    .repeat 4, k
    lda ball_vx+k
    sbc kc_p+k
    sta ball_vx+k
    .endrepeat
    jmp vy
calc:
    ldx #0                      ; vx
    jsr one
vy:
    ldx #4                      ; vy
one:
    stx t2
    lda ball_vx+3,x
    bmi _neg
    .repeat 4, k
    lda ball_vx+k,x
    sta m_b+k
    .endrepeat
    jsr umul32
    ldx t2
    clc
    .repeat 4, k
    lda ball_vx+k,x
    adc m_p+2+k
    sta ball_vx+k,x
    .endrepeat
    rts
_neg:
    sec
    .repeat 4, k
    lda #0
    sbc ball_vx+k,x
    sta m_b+k
    .endrepeat
    jsr umul32
    ldx t2
    sec
    .repeat 4, k
    lda ball_vx+k,x
    sbc m_p+2+k
    sta ball_vx+k,x
    .endrepeat
    rts
.endproc
.assert ball_vy = ball_vx + 4, error, "kspeed_mul: vx e vy consecutive"

; Il prodotto di vx per il prossimo colpo: kc_p = (|vx| * (kspeed - ONE)) >> 16 (i byte 2-5, come
; one in kspeed_mul) e kc_v = |vx| (wrapping, come abs32 di bounce). Usa m_a, m_b, m_p, m_t
; (ball_tick, all'inizio, dove non servono a nessuno). Codice corto: gira una volta per colpo.
.proc kc_fill
    lda kspeed
    sta m_a
    lda kspeed+1
    sta m_a+1
    lda #0
    sta m_a+2
    sta m_a+3
    ; m_b = |vx| = (vx eor s) - s, s = $FF con vx < 0 (il -s entra come riporto): X da $FC a $FF,
    ; gli indirizzi in pagina zero + 4 + X tornano su ball_vx e m_b (zp,x resta in pagina zero)
    lda ball_vx+3
    asl a                       ; C = segno
    lda #0
    adc #$FF
    eor #$FF
    sta m_t                     ; s
    asl a                       ; C = segno
    ldx #$FC
:   lda ball_vx+4,x
    eor m_t
    adc #0
    sta m_b+4,x
    inx
    bne :-
    jsr umul32                  ; (m_b resta)
    ldx #3
:   lda m_b,x
    sta kc_v,x
    lda m_p+2,x
    sta kc_p,x
    dex
    bpl :-
    rts
.endproc
.assert ball_vx + 4 < $100 .and m_b + 4 < $100, error, "kc_fill: ball_vx e m_b in pagina zero"
.macro kspeed_check k0, k1, k2, k3
    .assert k0 >= ONE .and k0 < 2 * ONE .and k1 >= ONE .and k1 < 2 * ONE, error, "kspeed fuori da [ONE, 2 ONE)"
    .assert k2 >= ONE .and k2 < 2 * ONE .and k3 >= ONE .and k3 < 2 * ONE, error, "kspeed fuori da [ONE, 2 ONE)"
.endmacro
kspeed_check T_KSPEED_1P
kspeed_check T_KSPEED_2P
kspeed_check T_KSPEED_NEXT

; Match::point: punto del lato A (0 sinistra, 4 destra), poi la battuta verso chi l'ha subito.
.proc point
    sta scorer
    lda m_players
    cmp #2
    bne _single
    ldx scorer
    lda score,x
    and score+1,x
    cmp #$FF
    beq :+
    inc score,x
    bne :+
    inc score+1,x
    ; l'area boost torna intera
:   jsr boost_reset
    jmp _serve
_single:
    ; record e punteggio azzerato
    lda best+1
    cmp score+1
    bcc _record
    bne _reset
    lda best
    cmp score
    bcs _reset
_record:
    lda score
    sta best
    lda score+1
    sta best+1
_reset:
    lda #0
    sta score
    sta score+1
_serve:
    event EV_SCORE
    lda m_next
    beq :+
    jsr next_on_point
:   lda scorer
    eor #4
    jmp serve
.endproc
