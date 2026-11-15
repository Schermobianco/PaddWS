// Generato da tools/gen_mister_titles.py: non modificare a mano.
// Titoli disegnati (assets/titles): un pixel per voce, 4 bit = ruolo del colore (0 trasparente,
// 1 nero, 2 bianco, 3 giallo, 4 giallo scuro, 5 grigio, 6 grigio scuro, 7 rosso, 8 rosso scuro).
// Il pixel (u, v) di un titolo sta a base + (v << SH) + u.
localparam [3:0] TL_CLEAR = 4'd0, TL_BLACK = 4'd1, TL_WHITE = 4'd2, TL_YELLOW = 4'd3, TL_DARK_YELLOW = 4'd4,
                 TL_GRAY = 4'd5, TL_DARK_GRAY = 4'd6, TL_RED = 4'd7, TL_DARK_RED = 4'd8;
// title_challenge.hex (challenge_render)
localparam integer TL_CH_DEPTH = 20224, TL_CH_ABITS = 15;
localparam integer TL_NEWCH_BASE = 0, TL_NEWCH_W = 192, TL_NEWCH_H = 38, TL_NEWCH_SH = 8;
// nomi degli avversari (PaddleKind): indirizzo di partenza, larghezza, altezza, passo 128 (1) o 64 (0)
function [14:0] tl_name_base(input [2:0] kind);
    case (kind)
        3'd0: tl_name_base = 9728;
        3'd1: tl_name_base = 10688;
        3'd2: tl_name_base = 12416;
        3'd3: tl_name_base = 14464;
        3'd4: tl_name_base = 15744;
        3'd5: tl_name_base = 17536;
        3'd6: tl_name_base = 18432;
        default: tl_name_base = 0;
    endcase
endfunction
function [6:0] tl_name_w(input [2:0] kind);
    case (kind)
        3'd0: tl_name_w = 58;
        3'd1: tl_name_w = 44;
        3'd2: tl_name_w = 80;
        3'd3: tl_name_w = 46;
        3'd4: tl_name_w = 86;
        3'd5: tl_name_w = 50;
        3'd6: tl_name_w = 77;
        default: tl_name_w = 0;
    endcase
endfunction
function [4:0] tl_name_h(input [2:0] kind);
    case (kind)
        3'd0: tl_name_h = 15;
        3'd1: tl_name_h = 26;
        3'd2: tl_name_h = 16;
        3'd3: tl_name_h = 20;
        3'd4: tl_name_h = 14;
        3'd5: tl_name_h = 14;
        3'd6: tl_name_h = 14;
        default: tl_name_h = 0;
    endcase
endfunction
function tl_name_sh7(input [2:0] kind);
    case (kind)
        3'd0: tl_name_sh7 = 0;
        3'd1: tl_name_sh7 = 0;
        3'd2: tl_name_sh7 = 1;
        3'd3: tl_name_sh7 = 0;
        3'd4: tl_name_sh7 = 1;
        3'd5: tl_name_sh7 = 0;
        3'd6: tl_name_sh7 = 1;
        default: tl_name_sh7 = 0;
    endcase
endfunction
// lettere per le entrate animate: GUARDIAN (prima colonna delle lettere 1-7) e BLASTER, in corsivo
// (prima colonna delle lettere 1-6 senza l'inclinazione; la riga v è spostata di tl_blaster_slant(v));
// centro della lettera 0 a metà altezza e passo, per i colpi che le accendono
function [6:0] tl_letter_x(input [2:0] kind, input [2:0] j);
    case ({kind, j})
        {3'd6, 3'd1}: tl_letter_x = 10;
        {3'd6, 3'd2}: tl_letter_x = 20;
        {3'd6, 3'd3}: tl_letter_x = 30;
        {3'd6, 3'd4}: tl_letter_x = 40;
        {3'd6, 3'd5}: tl_letter_x = 51;
        {3'd6, 3'd6}: tl_letter_x = 60;
        {3'd6, 3'd7}: tl_letter_x = 70;
        {3'd4, 3'd1}: tl_letter_x = 31;
        {3'd4, 3'd2}: tl_letter_x = 40;
        {3'd4, 3'd3}: tl_letter_x = 49;
        {3'd4, 3'd4}: tl_letter_x = 58;
        {3'd4, 3'd5}: tl_letter_x = 67;
        {3'd4, 3'd6}: tl_letter_x = 76;
        default: tl_letter_x = 7'd127;
    endcase
endfunction
function [2:0] tl_blaster_slant(input [4:0] v);
    case (v)
        5'd0: tl_blaster_slant = 4;
        5'd1: tl_blaster_slant = 4;
        5'd2: tl_blaster_slant = 3;
        5'd3: tl_blaster_slant = 3;
        5'd4: tl_blaster_slant = 3;
        5'd5: tl_blaster_slant = 2;
        5'd6: tl_blaster_slant = 2;
        5'd7: tl_blaster_slant = 2;
        5'd8: tl_blaster_slant = 1;
        5'd9: tl_blaster_slant = 1;
        5'd10: tl_blaster_slant = 1;
        default: tl_blaster_slant = 0;
    endcase
endfunction
localparam integer TL_BLASTER_CX0 = 27, TL_BLASTER_STEP = 9;
// title_perfect.hex (pong_render)
localparam integer TL_PF_DEPTH = 3200, TL_PF_ABITS = 12;
localparam integer TL_PF_W = 114, TL_PF_H = 25, TL_PF_SH = 7;
