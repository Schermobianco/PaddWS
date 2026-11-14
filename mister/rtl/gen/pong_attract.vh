// Generato da tools/gen_attract_assets.py: non modificare a mano.

localparam integer AT_BOOT_FRAMES = 288;
localparam integer AT_STRIPES_FRAMES = 144;
localparam integer AT_LOGO_FRAMES = 132;
localparam integer AT_TITLE_FRAMES = 480;
localparam integer AT_DEMO_FRAMES = 1200;
localparam integer AT_GAME_OVER_FRAMES = 180;
localparam integer AT_BOOT_X = 40;
localparam integer AT_BOOT_Y = 60;
localparam integer AT_BOOT_STEP = 14;
localparam integer AT_BOOT_LINE_FRAMES = 30;
localparam integer AT_BOOT_GRID_FROM = 228;
localparam integer AT_BOOT_LINE_RECIP = 2185;
localparam integer AT_STRIPE_START_STEP = 12;
localparam integer AT_SLIDE_LAST = 42;
localparam integer AT_STRIPE_H = 12;
localparam integer AT_LOGO_X = 82;
localparam integer AT_LOGO_Y = 94;
localparam integer AT_WIPE_FRAMES = 84;
localparam integer AT_FLASH_FRAMES = 3;
localparam integer AT_WS_X = 241;
localparam integer AT_WS_Y = 136;
localparam integer AT_LABEL_Y = 172;
localparam integer AT_CREDIT_Y = 204;
localparam integer AT_COPYRIGHT_Y = 222;
localparam integer AT_LABEL_FROM = 54;
localparam integer AT_BLINK_PERIOD = 60;
localparam integer AT_BLINK_ON = 37;
localparam integer AT_DEMO_LABEL_Y = 112;
localparam integer AT_GAME_OVER_Y = 112;
localparam integer AT_WINNER_Y = 132;
localparam integer AT_GAME_OVER_BLACK = 120;
localparam integer AT_STRIPE_ROW_0 = 96;
localparam integer AT_STRIPE_ROW_1 = 115;
localparam integer AT_STRIPE_ROW_2 = 134;
localparam integer AT_WS_OFF0_A = 0, AT_WS_OFF0_B = 15, AT_WS_OFF1_A = 30, AT_WS_OFF1_B = 45;
function [8:0] stripe_left_end(input [5:0] i);
    case (i)
        6'd0: stripe_left_end = 9'd0;
        6'd1: stripe_left_end = 9'd8;
        6'd2: stripe_left_end = 9'd15;
        6'd3: stripe_left_end = 9'd22;
        6'd4: stripe_left_end = 9'd29;
        6'd5: stripe_left_end = 9'd35;
        6'd6: stripe_left_end = 9'd40;
        6'd7: stripe_left_end = 9'd45;
        6'd8: stripe_left_end = 9'd50;
        6'd9: stripe_left_end = 9'd55;
        6'd10: stripe_left_end = 9'd58;
        6'd11: stripe_left_end = 9'd62;
        6'd12: stripe_left_end = 9'd65;
        6'd13: stripe_left_end = 9'd68;
        6'd14: stripe_left_end = 9'd71;
        6'd15: stripe_left_end = 9'd73;
        6'd16: stripe_left_end = 9'd75;
        6'd17: stripe_left_end = 9'd76;
        6'd18: stripe_left_end = 9'd78;
        6'd19: stripe_left_end = 9'd78;
        6'd20: stripe_left_end = 9'd78;
        6'd21: stripe_left_end = 9'd78;
        6'd22: stripe_left_end = 9'd78;
        6'd23: stripe_left_end = 9'd78;
        6'd24: stripe_left_end = 9'd78;
        6'd25: stripe_left_end = 9'd78;
        6'd26: stripe_left_end = 9'd78;
        6'd27: stripe_left_end = 9'd78;
        6'd28: stripe_left_end = 9'd78;
        6'd29: stripe_left_end = 9'd78;
        6'd30: stripe_left_end = 9'd78;
        6'd31: stripe_left_end = 9'd78;
        6'd32: stripe_left_end = 9'd78;
        6'd33: stripe_left_end = 9'd78;
        6'd34: stripe_left_end = 9'd78;
        6'd35: stripe_left_end = 9'd77;
        6'd36: stripe_left_end = 9'd77;
        6'd37: stripe_left_end = 9'd76;
        6'd38: stripe_left_end = 9'd76;
        6'd39: stripe_left_end = 9'd76;
        6'd40: stripe_left_end = 9'd75;
        6'd41: stripe_left_end = 9'd75;
        6'd42: stripe_left_end = 9'd75;
        default: stripe_left_end = 9'd75;
    endcase
endfunction
function [8:0] stripe_right_start(input [5:0] i);
    case (i)
        6'd0: stripe_right_start = 9'd320;
        6'd1: stripe_right_start = 9'd312;
        6'd2: stripe_right_start = 9'd304;
        6'd3: stripe_right_start = 9'd296;
        6'd4: stripe_right_start = 9'd290;
        6'd5: stripe_right_start = 9'd283;
        6'd6: stripe_right_start = 9'd277;
        6'd7: stripe_right_start = 9'd272;
        6'd8: stripe_right_start = 9'd267;
        6'd9: stripe_right_start = 9'd263;
        6'd10: stripe_right_start = 9'd258;
        6'd11: stripe_right_start = 9'd255;
        6'd12: stripe_right_start = 9'd251;
        6'd13: stripe_right_start = 9'd248;
        6'd14: stripe_right_start = 9'd246;
        6'd15: stripe_right_start = 9'd243;
        6'd16: stripe_right_start = 9'd241;
        6'd17: stripe_right_start = 9'd239;
        6'd18: stripe_right_start = 9'd238;
        6'd19: stripe_right_start = 9'd238;
        6'd20: stripe_right_start = 9'd238;
        6'd21: stripe_right_start = 9'd238;
        6'd22: stripe_right_start = 9'd238;
        6'd23: stripe_right_start = 9'd238;
        6'd24: stripe_right_start = 9'd238;
        6'd25: stripe_right_start = 9'd238;
        6'd26: stripe_right_start = 9'd238;
        6'd27: stripe_right_start = 9'd238;
        6'd28: stripe_right_start = 9'd238;
        6'd29: stripe_right_start = 9'd238;
        6'd30: stripe_right_start = 9'd238;
        6'd31: stripe_right_start = 9'd238;
        6'd32: stripe_right_start = 9'd238;
        6'd33: stripe_right_start = 9'd238;
        6'd34: stripe_right_start = 9'd238;
        6'd35: stripe_right_start = 9'd238;
        6'd36: stripe_right_start = 9'd239;
        6'd37: stripe_right_start = 9'd240;
        6'd38: stripe_right_start = 9'd240;
        6'd39: stripe_right_start = 9'd240;
        6'd40: stripe_right_start = 9'd241;
        6'd41: stripe_right_start = 9'd241;
        6'd42: stripe_right_start = 9'd241;
        default: stripe_right_start = 9'd241;
    endcase
endfunction
function [8:0] logo_wipe_rows(input [6:0] i);
    case (i)
        7'd0: logo_wipe_rows = 9'd0;
        7'd1: logo_wipe_rows = 9'd0;
        7'd2: logo_wipe_rows = 9'd1;
        7'd3: logo_wipe_rows = 9'd1;
        7'd4: logo_wipe_rows = 9'd2;
        7'd5: logo_wipe_rows = 9'd3;
        7'd6: logo_wipe_rows = 9'd3;
        7'd7: logo_wipe_rows = 9'd4;
        7'd8: logo_wipe_rows = 9'd4;
        7'd9: logo_wipe_rows = 9'd5;
        7'd10: logo_wipe_rows = 9'd6;
        7'd11: logo_wipe_rows = 9'd6;
        7'd12: logo_wipe_rows = 9'd7;
        7'd13: logo_wipe_rows = 9'd7;
        7'd14: logo_wipe_rows = 9'd8;
        7'd15: logo_wipe_rows = 9'd9;
        7'd16: logo_wipe_rows = 9'd9;
        7'd17: logo_wipe_rows = 9'd10;
        7'd18: logo_wipe_rows = 9'd10;
        7'd19: logo_wipe_rows = 9'd11;
        7'd20: logo_wipe_rows = 9'd12;
        7'd21: logo_wipe_rows = 9'd12;
        7'd22: logo_wipe_rows = 9'd13;
        7'd23: logo_wipe_rows = 9'd13;
        7'd24: logo_wipe_rows = 9'd14;
        7'd25: logo_wipe_rows = 9'd15;
        7'd26: logo_wipe_rows = 9'd15;
        7'd27: logo_wipe_rows = 9'd16;
        7'd28: logo_wipe_rows = 9'd17;
        7'd29: logo_wipe_rows = 9'd17;
        7'd30: logo_wipe_rows = 9'd18;
        7'd31: logo_wipe_rows = 9'd18;
        7'd32: logo_wipe_rows = 9'd19;
        7'd33: logo_wipe_rows = 9'd20;
        7'd34: logo_wipe_rows = 9'd20;
        7'd35: logo_wipe_rows = 9'd21;
        7'd36: logo_wipe_rows = 9'd21;
        7'd37: logo_wipe_rows = 9'd22;
        7'd38: logo_wipe_rows = 9'd23;
        7'd39: logo_wipe_rows = 9'd23;
        7'd40: logo_wipe_rows = 9'd24;
        7'd41: logo_wipe_rows = 9'd24;
        7'd42: logo_wipe_rows = 9'd25;
        7'd43: logo_wipe_rows = 9'd26;
        7'd44: logo_wipe_rows = 9'd26;
        7'd45: logo_wipe_rows = 9'd27;
        7'd46: logo_wipe_rows = 9'd27;
        7'd47: logo_wipe_rows = 9'd28;
        7'd48: logo_wipe_rows = 9'd29;
        7'd49: logo_wipe_rows = 9'd29;
        7'd50: logo_wipe_rows = 9'd30;
        7'd51: logo_wipe_rows = 9'd30;
        7'd52: logo_wipe_rows = 9'd31;
        7'd53: logo_wipe_rows = 9'd32;
        7'd54: logo_wipe_rows = 9'd32;
        7'd55: logo_wipe_rows = 9'd33;
        7'd56: logo_wipe_rows = 9'd34;
        7'd57: logo_wipe_rows = 9'd34;
        7'd58: logo_wipe_rows = 9'd35;
        7'd59: logo_wipe_rows = 9'd35;
        7'd60: logo_wipe_rows = 9'd36;
        7'd61: logo_wipe_rows = 9'd37;
        7'd62: logo_wipe_rows = 9'd37;
        7'd63: logo_wipe_rows = 9'd38;
        7'd64: logo_wipe_rows = 9'd38;
        7'd65: logo_wipe_rows = 9'd39;
        7'd66: logo_wipe_rows = 9'd40;
        7'd67: logo_wipe_rows = 9'd40;
        7'd68: logo_wipe_rows = 9'd41;
        7'd69: logo_wipe_rows = 9'd41;
        7'd70: logo_wipe_rows = 9'd42;
        7'd71: logo_wipe_rows = 9'd43;
        7'd72: logo_wipe_rows = 9'd43;
        7'd73: logo_wipe_rows = 9'd44;
        7'd74: logo_wipe_rows = 9'd44;
        7'd75: logo_wipe_rows = 9'd45;
        7'd76: logo_wipe_rows = 9'd46;
        7'd77: logo_wipe_rows = 9'd46;
        7'd78: logo_wipe_rows = 9'd47;
        7'd79: logo_wipe_rows = 9'd47;
        7'd80: logo_wipe_rows = 9'd48;
        7'd81: logo_wipe_rows = 9'd49;
        7'd82: logo_wipe_rows = 9'd49;
        7'd83: logo_wipe_rows = 9'd50;
        default: logo_wipe_rows = 9'd50;
    endcase
endfunction

localparam LOGO_W = 152;
localparam LOGO_H = 51;
function [151:0] logo_row(input [5:0] row);
    case (row)
        6'd1: logo_row = 152'b00000000000000000000000000000000000000000000000000111110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
        6'd2: logo_row = 152'b11111111111111111100000000000000000000000000001111111111111000000000000000011111111111111000000000000000000000000000111111111111100000000000000000000000;
        6'd3: logo_row = 152'b11111111111111111111110000000000000000000000111111111111111110000000000000011111111111111111100000000000000000000000111111111111111111000000000000000000;
        6'd4: logo_row = 152'b11111111111111111111111100000000000000000011111111111111111111000000000000011111111111111111111100000000000000000000111111111111111111111000000000000000;
        6'd5: logo_row = 152'b11111111111111111111111110000000000000000111111111111111111111110000000000011111111111111111111111000000000000000000111111111111111111111110000000000000;
        6'd6: logo_row = 152'b11111111111111111111111111000000000000001111111111111111111111111000000000011111111111111111111111110000000000000000111111111111111111111111100000000000;
        6'd7: logo_row = 152'b11111111111111111111111111100000000000011111111111111111111111111100000000011111111111111111111111111000000000000000111111111111111111111111110000000000;
        6'd8: logo_row = 152'b11111111111111111111111111110000000000111111111111111111111111111110000000011111111111111111111111111110000000000000111111111111111111111111111000000000;
        6'd9: logo_row = 152'b11111111111111111111111111111000000001111111111111111111111111111110000000011111111111111111111111111111000000000000111111111111111111111111111100000000;
        6'd10: logo_row = 152'b11111111111111111111111111111000000001111111111111111111111111111111000000011111111111111111111111111111100000000000111111111111111111111111111110000000;
        6'd11: logo_row = 152'b11111111111111111111111111111100000011111111111111000011111111111111000000011111111111111111111111111111110000000000111111111111111111111111111111000000;
        6'd12: logo_row = 152'b11111111110000000001111111111100000011111111111100000000011111111111100000011111111110000111111111111111111000000000111111111100011111111111111111100000;
        6'd13: logo_row = 152'b11111111110000000000111111111100000111111111111000000000001111111111100000011111111110000000111111111111111000000000111111111100000001111111111111110000;
        6'd14: logo_row = 152'b11111111110000000000011111111110000111111111110000000000000111111111110000011111111110000000001111111111111100000000111111111100000000011111111111111000;
        6'd15: logo_row = 152'b11111111110000000000001111111110000111111111100000000000000111111111110000011111111110000000000011111111111110000000111111111100000000001111111111111000;
        6'd16: logo_row = 152'b11111111110000000000001111111110000111111111100000000000000011111111110000011111111110000000000001111111111110000000111111111100000000000111111111111100;
        6'd17: logo_row = 152'b11111111110000000000001111111110001111111111000000000000000011111111110000011111111110000000000000111111111111000000111111111100000000000011111111111100;
        6'd18: logo_row = 152'b11111111110000000000001111111110001111111111000000000000000011111111110000011111111110000000000000011111111111000000111111111100000000000001111111111110;
        6'd19: logo_row = 152'b11111111110000000000001111111110001111111111000000000000000011111111110000011111111110000000000000001111111111000000111111111100000000000000111111111110;
        6'd20: logo_row = 152'b11111111110000000000011111111110001111111111000000000000000011111111110000011111111110000000000000001111111111100000111111111100000000000000011111111110;
        6'd21: logo_row = 152'b11111111110000000000111111111100001111111111000000000000000011111111110000011111111110000000000000000111111111100000111111111100000000000000011111111111;
        6'd22: logo_row = 152'b11111111110000000001111111111100001111111111000000000000000011111111110000011111111110000000000000000111111111100000111111111100000000000000001111111111;
        6'd23: logo_row = 152'b11111111111111111111111111111100001111111111111111111111111111111111110000011111111110000000000000000111111111100000111111111100000000000000001111111111;
        6'd24: logo_row = 152'b11111111111111111111111111111000001111111111111111111111111111111111110000011111111110000000000000000011111111110000111111111100000000000000001111111111;
        6'd25: logo_row = 152'b11111111111111111111111111111000001111111111111111111111111111111111110000011111111110000000000000000011111111110000111111111100000000000000001111111111;
        6'd26: logo_row = 152'b11111111111111111111111111110000001111111111111111111111111111111111110000011111111110000000000000000011111111110000111111111100000000000000001111111111;
        6'd27: logo_row = 152'b11111111111111111111111111100000001111111111111111111111111111111111110000011111111110000000000000000011111111110000111111111100000000000000001111111111;
        6'd28: logo_row = 152'b11111111111111111111111111000000001111111111111111111111111111111111110000011111111110000000000000000011111111110000111111111100000000000000001111111111;
        6'd29: logo_row = 152'b11111111111111111111111110000000001111111111111111111111111111111111110000011111111110000000000000000011111111110000111111111100000000000000001111111111;
        6'd30: logo_row = 152'b11111111111111111111111100000000001111111111111111111111111111111111110000011111111110000000000000000111111111100000111111111100000000000000001111111111;
        6'd31: logo_row = 152'b11111111111111111111110000000000001111111111111111111111111111111111110000011111111110000000000000000111111111100000111111111100000000000000001111111111;
        6'd32: logo_row = 152'b11111111111111111100000000000000001111111111111111111111111111111111110000011111111110000000000000000111111111100000111111111100000000000000011111111111;
        6'd33: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111110000000000000001111111111100000111111111100000000000000011111111110;
        6'd34: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111110000000000000001111111111000000111111111100000000000000111111111110;
        6'd35: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111110000000000000011111111111000000111111111100000000000001111111111110;
        6'd36: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111110000000000000111111111111000000111111111100000000000011111111111100;
        6'd37: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111110000000000001111111111110000000111111111100000000000111111111111100;
        6'd38: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111110000000000011111111111110000000111111111100000000001111111111111000;
        6'd39: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111110000000001111111111111100000000111111111100000000011111111111111000;
        6'd40: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111110000000111111111111111000000000111111111100000001111111111111110000;
        6'd41: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111110000111111111111111111000000000111111111100011111111111111111100000;
        6'd42: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111111111111111111111111110000000000111111111111111111111111111111000000;
        6'd43: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111111111111111111111111100000000000111111111111111111111111111110000000;
        6'd44: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111111111111111111111111000000000000111111111111111111111111111100000000;
        6'd45: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111111111111111111111110000000000000111111111111111111111111111000000000;
        6'd46: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111111111111111111111000000000000000111111111111111111111111110000000000;
        6'd47: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111111111111111111110000000000000000111111111111111111111111100000000000;
        6'd48: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111111111111111111000000000000000000111111111111111111111110000000000000;
        6'd49: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111111111111111100000000000000000000111111111111111111111000000000000000;
        6'd50: logo_row = 152'b11111111110000000000000000000000001111111111000000000000000011111111110000011111111111111111100000000000000000000000111111111111111111000000000000000000;
        default: logo_row = 152'd0;
    endcase
endfunction
function logo_lit(input [9:0] dx, input [9:0] dy);
    reg [151:0] r;
    begin
        r = logo_row(dy[5:0]);
        logo_lit = (dx < 152 && dy < 51) ? r[151 - dx] : 1'b0;
    end
endfunction

localparam WS_W = 22;
localparam WS_H = 8;
function [21:0] ws_row(input [2:0] row);
    case (row)
        3'd0: ws_row = 22'b0011000011001111100000;
        3'd1: ws_row = 22'b0011000011011100110000;
        3'd2: ws_row = 22'b0011001011011100000000;
        3'd3: ws_row = 22'b0011111111001111110000;
        3'd4: ws_row = 22'b0011111111000000010000;
        3'd5: ws_row = 22'b0011111111000000011100;
        3'd6: ws_row = 22'b0011100111011100011100;
        3'd7: ws_row = 22'b0011000011001111111000;
        default: ws_row = 22'd0;
    endcase
endfunction
function ws_lit(input [9:0] dx, input [9:0] dy);
    reg [21:0] r;
    begin
        r = ws_row(dy[2:0]);
        ws_lit = (dx < 22 && dy < 8) ? r[21 - dx] : 1'b0;
    end
endfunction

localparam INSERT_COIN_W = 43;
localparam INSERT_COIN_H = 7;
function [42:0] insert_coin_row(input [2:0] row);
    case (row)
        3'd0: insert_coin_row = 43'b1010010011011101110011100000110011001010010;
        3'd1: insert_coin_row = 43'b1010010100010001001001000001000100101010010;
        3'd2: insert_coin_row = 43'b1011010100010001001001000001000100101011010;
        3'd3: insert_coin_row = 43'b1010110010011101110001000001000100101010110;
        3'd4: insert_coin_row = 43'b1010010001010001001001000001000100101010010;
        3'd5: insert_coin_row = 43'b1010010001010001001001000001000100101010010;
        3'd6: insert_coin_row = 43'b1010010110011101001001000000110011001010010;
        default: insert_coin_row = 43'd0;
    endcase
endfunction
function insert_coin_lit(input [9:0] dx, input [9:0] dy);
    reg [42:0] r;
    begin
        r = insert_coin_row(dy[2:0]);
        insert_coin_lit = (dx < 43 && dy < 7) ? r[42 - dx] : 1'b0;
    end
endfunction

localparam PRESS_START_W = 47;
localparam PRESS_START_H = 7;
function [46:0] press_start_row(input [2:0] row);
    case (row)
        3'd0: press_start_row = 47'b11100111001110011001100000110111001100111001110;
        3'd1: press_start_row = 47'b10010100101000100010000001000010010010100100100;
        3'd2: press_start_row = 47'b10010100101000100010000001000010010010100100100;
        3'd3: press_start_row = 47'b11100111001110010001000000100010011110111000100;
        3'd4: press_start_row = 47'b10000100101000001000100000010010010010100100100;
        3'd5: press_start_row = 47'b10000100101000001000100000010010010010100100100;
        3'd6: press_start_row = 47'b10000100101110110011000001100010010010100100100;
        default: press_start_row = 47'd0;
    endcase
endfunction
function press_start_lit(input [9:0] dx, input [9:0] dy);
    reg [46:0] r;
    begin
        r = press_start_row(dy[2:0]);
        press_start_lit = (dx < 47 && dy < 7) ? r[46 - dx] : 1'b0;
    end
endfunction

localparam CREDIT_W = 27;
localparam CREDIT_H = 7;
function [26:0] credit_row(input [2:0] row);
    case (row)
        3'd0: credit_row = 27'b011011100111011100101110000;
        3'd1: credit_row = 27'b100010010100010010100100000;
        3'd2: credit_row = 27'b100010010100010010100100000;
        3'd3: credit_row = 27'b100011100111010010100100000;
        3'd4: credit_row = 27'b100010010100010010100100000;
        3'd5: credit_row = 27'b100010010100010010100100000;
        3'd6: credit_row = 27'b011010010111011100100100000;
        default: credit_row = 27'd0;
    endcase
endfunction
function credit_lit(input [9:0] dx, input [9:0] dy);
    reg [26:0] r;
    begin
        r = credit_row(dy[2:0]);
        credit_lit = (dx < 27 && dy < 7) ? r[26 - dx] : 1'b0;
    end
endfunction

localparam FREE_PLAY_W = 40;
localparam FREE_PLAY_H = 7;
function [39:0] free_play_row(input [2:0] row);
    case (row)
        3'd0: free_play_row = 40'b1110111001110111000011100100001100100010;
        3'd1: free_play_row = 40'b1000100101000100000010010100010010100010;
        3'd2: free_play_row = 40'b1000100101000100000010010100010010010100;
        3'd3: free_play_row = 40'b1110111001110111000011100100011110001000;
        3'd4: free_play_row = 40'b1000100101000100000010000100010010001000;
        3'd5: free_play_row = 40'b1000100101000100000010000100010010001000;
        3'd6: free_play_row = 40'b1000100101110111000010000111010010001000;
        default: free_play_row = 40'd0;
    endcase
endfunction
function free_play_lit(input [9:0] dx, input [9:0] dy);
    reg [39:0] r;
    begin
        r = free_play_row(dy[2:0]);
        free_play_lit = (dx < 40 && dy < 7) ? r[39 - dx] : 1'b0;
    end
endfunction

localparam COPYRIGHT_W = 91;
localparam COPYRIGHT_H = 7;
function [90:0] copyright_row(input [2:0] row);
    case (row)
        3'd0: copyright_row = 91'b0011100000011000110011000110000001100110100101110111001000100110011100100110010010011001100;
        3'd1: copyright_row = 91'b0100010000000101001000101000000010001000100101000100101000101001010010101001010010100010010;
        3'd2: copyright_row = 91'b1001101000000101001000101000000010001000100101000100101101101001010010101001011010100010010;
        3'd3: copyright_row = 91'b1010001000001001001001001110000001001000111101110111001010101001011100101111010110100010010;
        3'd4: copyright_row = 91'b1001101000010001001010001001000000101000100101000100101000101001010010101001010010100010010;
        3'd5: copyright_row = 91'b0100010000010001001010001001000000101000100101000100101000101001010010101001010010100010010;
        3'd6: copyright_row = 91'b0011100000011100110011100110000011000110100101110100101000100110011100101001010010011001100;
        default: copyright_row = 91'd0;
    endcase
endfunction
function copyright_lit(input [9:0] dx, input [9:0] dy);
    reg [90:0] r;
    begin
        r = copyright_row(dy[2:0]);
        copyright_lit = (dx < 91 && dy < 7) ? r[90 - dx] : 1'b0;
    end
endfunction

localparam GAME_OVER_W = 43;
localparam GAME_OVER_H = 7;
function [42:0] game_over_row(input [2:0] row);
    case (row)
        3'd0: game_over_row = 43'b0110001100100010111000001100100010111011100;
        3'd1: game_over_row = 43'b1000010010100010100000010010100010100010010;
        3'd2: game_over_row = 43'b1000010010110110100000010010100010100010010;
        3'd3: game_over_row = 43'b1011011110101010111000010010010100111011100;
        3'd4: game_over_row = 43'b1001010010100010100000010010010100100010010;
        3'd5: game_over_row = 43'b1001010010100010100000010010001000100010010;
        3'd6: game_over_row = 43'b0110010010100010111000001100001000111010010;
        default: game_over_row = 43'd0;
    endcase
endfunction
function game_over_lit(input [9:0] dx, input [9:0] dy);
    reg [42:0] r;
    begin
        r = game_over_row(dy[2:0]);
        game_over_lit = (dx < 43 && dy < 7) ? r[42 - dx] : 1'b0;
    end
endfunction

localparam P1_WINS_W = 28;
localparam P1_WINS_H = 7;
function [27:0] p1_wins_row(input [2:0] row);
    case (row)
        3'd0: p1_wins_row = 28'b1110001000010001010100100110;
        3'd1: p1_wins_row = 28'b1001011000010001010100101000;
        3'd2: p1_wins_row = 28'b1001001000010001010110101000;
        3'd3: p1_wins_row = 28'b1110001000010101010101100100;
        3'd4: p1_wins_row = 28'b1000001000011011010100100010;
        3'd5: p1_wins_row = 28'b1000001000010001010100100010;
        3'd6: p1_wins_row = 28'b1000001000010001010100101100;
        default: p1_wins_row = 28'd0;
    endcase
endfunction
function p1_wins_lit(input [9:0] dx, input [9:0] dy);
    reg [27:0] r;
    begin
        r = p1_wins_row(dy[2:0]);
        p1_wins_lit = (dx < 28 && dy < 7) ? r[27 - dx] : 1'b0;
    end
endfunction

localparam P2_WINS_W = 29;
localparam P2_WINS_H = 7;
function [28:0] p2_wins_row(input [2:0] row);
    case (row)
        3'd0: p2_wins_row = 29'b11100110000010001010100100110;
        3'd1: p2_wins_row = 29'b10010001000010001010100101000;
        3'd2: p2_wins_row = 29'b10010001000010001010110101000;
        3'd3: p2_wins_row = 29'b11100010000010101010101100100;
        3'd4: p2_wins_row = 29'b10000100000011011010100100010;
        3'd5: p2_wins_row = 29'b10000100000010001010100100010;
        3'd6: p2_wins_row = 29'b10000111000010001010100101100;
        default: p2_wins_row = 29'd0;
    endcase
endfunction
function p2_wins_lit(input [9:0] dx, input [9:0] dy);
    reg [28:0] r;
    begin
        r = p2_wins_row(dy[2:0]);
        p2_wins_lit = (dx < 29 && dy < 7) ? r[28 - dx] : 1'b0;
    end
endfunction

localparam YOU_WIN_W = 32;
localparam YOU_WIN_H = 7;
function [31:0] you_win_row(input [2:0] row);
    case (row)
        3'd0: you_win_row = 32'b10001001100100100001000101010010;
        3'd1: you_win_row = 32'b10001010010100100001000101010010;
        3'd2: you_win_row = 32'b01010010010100100001000101011010;
        3'd3: you_win_row = 32'b00100010010100100001010101010110;
        3'd4: you_win_row = 32'b00100010010100100001101101010010;
        3'd5: you_win_row = 32'b00100010010100100001000101010010;
        3'd6: you_win_row = 32'b00100001100011000001000101010010;
        default: you_win_row = 32'd0;
    endcase
endfunction
function you_win_lit(input [9:0] dx, input [9:0] dy);
    reg [31:0] r;
    begin
        r = you_win_row(dy[2:0]);
        you_win_lit = (dx < 32 && dy < 7) ? r[31 - dx] : 1'b0;
    end
endfunction

localparam CPU_WINS_W = 34;
localparam CPU_WINS_H = 7;
function [33:0] cpu_wins_row(input [2:0] row);
    case (row)
        3'd0: cpu_wins_row = 34'b0110111001001000010001010100100110;
        3'd1: cpu_wins_row = 34'b1000100101001000010001010100101000;
        3'd2: cpu_wins_row = 34'b1000100101001000010001010110101000;
        3'd3: cpu_wins_row = 34'b1000111001001000010101010101100100;
        3'd4: cpu_wins_row = 34'b1000100001001000011011010100100010;
        3'd5: cpu_wins_row = 34'b1000100001001000010001010100100010;
        3'd6: cpu_wins_row = 34'b0110100000110000010001010100101100;
        default: cpu_wins_row = 34'd0;
    endcase
endfunction
function cpu_wins_lit(input [9:0] dx, input [9:0] dy);
    reg [33:0] r;
    begin
        r = cpu_wins_row(dy[2:0]);
        cpu_wins_lit = (dx < 34 && dy < 7) ? r[33 - dx] : 1'b0;
    end
endfunction

localparam PERFECT_W = 30;
localparam PERFECT_H = 7;
function [29:0] perfect_row(input [2:0] row);
    case (row)
        3'd0: perfect_row = 30'b111001110111001110111001101110;
        3'd1: perfect_row = 30'b100101000100101000100010000100;
        3'd2: perfect_row = 30'b100101000100101000100010000100;
        3'd3: perfect_row = 30'b111001110111001110111010000100;
        3'd4: perfect_row = 30'b100001000100101000100010000100;
        3'd5: perfect_row = 30'b100001000100101000100010000100;
        3'd6: perfect_row = 30'b100001110100101000111001100100;
        default: perfect_row = 30'd0;
    endcase
endfunction
function perfect_lit(input [9:0] dx, input [9:0] dy);
    reg [29:0] r;
    begin
        r = perfect_row(dy[2:0]);
        perfect_lit = (dx < 30 && dy < 7) ? r[29 - dx] : 1'b0;
    end
endfunction

localparam BALLS_W = 25;
localparam BALLS_H = 7;
function [24:0] balls_row(input [2:0] row);
    case (row)
        3'd0: balls_row = 25'b1110001100100010000110000;
        3'd1: balls_row = 25'b1001010010100010001000000;
        3'd2: balls_row = 25'b1001010010100010001000000;
        3'd3: balls_row = 25'b1110011110100010000100000;
        3'd4: balls_row = 25'b1001010010100010000010000;
        3'd5: balls_row = 25'b1001010010100010000010000;
        3'd6: balls_row = 25'b1110010010111011101100000;
        default: balls_row = 25'd0;
    endcase
endfunction
function balls_lit(input [9:0] dx, input [9:0] dy);
    reg [24:0] r;
    begin
        r = balls_row(dy[2:0]);
        balls_lit = (dx < 25 && dy < 7) ? r[24 - dx] : 1'b0;
    end
endfunction

localparam MODE_CLASSIC_W = 27;
localparam MODE_CLASSIC_H = 7;
function [26:0] mode_classic_row(input [2:0] row);
    case (row)
        3'd0: mode_classic_row = 27'b011010000110001100110100110;
        3'd1: mode_classic_row = 27'b100010001001010001000101000;
        3'd2: mode_classic_row = 27'b100010001001010001000101000;
        3'd3: mode_classic_row = 27'b100010001111001000100101000;
        3'd4: mode_classic_row = 27'b100010001001000100010101000;
        3'd5: mode_classic_row = 27'b100010001001000100010101000;
        3'd6: mode_classic_row = 27'b011011101001011001100100110;
        default: mode_classic_row = 27'd0;
    endcase
endfunction
function mode_classic_lit(input [9:0] dx, input [9:0] dy);
    reg [26:0] r;
    begin
        r = mode_classic_row(dy[2:0]);
        mode_classic_lit = (dx < 27 && dy < 7) ? r[26 - dx] : 1'b0;
    end
endfunction

localparam MODE_EVO_W = 15;
localparam MODE_EVO_H = 7;
function [14:0] mode_evo_row(input [2:0] row);
    case (row)
        3'd0: mode_evo_row = 15'b111010001001100;
        3'd1: mode_evo_row = 15'b100010001010010;
        3'd2: mode_evo_row = 15'b100010001010010;
        3'd3: mode_evo_row = 15'b111001010010010;
        3'd4: mode_evo_row = 15'b100001010010010;
        3'd5: mode_evo_row = 15'b100000100010010;
        3'd6: mode_evo_row = 15'b111000100001100;
        default: mode_evo_row = 15'd0;
    endcase
endfunction
function mode_evo_lit(input [9:0] dx, input [9:0] dy);
    reg [14:0] r;
    begin
        r = mode_evo_row(dy[2:0]);
        mode_evo_lit = (dx < 15 && dy < 7) ? r[14 - dx] : 1'b0;
    end
endfunction

localparam MODE_NEXT_W = 19;
localparam MODE_NEXT_H = 7;
function [18:0] mode_next_row(input [2:0] row);
    case (row)
        3'd0: mode_next_row = 19'b1001011101000101110;
        3'd1: mode_next_row = 19'b1001010001000100100;
        3'd2: mode_next_row = 19'b1101010000101000100;
        3'd3: mode_next_row = 19'b1011011100010000100;
        3'd4: mode_next_row = 19'b1001010000101000100;
        3'd5: mode_next_row = 19'b1001010001000100100;
        3'd6: mode_next_row = 19'b1001011101000100100;
        default: mode_next_row = 19'd0;
    endcase
endfunction
function mode_next_lit(input [9:0] dx, input [9:0] dy);
    reg [18:0] r;
    begin
        r = mode_next_row(dy[2:0]);
        mode_next_lit = (dx < 19 && dy < 7) ? r[18 - dx] : 1'b0;
    end
endfunction

localparam MODE_CHALLENGE_W = 40;
localparam MODE_CHALLENGE_H = 7;
function [39:0] mode_challenge_row(input [2:0] row);
    case (row)
        3'd0: mode_challenge_row = 40'b0110100100110010001000111010010011001110;
        3'd1: mode_challenge_row = 40'b1000100101001010001000100010010100001000;
        3'd2: mode_challenge_row = 40'b1000100101001010001000100011010100001000;
        3'd3: mode_challenge_row = 40'b1000111101111010001000111010110101101110;
        3'd4: mode_challenge_row = 40'b1000100101001010001000100010010100101000;
        3'd5: mode_challenge_row = 40'b1000100101001010001000100010010100101000;
        3'd6: mode_challenge_row = 40'b0110100101001011101110111010010011001110;
        default: mode_challenge_row = 40'd0;
    endcase
endfunction
function mode_challenge_lit(input [9:0] dx, input [9:0] dy);
    reg [39:0] r;
    begin
        r = mode_challenge_row(dy[2:0]);
        mode_challenge_lit = (dx < 40 && dy < 7) ? r[39 - dx] : 1'b0;
    end
endfunction

localparam BOOT_0_W = 57;
localparam BOOT_0_H = 7;
function [56:0] boot_0_row(input [2:0] row);
    case (row)
        3'd0: boot_0_row = 57'b111000110011100111000001000100110000000100010100000001100;
        3'd1: boot_0_row = 57'b100101001010010100100001000101000000000100010100000010010;
        3'd2: boot_0_row = 57'b100101001010010100100001000101000000000100010101000010010;
        3'd3: boot_0_row = 57'b111001111010010100100001010100100000000010100101000010010;
        3'd4: boot_0_row = 57'b100001001010010100100001101100010000000010100111100010010;
        3'd5: boot_0_row = 57'b100001001010010100100001000100010000000001000001000010010;
        3'd6: boot_0_row = 57'b100001001011100111000001000101100000000001000001001001100;
        default: boot_0_row = 57'd0;
    endcase
endfunction
function boot_0_lit(input [9:0] dx, input [9:0] dy);
    reg [56:0] r;
    begin
        r = boot_0_row(dy[2:0]);
        boot_0_lit = (dx < 57 && dy < 7) ? r[56 - dx] : 1'b0;
    end
endfunction

localparam BOOT_2_W = 48;
localparam BOOT_2_H = 7;
function [47:0] boot_2_row(input [2:0] row);
    case (row)
        3'd0: boot_2_row = 48'b111000110010001000000000000000000000000110010010;
        3'd1: boot_2_row = 48'b100101001010001000000000000000000000001001010010;
        3'd2: boot_2_row = 48'b100101001011011000000000000000000000001001010100;
        3'd3: boot_2_row = 48'b111001111010101000000000000000000000001001011000;
        3'd4: boot_2_row = 48'b100101001010001000000000000000000000001001010100;
        3'd5: boot_2_row = 48'b100101001010001000000000000000000000001001010010;
        3'd6: boot_2_row = 48'b100101001010001000010101010101010100000110010010;
        default: boot_2_row = 48'd0;
    endcase
endfunction
function boot_2_lit(input [9:0] dx, input [9:0] dy);
    reg [47:0] r;
    begin
        r = boot_2_row(dy[2:0]);
        boot_2_lit = (dx < 48 && dy < 7) ? r[47 - dx] : 1'b0;
    end
endfunction

localparam BOOT_3_W = 48;
localparam BOOT_3_H = 7;
function [47:0] boot_3_row(input [2:0] row);
    case (row)
        3'd0: boot_3_row = 48'b111000110010001000000000000000000000000110010010;
        3'd1: boot_3_row = 48'b100101001010001000000000000000000000001001010010;
        3'd2: boot_3_row = 48'b100101001011011000000000000000000000001001010100;
        3'd3: boot_3_row = 48'b111001001010101000000000000000000000001001011000;
        3'd4: boot_3_row = 48'b100101001010001000000000000000000000001001010100;
        3'd5: boot_3_row = 48'b100101001010001000000000000000000000001001010010;
        3'd6: boot_3_row = 48'b100100110010001000010101010101010100000110010010;
        default: boot_3_row = 48'd0;
    endcase
endfunction
function boot_3_lit(input [9:0] dx, input [9:0] dy);
    reg [47:0] r;
    begin
        r = boot_3_row(dy[2:0]);
        boot_3_lit = (dx < 48 && dy < 7) ? r[47 - dx] : 1'b0;
    end
endfunction

localparam BOOT_4_W = 64;
localparam BOOT_4_H = 7;
function [63:0] boot_4_row(input [2:0] row);
    case (row)
        3'd0: boot_4_row = 64'b1000101011100111001100000110010000011001110000000000000110010010;
        3'd1: boot_4_row = 64'b1000101010010100010010000001010000100101001000000000001001010010;
        3'd2: boot_4_row = 64'b1000101010010100010010000001010100100101001000000000001001010100;
        3'd3: boot_4_row = 64'b0101001010010111010010000010010100100101110000000000001001011000;
        3'd4: boot_4_row = 64'b0101001010010100010010000100011110100101000000000000001001010100;
        3'd5: boot_4_row = 64'b0010001010010100010010000100000100100101000000000000001001010010;
        3'd6: boot_4_row = 64'b0010001011100111001100000111000100011001000000010100000110010010;
        default: boot_4_row = 64'd0;
    endcase
endfunction
function boot_4_lit(input [9:0] dx, input [9:0] dy);
    reg [63:0] r;
    begin
        r = boot_4_row(dy[2:0]);
        boot_4_lit = (dx < 64 && dy < 7) ? r[63 - dx] : 1'b0;
    end
endfunction

localparam BOOT_5_W = 50;
localparam BOOT_5_H = 7;
function [49:0] boot_5_row(input [2:0] row);
    case (row)
        3'd0: boot_5_row = 50'b01100100101110010011000000000000000000000110010010;
        3'd1: boot_5_row = 50'b10010100101001010100100000000000000000001001010010;
        3'd2: boot_5_row = 50'b10010100101001010100100000000000000000001001010100;
        3'd3: boot_5_row = 50'b11110100101001010100100000000000000000001001011000;
        3'd4: boot_5_row = 50'b10010100101001010100100000000000000000001001010100;
        3'd5: boot_5_row = 50'b10010100101001010100100000000000000000001001010010;
        3'd6: boot_5_row = 50'b10010011001110010011000001010101010100000110010010;
        default: boot_5_row = 50'd0;
    endcase
endfunction
function boot_5_lit(input [9:0] dx, input [9:0] dy);
    reg [49:0] r;
    begin
        r = boot_5_row(dy[2:0]);
        boot_5_lit = (dx < 50 && dy < 7) ? r[49 - dx] : 1'b0;
    end
endfunction

localparam GAME_OVER_LETTERS = 8;
function [5:0] game_over_l0(input [3:0] i);
    case (i)
        4'd0: game_over_l0 = 6'd0;
        4'd1: game_over_l0 = 6'd5;
        4'd2: game_over_l0 = 6'd10;
        4'd3: game_over_l0 = 6'd16;
        4'd4: game_over_l0 = 6'd23;
        4'd5: game_over_l0 = 6'd28;
        4'd6: game_over_l0 = 6'd34;
        4'd7: game_over_l0 = 6'd38;
        default: game_over_l0 = 6'd43;
    endcase
endfunction
function [5:0] game_over_l1(input [3:0] i);
    case (i)
        4'd0: game_over_l1 = 6'd4;
        4'd1: game_over_l1 = 6'd9;
        4'd2: game_over_l1 = 6'd15;
        4'd3: game_over_l1 = 6'd19;
        4'd4: game_over_l1 = 6'd27;
        4'd5: game_over_l1 = 6'd33;
        4'd6: game_over_l1 = 6'd37;
        4'd7: game_over_l1 = 6'd42;
        default: game_over_l1 = 6'd43;
    endcase
endfunction

localparam P1_WINS_LETTERS = 6;
function [5:0] p1_wins_l0(input [3:0] i);
    case (i)
        4'd0: p1_wins_l0 = 6'd0;
        4'd1: p1_wins_l0 = 6'd5;
        4'd2: p1_wins_l0 = 6'd11;
        4'd3: p1_wins_l0 = 6'd17;
        4'd4: p1_wins_l0 = 6'd19;
        4'd5: p1_wins_l0 = 6'd24;
        default: p1_wins_l0 = 6'd28;
    endcase
endfunction
function [5:0] p1_wins_l1(input [3:0] i);
    case (i)
        4'd0: p1_wins_l1 = 6'd4;
        4'd1: p1_wins_l1 = 6'd7;
        4'd2: p1_wins_l1 = 6'd16;
        4'd3: p1_wins_l1 = 6'd18;
        4'd4: p1_wins_l1 = 6'd23;
        4'd5: p1_wins_l1 = 6'd27;
        default: p1_wins_l1 = 6'd28;
    endcase
endfunction

localparam P2_WINS_LETTERS = 6;
function [5:0] p2_wins_l0(input [3:0] i);
    case (i)
        4'd0: p2_wins_l0 = 6'd0;
        4'd1: p2_wins_l0 = 6'd5;
        4'd2: p2_wins_l0 = 6'd12;
        4'd3: p2_wins_l0 = 6'd18;
        4'd4: p2_wins_l0 = 6'd20;
        4'd5: p2_wins_l0 = 6'd25;
        default: p2_wins_l0 = 6'd29;
    endcase
endfunction
function [5:0] p2_wins_l1(input [3:0] i);
    case (i)
        4'd0: p2_wins_l1 = 6'd4;
        4'd1: p2_wins_l1 = 6'd8;
        4'd2: p2_wins_l1 = 6'd17;
        4'd3: p2_wins_l1 = 6'd19;
        4'd4: p2_wins_l1 = 6'd24;
        4'd5: p2_wins_l1 = 6'd28;
        default: p2_wins_l1 = 6'd29;
    endcase
endfunction

localparam YOU_WIN_LETTERS = 6;
function [5:0] you_win_l0(input [3:0] i);
    case (i)
        4'd0: you_win_l0 = 6'd0;
        4'd1: you_win_l0 = 6'd6;
        4'd2: you_win_l0 = 6'd11;
        4'd3: you_win_l0 = 6'd19;
        4'd4: you_win_l0 = 6'd25;
        4'd5: you_win_l0 = 6'd27;
        default: you_win_l0 = 6'd32;
    endcase
endfunction
function [5:0] you_win_l1(input [3:0] i);
    case (i)
        4'd0: you_win_l1 = 6'd5;
        4'd1: you_win_l1 = 6'd10;
        4'd2: you_win_l1 = 6'd15;
        4'd3: you_win_l1 = 6'd24;
        4'd4: you_win_l1 = 6'd26;
        4'd5: you_win_l1 = 6'd31;
        default: you_win_l1 = 6'd32;
    endcase
endfunction

localparam CPU_WINS_LETTERS = 7;
function [5:0] cpu_wins_l0(input [3:0] i);
    case (i)
        4'd0: cpu_wins_l0 = 6'd0;
        4'd1: cpu_wins_l0 = 6'd4;
        4'd2: cpu_wins_l0 = 6'd9;
        4'd3: cpu_wins_l0 = 6'd17;
        4'd4: cpu_wins_l0 = 6'd23;
        4'd5: cpu_wins_l0 = 6'd25;
        4'd6: cpu_wins_l0 = 6'd30;
        default: cpu_wins_l0 = 6'd34;
    endcase
endfunction
function [5:0] cpu_wins_l1(input [3:0] i);
    case (i)
        4'd0: cpu_wins_l1 = 6'd3;
        4'd1: cpu_wins_l1 = 6'd8;
        4'd2: cpu_wins_l1 = 6'd13;
        4'd3: cpu_wins_l1 = 6'd22;
        4'd4: cpu_wins_l1 = 6'd24;
        4'd5: cpu_wins_l1 = 6'd29;
        4'd6: cpu_wins_l1 = 6'd33;
        default: cpu_wins_l1 = 6'd34;
    endcase
endfunction

localparam PERFECT_LETTERS = 7;
function [5:0] perfect_l0(input [3:0] i);
    case (i)
        4'd0: perfect_l0 = 6'd0;
        4'd1: perfect_l0 = 6'd5;
        4'd2: perfect_l0 = 6'd9;
        4'd3: perfect_l0 = 6'd14;
        4'd4: perfect_l0 = 6'd18;
        4'd5: perfect_l0 = 6'd22;
        4'd6: perfect_l0 = 6'd26;
        default: perfect_l0 = 6'd30;
    endcase
endfunction
function [5:0] perfect_l1(input [3:0] i);
    case (i)
        4'd0: perfect_l1 = 6'd4;
        4'd1: perfect_l1 = 6'd8;
        4'd2: perfect_l1 = 6'd13;
        4'd3: perfect_l1 = 6'd17;
        4'd4: perfect_l1 = 6'd21;
        4'd5: perfect_l1 = 6'd25;
        4'd6: perfect_l1 = 6'd29;
        default: perfect_l1 = 6'd30;
    endcase
endfunction
