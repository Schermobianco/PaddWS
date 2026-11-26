; Generato da tools/gen_c64_rotated.py: non modificare a mano.

; caratteri 1-3: quelli di oggi (fuori dalla partita) e CH_LINE_R e CH_WALL del campo girato
.define ROT_GL_TODAY $01, $01, $01, $01, $00, $00, $00, $00, $80, $80, $80, $80, $00, $00, $00, $00, $3C, $3C, $3C, $3C, $3C, $3C, $3C, $3C
.define ROT_GL_FIELD $C0, $C0, $C0, $C0, $C0, $C0, $C0, $C0, $00, $00, $00, $00, $FF, $FF, $FF, $FF

; campo girato: mezzeria nella riga 12, muro destro nella colonna 30, muro del singolo nella riga 1
ROT_LINE_ROW = 12
ROT_WALL_COL = 30
ROT_SINGLE_ROW = 1
ROT_FIELD_COLS = 30
ROT_HUD_COL = 31               ; fascia dell'HUD: prima colonna
; reti degli avversari nel carattere della mezzeria (il motivo di net_l/net_r girato, x = 156-163)
.define ROT_NET $00, $3F, $21, $21, $21, $21, $3F, $00, $00, $00, $00, $FF, $FF, $00, $00, $00, $FF, $FF, $FF, $00, $00, $FF, $FF, $FF, $00, $00, $00, $30, $F0, $C0, $00, $00, $00, $0C, $0C, $00, $00, $C0, $C0, $00, $00, $00, $00, $F0, $F0, $00, $00, $00, $F0, $F0, $00, $F0, $F0, $F0, $F0, $00, $00, $00, $00, $F0, $F0, $00, $00, $00
; reti animate: TWIST (dritta, a destra, a sinistra) e HAMMER (3 spostamenti), 8 byte l'una
.define ROT_NET_TW $00, $00, $00, $30, $F0, $C0, $00, $00, $00, $30, $F0, $C0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $30, $F0, $C0
.define ROT_NET_HAM $FF, $FF, $FF, $00, $00, $FF, $FF, $FF, $FF, $FF, $00, $00, $FF, $FF, $FF, $00, $00, $FF, $FF, $FF, $00, $00, $FF, $FF
; BLASTER: colonna delle bocche dei cannoni dalla prima colonna della racchetta (la prima,
; pari) e distanza della seconda; metà lunghezza della racchetta
ROT_SHOT_A = 10
ROT_SHOT_D = 22
ROT_BL_HALF = 22
; GUARDIAN: per corso dello scudo (0 il più a destra, il settore in alto nel core), per i 6 byte
; di una riga: il bianco da tenere (HIK), le coppie da tenere (MCK) e le coppie %01 (LO); righe
; dello scudo
.define ROT_G_HIK $FF, $FF, $FF, $FF, $C0, $FF, $FF, $FF, $FF, $F0, $FF, $FF, $FF, $FF, $FC, $3F, $FF, $FF, $FF, $FF, $0F, $FF, $FF, $FF, $FF, $03, $FF, $FF, $FF, $FF
.define ROT_G_MCK $FF, $FF, $FF, $FF, $C0, $FF, $FF, $FF, $FF, $F0, $FF, $FF, $FF, $FF, $FC, $3F, $FF, $FF, $FF, $FF, $0F, $FF, $FF, $FF, $FF, $03, $FF, $FF, $FF, $FF
.define ROT_G_LO $00, $00, $00, $00, $15, $00, $00, $00, $00, $05, $00, $00, $00, $00, $01, $40, $00, $00, $00, $00, $50, $00, $00, $00, $00, $54, $00, $00, $00, $00
ROT_G_ROWS = 4
; aloni di SLOW già disegnati (al posto di fx_copy con spin_plot): 2 sprite da 64 byte
.define ROT_RINGS $00, $00, $00, $00, $00, $00, $00, $00, $00, $05, $55, $00, $00, $00, $80, $04, $00, $00, $00, $00, $80, $04, $78, $00, $00, $78, $80, $04, $78, $00, $00, $78, $80, $04, $00, $00, $00, $00, $80, $04, $00, $00, $02, $AA, $80, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $15, $55, $50, $00, $00, $08, $10, $00, $00, $00, $00, $08, $10, $00, $00, $00, $00, $08, $10, $7E, $00, $00, $7E, $08, $10, $7E, $00, $00, $7E, $08, $10, $7E, $00, $00, $7E, $08, $10, $00, $00, $00, $00, $08, $10, $00, $00, $00, $00, $08, $10, $00, $00, $0A, $AA, $A8, $00, $00, $00, $00, $00, $00, $00

; pose delle astronavi (paddles.bin): per tipo e lato 4 pagine; nella posa lo sprite sinistro
; comincia ROT_OFF pixel prima della prima colonna della racchetta. Faccia: riga ROT_NOSE
; dell'immagine in basso, 20 - ROT_NOSE in quella in alto
.define ROT_OFF 8, 0, 4, 4, 2, 6, 8, 4
.define ROT_NOSE 0, 0, 0, 3, 2, 0, 0, 0
ROT_TWIST_T = 2
; scelta: la posa in basso ROT_PICK_DY righe più in giù, all'altezza di quella in alto
.define ROT_PICK_DY 9, 6, 8, 5, 3, 9, 12, 17
; salto del TELEPORT a caratteri (warp_tables): per arrivo * 33 + avanzamento
.define ROT_WB0 $C0, $C0, $C0, $C0, $C0, $CC, $CC, $CC, $CC, $CC, $CC, $CC, $CC, $FC, $FC, $FC, $FC, $FC, $FC, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FC, $FC, $FC, $FC, $FC, $FC, $CC, $CC, $CC, $CC, $CC, $CC, $CC, $CC, $C0, $C0, $C0, $C0, $C0, $00, $00, $00
.define ROT_WB1 $00, $00, $30, $30, $30, $30, $30, $30, $33, $33, $33, $F3, $F3, $F3, $F3, $F3, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $F3, $F3, $F3, $F3, $F3, $33, $33, $33, $30, $30, $30, $30, $30, $30, $00, $00, $00, $00, $00
.define ROT_WL0 $C0, $C0, $C0, $C0, $C0, $CC, $CC, $CC, $0C, $0C, $0C, $0C, $0C, $30, $30, $30, $30, $30, $30, $33, $33, $03, $03, $03, $03, $03, $03, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $03, $03, $03, $03, $03, $33, $33, $30, $30, $30, $30, $30, $30, $0C, $0C, $0C, $0C, $0C, $CC, $CC, $CC, $C0, $C0, $C0, $C0, $C0, $00, $00, $00
.define ROT_WL1 $00, $00, $30, $30, $30, $30, $30, $30, $33, $33, $03, $C3, $C3, $C3, $C3, $C3, $CC, $CC, $CC, $0C, $0C, $0C, $0C, $0C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0C, $0C, $0C, $0C, $0C, $CC, $CC, $CC, $C3, $C3, $C3, $C3, $C3, $03, $33, $33, $30, $30, $30, $30, $30, $30, $00, $00, $00, $00, $00
.define ROT_WEL $01, $01, $03, $03, $03, $03, $03, $03, $02, $02, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $02, $02, $03, $03, $03, $03, $03, $03, $01, $01, $00, $00, $00
ROT_BAND_ROWS = 4
; icone della mossa armata girate con il campo (colonna = y, riga = larghezza - x): le frecce
; puntano verso l'avversario, in alto per chi sta in basso e in basso per chi sta in alto
.define ROT_SUPER_ICONS $10, $38, $7C, $10, $10, $10, $10, $10, $10, $10, $10, $10, $10, $7C, $38, $10, $0E, $06, $0A, $10, $20, $20, $20, $20, $20, $20, $20, $20, $10, $0A, $06, $0E

