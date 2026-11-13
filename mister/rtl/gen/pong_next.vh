// Generato da tools/gen_next_assets.py: non modificare a mano.

// icone 9x9 dei bonus: riga `row` dell'icona `bonus` (bit 8 = colonna di sinistra)
function [8:0] icon_row(input [2:0] bonus, input [3:0] row);
    case ({bonus, row})
        {3'd0, 4'd0}: icon_row = 9'b100000001;
        {3'd0, 4'd1}: icon_row = 9'b100000001;
        {3'd0, 4'd2}: icon_row = 9'b100001001;
        {3'd0, 4'd3}: icon_row = 9'b100000101;
        {3'd0, 4'd4}: icon_row = 9'b101111111;
        {3'd0, 4'd5}: icon_row = 9'b100000101;
        {3'd0, 4'd6}: icon_row = 9'b100001001;
        {3'd0, 4'd7}: icon_row = 9'b100000001;
        {3'd0, 4'd8}: icon_row = 9'b100000001;
        {3'd1, 4'd0}: icon_row = 9'b000000110;
        {3'd1, 4'd1}: icon_row = 9'b000001100;
        {3'd1, 4'd2}: icon_row = 9'b000011000;
        {3'd1, 4'd3}: icon_row = 9'b000110000;
        {3'd1, 4'd4}: icon_row = 9'b001111110;
        {3'd1, 4'd5}: icon_row = 9'b000011000;
        {3'd1, 4'd6}: icon_row = 9'b000110000;
        {3'd1, 4'd7}: icon_row = 9'b001100000;
        {3'd1, 4'd8}: icon_row = 9'b011000000;
        {3'd2, 4'd0}: icon_row = 9'b111111111;
        {3'd2, 4'd1}: icon_row = 9'b010000010;
        {3'd2, 4'd2}: icon_row = 9'b001000100;
        {3'd2, 4'd3}: icon_row = 9'b000101000;
        {3'd2, 4'd4}: icon_row = 9'b000010000;
        {3'd2, 4'd5}: icon_row = 9'b000101000;
        {3'd2, 4'd6}: icon_row = 9'b001010100;
        {3'd2, 4'd7}: icon_row = 9'b010111010;
        {3'd2, 4'd8}: icon_row = 9'b111111111;
        {3'd3, 4'd0}: icon_row = 9'b000000111;
        {3'd3, 4'd1}: icon_row = 9'b000001111;
        {3'd3, 4'd2}: icon_row = 9'b000010111;
        {3'd3, 4'd3}: icon_row = 9'b000100000;
        {3'd3, 4'd4}: icon_row = 9'b001000000;
        {3'd3, 4'd5}: icon_row = 9'b001000000;
        {3'd3, 4'd6}: icon_row = 9'b001000000;
        {3'd3, 4'd7}: icon_row = 9'b000100000;
        {3'd3, 4'd8}: icon_row = 9'b000011110;
        {3'd4, 4'd0}: icon_row = 9'b001010100;
        {3'd4, 4'd2}: icon_row = 9'b100000001;
        {3'd4, 4'd4}: icon_row = 9'b100010001;
        {3'd4, 4'd6}: icon_row = 9'b100000001;
        {3'd4, 4'd8}: icon_row = 9'b001010100;
        {3'd5, 4'd0}: icon_row = 9'b100010001;
        {3'd5, 4'd1}: icon_row = 9'b010010010;
        {3'd5, 4'd2}: icon_row = 9'b001010100;
        {3'd5, 4'd3}: icon_row = 9'b000111000;
        {3'd5, 4'd4}: icon_row = 9'b111111111;
        {3'd5, 4'd5}: icon_row = 9'b000111000;
        {3'd5, 4'd6}: icon_row = 9'b001010100;
        {3'd5, 4'd7}: icon_row = 9'b010010010;
        {3'd5, 4'd8}: icon_row = 9'b100010001;
        {3'd6, 4'd0}: icon_row = 9'b001111100;
        {3'd6, 4'd1}: icon_row = 9'b010000010;
        {3'd6, 4'd2}: icon_row = 9'b100000001;
        {3'd6, 4'd3}: icon_row = 9'b100000001;
        {3'd6, 4'd4}: icon_row = 9'b111111111;
        {3'd6, 4'd5}: icon_row = 9'b100010001;
        {3'd6, 4'd6}: icon_row = 9'b100010001;
        {3'd6, 4'd7}: icon_row = 9'b010010010;
        {3'd6, 4'd8}: icon_row = 9'b001111100;
        {3'd7, 4'd0}: icon_row = 9'b001000000;
        {3'd7, 4'd1}: icon_row = 9'b010010000;
        {3'd7, 4'd2}: icon_row = 9'b100100000;
        {3'd7, 4'd3}: icon_row = 9'b101011110;
        {3'd7, 4'd4}: icon_row = 9'b101011111;
        {3'd7, 4'd5}: icon_row = 9'b101011110;
        {3'd7, 4'd6}: icon_row = 9'b100100000;
        {3'd7, 4'd7}: icon_row = 9'b010010000;
        {3'd7, 4'd8}: icon_row = 9'b001000000;
        default: icon_row = 9'd0;
    endcase
endfunction
function icon_lit(input [2:0] bonus, input [9:0] dx, input [9:0] dy);
    reg [8:0] r;
    begin
        r = icon_row(bonus, dy[3:0]);
        icon_lit = (dx < 9 && dy < 9) ? r[8 - dx] : 1'b0;
    end
endfunction

// segni 9x9 della mossa armata: riga `row` del segno della mossa `m` (0 STRAIGHT SHOT,
// 1 RISING STRIKE; bit 8 = colonna di sinistra, per il giocatore di sinistra)
function [8:0] special_row(input m, input [3:0] row);
    case ({m, row})
        {1'd0, 4'd0}: special_row = 9'b000010000;
        {1'd0, 4'd1}: special_row = 9'b000001000;
        {1'd0, 4'd2}: special_row = 9'b000000100;
        {1'd0, 4'd3}: special_row = 9'b000000010;
        {1'd0, 4'd4}: special_row = 9'b101111111;
        {1'd0, 4'd5}: special_row = 9'b000000010;
        {1'd0, 4'd6}: special_row = 9'b000000100;
        {1'd0, 4'd7}: special_row = 9'b000001000;
        {1'd0, 4'd8}: special_row = 9'b000010000;
        {1'd1, 4'd0}: special_row = 9'b000111111;
        {1'd1, 4'd1}: special_row = 9'b000000011;
        {1'd1, 4'd2}: special_row = 9'b000000101;
        {1'd1, 4'd3}: special_row = 9'b000001001;
        {1'd1, 4'd4}: special_row = 9'b000010001;
        {1'd1, 4'd5}: special_row = 9'b000100000;
        {1'd1, 4'd6}: special_row = 9'b001000000;
        {1'd1, 4'd7}: special_row = 9'b010000000;
        {1'd1, 4'd8}: special_row = 9'b100000000;
        default: special_row = 9'd0;
    endcase
endfunction
function special_lit(input m, input [9:0] dx, input [9:0] dy);
    reg [8:0] r;
    begin
        r = special_row(m, dy[3:0]);
        special_lit = (dx < 9 && dy < 9) ? r[8 - dx] : 1'b0;
    end
endfunction

function signed [9:0] sin_q8(input [5:0] i);
    case (i)
        6'd0: sin_q8 = 0;
        6'd1: sin_q8 = 25;
        6'd2: sin_q8 = 50;
        6'd3: sin_q8 = 74;
        6'd4: sin_q8 = 98;
        6'd5: sin_q8 = 121;
        6'd6: sin_q8 = 142;
        6'd7: sin_q8 = 162;
        6'd8: sin_q8 = 181;
        6'd9: sin_q8 = 198;
        6'd10: sin_q8 = 213;
        6'd11: sin_q8 = 226;
        6'd12: sin_q8 = 237;
        6'd13: sin_q8 = 245;
        6'd14: sin_q8 = 251;
        6'd15: sin_q8 = 255;
        6'd16: sin_q8 = 256;
        6'd17: sin_q8 = 255;
        6'd18: sin_q8 = 251;
        6'd19: sin_q8 = 245;
        6'd20: sin_q8 = 237;
        6'd21: sin_q8 = 226;
        6'd22: sin_q8 = 213;
        6'd23: sin_q8 = 198;
        6'd24: sin_q8 = 181;
        6'd25: sin_q8 = 162;
        6'd26: sin_q8 = 142;
        6'd27: sin_q8 = 121;
        6'd28: sin_q8 = 98;
        6'd29: sin_q8 = 74;
        6'd30: sin_q8 = 50;
        6'd31: sin_q8 = 25;
        6'd32: sin_q8 = 0;
        6'd33: sin_q8 = -25;
        6'd34: sin_q8 = -50;
        6'd35: sin_q8 = -74;
        6'd36: sin_q8 = -98;
        6'd37: sin_q8 = -121;
        6'd38: sin_q8 = -142;
        6'd39: sin_q8 = -162;
        6'd40: sin_q8 = -181;
        6'd41: sin_q8 = -198;
        6'd42: sin_q8 = -213;
        6'd43: sin_q8 = -226;
        6'd44: sin_q8 = -237;
        6'd45: sin_q8 = -245;
        6'd46: sin_q8 = -251;
        6'd47: sin_q8 = -255;
        6'd48: sin_q8 = -256;
        6'd49: sin_q8 = -255;
        6'd50: sin_q8 = -251;
        6'd51: sin_q8 = -245;
        6'd52: sin_q8 = -237;
        6'd53: sin_q8 = -226;
        6'd54: sin_q8 = -213;
        6'd55: sin_q8 = -198;
        6'd56: sin_q8 = -181;
        6'd57: sin_q8 = -162;
        6'd58: sin_q8 = -142;
        6'd59: sin_q8 = -121;
        6'd60: sin_q8 = -98;
        6'd61: sin_q8 = -74;
        6'd62: sin_q8 = -50;
        6'd63: sin_q8 = -25;
    endcase
endfunction

localparam NX_PICK_W = 58;
localparam NX_PICK_H = 9;
function [57:0] nx_pick_row(input [3:0] row);
    case (row)
        4'd1: nx_pick_row = 58'b1110010011010010000110000011100011001001010010011011100110;
        4'd2: nx_pick_row = 58'b1001010100010010000001000010010100101001010010100010001000;
        4'd3: nx_pick_row = 58'b1001010100010100000001000010010100101101010010100010001000;
        4'd4: nx_pick_row = 58'b1110010100011000000110000011100100101011010010010011100100;
        4'd5: nx_pick_row = 58'b1000010100010100000001000010010100101001010010001010000010;
        4'd6: nx_pick_row = 58'b1000010100010010000001000010010100101001010010001010000010;
        4'd7: nx_pick_row = 58'b1000010011010010000110000011100011001001001100110011101100;
        default: nx_pick_row = 58'd0;
    endcase
endfunction
function nx_pick_lit(input [9:0] dx, input [9:0] dy);
    reg [57:0] r;
    begin
        r = nx_pick_row(dy[3:0]);
        nx_pick_lit = (dx < 58 && dy < 9) ? r[57 - dx] : 1'b0;
    end
endfunction

localparam NX_READY_W = 27;
localparam NX_READY_H = 9;
function [26:0] nx_ready_row(input [3:0] row);
    case (row)
        4'd1: nx_ready_row = 27'b111001110011001110010001010;
        4'd2: nx_ready_row = 27'b100101000100101001010001010;
        4'd3: nx_ready_row = 27'b100101000100101001001010010;
        4'd4: nx_ready_row = 27'b111001110111101001000100010;
        4'd5: nx_ready_row = 27'b100101000100101001000100010;
        4'd6: nx_ready_row = 27'b100101000100101001000100000;
        4'd7: nx_ready_row = 27'b100101110100101110000100010;
        default: nx_ready_row = 27'd0;
    endcase
endfunction
function nx_ready_lit(input [9:0] dx, input [9:0] dy);
    reg [26:0] r;
    begin
        r = nx_ready_row(dy[3:0]);
        nx_ready_lit = (dx < 27 && dy < 9) ? r[26 - dx] : 1'b0;
    end
endfunction

localparam NX_P1_W = 8;
localparam NX_P1_H = 9;
function [7:0] nx_p1_row(input [3:0] row);
    case (row)
        4'd1: nx_p1_row = 8'b11100010;
        4'd2: nx_p1_row = 8'b10010110;
        4'd3: nx_p1_row = 8'b10010010;
        4'd4: nx_p1_row = 8'b11100010;
        4'd5: nx_p1_row = 8'b10000010;
        4'd6: nx_p1_row = 8'b10000010;
        4'd7: nx_p1_row = 8'b10000010;
        default: nx_p1_row = 8'd0;
    endcase
endfunction
function nx_p1_lit(input [9:0] dx, input [9:0] dy);
    reg [7:0] r;
    begin
        r = nx_p1_row(dy[3:0]);
        nx_p1_lit = (dx < 8 && dy < 9) ? r[7 - dx] : 1'b0;
    end
endfunction

localparam NX_P2_W = 9;
localparam NX_P2_H = 9;
function [8:0] nx_p2_row(input [3:0] row);
    case (row)
        4'd1: nx_p2_row = 9'b111001100;
        4'd2: nx_p2_row = 9'b100100010;
        4'd3: nx_p2_row = 9'b100100010;
        4'd4: nx_p2_row = 9'b111000100;
        4'd5: nx_p2_row = 9'b100001000;
        4'd6: nx_p2_row = 9'b100001000;
        4'd7: nx_p2_row = 9'b100001110;
        default: nx_p2_row = 9'd0;
    endcase
endfunction
function nx_p2_lit(input [9:0] dx, input [9:0] dy);
    reg [8:0] r;
    begin
        r = nx_p2_row(dy[3:0]);
        nx_p2_lit = (dx < 9 && dy < 9) ? r[8 - dx] : 1'b0;
    end
endfunction

localparam NX_CPU_W = 14;
localparam NX_CPU_H = 9;
function [13:0] nx_cpu_row(input [3:0] row);
    case (row)
        4'd1: nx_cpu_row = 14'b01101110010010;
        4'd2: nx_cpu_row = 14'b10001001010010;
        4'd3: nx_cpu_row = 14'b10001001010010;
        4'd4: nx_cpu_row = 14'b10001110010010;
        4'd5: nx_cpu_row = 14'b10001000010010;
        4'd6: nx_cpu_row = 14'b10001000010010;
        4'd7: nx_cpu_row = 14'b01101000001100;
        default: nx_cpu_row = 14'd0;
    endcase
endfunction
function nx_cpu_lit(input [9:0] dx, input [9:0] dy);
    reg [13:0] r;
    begin
        r = nx_cpu_row(dy[3:0]);
        nx_cpu_lit = (dx < 14 && dy < 9) ? r[13 - dx] : 1'b0;
    end
endfunction

localparam NX_OF3_W = 8;
localparam NX_OF3_H = 9;
function [7:0] nx_of3_row(input [3:0] row);
    case (row)
        4'd0: nx_of3_row = 8'b00100000;
        4'd1: nx_of3_row = 8'b00101100;
        4'd2: nx_of3_row = 8'b00100010;
        4'd3: nx_of3_row = 8'b01000010;
        4'd4: nx_of3_row = 8'b01001100;
        4'd5: nx_of3_row = 8'b01000010;
        4'd6: nx_of3_row = 8'b10000010;
        4'd7: nx_of3_row = 8'b10001100;
        4'd8: nx_of3_row = 8'b10000000;
        default: nx_of3_row = 8'd0;
    endcase
endfunction
function nx_of3_lit(input [9:0] dx, input [9:0] dy);
    reg [7:0] r;
    begin
        r = nx_of3_row(dy[3:0]);
        nx_of3_lit = (dx < 8 && dy < 9) ? r[7 - dx] : 1'b0;
    end
endfunction

localparam NX_CURSOR_W = 5;
localparam NX_CURSOR_H = 9;
function [4:0] nx_cursor_row(input [3:0] row);
    case (row)
        4'd3: nx_cursor_row = 5'b00100;
        4'd4: nx_cursor_row = 5'b00010;
        4'd5: nx_cursor_row = 5'b00100;
        default: nx_cursor_row = 5'd0;
    endcase
endfunction
function nx_cursor_lit(input [9:0] dx, input [9:0] dy);
    reg [4:0] r;
    begin
        r = nx_cursor_row(dy[3:0]);
        nx_cursor_lit = (dx < 5 && dy < 9) ? r[4 - dx] : 1'b0;
    end
endfunction

localparam NX_BANG_W = 2;
localparam NX_BANG_H = 9;
function [1:0] nx_bang_row(input [3:0] row);
    case (row)
        4'd1: nx_bang_row = 2'b10;
        4'd2: nx_bang_row = 2'b10;
        4'd3: nx_bang_row = 2'b10;
        4'd4: nx_bang_row = 2'b10;
        4'd5: nx_bang_row = 2'b10;
        4'd7: nx_bang_row = 2'b10;
        default: nx_bang_row = 2'd0;
    endcase
endfunction
function nx_bang_lit(input [9:0] dx, input [9:0] dy);
    reg [1:0] r;
    begin
        r = nx_bang_row(dy[3:0]);
        nx_bang_lit = (dx < 2 && dy < 9) ? r[1 - dx] : 1'b0;
    end
endfunction

localparam NX_NAME0_W = 35;
localparam NX_NAME0_H = 9;
function [34:0] nx_name0_row(input [3:0] row);
    case (row)
        4'd1: nx_name0_row = 35'b11101110100011101110001100111001110;
        4'd2: nx_name0_row = 35'b01001000100010001001010010100100100;
        4'd3: nx_name0_row = 35'b01001000100010001001010010100100100;
        4'd4: nx_name0_row = 35'b01001110100011101110010010111000100;
        4'd5: nx_name0_row = 35'b01001000100010001000010010100100100;
        4'd6: nx_name0_row = 35'b01001000100010001000010010100100100;
        4'd7: nx_name0_row = 35'b01001110111011101000001100100100100;
        default: nx_name0_row = 35'd0;
    endcase
endfunction
function nx_name0_lit(input [9:0] dx, input [9:0] dy);
    reg [34:0] r;
    begin
        r = nx_name0_row(dy[3:0]);
        nx_name0_lit = (dx < 35 && dy < 9) ? r[34 - dx] : 1'b0;
    end
endfunction

localparam NX_NAME1_W = 24;
localparam NX_NAME1_H = 9;
function [23:0] nx_name1_row(input [3:0] row);
    case (row)
        4'd1: nx_name1_row = 24'b011010001001100011010010;
        4'd2: nx_name1_row = 24'b100010001010010100010010;
        4'd3: nx_name1_row = 24'b100011011010010100010010;
        4'd4: nx_name1_row = 24'b010010101011110010011110;
        4'd5: nx_name1_row = 24'b001010001010010001010010;
        4'd6: nx_name1_row = 24'b001010001010010001010010;
        4'd7: nx_name1_row = 24'b110010001010010110010010;
        default: nx_name1_row = 24'd0;
    endcase
endfunction
function nx_name1_lit(input [9:0] dx, input [9:0] dy);
    reg [23:0] r;
    begin
        r = nx_name1_row(dy[3:0]);
        nx_name1_lit = (dx < 24 && dy < 9) ? r[23 - dx] : 1'b0;
    end
endfunction

localparam NX_NAME2_W = 19;
localparam NX_NAME2_H = 9;
function [18:0] nx_name2_row(input [3:0] row);
    case (row)
        4'd1: nx_name2_row = 19'b0110100001100100010;
        4'd2: nx_name2_row = 19'b1000100010010100010;
        4'd3: nx_name2_row = 19'b1000100010010100010;
        4'd4: nx_name2_row = 19'b0100100010010101010;
        4'd5: nx_name2_row = 19'b0010100010010110110;
        4'd6: nx_name2_row = 19'b0010100010010100010;
        4'd7: nx_name2_row = 19'b1100111001100100010;
        default: nx_name2_row = 19'd0;
    endcase
endfunction
function nx_name2_lit(input [9:0] dx, input [9:0] dy);
    reg [18:0] r;
    begin
        r = nx_name2_row(dy[3:0]);
        nx_name2_lit = (dx < 19 && dy < 9) ? r[18 - dx] : 1'b0;
    end
endfunction

localparam NX_NAME3_W = 24;
localparam NX_NAME3_H = 9;
function [23:0] nx_name3_row(input [3:0] row);
    case (row)
        4'd1: nx_name3_row = 24'b011010010111001000101110;
        4'd2: nx_name3_row = 24'b100010010100101000101000;
        4'd3: nx_name3_row = 24'b100010010100101000101000;
        4'd4: nx_name3_row = 24'b100010010111000101001110;
        4'd5: nx_name3_row = 24'b100010010100100101001000;
        4'd6: nx_name3_row = 24'b100010010100100010001000;
        4'd7: nx_name3_row = 24'b011001100100100010001110;
        default: nx_name3_row = 24'd0;
    endcase
endfunction
function nx_name3_lit(input [9:0] dx, input [9:0] dy);
    reg [23:0] r;
    begin
        r = nx_name3_row(dy[3:0]);
        nx_name3_lit = (dx < 24 && dy < 9) ? r[23 - dx] : 1'b0;
    end
endfunction

localparam NX_NAME4_W = 23;
localparam NX_NAME4_H = 9;
function [22:0] nx_name4_row(input [3:0] row);
    case (row)
        4'd1: nx_name4_row = 23'b01100100100110001101110;
        4'd2: nx_name4_row = 23'b10000100101001010000100;
        4'd3: nx_name4_row = 23'b10000100101001010000100;
        4'd4: nx_name4_row = 23'b10110111101001001000100;
        4'd5: nx_name4_row = 23'b10010100101001000100100;
        4'd6: nx_name4_row = 23'b10010100101001000100100;
        4'd7: nx_name4_row = 23'b01100100100110011000100;
        default: nx_name4_row = 23'd0;
    endcase
endfunction
function nx_name4_lit(input [9:0] dx, input [9:0] dy);
    reg [22:0] r;
    begin
        r = nx_name4_row(dy[3:0]);
        nx_name4_lit = (dx < 23 && dy < 9) ? r[22 - dx] : 1'b0;
    end
endfunction

localparam NX_NAME5_W = 23;
localparam NX_NAME5_H = 9;
function [22:0] nx_name5_row(input [3:0] row);
    case (row)
        4'd1: nx_name5_row = 23'b01101001011100111011100;
        4'd2: nx_name5_row = 23'b10001001010010100010010;
        4'd3: nx_name5_row = 23'b10001001010010100010010;
        4'd4: nx_name5_row = 23'b01001001011100111011100;
        4'd5: nx_name5_row = 23'b00101001010000100010010;
        4'd6: nx_name5_row = 23'b00101001010000100010010;
        4'd7: nx_name5_row = 23'b11000110010000111010010;
        default: nx_name5_row = 23'd0;
    endcase
endfunction
function nx_name5_lit(input [9:0] dx, input [9:0] dy);
    reg [22:0] r;
    begin
        r = nx_name5_row(dy[3:0]);
        nx_name5_lit = (dx < 23 && dy < 9) ? r[22 - dx] : 1'b0;
    end
endfunction

localparam NX_NAME6_W = 21;
localparam NX_NAME6_H = 9;
function [20:0] nx_name6_row(input [3:0] row);
    case (row)
        4'd1: nx_name6_row = 21'b011011101110111011100;
        4'd2: nx_name6_row = 21'b100001001000100010010;
        4'd3: nx_name6_row = 21'b100001001000100010010;
        4'd4: nx_name6_row = 21'b010001001110111011100;
        4'd5: nx_name6_row = 21'b001001001000100010010;
        4'd6: nx_name6_row = 21'b001001001000100010010;
        4'd7: nx_name6_row = 21'b110001001110111010010;
        default: nx_name6_row = 21'd0;
    endcase
endfunction
function nx_name6_lit(input [9:0] dx, input [9:0] dy);
    reg [20:0] r;
    begin
        r = nx_name6_row(dy[3:0]);
        nx_name6_lit = (dx < 21 && dy < 9) ? r[20 - dx] : 1'b0;
    end
endfunction

localparam NX_NAME7_W = 26;
localparam NX_NAME7_H = 9;
function [25:0] nx_name7_row(input [3:0] row);
    case (row)
        4'd1: nx_name7_row = 26'b11100100101000100011101110;
        4'd2: nx_name7_row = 26'b10010100101000100010000100;
        4'd3: nx_name7_row = 26'b10010100101000100010000100;
        4'd4: nx_name7_row = 26'b11100100101000100011100100;
        4'd5: nx_name7_row = 26'b10010100101000100010000100;
        4'd6: nx_name7_row = 26'b10010100101000100010000100;
        4'd7: nx_name7_row = 26'b11100011001110111011100100;
        default: nx_name7_row = 26'd0;
    endcase
endfunction
function nx_name7_lit(input [9:0] dx, input [9:0] dy);
    reg [25:0] r;
    begin
        r = nx_name7_row(dy[3:0]);
        nx_name7_lit = (dx < 26 && dy < 9) ? r[25 - dx] : 1'b0;
    end
endfunction

localparam NX_PPICK_W = 71;
localparam NX_PPICK_H = 9;
function [70:0] nx_ppick_row(input [3:0] row);
    case (row)
        4'd1: nx_ppick_row = 71'b11100100110100100001000100110010010111000001110001100111001110010001110;
        4'd2: nx_ppick_row = 71'b10010101000100100001000101001010010100100001001010010100101001010001000;
        4'd3: nx_ppick_row = 71'b10010101000101000000101001001010010100100001001010010100101001010001000;
        4'd4: nx_ppick_row = 71'b11100101000110000000010001001010010111000001110011110100101001010001110;
        4'd5: nx_ppick_row = 71'b10000101000101000000010001001010010100100001000010010100101001010001000;
        4'd6: nx_ppick_row = 71'b10000101000100100000010001001010010100100001000010010100101001010001000;
        4'd7: nx_ppick_row = 71'b10000100110100100000010000110001100100100001000010010111001110011101110;
        default: nx_ppick_row = 71'd0;
    endcase
endfunction
function nx_ppick_lit(input [9:0] dx, input [9:0] dy);
    reg [70:0] r;
    begin
        r = nx_ppick_row(dy[3:0]);
        nx_ppick_lit = (dx < 71 && dy < 9) ? r[70 - dx] : 1'b0;
    end
endfunction

localparam NX_OK_W = 10;
localparam NX_OK_H = 9;
function [9:0] nx_ok_row(input [3:0] row);
    case (row)
        4'd1: nx_ok_row = 10'b0110010010;
        4'd2: nx_ok_row = 10'b1001010010;
        4'd3: nx_ok_row = 10'b1001010100;
        4'd4: nx_ok_row = 10'b1001011000;
        4'd5: nx_ok_row = 10'b1001010100;
        4'd6: nx_ok_row = 10'b1001010010;
        4'd7: nx_ok_row = 10'b0110010010;
        default: nx_ok_row = 10'd0;
    endcase
endfunction
function nx_ok_lit(input [9:0] dx, input [9:0] dy);
    reg [9:0] r;
    begin
        r = nx_ok_row(dy[3:0]);
        nx_ok_lit = (dx < 10 && dy < 9) ? r[9 - dx] : 1'b0;
    end
endfunction

localparam NX_KIND0_W = 28;
localparam NX_KIND0_H = 9;
function [27:0] nx_kind0_row(input [3:0] row);
    case (row)
        4'd1: nx_kind0_row = 28'b0110011100011001100111001110;
        4'd2: nx_kind0_row = 28'b1001010010100010010100101000;
        4'd3: nx_kind0_row = 28'b1001010010100010010100101000;
        4'd4: nx_kind0_row = 28'b1111011100100011110100101110;
        4'd5: nx_kind0_row = 28'b1001010010100010010100101000;
        4'd6: nx_kind0_row = 28'b1001010010100010010100101000;
        4'd7: nx_kind0_row = 28'b1001010010011010010111001110;
        default: nx_kind0_row = 28'd0;
    endcase
endfunction
function nx_kind0_lit(input [9:0] dx, input [9:0] dy);
    reg [27:0] r;
    begin
        r = nx_kind0_row(dy[3:0]);
        nx_kind0_lit = (dx < 28 && dy < 9) ? r[27 - dx] : 1'b0;
    end
endfunction

localparam NX_KIND1_W = 20;
localparam NX_KIND1_H = 9;
function [19:0] nx_kind1_row(input [3:0] row);
    case (row)
        4'd1: nx_kind1_row = 20'b11101011100110010010;
        4'd2: nx_kind1_row = 20'b01001001001001010010;
        4'd3: nx_kind1_row = 20'b01001001001001011010;
        4'd4: nx_kind1_row = 20'b01001001001111010110;
        4'd5: nx_kind1_row = 20'b01001001001001010010;
        4'd6: nx_kind1_row = 20'b01001001001001010010;
        4'd7: nx_kind1_row = 20'b01001001001001010010;
        default: nx_kind1_row = 20'd0;
    endcase
endfunction
function nx_kind1_lit(input [9:0] dx, input [9:0] dy);
    reg [19:0] r;
    begin
        r = nx_kind1_row(dy[3:0]);
        nx_kind1_lit = (dx < 20 && dy < 9) ? r[19 - dx] : 1'b0;
    end
endfunction

localparam NX_KIND2_W = 31;
localparam NX_KIND2_H = 9;
function [30:0] nx_kind2_row(input [3:0] row);
    case (row)
        4'd1: nx_kind2_row = 31'b1001001100100010100010111011100;
        4'd2: nx_kind2_row = 31'b1001010010100010100010100010010;
        4'd3: nx_kind2_row = 31'b1001010010110110110110100010010;
        4'd4: nx_kind2_row = 31'b1111011110101010101010111011100;
        4'd5: nx_kind2_row = 31'b1001010010100010100010100010010;
        4'd6: nx_kind2_row = 31'b1001010010100010100010100010010;
        4'd7: nx_kind2_row = 31'b1001010010100010100010111010010;
        default: nx_kind2_row = 31'd0;
    endcase
endfunction
function nx_kind2_lit(input [9:0] dx, input [9:0] dy);
    reg [30:0] r;
    begin
        r = nx_kind2_row(dy[3:0]);
        nx_kind2_lit = (dx < 31 && dy < 9) ? r[30 - dx] : 1'b0;
    end
endfunction

localparam NX_KIND3_W = 20;
localparam NX_KIND3_H = 9;
function [19:0] nx_kind3_row(input [3:0] row);
    case (row)
        4'd1: nx_kind3_row = 20'b11101000101001101110;
        4'd2: nx_kind3_row = 20'b01001000101010000100;
        4'd3: nx_kind3_row = 20'b01001000101010000100;
        4'd4: nx_kind3_row = 20'b01001010101001000100;
        4'd5: nx_kind3_row = 20'b01001101101000100100;
        4'd6: nx_kind3_row = 20'b01001000101000100100;
        4'd7: nx_kind3_row = 20'b01001000101011000100;
        default: nx_kind3_row = 20'd0;
    endcase
endfunction
function nx_kind3_lit(input [9:0] dx, input [9:0] dy);
    reg [19:0] r;
    begin
        r = nx_kind3_row(dy[3:0]);
        nx_kind3_lit = (dx < 20 && dy < 9) ? r[19 - dx] : 1'b0;
    end
endfunction

localparam NX_KIND4_W = 31;
localparam NX_KIND4_H = 9;
function [30:0] nx_kind4_row(input [3:0] row);
    case (row)
        4'd1: nx_kind4_row = 31'b1110010000110001101110111011100;
        4'd2: nx_kind4_row = 31'b1001010001001010000100100010010;
        4'd3: nx_kind4_row = 31'b1001010001001010000100100010010;
        4'd4: nx_kind4_row = 31'b1110010001111001000100111011100;
        4'd5: nx_kind4_row = 31'b1001010001001000100100100010010;
        4'd6: nx_kind4_row = 31'b1001010001001000100100100010010;
        4'd7: nx_kind4_row = 31'b1110011101001011000100111010010;
        default: nx_kind4_row = 31'd0;
    endcase
endfunction
function nx_kind4_lit(input [9:0] dx, input [9:0] dy);
    reg [30:0] r;
    begin
        r = nx_kind4_row(dy[3:0]);
        nx_kind4_lit = (dx < 31 && dy < 9) ? r[30 - dx] : 1'b0;
    end
endfunction

localparam NX_KIND5_W = 19;
localparam NX_KIND5_H = 9;
function [18:0] nx_kind5_row(input [3:0] row);
    case (row)
        4'd1: nx_kind5_row = 19'b1110010010011010010;
        4'd2: nx_kind5_row = 19'b1001010010100010010;
        4'd3: nx_kind5_row = 19'b1001010010100010010;
        4'd4: nx_kind5_row = 19'b1110010010010011110;
        4'd5: nx_kind5_row = 19'b1001010010001010010;
        4'd6: nx_kind5_row = 19'b1001010010001010010;
        4'd7: nx_kind5_row = 19'b1001001100110010010;
        default: nx_kind5_row = 19'd0;
    endcase
endfunction
function nx_kind5_lit(input [9:0] dx, input [9:0] dy);
    reg [18:0] r;
    begin
        r = nx_kind5_row(dy[3:0]);
        nx_kind5_lit = (dx < 19 && dy < 9) ? r[18 - dx] : 1'b0;
    end
endfunction

localparam NX_KIND6_W = 37;
localparam NX_KIND6_H = 9;
function [36:0] nx_kind6_row(input [3:0] row);
    case (row)
        4'd1: nx_kind6_row = 37'b0110010010011001110011100100110010010;
        4'd2: nx_kind6_row = 37'b1000010010100101001010010101001010010;
        4'd3: nx_kind6_row = 37'b1000010010100101001010010101001011010;
        4'd4: nx_kind6_row = 37'b1011010010111101110010010101111010110;
        4'd5: nx_kind6_row = 37'b1001010010100101001010010101001010010;
        4'd6: nx_kind6_row = 37'b1001010010100101001010010101001010010;
        4'd7: nx_kind6_row = 37'b0110001100100101001011100101001010010;
        default: nx_kind6_row = 37'd0;
    endcase
endfunction
function nx_kind6_lit(input [9:0] dx, input [9:0] dy);
    reg [36:0] r;
    begin
        r = nx_kind6_row(dy[3:0]);
        nx_kind6_lit = (dx < 37 && dy < 9) ? r[36 - dx] : 1'b0;
    end
endfunction

localparam NX_TAG0_W = 55;
localparam NX_TAG0_H = 9;
function [54:0] nx_tag0_row(input [3:0] row);
    case (row)
        4'd1: nx_tag0_row = 55'b1000100110011100111000011100011001001010010011011100110;
        4'd2: nx_tag0_row = 55'b1000101001010010100000010010100101001010010100010001000;
        4'd3: nx_tag0_row = 55'b1101101001010010100000010010100101101010010100010001000;
        4'd4: nx_tag0_row = 55'b1010101001011100111000011100100101011010010010011100100;
        4'd5: nx_tag0_row = 55'b1000101001010010100000010010100101001010010001010000010;
        4'd6: nx_tag0_row = 55'b1000101001010010100000010010100101001010010001010000010;
        4'd7: nx_tag0_row = 55'b1000100110010010111000011100011001001001100110011101100;
        default: nx_tag0_row = 55'd0;
    endcase
endfunction
function nx_tag0_lit(input [9:0] dx, input [9:0] dy);
    reg [54:0] r;
    begin
        r = nx_tag0_row(dy[3:0]);
        nx_tag0_lit = (dx < 55 && dy < 9) ? r[54 - dx] : 1'b0;
    end
endfunction

localparam NX_TAG1_W = 56;
localparam NX_TAG1_H = 9;
function [55:0] nx_tag1_row(input [3:0] row);
    case (row)
        4'd1: nx_tag1_row = 56'b11100110010001000000111001001011100000110100001100100010;
        4'd2: nx_tag1_row = 56'b01001001010001000000100101001001000001000100010010100010;
        4'd3: nx_tag1_row = 56'b01001001010001000000100101001001000001000100010010100010;
        4'd4: nx_tag1_row = 56'b01001111010001000000111001001001000000100100010010101010;
        4'd5: nx_tag1_row = 56'b01001001010001000000100101001001000000010100010010110110;
        4'd6: nx_tag1_row = 56'b01001001010001000000100101001001000000010100010010100010;
        4'd7: nx_tag1_row = 56'b01001001011101110000111000110001000001100111001100100010;
        default: nx_tag1_row = 56'd0;
    endcase
endfunction
function nx_tag1_lit(input [9:0] dx, input [9:0] dy);
    reg [55:0] r;
    begin
        r = nx_tag1_row(dy[3:0]);
        nx_tag1_lit = (dx < 56 && dy < 9) ? r[55 - dx] : 1'b0;
    end
endfunction

localparam NX_TAG2_W = 50;
localparam NX_TAG2_H = 9;
function [49:0] nx_tag2_row(input [3:0] row);
    case (row)
        4'd1: nx_tag2_row = 50'b11100011001000101110111000000110100100110011100110;
        4'd2: nx_tag2_row = 50'b10010100101000101000100100001000100101001001001000;
        4'd3: nx_tag2_row = 50'b10010100101000101000100100001000100101001001001000;
        4'd4: nx_tag2_row = 50'b11100100101010101110111000000100111101001001000100;
        4'd5: nx_tag2_row = 50'b10000100101101101000100100000010100101001001000010;
        4'd6: nx_tag2_row = 50'b10000100101000101000100100000010100101001001000010;
        4'd7: nx_tag2_row = 50'b10000011001000101110100100001100100100110001001100;
        default: nx_tag2_row = 50'd0;
    endcase
endfunction
function nx_tag2_lit(input [9:0] dx, input [9:0] dy);
    reg [49:0] r;
    begin
        r = nx_tag2_row(dy[3:0]);
        nx_tag2_lit = (dx < 50 && dy < 9) ? r[49 - dx] : 1'b0;
    end
endfunction

localparam NX_TAG3_W = 63;
localparam NX_TAG3_H = 9;
function [62:0] nx_tag3_row(input [3:0] row);
    case (row)
        4'd1: nx_tag3_row = 63'b111010100011100110000100010101110100100000110111001110111011100;
        4'd2: nx_tag3_row = 63'b010010100001001000000100010100100100100001000100101000100010010;
        4'd3: nx_tag3_row = 63'b010010100001001000000100010100100100100001000100101000100010010;
        4'd4: nx_tag3_row = 63'b010010100001000100000101010100100111100000100111001110111010010;
        4'd5: nx_tag3_row = 63'b010010100001000010000110110100100100100000010100001000100010010;
        4'd6: nx_tag3_row = 63'b010010100001000010000100010100100100100000010100001000100010010;
        4'd7: nx_tag3_row = 63'b010010111001001100000100010100100100100001100100001110111011100;
        default: nx_tag3_row = 63'd0;
    endcase
endfunction
function nx_tag3_lit(input [9:0] dx, input [9:0] dy);
    reg [62:0] r;
    begin
        r = nx_tag3_row(dy[3:0]);
        nx_tag3_lit = (dx < 63 && dy < 9) ? r[62 - dx] : 1'b0;
    end
endfunction

localparam NX_TAG4_W = 65;
localparam NX_TAG4_H = 9;
function [64:0] nx_tag4_row(input [3:0] row);
    case (row)
        4'd1: nx_tag4_row = 65'b01101001001100011001110011000001100110011100011010010100011100110;
        4'd2: nx_tag4_row = 65'b10001001010010100100100100000010001001010010100010010100010001000;
        4'd3: nx_tag4_row = 65'b10001001010010100100100100000010001001010010100010010100010001000;
        4'd4: nx_tag4_row = 65'b01001111010010100100100010000010001111011100010010010100011100100;
        4'd5: nx_tag4_row = 65'b00101001010010100100100001000010001001010000001010010100010000010;
        4'd6: nx_tag4_row = 65'b00101001010010100100100001000010001001010000001010010100010000010;
        4'd7: nx_tag4_row = 65'b11001001001100011000100110000001101001010000110001100111011101100;
        default: nx_tag4_row = 65'd0;
    endcase
endfunction
function nx_tag4_lit(input [9:0] dx, input [9:0] dy);
    reg [64:0] r;
    begin
        r = nx_tag4_row(dy[3:0]);
        nx_tag4_lit = (dx < 65 && dy < 9) ? r[64 - dx] : 1'b0;
    end
endfunction

localparam NX_TAG5_W = 41;
localparam NX_TAG5_H = 9;
function [40:0] nx_tag5_row(input [3:0] row);
    case (row)
        4'd1: nx_tag5_row = 41'b10000110010010011000001110001100011010010;
        4'd2: nx_tag5_row = 41'b10001001010010100000001001010010100010010;
        4'd3: nx_tag5_row = 41'b10001001011010100000001001010010100010010;
        4'd4: nx_tag5_row = 41'b10001001010110101100001001011110010011110;
        4'd5: nx_tag5_row = 41'b10001001010010100100001001010010001010010;
        4'd6: nx_tag5_row = 41'b10001001010010100100001001010010001010010;
        4'd7: nx_tag5_row = 41'b11100110010010011000001110010010110010010;
        default: nx_tag5_row = 41'd0;
    endcase
endfunction
function nx_tag5_lit(input [9:0] dx, input [9:0] dy);
    reg [40:0] r;
    begin
        r = nx_tag5_row(dy[3:0]);
        nx_tag5_lit = (dx < 41 && dy < 9) ? r[40 - dx] : 1'b0;
    end
endfunction

localparam NX_TAG6_W = 61;
localparam NX_TAG6_H = 9;
function [60:0] nx_tag6_row(input [3:0] row);
    case (row)
        4'd1: nx_tag6_row = 61'b1110101000101110000011100101110011011100001000100110010001000;
        4'd2: nx_tag6_row = 61'b1000101000101000000010010101000100010000001000101001010001000;
        4'd3: nx_tag6_row = 61'b1000101000101000000010010101000100010000001000101001010001000;
        4'd4: nx_tag6_row = 61'b1110100101001110000011100101110100011100001010101111010001000;
        4'd5: nx_tag6_row = 61'b1000100101001000111010000101000100010000001101101001010001000;
        4'd6: nx_tag6_row = 61'b1000100010001000000010000101000100010000001000101001010001000;
        4'd7: nx_tag6_row = 61'b1000100010001110000010000101110011011100001000101001011101110;
        default: nx_tag6_row = 61'd0;
    endcase
endfunction
function nx_tag6_lit(input [9:0] dx, input [9:0] dy);
    reg [60:0] r;
    begin
        r = nx_tag6_row(dy[3:0]);
        nx_tag6_lit = (dx < 61 && dy < 9) ? r[60 - dx] : 1'b0;
    end
endfunction

localparam NX_MOVE0_W = 55;
localparam NX_MOVE0_H = 9;
function [54:0] nx_move0_row(input [3:0] row);
    case (row)
        4'd1: nx_move0_row = 55'b0110111011100011001001100100101110000011010010011001110;
        4'd2: nx_move0_row = 55'b1000010010010100101010000100100100000100010010100100100;
        4'd3: nx_move0_row = 55'b1000010010010100101010000100100100000100010010100100100;
        4'd4: nx_move0_row = 55'b0100010011100111101010110111100100000010011110100100100;
        4'd5: nx_move0_row = 55'b0010010010010100101010010100100100000001010010100100100;
        4'd6: nx_move0_row = 55'b0010010010010100101010010100100100000001010010100100100;
        4'd7: nx_move0_row = 55'b1100010010010100101001100100100100000110010010011000100;
        default: nx_move0_row = 55'd0;
    endcase
endfunction
function nx_move0_lit(input [9:0] dx, input [9:0] dy);
    reg [54:0] r;
    begin
        r = nx_move0_row(dy[3:0]);
        nx_move0_lit = (dx < 55 && dy < 9) ? r[54 - dx] : 1'b0;
    end
endfunction

localparam NX_MOVE1_W = 50;
localparam NX_MOVE1_H = 9;
function [49:0] nx_move1_row(input [3:0] row);
    case (row)
        4'd1: nx_move1_row = 50'b11100100110101001001100000011011101110010100101110;
        4'd2: nx_move1_row = 50'b10010101000101001010000000100001001001010100101000;
        4'd3: nx_move1_row = 50'b10010101000101101010000000100001001001010101001000;
        4'd4: nx_move1_row = 50'b11100100100101011010110000010001001110010110001110;
        4'd5: nx_move1_row = 50'b10010100010101001010010000001001001001010101001000;
        4'd6: nx_move1_row = 50'b10010100010101001010010000001001001001010100101000;
        4'd7: nx_move1_row = 50'b10010101100101001001100000110001001001010100101110;
        default: nx_move1_row = 50'd0;
    endcase
endfunction
function nx_move1_lit(input [9:0] dx, input [9:0] dy);
    reg [49:0] r;
    begin
        r = nx_move1_row(dy[3:0]);
        nx_move1_lit = (dx < 50 && dy < 9) ? r[49 - dx] : 1'b0;
    end
endfunction

localparam NX_MAX_W = 17;
localparam NX_MAX_H = 9;
function [16:0] nx_max_row(input [3:0] row);
    case (row)
        4'd1: nx_max_row = 17'b10001001100100010;
        4'd2: nx_max_row = 17'b10001010010100010;
        4'd3: nx_max_row = 17'b11011010010010100;
        4'd4: nx_max_row = 17'b10101011110001000;
        4'd5: nx_max_row = 17'b10001010010010100;
        4'd6: nx_max_row = 17'b10001010010100010;
        4'd7: nx_max_row = 17'b10001010010100010;
        default: nx_max_row = 17'd0;
    endcase
endfunction
function nx_max_lit(input [9:0] dx, input [9:0] dy);
    reg [16:0] r;
    begin
        r = nx_max_row(dy[3:0]);
        nx_max_lit = (dx < 17 && dy < 9) ? r[16 - dx] : 1'b0;
    end
endfunction

localparam [7:0] NX_P1_COLS = 8'b11110110;
function nx_p1_col(input [9:0] dx);
    nx_p1_col = (dx < 8) ? NX_P1_COLS[7 - dx] : 1'b0;
endfunction

localparam [8:0] NX_P2_COLS = 9'b111101110;
function nx_p2_col(input [9:0] dx);
    nx_p2_col = (dx < 9) ? NX_P2_COLS[8 - dx] : 1'b0;
endfunction

localparam [16:0] NX_MAX_COLS = 17'b11111011110111110;
function nx_max_col(input [9:0] dx);
    nx_max_col = (dx < 17) ? NX_MAX_COLS[16 - dx] : 1'b0;
endfunction

localparam [54:0] NX_MOVE0_COLS = 55'b1110111011110111101011110111101110000111011110111101110;
function nx_move0_col(input [9:0] dx);
    nx_move0_col = (dx < 55) ? NX_MOVE0_COLS[54 - dx] : 1'b0;
endfunction

localparam [49:0] NX_MOVE1_COLS = 50'b11110101110101111011110000111011101111010111101110;
function nx_move1_col(input [9:0] dx);
    nx_move1_col = (dx < 50) ? NX_MOVE1_COLS[49 - dx] : 1'b0;
endfunction

localparam [1:0] NX_BANG_COLS = 2'b10;
function nx_bang_col(input [9:0] dx);
    nx_bang_col = (dx < 2) ? NX_BANG_COLS[1 - dx] : 1'b0;
endfunction

function [6:0] kind_l1(input [2:0] kind, input [3:0] i);
    case ({kind, i})
        {3'd0, 4'd0}: kind_l1 = 7'd4;
        {3'd0, 4'd1}: kind_l1 = 7'd9;
        {3'd0, 4'd2}: kind_l1 = 7'd13;
        {3'd0, 4'd3}: kind_l1 = 7'd18;
        {3'd0, 4'd4}: kind_l1 = 7'd23;
        {3'd0, 4'd5}: kind_l1 = 7'd27;
        {3'd1, 4'd0}: kind_l1 = 7'd3;
        {3'd1, 4'd1}: kind_l1 = 7'd5;
        {3'd1, 4'd2}: kind_l1 = 7'd9;
        {3'd1, 4'd3}: kind_l1 = 7'd14;
        {3'd1, 4'd4}: kind_l1 = 7'd19;
        {3'd2, 4'd0}: kind_l1 = 7'd4;
        {3'd2, 4'd1}: kind_l1 = 7'd9;
        {3'd2, 4'd2}: kind_l1 = 7'd15;
        {3'd2, 4'd3}: kind_l1 = 7'd21;
        {3'd2, 4'd4}: kind_l1 = 7'd25;
        {3'd2, 4'd5}: kind_l1 = 7'd30;
        {3'd3, 4'd0}: kind_l1 = 7'd3;
        {3'd3, 4'd1}: kind_l1 = 7'd9;
        {3'd3, 4'd2}: kind_l1 = 7'd11;
        {3'd3, 4'd3}: kind_l1 = 7'd15;
        {3'd3, 4'd4}: kind_l1 = 7'd19;
        {3'd4, 4'd0}: kind_l1 = 7'd4;
        {3'd4, 4'd1}: kind_l1 = 7'd8;
        {3'd4, 4'd2}: kind_l1 = 7'd13;
        {3'd4, 4'd3}: kind_l1 = 7'd17;
        {3'd4, 4'd4}: kind_l1 = 7'd21;
        {3'd4, 4'd5}: kind_l1 = 7'd25;
        {3'd4, 4'd6}: kind_l1 = 7'd30;
        {3'd5, 4'd0}: kind_l1 = 7'd4;
        {3'd5, 4'd1}: kind_l1 = 7'd9;
        {3'd5, 4'd2}: kind_l1 = 7'd13;
        {3'd5, 4'd3}: kind_l1 = 7'd18;
        {3'd6, 4'd0}: kind_l1 = 7'd4;
        {3'd6, 4'd1}: kind_l1 = 7'd9;
        {3'd6, 4'd2}: kind_l1 = 7'd14;
        {3'd6, 4'd3}: kind_l1 = 7'd19;
        {3'd6, 4'd4}: kind_l1 = 7'd24;
        {3'd6, 4'd5}: kind_l1 = 7'd26;
        {3'd6, 4'd6}: kind_l1 = 7'd31;
        {3'd6, 4'd7}: kind_l1 = 7'd36;
        default: kind_l1 = 7'd127;
    endcase
endfunction
function [3:0] kind_letters(input [2:0] kind);
    case (kind)
        3'd0: kind_letters = 4'd6;
        3'd1: kind_letters = 4'd5;
        3'd2: kind_letters = 4'd6;
        3'd3: kind_letters = 4'd5;
        3'd4: kind_letters = 4'd7;
        3'd5: kind_letters = 4'd4;
        3'd6: kind_letters = 4'd8;
        default: kind_letters = 4'd0;
    endcase
endfunction

function [5:0] name_w(input [2:0] bonus);
    case (bonus)
        3'd0: name_w = 35;
        3'd1: name_w = 24;
        3'd2: name_w = 19;
        3'd3: name_w = 24;
        3'd4: name_w = 23;
        3'd5: name_w = 23;
        3'd6: name_w = 21;
        3'd7: name_w = 26;
        default: name_w = 0;
    endcase
endfunction
function name_lit(input [2:0] bonus, input [9:0] dx, input [9:0] dy);
    case (bonus)
        3'd0: name_lit = nx_name0_lit(dx, dy);
        3'd1: name_lit = nx_name1_lit(dx, dy);
        3'd2: name_lit = nx_name2_lit(dx, dy);
        3'd3: name_lit = nx_name3_lit(dx, dy);
        3'd4: name_lit = nx_name4_lit(dx, dy);
        3'd5: name_lit = nx_name5_lit(dx, dy);
        3'd6: name_lit = nx_name6_lit(dx, dy);
        3'd7: name_lit = nx_name7_lit(dx, dy);
        default: name_lit = 1'b0;
    endcase
endfunction

function [6:0] kind_name_w(input [2:0] kind);
    case (kind)
        3'd0: kind_name_w = 28;
        3'd1: kind_name_w = 20;
        3'd2: kind_name_w = 31;
        3'd3: kind_name_w = 20;
        3'd4: kind_name_w = 31;
        3'd5: kind_name_w = 19;
        3'd6: kind_name_w = 37;
        default: kind_name_w = 0;
    endcase
endfunction
function kind_name_lit(input [2:0] kind, input [9:0] dx, input [9:0] dy);
    case (kind)
        3'd0: kind_name_lit = nx_kind0_lit(dx, dy);
        3'd1: kind_name_lit = nx_kind1_lit(dx, dy);
        3'd2: kind_name_lit = nx_kind2_lit(dx, dy);
        3'd3: kind_name_lit = nx_kind3_lit(dx, dy);
        3'd4: kind_name_lit = nx_kind4_lit(dx, dy);
        3'd5: kind_name_lit = nx_kind5_lit(dx, dy);
        3'd6: kind_name_lit = nx_kind6_lit(dx, dy);
        default: kind_name_lit = 1'b0;
    endcase
endfunction

function [6:0] tag_w(input [2:0] kind);
    case (kind)
        3'd0: tag_w = 55;
        3'd1: tag_w = 56;
        3'd2: tag_w = 50;
        3'd3: tag_w = 63;
        3'd4: tag_w = 65;
        3'd5: tag_w = 41;
        3'd6: tag_w = 61;
        default: tag_w = 0;
    endcase
endfunction
function tag_lit(input [2:0] kind, input [9:0] dx, input [9:0] dy);
    case (kind)
        3'd0: tag_lit = nx_tag0_lit(dx, dy);
        3'd1: tag_lit = nx_tag1_lit(dx, dy);
        3'd2: tag_lit = nx_tag2_lit(dx, dy);
        3'd3: tag_lit = nx_tag3_lit(dx, dy);
        3'd4: tag_lit = nx_tag4_lit(dx, dy);
        3'd5: tag_lit = nx_tag5_lit(dx, dy);
        3'd6: tag_lit = nx_tag6_lit(dx, dy);
        default: tag_lit = 1'b0;
    endcase
endfunction

function [6:0] move_w(input [2:0] move);
    case (move)
        3'd0: move_w = 55;
        3'd1: move_w = 50;
        default: move_w = 0;
    endcase
endfunction
function move_lit(input [2:0] move, input [9:0] dx, input [9:0] dy);
    case (move)
        3'd0: move_lit = nx_move0_lit(dx, dy);
        3'd1: move_lit = nx_move1_lit(dx, dy);
        default: move_lit = 1'b0;
    endcase
endfunction
