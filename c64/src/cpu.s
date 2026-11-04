; Avversario controllato dal computer: traduzione di `Cpu::input` (rust/core/src/cpu.rs) con il
; comando da joystick, NEXT compreso (capsule, STEER, BLASTER, bonus, mosse speciali in supers.s),
; verificata comando per comando contro il core (paddws-c64 game).
;
; Ogni CPU ha il suo generatore xorshift32 (seme della partita xor $C0FFEE11): durante il suo
; turno lo stato prende il posto di `rng`, poi torna quello della partita.
;
; La previsione del punto d'arrivo (`arrival_y`) nel core avanza la palla di un tick alla volta;
; qui è in forma chiusa: passi fino alla faccia della racchetta (una divisione), spostamento
; verticale (una moltiplicazione) e riflessioni sui bordi (un modulo). Il risultato è lo stesso,
; perché ogni passo del ciclo riflette al più una volta e la riflessione è esatta.
;
; Con passi di un tick la previsione non cambia mentre la palla va dritta: si tiene da parte e
; si rifà solo dopo un evento che tocca la palla (rimbalzo, colpo, punto, bonus attivato, SUPER,
; barriera: non raccolta, sparo e TELEPORT), se cambiano la x della racchetta, la velocità
; orizzontale o il boost della palla, quando la palla ha fatto tutti i passi previsti o se la
; previsione era troncata all'orizzonte massimo.
;
; Con il BULLET la palla fa passi più corti di quelli della previsione e il risultato cambia a ogni
; tick; rifarla costerebbe circa 1.600 cicli per tick. Si aggiorna invece (cpu_step) dall'ultimo
; passo della palla: il resto della divisione dei passi perde il passo orizzontale (sotto zero, un
; passo in meno), la y senza bordi prende il passo verticale (meno vy per il passo in meno), poi i
; bordi. Stessi numeri del calcolo da capo.

CPU_SEED_XOR = $C0FFEE11
.assert P_PREDICT_MAX = P_ARRIVAL_MAX, error, "CPU e TELEPORT prevedono con lo stesso orizzonte"
.assert P_PREDICT_MAX < 256, error, "passi della previsione in un byte"

.segment "RODATA"
cpu_reaction_tab: .byte T_CPU_REACTION
cpu_fast_tab:     .byte T_CPU_FAST
cpu_predict_tab:  .byte T_CPU_PREDICT
cpu_fwd_tab:      .byte T_CPU_FWD_ODDS
cpu_bonus_tab:    .byte T_CPU_BONUS_ODDS
cpu_miss_tab:     .dword T_CPU_MISS
cpu_error_tab:    .dword T_CPU_MAX_ERROR
cpu_react_tab:    .dword T_CPU_REACT
cpu_inv_tab:      .dword T_CPU_INV_SPEED
cpu_invn_tab:     .dword T_CPU_INV_SPEED_NEXT

.segment "ZEROPAGE"
c_side:  .res 1                 ; lato della CPU in esame * 4
c_flags: .res 1                 ; comando in preparazione
c_coming: .res 1
c_strike: .res 1
c_tp:     .res 1                ; arrival_y per il TELEPORT (8): spostamento dell'ultimo tick
c_y:     .res 4                 ; previsione: y, passi, ...
c_n:     .res 1
c_d:     .res 4
c_a:     .res 4
c_k:     .res 1                 ; capsula in esame (0-3) e il suo indice * 4
c_k4:    .res 1
c_full:  .res 1                 ; riserva piena

.segment "CPUBSS"
; stato di ciascuna CPU (indice X = lato * 4)
cpu_rng:      .res 8
cpu_error:    .res 8            ; errore di mira per la palla in arrivo
cpu_max_err:  .res 8
cpu_last:     .res 8            ; ultimo punto scelto
cpu_react:    .res 8
cpu_inv:      .res 8
cpu_was:      .res 8            ; la palla veniva verso di sé al tick prima (byte)
cpu_since:    .res 8            ; tick da quando viene verso di sé (byte, fino a 255)
cpu_reaction: .res 8
cpu_miss:     .res 8
cpu_fast:     .res 8
cpu_predict:  .res 8
cpu_fwd:      .res 8
cpu_away:     .res 8            ; tick da avanzata con la palla che si allontana (byte)
cpu_invn:     .res 8            ; reciproco della velocità massima in NEXT
cpu_bonus:    .res 8            ; NEXT: bonus, una probabilità su N per tick
cpu_saved_rng: .res 4
cpu_speed:    .res 4
; previsione tenuta da parte: y, x della racchetta, vx e boost della palla, tick, passi, valida
cpu_cy:       .res 8
cpu_cx:       .res 8
cpu_cvx:      .res 8
cpu_cb:       .res 8
cpu_ct:       .res 8
cpu_cn:       .res 8
cpu_ok:       .res 8
; BULLET: punto d'arrivo previsto senza l'errore di mira (valido con cb_aim) e distanza della palla
; dalla casa, per Cpu::bullet_rescue
cb_aim:       .res 1
cb_y:         .res 4
cb_dist:      .res 4
.segment "BSS"
; ultima previsione di arrival_y, per lato (indice lato + c_tp: prima la CPU, poi il TELEPORT): y
; senza i bordi, resto della divisione dei passi e passo orizzontale (solo la CPU)
pred_y:       .res 16
pred_rem:     .res 16
pred_dxa:     .res 16

.segment "CODE"

; Cpu::new: CPU al livello A per il lato X (0 o 4), con il seme cfg_seed e la difficoltà cfg_diff.
.proc cpu_init
    stx c_side
    tay                         ; Y = livello
    lda cpu_reaction_tab,y
    sta cpu_reaction,x
    lda cpu_fast_tab,y
    sta cpu_fast,x
    lda cpu_predict_tab,y
    sta cpu_predict,x
    lda cpu_fwd_tab,y
    sta cpu_fwd,x
    lda cpu_bonus_tab,y
    sta cpu_bonus,x
    tya
    asl a
    asl a
    tay
    mov32 {cpu_miss,x}, {cpu_miss_tab,y}
    mov32 {cpu_max_err,x}, {cpu_error_tab,y}
    mov32 {cpu_react,x}, {cpu_react_tab,y}
    lda cfg_diff
    asl a
    asl a
    tay
    mov32 {cpu_inv,x}, {cpu_inv_tab,y}
    mov32 {cpu_invn,x}, {cpu_invn_tab,y}
    ; generatore proprio: seme xor costante (0 diventa il valore di Rng::new)
    lda cfg_seed
    eor #<CPU_SEED_XOR
    sta cpu_rng,x
    lda cfg_seed+1
    eor #>CPU_SEED_XOR
    sta cpu_rng+1,x
    lda cfg_seed+2
    eor #<(CPU_SEED_XOR >> 16)
    sta cpu_rng+2,x
    lda cfg_seed+3
    eor #<(CPU_SEED_XOR >> 24)
    sta cpu_rng+3,x
    or32 {cpu_rng,x}
    bne :+
    mov32 {cpu_rng,x}, {#$2545F491}
:   lda #0
    sta cpu_error,x
    sta cpu_error+1,x
    sta cpu_error+2,x
    sta cpu_error+3,x
    sta cpu_was,x
    sta cpu_since,x
    sta cpu_ok,x
    sta cpu_away,x
    mov32 {cpu_last,x}, {#P_HEIGHT / 2}
    rts
.endproc

; Cpu::input: comandi del tick per il lato X in in_dir, in_flags (prima di match_step).
.proc cpu_input
    stx c_side
    mov32 cpu_saved_rng, rng
    mov32 rng, {cpu_rng,x}
    ; un evento nel tick appena giocato cambia la traiettoria: la previsione va rifatta
    lda events
    and #EV_WALL | EV_HIT | EV_BOOST | EV_SCORE | EV_ACTIVATE | EV_SUPER
    bne invalid
    lda events+1
    and #EV_BARRIER_HI
    bne invalid
    lda nx_btimer               ; BULLET: la palla ha fatto un passo rallentato
    beq :+
    jsr cpu_step
    jmp :+
invalid:
    lda #0
    sta cpu_ok,x
:   lda #0
    sta c_flags
    sta cb_aim
    ; la palla viene verso di sé: a sinistra vx < 0, a destra vx > 0
    sta c_coming
    jsr ball_toward
    rol c_coming
    ldx c_side
    lda c_coming
    jeq not_new
    lda cpu_was,x
    jne not_new
    ; palla nuova in arrivo: tempo di reazione da capo, errore di mira (a volte apposta)
    lda #0
    sta cpu_since,x
    ; velocità rispetto alla massima: mul_recip(|mul(vx, boost)|, inv)
    mulq16 ball_vx, ball_boost
    abs32 m_a, m_a
    ldx c_side
    lda m_next
    beq classic
    mulq24 m_a, {cpu_invn,x}
    jmp speed
classic:
    mulq24 m_a, {cpu_inv,x}
speed:
    mov32 cpu_speed, m_a
    ; miss = (per mille * velocità) >> 16
    ldx c_side
    mov32 m_b, {cpu_miss,x}
    jsr umul32                  ; m_a = velocità, m_b = per mille
    mov32 c_d, {m_p+2}
    ; rng.below(1000) < miss ?
    lda #<1000
    sta m_b
    lda #>1000
    sta m_b+1
    jsr rng_below
    sta c_a
    stx c_a+1
    lda #0
    sta c_a+2
    sta c_a+3
    ldx c_side
    cmp32 c_a, c_d
    jpl aim
    ; mancata apposta: oltre il bordo della racchetta
    mov32 c_y, ball_r
    asl32 c_y
    add32 c_y, c_y, ball_r      ; raggio * 3
    add32 c_y, c_y, {pad_half,x}
    jsr rng_next
    ldx c_side
    lda rng+3
    bpl :+
    neg32 c_y, c_y
:   mov32 {cpu_error,x}, c_y
    jmp not_new
aim:
    ; errore piccolo: mul(mul(max_error, rng.unit()), velocità)
    jsr rng_unit                ; t0
    ldx c_side
    mulq16 {cpu_max_err,x}, t0
    mulq16 m_a, cpu_speed
    ldx c_side
    mov32 {cpu_error,x}, m_a
not_new:
    ldx c_side
    lda sm_on                   ; RISING STRIKE che s'impenna: tempo di reazione da capo
    beq :+
    jsr sm_cpu_rise
:   ; durante l'attesa della battuta si riparte da capo
    lda #0
    sta cpu_was,x
    or32 serve_timer
    bne :+
    lda c_coming
    sta cpu_was,x
:   ; tick da quando la palla viene verso di sé (si ferma a 255)
    lda cpu_since,x
    cmp #$ff
    beq :+
    inc cpu_since,x
:   ; dove andare: la palla in arrivo, altrimenti una capsula NEXT verso di sé, altrimenti il centro
    mov32 c_y, {#P_HEIGHT / 2}
    lda c_coming
    jeq capsule
    or32 serve_timer
    jne capsule
    lda cpu_reaction,x
    cmp cpu_since,x
    bcc reacting                ; since > reaction
    ; non si è ancora accorta della palla: resta dov'era
    mov32 c_y, {cpu_last,x}
    jmp target_done
reacting:
    ; |x - casa| < distanza di reazione
    sub32 c_d, ball_x, {pad_home,x}
    abs32 c_d, c_d
    cmp32 c_d, {cpu_react,x}
    jpl capsule
    ; come una persona: la palla fantasma nascosta non si vede, si resta dov'era
    lda m_next
    beq visible
    lda nx_ghost
    beq visible
    lda ghost_phase
    cmp #P_GHOST_VISIBLE
    bcc visible
    mov32 c_y, {cpu_last,x}
    jmp target_done
visible:
    mov32 cb_dist, c_d          ; per il BULLET: palla in arrivo e vista
    lda #1
    sta cb_aim
    lda cpu_predict,x
    beq follow
    ; la curva, la palla fantasma e quella guidata non si possono prevedere
    lda m_next
    beq predict
    or32 nx_curve
    ora nx_ghost
    ora nx_steer
    bne follow
predict:
    lda #0
    sta c_tp
    jsr cached_arrival          ; c_y
    ldx c_side
    jmp add_error
follow:
    mov32 c_y, ball_y
add_error:
    mov32 cb_y, c_y
    add32 c_y, c_y, {cpu_error,x}
    jmp target_done
capsule:
    ; NEXT: la prima capsula che vuole
    lda m_next
    beq target_done
    jsr cpu_capsule
    bcc target_done
    ldy c_k4
    mov32 c_y, {cap_y,y}
target_done:
    ldx c_side
    mov32 {cpu_last,x}, c_y
    ; STEER: la racchetta è ferma, su e giù guidano la palla lontano dalla racchetta avversaria
    lda m_next
    beq joystick
    lda nx_steer
    beq joystick
    lda nx_steer_s
    cmp c_side
    bne joystick
    txa
    eor #4
    tay                         ; Y = avversario
    lda #1
    sta in_dir,x
    cmp32 ball_y, {pad_y,y}
    jpl blaster                 ; palla sopra (o alla pari): su
    lda #$ff
    sta in_dir,x
    jmp blaster
joystick:
    ; joystick: su o giù oltre una zona morta di 1/8 di racchetta, rapido per i recuperi lunghi
    sub32 c_d, c_y, {pad_y,x}
    mov32 c_a, {pad_h,x}
    asr32 c_a
    asr32 c_a
    asr32 c_a
    lda #0
    sta in_dir,x
    cmp32 c_a, c_d
    bpl :+
    lda #1
    sta in_dir,x
    jmp fast
:   neg32 c_a, c_a
    cmp32 c_d, c_a
    bpl fast
    lda #$ff
    sta in_dir,x
fast:
    lda cpu_fast,x
    beq blaster
    abs32 c_d, c_d
    cmp32 {pad_h,x}, c_d
    bpl blaster
    lda #IN_FAST
    sta c_flags
blaster:
    ; BLASTER: spara (con il tasto dello scatto) quando una capsula che vuole è davanti alla
    ; racchetta; niente scatto
    ldx c_side
    lda m_next
    beq forward
    lda nx_kind,x
    cmp #K_BLASTER
    bne forward
    jsr cpu_fire
    jmp bonus
forward:
    ; scatto in avanti (EVO e NEXT): solo se intercetta davvero la palla
    lda m_evo
    ora m_next
    jeq done
    jsr cpu_strike              ; C = 1 se scatta
    ldx c_side
    lda #0
    rol a
    sta c_strike
    ; avanzata con la palla che si allontana: resta lì P_CPU_RETURN tick, poi torna a casa
    lda c_coming
    bne home_reset
    beq32 {pad_x,x}, {pad_home,x}, home_reset
    lda cpu_away,x
    cmp #$ff
    beq :+
    inc cpu_away,x
:   lda cpu_away,x
    cmp #P_CPU_RETURN + 1
    bcs press
    jmp strike_only
home_reset:
    lda #0
    sta cpu_away,x
strike_only:
    lda c_strike
    beq bonus
press:
    lda c_flags
    ora #IN_FORWARD
    sta c_flags
bonus:
    ; NEXT: attiva il bonus selezionato mentre la palla arriva; ogni tanto ne sceglie un altro.
    ; Il BULLET si usa come gli altri; in più, in emergenza (bullet_rescue), ci si va e lo si
    ; attiva con probabilità per tick 16 volte più alta. Con un BULLET già armato o in corso (di
    ; chiunque) quello selezionato non parte: si passa al successivo
    lda m_next
    jeq done
    ldx c_side
    jsr res_count
    sta c_n
    jeq done
    ; pronto (c_k): niente di armato, pausa finita, palla in arrivo, non durante la battuta
    lda #0
    sta c_k
    lda nx_armed,x
    cmp #B_NONE
    bne :+
    lda nx_cool,x
    ora nx_cool+1,x
    bne :+
    lda c_coming
    beq :+
    or32 serve_timer
    bne :+
    inc c_k
:   ; selezionato (c_k4): riserva[min(sel, n - 1)]
    lda nx_sel,x
    cmp c_n
    bcc :+
    lda c_n
    sbc #1
:   clc
    adc c_side
    tay
    lda nx_res,y
    sta c_k4
    ; emergenza: pronto, un BULLET in riserva, nessuno armato o in corso, bullet_rescue
    lda c_k
    beq not_rescue
    lda nx_bside
    bpl not_rescue
    lda #B_BULLET
    cmp nx_res,x
    beq :+
    cmp nx_res+1,x
    beq :+
    cmp nx_res+2,x
    bne not_rescue
:   jsr bullet_rescue
    bcc not_rescue
    lda c_k4
    cmp #B_BULLET
    bne press_select
    ; sul BULLET: lo attiva con probabilità 1 / max(bonus_odds >> 4, 1)
    lda cpu_bonus,x
    lsr a
    lsr a
    lsr a
    lsr a
    bne :+
    lda #1
:   jsr below_zero
    bcc done
    lda c_flags
    ora #IN_ACTIVATE
    sta c_flags
    jmp done
not_rescue:
    ; il BULLET selezionato con un BULLET già armato o in corso: al successivo, se c'è
    lda c_k4
    cmp #B_BULLET
    bne normal
    lda nx_bside                ; (bit 7: nessun BULLET) come gli altri bonus
    bmi normal
    lda c_n
    cmp #2
    bcc done
press_select:
    lda c_flags
    ora #IN_SELECT
    sta c_flags
    jmp done
normal:
    lda c_k
    beq select
    lda cpu_bonus,x
    jsr below_zero
    bcc select
    lda c_flags
    ora #IN_ACTIVATE
    sta c_flags
select:
    lda c_n
    cmp #2
    bcc done
    ldx c_side
    lda cpu_bonus,x
    asl a                       ; bonus_odds * 2 (al massimo 200)
    jsr below_zero
    bcc done
    lda c_flags
    ora #IN_SELECT
    sta c_flags
done:
    ldx c_side
    lda sm_on                   ; mosse speciali, se non attiva un bonus (sm_cpu)
    beq :+
    jsr sm_cpu
:   lda c_flags
    sta in_flags,x
    mov32 {cpu_rng,x}, rng
    mov32 rng, cpu_saved_rng
    rts
.endproc

; Cpu::bullet_rescue per la CPU c_side (X): C = 1 se la palla, in arrivo e vista (cb_aim), è
; veloce (|dx| oltre metà della velocità massima), vicina (cb_dist <= |dx| << P_CPU_BULLET_SHIFT),
; arriva fuori dalla racchetta (oltre mezza racchetta più il raggio) e la CPU non ha deciso di
; mancarla (errore di mira entro mezza racchetta). Non usa il generatore.
.proc bullet_rescue
    lda cb_aim
    bne go
no:
    clc
    rts
go:
    mov32 c_d, ball_dx
    jsr abs_cd                  ; |dx|
    mov32 c_a, max_ball         ; positiva: / 2 senza segno
    lsr c_a+3
    ror c_a+2
    ror c_a+1
    ror c_a
    cmp32 c_a, c_d              ; |dx| <= massima / 2: no
    bpl no
    ldy #P_CPU_BULLET_SHIFT
:   asl c_d
    rol c_d+1
    rol c_d+2
    rol c_d+3
    dey
    bne :-
    cmp32 c_d, cb_dist          ; |dx| << shift < distanza: no
    bmi no
    sub32 c_d, cb_y, {pad_y,x}
    jsr abs_cd
    add32 c_a, {pad_half,x}, ball_r
    cmp32 c_a, c_d              ; mezza racchetta + raggio >= scarto: no
    jpl no
    mov32 c_d, {cpu_error,x}
    jsr abs_cd
    cmp32 {pad_half,x}, c_d     ; mezza racchetta < |errore|: no
    jmi no
    sec
    rts
.endproc

; c_d = |c_d|
.proc abs_cd
    lda c_d+3
    bpl done
    neg32 c_d, c_d
done:
    rts
.endproc

; C = 1 se rng.below(A) == 0 (A < 256: il risultato sta in A). Distrugge X.
.proc below_zero
    sta m_b
    lda #0
    sta m_b+1
    jsr rng_below
    cmp #1                      ; C = 0 se A = 0
    rol a                       ; ...e il carry nel bit 0 di A
    eor #1
    lsr a                       ; C = 1 se il risultato era 0
    rts
.endproc

; Cpu::wants: C = 1 se la CPU c_side vuole la capsula c_k (che c'è): quelle verso di sé finché la
; riserva non è piena; il BLASTER, che le raccoglie sparando, anche quelle dell'avversario (con la
; riserva piena solo quelle, per distruggerle).
.proc cpu_wants
    ldx c_side
    jsr res_count
    ldy #0
    cmp #3
    bne :+
    iny
:   sty c_full
    ; verso chi va: vx < 0 a sinistra (0), altrimenti a destra (4)
    ldy c_k4
    lda #0
    ldx cap_vx+3,y
    bmi :+
    lda #4
:   ldx c_side
    cmp c_side
    beq mine
    ; dell'avversario: solo il BLASTER
    lda nx_kind,x
    cmp #K_BLASTER
    bne no
    sec
    rts
mine:
    ; verso di sé: se la riserva non è piena
    lda c_full
    bne no
    sec
    rts
no:
    clc
    rts
.endproc

; C = 1 se c'è una capsula che la CPU c_side vuole: la prima in c_k (indice * 4 in c_k4).
.proc cpu_capsule
    lda #0
    sta c_k
loop:
    ldy c_k
    lda cap_on,y
    beq next
    tya
    asl a
    asl a
    sta c_k4
    jsr cpu_wants
    bcs found
next:
    inc c_k
    lda c_k
    cmp #4
    bne loop
    clc
found:
    rts
.endproc

; BLASTER della CPU c_side: spara (IN_FORWARD) se può, se non ha colpi in volo, se una capsula
; che vuole è davanti alla racchetta (entro mezzo lato di capsula) e il generatore lo concede.
.proc cpu_fire
    ldx c_side
    ; pl.can_fire(): colpi nel caricatore, pausa finita (un posto libero c'è: sono tutti liberi)
    lda nx_ammo,x
    jeq no
    lda nx_gap,x
    ora nx_gap+1,x
    jne no
    ; un colpo alla volta: nessun colpo del giocatore in volo (posti X - X + 3)
    lda shot_on,x
    ora shot_on+1,x
    ora shot_on+2,x
    ora shot_on+3,x
    jne no
.assert MAX_SHOTS = 4, error, "cpu_fire: quattro posti per giocatore"
    ; una capsula allineata che vuole
    lda #0
    sta c_k
loop:
    ldy c_k
    lda cap_on,y
    jeq next
    tya
    asl a
    asl a
    sta c_k4
    tay
    ldx c_side
    ; davanti: a sinistra c.x > destra della racchetta, a destra c.x < sinistra
    cpx #0
    bne right
    add32 c_a, {pad_x,x}, {#P_PAD_HALF_W}
    blt32 c_a, {cap_x,y}, height
    jmp next
right:
    sub32 c_a, {pad_x,x}, {#P_PAD_HALF_W}
    blt32 {cap_x,y}, c_a, height
    jmp next
height:
    ; |c.y - pad.y| <= mezzo lato della capsula
    sub32 c_a, {cap_y,y}, {pad_y,x}
    abs32 c_a, c_a
    blt32 {#P_CAP_HALF}, c_a, next
    jsr cpu_wants
    bcs aligned
next:
    inc c_k
    lda c_k
    cmp #4
    jne loop
no:
    rts
aligned:
    ; una probabilità su N (quella dello scatto, 60 se il livello non scatta)
    ldx c_side
    lda cpu_fwd,x
    bne :+
    lda #60
:   jsr below_zero
    bcc no
    lda c_flags
    ora #IN_FORWARD
    sta c_flags
    rts
.endproc

; C = 1 se la CPU X scatta adesso: a casa, palla in arrivo nell'area dello scatto e all'altezza
; della racchetta, e il generatore lo concede (una probabilità su N).
.proc cpu_strike
    beq32 {pad_x,x}, {pad_home,x}, home
    clc
    rts
home:
    lda c_coming
    jeq no
    ; all'altezza della racchetta
    sub32 c_d, ball_y, ball_r
    add32 c_a, {pad_y,x}, {pad_half,x}
    cmp32 c_a, c_d
    jmi no
    add32 c_d, ball_y, ball_r
    sub32 c_a, {pad_y,x}, {pad_half,x}
    cmp32 c_d, c_a
    jmi no
    cpx #0
    jne right
    ; sinistra: casa + w/2 <= palla.sinistra <= avanzata + w/2
    sub32 c_d, ball_x, ball_r
    add32 c_a, {pad_home,x}, {#HALF_W_FLOOR}
    cmp32 c_d, c_a
    jmi no
    add32 c_a, {pad_fwd,x}, {#HALF_W_FLOOR}
    cmp32 c_a, c_d
    jmi no
    jmp odds
right:
    add32 c_d, ball_x, ball_r
    sub32 c_a, {pad_fwd,x}, {#HALF_W_FLOOR}
    cmp32 c_d, c_a
    bmi no
    sub32 c_a, {pad_home,x}, {#HALF_W_FLOOR}
    cmp32 c_a, c_d
    bmi no
odds:
    lda cpu_fwd,x
    beq no
    sta m_b
    lda #0
    sta m_b+1
    jsr rng_below               ; n < 256: il risultato sta in A
    cmp #0
    bne no
    sec
    rts
no:
    clc
    rts
.endproc

; BULLET: la previsione tenuta da parte della CPU X, fatta al tick prima e con ancora dei passi,
; segue l'ultimo passo (rallentato) della palla; altrimenti (fermo del SUPER, previsione più
; vecchia) va rifatta.
.proc cpu_step
    lda cpu_ok,x
    beq done
    lda nx_bmoved
    beq invalid
    lda tick                    ; un tick solo (la previsione vale meno di 256 tick)
    sec
    sbc cpu_ct,x
    cmp #1
    bne invalid
    lda cpu_cn,x
    bne go
invalid:
    lda #0
    sta cpu_ok,x
done:
    rts
go:
    sta c_n
    ; resto - |passo|: sotto zero un passo in meno (e il resto torna tra 0 e |dx|)
    mov32 c_d, ball_dx
    jsr abs_cd
    sub32 {pred_rem,x}, {pred_rem,x}, c_d
    clc
    lda pred_rem+3,x
    bpl keep
    add32 {pred_rem,x}, {pred_rem,x}, {pred_dxa,x}
    dec c_n
    sec
keep:
    lda c_n
    sta cpu_cn,x
    txa
    tay
    jsr pred_advance            ; C = 1: un passo in meno
    mov32 {cpu_ct,x}, tick
    mov32 {cpu_cy,x}, c_y
    rts
.endproc

; Previsione Y (indice di pred_y) avanzata dell'ultimo passo della palla: y senza bordi + ball_dy,
; meno vy con C = 1 (un passo in meno), poi i bordi in c_y. X = c_side alla fine.
.proc pred_advance
    php
    add32 c_y, {pred_y,y}, ball_dy
    plp
    bcc :+
    sub32 c_y, c_y, ball_vy
:   mov32 {pred_y,y}, c_y
    jmp fold_y
.endproc

; Previsione per la CPU X in c_y: quella tenuta da parte se vale ancora, altrimenti arrival_y.
.proc cached_arrival
    lda cpu_ok,x
    jeq compute
    beq32 {cpu_cx,x}, {pad_x,x}, :+
    jmp compute
:   beq32 {cpu_cvx,x}, ball_vx, :+
    jmp compute
:   beq32 {cpu_cb,x}, ball_boost, same
    jmp compute
same:
    ; tick passati dalla previsione, non più dei passi previsti
    sub32 c_d, tick, {cpu_ct,x}
    lda c_d+3
    ora c_d+2
    ora c_d+1
    bne compute
    lda cpu_cn,x
    cmp c_d
    bcc compute
    mov32 c_y, {cpu_cy,x}
    rts
compute:
    jsr arrival_y
    mov32 {cpu_cy,x}, c_y
    mov32 {cpu_cx,x}, {pad_x,x}
    mov32 {cpu_cvx,x}, ball_vx
    mov32 {cpu_cb,x}, ball_boost
    mov32 {cpu_ct,x}, tick
    lda c_n
    sta cpu_cn,x
    ; troncata all'orizzonte: cambia a ogni tick, non si tiene
    lda #1
    ldy c_n
    cpy #P_PREDICT_MAX
    bcc :+
    lda #0
:   sta cpu_ok,x
    rts
.endproc

; arrival_y di cpu.rs: y della palla quando arriverà alla faccia della racchetta X, in c_y.
.proc arrival_y
    ; faccia: x della palla al contatto
    cpx #0
    bne right
    add32 c_a, {pad_x,x}, {#P_PAD_HALF_W}
    add32 c_a, c_a, ball_r
    sub32 c_d, ball_x, c_a      ; distanza da percorrere (verso sinistra)
    jmp dx
right:
    sub32 c_a, {pad_x,x}, {#P_PAD_HALF_W}
    sub32 c_a, c_a, ball_r
    sub32 c_d, c_a, ball_x
dx:
    ; spostamento per tick: quello dell'ultimo tick per il TELEPORT (next.rs), mul(vx, boost)
    ; per la CPU (cpu.rs); stesso orizzonte (P_PREDICT_MAX = P_ARRIVAL_MAX)
    lda c_tp
    beq :+
    mov32 c_a, ball_dx
    jmp steps
:   beq32 ball_boost, {#ONE}, unit
    mulq16 ball_vx, ball_boost
    mov32 c_a, m_a
    jmp steps
unit:
    mov32 c_a, ball_vx
steps:
    ldx c_side
    lda #0
    sta c_n
    ; già arrivata (distanza <= 0) o palla ferma: nessun passo
    lda c_d+3
    jmi fold
    or32 c_d
    jeq fold
    or32 c_a
    jeq fold
    ; verso giusto? a sinistra dx < 0, a destra dx > 0; altrimenti non arriva mai
    lda c_a+3
    cpx #0
    bne :+
    eor #$80
:   and #$80
    jne away
    abs32 c_a, c_a
    ; passi = ceil(d / |dx|) = (d - 1) / |dx| + 1. Oltre l'orizzonte (passi > P_PREDICT_MAX, cioè
    ; d > |dx| * P_PREDICT_MAX) si mira all'ultimo punto: si vede dal quoziente, senza moltiplicare.
    ; Con d - 1 >= |dx| << 8 il quoziente non sta in 8 bit: di sicuro oltre.
    sub32 c_d, c_d, {#1}
    lda #0                      ; m_a = |dx| << 8 (|dx| < 2^24)
    sta m_a
    lda c_a
    sta m_a+1
    lda c_a+1
    sta m_a+2
    lda c_a+2
    sta m_a+3
    cmp32 c_d, m_a
    jpl away
    lsr m_a+3                   ; |dx| << 7
    ror m_a+2
    ror m_a+1
    ror m_a
    ldy #8
div:
    asl c_n
    cmp32 c_d, m_a
    bmi :+
    sub32 c_d, c_d, m_a
    inc c_n
:   lsr m_a+3
    ror m_a+2
    ror m_a+1
    ror m_a
    dey
    bne div
    ; resto e passo per gli aggiornamenti del BULLET (cpu_step)
    lda c_tp
    ora c_side
    tay
    mov32 {pred_rem,y}, c_d
    mov32 {pred_dxa,y}, c_a
    lda c_n                     ; passi - 1
    cmp #P_PREDICT_MAX
    bcs away
    inc c_n
    jmp fold
away:
    lda #P_PREDICT_MAX
    sta c_n
fold:
    ; y dopo n passi senza bordi: y + n * vy
    abs32 m_a, ball_vy
    lda c_n
    sta m_b
    lda #0
    sta m_b+1
    sta m_b+2
    sta m_b+3
    jsr umul32
    lda ball_vy+3
    bpl :+
    neg32 m_p, m_p
:   add32 c_y, ball_y, m_p
    lda c_tp                    ; senza bordi, per gli aggiornamenti del BULLET
    ora c_side
    tay
    mov32 {pred_y,y}, c_y
    ; (prosegue in fold_y)
.endproc

; Riflessioni di c_y sui bordi basso (r + 1) e alto (H - 1 - r): onda triangolare di periodo
; 2 (alto - basso). X = c_side alla fine.
.proc fold_y
    add32 c_a, ball_r, {#ONE}              ; basso
    sub32 c_d, {#P_HEIGHT - ONE}, ball_r   ; alto
    sub32 c_d, c_d, c_a                    ; ampiezza
    sub32 c_y, c_y, c_a                    ; u = y - basso
    mov32 m_a, c_d
    asl32 m_a                              ; periodo
:   lda c_y+3
    bpl :+
    add32 c_y, c_y, m_a
    jmp :-
:   cmp32 c_y, m_a
    bmi :+
    sub32 c_y, c_y, m_a
    jmp :-
:   ; u <= ampiezza: basso + u; altrimenti basso + periodo - u
    cmp32 c_d, c_y
    bpl :+
    sub32 c_y, m_a, c_y
:   add32 c_y, c_y, c_a
    ldx c_side
    rts
.endproc
