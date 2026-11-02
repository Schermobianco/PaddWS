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
    input  wire [17:0] name,              // iniziali scelte (codici del font, 6 bit ciascuno)
    input  wire [1:0]  name_pos,          // lettera in corso
    input  wire [5:0]  letter,            // codice della lettera sotto il cursore
    input  wire [179:0] table_names,      // classifica: 10 x 3 codici
    input  wire [279:0] table_bcd,        // 10 x 7 cifre
    input  wire [39:0] table_levels,      // 10 x livello (8 = scala finita)
    input  wire [3:0]  highlight,         // posto appena inserito (15 = nessuno)
    input  wire [3:0]  mult,              // moltiplicatore dello scambio
    output reg  [23:0] rgb,
    output reg         opaque
);

`include "pong_params.vh"
`include "pong_next.vh"
`include "pong_challenge.vh"

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
            if (ch_intro_lit(level, (x - (W - 2 * ch_intro_w(level)) / 2) >> 1, (y - 14) >> 1)) col = ACCENT;
            // la racchetta dell'avversario con i segni del tipo la disegna next_render (intro), sopra
            if (kind_name_lit(kind, (x - (W - 2 * kind_name_w(kind)) / 2) >> 1, (y - INTRO_KIND_Y) >> 1)) col = WHITE;
            if (tag_lit(kind, x - (W - tag_w(kind)) / 2, y - (INTRO_KIND_Y + 22))) col = GRAY;
            // i bonus dell'avversario su tre colonne (centri a 80, 160 e 240): capsula con l'icona
            // di pong_next.vh e nome sotto. Si sceglie la colonna, poi un solo accesso a icone e nomi
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
            b_dx = x - (b_cx - INTRO_CAP / 2);
            b_dy = y - INTRO_CAP_Y;
            if (b_dx < INTRO_CAP && b_dy < INTRO_CAP &&
                (b_dx == 0 || b_dy == 0 || b_dx == INTRO_CAP - 1 || b_dy == INTRO_CAP - 1 ||
                 icon_lit(b_sel, b_dx - (INTRO_CAP - 9) / 2, b_dy - (INTRO_CAP - 9) / 2)))
                col = ACCENT;
            if (name_lit(b_sel, x - (b_cx - name_w(b_sel) / 2), y - (INTRO_CAP_Y + INTRO_CAP + 3))) col = ACCENT;
            // FIRST TO n: n da rung_points, una o due cifre del font a celle dopo la scritta
            pts = rung_points(level);
            pts_tens = (pts >= 5'd30) ? 2'd3 : (pts >= 5'd20) ? 2'd2 : (pts >= 5'd10) ? 2'd1 : 2'd0;
            pts_units = pts - {pts_tens, 3'd0} - {pts_tens, 1'b0};
            first_x = (pts_tens != 2'd0) ? FIRST_X2 : FIRST_X1;
            if (ch_first_lit(x - first_x, y - INTRO_FIRST_Y)) col = GRAY;
            if (pts_tens != 2'd0) begin
                put(first_x + CH_FIRST_W + 2, INTRO_FIRST_Y, {4'd0, pts_tens}, 2'd0, GRAY);
                put(first_x + CH_FIRST_W + 2 + C, INTRO_FIRST_Y, {1'b0, pts_units}, 2'd0, GRAY);
            end else
                put(first_x + CH_FIRST_W + 2, INTRO_FIRST_Y, {1'b0, pts_units}, 2'd0, GRAY);
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
            if (`CENTER2(ch_cont_lit, CH_CONT_W, 36)) col = ACCENT;
            put(W / 2 - 2 * C, 10'd76, {2'd0, cont_digit}, 2'd2, WHITE);
            if (blink < 6'd30 &&
                (coin_prompt ? `CENTER1(ch_coin_lit, CH_COIN_W, 160) : `CENTER1(ch_press_lit, CH_PRESS_W, 160)))
                col = WHITE;
            if (`CENTER1(ch_reset_lit, CH_RESET_W, 190)) col = GRAY;
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
                    put(10'd56, 10'd36 + 18 * 9, 6'd1, 2'd0, (highlight == row) ? ACCENT : WHITE);
                    put(10'd56 + C, 10'd36 + 18 * 9, 6'd0, 2'd0, (highlight == row) ? ACCENT : WHITE);
                end else
                    put(10'd56 + C, 10'd36 + 18 * row, {2'd0, row} + 6'd1, 2'd0, (highlight == row) ? ACCENT : WHITE);
                for (j = 0; j < 3; j = j + 1)
                    put(10'd92 + C * j, 10'd36 + 18 * row, table_names[18 * row + 6 * j +: 6], 2'd0,
                         (highlight == row) ? ACCENT : WHITE);
                digits7(10'd136, 10'd36 + 18 * row, table_bcd[28 * row +: 28], (highlight == row) ? ACCENT : WHITE);
                if (table_levels[4 * row +: 4] > 4'd7) begin
                    // scala finita: ALL
                    put(10'd216, 10'd36 + 18 * row, 6'd10, 2'd0, (highlight == row) ? ACCENT : GRAY);
                    put(10'd216 + C, 10'd36 + 18 * row, G_L, 2'd0, (highlight == row) ? ACCENT : GRAY);
                    put(10'd216 + 2 * C, 10'd36 + 18 * row, G_L, 2'd0, (highlight == row) ? ACCENT : GRAY);
                end else begin
                    put(10'd216, 10'd36 + 18 * row, G_L, 2'd0, (highlight == row) ? ACCENT : GRAY);
                    put(10'd216 + C, 10'd36 + 18 * row, {2'd0, table_levels[4 * row +: 4]}, 2'd0,
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
