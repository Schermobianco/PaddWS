; Modalità NEXT prima e durante la partita: scelta dei 3 bonus e del tipo di racchetta (come
; rust/game/src/next_ui.rs `Pick` e paddle_ui.rs `PaddlePick`, con lo schermo del MiSTer in
; mister/rtl/next_render.v) e riserve in alto durante la partita.
;
; Ogni giocatore ha il suo cursore (joystick su e giù, o la rotazione del paddle) e il fuoco
; prende o lascia la voce. Dopo 10 secondi vale quello che c'è (i bonus mancanti dalle scelte
; predefinite), poi READY! per 1,2 secondi. Contro la CPU, la CPU sceglie da sola a caso dal seme
; della partita, con gli stessi numeri del PC.

PICK_FRAMES  = 10 * 50
READY_FRAMES = 60               ; 1,2 secondi
PICK_ROW0    = 8                ; prima voce, una ogni 2 righe
PICK_HINT    = 23               ; riga dei comandi e di READY!
PICK_SEED_BONUS = $9E3779B9     ; seme xor delle scelte della CPU (next_ui.rs, paddle_ui.rs)
PICK_SEED_KIND  = $7A11E5ED
KINDS = 7

; fasi della scena: il lavoro di un cambio di schermo non sta in un frame
PH_NONE  = 0
PH_CLEAR = 1                    ; pulire lo schermo
PH_CHARS = 2                    ; caratteri della scelta (ef_pick, circa 11.000 cicli)
PH_DRAW  = 3                    ; scritte fisse (poi le colonne, una per frame)
PH_MATCH = 4                    ; partita (lo schermo è già pulito)

.segment "NEXTBSS"
.segment "ZEROPAGE"
pk_kind:   .res 1               ; 0 scelta dei bonus, 1 della racchetta
.segment "NEXTBSS"
pk_cpu:    .res 1               ; il giocatore destro è la CPU
pk_fixed:  .res 1               ; lato che non sceglie (0, 1; $ff nessuno): la CPU, o il campione
                                ; di CHALLENGE quando entra uno sfidante
.segment "ZEROPAGE"
pk_cursor: .res 2
.segment "NEXTBSS"
pk_count:  .res 2               ; bonus presi
pk_chosen: .res 6               ; per giocatore 3 bonus nell'ordine in cui sono stati presi
pk_ok:     .res 2               ; racchetta confermata
pk_frames: .res 2               ; frame rimasti per scegliere
pk_ready:  .res 1               ; frame di READY! rimasti (0 = si sceglie ancora)
pk_secs:   .res 1               ; secondi a schermo ($ff = da disegnare)
.segment "ZEROPAGE"
pk_p:      .res 1               ; giocatore in esame
.segment "NEXTBSS"
.segment "ZEROPAGE"
pk_i:      .res 1               ; riga in disegno
.segment "NEXTBSS"
.segment "ZEROPAGE"
pk_dirty:  .res 1               ; colonne da ridisegnare
.segment "NEXTBSS"
pk_phase:  .res 1               ; lavori lunghi, un frame ciascuno: PH_*
cap_idx:   .res 1
hud_res:   .res 6               ; riserve disegnate in alto (B_NONE vuoto, $ff da disegnare)
hud_sel:   .res 2

.segment "CODE"

; ------------------------------------------------------------------------------------ dati

; bonus della scelta, nell'ordine di Bonus::PICKABLE
pickable:     .byte B_TELEPORT, B_SMASH, B_SLOW, B_CURVE, B_GHOST, B_STEER
PICKS = 6
; scelte predefinite quando scade il tempo (DEFAULT_PICK), poi nell'ordine della scelta
default_pick: .byte B_SMASH, B_TELEPORT, B_SLOW, B_TELEPORT, B_SMASH, B_SLOW, B_CURVE, B_GHOST, B_STEER
DEFAULTS = 9

bonus_names: .word s_teleport, s_smash, s_slow, s_curve, s_ghost, s_super, s_steer, s_bullet
s_teleport: .byte "TELEPORT", 0
s_smash:    .byte "SMASH   ", 0
s_slow:     .byte "SLOW    ", 0
s_curve:    .byte "CURVE   ", 0
s_ghost:    .byte "GHOST   ", 0
s_super:    .byte "SUPER   ", 0
s_steer:    .byte "STEER   ", 0
s_bullet:   .byte "BULLET  ", 0

kind_names: .word s_arcade, s_titan, s_hammer, s_twist, s_blaster, s_rush, s_guardian
s_arcade:   .byte "ARCADE  ", 0
s_titan:    .byte "TITAN   ", 0
s_hammer:   .byte "HAMMER  ", 0
s_twist:    .byte "TWIST   ", 0
s_blaster:  .byte "BLASTER ", 0
s_rush:     .byte "RUSH    ", 0
s_guardian: .byte "GUARDIAN", 0
; frase del tipo (paddle_ui::tagline), centrata sotto la colonna
kind_tags:  .word t_arcade, t_titan, t_hammer, t_twist, t_blaster, t_rush, t_guardian
t_arcade:   .byte "  MORE BONUSES  ", 0
t_titan:    .byte " TALL BUT SLOW  ", 0
t_hammer:   .byte "  POWER SHOTS   ", 0
t_twist:    .byte "TILTS WITH SPEED", 0
t_blaster:  .byte "SHOOTS CAPSULES ", 0
t_rush:     .byte "   LONG DASH    ", 0
t_guardian: .byte " FIVE-PIECE WALL", 0

cap_chars:  .byte CAP_CHARS
cap_empty:  .byte CAP_EMPTY
col_base:   .byte 0, 20             ; prima colonna della metà di ciascun giocatore

; ------------------------------------------------------------------------------------ scelta

; Inizio di NEXT dal menu: seme della partita, poi la scelta dei bonus.
.proc pick_enter
    jsr seed_from_time
    lda #0
    sta pk_cpu
    lda opt_players
    cmp #3
    bne :+
    inc pk_cpu
:   lda opt_players             ; CHALLENGE: anche la CPU
    cmp #OPT_CHALLENGE
    bne :+
    inc pk_cpu
:   ldx #$ff                    ; la CPU (a destra) non sceglie
    lda pk_cpu
    beq :+
    ldx #1
:   stx pk_fixed
    lda #0
    sta pk_kind
    sta pk_count
    sta pk_count+1
    jsr pick_start
    lda opt_players
    cmp #OPT_CHALLENGE
    bne :+
    ; CHALLENGE: a destra i bonus del primo avversario
    lda rung_loadout
    sta pk_chosen+3
    lda rung_loadout+1
    sta pk_chosen+4
    lda rung_loadout+2
    sta pk_chosen+5
    lda #3
    sta pk_count+1
    rts
:   ; la CPU sceglie tre bonus diversi a caso
    lda pk_cpu
    beq draw
    jsr rng_save
    mov32 rng, cfg_seed
    lda rng
    eor #<PICK_SEED_BONUS
    sta rng
    lda rng+1
    eor #>PICK_SEED_BONUS
    sta rng+1
    lda rng+2
    eor #<(PICK_SEED_BONUS >> 16)
    sta rng+2
    lda rng+3
    eor #<(PICK_SEED_BONUS >> 24)
    sta rng+3
    jsr rng_fix
cpu:
    lda #PICKS
    sta m_b
    lda #0
    sta m_b+1
    jsr rng_below
    tax
    lda pickable,x
    ldx #1
    jsr pick_has
    bcs cpu
    jsr pick_add
    lda pk_count+1
    cmp #3
    bne cpu
    jsr rng_restore
draw:
    rts
.endproc

; Scelta della racchetta, dopo quella dei bonus.
.proc kind_enter
    lda #1
    sta pk_kind
    lda #0
    sta pk_ok
    sta pk_ok+1
    jsr pick_start
    lda opt_players
    cmp #OPT_CHALLENGE
    bne :+
    lda cg_active
    cmp #CG_DUEL
    bne first
    ldx pk_fixed                ; nuovo sfidante: il campione tiene la sua racchetta
    lda ch_kinds,x
    sta pk_cursor,x
    lda #1
    sta pk_ok,x
    rts
first:
    lda rung_kind               ; CHALLENGE: la racchetta del primo avversario
    sta pk_cursor+1
    lda #1
    sta pk_ok+1
    rts
:   lda pk_cpu
    beq :+
    ; la CPU: un tipo a caso
    jsr rng_save
    lda cfg_seed
    eor #<PICK_SEED_KIND
    sta rng
    lda cfg_seed+1
    eor #>PICK_SEED_KIND
    sta rng+1
    lda cfg_seed+2
    eor #<(PICK_SEED_KIND >> 16)
    sta rng+2
    lda cfg_seed+3
    eor #<(PICK_SEED_KIND >> 24)
    sta rng+3
    jsr rng_fix
    lda #KINDS
    sta m_b
    lda #0
    sta m_b+1
    jsr rng_below
    sta pk_cursor+1
    lda #1
    sta pk_ok+1
    jsr rng_restore
:   rts
.endproc

; CHALLENGE, nuovo sfidante (Pick::challenger): sceglie solo lui, sul lato libero; il campione
; tiene i suoi bonus (e poi la sua racchetta, in kind_enter). Seme nuovo per la sfida.
.proc pick_challenger
    jsr seed_from_time
    lda #0
    sta pk_cpu
    sta pk_kind
    sta pk_count
    sta pk_count+1
    jsr pick_start
    lda ch_side
    lsr a
    lsr a
    sta pk_fixed
    tax
    lda #3
    sta pk_count,x
    ldx #5                      ; ch_load ha l'ordine di pk_chosen: 3 bonus per lato
:   lda ch_load,x
    sta pk_chosen,x
    dex
    bpl :-
    rts
.endproc

; Parte comune delle due scelte: scena, tempo, cursori, schermo vuoto senza sprite.
.proc pick_start
    lda #ST_PICK
    sta state
    lda #<PICK_FRAMES
    sta pk_frames
    lda #>PICK_FRAMES
    sta pk_frames+1
    lda #0
    sta pk_ready
    sta pk_cursor
    sta pk_cursor+1
    sta sh_enable
    sta sh_bg
    lda #$ff
    sta pk_secs
    lda #MODE_TEXT
    sta sh_mode
    lda #PH_CLEAR               ; schermo e scritte nei prossimi frame
    sta pk_phase
    rts
.endproc

; Generatore della partita da parte (le scelte della CPU usano un generatore proprio).
.proc rng_save
    mov32 cpu_saved_rng, rng
    rts
.endproc
.proc rng_restore
    mov32 rng, cpu_saved_rng
    rts
.endproc
; Rng::new: lo stato 0 diventa la costante
.proc rng_fix
    or32 rng
    bne :+
    mov32 rng, {#$2545F491}
:   rts
.endproc

; C = 1 se il giocatore X (0 o 1) ha già preso il bonus A.
.proc pick_has
    sta v_n
    txa
    asl a
    adc #0                      ; X * 3 = X * 2 + X (X <= 1)
    stx m_t
    clc
    adc m_t
    tay
    lda pk_count,x
    beq no
    sta m_t
:   lda pk_chosen,y
    cmp v_n
    beq yes
    iny
    dec m_t
    bne :-
no:
    lda v_n
    clc
    rts
yes:
    lda v_n
    sec
    rts
.endproc

; Aggiunge il bonus A ai presi dal giocatore X (ce n'è posto).
.proc pick_add
    pha
    txa
    asl a
    stx m_t
    clc
    adc m_t                     ; X * 3
    clc
    adc pk_count,x
    tay
    pla
    sta pk_chosen,y
    inc pk_count,x
    rts
.endproc

; Toglie il bonus A dai presi dal giocatore X (c'è), compattando gli altri.
.proc pick_remove
    sta v_n
    txa
    asl a
    stx m_t
    clc
    adc m_t
    tay                         ; Y = primo posto del giocatore
    sty m_lo
    lda pk_count,x
    clc
    adc m_lo
    sta m_lo                    ; fine
find:
    lda pk_chosen,y
    cmp v_n
    beq shift
    iny
    jmp find
shift:
    iny
    cpy m_lo
    beq done
    lda pk_chosen,y
    sta pk_chosen-1,y
    jmp shift
done:
    dec pk_count,x
    rts
.endproc

; Un frame della scelta (bonus o racchetta).
.proc pick_scene
    lda #KEY_STOP
    jsr key_pressed
    bcc :+
    jsr ef_pick                 ; (C = 1) i caratteri di prima
    jmp enter_menu
:   lda pk_phase
    beq ready
    cmp #PH_CHARS
    beq chars
    cmp #PH_DRAW
    beq draw
    bcs match
    ; schermo pulito
    lda #PH_CHARS
    sta pk_phase
    lda #COL_WHITE
    jmp clear_text
chars:
    ; sullo schermo vuoto: nella scelta dei bonus le metà delle lettere (put_low), in quella della
    ; racchetta di nuovo i caratteri di prima
    lda #PH_DRAW
    sta pk_phase
    lda pk_kind                 ; C = 0 i caratteri della scelta dei bonus, C = 1 quelli di prima
    cmp #1
    jmp ef_pick
draw:
    lda #PH_NONE
    sta pk_phase
    jmp pick_draw
match:
    lda #PH_NONE
    sta pk_phase
    jmp start_next
ready:
    lda pk_ready
    beq choosing
    ; READY!: lampeggia, poi si va avanti. Negli ultimi frame, leggeri, il codice delle mosse
    ; speciali dalla cartuccia, una pagina per frame (sm_page)
    dec pk_ready
    beq go
    lda pk_ready
    cmp #SM_PAGES + 1
    bcs :+
    sbc #0                      ; (C = 0) pagina pk_ready - 1
    jsr sm_page
:   jsr draw_ready
    lda pk_dirty
    beq :+
    jmp draw_columns
:   rts
go:
    lda pk_kind
    bne :+
    jmp kind_enter
:   ; la partita al prossimo frame, con lo schermo già pulito ora
    lda #PH_MATCH
    sta pk_phase
    lda #COL_WHITE
    jmp clear_text
choosing:
    ; tempo
    lda pk_frames
    bne :+
    dec pk_frames+1
:   dec pk_frames
    jsr draw_secs
    lda pk_fixed                ; chi non sceglie (la CPU o il campione) non ha comandi
    beq :+
    ldx #0
    jsr pick_player
:   lda pk_fixed
    cmp #1
    beq :+
    ldx #1
    jsr pick_player
:   ; fine: tutti hanno scelto o il tempo è scaduto
    lda pk_frames
    ora pk_frames+1
    beq finish
    lda pk_kind
    bne kinds
    lda pk_count
    and pk_count+1
    cmp #3
    bne redraw
    beq finish
kinds:
    lda pk_ok
    and pk_ok+1
    beq redraw
finish:
    lda pk_kind
    bne :+
    jsr fill_defaults
    jmp :++
:   lda #1
    sta pk_ok
    sta pk_ok+1
:   lda #READY_FRAMES
    sta pk_ready
    lda #EV_BOOST
    jsr sid_fx
    lda #3
    sta pk_dirty
redraw:
    lda pk_dirty
    beq :+
    jsr draw_columns
:   rts
.endproc

; Comandi del giocatore X nella scelta.
.proc pick_player
    stx pk_p
    ; scelta dei bonus finita: solo il fuoco (per lasciarne uno)
    lda pk_kind
    bne :+
    lda pk_count,x
    cmp #3
    beq fire
    jmp move
:   lda pk_ok,x
    bne fire
move:
    lda ctl_paddle
    beq joystick
    ; paddle: la rotazione sceglie la riga
    ldy #PICKS
    lda pk_kind
    beq :+
    ldy #KINDS
:   lda pot_raw,x
    jsr umul8                   ; m_t = pot * righe / 256
    ldx pk_p
    lda m_t
    cmp pk_cursor,x
    beq fire
    sta pk_cursor,x
    jmp moved
joystick:
    lda joy_edge,x
    and #JOY_UP
    beq down
    dec pk_cursor,x
    bpl moved
    jsr rows
    sec
    sbc #1
    sta pk_cursor,x
    jmp moved
down:
    lda joy_edge,x
    and #JOY_DOWN
    beq fire
    inc pk_cursor,x
    jsr rows
    cmp pk_cursor,x
    bne moved
    lda #0
    sta pk_cursor,x
moved:
    lda pk_bit,x
    ora pk_dirty
    sta pk_dirty
fire:
    ldx pk_p
    lda fire_edge,x
    beq done
    lda pk_kind
    bne kind
    ; prende o lascia il bonus sotto il cursore
    ldy pk_cursor,x
    lda pickable,y
    jsr pick_has
    bcc take
    jsr pick_remove
    lda #EV_WALL
    jmp sound
take:
    ldy pk_count,x
    cpy #3
    beq done
    jsr pick_add
    lda #EV_HIT
    jmp sound
kind:
    lda pk_ok,x
    eor #1
    sta pk_ok,x
    lda #EV_WALL
    ldy pk_ok,x
    beq sound
    lda #EV_HIT
sound:
    jsr sid_fx
    ldx pk_p
    lda pk_bit,x
    ora pk_dirty
    sta pk_dirty
done:
    rts
rows:
    lda #PICKS
    ldy pk_kind
    beq :+
    lda #KINDS
:   rts
.endproc

pk_bit: .byte 1, 2

; Tempo scaduto: i bonus mancanti dalle scelte predefinite, poi nell'ordine della scelta.
.proc fill_defaults
    ldx #0
player:
    ldy #0
next:
    lda pk_count,x
    cmp #3
    beq done
    sty pk_i
    lda default_pick,y
    jsr pick_has
    bcs :+
    jsr pick_add
:   ldy pk_i
    iny
    cpy #DEFAULTS
    bne next
done:
    inx
    cpx #2
    bne player
    rts
.endproc

; La partita NEXT: bonus e racchette scelti, poi come le altre (start_game senza nuovo seme).
.proc start_next
    lda opt_players             ; CHALLENGE: prima la presentazione dell'avversario
    cmp #OPT_CHALLENGE
    bne :+
    lda cg_active               ; o la sfida con il nuovo sfidante
    cmp #CG_DUEL
    beq duel
    jmp ch_start
duel:
    jsr ch_duel_prep
:   lda #1
    sta cfg_next
    ldx #0
    ldy #0
:   lda pk_chosen,y
    sta cfg_loadout,x
    lda pk_chosen+3,y
    sta cfg_loadout+4,x
    inx
    iny
    cpy #3
    bne :-
    lda pk_cursor
    sta cfg_kinds
    lda pk_cursor+1
    sta cfg_kinds+4
    lda #1                      ; schermo già pulito (pick_scene)
    sta screen_clear
    jmp begin_match
.endproc

; ------------------------------------------------------------------------------------ disegno

; Tutto lo schermo della scelta.
.proc pick_draw
    lda pk_kind
    bne :+
    jsr print_at
    .byte 13, 0, "PICK 3 BONUSES", 0
    jmp :++
:   jsr print_at
    .byte 12, 0, "PICK YOUR PADDLE", 0
:   lda #COL_YELLOW
    ldx #0
    ldy #0
    jsr color_row
    ; mezzeria sotto il tempo
    lda #6
    sta v_row
:   jsr center_line_row
    inc v_row
    lda v_row
    cmp #PICK_HINT
    bne :-
    ; comandi
    lda #COL_GRAY
    ldx #0
    ldy #PICK_HINT
    jsr color_row
    ; comandi sotto la colonna di chi sceglie
    lda pk_fixed
    bpl :+
    jsr print_at
    .byte 4, PICK_HINT, "UP DOWN + FIRE      UP DOWN + FIRE", 0
    jmp hint_done
:   bne :+
    jsr print_at
    .byte 24, PICK_HINT, "UP DOWN + FIRE", 0
    jmp hint_done
:   jsr print_at
    .byte 4, PICK_HINT, "UP DOWN + FIRE", 0
hint_done:
    lda #3                      ; le colonne nei frame dopo, una per frame
    sta pk_dirty
    rts
.endproc

; Secondi rimasti (cifre del punteggio, al centro) quando cambiano.
.proc draw_secs
    ; secondi = ceil(frame / 50)
    lda pk_frames
    sta m_lo
    lda pk_frames+1
    sta m_t
    ldx #0
:   lda m_t
    bne sub
    lda m_lo
    beq got
sub:
    inx
    lda m_lo
    sec
    sbc #50
    sta m_lo
    lda m_t
    sbc #0
    sta m_t
    bcs :-
    ; sotto zero: era l'ultimo pezzo di secondo
got:
    cpx pk_secs
    beq done
    stx pk_secs
    txa
    ldx #17
    ldy #2
    jmp draw_score2
done:
    rts
.endproc

; READY! in basso al centro, a tratti (6 volte al secondo, come sul PC).
.proc draw_ready
    lda pk_ready
    and #8
    beq off
    lda #COL_YELLOW
    ldx #0
    ldy #PICK_HINT
    jsr color_row
    jsr print_at
    .byte 4, PICK_HINT, "             READY!               ", 0
    rts
off:
    jsr print_at
    .byte 4, PICK_HINT, "                                  ", 0
    rts
.endproc

; Una delle colonne segnate in pk_dirty (bit 0 sinistro, bit 1 destro): ridisegnarle tutte e due
; nello stesso frame non ci sta nel budget, l'altra va al frame dopo.
.proc draw_columns
    ldx #0
    lda pk_dirty
    and #1
    bne :+
    inx
:   stx pk_p
    lda pk_dirty
    and pk_bit,x
    beq :+
    eor #$ff
    and pk_dirty
    sta pk_dirty
    jmp draw_column
:   rts
.endproc

; Colonna del giocatore pk_p: intestazione e righe.
.proc draw_column
    ldx pk_p
    ; intestazione: P1, P2 o CPU e, per i bonus, quanti su 3 (per la racchetta OK se confermata)
    lda col_base,x
    clc
    adc #2
    tax
    lda pk_p
    beq p1
    lda pk_cpu
    beq p2
    lda #<s_cpu_h
    ldy #>s_cpu_h
    jmp head
p1: lda #<s_p1
    ldy #>s_p1
    jmp head
p2: lda #<s_p2
    ldy #>s_p2
head:
    sta ptr2
    sty ptr2+1
    ldy #6
    jsr print_str
    ldx pk_p
    lda col_base,x
    clc
    adc #13
    tax
    lda pk_kind
    bne ok
    ldy pk_p
    lda pk_count,y
    clc
    adc #'0'
    ldy #6
    sty v_row
    jsr put_ascii
    inx
    lda #'/'
    ldy #6
    jsr put_ascii
    inx
    lda #'3'
    ldy #6
    jsr put_ascii
    ; bianco con 3 bonus, grigio prima
    ldy pk_p
    lda #COL_GRAY
    ldx pk_count,y
    cpx #3
    bne :+
    lda #COL_WHITE
:   ldx pk_p
    ldy col_base,x
    ldx #20
    jsr color_span_row6
    jmp rows
ok:
    ldy pk_p
    lda pk_ok,y
    beq :+
    lda #'O'
    ldy #6
    sty v_row
    jsr put_ascii
    inx
    lda #'K'
    ldy #6
    jsr put_ascii
    lda #COL_YELLOW
    jmp :++
:   lda #' '
    ldy #6
    sty v_row
    jsr put_ascii
    inx
    lda #' '
    ldy #6
    jsr put_ascii
    lda #COL_WHITE
:   ldx pk_p
    ldy col_base,x
    ldx #20
    jsr color_span_row6
rows:
    lda #0
    sta pk_i
row:
    jsr draw_row
    inc pk_i
    jsr rows_count
    cmp pk_i
    bne row
    ; racchetta: la frase del tipo sotto il cursore
    lda pk_kind
    beq done
    ldx pk_p
    ldy pk_cursor,x
    tya
    asl a
    tay
    lda kind_tags,y
    sta ptr2
    lda kind_tags+1,y
    sta ptr2+1
    lda col_base,x
    clc
    adc #2
    tax
    ldy #PICK_ROW0 + 2 * KINDS
    jsr print_str
    lda #COL_GRAY
    ldx pk_p
    ldy col_base,x
    ldx #20
    stx v_n
    ldx #PICK_ROW0 + 2 * KINDS
    jmp color_span
done:
    rts
rows_count:
    lda #PICKS
    ldy pk_kind
    beq :+
    lda #KINDS
:   rts
.endproc

s_p1:    .byte "P1 ", 0
s_p2:    .byte "P2 ", 0
s_cpu_h: .byte "CPU", 0

; Riga pk_i della colonna pk_p: cursore, capsula (bonus) e nome, nei colori della scelta.
.proc draw_row
    lda pk_i
    asl a
    adc #PICK_ROW0
    sta v_row
    ; acceso: preso (o confermato) o sotto il cursore
    ldx pk_p
    lda #0
    sta m_t                     ; preso
    lda pk_kind
    bne kind
    ldy pk_i
    lda pickable,y
    jsr pick_has
    lda #0                      ; preso = C (pick_has usa m_t: con 0 bonus del destro vi lascia 1)
    rol a
    sta m_t
    jmp cursor
kind:
    lda pk_ok,x
    beq cursor
    lda pk_i
    cmp pk_cursor,x
    bne cursor
    inc m_t
cursor:
    ; cursore: sotto il cursore, finché si sceglie (non per la CPU)
    lda #' '
    sta m_lo
    lda pk_i
    cmp pk_cursor,x
    bne :+
    lda pk_ready
    bne :+
    lda pk_p
    cmp pk_fixed
    beq :+
    lda pk_kind
    bne :+
    ldy pk_p
    lda pk_count,y
    cmp #3
    beq :+
    lda #'>'
    sta m_lo
:   lda pk_kind
    beq :+
    ; racchetta: il cursore finché non è confermata
    lda pk_i
    cmp pk_cursor,x
    bne :+
    lda pk_ok,x
    bne :+
    lda pk_ready
    bne :+
    lda #'>'
    sta m_lo
:   lda col_base,x
    clc
    adc #2
    tax
    lda m_lo
    jsr put_pick
    ; colore della riga: bonus presi e quello sotto il cursore bianchi, gli altri grigi; per la
    ; racchetta bianca quella sotto il cursore, gialla se confermata
    ldx pk_p
    lda pk_kind
    bne kcolor
    lda m_t
    bne white
    lda m_lo
    cmp #'>'
    beq white
gray:
    lda #COL_GRAY
    bne color
kcolor:
    lda pk_i
    cmp pk_cursor,x
    bne gray
    lda m_t
    beq white
    lda #COL_YELLOW
    bne color
white:
    lda #COL_WHITE
color:
    sta m_b
    ldy col_base,x
    ldx #20
    stx v_n
    ldx v_row
    jsr color_span
    ; scelta dei bonus: la riga sotto (metà basse della capsula e delle lettere) dello stesso colore
    lda pk_kind
    bne :+
    ldx pk_p
    ldy col_base,x
    lda #20
    sta v_n
    ldx v_row
    inx
    lda m_b
    jsr color_span
:
    ; il cursore in giallo (nella scelta dei bonus anche la metà sotto)
    lda m_lo
    cmp #'>'
    bne :+
    ldx v_row
    jsr cursor_yellow
    lda pk_kind
    bne :+
    ldx v_row
    inx
    jsr cursor_yellow
:   lda pk_kind
    bne name_kind
    ; capsula 2x2 (in negativo se presa) e nome del bonus
    ldy pk_i
    lda pickable,y
    sta m_b+1
    asl a
    asl a
    asl a
    ldy m_t
    beq :+
    ora #4
:   tay
    ldx pk_p
    lda col_base,x
    clc
    adc #4
    tax
    jsr put_cap
    ldx pk_p
    lda col_base,x
    clc
    adc #7
    tax
    lda m_b+1
    asl a
    tay
    lda bonus_names,y
    sta ptr2
    lda bonus_names+1,y
    sta ptr2+1
    jmp print_low
name_kind:
    ldx pk_p
    lda col_base,x
    clc
    adc #4
    tax
    lda pk_i
    asl a
    tay
    lda kind_names,y
    sta ptr2
    lda kind_names+1,y
    sta ptr2+1
    ldy v_row
    jmp print_str
.endproc

; Cursore della riga X in giallo.
.proc cursor_yellow
    ldy pk_p
    lda col_base,y
    clc
    adc #2
    tay
    lda #1
    sta v_n
    lda #COL_YELLOW
    jmp color_span
.endproc

; La capsula (2x2 caratteri) ha il centro tra due righe: nella scelta dei bonus il nome e il
; cursore accanto si abbassano di 4 pixel, con le metà delle lettere che ef_pick mette al posto
; delle scritte grandi (pick_start): la metà alta nella riga v_row, la bassa in quella sotto.

; Carattere ASCII A alla colonna X, riga v_row: nella scelta dei bonus abbassato (put_low).
.proc put_pick
    ldy pk_kind
    beq put_low
    ldy v_row
    jmp put_ascii
.endproc

; Stringa ASCII in (ptr2), abbassata, dalla colonna X alla riga v_row. Gli spazi si saltano: il
; nome di una riga è sempre lo stesso, le sue celle vuote restano quelle di clear_text.
.proc print_low
    ldy v_row
    txa
    clc
    adc row_lo,y
    sta top+1
    lda row_hi,y
    adc #0
    sta top+2
    lda top+1
    adc #40                     ; (C = 0)
    sta bottom+1
    lda top+2
    adc #0
    sta bottom+2
    ldy #0
loop:
    lda (ptr2),y
    beq done
    tax
    lda font_map - 32,x
    beq next
    clc
    adc #PICK_TOP
top:
    sta $ffff,y
    adc #PICK_BOTTOM - PICK_TOP
bottom:
    sta $ffff,y
next:
    iny
    bne loop
done:
    rts
.endproc

; Carattere ASCII A abbassato alla colonna X (resta), riga v_row; lo spazio è vuoto in tutte e due.
.proc put_low
    sec
    sbc #32
    tay
    lda font_map,y
    beq :+
    adc #PICK_TOP - 1           ; (C = 1 dalla sottrazione)
:   pha
    ldy v_row
    jsr put_char
    pla
    beq :+
    clc
    adc #PICK_BOTTOM - PICK_TOP
:   ldy v_row
    iny
    jmp put_char
.endproc

; Capsula 2x2: caratteri cap_chars da Y (4 di fila) con l'angolo in alto a sinistra alla
; colonna X, riga v_row.
.proc put_cap
    sty cap_idx
    stx v_col
    ldy v_row
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    ldx cap_idx
    ldy v_col
    lda cap_chars,x
    sta (ptr),y
    iny
    lda cap_chars+1,x
    sta (ptr),y
    tya
    clc
    adc #39
    tay
    lda cap_chars+2,x
    sta (ptr),y
    iny
    lda cap_chars+3,x
    sta (ptr),y
    rts
.endproc

; Colore A per v_n celle dalla colonna Y della riga X. Con l'easter egg (egg_check) giallo e rosso
; si scambiano qui, per tutte le scritte.
color_span:
    cmp #COL_RED
    beq :+
    cmp #COL_YELLOW
    bne color_span_raw
:   eor egg_x
; Lo stesso con il colore già scambiato (egg_yel, egg_red): i titoli di coda del finale, che
; scrivono i colori davanti al raster.
.proc color_span_raw
    pha
    lda row_lo,x
    sta ptr
    lda row_hi,x
    clc
    adc #>($d800 - SCREEN)
    sta ptr+1
    pla
    ldx v_n
:   sta (ptr),y
    iny
    dex
    bne :-
    rts
.endproc

; Colore A per X celle dalla colonna Y della riga 6 (intestazione).
.proc color_span_row6
    stx v_n
    ldx #6
    jmp color_span
.endproc

; Colore A per tutta la riga Y (X ignorato).
.proc color_row
    pha
    lda #40
    sta v_n
    tya
    tax
    ldy #0
    pla
    jmp color_span
.endproc

; ------------------------------------------------------------------------------------ partita

; Riserve in alto (come il MiSTer): tre posti per lato dal bordo, la capsula del selezionato in
; negativo con una freccetta sotto, il SUPER in giallo, i posti vuoti a puntini. Si ridisegna solo
; quello che cambia.
.proc next_hud
    lda m_next
    bne :+
    rts
:   jsr sm_hud                  ; mosse speciali: barre, colori, scritta e suoni
    bit $fffb                  ; con la voce di CHALLENGE (READY?, gli NMI costano circa 5.100
    bmi :+                      ; cicli per frame) le immagini aspettano che finisca
    jsr fx_copy                 ; effetti della palla a $E000, una pagina per frame
    lda fx_wait
    bne :+
    jsr pad_prep                ; e le immagini delle racchette, una per frame
    lda pp_side
    cmp #2
    bcc :+
    jsr spin_prep               ; poi quelle della rotazione del SUPER
:   ; riserve e selezioni come a schermo (quasi tutti i frame): solo le barriere
    ldx #2
:   lda nx_res,x
    cmp hud_res,x
    bne changed
    lda nx_res+4,x
    cmp hud_res+3,x
    bne changed
    dex
    bpl :-
    lda nx_sel
    cmp hud_sel
    bne changed
    lda nx_sel+4
    cmp hud_sel+1
    bne changed
    jmp draw_barrier
changed:
    ldx #0                      ; giocatore
player:
    stx pk_p
    txa
    asl a
    asl a
    tay                         ; Y = giocatore * 4
    lda nx_sel,y
    cmp hud_sel,x
    beq slots
    ; selezione cambiata: il posto lasciato e quello nuovo (all'inizio tutti e tre)
    pha
    txa
    asl a
    adc pk_p                    ; giocatore * 3
    sta m_lo
    lda hud_sel,x
    cmp #3
    bcc :+
    ldy m_lo                    ; nessuna selezione disegnata: tutti
    lda #$ff
    sta hud_res,y
    sta hud_res+1,y
    sta hud_res+2,y
    jmp :++
:   clc
    adc m_lo
    tay
    lda #$ff
    sta hud_res,y
:   pla
    sta hud_sel,x
    clc
    adc m_lo
    tay
    lda #$ff
    sta hud_res,y
slots:
    lda #0
    sta pk_i
slot:
    ; bonus del posto e disegnato
    lda pk_p
    asl a
    asl a
    clc
    adc pk_i
    tay
    lda nx_res,y
    sta m_t
    lda pk_p
    asl a
    adc pk_p
    clc
    adc pk_i
    tay
    lda m_t
    cmp hud_res,y
    beq :+
    sty m_lo
    jsr frame_late_small        ; frame già avanti: il posto al prossimo
    bcs :+
    ldy m_lo
    lda m_t
    sta hud_res,y
    jsr hud_slot
:   inc pk_i
    lda pk_i
    cmp #3
    bne slot
    ldx pk_p
    inx
    cpx #2
    jne player
    jmp draw_barrier
.endproc

; Posto pk_i della riserva di pk_p con il bonus m_t (B_NONE vuoto).
.proc hud_slot
    ; colonna: a sinistra 2 * posto, a destra 38 - 2 * posto
    lda pk_i
    asl a
    ldx pk_p
    beq :+
    eor #$ff
    sec
    adc #38
:   sta v_col
    lda #0
    sta v_row
    ; selezionato?
    lda #0
    sta m_lo
    ldy hud_sel,x
    cpy pk_i
    bne :+
    lda m_t
    cmp #B_NONE
    beq :+
    inc m_lo
:   lda m_t
    cmp #B_NONE
    bne cap
    ; vuoto: bordo a puntini grigio
    ldy #0
:   lda cap_empty,y
    sta empty_tmp,y
    iny
    cpy #4
    bne :-
    lda #COL_GRAY
    sta m_b
    jsr put_empty
    jmp arrow
cap:
    asl a
    asl a
    asl a
    ldy m_lo
    beq :+
    ora #4
:   tay
    ldx v_col
    jsr put_cap
    lda #COL_WHITE
    ldy m_t
    cpy #B_SUPER
    beq :+
    cpy #B_BULLET
    bne :++
:   lda #COL_YELLOW                ; le capsule rare
:   sta m_b
arrow:
    ; colori della capsula
    ldx #0
    jsr hud_color
    ldx #1
    jsr hud_color
    ; freccetta sotto il selezionato
    ldy #2
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    ldy v_col
    lda #CH_BLANK
    ldx m_lo
    beq :+
    lda #CH_ARROW_L
:   sta (ptr),y
    iny
    lda #CH_BLANK
    cpx #0
    beq :+
    lda #CH_ARROW_R
:   sta (ptr),y
    lda #COL_YELLOW
    sta m_b
    ldx #2
    jmp hud_color
.endproc

empty_tmp = m_p                 ; quattro caratteri del posto vuoto (m_p non serve qui)

; Posto vuoto alla colonna v_col, righe 0-1.
.proc put_empty
    ldy #0
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    ldy v_col
    lda empty_tmp
    sta (ptr),y
    iny
    lda empty_tmp+1
    sta (ptr),y
    tya
    clc
    adc #39
    tay
    lda empty_tmp+2
    sta (ptr),y
    iny
    lda empty_tmp+3
    sta (ptr),y
    rts
.endproc

; Colore m_b per le due celle del posto (colonna v_col) nella riga X.
.proc hud_color
    lda #2
    sta v_n
    ldy v_col
    lda m_b
    jmp color_span
.endproc

; Riserve da ridisegnare tutte (schermo della partita nuovo).
.proc hud_reset
    lda #$ff
    ldx #5
:   sta hud_res,x
    dex
    bpl :-
    sta hud_sel
    sta hud_sel+1
    jsr ch_hud_reset            ; CHALLENGE: punti da ridisegnare
    lda #0
    sta bar_shown               ; schermo vuoto: muri tutti da disegnare
    sta bar_shown+1
    sta bar_prev
    sta bar_prev+1
    sta bar_flash
    sta bar_flash+1
    sta sv_n                    ; nessun colpo a schermo
    sta lb_frames               ; nessuna scritta, nessun segno di STEER
    sta lb_pend
    sta st_drawn
    sta bl_on                   ; schermo nuovo: mezzeria e punteggi bianchi
    sta lb_prev
    sta lb_prev+1
    sta fx_pages                ; immagini degli effetti da copiare (la bitmap è cambiata)
    sta tr_ready                ; e la coda da ridisegnare
    sta pp_side                 ; e le immagini delle racchette
    sta wp_on                   ; nessun salto del TELEPORT in corso
    sta sp_k
    sta pp_var
    sta pp_ready
    sta pp_ready+1
    lda #2
    sta fx_wait
    rts
.endproc

; ------------------------------------------------------------------------------------ GUARDIAN

; Muro tratteggiato dietro la racchetta del GUARDIAN, sotto le riserve (righe BAR_ROW0-24): i
; settori (G_SECTORS) di colore alterno (giallo e arancione), disegnati solo quelli ancora in piedi; quello
; che rimanda la palla lampeggia per BAR_FLASH frame e sparisce. I settori non sono allineati ai
; caratteri: ogni riga di caratteri prende il settore del suo centro con la regola della logica
; (g_sector, sulla y del core che va verso l'alto), quindi il disegno è approssimato al carattere
; e la logica no. Si riscrivono solo le righe dei settori cambiati.
BAR_ROW0   = 3
BAR_FLASH  = 15                 ; frame del lampeggio (0,3 s)
.assert P_BARRIER_X = 8 << 16, error, "caratteri della barriera fatti per x = 8 (gen_c64_assets.py)"
; (P_GUARDIAN_TOP è la y del core dell'estremo alto del muro: a schermo P_HEIGHT - P_GUARDIAN_TOP)
.assert (BAR_ROW0 - 1) * 8 < (P_HEIGHT - P_GUARDIAN_TOP) >> 16 .and BAR_ROW0 * 8 >= (P_HEIGHT - P_GUARDIAN_TOP) >> 16, error, "muro del GUARDIAN: prima riga sotto la banda delle riserve"

.proc draw_barrier
    ldx #0
side_loop:
    stx pk_p
    txa
    asl a
    asl a
    tay                         ; Y = lato * 4
    lda nx_kind,y
    cmp #K_GUARDIAN
    jne next_side
    ; settori appena caduti (rimandano la palla): lampeggiano
    lda nx_barrier,y
    sta m_t                     ; settori da mostrare
    eor #$ff
    and bar_prev,x
    beq :+
    sta bar_fbit,x
    lda #BAR_FLASH
    sta bar_flash,x
:   lda m_t
    sta bar_prev,x
    lda bar_flash,x
    beq :+
    dec bar_flash,x
    lda tick
    and #2
    beq :+
    lda m_t
    ora bar_fbit,x
    sta m_t
:   lda m_t
    eor bar_shown,x
    beq next_side               ; a schermo è già così
    sta m_b                     ; settori da ridisegnare
    jsr frame_late_small        ; frame già avanti: al prossimo
    bcs next_side
    jsr shots_erase             ; i colpi non devono rimettere i caratteri di prima
    ldx pk_p
    lda m_t
    sta bar_shown,x
    lda bar_cols,x
    sta v_col
    lda #BAR_ROW0
    sta v_row
    lda #<((P_HEIGHT >> 16) - BAR_ROW0 * 8 - 4)
    sta v_n                     ; y del centro della riga nel core
row:
    lda v_n
    jsr g_sector
    bit m_b
    beq skip                    ; settore non cambiato
    sta m_lo
    ldy v_row
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    ldy v_col
    lda m_lo
    and m_t
    beq blank
    lda #CH_BAR_R
    sta (ptr),y
    iny
    lda #CH_BAR_L
    sta (ptr),y
    lda ptr+1
    clc
    adc #>($d800 - SCREEN)
    sta ptr+1
    ldx #COL_ORANGE             ; settori dispari arancioni, pari gialli
    lda m_lo
    and #%010101
    beq :+
    ldx egg_yel
:   txa
    sta (ptr),y
    dey
    sta (ptr),y
    bcc skip                    ; (C = 0 dall'adc qui sopra)
blank:
    lda #CH_BLANK
    sta (ptr),y
    iny
    sta (ptr),y
skip:
    lda v_n
    sec
    sbc #8
    sta v_n
    inc v_row
    lda v_row
    cmp #25
    bne row
next_side:
    ldx pk_p
    inx
    cpx #2
    jne side_loop
    rts
.endproc

bar_cols: .byte 0, 38           ; colonne della barriera (pixel 7-8 e 311-312)

; ------------------------------------------------------------------------------------ BLASTER

; Colpi del BLASTER: due tratti gialli di 7 pixel, 2 sopra e 2 sotto la riga del colpo, come sul
; MiSTer; in caratteri (gli sprite sono finiti), a passi di 2 pixel e sulla riga di caratteri più
; vicina. Si disegnano a inizio frame, nel vblank, rimettendo prima quello che c'era sotto quelli
; del frame prima. Chi scrive sul campo cancella prima i colpi (shots_erase).
SHOT_MAX_CELLS = 4 * MAX_SHOTS   ; fino a due celle per colpo, tutti e due i giocatori

.proc next_shots
    ; fuori dalla partita lo schermo è già un altro: i colpi si dimenticano
    lda state
    cmp #ST_COUNT
    jcc leave
    cmp #ST_OVER + 1
    jcs leave
    jsr shots_erase
    lda m_next
    jeq done
    lda state
    cmp #ST_COUNT
    bcc done
    cmp #ST_OVER + 1
    bcs done
    ldy #0
shot:
    lda shot_on,y
    jeq next
    sty ns_k
    tya
    asl a
    asl a
    tax                         ; X = posto * 4
    ; riga: (200 - y - 3) / 8, solo sotto le riserve e i punteggi
    lda #<((P_HEIGHT >> 16) - 3)
    sec
    sbc shot_y+2,x
    jcc skip
    lsr a
    lsr a
    lsr a
    cmp #4
    jcc skip
    cmp #25
    jcs skip
    sta v_row
    ; colonna e fase: x0 = int(x) - 3, colonna x0 / 8, fase x0 & 6
    lda shot_x+2,x
    sec
    sbc #3
    sta v_n
    lda shot_x+3,x
    sbc #0
    jmi skip
    lsr a                       ; bit 8 di x0 nel carry
    lda v_n
    ror a
    lsr a
    lsr a
    sta v_col
    cmp #40
    jcs skip
    lda v_n
    and #6
    sta m_t                     ; fase * 2 = indice in shot_chars
    tax
    lda shot_chars,x
    jsr shot_cell
    ldx m_t
    lda shot_chars+1,x
    beq skip                    ; fase 0: tutto nel primo carattere
    inc v_col
    lda v_col
    cmp #40
    bcs skip
    lda shot_chars+1,x
    jsr shot_cell
skip:
    ldy ns_k
next:
    iny
    cpy #2 * MAX_SHOTS
    jne shot
done:
    rts
leave:
    lda #0
    sta sv_n
    rts
.endproc

shot_chars: .byte SHOT_CHARS

; Carattere A del colpo, giallo, alla colonna v_col della riga v_row, salvando quello che c'è.
.proc shot_cell
    sta m_lo
    ldx sv_n
    cpx #SHOT_MAX_CELLS
    bcs full
    ldy v_row
    lda row_lo,y
    clc
    adc v_col
    sta ptr
    sta sv_lo,x
    lda row_hi,y
    adc #0
    sta ptr+1
    sta sv_hi,x
    ldy #0
    lda (ptr),y
    sta sv_ch,x
    lda m_lo
    sta (ptr),y
    lda ptr+1
    clc
    adc #>($d800 - SCREEN)
    sta ptr+1
    lda (ptr),y
    and #$0f                    ; il nibble alto della RAM del colore non esiste
    sta sv_col,x
    lda egg_yel
    sta (ptr),y
    inc sv_n
full:
    rts
.endproc

; Toglie i colpi disegnati, rimettendo caratteri e colori (dall'ultimo, se si sovrappongono).
.proc shots_erase
    ldx sv_n
    beq done
:   dex
    lda sv_lo,x
    sta ptr
    lda sv_hi,x
    sta ptr+1
    ldy #0
    lda sv_ch,x
    sta (ptr),y
    lda ptr+1
    clc
    adc #>($d800 - SCREEN)
    sta ptr+1
    lda sv_col,x
    sta (ptr),y
    txa
    bne :-
    stx sv_n
done:
    rts
.endproc

.segment "NEXTBSS"
bar_shown: .res 2               ; settori del muro a schermo
bar_prev:  .res 2               ; settori in piedi al frame prima
bar_flash: .res 2               ; frame di lampeggio rimasti
bar_fbit:  .res 2               ; e settore che lampeggia
sv_n:      .res 1               ; celle dei colpi a schermo
sv_lo:     .res SHOT_MAX_CELLS
sv_hi:     .res SHOT_MAX_CELLS
sv_ch:     .res SHOT_MAX_CELLS
sv_col:    .res SHOT_MAX_CELLS
.segment "CODE"

; ------------------------------------------------------------------------------------ effetti

LABEL_ROW    = 23               ; scritta del bonus attivato, in basso
LABEL_FRAMES = 60               ; 1,2 secondi

; Dopo il tick della partita: scritta "P1 SMASH!" del bonus attivato (chi ha una capsula in meno
; nella riserva; il bonus è quello armato, o SLOW e BULLET che non restano armati: il BULLET si
; riconosce da chi lo ha da questo tick, come sul PC), segni di STEER in cima e in fondo dove
; finisce la guida e i colori del bullet time.
.proc next_fx_scene
    lda m_next
    bne :+
    rts
:   jsr bullet_look
    lda events
    and #EV_ACTIVATE
    beq timer
    ldx #0
    jsr res_count
    ldy #0
    cmp lb_prev
    bcc :+
    ldy #4
:   lda #B_BULLET
    ldx nx_bside
    cpx lb_bprev
    beq :+
    cpy nx_bside
    beq bonus
:   lda nx_armed,y
    cmp #B_NONE
    bne bonus
    lda #B_SLOW
bonus:
    pha                         ; bonus e giocatore
    tya
    pha
    lda lb_frames
    beq :+
    jsr label_erase             ; la scritta di prima
    lda #0
    sta lb_frames
:   pla
    sta lb_player
    pla
    sta lb_bonus
    lda #1                      ; da disegnare appena il frame ha tempo
    sta lb_pend
timer:
    lda lb_pend
    beq :+
    jsr frame_late              ; prima ci sono ancora sprite, riserve e SID
    bcs counts
    lda #0
    sta lb_pend
    jsr label_draw
    lda #LABEL_FRAMES
    sta lb_frames
    jmp counts
:   lda lb_frames
    beq counts
    dec lb_frames
    bne counts
    jsr label_erase
counts:
    ; riserve dopo il tick, per il confronto del prossimo
    ldx #0
    jsr res_count
    sta lb_prev
    ldx #4
    jsr res_count
    sta lb_prev+1
    lda nx_bside
    sta lb_bprev
    ; STEER: 1 + lato di chi guida, 0 senza guida
    lda #0
    ldx nx_steer
    beq :+
    lda nx_steer_s
    clc
    adc #1
:   cmp st_drawn
    beq done
    pha
    lda st_drawn
    beq :+
    lda #0                      ; via i segni di prima
    jsr steer_marks
:   pla
    sta st_drawn
    beq done
    lda #1
    jsr steer_marks
done:
    rts
.endproc

; Bullet time a schermo, con la palette di sempre come su PC e MiSTer: mezzeria e punteggi grigi,
; di nuovo bianchi quando finisce (della mezzeria solo le celle che la mostrano: la scritta del
; bonus può coprirla). Racchetta avversaria, capsule e coda della palla sono negli sprite. Circa
; 1.500 cicli, solo all'inizio e alla fine del BULLET, e con il frame avanti al prossimo.
.proc bullet_look
    ldx #0
    lda nx_btimer
    beq :+
    inx
:   cpx bl_on
    beq done
    jsr frame_late
    bcs done
    stx bl_on
    lda look_color,x
    sta m_t
    ; mezzeria: colonne 19 e 20 di ogni riga, dove ci sono i suoi caratteri
    ldx #24
row:
    lda row_lo,x
    sta ptr
    sta ptr2
    lda row_hi,x
    sta ptr+1
    clc
    adc #>($d800 - SCREEN)
    sta ptr2+1
    ldy #19
    lda (ptr),y
    cmp #CH_LINE_L
    bne :+
    lda m_t
    sta (ptr2),y
:   iny
    lda (ptr),y
    cmp #CH_LINE_R
    bne :+
    lda m_t
    sta (ptr2),y
:   dex
    bpl row
    ; punteggi: righe 1-3, colonne 11-16 e 23-28 (draw_scores)
    ldx #3
digits:
    lda row_lo,x
    sta ptr2
    lda row_hi,x
    clc
    adc #>($d800 - SCREEN)
    sta ptr2+1
    lda m_t
    ldy #16
:   sta (ptr2),y
    dey
    cpy #11
    bcs :-
    ldy #28
:   sta (ptr2),y
    dey
    cpy #23
    bcs :-
    dex
    bne digits
done:
    rts
.endproc

.segment "RODATA"
look_color: .byte COL_WHITE, COL_GRAY  ; senza e con il bullet time
.segment "CODE"

; Segni di STEER di st_drawn (1 sinistra, 5 destra): A = 1 disegna, 0 cancella. Chi guida da
; sinistra guida fino a x = 240 (colonne 29-30), da destra fino a x = 80 (colonne 9-10).
.proc steer_marks
    sta m_t
    jsr shots_erase
    ldx #29
    lda st_drawn
    cmp #1
    beq :+
    ldx #9
:   stx v_col
    ; riga 0: in cima
    ldy #0
    lda #CH_STEER_TOP_R
    ldx #CH_STEER_TOP_L
    jsr mark
    ldy #24
    lda #CH_STEER_BOTTOM_R
    ldx #CH_STEER_BOTTOM_L
mark:
    sta m_lo
    stx m_b
    lda row_lo,y
    clc
    adc v_col
    sta ptr
    lda row_hi,y
    adc #0
    sta ptr+1
    ldy #0
    lda m_t
    beq erase
    lda m_lo
    sta (ptr),y
    iny
    lda m_b
    sta (ptr),y
    lda ptr+1
    clc
    adc #>($d800 - SCREEN)
    sta ptr+1
    lda egg_yel
    sta (ptr),y
    dey
    sta (ptr),y
    rts
erase:
    lda #CH_BLANK
    sta (ptr),y
    iny
    sta (ptr),y
    rts
.endproc

; Scritta "P1 SMASH!" (gialla) centrata nella riga LABEL_ROW; con il bit 7 di lb_bonus quella
; della mossa speciale (sm_label).
.proc label_draw
    jsr shots_erase
    bit lb_bonus
    bpl :+
    jmp sm_label
:
    ; nome del bonus e sua lunghezza (fino al primo spazio)
    lda lb_bonus
    asl a
    tay
    lda bonus_names,y
    sta ptr2
    lda bonus_names+1,y
    sta ptr2+1
    ldy #0
:   lda (ptr2),y
    beq :+
    cmp #' '
    beq :+
    iny
    cpy #8
    bne :-
:   sty lb_nlen
    tya
    clc
    adc #4                      ; "P1 " + nome + "!"
    sta lb_len
    lsr a
    eor #$ff
    sec
    adc #20
    sta lb_col
    ; P1 / P2
    lda lb_player
    beq :+
    lda #<s_p2
    ldy #>s_p2
    jmp :++
:   lda #<s_p1
    ldy #>s_p1
:   sta ptr2
    sty ptr2+1
    ldx lb_col
    ldy #LABEL_ROW
    jsr print_str               ; X avanza oltre "P1 "
    stx v_col
    lda lb_bonus
    asl a
    tay
    lda bonus_names,y
    sta ptr2
    lda bonus_names+1,y
    sta ptr2+1
    lda #LABEL_ROW
    sta v_row
    ldy #0
:   cpy lb_nlen
    beq :+
    lda (ptr2),y
    sty v_n
    ldx v_col
    jsr put_ascii
    inc v_col
    ldy v_n
    iny
    bne :-
:   lda #'!'
    ldx v_col
    jsr put_ascii
    lda lb_len
    sta v_n
    ldy lb_col
    ldx #LABEL_ROW
    lda #COL_YELLOW
    jmp color_span
.endproc

; Toglie la scritta e rimette la mezzeria.
.proc label_erase
    jsr shots_erase
    ldy #LABEL_ROW
    lda row_lo,y
    clc
    adc lb_col
    sta ptr
    lda row_hi,y
    adc #0
    sta ptr+1
    ldy lb_len
    lda #CH_BLANK
:   dey
    sta (ptr),y
    bne :-
    lda lb_len
    sta v_n
    ldy lb_col
    ldx #LABEL_ROW
    lda bl_on                   ; la mezzeria del colore che ha (grigia nel bullet time)
    tax
    lda look_color,x
    ldx #LABEL_ROW
    jsr color_span
    lda #LABEL_ROW
    sta v_row
    jmp center_line_row
.endproc

.segment "NEXTBSS"
lb_prev:   .res 2               ; bonus nella riserva dopo il tick prima
lb_bprev:  .res 1               ; e chi aveva il BULLET (nx_bside)
lb_bonus:  .res 1
lb_player: .res 1               ; 0 sinistro, 4 destro
lb_frames: .res 1               ; frame rimasti della scritta
lb_pend:   .res 1               ; scritta ancora da disegnare
lb_nlen:   .res 1
lb_len:    .res 1
lb_col:    .res 1
st_drawn:  .res 1               ; segni di STEER a schermo: 0, o 1 + lato di chi guida
bl_on:     .res 1               ; colori del bullet time a schermo
.segment "CODE"

; ------------------------------------------------------------------------------------ anteprima

; Scelta della racchetta: la racchetta sotto il cursore a grandezza reale (sprite 3 e 4 come in
; partita), a destra della lista di ciascun giocatore e con il davanti verso la mezzeria, come
; sul MiSTer: TWIST inclinata, BLASTER con il caricatore pieno.
PV_CY = (PICK_ROW0 + KINDS - 1) * 8 + 4    ; centro della lista (riga in pixel)

.proc pick_preview
    lda #0
    sta sh_enable
    lda pk_kind
    bne :+
    lda #$ff                    ; scelta dei bonus: anteprime da rifare
    sta pv_kind
    sta pv_kind+1
    rts
:   lda pk_phase                ; schermo che cambia
    jne done
    ldy #0
side:
    sty pi_side
    ldx pk_cursor,y
    txa
    cmp pv_kind,y
    beq place
    jsr frame_late              ; un'immagine costa: con il frame avanti al prossimo
    bcs place
    ldy pi_side
    lda pk_cursor,y
    sta pv_kind,y
    sta pi_kind
    tax
    lda pv_rows,x
    sta pi_n
    lda pv_var,x
    sta pi_var
    cpx #K_BLASTER
    bne :+
    lda #P_BLASTER_SHOTS        ; caricatore pieno
    jsr mag_setup
:   jsr pad_image
    ldy pi_side
    lda #1
    sta pd_dirty,y
    lda #$ff                    ; in partita l'immagine si rifà
    sta pd_n,y
place:
    ldy pi_side
    lda pv_kind,y
    cmp #$ff
    beq next                    ; immagine non ancora fatta
    tax
    lda #SP_PAD0
    clc
    adc pi_side
    sta sh_ptr+SPN_PAD,y
    lda #COL_WHITE
    sta sh_col+SPN_PAD,y
    lda bit_of+SPN_PAD,y
    ora sh_enable
    sta sh_enable
    lda bit_of+SPN_PAD,y
    ora sh_mc
    sta sh_mc
    lda bit_of+SPN_PAD,y
    ora sh_yexp
    sta sh_yexp
    lda bit_of+SPN_PAD,y
    eor #$ff
    and sh_xexp
    sta sh_xexp
    ; x: il corpo è al centro dell'immagine (24 pixel); la destra oltre 255
    lda pv_x,y
    sta sh_x+SPN_PAD,y
    lda bit_of+SPN_PAD,y
    eor #$ff
    and sh_msb
    cpy #1
    bne :+
    ora bit_of+SPN_PAD,y
:   sta sh_msb
    ; y: centrata sulla lista, due righe di pixel per riga dello sprite
    lda #<(SPR_Y0 + PV_CY)
    sec
    sbc pv_rows,x
    sta sh_y+SPN_PAD,y
next:
    iny
    cpy #2
    jne side
done:
    rts
.endproc

.segment "RODATA"
; righe dello sprite per tipo (altezza in pixel / 2, per eccesso), varianti dell'anteprima
.macro pv_rows_of h0, h1, h2, h3, h4, h5, h6, h7
    .byte ((h0 >> 16) + 1) / 2, ((h1 >> 16) + 1) / 2, ((h2 >> 16) + 1) / 2, ((h3 >> 16) + 1) / 2
    .byte ((h4 >> 16) + 1) / 2, ((h5 >> 16) + 1) / 2, ((h6 >> 16) + 1) / 2, ((h7 >> 16) + 1) / 2
.endmacro
pv_rows: pv_rows_of T_KIND_H
pv_var:  .byte 0, 0, 0, 3 + 3, P_BLASTER_SHOTS * 32, 0, 0, 0
pv_x:    .byte <(SPR_X0 + 16 * 8 - 12), <(SPR_X0 + 36 * 8 - 12)
.assert SPR_X0 + 16 * 8 - 12 < 256 .and SPR_X0 + 36 * 8 - 12 >= 256, error, "anteprime: bit alto della x"
.segment "NEXTBSS"
pv_kind: .res 2                 ; tipo nell'immagine dell'anteprima ($ff nessuna)
.segment "CODE"
