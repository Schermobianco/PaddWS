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
win_pg:    .res 1               ; YOU WIN o PERFECT nel GAME OVER: 0 no, 1-16 prossima pagina + 1,
                                ; poi da dire, detta, finita (WIN_SAID)

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
.elseif .defined(OVERTEST)
; Build per le schermate del GAME OVER (-Define OVERTEST=n): una partita EVO che finisce subito,
; al primo frame. n = 1 contro la CPU vinta 11 a 0 (PERFECT), 2 in due 0 a 11 (PERFECT e P2 WINS),
; 3 contro la CPU vinta 11 a 3 (YOU WIN), 4 contro la CPU persa 0 a 11; senza FREE PLAY, così la demo
; dopo mostra INSERT COIN. Tra le routine dell'avvio.
.segment "BOOTCODE"
.proc overtest_setup
    lda #3
    .if ::OVERTEST = 2
    lda #2
    .endif
    sta opt_players
    lda #1
    sta opt_mode
    lda #0                      ; nella demo dopo, INSERT COIN
    sta opt_free
    jsr start_game
    .if ::OVERTEST = 1
    lda #11
    sta score
    .elseif ::OVERTEST = 2
    lda #11
    sta score+4
    .elseif ::OVERTEST = 3
    lda #11
    sta score
    lda #3
    sta score+4
    .else
    lda #11
    sta score+4
    .endif
    jsr draw_scores
    lda #ST_PLAY
    sta state
    lda #1
    sta over_next
    rts
.endproc
.segment "CODE"
.elseif .defined(CONTTEST)
; Build per le schermate del continue (-Define CONTTEST): CHALLENGE, livello 3 perso, subito il
; conto alla rovescia (poi, se scade, il GAME OVER). Tra le routine dell'avvio.
.segment "BOOTCODE"
.proc conttest_setup
    lda #OPT_CHALLENGE
    sta opt_players
    lda #2
    sta opt_mode
    lda #0
    sta opt_free
    sta ch_side
    lda #CG_LADDER
    sta cg_active
    lda #2
    sta ch_level
    jmp enter_cont
.endproc
.segment "CODE"
.elseif .defined(INTROTEST)
; Build per le schermate delle presentazioni (-Define INTROTEST=n): CHALLENGE, subito la
; presentazione del livello n (1-7). Tra le routine dell'avvio.
.segment "BOOTCODE"
.proc introtest_setup
    lda #OPT_CHALLENGE
    sta opt_players
    lda #2
    sta opt_mode
    lda #0
    sta ch_side
    lda #CG_LADDER
    sta cg_active
    lda #::INTROTEST - 1
    sta ch_level
    jmp enter_intro
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
.elseif .defined(OVERTEST)
    jsr overtest_setup          ; build per le schermate del GAME OVER (sopra)
.elseif .defined(CONTTEST)
    jsr conttest_setup          ; build per le schermate del continue (sopra)
.elseif .defined(INTROTEST)
    jsr introtest_setup         ; build per le schermate delle presentazioni (sopra)
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
.ifdef FRAMETEST
    ; prova per VICE (-Define FRAMETEST): un frame finito dopo l'interrupt del frame dopo è oltre il
    ; suo tempo; quanti (una cifra, al più 9) nella cella in basso a destra, rossa, a ogni frame
    lda ft_n                    ; (i primi giri no: con AUTOSTART il primo frame parte tardi,
    cmp #5                      ; dopo start_game)
    bcs :+
    inc ft_n
    bcc :++
:   lda frame_flag
    beq :+
    lda state                   ; (l'entrata nella presentazione carica il file voce, a schermo
    cmp #ST_INTRO               ; fermo: è un caricamento, non conta, né i due giri dopo, che
    bne ft_real                 ; partono a metà frame)
    cmp ft_prev
    beq ft_real
    lda #3
    sta ft_n
    bne :+
ft_real:
    lda ft_over
    bne ft_inc
ft_first:
    lda state                   ; (lo stato del primo, nelle celle prima)
    sta ft_state
    lda pk_phase
    sta ft_state+1
    lda pk_kind
    sta ft_state+2
    lda frame_count
    sta ft_state+3
    lda frame_count+1
    sta ft_state+4
ft_inc:
    lda ft_over
    cmp #9
    bcs :+
    inc ft_over
:   ldx ft_state
    lda font_map + 'A' - 32,x
    sta SCREEN + 997
    ldx ft_state+1
    lda font_map + '0' - 32,x
    sta SCREEN + 998
    ldx ft_state+2
    lda font_map + '0' - 32,x
    sta SCREEN + 996
    ldy #0
:   lda ft_state+3,y            ; il frame: 4 cifre esadecimali come lettere A-P
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    tax
    lda font_map + 'A' - 32,x
    sta SCREEN + 990,y
    pla
    and #15
    tax
    lda font_map + 'A' - 32,x
    sta SCREEN + 992,y
    iny
    cpy #2
    bne :-
    ldx ft_over
    lda font_map + '0' - 32,x
    sta SCREEN + 999
    lda #COL_RED
    sta $d800 + 999
    lda state
    sta ft_prev
.ifdef FRAMESTOP
    lda ft_over                 ; (fermo al primo: la schermata mostra quel frame)
    beq :+
    sei
    lda #COL_RED                ; (bordo rosso: fermo)
    sta $d020
    jmp *
:
.endif
.endif
    jmp loop
.ifdef FRAMETEST
ft_over: .byte 0
ft_n:    .byte 0
ft_prev: .byte 0
ft_state: .byte 0, 0, 0, 0, 0
.endif
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
    .word menu_scene - 1, count_scene - 1, play_scene - 1, ov_scene - 1, pick_scene - 1
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
    cmp #ST_OVER                ; GAME OVER: sprite e riserve li tiene il suo codice (ov_scene),
    beq music                   ; che sta dove ci sono le mosse speciali (sm_hud)
    ; dopo un tick pesantissimo (frame già oltre circa 14.500 cicli: colpo con previsioni, capsula e
    ; BULLET insieme) restano gli sprite del frame prima: il resto aspetta comunque (frame_after).
    ; Sprite, riserve e controlli costano fino a circa 3.400 cicli: con la soglia più in alto un
    ; frame arriverebbe oltre il suo tempo e i controlli dopo troverebbero il raster "all'inizio"
    lda #KEEP_SPRITES_LINE
    jsr frame_after
    bcs :+
    jsr compute_sprites
:   jsr next_hud
music:
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
    cmp #ST_OVER                ; GAME OVER: il bordo lo tiene il suo codice (ov_enter, chiusura)
    beq done
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
done:
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

; Partita dimostrativa: due CPU, EVO, difficoltà Normal. Prima i caratteri di INSERT COIN e
; PRESS START che il GAME OVER può aver usato per PERFECT (ov_enter): la loro pagina del set di
; caratteri, dalla cartuccia (circa 3.800 cicli).
.proc demo_enter
    lda #$80 + PERFECT_PAGE
    sta ef_src+2
    lda #CHARSET_BANK
    ldx #1
    ldy #>CHARSET + PERFECT_PAGE
    jsr ef_copy
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

; Il menu sta nella cartuccia (segmento MENUCODE, nel .prg da MENU_IMG) e gira a MENU_RUN, nel
; secondo schermo: nel menu (a caratteri) non serve, l'attract ci rifà i colori della bitmap, la
; scelta di NEXT e la presentazione di CHALLENGE ci ricopiano le mosse speciali. enter_menu lo copia
; tutto (4 pagine, circa 15.000 cicli: il frame che apre il menu è già lungo, con il disegno) e ci
; salta; una voce di CHALLENGE (READY?, GO!) prima si ferma, perché la copia accende le ROM.
MENU_RUN  = SCREEN2
MENU_IMG  = $EA00
MENU_BANK = PRG_BANK + (MENU_IMG - $0800) / $4000
MENU_SRC  = $80 + ((MENU_IMG - $0800) .mod $4000) / 256
.import __MENUCODE_LOAD__, __MENUCODE_RUN__, __MENUCODE_SIZE__
.assert __MENUCODE_LOAD__ = MENU_IMG .and __MENUCODE_RUN__ = MENU_RUN .and __MENUCODE_SIZE__ <= $400, lderror, "menu fuori posto o oltre il secondo schermo"
.assert (MENU_IMG + $0400 - $0800 - 1) / $4000 = (MENU_IMG - $0800) / $4000, error, "menu su due banchi"
.proc enter_menu
    bit $fffb                   ; il vettore dell'NMI nel player: una voce, da fermare
    bpl :+
    jsr VOICE_HUSH
:   lda #MENU_SRC
    sta ef_src+2
    lda #MENU_BANK
    ldx #4
    ldy #>MENU_RUN
    jsr ef_copy
    jmp menu_enter
.endproc

.segment "MENUCODE"
.proc menu_enter
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

.segment "CODE"

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
    ; effetto sonoro, con il frame già avanti al prossimo (avviarlo costa). NEXT e tipi di
    ; racchetta come nel MiSTer: capsula e barriera del GUARDIAN = muro, sparo del BLASTER =
    ; colpo, bonus attivato e TELEPORT = boost, SUPER = punto (senza questi eventi, la via corta)
    lda events
    and #EV_COLLECT | EV_ACTIVATE | EV_SUPER | EV_TELEPORT
    bne :+
    lda events+1
    and #EV_FIRE_HI | EV_BARRIER_HI
    beq @fx_base                ; A = 0
:   lda events
    asl a
    asl a
    sta m_t                     ; bit 7 bonus attivato, bit 6 capsula
    lda events+1
    lsr a                       ; C = sparo; bit 0 = barriera
    and #EV_WALL
    bcc :+
    ora #EV_HIT
:   bit m_t
    bpl :+
    ora #EV_BOOST
:   bvc :+
    ora #EV_WALL
:   bit events                  ; N = TELEPORT, V = SUPER
    bpl :+
    ora #EV_BOOST
:   bvc @fx_base
    ora #EV_SCORE
@fx_base:
    sta m_t
    lda events
    and #EV_WALL | EV_HIT | EV_BOOST | EV_SCORE   ; il bit 4 del player è il gettone
    ora m_t
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
; sul MiSTer. Vinta da un giocatore (non dalla CPU) con l'avversario a 0 punti, PERFECT: al posto
; di YOU WIN, o di GAME OVER sopra chi ha vinto. Il riquadro: 4 righe con una scritta, 7 con due.
; Animazioni come rust/game/src/attract.rs (draw_game_over_anim, net_off, pads_left,
; draw_crt_close), a celle:
; - GAME OVER: la mezzeria si spegne dall'alto, palla e racchette se ne vanno (le racchette si
;   accorciano), GAME OVER e chi ha vinto si scrivono con il cursore, poi lo schermo si chiude
;   come un televisore e resta nero per AT_GAME_OVER_BLACK frame;
; - PERFECT: un timbro di blocchi pieni che si stringe in tre passi, la scritta con una scossa
;   (scroll fine), poi ogni secondo un riflesso in diagonale nei colori;
; - YOU WIN: la palla parte dalla racchetta di chi ha vinto, salta da una cella all'altra e le
;   accende, poi se ne va; alla fine la scritta lampeggia;
; - CPU WINS da sola (livello perso di CHALLENGE): si scrive con il cursore, subito.
; In NEXT chi ha vinto è giallo, come sul PC.
OV_GAME_OVER = 0                ; scritte grandi del GAME OVER (over_lo e le altre tabelle)
OV_YOU_WIN   = 1
OV_P1_WINS   = 2                ; da qui con GAME OVER (o PERFECT) sopra
OV_P2_WINS   = 3
OV_CPU_WINS  = 4
OV_PERFECT   = 5                ; la mappa è nel codice del GAME OVER: solo da ov_enter
; Chi ha vinto, le scritte, la voce e le animazioni stanno nella cartuccia (segmento OVCODE, nel
; .prg da OV_IMG) e girano a OV_RUN, nel secondo schermo come le mosse speciali: fuori dalla
; partita NEXT è libero (l'attract ci rifà i colori della bitmap, la scala della CHALLENGE ci
; ricopia le mosse alla fine di ogni presentazione, intro_scene). enter_over ne copia la prima
; pagina (circa 3.800 cicli) e ci salta; le altre le copia la scena nei frame dopo, una per frame.
; Nel programma restano enter_over e over_big. La pagina del set di caratteri con PERFECT
; (OVCHARS, gen/perfect_chars.bin) sta nel .prg da OVCH_IMG.
OV_RUN   = SCREEN2              ; dove gira (paddws.cfg, OVRAM)
OV_IMG   = $E000                ; dove sta nel .prg (OVIMG), poi nella flash
OVCH_IMG = $DF00                ; i caratteri di PERFECT (OVCHIMG)
OV_BANK  = PRG_BANK + (OV_IMG - $0800) / $4000
OV_SRC   = $80 + ((OV_IMG - $0800) .mod $4000) / 256
OVCH_SRC = $80 + ((OVCH_IMG - $0800) .mod $4000) / 256
OV_PAGES = >(__OVCODE_SIZE__ + 255)
.import __OVCODE_LOAD__, __OVCODE_RUN__, __OVCODE_SIZE__, __OVCHARS_LOAD__
.assert __OVCODE_LOAD__ = OV_IMG .and __OVCODE_RUN__ = OV_RUN, lderror, "GAME OVER fuori posto"
.assert __OVCODE_SIZE__ <= $400 .and __OVCHARS_LOAD__ = OVCH_IMG, lderror, "GAME OVER oltre il secondo schermo"
.assert ((OV_IMG - $0800) .mod $4000) + $0400 <= $2000 .and (OV_IMG - $0800) / $4000 = (OVCH_IMG - $0800) / $4000, error, "GAME OVER oltre la ROML del banco"
; pagina del set di caratteri con i caratteri di PERFECT (gen/perfect_chars.bin)
PERFECT_PAGE = PERFECT_C0 * 8 / 256
.assert (PERFECT_C0 + PERFECT_CHARS - 1) * 8 / 256 = PERFECT_PAGE, error, "PERFECT: caratteri su due pagine"
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
    lda #OV_SRC
    sta ef_src+2
    lda #OV_BANK
    ldx #1
    ldy #>OV_RUN
    jsr ef_copy
    jmp ov_enter
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
over_lo:  .lobytes big_game_over, big_you_win, big_p1_wins, big_p2_wins, big_cpu_wins, ovc::big_perfect
over_hi:  .hibytes big_game_over, big_you_win, big_p1_wins, big_p2_wins, big_cpu_wins, ovc::big_perfect
over_w:   .byte BIG_GAME_OVER_W, BIG_YOU_WIN_W, BIG_P1_WINS_W, BIG_P2_WINS_W, BIG_CPU_WINS_W, BIG_PERFECT_W
over_col: .byte (40 - BIG_GAME_OVER_W) / 2, (40 - BIG_YOU_WIN_W) / 2, (40 - BIG_P1_WINS_W) / 2
          .byte (40 - BIG_P2_WINS_W) / 2, (40 - BIG_CPU_WINS_W) / 2, (40 - BIG_PERFECT_W) / 2

; Tempi delle animazioni (attract.rs, a 50 Hz), in frame da quando il codice è tutto copiato.
OA_NET     = 40                 ; mezzeria spenta dall'alto (NET_OFF)
OA_PADS    = 10                 ; poi le racchette si accorciano (PADS_OFF)
OA_TYPE    = 47                 ; GAME OVER si scrive da qui (TYPE_AT), una cella ogni OA_STEP
OA_STEP    = 3
OA_GAP     = 8                  ; chi ha vinto OA_GAP dopo (WIN_GAP), una cella ogni OA_WSTEP
OA_WSTEP   = 2
OA_TYPE1   = 10                 ; CPU WINS da sola: subito
OA_BLINK   = 25                 ; cursore a scritte finite: acceso OA_BLINK / 2 frame su OA_BLINK
OA_CLOSE   = 19                 ; chiusura negli ultimi frame: 7 la fascia si stringe, 7 la riga,
OA_SQUASH  = 7                  ; 5 il puntino (CLOSE_SQUASH, CLOSE_LINE, CLOSE_DOT)
OA_LINE    = 7
OA_HOLD    = 3                  ; PERFECT: frame di ogni grandezza del timbro (STAMP_HOLD)
OA_SHAKE   = 8                  ; frame della scossa dopo il timbro (STAMP_SHAKE)
OA_WIN     = 23                 ; chi ha vinto sotto PERFECT (STAMP_WIN)
OA_GLINT   = 40                 ; riflesso da qui, ogni OA_GLINT_P frame (GLINT_AT, GLINT_PERIOD)
OA_GLINT_P = 50
OA_FIRST   = 16                 ; YOU WIN: la palla sulla prima cella (HOP_FIRST), poi una cella
OA_HOP     = 3                  ; ogni OA_HOP frame (HOP)
OA_LAST    = OA_FIRST + OA_HOP * (BIG_YOU_WIN_W - 1)  ; sull'ultima cella
.assert AT_GAME_OVER_FRAMES + AT_GAME_OVER_BLACK < 256, error, "GAME OVER: il tempo sta in un byte"
.assert OA_NET + OA_PADS + 4 < AT_GAME_OVER_FRAMES - OA_CLOSE, error, "GAME OVER: la chiusura arriva prima della fine del campo"
OV_ROW   = 10                   ; righe delle scritte: in alto e sotto
OV_ROW2  = 13
HOP_COL  = (40 - BIG_YOU_WIN_W) / 2
HOP_X    = SPR_X0 + HOP_COL * 8 + 2         ; palla (4x4) sulla prima cella di YOU WIN
HOP_Y    = SPR_Y0 + OV_ROW * 8 - 5
GLINT_COL = $d800 + OV_ROW * 40 + (40 - BIG_PERFECT_W) / 2
HOP_COLOR = $d800 + OV_ROW * 40 + HOP_COL
.assert HOP_X + 8 * BIG_YOU_WIN_W < 256, error, "YOU WIN: la palla sulle lettere senza il bit 8"
; Le pagine 1-3 (da OV_MODE) in tre versioni, una per animazione, nel .prg da OVA_IMG, OVB_IMG e
; OVC_IMG: la sceglie ov_enter (ov_mode), le copia ov_scene. Ognuna comincia con la sua scena e
; ha le sue copie delle routine comuni (ov_box_code, ov_win_tick).
OV_MODE  = OV_RUN + $100
OVA_IMG  = $E100
OVB_IMG  = $E400
OVC_IMG  = $E700
OVA_SRC  = $80 + ((OVA_IMG - $0800) .mod $4000) / 256
OVB_SRC  = $80 + ((OVB_IMG - $0800) .mod $4000) / 256
OVC_SRC  = $80 + ((OVC_IMG - $0800) .mod $4000) / 256
.assert (OVC_IMG + $0300 - $0800 - 1) / $4000 = (OV_IMG - $0800) / $4000, error, "GAME OVER: le versioni in un altro banco"
.import __OVA_LOAD__, __OVB_LOAD__, __OVC_LOAD__
.assert __OVA_LOAD__ = OVA_IMG .and __OVB_LOAD__ = OVB_IMG .and __OVC_LOAD__ = OVC_IMG, lderror, "GAME OVER: versioni fuori posto"

; Il tempo del GAME OVER, con la voce (YOU WIN e PERFECT): la sua copia, la voce, poi le tabelle dei
; quadrati.
.macro ov_win_tick
.proc win_tick
    ; Contro la CPU, se vince chi gioca, "YOU WIN!" (o "PERFECT!", anche in due: lo sceglie
    ; ov_enter): l'immagine del banco della vittoria (voice.inc) a WIN_RUN, due pagine per frame
    ; (circa 7.700 cicli), poi la voce. I campioni stanno dove ci sono le tabelle dei quadrati e il
    ; tema, che poi si rifanno (math_step, il file voce della presentazione dopo).
    ldx win_pg
    beq tick
    cpx #WIN_PAGES + 1
    bcc copy
    bne said
    inc win_pg
    ldx #<WIN_DESC
    ldy #>WIN_DESC
    jsr VOICE_SAY
    jmp tick
said:
    ; finita la voce (l'NMI di nuovo del programma), una volta: le tabelle dei quadrati, coperte
    ; dai campioni, si rifanno già nel GAME OVER (math_step), così sono pronte per quello che segue
    ; (dopo la sfida di CHALLENGE subito la presentazione, che non lascia tempo a math_step)
    cpx #WIN_SAID
    beq tick
    bit $fffb
    bmi tick
    inc win_pg
    jsr math_invalidate
    jmp tick
copy:
    dex
    txa
    ora ov_wsrc                 ; ($80 YOU WIN, WIN_PERFECT PERFECT: lo sceglie ov_enter)
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
    ldx win_pg                  ; (se la voce non fosse finita)
    beq :+
    cpx #WIN_SAID
    beq :+
    jsr math_invalidate
:   lda cg_active               ; CHALLENGE: livello superato o continue
    beq :+
    jmp ch_after
:   jmp go_stripes              ; (salti: dopo questo codice può sparire)
done:
    rts
.endproc
.endmacro
WIN_SAID = WIN_PAGES + 3        ; win_pg: voce finita, tabelle dei quadrati da rifare
.assert WIN_PAGES .mod 2 = 0, error, "YOU WIN: pagine a coppie"
.assert WIN_PERFECT .mod WIN_PAGES = 0 .and WIN_PAGES <= 16, error, "PERFECT: pagine dell'immagine con ora"

; Il riquadro e i colori, in ogni versione.
.macro ov_box_code
; variabili delle versioni (con i valori di partenza: si ricopiano a ogni GAME OVER)
ov_hh:    .byte 13              ; chiusura: mezza altezza della fascia nel frame prima
ov_bx:    .word 0               ; YOU WIN: palla (x in pixel degli sprite, y), salita del volo
ov_by:    .byte 0
ov_vy:    .byte 0
ov_t:     .byte 0               ; temporanee
ov_n:     .byte 0
ov_row:   .byte 0
ov_cx:    .byte 0
ov_c0:    .byte 0
ov_cy:    .byte 0
ov_full:  .byte 0
; Il riquadro nero (4 righe con una scritta, 7 con due) e i colori delle scritte.
.proc ov_box
    lda #4
    ldx bottom
    bmi :+
    lda #7
:   sta v_n
    lda #16
    ldx #12
    ldy #9
    jsr blank_box
    lda ov_tcol
    ldx #OV_ROW
    jsr ov_colors
    ldx bottom
    bmi :+
    lda ov_wcol
    ldx #OV_ROW2
    jmp ov_colors
:   rts
.endproc

; Colore A per le righe X e X + 1, colonne 12-27.
.proc ov_colors
    sta ov_n
    stx ov_row
    lda #16
    sta v_n
    jsr one
    inc ov_row
one:
    lda ov_n
    ldy #12
    ldx ov_row
    jmp color_span_raw
.endproc

.endmacro

.segment "OVCODE"
.segment "OVCODE"
; Variabili, nella prima pagina (ov_enter le scrive prima che arrivino le altre, e le usano tutte
; le versioni), con i valori di partenza: il codice si ricopia dalla cartuccia a ogni GAME OVER.
ov_pg:    .byte 1               ; pagine già copiate (la prima la copia enter_over)
ov_f:     .byte 0               ; frame dell'animazione, da quando il codice è tutto copiato
top:      .byte OV_GAME_OVER    ; scritte: in alto (righe 10-11) e sotto (13-14, $ff nessuna)
bottom:   .byte $ff
lost:     .byte 0               ; punti di chi perde (byte basso | alto)
ov_mode:  .byte 0               ; versione delle pagine 1-3: 0 GAME OVER e CPU WINS, 1 YOU WIN, 2 PERFECT
ov_wsrc:  .byte $80             ; prima pagina dell'immagine della voce nel banco della vittoria
ov_at:    .byte OA_TYPE         ; GAME OVER si scrive da qui (subito nel continue: cont_over)
ov_side:  .byte 0               ; lato di chi ha vinto * 4 (YOU WIN: la palla parte da lì)
ov_tcol:  .byte COL_WHITE       ; colori della scritta in alto e di chi ha vinto, già scambiati
ov_wcol:  .byte COL_WHITE       ; per l'easter egg (si scrivono con color_span_raw)

; Il GAME OVER dopo enter_over (a OV_RUN): le scritte in top e bottom; la voce in win_pg (1 da
; dire, come in win_tick), quale nell'immagine da copiare (ov_wsrc): YOU WIN quando un giocatore
; batte la CPU, PERFECT al suo posto, anche in due, quando chi perde ha 0 punti; all'ultimo
; livello di CHALLENGE nessuna (la dice il finale), ma la scritta resta PERFECT, come sul PC.
.proc ov_enter
    lda #COL_BLACK
    sta sh_bg
    sta win_pg
    lda #$80                    ; YOU WIN, all'inizio della ROML del banco della vittoria
    sta ov_wsrc
    ; il bordo lo tiene il GAME OVER (border_game non lo cambia): quello della partita, senza i
    ; colori del match point e delle mosse
    lda #0
    ldx opt_border
    beq :+
    lda #COL_DGRAY
:   sta sh_brd
    ; in NEXT chi ha vinto è giallo
    lda m_next
    beq :+
    lda egg_yel
    sta ov_wcol
:   lda m_players               ; in singolo solo GAME OVER
    cmp #2
    jne draw
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
:   sty ov_side
    ; partita perfetta: chi perde (dal lato Y eor 4) è a 0 punti
    tya
    eor #4
    tax
    lda score,x
    ora score+1,x
    sta lost                    ; 0: perfetta, se ha vinto un giocatore
    ; contro la CPU YOU WIN o CPU WINS (chi gioca può essere a destra), in due P1 o P2 WINS
    lda cpu_side
    bmi humans
    sty m_t
    cmp m_t
    bne you_win
    ; ha vinto la CPU (niente PERFECT): GAME OVER e sotto CPU WINS, da sola a un livello perso
    ; di CHALLENGE (si può ancora continuare)
    lda #OV_CPU_WINS
    ldx cg_active
    cpx #CG_LADDER
    bne :+
    sta top
    beq draw                    ; (Z dal confronto: sta non lo cambia)
:   sta bottom
    bne draw
you_win:
    ; la voce, come sul PC (non all'ultimo livello di CHALLENGE: la dice il finale)
    lda cg_active
    beq :+
    lda ch_level
    cmp #CH_LEVELS - 1
    beq :++
:   inc win_pg
:   lda #OV_YOU_WIN             ; YOU WIN da sola, o PERFECT al suo posto
    ldx lost
    beq perfect
    sta top
    sta ov_mode                 ; (OV_YOU_WIN = 1: la versione di YOU WIN)
    bne draw
humans:
    ldx #OV_P1_WINS
    tya
    beq :+
    inx
:   stx bottom
    lda lost
    bne draw
    inc win_pg                  ; in due la voce c'è solo per PERFECT, che va al posto di GAME OVER
perfect:
    lda #OV_PERFECT
    sta top
    lda #2                      ; la versione di PERFECT
    sta ov_mode
    lda #WIN_PERFECT            ; "PERFECT!" al posto di "YOU WIN!"
    sta ov_wsrc
draw:
    ; la scritta in alto è di chi ha vinto quando è da sola (salvo GAME OVER in singolo)
    lda bottom
    bpl :+
    lda top
    beq :+
    lda ov_wcol
    sta ov_tcol
:   ; con GAME OVER in alto, dopo la chiusura lo schermo resta nero
    lda top
    bne :+
    lda #AT_GAME_OVER_FRAMES + AT_GAME_OVER_BLACK
    sta timer
:   rts
.assert OV_YOU_WIN = 1, error, "ov_enter: OV_YOU_WIN è anche la versione"
.endproc
ov_msrc: .byte OVA_SRC - 1, OVB_SRC - 1, OVC_SRC - 1   ; per la pagina 1 di ogni versione


; La scena del GAME OVER: nei primi frame le pagine 1-3 della versione giusta dalla cartuccia (una
; per frame), poi la sua scena (OV_MODE).
.proc ov_scene
    ldx ov_pg
    cpx #4
    bcs run
    inc ov_pg
    txa
    ldy ov_mode
    clc
    adc ov_msrc,y
    sta ef_src+2
    txa
    adc #>OV_RUN
    tay
    lda #OV_BANK
    ldx #1
    jsr ef_copy
    dec timer                   ; (finisce dopo OA_CLOSE: assert sopra)
    rts
run:
    jmp OV_MODE
.endproc
.assert * <= OV_RUN + $100, lderror, "GAME OVER: la prima pagina è piena"

.segment "OVA"
.scope ova
; GAME OVER e CPU WINS (senza voce): l'animazione, poi il tempo.
.proc scene
    lda #OA_TYPE1
    ldx top
    bne type                    ; CPU WINS da sola: subito
    jsr ov_field                ; GAME OVER: il campo si spegne, poi la chiusura
    bcs tick
    lda ov_at
type:
    jsr ov_type
tick:
    inc ov_f
    bne :+
    dec ov_f
:
    dec timer
    bne done
    lda cg_active               ; CHALLENGE: la sfida, o il continue
    beq :+
    jmp ch_after
:   jmp go_stripes              ; (salti: dopo questo codice può sparire)
done:
    rts
.endproc
.assert scene = OV_MODE, lderror, "GAME OVER: la scena non all'inizio della versione"

; GAME OVER: la mezzeria si spegne dall'alto, via la palla, le racchette si accorciano (metà
; altezza, poi via: sono sprite); negli ultimi OA_CLOSE frame la chiusura (C = 1: niente scritte),
; poi nero.
.proc ov_field
    lda timer
    cmp #AT_GAME_OVER_BLACK + OA_CLOSE + 1
    bcs field
    jmp ov_close
field:
    lda ov_f
    cmp #OA_NET
    bcs pads
    ; la riga f * 5 / 8 (le 25 righe in OA_NET frame): via i trattini della mezzeria
    asl a
    asl a
    adc ov_f
    lsr a
    lsr a
    lsr a
    tay
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    ldy #19
    jsr dash
    iny
    jsr dash
    clc
    rts
dash:
    lda (ptr),y
    cmp #CH_LINE_L
    beq :+
    cmp #CH_LINE_R
    bne :++
:   lda #CH_BLANK
    sta (ptr),y
:   rts
pads:
    bne cut
    ; spenta la mezzeria, via la palla e il resto; le racchette a metà altezza (non espanse, al
    ; centro di dov'erano: le immagini cominciano dalla riga in alto)
    lda sh_enable
    and #%11 << SPN_PAD
    sta sh_enable
    lda sh_yexp
    and #<~(%11 << SPN_PAD)
    sta sh_yexp
    ldx #1
half:
    lda pd_cur_n,x
    lsr a
    clc
    adc sh_y+SPN_PAD,x
    sta sh_y+SPN_PAD,x
    dex
    bpl half
    lda ov_f
cut:
    cmp #OA_NET + OA_PADS / 2   ; poi via anche loro
    bne done
    lda #0
    sta sh_enable
done:
    clc
    rts
.endproc

; Chiusura da vecchio televisore, al frame c = AT_GAME_OVER_BLACK + OA_CLOSE - timer (0-18; dopo
; nero): la fascia si stringe verso il centro con i bordi bianchi, diventa una riga che si accorcia,
; poi un puntino. C = 1.
.proc ov_close
    eor #$ff
    sec
    adc #AT_GAME_OVER_BLACK + OA_CLOSE
    cmp #OA_SQUASH
    bcs line
    tax
    bne :+
    stx sh_brd                  ; (X = 0) bordo nero
:   lda ov_clhh,x
    sta ov_n                    ; mezza altezza della fascia
    ldy #24
row:
    tya
    sec
    sbc #12
    bcs :+
    eor #$ff
    adc #1                      ; |riga - 12|
:   cmp ov_n
    beq edge
    bcc skip
    cmp ov_hh                   ; fuori dalla fascia: nera, se non lo era già
    beq blank
    bcs skip
blank:
    lda #CH_BLANK
    .byte $2c                   ; (bit: salta il lda)
edge:
    lda #CH_GRID_T              ; bordo: una riga bianca
    jsr ov_fill
skip:
    dey
    bpl row
    lda ov_n
    sta ov_hh
    sec
    rts
line:
    sbc #OA_SQUASH              ; (C = 1)
    cmp #OA_LINE
    bcs dot
    tax
    lda #CH_BLANK               ; la fascia (righe 10-14) nera, poi la riga
    ldy #14
:   jsr ov_fill
    dey
    cpy #9
    bne :-
    lda ov_clw,x            ; la riga, larga 2 * ov_clw celle al centro
    sta ov_n
    asl a
    tax
    lda ov_n
    clc
    adc #19
    tay
    lda #CH_GRID_T
:   sta SCREEN + 12 * 40,y
    dey
    dex
    bne :-
    sec
    rts
dot:
    sbc #OA_LINE                ; (C = 1)
    cmp #OA_CLOSE - OA_SQUASH - OA_LINE
    bcs black
    tax
    bne :+                      ; il puntino solo al primo frame
    lda #CH_BLANK
    ldy #12
    jsr ov_fill
    lda #CH_LINE_L              ; un trattino di 2 pixel al centro
    sta SCREEN + 12 * 40 + 19
    lda #CH_LINE_R
    sta SCREEN + 12 * 40 + 20
:   sec
    rts
black:
    bne :-                      ; dopo il primo frame di nero niente
    lda #CH_BLANK
    ldy #12
    jsr ov_fill
    sec
    rts
.endproc
ov_clhh:   .byte 12, 10, 9, 7, 5, 3, 2
ov_clw: .byte 20, 17, 14, 11, 8, 5, 2

; Riga Y piena del carattere A, bianca (Y resta).
.proc ov_fill
    sty ov_row
    pha
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    pla
    ldy #39
:   sta (ptr),y
    dey
    bpl :-
    pha
    lda ptr+1
    clc
    adc #>($d800 - SCREEN)
    sta ptr+1
    lda #COL_WHITE
    ldy #39
:   sta (ptr),y
    dey
    bpl :-
    pla
    ldy ov_row
    rts
.endproc

; Scritte che si scrivono con il cursore dal frame A: top nella riga OV_ROW, una cella ogni
; OA_STEP frame, poi (se c'è) bottom nella riga OV_ROW2, OA_GAP frame dopo, una cella ogni
; OA_WSTEP; il cursore pieno mentre scrive, poi lampeggia.
.proc ov_type
    eor #$ff
    sec
    adc ov_f
    bcc done                    ; non ancora
    sta ov_t
    bne :+
    jsr ov_box                  ; il primo frame: il riquadro
:   lda ov_t
    ldx top
    ldy #OA_STEP
    jsr ov_cells
    ror ov_full                 ; bit 7: scritta finita
    ldx top
    ldy #OV_ROW
    jsr ov_part
    bit ov_full
    bpl solid
    ldx bottom
    bmi blink
    ; chi ha vinto, OA_GAP frame dopo l'ultima cella in alto
    ldx top
    lda over_w,x
    sta ov_n
    asl a
    adc ov_n                    ; (OA_STEP = 3)
    adc #OA_GAP
    eor #$ff
    sec
    adc ov_t
    bcc solid                   ; non ancora: il cursore resta in alto
    ldx bottom
    ldy #OA_WSTEP
    jsr ov_cells
    ror ov_full
    ldx bottom
    ldy #OV_ROW2
    jsr ov_part
    bit ov_full
    bpl solid
blink:
    lda ov_f                    ; finita: acceso nella prima metà di ogni OA_BLINK frame
:   sec
    sbc #OA_BLINK
    bcs :-
    adc #OA_BLINK
    cmp #OA_BLINK / 2
    lda #CH_BLANK
    bcs cursor
solid:
    lda #CH_SOLID
cursor:
    ldx ov_cx
    ldy ov_cy
    sty ov_row
    pha
    jsr put_char
    pla
    ldy ov_row
    iny
    jmp put_char
done:
    rts
.assert OA_STEP = 3, error, "ov_type: il passo in alto è 3"
.endproc

; Celle della scritta X da scrivere al frame A (da 0), una ogni Y frame: A = A / Y + 1, al più la
; larghezza; C = 1 se è tutta.
.proc ov_cells
    sty ov_n
    ldy #0
:   iny
    sec
    sbc ov_n
    bcs :-
    tya
    cmp over_w,x
    bcc :+
    lda over_w,x
:   rts
.endproc

; Le prime A celle della scritta grande X nella riga Y (due righe), poi una cella vuota (dove
; c'era il cursore); il cursore va dopo le celle scritte (ov_cx, ov_cy).
.proc ov_part
    sta ov_n
    sty ov_cy
    sty ov_row
    lda over_lo,x
    sta ptr2
    lda over_hi,x
    sta ptr2+1
    lda over_col,x
    sta ov_c0
    clc
    adc ov_n
    sta ov_cx
    lda over_w,x
    pha
    jsr row
    inc ov_row
    pla
    clc
    adc ptr2
    sta ptr2
    bcc row
    inc ptr2+1
row:
    ldy ov_row
    clc
    lda row_lo,y
    adc ov_c0
    sta ptr
    lda row_hi,y
    adc #0
    sta ptr+1
    ldy #0
:   cpy ov_n
    beq :+
    lda (ptr2),y
    sta (ptr),y
    iny
    bne :-
:   lda #CH_BLANK
    sta (ptr),y
    rts
.endproc

ov_box_code
.endscope


.segment "OVB"
.scope ovb
; YOU WIN: l'animazione, poi la voce e il tempo.
.proc scene
    jsr ov_hop
    inc ov_f
    bne :+
    dec ov_f
:
    jmp win_tick
.endproc
.assert scene = OV_MODE, lderror, "YOU WIN: la scena non all'inizio della versione"
ov_win_tick

; YOU WIN: la palla parte dalla racchetta di chi ha vinto e si avvicina alla prima cella (un
; quarto della distanza a frame, con l'arco di ov_arc), poi salta di cella in cella accendendole,
; nell'ordine da quel lato; dopo l'ultima vola via e la scritta lampeggia.
.proc ov_hop
    lda ov_f
    bne moving
    ; primo frame: il riquadro, le lettere spente, la palla sulla racchetta
    jsr ov_box
    ldx top
    ldy #OV_ROW
    jsr over_big
    lda #COL_DGRAY
    ldx #OV_ROW
    jsr ov_colors
    lda ov_side
    lsr a
    lsr a
    tax
    lda sh_y+SPN_PAD,x
    clc
    adc #18
    sta ov_by
    lda sh_msb
    lsr a
    lsr a
    lsr a
    cpx #0
    beq :+
    lsr a
:   and #1
    sta ov_bx+1
    lda sh_x+SPN_PAD,x
    clc
    adc #8
    sta ov_bx
    bcc :+
    inc ov_bx+1
:   lda #SP_BALL4
    sta sh_ptr
    lda #COL_WHITE
    sta sh_col
    lda sh_mc
    and #$fe
    sta sh_mc
    lda sh_xexp
    and #$fe
    sta sh_xexp
    lda sh_yexp
    and #$fe
    sta sh_yexp
    lda sh_enable
    ora #1
    sta sh_enable
    lda ov_f
moving:
    cmp #OA_FIRST
    bcs hops
    ; avvicinamento alla prima cella
    pha
    lda #0
    jsr cell_x
    sec
    sbc ov_bx
    sta ov_t
    lda #0
    sbc ov_bx+1
    cmp #$80                    ; distanza / 4, con il segno
    ror a
    ror ov_t
    cmp #$80
    ror a
    ror ov_t
    tax
    clc
    lda ov_t
    adc ov_bx
    sta ov_bx
    txa
    adc ov_bx+1
    sta ov_bx+1
    lda #HOP_Y
    sec
    sbc ov_by
    cmp #$80
    ror a
    cmp #$80
    ror a
    clc
    adc ov_by
    sta ov_by
    pla
    tax
    lda ov_by
    sec
    sbc ov_arc,x
    jmp ball
hops:
    sbc #OA_FIRST               ; (C = 1) Y = salto, A = frame del salto
    ldy #$ff
:   iny
    sec
    sbc #OA_HOP
    bcs :-
    adc #OA_HOP
    sta ov_t
    cpy #BIG_YOU_WIN_W - 1
    bcs last
    ; sulla cella Y: accesa al primo frame; la palla verso la dopo
    tya
    pha
    ldx ov_t
    bne :+
    jsr light
:   pla
    jsr cell_x
    ldx ov_t
    ldy ov_side
    beq rightward
    sec
    sbc ov_hdx,x
    bcs placed                  ; (sempre)
rightward:
    adc ov_hdx,x                ; (C = 0 da cell_x)
placed:
    sta ov_bx
    lda #0
    sta ov_bx+1
    lda #HOP_Y
    sec
    sbc ov_hup,x
    jmp ball
last:
    bne fly
    ldx ov_t
    bne fly
    ; l'ultima cella: accesa, poi la palla vola via
    tya
    jsr light
    lda #BIG_YOU_WIN_W - 1
    jsr cell_x
    sta ov_bx
    lda #0
    sta ov_bx+1
    lda #HOP_Y
    sta ov_by
    lda #<-7
    sta ov_vy
fly:
    lda ov_by
    cmp #250
    bcs gone
    clc
    adc ov_vy
    sta ov_by
    inc ov_vy
    inc ov_vy
    lda ov_side
    beq :+
    lda ov_bx                   ; verso il lato di chi ha vinto
    sec
    sbc #5
    sta ov_bx
    bcs blink
    dec ov_bx+1
    bpl blink
    bmi gone
:   lda ov_bx
    clc
    adc #5
    sta ov_bx
    bcc blink
    inc ov_bx+1
blink:
    lda ov_by
    jsr ball
    jmp flash
gone:
    lda sh_enable
    and #$fe
    sta sh_enable
flash:
    ; la scritta lampeggia da OA_LAST + 12 a OA_LAST + 52, 5 frame accesa e 5 di là
    lda ov_f
    sec
    sbc #OA_LAST + 12
    bcc done
    cmp #40
    bcc :+
    bne done
    lda ov_tcol                 ; finito: di nuovo accesa
    bne set
:   ldy #$ff
:   iny
    sec
    sbc #5
    bcs :-
    tya
    lsr a
    lda ov_tcol
    bcs set
    lda #COL_WHITE
    cmp ov_tcol
    bne set
    lda #COL_DGRAY
set:
    ldx #BIG_YOU_WIN_W - 1
:   sta HOP_COLOR,x
    sta HOP_COLOR + 40,x
    dex
    bpl :-
done:
    rts
; palla alla riga A, colonna ov_bx
ball:
    sta sh_y
    lda ov_bx
    sta sh_x
    lda sh_msb
    and #$fe
    ora ov_bx+1
    sta sh_msb
    rts
; cella Y nell'ordine del salto (da destra se ha vinto il destro): accesa
light:
    jsr order
    tax
    lda ov_tcol
    sta HOP_COLOR,x
    sta HOP_COLOR + 40,x
    rts
; A = x della palla sulla cella A nell'ordine del salto (C = 0)
cell_x:
    jsr order
    asl a
    asl a
    asl a
    adc #HOP_X
    rts
order:
    ldx ov_side
    beq :+
    eor #$ff
    clc
    adc #BIG_YOU_WIN_W
:   rts
.endproc
ov_arc: .byte 0, 5, 9, 12, 15, 17, 19, 20, 20, 20, 19, 17, 15, 12, 9, 5   ; 80 u (1 - u)
ov_hdx:  .byte 0, 3, 5          ; dentro un salto: verso la cella dopo
ov_hup:  .byte 0, 16, 16        ; 72 u (1 - u)
.assert OA_FIRST = 16 .and OA_HOP = 3, error, "YOU WIN: tabelle dei salti"
ov_box_code
.endscope


.segment "OVC"
.scope ovc
; PERFECT: l'animazione, poi la voce e il tempo.
.proc scene
    jsr ov_stamp
    inc ov_f
    bne :+
    dec ov_f
:
    jmp win_tick
.endproc
.assert scene = OV_MODE, lderror, "PERFECT: la scena non all'inizio della versione"
ov_win_tick

; PERFECT: il timbro (blocchi pieni che si stringono, OA_HOLD frame per grandezza), poi la scritta
; con la scossa, chi ha vinto sotto da OA_WIN, il riflesso da OA_GLINT.
.proc ov_stamp
    lda ov_f
    bne :+
    ; i caratteri di PERFECT al posto di alcuni di INSERT COIN e PRESS START, che si vedono solo
    ; nella demo (demo_enter rimette gli originali): la loro pagina dalla cartuccia
    lda #OVCH_SRC
    sta ef_src+2
    lda #OV_BANK
    ldx #1
    ldy #>CHARSET + PERFECT_PAGE
    jsr ef_copy
    lda ov_f
:   cmp #3 * OA_HOLD
    bcs stamped
    ldx #$ff                    ; X = f / OA_HOLD, solo al primo frame di ogni grandezza
:   inx
    sec
    sbc #OA_HOLD
    bcs :-
    adc #OA_HOLD
    jne done
    txa
    beq :+
    dex                         ; la grandezza prima torna vuota
    lda #CH_BLANK
    jsr ov_rect
    inx
:   lda #CH_SOLID
    jmp ov_rect
stamped:
    bne shake
    ; la scritta: via l'ultimo timbro, di nuovo la mezzeria che copriva, il riquadro
    ldx #2
    lda #CH_BLANK
    jsr ov_rect
    lda #8
    sta v_row
:   jsr center_line_row
    inc v_row
    lda v_row
    cmp #14
    bne :-
    jsr ov_box
    ldx top
    ldy #OV_ROW
    jsr over_big
    lda ov_f
shake:
    sec
    sbc #3 * OA_HOLD
    cmp #OA_SHAKE
    bcs :+
    tax
    lda ov_shx,x               ; la scossa: scroll fine del testo
    ora #$c8
    sta $d016
    lda ov_shy,x
    ora #$18
    sta $d011
    rts
:   bne :+
    lda #$c8
    sta $d016
:   lda ov_f
    cmp #OA_WIN
    bne :+
    ldx bottom
    bmi :+
    ldy #OV_ROW2
    jsr over_big
:   lda ov_f
    sec
    sbc #OA_GLINT
    bcc done
:   cmp #OA_GLINT_P
    bcc :+
    sbc #OA_GLINT_P
    bcs :-
:   cmp #21
    bcs done
    ; riflesso: le celle con colonna + riga nella diagonale d o d + 1 (d = k * 5 / 8 - 2)
    sta ov_n
    asl a
    asl a
    adc ov_n
    lsr a
    lsr a
    lsr a
    sec
    sbc #2
    sta ov_n
    ldy #BIG_PERFECT_W - 1
:   tya
    sec
    sbc ov_n
    jsr shade
    sta GLINT_COL,y
    tya
    clc
    adc #1                      ; la riga sotto: un passo più avanti nella diagonale
    sec
    sbc ov_n
    jsr shade
    sta GLINT_COL + 40,y
    dey
    bpl :-
done:
    rts
shade:
    cmp #2
    lda ov_tcol
    bcs :+
    lda #COL_WHITE              ; riflesso: giallo sul bianco, bianco sul giallo
    cmp ov_tcol
    bne :+
    lda egg_yel
:   rts
.endproc
ov_shx: .byte 6, 0, 6, 1, 5, 2, 4, 3           ; STAMP_SHAKE + 3 (lo scroll non va sotto 0)
ov_shy: .byte 3, 5, 1, 4, 2, 3, 3, 3
; grandezze del timbro (6, 4,5 e 3 volte le lettere): colonna, larghezza, riga, altezza
ov_stcol: .byte 8, 11, 14
ov_stw:   .byte 24, 18, 12
ov_strow: .byte 8, 9, 9
ov_sth:   .byte 6, 4, 3

; Rettangolo X del timbro pieno del carattere A, del colore della scritta.
.proc ov_rect
    pha
    lda ov_strow,x
    sta ov_row
    lda ov_sth,x
    sta ov_t
    pla
    sta ov_cx
row:
    ldy ov_row
    clc
    lda row_lo,y
    adc ov_stcol,x
    sta ptr
    lda row_hi,y
    adc #0
    sta ptr+1
    ldy ov_stw,x
    dey
    lda ov_cx
:   sta (ptr),y
    dey
    bpl :-
    lda ptr+1
    clc
    adc #>($d800 - SCREEN)
    sta ptr+1
    ldy ov_stw,x
    dey
    lda ov_tcol
:   sta (ptr),y
    dey
    bpl :-
    inc ov_row
    dec ov_t
    bne row
    rts
.endproc

ov_box_code
big_perfect: .byte BIG_PERFECT
.endscope


.segment "OVCHARS"
    .incbin "perfect_chars.bin"
.segment "CODE"
