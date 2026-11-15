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
; lettere 2x (GAME OVER, YOU WIN, PERFECT): quattro caratteri per lettera da BIG2_FIRST (alto
; sinistra, alto destra, basso sinistra, basso destra), ogni pixel 2x2 del carattere del
; font BIG2_SRC; il resto delle pagine della scelta resta vuoto
BIG2_FIRST = 64
BIG2_N = 16    ; ACEFGIMNOPRTUVWY
.define BIG2_SRC 38, 40, 42, 43, 44, 46, 50, 51, 52, 53, 55, 57, 58, 59, 60, 62
; scritte del GAME OVER: larghezza (celle), celle per lettera (BIG_*_K), codici delle due righe
BIG_GAME_OVER_W = 18
BIG_GAME_OVER_K = 2
.define BIG_GAME_OVER 80, 81, 64, 65, 88, 89, 72, 73, 0, 0, 96, 97, 116, 117, 72, 73, 104, 105, 82, 83, 66, 67, 90, 91, 74, 75, 0, 0, 98, 99, 118, 119, 74, 75, 106, 107
BIG_P1_WINS_W = 7
BIG_P1_WINS_K = 1
.define BIG_P1_WINS 53, 25, 0, 60, 46, 51, 56, 0, 0, 0, 0, 0, 0, 0
BIG_P2_WINS_W = 7
BIG_P2_WINS_K = 1
.define BIG_P2_WINS 53, 26, 0, 60, 46, 51, 56, 0, 0, 0, 0, 0, 0, 0
BIG_YOU_WIN_W = 14
BIG_YOU_WIN_K = 2
.define BIG_YOU_WIN 124, 125, 96, 97, 112, 113, 0, 0, 120, 121, 84, 85, 92, 93, 126, 127, 98, 99, 114, 115, 0, 0, 122, 123, 86, 87, 94, 95
BIG_CPU_WINS_W = 8
BIG_CPU_WINS_K = 1
.define BIG_CPU_WINS 40, 53, 58, 0, 60, 46, 51, 56, 0, 0, 0, 0, 0, 0, 0, 0
BIG_PERFECT_W = 14
BIG_PERFECT_K = 2
.define BIG_PERFECT 100, 101, 72, 73, 104, 105, 76, 77, 72, 73, 68, 69, 108, 109, 102, 103, 74, 75, 106, 107, 78, 79, 74, 75, 70, 71, 110, 111
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
.define SID_TRACK_MOVE $71, $93, $80, $28, $2B, $08, $80, $3C, $32, $0A, $FF
.define SID_TRACK_SPECIAL $75, $54, $03, $76, $54, $02, $4F, $02, $4C, $02, $48, $02, $43, $02, $40, $02, $3C, $03, $37, $03, $30, $08, $FF

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
; HOW TO PLAY: scritte nella bitmap (colonna, con il bit 7 a 2x; riga; testo; 0), $FE
; alla fine di ogni frame di disegno, $FF alla fine (i colori sono già in howto.bin)
HT_GROUPS = 7
.define HT_TEXTS 14, 0, "HOW TO PLAY", 0, 9, 2, "SUPER MOVES - JOYSTICK", 0, $FE, 2, 4, "STRAIGHT SHOT", 0, 2, 6, "NEXT SHOT FLAT AND FAST", 0, $FE, 20, 9, "FIRE", 0, 2, 12, "RISING STRIKE", 0, 20, 17, "FIRE", 0, $FE, 2, 14, "FLAT SHOT WITH A LATE BREAK", 0, $FE, 2, 20, "HALF", 0, 13, 20, "= MOVE", 0, 20, 20, "FULL", 0, 30, 20, "= MAX", 0, $FE, 1, 22, "FIRE: USE THE BONUS     FORWARD: DASH", 0, $FE, 11, 24, "PRESS FIRE TO SKIP", 0, $FF
