; Grafica: VIC-II nel banco 3, caratteri per campo, punteggi e scritte, sprite per palla e
; racchette.
;
; Lo stato della partita (coordinate del core, Q16.16 con la y verso l'alto) diventa colonne e
; righe di pixel come in mister/rtl/pong_render.v: un pixel è acceso se il suo centro cade nel
; rettangolo. Le posizioni degli sprite si calcolano durante il frame in registri ombra, che si
; copiano nel VIC nel vblank (apply_shadows).

SCREEN   = $C000
CHARSET  = $C800
SPRITES  = $D000                ; RAM sotto l'I/O: il VIC la vede, il 6502 ci scrive con $01 = $34
SPR_PTR  = SCREEN + $3F8
SP_BALL4 = (SPRITES - $C000) / 64          ; palla 4x4
SP_BALL6 = SP_BALL4 + 1                    ; palla con il boost 6x6
SP_PAD0  = SP_BALL4 + 2                    ; racchette: immagini rifatte a ogni frame
SP_PAD1  = SP_BALL4 + 3
SP_BAND1 = SP_BALL4 + 6                    ; banda grigia EVO di 1 riga (poi 2, 3...)
SP_CAP0  = SP_BAND1 + SPRITE_BANDS         ; NEXT: capsula del bonus 0 (poi 1, 2..., il BULLET 7)
SP_CAPINV = SP_CAP0 + SPRITE_CAPS          ; NEXT: capsula del SUPER in negativo (lampeggio)
SP_ICON0 = SP_CAPINV + 1                   ; NEXT: icona del bonus armato 0 (poi 1, 2...)
.assert SPRITE_CAPS = B_BULLET + 1 .and SPRITE_ICONS = B_BULLET, error, "capsule per bonus, icone senza il BULLET"
SPR_X0   = 24                  ; coordinate degli sprite del primo pixel del campo
SPR_Y0   = 50
HALF_PX  = $8000

COL_BLACK  = 0
COL_WHITE  = 1
COL_RED    = 2
COL_CYAN   = 3
COL_PURPLE = 4
COL_BLUE   = 6
COL_YELLOW = 7
COL_ORANGE = 8
COL_BROWN  = 9
COL_LRED   = 10
COL_DGRAY  = 11                 ; grigio scuro: il bordo della partita con BORDER GRAY
COL_MGRAY  = 12
COL_GREEN  = 13                 ; verde chiaro: il fosforo dell'auto-test
COL_LBLUE  = 14
COL_GRAY   = 15                 ; grigio chiaro: area boost (il grigio del MiSTer)

; modi video
MODE_TEXT   = 0                 ; caratteri, schermo $C000
MODE_BITMAP = 1                 ; bitmap hires $E000, colori in $C400
MODE_OFF    = 2                 ; schermo spento: tutto del colore del bordo
MODE_HOWTO  = 3                 ; bitmap hires $E000, colori in $C000 (HOW TO PLAY, pick.s)
SCREEN2  = $C400                ; colori della bitmap
BITMAP   = $E000
SP_LINE24 = SP_BALL4 + 4        ; linea di 24 pixel (raster dell'attract)
SP_LINE8  = SP_BALL4 + 5

; righe di sprite (Y espanso: 2 righe dello schermo ciascuna)
PAD_ROWS = 21
IMG_BYTES = 3 * PAD_ROWS
PAD_FAT    = 4                  ; prima colonna doppia del corpo nell'immagine
PAD_BODY_X = 2 * PAD_FAT        ; pixel dell'immagine prima del corpo
PAD_BLINK  = 4                  ; racchetta grigia a tratti con un bonus armato (ogni 4 tick)
; colori dello sprite multicolore della racchetta
COLOR_NONE   = 0
COLOR_GRAY   = 1                ; %01: $D025
COLOR_WHITE  = 2                ; %10: colore dello sprite
COLOR_YELLOW = 3                ; %11: $D026, il giallo dei segni

; sprite della partita: la palla sopra tutto, poi le bande grigie EVO sopra le racchette
SPN_BAND = 1                    ; 1 e 2: bande delle racchette sinistra e destra
SPN_PAD  = 3                    ; 3 e 4: racchette
; NEXT (niente bande): 1 e 2 icone dei bonus armati, 5-7 capsule; la quarta capsula prende lo
; sprite 1 o 2 se il giocatore non ha un bonus armato
SPN_ICON = 1
SPN_CAP  = 5
CAP_BLINK = 8                   ; SUPER in negativo ogni 8 tick (0,16 s, come sul MiSTer)

; caratteri caricati già al loro posto; sprite caricati sul primo schermo, copiati all'avvio
.segment "CHARSET"
charset_data: .incbin "charset.bin"
.assert charset_data = CHARSET, error, "caratteri caricati dove li legge il VIC"
.segment "SPRDATA"
sprite_data:  .incbin "sprites.bin"
.assert * <= CHARSET, error, "sprite oltre il primo schermo"
.segment "RODATA"
score_tiles:  .byte SCORE_TILES
font_map:     .byte FONT_MAP
big_game_over: .byte BIG_GAME_OVER
big_p1_wins:  .byte BIG_P1_WINS
big_p2_wins:  .byte BIG_P2_WINS
big_you_win:  .byte BIG_YOU_WIN
big_cpu_wins: .byte BIG_CPU_WINS
big_insert_coin: .byte BIG_INSERT_COIN
big_press_start: .byte BIG_PRESS_START
row_lo:
    .repeat 25, i
    .byte <(SCREEN + 40 * i)
    .endrepeat
row_hi:
    .repeat 25, i
    .byte >(SCREEN + 40 * i)
    .endrepeat
; durante l'attesa della battuta la palla lampeggia: nascosta se (attesa * 8 / tick al secondo) è
; dispari, come nel gioco su PC
serve_blink:
    .repeat P_SERVE_TICKS + 1, i
    .byte (i * 8 / P_TICK_HZ) & 1
    .endrepeat

.segment "ZEROPAGE"
ptr:   .res 2
ptr2:  .res 2
v_col: .res 1
v_row: .res 1
v_n:   .res 1
sh_msb:    .res 1
sh_enable: .res 1

.segment "BSS"
; registri ombra degli 8 sprite (in partita: 0 palla, 1-2 racchette) e del modo video
sh_x:      .res 8
sh_y:      .res 8
sh_ptr:    .res 8
sh_col:    .res 8
sh_xexp:   .res 1
.segment "ZEROPAGE"
sh_yexp:   .res 1
.segment "BSS"
sh_mc:     .res 1
.segment "ZEROPAGE"
sh_bg:     .res 1               ; colore di bordo e sfondo (bianco nel lampo del punto)
.segment "BSS"
sh_brd:    .res 1               ; bordo con lo sfondo nero (border_game in partita, se no 0)
.segment "ZEROPAGE"
sh_mode:   .res 1               ; MODE_TEXT, MODE_BITMAP o MODE_OFF (schermo del colore del bordo)
.segment "BSS"
sh_img:    .res 2 * IMG_BYTES   ; immagini delle due racchette
pd_r0:     .res 1               ; righe della racchetta e dell'area boost
pd_r1:     .res 1
pd_b0:     .res 1
pd_b1:     .res 1
pd_draw_lo: .res 2              ; colonna disegnata delle racchette (scatto che scivola)
pd_draw_hi: .res 2
pd_snap:   .res 2               ; la racchetta va subito alla sua colonna
pd_home:   .res 2               ; a casa prima del tick
pd_n:      .res 2               ; righe accese nell'immagine delle racchette ($FF: da rifare)
pd_kind:   .res 2               ; tipo e variante dell'immagine
pd_var:    .res 2
pd_cur_n:  .res 2               ; righe della racchetta in questo frame
; immagine in preparazione
.segment "ZEROPAGE"
pi_side:   .res 1
.segment "BSS"
.segment "ZEROPAGE"
pi_n:      .res 1
.segment "BSS"
.segment "ZEROPAGE"
pi_kind:   .res 1
.segment "BSS"
.segment "ZEROPAGE"
pi_var:    .res 1
.segment "BSS"
.segment "ZEROPAGE"
pi_k:      .res 1
.segment "BSS"
.segment "ZEROPAGE"
pi_c:      .res 1
.segment "BSS"
pi_s:      .res 1
pi_out:    .res 1
.segment "ZEROPAGE"
pi_half:   .res 1
.segment "BSS"
pi_quarter: .res 1
pi_eighth: .res 1
pi_seg:    .res 1
pi_ammo:   .res 1
pi_full:   .res 1
.segment "ZEROPAGE"
pi_row:    .res 3
.segment "BSS"
pi_base:   .res 3               ; riga base, poi con il caricatore giallo (di seguito)
pi_basey:  .res 3
pi_tsign:  .res 1               ; TWIST: inclinazione con il segno, |t| e (k - n/2) * |t|
pi_tabs:   .res 1
pi_acc:    .res 1
pi_flags:  .res PAD_ROWS        ; righe con un segno del tipo
pd_made:   .res 1               ; immagine di racchetta già rifatta in questo frame
pd_dirty:  .res 2               ; immagine da copiare nella RAM degli sprite

.segment "CODE"

; ------------------------------------------------------------------------------------ avvio

.segment "BOOTCODE"           ; solo all'avvio (unpack.s)
.proc video_init
    ; banco VIC 3 ($C000-$FFFF): bit 0-1 di $DD00 a zero
    lda $dd02
    ora #3
    sta $dd02
    lda $dd00
    and #$fc
    sta $dd00
    lda #$02                    ; schermo $C000, caratteri $C800
    sta $d018
    lda #$1b                    ; testo, 25 righe, schermo acceso
    sta $d011
    lda #$c8                    ; 40 colonne
    sta $d016
    lda #COL_BLACK
    sta $d020
    sta $d021
    sta sh_bg
    ; (i caratteri sono già a $C800, caricati con il programma)
    ; sprite: 16 da 64 byte (4 pagine) nella RAM sotto l'I/O
    lda #<sprite_data
    sta ptr2
    lda #>sprite_data
    sta ptr2+1
    lda #<SPRITES
    sta ptr
    lda #>SPRITES
    sta ptr+1
    sei
    lda #$34
    sta $01
    ldx #(SPRITES_N * 64 + 255) / 256
    jsr copy_pages
    lda #$35
    sta $01
    cli
    lda #$ff                    ; immagini delle racchette da fare al primo frame
    sta pd_n
    sta pd_n+1
    ; colore dei caratteri: bianco
    ldx #0
    lda #COL_WHITE
:   sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $dae8,x
    inx
    bne :-
    ; multicolore degli sprite delle racchette: %01 grigio, %11 giallo (segni dei tipi di NEXT)
    lda #COL_GRAY
    sta $d025
    lda #COL_YELLOW
    sta $d026
    sta egg_yel                 ; easter egg spento (egg_check)
    lda #COL_RED
    sta egg_red
    lda #SID_SONG_TITLE
    sta egg_song
    lda #0
    sta egg_x
.ifdef EGGTEST
    ; prova per VICE (-Define EGGTEST): easter egg acceso dall'avvio, come dopo le iniziali RED
    ldx #3
:   lda egg_x,x
    eor egg_flip,x
    sta egg_x,x
    dex
    bpl :-
    lda egg_yel
    sta $d026
    lda #0
.endif
    sta $d01b                   ; sprite davanti ai caratteri
    lda #0
    sta sh_enable
    sta sh_mode
    jsr game_sprites
    jmp clear_screen
.endproc
.segment "CODE"

; Sprite della partita: palla hires bianca, bande grigie hires, racchette multicolore espanse in
; verticale.
.proc game_sprites
    lda #COL_WHITE
    sta sh_col
    sta sh_col+SPN_PAD
    sta sh_col+SPN_PAD+1
    lda #COL_GRAY
    sta sh_col+SPN_BAND
    sta sh_col+SPN_BAND+1
    lda #%11 << SPN_PAD
    sta sh_mc
    sta sh_yexp
    lda #0
    sta sh_xexp
    lda #SP_BALL4
    sta sh_ptr
    lda #SP_PAD0
    sta sh_ptr+SPN_PAD
    lda #SP_PAD1
    sta sh_ptr+SPN_PAD+1
    lda #MODE_TEXT
    sta sh_mode
    rts
.endproc

; Copia X pagine da (ptr2) a (ptr).
.proc copy_pages
    ldy #0
:   lda (ptr2),y
    sta (ptr),y
    iny
    bne :-
    inc ptr2+1
    inc ptr+1
    dex
    bne :-
    rts
.endproc

; ------------------------------------------------------------------------------------ caratteri

; Schermo di testo vuoto e caratteri del colore A (prosegue in clear_screen).
.proc clear_text
    ldx #0
:   sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $dae8,x
    inx
    bne :-
.endproc

.proc clear_screen
    ldx #0
    lda #CH_BLANK
:   sta SCREEN,x
    sta SCREEN+$100,x
    sta SCREEN+$200,x
    sta SCREEN+$2e8,x
    inx
    bne :-
    rts
.endproc

; Carattere A alla colonna X, riga Y. Cambia Y.
.proc put_char
    pha
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    txa
    tay
    pla
    sta (ptr),y
    rts
.endproc

; Carattere ASCII A con il font monospazio, alla colonna X, riga Y. Cambia Y.
.proc put_ascii
    sec
    sbc #32
    tay
    lda font_map,y
    ldy v_row
    jmp put_char
.endproc

; Stringa ASCII terminata da 0 in (ptr2), dalla colonna X alla riga Y.
.proc print_str
    sty v_row
    ldy #0
:   lda (ptr2),y
    beq done
    sty v_n
    jsr put_ascii
    ldy v_n
    inx
    iny
    bne :-
done:
    rts
.endproc

; Stampa la stringa che segue la chiamata (jsr print_at / .byte col, riga, "TESTO", 0).
.proc print_at
    pla
    sta ptr2
    pla
    sta ptr2+1
    ldy #1
    lda (ptr2),y
    tax
    iny
    lda (ptr2),y
    sta v_row
    ; ptr2 alla stringa
    clc
    lda ptr2
    adc #3
    sta ptr2
    bcc :+
    inc ptr2+1
:   ldy v_row
    jsr print_str
    ; ritorno dopo lo 0 finale: ptr2 + lunghezza + 1
    tya
    sec
    adc ptr2
    sta ptr2
    bcc :+
    inc ptr2+1
:   jmp (ptr2)
.endproc

; Numero A (0-99) con il font monospazio, due cifre, alla colonna X, riga Y.
.proc print_num2
    sty v_row
    jsr split10
    pha
    txa
    pha
    ldx v_col
    tya
    clc
    adc #'0'
    ldy v_row
    jsr put_ascii
    pla
    tax
    inx
    pla
    clc
    adc #'0'
    ldy v_row
    jmp put_ascii
.endproc

; A (0-99) -> Y decine, A unità; salva X in v_col.
.proc split10
    stx v_col
    ldy #0
:   cmp #10
    bcc :+
    sbc #10
    iny
    bne :-
:   rts
.endproc

; Cifra del punteggio A (3x3 caratteri) con l'angolo in alto a sinistra alla colonna X, riga Y.
.proc draw_digit
    sta v_n
    asl a
    asl a
    asl a
    adc v_n                     ; cifra * 9
    sta v_n
    stx v_col
    sty v_row
    ldx #3
row:
    ldy v_row
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    ldy v_col
    .repeat 3
    stx m_t
    ldx v_n
    lda score_tiles,x
    sta (ptr),y
    inc v_n
    iny
    ldx m_t
    .endrepeat
    inc v_row
    dex
    bne row
    rts
.endproc

; Scritta grande (2 righe di A caratteri, codici in (ptr2)) dalla colonna X, riga Y.
.proc draw_big
    sta v_n
    stx v_col
    sty v_row
    lda #2
    sta m_t
row:
    ldy v_row
    clc
    lda row_lo,y
    adc v_col
    sta ptr
    lda row_hi,y
    adc #0
    sta ptr+1
    ldy #0
:   lda (ptr2),y
    sta (ptr),y
    iny
    cpy v_n
    bne :-
    clc
    lda ptr2
    adc v_n
    sta ptr2
    bcc :+
    inc ptr2+1
:   inc v_row
    dec m_t
    bne row
    rts
.endproc

; Riquadro vuoto: colonne X..X+A-1, righe Y..Y+v_n-1 (v_n impostato dal chiamante).
.proc blank_box
    sta m_t
    stx v_col
    sty v_row
row:
    ldy v_row
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    ldy v_col
    ldx m_t
    lda #CH_BLANK
:   sta (ptr),y
    iny
    dex
    bne :-
    inc v_row
    dec v_n
    bne row
    rts
.endproc

; Campo: mezzeria e, in singolo, il muro a destra.
; Campo sullo schermo già pulito (clear_text).
.proc draw_field
    jsr bullet_chars
    lda #0
    sta v_row
:   jsr center_line_row
    inc v_row
    lda v_row
    cmp #25
    bne :-
    lda m_players
    cmp #1
    bne done
    ldy #24
:   sty v_row
    ldx #37
    lda #CH_WALL
    jsr put_char
    ldy v_row
    dey
    bpl :-
done:
    rts
.endproc

; Il set di caratteri è pieno: in NEXT la capsula del BULLET della riserva (8 caratteri, normale e
; in negativo) prende il posto di caratteri che in NEXT non servono, cioè cursore e reticolo
; dell'auto-test (solo all'accensione), il muro del singolo e uno di INSERT COIN della demo (EVO);
; nelle altre partite tornano quelli originali (tools/gen_c64_assets.py, BULLET_C0-7). Lì tornano
; anche quelli di PRESS START che in NEXT fanno la barra delle mosse speciali (sm_init).
.proc bullet_chars
    ldx m_next
    bne :++
    ldx #8 * BAR_CHARS - 1
:   lda bar_orig,x
    sta CHARSET + 8 * BAR_C0,x
    dex
    bpl :-
:   lda #<bullet_orig
    ldy #>bullet_orig
    ldx m_next
    beq :+
    lda #<bullet_tiles
    ldy #>bullet_tiles
:   sta ptr2
    sty ptr2+1
    ldx #0
tile:
    lda bullet_dst_lo,x
    sta ptr
    lda bullet_dst_hi,x
    sta ptr+1
    ldy #7
:   lda (ptr2),y
    sta (ptr),y
    dey
    bpl :-
    lda ptr2
    clc
    adc #8
    sta ptr2
    bcc :+
    inc ptr2+1
:   inx
    cpx #8
    bne tile
    rts
.endproc

.segment "HIBSS"                ; sotto il KERNAL: li copia title_unpack (unpack.s)
bullet_tiles: .res 64
.assert bullet_tiles = $FF40, error, "caratteri del BULLET fuori posto (gen/pick_bank.bin)"
bullet_orig:  .res 64
voice_count:  .res 3            ; VOICE_COUNT (voice.inc): RTS o il salto al conto della voce
.assert voice_count = VOICE_COUNT, error, "VOICE_COUNT fuori posto"
bar_orig:     .res 8 * BAR_CHARS ; caratteri che la barra delle mosse speciali prende in NEXT
.assert bar_orig = $FFC3, error, "originali dei caratteri della barra fuori posto (gen/pick_bank.bin)"
; easter egg (egg_check, challenge.s): li prepara video_init, li scambia egg_check; in quest'ordine
egg_x:        .res 1            ; 0, o COL_YELLOW ^ COL_RED con l'easter egg (color_span)
egg_yel:      .res 1            ; il giallo: COL_YELLOW, o COL_RED con l'easter egg
egg_red:      .res 1            ; il rosso: COL_RED, o COL_YELLOW
egg_song:     .res 1            ; canzone del titolo: SID_SONG_TITLE, o SID_SONG_EGG
egg_buf:      .res 3            ; il comando di SID_SONG_EGG dalla cartuccia (egg_stage, sid.s)
; VOLUME del menu: qui, a un indirizzo fisso, perché lo legge anche il player delle voci (voice.s)
opt_volume:   .res 1            ; passo, da 0 (0%) a VOLUME_STEPS - 1 (100%)
sid_vol:      .res 1            ; il suo volume del SID, 0-15 (vol_levels, sid.s)
.assert sid_vol = VOICE_VOL, error, "VOICE_VOL fuori posto"
.segment "RODATA"
bullet_dst_lo:
    .repeat 8, i
    .byte <(CHARSET + 8 * .ident(.sprintf("BULLET_C%d", i)))
    .endrepeat
bullet_dst_hi:
    .repeat 8, i
    .byte >(CHARSET + 8 * .ident(.sprintf("BULLET_C%d", i)))
    .endrepeat
.segment "CODE"

; Mezzeria nella riga v_row.
.proc center_line_row
    ldy v_row
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    ldy #19
    lda #CH_LINE_L
    sta (ptr),y
    iny
    lda #CH_LINE_R
    sta (ptr),y
    rts
.endproc

; Punteggi: in due ai lati della mezzeria; in singolo i colpi a sinistra, record e palle a destra.
.proc draw_scores
    lda score+1
    ldx score
    jsr clamp99
    ldx #11
    ldy #1
    jsr draw_score2
    lda m_players
    cmp #2
    bne single
    lda score+5
    ldx score+4
    jsr clamp99
    ldx #23
    ldy #1
    jmp draw_score2
single:
    jsr print_at
    .byte 24, 1, "TOP ", 0
    lda best+1
    ldx best
    jsr clamp99
    ldx #28
    ldy #1
    jsr print_num2
    jsr print_at
    .byte 24, 3, "BALLS ", 0
    lda lives
    clc
    adc #'0'
    ldx #30
    ldy #3
    sty v_row
    jmp put_ascii
.endproc

; A:X (alto:basso) -> A = valore fino a 99
.proc clamp99
    cmp #0
    bne big
    txa
    cmp #100
    bcc :+
big:
    lda #99
:   rts
.endproc

; Due cifre del punteggio A (0-99) dalla colonna X, riga Y.
.proc draw_score2
    sty v_row
    jsr split10                 ; Y decine, A unità, v_col = X
    pha
    lda v_col
    pha
    tya
    ldy v_row
    jsr draw_digit              ; decine
    pla
    clc
    adc #3
    tax
    pla
    ldy v_row
    dey
    dey
    dey
    jmp draw_digit              ; unità (draw_digit ha avanzato v_row di 3)
.endproc

; ------------------------------------------------------------------------------------ sprite

; Registri ombra dallo stato della partita.
.proc compute_sprites
    lda #0
    sta pd_made
    jsr game_sprites
    lda #0
    sta sh_enable
    sta sh_msb
    ; nel lampo del punto tutto lo schermo è bianco
    lda sh_bg
    beq :+
    rts
:   ; palla, salvo i lampi durante l'attesa della battuta
    lda serve_timer+1
    ora serve_timer+2
    ora serve_timer+3
    bne ball_on
    ldx serve_timer
    cpx #P_SERVE_TICKS + 1
    bcs ball_on
    lda serve_blink,x
    jne pads
ball_on:
    sub32 t0, ball_x, ball_r
    add32 t0, t0, {#HALF_PX - 1}
    clc
    lda t0+2
    adc #SPR_X0
    sta sh_x
    lda t0+3
    adc #0
    and #1
    sta sh_msb
    add32 t1, ball_y, ball_r
    sub32 t1, {#P_HEIGHT - HALF_PX}, t1
    clc
    lda t1+2
    adc #SPR_Y0 + 1
    sta sh_y
    ldx #SP_BALL4
    lda ball_r+2
    cmp #3
    bcc :+
    ldx #SP_BALL6
:   stx sh_ptr
    lda #%001
    sta sh_enable
    lda m_next
    beq pads
    ; GHOST: la palla si vede solo a lampi (Next::ball_hidden) e senza effetti, che la
    ; tradirebbero; le posizioni per la coda si tengono lo stesso
    lda nx_ghost
    beq fx
    jsr trail_push
    lda ghost_phase
    cmp #P_GHOST_VISIBLE
    bcc pads
    lda #0
    sta sh_enable
    beq pads
fx:
    jsr ball_fx                 ; NEXT: scia, cometa, alone
pads:
    ldx #0
    jsr pad_sprite
    lda m_players
    cmp #2
    bne :+
    ldx #4
    jsr pad_sprite
:   lda m_next
    beq :+
    jmp next_sprites
:   rts
.endproc

; NEXT: icone grigie dei bonus armati accanto alle racchette (gialla quella della mossa speciale
; armata, sm_icon) e capsule in volo (bianche, il SUPER giallo e a tratti in negativo, il BULLET
; giallo), come in mister/rtl/next_render.v. Nel bullet time le capsule bianche diventano grigie.
.proc next_sprites
    lda #0
    sta ns_icons
    ldy #0                      ; lato
armed:
    tya
    asl a
    asl a
    tax
    stx m_lo
    lda #COL_GRAY
    sta m_t
    ; STEER: il volante giallo accanto a chi guida, al posto del bonus armato
    lda nx_steer
    beq :+
    lda nx_steer_s
    cmp m_lo
    bne :+
    lda egg_yel
    sta m_t
    lda #B_STEER
    jmp show
:   jsr sm_icon                 ; mossa speciale armata: la sua icona, gialla
    bcs show
    lda nx_armed,x
    cmp #B_NONE
    beq next_side
show:
    clc
    adc #SP_ICON0
    sta sh_ptr+SPN_ICON,y
    lda m_t
    sta sh_col+SPN_ICON,y
    ; x: a sinistra 3 pixel oltre la faccia, a destra 12 pixel prima (racchetta larga 4)
    lda pd_draw_lo,y
    clc
    adc icon_dx_lo,y
    sta v_n
    lda pd_draw_hi,y
    adc icon_dx_hi,y
    sta v_col
    lda v_n
    clc
    adc #SPR_X0
    sta sh_x+SPN_ICON,y
    lda v_col
    adc #0
    and #1
    beq :+
    lda bit_of+SPN_ICON,y
    ora sh_msb
    sta sh_msb
:   ; y: 4 righe sopra il centro della racchetta
    lda #<(SPR_Y0 + (P_HEIGHT >> 16) - 4)
    sec
    sbc pad_y+2,x
    sta sh_y+SPN_ICON,y
    lda bit_of+SPN_ICON,y
    ora sh_enable
    sta sh_enable
    ora ns_icons
    sta ns_icons
next_side:
    iny
    cpy #2
    bne armed
    ; capsule: 5, 6, 7 e il primo tra 1 e 2 rimasto libero
    ldy #0
cap:
    lda cap_on,y
    jeq cap_next
    lda cap_sprite,y
    cpy #3
    bne have
    lda ns_icons
    and #bit_of_icon1
    bne :+
    lda #SPN_ICON
    jmp have
:   lda ns_icons
    and #bit_of_icon2
    bne cap_next                ; nessuno sprite libero: questa non si vede
    lda #SPN_ICON + 1
have:
    sta ns_n
    sty ns_k
    tax                         ; X = sprite
    ; immagine e colore: bianca (grigia nel bullet time), il SUPER e il BULLET gialli, il SUPER
    ; in negativo a tratti
    lda cap_bonus,y
    clc
    adc #SP_CAP0
    sta sh_ptr,x
    lda #COL_WHITE
    ldy nx_btimer
    beq :+
    lda #COL_GRAY
:   sta sh_col,x
    ldy ns_k
    lda cap_bonus,y
    cmp #B_BULLET
    bne :+
    lda egg_yel
    sta sh_col,x
:   lda cap_bonus,y
    cmp #B_SUPER
    bne :+
    lda egg_yel
    sta sh_col,x
    lda tick
    and #CAP_BLINK
    beq :+
    lda #SP_CAPINV
    sta sh_ptr,x
:   ; x: colonna del centro - CAP_DRAW / 2 (16 bit, la capsula può uscire a sinistra)
    tya
    asl a
    asl a
    tay                         ; Y = capsula * 4
    lda cap_x+2,y
    clc
    adc #<(SPR_X0 - CAP_DRAW / 2)
    sta sh_x,x
    lda cap_x+3,y
    adc #0
    and #1
    beq :+
    lda bit_of,x
    ora sh_msb
    sta sh_msb
:   ; y: riga del centro - CAP_DRAW / 2
    lda #<(SPR_Y0 + (P_HEIGHT >> 16) - CAP_DRAW / 2)
    sec
    sbc cap_y+2,y
    sta sh_y,x
    lda bit_of,x
    ora sh_enable
    sta sh_enable
    ldy ns_k
cap_next:
    iny
    cpy #4
    jne cap
    jmp warp_fx                 ; salto del TELEPORT (usa lo sprite dell'icona)
.endproc

bit_of_icon1 = 1 << SPN_ICON
bit_of_icon2 = 1 << (SPN_ICON + 1)
cap_sprite: .byte SPN_CAP, SPN_CAP + 1, SPN_CAP + 2, 0
; icona del bonus armato rispetto alla colonna sinistra della racchetta disegnata
icon_dx_lo: .byte <7, <(-12)
icon_dx_hi: .byte >7, >(-12)

.segment "BSS"
ns_icons: .res 1                ; sprite delle icone in uso (bit)
ns_n:     .res 1
ns_k:     .res 1
.segment "CODE"

; Scatto in avanti a schermo, come su PC e MiSTer: la colonna disegnata della racchetta Y (0 o 1)
; raggiunge quella della logica (t0+2, t0+3) dimezzando la distanza a ogni frame, almeno 6 pixel.
; Solo grafica: la logica resta istantanea. Oltre 100 pixel (nuova partita) o con lo scatto che
; intercetta la palla (pd_snap) arriva subito, altrimenti la palla rimbalzerebbe prima.
SLIDE_MIN = 6
SLIDE_SNAP = 100

.proc slide_x
    lda pd_snap,y
    bne snap
    ; d = destinazione - disegnata (16 bit con segno)
    sec
    lda t0+2
    sbc pd_draw_lo,y
    sta m_lo
    lda t0+3
    sbc pd_draw_hi,y
    sta m_t
    bpl pos
    ; d < 0
    cmp #$ff
    bne snap
    lda m_lo
    cmp #<(-SLIDE_SNAP)
    bcc snap
    ; delta = d / 2 (verso il basso), al massimo -6, non oltre d
    sec
    ror a
    cmp #<(-SLIDE_MIN)
    bcc add_neg
    lda m_lo
    cmp #<(-SLIDE_MIN)
    bcc :+
    jmp add_neg                 ; |d| <= 6: tutto d
:   lda #<(-SLIDE_MIN)
add_neg:
    clc
    adc pd_draw_lo,y
    sta pd_draw_lo,y
    lda pd_draw_hi,y
    adc #$ff
    sta pd_draw_hi,y
    rts
pos:
    bne snap                    ; oltre 255 pixel
    lda m_lo
    beq done
    cmp #SLIDE_SNAP + 1
    bcs snap
    lsr a
    cmp #SLIDE_MIN
    bcs add_pos
    lda m_lo
    cmp #SLIDE_MIN
    bcc add_pos                 ; |d| < 6: tutto d
    lda #SLIDE_MIN
add_pos:
    clc
    adc pd_draw_lo,y
    sta pd_draw_lo,y
    lda pd_draw_hi,y
    adc #0
    sta pd_draw_hi,y
done:
    rts
snap:
    lda #0
    sta pd_snap,y
    lda t0+2
    sta pd_draw_lo,y
    lda t0+3
    sta pd_draw_hi,y
    rts
.endproc

; Prima del tick: quali racchette sono a casa.
.proc dash_before
    ldy #0
    ldx #0
:   lda #0
    sta pd_home,y
    beq32 {pad_x,x}, {pad_home,x}, home
    jmp next
home:
    lda #1
    sta pd_home,y
next:
    inx
    inx
    inx
    inx
    iny
    cpy #2
    bne :-
    rts
.endproc

; Dopo il tick: lo scatto che ha colpito la palla (era a casa, ora no, e la palla si allontana)
; si vede subito avanzato.
.proc dash_after
    lda events
    and #EV_HIT | EV_BOOST
    beq done
    lda pd_home
    beq right
    beq32 pad_x, pad_home, right
    lda ball_vx+3
    bmi right
    lda #1
    sta pd_snap
right:
    lda pd_home+1
    beq done
    beq32 pad_x+4, pad_home+4, done
    lda ball_vx+3
    bpl done
    lda #1
    sta pd_snap+1
done:
    rts
.endproc

; Nuova partita: le racchette si disegnano subito al loro posto.
.proc slide_reset
    lda #1
    sta pd_snap
    sta pd_snap+1
    rts
.endproc

; Racchetta X (0 o 4): posizione dello sprite 1 o 2 e la sua immagine.
.proc pad_sprite
    stx side
    ; colonna: x - metà larghezza + HALF_PX - 1, in una somma
    add32 t0, {pad_x,x}, {#HALF_PX - 1 - P_PAD_HALF_W}
    txa
    lsr a
    lsr a
    tay                         ; Y = lato
    jsr slide_x                 ; colonna a schermo: lo scatto scivola in circa 5 frame
    ; la banda EVO dalla colonna della racchetta, lo sprite della racchetta 8 pixel prima (il
    ; corpo è al centro dell'immagine, con i segni dei tipi dietro e davanti)
    clc
    lda pd_draw_lo,y
    adc #SPR_X0
    sta sh_x+SPN_BAND,y
    sta v_n
    lda pd_draw_hi,y
    adc #0
    sta v_col
    and #1
    beq :+
    lda bit_of+SPN_BAND,y
    ora sh_msb
    sta sh_msb
:   ; colpo di una mossa (sm_kick, da sm_floor): la racchetta rincula verso il fondo di sm_kick / 4
    ; pixel e torna, un frame alla volta (X = side, come prima)
    ldx side
    lda sm_kick,x
    beq kicked
    dec sm_kick,x
    lsr a
    lsr a
    cpy #0                      ; C = 1
    bne kick_right
    eor #$ff                    ; a sinistra: v - A
    adc v_n
    sta v_n
    bcs kicked
    dec v_col
    bcc kicked
kick_right:
    clc                         ; a destra: v + A
    adc v_n
    sta v_n
    bcc kicked
    inc v_col
kicked:
    lda v_n
    sec
    sbc #PAD_BODY_X
    sta sh_x+SPN_PAD,y
    lda v_col
    sbc #0
    and #1
    beq :+
    lda bit_of+SPN_PAD,y
    ora sh_msb
    sta sh_msb
:   ; righe della racchetta: row_first(y + metà) e row_last(y - metà), cioè il byte 2 di
    ; u - metà (+ 1) e di u + metà con u = P_HEIGHT - HALF_PX - y. Bastano i byte 0-2: il byte 0
    ; dà solo il riporto (cmp al posto di sbc), il byte 3 non tocca il byte 2.
    sec
    lda #<(P_HEIGHT - HALF_PX)
    sbc pad_y,x
    sta t1
    lda #>(P_HEIGHT - HALF_PX)
    sbc pad_y+1,x
    sta t1+1
    lda #^(P_HEIGHT - HALF_PX)
    sbc pad_y+2,x
    sta t1+2
    lda t1
    cmp pad_half,x
    lda t1+1
    sbc pad_half+1,x
    lda t1+2
    sbc pad_half+2,x
    clc
    adc #1
    sta pd_r0
    lda t1
    clc
    adc pad_half,x
    lda t1+1
    adc pad_half+1,x
    lda t1+2
    adc pad_half+2,x
    sta pd_r1
    ; area boost (EVO): metà altezza dell'area (byte 0-2 di pad_bh / 2)
    lda m_evo
    beq image
    lda pad_bh+3,x
    lsr a
    lda pad_bh+2,x
    ror a
    sta t2+2
    lda pad_bh+1,x
    ror a
    sta t2+1
    lda pad_bh,x
    ror a
    sta t2
    lda t1
    cmp t2
    lda t1+1
    sbc t2+1
    lda t1+2
    sbc t2+2
    clc
    adc #1
    sta pd_b0
    lda t1
    clc
    adc t2
    lda t1+1
    adc t2+1
    lda t1+2
    adc t2+2
    sta pd_b1
    ; banda: sprite non espanso dalla riga b0, alto b1 - b0 + 1 righe (se ce ne sono)
    sec
    sbc pd_b0
    bcc image
    cmp #SPRITE_BANDS
    bcc :+
    lda #SPRITE_BANDS - 1
:   clc
    adc #SP_BAND1
    sta sh_ptr+SPN_BAND,y
    lda pd_b0
    clc
    adc #SPR_Y0
    sta sh_y+SPN_BAND,y
    lda bit_of+SPN_BAND,y
    ora sh_enable
    sta sh_enable
image:
    lda pd_r0
    clc
    adc #SPR_Y0
    sta sh_y+SPN_PAD,y
    lda bit_of+SPN_PAD,y
    ora sh_enable
    sta sh_enable
    ; righe dello sprite: ognuna copre le righe r0 + 2k e r0 + 2k + 1 ed è accesa se
    ; r0 + 2k <= r1, cioè le prime (r1 - r0) / 2 + 1
    lda pd_r1
    sec
    sbc pd_r0
    bcc none                    ; r1 < r0: nessuna riga
    lsr a
    clc
    adc #1
    cmp #PAD_ROWS + 1
    bcc :+
    lda #PAD_ROWS
    bne :+
none:
    lda #0
:   sta pi_n
    lda pd_r0                   ; riga del centro (salto del TELEPORT)
    clc
    adc pd_r1
    ror a
    sta pd_cy,y
    ; colore: grigio con il BULLET scattato dell'avversario, con STEER e, a tratti, con un bonus
    ; armato o con il proprio BULLET armato e non ancora scattato
    lda #COL_WHITE
    ldx m_next
    beq color
    ldx side
    lda nx_btimer
    beq :+
    cpx nx_bside
    bne gray
:   lda nx_steer
    beq :+
    lda nx_steer_s
    cmp side
    beq gray
:   lda nx_armed,x
    cmp #B_NONE
    bne blink
    lda nx_btimer
    bne white
    cpx nx_bside
    bne white
blink:
    lda tick
    and #PAD_BLINK
    beq white
gray:
    lda #COL_GRAY
    bne color
white:
    ; lampo giallo del colpo di una mossa: i primi 4 frame, e con la MAX (31) anche dal 16° al 19°
    lda sm_kick,x
    and #%1100
    cmp #%1100
    bne :+
    lda egg_yel
    bne color
:
    lda #COL_WHITE
color:
    sta sh_col+SPN_PAD,y
    ; l'immagine dipende da righe, tipo e variante: si rifà (e apply_shadows la copia) solo
    ; quando cambiano
    sty pi_side
    lda pi_n
    sta pd_cur_n,y
    jsr pad_variant
    ldy pi_side
    ; NEXT: l'immagine preparata a inizio partita, se c'è: TWIST per inclinazione, BLASTER per
    ; colpi nel caricatore (pi_ammo da pad_variant), così il caricatore cala nel frame del colpo
    lda m_next
    beq dynamic
    lda pp_ready,y
    beq dynamic
    lda pi_n
    cmp pp_n,y
    bne dynamic
    lda pi_kind
    ldx #0
    cmp #K_TWIST
    bne :+
    ldx pi_var
:   cmp #K_BLASTER
    bne :+
    ldx pi_ammo
:   txa
    clc
    adc prep_base,y
    sta sh_ptr+SPN_PAD,y
    jmp done
dynamic:
    lda pi_n
    cmp pd_n,y
    bne make
    lda pi_kind
    cmp pd_kind,y
    bne make
    lda pi_var
    cmp pd_var,y
    beq done
make:
    ; una sola immagine per frame (costa qualche migliaio di cicli): l'altra al prossimo; nel
    ; GAME OVER le racchette sono ferme e quel frame ha già le scritte da fare
    lda pd_made
    bne done
    lda state
    cmp #ST_OVER
    beq done
    lda wp_on                   ; durante il salto del TELEPORT l'immagine è quella del salto
    beq :+
    lda wp_side
    cmp pi_side
    beq done
:
    ; frame già avanti: al prossimo
    jsr frame_late
    bcs done
    inc pd_made
    lda pi_n
    sta pd_n,y
    lda pi_kind
    sta pd_kind,y
    lda pi_var
    sta pd_var,y
    lda #1
    sta pd_dirty,y
    jsr pad_image
done:
    jsr pad_spin
    ldx side
    rts
.endproc

; SUPER armato con la rotazione (animazione 0): al posto della racchetta l'immagine dell'angolo
; del frame, centrata sulla racchetta (sprite hires espanso).
.proc pad_spin
    lda m_next
    beq no
    ldy pi_side
    ldx side
    lda nx_armed,x
    cmp #B_SUPER
    bne no
    lda nx_anim,x
    bne no
    lda sp_k
    cmp #16
    bcc no                      ; immagini non ancora pronte
    tya
    asl a
    asl a
    asl a
    sta m_t
    lda tick
    and #7
    ora m_t
    clc
    adc #SP_SPIN0
    sta sh_ptr+SPN_PAD,y
    lda #COL_WHITE
    sta sh_col+SPN_PAD,y
    ; hires ed espanso
    lda bit_of+SPN_PAD,y
    eor #$ff
    and sh_mc
    sta sh_mc
    lda bit_of+SPN_PAD,y
    ora sh_xexp
    sta sh_xexp
    lda bit_of+SPN_PAD,y
    ora sh_yexp
    sta sh_yexp
    ; x: colonna della racchetta + metà larghezza - 2 * SPIN_CX (16 bit, con il bit alto)
    lda pd_draw_lo,y
    clc
    adc #<(SPR_X0 + 2 - 2 * SPIN_CX)
    sta sh_x+SPN_PAD,y
    lda pd_draw_hi,y
    adc #>(SPR_X0 + 2 - 2 * SPIN_CX)
    and #1
    beq :+
    lda bit_of+SPN_PAD,y
    ora sh_msb
    sta sh_msb
    jmp :++
:   lda bit_of+SPN_PAD,y
    eor #$ff
    and sh_msb
    sta sh_msb
:   ; y: riga del centro - 2 * SPIN_CY
    lda pd_r0
    clc
    adc pd_r1
    ror a
    clc
    adc #<(SPR_Y0 - 2 * SPIN_CY)
    sta sh_y+SPN_PAD,y
no:
    rts
.endproc

; Tipo della racchetta di pi_side (K_NONE fuori da NEXT) in pi_kind e variante dell'immagine in
; pi_var: TWIST l'inclinazione + 3, BLASTER i colpi nel caricatore * 32.
.proc pad_variant
    lda #0
    sta pi_var
    lda #K_NONE
    sta pi_kind
    lda m_next
    bne :+
    rts
:   ldx side
    lda nx_kind,x
    sta pi_kind
    cmp #K_TWIST
    beq twist
    cmp #K_BLASTER
    beq blaster
    rts
blaster:
    lda nx_ammo,x
    jsr mag_setup
    asl a
    asl a
    asl a
    asl a
    asl a
    sta pi_var
    rts
twist:
    ; inclinazione a gradini dalla velocità della racchetta (twist_tilt del MiSTer)
    abs32 n_t, {pad_motion,x}
    ldy #3
    blt32 {#TILT3}, n_t, sign
    dey
    blt32 {#TILT2}, n_t, sign
    dey
    blt32 {#TILT1}, n_t, sign
    dey
sign:
    sty m_t
    ldx side
    lda pad_motion+3,x
    bpl :+
    lda #0
    sec
    sbc m_t
    sta m_t
:   lda m_t
    clc
    adc #3
    sta pi_var
    rts
.endproc

TILT1 = P_PAD_MAX_SPEED / 6
TILT2 = P_PAD_MAX_SPEED / 2
TILT3 = P_PAD_MAX_SPEED * 5 / 6

; Caricatore del BLASTER con A colpi (come su PC, un rettangolino giallo per colpo e niente
; ricarica a schermo): dal basso un tratto di n / 4 righe per colpo, l'ultima riga spenta.
; pi_seg righe per tratto, pi_full righe dei tratti; ritorna A = colpi.
.proc mag_setup
    sta pi_ammo
    lda pi_n
    lsr a
    lsr a
    sta pi_seg
    ldy pi_ammo
    lda #0
:   dey
    bmi :+
    clc
    adc pi_seg
    bcc :-                      ; (sempre: al massimo n)
:   sta pi_full
    lda pi_ammo
    rts
.endproc
.assert P_BLASTER_SHOTS = 4, error, "caricatore del BLASTER: un tratto di n / 4 righe per colpo"

; Immagine della racchetta di pi_side in sh_img (63 byte, 3 per riga): pi_n righe di corpo con i
; segni del tipo pi_kind, come kind_px del MiSTer alla risoluzione dello sprite multicolore (2x2
; pixel). Le colonne si contano dal lato sinistro della racchetta sinistra; per la destra
; l'immagine si specchia.
; Immagine della racchetta di pi_side in sh_img (63 byte, 3 per riga): pi_n righe di corpo con i
; segni del tipo pi_kind, come kind_px del MiSTer alla risoluzione dello sprite multicolore (2x2
; pixel). Le colonne si contano dal lato sinistro della racchetta sinistra; per la destra
; l'immagine si specchia. Quasi tutte le righe sono uguali: si copia una riga base (con il
; caricatore del BLASTER giallo, o il corpo spostato di TWIST da una tabella); solo le
; poche righe con un segno si fanno colonna per colonna (slow_row).
.proc pad_image
    ldy pi_side
    lda img_base,y
    sta pi_out
    ; righe notevoli: metà, quarto, ottavo
    lda pi_n
    lsr a
    sta pi_half
    lsr a
    sta pi_quarter
    lsr a
    sta pi_eighth
    ; riga base: il corpo senza segni
    lda #0
    sta pi_row
    sta pi_row+1
    sta pi_row+2
    lda #COLOR_WHITE
    sta pi_c
    lda pi_kind
    cmp #K_HAMMER
    bne :+
    lda #PAD_FAT - 1
    jsr plot
:   lda #PAD_FAT
    jsr plot
    lda #PAD_FAT + 1
    jsr plot
    ldx #2
:   lda pi_row,x
    sta pi_base,x
    sta pi_basey,x
    dex
    bpl :-
    lda pi_kind
    cmp #K_BLASTER
    bne twist_setup
    ; BLASTER: anche con il tratto giallo del caricatore
    lda #COLOR_YELLOW
    sta pi_c
    lda #PAD_FAT - 2
    jsr plot
    ldx #2
:   lda pi_row,x
    sta pi_basey,x
    dex
    bpl :-
twist_setup:
    ; TWIST: |t| e (k - n/2) * |t| alla riga 0, poi + |t| a ogni riga
    lda pi_kind
    cmp #K_TWIST
    bne rows
    lda pi_var
    sec
    sbc #3
    sta pi_tsign
    bpl :+
    eor #$ff
    clc
    adc #1
:   sta pi_tabs
    tax
    lda #0
    sec
    sbc pi_half
    sta m_lo
    lda #0
:   dex
    bmi :+
    clc
    adc m_lo
    jmp :-
:   sta pi_acc
rows:
    jsr pad_special
    lda #0
    sta pi_k
row:
    lda pi_k
    cmp pi_n
    bcc on
    lda #0
    sta pi_row
    sta pi_row+1
    sta pi_row+2
    jmp store
on:
    lda pi_kind
    cmp #K_TWIST
    bne marks
    ; TWIST: corpo spostato di (acc >> 3) colonne doppie, con il segno dell'inclinazione
    lda pi_acc
    cmp #$80
    ror a
    cmp #$80
    ror a
    cmp #$80
    ror a
    ldx pi_tsign
    bpl :+
    eor #$ff
    clc
    adc #1
:   ldx pi_side
    beq :+
    eor #$ff                    ; destra: 4 - s
    clc
    adc #1
:   clc
    adc #PAD_FAT
    sta m_lo
    asl a
    adc m_lo                    ; * 3
    tax
    lda body2,x
    sta pi_row
    lda body2+1,x
    sta pi_row+1
    lda body2+2,x
    sta pi_row+2
    lda pi_acc
    clc
    adc pi_tabs
    sta pi_acc
    jmp store
marks:
    ldx pi_k
    lda pi_flags,x
    beq fast
    ; riga con un segno: colonna per colonna
    lda #0
    sta pi_row
    sta pi_row+1
    sta pi_row+2
    jsr slow_row
    jmp store
fast:
    ldx #0                      ; pi_base
    lda pi_kind
    cmp #K_BLASTER
    bne copy
    ; caricatore: j = n - 1 - k dal basso; tratti gialli (l'ultima riga spenta), sopra niente
    lda pi_n
    clc
    sbc pi_k
    cmp pi_full
    bcs copy
:   cmp pi_seg
    bcc :+
    sbc pi_seg
    jmp :-
:   clc
    adc #1
    cmp pi_seg
    beq copy
    ldx #3                      ; pi_basey
copy:
    lda pi_base,x
    sta pi_row
    lda pi_base+1,x
    sta pi_row+1
    lda pi_base+2,x
    sta pi_row+2
store:
    ldy pi_out
    lda pi_row
    sta sh_img,y
    lda pi_row+1
    sta sh_img+1,y
    lda pi_row+2
    sta sh_img+2,y
    iny
    iny
    iny
    sty pi_out
    inc pi_k
    lda pi_k
    cmp #PAD_ROWS
    jne row
    rts
.endproc

; Righe con un segno del tipo (strada lenta) in pi_flags: bande di HAMMER, estremità di TITAN,
; spigoli e canne del BLASTER.
.proc pad_special
    lda #0
    ldx #PAD_ROWS - 1
:   sta pi_flags,x
    dex
    bpl :-
    lda pi_kind
    cmp #K_HAMMER
    bne :+
    lda pi_half
    sec
    sbc #5
    jsr flag
    lda pi_half
    clc
    adc #4
    jmp flag
:   cmp #K_TITAN
    bne :++
    ldx pi_eighth
    beq done
:   dex
    txa
    jsr flag
    lda pi_n
    sec
    sbc pi_eighth
    stx m_t
    clc
    adc m_t
    jsr flag
    ldx m_t
    bne :-
    rts
:   cmp #K_BLASTER
    bne :+
    lda #0
    jsr flag
    ldx pi_n
    dex
    txa
    jsr flag
    lda pi_half
    sec
    sbc #2
    jsr flag
    lda pi_half
    clc
    adc #1
    jmp flag
:
done:
    rts
; segna la riga A (se è nell'immagine)
flag:
    cmp #PAD_ROWS
    bcs :+
    tay
    lda #1
    sta pi_flags,y
:   rts
.endproc

; Riga pi_k (azzerata dal chiamante) con i segni del tipo, colonna per colonna.
.proc slow_row
    ; corpo bianco su due colonne doppie (tre per HAMMER, spostate per TWIST)
    lda #COLOR_WHITE
    sta pi_c
    lda pi_kind
    cmp #K_TWIST
    bne :+
    jsr twist_shift
    jmp body2
:   cmp #K_HAMMER
    bne body
    ; HAMMER: più spessa verso il retro, con le bande grigie del peso
    lda pi_half
    sec
    sbc #5
    cmp pi_k
    beq band
    lda pi_half
    clc
    adc #4
    cmp pi_k
    bne hammer
band:
    lda #COLOR_GRAY
    sta pi_c
hammer:
    lda #PAD_FAT - 1
    jsr plot
body:
    lda #0
body2:
    sta pi_s
    clc
    adc #PAD_FAT
    jsr plot
    lda pi_s
    clc
    adc #PAD_FAT + 1
    jsr plot
    ; segni
    lda pi_kind
    cmp #K_TITAN
    beq titan
    cmp #K_BLASTER
    beq blaster
    rts
titan:
    ; TITAN: estremità gialle sul retro (un ottavo dell'altezza)
    lda pi_k
    cmp pi_eighth
    bcc mark
    lda pi_n
    sec
    sbc pi_eighth
    cmp pi_k
    beq mark
    bcs store
mark:
    lda #COLOR_YELLOW
    sta pi_c
    lda #PAD_FAT
    jsr plot
    rts
blaster:
    ; BLASTER: spigoli del davanti smussati
    lda pi_k
    beq cut
    ldx pi_n
    dex
    cpx pi_k
    bne barrels
cut:
    lda #COLOR_NONE
    sta pi_c
    lda #PAD_FAT + 1
    jsr plot
barrels:
    ; canne grigie davanti, sopra e sotto il centro
    lda pi_half
    sec
    sbc #2
    cmp pi_k
    beq barrel
    lda pi_half
    clc
    adc #1
    cmp pi_k
    bne ammo
barrel:
    lda #COLOR_GRAY
    sta pi_c
    lda #PAD_FAT + 2
    jsr plot
ammo:
    ; caricatore dietro: dal basso un tratto giallo per colpo (l'ultima riga di ogni tratto
    ; spenta)
    lda pi_n
    clc
    sbc pi_k                    ; j = n - 1 - k, riga contata dal basso
    cmp pi_full
    bcs store
:   cmp pi_seg                  ; j % seg
    bcc :+
    sbc pi_seg
    jmp :-
:   clc
    adc #1
    cmp pi_seg
    beq store                   ; ultima riga del tratto: spenta
    lda #COLOR_YELLOW
    sta pi_c
    lda #PAD_FAT - 2
    jmp plot
store:
    rts
.endproc

; corpo di TWIST: due colonne doppie bianche dalla colonna f (0-10), 3 byte per f
body2:
    .byte $A0, $00, $00,  $28, $00, $00,  $0A, $00, $00,  $02, $80, $00
    .byte $00, $A0, $00,  $00, $28, $00,  $00, $0A, $00,  $00, $02, $80
    .byte $00, $00, $A0,  $00, $00, $28,  $00, $00, $0A

img_base: .byte 0, IMG_BYTES
prep_base: .byte SP_PREP0, SP_PREP0 + 7

; TWIST: spostamento orizzontale della riga pi_k in colonne doppie, ((k - n/2) * |t|) >> 3 con il
; segno dell'inclinazione t = pi_var - 3 (positiva: faccia verso l'alto).
.proc twist_shift
    lda pi_var
    sec
    sbc #3
    sta m_t                     ; t
    bpl :+
    eor #$ff
    clc
    adc #1
:   tax                         ; |t|
    lda pi_k
    sec
    sbc pi_half
    sta m_lo                    ; d
    lda #0
:   dex
    bmi :+
    clc
    adc m_lo
    jmp :-
:   cmp #$80                    ; >> 3 con il segno
    ror a
    cmp #$80
    ror a
    cmp #$80
    ror a
    ldx m_t
    bpl :+
    eor #$ff
    clc
    adc #1
:   rts
.endproc

; Colonna doppia A (vista dalla racchetta sinistra, 0-9) della riga pi_row nel colore pi_c; per la
; racchetta destra la colonna si specchia (9 - A).
.proc plot
    ldx pi_side
    beq :+
    eor #$ff
    sec
    adc #9
:   cmp #12
    bcs out                     ; fuori dall'immagine
    tax
    ldy fat_byte,x
    lda pi_row,y
    and fat_clear,x
    sta m_lo
    ldy pi_c
    lda color_all,y
    and fat_mask,x
    ora m_lo
    ldy fat_byte,x
    sta pi_row,y
out:
    rts
.endproc

fat_byte:  .byte 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2
fat_mask:  .byte $C0, $30, $0C, $03, $C0, $30, $0C, $03, $C0, $30, $0C, $03
fat_clear: .byte $3F, $CF, $F3, $FC, $3F, $CF, $F3, $FC, $3F, $CF, $F3, $FC
color_all: .byte $00, $55, $AA, $FF  ; nessuno, grigio (%01), bianco (%10), giallo (%11)

bit_of: .byte %00000001, %00000010, %00000100, %00001000, %00010000, %00100000, %01000000, %10000000

; Nel vblank: registri ombra nel VIC, immagini delle racchette nella RAM degli sprite. Copie
; srotolate: è codice di ogni frame.
.proc apply_shadows
    .repeat 8, i
    lda sh_x+i
    sta $d000+2*i
    lda sh_y+i
    sta $d001+2*i
    lda sh_col+i
    sta $d027+i
    .endrepeat
    lda sh_msb
    sta $d010
    lda sh_xexp
    sta $d01d
    lda sh_yexp
    sta $d017
    lda sh_mc
    sta $d01c
    ; bordo e sfondo solo quando cambiano: ogni scrittura in un registro di colore mentre quel
    ; colore è a schermo lascia un pixel grigio chiaro (il "grey dot" dei VIC-II nuovi), e qui
    ; il raster è nel bordo in basso, a una colonna che cambia con il ritardo dell'interrupt. Il
    ; bordo è quello dello sfondo se non è nero (lampo del punto, attract), se no sh_brd (in
    ; partita con BORDER GRAY, border_game; altrimenti 0, nero)
    lda sh_bg
    eor $d021                   ; (letti, hanno il nibble alto a 1)
    and #$0f
    beq :+
    lda sh_bg
    sta $d021
:   lda sh_bg
    bne :+
    lda sh_brd
:   tax
    eor $d020
    and #$0f
    beq :+
    stx $d020
:
    ; modo video e puntatori degli sprite (in fondo allo schermo in uso)
    ldx sh_mode
    lda mode_d011,x
    sta $d011
    lda mode_d018,x
    sta $d018
    cpx #MODE_BITMAP
    beq bitmap
    .repeat 8, i
    lda sh_ptr+i
    sta SPR_PTR+i
    .endrepeat
    jmp pointers_done
bitmap:
    .repeat 8, i
    lda sh_ptr+i
    sta SCREEN2 + $3f8+i
    .endrepeat
pointers_done:
    lda sh_enable
    sta $d015
    ; immagini delle racchette cambiate (di rado: altezza, tipo, inclinazione, caricatore)
    lda pd_dirty
    ora pd_dirty+1
    beq done
    bit $fffb                   ; con la voce di CHALLENGE l'I/O resta acceso (gli NMI scrivono
    bmi done                    ; nel SID): la copia aspetta che finisca (racchette ferme o già
    sei                         ; preparate in $E000)
    lda #$34
    sta $01
    lda pd_dirty
    beq right
    ldx #IMG_BYTES - 1
:   lda sh_img,x
    sta SPRITES + 2 * 64,x
    dex
    bpl :-
right:
    lda pd_dirty+1
    beq copied
    ldx #IMG_BYTES - 1
:   lda sh_img + IMG_BYTES,x
    sta SPRITES + 3 * 64,x
    dex
    bpl :-
copied:
    lda #$35
    sta $01
    cli
    lda #0
    sta pd_dirty
    sta pd_dirty+1
done:
    rts
.endproc

; $D011 e $D018 dei modi video: testo ($C000, caratteri $C800), bitmap ($E000, colori $C400),
; schermo spento
mode_d011: .byte $1b, $3b, $0b, $3b
mode_d018: .byte $02, $18, $02, $08

; ------------------------------------------------------------------------------------ effetti

; NEXT: effetti della palla come sul MiSTer, con lo sprite della palla, nella bitmap dell'attract
; a $E000 (in partita non serve: l'attract la rifà da capo). La coda e la cometa si disegnano in
; partita dalle posizioni vere della palla (trail_end); gli aloni si preparano a inizio partita.
SP_FX0    = ($E000 - $C000) / 64 ; prima immagine: gli sprite della coda, poi gli aloni
TRAIL_BUFS = 4                  ; coda della palla: sprite della cache (trail_end)
SP_TRAIL0 = SP_FX0
SP_RING0  = SP_FX0 + TRAIL_BUFS ; alone di SLOW, palla 4 e 6

; Un'immagine degli effetti per frame, finché non ci sono tutte: gli aloni si disegnano dai
; quadrati di FX_SQUARES (x, y, lato in pixel; $FF chiude l'immagine), che fx_sp scorre.
; Un'immagine si fa solo se il frame resta sotto circa 17.000 cicli.
FX_COST = 10500
FX_LATE = (17000 - FX_COST) / 58
.proc fx_copy
    lda fx_wait                 ; i primi frame della partita hanno già molto da fare
    beq :+
    dec fx_wait
    rts
:   lda fx_pages
    cmp #FX_SPRITES
    bcc :+
    rts
:   lda #FX_LATE                ; un alone costa fino a FX_COST cicli: con il frame avanti al
    jsr frame_after             ; prossimo
    bcc :+
    rts
:   lda fx_pages
    bne :+
    lda #<fx_squares            ; prima immagine: dall'inizio dei quadrati
    sta fx_sp
    lda #>fx_squares
    sta fx_sp+1
:   ; sprite di destinazione: $C000 + (SP_RING0 + immagine) * 64
    lda fx_pages
    clc
    adc #SP_RING0
    pha
    lsr a
    lsr a
    clc
    adc #>$C000
    sta ptr+1
    pla
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    sta ptr
    ldy #62
    lda #0
:   sta (ptr),y
    dey
    bpl :-
square:
    ldy #0
    lda (fx_sp),y
    cmp #$ff
    beq end
    sta fx_x
    iny
    lda (fx_sp),y
    sta fx_y
    iny
    lda (fx_sp),y
    sta fx_n
    lda fx_sp
    clc
    adc #3
    sta fx_sp
    bcc :+
    inc fx_sp+1
:   lda #0
    sta fx_j
rows:
    lda #0
    sta fx_i
cols:
    lda fx_x
    clc
    adc fx_i
    tax
    lda fx_y
    clc
    adc fx_j
    tay
    jsr spin_plot
    inc fx_i
    lda fx_i
    cmp fx_n
    bne cols
    inc fx_j
    lda fx_j
    cmp fx_n
    bne rows
    jmp square
end:
    inc fx_sp
    bne :+
    inc fx_sp+1
:   inc fx_pages
    rts
.endproc

; Immagine della palla con l'effetto: cometa del SUPER, alone di SLOW (a tratti), coda grigia che
; sfuma con boost, curva, STEER, SUPER, SLOW o BULLET. Il SUPER in volo è giallo. Coda e cometa
; vengono dalle posizioni vere della palla (trail_end).
.proc ball_fx
    jsr trail_push              ; posizioni della palla per la coda, a ogni frame
    ldx #0                      ; palla di 4 pixel (0) o 6 (8)
    lda sh_ptr
    cmp #SP_BALL6
    bne :+
    ldx #8
:   stx fx_size
    lda #0
    sta tr_cm                   ; coda grigia
    lda nx_super
    beq slow
    lda egg_yel
    sta sh_col
    lda nx_super_a
    cmp #2
    bne trail
    inc tr_cm                   ; cometa: coda gialla più piena, nello sprite espanso
    jmp trail
slow:
    lda nx_slow
    ora nx_slow+1
    beq plain
    lda tick
    and #4
    beq trail
    lda fx_pages
    cmp #FX_SPRITES
    bcc trail
    ; alone: sprite normale, palla nel pixel (FX_RING_X, FX_RING_Y)
    lda fx_size
    lsr a
    lsr a
    lsr a
    clc
    adc #SP_RING0
    sta sh_ptr
    lda #FX_RING_X
    ldx #FX_RING_Y
    jmp shift
plain:
    ; coda anche con boost, curva, STEER, BULLET e il tiro di una mossa speciale
    lda nx_steer
    ora nx_btimer
    ora sm_fl
    bne trail
    or32 nx_curve
    bne trail
    beq32 ball_boost, {#ONE}, none
trail:
    ; coda dalle posizioni vere, ridisegnata a fine frame (trail_end); intanto l'immagine di prima
    ; se è dello stesso tipo e con la palla nello stesso angolo, o la palla semplice: dopo un
    ; rimbalzo l'immagine di prima avrebbe la coda davanti alla palla (e trail_end, nei frame
    ; carichi, può non fare in tempo a sostituirla)
    lda #1
    sta tr_want
    lda tr_ready
    beq none
    lda tr_cm
    cmp tr_shcm
    bne none
    jsr trail_dir
    cmp tr_shdir
    bne none
    jsr trail_attr
    lda tr_buf
    clc
    adc #SP_TRAIL0
    sta sh_ptr
    lda tr_ax
    ldx tr_ay
shift:
    ; lo sprite comincia A pixel a sinistra e X sopra la palla
    stx m_t
    sta m_lo
    lda sh_x
    sec
    sbc m_lo
    sta sh_x
    lda sh_msb
    sbc #0
    and #1
    sta m_lo
    lda sh_msb
    and #$fe
    ora m_lo
    sta sh_msb
    lda sh_y
    sec
    sbc m_t
    sta sh_y
none:
    rts
.endproc

; A = angolo dello sprite della coda in cui sta la palla, dal moto (come trail_layout): bit 7 il
; segno di vx, bit 0-1 vy (0 sale, 1 orizzontale, 2 scende). Cambia Y.
.proc trail_dir
    lda ball_vy+3
    bmi fall
    ora ball_vy+2
    ora ball_vy+1
    ora ball_vy
    beq level
    lda #0
    beq vx
fall:
    lda #2
    bne vx
level:
    lda #1
vx:
    ldy ball_vx+3
    bpl :+
    ora #$80
:   rts
.endproc

; Sprite della palla per la coda: multicolore, oppure (cometa) hires espanso.
.proc trail_attr
    lda tr_cm
    bne comet
    lda sh_mc
    ora #1
    sta sh_mc
    rts
comet:
    lda sh_xexp
    ora #1
    sta sh_xexp
    lda sh_yexp
    ora #1
    sta sh_yexp
    rts
.endproc

; ------------------------------------------------------------------------ coda della palla

; La coda grigia di boost, curva, STEER, SUPER e SLOW, come su PC e MiSTer: le posizioni vere della
; palla negli ultimi TRAIL_N frame (0,1 s), e quelle a metà tra due frame se la palla va così
; veloce che non si toccano, sempre più rade (retino per età, TRAIL_DITHER), nello sprite
; multicolore della palla (pixel doppi, griglia 12x21) con la palla nell'angolo dalla parte del
; moto. Segue così la traiettoria, anche dopo un rimbalzo.
; Si prepara a fine frame (trail_end), quando il resto è fatto, con le posizioni della palla di
; questo tick; il puntatore cambia nel vblank. Cache: TRAIL_BUFS sprite con la forma che contengono
; (posizioni nello sprite e lato della palla, la "firma"). A velocità costante la forma vista dalla
; palla si ripete (cambia solo l'arrotondamento ai pixel): se è già in uno sprite basta puntarlo,
; altrimenti si disegna in quello usato meno di recente, mai in quello che si vede, e solo se il
; frame ha ancora il tempo; se no resta l'immagine di prima, agganciata alla palla. Quadrati già
; ritagliati in tabella (TRAIL_X_*, TRAIL_Y_*).
; La cometa del SUPER usa le stesse posizioni e la stessa cache in uno sprite hires espanso (pixel
; 2x2, griglia 24x21, il doppio di strada): testa di COMET_HEAD pixel doppi attorno alla palla (3),
; poi quadrati gialli pieni sempre più piccoli con l'età (comet_side), come la cometa del PC.
TRAIL_BASE = $C000 + SP_TRAIL0 * 64
COMET_S    = 3                  ; palla della cometa in pixel doppi (il "lato" della firma)
COMET_HEAD = 5
TRAIL_KEY = 2 * (TRAIL_N + 1) + 1   ; firma: tr_qxk, tr_qyk, tr_s (di seguito in memoria)
; righe dopo l'inizio del vblank oltre le quali la coda aspetta il frame dopo: la ricerca nella
; cache costa al massimo circa 1.000 cicli (255: il massimo che frame_after conta), il disegno
; circa 4.000 (misurati con paddws-c64 frames). Il disegno si fa solo se il frame resta sotto
; circa 16.500 cicli: nei frame più carichi aspetta, intanto c'è la forma della cache più simile
TRAIL_LATE_FIND = 255
TRAIL_LATE = (16500 - 4000) / 58

; Posizione della palla sullo schermo (sh_x con il nono bit in sh_msb, sh_y) in testa alle passate.
; Nel bullet time la coda dura il doppio, come sul PC: nei tick dispari cambia solo la posizione di
; adesso, così le passate sono di 2 frame in 2 frame (e la firma va rifatta da capo).
.proc trail_push
    lda tr_lay                  ; la firma dell'ultimo frame vale per il prossimo solo se è di quello
    sta tr_prev_ok
    lda #0
    sta tr_lay
    lda nx_btimer
    beq :+
    lda tick
    lsr a
    bcc :+
    lda #0
    sta tr_prev_ok
    beq head
:   ldx #TRAIL_N
:   lda tr_x-1,x
    sta tr_x,x
    lda tr_xh-1,x
    sta tr_xh,x
    lda tr_y-1,x
    sta tr_y,x
    dex
    bne :-
head:
    lda sh_x
    sta tr_x
    lda sh_msb
    and #1
    sta tr_xh
    lda sh_y
    sta tr_y
    rts
.endproc

; A fine frame: la coda chiesta da ball_fx, dalla cache o disegnata se c'è ancora tempo; la palla
; passa a quello sprite.
.proc trail_end
    lda tr_want
    jeq done
    lda #0
    sta tr_want
    lda #TRAIL_LATE_FIND
    jsr frame_after
    jcs done
    lda tr_ready                ; prima coda della partita: la cache ha la bitmap dell'attract
    bne layout
    ldx #TRAIL_BUFS - 1
    stx tr_shown
invalid:
    lda #0
    sta tr_valid,x
    lda #$fe                    ; i più vecchi: si riempiono per primi
    sta tr_old,x
    dex
    bpl invalid
layout:
    jsr trail_layout
    ; nella cache? Prima lo sprite che si vede, quasi sempre quello giusto
    ldx tr_shown
    jsr trail_match
    bcs show
    lda #TRAIL_BUFS - 1
    sta tr_b
find:
    ldx tr_b
    cpx tr_shown
    beq other
    jsr trail_match
    bcs show
other:
    dec tr_b
    bpl find
    ; da disegnare, se c'è tempo, nello sprite usato meno di recente tra quelli che non si vedono
    lda #TRAIL_LATE
    jsr frame_after
    jcs done
    ldy #$ff                    ; più vecchio finora (età + 1, 0 = nessuno)
    lda #0
    sta tr_t
    ldx #TRAIL_BUFS - 1
old:
    cpx tr_shown
    beq :+
    lda tr_old,x
    clc
    adc #1
    cmp tr_t
    bcc :+
    sta tr_t
    txa
    tay
:   dex
    bpl old
    tya
    tax
    jsr trail_draw
show:
    ; età nella cache: questo appena usato, gli altri un frame in più (fino a 255)
    stx tr_shown
    ldy #TRAIL_BUFS - 1
aging:
    lda tr_old,y
    cmp #$fe                    ; fino a 254: età + 1 sta in un byte
    bcs aged
    adc #1
    sta tr_old,y
aged:
    dey
    bpl aging
    lda #0
    sta tr_old,x
    lda #1
    sta tr_ready
    txa
    sta tr_buf
    clc
    adc #SP_TRAIL0
    sta sh_ptr
    jsr trail_attr
    lda tr_cm
    sta tr_shcm
    lda tr_dir
    sta tr_shdir
    ; palla nello sprite: dalla firma (posizione di adesso + 16), nella cometa in pixel doppi
    lda tr_qxk
    sec
    sbc #16
    ldy tr_cm
    beq :+
    asl a
:   sta tr_ax
    lda tr_qyk
    sec
    sbc #16
    ldy tr_cm
    beq :+
    asl a
:   sta tr_ay
    ; lo sprite comincia tr_ax pixel a sinistra e tr_ay sopra la palla
    lda tr_x
    sec
    sbc tr_ax
    sta sh_x
    lda tr_xh
    sbc #0
    and #1
    sta m_lo
    lda sh_msb
    and #$fe
    ora m_lo
    sta sh_msb
    lda tr_y
    sec
    sbc tr_ay
    sta sh_y
done:
    rts
.endproc

; C = 1 se la forma nello sprite X della cache va bene per la firma di adesso: ogni valore al più
; 1 pixel diverso (non si vede; l'angolo della palla e il lato invece cambiano di almeno 2). Le
; firme sono salvate aumentate di 1: salvata - adesso = differenza + 1, da 0 a 2 se va bene.
; Confronto srotolato. X resta.
.proc trail_match
    lda tr_valid,x
    bne :+
    clc
    rts
:
    ldy tr_keyof,x
    .repeat ::TRAIL_KEY, i
    lda tr_keys + i,y
    sec
    sbc tr_qxk + i
    cmp #3
    bcs no
    .if i = ::TRAIL_KEY / 2
    jmp more                    ; uscita a metà: i salti la raggiungono da tutte e due le parti
no:
    clc
    rts
more:
    .endif
    .endrepeat
    sec
    rts
.endproc

; La firma della coda di adesso: lato della palla, palla nell'angolo dalla parte del moto, posizioni
; nello sprite + 16 in tr_qxk e tr_qyk ($FF tutte e due se fuori dalla portata delle tabelle).
.proc trail_layout
    jsr trail_dir
    sta tr_dir
    and #3
    sta tr_t                    ; 0 sale, 1 orizzontale, 2 scende
    lda tr_cm
    jne comet
    ; palla di 4 o 6 pixel: tabelle dal primo o dal secondo gruppo
    ldx #4
    lda #0
    ldy fx_size
    beq :+
    ldx #6
    lda #TRAIL_SPAN
:   stx tr_s
    sta tr_so
    ; x pari (pixel doppi)
    lda #16
    bit tr_dir
    bmi set_x
    lda #24 + 16
    sec
    sbc tr_s
set_x:
    sta tr_axo
    ; y del core verso l'alto: la palla che sale sta in alto, con la coda sotto; in orizzontale a
    ; metà, (21 - lato) / 2; quella che scende in basso, 21 - lato
    lda #21
    sec
    sbc tr_s
    ldy tr_t
    beq rising
    dey
    bne set_y16
    lsr a
set_y16:
    clc
    adc #16
    bne set_y
rising:
    lda #16
set_y:
    sta tr_ayo
    ; dalla firma del frame prima, se è di quel frame e la palla ha ancora lo stesso angolo e lato:
    ; le posizioni scalano di un posto e si spostano del movimento della palla (somma a 8 bit)
    lda tr_prev_ok
    jeq full
    lda tr_s
    cmp tr_sp
    jne full
    lda tr_axo
    cmp tr_qxk
    bne full
    lda tr_ayo
    cmp tr_qyk
    bne full
    lda tr_x+1                  ; x di un frame fa - x di adesso, tra -47 e 47
    sec
    sbc tr_x
    sta tr_bx
    lda tr_xh+1
    sbc tr_xh
    beq :+
    cmp #$ff
    bne full
    lda tr_bx
    cmp #256 - TRAIL_SPAN + 1
    bcc full
    bcs dy
:   lda tr_bx
    cmp #TRAIL_SPAN
    bcs full
dy:
    lda tr_y+1                  ; y di un frame fa - y di adesso
    sec
    sbc tr_y
    sta tr_by
    bcc :+
    cmp #TRAIL_SPAN
    bcs full
    bcc shift
:   cmp #256 - TRAIL_SPAN + 1
    bcc full
shift:
    ldx #TRAIL_N
moved:
    lda tr_qxk-1,x
    cmp #$ff
    beq gone
    clc
    adc tr_bx                   ; fuori dallo sprite (anche sotto zero: da $D1): $FF
    cmp #TRAIL_SPAN
    bcs gone
    sta tr_qxk,x
    lda tr_qyk-1,x
    clc
    adc tr_by
    cmp #TRAIL_SPAN
    bcs gone
    sta tr_qyk,x
    dex
    bne moved
    jmp done
gone:
    lda #$ff
    sta tr_qxk,x
    sta tr_qyk,x
    dex
    bne moved
    jmp done
full:
    ldx #TRAIL_N
rel:
    lda tr_x,x
    sec
    sbc tr_x
    sta tr_t
    lda tr_xh,x
    sbc tr_xh
    ldy tr_cm                   ; cometa: in pixel doppi, / 2 con il segno
    beq :+
    cmp #$80
    ror a
    ror tr_t
:   sta tr_t+1
    lda tr_t
    clc
    adc tr_axo
    sta tr_t
    lda tr_t+1
    adc #0
    bne far
    lda tr_t
    cmp #TRAIL_SPAN
    bcs far
    sta tr_qxk,x
    lda tr_y,x
    sec
    sbc tr_y
    sta tr_t
    lda #0
    sbc #0
    ldy tr_cm
    beq :+
    cmp #$80
    ror a
    ror tr_t
:   sta tr_t+1
    lda tr_t
    clc
    adc tr_ayo
    sta tr_t
    lda tr_t+1
    adc #0
    bne far
    lda tr_t
    cmp #TRAIL_SPAN
    bcs far
    sta tr_qyk,x
    dex
    bpl rel
    bmi done
far:
    lda #$ff
    sta tr_qxk,x
    sta tr_qyk,x
    dex
    bpl rel
done:
    lda #1                      ; firma di questo frame (trail_push la passa a tr_prev_ok)
    sta tr_lay
    lda tr_s
    sta tr_sp
    rts
comet:
    ; cometa: in pixel doppi, testa (palla + 1 per parte) nell'angolo dalla parte del moto
    lda #COMET_S
    sta tr_s
    lda #1 + 16
    bit tr_dir
    bmi :+
    lda #24 - COMET_S - 1 + 16
:   sta tr_axo
    ldy tr_t
    lda comet_y,y
    sta tr_ayo
    jmp full                    ; sempre da capo: le metà non si sommano
.endproc

; Disegna la coda (o la cometa) di tr_qxk e tr_qyk nello sprite X della cache, svuotato, e ne salva
; la firma.
.proc trail_draw
    stx tr_dbuf
    txa                         ; indirizzo: TRAIL_BASE + X * 64
    lsr a
    lsr a
    clc
    adc #>TRAIL_BASE
    sta ptr+1
    txa
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    sta ptr
    tax
    lda #0
    .repeat 63, i
    sta TRAIL_BASE + i,x        ; X = 64 * sprite (fino a 192, + 62)
    .endrepeat
    ; dalla più vecchia: la posizione di k frame fa (età 2k - 1), poi quella a metà con k - 1 (età
    ; 2k - 2), solo se tra le due c'è un buco (distanza maggiore del lato)
    ldx #TRAIL_N
age:
    stx tr_k
    lda tr_qxk,x
    bmi next
    sta tr_qx
    lda tr_qyk,x
    sta tr_qy
    txa
    asl a
    sec
    sbc #1
    sta tr_age
    jsr tr_square
    ldx tr_k
    lda tr_qxk-1,x
    bmi next
    sec
    sbc tr_qxk,x
    bcs :+
    eor #$ff
    adc #1
:   cmp tr_s
    beq dy
    bcs mid
dy:
    lda tr_qyk-1,x
    sec
    sbc tr_qyk,x
    bcs :+
    eor #$ff
    adc #1
:   cmp tr_s
    beq next
    bcc next
mid:
    lda tr_qxk,x
    clc
    adc tr_qxk-1,x
    lsr a
    sta tr_qx
    lda tr_qyk,x
    clc
    adc tr_qyk-1,x
    lsr a
    sta tr_qy
    dec tr_age
    jsr tr_square
next:
    ldx tr_k
    dex
    bne age
    ; la palla, sopra la coda
    lda tr_qxk
    sta tr_qx
    lda tr_qyk
    sta tr_qy
    lda #$ff
    sta tr_age
    jsr tr_square
    ; firma nella cache, aumentata di 1 (trail_match)
    ldx tr_dbuf
    ldy tr_keyof,x
    ldx #0
:   lda tr_qxk,x
    clc
    adc #1
    sta tr_keys,y
    iny
    inx
    cpx #TRAIL_KEY
    bne :-
    ldx tr_dbuf
    lda #1
    sta tr_valid,x
    rts
.endproc

; Quadrato della coda o della cometa, secondo tr_cm.
.proc tr_square
    lda tr_cm
    bne comet_square
    jmp trail_square
.endproc

; Cometa: quadrato pieno in (tr_qx, tr_qy) + 16 dello sprite hires in (ptr), di lato comet_side
; per l'età tr_age; tr_age = $FF: la testa, COMET_HEAD attorno alla palla. Ritagliato alla griglia
; 24x21. Usa tr_qx e tr_qy (trail_draw li rifà per ogni quadrato), non tr_age.
.proc comet_square
    ldx tr_age
    bmi head
    lda comet_side,x
    sta tr_n
    lda tr_qx
    ldx tr_qy
    jmp draw
head:
    lda #COMET_HEAD
    sta tr_n
    ldx tr_qy
    dex
    lda tr_qx
    sec
    sbc #1
draw:
    sta tr_t                    ; sinistra + 16
    stx tr_t+1                  ; alto + 16
    ; colonne x0 = max(sinistra, 0), x1 = min(sinistra + lato - 1, 23)
    clc
    adc tr_n
    sec
    sbc #16 + 1
    jcc out
    cmp #24
    bcc :+
    lda #23
:   sta tr_rm
    lda tr_t
    sec
    sbc #16
    bcs :+
    lda #0
:   cmp #24
    jcs out
    sta tr_lm
    ; righe y0 = max(alto, 0), y1 = min(alto + lato - 1, 20)
    lda tr_t+1
    clc
    adc tr_n
    sec
    sbc #16 + 1
    bcc out
    cmp #21
    bcc :+
    lda #20
:   sta tr_r0
    lda tr_t+1
    sec
    sbc #16
    bcs :+
    lda #0
:   cmp #21
    bcs out
    sta tr_qy
    eor #$ff                    ; righe: y1 - y0 + 1
    sec
    adc tr_r0
    sta tr_n
    inc tr_n
    ; maschere: dal pixel x0 a fine byte, da inizio byte al pixel x1 (in un byte solo: insieme)
    lda tr_lm
    and #7
    tay
    lda comet_from,y
    sta tr_bl
    lda tr_rm
    and #7
    tay
    lda comet_to,y
    sta tr_br
    lda tr_lm
    lsr a
    lsr a
    lsr a
    sta tr_b0
    lda tr_rm
    lsr a
    lsr a
    lsr a
    cmp tr_b0
    bne :+
    lda tr_bl
    and tr_br
    sta tr_bl
    lda #0
    sta tr_br
:   lda tr_qy                   ; Y = 3 * y0 + byte
    asl a
    adc tr_qy
    adc tr_b0
    tay
    lda tr_br
    bne two
one:
    lda tr_bl
    ora (ptr),y
    sta (ptr),y
    iny
    iny
    iny
    dec tr_n
    bne one
out:
    rts
two:
    lda tr_bl
    ora (ptr),y
    sta (ptr),y
    iny
    lda tr_br
    ora (ptr),y
    sta (ptr),y
    iny
    iny
    dec tr_n
    bne two
    rts
.endproc

; Quadrato della palla in (tr_qx, tr_qy) dello sprite in (ptr), coordinate + 16 (tabelle già
; ritagliate): grigio %01 con il retino dell'età tr_age, oppure (tr_age = $FF) la palla, %10 al
; posto di quello che c'è.
.proc trail_square
    lda tr_qx
    clc
    adc tr_so
    tax
    lda trail_x_lm,x
    beq out
    sta tr_lm
    lda trail_x_rm,x
    sta tr_rm
    lda trail_x_b0,x
    sta tr_b0
    lda tr_qy
    clc
    adc tr_so
    tax
    lda trail_y_rows,x
    beq out
    sta tr_n
    lda trail_y_r0,x
    sta tr_r0
    lda trail_y_base,x
    clc
    adc tr_b0
    tay
    ldx tr_age
    bmi ball
    lda trail_age,x
    clc
    adc tr_r0
    tax                         ; retino: età * TRAIL_ROWS + riga
    lda tr_rm
    bne two
one:
    lda trail_dither,x
    and tr_lm
    ora (ptr),y
    sta (ptr),y
    inx
    iny
    iny
    iny
    dec tr_n
    bne one
out:
    rts
two:
    lda trail_dither,x
    and tr_lm
    ora (ptr),y
    sta (ptr),y
    iny
    lda trail_dither,x
    and tr_rm
    ora (ptr),y
    sta (ptr),y
    inx
    iny
    iny
    dec tr_n
    bne two
    rts
ball:
    ; la palla: i pixel doppi delle maschere a %10 (la palla sta sempre in un byte o due interi)
    lda tr_lm
    and #$aa
    sta tr_bl
    lda tr_rm
    and #$aa
    sta tr_br
brow:
    lda tr_lm
    eor #$ff
    and (ptr),y
    ora tr_bl
    sta (ptr),y
    iny
    lda tr_rm
    beq :+
    eor #$ff
    and (ptr),y
    ora tr_br
    sta (ptr),y
:   iny
    iny
    dec tr_n
    bne brow
    rts
.endproc

.segment "RODATA"
fx_squares:   .byte FX_SQUARES
trail_dither: .byte TRAIL_DITHER
trail_x_b0:   .byte TRAIL_X_B0
trail_x_lm:   .byte TRAIL_X_LM
trail_x_rm:   .byte TRAIL_X_RM
trail_y_base: .byte TRAIL_Y_BASE
trail_y_rows: .byte TRAIL_Y_ROWS
trail_y_r0:   .byte TRAIL_Y_R0
trail_age:    .byte TRAIL_AGE
comet_y:      .byte 1 + 16, (21 - COMET_S) / 2 + 16, 21 - COMET_S - 1 + 16 ; riga della testa per vy
comet_side:   .byte 4, 4, 4, 3, 3, 3, 2, 2, 1, 1   ; cometa: lato per età (0 - 2 * TRAIL_N - 1)
comet_from:   .byte $FF, $7F, $3F, $1F, $0F, $07, $03, $01
comet_to:     .byte $80, $C0, $E0, $F0, $F8, $FC, $FE, $FF
tr_keyof:     .repeat TRAIL_BUFS, b ; prima riga della firma di ogni sprite della cache
              .byte b * TRAIL_KEY
              .endrepeat
.segment "BSS"
tr_x:    .res TRAIL_N + 1       ; posizioni della palla sullo schermo, la più recente prima
tr_xh:   .res TRAIL_N + 1
tr_y:    .res TRAIL_N + 1
tr_qxk:  .res TRAIL_N + 1       ; firma della coda di adesso, di seguito: le posizioni nello
tr_qyk:  .res TRAIL_N + 1       ; sprite della coda + 16 ($FF: fuori) e il lato della palla
tr_s:    .res 1
tr_keys: .res TRAIL_BUFS * TRAIL_KEY   ; firme degli sprite della cache
tr_valid: .res TRAIL_BUFS       ; sprite della cache con una forma (0: da disegnare)
tr_old:  .res TRAIL_BUFS        ; frame da quando uno sprite della cache non serve
tr_shown: .res 1                ; sprite della cache che si vede
tr_dbuf: .res 1                 ; sprite della cache in disegno
tr_b:    .res 1                 ; sprite della cache in confronto
tr_lay:  .res 1                 ; firma calcolata dopo l'ultimo trail_push
tr_prev_ok: .res 1              ; firma del frame prima ancora buona
tr_sp:   .res 1                 ; lato della palla della firma di prima
tr_bx:   .res 1                 ; movimento della palla dal frame prima, al contrario
tr_by:   .res 1
tr_want: .res 1                 ; coda chiesta in questo frame
tr_cm:   .res 1                 ; 1: la coda chiesta è la cometa del SUPER
tr_shcm: .res 1                 ; 1: lo sprite della coda che si vede è una cometa
tr_shdir: .res 1                ; angolo della palla nello sprite della coda che si vede (trail_dir)
tr_dir:  .res 1                 ; angolo della firma di adesso (trail_layout)
tr_ready: .res 1                ; coda già preparata in questa partita
tr_buf:  .res 1                 ; sprite della coda che si vede (0 - TRAIL_BUFS-1)
tr_ax:   .res 1                 ; palla nello sprite della coda, pixel dello schermo dall'angolo
tr_ay:   .res 1
tr_axo:  .res 1                 ; le stesse + 16
tr_ayo:  .res 1
tr_so:   .res 1                 ; tabelle della palla di questo lato (0 o TRAIL_SPAN)
tr_k:    .res 1
tr_age:  .res 1
tr_qx:   .res 1                 ; quadrato in disegno
tr_qy:   .res 1
tr_t:    .res 2
tr_n:    .res 1
tr_r0:   .res 1
tr_b0:   .res 1
tr_lm:   .res 1
tr_rm:   .res 1
tr_bl:   .res 1
tr_br:   .res 1
.segment "ZEROPAGE"
fx_sp:    .res 2                ; quadrato in lettura (FX_SQUARES)
.segment "NEXTBSS"
fx_pages: .res 1                ; immagini degli effetti già disegnate a $E000
fx_x:     .res 1                ; quadrato in disegno
fx_y:     .res 1
fx_n:     .res 1
fx_i:     .res 1
fx_j:     .res 1
fx_wait:  .res 1                ; frame prima di cominciare a copiarle
late_lines: .res 1              ; frame_after: righe concesse
fx_size:  .res 1
.segment "CODE"

; NEXT: immagini delle racchette preparate a inizio partita (una per frame, durante il conto alla
; rovescia) nella bitmap dell'attract, dopo gli effetti della palla: TWIST le 7 inclinazioni, il
; BLASTER una per colpi nel caricatore (0 - P_BLASTER_SHOTS), gli altri tipi un'immagine. In
; partita si cambia solo il puntatore, nel frame stesso; un'altezza diversa (rara) resta con
; l'immagine rifatta, che aspetta un frame con il tempo per farla.
SP_PREP0 = SP_RING0 + FX_SPRITES   ; 7 immagini per lato

.proc pad_prep
    lda pp_side
    cmp #2
    bcs done
    jsr frame_late
    bcs done
    lda pp_side                 ; frame_late cambia A
    tax
    asl a
    asl a
    tay
    lda nx_kind,y
    sta pi_kind
    tay
    lda prep_count,y
    cmp pp_var
    beq side_done
    bcc side_done
    ; variante pp_var del lato pp_side
    stx pi_side
    lda pd_cur_n,x
    sta pi_n
    lda pp_var
    sta pi_var
    lda pi_kind
    cmp #K_BLASTER
    bne :+
    lda pp_var                  ; BLASTER: variante = colpi nel caricatore
    jsr mag_setup
:   lda #<SP_PREP0
    ldy pi_side
    beq :+
    lda #<(SP_PREP0 + 7)
:   clc
    adc pp_var
    sta pp_dst                  ; puntatore della variante (pad_image usa m_t: TITAN, TWIST)
    jsr pad_image
    ; da sh_img alla bitmap: indirizzo $C000 + puntatore * 64
    lda pp_dst
    lsr a
    lsr a
    clc
    adc #>$C000
    sta ptr+1
    lda pp_dst
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    sta ptr
    ldx pi_side
    ldy img_base,x
    sty m_lo
    ldy #IMG_BYTES - 1
:   tya
    clc
    adc m_lo
    tax
    lda sh_img,x
    sta (ptr),y
    dey
    bpl :-
    ldx pi_side
    lda #$ff                    ; l'immagine dinamica, se servirà, si rifà
    sta pd_n,x
    inc pp_var
done:
    rts
side_done:
    lda pd_cur_n,x
    sta pp_n,x
    lda #1
    sta pp_ready,x
    inc pp_side
    lda #0
    sta pp_var
    rts
.endproc

; immagini da preparare per tipo (ARCADE, TITAN, HAMMER, TWIST, BLASTER, RUSH, GUARDIAN, nessuno)
prep_count: .byte 1, 1, 1, 7, P_BLASTER_SHOTS + 1, 1, 1, 1
.assert P_BLASTER_SHOTS + 1 <= 7, error, "immagini del BLASTER: al massimo 7 per lato"

.segment "NEXTBSS"
pp_side:  .res 1                ; lato in preparazione (2: finito)
pp_var:   .res 1
pp_ready: .res 2                ; immagini pronte per il lato
pp_n:     .res 2                ; righe con cui sono state fatte
pp_dst:   .res 1                ; sprite in preparazione
.segment "CODE"

; C = 1 se il frame è già avanti: dall'interrupt della riga 250 sono passate più righe (circa 58
; cicli utili ciascuna) di quelle che lasciano il tempo al lavoro rimandabile e a quello che resta
; del frame (riserve, SID). Immagini delle racchette e scritte in partita (frame_late, fino a
; 8.000 cicli) e posti delle riserve (frame_late_small, fino a 12.000) aspettano allora il frame
; dopo.
LATE_BIG   = 8000 / 58
LATE_SMALL = 12000 / 58
LATE_SPIN  = 5000 / 58          ; un'immagine della rotazione del SUPER costa fino a circa 10.400

.proc frame_late
    lda #LATE_BIG
    bne frame_after
.endproc
.proc frame_late_small
    lda #LATE_SMALL
.endproc
; C = 1 se sono passate almeno A righe dall'interrupt. Un frame oltre il suo tempo trova il raster
; di nuovo alle righe 250-311, come appena dopo l'interrupt: lo distingue frame_flag, che
; l'interrupt della riga 250 ha rialzato (play_main lo azzera prima del frame), e allora è tardi,
; così un frame già sforato non accetta altro lavoro; sid_time fa lo stesso. (Il banco di prova
; non esegue l'interrupt: lì un frame così lo segnala come oltre il budget.)
.proc frame_after
    sta late_lines
    lda $d011
    bmi early                   ; righe 256-311: appena dopo l'interrupt
    lda $d012
    cmp #RASTER_LINE
    bcs early                   ; righe 250-255
    clc
    adc #312 - RASTER_LINE      ; righe 0-249: passate riga + 62
    bcs late
    cmp late_lines
    rts
early:
    lda frame_flag              ; di nuovo l'interrupt: il raster ha fatto il giro, tardi
    bne late
    clc
    rts
late:
    sec
    rts
.endproc

; NEXT: racchetta che ruota con il SUPER armato (animazione 0), come sul MiSTer. Otto angoli su
; mezzo giro (l'altro mezzo è uguale), per lato con l'altezza del suo tipo, preparati a inizio
; partita dopo le altre immagini: sprite hires espansi (pixel 2x2, griglia 24x21) con il centro
; della racchetta nel pixel doppio (12, 10). La racchetta è un segmento spesso 2 pixel doppi
; (4 pixel) disegnato a mezzi passi in virgola fissa 8.8.
SP_SPIN0 = SP_PREP0 + 14        ; 8 immagini per lato
SPIN_CX  = 12
SPIN_CY  = 10

.proc spin_prep
    lda sp_k
    cmp #16
    jcs done
    lda #LATE_SPIN              ; frame già avanti (anche per un'immagine di racchetta): al prossimo
    jsr frame_after
    jcs done
    ; destinazione: $C000 + (SP_SPIN0 + k) * 64
    lda sp_k
    clc
    adc #SP_SPIN0
    sta m_t
    lsr a
    lsr a
    clc
    adc #>$C000
    sta ptr+1
    lda m_t
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    sta ptr
    ldy #62
    lda #0
:   sta (ptr),y
    dey
    bpl :-
    ; mezza lunghezza in pixel doppi: altezza della racchetta / 4
    lda sp_k
    and #8
    lsr a                       ; lato * 4
    tax
    lda pad_h+2,x
    lsr a
    lsr a
    sta sp_l
    ; direzione della lunghezza (sin, cos dell'angolo, * 64): mezzo passo = direzione * 2 (8.8)
    lda sp_k
    and #7
    tax
    lda spin_sin,x
    jsr sext2
    sta sp_dx
    sty sp_dx+1
    lda spin_cos,x
    jsr sext2
    sta sp_dy
    sty sp_dy+1
    lda spin_px,x
    sta sp_px
    lda spin_py,x
    sta sp_py
    ; partenza: centro - mezza lunghezza * direzione = centro - 2 * l mezzi passi
    lda #<(SPIN_CX * 256 + 128)
    sta sp_x
    lda #>(SPIN_CX * 256 + 128)
    sta sp_x+1
    lda #<(SPIN_CY * 256 + 128)
    sta sp_y
    lda #>(SPIN_CY * 256 + 128)
    sta sp_y+1
    lda sp_l
    asl a
    sta sp_n
    beq draw
:   lda sp_x
    sec
    sbc sp_dx
    sta sp_x
    lda sp_x+1
    sbc sp_dx+1
    sta sp_x+1
    lda sp_y
    sec
    sbc sp_dy
    sta sp_y
    lda sp_y+1
    sbc sp_dy+1
    sta sp_y+1
    dec sp_n
    bne :-
draw:
    ; 4 * l + 1 mezzi passi, due pixel per passo (lo spessore)
    lda sp_l
    asl a
    asl a
    sta sp_n
    inc sp_n
step:
    ldx sp_x+1
    ldy sp_y+1
    jsr spin_plot
    lda sp_x+1
    clc
    adc sp_px
    tax
    lda sp_y+1
    clc
    adc sp_py
    tay
    jsr spin_plot
    lda sp_x
    clc
    adc sp_dx
    sta sp_x
    lda sp_x+1
    adc sp_dx+1
    sta sp_x+1
    lda sp_y
    clc
    adc sp_dy
    sta sp_y
    lda sp_y+1
    adc sp_dy+1
    sta sp_y+1
    dec sp_n
    bne step
    inc sp_k
done:
    rts
.endproc

; A (con segno) * 2 in A (basso) e Y (alto).
.proc sext2
    ldy #0
    cmp #$80
    bcc :+
    ldy #$ff
:   asl a
    pha
    tya
    rol a
    tay
    pla
    rts
.endproc

; Pixel doppio (X, Y) dell'immagine in (ptr), se è nella griglia 24x21.
.proc spin_plot
    cpx #24
    bcs out
    cpy #21
    bcs out
    txa
    lsr a
    lsr a
    lsr a
    clc
    adc row3,y
    sty m_lo
    tay
    txa
    and #7
    tax
    lda bit_hi,x
    ora (ptr),y
    sta (ptr),y
out:
    rts
.endproc

row3:   .byte 0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 39, 42, 45, 48, 51, 54, 57, 60
bit_hi: .byte $80, $40, $20, $10, $08, $04, $02, $01
; angolo k * 22,5 gradi: direzione della lunghezza (sin, cos) * 64 e un passo di spessore
spin_sin: .byte 0, 24, 45, 59, 64, 59, 45, 24
spin_cos: .byte 64, 59, 45, 24, 0, <-24, <-45, <-59
spin_px:  .byte 1, 1, 1, 0, 0, 0, 1, 1
spin_py:  .byte 0, 0, $ff, 1, 1, 1, 1, 0

.segment "NEXTBSS"
sp_k:  .res 1                   ; immagine in preparazione (16: finito)
.segment "BSS"
sp_l:  .res 1
sp_n:  .res 1
sp_x:  .res 2
sp_y:  .res 2
sp_dx: .res 2
sp_dy: .res 2
sp_px: .res 1
sp_py: .res 1
.segment "CODE"

; NEXT: salto del TELEPORT, come next_ui.rs e il MiSTer. Con la palla in arrivo la racchetta
; affonda nel primo portale (una linea gialla larga 18 pixel) mentre la palla va da metà campo a
; 32 pixel più in là, poi esce dal secondo, sul punto d'arrivo, mentre la palla va da 96 a 64
; pixel dal bordo del giocatore; il secondo portale si apre a metà dell'affondo. Il pezzo che
; affonda è nello sprite della racchetta, quello che esce nello sprite dell'icona del bonus.
WARP_STEP = 32
WARP_SUNK = (P_WIDTH >> 16) / 2
WARP_RISE = 3 * WARP_STEP
SP_WARP   = SP_SPIN0 + 16       ; immagine del pezzo che esce
; Il salto si disegna dopo la scena, quando il frame è già oltre gli 8.000 cicli di frame_late (in
; NEXT a circa 10.000-12.500: con frame_late non si disegnava mai). Le due immagini costano circa
; WARP_COST cicli e si fanno se il frame resta sotto circa 16.000; se no resta l'immagine di prima.
WARP_COST = 3000
WARP_LATE = (16000 - WARP_COST) / 58

.proc warp_fx
    ; inizio: evento del TELEPORT (salta chi riceve la palla)
    lda wp_on
    bne running
    lda events
    and #EV_TELEPORT
    jeq remember
    ldx #0
    lda ball_vx+3
    bmi :+
    inx
:   stx wp_side
    lda pd_last,x
    sta wp_from
    lda #1
    sta wp_on
    lda #0                      ; nessun pezzo finché non c'è un'immagine di questo salto
    sta wp_en
    sta wp_ex
running:
    ; fine: colpo, punto, o racchetta tutta fuori (palla a 64 pixel dal bordo)
    lda events
    and #EV_HIT | EV_BOOST | EV_SCORE
    bne stop
    jsr warp_d                  ; A = distanza della palla dal bordo di chi salta
    cmp #WARP_RISE - WARP_STEP + 1
    bcs :+
stop:
    lda #0
    sta wp_on
    ldx wp_side
    lda #$ff                    ; l'immagine della racchetta si rifà
    sta pd_n,x
    jmp remember
:   sta wp_d
    lda #WARP_LATE              ; frame già avanti: resta l'immagine di prima
    jsr frame_after
    jcs place
    ; avanzamento: pixel affondati e usciti (0-32)
    lda #WARP_SUNK
    jsr warp_part
    sta wp_sunk
    lda #WARP_RISE
    jsr warp_part
    sta wp_out
    ; altezza della racchetta e verso del salto
    lda wp_side
    asl a
    asl a
    tax
    lda pad_h+2,x
    sta wp_ph
    ldx wp_side
    lda pd_cy,x
    sta wp_to
    ; primo portale finché la racchetta non è affondata
    lda #0
    sta wp_en
    lda wp_sunk
    cmp #WARP_STEP
    jcs exit
    inc wp_en
    lda wp_sunk
    jsr warp_shift              ; A = altezza * affondo / 32
    sta m_t
    lda wp_to
    cmp wp_from
    bcc en_up
    ; giù: linea sotto, la racchetta scende dentro
    lda wp_ph
    lsr a
    sta m_lo
    lda wp_from
    clc
    adc m_lo
    sta wp_edge                 ; bordo basso
    lda wp_from
    sec
    sbc m_lo
    clc
    adc m_t
    sta wp_lo
    clc
    adc wp_ph
    cmp wp_edge
    bcc :+
    lda wp_edge
:   sta wp_hi
    jmp en_draw
en_up:
    lda wp_ph
    lsr a
    sta m_lo
    lda wp_from
    sec
    sbc m_lo
    sta wp_edge                 ; bordo alto
    sec
    sbc m_t
    sta wp_lo                   ; cima della racchetta che sale
    clc
    adc wp_ph
    sta wp_hi
    lda wp_lo
    cmp wp_edge
    bcs en_draw
    lda wp_edge
    sta wp_lo
en_draw:
    ldx wp_side
    ldy img_base,x
    jsr warp_image
    lda wp_top
    sta wp_en_top
    ldx wp_side
    lda #1
    sta pd_dirty,x
    lda #$ff
    sta pd_n,x
exit:
    ; secondo portale da metà affondo
    lda #0
    sta wp_ex
    lda wp_sunk
    cmp #WARP_STEP / 2
    bcc place
    inc wp_ex
    lda wp_out
    jsr warp_shift
    sta m_t                     ; altezza * uscita / 32
    lda wp_ph
    sec
    sbc m_t
    sta m_t                     ; ancora dentro
    lda wp_ph
    lsr a
    sta m_lo
    lda wp_to
    cmp wp_from
    bcc ex_up
    ; giù: linea sopra il punto d'arrivo, la racchetta esce in giù
    lda wp_to
    sec
    sbc m_lo
    sta wp_edge
    sec
    sbc m_t
    sta wp_lo
    clc
    adc wp_ph
    sta wp_hi
    lda wp_lo
    cmp wp_edge
    bcs ex_draw
    lda wp_edge
    sta wp_lo
    jmp ex_draw
ex_up:
    lda wp_to
    clc
    adc m_lo
    sta wp_edge
    lda wp_to
    sec
    sbc m_lo
    clc
    adc m_t
    sta wp_lo
    clc
    adc wp_ph
    cmp wp_edge
    bcc :+
    lda wp_edge
:   sta wp_hi
ex_draw:
    lda #<(SP_WARP * 64 + $C000)
    sta ptr
    lda #>(SP_WARP * 64 + $C000)
    sta ptr+1
    ldy #$ff                    ; nell'immagine di SP_WARP
    jsr warp_image
    lda wp_top
    sta wp_ex_top
place:
    ; sprite: il pezzo che affonda nella racchetta (immagine dinamica), quello che esce nell'icona
    ldy wp_side
    lda wp_en
    beq :+
    lda pad_slot,y
    sta sh_ptr+SPN_PAD,y
    lda wp_en_top
    clc
    adc #SPR_Y0
    sta sh_y+SPN_PAD,y
    lda #COL_WHITE
    sta sh_col+SPN_PAD,y
    jmp icon
:   lda bit_of+SPN_PAD,y        ; affondata: niente racchetta
    eor #$ff
    and sh_enable
    sta sh_enable
icon:
    lda wp_ex
    beq no_icon
    lda #SP_WARP
    sta sh_ptr+SPN_ICON,y
    lda #COL_WHITE
    sta sh_col+SPN_ICON,y
    lda wp_ex_top
    clc
    adc #SPR_Y0
    sta sh_y+SPN_ICON,y
    lda sh_x+SPN_PAD,y          ; stessa colonna della racchetta
    sta sh_x+SPN_ICON,y
    lda sh_msb
    and bit_of+SPN_PAD,y
    beq :+
    lda bit_of+SPN_ICON,y
    ora sh_msb
    sta sh_msb
:   lda bit_of+SPN_ICON,y
    ora sh_mc
    sta sh_mc
    lda bit_of+SPN_ICON,y
    ora sh_yexp
    sta sh_yexp
    lda bit_of+SPN_ICON,y
    ora sh_enable
    sta sh_enable
    jmp remember
no_icon:
    lda bit_of+SPN_ICON,y
    eor #$ff
    and sh_enable
    sta sh_enable
remember:
    ; righe del centro delle racchette, per il prossimo salto
    lda pd_cy
    sta pd_last
    lda pd_cy+1
    sta pd_last+1
    rts
.endproc

; A = distanza in pixel della palla dal bordo di chi salta (al massimo 255).
.proc warp_d
    lda ball_x+2
    ldx ball_x+3
    ldy wp_side
    beq left
    ; destra: 320 - x
    eor #$ff
    sec
    adc #<(P_WIDTH >> 16)
    tay
    txa
    eor #$ff
    adc #>(P_WIDTH >> 16)
    tax
    tya
left:
    cpx #0
    beq :+
    lda #$ff
:   rts
.endproc

; A = clamp(A - wp_d, 0, WARP_STEP): quanto è avanzata una fase che comincia con la palla a A pixel.
.proc warp_part
    sec
    sbc wp_d
    bcs :+
    lda #0
:   cmp #WARP_STEP
    bcc :+
    lda #WARP_STEP
:   rts
.endproc

; A = altezza della racchetta * A / 32.
.proc warp_shift
    ldy wp_ph
    jsr umul8                   ; m_t:A = altezza * A
    lsr m_t
    ror a
    lsr m_t
    ror a
    lsr m_t
    ror a
    lsr m_t
    ror a
    lsr m_t
    ror a
    rts
.endproc

; Immagine di un pezzo del salto: righe wp_lo..wp_hi - 1 di racchetta (bianca) e il portale
; (giallo, righe wp_edge - 1 e wp_edge, largo 20 pixel) dalla riga wp_top = min(wp_lo, wp_edge - 1).
; Y = inizio in sh_img, oppure $ff per l'immagine in (ptr). Ogni riga dello sprite copre due righe
; dello schermo (y = wp_top + 2 * i): l'immagine si svuota e si riempiono solo le righe del corpo
; (y in [wp_lo - 1, wp_hi)) e del portale (y in [wp_edge - 2, wp_edge]).
.proc warp_image
    cpy #$ff
    beq :+
    tya                         ; (ptr) = sh_img + Y
    clc
    adc #<sh_img
    sta ptr
    lda #>sh_img
    adc #0
    sta ptr+1
:   ldx wp_edge
    dex
    txa
    cmp wp_lo
    bcc :+
    lda wp_lo
:   sta wp_top
    lda #0
    ldy #IMG_BYTES - 1
clear:
    sta (ptr),y
    dey
    sta (ptr),y
    dey
    sta (ptr),y
    dey
    bpl clear
    ; corpo: righe da (lo - top) / 2 a (hi - top + 1) / 2 escluso, colonne doppie 4 e 5
    lda wp_hi
    sec
    sbc wp_lo
    bcc portal                  ; (con hi = lo c'è ancora la riga lo - 1)
    lda wp_hi
    sec
    sbc wp_top
    adc #0                      ; C = 1: + 1
    lsr a
    cmp #PAD_ROWS
    bcc :+
    lda #PAD_ROWS
:   sta m_lo
    asl a
    adc m_lo
    sta wp_y                    ; fine * 3
    lda wp_lo
    sec
    sbc wp_top
    lsr a
    sta m_lo
    asl a
    adc m_lo                    ; inizio * 3
    cmp wp_y
    bcs portal
    tay
    iny
    inc wp_y
    lda #$A0
body:
    sta (ptr),y
    iny
    iny
    iny
    cpy wp_y
    bcc body
portal:
    ; portale: righe da (edge - top - 1) / 2 a (edge - top) / 2, colonne doppie 0-9
    lda wp_edge
    sec
    sbc wp_top
    tax
    lsr a
    sta wp_y                    ; ultima riga
    dex
    txa
    lsr a
prow:
    cmp #PAD_ROWS
    bcs done
    sta m_lo
    asl a
    adc m_lo
    tay
    lda #$FF
    sta (ptr),y
    iny
    sta (ptr),y
    iny
    lda #$F0
    sta (ptr),y
    lda m_lo
    cmp wp_y
    bcs done
    adc #1
    bcc prow
done:
    rts
.endproc

pad_slot: .byte SP_PAD0, SP_PAD1

.segment "BSS"
wp_on:     .res 1
wp_side:   .res 1
wp_from:   .res 1               ; riga del centro della racchetta prima del salto
wp_to:     .res 1
wp_d:      .res 1
wp_sunk:   .res 1
wp_out:    .res 1
wp_ph:     .res 1
wp_en:     .res 1
wp_ex:     .res 1
.segment "ZEROPAGE"
wp_edge:   .res 1
.segment "BSS"
.segment "ZEROPAGE"
wp_lo:     .res 1
.segment "BSS"
wp_hi:     .res 1
wp_top:    .res 1
wp_y:      .res 1
wp_en_top: .res 1
wp_ex_top: .res 1
pd_cy:     .res 2               ; riga del centro delle racchette in questo frame
pd_last:   .res 2               ; e al frame prima
.segment "CODE"
