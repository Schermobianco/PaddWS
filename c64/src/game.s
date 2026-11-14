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
t_refl: .res 4
t_speed: .res 4
t_start: .res 4
t_rel:  .res 4
prev_x: .res 4
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
pad_before: .res 8      ; y all'inizio del tick

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
    ldx #0
_pad:
    mov32 {pad_y,x}, {#P_HEIGHT / 2}
    mov32 {pad_h,x}, {#P_PAD_H}
    mov32 {pad_inv,x}, {#P_PAD_INV_HALF}
    mov32 {pad_bh,x}, boost_h_tab
    mov32 {pad_max,x}, {#P_PAD_MAX}
    mov32 {pad_acc,x}, {#P_PAD_ACC}
    mov32 {pad_facc,x}, {#P_PAD_FACC}
    mov32 {pad_fmax,x}, {#P_PAD_MAX}
    mov32 {pad_fwacc,x}, {#P_PAD_ACC}
    mov32 {pad_fwfacc,x}, {#P_PAD_FACC}
    lda #0
    ldy #4
:   sta pad_speed,x
    sta pad_motion,x
    sta pad_step,x
    sta pad_level,x
    sta pad_dir,x
    sta pad_fast,x
    inx
    dey
    bne :-
    cpx #8
    jne _pad
    mov32 pad_x, {#P_PAD_START}
    mov32 pad_home, {#P_PAD_START}
    mov32 pad_fwd, {#P_PAD_FWD}
    mov32 pad_x+4, {#P_WIDTH - P_PAD_START}
    mov32 pad_home+4, {#P_WIDTH - P_PAD_START}
    mov32 pad_fwd+4, {#P_WIDTH - P_PAD_FWD}
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
    ; palla al centro, ferma
    mov32 ball_x, {#P_WIDTH / 2}
    mov32 ball_y, {#P_HEIGHT / 2}
    mov32 ball_r, {#P_BALL_R}
    mov32 ball_boost, {#ONE}
    lda #0
    ldx #3
:   sta ball_vx,x
    sta ball_vy,x
    sta ball_dx,x
    sta serve_timer,x
    sta tick,x
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
    mov32 pad_before, pad_y
    mov32 pad_before+4, pad_y+4
    jsr apply_input
    ldx #0
    jsr pad_update
    jsr update_motion
    ldx #4
    jsr pad_update
    jsr update_motion
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

; Paddle::motion += (y - y all'inizio del tick - motion) >> 2
.proc update_motion
    sub32 t0, {pad_y,x}, {pad_before,x}
    sub32 t0, t0, {pad_motion,x}
    asr32 t0
    asr32 t0
    add32 {pad_motion,x}, {pad_motion,x}, t0
    rts
.endproc

; Paddle::update: accelerazione o frenata, poi il movimento entro il campo. Con il BULLET
; dell'avversario il passo è rallentato (la velocità no).
.proc pad_update
    stx side
    lda pad_dir,x
    bne :+
    jmp _nodir
    ; a casa o avanzata: valori diversi (RUSH)
:   beq32 {pad_x,x}, {pad_home,x}, _home
    mov32 t1, {pad_fmax,x}
    lda pad_fast,x
    beq :+
    mov32 t0, {pad_fwfacc,x}
    jmp _acc
:   mov32 t0, {pad_fwacc,x}
    jmp _acc
_home:
    mov32 t1, {pad_max,x}
    lda pad_fast,x
    beq :+
    mov32 t0, {pad_facc,x}
    jmp _acc
:   mov32 t0, {pad_acc,x}
_acc:
    lda pad_dir,x
    bpl :+
    neg32 t0, t0
:   add32 {pad_speed,x}, {pad_speed,x}, t0
    ; clamp(-max, max)
    cmp32 t1, {pad_speed,x}
    bpl :+
    mov32 {pad_speed,x}, t1
    jmp _move
:   neg32 t1, t1
    cmp32 {pad_speed,x}, t1
    jpl _move
    mov32 {pad_speed,x}, t1
    jmp _move
_nodir:
    ; senza comando frena, e sotto la soglia si ferma
    abs32 t0, {pad_speed,x}
    cmp32 {#P_PAD_STOP}, t0
    bpl _zero
    lda pad_speed+3,x
    bmi _neg
    sub32 {pad_speed,x}, {pad_speed,x}, {#P_PAD_DECEL}
    lda pad_speed+3,x
    bpl _move
    jmp _zero
_neg:
    add32 {pad_speed,x}, {pad_speed,x}, {#P_PAD_DECEL}
    lda pad_speed+3,x
    bmi _move
_zero:
    lda #0
    sta pad_speed,x
    sta pad_speed+1,x
    sta pad_speed+2,x
    sta pad_speed+3,x
_move:
    lda nx_btimer
    jne _slow
    add32 t0, {pad_y,x}, {pad_speed,x}
_moved:
    cmp32 t0, {pad_half,x}
    bpl :+
    mov32 {pad_y,x}, {pad_half,x}
    jmp _stop
:   sub32 t1, {#P_HEIGHT}, {pad_half,x}
    cmp32 t1, t0
    bpl :+
    mov32 {pad_y,x}, t1
    jmp _stop
:   mov32 {pad_y,x}, t0
    rts
_stop:
    lda #0
    sta pad_speed,x
    sta pad_speed+1,x
    sta pad_speed+2,x
    sta pad_speed+3,x
    rts
_slow:
    mov32 s_v, {pad_speed,x}
    jsr bullet_shift_x
    jsr slow_v
    add32 t0, {pad_y,x}, s_v
    jmp _moved
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
    lda in_dir,x
    beq _offset
    lda in_flags,x
    and #IN_FAST
    cmp pad_fast,x
    beq _offset
_set:
    jsr set_direction
_offset:
    ldx side
    lda in_flags,x
    bpl _blaster
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
    ldx side
    lda in_flags,x
    and #IN_FORWARD
    beq _command
    jsr toggle_forward
_command:
    ; NEXT: seleziona e attiva i bonus
    ldx side
    lda m_next
    beq :+
    lda in_flags,x
    and #IN_SELECT | IN_ACTIVATE
    beq :+
    jsr next_command
:   rts
.endproc

; Paddle::set_direction: invertendo la direzione resta un po' di slancio.
.proc set_direction
    or32 {pad_speed,x}
    beq _store
    lda in_dir,x
    beq _store
    eor pad_speed+3,x
    bpl _store
    mulq16 {pad_speed,x}, {#REVERSE_KEEP}
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
    lda #0
    sta t0
    sta t0+1
    sta t0+3
    lda in_offset,x
    sta t0+2
    ; goal = (H - offset - metà altezza).clamp(metà, H - metà)
    sub32 t0, {#P_HEIGHT}, t0
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
    beq _step
    jsr bullet_shift_x
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
    sub32 t1, t_start, t1
    lda t1+3
    bmi _no
    sec
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
    bne _loop
_no:
    clc
    rts
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
    abs32 t0, ball_vx
    mulq16 t0, {#FWD_PUSH}
    ldx side
    bne :+
    mov32 ball_vx, m_a
    jmp _vy
:   neg32 ball_vx, m_a
    ; vy += mul(rng.unit(), serve_unit)
_vy:
    jsr rng_unit
    mulq16 t0, {#P_SERVE_UNIT}
    add32 ball_vy, ball_vy, m_a
    ; la palla presa tra la posizione di casa e quella avanzata riparte dalla faccia della
    ; racchetta (già avanzata), non da dietro: a sinistra x = max(x, destra + r), a destra
    ; x = min(x, sinistra - r). Cicli sui 4 byte: tya e and non toccano il riporto.
    ldy #0                      ; t1 = r + w/2
    clc
:   lda ball_r,y
    adc half_w,y
    sta t1,y
    iny
    tya
    and #3
    bne :-
    lda #$79                    ; adc abs,y: a sinistra t0 = racchetta + t1
    ldx side
    clc
    beq :+
    lda #$f9                    ; sbc abs,y: a destra racchetta - t1
    sec
:   sta _op
    ldy #0
:   lda pad_x,x
_op:
    adc t1,y
    sta t0,y
    inx
    iny
    tya
    and #3
    bne :-
    ldy #0                      ; x - t0: a sinistra vale t0 se è negativo, a destra se no
    sec
:   lda ball_x,y
    sbc t0,y
    sta t1,y
    iny
    tya
    and #3
    bne :-
    lda side                    ; segno di x - t0, rovesciato a destra
    beq :+
    lda #$80
:   eor t1+3
    bpl _done
    ldy #3
:   lda t0,y
    sta ball_x,y
    dey
    bpl :-
_done:
    ldx side
    rts
half_w: .dword P_PAD_HALF_W
.endproc

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
    rol a
    sta t0+2
    lda #0
    sta t0+3
    sub32 t0, t0, {#ONE}
    rts
.endproc

; ------------------------------------------------------------------------------------ palla

; Parte del tick dopo l'attesa della battuta: movimento, bordi, contatto o punto.
.proc ball_tick
    mov32 prev_x, ball_x
    mov32 prev_y, ball_y
    ; dx = mul(vx, boost): con boost 1 è vx
    beq32 ball_boost, {#ONE}, _unit
    mulq16 ball_vx, ball_boost
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
    jsr ball_slowed             ; BULLET: passo rallentato
    jmp _x
_plain:
    add32 ball_y, ball_y, ball_vy
_x:
    add32 ball_x, ball_x, t0
    mov32 ball_dx, t0
    ; bordo alto e basso
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
:   ; racchetta verso cui va la palla
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
    ; palla oltre il bordo sinistro o destro: punto
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
:   rts
.endproc

; Match::contact: C = 1 se la palla tocca la racchetta X nell'ultimo spostamento, con la y del
; contatto in cy (punto medio dello spostamento se il bordo della palla ha attraversato la
; faccia, altrimenti la y della palla).
.proc contact
    cpx #0
    jne _right
    ; sinistra: se la palla era già dietro la racchetta niente
    cmp32 prev_x, {pad_x,x}
    bpl :+
    clc
    rts
:   add32 t2, {pad_x,x}, {#P_PAD_HALF_W}     ; faccia
    sub32 t0, prev_x, ball_r
    cmp32 t0, t2
    jmi _overlap
    sub32 t0, ball_x, ball_r
    cmp32 t0, t2
    jpl _overlap
    jmp _crossed
_right:
    cmp32 {pad_x,x}, prev_x
    bpl :+
    clc
    rts
:   sub32 t2, {pad_x,x}, {#P_PAD_HALF_W}
    add32 t0, prev_x, ball_r
    cmp32 t2, t0
    jmi _overlap
    add32 t0, ball_x, ball_r
    cmp32 t2, t0
    jpl _overlap
_crossed:
    add32 cy, prev_y, ball_y
    asr32 cy
    sub32 t0, cy, ball_r
    add32 t1, {pad_y,x}, {pad_half,x}
    cmp32 t1, t0
    bmi _overlap
    add32 t0, cy, ball_r
    sub32 t1, {pad_y,x}, {pad_half,x}
    cmp32 t0, t1
    bmi _overlap
    sec
    rts
_overlap:
    ; sovrapposizione semplice
    sub32 t0, ball_x, ball_r
    add32 t1, {pad_x,x}, {#P_PAD_HALF_W}
    cmp32 t1, t0
    jmi _no
    add32 t0, ball_x, ball_r
    sub32 t1, {pad_x,x}, {#P_PAD_HALF_W}
    cmp32 t0, t1
    jmi _no
    sub32 t0, ball_y, ball_r
    add32 t1, {pad_y,x}, {pad_half,x}
    cmp32 t1, t0
    bmi _no
    add32 t0, ball_y, ball_r
    sub32 t1, {pad_y,x}, {pad_half,x}
    cmp32 t0, t1
    bmi _no
    mov32 cy, ball_y
    sec
    rts
_no:
    clc
    rts
.endproc

; Match::reflection: velocità verticale data dalla racchetta X, in t_refl; in_area = 1 se la palla
; è dentro l'area boost EVO.
.proc reflection
    lda #0
    sta in_area
    abs32 t_speed, ball_vx
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
    sub32 t0, t_rel, t0
    lda pad_level,x
    asl a
    asl a
    tay
    mov32 t1, {boost_inv_tab,y}
    lda #1
    sta in_area
    mulq16 t_speed, t0
    mulq24 m_a, t1
    mulq16 m_a, {#DAMP_BOOST}
    mov32 t_refl, m_a
    ldx side
    rts
_plain:
    sub32 t0, ball_y, {pad_y,x}
    mulq16 t_speed, t0
    ldx side
    mulq24 m_a, {pad_inv,x}
    mov32 t_refl, m_a
    ldx side
    rts
.endproc

; Match::bounce: la racchetta X respinge la palla.
.proc bounce
    jsr reflection
    add32 ball_vy, ball_vy, t_refl
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
    cpx #0
    bne :+
    add32 t0, {pad_x,x}, {#P_PAD_HALF_W}
    add32 ball_x, t0, ball_r
    jmp _flip
:   sub32 t0, {pad_x,x}, {#P_PAD_HALF_W}
    sub32 ball_x, t0, ball_r
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
    abs32 t0, ball_vx
    cmp32 t0, max_ball
    bpl :+
    mulq16 ball_vx, kspeed
    mov32 ball_vx, m_a
    mulq16 ball_vy, kspeed
    mov32 ball_vy, m_a
:   ldx side
    rts
.endproc

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
:   lda #0
    sta pad_level
    sta pad_level+4
    mov32 pad_bh, boost_h_tab
    mov32 pad_bh+4, boost_h_tab
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
