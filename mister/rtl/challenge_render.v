// Schermate della modalità CHALLENGE (come rust/game/src/challenge_ui.rs): presentazione
// dell'avversario, livello superato, continue, iniziali, classifica, nuovo sfidante, e in partita i
// punti arcade in basso dalla parte dell'avversario. Scritte fisse da tools/gen_challenge_assets.py; numeri e iniziali con un font a
// celle: per ogni pixel si sceglie al più una cella, poi un solo accesso al font.

`timescale 1ns / 1ps

module challenge_render (
    input  wire        clk,
    input  wire [9:0]  hc,
    input  wire [9:0]  vc,
    input  wire [2:0]  screen,            // 0 niente, 1 presentazione, 2 livello superato, 3 continue,
                                          // 4 iniziali, 5 classifica, 6 punti in partita, 7 nuovo sfidante
    input  wire        side,              // il giocatore è a destra: punti in partita in basso a sinistra
    input  wire        join_prompt,       // presentazione: uno sfidante può entrare dal lato libero
    input  wire [2:0]  level,             // livello in corso (0-6)
    input  wire [2:0]  kind,              // racchetta dell'avversario
    input  wire [8:0]  loadout,           // bonus dell'avversario (3 bit ciascuno)
    input  wire [27:0] score_bcd,         // punti arcade, 7 cifre
    input  wire [27:0] hi_bcd,            // primo della classifica
    input  wire        perfect,           // livello vinto senza punti dell'avversario
    input  wire        coin_prompt,       // INSERT COIN invece di PRESS START
    input  wire [5:0]  blink,             // frame % 60
    input  wire [3:0]  cont_digit,        // secondi del continue
    input  wire [5:0]  cont_sub,          // frame dentro il secondo del continue (0-59)
    input  wire        cont_over,         // continue scaduto: GAME OVER al posto della schermata
    input  wire [17:0] name,              // iniziali scelte (codici del font, 6 bit ciascuno)
    input  wire [1:0]  name_pos,          // lettera in corso
    input  wire [5:0]  letter,            // codice della lettera sotto il cursore
    input  wire [179:0] table_names,      // classifica: 10 x 3 codici
    input  wire [279:0] table_bcd,        // 10 x 7 cifre
    input  wire [39:0] table_levels,      // 10 x livello (8 = scala finita)
    input  wire [3:0]  highlight,         // posto appena inserito (15 = nessuno)
    input  wire [3:0]  mult,              // moltiplicatore dello scambio
    input  wire [7:0]  intro_age,         // presentazione: frame dall'inizio (fermi a 255)
    output reg  [23:0] rgb,
    output reg         opaque
);

`include "pong_params.vh"
`include "pong_next.vh"
`include "pong_challenge.vh"
`include "pong_attract.vh"

localparam integer W = P_WIDTH >>> 16;
localparam [23:0] WHITE = 24'hFFFFFF, GRAY = 24'hB4B4B4, BLACK = 24'h000000, ACCENT = 24'hFFD225;
localparam [5:0] G_SPACE = 6'd36, G_PLUS = 6'd37, G_DOT = 6'd38, G_X = 6'd39, G_L = 6'd21;
localparam integer C = CH_CELL;
// presentazione: nome della racchetta, capsule dei bonus (lato 13 come nel gioco PC, l'icona 9x9
// con un pixel di margine), riga FIRST TO n centrata con una o due cifre
localparam integer INTRO_KIND_Y = 114, INTRO_CAP = 13, INTRO_CAP_Y = 154, INTRO_FIRST_Y = 190;
localparam integer FIRST_X1 = (W - (CH_FIRST_W + 2 + C)) / 2, FIRST_X2 = (W - (CH_FIRST_W + 2 + 2 * C)) / 2;
// punti in partita: in basso, dalla parte dell'avversario (a destra da HUD_R, a sinistra speculari)
localparam integer HUD_R = 196, HUD_SPAN = 74 + 2 * C, HUD_L = W - HUD_R - HUD_SPAN;
// nuovo sfidante: banda rossa con le due righe a scala 4
localparam integer NEW_BAND_Y = 58, NEW_BAND_H = 104, NEW_Y1 = 70, NEW_Y2 = 116;
localparam [23:0] BAND = 24'h8C1414;
// invito allo sfidante, in alto al centro del lato libero: "P2 PRESS START" o "INSERT COIN"
localparam integer JOIN_Y = 2, JOIN_W = 2 * C + 4 + CH_PRESS_W;
localparam integer JOIN_XL = W / 4 - JOIN_W / 2, JOIN_XR = 3 * W / 4 - JOIN_W / 2;
localparam integer COIN_XL = W / 4 - CH_COIN_W / 2, COIN_XR = 3 * W / 4 - CH_COIN_W / 2;
localparam [5:0] G_P = 6'd25;
// classifica: colonne di posizione, iniziali, punti (7 cifre) e livello ("ALL", 3 celle), l'elenco
// centrato sull'inchiostro (l'ultima colonna della cella è lo spazio fra i caratteri)
localparam integer TB_NAMES = 36, TB_SCORE = 80, TB_LEVEL = 160, TB_SPAN = TB_LEVEL + 3 * C - 1;
localparam integer TB_X = (W - TB_SPAN) / 2;

wire [9:0] x = hc;
wire [9:0] y = vc;

// cifra i (0 = la più a sinistra) di un numero BCD a 7 cifre
function [5:0] bcd7(input [27:0] v, input [2:0] i);
    bcd7 = {2'd0, v[4 * (6 - i) +: 4]};
endfunction

// cella del font: codice, scostamento (già diviso per la scala) e colore
reg        g_on;
reg [5:0]  g_code;
reg [9:0]  g_dx, g_dy;
reg [23:0] g_col;
reg [23:0] col;
reg        on;
reg [3:0]  row;
reg [2:0]  b_sel;                       // presentazione: bonus della colonna sotto il pixel
reg [9:0]  b_cx, b_dx, b_dy, first_x;
reg [4:0]  pts, pts_units;
reg [1:0]  pts_tens;
reg [9:0]  hud_x;
integer    i, j;
// presentazione: nome (riga, origine, colonna, lettera del GUARDIAN), capsula
reg signed [10:0] n_row, n_x0, n_u, n_v;
reg [2:0]  n_li;
reg        n_px, c_lit;

// numero di 7 cifre in (x0, y0), scala 1
task digits7(input [9:0] x0, input [9:0] y0, input [27:0] v, input [23:0] c);
    for (j = 0; j < 7; j = j + 1)
        if (x - (x0 + C * j) < C && y - y0 < CH_GLYPH_H) begin
            g_on = 1'b1; g_code = bcd7(v, j[2:0]); g_dx = x - (x0 + C * j); g_dy = y - y0; g_col = c;
        end
endtask

// una cella in (x0, y0) alla scala 2^s
task put(input [9:0] x0, input [9:0] y0, input [5:0] code, input [1:0] s, input [23:0] c);
    if (x - x0 < (C << s) && y - y0 < (CH_GLYPH_H << s)) begin
        g_on = 1'b1; g_code = code; g_dx = (x - x0) >> s; g_dy = (y - y0) >> s; g_col = c;
    end
endtask

// ------------------------------------------------ presentazione animata
// Come Stage di rust/game/src/challenge_ui.rs, con le distanze dimezzate: in cima il livello e sotto
// la scala dei sette livelli (trattini come quelli della mezzeria: battuti bianchi, quello in corso
// giallo che lampeggia), poi ogni avversario entra a modo suo e porta nome, motto, bonus e FIRST TO.
// La racchetta la disegna next_render (ip_*); qui il resto, con i valori di ogni frame calcolati da
// intro_age (i_*): nel pixel solo confronti e le ROM delle scritte. Le x "verso l'avversario" (ax)
// vanno verso la sua metà campo, da dove entra.
localparam integer IP_Y = 82;                     // centro della racchetta (INTRO_Y di next_render)
localparam integer LADDER_Y = 34, LADDER_X = 76;  // scala: 7 trattini 16x4 ogni 24 pixel
localparam integer NAME_GROUND = INTRO_KIND_Y + 17;   // TITAN: il pavimento sotto il nome
localparam integer WALL_TOP = IP_Y - 34;          // GUARDIAN: 5 settori da 12 righe ogni 14
localparam [2:0] K_ARCADE = 3'd0, K_TITAN = 3'd1, K_HAMMER = 3'd2, K_TWIST = 3'd3, K_BLASTER = 3'd4,
                 K_RUSH = 3'd5, K_GUARDIAN = 3'd6;
localparam [23:0] DIM = 24'h3A3A3A, GHOST = 24'h7F6912, TRAIL1 = 24'h9A9A9A, TRAIL2 = 24'h5E5E5E,
                  TRAIL3 = 24'h303030;

function signed [10:0] ax(input signed [10:0] d);
    ax = W / 2 + (side ? -d : d);
endfunction
// ARCADE: altezza delle capsule della raffica rispetto alla racchetta (come in next_render)
function signed [5:0] arcade_dy(input [3:0] k);
    case (k)
        4'd0: arcade_dy = -6'sd14; 4'd1: arcade_dy = 6'sd10;  4'd2: arcade_dy = -6'sd4; 4'd3: arcade_dy = 6'sd16;
        4'd4: arcade_dy = -6'sd18; 4'd5: arcade_dy = 6'sd2;   4'd6: arcade_dy = 6'sd12; 4'd7: arcade_dy = -6'sd10;
        4'd8: arcade_dy = 6'sd6;   default: arcade_dy = -6'sd2;
    endcase
endfunction
// ARCADE: trattini della mezzeria (6 righe accese ogni 12, dalla riga IP_Y - 28): (y - y0) / 6 pari
function net_dash(input [9:0] yy);
    reg [15:0] m;
    begin
        m = (yy - (IP_Y - 28)) * 43;
        net_dash = !m[8];
    end
endfunction
// TWIST: il nome entra inclinato e oscilla finché non si raddrizza (pixel per riga)
function signed [2:0] twist_shear(input [4:0] t);
    case (t)
        5'd0, 5'd1: twist_shear = 3'sd2;
        5'd5, 5'd6: twist_shear = -3'sd2;
        5'd2, 5'd9, 5'd10, 5'd11, 5'd18: twist_shear = 3'sd1;
        5'd4, 5'd7, 5'd13, 5'd14, 5'd15: twist_shear = -3'sd1;
        default: twist_shear = 3'sd0;
    endcase
endfunction
// caduta: frazione della strada fatta (256 = arrivata) dopo t + 1 frame su 5, ((t + 1) / 5)^2
function [8:0] fall_q(input [2:0] t);
    case (t)
        3'd0: fall_q = 9'd10;  3'd1: fall_q = 9'd41;  3'd2: fall_q = 9'd92;  3'd3: fall_q = 9'd164;
        default: fall_q = 9'd256;
    endcase
endfunction
// pixel nel rettangolo w x h con l'angolo in (x0, y0), anche fuori schermo
function in_box(input signed [10:0] x0, input signed [10:0] y0, input [6:0] w, input [6:0] h);
    reg signed [11:0] ddx, ddy;
    begin
        ddx = $signed({2'b0, x}) - x0;
        ddy = $signed({2'b0, y}) - y0;
        in_box = ddx >= 0 && ddx < $signed({5'd0, w}) && ddy >= 0 && ddy < $signed({5'd0, h});
    end
endfunction

// continue: y della pallina (parabola di 60 frame, alta 30 pixel: s (60 - s) * 17 / 512) e GAME OVER
// che si scrive (una lettera ogni 5 frame dal 12, cursore) e si chiude (dal frame 158)
reg signed [10:0] cont_ball_y;
reg [5:0]  go_cols;
reg        go_cur, go_close, go_close_line, go_close_dot;
reg signed [10:0] go_cur_x;
reg [6:0]  go_close_w, go_close_h;
reg [11:0] cb_m;
reg [7:0]  go_a;
reg [3:0]  go_n;
always @(posedge clk) begin
    cb_m = {6'd0, cont_sub} * (12'd60 - {6'd0, cont_sub});
    cont_ball_y <= 76 + 4 * CH_GLYPH_H - 6 - ((cb_m * 17) >> 9);
    go_a = intro_age - 8'd12;
    go_n = (intro_age < 8'd12) ? 4'd0 : (go_a >= 8'd40) ? GAME_OVER_LETTERS : ((go_a * 13) >> 6) + 4'd1;
    go_cols <= (go_n == 4'd0) ? 6'd0 : game_over_l1(go_n - 4'd1);
    go_cur_x <= (W - 2 * GAME_OVER_W) / 2 + 2 * ((go_n == 4'd0) ? 6'd0 : game_over_l1(go_n - 4'd1)) + 2;
    go_cur <= intro_age >= 8'd12 && (go_n < GAME_OVER_LETTERS || intro_age[4]);
    go_close <= intro_age >= 8'd158;
    go_close_line <= intro_age >= 8'd166 && intro_age < 8'd174;
    go_close_dot <= intro_age >= 8'd174;
    go_close_h <= (intro_age >= 8'd165) ? 7'd1 : 7'd120 - 7'd15 * (intro_age[6:0] - 7'd30);   // 158 = 128 + 30
    go_close_w <= (intro_age >= 8'd173) ? 7'd1 : 7'd127 - 7'd16 * (intro_age[6:0] - 7'd38);   // 166 = 128 + 38
end

reg        i_title, i_name, i_nacc, i_ground, i_gline, i_ghost, i_tag, i_first, i_net, i_ball, i_dust, i_wflash;
reg [2:0]  i_lad, i_cap, i_cinv, i_cname, i_trail, i_shot;
reg [3:0]  i_son;
reg [6:0]  i_nlo, i_nhi, i_tcols;
reg signed [10:0] i_ndx, i_ndy, i_gdx, i_tdx, i_bx, i_by, i_netx, i_wx;
reg signed [2:0]  i_shear;
reg signed [10:0] i_cdx [0:2];
reg signed [10:0] i_cdy [0:2];
reg signed [10:0] i_sx [0:3];
reg signed [10:0] i_sy [0:3];
reg signed [10:0] i_tx [0:2];
reg signed [10:0] i_shx [0:2];
reg signed [10:0] i_shy [0:2];
reg signed [10:0] i_ux [0:3];
reg signed [10:0] i_uy [0:3];
reg [7:0]  i_lshow;
reg signed [10:0] i_ldy [0:7];
reg [4:0]  i_wall;
reg signed [10:0] i_wy [0:4];

reg [7:0]  ts, tt;
reg [3:0]  tn;
reg signed [15:0] tm, td, tv, tw;
reg signed [10:0] tx0;
integer    c, q;

// motto scritto da t0, una lettera (5 pixel) per frame
task tag_from(input [7:0] t0);
    begin
        i_tag <= intro_age >= t0;
        tt = intro_age - t0;
        i_tcols <= (tt >= 8'd25) ? 7'd127 : ({tt[4:0], 2'b0} + tt[4:0]);
    end
endtask
// capsule che arrivano dalla metà campo dell'avversario (da 180 pixel dal centro), una ogni gap frame
// da t0, a sp pixel per frame; arrivate si accendono in negativo per 4 frame e mostrano il nome
task caps_slide(input [7:0] t0, input [7:0] gap, input [5:0] sp);
    for (c = 0; c < 3; c = c + 1) begin
        ts = t0 + gap * c;
        tv = side ? 16'sd100 + 16'sd80 * c : 16'sd260 - 16'sd80 * c;       // strada fino al posto
        tm = $signed({8'd0, intro_age - ts}) * $signed({10'd0, sp});
        if (intro_age < ts) begin
            i_cap[c] <= 1'b0;
            i_cname[c] <= 1'b0;
        end else if (tm < tv) begin
            i_cdx[c] <= side ? -(tv - tm) : (tv - tm);
            i_cname[c] <= 1'b0;
        end else
            i_cinv[c] <= tm < tv + ($signed({10'd0, sp}) <<< 2);
    end
endtask
// capsule che compaiono al loro posto in negativo, una ogni gap frame da t0
task caps_pop(input [7:0] t0, input [7:0] gap);
    for (c = 0; c < 3; c = c + 1) begin
        ts = t0 + gap * c;
        i_cap[c] <= intro_age >= ts;
        i_cname[c] <= intro_age >= ts;
        i_cinv[c] <= intro_age >= ts && intro_age < ts + 8'd4;
    end
endtask

always @(posedge clk) begin
    // stato finale, tutto fermo; ogni avversario cambia quello che anima
    i_title <= intro_age >= 8'd14 && (level != 3'd6 || !intro_age[3]);
    i_lad <= (intro_age >= 8'd12) ? 3'd7 : intro_age[3:1] + 3'd1;
    i_name <= 1'b1;
    i_ndx <= 11'sd0;
    i_ndy <= 11'sd0;
    i_nacc <= 1'b0;
    i_nlo <= 7'd0;
    i_nhi <= 7'd127;
    i_shear <= 3'sd0;
    i_ground <= 1'b0;
    i_gline <= 1'b0;
    i_ghost <= 1'b0;
    i_gdx <= 11'sd0;
    i_lshow <= 8'hFF;
    for (q = 0; q < 8; q = q + 1) i_ldy[q] <= 11'sd0;
    i_tag <= 1'b1;
    i_tcols <= 7'd127;
    i_tdx <= 11'sd0;
    i_cap <= 3'b111;
    i_cinv <= 3'b000;
    i_cname <= 3'b111;
    for (q = 0; q < 3; q = q + 1) begin
        i_cdx[q] <= 11'sd0;
        i_cdy[q] <= 11'sd0;
    end
    i_first <= 1'b1;
    i_net <= 1'b0;
    i_son <= 4'd0;
    i_ball <= 1'b0;
    i_trail <= 3'd0;
    i_shot <= 3'd0;
    i_dust <= 1'b0;
    i_wall <= 5'd0;
    i_wflash <= 1'b0;
    case (kind)
        K_ARCADE: begin
            // una raffica di capsule dalla mezzeria (a 120 pixel dal centro, dalla parte del
            // giocatore), 20 frame di volo ciascuna, una ogni 6 frame: quattro posti bastano
            i_net <= intro_age >= 8'd6 && intro_age < 8'd84;
            i_netx <= ax(-11'sd120);
            for (q = 0; q < 10; q = q + 1) begin
                ts = 8'd10 + 8'd6 * q;
                if (intro_age >= ts && intro_age < ts + 8'd20) begin
                    i_son[q % 4] <= 1'b1;
                    tv = $signed({8'd0, intro_age - ts}) * 16'sd6;
                    i_sx[q % 4] <= ax(-11'sd120 + tv[10:0]) - 11'sd4;
                    i_sy[q % 4] <= IP_Y + arcade_dy(q) - 4;
                end
            end
            // il nome lampeggia come INSERT COIN, poi i bonus escono dalla racchetta
            tt = intro_age - 8'd84;
            i_name <= intro_age >= 8'd84 && (intro_age >= 8'd108 || !tt[2]);
            tag_from(8'd100);
            for (c = 0; c < 3; c = c + 1) begin
                ts = 8'd120 + 8'd8 * c;
                tt = (intro_age < ts) ? 8'd0 : (intro_age - ts >= 8'd8) ? 8'd8 : intro_age - ts;
                i_cap[c] <= intro_age >= ts;
                i_cdx[c] <= ((11'sd80 - 11'sd80 * c) * $signed({7'd0, 4'd8 - tt[3:0]})) >>> 3;
                i_cdy[c] <= ($signed(IP_Y - 6 - INTRO_CAP_Y) * $signed({7'd0, 4'd8 - tt[3:0]})) >>> 3;
                i_cinv[c] <= intro_age >= ts + 8'd8 && intro_age < ts + 8'd12;
                i_cname[c] <= intro_age >= ts + 8'd8;
            end
            i_first <= intro_age >= 8'd160;
        end
        K_TWIST: begin
            // la palla arriva e la racchetta inclinata la ribatte di sbieco, verso l'alto
            if (intro_age >= 8'd14 && intro_age < 8'd30) begin
                i_ball <= 1'b1;
                i_bx <= ax(-11'sd160 + $signed({3'd0, intro_age - 8'd14}) * 10) - 11'sd2;
                i_by <= IP_Y + 9;
            end else if (intro_age >= 8'd30 && intro_age < 8'd55) begin
                tt = intro_age - 8'd30;
                i_ball <= 1'b1;
                i_bx <= ax(-11'sd8 - $signed({3'd0, tt}) * 7) - 11'sd2;
                i_by <= IP_Y + 9 - $signed({3'd0, tt}) * 4;
            end
            i_name <= intro_age >= 8'd66;
            tt = intro_age - 8'd66;
            i_shear <= (intro_age >= 8'd66 && tt < 8'd24) ? twist_shear(tt[4:0]) : 3'sd0;
            tag_from(8'd92);
            caps_slide(8'd112, 8'd12, 6'd30);
            i_first <= intro_age >= 8'd160;
        end
        K_HAMMER: begin
            // la palla arriva piano, il martello la ribatte fortissimo con la scia
            if (intro_age >= 8'd12 && intro_age < 8'd49) begin
                i_ball <= 1'b1;
                i_bx <= ax(-11'sd10 - $signed({3'd0, 8'd49 - intro_age}) * 4) - 11'sd2;
                i_by <= IP_Y - 2;
            end else if (intro_age >= 8'd49 && intro_age < 8'd59) begin
                tv = -16'sd10 - $signed({8'd0, intro_age - 8'd49}) * 20;
                i_ball <= 1'b1;
                i_bx <= ax(tv[10:0]) - 11'sd2;
                i_by <= IP_Y - 2;
                i_trail <= 3'b111;
                for (q = 0; q < 3; q = q + 1) i_tx[q] <= ax(tv[10:0] + 11'sd8 * (q + 1)) - 11'sd2;
            end
            // il nome cade come un peso (1,3 d^2 pixel sopra) e alza la polvere
            i_name <= intro_age >= 8'd62;
            tt = 8'd72 - intro_age;
            tm = $signed({8'd0, tt}) * $signed({8'd0, tt});
            i_ndy <= (intro_age < 8'd72) ? -(tm + ((tm * 5) >>> 4)) : 16'sd0;
            if (intro_age >= 8'd72 && intro_age < 8'd82) begin
                tt = intro_age - 8'd72;
                tv = $signed({8'd0, tt});
                tm = (tv * tv * 13) >>> 5;
                tw = $signed({9'd0, kind_name_w(kind)});
                i_dust <= 1'b1;
                i_ux[0] <= W / 2 - tw - 5 - tv * 3;
                i_ux[1] <= W / 2 + tw + 3 + tv * 3;
                i_ux[2] <= W / 2 - tw - 5 - tv * 5;
                i_ux[3] <= W / 2 + tw + 3 + tv * 5;
                i_uy[0] <= 137 - ((tv * 5) >>> 1) + tm;
                i_uy[1] <= 137 - ((tv * 5) >>> 1) + tm;
                i_uy[2] <= 137 - ((tv * 3) >>> 1) + tm;
                i_uy[3] <= 137 - ((tv * 3) >>> 1) + tm;
            end
            tag_from(8'd88);
            // le capsule cadono pesanti
            for (c = 0; c < 3; c = c + 1) begin
                ts = 8'd106 + 8'd10 * c;
                tt = intro_age - ts;
                tv = 16'sd8 - $signed({8'd0, tt});
                i_cap[c] <= intro_age >= ts;
                i_cdy[c] <= (intro_age >= ts && tt < 8'd8) ? -(tv * tv * 3) : 16'sd0;
                i_cinv[c] <= intro_age >= ts && tt >= 8'd8 && tt < 8'd11;
                i_cname[c] <= intro_age >= ts && tt >= 8'd8;
            end
            i_first <= intro_age >= 8'd150;
        end
        K_TITAN: begin
            // il nome sale da sotto il pavimento, un pixel per frame
            i_name <= intro_age >= 8'd84;
            tt = intro_age - 8'd84;
            i_ndy <= (intro_age < 8'd84 || tt >= 8'd25) ? 11'sd0 : 11'sd25 - $signed({3'd0, tt});
            i_ground <= 1'b1;
            i_gline <= intro_age >= 8'd84 && intro_age < 8'd112;
            // il motto si scrive piano: una lettera ogni 3 frame
            i_tag <= intro_age >= 8'd114;
            tm = ($signed({8'd0, intro_age - 8'd114}) * 55) >>> 5;
            i_tcols <= (intro_age - 8'd114 >= 8'd74) ? 7'd127 : tm[6:0];
            caps_slide(8'd156, 8'd12, 6'd8);
            i_first <= intro_age >= 8'd214;
        end
        K_BLASTER: begin
            // ogni colpo accende una lettera del nome, dalla più vicina alla racchetta (bocca a 112
            // pixel verso l'avversario, colpi a 20 pixel per frame, uno ogni 5 frame dal 12)
            tn = 4'd0;
            tx0 = (W - 2 * kind_name_w(K_BLASTER)) / 2;
            for (q = 0; q < 7; q = q + 1) begin
                // centro della lettera j (contata da sinistra) e distanza dalla bocca
                tv = side ? q : 6 - q;
                td = tx0 + ((tv == 0) ? kind_l1(K_BLASTER, 4'd0) - 1 :
                            kind_l1(K_BLASTER, tv[3:0] - 4'd1) + kind_l1(K_BLASTER, tv[3:0]));
                td = ax(11'sd112) - td;
                td = (td < 0) ? -td : td;
                ts = 8'd12 + 8'd5 * q;
                tm = $signed({8'd0, intro_age - ts}) * 20;
                if (intro_age >= ts && tm >= td) tn = tn + 4'd1;
                if (intro_age >= ts && tm < td) begin
                    i_shot[q % 3] <= 1'b1;
                    i_shx[q % 3] <= ax(11'sd112 - tm[10:0]) - 11'sd3;
                    i_shy[q % 3] <= INTRO_KIND_Y + 9;
                end
            end
            i_nlo <= side ? 7'd0 : (tn == 4'd0) ? 7'd127 : (tn >= 4'd7) ? 7'd0 : kind_l1(K_BLASTER, 4'd6 - tn);
            i_nhi <= !side ? 7'd127 : (tn == 4'd0) ? 7'd0 : kind_l1(K_BLASTER, tn - 4'd1);
            tag_from(8'd56);
            // poi, sceso all'altezza delle capsule (dal frame 76), le colpisce al volo: arrivano
            // dalla parte del giocatore e il colpo, dalla bocca, le ferma al loro posto
            for (c = 0; c < 3; c = c + 1) begin
                ts = 8'd96 + 8'd14 * c;
                if (intro_age < ts) begin
                    tv = $signed({8'd0, ts - intro_age}) * 10;
                    i_cdx[c] <= side ? tv : -tv;
                    i_cap[c] <= tv < 16'sd200;
                    i_cname[c] <= 1'b0;
                    tm = 16'sd10 + $signed({8'd0, ts - intro_age}) * 20;          // colpo, dal posto
                    tw = side ? 16'sd112 + 16'sd80 * (c - 1) : 16'sd112 - 16'sd80 * (c - 1);   // posto-bocca
                    if (intro_age >= 8'd76 && tm <= tw) begin
                        i_shot[c] <= 1'b1;
                        i_shx[c] <= W / 2 - 80 + 80 * c + (side ? -tm : tm) - 3;
                        i_shy[c] <= INTRO_CAP_Y + 6;
                    end
                end else
                    i_cinv[c] <= intro_age < ts + 8'd4;
            end
            i_first <= intro_age >= 8'd150;
        end
        K_RUSH: begin
            // nome, motto e capsule entrano con uno scatto, come la racchetta; il nome con
            // un'immagine gialla dietro
            tt = intro_age - 8'd30;
            tv = (tt == 8'd0) ? 16'sd127 : (tt == 8'd1) ? 16'sd85 : (tt == 8'd2) ? 16'sd42 : 16'sd0;
            i_name <= intro_age >= 8'd30;
            i_ndx <= side ? -tv : tv;
            i_ghost <= intro_age >= 8'd30 && tt < 8'd12;
            i_gdx <= side ? -((16'sd170 + tv) >>> 1) : ((16'sd170 + tv) >>> 1);
            i_nacc <= intro_age >= 8'd34 && intro_age < 8'd36;
            tt = intro_age - 8'd44;
            tv = (tt == 8'd0) ? 16'sd113 : (tt == 8'd1) ? 16'sd57 : 16'sd0;
            i_tag <= intro_age >= 8'd44;
            i_tdx <= side ? -tv : tv;
            for (c = 0; c < 3; c = c + 1) begin
                ts = 8'd58 + 8'd6 * c;
                tt = intro_age - ts;
                tm = side ? 16'sd100 + 16'sd80 * c : 16'sd260 - 16'sd80 * c;
                tv = (tt == 8'd0) ? (tm * 21) >>> 5 : (tt == 8'd1) ? (tm * 11) >>> 5 : 16'sd0;
                i_cap[c] <= intro_age >= ts;
                i_cdx[c] <= side ? -tv : tv;
                i_cinv[c] <= intro_age >= ts && tt >= 8'd3 && tt < 8'd5;
                i_cname[c] <= intro_age >= ts && tt >= 8'd3;
            end
            i_first <= intro_age >= 8'd90;
        end
        K_GUARDIAN: begin
            // i cinque pezzi del muro cadono uno sull'altro, dal basso
            i_wx <= ax(11'sd18);
            for (q = 0; q < 5; q = q + 1) begin
                ts = 8'd10 + 8'd8 * q;
                tt = intro_age - ts;
                tv = WALL_TOP + 14 * (4 - q);
                i_wall[4 - q] <= intro_age >= ts;
                i_wy[4 - q] <= (intro_age >= ts && tt < 8'd5) ?
                               -16'sd15 + (((tv + 16'sd15) * $signed({7'd0, fall_q(tt[2:0])})) >>> 8) : tv;
            end
            i_wflash <= intro_age >= 8'd82 && intro_age < 8'd90 && !intro_age[1];
            // una palla passa sopra la racchetta e il muro la rimanda
            if (intro_age >= 8'd52 && intro_age < 8'd82) begin
                i_ball <= 1'b1;
                i_bx <= ax(-11'sd162 + $signed({3'd0, intro_age - 8'd52}) * 6) - 11'sd2;
                i_by <= WALL_TOP + 4;
            end else if (intro_age >= 8'd82 && intro_age < 8'd112) begin
                i_ball <= 1'b1;
                i_bx <= ax(11'sd16 - $signed({3'd0, intro_age - 8'd82}) * 6) - 11'sd2;
                i_by <= WALL_TOP + 4;
            end
            // il nome si posa lettera per lettera, come i mattoni, da 157 pixel sopra (79 / 128: a 16 bit
            // 157 * 256 non ci sta)
            for (q = 0; q < 8; q = q + 1) begin
                ts = 8'd96 + 8'd3 * q;
                tt = intro_age - ts;
                i_lshow[q] <= intro_age >= ts;
                i_ldy[q] <= (intro_age >= ts && tt < 8'd5) ?
                            -((16'sd79 * (16'sd256 - $signed({7'd0, fall_q(tt[2:0])}))) >>> 7) : 16'sd0;
            end
            tag_from(8'd130);
            caps_pop(8'd152, 8'd10);
            i_first <= intro_age >= 8'd190;
        end
        default: ;
    endcase
end

// scritta centrata, scala 2
`define CENTER2(lit, w, y0) lit((x - (W - 2 * (w)) / 2) >> 1, (y - (y0)) >> 1)
`define CENTER1(lit, w, y0) lit(x - (W - (w)) / 2, y - (y0))

always @(*) begin
    col = BLACK;
    on = 1'b0;
    g_on = 1'b0;
    g_code = 6'd0;
    g_dx = 10'd0;
    g_dy = 10'd0;
    g_col = WHITE;
    row = 4'd0;
    b_sel = 3'd0;
    b_cx = 10'd0;
    b_dx = 10'd0;
    b_dy = 10'd0;
    first_x = 10'd0;
    pts = 5'd0;
    pts_tens = 2'd0;
    pts_units = 5'd0;
    hud_x = 10'd0;
    case (screen)
        3'd1: begin   // ------------------------------------------------ presentazione
            on = 1'b1;
            if (i_title && ch_intro_lit(level, (x - (W - 2 * ch_intro_w(level)) / 2) >> 1, (y - 14) >> 1)) col = ACCENT;
            // la scala dei livelli
            for (j = 0; j < 7; j = j + 1)
                if (j < i_lad && in_box(LADDER_X + 24 * j, LADDER_Y, 7'd16, 7'd4))
                    col = (j < level) ? WHITE : (j == level && !intro_age[3]) ? ACCENT : DIM;
            // nome: spostato, inclinato per riga (TWIST), a colonne (BLASTER), sotto il pavimento
            // (TITAN), lettera per lettera (GUARDIAN); RUSH ha un'immagine gialla dietro
            n_row = ($signed({2'b0, y}) - (INTRO_KIND_Y + i_ndy)) >>> 1;
            n_x0 = (W - 2 * kind_name_w(kind)) / 2 + i_ndx + i_shear * (n_row - 11'sd4);
            n_u = ($signed({2'b0, x}) - n_x0) >>> 1;
            n_li = (n_u >= kind_l1(K_GUARDIAN, 4'd0)) + (n_u >= kind_l1(K_GUARDIAN, 4'd1)) +
                   (n_u >= kind_l1(K_GUARDIAN, 4'd2)) + (n_u >= kind_l1(K_GUARDIAN, 4'd3)) +
                   (n_u >= kind_l1(K_GUARDIAN, 4'd4)) + (n_u >= kind_l1(K_GUARDIAN, 4'd5)) +
                   (n_u >= kind_l1(K_GUARDIAN, 4'd6));
            n_v = ($signed({2'b0, y}) - (INTRO_KIND_Y + i_ndy + (kind == K_GUARDIAN ? i_ldy[n_li] : 11'sd0))) >>> 1;
            n_px = i_name && n_u >= 0 && n_u >= $signed({4'd0, i_nlo}) && n_u < $signed({4'd0, i_nhi}) &&
                   kind_name_lit(kind, n_u[9:0], n_v[9:0]) && (kind != K_GUARDIAN || i_lshow[n_li]) &&
                   !(i_ground && y >= NAME_GROUND);
            if (i_ghost && !n_px && kind_name_lit(kind, (x - ((W - 2 * kind_name_w(kind)) / 2 + i_gdx)) >> 1,
                                                  (y - INTRO_KIND_Y) >> 1))
                col = GHOST;
            if (n_px) col = i_nacc ? ACCENT : WHITE;
            if (i_gline && y == NAME_GROUND && in_box(W / 2 - kind_name_w(kind) - 8, NAME_GROUND, 2 * kind_name_w(kind) + 16, 7'd1))
                col = DIM;
            // motto: scritto a colonne, o spostato (RUSH)
            if (i_tag && tag_lit(kind, x - ((W - tag_w(kind)) / 2 + i_tdx), y - (INTRO_KIND_Y + 22)) &&
                x - ((W - tag_w(kind)) / 2 + i_tdx) < i_tcols)
                col = GRAY;
            // i bonus dell'avversario su tre colonne (centri a 80, 160 e 240): capsula con l'icona di
            // pong_next.vh, spostata o in negativo; il nome sotto, al suo posto
            for (j = 0; j < 3; j = j + 1)
                if (i_cap[j] && in_box(W / 2 - 86 + 80 * j + i_cdx[j], INTRO_CAP_Y + i_cdy[j], INTRO_CAP, INTRO_CAP)) begin
                    b_dx = x - (W / 2 - 86 + 80 * j + i_cdx[j]);
                    b_dy = y - (INTRO_CAP_Y + i_cdy[j]);
                    c_lit = icon_lit(loadout[3 * j +: 3], b_dx - (INTRO_CAP - 9) / 2, b_dy - (INTRO_CAP - 9) / 2);
                    if (i_cinv[j]) col = c_lit ? BLACK : ACCENT;
                    else if (c_lit || b_dx == 0 || b_dy == 0 || b_dx == INTRO_CAP - 1 || b_dy == INTRO_CAP - 1)
                        col = ACCENT;
                end
            if (x < 10'd120) begin
                b_sel = loadout[2:0];
                b_cx = 10'd80;
            end else if (x < 10'd200) begin
                b_sel = loadout[5:3];
                b_cx = 10'd160;
            end else begin
                b_sel = loadout[8:6];
                b_cx = 10'd240;
            end
            if (i_cname[(x < 10'd120) ? 0 : (x < 10'd200) ? 1 : 2] &&
                name_lit(b_sel, x - (b_cx - name_w(b_sel) / 2), y - (INTRO_CAP_Y + INTRO_CAP + 3))) col = ACCENT;
            // FIRST TO n: n da rung_points, una o due cifre del font a celle dopo la scritta
            pts = rung_points(level);
            pts_tens = (pts >= 5'd30) ? 2'd3 : (pts >= 5'd20) ? 2'd2 : (pts >= 5'd10) ? 2'd1 : 2'd0;
            pts_units = pts - {pts_tens, 3'd0} - {pts_tens, 1'b0};
            first_x = (pts_tens != 2'd0) ? FIRST_X2 : FIRST_X1;
            if (i_first) begin
                if (ch_first_lit(x - first_x, y - INTRO_FIRST_Y)) col = GRAY;
                if (pts_tens != 2'd0) begin
                    put(first_x + CH_FIRST_W + 2, INTRO_FIRST_Y, {4'd0, pts_tens}, 2'd0, GRAY);
                    put(first_x + CH_FIRST_W + 2 + C, INTRO_FIRST_Y, {1'b0, pts_units}, 2'd0, GRAY);
                end else
                    put(first_x + CH_FIRST_W + 2, INTRO_FIRST_Y, {1'b0, pts_units}, 2'd0, GRAY);
            end
            // il resto delle entrate: mezzeria e raffica (ARCADE), palla e scia, colpi (BLASTER),
            // polvere (HAMMER), muro a settori (GUARDIAN)
            if (i_net && (x == i_netx || x == i_netx + 1) && y >= IP_Y - 28 && y < IP_Y + 32 && net_dash(y))
                col = WHITE;
            for (j = 0; j < 4; j = j + 1)
                if (i_son[j] && in_box(i_sx[j], i_sy[j], 7'd8, 7'd8) && !in_box(i_sx[j] + 1, i_sy[j] + 1, 7'd6, 7'd6))
                    col = ACCENT;
            for (j = 0; j < 3; j = j + 1)
                if (i_trail[j] && in_box(i_tx[j], i_by, 7'd4, 7'd4))
                    col = (j == 0) ? TRAIL1 : (j == 1) ? TRAIL2 : TRAIL3;
            if (i_ball && in_box(i_bx, i_by, 7'd4, 7'd4)) col = WHITE;
            for (j = 0; j < 3; j = j + 1)
                if (i_shot[j] && (in_box(i_shx[j], i_shy[j] - 4, 7'd6, 7'd1) || in_box(i_shx[j], i_shy[j] + 3, 7'd6, 7'd1)))
                    col = ACCENT;
            for (j = 0; j < 4; j = j + 1)
                if (i_dust && in_box(i_ux[j], i_uy[j], 7'd2, 7'd2)) col = GRAY;
            for (j = 0; j < 5; j = j + 1)
                if (i_wall[j] && in_box(i_wx, i_wy[j], 7'd2, 7'd12) && !in_box(i_wx, i_wy[j] + 3, 7'd2, 7'd1) &&
                    !in_box(i_wx, i_wy[j] + 7, 7'd2, 7'd1) && !in_box(i_wx, i_wy[j] + 11, 7'd2, 7'd1))
                    col = (j == 0 && i_wflash) ? WHITE : ACCENT;
            if (ch_score_lit(x - 40, y - 216)) col = WHITE;
            digits7(10'd40 + CH_SCORE_W + 4, 10'd216, score_bcd, WHITE);
            if (ch_hi_lit(x - 176, y - 216)) col = WHITE;
            digits7(10'd176 + CH_HI_W + 4, 10'd216, hi_bcd, WHITE);
            // sfidante: invito lampeggiante dal lato libero (P2 con il campione a sinistra)
            if (join_prompt && blink < 6'd30) begin
                if (coin_prompt) begin
                    if (ch_coin_lit(x - (side ? COIN_XL : COIN_XR), y - JOIN_Y)) col = WHITE;
                end else begin
                    put(side ? JOIN_XL : JOIN_XR, JOIN_Y, G_P, 2'd0, WHITE);
                    put((side ? JOIN_XL : JOIN_XR) + C, JOIN_Y, side ? 6'd1 : 6'd2, 2'd0, WHITE);
                    if (ch_press_lit(x - ((side ? JOIN_XL : JOIN_XR) + 2 * C + 4), y - JOIN_Y)) col = WHITE;
                end
            end
        end
        3'd2: begin   // ---------------------------------------------- livello superato
            on = 1'b1;
            if (ch_clear_lit(level, (x - (W - 2 * ch_clear_w(level)) / 2) >> 1, (y - 40) >> 1)) col = ACCENT;
            if (level == CH_LEVELS - 1 && `CENTER1(ch_beat_lit, CH_BEAT_W, 72)) col = WHITE;
            if (ch_win_lit(x - 90, y - 100)) col = WHITE;
            // +1000 x livello: cifre "n000"
            put(10'd180, 10'd100, G_PLUS, 2'd0, WHITE);
            for (j = 0; j < 4; j = j + 1)
                put(10'd187 + C * j, 10'd100, (j == 0) ? {3'd0, level} + 6'd1 : 6'd0, 2'd0, WHITE);
            if (perfect) begin
                if (ch_perfect_lit(x - 90, y - 120)) col = ACCENT;
                // +2000 x livello
                put(10'd180, 10'd120, G_PLUS, 2'd0, ACCENT);
                if (level >= 3'd4) begin
                    put(10'd187, 10'd120, 6'd1, 2'd0, ACCENT);
                    put(10'd187 + C, 10'd120, {2'd0, ({level, 1'b0} + 4'd2) - 4'd10}, 2'd0, ACCENT);
                end else
                    put(10'd187, 10'd120, {2'd0, {level, 1'b0} + 4'd2}, 2'd0, ACCENT);
                for (j = 0; j < 3; j = j + 1)
                    put(10'd187 + C * (j + (level >= 3'd4 ? 2 : 1)), 10'd120, 6'd0, 2'd0, ACCENT);
            end
            if (ch_score_lit(x - 90, y - 150)) col = WHITE;
            digits7(10'd180, 10'd150, score_bcd, WHITE);
            if (`CENTER1(ch_press_lit, CH_PRESS_W, 200)) col = GRAY;
        end
        3'd3: begin   // ------------------------------------------------------ continue
            on = 1'b1;
            if (cont_over) begin
                // continue scaduto: GAME OVER al centro, come quello sopra la partita ma senza campo
                // da spegnere: si scrive subito con il cursore, poi lo schermo si chiude come un
                // televisore (come OV_TYPE e OV_OFF di pong_render; intro_age conta i frame del GAME OVER)
                if (`CENTER2(game_over_lit, GAME_OVER_W, AT_GAME_OVER_Y) && (x - (W - 2 * GAME_OVER_W) / 2) >> 1 < go_cols)
                    col = WHITE;
                if (go_cur && in_box(go_cur_x, AT_GAME_OVER_Y, 7'd8, 7'd14)) col = WHITE;
                if (go_close && (go_close_dot ? (x == W / 2 - 1 || x == W / 2) && (y == 119 || y == 120) :
                                 go_close_line ? (y == 119 || y == 120) && x >= W / 2 - go_close_w && x < W / 2 + go_close_w :
                                 (y == 120 - go_close_h || y == 119 + go_close_h)))
                    col = WHITE;
                else if (go_close && (go_close_dot || go_close_line || y < 120 - go_close_h || y > 119 + go_close_h))
                    col = BLACK;
            end else begin
                if (`CENTER2(ch_cont_lit, CH_CONT_W, 36)) col = ACCENT;
                put(W / 2 - 2 * C, 10'd76, {2'd0, cont_digit}, 2'd2, WHITE);
                // pallina che rimbalza a destra del numero: tocca terra a ogni secondo, quando il
                // numero cambia; negli ultimi tre secondi diventa gialla
                if (in_box(W / 2 + 2 * C + 12, cont_ball_y, 7'd6, 7'd6)) col = (cont_digit <= 4'd2) ? ACCENT : WHITE;
                if (in_box(W / 2 + 2 * C + 9, 10'd76 + 4 * CH_GLYPH_H, 7'd12, 7'd1)) col = GRAY;
                if (blink < 6'd30 &&
                    (coin_prompt ? `CENTER1(ch_coin_lit, CH_COIN_W, 160) : `CENTER1(ch_press_lit, CH_PRESS_W, 160)))
                    col = WHITE;
                if (`CENTER1(ch_reset_lit, CH_RESET_W, 190)) col = GRAY;
            end
        end
        3'd4: begin   // ------------------------------------------------------- iniziali
            on = 1'b1;
            if (`CENTER2(ch_record_lit, CH_RECORD_W, 24)) col = ACCENT;
            if (ch_score_lit(x - 100, y - 66)) col = WHITE;
            digits7(10'd100 + CH_SCORE_W + 4, 10'd66, score_bcd, WHITE);
            if (`CENTER1(ch_enter_lit, CH_ENTER_W, 92)) col = GRAY;
            for (i = 0; i < 3; i = i + 1) begin
                if (i < name_pos)
                    put(10'd160 - 2 * C + 40 * (i - 1), 10'd116, name[6 * i +: 6], 2'd2, WHITE);
                else if (i == name_pos) begin
                    if (blink < 6'd40) put(10'd160 - 2 * C + 40 * (i - 1), 10'd116, letter, 2'd2, ACCENT);
                end else
                    put(10'd160 - 2 * C + 40 * (i - 1), 10'd116, G_DOT, 2'd2, WHITE);
            end
            if (`CENTER1(ch_hint_lit, CH_HINT_W, 210)) col = GRAY;
        end
        3'd5: begin   // ----------------------------------------------------- classifica
            on = 1'b1;
            if (`CENTER2(ch_table_lit, CH_TABLE_W, 6)) col = ACCENT;
            // dieci righe da 18 pixel: si sceglie la riga, poi la cella
            for (i = 0; i < 10; i = i + 1)
                if (y - (36 + 18 * i) < CH_GLYPH_H) row = i[3:0];
            if (y >= 36 && y < 36 + 18 * 10) begin
                // posizione: 1-10
                if (row == 4'd9) begin
                    put(TB_X, 10'd36 + 18 * 9, 6'd1, 2'd0, (highlight == row) ? ACCENT : WHITE);
                    put(TB_X + C, 10'd36 + 18 * 9, 6'd0, 2'd0, (highlight == row) ? ACCENT : WHITE);
                end else
                    put(TB_X + C, 10'd36 + 18 * row, {2'd0, row} + 6'd1, 2'd0, (highlight == row) ? ACCENT : WHITE);
                for (j = 0; j < 3; j = j + 1)
                    put(TB_X + TB_NAMES + C * j, 10'd36 + 18 * row, table_names[18 * row + 6 * j +: 6], 2'd0,
                         (highlight == row) ? ACCENT : WHITE);
                digits7(TB_X + TB_SCORE, 10'd36 + 18 * row, table_bcd[28 * row +: 28], (highlight == row) ? ACCENT : WHITE);
                if (table_levels[4 * row +: 4] > 4'd7) begin
                    // scala finita: ALL
                    put(TB_X + TB_LEVEL, 10'd36 + 18 * row, 6'd10, 2'd0, (highlight == row) ? ACCENT : GRAY);
                    put(TB_X + TB_LEVEL + C, 10'd36 + 18 * row, G_L, 2'd0, (highlight == row) ? ACCENT : GRAY);
                    put(TB_X + TB_LEVEL + 2 * C, 10'd36 + 18 * row, G_L, 2'd0, (highlight == row) ? ACCENT : GRAY);
                end else begin
                    put(TB_X + TB_LEVEL, 10'd36 + 18 * row, G_L, 2'd0, (highlight == row) ? ACCENT : GRAY);
                    put(TB_X + TB_LEVEL + C, 10'd36 + 18 * row, {2'd0, table_levels[4 * row +: 4]}, 2'd0,
                         (highlight == row) ? ACCENT : GRAY);
                end
            end
            if (blink < 6'd30 &&
                (coin_prompt ? `CENTER1(ch_coin_lit, CH_COIN_W, 226) : `CENTER1(ch_press_lit, CH_PRESS_W, 226)))
                col = GRAY;
        end
        3'd6: begin   // -------------------------------------------- punti in partita
            // in basso dalla parte dell'avversario, lontano dai punteggi e dalla mezzeria: livello,
            // punti, moltiplicatore
            hud_x = side ? HUD_L : HUD_R;
            put(hud_x, 10'd229, G_L, 2'd0, GRAY);
            put(hud_x + C, 10'd229, {3'd0, level} + 6'd1, 2'd0, GRAY);
            digits7(hud_x + 20, 10'd229, score_bcd, WHITE);
            if (mult > 4'd1) begin
                put(hud_x + 74, 10'd229, G_X, 2'd0, ACCENT);
                put(hud_x + 74 + C, 10'd229, {2'd0, mult}, 2'd0, ACCENT);
            end
        end
        3'd7: begin   // ----------------------------------- HERE COMES A NEW CHALLENGER!
            // come nei picchiaduro: banda rossa e scritta a scala 4 che lampeggia (8 frame per colore)
            on = 1'b1;
            if (y - NEW_BAND_Y < NEW_BAND_H) col = BAND;
            if (y - NEW_BAND_Y == 0 || y - NEW_BAND_Y == NEW_BAND_H - 1) col = ACCENT;
            if (ch_here_lit((x - (W - 4 * CH_HERE_W) / 2) >> 2, (y - NEW_Y1) >> 2) ||
                ch_newch_lit((x - (W - 4 * CH_NEWCH_W) / 2) >> 2, (y - NEW_Y2) >> 2))
                col = blink[3] ? WHITE : ACCENT;
        end
        default: ;
    endcase
    if (g_on && glyph_lit(g_code, g_dx, g_dy)) begin
        on = 1'b1;
        col = g_col;
    end
end

`undef CENTER1
`undef CENTER2

always @(posedge clk) begin
    rgb <= col;
    opaque <= on;
end

endmodule

// Binario -> BCD (7 cifre) con il doppio dabble, un bit per ciclo: si ricomincia di continuo, il
// risultato si aggiorna ogni 25 cicli. Solo confronti, somme e shift.
module bin_to_bcd (
    input  wire        clk,
    input  wire [23:0] bin,
    output reg  [27:0] bcd
);

reg [23:0] sh = 24'd0;
reg [31:0] acc = 32'd0;
reg [4:0]  count = 5'd0;
reg [31:0] adj;
integer    d;

initial bcd = 28'd0;

always @(*) begin
    adj = acc;
    for (d = 0; d < 8; d = d + 1)
        if (acc[4 * d +: 4] >= 4'd5) adj[4 * d +: 4] = acc[4 * d +: 4] + 4'd3;
end

always @(posedge clk) begin
    if (count == 5'd0) begin
        sh <= bin;
        acc <= 32'd0;
        count <= 5'd24;
    end else begin
        {acc, sh} <= {adj[30:0], sh, 1'b0};
        count <= count - 5'd1;
        if (count == 5'd1) bcd <= {adj[26:0], sh[23]};
    end
end

endmodule
