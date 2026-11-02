; Aritmetica a virgola fissa Q16.16 su 32 bit, identica a rust/core/src/fixed.rs e rng.rs.
;
; I numeri sono a 32 bit in complemento a due, byte basso per primo. Le moltiplicazioni passano
; per un prodotto senza segno a 64 bit e troncano verso lo zero come `fixed::mul` (>> 16) e
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

; m_a = a * b / 2^16 (fixed::mul)
.macro mulq16 pa, pb
    mov32 m_a, {pa}
    mov32 m_b, {pb}
    jsr mul_q16
.endmacro

; m_a = a * r / 2^24 (fixed::mul_recip)
.macro mulq24 pa, pr
    mov32 m_a, {pa}
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
m_p:    .res 8 + 3      ; prodotto a 64 bit (3 byte in più per il riporto)
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

; Le tabelle dei quadrati stanno nella bitmap dell'attract ($F000), che strisce, logo e titolo
; coprono: math_invalidate le segna da rifare, math_step ne rifà un pezzo per frame fuori da quelle
; scene, math_ensure le finisce subito (prima di una partita o della demo).
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
    ; f(x - 255) = f(|x - 255|): per x = 0..255 vale f(255 - x), per x = 256 + k vale f(k + 1)
    ldx #0
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
    bne :-
    lda #1
    sta math_ready
    rts
.endproc

; ------------------------------------------------------------------------------------ prodotto

; Prodotto parziale m_a[i] * m_b[j] (puntatori sq* già impostati per m_a[i]) sommato in m_p dal
; byte i + j, con il riporto. Il byte basso del prodotto aspetta in X, l'alto in Y.
.macro umul_part i, j
    .local done
    ldy m_b+j
    beq done
    sec
    lda (sq1_lo),y
    sbc (sq2_lo),y
    tax
    lda (sq1_hi),y
    sbc (sq2_hi),y
    tay
    txa
    clc
    adc m_p+i+j
    sta m_p+i+j
    tya
    adc m_p+i+j+1
    sta m_p+i+j+1
    .if i + j + 2 <= 7
    bcc done
    .repeat 6 - (i + j), k
    inc m_p+i+j+2+k
    bne done
    .endrepeat
    .endif
done:
.endmacro

; Riga del prodotto per il byte i di m_a (saltata se è zero).
.macro umul_row i
    .local next
    lda m_a+i
    jeq next
    sta sq1_lo
    sta sq1_hi
    eor #$ff
    sta sq2_lo
    sta sq2_hi
    .repeat 4, j
    umul_part i, j
    .endrepeat
next:
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

; m_p (64 bit) = m_a * m_b, senza segno. m_a e m_b restano intatti. Tutto srotolato: indirizzi
; fissi in pagina zero, nessun ciclo.
umul32:
    lda #0
    .repeat 8, k
    sta m_p+k
    .endrepeat
    .repeat 4, i
    umul_row i
    .endrepeat
    rts

; A * Y senza segno: m_t = byte alto, A = byte basso.
umul8:
    sta sq1_lo
    sta sq1_hi
    eor #$ff
    sta sq2_lo
    sta sq2_hi
    mul8
    rts

; Prepara m_a e m_b per un prodotto con segno: valori assoluti e segno del risultato in m_sign.
abs_operands:
    lda m_a+3
    eor m_b+3
    sta m_sign
    lda m_a+3
    bpl :+
    neg32 m_a, m_a
:   lda m_b+3
    bpl :+
    neg32 m_b, m_b
:   rts

; m_a = m_a * m_b / 2^16, troncato verso lo zero (fixed::mul). Distrugge m_b.
mul_q16:
    jsr abs_operands
    jsr umul32
    lda m_p+2
    sta m_a
    lda m_p+3
    sta m_a+1
    lda m_p+4
    sta m_a+2
    lda m_p+5
    sta m_a+3
    jmp apply_sign

; m_a = m_a * m_b / 2^24 con m_b reciproco Q8.24 (fixed::mul_recip). Distrugge m_b.
mul_q24:
    jsr abs_operands
    jsr umul32
    lda m_p+3
    sta m_a
    lda m_p+4
    sta m_a+1
    lda m_p+5
    sta m_a+2
    lda m_p+6
    sta m_a+3
apply_sign:
    lda m_sign
    bpl :+
    neg32 m_a, m_a
:   rts

; ------------------------------------------------------------------------------------ generatore

; rng = xorshift32(rng): x ^= x << 13; x ^= x >> 17; x ^= x << 5 (Rng::next_u32)
;
; Uno shift a sinistra di 8k + 5 bit dà al byte j il valore (x[j-k-1] >> 3) | (x[j-k] << 5):
; con le tabelle shr3 e shl5 ogni byte costa una ventina di cicli. I byte si aggiornano dall'alto,
; così quelli letti sono ancora i vecchi.
.macro xor_shl5 j, k
    .if j - k - 1 >= 0
    ldy rng + j - k - 1
    lda shr3,y
    ldy rng + j - k
    ora shl5,y
    .else
    ldy rng + j - k
    lda shl5,y
    .endif
    eor rng + j
    sta rng + j
.endmacro

rng_next:
    ; x ^= x << 13 (k = 1)
    xor_shl5 3, 1
    xor_shl5 2, 1
    xor_shl5 1, 1
    ; x ^= x >> 17
    lda rng+3
    lsr a
    sta r_t
    lda rng+2
    ror a
    eor rng
    sta rng
    lda r_t
    eor rng+1
    sta rng+1
    ; x ^= x << 5 (k = 0)
    xor_shl5 3, 0
    xor_shl5 2, 0
    xor_shl5 1, 0
    xor_shl5 0, 0
    rts

; A:X (A basso) = Rng::below(n) con n in m_b (16 bit): ((x >> 16) * n) >> 16. Avanza il generatore.
rng_below:
    jsr rng_next
    lda rng+2
    sta m_a
    lda rng+3
    sta m_a+1
    lda #0
    sta m_a+2
    sta m_a+3
    sta m_b+2
    sta m_b+3
    jsr umul32
    lda m_p+2
    ldx m_p+3
    rts
