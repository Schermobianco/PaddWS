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

localparam NX_PICK_W = 111;
localparam NX_PICK_H = 8;
function [110:0] nx_pick_row(input [2:0] row);
    case (row)
        3'd0: nx_pick_row = 111'b111111000111111000111100110001100000000001111110000000001111110001111100110001101100011001111100111111100111110;
        3'd1: nx_pick_row = 111'b110001100001100001100110110011000000000000001100000000001100011011000110111001101100011011000110110000001100011;
        3'd2: nx_pick_row = 111'b110001100001100011000000110110000000000000011000000000001100011011000110111101101100011011000000110000001100000;
        3'd3: nx_pick_row = 111'b110001100001100011000000111100000000000000111100000000001111110011000110110111101100011001111100111111000111110;
        3'd4: nx_pick_row = 111'b111111000001100011000000111110000000000000000110000000001100011011000110110011101100011000000110110000000000011;
        3'd5: nx_pick_row = 111'b110000000001100001100110110111000000000011000110000000001100011011000110110001101100011011000110110000001100011;
        3'd6: nx_pick_row = 111'b110000000111111000111100110011100000000001111100000000001111110001111100110001100111110001111100111111100111110;
        default: nx_pick_row = 111'd0;
    endcase
endfunction
function nx_pick_lit(input [9:0] dx, input [9:0] dy);
    reg [110:0] r;
    begin
        r = nx_pick_row(dy[2:0]);
        nx_pick_lit = (dx < 111 && dy < 8) ? r[110 - dx] : 1'b0;
    end
endfunction

localparam NX_READY_W = 47;
localparam NX_READY_H = 8;
function [46:0] nx_ready_row(input [2:0] row);
    case (row)
        3'd0: nx_ready_row = 47'b11111100111111100011100011111000011001100011100;
        3'd1: nx_ready_row = 47'b11000110110000000110110011001100011001100011100;
        3'd2: nx_ready_row = 47'b11000110110000001100011011000110011001100011100;
        3'd3: nx_ready_row = 47'b11001110111111001100011011000110001111000011000;
        3'd4: nx_ready_row = 47'b11111000110000001111111011000110000110000011000;
        3'd5: nx_ready_row = 47'b11011100110000001100011011001100000110000000000;
        3'd6: nx_ready_row = 47'b11001110111111101100011011111000000110000011000;
        default: nx_ready_row = 47'd0;
    endcase
endfunction
function nx_ready_lit(input [9:0] dx, input [9:0] dy);
    reg [46:0] r;
    begin
        r = nx_ready_row(dy[2:0]);
        nx_ready_lit = (dx < 47 && dy < 8) ? r[46 - dx] : 1'b0;
    end
endfunction

localparam NX_P1_W = 15;
localparam NX_P1_H = 8;
function [14:0] nx_p1_row(input [2:0] row);
    case (row)
        3'd0: nx_p1_row = 15'b111111000001100;
        3'd1: nx_p1_row = 15'b110001100011100;
        3'd2: nx_p1_row = 15'b110001100001100;
        3'd3: nx_p1_row = 15'b110001100001100;
        3'd4: nx_p1_row = 15'b111111000001100;
        3'd5: nx_p1_row = 15'b110000000001100;
        3'd6: nx_p1_row = 15'b110000000111111;
        default: nx_p1_row = 15'd0;
    endcase
endfunction
function nx_p1_lit(input [9:0] dx, input [9:0] dy);
    reg [14:0] r;
    begin
        r = nx_p1_row(dy[2:0]);
        nx_p1_lit = (dx < 15 && dy < 8) ? r[14 - dx] : 1'b0;
    end
endfunction

localparam NX_P2_W = 15;
localparam NX_P2_H = 8;
function [14:0] nx_p2_row(input [2:0] row);
    case (row)
        3'd0: nx_p2_row = 15'b111111000111110;
        3'd1: nx_p2_row = 15'b110001101100011;
        3'd2: nx_p2_row = 15'b110001100000111;
        3'd3: nx_p2_row = 15'b110001100011110;
        3'd4: nx_p2_row = 15'b111111000111100;
        3'd5: nx_p2_row = 15'b110000001110000;
        3'd6: nx_p2_row = 15'b110000001111111;
        default: nx_p2_row = 15'd0;
    endcase
endfunction
function nx_p2_lit(input [9:0] dx, input [9:0] dy);
    reg [14:0] r;
    begin
        r = nx_p2_row(dy[2:0]);
        nx_p2_lit = (dx < 15 && dy < 8) ? r[14 - dx] : 1'b0;
    end
endfunction

localparam NX_CPU_W = 23;
localparam NX_CPU_H = 8;
function [22:0] nx_cpu_row(input [2:0] row);
    case (row)
        3'd0: nx_cpu_row = 23'b00111100111111001100011;
        3'd1: nx_cpu_row = 23'b01100110110001101100011;
        3'd2: nx_cpu_row = 23'b11000000110001101100011;
        3'd3: nx_cpu_row = 23'b11000000110001101100011;
        3'd4: nx_cpu_row = 23'b11000000111111001100011;
        3'd5: nx_cpu_row = 23'b01100110110000001100011;
        3'd6: nx_cpu_row = 23'b00111100110000000111110;
        default: nx_cpu_row = 23'd0;
    endcase
endfunction
function nx_cpu_lit(input [9:0] dx, input [9:0] dy);
    reg [22:0] r;
    begin
        r = nx_cpu_row(dy[2:0]);
        nx_cpu_lit = (dx < 23 && dy < 8) ? r[22 - dx] : 1'b0;
    end
endfunction

localparam NX_OF3_W = 15;
localparam NX_OF3_H = 8;
function [14:0] nx_of3_row(input [2:0] row);
    case (row)
        3'd0: nx_of3_row = 15'b000000100111111;
        3'd1: nx_of3_row = 15'b000001000000110;
        3'd2: nx_of3_row = 15'b000010000001100;
        3'd3: nx_of3_row = 15'b000100000011110;
        3'd4: nx_of3_row = 15'b001000000000011;
        3'd5: nx_of3_row = 15'b010000001100011;
        3'd6: nx_of3_row = 15'b100000000111110;
        default: nx_of3_row = 15'd0;
    endcase
endfunction
function nx_of3_lit(input [9:0] dx, input [9:0] dy);
    reg [14:0] r;
    begin
        r = nx_of3_row(dy[2:0]);
        nx_of3_lit = (dx < 15 && dy < 8) ? r[14 - dx] : 1'b0;
    end
endfunction

localparam NX_CURSOR_W = 7;
localparam NX_CURSOR_H = 8;
function [6:0] nx_cursor_row(input [2:0] row);
    case (row)
        3'd0: nx_cursor_row = 7'b0110000;
        3'd1: nx_cursor_row = 7'b0011000;
        3'd2: nx_cursor_row = 7'b0001100;
        3'd3: nx_cursor_row = 7'b0000110;
        3'd4: nx_cursor_row = 7'b0001100;
        3'd5: nx_cursor_row = 7'b0011000;
        3'd6: nx_cursor_row = 7'b0110000;
        default: nx_cursor_row = 7'd0;
    endcase
endfunction
function nx_cursor_lit(input [9:0] dx, input [9:0] dy);
    reg [6:0] r;
    begin
        r = nx_cursor_row(dy[2:0]);
        nx_cursor_lit = (dx < 7 && dy < 8) ? r[6 - dx] : 1'b0;
    end
endfunction

localparam NX_BANG_W = 7;
localparam NX_BANG_H = 8;
function [6:0] nx_bang_row(input [2:0] row);
    case (row)
        3'd0: nx_bang_row = 7'b0011100;
        3'd1: nx_bang_row = 7'b0011100;
        3'd2: nx_bang_row = 7'b0011100;
        3'd3: nx_bang_row = 7'b0011000;
        3'd4: nx_bang_row = 7'b0011000;
        3'd6: nx_bang_row = 7'b0011000;
        default: nx_bang_row = 7'd0;
    endcase
endfunction
function nx_bang_lit(input [9:0] dx, input [9:0] dy);
    reg [6:0] r;
    begin
        r = nx_bang_row(dy[2:0]);
        nx_bang_lit = (dx < 7 && dy < 8) ? r[6 - dx] : 1'b0;
    end
endfunction

localparam NX_NAME0_W = 63;
localparam NX_NAME0_H = 8;
function [62:0] nx_name0_row(input [2:0] row);
    case (row)
        3'd0: nx_name0_row = 63'b011111101111111001100000111111101111110001111100111111000111111;
        3'd1: nx_name0_row = 63'b000110001100000001100000110000001100011011000110110001100001100;
        3'd2: nx_name0_row = 63'b000110001100000001100000110000001100011011000110110001100001100;
        3'd3: nx_name0_row = 63'b000110001111110001100000111111001100011011000110110011100001100;
        3'd4: nx_name0_row = 63'b000110001100000001100000110000001111110011000110111110000001100;
        3'd5: nx_name0_row = 63'b000110001100000001100000110000001100000011000110110111000001100;
        3'd6: nx_name0_row = 63'b000110001111111001111110111111101100000001111100110011100001100;
        default: nx_name0_row = 63'd0;
    endcase
endfunction
function nx_name0_lit(input [9:0] dx, input [9:0] dy);
    reg [62:0] r;
    begin
        r = nx_name0_row(dy[2:0]);
        nx_name0_lit = (dx < 63 && dy < 8) ? r[62 - dx] : 1'b0;
    end
endfunction

localparam NX_NAME1_W = 39;
localparam NX_NAME1_H = 8;
function [38:0] nx_name1_row(input [2:0] row);
    case (row)
        3'd0: nx_name1_row = 39'b011111001100011000111000011111001100011;
        3'd1: nx_name1_row = 39'b110001101110111001101100110001101100011;
        3'd2: nx_name1_row = 39'b110000001111111011000110110000001100011;
        3'd3: nx_name1_row = 39'b011111001101011011000110011111001111111;
        3'd4: nx_name1_row = 39'b000001101101011011111110000001101100011;
        3'd5: nx_name1_row = 39'b110001101100011011000110110001101100011;
        3'd6: nx_name1_row = 39'b011111001100011011000110011111001100011;
        default: nx_name1_row = 39'd0;
    endcase
endfunction
function nx_name1_lit(input [9:0] dx, input [9:0] dy);
    reg [38:0] r;
    begin
        r = nx_name1_row(dy[2:0]);
        nx_name1_lit = (dx < 39 && dy < 8) ? r[38 - dx] : 1'b0;
    end
endfunction

localparam NX_NAME2_W = 31;
localparam NX_NAME2_H = 8;
function [30:0] nx_name2_row(input [2:0] row);
    case (row)
        3'd0: nx_name2_row = 31'b0111110001100000011111001101011;
        3'd1: nx_name2_row = 31'b1100011001100000110001101101011;
        3'd2: nx_name2_row = 31'b1100000001100000110001101101011;
        3'd3: nx_name2_row = 31'b0111110001100000110001101101011;
        3'd4: nx_name2_row = 31'b0000011001100000110001101111111;
        3'd5: nx_name2_row = 31'b1100011001100000110001101110111;
        3'd6: nx_name2_row = 31'b0111110001111110011111000100010;
        default: nx_name2_row = 31'd0;
    endcase
endfunction
function nx_name2_lit(input [9:0] dx, input [9:0] dy);
    reg [30:0] r;
    begin
        r = nx_name2_row(dy[2:0]);
        nx_name2_lit = (dx < 31 && dy < 8) ? r[30 - dx] : 1'b0;
    end
endfunction

localparam NX_NAME3_W = 39;
localparam NX_NAME3_H = 8;
function [38:0] nx_name3_row(input [2:0] row);
    case (row)
        3'd0: nx_name3_row = 39'b001111001100011011111100110001101111111;
        3'd1: nx_name3_row = 39'b011001101100011011000110110001101100000;
        3'd2: nx_name3_row = 39'b110000001100011011000110110001101100000;
        3'd3: nx_name3_row = 39'b110000001100011011001110111011101111110;
        3'd4: nx_name3_row = 39'b110000001100011011111000011111001100000;
        3'd5: nx_name3_row = 39'b011001101100011011011100001110001100000;
        3'd6: nx_name3_row = 39'b001111000111110011001110000100001111111;
        default: nx_name3_row = 39'd0;
    endcase
endfunction
function nx_name3_lit(input [9:0] dx, input [9:0] dy);
    reg [38:0] r;
    begin
        r = nx_name3_row(dy[2:0]);
        nx_name3_lit = (dx < 39 && dy < 8) ? r[38 - dx] : 1'b0;
    end
endfunction

localparam NX_NAME4_W = 39;
localparam NX_NAME4_H = 8;
function [38:0] nx_name4_row(input [2:0] row);
    case (row)
        3'd0: nx_name4_row = 39'b001111101100011001111100011111000111111;
        3'd1: nx_name4_row = 39'b011000001100011011000110110001100001100;
        3'd2: nx_name4_row = 39'b110000001100011011000110110000000001100;
        3'd3: nx_name4_row = 39'b110011101111111011000110011111000001100;
        3'd4: nx_name4_row = 39'b110001101100011011000110000001100001100;
        3'd5: nx_name4_row = 39'b011001101100011011000110110001100001100;
        3'd6: nx_name4_row = 39'b001111101100011001111100011111000001100;
        default: nx_name4_row = 39'd0;
    endcase
endfunction
function nx_name4_lit(input [9:0] dx, input [9:0] dy);
    reg [38:0] r;
    begin
        r = nx_name4_row(dy[2:0]);
        nx_name4_lit = (dx < 39 && dy < 8) ? r[38 - dx] : 1'b0;
    end
endfunction

localparam NX_NAME5_W = 39;
localparam NX_NAME5_H = 8;
function [38:0] nx_name5_row(input [2:0] row);
    case (row)
        3'd0: nx_name5_row = 39'b011111001100011011111100111111101111110;
        3'd1: nx_name5_row = 39'b110001101100011011000110110000001100011;
        3'd2: nx_name5_row = 39'b110000001100011011000110110000001100011;
        3'd3: nx_name5_row = 39'b011111001100011011000110111111001100111;
        3'd4: nx_name5_row = 39'b000001101100011011111100110000001111100;
        3'd5: nx_name5_row = 39'b110001101100011011000000110000001101110;
        3'd6: nx_name5_row = 39'b011111000111110011000000111111101100111;
        default: nx_name5_row = 39'd0;
    endcase
endfunction
function nx_name5_lit(input [9:0] dx, input [9:0] dy);
    reg [38:0] r;
    begin
        r = nx_name5_row(dy[2:0]);
        nx_name5_lit = (dx < 39 && dy < 8) ? r[38 - dx] : 1'b0;
    end
endfunction

localparam NX_NAME6_W = 39;
localparam NX_NAME6_H = 8;
function [38:0] nx_name6_row(input [2:0] row);
    case (row)
        3'd0: nx_name6_row = 39'b011111000111111011111110111111101111110;
        3'd1: nx_name6_row = 39'b110001100001100011000000110000001100011;
        3'd2: nx_name6_row = 39'b110000000001100011000000110000001100011;
        3'd3: nx_name6_row = 39'b011111000001100011111100111111001100111;
        3'd4: nx_name6_row = 39'b000001100001100011000000110000001111100;
        3'd5: nx_name6_row = 39'b110001100001100011000000110000001101110;
        3'd6: nx_name6_row = 39'b011111000001100011111110111111101100111;
        default: nx_name6_row = 39'd0;
    endcase
endfunction
function nx_name6_lit(input [9:0] dx, input [9:0] dy);
    reg [38:0] r;
    begin
        r = nx_name6_row(dy[2:0]);
        nx_name6_lit = (dx < 39 && dy < 8) ? r[38 - dx] : 1'b0;
    end
endfunction

localparam NX_NAME7_W = 47;
localparam NX_NAME7_H = 8;
function [46:0] nx_name7_row(input [2:0] row);
    case (row)
        3'd0: nx_name7_row = 47'b11111100110001100110000001100000111111100111111;
        3'd1: nx_name7_row = 47'b11000110110001100110000001100000110000000001100;
        3'd2: nx_name7_row = 47'b11000110110001100110000001100000110000000001100;
        3'd3: nx_name7_row = 47'b11111100110001100110000001100000111111000001100;
        3'd4: nx_name7_row = 47'b11000110110001100110000001100000110000000001100;
        3'd5: nx_name7_row = 47'b11000110110001100110000001100000110000000001100;
        3'd6: nx_name7_row = 47'b11111100011111000111111001111110111111100001100;
        default: nx_name7_row = 47'd0;
    endcase
endfunction
function nx_name7_lit(input [9:0] dx, input [9:0] dy);
    reg [46:0] r;
    begin
        r = nx_name7_row(dy[2:0]);
        nx_name7_lit = (dx < 47 && dy < 8) ? r[46 - dx] : 1'b0;
    end
endfunction

localparam NX_PPICK_W = 127;
localparam NX_PPICK_H = 8;
function [126:0] nx_ppick_row(input [2:0] row);
    case (row)
        3'd0: nx_ppick_row = 127'b1111110001111110001111001100011000000000011001100111110011000110111111000000000011111100001110001111100011111000011000001111111;
        3'd1: nx_ppick_row = 127'b1100011000011000011001101100110000000000011001101100011011000110110001100000000011000110011011001100110011001100011000001100000;
        3'd2: nx_ppick_row = 127'b1100011000011000110000001101100000000000011001101100011011000110110001100000000011000110110001101100011011000110011000001100000;
        3'd3: nx_ppick_row = 127'b1100011000011000110000001111000000000000001111001100011011000110110011100000000011000110110001101100011011000110011000001111110;
        3'd4: nx_ppick_row = 127'b1111110000011000110000001111100000000000000110001100011011000110111110000000000011111100111111101100011011000110011000001100000;
        3'd5: nx_ppick_row = 127'b1100000000011000011001101101110000000000000110001100011011000110110111000000000011000000110001101100110011001100011000001100000;
        3'd6: nx_ppick_row = 127'b1100000001111110001111001100111000000000000110000111110001111100110011100000000011000000110001101111100011111000011111101111111;
        default: nx_ppick_row = 127'd0;
    endcase
endfunction
function nx_ppick_lit(input [9:0] dx, input [9:0] dy);
    reg [126:0] r;
    begin
        r = nx_ppick_row(dy[2:0]);
        nx_ppick_lit = (dx < 127 && dy < 8) ? r[126 - dx] : 1'b0;
    end
endfunction

localparam NX_OK_W = 15;
localparam NX_OK_H = 8;
function [14:0] nx_ok_row(input [2:0] row);
    case (row)
        3'd0: nx_ok_row = 15'b011111001100011;
        3'd1: nx_ok_row = 15'b110001101100110;
        3'd2: nx_ok_row = 15'b110001101101100;
        3'd3: nx_ok_row = 15'b110001101111000;
        3'd4: nx_ok_row = 15'b110001101111100;
        3'd5: nx_ok_row = 15'b110001101101110;
        3'd6: nx_ok_row = 15'b011111001100111;
        default: nx_ok_row = 15'd0;
    endcase
endfunction
function nx_ok_lit(input [9:0] dx, input [9:0] dy);
    reg [14:0] r;
    begin
        r = nx_ok_row(dy[2:0]);
        nx_ok_lit = (dx < 15 && dy < 8) ? r[14 - dx] : 1'b0;
    end
endfunction

localparam NX_KIND0_W = 47;
localparam NX_KIND0_H = 8;
function [46:0] nx_kind0_row(input [2:0] row);
    case (row)
        3'd0: nx_kind0_row = 47'b00111000111111000011110000111000111110001111111;
        3'd1: nx_kind0_row = 47'b01101100110001100110011001101100110011001100000;
        3'd2: nx_kind0_row = 47'b11000110110001101100000011000110110001101100000;
        3'd3: nx_kind0_row = 47'b11000110110011101100000011000110110001101111110;
        3'd4: nx_kind0_row = 47'b11111110111110001100000011111110110001101100000;
        3'd5: nx_kind0_row = 47'b11000110110111000110011011000110110011001100000;
        3'd6: nx_kind0_row = 47'b11000110110011100011110011000110111110001111111;
        default: nx_kind0_row = 47'd0;
    endcase
endfunction
function nx_kind0_lit(input [9:0] dx, input [9:0] dy);
    reg [46:0] r;
    begin
        r = nx_kind0_row(dy[2:0]);
        nx_kind0_lit = (dx < 47 && dy < 8) ? r[46 - dx] : 1'b0;
    end
endfunction

localparam NX_KIND1_W = 39;
localparam NX_KIND1_H = 8;
function [38:0] nx_kind1_row(input [2:0] row);
    case (row)
        3'd0: nx_kind1_row = 39'b011111100111111001111110001110001100011;
        3'd1: nx_kind1_row = 39'b000110000001100000011000011011001110011;
        3'd2: nx_kind1_row = 39'b000110000001100000011000110001101111011;
        3'd3: nx_kind1_row = 39'b000110000001100000011000110001101101111;
        3'd4: nx_kind1_row = 39'b000110000001100000011000111111101100111;
        3'd5: nx_kind1_row = 39'b000110000001100000011000110001101100011;
        3'd6: nx_kind1_row = 39'b000110000111111000011000110001101100011;
        default: nx_kind1_row = 39'd0;
    endcase
endfunction
function nx_kind1_lit(input [9:0] dx, input [9:0] dy);
    reg [38:0] r;
    begin
        r = nx_kind1_row(dy[2:0]);
        nx_kind1_lit = (dx < 39 && dy < 8) ? r[38 - dx] : 1'b0;
    end
endfunction

localparam NX_KIND2_W = 47;
localparam NX_KIND2_H = 8;
function [46:0] nx_kind2_row(input [2:0] row);
    case (row)
        3'd0: nx_kind2_row = 47'b11000110001110001100011011000110111111101111110;
        3'd1: nx_kind2_row = 47'b11000110011011001110111011101110110000001100011;
        3'd2: nx_kind2_row = 47'b11000110110001101111111011111110110000001100011;
        3'd3: nx_kind2_row = 47'b11111110110001101101011011010110111111001100111;
        3'd4: nx_kind2_row = 47'b11000110111111101101011011010110110000001111100;
        3'd5: nx_kind2_row = 47'b11000110110001101100011011000110110000001101110;
        3'd6: nx_kind2_row = 47'b11000110110001101100011011000110111111101100111;
        default: nx_kind2_row = 47'd0;
    endcase
endfunction
function nx_kind2_lit(input [9:0] dx, input [9:0] dy);
    reg [46:0] r;
    begin
        r = nx_kind2_row(dy[2:0]);
        nx_kind2_lit = (dx < 47 && dy < 8) ? r[46 - dx] : 1'b0;
    end
endfunction

localparam NX_KIND3_W = 39;
localparam NX_KIND3_H = 8;
function [38:0] nx_kind3_row(input [2:0] row);
    case (row)
        3'd0: nx_kind3_row = 39'b011111101101011001111110011111000111111;
        3'd1: nx_kind3_row = 39'b000110001101011000011000110001100001100;
        3'd2: nx_kind3_row = 39'b000110001101011000011000110000000001100;
        3'd3: nx_kind3_row = 39'b000110001101011000011000011111000001100;
        3'd4: nx_kind3_row = 39'b000110001111111000011000000001100001100;
        3'd5: nx_kind3_row = 39'b000110001110111000011000110001100001100;
        3'd6: nx_kind3_row = 39'b000110000100010001111110011111000001100;
        default: nx_kind3_row = 39'd0;
    endcase
endfunction
function nx_kind3_lit(input [9:0] dx, input [9:0] dy);
    reg [38:0] r;
    begin
        r = nx_kind3_row(dy[2:0]);
        nx_kind3_lit = (dx < 39 && dy < 8) ? r[38 - dx] : 1'b0;
    end
endfunction

localparam NX_KIND4_W = 55;
localparam NX_KIND4_H = 8;
function [54:0] nx_kind4_row(input [2:0] row);
    case (row)
        3'd0: nx_kind4_row = 55'b1111110001100000001110000111110001111110111111101111110;
        3'd1: nx_kind4_row = 55'b1100011001100000011011001100011000011000110000001100011;
        3'd2: nx_kind4_row = 55'b1100011001100000110001101100000000011000110000001100011;
        3'd3: nx_kind4_row = 55'b1111110001100000110001100111110000011000111111001100111;
        3'd4: nx_kind4_row = 55'b1100011001100000111111100000011000011000110000001111100;
        3'd5: nx_kind4_row = 55'b1100011001100000110001101100011000011000110000001101110;
        3'd6: nx_kind4_row = 55'b1111110001111110110001100111110000011000111111101100111;
        default: nx_kind4_row = 55'd0;
    endcase
endfunction
function nx_kind4_lit(input [9:0] dx, input [9:0] dy);
    reg [54:0] r;
    begin
        r = nx_kind4_row(dy[2:0]);
        nx_kind4_lit = (dx < 55 && dy < 8) ? r[54 - dx] : 1'b0;
    end
endfunction

localparam NX_KIND5_W = 31;
localparam NX_KIND5_H = 8;
function [30:0] nx_kind5_row(input [2:0] row);
    case (row)
        3'd0: nx_kind5_row = 31'b1111110011000110011111001100011;
        3'd1: nx_kind5_row = 31'b1100011011000110110001101100011;
        3'd2: nx_kind5_row = 31'b1100011011000110110000001100011;
        3'd3: nx_kind5_row = 31'b1100111011000110011111001111111;
        3'd4: nx_kind5_row = 31'b1111100011000110000001101100011;
        3'd5: nx_kind5_row = 31'b1101110011000110110001101100011;
        3'd6: nx_kind5_row = 31'b1100111001111100011111001100011;
        default: nx_kind5_row = 31'd0;
    endcase
endfunction
function nx_kind5_lit(input [9:0] dx, input [9:0] dy);
    reg [30:0] r;
    begin
        r = nx_kind5_row(dy[2:0]);
        nx_kind5_lit = (dx < 31 && dy < 8) ? r[30 - dx] : 1'b0;
    end
endfunction

localparam NX_KIND6_W = 63;
localparam NX_KIND6_H = 8;
function [62:0] nx_kind6_row(input [2:0] row);
    case (row)
        3'd0: nx_kind6_row = 63'b001111101100011000111000111111001111100001111110001110001100011;
        3'd1: nx_kind6_row = 63'b011000001100011001101100110001101100110000011000011011001110011;
        3'd2: nx_kind6_row = 63'b110000001100011011000110110001101100011000011000110001101111011;
        3'd3: nx_kind6_row = 63'b110011101100011011000110110011101100011000011000110001101101111;
        3'd4: nx_kind6_row = 63'b110001101100011011111110111110001100011000011000111111101100111;
        3'd5: nx_kind6_row = 63'b011001101100011011000110110111001100110000011000110001101100011;
        3'd6: nx_kind6_row = 63'b001111100111110011000110110011101111100001111110110001101100011;
        default: nx_kind6_row = 63'd0;
    endcase
endfunction
function nx_kind6_lit(input [9:0] dx, input [9:0] dy);
    reg [62:0] r;
    begin
        r = nx_kind6_row(dy[2:0]);
        nx_kind6_lit = (dx < 63 && dy < 8) ? r[62 - dx] : 1'b0;
    end
endfunction

localparam NX_TAG0_W = 95;
localparam NX_TAG0_H = 8;
function [94:0] nx_tag0_row(input [2:0] row);
    case (row)
        3'd0: nx_tag0_row = 95'b11000110011111001111110011111110000000001111110001111100110001101100011001111100111111100111110;
        3'd1: nx_tag0_row = 95'b11101110110001101100011011000000000000001100011011000110111001101100011011000110110000001100011;
        3'd2: nx_tag0_row = 95'b11111110110001101100011011000000000000001100011011000110111101101100011011000000110000001100000;
        3'd3: nx_tag0_row = 95'b11010110110001101100111011111100000000001111110011000110110111101100011001111100111111000111110;
        3'd4: nx_tag0_row = 95'b11010110110001101111100011000000000000001100011011000110110011101100011000000110110000000000011;
        3'd5: nx_tag0_row = 95'b11000110110001101101110011000000000000001100011011000110110001101100011011000110110000001100011;
        3'd6: nx_tag0_row = 95'b11000110011111001100111011111110000000001111110001111100110001100111110001111100111111100111110;
        default: nx_tag0_row = 95'd0;
    endcase
endfunction
function nx_tag0_lit(input [9:0] dx, input [9:0] dy);
    reg [94:0] r;
    begin
        r = nx_tag0_row(dy[2:0]);
        nx_tag0_lit = (dx < 95 && dy < 8) ? r[94 - dx] : 1'b0;
    end
endfunction

localparam NX_TAG1_W = 103;
localparam NX_TAG1_H = 8;
function [102:0] nx_tag1_row(input [2:0] row);
    case (row)
        3'd0: nx_tag1_row = 103'b0111111000111000011000000110000000000000111111001100011001111110000000000111110001100000011111001101011;
        3'd1: nx_tag1_row = 103'b0001100001101100011000000110000000000000110001101100011000011000000000001100011001100000110001101101011;
        3'd2: nx_tag1_row = 103'b0001100011000110011000000110000000000000110001101100011000011000000000001100000001100000110001101101011;
        3'd3: nx_tag1_row = 103'b0001100011000110011000000110000000000000111111001100011000011000000000000111110001100000110001101101011;
        3'd4: nx_tag1_row = 103'b0001100011111110011000000110000000000000110001101100011000011000000000000000011001100000110001101111111;
        3'd5: nx_tag1_row = 103'b0001100011000110011000000110000000000000110001101100011000011000000000001100011001100000110001101110111;
        3'd6: nx_tag1_row = 103'b0001100011000110011111100111111000000000111111000111110000011000000000000111110001111110011111000100010;
        default: nx_tag1_row = 103'd0;
    endcase
endfunction
function nx_tag1_lit(input [9:0] dx, input [9:0] dy);
    reg [102:0] r;
    begin
        r = nx_tag1_row(dy[2:0]);
        nx_tag1_lit = (dx < 103 && dy < 8) ? r[102 - dx] : 1'b0;
    end
endfunction

localparam NX_TAG2_W = 87;
localparam NX_TAG2_H = 8;
function [86:0] nx_tag2_row(input [2:0] row);
    case (row)
        3'd0: nx_tag2_row = 87'b111111000111110011010110111111101111110000000000011111001100011001111100011111100111110;
        3'd1: nx_tag2_row = 87'b110001101100011011010110110000001100011000000000110001101100011011000110000110001100011;
        3'd2: nx_tag2_row = 87'b110001101100011011010110110000001100011000000000110000001100011011000110000110001100000;
        3'd3: nx_tag2_row = 87'b110001101100011011010110111111001100111000000000011111001111111011000110000110000111110;
        3'd4: nx_tag2_row = 87'b111111001100011011111110110000001111100000000000000001101100011011000110000110000000011;
        3'd5: nx_tag2_row = 87'b110000001100011011101110110000001101110000000000110001101100011011000110000110001100011;
        3'd6: nx_tag2_row = 87'b110000000111110001000100111111101100111000000000011111001100011001111100000110000111110;
        default: nx_tag2_row = 87'd0;
    endcase
endfunction
function nx_tag2_lit(input [9:0] dx, input [9:0] dy);
    reg [86:0] r;
    begin
        r = nx_tag2_row(dy[2:0]);
        nx_tag2_lit = (dx < 87 && dy < 8) ? r[86 - dx] : 1'b0;
    end
endfunction

localparam NX_TAG3_W = 127;
localparam NX_TAG3_H = 8;
function [126:0] nx_tag3_row(input [2:0] row);
    case (row)
        3'd0: nx_tag3_row = 127'b0111111001111110011000000111111001111100000000001101011001111110011111101100011000000000011111001111110011111110111111101111100;
        3'd1: nx_tag3_row = 127'b0001100000011000011000000001100011000110000000001101011000011000000110001100011000000000110001101100011011000000110000001100110;
        3'd2: nx_tag3_row = 127'b0001100000011000011000000001100011000000000000001101011000011000000110001100011000000000110000001100011011000000110000001100011;
        3'd3: nx_tag3_row = 127'b0001100000011000011000000001100001111100000000001101011000011000000110001111111000000000011111001100011011111100111111001100011;
        3'd4: nx_tag3_row = 127'b0001100000011000011000000001100000000110000000001111111000011000000110001100011000000000000001101111110011000000110000001100011;
        3'd5: nx_tag3_row = 127'b0001100000011000011000000001100011000110000000001110111000011000000110001100011000000000110001101100000011000000110000001100110;
        3'd6: nx_tag3_row = 127'b0001100001111110011111100001100001111100000000000100010001111110000110001100011000000000011111001100000011111110111111101111100;
        default: nx_tag3_row = 127'd0;
    endcase
endfunction
function nx_tag3_lit(input [9:0] dx, input [9:0] dy);
    reg [126:0] r;
    begin
        r = nx_tag3_row(dy[2:0]);
        nx_tag3_lit = (dx < 127 && dy < 8) ? r[126 - dx] : 1'b0;
    end
endfunction

localparam NX_TAG4_W = 119;
localparam NX_TAG4_H = 8;
function [118:0] nx_tag4_row(input [2:0] row);
    case (row)
        3'd0: nx_tag4_row = 119'b01111100110001100111110001111100011111100111110000000000001111000011100011111100011111001100011001100000111111100111110;
        3'd1: nx_tag4_row = 119'b11000110110001101100011011000110000110001100011000000000011001100110110011000110110001101100011001100000110000001100011;
        3'd2: nx_tag4_row = 119'b11000000110001101100011011000110000110001100000000000000110000001100011011000110110000001100011001100000110000001100000;
        3'd3: nx_tag4_row = 119'b01111100111111101100011011000110000110000111110000000000110000001100011011000110011111001100011001100000111111000111110;
        3'd4: nx_tag4_row = 119'b00000110110001101100011011000110000110000000011000000000110000001111111011111100000001101100011001100000110000000000011;
        3'd5: nx_tag4_row = 119'b11000110110001101100011011000110000110001100011000000000011001101100011011000000110001101100011001100000110000001100011;
        3'd6: nx_tag4_row = 119'b01111100110001100111110001111100000110000111110000000000001111001100011011000000011111000111110001111110111111100111110;
        default: nx_tag4_row = 119'd0;
    endcase
endfunction
function nx_tag4_lit(input [9:0] dx, input [9:0] dy);
    reg [118:0] r;
    begin
        r = nx_tag4_row(dy[2:0]);
        nx_tag4_lit = (dx < 119 && dy < 8) ? r[118 - dx] : 1'b0;
    end
endfunction

localparam NX_TAG5_W = 71;
localparam NX_TAG5_H = 8;
function [70:0] nx_tag5_row(input [2:0] row);
    case (row)
        3'd0: nx_tag5_row = 71'b01100000011111001100011000111110000000001111100000111000011111001100011;
        3'd1: nx_tag5_row = 71'b01100000110001101110011001100000000000001100110001101100110001101100011;
        3'd2: nx_tag5_row = 71'b01100000110001101111011011000000000000001100011011000110110000001100011;
        3'd3: nx_tag5_row = 71'b01100000110001101101111011001110000000001100011011000110011111001111111;
        3'd4: nx_tag5_row = 71'b01100000110001101100111011000110000000001100011011111110000001101100011;
        3'd5: nx_tag5_row = 71'b01100000110001101100011001100110000000001100110011000110110001101100011;
        3'd6: nx_tag5_row = 71'b01111110011111001100011000111110000000001111100011000110011111001100011;
        default: nx_tag5_row = 71'd0;
    endcase
endfunction
function nx_tag5_lit(input [9:0] dx, input [9:0] dy);
    reg [70:0] r;
    begin
        r = nx_tag5_row(dy[2:0]);
        nx_tag5_lit = (dx < 71 && dy < 8) ? r[70 - dx] : 1'b0;
    end
endfunction

localparam NX_TAG6_W = 119;
localparam NX_TAG6_H = 8;
function [118:0] nx_tag6_row(input [2:0] row);
    case (row)
        3'd0: nx_tag6_row = 119'b11111110011111101100011011111110000000001111110001111110111111100011110011111110000000001101011000111000011000000110000;
        3'd1: nx_tag6_row = 119'b11000000000110001100011011000000000000001100011000011000110000000110011011000000000000001101011001101100011000000110000;
        3'd2: nx_tag6_row = 119'b11000000000110001100011011000000000000001100011000011000110000001100000011000000000000001101011011000110011000000110000;
        3'd3: nx_tag6_row = 119'b11111100000110001110111011111100011111101100011000011000111111001100000011111100000000001101011011000110011000000110000;
        3'd4: nx_tag6_row = 119'b11000000000110000111110011000000000000001111110000011000110000001100000011000000000000001111111011111110011000000110000;
        3'd5: nx_tag6_row = 119'b11000000000110000011100011000000000000001100000000011000110000000110011011000000000000001110111011000110011000000110000;
        3'd6: nx_tag6_row = 119'b11000000011111100001000011111110000000001100000001111110111111100011110011111110000000000100010011000110011111100111111;
        default: nx_tag6_row = 119'd0;
    endcase
endfunction
function nx_tag6_lit(input [9:0] dx, input [9:0] dy);
    reg [118:0] r;
    begin
        r = nx_tag6_row(dy[2:0]);
        nx_tag6_lit = (dx < 119 && dy < 8) ? r[118 - dx] : 1'b0;
    end
endfunction

localparam NX_MOVE0_W = 103;
localparam NX_MOVE0_H = 8;
function [102:0] nx_move0_row(input [2:0] row);
    case (row)
        3'd0: nx_move0_row = 103'b0111110001111110111111000011100001111110001111101100011001111110000000000111110011000110011111000111111;
        3'd1: nx_move0_row = 103'b1100011000011000110001100110110000011000011000001100011000011000000000001100011011000110110001100001100;
        3'd2: nx_move0_row = 103'b1100000000011000110001101100011000011000110000001100011000011000000000001100000011000110110001100001100;
        3'd3: nx_move0_row = 103'b0111110000011000110011101100011000011000110011101111111000011000000000000111110011111110110001100001100;
        3'd4: nx_move0_row = 103'b0000011000011000111110001111111000011000110001101100011000011000000000000000011011000110110001100001100;
        3'd5: nx_move0_row = 103'b1100011000011000110111001100011000011000011001101100011000011000000000001100011011000110110001100001100;
        3'd6: nx_move0_row = 103'b0111110000011000110011101100011001111110001111101100011000011000000000000111110011000110011111000001100;
        default: nx_move0_row = 103'd0;
    endcase
endfunction
function nx_move0_lit(input [9:0] dx, input [9:0] dy);
    reg [102:0] r;
    begin
        r = nx_move0_row(dy[2:0]);
        nx_move0_lit = (dx < 103 && dy < 8) ? r[102 - dx] : 1'b0;
    end
endfunction

localparam NX_MOVE1_W = 103;
localparam NX_MOVE1_H = 8;
function [102:0] nx_move1_row(input [2:0] row);
    case (row)
        3'd0: nx_move1_row = 103'b1111110001111110011111000111111011000110001111100000000001111100011111101111110001111110110001101111111;
        3'd1: nx_move1_row = 103'b1100011000011000110001100001100011100110011000000000000011000110000110001100011000011000110011001100000;
        3'd2: nx_move1_row = 103'b1100011000011000110000000001100011110110110000000000000011000000000110001100011000011000110110001100000;
        3'd3: nx_move1_row = 103'b1100111000011000011111000001100011011110110011100000000001111100000110001100111000011000111100001111110;
        3'd4: nx_move1_row = 103'b1111100000011000000001100001100011001110110001100000000000000110000110001111100000011000111110001100000;
        3'd5: nx_move1_row = 103'b1101110000011000110001100001100011000110011001100000000011000110000110001101110000011000110111001100000;
        3'd6: nx_move1_row = 103'b1100111001111110011111000111111011000110001111100000000001111100000110001100111001111110110011101111111;
        default: nx_move1_row = 103'd0;
    endcase
endfunction
function nx_move1_lit(input [9:0] dx, input [9:0] dy);
    reg [102:0] r;
    begin
        r = nx_move1_row(dy[2:0]);
        nx_move1_lit = (dx < 103 && dy < 8) ? r[102 - dx] : 1'b0;
    end
endfunction

localparam NX_MAX_W = 23;
localparam NX_MAX_H = 8;
function [22:0] nx_max_row(input [2:0] row);
    case (row)
        3'd0: nx_max_row = 23'b11000110001110001100011;
        3'd1: nx_max_row = 23'b11101110011011001100011;
        3'd2: nx_max_row = 23'b11111110110001100110110;
        3'd3: nx_max_row = 23'b11010110110001100011100;
        3'd4: nx_max_row = 23'b11010110111111100110110;
        3'd5: nx_max_row = 23'b11000110110001101100011;
        3'd6: nx_max_row = 23'b11000110110001101100011;
        default: nx_max_row = 23'd0;
    endcase
endfunction
function nx_max_lit(input [9:0] dx, input [9:0] dy);
    reg [22:0] r;
    begin
        r = nx_max_row(dy[2:0]);
        nx_max_lit = (dx < 23 && dy < 8) ? r[22 - dx] : 1'b0;
    end
endfunction

localparam [14:0] NX_P1_COLS = 15'b111111100111111;
function nx_p1_col(input [9:0] dx);
    nx_p1_col = (dx < 15) ? NX_P1_COLS[14 - dx] : 1'b0;
endfunction

localparam [14:0] NX_P2_COLS = 15'b111111101111111;
function nx_p2_col(input [9:0] dx);
    nx_p2_col = (dx < 15) ? NX_P2_COLS[14 - dx] : 1'b0;
endfunction

localparam [22:0] NX_MAX_COLS = 23'b11111110111111101111111;
function nx_max_col(input [9:0] dx);
    nx_max_col = (dx < 23) ? NX_MAX_COLS[22 - dx] : 1'b0;
endfunction

localparam [102:0] NX_MOVE0_COLS = 103'b1111111001111110111111101111111001111110111111101111111001111110000000001111111011111110111111100111111;
function nx_move0_col(input [9:0] dx);
    nx_move0_col = (dx < 103) ? NX_MOVE0_COLS[102 - dx] : 1'b0;
endfunction

localparam [102:0] NX_MOVE1_COLS = 103'b1111111001111110111111100111111011111110111111100000000011111110011111101111111001111110111111101111111;
function nx_move1_col(input [9:0] dx);
    nx_move1_col = (dx < 103) ? NX_MOVE1_COLS[102 - dx] : 1'b0;
endfunction

localparam [6:0] NX_BANG_COLS = 7'b0011100;
function nx_bang_col(input [9:0] dx);
    nx_bang_col = (dx < 7) ? NX_BANG_COLS[6 - dx] : 1'b0;
endfunction

function [6:0] kind_l1(input [2:0] kind, input [3:0] i);
    case ({kind, i})
        {3'd0, 4'd0}: kind_l1 = 7'd7;
        {3'd0, 4'd1}: kind_l1 = 7'd15;
        {3'd0, 4'd2}: kind_l1 = 7'd23;
        {3'd0, 4'd3}: kind_l1 = 7'd31;
        {3'd0, 4'd4}: kind_l1 = 7'd39;
        {3'd0, 4'd5}: kind_l1 = 7'd47;
        {3'd1, 4'd0}: kind_l1 = 7'd7;
        {3'd1, 4'd1}: kind_l1 = 7'd15;
        {3'd1, 4'd2}: kind_l1 = 7'd23;
        {3'd1, 4'd3}: kind_l1 = 7'd31;
        {3'd1, 4'd4}: kind_l1 = 7'd39;
        {3'd2, 4'd0}: kind_l1 = 7'd7;
        {3'd2, 4'd1}: kind_l1 = 7'd15;
        {3'd2, 4'd2}: kind_l1 = 7'd23;
        {3'd2, 4'd3}: kind_l1 = 7'd31;
        {3'd2, 4'd4}: kind_l1 = 7'd39;
        {3'd2, 4'd5}: kind_l1 = 7'd47;
        {3'd3, 4'd0}: kind_l1 = 7'd7;
        {3'd3, 4'd1}: kind_l1 = 7'd15;
        {3'd3, 4'd2}: kind_l1 = 7'd23;
        {3'd3, 4'd3}: kind_l1 = 7'd31;
        {3'd3, 4'd4}: kind_l1 = 7'd39;
        {3'd4, 4'd0}: kind_l1 = 7'd7;
        {3'd4, 4'd1}: kind_l1 = 7'd15;
        {3'd4, 4'd2}: kind_l1 = 7'd23;
        {3'd4, 4'd3}: kind_l1 = 7'd31;
        {3'd4, 4'd4}: kind_l1 = 7'd39;
        {3'd4, 4'd5}: kind_l1 = 7'd47;
        {3'd4, 4'd6}: kind_l1 = 7'd55;
        {3'd5, 4'd0}: kind_l1 = 7'd7;
        {3'd5, 4'd1}: kind_l1 = 7'd15;
        {3'd5, 4'd2}: kind_l1 = 7'd23;
        {3'd5, 4'd3}: kind_l1 = 7'd31;
        {3'd6, 4'd0}: kind_l1 = 7'd7;
        {3'd6, 4'd1}: kind_l1 = 7'd15;
        {3'd6, 4'd2}: kind_l1 = 7'd23;
        {3'd6, 4'd3}: kind_l1 = 7'd31;
        {3'd6, 4'd4}: kind_l1 = 7'd39;
        {3'd6, 4'd5}: kind_l1 = 7'd47;
        {3'd6, 4'd6}: kind_l1 = 7'd55;
        {3'd6, 4'd7}: kind_l1 = 7'd63;
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
        3'd0: name_w = 63;
        3'd1: name_w = 39;
        3'd2: name_w = 31;
        3'd3: name_w = 39;
        3'd4: name_w = 39;
        3'd5: name_w = 39;
        3'd6: name_w = 39;
        3'd7: name_w = 47;
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
        3'd0: kind_name_w = 47;
        3'd1: kind_name_w = 39;
        3'd2: kind_name_w = 47;
        3'd3: kind_name_w = 39;
        3'd4: kind_name_w = 55;
        3'd5: kind_name_w = 31;
        3'd6: kind_name_w = 63;
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
        3'd0: tag_w = 95;
        3'd1: tag_w = 103;
        3'd2: tag_w = 87;
        3'd3: tag_w = 127;
        3'd4: tag_w = 119;
        3'd5: tag_w = 71;
        3'd6: tag_w = 119;
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
        3'd0: move_w = 103;
        3'd1: move_w = 103;
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
