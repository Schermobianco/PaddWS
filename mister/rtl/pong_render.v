// Disegno del campo pixel per pixel (RGB a 24 bit; il gioco è in bianco e nero): racchette, palla,
// aree boost, mezzeria (o la rete dell'avversario), alone e grigi del bullet time, lampo bianco, e gli
// effetti del campo della fine partita (mezzeria che si spegne, racchette che si accorciano, palla
// spenta). Le scritte (punteggi, crediti della demo, GAME OVER...) sono dello schermo a oggetti
// (ui_render, rust/mister-ui): quelle che stanno dentro il campo arrivano qui come pixel di classe C
// (`ui_c`, sotto palla e racchette, sopra mezzeria e alone), le altre le mette sopra pong_top.
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
    input  wire        field_off,       // fine partita con GAME OVER: il campo si spegne (con over_age)
    input  wire [7:0]  over_age,        // GAME OVER: frame dall'inizio (fermi a 255)
    input  wire        ball_accent,     // NEXT: palla del SUPER in volo nel colore di accento
    input  wire        ball_relief,     // NEXT: palla in rilievo (ombra portata, retro e fondo in ombra)
    input  wire        ball_right,      // verso della palla: l'ombra va dietro
    input  wire [1:0]  pad_hide,        // NEXT: racchetta disegnata da next_render (SUPER, TELEPORT, TWIST)
    input  wire [1:0]  pad_gray,        // NEXT: racchetta con un bonus armato (lampeggia) o rallentata dal BULLET
    input  wire        field_gray,      // NEXT: bullet time, palla e linea centrale grigie
    input  wire [1:0]  blur,            // NEXT: bullet time, profondità dell'alone in pixel (0 = niente)
    input  wire [1:0]  blur_pads,       // racchette con l'alone (non quella di chi ha il BULLET)
    input  wire [179:0] dash_off,       // NEXT: scostamento di ognuno dei 30 trattini della mezzeria
    // CHALLENGE contro la CPU: la rete dell'avversario (tipo di racchetta, 7 = quella di sempre), frame
    // per lo scorrimento del RUSH, vibrazione dopo un colpo dell'HAMMER (lato della scossa)
    input  wire [2:0]  net_kind,
    input  wire [3:0]  net_t,
    input  wire        net_shake,
    input  wire        net_shake_dir,
    // pixel dello schermo a oggetti di classe C (punteggi, crediti della demo) e il suo colore
    input  wire        ui_c,
    input  wire [23:0] ui_c_rgb,

    output reg  [23:0] rgb,
    output reg         bg,              // pixel di sfondo (nero, senza alone): ci va l'alone delle capsule
    output reg         ball             // pixel della palla: sta sopra alla scritta del bonus di NEXT
);

`include "pong_params.vh"

localparam signed [31:0] HALF_PX = 32'sd32768;
localparam integer W = P_WIDTH >>> 16;
localparam integer H = P_HEIGHT >>> 16;
localparam [23:0] WHITE = 24'hFFFFFF;
localparam [23:0] GRAY = 24'hB4B4B4;
localparam [23:0] BLACK = 24'h000000;
localparam [23:0] ACCENT = 24'hFFD225;            // colore di accento di NEXT, come in next_render
// alone del bullet time: grigi sempre più scuri a 1, 2 e 3 pixel dal bordo (anche in next_render)
localparam [23:0] HALO1 = 24'h6E6E6E, HALO2 = 24'h404040, HALO3 = 24'h1E1E1E;
// palla in rilievo di NEXT, come draw_relief_ball di next_ui.rs: ombra portata grigio scuro e i
// colori della palla in ombra (per 212, 214, 224 / 255)
localparam [23:0] SHADOW = 24'h30303A, WHITE_SH = 24'hD4D6E0, ACCENT_SH = 24'hD4B021, GRAY_SH = 24'h9697A2;

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

reg       flash_q, ball_accent_q, field_gray_q, relief_q, right_q;
reg [1:0] blur_q, blur_pads_q;

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
        flash_q <= flash;
        ball_accent_q <= ball_accent;
        relief_q <= ball_relief;
        right_q <= ball_right;
        field_gray_q <= field_gray;
        blur_q <= blur;
        blur_pads_q <= blur_pads;
    end
end

// ------------------------------------------------- fine partita: il campo si spegne
// Come draw_game_over_anim di rust/game/src/attract.rs con GAME OVER: i trattini della mezzeria si
// spengono dall'alto (48 frame), poi palla e racchette se ne vanno (12); il resto (scritte, chiusura
// del televisore) lo disegna lo schermo a oggetti.
reg        ov_off = 1'b0;
reg [7:0]  net_cut = 8'd0;              // righe della mezzeria già spente, dall'alto
reg [5:0]  pad_cut = 6'd0;              // righe tolte a ciascun capo delle racchette
reg        field_ball_off = 1'b0;
reg [5:0]  pc;
always @(posedge clk) begin
    if (snapshot) begin
        ov_off <= field_off;
        net_cut <= (over_age >= 8'd48) ? 8'd240 : {over_age[5:0], 2'b0} + over_age;
        pc = over_age[5:0] - 6'd48;
        pad_cut <= (over_age < 8'd48) ? 6'd0 : (over_age >= 8'd60) ? 6'd40 : {pc[4:0], 1'b0} + pc;
        field_ball_off <= over_age >= 8'd48;
    end
end

// ------------------------------------------------- reti degli avversari

// Come draw_net di rust/game/src/scenes.rs: la rete di sempre (trattini di 4 righe ogni 8, larghi 2) o,
// nella CHALLENGE contro la CPU, quella del tipo di racchetta dell'avversario. rx è la colonna dal
// centro (le due colonne della rete di sempre sono -1 e 0), solo confronti con costanti:
// - ARCADE: quadratini vuoti 6x6 ogni 16 righe;
// - TWIST: trattini inclinati di 4 righe ogni 8, che si piegano verso la palla quando passa (fino a 4
//   pixel, meno lontano da lei: net_bend in pixel per riga, calcolato a ogni frame);
// - HAMMER: rete doppia (colonne -4..-2 e 1..3), trattini di 10 righe ogni 16, che vibra di un pixel
//   (trattini alterni da parti opposte) dopo un colpo dell'HAMMER;
// - TITAN: trattini lunghi 20 righe ogni 32;
// - BLASTER: due file di puntini 2x2 sfalsati, ogni 8 righe;
// - RUSH: trattini di 8 righe ogni 16 che scorrono verso il basso, con 2 righe gialle scure sopra;
// - GUARDIAN: mattoni 4x4 sfalsati, due per riga, ogni 8 righe, e gli angoli del campo gialli.
localparam [2:0] NK_ARCADE = 3'd0, NK_TITAN = 3'd1, NK_HAMMER = 3'd2, NK_TWIST = 3'd3, NK_BLASTER = 3'd4,
                 NK_RUSH = 3'd5, NK_GUARDIAN = 3'd6;
localparam [23:0] RUSH_TRAIL = 24'h5C4C0D;
reg        bend_on, bend_dir;              // TWIST: la palla è vicina alla rete, e va a destra
reg signed [11:0] bend_row;                // ... riga del suo centro
always @(posedge clk) begin
    if (snapshot) begin
        bend_on <= (c0[4] + c1[4]) >= W - 60 && (c0[4] + c1[4]) < W + 60;
        bend_dir <= ball_x[31:16] > last_bx;
        bend_row <= (r0[4] + r1[4]) >>> 1;
    end
end
reg [15:0] last_bx;
always @(posedge clk) if (snapshot) last_bx <= ball_x[31:16];

// rete: 0 niente, 1 bianca (grigia nel bullet time), 2 gialla scura (RUSH), 3 gialla (angoli del GUARDIAN)
function [1:0] net_px(input signed [11:0] rx, input [7:0] yy);
    reg [4:0] q;
    reg signed [11:0] d, b, s;
    begin
        net_px = 2'd0;
        case (net_kind)
            NK_ARCADE: begin
                q = {1'b0, yy[3:0]};
                if (q >= 2 && q < 8 && rx >= -3 && rx <= 2 && (q == 2 || q == 7 || rx == -3 || rx == 2)) net_px = 2'd1;
            end
            NK_TWIST: begin
                d = $signed({4'd0, yy}) - bend_row;
                if (d < 0) d = -d;
                b = !bend_on ? 12'sd0 : (d < 10) ? 12'sd4 : (d < 20) ? 12'sd3 : (d < 30) ? 12'sd2 : (d < 40) ? 12'sd1 : 12'sd0;
                s = $signed({10'd0, yy[2:1]}) - 12'sd2 + (bend_dir ? b : -b);
                if (!yy[2] && (rx == s || rx == s + 1)) net_px = 2'd1;
            end
            NK_HAMMER: begin
                s = !net_shake ? 12'sd0 : (yy[4] ^ net_shake_dir) ? 12'sd1 : -12'sd1;
                if (yy[3:0] < 4'd10 && ((rx - s >= -4 && rx - s <= -2) || (rx - s >= 1 && rx - s <= 3))) net_px = 2'd1;
            end
            NK_TITAN: begin
                q = yy[4:0];
                if (q >= 2 && q < 22 && (rx == -1 || rx == 0)) net_px = 2'd1;
            end
            NK_BLASTER: begin
                if (yy[2:1] == 2'd0 && (rx == -3 || rx == -2)) net_px = 2'd1;
                if (yy[2:1] == 2'd2 && (rx == 1 || rx == 2)) net_px = 2'd1;
            end
            NK_RUSH: begin
                q = {1'b0, yy[3:0] - net_t};
                if (rx == -1 || rx == 0) net_px = (q < 8) ? 2'd1 : (q >= 14) ? 2'd2 : 2'd0;
            end
            NK_GUARDIAN: begin
                s = yy[3] ? -12'sd3 : 12'sd0;
                if (yy[2:0] < 3'd4 && ((rx - s >= -3 && rx - s <= 0) || (rx - s >= 2 && rx - s <= 5))) net_px = 2'd1;
            end
            default: if (!yy[2] && (rx == -1 || rx == 0)) net_px = 2'd1;
        endcase
    end
endfunction
// GUARDIAN: angoli del campo gialli, 14 pixel per lato, spessi 2
wire corner_px = net_kind == NK_GUARDIAN &&
                 ((hc < 14 || hc >= W - 14) && (vc < 2 || vc >= H - 2) ||
                  (hc < 2 || hc >= W - 2) && (vc < 14 || vc >= H - 14));

// ------------------------------------------------------------------ pixel

wire signed [11:0] x = {3'd0, hc};
wire signed [5:0]  line_off = dash_off[6 * vc[7:3] +: 6];
wire signed [11:0] y = {3'd0, vc};

function in_rect(input integer i, input signed [11:0] px, input signed [11:0] py);
    in_rect = on[i] && px >= c0[i] && px < c1[i] && py >= r0[i] && py <= r1[i];
endfunction

// linea centrale (net_px: quella di sempre o quella dell'avversario; in NEXT la COMETA ne sposta
// i trattini di lato); a fine partita, con GAME OVER, si spegne dall'alto
reg        line_px, net_acc;
reg [1:0]  net_q;
always @(*) begin
    net_q = net_px(x - (W / 2 + line_off), y[7:0]);
    line_px = net_q == 2'd1 && !(ov_off && y < $signed({4'd0, net_cut}));
    net_acc = (net_q == 2'd2 || corner_px) && !(ov_off && y < $signed({4'd0, net_cut}));
end

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

// GAME OVER: racchette (e aree boost) che si accorciano di pad_cut righe per capo, palla spenta
function pad_in(input integer i, input signed [11:0] px, input signed [11:0] py);
    pad_in = in_rect(i, px, py) &&
             !(ov_off && (py < r0[i] + $signed({6'd0, pad_cut}) || py > r1[i] - $signed({6'd0, pad_cut})));
endfunction
wire ball_in = in_rect(4, x, y) && !(ov_off && field_ball_off);
// rilievo: colonna del retro e fila di fondo della palla in ombra; ombra portata 1 pixel in basso e 1
// dietro (fuori dalla palla)
wire ball_shade = relief_q && (y == r1[4] || x == (right_q ? c0[4] : c1[4] - 12'sd1));
wire ball_shadow = relief_q && !(ov_off && field_ball_off) &&
                   in_rect(4, right_q ? x + 12'sd1 : x - 12'sd1, y - 12'sd1);

always @(posedge clk) begin
    if (flash_q)
        rgb <= WHITE;
    else if (ball_in)
        rgb <= ball_shade ? (ball_accent_q ? ACCENT_SH : field_gray_q ? GRAY_SH : WHITE_SH)
                          : (ball_accent_q ? ACCENT : field_gray_q ? GRAY : WHITE);
    else if (pad_in(2, x, y) || pad_in(3, x, y))
        rgb <= GRAY;
    else if ((pad_in(0, x, y) && !pad_hide[0] && pad_gray[0]) || (pad_in(1, x, y) && !pad_hide[1] && pad_gray[1]))
        rgb <= GRAY;
    else if ((pad_in(0, x, y) && !pad_hide[0]) || (pad_in(1, x, y) && !pad_hide[1]))
        rgb <= WHITE;
    else if (ui_c)
        rgb <= ui_c_rgb;
    else if (ball_shadow)
        rgb <= SHADOW;
    else if (line_px)
        rgb <= field_gray_q ? GRAY : WHITE;
    else if (net_acc)
        rgb <= corner_px ? ACCENT : RUSH_TRAIL;
    else if (halo_q != 2'd0)
        rgb <= (halo_q == 2'd1) ? HALO1 : (halo_q == 2'd2) ? HALO2 : HALO3;
    else
        rgb <= BLACK;
    bg <= !flash_q && !ball_in && !pad_in(2, x, y) && !pad_in(3, x, y) && !(pad_in(0, x, y) && !pad_hide[0]) &&
          !(pad_in(1, x, y) && !pad_hide[1]) && !ui_c && !ball_shadow && !line_px && !net_acc && halo_q == 2'd0;
    ball <= !flash_q && ball_in;
end

endmodule
