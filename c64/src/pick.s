; Modalità NEXT prima e durante la partita: scelta del tipo di racchetta e poi dei 3 bonus (come
; rust/game/src/next_ui.rs `Pick` e paddle_ui.rs `PaddlePick`, con lo schermo del MiSTer in
; mister/rtl/next_render.v) e riserve in alto durante la partita.
;
; Ogni giocatore ha il suo cursore (joystick su e giù, o la rotazione del paddle) e il fuoco
; prende o lascia la voce. Niente tempo: quando tutti hanno scelto, READY! per 1,2 secondi. Contro la CPU, la CPU sceglie da sola a caso dal seme
; della partita, con gli stessi numeri del PC.

READY_FRAMES = 60               ; 1,2 secondi
PICK_ROW0    = 8                ; prima voce, una ogni 2 righe
PICK_HINT    = 24               ; riga dei comandi e di READY! (una vuota dopo la frase del tipo, riga 22)
PICK_SEED_BONUS = $9E3779B9     ; seme xor delle scelte della CPU (next_ui.rs, paddle_ui.rs)
PICK_SEED_KIND  = $7A11E5ED
KINDS = 7

; fasi della scena: il lavoro di un cambio di schermo non sta in un frame
PH_NONE  = 0
PH_CLEAR = 1                    ; pulire lo schermo
PH_CHARS = 2                    ; caratteri della scelta (pick_chars, circa 9.500 cicli)
PH_DRAW  = 3                    ; scritte fisse (poi le colonne, una per frame)
PH_MATCH = 4                    ; partita (lo schermo è già pulito)
PH_RESTORE = 5                  ; scelte finite, schermo pulito: i caratteri di sempre, poi la
                                ; HOW TO PLAY o la partita
PH_THEME = 6                    ; sfida di CHALLENGE: il tema (ch_duel_theme), poi la partita
PH_RESTORE2 = 7                 ; la seconda metà delle lettere 2x, poi come PH_RESTORE
; HOW TO PLAY delle mosse speciali, dopo le scelte (come su PC e MiSTer): bitmap e
; colori dalla cartuccia (gen/howto.bin, banchi HOWTO_BANK) a schermo spento, HW_STEP pagine per
; frame, poi le scritte (un gruppo per frame, con i glifi del set: il font della ROM; i testi li
; porta la bitmap stessa, nella riga 1, vuota e nera: HT_TEXTS_AT),
; poi la bitmap per HOWTO_FRAMES frame (8 s); fuoco o Start la saltano dopo HOWTO_SKIP.
; La bitmap copre le tabelle dei quadrati ($F000), che poi si rifanno (math_invalidate, math_step
; nel conto alla rovescia o nella presentazione); i colori vanno nello schermo di testo ($C000),
; non a $C400, dove c'è già il codice delle mosse speciali.
HW_BITMAP    = 31               ; pagine della bitmap: $E000-$FEFF (le ultime 8 celle sono vuote)
HW_PAGES     = HW_BITMAP + 4    ; poi i colori
HW_STEP      = 3                ; pagine per frame (circa 3.800 cicli l'una)
HOWTO_FRAMES = 8 * 50
HOWTO_SKIP   = 15               ; 0,3 s
.assert HOWTO_FRAMES >= 256 .and HOWTO_FRAMES < 512, error, "HOW TO PLAY: il tempo si conta così"

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
.segment "BSS"                  ; (non NEXTBSS: in fondo alla RAM bassa serve il posto a FZCODE)
pk_count:  .res 2               ; bonus presi
pk_ok:     .res 2               ; racchetta confermata
.segment "CPUBSS"               ; (lo stesso; come NEXTBSS non si azzera all'avvio)
pk_chosen: .res 6               ; per giocatore 3 bonus nell'ordine in cui sono stati presi
.segment "NEXTBSS"
pk_ready:  .res 1               ; frame di READY! rimasti (0 = si sceglie ancora)
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
.segment "BSS"                  ; (non NEXTBSS: in fondo alla RAM bassa serve il posto a FZCODE)
hud_res:   .res 6               ; riserve disegnate in alto (B_NONE vuoto, $ff da disegnare)
.segment "NEXTBSS"
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
            .word s_omega            ; (OMEGA_KIND: OPPONENT del menu)
s_arcade:   .byte "ARCADE  ", 0
s_titan:    .byte "TITAN   ", 0
s_hammer:   .byte "HAMMER  ", 0
s_twist:    .byte "TWIST   ", 0
s_blaster:  .byte "BLASTER ", 0
s_rush:     .byte "RUSH    ", 0
s_guardian: .byte "GUARDIAN", 0
s_omega:    .byte "OMEGA   ", 0
; frase del tipo (paddle_ui::tagline), centrata nella metà (scelta e presentazione)
kind_tags: .word t_arcade, t_titan, t_hammer, t_twist, t_blaster, t_rush, t_guardian
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

; Inizio di NEXT dal menu: seme della partita, i bonus della CPU (o dell'avversario di CHALLENGE),
; poi la scelta della racchetta (kind_enter) e dopo quella dei bonus (bonus_enter), come sul PC.
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
    sta hw_pg
    sta pk_count
    sta pk_count+1
    lda opt_players
    cmp #OPT_CHALLENGE
    bne :+
    ; CHALLENGE: a destra i bonus dell'avversario del livello (il primo, o quello dell'allenamento)
    lda ch_level
    asl a
    adc ch_level
    tax
    lda rung_loadout,x
    sta pk_chosen+3
    lda rung_loadout+1,x
    sta pk_chosen+4
    lda rung_loadout+2,x
    sta pk_chosen+5
    lda #3
    sta pk_count+1
    bne draw
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
    jmp kind_enter
.endproc

; Scelta della racchetta, la prima: il suo codice (kpick.s) dalla cartuccia, al posto delle mosse
; speciali, che la scelta dei bonus ricopia.
.proc kind_enter
    lda #$80
    sta ef_src+2
    lda #KP_BANK
    ldx #4
    ldy #>KP_RUN
    jsr ef_copy
    lda #1
    sta pk_kind
    lda #$ff                    ; nessuna anteprima ancora (NEXTBSS non si azzera all'avvio, e la
    sta pv_kind                 ; scelta della racchetta ora viene prima di quella dei bonus)
    sta pv_kind+1
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
    ldx ch_level                ; CHALLENGE: la racchetta dell'avversario (start_game)
    lda rung_kind,x
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
; tiene la sua racchetta (kind_enter) e i suoi bonus. Seme nuovo per la sfida.
.proc pick_challenger
    jsr seed_from_time
    lda #0
    sta pk_cpu
    sta pk_count
    sta pk_count+1
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
    jmp kind_enter
.endproc

; Scelta dei bonus, dopo quella della racchetta: i tipi scelti vanno nella configurazione (il cursore
; serve di nuovo).
.proc bonus_enter
    lda pk_cursor
    sta cfg_kinds
    lda pk_cursor+1
    sta cfg_kinds+4
    lda #0
    sta pk_kind
    jmp pick_start
.endproc

; Parte comune delle due scelte: scena, cursori, schermo vuoto senza sprite.
.proc pick_start
    lda #ST_PICK
    sta state
    lda #0
    sta pk_ready
    sta pk_cursor
    sta pk_cursor+1
    sta sh_enable
    sta sh_bg
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
    lda hw_pg                   ; HOW TO PLAY in corso
    beq :+
    jmp howto_scene
:   lda pk_kind                 ; la racchetta: kpick.s
    beq :+
    jmp KP_RUN
:   lda #KEY_STOP
    jsr key_pressed
    bcc :+
    jsr pick_letters            ; di nuovo le lettere 2x (un frame lungo, verso il menu)
    jsr math_invalidate         ; (la scelta della racchetta ha coperto le tabelle dei quadrati)
    jmp enter_menu
:   lda pk_phase
    beq ready
    cmp #PH_CHARS
    beq chars
    cmp #PH_DRAW
    beq draw
    cmp #PH_MATCH
    beq match
    bcs late
    ; schermo pulito
    lda #PH_CHARS
    sta pk_phase
    lda #COL_WHITE
    jmp clear_text
chars:
    ; sullo schermo vuoto le metà delle lettere (put_low)
    lda #PH_DRAW
    sta pk_phase
    clc
    jmp pick_chars
draw:
    lda #PH_NONE
    sta pk_phase
    jmp pick_draw
match:
    lda math_ready              ; le tabelle dei quadrati, che la scelta della racchetta ha coperto
    beq :+
    lda #PH_NONE
    sta pk_phase
    jmp start_next
:   rts
late:
    cmp #PH_THEME
    bne restore
    jsr ch_duel_theme
    lda #PH_MATCH
    sta pk_phase
    rts
restore:
    ; di nuovo le lettere 2x (pick_chars, sullo schermo già pulito), in due frame: PH_RESTORE la
    ; prima metà, PH_RESTORE2 la seconda; poi con le mosse speciali la HOW TO PLAY (non con i
    ; paddle, senza gesti, né per lo sfidante); la sfida prima il suo tema (PH_THEME); poi la
    ; partita al prossimo frame
    cmp #PH_RESTORE2
    beq second
    lda #PH_RESTORE2
    sta pk_phase
    lda #0
    sec
    jmp pick_chars
second:
    lda #1
    sec
    jsr pick_chars
    lda cg_active
    cmp #CG_DUEL
    jeq vs_duel                 ; la sfida: prima lo schermo VS (kvs.s), che carica il tema
    lda cfg_super
    beq match_next
    lda ctl_paddle
    bne match_next
    jmp howto_enter
match_next:
    ldx #PH_MATCH
phase:
    stx pk_phase
    rts
ready:
    lda pk_ready
    beq choosing
    ; READY!: lampeggia, poi si va avanti. Negli ultimi frame, leggeri, il codice delle mosse
    ; speciali dalla cartuccia, una pagina per frame (sm_page)
    dec pk_ready
    beq go
    lda pk_ready
    cmp #READY_FRAMES - 3       ; dopo le due colonne: le tabelle dei quadrati, che la scelta della
    bne :+                      ; racchetta ha coperto, da rifare (math_step, nei frame leggeri)
    jsr math_invalidate
    lda pk_ready
:   cmp #SM_PAGES + 1
    bcs :+
    sbc #0                      ; (C = 0) pagina pk_ready - 1
    jsr sm_page
:   jsr draw_ready
    lda pk_dirty
    beq :+
    jmp draw_columns
:   rts
go:
    ; scelte finite: lo schermo pulito ora, il resto al prossimo frame (PH_RESTORE)
    lda #PH_RESTORE
    sta pk_phase
    lda #COL_WHITE
    jmp clear_text
choosing:
    lda pk_fixed                ; chi non sceglie (la CPU o il campione) non ha comandi
    beq :+
    ldx #0
    jsr pick_player
:   lda pk_fixed
    cmp #1
    beq :+
    ldx #1
    jsr pick_player
:   ; fine: tutti hanno scelto
.ifdef AUTONEXT
    ; (prova per VICE, senza tempo nella scelta: ogni 128 frame tutti confermano la racchetta, e
    ; nei bonus prendono quelli predefiniti)
    lda frame_count
    and #127
    bne :+
    lda pk_kind
    beq finish
    lda #1
    sta pk_ok
    sta pk_ok+1
:
.endif
    lda pk_count
    and pk_count+1
    cmp #3
    bne redraw
finish:
    jsr fill_defaults
    lda #READY_FRAMES
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

; Di nuovo tutte le lettere 2x al posto delle metà delle lettere (pick_chars, le due metà).
.proc pick_letters
    lda #0
    sec
    jsr pick_chars
    lda #1
    sec
    jmp pick_chars
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
    lda pk_kind
    beq updown
    ; racchetta, griglia 4x2 (kpick.s): destra e sinistra la dopo e la prima, da una riga
    ; all'altra; su e giù l'altra riga, stessa colonna (sotto TWIST c'è OMEGA: fermo)
    lda joy_edge,x
    and #JOY_LEFT
    bne prev
    lda joy_edge,x
    and #JOY_RIGHT
    bne next
    lda joy_edge,x
    and #JOY_UP | JOY_DOWN
    beq fire
    lda pk_cursor,x
    eor #4
    cmp #KINDS
    bcs fire
    sta pk_cursor,x
    bcc moved                   ; (sempre)
updown:
    lda joy_edge,x
    and #JOY_UP
    beq down
prev:
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
next:
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
    lda #1                      ; schermo già pulito (pick_scene; le racchette: bonus_enter)
    sta screen_clear
    jmp begin_match
.endproc

; ------------------------------------------------------------------------------------ disegno

; Tutto lo schermo della scelta dei bonus.
.proc pick_draw
    jsr print_at
    .byte 13, 0, "PICK 3 BONUSES", 0
    lda #COL_YELLOW
    ldx #0
    ldy #0
    jsr color_row
    ; mezzeria sotto il tempo
.ifdef ROTATED
    jsr today_glyphs            ; (campo girato: i caratteri della mezzeria di oggi, in verticale)
.endif
    lda #6
    sta v_row
:
.ifdef ROTATED
    jsr pick_line_row
.else
    jsr center_line_row
.endif
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
    ; intestazione: P1, P2 o CPU e quanti bonus su 3
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
    lda #0
    sta pk_i
row:
    jsr draw_row
    inc pk_i
    lda pk_i
    cmp #PICKS
    bne row
    rts
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
    ldy pk_i
    lda pickable,y
    jsr pick_has
    lda #0                      ; preso = C (pick_has usa m_t: con 0 bonus del destro vi lascia 1)
    rol a
    sta m_t

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
    ldy pk_p
    lda pk_count,y
    cmp #3
    beq :+
    lda #'>'
    sta m_lo
:   lda col_base,x
    clc
    adc #2
    tax
    lda m_lo
    jsr put_low
    ; colore della riga: bonus presi e quello sotto il cursore bianchi, gli altri grigi
    ldx pk_p
    lda m_t
    bne white
    lda m_lo
    cmp #'>'
    beq white
    lda #COL_GRAY
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
    ; la riga sotto (metà basse della capsula e delle lettere) dello stesso colore
    ldx pk_p
    ldy col_base,x
    lda #20
    sta v_n
    ldx v_row
    inx
    lda m_b
    jsr color_span
    ; il cursore in giallo, le due metà
    lda m_lo
    cmp #'>'
    bne :+
    ldx v_row
    jsr cursor_yellow
    ldx v_row
    inx
    jsr cursor_yellow
:   ; capsula 2x2 (in negativo se presa) e nome del bonus
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
; cursore accanto si abbassano di 4 pixel, con le metà delle lettere che pick_chars mette al posto
; delle lettere 2x (pick_start): la metà alta nella riga v_row, la bassa in quella sotto.

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

; Colore A per v_n celle dalla colonna Y della riga X.
color_span:
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
:   lda sm_on
    beq :+
    jsr sm_hud                  ; mosse speciali: barre, colori, scritta e suoni
:
    bit $fffb                  ; con la voce di CHALLENGE (READY?, gli NMI costano circa 5.100
    bmi :+                      ; cicli per frame) le immagini aspettano che finisca
    ; (ognuna chiamata solo finché ha da fare: è codice di quasi tutti i frame della partita)
    lda fx_pages
    cmp #FX_SPRITES
    bcs fx_done
    jsr fx_copy                 ; effetti della palla a $E000, una pagina per frame
    lda fx_wait
    bne :+
fx_done:
    lda pp_side
    cmp #2
    bcs pp_done
    jsr pad_prep                ; e le immagini delle racchette, una pagina per frame
    lda pp_side
    cmp #2
    bcc :+
pp_done:
.ifndef ROTATED                 ; (campo girato: niente rotazione del SUPER, lì le pose del lato in alto)
    lda sp_k
    cmp #16
    bcs :+
    jsr spin_prep               ; poi quelle della rotazione del SUPER
.endif
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
    jsr frame_late_hud          ; frame già avanti: il posto al prossimo (su NTSC soglia leggera)
    bcs :+
    jsr shots_off_hud           ; (un fascio sopra il posto lo rimetterebbe com'era)
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
.ifdef ROTATED
    adc #ROT_HUD_COL            ; (campo girato: nella fascia, colonna 31 + 2 * posto; C = 0)
    sta v_col
    lda hud_row,x
.else
    beq :+
    eor #$ff
    sec
    adc #38
:   sta v_col
    lda #0
.endif
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
.ifdef ROTATED
    lda v_row
    clc
    adc #2
    tay
.else
    ldy #2
.endif
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

; Posto vuoto alla colonna v_col, righe 0-1 (campo girato: v_row e la dopo).
.proc put_empty
.ifdef ROTATED
    ldy v_row
.else
    ldy #0
.endif
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
.ifdef ROTATED
    txa                         ; (campo girato: righe da v_row)
    clc
    adc v_row
    tax
.endif
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
    sta mv_st                   ; nessuna scritta delle mosse speciali, nessun segno di STEER
    sta mv_st+1
    sta st_drawn
    sta bl_on                   ; schermo nuovo: mezzeria e punteggi bianchi
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

; ------------------------------------------------------------------------------------ HOW TO PLAY

.proc howto_enter
    lda #1
    sta hw_pg                   ; pagina da copiare + 1
    sta math_ready              ; niente math_step nella bitmap finché si vede (poi da capo)
    lda #0
    sta sh_enable
    lda #MODE_OFF
    sta sh_mode
    rts
.endproc

.proc howto_scene
    lda hw_pg
    cmp #$ff
    bne :+
    ; schermo pulito: la partita quando le tabelle dei quadrati sono rifatte (math_step, in frame),
    ; non nello stesso frame (con begin_match sarebbe troppo)
    lda math_ready
    jeq wait
    lda #0
    sta hw_pg
    lda #PH_MATCH
    sta pk_phase
    rts
:   cmp #HW_PAGES + 1
    bcc copy_frame
    cmp #HW_PAGES + 1 + HT_GROUPS
    bcc texts
    jmp show
copy_frame:
    ; copia: la bitmap a $E000, poi i colori (quelli dell'easter egg 4 pagine dopo) a $C000
    ldx #HW_STEP
copy:
    txa
    pha
    ldx hw_pg
    dex                         ; pagina
    txa
    cmp #HW_BITMAP
    bcs colors
    pha
    adc #$80                    ; (C = 0)
    sta ef_src+2
    pla
    adc #>$E000                 ; (C = 0)
    tay
    lda #HOWTO_BANK
    bne one
colors:
    sbc #HW_BITMAP              ; (C = 1)
    pha
    clc
    adc #$80                    ; (C = 0)
    sta ef_src+2
    pla
    clc
    adc #>SCREEN
    tay
    lda #HOWTO_BANK + 1
one:
    ldx #1
    jsr ef_copy
    inc hw_pg
    pla
    tax
    lda hw_pg
    cmp #HW_PAGES + 1
    bcs :+
    dex
    bne copy
:   rts
texts:
    ; le scritte, un gruppo per frame; poi si vede
    sec
    sbc #HW_PAGES + 1
    jsr howto_texts
    inc hw_pg
    lda hw_pg
    cmp #HW_PAGES + 1 + HT_GROUPS
    bcc :-
    lda #MODE_HOWTO
    sta sh_mode
    lda #0
    sta hw_t
    sta hw_t+1
    rts
show:
    ; HOWTO_FRAMES frame, o fuoco / Start dopo HOWTO_SKIP
    inc hw_t
    bne :+
    inc hw_t+1
:   lda hw_t+1
    bne late
    lda hw_t
    cmp #HOWTO_SKIP
    bcc wait
    bcs skip
late:
    lda hw_t
    cmp #<HOWTO_FRAMES
    bcs leave
skip:
    jsr start_pressed
    bcs leave
wait:
    rts
leave:
    ; schermo di testo pulito, poi le tabelle dei quadrati da rifare (sopra) e la partita
    lda #$ff
    sta hw_pg
    jsr math_invalidate
    lda #MODE_TEXT
    sta sh_mode
    lda #COL_WHITE
    jmp clear_text
.endproc

; Le scritte del gruppo A nella bitmap (print_str con i glifi del set), dai testi che la bitmap
; copiata porta nella riga 1 (HT_TEXTS_AT, tools/gen_c64_assets.py).
.proc howto_texts
    tax
    lda #<HT_TEXTS_AT
    sta ptr2
    lda #>HT_TEXTS_AT
    sta ptr2+1
find:
    dex
    bmi entry
:   jsr ht_byte                 ; il gruppo dopo: fino a $FE
    cmp #$fe
    bne :-
    beq find
entry:
    jsr ht_byte                 ; colonna, o la fine del gruppo
    cmp #$fe
    bcs done
    tax
    lda #$40                    ; nella bitmap
    sta v_big
    jsr ht_byte                 ; riga
    tay
    jsr print_str               ; (Y = lunghezza)
    tya
    sec
    adc ptr2
    sta ptr2
    bcc entry
    inc ptr2+1
    bcs entry
done:
    lda #0
    sta v_big
    rts
ht_byte:
    ldy #0
    lda (ptr2),y
    inc ptr2
    bne :+
    inc ptr2+1
:   rts
.endproc
.assert HW_PAGES + 1 + HT_GROUPS < $ff, error, "HOW TO PLAY: hw_pg arriva a $FF"

.segment "NEXTBSS"
hw_pg:  .res 1                  ; HOW TO PLAY: pagina da copiare + 1 (0 = non in corso, $FF = finita,
                                ; si aspettano le tabelle dei quadrati)
hw_t:   .res 2                  ; frame da quando si vede
.segment "CODE"

; ------------------------------------------------------------------------------------ GUARDIAN

; Muro del GUARDIAN dietro la racchetta, sotto le riserve (righe BAR_ROW0-24): non si vede (i settori
; in piedi sono i corsi della racchetta, pad_image); il settore che rimanda la palla lampeggia per
; BAR_FLASH frame, a tratti, nel colore del GUARDIAN (azzurro), e sparisce. I settori non sono allineati ai
; caratteri: ogni riga di caratteri prende il settore del suo centro con la regola della logica
; (g_sector, sulla y del core che va verso l'alto), quindi il disegno è approssimato al carattere
; e la logica no. Si riscrivono solo le righe dei settori cambiati.
BAR_ROW0   = 3
BAR_FLASH  = (15 * TV_HZ + 25) / 50 ; frame del lampeggio (0,3 s)
.ifndef ROTATED
.assert P_BARRIER_X = 8 << 16, error, "caratteri della barriera fatti per x = 8 (gen_c64_assets.py)"
; (P_GUARDIAN_TOP è la y del core dell'estremo alto del muro: a schermo P_HEIGHT - P_GUARDIAN_TOP)
.assert (BAR_ROW0 - 1) * 8 < (P_HEIGHT - P_GUARDIAN_TOP) >> 16 .and BAR_ROW0 * 8 >= (P_HEIGHT - P_GUARDIAN_TOP) >> 16, error, "muro del GUARDIAN: prima riga sotto la banda delle riserve"
.endif

.ifndef ROTATED                 ; (campo girato: rot_video.s)
.proc draw_barrier
    lda nx_kind                 ; nessun GUARDIAN (quasi sempre): niente da fare
    cmp #K_GUARDIAN
    beq :+
    lda nx_kind+4
    cmp #K_GUARDIAN
    beq :+
    rts
:   ldx #0
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
    sta m_t
    eor #$ff
    and bar_prev,x
    beq :+
    sta bar_fbit,x
    lda #BAR_FLASH
    sta bar_flash,x
:   lda m_t
    sta bar_prev,x
    lda #0
    sta m_t                     ; settori da mostrare: solo quello che lampeggia
    lda bar_flash,x
    beq :+
    dec bar_flash,x
    lda tick
    and #2
    beq :+
    lda bar_fbit,x
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
    lda #COL_LBLUE              ; nel colore del GUARDIAN (kind_col)
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
.endif

; ------------------------------------------------------------------------------------ BLASTER

; Colpi del BLASTER: due fasci laser verdi paralleli che escono dalle bocche dei due cannoni alari
; dell'astronave (righe SHOT_TOP - ceil(y) e SHOT_BOT - ceil(y), y del colpo, cioè della racchetta
; quando ha sparato: gen_c64_assets.py, shot_rows), in caratteri a passi di 2 pixel: una cella, o
; due vicine. Il tratto alto 2 pixel sta a una di quattro altezze nella cella (righe 0-1, 2-3, 4-5,
; 6-7: SHOT_CHARS per altezza e fase), al più un pixel sopra la bocca. I due fasci sono a 16 righe:
; stessa altezza, due righe di celle. Le altezze 0-2 sono caratteri presi in prestito in NEXT
; (shot_glyphs). Dappertutto, anche sopra punteggi, barre e riserve (righe 0-3). Si disegnano a
; inizio frame, nel vblank, nel conto alla rovescia e in partita (nel GAME OVER no: le scritte vanno
; sul campo pulito). Chi scrive sul campo cancella prima i colpi (shots_erase; sopra, shots_off_hud).
;
; Nelle righe 0-3 il fascio non cancella quello che c'è sotto: dove la cella non è vuota ci va un
; carattere fuso, quello di sotto con il tratto sopra (bd_fuse), e il colore resta quello di
; sotto (una cella ha un colore solo: lì il tratto non è verde). I caratteri fusi sono SHOT_PN da
; SHOT_P0, uno per cella di fascio (lo stesso posto di sv_c), presi in prestito come gli altri:
; sono le lettere 2x, che next_shots rifà al GAME OVER. Nel resto del campo (rete, muro) il fascio
; copre, come sempre.
;
; Per differenza: per ogni colpo restano a schermo le celle dell'ultimo disegno (sd_cw, sd_y, i
; puntatori alle righe dei due fasci e, per cella, carattere e colore di prima in sv_c e sv_k nel
; posto colpo * 4 + fascio * 2 + colonna & 1). Al frame dopo si rimettono solo le celle lasciate,
; si salvano solo quelle nuove, e in tutte le celle di adesso si scrivono carattere e verde: lo
; schermo è quello che darebbe cancellare tutto e ridisegnare tutto, se nessun fascio copre un
; altro. Un fascio sopra un altro si riconosce dal carattere salvato (uno dei colpi): allora si
; cancella tutto e si ridisegna tutto da capo, nell'ordine dei colpi (i caratteri salvati sono
; quelli dei fasci sotto, come prima), e al frame dopo di nuovo da capo (sv_n = $FF), finché i
; fasci non si separano. Con un solo fascio in campo (l'altro sopra le riserve o sotto lo
; schermo) i due puntatori sono quelli dello stesso fascio: si scrive due volte la stessa cosa.
SH_LO   = SHOT_P0               ; caratteri dei colpi: da SH_LO a SH_HI - 1 (presi in prestito:
                                ; i fusi, lettere 2x che in partita non sono a schermo, i tratti)
SH_HI   = SHOT_B0 + SHOT_BN
SH2_LO  = SHOT_OWN              ; e da SH2_LO a SH2_HI - 1 (del set)
SH2_HI  = SHOT_OWN + 7
.assert SH_HI <= SH2_LO, error, "colpi: i caratteri presi prima di quelli del set (bd_cell)"
bd_pb   = n_t                   ; fascio basso: puntatori alla riga (carattere) e al colore
bd_kb   = n_t + 2               ; (il fascio alto in ptr e ptr2)
bd_c0   = m_b                   ; caratteri delle celle di adesso (bd_c1 = 0: una cella sola)
bd_c1   = m_b + 1
bd_nc   = m_b + 2               ; colonna di adesso
bd_oc   = m_b + 3               ; colonna di prima (in fresh: riga del fascio basso)
bd_s    = m_a                   ; colpo
bd_ny   = m_a + 1               ; ceil(y) (la y in pixel interi arrotondata in su)
bd_ow   = m_a + 2               ; bit 7: due celle prima (in fresh: riga del fascio alto)
bd_k    = m_a + 3               ; celle a schermo se ci si ferma per una sovrapposizione ($FF nessuna)
bd_full = m_p                   ; bit 7: da capo (sovrapposizioni ammesse)
bd_dirty = m_p + 1              ; bit 7: un fascio sopra un altro
bd_mask = m_p + 2               ; colpi ancora da guardare (in volo o con celle a schermo; bit 0 il prossimo)
bd_x4   = v_col                 ; colpo * 4
; (in pagina zero, dichiarate prima dell'uso: ca65 altrimenti le prende per indirizzi lunghi)
.segment "ZEROPAGE"
fz_s:   .res 2                  ; bd_fuse: glifo di sotto
fz_g:   .res 2                  ; e del tratto
fz_hi:  .res 1                  ; bit 7: il fascio alto del colpo in esame è nelle righe 0-3
fz_new: .res 1                  ; bit 7: la cella è nuova, il carattere fuso si fa per intero
.segment "CODE"
bd_g    = v_n                   ; bd_put: il carattere del tratto
fz_x    = m_p + 3               ; bd_fuse: X e Y di chi chiama
fz_y    = m_p + 4
.assert SHOT_P0 + SHOT_PN <= SHOT_B0 .and SHOT_PN = 8 * MAX_SHOTS, error, "colpi: un carattere fuso per cella di fascio"
.assert SHOT_BOT = SHOT_TOP + 16 .and SHOT_BOT < 256, error, "colpi: fasci a due righe di celle, righe in un byte"

.ifndef ROTATED                 ; (campo girato: rot_shots.s)
.proc next_shots
    ; fuori dalla partita (anche nel GAME OVER, che ha appena tolto i colpi: enter_over) lo schermo
    ; è già un altro: i colpi si dimenticano. Al primo frame fuori dalla partita, comunque sia
    ; finita (GAME OVER, menu, nuovo sfidante, un'altra partita), i caratteri presi in prestito
    ; tornano vuoti: nessuna schermata deve mostrare un tratto di laser, nemmeno per un frame (sg_on
    ; a SG_BLANK: restano da rifare le lettere 2x, anche quelle dei caratteri fusi). Nei due frame
    ; dopo, se è il GAME OVER, le lettere 2x di nuovo al loro posto, metà per frame (le scritte
    ; vengono dopo: il banco di prova lo controlla); le altre schermate che le usano se le rifanno
    lda state
    cmp #ST_COUNT
    bcc out_game
    cmp #ST_PLAY + 1
    bcc in_game
out_game:
    lda sg_on
    beq leave
    cmp #SG_GLYPHS
    bne relet
    ldx #8 * SHOT_BN
    lda #0
blank:
    sta SG_DST - 1,x
    dex
    bne blank
    beq step                    ; (sempre)
relet:
    ldx state
    cpx #ST_OVER
    bne leave
    ldy #0
    cmp #SG_BLANK
    beq :+
    ldy #BIG2_N / 2
:   ldx #BIG2_N / 2
    jsr big2_build
step:
    inc sg_on
leave:
    lda #0
    sta sv_n
    rts
in_game:
    bit sv_n                    ; fasci sovrapposti al frame prima: via tutto, poi da capo
    bpl :+
    jsr shots_erase
:   lda m_next
    beq none
start:
    ; colpi in volo (bit k: colpo k)
    lda shot_on+7
    .repeat 7, k
    asl a
    ora shot_on+6-k
    .endrepeat
    bne some
none:
    jmp shots_erase             ; (via quelli rimasti)
some:
    sta bd_mask
    lda #0
    sta bd_dirty
    sta bd_full
    lda sv_n
    beq full
    lda bd_mask                 ; e i colpi con celle a schermo
    ora sd_on
    sta bd_mask
    bne go
full:
    ; da capo: niente a schermo che conti
    lda #$80
    sta bd_full
    lda #$FF
    ldx #7
:   sta sd_cw,x
    dex
    bpl :-
    inx
    stx sd_on
go:
    ldx #$FF
skip:
    inx                         ; il prossimo colpo da guardare
    lsr bd_mask
    bcc skip
shot:
    stx bd_s
    lda shot_on,x
    beq gone
    txa
    asl a
    asl a
    sta bd_x4
    tay
    ; colonna e fase: x0 = int(x) - 3, colonna x0 / 8, fase x0 & 6
    lda shot_x+2,y
    sec
    sbc #3
    sta v_n
    lda shot_x+3,y
    sbc #0
    bmi gone
    lsr a                       ; bit 8 di x0 nel carry
    lda v_n
    ror a
    lsr a
    lsr a
    cmp #40
    bcs gone
    sta bd_nc
    lda shot_y,y                ; ceil(y): la parte intera, + 1 con la frazione
    ora shot_y+1,y
    cmp #1
    lda shot_y+2,y
    adc #0
    sta bd_ny
    lda v_n
    and #6
    sta bd_c0                   ; fase * 2
    lda #SHOT_BOT               ; altezza del tratto: (riga del fascio basso & 6) / 2
    sec
    sbc bd_ny
    and #6
    sta fz_r                    ; riga del tratto nella cella (bd_part)
    asl a
    asl a
    ora bd_c0
    tay                         ; altezza * 8 + fase * 2 = indice in shot_chars
    lda shot_chars,y
    sta bd_c0
    lda bd_nc
    cmp #39
    lda #0                      ; colonna 39: niente cella a destra
    bcs :+
    lda shot_chars+1,y
:   sta bd_c1
    lda sd_cw,x
    cmp #$FF
    jeq fresh
    lda bd_ny
    cmp sd_y,x
    beq same
    jsr erase_shot              ; altre righe: via le celle di prima
    jmp fresh
gone:
    lda sd_cw,x
    cmp #$FF
    beq next
    jsr erase_shot
next:
    ldx bd_s
    lda bd_mask
    jne skip
    lda #1
    bit bd_dirty
    bpl :+
    lda #$FF
:   sta sv_n
    rts
same:
    ; stesse righe: celle di prima (colonna, una o due) e di adesso
    lda sd_cw,x
    sta bd_ow
    and #$7F
    sta bd_oc
    jsr bd_ptrs
    lda bd_nc
    sec
    sbc bd_oc
    beq same_col
    cmp #1
    beq right1
    cmp #$FF
    beq left1
generic:
    jsr erase_shot
    jmp fresh
right1:
    ; una colonna a destra, con due celle prima: via la prima, la seconda è la prima di adesso
    bit bd_ow
    bpl generic
    ldy bd_oc
    tya
    and #1
    ora bd_x4
    tax
    jsr bd_rest
    iny
    lda bd_c0
    jsr bd_put
    sty bd_k
    lda bd_c1
    jeq done_cw
    iny                         ; la seconda di adesso: nel posto della prima di prima
    jsr bd_cell
    jmp done_cw
left1:
    ; una colonna a sinistra, con due celle adesso: la prima di prima è la seconda di adesso
    lda bd_c1
    beq generic
    ldy bd_oc
    jsr bd_put
    bit bd_ow
    bpl :+
    iny                         ; via la seconda di prima
    tya
    and #1
    ora bd_x4
    tax
    jsr bd_rest
    dey
:   sty bd_k
    dey                         ; la prima di adesso
    tya
    and #1
    ora bd_x4
    tax
    lda bd_c0
    jsr bd_cell
    jmp done_cw
same_col:
    ldy bd_nc
    sty bd_k
    lda bd_c0
    jsr bd_put
    iny
    tya
    and #1
    ora bd_x4
    tax                         ; posto della seconda cella
    bit bd_ow
    bmi two
    lda bd_c1                   ; una prima: con due adesso, la seconda è nuova
    jeq done_cw
    jsr bd_cell
    jmp done_cw
two:
    lda bd_c1                   ; due prima: la seconda resta, o va via
    beq :+
    jsr bd_put
    jmp done_cw
:   jsr bd_rest
    jmp done_cw
fresh:
    ; colpo da disegnare (X = colpo): righe dei fasci (0-24), basso (SHOT_BOT - ceil(y)) / 8, alto
    ; due righe sopra; uno solo a schermo: tutti e due i puntatori su quello
    lda #$FF
    sta bd_k
    lda #SHOT_BOT
    sec
    sbc bd_ny
    jcc next                    ; tutti e due sopra lo schermo (sd_cw resta $FF)
    lsr a
    lsr a
    lsr a
    sta bd_oc                   ; riga del fascio basso (25: sotto lo schermo)
    sec
    sbc #2                      ; riga del fascio alto
    bcs :+
    lda bd_oc                   ; l'alto sopra lo schermo: il basso
:   sta bd_ow
    tay
    lda row_lo,y
    sta sv_la,x
    lda row_hi,y
    sta sv_ha,x
    ldy bd_oc
    cpy #25
    bcc :+
    ldy bd_ow                   ; il basso sotto lo schermo: l'alto
:   lda row_lo,y
    sta sv_lb,x
    lda row_hi,y
    sta sv_hb,x
    jsr bd_ptrs
    ldy bd_nc
    tya
    and #1
    ora bd_x4
    tax
    lda bd_c0
    jsr bd_cell
    lda bd_c1
    beq done
    sty bd_k
    iny
    txa
    eor #1
    tax
    lda bd_c1
    jsr bd_cell
done:
    ldx bd_s                    ; colpo nuovo o righe nuove: la y e il bit in sd_on
    lda bd_ny
    sta sd_y,x
    lda sd_on
    ora col_bit,x
    sta sd_on
done_cw:
    ldx bd_s                    ; (stesse righe: solo le celle)
    lda bd_c1
    cmp #1                      ; C = 1: due celle
    lda bd_nc
    bcc :+
    ora #$80
:   sta sd_cw,x
    jmp next
.endproc

.endif
shot_chars: .byte SHOT_CHARS

.ifndef ROTATED                 ; (campo girato: rot_shots.s)
; Puntatori dei due fasci del colpo X: ptr e ptr2 l'alto, bd_pb e bd_kb il basso; fz_hi negativo
; se il fascio alto è nelle righe 0-3 (prima pagina dello schermo, sotto la riga 4: $D8 - $D8 con
; il prestito). X e Y restano. Sta sotto lo stack (STKCODE: in MAIN non c'è posto), copiato da
; title_unpack.
.segment "STKCODE"
.proc bd_ptrs
    lda sv_la,x
    sta ptr
    sta ptr2
    cmp #4 * 40
    lda sv_ha,x
    sta ptr+1
    ora #>($d800 - SCREEN)      ; $C0..$C3 -> $D8..$DB (Color RAM)
    sta ptr2+1
    sbc #>$d800
    sta fz_hi
    lda sv_lb,x
    sta bd_pb
    sta bd_kb
    lda sv_hb,x
    sta bd_pb+1
    ora #>($d800 - SCREEN)
    sta bd_kb+1
    rts
.endproc
.segment "CODE"
.assert (>SCREEN & >($d800 - SCREEN)) = 0 .and (>(SCREEN + 999) & >($d800 - SCREEN)) = 0, error, "colpi: ora per la RAM del colore"

; Cella Y dei due fasci (posti X e X + 2): rimette carattere e colore di prima. X e Y restano.
.proc bd_rest
    lda sv_c,x
    sta (ptr),y
    lda sv_k,x
    sta (ptr2),y
    lda sv_c+2,x
    sta (bd_pb),y
    lda sv_k+2,x
    sta (bd_kb),y
    rts
.endproc

; Cella nuova Y dei due fasci (posti X e X + 2): salva carattere e colore (un colpo sotto:
; sovrapposizione, bd_over), poi il carattere A in verde (bd_put). X e Y restano.
.proc bd_cell
    pha
    lda (ptr),y
    cmp #SH_LO
    bcc :+
    jsr bd_over
:   sta sv_c,x
    lda (ptr2),y
    sta sv_k,x
    lda (bd_pb),y
    cmp #SH_LO
    bcc :+
    jsr bd_over
:   sta sv_c+2,x
    lda (bd_kb),y
    sta sv_k+2,x
    lda #$80                    ; cella nuova: il carattere fuso, se serve, si fa per intero
    sta fz_new
    pla
    .byte $2c                   ; (bit abs: salta i due byte del lsr fz_new di bd_put; legge
.endproc                        ; l'indirizzo fz_new * 256 + $46, che non deve essere dell'I/O)
.assert fz_new < $d0 .or fz_new > $df, error, "bd_cell: il bit che salta il lsr legge un registro"
; (prosegue)
; Carattere A in verde nella cella Y dei due fasci (quello che c'è sotto è salvato nei posti
; della cella: colpo * 4 + colonna & 1, e + 2 per il fascio basso). Nelle righe 0-3, sopra una
; cella non vuota, il carattere fuso con quello di sotto e il suo colore (bd_fuse: mai prima il
; tratto da solo, che per qualche riga del raster si vedrebbe). Il fascio basso può essere nelle
; righe 0-3 solo con l'alto lì (due righe sopra, o lo stesso fascio: allora basta una volta).
; Sulla rete (colonne NET_COL e la dopo) lo stesso in tutte le righe: il fascio la attraversa
; senza cancellarla. Una cella che era già del fascio al frame prima ha già nel suo carattere
; fuso il glifo di sotto: bd_fuse ci rifà solo le due righe del tratto (fz_new a 0; bd_cell lo
; alza per le celle nuove). X e Y restano.
NET_COL = 19                    ; la rete: colonne 19 e 20
.proc bd_put
    lsr fz_new                  ; chiamata da sola: la cella c'era già
    bit fz_hi
    bmi hud
    cpy #NET_COL
    bcc fast
    cpy #NET_COL + 2
    bcc hud                     ; sulla rete
fast:
    sta (ptr),y
    sta (bd_pb),y
    lda #COL_GREEN
    sta (ptr2),y
    sta (bd_kb),y
    rts
hud:
    sta bd_g
    txa
    pha
    tya
    and #1
    ora bd_x4
    tax                         ; il posto della cella
    lda sv_c,x
    beq hp
    jsr bd_fuse
    sta (ptr),y
    lda sv_k,x
    bcc hk                      ; (sempre)
hp: lda bd_g
    sta (ptr),y
    lda #COL_GREEN
hk: sta (ptr2),y
    lda bd_pb
    cmp ptr
    beq out                     ; un fascio solo a schermo: la stessa cella
    lda sv_c+2,x
    beq lp
    inx
    inx
    jsr bd_fuse
    dex
    dex
    sta (bd_pb),y
    lda sv_k+2,x
    bcc lk                      ; (sempre)
lp: lda bd_g
    sta (bd_pb),y
    lda #COL_GREEN
lk: sta (bd_kb),y
out:
    pla
    tax
    rts
.endproc

; Puntatore al glifo del carattere A nelle due celle di pagina zero p e p + 1.
.macro glyph_at p
    sta p
    lda #>CHARSET >> 3
    asl p
    rol a
    asl p
    rol a
    asl p
    rol a
    sta p+1
.endmacro

; Carattere fuso della cella del posto X: il glifo del carattere A (quello di sotto) con sopra
; quello del tratto bd_g, nel carattere SHOT_P0 + X. Rende il carattere in A, con C = 0. X e Y
; restano. Sta in fondo alla RAM bassa (FZCODE: in MAIN non c'è posto), copiato da title_unpack.
.segment "FZCODE"
.proc bd_fuse
    stx fz_x
    sty fz_y
    glyph_at fz_s
    lda bd_g
    glyph_at fz_g
    txa
    asl a
    asl a
    asl a
    bit fz_new
    bmi full
    ; la cella era già del fascio al frame prima: nel carattere fuso c'è già il glifo di sotto,
    ; con il tratto di prima nelle stesse due righe (la y di un colpo non cambia); solo quelle
    ora fz_r
    tax
    ldy fz_r
    lda (fz_s),y
    ora (fz_g),y
    sta CHARSET + 8 * SHOT_P0,x
    inx
    iny
    lda (fz_s),y
    ora (fz_g),y
    sta CHARSET + 8 * SHOT_P0,x
    bcc done                    ; (sempre: C = 0 dall'ultimo asl)
full:
    ora #7
    tax                         ; posto * 8 + 7: l'ultima riga del carattere fuso
    ldy #7
:   lda (fz_s),y
    ora (fz_g),y
    sta CHARSET + 8 * SHOT_P0,x
    dex
    dey
    bpl :-
done:
    lda fz_x                    ; (C = 0 dall'ultimo asl)
    adc #SHOT_P0
    ldx fz_x
    ldy fz_y
    rts
.endproc
.assert <CHARSET = 0 .and (>CHARSET & 7) = 0, error, "glyph_at: il set a una pagina multipla di 8"
.segment "BSS"
fz_r:   .res 1                  ; riga del tratto nella cella (0, 2, 4, 6) del colpo in esame
.segment "CODE"
.segment "CODE"

.endif
; Da bd_cell, con A = carattere sotto (da SH_LO in su): se è un colpo, da capo si continua (al
; frame dopo di nuovo da capo); per differenza ci si ferma, si cancella tutto (il colpo in esame
; ha a schermo solo le celle bd_k) e si ricomincia da capo. A resta.
.ifndef ROTATED                 ; (campo girato: rot_shots.s)
.proc bd_over
    cmp #SH_HI
    bcc shot
    cmp #SH2_LO
    bcc ok
    cmp #SH2_HI
    bcs ok
shot:
    bit bd_full
    bpl stop
    sec
    ror bd_dirty
ok: rts
stop:
    pla                         ; (le chiamate di bd_over e bd_cell, e il carattere di bd_cell)
    pla
    pla
    pla
    pla
    ldx bd_s
    lda bd_k
    sta sd_cw,x
    lda #1
    sta sv_n
    jsr shots_erase
    jmp next_shots::start
.endproc

; Toglie i colpi disegnati, rimettendo caratteri e colori (dall'ultimo colpo: con i fasci
; sovrapposti il carattere salvato da uno è quello dell'altro). Usa ptr, ptr2, n_t e v_col.
.proc shots_erase
    lda sv_n
    beq done
    ldx #2 * MAX_SHOTS - 1
loop:
    lda sd_cw,x
    cmp #$FF
    beq :+
    jsr erase_shot
:   dex
    bpl loop
    lda #0
    sta sv_n
done:
    rts
.endproc

; Come shots_erase, ma solo se un fascio a schermo è nelle righe 0-3 (riserve, barre, punteggi):
; chi ridisegna lì lo chiama prima. Basta il fascio alto (il basso è più giù), che al posto
; dell'alto sopra lo schermo è il basso. X resta; usa A, Y, ptr, ptr2, n_t e v_col.
.proc shots_off_hud
    lda sv_n
    beq done
    txa
    pha
    ldx #2 * MAX_SHOTS - 1
loop:
    lda sd_cw,x
    cmp #$FF
    beq next
    lda sv_ha,x
    cmp #>SCREEN
    bne next
    lda sv_la,x
    cmp #<(SCREEN + 4 * 40)
    bcs next
    jsr shots_erase
    jmp out
next:
    dex
    bpl loop
out:
    pla
    tax
done:
    rts
.endproc
.assert <SCREEN = 0, error, "shots_off_hud: righe 0-3 nella prima pagina dello schermo"

.endif
; Nel conto alla rovescia di NEXT (count_scene): i glifi dei fasci alle altezze 0-2 nei caratteri
; presi in prestito (da SHOT_B0, 7 per altezza), dal tratto dei caratteri del set (altezza 3, righe
; 6-7), circa 2.100 cicli. Fuori dalla partita next_shots li rimette vuoti, e al GAME OVER rifà le
; lettere 2x (sg_on: SG_GLYPHS, poi un passo alla volta fino a 0).
SG_GLYPHS = $FD                 ; glifi dei fasci nei caratteri presi in prestito
SG_BLANK  = $FE                 ; caratteri dei tratti di nuovo vuoti, lettere 2x da rifare
                                ; ($FF: fatta la prima metà)
.assert SHOT_LETTER0 = 0 .and SHOT_LETTERS = BIG2_N .and BIG2_N .mod 2 = 0, error, "next_shots: tutte le lettere 2x, in due metà"
SG_DST = CHARSET + 8 * SHOT_B0
SG_SRC = CHARSET + 8 * SHOT_OWN + 2 * SHOT_H0
.assert 8 * SHOT_BN <= 256 .and SHOT_BN = 3 * 7 .and SHOT_H0 = 3, error, "shot_glyphs: tre altezze prese (0-2), 168 byte"
.ifndef ROTATED                 ; (campo girato: rot_shots.s)
.proc shot_glyphs
    lda #SG_GLYPHS
    sta sg_on
    ldx #8 * SHOT_BN
    lda #0
:   sta SG_DST - 1,x
    dex
    bne :-
height:
    ldy #0                      ; tratto del carattere del set (passo 8)
glyph:
    lda SG_SRC,y
    sta SG_DST,x                ; X = 58 * altezza + 8 * carattere: riga 2 * altezza
    sta SG_DST + 1,x
    txa
    clc
    adc #8
    tax
    tya
    adc #8                      ; (C = 0)
    tay
    cpy #8 * 7
    bne glyph
    inx                         ; altezza dopo: il carattere dopo, due righe più giù
    inx
    cpx #3 * (8 * 7 + 2)
    bne height
    rts
.endproc

; Rimette le celle dei due fasci del colpo X (a schermo) e lo segna senza celle. X resta.
.proc erase_shot
    jsr bd_ptrs
    txa
    asl a
    asl a
    sta bd_x4
    lda sd_cw,x
    pha
    and #$7F
    tay
    and #1
    ora bd_x4
    tax
    jsr bd_rest
    pla
    bpl :+
    iny                         ; la seconda cella
    txa
    eor #1
    tax
    jsr bd_rest
:   lda bd_x4
    lsr a
    lsr a
    tax
    lda #$FF
    sta sd_cw,x
    lda col_bit,x
    eor #$FF
    and sd_on
    sta sd_on
    rts
.endproc

.endif
.segment "BSS"                  ; (non NEXTBSS: in fondo alla RAM bassa serve il posto a FZCODE)
bar_shown: .res 2               ; settori del muro a schermo
bar_prev:  .res 2               ; settori in piedi al frame prima
bar_flash: .res 2               ; frame di lampeggio rimasti
bar_fbit:  .res 2               ; e settore che lampeggia
sv_n:      .res 1               ; 0 niente a schermo, 1 colpi a schermo, $FF sovrapposti (da capo)
sv_la:     .res 2 * MAX_SHOTS   ; per colpo: riga del fascio alto (indirizzo della colonna 0)
sv_ha:     .res 2 * MAX_SHOTS
sv_lb:     .res 2 * MAX_SHOTS   ; e del fascio basso
sv_hb:     .res 2 * MAX_SHOTS
sv_c:      .res 8 * MAX_SHOTS   ; per cella (colpo * 4 + fascio * 2 + colonna & 1): carattere
sv_k:      .res 8 * MAX_SHOTS   ; e colore di prima
sd_y:      .res 2 * MAX_SHOTS   ; per colpo: parte intera della y dei fasci a schermo
sd_cw:     .res 2 * MAX_SHOTS   ; colonna della prima cella, bit 7 due celle; $FF niente a schermo
sd_on:     .res 1               ; colpi con celle a schermo (bit k: colpo k)
sg_on:     .res 1               ; 0, o SG_GLYPHS e seguenti: caratteri presi in prestito da rimettere
.segment "CODE"

.ifdef ROTATED
.include "rot_shots.s"
.endif

; ------------------------------------------------------------------------------------ effetti

; Dopo il tick della partita: colori del bullet time, scritte delle mosse speciali, rete
; dell'avversario e segni di STEER in cima e in fondo dove finisce la guida.
.proc next_fx_scene
    lda m_next
    bne :+
    rts
:   ldx #0                      ; bullet time: 1 in corso; bullet_look se a schermo è cambiato
    lda nx_btimer
    beq :+
    inx
:   cpx bl_on
    beq :+
    jsr bullet_look
:   lda sm_on                   ; le scritte delle mosse speciali, se c'è un colpo con la mossa,
    beq :+                      ; una scritta o una mossa armata (quasi mai)
    lda events+1
    and #EV_SPECIAL_HI
    ora mv_st
    ora mv_st+1
    ora sm_arm
    ora sm_arm+4
    beq :+
    jsr sm_labels
:   jsr net_tick                ; la rete dell'avversario
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
; 1.500 cicli, solo all'inizio e alla fine del BULLET, e con il frame avanti al prossimo. X = 1
; con il bullet time, 0 senza, diverso da bl_on (next_fx_scene).
.ifndef ROTATED                 ; (campo girato: rot_video.s)
.proc bullet_look
    jsr frame_late
    bcs done
    stx bl_on
    lda look_color,x
    sta m_t
    jsr shots_erase             ; i colpi rimetterebbero i colori di prima
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

.endif
.segment "RODATA"
look_color: .byte COL_WHITE, COL_GRAY  ; senza e con il bullet time
.segment "CODE"

.ifndef ROTATED                 ; (campo girato: rot_video.s)
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
    lda #COL_YELLOW
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

.endif
.segment "NEXTBSS"
st_drawn:  .res 1               ; segni di STEER a schermo: 0, o 1 + lato di chi guida
bl_on:     .res 1               ; colori del bullet time a schermo
.segment "CODE"

; ------------------------------------------------------------------------------------ anteprima

; Scelta della racchetta: la racchetta sotto il cursore a grandezza reale (sprite 3 e 4 come in
; partita), nel campo sotto la griglia (paddle_ui.rs, PADDLE_X) e con il davanti verso la
; mezzeria: TWIST dritta, BLASTER con il caricatore pieno. Poi i cursori (kpick.s). Le astronavi
; sono in due metà come in partita: la metà alta dalla riga PV_TOP, la bassa dalla riga del centro
; PV_S, dove lo split del raster (kp_split) cambia Y e puntatori (pose_load di video.s).
PV_CY = 13 * 8 + 36             ; centro del campo (riga in pixel)
PV_S   = SPR_Y0 + PV_CY         ; riga del cambio di sprite
PV_TOP = PV_S - PAD_ROWS
.assert (PV_S & 7) <> 3 .and ((PV_S - 1) & 7) <> 3, error, "anteprima: il cambio di sprite in una badline"

.proc pick_preview
.ifdef ROTATED
    jmp rp_preview              ; (campo girato: le astronavi della partita)
.else
    lda #0
    sta sh_enable
    lda hw_pg                   ; nella HOW TO PLAY nessuna anteprima
    beq :+
    rts
:   lda pk_kind
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
    jsr pose_load               ; la sua posa dalla cartuccia (A = tipo, Y = lato); se non è il
    ldy pi_side                 ; momento resta quella di prima, e si riprova al prossimo frame
    bcs place
    lda pk_cursor,y
    sta pv_kind,y
place:
    ldy pi_side
    lda pv_kind,y
    cmp #$ff
    beq next                    ; immagine non ancora fatta
    tax
    lda pose_top,y
    sta sh_ptr+SPN_PAD,y
    lda kind_col,x
    sta sh_col+SPN_PAD,y
    lda bit_of+SPN_PAD,y
    ora sh_enable
    sta sh_enable
    lda bit_of+SPN_PAD,y
    ora sh_mc
    sta sh_mc
    lda bit_of+SPN_PAD,y        ; non espanso
    eor #$ff
    pha
    and sh_yexp
    sta sh_yexp
    pla
    and sh_xexp
    sta sh_xexp
    ; x: la faccia dell'astronave dove c'era il corpo della racchetta senza tipo
    lda pv_x,y
    jsr pad_face_x
    sta sh_x+SPN_PAD,y
    lda bit_of+SPN_PAD,y
    eor #$ff
    and sh_msb
    sta sh_msb
    ; y: la metà alta finisce alla riga del centro (la posa è centrata nelle sue 42 righe)
    lda #PV_TOP
    sta sh_y+SPN_PAD,y
next:
    iny
    cpy #2
    jne side
done:
    jmp KP_RUN + 3
.endif
.endproc

.segment "RODATA"
; righe dello sprite per tipo (altezza in pixel / 2, per eccesso), varianti dell'anteprima
.macro pv_rows_of h0, h1, h2, h3, h4, h5, h6, h7
    .byte ((h0 >> 16) + 1) / 2, ((h1 >> 16) + 1) / 2, ((h2 >> 16) + 1) / 2, ((h3 >> 16) + 1) / 2
    .byte ((h4 >> 16) + 1) / 2, ((h5 >> 16) + 1) / 2, ((h6 >> 16) + 1) / 2, ((h7 >> 16) + 1) / 2
.endmacro
.ifndef ROTATED                 ; (campo girato: le anteprime sono le astronavi, rp_preview)
pv_rows: pv_rows_of T_KIND_H
pv_x:    .byte SPR_X0 + 14 * 8 + 4 - 12, SPR_X0 + 25 * 8 + 4 - 12
.endif
.assert SPR_X0 + 25 * 8 + 4 - 12 < 256, error, "anteprime: bit alto della x"
.segment "NEXTBSS"
pv_kind: .res 2                 ; tipo nell'immagine dell'anteprima ($ff nessuna)
.segment "CODE"

.ifndef ROTATED                 ; (campo girato: le anteprime sono le astronavi, rp_preview)
; A + 8 - pad_dx del tipo X sul lato Y: la x di uno sprite di racchetta con la faccia dove sarebbe
; il corpo della racchetta senza tipo con lo sprite ad A. X e Y restano.
.proc pad_face_x
    stx m_lo
    cpy #0
    beq :+
    pha
    txa
    ora #8
    tax
    pla
:   clc
    adc #8
    sec
    sbc pad_dx,x
    ldx m_lo
    rts
.endproc
.endif
