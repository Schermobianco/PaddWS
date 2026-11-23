; Televisore: PAL (50 frame al secondo, la versione di sempre) o NTSC (60, con il simbolo NTSC:
; c64\build.ps1 -Ntsc, che prende anche i parametri del core a 60 Hz da gen\ntsc\params.inc). Un tick
; della logica per frame in tutti e due.
;
; Le soglie del lavoro nel frame sono "il budget meno quello che resta da fare", in cicli veri
; dall'interrupt della riga 250 (quelli che il VIC-II ruba per caratteri e sprite compresi, come li
; conta il banco di prova, tarato su VICE): il budget TV_BUDGET è il 90% del frame, e TV_LCYC, i
; cicli di una riga, li porta in righe del raster, come le conta frame_after. Quello che resta da
; fare va quindi scritto con circa il 10% in più dei cicli del 6502 (le righe dei caratteri).
.ifdef NTSC
TV_HZ     = 60
TV_LINES  = 263                 ; righe del frame (6567R8)
TV_LINE   = 65                  ; cicli per riga
TV_BUDGET = 15400               ; il 90% del frame (17.095 cicli)
TV_LCYC   = TV_LINE
TV_UCYC   = 59                  ; cicli del 6502 per riga con lo schermo acceso (caratteri tolti)
TV_CLOCK  = 1022727             ; Hz della CPU
.else
TV_HZ     = 50
TV_LINES  = 312
TV_LINE   = 63
TV_BUDGET = 17700               ; il 90% del frame (19.656 cicli)
TV_LCYC   = TV_LINE
TV_UCYC   = 58
TV_CLOCK  = 985248
.endif
TV_FRAME  = TV_LINE * TV_LINES  ; cicli di un frame

; Niente macro con argomenti (.define con parametri): ca65 prende nell'argomento anche il resto
; della riga (`2 * FR(10) + 1` darebbe 22). Si scrivono per esteso:
;   righe del raster quando mancano c cicli alla fine del budget: (TV_BUDGET - c) / TV_LCYC
;   n frame a 50 Hz nei frame del televisore: (n * TV_HZ + 25) / 50
