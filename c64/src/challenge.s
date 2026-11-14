; Modalità CHALLENGE (rust/core/src/challenge.rs, schermate come rust/game/src/challenge_ui.rs e il
; MiSTer): da soli contro i 7 avversari della scala, con bonus e racchetta scelti una volta.
; Presentazione dell'avversario, partita NEXT, livello superato o continue (un gettone, stesso
; livello, punti da zero); alla fine iniziali e classifica dei 10 migliori, salvata nella flash
; della cartuccia.
;
; Punti arcade come `Score::on_tick`: colpi, scatti riusciti e SUPER di chi gioca, punti segnati,
; con il moltiplicatore che sale di uno ogni CH_RALLY_STEP colpi dello scambio.
;
; Nuovo sfidante (challenge_ui.rs): nella presentazione, nella partita
; contro la CPU e nel livello superato (non l'ultimo) entra il giocatore del lato libero con il
; fuoco del suo joystick (porta 2 a sinistra, porta 1 a destra; con i paddle il pulsante del suo
; paddle), se c'è un credito o in Free Play. HERE COMES A NEW CHALLENGER!, poi lo sfidante sceglie
; bonus e racchetta e i due giocano NEXT ai punti e alla velocità del livello. Il vincitore riprende
; il livello dal suo lato (ch_side), con i punti di Score::after_duel; prima il perdente, se era il
; campione e il suo miglior punteggio entra in classifica, mette le iniziali.

CH_INTRO_FRAMES  = 200          ; 4 s
CH_CLEAR_FRAMES  = 200
CH_CONT_FRAMES   = 500          ; 10 s
CH_INIT_FRAMES   = 1500         ; 30 s
CH_SCORES_FRAMES = 400          ; 8 s
CH_SKIP_FRAMES   = 60           ; prima non si salta (niente salti per sbaglio)
CH_CHAL_FRAMES   = 150          ; HERE COMES A NEW CHALLENGER!: 3 s
CG_LADDER        = 1            ; cg_active: la scala contro la CPU
CG_DUEL          = 2            ; sfida tra il campione e un nuovo sfidante (da quando entra)
JOIN_ROW         = 0            ; invito per lo sfidante
CH_ENTRY         = 8            ; riga della classifica: iniziali (3), punti (4), livello
OPT_CHALLENGE    = 4            ; opt_players

.segment "RODATA"
rung_kind:    .byte T_RUNG_KIND
rung_cpu:     .byte T_RUNG_CPU
rung_speed:   .byte T_RUNG_SPEED
rung_points:  .byte T_RUNG_POINTS
rung_loadout: .byte T_RUNG_LOADOUT
pow10:        .dword 1000000, 100000, 10000, 1000, 100, 10, 1
; lettere delle iniziali, come rust/game/src/challenge_ui.rs: il "!" dopo lo spazio
letters:      .byte "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 !"
LETTERS = * - letters

.segment "BSS"
cg_active: .res 1               ; 0 fuori da CHALLENGE, CG_LADDER, CG_DUEL
ch_side:   .res 1               ; lato di chi gioca contro la CPU * 4 (dopo una sfida anche 4)
ch_load:   .res 6               ; bonus di ciascun lato (come pk_chosen): il campione tiene i suoi
ch_kinds:  .res 2               ; racchetta di ciascun lato
ch_loser:  .res 1               ; iniziali del perdente di una sfida, poi riprende il vincitore
.segment "ZEROPAGE"
ch_level:  .res 1
.segment "BSS"
ch_score:  .res 4
ch_best:   .res 4
ch_best_lv: .res 1
ch_rally:  .res 2
ch_before: .res 2               ; punti di chi gioca prima del tick
ch_shown:  .res 4               ; punti e moltiplicatore a schermo in partita
ch_mshown: .res 1
ch_bonus:  .res 4               ; premi del livello (vittoria, partita perfetta)
ch_rank:   .res 1
ch_pos:    .res 1
ch_letter: .res 1
ch_name:   .res 3
ch_hl:     .res 1               ; riga della classifica in evidenza ($ff nessuna)
ch_attract: .res 1              ; classifica dell'attract (poi la demo)
ch_timer:  .res 2
ch_phase:  .res 1               ; 1: schermo da pulire, 2: da disegnare
ch_elapsed: .res 1              ; frame dall'inizio della schermata (fino a 255)
ch_more:   .res 1               ; il disegno continua al prossimo frame
ch_digit:  .res 1
ch_go:     .res 1               ; presentazione finita: la partita al prossimo frame; nel continue
                                ; il GAME OVER dopo il conto alla rovescia
.segment "ZEROPAGE"
ch_tmp:    .res 4
.segment "BSS"
ch_txt:    .res 8
.segment "LOWBSS"               ; (si vede anche nel modo Ultimax: src/ef.s la scrive da qui)
ch_table:  .res CH_TABLE * CH_ENTRY
hi_tail:   .res 3               ; HI_MAGIC e il controllo, per il salvataggio
hi_next:   .res 1               ; posto della flash del prossimo salvataggio ($80: niente)
.segment "BSS"
win_points: .res 1              ; punti per vincere la partita
bm_cpu:    .res 1               ; livello della CPU e difficoltà della prossima partita
bm_diff:   .res 1

.segment "CODE"

; ------------------------------------------------------------------------------------ scala

; Dalle scelte di NEXT: la scala dal primo livello, chi gioca a sinistra.
.proc ch_start
    lda #CG_LADDER
    sta cg_active
    jsr ch_keep
    lda #0
    sta ch_level
    sta ch_side
    sta ch_loser
    jsr zero_score
    ldx #3
:   sta ch_best,x
    dex
    bpl :-
    lda #1
    sta ch_best_lv
    jmp enter_intro
.endproc

.proc zero_score
    lda #0
    ldx #3
:   sta ch_score,x
    dex
    bpl :-
    rts
.endproc

; La partita del livello: bonus e racchetta di chi gioca dal suo lato (Rung::sides), avversario
; del livello dall'altro, velocità della palla dalla difficoltà del menu (Rung::speed_at), primo ai
; punti del livello (rung_points).
.proc ch_begin
    lda #1
    sta cfg_next
    ; chi gioca: i suoi bonus (ch_load dal lato * 3)
    ldx ch_side
    ldy #0
    txa
    beq :+
    ldy #3
:   lda #3
    sta ch_tmp
:   lda ch_load,y
    sta cfg_loadout,x
    inx
    iny
    dec ch_tmp
    bne :-
    ; la CPU dall'altro lato: quelli del livello
    lda ch_side
    eor #4
    tax
    lda ch_level
    asl a
    adc ch_level                ; livello * 3
    tay
    lda #3
    sta ch_tmp
:   lda rung_loadout,y
    sta cfg_loadout,x
    inx
    iny
    dec ch_tmp
    bne :-
    ; racchette
    lda ch_side
    lsr a
    lsr a
    tay
    ldx ch_side
    lda ch_kinds,y
    sta cfg_kinds,x
    txa
    eor #4
    tax
    ldy ch_level
    lda rung_kind,y
    sta cfg_kinds,x
    jsr ch_rung
    lda #0
    sta ch_rally
    sta ch_rally+1
    lda #1
    sta screen_clear
    jmp begin_match
.endproc

; Partita al livello in corso: CPU, punti per vincere e velocità della palla (speed_at: velocità
; del livello + difficoltà - 1, tra 0 e 3). Anche per la sfida tra due giocatori.
.proc ch_rung
    ldx ch_level
    lda rung_cpu,x
    sta bm_cpu
    lda rung_points,x
    sta win_points
    lda rung_speed,x
    clc
    adc opt_level
    sec
    sbc #1
    bpl :+
    lda #0
:   cmp #4
    bcc :+
    lda #3
:   sta bm_diff
    rts
.endproc

; Bonus e racchette scelti, di tutti e due i lati, da parte per la scala.
.proc ch_keep
    ldx #5
:   lda pk_chosen,x
    sta ch_load,x
    dex
    bpl :-
    lda pk_cursor
    sta ch_kinds
    lda pk_cursor+1
    sta ch_kinds+1
    rts
.endproc

; La sfida, dopo le scelte dello sfidante (start_next prosegue con i bonus e le racchette scelti
; e begin_match senza CPU): i punti e la velocità del livello.
.proc ch_duel_prep
    jsr ch_keep
    jmp ch_rung
.endproc

; Dopo il tick: punti arcade (Score::on_tick) di chi gioca, dal lato ch_side; non nella sfida.
.proc ch_tick
    lda cg_active
    cmp #CG_LADDER
    beq :+
    rts
:   lda events
    and #EV_HIT | EV_BOOST | EV_SUPER
    beq points
    inc ch_rally
    bne :+
    inc ch_rally+1
    bne :+
    dec ch_rally                ; satura a $FFFF
    dec ch_rally+1
:   ; chi ha colpito: la palla ora si allontana da lui (vx > 0: il sinistro, se no il destro)
    ldy #4
    lda ball_vx+3
    bmi :+
    ora ball_vx+2
    ora ball_vx+1
    ora ball_vx
    beq :+
    ldy #0
:   cpy ch_side
    bne points
    jsr mult
    ldy #CH_HIT
    jsr add_mult
    lda events
    and #EV_BOOST
    beq :+
    lda #CH_BOOST
    jsr add_a
:   lda events
    and #EV_SUPER
    beq points
    lda #CH_SUPER
    jsr add_a
points:
    lda events
    and #EV_SCORE
    beq done
    ; solo se i punti di chi gioca sono saliti (score > prima, 16 bit)
    ldx ch_side
    lda ch_before
    cmp score,x
    lda ch_before+1
    sbc score+1,x
    bcs :+
    jsr mult
    ldy #CH_POINT
    jsr add_mult
:   lda #0
    sta ch_rally
    sta ch_rally+1
done:
    ldx ch_side
    lda score,x
    sta ch_before
    lda score+1,x
    sta ch_before+1
    rts
.endproc

; A = moltiplicatore dello scambio: 1 + colpi / CH_RALLY_STEP, al massimo CH_MAX_MULT.
.proc mult
    lda ch_rally+1
    bne max
    lda ch_rally
    lsr a
    lsr a
    clc
    adc #1
    cmp #CH_MAX_MULT
    bcc :+
max:
    lda #CH_MAX_MULT
:   rts
.endproc

; Punti += Y * A (A <= 8).
.proc add_mult
    tax
:   tya
    jsr add_a
    dex
    bne :-
    rts
.endproc

; Punti += A.
.proc add_a
    clc
    adc ch_score
    sta ch_score
    bcc :+
    inc ch_score+1
    bne :+
    inc ch_score+2
    bne :+
    inc ch_score+3
:   rts
.endproc

; Punti += ch_tmp (16 bit).
.proc add_tmp
    clc
    lda ch_score
    adc ch_tmp
    sta ch_score
    lda ch_score+1
    adc ch_tmp+1
    sta ch_score+1
    bcc :+
    inc ch_score+2
    bne :+
    inc ch_score+3
:   rts
.endproc

; Miglior punteggio della sessione (va in classifica) con il livello A raggiunto.
.proc remember
    tax
    lda ch_best+3
    cmp ch_score+3
    bne :+
    lda ch_best+2
    cmp ch_score+2
    bne :+
    lda ch_best+1
    cmp ch_score+1
    bne :+
    lda ch_best
    cmp ch_score
:   bcs done                    ; best >= score
    ldy #3
:   lda ch_score,y
    sta ch_best,y
    dey
    bpl :-
    stx ch_best_lv
done:
    rts
.endproc

; Fine di una partita CHALLENGE (dopo il GAME OVER): livello superato o continue; dopo la sfida
; riprende il vincitore.
.proc ch_after
    lda cg_active
    cmp #CG_DUEL
    bne :+
    jmp duel_over
:   ldx ch_side
    txa
    eor #4
    tay
    lda score,x
    cmp score,y
    beq lost
    bcs won
lost:
    jmp enter_cont
won:
    jmp enter_clear
.endproc

; Fine della scala: le iniziali se il miglior punteggio entra in classifica.
.proc ch_finish
    lda #0
    sta cg_active
    jsr table_rank
    sta ch_rank
    cmp #CH_TABLE
    bcs :+
    jmp enter_initials
:   lda #$ff
    sta ch_hl
    lda #0
    sta ch_attract
    jmp enter_scores
.endproc

; A = posizione di ch_best in classifica (CH_TABLE se non entra): la prima riga con meno punti.
.proc table_rank
    ldx #0
    ldy #0                      ; Y = X * 8: punti della riga da ch_table + 3,y (4 byte)
row:
    lda ch_best+3
    cmp ch_table+6,y
    bne :+
    lda ch_best+2
    cmp ch_table+5,y
    bne :+
    lda ch_best+1
    cmp ch_table+4,y
    bne :+
    lda ch_best
    cmp ch_table+3,y
    beq next
:   bcs found                   ; best > riga
next:
    tya
    clc
    adc #CH_ENTRY
    tay
    inx
    cpx #CH_TABLE
    bne row
found:
    txa
    rts
.endproc

; ------------------------------------------------------------------------------------ schermate

; Prepara una schermata della scala: scena A, durata in X:Y frame; lo schermo si pulisce e si
; disegna nei due frame dopo (ch_phase).
.proc ch_screen
    sta state
    stx ch_timer
    sty ch_timer+1
    lda #0
    sta sh_enable
    sta sh_bg
    lda #MODE_TEXT
    sta sh_mode
    lda #1
    sta ch_phase
    lda #0
    sta ch_elapsed
    rts
.endproc

; Fasi comuni: C = 1 se il frame è servito a pulire o disegnare (A = routine di disegno in ptr2).
.proc ch_phases
    lda ch_phase
    beq none
    cmp #1
    bne draw
    inc ch_phase
    lda #COL_WHITE
    jsr clear_text
    sec
    rts
draw:
    lda #0
    sta ch_more
    jsr jmp_ptr2
    lda ch_more                 ; da finire al prossimo frame
    bne :+
    sta ch_phase
:   sec
    rts
none:
    ; tempo
    lda ch_timer
    bne :+
    dec ch_timer+1
:   dec ch_timer
    inc ch_elapsed
    bne :+
    dec ch_elapsed
:   clc
    rts
.endproc

.proc jmp_ptr2
    jmp (ch_draw)
.endproc

; C = 1 se il tempo è finito.
; Niente continue: GAME OVER, la partita è finita davvero (con la sua musica e per il suo tempo,
; come quello sopra la partita), poi iniziali o classifica (cont_scene, ch_finish).
.proc cont_over
    inc ch_go
    lda #<draw_cont_over
    sta ch_draw
    lda #>draw_cont_over
    sta ch_draw+1
    lda #SID_SONG_GAME_OVER
    jsr sid_song
    lda #ST_CONT
    ldx #<AT_GAME_OVER_FRAMES
    ldy #>AT_GAME_OVER_FRAMES
    jmp ch_screen
.endproc

.proc draw_cont_over
    ldx #OV_GAME_OVER
    ldy #11
    jmp over_big
.endproc

.proc ch_timeout
    lda ch_timer
    ora ch_timer+1
    bne :+
    sec
    rts
:   clc
    rts
.endproc

; C = 1 se si può saltare la schermata (passato il primo secondo) e chi gioca preme Start.
.proc ch_skip
    lda ch_elapsed
    cmp #CH_SKIP_FRAMES
    bcc no
    jmp champ_start
no:
    clc
    rts
.endproc

; Numero ch_tmp (32 bit) in ch_txt: 7 cifre ASCII e lo 0 finale.
.proc num7
    ldx #0                      ; cifra
    ldy #0                      ; indice in pow10
digit:
    lda #'0'
    sta ch_txt,x
sub:
    lda ch_tmp
    sec
    sbc pow10,y
    sta m_lo
    lda ch_tmp+1
    sbc pow10+1,y
    sta m_t
    lda ch_tmp+2
    sbc pow10+2,y
    sta m_b
    lda ch_tmp+3
    sbc pow10+3,y
    bcc next
    sta ch_tmp+3
    lda m_b
    sta ch_tmp+2
    lda m_t
    sta ch_tmp+1
    lda m_lo
    sta ch_tmp
    inc ch_txt,x
    jmp sub
next:
    iny
    iny
    iny
    iny
    inx
    cpx #7
    bne digit
    lda #0
    sta ch_txt+7
    rts
.endproc

; Punti (ch_score) come 7 cifre alla colonna X, riga Y.
.proc print_score
    lda ch_score
    sta ch_tmp
    lda ch_score+1
    sta ch_tmp+1
    lda ch_score+2
    sta ch_tmp+2
    lda ch_score+3
    sta ch_tmp+3
.endproc
; ch_tmp come 7 cifre alla colonna X, riga Y (prosegue da print_score).
.proc print_tmp
    stx v_col
    sty v_row
    jsr num7
    lda #<ch_txt
    sta ptr2
    lda #>ch_txt
    sta ptr2+1
    ldx v_col
    ldy v_row
    jmp print_str
.endproc

; --- presentazione dell'avversario

.proc enter_intro
    ldx ch_level                ; il file voce dell'avversario dalla cartuccia (src/ef.s)
    lda rung_kind,x
    jsr ef_voice
    lda #0
    sta ch_go
    lda #<draw_intro
    sta ch_draw
    lda #>draw_intro
    sta ch_draw+1
    lda #SID_SONG_INTRO
    jsr sid_song
    lda #ST_INTRO
    ldx #<CH_INTRO_FRAMES
    ldy #>CH_INTRO_FRAMES
    jmp ch_screen
.endproc

INTRO_COL0    = 10              ; colonne dei bonus: centri alle celle 10, 20 e 30
INTRO_STEP    = 10
INTRO_CAP_ROW = 13              ; capsule nelle righe 13-14, nomi nella 15

.proc draw_intro
    ; LEVEL n OF 7, o FINAL LEVEL
    lda ch_level
    cmp #CH_LEVELS - 1
    bne :+
    jsr print_at
    .byte 14, 3, "FINAL LEVEL", 0
    jmp :++
:   jsr print_at
    .byte 14, 3, "LEVEL   OF 7", 0
    lda ch_level
    clc
    adc #'1'
    ldx #20
    ldy #3
    sty v_row
    jsr put_ascii
:   lda #COL_YELLOW
    ldy #3
    jsr color_row
    ; racchetta (centrata, kind_col), frase e bonus dell'avversario
    ldx ch_level
    lda rung_kind,x
    tax
    asl a
    tay
    lda kind_names,y
    sta ptr2
    lda kind_names+1,y
    sta ptr2+1
    lda kind_col,x
    tax
    ldy #8
    jsr print_str
    ldx ch_level
    lda rung_kind,x
    asl a
    tay
    lda kind_tags,y
    sta ptr2
    lda kind_tags+1,y
    sta ptr2+1
    ldx #12
    ldy #10
    jsr print_str
    lda #COL_GRAY
    ldy #10
    jsr color_row
    ; bonus dell'avversario: capsula gialla con l'icona e nome sotto, su tre colonne centrate
    lda ch_level
    asl a
    adc ch_level
    sta ch_tmp                  ; primo bonus del livello
    lda #INTRO_COL0
    sta ch_tmp+1                ; centro della colonna: la cella a destra del centro
bonus:
    ldy ch_tmp
    lda rung_loadout,y
    sta ch_tmp+2
    asl a
    asl a
    asl a                       ; bonus * 8: capsula normale
    tay
    lda #INTRO_CAP_ROW
    sta v_row
    ldx ch_tmp+1
    dex
    jsr put_cap
    lda ch_tmp+2
    asl a
    tay
    lda bonus_names,y
    sta ptr2
    lda bonus_names+1,y
    sta ptr2+1
    ; nome centrato sotto la capsula: lunghezza fino allo spazio (o allo 0)
    ldy #0
:   lda (ptr2),y
    beq :+
    cmp #' '
    beq :+
    iny
    bne :-
:   tya
    lsr a
    sta m_t
    lda ch_tmp+1
    sec
    sbc m_t
    tax
    ldy #INTRO_CAP_ROW + 2
    jsr print_str
    inc ch_tmp
    lda ch_tmp+1
    clc
    adc #INTRO_STEP
    sta ch_tmp+1
    cmp #INTRO_COL0 + 3 * INTRO_STEP
    bne bonus
    lda #COL_YELLOW
    ldy #INTRO_CAP_ROW
    jsr color_row
    lda #COL_YELLOW
    ldy #INTRO_CAP_ROW + 1
    jsr color_row
    lda #COL_YELLOW
    ldy #INTRO_CAP_ROW + 2
    jsr color_row
    ; punti per vincere (una o due cifre)
    jsr print_at
    .byte 15, INTRO_CAP_ROW + 5, "FIRST TO", 0
    ldx ch_level
    lda rung_points,x
    cmp #10
    bcc :+
    ldx #24
    ldy #INTRO_CAP_ROW + 5
    jsr print_num2
    jmp :++
:   adc #'0'
    ldx #24
    ldy #INTRO_CAP_ROW + 5
    sty v_row
    jsr put_ascii
:   lda #COL_GRAY
    ldy #INTRO_CAP_ROW + 5
    jsr color_row
    ; punti e record
    jsr print_at
    .byte 7, 22, "SCORE           HI", 0
    ldx #13
    ldy #22
    jsr print_score
    ldx #0
:   lda ch_table+3,x
    sta ch_tmp,x
    inx
    cpx #4
    bne :-
    ldx #26
    ldy #22
    jmp print_tmp
.endproc

.proc intro_scene
    lda ch_go
    beq :+
    jmp ch_begin
:   jsr VOICE_TICK              ; la voce, 0,5 s dopo il primo frame
    jsr ch_phases
    bcs done
    jsr ch_join                 ; nuovo sfidante
    bcc :+
    jsr VOICE_STOP
    jmp enter_challenger
:   jsr join_hint
    jsr ch_skip
    bcs go
    jsr ch_timeout
    bcc done
go:
    ; la partita: schermo pulito qui, partita al prossimo frame (poi le immagini degli effetti
    ; prendono il posto del file voce, non della parte che resta); con il file voce la musica è il
    ; tema dell'avversario, che il file ha già copiato a THEME_BASE (senza file VOICE_STOP è un
    ; RTS: resta A = 0, silenzio)
    lda #0
    jsr VOICE_STOP
    sta match_song
    inc ch_go
    lda #COL_WHITE
    jmp clear_text
done:
    rts
.endproc

; --- livello superato

.proc enter_clear
    ; premi: vittoria (1000 * livello) e partita perfetta (2000 * livello) se l'avversario è a 0
    ldx ch_level
    inx
    stx ch_tmp+2
    lda ch_side                 ; punti della CPU: 0 per la partita perfetta
    eor #4
    tax
    lda score,x
    sta ch_tmp+3
    lda #0
    sta ch_bonus
    sta ch_bonus+1
    sta ch_bonus+2
    sta ch_bonus+3
:   clc
    lda ch_bonus
    adc #<CH_WIN
    sta ch_bonus
    lda ch_bonus+1
    adc #>CH_WIN
    sta ch_bonus+1
    lda ch_tmp+3
    bne :+
    clc
    lda ch_bonus+2
    adc #<CH_PERFECT
    sta ch_bonus+2
    lda ch_bonus+3
    adc #>CH_PERFECT
    sta ch_bonus+3
:   dec ch_tmp+2
    bne :--
    lda ch_bonus
    sta ch_tmp
    lda ch_bonus+1
    sta ch_tmp+1
    jsr add_tmp
    lda ch_bonus+2
    sta ch_tmp
    lda ch_bonus+3
    sta ch_tmp+1
    jsr add_tmp
    ; livello raggiunto: il prossimo, o 8 a scala finita
    lda ch_level
    clc
    adc #2
    jsr remember
    ; l'ultimo avversario: il finale (ending.s)
    lda ch_level
    cmp #CH_LEVELS - 1
    beq end_enter
    lda #<draw_clear
    sta ch_draw
    lda #>draw_clear
    sta ch_draw+1
    lda #SID_SONG_CLEAR
    jsr sid_song
    lda #ST_CLEAR
    ldx #<CH_CLEAR_FRAMES
    ldy #>CH_CLEAR_FRAMES
    jmp ch_screen
.endproc

; Il finale di CHALLENGE (ending.s): la sua prima pagina dalla cartuccia, poi lei copia il resto.
.proc end_enter
    lda #$80
    sta ef_src+2
    lda #END_BANK
    ldx #1
    ldy #>END_RUN
    jsr ef_copy
    jmp end_init
.endproc

.proc draw_clear
    jsr print_at
    .byte 13, 5, "LEVEL   CLEAR", 0
    lda ch_level
    clc
    adc #'1'
    ldx #19
    ldy #5
    sty v_row
    jsr put_ascii
    lda #COL_YELLOW
    ldy #5
    jsr color_row
    jsr print_at
    .byte 12, 11, "WIN BONUS  +", 0
    lda ch_bonus
    ldx ch_bonus+1
    ldy #11
    jsr print_bonus
    lda ch_bonus+2
    ora ch_bonus+3
    beq :+
    jsr print_at
    .byte 12, 13, "PERFECT    +", 0
    lda ch_bonus+2
    ldx ch_bonus+3
    ldy #13
    jsr print_bonus
    lda #COL_YELLOW
    ldy #13
    jsr color_row
:   jsr print_at
    .byte 13, 17, "SCORE", 0
    ldx #19
    ldy #17
    jsr print_score
    jsr print_at
    .byte 14, 21, "PRESS START", 0
    lda #COL_GRAY
    ldy #21
    jmp color_row
.endproc

; Premio A:X (16 bit) senza zeri davanti dalla colonna 24, riga Y (righe centrate con 4 cifre).
.proc print_bonus
    sta ch_tmp
    stx ch_tmp+1
    lda #0
    sta ch_tmp+2
    sta ch_tmp+3
    sty v_row
    jsr num7
    ldx #0
:   lda ch_txt,x
    cmp #'0'
    bne :+
    inx
    cpx #6
    bne :-
:   txa
    clc
    adc #<ch_txt
    sta ptr2
    lda #>ch_txt
    adc #0
    sta ptr2+1
    ldx #24
    ldy v_row
    jmp print_str
.endproc

.proc clear_scene
    jsr ch_phases
    bcs done
    ; nuovo sfidante (dopo l'ultimo livello c'è il finale): la sfida è al livello dopo, quello che
    ; il vincitore affronterà
    jsr ch_join
    bcc :+
    inc ch_level
    jmp enter_challenger
:   jsr join_hint
    jsr ch_skip
    bcs go
    jsr ch_timeout
    bcc done
go:
    inc ch_level
    jmp enter_intro
done:
    rts
.endproc

; --- nuovo sfidante

; X = lato di chi gioca (0 sinistro, 1 destro).
.proc champ_joy
    lda ch_side
    lsr a
    lsr a
    tax
    rts
.endproc

; C = 1 se chi gioca (lato ch_side) preme Start: il suo fuoco, RETURN, SPAZIO o 1. Il fuoco del
; lato libero è dello sfidante.
.proc champ_start
    jsr champ_joy
    lda fire_edge,x
    beq :+
    sec
    rts
:   jmp start_keys
.endproc

; Gettone (tasto 5) e Start dello sfidante, il fuoco del lato libero (con i paddle il pulsante del
; suo paddle): C = 1 se entra, con un credito che si consuma o in Free Play.
.proc ch_join
    lda #KEY_5
    jsr key_pressed
    bcc start
    lda opt_free
    bne start
    lda credits
    cmp #MAX_CREDITS
    bcs start
    inc credits
    lda state                   ; in partita l'effetto passa da fx_pend (il frame può essere avanti)
    cmp #ST_PLAY
    bne :+
    lda fx_pend
    ora #EV_COIN
    sta fx_pend
    jmp start
:   lda #EV_COIN
    jsr sid_fx
start:
    jsr champ_joy
    txa
    eor #1
    tax
    lda fire_edge,x
    beq no
    lda opt_free
    bne yes
    lda credits
    beq no
    dec credits
yes:
    sec
    rts
no:
    clc
    rts
.endproc

; Nella partita contro la CPU (anche nel conto alla rovescia): C = 1 se è entrato uno sfidante. La
; partita si interrompe, i punti arcade fatti restano a chi gioca.
.proc ch_join_match
    lda cg_active
    cmp #CG_LADDER
    bne no
    jsr ch_join
    bcc no
    lda ch_level
    clc
    adc #1
    jsr remember
    jsr enter_challenger
    sec
    rts
no:
    clc
    rts
.endproc

; Invito per lo sfidante, a tratti, in alto sul lato libero: P2 PRESS START (o P1), INSERT COIN
; senza crediti (draw_join_hint del PC).
.proc join_hint
    ldx #25                     ; colonna: il lato libero è a destra
    lda ch_side
    beq :+
    ldx #1
:   stx ch_tmp+3
    ldy #0
    lda frame_count
    and #$20
    beq :+
    ldy #2
    lda opt_free
    ora credits
    bne :+
    ldy #4
:   sty ch_tmp+2
    lda join_texts,y
    sta ptr2
    lda join_texts+1,y
    sta ptr2+1
    ldy #JOIN_ROW
    jsr print_str
    lda ch_tmp+2
    beq color
    ldx ch_tmp+3                ; P1 o P2: il numero del lato libero
    inx
    lda #'2'
    ldy ch_side
    beq :+
    lda #'1'
:   ldy #JOIN_ROW
    sty v_row
    jsr put_ascii
color:
    lda #JOIN_LEN
    sta v_n
    ldy ch_tmp+3
    ldx #JOIN_ROW
    lda #COL_GRAY
    jmp color_span
.endproc

join_texts:   .word s_join_off, s_join_start, s_join_coin
s_join_off:   .byte "              ", 0
s_join_start: .byte "P  PRESS START", 0
s_join_coin:  .byte "P  INSERT COIN", 0
JOIN_LEN = 14

; HERE COMES A NEW CHALLENGER! (Challenger del PC): la scala si ferma, il jingle della presentazione
; riparte da capo; dopo 3 secondi lo sfidante sceglie bonus e racchetta.
.proc enter_challenger
    lda #CG_DUEL
    sta cg_active
    lda #<draw_challenger
    sta ch_draw
    lda #>draw_challenger
    sta ch_draw+1
    lda #0
    jsr sid_song
    lda #SID_SONG_INTRO
    jsr sid_song
    lda #EV_BOOST
    jsr sid_fx
    lda #ST_CHALLENGER
    ldx #<CH_CHAL_FRAMES
    ldy #>CH_CHAL_FRAMES
    jmp ch_screen
.endproc

CHAL_BAND0 = 5                  ; bande piene in alto e in basso
CHAL_BAND1 = 19
CHAL_ROW0  = 9                  ; HERE COMES
CHAL_ROW1  = 12                 ; A NEW CHALLENGER!
CHAL_ROW2  = 16                 ; chi sfida e punti

.proc draw_challenger
    ldy #CHAL_BAND0
    jsr solid_row
    ldy #CHAL_BAND1
    jsr solid_row
    jsr print_at
    .byte 15, CHAL_ROW0, "HERE COMES", 0
    jsr print_at
    .byte 11, CHAL_ROW1, "A NEW CHALLENGER!", 0
    jsr print_at
    .byte 6, CHAL_ROW2, "P  VS CHAMPION   FIRST TO", 0
    lda #'2'                    ; lo sfidante: P2 se chi gioca è a sinistra
    ldy ch_side
    beq :+
    lda #'1'
:   ldx #7
    ldy #CHAL_ROW2
    sty v_row
    jsr put_ascii
    ldx ch_level
    lda rung_points,x
    ldx #32
    ldy #CHAL_ROW2
    jsr print_points
    jmp challenger_colors
.endproc

; Lampeggio: le due scritte si scambiano giallo e bianco, le bande giallo e grigio.
.proc challenger_colors
    lda frame_count
    lsr a
    lsr a
    lsr a
    and #1
    sta ch_tmp+3
    tax
    lda chal_col_a,x
    ldy #CHAL_BAND0
    jsr color_row
    ldx ch_tmp+3
    lda chal_col_b,x
    ldy #CHAL_BAND1
    jsr color_row
    ldx ch_tmp+3
    lda chal_col_c,x
    ldy #CHAL_ROW0
    jsr color_row
    ldx ch_tmp+3
    lda chal_col_d,x
    ldy #CHAL_ROW1
    jmp color_row
.endproc

chal_col_a: .byte COL_YELLOW, COL_GRAY      ; banda alta
chal_col_b: .byte COL_GRAY, COL_YELLOW      ; banda bassa
chal_col_c: .byte COL_WHITE, COL_YELLOW     ; HERE COMES
chal_col_d: .byte COL_YELLOW, COL_WHITE     ; A NEW CHALLENGER!

.proc challenger_scene
    jsr ch_phases
    bcs done
    jsr challenger_colors
    jsr ch_timeout
    bcc done
    jmp pick_challenger
done:
    rts
.endproc

; Riga Y piena (CH_SOLID), del colore che ha.
.proc solid_row
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    ldy #39
    lda #CH_SOLID
:   sta (ptr),y
    dey
    bpl :-
    rts
.endproc

; Punti A (una o due cifre) alla colonna X, riga Y.
.proc print_points
    cmp #10
    bcc :+
    jmp print_num2
:   adc #'0'
    sty v_row
    jmp put_ascii
.endproc

; Fine della sfida (duel_over del PC, dopo il GAME OVER): vince chi ha più punti (a parità il
; destro). Il vincitore riprende il livello in corso con Score::after_duel punti: il campione i
; suoi più il premio, lo sfidante il premio. Se vince lo sfidante, prima il campione mette le
; iniziali se il suo miglior punteggio entra in classifica.
.proc duel_over
    lda #CG_LADDER
    sta cg_active
    ldx #4
    lda score+4
    cmp score
    bcs :+
    ldx #0
:   cpx ch_side
    bne challenger
    jsr add_duel_bonus
    jmp duel_resume
challenger:
    jsr table_rank
    sta ch_rank
    cmp #CH_TABLE
    bcs :+
    lda #1
    sta ch_loser
    jmp enter_initials
:   jsr duel_takeover
.endproc
; Il vincitore riprende il livello dalla presentazione (prosegue da duel_over).
.proc duel_resume
    lda ch_level
    clc
    adc #1
    jsr remember
    jmp enter_intro
.endproc

; Ha vinto lo sfidante: gioca lui, dal suo lato, da 0 punti più il premio (prosegue in
; add_duel_bonus); il suo miglior punteggio della sessione riparte da zero.
.proc duel_takeover
    lda ch_side
    eor #4
    sta ch_side
    jsr zero_score              ; A = 0
    ldx #3
:   sta ch_best,x
    dex
    bpl :-
    lda #1
    sta ch_best_lv
.endproc
; Punti += premio della sfida, Score::duel_bonus: CH_WIN * (livello + 1).
.proc add_duel_bonus
    ldx ch_level
    inx
    lda #0
    sta ch_tmp
    sta ch_tmp+1
:   clc
    lda ch_tmp
    adc #<CH_WIN
    sta ch_tmp
    lda ch_tmp+1
    adc #>CH_WIN
    sta ch_tmp+1
    dex
    bne :-
    jmp add_tmp
.endproc

; --- continue

.proc enter_cont
    lda ch_level
    clc
    adc #1
    jsr remember
    lda #$ff
    sta ch_digit
    lda #0
    sta ch_go
    lda #<draw_cont
    sta ch_draw
    lda #>draw_cont
    sta ch_draw+1
    lda #SID_SONG_CONTINUE
    jsr sid_song
    lda #ST_CONT
    ldx #<CH_CONT_FRAMES
    ldy #>CH_CONT_FRAMES
    jmp ch_screen
.endproc

.proc draw_cont
    jsr print_at
    .byte 15, 5, "CONTINUE?", 0
    lda #COL_YELLOW
    ldy #5
    jsr color_row
    jsr print_at
    .byte 7, 18, "LEVEL     SCORE RESETS TO 0", 0
    lda ch_level
    clc
    adc #'1'
    ldx #13
    ldy #18
    sty v_row
    jsr put_ascii
    lda #COL_GRAY
    ldy #18
    jmp color_row
.endproc

.proc cont_scene
    jsr ch_phases
    jcs done
    lda ch_go                   ; GAME OVER: poi iniziali o classifica
    beq :+
    jsr ch_timeout
    jcc done
    jmp ch_finish
:   ; gettone
    lda #KEY_5
    jsr key_pressed
    bcc :+
    lda opt_free
    bne :+
    lda credits
    cmp #MAX_CREDITS
    bcs :+
    inc credits
    lda #EV_COIN
    jsr sid_fx
:   ; continue: Start con un credito (o Free Play)
    jsr ch_skip
    bcc wait
    lda opt_free
    bne go
    lda credits
    beq wait
    dec credits
go:
    jsr zero_score
    jmp enter_intro
wait:
    jsr ch_timeout
    bcc :+
    jmp cont_over
:   ; secondi rimasti (cifra grande al centro), con un colpo a ogni secondo
    lda ch_timer
    sta ch_tmp
    lda ch_timer+1
    sta ch_tmp+1
    ldx #0
:   lda ch_tmp
    ora ch_tmp+1
    beq got
    inx
    lda ch_tmp
    sec
    sbc #50
    sta ch_tmp
    lda ch_tmp+1
    sbc #0
    sta ch_tmp+1
    bcs :-
got:
    cpx #10
    bcc :+
    ldx #9
:   cpx ch_digit
    beq prompt
    stx ch_digit
    txa
    ldx #18
    ldy #9
    jsr draw_digit
    lda #EV_WALL
    jsr sid_fx
prompt:
    ; PRESS START o INSERT COIN, a tratti
    lda frame_count
    and #$20
    beq off
    lda opt_free
    ora credits
    beq coin
    jsr print_at
    .byte 14, 15, "PRESS START", 0
    rts
coin:
    jsr print_at
    .byte 14, 15, "INSERT COIN", 0
    rts
off:
    jsr print_at
    .byte 14, 15, "           ", 0
done:
    rts
.endproc

; --- iniziali

.proc enter_initials
    lda #0
    sta ch_pos
    sta ch_letter
    lda #<draw_initials
    sta ch_draw
    lda #>draw_initials
    sta ch_draw+1
    lda #SID_SONG_CHAMPION
    jsr sid_song
    lda #ST_INITIALS
    ldx #<CH_INIT_FRAMES
    ldy #>CH_INIT_FRAMES
    jmp ch_screen
.endproc

.proc draw_initials
    jsr print_at
    .byte 14, 4, "NEW RECORD!", 0
    lda #COL_YELLOW
    ldy #4
    jsr color_row
    jsr print_at
    .byte 13, 7, "SCORE", 0
    ldx #0
:   lda ch_best,x
    sta ch_tmp,x
    inx
    cpx #4
    bne :-
    ldx #19
    ldy #7
    jsr print_tmp
    lda ch_loser
    beq :+
    jsr print_at
    .byte 9, 10, "P  ENTER YOUR INITIALS", 0
    jsr champ_joy               ; P1 o P2: il lato del perdente
    txa
    clc
    adc #'1'
    ldx #10
    ldy #10
    sty v_row
    jsr put_ascii
    jmp :++
:   jsr print_at
    .byte 10, 10, "ENTER YOUR INITIALS", 0
:   jsr print_at
    .byte 13, 20, "UP DOWN + FIRE", 0
    lda #COL_GRAY
    ldy #10
    jsr color_row
    lda #COL_GRAY
    ldy #20
    jmp color_row
.endproc

.proc initials_scene
    jsr ch_phases
    jcs done
    ; lettera con su e giù (joystick o cursori); dopo una sfida solo il joystick del perdente
    lda ch_loser
    beq :+
    jsr champ_joy
    lda joy_edge,x
    jmp :++
:   lda joy_edge
    ora joy_edge+1
:   sta m_t
    lda #KEY_CRSR_UD
    jsr key_pressed
    bcc :+
    lda m_t
    ora #JOY_DOWN
    sta m_t
:   lda m_t
    and #JOY_UP
    beq :+
    dec ch_letter
    bpl :+
    lda #LETTERS - 1
    sta ch_letter
:   lda m_t
    and #JOY_DOWN
    beq :+
    inc ch_letter
    lda ch_letter
    cmp #LETTERS
    bcc :+
    lda #0
    sta ch_letter
:   ; conferma con fuoco, Invio o spazio; a tempo scaduto valgono le lettere sotto il cursore
    jsr ch_timeout
    bcs confirm
    lda ch_loser
    beq :+
    jsr champ_start             ; il perdente gioca ancora dal lato ch_side
    bcc draw
    bcs confirm
:   jsr start_pressed
    bcc draw
confirm:
    ldx ch_pos
    ldy ch_letter
    lda letters,y
    sta ch_name,x
    lda #EV_HIT
    jsr sid_fx
    inc ch_pos
    lda ch_pos
    cmp #3
    bcc draw
    jsr egg_check
    jmp table_insert
draw:
    ; le tre lettere: quelle scelte bianche, quella in corso gialla e a tratti, le altre punti
    ldx #0
:   stx m_lo
    lda #'.'
    cpx ch_pos
    bcc chosen
    bne put
    ; a tratti: spenta 8 frame ogni 32 (0,16 s su 0,64), accesa il resto, come il cursore del PC
    ; e del MiSTer (prima il bit 7 del contatore: 2,5 s accesa e 2,5 s spenta)
    ldy ch_letter
    lda frame_count
    and #$18
    cmp #$18                    ; C = 1 negli 8 frame spenti
    lda letters,y               ; (C resta)
    bcc put
    lda #' '
    jmp put
chosen:
    lda ch_name,x
put:
    pha
    txa
    asl a
    adc #17
    tax
    ldy #14
    sty v_row
    pla
    jsr put_ascii
    ldx m_lo
    inx
    cpx #3
    bne :-
    lda #COL_WHITE
    ldy #14
    jsr color_row
    lda ch_pos
    cmp #3
    bcs done
    asl a
    adc #17
    tay
    lda #1
    sta v_n
    ldx #14
    lda #COL_YELLOW
    jsr color_span
done:
    rts
.endproc

; Easter egg, come egg_after di rust/game/src/challenge_ui.rs: le iniziali "RED" lo accendono e la
; volta dopo lo spengono, fino allo spegnimento (il record si salva come gli altri). Giallo e rosso
; si scambiano ovunque: color_span per le scritte, egg_yel ed egg_red dove i colori si scrivono
; direttamente, $D026 per i segni delle racchette; al posto della canzone del titolo quella del
; finale, letta dalla cartuccia (egg_song, SID_SONG_EGG). Si vede subito nella classifica.
.proc egg_check
    ldx #2
:   lda ch_name,x
    cmp egg_name,x
    bne done
    dex
    bpl :-
    ldx #3
:   lda egg_x,x
    eor egg_flip,x
    sta egg_x,x
    dex
    bpl :-
    lda egg_yel
    sta $d026                   ; segni gialli delle racchette (multicolore %11)
done:
    rts
.endproc
egg_name: .byte "RED"
; egg_x, egg_yel, egg_red ed egg_song (video.s, in quest'ordine)
egg_flip: .byte COL_YELLOW ^ COL_RED, COL_YELLOW ^ COL_RED, COL_YELLOW ^ COL_RED
          .byte SID_SONG_TITLE ^ SID_SONG_EGG
.assert egg_yel = egg_x + 1 .and egg_red = egg_x + 2 .and egg_song = egg_x + 3, error, "variabili dell'easter egg in fila"

; Nuova riga in classifica alla posizione ch_rank (le altre scendono), salvata nella flash; poi la
; classifica con la riga in evidenza.
.proc table_insert
    ; da ch_rank in giù di una riga: dall'ultimo byte della penultima riga
    lda ch_rank
    asl a
    asl a
    asl a
    sta m_lo                    ; primo byte della riga
    ldx #(CH_TABLE - 1) * CH_ENTRY - 1
:   cpx m_lo
    bcc :+
    lda ch_table,x
    sta ch_table + CH_ENTRY,x
    dex
    cpx #$ff
    bne :-
:   ldx m_lo
    lda ch_name
    sta ch_table,x
    lda ch_name+1
    sta ch_table+1,x
    lda ch_name+2
    sta ch_table+2,x
    lda ch_best
    sta ch_table+3,x
    lda ch_best+1
    sta ch_table+4,x
    lda ch_best+2
    sta ch_table+5,x
    lda ch_best+3
    sta ch_table+6,x
    lda ch_best_lv
    sta ch_table+7,x
    jsr hi_save
    lda ch_loser                ; dopo una sfida riprende il vincitore
    beq :+
    lda #0
    sta ch_loser
    jsr duel_takeover
    jmp duel_resume
:   lda ch_rank
    sta ch_hl
    lda #0
    sta ch_attract
    jmp enter_scores
.endproc

; --- classifica

; Il codice della classifica (disegno della tabella, scena) sta nella
; cartuccia (segmento HSCODE, nel .prg da HS_IMG, dopo le mosse speciali) e girano a HS_RUN, nella
; bitmap dell'attract: nella classifica lo schermo è a caratteri, e dopo la classifica la bitmap si
; rifà sempre da capo (strisce). Lo copia hs_load nel primo frame di disegno, quando a schermo c'è
; già il testo pulito: la copia non si vede. Nel programma restano enter_scores, hs_load e l'inizio
; di scores_scene (le fasi comuni, prima della copia).
HS_RUN   = $E000                ; dove gira (paddws.cfg, HSRAM)
HS_IMG   = $DC00                ; dove sta nel .prg (HSIMG), poi nella flash
HS_BANK  = PRG_BANK + (HS_IMG - $0800) / $4000
HS_SRC   = $80 + ((HS_IMG - $0800) .mod $4000) / 256
HS_PAGES = >(__HSCODE_SIZE__ + 255)
.import __HSCODE_LOAD__, __HSCODE_RUN__, __HSCODE_SIZE__
.assert __HSCODE_LOAD__ = HS_IMG .and __HSCODE_RUN__ = HS_RUN, lderror, "classifica fuori posto"
.assert ((HS_IMG - $0800) .mod $4000) + $0400 <= $2000, error, "classifica oltre la ROML del banco"

; Classifica (ch_hl in evidenza); ch_attract = 1 dall'attract (poi la demo).
.proc enter_scores
    lda #0
    sta pk_i                    ; prima riga da disegnare
    lda #<hs_load
    sta ch_draw
    lda #>hs_load
    sta ch_draw+1
    lda #ST_SCORES
    ldx #<CH_SCORES_FRAMES
    ldy #>CH_SCORES_FRAMES
    jmp ch_screen
.endproc

; Primo frame di disegno: il codice della classifica dalla cartuccia (circa 3.800 cicli a pagina),
; poi hs_init prepara il resto.
.proc hs_load
    lda #HS_SRC
    sta ef_src+2
    lda #HS_BANK
    ldx #HS_PAGES
    ldy #>HS_RUN
    jsr ef_copy
    jmp hs_init
.endproc

; Le fasi comuni (pulizia, disegno); il resto nella cartuccia, copiato nella fase di disegno.
.proc scores_scene
    jsr ch_phases
    bcs :+
    jmp hs_scene
:   rts
.endproc

.segment "HSCODE"

; Dopo la copia (hs_load): il disegno della tabella dal prossimo frame.
.proc hs_init
    lda #<draw_scores_table
    sta ch_draw
    lda #>draw_scores_table
    sta ch_draw+1
    inc ch_more
    rts
.endproc

; Quattro righe per frame (tutta la tabella non sta nel budget).
.proc draw_scores_table
    lda pk_i
    bne :+
    jsr print_at
    .byte 9, 1, "CHALLENGE HIGH SCORES", 0
    lda #COL_YELLOW
    ldy #1
    jsr color_row
:   lda pk_i
    clc
    adc #4
    sta pk_ok                   ; fine di questo frame
row:
    ; riga Y = 4 + 2 * i: posto, iniziali, punti, livello, centrati (colonne 8-31)
    lda pk_i
    asl a
    adc #4
    sta pk_p                    ; riga
    lda pk_i
    clc
    adc #'1'
    cmp #'9' + 1
    bne :+
    lda #'1'                    ; 10: "10"
    ldx #8
    ldy pk_p
    sty v_row
    jsr put_ascii
    lda #'0'
:   ldx #9
    ldy pk_p
    sty v_row
    jsr put_ascii
    lda pk_i
    asl a
    asl a
    asl a
    tax
    stx pk_dirty                ; inizio della riga
    lda ch_table,x
    ldx #13
    jsr put_ascii
    ldx pk_dirty
    lda ch_table+1,x
    ldx #14
    jsr put_ascii
    ldx pk_dirty
    lda ch_table+2,x
    ldx #15
    jsr put_ascii
    ldx pk_dirty
    ldy #0
:   lda ch_table+3,x
    sta ch_tmp,y
    inx
    iny
    cpy #4
    bne :-
    ldx #19
    ldy pk_p
    jsr print_tmp
    ; livello: L1-L7, ALL a scala finita
    ldx pk_dirty
    lda ch_table+7,x
    cmp #CH_LEVELS + 1
    bcc :+
    jsr print_all
    jmp color
:   pha
    lda #'L'
    ldx #29
    ldy pk_p
    sty v_row
    jsr put_ascii
    pla
    clc
    adc #'0'
    ldx #30
    jsr put_ascii
color:
    lda #COL_WHITE
    ldx pk_i
    cpx ch_hl
    bne :+
    lda #COL_YELLOW
:   ldy pk_p
    jsr color_row
    inc pk_i
    lda pk_i
    cmp #CH_TABLE
    beq last
    cmp pk_ok
    jne row
    inc ch_more
    rts
last:
    lda #COL_GRAY
    ldy #24
    jmp color_row
.endproc

.proc print_all
    lda #'A'
    ldx #29
    ldy pk_p
    sty v_row
    jsr put_ascii
    lda #'L'
    ldx #30
    jsr put_ascii
    lda #'L'
    ldx #31
    jmp put_ascii
.endproc

; La classifica con la tabella già disegnata (da scores_scene).
.proc hs_scene
    ; come nell'attract: gettone e Start
    jsr coin_and_start
    bcs done
    lda frame_count
    and #$20
    beq off
    lda opt_free
    ora credits
    beq coin
    jsr print_at
    .byte 14, 24, "PRESS START", 0
    jmp time
coin:
    jsr print_at
    .byte 14, 24, "INSERT COIN", 0
    jmp time
off:
    jsr print_at
    .byte 14, 24, "           ", 0
time:
    jsr ch_timeout
    bcc done
    ; dall'attract la demo (testo pulito qui, demo al prossimo frame), dopo una partita le strisce
    lda ch_attract
    beq :+
    lda #ST_TITLE
    sta state
    lda #2
    sta demo_prep
    lda #COL_WHITE
    jmp clear_text
:   jmp go_stripes
done:
    rts
.endproc


.segment "CODE"

; ------------------------------------------------------------------------------------ in partita

; Punti arcade in basso dalla parte dell'avversario (a destra, a sinistra se chi gioca è a destra,
; come sul PC e sul MiSTer) e moltiplicatore (x2-x8) sopra, quando cambiano; nella sfida niente.
.proc ch_hud
    lda cg_active
    cmp #CG_LADDER
    beq :+
    rts
:   ; moltiplicatore (poco lavoro), poi i punti (le cifre costano: solo con il frame indietro)
    jsr mult
    cmp ch_mshown
    beq digits
    pha
    jsr frame_late              ; frame già avanti: al prossimo
    pla
    bcs digits
    sta ch_mshown
    pha
    jsr shots_erase
    pla
    ldy #23
    sty v_row
    cmp #2
    bcs :+
    lda #' '
    jsr put_ascii38
    lda #' '
    jmp put_ascii39
:   adc #'0' - 1                ; C = 1
    pha
    lda #'X'
    jsr put_ascii38
    pla
    jsr put_ascii39
digits:
    ldx #3
:   lda ch_score,x
    cmp ch_shown,x
    bne draw
    dex
    bpl :-
    rts
draw:
    jsr frame_late
    bcc :+
    rts
:   jsr shots_erase
    ldx #3
:   lda ch_score,x
    sta ch_shown,x
    dex
    bpl :-
    ldx #32
    lda ch_side
    beq :+
    ldx #1
:   ldy #24
    jmp print_score
put_ascii38:
    ldx #38
    ldy ch_side
    beq :+
    ldx #0
:   jmp put_ascii
put_ascii39:
    ldx #39
    ldy ch_side
    beq :+
    ldx #1
:   jmp put_ascii
.endproc

; Punti da ridisegnare (schermo della partita nuovo).
.proc ch_hud_reset
    lda #$ff
    sta ch_shown
    sta ch_mshown
    ldx ch_side
    lda score,x
    sta ch_before
    lda score+1,x
    sta ch_before+1
    rts
.endproc

; ------------------------------------------------------------------------------------ classifica nella flash

; All'avvio, prima di clear_vars (nel segmento INIT: classifica e posto sono nella pagina $0200,
; che clear_vars non tocca): la classifica iniziale, poi l'ultima salvata nella cartuccia (src/ef.s).
; I posti del banco HI_BANK si leggono a HI_SCAN; quelli scritti si susseguono dal primo, il primo
; libero (primo byte $FF: le iniziali non lo sono mai) è dove andrà il prossimo salvataggio. Vale
; l'ultimo posto completo (HI_MAGIC e l'EOR giusto): uno scritto a metà, per uno spegnimento, no.
.segment "INIT"
.proc hi_load
    ldx #CH_TABLE * CH_ENTRY - 1    ; la classifica iniziale
:   lda table_init,x
    sta ch_table,x
    dex
    bpl :-
    lda #HI_BANK - VOICE_BANK0
    jsr ef_voice
    lda #<HI_SCAN
    sta ptr
    lda #>HI_SCAN
    sta ptr+1
    ldx #0
slot:
    ldy #0
    lda (ptr),y
    cmp #$ff
    beq done
    ldy #HI_REC - 3
    lda (ptr),y
    cmp #<HI_MAGIC
    bne next
    iny
    lda (ptr),y
    cmp #>HI_MAGIC
    bne next
    ldy #HI_REC - 1
    lda #0
:   eor (ptr),y
    dey
    bpl :-
    cmp #HI_SEED
    bne next
    ldy #CH_TABLE * CH_ENTRY - 1
:   lda (ptr),y
    sta ch_table,y
    dey
    bpl :-
next:
    lda ptr
    eor #HI_SLOT                ; posti da 128 byte: due per pagina
    sta ptr
    bne :+
    inc ptr+1
:   inx
    cpx #HI_SLOTS
    bne slot
done:
    stx hi_next
    rts
.endproc
table_init: .byte T_TABLE
.segment "CODE"

; Salva la classifica nel posto hi_next della flash; con i posti finiti, o un posto non cancellato
; (la flash della EasyFlash vera può avere i dati di prima), cancella il settore e scrive nel primo.
; Se non si scrive nemmeno lì la cartuccia non si lascia scrivere: niente più salvataggi (hi_next
; con il bit 7). Musica muta durante la scrittura (interrupt spenti: circa 1 ms, 1 s cancellando).
.proc hi_save
    lda hi_next
    bmi off
    ; dopo la classifica HI_MAGIC e il byte che porta l'EOR di tutto il posto a HI_SEED
    lda #<HI_MAGIC
    sta hi_tail
    lda #>HI_MAGIC
    sta hi_tail+1
    ldx #HI_REC - 2
    lda #HI_SEED
:   eor ch_table,x
    dex
    bpl :-
    sta hi_tail+2
    lda #0
    sta SID + $18
    lda hi_next
    cmp #HI_SLOTS
    bcs erase
    jsr write
    bcc done
erase:
    jsr ef_hi_erase
    lda #0
    sta hi_next
    bcs fail
    jsr write
    bcc done
fail:
    lda #$80
    sta hi_next
done:
    jsr sid_set_vol             ; il volume del menu, con il modo del filtro
off:
    rts
; posto hi_next: $8000 + hi_next * 128
write:
    lda hi_next
    lsr a
    tay                         ; (C: posto dispari)
    lda #0
    ror a
    tax
    tya
    ora #$80
    tay
    jsr ef_hi_write
    bcs :+
    inc hi_next
:   rts
.endproc
.assert hi_tail = ch_table + CH_TABLE * CH_ENTRY, error, "il posto della classifica non è di seguito"

.segment "ZEROPAGE"
ch_draw: .res 2                 ; routine di disegno della schermata
.segment "CODE"
