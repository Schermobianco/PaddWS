; Musiche ed effetti con il SID: traduzione in 6502 del player del core MiSTer (mister/rtl/pong_sid.v).
;
; Quattro canali leggono le tracce dalla stessa ROM (tools/gen_sid_music.py, gen/sid_music.bin con
; le frequenze per il clock PAL) e scrivono i registri del SID nello stesso ordine del player
; Verilog: i canali 0-2 suonano la canzone sulle voci 1-3, il canale 3 gli effetti sulla voce 3,
; che intanto la canzone continua a contare senza suonare. Verificato scrittura per scrittura
; contro il player Verilog (paddws-c64 sid).
;
; Uso: sid_song (A = canzone, 0 = silenzio) quando si vuole, sid_fx (A = eventi del tick), una
; volta per frame sid_tempo e sid_tick, in quest'ordine, e sid_more quando il frame ha tempo.
;
; Tempo della canzone, come il SID Rust (rust/sid/src/engine.rs e player.rs), solo per i canali
; 0-2; gli effetti restano a 50 Hz e alla loro altezza:
; - match point (sid_tempo, bit 0): 62,5 Hz, cioè 5 passi ogni 4 frame. Il passo in più è un
;   credito (sid_extra) che sid_more spende in un frame che ha ancora tempo: le scritture della
;   canzone sono le stesse, in sequenza;
; - bullet time (bit 7): un passo su due e le frequenze dimezzate (un'ottava sotto); al cambio, in
;   entrata e in uscita, al passo dopo si riscrivono subito le frequenze delle note in corso.
; Le due regole si sommano: al match point nel bullet time un passo su due di quelli da 62,5 Hz.
;
; Filtro (formato in tools/gen_sid_music.py), come il player Verilog: il taglio a 16 bit (sid_fc,
; 5 bit di frazione) dal comando $A0+l, h e la sua scivolata (sid_sw, comando $B0 e 16 bit) a ogni
; passo della canzone servito, prima dei canali, senza saturazione; $D417 e $D418 dagli strumenti
; nel filtro (byte 6 e 7), scritti con il taglio solo quando cambiano rispetto alla copia
; (sid_rf, sid_vm). La voce di CHALLENGE scrive $D417 = 0: finché ha il SID la copia di $D417 torna
; a 0 (sid_tick), così la prima nota nel filtro dopo la voce riscrive tutto.
;
; Le canzoni della ROM del C64 sono le prime SID_SONGS; la SID_SONG_THEME (in CHALLENGE contro la CPU) legge le tracce a THEME_BASE, dove le
; mette il file voce dell'avversario: sono quelle delle canzoni 7-13 del MiSTer, una per tipo. La
; SID_SONG_ENDING (il finale di CHALLENGE, ENDING del MiSTer) le legge nel finale (ending.s).
; SID_SONG_EGG è la stessa canzone letta dalla cartuccia (egg_stage): l'easter egg delle iniziali
; (egg_check, challenge.s) la mette al posto di quella del titolo, quando la bitmap dell'attract
; copre le tracce del finale.

SID = $d400

.segment "RODATA"
sid_rom:    .incbin "sid_music.bin"
song_start: .word 0, 0, 0                   ; canzone 0: silenzio
            .repeat 3 * SID_SONGS, i
            .word sid_rom + .mid(i * 2, 1, {SID_SONG_STARTS})
            .endrepeat
            ; canzone SID_SONG_THEME: il tema dell'avversario di CHALLENGE, copiato dal file voce
            ; (voice.s), una traccia per pagina
            .word THEME_BASE, THEME_BASE + $100, THEME_BASE + $200
            ; canzone SID_SONG_ENDING: il finale di CHALLENGE, con le tracce nel finale (ending.s)
            .word end_bass, end_lead, end_arp
            ; canzone SID_SONG_EGG: le stesse tracce dove stanno nella cartuccia, nella finestra
            ; della ROML (egg_stage)
            .word EGG_TRACK + end_bass - ENDC_RUN + EPG_C * 256
            .word EGG_TRACK + end_lead - ENDC_RUN + EPG_C * 256
            .word EGG_TRACK + end_arp - ENDB_RUN + EPG_B * 256
.assert SID_SONG_THEME = SID_SONGS + 1 .and SID_SONG_ENDING = SID_SONG_THEME + 1, error, "il tema e il finale devono seguire le canzoni"
SID_SONG_EGG = SID_SONG_ENDING + 1
EGG_TRACK    = $8000            ; ROML del banco END_BANK: il file del finale dalla prima pagina
ENDB_RUN     = $EC00            ; dove girano le aree del finale con le tracce (paddws.cfg)
ENDC_RUN     = $FB00
.assert end_arp >= ENDB_RUN .and end_arp < ENDB_RUN + $400 .and end_bass >= ENDC_RUN .and end_lead < ENDC_RUN + $400, error, "tracce del finale fuori da ENDB e ENDC"
.assert (EPG_C + 4) * 256 <= $2000, error, "tracce del finale oltre la ROML del primo banco del finale"
.assert sid_rom >= EGG_TRACK + $2000 .and sid_track_move >= EGG_TRACK + $2000 .and sid_track_special >= EGG_TRACK + $2000 .and THEME_BASE >= EGG_TRACK + $2000 .and end_arp >= EGG_TRACK + $2000 .and end_bass >= EGG_TRACK + $2000, error, "tracce sotto $A000: read_cmd le prenderebbe per quelle di SID_SONG_EGG"
fx_start:   .word 0
            .repeat SID_EFFECTS, i
            .word sid_rom + .mid(i * 2, 1, {SID_FX_STARTS})
            .endrepeat
            ; effetti 6 e 7 (MOVE e SPECIAL, come SID_FX_MOVE e SID_FX_SPECIAL del MiSTer): mosse
            ; speciali di NEXT, con le tracce in supers.s; li fa partire sm_hud (sid_fx::start)
            .word sid_track_move, sid_track_special
vbase:      .byte 0, 7, 14, 14              ; primo registro della voce di ogni canale
; arpeggi: semitoni per i passi 0-2 (modo 0 spento, 1 minore, 2 maggiore, 3 ottava)
arp_table:  .byte 0, 0, 0,  0, 3, 7,  0, 4, 7,  0, 12, 12

.segment "ZEROPAGE"
sp:      .res 2                 ; lettura della traccia

.segment "BSS"
ch_ptr_lo:   .res 4
ch_ptr_hi:   .res 4
ch_start_lo: .res 4
ch_start_hi: .res 4
ch_cnt:      .res 4
ch_note:     .res 4
ch_ins:      .res 4
ch_arp:      .res 4
ch_slide:    .res 4
ch_freq_lo:  .res 4
ch_freq_hi:  .res 4
ch_wave:     .res 4             ; forma d'onda dello strumento (senza gate)
ch_rel:      .res 4             ; frame di rilascio prima della fine della nota
ch_active:   .res 4
sid_phase:   .res 1             ; passo degli arpeggi (0-2)
sid_song_n:  .res 1             ; canzone richiesta
sid_new:     .res 1             ; canzone cambiata: ricomincia al prossimo frame
sid_cmd:     .res 1
sid_pw_lo:   .res 1
sid_fast:    .res 1             ; match point: 5 passi della canzone ogni 4 frame
sid_quarter: .res 1             ; frame del match point (ogni 4 un passo in più)
sid_extra:   .res 1             ; passi della canzone in più ancora da fare (sid_more)
sid_slow:    .res 1             ; bullet time ($80): un passo su due, frequenze dimezzate
sid_skip:    .res 1             ; il prossimo passo della canzone si salta (con sid_slow)
sid_retune:  .res 1             ; frequenze delle note in corso da riscrivere al prossimo passo
sid_fc:      .res 2             ; filtro: taglio a 16 bit (il registro a 11 bit è >> 5)
sid_sw:      .res 2             ; scivolata del taglio per passo della canzone (0 = ferma)
sid_rf:      .res 1             ; copia di $D417 (0: nessuna voce nel filtro)
sid_vm:      .res 1             ; copia di $D418, valida con sid_rf diverso da 0

.segment "CODE"

; Registri del SID a zero, player fermo.
.segment "BOOTCODE"           ; solo all'avvio (unpack.s)
.proc sid_init
    lda #0
    ldx #$18
:   sta SID,x
    dex
    bpl :-
    ldx #3
:   sta ch_active,x
    sta ch_cnt,x
    sta ch_wave,x
    dex
    bpl :-
    sta sid_phase
    sta sid_song_n
    ldx #5
:   sta sid_fc,x                ; taglio, scivolata e copie del filtro
    dex
    bpl :-
    lda #1
    sta sid_new
    rts
.endproc
.segment "CODE"

; Canzone A (0 = silenzio): se cambia ricomincia da capo al prossimo frame. Una voce di CHALLENGE
; ancora in corso (GO! appena dopo il via, READY? se entra uno sfidante) si ferma subito: la scena
; cambia e la musica non aspetta.
.proc sid_song
    bit $fffb                   ; il vettore dell'NMI è nel player della voce (voice.s)?
    bpl :+
    jsr VOICE_HUSH
:   cmp sid_song_n
    beq :+
    sta sid_song_n
    lda #1
    sta sid_new
:   rts
.endproc

; Effetto degli eventi A (bit 0 muro, 1 colpo, 2 boost, 3 punto, 4 gettone): parte subito sul
; canale 3, con la priorità gettone > punto > boost > colpo > muro.
.proc sid_fx
    bit $fffb                   ; la voce di CHALLENGE ha il SID (voice.s): niente effetti
    bmi done
    and #$1f
    bne :+
done:
    rts
:   ldx #SID_FX_COIN
    cmp #$10
    bcs start
    dex                         ; SCORE
    cmp #$08
    bcs start
    dex                         ; BOOST
    cmp #$04
    bcs start
    dex                         ; HIT
    cmp #$02
    bcs start
    dex                         ; WALL
start:
    txa
    asl a
    tax
    lda fx_start,x
    sta ch_ptr_lo+3
    sta ch_start_lo+3
    lda fx_start+1,x
    sta ch_ptr_hi+3
    sta ch_start_hi+3
    lda #0
    sta ch_cnt+3
    sta ch_ins+3
    sta ch_arp+3
    sta ch_slide+3
    lda #1
    sta ch_active+3
    ; prima si chiude il gate della voce 3
    lda #0
    sta SID + $12
    ldx #3
    jmp channel
.endproc

; Tempo della canzone per i prossimi passi: A bit 0 match point, bit 7 bullet time.
.proc sid_tempo
    tax
    and #1
    sta sid_fast
    bne :+
    sta sid_extra               ; (A = 0) fuori dal match point niente passi in sospeso
    sta sid_quarter
:   txa
    and #$80
    cmp sid_slow
    beq :+
    sta sid_slow
    lda #0
    sta sid_skip
    lda #1
    sta sid_retune
:   rts
.endproc

; Un frame del player (50 Hz): un passo della canzone e uno degli effetti; al match point ogni 4
; frame un passo della canzone in più da fare (sid_more).
.proc sid_tick
    bit $fffb                   ; la voce di CHALLENGE ha il SID: il player aspetta e la copia di
    bmi hush                    ; $D417 torna a 0, come lo mette la voce
    jsr song_step
    lda sid_fast
    beq :+
    inc sid_quarter
    lda sid_quarter
    and #3
    bne :+
    inc sid_extra
:   ldx #3                      ; effetti
    jmp channel
hush:
    lda #0
    sta sid_rf
    rts
.endproc

; Il passo della canzone in più del match point, se ce n'è uno in sospeso.
.proc sid_more
    lda sid_extra
    beq :+
    bit $fffb
    bmi :+
    dec sid_extra
    jmp song_step
:   rts
.endproc

; Un passo della canzone (canali 0-2), come Player::tick senza gli effetti.
.proc song_step
    ldx sid_phase
    inx
    cpx #3
    bcc :+
    ldx #0
:   stx sid_phase
    lda sid_new
    sta m_t                     ; (canzone nuova: niente da riscrivere)
    beq retune
    ; canzone nuova (o silenzio): i canali 0-2 ripartono
    lda #0
    sta sid_new
    lda sid_song_n
    asl a
    adc sid_song_n              ; canzone * 3
    asl a                       ; * 2 byte
    tay
    ldx #0
:   lda song_start,y
    sta ch_ptr_lo,x
    sta ch_start_lo,x
    lda song_start+1,y
    sta ch_ptr_hi,x
    sta ch_start_hi,x
    lda #0
    sta ch_cnt,x
    sta ch_ins,x
    sta ch_arp,x
    sta ch_slide,x
    lda sid_song_n
    beq :+
    lda #1
:   sta ch_active,x
    iny
    iny
    inx
    cpx #3
    bne :--
    ; volume al massimo, senza filtro: modo spento, nessuna voce nel filtro, la scivolata del
    ; taglio ferma (il taglio resta)
    lda #$0f
    sta SID + $18
    ldx #0
    stx SID + $17
    stx sid_rf
    stx sid_sw
    stx sid_sw+1
retune:
    ; tempo appena cambiato (bullet time): le note in corso cambiano ottava subito
    lda sid_retune
    beq skip
    lda #0
    sta sid_retune
    lda m_t
    bne skip
    ldx #0
:   lda ch_active,x
    beq :+
    jsr write_freq
:   inx
    cpx #3
    bne :--
skip:
    ; nel bullet time la canzone avanza un passo su due
    lda sid_skip
    and sid_slow
    sta sid_cmd                 ; (bit 7: passo saltato)
    lda sid_skip
    eor #$80
    sta sid_skip
    ; silenzio: si chiude il gate delle voci della canzone, altrimenti l'ultima nota resta tenuta
    ; (la voce 3 no se suona un effetto, come in wr)
    lda m_t
    beq play
    lda sid_song_n
    bne play
    ldx #0
:   ldy #4
    lda ch_wave,x
    jsr wr
    inx
    cpx #3
    bne :-
play:
    bit sid_cmd
    bmi done
    ; la scivolata del taglio, prima dei canali; il taglio si scrive sempre
    lda sid_sw
    ora sid_sw+1
    beq chans
    clc
    lda sid_fc
    adc sid_sw
    sta sid_fc
    lda sid_fc+1
    adc sid_sw+1
    sta sid_fc+1
    jsr write_cut
chans:
    ldx #0
:   stx sid_cmd
    jsr channel
    ldx sid_cmd
    inx
    cpx #3
    bne :-
done:
    rts
.endproc

; Scrive A nel registro Y della voce del canale X; la canzone sulla voce 3 tace mentre suona un
; effetto. Cambia Y.
.proc wr
    cpx #2
    bne write
    pha
    lda ch_active+3
    beq :+
    pla
    rts
:   pla
write:
    pha
    tya
    clc
    adc vbase,x
    tay
    pla
    sta SID,y
    rts
.endproc

; Un passo del canale X.
.proc channel
    lda ch_active,x
    bne :+
    rts
:   lda ch_cnt,x
    cmp #2
    bcs running
    ; nota finita: si legge il comando dopo
    lda #0
    sta ch_cnt,x
    jmp read_cmd
running:
    sec
    sbc #1
    sta ch_cnt,x
    ; rilascio qualche frame prima della fine: la nota dopo riparte con l'attacco
    cmp ch_rel,x
    bne run
    lda ch_wave,x
    ldy #4
    jsr wr
run:
    lda ch_arp,x
    beq slide
    ; arpeggio: frequenza della nota più i semitoni del passo
    asl a
    adc ch_arp,x                ; modo * 3
    adc sid_phase
    tay
    lda arp_table,y
    clc
    adc ch_note,x
    and #$7f
    asl a
    tay
    jmp set_freq
slide:
    lda ch_slide,x
    bne :+
    rts
:   clc
    adc ch_freq_lo,x
    sta ch_freq_lo,x
    lda ch_slide,x
    and #$80
    beq :+
    lda #$ff
:   adc ch_freq_hi,x
    sta ch_freq_hi,x
    jmp write_freq

; Y = indice nella tabella delle frequenze: frequenza del canale e registri, senza gate.
set_freq:
    lda sid_rom + SID_FREQ_BASE,y
    sta ch_freq_lo,x
    lda sid_rom + SID_FREQ_BASE + 1,y
    sta ch_freq_hi,x
    jmp write_freq

read_cmd:
    lda ch_ptr_lo,x
    sta sp
    lda ch_ptr_hi,x
    sta sp+1
    cmp #>EGG_TRACK + $20       ; traccia nella finestra della cartuccia (SID_SONG_EGG)? Le altre
    bcs :+                      ; stanno tutte da $A000 (sotto)
    jsr egg_stage
:   ldy #0
    lda (sp),y
    sta sid_cmd_byte
    cmp #$70
    bcc note_or_rest
    cmp #$80
    bcs :+
    and #15                     ; $7x: strumento (16, 8 byte ciascuno)
    sta ch_ins,x
    jmp next1
:   bne :+
    iny                         ; $80: scivolata, il valore dopo
    lda (sp),y
    sta ch_slide,x
    jmp next2
:   cmp #$a0
    bcs :+
    cmp #$90
    bcc stop
    and #3                      ; $9x: arpeggio
    sta ch_arp,x
    jmp next1
:   cmp #$b0
    beq sweep
    bcs :+
    asl a                       ; $A0+l: taglio, l i 3 bit bassi, poi gli 8 alti
    asl a
    asl a
    asl a
    asl a
    sta sid_fc
    iny
    lda (sp),y
    sta sid_fc+1
    jsr write_cut
    jmp next2
:   cmp #$fe
    bne stop
    lda ch_start_lo,x           ; $FE: da capo
    sta ch_ptr_lo,x
    lda ch_start_hi,x
    sta ch_ptr_hi,x
    jmp read_cmd
stop:
    ; fine della traccia: la voce tace
    lda #0
    sta ch_active,x
    ldy #4
    jmp wr
sweep:
    iny                         ; $B0: scivolata del taglio, 16 bit
    lda (sp),y
    sta sid_sw
    iny
    lda (sp),y
    sta sid_sw+1
    jsr advance
next2:
    jsr advance
next1:
    jsr advance
    jmp read_cmd

note_or_rest:
    iny
    lda (sp),y
    sta ch_cnt,x
    jsr advance
    jsr advance
    lda sid_cmd_byte
    cmp #$60
    bne note
    ; pausa: gate chiuso
    lda ch_wave,x
    ldy #4
    jmp wr
note:
    and #$7f
    sta ch_note,x
    ; strumento: forma d'onda, attacco/decadimento, sostegno/rilascio, impulso, rilascio
    lda ch_ins,x
    asl a
    asl a
    asl a
    adc #<(sid_rom + SID_INSTR_BASE)
    sta sp
    lda #>(sid_rom + SID_INSTR_BASE)
    adc #0
    sta sp+1
    ldy #0
    lda (sp),y
    sta ch_wave,x
    iny
    lda (sp),y
    ldy #5
    jsr wr
    ldy #2
    lda (sp),y
    ldy #6
    jsr wr
    ldy #3
    lda (sp),y
    sta sid_pw_lo
    ldy #4
    lda (sp),y
    ldy #3
    jsr wr
    lda sid_pw_lo
    ldy #2
    jsr wr
    ldy #5
    lda (sp),y
    sta ch_rel,x
    ; frequenza della nota, poi il gate: parte l'inviluppo
    lda ch_note,x
    asl a
    tay
    jsr set_freq
    lda ch_wave,x
    ora #1
    ldy #4
    jsr wr
    ; strumento nel filtro: se $D417 o $D418 cambiano, taglio, $D417 e $D418 (X non serve più)
    ldy #6
    lda (sp),y
    beq :+
    tax
    iny
    lda (sp),y
    cpx sid_rf
    bne filter
    cmp sid_vm
    beq :+
filter:
    stx sid_rf
    sta sid_vm
    jsr write_cut
    stx SID + $17
    lda sid_vm
    sta SID + $18
:   rts

; puntatore della traccia avanti di un byte
advance:
    inc ch_ptr_lo,x
    bne :+
    inc ch_ptr_hi,x
:   rts
.endproc

; Frequenza del canale X nei registri: byte basso e alto; nel bullet time (solo i canali della
; canzone) dimezzata, prima l'alto e poi il basso con il bit che scende dall'alto, come il player
; Verilog con gli effetti rallentati.
.proc write_freq
    cpx #3
    beq full
    bit sid_slow
    bpl full
    lda ch_freq_hi,x
    lsr a
    ldy #1
    jsr wr
    lda ch_freq_hi,x
    lsr a
    lda ch_freq_lo,x
    ror a
    ldy #0
    jmp wr
full:
    lda ch_freq_lo,x
    ldy #0
    jsr wr
    lda ch_freq_hi,x
    ldy #1
    jmp wr
.endproc

; Registri del taglio dal taglio a 16 bit: $D415 i 3 bit bassi (bit 5-7), $D416 gli 8 alti. Il
; filtro è di tutto il SID: non tace per la voce 3. Cambia A.
.proc write_cut
    lda sid_fc
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    sta SID + $15
    lda sid_fc+1
    sta SID + $16
    rts
.endproc

.segment "BSS"
sid_cmd_byte: .res 1

; Comando di una traccia di SID_SONG_EGG, che resta nella cartuccia (nella finestra $8000-$9FFF):
; i suoi byte (al più 3, Y = 0-2 in read_cmd) dalla ROML del banco END_BANK a egg_buf, e (sp) lì.
; Per un momento la cartuccia accesa (modo a 8K, $01 = $37), con gli interrupt spenti: gira nella
; pagina 2, che la cartuccia non copre. X resta.
.segment "LOWCODE"
.proc egg_stage
    sei
    lda #END_BANK
    sta EF_BANK
    lda #EF_8K
    sta EF_MODE
    lda #$37
    sta $01
    ldy #2
:   lda (sp),y
    sta egg_buf,y
    dey
    bpl :-
    lda #$35
    sta $01
    lda #EF_OFF
    sta EF_MODE
    cli
    lda #<egg_buf
    sta sp
    lda #>egg_buf
    sta sp+1
    rts
.endproc
.segment "CODE"
