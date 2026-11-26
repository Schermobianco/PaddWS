; Schermo VS della presentazione di CHALLENGE (4.5.0), come rust/game/src/challenge_ui.rs `Stage::vs`:
; la seconda parte della presentazione, dopo quella a celle con la voce (intro.s), al posto delle
; entrate animate dei singoli avversari. Bitmap a $E000 con i colori a $C000 (MODE_HOWTO): in
; cima la scala e il livello, i due ritratti ognuno dalla parte in cui gioca (pannelli della scelta
; della racchetta, kpick.s; OMEGA svelato dai suoi), VS che si stampa a 4x, 3x e 2x, il campo con la
; rete e le due racchette vere (sprite 3 e 4, pad_image), i nomi, i motti scritti una lettera per
; frame (quello dell'avversario grigio), le icone dei bonus di tutti e due, FIRST TO e i punti.
;
; Le righe di celle KV_MC_ROW0-KV_MC_ROW1 (ritratti, VS, rete) sono in bitmap multicolor, il resto in
; hires (le scritte), con lo split del raster di kpick.s (kv_split): dei ritratti le prime 12 righe,
; dalla riga 2 (la riga 1 è il livello). La rete disegnata come in hires ($01 e $80 nelle colonne 19
; e 20) in multicolor è bianca nella coppia 158-159 e nera nell'altra. Le copie dalla cartuccia
; (kv_bytes) non spengono gli interrupt: con la ROM del KERNAL accesa lo split passa da $0314.
;
; Semplificazioni rispetto al PC: i ritratti non scivolano dentro ma si scoprono una colonna di
; celle per frame dal bordo dello schermo (spostarli costerebbe troppo), lo schermo non trema, i
; punti stanno nella riga 23 (intro_hud) invece che nella 24.
;
; Dove sta. Il codice gira a $C400 (segmento KVCODE, al posto della parte comune della
; presentazione), nella prima pagina della riga 24 della bitmap (KVCODE2, nera su nera) e in 18 celle
; delle righe 14 e 15 (KVCODE4 e KVCODE5, nere su nere, copiate a schermo spento con i colori):
; vs_enter (challenge.s) copia i primi due quando la voce ha finito. Dati nel banco KP_BANK + KV_BANK_REL
; (tools/gen_c64_portraits.py): colori, le tre scritte VS, i pannelli di OMEGA; ritratti e nomi dei
; tipi dai pannelli della scelta. La bitmap copre il file voce, il player, READY, il tema, GO e le
; tabelle dei quadrati: alla fine, a schermo spento, si ricaricano (il file voce del primo livello
; per GO, che solo lui porta, poi quello dell'avversario per il tema) e si torna a intro_scene
; (intro_go), che finisce come sempre. La cartuccia si accende solo per le copie (kv_bytes): a
; $8000-$BFFF ci sono anche le tabelle del programma.

KV_RUN    = $C400
KV_BANK   = KP_BANK + KV_BANK_REL
KV_ROW24  = $FE00               ; KVCODE2: la riga 24 della bitmap, colonne 0-31
KV_CHARS  = $CA00               ; KVCODE3: i caratteri 64-153 (CHARSET + 64 * 8)
.assert KV_CHARS = CHARSET + 8 * BIG2_FIRST, error, "VS: il codice non al posto delle lettere 2x"

; tempi in frame a 50 Hz dallo schermo acceso (sul PC a 60: VS_* di challenge_ui.rs)
KV_WIPE_AT   = 4                ; ritratti: una colonna di celle per frame
KV_STAMP_AT  = 20               ; VS a 4x, 3x, 2x (un colpo)
KV_STAMP3_AT = 23
KV_STAMP2_AT = 26
KV_NET_AT    = 28               ; rete: una riga di trattini per frame
KV_PADS_AT   = 35
KV_NAME_AT   = 37               ; nome, motto e icone del giocatore; quelli dell'avversario dopo
KV_THEIRS    = 5
KV_TAG_AT    = 45
KV_ICONS_AT  = 62
KV_ICON_GAP  = 5
KV_FIRST_AT  = 83
KV_END       = 150
KV_PAD_CY    = 6 * 8 + 36       ; centro del campo (riga in pixel)
KV_S         = SPR_Y0 + KV_PAD_CY   ; astronavi in due metà: riga del cambio di sprite (kv_split)
KV_TOP       = KV_S - PAD_ROWS
.assert (KV_S & 7) <> 3 .and ((KV_S - 1) & 7) <> 3, error, "VS: il cambio di sprite in una badline"
KV_NET_ROW   = 6
KV_NET_ROWS  = KV_MC_ROW1 + 1 - KV_NET_ROW     ; (solo nelle righe multicolor)
; split del raster: righe di pixel vuote del cambio (prima e dopo le righe multicolor)
KV_LINE_ON  = 51 + KV_MC_ROW0 * 8 - 1
KV_LINE_OFF = 51 + (KV_MC_ROW1 + 1) * 8
KV_SHOW      = 11               ; kv_step: caricamento (0-10), lo schermo, poi KV_RELOAD e dopo
KV_RELOAD    = KV_SHOW + 1
KV_DUEL      = IM_TRAIN + 1     ; kv_mode: la sfida (gli altri sono IM_* di intro_hud)

.segment "KVCODE"
    jmp kv_enter                ; KV_RUN: da vs_enter
    jmp kv_tick                 ; KV_RUN + 3: un frame (intro_scene, con in_vs)

kv_f:    .byte 0                ; frame dallo schermo acceso
kv_step: .byte 0
kv_me:   .byte 0                ; lato del giocatore (0 sinistra, 1 destra)
kv_kind: .byte 0, 0             ; tipo per lato (OMEGA_KIND: OMEGA)
kv_mode: .byte 0                ; IM_* (intro_hud)
kv_bank: .byte 0                ; banco della copia (kv_bytes)
kv_n:    .byte 0                ; temporanee
kv_c:    .byte 0
kv_r:    .byte 0
kv_s:    .byte 0
kv_y:    .byte 0
kv_t:    .byte 0
kv_hi:   .byte 0

; ------------------------------------------------------------------------------------ inizio

.proc kv_enter
    lda #1
    sta in_vs
    lda #0
    sta sh_enable
    sta $d01b                   ; sprite davanti ai caratteri
    lda #$c8
    sta $d016
    lda #MODE_OFF
    sta sh_mode
    lda #1                      ; niente math_step nella bitmap
    sta math_ready
    lda cg_active               ; la sfida: P1 a sinistra, P2 a destra, con le loro racchette
    cmp #CG_DUEL
    bne ladder
    lda #KV_DUEL
    sta kv_mode
    lda #0
    sta kv_me
    lda cfg_kinds
    sta kv_kind
    lda cfg_kinds+4
    sta kv_kind+1
    rts
ladder:
    ; il giocatore dal suo lato, l'avversario dall'altro
    lda ch_side
    lsr a
    lsr a
    sta kv_me
    tay
    lda ch_kinds,y
    sta kv_kind,y
    tya
    eor #1
    tax
    ldy ch_level
    lda rung_kind,y
    cpy #CH_OMEGA
    bcc :+
    lda #OMEGA_KIND
:   sta kv_kind,x
    rts
.endproc

; ------------------------------------------------------------------------------------ frame

.proc kv_tick
    lda kv_step
    cmp #KV_SHOW
    beq live
    bcc :+
    jmp kv_reload
:   cmp #0
    bne :+
    ; il codice dell'animazione al posto dei caratteri 64-159 (KVCODE3; la riga 24 al passo dopo)
    lda #KV_CHARSP
    sta ef_src+2
    lda #KV_BANK
    ldx #3
    ldy #>KV_CHARS
    jsr ef_copy
    inc kv_step
    rts
:   jmp kv_load
live:
    jsr ch_phases               ; (ch_elapsed, per ch_skip)
    lda kv_mode
    cmp #KV_DUEL
    beq :+
    jsr ch_join                 ; nuovo sfidante (i file della scala li ricarica la sfida)
    bcc :+
    jsr kv_split_off
    jsr math_invalidate
    jmp enter_challenger
:   jsr ch_skip
    bcs over
    inc kv_f
    lda kv_f
    cmp #KV_END
    bcs over
    jmp kv_anim
over:
    jsr kv_split_off
    lda #0
    sta sh_enable
    lda #MODE_OFF
    sta sh_mode
    inc kv_step
    rts
.endproc

; ------------------------------------------------------------------------------------ copie

; Sorgente: kv_base + A in kv_src.
.proc kv_from
    clc
    adc kv_base
    sta kv_src+1
    lda kv_base+1
    adc #0
    sta kv_src+2
    rts
.endproc
kv_base: .word 0                ; inizio della riga del pannello nella finestra della cartuccia

; Y byte da kv_src a (ptr), dal banco kv_bank: la cartuccia accesa solo qui (modo a 16K, $01 = $37;
; le scritture vanno nella RAM anche sotto il KERNAL e nella Color RAM). Mai con una voce. Interrupt
; accesi: lo split passa dal KERNAL (kv_split).
.proc kv_bytes
    lda kv_bank
    sta EF_BANK
    lda #$37
    sta $01
    lda #EF_16K
    sta EF_MODE
    dey
loop:
src:
    lda $ffff,y
    sta (ptr),y
    dey
    bpl loop
    lda #EF_OFF
    sta EF_MODE
    lda #$35
    sta $01
    rts
.endproc
kv_src = kv_bytes::src

; Banco X (da KP_BANK) e pagina A dell'inizio dei dati da copiare, in kv_bank e kv_base.
.proc kv_at
    sta kv_base+1
    lda #0
    sta kv_base
    txa
    clc
    adc #KP_BANK
    sta kv_bank
    rts
.endproc

; Fine, a schermo spento, un caricamento per frame: il file voce del primo livello (il player,
; READY, e GO con gli NMI, che copia al quarto frame), quello dell'avversario (il suo tema; OMEGA:
; la prima sezione della sua canzone), le due metà delle lettere 2x (al posto del codice
; dell'animazione); poi intro_scene finisce la presentazione (intro_go).
.proc kv_reload
    lda kv_step
    cmp #KV_RELOAD + 2
    bcs twox
    ldx kv_mode                 ; la sfida: il tema di un avversario a caso (con player e GO)
    cpx #KV_DUEL
    bne :+
    jsr ch_duel_theme
    lda #KV_RELOAD + 2
    sta kv_step
    rts
:   cmp #KV_RELOAD
    bne theirs
    lda rung_kind
    jsr ef_voice
    ldx #4
:   txa
    pha
    jsr VOICE_TICK
    pla
    tax
    dex
    bne :-
    inc kv_step
    lda ch_level                ; (al primo livello il tema è già questo)
    bne done
    inc kv_step
    rts
theirs:
    ldx ch_level
    lda rung_kind,x
    cpx #CH_OMEGA
    bcc :+
    lda #OM_BANK - VOICE_BANK0
:   jsr ef_voice
    ldx ch_level
    cpx #CH_OMEGA
    bcc theme
    lda #>om_s0
    sta ef_src+2
    lda #OM_BANK
    ldx #(om_s1 - om_s0) / 256
    ldy #>THEME_BASE
    jsr ef_copy
    inc kv_step
    rts
theme:
    jsr VOICE_TICK              ; primo frame del file: il tema a THEME_BASE
    inc kv_step
    rts
twox:
    sbc #KV_RELOAD + 2          ; (C = 1) 0 la prima metà, 1 la seconda, 2 la fine
    cmp #2
    beq go
    sec
    jsr pick_chars
    inc kv_step
    rts
go:
    jsr math_invalidate
    lda #MODE_TEXT
    sta sh_mode
    lda #0
    sta in_vs
    jmp intro_go
done:
    rts
.endproc

; Caricamento a schermo spento, un passo per frame: la bitmap pulita (6 pagine per frame, non
; questa), i colori, la scala, la rete e le scritte, le immagini delle due racchette.
.proc kv_load
    lda kv_step
    cmp #6
    bcs copy
    cmp #1
    bne :+
    lda #KV_ROW24P              ; il codice della riga 24 (KVCODE2)
    sta ef_src+2
    lda #KV_BANK
    ldx #1
    ldy #>KV_ROW24
    jsr ef_copy
    lda kv_step
:   ; passi 1-5: pagine $E0 + 6 * (passo - 1) ... + 5 (fino a $FD); all'ultimo anche $FF00-$FF3F
    clc
    sbc #0                      ; (passo - 1)
    sta kv_n
    asl a
    adc kv_n
    asl a                       ; * 6
    adc #>$E000                 ; (C = 0)
    ldy #6
page:
    sta c0+2
    sta c1+2
    sta c2+2
    sta c3+2
    lda #0
    tax
:
c0: sta $ff00,x
c1: sta $ff40,x
c2: sta $ff80,x
c3: sta $ffc0,x
    inx
    cpx #64
    bne :-
    lda c0+2
    clc
    adc #1
    dey
    bne page
    cmp #>KV_ROW24
    bne :++
    lda #0                      ; $FF00-$FF3F (dopo, le variabili)
    ldx #63
:   sta $ff00,x
    dex
    bpl :-
:   inc kv_step
    rts
copy:
    bne draw
    ; colori (4 pagine)
    lda #KV_COLORS
    sta ef_src+2
    lda #KV_BANK
    ldx #4
    ldy #>SCREEN
    jsr ef_copy
    inc kv_step
    rts
draw:
    cmp #8
    jeq texts
    jcs pad
    ; le tre pagine della bitmap con le celle di KVCODE4 e KVCODE5 (lì la bitmap è ancora vuota:
    ; ritratti e nomi vengono dopo, la rete sta sopra)
    lda #KV_CODE4P
    sta ef_src+2
    lda #KV_BANK
    ldx #3
    ldy #>KV_CODE4
    jsr ef_copy
    lda kv_mode                 ; (la sfida senza scala)
    cmp #KV_DUEL
    beq net0
    ; scala (trattini di 2 celle, righe 1-5 delle celle, uno ogni 3 colonne dalla 10)
    ldy #10 * 8 + 1
rung:
    lda #$ff
    sta $E000,y
    sta $E001,y
    sta $E002,y
    sta $E003,y
    sta $E004,y
    sta $E008,y
    sta $E009,y
    sta $E00A,y
    sta $E00B,y
    sta $E00C,y
    tya
    clc
    adc #24
    tay
    cpy #10 * 8 + 1 + CH_LEVELS * 24
    bne rung
    ; rete: righe 2-6 delle celle, x 159 (colonna 19) e 160 (colonna 20)
net0:
    ldx #KV_NET_ROW
net:
    lda cell_row_lo,x
    sta ptr
    lda cell_row_hi,x
    sta ptr+1
    ldy #19 * 8 + 2
:   lda #$01
    sta (ptr),y
    tya
    clc
    adc #8
    tay
    lda #$80
    sta (ptr),y
    tya
    sec
    sbc #7
    tay
    cpy #19 * 8 + 7
    bne :-
    inx
    cpx #KV_NET_ROW + KV_NET_ROWS
    bne net
    inc kv_step
    rts
texts:
    ; in due frame (insieme non ci stanno nel frame NTSC): punti, poi livello e colori. Tra i due
    ; v_big resta $40, ed è il segno che il primo è fatto
    bit v_big
    bvs second
    lda #$40
    sta v_big
    lda kv_mode
    cmp #KV_DUEL
    bne :+
    ; la sfida: P1 e P2 sopra i ritratti, CHALLENGE al centro (niente punti)
    jsr print_at
    .byte 4, 0, "P1", 0
    jsr print_at
    .byte 34, 0, "P2", 0
    jsr print_at
    .byte 15, KV_LEVEL_ROW, "CHALLENGE", 0
    lda #0
    sta v_big
    inc kv_step
    rts
:   ; punti (SCORE e HI nella riga 23, i duelli vinti nella 0) e livello
    jsr intro_hud
    sta kv_mode
    rts
second:
    jsr kv_level
    lda #0
    sta v_big
    ; scala: battuti bianchi (non nell'allenamento), gli altri grigio scuro
    ldx #0
:   lda #COL_DGRAY << 4
    cpx ch_level
    bcs :+
    ldy kv_mode
    cpy #IM_TRAIN
    beq :+
    lda #COL_WHITE << 4
:   stx kv_n
    pha
    txa
    asl a
    adc kv_n
    tay
    pla
    sta SCREEN + 10,y
    sta SCREEN + 11,y
    inx
    cpx #CH_LEVELS
    bne :--
    ; il motto dell'avversario grigio
    lda kv_me
    eor #1
    tax
    lda kv_half,x
    tax
    ldy #20
    lda #COL_GRAY << 4
:   sta SCREEN + KV_TAG_ROW * 40,x
    inx
    dey
    bne :-
    inc kv_step
    rts
pad:
    ; l'immagine della racchetta del lato (passo 9 il sinistro, 10 il destro; OMEGA: ARCADE)
    sec
    sbc #9
    tay
    sty pi_side
    ldx kv_kind,y
    cpx #OMEGA_KIND
    bcc :+
    ldx #K_ARCADE
:
.ifdef ROTATED
    stx pi_kind
    txa                         ; (campo girato: le astronavi della partita, posa e serie del lato)
    ldx pi_side
    jsr ship_load
    ldy pi_side
    lda #1
    sta pd_dirty,y
    lda #$ff
    sta pd_n,y
.else
    txa                         ; la sua posa dalla cartuccia (pose_load di video.s, Y = lato): se
    jsr pose_load               ; non è il momento, al prossimo frame
    bcc :+
    rts
:
.endif
    inc kv_step
    lda kv_step
    cmp #KV_SHOW
    bne :+
    lda #MODE_HOWTO             ; si accende, con lo split
    sta sh_mode
    jmp kv_split_on
:   rts
.endproc
kv_half: .byte 0, 20

; Icona Y (0-2) dei bonus del lato X: la capsula 2x2 (cap_chars) nelle righe KV_ICON_ROW e dopo.
.proc kv_icon
    sty kv_r
    tya
    asl a
    adc kv_r                    ; Y * 3
    adc kv_icon_col,x
    sta kv_c
    ; bonus: il giocatore da ch_load, l'avversario dalla scala; nella sfida le scelte
    lda kv_mode
    cmp #KV_DUEL
    bne :+
    txa
    asl a
    adc kv_s                    ; (kv_s = X) lato * 3
    adc kv_r
    tay
    lda pk_chosen,y
    jmp got
:   lda kv_r
    cpx kv_me
    bne theirs
    ldy ch_side
    beq :+
    clc
    adc #3
:   tay
    lda ch_load,y
    jmp got
theirs:
    sta kv_n
    lda ch_level
    asl a
    adc ch_level
    adc kv_n
    tay
    lda rung_loadout,y
got:
    asl a
    asl a
    asl a
    sta kv_n                    ; cap_chars: bonus * 8
    lda #KV_ICON_ROW
    sta v_row
    jsr two
    inc v_row
two:
    lda kv_c
    sta p_col
    jsr one
one:
    ldx kv_n
    lda cap_chars,x
    inc kv_n
    jmp text_cell
.endproc
kv_icon_col: .byte 6, 26        ; prima capsula, poi una ogni 3 colonne

; FIRST TO n, grigio, nella riga KV_FIRST_ROW (i punti del livello sono una cifra).
.proc kv_first
    lda #$40
    sta v_big
    jsr print_at
    .byte 15, KV_FIRST_ROW, "FIRST TO", 0
    lda #0
    sta v_big
    ldx ch_level
    lda rung_points,x
    clc
    adc #'0' - 32
    tay
    lda font_map,y
    ldx #24
    stx p_col
    ldx #KV_FIRST_ROW
    stx v_row
    jmp text_cell
.endproc

; ------------------------------------------------------------------------------------ animazione

; Codice dell'animazione al posto dei caratteri 64-153 (KVCODE3: le lettere 2x e il nome della
; prima parte, che qui non si vedono; kv_reload rifà le lettere 2x): kv_tick lo copia al primo passo.
.segment "KVCODE3"

; Un frame dello schermo, a kv_f.
.proc kv_anim
    ; scala: quello di adesso giallo e grigio scuro, 8 frame ciascuno (non contro OMEGA né nella
    ; sfida)
    lda kv_mode
    cmp #KV_DUEL
    beq level
    lda ch_level
    cmp #CH_LEVELS
    bcs level
    lda #COL_YELLOW << 4
    tax
    lda kv_f
    and #8
    beq :+
    ldx #COL_DGRAY << 4
:   txa
    jsr kv_rung
level:
    ; FINAL LEVEL e SECRET LEVEL a tratti, 10 frame accesi e 10 spenti
    lda kv_mode
    cmp #IM_FINAL
    bne wipe
    lda kv_f
:   cmp #20
    bcc :+
    sbc #20
    bcs :-
:   ldy #COL_YELLOW << 4
    cmp #10
    bcc :+
    ldy #0
:   tya
    ldx #12
:   sta SCREEN + KV_LEVEL_ROW * 40 + 13,x
    dex
    bne :-
wipe:
    ; ritratti: la colonna k dal bordo dello schermo verso il centro
    lda kv_f
    sec
    sbc #KV_WIPE_AT
    bcc stamp
    cmp #KP_PANEL_W
    bcs land
    sta kv_c
    ldx #0
    jsr kv_column
    lda #KP_PANEL_W - 1
    sec
    sbc kv_c
    sta kv_c
    ldx #1
    jsr kv_column
    jmp stamp
land:
    bne stamp
    lda #EV_HIT                 ; posati
    jsr sid_fx
stamp:
    ; VS: 4x, 3x, poi si posa a 2x con un colpo
    ldx #2
:   lda kv_f
    cmp kv_stamp_at,x
    beq :+
    dex
    bpl :-
    bmi net
:   lda kv_stamp_page,x
    jsr kv_stamp
    lda kv_f
    cmp #KV_STAMP2_AT
    bne net
    lda #EV_SCORE
    jsr sid_fx
net:
    ; rete: la riga kv_f - KV_NET_AT accesa
    lda kv_f
    sec
    sbc #KV_NET_AT
    bcc pads
    cmp #KV_NET_ROWS
    bcs pads
    adc #KV_NET_ROW             ; (C = 0)
    tay
    lda row_lo,y
    sta ptr
    lda row_hi,y
    sta ptr+1
    lda #COL_WHITE << 4
    ldy #19
    sta (ptr),y
    iny
    sta (ptr),y
pads:
    lda kv_f
    cmp #KV_PADS_AT
    bne sides
    jsr kv_pads
sides:
    ldx #1
side:
    stx kv_s
    ; frame del lato: l'avversario KV_THEIRS dopo
    lda kv_f
    cpx kv_me
    beq :+
    sec
    sbc #KV_THEIRS
    bcc next
:   sta kv_t
    sec
    sbc #KV_NAME_AT
    bcc :+
    jsr kv_name
    ldx kv_s
:   lda kv_t
    sec
    sbc #KV_TAG_AT
    bcc next
    jsr kv_tag_char
    ldx kv_s
    ; icone: una ogni KV_ICON_GAP frame (ldy prima di sbc per non sovrascrivere il flag Z)
    ldy #0
    lda kv_t
    sec
    sbc #KV_ICONS_AT
    bcc next
:   beq icon
    iny
    cpy #3
    beq next
    sec
    sbc #KV_ICON_GAP
    bcs :-
    bcc next
icon:
    jsr kv_icon
next:
    ldx kv_s
    dex
    bpl side
    lda kv_f
    cmp #KV_FIRST_AT
    bne done
    jmp kv_first
done:
    rts
.endproc

kv_stamp_at:   .byte KV_STAMP_AT, KV_STAMP3_AT, KV_STAMP2_AT
kv_stamp_page: .byte KV_STAMP4, KV_STAMP3, KV_STAMP2

; La scritta VS (A pagina dei dati): le 8x4 celle del riquadro, 64 byte per riga.
.proc kv_stamp
    ldx #KV_BANK_REL
    jsr kv_at
    ldx #KV_STAMP_ROW
row:
    stx kv_r
    lda cell_row_lo,x
    clc
    adc #KV_STAMP_COL * 8
    sta ptr
    lda cell_row_hi,x
    adc #0
    sta ptr+1
    lda #0
    jsr kv_from
    ldy #KV_STAMP_W * 8
    jsr kv_bytes
    lda kv_base
    clc
    adc #KV_STAMP_W * 8
    sta kv_base
    ldx kv_r
    inx
    cpx #KV_STAMP_ROW + KV_STAMP_H
    bne row
    rts
.endproc

; Inizio del pannello del lato X in kv_bank e kv_base.
.proc kv_panel_at
    lda kv_kind,x
    cmp #OMEGA_KIND
    bcc :+
    lda kv_omega_page,x
    ldx #KV_BANK_REL
    jmp kv_at
:   cpx #0
    beq :+
    clc
    adc #7
:   tay
    ldx kv_vs_bank,y
    lda kv_vs_page,y
    jmp kv_at
.endproc
kv_omega_page: .byte KV_OMEGA0, KV_OMEGA1
kv_vs_bank: .byte KP_MC_BANK
kv_vs_page: .byte KP_MC_PAGE

; La riga del pannello dopo: kv_base + 110.
.proc kv_next_row
    lda kv_base
    clc
    adc #KP_MC_ROW_BYTES
    sta kv_base
    bcc :+
    inc kv_base+1
:   rts
.endproc

; Cella kv_c del pannello (riga kv_base) alla colonna kv_n e riga X dello schermo: bitmap, colore e
; Color RAM (nelle righe hires non conta).
.proc kv_cell
    stx kv_r
    lda kv_n                    ; colonna * 8: dalla colonna 32 oltre 255
    asl a
    asl a
    asl a
    tay
    lda #0
    rol a
    sta kv_hi
    tya
    clc
    adc cell_row_lo,x
    sta ptr
    lda cell_row_hi,x
    adc kv_hi
    sta ptr+1
    lda kv_c
    asl a
    asl a
    asl a
    jsr kv_from
    ldy #8
    jsr kv_bytes
    ldx kv_r                    ; colore: SCREEN + riga * 40 + colonna, dalla riga + 88 + kv_c
    lda row_lo,x
    clc
    adc kv_n
    sta ptr
    lda row_hi,x
    adc #0
    sta ptr+1
    lda kv_c
    adc #KP_PANEL_W * 8         ; (C = 0)
    jsr kv_from
    ldy #1
    jsr kv_bytes
    lda ptr+1                   ; Color RAM: da $D800, dalla riga + 99 + kv_c
    clc
    adc #>($D800 - SCREEN)
    sta ptr+1
    lda kv_c
    adc #KP_PANEL_W * 9         ; (C = 0)
    jsr kv_from
    ldy #1
    jmp kv_bytes
.endproc

; Colonna di celle kv_c del ritratto del lato X: righe 0-11 del pannello alle righe multicolor
; KV_MC_ROW0-KV_MC_ROW1 (la riga 12, il fondo del busto, non c'è).
.proc kv_column
    stx kv_s
    jsr kv_panel_at
    ldx kv_s
    lda kv_panel_col,x
    clc
    adc kv_c
    sta kv_n
    ldx #KV_MC_ROW0
:   jsr kv_cell
    jsr kv_next_row
    ldx kv_r
    inx
    cpx #KV_MC_ROW1 + 1
    bne :-
    rts
.endproc
.assert KV_MC_ROW1 - KV_MC_ROW0 + 1 <= KP_MC_ROW1 - KP_PANEL_ROW + 1, error, "VS: ritratti oltre le righe multicolor dei pannelli"

; Split del raster, come kp_split di kpick.s: alla riga KV_LINE_ON - 1 aspetta la KV_LINE_ON (vuota)
; e accende il multicolor, alla KV_LINE_OFF - 1 aspetta la KV_LINE_OFF (vuota) e lo spegne, poi alla
; riga 250 l'interrupt di sempre. Con A, X e Y nello stack: da kv_irq (vettore in RAM) o dal KERNAL
; (vettore $0314, con la ROM accesa durante kv_bytes), quindi qui a $C400.
.proc kv_split
    ldx kv_irq_n                ; 0 la riga 250, 1 accendere, 2 spegnere
    beq vbl
:   lda $d012
    cmp kv_line,x
    bcc :-
.ifndef ROTATED
    cpx #2                      ; alla riga del centro delle astronavi (KV_S) le loro metà basse,
    bne :+                      ; come nella scelta (kp_split)
    lda #KV_S
    sta $d001 + 2 * SPN_PAD
    sta $d003 + 2 * SPN_PAD
    lda #POSE_BOT0
    sta SPR_PTR + SPN_PAD
    lda #POSE_BOT1
    sta SPR_PTR + SPN_PAD + 1
:
.endif
    lda kv_d016,x
    sta $d016
    lda kv_next,x
    sta $d012
    inx
    cpx #KV_SPLITS + 1
    bcc :+
    ldx #0
:   stx kv_irq_n
    asl $d019                   ; (riscrive il registro: interrupt del raster visto; due byte in meno)
    pla
    tay
    pla
    tax
    pla
    rti
vbl:
    lda #KV_LINE_ON - 1
    sta $d012
    inc kv_irq_n
    pla
    tay
    pla
    tax
    pla
    jmp irq_handler             ; frame_flag, frame_count (in pagina zero; irq_handler sotto $8000)
.endproc
kv_irq_n: .byte 0
.ifdef ROTATED
KV_SPLITS = 2
kv_line   = * - 1               ; (per kv_irq_n 1 e 2)
    .byte KV_LINE_ON, KV_LINE_OFF
kv_d016   = * - 1
    .byte $c8 | $10, $c8        ; multicolor, hires
.else
KV_SPLITS = 3                   ; (alla riga KV_S le metà basse delle astronavi)
kv_line   = * - 1               ; (per kv_irq_n 1, 2 e 3)
    .byte KV_LINE_ON, KV_S, KV_LINE_OFF
kv_d016   = * - 1
    .byte $c8 | $10, $c8 | $10, $c8     ; multicolor, multicolor, hires
.endif
kv_next   = * - 1
.ifdef ROTATED
    .byte KV_LINE_OFF - 1, RASTER_LINE
.else
    .byte KV_S - 1, KV_LINE_OFF - 1, RASTER_LINE
.assert KV_LINE_ON < KV_S - 1 .and KV_S < KV_LINE_OFF - 1, error, "VS: righe dello split"
.endif
.assert KV_LINE_ON < KV_LINE_OFF - 1 .and KV_LINE_OFF < RASTER_LINE, error, "VS: righe dello split"

; ------------------------------------------------------------------------------------ scritte

; Lettera A (da 0) del motto del lato X, nella riga KV_TAG_ROW.
.proc kv_tag_char
    sta kv_n
    lda kv_kind,x
    cmp #OMEGA_KIND
    bcc kind
    ldy kv_n
    cpy #KV_OMEGA_TAG_LEN
    bcs done
    lda kv_omega_tag,y
    pha
    lda kv_omega_col,x
    jmp put
kind:
    lda kv_n
    cmp #16
    bcs done
    lda kv_kind,x
    asl a
    tay
    lda kind_tags,y
    sta ptr2
    lda kind_tags+1,y
    sta ptr2+1
    ldy kv_n
    lda (ptr2),y
    pha
    lda kv_tag_col,x
put:
    clc
    adc kv_n
    sta p_col
    lda #KV_TAG_ROW
    sta v_row
    pla
    tay
    lda font_map - 32,y
    jmp text_cell
done:
    rts
.endproc

; ------------------------------------------------------------------------------------ racchette

kv_panel_col: .byte KP_PANEL_COL0, KP_PANEL_COL1
kv_tag_col:   .byte KP_TAG_COL0, KP_TAG_COL1

; ------------------------------------------------------------------------------------ riga 24

; Codice usato solo nel caricamento e alla fine: nella prima pagina della riga 24 della bitmap, nera
; su nera (vs_enter la copia con il resto).
.segment "KVCODE2"

; Le due racchette nel campo (sprite 3 e 4, immagini fatte nel caricamento): a grandezza reale,
; con il davanti verso la mezzeria; quella di OMEGA rossa. Nel campo girato le astronavi della
; partita (ship_vs).
.proc kv_pads
.ifdef ROTATED
    ; le due astronavi caricate da ship_load (il giocatore con la posa in basso, l'altro con quella
    ; in alto, come nella scelta), a metà fra il ritratto e la mezzeria; quella di OMEGA rossa
    ldy #1
side:
    lda sv_x,y
    sta ship_x
    ldx kv_kind,y
    cpx #OMEGA_KIND
    bcc :+
    ldx #K_ARCADE               ; (OMEGA: l'immagine di ARCADE)
:   lda #SHIP_VS_TOP
    cpy #0
    bne :+
    clc
    adc rp_dy,x
:   sta ship_y
    tya
    pha
    asl a
    asl a
    tax                         ; sprite da 4 * lato
    lda kv_kind,y               ; (per il colore: OMEGA rosso)
    jsr ship_regs               ; (Y = serie = lato)
    pla
    tay
    dey
    bpl side
    rts
.else
    ldy #1
side:
    lda pose_top,y              ; in due metà (pose_load): la metà bassa la mette kv_split
    sta sh_ptr+SPN_PAD,y
    ldx kv_kind,y
    lda kind_col,x
    cpx #OMEGA_KIND
    bcc color
    ldx #K_ARCADE
color:
    sta sh_col+SPN_PAD,y
    lda pv_x,y
    jsr pad_face_x
    sta sh_x+SPN_PAD,y
    lda #KV_TOP
    sta sh_y+SPN_PAD,y
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
    pha
    and sh_xexp
    sta sh_xexp
    pla
    and sh_msb
    sta sh_msb
    dey
    bpl side
    rts
.endif
.endproc
.ifdef ROTATED
SHIP_VS_TOP = SPR_Y0 + KV_PAD_CY - 14       ; la posa in alto (il disegno finisce alla riga 20)
SV_CX0 = ((KP_PANEL_COL0 + KP_PANEL_W) * 8 + 160) / 2     ; centri: fra il ritratto e la mezzeria
SV_CX1 = (KP_PANEL_COL1 * 8 + 160) / 2
sv_x: .byte SPR_X0 + SV_CX0 - 24, SPR_X0 + SV_CX1 - 24
.assert SPR_X0 + SV_CX1 + 24 < 256, error, "VS: astronavi senza il nono bit"
.endif

; Colore A del trattino della scala ch_level (due celle della riga 0).
.proc kv_rung
    pha
    lda ch_level
    asl a
    adc ch_level
    tay
    pla
    sta SCREEN + 10,y
    sta SCREEN + 11,y
    rts
.endproc

kv_omega_tag: .byte "IT BECOMES THEM ALL"
KV_OMEGA_TAG_LEN = * - kv_omega_tag
kv_omega_col: .byte 1, 21       ; centrato nella metà (19 lettere)



; LEVEL n OF 7, FINAL LEVEL, SECRET LEVEL o TRAINING nella riga KV_LEVEL_ROW (kv_mode).
.proc kv_level
    lda kv_mode
    cmp #IM_TRAIN
    beq train
    lda ch_level
    cmp #CH_OMEGA
    bcc :+
    jsr print_at
    .byte 14, KV_LEVEL_ROW, "SECRET LEVEL", 0
    rts
:   lda kv_mode
    beq level
    jsr print_at
    .byte 14, KV_LEVEL_ROW, "FINAL LEVEL", 0
    rts
train:
    jsr print_at
    .byte 16, KV_LEVEL_ROW, "TRAINING", 0
    rts
level:
    jsr print_at
    .byte 14, KV_LEVEL_ROW, "LEVEL   OF 7", 0
    lda ch_level
    clc
    adc #'1' - 32
    tay
    lda font_map,y
    ldx #20
    stx p_col
    ldx #KV_LEVEL_ROW
    stx v_row
    jmp text_cell
.endproc

; ------------------------------------------------------------------------------------ riga 14

; Codice in 18 celle della riga 14 della bitmap (KV_CODE4), nere su nere, tra i ritratti e il
; sigillo di OMEGA: kv_load lo copia con i colori. Gira solo con $01 = $35 (sotto c'è la ROM del KERNAL).
.segment "KVCODE4"

; Interrupt dal vettore in RAM ($FFFE): come quello del KERNAL, A, X e Y nello stack, poi kv_split.
.proc kv_irq
    pha
    txa
    pha
    tya
    pha
    jmp kv_split
.endproc

; Split acceso (kv_irq e kv_split al posto di irq_handler e del vettore del KERNAL) o spento (di
; nuovo irq_handler alla riga 250, il vettore di prima, senza multicolor): a schermo acceso, alla
; fine e con il nuovo sfidante. L'interrupt dopo è quello della riga 250 (kv_irq_n 0).
.proc kv_split_on
    ; Color RAM nera nelle celle di KVCODE4: nella riga di pixel dello spegnimento (la prima della
    ; riga 14) il codice si vede in multicolor finché $D016 non cambia, e %11 prende il colore da lì
    lda #0
    ldx #KV_CODE4_CELLS - 1
:   sta $d800 + (KV_CODE4 - $E000) / 8,x
    dex
    bpl :-
    lda $0314
    sta kv_kernal
    lda $0315
    sta kv_kernal+1
    sei
    lda #<kv_split
    sta $0314
    lda #>kv_split
    sta $0315
    ldx #<kv_irq
    ldy #>kv_irq
    bne kv_split_set            ; (sempre)
.endproc
kv_split_off:
    lda #RASTER_LINE
    sta $d012
    lda #$c8
    sta $d016
    sei
    lda kv_kernal
    sta $0314
    lda kv_kernal+1
    sta $0315
    ldx #<irq_handler
    ldy #>irq_handler
kv_split_set:
    lda #0
    sta kv_irq_n
    stx $fffe
    sty $ffff
    cli
    rts
kv_kernal: .word 0              ; vettore $0314 di prima
KV_CODE4_CELLS = 18
.assert (KV_CODE4 - $E000) / 320 = KV_MC_ROW1 + 1, error, "KVCODE4 nella riga dello spegnimento dello split"

; ------------------------------------------------------------------------------------ riga 15

; Codice in 18 celle della riga 15 della bitmap (KV_CODE5), nere su nere, tra i nomi: kv_load lo
; copia con quello della riga 14. Solo con $01 = $35.
.segment "KVCODE5"

; Riga A (da 0) del nome del lato X: dalle righe 13-16 del pannello alle 15-18 dello schermo
; (OMEGA: 13-17 alle 14-18), una riga per frame (11 celle, circa 4.500 cicli). C = 1 finito.
.proc kv_name
    stx kv_s
    sta kv_y
    lda kv_kind,x               ; righe: 4, OMEGA 5
    cmp #OMEGA_KIND
    lda #4
    adc #0
    cmp kv_y
    beq done
    bcc done
    jsr kv_panel_at
    lda kv_y
    clc
    adc #13
    tax
:   jsr kv_next_row
    dex
    bne :-
    ldx kv_s
    lda kv_panel_col,x
    sta kv_n
    ldy #15                     ; riga dello schermo: 15 + A, OMEGA 14 + A
    lda kv_kind,x
    cmp #OMEGA_KIND
    bcc :+
    dey
:   tya
    clc
    adc kv_y
    sta kv_y
    lda #0
    sta kv_c
:   ldx kv_y
    jsr kv_cell
    inc kv_n
    inc kv_c
    lda kv_c
    cmp #KP_PANEL_W
    bne :-
done:
    rts
.endproc

.segment "KVCODE"
