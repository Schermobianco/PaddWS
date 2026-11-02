// Generato da tools/gen_howto_assets.py: non modificare a mano.
// Schermata HOW TO PLAY delle mosse speciali (howto_render.v).
localparam integer HT_TEXT_ROWS = 88;          // righe di 320 pixel in howto_text.hex
// howto_rows.hex: 1024 voci {controllo, y} -> bit 8 la riga ha scritte, bit 7-0 la riga
localparam integer HT_SPRITES = 10;            // celle 32x32 in howto_sprites.hex
localparam integer HT_SKIP_Y0 = 228, HT_SKIP_Y1 = 235;   // righe della scritta che lampeggia
// riquadri delle mosse (cornice da y0 - 4 a y0 + 62, da x = 8 a 311), riga del comando
localparam integer HT_BOX0_Y = 42, HT_BOX1_Y = 112, HT_CY0 = 86, HT_CY1 = 156;
// figurine: centro del disegno nella cella (AX, AY), larghezza della finestra di un posto
localparam integer HT_AX = 11, HT_AY = 16, HT_SLOT_W = 26;
// centri dei passi e del pulsante A: joystick (3 passi) e manopola (2 passi)
localparam integer HT_JOY_S0 = 30, HT_JOY_S1 = 64, HT_JOY_S2 = 98, HT_JOY_A = 146;
localparam integer HT_KNOB_S0 = 30, HT_KNOB_S1 = 64, HT_KNOB_A = 112;
// freccette tra i passi: colonna di sinistra (centro del passo + 15), righe da cy - 3
localparam integer HT_ARROW_DX = 15;
// legenda: centri dei pulsanti piccoli sulla riga HT_LEG_CY
localparam integer HT_LEG_CY = 205, HT_LEG_X0 = 22, HT_LEG_X1 = 75, HT_LEG_X2 = 133;
// figurine
localparam [3:0] HT_STICK_D = 4'd0;
localparam [3:0] HT_STICK_DF = 4'd1;
localparam [3:0] HT_STICK_F = 4'd2;
localparam [3:0] HT_SPIN_D = 4'd3;
localparam [3:0] HT_SPIN_U = 4'd4;
localparam [3:0] HT_BTN_A = 4'd5;
localparam [3:0] HT_BTN_A_DOWN = 4'd6;
localparam [3:0] HT_SMALL_0 = 4'd7;
localparam [3:0] HT_SMALL_1 = 4'd8;
localparam [3:0] HT_SMALL_2 = 4'd9;
// codici dei colori delle figurine (pallina, bordo della base e freccia della manopola: accesi o spenti)
localparam [3:0] HS_DARK = 4'd1;
localparam [3:0] HS_HOLE = 4'd2;
localparam [3:0] HS_SHAFT = 4'd3;
localparam [3:0] HS_BALL = 4'd4;
localparam [3:0] HS_BASE_EDGE = 4'd5;
localparam [3:0] HS_WHITE = 4'd6;
localparam [3:0] HS_RED = 4'd7;
localparam [3:0] HS_RED_DARK = 4'd8;
localparam [3:0] HS_RED_LIGHT = 4'd9;
localparam [3:0] HS_KNOB = 4'd10;
localparam [3:0] HS_KNOB_EDGE = 4'd11;
localparam [3:0] HS_KNOB_TOP = 4'd12;
localparam [3:0] HS_SPIN = 4'd13;
// freccetta tra i passi, 5x7 (bit 4 = colonna di sinistra)
function [4:0] ht_arrow_row(input [2:0] row);
    case (row)
        3'd0: ht_arrow_row = 5'b10000;
        3'd1: ht_arrow_row = 5'b11000;
        3'd2: ht_arrow_row = 5'b11110;
        3'd3: ht_arrow_row = 5'b11111;
        3'd4: ht_arrow_row = 5'b11110;
        3'd5: ht_arrow_row = 5'b11000;
        3'd6: ht_arrow_row = 5'b10000;
        default: ht_arrow_row = 5'd0;
    endcase
endfunction
