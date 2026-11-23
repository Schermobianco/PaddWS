; Aritmetica a virgola fissa Q16.16 su 32 bit, identica a rust/core/src/fixed.rs e rng.rs.
;
; I numeri sono a 32 bit in complemento a due, byte basso per primo. Le moltiplicazioni passano
; per il prodotto senza segno dei valori assoluti (i byte 0-6 dei 64) e troncano verso lo zero
; come `fixed::mul` (>> 16) e
; `fixed::mul_recip` (>> 24); il prodotto 8x8 usa le tabelle dei quarti di quadrato
; (a*b = f(a+b) - f(a-b), f(x) = x*x/4) e salta i byte nulli dei fattori.

; ------------------------------------------------------------------------------------ macro
;
; Gli operandi delle macro a 32 bit sono un indirizzo (`ball_x`), un indirizzo indicizzato tra
; graffe (`{pad_y,x}`, anche `{tab,y}`) o una costante tra graffe (`{#P_WIDTH}`).

; Istruzione `opc` sul byte `k` (0 = basso) dell'operando `arg`.
.macro op8 opc, arg, k
  .if .xmatch(.left(1, {arg}), #)
    opc #<((.right(.tcount({arg})-1, {arg})) >> (8*(k)))
  .elseif .tcount({arg}) >= 3 .and .match(.right(1, {arg}), x)
    opc .left(.tcount({arg})-2, {arg})+(k), x
  .elseif .tcount({arg}) >= 3 .and .match(.right(1, {arg}), y)
    opc .left(.tcount({arg})-2, {arg})+(k), y
  .else
    opc arg+(k)
  .endif
.endmacro

; dst = src
.macro mov32 dst, src
    .repeat 4, k
    op8 lda, {src}, k
    op8 sta, {dst}, k
    .endrepeat
.endmacro

; dst = a + b
.macro add32 dst, pa, pb
    clc
    .repeat 4, k
    op8 lda, {pa}, k
    op8 adc, {pb}, k
    op8 sta, {dst}, k
    .endrepeat
.endmacro

; dst = a - b
.macro sub32 dst, pa, pb
    sec
    .repeat 4, k
    op8 lda, {pa}, k
    op8 sbc, {pb}, k
    op8 sta, {dst}, k
    .endrepeat
.endmacro

; dst = -src
.macro neg32 dst, src
    sec
    .repeat 4, k
    lda #0
    op8 sbc, {src}, k
    op8 sta, {dst}, k
    .endrepeat
.endmacro

; dst = |src| (|i32::MIN| resta i32::MIN, come wrapping_abs); sul posto (dst = src) senza la copia
.macro abs32 dst, src
    .local pos, done
  .if .xmatch({dst}, {src})
    op8 lda, {src}, 3
    bpl done
    neg32 {dst}, {src}
  .else
    op8 lda, {src}, 3
    bpl pos
    neg32 {dst}, {src}
    jmp done
pos:
    mov32 {dst}, {src}
  .endif
done:
.endmacro

; confronto con segno: dopo la macro il bit 7 di A (e il flag N) vale 1 se a < b
.macro cmp32 pa, pb
    .local ok
    sec
    .repeat 4, k
    op8 lda, {pa}, k
    op8 sbc, {pb}, k
    .endrepeat
    bvc ok
    eor #$80
ok:
.endmacro

; salta a `target` se a < b (con segno); il salto è lungo
.macro blt32 pa, pb, target
    .local skip
    cmp32 {pa}, {pb}
    bpl skip
    jmp target
skip:
.endmacro

; salta a `target` se a >= b (con segno)
.macro bge32 pa, pb, target
    .local skip
    cmp32 {pa}, {pb}
    bmi skip
    jmp target
skip:
.endmacro

; salta a `target` se a == b
.macro beq32 pa, pb, target
    .local skip
    .repeat 4, k
    op8 lda, {pa}, k
    op8 cmp, {pb}, k
    bne skip
    .endrepeat
    jmp target
skip:
.endmacro

; A = 0 (e flag Z) se v è zero
.macro or32 v
    op8 lda, {v}, 0
    op8 ora, {v}, 1
    op8 ora, {v}, 2
    op8 ora, {v}, 3
.endmacro

; v = v >> 1 con segno
.macro asr32 v
    op8 lda, {v}, 3
    cmp #$80
    op8 ror, {v}, 3
    op8 ror, {v}, 2
    op8 ror, {v}, 1
    op8 ror, {v}, 0
.endmacro

; v = v << 1
.macro asl32 v
    op8 asl, {v}, 0
    op8 rol, {v}, 1
    op8 rol, {v}, 2
    op8 rol, {v}, 3
.endmacro

; v = v + 1
.macro inc32 v
    .local done
    op8 inc, {v}, 0
    bne done
    op8 inc, {v}, 1
    bne done
    op8 inc, {v}, 2
    bne done
    op8 inc, {v}, 3
done:
.endmacro

; dst = parte intera di src come Fx (fixed::int(fixed::floor(v))): azzera la parte frazionaria
.macro floor32 dst, src
    lda #0
    op8 sta, {dst}, 0
    op8 sta, {dst}, 1
    op8 lda, {src}, 2
    op8 sta, {dst}, 2
    op8 lda, {src}, 3
    op8 sta, {dst}, 3
.endmacro

; m_a = a * b / 2^16 (fixed::mul); con a = m_a niente copia
.macro mulq16 pa, pb
  .if .not .xmatch({pa}, m_a)
    mov32 m_a, {pa}
  .endif
    mov32 m_b, {pb}
    jsr mul_q16
.endmacro

; m_a = a * r / 2^24 (fixed::mul_recip); con a = m_a niente copia
.macro mulq24 pa, pr
  .if .not .xmatch({pa}, m_a)
    mov32 m_a, {pa}
  .endif
    mov32 m_b, {pr}
    jsr mul_q24
.endmacro

; eventi del byte alto (events + 1)
.macro event_hi ev
    lda events+1
    ora #ev
    sta events+1
.endmacro

; v (16 bit) = v - 1 se non è zero
.macro dec16_sat v
    .local done, lo
    op8 lda, {v}, 0
    op8 ora, {v}, 1
    beq done
    op8 lda, {v}, 0
    bne lo
    op8 dec, {v}, 1
lo:
    op8 dec, {v}, 0
done:
.endmacro

; ------------------------------------------------------------------------------------ dati

.segment "ZEROPAGE"
m_a:    .res 4          ; primo fattore (e risultato di mul_q16 / mul_q24)
m_b:    .res 4          ; secondo fattore (distrutto)
m_p:    .res 8 + 3      ; prodotto nei byte 0-6 (altri file usano tutti gli 11 byte come variabili)
m_sign: .res 1
m_t:    .res 1
m_lo:   .res 1
sq1_lo: .res 2          ; puntatori alle tabelle dei quadrati (il byte basso è il fattore)
sq1_hi: .res 2
sq2_lo: .res 2
sq2_hi: .res 2
rng:    .res 4          ; stato del generatore xorshift32 della partita
r_t:    .res 4

; tabelle dei quarti di quadrato, 512 voci ciascuna: f(x) = x*x/4 e f(x - 255); nella bitmap
; dell'attract (vedi math_step)
.segment "TABLES"
square1_lo: .res 512
square1_hi: .res 512
square2_lo: .res 512
square2_hi: .res 512

; tabelle degli shift di rng_next, nella RAM bassa
.segment "TABLES2"
shl5:       .res 256    ; (i << 5) & $FF
shr3:       .res 256    ; i >> 3

.segment "CODE"

; ------------------------------------------------------------------------------------ tabelle

.segment "BOOTCODE"           ; solo all'avvio (unpack.s)
; Prepara le tabelle e i puntatori. Da chiamare una volta all'avvio.
math_init:
    ; tabelle degli shift di rng_next
    ldx #0
:   txa
    lsr a
    lsr a
    lsr a
    sta shr3,x
    txa
    asl a
    asl a
    asl a
    asl a
    asl a
    sta shl5,x
    inx
    bne :-
    ; byte alti dei puntatori
    lda #>square1_lo
    sta sq1_lo+1
    lda #>square1_hi
    sta sq1_hi+1
    lda #>square2_lo
    sta sq2_lo+1
    lda #>square2_hi
    sta sq2_hi+1
    jsr math_invalidate
    jmp math_ensure
.segment "CODE"

; Le tabelle dei quadrati stanno nella bitmap dell'attract ($F000), che il titolo
; copre: math_invalidate le segna da rifare, math_step ne rifà un pezzo per frame fuori da quelle
; scene, math_ensure le finisce subito (prima di una partita).
.segment "BSS"
sq_x:       .res 2              ; prossima voce di f(x) (512: poi f(x - 255))
sq_acc:     .res 3              ; x * x
sq_odd:     .res 2              ; dispari da sommare
math_ready: .res 1              ; tabelle dei quadrati pronte
.segment "CODE"

.proc math_invalidate
    lda #0
    sta math_ready
    sta sq_x
    sta sq_x+1
    sta sq_acc
    sta sq_acc+1
    sta sq_acc+2
    sta sq_odd+1
    lda #1
    sta sq_odd
    rts
.endproc

.proc math_ensure
:   jsr math_step
    lda math_ready
    beq :-
    rts
.endproc

SQ_CHUNK = 64                   ; voci di f(x) per pezzo (divide 256)

.proc math_step
    lda math_ready
    beq :+
    rts
:   lda sq_x+1
    cmp #2
    bcs second
    ldx sq_x
    ldy #SQ_CHUNK
loop:
    ; f(x) = (x * x) >> 2: A basso, m_lo alto
    lda sq_acc+2
    lsr a
    sta m_t
    lda sq_acc+1
    ror a
    sta m_lo
    lda sq_acc
    ror a
    lsr m_t
    ror m_lo
    ror a
    pha
    lda sq_x+1
    bne hi_page
    pla
    sta square1_lo,x
    lda m_lo
    sta square1_hi,x
    jmp add
hi_page:
    pla
    sta square1_lo+256,x
    lda m_lo
    sta square1_hi+256,x
add:
    ; x * x += dispari; dispari += 2
    clc
    lda sq_acc
    adc sq_odd
    sta sq_acc
    lda sq_acc+1
    adc sq_odd+1
    sta sq_acc+1
    lda sq_acc+2
    adc #0
    sta sq_acc+2
    clc
    lda sq_odd
    adc #2
    sta sq_odd
    bcc :+
    inc sq_odd+1
:   inx
    bne :+
    inc sq_x+1
:   dey
    bne loop
    stx sq_x
    rts
second:
    ; f(x - 255) = f(|x - 255|): per x = 0..255 vale f(255 - x), per x = 256 + k vale f(k + 1). In
    ; due passi da 128 (circa 6.000 cicli l'uno: con la musica nel frame NTSC), da sq_x
    ldx sq_x
:   txa
    eor #$ff                    ; 255 - x
    tay
    lda square1_lo,y
    sta square2_lo,x
    lda square1_hi,y
    sta square2_hi,x
    lda square1_lo+1,x
    sta square2_lo+256,x
    lda square1_hi+1,x
    sta square2_hi+256,x
    inx
    beq ready
    cpx #$80
    bne :-
    stx sq_x                    ; metà: il resto al prossimo passo
    rts
ready:
    lda #1
    sta math_ready
    rts
.endproc

; ------------------------------------------------------------------------------------ prodotto

; Prodotto parziale P = m_b[i] * m_a[j] (puntatori sq* già impostati per m_b[i]) sommato in m_p
; dal byte i + j, con il riporto fino al byte 6. Entra ed esce con C = 0: le sottrazioni danno
; P - 1 (P >= 1, i byte nulli si saltano, quindi alla fine C = 1) e il riporto della prima somma
; rimette l'1. Il byte basso aspetta in X, l'alto in Y.
.macro umul_part i, j
    .local done, carry
    ldy m_a+j
    beq done
  .if i + j = 6
    ; solo il byte basso: il byte 7 non serve
    lda (sq1_lo),y
    sbc (sq2_lo),y
    sec
    adc m_p+6
    sta m_p+6
    clc
  .else
    lda (sq1_lo),y
    sbc (sq2_lo),y
    tax
    lda (sq1_hi),y
    sbc (sq2_hi),y
    tay
    txa
    adc m_p+i+j
    sta m_p+i+j
    tya
    adc m_p+i+j+1
    sta m_p+i+j+1
    .if i + j = 5
    clc                         ; il riporto nel byte 7 non serve
    .else
    bcc done
    .repeat 5 - (i + j), k
    inc m_p+i+j+2+k
      .if i + j + k < 4
    bne carry
      .endif
    .endrepeat
carry:
    clc
    .endif
  .endif
done:
.endmacro

; Come umul_part per la prima riga (i = 0): prima di lei nessuno ha scritto i byte 0-3 di m_p
; (il 4 è a zero), quindi l'alto si scrive senza somma (alto + riporto <= 255: nessun riporto
; oltre) e il basso del primo prodotto anche; un byte nullo di m_a scrive 0 al posto dell'alto.
.macro umul_part0 j
    .local done, do
    ldy m_a+j
  .if j = 3
    beq done
  .else
    bne do
    .if j = 0
    sty m_p
    .endif
    sty m_p+j+1
    beq done
  .endif
do:
    lda (sq1_lo),y
    sbc (sq2_lo),y
    tax
    lda (sq1_hi),y
    sbc (sq2_hi),y
    tay
    txa
  .if j = 0
    adc #0
  .else
    adc m_p+j
  .endif
    sta m_p+j
    tya
    adc #0
    sta m_p+j+1
done:
.endmacro

; Riga del prodotto per il byte i di m_b (saltata se è zero; la prima riga saltata azzera i byte
; 0-3). Le righe vanno sul fattore m_b, che nelle chiamate è più spesso una costante con pochi
; byte non nulli. Le righe 2 e 3 (parte intera dei fattori Q16.16 e Q8.24) con il byte 1 o 2
; passano da umul_small. `small` è l'etichetta di umul_small i.
.macro umul_row i, small
    .local next, row
    lda m_b+i
  .if i = 0
    bne row
    .repeat 4, k
    sta m_p+k
    .endrepeat
    jmp next
row:
  .elseif i = 3
    beq next
  .else
    jeq next
  .endif
    sta sq1_lo
    sta sq1_hi
    eor #$ff
  .if i = 3
    cmp #$fd                    ; 255 - m_b[i] >= 253: m_b[i] = 1 o 2; se no C = 0
    bcs small
  .elseif i = 2
    cmp #$fd
    jcs small
  .endif
    sta sq2_lo
    sta sq2_hi
    .repeat 4, j
  .if i = 0
    umul_part0 j
  .else
    umul_part i, j
  .endif
    .endrepeat
next:
.endmacro

; Riga i (2 o 3) con m_b[i] = 1 o 2 (A = 255 - m_b[i]): m_a sommato una o due volte dal byte i,
; senza tabelle, fino al byte 6. Esce con C = 0.
.macro umul_small i
    .local add, hi
    eor #$ff
    tax
    clc
add:
    .repeat 4, k
    lda m_a+k
    adc m_p+i+k
    sta m_p+i+k
    .endrepeat
  .if i = 2
    bcc hi
    inc m_p+6
hi:
  .endif
    clc
    dex
    bne add
.endmacro

; Prodotto del fattore impostato (puntatori sq*) per il byte in Y: A = byte basso, m_t = alto.
.macro mul8
    sec
    lda (sq1_lo),y
    sbc (sq2_lo),y
    sta m_lo
    lda (sq1_hi),y
    sbc (sq2_hi),y
    sta m_t
    lda m_lo
.endmacro

; A * Y senza segno: m_t = byte alto, A = byte basso.
umul8:
    sta sq1_lo
    sta sq1_hi
    eor #$ff
    sta sq2_lo
    sta sq2_hi
    mul8
    rts

; m_a = m_a * m_b / 2^16, troncato verso lo zero (fixed::mul). Distrugge m_b.
mul_q16:
    jsr abs_operands
    lda m_sign
    bmi :+
    mov32 m_a, {m_p+2}
    rts
:   neg32 m_a, {m_p+2}          ; -(|a * b| >> 16): troncato verso lo zero
    rts

; m_a = m_a * m_b / 2^24 con m_b reciproco Q8.24 (fixed::mul_recip). Distrugge m_b.
mul_q24:
    jsr abs_operands
    lda m_sign
    bmi :+
    mov32 m_a, {m_p+3}
    rts
:   neg32 m_a, {m_p+3}
    rts

; Prodotto con segno: valori assoluti di m_a e m_b, segno del risultato in m_sign, poi m_p =
; |m_a| * |m_b| (prosegue in umul32).
.proc abs_operands
    lda m_a+3
    bmi neg_a
    lda m_b+3                   ; a >= 0: il segno è quello di b
    sta m_sign
    bpl umul32
    bmi neg_b
neg_a:
    eor m_b+3
    sta m_sign
    neg32 m_a, m_a
    lda m_b+3
    bpl umul32
neg_b:
    neg32 m_b, m_b
    ; (prosegue in umul32)
.endproc

; m_p = m_a * m_b, senza segno, nei byte 0-6 (il byte 7 non si calcola: non serve a nessuno). m_a
; e m_b restano intatti. Tutto srotolato: indirizzi fissi in pagina zero, nessun ciclo.
.proc umul32
    lda #0                      ; i byte 0-3 li scrive la prima riga
    sta m_p+4
    sta m_p+5
    sta m_p+6
    clc
    umul_row 0, 0
    umul_row 1, 0
    umul_row 2, small2
row3:
    umul_row 3, small3
    rts
small3:
    umul_small 3
    rts
small2:
    umul_small 2
    jmp row3
.endproc

; ------------------------------------------------------------------------------------ generatore

; rng = xorshift32(rng): x ^= x << 13; x ^= x >> 17; x ^= x << 5 (Rng::next_u32)
;
; Uno shift a sinistra di 8k + 5 bit dà al byte j il valore (x[j-k] << 5) | (x[j-k-1] >> 3):
; con le tabelle shl5 e shr3 ogni byte costa una ventina di cicli. I byte si aggiornano dall'alto,
; così quelli letti sono ancora i vecchi, e Y resta su x[j-k-1], che serve subito al byte j - 1
; (`first` = 0: Y è già pronto).
.macro xor_shl5 j, k, first
    .if first
    ldy rng + j - k
    .endif
    lda shl5,y
    .if j - k - 1 >= 0
    ldy rng + j - k - 1
    ora shr3,y
    .endif
    eor rng + j
    sta rng + j
.endmacro

rng_next:
    ; x ^= x << 13 (k = 1)
    xor_shl5 3, 1, 1
    xor_shl5 2, 1, 0
    xor_shl5 1, 1, 0
    ; x ^= x >> 17
    lda rng+3
    lsr a
    tay
    lda rng+2
    ror a
    eor rng
    sta rng
    tya
    eor rng+1
    sta rng+1
    ; x ^= x << 5 (k = 0)
    xor_shl5 3, 0, 1
    xor_shl5 2, 0, 0
    xor_shl5 1, 0, 0
    xor_shl5 0, 0, 0
    rts

; A:X (A basso) = Rng::below(n) con n in m_b (16 bit): ((x >> 16) * n) >> 16. Avanza il generatore.
; Prodotto 16x16 dei byte x = rng+2, rng+3 per n, solo fino ai byte 2 e 3 che servono (byte 1 e
; 2 in m_p+1 e m_p+2, il 3 in m_p+3). Le sottrazioni partono da C = 1: i fattori nulli danno 0.
.proc rng_below
    jsr rng_next
    lda m_b
    sta sq1_lo
    sta sq1_hi
    eor #$ff
    sta sq2_lo
    sta sq2_hi
    ; x1 * n0: basso nel byte 1 (X), alto nel byte 2 (A)
    ldy rng+3
    sec
    lda (sq1_lo),y
    sbc (sq2_lo),y
    tax
    lda (sq1_hi),y
    sbc (sq2_hi),y
    ldy m_b+1
    bne wide
    ; n < 256: l'alto di x0 * n è al più n - 1, quindi se basso + n + 1 (C = 1) non riporta, il
    ; byte 2 è già l'alto di x1 * n
    tay
    txa
    adc m_b
    bcs exact
    tya
    ldx #0
    rts
exact:
    tya
wide:
    sta m_p+2
    stx m_p+1
    ; x0 * n0: solo l'alto, nel byte 1 (il basso è da solo nel byte 0: nessun riporto)
    ldy rng+2
    sec
    lda (sq1_lo),y
    sbc (sq2_lo),y
    lda (sq1_hi),y
    sbc (sq2_hi),y
    clc
    adc m_p+1
    sta m_p+1
    lda m_p+2
    adc #0                      ; (alto di x1 * n0) + 1 <= 255
    sta m_p+2
    ldx m_b+1
    bne wide2
    rts                         ; n < 256: X = 0 è il byte 3
wide2:
    stx sq1_lo
    stx sq1_hi
    txa
    eor #$ff
    sta sq2_lo
    sta sq2_hi
    ; x0 * n1: basso nel byte 1 (serve solo il riporto), alto nel byte 2
    ldy rng+2
    sec
    lda (sq1_lo),y
    sbc (sq2_lo),y
    tax
    lda (sq1_hi),y
    sbc (sq2_hi),y
    tay
    txa
    clc
    adc m_p+1
    tya
    adc m_p+2
    sta m_p+2
    lda #0
    rol a
    sta m_p+3
    ; x1 * n1: basso nel byte 2, alto nel byte 3
    ldy rng+3
    sec
    lda (sq1_lo),y
    sbc (sq2_lo),y
    tax
    lda (sq1_hi),y
    sbc (sq2_hi),y
    tay
    txa
    clc
    adc m_p+2
    sta m_p+2
    tya
    adc m_p+3
    tax
    lda m_p+2
    rts
.endproc
