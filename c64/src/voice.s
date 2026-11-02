; Voci di CHALLENGE dette dal SID con il trucco del registro del volume ($D418), come sul MiSTer
; (mister/rtl/pong_sid.v) e sul PC: il nome dell'avversario nella presentazione, "READY?" all'inizio
; del conto alla rovescia e "GO!" al via (al posto del suo bip).
;
; Un file per tipo di racchetta (un banco della cartuccia, src/ef.inc), con i campioni del
; nome (assets/sounds/voice, tools/gen_voices.py; copiati in c64/gen/voiceN.bin da
; tools/gen_c64_assets.py: 5000 Hz, 4 bit, due per byte, prima il nibble alto, 8 = silenzio) e il
; tema dell'avversario. Si assembla una volta per tipo: c64/build.ps1, con VOICE_KIND = codice del
; tipo. Il programma contiene solo il caricamento e le chiamate (voice.inc): VOICE_TICK a ogni
; frame della presentazione, VOICE_STOP quando finisce, VOICE_COUNT a ogni frame del conto alla
; rovescia e VOICE_HUSH quando cambia la musica; senza file sono degli RTS.
;
; READY e GO sono uguali per tutti: viaggiano solo nel file dell'avversario del primo livello
; (FIRST), che una scala carica sempre per primo, insieme al player. Quella parte resta finché la
; scala continua: da VOICE_RES a VOICE_END il player e READY, sopra le immagini degli effetti di
; NEXT ($E000-$E93F); gli NMI del player e GO il file li copia a VOICE_GO, dopo il tema. Gli altri
; file finiscono prima di VOICE_RES e dicono il nome con quel player, se c'è (VOICE_COUNT è il
; salto che il file del primo livello mette quando ha copiato tutto).
;
; Il player (say) prende il SID per la voce e poi lo rende da solo, con gli NMI del timer A del
; CIA2 e senza altre chiamate (il conto alla rovescia si può interrompere):
; - subito: nessuna voce nel filtro ($D417 = 0: il player del SID lo sa, sid_tick), volume a 8
;   (il silenzio dei campioni), le tre voci con il bit di test e l'impulso,
;   cioè un'uscita ferma al massimo: un DC costante che sale con l'attacco. Il volume moltiplica
;   tutta l'uscita del SID: sul 6581 c'è già il DC del suo mixer, sull'8580 quasi niente, e senza
;   queste voci là non si sentirebbe nulla (è la tecnica dei player di campioni per l'8580). Il
;   MiSTer ne usa due; qui tre, perché in VICE con l'8580 la voce con due resta sotto il jingle;
; - per ATTACK_FRAMES frame un NMI a frame aspetta l'attacco, poi un NMI ogni SAMPLE_CYCLES cicli
;   scrive un campione nel volume;
; - finiti i campioni, volume a 8 e gate chiusi: il DC scende con il rilascio, senza il colpo che
;   farebbe a volume pieno; dopo RELEASE_FRAMES frame (un NMI a frame) voci spente, volume a 15 e
;   il vettore dell'NMI di prima.
; Finché il vettore dell'NMI ($FFFA) punta qui, sid_tick e sid_fx del programma non scrivono nel
; SID (il loro NMI è sotto $8000: bit 7 del byte alto a zero, qui a uno): la musica aspetta, il bip
; del via non suona. Mentre la voce suona nessuno spegne l'I/O ($01 resta $35): il banco di prova
; lo controlla a ogni NMI.
;
; Cicli: NMI del nibble alto 49, del basso 53 (con l'interrupt), circa 5.100 per frame.
;
; Il file porta anche il tema dell'avversario per la partita (tools/gen_sid_music.py: basso e
; melodia in gen/themeK_0.bin e themeK_1.bin, senza indirizzi assoluti; la terza traccia è vuota,
; un solo $FF, perché la voce 3 resta agli effetti). Al primo frame della presentazione, leggero
; e sempre prima di VOICE_STOP, le copia a THEME_BASE, una per pagina (circa 4.500 cicli): da
; hud_reset in poi qui ci sono le immagini degli effetti, mentre $F800-$FF3F (bitmap dell'attract,
; dopo le tabelle dei quadrati) in partita serve solo alla voce. VOICE_STOP restituisce
; A = SID_SONG_THEME, la canzone del player (sid.s) che le suona. Il banco di prova (paddws-c64 ui)
; controlla le tre pagine contro i file del generatore.

.setcpu "6502"
.include "voice.inc"
.include "sid_music.inc"
.include "params.inc"

SID           = $d400
SAMPLE_CYCLES = 197             ; 985.248 Hz (PAL) / 5000
FRAME_CYCLES  = 63 * 312        ; un NMI a frame nelle attese
ATTACK_AT     = 21              ; frame della presentazione: il DC sale, il nome 0,5 s dopo il primo
ATTACK_FRAMES = 4               ; attacco 6 (68 ms) del DC prima dei campioni
RELEASE_FRAMES = 6              ; 120 ms: rilascio 4 (114 ms) del DC
GO_AT         = ATTACK_FRAMES + 1 ; frame rimasti del conto: i campioni di GO partono al via
COPY_AT       = 3               ; frame della presentazione della copia a VOICE_GO: dopo il disegno
                                ; dello schermo (prima non si esce: sfidante, salto)
FIRST         = VOICE_KIND = .mid(0, 1, {T_RUNG_KIND})   ; l'avversario del primo livello

; traccia v del tema (da src a src_end, da 1 a 255 byte) all'inizio della sua pagina
.macro copy_track src, src_end, v
    .local loop
    ldx #<(src_end - src)
loop:
    lda src - 1,x
    sta THEME_BASE + v * $100 - 1,x
    dex
    bne loop
.endmacro

.segment "LOADADDR"
    .addr VOICE_BASE

.segment "CODE"
file_start:
    jmp tick                    ; VOICE_TICK
    jmp stop                    ; VOICE_STOP

frames:   .byte 0               ; frame della presentazione ($FF: finita o fermata)
name:     .word samples, samples_end

.if FIRST

; ------------------------------------------------------------------------------------ a VOICE_GO

; Copiati a VOICE_GO (go_copy): gli NMI del player e GO, che lì restano come READY.
go_src:
.assert go_src = VOICE_GO_SRC, error, "VOICE_GO_SRC fuori posto (banco della vittoria, make_crt.py)"
.org VOICE_GO

; NMI: un campione nel volume, alternando nibble alto e basso (cambia solo il byte basso del
; vettore: i gestori sono nella stessa pagina). A si mette da parte nell'istruzione che lo
; rimette; il byte dei campioni (hi_src), quello del nibble basso (lo_byte) e la fine dei campioni
; (end_lo, end_hi) sono gli operandi.
nmi_hi:
    sta hi_save+1
    lda $dd0d
hi_src:
    lda $ffff
    sta lo_byte+1
    lsr a
    lsr a
    lsr a
    lsr a
    sta SID + $18
    lda #<nmi_lo
    sta $fffa
hi_save:
    lda #0
    rti

nmi_lo:
    sta lo_save+1
    lda $dd0d
lo_byte:
    lda #0
    and #$0f
    sta SID + $18
    inc hi_src+1
    bne :+
    inc hi_src+2
:   lda hi_src+1
end_lo:
    cmp #0
    bne lo_next
    lda hi_src+2
end_hi:
    cmp #0
    beq lo_finish
lo_next:
    lda #<nmi_hi
    sta $fffa
lo_save:
    lda #0
    rti
lo_finish:
    ; campioni finiti: volume a metà, gate chiusi, poi il rilascio (un NMI a frame)
    lda #8
    sta SID + $18
    lda #$48
    sta SID + $04
    sta SID + $0b
    sta SID + $12
    jsr set_frame
    lda #RELEASE_FRAMES
    sta wait
    inc phase
    lda #<nmi_wait
    sta $fffa
    bne lo_save                 ; (sempre)

; NMI delle attese: dopo l'attacco i campioni, dopo il rilascio il SID al programma. Un NMI che
; non viene dal timer (RESTORE) non conta.
nmi_wait:
    sta w_save+1
    lda $dd0d
    lsr a
    bcc w_save
    dec wait
    bne w_save
    lda phase
    bne w_end
    jsr set_sample
    lda #<nmi_hi
    sta $fffa
    bne w_save                  ; (sempre)
w_end:
    jsr cia_off
w_save:
    lda #0
    rti

.assert >nmi_hi = >nmi_wait && >nmi_lo = >nmi_wait, error, "gestori dell'NMI in pagine diverse"
.assert <nmi_hi <> 0 && <nmi_wait <> 0, error, "i salti sempre presi vogliono byte bassi non nulli"

; Timer A del CIA2 ricaricato e ripartito subito, continuo: un NMI a frame o a campione.
set_frame:
    lda #<(FRAME_CYCLES - 1)
    sta $dd04
    lda #>(FRAME_CYCLES - 1)
    bne set_hi                  ; (sempre)
set_sample:
    lda #<(SAMPLE_CYCLES - 1)
    sta $dd04
    lda #>(SAMPLE_CYCLES - 1)
set_hi:
    sta $dd05
    lda #$11
    sta $dd0e
    rts

wait:     .byte 0               ; NMI rimasti nell'attesa
phase:    .byte 0               ; attesa: 0 l'attacco, 1 il rilascio
old_nmi:  .word 0               ; vettore dell'NMI del programma
; dove say mette il descrittore: inizio e fine dei campioni, negli operandi
say_dst:  .byte <(hi_src+1), <(hi_src+2), <(end_lo+1), <(end_hi+1)
.assert >hi_src = >nmi_hi && >(end_hi+1) = >nmi_hi, error, "operandi del player in pagine diverse"

go:
    .incbin "go.bin"
go_end:
go_block_end:
.reloc
GO_PAGES = (go_block_end - VOICE_GO + 255) / 256
.assert VOICE_GO + GO_PAGES * 256 <= $FF40, error, "GO e il player oltre la bitmap (caratteri del BULLET)"
.assert THEME_BASE + $201 <= VOICE_GO, error, "VOICE_GO sopra il tema"

.endif

; ------------------------------------------------------------------------------------ presentazione

.proc tick
    ldx frames
    inx
    beq done                    ; $FF: finita
    stx frames
    cpx #1
    beq theme
.if ::FIRST
    cpx #COPY_AT
    beq go_copy
.endif
    cpx #ATTACK_AT
    bne done
    lda VOICE_COUNT             ; il player c'è (il file del primo livello è arrivato)?
    cmp #$4c                    ; JMP
    bne done
    ldx #<name
    ldy #>name
    jmp VOICE_SAY
done:
    rts
theme:
    copy_track theme_0, theme_0_end, 0
    copy_track theme_1, theme_1_end, 1
    lda #$ff                    ; terza traccia: solo la fine
    sta THEME_BASE + $200
    rts
.if ::FIRST
go_copy:
    ; NMI del player e GO al loro posto (pagine intere, circa 14.000 cicli in un frame leggero),
    ; poi il conto alla rovescia trova il player: VOICE_COUNT salta a cd
    ldx #0
:
    .repeat ::GO_PAGES, p
    lda go_src + p * $100,x
    sta VOICE_GO + p * $100,x
    .endrepeat
    inx
    bne :-
    lda #$4c
    sta VOICE_COUNT
    lda #<cd
    sta VOICE_COUNT+1
    lda #>cd
    sta VOICE_COUNT+2
    rts
.endif
.endproc

.proc stop
    lda #$ff
    sta frames
    bit $fffb                   ; il vettore dell'NMI è nel player (bit 7: vedi sopra)?
    bpl :+
    jsr VOICE_HUSH              ; voce ferma subito, il SID al programma
:   lda #SID_SONG_THEME         ; il tema, già a THEME_BASE
    rts
.endproc

; tema dell'avversario: basso e melodia (la terza traccia, vuota, la scrive tick)
theme_0:
    .incbin .sprintf("theme%d_0.bin", VOICE_KIND)
theme_0_end:
theme_1:
    .incbin .sprintf("theme%d_1.bin", VOICE_KIND)
theme_1_end:
.assert theme_0_end - theme_0 >= 1 && theme_0_end - theme_0 <= 255, error, "basso del tema vuoto o oltre 255 byte"
.assert theme_1_end - theme_1 >= 1 && theme_1_end - theme_1 <= 255, error, "melodia del tema vuota o oltre 255 byte"

samples:
    .incbin .sprintf("voice%d.bin", VOICE_KIND)
samples_end:

.if FIRST

; ------------------------------------------------------------------------------------ a VOICE_RES

    .res VOICE_RES - VOICE_BASE - (* - file_start), 0

; Voce ferma subito (VOICE_HUSH): A, X e Y restano.
.proc hush
    pha
    jsr cia_off
    pla
    rts
.endproc
.assert hush = VOICE_HUSH, error, "VOICE_HUSH fuori posto"

; Dice i campioni del descrittore a X:Y (inizio, fine; almeno 1 byte): il SID è della voce fino
; alla fine (vedi sopra). Con una voce già in corso non fa niente.
.proc say
    bit $fffb
    bmi done
    stx src+1
    sty src+2
    ldx #3
src:
    lda $ffff,x
    ldy say_dst,x
    sta VOICE_GO & $ff00,y
    dex
    bpl src
    lda #0
    sta phase
    lda #ATTACK_FRAMES
    sta wait
    ; il SID è della voce: il vettore dell'NMI all'attesa dell'attacco
    lda $fffa
    sta old_nmi
    lda $fffb
    sta old_nmi+1
    lda #<nmi_wait
    sta $fffa
    lda #>nmi_wait
    sta $fffb
    lda #0                      ; nessuna voce nel filtro del SID: il DC passa diretto
    sta SID + $17
    ldx #14                     ; voci 3, 2 e 1
:   lda #$48                    ; impulso e bit di test, gate chiuso
    sta SID + 4,x
    lda #$60                    ; attacco 6, decadimento 0
    sta SID + 5,x
    lda #$f4                    ; sostegno 15, rilascio 4
    sta SID + 6,x
    txa
    sec
    sbc #7
    tax
    bcs :-
    lda #8
    sta SID + $18
    lda #$49                    ; gate aperto: l'attacco parte dal fronte
    sta SID + $04
    sta SID + $0b
    sta SID + $12
    lda $dd0d                   ; nessuna richiesta vecchia
    jsr set_frame
    lda #$81                    ; NMI dal timer A
    sta $dd0d
done:
    rts
.endproc
.assert say = VOICE_SAY, error, "VOICE_SAY fuori posto"
.assert >nmi_hi = >VOICE_GO, error, "operandi del player fuori dalla pagina di VOICE_GO"

; Un frame del conto alla rovescia (VOICE_COUNT salta qui), A = frame rimasti: READY al primo, GO
; ATTACK_FRAMES frame prima del via, così i suoi campioni partono al via.
.proc cd
    ldy #>ready_desc
    ldx #<ready_desc
    cmp #COUNT_FRAMES
    beq say
    ldx #<go_desc
    cmp #GO_AT
    beq say
    rts
.endproc

ready_desc: .word ready, ready_end
go_desc:    .word go, go_end
.assert >ready_desc = >go_desc, error, "descrittori di READY e GO in pagine diverse"

; Timer A del CIA2 fermo, nessuna richiesta in sospeso; prosegue in give_back.
.proc cia_off
    lda #$7f
    sta $dd0d
    lda #0
    sta $dd0e
    lda $dd0d
.endproc

; Il SID torna al programma: voci spente, volume al massimo, il suo NMI.
.proc give_back
    lda #0
    sta SID + $04
    sta SID + $0b
    sta SID + $12
    lda #$0f
    sta SID + $18
    lda old_nmi
    sta $fffa
    lda old_nmi+1
    sta $fffb
    rts
.endproc

ready:
    .incbin "ready.bin"
ready_end:
.assert ready_end <= VOICE_END, error, "READY oltre le tabelle dei quadrati (VOICE_END)"

.else

.assert samples_end <= VOICE_RES, error, "file voce sopra la parte che resta (VOICE_RES)"

.endif

.assert * - VOICE_BASE <= VOICE_PAGES * 256, error, "file voce più lungo di VOICE_PAGES"
