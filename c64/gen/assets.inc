; Generato da tools/gen_c64_assets.py: non modificare a mano.

CH_BLANK  = 0
CH_LINE_L = 1    ; mezzeria, colonna 19
CH_LINE_R = 2    ; mezzeria, colonna 20
CH_WALL   = 3    ; muro del singolo, colonna 37

; cifre del punteggio: 9 caratteri per cifra (3 righe di 3)
.define SCORE_TILES 4, 5, 0, 6, 6, 0, 7, 8, 0, 0, 9, 0, 0, 6, 0, 0, 10, 0, 11, 5, 0, 4, 12, 0, 7, 13, 0, 11, 5, 0, 11, 14, 0, 15, 8, 0, 9, 9, 0, 16, 14, 0, 0, 10, 0, 4, 17, 0, 16, 5, 0, 15, 8, 0, 9, 0, 0, 18, 5, 0, 7, 8, 0, 11, 5, 0, 0, 6, 0, 0, 10, 0, 4, 5, 0, 18, 14, 0, 7, 8, 0, 4, 5, 0, 16, 14, 0, 0, 10, 0
; font monospazio: codice del carattere per ASCII 32-95
.define FONT_MAP 0, 19, 0, 0, 0, 0, 0, 0, 0, 0, 0, 20, 0, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 0, 0, 35, 36, 37, 0, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 0, 0, 0, 0, 0
FONT_FIRST = 19
FONT_CHARS = 45
; font: codice nella ROM dei caratteri (set maiuscolo) dei caratteri da FONT_FIRST
.define FONT_ROM 33, 43, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 61, 62, 63, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26
; lettere 2x (GAME OVER, YOU WIN): quattro caratteri per lettera da BIG2_FIRST (alto
; sinistra, alto destra, basso sinistra, basso destra), ogni pixel 2x2 del carattere del
; font BIG2_SRC; il resto delle pagine della scelta resta vuoto
BIG2_FIRST = 64
BIG2_N = 12    ; AEGIMNORUVWY
.define BIG2_SRC 38, 42, 44, 46, 50, 51, 52, 55, 58, 59, 60, 62
; scritte del GAME OVER: larghezza (celle), celle per lettera (BIG_*_K), codici delle due righe
BIG_GAME_OVER_W = 18
BIG_GAME_OVER_K = 2
.define BIG_GAME_OVER 72, 73, 64, 65, 80, 81, 68, 69, 0, 0, 88, 89, 100, 101, 68, 69, 92, 93, 74, 75, 66, 67, 82, 83, 70, 71, 0, 0, 90, 91, 102, 103, 70, 71, 94, 95
BIG_P1_WINS_W = 7
BIG_P1_WINS_K = 1
.define BIG_P1_WINS 53, 25, 0, 60, 46, 51, 56, 0, 0, 0, 0, 0, 0, 0
BIG_P2_WINS_W = 7
BIG_P2_WINS_K = 1
.define BIG_P2_WINS 53, 26, 0, 60, 46, 51, 56, 0, 0, 0, 0, 0, 0, 0
BIG_YOU_WIN_W = 14
BIG_YOU_WIN_K = 2
.define BIG_YOU_WIN 108, 109, 88, 89, 96, 97, 0, 0, 104, 105, 76, 77, 84, 85, 110, 111, 90, 91, 98, 99, 0, 0, 106, 107, 78, 79, 86, 87
BIG_CPU_WINS_W = 8
BIG_CPU_WINS_K = 1
.define BIG_CPU_WINS 40, 53, 58, 0, 60, 46, 51, 56, 0, 0, 0, 0, 0, 0, 0, 0
CH_CURSOR = 160
CH_GRID_TL = 161
CH_GRID_T = 162
CH_GRID_L = 163
CH_GRID_TLB = 164
CH_GRID_TB = 165
; NEXT: capsule 2x2 (alto sinistra, alto destra, basso sinistra, basso destra), per bonus
; normale e in negativo: indice = bonus * 8 + negativo * 4
.define CAP_CHARS 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 160, 161, 163, 164, 165, 166, 167, 168
; BULLET: le sue capsule della riserva al posto dei caratteri BULLET_C0-7 (bullet_chars),
; con quelli originali per le partite che non sono NEXT
BULLET_C0 = 160
BULLET_C1 = 161
BULLET_C2 = 163
BULLET_C3 = 164
BULLET_C4 = 165
BULLET_C5 = 166
BULLET_C6 = 167
BULLET_C7 = 168
.define CAP_EMPTY 225, 226, 227, 228
CH_ARROW_L = 229
CH_ARROW_R = 230
CH_BAR_R = 231    ; pixel 7 della colonna
CH_BAR_L = 232    ; pixel 0 della colonna
.define SHOT_CHARS 233, 0, 234, 235, 236, 237, 238, 239    ; per fase: primo, secondo
CH_STEER_TOP_R = 240
CH_STEER_TOP_L = 241
CH_STEER_BOTTOM_R = 242
CH_STEER_BOTTOM_L = 243

CH_SOLID = 244
; NEXT, mosse speciali: caratteri della barra (supers.s, bullet_chars)
BAR_C0 = 245
BAR_CHARS = 5
.define BAR_GLYPHS $FF, $00, $00, $00, $FF, $00, $00, $00, $FF, $C0, $C0, $C0, $FF, $00, $00, $00, $FF, $F0, $F0, $F0, $FF, $00, $00, $00, $FF, $FC, $FC, $FC, $FF, $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $00, $00, $00
; icone della mossa armata: STRAIGHT SHOT sinistro e destro, RISING STRIKE sinistro e destro
.define SUPER_ICONS $00, $00, $04, $06, $FF, $06, $04, $00, $00, $00, $20, $60, $FF, $60, $20, $00, $00, $07, $03, $05, $08, $F0, $00, $00, $00, $E0, $C0, $A0, $10, $0F, $00, $00
SID_FX_MOVE = 6
.define SID_TRACK_MOVE $71, $93, $80, $28, $2B, $08, $80, $3C, $32, $0A, $FF
SID_FX_SPECIAL = 7
.define SID_TRACK_SPECIAL $75, $54, $03, $76, $54, $02, $4F, $02, $4C, $02, $48, $02, $43, $02, $40, $02, $3C, $03, $37, $03, $30, $08, $FF
SID_FX_LASER = 8
.define SID_TRACK_LASER $74, $58, $01, $53, $01, $4E, $01, $49, $01, $44, $01, $40, $02, $FF
SID_FX_BOUNCE = 9
.define SID_TRACK_BOUNCE $73, $4C, $06, $FF

; attract (attract.json riportato a 320x200 e 50 Hz)
AT_BOOT_FRAMES = 240
AT_STRIPES_FRAMES = 120
AT_LOGO_FRAMES = 110
AT_TITLE_FRAMES = 400
AT_GAME_OVER_FRAMES = 150
AT_GAME_OVER_BLACK = 100
AT_BOOT_LINE_FRAMES = 25
AT_BOOT_GRID_FROM = 190
AT_CURSOR_HALF = 8
AT_STRIPE_STEP = 10
AT_SLIDE_LAST = 35
AT_STRIPE_H = 12
AT_STRIPE_LEFT = 75
AT_STRIPE_RIGHT = 241
AT_LOGO_Y = 74
AT_LOGO_H = 51
AT_LOGO_X = 82
AT_LOGO_W = 152
AT_LOGO_C0 = 10
AT_LOGO_C1 = 29
AT_WIPE_FRAMES = 70
AT_FLASH_FRAMES = 3
AT_WS_Y = 116
AT_WS_H = 8
AT_WS_C0 = 30
AT_WS_C1 = 32
AT_BLINK_PERIOD = 50
AT_BLINK_ON = 31
AT_LABEL_FROM = 45
AT_LABEL_C0 = 14
AT_LABEL_W = 11
AT_LABEL_R0 = 19
AT_LABEL_2X = 0
AT_FREE_C0 = 15
AT_CREDIT_C0 = 16
AT_CREDIT_W = 10
AT_CREDIT_R0 = 22
AT_BALL_X = 640
AT_BALL_Y = 2560
AT_BALL_VX = 123
AT_BALL_VY = 90
AT_BALL_SIZE = 4
AT_COPYRIGHT_Y = 192
AT_COPYRIGHT_H = 8
AT_COPYRIGHT_C0 = 12
AT_STRIPE_Y0 = 76
AT_STRIPE_Y1 = 95
AT_STRIPE_Y2 = 114
.define AT_WS_OFF 0, 12, 25, 38
; strisce: pixel coperti a sinistra e a destra, frame per frame
.define AT_SLIDE_LEFT 0, 8, 15, 29, 35, 40, 45, 50, 58, 62, 65, 68, 71, 75, 76, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 77, 77, 76, 76, 75, 75, 75
.define AT_SLIDE_RIGHT 0, 8, 16, 30, 37, 43, 48, 53, 62, 65, 69, 72, 74, 79, 81, 82, 82, 82, 82, 82, 82, 82, 82, 82, 82, 82, 82, 82, 82, 82, 81, 80, 80, 79, 79, 79
TITLE_A_ROW = 9    ; righe di caratteri del blocco A in title.bin, poi il B
TITLE_A_END = 16
TITLE_A_C0 = 10    ; colonne del blocco A (il B è largo tutto lo schermo)
TITLE_A_W = 23
TITLE_B_ROW = 24
TITLE_B_END = 25
TITLE_SIZE = 1608    ; byte di title.bin
.define AT_COPYRIGHT_TEXT "2026 SCHERMOBIANCO"
CHARSET_USED = 250
PICK_FIRST = 64    ; scelta dei bonus: caratteri sostituiti (pagine intere)
PICK_PAGES = 3
SPRITE_BANDS = 10
SPRITE_CAPS = 8
SPRITE_ICONS = 7
CAP_DRAW = 12
SPRITES_N = 32
FX_SPRITES = 2    ; effetti della palla: 2 aloni
FX_RING_X = 9
FX_RING_Y = 7
TRAIL_N = 5    ; coda: posizioni passate della palla
; coda: retino per età (2 * TRAIL_N, TRAIL_ROWS righe ciascuna), %01 nei pixel doppi accesi
.define TRAIL_DITHER $55, $55, $55, $15, $55, $55, $55, $15, $55, $55, $55, $15, $55, $55, $55, $15, $55, $55, $55, $15, $55, $55, $55, $15, $55, $51, $55, $15, $55, $51, $55, $15, $55, $51, $55, $15, $55, $51, $55, $15, $55, $51, $55, $15, $55, $51, $55, $15, $55, $11, $55, $11, $55, $11, $55, $11, $55, $11, $55, $11, $55, $11, $55, $11, $55, $11, $55, $11, $55, $11, $55, $11, $55, $11, $45, $11, $55, $11, $45, $11, $55, $11, $45, $11, $55, $11, $45, $11, $55, $11, $45, $11, $55, $11, $45, $11, $54, $11, $44, $11, $54, $11, $44, $11, $54, $11, $44, $11, $54, $11, $44, $11, $54, $11, $44, $11, $54, $11, $44, $11, $44, $11, $44, $11, $44, $11, $44, $11, $44, $11, $44, $11, $44, $11, $44, $11, $44, $11, $44, $11, $44, $11, $44, $11, $44, $10, $44, $01, $44, $10, $44, $01, $44, $10, $44, $01, $44, $10, $44, $01, $44, $10, $44, $01, $44, $10, $44, $01, $44, $10, $44, $00, $44, $10, $44, $00, $44, $10, $44, $00, $44, $10, $44, $00, $44, $10, $44, $00, $44, $10, $44, $00, $44, $00, $04, $00, $44, $00, $04, $00, $44, $00, $04, $00, $44, $00, $04, $00, $44, $00, $04, $00, $44, $00, $04, $00, $40, $00, $04, $00, $40, $00, $04, $00, $40, $00, $04, $00, $40, $00, $04, $00, $40, $00, $04, $00, $40, $00, $04, $00
TRAIL_SPAN = 48    ; coda: coordinate dei quadrati nello sprite + 16, da 0 a 47
.define TRAIL_X_B0 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $02, $02, $02, $02, $02, $02, $02, $02, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $02, $02, $02, $02, $02, $02, $02, $02, $00, $00, $00, $00, $00, $00, $00, $00
.define TRAIL_X_LM $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $C0, $C0, $F0, $F0, $FC, $3C, $3F, $0F, $0F, $03, $03, $F0, $FC, $3C, $3F, $0F, $0F, $03, $03, $F0, $FC, $3C, $3F, $0F, $0F, $03, $03, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $C0, $C0, $F0, $F0, $FC, $FC, $FF, $3F, $3F, $0F, $0F, $03, $03, $FC, $FF, $3F, $3F, $0F, $0F, $03, $03, $FC, $FF, $3F, $3F, $0F, $0F, $03, $03, $00, $00, $00, $00, $00, $00, $00, $00
.define TRAIL_X_RM $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $C0, $C0, $F0, $00, $00, $00, $00, $00, $C0, $C0, $F0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $C0, $C0, $F0, $F0, $FC, $00, $00, $00, $C0, $C0, $F0, $F0, $FC, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.define TRAIL_Y_BASE $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $06, $09, $0C, $0F, $12, $15, $18, $1B, $1E, $21, $24, $27, $2A, $2D, $30, $33, $36, $39, $3C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $06, $09, $0C, $0F, $12, $15, $18, $1B, $1E, $21, $24, $27, $2A, $2D, $30, $33, $36, $39, $3C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.define TRAIL_Y_ROWS $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $02, $03, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $03, $02, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $02, $03, $04, $05, $06, $06, $06, $06, $06, $06, $06, $06, $06, $06, $06, $06, $06, $06, $06, $06, $05, $04, $03, $02, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.define TRAIL_Y_R0 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $0B, $0C, $0D, $0E, $0F, $10, $11, $12, $13, $14, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $0B, $0C, $0D, $0E, $0F, $10, $11, $12, $13, $14, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.define TRAIL_AGE $00, $18, $30, $48, $60, $78, $90, $A8, $C0, $D8
; aloni: quadrati (x, y, lato) per immagine, $FF alla fine di ognuna
.define FX_SQUARES 9, 7, 4, 5, 3, 1, 5, 5, 1, 5, 7, 1, 5, 9, 1, 5, 11, 1, 5, 13, 1, 6, 14, 1, 7, 3, 1, 8, 14, 1, 9, 3, 1, 10, 14, 1, 11, 3, 1, 12, 14, 1, 13, 3, 1, 14, 14, 1, 15, 3, 1, 16, 4, 1, 16, 6, 1, 16, 8, 1, 16, 10, 1, 16, 12, 1, 16, 14, 1, 255, 9, 7, 6, 3, 1, 1, 3, 3, 1, 3, 5, 1, 3, 7, 1, 3, 9, 1, 3, 11, 1, 3, 13, 1, 3, 15, 1, 3, 17, 1, 4, 18, 1, 5, 1, 1, 6, 18, 1, 7, 1, 1, 8, 18, 1, 9, 1, 1, 10, 18, 1, 11, 1, 1, 12, 18, 1, 13, 1, 1, 14, 18, 1, 15, 1, 1, 16, 18, 1, 17, 1, 1, 18, 18, 1, 19, 1, 1, 20, 2, 1, 20, 4, 1, 20, 6, 1, 20, 8, 1, 20, 10, 1, 20, 12, 1, 20, 14, 1, 20, 16, 1, 20, 18, 1, 255
; HOW TO PLAY: scritte nella riga HT_DATA_ROW della bitmap, vuota e nera (colonna, con il
; bit 7 a 2x; riga; testo; 0), $FE alla fine di ogni frame di disegno, $FF alla fine (i
; colori sono già in howto.bin)
HT_GROUPS = 10
HT_TEXTS_AT = $E140
; astronavi delle racchette di NEXT (assets/ships/sprites/c64): righe viste dalla racchetta
; sinistra, 3 byte per riga; x dello sprite: colonna della racchetta - PAD_DX_L / PAD_DX_R
; (per tipo, poi la racchetta senza tipo); PAD_BL_THR: prima riga accesa del BLASTER per
; livello del caricatore (0-4)
.define PAD_DX_L 8, 8, 8, 12, 10, 8, 8, 8
.define PAD_DX_R 12, 12, 12, 8, 10, 12, 12, 12
.define PAD_IMG_N 14, 20, 17, 17, 19, 14, 14
.define PAD_BL_THR 19, 10, 9, 8, 0
.define PAD_IMG_ARCADE $01, $40, $00, $05, $50, $00, $0F, $F0, $00, $3F, $F0, $00, $7F, $F0, $00, $05, $50, $00, $0A, $A0, $00, $0A, $A0, $00, $05, $50, $00, $7F, $F0, $00, $3F, $F0, $00, $0F, $F0, $00, $05, $50, $00, $01, $40, $00
.define PAD_IMG_TITAN $03, $F0, $00, $03, $F0, $00, $01, $50, $00, $1F, $F0, $00, $47, $F0, $00, $17, $F0, $00, $1F, $F0, $00, $03, $F0, $00, $0A, $A0, $00, $05, $A0, $00, $05, $A0, $00, $0A, $A0, $00, $03, $F0, $00, $1F, $F0, $00, $17, $F0, $00, $47, $F0, $00, $1F, $F0, $00, $01, $50, $00, $03, $F0, $00, $03, $F0, $00
.define PAD_IMG_HAMMER $05, $80, $00, $00, $90, $00, $0A, $90, $00, $08, $D0, $00, $08, $D0, $00, $08, $D0, $00, $08, $D0, $00, $10, $D0, $00, $08, $D0, $00, $10, $D0, $00, $08, $D0, $00, $08, $D0, $00, $08, $D0, $00, $08, $D0, $00, $08, $D0, $00, $00, $10, $00, $05, $40, $00
.define PAD_IMG_TWIST $00, $0C, $00, $00, $0F, $00, $00, $3F, $00, $00, $BD, $00, $02, $BD, $00, $00, $BD, $00, $00, $3D, $00, $00, $AD, $00, $02, $A9, $00, $00, $AD, $00, $00, $3D, $00, $00, $BD, $00, $02, $BD, $00, $00, $BD, $00, $00, $3F, $00, $00, $0F, $00, $00, $0C, $00
.define PAD_IMG_BLASTER $03, $D0, $00, $0F, $F4, $00, $0F, $F4, $00, $0F, $F4, $00, $04, $F4, $00, $01, $01, $80, $03, $F4, $00, $43, $F4, $00, $AE, $E4, $00, $AF, $B4, $00, $AE, $E4, $00, $43, $F4, $00, $03, $F4, $00, $01, $01, $80, $04, $F4, $00, $0F, $F4, $00, $0F, $F4, $00, $0F, $F4, $00, $03, $D0, $00
.define PAD_IMG_RUSH $02, $80, $00, $09, $D0, $00, $23, $D0, $00, $03, $D0, $00, $03, $D0, $00, $03, $F0, $00, $06, $90, $00, $06, $90, $00, $03, $F0, $00, $03, $D0, $00, $03, $D0, $00, $23, $D0, $00, $09, $D0, $00, $02, $80, $00
.define PAD_IMG_GUARDIAN $00, $F0, $00, $00, $F0, $00, $00, $A0, $00, $08, $F0, $00, $02, $F0, $00, $05, $A0, $00, $05, $F0, $00, $05, $F0, $00, $05, $A0, $00, $02, $F0, $00, $08, $F0, $00, $00, $A0, $00, $00, $F0, $00, $00, $F0, $00

; titoli disegnati (assets/titles): caratteri hires, un colore per cella. Nomi e PERFECT
; da TN_FIRST (una pagina di titles.bin ciascuno), la targa da TC_FIRST (due pagine)
TN_FIRST = 128
TC_FIRST = 64
; nomi: celle (larghezza, altezza), prima riga e colonna, y del centro (pixel), codici e
; colori riga per riga (0: cella vuota)
TN_0_W = 8    ; ARCADE, 16 caratteri
TN_0_H = 2
TN_0_ROW = 12
TN_0_COL = 16
TN_0_CY = 103
.define TN_0_MAP 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143
.define TN_0_CLR 1, 1, 1, 1, 1, 1, 1, 1, 7, 7, 7, 7, 7, 7, 7, 7
TN_1_W = 6    ; TITAN, 24 caratteri
TN_1_H = 5
TN_1_ROW = 10
TN_1_COL = 17
TN_1_CY = 99
.define TN_1_MAP 128, 129, 129, 129, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 150, 150, 150, 151
.define TN_1_CLR 7, 7, 7, 7, 7, 7, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 7, 7, 7, 7, 7
TN_2_W = 11    ; HAMMER, 22 caratteri
TN_2_H = 2
TN_2_ROW = 12
TN_2_COL = 14
TN_2_CY = 103
.define TN_2_MAP 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149
.define TN_2_CLR 7, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 7, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7
TN_3_W = 5    ; TWIST, 13 caratteri
TN_3_H = 3
TN_3_ROW = 11
TN_3_COL = 17
TN_3_CY = 102
.define TN_3_MAP 128, 0, 0, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140
.define TN_3_CLR 1, 0, 0, 7, 1, 1, 7, 1, 7, 1, 1, 7, 1, 7, 1
TN_4_W = 12    ; BLASTER, 31 caratteri
TN_4_H = 3
TN_4_ROW = 12
TN_4_COL = 14
TN_4_CY = 107
.define TN_4_MAP 0, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 0, 0, 0, 151, 152, 153, 154, 155, 156, 157, 158, 0
.define TN_4_CLR 0, 12, 12, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 0, 0, 0, 7, 7, 7, 7, 7, 7, 7, 7, 0
TN_5_W = 7    ; RUSH, 13 caratteri
TN_5_H = 2
TN_5_ROW = 12
TN_5_COL = 16
TN_5_CY = 103
.define TN_5_MAP 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 0
.define TN_5_CLR 12, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0
TN_6_W = 10    ; GUARDIAN, 18 caratteri
TN_6_H = 2
TN_6_ROW = 12
TN_6_COL = 15
TN_6_CY = 103
.define TN_6_MAP 128, 129, 130, 131, 132, 133, 134, 135, 131, 136, 137, 138, 139, 140, 141, 142, 143, 144, 140, 145
.define TN_6_CLR 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7
; PERFECT: celle, codici riga per riga, colore di ogni riga
TP_W = 15    ; 24 caratteri
TP_H = 4
.define TP_MAP 128, 129, 130, 131, 132, 129, 130, 131, 132, 131, 133, 134, 135, 136, 137, 128, 138, 139, 140, 128, 141, 139, 140, 128, 140, 128, 0, 0, 142, 0, 128, 0, 128, 143, 144, 145, 144, 0, 128, 143, 146, 147, 148, 142, 0, 149, 150, 150, 150, 150, 150, 150, 150, 150, 150, 150, 150, 150, 150, 151
.define TP_ROWC 1, 7, 8, 7
; targa di HERE COMES A NEW CHALLENGER!: celle, codici riga per riga (da TC_YEL0 gialli,
; prima bianchi), sprite del rosso (immagine a TC_SPRITE, righe espanse, x dal bordo
; sinistro della targa, y dal bordo alto)
TC_W = 24    ; 53 caratteri
TC_H = 5
TC_YEL0 = 92
TC_SPRITE = 120
TC_SPR_Y = 6
TC_SPR_X0 = 3
TC_SPR_X1 = 51
TC_SPR_X2 = 99
TC_SPR_X3 = 141
.define TC_MAP 92, 93, 93, 93, 93, 93, 93, 93, 93, 93, 93, 93, 93, 93, 93, 93, 93, 93, 93, 93, 93, 93, 93, 94, 95, 0, 0, 0, 0, 0, 64, 65, 66, 67, 68, 0, 69, 70, 71, 72, 73, 74, 0, 0, 0, 0, 0, 96, 95, 0, 75, 76, 0, 77, 78, 79, 80, 81, 82, 83, 76, 84, 85, 78, 86, 87, 88, 89, 90, 91, 0, 96, 95, 0, 97, 98, 0, 99, 100, 101, 102, 103, 104, 105, 98, 106, 107, 100, 108, 109, 110, 111, 112, 113, 0, 96, 114, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 116
TN_7_W = 10    ; OMEGA, 19 caratteri
TN_7_H = 4
TN_7_ROW = 11
TN_7_COL = 15
TN_7_CY = 103
.define TN_7_MAP 128, 128, 128, 129, 130, 131, 132, 128, 128, 128, 0, 0, 0, 0, 133, 134, 0, 0, 0, 0, 0, 0, 135, 136, 137, 138, 139, 140, 0, 0, 0, 0, 141, 142, 143, 144, 145, 146, 0, 0
.define TN_7_CLR 2, 2, 2, 2, 7, 7, 2, 2, 2, 2, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0
; WARNING! prima di OMEGA: come la targa (stessi sprite del rosso), da TW_YEL0 gialli
TW_YEL0 = 94    ; 53 caratteri
.define TW_MAP 94, 95, 95, 95, 95, 95, 95, 95, 95, 95, 95, 95, 95, 95, 95, 95, 95, 95, 95, 95, 95, 95, 95, 96, 97, 0, 0, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 77, 0, 0, 98, 97, 0, 0, 64, 81, 82, 83, 77, 84, 85, 86, 87, 0, 88, 80, 89, 77, 90, 91, 92, 93, 0, 0, 98, 97, 0, 0, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 102, 103, 111, 112, 108, 113, 0, 0, 98, 114, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 115, 116
; titles.bin: pagina del nome k (TTL_NAMES + k), di PERFECT, della targa (due), del nome di
; OMEGA, di WARNING! (due)
TTL_NAMES = 0
TTL_PERFECT = 7
TTL_PLATE = 8
TTL_OMEGA = 10
TTL_WARN = 11
TTL_PAGES = 13
