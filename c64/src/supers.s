; Mosse speciali di NEXT: traduzione di `Next::super_moves` (rust/core/src/next.rs: barra, STRAIGHT
; SHOT e RISING STRIKE) e di `Cpu::special` (cpu.rs), più i gesti dei comandi, la grafica e i
; suoni. Sempre accese (cfg_super, da play_main), valgono per le partite NEXT e CHALLENGE; spente
; (solo nei banchi di prova) la partita è quella di prima (nessuna routine di qui cambia lo stato).
;
; Il programma è quasi pieno: gran parte del codice sta nella cartuccia (segmento SMCODE, nel
; .prg da SM_IMG, dopo le routine dell'avvio) e gira a SM_RUN, nella RAM del secondo schermo, che
; serve solo ai colori della bitmap dell'attract. Lo copia la scelta di NEXT, una pagina per frame
; nei primi frame di READY (sm_page): ogni partita NEXT passa di lì e l'attract, che ricopre quella
; RAM, viene sempre dopo. Nel programma (segmento CODE) ci sono le chiamate (next.s, game.s, cpu.s,
; input.s, pick.s, video.s), il menu, sm_page e le routine della partita che non ci stanno; poche
; altre (segmento LOWCODE) stanno nella pagina 2, dove title_unpack le copia all'avvio.
;
; Stato (per giocatore, passo 4 come il resto: X = lato * 4):
; - sm_meter: la barra, 0-P_SUPER_METER_MAX; ogni colpo P_SUPER_GAIN_HIT, lo scatto che intercetta
;   la palla P_SUPER_GAIN_DASH, il punto subito P_SUPER_GAIN_CONCEDED (sm_gain);
; - sm_arm: la mossa armata per il prossimo colpo, 0 nessuna, 1-2 STRAIGHT SHOT di livello 1-2,
;   3-4 RISING STRIKE di livello 1-2. Una mossa spende tutti i settori pieni (P_SUPER_COST
;   ciascuno, al massimo 2): il livello è quanti ne ha spesi;
; - sm_fl: il tiro in volo (Next::special_flight e special_level, per il disegno), 0 nessuno,
;   1 STRAIGHT SHOT, 2 RISING STRIKE, + 4 al livello 2;
; - sm_rise: RISING STRIKE da impennare (Next::rise_break), 0 nessuno, 1-2 dal giocatore sinistro
;   di livello 1-2, 3-4 dal destro: la soglia è in rise_lo/rise_hi.
;
; Comandi: in_flags IN_STRAIGHT o IN_RISE (PlayerInput::special), dalla CPU (sm_cpu) o dal gesto
; del joystick (sm_joy), come sul MiSTer, con avanti = verso l'avversario: giù, giù-avanti, avanti +
; fuoco = STRAIGHT SHOT; avanti, giù, giù-avanti + fuoco = RISING STRIKE. Il fuoco che completa il
; gesto diventa la mossa solo se la mossa può partire; altrimenti attiva il bonus selezionato, come
; sempre. Con i paddle nessun gesto: il riconoscitore della manopola del MiSTer (circa 400 byte)
; non ci sta.
;
; A schermo (sm_hud): la barra di ciascun giocatore accanto alle riserve (riga BAR_ROW, caratteri
; di PRESS START presi in prestito: gialla per settore pieno, cioè quando la mossa è pronta),
; l'icona gialla della mossa armata accanto alla racchetta (sprite dell'icona del bonus, sm_icon),
; la racchetta gialla con la mossa di livello 2, la scritta "P1 STRAIGHT SHOT!" (o "P1 MAX ...")
; all'attivazione, la palla gialla con la coda nel tiro della mossa e a lampi quando RISING STRIKE
; s'impenna. Suoni: gli effetti MOVE (attivazione) e SPECIAL (colpo) della ROM della musica, con
; le priorità del player Verilog.

SM_RUN   = $C400                ; dove gira (paddws.cfg, SMRAM)
SM_IMG   = $D800                ; dove sta nel .prg (SMIMG), poi nella flash
SM_BANK  = PRG_BANK + (SM_IMG - $0800) / $4000
SM_SRC   = $80 + ((SM_IMG - $0800) .mod $4000) / 256
SM_PAGES = >(__SMCODE_SIZE__ + 255)
.import __SMCODE_LOAD__, __SMCODE_RUN__, __SMCODE_SIZE__
.assert __SMCODE_LOAD__ = SM_IMG .and __SMCODE_RUN__ = SM_RUN, lderror, "mosse speciali fuori posto"
.assert ((SM_IMG - $0800) .mod $4000) + $0400 <= $2000, error, "mosse speciali oltre la ROML del banco"
.assert SM_RUN = SCREEN2, error, "le mosse speciali stanno nel secondo schermo"

MAX_LEVEL  = 2                  ; MAX_SPECIAL_LEVEL
SM_CELL    = P_SUPER_METER_MAX / 4  ; barra: quattro celle, due per settore
BAR_ROW    = 1                  ; barra: riga e prima colonna di ciascun lato, accanto alle riserve
BAR_COL_L  = 6
BAR_COL_R  = 30
SM_FLASH   = 12                 ; frame del lampo dell'impennata
SFX_MOVE    = SID_EFFECTS + 1   ; sm_fxp: effetti 6 e 7 del player (sid.s, fx_start)
SFX_SPECIAL = SID_EFFECTS + 2
SM_ICON0   = SP_WARP + 1        ; icone: STRAIGHT SHOT sinistro e destro, RISING STRIKE (sm_icon)
SM_ICON_ADDR = $C000 + SM_ICON0 * 64
.assert P_SUPER_METER_MAX = MAX_LEVEL * P_SUPER_COST, error, "barra: due settori"
.assert SM_CELL = 4 * (BAR_CHARS - 1), error, "barra: un carattere ogni 4 unità della cella"
.assert P_SUPER_METER_MAX + P_SUPER_GAIN_CONCEDED < 256, error, "barra in un byte"
.assert SM_ICON_ADDR + 4 * 64 <= VOICE_RES, error, "icone delle mosse sopra la voce di CHALLENGE"
.assert IN_RISE = $40, error, "IN_RISE nel bit 6 (bit, bvc)"

; RISING STRIKE: s'impenna passati i 5/8 del campo (7/8 al livello 2) contati da chi colpisce
RISE_1 = (P_WIDTH >> 1) + (P_WIDTH >> 3)
RISE_2 = P_WIDTH - (P_WIDTH >> 3)
.assert ((RISE_1 | RISE_2) & $FFFF) = 0, error, "soglie di RISING STRIKE: pixel interi"

; gesto del joystick: tempi a 50 Hz di move_gesture (mister/rtl/pong_top.v)
STEP_F    = 15                  ; 0,3 s tra due direzioni
BTN_F     = 13                  ; 0,25 s dall'ultima al fuoco
; colpo di una mossa sulla racchetta di chi l'ha fatto (KICK_SECONDS di next_ui.rs): rinculo e
; lampo per 0,3 s; con la MAX il doppio (31 frame: rinculo più ampio, due lampi)
KICK_FRAMES = 15

.segment "BSS"
cfg_super: .res 1               ; mosse speciali accese: 1 dall'accensione (play_main), 0 solo nei banchi di prova
sm_on:     .res 1               ; mosse speciali nella partita in corso (next_init, solo NEXT)

.segment "LOWBSS"
sm_dash:   .res 1               ; bit 7: il colpo in corso è lo scatto (next_on_hit)
sm_vars:                        ; a zero a ogni partita NEXT (next_init)
sm_meter:  .res 8
sm_arm:    .res 8
sm_fl:     .res 1
sm_rise:   .res 1
cpu_wrise: .res 8               ; CPU: al tick prima un RISING STRIKE doveva ancora impennarsi
sm_age:    .res 8               ; joystick: frame da giù, giù-avanti, avanti tenuti (passo 4)
sm_shown:  .res 8               ; barra a schermo + 1 (0 = da disegnare)
sm_lnew:   .res 1               ; scritta da mostrare: $80 + mossa armata (sm_tick)
sm_lside:  .res 1
sm_fxp:    .res 1               ; effetto da suonare (SFX_*)
sm_flash:  .res 1
sm_icons:  .res 1               ; icone già preparate
SM_VARS = * - sm_vars
.assert SM_VARS <= 128, error, "stato delle mosse speciali: next_init lo azzera con un byte"

.segment "NEXTBSS"
sm_kick:   .res 5               ; colpo di una mossa: frame dell'animazione della racchetta, per n_side (0, 4)

; ------------------------------------------------------------------------------------ programma

.segment "CODE"

; Velocità orizzontale minima al colpo della mossa Y (1-2 STRAIGHT SHOT, 3-4 RISING STRIKE) di
; n_side (raise_vx di next.rs): sotto, |vx| diventa il minimo della difficoltà, nel verso di chi ha
; colpito. Nella MAIN perché SMCODE è pieno; conserva Y, X torna n_side. Circa 160 cicli al più. I
; cicli vanno da X = $FC a 0 (inx non tocca il riporto) su ball_vx + 4, che in pagina zero torna a
; ball_vx.
.proc sm_floor
    sty m_t
    lda cfg_diff
    asl a
    asl a
    cpy #3
    bcc :+
    adc #16 - 1                 ; RISING STRIKE: la seconda tabella (C = 1)
:   tay
    ldx #$fc
    lda n_side
    bne right
    sec                         ; da sinistra vx > 0: vx - minimo, con il prestito vx < minimo
:   lda ball_vx + 4,x
    sbc min_tab,y
    iny
    inx
    bne :-
    bcs done
    jsr back
:   lda min_tab,y               ; vx = minimo
    sta ball_vx + 4,x
    iny
    inx
    bne :-
    beq done
right:
    clc                         ; da destra vx < 0: vx + minimo, con il riporto |vx| <= minimo
:   lda ball_vx + 4,x           ; (a |vx| = minimo la copia non cambia nulla)
    adc min_tab,y
    iny
    inx
    bne :-
    bcc done
    jsr back
    sec
:   lda #0                      ; vx = -minimo
    sbc min_tab,y
    sta ball_vx + 4,x
    iny
    inx
    bne :-
done:
    ldy m_t
    ldx n_side
    ; animazione del colpo sulla racchetta (pad_sprite): KICK_FRAMES frame, il doppio con la MAX
    ; (codice pari), che rincula di più e lampeggia due volte
    tya
    lsr a
    lda #KICK_FRAMES
    bcs :+
    lda #KICK_FRAMES * 2 + 1
:   sta sm_kick,x
    rts
back:                           ; di nuovo al primo byte del minimo
    dey
    dey
    dey
    dey
    ldx #$fc
    rts
; per difficoltà: STRAIGHT SHOT, poi RISING STRIKE (Params::super_min_vx_*)
min_tab: .dword T_SM_MIN_STRAIGHT, T_SM_MIN_RISE
.endproc
.assert ball_vx < $100 - 4, error, "sm_floor: ball_vx deve stare in pagina zero"

; Pagina A del codice delle mosse speciali dalla cartuccia a SM_RUN (circa 3.800 cicli).
.proc sm_page
    tax
    clc
    adc #SM_SRC
    sta ef_src+2
    txa
    adc #>SM_RUN
    tay
    lda #SM_BANK
    ldx #1
    jmp ef_copy
.endproc

; Inizio della partita NEXT con le mosse accese (next_init, stato già a zero): gesti dimenticati,
; caratteri della barra al posto di quelli di PRESS START (bullet_chars li rimette nelle altre
; partite). Le icone si preparano nei primi frame (sm_hud).
.proc sm_init
    lda #$ff
    ldx #7
:   sta sm_age,x
    dex
    bpl :-
    ldx #8 * BAR_CHARS - 1
:   lda bar_glyphs,x
    sta CHARSET + 8 * BAR_C0,x
    dex
    bpl :-
    rts
.endproc

; Scritta della mossa attivata (label_draw con il bit 7 di lb_bonus: $80 + mossa armata) nella
; riga LABEL_ROW: "P1 STRAIGHT SHOT!", con "MAX" davanti al livello 2, gialla.
.proc sm_label
    lda lb_bonus
    and #$7f
    sta m_lo                    ; 1-4
    lsr a                       ; C = 1: livello 1
    lda #3 + 14
    bcs :+
    lda #3 + 4 + 14
:   sta lb_len
    lsr a
    eor #$ff
    sec
    adc #20
    sta lb_col
    sta v_col                   ; colonna del pezzo dopo
    lda #<s_p1
    ldy #>s_p1
    ldx lb_player
    beq :+
    lda #<s_p2
    ldy #>s_p2
:   jsr text
    lda m_lo
    lsr a
    bcs :+
    lda #<s_max
    ldy #>s_max
    jsr text
:   lda #<s_straight
    ldy #>s_straight
    ldx m_lo
    cpx #3
    bcc :+
    lda #<s_rise
    ldy #>s_rise
:   jsr text
    lda lb_len
    sta v_n
    ldy lb_col
    ldx #LABEL_ROW
    lda #COL_YELLOW
    jmp color_span
text:
    sta ptr2
    sty ptr2+1
    ldx v_col
    ldy #LABEL_ROW
    jsr print_str
    stx v_col
    rts
.endproc

s_max:      .byte "MAX ", 0
s_straight: .byte "STRAIGHT SHOT!", 0
s_rise:     .byte "RISING STRIKE!", 0
bar_glyphs: .byte BAR_GLYPHS
; tracce degli effetti 6 e 7 del player (sid.s, fx_start), dalla ROM della musica
sid_track_move:    .byte SID_TRACK_MOVE
sid_track_special: .byte SID_TRACK_SPECIAL

; ------------------------------------------------------------------------------------ pagina 2

.segment "LOWCODE"

; C = 1 se il giocatore X può eseguire una mossa (NextPlayer::special_ready): barra sufficiente,
; nessuna mossa né bonus armato. X resta.
.proc sm_ready
    lda sm_arm,x
    bne no
    lda nx_armed,x
    cmp #B_NONE
    bne no
    lda sm_meter,x
    cmp #P_SUPER_COST
    rts
no: clc
    rts
.endproc

; C = 1 se il giocatore X può eseguire una mossa adesso: pronta (sm_ready) e la palla in gioco.
.proc sm_allow
    lda serve_timer
    ora serve_timer+1
    ora serve_timer+2
    ora serve_timer+3
    beq sm_ready
    clc
    rts
.endproc

; La barra del giocatore X cresce di A, fino al massimo. X resta.
.proc sm_gain
    clc
    adc sm_meter,x
    cmp #P_SUPER_METER_MAX + 1
    bcc :+
    lda #P_SUPER_METER_MAX
:   sta sm_meter,x
    rts
.endproc

; Match::next_on_point: le mosse armate finiscono e chi ha subito il punto carica la barra.
.proc sm_point
    lda sm_on
    beq done
    lda #0
    sta sm_arm
    sta sm_arm+4
    lda scorer
    eor #4
    tax
    lda #P_SUPER_GAIN_CONCEDED
    jmp sm_gain
done:
    rts
.endproc

; Icona della mossa armata del giocatore X (Y = lato, 0 o 1) per next_sprites: C = 1, A = immagine
; - SP_ICON0 e m_t = colore; C = 0 senza mossa. X e Y restano.
.proc sm_icon
    lda sm_arm,x
    beq no
    cmp #3                      ; C = 1: RISING STRIKE
    lda #0
    rol a
    asl a
    sty m_t
    ora m_t
    clc
    adc #SM_ICON0 - SP_ICON0
    pha
    lda egg_yel
    sta m_t
    pla
    sec
    rts
no: clc
    rts
.endproc

; ------------------------------------------------------------------------------------ cartuccia

.segment "SMCODE"

; Match::next_special, alla fine del tick NEXT (next_tick), fuori dall'attesa della battuta: la
; mossa comandata (IN_STRAIGHT o IN_RISE) si arma, se può partire, spendendo tutti i settori pieni.
.proc sm_tick
    lda sm_on
    beq done
    or32 serve_timer
    bne done
    ldx #0
    jsr one
    ldx #4
one:
    lda in_flags,x
    and #IN_STRAIGHT | IN_RISE
    beq done
    sta m_t
    jsr sm_ready
    bcc done
    lda sm_meter,x              ; livello: settori pieni, al massimo MAX_LEVEL
    ldy #0
:   cmp #P_SUPER_COST
    bcc :+
    sbc #P_SUPER_COST
    iny
    cpy #MAX_LEVEL
    bne :-
:   sta sm_meter,x
    tya
    ldy #EV_STRAIGHT_HI
    bit m_t
    bvc :+                      ; RISING STRIKE: 3-4
    clc
    adc #2
    ldy #EV_RISE_HI
:   sta sm_arm,x
    ora #$80                    ; scritta e suono (sm_hud)
    sta sm_lnew
    stx sm_lside
    tya
    ora events+1
    sta events+1
    lda #SFX_MOVE
    sta sm_fxp
done:
    rts
.endproc

; Fine di Match::next_on_hit (colpo di n_side, scatto nel bit 7 di sm_dash): la barra cresce, poi
; il tiro della mossa armata, almeno alla velocità minima della mossa. STRAIGHT SHOT: orizzontale e
; più veloce (boost += boost >> (shift + 2 - livello)); RISING STRIKE: orizzontale, poi s'impenna
; alla soglia (sm_motion).
.proc sm_hit
    lda sm_on
    beq done
    ldx n_side
    lda #P_SUPER_GAIN_HIT
    bit sm_dash
    bpl :+
    lda #P_SUPER_GAIN_DASH
:   jsr sm_gain
    ldy sm_arm,x
    beq done
    lda #0
    sta sm_arm,x
    sta ball_vy
    sta ball_vy+1
    sta ball_vy+2
    sta ball_vy+3
    lda flight_of-1,y
    sta sm_fl
    event_hi EV_SPECIAL_HI
    lda #SFX_SPECIAL
    sta sm_fxp
    jsr sm_floor
    cpy #3
    bcs rise
    mov32 n_t, ball_boost
    tya
    eor #$ff
    sec
    adc #P_SUPER_STRAIGHT_SHIFT + MAX_LEVEL
    tay
    beq add
:   lsr n_t+3                   ; il boost è positivo
    ror n_t+2
    ror n_t+1
    ror n_t
    dey
    bne :-
add:
    add32 ball_boost, ball_boost, n_t
done:
    rts
rise:
    tya                         ; 3-4; a sinistra 1-2 (cpx: C = 1)
    cpx #0
    bne :+
    sbc #2
:   sta sm_rise
    rts
flight_of: .byte 1, 1 + 4, 2, 2 + 4
.endproc

; Next::ball_motion, RISING STRIKE (sm_rise non zero, n_u = |vx|): passata la soglia la palla
; s'impenna a 45 gradi verso il bordo lontano dalla racchetta verso cui va. La previsione delle
; CPU (cached_arrival) tiene vx e boost, non vy: va rifatta.
.proc sm_motion
    ldy sm_rise
    lda ball_vx+3
    bmi left
    lda ball_x+2                ; verso destra: x >= soglia (intera)
    cmp rise_lo-1,y
    lda ball_x+3
    sbc rise_hi-1,y
    bcc no
    lda #0                      ; away_from guarda la racchetta di n_side xor 4
    beq go
left:
    sec                         ; verso sinistra: soglia - x >= 0
    lda #0
    sbc ball_x
    lda #0
    sbc ball_x+1
    lda rise_lo-1,y
    sbc ball_x+2
    lda rise_hi-1,y
    sbc ball_x+3
    bcc no
    lda #4
go:
    sta n_side
    lda #0
    sta sm_rise
    sta cpu_ok
    sta cpu_ok+4
    mov32 n_t, n_u
    jsr away_from
    lda #SM_FLASH
    sta sm_flash
no:
    rts
.endproc

rise_lo: .byte <(RISE_1 >> 16), <(RISE_2 >> 16), <((P_WIDTH - RISE_1) >> 16), <((P_WIDTH - RISE_2) >> 16)
rise_hi: .byte >(RISE_1 >> 16), >(RISE_2 >> 16), >((P_WIDTH - RISE_1) >> 16), >((P_WIDTH - RISE_2) >> 16)

; Cpu::input per la CPU X (c_side) con un RISING STRIKE in arrivo: quando s'impenna il tempo di
; reazione riparte da capo (cpu_since), come per una palla nuova.
.proc sm_cpu_rise
    lda sm_rise
    beq none
    lda #1
    sta cpu_wrise,x
    rts
none:
    lda cpu_wrise,x
    beq done
    lda #0
    sta cpu_wrise,x
    lda c_coming
    beq done
    lda #0
    sta cpu_since,x
done:
    rts
.endproc

; Cpu::special per la CPU X (c_side), con il suo generatore in rng, se non attiva un bonus: con la
; palla in arrivo già vista (cb_aim, punto d'arrivo previsto in cb_y), la mossa pronta, la
; racchetta sul punto d'arrivo e nessun errore di mira voluto (entro mezza racchetta tutti e due),
; un'estrazione below(odds * 2): 0 STRAIGHT SHOT, 1 RISING STRIKE (odds = bonus_odds, il doppio con
; un solo settore pieno). X resta.
.proc sm_cpu
    lda c_flags
    and #IN_ACTIVATE
    bne no
    lda cb_aim
    beq no
    jsr sm_ready
    bcc no
    sub32 c_d, cb_y, {pad_y,x}
    jsr half_out
    bcs no
    mov32 c_d, {cpu_error,x}
    jsr half_out
    bcs no
    lda cpu_bonus,x
    ldy sm_meter,x
    cpy #MAX_LEVEL * P_SUPER_COST
    bcs :+
    asl a
:   ldy #0
    asl a
    bcc :+
    iny
:   sta m_b
    sty m_b+1
    jsr rng_below               ; A basso, X alto
    ldy #IN_STRAIGHT
    cpx #0
    bne none
    cmp #1
    bcc got
    bne none
    ldy #IN_RISE
got:
    tya
    ora c_flags
    sta c_flags
none:
    ldx c_side
no:
    rts
; C = 1 se |c_d| è oltre mezza racchetta della CPU X
half_out:
    jsr abs_cd
    cmp32 {pad_half,x}, c_d
    asl a                       ; il segno di mezza racchetta - |c_d|
    rts
.endproc

; Joystick del giocatore Y (X = Y * 4), a ogni frame prima del fuoco (next_keys): età delle tre
; direzioni, poi il fuoco che completa un gesto, se la mossa può partire, diventa la mossa (e non
; attiva il bonus). X e Y restano.
.proc sm_joy
    lda sm_on
    beq done
    lda joy,y                   ; tenute: bit 0 giù, 1 giù-avanti, 2 avanti
    and #JOY_DOWN | JOY_UP
    sta m_lo
    lda joy,y
    and toward,y
    beq not_fw
    lda m_lo
    beq fw
    cmp #JOY_DOWN
    bne none
    lda #2
    bne have
fw: lda #4
    bne have
not_fw:
    lda m_lo
    and #JOY_DOWN
    lsr a
    .byte $2c                   ; (bit: salta il lda)
none:
    lda #0
have:
    sta m_lo
    lda #3
    sta m_t
age:
    lsr m_lo
    lda #0
    bcs :+
    lda sm_age,x
    cmp #$ff
    beq :++
    adc #1
:   sta sm_age,x
:   inx
    dec m_t
    bne age
    tya
    asl a
    asl a
    tax
    lda fire_edge,y
    beq done
    jsr sm_allow
    bcc done
    jsr gesture
    beq done
    ora in_flags,x
    sta in_flags,x
    lda #0
    sta fire_edge,y
    lda #$ff
    sta sm_age,x
    sta sm_age+1,x
    sta sm_age+2,x
done:
    rts
.endproc

; Gesto del joystick dalle età del giocatore X (move_gesture): A = IN_RISE, IN_STRAIGHT o 0 (Z = 1).
; Le direzioni nell'ordine, a non più di STEP_F frame l'una dall'altra, l'ultima entro BTN_F.
.proc gesture
    lda sm_age,x                ; giù prima di giù-avanti
    sec
    sbc sm_age+1,x
    bcc no
    cmp #STEP_F + 1
    bcs no
    lda sm_age+1,x              ; RISING STRIKE: avanti, giù, giù-avanti
    cmp #BTN_F + 1
    bcs qcf
    lda sm_age+2,x
    sec
    sbc sm_age,x
    bcc qcf
    cmp #STEP_F + 1
    bcs qcf
    lda #IN_RISE
    rts
qcf:
    lda sm_age+2,x              ; STRAIGHT SHOT: giù, giù-avanti, avanti
    cmp #BTN_F + 1
    bcs no
    lda sm_age+1,x
    sec
    sbc sm_age+2,x
    bcc no
    cmp #STEP_F + 1
    bcs no
    lda #IN_STRAIGHT
    rts
no: lda #0
    rts
.endproc

; A ogni frame di partita NEXT (next_hud, dopo gli sprite): palla e racchette gialle, scritta e
; suono della mossa attivata o del suo colpo, barre, icone ancora da preparare.
.proc sm_hud
    lda sm_on
    bne :+
    rts
:
.ifdef SMFULL
    lda #P_SUPER_METER_MAX      ; prova per VICE (-Define SMFULL): barre sempre piene, mosse MAX
    sta sm_meter
    sta sm_meter+4
.endif
    lda sm_fl                   ; tiro della mossa: palla gialla, bianca a lampi all'impennata
    beq pads
    ldx egg_yel
    lda sm_flash
    beq :+
    dec sm_flash
    and #2
    beq :+
    ldx #COL_WHITE
:   stx sh_col
pads:
    ldx #0                      ; mossa di livello 2 armata (sm_arm pari): racchetta gialla
    jsr pad
    ldx #4
    jsr pad
    jsr frame_late_small        ; frame già avanti: il resto al prossimo
    bcs done
    lda sm_lnew                 ; scritta della mossa attivata: next_fx_scene la disegna appena
    beq sound                   ; il frame ha tempo
    lda lb_frames
    beq :+
    jsr label_erase
    lda #0
    sta lb_frames
:   lda sm_lnew
    sta lb_bonus
    lda sm_lside
    sta lb_player
    lda #1
    sta lb_pend
    lda #0
    sta sm_lnew
sound:
    lda sm_fxp                  ; MOVE dopo BOOST e punto, SPECIAL solo dopo il punto (pong_sid.v)
    beq bars
    cmp #SFX_MOVE
    bne :+
    lda events
    and #EV_BOOST | EV_SCORE
    bne drop
:   jsr frame_late_small
    bcs bars
    bit $fffb                   ; la voce di CHALLENGE ha il SID
    bmi drop
    ldx sm_fxp
    jsr sid_fx::start
    lda #0
    sta fx_pend                 ; l'effetto rimandato del tick (colpo o muro) non lo copre
drop:
    lda #0
    sta sm_fxp
bars:
    ldx #0
    jsr bar
    ldx #4
    jsr bar
    lda sm_icons
    cmp #4
    bcs done
    jsr frame_late_small
    bcs done
    jmp icon
done:
    rts
pad:
    lda sm_arm,x
    beq :+
    lsr a
    bcs :+
    txa
    lsr a
    lsr a
    tax
    lda egg_yel
    sta sh_col + SPN_PAD,x
:   rts
.endproc

; Barra del giocatore X, se è cambiata e il frame ha tempo: quattro celle dalla colonna del suo
; lato, ognuna di SM_CELL unità (un carattere ogni 4), gialle quando il loro settore è pieno.
.proc bar
    lda sm_meter,x
    clc
    adc #1
    cmp sm_shown,x
    beq done
    pha
    jsr frame_late_small
    pla
    bcs done
    sta sm_shown,x
    lda sm_meter,x
    sta m_t                     ; da distribuire
    sta v_n
    ldy #BAR_COL_L
    cpx #0
    beq :+
    ldy #BAR_COL_R
:   ldx #0
cell:
    lda m_t
    cmp #SM_CELL
    bcc :+
    lda #SM_CELL
:   pha
    eor #$ff
    sec
    adc m_t
    sta m_t
    pla
    lsr a
    lsr a
    clc
    adc #BAR_C0
    sta SCREEN + 40 * BAR_ROW,y
    lda v_n
    cmp sector,x
    lda #COL_GRAY
    bcc :+
    lda egg_yel
:   sta $d800 + 40 * BAR_ROW,y
    iny
    inx
    cpx #4
    bne cell
done:
    rts
sector: .byte P_SUPER_COST, P_SUPER_COST, 2 * P_SUPER_COST, 2 * P_SUPER_COST
.endproc

; Un'icona delle mosse (sm_icons) nel suo sprite: righe 0-7 della prima colonna, il resto vuoto.
.proc icon
    lda sm_icons
    asl a
    asl a
    asl a
    sta m_lo                    ; prima riga in super_icons
    lda sm_icons
    lsr a
    ror a
    ror a                       ; icona * 64
    tax
    ldy #63
    lda #0
:   sta SM_ICON_ADDR,x
    inx
    dey
    bpl :-
    txa
    sec
    sbc #64
    tax
    ldy m_lo
:   lda super_icons,y
    sta SM_ICON_ADDR,x
    inx
    inx
    inx
    iny
    tya
    and #7
    bne :-
    inc sm_icons
    rts
.endproc

super_icons: .byte SUPER_ICONS

.segment "CODE"
