; Finale di CHALLENGE, quando si batte l'ultimo avversario (rust/game/src/ending_ui.rs): al posto
; della schermata CHAMPION, prima delle iniziali. Sei parti in fila, come sul PC:
;   1. CONGRATULATIONS! che lampeggia e, dopo un secondo, YOU WIN! con la voce del SID;
;   2. la sfilata dei sette avversari battuti (le racchette vere negli sprite, una al secondo) con
;      il timbro rosso DEFEATED mezzo secondo dopo;
;   3. il punteggio: SCORE che sale in 3 s, CHAMPION BONUS in 1 s, poi TOTAL, che resta;
;   4. YOU ARE THE PADD WS CHAMPION con i fuochi d'artificio: razzi negli sprite che salgono
;      rallentando, poi lo scoppio con la gravità, sei tipi a turno (anello, salice, palma,
;      crisantemo, crepitio, croce che si divide);
;   5. i titoli di coda che salgono dal basso, a sezioni, finché l'ultima riga arriva al centro;
;   6. THE END che lampeggia.
; Start (fuoco di chi gioca, RETURN, SPAZIO o 1) salta tutto dopo mezzo secondo. Poi ch_finish:
; iniziali o classifica. Colori: solo bianco, giallo e rosso sul nero; le scintille non si
; scuriscono, si diradano (alive di ending_ui.rs). Il bordo resta nero, come in tutte le
; schermate fuori dalla partita (BORDER GRAY vale per la partita e la demo). Musica: la canzone
; ENDING di tools/gen_sid_music.py (SID_SONG_ENDING del player del C64, tracce qui); niente
; effetti, perché la terza voce della canzone è la batteria.
;
; Dove sta. Nel programma solo end_enter (challenge.s), la canzone nel player e la scena; il resto
; è nella cartuccia (banchi da END_BANK, l'uscita %O.end di ld65, tools/make_crt.py) e gira nella
; bitmap dell'attract ($E000-$FEFF), che dopo il finale si rifà sempre da capo, e al posto del set
; di caratteri del programma ($C800), che alla fine si rimette dalla cartuccia:
;   ENDA  $E000-$EAFF  pagina 0: avvio, scena, caricatore (end_enter la copia); poi il resto
;   ENDB  $EC00-$EFFF  terza traccia della canzone e codice
;   ENDC  $FB00-$FEFF  prime due tracce della canzone e codice
;   ENDCH $C800-$CFFF  set di caratteri del finale (gen/ending_chars.bin, tools/gen_c64_assets.py)
;   ENDD  $EB00-$EBFF  dopo la voce: lo sprite del razzo
;   ENDE  $F000-$FAFF  dopo la voce: i fuochi d'artificio
; Il file del primo livello ha lasciato in memoria il player delle voci ($EB20, NMI a $FA01): YOU
; WIN usa quello, con i campioni a WIN_SAMPLES (dal banco della vittoria, voice.inc), quindi ENDD
; ed ENDE arrivano solo dopo la voce. Prima della voce, nei primi frame a schermo spento, ENDA (il
; resto), ENDB, ENDC, ENDCH e i campioni, E_LOAD_PAGES pagine per frame (circa 11.500 cicli).
;
; Schermo: caratteri, con il set del finale (il font del programma ai suoi codici: le routine del
; programma scrivono come sempre). Le lettere grandi sono il font a scala 2 (2x2 caratteri). I
; fuochi usano il modo multicolore: i caratteri dei punti hanno i colori nei bit ($D022 bianco,
; $D023 giallo, rosso dal colore del carattere, uguale per tutto il cielo), quindi si disegnano in
; un secondo schermo ($C400) mentre si vede il primo, e si scambiano (doppio buffer) senza toccare
; la RAM dei colori. Anche i titoli di coda usano i due schermi, con lo scorrimento fine
; ($D011, 24 righe): a ogni riga intera si scambiano e i colori delle righe con il testo si
; scrivono nel vblank, davanti al raster.

.include "ending.inc"

; parti
EP_LOAD     = 0                 ; copia dalla cartuccia, schermo spento
EP_CONGRATS = 1
EP_PARADE   = 2
EP_SCORE    = 3
EP_CHAMP    = 4
EP_CREDITS  = 5
EP_THEEND   = 6
EP_CLOSE    = 7                 ; il set di caratteri del programma torna dalla cartuccia

; tempi in frame (ending_ui.rs)
E_CONGRATS  = 175               ; 3,5 s
E_PARADE    = 450
E_SCORE     = 450
E_CHAMP     = FW_CHAMPION
E_THEEND    = 150
E_HOLD      = 100               ; titoli: l'ultima riga ferma al centro
E_YOUWIN    = 50                ; YOU WIN! e la voce un secondo dopo CONGRATULATIONS
E_SKIP      = 25                ; Start salta il finale dopo mezzo secondo
E_STEP      = 25                ; sfilata: un avversario al secondo, il timbro mezzo secondo dopo
E_SCORE_N   = 150               ; SCORE sale in 3 s
E_BONUS_N   = 50                ; il premio in 1 s
E_TOTAL_AT  = 225               ; TOTAL a 4,5 s
E_FLASH     = 25                ; CONGRATULATIONS: giallo e bianco ogni 0,5 s
E_FLASH_END = 33                ; THE END: ogni 0,66 s
E_LOAD_PAGES = 3                ; pagine copiate per frame (circa 3.800 cicli l'una)
FW_CHAMPION = 350
END_RUN     = $E000             ; pagina 0 del finale (end_enter la copia)

; pagine nel file del finale (l'ordine delle aree in paddws.cfg)
EPG_A  = 0
EPG_B  = 11
EPG_C  = 15
EPG_CH = 19
EPG_D  = 27
EPG_E  = 28
EPG_BANK = 32                   ; pagine della ROML per banco
; (le aree hanno le misure fisse di paddws.cfg: ld65 controlla che i segmenti ci stiano)

; schermi (doppio buffer): il secondo a $C400, come i colori della bitmap dell'attract
SCR_B    = $04                  ; da aggiungere al byte alto delle righe di SCREEN
D018_A   = $02                  ; schermo $C000, caratteri $C800
D018_B   = $12                  ; schermo $C400
SKY_ROWS = 18                   ; fuochi nelle righe 0-17 (griglia di 4 pixel: 36 righe)
COL_FWSKY = 8 + COL_RED         ; cielo: multicolore, %11 rosso

; ------------------------------------------------------------------------------------ pagina 0

.segment "ENDA"
end_run:

; Da end_enter (challenge.s), con questa pagina appena copiata: schermo spento, la scena del
; finale copia il resto nei frame dopo.
.proc end_init
    lda #0
    sta sh_enable
    sta e_part                  ; EP_LOAD
    sta e_chunk
    sta e_pg
    lda #MODE_OFF
    sta sh_mode
    lda #ST_ENDING
    sta state
    rts
.endproc
.assert end_init = END_RUN, error, "end_init fuori posto"

; Scena del finale, un frame.
.proc end_scene
    lda e_part
    beq :+
    jmp end_frame
:   jsr load_step               ; EP_LOAD: copia, poi CONGRATULATIONS!
    bcc :+
    jsr next_part
    jmp e_tick
:   rts
.endproc

; Un passo della copia dalla cartuccia: il pezzo corrente della tabella load_tab (banco, pagina
; della ROML, pagina di arrivo, pagine), al più E_LOAD_PAGES pagine. C = 1 alla fine di una fase
; (lo 0 della tabella), senza copiare: e_chunk passa alla fase dopo.
.proc load_step
    ldy e_chunk
    lda load_tab,y
    beq stage
    sta e_bank
    lda load_tab+3,y
    sec
    sbc e_pg
    cmp #E_LOAD_PAGES + 1
    bcc :+
    lda #E_LOAD_PAGES
:   sta e_n
    lda load_tab+1,y
    clc
    adc e_pg
    sta ef_src+2
    lda load_tab+2,y
    clc
    adc e_pg
    tay
    lda e_bank
    ldx e_n
    jsr ef_copy
    lda e_pg
    clc
    adc e_n
    sta e_pg
    ldy e_chunk
    cmp load_tab+3,y
    bcc :+
    lda #0
    sta e_pg
    tya
    adc #3                      ; (C = 1)
    sta e_chunk
:   clc
    rts
stage:
    iny
    sty e_chunk
    sec
    rts
.endproc

; Pezzi: prima della voce il resto di ENDA, ENDB, ENDC, il set di caratteri e i campioni di YOU WIN;
; dopo la voce ENDD ed ENDE (che passa al banco dopo).
.macro piece page, run, n
    .byte END_BANK + (page) / EPG_BANK, $80 + (page) .mod EPG_BANK, >(run), n
.endmacro
load_tab:
    piece EPG_A + 1, end_run + $100, EPG_B - EPG_A - 1
    piece EPG_B, $EC00, EPG_C - EPG_B
    piece EPG_C, $FB00, EPG_CH - EPG_C
    piece EPG_CH, CHARSET, EPG_D - EPG_CH
    .byte WIN_BANK, $80 + >(WIN_SAMPLES - WIN_RUN), >WIN_SAMPLES, 10
    .byte 0
    piece EPG_D, WIN_RUN, 1
    piece EPG_E, WIN_SAMPLES, EPG_BANK - EPG_E
    piece EPG_BANK, WIN_SAMPLES + (EPG_BANK - EPG_E) * 256, 11 - (EPG_BANK - EPG_E)
    .byte 0
.assert (WIN_DESC & $ff00) < WIN_SAMPLES + 10 * 256, error, "finale: descrittore di YOU WIN fuori dalle pagine copiate"

; variabili del finale (si ricopiano a ogni finale)
e_part:   .byte 0
e_chunk:  .byte 0               ; copia: pezzo (indice in load_tab), pagine già copiate
e_pg:     .byte 0
e_bank:   .byte 0
e_n:      .byte 0
.assert * <= end_run + $100, error, "finale: la pagina 0 (copiata da end_enter) è piena"

; (dalla pagina 1: si usano solo dopo la copia)
e_t:      .word 0               ; frame dall'inizio della parte
e_skip:   .byte 0               ; frame dall'inizio (fino a E_SKIP)
e_voiced: .byte 0               ; YOU WIN detta
e_bdone:  .byte 0               ; ENDD ed ENDE copiati

; ------------------------------------------------------------------------------------ comuni

; Un frame dopo la copia. Fra una parte e l'altra due frame a schermo spento: nel primo lo schermo
; si pulisce (circa 11.500 cicli), nel secondo la parte nuova lo disegna (la sua entrata); poi la
; parte, con il tempo da zero.
.proc end_frame
    cmp #EP_CLOSE
    bne :+
    jmp close_frame
:   ; salto: dopo E_SKIP frame, Start di chi gioca
    lda e_skip
    cmp #E_SKIP
    bcs :+
    inc e_skip
    bne run
:   jsr champ_start
    bcc run
    jmp close_enter
run:
    lda e_new
    bne change
    ; ENDD ed ENDE dopo la voce (detta e finita: niente copie con gli NMI della voce)
    lda e_bdone
    bne :+
    lda e_voiced
    beq :+
    bit $fffb
    bmi :+
    jsr load_step
    rol e_bdone
:   jsr dispatch
    jmp e_tick
change:
    dec e_new
    beq :+
    lda #COL_WHITE
    jsr clear_text
    jmp e_tick
:   jsr enter
.endproc
; (prosegue) Il tempo della parte.
.proc e_tick
    inc e_t
    bne :+
    inc e_t+1
:   rts
.endproc

.proc dispatch
    lda e_part
    asl a
    tax
    lda part_tab-1,x
    pha
    lda part_tab-2,x
    pha
    rts
.endproc

.proc enter
    lda e_part
    asl a
    tax
    lda enter_tab-1,x
    pha
    lda enter_tab-2,x
    pha
    rts
.endproc

part_tab:  .word congrats_frame - 1, parade_frame - 1, score_frame - 1, champ_frame - 1
           .word credits_frame - 1, theend_frame - 1
enter_tab: .word congrats_enter - 1, parade_enter - 1, score_enter - 1, champ_enter - 1
           .word credits_enter - 1, theend_enter - 1

; Passa alla parte dopo: schermo spento, i due frame del cambio (end_frame), poi la parte con il
; tempo da zero (e_tick lo porta avanti in questo frame e nei due del cambio).
.proc next_part
    inc e_part
    lda #<-3
    sta e_t
    lda #>-3
    sta e_t+1
    lda #2
    sta e_new
    lda #MODE_OFF
    sta sh_mode
    lda #0
    sta sh_enable
    rts
.endproc
e_new: .byte 0                  ; frame del cambio di parte rimasti (2: pulizia, 1: entrata)

; C = 1 se e_t vale A:X (byte alto in X).
.proc at_time
    cmp e_t
    bne no
    cpx e_t+1
    bne no
    sec
    rts
no:
    clc
    rts
.endproc

; Lo schermo (già pulito nel cambio di parte) si vede, senza sprite.
.proc fresh_screen
    lda #MODE_TEXT
    sta sh_mode
    lda #0
    sta sh_enable
    rts
.endproc

; Scritta grande (scala 2) da (ptr2), dalla colonna X, righe Y e Y + 1, nello schermo SCREEN più
; e_scr pagine (0 o SCR_B).
.proc big_at
    stx v_col
    sty v_row
    ldy #0
loop:
    lda (ptr2),y
    beq done
    sty v_n
    sec
    sbc #32
    tax
    lda big_idx,x
    tax
    ldy v_row
    lda row_lo,y
    sta ptr
    lda row_hi,y
    clc
    adc e_scr
    sta ptr+1
    ldy v_col
    lda big_tl,x
    sta (ptr),y
    iny
    lda big_tr,x
    sta (ptr),y
    lda ptr
    clc
    adc #40
    sta ptr
    bcc :+
    inc ptr+1
:   lda big_br,x
    sta (ptr),y
    dey
    lda big_bl,x
    sta (ptr),y
    inc v_col
    inc v_col
    ldy v_n
    iny
    bne loop
done:
    rts
.endproc

; La scritta grande che segue la chiamata (jsr big_print / .byte colonna, riga, "TESTO", 0), nel
; primo schermo.
.proc big_print
    pla
    sta ptr2
    pla
    sta ptr2+1
    ldy #1
    lda (ptr2),y
    sta e_col
    iny
    lda (ptr2),y
    sta e_row
    lda ptr2
    clc
    adc #3
    sta ptr2
    bcc :+
    inc ptr2+1
:   lda #0
    sta e_scr
    ldx e_col
    ldy e_row
    jsr big_at
    ; ritorno dopo lo 0 finale (Y = lunghezza)
    tya
    sec
    adc ptr2
    sta ptr2
    bcc :+
    inc ptr2+1
:   jmp (ptr2)
.endproc

; Colore A per le righe Y e Y + 1.
.proc color_rows2
    sta e_c
    sty e_row
    jsr color_row
    ldy e_row
    iny
    lda e_c
    jmp color_row
.endproc

; Lampeggio di una scritta grande alle righe Y e Y + 1: ogni A frame il colore passa dal giallo al
; bianco e viceversa (giallo all'inizio, e_blink = 0).
.proc e_blinker
    dec e_blink
    bpl done
    sec
    sbc #1
    sta e_blink
    lda e_bcol
    eor #COL_YELLOW ^ COL_WHITE
    sta e_bcol
    jmp color_rows2
done:
    rts
.endproc

; Numero ch_tmp in 7 cifre in ch_txt, puntato da ptr2.
.proc e_digits
    jsr num7
    lda #<ch_txt
    sta ptr2
    lda #>ch_txt
    sta ptr2+1
    rts
.endproc

big_idx: .byte END_BIG_IDX
big_tl:  .byte END_BIG_TL
big_tr:  .byte END_BIG_TR
big_bl:  .byte END_BIG_BL
big_br:  .byte END_BIG_BR

e_scr:   .byte 0
e_col:   .byte 0
e_row:   .byte 0
e_c:     .byte 0
e_blink: .byte 0
e_bcol:  .byte COL_WHITE

; ------------------------------------------------------------------------------------ CONGRATULATIONS

.proc congrats_enter
    jsr fresh_screen
    jsr big_print
    .byte 4, 10, "CONGRATULATIONS!", 0
    lda #SID_SONG_ENDING
    jmp sid_song
.endproc

.proc congrats_frame
    lda #E_FLASH
    ldy #10
    jsr e_blinker
    lda #E_YOUWIN
    ldx #0
    jsr at_time
    bcc :+
    jsr big_print
    .byte 12, 15, "YOU WIN!", 0
    ldx #<WIN_DESC              ; la voce, con il player del file del primo livello
    ldy #>WIN_DESC
    jsr VOICE_SAY
    inc e_voiced
:   lda #<E_CONGRATS
    ldx #>E_CONGRATS
    jsr at_time
    bcc :+
    jmp next_part
:   rts
.endproc

; ------------------------------------------------------------------------------------ THE END

.proc theend_enter
    jsr fresh_screen
    lda #$c8                    ; fine dei titoli: niente scorrimento
    sta $d016
    lda #0
    sta e_blink
    lda #COL_WHITE
    sta e_bcol
    jsr big_print
    .byte 13, 11, "THE END", 0
    rts
.endproc

.proc theend_frame
    lda #E_FLASH_END
    ldy #11
    jsr e_blinker
    lda #<E_THEEND
    ldx #>E_THEEND
    jsr at_time
    bcc :+
    jmp close_enter
:   rts
.endproc

; ------------------------------------------------------------------------------------ uscita

; Fine o salto: la voce si ferma, registri come prima, poi il set di caratteri del programma
; dalla cartuccia (EP_CLOSE, a schermo spento).
.proc close_enter
    bit $fffb                   ; voce in corso: si ferma (il SID torna al programma)
    bpl :+
    jsr VOICE_HUSH
:   lda #EP_CLOSE
    sta e_part
    lda #0
    sta e_pg
    sta sh_enable
    sta $d01b
    lda #MODE_OFF
    sta sh_mode
    lda #$c8
    sta $d016
    lda #COL_GRAY               ; il grigio delle racchette
    sta $d025
    lda #$ff
    sta pd_n
    sta pd_n+1
    rts
.endproc

.proc close_frame
    lda e_pg
    cmp #8
    bcs done
    ora #$80
    sta ef_src+2
    lda e_pg
    clc
    adc #>CHARSET
    tay
    lda e_pg
    clc
    adc #E_LOAD_PAGES
    sta e_pg
    ldx #E_LOAD_PAGES
    cmp #8 + 1
    bcc :+
    ldx #8 - 2 * E_LOAD_PAGES
:   lda #CHARSET_BANK
    jmp ef_copy
done:
    ; finito: schermo vuoto (la schermata dopo lo pulisce nel suo primo frame, che si vede già),
    ; le tabelle dei quadrati da rifare (qui c'erano i campioni e i fuochi), la musica delle iniziali
    jsr clear_screen
    ; i fuochi usano come variabili anche i byte alti dei puntatori dei quadrati (fq2, fthr2, fage,
    ; fn), che fuori dal finale non cambiano mai: di nuovo quelli di math_init, se no ogni prodotto
    ; dopo il finale è sbagliato
    lda #>square1_lo
    sta sq1_lo+1
    lda #>square1_hi
    sta sq1_hi+1
    lda #>square2_lo
    sta sq2_lo+1
    lda #>square2_hi
    sta sq2_hi+1
    jsr math_invalidate
    lda #SID_SONG_CHAMPION
    jsr sid_song
    jmp ch_finish
.endproc
.assert 8 - 2 * E_LOAD_PAGES > 0 .and 8 - 2 * E_LOAD_PAGES <= E_LOAD_PAGES, error, "uscita: pagine del set di caratteri"

; ------------------------------------------------------------------------------------ titoli

; Righe virtuali: la riga R + r - 25 del testo nella riga r dello schermo, con lo scorrimento fine
; (e_s in 1/8 di pixel: R = e_s / 64). Lo schermo nascosto si prepara riga per riga (CRED_ROWS per
; frame) per la R dopo; quando R cambia si scambiano gli schermi e si scrivono i colori.
CRED_SPEED = 9                  ; 1/8 di pixel ogni due frame: 0,56 pixel per frame
CRED_END   = (END_CRED_LAST + 13) * 64    ; l'ultima riga di testo al centro (righe 12-13)
CRED_ROWS  = 5                  ; righe preparate per frame


cred_rows:  .byte END_CRED_ROW
cred_col:   .byte END_CRED_COL
cred_style: .byte END_CRED_STYLE
cred_len:   .byte END_CRED_LEN
cred_lo:
    .repeat END_CRED_LINES, i
    .byte <(cred_text + .mid(i * 2, 1, {END_CRED_OFF}))
    .endrepeat
cred_hi:
    .repeat END_CRED_LINES, i
    .byte >(cred_text + .mid(i * 2, 1, {END_CRED_OFF}))
    .endrepeat
cred_text: .byte END_CRED_TEXT

e_s:     .word 0                ; scorrimento in 1/8 di pixel
e_R:     .byte 0                ; righe intere dello schermo davanti
e_rnext: .byte 0                ; R dello schermo nascosto
e_rr:    .byte 0                ; prossima riga da preparare nello schermo nascosto
e_front: .byte 0                ; schermo davanti: 0 o SCR_B
e_hold:  .byte 0
e_line:  .byte 0

.proc champ_enter
    jsr fresh_screen
    lda egg_red                 ; cielo multicolore (righe 0-17), il testo sotto bianco: COL_FWSKY,
    ora #8                      ; con il giallo dell'easter egg (egg_check) al posto del rosso
    ldx #SKY_ROWS * 40 / 3
:   sta $d800 - 1,x
    sta $d800 + SKY_ROWS * 40 / 3 - 1,x
    sta $d800 + SKY_ROWS * 40 * 2 / 3 - 1,x
    dex
    bne :-
    jsr print_at
    .byte 14, 19, "YOU ARE THE", 0
    jsr big_print
    .byte 4, 21, "PADD WS CHAMPION", 0
    lda #COL_YELLOW
    ldy #21
    jsr color_rows2
    ; le righe del testo anche nel secondo schermo (il suo cielo lo pulisce sky_clear)
    ldx #(25 - SKY_ROWS) * 20
:   lda SCREEN + SKY_ROWS * 40 - 1,x
    sta SCREEN + $400 + SKY_ROWS * 40 - 1,x
    lda SCREEN + SKY_ROWS * 40 + (25 - SKY_ROWS) * 20 - 1,x
    sta SCREEN + $400 + SKY_ROWS * 40 + (25 - SKY_ROWS) * 20 - 1,x
    dex
    bne :-
    ; multicolore: %01 bianco, %10 giallo
    lda #$d8
    sta $d016
    lda #COL_WHITE
    sta $d022
    lda egg_yel
    sta $d023
    jmp fw_init                 ; (il cielo del secondo schermo lo pulisce il primo passo)
.endproc

.proc champ_frame
    lda #D018_A
    ldx fw_front
    beq :+
    lda #D018_B
:   sta $d018
    jsr fw_frame
    lda #<E_CHAMP
    ldx #>E_CHAMP
    jsr at_time
    bcc :+
    lda #0
    sta sh_enable
    jmp next_part
:   rts
.endproc

; ------------------------------------------------------------------------------------ sfilata

PARADE_Y   = 77                 ; centro delle racchette (pixel)
PARADE_SPR = $C400              ; immagini delle racchette, una per sprite (puntatori 16-22)
STAMP_ROW  = 9

.proc parade_enter
    jsr fresh_screen
    jsr big_print
    .byte 6, 2, "YOUR OPPONENTS", 0
    lda #COL_YELLOW
    ldy #2
    jsr color_rows2
    ; sprite 0-6: le racchette, multicolore ed espanse in verticale, dietro le scritte (il timbro)
    lda #$7f
    sta sh_mc
    sta sh_yexp
    sta $d01b
    lda #0
    sta sh_xexp
    sta sh_msb
    sta e_k
    sta e_due
    lda egg_yel                 ; segni dei tipi: solo giallo ($D025 era il grigio)
    sta $d025
    ldx #6
:   lda #COL_WHITE
    sta sh_col,x
    txa
    clc
    adc #(PARADE_SPR - $C000) / 64
    sta sh_ptr,x
    dex
    bpl :-
    rts
.endproc

.proc parade_frame
    ; immagini: una per frame nei primi 7 (pad_image del programma, come le anteprime della scelta)
    lda e_t+1
    bne events
    lda e_t
    cmp #7
    bcs events
    jsr make_pad
events:
    ; ogni E_STEP frame un avversario (k pari) o il suo timbro (k dispari)
    lda e_k
    cmp #14
    bcs end
    dec e_due
    bpl end
    lda #E_STEP - 1
    sta e_due
    lda e_k
    inc e_k
    lsr a
    tax                         ; avversario
    bcs stamp
    jsr show_pad
    jmp end
stamp:
    jsr show_stamp
end:
    lda #<E_PARADE
    ldx #>E_PARADE
    jsr at_time
    bcc :+
    lda #0                      ; sprite come prima
    sta sh_enable
    sta $d01b
    lda #$ff                    ; in partita le immagini delle racchette si rifanno
    sta pd_n
    sta pd_n+1
    jmp next_part
:   rts
.endproc

; Immagine della racchetta del tipo e_t nello sprite PARADE_SPR + tipo * 64.
.proc make_pad
    sta e_c
    sta pi_kind
    tax
    lda #0
    sta pi_side
    lda pv_rows,x
    sta pi_n
    lda pv_var,x
    sta pi_var
    cpx #K_BLASTER
    bne :+
    lda #P_BLASTER_SHOTS        ; caricatore pieno
    jsr mag_setup
:   jsr pad_image
    lda e_c
    lsr a
    lsr a
    clc
    adc #>PARADE_SPR
    sta ptr+1
    lda e_c                     ; (tipo & 3) * 64
    lsr a
    ror a
    ror a
    and #$c0
    sta ptr
    ldy #IMG_BYTES - 1
:   lda sh_img,y
    sta (ptr),y
    dey
    bpl :-
    rts
.endproc

; Avversario X: la racchetta (sprite X) e il nome sotto (righe 14 e 16 a turno).
.proc show_pad
    stx e_c
    lda bit_of,x
    ora sh_enable
    sta sh_enable
    ; x: centro 44 + 40 * X; y: centrata su PARADE_Y (due righe di pixel per riga dello sprite)
    lda epad_x,x
    sta sh_x,x
    cpx #5
    bcc :+
    lda bit_of,x
    ora sh_msb
    sta sh_msb
:   lda #<(SPR_Y0 + PARADE_Y)
    sec
    sbc pv_rows,x
    sta sh_y,x
    ; nome
    lda name_lo,x
    sta ptr2
    lda name_hi,x
    sta ptr2+1
    ldy #14
    txa
    lsr a
    bcc :+
    ldy #16
:   lda name_col,x
    tax
    jmp print_str
.endproc

; Timbro DEFEATED rosso dell'avversario X (5x3 caratteri, centrato sulla racchetta).
.proc show_stamp
    lda stamp_col,x
    sta e_col
    lda #STAMP_ROW
    sta e_row
    ldx #0
row:
    stx e_c
    ldy e_row
    lda row_lo,y
    clc
    adc e_col
    sta ptr
    lda row_hi,y
    adc #0
    sta ptr+1
    ldy #0
:   lda stamp_tiles,x
    sta (ptr),y
    lda ptr+1                   ; colore: la stessa cella nella RAM dei colori
    pha
    clc
    adc #>($d800 - SCREEN)
    sta ptr+1
    lda egg_red
    sta (ptr),y
    pla
    sta ptr+1
    inx
    iny
    cpy #END_STAMP_W
    bne :-
    inc e_row
    cpx #END_STAMP_W * END_STAMP_H
    bne row
    rts
.endproc

.macro pad_names n0, n1, n2, n3, n4, n5, n6
    name_lo:  .lobytes n0, n1, n2, n3, n4, n5, n6
    name_hi:  .hibytes n0, n1, n2, n3, n4, n5, n6
.endmacro
pad_names n_arcade, n_titan, n_hammer, n_twist, n_blaster, n_rush, n_guardian
; colonna del nome: centrato su 44 + 40 * k pixel
name_col: .byte 3, 8, 13, 18, 22, 29, 32
epad_x:
    .repeat 7, k
    .byte <(SPR_X0 + 44 + 40 * k - 12)
    .endrepeat
stamp_col:
    .repeat 7, k
    .byte 3 + 5 * k
    .endrepeat
stamp_tiles: .byte END_STAMP
n_arcade:   .byte "ARCADE", 0
n_titan:    .byte "TITAN", 0
n_hammer:   .byte "HAMMER", 0
n_twist:    .byte "TWIST", 0
n_blaster:  .byte "BLASTER", 0
n_rush:     .byte "RUSH", 0
n_guardian: .byte "GUARDIAN", 0
e_k:   .byte 0                  ; prossimo evento della sfilata (avversario * 2 + timbro)
e_due: .byte 0                  ; frame che mancano all'evento (- 1)

.proc score_frame
    ldy e_t+1
    bne bonus
    lda e_t
    cmp #E_SCORE_N
    bcs bonus
    ; SCORE che sale
    ldx #0
    jsr e_count
    ldx #22
    ldy #8
    jsr print_tmp
    jmp total
bonus:
    lda #E_SCORE_N
    ldx #0
    jsr at_time
    bcc :+
    jsr print_at
    .byte 4, 11, "CHAMPION BONUS   +", 0
    lda #COL_YELLOW
    ldy #11
    jsr color_row
:   ldy e_t+1
    bne total
    lda e_t
    cmp #E_SCORE_N + E_BONUS_N
    bcs total
    ; il premio che sale: + e sei cifre
    ldx #e_bon - e_vals
    jsr e_count
    jsr num7
    lda #<(ch_txt + 1)
    sta ptr2
    lda #>(ch_txt + 1)
    sta ptr2+1
    ldx #22
    ldy #11
    jsr print_str
total:
    lda #E_TOTAL_AT
    ldx #0
    jsr at_time
    bcc later
    jsr big_print
    .byte 4, 15, "TOTAL", 0
    ldx #3
:   lda ch_score,x
    sta ch_tmp,x
    dex
    bpl :-
    jsr e_digits
    lda #0
    sta e_scr
    ldx #18
    ldy #15
    jsr big_at
later:
    lda #<E_SCORE
    ldx #>E_SCORE
    jsr at_time
    bcc :+
    jmp next_part
:   rts
.endproc

; Conto del valore e_vals + X: e_cur += passo, al più il valore; il risultato in ch_tmp.
.proc e_count
    clc
    lda e_cur,x
    adc e_vals+4,x
    sta ch_tmp
    lda e_cur+1,x
    adc e_vals+5,x
    sta ch_tmp+1
    lda e_cur+2,x
    adc e_vals+6,x
    sta ch_tmp+2
    lda e_cur+3,x
    adc e_vals+7,x
    sta ch_tmp+3
    ; oltre il valore: il valore
    lda ch_tmp+3
    cmp e_vals+3,x
    bne :+
    lda ch_tmp+2
    cmp e_vals+2,x
    bne :+
    lda ch_tmp+1
    cmp e_vals+1,x
    bne :+
    lda ch_tmp
    cmp e_vals,x
:   bcc keep
    lda e_vals,x
    sta ch_tmp
    lda e_vals+1,x
    sta ch_tmp+1
    lda e_vals+2,x
    sta ch_tmp+2
    lda e_vals+3,x
    sta ch_tmp+3
keep:
    lda ch_tmp
    sta e_cur,x
    lda ch_tmp+1
    sta e_cur+1,x
    lda ch_tmp+2
    sta e_cur+2,x
    lda ch_tmp+3
    sta e_cur+3,x
    rts
.endproc

; valori (32 bit) e passi: punti prima del premio, premio
e_vals:
e_base:  .res 8                 ; valore, passo
e_bon:   .res 8
e_cur:   .res 12                ; valori a schermo (e_base, e_bon), allo stesso offset
.assert e_cur - e_vals = 16, error, "finale: e_cur fuori posto"
e_div:   .res 1
e_rem:   .res 1
e_q:     .res 4

overlay_end:

; Scintille dei fuochi: nella RAM del codice della sfilata e del punteggio, che a quel punto non
; serve più (il finale si ricopia sempre da capo).
FW_PARTS = FW_SLOTS * FW_MAX
p_xl = parade_enter
p_xh = p_xl + FW_PARTS
p_yl = p_xh + FW_PARTS
p_yh = p_yl + FW_PARTS
p_vx = p_yh + FW_PARTS
p_vy = p_vx + FW_PARTS
p_c  = p_vy + FW_PARTS
.assert p_c + FW_PARTS <= overlay_end, error, "fuochi: le scintille oltre la sfilata e il punteggio"

; ------------------------------------------------------------------------------------ punteggio

.segment "ENDB"
end_arp: .incbin "ending.bin", SID_ENDING_ARP, SID_ENDING_SIZE - SID_ENDING_ARP

.proc score_enter
    jsr fresh_screen
    jsr big_print
    .byte 9, 4, "FINAL SCORE", 0
    lda #COL_YELLOW
    ldy #4
    jsr color_rows2
    jsr print_at
    .byte 9, 8, "SCORE", 0
    ; premio del campione (vittoria e partita perfetta, già sommati da enter_clear) e punti prima
    clc
    lda ch_bonus
    adc ch_bonus+2
    sta e_bon
    lda ch_bonus+1
    adc ch_bonus+3
    sta e_bon+1
    lda #0
    rol a
    sta e_bon+2
    lda #0
    sta e_bon+3
    ldx #0
    sec
:   lda ch_score,x
    sbc e_bon,x
    sta e_base,x
    inx
    txa
    eor #4
    bne :-
    ; passi: SCORE in E_SCORE_N frame, il premio in E_BONUS_N
    ldx #e_base - e_vals
    lda #E_SCORE_N
    jsr step_of
    ldx #e_bon - e_vals
    lda #E_BONUS_N
    jsr step_of
    lda #0
    ldx #11
:   sta e_cur,x
    dex
    bpl :-
    rts
.endproc

; Passo del conto del valore e_vals + X (32 bit): valore / A + 1, in e_vals + X + 4.
.proc step_of
    sta e_div
    lda #0
    sta e_rem
    ldy #32
    lda e_vals,x                ; quoziente al posto del dividendo (copia)
    sta e_q
    lda e_vals+1,x
    sta e_q+1
    lda e_vals+2,x
    sta e_q+2
    lda e_vals+3,x
    sta e_q+3
:   asl e_q
    rol e_q+1
    rol e_q+2
    rol e_q+3
    rol e_rem                   ; resto a 9 bit: con il nono acceso è oltre il divisore
    lda e_rem
    bcs sub
    cmp e_div
    bcc :+
sub:
    sbc e_div                   ; (C = 1)
    sta e_rem
    inc e_q
:   dey
    bne :--
    sec
    lda e_q
    adc #0
    sta e_vals+4,x
    lda e_q+1
    adc #0
    sta e_vals+5,x
    lda e_q+2
    adc #0
    sta e_vals+6,x
    lda e_q+3
    adc #0
    sta e_vals+7,x
    rts
.endproc

.segment "ENDC"
end_bass: .incbin "ending.bin", 0, SID_ENDING_LEAD
end_lead: .incbin "ending.bin", SID_ENDING_LEAD, SID_ENDING_ARP - SID_ENDING_LEAD

.segment "ENDCH"
    .incbin "ending_chars.bin"

.segment "ENDA"
; ------------------------------------------------------------------------------------ fuochi

; Dopo la voce (ENDD ed ENDE). Un passo dei fuochi ogni FW_FRAMES frame, diviso nei tre frame:
; 0 lo schermo nascosto vuoto (il cielo) e il fuoco 0, 1 i fuochi 1 e 2, 2 il fuoco 3 e lo scambio
; degli schermi. I razzi (sprite 0-2) a ogni frame.
.segment "ENDD"
rocket_img:                     ; multicolore: testa bianca (%10), scia gialla (%11, %01)
    .byte $00, $20, $00
    .byte $00, $20, $00
    .byte $00, $00, $00
    .byte $00, $30, $00
    .byte $00, $30, $00
    .byte $00, $00, $00
    .byte $00, $10, $00
    .res 64 - 21, 0
ROCKET_IMG = WIN_RUN
.assert rocket_img = ROCKET_IMG, lderror, "razzo: sprite fuori posto"
ROCKET_PTR = (ROCKET_IMG - $C000) / 64
RK_HEAD_X  = 11                 ; pixel della testa nello sprite

.segment "ENDE"

.proc credits_enter
    jsr fresh_screen
    lda #0
    sta e_s
    sta e_s+1
    sta e_R
    sta e_rr
    sta e_front
    sta e_hold
    lda #$c8                    ; niente multicolore
    sta $d016
    lda #1                      ; lo schermo nascosto per R = 1
    sta e_rnext
    ; secondo schermo vuoto (il primo l'ha pulito fresh_screen)
    ldx #0
    lda #CH_BLANK
:   sta SCREEN + $400,x
    sta SCREEN + $500,x
    sta SCREEN + $600,x
    sta SCREEN + $6e8,x
    inx
    bne :-
    rts
.endproc

.proc credits_frame
    ; avanti: 9/8 di pixel ogni due frame, fino a CRED_END, poi E_HOLD frame fermo
    lda e_s+1
    cmp #>CRED_END
    bcc move
    bne hold
    lda e_s
    cmp #<CRED_END
    bcc move
hold:
    inc e_hold
    lda e_hold
    cmp #E_HOLD
    bcc regs
    jmp next_part
move:
    lda e_t
    and #1
    beq regs
    lda e_s
    clc
    adc #CRED_SPEED
    sta e_s
    bcc :+
    inc e_s+1
:   ; R = e_s / 64
    lda e_s+1
    sta e_c
    lda e_s
    asl a
    rol e_c
    asl a
    rol e_c
    lda e_c
    cmp e_R
    beq regs
    ; riga intera: lo schermo nascosto è pronto (o quasi: lo si finisce qui), si scambiano
:   lda e_rr
    cmp #25
    bcs :+
    jsr cred_row
    jmp :-
:   lda e_c
    sta e_R
    lda e_front
    eor #SCR_B
    sta e_front
    jsr cred_colors
    lda #0
    sta e_rr
    lda e_R
    clc
    adc #1
    sta e_rnext
regs:
    ; registri: schermo davanti, scorrimento fine (24 righe), ancora nel vblank
    lda #D018_A
    ldx e_front
    beq :+
    lda #D018_B
:   sta $d018
    lda e_s
    lsr a
    lsr a
    lsr a
    and #7
    eor #$17                    ; $10 | (7 - fine): testo, 24 righe, schermo acceso
    sta $d011
prep:
    ; lo schermo nascosto, CRED_ROWS righe
    ldx #CRED_ROWS
:   lda e_rr
    cmp #25
    bcs :+
    txa
    pha
    jsr cred_row
    pla
    tax
    dex
    bne :-
:   rts
.endproc

; Riga e_rr dello schermo nascosto per R = e_rnext; poi e_rr + 1.
.proc cred_row
    ldy e_rr
    inc e_rr
    lda row_lo,y
    sta ptr
    lda row_hi,y
    eor #SCR_B
    eor e_front                 ; (lo schermo nascosto: l'altro)
    sta ptr+1
    jsr line_of                 ; X = riga di testo (da 1) e bit 7, o Z = 1
    bne :+
    jmp blank
:   stx e_line
    ; vuota, poi il testo
    lda #CH_BLANK
    ldy #39
:   sta (ptr),y
    dey
    bpl :-
    txa
    and #$7f
    tax
    lda cred_col-1,x
    sta e_col
    lda cred_len-1,x
    sta e_n
    lda cred_lo-1,x
    sta ptr2
    lda cred_hi-1,x
    sta ptr2+1
    lda cred_style-1,x
    cmp #2
    beq big
    ldy #0
:   lda (ptr2),y
    sec
    sbc #32
    tax
    lda font_map,x
    sty e_c
    ldy e_col
    sta (ptr),y
    inc e_col
    ldy e_c
    iny
    cpy e_n
    bne :-
    rts
big:
    ; scala 2: la metà alta o (bit 7) la bassa
    ldy #0
:   sty e_c
    lda (ptr2),y
    sec
    sbc #32
    tax
    lda big_idx,x
    tax
    ldy e_col
    bit e_line
    bmi lower
    lda big_tl,x
    sta (ptr),y
    iny
    lda big_tr,x
    jmp put
lower:
    lda big_bl,x
    sta (ptr),y
    iny
    lda big_br,x
put:
    sta (ptr),y
    iny
    sty e_col
    ldy e_c
    iny
    cpy e_n
    bne :-
    rts
blank:
    lda #CH_BLANK
    ldy #39
:   sta (ptr),y
    dey
    bpl :-
    rts
.endproc

; Riga virtuale per la riga Y dello schermo con R = e_rnext: X = cred_row (0 vuota), Z = 1 se vuota.
.proc line_of
    tya
    clc
    adc e_rnext
    sec
    sbc #25
    bcc none                    ; prima del testo
    cmp #END_CRED_ROWS
    bcs none
    tax
    lda cred_rows,x
    tax
    rts
none:
    ldx #0
    rts
.endproc

; Colori delle righe con il testo nello schermo davanti (R = e_R), dall'alto: il raster è nel
; vblank e ogni riga si scrive prima che il raster ci arrivi.
.proc cred_colors
    lda e_R
    sta e_rnext                 ; (line_of guarda e_rnext)
    ldy #0
row:
    sty e_row
    jsr line_of
    beq next
    txa
    and #$7f
    tax
    lda cred_len-1,x
    ldy cred_style-1,x
    beq :+
    cpy #2
    bne :+
    asl a                       ; scala 2: il doppio delle celle
:   sta v_n
    lda #COL_WHITE
    cpy #0
    beq :+
    lda egg_yel
:   pha
    ldy cred_col-1,x
    ldx e_row
    pla
    jsr color_span_raw
next:
    ldy e_row
    iny
    cpy #25
    bne row
    rts
.endproc


; Stato dei fuochi a zero, razzi pronti.
.proc fw_init
    lda #0
    ldx #fw_vars_end - fw_vars - 1
:   sta fw_vars,x
    dex
    bpl :-
    sta sh_enable
    lda #%111                   ; razzi: sprite 0-2 multicolore, non espansi, davanti
    sta sh_mc
    lda #0
    sta sh_yexp
    sta sh_xexp
    sta sh_msb
    sta $d01b
    ldx #2
:   lda #COL_WHITE
    sta sh_col,x
    lda #ROCKET_PTR
    sta sh_ptr,x
    sta SCREEN + $400 + $3f8,x  ; (il secondo schermo ha i suoi puntatori)
    dex
    bpl :-
    rts
.endproc

.proc fw_frame
    jsr rockets
    lda fw_phase
    bne :+
    ; fase 0: un passo nuovo, il cielo dello schermo nascosto vuoto, il fuoco 0
    jsr launch
    jsr sky_clear
    ldx #0
    jsr slot_step
    jmp next
:   cmp #1
    bne :+
    ldx #1
    jsr slot_step
    ldx #2
    jsr slot_step
    jmp next
:   ldx #3
    jsr slot_step
    lda fw_front                ; scambio: si vede lo schermo appena disegnato
    eor #SCR_B
    sta fw_front
    lda #$ff
    sta fw_phase
next:
    inc fw_phase
    rts
.endproc

; Cielo vuoto nello schermo nascosto: righe 0-17, una colonna alla volta.
.proc sky_clear
    lda #CH_BLANK
    ldx #39
    ldy fw_front
    bne clear_a
:   .repeat ::SKY_ROWS, r
    sta SCREEN + $400 + r * 40,x
    .endrepeat
    dex
    bpl :-
    rts
clear_a:
:   .repeat ::SKY_ROWS, r
    sta SCREEN + r * 40,x
    .endrepeat
    dex
    bpl :-
    rts
.endproc

; Razzi del passo: quelli dello spettacolo che partono ora, ognuno nel suo sprite.
.proc launch
    lda fw_step
    inc fw_step
    ldy fw_next
    cmp fs_step,y
    bne done
    inc fw_next
    ; sprite libero (0-2)
    ldx #2
:   lda rk_on,x
    beq free
    dex
    bpl :-
done:
    rts
free:
    tya
    sta rk_fw,x
    lda #FW_RISE
    sta rk_on,x
    lda #0
    sta rk_yl,x
    lda #200
    sta rk_yh,x
    lda fs_v0l,y
    sta rk_vl,x
    lda fs_v0h,y
    sta rk_vh,x
    ; x: centro della cella della griglia, la testa nel suo pixel
    lda fs_gx,y
    sta e_c
    lda #0
    asl e_c
    rol a
    asl e_c
    rol a
    sta ptr
    lda e_c
    clc
    adc #<(SPR_X0 + 2 - RK_HEAD_X)
    sta sh_x,x
    lda ptr
    adc #0
    beq :+
    lda bit_of,x
    ora sh_msb
    bne :++
:   lda bit_of,x
    eor #$ff
    and sh_msb
:   sta sh_msb
    lda bit_of,x
    ora sh_enable
    sta sh_enable
    rts
.endproc

; Razzi: salgono rallentando (y -= v, v -= accelerazione); alla fine lo scoppio.
.proc rockets
    ldx #2
loop:
    lda rk_on,x
    beq next
    ldy rk_fw,x
    sec
    lda rk_yl,x
    sbc rk_vl,x
    sta rk_yl,x
    lda rk_yh,x
    sbc rk_vh,x
    sta rk_yh,x
    sec
    lda rk_vl,x
    sbc fs_acc,y
    sta rk_vl,x
    bcs :+
    dec rk_vh,x
:   lda rk_yh,x
    clc
    adc #SPR_Y0 - 1
    sta sh_y,x
    dec rk_on,x
    bne next
    lda bit_of,x                ; scoppio: lo sprite si spegne
    eor #$ff
    and sh_enable
    sta sh_enable
    stx e_c
    jsr burst
    ldx e_c
next:
    dex
    bpl loop
    rts
.endproc

; Scoppio del fuoco Y dello spettacolo: un posto libero (o quello più vicino alla fine) e le sue
; scintille dal centro.
.proc burst
    ; posto: il primo spento, se no quello con meno vita
    ldx #FW_SLOTS - 1
    lda #$ff
    sta fq
:   lda sl_on,x
    beq found
    lda sl_thr,x
    cmp fq
    bcs :+
    sta fq
    stx fi
:   dex
    bpl :--
    ldx fi
found:
    lda fs_kind,y
    sta sl_kind,x
    lda #1
    sta sl_on,x
    lda #0
    sta sl_age,x
    sta sl_cnt,x
    sta sl_t3,x
    lda #10
    sta sl_thr,x
    lda fs_gx,y
    sta fg
    lda fs_gy,y
    sta fdr
    ; scintille: posto * FW_MAX, dalle tabelle del tipo
    lda fs_kind,y
    pha
    lda slot_base,x
    tax
    pla
    tay
    lda k_n,y
    sta ftr
    lda k_off,y
    tay
:   lda fg
    sta p_xh,x
    lda fdr
    sta p_yh,x
    lda #$80
    sta p_xl,x
    sta p_yl,x
    lda fw_vx,y
    sta p_vx,x
    lda fw_vy,y
    sta p_vy,x
    lda fw_vc,y
    sta p_c,x
    inx
    iny
    dec ftr
    bne :-
    rts
.endproc

; Un passo del fuoco X: età, vita (le scintille si diradano), poi le scintille.
.proc slot_step
    lda sl_on,x
    bne :+
    rts
:   stx fslot
    inc sl_age,x
    ldy sl_kind,x
    ; (t * 3) mod 10
    lda sl_t3,x
    clc
    adc #3
    cmp #10
    bcc :+
    sbc #10
:   sta sl_t3,x
    sta ft3
    ; soglia: 10 - 10 * età / vita (Bresenham)
    lda sl_cnt,x
    clc
    adc #10
:   cmp k_life,y
    bcc :+
    sbc k_life,y
    dec sl_thr,x
    jmp :-
:   sta sl_cnt,x
    lda sl_thr,x
    bne :+
    sta sl_on,x                 ; finito
    rts
:   sta fthr
    lda sl_age,x
    sta fage
    ; blocco (crepitio: le scintille si fermano, resta la gravità) e divisione (croce)
    cmp k_freeze,y
    bne :+
    jsr freeze
:   lda fage
    cmp k_split,y
    bne :+
    jsr split
:   lda k_grav,y
    sta fg
    lda k_drag,y
    sta fdr
    lda fage                    ; attrito a passi alterni, il doppio
    lsr a
    bcs :+
    lda #0
    sta fdr
:   lda fdr
    beq :+
    dec fdr
:   lda k_trail,y
    sta ftr
    lda k_flick,y
    sta fflk
    lda k_n,y
    sta fn
    lda fage                    ; crepitio: età mod 3 per la prima scintilla
:   cmp #3
    bcc :+
    sbc #3
    bcs :-
:   sta fm3
    lda slot_base,x
    tax
    lda #0
    sta fi
loop:
    jsr spark
    inx
    inc fi
    dec fn
    bne loop
    ldx fslot
    rts
.endproc

; Le scintille ferme (vx = vy = 0).
.proc freeze
    lda slot_base,x
    tax
    lda k_n,y
    sta fn
    lda #0
:   sta p_vx,x
    sta p_vy,x
    inx
    dec fn
    bne :-
    ldx fslot
    rts
.endproc

; Divisione della croce: velocità e colori dalla seconda tabella.
.proc split
    lda slot_base,x
    tax
    lda k_n,y
    sta fn
    tya
    pha
    ldy #FW_SPLIT_OFF
:   lda fw_vx,y
    sta p_vx,x
    lda fw_vy,y
    sta p_vy,x
    lda fw_vc,y
    sta p_c,x
    inx
    iny
    dec fn
    bne :-
    pla
    tay
    ldx fslot
    rts
.endproc

; Una scintilla (X): movimento, gravità, attrito, poi il punto (e la scia) se si vede.
.proc spark
    ; x += vx, y += vy (8.8 sulla griglia, v con segno)
    lda p_vx,x
    bmi :+
    clc
    adc p_xl,x
    sta p_xl,x
    bcc :++
    inc p_xh,x
    bcs :++                     ; (sempre)
:   clc
    adc p_xl,x
    sta p_xl,x
    bcs :+
    dec p_xh,x
:   lda p_vy,x
    bmi :+
    clc
    adc p_yl,x
    sta p_yl,x
    bcc :++
    inc p_yh,x
    bcs :++
:   clc
    adc p_yl,x
    sta p_yl,x
    bcs :+
    dec p_yh,x
:   ; gravità, senza traboccare
    lda p_vy,x
    clc
    adc fg
    bvc :+
    lda #$7f
:   sta p_vy,x
    ; attrito: v -= v >> fdr (a passi alterni)
    ldy fdr
    beq vis
    lda p_vx,x
:   cmp #$80
    ror a
    dey
    bne :-
    sta fq
    lda p_vx,x
    sec
    sbc fq
    sta p_vx,x
    ldy fdr
    lda p_vy,x
:   cmp #$80
    ror a
    dey
    bne :-
    sta fq
    lda p_vy,x
    sec
    sbc fq
    sta p_vy,x
vis:
    ; si vede? crepitio: (età + i) mod 3 <> 0, bianco e giallo a turno; gli altri: la fase
    ; (i * 7 + età * 3) mod 10 sotto la soglia
    lda fflk
    beq thin
    ldy fm3                     ; (età + i) mod 3 di questa, poi quello della prossima
    iny
    cpy #3
    bcc :+
    ldy #0
:   sty fm3
    cpy #1                      ; la prossima a 1: questa a 0, spenta
    jeq out
    lda fage
    clc
    adc fi
    sta fq
    and #1
    beq :+
    lda #$d0 - $c0              ; giallo
:   eor #$c0                    ; bianco ($C0) o giallo ($D0)
    sta fc
    lda p_xh,x
    ldy p_yh,x
    jmp fw_plot
thin:
    ldy fi
    lda phase7,y
    clc
    adc ft3
    cmp #10
    bcc :+
    sbc #10
:   sta fph
    cmp fthr
    jcs out
    lda p_c,x
    sta fc
    lda p_xh,x
    ldy p_yh,x
    jsr fw_plot
trail:
    ; scia: punti indietro di due passi alla volta, con la soglia dimezzata a ogni punto
    lda ftr
    jeq out
    sta fk
    lda fthr
    sta fthr2
    lda p_xl,x
    sta fxl
    lda p_xh,x
    sta fxh
    lda p_yl,x
    sta fyl
    lda p_yh,x
    sta fyh
    lda p_c,x
    sta fc
tloop:
    lsr fthr2
    ; indietro di 2 v
    lda p_vx,x
    asl a
    sta fq
    lda #0
    sbc #0                      ; (C dal bit 7 di v: 0 o $FF)
    eor #$ff
    sta fq2
    sec
    lda fxl
    sbc fq
    sta fxl
    lda fxh
    sbc fq2
    sta fxh
    lda p_vy,x
    asl a
    sta fq
    lda #0
    sbc #0
    eor #$ff
    sta fq2
    sec
    lda fyl
    sbc fq
    sta fyl
    lda fyh
    sbc fq2
    sta fyh
    lda fph
    cmp fthr2
    bcs :+
    lda fxh
    ldy fyh
    jsr fw_plot
:   dec fk
    bne tloop
out:
    rts
.endproc

; Punto (2x2 pixel) nella cella della griglia A (x, 0-79), Y (y, 0-35) dello schermo nascosto,
; colore fc ($C0, $D0, $E0): il carattere della cella prende il quadrante e il colore.
.proc fw_plot
    cmp #80
    bcs out
    lsr a
    sta fcol
    lda #0
    rol a                       ; x dispari: bit 0
    sta fqd
    tya
    cmp #SKY_ROWS * 2
    bcs out
    lsr a
    tay
    bcc :+
    lda fqd
    ora #2                      ; y dispari: bit 1
    sta fqd
:   lda row_lo,y
    sta fp
    lda row_hi,y
    eor fw_front
    eor #SCR_B                  ; (lo schermo nascosto)
    sta fp+1
    ldy fqd
    lda qbit,y
    ora fc
    sta fqd
    ldy fcol
    lda (fp),y
    and #$0f
    ora fqd
    sta (fp),y
out:
    rts
.endproc

qbit: .byte 1, 2, 4, 8
phase7:
    .repeat FW_MAX, i
    .byte (i * 7) .mod 10
    .endrepeat
slot_base:
    .repeat FW_SLOTS, i
    .byte i * FW_MAX
    .endrepeat
k_n:      .byte FW_K_N
k_life:   .byte FW_K_LIFE
k_grav:   .byte FW_K_GRAV
k_drag:   .byte FW_K_DRAG
k_trail:  .byte FW_K_TRAIL
k_freeze: .byte FW_K_FREEZE
k_split:  .byte FW_K_SPLIT
k_flick:  .byte FW_K_FLICK
k_off:    .byte FW_K_OFF
fw_vx:    .byte FW_VX
fw_vy:    .byte FW_VY
fw_vc:    .byte FW_VC
fs_step:  .byte FW_S_STEP
fs_kind:  .byte FW_S_KIND
fs_gx:    .byte FW_S_GX
fs_gy:    .byte FW_S_GY
fs_v0l:   .lobytes FW_S_V0
fs_v0h:   .hibytes FW_S_V0
fs_acc:   .byte FW_S_ACC

; stato (fw_init lo azzera)
fw_vars:
fw_phase: .res 1                ; frame del passo (0-2)
fw_step:  .res 1                ; passi dall'inizio
fw_next:  .res 1                ; prossimo fuoco dello spettacolo
fw_front: .res 1                ; schermo davanti: 0 o SCR_B
rk_on:    .res 3                ; razzi: frame rimasti (0 spento)
rk_fw:    .res 3
rk_yl:    .res 3
rk_yh:    .res 3
rk_vl:    .res 3
rk_vh:    .res 3
sl_on:    .res FW_SLOTS
sl_kind:  .res FW_SLOTS
sl_age:   .res FW_SLOTS
sl_thr:   .res FW_SLOTS
sl_cnt:   .res FW_SLOTS
sl_t3:    .res FW_SLOTS
fw_vars_end:
.assert fw_vars_end - fw_vars <= 128, error, "fuochi: stato oltre 128 byte"

; variabili veloci dei fuochi: nella pagina zero, al posto dei prodotti (qui non servono)
fp    = m_p                     ; puntatore della cella
fcol  = m_p + 2
fqd   = m_p + 3
fc    = m_p + 4                 ; colore della scintilla
fi    = m_p + 5                 ; indice della scintilla nel fuoco
fthr  = m_p + 6                 ; soglia (0-10)
ft3   = m_p + 7                 ; (età * 3) mod 10
fg    = m_p + 8                 ; gravità
fdr   = m_p + 9                 ; attrito: shift (0 niente)
ftr   = m_p + 10                ; punti della scia
fxl   = m_a
fxh   = m_a + 1
fyl   = m_a + 2
fyh   = m_a + 3
fq    = sq1_lo
fq2   = sq1_lo + 1
fk    = sq1_hi
fthr2 = sq1_hi + 1
fph   = sq2_lo
fage  = sq2_lo + 1
fflk  = sq2_hi
fn    = sq2_hi + 1
fm3   = m_b                     ; crepitio: (età + i) mod 3
fslot = fw_slot
.segment "ENDE"
fw_slot: .res 1

.segment "CODE"
