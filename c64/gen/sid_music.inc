; Generato da tools/gen_sid_music.py: non modificare a mano.
SID_FREQ_BASE = 0
SID_INSTR_BASE = 192
SID_SONGS = 6
SID_EFFECTS = 5
SID_ROM_SIZE = 831
SID_SONG_TITLE = 1
SID_SONG_INTRO = 2
SID_SONG_CLEAR = 3
SID_SONG_CONTINUE = 4
SID_SONG_GAME_OVER = 5
SID_SONG_CHAMPION = 6
SID_FX_WALL = 1
SID_FX_HIT = 2
SID_FX_BOOST = 3
SID_FX_SCORE = 4
SID_FX_COIN = 5
; tema dell'avversario di CHALLENGE (dal file voce): una traccia per pagina da THEME_BASE
SID_SONG_THEME = 7
THEME_BASE = $F800
; inizio delle tracce nella ROM: per canzone (da 1) le voci 0-2, poi gli effetti (da 1)
.define SID_SONG_STARTS 320, 450, 529, 555, 563, 573, 578, 586, 600, 605, 639, 657, 660, 668, 686, 689, 755, 791
.define SID_FX_STARTS 805, 809, 813, 819, 825
; finale di CHALLENGE (ending.bin, le tre tracce di fila): offset delle tracce
SID_SONG_ENDING = 8
SID_ENDING_LEAD = 514
SID_ENDING_ARP = 939
SID_ENDING_SIZE = 1595
; canzone di OMEGA (omegaK_V.bin, una sezione per forma, come i temi): nel player è la canzone del tema
SID_OMEGA_SECTIONS = 7
