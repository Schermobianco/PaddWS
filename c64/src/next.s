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

K_ARCADE   = 0                  ; (zero: i confronti con l'ARCADE sono lda/beq)
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

; salto corto a `target` se il byte k di a e quello di b sono diversi
.macro ne8_to pa, pb, k, target
    op8 lda, {pa}, k
    op8 cmp, {pb}, k
    bne target
.endmacro

; salto corto a `target` se a != b (32 bit)
.macro ne32_to pa, pb, target
    .repeat 4, k
    ne8_to {pa}, {pb}, k, target
    .endrepeat
.endmacro

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
nx_dash = nx_res + 3            ; nel quarto byte: scatto in questo tick (move_capsules lo azzera)
nx_sel:    .res 8
nx_armed:  .res 8
nx_anim:   .res 8
nx_cool:   .res 8               ; pausa prima di un altro bonus (16 bit)
nx_kind:   .res 8
nx_ammo:   .res 8
nx_gap:    .res 8               ; pausa prima del colpo successivo (16 bit)
nx_reload: .res 8               ; ricarica del caricatore (16 bit)
nx_lslow:  .res 8               ; rallentamento lieve da colpo laser del BLASTER (1 byte per lato)
nx_atap:   .res 8               ; ARCADE: finestra doppio clic su USE a riserva vuota (1 byte)
nx_barrier: .res 8              ; GUARDIAN: settori del muro in piedi, bit 0 = settore 0
nx_morph:  .res 1               ; OMEGA: lato (0 o 4) che cambia forma a ogni punto subito ($FF nessuno)
; colpi del BLASTER: 8 posti (4 per giocatore, prima il sinistro: posto = lato * 4 + k, cioè
; X del giocatore + k), passo 4; la velocità è +P_SHOT_SPEED per il sinistro, -P_SHOT_SPEED per
; il destro (move_shots)
MAX_SHOTS = 4
shot_on:   .res 2 * MAX_SHOTS
shot_x:    .res 8 * MAX_SHOTS
shot_y:    .res 8 * MAX_SHOTS
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
s_ex:      .res 1               ; shift extra adattivo del BULLET sulla palla (0, 1 o 2)
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
.assert P_BLASTER_SLOW < 256, error, "rallentamento del laser del BLASTER in un byte"
.assert P_ARCADE_TAP < 256, error, "finestra doppio clic ARCADE in un byte"
.assert P_BULLET_CUT < $10000 .and P_SUPER_CUT <= P_BULLET_CUT, error, "capsule: estrazione a 16 bit"

.segment "ZEROPAGE"
n_i:    .res 1                  ; indice in esame (capsula, colpo)
n_j:    .res 1
n_side: .res 1
n_t:    .res 4
m_next:      .res 1
n_u:    .res 4
bm_kx:  .res 1                  ; s_k + 4 * s_ex del passo orizzontale in bm_dx (ball_slowed)

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
    sta nx_anim,x
    sta nx_cool,x
    sta nx_cool+1,x
    sta nx_lslow,x
    sta nx_atap,x
    lda cfg_kinds,x
    sta nx_kind,x
    jsr set_kind
    inx
    inx
    inx
    inx
    cpx #8
    bne pl
    ; OMEGA (Match::set_morph): la CPU di CHALLENGE al livello CH_OMEGA
    ldx #$ff
    lda cg_active
    beq :+
    lda ch_level
    cmp #CH_OMEGA
    bne :+
    lda ch_side
    eor #4
    tax
:   stx nx_morph
    lda #0
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

; Match::set_paddle_kind: la racchetta X prende il tipo nx_kind,x, con lo stato del tipo (muro del
; GUARDIAN intero, caricatore del BLASTER pieno, nessun colpo in volo, pausa e ricarica a 0). A
; inizio partita (next_init) e alle trasformazioni di OMEGA (next_morph). X resta.
.proc set_kind
    lda #0
    sta tp_ok,x                 ; (la previsione del TELEPORT si rifà)
    sta nx_gap,x
    sta nx_gap+1,x
    sta nx_reload,x
    sta nx_reload+1,x
    sta nx_atap,x
    .assert MAX_SHOTS = 4, error, "set_kind: quattro posti per giocatore"
    sta shot_on,x
    sta shot_on+1,x
    sta shot_on+2,x
    sta shot_on+3,x
    ldy nx_kind,x
    cpy #K_BLASTER
    bne :+
    lda #P_BLASTER_SHOTS
:   sta nx_ammo,x
    lda #0
    cpy #K_GUARDIAN
    bne :+
    lda #G_WALL                 ; il muro intero
:   sta nx_barrier,x
.endproc
; (prosegue)
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
    beq done
    lda #1
    ldy nx_res+1,x
    cpy #B_NONE
    beq done
    lda #2
    ldy nx_res+2,x
    cpy #B_NONE
    beq done
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
    lda in_dir,x
    ldy in_flags,x
    bpl set
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
    mov32 n_u, {pad_half,x}         ; (pad_half = pad_h >> 1)
    asr32 n_u
    asr32 n_u                       ; dead = altezza / 8
    mov32 s_w, n_u                  ; (temporanea: nessuna moltiplicazione qui)
    add32 n_u, {pad_y,x}, n_u
    cmp32 n_u, n_t                  ; y + dead < goal: su
    bpl :+
    lda #1
    rts
:   sub32 n_u, {pad_y,x}, s_w
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
    beq activate
    ; seleziona: il successivo, in giro
    jsr res_count
    beq activate
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
    ; toglie il selezionato dalla riserva, compattando gli altri; se vuota e ARCADE, doppio clic chiama un bonus
    jsr res_count
    bne has_bonus
    lda nx_kind,x               ; (K_ARCADE = 0)
    jne done
    lda nx_atap,x
    bne arcade_call
    lda #P_ARCADE_TAP
    sta nx_atap,x
    rts
arcade_call:
    lda #0
    sta nx_atap,x
    stx n_side
    ; nessuna capsula già in arrivo verso questo lato: verso sinistra vx < 0, verso destra
    ; vx >= 0, cioè il segno di vx xor  a destra (n_j = lato << 5)
    txa
    asl a
    asl a
    asl a
    asl a
    asl a
    sta n_j
    ldy #0                      ; posto
    ldx #0                      ; posto * 4
chk_c:
    lda cap_on,y
    beq next_c
    lda cap_vx+3,x
    eor n_j
    jmi done
next_c:
    inx
    inx
    inx
    inx
    iny
    cpy #4
    bne chk_c
    lda n_side
    jsr spawn_to_side
    jcc done
    ldx n_side
    lda #<P_COOLDOWN
    sta nx_cool,x
    lda #>P_COOLDOWN
    sta nx_cool+1,x
    event EV_COLLECT
    rts
has_bonus:
    sta n_t                     ; n
    tay
    lda #0
    sta nx_atap,x
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
    bpl done
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
    ; selezionato: se era l'ultimo (o oltre), uno indietro
    lda nx_sel,x
    beq pause
    cmp n_t+1
    bcc pause
    dec nx_sel,x
pause:
    ; pausa prima del bonus successivo (più breve con l'ARCADE)
    lda nx_kind,x
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
    beq slow
    cmp #B_BULLET
    jeq bullet
    cmp #B_SUPER
    bne arm
    ; SUPER: animazione a caso
    stx n_side
    jsr rng_below3
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
    jsr abs_vx_t
    cmp32 n_t, {#2 * P_SERVE_UNIT}
    bpl vy
    lda ball_vx+3
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
; zona del BULLET (Next::bullet_trigger), oggi anche lei la metà campo; Y = ZONE_NEAR: a
; ZONE_NEAR_PX pixel dal bordo, il colpo o il punto a pochi tick (om_early). Le soglie sono pixel
; interi: a sinistra basta la parte intera di x (x < T se e solo se int(x) < T), a destra la
; sottrazione T - x è intera. X e Y restano.
ZONE_HALF    = 0
ZONE_BULLET  = 1
ZONE_NEAR    = 2
.ifdef ROTATED
ZONE_NEAR_PX = 112 * 200 / 320  ; (campo girato: gli stessi tick, la palla attraversa i 200 pixel nel tempo dei 320)
.else
ZONE_NEAR_PX = 112
.endif
.proc ball_in_zone
    jsr ball_toward
    bcc no
    cpx #0
    bne right
    sec
    lda ball_x+2
    sbc zone_l,y
    lda ball_x+3
    sbc zone_l+3,y
    jmp sign
right:
    sec
    lda #0
    sbc ball_x
    lda #0
    sbc ball_x+1
    lda zone_r,y
    sbc ball_x+2
    lda zone_r+3,y
    sbc ball_x+3
sign:
    bvc :+
    eor #$80
:   asl a                       ; il segno della differenza
no:
    rts
.endproc

; soglie (parte intera, 16 bit): byte bassi delle tre, poi byte alti
zone_l: .byte <(P_WIDTH >> 17), <(P_BULLET_ZONE >> 16), <ZONE_NEAR_PX
        .byte >(P_WIDTH >> 17), >(P_BULLET_ZONE >> 16), >ZONE_NEAR_PX
zone_r: .byte <(P_WIDTH >> 17), <((P_WIDTH - P_BULLET_ZONE) >> 16), <((P_WIDTH >> 16) - ZONE_NEAR_PX)
        .byte >(P_WIDTH >> 17), >((P_WIDTH - P_BULLET_ZONE) >> 16), >((P_WIDTH >> 16) - ZONE_NEAR_PX)
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
    beq free
    iny
    dex
    bne :-
    ldx n_side_x
    rts
free:
    ldx n_side_x
    lda #1
    sta shot_on,y
    lsr a
    sta shot_safe,y             ; le capsule si guardano dal primo passo (move_shots)
    tya
    asl a
    asl a
    tay                         ; Y = posto * 4
    cpx #0
    bne right
    add32 {shot_x,y}, {pad_x,x}, {#P_PAD_HALF_W}
    jmp sy
right:
    sub32 {shot_x,y}, {pad_x,x}, {#P_PAD_HALF_W}
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
; previsione del TELEPORT tenuta da parte, per giocatore (passo 4): y già nei limiti della
; racchetta (la scrive teleport), x della racchetta (parte intera), palla (spostamento, vy, raggio
; intero, x all'ultima chiamata), passi rimasti, valida
tp_y:   .res 8
tp_cx:  .res 8
tp_dx:  .res 8
tp_vy:  .res 8
tp_r:   .res 8
tp_bx:  .res 8
tp_n:   .res 8
tp_ok:  .res 8
.segment "CODE"

; x delle racchette in pixel interi (casa e avanzata, anche quelle dei tipi): la chiave del
; TELEPORT ne guarda solo la parte intera
.macro kfwd_check k0, k1, k2, k3, k4, k5, k6, k7
    .assert (k0 | k1 | k2 | k3 | k4 | k5 | k6 | k7) & $FFFF = 0, error, "kind_fwd: x intere"
.endmacro
kfwd_check T_KIND_FWD
.assert (P_PAD_START | P_PAD_FWD | P_WIDTH) & $FFFF = 0, error, "racchette: x intere"

; arrival_y per il TELEPORT del giocatore c_side (X = c_side all'uscita). Il core la rifà a ogni
; tick; su un tratto rettilineo il risultato non cambia: si tiene finché la palla avanza di ball_dx
; a ogni tick con la stessa velocità e lo stesso raggio, la racchetta non cambia x e restano passi
; da fare. Se il BULLET ha rallentato l'ultimo passo della palla (s_k dell'ultimo
; next_ball_motion, che nessuno cambia prima del TELEPORT) la y non è avanzata di ball_vy ma di
; ball_dy: un passo in meno, la y senza bordi prende ball_dy - vy e si rifanno solo i bordi (come
; pred_advance di cpu.s, qui dentro).
; C = 1: vale quella tenuta da parte (tp_y, già nei limiti; c_y non è scritta); C = 0: c_y nuova
; (rifatta o aggiornata), da portare nei limiti.
.proc tp_arrival
    ldx c_side
    lda tp_ok,x
    beq miss
    ne32_to {tp_vy,x}, ball_vy, miss    ; (prima la chiave che cambia più spesso)
    ne8_to {tp_cx,x}, {pad_x,x}, 2, miss
    ne8_to {tp_cx,x}, {pad_x,x}, 3, miss
    lda tp_r,x                  ; (il raggio è intero: conta il byte 2)
    cmp ball_r+2
    beq same
miss:
    jmp compute
same:
    ; un passo di ball_dx dall'ultima chiamata: lo stesso passo (tp_dx) e la x di allora (tp_bx)
    ; più il passo è quella di adesso, cioè x - dx è la x di allora
    ne32_to {tp_dx,x}, ball_dx, miss
    sec
    .repeat 4, k
    lda ball_x+k
    sbc ball_dx+k
    eor tp_bx+k,x               ; (eor: il prestito resta)
    bne miss
    .endrepeat
    dec tp_n,x                  ; un passo in meno; all'arrivo si rifà
    beq compute
    jsr keep_x
    lda s_k
    bne slowed
    sec
    rts
slowed:
    ; y senza bordi (pred_y) + ball_dy - vy, poi i bordi (fold_y)
    txa
    ora #8
    tay
    clc
    .repeat 4, k
    lda pred_y+k,y
    adc ball_dy+k
    sta c_y+k
    .endrepeat
    sec
    .repeat 4, k
    lda c_y+k
    sbc ball_vy+k
    sta c_y+k
    sta pred_y+k,y
    .endrepeat
    jsr fold_y                  ; (X = c_side)
    clc
    rts
compute:
    lda #8
    sta c_tp
    jsr arrival_y
    ldx c_side
    lda pad_x+2,x
    sta tp_cx+2,x
    lda pad_x+3,x
    sta tp_cx+3,x
    mov32 {tp_dx,x}, ball_dx
    mov32 {tp_vy,x}, ball_vy
    lda ball_r+2
    sta tp_r,x
    jsr keep_x
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
    clc
    rts
keep_x:
    ; la x di adesso, per il tick dopo
    .repeat 4, k
    lda ball_x+k
    sta tp_bx+k,x
    .endrepeat
    rts
.endproc

; Match::next_tick: pause, caricatore, TELEPORT, capsule, colpi del BLASTER e, per ultime, le
; mosse speciali (sm_tick).
.proc next_tick
    ; pause tra due bonus e due colpi, rallentamento da laser, ricarica del caricatore (prima il
    ; destro: i due giocatori non dipendono l'uno dall'altro)
    ldx #4
loop:
    dec16_sat {nx_cool,x}
    dec16_sat {nx_gap,x}
    lda nx_lslow,x
    beq :+
    dec nx_lslow,x
:   lda nx_atap,x
    beq :+
    dec nx_atap,x
:   lda nx_reload,x
    ora nx_reload+1,x
    beq next
    lda nx_reload,x
    bne :+
    dec nx_reload+1,x
:   dec nx_reload,x
    bne next
    lda nx_reload+1,x
    bne next
    lda #P_BLASTER_SHOTS
    sta nx_ammo,x
next:
    dex
    dex
    dex
    dex
    bpl loop
    ; TELEPORT (non durante l'attesa della battuta), per chi l'ha armato
    or32 serve_timer
    bne caps
    .assert B_TELEPORT = 0, error, "next_tick: TELEPORT armato con lda/bne"
    lda nx_armed
    bne :+
    ldx #0
    jsr teleport
:   lda nx_armed+4
    bne caps
    ldx #4
    jsr teleport
caps:
    ; una capsula ogni tanto: alla fine dell'attesa (nx_spawn, che non scende sotto zero)
    lda nx_spawn
    ora nx_spawn+1
    beq spawn
    lda nx_spawn
    bne :+
    dec nx_spawn+1
:   dec nx_spawn
    bne move
    lda nx_spawn+1
    bne move
spawn:
    jsr spawn_capsule
move:
    jsr move_capsules
    jsr move_shots
    jmp sm_tick
.endproc

; TELEPORT del giocatore X, che l'ha armato (next_tick): passata la metà campo, la racchetta salta
; dove arriverà la palla e resta sul punto previsto (rifatto a ogni tick) fino al colpo.
.assert P_HEIGHT < $01000000, error, "teleport: altezze in 24 bit"
.proc teleport
    ; la palla viene verso di sé ed è oltre la metà campo
    ldy #ZONE_HALF
    jsr ball_in_zone
    jcc no
    stx c_side
    jsr tp_arrival              ; c_y, o C = 1 (X = c_side)
    bcc fresh
    ; il punto tenuto da parte (già nei limiti) è quello del tick prima, dove la racchetta è stata
    ; messa: se è ancora lì ferma, il salto è nullo e le scritture non cambiano niente
    ne32_to {pad_y,x}, {tp_y,x}, moved
    lda pad_speed,x
    ora pad_speed+1,x
    ora pad_speed+2,x
    ora pad_speed+3,x
    bne moved
    rts
moved:
    mov32 c_y, {tp_y,x}
    jmp jump
fresh:
    ; tra metà altezza e H - metà altezza. c_y (tra r + 1 e H - 1 - r, come la danno arrival_y
    ; e fold_y), la metà altezza e H - metà sono positive e sotto 2^24: il byte alto è 0, si
    ; confrontano senza segno dal byte 2
    lda c_y+2
    cmp pad_half+2,x
    bne :+
    lda c_y+1
    cmp pad_half+1,x
    bne :+
    lda c_y
    cmp pad_half,x
:   bcs :+
    mov32 c_y, {pad_half,x}
:   sec
    lda #<P_HEIGHT
    sbc pad_half,x
    sta n_t
    lda #>P_HEIGHT
    sbc pad_half+1,x
    sta n_t+1
    lda #^P_HEIGHT
    sbc pad_half+2,x
    sta n_t+2                   ; (byte alto 0)
    cmp c_y+2
    bne :+
    lda n_t+1
    cmp c_y+1
    bne :+
    lda n_t
    cmp c_y
:   bcs :+
    lda n_t                     ; c_y = H - metà (il byte alto resta 0)
    sta c_y
    lda n_t+1
    sta c_y+1
    lda n_t+2
    sta c_y+2
:
jump:
    ; il salto vero (oltre un quarto di racchetta) ha la sua animazione; pad_half è pad_h >> 1
    ; (half_height), quindi pad_h >> 2 = pad_half >> 1. Anche pad_y sta nel campo: tutto in 3
    ; byte, |c_y - pad_y| < 2^24 (C = 0 dopo la sottrazione: differenza negativa)
    sec
    lda c_y
    sbc pad_y,x
    sta n_t
    lda c_y+1
    sbc pad_y+1,x
    sta n_t+1
    lda c_y+2
    sbc pad_y+2,x
    sta n_t+2
    bcs :+
    sec
    lda #0
    sbc n_t
    sta n_t
    lda #0
    sbc n_t+1
    sta n_t+1
    lda #0
    sbc n_t+2
    sta n_t+2
:   ; |d| > pad_half >> 1, cioè (interi) 2 |d| > pad_half: |d| > m = floor(h / 2) vuol dire
    ; |d| >= m + 1, 2 |d| >= 2 m + 2 > h; e 2 |d| > h >= 2 m vuol dire |d| > m
    asl n_t
    rol n_t+1
    rol n_t+2
    bcs jumped                  ; (2 |d| >= 2^24 > pad_half)
    lda pad_half+2,x
    cmp n_t+2
    bne :+
    lda pad_half+1,x
    cmp n_t+1
    bne :+
    lda pad_half,x
    cmp n_t
:   bcs :+
jumped:
    event EV_TELEPORT
:   ; la racchetta sul punto, e il punto (nei limiti) per i tick dopo: con quello tenuto da parte
    ; (moved) tp_y non cambia
    .repeat 4, k
    lda c_y+k
    sta pad_y+k,x
    sta tp_y+k,x
    .endrepeat
    lda #0
    sta pad_speed,x
    sta pad_speed+1,x
    sta pad_speed+2,x
    sta pad_speed+3,x
no:
    rts
.endproc

; A = numero a caso sotto 3 (Rng::below(3)).
.proc rng_below3
    lda #3
    sta m_b
    lda #0
    sta m_b+1
    jmp rng_below
.endproc

; Una capsula ogni tanto dalla mezzeria, verso un giocatore, con uno dei suoi bonus, il SUPER o
; il BULLET: next_tick la chiama alla fine dell'attesa (nx_spawn a zero).
.proc spawn_capsule
    ; prossima: con un ARCADE in campo più spesso
    lda nx_kind                 ; (K_ARCADE = 0)
    beq arcade
    lda nx_kind+4
    beq arcade
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
    beq free
    inx
    cpx #4
    bne :-
    rts
free:
    stx n_i
    ; verso chi: contro un solo ARCADE due su tre a lui, altrimenti a caso
    lda #0
    sta n_t
    lda nx_kind
    bne :+
    inc n_t
:   lda nx_kind+4
    bne :+
    lda n_t
    eor #2
    sta n_t
:   lda n_t
    beq coin
    cmp #3
    beq coin
    ; n_t = 1: ARCADE a sinistra, 2: a destra
    jsr rng_below3
    cmp #P_ARCADE_SHARE
    lda n_t
    bcc :+
    eor #3                      ; all'altro
:   cmp #1
    beq left
    jmp to_right
coin:
    jsr rng_next
    lda rng+3
    bmi to_right
left:
    lda #0
    beq side
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
    jsr rng_below3
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
    ; y a caso tra il basso e la fascia delle riserve: low + mul(high - low, frac). L'ampiezza è un
    ; numero intero R di pixel: mul(R * ONE, frac) = R * frac, un prodotto 8 x 16 (tabelle su R)
    jsr rng_next
    lda #<((CAP_HIGH - CAP_LOW) >> 16)
    sta sq1_lo
    sta sq1_hi
    eor #$ff
    sta sq2_lo
    sta sq2_hi
    ldx n_j
    ldy rng+2                   ; R * frac0: byte 0 e 1
    sec
    lda (sq1_lo),y
    sbc (sq2_lo),y
    sta cap_y,x
    lda (sq1_hi),y
    sbc (sq2_hi),y
    sta cap_y+1,x
    ldy rng+3                   ; R * frac1: byte 1 e 2
    sec
    lda (sq1_lo),y
    sbc (sq2_lo),y
    sta m_t
    lda (sq1_hi),y
    sbc (sq2_hi),y
    tay
    clc
    lda cap_y+1,x
    adc m_t
    sta cap_y+1,x
    tya                         ; + low (intero)
    adc #<(CAP_LOW >> 16)
    sta cap_y+2,x
    lda #0
    adc #0
    sta cap_y+3,x
    ldy n_j
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
:   lda #0                      ; capsula nuova: i colpi tornano a guardare le capsule (move_shots)
    .repeat 2 * ::MAX_SHOTS, k
    sta shot_safe+k
    .endrepeat
    inc nx_spawned
    bne :+
    inc nx_spawned+1
:   sec                         ; capsula generata (spawn_to_side)
done:
    rts
.endproc

; Genera una capsula diretta verso il lato A (0 o 4) nel primo posto libero (C = 1 se creata).
.proc spawn_to_side
    sta n_side
    ldx #0
:   lda cap_on,x
    beq free
    inx
    cpx #4
    bne :-
    clc
    rts
free:
    stx n_i
    lda n_side
    jmp spawn_capsule::side
.endproc

; Tick dello scatto (nx_dash): la x della capsula vale in tutto il tratto fra casa e la posizione
; avanzata, in pixel interi come nel core: parte intera fra quella del lato basso meno SW_REACH e
; quella del lato alto più SW_REACH. Lato basso e alto sono pad_home e pad_fwd (sinistra) o pad_fwd
; e pad_home (destra): indici 0 e 8 o 12 e 4 da pad_home.
SW_REACH = (P_CAP_HALF + P_PAD_HALF_W) >> 16
.assert (P_CAP_HALF + P_PAD_HALF_W) & $FFFF = 0, error, "scatto: metà capsula + metà larghezza intere"
.assert pad_fwd = pad_home + 8, error, "scatto: pad_fwd subito dopo pad_home"

; La capsula n_i (Y = n_i * 4) diretta al giocatore X la prende la racchetta se è alla sua altezza
; (|cy - py| <= metà capsula + metà altezza) e ha un posto libero nella riserva.
.proc cap_take
    sub32 n_t, {cap_y,y}, {pad_y,x}
    jsr abs_nt
    add32 n_u, {pad_half,x}, {#P_CAP_HALF}
    cmp32 n_u, n_t
    bmi done
    ; con la riserva piena passa oltre
    jsr res_count
    cmp #3
    beq done
    ldy n_i
    lda cap_bonus,y
    jsr res_push
    event EV_COLLECT
    ldx n_i
    lda #0
    sta cap_on,x
done:
    rts
.endproc

; Capsule in volo: rimbalzano tra il basso e la fascia delle riserve; chi le tocca con la
; racchetta (con un posto libero nella riserva) le prende; fuori dal campo spariscono. Con il
; BULLET rallentano tutte.
; La capsula nasce tra CAP_LOW e CAP_HIGH e ci resta dopo ogni passo; vx non cambia mai e vy cambia
; solo di segno (il passo, rallentato o no, ha il segno della velocità). Così basta guardare il
; bordo verso cui va: salendo y non scende sotto CAP_LOW, scendendo non supera CAP_HIGH, e y resta
; positiva (P_CAP_DRIFT < CAP_LOW). Anche x va sempre dalla mezzeria verso il suo lato: verso
; sinistra non supera W, verso destra resta positiva.
.assert P_CAP_DRIFT < CAP_LOW .and CAP_HIGH < $01000000, error, "capsule: y positiva e sotto 256 pixel"
.assert (CAP_LOW | P_CAP_HALF) & $FFFF = 0, error, "capsule: CAP_LOW e metà capsula in pixel interi"
.assert (CAP_HIGH - CAP_LOW) & $FF00FFFF = 0 .and CAP_LOW < $01000000, error, "spawn_capsule: ampiezza intera sotto 256 pixel"
.assert SW_REACH + 2 < 128, error, "capsule: portata della racchetta in un byte"
.proc move_capsules
    lda nx_btimer               ; shift 0 senza il BULLET scattato
    beq :+
    jsr bullet_shift
    jsr set_ki                  ; s_ki serve solo ai passi rallentati (A resta)
:   sta s_k
    ldx #0
cap:
    lda cap_on,x
    bne live
next:
    inx
    cpx #4
    bne cap
    lda #0
    sta nx_dash
    sta nx_dash+4
    rts
live:
    stx n_i
    txa
    asl a
    asl a
    tay
    lda s_k
    jne slowed
    add32 {cap_x,y}, {cap_x,y}, {cap_vx,y}
    clc
    lda cap_y,y
    adc cap_vy,y
    sta cap_y,y
    lda cap_y+1,y
    adc cap_vy+1,y
    sta cap_y+1,y
moved:
    ; il passo verticale sta in 16 bit con il segno (P_CAP_DRIFT < $10000): i due byte bassi sono
    ; già sommati, C è il riporto; i byte alti del passo sono 0 (sale) o $FFFF (scende)
    lda cap_vy+3,y
    bmi down
    bcc up
    lda cap_y+2,y
    adc #0
    sta cap_y+2,y
    lda cap_y+3,y
    adc #0
    sta cap_y+3,y
up:
    ; sale: CAP_HIGH < y, cioè y >= CAP_HIGH + 1 (positive: confronto senza segno)
    lda cap_y,y
    cmp #<(CAP_HIGH + 1)
    lda cap_y+1,y
    sbc #>(CAP_HIGH + 1)
    lda cap_y+2,y
    sbc #^(CAP_HIGH + 1)
    lda cap_y+3,y
    sbc #<((CAP_HIGH + 1) >> 24)
    bcc toward
    mov32 {cap_y,y}, {#CAP_HIGH}
    jmp flip                    ; vy = -|vy| = -vy
down:
    bcs dn                      ; + $FFFF + C: con il riporto i byte alti non cambiano
    lda cap_y+2,y
    sbc #0                      ; C = 0: meno uno
    sta cap_y+2,y
    lda cap_y+3,y
    sbc #0
    sta cap_y+3,y
dn:
    ; scende: y < CAP_LOW, dalla parte intera (CAP_LOW intero, y positiva)
    lda cap_y+2,y
    cmp #<(CAP_LOW >> 16)
    lda cap_y+3,y
    sbc #>(CAP_LOW >> 16)
    bcs toward
    mov32 {cap_y,y}, {#CAP_LOW}
flip:
    neg32 {cap_vy,y}, {cap_vy,y}    ; in basso vy = |vy| = -vy
toward:
    ; il giocatore verso cui va (vx < 0: sinistra)
    ldx #0
    lda cap_vx+3,y
    bmi :+
    ldx #4
:   stx n_side
    ; tocca la racchetta: |cx - px| <= metà capsula + metà larghezza, poi l'altezza (cap_take).
    ; Prima le parti intere: e = int(cx) - int(px) vale floor(cx - px) o uno in più; con
    ; e >= SW_REACH + 2 o e <= -(SW_REACH + 2) la distanza è già oltre SW_REACH
    sec
    lda cap_x+2,y
    sbc pad_x+2,x
    sta n_t
    lda cap_x+3,y
    sbc pad_x+3,x
    beq e_pos
    cmp #$FF
    bne dash
    lda n_t
    cmp #<-(SW_REACH + 1)
    bcc dash
    bcs exact
e_pos:
    lda n_t
    cmp #SW_REACH + 2
    bcs dash
exact:
    sub32 n_t, {cap_x,y}, {pad_x,x}
    jsr abs_nt
    blt32 {#P_CAP_HALF + P_PAD_HALF_W}, n_t, dash
take:
    ; presa, la prova del campo qui sotto non cambia niente
    jsr cap_take
    lda n_i
    asl a
    asl a
    tay
    jmp out
dash:
    ; nel tick dello scatto anche il tratto saltato: cx + SW_REACH - basso >= 0, alto + SW_REACH - cx >= 0
    lda nx_dash,x
    beq out
    txa
    asl a
    adc n_side
    tax                         ; 0 a sinistra, 12 a destra: il lato basso del tratto
    clc
    lda cap_x+2,y
    adc #<SW_REACH
    sta n_t
    lda cap_x+3,y
    adc #>SW_REACH
    sta n_t+1
    sec
    lda n_t
    sbc pad_home+2,x
    lda n_t+1
    sbc pad_home+3,x
    bmi out
    txa
    eor #8
    tax
    clc
    lda pad_home+2,x
    adc #<SW_REACH
    sta n_t
    lda pad_home+3,x
    adc #>SW_REACH
    sta n_t+1
    sec
    lda n_t
    sbc cap_x+2,y
    lda n_t+1
    sbc cap_x+3,y
    bmi out
    ldx n_side
    jmp take
out:
    ; fuori dal campo, dal lato verso cui va (Y = posto * 4)
    ldx n_i
    lda cap_vx+3,y
    bpl right
    ; verso sinistra: cx + metà < 0; la metà è intera, bastano i due byte alti della somma
    clc
    lda cap_x+2,y
    adc #<(P_CAP_HALF >> 16)
    lda cap_x+3,y
    adc #>(P_CAP_HALF >> 16)
    bmi gone
    jmp next
right:
    ; verso destra: cx - metà > W, cioè cx >= W + metà + 1 (x positiva: senza segno; sotto i
    ; 256 pixel il byte alto è 0)
.ifdef ROTATED
    ; (campo girato: W + metà + 1 sotto i 256 pixel, e la capsula sparisce prima di arrivarci)
    .assert P_WIDTH + P_CAP_HALF + 1 < $01000000, error, "capsule: uscita a destra sotto i 256 pixel"
    lda cap_x,y
    cmp #<(P_WIDTH + P_CAP_HALF + 1)
    lda cap_x+1,y
    sbc #>(P_WIDTH + P_CAP_HALF + 1)
    lda cap_x+2,y
    sbc #^(P_WIDTH + P_CAP_HALF + 1)
    jcc next
.else
    lda cap_x+3,y
    jeq next
    lda cap_x,y
    cmp #<(P_WIDTH + P_CAP_HALF + 1)
    lda cap_x+1,y
    sbc #>(P_WIDTH + P_CAP_HALF + 1)
    lda cap_x+2,y
    sbc #^(P_WIDTH + P_CAP_HALF + 1)
    lda cap_x+3,y
    sbc #<((P_WIDTH + P_CAP_HALF + 1) >> 24)
    jcc next
.endif
gone:
    lda #0
    sta cap_on,x
    jmp next
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
:   clc                         ; due byte bassi, poi i byte alti dal segno (moved)
    lda cap_y,y
    adc cap_sy,x
    sta cap_y,y
    lda cap_y+1,y
    adc cap_sy+1,x
    sta cap_y+1,y
    jmp moved
.endproc
.assert P_CAP_DRIFT < $10000, error, "capsule: passo verticale in 16 bit con il segno"

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
; colpi del BLASTER (move_shots), indice passo * 8 + lato: 0 piena velocità, 1 P_BULLET_SHIFT, 2
; P_BULLET_RSHIFT; il passo (+ a sinistra, - a destra) e la portata |passo| + metà capsula
shot_step: .dword P_SHOT_SPEED, (-P_SHOT_SPEED) & $FFFFFFFF
shot_sx:   slow_consts P_SHOT_SPEED
SHOT_P1 = P_SHOT_SPEED - (P_SHOT_SPEED >> P_BULLET_SHIFT)     ; |passo| rallentato, a sinistra
SHOT_N1 = P_SHOT_SPEED - ((P_SHOT_SPEED + (1 << P_BULLET_SHIFT) - 1) >> P_BULLET_SHIFT)  ; e a destra
SHOT_P2 = P_SHOT_SPEED - (P_SHOT_SPEED >> P_BULLET_RSHIFT)
SHOT_N2 = P_SHOT_SPEED - ((P_SHOT_SPEED + (1 << P_BULLET_RSHIFT) - 1) >> P_BULLET_RSHIFT)
shot_reach: .dword P_SHOT_SPEED + P_CAP_HALF, P_SHOT_SPEED + P_CAP_HALF
            .dword SHOT_P1 + P_CAP_HALF, SHOT_N1 + P_CAP_HALF
            .dword SHOT_P2 + P_CAP_HALF, SHOT_N2 + P_CAP_HALF
.assert shot_sx = shot_step + 8, error, "shot_step: i passi rallentati subito dopo quelli pieni"
.segment "CODE"

; Colpi del BLASTER: attraversano la palla, raccolgono la prima capsula che toccano (con la
; riserva piena la distruggono) e si fermano sulla racchetta avversaria o fuori dal campo.
; I colpi di un giocatore vanno tutti alla stessa velocità (+/- P_SHOT_SPEED, rallentata dal
; BULLET con lo stesso shift): passo e portata vengono da shot_step e shot_reach, la faccia della
; racchetta avversaria si conta una volta per giocatore (la fascia solo per il colpo arrivato alla
; faccia), e le capsule in campo una volta per tick.
;
; Capsule lontane (shot_safe): guardate le capsule, un colpo sa per quanti tick nessuna può
; arrivargli vicino (alla portata: lo scarto veloce qui sotto non passa, e il confronto vero non
; si fa), e per quei tick non le guarda. Con le parti intere d = int(cx) - int(sx): in un tick d
; cambia al più di MS_CLOSE (passo pieno del colpo più quello della capsula, più 2 per le parti
; intere), e lo scarto veloce passa solo con |d| sotto MS_RLIM (la portata più grande, quella del
; passo pieno). Una capsula davanti al colpo a distanza e >= MS_RLIM resta lontana per almeno
; (e - MS_RLIM) / MS_CLOSE tick: shot_safe = (e - MS_RLIM) >> 4 (MS_CLOSE <= 16). Una capsula
; dietro al colpo non torna mai avanti: il colpo più lento va più veloce della capsula più veloce
; di almeno un pixel a tick (MS_GAIN), quindi d non cala (colpo del destro) o non cresce (colpo
; del sinistro); dietro di almeno MS_RLIM non passa più lo scarto veloce. Una capsula nuova azzera
; tutti i shot_safe (spawn_capsule), un colpo nuovo il suo (next_fire); le capsule che spariscono
; non contano. Il BULLET cambia i passi ma non i limiti: valgono per tutti i passi.
MS_RLIM  = ((P_SHOT_SPEED + P_CAP_HALF) >> 16) + 2
MS_CLOSE = ((P_SHOT_SPEED + P_CAP_SPEED) >> 16) + 2
.assert MS_CLOSE <= 16, error, "move_shots: shot_safe con lo shift di 4"
.assert SHOT_P1 <= P_SHOT_SPEED .and SHOT_P2 <= P_SHOT_SPEED, error, "move_shots: portata più grande con il passo pieno"
.assert SHOT_N1 >= P_CAP_SPEED + ONE .and SHOT_N2 >= P_CAP_SPEED + ONE .and SHOT_N1 <= SHOT_P1 .and SHOT_N2 <= SHOT_P2, error, "move_shots: colpi più veloci delle capsule di un pixel (MS_GAIN)"
ms_v    = m_p                   ; passo dei colpi del giocatore
ms_face = m_p + 4               ; parte intera della faccia della racchetta avversaria (2 byte)
ms_rlim = m_p + 6               ; parte intera della portata + 2 (scarto veloce delle capsule)
ms_y    = m_p + 7               ; posto del colpo * 4
ms_mask = m_p + 8               ; posti del giocatore con un colpo, ancora da muovere (bit 0 il prossimo)
ms_k    = m_p + 9               ; indice in shot_step e shot_reach
ms_min  = m_p + 10              ; distanza delle capsule vicine (shot_safe)
ms_cap  = m_a                   ; capsule in campo (posto * 4; $FF presa da un colpo)
ms_band = n_u                   ; metà altezza della racchetta avversaria + metà fascia dei colpi
ms_opp  = m_b                   ; avversario (0 o 4)
ms_sxl  = m_b + 1               ; parte intera della x del colpo in esame
ms_sxh  = m_b + 2
ms_ncap = m_b + 3               ; capsule in ms_cap (0 nessuna; $80 ci sono, ms_cap da fare)
.assert P_CAP_HALF + P_SHOT_SPEED < $00FD0000, error, "move_shots: portata in meno di 253 pixel"
.assert (P_PAD_HALF_W & $FFFF) = 0, error, "move_shots: faccia dalla parte intera della x"
.proc move_shots
    ; uscita rapida se non c'è nessun colpo in volo
    lda shot_on
    ora shot_on+1
    ora shot_on+2
    ora shot_on+3
    ora shot_on+4
    ora shot_on+5
    ora shot_on+6
    ora shot_on+7
    bne :+
    rts
:   ; capsule in campo: la lista (ms_cap) si fa solo se un colpo le guarda (look)
    lda cap_on
    ora cap_on+1
    ora cap_on+2
    ora cap_on+3
    beq :+
    lda #$80
:   sta ms_ncap
    lda #0
    sta n_side
side:
    ; posti con un colpo (bit k: posto k del giocatore)
    ldx n_side
    lda shot_on+3,x
    asl a
    ora shot_on+2,x
    asl a
    ora shot_on+1,x
    asl a
    ora shot_on,x
    jeq next_side
    sta ms_mask
    ; passo: indice in shot_step dallo shift del BULLET per i colpi del giocatore
    ; (Next::bullet_shift_for: 0 senza BULLET scattato o se l'ha attivato lui, P_BULLET_RSHIFT
    ; nella rampa, P_BULLET_SHIFT dopo)
    txa
    ldy nx_btimer
    beq got
    cpx nx_bside
    beq got
    ora #8                      ; P_BULLET_SHIFT
    cpy #2
    bcc got
    eor #8 ^ 16                 ; P_BULLET_RSHIFT
got:
    tay
    sty ms_k
    .repeat 4, k
    lda shot_step+k,y
    sta ms_v+k
    .endrepeat
    lda shot_reach+2,y          ; scarto veloce oltre parte intera della portata + 2 pixel
    clc
    adc #2
    sta ms_rlim
    ; racchetta avversaria: faccia (la parte intera; la fascia serve solo alla faccia, in height)
    lda n_side
    eor #4
    sta ms_opp
    tax
    beq left_pad
    sec
    lda pad_x+2,x
    sbc #<(P_PAD_HALF_W >> 16)
    sta ms_face
    lda pad_x+3,x
    sbc #>(P_PAD_HALF_W >> 16)
    jmp faced
left_pad:
    clc
    lda pad_x+2,x
    adc #<(P_PAD_HALF_W >> 16)
    sta ms_face
    lda pad_x+3,x
    adc #>(P_PAD_HALF_W >> 16)
faced:
    sta ms_face+1
    ldx n_side
    dex
    stx n_i                     ; posto 0-7 (0-3 sinistro, 4-7 destro), qui quello prima
skip:
    inc n_i
shot:
    lsr ms_mask                 ; il posto ha un colpo?
    bcc skip
    ldx n_i
    txa
    asl a
    asl a
    sta ms_y
    tay
    clc
    lda shot_x,y
    adc ms_v
    sta shot_x,y
    lda shot_x+1,y
    adc ms_v+1
    sta shot_x+1,y
    lda shot_x+2,y
    adc ms_v+2
    sta shot_x+2,y
    sta ms_sxl                  ; parte intera della x del colpo
    lda shot_x+3,y
    adc ms_v+3
    sta shot_x+3,y
    sta ms_sxh
    lda ms_ncap
    beq to_pad
    lda shot_safe,x             ; capsule lontane ancora per qualche tick
    beq look
    dec shot_safe,x
to_pad:
    jmp pad
look:
    bit ms_ncap
    bpl listed
    ; capsule in campo (posto * 4), nell'ordine dei posti
    ldx #0
    ldy #0
:   lda cap_on,x
    beq :+
    txa
    asl a
    asl a
    sta ms_cap,y
    iny
:   inx
    cpx #4
    bne :--
    sty ms_ncap
    tya
    beq to_pad                  ; prese tutte dai colpi prima
listed:
    lda #$FF
    sta ms_min
    ldy #0                      ; Y = indice in ms_cap
cap:
    ldx ms_cap,y                ; X = posto della capsula * 4 (bit 7: presa da un colpo prima)
    bmi next_cap
    ; parti intere lontane (|d| >= portata intera + 2: d - 1 pixel è già oltre la portata);
    ; per d < 0 si prende e = ~d = |d| - 1, che scarta al più qualcosa di meno
    lda cap_x+2,x
    sec
    sbc ms_sxl
    sta n_t
    lda cap_x+3,x
    sbc ms_sxh
    bpl pos
    eor #$FF
    bne next_cap                ; oltre 256 pixel (davanti o dietro: lontana)
    lda n_t
    eor #$FF
    cmp ms_rlim
    jcc exact
    ldx n_side                  ; d < 0: davanti al colpo del destro, dietro a quello del sinistro
    bne ahead
behind:
    cmp #MS_RLIM
    bcs next_cap                ; dietro per sempre
    lda #0                      ; dietro ma vicina: si guarda al prossimo tick
ahead:
    cmp ms_min
    bcs next_cap
    sta ms_min
next_cap:
    iny
    cpy ms_ncap
    bne cap
    ; tick per cui le capsule restano lontane
    ldx n_i
    lda ms_min
    sec
    sbc #MS_RLIM
    bcs :+
    lda #0
:   lsr a
    lsr a
    lsr a
    lsr a
    sta shot_safe,x
    jmp pad
pos:
    bne next_cap                ; oltre 256 pixel
    lda n_t
    cmp ms_rlim
    jcc exact
    ldx n_side                  ; d >= 0: davanti al colpo del sinistro, dietro a quello del destro
    bne behind
    beq ahead
pad:
    ; racchetta avversaria o fuori dal campo. Prima della faccia il colpo è ancora in campo: parte
    ; dalla sua racchetta e va verso l'altra, quindi tra 0 e W. La faccia è un pixel intero: a
    ; sinistra decide la parte intera, a destra anche la frazione se le parti intere sono uguali
    lda n_side
    bne hit_left
    ; colpo del sinistro: x >= faccia della racchetta destra (positive: senza segno)
    lda ms_sxl
    cmp ms_face
    lda ms_sxh
    sbc ms_face+1
    bcc next
    bcs height
hit_left:
    sec                         ; faccia - int(x): x e faccia tra 0 e W, nessun traboccamento
    lda ms_face
    sbc ms_sxl
    tax
    lda ms_face+1
    sbc ms_sxh
    bmi next
    bne height
    txa
    bne height
    ldy ms_y                    ; parti intere uguali: x <= faccia senza frazione
    lda shot_x,y
    ora shot_x+1,y
    beq height
next:
    lda ms_mask                 ; altri colpi del giocatore?
    beq next_side
    inc n_i
    jmp shot
next_side:
    lda n_side
    eor #4
    sta n_side
    jne side
    rts
height:
    ldy ms_y
    ldx ms_opp
    add32 ms_band, {pad_half,x}, {#P_BLASTER_BAND}
    sub32 n_t, {shot_y,y}, {pad_y,x}
    jsr abs_nt
    cmp32 ms_band, n_t
    bmi edge
    ; colpito l'avversario: rallentamento lieve della sua racchetta
    lda #P_BLASTER_SLOW
    sta nx_lslow,x
    jmp stop
edge:
    lda shot_x+3,y
    bmi stop
    blt32 {#P_WIDTH}, {shot_x,y}, stop
    jmp next
stop:
    ldx n_i
    lda #0
    sta shot_on,x
    jmp next
exact:
    ; candidata: il confronto vero (Y = colpo * 4), con la portata di questo passo
    sty n_j
    ldy ms_k
    mov32 n_u, {shot_reach,y}
    ldy ms_y
    sub32 n_t, {cap_x,x}, {shot_x,y}
    jsr abs_nt
    cmp32 n_u, n_t
    jmi miss
    sub32 n_t, {cap_y,x}, {shot_y,y}
    jsr abs_nt
    cmp32 {#P_CAP_HALF + P_BLASTER_BAND}, n_t
    bmi miss
    ; preso: nella riserva se c'è posto
    ldy n_j
    lda #$FF
    sta ms_cap,y                ; per i colpi dopo
    txa
    lsr a
    lsr a
    tax
    lda #0
    sta cap_on,x
    lda cap_bonus,x
    pha
    ldx n_side
    jsr res_count
    cmp #3
    pla
    bcs :+                      ; (riserva piena: C = 1 dal confronto)
    jsr res_push
:   event EV_COLLECT
    jmp stop
miss:
    lda #0                      ; vicina: si guarda al prossimo tick
    sta ms_min
    ldy n_j
    jmp next_cap
.endproc
.segment "NEXTBSS"
shot_safe: .res 2 * MAX_SHOTS   ; tick in cui le capsule restano lontane dal colpo (move_shots)
.segment "CODE"
.assert MAX_SHOTS = 4, error, "posti dei colpi: lato * 4 + k (X del giocatore + k)"

; ------------------------------------------------------------------------------------ palla

; Next::ball_motion: RISING STRIKE che s'impenna (sm_motion), palla a effetto (CURVE) o guidata
; (STEER), prima dello spostamento. Con il BULLET rallentano anche le accelerazioni con lo
; stesso fattore adattivo del passo (calcolato da |dx| in t0; il passo lo rallenta ball_slowed).
.proc next_ball_motion
    lda nx_btimer
    bne bullet
    sta s_k                     ; nessun BULLET scattato: piena velocità
    sta s_ex
    beq rise
bullet:
    cmp #2                      ; bullet_shift, qui dentro (nx_btimer in A)
    lda #P_BULLET_SHIFT
    bcc :+
    lda #P_BULLET_RSHIFT
:   jsr bullet_ball_set
rise:
    lda sm_rise
    beq :+
    jsr abs_vx                  ; mai più ripida di 45 gradi
    jsr sm_motion
:   or32 nx_curve
    beq steer
    jsr abs_vx
    mov32 s_v, nx_curve
    jsr slow_ball_v
    add32 ball_vy, ball_vy, s_v
    jsr clamp_vy
steer:
    lda nx_steer
    jeq slow
    ; si guida fino a 3/4 del campo, contati da chi ha colpito
    lda nx_steer_s
    bne right
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
    beq slow
    ; fino al doppio della velocità orizzontale (circa 63 gradi)
    jsr abs_vx
    asl32 n_u
    lda nx_steer_dir
    bmi down
    mov32 s_v, {#P_STEER_ACCEL}
    jmp accel
down:
    mov32 s_v, {#-P_STEER_ACCEL}
accel:
    jsr slow_ball_v             ; slowed_extra(-a) non è -slowed_extra(a): shift con il segno
    add32 ball_vy, ball_vy, s_v
    jsr clamp_vy
slow:
    lda nx_slow_s               ; con la palla rallentata l'alone resta
    bpl :+
    dec16_sat nx_slow
:   rts
.endproc

; Next::bullet_ball_slow: dato A = bullet_shift e t0 = dx, imposta (s_k, s_ex) in base a |dx|
; rispetto a 4, 8 e 16 volte P_SERVE_UNIT. Lascia t0 intatto, distrugge X. Confronto alto-prima
; per restare veloce anche nei tick BULLET più pesanti sull'NTSC.
.proc bullet_ball_set
    sta s_k
    ldy #0
    sty s_ex
    ora #0
    beq done
    ; |t0|: t0 stesso se positivo, altrimenti n_t = -t0 (X = indirizzo in pagina zero)
    ldx #t0
    lda t0+3
    bpl cmp_go
    neg32 n_t, t0
    ldx #n_t
cmp_go:
    ldy #3
    lda 3,x
    bne hit
    ldy #0
    ; Y = 0: <= 4x -> s_k=2; Y = 1: <= 8x -> s_ex=0; Y = 2: <= 16x -> s_ex=1; > 16x -> s_ex=2
loop:
    lda b_cap_hi,y
    cmp 2,x
    bcc next
    bne hit
    lda b_cap_md,y
    cmp 1,x
    bcc next
    bne hit
    lda b_cap_lo,y
    cmp 0,x
    bcs hit
next:
    iny
    cpy #3
    bne loop
hit:
    tya
    bne not_slow
    lda #2
    sta s_k
done:
    rts
not_slow:
    dey
    sty s_ex
    rts
.endproc

B_CAP0 = P_SERVE_UNIT << 2
B_CAP1 = P_SERVE_UNIT << 3
B_CAP2 = P_SERVE_UNIT << 4
.assert B_CAP2 < $01000000, error, "B_CAP2 deve stare in 3 byte"
.segment "RODATA"
b_cap_hi: .byte ^B_CAP0, ^B_CAP1, ^B_CAP2
b_cap_md: .byte >B_CAP0, >B_CAP1, >B_CAP2
b_cap_lo: .byte <B_CAP0, <B_CAP1, <B_CAP2
.segment "CODE"

; s_v = slowed_extra(v, s_k, s_ex), v nei 4 byte di pagina zero da Y. X resta.
.proc slow_ball_at
    lda s_k
    jsr slow_at
extra:
    ldy s_ex
    beq done
:   asr32 s_v
    dey
    bne :-
done:
    rts
.endproc

; s_v = slowed_extra(s_v, s_k, s_ex) = slowed(s_v, s_k) >> s_ex (con s_k = 0 anche s_ex è 0:
; invariato). X resta.
.proc slow_ball_v
    lda s_k
    beq done
    ldy #s_v
    jsr slow_at
    jmp slow_ball_at::extra
done:
    rts
.endproc

; BULLET (s_k e s_ex da next_ball_motion): spostamento rallentato, dx in t0 e la y (passo anche
; in ball_dy). Il passo verticale cambia di rado (rimbalzi, CURVE, STEER, fine della rampa): se
; vy, s_k e s_ex sono quelli dell'ultimo calcolo (bs_key) ball_dy è già il passo, che solo questa
; routine scrive. La chiave tiene i 3 byte bassi di vy e, nell'ultimo, s_k + 4 * s_ex + $10 se vy
; è negativa: vale solo con il byte alto di vy uguale al segno del byte 2 (vy in 24 bit con il
; segno), altrimenti l'ultimo byte è $FF e non coincide mai (s_k < 4, s_ex < 4).
; Anche il passo orizzontale si tiene da parte: con t0, s_k e s_ex dell'ultimo calcolo (bm_t0,
; bm_kx; s_k non è mai 0 qui, quindi bm_kx = 0 dall'avvio non coincide) vale bm_dx.
.proc ball_slowed
    lda s_ex
    asl a
    asl a
    ora s_k
    tax                         ; X = s_k + 4 * s_ex
    cpx bm_kx
    bne slow_dx
    .repeat 4, k
    lda t0+k
    cmp bm_t0+k
    bne slow_dx
    .endrepeat
    .repeat 4, k
    lda bm_dx+k                 ; stesso passo dell'ultima volta
    sta t0+k
    .endrepeat
    jmp dy
slow_dx:
    stx bm_kx
    ldy #3
:   lda t0,y
    sta bm_t0,y
    dey
    bpl :-
    ldy #t0
    jsr slow_ball_at            ; (X resta)
    ldy #3
:   lda s_v,y
    sta t0,y
    sta bm_dx,y
    dey
    bpl :-
dy:
    lda ball_vy+3
    beq pos
    cmp #$FF
    beq neg
    ldx #$FF                    ; fuori dai 24 bit: nessuna chiave
    bne new
neg:
    txa
    ora #$10
    tax
pos:
    lda ball_vy+2               ; con il segno del byte 2
    eor ball_vy+3
    bmi wide
    cpx bs_key+3
    bne new
    lda ball_vy
    cmp bs_key
    bne new
    lda ball_vy+1
    cmp bs_key+1
    bne new
    lda ball_vy+2
    cmp bs_key+2
    bne new
    add32 ball_y, ball_y, ball_dy   ; stesso passo dell'ultima volta
    jmp done
wide:
    ldx #$FF
new:
    stx bs_key+3
    lda ball_vy
    sta bs_key
    lda ball_vy+1
    sta bs_key+1
    lda ball_vy+2
    sta bs_key+2
    ldy #ball_vy
    jsr slow_ball_at
    clc
    .repeat 4, k
    lda s_v+k
    sta ball_dy+k
    adc ball_y+k
    sta ball_y+k
    .endrepeat
done:
    lda #1
    sta nx_bmoved
    rts
.endproc
.segment "BSS"
bs_key: .res 4                  ; chiave del passo verticale in ball_dy (ball_slowed)
bm_t0:  .res 4                  ; t0 dell'ultimo passo orizzontale rallentato
bm_dx:  .res 4                  ; e il passo (con s_k + 4 * s_ex di allora in bm_kx)
.segment "CODE"
.assert P_BULLET_SHIFT < 4 .and P_BULLET_RSHIFT < 4, error, "ball_slowed: s_k in due bit"

; Next::paddle_slow_shift: shift di rallentamento della racchetta X (BULLET avversario oppure
; shift 1 = -50% quando è stata colpita dal laser del BLASTER). X resta, Z = (A == 0).
.proc pad_slow_shift_x
    lda nx_btimer               ; Next::bullet_shift_for, qui dentro: chi ha attivato il BULLET
                                ; resta a piena velocità
    beq laser
    cpx nx_bside
    beq own
    cmp #2
    lda #P_BULLET_SHIFT
    bcc :+
    lda #P_BULLET_RSHIFT
:   cmp #1
    beq done
    bne laser
own:
    lda #0
laser:
    ldy nx_lslow,x
    beq done
    lda #1
done:
    ora #0
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

; s_v = slowed(s_v, A) = s_v - (s_v >> A), shift con il segno (A = 0: invariato). X resta.
.proc slow_v
    ldy #s_v
    cmp #0
    bne slow_at
    rts
.endproc

; s_v = slowed(v, A), v nei 4 byte di pagina zero da Y (anche s_v stesso). X e Y restano.
; Con A = 1: v - (v >> 1) = ceil(v / 2) = (v + 1) >> 1, con il segno vero della somma a 33 bit
; (V = 1 solo per v = $7FFFFFFF: somma positiva).
.proc slow_at
    cmp #1
    beq one
    bcc zero
    sta s_n
    ; w = v >> A: copia e primo shift insieme
    lda 3,y
    cmp #$80
    ror a
    sta s_w+3
    lda 2,y
    ror a
    sta s_w+2
    lda 1,y
    ror a
    sta s_w+1
    lda 0,y
    ror a
    sta s_w
    dec s_n
:   lda s_w+3
    cmp #$80
    ror s_w+3
    ror s_w+2
    ror s_w+1
    ror s_w
    dec s_n
    bne :-
    sec
    .repeat 4, k
    lda k,y
    sbc s_w+k
    sta s_v+k
    .endrepeat
    rts
zero:
    .repeat 4, k
    lda k,y
    sta s_v+k
    .endrepeat
    rts
one:
    sec
    .repeat 3, k
    lda k,y
    adc #0
    sta s_v+k
    .endrepeat
    lda 3,y
    adc #0
    bvs ovf
    cmp #$80                    ; C = segno
    jmp sh
ovf:
    clc
sh:
    ror a
    sta s_v+3
    ror s_v+2
    ror s_v+1
    ror s_v
    rts
.endproc

; n_u = |ball_vx| (condivisa tra next_ball_motion, SLOW e TWIST). X e Y restano.
.proc abs_vx
    abs32 n_u, ball_vx
    rts
.endproc

; n_t = |ball_vx| (SLOW, SMASH, SUPER); poi n_t = |n_t| (abs_nt). X e Y restano.
.proc abs_vx_t
    mov32 n_t, ball_vx
.endproc
; (prosegue)
.proc abs_nt
    lda n_t+3
    bpl done
    neg32 n_t, n_t
done:
    rts
.endproc

; vy tra -n_u e n_u. n_u è |vx|, 2 |vx| (STEER) o 1,75 |vx| (TWIST), e |vx| resta sotto la
; velocità massima della palla (pochi pixel per tick): n_u >= 0, quindi basta il limite dalla
; parte del segno di vy (vy >= 0 >= -n_u, vy < 0 <= n_u).
.proc clamp_vy
    lda ball_vy+3
    bmi low
    cmp32 n_u, ball_vy
    bpl :+
    mov32 ball_vy, n_u
:   rts
low:
    neg32 n_t, n_u
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
    ; P_SLOW_BACK è tra ONE e 2 ONE: mul(v, K) = v +/- (|v| * (K - ONE)) >> 16, come kspeed_mul (il
    ; fattore in m_a resta per vy)
    lda #<(P_SLOW_BACK - ONE)
    sta m_a
    lda #>(P_SLOW_BACK - ONE)
    sta m_a+1
    lda #0
    sta m_a+2
    sta m_a+3
    tax                         ; vx
    jsr kspeed_mul::one
    cmp32 max_ball, ball_vx
    bpl :+
    mov32 ball_vx, max_ball
    jmp vy
:   neg32 n_t, max_ball
    cmp32 ball_vx, n_t
    bpl vy
    mov32 ball_vx, n_t
vy:
    ldx #4
    jsr kspeed_mul::one
    jsr abs_vx
    jsr clamp_vy
    ldx n_side
kinds:
    lda nx_kind,x
    cmp #K_TWIST
    jne hammer
    ; TWIST: la palla prende parte della velocità della racchetta, fino a ~60 gradi (1,75 * |vx|)
    mulq16 {pad_motion,x}, {#P_TWIST_TRANSFER}
    add32 ball_vy, ball_vy, m_a
    jsr abs_vx                  ; n_u = |vx|; n_u += |vx| >> 1, poi += |vx| >> 2
    lda n_u+3
    lsr a
    sta n_t+3
    lda n_u+2
    ror a
    sta n_t+2
    lda n_u+1
    ror a
    sta n_t+1
    lda n_u
    ror a
    sta n_t
    clc
    .repeat 4, k
    lda n_u+k
    adc n_t+k
    sta n_u+k
    .endrepeat
    lsr n_t+3
    ror n_t+2
    ror n_t+1
    ror n_t
    clc
    .repeat 4, k
    lda n_u+k
    adc n_t+k
    sta n_u+k
    .endrepeat
    jsr clamp_vy
    jmp armed
hammer:
    cmp #K_HAMMER
    bne rush
    ; HAMMER: tiro più veloce se la palla non ha già un boost e non c'è SMASH o SUPER
    beq32 ball_boost, {#ONE}, :+
    jmp armed
:   jsr smash_or_super
    bcs armed
    mov32 ball_boost, {#P_HAMMER_MUL}
    jmp armed
rush:
    cmp #K_RUSH
    bne armed
    ; RUSH dalla posizione avanzata: tiro più veloce, se non c'è SMASH o SUPER
    beq32 {pad_x,x}, {pad_home,x}, armed
    jsr smash_or_super
    bcs armed
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
    beq smash
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
    jsr abs_vx_t
    mov32 n_u, n_t
    asr32 n_u
    asr32 n_u
    sub32 n_t, n_t, n_u
    jsr away_from
    event EV_BOOST
    rts
super:
    mov32 ball_boost, {#P_SUPER_MUL}
    jsr abs_vx_t                ; a 45 gradi
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
.assert P_SLOW_BACK >= ONE .and P_SLOW_BACK < 2 * ONE, error, "hit_bonus: P_SLOW_BACK in [ONE, 2 ONE)"

.proc smash_or_super
    ldx n_side
    lda nx_armed,x
    cmp #B_SMASH
    beq yes
    cmp #B_SUPER
    beq yes
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
    bne wall
    clc                         ; nessun muro (quasi sempre)
    rts
wall:
    cpx #0
    bne right
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
    jsr bullet_end
:   lda #0
    sta nx_lslow
    sta nx_lslow+4
    sta nx_atap
    sta nx_atap+4
.endproc
; (prosegue)
; Match::next_morph (OMEGA): dopo un punto dell'avversario la racchetta di nx_morph prende la forma
; dei punti che ha subito (challenge::omega_form: l'avversario della scala di quel livello, poi
; resta il GUARDIAN), torna a casa e prende i bonus di quella forma; riserva, barra e bonus armati
; restano.
.proc next_morph
    ldx nx_morph
    bmi done
    cpx scorer
    beq done
    ldy scorer
    lda score+1,y
    bne last
    lda score,y
    cmp #CH_LEVELS
    bcc :+
last:
    lda #CH_LEVELS - 1
:   tay
    lda rung_kind,y
    sta nx_kind,x
    sty n_t
    tya
    asl a
    adc n_t                     ; livello * 3 (C = 0)
    tay
    lda rung_loadout,y
    sta nx_load,x
    lda rung_loadout+1,y
    sta nx_load+1,x
    lda rung_loadout+2,y
    sta nx_load+2,x
    jsr set_kind
    ; (per lo schermo, nello stesso tick il lampo bianco, om_flash di omega.s; le immagini della
    ; forma nuova le copia dalla cartuccia pad_prep di video.s, da capo per il lato di OMEGA)
    txa
    lsr a
    lsr a
    tay
    lda #0
    sta pp_ready,y
    sta pp_side
    sta pp_var
    lda #OM_FLASH
    sta om_flash
    ldy #4                      ; x = home_x (X avanti di 4: non serve più)
:   lda pad_home,x
    sta pad_x,x
    inx
    dey
    bne :-
done:
    rts
.endproc
