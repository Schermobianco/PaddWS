; Campo girato (build -Rotated, simbolo ROTATED): sprite della partita, interrupt della mezzeria,
; campo e punteggi. Prende il posto delle routine di video.s con lo stesso nome (lì sotto
; .ifndef ROTATED).
;
; Il campo del core (Tuning::c64_rotated) è largo 200 (x, da una porta all'altra) e alto 240 (y,
; lungo le racchette). A schermo la x diventa la riga e la y la colonna: colonna = y, riga = 200 - x
; (le formule di oggi con x e y scambiate e P_WIDTH al posto di P_HEIGHT). Il giocatore sinistro
; (lato 0) sta in basso con la faccia in alto, il destro (lato 1) in alto. Colonne 0-29 il campo,
; 30 il muro, 31-39 la fascia dell'HUD.
;
; Sprite in partita: 0 la palla (sopra tutto, con coda, cometa e alone come oggi), 1 l'icona del
; bonus armato o la banda EVO, 2-3 il bianco hires delle astronavi (sinistro, destro), 4-5 il
; multicolore (%01 grigio chiaro come oggi, %10 colore del tipo, %11 grigio scuro: $D026 in partita,
; bianco fuori come oggi), 6-7 le capsule. Gli sprite
; 1-5 servono a tutte e due le metà: i registri ombra sh_* sono quelli della metà in alto (il VIC
; li prende nel vblank, apply_shadows), shb_* quelli della metà in basso, che l'interrupt della
; mezzeria (riga SPLIT_LINE) scrive nel VIC con i valori fissati in apply_shadows (negli operandi
; del codice dell'interrupt stesso). Uno sprite della metà in alto deve finire prima della riga
; 100 dello schermo, uno di quella in basso cominciare dopo: racchette, icone e bande ci stanno
; sempre; le capsule hanno 6 e 7, che non cambiano, e lo sprite 1 di una metà se è libero e la
; capsula ci sta tutta.

SPN_ICON_R = 1                  ; icona del bonus armato o banda EVO (per metà)
SPN_HI     = 2                  ; 2 e 3: bianco hires delle astronavi (per metà)
SPN_MC     = 4                  ; 4 e 5: multicolore
SPN_CAP_R  = 6                  ; 6 e 7: capsule
SPLIT_LINE = SPR_Y0 + 100       ; interrupt della mezzeria: la riga 100 dello schermo
ROT_PAGES  = $E100              ; pose delle astronavi: lato 0 da $E100, lato 1 da $E500 (4 pagine)
ROT_PTR0   = (ROT_PAGES - $C000) / 64
ROT_W       = P_WIDTH >> 16      ; 200: righe del campo
ICON_GAP   = 3                  ; pixel tra la faccia (più la sporgenza) e l'icona
.assert ROT_W = 200 .and (P_HEIGHT >> 16) = 240, error, "campo girato: 200 x 240"
.assert sh_y = sh_x + 8 .and sh_ptr = sh_x + 16 .and sh_col = sh_x + 24, error, "registri ombra di seguito"

; registri ombra della metà in basso (indice = sprite, solo 1-5), nella memoria delle immagini
; dinamiche delle racchette (sh_img), che in partita il campo girato non usa
shb_x    = sh_img
shb_y    = sh_img + 8
shb_ptr  = sh_img + 16
shb_col  = sh_img + 24
shb_msb  = sh_img + 32          ; bit 1-5
shb_en   = sh_img + 33
rot_msb  = sh_img + 34
sh_pri   = sh_img + 35          ; priorità degli sprite ($D01B) in alto e in basso (salto del TELEPORT)
shb_pri  = sh_img + 36
.assert 2 * IMG_BYTES >= 35, error, "registri della metà in basso in sh_img"

; ------------------------------------------------------------------------------------ interrupt

; Interrupt del raster: alla riga RASTER_LINE il frame (come oggi), alla riga SPLIT_LINE la
; mezzeria. Si distinguono dalla riga (un interrupt rimandato da un sei arriva più tardi: quella
; del frame può essere già oltre la 255).
.proc irq_handler
    pha
    ; la mezzeria solo in partita (dal conto alla rovescia al GAME OVER) con lo split acceso: chi
    ; esce dalla partita senza apply_shadows (il finale) lo lascia acceso
    lda state
    cmp #ST_COUNT
    bcc closed
    cmp #ST_OVER + 1
    bcs closed
irq_gate:
    jmp closed                  ; (apply_shadows: jmp fuori dalla partita, bit in partita)
    lda $d011
    bmi on_frame
    lda $d012
    cmp #RASTER_LINE - 30
    bcc mid
on_frame:
    lda #SPLIT_LINE             ; in partita: poi la mezzeria
    sta $d012
plain:
    inc frame_flag
    inc frame_count
    bne :+
    inc frame_count+1
:   lda #$ff
    sta $d019
    pla
    rti
closed:
    ; fuori dalla partita come oggi: il frame e basta, la riga la decide chi ha chiamato (gli split
    ; della scelta e del VS saltano qui nel vblank dopo aver messo la loro). Sopra la riga del
    ; frame può arrivare solo una mezzeria rimasta: di nuovo la riga del frame, nessun frame
    lda $d011
    bmi plain
    lda $d012
    cmp #RASTER_LINE - 30
    bcs plain
    lda #RASTER_LINE
    sta $d012
    lda #$ff
    sta $d019
    pla
    rti
mid:
    ; mezzeria: gli sprite 1-5 della metà in basso, poi l'interrupt del frame
irq_block:                      ; per sprite 4 coppie lda #/sta da 5 byte: x, y, colore, puntatore
    .repeat 5, i
    lda #0
    sta $d002 + 2 * i
    lda #0
    sta $d003 + 2 * i
    lda #0
    sta $d028 + i
    lda #0
    sta SPR_PTR + 1 + i
    .endrepeat
    lda #0                      ; nono bit
    sta $d010
    lda #0                      ; sprite accesi
    sta $d015
    lda #0                      ; priorità (sprite dietro i caratteri)
    sta $d01b
done:
    lda #RASTER_LINE
    sta $d012
    lda #$ff
    sta $d019
    pla
    rti
.endproc
IRQ_OP = irq_handler::irq_block + 1     ; operando del primo lda #
.assert irq_handler::done - irq_handler::irq_block = 115, error, "interrupt della mezzeria: 23 coppie da 5 byte"

; Registri ombra nel VIC (nel vblank, come oggi), poi i valori della metà in basso negli operandi
; dell'interrupt della mezzeria: solo in partita con lo schermo di testo.
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
    ; bordo e sfondo solo quando cambiano (il "grey dot", vedi video.s)
    lda sh_bg
    eor $d021
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
:   ldx sh_mode
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
    ; anteprima della scelta della racchetta (pick_preview, come oggi): l'immagine in sh_img negli
    ; sprite 2 e 3 (le partite senza tipo ci rimettono la barra: bar_sprites)
    lda pd_dirty
    ora pd_dirty+1
    beq copied
    bit $fffb                   ; con la voce di CHALLENGE l'I/O resta acceso: la copia aspetta
    bmi copied
    sei
    lda #$34
    sta $01
    lda pd_dirty
    beq :++
    ldx #IMG_BYTES - 1
:   lda sh_img,x
    sta $C000 + SP_PAD0 * 64,x
    dex
    bpl :-
:   lda pd_dirty+1
    beq :++
    ldx #IMG_BYTES - 1
:   lda sh_img + IMG_BYTES,x
    sta $C000 + SP_PAD1 * 64,x
    dex
    bpl :-
:   lda #$35
    sta $01
    cli
    lda #0
    sta pd_dirty
    sta pd_dirty+1
copied:
    ; la metà in basso
    ldx state
    cpx #ST_COUNT
    jcc off
    cpx #ST_OVER + 1
    jcs off
    lda sh_mode
    jne off
    .repeat 5, i
    lda shb_x+1+i
    sta IRQ_OP + 20 * i
    lda shb_y+1+i
    sta IRQ_OP + 20 * i + 5
    lda shb_col+1+i
    sta IRQ_OP + 20 * i + 10
    lda shb_ptr+1+i
    sta IRQ_OP + 20 * i + 15
    .endrepeat
    lda sh_msb
    and #%11000001
    ora shb_msb
    sta IRQ_OP + 100
    lda sh_enable
    and #%11000001
    ora shb_en
    sta IRQ_OP + 105
    lda sh_pri                  ; (solo in partita: la presentazione di CHALLENGE usa $D01B)
    sta $d01b
    lda shb_pri
    sta IRQ_OP + 110
    ldx #COL_DGRAY              ; %11 delle astronavi: grigio scuro
    lda #$2c                    ; bit: si scrive
    bne gate
off:
    lda irq_handler::irq_gate   ; usciti dalla partita: l'interrupt di nuovo alla riga del frame
    cmp #$2c
    bne :+
    lda #RASTER_LINE
    sta $d012
:   ldx #COL_WHITE              ; %11 come oggi: il bianco delle racchette delle altre schermate
    lda ship_dgray              ; (con un'astronave della girata il grigio scuro, finché ci sono
    beq :+                      ; sprite accesi)
    lda sh_enable
    sta ship_dgray
    beq :+
    ldx #COL_DGRAY
:   lda ship_bands              ; bande EVO prese dalle astronavi: una al frame nel titolo e nel
    beq :+                      ; menu, prima di ogni partita EVO
    lda state
    cmp #ST_TITLE
    beq band
    cmp #ST_MENU
    bne :+
band:
    stx ship_t
    jsr band_step
    ldx ship_t
:
    lda #$4c                    ; jmp: l'interrupt è quello di oggi
gate:
    sta irq_handler::irq_gate
    txa                         ; (solo quando cambia: siamo nel bordo, ma come per $D020)
    eor $d026
    and #$0f
    beq :+
    stx $d026
:   rts
.endproc

; ------------------------------------------------------------------------------------ sprite

.proc game_sprites
    lda #COL_WHITE
    sta sh_col
    .repeat 2, i
    sta sh_col+SPN_HI+i
    sta shb_col+SPN_HI+i
    .endrepeat
    lda #%11 << SPN_MC
    sta sh_mc
    lda #0
    sta sh_yexp
    sta sh_xexp
    lda #SP_BALL4
    sta sh_ptr
    lda #MODE_TEXT
    sta sh_mode
    rts                         ; (A = 0: compute_sprites)
.endproc
.assert MODE_TEXT = 0, error, "game_sprites: A = 0 all'uscita"

.proc compute_sprites
    lda #0
    sta pd_made
    jsr game_sprites            ; (A = MODE_TEXT = 0)
    sta sh_enable
    sta sh_msb
    sta shb_en
    sta shb_msb
    sta sh_pri
    sta shb_pri
    ; nel lampo del punto tutto lo schermo è bianco
    lda sh_bg
    beq :+
    rts
:   ; palla, salvo i lampi durante l'attesa della battuta (come oggi)
    lda serve_timer+1
    ora serve_timer+2
    ora serve_timer+3
    bne ball_on
    lda serve_timer
    cmp #P_SERVE_TICKS + 1
    bcs ball_on
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
    ; colonna: byte 2 e 3 di y - r + HALF_PX - 1
    sec
    lda ball_y
    sbc ball_r
    tax
    lda ball_y+1
    sbc ball_r+1
    tay
    lda ball_y+2
    sbc ball_r+2
    sta m_lo
    lda ball_y+3
    sbc ball_r+3
    sta m_t
    cpx #1                      ; C = riporto di y0 + $FF
    tya
    adc #>(HALF_PX - 1)
    lda m_lo
    adc #SPR_X0
    sta sh_x
    lda m_t
    adc #0
    and #1
    sta sh_msb
    ; riga: byte 2 di P_WIDTH - HALF_PX - (x + r)
    clc
    lda ball_x
    adc ball_r
    sta m_lo
    lda ball_x+1
    adc ball_r+1
    sta m_t
    lda ball_x+2
    adc ball_r+2
    sta t1+2
    lda #<(P_WIDTH - HALF_PX)
    cmp m_lo
    lda #>(P_WIDTH - HALF_PX)
    sbc m_t
    lda #^(P_WIDTH - HALF_PX)
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
    jsr warp_fx                 ; salto del TELEPORT (NEXT): quale immagine, prima delle racchette
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
    jsr next_sprites
    jsr warp_place              ; (dopo le icone: la maschera del salto del TELEPORT)
    rts
:   rts
.endproc

; I registri della metà in esame si scrivono con l'indice rot_hb: 0 quelli della metà in alto
; (sh_*), ROT_HB quelli della metà in basso (shb_*, la stessa disposizione più in là).
ROT_HB = shb_x - sh_x
rot_hb = pi_half                ; (pagina zero di pad_image, che il campo girato non ha)
.assert ROT_HB > 0 .and ROT_HB + 32 < 256, error, "registri delle due metà entro una pagina"
.assert shb_y = shb_x + 8 .and shb_ptr = shb_x + 16 .and shb_col = shb_x + 24, error, "registri della metà in basso come quelli in alto"
hb_of:  .byte ROT_HB, 0         ; per lato: 0 in basso, 1 in alto

; Prima colonna di un tratto lungo le racchette dal centro t0 (y, Q16.16) e dalla metà in A:X:Y
; (byte 2, 1, 0; anche in t2): byte 2 e 3 di y - metà + HALF_PX - 1 in m_lo (colonna) e m_t
; (byte alto, $FF se negativa). Un pixel è acceso se il suo centro cade nel tratto. Solo per la
; banda EVO: la racchetta fa il conto in linea.
.proc first_col
    sta t2+2
    stx t2+1
    sty t2
    sec
    lda t0
    sbc t2
    tax
    lda t0+1
    sbc t2+1
    tay
    lda t0+2
    sbc t2+2
    sta m_lo
    lda t0+3
    sbc #0
    sta m_t
    cpx #1                      ; C = riporto del byte 0 + $FF
    tya
    adc #>(HALF_PX - 1)
    lda m_lo
    adc #0
    sta m_lo
    lda m_t
    adc #0
    sta m_t
    rts
.endproc

; Racchetta X (0 o 4) del lato Y (0 in basso, 1 in alto): gli sprite 2-5 (e 1 con la banda EVO)
; nei registri della sua metà. X = side alla fine.
.proc pad_sprite
    stx side
    sty pi_side
    lda hb_of,y
    sta rot_hb
    ; riga della faccia: in basso W - x - metà larghezza, in alto W - x + metà larghezza - 1 (la x
    ; è intera); lo scatto scivola come oggi (slide_x)
    lda face_k,y
    sec
    sbc pad_x+2,x
    sta t0+2
    lda #0
    sta t0+3
    lda t0+2
    cmp pd_draw_lo,y
    bne slide
    lda pd_draw_hi,y
    bne slide
    lda pd_snap,y
    beq slid
slide:
    jsr slide_x
slid:
    ; colpo di una mossa (sm_kick): la racchetta rincula verso il fondo di sm_kick / 4 pixel
    lda pd_draw_lo,y
    sta v_row
    lda sm_kick,x
    beq kicked
    dec sm_kick,x
    lsr a
    lsr a
    cpy #0
    bne kick_up
    clc
    adc v_row                   ; in basso: più giù
    sta v_row
    bcc kicked
kick_up:
    eor #$ff                    ; in alto: più su
    sec
    adc v_row
    sta v_row
kicked:
    ; tipo (K_NONE fuori da NEXT)
    lda #K_NONE
    ldx m_next
    beq :+
    ldx side
    lda nx_kind,x
:   sta pi_kind
    ldx side
    lda m_evo
    jne evo
    ; prima colonna: byte 2 e 3 di y - metà altezza (pad_half) + HALF_PX - 1 (come first_col)
    sec
    lda pad_y,x
    sbc pad_half,x
    sta m_lo
    lda pad_y+1,x
    sbc pad_half+1,x
    tay
    lda pad_y+2,x
    sbc pad_half+2,x
    sta v_n
    lda pad_y+3,x
    sbc #0
    sta m_t
    lda m_lo
    cmp #1                      ; C = riporto del byte 0 + $FF
    tya
    adc #>(HALF_PX - 1)
    lda v_n
    adc #0
    sta m_lo
    bcc :+
    inc m_t
:   ldy pi_side                 ; (dov'era la racchetta, per il prossimo salto del TELEPORT)
    sta pd_last,y
no_band:
    ; immagine: posa dal tipo (NEXT) o la barra bianca (le altre partite)
    ldx pi_kind
    cpx #K_NONE
    bne ship
    jsr warp_here               ; (nel salto del TELEPORT la barra di pad_prep, come le astronavi)
    bcs ship
    ; barra: SP_PAD0 (24 pixel) e SP_PAD1 (16), righe 0-3 dello sprite, niente multicolore
    ldy rot_hb
    lda #SP_PAD0
    sta sh_ptr + SPN_HI,y
    lda #SP_PAD1
    sta sh_ptr + SPN_HI + 1,y
    lda #(1 << SPN_HI) | (1 << (SPN_HI + 1))
    sta v_n
    lda v_row
    ldx pi_side
    beq :+
    sec
    sbc #3
:   ldx #SPR_X0                 ; (la barra comincia dal primo pixel dello sprite)
    jsr put_xy
    ldx side
    rts
ship:
    ; riga dello sprite: in basso faccia - ROT_NOSE, in alto faccia - 20 + ROT_NOSE
    lda v_row
    ldy pi_side
    bne :+
    sec
    sbc rot_nose,x
    jmp :++
:   sec
    sbc #20
    clc
    adc rot_nose,x
:   cpx #K_RUSH                 ; RUSH vibra come su PC e MiSTer: un pixel avanti e indietro ogni
    bne rush_done               ; 8 frame
    tay
    lda frame_count
    and #8
    beq :+
    iny
:   tya
rush_done:
    pha
    ldy pi_side
    lda pp_ready,y              ; pose non ancora in memoria: la racchetta non si vede
    bne :+
    pla
    ldx side
    rts
:   jsr warp_here
    jcs warp_ship
ship_on:
    lda #%1111 << SPN_HI
    sta v_n
    lda rot_xo,x
    tax
    pla
    jsr put_xy
    ; pagina della posa e sprite multicolori (BLASTER: dal livello del caricatore)
    ldy pi_side
    lda rot_p0,y
    sta m_t                     ; puntatore della pagina 0 del lato
    lda pi_kind
    cmp #K_TWIST
    jeq twist
    cmp #K_GUARDIAN
    jeq guardian
    cmp #K_BLASTER
    jne page0
    ldx side
    ldy nx_ammo,x               ; livello del caricatore (mag_setup)
    ldx bl_vis,y
    cpx #BLASTER_VIS
    jcs page0
    txa                         ; livello 0-3: pagina 1 + livello / 2, sprite (livello & 1) * 2
    asl a                       ; (C = 0)
    adc m_t
    adc #4
    tax                         ; X = puntatore del multicolore sinistro
    lda m_t
    jmp pointers
twist:
    ; inclinazione dalla velocità della racchetta: pagina 1 verso sinistra (y che scende), 2
    ; verso destra, 0 dritta. Dal primo gradino di oggi (TILT1): con TILT2 si inclinava tardi
    ldx side
    abs32 n_t, {pad_motion,x}
    blt32 {#TILT1}, n_t, tilted
    jmp page0
tilted:
    ldx side
    lda m_t
    clc
    adc #4
    ldy pad_motion+3,x
    bmi :+
    adc #4
:   sta m_t
    jmp page0
guardian:
    ; settori persi: la pagina 3 con i corsi grigi (guard_page, un corso per frame finché non è
    ; come i settori; con tutti i settori la posa di sempre, e intanto la pagina 3 si ripulisce)
    ldx side
    lda nx_barrier,x
    eor #(1 << G_SECTORS) - 1
    ldy pi_side
    cmp pd_var,y
    beq :+
    pha
    jsr guard_page
    pla
:   tax
    jeq page0
    lda m_t
    clc
    adc #12
    sta m_t
page0:
    lda m_t
    tax
    inx
    inx
pointers:
    ldy rot_hb
    sta sh_ptr + SPN_HI,y
    clc
    adc #1
    sta sh_ptr + SPN_HI + 1,y
    txa
    sta sh_ptr + SPN_MC,y
    adc #1                      ; (C = 0)
    sta sh_ptr + SPN_MC + 1,y
    ; colore del multicolore (%10): come oggi
    jsr pad_color
    ldy rot_hb
    sta sh_col + SPN_MC,y
    sta sh_col + SPN_MC + 1,y
    ldx side
    rts
warp_ship:
    ; salto del TELEPORT (X = tipo, la riga dello sprite sulla pila): la posa di sempre, nascosta a
    ; colonne dalla maschera (warp_place); niente con tutte le colonne nascoste; alla partenza
    ; dov'era la racchetta; x pari (la maschera è a colonne di due pixel, rot_off è pari)
    lda wm_b0
    and wm_b1
    cmp #$ff
    bne :+
    pla
    ldx side
    rts
:   lda wp_out
    bne :+
    lda wp_from
    sta m_lo
    lda #0
    sta m_t
:   lda m_lo
    and #$fe
    sta m_lo
    jmp ship_on
evo:
    ; partita EVO: la prima colonna con first_col, poi la banda (sprite 1): l'area boost, colonne
    ; da y - metà area a y + metà area
    lda pad_y,x
    sta t0
    lda pad_y+1,x
    sta t0+1
    lda pad_y+2,x
    sta t0+2
    lda pad_y+3,x
    sta t0+3
    ldy pad_half,x
    lda pad_half+2,x
    pha
    lda pad_half+1,x
    tax
    pla
    jsr first_col
    ldy pi_side
    lda m_lo
    sta pd_last,y
    pha
    lda m_t
    pha
    ldx side
    lda pad_bh+3,x              ; metà dell'area: byte 0-2 di pad_bh / 2
    lsr a
    lda pad_bh+2,x
    ror a
    sta t1+2
    lda pad_bh+1,x
    ror a
    sta t1+1
    lda pad_bh,x
    ror a
    tay
    ldx t1+1
    lda t1+2
    jsr first_col               ; m_lo = prima colonna (t2 = metà area)
    ; ultima: byte 2 di y + metà area - HALF_PX
    clc
    lda t0
    adc t2
    lda t0+1
    adc t2+1
    sta t1+1
    lda t0+2
    adc t2+2
    sta t1+2
    lda t1+1
    sec
    sbc #>HALF_PX
    lda t1+2
    sbc #0
    sec
    sbc m_lo                    ; larghezza - 1
    bcc band_off
    cmp #SPRITE_BANDS
    bcc :+
    lda #SPRITE_BANDS - 1
:   clc
    adc #SP_BAND1
    ldy rot_hb
    sta sh_ptr + SPN_ICON_R,y
    lda #COL_GRAY
    sta sh_col + SPN_ICON_R,y
    lda v_row                   ; la riga in alto del rettangolo della racchetta
    ldx pi_side
    beq :+
    sec
    sbc #3
:   clc
    adc #SPR_Y0
    sta sh_y + SPN_ICON_R,y
    lda m_lo
    clc
    adc #SPR_X0
    sta sh_x + SPN_ICON_R,y
    lda #1 << SPN_ICON_R
    sta v_n
    bcs :+
    lda #0
:   jsr or_half
band_off:
    pla
    sta m_t
    pla
    sta m_lo
    jmp no_band
.endproc
; riga della faccia: W - metà larghezza (in basso), W + metà larghezza - 1 (in alto), meno la x
face_k: .byte ROT_W - (P_PAD_HALF_W >> 16), ROT_W + (P_PAD_HALF_W >> 16) - 1
.assert (P_PAD_HALF_W & $FFFF) = 0, error, "racchette: metà larghezza intera"
rot_off:  .byte ROT_OFF
rot_xo:   .repeat 8, k          ; SPR_X0 - rot_off: la x dello sprite dalla prima colonna
          .byte SPR_X0 - .mid(2 * k, 1, {ROT_OFF})
          .endrepeat
rot_nose: .byte ROT_NOSE
rot_p0:   .byte ROT_PTR0, ROT_PTR0 + 16     ; puntatore della pagina 0 delle pose, per lato

; Sprite della racchetta (2-5) nei registri della metà in esame (rot_hb): riga A dello sprite (senza
; SPR_Y0), x = X + la colonna m_lo (m_t il byte alto; X = SPR_X0 meno lo scostamento
; dell'immagine), v_n gli sprite da accendere.
.proc put_xy
    ldy rot_hb
    clc
    adc #SPR_Y0
    sta sh_y + SPN_HI,y
    sta sh_y + SPN_HI + 1,y
    sta sh_y + SPN_MC,y
    sta sh_y + SPN_MC + 1,y
    txa
    clc
    adc m_lo
    tax                         ; x degli sprite sinistri
    lda m_t
    adc #0
    bpl :+
    lda #0                      ; (fuori dal campo a sinistra: al bordo)
    tax
:   sta rot_msb                 ; nono bit degli sprite sinistri
    txa
    sta sh_x + SPN_HI,y
    sta sh_x + SPN_MC,y
    clc
    adc #24
    sta sh_x + SPN_HI + 1,y
    sta sh_x + SPN_MC + 1,y
    lda #0
    adc rot_msb                 ; nono bit dei destri
    beq :+
    lda #(1 << (SPN_HI + 1)) | (1 << (SPN_MC + 1))
:   ldx rot_msb
    beq :+
    ora #(1 << SPN_HI) | (1 << SPN_MC)
:   ; (prosegue in or_half)
.endproc

; Nella metà in esame (rot_hb): i bit di A nei noni bit, quelli di v_n negli sprite accesi.
.proc or_half
    ldy rot_hb
    bne low
    ora sh_msb
    sta sh_msb
    lda v_n
    ora sh_enable
    sta sh_enable
    rts
low:
    ora shb_msb
    sta shb_msb
    lda v_n
    ora shb_en
    sta shb_en
    rts
.endproc

; A = colore del multicolore (%10) della racchetta di side: grigio con il BULLET scattato
; dell'avversario, con STEER e a tratti con un bonus armato; giallo nel colpo di una mossa, verde a
; tratti colpita dal laser, OMEGA bianco o viola, se no il colore del tipo (come oggi).
.proc pad_color
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
    cpx nx_bside
    bne white
blink:
    lda tick
    and #PAD_BLINK
    beq white
gray:
    lda #COL_GRAY
    rts
bullet:
    cpx nx_bside
    bne gray
    lda nx_steer
    beq :+
    cpx nx_steer_s
    beq gray
:   lda nx_armed,x
    cmp #B_NONE
    bne blink
white:
    lda sm_kick,x
    and #%1100
    cmp #%1100
    bne :+
    lda #COL_YELLOW
    rts
:   lda nx_lslow,x
    beq :+
    lda tick
    and #PAD_BLINK
    beq :+
    lda #COL_GREEN
    rts
:   cpx nx_morph
    bne kind_color
    jmp om_white                ; (bianco o viola)
kind_color:
    ldx pi_kind
    lda kind_col,x
    rts
.endproc

; NEXT: icone dei bonus armati davanti alla faccia della racchetta (sprite 1 della sua metà) e
; capsule in volo (6 e 7; la terza e la quarta nello sprite 1 di una metà libera, se ci stanno).
.proc next_sprites
    lda #0
    sta ns_icons
    ldy #0                      ; lato
armed:
    sty pi_side
    lda hb_of,y
    sta rot_hb
    tya
    asl a
    asl a
    tax
    stx m_lo
    lda #COL_GRAY
    sta m_t
    lda nx_steer
    beq :+
    lda nx_steer_s
    cmp m_lo
    bne :+
    lda #COL_YELLOW
    sta m_t
    lda #B_STEER
    bne show                    ; (sempre)
:   jsr sm_icon
    bcs show
    lda nx_armed,x
    cmp #B_NONE
    beq next_side
show:
    clc
    adc #SP_ICON0
    ldy rot_hb
    sta sh_ptr + SPN_ICON_R,y
    lda m_t
    sta sh_col + SPN_ICON_R,y
    ; y: davanti alla faccia (in basso sopra, in alto sotto), oltre la sporgenza dei cannoni
    ldx pi_side
    lda pd_draw_lo,x
    cpx #0
    bne :+
    sec
    sbc #ICON_GAP + 8
    jmp :++
:   clc
    adc #ICON_GAP + 1
:   clc
    adc #SPR_Y0
    sta sh_y + SPN_ICON_R,y
    ; x: colonna del centro della racchetta - 4
    ldx m_lo
    lda pad_y+2,x
    clc
    adc #SPR_X0 - 4
    sta sh_x + SPN_ICON_R,y
    lda #1 << SPN_ICON_R
    sta v_n
    bcs :+
    lda #0
:   jsr or_half
    ldy pi_side
    lda bit_of,y
    ora ns_icons
    sta ns_icons
next_side:
    ldy pi_side
    iny
    cpy #2
    jne armed
    ; capsule
    ldy #0
cap:
    lda cap_on,y
    jeq cap_next
    sty ns_k
    ; riga del centro: W - x (byte 2, con il segno: la capsula esce di qualche pixel)
    tya
    asl a
    asl a
    tax                         ; X = capsula * 4
    lda #<(SPR_Y0 + ROT_W - CAP_DRAW / 2)
    sec
    sbc cap_x+2,x
    sta v_row
    lda cap_y+2,x
    clc
    adc #<(SPR_X0 - CAP_DRAW / 2)
    sta v_col
    lda #0
    rol a
    sta rot_msb                 ; nono bit
    ; sprite: 6 e 7 le prime due, poi lo sprite 1 di una metà dove sta tutta e non c'è l'icona
    cpy #2
    bcs extra
    tya
    adc #SPN_CAP_R              ; (C = 0)
    tax
    ldy #0                      ; (6 e 7 nei registri della metà in alto: la mezzeria non li cambia)
    beq have                    ; (sempre)
extra:
    ldx #SPN_ICON_R
    lda v_row
    cmp #SPLIT_LINE - 21 - 2 + 1
    bcs :+
    lda ns_icons                ; tutta in alto
    and #%10
    jne cap_skip
    lda ns_icons
    ora #%10
    sta ns_icons
    ldy #0
    beq have                    ; (sempre)
:   cmp #SPLIT_LINE + 4
    bcc cap_skip                ; a cavallo della mezzeria: non si vede
    lda ns_icons                ; tutta in basso
    and #%01
    bne cap_skip
    lda ns_icons
    ora #%01
    sta ns_icons
    ldy #ROT_HB
have:
    sty rot_hb
    stx ns_n
    txa                         ; Y = registro dello sprite nella sua metà
    clc
    adc rot_hb
    tay
    lda v_col
    sta sh_x,y
    lda v_row
    sta sh_y,y
    ; immagine e colore: bianca (grigia nel bullet time), il SUPER e il BULLET gialli, il SUPER
    ; in negativo a tratti
    ldx #COL_WHITE
    lda nx_btimer
    beq :+
    ldx #COL_GRAY
:   stx m_t
    ldx ns_k
    lda cap_bonus,x
    clc
    adc #SP_CAP0
    sta m_lo
    lda cap_bonus,x
    cmp #B_BULLET
    beq yellow
    cmp #B_SUPER
    bne colored
    lda tick
    and #CAP_BLINK
    beq yellow
    lda #SP_CAPINV
    sta m_lo
yellow:
    lda #COL_YELLOW
    sta m_t
colored:
    lda m_t
    sta sh_col,y
    lda m_lo
    sta sh_ptr,y
    ldx ns_n
    lda bit_of,x
    sta v_n
    ldx rot_msb
    bne :+
    lda #0
:   jsr or_half
cap_skip:
    ldy ns_k
cap_next:
    iny
    cpy #4
    jne cap
    rts
.endproc

; ------------------------------------------------------------------------------------ campo

; Mezzeria nella riga 12 (colonne 0-29: un carattere per colonna, vuoto dove la rete salta), muro
; destro nella colonna 30 (grigio scuro), in singolo il muro in alto nella riga 1. Scritture dirette:
; è il primo frame della partita, già pesante.
.proc draw_field
    jsr bullet_chars
    jsr field_glyphs
    lda m_evo                   ; partita EVO con le bande ancora prese dalle astronavi (di solito
    beq :+                      ; il titolo e il menu le hanno già rifatte: band_step)
    lda ship_bands
    beq :+
    jsr band_sprites
:
    lda m_next                  ; partite senza tipo: la barra negli sprite 2 e 3 (la scelta della
    bne :+                      ; racchetta ci mette le sue anteprime)
    jsr bar_sprites
:
    jsr net_setup
    lda #ROT_LINE_ROW
    sta v_row
    jsr center_line_row
    lda #CH_LINE_R
    ldx #COL_DGRAY
    .repeat 25, r
    sta SCREEN + r * 40 + ROT_WALL_COL
    stx $d800 + r * 40 + ROT_WALL_COL
    .endrepeat
    lda m_players
    cmp #1
    bne done
    lda #CH_WALL
    ldy #ROT_FIELD_COLS - 1
:   sta SCREEN + ROT_SINGLE_ROW * 40,y
    dey
    bpl :-
done:
    rts
.endproc

; Mezzeria: la riga v_row se è quella della mezzeria (le altre non ne hanno).
.proc center_line_row
    lda v_row
    cmp #ROT_LINE_ROW
    bne done
    lda row_lo + ROT_LINE_ROW
    sta ptr
    lda row_hi + ROT_LINE_ROW
    sta ptr+1
    ldy #ROT_FIELD_COLS - 1
col:
    tya                         ; colonne vuote della rete dell'avversario (net_skip)
    and #3
    tax
    lda bit_of,x
    and net_skip
    beq on
    lda #CH_BLANK
    .byte $2c
on: lda #CH_LINE_L
    sta (ptr),y
    dey
    bpl col
done:
    rts
.endproc

; Caratteri 1-3: nel set quelli di oggi (la scelta dei bonus, la classifica); il campo girato
; mette il suo muro destro e il muro del singolo (field_glyphs, da draw_field; la mezzeria è la
; rete di net_setup), today_glyphs rimette quelli di oggi.
.proc today_glyphs
    ldx #23
:   lda rot_gl_today,x
    sta CHARSET + 8 * CH_LINE_L,x
    dex
    bpl :-
    rts
.endproc
.proc field_glyphs
    ldx #15
:   lda rot_gl_field,x
    sta CHARSET + 8 * CH_LINE_R,x
    dex
    bpl :-
    rts
.endproc
rot_gl_today: .byte ROT_GL_TODAY
rot_gl_field: .byte ROT_GL_FIELD
.assert CH_LINE_R = CH_LINE_L + 1 .and CH_WALL = CH_LINE_L + 2, error, "caratteri 1-3 in fila"

; La barra bianca delle partite senza tipo negli sprite 2 e 3 (come in gen/rotated/sprites.bin): 24
; pixel nel primo, 16 nel secondo, righe 0-3.
.proc bar_sprites
    sei
    lda #$34
    sta $01
    ldx #127
    lda #0
:   sta $C000 + SP_PAD0 * 64,x
    dex
    bpl :-
    lda #$ff
    ldx #11
:   sta $C000 + SP_PAD0 * 64,x
    dex
    bpl :-
    .repeat 4, r
    sta $C000 + SP_PAD1 * 64 + 3 * r
    sta $C000 + SP_PAD1 * 64 + 3 * r + 1
    .endrepeat
    lda #$35
    sta $01
    cli
    rts
.endproc
.assert SP_PAD1 = SP_PAD0 + 1 .and $C000 + SP_PAD0 * 64 >= $D000 .and $C000 + SP_PAD1 * 64 + 64 <= $D800, error, "bar_sprites: sprite 2 e 3 in fila, nella RAM sotto l'I/O"

; ------------------------------------------------------------------------ fuori partita

; Le astronavi della partita anche fuori dalla partita (scelta, VS, presentazione, finale): quattro
; sprite ciascuna, bianco hires sinistro e destro poi multicolore sinistro e destro, come in
; partita. Le immagini sono le pose dalla cartuccia (PAD_BANK, pagina 0 del tipo e del lato) negli
; sprite delle bande EVO, due serie da quattro (SHIP_SLOT0, poi quattro più in là): ship_copy ne
; copia uno per frame, nel vblank; le bande si rifanno nel titolo e nel menu, all'uscita dal finale
; o a inizio partita (band_sprites). Il %11 del multicolore è il grigio scuro: ship_regs lo chiede ad
; apply_shadows (ship_dgray), che lo tiene finché ci sono sprite accesi.
SHIP_SLOT0 = SP_BAND1
.assert SPRITE_BANDS >= 8, error, "astronavi fuori partita negli sprite delle bande EVO"
.assert (SHIP_SLOT0 * 64) .mod 256 = $80, error, "ship_copy: le serie a mezza pagina"

; Uno sprite (ship_part, 0-3) della posa del tipo A e del lato Y (0 in basso, 1 in alto) nella serie
; X. Solo nelle prime righe del vblank, da RASTER_LINE - 2 a fine schermo (la copia, circa 1.600
; cicli, tiene spenti gli interrupt e l'I/O: finisce prima degli split delle schermate), senza voce.
; Sull'NTSC lo schermo finisce 13 righe dopo l'interrupt e chi chiama (dopo registri, comandi e
; musica) arrivava sempre più tardi: le pose non si copiavano mai (niente astronavi nella scelta e
; nel finale). Lì valgono anche le prime SHIP_TOP righe del frame dopo, nel bordo in alto: la
; copia (25 righe) finisce prima della prima riga dello schermo, dove cominciano gli split.
; C = 0 copiato (ship_part avanza), C = 1 non adesso. Sotto $8000: con la cartuccia accesa.
SHIP_TOP = 24
.assert SHIP_TOP + 26 <= SPR_Y0, error, "ship_copy: sull'NTSC la copia finisce nel bordo in alto"
.proc ship_copy
    sta ship_k
    bit $fffb
    bpl :+
no: sec
    rts
:   lda $d011
    bmi ok
    lda $d012
    cmp #RASTER_LINE - 2
.ifdef NTSC
    bcs ok
    cmp #SHIP_TOP
    bcs no
.else
    bcc no
.endif
ok:
    ; sorgente: la pagina (tipo * 2 + lato) * 4 della finestra a 16K, sprite ship_part
    lda ship_k
    asl a
    sty ship_t
    ora ship_t
    asl a
    asl a
    ora #$80
    sta src + 2
    lda ship_part
    lsr a
    ror a
    ror a                       ; (parte & 3) * 64
    and #$C0
    sta src + 1
    ; destinazione: $C000 + (SHIP_SLOT0 + serie * 4 + parte) * 64
    txa
    asl a
    asl a
    ora ship_part
    clc
    adc #SHIP_SLOT0
    sta ship_t                  ; posto dello sprite
    lsr a
    lsr a
    clc
    adc #$C0
    sta dst + 2
    lda ship_t
    lsr a
    ror a
    ror a
    and #$C0
    sta dst + 1
    sei
    lda #PAD_BANK
    sta EF_BANK
    lda #EF_16K
    sta EF_MODE
    ldy #62
loop:
    lda #$37
    sta $01
src:
    lda $8000,y
    ldx #$34
    stx $01
dst:
    sta $D180,y
    dey
    bpl loop
    lda #$37
    sta $01
    lda #EF_OFF
    sta EF_MODE
    lda #$35
    sta $01
    cli
    lda #SPRITE_BANDS           ; tutte le bande da rifare
    sta ship_bands
    inc ship_part
    clc
    rts
.endproc

; Tutta la posa del tipo A e del lato Y nella serie X, subito: a schermo spento (quattro copie di
; ship_copy, circa 6.400 cicli, con gli interrupt accesi fra l'una e l'altra). Sotto $8000.
.proc ship_load
    sta ship_k
    lda #0
    sta ship_part
:   txa
    pha
    tya
    pha
    jsr ship_copy::ok
    pla
    tay
    pla
    tax
    lda ship_part
    cmp #4
    bcc :-
    rts
.endproc
.assert ship_load + 32 < $8000, error, "ship_load: sotto la cartuccia"

; I quattro sprite dell'astronave del tipo A dalla serie Y nelle ombre degli sprite da X (0 o 4),
; alla x ship_x (lo sprite sinistro, senza il nono bit) e alla y ship_y. Il grigio scuro finché ci
; sono sprite accesi (apply_shadows).
.proc ship_regs
    sta ship_k
    tya
    asl a
    asl a
    adc #SHIP_SLOT0             ; (C = 0)
    sta sh_ptr,x
    adc #1
    sta sh_ptr+1,x
    adc #1
    sta sh_ptr+2,x
    adc #1
    sta sh_ptr+3,x
    lda ship_x
    sta sh_x,x
    sta sh_x+2,x
    clc
    adc #24
    sta sh_x+1,x
    sta sh_x+3,x
    lda ship_y
    sta sh_y,x
    sta sh_y+1,x
    sta sh_y+2,x
    sta sh_y+3,x
    lda #COL_WHITE
    sta sh_col,x
    sta sh_col+1,x
    ldy ship_k
    lda kind_col,y
    sta sh_col+2,x
    sta sh_col+3,x
    lda ship_mask,x             ; i quattro sprite: accesi, niente nono bit né espansioni
    ora sh_enable
    sta sh_enable
    lda ship_mask,x
    eor #$ff
    tay
    and sh_msb
    sta sh_msb
    tya
    and sh_xexp
    sta sh_xexp
    tya
    and sh_yexp
    sta sh_yexp
    tya
    and sh_mc
    ora ship_mcm,x              ; multicolore solo i due dopo
    sta sh_mc
    sty ship_dgray              ; (non zero)
    rts
.endproc
ship_mask: .byte %00001111      ; per X = 0 e 4, intrecciate
ship_mcm:  .byte %00001100, 0, 0, %11110000, %11000000
.assert ship_mcm = ship_mask + 1, error, "ship_regs: tabelle intrecciate"

; Le bande EVO di nuovo negli sprite che le astronavi hanno preso (come gen/rotated/sprites.bin: la
; banda i larga i + 1 pixel nelle righe 0-3).
.proc band_sprites
:   jsr band_step
    lda ship_bands
    bne :-
    rts
.endproc

; Una banda (la ship_bands - 1, poi ship_bands scende): sprite vuoto, poi le righe 0-3.
.proc band_step
    sei
    lda #$34
    sta $01
    ldx ship_bands
    dex
    stx ship_bands
    txa                         ; ptr = $C000 + (SP_BAND1 + i) * 64
    clc
    adc #SP_BAND1
    sta ptr
    lda #0
    lsr ptr
    ror a
    lsr ptr
    ror a
    sta ptr2                    ; (byte basso)
    lda ptr
    clc
    adc #$C0
    sta ptr+1
    lda ptr2
    sta ptr
    lda #0
    ldy #63
:   sta (ptr),y
    dey
    bpl :-
    ldy #9
:   lda band_rows,x
    sta (ptr),y                 ; righe 0-3, byte 0
    lda band_rows2,x
    iny
    sta (ptr),y                 ; byte 1
    dey
    dey
    dey
    dey
    bpl :-
    lda #$35
    sta $01
    cli
    rts
.endproc
band_rows:  .byte $80, $C0, $E0, $F0, $F8, $FC, $FE, $FF, $FF, $FF
band_rows2: .byte 0, 0, 0, 0, 0, 0, 0, 0, $80, $C0
.assert SPRITE_BANDS = 10, error, "band_sprites: dieci bande"

ship_k:     .res 1
ship_t:     .res 1
ship_part:  .res 1
ship_x:     .res 1
ship_y:     .res 1
ship_bands: .res 1              ; bande EVO ancora da rifare (le astronavi ne hanno preso gli sprite)
ship_dgray: .res 1              ; $D026 grigio scuro in questo frame

; Scelta della racchetta: le anteprime sono le astronavi (a sinistra P1 con la posa in basso, a
; destra l'altro con quella in alto), sotto la griglia. Fin sotto la griglia gli otto sprite sono
; dei cursori: alla riga RP_LINE lo split della scelta (kp_split) li riprogramma per le astronavi
; (rp_mid, dai registri che rp_preview prepara), al frame dopo apply_shadows rimette i cursori.
; rp_mid e i suoi registri stanno sotto $8000: kp_split gira anche con la cartuccia accesa.
RP_LINE   = 168                 ; sotto le cornici e le sigle dei cursori (fino alla riga 166)
RP_TOP    = 178                 ; prima riga degli sprite delle astronavi: rp_mid finisce verso la 174
RP_CX0    = 14 * 8 + 4          ; centri delle astronavi (pixel del campo): come le anteprime di oggi
RP_CX1    = 25 * 8 + 4

.proc rp_preview
    lda #0
    sta sh_enable
    sta ship_dgray              ; (ship_regs lo riaccende con le astronavi)
    sta rp_regs + 34            ; (sprite accesi sotto la griglia: nessuno)
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
    bne done
    jsr rp_pose                 ; (con lo schermo della scelta: nella sua bitmap, kpick.s)
    jsr rp_place
done:
    jmp KP_RUN + 3              ; i cursori
.endproc
rp_dy: .byte ROT_PICK_DY
.assert RP_TOP >= RP_LINE + 10, error, "scelta: le astronavi dopo la fine di rp_mid"
.assert SPR_X0 + RP_CX1 + 24 < 256, error, "scelta: astronavi senza il nono bit"

; Alla riga RP_LINE (kp_split, con A, X e Y salvati): gli otto sprite per le astronavi.
.proc rp_mid
    ldx #7
    ldy #14
:   lda rp_regs,x
    sta $d000,y
    lda rp_regs + 8,x
    sta $d001,y
    lda rp_regs + 16,x
    sta SPR_PTR,x
    lda rp_regs + 24,x
    sta $d027,x
    dey
    dey
    dex
    bpl :-
    lda #0                      ; (le x sotto 256, niente espansioni)
    sta $d010
    sta $d017
    sta $d01d
    lda rp_regs + 32
    sta $d01c
    lda rp_regs + 34
    sta $d015
    rts
.endproc
rp_regs: .res 35                ; x, y, puntatori, colori (8 ciascuno), multicolore, -, accesi
rp_part: .res 2                 ; sprite di posa copiati per lato (4: tutta)
.assert rp_mid < $8000 .and rp_regs + 35 < $8000, error, "rp_mid: sotto la cartuccia"

; La mezzeria verticale di oggi nella riga v_row (colonne 19 e 20): la scelta dei bonus.
.proc pick_line_row
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

; Rete della partita nel carattere della mezzeria (ROT_NET: il motivo di oggi girato).
NET_CH = CHARSET + 8 * CH_LINE_L
.proc net_setup
    lda #K_NONE
    ldx cg_active
    cpx #CG_LADDER
    bne :+
    ldx ch_level
    lda rung_kind,x
    cpx #CH_OMEGA
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
    lda #12
    sta net_t
    txa
    asl a
    asl a
    asl a
    tax
    ldy #0
:   lda rot_net,x
    sta NET_CH,y
    inx
    iny
    cpy #8
    bne :-
    rts
.endproc
rot_net:   .byte ROT_NET
net_skips: .byte %1010, %1000, %1010, 0, 0, 0, 0, 0

.proc net_plain
    lda #K_NONE
    jmp net_setup::set
.endproc

; Reti animate (come net_tick di oggi, nel carattere della mezzeria): RUSH trattini che scorrono di
; un pixel a tick, TWIST inclinata di 2 pixel verso dove va la palla quando è entro NET_NEAR pixel
; dalla mezzeria, HAMMER che vibra per 12 frame ai colpi della CPU.
NET_NEAR = 30 * 200 / 320       ; (i 30 pixel di oggi, in proporzione)
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
    lda tick
    and #7
    tax
    lda rush_pat,x
    sta NET_CH + 3
    sta NET_CH + 4
    rts
twist:
    ldx #0
    lda ball_x+3
    bne :+
    lda ball_x+2
    cmp #(P_WIDTH >> 17) - NET_NEAR
    bcc :+
    cmp #(P_WIDTH >> 17) + NET_NEAR
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
    asl a
    tax
    ldy #0
:   lda rot_tw,x
    sta NET_CH,y
    inx
    iny
    cpy #8
    bne :-
done:
    rts
hammer:
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
    txa
    asl a
    asl a
    asl a
    tax
    ldy #0
:   lda rot_ham,x
    sta NET_CH,y
    inx
    iny
    cpy #8
    bne :-
    rts
.endproc
rush_pat: .byte $F0, $78, $3C, $1E, $0F, $87, $C3, $E1
rot_tw:   .byte ROT_NET_TW
rot_ham:  .byte ROT_NET_HAM

; ------------------------------------------------------------------------------------ punteggi

; Punteggi nella fascia: in due il giocatore in alto (destro) nelle righe 3-5, quello in basso
; (sinistro) nelle 19-21; in singolo i colpi in basso, record e palle in alto.
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
    .byte 31, 3, "TOP", 0
    lda best+1
    ldx best
    jsr clamp99
    ldx #36
    ldy #3
    jsr print_num2
    jsr print_at
    .byte 31, 5, "BALLS", 0
    lda lives
    clc
    adc #'0'
    ldx #37
    ldy #5
    sty v_row
    jmp put_ascii
.endproc

; Punteggio del lato Y (0: in basso, righe 19-21; 4: in alto, righe 3-5), colonna 31.
.proc draw_side
    ldx score,y
    lda score+1,y
    jsr clamp99
    ldx #31
    cpy #0
    bne :+
    ldy #19
    jmp draw_score2
:   ldy #3
    jmp draw_score2
.endproc

; ------------------------------------------------------------------------------------ pose

; Pose delle astronavi dalla cartuccia (PAD_BANK, gen/rotated/paddles.bin): per lato le pagine del
; suo tipo (TWIST e BLASTER 3, GUARDIAN 4, gli altri 1) da $E100 + lato * $400, una pagina per frame nei frame
; con il tempo, senza voci e non a cavallo della mezzeria (la copia tiene gli interrupt spenti).
.proc pad_prep
    ldy pp_side
    cpy #2
    bcs quit
    lda pp_ready,y
    beq load
    iny
    sty pp_side
    bne pad_prep
load:
    lda #PP_LATE
    jsr frame_after
    bcs quit
    jsr split_clear
    bcs quit
    lda pp_side
    asl a
    asl a
    tax                         ; lato * 4
    lda nx_kind,x
    asl a
    asl a
    asl a                       ; tipo * 8 (C = 0)
    adc pp_side
    adc pp_side
    adc pp_side
    adc pp_side                 ; + lato * 4
    adc pp_var
    adc #$80                    ; pagina nella finestra della cartuccia
    sta ef_src+2
    lda pp_side
    asl a
    asl a
    adc pp_var
    adc #>ROT_PAGES
    tay
    lda #PAD_BANK
    ldx #1
    jsr ef_copy
    ldy pp_side
    inc pp_var
    lda pp_side
    asl a
    asl a
    tax
    lda nx_kind,x
    tax
    lda pp_var
    cmp rot_pages,x
    bcc quit
    lda #0
    sta pp_var
    sta pd_var,y                ; (GUARDIAN: la pagina 3 è la posa intera, nessun corso grigio)
    lda #1
    sta pp_ready,y
quit:
    rts
.endproc
rot_pages: .byte 1, 1, 1, 3, 3, 1, 4, 1   ; pagine per tipo (TWIST e BLASTER 3, GUARDIAN 4)

; C = 1 se una copia di circa 3.500 cicli partita adesso arriverebbe alla mezzeria.
.proc split_clear
    lda $d011
    bmi ok
    lda $d012
    cmp #SPLIT_LINE - 3500 / TV_LCYC - 2
    bcc ok
    cmp #SPLIT_LINE + 2
    bcs ok
    sec
    rts
ok: clc
    rts
.endproc

; ------------------------------------------------------------------------------------ coda

; A = angolo dello sprite della coda in cui sta la palla, dal moto a schermo (come trail_dir di
; oggi): bit 7 se va a sinistra (vy < 0), bit 0-1 il moto verticale (0 sale: vx > 0, 1 fermo,
; 2 scende). Cambia Y.
.proc trail_dir
    lda ball_vx+3
    bmi fall
    ora ball_vx+2
    ora ball_vx+1
    ora ball_vx
    beq level
    lda #0
    beq vy
fall:
    lda #2
    bne vy
level:
    lda #1
vy:
    ldy ball_vy+3
    bpl :+
    ora #$80
:   rts
.endproc

; ------------------------------------------------------------------------------------ effetti

; Salto del TELEPORT, come oggi (warp_fx di video.s, next_ui.rs e il MiSTer) ma con i caratteri:
; con la palla in arrivo l'astronave si scompone a colonne dove si trova mentre la palla va da metà
; campo a 32 pixel più in là, poi si ricompone sul punto d'arrivo mentre la palla va da 96 a 64
; pixel dal bordo (in pixel del campo di oggi: warp_d li converte). L'astronave resta la sua posa
; di sempre; sopra, gli sprite 2-5 della sua metà dietro i caratteri, una maschera nelle celle
; vuote del rettangolo dei suoi sprite (warp_place): caratteri neri con accese le colonne di due
; pixel nascoste (in luce e vuote: la classe della colonna k dello schermo è (k * 5) & 7, le soglie
; come oggi), e, nelle celle senza colonne vuote, a scacchiera che cambia con il tremolio,
; caratteri nel colore del personaggio con le colonne in luce a puntini. Quattro caratteri:
; WM_CH nero per le colonne di celle pari e dispari, WM_CH + 2 in accento; si rifanno a ogni passo
; (tabelle ROT_WB0/1, ROT_WL0/1 e ROT_WEL di gen/rotated/rotated.inc, per arrivo * 33 +
; avanzamento). Stanno tra i laser (64-95, 107-127) dentro le lettere 2x, che la fine della partita
; NEXT rifà. wp_en: il passo; wp_ls: quello dei caratteri (passo * 2 + tremolio, $FF da rifare);
; wp_src: il tremolio.
ROT_SUNK  = 160                 ; (WARP_STEP e WARP_RISE di video.s; WARP_SUNK lì è metà del campo girato)
ROT_HALF  = (P_WIDTH >> 16) / 2
WM_CH     = 102
WM_CELLS  = 8 * 4               ; wm_save: 8 celle per riga (al più 7: 48 pixel), 4 righe (21)
.assert WM_CH >= SHOT_P0 + SHOT_PN .and WM_CH + 4 <= SHOT_B0 .and WM_CH + 4 <= BIG2_FIRST + 4 * BIG2_N, error, "salto del TELEPORT: caratteri fuori dalle lettere 2x o sui laser"

.proc warp_early
    rts
.endproc

.proc warp_fx
    lda m_next
    beq off
    lda wp_on
    bne running
    lda events
    and #EV_TELEPORT
    beq off
    ; inizio: salta chi riceve la palla
    ldx #0
    lda ball_vx+3
    sta wp_dir                  ; (il verso della palla: verso chi salta)
    bmi :+
    inx
:   stx wp_side
    lda pd_last,x
    sta wp_from
    lda #$ff                    ; caratteri da rifare
    sta wp_ls
    lda #1
    sta wp_on
running:
    ; fine: colpo, punto, battuta, palla che si allontana, o racchetta tutta fuori
    lda events
    and #EV_HIT | EV_BOOST | EV_SCORE
    bne stop
    lda serve_timer
    ora serve_timer+1
    bne stop
    lda ball_vx+3
    eor wp_dir
    bmi stop
    jsr warp_d
    cmp #WARP_RISE - WARP_STEP + 1
    bcs going
stop:
    lda #0
    sta wp_on
off:
    rts
going:
    sta wp_d
    ; avanzamento: pixel affondati e usciti (0-32), clamp(fase - wp_d, 0, WARP_STEP)
    lda #ROT_SUNK
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
    ; passo: arrivo * 33 + avanzamento; tremolio 6 volte al secondo
    beq dep
    clc
    adc #33
    bne key
dep:
    lda wp_sunk
key:
    sta wp_en
    lda tick
    lsr a
    lsr a
    and #1
    sta wp_src
    lda wp_en
    asl a
    ora wp_src
    cmp wp_ls
    jeq done
    sta wp_ls
    jsr warp_step
    ; i quattro caratteri: neri (le colonne nascoste, tutte le righe), in accento (le colonne in
    ; luce, a righe alterne di due con il tremolio)
    ldx #7
row:
    lda wm_b0
    sta CHARSET + 8 * WM_CH,x
    lda wm_b1
    sta CHARSET + 8 * WM_CH + 8,x
    txa
    lsr a
    eor wp_src
    and #1
    beq dots
    lda #0                      ; riga senza puntini
    sta CHARSET + 8 * WM_CH + 16,x
    beq odd                     ; (sempre)
dots:
    lda wm_l0
    sta CHARSET + 8 * WM_CH + 16,x
    lda wm_l1
odd:
    sta CHARSET + 8 * WM_CH + 24,x
    dex
    bpl row
done:
    rts
.endproc

; Le classi del passo wp_en (come warp_image di oggi): la classe c ha la soglia (c * 11) >> 2; è
; nascosta (in luce o vuota) con soglia < H, in luce se anche soglia >= L; alla partenza (passo a)
; H = a + 1 e L = a - 7, all'arrivo (passo 33 + a) H = 30 - a e L = 22 - a (tutto + 16, per
; restare sopra lo zero). Poi i byte dei caratteri: wm_b0/wm_b1 neri (le colonne nascoste) e
; wm_l0/wm_l1 in accento (le colonne in luce) delle colonne di celle pari e dispari (le classi
; (4 * parità + 5 * j) & 7, due bit per colonna), wm_el le parità che possono essere in accento
; (nessuna colonna vuota, almeno una in luce).
.proc warp_step
    lda wp_en
    cmp #33
    bcs arr
    adc #17                     ; partenza (C = 0): H = a + 17, L = a + 9
    sta v_n
    sbc #7                      ; (C = 0: - 8)
    jmp bounds
arr:
    eor #$ff                    ; arrivo: H = 79 - passo, L = 71 - passo
    sec
    adc #79
    sta v_n
    sec
    sbc #8
bounds:
    sta v_col                   ; L
    ; per classe: nascosta (soglia < H) i suoi due bit nel carattere nero della sua parità, in luce
    ; (anche soglia >= L) pure in quello in accento; per parità, in v_row, bit 0-1 con colonne in
    ; luce, bit 2-3 con colonne vuote
    lda #0
    sta wm_b0
    sta wm_b1
    sta wm_l0
    sta wm_l1
    sta v_row
    ldx #7
cls:
    lda ws_th,x
    cmp v_n
    bcs next                    ; piena
    ldy ws_par,x
    lda ws_bits,x
    ora wm_b0,y
    sta wm_b0,y
    lda ws_th,x
    cmp v_col
    bcc empty
    lda ws_bits,x               ; in luce
    ora wm_l0,y
    sta wm_l0,y
    lda wm_bit,y
    bne mark                    ; (sempre)
empty:
    lda wm_bit,y
    asl a
    asl a
mark:
    ora v_row
    sta v_row
next:
    dex
    bpl cls
    ; parità in accento: almeno una in luce, nessuna vuota
    lda v_row
    lsr a
    lsr a
    eor #$ff
    and v_row
    and #3
    sta wm_el
    rts
.endproc
ws_th:    .repeat 8, c
          .byte ((c * 11) >> 2) + 16
          .endrepeat
; per classe: parità della colonna di celle e i suoi due bit nel carattere (le classi delle colonne
; 0-3 di una cella pari sono 0, 5, 2, 7, di una dispari 4, 1, 6, 3)
ws_par:   .byte 0, 1, 0, 1, 1, 0, 1, 0
ws_bits:  .byte $C0, $30, $0C, $03, $C0, $30, $0C, $03

; C = 1 se la racchetta di pi_side fa il salto del TELEPORT. X e Y restano.
.proc warp_here
    lda wp_on
    beq no
    lda pi_side
    cmp wp_side
    beq yes
no: clc
    rts
yes:
    sec
    rts
.endproc

; La maschera del salto (dopo next_sprites): rettangolo di celle dagli sprite dell'astronave che
; salta, gli sprite 2-5 della sua metà dietro i caratteri, le celle rifatte quando cambiano il
; rettangolo o la scacchiera (rot_wel, tremolio, colore). Senza salto le celle tornano vuote.
.proc warp_place
    lda wp_on
    bne :+
    jmp mask_off
:   lda wp_side
    bne top
    lda shb_en                  ; in basso
    and #1 << SPN_HI
    jeq hidden
    lda #%1111 << SPN_HI
    sta shb_pri
    ldx shb_y + SPN_HI
    lda shb_msb
    ldy shb_x + SPN_HI
    jmp have
top:
    lda sh_enable
    and #1 << SPN_HI
    jeq hidden
    lda #%1111 << SPN_HI
    sta sh_pri
    ldx sh_y + SPN_HI
    lda sh_msb
    ldy sh_x + SPN_HI
have:
    ; u = x - SPR_X0 + 8 + rot_off del tipo: il primo pixel dell'astronave + 8 (9 bit, mai sotto
    ; zero); le celle vanno da lì a 47 - 2 * rot_off pixel più in là (la sua lunghezza)
    and #1 << SPN_HI
    cmp #1                      ; C = nono bit
    lda #0
    rol a
    sta m_t
    sty m_lo
    lda wp_side
    asl a
    asl a
    tay
    lda nx_kind,y
    tay
    lda rot_off,y
    sta wm_off
    clc
    adc m_lo
    sta m_lo
    lda m_t
    adc #0
    sta m_t
    lda m_lo
    sec
    sbc #SPR_X0 - 8
    sta m_lo
    lda m_t
    sbc #0
    sta m_t
    lsr a                       ; (C = bit 8 di u)
    lda m_lo
    ror a
    lsr a
    lsr a                       ; u / 8
    sec
    sbc #1
    bcs :+
    lda #0
:   sta wm_n0                   ; prima colonna di celle
    lda wm_off
    asl a
    eor #$ff
    sec
    adc #47                     ; 47 - 2 * rot_off
    clc
    adc m_lo
    sta m_lo
    lda m_t
    adc #0
    lsr a
    lda m_lo
    ror a
    lsr a
    lsr a
    sec
    sbc #1
    cmp #ROT_FIELD_COLS
    bcc :+
    lda #ROT_FIELD_COLS - 1
:   sta wm_n1                   ; ultima
    ; righe: v = y - SPR_Y0 + 24 (mai sotto zero)
    txa
    sec
    sbc #SPR_Y0 - 24
    tax
    lsr a
    lsr a
    lsr a
    sec
    sbc #3
    bcs :+
    lda #0
:   sta wm_m0
    txa
    clc
    adc #20
    lsr a
    lsr a
    lsr a
    sec
    sbc #3
    cmp #25
    bcc :+
    lda #24
:   sta wm_m1
    ; scacchiera: colonne che possono essere in accento, tremolio, colore del personaggio
    lda wp_side
    asl a
    asl a
    tax
    jsr om_white
    asl a
    asl a
    asl a
    sta wm_nk
    lda wm_el
    beq :+
    ora wm_nk
:   sta wm_nk
    ; stesso rettangolo e stessa scacchiera: niente da fare
    lda wm_n0
    cmp wm_c0
    bne redo
    lda wm_n1
    cmp wm_c1
    bne redo
    lda wm_m0
    cmp wm_r0
    bne redo
    lda wm_m1
    cmp wm_r1
    bne redo
    lda wm_nk
    cmp wm_ck
    bne fill
hidden:
    rts
redo:
    lda #WM_LATE                ; frame già avanti: le celle al frame dopo (anche le prime: il
    jsr frame_after             ; frame del tick del TELEPORT è già pesante)
    bcs hidden
    jsr mask_off
    lda wm_n0
    sta wm_c0
    lda wm_n1
    sta wm_c1
    lda wm_m0
    sta wm_r0
    lda wm_m1
    sta wm_r1
    jmp fill_now                ; (il controllo del tempo l'ha già fatto redo)
fill:
    lda #WM_LATE
    jsr frame_after
    bcs hidden
fill_now:
    lda wm_nk
    sta wm_ck
    jsr mask_on
    rts
.endproc
WM_LATE = (TV_BUDGET - 4000) / TV_LCYC   ; togliere e rimettere le celle: fino a circa 2.500 cicli

; Fine del salto (GAME OVER): via la maschera, sprite di nuovo davanti ai caratteri.
.proc warp_end
    lda #0
    sta wp_on
    sta sh_pri
    sta shb_pri
    jmp mask_off
.endproc

; Le celle del rettangolo: quelle vuote prendono la maschera (colore di prima in wm_save, 8 per
; riga), quelle già della maschera si rifanno, le altre restano ($FF in wm_save). In una riga
; possono essere in accento solo le colonne di celle con (colonna + riga) pari, cioè con la parità
; della riga, e solo se rot_wel lo permette (i puntini si alternano nei caratteri, le celle
; restano): per riga due coppie carattere e colore, una per parità, scritte in due passate. Usa t0.
.proc mask_on
    jsr wm_start
rows:
    ; le due coppie della riga
    lda #WM_CH
    sta wm_chr
    lda #WM_CH + 1
    sta wm_chr + 1
    lda #0
    sta wm_col
    sta wm_col + 1
    lda wm_rr
    and #1
    tay                         ; parità che può essere in accento
    lda wm_ck
    and wm_bit,y
    beq :+
    tya
    ora #WM_CH + 2
    sta wm_chr,y
    lda wm_ck
    lsr a
    lsr a
    lsr a
    sta wm_col,y
:   jsr wm_row
    ldx #0                      ; passata: parità della colonna di celle
pass:
    lda wm_chr,x
    sta pc + 1
    lda wm_col,x
    sta pk + 1
    txa
    eor wm_c0
    and #1
    tay                         ; prima cella con quella parità
    cpy wm_w
    bcs pdone
cell:
    lda (ptr),y
    beq fresh                   ; (CH_BLANK)
    cmp #WM_CH
    bcc skip
    cmp #WM_CH + 4
    bcs skip
    lda (t0),y                  ; della maschera: si rifà
    bpl put
skip:
    lda #$ff
    sta (t0),y
    bne nx
fresh:
    lda (ptr2),y
    and #$0f
    sta (t0),y
put:
pc: lda #0
    sta (ptr),y
pk: lda #0
    sta (ptr2),y
nx: iny
    iny
    cpy wm_w
    bcc cell
pdone:
    inx
    cpx #2
    bcc pass
    jsr wm_next
    jcc rows
    rts
.endproc
wm_bit: .byte 1, 2
.assert CH_BLANK = 0, error, "mask_on: la cella vuota è il carattere 0"

; Le celle della maschera tornano vuote con il loro colore; niente rettangolo.
.proc mask_off
    lda wm_c0
    cmp #$ff
    beq done
    jsr shots_erase             ; prima i fasci: un fascio sopra la maschera la rimetterebbe
    jsr wm_start
rows:
    jsr wm_row
cell:
    lda (t0),y
    bmi nx
    lda (ptr),y
    cmp #WM_CH
    bcc nx
    cmp #WM_CH + 4
    bcs nx
    lda #CH_BLANK
    sta (ptr),y
    lda (t0),y
    sta (ptr2),y
nx: iny
    cpy wm_w
    bcc cell
    jsr wm_next
    bcc rows
    lda #$ff
    sta wm_c0
done:
    rts
.endproc

; Inizio di mask_on e mask_off: celle per riga (wm_w), prima riga, (t0) su wm_save della riga.
.proc wm_start
    lda wm_c1
    sec
    sbc wm_c0
    clc
    adc #1
    sta wm_w
    lda wm_r0
    sta wm_rr
    lda #<wm_save
    sta t0
    lda #>wm_save
    sta t0+1
    rts
.endproc

; Riga dopo ((t0) 8 byte più in là): C = 1 se era l'ultima.
.proc wm_next
    lda wm_rr
    cmp wm_r1
    bcs done
    inc wm_rr
    lda t0
    clc
    adc #8
    sta t0
    bcc done                    ; (C = 0)
    inc t0+1
    clc
done:
    rts
.endproc

; (ptr) e (ptr2) sulla riga wm_rr dello schermo e dei colori, dalla colonna wm_c0; Y = 0.
.proc wm_row
    ldy wm_rr
    lda row_lo,y
    clc
    adc wm_c0
    sta ptr
    sta ptr2
    lda row_hi,y
    adc #0
    sta ptr+1
    clc
    adc #>($d800 - SCREEN)
    sta ptr2+1
    ldy #0
    rts
.endproc

; variabili della maschera (nella RAM del programma: BSS è pieno)
wm_c0:   .byte $ff              ; rettangolo: colonne e righe di celle ($FF nessuno)
wm_c1:   .res 1
wm_r0:   .res 1
wm_r1:   .res 1
wm_ck:   .res 1                 ; scacchiera: bit 0-1 colonne in accento, 3-6 colore
wm_n0:   .res 1                 ; il rettangolo e la scacchiera di adesso
wm_n1:   .res 1
wm_m0:   .res 1
wm_m1:   .res 1
wm_nk:   .res 1
wm_rr:   .res 1                 ; riga in corso
wm_w:    .res 1                 ; celle per riga del rettangolo (mask_on, mask_off)
wm_b0:   .res 2                 ; il passo (warp_step): caratteri neri e in accento per parità,
wm_l0:   .res 2                 ; parità che possono essere in accento
wm_b1    = wm_b0 + 1
wm_l1    = wm_l0 + 1
wm_el:   .res 1
wm_off:  .res 1                 ; rot_off del tipo di chi salta
wm_chr:  .res 2                 ; carattere e colore della riga per parità della colonna di celle
wm_col:  .res 2
wm_save: .res WM_CELLS          ; colore di prima delle celle ($FF: non della maschera)

; A = distanza in pixel della palla dal bordo di chi salta, in pixel del campo di oggi (* 8 / 5),
; accelerata verso la metà campo quando la racchetta è in dash (2x a 30 pixel dal bordo, 4x a 60:
; i 48 e 96 di oggi) così l'animazione finisce prima che la palla arrivi alla racchetta. Da metà
; campo in su $FF.
.proc warp_d
    ldy wp_side
    bne right
    lda ball_x+2                ; in basso (sinistra del core): x
    cmp #ROT_HALF
    bcs far
    sta m_lo
    lda pad_x+2
    jmp scale
right:
    lda #<(P_WIDTH >> 16)       ; in alto: larghezza - x
    sec
    sbc ball_x+2
    cmp #ROT_HALF
    bcs far
    sta m_lo
    lda #<(P_WIDTH >> 16)
    sec
    sbc pad_x+4+2
scale:
    cmp #30
    bcc done
    tax
    lda #ROT_HALF
    sec
    sbc m_lo
    sta m_t                     ; distanza percorsa oltre la metà campo
    asl m_t                     ; dash normale: 2x (al più 200)
    cpx #60
    bcc :+
    asl m_t                     ; dash lungo (RUSH): 4x
    bcs sat
:   lda m_t
    cmp #ROT_HALF
    bcc :+
sat:
    lda #ROT_HALF
:   sta m_t
    lda #ROT_HALF
    sec
    sbc m_t
    sta m_lo
done:
    ; * 8 / 5 come d + d/2 + d/16 + d/32 (al più 1 in meno)
    lda m_lo
    lsr a
    sta m_t
    lsr a
    lsr a
    lsr a
    sta v_n
    lsr a
    clc
    adc v_n
    adc m_t
    adc m_lo
    rts
far:
    lda #$ff
    rts
.endproc
.assert ROT_HALF * 8 / 5 = ROT_SUNK .and ROT_HALF + ROT_HALF / 2 + ROT_HALF / 16 + ROT_HALF / 32 < ROT_SUNK + 1, error, "salto del TELEPORT: metà campo diversa da ROT_SUNK"
.assert ROT_HALF * 2 < 256, error, "warp_d: la distanza 2x in un byte"

; ------------------------------------------------------------------------------------ fascia

hud_row: .byte 15, 7            ; riserve: chi gioca in basso (sinistro) e in alto (destro)
name_row: .byte 23, 1           ; nomi dei tipi
tag_row: .byte 21, 5            ; CPU, 1P, 2P: accanto alla riga in basso del punteggio
ROT_TAG_COL = ROT_HUD_COL + 6

; Nomi dei tipi (NEXT, nel colore del tipo; OMEGA il suo) e chi gioca (CPU, 1P, 2P) nella fascia,
; all'inizio della partita e quando OMEGA cambia forma.
.proc rot_names
    lda m_players
    cmp #2
    beq :+
    rts
:   ldx #1
side:
    stx pi_side
    lda m_next
    beq tag
    txa
    asl a
    asl a
    tax                         ; lato * 4
    lda nx_kind,x
    cpx nx_morph
    bne :+
    lda #7                      ; OMEGA (kind_names: dopo i sette tipi)
:   pha
    asl a
    tay
    lda kind_names,y
    sta ptr2
    lda kind_names+1,y
    sta ptr2+1
    ldy pi_side
    lda name_row,y
    tay
    ldx #ROT_HUD_COL
    jsr print_str
    pla
    tax
    lda rot_name_col,x
    pha
    lda #8
    sta v_n
    ldy pi_side
    ldx name_row,y
    ldy #ROT_HUD_COL
    pla
    jsr color_span
tag:
    ; CPU, se no 1P a sinistra (in basso) e 2P a destra (in alto)
    lda pi_side
    asl a
    asl a
    cmp cpu_side
    bne :+
    ldy #4                      ; "CPU"
    bne :++
:   ldy pi_side
:   lda rot_tags,y
    sta ptr2
    lda rot_tags_hi,y
    sta ptr2+1
    ldy pi_side
    lda tag_row,y
    tay
    ldx #ROT_TAG_COL
    jsr print_str
    lda #3
    sta v_n
    ldy pi_side
    ldx tag_row,y
    ldy #ROT_TAG_COL
    lda #COL_MGRAY
    jsr color_span
    ldx pi_side
    dex
    bpl side
    rts
.endproc
rot_name_col: .byte COL_YELLOW, COL_ORANGE, COL_RED, COL_PURPLE, COL_DGREEN, COL_CYAN, COL_LBLUE, COL_RED   ; (OMEGA rosso)
rt_1p:  .byte "1P ", 0
rt_2p:  .byte "2P ", 0
rt_cpu: .byte "CPU", 0
rot_tags:    .byte <rt_1p, <rt_2p, 0, 0, <rt_cpu
rot_tags_hi: .byte >rt_1p, >rt_2p, 0, 0, >rt_cpu

; ------------------------------------------------------------------------------------ GUARDIAN

; Muro del GUARDIAN dietro la racchetta (come oggi non si vede: lampeggia per BAR_FLASH frame solo il
; settore che rimanda la palla, nel colore del GUARDIAN): una riga di caratteri, la 24 per chi gioca
; in basso (CH_BAR_R, righe 194-195) e la 0 per chi gioca in alto (CH_BAR_L, righe 4-5). Ogni
; colonna prende il settore del suo centro (g_sector, sulla y del core); si riscrivono solo le
; colonne dei settori cambiati.
.proc draw_barrier
    lda nx_kind
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
    tay
    lda nx_kind,y
    cmp #K_GUARDIAN
    jne next_side
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
    sta m_t
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
    jeq next_side
    sta m_b
    jsr frame_late_small
    jcs next_side
    jsr shots_erase
    ldx pk_p
    lda m_t
    sta bar_shown,x
    ldy bar_rows,x
    lda row_lo,y
    sta ptr
    sta ptr2
    lda row_hi,y
    sta ptr+1
    clc
    adc #>($d800 - SCREEN)
    sta ptr2+1
    lda bar_glyph,x
    sta v_row
    lda #0
    sta v_col
    lda #4
    sta v_n                     ; y del centro della colonna nel core
col:
    lda v_n
    jsr g_sector
    bit m_b
    beq skip
    and m_t
    beq blank
    ldy v_col
    lda v_row
    sta (ptr),y
    lda #COL_LBLUE
    sta (ptr2),y
    bne skip
blank:
    ldy v_col
    lda #CH_BLANK
    sta (ptr),y
skip:
    lda v_n
    clc
    adc #8
    sta v_n
    inc v_col
    lda v_col
    cmp #ROT_FIELD_COLS
    bne col
next_side:
    ldx pk_p
    inx
    cpx #2
    jne side_loop
    rts
.endproc
bar_rows:  .byte 24, 0
bar_glyph: .byte CH_BAR_R, CH_BAR_L

; ------------------------------------------------------------------------------------ bullet time, STEER

; Colori del bullet time (X: 0 senza, 1 con): la mezzeria (riga 12, dove ci sono i suoi caratteri) e
; i punteggi nella fascia (righe 3-5 e 19-21, colonne 31-36).
.proc bullet_look
    jsr frame_late
    bcs done
    stx bl_on
    lda look_color,x
    sta m_t
    jsr shots_erase
    ldy #ROT_FIELD_COLS - 1
:   lda SCREEN + ROT_LINE_ROW * 40,y
    cmp #CH_LINE_L
    bne :+
    lda m_t
    sta $d800 + ROT_LINE_ROW * 40,y
:   dey
    bpl :--
    ldx #5
digits:
    lda look_rows,x
    tay
    lda row_lo,y
    sta ptr2
    lda row_hi,y
    clc
    adc #>($d800 - SCREEN)
    sta ptr2+1
    lda m_t
    ldy #ROT_HUD_COL + 5
:   sta (ptr2),y
    dey
    cpy #ROT_HUD_COL
    bcs :-
    dex
    bpl digits
done:
    rts
.endproc
look_rows: .byte 3, 4, 5, 19, 20, 21

; Segni di STEER di st_drawn (1 chi guida in basso, 5 in alto): A = 1 disegna, 0 cancella. Chi guida
; dal basso guida fino alla x 3/4 del campo (righe 49-50, riga di caratteri 6), dall'alto fino a 1/4
; (righe 149-150, riga 18): un tratto sul bordo sinistro e uno sul destro del campo.
.proc steer_marks
    sta m_t
    jsr shots_erase
    ldy #6
    lda #CH_STEER_TOP_R
    ldx #CH_STEER_TOP_L
    pha
    lda st_drawn
    cmp #1
    beq :+
    ldy #18
    pla
    lda #CH_STEER_BOTTOM_R
    ldx #CH_STEER_BOTTOM_L
    pha
:   pla
    sta m_lo
    stx m_b
    lda row_lo,y
    sta ptr
    sta ptr2
    lda row_hi,y
    sta ptr+1
    clc
    adc #>($d800 - SCREEN)
    sta ptr2+1
    ldy #0
    lda m_t
    beq erase
    lda m_lo
    sta (ptr),y
    lda #COL_YELLOW
    sta (ptr2),y
    ldy #ROT_FIELD_COLS - 1
    lda m_b
    sta (ptr),y
    lda #COL_YELLOW
    sta (ptr2),y
    rts
erase:
    lda #CH_BLANK
    sta (ptr),y
    ldy #ROT_FIELD_COLS - 1
    sta (ptr),y
    rts
.endproc

; Aloni di SLOW: già disegnati dal generatore (ROT_RINGS), si copiano e basta (oggi fx_copy li
; disegna a quadrati con spin_plot, circa 12.000 cicli per immagine).
.proc fx_copy
    lda fx_wait                 ; i primi frame della partita hanno già molto da fare
    beq :+
    dec fx_wait
    rts
:   ldx #2 * 64 - 1
:   lda rot_rings,x
    sta $C000 + SP_RING0 * 64,x
    dex
    bpl :-
    lda #FX_SPRITES
    sta fx_pages
    rts
.endproc
rot_rings: .byte ROT_RINGS
.assert FX_SPRITES = 2, error, "aloni: due immagini"

; GUARDIAN con i settori persi A (bit 0 il settore in alto nel core: il corso più a destra), lato
; pi_side. La pagina 3 del lato (dalla cartuccia la posa di sempre) ha grigi i corsi di pd_var: qui
; se ne sistema uno per frame, il primo diverso da A. Perso: via il bianco hires e il multicolore
; %01 nelle righe dello scudo; ripreso: i suoi bit di nuovo dalla pagina 0 (i corsi si dividono i
; byte, quelli degli altri restano). Circa 2.000 cicli, solo se il frame ha tempo (LATE_GUARD):
; C = 1 se no. Usa ptr, v_n, v_col, v_row, m_lo; ptr2 e m_t restano.
.proc guard_page
    sta v_n
    lda #LATE_GUARD
    jsr frame_after
    bcs out
    ldy pi_side
    lda rot_hi,y                ; pagina 0 del lato (da cui si riprende), poi la 3
    sta src0 + 2
    sta src1 + 2
    clc
    adc #3
    sta ptr+1
    lda #0
    sta ptr
    lda v_n
    eor pd_var,y                ; corsi da sistemare (non zero: il chiamante li ha confrontati)
    ldx #0                      ; bit k il corso k (il settore k: 0 in alto nel core, il corso più a destra)
find:
    lsr a
    bcs found
    inx
    cpx #5
    bcc find
    clc
out:
    rts
found:
    stx v_col
    lda g_bit,x
    eor pd_var,y
    sta pd_var,y
    and g_bit,x
    sta v_n                     ; non zero: il corso diventa grigio; zero: torna com'era
    lda g_row0,y                ; righe dello scudo: in basso dalla 0, in alto dalla 21 - ROT_G_ROWS
    sta v_row
row:
    ; i 6 byte della riga: hires (sprite 0 e 1) e multicolore (2 e 3)
    lda #0
    sta m_lo
byte:
    lda v_col
    asl a
    adc v_col
    asl a                       ; corso * 6 (C = 0)
    adc m_lo
    tax                         ; maschere: corso * 6 + byte
    ldy m_lo
    lda g_byte,y                ; scostamento del byte nella pagina: sprite * 64 + colonna
    clc
    adc v_row
    tay
    lda v_n
    beq back
    lda (ptr),y                 ; hires: via il bianco del corso
    and g_hik,x
    sta (ptr),y
    tya
    clc
    adc #128                    ; il multicolore dello stesso byte, due sprite più in là
    tay
    lda (ptr),y
    and g_mck,x
    ora g_lo,x                  ; %01, grigio chiaro
    sta (ptr),y
    jmp next_byte
back:
    ; i bit del corso dalla pagina 0, gli altri dalla 3: p0 ^ ((p0 ^ p3) & maschera)
    jsr merge                   ; hires (maschera g_hik)
    tya
    clc
    adc #128
    tay
    txa                         ; multicolore (maschera g_mck)
    clc
    adc #5 * 6                  ; (g_mck subito dopo g_hik)
    tax
    jsr merge
next_byte:
    inc m_lo
    lda m_lo
    cmp #6
    bne byte
    lda v_row
    clc
    adc #3
    sta v_row
    ldy pi_side
    cmp g_row_end,y
    bne row
    clc
    rts
merge:
    lda (ptr),y
src0:
    eor $E100,y
    and g_hik,x
src1:
    eor $E100,y
    sta (ptr),y
    rts
.endproc
rot_hi:    .byte >ROT_PAGES, >ROT_PAGES + 4
g_row0:    .byte 0, (21 - ROT_G_ROWS) * 3
g_row_end: .byte ROT_G_ROWS * 3, 21 * 3
g_byte:    .byte 0, 1, 2, 64, 65, 66
g_bit:     .byte 1, 2, 4, 8, 16    ; per corso, il bit del settore
g_hik:     .byte ROT_G_HIK
g_mck:     .byte ROT_G_MCK
g_lo:      .byte ROT_G_LO
.assert g_mck - g_hik = 5 * 6 .and g_lo - g_mck = 5 * 6, error, "GUARDIAN: maschere di 5 corsi da 6 byte"
