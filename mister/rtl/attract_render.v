// Disegno della sequenza attract: auto-test, strisce, logo, titolo (RGB a 24 bit).
//
// Tempi, posizioni e bitmap vengono da rtl/gen/pong_attract.vh, generato da
// tools/gen_attract_assets.py con gli stessi dati delle versioni Rust e Python.
// `solid` dice se il pixel è nero nella scena del titolo (pallina esclusa): pong_top lo
// usa durante la scansione per far rimbalzare la pallina contro tutto ciò che è nero.

`timescale 1ns / 1ps

module attract_render (
    input  wire        clk,
    input  wire [8:0]  hc,
    input  wire [8:0]  vc,
    input  wire [1:0]  phase,          // 0 auto-test, 1 strisce, 2 logo, 3 titolo
    input  wire [10:0] frame,          // frame dall'inizio della fase
    input  wire [5:0]  blink,          // frame % 60
    input  wire        free_play,
    input  wire [3:0]  credits,
    input  wire [8:0]  ball_x,         // pallina del titolo (angolo in alto a sinistra)
    input  wire [8:0]  ball_y,

    output reg  [23:0] rgb,
    output reg         solid
);

`include "pong_attract.vh"
`include "pong_fonts.vh"

localparam [23:0] YELLOW = 24'hFFD225, BLACK = 24'h000000, WHITE = 24'hFFFFFF, PHOSPHOR = 24'hD4F7C8;
localparam [1:0] P_BOOT = 2'd0, P_STRIPES = 2'd1, P_LOGO = 2'd2, P_TITLE = 2'd3;
localparam integer SCREEN_W = 320;

// testi centrati (scala 2 per la scritta lampeggiante)
localparam integer IC_X = (SCREEN_W - 2 * INSERT_COIN_W) / 2;
localparam integer PS_X = (SCREEN_W - 2 * PRESS_START_W) / 2;
localparam integer CR_X = (SCREEN_W - CREDIT_W - TEXT_W) / 2;       // "CREDIT " + una cifra
localparam integer FP_X = (SCREEN_W - FREE_PLAY_W) / 2;
localparam integer CP_X = (SCREEN_W - COPYRIGHT_W) / 2;

wire [9:0] x = {1'b0, hc};
wire [9:0] y = {1'b0, vc};

// ------------------------------------------------------ valori del frame

// posizione delle sei strisce: ognuna parte AT_STRIPE_START_STEP frame dopo la precedente
function [5:0] slide_step(input [10:0] f, input integer i);
    reg [10:0] local_f;
    begin
        local_f = (f > i * AT_STRIPE_START_STEP) ? f - i * AT_STRIPE_START_STEP : 11'd0;
        slide_step = (local_f > AT_SLIDE_LAST) ? AT_SLIDE_LAST : local_f[5:0];
    end
endfunction

reg [8:0] left_end [0:2];
reg [8:0] right_start [0:2];
reg [5:0] wipe_rows;
reg [2:0] boot_shown;          // ultima riga dell'auto-test già comparsa (0..5)
reg       cursor_on;
integer   i;

always @(posedge clk) begin
    if (hc == 9'd0 && vc == 9'd0) begin
        for (i = 0; i < 3; i = i + 1) begin
            left_end[i] <= (phase == P_STRIPES) ? stripe_left_end(slide_step(frame, 2 * i)) : 9'd75;
            right_start[i] <= (phase == P_STRIPES) ? stripe_right_start(slide_step(frame, 2 * i + 1)) : 9'd241;
        end
        wipe_rows <= (frame < AT_WIPE_FRAMES) ? logo_wipe_rows(frame[6:0]) : 6'd51;
        // frame / AT_BOOT_LINE_FRAMES e frame / 10 con moltiplicazione per il reciproco
        boot_shown <= ((frame * AT_BOOT_LINE_RECIP) >> 16) > 5 ? 3'd5 : (frame * AT_BOOT_LINE_RECIP) >> 16;
        cursor_on <= !(((frame * 24'd6554) >> 16) & 1);
    end
end

// ------------------------------------------------------------------ pixel

reg        in_stripe, ws_px, logo_px, label_px, credit_px, copy_px, ball_px, boot_px, cursor_px;
reg [9:0]  cursor_x;
reg [4:0]  digit_row;
reg [23:0] color;

function in_rows(input [9:0] yy, input integer row);
    in_rows = yy >= row && yy < row + AT_STRIPE_H;
endfunction

always @(*) begin
    // strisce: la sinistra arriva al bordo sinistro, la destra a quello destro
    in_stripe = (in_rows(y, AT_STRIPE_ROW_0) && (x < left_end[0] || x >= right_start[0])) ||
                (in_rows(y, AT_STRIPE_ROW_1) && (x < left_end[1] || x >= right_start[1])) ||
                (in_rows(y, AT_STRIPE_ROW_2) && (x < left_end[2] || x >= right_start[2]));
    ws_px = ws_lit(x - AT_WS_X, y - AT_WS_Y);
    logo_px = logo_lit(x - AT_LOGO_X, y - AT_LOGO_Y);

    // scritta lampeggiante del titolo
    label_px = frame > AT_LABEL_FROM && blink < AT_BLINK_ON &&
               ((!free_play && credits == 4'd0) ? insert_coin_lit((x - IC_X) >> 1, (y - AT_LABEL_Y) >> 1)
                                                : press_start_lit((x - PS_X) >> 1, (y - AT_LABEL_Y) >> 1));
    // "CREDIT n" o "FREE PLAY"
    digit_row = text_glyph(credits, y - AT_CREDIT_Y);
    if (free_play)
        credit_px = free_play_lit(x - FP_X, y - AT_CREDIT_Y);
    else
        credit_px = credit_lit(x - CR_X, y - AT_CREDIT_Y) ||
                    (x >= CR_X + CREDIT_W && x < CR_X + CREDIT_W + TEXT_W && y >= AT_CREDIT_Y && y < AT_CREDIT_Y + TEXT_H &&
                     digit_row[TEXT_W - 1 - (x - CR_X - CREDIT_W)]);
    copy_px = copyright_lit(x - CP_X, y - AT_COPYRIGHT_Y);
    ball_px = x >= ball_x && x < ball_x + 4 && y >= ball_y && y < ball_y + 4;

    // auto-test: una riga ogni 15 frame, cursore dopo l'ultima comparsa
    boot_px = boot_0_lit(x - AT_BOOT_X, y - AT_BOOT_Y) ||
              (boot_shown >= 3'd2 && boot_2_lit(x - AT_BOOT_X, y - (AT_BOOT_Y + 2 * AT_BOOT_STEP))) ||
              (boot_shown >= 3'd3 && boot_3_lit(x - AT_BOOT_X, y - (AT_BOOT_Y + 3 * AT_BOOT_STEP))) ||
              (boot_shown >= 3'd4 && boot_4_lit(x - AT_BOOT_X, y - (AT_BOOT_Y + 4 * AT_BOOT_STEP))) ||
              (boot_shown >= 3'd5 && boot_5_lit(x - AT_BOOT_X, y - (AT_BOOT_Y + 5 * AT_BOOT_STEP)));
    case (boot_shown)
        3'd0: cursor_x = AT_BOOT_X + BOOT_0_W + 2;
        3'd1: cursor_x = AT_BOOT_X + 2;                 // riga vuota
        3'd2: cursor_x = AT_BOOT_X + BOOT_2_W + 2;
        3'd3: cursor_x = AT_BOOT_X + BOOT_3_W + 2;
        3'd4: cursor_x = AT_BOOT_X + BOOT_4_W + 2;
        default: cursor_x = AT_BOOT_X + BOOT_5_W + 2;
    endcase
    cursor_px = cursor_on && x >= cursor_x && x < cursor_x + 5 &&
                y >= AT_BOOT_Y + boot_shown * AT_BOOT_STEP && y < AT_BOOT_Y + boot_shown * AT_BOOT_STEP + 8;

    case (phase)
        P_BOOT:
            if (frame < AT_BOOT_GRID_FROM)
                color = (boot_px || cursor_px) ? PHOSPHOR : BLACK;
            else                                         // reticolo di test dei vecchi cabinati
                color = (x[3:0] == 4'd0 || y[3:0] == 4'd0 || y == 10'd239) ? WHITE : BLACK;
        P_STRIPES:
            color = in_stripe ? BLACK : YELLOW;
        P_LOGO:
            if (frame >= AT_WIPE_FRAMES && frame < AT_WIPE_FRAMES + AT_FLASH_FRAMES)
                color = WHITE;                           // lampo
            else if (x >= AT_LOGO_X && x < AT_LOGO_X + LOGO_W && y == AT_LOGO_Y + wipe_rows + 1 && frame < AT_WIPE_FRAMES)
                color = WHITE;                           // il raster che scende
            else if ((in_stripe && !ws_px) || (logo_px && y < AT_LOGO_Y + wipe_rows))
                color = BLACK;
            else
                color = YELLOW;
        default: begin                                   // titolo
            if (in_stripe && !(ws_px && !((frame >= AT_WS_OFF0_A && frame < AT_WS_OFF0_B) ||
                                          (frame >= AT_WS_OFF1_A && frame < AT_WS_OFF1_B))))
                color = BLACK;
            else if (logo_px || label_px || credit_px || copy_px || ball_px)
                color = BLACK;
            else
                color = YELLOW;
        end
    endcase
end

always @(posedge clk) begin
    rgb <= color;
    solid <= phase == P_TITLE && ((in_stripe && !ws_px) || logo_px || label_px || credit_px || copy_px);
end

endmodule
