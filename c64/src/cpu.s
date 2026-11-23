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
; tick; rifarla costerebbe circa 1.300 cicli per tick. Si aggiorna invece (cpu_step) dall'ultimo
; passo della palla: il resto della divisione dei passi perde il passo orizzontale (sotto zero, un
; passo in meno), la y senza bordi prende il passo verticale (meno vy per il passo in meno), poi i
; bordi. Stessi numeri del calcolo da capo.
;
; L'errore di mira di una palla nuova (due prodotti) non serve finché la CPU non reagisce: nel
; tick della palla nuova si fa solo l'estrazione, i prodotti al tick dopo (aim_error).

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
cpu_pend = cpu_was + 1          ; errore di mira da fare (aim_error), nel byte dopo cpu_was
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
.segment "NEXTBSS"
; velocità e soglia della mancata apposta dell'ultima palla nuova (cpu_input): CPU, vx e boost
; della palla, velocità, soglia
cs_side:      .res 1
cs_key:       .res 8
cs_speed:     .res 4
cs_miss:      .res 4
.segment "BSS"
; ultima previsione di arrival_y, per lato (indice lato + c_tp: prima la CPU, poi il TELEPORT): y
; senza i bordi; resto della divisione dei passi e passo orizzontale solo per la CPU (cpu_step)
pred_y:       .res 16
pred_rem:     .res 8
pred_dxa:     .res 8

.segment "CODE"

; Cpu::new: CPU al livello A per il lato X (0 o 4), con il seme cfg_seed e la difficoltà cfg_diff.
.proc cpu_init
    stx c_side
    ldy #$ff                    ; velocità e soglia tenute da parte: da rifare (livello nuovo)
    sty cs_side
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
    sta cpu_pend,x
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
    ; la palla viene verso di sé: a sinistra vx < 0, a destra vx > 0 (ball_toward: in C, X resta)
    jsr ball_toward
    lda #0
    rol a
    sta c_coming
    jeq not_new
    lda cpu_was,x
    jne not_new
    ; palla nuova in arrivo: tempo di reazione da capo, errore di mira (a volte apposta)
    lda #0
    sta cpu_since,x
    ; velocità e soglia della mancata apposta dipendono solo dalla palla (vx e boost) e dalla CPU:
    ; nell'attesa della battuta si rifanno a ogni tick con gli stessi valori, e si tengono da parte
    ; (cs_*; le estrazioni dopo si fanno sempre, come nel core)
    cpx cs_side
    bne fresh
    ldy #3
:   lda ball_vx,y               ; vx e boost
    cmp cs_key,y
    bne fresh
    lda ball_boost,y
    cmp cs_key+4,y
    bne fresh
    dey
    bpl :-
    jmp cached
fresh:
    ; velocità rispetto alla massima: mul_recip(|mul(vx, boost)|, inv)
    jsr vx_boost
    abs32 m_a, m_a
    ldx c_side
    lda m_next
    beq classic
    mov32 m_b, {cpu_invn,x}
    jmp speed
classic:
    mov32 m_b, {cpu_inv,x}
speed:
    jsr mul_q24
    mov32 cs_speed, m_a
    ; miss = (per mille * velocità) >> 16
    ldx c_side
    stx cs_side
    mov32 m_b, {cpu_miss,x}
    jsr umul32                  ; m_a = velocità, m_b = per mille
    mov32 cs_miss, {m_p+2}
    ldy #3
:   lda ball_vx,y
    sta cs_key,y
    lda ball_boost,y
    sta cs_key+4,y
    dey
    bpl :-
cached:
    ; rng.below(1000) < miss ? Il risultato (fino a 999) sta in 16 bit: si confronta con la soglia
    ; con segno dal byte alto
    lda #<1000
    sta m_b
    lda #>1000
    sta m_b+1
    jsr rng_below               ; A basso, X alto
    ldy cs_miss+3
    bmi aim                     ; soglia negativa: mai sotto
    bne miss                    ; oltre 65535: sempre sotto
    ldy cs_miss+2
    bne miss
    cpx cs_miss+1
    bcc miss
    bne aim
    cmp cs_miss
    bcc miss
aim:
    ; errore piccolo: mul(mul(max_error, rng.unit()), velocità). Durante l'attesa della battuta
    ; l'errore non si usa (solo con la palla in gioco: qui sotto, bullet_rescue, sm_cpu) e al primo
    ; tick dopo la battuta, o alla prima palla in arrivo dopo, si rifà (cpu_was resta a 0): basta
    ; l'estrazione. Fuori dall'attesa i prodotti si rimandano (aim_error): qui si tiene unit()
    or32 serve_timer
    beq :+
    jsr rng_next
    jmp not_new
:   jsr rng_unit                ; t0
    ldx c_side
    mov32 {cpu_error,x}, t0
    lda #1
    sta cpu_pend,x
    jmp not_new
miss:
    ; mancata apposta: oltre il bordo della racchetta
    ldx c_side
    lda #0
    sta cpu_pend,x
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
not_new:
    ldx c_side
    lda sm_on                   ; RISING STRIKE che s'impenna: tempo di reazione da capo
    beq :+
    jsr sm_cpu_rise
:   ; tick da quando la palla viene verso di sé (si ferma a 255)
    inc cpu_since,x
    bne :+
    dec cpu_since,x
:   ; durante l'attesa della battuta si riparte da capo. Dove andare: la palla in arrivo (e non
    ; durante la battuta), altrimenti una capsula NEXT verso di sé, altrimenti il centro
    lda #0
    sta cpu_was,x
    or32 serve_timer
    jne capsule
    lda c_coming
    sta cpu_was,x
    jeq capsule
    lda cpu_reaction,x
    cmp cpu_since,x
    bcc reacting                ; since > reaction
    ; non si è ancora accorta della palla: resta dov'era. Dal tick dopo la palla nuova (since >= 2:
    ; il tempo di reazione è di almeno 10 tick) si fa l'errore di mira rimandato
    lda cpu_pend,x
    beq :+
    lda cpu_since,x
    cmp #2
    bcc :+
    jsr aim_error
:   mov32 c_y, {cpu_last,x}
    jmp target_done
reacting:
    ; |x - casa| < distanza di reazione, in cb_dist per il BULLET. La differenza di due x del campo
    ; non trabocca: confronto senza segno di valori positivi, dal byte alto
    sub32 cb_dist, ball_x, {pad_home,x}
    lda cb_dist+3
    bpl :+
    neg32 cb_dist, cb_dist
:   lda cb_dist+3
    cmp cpu_react+3,x
    bcc near
    jne capsule
    lda cb_dist+2
    cmp cpu_react+2,x
    bcc near
    jne capsule
    lda cb_dist+1
    cmp cpu_react+1,x
    bcc near
    jne capsule
    lda cb_dist
    cmp cpu_react,x
    jcs capsule
near:
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
    lda cpu_pend,x              ; l'errore di mira serve da qui
    beq :+
    jsr aim_error
:   lda #1                      ; per il BULLET e le mosse: palla in arrivo e vista
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
    clc                         ; cb_y = punto previsto, c_y = punto + errore
    .repeat 4, k
    lda c_y+k
    sta cb_y+k
    adc cpu_error+k,x
    sta c_y+k
    .endrepeat
    jmp target_done
capsule:
    ; NEXT: la prima capsula che vuole; altrimenti il centro
    mov32 c_y, {#P_HEIGHT / 2}
    lda m_next
    beq target_done
    jsr cpu_capsule
    bcs found
    ; Cpu::hunts: il BLASTER, con la palla che va verso l'avversario, colpi nel caricatore e
    ; l'avversario non già rallentato dal laser, si mette alla sua altezza per sparargli (il
    ; caricatore ha colpi solo per il BLASTER: set_kind)
    ldx c_side
    lda nx_ammo,x
    beq target_done
    jsr cpu_opp
    bne target_done
    ldx #0
:   lda pad_y,y                 ; c_y = y della racchetta avversaria
    sta c_y,x
    iny
    inx
    cpx #4
    bne :-
    beq target_done             ; sempre
found:
    ldy c_k4
    mov32 c_y, {cap_y,y}
target_done:
    ldx c_side
    ; STEER: la racchetta è ferma, su e giù guidano la palla lontano dalla racchetta avversaria
    lda m_next
    beq joystick
    lda nx_steer
    beq joystick
    lda nx_steer_s
    cmp c_side
    bne joystick
    mov32 {cpu_last,x}, c_y
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
    ; joystick: su o giù oltre una zona morta di 1/8 di racchetta, rapido per i recuperi lunghi.
    ; Ultimo punto scelto e d = punto - y della racchetta
    sec
    .repeat 4, k
    lda c_y+k
    sta cpu_last+k,x
    sbc pad_y+k,x
    sta c_d+k
    .endrepeat
    ; d è la differenza di due y vicine al campo (|d| ben sotto 2^31): |d| non trabocca e i
    ; confronti con segno diventano confronti senza segno di valori positivi, dal byte alto. Su se
    ; d > h / 8, giù se d < -h / 8: |d| > h / 8 con la direzione dal segno
    ldy #1
    lda c_d+3
    bpl :+
    neg32 c_d, c_d
    ldy #$ff
:   tya
    sta in_dir,x
    ; h / 8 (h = altezza, positiva) byte per byte con le tabelle degli shift:
    ; (h[k] >> 3) | (h[k+1] << 5)
    ldy pad_h+3,x
    lda shr3,y
    cmp c_d+3
    bcc out
    bne inside
    ldy pad_h+2,x
    lda shr3,y
    ldy pad_h+3,x
    ora shl5,y
    cmp c_d+2
    bcc out
    bne inside
    ldy pad_h+1,x
    lda shr3,y
    ldy pad_h+2,x
    ora shl5,y
    cmp c_d+1
    bcc out
    bne inside
    ldy pad_h,x
    lda shr3,y
    ldy pad_h+1,x
    ora shl5,y
    cmp c_d
    bcc out
inside:
    ; nella zona morta: ferma, e niente rapido (|d| <= h / 8 <= h)
    lda #0
    sta in_dir,x
    beq blaster                 ; sempre
out:
    ; rapido: |d| > h
    lda cpu_fast,x
    beq blaster
    lda pad_h+3,x
    cmp c_d+3
    bcc rapid
    bne blaster
    lda pad_h+2,x
    cmp c_d+2
    bcc rapid
    bne blaster
    lda pad_h+1,x
    cmp c_d+1
    bcc rapid
    bne blaster
    lda pad_h,x
    cmp c_d
    bcs blaster
rapid:
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
    jeq arcade
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
arcade:
    ; ARCADE a riserva vuota: doppio clic su USE, che chiama subito una capsula verso di sé
    ; (Cpu::input). Il primo clic con la probabilità dei bonus, il secondo passato un quarto della
    ; finestra; pausa, bonus armato, battuta e capsula già in arrivo li controlla next.s
    ; (done sta appena sopra: salti corti all'indietro)
    lda nx_kind,x
    bne done                    ; K_ARCADE = 0
    lda nx_atap,x
    beq first_tap
    cmp #P_ARCADE_TAP - P_ARCADE_TAP / 4 + 1
    bcs done                    ; troppo presto per il secondo clic
    bcc press_activate
first_tap:
    lda cpu_bonus,x
    jsr below_zero
    bcc done
press_activate:
    lda c_flags
    ora #IN_ACTIVATE
    sta c_flags
    bne done                    ; (sempre: IN_ACTIVATE non è zero)
.assert K_ARCADE = 0 .and IN_ACTIVATE <> 0, error, "cpu: ARCADE e IN_ACTIVATE"
.endproc

; Errore di mira della palla nuova, rimandato da cpu_input (cpu_pend): mul(mul(max_error, unit),
; velocità), con unit() in cpu_error e la velocità ancora in cs_speed (cs_* cambia solo con una
; palla nuova, e una palla nuova dell'altro lato vuol dire che questa non arriva più: alla
; prossima in arrivo l'errore si rifà). Per la CPU X = c_side, che resta.
.proc aim_error
    lda #0
    sta cpu_pend,x
    mulq16 {cpu_max_err,x}, {cpu_error,x}
    mov32 m_b, cs_speed
    jsr mul_q16
    ldx c_side
    mov32 {cpu_error,x}, m_a
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

; C = 1 se rng.below(A) == 0 (A < 256). Distrugge X e Y.
; Il risultato è zero se (x >> 16) * A < 65536. Con x3 * A = h1:l1 e x2 * A = h0:l0 il prodotto è
; h1 * 65536 + (l1 + h0) * 256 + l0: serve h1 = 0 e l1 + h0 < 256. Quasi sempre h1 non è zero e
; basta un prodotto 8x8.
.proc below_zero
    pha
    jsr rng_next
    pla
    tay                         ; Y = n
    lda rng+3
    jsr umul8                   ; A = l1, m_t = h1
    ldx m_t
    bne no
    tax
    lda rng+2
    jsr umul8                   ; m_t = h0 (Y resta)
    txa
    eor #$ff                    ; 255 - l1 >= h0: C = 1
    cmp m_t
    rts
no:
    clc
    rts
.endproc

; Y = l'avversario della CPU X; Z = 1 se la palla va verso di lui e il laser del BLASTER non lo ha
; già rallentato (il bersaglio del BLASTER, in cpu_fire e nella scelta di dove andare).
.proc cpu_opp
    txa
    eor #4
    tay
    lda c_coming
    bne :+
    lda nx_lslow,y
:   rts
.endproc

; A = |A - y della racchetta X| in pixel interi (le y stanno in un byte). Y resta.
.proc dy_pad
    sec
    sbc pad_y+2,x
    bcs :+
    eor #$ff                    ; C = 0: il complemento a due
    adc #1
:   rts
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
    lda cap_on                  ; nessuna in campo (4 posti): C = 0
    ora cap_on+1
    ora cap_on+2
    ora cap_on+3
    cmp #1
    bcc found
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
; che vuole è davanti alla racchetta (entro mezzo lato di capsula) o la racchetta avversaria è
; nella fascia del laser mentre la palla va verso di lei, e il generatore lo concede.
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
.assert P_CAP_HALF >> 16 < 255 .and P_BLASTER_BAND >> 16 < 128, error, "cpu_fire: distanze in un byte"
    ; una capsula allineata che vuole, se ce n'è una in campo. Davanti: a sinistra c.x > destra
    ; della racchetta, a destra c.x < sinistra; il bordo in c_a, una volta sola (cpu_wants e dy_pad
    ; non lo toccano)
    lda cap_on
    ora cap_on+1
    ora cap_on+2
    ora cap_on+3
    jeq opp
    cpx #0
    bne :+
    add32 c_a, {pad_x,x}, {#P_PAD_HALF_W}
    jmp :++
:   sub32 c_a, {pad_x,x}, {#P_PAD_HALF_W}
:   lda #0
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
    cpx #0                      ; X = c_side (anche dopo cpu_wants e dy_pad)
    bne right
    blt32 c_a, {cap_x,y}, height
    jmp next
right:
    blt32 {cap_x,y}, c_a, height
    jmp next
height:
    ; |c.y - pad.y| <= mezzo lato della capsula, a pixel interi
    lda cap_y+2,y
    jsr dy_pad
    cmp #<(P_CAP_HALF >> 16) + 1
    bcs next
    jsr cpu_wants
    jcs aligned
next:
    inc c_k
    lda c_k
    cmp #4
    jne loop
opp:
    ; nessuna capsula: la racchetta avversaria, se la palla va verso di lei e non è già
    ; rallentata, quando è nella fascia del laser, a pixel interi (|y - y avversaria| <= mezza
    ; racchetta avversaria + P_BLASTER_BAND); le y stanno in un byte
    jsr cpu_opp                 ; X = c_side (anche dopo cpu_wants)
    bne no
    lda pad_y+2,y
    jsr dy_pad
    sec
    sbc pad_half+2,y            ; dentro la racchetta avversaria
    bcc aligned
    cmp #<(P_BLASTER_BAND >> 16) + 1
    bcc aligned                 ; o nella fascia oltre il suo bordo
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
    ; all'altezza della racchetta: y <= alto + r e y >= basso - r (contact::band, X = lato)
    jsr contact::band
    cmp32 t_start, ball_y
    jmi no
    cmp32 ball_y, t_rel
    jmi no
    ; casa, avanzata, metà larghezza e raggio sono pixel interi (m_t = w/2 + r): le x si
    ; confrontano sulla parte intera, con la frazione solo dove decide (x > K)
    lda ball_r+2
    clc
    adc #<(HALF_W_FLOOR >> 16)
    sta m_t
    cpx #0
    jne right
    ; sinistra: casa + w/2 <= palla.sinistra <= avanzata + w/2
    clc
    lda pad_home+2
    adc m_t
    sta c_a
    lda pad_home+3
    adc #0
    sta c_a+1
    cmp16 ball_x+2, ball_x+3, c_a, c_a+1
    jmi no
    clc
    lda pad_fwd+2
    adc m_t
    sta c_a
    lda pad_fwd+3
    adc #0
    sta c_a+1
    cmpk16 c_a, c_a+1, ball_x
    jmi no
    jmp odds
right:
    ; destra: avanzata - w/2 <= palla.destra <= casa - w/2
    sec
    lda pad_fwd+4+2
    sbc m_t
    sta c_a
    lda pad_fwd+4+3
    sbc #0
    sta c_a+1
    cmp16 ball_x+2, ball_x+3, c_a, c_a+1
    bmi no
    sec
    lda pad_home+4+2
    sbc m_t
    sta c_a
    lda pad_home+4+3
    sbc #0
    sta c_a+1
    cmpk16 c_a, c_a+1, ball_x
    bmi no
odds:
    lda cpu_fwd,x
    beq no
    jmp below_zero
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
    ; resto - |passo| (con il passo negativo: resto + passo): sotto zero un passo in meno (e il
    ; resto torna tra 0 e |dx|)
    lda ball_dx+3
    bmi neg
    sub32 {pred_rem,x}, {pred_rem,x}, ball_dx
    jmp sign
neg:
    add32 {pred_rem,x}, {pred_rem,x}, ball_dx
sign:
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
    lda cpu_cx+2,x              ; (x della racchetta intera: contano i byte 2 e 3)
    cmp pad_x+2,x
    jne compute
    lda cpu_cx+3,x
    cmp pad_x+3,x
    beq :+
    jmp compute
:   beq32 {cpu_cvx,x}, ball_vx, :+
    jmp compute
:   beq32 {cpu_cb,x}, ball_boost, same
    jmp compute
same:
    ; tick passati dalla previsione (meno di 256), non più dei passi previsti
    sec
    lda tick
    sbc cpu_ct,x
    sta c_d
    lda tick+1
    sbc cpu_ct+1,x
    bne compute
    lda tick+2
    sbc cpu_ct+2,x
    bne compute
    lda tick+3
    sbc cpu_ct+3,x
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

; m_a = mul(vx, boost) della palla; con boost 1 è vx (mul(a, ONE) = a esatto). Distrugge m_b.
; Il prodotto dell'ultima coppia (vx, boost) si tiene da parte (vb_*): con la palla potenziata
; serve a ogni tick (ball_tick) e alle previsioni della CPU con gli stessi valori. All'avvio la
; chiave e il prodotto sono a zero: mul(0, 0) = 0.
.segment "BSS"
vb_key: .res 8                  ; vx e boost dell'ultimo prodotto
vb_val: .res 4
.segment "CODE"
.proc vx_boost
    lda ball_boost
    ora ball_boost+1
    ora ball_boost+3
    bne mul
    lda ball_boost+2
    cmp #>(ONE >> 8)
    bne mul
    mov32 m_a, ball_vx
    rts
mul:
    ldy #3
:   lda ball_vx,y
    cmp vb_key,y
    bne new
    lda ball_boost,y
    cmp vb_key+4,y
    bne new
    dey
    bpl :-
    mov32 m_a, vb_val
    rts
new:
    ldy #3
:   lda ball_vx,y
    sta vb_key,y
    lda ball_boost,y
    sta vb_key+4,y
    dey
    bpl :-
    mulq16 ball_vx, ball_boost
    mov32 vb_val, m_a
    rts
.endproc
vx_boost_mul = vx_boost::mul    ; (per ball_tick, che ha già guardato il boost 1)
.assert ONE = $00010000, error, "vx_boost: ONE nel byte 2"

; Quoziente in 8 bit di c_d / c_a (c_d >= 0, 0 < c_a < 2^24): C = 1 se non ci sta (c_d >= c_a << 8:
; confronto senza segno, dal byte 1); altrimenti C = 0, c_d = quoziente, c_d+1..3 = resto. Divisione
; lunga sul posto: c_d+1..3 è il resto (sotto c_a, 24 bit), in c_d entrano i bit del quoziente al
; posto di quelli del dividendo. Usa m_t, X e Y.
.proc div8
    sec
    lda c_d+1
    sbc c_a
    lda c_d+2
    sbc c_a+1
    lda c_d+3
    sbc c_a+2
    bcs done
    lda #8
    sta m_t
div:
    asl c_d
    rol c_d+1
    rol c_d+2
    rol c_d+3
    bcs over                    ; resto oltre 2^24 > c_a
    sec
    lda c_d+1
    sbc c_a
    tax
    lda c_d+2
    sbc c_a+1
    tay
    lda c_d+3
    sbc c_a+2
    bcc next                    ; resto < c_a
keep:
    sta c_d+3
    sty c_d+2
    stx c_d+1
    inc c_d
next:
    dec m_t
    bne div
    clc
done:
    rts
over:
    ; si sottrae di sicuro (C = 1 dal rol: nessun prestito in ingresso)
    lda c_d+1
    sbc c_a
    tax
    lda c_d+2
    sbc c_a+1
    tay
    lda c_d+3
    sbc c_a+2
    jmp keep
.endproc

; Match::ball_in_forward_area dopo BIF_STEPS passi, in forma chiusa (game.s; qui accanto a div8).
.proc bif_closed
    ; dopo BIF_STEPS passi, in forma chiusa (restano 64 - BIF_STEPS controlli; vy non è zero: con
    ; vy = 0 il controllo è uno solo). Il primo passo k con t1 + k |vy| >= 0: con D = -t1 - 1 = ~t1
    ; (>= 0), q = D / |vy| e r il resto, k = q + 1 e t1 + k |vy| = |vy| - r - 1. Il tratto cala a
    ; ogni passo: va ancora avanti fino al passo k se al passo q è positivo, t0 - q |vx| > 0. Le
    ; velocità stanno sotto i 256 pixel per tick (24 bit, come in arrival_y)
    lda t1+3
    jpl ball_in_forward_area::_band
    .repeat 4, k
    lda t1+k
    eor #$ff
    sta c_d+k
    .endrepeat
    lda cy
    sta c_a
    lda cy+1
    sta c_a+1
    lda cy+2
    sta c_a+2
    jsr div8
    jcs ball_in_forward_area::_no
    lda c_d                     ; q
    cmp #64 - BIF_STEPS - 1     ; k = q + 1 entro gli ultimi controlli
    jcs ball_in_forward_area::_no
    ; q |vx| in old_x (che non serve più), le tabelle dei quadrati su q
    sta sq1_lo
    sta sq1_hi
    eor #$ff
    sta sq2_lo
    sta sq2_hi
    ldy t2
    mul8
    sta old_x
    lda m_t
    sta old_x+1
    ldy t2+1
    mul8
    clc
    adc old_x+1
    sta old_x+1
    lda m_t
    adc #0
    sta old_x+2
    ldy t2+2
    mul8
    clc
    adc old_x+2
    sta old_x+2
    lda m_t
    adc #0
    sta old_x+3
    sec                         ; t0 - q |vx| > 0 (m_t: byte non nulli)
    lda t0
    sbc old_x
    sta m_t
    lda t0+1
    sbc old_x+1
    ora m_t
    sta m_t
    lda t0+2
    sbc old_x+2
    ora m_t
    sta m_t
    lda t0+3
    sbc old_x+3
    jmi ball_in_forward_area::_no
    ora m_t
    jeq ball_in_forward_area::_no
    clc                         ; t1 = |vy| - r - 1
    lda cy
    sbc c_d+1
    sta t1
    lda cy+1
    sbc c_d+2
    sta t1+1
    lda cy+2
    sbc c_d+3
    sta t1+2
    lda cy+3
    sbc #0
    sta t1+3
    jmp ball_in_forward_area::_band
.endproc

; arrival_y di cpu.rs: y della palla quando arriverà alla faccia della racchetta X, in c_y.
.assert P_PAD_HALF_W & $FF00FFFF = 0 .and (P_PAD_HALF_W + BALL_R_MAX) >> 16 < 256, error, "arrival_y: metà larghezza e raggio interi"
.proc arrival_y
    ; faccia: x della palla al contatto, a metà larghezza più il raggio (pixel interi, in m_t)
    ; dalla racchetta. c_d = distanza da percorrere - 1 (sottrazione con C = 0), poi meno la
    ; parte intera m_t (byte 2 e 3)
    lda ball_r+2
    clc
    adc #<(P_PAD_HALF_W >> 16)
    sta m_t
    cpx #0
    bne right
    ; verso sinistra: x della palla - x della racchetta - 1
    clc
    lda ball_x
    sbc pad_x
    sta c_d
    lda ball_x+1
    sbc pad_x+1
    sta c_d+1
    lda ball_x+2
    sbc pad_x+2
    tay
    lda ball_x+3
    sbc pad_x+3
    jmp face
right:
    ; verso destra: x della racchetta - x della palla - 1
    clc
    lda pad_x+4
    sbc ball_x
    sta c_d
    lda pad_x+4+1
    sbc ball_x+1
    sta c_d+1
    lda pad_x+4+2
    sbc ball_x+2
    tay
    lda pad_x+4+3
    sbc ball_x+3
face:
    tax
    sec
    tya
    sbc m_t
    sta c_d+2
    txa
    sbc #0
    sta c_d+3
dx:
    ; spostamento per tick: quello dell'ultimo tick per il TELEPORT (next.rs), mul(vx, boost)
    ; per la CPU (cpu.rs); stesso orizzonte (P_PREDICT_MAX = P_ARRIVAL_MAX)
    lda c_tp
    beq :+
    mov32 c_a, ball_dx
    jmp steps
:   jsr vx_boost
    mov32 c_a, m_a
steps:
    ldx c_side
    lda #0
    sta c_n
    ; già arrivata (distanza <= 0, distanza - 1 < 0) o palla ferma: nessun passo
    lda c_d+3
    jmi fold
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
    ; d > |dx| * P_PREDICT_MAX) si mira all'ultimo punto: si vede dal quoziente, senza moltiplicare
    ; (|dx| < 2^24, cioè meno di 256 pixel per tick). Alla fine c_d = passi - 1, c_d+1..3 il resto
    jsr div8
    bcs away
    ; resto e passo per gli aggiornamenti del BULLET (cpu_step: solo la CPU)
    lda c_tp
    bne quot
    ldy c_side
    lda c_d+1
    sta pred_rem,y
    lda c_d+2
    sta pred_rem+1,y
    lda c_d+3
    sta pred_rem+2,y
    lda #0
    sta pred_rem+3,y
    mov32 {pred_dxa,y}, c_a
quot:
    lda c_d                     ; passi - 1
    cmp #P_PREDICT_MAX
    bcs away
    adc #1                      ; C = 0
    sta c_n
    jmp fold
away:
    lda #P_PREDICT_MAX
    sta c_n
fold:
    ; y dopo n passi senza bordi: y + n * vy. Bastano i 32 bit bassi del prodotto, che con vy in
    ; complemento a due sono quelli del prodotto con segno: n per ogni byte di vy, sommati a
    ; scalare di un byte. Le tabelle dei quadrati puntate una volta sola su n (come umul8)
    lda c_n
    sta sq1_lo
    sta sq1_hi
    eor #$ff
    sta sq2_lo
    sta sq2_hi
    ldy ball_vy                 ; n * vy0: byte 0 e 1
    sec
    lda (sq1_lo),y
    sbc (sq2_lo),y
    sta c_y
    lda (sq1_hi),y
    sbc (sq2_hi),y
    sta c_y+1
    ldy ball_vy+1               ; n * vy1: byte 1 e 2 (alto al più $FE: il riporto ci sta)
    sec
    lda (sq1_lo),y
    sbc (sq2_lo),y
    tax
    lda (sq1_hi),y
    sbc (sq2_hi),y
    sta c_y+2
    txa
    clc
    adc c_y+1
    sta c_y+1
    bcc :+
    inc c_y+2
:   ldy ball_vy+2               ; n * vy2: byte 2 e 3
    sec
    lda (sq1_lo),y
    sbc (sq2_lo),y
    tax
    lda (sq1_hi),y
    sbc (sq2_hi),y
    sta c_y+3
    txa
    clc
    adc c_y+2
    sta c_y+2
    bcc :+
    inc c_y+3
:   ldy ball_vy+3               ; n * vy3: solo il byte 3
    sec
    lda (sq1_lo),y
    sbc (sq2_lo),y
    clc
    adc c_y+3
    sta c_y+3
    ; + y, anche nella previsione senza bordi per gli aggiornamenti del BULLET
    lda c_tp
    ora c_side
    tay
    clc
    .repeat 4, k
    lda c_y+k
    adc ball_y+k
    sta c_y+k
    sta pred_y+k,y
    .endrepeat
    ; (prosegue in fold_y)
.endproc

; Riflessioni di c_y sui bordi basso (r + 1) e alto (H - 1 - r): onda triangolare di periodo
; 2 (alto - basso). X = c_side alla fine.
;
; Il raggio è un numero intero di pixel (R = ball_r+2, gli altri byte a zero: ball_r prende solo
; i valori di BALL_R_MAX), quindi basso, ampiezza (H - 2 - 2R, sotto 256) e periodo sono interi:
; si lavora sulla parte intera della y (16 bit con il segno, i byte 2 e 3), la frazione resta e
; cambia solo nella parte riflessa (u > ampiezza: basso + periodo - u).
.assert (P_HEIGHT - ONE) & $FF00FFFF = 0, error, "fold_y: H - 1 intero, sotto 256 pixel"
.assert (P_BALL_R | P_BALL_R_BOOST | P_BALL_R_FWD) & $FF80FFFF = 0, error, "fold_y: raggio intero sotto 128 pixel"
.assert (P_HEIGHT >> 16) - 2 - 2 * (BALL_R_MAX >> 16) > 0, error, "fold_y: ampiezza positiva"
.proc fold_y
    ; già tra i bordi (y - r >= 1 e y + r <= H - 1): resta y, come dal calcolo intero (u tra 0 e
    ; l'ampiezza). Così le previsioni senza rimbalzi
    lda c_y+3
    bne slow                    ; y < 0, o oltre 256 pixel (oltre H)
    lda c_y+2
    cmp ball_r+2
    beq slow                    ; int(y) <= R: y - r < 1
    bcc slow
    clc
    adc ball_r+2                ; int(y) + R
    bcs slow
    cmp #<((P_HEIGHT - ONE) >> 16)
    bcc inside
    bne slow
    lda c_y                     ; y + r = H - 1 solo senza frazione
    ora c_y+1
    bne slow
inside:
    ldx c_side
    rts
slow:
    ; ampiezza (c_d, un byte) e periodo (c_a, 16 bit)
    lda ball_r+2
    asl a
    sta c_a
    lda #<((P_HEIGHT >> 16) - 2)
    sec
    sbc c_a
    sta c_d
    asl a
    sta c_a
    lda #0
    rol a
    sta c_a+1
    ; U = int(y) - basso (R + 1: sottrazione con C = 0); u = U + frazione
    clc
    lda c_y+2
    sbc ball_r+2
    sta c_y+2
    lda c_y+3
    sbc #0
    sta c_y+3
    ; u tra 0 e il periodo (interi: conta solo U)
    bpl down
up:
    clc
    lda c_y+2
    adc c_a
    sta c_y+2
    lda c_y+3
    adc c_a+1
    sta c_y+3
    bmi up
down:
    sec
    lda c_y+2
    sbc c_a
    tax
    lda c_y+3
    sbc c_a+1
    bcc folded                  ; U < periodo
    sta c_y+3
    stx c_y+2
    bcs down
folded:
    ; u <= ampiezza (U < ampiezza, o uguale senza frazione): basso + u
    lda c_y+3
    bne mirror
    lda c_y+2
    cmp c_d
    bcc plain
    bne mirror
    lda c_y
    ora c_y+1
    beq plain
mirror:
    ; altrimenti basso + periodo - u: periodo * ONE - u sui 4 byte (la frazione dà il prestito)
    sec
    lda #0
    sbc c_y
    sta c_y
    lda #0
    sbc c_y+1
    sta c_y+1
    lda c_a
    sbc c_y+2
    sta c_y+2
    lda c_a+1
    sbc c_y+3
    sta c_y+3
plain:
    sec                         ; + basso (R + 1)
    lda c_y+2
    adc ball_r+2
    sta c_y+2
    lda c_y+3
    adc #0
    sta c_y+3
    ldx c_side
    rts
.endproc
