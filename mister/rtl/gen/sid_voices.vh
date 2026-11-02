// Generato da tools/gen_voices.py: non modificare a mano.
// Voci "da SID", campioni a 4 bit (8 = silenzio), due per byte, prima il nibble alto: 0-6 i nomi
// degli avversari della CHALLENGE (`PaddleKind`), 7-8 le urla delle mosse speciali (`Special`),
// 9 READY e 10 GO della CHALLENGE, 11 YOU WIN (vittoria contro la CPU e finale della CHALLENGE).
localparam VOICE_RATE = 5000;
localparam VOICE_ROM_SIZE = 17086;
localparam [3:0] VOICE_STRAIGHT = 4'd7;
localparam [3:0] VOICE_RISE = 4'd8;
localparam [3:0] VOICE_READY = 4'd9;
localparam [3:0] VOICE_GO = 4'd10;
localparam [3:0] VOICE_YOU_WIN = 4'd11;
function [14:0] voice_start(input [3:0] id);
    case (id)
        4'd0: voice_start = 15'd0;   // ARCADE
        4'd1: voice_start = 15'd1281;   // TITAN
        4'd2: voice_start = 15'd2422;   // HAMMER
        4'd3: voice_start = 15'd3522;   // TWIST
        4'd4: voice_start = 15'd4565;   // BLASTER
        4'd5: voice_start = 15'd5914;   // RUSH
        4'd6: voice_start = 15'd6862;   // GUARDIAN
        4'd7: voice_start = 15'd8092;   // STRAIGHT SHOT
        4'd8: voice_start = 15'd10166;   // RISING STRIKE
        4'd9: voice_start = 15'd12497;   // READY?
        4'd10: voice_start = 15'd13519;   // GO
        4'd11: voice_start = 15'd14538;   // YOU WIN
        default: voice_start = 15'd0;
    endcase
endfunction
function [11:0] voice_len(input [3:0] id);
    case (id)
        4'd0: voice_len = 12'd1281;   // 0.51 s
        4'd1: voice_len = 12'd1141;   // 0.46 s
        4'd2: voice_len = 12'd1100;   // 0.44 s
        4'd3: voice_len = 12'd1043;   // 0.42 s
        4'd4: voice_len = 12'd1349;   // 0.54 s
        4'd5: voice_len = 12'd948;   // 0.38 s
        4'd6: voice_len = 12'd1230;   // 0.49 s
        4'd7: voice_len = 12'd2074;   // 0.83 s
        4'd8: voice_len = 12'd2331;   // 0.93 s
        4'd9: voice_len = 12'd1022;   // 0.41 s
        4'd10: voice_len = 12'd1019;   // 0.41 s
        4'd11: voice_len = 12'd2548;   // 1.02 s
        default: voice_len = 12'd0;
    endcase
endfunction
