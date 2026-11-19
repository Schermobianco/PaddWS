; JUKEBOX (rust/game/src/jukebox.rs e scope.rs): una voce del menu, visibile solo sbloccata (battendo
; OMEGA o con le iniziali BAS: hi_juke), che suona i temi. Brani: i sette temi degli avversari
; nell'ordine della scala, il finale (ENDING) e OMEGA, un brano solo che passa da una sezione alla
; successiva ogni due giri (OMEGA0-OMEGA6, poi da capo). Su e giù scelgono il brano e lo fanno
; partire, il fuoco (RETURN, SPAZIO) lo ferma o lo fa ripartire, RUN/STOP torna al menu. Il volume è
; quello del menu.
;
; Sotto il nome del brano e la sua posizione (n/9), tre oscilloscopi affiancati, uno per voce del
; SID, nella bitmap hires (96 x 40 pixel ciascuno, linea continua gialla). Il C64 non legge l'uscita
; delle voci: l'onda si ricostruisce dai registri che il player scrive davvero nel SID (wr di sid.s,
; deviata qui per tenerne una copia: jb_regs), cioè frequenza, forma d'onda del registro di
; controllo (triangolo, dente di sega, impulso con la sua larghezza, rumore; delle combinazioni
; vale la prima di impulso, dente di sega, triangolo) e gate, con l'ampiezza da un inviluppo ADSR
; calcolato qui dai valori dello strumento (attacco e decadimento lineari, approssimati). Finestra
; di circa 20 ms dal passaggio per lo zero in salita (fase 0 della forma): i bassi fanno uno o due
; periodi, gli acuti di più. Il filtro non si emula: la voce 2 nel filtro (OMEGA, HAMMER) ha
; l'ampiezza scalata dal taglio, così il wobble si vede. Voce spenta o muta: linea piatta. Si
; ridisegna un terzo di voce per frame (con i valori presi al primo terzo): ogni oscilloscopio poco più
; di cinque volte al secondo, al più circa 9.000 cicli. I tratti verticali costano: al più JB_MAX_PER periodi nella
; finestra (gli acuti si allargano) e il rumore a punti.
;
; Memoria: la bitmap dell'attract ($E000, colori a $C400; dopo il menu viene l'attract, che la
; rifà). Le righe di celle 0-18 sono a schermo; nelle altre (colori neri) ci sono la musica copiata
; (THEME_BASE) e la seconda parte del codice, nella riga 13 le tabelle del disegno (JB_RAM). Il codice
; (segmenti JBCODE, JBCODE2 e JBCODE3, nel banco di OMEGA) gira nello schermo di testo $C000, che nel
; modo bitmap non si vede, a JB_B dopo la musica e nella prima pagina della bitmap (riga 0, nera):
; enter_jukebox lo copia (il frame che apre il jukebox è lungo come quello che apre il menu). Le
; scritte coprono le tabelle dei quadrati: nel jukebox valgono pronte, all'uscita si rifanno. I temi e
; le sezioni di OMEGA sono le immagini di OMMUSIC (omega.s), copiate a THEME_BASE una pagina per frame
; (intanto silenzio) e suonate da SID_SONG_OMEGA; il finale è SID_SONG_EGG, letto dalla cartuccia.
JB_A      = $C000               ; prima parte (lo schermo di testo, fino alle celle di FRAMETEST)
JB_A_MAX  = 990
JB_B      = $FC00               ; seconda parte (bitmap, righe di celle nere)
JB_PAGES_A = 4
JB_PAGES_B = 3
JB_C      = JB_BITMAP           ; terza parte (la prima pagina della bitmap: riga di celle 0, nera)
JB_SRC    = $80 + OM_JB_OFF / 256
JB_TRACKS = 9
JB_BITMAP = $E000
SC_ROW    = 6                   ; oscilloscopi: righe di celle 6-10, colonne SC_COL0 + 13 * voce
SC_COL0   = 1
SC_H      = 40
SC_W      = 96
SC_PART   = SC_W / 3            ; colonne disegnate per frame (un terzo di voce)
JB_ROWS   = 19                  ; righe di celle a schermo (da pulire)
JB_RAM    = JB_BITMAP + 13 * 320 ; riga di celle 13 (nera): tabelle del disegno e copie dei registri
JB_LATE   = (TV_BUDGET - (14000)) / TV_LCYC          ; un terzo di voce (al più circa 9.000 cicli) solo prima di qui
JB_MAX_PER = 4                  ; periodi al più nella finestra (gli acuti oltre circa 200 Hz)
JB_MAXSTEP = JB_MAX_PER * 65536 / SC_W
.import __JBCODE_SIZE__, __JBCODE2_SIZE__, __JBCODE_RUN__, __JBCODE2_RUN__, __JBCODE3_SIZE__, __JBCODE3_RUN__
.assert __JBCODE3_RUN__ = JB_C .and __JBCODE3_SIZE__ <= 256, lderror, "jukebox: terza parte fuori posto o troppo lunga"
.assert __JBCODE_RUN__ = JB_A .and __JBCODE_SIZE__ <= JB_A_MAX, lderror, "jukebox: prima parte fuori posto o oltre lo schermo di testo"
.assert __JBCODE2_RUN__ = JB_B .and __JBCODE2_SIZE__ <= JB_PAGES_B * 256, lderror, "jukebox: seconda parte fuori posto o troppo lunga"
.assert JB_BITMAP + JB_ROWS * 320 <= THEME_BASE .and THEME_BASE + $400 <= JB_B .and JB_B + JB_PAGES_B * 256 <= $FF40, error, "jukebox: bitmap, musica e codice si sovrappongono"

.segment "CODE"
.proc enter_jukebox
    lda #JB_SRC
    sta ef_src+2
    lda #OM_BANK
    ldx #JB_PAGES_A
    ldy #>JB_A
    jsr ef_copy
    lda #JB_SRC + 4
    sta ef_src+2
    lda #OM_BANK
    ldx #JB_PAGES_B
    ldy #>JB_B
    jsr ef_copy
    lda #JB_SRC + 7
    sta ef_src+2
    lda #OM_BANK
    ldx #1
    ldy #>JB_C
    jsr ef_copy
    jmp jb_enter
.endproc

; ------------------------------------------------------------------------------------ prima parte

.segment "JBCODE"
.scope jb

; ------------------------------------------------------------------------------------ entrata

.proc enter
    lda #ST_JUKEBOX
    sta state
    lda #1                      ; (le scritte coprono le tabelle dei quadrati: all'uscita si rifanno)
    sta math_ready
    lda #0
    sta sh_bg
    sta sh_enable
    ; bitmap delle righe a schermo e colori a zero (le altre righe restano nere; la prima pagina
    ; è la terza parte del codice, nella riga di celle 0, senza scritte)
    tay
    ldx #>JB_BITMAP + 1
:   stx clr + 2
    ldy #0
clr:
    sta $ff00,y
    iny
    bne clr
    inx
    cpx #>(JB_BITMAP + JB_ROWS * 320 + 255)
    bne :-
    ldy #0
:   sta SCREEN2,y
    sta SCREEN2 + $100,y
    sta SCREEN2 + $200,y
    sta SCREEN2 + $2e8,y
    iny
    bne :-
    lda v_big                   ; le scritte nella bitmap
    ora #$40
    sta v_big
    ; il player scrive nel SID anche nella copia dei registri (jb_wr)
    lda #$4c
    sta wr_store
    lda #<jb_wr
    sta wr_store + 1
    lda #>jb_wr
    sta wr_store + 2
    ldx #3 * 7 - 1
    lda #0
:   sta jb_regs,x
    dex
    bpl :-
    ldx #2
:   sta env_lv,x
    sta env_st,x
    sta env_g,x
    dex
    bpl :-
    sta dv
    sta dh
    ; indirizzi delle righe di pixel degli oscilloscopi, per voce
    ldx #0                      ; voce * SC_H
    ldy #0                      ; voce
vy:
    lda sc_lo,y
    sta ptr
    lda sc_hi,y
    sta ptr+1
    lda #0
    sta m_t                     ; riga di pixel
px:
    lda ptr
    sta ya_lo,x
    lda ptr+1
    sta ya_hi,x
    inx
    inc m_t
    lda m_t
    and #7
    beq cellrow
    inc ptr
    bne pnext
    inc ptr+1
    bne pnext                   ; (sempre)
cellrow:
    lda ptr                     ; riga di celle dopo: + 320 - 7
    clc
    adc #<(320 - 7)
    sta ptr
    lda ptr+1
    adc #>(320 - 7)
    sta ptr+1
pnext:
    lda m_t
    cmp #SC_H
    bne px
    iny
    cpy #3
    bne vy
    ; scritte e colori
    jsr print_at
    .byte 16, 1, "JUKEBOX", 0
    lda egg_yel
    ldx #1
    jsr paint_row
    jsr print_at
    .byte 4, 12, "VOICE 1      VOICE 2      VOICE 3", 0
    lda #COL_GRAY
    ldx #12
    jsr paint_row
    jsr print_at
    .byte 6, 16, "UP DOWN: CHOOSE   FIRE: STOP", 0
    lda #COL_GRAY
    ldx #16
    jsr paint_row
    jsr print_at
    .byte 13, 18, "RUN/STOP: BACK", 0
    lda #COL_GRAY
    ldx #18
    jsr paint_row
    lda #COL_WHITE
    ldx #3
    jsr paint_row
    lda #COL_GRAY
    ldx #4
    jsr paint_row
    lda #COL_WHITE
    ldx #14
    jsr paint_row
    lda egg_yel                 ; le celle degli oscilloscopi, gialle
    ldx #SC_ROW
:   jsr paint_row
    inx
    cpx #SC_ROW + 5
    bne :-
    lda #MODE_BITMAP
    sta sh_mode
.ifdef JUKETRACK
    lda #::JUKETRACK            ; (prova per VICE: -Define JUKETEST,JUKETRACK=n, il brano n da 0)
.else
    lda #0
.endif
    sta track
    lda #1
    sta play
    jmp start
.endproc

; Colore A (in primo piano, sul nero) per la riga di celle X della bitmap. A e X restano.
.proc paint_row
    pha
    lda row_lo,x
    sta ptr
    lda row_hi,x
    clc
    adc #>(SCREEN2 - SCREEN)
    sta ptr+1
    pla
    pha
    asl a
    asl a
    asl a
    asl a
    ldy #39
:   sta (ptr),y
    dey
    bpl :-
    pla
    rts
.endproc

; Carattere ASCII A nella bitmap, colonna X, riga Y.
.proc putc
    sty v_row
    stx p_col
    tay
    lda font_map - 32,y
    jmp text_cell
.endproc

; ------------------------------------------------------------------------------------ frame

.proc jbscene
    lda #KEY_STOP
    jsr key_pressed
    bcc :+
    lda #$99                    ; via: wr com'era (sta SID,y), le scritte nello schermo, le tabelle dei
    sta wr_store               ; quadrati da rifare, il menu (con la sua musica)
    lda #<SID
    sta wr_store + 1
    lda #>SID
    sta wr_store + 2
    lda v_big
    and #$bf
    sta v_big
    jsr math_invalidate
    lda #0
    jsr sid_song
    jmp enter_menu
:   ; comandi come nel menu: joystick sulle due porte, cursori, RETURN e SPAZIO
    lda joy_edge
    ora joy_edge+1
    ora fire_edge
    ora fire_edge+1
    sta m_t
    lda #KEY_CRSR_UD
    jsr key_pressed
    bcc :+
    lda m_t
    ora #JOY_DOWN
    sta m_t
:   lda #KEY_RETURN
    jsr key_pressed
    bcs :+
    lda #KEY_SPACE
    jsr key_pressed
    bcc :++
:   lda m_t
    ora #JOY_FIRE
    sta m_t
:   ldx track
    lda m_t
    and #JOY_UP
    beq :+
    dex
    bpl new
    ldx #JB_TRACKS - 1
    bne new
:   lda m_t
    and #JOY_DOWN
    beq :+
    inx
    cpx #JB_TRACKS
    bcc new
    ldx #0
new:
    stx track
    lda #1
    sta play
    jsr start
    jmp frame
:   lda m_t
    and #JOY_FIRE
    beq frame
    lda play
    eor #1
    sta play
    jsr start
.endproc
; (prosegue)
; Il resto del frame: gli inviluppi, la copia di una pagina della musica, OMEGA alla sezione dopo
; ogni due giri, mezzo oscilloscopio.
.proc frame
    jsr envelopes
    lda left
    beq omega
    lda src
    sta ef_src+2
    inc src
    ldy dst
    inc dst
    lda #OM_BANK
    ldx #1
    jsr ef_copy
    dec left
    bne done
    lda song
    jmp sid_song
omega:
    lda track
    cmp #JB_TRACKS - 1
    bne scope
    lda play
    beq scope
    ; un giro: il puntatore del canale 0 torna indietro (comando $FE)
    lda ch_ptr_hi
    cmp last
    bne :+
    lda ch_ptr_lo
    cmp lastlo
:   php
    lda ch_ptr_hi
    sta last
    lda ch_ptr_lo
    sta lastlo
    plp
    bcs scope
    inc loops
    lda loops
    cmp #2
    bcc scope
    ldx osec
    inx
    cpx #CH_LEVELS
    bcc :+
    ldx #0
:   stx osec
    jsr section
    jmp name
scope:
    jmp draw_half
done:
    rts
.endproc

; ------------------------------------------------------------------------------------ brani

; Fa partire il brano track (play = 1) o lo ferma; il nome, la posizione, PLAYING o STOPPED.
.proc start
    lda #0
    sta left
    jsr sid_song
    lda play
    beq name
    lda track
    cmp #JB_TRACKS - 2
    beq ending
    bcs omega
    tax                         ; un tema: la sua immagine
    lda theme_pg,x
    sta src
    lda theme_n,x
    sta left
    lda #SID_SONG_OMEGA
    bne copy
ending:
    lda #SID_SONG_EGG           ; il finale, dalla cartuccia
    jsr sid_song
    jmp name
omega:
    lda #0
    sta osec
    jsr section
    jmp name
copy:
    sta song
    lda #>THEME_BASE
    sta dst
.endproc
; (prosegue)
; Nome del brano (con la sezione di OMEGA; il font non ha le parentesi angolari del PC),
; posizione e stato.
.proc name
    lda track
    cmp #JB_TRACKS - 2
    bcc theme
    beq :+
    lda #<s_omega
    ldx #>s_omega
    bne put
:   lda #<s_ending
    ldx #>s_ending
    bne put
theme:
    tax
    lda rung_kind,x
    asl a
    tax
    lda kind_names+1,x
    pha
    lda kind_names,x
    tax
    pla
    sta ptr2+1
    stx ptr2
    jmp :+
put:
    sta ptr2
    stx ptr2+1
:   ldx #16
    ldy #3
    jsr print_str
    lda track                   ; OMEGA: la sezione (1-7) dopo il nome
    cmp #JB_TRACKS - 1
    bne :+
    lda osec
    clc
    adc #'1'
    ldx #22
    ldy #3
    jsr putc
:   lda track                   ; posizione: n/9
    clc
    adc #'1'
    ldx #18
    ldy #4
    jsr putc
    lda #'/'
    ldx #19
    ldy #4
    jsr putc
    lda #'0' + JB_TRACKS
    ldx #20
    ldy #4
    jsr putc
    lda play
    bne :+
    jsr print_at
    .byte 16, 14, "STOPPED", 0
    rts
:   jsr print_at
    .byte 16, 14, "PLAYING", 0
    rts
.endproc

; Copia dei registri delle voci (wr di sid.s, deviata qui da enter).
.proc jb_wr
    sta SID,y
    sta jb_regs,y
    rts
.endproc

s_ending: .byte "ENDING  ", 0
s_omega:  .byte "OMEGA   ", 0
; prima cella (in alto a sinistra) di ogni oscilloscopio nella bitmap
sc_lo:    .lobytes JB_BITMAP + SC_ROW * 320 + (SC_COL0 + 0) * 8, JB_BITMAP + SC_ROW * 320 + (SC_COL0 + 13) * 8, JB_BITMAP + SC_ROW * 320 + (SC_COL0 + 26) * 8
sc_hi:    .hibytes JB_BITMAP + SC_ROW * 320 + (SC_COL0 + 0) * 8, JB_BITMAP + SC_ROW * 320 + (SC_COL0 + 13) * 8, JB_BITMAP + SC_ROW * 320 + (SC_COL0 + 26) * 8

; ------------------------------------------------------------------------------------ seconda parte

.segment "JBCODE2"

; tabelle e registri nella riga di celle 13 della bitmap, che non si vede (colori neri): JB_RAM
ya_lo   = ::JB_RAM                      ; indirizzo di ogni riga di pixel di ogni oscilloscopio
ya_hi   = ya_lo + 3 * ::SC_H
yq      = ya_hi + 3 * ::SC_H            ; riga di pixel (0-39) per valore dell'onda / 8
jb_regs = yq + 32                       ; registri delle voci come li ha scritti il player
env_lv  = jb_regs + 3 * 7               ; inviluppo: livello, fase (0 attacco, 1 decadimento e
env_st  = env_lv + 3                    ; sostegno, 2 rilascio), gate del frame prima
env_g   = env_st + 3
.assert env_g + 3 <= ::JB_RAM + 320, error, "jukebox: tabelle oltre la riga di celle"

; OMEGA alla sezione osec: la sua immagine, dai giri da capo.
.proc section
    lda #0
    sta loops
    sta left
    sta last
    sta lastlo
    jsr sid_song
    ldx osec
    lda om_pages,x
    sta src
    lda om_npages,x
    sta left
    lda #SID_SONG_OMEGA
    sta song
    lda #>THEME_BASE
    sta dst
    rts
.endproc

theme_pg: .byte >om_t0, >om_t1, >om_t2, >om_t3, >om_t4, >om_t5, >om_t6
theme_n:  .byte (om_t1 - om_t0) / 256, (om_t2 - om_t1) / 256, (om_t3 - om_t2) / 256
          .byte (om_t4 - om_t3) / 256, (om_t5 - om_t4) / 256, (om_t6 - om_t5) / 256
          .byte (om_mus_end - om_t6) / 256
om_pages:  .byte >om_s0, >om_s1, >om_s2, >om_s3, >om_s4, >om_s5, >om_s6
om_npages: .byte (om_s1 - om_s0) / 256, (om_s2 - om_s1) / 256, (om_s3 - om_s2) / 256
           .byte (om_s4 - om_s3) / 256, (om_s5 - om_s4) / 256, (om_s6 - om_s5) / 256
           .byte (om_t0 - om_s6) / 256

; variabili (si ricopiano con il codice)
track:  .byte 0                 ; brano (0-8)
play:   .byte 1                 ; 1: suona
osec:   .byte 0                 ; OMEGA: sezione
loops:  .byte 0                 ; e giri del canale 0
last:   .byte 0                 ; pagina alta del puntatore del canale 0 nel frame prima
lastlo: .byte 0
src:    .byte 0                 ; immagine in copia: pagina nella cartuccia, pagine rimaste,
left:   .byte 0                 ; destinazione
dst:    .byte 0
song:   .byte 0                 ; canzone da far partire a copia finita
dv:     .byte 0                 ; voce in disegno e suo terzo (0-2, da sinistra)
dh:     .byte 0
; presi al primo terzo: passo e fase (16 bit, 65536 = un periodo), forma, ampiezza
stp:    .word 0
ph:     .word 0
duty:   .byte 0
prev:   .byte 0                 ; riga del punto prima
col8:   .byte 0                 ; colonna: byte nella riga di celle (multiplo di 8) e bit
pbit:   .byte 0
cnt:    .byte 0
lfsr:   .byte $a5
acc:    .word 0

; Un terzo di oscilloscopio (dv, dh 0-2): al primo terzo prende la voce (forma, passo, larghezza
; dell'impulso, ampiezza), poi pulisce il suo terzo e disegna SC_PART colonne, ognuna un tratto
; verticale dalla riga di prima alla sua.
.proc draw_half
    lda #JB_LATE
    jsr frame_after
    bcc :+
    rts
:   lda dh
    bne half
    jsr latch
half:
    ; pulizia: le cinque righe di celle del terzo (32 byte ciascuna)
    ldy dh
    lda part_col,y
    sta col8
    ldx dv
    clc
    adc sc_lo,x
    sta ptr
    lda sc_hi,x
    adc #0
    sta ptr+1
    ldx #5
row:
    ldy #SC_PART - 1
    lda #0
:   sta (ptr),y
    dey
    bpl :-
    lda ptr
    clc
    adc #<320
    sta ptr
    lda ptr+1
    adc #>320
    sta ptr+1
    dex
    bne row
    ; righe della voce nelle tabelle degli indirizzi
    ldx dv
    lda ya_off,x
    sta yofs
    lda #$80
    sta pbit
    lda #SC_PART
    sta cnt
col:
    ; fase
    clc
    lda ph
    adc stp
    sta ph
    lda ph+1
    adc stp+1
    sta ph+1
sjmp:
    jmp flat                    ; (la forma della voce: latch)
saw:
    eor #$80
    jmp got
tri:
    clc
    adc #64
    asl a
    bcc got
    eor #$ff
    jmp got
pulse:
    cmp duty
    lda #0
    bcs got
    lda #$ff
    bne got
noise:
    lda lfsr                    ; (a punti, senza i tratti verticali)
    lsr a
    bcc :+
    eor #$b8
:   sta lfsr
    lsr a
    lsr a
    lsr a
    tay
    lda yq,y
    sta prev
    tax
    sta m_hi
    jmp seg
flat:
    lda #$80
got:
    lsr a
    lsr a
    lsr a
    tay
    lda yq,y                    ; riga 0-39
    ; tratto dalla riga di prima (X) a questa (A), dall'alto
    ldx prev
    sta prev
    cpx prev
    bcc down
    stx m_hi                    ; dalla nuova alla vecchia
    tax
    jmp seg
down:
    sta m_hi                    ; dalla vecchia alla nuova
seg:
    txa
    clc
    adc yofs
    tax
    lda m_hi
    clc
    adc yofs
    sta m_lo
cell:
    lda ya_lo,x                 ; la riga nella sua cella; le righe dopo nella stessa cella sono i
    sta ptr                     ; byte dopo
    lda ya_hi,x
    sta ptr+1
    ldy col8
pix:
    lda (ptr),y
    ora pbit
    sta (ptr),y
    cpx m_lo
    beq :+
    inx
    iny
    txa
    and #7                      ; (yofs multiplo di 8)
    bne pix
    beq cell
:   ; colonna dopo
    lsr pbit
    bcc :+
    lda #$80
    sta pbit
    lda col8
    clc
    adc #8
    sta col8
:   dec cnt
    beq :+
    jmp col
:   ldx dh                      ; terzo dopo, o la voce dopo
    inx
    cpx #3
    bcs :+
    stx dh
    rts
:   lda #0
    sta dh
    ldx dv
    inx
    cpx #3
    bcc :+
    ldx #0
:   stx dv
done:
    rts
.endproc
part_col: .byte 0, ::SC_PART, 2 * ::SC_PART
shape = draw_half::sjmp         ; (il jmp alla forma: latch ne cambia l'indirizzo)
sh_lo:  .lobytes draw_half::flat, draw_half::pulse, draw_half::saw, draw_half::tri, draw_half::noise
sh_hi:  .hibytes draw_half::flat, draw_half::pulse, draw_half::saw, draw_half::tri, draw_half::noise
yofs:   .byte 0
m_hi:   .byte 0
ya_off: .byte 0, ::SC_H, 2 * ::SC_H

; La voce dv come la suonano adesso i registri: forma (salto in draw_half), passo, larghezza
; dell'impulso, la tabella delle righe per l'ampiezza dell'inviluppo; fase 0, riga di partenza.
.proc latch
    ldx dv
    ldy vreg,x
    lda jb_regs + 4,y           ; forma: impulso, dente di sega, triangolo, rumore, o piatta
    ldx #0                      ; (piatta: senza forma, o con il bit di test)
    and #$f8
    cmp #$08
    bcc set
    and #$08
    bne set
    lda jb_regs + 4,y
    inx
    and #$40
    bne set
    lda jb_regs + 4,y
    inx
    and #$20
    bne set
    lda jb_regs + 4,y
    inx
    and #$10
    bne set
    inx
set:
    lda sh_lo,x
    sta shape + 1
    lda sh_hi,x
    sta shape + 2
    ; passo: frequenza * 13 / 16 (20 ms in 96 colonne)
    lda jb_regs,y
    sta stp
    lda jb_regs + 1,y
    sta stp+1
    lsr a
    sta acc+1
    lda stp
    ror a
    sta acc                     ; f / 2
    lsr acc+1
    ror acc
    lsr acc+1
    ror acc                     ; f / 8
    lda stp
    sec
    sbc acc
    sta stp
    lda stp+1
    sbc acc+1
    sta stp+1
    lsr acc+1
    ror acc                     ; f / 16
    lda stp
    sec
    sbc acc
    sta stp
    lda stp+1
    sbc acc+1
    sta stp+1
    cmp #>JB_MAXSTEP            ; al più JB_MAX_PER periodi (i tratti verticali costano)
    bcc :+
    lda #<JB_MAXSTEP
    sta stp
    lda #>JB_MAXSTEP
    sta stp+1
:   ; larghezza dell'impulso: 12 bit / 16
    lda jb_regs + 3,y
    asl a
    asl a
    asl a
    asl a
    sta duty
    lda jb_regs + 2,y
    lsr a
    lsr a
    lsr a
    lsr a
    ora duty
    sta duty
    ; ampiezza: l'inviluppo; la voce 2 nel filtro scalata dal taglio (il wobble)
    ldx dv
    lda env_lv,x
    lsr a
    lsr a
    lsr a
    lsr a
    tax
    lda amp_tab,x
    sta m_hi
    lda dv
    cmp #1
    bne :+
    lda sid_rf
    and #2
    beq :+
    lda sid_fc+1                ; taglio / 32 + 1 (1-4): ampiezza * quello / 4
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    cmp #3
    bcc :++
    lda #3
:   lda #3                      ; (fuori dal filtro: intera)
:   tax
    lda #0
:   clc
    adc m_hi
    dex
    bpl :-
    lsr a
    lsr a
    sta m_hi
    ; righe: y = 20 - ((valore / 8 - 16) * ampiezza) / 16, per i 32 valori
    lda m_hi                    ; acc = 8 - 16 * ampiezza (16 bit)
    asl a
    asl a
    asl a
    asl a
    sta acc
    lda m_hi
    lsr a
    lsr a
    lsr a
    lsr a
    sta acc+1
    lda #8
    sec
    sbc acc
    sta acc
    lda #0
    sbc acc+1
    sta acc+1
    ldx #0
:   lda acc
    lsr a
    lsr a
    lsr a
    lsr a
    sta m_lo
    lda acc+1
    asl a
    asl a
    asl a
    asl a
    ora m_lo
    eor #$ff
    sec
    adc #20
    sta yq,x
    lda acc
    clc
    adc m_hi
    sta acc
    bcc :+
    inc acc+1
:   inx
    cpx #32
    bne :--
    lda #0
    sta ph
    sta ph+1
    lda yq + 16                 ; riga del valore 0
    sta prev
    rts
.endproc
.segment "JBCODE3"

; ------------------------------------------------------------------------------------ inviluppi

; Un frame (20 ms) dell'inviluppo di ogni voce dai suoi registri: il gate che si apre fa partire
; l'attacco, chiuso il rilascio; dopo l'attacco il decadimento fino al sostegno. Livello 0-255.
; (Il registro di controllo della voce 3 conta solo dopo la canzone: gli effetti nel jukebox non ci
; sono.)
.proc envelopes
    ldx #2
voice:
    ldy vreg,x                  ; registri della voce
    lda jb_regs + 4,y
    and #1
    cmp env_g,x
    beq same
    sta env_g,x
    tay
    beq rel                     ; gate chiuso: rilascio (env_st 2)
    lda #0                      ; aperto: attacco
    sta env_st,x
    beq step                    ; (sempre)
rel:
    lda #2
    sta env_st,x
same:
step:
    ldy vreg,x
    lda env_st,x
    beq attack
    cmp #1
    beq decay
    ; rilascio verso 0
    lda jb_regs + 6,y
    and #15
    tay
    lda env_lv,x
    sec
    sbc dec_step,y
    bcs :+
    lda #0
:   sta env_lv,x
    jmp next
attack:
    lda jb_regs + 5,y
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    lda env_lv,x
    clc
    adc att_step,y
    bcc :+
    lda #255
    inc env_st,x                ; poi il decadimento
:   sta env_lv,x
    jmp next
decay:
    lda jb_regs + 6,y           ; sostegno * 17
    lsr a
    lsr a
    lsr a
    lsr a
    sta m_t
    asl a
    asl a
    asl a
    asl a
    ora m_t
    sta m_t
    lda jb_regs + 5,y
    and #15
    tay
    lda env_lv,x
    sec
    sbc dec_step,y
    bcc :+
    cmp m_t
    bcs :++
:   lda m_t
:   sta env_lv,x
next:
    dex
    bmi :+
    jmp voice
:   rts
.endproc
vreg:     .byte 0, 7, 14
; passo per frame (livello 0-255): attacco da 2 ms a 8 s, decadimento e rilascio tre volte più lenti
att_step: .byte 255, 255, 255, 212, 134, 91, 75, 64, 51, 20, 10, 6, 5, 2, 1, 1
dec_step: .byte 255, 212, 106, 71, 45, 30, 25, 21, 17, 7, 3, 2, 2, 1, 1, 1
; ampiezza in pixel (0-19) per livello / 16
amp_tab:  .byte 0, 1, 3, 4, 5, 6, 8, 9, 10, 11, 13, 14, 15, 16, 18, 19

.endscope
jb_enter = jb::enter
jb_scene = jb::jbscene
.segment "CODE"
