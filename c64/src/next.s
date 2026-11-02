; Modalità NEXT: traduzione di rust/core/src/next.rs, chiamata da game.s nei punti del tick in cui
; la chiama `Match::step` (comandi, dopo le racchette, movimento della palla, bordi, colpo,
; barriera, punto). Stessa sequenza di operazioni e di estrazioni dal generatore: lo stato
; coincide con il core tick per tick (paddws-c64 game, partite NEXT).
;
; Bonus (come `Bonus`): 0 TELEPORT, 1 SMASH, 2 SLOW, 3 CURVE, 4 GHOST, 5 SUPER, 6 STEER, 7 BULLET,
; 8 vuoto.
;
; BULLET (bullet time): attivato resta armato finché la palla entra nella metà campo
; di chi l'ha attivato (P_BULLET_ZONE) andando verso di lui; allora scatta e rallenta tutto tranne la sua racchetta, finché la
; palla torna ad allontanarsi (l'ha ribattuta) o c'è un punto. Un punto prima che scatti non lo
; consuma. Si rallenta il passo del tick, mai la velocità memorizzata: v - (v >> k) (slow_v), con
; k = P_BULLET_RSHIFT nei primi P_BULLET_RAMP tick dallo scatto e poi P_BULLET_SHIFT.
; Tipi di racchetta (come `PaddleKind`): 0 ARCADE, 1 TITAN, 2 HAMMER, 3 TWIST, 4 BLASTER, 5 RUSH,
; 6 GUARDIAN, 7 senza tipo. Per giocatore, vettori con passo 4 (indice X = lato * 4).

B_TELEPORT = 0
B_SMASH    = 1
B_SLOW     = 2
B_CURVE    = 3
B_GHOST    = 4
B_SUPER    = 5
B_STEER    = 6
B_BULLET   = 7
B_NONE     = 8

K_ARCADE   = 0
K_TITAN    = 1
K_HAMMER   = 2
K_TWIST    = 3
K_BLASTER  = 4
K_RUSH     = 5
K_GUARDIAN = 6
K_NONE     = 7

G_SECTORS  = 5                  ; GUARDIAN: settori del muro (GUARDIAN_SECTORS)
G_WALL     = (1 << G_SECTORS) - 1

ANIM_HITSTOP = 1

EV_COLLECT  = $10
EV_ACTIVATE = $20
EV_SUPER    = $40
EV_TELEPORT = $80
EV_FIRE_HI    = $01             ; byte alto degli eventi
EV_BARRIER_HI = $02
EV_STRAIGHT_HI = $04            ; mosse speciali: STRAIGHT SHOT o RISING STRIKE armati, colpo
EV_RISE_HI    = $08             ; con una mossa (supers.s)
EV_SPECIAL_HI = $10

; comandi NEXT (in_flags)
IN_SELECT   = $04
IN_ACTIVATE = $08
IN_FIRE     = $10
IN_STRAIGHT = $20               ; mosse speciali (PlayerInput::special)
IN_RISE     = $40

CAP_LOW  = P_CAP_HALF + ONE                         ; capsule tra il basso e la fascia delle riserve
CAP_HIGH = P_HEIGHT - P_CAP_MARGIN - P_CAP_HALF

.segment "NEXTBSS"
; configurazione (prima di match_new, con cfg_next = 1)
cfg_next:    .res 1
cfg_loadout: .res 8             ; 3 bonus per giocatore
cfg_kinds:   .res 8             ; tipo di racchetta per giocatore

; giocatori
nx_load:   .res 8
nx_res:    .res 8               ; riserva: 3 posti, compatta nei primi
nx_sel:    .res 8
nx_armed:  .res 8
nx_anim:   .res 8
nx_cool:   .res 8               ; pausa prima di un altro bonus (16 bit)
nx_kind:   .res 8
nx_ammo:   .res 8
nx_gap:    .res 8               ; pausa prima del colpo successivo (16 bit)
nx_reload: .res 8               ; ricarica del caricatore (16 bit)
nx_barrier: .res 8              ; GUARDIAN: settori del muro in piedi, bit 0 = settore 0
; colpi del BLASTER: 8 posti (4 per giocatore, prima il sinistro: posto = lato * 4 + k, cioè
; X del giocatore + k), passo 4
MAX_SHOTS = 4
shot_on:   .res 2 * MAX_SHOTS
shot_x:    .res 8 * MAX_SHOTS
shot_y:    .res 8 * MAX_SHOTS
shot_vx:   .res 8 * MAX_SHOTS
; capsule: 4 posti, passo 4
cap_on:    .res 4
cap_x:     .res 16
cap_y:     .res 16
cap_vx:    .res 16
cap_vy:    .res 16
cap_bonus: .res 4
; effetti
nx_spawn:  .res 2               ; tick alla prossima capsula
nx_slow:   .res 2               ; alone di SLOW (fermo finché la palla è rallentata)
nx_slow_s: .res 1               ; chi ha rallentato la palla con SLOW (0 o 4; bit 7 = nessuno)
nx_curve:  .res 4
nx_ghost:  .res 1               ; palla fantasma (dopo il tiro di nx_ghost_s)
nx_ghost_s: .res 1
.segment "ZEROPAGE"
nx_steer:  .res 1               ; palla guidata da nx_steer_s, verso del tick
.segment "NEXTBSS"
nx_steer_s: .res 1
nx_steer_dir: .res 1
nx_super:  .res 1               ; SUPER in volo, con l'animazione
nx_super_a: .res 1
nx_freeze: .res 2               ; fermo del gioco (hit-stop)
nx_spawned: .res 2
ghost_phase: .res 1             ; tick % P_GHOST_PERIOD (lampi della palla fantasma)
nx_btimer: .res 1               ; BULLET scattato: tick di rampa rimasti + 1 (0 = non scattato)
nx_bside:  .res 1               ; chi l'ha attivato, armato o scattato (0 o 4; bit 7 = nessuno)
s_k:       .res 1               ; shift del BULLET per palla e capsule in questo tick
s_ki:      .res 1               ; e indice delle costanti rallentate: 0 in mezzo, 8 nelle rampe
.segment "BSS"
ball_dy:   .res 4               ; passo verticale rallentato dell'ultimo tick (ball_slowed)
nx_bmoved: .res 1               ; la palla ha fatto un passo rallentato nell'ultimo tick
.segment "NEXTBSS"
; passo da rallentare (slow_v): nel prodotto delle moltiplicazioni, che lì non servono (nessuna
; moltiplicazione tra il passo messo in s_v e il suo uso)
s_v = m_p
s_w = m_p + 4
s_n = m_p + 8

.assert P_BULLET_RAMP < 255 .and P_BULLET_SHIFT > 0 .and P_BULLET_RSHIFT > 0, error, "BULLET: timer in un byte"
.assert P_BULLET_CUT < $10000 .and P_SUPER_CUT <= P_BULLET_CUT, error, "capsule: estrazione a 16 bit"

.segment "ZEROPAGE"
n_i:    .res 1                  ; indice in esame (capsula, colpo)
n_j:    .res 1
n_side: .res 1
n_t:    .res 4
m_next:      .res 1
n_u:    .res 4

.segment "CODE"


; ------------------------------------------------------------------------------------ partita

; Match::new_next_paddles: dopo il resto di match_new, racchette dei tipi scelti e stato di NEXT.
.proc next_init
    ldx #0
pl:
    ; bonus scelti, riserva vuota
    lda cfg_loadout,x
    sta nx_load,x
    lda cfg_loadout+1,x
    sta nx_load+1,x
    lda cfg_loadout+2,x
    sta nx_load+2,x
    lda #B_NONE
    sta nx_res,x
    sta nx_res+1,x
    sta nx_res+2,x
    sta nx_armed,x
    lda #0
    sta nx_sel,x
    sta tp_ok,x
    sta nx_anim,x
    sta nx_cool,x
    sta nx_cool+1,x
    sta nx_gap,x
    sta nx_gap+1,x
    sta nx_reload,x
    sta nx_reload+1,x
    sta nx_ammo,x
    sta nx_barrier,x
    lda cfg_kinds,x
    sta nx_kind,x
    cmp #K_BLASTER
    bne :+
    lda #P_BLASTER_SHOTS
    sta nx_ammo,x
:   lda nx_kind,x
    cmp #K_GUARDIAN
    bne :+
    lda #G_WALL                 ; il muro intero
    sta nx_barrier,x
:   jsr kind_paddle
    inx
    inx
    inx
    inx
    cpx #8
    jne pl
    lda #0
    ldx #2 * MAX_SHOTS - 1
:   sta shot_on,x
    dex
    bpl :-
    ldx #3
:   sta cap_on,x
    dex
    bpl :-
    sta nx_curve
    sta nx_curve+1
    sta nx_curve+2
    sta nx_curve+3
    sta nx_ghost
    sta nx_steer
    sta nx_steer_dir
    sta nx_super
    sta nx_freeze
    sta nx_freeze+1
    sta nx_spawned
    sta nx_spawned+1
    sta ghost_phase
    jsr slow_end                ; nessuno SLOW
    jsr bullet_end              ; nessun BULLET
    lda #<P_SPAWN_TICKS
    sta nx_spawn
    lda #>P_SPAWN_TICKS
    sta nx_spawn+1
    ; mosse speciali (supers.s): tutto a zero, poi l'opzione del menu
    lda #0
    ldx #SM_VARS - 1
:   sta sm_vars,x
    dex
    bpl :-
    lda cfg_super
    sta sm_on
    beq :+
    jsr sm_init
:   rts
.endproc

; Racchetta X con i valori del suo tipo (7 = la racchetta normale).
.proc kind_paddle
    lda nx_kind,x
    asl a
    asl a
    tay
    mov32 {pad_h,x}, {kind_h,y}
    mov32 {pad_inv,x}, {kind_inv,y}
    mov32 {pad_max,x}, {kind_max,y}
    mov32 {pad_acc,x}, {kind_acc,y}
    mov32 {pad_facc,x}, {kind_facc,y}
    mov32 {pad_fmax,x}, {kind_fmax,y}
    mov32 {pad_fwacc,x}, {kind_fwacc,y}
    mov32 {pad_fwfacc,x}, {kind_fwfacc,y}
    mov32 {pad_step,x}, {kind_step,y}
    cpx #0
    bne :+
    mov32 {pad_fwd,x}, {kind_fwd,y}
    jmp half_height
:   sub32 {pad_fwd,x}, {#P_WIDTH}, {kind_fwd,y}
    jmp half_height
.endproc

.segment "RODATA"
kind_h:      .dword T_KIND_H
kind_inv:    .dword T_KIND_INV
kind_max:    .dword T_KIND_MAX
kind_acc:    .dword T_KIND_ACC
kind_facc:   .dword T_KIND_FACC
kind_fwd:    .dword T_KIND_FWD
kind_fmax:   .dword T_KIND_FMAX
kind_fwacc:  .dword T_KIND_FWACC
kind_fwfacc: .dword T_KIND_FWFACC
kind_step:   .dword T_KIND_STEP
kspeed_next_tab: .dword T_KSPEED_NEXT
max_next_tab:    .dword T_MAX_NEXT
.segment "CODE"

; Effetti di un solo tiro: finiscono al colpo successivo o al punto (Next::clear_shot).
.proc clear_shot
    lda #0
    sta nx_curve
    sta nx_curve+1
    sta nx_curve+2
    sta nx_curve+3
    sta nx_ghost
    sta nx_steer
    sta nx_steer_dir
    sta nx_super
    sta sm_fl                   ; tiro di una mossa speciale e impennata di RISING STRIKE
    sta sm_rise
    rts
.endproc

; Bonus nella riserva del giocatore X in A (la riserva è compatta).
.proc res_count
    lda #0
    ldy nx_res,x
    cpy #B_NONE
    jeq done
    lda #1
    ldy nx_res+1,x
    cpy #B_NONE
    jeq done
    lda #2
    ldy nx_res+2,x
    cpy #B_NONE
    jeq done
    lda #3
done:
    ora #0                      ; Z = 1 se la riserva è vuota
    rts
.endproc

; Mette il bonus A nel primo posto libero della riserva X (se c'è).
.proc res_push
    ldy nx_res,x
    cpy #B_NONE
    bne :+
    sta nx_res,x
    rts
:   ldy nx_res+1,x
    cpy #B_NONE
    bne :+
    sta nx_res+1,x
    rts
:   ldy nx_res+2,x
    cpy #B_NONE
    bne :+
    sta nx_res+2,x
:   rts
.endproc

; ------------------------------------------------------------------------------------ comandi

; STEER del giocatore X: il verso (su/giù, o la manopola lontana dalla racchetta) e la racchetta ferma.
.proc steer_store
    ; il verso: in_dir, oppure dalla manopola
    lda in_flags,x
    jmi knob
    lda in_dir,x
    jmp set
knob:
    jsr steer_knob
set:
    sta nx_steer_dir
    lda #0
    sta pad_dir,x
    sta pad_speed,x
    sta pad_speed+1,x
    sta pad_speed+2,x
    sta pad_speed+3,x
    rts
.endproc

; A = verso di STEER dalla manopola del giocatore X (steer_from_offset di game.rs).
.proc steer_knob
    lda #0
    sta n_t
    sta n_t+1
    sta n_t+3
    lda in_offset,x
    sta n_t+2
    sub32 n_t, {#P_HEIGHT}, n_t
    sub32 n_t, n_t, {pad_half,x}    ; goal
    mov32 n_u, {pad_h,x}
    asr32 n_u
    asr32 n_u
    asr32 n_u                       ; dead = altezza / 8
    add32 n_u, {pad_y,x}, n_u
    cmp32 n_u, n_t                  ; y + dead < goal: su
    bpl :+
    lda #1
    rts
:   mov32 n_u, {pad_h,x}
    asr32 n_u
    asr32 n_u
    asr32 n_u
    sub32 n_u, {pad_y,x}, n_u
    cmp32 n_t, n_u                  ; goal < y - dead: giù
    bpl :+
    lda #$ff
    rts
:   lda #0
    rts
.endproc

; Match::next_command: seleziona il bonus successivo e/o attiva quello selezionato (giocatore X).
.proc next_command
    lda in_flags,x
    and #IN_SELECT
    jeq activate
    ; seleziona: il successivo, in giro
    jsr res_count
    jeq activate
    sta n_t
    ldy nx_sel,x
    iny
    cpy n_t
    bcc :+
    ldy #0
:   tya
    sta nx_sel,x
activate:
    lda in_flags,x
    and #IN_ACTIVATE
    jeq done
    ; un bonus alla volta, non durante l'attesa della battuta, con una pausa tra due attivazioni;
    ; nemmeno con una mossa speciale armata
    or32 serve_timer
    jne done
    lda nx_cool,x
    ora nx_cool+1,x
    jne done
    lda nx_armed,x
    cmp #B_NONE
    jne done
    lda sm_arm,x
    jne done
    ; toglie il selezionato dalla riserva, compattando gli altri
    jsr res_count
    jeq done
    sta n_t                     ; n
    tay
    dey                         ; n - 1
    sty n_t+1
    lda nx_sel,x
    cmp n_t+1
    bcc :+
    lda n_t+1                   ; min(selezionato, n - 1)
:   sta n_i
    txa
    clc
    adc n_i
    tay
    lda nx_res,y
    sta n_j                     ; il bonus
    ; un BULLET alla volta: con uno armato o in corso (di chiunque) resta in riserva
    cmp #B_BULLET
    bne :+
    lda nx_bside
    jpl done
    ; posti dopo i: avanti di uno
:   lda n_i
    cmp #2
    bcs :+
    lda nx_res+1,y
    sta nx_res,y
    iny
    inc n_i
    jmp :-
:   lda #B_NONE
    sta nx_res,y
    ; selezionato: se era l'ultimo, uno indietro
    lda nx_sel,x
    cmp n_t+1
    bcc :+
    beq :+
    jmp dec_sel
:   lda nx_sel,x
    cmp n_t+1
    jne pause
dec_sel:
    lda nx_sel,x
    jeq pause
    dec nx_sel,x
pause:
    ; pausa prima del bonus successivo (più breve con l'ARCADE)
    lda nx_kind,x
    cmp #K_ARCADE
    bne :+
    lda #<P_ARCADE_COOLDOWN
    sta nx_cool,x
    lda #>P_ARCADE_COOLDOWN
    sta nx_cool+1,x
    jmp :++
:   lda #<P_COOLDOWN
    sta nx_cool,x
    lda #>P_COOLDOWN
    sta nx_cool+1,x
:   event EV_ACTIVATE
    lda n_j
    cmp #B_SLOW
    jeq slow
    cmp #B_BULLET
    jeq bullet
    cmp #B_SUPER
    jne arm
    ; SUPER: animazione a caso
    stx n_side
    lda #3
    sta m_b
    lda #0
    sta m_b+1
    jsr rng_below
    ldx n_side
    sta nx_anim,x
    lda n_j
arm:
    sta nx_armed,x
done:
    rts
slow:
    ; la palla perde velocità fino al prossimo colpo di chi l'ha usato (next_on_hit), ma non va
    ; sotto la battuta
    stx n_side
    stx nx_slow_s
    mulq16 ball_vx, {#P_SLOW_MUL}
    mov32 ball_vx, m_a
    abs32 n_t, ball_vx
    blt32 n_t, {#2 * P_SERVE_UNIT}, :+
    jmp vy
:   lda ball_vx+3
    bmi :+
    mov32 ball_vx, {#2 * P_SERVE_UNIT}
    jmp vy
:   mov32 ball_vx, {#-2 * P_SERVE_UNIT}
vy:
    mulq16 ball_vy, {#P_SLOW_MUL}
    mov32 ball_vy, m_a
    lda #<P_SLOW_TICKS
    sta nx_slow
    lda #>P_SLOW_TICKS
    sta nx_slow+1
    ldx n_side
    rts
bullet:
    ; armato; se la palla è già nella sua metà campo e va verso di lui scatta da questo tick:
    ; rallenta già le racchette, che si muovono subito dopo (continua in bullet_trigger)
    stx nx_bside
.endproc

; Next::bullet_trigger: il BULLET armato del giocatore X scatta se la palla è nella metà campo
; dalla sua parte (P_BULLET_ZONE) e va verso di lui, con la rampa. X resta.
.proc bullet_trigger
    ldy #ZONE_BULLET
    jsr ball_in_zone
    bcc :+
    lda #P_BULLET_RAMP + 1
    sta nx_btimer
:   rts
.endproc

; Next::bullet_step, all'inizio del tick (non durante il fermo): il BULLET armato scatta
; (bullet_trigger); quello in corso finisce quando la palla si allontana da chi l'ha attivato
; (l'ha ribattuta), altrimenti scende la rampa (nx_btimer si ferma a 1).
.proc bullet_step
    ldx nx_bside
    bmi done
    lda nx_btimer
    beq bullet_trigger
    jsr ball_toward
    bcc bullet_end
    dec nx_btimer
    bne done
    inc nx_btimer
done:
    rts
.endproc

; Fine di SLOW (al colpo di chi l'ha usato, al punto, a inizio partita): nessuno ha rallentato
; la palla e l'alone sparisce; A = 0.
.proc slow_end
    lda #$80
    sta nx_slow_s
    asl a
    sta nx_slow
    sta nx_slow+1
    rts
.endproc

; Fine del BULLET (alla ribattuta o al punto); A = 0.
.proc bullet_end
    lda #$80
    sta nx_bside
    asl a
    sta nx_btimer
    rts
.endproc

; C = 1 se la palla va verso il giocatore X (coming_toward di next.rs: a sinistra vx < 0, a destra
; vx > 0). X resta.
.proc ball_toward
    lda ball_vx+3
    cpx #0
    bne right
    asl a                       ; il segno
    rts
right:
    asl a
    bcs no
    or32 ball_vx
    cmp #1                      ; non zero
    rts
no:
    clc
    rts
.endproc

; C = 1 se la palla va verso il giocatore X ed è oltre la soglia del suo lato: a sinistra
; x < zone_l, a destra x > zone_r. Y = ZONE_HALF: metà campo (TELEPORT); Y = ZONE_BULLET: la
; zona del BULLET (Next::bullet_trigger), oggi anche lei la metà campo. Le soglie sono pixel interi: a
; sinistra basta la parte intera di x (x < T se e solo se int(x) < T), a destra la sottrazione
; T - x è intera. X resta.
ZONE_HALF   = 0
ZONE_BULLET = 1
.proc ball_in_zone
    jsr ball_toward
    bcc no
    cpx #0
    bne right
    sec
    lda ball_x+2
    sbc zone_l,y
    lda ball_x+3
    sbc zone_l+2,y
    jmp sign
right:
    sec
    lda #0
    sbc ball_x
    lda #0
    sbc ball_x+1
    lda zone_r,y
    sbc ball_x+2
    lda zone_r+2,y
    sbc ball_x+3
sign:
    bvc :+
    eor #$80
:   asl a                       ; il segno della differenza
no:
    rts
.endproc

; soglie (parte intera, 16 bit): byte bassi delle due, poi byte alti
zone_l: .byte <(P_WIDTH >> 17), <(P_BULLET_ZONE >> 16)
        .byte >(P_WIDTH >> 17), >(P_BULLET_ZONE >> 16)
zone_r: .byte <(P_WIDTH >> 17), <((P_WIDTH - P_BULLET_ZONE) >> 16)
        .byte >(P_WIDTH >> 17), >((P_WIDTH - P_BULLET_ZONE) >> 16)
.assert ((P_WIDTH / 2) | P_BULLET_ZONE) & $FFFF = 0 .and P_WIDTH < $40000000, error, "soglie di ball_in_zone: pixel interi"

; Match::next_fire: il BLASTER X spara se ha colpi, la pausa è finita e c'è un posto libero.
.proc next_fire
    lda nx_ammo,x
    jeq no
    lda nx_gap,x
    ora nx_gap+1,x
    jne no
    ; primo posto libero tra i MAX_SHOTS del giocatore (dal posto X)
    txa
    tay
    ldx #MAX_SHOTS
:   lda shot_on,y
    jeq free
    iny
    dex
    bne :-
    ldx n_side_x
    rts
free:
    ldx n_side_x
    lda #1
    sta shot_on,y
    tya
    asl a
    asl a
    tay                         ; Y = posto * 4
    cpx #0
    jne right
    add32 {shot_x,y}, {pad_x,x}, {#P_PAD_HALF_W}
    mov32 {shot_vx,y}, {#P_SHOT_SPEED}
    jmp sy
right:
    sub32 {shot_x,y}, {pad_x,x}, {#P_PAD_HALF_W}
    mov32 {shot_vx,y}, {#-P_SHOT_SPEED}
sy:
    mov32 {shot_y,y}, {pad_y,x}
    ; il primo colpo a caricatore pieno fa partire la ricarica
    lda nx_ammo,x
    cmp #P_BLASTER_SHOTS
    bne :+
    lda #<P_BLASTER_RELOAD
    sta nx_reload,x
    lda #>P_BLASTER_RELOAD
    sta nx_reload+1,x
:   dec nx_ammo,x
    lda #<P_BLASTER_GAP
    sta nx_gap,x
    lda #>P_BLASTER_GAP
    sta nx_gap+1,x
    event_hi EV_FIRE_HI
no:
    rts
.endproc

.segment "NEXTBSS"
n_side_x: .res 1
.segment "CODE"

; ------------------------------------------------------------------------------------ tick

.segment "NEXTBSS"
; previsione del TELEPORT tenuta da parte, per giocatore (passo 4): y, x della racchetta, palla
; (spostamento, vy, raggio, x all'ultima chiamata), passi rimasti, valida
tp_y:   .res 8
tp_cx:  .res 8
tp_dx:  .res 8
tp_vy:  .res 8
tp_r:   .res 8
tp_bx:  .res 8
tp_n:   .res 8
tp_ok:  .res 8
.segment "CODE"

; arrival_y per il TELEPORT del giocatore c_side, in c_y. Il core la rifà a ogni tick; su un tratto
; rettilineo il risultato non cambia: si tiene finché la palla avanza di ball_dx a ogni tick con
; la stessa velocità e lo stesso raggio, la racchetta non cambia x e restano passi da fare. Se il
; BULLET ha rallentato l'ultimo passo della palla (s_k dell'ultimo next_ball_motion, che nessuno
; cambia prima del TELEPORT) la y non è avanzata di ball_vy ma di ball_dy: un passo in meno, la y
; senza bordi prende ball_dy - vy e si rifanno solo i bordi.
.proc tp_arrival
    ldx c_side
    lda tp_ok,x
    jeq compute
    beq32 {tp_cx,x}, {pad_x,x}, :+
    jmp compute
:   beq32 {tp_dx,x}, ball_dx, :+
    jmp compute
:   beq32 {tp_vy,x}, ball_vy, :+
    jmp compute
:   beq32 {tp_r,x}, ball_r, :+
    jmp compute
:   add32 n_t, {tp_bx,x}, ball_dx
    beq32 n_t, ball_x, :+
    jmp compute
:   dec tp_n,x                  ; un passo in meno; all'arrivo si rifà
    jeq compute
    mov32 {tp_bx,x}, ball_x
    lda s_k
    bne slowed
    mov32 c_y, {tp_y,x}
    rts
slowed:
    txa
    ora #8
    tay
    sec                         ; un passo in meno
    jsr pred_advance
    mov32 {tp_y,x}, c_y
    rts
compute:
    lda #8
    sta c_tp
    jsr arrival_y
    ldx c_side
    mov32 {tp_y,x}, c_y
    mov32 {tp_cx,x}, {pad_x,x}
    mov32 {tp_dx,x}, ball_dx
    mov32 {tp_vy,x}, ball_vy
    mov32 {tp_r,x}, ball_r
    mov32 {tp_bx,x}, ball_x
    ; si tiene se ci sono passi da fare e la previsione non è troncata all'orizzonte
    ldy #0
    lda c_n
    sta tp_n,x
    beq :+
    cmp #P_ARRIVAL_MAX
    bcs :+
    iny
:   tya
    sta tp_ok,x
    rts
.endproc

; Match::next_tick: pause, caricatore, TELEPORT, capsule, colpi del BLASTER e, per ultime, le
; mosse speciali (sm_tick).
.proc next_tick
    ; pause tra due bonus e due colpi, ricarica del caricatore
    ldx #0
:   dec16_sat {nx_cool,x}
    dec16_sat {nx_gap,x}
    lda nx_reload,x
    ora nx_reload+1,x
    jeq next
    lda nx_reload,x
    bne :+
    dec nx_reload+1,x
:   dec nx_reload,x
    lda nx_reload,x
    ora nx_reload+1,x
    jne next
    lda #P_BLASTER_SHOTS
    sta nx_ammo,x
next:
    inx
    inx
    inx
    inx
    cpx #8
    bne :--
    ; TELEPORT (non durante l'attesa della battuta)
    or32 serve_timer
    bne :+
    ldx #0
    jsr teleport
    ldx #4
    jsr teleport
:   jsr spawn_capsule
    jsr move_capsules
    jsr move_shots
    jmp sm_tick
.endproc

; TELEPORT del giocatore X: passata la metà campo, la racchetta salta dove arriverà la palla e
; resta sul punto previsto (rifatto a ogni tick) fino al colpo.
.proc teleport
    lda nx_armed,x
    cmp #B_TELEPORT
    jne no
    ; la palla viene verso di sé ed è oltre la metà campo
    ldy #ZONE_HALF
    jsr ball_in_zone
    jcc no
    stx c_side
    jsr tp_arrival              ; c_y
    ldx c_side
    ; tra metà altezza e H - metà altezza
    cmp32 c_y, {pad_half,x}
    bpl :+
    mov32 c_y, {pad_half,x}
:   sub32 n_t, {#P_HEIGHT}, {pad_half,x}
    cmp32 n_t, c_y
    bpl :+
    mov32 c_y, n_t
:   ; il salto vero (oltre un quarto di racchetta) ha la sua animazione
    sub32 n_t, c_y, {pad_y,x}
    abs32 n_t, n_t
    mov32 n_u, {pad_h,x}
    asr32 n_u
    asr32 n_u
    cmp32 n_u, n_t
    bpl :+
    event EV_TELEPORT
:   mov32 {pad_y,x}, c_y
    lda #0
    sta pad_speed,x
    sta pad_speed+1,x
    sta pad_speed+2,x
    sta pad_speed+3,x
no:
    rts
.endproc

; Una capsula ogni tanto dalla mezzeria, verso un giocatore, con uno dei suoi bonus, il SUPER o
; il BULLET.
.proc spawn_capsule
    dec16_sat nx_spawn
    lda nx_spawn
    ora nx_spawn+1
    jne done
    ; prossima: con un ARCADE in campo più spesso
    lda nx_kind
    cmp #K_ARCADE
    jeq arcade
    lda nx_kind+4
    cmp #K_ARCADE
    jeq arcade
    lda #<P_SPAWN_TICKS
    sta n_t
    lda #>P_SPAWN_TICKS
    sta n_t+1
    jmp jitter
arcade:
    lda #<P_ARCADE_SPAWN
    sta n_t
    lda #>P_ARCADE_SPAWN
    sta n_t+1
jitter:
    lda #<P_SPAWN_JITTER
    sta m_b
    lda #>P_SPAWN_JITTER
    sta m_b+1
    jsr rng_below
    clc
    adc n_t
    sta nx_spawn
    txa
    adc n_t+1
    sta nx_spawn+1
    ; primo posto libero
    ldx #0
:   lda cap_on,x
    jeq free
    inx
    cpx #4
    bne :-
    jmp done
free:
    stx n_i
    ; verso chi: contro un solo ARCADE due su tre a lui, altrimenti a caso
    lda #0
    sta n_t
    lda nx_kind
    cmp #K_ARCADE
    bne :+
    inc n_t
:   lda nx_kind+4
    cmp #K_ARCADE
    bne :+
    lda n_t
    eor #2
    sta n_t
:   lda n_t
    jeq coin
    cmp #3
    jeq coin
    ; n_t = 1: ARCADE a sinistra, 2: a destra
    lda #3
    sta m_b
    lda #0
    sta m_b+1
    jsr rng_below
    cmp #P_ARCADE_SHARE
    lda n_t
    bcc :+
    eor #3                      ; all'altro
:   cmp #1
    jeq left
    jmp to_right
coin:
    jsr rng_next
    lda rng+3
    jmi to_right
left:
    lda #0
    jmp side
to_right:
    lda #4
side:
    sta n_side
    ; bonus: 16 bit del generatore (Rng::bits16), sotto P_SUPER_CUT il SUPER, sotto P_BULLET_CUT
    ; il BULLET, altrimenti uno dei 3 del giocatore (con un'altra estrazione)
    jsr rng_next
    lda rng+2
    cmp #<P_SUPER_CUT
    lda rng+3
    sbc #>P_SUPER_CUT
    bcs :+
    lda #B_SUPER
    jmp bonus
:   lda rng+2
    cmp #<P_BULLET_CUT
    lda rng+3
    sbc #>P_BULLET_CUT
    bcs pick
    lda #B_BULLET
    jmp bonus
pick:
    lda #3
    sta m_b
    lda #0
    sta m_b+1
    jsr rng_below
    clc
    adc n_side
    tax
    lda nx_load,x
bonus:
    ldx n_i
    sta cap_bonus,x
    lda #1
    sta cap_on,x
    txa
    asl a
    asl a
    sta n_j                     ; posto * 4
    ; y a caso tra il basso e la fascia delle riserve: low + mul(high - low, frac)
    jsr rng_next
    lda rng+2
    sta m_b
    lda rng+3
    sta m_b+1
    lda #0
    sta m_b+2
    sta m_b+3
    mov32 m_a, {#CAP_HIGH - CAP_LOW}
    jsr mul_q16
    ldy n_j
    add32 {cap_y,y}, m_a, {#CAP_LOW}
    mov32 {cap_x,y}, {#P_WIDTH / 2}
    lda n_side
    bne :+
    mov32 {cap_vx,y}, {#-P_CAP_SPEED}
    jmp drift
:   mov32 {cap_vx,y}, {#P_CAP_SPEED}
drift:
    jsr rng_next
    ldy n_j
    lda rng+3
    bmi :+
    mov32 {cap_vy,y}, {#P_CAP_DRIFT}
    jmp :++
:   mov32 {cap_vy,y}, {#-P_CAP_DRIFT}
:   inc nx_spawned
    jne done
    inc nx_spawned+1
done:
    rts
.endproc

; Capsule in volo: rimbalzano tra il basso e la fascia delle riserve; chi le tocca con la
; racchetta (con un posto libero nella riserva) le prende; fuori dal campo spariscono. Con il
; BULLET rallentano tutte.
.proc move_capsules
    jsr bullet_shift
    sta s_k
    jsr set_ki
    lda #0
    sta n_i
cap:
    ldx n_i
    lda cap_on,x
    jeq next
    txa
    asl a
    asl a
    tay
    lda s_k
    jne slowed
    add32 {cap_x,y}, {cap_x,y}, {cap_vx,y}
    add32 {cap_y,y}, {cap_y,y}, {cap_vy,y}
moved:
    blt32 {cap_y,y}, {#CAP_LOW}, low
    blt32 {#CAP_HIGH}, {cap_y,y}, high
    jmp toward
low:
    mov32 {cap_y,y}, {#CAP_LOW}
    abs32 {cap_vy,y}, {cap_vy,y}
    jmp toward
high:
    mov32 {cap_y,y}, {#CAP_HIGH}
    abs32 n_t, {cap_vy,y}
    neg32 {cap_vy,y}, n_t
toward:
    ; il giocatore verso cui va (vx < 0: sinistra)
    ldx #0
    lda cap_vx+3,y
    bmi :+
    ldx #4
:   stx n_side
    ; tocca la racchetta: |cx - px| <= metà capsula + metà larghezza, |cy - py| <= metà + metà altezza
    sub32 n_t, {cap_x,y}, {pad_x,x}
    abs32 n_t, n_t
    blt32 {#P_CAP_HALF + P_PAD_HALF_W}, n_t, out
    sub32 n_t, {cap_y,y}, {pad_y,x}
    abs32 n_t, n_t
    add32 n_u, {pad_half,x}, {#P_CAP_HALF}
    cmp32 n_u, n_t
    jmi out
    ; con la riserva piena passa oltre
    jsr res_count
    cmp #3
    jeq out
    ldy n_i
    lda cap_bonus,y
    jsr res_push
    event EV_COLLECT
    ldx n_i
    lda #0
    sta cap_on,x
    jmp next
out:
    ; fuori dal campo: cx + metà < 0 o cx - metà > W
    ldx n_i
    txa
    asl a
    asl a
    tay
    add32 n_t, {cap_x,y}, {#P_CAP_HALF}
    lda n_t+3
    jmi gone
    sub32 n_t, {cap_x,y}, {#P_CAP_HALF}
    blt32 {#P_WIDTH}, n_t, gone
    jmp next
gone:
    ldx n_i
    lda #0
    sta cap_on,x
next:
    inc n_i
    lda n_i
    cmp #4
    jne cap
    rts
slowed:
    ; BULLET: le velocità sono sempre +/- P_CAP_SPEED e P_CAP_DRIFT, i passi rallentati costanti
    ldx s_ki
    lda cap_vx+3,y
    bpl :+
    inx
    inx
    inx
    inx
:   add32 {cap_x,y}, {cap_x,y}, {cap_sx,x}
    ldx s_ki
    lda cap_vy+3,y
    bpl :+
    inx
    inx
    inx
    inx
:   add32 {cap_y,y}, {cap_y,y}, {cap_sy,x}
    jmp moved
.endproc

; A = shift del BULLET (non zero): s_ki = 0 per P_BULLET_SHIFT, 8 per P_BULLET_RSHIFT. Distrugge Y.
.proc set_ki
    ldy #0
    cmp #P_BULLET_SHIFT
    beq :+
    ldy #8
:   sty s_ki
    rts
.endproc

.segment "RODATA"
; BULLET: passi rallentati (slowed di next.rs, v - (v >> k) con lo shift con il segno) delle
; velocità costanti di capsule e colpi del BLASTER: con P_BULLET_SHIFT +v e -v, poi con
; P_BULLET_RSHIFT +v e -v
.define SLOW_POS(c, k) ((c) - ((c) >> (k)))
; negativo: ridotto a 32 bit, perché il ca65 a 64 bit (Linux) non accetta negativi in .dword
.define SLOW_NEG(c, k) (((((c) + (1 << (k)) - 1) >> (k)) - (c)) & $FFFFFFFF)
.macro slow_consts c
    .dword SLOW_POS c, P_BULLET_SHIFT, SLOW_NEG c, P_BULLET_SHIFT
    .dword SLOW_POS c, P_BULLET_RSHIFT, SLOW_NEG c, P_BULLET_RSHIFT
.endmacro
cap_sx:  slow_consts P_CAP_SPEED
cap_sy:  slow_consts P_CAP_DRIFT
shot_sx: slow_consts P_SHOT_SPEED
.segment "CODE"

; Colpi del BLASTER: attraversano la palla, raccolgono la prima capsula che toccano (con la
; riserva piena la distruggono) e si fermano sulla racchetta avversaria o fuori dal campo.
.proc move_shots
    lda #0
    sta n_i                     ; posto 0-7 (0-3 sinistro, 4-7 destro)
shot:
    ldx n_i
    lda shot_on,x
    jeq next
    ; giocatore del colpo
    txa
    and #MAX_SHOTS
    sta n_side
    txa
    asl a
    asl a
    tay
    ; passo del colpo, rallentato dal BULLET dell'avversario (velocità +/- P_SHOT_SPEED: passi
    ; rallentati costanti)
    lda nx_btimer
    beq plain
    ldx n_side
    jsr bullet_shift_x
    beq plain
    jsr set_ki
    ldy n_i
    tya
    asl a
    asl a
    tay
    ldx s_ki
    lda shot_vx+3,y
    bpl :+
    inx
    inx
    inx
    inx
:   mov32 s_v, {shot_sx,x}
    jmp step
plain:
    mov32 s_v, {shot_vx,y}
step:
    add32 {shot_x,y}, {shot_x,y}, s_v
    ; portata: metà capsula + |passo|, fascia: metà capsula + metà fascia dei colpi
    abs32 n_u, s_v
    add32 n_u, n_u, {#P_CAP_HALF}
    lda #0
    sta n_j
cap:
    ldx n_j
    lda cap_on,x
    jeq next_cap
    txa
    asl a
    asl a
    tax
    ldy n_i
    tya
    asl a
    asl a
    tay
    sub32 n_t, {cap_x,x}, {shot_x,y}
    abs32 n_t, n_t
    cmp32 n_u, n_t
    jmi next_cap
    sub32 n_t, {cap_y,x}, {shot_y,y}
    abs32 n_t, n_t
    blt32 {#P_CAP_HALF + P_BLASTER_BAND}, n_t, next_cap
    ; preso: nella riserva se c'è posto
    ldx n_j
    lda #0
    sta cap_on,x
    ldx n_side
    jsr res_count
    cmp #3
    beq :+
    ldy n_j
    lda cap_bonus,y
    jsr res_push
:   event EV_COLLECT
    ldx n_i
    lda #0
    sta shot_on,x
    jmp next
next_cap:
    inc n_j
    lda n_j
    cmp #4
    jne cap
    ; racchetta avversaria o fuori dal campo
    ldx n_i
    txa
    asl a
    asl a
    tay
    lda n_side
    eor #4
    tax                         ; X = avversario
    cpx #0
    jeq hit_left
    ; colpo del sinistro: x >= bordo sinistro della racchetta destra
    sub32 n_t, {pad_x,x}, {#P_PAD_HALF_W}
    cmp32 {shot_x,y}, n_t
    jmi edge
    jmp height
hit_left:
    add32 n_t, {pad_x,x}, {#P_PAD_HALF_W}
    cmp32 n_t, {shot_x,y}
    jmi edge
height:
    sub32 n_t, {shot_y,y}, {pad_y,x}
    abs32 n_t, n_t
    add32 n_u, {pad_half,x}, {#P_BLASTER_BAND}
    cmp32 n_u, n_t
    jpl stop
edge:
    lda shot_x+3,y
    jmi stop
    blt32 {#P_WIDTH}, {shot_x,y}, stop
    jmp next
stop:
    ldx n_i
    lda #0
    sta shot_on,x
next:
    inc n_i
    lda n_i
    cmp #2 * MAX_SHOTS
    jne shot
    rts
.endproc
.assert MAX_SHOTS = 4, error, "posti dei colpi: lato * 4 + k (X del giocatore + k)"

; ------------------------------------------------------------------------------------ palla

; Next::ball_motion: RISING STRIKE che s'impenna (sm_motion), palla a effetto (CURVE) o guidata
; (STEER), prima dello spostamento. Con il BULLET rallentano anche le accelerazioni (il passo lo
; rallenta ball_slowed).
.proc next_ball_motion
    jsr bullet_shift
    sta s_k
    abs32 n_u, ball_vx          ; mai più ripida di 45 gradi
    lda sm_rise
    beq :+
    jsr sm_motion
:   or32 nx_curve
    jeq steer
    mov32 s_v, nx_curve
    lda s_k
    jsr slow_v
    add32 ball_vy, ball_vy, s_v
    jsr clamp_vy
steer:
    lda nx_steer
    jeq slow
    ; si guida fino a 3/4 del campo, contati da chi ha colpito
    lda nx_steer_s
    jne right
    blt32 ball_x, {#P_WIDTH - (P_WIDTH >> 2)}, guide
    jmp past
right:
    blt32 {#P_WIDTH >> 2}, ball_x, guide
past:
    lda #0
    sta nx_steer
    sta nx_steer_dir
    jmp slow
guide:
    lda nx_steer_dir
    jeq slow
    ; fino al doppio della velocità orizzontale (circa 63 gradi)
    asl32 n_u
    lda nx_steer_dir
    jmi down
    mov32 s_v, {#P_STEER_ACCEL}
    jmp accel
down:
    mov32 s_v, {#-P_STEER_ACCEL}
accel:
    lda s_k                     ; slowed(-a) non è -slowed(a): lo shift è con il segno
    jsr slow_v
    add32 ball_vy, ball_vy, s_v
    jsr clamp_vy
slow:
    lda nx_slow_s               ; con la palla rallentata l'alone resta
    bpl :+
    dec16_sat nx_slow
:   rts
.endproc

; BULLET (s_k da next_ball_motion): spostamento rallentato, dx in t0 (che si rallenta) e la y.
.proc ball_slowed
    mov32 s_v, t0
    lda s_k
    jsr slow_v
    mov32 t0, s_v
    mov32 s_v, ball_vy
    lda s_k
    jsr slow_v
    mov32 ball_dy, s_v
    add32 ball_y, ball_y, s_v
    lda #1
    sta nx_bmoved
    rts
.endproc

; Next::bullet_shift_for: come bullet_shift, per ciò che appartiene al giocatore X (racchetta,
; colpi): chi ha attivato il BULLET resta a piena velocità. X resta.
.proc bullet_shift_x
    lda nx_btimer
    beq done
    cpx nx_bside
    bne bullet_shift
    lda #0
done:
    rts
.endproc

; Next::bullet_shift: shift del BULLET per palla e capsule in A (0 = piena velocità, anche con il
; BULLET solo armato, e Z = 1): P_BULLET_RSHIFT nei primi P_BULLET_RAMP tick dallo scatto
; (nx_btimer > 1), poi P_BULLET_SHIFT.
.proc bullet_shift
    lda nx_btimer
    beq done
    cmp #2
    lda #P_BULLET_SHIFT
    bcc done
    lda #P_BULLET_RSHIFT
done:
    rts
.endproc

; s_v = slowed(s_v, A) = s_v - (s_v >> A), shift con il segno (A = 0: invariato). X e Y restano.
.proc slow_v
    sta s_n
    ora #0
    beq done
    lda s_v
    sta s_w
    lda s_v+1
    sta s_w+1
    lda s_v+2
    sta s_w+2
    lda s_v+3
    sta s_w+3
:   cmp #$80
    ror s_w+3
    ror s_w+2
    ror s_w+1
    ror s_w
    lda s_w+3
    dec s_n
    bne :-
    sub32 s_v, s_v, s_w
done:
    rts
.endproc

; vy tra -n_u e n_u
.proc clamp_vy
    cmp32 n_u, ball_vy
    bpl :+
    mov32 ball_vy, n_u
    rts
:   neg32 n_t, n_u
    cmp32 ball_vy, n_t
    bpl :+
    mov32 ball_vy, n_t
:   rts
.endproc

; Match::next_on_hit: colpo del giocatore X, con C = 1 se è lo scatto che intercetta la palla.
; Finiscono gli effetti del tiro precedente, il tipo di racchetta fa il suo, parte il bonus armato
; (hit_bonus), poi la barra e la mossa speciale (sm_hit).
.proc next_on_hit
    ror sm_dash
    jsr hit_bonus
    jmp sm_hit
.endproc

.proc hit_bonus
    stx n_side
    jsr clear_shot
    ldx n_side
    cpx nx_slow_s
    jne kinds
    ; SLOW: al colpo di chi l'ha usato la palla riparte alla velocità di prima (quella di adesso
    ; per P_SLOW_BACK), mai oltre la massima e mai più ripida di 45 gradi
    jsr slow_end
    mulq16 ball_vx, {#P_SLOW_BACK}
    mov32 ball_vx, m_a
    cmp32 max_ball, ball_vx
    bpl :+
    mov32 ball_vx, max_ball
    jmp vy
:   neg32 n_t, max_ball
    cmp32 ball_vx, n_t
    bpl vy
    mov32 ball_vx, n_t
vy:
    mulq16 ball_vy, {#P_SLOW_BACK}
    mov32 ball_vy, m_a
    abs32 n_u, ball_vx
    jsr clamp_vy
    ldx n_side
kinds:
    lda nx_kind,x
    cmp #K_TWIST
    jne hammer
    ; TWIST: la palla prende parte della velocità della racchetta, entro i 45 gradi
    mulq16 {pad_motion,x}, {#P_TWIST_TRANSFER}
    add32 ball_vy, ball_vy, m_a
    abs32 n_u, ball_vx
    jsr clamp_vy
    jmp armed
hammer:
    cmp #K_HAMMER
    jne rush
    ; HAMMER: tiro più veloce se la palla non ha già un boost e non c'è SMASH o SUPER
    beq32 ball_boost, {#ONE}, :+
    jmp armed
:   jsr smash_or_super
    jcs armed
    mov32 ball_boost, {#P_HAMMER_MUL}
    jmp armed
rush:
    cmp #K_RUSH
    jne armed
    ; RUSH dalla posizione avanzata: tiro più veloce, se non c'è SMASH o SUPER
    beq32 {pad_x,x}, {pad_home,x}, armed
    jsr smash_or_super
    jcs armed
    mulq16 ball_boost, {#P_RUSH_MUL}
    mov32 ball_boost, m_a
armed:
    ldx n_side
    lda nx_armed,x
    pha
    lda #B_NONE
    sta nx_armed,x
    pla
    cmp #B_SMASH
    jeq smash
    cmp #B_SUPER
    jeq super
    cmp #B_CURVE
    jeq curve
    cmp #B_GHOST
    jeq ghost
    cmp #B_STEER
    jeq steer
    rts
smash:
    ; schiacciata: veloce e angolata lontano dalla racchetta avversaria
    mov32 ball_boost, {#P_SMASH_MUL}
    abs32 n_t, ball_vx
    mov32 n_u, n_t
    asr32 n_u
    asr32 n_u
    sub32 n_t, n_t, n_u
    jsr away_from
    event EV_BOOST
    rts
super:
    mov32 ball_boost, {#P_SUPER_MUL}
    abs32 n_t, ball_vx           ; a 45 gradi
    jsr away_from
    lda #1
    sta nx_super
    ldx n_side
    lda nx_anim,x
    sta nx_super_a
    cmp #ANIM_HITSTOP
    bne :+
    lda #<P_HITSTOP
    sta nx_freeze
    lda #>P_HITSTOP
    sta nx_freeze+1
:   event EV_SUPER
    rts
curve:
    ; curva verso il lato opposto a quello in cui sale o scende
    lda ball_vy+3
    bmi :+
    mov32 nx_curve, {#-P_CURVE_ACCEL}
    rts
:   mov32 nx_curve, {#P_CURVE_ACCEL}
    rts
ghost:
    lda #1
    sta nx_ghost
    lda n_side
    sta nx_ghost_s
    rts
steer:
    lda #1
    sta nx_steer
    lda n_side
    sta nx_steer_s
    rts
.endproc

; C = 1 se il giocatore n_side ha armato SMASH o SUPER.
.proc smash_or_super
    ldx n_side
    lda nx_armed,x
    cmp #B_SMASH
    jeq yes
    cmp #B_SUPER
    jeq yes
    clc
    rts
yes:
    sec
    rts
.endproc

; vy = n_t verso il bordo lontano dalla racchetta avversaria (away_from di next.rs).
.proc away_from
    lda n_side
    eor #4
    tax
    cmp32 ball_y, {pad_y,x}     ; y della palla < y dell'avversario: verso il basso
    bpl :+
    neg32 ball_vy, n_t
    rts
:   mov32 ball_vy, n_t
    rts
.endproc

; Match::next_barrier: la palla mancata dal GUARDIAN X rimbalza sul settore del muro dietro la
; racchetta in cui sta il suo centro, se c'è ancora, e il settore sparisce (il muro non torna).
; C = 1 se ha rimbalzato.
.proc next_barrier
    lda nx_barrier,x
    jeq no
    cpx #0
    jne right
    ; sinistra: palla.sinistra <= linea
    sub32 n_t, ball_x, ball_r
    blt32 {#P_GUARDIAN_X}, n_t, no
    jmp hit
right:
    add32 n_t, ball_x, ball_r
    blt32 n_t, {#P_WIDTH - P_GUARDIAN_X}, no
hit:
    ; settore della y della palla: dopo i bordi è tra 0 e 199, basta la parte intera
    lda ball_y+2
    jsr g_sector
    and nx_barrier,x
    jeq no                      ; settore già caduto: punto
    eor nx_barrier,x
    sta nx_barrier,x
    stx n_side
    jsr clear_shot
    ldx n_side
    ; rimbalzo semplice: niente accelerazione
    mov32 ball_boost, {#ONE}
    mov32 ball_r, {#P_BALL_R}
    neg32 ball_vx, ball_vx
    cpx #0
    bne :+
    add32 ball_x, {#P_GUARDIAN_X}, ball_r
    sec
    rts
:   sub32 ball_x, {#P_WIDTH - P_GUARDIAN_X}, ball_r
    sec
    rts
no:
    clc
    rts
.endproc

; guardian_sector: bit del settore del muro all'altezza A (parte intera della y del core, che va
; verso l'alto, 0-255; i confini sono pixel interi, quindi il confronto è esatto). Il settore è
; il numero di confini con y < confine (0 in alto); con i confini decrescenti è il primo indice
; da destra con y < confine. Y = settore. Usa solo A e Y.
.proc g_sector
    ldy #G_SECTORS - 1
:   cmp g_bounds-1,y
    bcc done
    dey
    bne :-
done:
    lda col_bit,y
    rts
.endproc

g_bounds: .byte <(P_GUARDIAN_B1 >> 16), <(P_GUARDIAN_B2 >> 16), <(P_GUARDIAN_B3 >> 16)
          .byte <(P_GUARDIAN_B4 >> 16)
.assert G_SECTORS = 5, error, "g_bounds: un confine per settore oltre il primo"
.assert (P_GUARDIAN_B1 | P_GUARDIAN_B2 | P_GUARDIAN_B3 | P_GUARDIAN_B4) & $FF00FFFF = 0, error, "confini del GUARDIAN: pixel interi sotto 256"
.assert P_GUARDIAN_TOP > P_GUARDIAN_B1 .and P_GUARDIAN_B1 > P_GUARDIAN_B2 .and P_GUARDIAN_B2 > P_GUARDIAN_B3 .and P_GUARDIAN_B3 > P_GUARDIAN_B4, error, "confini del GUARDIAN decrescenti, dall'alto"
.assert P_HEIGHT <= $1000000, error, "g_sector: y della palla in un byte"

; Match::next_on_point: finiscono gli effetti sulla palla, il BULLET in corso (quello armato
; resta) e le mosse speciali armate; chi ha subito il punto carica la barra (sm_point).
.proc next_on_point
    jsr sm_point
    jsr clear_shot
    jsr slow_end
    lda nx_btimer
    beq :+
    jmp bullet_end
:   rts
.endproc
