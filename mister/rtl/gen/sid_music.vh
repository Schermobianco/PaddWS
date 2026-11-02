// Generato da tools/gen_sid_music.py: non modificare a mano.
localparam SID_FREQ_BASE = 0;
localparam SID_INSTR_BASE = 192;
localparam SID_SONGS = 14;
localparam SID_EFFECTS = 7;
localparam SID_SONG_TITLE = 1;   // 15.4 s
localparam SID_SONG_INTRO = 2;   // 1.4 s
localparam SID_SONG_CLEAR = 3;   // 1.9 s
localparam SID_SONG_CONTINUE = 4;   // 3.8 s
localparam SID_SONG_GAME_OVER = 5;   // 3.6 s
localparam SID_SONG_CHAMPION = 6;   // 7.7 s
localparam SID_FX_WALL = 1;
localparam SID_FX_HIT = 2;
localparam SID_FX_BOOST = 3;
localparam SID_FX_SCORE = 4;
localparam SID_FX_COIN = 5;
localparam SID_SONG_THEME0 = 7;   // temi di CHALLENGE, nell'ordine di PaddleKind
localparam SID_SONG_THEME_ARCADE = 7;   // 15.4 s
localparam SID_SONG_THEME_TITAN = 8;   // 19.2 s
localparam SID_SONG_THEME_HAMMER = 9;   // 10.7 s
localparam SID_SONG_THEME_TWIST = 10;   // 15.4 s
localparam SID_SONG_THEME_BLASTER = 11;   // 11.5 s
localparam SID_SONG_THEME_RUSH = 12;   // 11.5 s
localparam SID_SONG_THEME_GUARDIAN = 13;   // 15.4 s
localparam SID_SONG_ENDING = 14;   // 61.4 s
localparam SID_FX_MOVE = 6;
localparam SID_FX_SPECIAL = 7;
localparam SID_ROM_SIZE = 4093;
localparam SID_ROM_BASE_SIZE = 846;   // senza i temi (C64)
function [11:0] sid_song_start(input [3:0] song, input [1:0] voice);
    case ({song, voice})
        {4'd1, 2'd0}: sid_song_start = 12'd320;
        {4'd1, 2'd1}: sid_song_start = 12'd450;
        {4'd1, 2'd2}: sid_song_start = 12'd529;
        {4'd2, 2'd0}: sid_song_start = 12'd555;
        {4'd2, 2'd1}: sid_song_start = 12'd563;
        {4'd2, 2'd2}: sid_song_start = 12'd573;
        {4'd3, 2'd0}: sid_song_start = 12'd578;
        {4'd3, 2'd1}: sid_song_start = 12'd586;
        {4'd3, 2'd2}: sid_song_start = 12'd600;
        {4'd4, 2'd0}: sid_song_start = 12'd605;
        {4'd4, 2'd1}: sid_song_start = 12'd639;
        {4'd4, 2'd2}: sid_song_start = 12'd657;
        {4'd5, 2'd0}: sid_song_start = 12'd675;
        {4'd5, 2'd1}: sid_song_start = 12'd683;
        {4'd5, 2'd2}: sid_song_start = 12'd701;
        {4'd6, 2'd0}: sid_song_start = 12'd704;
        {4'd6, 2'd1}: sid_song_start = 12'd770;
        {4'd6, 2'd2}: sid_song_start = 12'd806;
        {4'd7, 2'd0}: sid_song_start = 12'd846;
        {4'd7, 2'd1}: sid_song_start = 12'd976;
        {4'd7, 2'd2}: sid_song_start = 12'd1070;
        {4'd8, 2'd0}: sid_song_start = 12'd1071;
        {4'd8, 2'd1}: sid_song_start = 12'd1137;
        {4'd8, 2'd2}: sid_song_start = 12'd1199;
        {4'd9, 2'd0}: sid_song_start = 12'd1200;
        {4'd9, 2'd1}: sid_song_start = 12'd1320;
        {4'd9, 2'd2}: sid_song_start = 12'd1429;
        {4'd10, 2'd0}: sid_song_start = 12'd1430;
        {4'd10, 2'd1}: sid_song_start = 12'd1560;
        {4'd10, 2'd2}: sid_song_start = 12'd1676;
        {4'd11, 2'd0}: sid_song_start = 12'd1677;
        {4'd11, 2'd1}: sid_song_start = 12'd1870;
        {4'd11, 2'd2}: sid_song_start = 12'd1990;
        {4'd12, 2'd0}: sid_song_start = 12'd1991;
        {4'd12, 2'd1}: sid_song_start = 12'd2168;
        {4'd12, 2'd2}: sid_song_start = 12'd2272;
        {4'd13, 2'd0}: sid_song_start = 12'd2273;
        {4'd13, 2'd1}: sid_song_start = 12'd2403;
        {4'd13, 2'd2}: sid_song_start = 12'd2463;
        {4'd14, 2'd0}: sid_song_start = 12'd2464;
        {4'd14, 2'd1}: sid_song_start = 12'd2978;
        {4'd14, 2'd2}: sid_song_start = 12'd3403;
        default: sid_song_start = 12'd0;
    endcase
endfunction
function [11:0] sid_fx_start(input [2:0] fx);
    case (fx)
        3'd1: sid_fx_start = 12'd820;
        3'd2: sid_fx_start = 12'd824;
        3'd3: sid_fx_start = 12'd828;
        3'd4: sid_fx_start = 12'd834;
        3'd5: sid_fx_start = 12'd840;
        3'd6: sid_fx_start = 12'd4059;
        3'd7: sid_fx_start = 12'd4070;
        default: sid_fx_start = 12'd0;
    endcase
endfunction
