; Generato da tools/gen_c64_portraits.py: non modificare a mano.

KP_BG_PAGES   = 31          ; bitmap da $E000 (le ultime 8 celle le pulisce il programma)
KP_COL_PAGES  = 4           ; colori da $C000
KP_PANEL_W    = 11
KP_PANEL_H    = 17
KP_PANEL_ROW  = 5
KP_PANEL_COL0 = 0
KP_PANEL_COL1 = 29
KP_GRID_X     = 96
KP_GRID_Y     = 40
KP_LABEL_ROW  = 4
KP_LABEL_COL0 = 4
KP_LABEL_COL1 = 33
KP_OK_COL0    = 8
KP_OK_COL1    = 30
KP_TAG_ROW    = 22
KP_TAG_COL0   = 2
KP_TAG_COL1   = 22
KP_HINT_ROW   = 24
KP_HINT_COL0  = 3
KP_HINT_COL1  = 23
KP_READY_COL  = 17
KP_TIMER_ROW  = 2
KP_TIMER_COL  = 17
KP_SPRITE     = ($E000 + 7360 - $C000) / 64    ; cursore, poi i due riquadri e le due sigle
; pannelli (lato * 7 + tipo): banco (da KP_BANK) e pagina nella finestra a 16K ($80-$BF)
.define KP_PANEL_BANK 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2
.define KP_PANEL_PAGE $A7, $AE, $B5, $80, $87, $8E, $95, $9C, $A3, $AA, $B1, $B8, $80, $87

; schermo VS (kvs.s): pagine nella finestra a 16K del banco KP_BANK + KV_BANK_REL
KV_COLORS = $80 + 4          ; pagina dei colori (4), poi una per la riga 24 e tre per
KV_ROW24P = $80 + 8          ; i caratteri 64-159 (il codice: tools/make_crt.py)
KV_CHARSP = $80 + 9
KV_STAMP4 = $80 + 12
KV_STAMP3 = $80 + 13
KV_STAMP2 = $80 + 14
KV_OMEGA0  = $80 + 15    ; pannello di OMEGA, lato 0
KV_OMEGA1  = $80 + 22    ; pannello di OMEGA, lato 1
KV_BANK_REL = 3    ; banco del VS (codice e dati) da KP_BANK
KV_STAMP_COL = 16
KV_STAMP_ROW = 2
KV_STAMP_W = 8
KV_STAMP_H = 4
KV_OMEGA_H = 18
KV_LEVEL_ROW = 1
KV_TAG_ROW = 19
KV_ICON_ROW = 20
KV_FIRST_ROW = 22
KV_SCORE_ROW = 23

; sfilata del finale (parade.s): pannelli 8x9 celle, uno ogni 3 pagine dalla $80 + 4 del banco
; KP_BANK + PR_BANK_REL (tipo * 2 + sconfitto; OMEGA come tipo 7, poi OMEGA in sagoma)
PR_W = 8
PR_H = 9
PR_ROW_BYTES = 72
PR_PAGE0 = $80 + 4
PR_LOCKED = $80 + 4 + 48
PR_BANK_REL = 4
KP_BANKS      = 5
