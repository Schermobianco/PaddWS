; Generato da tools/gen_c64_assets.py: non modificare a mano.

; finale di CHALLENGE (src/ending.s): set di caratteri ending_chars.bin

END_BIG_BASE = 64    ; lettere 2x: quattro caratteri per lettera da qui
END_BIG_N = 7
; lettere 2x: il carattere del font da cui si fanno (big_build)
.define END_BIG_SRC 19, 46, 51, 52, 58, 60, 62
; scala 2: indice (da 1) per ASCII 32-95, poi i caratteri in alto a sinistra, in alto
; a destra, in basso a sinistra, in basso a destra (indice 0 = spazio)
.define END_BIG_IDX 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 3, 4, 0, 0, 0, 0, 0, 5, 0, 6, 0, 7, 0, 0, 0, 0, 0, 0
.define END_BIG_TL 0, 64, 68, 72, 76, 80, 84, 88
.define END_BIG_TR 0, 65, 69, 73, 77, 81, 85, 89
.define END_BIG_BL 0, 66, 70, 74, 78, 82, 86, 90
.define END_BIG_BR 0, 67, 71, 75, 79, 83, 87, 91
END_STAMP_W = 5
END_STAMP_H = 3
.define END_STAMP 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 0
END_FW_BASE = 192    ; fuochi: base + colore * 16 + quadranti (multicolore)
END_CHARS_USED = 135
; titoli di coda (righe virtuali da 0): per riga 0 o la riga di testo (da 1, bit 7: seconda
; riga di un titolo grande); per riga di testo colonna, stile (0 voce bianca, 1 titolo giallo,
; 2 grande giallo), lunghezza, inizio nel testo
END_CRED_LINES = 28
END_CRED_ROWS = 70
END_CRED_LAST = 68    ; prima riga dell'ultima riga di testo
.define END_CRED_ROW 1, 0, 0, 0, 2, 0, 3, 0, 0, 4, 0, 5, 0, 6, 0, 7, 0, 0, 8, 0, 9, 0, 10, 0, 11, 0, 0, 12, 0, 13, 0, 14, 0, 15, 0, 0, 16, 0, 17, 0, 18, 0, 19, 0, 20, 0, 21, 0, 22, 0, 23, 0, 0, 24, 0, 25, 0, 26, 0, 0, 0, 0, 0, 0, 27, 0, 0, 0, 28, 0
.define END_CRED_COL 16, 6, 13, 15, 9, 14, 14, 12, 11, 11, 12, 12, 8, 9, 14, 11, 7, 7, 2, 10, 7, 6, 9, 13, 7, 9, 15, 14
.define END_CRED_STYLE 1, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1
.define END_CRED_LEN 7, 27, 13, 9, 21, 11, 12, 15, 18, 17, 16, 15, 23, 22, 12, 17, 26, 26, 35, 19, 25, 27, 21, 14, 25, 22, 9, 11
.define END_CRED_OFF 0, 7, 34, 47, 56, 77, 88, 100, 115, 133, 150, 166, 181, 204, 226, 238, 255, 281, 307, 342, 361, 386, 413, 434, 448, 473, 495, 504
.define END_CRED_TEXT "PADD WS", "GAME DESIGN AND PROGRAMMING", "SCHERMOBIANCO", "PLATFORMS", "PC  WEB  RASPBERRY PI", "MISTER FPGA", "COMMODORE 64", "MUSIC AND SOUND", "ORIGINAL SID MUSIC", "SID SOUND EFFECTS", "ANNOUNCER VOICES", "THE CHALLENGERS", "ARCADE   TITAN   HAMMER", "TWIST   BLASTER   RUSH", "AND GUARDIAN", "THIRD-PARTY WORKS", "PONG SCORE FONT  PWNZOR.AK", "MISTER FRAMEWORK  SORGELIG", "SID EMULATION  DAG LEM  A. MELNIKOV", "VEXRISCV  SPINALHDL", "MACROQUAD  FEDOR LOGACHEV", "GILRS  SDL GAMECONTROLLERDB", "PYTHON ARCADE  PIGPIO", "SPECIAL THANKS", "THE MISTER FPGA COMMUNITY", "THE COMMODORE 64 SCENE", "THANK YOU", "FOR PLAYING"
; fuochi d'artificio: tipi (anello, salice, palma, crisantemo, crepitio, croce che si divide)
FW_FRAMES = 3    ; frame per passo
FW_RISE = 45    ; frame del razzo
FW_SLOTS = 4
FW_MAX = 24
FW_KINDS = 6
FW_SPLIT_OFF = 95    ; velocità dopo la divisione (CROSSETTE)
FW_SHOW = 10
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
.define FW_VC 224, 208, 224, 208, 224, 208, 224, 208, 224, 208, 224, 208, 224, 208, 224, 208, 224, 208, 224, 208, 224, 208, 224, 208, 224, 208, 224, 208, 224, 208, 224, 224, 224, 224, 224, 224, 224, 192, 192, 192, 192, 192, 192, 192, 192, 224, 224, 224, 224, 224, 224, 224, 224, 224, 224, 224, 224, 224, 224, 192, 208, 224, 192, 208, 224, 192, 208, 224, 192, 208, 224, 192, 208, 224, 192, 208, 224, 192, 208, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 192, 224, 208, 224, 208, 208, 224, 208, 224, 224, 208, 224, 208, 208, 224, 208, 224
.define FW_S_STEP 0, 7, 14, 25, 37, 43, 54, 64, 71, 80, 255
.define FW_S_KIND 0, 1, 2, 3, 4, 5, 0, 1, 2, 3
.define FW_S_GX 18, 38, 38, 49, 14, 28, 58, 23, 43, 54
.define FW_S_GY 8, 15, 10, 24, 16, 8, 11, 9, 8, 16
.define FW_S_V0 1848, 1536, 1759, 1135, 1491, 1848, 1714, 1803, 1848, 1491
.define FW_S_ACC 41, 34, 39, 25, 33, 41, 38, 40, 41, 33
.define FW_S_COL 11, 10, 12, 13, 11, 14, 12, 10, 13, 15
