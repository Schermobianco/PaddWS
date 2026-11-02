; Generato da tools/gen_c64_assets.py: non modificare a mano.

; finale di CHALLENGE (src/ending.s): set di caratteri ending_chars.bin

; scala 2: indice (da 1) per ASCII 32-95, poi i caratteri in alto a sinistra, in alto
; a destra, in basso a sinistra, in basso a destra (indice 0 = spazio)
.define END_BIG_IDX 0, 37, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 0, 0, 0, 0, 0, 0, 0, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 0, 0, 0, 0, 0
.define END_BIG_TL 0, 1, 5, 7, 11, 13, 16, 17, 7, 63, 63, 17, 65, 67, 69, 16, 16, 72, 74, 76, 77, 79, 81, 82, 82, 1, 65, 1, 65, 86, 77, 87, 88, 91, 94, 94, 98, 76
.define END_BIG_TR 0, 2, 0, 8, 8, 0, 15, 0, 18, 8, 2, 2, 8, 15, 2, 70, 70, 73, 75, 0, 0, 4, 0, 83, 75, 2, 8, 2, 8, 15, 15, 75, 89, 87, 95, 95, 4, 0
.define END_BIG_BL 0, 3, 6, 9, 12, 14, 12, 3, 62, 3, 12, 64, 66, 68, 66, 9, 71, 3, 64, 6, 78, 80, 9, 64, 64, 3, 64, 84, 64, 12, 6, 3, 90, 92, 96, 6, 99, 100
.define END_BIG_BR 0, 4, 0, 10, 4, 15, 4, 4, 0, 4, 4, 18, 4, 10, 4, 10, 0, 4, 18, 0, 0, 8, 10, 64, 18, 4, 0, 85, 18, 4, 0, 4, 15, 93, 97, 0, 10, 0
END_STAMP_W = 5
END_STAMP_H = 3
.define END_STAMP 0, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 0
END_FW_BASE = 192    ; fuochi: base + colore * 16 + quadranti (multicolore)
END_CHARS_USED = 162
; titoli di coda (righe virtuali da 0): per riga 0 o la riga di testo (da 1, bit 7: seconda
; riga di un titolo grande); per riga di testo colonna, stile (0 voce bianca, 1 titolo giallo,
; 2 grande giallo), lunghezza, inizio nel testo
END_CRED_LINES = 29
END_CRED_ROWS = 70
END_CRED_LAST = 68    ; prima riga dell'ultima riga di testo
.define END_CRED_ROW 1, 129, 0, 0, 2, 0, 3, 0, 0, 4, 0, 5, 0, 6, 0, 7, 0, 0, 8, 0, 9, 0, 10, 0, 11, 0, 0, 12, 0, 13, 0, 14, 0, 15, 0, 0, 16, 0, 17, 0, 18, 0, 19, 0, 20, 0, 21, 0, 22, 0, 23, 0, 24, 0, 0, 25, 0, 26, 0, 27, 0, 0, 0, 0, 28, 156, 0, 0, 29, 157
.define END_CRED_COL 13, 6, 13, 15, 9, 14, 14, 12, 11, 11, 12, 12, 8, 9, 14, 11, 9, 7, 7, 2, 10, 7, 6, 9, 13, 7, 9, 11, 9
.define END_CRED_STYLE 2, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 2, 2
.define END_CRED_LEN 7, 27, 13, 9, 21, 11, 12, 15, 18, 17, 16, 15, 23, 22, 12, 17, 22, 26, 26, 35, 19, 25, 27, 21, 14, 25, 22, 9, 11
.define END_CRED_OFF 0, 7, 34, 47, 56, 77, 88, 100, 115, 133, 150, 166, 181, 204, 226, 238, 255, 277, 303, 329, 364, 383, 408, 435, 456, 470, 495, 517, 526
.define END_CRED_TEXT "PADD WS", "GAME DESIGN AND PROGRAMMING", "SCHERMOBIANCO", "PLATFORMS", "PC  WEB  RASPBERRY PI", "MISTER FPGA", "COMMODORE 64", "MUSIC AND SOUND", "ORIGINAL SID MUSIC", "SID SOUND EFFECTS", "ANNOUNCER VOICES", "THE CHALLENGERS", "ARCADE   TITAN   HAMMER", "TWIST   BLASTER   RUSH", "AND GUARDIAN", "THIRD-PARTY WORKS", "MUNRO FONT  ED MERRITT", "PONG SCORE FONT  PWNZOR.AK", "MISTER FRAMEWORK  SORGELIG", "SID EMULATION  DAG LEM  A. MELNIKOV", "VEXRISCV  SPINALHDL", "MACROQUAD  FEDOR LOGACHEV", "GILRS  SDL GAMECONTROLLERDB", "PYTHON ARCADE  PIGPIO", "SPECIAL THANKS", "THE MISTER FPGA COMMUNITY", "THE COMMODORE 64 SCENE", "THANK YOU", "FOR PLAYING"
; fuochi d'artificio: tipi (anello, salice, palma, crisantemo, crepitio, croce che si divide)
FW_FRAMES = 3    ; frame per passo
FW_RISE = 45    ; frame del razzo
FW_SLOTS = 4
FW_MAX = 24
FW_KINDS = 6
FW_SPLIT_OFF = 95    ; velocità dopo la divisione (CROSSETTE)
FW_SHOW = 9
.define FW_K_N 18, 12, 7, 22, 20, 16
.define FW_K_LIFE 29, 56, 38, 34, 45, 38
.define FW_K_GRAV 3, 3, 3, 3, 2, 3
.define FW_K_DRAG 5, 5, 5, 5, 0, 0
.define FW_K_TRAIL 0, 2, 2, 0, 0, 0
.define FW_K_FREEZE 0, 0, 0, 0, 21, 0
.define FW_K_SPLIT 0, 0, 0, 0, 0, 14
.define FW_K_FLICK 0, 0, 0, 0, 1, 0
.define FW_K_OFF 0, 18, 30, 37, 59, 79
.define FW_VX 96, 90, 74, 48, 17, 239, 208, 182, 166, 160, 166, 182, 208, 239, 17, 48, 74, 90, 62, 50, 24, 248, 218, 198, 194, 206, 232, 8, 38, 58, 103, 39, 202, 149, 177, 8, 89, 52, 29, 246, 212, 204, 227, 10, 44, 101, 91, 63, 22, 234, 193, 165, 155, 165, 193, 234, 22, 63, 91, 10, 94, 27, 178, 216, 237, 183, 15, 234, 167, 211, 225, 55, 197, 14, 17, 226, 206, 222, 219, 76, 76, 76, 76, 180, 180, 180, 180, 180, 180, 180, 180, 76, 76, 76, 76, 60, 52, 31, 2, 254, 225, 204, 196, 196, 204, 225, 254, 2, 31, 52, 60
.define FW_VY 0, 33, 62, 83, 95, 95, 83, 62, 33, 0, 223, 194, 173, 161, 161, 173, 194, 223, 8, 38, 58, 62, 50, 24, 248, 218, 198, 194, 206, 232, 32, 101, 93, 16, 182, 148, 195, 10, 44, 52, 29, 246, 212, 204, 227, 0, 44, 79, 98, 98, 79, 44, 0, 212, 177, 158, 158, 177, 212, 11, 7, 37, 241, 241, 57, 0, 223, 232, 243, 247, 31, 4, 188, 24, 207, 21, 19, 219, 188, 76, 76, 76, 76, 76, 76, 76, 76, 180, 180, 180, 180, 180, 180, 180, 180, 2, 31, 52, 60, 60, 52, 31, 2, 254, 225, 204, 196, 196, 204, 225, 254
.define FW_VC 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 224, 224, 224, 224, 224, 224, 224, 192, 192, 192, 192, 192, 192, 192, 192, 224, 224, 224, 224, 224, 224, 224, 224, 224, 224, 224, 224, 224, 224, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208, 208
.define FW_S_STEP 0, 9, 18, 28, 40, 52, 59, 67, 75, 255
.define FW_S_KIND 0, 1, 2, 3, 4, 5, 0, 1, 2
.define FW_S_GX 18, 38, 38, 66, 42, 16, 26, 18, 50
.define FW_S_GY 8, 15, 10, 22, 8, 19, 16, 10, 20
.define FW_S_V0 1848, 1536, 1759, 1224, 1848, 1358, 1491, 1759, 1313
.define FW_S_ACC 41, 34, 39, 27, 41, 30, 33, 39, 29
