; Televisore: PAL (50 frame al secondo, la versione di sempre) o NTSC (60, con il simbolo NTSC:
; c64\build.ps1 -Ntsc, che prende anche i parametri del core a 60 Hz da gen\ntsc\params.inc). Un tick
; della logica per frame in tutti e due.
;
; Le soglie del lavoro nel frame sono "il budget meno quello che resta da fare": TV_CYC le porta in
; righe del raster dall'interrupt (TV_LCYC cicli utili per riga, caratteri e sprite tolti), come le
; conta frame_after. FR porta una durata data in frame a 50 Hz nei frame del televisore. Con il PAL
; i valori sono quelli di prima.
.ifdef NTSC
TV_HZ     = 60
TV_LINES  = 263                 ; righe del frame (6567R8)
TV_LINE   = 65                  ; cicli per riga
TV_BUDGET = 15500               ; cicli utili del frame (17.095 meno caratteri e sprite)
TV_LCYC   = 59
TV_CLOCK  = 1022727             ; Hz della CPU
.else
TV_HZ     = 50
TV_LINES  = 312
TV_LINE   = 63
TV_BUDGET = 18000               ; (19.656 meno caratteri e sprite: il budget del banco di prova)
TV_LCYC   = 58
TV_CLOCK  = 985248
.endif
TV_FRAME  = TV_LINE * TV_LINES  ; cicli di un frame

; Niente macro con argomenti (.define con parametri): ca65 prende nell'argomento anche il resto
; della riga (`2 * FR(10) + 1` darebbe 22). Si scrivono per esteso:
;   righe del raster quando mancano c cicli alla fine del budget: (TV_BUDGET - c) / TV_LCYC
;   n frame a 50 Hz nei frame del televisore: (n * TV_HZ + 25) / 50
