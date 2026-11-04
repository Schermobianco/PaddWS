// Disegno del campo pixel per pixel (RGB a 24 bit; il gioco è in bianco e nero),
// con le scritte sovrapposte della demo e del GAME OVER.
// Con `upright` basso punteggi e scritte guardano i giocatori seduti ai lati (tavolo),
// con `upright` alto sono dritti, per un cabinato o un monitor normale.
//
// Una volta per frame (`snapshot`, durante il vblank, a logica ferma) i rettangoli in
// coordinate del core (Q16.16, y verso l'alto) diventano limiti di colonna e di riga
// dello schermo (y verso il basso): durante il frame restano solo confronti a 12 bit.
// Un pixel è acceso se il suo centro cade nel rettangolo, come nel gioco desktop.

`timescale 1ns / 1ps

module pong_render (
    input  wire        clk,
    input  wire        snapshot,
    input  wire [8:0]  hc,
    input  wire [8:0]  vc,

    input  wire        two,
    input  wire        evo,
    input  wire        flash,
    input  wire signed [31:0] ball_x,
    input  wire signed [31:0] ball_y,
    input  wire signed [31:0] ball_r,
    input  wire        ball_visible,
    input  wire signed [31:0] pad0_x,
    input  wire signed [31:0] pad0_y,
    input  wire signed [31:0] pad1_x,
    input  wire signed [31:0] pad1_y,
    input  wire signed [31:0] pad0_h,          // altezza delle racchette (NEXT: dal tipo; muro in singolo)
    input  wire signed [31:0] pad1_h,
    input  wire signed [31:0] pad0_boost_h,
    input  wire signed [31:0] pad1_boost_h,
    input  wire [15:0] score0,
    input  wire [15:0] score1,
    input  wire [15:0] best,
    input  wire [1:0]  lives,           // palle rimaste in singolo
    input  wire        show_lives,
    input  wire [1:0]  overlay,         // 0 nessuna, 1 demo (crediti e scritta), 2 GAME OVER
    input  wire [1:0]  demo_mode,       // modalità della demo: 0 CLASSIC, 1 EVO, 2 NEXT, 3 CHALLENGE
    input  wire [2:0]  winner,          // sotto GAME OVER: 0 nessuno, 1 P1 WINS, 2 P2 WINS, 3 YOU WIN, 4 CPU WINS
    input  wire        win_solo,        // chi ha vinto da solo, al posto di GAME OVER (YOU WIN, livello perso)
    input  wire        winner_accent,   // NEXT: chi ha vinto nel colore di accento
    input  wire        ball_accent,     // NEXT: palla del SUPER in volo nel colore di accento
    input  wire        free_play,
    input  wire [3:0]  credits,
    input  wire [5:0]  blink,           // frame % 60
    input  wire        upright,         // scritte dritte invece che verso i giocatori
    input  wire [1:0]  countdown,       // cifra del conto alla rovescia, 0 = nessuna
    input  wire [1:0]  pad_hide,        // NEXT: racchetta disegnata da next_render (SUPER, TELEPORT, TWIST)
    input  wire [1:0]  pad_gray,        // NEXT: racchetta con un bonus armato (lampeggia) o rallentata dal BULLET
    input  wire        field_gray,      // NEXT: bullet time, palla, linea centrale e punteggi grigi
    input  wire [1:0]  blur,            // NEXT: bullet time, profondità dell'alone in pixel (0 = niente)
    input  wire [1:0]  blur_pads,       // racchette con l'alone (non quella di chi ha il BULLET)
    input  wire [179:0] dash_off,       // NEXT: scostamento di ognuno dei 30 trattini della mezzeria

    output reg  [23:0] rgb,
    output reg         top,             // scritta sovrapposta: sopra anche alle aggiunte di NEXT
    output reg         bg               // pixel di sfondo (nero, senza alone): ci va l'alone delle capsule
);

`include "pong_params.vh"
`include "pong_fonts.vh"
`include "pong_attract.vh"

localparam signed [31:0] HALF_PX = 32'sd32768;
localparam integer W = P_WIDTH >>> 16;
localparam integer H = P_HEIGHT >>> 16;
localparam [23:0] WHITE = 24'hFFFFFF;
localparam [23:0] GRAY = 24'hB4B4B4;
localparam [23:0] BLACK = 24'h000000;
localparam [23:0] ACCENT = 24'hFFD225;            // colore di accento di NEXT, come in next_render
// alone del bullet time: grigi sempre più scuri a 1, 2 e 3 pixel dal bordo (anche in next_render)
localparam [23:0] HALO1 = 24'h6E6E6E, HALO2 = 24'h404040, HALO3 = 24'h1E1E1E;

// Punteggi rivolti ai giocatori seduti ai lati: centri come nel gioco desktop
localparam integer OX = 60 * W / 800;
localparam integer OY = 60 * H / 480;
localparam integer BEST_OFFSET = (55 * P_SCALE + 32768) / 65536;   // 55 * scala, arrotondato
localparam integer LS_X0 = W / 2 - OX - SCORE_H / 2;                // punteggio sinistro (orario)
localparam integer LS_Y0 = H - OY - SCORE_W;
localparam integer RS_X0 = W / 2 + OX - SCORE_H / 2;                // punteggio destro (antiorario)
localparam integer RS_Y0 = OY - SCORE_W;
localparam integer BT_X0 = W / 2 - OX - BEST_OFFSET - TEXT_H / 2;   // "TOP NN" del singolo (orario)
localparam integer BT_Y0 = H - OY - 3 * TEXT_W;
localparam integer BALLS_OFFSET = (85 * P_SCALE + 32768) / 65536;  // 85 * scala, arrotondato
localparam integer BL_X0 = W / 2 - OX - BALLS_OFFSET - TEXT_H / 2;  // "BALLS n" del singolo (orario)
localparam integer BL_Y0 = H - OY - (BALLS_W + TEXT_W) / 2;

// Punteggi dritti: in alto, ai lati della linea centrale; record e palle del singolo a destra
localparam integer UL_X0 = W / 2 - 2 * OX - SCORE_W;                // punteggio sinistro
localparam integer UR_X0 = W / 2 + 2 * OX - SCORE_W;                // punteggio destro
localparam integer U_Y0 = 8;
localparam integer UT_X0 = W / 2 + 2 * OX - 3 * TEXT_W;             // "TOP NN"
localparam integer UT_Y0 = 10;
localparam integer UB_X0 = W / 2 + 2 * OX - (BALLS_W + TEXT_W) / 2; // "BALLS n"
localparam integer UB_Y0 = UT_Y0 + TEXT_H + 4;

// scritte sovrapposte (scala 2): centrate, oppure una per metà campo ruotata verso il giocatore
localparam integer IC_W2 = 2 * INSERT_COIN_W, PS_W2 = 2 * PRESS_START_W, GO_W2 = 2 * GAME_OVER_W;
localparam integer GO_BOX_X = (W - GO_W2 - 12) / 2;
// (centri a metà tra la racchetta avanzata, a P_PAD_FWD_POS dal bordo, e la mezzeria)
localparam integer FWD_X = P_PAD_FWD_POS >>> 16;
localparam integer ROT_CX_L = (FWD_X + W / 2) / 2 + 8, ROT_CX_R = W - ROT_CX_L;
// distanza tra GAME OVER e la riga di chi ha vinto, come nella scritta dritta
localparam integer WIN_STEP = AT_WINNER_Y - AT_GAME_OVER_Y;
// conto alla rovescia verso i giocatori: in due una cifra per parte accanto alla mezzeria,
// in singolo una sola cifra al centro dello schermo
localparam integer CD_CX_L2 = W / 2 - SCORE_H - 6, CD_CX_R2 = W / 2 + SCORE_H + 6;
// le cifre del punteggio hanno l'inchiostro nelle colonne 0-10 della cella da 22: a scala 2
// metà larghezza dell'inchiostro, per centrarle
localparam integer CD_INK = 11;

// --------------------------------------------------------- limiti dei rettangoli

// colonna minima (inclusa) e massima (esclusa) dei pixel con il centro in [lo, hi)
function signed [11:0] col_of(input signed [31:0] v);
    reg signed [31:0] t;
    begin
        t = (v - HALF_PX + 32'sd65535) >>> 16;
        col_of = t[11:0];
    end
endfunction

// righe dello schermo: centro del pixel r a y = H - r - 0.5
function signed [11:0] row_first(input signed [31:0] top);
    reg signed [31:0] t;
    begin
        t = ((P_HEIGHT - HALF_PX - top) >>> 16) + 32'sd1;
        row_first = t[11:0];
    end
endfunction

function signed [11:0] row_last(input signed [31:0] bottom);
    reg signed [31:0] t;
    begin
        t = (P_HEIGHT - HALF_PX - bottom) >>> 16;
        row_last = t[11:0];
    end
endfunction

// indice dei rettangoli: 0/1 racchette, 2/3 aree boost, 4 palla
reg signed [11:0] c0 [0:4];
reg signed [11:0] c1 [0:4];
reg signed [11:0] r0 [0:4];
reg signed [11:0] r1 [0:4];
reg               on [0:4];
reg signed [11:0] r2 [0:4];             // r1 + 1 (fine esclusiva, per l'alone)

reg [3:0] ls_t, ls_o, rs_t, rs_o, bt_t, bt_o;
reg       show_rs, show_best, flash_q, ball_accent_q, field_gray_q;
reg [1:0] blur_q, blur_pads_q;

function [3:0] tens(input [15:0] v);
    reg [15:0] c;
    reg [17:0] m;
    begin
        c = (v > 16'd99) ? 16'd99 : v;
        m = c[7:0] * 10'd205;
        tens = m[14:11];          // c * 205 / 2048 = c / 10 per c < 100
    end
endfunction

function [3:0] ones(input [15:0] v);
    reg [15:0] c;
    begin
        c = (v > 16'd99) ? 16'd99 : v;
        ones = c[7:0] - tens(v) * 4'd10;
    end
endfunction

wire signed [31:0] pad_hw = P_PAD_WIDTH >>> 1;
wire signed [31:0] pad1_hh = pad1_h >>> 1;
wire signed [31:0] pad0_hh = pad0_h >>> 1;

always @(posedge clk) begin
    if (snapshot) begin
        c0[0] <= col_of(pad0_x - pad_hw);  c1[0] <= col_of(pad0_x + pad_hw);
        r0[0] <= row_first(pad0_y + pad0_hh); r1[0] <= row_last(pad0_y - pad0_hh);
        r2[0] <= row_last(pad0_y - pad0_hh) + 12'sd1;
        on[0] <= 1'b1;
        c0[1] <= col_of(pad1_x - pad_hw);  c1[1] <= col_of(pad1_x + pad_hw);
        r0[1] <= row_first(pad1_y + pad1_hh); r1[1] <= row_last(pad1_y - pad1_hh);
        r2[1] <= row_last(pad1_y - pad1_hh) + 12'sd1;
        on[1] <= 1'b1;
        c0[2] <= col_of(pad0_x - pad_hw);  c1[2] <= col_of(pad0_x + pad_hw);
        r0[2] <= row_first(pad0_y + (pad0_boost_h >>> 1)); r1[2] <= row_last(pad0_y - (pad0_boost_h >>> 1));
        on[2] <= evo;
        c0[3] <= col_of(pad1_x - pad_hw);  c1[3] <= col_of(pad1_x + pad_hw);
        r0[3] <= row_first(pad1_y + (pad1_boost_h >>> 1)); r1[3] <= row_last(pad1_y - (pad1_boost_h >>> 1));
        on[3] <= evo;
        c0[4] <= col_of(ball_x - ball_r);  c1[4] <= col_of(ball_x + ball_r);
        r0[4] <= row_first(ball_y + ball_r); r1[4] <= row_last(ball_y - ball_r);
        r2[4] <= row_last(ball_y - ball_r) + 12'sd1;
        on[4] <= ball_visible;
        ls_t <= tens(score0);  ls_o <= ones(score0);
        rs_t <= tens(score1);  rs_o <= ones(score1);
        bt_t <= tens(best);    bt_o <= ones(best);
        show_rs <= two;
        show_best <= !two;
        flash_q <= flash;
        ball_accent_q <= ball_accent;
        field_gray_q <= field_gray;
        blur_q <= blur;
        blur_pads_q <= blur_pads;
    end
end

// ------------------------------------------------------------------ pixel

wire signed [11:0] x = {3'd0, hc};
wire signed [5:0]  line_off = dash_off[6 * vc[7:3] +: 6];
wire signed [11:0] y = {3'd0, vc};
// demo: nella parte spenta del lampeggio il riquadro mostra il nome della modalità; in NEXT e
// CHALLENGE i crediti vanno in basso, in alto ci sono le riserve
wire               show_mode = blink >= AT_BLINK_ON;
wire signed [11:0] credit_y = demo_mode[1] ? H - 6 - TEXT_H : 12'sd6;

function in_rect(input integer i, input signed [11:0] px, input signed [11:0] py);
    in_rect = on[i] && px >= c0[i] && px < c1[i] && py >= r0[i] && py <= r1[i];
endfunction

// Scritta a scala 2 lunga `len` pixel, centrata in (cx, H/2) e ruotata verso il giocatore
// sinistro (orario, si legge dall'alto) o destro (antiorario): {dentro, colonna, riga} nel testo
function [20:0] rot_coord(input right, input signed [11:0] px, input signed [11:0] py,
                          input signed [11:0] cx, input signed [11:0] len);
    reg signed [11:0] dx, dy, along;
    reg [9:0] u, v;
    begin
        dx = px - (cx - TEXT_H);
        dy = py - ((H - len) >>> 1);
        along = right ? len - 12'sd1 - dy : dy;
        u = along[10:1];
        v = right ? dx[10:1] : TEXT_H - 1 - dx[10:1];
        rot_coord = {dx >= 0 && dx < 2 * TEXT_H && dy >= 0 && dy < len, u, v};
    end
endfunction

// chi ha vinto: larghezza e pixel acceso della scritta
function [5:0] winner_w(input [2:0] w);
    case (w)
        3'd1: winner_w = P1_WINS_W;
        3'd2: winner_w = P2_WINS_W;
        3'd3: winner_w = YOU_WIN_W;
        3'd4: winner_w = CPU_WINS_W;
        default: winner_w = 6'd0;
    endcase
endfunction
function winner_lit(input [2:0] w, input [9:0] dx, input [9:0] dy);
    case (w)
        3'd1: winner_lit = p1_wins_lit(dx, dy);
        3'd2: winner_lit = p2_wins_lit(dx, dy);
        3'd3: winner_lit = you_win_lit(dx, dy);
        3'd4: winner_lit = cpu_wins_lit(dx, dy);
        default: winner_lit = 1'b0;
    endcase
endfunction

// nome della modalità della demo (scala 1)
function [7:0] mode_w(input [1:0] m);
    case (m)
        2'd0: mode_w = MODE_CLASSIC_W;
        2'd1: mode_w = MODE_EVO_W;
        2'd2: mode_w = MODE_NEXT_W;
        default: mode_w = MODE_CHALLENGE_W;
    endcase
endfunction
function mode_lit(input [1:0] m, input [9:0] dx, input [9:0] dy);
    case (m)
        2'd0: mode_lit = mode_classic_lit(dx, dy);
        2'd1: mode_lit = mode_evo_lit(dx, dy);
        2'd2: mode_lit = mode_next_lit(dx, dy);
        default: mode_lit = mode_challenge_lit(dx, dy);
    endcase
endfunction

// riquadro nero attorno a una scritta ruotata
function rot_box(input signed [11:0] px, input signed [11:0] py, input signed [11:0] cx, input signed [11:0] len);
    rot_box = px >= cx - TEXT_H - 5 && px < cx + TEXT_H + 5 &&
              py >= ((H - len) >>> 1) - 6 && py < ((H - len) >>> 1) + len + 6;
endfunction

// testo ruotato in senso orario (si legge dall'alto in basso) o antiorario
reg        ls_px, rs_px, bt_px, bl_px, line_px;
reg        ul_px, ur_px, ut_px, ub_px;
reg        credit_px, label_px, label_box, go_px, go_box;
reg        label_rot_px, label_rot_box, go_rot_px, go_rot_box, cd_px, cd_box;
reg [20:0] wl, wr;
reg        win_px, win_rot_px;
reg signed [11:0] win_w2;
reg [11:0] cd_cx;
reg [20:0] lc, rc;
reg [9:0]  label_w;
reg [4:0]  drow;
reg [11:0] dx, dy, along;
reg [3:0]  ch;
reg [4:0]  gx;
reg [21:0] srow;
reg [4:0]  trow;

always @(*) begin
    // valori di default: nessun latch
    ch = 4'd0;
    gx = 5'd0;
    srow = 22'd0;
    trow = 5'd0;

    // punteggio sinistro, orario: la cima delle cifre guarda verso destra
    ls_px = 1'b0;
    dx = x - LS_X0;
    dy = y - LS_Y0;
    if (x >= LS_X0 && x < LS_X0 + SCORE_H && y >= LS_Y0 && y < LS_Y0 + 2 * SCORE_W) begin
        ch = (dy >= SCORE_W) ? ls_o : ls_t;
        gx = (dy >= SCORE_W) ? dy - SCORE_W : dy;
        srow = score_glyph(ch, SCORE_H - 1 - dx);
        ls_px = srow[SCORE_W - 1 - gx];
    end

    // punteggio destro, antiorario: si legge dal basso in alto, cima verso sinistra
    rs_px = 1'b0;
    dx = x - RS_X0;
    along = RS_Y0 + 2 * SCORE_W - 1 - y;
    if (show_rs && x >= RS_X0 && x < RS_X0 + SCORE_H && y >= RS_Y0 && y < RS_Y0 + 2 * SCORE_W) begin
        ch = (along >= SCORE_W) ? rs_o : rs_t;
        gx = (along >= SCORE_W) ? along - SCORE_W : along;
        srow = score_glyph(ch, dx);
        rs_px = srow[SCORE_W - 1 - gx];
    end

    // "TOP NN" del giocatore singolo, orario
    bt_px = 1'b0;
    dx = x - BT_X0;
    dy = y - BT_Y0;
    if (show_best && x >= BT_X0 && x < BT_X0 + TEXT_H && y >= BT_Y0 && y < BT_Y0 + 6 * TEXT_W) begin
        along = (dy * 12'd13) >> 6;                    // dy / 5 per dy < 30
        case (along[2:0])
            3'd0: ch = TEXT_CH_T;
            3'd1: ch = TEXT_CH_O;
            3'd2: ch = TEXT_CH_P;
            3'd3: ch = TEXT_CH_SPACE;
            3'd4: ch = bt_t;
            default: ch = bt_o;
        endcase
        gx = dy - along * TEXT_W;
        trow = text_glyph(ch, TEXT_H - 1 - dx);
        bt_px = trow[TEXT_W - 1 - gx];
    end

    // "BALLS n" del giocatore singolo, orario come il record
    bl_px = 1'b0;
    dx = x - BL_X0;
    dy = y - BL_Y0;
    drow = 5'd0;
    if (show_lives && x >= BL_X0 && x < BL_X0 + TEXT_H && y >= BL_Y0 && y < BL_Y0 + BALLS_W + TEXT_W) begin
        if (dy < BALLS_W)
            bl_px = balls_lit(dy, TEXT_H - 1 - dx);
        else begin
            drow = text_glyph({2'd0, lives}, TEXT_H - 1 - dx);
            bl_px = drow[TEXT_W - 1 - (dy - BALLS_W)];
        end
    end

    // punteggi dritti
    ul_px = 1'b0;
    dx = x - UL_X0;
    dy = y - U_Y0;
    if (x >= UL_X0 && x < UL_X0 + 2 * SCORE_W && y >= U_Y0 && y < U_Y0 + SCORE_H) begin
        ch = (dx >= SCORE_W) ? ls_o : ls_t;
        gx = (dx >= SCORE_W) ? dx - SCORE_W : dx;
        srow = score_glyph(ch, dy);
        ul_px = srow[SCORE_W - 1 - gx];
    end
    ur_px = 1'b0;
    dx = x - UR_X0;
    if (show_rs && x >= UR_X0 && x < UR_X0 + 2 * SCORE_W && y >= U_Y0 && y < U_Y0 + SCORE_H) begin
        ch = (dx >= SCORE_W) ? rs_o : rs_t;
        gx = (dx >= SCORE_W) ? dx - SCORE_W : dx;
        srow = score_glyph(ch, dy);
        ur_px = srow[SCORE_W - 1 - gx];
    end
    ut_px = 1'b0;
    dx = x - UT_X0;
    dy = y - UT_Y0;
    if (show_best && x >= UT_X0 && x < UT_X0 + 6 * TEXT_W && y >= UT_Y0 && y < UT_Y0 + TEXT_H) begin
        along = (dx * 12'd13) >> 6;                    // dx / 5 per dx < 30
        case (along[2:0])
            3'd0: ch = TEXT_CH_T;
            3'd1: ch = TEXT_CH_O;
            3'd2: ch = TEXT_CH_P;
            3'd3: ch = TEXT_CH_SPACE;
            3'd4: ch = bt_t;
            default: ch = bt_o;
        endcase
        gx = dx - along * TEXT_W;
        trow = text_glyph(ch, dy);
        ut_px = trow[TEXT_W - 1 - gx];
    end
    ub_px = 1'b0;
    dx = x - UB_X0;
    dy = y - UB_Y0;
    if (show_lives && x >= UB_X0 && x < UB_X0 + BALLS_W + TEXT_W && y >= UB_Y0 && y < UB_Y0 + TEXT_H) begin
        if (dx < BALLS_W)
            ub_px = balls_lit(dx, dy);
        else begin
            drow = text_glyph({2'd0, lives}, dy);
            ub_px = drow[TEXT_W - 1 - (dx - BALLS_W)];
        end
    end

    // linea centrale: trattini di 4 pixel ogni 8, larga 2 (in NEXT la COMETA li sposta di lato)
    line_px = (x == W / 2 - 1 + line_off || x == W / 2 + line_off) && (y[2] == 1'b0);

    // demo: "CREDIT n" (o "FREE PLAY") in alto a sinistra (in basso in NEXT e CHALLENGE, dove in
    // alto ci sono le riserve) e al centro la scritta lampeggiante, alternata al nome della modalità
    trow = text_glyph(credits, y - credit_y);
    if (free_play)
        credit_px = free_play_lit(x - 8, y - credit_y);
    else
        credit_px = credit_lit(x - 8, y - credit_y) ||
                    (x >= 8 + CREDIT_W && x < 8 + CREDIT_W + TEXT_W && y >= credit_y && y < credit_y + TEXT_H &&
                     trow[TEXT_W - 1 - (x - 8 - CREDIT_W)]);
    label_w = show_mode ? 2 * mode_w(demo_mode) : (!free_play && credits == 4'd0) ? IC_W2 : PS_W2;
    label_box = x >= (W - label_w - 12) / 2 && x < (W - label_w - 12) / 2 + label_w + 12 &&
                y >= AT_DEMO_LABEL_Y - 4 && y < AT_DEMO_LABEL_Y + 20;
    label_px = show_mode
        ? mode_lit(demo_mode, (x - (W - label_w) / 2) >> 1, (y - AT_DEMO_LABEL_Y) >> 1)
        : (!free_play && credits == 4'd0)
        ? insert_coin_lit((x - (W - IC_W2) / 2) >> 1, (y - AT_DEMO_LABEL_Y) >> 1)
        : press_start_lit((x - (W - PS_W2) / 2) >> 1, (y - AT_DEMO_LABEL_Y) >> 1);

    // la stessa scritta ruotata, una per giocatore
    lc = rot_coord(1'b0, x, y, ROT_CX_L, label_w);
    rc = rot_coord(1'b1, x, y, ROT_CX_R, label_w);
    label_rot_box = rot_box(x, y, ROT_CX_L, label_w) || rot_box(x, y, ROT_CX_R, label_w);
    label_rot_px = show_mode
        ? (lc[20] && mode_lit(demo_mode, lc[19:10], lc[9:0])) || (rc[20] && mode_lit(demo_mode, rc[19:10], rc[9:0]))
        : (!free_play && credits == 4'd0)
        ? (lc[20] && insert_coin_lit(lc[19:10], lc[9:0])) || (rc[20] && insert_coin_lit(rc[19:10], rc[9:0]))
        : (lc[20] && press_start_lit(lc[19:10], lc[9:0])) || (rc[20] && press_start_lit(rc[19:10], rc[9:0]));

    // conto alla rovescia: cifra del punteggio a scala 2 su un riquadro nero, dritta al centro
    // oppure una per giocatore ruotata verso di lui (orario a sinistra, antiorario a destra)
    cd_px = 1'b0;
    cd_box = 1'b0;
    cd_cx = W / 2;
    if (countdown != 2'd0 && upright) begin
        cd_box = x >= W / 2 - SCORE_W - 6 && x < W / 2 + SCORE_W + 6 && y >= H / 2 - SCORE_H - 6 && y < H / 2 + SCORE_H + 6;
        if (x >= W / 2 - CD_INK && x < W / 2 - CD_INK + 2 * SCORE_W && y >= H / 2 - SCORE_H && y < H / 2 + SCORE_H) begin
            dx = x - (W / 2 - CD_INK);
            dy = y - (H / 2 - SCORE_H);
            srow = score_glyph({2'd0, countdown}, dy[5:1]);
            cd_px = srow[SCORE_W - 1 - dx[5:1]];
        end
    end else if (countdown != 2'd0) begin
        cd_cx = show_rs ? CD_CX_L2 : W / 2;
        // in singolo solo la cifra rivolta al giocatore di sinistra
        cd_box = (x >= cd_cx - SCORE_H - 6 && x < cd_cx + SCORE_H + 6 ||
                  show_rs && x >= CD_CX_R2 - SCORE_H - 6 && x < CD_CX_R2 + SCORE_H + 6) &&
                 y >= H / 2 - SCORE_W - 6 && y < H / 2 + SCORE_W + 6;
        // le colonne della cifra diventano righe dello schermo: si centra l'inchiostro su H/2
        if (x >= cd_cx - SCORE_H && x < cd_cx + SCORE_H &&
            y >= H / 2 - CD_INK && y < H / 2 - CD_INK + 2 * SCORE_W) begin
            dx = x - (cd_cx - SCORE_H);
            dy = y - (H / 2 - CD_INK);
            srow = score_glyph({2'd0, countdown}, SCORE_H - 1 - dx[5:1]);
            cd_px = srow[SCORE_W - 1 - dy[5:1]];
        end else if (show_rs && x >= CD_CX_R2 - SCORE_H && x < CD_CX_R2 + SCORE_H &&
                     y >= H / 2 + CD_INK - 2 * SCORE_W && y < H / 2 + CD_INK) begin
            dx = x - (CD_CX_R2 - SCORE_H);
            along = H / 2 + CD_INK - 1 - y;
            srow = score_glyph({2'd0, countdown}, dx[5:1]);
            cd_px = srow[SCORE_W - 1 - along[5:1]];
        end
    end

    // GAME OVER su un riquadro nero, dritto o una volta per giocatore
    go_box = x >= GO_BOX_X && x < GO_BOX_X + GO_W2 + 12 && y >= AT_GAME_OVER_Y - 5 && y < AT_GAME_OVER_Y + 19;
    go_px = game_over_lit((x - (W - GO_W2) / 2) >> 1, (y - AT_GAME_OVER_Y) >> 1);
    lc = rot_coord(1'b0, x, y, ROT_CX_L, GO_W2);
    rc = rot_coord(1'b1, x, y, ROT_CX_R, GO_W2);
    go_rot_box = rot_box(x, y, ROT_CX_L, GO_W2) || (show_rs && rot_box(x, y, ROT_CX_R, GO_W2));   // singolo: solo a sinistra
    go_rot_px = (lc[20] && game_over_lit(lc[19:10], lc[9:0])) || (show_rs && rc[20] && game_over_lit(rc[19:10], rc[9:0]));
    // chi ha vinto, una riga sotto GAME OVER; ruotata, la riga sotto è quella verso il giocatore
    win_w2 = 2 * winner_w(winner);
    win_px = 1'b0;
    win_rot_px = 1'b0;
    if (win_solo && winner != 3'd0) begin
        // solo chi ha vinto, nella riga di GAME OVER e nel suo colore, su un riquadro della sua
        // misura: YOU WIN contro la CPU, CPU WINS a un livello perso della CHALLENGE (il GAME OVER
        // viene dopo, se il continue scade)
        go_box = x >= (W - win_w2 - 12) / 2 && x < (W + win_w2 + 12) / 2 && y >= AT_GAME_OVER_Y - 5 && y < AT_GAME_OVER_Y + 19;
        go_px = 1'b0;
        win_px = winner_lit(winner, (x - ((W - win_w2) >>> 1)) >> 1, (y - AT_GAME_OVER_Y) >> 1);
        wl = rot_coord(1'b0, x, y, ROT_CX_L, win_w2);
        wr = rot_coord(1'b1, x, y, ROT_CX_R, win_w2);
        go_rot_box = rot_box(x, y, ROT_CX_L, win_w2) || (show_rs && rot_box(x, y, ROT_CX_R, win_w2));
        go_rot_px = 1'b0;
        win_rot_px = (wl[20] && winner_lit(winner, wl[19:10], wl[9:0])) ||
                     (show_rs && wr[20] && winner_lit(winner, wr[19:10], wr[9:0]));
    end else if (winner != 3'd0) begin
        go_box = x >= GO_BOX_X && x < GO_BOX_X + GO_W2 + 12 && y >= AT_GAME_OVER_Y - 5 && y < AT_WINNER_Y + 19;
        win_px = winner_lit(winner, (x - ((W - win_w2) >>> 1)) >> 1, (y - AT_WINNER_Y) >> 1);
        wl = rot_coord(1'b0, x, y, ROT_CX_L - WIN_STEP, win_w2);
        wr = rot_coord(1'b1, x, y, ROT_CX_R + WIN_STEP, win_w2);
        go_rot_box = go_rot_box || rot_box(x, y, ROT_CX_L - WIN_STEP, GO_W2) ||
                     (show_rs && rot_box(x, y, ROT_CX_R + WIN_STEP, GO_W2));
        win_rot_px = (wl[20] && winner_lit(winner, wl[19:10], wl[9:0])) ||
                     (show_rs && wr[20] && winner_lit(winner, wr[19:10], wr[9:0]));
    end else begin
        wl = 21'd0;
        wr = 21'd0;
    end
end

wire text_px = upright ? (ul_px || ur_px || ut_px || ub_px) : (ls_px || rs_px || bt_px || bl_px);

// ------------------------------------------------- alone del bullet time

// Bordi morbidi al posto di uno sfocato vero (non c'è un framebuffer): attorno a palla, racchetta
// avversaria e linea centrale un alone grigio che scurisce con la distanza (fino a `blur` pixel),
// distanza = scarto in x + scarto in y (angoli smussati). Solo sottrazioni e confronti; il livello
// si registra e si usa un ciclo dopo, dentro lo stesso pixel (ogni pixel dura 3 cicli di clk).

// scarto di p dall'intervallo [lo, hi): 0 dentro, 1-3 vicino, 4 oltre
function [2:0] gap_of(input signed [11:0] p, input signed [11:0] lo, input signed [11:0] hi);
    reg signed [11:0] a, b;
    begin
        a = p - lo;
        b = p - hi;
        if (a[11])
            gap_of = (a[11:2] == 10'h3FF && a[1:0] != 2'd0) ? 3'd4 - {1'b0, a[1:0]} : 3'd4;
        else if (!b[11])
            gap_of = (b[11:2] == 10'd0 && b[1:0] != 2'd3) ? {1'b0, b[1:0]} + 3'd1 : 3'd4;
        else
            gap_of = 3'd0;
    end
endfunction

// distanza dal rettangolo i (15 = nessun alone: spento, o il pixel è dentro)
function [3:0] rect_gap(input integer i, input signed [11:0] px, input signed [11:0] py);
    reg [3:0] d;
    begin
        d = {1'b0, gap_of(px, c0[i], c1[i])} + {1'b0, gap_of(py, r0[i], r2[i])};
        rect_gap = (!on[i] || d == 4'd0) ? 4'd15 : d;
    end
endfunction

function [3:0] min4(input [3:0] a, input [3:0] b);
    min4 = (a < b) ? a : b;
endfunction

reg [3:0]  hg_ball, hg_p0, hg_p1, hg_line, hg;
reg [2:0]  lgx, lgy;
reg signed [11:0] lv;
reg [1:0]  halo_q = 2'd0;
always @(*) begin
    hg_ball = rect_gap(4, x, y);
    hg_p0 = blur_pads_q[0] ? rect_gap(0, x, y) : 4'd15;
    hg_p1 = blur_pads_q[1] ? rect_gap(1, x, y) : 4'd15;
    // linea centrale: colonne W/2-1+off e W/2+off, trattini nelle righe con y[2] = 0
    lv = x - (W / 2 + line_off);
    if (!lv[11]) lgx = (lv == 12'sd0) ? 3'd0 : (lv[11:2] == 10'd0) ? {1'b0, lv[1:0]} : 3'd4;
    else         lgx = (lv == -12'sd1) ? 3'd0 : (lv[11:2] == 10'h3FF) ? {1'b0, ~lv[1:0]} : 3'd4;
    lgy = !y[2] ? 3'd0 : (y[1:0] == 2'd0 || y[1:0] == 2'd3) ? 3'd1 : 3'd2;
    hg_line = ({1'b0, lgx} + {1'b0, lgy} == 4'd0) ? 4'd15 : {1'b0, lgx} + {1'b0, lgy};
    hg = min4(min4(hg_ball, hg_line), min4(hg_p0, hg_p1));
end
always @(posedge clk)
    halo_q <= (blur_q != 2'd0 && hg <= {2'd0, blur_q}) ? hg[1:0] : 2'd0;

always @(posedge clk) begin
    top <= cd_box || (overlay == 2'd2 && (upright ? go_box : go_rot_box)) ||
           (overlay == 2'd1 && (upright ? label_box : label_rot_box));
    if (cd_box)
        rgb <= cd_px ? WHITE : BLACK;
    else if (overlay == 2'd2 && (upright ? go_box : go_rot_box))
        rgb <= (upright ? go_px : go_rot_px) ? WHITE :
               (upright ? win_px : win_rot_px) ? (winner_accent ? ACCENT : WHITE) : BLACK;
    else if (overlay == 2'd1 && (upright ? label_box : label_rot_box))
        rgb <= (upright ? label_px : label_rot_px) ? WHITE : BLACK;
    else if (flash_q)
        rgb <= WHITE;
    else if (in_rect(4, x, y))
        rgb <= ball_accent_q ? ACCENT : field_gray_q ? GRAY : WHITE;
    else if (in_rect(2, x, y) || in_rect(3, x, y))
        rgb <= GRAY;
    else if ((in_rect(0, x, y) && !pad_hide[0] && pad_gray[0]) || (in_rect(1, x, y) && !pad_hide[1] && pad_gray[1]))
        rgb <= GRAY;
    else if ((in_rect(0, x, y) && !pad_hide[0]) || (in_rect(1, x, y) && !pad_hide[1]) || (overlay == 2'd1 && credit_px))
        rgb <= WHITE;
    else if (text_px || line_px)
        rgb <= field_gray_q ? GRAY : WHITE;
    else if (halo_q != 2'd0)
        rgb <= (halo_q == 2'd1) ? HALO1 : (halo_q == 2'd2) ? HALO2 : HALO3;
    else
        rgb <= BLACK;
    bg <= !cd_box && !(overlay == 2'd2 && (upright ? go_box : go_rot_box)) &&
          !(overlay == 2'd1 && (upright ? label_box : label_rot_box)) && !flash_q && !in_rect(4, x, y) &&
          !in_rect(2, x, y) && !in_rect(3, x, y) && !(in_rect(0, x, y) && !pad_hide[0]) &&
          !(in_rect(1, x, y) && !pad_hide[1]) && !(overlay == 2'd1 && credit_px) && !text_px && !line_px &&
          halo_q == 2'd0;
end

endmodule
