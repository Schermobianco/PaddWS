// Generato da tools/gen_challenge_assets.py: non modificare a mano.

localparam CH_INTRO0_W = 47;
localparam CH_INTRO0_H = 8;
function [46:0] ch_intro0_row(input [2:0] row);
    case (row)
        3'd0: ch_intro0_row = 47'b10001110100010111010000000100000110011100001110;
        3'd1: ch_intro0_row = 47'b10001000100010100010000001100001001010000000010;
        3'd2: ch_intro0_row = 47'b10001000100010100010000000100001001010000000010;
        3'd3: ch_intro0_row = 47'b10001110010100111010000000100001001011100000100;
        3'd4: ch_intro0_row = 47'b10001000010100100010000000100001001010000000100;
        3'd5: ch_intro0_row = 47'b10001000001000100010000000100001001010000001000;
        3'd6: ch_intro0_row = 47'b11101110001000111011100000100000110010000001000;
        default: ch_intro0_row = 47'd0;
    endcase
endfunction
function ch_intro0_lit(input [9:0] dx, input [9:0] dy);
    reg [46:0] r;
    begin
        r = ch_intro0_row(dy[2:0]);
        ch_intro0_lit = (dx < 47 && dy < 8) ? r[46 - dx] : 1'b0;
    end
endfunction

localparam CH_INTRO1_W = 48;
localparam CH_INTRO1_H = 8;
function [47:0] ch_intro1_row(input [2:0] row);
    case (row)
        3'd0: ch_intro1_row = 48'b100011101000101110100000011000000110011100001110;
        3'd1: ch_intro1_row = 48'b100010001000101000100000000100001001010000000010;
        3'd2: ch_intro1_row = 48'b100010001000101000100000000100001001010000000010;
        3'd3: ch_intro1_row = 48'b100011100101001110100000001000001001011100000100;
        3'd4: ch_intro1_row = 48'b100010000101001000100000010000001001010000000100;
        3'd5: ch_intro1_row = 48'b100010000010001000100000010000001001010000001000;
        3'd6: ch_intro1_row = 48'b111011100010001110111000011100000110010000001000;
        default: ch_intro1_row = 48'd0;
    endcase
endfunction
function ch_intro1_lit(input [9:0] dx, input [9:0] dy);
    reg [47:0] r;
    begin
        r = ch_intro1_row(dy[2:0]);
        ch_intro1_lit = (dx < 48 && dy < 8) ? r[47 - dx] : 1'b0;
    end
endfunction

localparam CH_INTRO2_W = 48;
localparam CH_INTRO2_H = 8;
function [47:0] ch_intro2_row(input [2:0] row);
    case (row)
        3'd0: ch_intro2_row = 48'b100011101000101110100000011000000110011100001110;
        3'd1: ch_intro2_row = 48'b100010001000101000100000000100001001010000000010;
        3'd2: ch_intro2_row = 48'b100010001000101000100000000100001001010000000010;
        3'd3: ch_intro2_row = 48'b100011100101001110100000011000001001011100000100;
        3'd4: ch_intro2_row = 48'b100010000101001000100000000100001001010000000100;
        3'd5: ch_intro2_row = 48'b100010000010001000100000000100001001010000001000;
        3'd6: ch_intro2_row = 48'b111011100010001110111000011000000110010000001000;
        default: ch_intro2_row = 48'd0;
    endcase
endfunction
function ch_intro2_lit(input [9:0] dx, input [9:0] dy);
    reg [47:0] r;
    begin
        r = ch_intro2_row(dy[2:0]);
        ch_intro2_lit = (dx < 48 && dy < 8) ? r[47 - dx] : 1'b0;
    end
endfunction

localparam CH_INTRO3_W = 49;
localparam CH_INTRO3_H = 8;
function [48:0] ch_intro3_row(input [2:0] row);
    case (row)
        3'd0: ch_intro3_row = 49'b1000111010001011101000000100000000110011100001110;
        3'd1: ch_intro3_row = 49'b1000100010001010001000000100000001001010000000010;
        3'd2: ch_intro3_row = 49'b1000100010001010001000000101000001001010000000010;
        3'd3: ch_intro3_row = 49'b1000111001010011101000000101000001001011100000100;
        3'd4: ch_intro3_row = 49'b1000100001010010001000000111100001001010000000100;
        3'd5: ch_intro3_row = 49'b1000100000100010001000000001000001001010000001000;
        3'd6: ch_intro3_row = 49'b1110111000100011101110000001000000110010000001000;
        default: ch_intro3_row = 49'd0;
    endcase
endfunction
function ch_intro3_lit(input [9:0] dx, input [9:0] dy);
    reg [48:0] r;
    begin
        r = ch_intro3_row(dy[2:0]);
        ch_intro3_lit = (dx < 49 && dy < 8) ? r[48 - dx] : 1'b0;
    end
endfunction

localparam CH_INTRO4_W = 48;
localparam CH_INTRO4_H = 8;
function [47:0] ch_intro4_row(input [2:0] row);
    case (row)
        3'd0: ch_intro4_row = 48'b100011101000101110100000011100000110011100001110;
        3'd1: ch_intro4_row = 48'b100010001000101000100000010000001001010000000010;
        3'd2: ch_intro4_row = 48'b100010001000101000100000010000001001010000000010;
        3'd3: ch_intro4_row = 48'b100011100101001110100000011000001001011100000100;
        3'd4: ch_intro4_row = 48'b100010000101001000100000000100001001010000000100;
        3'd5: ch_intro4_row = 48'b100010000010001000100000000100001001010000001000;
        3'd6: ch_intro4_row = 48'b111011100010001110111000011000000110010000001000;
        default: ch_intro4_row = 48'd0;
    endcase
endfunction
function ch_intro4_lit(input [9:0] dx, input [9:0] dy);
    reg [47:0] r;
    begin
        r = ch_intro4_row(dy[2:0]);
        ch_intro4_lit = (dx < 48 && dy < 8) ? r[47 - dx] : 1'b0;
    end
endfunction

localparam CH_INTRO5_W = 49;
localparam CH_INTRO5_H = 8;
function [48:0] ch_intro5_row(input [2:0] row);
    case (row)
        3'd0: ch_intro5_row = 49'b1000111010001011101000000011000000110011100001110;
        3'd1: ch_intro5_row = 49'b1000100010001010001000000100000001001010000000010;
        3'd2: ch_intro5_row = 49'b1000100010001010001000000100000001001010000000010;
        3'd3: ch_intro5_row = 49'b1000111001010011101000000111000001001011100000100;
        3'd4: ch_intro5_row = 49'b1000100001010010001000000100100001001010000000100;
        3'd5: ch_intro5_row = 49'b1000100000100010001000000100100001001010000001000;
        3'd6: ch_intro5_row = 49'b1110111000100011101110000011000000110010000001000;
        default: ch_intro5_row = 49'd0;
    endcase
endfunction
function ch_intro5_lit(input [9:0] dx, input [9:0] dy);
    reg [48:0] r;
    begin
        r = ch_intro5_row(dy[2:0]);
        ch_intro5_lit = (dx < 49 && dy < 8) ? r[48 - dx] : 1'b0;
    end
endfunction

localparam CH_INTRO6_W = 45;
localparam CH_INTRO6_H = 8;
function [44:0] ch_intro6_row(input [2:0] row);
    case (row)
        3'd0: ch_intro6_row = 45'b111010100100110010000001000111010001011101000;
        3'd1: ch_intro6_row = 45'b100010100101001010000001000100010001010001000;
        3'd2: ch_intro6_row = 45'b100010110101001010000001000100010001010001000;
        3'd3: ch_intro6_row = 45'b111010101101111010000001000111001010011101000;
        3'd4: ch_intro6_row = 45'b100010100101001010000001000100001010010001000;
        3'd5: ch_intro6_row = 45'b100010100101001010000001000100000100010001000;
        3'd6: ch_intro6_row = 45'b100010100101001011100001110111000100011101110;
        default: ch_intro6_row = 45'd0;
    endcase
endfunction
function ch_intro6_lit(input [9:0] dx, input [9:0] dy);
    reg [44:0] r;
    begin
        r = ch_intro6_row(dy[2:0]);
        ch_intro6_lit = (dx < 45 && dy < 8) ? r[44 - dx] : 1'b0;
    end
endfunction

localparam CH_CLEAR0_W = 53;
localparam CH_CLEAR0_H = 8;
function [52:0] ch_clear0_row(input [2:0] row);
    case (row)
        3'd0: ch_clear0_row = 53'b10001110100010111010000000100000110100011100110011100;
        3'd1: ch_clear0_row = 53'b10001000100010100010000001100001000100010001001010010;
        3'd2: ch_clear0_row = 53'b10001000100010100010000000100001000100010001001010010;
        3'd3: ch_clear0_row = 53'b10001110010100111010000000100001000100011101111011100;
        3'd4: ch_clear0_row = 53'b10001000010100100010000000100001000100010001001010010;
        3'd5: ch_clear0_row = 53'b10001000001000100010000000100001000100010001001010010;
        3'd6: ch_clear0_row = 53'b11101110001000111011100000100000110111011101001010010;
        default: ch_clear0_row = 53'd0;
    endcase
endfunction
function ch_clear0_lit(input [9:0] dx, input [9:0] dy);
    reg [52:0] r;
    begin
        r = ch_clear0_row(dy[2:0]);
        ch_clear0_lit = (dx < 53 && dy < 8) ? r[52 - dx] : 1'b0;
    end
endfunction

localparam CH_CLEAR1_W = 54;
localparam CH_CLEAR1_H = 8;
function [53:0] ch_clear1_row(input [2:0] row);
    case (row)
        3'd0: ch_clear1_row = 54'b100011101000101110100000011000000110100011100110011100;
        3'd1: ch_clear1_row = 54'b100010001000101000100000000100001000100010001001010010;
        3'd2: ch_clear1_row = 54'b100010001000101000100000000100001000100010001001010010;
        3'd3: ch_clear1_row = 54'b100011100101001110100000001000001000100011101111011100;
        3'd4: ch_clear1_row = 54'b100010000101001000100000010000001000100010001001010010;
        3'd5: ch_clear1_row = 54'b100010000010001000100000010000001000100010001001010010;
        3'd6: ch_clear1_row = 54'b111011100010001110111000011100000110111011101001010010;
        default: ch_clear1_row = 54'd0;
    endcase
endfunction
function ch_clear1_lit(input [9:0] dx, input [9:0] dy);
    reg [53:0] r;
    begin
        r = ch_clear1_row(dy[2:0]);
        ch_clear1_lit = (dx < 54 && dy < 8) ? r[53 - dx] : 1'b0;
    end
endfunction

localparam CH_CLEAR2_W = 54;
localparam CH_CLEAR2_H = 8;
function [53:0] ch_clear2_row(input [2:0] row);
    case (row)
        3'd0: ch_clear2_row = 54'b100011101000101110100000011000000110100011100110011100;
        3'd1: ch_clear2_row = 54'b100010001000101000100000000100001000100010001001010010;
        3'd2: ch_clear2_row = 54'b100010001000101000100000000100001000100010001001010010;
        3'd3: ch_clear2_row = 54'b100011100101001110100000011000001000100011101111011100;
        3'd4: ch_clear2_row = 54'b100010000101001000100000000100001000100010001001010010;
        3'd5: ch_clear2_row = 54'b100010000010001000100000000100001000100010001001010010;
        3'd6: ch_clear2_row = 54'b111011100010001110111000011000000110111011101001010010;
        default: ch_clear2_row = 54'd0;
    endcase
endfunction
function ch_clear2_lit(input [9:0] dx, input [9:0] dy);
    reg [53:0] r;
    begin
        r = ch_clear2_row(dy[2:0]);
        ch_clear2_lit = (dx < 54 && dy < 8) ? r[53 - dx] : 1'b0;
    end
endfunction

localparam CH_CLEAR3_W = 55;
localparam CH_CLEAR3_H = 8;
function [54:0] ch_clear3_row(input [2:0] row);
    case (row)
        3'd0: ch_clear3_row = 55'b1000111010001011101000000100000000110100011100110011100;
        3'd1: ch_clear3_row = 55'b1000100010001010001000000100000001000100010001001010010;
        3'd2: ch_clear3_row = 55'b1000100010001010001000000101000001000100010001001010010;
        3'd3: ch_clear3_row = 55'b1000111001010011101000000101000001000100011101111011100;
        3'd4: ch_clear3_row = 55'b1000100001010010001000000111100001000100010001001010010;
        3'd5: ch_clear3_row = 55'b1000100000100010001000000001000001000100010001001010010;
        3'd6: ch_clear3_row = 55'b1110111000100011101110000001000000110111011101001010010;
        default: ch_clear3_row = 55'd0;
    endcase
endfunction
function ch_clear3_lit(input [9:0] dx, input [9:0] dy);
    reg [54:0] r;
    begin
        r = ch_clear3_row(dy[2:0]);
        ch_clear3_lit = (dx < 55 && dy < 8) ? r[54 - dx] : 1'b0;
    end
endfunction

localparam CH_CLEAR4_W = 54;
localparam CH_CLEAR4_H = 8;
function [53:0] ch_clear4_row(input [2:0] row);
    case (row)
        3'd0: ch_clear4_row = 54'b100011101000101110100000011100000110100011100110011100;
        3'd1: ch_clear4_row = 54'b100010001000101000100000010000001000100010001001010010;
        3'd2: ch_clear4_row = 54'b100010001000101000100000010000001000100010001001010010;
        3'd3: ch_clear4_row = 54'b100011100101001110100000011000001000100011101111011100;
        3'd4: ch_clear4_row = 54'b100010000101001000100000000100001000100010001001010010;
        3'd5: ch_clear4_row = 54'b100010000010001000100000000100001000100010001001010010;
        3'd6: ch_clear4_row = 54'b111011100010001110111000011000000110111011101001010010;
        default: ch_clear4_row = 54'd0;
    endcase
endfunction
function ch_clear4_lit(input [9:0] dx, input [9:0] dy);
    reg [53:0] r;
    begin
        r = ch_clear4_row(dy[2:0]);
        ch_clear4_lit = (dx < 54 && dy < 8) ? r[53 - dx] : 1'b0;
    end
endfunction

localparam CH_CLEAR5_W = 55;
localparam CH_CLEAR5_H = 8;
function [54:0] ch_clear5_row(input [2:0] row);
    case (row)
        3'd0: ch_clear5_row = 55'b1000111010001011101000000011000000110100011100110011100;
        3'd1: ch_clear5_row = 55'b1000100010001010001000000100000001000100010001001010010;
        3'd2: ch_clear5_row = 55'b1000100010001010001000000100000001000100010001001010010;
        3'd3: ch_clear5_row = 55'b1000111001010011101000000111000001000100011101111011100;
        3'd4: ch_clear5_row = 55'b1000100001010010001000000100100001000100010001001010010;
        3'd5: ch_clear5_row = 55'b1000100000100010001000000100100001000100010001001010010;
        3'd6: ch_clear5_row = 55'b1110111000100011101110000011000000110111011101001010010;
        default: ch_clear5_row = 55'd0;
    endcase
endfunction
function ch_clear5_lit(input [9:0] dx, input [9:0] dy);
    reg [54:0] r;
    begin
        r = ch_clear5_row(dy[2:0]);
        ch_clear5_lit = (dx < 55 && dy < 8) ? r[54 - dx] : 1'b0;
    end
endfunction

localparam CH_CLEAR6_W = 39;
localparam CH_CLEAR6_H = 8;
function [38:0] ch_clear6_row(input [2:0] row);
    case (row)
        3'd0: ch_clear6_row = 39'b011010010011001000101110010011001001010;
        3'd1: ch_clear6_row = 39'b100010010100101000101001010100101001010;
        3'd2: ch_clear6_row = 39'b100010010100101101101001010100101101010;
        3'd3: ch_clear6_row = 39'b100011110111101010101110010100101011010;
        3'd4: ch_clear6_row = 39'b100010010100101000101000010100101001010;
        3'd5: ch_clear6_row = 39'b100010010100101000101000010100101001000;
        3'd6: ch_clear6_row = 39'b011010010100101000101000010011001001010;
        default: ch_clear6_row = 39'd0;
    endcase
endfunction
function ch_clear6_lit(input [9:0] dx, input [9:0] dy);
    reg [38:0] r;
    begin
        r = ch_clear6_row(dy[2:0]);
        ch_clear6_lit = (dx < 39 && dy < 8) ? r[38 - dx] : 1'b0;
    end
endfunction

localparam CH_FIRST_W = 31;
localparam CH_FIRST_H = 8;
function [30:0] ch_first_row(input [2:0] row);
    case (row)
        3'd0: ch_first_row = 31'b1110101110001101110000111001100;
        3'd1: ch_first_row = 31'b1000101001010000100000010010010;
        3'd2: ch_first_row = 31'b1000101001010000100000010010010;
        3'd3: ch_first_row = 31'b1110101110001000100000010010010;
        3'd4: ch_first_row = 31'b1000101001000100100000010010010;
        3'd5: ch_first_row = 31'b1000101001000100100000010010010;
        3'd6: ch_first_row = 31'b1000101001011000100000010001100;
        default: ch_first_row = 31'd0;
    endcase
endfunction
function ch_first_lit(input [9:0] dx, input [9:0] dy);
    reg [30:0] r;
    begin
        r = ch_first_row(dy[2:0]);
        ch_first_lit = (dx < 31 && dy < 8) ? r[30 - dx] : 1'b0;
    end
endfunction

localparam CH_SCORE_W = 22;
localparam CH_SCORE_H = 8;
function [21:0] ch_score_row(input [2:0] row);
    case (row)
        3'd0: ch_score_row = 22'b0110011001100111001110;
        3'd1: ch_score_row = 22'b1000100010010100101000;
        3'd2: ch_score_row = 22'b1000100010010100101000;
        3'd3: ch_score_row = 22'b0100100010010111001110;
        3'd4: ch_score_row = 22'b0010100010010100101000;
        3'd5: ch_score_row = 22'b0010100010010100101000;
        3'd6: ch_score_row = 22'b1100011001100100101110;
        default: ch_score_row = 22'd0;
    endcase
endfunction
function ch_score_lit(input [9:0] dx, input [9:0] dy);
    reg [21:0] r;
    begin
        r = ch_score_row(dy[2:0]);
        ch_score_lit = (dx < 22 && dy < 8) ? r[21 - dx] : 1'b0;
    end
endfunction

localparam CH_HI_W = 7;
localparam CH_HI_H = 8;
function [6:0] ch_hi_row(input [2:0] row);
    case (row)
        3'd0: ch_hi_row = 7'b1001010;
        3'd1: ch_hi_row = 7'b1001010;
        3'd2: ch_hi_row = 7'b1001010;
        3'd3: ch_hi_row = 7'b1111010;
        3'd4: ch_hi_row = 7'b1001010;
        3'd5: ch_hi_row = 7'b1001010;
        3'd6: ch_hi_row = 7'b1001010;
        default: ch_hi_row = 7'd0;
    endcase
endfunction
function ch_hi_lit(input [9:0] dx, input [9:0] dy);
    reg [6:0] r;
    begin
        r = ch_hi_row(dy[2:0]);
        ch_hi_lit = (dx < 7 && dy < 8) ? r[6 - dx] : 1'b0;
    end
endfunction

localparam CH_WIN_W = 40;
localparam CH_WIN_H = 8;
function [39:0] ch_win_row(input [2:0] row);
    case (row)
        3'd0: ch_win_row = 40'b1000101010010000111000110010010100100110;
        3'd1: ch_win_row = 40'b1000101010010000100101001010010100101000;
        3'd2: ch_win_row = 40'b1000101011010000100101001011010100101000;
        3'd3: ch_win_row = 40'b1010101010110000111001001010110100100100;
        3'd4: ch_win_row = 40'b1101101010010000100101001010010100100010;
        3'd5: ch_win_row = 40'b1000101010010000100101001010010100100010;
        3'd6: ch_win_row = 40'b1000101010010000111000110010010011001100;
        default: ch_win_row = 40'd0;
    endcase
endfunction
function ch_win_lit(input [9:0] dx, input [9:0] dy);
    reg [39:0] r;
    begin
        r = ch_win_row(dy[2:0]);
        ch_win_lit = (dx < 40 && dy < 8) ? r[39 - dx] : 1'b0;
    end
endfunction

localparam CH_PERFECT_W = 30;
localparam CH_PERFECT_H = 8;
function [29:0] ch_perfect_row(input [2:0] row);
    case (row)
        3'd0: ch_perfect_row = 30'b111001110111001110111001101110;
        3'd1: ch_perfect_row = 30'b100101000100101000100010000100;
        3'd2: ch_perfect_row = 30'b100101000100101000100010000100;
        3'd3: ch_perfect_row = 30'b111001110111001110111010000100;
        3'd4: ch_perfect_row = 30'b100001000100101000100010000100;
        3'd5: ch_perfect_row = 30'b100001000100101000100010000100;
        3'd6: ch_perfect_row = 30'b100001110100101000111001100100;
        default: ch_perfect_row = 30'd0;
    endcase
endfunction
function ch_perfect_lit(input [9:0] dx, input [9:0] dy);
    reg [29:0] r;
    begin
        r = ch_perfect_row(dy[2:0]);
        ch_perfect_lit = (dx < 30 && dy < 8) ? r[29 - dx] : 1'b0;
    end
endfunction

localparam CH_BEAT_W = 96;
localparam CH_BEAT_H = 8;
function [95:0] ch_beat_row(input [2:0] row);
    case (row)
        3'd0: ch_beat_row = 96'b100010011001001000011100111001100111000011101000101110111001000100001110001100111001110010001110;
        3'd1: ch_beat_row = 96'b100010100101001000010010100010010010000010001000101000100101000100001001010010100101001010001000;
        3'd2: ch_beat_row = 96'b010100100101001000010010100010010010000010001000101000100100101000001001010010100101001010001000;
        3'd3: ch_beat_row = 96'b001000100101001000011100111011110010000011100101001110111000010000001110011110100101001010001110;
        3'd4: ch_beat_row = 96'b001000100101001000010010100010010010000010000101001000100100010000001000010010100101001010001000;
        3'd5: ch_beat_row = 96'b001000100101001000010010100010010010000010000010001000100100010000001000010010100101001010001000;
        3'd6: ch_beat_row = 96'b001000011000110000011100111010010010000011100010001110100100010000001000010010111001110011101110;
        default: ch_beat_row = 96'd0;
    endcase
endfunction
function ch_beat_lit(input [9:0] dx, input [9:0] dy);
    reg [95:0] r;
    begin
        r = ch_beat_row(dy[2:0]);
        ch_beat_lit = (dx < 96 && dy < 8) ? r[95 - dx] : 1'b0;
    end
endfunction

localparam CH_PRESS_W = 47;
localparam CH_PRESS_H = 8;
function [46:0] ch_press_row(input [2:0] row);
    case (row)
        3'd0: ch_press_row = 47'b11100111001110011001100000110111001100111001110;
        3'd1: ch_press_row = 47'b10010100101000100010000001000010010010100100100;
        3'd2: ch_press_row = 47'b10010100101000100010000001000010010010100100100;
        3'd3: ch_press_row = 47'b11100111001110010001000000100010011110111000100;
        3'd4: ch_press_row = 47'b10000100101000001000100000010010010010100100100;
        3'd5: ch_press_row = 47'b10000100101000001000100000010010010010100100100;
        3'd6: ch_press_row = 47'b10000100101110110011000001100010010010100100100;
        default: ch_press_row = 47'd0;
    endcase
endfunction
function ch_press_lit(input [9:0] dx, input [9:0] dy);
    reg [46:0] r;
    begin
        r = ch_press_row(dy[2:0]);
        ch_press_lit = (dx < 47 && dy < 8) ? r[46 - dx] : 1'b0;
    end
endfunction

localparam CH_COIN_W = 43;
localparam CH_COIN_H = 8;
function [42:0] ch_coin_row(input [2:0] row);
    case (row)
        3'd0: ch_coin_row = 43'b1010010011011101110011100000110011001010010;
        3'd1: ch_coin_row = 43'b1010010100010001001001000001000100101010010;
        3'd2: ch_coin_row = 43'b1011010100010001001001000001000100101011010;
        3'd3: ch_coin_row = 43'b1010110010011101110001000001000100101010110;
        3'd4: ch_coin_row = 43'b1010010001010001001001000001000100101010010;
        3'd5: ch_coin_row = 43'b1010010001010001001001000001000100101010010;
        3'd6: ch_coin_row = 43'b1010010110011101001001000000110011001010010;
        default: ch_coin_row = 43'd0;
    endcase
endfunction
function ch_coin_lit(input [9:0] dx, input [9:0] dy);
    reg [42:0] r;
    begin
        r = ch_coin_row(dy[2:0]);
        ch_coin_lit = (dx < 43 && dy < 8) ? r[42 - dx] : 1'b0;
    end
endfunction

localparam CH_CONT_W = 38;
localparam CH_CONT_H = 8;
function [37:0] ch_cont_row(input [2:0] row);
    case (row)
        3'd0: ch_cont_row = 38'b01100110010010111010100101001011101100;
        3'd1: ch_cont_row = 38'b10001001010010010010100101001010000010;
        3'd2: ch_cont_row = 38'b10001001011010010010110101001010000010;
        3'd3: ch_cont_row = 38'b10001001010110010010101101001011100100;
        3'd4: ch_cont_row = 38'b10001001010010010010100101001010000100;
        3'd5: ch_cont_row = 38'b10001001010010010010100101001010000000;
        3'd6: ch_cont_row = 38'b01100110010010010010100100110011100100;
        default: ch_cont_row = 38'd0;
    endcase
endfunction
function ch_cont_lit(input [9:0] dx, input [9:0] dy);
    reg [37:0] r;
    begin
        r = ch_cont_row(dy[2:0]);
        ch_cont_lit = (dx < 38 && dy < 8) ? r[37 - dx] : 1'b0;
    end
endfunction

localparam CH_RESET_W = 70;
localparam CH_RESET_H = 8;
function [69:0] ch_reset_row(input [2:0] row);
    case (row)
        3'd0: ch_reset_row = 70'b0110011001100111001110000111001110011011101110011000011100110000001100;
        3'd1: ch_reset_row = 70'b1000100010010100101000000100101000100010000100100000001001001000010010;
        3'd2: ch_reset_row = 70'b1000100010010100101000000100101000100010000100100000001001001000010010;
        3'd3: ch_reset_row = 70'b0100100010010111001110000111001110010011100100010000001001001000010010;
        3'd4: ch_reset_row = 70'b0010100010010100101000000100101000001010000100001000001001001000010010;
        3'd5: ch_reset_row = 70'b0010100010010100101000000100101000001010000100001000001001001000010010;
        3'd6: ch_reset_row = 70'b1100011001100100101110000100101110110011100100110000001000110000001100;
        default: ch_reset_row = 70'd0;
    endcase
endfunction
function ch_reset_lit(input [9:0] dx, input [9:0] dy);
    reg [69:0] r;
    begin
        r = ch_reset_row(dy[2:0]);
        ch_reset_lit = (dx < 70 && dy < 8) ? r[69 - dx] : 1'b0;
    end
endfunction

localparam CH_RECORD_W = 48;
localparam CH_RECORD_H = 8;
function [47:0] ch_record_row(input [2:0] row);
    case (row)
        3'd0: ch_record_row = 48'b100101110100010000111001110011001100111001110010;
        3'd1: ch_record_row = 48'b100101000100010000100101000100010010100101001010;
        3'd2: ch_record_row = 48'b110101000100010000100101000100010010100101001010;
        3'd3: ch_record_row = 48'b101101110101010000111001110100010010111001001010;
        3'd4: ch_record_row = 48'b100101000110110000100101000100010010100101001010;
        3'd5: ch_record_row = 48'b100101000100010000100101000100010010100101001000;
        3'd6: ch_record_row = 48'b100101110100010000100101110011001100100101110010;
        default: ch_record_row = 48'd0;
    endcase
endfunction
function ch_record_lit(input [9:0] dx, input [9:0] dy);
    reg [47:0] r;
    begin
        r = ch_record_row(dy[2:0]);
        ch_record_lit = (dx < 48 && dy < 8) ? r[47 - dx] : 1'b0;
    end
endfunction

localparam CH_ENTER_W = 77;
localparam CH_ENTER_H = 8;
function [76:0] ch_enter_row(input [2:0] row);
    case (row)
        3'd0: ch_enter_row = 77'b11101001011101110111000001000100110010010111000001010010101110100110010000110;
        3'd1: ch_enter_row = 77'b10001001001001000100100001000101001010010100100001010010100100101001010001000;
        3'd2: ch_enter_row = 77'b10001101001001000100100000101001001010010100100001011010100100101001010001000;
        3'd3: ch_enter_row = 77'b11101011001001110111000000010001001010010111000001010110100100101111010000100;
        3'd4: ch_enter_row = 77'b10001001001001000100100000010001001010010100100001010010100100101001010000010;
        3'd5: ch_enter_row = 77'b10001001001001000100100000010001001010010100100001010010100100101001010000010;
        3'd6: ch_enter_row = 77'b11101001001001110100100000010000110001100100100001010010100100101001011101100;
        default: ch_enter_row = 77'd0;
    endcase
endfunction
function ch_enter_lit(input [9:0] dx, input [9:0] dy);
    reg [76:0] r;
    begin
        r = ch_enter_row(dy[2:0]);
        ch_enter_lit = (dx < 77 && dy < 8) ? r[76 - dx] : 1'b0;
    end
endfunction

localparam CH_HINT_W = 132;
localparam CH_HINT_H = 8;
function [131:0] ch_hint_row(input [2:0] row);
    case (row)
        3'd0: ch_hint_row = 132'b100101110000011100011001000101001000011100110000001101001001100011000110111000000011000001110011000000110011001001011101011100100010;
        3'd1: ch_hint_row = 132'b100101001000010010100101000101001000001001001000010001001010010100101000100000000100100000100100100001000100101001010001010010100010;
        3'd2: ch_hint_row = 132'b100101001000010010100101000101101000001001001000010001001010010100101000100000000100100000100100100001000100101101010001010010110110;
        3'd3: ch_hint_row = 132'b100101110000010010100101010101011000001001001000010001111010010100100100111000000111100000100100100001000100101011011101011100101010;
        3'd4: ch_hint_row = 132'b100101000000010010100101101101001000001001001000010001001010010100100010100000000100100000100100100001000100101001010001010010100010;
        3'd5: ch_hint_row = 132'b100101000000010010100101000101001000001001001000010001001010010100100010100000000100100000100100100001000100101001010001010010100010;
        3'd6: ch_hint_row = 132'b011001000000011100011001000101001000001000110000001101001001100011001100111010000100100000100011000000110011001001010001010010100010;
        3'd7: ch_hint_row = 132'b000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000;
        default: ch_hint_row = 132'd0;
    endcase
endfunction
function ch_hint_lit(input [9:0] dx, input [9:0] dy);
    reg [131:0] r;
    begin
        r = ch_hint_row(dy[2:0]);
        ch_hint_lit = (dx < 132 && dy < 8) ? r[131 - dx] : 1'b0;
    end
endfunction

localparam CH_TABLE_W = 89;
localparam CH_TABLE_H = 8;
function [88:0] ch_table_row(input [2:0] row);
    case (row)
        3'd0: ch_table_row = 89'b01101001001100100010001110100100110011100001001010011001001000001100110011001110011100110;
        3'd1: ch_table_row = 89'b10001001010010100010001000100101000010000001001010100001001000010001000100101001010001000;
        3'd2: ch_table_row = 89'b10001001010010100010001000110101000010000001001010100001001000010001000100101001010001000;
        3'd3: ch_table_row = 89'b10001111011110100010001110101101011011100001111010101101111000001001000100101110011100100;
        3'd4: ch_table_row = 89'b10001001010010100010001000100101001010000001001010100101001000000101000100101001010000010;
        3'd5: ch_table_row = 89'b10001001010010100010001000100101001010000001001010100101001000000101000100101001010000010;
        3'd6: ch_table_row = 89'b01101001010010111011101110100100110011100001001010011001001000011000110011001001011101100;
        default: ch_table_row = 89'd0;
    endcase
endfunction
function ch_table_lit(input [9:0] dx, input [9:0] dy);
    reg [88:0] r;
    begin
        r = ch_table_row(dy[2:0]);
        ch_table_lit = (dx < 89 && dy < 8) ? r[88 - dx] : 1'b0;
    end
endfunction

localparam CH_HERE_W = 44;
localparam CH_HERE_H = 8;
function [43:0] ch_here_row(input [2:0] row);
    case (row)
        3'd0: ch_here_row = 44'b10010111011100111000001100110010001011100110;
        3'd1: ch_here_row = 44'b10010100010010100000010001001010001010001000;
        3'd2: ch_here_row = 44'b10010100010010100000010001001011011010001000;
        3'd3: ch_here_row = 44'b11110111011100111000010001001010101011100100;
        3'd4: ch_here_row = 44'b10010100010010100000010001001010001010000010;
        3'd5: ch_here_row = 44'b10010100010010100000010001001010001010000010;
        3'd6: ch_here_row = 44'b10010111010010111000001100110010001011101100;
        default: ch_here_row = 44'd0;
    endcase
endfunction
function ch_here_lit(input [9:0] dx, input [9:0] dy);
    reg [43:0] r;
    begin
        r = ch_here_row(dy[2:0]);
        ch_here_lit = (dx < 44 && dy < 8) ? r[43 - dx] : 1'b0;
    end
endfunction

localparam CH_NEWCH_W = 73;
localparam CH_NEWCH_H = 8;
function [72:0] ch_newch_row(input [2:0] row);
    case (row)
        3'd0: ch_newch_row = 73'b0110000010010111010001000001101001001100100010001110100100110011101110010;
        3'd1: ch_newch_row = 73'b1001000010010100010001000010001001010010100010001000100101000010001001010;
        3'd2: ch_newch_row = 73'b1001000011010100010001000010001001010010100010001000110101000010001001010;
        3'd3: ch_newch_row = 73'b1111000010110111010101000010001111011110100010001110101101011011101110010;
        3'd4: ch_newch_row = 73'b1001000010010100011011000010001001010010100010001000100101001010001001010;
        3'd5: ch_newch_row = 73'b1001000010010100010001000010001001010010100010001000100101001010001001000;
        3'd6: ch_newch_row = 73'b1001000010010111010001000001101001010010111011101110100100110011101001010;
        default: ch_newch_row = 73'd0;
    endcase
endfunction
function ch_newch_lit(input [9:0] dx, input [9:0] dy);
    reg [72:0] r;
    begin
        r = ch_newch_row(dy[2:0]);
        ch_newch_lit = (dx < 73 && dy < 8) ? r[72 - dx] : 1'b0;
    end
endfunction

function [8:0] ch_intro_w(input [2:0] lvl);
    case (lvl)
        3'd0: ch_intro_w = 47;
        3'd1: ch_intro_w = 48;
        3'd2: ch_intro_w = 48;
        3'd3: ch_intro_w = 49;
        3'd4: ch_intro_w = 48;
        3'd5: ch_intro_w = 49;
        3'd6: ch_intro_w = 45;
        default: ch_intro_w = 0;
    endcase
endfunction
function ch_intro_lit(input [2:0] lvl, input [9:0] dx, input [9:0] dy);
    case (lvl)
        3'd0: ch_intro_lit = ch_intro0_lit(dx, dy);
        3'd1: ch_intro_lit = ch_intro1_lit(dx, dy);
        3'd2: ch_intro_lit = ch_intro2_lit(dx, dy);
        3'd3: ch_intro_lit = ch_intro3_lit(dx, dy);
        3'd4: ch_intro_lit = ch_intro4_lit(dx, dy);
        3'd5: ch_intro_lit = ch_intro5_lit(dx, dy);
        3'd6: ch_intro_lit = ch_intro6_lit(dx, dy);
        default: ch_intro_lit = 1'b0;
    endcase
endfunction

function [8:0] ch_clear_w(input [2:0] lvl);
    case (lvl)
        3'd0: ch_clear_w = 53;
        3'd1: ch_clear_w = 54;
        3'd2: ch_clear_w = 54;
        3'd3: ch_clear_w = 55;
        3'd4: ch_clear_w = 54;
        3'd5: ch_clear_w = 55;
        3'd6: ch_clear_w = 39;
        default: ch_clear_w = 0;
    endcase
endfunction
function ch_clear_lit(input [2:0] lvl, input [9:0] dx, input [9:0] dy);
    case (lvl)
        3'd0: ch_clear_lit = ch_clear0_lit(dx, dy);
        3'd1: ch_clear_lit = ch_clear1_lit(dx, dy);
        3'd2: ch_clear_lit = ch_clear2_lit(dx, dy);
        3'd3: ch_clear_lit = ch_clear3_lit(dx, dy);
        3'd4: ch_clear_lit = ch_clear4_lit(dx, dy);
        3'd5: ch_clear_lit = ch_clear5_lit(dx, dy);
        3'd6: ch_clear_lit = ch_clear6_lit(dx, dy);
        default: ch_clear_lit = 1'b0;
    endcase
endfunction

localparam CH_CELL = 7;
localparam CH_GLYPH_H = 8;
function [6:0] glyph_row(input [5:0] code, input [3:0] row);
    case ({code, row})
        {6'd0, 4'd0}: glyph_row = 7'b0110000;
        {6'd0, 4'd1}: glyph_row = 7'b1001000;
        {6'd0, 4'd2}: glyph_row = 7'b1001000;
        {6'd0, 4'd3}: glyph_row = 7'b1001000;
        {6'd0, 4'd4}: glyph_row = 7'b1001000;
        {6'd0, 4'd5}: glyph_row = 7'b1001000;
        {6'd0, 4'd6}: glyph_row = 7'b0110000;
        {6'd1, 4'd0}: glyph_row = 7'b0010000;
        {6'd1, 4'd1}: glyph_row = 7'b0110000;
        {6'd1, 4'd2}: glyph_row = 7'b0010000;
        {6'd1, 4'd3}: glyph_row = 7'b0010000;
        {6'd1, 4'd4}: glyph_row = 7'b0010000;
        {6'd1, 4'd5}: glyph_row = 7'b0010000;
        {6'd1, 4'd6}: glyph_row = 7'b0010000;
        {6'd2, 4'd0}: glyph_row = 7'b0110000;
        {6'd2, 4'd1}: glyph_row = 7'b0001000;
        {6'd2, 4'd2}: glyph_row = 7'b0001000;
        {6'd2, 4'd3}: glyph_row = 7'b0010000;
        {6'd2, 4'd4}: glyph_row = 7'b0100000;
        {6'd2, 4'd5}: glyph_row = 7'b0100000;
        {6'd2, 4'd6}: glyph_row = 7'b0111000;
        {6'd3, 4'd0}: glyph_row = 7'b0110000;
        {6'd3, 4'd1}: glyph_row = 7'b0001000;
        {6'd3, 4'd2}: glyph_row = 7'b0001000;
        {6'd3, 4'd3}: glyph_row = 7'b0110000;
        {6'd3, 4'd4}: glyph_row = 7'b0001000;
        {6'd3, 4'd5}: glyph_row = 7'b0001000;
        {6'd3, 4'd6}: glyph_row = 7'b0110000;
        {6'd4, 4'd0}: glyph_row = 7'b1000000;
        {6'd4, 4'd1}: glyph_row = 7'b1000000;
        {6'd4, 4'd2}: glyph_row = 7'b1010000;
        {6'd4, 4'd3}: glyph_row = 7'b1010000;
        {6'd4, 4'd4}: glyph_row = 7'b1111000;
        {6'd4, 4'd5}: glyph_row = 7'b0010000;
        {6'd4, 4'd6}: glyph_row = 7'b0010000;
        {6'd5, 4'd0}: glyph_row = 7'b0111000;
        {6'd5, 4'd1}: glyph_row = 7'b0100000;
        {6'd5, 4'd2}: glyph_row = 7'b0100000;
        {6'd5, 4'd3}: glyph_row = 7'b0110000;
        {6'd5, 4'd4}: glyph_row = 7'b0001000;
        {6'd5, 4'd5}: glyph_row = 7'b0001000;
        {6'd5, 4'd6}: glyph_row = 7'b0110000;
        {6'd6, 4'd0}: glyph_row = 7'b0110000;
        {6'd6, 4'd1}: glyph_row = 7'b1000000;
        {6'd6, 4'd2}: glyph_row = 7'b1000000;
        {6'd6, 4'd3}: glyph_row = 7'b1110000;
        {6'd6, 4'd4}: glyph_row = 7'b1001000;
        {6'd6, 4'd5}: glyph_row = 7'b1001000;
        {6'd6, 4'd6}: glyph_row = 7'b0110000;
        {6'd7, 4'd0}: glyph_row = 7'b0111000;
        {6'd7, 4'd1}: glyph_row = 7'b0001000;
        {6'd7, 4'd2}: glyph_row = 7'b0001000;
        {6'd7, 4'd3}: glyph_row = 7'b0010000;
        {6'd7, 4'd4}: glyph_row = 7'b0010000;
        {6'd7, 4'd5}: glyph_row = 7'b0100000;
        {6'd7, 4'd6}: glyph_row = 7'b0100000;
        {6'd8, 4'd0}: glyph_row = 7'b0110000;
        {6'd8, 4'd1}: glyph_row = 7'b1001000;
        {6'd8, 4'd2}: glyph_row = 7'b1001000;
        {6'd8, 4'd3}: glyph_row = 7'b0110000;
        {6'd8, 4'd4}: glyph_row = 7'b1001000;
        {6'd8, 4'd5}: glyph_row = 7'b1001000;
        {6'd8, 4'd6}: glyph_row = 7'b0110000;
        {6'd9, 4'd0}: glyph_row = 7'b0110000;
        {6'd9, 4'd1}: glyph_row = 7'b1001000;
        {6'd9, 4'd2}: glyph_row = 7'b1001000;
        {6'd9, 4'd3}: glyph_row = 7'b0111000;
        {6'd9, 4'd4}: glyph_row = 7'b0001000;
        {6'd9, 4'd5}: glyph_row = 7'b0001000;
        {6'd9, 4'd6}: glyph_row = 7'b0110000;
        {6'd10, 4'd0}: glyph_row = 7'b0110000;
        {6'd10, 4'd1}: glyph_row = 7'b1001000;
        {6'd10, 4'd2}: glyph_row = 7'b1001000;
        {6'd10, 4'd3}: glyph_row = 7'b1111000;
        {6'd10, 4'd4}: glyph_row = 7'b1001000;
        {6'd10, 4'd5}: glyph_row = 7'b1001000;
        {6'd10, 4'd6}: glyph_row = 7'b1001000;
        {6'd11, 4'd0}: glyph_row = 7'b1110000;
        {6'd11, 4'd1}: glyph_row = 7'b1001000;
        {6'd11, 4'd2}: glyph_row = 7'b1001000;
        {6'd11, 4'd3}: glyph_row = 7'b1110000;
        {6'd11, 4'd4}: glyph_row = 7'b1001000;
        {6'd11, 4'd5}: glyph_row = 7'b1001000;
        {6'd11, 4'd6}: glyph_row = 7'b1110000;
        {6'd12, 4'd0}: glyph_row = 7'b0011000;
        {6'd12, 4'd1}: glyph_row = 7'b0100000;
        {6'd12, 4'd2}: glyph_row = 7'b0100000;
        {6'd12, 4'd3}: glyph_row = 7'b0100000;
        {6'd12, 4'd4}: glyph_row = 7'b0100000;
        {6'd12, 4'd5}: glyph_row = 7'b0100000;
        {6'd12, 4'd6}: glyph_row = 7'b0011000;
        {6'd13, 4'd0}: glyph_row = 7'b1110000;
        {6'd13, 4'd1}: glyph_row = 7'b1001000;
        {6'd13, 4'd2}: glyph_row = 7'b1001000;
        {6'd13, 4'd3}: glyph_row = 7'b1001000;
        {6'd13, 4'd4}: glyph_row = 7'b1001000;
        {6'd13, 4'd5}: glyph_row = 7'b1001000;
        {6'd13, 4'd6}: glyph_row = 7'b1110000;
        {6'd14, 4'd0}: glyph_row = 7'b0111000;
        {6'd14, 4'd1}: glyph_row = 7'b0100000;
        {6'd14, 4'd2}: glyph_row = 7'b0100000;
        {6'd14, 4'd3}: glyph_row = 7'b0111000;
        {6'd14, 4'd4}: glyph_row = 7'b0100000;
        {6'd14, 4'd5}: glyph_row = 7'b0100000;
        {6'd14, 4'd6}: glyph_row = 7'b0111000;
        {6'd15, 4'd0}: glyph_row = 7'b0111000;
        {6'd15, 4'd1}: glyph_row = 7'b0100000;
        {6'd15, 4'd2}: glyph_row = 7'b0100000;
        {6'd15, 4'd3}: glyph_row = 7'b0111000;
        {6'd15, 4'd4}: glyph_row = 7'b0100000;
        {6'd15, 4'd5}: glyph_row = 7'b0100000;
        {6'd15, 4'd6}: glyph_row = 7'b0100000;
        {6'd16, 4'd0}: glyph_row = 7'b0110000;
        {6'd16, 4'd1}: glyph_row = 7'b1000000;
        {6'd16, 4'd2}: glyph_row = 7'b1000000;
        {6'd16, 4'd3}: glyph_row = 7'b1011000;
        {6'd16, 4'd4}: glyph_row = 7'b1001000;
        {6'd16, 4'd5}: glyph_row = 7'b1001000;
        {6'd16, 4'd6}: glyph_row = 7'b0110000;
        {6'd17, 4'd0}: glyph_row = 7'b1001000;
        {6'd17, 4'd1}: glyph_row = 7'b1001000;
        {6'd17, 4'd2}: glyph_row = 7'b1001000;
        {6'd17, 4'd3}: glyph_row = 7'b1111000;
        {6'd17, 4'd4}: glyph_row = 7'b1001000;
        {6'd17, 4'd5}: glyph_row = 7'b1001000;
        {6'd17, 4'd6}: glyph_row = 7'b1001000;
        {6'd18, 4'd0}: glyph_row = 7'b0010000;
        {6'd18, 4'd1}: glyph_row = 7'b0010000;
        {6'd18, 4'd2}: glyph_row = 7'b0010000;
        {6'd18, 4'd3}: glyph_row = 7'b0010000;
        {6'd18, 4'd4}: glyph_row = 7'b0010000;
        {6'd18, 4'd5}: glyph_row = 7'b0010000;
        {6'd18, 4'd6}: glyph_row = 7'b0010000;
        {6'd19, 4'd0}: glyph_row = 7'b0110000;
        {6'd19, 4'd1}: glyph_row = 7'b0010000;
        {6'd19, 4'd2}: glyph_row = 7'b0010000;
        {6'd19, 4'd3}: glyph_row = 7'b0010000;
        {6'd19, 4'd4}: glyph_row = 7'b0010000;
        {6'd19, 4'd5}: glyph_row = 7'b0010000;
        {6'd19, 4'd6}: glyph_row = 7'b0100000;
        {6'd20, 4'd0}: glyph_row = 7'b1001000;
        {6'd20, 4'd1}: glyph_row = 7'b1001000;
        {6'd20, 4'd2}: glyph_row = 7'b1010000;
        {6'd20, 4'd3}: glyph_row = 7'b1100000;
        {6'd20, 4'd4}: glyph_row = 7'b1010000;
        {6'd20, 4'd5}: glyph_row = 7'b1001000;
        {6'd20, 4'd6}: glyph_row = 7'b1001000;
        {6'd21, 4'd0}: glyph_row = 7'b0100000;
        {6'd21, 4'd1}: glyph_row = 7'b0100000;
        {6'd21, 4'd2}: glyph_row = 7'b0100000;
        {6'd21, 4'd3}: glyph_row = 7'b0100000;
        {6'd21, 4'd4}: glyph_row = 7'b0100000;
        {6'd21, 4'd5}: glyph_row = 7'b0100000;
        {6'd21, 4'd6}: glyph_row = 7'b0111000;
        {6'd22, 4'd0}: glyph_row = 7'b1000100;
        {6'd22, 4'd1}: glyph_row = 7'b1000100;
        {6'd22, 4'd2}: glyph_row = 7'b1101100;
        {6'd22, 4'd3}: glyph_row = 7'b1010100;
        {6'd22, 4'd4}: glyph_row = 7'b1000100;
        {6'd22, 4'd5}: glyph_row = 7'b1000100;
        {6'd22, 4'd6}: glyph_row = 7'b1000100;
        {6'd23, 4'd0}: glyph_row = 7'b1001000;
        {6'd23, 4'd1}: glyph_row = 7'b1001000;
        {6'd23, 4'd2}: glyph_row = 7'b1101000;
        {6'd23, 4'd3}: glyph_row = 7'b1011000;
        {6'd23, 4'd4}: glyph_row = 7'b1001000;
        {6'd23, 4'd5}: glyph_row = 7'b1001000;
        {6'd23, 4'd6}: glyph_row = 7'b1001000;
        {6'd24, 4'd0}: glyph_row = 7'b0110000;
        {6'd24, 4'd1}: glyph_row = 7'b1001000;
        {6'd24, 4'd2}: glyph_row = 7'b1001000;
        {6'd24, 4'd3}: glyph_row = 7'b1001000;
        {6'd24, 4'd4}: glyph_row = 7'b1001000;
        {6'd24, 4'd5}: glyph_row = 7'b1001000;
        {6'd24, 4'd6}: glyph_row = 7'b0110000;
        {6'd25, 4'd0}: glyph_row = 7'b1110000;
        {6'd25, 4'd1}: glyph_row = 7'b1001000;
        {6'd25, 4'd2}: glyph_row = 7'b1001000;
        {6'd25, 4'd3}: glyph_row = 7'b1110000;
        {6'd25, 4'd4}: glyph_row = 7'b1000000;
        {6'd25, 4'd5}: glyph_row = 7'b1000000;
        {6'd25, 4'd6}: glyph_row = 7'b1000000;
        {6'd26, 4'd0}: glyph_row = 7'b0110000;
        {6'd26, 4'd1}: glyph_row = 7'b1001000;
        {6'd26, 4'd2}: glyph_row = 7'b1001000;
        {6'd26, 4'd3}: glyph_row = 7'b1001000;
        {6'd26, 4'd4}: glyph_row = 7'b1001000;
        {6'd26, 4'd5}: glyph_row = 7'b1010000;
        {6'd26, 4'd6}: glyph_row = 7'b0101000;
        {6'd27, 4'd0}: glyph_row = 7'b1110000;
        {6'd27, 4'd1}: glyph_row = 7'b1001000;
        {6'd27, 4'd2}: glyph_row = 7'b1001000;
        {6'd27, 4'd3}: glyph_row = 7'b1110000;
        {6'd27, 4'd4}: glyph_row = 7'b1001000;
        {6'd27, 4'd5}: glyph_row = 7'b1001000;
        {6'd27, 4'd6}: glyph_row = 7'b1001000;
        {6'd28, 4'd0}: glyph_row = 7'b0011000;
        {6'd28, 4'd1}: glyph_row = 7'b0100000;
        {6'd28, 4'd2}: glyph_row = 7'b0100000;
        {6'd28, 4'd3}: glyph_row = 7'b0010000;
        {6'd28, 4'd4}: glyph_row = 7'b0001000;
        {6'd28, 4'd5}: glyph_row = 7'b0001000;
        {6'd28, 4'd6}: glyph_row = 7'b0110000;
        {6'd29, 4'd0}: glyph_row = 7'b0111000;
        {6'd29, 4'd1}: glyph_row = 7'b0010000;
        {6'd29, 4'd2}: glyph_row = 7'b0010000;
        {6'd29, 4'd3}: glyph_row = 7'b0010000;
        {6'd29, 4'd4}: glyph_row = 7'b0010000;
        {6'd29, 4'd5}: glyph_row = 7'b0010000;
        {6'd29, 4'd6}: glyph_row = 7'b0010000;
        {6'd30, 4'd0}: glyph_row = 7'b1001000;
        {6'd30, 4'd1}: glyph_row = 7'b1001000;
        {6'd30, 4'd2}: glyph_row = 7'b1001000;
        {6'd30, 4'd3}: glyph_row = 7'b1001000;
        {6'd30, 4'd4}: glyph_row = 7'b1001000;
        {6'd30, 4'd5}: glyph_row = 7'b1001000;
        {6'd30, 4'd6}: glyph_row = 7'b0110000;
        {6'd31, 4'd0}: glyph_row = 7'b1000100;
        {6'd31, 4'd1}: glyph_row = 7'b1000100;
        {6'd31, 4'd2}: glyph_row = 7'b1000100;
        {6'd31, 4'd3}: glyph_row = 7'b0101000;
        {6'd31, 4'd4}: glyph_row = 7'b0101000;
        {6'd31, 4'd5}: glyph_row = 7'b0010000;
        {6'd31, 4'd6}: glyph_row = 7'b0010000;
        {6'd32, 4'd0}: glyph_row = 7'b1000100;
        {6'd32, 4'd1}: glyph_row = 7'b1000100;
        {6'd32, 4'd2}: glyph_row = 7'b1000100;
        {6'd32, 4'd3}: glyph_row = 7'b1010100;
        {6'd32, 4'd4}: glyph_row = 7'b1101100;
        {6'd32, 4'd5}: glyph_row = 7'b1000100;
        {6'd32, 4'd6}: glyph_row = 7'b1000100;
        {6'd33, 4'd0}: glyph_row = 7'b1000100;
        {6'd33, 4'd1}: glyph_row = 7'b1000100;
        {6'd33, 4'd2}: glyph_row = 7'b0101000;
        {6'd33, 4'd3}: glyph_row = 7'b0010000;
        {6'd33, 4'd4}: glyph_row = 7'b0101000;
        {6'd33, 4'd5}: glyph_row = 7'b1000100;
        {6'd33, 4'd6}: glyph_row = 7'b1000100;
        {6'd34, 4'd0}: glyph_row = 7'b1000100;
        {6'd34, 4'd1}: glyph_row = 7'b1000100;
        {6'd34, 4'd2}: glyph_row = 7'b0101000;
        {6'd34, 4'd3}: glyph_row = 7'b0010000;
        {6'd34, 4'd4}: glyph_row = 7'b0010000;
        {6'd34, 4'd5}: glyph_row = 7'b0010000;
        {6'd34, 4'd6}: glyph_row = 7'b0010000;
        {6'd35, 4'd0}: glyph_row = 7'b0111000;
        {6'd35, 4'd1}: glyph_row = 7'b0001000;
        {6'd35, 4'd2}: glyph_row = 7'b0010000;
        {6'd35, 4'd3}: glyph_row = 7'b0010000;
        {6'd35, 4'd4}: glyph_row = 7'b0010000;
        {6'd35, 4'd5}: glyph_row = 7'b0100000;
        {6'd35, 4'd6}: glyph_row = 7'b0111000;
        {6'd37, 4'd1}: glyph_row = 7'b0010000;
        {6'd37, 4'd2}: glyph_row = 7'b0010000;
        {6'd37, 4'd3}: glyph_row = 7'b1111100;
        {6'd37, 4'd4}: glyph_row = 7'b0010000;
        {6'd37, 4'd5}: glyph_row = 7'b0010000;
        {6'd38, 4'd6}: glyph_row = 7'b0010000;
        {6'd39, 4'd2}: glyph_row = 7'b1000100;
        {6'd39, 4'd3}: glyph_row = 7'b0101000;
        {6'd39, 4'd4}: glyph_row = 7'b0010000;
        {6'd39, 4'd5}: glyph_row = 7'b0101000;
        {6'd39, 4'd6}: glyph_row = 7'b1000100;
        {6'd40, 4'd0}: glyph_row = 7'b0010000;
        {6'd40, 4'd1}: glyph_row = 7'b0010000;
        {6'd40, 4'd2}: glyph_row = 7'b0010000;
        {6'd40, 4'd3}: glyph_row = 7'b0010000;
        {6'd40, 4'd4}: glyph_row = 7'b0010000;
        {6'd40, 4'd6}: glyph_row = 7'b0010000;
        default: glyph_row = 7'd0;
    endcase
endfunction
function glyph_lit(input [5:0] code, input [9:0] dx, input [9:0] dy);
    reg [6:0] r;
    begin
        r = glyph_row(code, dy[3:0]);
        glyph_lit = (dx < 7 && dy < 8) ? r[6 - dx] : 1'b0;
    end
endfunction
