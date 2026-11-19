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
;   scrive un campione nel volume, al VOLUME del menu come musica ed effetti: 8 + (campione - 8) *
;   livello / 15, arrotondato (VOL_TAB, fatta da say quando il livello cambia; al 100% i campioni
;   come sono). Con il VOLUME a 0 nessuna voce: niente DC dell'attacco, niente colpi;
; - finiti i campioni, volume a 8 e gate chiusi: il DC scende con il rilascio, senza il colpo che
;   farebbe a volume pieno; dopo RELEASE_FRAMES frame (un NMI a frame) voci spente, volume a 15 e
;   il vettore dell'NMI di prima.
; Finché il vettore dell'NMI ($FFFA) punta qui, sid_tick e sid_fx del programma non scrivono nel
; SID (il loro NMI è sotto $8000: bit 7 del byte alto a zero, qui a uno): la musica aspetta, il bip
; del via non suona. Mentre la voce suona nessuno spegne l'I/O ($01 resta $35): il banco di prova
; lo controlla a ogni NMI.
;
; Cicli: NMI del nibble alto 57, del basso 54 (con l'interrupt; VOL_TAB costa 8 cicli a NMI, la fine
; guardata solo nell'ultima pagina ne rende 9 al basso), circa 5.550 per frame (misurati in VICE: i
; primi frame di partita con GO finiscono almeno 500 cicli prima dell'interrupt dopo).
;
; Il file porta anche il tema dell'avversario per la partita (tools/gen_sid_music.py: basso e
; melodia in gen/themeK_0.bin e themeK_1.bin, senza indirizzi assoluti; la terza traccia è vuota,
; un solo $FF, perché la voce 3 resta agli effetti). Al primo frame della presentazione, leggero
; e sempre prima di VOICE_STOP, le copia a THEME_BASE, una per pagina (circa 4.500 cicli): da
; hud_reset in poi qui ci sono le immagini degli effetti, mentre $F800-$FF3F (bitmap dell'attract,
; dopo le tabelle dei quadrati) in partita serve solo alla voce. VOICE_STOP restituisce
; A = SID_SONG_THEME, la canzone del player (sid.s) che le suona. Il banco di prova (paddws-c64 ui)
; controlla le tre pagine contro i file del generatore.
;
; Il file di OMEGA (VOICE_KIND = OMEGA_KIND) non ha il tema: la sua musica, una sezione per forma,
; la copia dalla cartuccia chi lo carica (enter_intro, la partita), e VOICE_STOP dà OMEGA_SONG. Il
; suo nome è il più lungo: i campioni (voice7.bin) arrivano quasi a VOICE_RES.

.setcpu "6502"
.include "tv.inc"
.include "voice.inc"
.include "sid_music.inc"
.include "params.inc"

SID           = $d400
SAMPLE_CYCLES = (TV_CLOCK + 2500) / 5000 ; 197 PAL (985.248 Hz / 5000), 205 NTSC
FRAME_CYCLES  = TV_FRAME        ; un NMI a frame nelle attese (anche sull'NTSC il conto alla rovescia
                                ; va un frame alla volta: GO resta al via)
ATTACK_AT     = 21              ; frame della presentazione: il DC sale, il nome 0,5 s dopo il primo
ATTACK_FRAMES = 4               ; attacco 6 (68 ms) del DC prima dei campioni
RELEASE_FRAMES = 6              ; 120 ms: rilascio 4 (114 ms) del DC
GO_AT         = ATTACK_FRAMES + 1 ; frame rimasti del conto: i campioni di GO partono al via
COPY_AT       = 3               ; frame della presentazione della copia a VOICE_GO: dopo il disegno
                                ; dello schermo (prima non si esce: sfidante, salto)
FIRST         = VOICE_KIND = .mid(0, 1, {T_RUNG_KIND})   ; l'avversario del primo livello
OMEGA         = VOICE_KIND = OMEGA_KIND                 ; il file di OMEGA: senza tema

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
.assert frames = VOICE_FRAMES, error, "VOICE_FRAMES fuori posto"
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
    sta hi_vol+1                ; il campione al volume del menu (VOL_TAB)
hi_vol:
    lda VOL_TAB
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
    sta lo_vol+1
lo_vol:
    lda VOL_TAB
    sta SID + $18
    ; la fine si guarda solo nell'ultima pagina dei campioni (lo_page, dalla pagina nuova o da say):
    ; prima basta il passo, 9 cicli invece di 18, che pagano parte di VOL_TAB
    inc hi_src+1
lo_page:
    bne lo_next                 ; (nell'ultima pagina: bne lo_last)
    inc hi_src+2
    lda hi_src+2
end_hi:
    cmp #0
    bne lo_next
    lda #lo_last - (lo_page + 2)
    sta lo_page+1
lo_last:
    lda hi_src+1
end_lo:
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

; VOL_TAB per il livello A (1-15) del VOLUME del menu: floor(((n - 8) * A + 127) / 15), cioè
; 8 + round((n - 8) * A / 15), con quoziente e resto che crescono di A per passo (circa 600 cicli).
; A 15 i campioni restano quelli del file. Cambia X. (Qui, nella pagina che anche il banco della
; vittoria copia: sopra VOICE_RES + $C0 c'è READY, che la partita contro OMEGA e il finale coprono.)
; VOL_TAB pronta per il livello A: rifatta se il livello è cambiato o se un file voce caricato
; dalla cartuccia l'ha coperta (lì ci sono zeri: l'elemento del silenzio vale sempre 8).
vol_check:
    cmp vt_level
    bne vol_make
    ldx VOL_TAB + 8
    cpx #8
    bne vol_make
    rts
vol_make:
    sta vt_level
    asl a
    asl a
    asl a                       ; 8 * A (al più 120)
    eor #$7f                    ; resto per n = 0: 127 - 8 * A, almeno 7
    ldx #0
    stx vt_q
vm_loop:
:   cmp #15
    bcc :+
    sbc #15
    inc vt_q
    bcs :-                      ; (sempre)
:   pha
    lda vt_q
    sta VOL_TAB,x
    pla
    clc
    adc vt_level
    inx
    cpx #16
    bne vm_loop
    rts
vt_level: .byte $ff             ; livello di VOL_TAB ($FF: da fare; anche nel banco della vittoria)
vt_q:     .byte 0
.assert * <= VOICE_GO + 255, error, "player fuori dalla pagina degli NMI (anche nel banco della vittoria)"
LO_NEXT = lo_next - (lo_page + 2)  ; i due salti di lo_page
LO_LAST = lo_last - (lo_page + 2)
.assert <VOL_TAB = 0 .and VOL_TAB + 16 <= VOICE_RES, error, "VOL_TAB fuori posto"

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
.if !::OMEGA
    cpx #1
    beq theme
.endif
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
.if !::OMEGA
theme:
    copy_track theme_0, theme_0_end, 0
    copy_track theme_1, theme_1_end, 1
    lda #$ff                    ; terza traccia: solo la fine
    sta THEME_BASE + $200
    rts
.endif
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
.if ::OMEGA
:   lda #OMEGA_SONG             ; la sezione di OMEGA, a THEME_BASE dalla presentazione
.else
:   lda #SID_SONG_THEME         ; il tema, già a THEME_BASE
.endif
    rts
.endproc

.if !OMEGA
; tema dell'avversario: basso e melodia (la terza traccia, vuota, la scrive tick)
theme_0:
    .incbin .sprintf("theme%d_0.bin", VOICE_KIND)
theme_0_end:
theme_1:
    .incbin .sprintf("theme%d_1.bin", VOICE_KIND)
theme_1_end:
.assert theme_0_end - theme_0 >= 1 && theme_0_end - theme_0 <= 255, error, "basso del tema vuoto o oltre 255 byte"
.assert theme_1_end - theme_1 >= 1 && theme_1_end - theme_1 <= 255, error, "melodia del tema vuota o oltre 255 byte"
.endif

samples:
    .incbin .sprintf("voice%d.bin", VOICE_KIND)
samples_end:

.if FIRST

; ------------------------------------------------------------------------------------ a VOICE_RES

.assert samples_end <= VOL_TAB, error, "file del primo livello sopra la tabella del volume (VOL_TAB)"
    .res VOICE_RES - VOICE_BASE - (* - file_start), 0

; Voce ferma subito (VOICE_HUSH): A, X e Y restano.
.proc hush
    pha
    jsr cia_off
    pla
.endproc
quit:
    rts
.assert hush = VOICE_HUSH, error, "VOICE_HUSH fuori posto"

; Dice i campioni del descrittore a X:Y (inizio, fine; almeno 1 byte): il SID è della voce fino
; alla fine (vedi sopra). Con una voce già in corso non fa niente.
.proc say
    bit $fffb
    bmi quit
    lda VOICE_VOL               ; volume a 0: nessuna voce (né il DC dell'attacco)
    beq quit
    stx src+1
    sty src+2
    jsr vol_check               ; (cambia X)
    ldx #3
src:
    lda $ffff,x
    ldy say_dst,x
    sta VOICE_GO & $ff00,y
    dex
    bpl src
    lda #LO_NEXT                ; la fine solo nell'ultima pagina (nmi_lo: le voci sono tutte più
    sta lo_page+1               ; lunghe di una pagina, quindi la prima non è mai l'ultima)
    lda #0
    sta phase
    sta SID + $17               ; nessuna voce nel filtro del SID: il DC passa diretto
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
    beq to_say
    ldx #<go_desc
    cmp #GO_AT
    beq to_say
    rts
to_say:
    jmp say
.endproc
ready_desc: .word ready, ready_end
go_desc:    .word go, go_end
.assert >ready_desc = >go_desc, error, "descrittori di READY e GO in pagine diverse"


; Timer A del CIA2 fermo, nessuna richiesta in sospeso; prosegue in give_back.
.proc cia_off
    lda #$7f
    sta $dd0d
    lda $dd0d
    lda #0
    sta $dd0e
.endproc

; Il SID torna al programma (A = 0): voci spente, il volume del menu (VOICE_VOL), il suo NMI.
.proc give_back
    sta SID + $04
    sta SID + $0b
    sta SID + $12
    lda VOICE_VOL
    sta SID + $18
    lda old_nmi
    sta $fffa
    lda old_nmi+1
    sta $fffb
    rts
.endproc

.assert * <= VOICE_KEEP, error, "player delle voci oltre VOICE_KEEP (OMCODE, finale)"
ready:
    .incbin "ready.bin"
ready_end:
.assert ready_end <= VOICE_END, error, "READY oltre le tabelle dei quadrati (VOICE_END)"
.assert ready_end - ready > 256 .and go_end - go > 256, error, "READY e GO: almeno due pagine (nmi_lo)"

.else

.assert samples_end <= VOL_TAB, error, "file voce sopra la tabella del volume (VOL_TAB)"

.endif

.assert * - VOICE_BASE <= VOICE_PAGES * 256, error, "file voce più lungo di VOICE_PAGES"
.assert samples_end - samples > 256, error, "nome: almeno due pagine (nmi_lo guarda la fine solo dall'ultima)"
