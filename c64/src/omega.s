; OMEGA, il boss segreto dopo il GUARDIAN (rust/core/src/challenge.rs: OMEGA, omega_form), come
; rust/game/src/scenes.rs e challenge_ui.rs: qui la parte della partita contro di lui, che resta in
; memoria (il resto sta con le altre schermate: challenge.s, intro.s, ending.s, il jukebox).
;
; La regola del core (la racchetta che cambia forma a ogni punto subito) è next_morph in next.s.
; Qui quello che si vede e si sente, a ogni frame della partita (om_tick, dopo il tick e gli sprite):
; - la racchetta di OMEGA rossa (viola con l'easter egg RED, che scambia giallo e rosso), bianca
;   per OM_FLASH frame a ogni trasformazione (om_white, dal colore delle racchette di video.s);
; - la musica: la sezione della forma (canzoni OMEGA0-OMEGA6 del MiSTer, SID_SONG_OMEGA del player)
;   copiata dalla cartuccia a THEME_BASE dopo la trasformazione, una pagina per frame con il tempo
;   e senza voce in corso (la copia accende le ROM); intanto silenzio;
; - le immagini della racchetta: come per ogni lato, il blocco del tipo dalla
;   cartuccia (pad_prep di video.s), che si ricopia dopo la trasformazione (2 pagine, nella pausa
;   dopo il punto; intanto l'immagine dinamica); OMEGA non ha la rotazione del SUPER, quella
;   dell'avversario resta;
; - il nome della forma nuova (om_name), la grafica delle presentazioni, per NM_FRAMES frame in alto
;   nella metà campo di OMEGA, a tratti negli ultimi NM_BLINK: i suoi caratteri (la pagina del nome
;   di titles.bin) vanno a TN_FIRST, che in partita non si vedono, copiati dopo la trasformazione
;   come le pagine della musica;
; - la rete (om_net): i trattini spostati come la voce 2 del SID, imitata dallo stato del player,
;   con sei caratteri liberi del set (OM_CH, da CHARSET_USED).
; Nel programma restano om_tick, om_white e le tabelle della rete: il resto (segmento OMCODE) sta
; nel banco di OMEGA, e om_tick lo copia a OM_RUN nei primi frame della partita, una pagina per
; frame, appena GO è finito. OM_RUN è dove sta READY nel conto alla rovescia (dopo il player delle voci, che resta): in
; partita non serve più, e il GAME OVER vinto e il file del primo livello lo rimettono. Le sezioni
; della musica coprono invece la pagina degli NMI del player (VOICE_GO): la rimettono il GAME OVER
; vinto e, con OMEGA perso, il finale (load_tab di ending.s), che usa il player per YOU WIN.
;
; Le musiche stanno nel banco OM_BANK (segmento OMMUSIC, paddws.cfg): per ogni sezione (e per ogni
; tema degli avversari, per il jukebox) un'immagine di pagine intere da copiare a THEME_BASE, come
; la legge SID_SONG_OMEGA (sid.s): la prima traccia nella prima pagina, la terza (un solo $FF)
; nell'ultimo byte di quella pagina, la seconda dalla pagina dopo.

; il banco OM_BANK: il file voce di OMEGA (VOICE_PAGES pagine), le musiche (OMMUSIC), il jukebox
; (JBCODE), l'entrata nella presentazione (INV7): offset nel banco (paddws.cfg)
OM_MUS_OFF = VOICE_PAGES * 256
OM_JB_OFF  = OM_MUS_OFF + $2000
OM_INV_OFF = OM_JB_OFF + $0800
OM_CODE_OFF = OM_INV_OFF + $0200
OM_RUN     = $EC00              ; OMCODE: quattro pagine, in partita sopra READY
OM_PAGES   = 4
OM_CODE_SRC = $80 + OM_CODE_OFF / 256
.import __OMMUSIC_LOAD__, __INV7_RUN__, __OMCODE_RUN__, __OMCODE_SIZE__
.assert __OMMUSIC_LOAD__ = $8000 + OM_MUS_OFF .and __INV7_RUN__ = INV_RUN, lderror, "banco di OMEGA fuori posto"
.assert __OMCODE_RUN__ = OM_RUN .and __OMCODE_SIZE__ <= OM_PAGES * 256, lderror, "OMEGA: codice della partita fuori posto o troppo lungo"
.assert OM_RUN >= VOICE_KEEP .and OM_RUN + OM_PAGES * 256 <= VOICE_END, error, "OMEGA: codice della partita sopra il player delle voci o oltre READY"

OM_FLASH   = (8 * TV_HZ + 25) / 50 ; frame del lampo bianco della trasformazione (8 a 60 Hz sul PC)
OM_CH      = CHARSET_USED       ; rete: 6 caratteri liberi del set
OM_CHARS   = CHARSET + 8 * OM_CH
NM_FRAMES  = (50 * TV_HZ + 25) / 50 ; nome della forma nuova: 1 s, gli ultimi NM_BLINK frame a tratti
NM_BLINK   = (10 * TV_HZ + 25) / 50
NM_ROW     = 6                  ; prima riga (sotto le scritte delle mosse, righe 4 e 5)
OM_LATE_COPY = (TV_BUDGET - (5800)) / TV_LCYC      ; una pagina (circa 3.800 cicli) solo prima di qui: dopo om_tick
; c'è solo la coda della palla; la rete (circa 1.600 cicli) e il nome (1.800) solo prima di qui
; (sull'NTSC, più carico, più avanti)
.ifdef NTSC
OM_LATE_NET  = (TV_BUDGET - (1700)) / TV_LCYC
.else
OM_LATE_NET  = (TV_BUDGET - (3600)) / TV_LCYC
.endif
.assert OM_CH + 6 <= 256, error, "rete di OMEGA: niente caratteri liberi nel set"

.segment "BSS"
om_on:    .res 1                ; partita contro OMEGA già preparata (om_tick)
om_kind:  .res 1                ; tipo della racchetta di OMEGA nel frame prima
om_flash: .res 1                ; frame del lampo bianco rimasti
om_src:   .res 1                ; sezione in copia: prossima pagina nella cartuccia, pagine rimaste,
om_left:  .res 1                ; destinazione
om_dst:   .res 1
om_amp:   .res 1                ; rete a schermo: ampiezza * 16 ($FF: da ridisegnare) e passo
om_step:  .res 1
ch_clean: .res 1                ; scala fatta dal livello 1 senza continue (Run::clean del PC)
ch_omega: .res 1                ; OMEGA battuto: il finale speciale (ending.s)

.segment "CODE"

; Un frame della partita (scene_done, dopo gli sprite), in NEXT contro OMEGA (nx_morph, next.s): il
; codice della partita (OMCODE) dalla cartuccia, una pagina per frame se c'è tempo e nessuna voce
; (GO), poi ogni frame om_frame. om_on: pagine copiate (begin_match lo azzera).
.proc om_tick
    lda m_next
    beq done
    ldx nx_morph
    bmi done
    lda om_on
    cmp #OM_PAGES
    bcc load
    jmp om_frame
load:
    bit $fffb
    bmi done
    lda #OM_LATE_COPY
    jsr frame_after
    bcs done
    lda om_on
    tax
    adc #OM_CODE_SRC            ; (C = 0)
    sta ef_src+2
    txa
    adc #>OM_RUN
    tay
    lda #OM_BANK
    ldx #1
    jsr ef_copy
    inc om_on
    lda om_on
    cmp #OM_PAGES
    bcc done
    jmp om_init
done:
    rts
.endproc

; NTSC: il codice di OMEGA (una pagina per frame) e la parte di om_frame con le copie e i disegni
; (il nome della forma nuova, circa 3.800 cicli per i caratteri; le pagine della musica; il nome a
; schermo; la rete) all'inizio del frame, che ha il tempo: dopo gli sprite (om_tick) non c'era quasi
; mai. Sullo stato del tick prima, come la musica che la rete segue. Solo in
; partita con il codice di OMEGA copiato (om_on: begin_match lo azzera, nelle altre partite resta 0).
.ifdef NTSC
OM_EARLY_NET = (TV_BUDGET - (12700)) / TV_LCYC
.proc om_early
    lda state
    cmp #ST_PLAY
    bne done
    lda nx_morph                ; (OMEGA in questa partita)
    bmi done
    ; palla a pochi tick da una racchetta: colpo o punto (rimbalzo, CPU, punteggi) fanno già
    ; pesante il tick, e il resto aspetta
    ldy #ZONE_NEAR
    ldx #0
    jsr ball_in_zone
    bcs done
    ldx #4
    jsr ball_in_zone
    bcs done
    lda om_on
    cmp #OM_PAGES
    bcs loaded
    jmp om_tick                 ; il suo codice, una pagina (dopo gli sprite non c'era il tempo)
loaded:
    lda pp_side                 ; prima le immagini della forma nuova dalla cartuccia (pad_prep, due
    cmp #2                      ; pagine: intanto l'immagine dinamica), poi il resto
    bcs :+
    jmp pad_prep
:   jsr om_rest                 ; caratteri del nome, una pagina della musica o il nome a schermo
    lda #OM_EARLY_NET           ; poi la rete, se il frame è ancora all'inizio (niente di pesante
    jsr frame_after             ; prima)
    bcs done
    jmp om_net
done:
    rts
.endproc
.endif

; Colore dedicato della racchetta del giocatore X (0 o 4): colore del tipo (kind_col), oppure
; viola per OMEGA (bianco nel lampo della trasformazione). Y resta.
.proc om_white
    cpx nx_morph
    bne normal
    lda #COL_WHITE
    ldx om_flash
    bne done
    lda #COL_PURPLE
    rts
normal:
    lda nx_kind,x
    tax
    lda kind_col,x
done:
    rts
.endproc

.segment "OMCODE"
; Il codice appena copiato: la prima forma è ARCADE (se una trasformazione è già arrivata, la vede
; om_frame), rete da disegnare (i suoi caratteri li fa l'entrata nella presentazione, om_glyphs).
.proc om_init
    lda #K_ARCADE
    sta om_kind
    lda #0
    sta om_flash
    sta om_left
    sta nm_s
    sta nm_on
    lda #$ff
    sta om_amp
    rts
.endproc

; Un frame della partita contro OMEGA.
.proc om_frame
.ifdef OMTELE
    lda #B_TELEPORT             ; (prova per VICE, -Define OMTELE: OMEGA a destra ha sempre il
    sta nx_res+4                ; TELEPORT nel primo posto della riserva)
.endif
    lda over_next               ; partita finita: il nome della forma via
    beq :+
    jsr nm_erase
:   ldx nx_morph
    ; trasformazione nel tick: il nome e la musica della forma
    lda nx_kind,x
    cmp om_kind
    beq same
    sta om_kind
    jsr nm_erase                ; il nome della forma nuova (quello di prima via; lampo e immagine
    lda om_kind                 ; li ha già cambiati il tick, next_morph e le immagini preparate)
    sta nm_k
    lda #1
    sta nm_s
    ; forma = punti dell'avversario (omega_form), al più l'ultima
    lda nx_morph
    eor #4
    tay
    lda score+1,y
    bne last
    lda score,y
    cmp #CH_LEVELS
    bcc :+
last:
    lda #CH_LEVELS - 1
:   tay
    lda om_pages,y
    sta om_src
    lda om_npages,y
    sta om_left
    lda #>THEME_BASE
    sta om_dst
    lda #0                      ; silenzio finché la sezione non c'è
    jsr sid_song
same:
    lda om_flash
    beq :+
    dec om_flash
:
.ifdef NTSC
stop:
    rts                         ; (il resto all'inizio del frame dopo: om_early)
.endif
rest:
    jsr om_name
.ifdef NTSC
    bcs stop                    ; (all'inizio del frame una cosa sola: caratteri, una pagina della
.else                           ; musica, nome a schermo o rete)
    bcs net                     ; (ha copiato i caratteri del nome: niente altre copie)
.endif
    ; una pagina della sezione per frame, se c'è tempo e nessuna voce (READY, GO)
    lda om_left
    beq net
    bit $fffb
    bmi net
    lda #OM_LATE_COPY
    jsr frame_after
    bcs net
    lda om_src
    sta ef_src+2
    inc om_src
    ldy om_dst
    inc om_dst
    lda #OM_BANK
    ldx #1
    jsr ef_copy
    dec om_left
    bne copied
    lda #SID_SONG_OMEGA
    jsr sid_song
copied:
.ifdef NTSC
    rts
.endif
net:
.ifdef NTSC
    jmp nm_show                 ; (la rete la decide om_early)
.else
    jsr nm_show
    jmp om_net
.endif
.endproc
om_rest = om_frame::rest        ; (om_early)

; Nome della forma nuova: prima i caratteri (om_name, C = 1 se li ha copiati in questo frame), poi a
; schermo (nm_show, dopo la musica) NM_FRAMES frame, gli ultimi NM_BLINK a tratti (2 frame
; accesi, 2 spenti), poi via.
; Disegno e cancellazione (al più circa 1.800 cicli) solo se il frame ha tempo, se no al prossimo.
nm_s:   .byte 0                 ; 0 niente, 1 caratteri da copiare, 2 a schermo
nm_k:   .byte 0                 ; tipo della forma
nm_t:   .byte 0                 ; frame rimasti a schermo
nm_on:  .byte 0                 ; 1: disegnato
.proc om_name
    lda nm_s
    cmp #1
    bne no
    bit $fffb                   ; i caratteri: come le pagine della musica
    bmi no
    lda #OM_LATE_COPY
    jsr frame_after
    bcs no
    lda nm_k
    clc
    adc #TTL_NAMES
    jsr title_copy
    lda #2
    sta nm_s
    lda #NM_FRAMES
    sta nm_t
    sec
    rts
no:
    clc
    rts
.endproc
.proc nm_show
    lda nm_s
    cmp #2
    bne no
    dec nm_t
    beq off
    lda nm_t                    ; acceso, o a tratti negli ultimi NM_BLINK
    cmp #NM_BLINK
    bcs on
    and #2
    beq hide
on:
    lda nm_on
    bne no
    lda #OM_LATE_NET
    jsr frame_after
    bcs no
    jsr nm_draw
    inc nm_on
no:
    clc
    rts
off:
    inc nm_t                    ; (resta a 1 finché non è cancellato)
    lda nm_on
    bne hide
    sta nm_s
    rts
hide:
    lda nm_on
    beq no
    lda #OM_LATE_NET
    jsr frame_after
    bcs no
    jmp nm_erase
.endproc

; Il nome nm_k (le mappe delle presentazioni, TN_k_* di gen/assets.inc) con i suoi colori, in alto
; nella metà campo di OMEGA; nm_erase lo toglie (le sue celle piene vuote), se c'è.
.proc nm_erase
    lda nm_on
    beq done
    lda #0
    sta nm_on
    jsr shots_erase             ; (i colpi del BLASTER rimetterebbero il nome)
    sec
    bcs nm_cells
done:
    rts
.endproc
.proc nm_draw
    jsr shots_erase             ; (i colpi del BLASTER rimetterebbero quello che c'era)
    clc
.endproc
; (prosegue) C = 1 cancella.
.proc nm_cells
    ror nm_wipe                 ; bit 7: cancella
    ldx nm_k
    lda nm_map_lo,x
    sta ptr2
    lda nm_map_hi,x
    sta ptr2+1
    lda nm_w,x
    sta nm_cw
    lda nm_n,x
    sta nm_cn
    lda #20                     ; colonna: centrato nella metà campo di OMEGA
    sec
    sbc nm_cw
    lsr a
    ldy nm_k_side
    beq :+
    adc #20                     ; (C = 0)
:   sta nm_col
    lda #NM_ROW
    sta nm_r
    ldx #0                      ; cella
row:
    ldy nm_r                    ; schermo in ptr, colore in m_a (libero: nessuna moltiplicazione)
    lda row_lo,y
    clc
    adc nm_col
    sta ptr
    sta m_a
    lda row_hi,y
    adc #0
    sta ptr+1
    adc #>($d800 - SCREEN)      ; (C = 0)
    sta m_a+1
    ldy #0
cell:
    stx nm_i
    sty nm_y
    txa
    tay
    lda (ptr2),y                ; codice (0: cella vuota)
    beq next
    bit nm_wipe
    bpl :+
    lda #CH_BLANK
:   ldy nm_y
    sta (ptr),y
    bit nm_wipe
    bmi next
    lda nm_i                    ; il colore: dopo i codici
    clc
    adc nm_cn
    tay
    lda (ptr2),y
    ldy nm_y
    sta (m_a),y
next:
    ldx nm_i
    inx
    ldy nm_y
    iny
    cpy nm_cw
    bne cell
    inc nm_r
    cpx nm_cn
    bne row
    rts
.endproc
nm_k_side = nx_morph            ; (0 OMEGA a sinistra, 4 a destra)
nm_wipe: .byte 0
nm_cw:  .byte 0
nm_cn:  .byte 0
nm_col: .byte 0
nm_r:   .byte 0
nm_i:   .byte 0
nm_y:   .byte 0
; i nomi delle presentazioni per tipo: larghezza e celle, mappa (codici, poi colori)
nm_0:   .byte TN_0_MAP
        .byte TN_0_CLR
nm_1:   .byte TN_1_MAP
        .byte TN_1_CLR
nm_2:   .byte TN_2_MAP
        .byte TN_2_CLR
nm_3:   .byte TN_3_MAP
        .byte TN_3_CLR
nm_4:   .byte TN_4_MAP
        .byte TN_4_CLR
nm_5:   .byte TN_5_MAP
        .byte TN_5_CLR
nm_6:   .byte TN_6_MAP
        .byte TN_6_CLR


; Rete di OMEGA (draw_omega_net del PC): la mezzeria di sempre con ogni trattino spostato di ±3
; pixel al più come la voce 2 del SID (il basso col wobble) alla sua riga, in una finestra di
; 120 ms su tutto il campo agganciata al passaggio per lo zero in salita. Il C64 non legge la voce:
; si imita dallo stato del player, una sinusoide che parte da 0 in cima con tanti periodi quanti ne
; fa la nota in 120 ms (fase per riga di celle = frequenza del canale 1 / 16, 256 un periodo) e
; l'ampiezza dal taglio del filtro (0-3 pixel: il wobble lo apre e lo chiude, la rete pulsa);
; diritta senza la canzone di OMEGA. Si ridisegna (circa 1.600 cicli) solo quando cambia e se il
; frame ha tempo.
.proc om_net
    lda #0
    tax
    ldy sid_song_n
    cpy #SID_SONG_OMEGA
    bne sig
    ldy ch_active+1
    beq sig
    lda sid_fc+1                ; ampiezza: taglio / 32, al più 3
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    cmp #4
    bcc :+
    lda #3
:   asl a
    asl a
    asl a
    asl a
    pha
    lda ch_freq_lo+1            ; passo: la frequenza / 16
    lsr a
    lsr a
    lsr a
    lsr a
    sta m_t
    lda ch_freq_hi+1
    asl a
    asl a
    asl a
    asl a
    ora m_t
    tax
    pla
sig:
    cmp om_amp
    bne :+
    cpx om_step
    beq done
:   pha
    lda #OM_LATE_NET
    jsr frame_after
    pla
    bcs done
    sta om_amp
    stx om_step
    jsr shots_erase             ; (i colpi del BLASTER rimetterebbero la rete di prima)
    ldx #0
    stx m_t                     ; fase
row:
    lda row_lo,x
    sta ptr
    lda row_hi,x
    sta ptr+1
    lda m_t
    lsr a
    lsr a
    lsr a
    lsr a
    ora om_amp
    tay
    lda #3                      ; (ampiezza 0: dritta)
    cpy #16
    bcc :+
    lda om_wave - 16,y          ; spostamento + 3
:   tay
    lda om_rch,y
    pha
    lda om_lch,y
    ldy #19
    sta (ptr),y
    pla
    iny
    sta (ptr),y
    lda m_t
    clc
    adc om_step
    sta m_t
    inx
    cpx #25
    bne row
done:
    rts
.endproc

; sezioni della canzone di OMEGA nella cartuccia (OMMUSIC): prima pagina e pagine
om_pages:  .byte >om_s0, >om_s1, >om_s2, >om_s3, >om_s4, >om_s5, >om_s6
om_npages: .byte (om_s1 - om_s0) / 256, (om_s2 - om_s1) / 256, (om_s3 - om_s2) / 256
           .byte (om_s4 - om_s3) / 256, (om_s5 - om_s4) / 256, (om_s6 - om_s5) / 256
           .byte (om_t0 - om_s6) / 256
.assert SID_SONG_OMEGA = OMEGA_SONG, error, "canzone di OMEGA diversa da quella dei file voce"
; rete: spostamento + 3 (0-6) per ampiezza (1-3) e sedicesimo di periodo, una sinusoide
om_wave: .byte 3, 3, 4, 4, 4, 4, 4, 3, 3, 3, 2, 2, 2, 2, 2, 3
         .byte 3, 4, 4, 5, 5, 5, 4, 4, 3, 2, 2, 1, 1, 1, 2, 2
         .byte 3, 4, 5, 6, 6, 6, 5, 4, 3, 2, 1, 0, 0, 0, 1, 2
; caratteri della rete per spostamento + 3 (0-6), a sinistra e a destra della linea
om_lch:  .byte OM_CH, OM_CH + 1, OM_CH + 2, CH_LINE_L, CH_BLANK, CH_BLANK, CH_BLANK
om_rch:  .byte CH_BLANK, CH_BLANK, CH_BLANK, CH_LINE_R, OM_CH + 3, OM_CH + 4, OM_CH + 5
; i nomi delle forme (om_name): larghezza, celle, mappa
nm_w:   .byte TN_0_W, TN_1_W, TN_2_W, TN_3_W, TN_4_W, TN_5_W, TN_6_W
nm_n:   .byte TN_0_W * TN_0_H, TN_1_W * TN_1_H, TN_2_W * TN_2_H, TN_3_W * TN_3_H
        .byte TN_4_W * TN_4_H, TN_5_W * TN_5_H, TN_6_W * TN_6_H
nm_map_lo: .lobytes nm_0, nm_1, nm_2, nm_3, nm_4, nm_5, nm_6
nm_map_hi: .hibytes nm_0, nm_1, nm_2, nm_3, nm_4, nm_5, nm_6
.segment "CODE"

; --------------------------------------------------------------------------- musiche nella cartuccia

; Un'immagine da copiare a THEME_BASE: le tracce t0, t1 (e la terza, un $FF) come le legge
; SID_SONG_OMEGA, fino alla fine dell'ultima pagina.
.macro om_image t0, t1
    .local start
start:
    .incbin t0
    .assert * - start <= 255, error, "prima traccia oltre 255 byte"
    .res 255 - (* - start), 0
    .byte $FF
    .incbin t1
    .assert * - start <= 4 * 256, error, "sezione oltre quattro pagine"
    .res (256 - (* - start) .mod 256) .mod 256, 0
.endmacro

.segment "OMMUSIC"
om_s0: om_image "omega0_0.bin", "omega0_1.bin"
om_s1: om_image "omega1_0.bin", "omega1_1.bin"
om_s2: om_image "omega2_0.bin", "omega2_1.bin"
om_s3: om_image "omega3_0.bin", "omega3_1.bin"
om_s4: om_image "omega4_0.bin", "omega4_1.bin"
om_s5: om_image "omega5_0.bin", "omega5_1.bin"
om_s6: om_image "omega6_0.bin", "omega6_1.bin"
; i temi dei sette avversari nell'ordine della scala, per il jukebox (themeK_V.bin, K = tipo)
om_t0: om_image "theme0_0.bin", "theme0_1.bin"     ; ARCADE
om_t1: om_image "theme3_0.bin", "theme3_1.bin"     ; TWIST
om_t2: om_image "theme2_0.bin", "theme2_1.bin"     ; HAMMER
om_t3: om_image "theme1_0.bin", "theme1_1.bin"     ; TITAN
om_t4: om_image "theme4_0.bin", "theme4_1.bin"     ; BLASTER
om_t5: om_image "theme5_0.bin", "theme5_1.bin"     ; RUSH
om_t6: om_image "theme6_0.bin", "theme6_1.bin"     ; GUARDIAN
om_mus_end:
.assert .mid(0, 1, {T_RUNG_KIND}) = 0 .and .mid(2, 1, {T_RUNG_KIND}) = 3 .and .mid(4, 1, {T_RUNG_KIND}) = 2 .and .mid(6, 1, {T_RUNG_KIND}) = 1 .and .mid(8, 1, {T_RUNG_KIND}) = 4 .and .mid(10, 1, {T_RUNG_KIND}) = 5 .and .mid(12, 1, {T_RUNG_KIND}) = 6, error, "jukebox: temi non nell'ordine della scala"
.segment "CODE"

