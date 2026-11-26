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
COL_DGREEN = 5                  ; verde: colore dedicato del BLASTER
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
PAD_BLINK  = 4                  ; racchetta grigia a tratti con un bonus armato (ogni 4 tick)
; colori dello sprite multicolore della racchetta: %01 grigio condiviso, %10 colore dedicato del
; personaggio ($D027+i, indipendente per P1 e P2), %11 bianco condiviso ($D026, scafo)
COLOR_NONE   = 0
COLOR_GRAY   = 1                ; %01: $D025
COLOR_YELLOW = 2                ; %10: colore dedicato del tipo ($D027+i)
COLOR_WHITE  = 3                ; %11: $D026, bianco dello scafo

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
big2_src:     .byte BIG2_SRC        ; carattere del font di ogni lettera 2x (big_build)
big_game_over: .byte BIG_GAME_OVER
big_p1_wins:  .byte BIG_P1_WINS
big_p2_wins:  .byte BIG_P2_WINS
big_you_win:  .byte BIG_YOU_WIN
big_cpu_wins: .byte BIG_CPU_WINS
row_lo:
    .repeat 25, i
    .byte <(SCREEN + 40 * i)
    .endrepeat
row_hi:
    .repeat 25, i
    .byte >(SCREEN + 40 * i)
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
pd_r0:     .res 1               ; righe della racchetta (pad_sprite)
pd_r1:     .res 1
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
pi_out:    .res 1
.segment "ZEROPAGE"
pi_half:   .res 1
.segment "BSS"
pi_ammo:   .res 1               ; BLASTER: livello del caricatore (0 - BLASTER_VIS)
pi_full:   .res 1               ; BLASTER: prima riga con il colore del tipo acceso
.segment "ZEROPAGE"
pi_row:    .res 3
.segment "BSS"
pi_tsign:  .res 1               ; TWIST: inclinazione con il segno, |t| e (k - n/2) * |t|
pi_tabs:   .res 1
pi_acc:    .res 1
pd_made:   .res 1               ; immagine di racchetta già rifatta in questo frame
pd_dirty:  .res 2               ; immagine da copiare nella RAM degli sprite
pd_full:   .res 2               ; GUARDIAN con dei settori persi: sprite del muro intero (0 nessuno)

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
    ; multicolore degli sprite delle racchette: %01 grigio, %11 bianco (scafo condiviso);
    ; %10 è il colore individuale dello sprite ($D027+i), dedicato a ciascuna astronave
    lda #COL_GRAY
    sta $d025
    lda #COL_WHITE
    sta $d026
    lda #0
    sta $d01b                   ; sprite davanti ai caratteri
    lda #0
    sta sh_enable
    sta sh_mode
    jsr game_sprites
    jsr clear_screen
    ; le lettere 2x dal font, che title_unpack ha già preso dalla ROM dei caratteri
    ldy #0
    ldx #BIG2_N
    jmp big2_build
.endproc
.segment "CODE"

; ------------------------------------------------------------------------------------ font

; Il font del programma è quello della ROM dei caratteri della macchina, che nessun file contiene:
; nel set di caratteri (gen/charset.bin, tools/gen_c64_assets.py) al posto dei glifi ci sono dei
; segnaposto vuoti. font_from_rom ci copia i glifi 1x dalla ROM, big_build fa da questi le lettere
; 2x (BIG2_FIRST, quattro caratteri per lettera); le metà delle lettere della scelta dei bonus
; vengono anch'esse dai glifi 1x (pick_chars). Lo fanno l'avvio (video_init) e il finale, che ha il
; suo set e alla fine ricarica dalla cartuccia quello del programma; la scelta dei bonus rifà le
; lettere 2x, che nelle sue pagine prendono le metà delle lettere.

; I glifi del font (da FONT_FIRST) dalla ROM dei caratteri (set maiuscolo a $D000): interrupt
; spenti e $01 = $31, cioè la ROM dei caratteri a $D000 (le scritture lì vanno nella RAM sotto) e
; la RAM al posto di BASIC e KERNAL, senza l'I/O (la cartuccia è spenta). Mai durante una voce:
; un NMI troverebbe spento l'I/O. Circa 8.000 cicli. È una macro: una copia in INIT
; (font_from_rom, da title_unpack), una nel finale (ending.s), ognuna con la sua tabella FONT_ROM.
.macro font_rom_code
    lda #<(CHARSET + 8 * FONT_FIRST)
    sta ptr
    lda #>(CHARSET + 8 * FONT_FIRST)
    sta ptr+1
    php
    sei
    lda #$31
    sta $01
    ldx #0
char:
    lda #>$D000 >> 3            ; ptr2 = $D000 + codice * 8
    sta ptr2+1
    lda rom,x
    asl a
    rol ptr2+1
    asl a
    rol ptr2+1
    asl a
    rol ptr2+1
    sta ptr2
    ldy #7
:   lda (ptr2),y
    sta (ptr),y
    dey
    bpl :-
    lda ptr
    clc
    adc #8
    sta ptr
    bcc :+
    inc ptr+1
:   inx
    cpx #FONT_CHARS
    bne char
    lda #$35
    sta $01
    plp
    rts
rom: .byte FONT_ROM             ; codice della ROM di ogni carattere del font
.endmacro
.segment "INIT"
.proc font_from_rom
    font_rom_code
.endproc
.segment "CODE"
.assert >$D000 >> 3 << 3 = >$D000, error, "font_from_rom: indirizzo della ROM"

; Lettere 2x del programma: X lettere dalla Y-esima (big2_src), nei loro caratteri da BIG2_FIRST.
.proc big2_build
    tya
    asl a
    asl a                       ; lettera * 4 caratteri * 8 byte
    sta ptr
    lda #0
    asl ptr
    rol a
    asl ptr
    rol a
    asl ptr
    rol a
    adc #>(CHARSET + 8 * BIG2_FIRST)
    sta ptr+1
    lda ptr
    clc
    adc #<(CHARSET + 8 * BIG2_FIRST)
    sta ptr
    bcc :+
    inc ptr+1
:   lda #<big2_src
    sta big_tab+1
    lda #>big2_src
    sta big_tab+2
.endproc
; (prosegue)
; X lettere 2x dalla Y-esima della tabella dei caratteri del font a big_tab+1 (la scrive il
; chiamante), da (ptr) in avanti, 32 byte per lettera: i caratteri in alto a sinistra, in alto a
; destra, in basso a sinistra e in basso a destra, ogni pixel del glifo 1x (già nel set) 2x2.
; Circa 670 cicli per lettera.
.proc big_build
    stx v_n
letter:
    sty v_col
tab:
    lda $ffff,y                 ; carattere del font: ptr2 al suo glifo
    ldx #>(CHARSET / 8)
    stx ptr2+1
    asl a
    rol ptr2+1
    asl a
    rol ptr2+1
    asl a
    rol ptr2+1
    sta ptr2
    ldx #7
row:
    txa
    tay
    lda (ptr2),y
    sta m_t
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    lda bb_dbl,y                ; metà sinistra: due righe uguali
    ldy bb_off,x
    sta (ptr),y
    iny
    sta (ptr),y
    lda m_t
    and #$0f
    tay
    lda bb_dbl,y                ; metà destra, nel carattere accanto
    ldy bb_off8,x
    sta (ptr),y
    iny
    sta (ptr),y
    dex
    bpl row
    lda ptr
    clc
    adc #32
    sta ptr
    bcc :+
    inc ptr+1
:   ldy v_col
    iny
    dec v_n
    bne letter
    rts
.endproc
big_tab = big_build::tab
.assert <(CHARSET / 8) = 0, error, "big_build: indirizzo del set"
; quattro pixel doppi; riga del glifo -> byte della lettera 2x (alto sinistra o basso sinistra)
bb_dbl:
    .repeat 16, n
    .byte (n & 8) * $18 + (n & 4) * $0c + (n & 2) * $06 + (n & 1) * $03
    .endrepeat
bb_off:  .byte 0, 2, 4, 6, 16, 18, 20, 22
bb_off8: .byte 8, 10, 12, 14, 24, 26, 28, 30

; Caratteri della scelta dei bonus (C = 0): da PICK_FIRST le metà alte delle lettere del font
; abbassate di 4 pixel, da PICK_FIRST + FONT_CHARS le metà basse in cima al carattere (put_low,
; pick.s), dai glifi 1x del set; circa 9.500 cicli. Con C = 1 di nuovo le lettere 2x, che stanno
; nelle stesse pagine: la prima metà (A = 0) o la seconda (A = 1), circa 8.000 cicli ciascuna.
PICK_TOP   = PICK_FIRST - FONT_FIRST    ; codice del font + PICK_TOP: metà alta, abbassata
PICK_BOTTOM = PICK_TOP + FONT_CHARS     ; codice del font + PICK_BOTTOM: metà bassa, in alto
.assert PICK_BOTTOM + FONT_FIRST + FONT_CHARS <= PICK_FIRST + PICK_PAGES * 32, error, "metà delle lettere oltre le pagine della scelta"
.assert BIG2_FIRST = PICK_FIRST .and 4 * BIG2_N <= PICK_PAGES * 32, error, "lettere 2x fuori dalle pagine della scelta"
PK_FONT = CHARSET + 8 * FONT_FIRST
PK_TOP  = CHARSET + 8 * PICK_FIRST
PK_BOT  = PK_TOP + 8 * FONT_CHARS
PK_HALF = FONT_CHARS / 2 * 8            ; byte per passata (i caratteri in due passate)
.assert PK_HALF <= 256, error, "pick_chars: passata oltre 256 byte"
PK_REST = 8 * (PICK_FIRST + 2 * FONT_CHARS - BIG2_FIRST - 4 * BIG2_N)    ; dopo le lettere 2x
PK_REST0 = CHARSET + 8 * (BIG2_FIRST + 4 * BIG2_N)
.assert PK_REST > 256 .and PK_REST <= 512, error, "pick_chars: caratteri dopo le lettere 2x"
.proc pick_chars
.ifdef ROTATED
    pha                         ; (campo girato: anche i caratteri 1-3 di oggi; A e C restano)
    jsr today_glyphs
    pla
.endif
    bcc halves
    ldy #0
    ldx #BIG2_N / 2
    cmp #0
    beq :+
    ; (con la seconda metà di nuovo vuoti i caratteri dopo le lettere 2x, che non si usano: due
    ; tratti di 256 byte, il secondo dalla fine, che si sovrappongono)
    tya
rest:
    sta PK_REST0,y
    sta PK_REST0 + PK_REST - 256,y
    iny
    bne rest
    ldy #BIG2_N / 2
    ldx #BIG2_N - BIG2_N / 2
:   jmp big2_build
halves:
    .repeat 2, h
    .scope
    ldy #PK_HALF - 1
byte:
    tya
    and #4
    beq low
    lda PK_FONT + h * PK_HALF - 4,y     ; righe 4-7 della metà alta: righe 0-3 del glifo
    sta PK_TOP + h * PK_HALF,y
    lda #0
    sta PK_BOT + h * PK_HALF,y
    beq next
low:
    lda PK_FONT + h * PK_HALF + 4,y     ; righe 0-3 della metà bassa: righe 4-7 del glifo
    sta PK_BOT + h * PK_HALF,y
    lda #0
    sta PK_TOP + h * PK_HALF,y
next:
    dey
    cpy #$ff
    bne byte
    .endscope
    .endrepeat
    ; il resto (con un numero dispari di caratteri l'ultimo)
    .if ::FONT_CHARS .mod 2
    ldy #3
:   lda PK_FONT + 2 * PK_HALF,y
    sta PK_TOP + 2 * PK_HALF + 4,y
    lda PK_FONT + 2 * PK_HALF + 4,y
    sta PK_BOT + 2 * PK_HALF,y
    lda #0
    sta PK_TOP + 2 * PK_HALF,y
    sta PK_BOT + 2 * PK_HALF + 4,y
    dey
    bpl :-
    .endif
    rts
.endproc

; Sprite della partita: palla hires bianca, bande grigie hires, racchette multicolore espanse in
; verticale.
.ifndef ROTATED                 ; (campo girato: rot_video.s)
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
    rts                         ; (A = 0: compute_sprites)
.endproc
.assert MODE_TEXT = 0, error, "game_sprites: A = 0 all'uscita"
.assert (HALF_PX - 1) & $FFFF00FF = $FF, error, "compute_sprites: HALF_PX - 1 con il byte 0 a $FF e i byte 2-3 a 0"

.endif
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

; Schermo di testo vuoto e caratteri del colore A (prosegue in clear_screen). Le due metà costano
; circa 6.400 cicli ciascuna: clear_screen e clear_colors da sole in due frame dove non ci stanno
; insieme (ch_phases).
.proc clear_text
    jsr clear_colors
.endproc

; Schermo di testo vuoto. Non tocca C.
.proc clear_screen
    ldx #0
    lda #CH_BLANK
:   sta SCREEN,x
    sta SCREEN+$100,x
    sta SCREEN+$200,x
    sta SCREEN+$2e8,x
    inx
.ifdef ROTATED                  ; (campo girato: due celle a giro, 640 cicli in meno; il frame della
    sta SCREEN,x                ; scelta che pulisce schermo e colori sull'NTSC non ci stava)
    sta SCREEN+$100,x
    sta SCREEN+$200,x
    sta SCREEN+$2e8,x
    inx
.endif
    bne :-
    rts
.endproc

; Caratteri dello schermo di testo del colore A.
.proc clear_colors
    ldx #0
:   sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $dae8,x
    inx
.ifdef ROTATED                  ; (campo girato: come clear_screen)
    sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $dae8,x
    inx
.endif
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

; Stringa ASCII terminata da 0 in (ptr2), dalla colonna X alla riga Y; con il bit 6 di v_big
; nella bitmap a $E000 (i glifi del set copiati nelle celle) invece che nello schermo di testo.
; Poi X = colonna dopo l'ultima, Y = lunghezza.
.proc print_str
    sty v_row
    stx p_col
    bit v_big
    bvs bitmap
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    ldy #0
next:
    lda (ptr2),y
    beq done
    sty v_n
    tay
    lda font_map - 32,y
    ldy p_col
    sta (ptr),y
    inc p_col
    ldy v_n
    iny
    bne next
done:
    ldx p_col
    rts
bitmap:
    ldy #0
:   lda (ptr2),y
    beq done
    sty v_n
    tay
    lda font_map - 32,y
    jsr text_cell
    ldy v_n
    iny
    bne :-
.endproc

; Il glifo del carattere A del set nella cella della bitmap alla colonna p_col, riga v_row, poi
; p_col + 1.
.proc text_cell
    pha
    ldy v_row
    lda cell_row_lo,y
    sta ptr
    lda cell_row_hi,y
    sta ptr+1
    lda p_col
    asl a
    asl a
    asl a                       ; colonna * 8 (il bit 8 nel riporto)
    bcc :+
    inc ptr+1
    clc
:   adc ptr
    sta ptr
    bcc :+
    inc ptr+1
:   pla
    ldx #>(CHARSET / 8)         ; il glifo: CHARSET + carattere * 8
    stx glyph+2
    asl a
    rol glyph+2
    asl a
    rol glyph+2
    asl a
    rol glyph+2
    sta glyph+1
    ldy #7
glyph:
    lda $ffff,y
    sta (ptr),y
    dey
    bpl glyph
    inc p_col
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
.ifndef ROTATED                 ; (campo girato: rot_video.s)
.proc draw_field
    jsr bullet_chars
    jsr net_setup               ; la rete della partita
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

.endif
; Il set di caratteri è pieno: in NEXT la capsula del BULLET della riserva (8 caratteri, normale e
; in negativo) prende il posto di caratteri che in NEXT non servono, cioè cursore e reticolo
; dell'auto-test (solo all'accensione) e tre caratteri vuoti suoi; non CH_GRID_T né il muro del
; singolo, che le scritte animate e la CHALLENGE usano anche in NEXT e dopo. Restano così anche
; nelle altre partite (gli originali, bullet_orig e bar_orig, ci sono ancora:
; tools/gen_c64_assets.py, BULLET_C0-7), come quelli della barra delle mosse speciali (sm_init).
.proc bullet_chars
    ldx m_next
    bne :+
    rts
:   lda #<bullet_tiles
    sta ptr2
    lda #>bullet_tiles
    sta ptr2+1
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
hibss_free:   .res 4            ; liberi dopo la rimozione dell'easter egg RED (tieniamo VOICE_VOL fisso)
egg_buf:      .res 3            ; il comando di SID_SONG_EGG dalla cartuccia (egg_stage, sid.s, jukebox)
; VOLUME del menu: qui, a un indirizzo fisso, perché lo legge anche il player delle voci (voice.s)
opt_volume:   .res 1            ; passo, da 0 (0%) a VOLUME_STEPS - 1 (100%)
sid_vol:      .res 1            ; il suo volume del SID, 0-15 (vol_levels, sid.s)
.assert sid_vol = VOICE_VOL, error, "VOICE_VOL fuori posto"
; scritte (print_str, sotto): non si azzerano all'avvio, ma la pagina $FF00 della cartuccia qui ha 0
v_big:        .res 1            ; bit 6 nella bitmap (di solito 0)
p_col:        .res 1            ; colonna
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

.ifndef ROTATED                 ; (campo girato: rot_video.s)
; Mezzeria nella riga v_row.
.proc center_line_row
    ldy v_row
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    tya                         ; righe vuote della rete dell'avversario (net_skip)
    and #3
    tay
    lda bit_of,y
    and net_skip
    beq on
    lda #CH_BLANK
    ldy #19
    sta (ptr),y
    iny
    sta (ptr),y
    rts
on:
    ldy #19
    lda #CH_LINE_L
    sta (ptr),y
    iny
    lda #CH_LINE_R
    sta (ptr),y
    rts
.endproc

; Reti degli avversari nella CHALLENGE contro la CPU, come draw_net di rust/game/src/scenes.rs (e
; net_px del MiSTer), con i due caratteri della mezzeria (8 pixel di altezza, a cavallo tra le
; colonne 19 e 20) ridefiniti da net_setup per la partita; per i motivi lunghi 16 o 32 righe alcune
; righe di caratteri restano vuote (net_skip). ARCADE quadratini, HAMMER rete doppia, TITAN
; trattini lunghi, BLASTER due file di puntini, GUARDIAN mattoni (non sfalsati), TWIST trattini
; inclinati che si piegano tutti insieme verso la palla quando passa, HAMMER che salta di un pixel
; ai colpi della CPU, RUSH trattini che scorrono (net_tick, ogni frame). Nelle altre partite la
; mezzeria di sempre (K_NONE).
NET_CH = CHARSET + 8 * CH_LINE_L
.assert CH_LINE_R = CH_LINE_L + 1 .and K_NONE = 7, error, "reti: i due caratteri della mezzeria in fila, K_NONE ultimo"
.proc net_setup
    lda #K_NONE
    ldx cg_active
    cpx #CG_LADDER
    bne :+
    ldx ch_level
    lda rung_kind,x
    cpx #CH_OMEGA               ; OMEGA: la sua rete (om_net), sulla mezzeria di sempre
    bcc :+
    lda #K_NONE
:
set:
    sta net_kind
    tax
    lda net_skips,x
    sta net_skip
    lda #$ff
    sta net_var
    lda #12                     ; HAMMER fermo
    sta net_t
    txa
    asl a
    asl a
    asl a
    tax
    ldy #0
:   lda net_l,x
    sta NET_CH,y
    lda net_r,x
    sta NET_CH + 8,y
    inx
    iny
    cpy #8
    bne :-
    rts
.endproc

; La mezzeria di sempre nei caratteri della rete (la rete dell'avversario resta nel set dopo la
; partita: il puntino della chiusura del GAME OVER li usa).
.proc net_plain
    lda #K_NONE
    jmp net_setup::set
.endproc

.proc net_tick
    lda net_kind
    cmp #K_RUSH
    beq rush
    cmp #K_TWIST
    beq twist
    cmp #K_HAMMER
    beq hammer
    rts
rush:
    ; trattini di 4 righe ogni 8 che scendono di una riga a tick
    lda tick
    and #7
    sta net_t
    ldx #7
row:
    txa
    sec
    sbc net_t
    and #7
    cmp #4
    lda #0
    ldy #0
    bcs :+
    lda #$01
    ldy #$80
:   sta NET_CH,x
    tya
    sta NET_CH + 8,x
    dex
    bpl row
    rts
twist:
    ; palla entro 30 pixel dalla rete: inclinata di 2 pixel verso dove va (variante 1 a destra,
    ; 2 a sinistra)
    ldx #0
    lda ball_x+2
    cmp #<(160 - 30)
    lda ball_x+3
    sbc #>(160 - 30)
    bcc :+
    lda ball_x+2
    cmp #<(160 + 30)
    lda ball_x+3
    sbc #>(160 + 30)
    bcs :+
    inx
    lda ball_vx+3
    bpl :+
    inx
:   cpx net_var
    beq done
    stx net_var
    txa
    asl a
    asl a
    tax
    ldy #0
:   lda tw_l,x
    sta NET_CH,y
    lda tw_r,x
    sta NET_CH + 8,y
    inx
    iny
    cpy #4
    bne :-
done:
    rts
hammer:
    ; colpo della CPU (la palla che si allontana da lei): 12 frame di vibrazione, un pixel da
    ; una parte e dall'altra
    lda events
    and #EV_HIT
    beq count
    lda ball_vx+3
    ldx cpu_side
    beq :+
    eor #$80
:   bmi count
    lda #0
    sta net_t
count:
    ldx #0
    lda net_t
    cmp #12
    bcs set
    inc net_t
    and #2
    beq set
    inx
    lda net_t
    and #4
    beq set
    inx
set:
    cpx net_var
    beq done
    stx net_var
    lda ham_l,x
    ldy ham_r,x
    ldx #7
:   sta NET_CH,x
    pha
    tya
    sta NET_CH + 8,x
    pla
    dex
    bpl :-
    rts
.endproc

.endif
net_kind: .byte K_NONE          ; rete della partita (net_setup)
net_skip: .byte 0               ; righe di caratteri vuote: bit (riga and 3)
net_var:  .byte 0               ; animazione a schermo
net_t:    .byte 0
; i due caratteri per tipo (K_*, poi K_NONE): colonna 19 (bit 0 = x 159) e colonna 20 (bit 7 = x 160)
.ifndef ROTATED                 ; (campo girato: rot_video.s)
net_l: .byte $00, $00, $07, $04, $04, $04, $04, $07   ; ARCADE: quadratini, ogni 16 righe
       .byte $01, $01, $01, $01, $01, $01, $01, $01   ; TITAN: trattini di 24 righe ogni 32
       .byte $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E   ; HAMMER: rete doppia, 8 righe ogni 16
       .byte $03, $03, $01, $01, $00, $00, $00, $00   ; TWIST: trattini inclinati
       .byte $06, $06, $00, $00, $00, $00, $00, $00   ; BLASTER: due file di puntini
       .byte $01, $01, $01, $01, $00, $00, $00, $00   ; RUSH (poi scorre)
       .byte $07, $07, $07, $07, $00, $00, $00, $00   ; GUARDIAN: mattoni
       .byte $01, $01, $01, $01, $00, $00, $00, $00   ; la mezzeria di sempre
net_r: .byte $00, $00, $E0, $20, $20, $20, $20, $E0
       .byte $80, $80, $80, $80, $80, $80, $80, $80
       .byte $70, $70, $70, $70, $70, $70, $70, $70
       .byte $00, $00, $80, $80, $00, $00, $00, $00
       .byte $00, $00, $00, $00, $60, $60, $00, $00
       .byte $80, $80, $80, $80, $00, $00, $00, $00
       .byte $BC, $BC, $BC, $BC, $00, $00, $00, $00
       .byte $80, $80, $80, $80, $00, $00, $00, $00
net_skips: .byte %1010, %1000, %1010, 0, 0, 0, 0, 0
tw_l:  .byte $03, $03, $01, $01,  $00, $00, $00, $00,  $0C, $0C, $06, $06
tw_r:  .byte $00, $00, $80, $80,  $C0, $C0, $60, $60,  $00, $00, $00, $00
ham_l: .byte $0E, $07, $1C
ham_r: .byte $70, $38, $E0
.endif

.ifndef ROTATED                 ; (campo girato: rot_video.s)
; Punteggi: in due ai lati della mezzeria; in singolo i colpi a sinistra, record e palle a destra.
.proc draw_scores
    ldy #0
    jsr draw_side
    lda m_players
    cmp #2
    bne single
    ldy #4
    jmp draw_side
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

; Punteggio del lato Y (0: colonna 11, 4: colonna 23). Al punto in due si rifà solo quello di chi
; ha segnato (play.s): con il tick del punto e il resto del frame, entrambi sforavano sull'NTSC.
.proc draw_side
    ldx score,y
    lda score+1,y
    jsr clamp99
    ldx #11
    cpy #0
    beq :+
    ldx #23
:   ldy #1
    jmp draw_score2
.endproc

.endif
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
.ifndef ROTATED                 ; (campo girato: rot_video.s)
.proc compute_sprites
    lda #0
    sta pd_made
    jsr game_sprites            ; (A = MODE_TEXT = 0)
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
    lda serve_timer
    cmp #P_SERVE_TICKS + 1
    bcs ball_on
    ; nascosta se (attesa * 8 / tick al secondo) è dispari, come nel gioco su PC (la divisione per
    ; sottrazioni: al più 8)
    asl a
    asl a
    asl a
    ldy #0
:   cmp #P_TICK_HZ
    bcc :+
    sbc #P_TICK_HZ
    iny
    bne :-
:   tya
    lsr a
    jcs pads
ball_on:
    ; colonna: byte 2 e 3 di x - r + HALF_PX - 1 ($7FFF: i byte 0 e 1 danno solo il riporto, che
    ; entra nel byte 2 insieme a SPR_X0, una somma sola: al più un riporto nel byte 3)
    sec
    lda ball_x
    sbc ball_r
    tax
    lda ball_x+1
    sbc ball_r+1
    tay
    lda ball_x+2
    sbc ball_r+2
    sta m_lo
    lda ball_x+3
    sbc ball_r+3
    sta m_t
    cpx #1                      ; C = riporto di x0 + $FF
    tya
    adc #>(HALF_PX - 1)
    lda m_lo
    adc #SPR_X0
    sta sh_x
    lda m_t
    adc #0
    and #1
    sta sh_msb
    ; riga: byte 2 di P_HEIGHT - HALF_PX - (y + r) (byte 0-2: il byte 0 dà solo il riporto)
    clc
    lda ball_y
    adc ball_r
    sta m_lo
    lda ball_y+1
    adc ball_r+1
    sta m_t
    lda ball_y+2
    adc ball_r+2
    sta t1+2
    lda #<(P_HEIGHT - HALF_PX)
    cmp m_lo
    lda #>(P_HEIGHT - HALF_PX)
    sbc m_t
    lda #^(P_HEIGHT - HALF_PX)
    sbc t1+2
    clc
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
    ldy #0
    jsr pad_sprite
    lda m_players
    cmp #2
    bne :+
    ldx #4
    ldy #1
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
    lda #COL_YELLOW
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
    lda #COL_YELLOW
    sta sh_col,x
:   lda cap_bonus,y
    cmp #B_SUPER
    bne :+
    lda #COL_YELLOW
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

.endif
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

; Prima del tick: quali racchette sono a casa (pad_x = pad_home, i 4 byte; prima il byte 2, che di
; solito è quello diverso).
.proc dash_before
    .repeat 2, s
    ldx #0
    lda pad_x+4*s+2
    cmp pad_home+4*s+2
    bne :+
    lda pad_x+4*s
    cmp pad_home+4*s
    bne :+
    lda pad_x+4*s+1
    cmp pad_home+4*s+1
    bne :+
    lda pad_x+4*s+3
    cmp pad_home+4*s+3
    bne :+
    inx
:   stx pd_home+s
    .endrepeat
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

; Racchetta X (0 o 4) del lato Y (0 o 1): posizione dello sprite 1 o 2 e la sua immagine. X = side
; alla fine.
.ifndef ROTATED                 ; (campo girato: rot_video.s)
PS_K = HALF_PX - 1 - P_PAD_HALF_W  ; colonna della racchetta: x + PS_K, byte 2 e 3
kind_side: .byte 0, 8           ; pad_dx: la racchetta destra dopo i tipi della sinistra

.proc pad_sprite
    stx side
    ; colonna in t0+2 e t0+3 (per slide_x): i byte 0 e 1 della somma danno solo il riporto
  .if (::PS_K & $FF) = 0
    clc
  .else
    lda pad_x,x
    cmp #<(256 - (PS_K & $FF))  ; C = riporto di x0 + il byte 0 di PS_K
  .endif
    lda pad_x+1,x
    adc #>PS_K
    lda pad_x+2,x
    adc #^PS_K
    sta t0+2
    lda pad_x+3,x
    adc #<(PS_K >> 24)
    sta t0+3
    ; colonna a schermo: lo scatto scivola in circa 5 frame (slide_x, solo se la colonna disegnata
    ; non è già quella o se deve arrivare subito)
    cmp pd_draw_hi,y
    bne slide
    lda t0+2
    cmp pd_draw_lo,y
    bne slide
    lda pd_snap,y
    beq slid
slide:
    jsr slide_x
slid:
    ; la banda EVO dalla colonna della racchetta, lo sprite della racchetta pad_dx pixel prima
    ; (per tipo e lato: dove sta la faccia dell'astronave nell'immagine)
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
    ; pixel e torna, un frame alla volta (X = side dall'inizio: slide_x non lo cambia)
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
    ; tipo della racchetta in pi_kind (K_NONE fuori da NEXT)
    lda #K_NONE
    ldx m_next
    beq :+
    ldx side
    lda nx_kind,x
:   sta pi_kind
    cmp #K_RUSH                 ; RUSH vibra come su PC e MiSTer: un pixel avanti e indietro ogni
    bne :++                     ; 8 frame
    lda frame_count
    and #8
    beq :+
    inc v_n
    bne :+
    inc v_col
:   lda pi_kind
:   ora kind_side,y
    tax
    lda v_n
    sec
    sbc pad_dx,x
    sta sh_x+SPN_PAD,y
    ldx side
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
    clc
    adc pad_half,x
    lda t1+1
    adc pad_half+1,x
    lda t1+2
    adc pad_half+2,x
    sta pd_r1
    lda t1
    cmp pad_half,x
    lda t1+1
    sbc pad_half+1,x
    lda t1+2
    sbc pad_half+2,x
    clc
    adc #1
    sta pd_r0
    ; area boost (EVO): metà altezza dell'area (byte 0-2 di pad_bh / 2)
    ldx m_evo
    beq image_r0                ; (A = r0)
    ldx side
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
    sta m_t                     ; b0
    lda t1
    clc
    adc t2
    lda t1+1
    adc t2+1
    lda t1+2
    adc t2+2                    ; b1
    ; banda: sprite non espanso dalla riga b0, alto b1 - b0 + 1 righe (se ce ne sono)
    sec
    sbc m_t
    bcc image
    cmp #SPRITE_BANDS
    bcc :+
    lda #SPRITE_BANDS - 1
:   clc
    adc #SP_BAND1
    sta sh_ptr+SPN_BAND,y
    lda m_t
    clc
    adc #SPR_Y0
    sta sh_y+SPN_BAND,y
    lda bit_of+SPN_BAND,y
    ora sh_enable
    sta sh_enable
image:
    lda pd_r0
image_r0:
    clc
    adc #SPR_Y0
    sta sh_y+SPN_PAD,y
    lda bit_of+SPN_PAD,y
    ora sh_enable
    sta sh_enable
    ; righe dello sprite: ognuna copre le righe r0 + 2k e r0 + 2k + 1 ed è accesa se
    ; r0 + 2k <= r1, cioè le prime (r1 - r0) / 2 + 1 = (r1 - r0 + 2) / 2 (9 bit)
    lda pd_r1
    sec
    sbc pd_r0
    bcs :+
    bit pd_r0                   ; r1 < r0: nessuna riga, tranne con r0 sopra il campo (negativo:
    bpl none                    ; OMEGA appena trasformato, più alto, vicino al bordo, finché il
    sec                         ; core non lo riporta dentro; come sul PC esce dal campo)
:   adc #1                      ; (C = 1)
    ror a
    cmp #PAD_ROWS + 1
    bcc :+
    lda #PAD_ROWS
    bne :+
none:
    lda #0
:   sta pi_n
    sta pd_cur_n,y              ; (l'immagine dipende da righe, tipo e variante)
    sty pi_side
    lda pd_r0                   ; riga del centro (salto del TELEPORT)
    clc
    adc pd_r1
    ror a
    sta pd_cy,y
    ldx m_next
    jeq evo
    ; NEXT. Colore: grigio con il BULLET scattato dell'avversario, con STEER e, a tratti, con un
    ; bonus armato o con il proprio BULLET armato e non ancora scattato
    ldx side
    lda nx_btimer
    bne bullet
    lda nx_steer
    beq armed
    cpx nx_steer_s
    beq gray
armed:
    lda nx_armed,x
    cmp #B_NONE
    bne blink
    cpx nx_bside                ; (BULLET non scattato: il proprio, armato)
    bne white
blink:
    lda tick
    and #PAD_BLINK
    beq white
gray:
    lda #COL_GRAY
    bne color
bullet:
    cpx nx_bside                ; BULLET scattato
    bne gray
    lda nx_steer
    beq :+
    cpx nx_steer_s
    beq gray
:   lda nx_armed,x
    cmp #B_NONE
    bne blink
white:
    ; lampo giallo del colpo di una mossa: i primi 4 frame, e con la MAX (31) anche dal 16° al 19°
    lda sm_kick,x
    and #%1100
    cmp #%1100
    bne :+
    lda #COL_YELLOW
    bne color
:   ; colpita dal laser del BLASTER (rallentata): verde chiaro a tratti, come l'alone del PC
    lda nx_lslow,x
    beq :+
    lda tick
    and #PAD_BLINK
    beq :+
    lda #COL_GREEN
    bne color
:   cpx nx_morph                ; colore dedicato del tipo (OMEGA: om_white, omega.s)
    bne kind_color
    jsr om_white
    bne color                   ; (sempre: bianco o viola)
kind_color:
    ldx pi_kind
    lda kind_col,x
color:
    sta sh_col+SPN_PAD,y
    ; variante dell'immagine in pi_var: TWIST l'inclinazione + 3, BLASTER i colpi nel caricatore
    ; * 32, GUARDIAN i settori persi (un bit per settore: 0 il muro intero); X = il posto
    ; dell'immagine nel blocco del lato (TWIST pi_var, BLASTER pi_ammo, gli altri 0)
    ldx side
    lda pi_kind
    cmp #K_BLASTER
    bne not_blaster
    ldy nx_ammo,x               ; livello del caricatore (mag_setup)
    ldx bl_vis,y
    stx pi_ammo
    lda bl_var,x
    sta pi_var
    ldy pi_side
    jmp prep
not_blaster:
    cmp #K_TWIST
    jeq twist
    cmp #K_GUARDIAN
    bne :+
    lda nx_barrier,x
    eor #(1 << G_SECTORS) - 1
    sta pi_var
    beq pose
    ; GUARDIAN con dei settori persi: l'immagine dinamica, fatta dal muro intero preparato
    lda #0
    sta pd_full,y
    lda pp_ready,y
    jeq dynamic
    lda pi_n
    cmp pp_n,y
    jne dynamic
    lda prep_base,y
    sta pd_full,y
    jmp dynamic
:   lda #0
    sta pi_var
pose:
    tax                         ; (A = 0)
prep:
    ; l'immagine preparata a inizio partita, se c'è (pad_prep, dalla cartuccia): TWIST per
    ; inclinazione, BLASTER per colpi nel caricatore, così il caricatore cala nel frame del colpo
    ; (Y = lato)
    lda #0                      ; (nessun muro intero del GUARDIAN da cui partire)
    sta pd_full,y
    lda pp_ready,y              ; (next_morph lo azzera: il blocco della forma nuova arriva tra poco)
    jeq dynamic
    lda pi_n
    cmp pp_n,y
    jne dynamic
    txa
    clc
    adc prep_base,y
put:
    sta sh_ptr+SPN_PAD,y
spin:
    ; NEXT: SUPER armato con la rotazione (animazione 0): al posto della racchetta l'immagine
    ; dell'angolo del frame, centrata sulla racchetta (sprite hires espanso)
    ldx side
    lda nx_armed,x
    cmp #B_SUPER
    bne no_spin1
    cpx nx_morph                ; (OMEGA non ruota, come prima: spin_prep non gli prepara le
    beq no_spin1                ; immagini della rotazione)
    lda nx_anim,x
    bne no_spin1
    lda sp_k
    cmp #16
    jcs spin_on                 ; (prima le immagini pronte)
no_spin1:
    rts
evo:
    ; le altre partite: racchetta bianca senza tipo, niente immagini preparate
    lda #COL_WHITE
    sta sh_col+SPN_PAD,y
    lda #0
    sta pi_var
    sta pd_full,y
dynamic:
    lda pi_n
    cmp pd_n,y
    bne make
    lda pi_kind
    cmp pd_kind,y
    bne make
    lda pi_var
    cmp pd_var,y
    beq done                    ; (game_sprites mette nello sprite l'immagine dinamica)
make:
    ; una sola immagine per frame (costa qualche migliaio di cicli): l'altra al prossimo; nel
    ; GAME OVER le racchette sono ferme e quel frame ha già le scritte da fare
    lda pd_made
    bne keep
    lda state
    cmp #ST_OVER
    beq done
    lda wp_on                   ; durante il salto del TELEPORT l'immagine è quella del salto
    beq :+
    lda wp_side
    cmp pi_side
    beq done
:
    ; frame già avanti: al prossimo. Il GUARDIAN dal muro intero (guard) costa meno di un terzo
    ; di pad_image e si fa anche più avanti nel frame
    lda #LATE_BIG
    ldx pd_full,y
    beq :+
    lda #LATE_GUARD
:   jsr frame_after
    bcs keep
    inc pd_made
    lda pi_n
    sta pd_n,y
    lda pi_kind
    sta pd_kind,y
    lda pi_var
    sta pd_var,y
    lda #1
    sta pd_dirty,y
    lda pd_full,y
    bne guard
    jsr pad_image               ; (game_sprites ha messo nello sprite l'immagine dinamica)
    ldy pi_side
keep:
    ; immagine rimandata (o appena fatta: pd_n non è $FF): se nello sprite dinamico non c'è la
    ; racchetta (pd_n = $FF: c'è il pezzo del salto del TELEPORT) e c'è il muro intero del
    ; GUARDIAN, intanto quello
    ldx pd_n,y
    inx
    bne done
    lda pd_full,y
    jne put
done:
    lda m_next
    jne spin
    ldx side
no_spin:
    rts
guard:
    ; GUARDIAN con dei settori persi (pi_var): in sh_img l'immagine preparata del muro intero (lo
    ; sprite A), poi lo scudo grigio nei settori persi (guard_gray, come pad_image)
    ldx #0
    stx ptr
    lsr a
    ror ptr
    lsr a
    ror ptr
    ora #>$C000
    sta ptr+1                   ; (ptr) = $C000 + A * 64
    lda img_base,y
    bne g_right
    ldy #IMG_BYTES - 1
:   lda (ptr),y
    sta sh_img,y
    dey
    bpl :-
    bmi g_gray                  ; (sempre)
g_right:
    ldy #IMG_BYTES - 1
:   lda (ptr),y
    sta sh_img + IMG_BYTES,y
    dey
    bpl :-
g_gray:
    lda pi_var
    jsr guard_gray
    jmp done
spin_on:
    ldy pi_side
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
    ldx side
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
    tax
    ldy pi_side
    jmp prep
.endproc

.endif
TILT1 = P_PAD_MAX_SPEED / 6
TILT2 = P_PAD_MAX_SPEED / 2
TILT3 = P_PAD_MAX_SPEED * 5 / 6

; Caricatore del BLASTER: i colpi (0..P_BLASTER_SHOTS) si mappano su BLASTER_VIS + 1 livelli
; visivi (0..4) per stare nei posti degli sprite di OMEGA prima di VOL_TAB; pad_image spegne dall'alto
; il colore del tipo (pad_bl_thr).
; mag_setup mappa A colpi in livello visivo e prosegue in mag_vis (usata anche da pad_prep).
BLASTER_VIS = 4
bl_vis: .byte 0, 1, 2, 2, 3, 3, 4
.ifndef ROTATED
bl_var: .byte 0, 32, 64, 96, 128    ; pi_var del BLASTER: livello visivo * 32 (pad_sprite)
.endif
.proc mag_setup
    tay
    lda bl_vis,y
.endproc
.proc mag_vis
    sta pi_ammo
    rts
.endproc
.assert P_BLASTER_SHOTS = 6, error, "caricatore del BLASTER: bl_vis mappa 0..6 in 0..4"

.ifndef ROTATED                 ; (campo girato: le pose dalla cartuccia, anche fuori dalla partita)
; Immagine della racchetta di pi_side in sh_img (63 byte, 3 per riga): pi_n righe dell'astronave del
; tipo pi_kind (PAD_IMG_* di gen/assets.inc, dagli sprite di assets/ships/sprites/c64), vista dalla
; racchetta sinistra; per la destra ogni riga si specchia. La racchetta senza tipo (K_NONE) è il
; corpo bianco nelle colonne doppie 4 e 5. Varianti: TWIST le righe spostate verso il davanti o il
; retro con l'inclinazione (pi_var - 3, a gradini lungo l'altezza), BLASTER il colore del tipo grigio
; nelle righe sopra la soglia del livello del caricatore (pi_ammo), GUARDIAN lo scudo grigio nei
; settori persi (pi_var, guard_gray).
.proc pad_image
    ldy pi_side
    lda img_base,y
    sta pi_out
    lda pi_n
    lsr a
    sta pi_half
    ldx pi_kind
    cpx #K_NONE
    bcs :+
    lda pad_img_lo,x
    sta ptr
    lda pad_img_hi,x
    sta ptr+1
:   cpx #K_BLASTER
    bne :+
    ldy pi_ammo
    lda pad_bl_thr,y
    sta pi_full
:   cpx #K_TWIST
    bne rows
    ; TWIST: |t| e (k - n/2) * |t| alla riga 0, poi + |t| a ogni riga
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
    lda #0
    sta pi_k
row:
    lda pi_k
    cmp pi_n
    jcs blank
    ldx pi_kind
    cpx #K_NONE
    bcc ship
    lda #0
    sta pi_row
    sta pi_row+2
    lda #(COLOR_WHITE * $55) & $F0
    sta pi_row+1
    jmp mirror
ship:
    cmp pad_img_n,x
    jcs blank
    sta m_lo
    asl a
    adc m_lo                    ; * 3 (C = 0)
    tay
    lda (ptr),y
    sta pi_row
    iny
    lda (ptr),y
    sta pi_row+1
    iny
    lda (ptr),y
    sta pi_row+2
    cpx #K_BLASTER
    bne tilt
    lda pi_k
    cmp pi_full
    bcs mirror
    ; riga sopra il caricatore: %10 (colore del tipo) diventa %01 (grigio)
    ldx #2
:   lda pi_row,x
    asl a
    eor #$ff
    and pi_row,x
    and #%10101010
    sta m_lo
    lsr a
    ora m_lo
    eor pi_row,x
    sta pi_row,x
    dex
    bpl :-
    bmi mirror                  ; (sempre)
tilt:
    cpx #K_TWIST
    bne mirror
    ; TWIST: riga spostata di (acc >> 3) colonne doppie verso il davanti, con il segno
    ; dell'inclinazione (la destra si specchia dopo: lo spostamento è lo stesso)
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
:   tax
    lda pi_acc
    clc
    adc pi_tabs
    sta pi_acc
    txa
    beq mirror
    bmi back
    asl a                       ; due bit per colonna doppia
    tax
:   lsr pi_row
    ror pi_row+1
    ror pi_row+2
    dex
    bne :-
    beq mirror                  ; (sempre)
back:
    eor #$ff
    clc
    adc #1
    asl a
    tax
:   asl pi_row+2
    rol pi_row+1
    rol pi_row
    dex
    bne :-
mirror:
    lda pi_side
    beq store
    ldx pi_row
    lda pi_row+2
    jsr mirror_byte
    sta pi_row
    txa
    jsr mirror_byte
    sta pi_row+2
    lda pi_row+1
    jsr mirror_byte
    sta pi_row+1
    jmp store
blank:
    lda #0
    sta pi_row
    sta pi_row+1
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
    lda pi_kind
    cmp #K_GUARDIAN
    bne done
    lda pi_var
    bne guard_gray
done:
    rts
.endproc

; GUARDIAN: nell'immagine del lato pi_side lo scudo (colonne doppie 4 e 5, nella racchetta destra 6 e
; 7: il byte 1 di ogni riga) grigio nei settori persi A (bit 0 il settore in alto). I settori si
; contano dalle giunture nel colore del tipo; si fa grigia solo una riga di scudo tutta bianca.
.proc guard_gray
    sta pi_k                    ; bit 0: il settore della riga è perso
    ldx pi_side
    lda guard_mask,x
    sta m_t
    ldy img_base,x
    ldx #PAD_ROWS
row:
    lda sh_img+1,y
    and m_t
    sta m_lo
    lda #COLOR_YELLOW * $55
    and m_t
    cmp m_lo
    bne :+
    lsr pi_k                    ; giuntura: il settore dopo
    jmp next
:   lda m_t                     ; (bianco: %11 in tutte e due le colonne)
    cmp m_lo
    bne next
    lda pi_k
    lsr a
    bcc next
    lda m_t
    eor #$ff
    and sh_img+1,y
    sta m_lo
    lda #COLOR_GRAY * $55
    and m_t
    ora m_lo
    sta sh_img+1,y
next:
    iny
    iny
    iny
    dex
    bne row
    rts
.endproc
guard_mask: .byte $F0, $0F
.assert COLOR_GRAY = 1 .and COLOR_YELLOW = 2 .and COLOR_WHITE = 3, error, "guard_gray: colori dello scudo del GUARDIAN"

; A con le quattro coppie di bit in ordine inverso (pixel multicolore specchiati). Y cambia.
.proc mirror_byte
    pha
    and #$0F
    tay
    lda mir_hi,y
    sta m_lo
    pla
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    lda mir_lo,y
    ora m_lo
    rts
.endproc
; due coppie di bit scambiate (ab -> ba), nel nibble basso e in quello alto
mir_lo: .repeat 16, I
    .byte ((I & 3) << 2) | (I >> 2)
.endrepeat
mir_hi: .repeat 16, I
    .byte (((I & 3) << 2) | (I >> 2)) << 4
.endrepeat

; astronavi dei tipi (ARCADE, TITAN, HAMMER, TWIST, BLASTER, RUSH, GUARDIAN), gen/assets.inc
pad_img0: .byte PAD_IMG_ARCADE
pad_img1: .byte PAD_IMG_TITAN
pad_img2: .byte PAD_IMG_HAMMER
pad_img3: .byte PAD_IMG_TWIST
pad_img4: .byte PAD_IMG_BLASTER
pad_img5: .byte PAD_IMG_RUSH
pad_img6: .byte PAD_IMG_GUARDIAN
pad_img_lo: .lobytes pad_img0, pad_img1, pad_img2, pad_img3, pad_img4, pad_img5, pad_img6
pad_img_hi: .hibytes pad_img0, pad_img1, pad_img2, pad_img3, pad_img4, pad_img5, pad_img6
pad_img_n:  .byte PAD_IMG_N
pad_bl_thr: .byte PAD_BL_THR
.endif
; pixel tra il bordo sinistro dello sprite e la colonna della racchetta: sinistra per tipo (K_NONE
; per ultimo), poi destra
.ifndef ROTATED
pad_dx:     .byte PAD_DX_L, PAD_DX_R
.endif
.assert K_ARCADE = 0 .and K_TITAN = 1 .and K_HAMMER = 2 .and K_TWIST = 3 .and K_BLASTER = 4 .and K_RUSH = 5 .and K_GUARDIAN = 6 .and K_NONE = 7, error, "astronavi delle racchette nell'ordine dei tipi"

; colore dedicato di ciascuna astronave (%10 = $D027+i): ARCADE, TITAN, HAMMER, TWIST, BLASTER,
; RUSH, GUARDIAN, OMEGA
kind_col:
    .byte COL_YELLOW, COL_ORANGE, COL_RED, COL_PURPLE, COL_DGREEN, COL_CYAN, COL_LBLUE, COL_PURPLE


img_base: .byte 0, IMG_BYTES
prep_base: .byte SP_PREP0, SP_PREP0 + 8


bit_of: .byte %00000001, %00000010, %00000100, %00001000, %00010000, %00100000, %01000000, %10000000

.ifndef ROTATED                 ; (campo girato: rot_video.s)
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
    ; immagini delle racchette cambiate (di rado: altezza, tipo, inclinazione, caricatore; nel
    ; salto del TELEPORT a ogni frame, pd_dirty = 2: solo le righe rifatte, wp_rows)
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
    cmp #2
    bne :+
    jsr warp_rows_l
    bcc right                   ; (C = 0: fatto; C = 1: tutte le righe, la copia intera)
:   ldx #IMG_BYTES - 1
:   lda sh_img,x
    sta SPRITES + 2 * 64,x
    dex
    bpl :-
right:
    lda pd_dirty+1
    beq copied
    cmp #2
    bne :+
    jsr warp_rows_r
    bcc copied                  ; (C = 0: fatto; C = 1: tutte le righe, la copia intera)
:   ldx #IMG_BYTES - 1
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
    sta wp_rows
done:
    rts
.endproc

; apply_shadows, immagine della partenza del salto del TELEPORT di una racchetta (warp_rows_l la
; sinistra, warp_rows_r la destra): nella RAM degli sprite (I/O spento) solo le righe delle classi
; rifatte da warp_image (wp_rows: la classe k ha le righe (k * 5) & 7, + 8, + 16). C = 0 fatto;
; C = 1 con tutte le classi (prima immagine del salto): allora la copia intera, che costa meno.
; Usa m_lo.
.macro warp_rows_of img, spr
    .local cls, row, next, all
    lda wp_rows
    cmp #$ff
    beq all
    sta m_lo
    ldx #0
cls:
    lsr m_lo
    bcc next
    ldy wp_ylast,x              ; ultimo byte della classe, poi una riga ogni 8 (24 byte) indietro
row:
    lda img,y
    sta spr,y
    lda img+1,y
    sta spr+1,y
    lda img+2,y
    sta spr+2,y
    tya
    sbc #3 * 8                  ; (C = 1 dal bit della classe, poi senza prestito)
    tay
    bcs row
next:
    inx
    lda m_lo
    bne cls
    clc
all:
    rts
.endmacro
.proc warp_rows_l
    warp_rows_of sh_img, SPRITES + 2 * 64
.endproc
.proc warp_rows_r
    warp_rows_of sh_img + IMG_BYTES, SPRITES + 3 * 64
.endproc

.endif
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
SP_RING0  = SP_SPIN0 + 16      ; alone di SLOW, palla 4 e 6 (dopo le immagini delle racchette)

; Un'immagine degli effetti per frame, finché non ci sono tutte: gli aloni si disegnano dai
; quadrati di FX_SQUARES (x, y, lato in pixel; $FF chiude l'immagine), che fx_sp scorre.
; Un'immagine si fa solo se il frame resta nel budget.
.ifdef ROTATED
FX_COST = 11000                 ; (campo girato: anche l'interrupt della mezzeria, che cade nel frame)
.else
FX_COST = 10500
.endif
FX_LATE = (TV_BUDGET - (500 + FX_COST)) / TV_LCYC
.ifndef ROTATED                 ; (campo girato: rot_video.s)
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

.endif

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
    lda #COL_YELLOW
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

.ifndef ROTATED                 ; (campo girato: rot_video.s)
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

.endif
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
; cache costa al massimo circa 1.500 cicli (firma della cometa e quattro confronti), il disegno
; fino a circa 7.100 con la firma (cicli veri, misurati con paddws-c64 frames). Il disegno si fa solo se il frame resta nel
; budget: nei frame più carichi aspetta, intanto c'è la forma della cache più simile.
; La ricerca si fa solo con il tempo per firma, confronti e sprite (fino a circa 2.300 cicli veri), se
; no dopo sprite e HUD pesanti il frame passava il budget
.if (TV_BUDGET - 2700) / TV_LCYC > 255
TRAIL_LATE_FIND = 255
.else
TRAIL_LATE_FIND = (TV_BUDGET - 2700) / TV_LCYC
.endif
TRAIL_LATE = (TV_BUDGET - (7600)) / TV_LCYC
; una metà del disegno in sospeso (trail_first o trail_rest con lo sprite: fino a circa 2.900)
TRAIL_LATE_HALF = (TV_BUDGET - (3100)) / TV_LCYC

; Posizione della palla sullo schermo (sh_x con il nono bit in sh_msb, sh_y) in testa alle passate.
; Nel bullet time la coda dura il doppio, come sul PC: nei tick dispari cambia solo la posizione di
; adesso, così le passate sono di 2 frame in 2 frame (e la firma va rifatta da capo).
; A ogni colpo (vx cambia segno) la coda riparte, come sul PC (next_ui.rs): valgono solo le passate
; da allora (tr_nv; trail_layout toglie le altre). Se no restava piegata sul percorso d'arrivo, e
; con la CURVE presa al colpo non seguiva la traiettoria nuova. (Poco lavoro qui: il frame del colpo
; è il più pesante.)
; Le passate (età da 1 a TRAIL_N) stanno nei posti da 1 a TRAIL_N di tr_x, tr_xh e tr_y in un anello:
; l'età a nel posto 1 + (tr_rp + a - 1) mod TRAIL_N; la testa (età 0) sempre nel posto 0. A ogni
; frame la testa di prima prende il posto della passata più vecchia, senza spostare le altre.
.proc trail_push
    lda tr_lay                  ; la firma dell'ultimo frame vale per il prossimo solo se è di quello
    sta tr_prev_ok
    lda #0
    sta tr_lay
    lda ball_vx+3
    eor tr_vxs
    bpl :+
    eor tr_vxs
    sta tr_vxs
    lda #0
    sta tr_nv
    sta tr_prev_ok
    beq head                    ; (sempre)
:
    lda nx_btimer
    beq :+
    lda tick
    lsr a
    bcc :+
    lda #0
    sta tr_prev_ok
    beq head
:   lda tr_nv
    cmp #TRAIL_N
    bcs :+
    inc tr_nv
:   ldx tr_rp                   ; la più vecchia (età TRAIL_N) diventa l'età 1
    dex
    bpl :+
    ldx #TRAIL_N - 1
:   stx tr_rp
    lda tr_x
    sta tr_x + 1,x
    lda tr_xh
    sta tr_xh + 1,x
    lda tr_y
    sta tr_y + 1,x
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
    ; la coda rimasta da disegnare nel frame prima per il tempo (tr_pend: il suo tipo + 1): con la
    ; firma di allora, se la palla ha ancora lo stesso angolo, subito, senza rifare firma e ricerca
    ; (circa 1.500 cicli con la cometa). A velocità costante la firma di adesso è quella a meno di
    ; un pixel, cioè la stessa per trail_match: dal frame dopo la trova nella cache
    ldx tr_pend
    sta tr_pend
    dex
    cpx tr_cm
    bne find_it
    jsr trail_cache
    jsr trail_dir
    cmp tr_dir
    bne find_it
    ; in due metà, una per frame (circa 2.700 cicli l'una): la prima nello sprite usato meno di
    ; recente, la seconda nel frame dopo, che lo mostra; senza tempo si riprova al prossimo
    lda #TRAIL_LATE_HALF
    jsr frame_after
    bcs keep
    ldx tr_half
    bne second
    jsr trail_oldest
    jsr trail_first
    ldx tr_dbuf
    inx
    stx tr_half
keep:
    ldx tr_cm
    inx
    stx tr_pend
    rts
second:
    lda #0
    sta tr_half
    jsr trail_rest
    jmp show
find_it:
    lda #0                      ; (una metà lasciata: lo sprite resta non valido)
    sta tr_half
    lda #TRAIL_LATE_FIND
    jsr frame_after
    jcs done
    jsr trail_cache
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
    ; da disegnare, se c'è tempo, nello sprite usato meno di recente tra quelli che non si vedono;
    ; se no al prossimo frame, con questa firma
    lda #TRAIL_LATE
    jsr frame_after
    bcc draw_it
    ldx tr_cm
    inx
    stx tr_pend
    rts
draw_it:
    jsr trail_oldest
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

; Prima coda della partita (nessuna ancora mostrata, tr_ready): la cache ha la bitmap dell'attract,
; tutta da rifare.
.proc trail_cache
    lda tr_ready
    bne done
    ldx #TRAIL_BUFS - 1
    stx tr_shown
invalid:
    lda #0
    sta tr_valid,x
    lda #$fe                    ; i più vecchi: si riempiono per primi
    sta tr_old,x
    dex
    bpl invalid
done:
    rts
.endproc

; X = lo sprite della cache usato meno di recente tra quelli che non si vedono.
.proc trail_oldest
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
    ldx tr_rp                   ; (posto della passata di un frame fa: X fino a dy)
    lda tr_x + 1,x              ; x di un frame fa - x di adesso, tra -47 e 47
    sec
    sbc tr_x
    sta tr_bx
    lda tr_xh + 1,x
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
    lda tr_y + 1,x              ; y di un frame fa - y di adesso
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
    lda tr_cm                   ; m_lo: la cometa nel bit 7 (bit, così Y resta il posto); nel
                                ; ciclo la differenza in m_t e m_sign (pagina zero)
    lsr a
    ror a
    sta m_lo
    ldy tr_rp                   ; Y: posto dell'età X nell'anello di trail_push (TRAIL_N: tr_rp,
    bne :+                      ; o TRAIL_N se è 0)
    ldy #TRAIL_N
:   ldx #TRAIL_N
rel:
    cpx tr_nv                   ; (prima dell'ultimo colpo: via)
    beq :+
    bcs far
:   lda tr_x,y
    sec
    sbc tr_x
    sta m_t
    lda tr_xh,y
    sbc tr_xh
    bit m_lo                    ; cometa: in pixel doppi, / 2 con il segno
    bpl :+
    cmp #$80
    ror a
    ror m_t
:   sta m_sign
    lda m_t
    clc
    adc tr_axo
    sta m_t
    lda m_sign
    adc #0
    bne far
    lda m_t
    cmp #TRAIL_SPAN
    bcs far
    sta tr_qxk,x
    lda tr_y,y
    sec
    sbc tr_y
    sta m_t
    lda #0
    sbc #0
    bit m_lo
    bpl :+
    cmp #$80
    ror a
    ror m_t
:   sta m_sign
    lda m_t
    clc
    adc tr_ayo
    sta m_t
    lda m_sign
    adc #0
    bne far
    lda m_t
    cmp #TRAIL_SPAN
    bcs far
    sta tr_qyk,x
    jmp next
far:
    lda #$ff
    sta tr_qxk,x
    sta tr_qyk,x
next:
    ; l'età dopo: il posto prima nell'anello (da 1 si torna a TRAIL_N); all'età 0 la testa, posto 0
    dex
    bmi done
    beq head
    dey
    jne rel
    ldy #TRAIL_N
    jmp rel
head:
    ldy #0
    jmp rel
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
; la firma. In due metà (una per frame: trail_end) trail_first e trail_rest.
.proc trail_draw
    jsr trail_first
.endproc                        ; (prosegue in trail_rest)

; La seconda metà nello sprite tr_dbuf: le posizioni da TRAIL_HALF a 1, la palla, la firma (lo
; sprite diventa valido). X = tr_dbuf alla fine.
.proc trail_rest
    ldx tr_dbuf
    jsr trail_ptr
    lda #0
    sta tr_stop
    ldx #TRAIL_HALF
    jsr trail_ages
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

; (ptr) = sprite X della cache (TRAIL_BASE + X * 64); X = 64 * X.
.proc trail_ptr
    txa
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
    rts
.endproc

; La prima metà nello sprite X: svuotato e non più valido (non lo trova trail_match finché la
; seconda metà non lo finisce), le posizioni da TRAIL_N a TRAIL_HALF + 1.
TRAIL_HALF = 2
.proc trail_first
    stx tr_dbuf
    lda #0
    sta tr_valid,x
    jsr trail_ptr
    lda #0
    ldy #9                      ; 7 scritture per giro, 9 giri: i byte 0-62 dello sprite (circa
:   .repeat 7, i                ; 380 cicli; srotolate tutte, 315, ma 160 byte in più)
    sta TRAIL_BASE + 9 * i,x    ; X = 64 * sprite + giro
    .endrepeat
    inx
    dey
    bne :-
    lda #TRAIL_HALF
    sta tr_stop
    ldx #TRAIL_N
.endproc                        ; (prosegue in trail_ages)

; Dalla posizione X fino a tr_stop + 1, dalla più vecchia: la posizione di k frame fa (età 2k - 1),
; poi quella a metà con k - 1 (età 2k - 2), solo se tra le due c'è un buco (distanza maggiore del
; lato).
.proc trail_ages
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
    cpx tr_stop
    bne age
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
    ; A = sinistra + 16, X = alto + 16. Colonne x1 = min(sinistra + lato - 1, 23) e
    ; x0 = max(sinistra, 0); fuori dalla griglia niente
    tay
    clc
    adc tr_n
    sbc #16                     ; (C = 0: meno 17)
    jcc out
    cmp #24
    bcc :+
    lda #23
:   sta tr_rm
    tya
    sec
    sbc #16
    bcs :+
    lda #0
:   cmp #24
    jcs out
    sta tr_lm
    ; righe y0 = max(alto, 0), y1 = min(alto + lato - 1, 20)
    txa
    clc
    adc tr_n
    sbc #16
    bcc out
    cmp #21
    bcc :+
    lda #20
:   sta tr_r0
    txa
    sec
    sbc #16
    bcs :+
    lda #0
:   cmp #21
    bcs out
    sta tr_qy
    eor #$ff                    ; righe in X: y1 - y0 + 1
    sec
    adc tr_r0
    tax
    inx
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
    dex
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
    dex
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
.ifndef ROTATED                 ; (campo girato: anelli già pronti, ROT_RINGS)
fx_squares:   .byte FX_SQUARES
.endif
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
tr_x:    .res TRAIL_N + 1       ; posizioni della palla sullo schermo: la testa, poi l'anello (trail_push)
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
tr_vxs:  .res 1                 ; segno di vx all'ultimo trail_push (bit 7)
tr_nv:   .res 1                 ; passate dopo l'ultimo colpo (0 - TRAIL_N): le altre non valgono
tr_rp:   .res 1                 ; anello delle passate: l'età 1 nel posto tr_rp + 1 (trail_push)
tr_sp:   .res 1                 ; lato della palla della firma di prima
tr_bx:   .res 1                 ; movimento della palla dal frame prima, al contrario
tr_by:   .res 1
tr_want: .res 1                 ; coda chiesta in questo frame
tr_pend: .res 1                 ; coda non disegnata nel frame prima per il tempo: tr_cm + 1, o 0
tr_half: .res 1                 ; sprite + 1 con la prima metà di quella coda (trail_first), o 0
tr_stop: .res 1                 ; trail_ages: ultima posizione esclusa
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

; NEXT: immagini delle racchette pronte nella cartuccia (gen/paddles.bin di tools/gen_c64_assets.py,
; byte per byte come pad_image, banco PAD_BANK): per tipo e lato un blocco di 8 posti (2 pagine),
; copiato nel blocco del lato, una pagina per frame, nei frame con il tempo e senza voci (next_hud;
; sull'NTSC anche om_early); nel posto k l'inclinazione k - 3 della TWIST, il livello k del
; caricatore del BLASTER, per gli altri tipi solo il posto 0. In partita si cambia solo il
; puntatore. Quando OMEGA si trasforma next_morph azzera pp_ready del suo lato e pp_side, e il suo
; blocco si ricopia nella pausa dopo il punto; intanto l'immagine dinamica.
SP_PREP0 = SP_FX0 + TRAIL_BUFS  ; 8 immagini per lato, i blocchi a inizio pagina
.assert (SP_PREP0 .mod 4) = 0, error, "immagini delle racchette: i blocchi a inizio pagina"
PP_DST = >($C000 + SP_PREP0 * 64)
PP_LATE = (TV_BUDGET - 5800) / TV_LCYC  ; come OM_LATE_COPY: la copia di una pagina e quello che resta

.ifndef ROTATED                 ; (campo girato: rot_video.s)
.proc pad_prep
    ldy pp_side
    cpy #2
    bcs quit                    ; tutte pronte (next_morph lo rimette a 0)
    lda pp_ready,y
    beq load
    iny
    sty pp_side
    bne pad_prep                ; (sempre)
load:
    lda #PP_LATE                ; una pagina, circa 3.700 cicli: anche in partita (OMEGA trasformato)
    jsr frame_after
    bcs quit
    lda pp_side
    asl a
    ora pp_var
    sta m_lo                    ; lato * 2 + pagina
    asl a
    and #%100
    tax                         ; lato * 4
    lda nx_kind,x
    tax
    asl a
    asl a                       ; (C = 0)
    adc m_lo
    adc #$80                    ; pagina nella ROML: tipo * 4 + lato * 2 + pagina
    sta ef_src+2
    lda pv_rows,x
    ldy pp_side
    sta pp_n,y                  ; righe delle immagini
    lda m_lo
    clc
    adc #PP_DST
    tay
    lda #PAD_BANK
    ldx #1
    jsr ef_copy
    ldy pp_side
    inc pp_var
    lda pp_var
    cmp #2
    bcc quit
    lda #0
    sta pp_var
    lda #1
    sta pp_ready,y
quit:
    rts
.endproc

.endif

.assert BLASTER_VIS + 1 <= 8, error, "immagini delle racchette: al massimo 8 per lato"

.segment "NEXTBSS"
pp_side:  .res 1                ; lato da preparare (2: tutti pronti)
pp_var:   .res 1                ; pagina del blocco in copia
pp_ready: .res 2                ; immagini pronte per il lato
pp_n:     .res 2                ; righe delle immagini del lato
.segment "CODE"

; C = 1 se il frame è già avanti: dall'interrupt della riga 250 sono passate più righe (TV_LCYC
; cicli veri ciascuna) di quelle che lasciano il tempo al lavoro rimandabile e a quello che resta
; del frame (riserve, coda). Immagini delle racchette e scritte in partita (frame_late: partono
; entro circa 8.700 cicli) e posti delle riserve (frame_late_small, entro 13.000) aspettano
; allora il frame dopo.
LATE_BIG   = (TV_BUDGET - (9000)) / TV_LCYC
LATE_SMALL = (TV_BUDGET - (4700)) / TV_LCYC
.ifdef NTSC
LATE_HUD   = (TV_BUDGET - (1400)) / TV_LCYC         ; NTSC: hud_slot costa ~550 cicli, e ne può seguire un altro
.else
LATE_HUD   = LATE_SMALL
.endif
LATE_SPIN  = (TV_BUDGET - (12300)) / TV_LCYC         ; un'immagine della rotazione del SUPER costa fino a circa 10.400
; spin_prep: con il byte basso della riga del raster da SPIN_FAST a RASTER_LINE - 1 il frame è di
; sicuro oltre LATE_SPIN (riga + TV_LINES - RASTER_LINE righe dall'interrupt), senza frame_after:
; non può essere una riga dopo la 255 (quelle hanno il byte basso sotto TV_LINES - 256)
SPIN_FAST_A = LATE_SPIN - (TV_LINES - RASTER_LINE)
SPIN_FAST  = SPIN_FAST_A * (SPIN_FAST_A > TV_LINES - 256) + (TV_LINES - 256) * (SPIN_FAST_A <= TV_LINES - 256)
.assert SPIN_FAST > 0 .and SPIN_FAST < RASTER_LINE, error, "spin_prep: soglia del raster"
LATE_GUARD = (TV_BUDGET - (3600)) / TV_LCYC          ; GUARDIAN dal muro intero (pad_sprite): circa 2.000 cicli

.proc frame_late
    lda #LATE_BIG
    bne frame_after
.endproc
.proc frame_late_hud
    lda #LATE_HUD
    bne frame_after
.endproc
.proc frame_late_small
    lda #LATE_SMALL
.endproc
; C = 1 se sono passate almeno A righe dall'interrupt. Un frame oltre il suo tempo trova il raster
; di nuovo alle righe dopo l'interrupt: lo distingue frame_flag, che l'interrupt della riga 250 ha
; rialzato (play_main lo azzera prima del frame), e allora è tardi, così un frame già sforato non
; accetta altro lavoro; sid_time fa lo stesso. Sull'NTSC, dove un frame di partita può sforare di
; poco, a qualsiasi riga; sul PAL, che non sfora mai, solo alle righe 250-311 (5 cicli in meno per
; chiamata: le scritte di HOW TO PLAY ne fanno tante, al limite del frame). frame_flag sempre dopo
; il raster: letto prima, l'interrupt poteva arrivare in mezzo (flag a 0, raster già a 250: presto).
; (Il banco di prova alza frame_flag dopo un frame intero, come l'interrupt.)
.proc frame_after
    sta late_lines
    lda $d011
    bmi early                   ; righe 256-311: appena dopo l'interrupt
    lda $d012
    cmp #RASTER_LINE
    bcs early                   ; righe 250-255
    clc
    adc #TV_LINES - RASTER_LINE ; righe 0-249: passate riga + 62 (NTSC 13)
    bcs late
    cmp late_lines
.ifdef NTSC
    bcs late
    lda frame_flag              ; di nuovo l'interrupt: il raster ha fatto il giro, tardi
    bne late
    clc
.endif
    rts
early:
    lda frame_flag
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
SP_SPIN0 = SP_PREP0 + 16        ; 8 immagini per lato
SPIN_CX  = 12
SPIN_CY  = 10

.ifndef ROTATED                 ; (campo girato: rot_video.s)
.proc spin_prep
    lda sp_k
    cmp #16
    jcs done
    ; le immagini della rotazione del lato di OMEGA no (OMEGA non ruota): al lato dopo
    and #8
    lsr a
    cmp nx_morph
    bne :+
    lda sp_k
    ora #7
    sta sp_k
    inc sp_k
    rts
:   ; frame già avanti (anche per un'immagine di racchetta): al prossimo. Quasi sempre lo dice già
    ; la riga del raster da sola (SPIN_FAST, senza frame_after)
    lda $d012
    cmp #SPIN_FAST
    bcc :+
    cmp #RASTER_LINE
    jcc done
:   lda #LATE_SPIN
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
.endif

.ifndef ROTATED                 ; (campo girato: niente rotazione del SUPER)
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
.endif

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

; NEXT: salto del TELEPORT, come next_ui.rs e il MiSTer. Con la palla in arrivo la racchetta si
; scompone a righe dove si trova mentre la palla va da metà campo a 32 pixel più in là, poi si
; ricompone a righe sul punto d'arrivo mentre la palla va da 96 a 64 pixel dal bordo del giocatore
; (warp_image). L'astronave che sparisce è nello sprite della racchetta, quella che compare nello
; sprite dell'icona del bonus; le righe vengono dall'immagine che la racchetta mostrava (wp_src).
WARP_STEP = 32
WARP_SUNK = (P_WIDTH >> 16) / 2
WARP_RISE = 3 * WARP_STEP
SP_WARP   = SP_RING0 + FX_SPRITES ; immagine del pezzo che esce
; Il salto si disegna dopo la scena, quando il frame è già oltre gli 8.000 cicli di frame_late (in
; NEXT a circa 10.000-12.500: con frame_late non si disegnava mai). Il salto (warp_fx con
; l'immagine) costa fino a WARP_COST cicli veri, con la prima immagine di una fase tutta da fare
; (warp_image: dal 2026-11-23 fino a circa 2.050 cicli la prima, in media circa 560 le altre, che
; rifanno solo le righe cambiate; le due fasi non si sovrappongono), e si fa se dopo resta il tempo
; per le riserve; se no resta l'immagine di prima. (La soglia è rimasta quella di prima.)
WARP_COST = 3000
WARP_LATE = (TV_BUDGET - (WARP_COST + 200)) / TV_LCYC

; Il salto rimasto da disegnare nel frame prima (wp_pend, frame già avanti): all'inizio di questo,
; che ha il tempo, sullo stato del tick prima (poi compute_sprites rimette sprite e posizioni). Solo
; con il salto in corso: events è ancora quello del tick prima, non deve farne partire un altro.
.ifndef ROTATED                 ; (campo girato: rot_video.s)
.proc warp_early
    lda wp_pend
    beq done
    ; chi salta (e riceve la palla) rifà in questo tick la previsione del TELEPORT, o quella della
    ; CPU (senza quella tenuta da parte: circa 900-1.500 cicli l'una): con il disegno del salto il
    ; frame andava oltre il budget. Il disegno aspetta il frame dopo
    lda wp_side
    asl a
    asl a
    tax
    lda tp_ok,x
    beq done
    cpx cpu_side
    bne :+
    lda cpu_ok,x
    beq done
:
    lda #0
    sta wp_pend
    lda wp_on
    beq done
    jmp warp_fx
done:
    rts
.endproc

.proc warp_fx
    ; inizio: evento del TELEPORT (salta chi riceve la palla)
    lda wp_on
    bne running
    lda events
    and #EV_TELEPORT
    jeq remember
    ldx #0
    lda ball_vx+3
    sta wp_dir                  ; (il verso della palla: verso chi salta)
    bmi :+
    inx
:   stx wp_side
    lda pd_last,x
    sta wp_from
    lda sh_ptr+SPN_PAD,x        ; immagine della racchetta, da cui vengono le righe del salto: se
    cmp pad_slot,x              ; è quella rifatta, il muro intero del GUARDIAN o nessuna (la
    bne :+                      ; racchetta sparisce e ricompare)
    lda pd_full,x
:   sta wp_src
    lda #$ff                    ; nessuna immagine ancora fatta
    sta wp_ls
    sta wp_lo
    lda #1
    sta wp_on
    lda #0                      ; nessun pezzo finché non c'è un'immagine di questo salto
    sta wp_en
    sta wp_ex
running:
    ; fine: colpo, punto, o racchetta tutta fuori (palla a 64 pixel dal bordo); anche con la palla
    ; che si allontana o ferma per la battuta, se il frame dell'evento ha tenuto gli sprite di prima
    ; (warp_fx non c'era: la racchetta restava affondata, con il portale)
    lda events
    and #EV_HIT | EV_BOOST | EV_SCORE
    bne stop
    lda serve_timer
    ora serve_timer+1
    bne stop
    lda ball_vx+3
    eor wp_dir
    bmi stop
    jsr warp_d                  ; A = distanza della palla dal bordo di chi salta
    cmp #WARP_RISE - WARP_STEP + 1
    bcs going
stop:
    lda #0
    sta wp_on
    ldx wp_side
    lda #$ff                    ; l'immagine della racchetta si rifà (con le immagini preparate
    sta pd_n,x                  ; torna subito una di quelle)
    lda pd_full,x               ; GUARDIAN con dei settori persi: nello sprite dinamico c'è il
    beq :+                      ; pezzo del salto, intanto il muro intero (pad_sprite)
    sta sh_ptr+SPN_PAD,x
:   jmp remember
going:
    sta wp_d
    lda #WARP_LATE              ; frame già avanti: resta l'immagine di prima, e il disegno si fa
    jsr frame_after             ; all'inizio del frame dopo (warp_early)
    bcc :+
    inc wp_pend
    jmp place
:
    ; avanzamento: pixel affondati e usciti (0-32), clamp(fase - wp_d, 0, WARP_STEP); qui wp_d >
    ; WARP_RISE - WARP_STEP, quindi l'uscita non arriva a WARP_STEP
    lda #WARP_SUNK
    sec
    sbc wp_d
    bcs :+
    lda #0
:   cmp #WARP_STEP
    bcc :+
    lda #WARP_STEP
:   sta wp_sunk
    lda #WARP_RISE
    sec
    sbc wp_d
    bcs :+
    lda #0
:   sta wp_out
    ; righe in cima delle due astronavi: quella che sparisce dove era, quella che compare dove è
    lda wp_side
    asl a
    asl a
    tax
    lda pad_h+2,x
    lsr a
    sta m_lo                    ; metà altezza
    ldx wp_side
    lda wp_from
    sec
    sbc m_lo
    sta wp_en_top
    lda pd_cy,x
    sec
    sbc m_lo
    sta wp_ex_top
    ; le immagini si rifanno solo quando cambiano l'avanzamento o il verso del tremolio (wp_tb: lo
    ; legge anche l'arrivo, dopo warp_image): le due fasi non si sovrappongono, quindi quasi sempre
    ; se ne rifà una sola
    lda tick
    lsr a
    lsr a
    and #1
    sta wp_tb
    lda wp_sunk
    asl a
    ora wp_tb
    cmp wp_ls
    beq arrival
    ldy wp_ls
    sty wp_prev
    sta wp_ls
    ; partenza nell'immagine dinamica della racchetta
    lda img_base,x
    clc
    adc #<sh_img
    sta ptr
    lda #>sh_img
    adc #0
    sta ptr+1
    lda wp_sunk
    ldx #0
    jsr warp_image
    ldx wp_side
    lda pd_dirty,x              ; apply_shadows copia solo le righe rifatte (2, wp_rows), se non
    bne :+                      ; c'è già da copiare tutta l'immagine (1)
    lda #2
    sta pd_dirty,x
:   lda #1
    sta wp_en
    lda #$ff
    sta pd_n,x
arrival:
    ; l'astronave d'arrivo si disegna solo quando comincia a comparire
    lda wp_out
    bne :+
    sta wp_ex
    jmp place
:   asl a
    ora wp_tb
    cmp wp_lo
    beq place
    ldy wp_lo
    sty wp_prev
    sta wp_lo
    ; arrivo nell'immagine di SP_WARP
    lda #<(SP_WARP * 64 + $C000)
    sta ptr
    lda #>(SP_WARP * 64 + $C000)
    sta ptr+1
    lda wp_out
    ldx #1
    jsr warp_image
    lda #1
    sta wp_ex
place:
    ; sprite: il pezzo che affonda nella racchetta (immagine dinamica), quello che esce nell'icona,
    ; tutti e due nel colore dedicato di chi salta (m_t; om_white lascia Y)
    ldy wp_side
    tya
    asl a
    asl a
    tax
    jsr om_white
    sta m_t
    lda wp_en
    beq :+
    lda bit_of+SPN_PAD,y
    ora sh_enable
    sta sh_enable
    lda pad_slot,y
    sta sh_ptr+SPN_PAD,y
    lda wp_en_top
    clc
    adc #SPR_Y0
    sta sh_y+SPN_PAD,y
    lda m_t
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
    lda m_t
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

; A = distanza in pixel della palla dal bordo di chi salta, accelerata verso la metà campo quando
; la racchetta è in dash (2x a x >= 48, 4x a x >= 96 come sul MiSTer) così l'animazione del
; TELEPORT si completa sempre prima che la palla arrivi alla racchetta. Da WARP_SUNK in su (non ha
; ancora passato la metà campo) $FF: per warp_fx ogni valore da lì in su dà lo stesso salto.
.proc warp_d
    ldy wp_side
    bne right
    lda ball_x+3                ; sinistra: x
    bne far
    lda ball_x+2
    cmp #WARP_SUNK
    bcs far
    sta m_lo                    ; d grezzo (0..159)
    lda pad_x+2                 ; distanza della racchetta dal suo bordo (8 bit bastano: 20..110)
    jmp scale
right:
    lda #<(P_WIDTH >> 16)       ; destra: 320 - x
    sec
    sbc ball_x+2
    tay
    lda #>(P_WIDTH >> 16)
    sbc ball_x+3
    bne far
    tya
    cmp #WARP_SUNK
    bcs far
    sta m_lo
    lda #<(P_WIDTH >> 16)
    sec
    sbc pad_x+4+2
scale:
    cmp #48
    bcc no_scale
    tax
    lda #WARP_SUNK
    sec
    sbc m_lo
    sta m_t                     ; distanza percorsa oltre la metà campo (1..160)
    asl m_t                     ; dash normale: 2x
    bcs sat
    cpx #96
    bcc scale_done
    asl m_t                     ; dash lungo (RUSH): 4x
    bcs sat
scale_done:
    lda m_t
    cmp #WARP_SUNK
    bcc :+
sat:
    lda #WARP_SUNK
    sta m_t
:   lda #WARP_SUNK
    sec
    sbc m_t
    rts
no_scale:
    lda m_lo
    rts
far:
    lda #$ff
    rts
.endproc
.assert WARP_SUNK < $ff, error, "warp_d: $FF oltre la metà campo"

; Un'astronave del salto in (ptr), dalle righe dell'immagine wp_src (sprite in $C000 + 64 * wp_src,
; 0 nessuna: vuota): ogni riga dello sprite (due dello schermo) piena, in luce o vuota secondo la
; sua soglia (wp_th) e l'avanzamento A (0-32), come scan_row di paddle_ui.rs. Alla partenza (X = 0)
; la riga è piena finché l'avanzamento non arriva alla soglia, poi in luce per 8 passi, poi vuota;
; all'arrivo (X = 1) il contrario, con le soglie rovesciate. In luce: i pixel accesi nel colore del
; personaggio (%10), spostati di un pixel doppio a sinistra o a destra, a righe e a tempi alterni.
;
; Si rifanno solo le righe cambiate dall'immagine di prima (wp_prev: la sua chiave, avanzamento * 2
; + tremolio; $FF nessuna, tutte): le soglie sono 8 (WP_TH, una per classe (riga * 5) & 7, crescenti
; con la classe), quindi le classi sotto wp_n1 sono vuote, quelle da wp_n1 a wp_n2 - 1 in luce, le
; altre piene, alla partenza come all'arrivo; i confini di prima restano in wp_o1 e wp_o2 (per
; immagine). Si ridisegnano le classi tra un confine di prima e quello di adesso (hanno cambiato
; stato) e, se è cambiato il tremolio, quelle in luce: ogni classe al più una volta. Chi scrive in
; sh_img (pad_prep) rimette wp_ls a $FF. Le classi rifatte si aggiungono a wp_rows (un bit per
; classe, tutte senza immagine): alla partenza apply_shadows copia solo quelle.
; Le righe stanno in wp_ord in ordine di classe: un tratto di classi è un tratto della lista, che
; wp_span scorre in tre cicli (vuote, in luce, piene) senza chiamate per riga.
; Temporanee di wp_span in pagina zero (definite prima dell'uso: ca65 sceglie lì l'indirizzamento),
; nessuna chiamata dentro
wp_stop = m_sign                ; fine delle righe nella lista
wp_lim  = m_t                   ; fine del ciclo di adesso
wp_i    = m_lo                  ; riga nella lista (le righe in luce usano X)
.proc warp_image
    sta wp_lvl
    stx wp_arr
    lda wp_src                  ; (ptr2) = $C000 + 64 * wp_src
    lsr a
    lsr a
    ora #$C0
    sta ptr2+1
    lda wp_src                  ; byte basso: (wp_src & 3) << 6
    lsr a
    ror a
    ror a
    and #$C0
    sta ptr2
    lda wp_src
    bne :++
    tay                         ; nessuna immagine: tutto vuoto
:   sta (ptr),y
    iny
    cpy #IMG_BYTES
    bne :-
    lda #$ff
    sta wp_rows
    rts
:   ; confini di adesso, come posti nella lista wp_ord: partenza soglie <= avanzamento - 8 e
    ; <= avanzamento, arrivo soglie < 22 - avanzamento e < 30 - avanzamento (wp_nle_pos)
    ldy wp_lvl
    lda wp_arr
    bne arrive
    lda wp_nle_pos + 3,y
    sta wp_n1
    lda wp_nle_pos + 11,y
    jmp bounds
arrive:
    lda #32
    sec
    sbc wp_lvl
    tay
    lda wp_nle_pos,y
    sta wp_n1
    lda wp_nle_pos + 8,y
bounds:
    sta wp_n2
    ; tremolio di adesso (bit 0 del verso delle righe pari) e cambiato da prima
    lda tick
    lsr a
    lsr a
    sta wp_ph
    ldy wp_arr
    ldx wp_prev
    inx
    bne :+
    lda #0                      ; nessuna immagine di prima: tutte le righe
    ldx #PAD_ROWS
    jsr wp_span
    jmp save
:   eor wp_prev
    and #1
    beq steady
    ; tremolio cambiato: tutte quelle in luce, più quelle che hanno cambiato stato, cioè dal più
    ; basso dei confini delle vuote al più alto di quelli delle piene, una volta sola
    lda wp_o2,y
    cmp wp_n2
    bcs :+
    lda wp_n2
:   tax
    lda wp_o1,y
    cmp wp_n1
    bcc :+
    lda wp_n1
:   jsr wp_span
    jmp save
steady:
    lda wp_o1,y                 ; le classi passate da in luce a vuote (o il contrario)
    ldx wp_n1
    cmp wp_n1
    bne :+
    stx wp_end                  ; (confine fermo: nessuna, wp_end come dopo wp_between)
    beq :++
:   jsr wp_between
:   ldy wp_arr                  ; e da piene a in luce, da dove è arrivato il giro di prima
    lda wp_o2,y                 ; (wp_end: con un salto lungo i due tratti si sovrappongono)
    ldx wp_n2
    cmp wp_n2
    bcc :+
    tax
    lda wp_n2
:   cmp wp_end
    bcs :+
    lda wp_end
:   stx wp_end                  ; (tratto vuoto: niente da fare)
    cmp wp_end
    bcs save
    jsr wp_span
save:
    ldy wp_arr
    lda wp_n1
    sta wp_o1,y
    lda wp_n2
    sta wp_o2,y
    rts
.endproc

; Ridisegna le righe tra i posti A e X della lista wp_ord (confini di classe), in un ordine o
; nell'altro (wp_between), o da A a X - 1 (wp_span), nello stato di adesso: sotto wp_n1 vuote,
; sotto wp_n2 in luce, le altre piene.
.proc wp_between
    stx wp_end
    cmp wp_end
    bcc wp_span
    tay                         ; A >= X: da X a A - 1
    txa
    sty wp_end
    ldx wp_end
.endproc
.proc wp_span
    sta wp_k
    stx wp_end
    cmp wp_end
    jcs done                    ; (nessuna riga)
    stx wp_stop
    lda wp_lomask,x             ; classi rifatte (apply_shadows): i bit delle classi da A a X - 1
    ldx wp_k
    eor wp_lomask,x
    ora wp_rows
    sta wp_rows
    ; vuote: le righe delle classi sotto wp_n1
    lda wp_n1
    cmp wp_stop
    bcc :+
    lda wp_stop
:   sta wp_lim
    cpx wp_lim
    bcs light
    lda #0
empty:
    ldy wp_ord,x
    sta (ptr),y
    iny
    sta (ptr),y
    iny
    sta (ptr),y
    inx
    cpx wp_lim
    bcc empty
light:
    ; in luce: le righe delle classi sotto wp_n2. I pixel accesi (doppi) nel colore del
    ; personaggio, spostati di un pixel doppio: g(b) = ((b | b >> 1) & %01010101) << 1 per byte e
    ; i 24 bit della riga << 2 o >> 2. g lavora a coppie di bit, quindi va d'accordo con gli
    ; spostamenti di 2 bit: g(b) << 2 = g(b & $3F) << 2, g(b) >> 2 = g(b >> 2); dal byte
    ; accanto entra un solo bit, la coppia alta (b >= $40) a sinistra, la bassa (b & 3) a destra.
    ; wp_g ha g(c) << 1 per c < 64 (bit 6, 4, 2: il bit 0 e il 7 liberi per quel bit)
    lda wp_n2
    cmp wp_stop
    bcc :+
    lda wp_stop
:   sta wp_lim
    cpx wp_lim
    bcs full
lrow:
    stx wp_i
    ldy wp_ord,x
    tya                         ; verso: riga (pari come il suo primo byte, 3 * riga) e tempo
    eor wp_ph                   ; (6 volte al secondo)
    lsr a
    bcs right
    ; verso sinistra, dal byte 2: (wp_g(b & $3F) | coppia alta del byte dopo) << 1
    iny
    iny
    lda (ptr2),y
    and #$3F
    tax
    lda wp_g,x
    asl a
    sta (ptr),y
    lda (ptr2),y
    cmp #$40                    ; C = coppia alta accesa
    dey
    lda (ptr2),y
    and #$3F
    tax
    lda wp_g,x
    adc #0                      ; (bit 0 libero: | C)
    asl a
    sta (ptr),y
    lda (ptr2),y
    cmp #$40
    dey
    lda (ptr2),y
    and #$3F
    tax
    lda wp_g,x
    adc #0
    asl a
    sta (ptr),y
    jmp lnext
right:
    ; verso destra: wp_g(b >> 2) con la coppia bassa del byte prima nel bit 7 (ror; bit 0 a 0)
    lda (ptr2),y
    lsr a
    lsr a
    tax
    lda wp_g,x
    lsr a
    sta (ptr),y
    iny
    lda (ptr2),y
    lsr a
    lsr a
    tax
    dey
    lda (ptr2),y
    and #3
    cmp #1                      ; C = coppia bassa accesa
    lda wp_g,x
    ror a
    iny
    sta (ptr),y
    iny
    lda (ptr2),y
    lsr a
    lsr a
    tax
    dey
    lda (ptr2),y
    and #3
    cmp #1
    lda wp_g,x
    ror a
    iny
    sta (ptr),y
lnext:
    ldx wp_i
    inx
    cpx wp_lim
    bcc lrow
full:
    ; piene: le righe dell'immagine
    cpx wp_stop
    bcs done
frow:
    ldy wp_ord,x
    lda (ptr2),y
    sta (ptr),y
    iny
    lda (ptr2),y
    sta (ptr),y
    iny
    lda (ptr2),y
    sta (ptr),y
    inx
    cpx wp_stop
    bcc frow
done:
    rts
.endproc

; soglia della classe k (WP_TH: (k * 11) / 4, da 0 a 19, crescente); la riga r ha la classe
; (r * 5) & 7, cioè la classe k ha le righe (k * 5) & 7, + 8, + 16 (le classi con (k * 5) & 7 > 4,
; cioè 1, 3 e 6, ne hanno due). wp_ord: il primo byte delle righe in ordine di classe; la classe k
; comincia al posto WP_CLS(k) = 3k - (k > 1) - (k > 3) - (k > 6) (WP_CLS(8) = 21).
; wp_nle_pos: il posto della prima classe con la soglia > i - 11 (cioè WP_CLS del numero di
; soglie <= i - 11), per i da 0 a 43: avanzamento da 0 a 32 e i quattro confini di warp_image;
; wp_lomask: per il posto p, (1 << classi prima di p) - 1; wp_ylast: primo byte dell'ultima
; riga della classe (apply_shadows); wp_g: le righe in luce (wp_span)
wp_nle_pos:
.repeat 44, I
WP_N .set ((I - 11) >= 0) + ((I - 11) >= 2) + ((I - 11) >= 5) + ((I - 11) >= 8) + ((I - 11) >= 11) + ((I - 11) >= 13) + ((I - 11) >= 16) + ((I - 11) >= 19)
    .byte 3 * WP_N - (WP_N > 1) - (WP_N > 3) - (WP_N > 6)
.endrepeat
wp_lomask:
.repeat PAD_ROWS + 1, P
WP_N .set 0
  .repeat 8, K
WP_C .set K + 1
    .if 3 * WP_C - (WP_C > 1) - (WP_C > 3) - (WP_C > 6) <= P
WP_N .set WP_N + 1
    .endif
  .endrepeat
    .byte (1 << WP_N) - 1
.endrepeat
wp_ylast:
.repeat 8, K
    .byte 3 * (((K * 5) & 7) + 8 + 8 * (((K * 5) & 7) + 16 < PAD_ROWS))
.endrepeat
wp_ord:
.repeat 8, K
  .repeat 3, J
    .if ((K * 5) & 7) + 8 * J < PAD_ROWS
    .byte 3 * (((K * 5) & 7) + 8 * J)
    .endif
  .endrepeat
WP_C .set K + 1
  .assert wp_ord + 3 * WP_C - (WP_C > 1) - (WP_C > 3) - (WP_C > 6) = *, error, "salto del TELEPORT: WP_CLS diverso dalle righe delle classi"
.endrepeat
wp_g:
.repeat 64, C
    .byte ((C | (C >> 1)) & $15) << 2
.endrepeat
.repeat 8, K
    .assert (K * 11) >> 2 = (K >= 1) * 2 + (K >= 2) * 3 + (K >= 3) * 3 + (K >= 4) * 3 + (K >= 5) * 2 + (K >= 6) * 3 + (K >= 7) * 3, error, "soglie del salto del TELEPORT diverse da wp_nle_pos"
.endrepeat
.assert PAD_ROWS = 21, error, "salto del TELEPORT: tre righe per classe fino alla 20"

pad_slot: .byte SP_PAD0, SP_PAD1

.endif
.segment "BSS"
wp_on:     .res 1
wp_pend:   .res 1               ; disegno del salto rimasto dal frame prima (warp_early)
wp_dir:    .res 1               ; bit 7: il verso della palla all'inizio del salto
wp_side:   .res 1
wp_from:   .res 1               ; riga del centro della racchetta prima del salto
wp_d:      .res 1
wp_sunk:   .res 1
wp_out:    .res 1
wp_en:     .res 1
wp_ex:     .res 1
wp_src:    .res 1               ; sprite dell'immagine della racchetta all'inizio del salto (0 nessuna)
wp_ls:     .res 1               ; avanzamento * 2 + tremolio delle immagini fatte ($ff nessuna):
wp_lo:     .res 1               ; partenza e arrivo
.segment "ZEROPAGE"
wp_lvl:    .res 1               ; warp_image: avanzamento
.segment "BSS"
.segment "ZEROPAGE"
wp_arr:    .res 1               ; warp_image: 1 all'arrivo
.segment "BSS"
wp_o1:     .res 2               ; warp_image: confini delle classi vuote e in luce (posti in wp_ord)
wp_o2:     .res 2               ; nelle immagini fatte (partenza e arrivo)
wp_rows:   .res 1               ; classi rifatte dall'ultima copia nella RAM degli sprite (apply_shadows)
; temporanee di warp_image, nelle variabili del disegno della coda (trail_end viene dopo)
wp_prev = tr_r0                 ; chiave dell'immagine di prima ($ff nessuna)
wp_n1   = tr_lm                 ; confini di adesso
wp_n2   = tr_rm
wp_k    = tr_k
wp_end  = tr_n                  ; wp_span: prima classe esclusa
wp_ph   = tr_br                 ; tick / 4
wp_tb   = tr_bl                 ; warp_fx: tremolio (bit 1 di tick)
wp_en_top: .res 1
wp_ex_top: .res 1
pd_cy:     .res 2               ; riga del centro delle racchette in questo frame
pd_last:   .res 2               ; e al frame prima
.segment "CODE"

.ifdef ROTATED
.include "rot_video.s"
.endif
