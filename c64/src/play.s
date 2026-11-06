; Ciclo dei frame e scene: attract (auto-test all'accensione, strisce, logo, titolo, demo), menu,
; conto alla rovescia, partita, GAME OVER; gettoni e crediti.
;
; Un interrupt di raster alla riga 250 segna l'inizio del vblank: lì si copiano i registri ombra
; nel VIC, poi si leggono i comandi ed esegue un tick (uno per frame, a 50 Hz). Il tempo delle
; scene è contato in frame.

RASTER_LINE = 250
; COUNT_FRAMES (3 secondi di conto alla rovescia prima della prima battuta) è in voice.inc
FLASH_FRAMES = 3                ; lampo bianco del punto (0,05 s sul PC)
POINTS_TO_WIN = 11
LIVES = 3
MAX_CREDITS = 9
DEMO_LEVEL = 1                  ; la demo è EVO a due, difficoltà e CPU Normal (come sul MiSTer)

; scene (indice nella tabella `scenes`); le prime cinque sono l'attract
ST_BOOT    = 0
ST_STRIPES = 1
ST_LOGO    = 2
ST_TITLE   = 3
ST_DEMO    = 4
ST_MENU    = 5
ST_COUNT   = 6
ST_PLAY    = 7
ST_OVER    = 8
ST_PICK    = 9                  ; NEXT: scelta dei bonus e della racchetta (pick.s)
ST_INTRO   = 10                 ; CHALLENGE (challenge.s): presentazione dell'avversario
ST_CLEAR   = 11                 ; livello superato
ST_CONT    = 12                 ; continue
ST_INITIALS = 13                ; iniziali
ST_SCORES  = 14                 ; classifica
ST_CHALLENGER = 15              ; nuovo sfidante: HERE COMES A NEW CHALLENGER!
ST_ENDING  = 16                 ; finale di CHALLENGE (ending.s)

EV_COIN = $10                   ; effetto del gettone nel player del SID

.segment "ZEROPAGE"
frame_flag:  .res 1
frame_count: .res 2
state:       .res 1

.segment "BSS"
.segment "ZEROPAGE"
opt_mode:    .res 1             ; 0 CLASSIC, 1 EVO, 2 NEXT
.segment "BSS"
.segment "ZEROPAGE"
opt_players: .res 1             ; 1 singolo, 2 in due, 3 contro la CPU
.segment "BSS"
opt_level:   .res 1
.segment "ZEROPAGE"
opt_free:    .res 1             ; Free Play
.segment "BSS"
opt_asound:  .res 1             ; suoni dell'attract (gettone e Start si sentono sempre)
opt_border:  .res 1             ; bordo in partita: 0 BLACK, 1 GRAY (border_game)
.segment "ZEROPAGE"
credits:     .res 1
.segment "BSS"
timer:       .res 1             ; frame rimasti della scena (conto alla rovescia, GAME OVER)
cd_digit:    .res 1             ; cifra del conto alla rovescia a schermo
lives:       .res 1             ; palle del singolo
flash:       .res 1
paused:      .res 1
menu_sel:    .res 1             ; voce selezionata del menu
menu_i:      .res 1             ; voce in disegno (print_str usa v_n)
demo_label:  .res 1             ; demo: scritta a schermo (0 nessuna, 1 INSERT COIN, 2 PRESS START)
demo_credit: .res 1             ; demo: riga dei crediti a schermo (variante + 1)
demo_prep:   .res 1             ; titolo finito: 1 = pulire il testo, 2 = entrare nella demo
screen_clear: .res 1            ; begin_match: schermo di testo già pulito nel frame prima
over_next: .res 1               ; partita finita: GAME OVER al prossimo frame
fx_pend:   .res 1               ; effetti sonori rimandati dal frame prima (già avanti)
match_song: .res 1              ; musica della prossima partita: il tema di CHALLENGE, o 0
cpu_side:  .res 1               ; lato della CPU in partita * 4 ($ff nessuna)
win_pg:    .res 1               ; YOU WIN nel GAME OVER: 0 no, 1-16 prossima pagina + 1, poi detta

.segment "CODE"

; ------------------------------------------------------------------------------------ interrupt

.segment "BOOTCODE"           ; solo all'avvio (unpack.s)
.proc irq_init
    lda #$7f
    sta $dc0d                   ; niente interrupt dai CIA
    sta $dd0d
    lda $dc0d
    lda $dd0d
    lda #<irq_handler
    sta $fffe
    lda #>irq_handler
    sta $ffff
    lda #<nmi_handler
    sta $fffa
    lda #>nmi_handler
    sta $fffb
    lda #RASTER_LINE
    sta $d012
    lda $d011
    and #$7f
    sta $d011
    lda #1
    sta $d01a
    lda #$ff
    sta $d019
    rts
.endproc
.segment "CODE"

.proc irq_handler
    pha
    inc frame_flag
    inc frame_count
    bne :+
    inc frame_count+1
:   lda #$ff
    sta $d019
    pla
    rti
.endproc

; RESTORE: ignorato. Sotto $8000: con il vettore dell'NMI nel file voce (bit 7 del byte alto)
; la musica tace (sid_tick, sid_fx).
.proc nmi_handler
    rti
.endproc
.assert nmi_handler < $8000 && VOICE_BASE >= $8000, error, "vettore dell'NMI: il bit 7 non distingue la voce"

; ------------------------------------------------------------------------------------ ciclo

.if .defined(ENDTEST)
; Build per le schermate del finale di CHALLENGE (-Define ENDTEST): l'ultimo livello appena vinto
; 5 a 0, con il player delle voci del file del primo livello in memoria come dopo una scala (la
; copia e i primi tre frame della presentazione). Tra le routine dell'avvio, che play_main trova
; ancora al loro posto, così non occupa il programma.
.segment "BOOTCODE"
.proc endtest_setup
    lda rung_kind
    jsr ef_voice
    jsr VOICE_TICK
    jsr VOICE_TICK
    jsr VOICE_TICK
    jsr VOICE_STOP
    lda #CG_LADDER
    sta cg_active
    lda #CH_LEVELS - 1
    sta ch_level
    lda #5
    sta score
    lda #0
    sta ch_side
    sta score+1
    sta score+4
    sta score+5
    lda #<123456
    sta ch_score
    lda #>123456
    sta ch_score+1
    lda #^123456
    sta ch_score+2
    jmp ch_after
.endproc
.segment "CODE"
.endif

.proc play_main
    lda #1
    sta opt_level
    sta opt_free
    sta opt_asound
    sta opt_border
    sta cfg_super               ; mosse speciali sempre accese (NEXT e CHALLENGE)
    lda #2                      ; all'accensione NEXT in CHALLENGE, come su PC e MiSTer
    sta opt_mode
    lda #OPT_CHALLENGE
    sta opt_players
    lda #0
    sta ctl_paddle
    sta credits
    sta screen_clear
.if .defined(ENDTEST)
    jsr endtest_setup           ; build per le schermate del finale (sotto, tra le routine dell'avvio)
.elseif .defined(AUTOSTART)
    lda #3                      ; build per le schermate: subito una partita EVO contro la CPU
    sta opt_players
    lda #1
.ifdef AUTONEXT
    lda #2                      ; (con AUTONEXT in NEXT, dalle scelte; con SMTEST due CPU, SMFULL:
.endif                          ; barre piene)
    sta opt_mode
.ifdef AUTOCHALLENGE
    lda #2                      ; (con AUTOCHALLENGE in CHALLENGE, dalle scelte)
    sta opt_mode
    lda #OPT_CHALLENGE
    sta opt_players
.endif
    jsr start_game
.else
    jsr boot_enter
    lda #ST_BOOT
    sta state
    jsr attract_song
.endif
loop:
    lda frame_flag
    beq loop
    lda #0
    sta frame_flag
    jsr frame
    jmp loop
.endproc

; Esegue la scena corrente (ognuna torna con rts).
.proc run_scene
    lda state
    asl a
    tax
    lda scenes+1,x
    pha
    lda scenes,x
    pha
    rts                         ; salta alla scena (indirizzo - 1 nella tabella)
.endproc

scenes:
    .word boot_scene - 1, stripes_scene - 1, logo_scene - 1, title_scene - 1, demo_scene - 1
    .word menu_scene - 1, count_scene - 1, play_scene - 1, over_scene - 1, pick_scene - 1
    .word intro_scene - 1, clear_scene - 1, cont_scene - 1, initials_scene - 1, scores_scene - 1
    .word challenger_scene - 1, end_scene - 1

; Un frame: registri ombra nel VIC (vblank), comandi, scena, sprite e musica. Il banco di prova
; (paddws-c64 frames) lo chiama per misurare i cicli di un frame intero. Prosegue in scene_done.
.proc frame
    jsr apply_shadows
    jsr read_input
    ; tabelle dei quadrati da rifare, fuori dalle scene in bitmap
    lda math_ready
    bne :+
    lda ch_phase                ; non mentre una schermata si prepara
    bne :+
    lda state
    beq step
    cmp #ST_TITLE + 1
    bcc :+
step:
    jsr math_step
:
    jsr next_shots              ; NEXT: colpi del BLASTER (caratteri), anche loro nel vblank
    jsr run_scene
.endproc                        ; (prosegue in scene_done)

; Dopo ogni scena: sprite e riserve di NEXT dallo stato della partita (demo e partita) e musica.
; Segue frame senza salto.
SID_TICK_MAX  = 2500            ; sid_tick (o sid_more) più pesante in partita, anche con il tempo
                                ; che cambia nel bullet time e con il filtro (paddws-c64 sid: i temi
                                ; fino a circa 2.260, al primo frame di HAMMER; fuori dalla partita il
                                ; primo frame del titolo arriva a circa 2.930)
SID_LATE      = 18000 - SID_TICK_MAX
SID_LATE_LINE = RASTER_LINE + SID_LATE / 58 - 312
KEEP_SPRITES_LINE = 14500 / 58  ; righe oltre le quali restano gli sprite del frame prima
.assert SID_LATE_LINE >= 56 && SID_LATE_LINE < RASTER_LINE, error, "SID_LATE_LINE fuori dalle righe 56-249"
.proc scene_done
    lda state
    cmp #ST_DEMO
    beq game
    cmp #ST_COUNT
    bcc other
    cmp #ST_OVER + 1
    bcs other
game:
    ; dopo un tick pesantissimo (frame già oltre circa 14.500 cicli: colpo con previsioni, capsula e
    ; BULLET insieme) restano gli sprite del frame prima: il resto aspetta comunque (frame_after).
    ; Sprite, riserve e controlli costano fino a circa 3.400 cicli: con la soglia più in alto un
    ; frame arriverebbe oltre il suo tempo e i controlli dopo troverebbero il raster "all'inizio"
    lda #KEEP_SPRITES_LINE
    jsr frame_after
    bcs :+
    jsr compute_sprites
:   jsr next_hud
    ; frame già troppo avanti per il player (il tema di CHALLENGE con due note nuove costa fino
    ; a circa 1.700 cicli): la musica aspetta il prossimo, come gli effetti (fx_pend), con le
    ; stesse scritture un frame dopo. Righe SID_LATE_LINE-249: il frame è oltre SID_LATE cicli
    jsr sid_time
    bcc late
    lda state                   ; in partita (non nella demo) il tempo della musica
    cmp #ST_DEMO
    beq :+
    jsr match_tempo
:   jsr sid_tick
    jsr border_game             ; (anche lui solo se il frame ha tempo)
    ; match point: il passo della canzone in più (uno ogni 4 frame), se c'è ancora tempo
    lda sid_extra
    beq late
    jsr sid_time
    bcc late
    jsr sid_more
late:
    jmp trail_end               ; NEXT: la coda della palla, se il frame ha ancora tempo
other:
    lda #0                      ; fuori dalla partita il tempo di sempre e il bordo dello sfondo
    sta sh_brd
    jsr sid_tempo
    lda state
    cmp #ST_PICK                ; scelta della racchetta: anteprime
    bne :+
    jsr pick_preview
:   jmp sid_tick
.endproc

; C = 0 se il frame è già oltre SID_LATE cicli (righe SID_LATE_LINE-249), 1 se c'è tempo; alle
; righe 250-311 solo se il frame è appena cominciato e non è un giro dopo (frame_flag, come in
; frame_after).
.proc sid_time
    lda $d011
    bmi early
    lda $d012
    cmp #RASTER_LINE
    bcs early
    sec
    sbc #SID_LATE_LINE
    cmp #RASTER_LINE - SID_LATE_LINE
    rts
early:
    lda #0
    cmp frame_flag              ; C = 1 solo senza un nuovo interrupt
    rts
.endproc

; Tempo della musica in partita, come Game::tempo del gioco Rust: match point (bit 0) in due, con
; uno dei giocatori a un punto dalla vittoria, fino alla fine della partita; bullet time (bit 7)
; con il BULLET scattato (anche nella rampa).
.proc match_tempo
    lda m_players
    cmp #2
    bne slow
    ldx win_points
    dex
    stx m_t
    lda score
    cmp m_t
    bcs fast
    lda score+4
    cmp m_t
fast:
    lda #0
    rol a                       ; C: a un punto dalla vittoria
    .byte $2c                   ; (bit: salta il lda)
slow:
    lda #0
    ldx m_next
    beq :+
    ldx nx_btimer
    beq :+
    ora #$80
:   jmp sid_tempo
.endproc

; Bordo della partita (sh_brd; apply_shadows lo usa con lo sfondo nero, quindi il lampo del punto
; resta bianco): con BORDER GRAY grigio scuro, così si vedono i limiti del campo; in partita giallo
; con il SUPER o una mossa speciale MAX in volo, grigio pulsante nel bullet time, rosso lento al
; match point (gli ultimi due dal tempo della musica, match_tempo). Con BLACK il bordo di sempre.
.proc border_game
    lda #0
    ldx opt_border
    beq set
    lda state
    cmp #ST_PLAY
    bne base
    lda m_next
    beq tempo
    lda nx_super                ; SUPER in volo
    bne yellow
    lda sm_fl                   ; mossa speciale di livello 2 in volo
    and #4
    bne yellow
tempo:
    lda frame_count
    bit sid_slow                ; bullet time
    bmi bullet
    ldx sid_fast                ; match point: rosso per 32 frame ogni 64
    beq base
    and #$20
    beq base
    lda egg_red                 ; (con l'easter egg giallo e rosso si scambiano)
    bne set
bullet:
    lsr a                       ; grigio scuro, medio, chiaro, medio: 8 frame ciascuno
    lsr a
    lsr a
    and #3
    tax
    lda bullet_grays,x
    bne set
yellow:
    lda egg_yel
    bne set
base:
    lda #COL_DGRAY
set:
    sta sh_brd
    rts
.endproc

bullet_grays: .byte COL_DGRAY, COL_MGRAY, COL_GRAY, COL_MGRAY

; ------------------------------------------------------------------------------------ attract

; Musica del titolo nell'attract, se i suoni dell'attract sono accesi.
.proc attract_song
    lda #0
    ldx opt_asound
    beq :+
    lda egg_song                ; SID_SONG_TITLE (con l'easter egg SID_SONG_EGG)
:   jmp sid_song
.endproc

; Gettone (tasto 5) e Start nell'attract: C = 1 se si va al menu.
.proc coin_and_start
    lda #KEY_5
    jsr key_pressed
    bcc start
    lda opt_free
    bne start
    lda credits
    cmp #MAX_CREDITS
    bcs start
    inc credits
    lda #EV_COIN
    jsr sid_fx
start:
    jsr start_pressed
    bcc no
    lda opt_free
    bne go
    lda credits
    beq no
    dec credits
go:
    lda #EV_HIT
    jsr sid_fx
    jsr enter_menu
    sec
    rts
no:
    clc
    rts
.endproc

; C = 1 se è stato premuto Start: fuoco (o pulsante del paddle), RETURN, SPAZIO o 1.
.proc start_pressed
    jsr any_fire
    bcc start_keys
    rts
.endproc

; C = 1 se è stato premuto RETURN, SPAZIO o 1.
.proc start_keys
    lda #KEY_RETURN
    jsr key_pressed
    bcs yes
    lda #KEY_SPACE
    jsr key_pressed
    bcs yes
    lda #KEY_1
    jmp key_pressed
yes:
    rts
.endproc

.proc boot_scene
    jsr coin_and_start
    bcs done
    jsr boot_frame
    bcc done
    jsr go_stripes
done:
    rts
.endproc

; Strisce: anche dopo il titolo, la demo, il GAME OVER e il menu.
.proc go_stripes
    jsr stripes_enter
    lda #ST_STRIPES
    sta state
    jmp attract_song
.endproc

.proc stripes_scene
    jsr coin_and_start
    bcs done
    jsr stripes_frame
    bcc done
    jsr logo_enter
    lda #ST_LOGO
    sta state
done:
    rts
.endproc

.proc logo_scene
    jsr coin_and_start
    bcs done
    jsr logo_frame
    bcc done
    jsr title_enter
    lda #ST_TITLE
    sta state
done:
    rts
.endproc

; Alla fine del titolo la demo entra in tre frame, perché il lavoro non sta in uno: il titolo
; finisce, poi si pulisce lo schermo di testo (non si vede, a schermo c'è la bitmap), poi la demo.
.proc title_scene
    jsr coin_and_start
    bcs done
    lda demo_prep
    beq title
    cmp #1
    beq clear
    lda #0
    sta demo_prep
    jmp demo_enter
clear:
    lda #COL_WHITE
    jsr clear_text
    inc demo_prep
    rts
title:
    jsr title_frame
    bcc done
    ; dopo il titolo la classifica di CHALLENGE (poi la demo), come sul MiSTer
    lda #$ff
    sta ch_hl
    lda #1
    sta ch_attract
    jmp enter_scores
done:
    rts
.endproc

; ------------------------------------------------------------------------------------ demo

; Partita dimostrativa: due CPU, EVO, difficoltà Normal.
.proc demo_enter
    jsr math_ensure
    lda #0
    sta cfg_next
    lda #2
    sta cfg_players
    lda #1
    sta cfg_evo
    lda #DEMO_LEVEL
    sta cfg_diff
    jsr seed_from_time
    jsr match_new
    lda #DEMO_LEVEL
    ldx #0
    jsr cpu_init
    lda #DEMO_LEVEL
    ldx #4
    jsr cpu_init
    jsr game_screen_draw        ; testo già pulito da title_scene
    lda #0
    sta at_f
    sta at_f+1
    sta demo_label
    sta demo_credit
    lda #ST_DEMO
    sta state
    rts
.endproc

.proc demo_scene
    jsr coin_and_start
    bcc :+
    rts
:   jsr flash_frame
    ldx #0
    jsr cpu_input
    ldx #4
    jsr cpu_input
    jsr dash_before
    jsr match_step
    jsr dash_after
    lda events
    and #EV_WALL | EV_HIT | EV_BOOST | EV_SCORE
    jsr at_sound
    lda events
    and #EV_SCORE
    beq :+
    lda #FLASH_FRAMES
    sta flash
    jsr draw_scores
:   jsr demo_overlay
    jsr at_tick
    lda at_f+1
    cmp #>AT_DEMO_FRAMES
    bcc done
    bne :+
    lda at_f
    cmp #<AT_DEMO_FRAMES
    bcc done
:   jsr go_stripes
done:
    rts
.endproc

DEMO_LABEL_W = BIG_PRESS_START_W
DEMO_BOX_C0 = (40 - DEMO_LABEL_W) / 2 - 1
DEMO_BOX_W = DEMO_LABEL_W + 2

; Scritte della demo: INSERT COIN / PRESS START che lampeggia al centro, crediti in alto a sinistra.
.proc demo_overlay
    ldx #0
    jsr blink_on
    bcc :+
    ldx #2
    jsr credit_variant
    bne :+
    ldx #1
:   cpx demo_label
    beq credit
    stx demo_label
    ; riquadro vuoto sopra il campo, poi la scritta; senza scritta torna la mezzeria
    lda #4
    sta v_n
    lda #DEMO_BOX_W
    ldx #DEMO_BOX_C0
    ldy #10
    jsr blank_box
    lda demo_label
    bne label
    lda #10
    sta v_row
:   jsr center_line_row
    inc v_row
    lda v_row
    cmp #14
    bne :-
    jmp credit
label:
    cmp #1
    bne press
    lda #<big_insert_coin
    sta ptr2
    lda #>big_insert_coin
    sta ptr2+1
    lda #BIG_INSERT_COIN_W
    ldx #(40 - BIG_INSERT_COIN_W) / 2
    jmp big
press:
    lda #<big_press_start
    sta ptr2
    lda #>big_press_start
    sta ptr2+1
    lda #BIG_PRESS_START_W
    ldx #(40 - BIG_PRESS_START_W) / 2
big:
    ldy #11
    jsr draw_big
credit:
    jsr credit_variant
    clc
    adc #1
    cmp demo_credit
    beq done
    sta demo_credit
    jmp print_credits
done:
    rts
.endproc

; "CREDIT n" o "FREE PLAY" in alto a sinistra (testo).
.proc print_credits
    lda opt_free
    beq :+
    jsr print_at
    .byte 1, 0, "FREE PLAY", 0
    rts
:   jsr print_at
    .byte 1, 0, "CREDIT   ", 0
    lda credits
    clc
    adc #'0'
    ldx #8
    ldy #0
    sty v_row
    jmp put_ascii
.endproc

; ------------------------------------------------------------------------------------ menu

MENU_ITEMS = 9
MI_GAME    = 0
MI_PLAYERS = 1
MI_LEVEL   = 2
MI_CONTROL = 3
MI_FREE    = 4
MI_ASOUND  = 5
MI_VOLUME  = 6                  ; volume del SID (opt_volume, sid_volume)
MI_BORDER  = 7                  ; bordo in partita (opt_border, border_game)
MI_PLAY    = 8
MENU_ROW0  = 4                  ; prima voce, una ogni 2 righe (fino alla 20)
MENU_COL   = 8
MENU_VCOL  = 25

.proc enter_menu
    lda #ST_MENU
    sta state
    lda #0
    sta sh_enable
    sta sh_bg
    lda #MODE_TEXT
    sta sh_mode
    jsr attract_song            ; anche nel menu la musica segue ATTRACT SOUND
    lda #MI_PLAY
    sta menu_sel
    lda #COL_WHITE
    jsr color_text
    jsr clear_screen
    jsr print_at
    .byte 16, 2, "PADD WS", 0
    jsr print_at
    .byte 7, 22, "RUN/STOP: BACK   FIRE: OK", 0
    jmp draw_menu
.endproc

; Voci del menu con i valori; la selezionata in bianco, le altre in grigio.
.proc draw_menu
    ldx #0
item:
    stx menu_i
    txa
    asl a
    adc #MENU_ROW0
    sta v_row
    ; colore della riga
    tay
    lda row_lo,y
    sta ptr
    lda row_hi,y
    clc
    adc #>($d800 - SCREEN)
    sta ptr+1
    lda #COL_GRAY
    ldx menu_i
    cpx menu_sel
    bne :+
    lda #COL_WHITE
:   ldy #39
:   sta (ptr),y
    dey
    bpl :-
    ; nome della voce
    lda menu_i
    asl a
    tax
    lda item_names,x
    sta ptr2
    lda item_names+1,x
    sta ptr2+1
    ldx #MENU_COL
    ldy v_row
    jsr print_str
    ; valore
    lda menu_i
    jsr item_value              ; ptr2
    lda ptr2+1
    beq :+
    ldx #MENU_VCOL
    ldy v_row
    jsr print_str
:   ldx menu_i
    inx
    cpx #MENU_ITEMS
    bne item
    rts
.endproc

item_names: .word s_game, s_players, s_level, s_control, s_free, s_asound, s_volume, s_border
            .word s_play
s_game:     .byte "GAME", 0
s_players:  .byte "PLAYERS", 0
s_level:    .byte "DIFFICULTY", 0
s_control:  .byte "CONTROL", 0
s_free:     .byte "FREE PLAY", 0
s_asound:   .byte "ATTRACT SOUND", 0
s_volume:   .byte "VOLUME", 0
s_border:   .byte "BORDER", 0
s_play:     .byte "PLAY", 0

; ptr2 = valore della voce A (0 = nessuno)
.proc item_value
    asl a
    tax
    lda value_fn+1,x
    pha
    lda value_fn,x
    pha
    rts
.endproc

value_fn: .word v_game - 1, v_players - 1, v_level - 1, v_control - 1, v_free - 1, v_asound - 1
          .word v_volume - 1, v_border - 1, v_none - 1

.proc v_game
    lda opt_mode
    ldx #<game_names
    ldy #>game_names
    jmp pick_name
.endproc
.proc v_players
    lda opt_players
    sec
    sbc #1
    ldx #<player_names
    ldy #>player_names
    jmp pick_name
.endproc
.proc v_level
    lda opt_level
    ldx #<level_names
    ldy #>level_names
    jmp pick_name
.endproc
.proc v_control
    lda ctl_paddle
    ldx #<control_names
    ldy #>control_names
    jmp pick_name
.endproc
.proc v_free
    lda opt_free
    ldx #<on_off_names
    ldy #>on_off_names
    jmp pick_name
.endproc
.proc v_asound
    lda opt_asound
    ldx #<on_off_names
    ldy #>on_off_names
    jmp pick_name
.endproc
; il passo del volume in percento in vol_text ("0%", "10%"... "100%", con gli spazi fino a 4)
.proc v_volume
    ldy #0
    ldx opt_volume
    cpx #VOLUME_STEPS - 1
    bcc tens
    lda #'1'                    ; 100%
    sta vol_text
    lda #'0'
    sta vol_text+1
    ldy #2
    bne zero
tens:
    txa
    beq zero                    ; 0%
    ora #'0'
    sta vol_text
    iny
zero:
    lda #'0'
    sta vol_text,y
    lda #'%'
    sta vol_text+1,y
    iny
    iny
    lda #' '
pad:
    cpy #4
    bcs done
    sta vol_text,y
    iny
    bne pad
done:
    lda #<vol_text
    sta ptr2
    lda #>vol_text
    sta ptr2+1
    rts
.endproc
.proc v_border
    lda opt_border
    ldx #<border_names
    ldy #>border_names
    jmp pick_name
.endproc
.proc v_none
    lda #0
    sta ptr2+1
    rts
.endproc

; ptr2 = nome A della tabella di parole X:Y
.proc pick_name
    stx ptr
    sty ptr+1
    asl a
    tay
    lda (ptr),y
    sta ptr2
    iny
    lda (ptr),y
    sta ptr2+1
    rts
.endproc

game_names:    .word s_classic, s_evo, s_next
player_names:  .word s_one, s_two, s_cpu, s_challenge
control_names: .word s_joystick, s_paddle
level_names:   .word s_easy, s_normal, s_hard, s_expert
on_off_names:  .word s_off, s_on
border_names:  .word s_black, s_gray
; stessa lunghezza, così il valore nuovo copre il vecchio
s_classic:  .byte "CLASSIC ", 0
s_evo:      .byte "EVO     ", 0
s_next:     .byte "NEXT    ", 0
s_one:      .byte "ONE      ", 0
s_two:      .byte "TWO      ", 0
s_cpu:      .byte "VS CPU   ", 0
s_challenge: .byte "CHALLENGE", 0
s_joystick: .byte "JOYSTICK", 0
s_paddle:   .byte "PADDLE  ", 0
s_easy:     .byte "EASY    ", 0
s_normal:   .byte "NORMAL  ", 0
s_hard:     .byte "HARD    ", 0
s_expert:   .byte "EXPERT  ", 0
s_off:      .byte "OFF     ", 0
s_on:       .byte "ON      ", 0
s_black:    .byte "BLACK   ", 0
s_gray:     .byte "GRAY    ", 0
vol_text:   .byte "100%", 0     ; il valore di VOLUME, scritto da v_volume

; Menu: su e giù scelgono la voce, sinistra e destra (o fuoco) cambiano il valore; fuoco su PLAY
; inizia la partita; RUN/STOP torna all'attract. Joystick sulle due porte, cursori e RETURN.
.proc menu_scene
    lda #KEY_STOP
    jsr key_pressed
    bcc :+
    jmp go_stripes
:   lda joy_edge
    ora joy_edge+1
    ora fire_edge               ; anche i pulsanti dei paddle
    ora fire_edge+1
    sta at_tmp
    lda #KEY_CRSR_UD
    jsr key_pressed
    bcc :+
    lda at_tmp
    ora #JOY_DOWN
    sta at_tmp
:   lda #KEY_CRSR_LR
    jsr key_pressed
    bcc :+
    lda at_tmp
    ora #JOY_RIGHT
    sta at_tmp
:   lda #KEY_RETURN
    jsr key_pressed
    bcc :+
    lda at_tmp
    ora #JOY_FIRE
    sta at_tmp
:   lda #KEY_SPACE
    jsr key_pressed
    bcc :+
    lda at_tmp
    ora #JOY_FIRE
    sta at_tmp
:   ; su e giù
    lda at_tmp
    and #JOY_UP
    beq :+
    dec menu_sel
    bpl redraw
    lda #MENU_ITEMS - 1
    sta menu_sel
    jmp redraw
:   lda at_tmp
    and #JOY_DOWN
    beq :+
    inc menu_sel
    lda menu_sel
    cmp #MENU_ITEMS
    bcc redraw
    lda #0
    sta menu_sel
    jmp redraw
:   ; fuoco: PLAY parte, le altre voci cambiano valore
    lda at_tmp
    and #JOY_FIRE
    beq :+
    lda menu_sel
    cmp #MI_PLAY
    bne next_value
    jmp start_game
:   lda at_tmp
    and #JOY_RIGHT
    bne next_value
    lda at_tmp
    and #JOY_LEFT
    beq done
    lda #$ff
    bne change
next_value:
    lda #1
change:
    jsr change_value
redraw:
    lda #EV_WALL
    jsr sid_fx
    jsr draw_menu
done:
    rts
.endproc

; Cambia il valore della voce selezionata di A (+1 o -1), in giro.
.proc change_value
    sta at_tmp
    ldx menu_sel
    cpx #MI_GAME
    bne not_game
    ; CLASSIC, EVO, NEXT in giro; EVO e NEXT sono a due (come sul PC)
    lda opt_mode
    clc
    adc at_tmp
    bpl mode_hi
    lda #2
mode_hi:
    cmp #3
    bcc mode_ok
    lda #0
mode_ok:
    sta opt_mode
    ; CHALLENGE si gioca in NEXT: con un altro gioco diventa VS CPU
    cmp #2
    beq :+
    lda opt_players
    cmp #OPT_CHALLENGE
    bne :+
    lda #3
    sta opt_players
:   lda opt_mode
    beq mode_done
    lda opt_players
    cmp #1
    bne mode_done
    lda #2
    sta opt_players
mode_done:
    rts
not_game:
    cpx #MI_PLAYERS
    bne not_players
    lda opt_players
    clc
    adc at_tmp
    beq wrap_hi
    cmp #OPT_CHALLENGE + 1
    bcc store_p
    lda #1
    bne store_p
wrap_hi:
    lda #OPT_CHALLENGE
store_p:
    sta opt_players
    ; il singolo è solo CLASSIC, CHALLENGE solo NEXT
    cmp #OPT_CHALLENGE
    bne :+
    lda #2
    sta opt_mode
    rts
:   cmp #1
    bne players_done
    lda #0
    sta opt_mode
players_done:
    rts
not_players:
    cpx #MI_LEVEL
    bne :+
    lda opt_level
    clc
    adc at_tmp
    and #3
    sta opt_level
    rts
:   cpx #MI_CONTROL
    bne :+
    lda ctl_paddle
    eor #1
    sta ctl_paddle
    rts
:   cpx #MI_FREE
    bne :+
    lda opt_free
    eor #1
    sta opt_free
    rts
:   cpx #MI_ASOUND
    bne :+
    lda opt_asound
    eor #1
    sta opt_asound
    jmp attract_song            ; la musica si ferma (o riparte) subito
:   cpx #MI_VOLUME
    bne not_volume
    ; un passo su o giù: sotto lo 0% resta 0%, dopo il 100% si torna a 0% (il fuoco fa il giro)
    lda opt_volume
    clc
    adc at_tmp
    bpl :+
    lda #0
:   cmp #VOLUME_STEPS
    bcc :+
    lda #0
:   sta opt_volume
    jmp sid_volume              ; subito, anche per la musica che suona
not_volume:
    cpx #MI_BORDER
    bne :+
    lda opt_border
    eor #1
    sta opt_border
:   rts
.endproc

; ------------------------------------------------------------------------------------ partita

; Seme della partita dai frame dall'accensione e dai timer dei CIA.
.proc seed_from_time
    lda frame_count
    sta cfg_seed
    lda frame_count+1
    sta cfg_seed+1
    lda $dc04
    sta cfg_seed+2
    lda $dd04
    sta cfg_seed+3
    rts
.endproc

; Schermo della partita: caratteri bianchi, campo, punteggi, racchette al loro posto (prosegue in
; game_screen_draw).
.proc game_screen
    lda #COL_WHITE
    jsr clear_text
.endproc

; Come game_screen, con lo schermo di testo già pulito e bianco.
.proc game_screen_draw
    lda #0
    sta flash
    sta paused
    sta sh_bg
    jsr draw_field
    jsr draw_scores
    jsr hud_reset               ; NEXT: le riserve si disegnano al prossimo frame
    jmp slide_reset
.endproc

; PLAY dal menu: NEXT passa prima dalla scelta dei bonus e della racchetta (pick.s); le altre
; partite prendono un seme nuovo e proseguono in begin_match.
.proc start_game
    jsr math_ensure             ; tabelle dei quadrati pronte
    lda opt_level               ; CPU e velocità dalla difficoltà (CHALLENGE le cambia)
    sta bm_cpu
    sta bm_diff
    lda #POINTS_TO_WIN
    sta win_points
    lda #0
    sta cg_active
    lda #$60                    ; RTS: READY e GO solo dal file voce del primo livello di CHALLENGE
    sta VOICE_COUNT
    lda opt_mode
    cmp #2
    bne :+
    jmp pick_enter
:   lda #0
    sta cfg_next
    jsr seed_from_time
.endproc

; La partita con le opzioni del menu e il seme in cfg_seed (cfg_next e, in NEXT, bonus e racchette
; già impostati).
.proc begin_match
    lda opt_players
    cmp #3                      ; contro la CPU si gioca in due
    bcc :+
    lda #2
:   sta cfg_players
    ldx #0
    lda opt_mode
    cmp #1
    bne :+
    inx
:   stx cfg_evo
    lda bm_diff
    sta cfg_diff
    jsr match_new
    lda #SCROLL_FRAMES - 1      ; il primo cambio del bonus selezionato dopo un secondo
    sta scroll_t
    sta scroll_t+1
    ; contro la CPU: a destra, al livello scelto; in CHALLENGE dal lato opposto a chi gioca (che
    ; dopo una sfida può essere a destra), nella sfida tra due giocatori nessuna
    lda #$ff
    sta cpu_side
    lda opt_players
    cmp #3
    bcc :++
    ldx #4
    lda cg_active
    beq :+
    cmp #CG_DUEL
    beq :++
    lda ch_side
    eor #4
    tax
:   stx cpu_side
    lda bm_cpu
    jsr cpu_init
.ifdef SMTEST
    lda bm_cpu                  ; (prova per VICE: anche il giocatore sinistro è la CPU)
    ldx #0
    jsr cpu_init
.endif
:   lda match_song              ; in partita solo gli effetti, tranne il tema di CHALLENGE contro
    jsr sid_song                ; la CPU (intro_scene), che vale per questa partita sola
    lda #LIVES
    sta lives
    lda #0
    sta match_song
    sta cd_digit
    sta over_next
    sta fx_pend
    ; schermo della partita (già pulito se si arriva dalle scelte di NEXT)
    lda screen_clear
    beq :+
    lda #0
    sta screen_clear
    jsr game_screen_draw
    jmp :++
:   jsr game_screen
:   lda #COUNT_FRAMES
    sta timer
    lda #ST_COUNT
    sta state
    rts
.endproc

; Conto alla rovescia: 3, 2, 1 al centro; la logica è ferma. In CHALLENGE la voce dice "READY?"
; al primo frame e "GO!" al via, al posto del bip (voice.s: con il SID della voce sid_fx tace).
.proc count_scene
    jsr ch_join_match           ; CHALLENGE: può entrare un nuovo sfidante
    bcc :+
    rts
:   lda timer
    jsr VOICE_COUNT             ; RTS senza file e fuori da CHALLENGE (start_game)
    ldx #3
    lda timer
    cmp #2 * 50 + 1
    bcs :+
    dex
    cmp #50 + 1
    bcs :+
    dex
:   cpx cd_digit
    beq :+
    ; un bip a ogni secondo (non al primo: come sul PC)
    lda cd_digit
    stx cd_digit
    beq first
    lda #EV_WALL
    jsr sid_fx
first:
    lda cd_digit
    ldx #19
    ldy #11
    jsr draw_digit
:   dec timer
    bne done
    lda #EV_BOOST               ; il via
    jsr sid_fx
    ; via: torna la mezzeria
    lda #11
    sta v_row
:   jsr center_line_row
    ldy v_row
    ldx #21
    lda #CH_BLANK
    jsr put_char
    inc v_row
    lda v_row
    cmp #14
    bne :-
    lda #ST_PLAY
    sta state
done:
    rts
.endproc

; Lampo bianco del punto: per qualche frame bordo e sfondo bianchi, senza sprite.
.proc flash_frame
    lda #COL_BLACK
    ldx flash
    beq :+
    dec flash
    lda #COL_WHITE
:   sta sh_bg
    rts
.endproc

.proc play_scene
    lda over_next               ; ultimo punto nel frame prima (punteggio già disegnato)
    beq :+
    lda #0
    sta over_next
    jmp enter_over
:   lda #KEY_STOP
    jsr key_pressed
    bcc :+
    lda paused
    eor #1
    sta paused
:   lda #KEY_Q
    jsr key_pressed
    bcc :+
    jmp enter_menu
:   lda paused
    beq :+
    rts
:   jsr ch_join_match           ; CHALLENGE: può entrare un nuovo sfidante
    bcc :+
    rts
:   jsr flash_frame
    jsr build_input
    ldx cpu_side
    bmi :+
    jsr cpu_input
.ifdef SMTEST
    ldx #0
    jsr cpu_input
.endif
:   jsr dash_before
    jsr match_step
    jsr dash_after
    jsr next_fx_scene           ; NEXT: scritta del bonus attivato, segni di STEER
    jsr ch_tick                 ; CHALLENGE: punti arcade
    jsr ch_hud
    ; effetto sonoro, con il frame già avanti al prossimo (avviarlo costa)
    lda events
    and #EV_WALL | EV_HIT | EV_BOOST | EV_SCORE   ; il bit 4 del player è il gettone
    ora fx_pend
    beq :+
    sta fx_pend
    jsr frame_late_small
    bcs :+
    lda fx_pend
    ldx #0
    stx fx_pend
    jsr sid_fx
:    lda events
    and #EV_SCORE
    beq check
    lda #FLASH_FRAMES
    sta flash
    lda m_players
    cmp #1
    bne :+
    dec lives
:   jsr draw_scores
check:
    ; fine partita: in due il primo a 11, in singolo le palle finite
    lda m_players
    cmp #1
    bne two
    lda lives
    beq over
    rts
two:
    ldx #0
    jsr reached
    bcs over
    ldx #4
    jsr reached
    bcs over
    rts
over:
    inc over_next
    rts
.endproc

; C = 1 se il punteggio X (0 o 4) è arrivato ai punti per vincere.
.proc reached
    lda score+1,x
    bne yes
    lda score,x
    cmp win_points
    rts
yes:
    sec
    rts
.endproc

; GAME OVER, e sotto chi ha vinto (in due). Da sola, al posto di GAME OVER, la scritta di chi ha
; vinto quando la partita non è finita davvero o è vinta: YOU WIN contro la CPU, CPU WINS a un
; livello perso di CHALLENGE (poi il continue; il GAME OVER se scade, cont_over), come sul PC e
; sul MiSTer. Il riquadro: 4 righe con una scritta, 7 con due.
OV_GAME_OVER = 0                ; scritte grandi del GAME OVER (over_lo e le altre tabelle)
OV_YOU_WIN   = 1
OV_P1_WINS   = 2                ; da qui con GAME OVER sopra
OV_P2_WINS   = 3
OV_CPU_WINS  = 4
.proc enter_over
    jsr shots_erase             ; le scritte vanno sul campo pulito
    lda #ST_OVER
    sta state
    lda #SID_SONG_GAME_OVER
    ldx cg_active               ; in CHALLENGE silenzio (poi la sua musica)
    beq :+
    lda #0
:   jsr sid_song
    lda #AT_GAME_OVER_FRAMES
    sta timer
    lda #COL_BLACK
    sta sh_bg
    sta win_pg
    ldx #OV_GAME_OVER           ; in singolo solo GAME OVER
    lda m_players
    cmp #2
    bne box
    ; vince chi ha più punti (a parità il destro): Y = lato del vincitore * 4
    ldy #0
    lda score+5
    cmp score+1
    bcc :+
    bne right
    lda score+4
    cmp score
    bcc :+
right:
    ldy #4
:   ; contro la CPU YOU WIN o CPU WINS (chi gioca può essere a destra), in due P1 o P2 WINS
    lda cpu_side
    bmi humans
    sty m_t
    ldx #OV_CPU_WINS
    cmp m_t
    beq box
    ; la voce YOU WIN, come sul PC (non all'ultimo livello di CHALLENGE: la dice il finale)
    lda cg_active
    beq :+
    lda ch_level
    cmp #CH_LEVELS - 1
    beq :++
:   inc win_pg
:   ldx #OV_YOU_WIN
    bne box
humans:
    ldx #OV_P1_WINS
    tya
    beq box
    inx
box:
    ; Y = 1 con una scritta sola: GAME OVER in singolo, YOU WIN, CPU WINS nella scalata
    ldy #1
    cpx #OV_P1_WINS
    bcc push
    cpx #OV_CPU_WINS
    bne pair
    lda cg_active
    cmp #CG_LADDER
    beq push
pair:
    ldy #0
push:
    txa
    pha
    tya
    pha
    lda #4
    cpy #1
    beq :+
    lda #7
:   sta v_n
    lda #16
    ldx #12
    ldy #9
    jsr blank_box
    pla                         ; una scritta sola: quella, nella riga di GAME OVER
    tay
    pla
    cpy #0
    beq :+
    tax
    ldy #10
    jmp over_big
:   pha                         ; due: GAME OVER e sotto chi ha vinto
    ldx #OV_GAME_OVER
    ldy #10
    jsr over_big
    pla
    tax
    ldy #13                     ; (prosegue in over_big)
.endproc
; Scritta grande X del GAME OVER (OV_*), centrata nella riga Y.
.proc over_big
    lda over_lo,x
    sta ptr2
    lda over_hi,x
    sta ptr2+1
    lda over_w,x
    pha
    lda over_col,x
    tax
    pla
    jmp draw_big
.endproc
over_lo:  .lobytes big_game_over, big_you_win, big_p1_wins, big_p2_wins, big_cpu_wins
over_hi:  .hibytes big_game_over, big_you_win, big_p1_wins, big_p2_wins, big_cpu_wins
over_w:   .byte BIG_GAME_OVER_W, BIG_YOU_WIN_W, BIG_P1_WINS_W, BIG_P2_WINS_W, BIG_CPU_WINS_W
over_col: .byte (40 - BIG_GAME_OVER_W) / 2, (40 - BIG_YOU_WIN_W) / 2, (40 - BIG_P1_WINS_W) / 2
          .byte (40 - BIG_P2_WINS_W) / 2, (40 - BIG_CPU_WINS_W) / 2

; Dopo il GAME OVER si torna all'attract. Contro la CPU, se vince chi gioca, "YOU WIN!": il banco
; della vittoria (voice.inc) a WIN_RUN, due pagine per frame (circa 7.700 cicli), poi la voce. I
; campioni stanno dove ci sono le tabelle dei quadrati e il tema, che poi si rifanno (math_step,
; il file voce della presentazione dopo).
.proc over_scene
    ldx win_pg
    beq tick
    cpx #WIN_PAGES + 1
    bcc copy
    bne tick                    ; (già detta)
    inc win_pg
    ldx #<WIN_DESC
    ldy #>WIN_DESC
    jsr VOICE_SAY
    jmp tick
copy:
    dex
    txa
    ora #$80
    sta ef_src+2
    txa
    clc
    adc #>WIN_RUN
    tay
    inx
    inx
    inx
    stx win_pg
    lda #WIN_BANK
    ldx #2
    jsr ef_copy
tick:
    dec timer
    bne done
    lda win_pg
    beq :+
    jsr math_invalidate
:   lda cg_active               ; CHALLENGE: livello superato o continue
    beq stripes
    jmp ch_after
stripes:
    jsr go_stripes
done:
    rts
.endproc
.assert WIN_PAGES .mod 2 = 0, error, "YOU WIN: pagine a coppie"
