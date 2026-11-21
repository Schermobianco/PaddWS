// Generato da tools/gen_ending_assets.py: non modificare a mano.
// Finale della CHALLENGE (ending_render.v): tempi in frame a 60 Hz, finestre della mappa, posizioni
// a 320x240, tabella dei fuochi d'artificio.
localparam integer END_LEN0 = 210;
localparam integer END_LEN1 = 540;
localparam integer END_LEN2 = 540;
localparam integer END_LEN3 = 420;
localparam integer END_LEN4 = 1526;
localparam integer END_LEN5 = 270;
localparam integer END_TOTAL = 3506;
localparam integer END_YOU_WIN_AT = 60;
localparam integer END_SKIP_AFTER = 30;
localparam integer END_BEAT = 30;   // sfilata: un avversario ogni 2 battute, il timbro alla seconda
localparam integer END_SCORE_COUNT = 180;
localparam integer END_BONUS_END = 240;
localparam integer END_TOTAL_AT = 270;
localparam integer END_FLASH0 = 30, END_FLASH5 = 40;
localparam integer END_TEXT_ROWS = 299, END_TEXT_BYTES = 11960;
localparam integer END_MAP_SIZE = 833;
localparam integer END_FW_SIZE = 11812;   // 9412 punti
localparam integer END_GLYPH_H = 8, END_CELL = 8;
localparam integer END_STRIP_ROW0 = 0, END_STAMP_ROW0 = 8;
localparam integer END_STAMP_W = 76, END_STAMP_H = 26;
localparam integer END_DIG_X0 = 199;
localparam integer END_PARADE_X0 = 8, END_PARADE_DX = 80, END_PARADE_W = 64, END_PARADE_H = 72;
localparam integer END_PARADE_ROW0 = 44, END_PARADE_ROW1 = 132, END_PARADE_NAME0 = 120, END_PARADE_NAME1 = 208;
localparam integer END_PARADE_STAMP_UP = 14;
localparam integer END_WIN0_TOP = 106, END_WIN0_H = 36, END_WIN0_BASE = 0;
localparam integer END_WIN1_TOP = 28, END_WIN1_H = 7, END_WIN1_BASE = 36;
localparam integer END_WIN2_TOP = 46, END_WIN2_H = 98, END_WIN2_BASE = 43;
localparam integer END_WIN3_TOP = 180, END_WIN3_H = 23, END_WIN3_BASE = 141;
localparam integer END_WIN5_TOP = 174, END_WIN5_H = 7, END_WIN5_BASE = 164;
localparam integer END_CRED_C0 = 281, END_CRED_LEN = 662, END_CRED_BASE = 171;
localparam integer END_CRED_SMAX = 820;
localparam integer END_FWS = 15, END_FW_STRIDE = 80;
// fuoco i: frame del lancio (a 15 Hz), cella dello scoppio (160x120) e tema colori (0..7)
function [6:0] fw_start(input [4:0] i);
    case (i)
        5'd0: fw_start = 7'd0;
        5'd1: fw_start = 7'd6;
        5'd2: fw_start = 7'd11;
        5'd3: fw_start = 7'd19;
        5'd4: fw_start = 7'd26;
        5'd5: fw_start = 7'd32;
        5'd6: fw_start = 7'd37;
        5'd7: fw_start = 7'd46;
        5'd8: fw_start = 7'd51;
        5'd9: fw_start = 7'd56;
        5'd10: fw_start = 7'd61;
        5'd11: fw_start = 7'd71;
        5'd12: fw_start = 7'd54;
        5'd13: fw_start = 7'd56;
        5'd14: fw_start = 7'd58;
        default: fw_start = 7'd127;
    endcase
endfunction
function [7:0] fw_cx(input [4:0] i);
    case (i)
        5'd0: fw_cx = 8'd80;   // ring
        5'd1: fw_cx = 8'd134;   // willow
        5'd2: fw_cx = 8'd121;   // palm
        5'd3: fw_cx = 8'd62;   // chrysanthemum
        5'd4: fw_cx = 8'd121;   // crackle
        5'd5: fw_cx = 8'd100;   // crossette
        5'd6: fw_cx = 8'd72;   // ring
        5'd7: fw_cx = 8'd59;   // willow
        5'd8: fw_cx = 8'd106;   // palm
        5'd9: fw_cx = 8'd86;   // chrysanthemum
        5'd10: fw_cx = 8'd30;   // crackle
        5'd11: fw_cx = 8'd104;   // crossette
        5'd12: fw_cx = 8'd38;   // chrysanthemum
        5'd13: fw_cx = 8'd80;   // willow
        5'd14: fw_cx = 8'd121;   // chrysanthemum
        default: fw_cx = 8'd0;
    endcase
endfunction
function [6:0] fw_cy(input [4:0] i);
    case (i)
        5'd0: fw_cy = 7'd45;
        5'd1: fw_cy = 7'd34;
        5'd2: fw_cy = 7'd16;
        5'd3: fw_cy = 7'd49;
        5'd4: fw_cy = 7'd35;
        5'd5: fw_cy = 7'd33;
        5'd6: fw_cy = 7'd36;
        5'd7: fw_cy = 7'd49;
        5'd8: fw_cy = 7'd53;
        5'd9: fw_cy = 7'd56;
        5'd10: fw_cy = 7'd36;
        5'd11: fw_cy = 7'd28;
        5'd12: fw_cy = 7'd24;
        5'd13: fw_cy = 7'd18;
        5'd14: fw_cy = 7'd24;
        default: fw_cy = 7'd0;
    endcase
endfunction
function [2:0] fw_theme(input [4:0] i);
    case (i)
        5'd0: fw_theme = 3'd0;
        5'd1: fw_theme = 3'd1;
        5'd2: fw_theme = 3'd2;
        5'd3: fw_theme = 3'd3;
        5'd4: fw_theme = 3'd4;
        5'd5: fw_theme = 3'd5;
        5'd6: fw_theme = 3'd6;
        5'd7: fw_theme = 3'd7;
        5'd8: fw_theme = 3'd0;
        5'd9: fw_theme = 3'd1;
        5'd10: fw_theme = 3'd2;
        5'd11: fw_theme = 3'd3;
        5'd12: fw_theme = 3'd0;
        5'd13: fw_theme = 3'd1;
        5'd14: fw_theme = 3'd4;
        default: fw_theme = 3'd0;
    endcase
endfunction
