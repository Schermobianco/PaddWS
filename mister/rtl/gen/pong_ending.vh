// Generato da tools/gen_ending_assets.py: non modificare a mano.
// Finale della CHALLENGE (ending_render.v): tempi in frame a 60 Hz, finestre della mappa, posizioni
// a 320x240, tabella dei fuochi d'artificio.
localparam integer END_LEN0 = 210;
localparam integer END_LEN1 = 540;
localparam integer END_LEN2 = 540;
localparam integer END_LEN3 = 420;
localparam integer END_LEN4 = 1526;
localparam integer END_LEN5 = 180;
localparam integer END_TOTAL = 3416;
localparam integer END_YOU_WIN_AT = 60;
localparam integer END_SKIP_AFTER = 30;
localparam integer END_BEAT = 30;   // sfilata: un avversario ogni 2 battute, il timbro alla seconda
localparam integer END_SCORE_COUNT = 180;
localparam integer END_BONUS_END = 240;
localparam integer END_TOTAL_AT = 270;
localparam integer END_FLASH0 = 30, END_FLASH5 = 40;
localparam integer END_TEXT_ROWS = 280, END_TEXT_BYTES = 5600;
localparam integer END_MAP_SIZE = 925;
localparam integer END_FW_SIZE = 7658;   // 6058 punti
localparam integer END_GLYPH_H = 7, END_CELL = 7;
localparam integer END_STRIP_ROW0 = 0, END_STAMP_ROW0 = 7;
localparam integer END_STAMP_W = 64, END_STAMP_H = 36, END_STAMP_Y0 = 82;
localparam integer END_DIG_X0 = 181;
localparam integer END_PARADE_Y = 92, END_PARADE_NAME_Y = 145;
localparam integer END_COL0 = 23;
localparam integer END_COL1 = 69;
localparam integer END_COL2 = 114;
localparam integer END_COL3 = 160;
localparam integer END_COL4 = 206;
localparam integer END_COL5 = 251;
localparam integer END_COL6 = 297;
localparam integer END_WIN0_TOP = 100, END_WIN0_H = 52, END_WIN0_BASE = 0;
localparam integer END_WIN1_TOP = 18, END_WIN1_H = 14, END_WIN1_BASE = 52;
localparam integer END_WIN2_TOP = 33, END_WIN2_H = 119, END_WIN2_BASE = 66;
localparam integer END_WIN3_TOP = 173, END_WIN3_H = 43, END_WIN3_BASE = 185;
localparam integer END_WIN5_TOP = 110, END_WIN5_H = 21, END_WIN5_BASE = 228;
localparam integer END_CRED_C0 = 275, END_CRED_LEN = 676, END_CRED_BASE = 249;
localparam integer END_CRED_SMAX = 820;
localparam integer END_FWS = 10, END_FW_STRIDE = 80;
// fuoco i: frame del lancio (a 15 Hz) e cella del punto dello scoppio (griglia 160x120)
function [6:0] fw_start(input [3:0] i);
    case (i)
        4'd0: fw_start = 7'd0;
        4'd1: fw_start = 7'd7;
        4'd2: fw_start = 7'd13;
        4'd3: fw_start = 7'd23;
        4'd4: fw_start = 7'd32;
        4'd5: fw_start = 7'd39;
        4'd6: fw_start = 7'd45;
        4'd7: fw_start = 7'd57;
        4'd8: fw_start = 7'd63;
        4'd9: fw_start = 7'd69;
        default: fw_start = 7'd127;
    endcase
endfunction
function [7:0] fw_cx(input [3:0] i);
    case (i)
        4'd0: fw_cx = 8'd80;   // ring
        4'd1: fw_cx = 8'd125;   // willow
        4'd2: fw_cx = 8'd114;   // palm
        4'd3: fw_cx = 8'd65;   // chrysanthemum
        4'd4: fw_cx = 8'd114;   // crackle
        4'd5: fw_cx = 8'd97;   // crossette
        4'd6: fw_cx = 8'd73;   // ring
        4'd7: fw_cx = 8'd62;   // willow
        4'd8: fw_cx = 8'd101;   // palm
        4'd9: fw_cx = 8'd85;   // chrysanthemum
        default: fw_cx = 8'd0;
    endcase
endfunction
function [6:0] fw_cy(input [3:0] i);
    case (i)
        4'd0: fw_cy = 7'd46;
        4'd1: fw_cy = 7'd36;
        4'd2: fw_cy = 7'd19;
        4'd3: fw_cy = 7'd50;
        4'd4: fw_cy = 7'd36;
        4'd5: fw_cy = 7'd35;
        4'd6: fw_cy = 7'd37;
        4'd7: fw_cy = 7'd49;
        4'd8: fw_cy = 7'd53;
        4'd9: fw_cy = 7'd57;
        default: fw_cy = 7'd0;
    endcase
endfunction
