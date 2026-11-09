; Voci di CHALLENGE: indirizzi comuni al programma (challenge.s, play.s, sid.s) e ai file voce
; (voice.s), che contengono i campioni del nome di un avversario e il suo tema.
;
; Il file si carica a VOICE_BASE, nella bitmap dell'attract: in CHALLENGE lì ci sono le immagini
; degli effetti e delle racchette di NEXT ($E000-$E93F), che si rifanno a ogni inizio partita
; (hud_reset), cioè dopo la presentazione. Il file dell'avversario del primo livello porta anche la
; parte che resta per tutta la scala: da VOICE_RES il player e "READY?", e "GO!" con gli NMI del
; player, che il file copia a VOICE_GO. Gli altri file finiscono prima di VOICE_RES e usano quel
; player. I file stanno nella cartuccia (src/ef.inc, VOICE_BANK0), uno per banco.

VOICE_BASE  = $E000
VOICE_TICK  = VOICE_BASE        ; jsr a ogni frame della presentazione (dal primo)
VOICE_STOP  = VOICE_BASE + 3    ; jsr quando la presentazione finisce (anche prima della voce)
VOICE_END   = $F000             ; i file devono finire prima delle tabelle dei quadrati

; Parte che resta (dal file del primo livello): sopra le immagini degli effetti, fino a VOICE_END.
; Il file del primo livello ci arriva quasi esatto (voice.s lo controlla): se cambiano le sue voci
; o il player, VOICE_RES si sposta (dove finisce la parte che si copia, più qualche byte).
VOICE_RES   = $EB20
VOICE_HUSH  = VOICE_RES         ; jsr: ferma subito la voce (A, X e Y restano); solo con il vettore
                                ; dell'NMI nel player (bit 7 di $FFFB)
VOICE_SAY   = VOICE_RES + 6     ; jsr: dice i campioni descritti a X:Y (inizio, fine)
VOICE_GO    = $FA01             ; "GO!" e gli NMI del player, dopo il tema (THEME_BASE, $F800-$FA00)
VOICE_GO_SRC = $E00B            ; nel file del primo livello: quello che il file copia a VOICE_GO

; "YOU WIN!" (banco WIN_BANK della cartuccia, tools/make_crt.py): 16 pagine da WIN_RUN, cioè il
; player e READY come da VOICE_RES (in CHALLENGE già lì), i campioni a WIN_SAMPLES (al posto
; delle tabelle dei quadrati e del tema) con il descrittore per VOICE_SAY a WIN_DESC, e la pagina
; degli NMI del player da $FA00. Per il GAME OVER contro la CPU e il finale di CHALLENGE. Nelle
; WIN_PAGES pagine dopo, nello stesso banco, la stessa immagine con "PERFECT!" al posto di YOU WIN
; (WIN_PERFECT), per il GAME OVER vinto da un giocatore con l'avversario a 0 punti.
WIN_RUN     = $EB00
WIN_SAMPLES = $F000
WIN_DESC    = $F9FC
WIN_PAGES   = 16
WIN_PERFECT = $80 + WIN_PAGES   ; prima pagina dell'immagine di PERFECT nella ROML ($8000 YOU WIN)

; Conto alla rovescia (play.s): jsr VOICE_COUNT a ogni frame con A = frame rimasti (da COUNT_FRAMES
; a 1). È un RTS (start_game) finché il file del primo livello non ci mette il salto al suo conto:
; così fuori da CHALLENGE, e prima del file del primo livello, non succede nulla.
COUNT_FRAMES = 3 * 50           ; conto alla rovescia di 3 secondi prima della prima battuta
VOICE_COUNT = $FFC0             ; 3 byte nella RAM sotto il KERNAL, dopo i caratteri del BULLET

; Volume del SID scelto nel menu (VOLUME, 0-15; sid_vol in video.s): finita la voce, il SID torna
; a questo volume invece che a 15.
VOICE_VOL = $FFF3

VOICE_PAGES = 16                ; pagine copiate dalla cartuccia: da VOICE_BASE a VOICE_END
