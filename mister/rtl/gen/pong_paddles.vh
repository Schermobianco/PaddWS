// Generato da tools/gen_mister_paddles.py: non modificare a mano.
// Colori e tabelle delle racchette dei personaggi (next_render.v).
localparam integer PD_HIT_FRAMES = 30, PD_FIRE_FRAMES = 26, PD_CRACK_FRAMES = 9, PD_BREAK_FRAMES = 39,
                   PD_BLINK_FRAMES = 15, PD_BARRIER_FRAMES = 42;

// colori dei personaggi (accent di portraits.json, come i segni del PC): pieno, scurito,
// schiarito, per tipo (PaddleKind); e il corpo in ombra dei colori del corpo
localparam [23:0] PD_MARK0 = 24'hFFD21E, PD_MARK_DARK0 = 24'h997E12, PD_MARK_LIGHT0 = 24'hFFE683;
localparam [23:0] PD_MARK1 = 24'hE67828, PD_MARK_DARK1 = 24'h8A4818, PD_MARK_LIGHT1 = 24'hF1B589;
localparam [23:0] PD_MARK2 = 24'hE62828, PD_MARK_DARK2 = 24'h8A1818, PD_MARK_LIGHT2 = 24'hF18989;
localparam [23:0] PD_MARK3 = 24'h9646C8, PD_MARK_DARK3 = 24'h5A2A78, PD_MARK_LIGHT3 = 24'hC599E1;
localparam [23:0] PD_MARK4 = 24'h46BE46, PD_MARK_DARK4 = 24'h2A722A, PD_MARK_LIGHT4 = 24'h99DB99;
localparam [23:0] PD_MARK5 = 24'h3CC8DC, PD_MARK_DARK5 = 24'h247884, PD_MARK_LIGHT5 = 24'h94E1EC;
localparam [23:0] PD_MARK6 = 24'h5A96FF, PD_MARK_DARK6 = 24'h365A99, PD_MARK_LIGHT6 = 24'hA4C5FF;
localparam [23:0] PD_WHITE_SH = 24'hD4D6E0;
localparam [23:0] PD_GRAY_SH = 24'h96979E;
localparam [23:0] PD_ACCENT_SH = 24'hD4B021;
localparam [23:0] PD_OMEGA_RED_SH = 24'hBF2223;
localparam [23:0] PD_OMEGA_PURPLE_SH = 24'h8536C5;
localparam [23:0] PD_SHADOW = 24'h30303A;
localparam [23:0] PD_GRAY = 24'hB4B4B4;
localparam [23:0] PD_GRAY_LIGHT = 24'hE2E2E6;
localparam [23:0] PD_DARK = 24'h5C5C62;
localparam [23:0] PD_DARK_DEEP = 24'h34343C;
localparam [23:0] PD_SHADOW_TITAN = 24'h1C1C26;
localparam [23:0] PD_RUSH_GHOST1 = 24'h0B2428;
localparam [23:0] PD_RUSH_GHOST2 = 24'h16484F;
localparam [23:0] PD_RUSH_GHOST3 = 24'h206C77;
localparam [23:0] PD_WALL = 24'h5A96FF, PD_WALL_LIGHT = 24'hBED6FF, PD_WALL1 = 24'h4878CC, PD_WALL2 = 24'h365A99;

// HAMMER: posa delle scintille (0-3, 8 al secondo) al frame `f` dal colpo potente
function [1:0] pd_spark_pose(input [4:0] f);
    pd_spark_pose = (f < 5'd8) ? 2'd0 : (f < 5'd15) ? 2'd1 : (f < 5'd23) ? 2'd2 : 2'd3;
endfunction
// pixel (du, dv) delle scintille alla posa `pose`, contati dalla faccia e dalla riga del colpo
function pd_spark(input [1:0] pose, input signed [11:0] du, input signed [11:0] dv);
    case (pose)
        2'd0: pd_spark = (du == 1 && dv == -4) ||
                   (du == 1 && dv == -2) ||
                   (du == 1 && dv == 2) ||
                   (du == 1 && dv == 4) ||
                   (du == 2 && dv == -2) ||
                   (du == 2 && dv == -1) ||
                   (du == 2 && dv == 1) ||
                   (du == 2 && dv == 2) ||
                   (du == 3 && dv == -3) ||
                   (du == 3 && dv == 3) ||
                   (du == 4 && dv == -1) ||
                   (du == 4 && dv == 1);
        2'd1: pd_spark = (du == 1 && dv == -4) ||
                   (du == 1 && dv == 4) ||
                   (du == 2 && dv == -5) ||
                   (du == 2 && dv == 5) ||
                   (du == 3 && dv == -3) ||
                   (du == 3 && dv == 3) ||
                   (du == 4 && dv == -4) ||
                   (du == 4 && dv == -1) ||
                   (du == 4 && dv == 1) ||
                   (du == 4 && dv == 4) ||
                   (du == 5 && dv == -1) ||
                   (du == 5 && dv == 1);
        2'd2: pd_spark = (du == 2 && dv == -7) ||
                   (du == 2 && dv == -5) ||
                   (du == 2 && dv == 5) ||
                   (du == 2 && dv == 7) ||
                   (du == 4 && dv == -4) ||
                   (du == 4 && dv == 4) ||
                   (du == 5 && dv == -5) ||
                   (du == 5 && dv == 5) ||
                   (du == 6 && dv == -1) ||
                   (du == 6 && dv == 1) ||
                   (du == 7 && dv == -2) ||
                   (du == 7 && dv == 2);
        2'd3: pd_spark = (du == 3 && dv == -8) ||
                   (du == 3 && dv == -7) ||
                   (du == 3 && dv == 7) ||
                   (du == 3 && dv == 8) ||
                   (du == 6 && dv == -5) ||
                   (du == 6 && dv == 5) ||
                   (du == 7 && dv == -6) ||
                   (du == 7 && dv == -2) ||
                   (du == 7 && dv == 2) ||
                   (du == 7 && dv == 6) ||
                   (du == 9 && dv == -2) ||
                   (du == 9 && dv == 2);
        default: pd_spark = 1'b0;
    endcase
endfunction

// TWIST: onda al frame `f` dal colpo (0-29): il pixel (du, dv) dal centro dell'estremita' e'
// sull'anello se pd_ring_lo <= 16 (du^2 + dv^2) < pd_ring_hi
function [12:0] pd_ring_lo(input [4:0] f);
    case (f)
        5'd0: pd_ring_lo = 13'd100;
        5'd1: pd_ring_lo = 13'd120;
        5'd2: pd_ring_lo = 13'd141;
        5'd3: pd_ring_lo = 13'd164;
        5'd4: pd_ring_lo = 13'd189;
        5'd5: pd_ring_lo = 13'd215;
        5'd6: pd_ring_lo = 13'd243;
        5'd7: pd_ring_lo = 13'd273;
        5'd8: pd_ring_lo = 13'd305;
        5'd9: pd_ring_lo = 13'd339;
        5'd10: pd_ring_lo = 13'd374;
        5'd11: pd_ring_lo = 13'd411;
        5'd12: pd_ring_lo = 13'd449;
        5'd13: pd_ring_lo = 13'd490;
        5'd14: pd_ring_lo = 13'd532;
        5'd15: pd_ring_lo = 13'd576;
        5'd16: pd_ring_lo = 13'd622;
        5'd17: pd_ring_lo = 13'd669;
        5'd18: pd_ring_lo = 13'd718;
        5'd19: pd_ring_lo = 13'd769;
        5'd20: pd_ring_lo = 13'd822;
        5'd21: pd_ring_lo = 13'd876;
        5'd22: pd_ring_lo = 13'd932;
        5'd23: pd_ring_lo = 13'd990;
        5'd24: pd_ring_lo = 13'd1050;
        5'd25: pd_ring_lo = 13'd1111;
        5'd26: pd_ring_lo = 13'd1174;
        5'd27: pd_ring_lo = 13'd1239;
        5'd28: pd_ring_lo = 13'd1306;
        5'd29: pd_ring_lo = 13'd1374;
        default: pd_ring_lo = 13'd8191;
    endcase
endfunction
function [12:0] pd_ring_hi(input [4:0] f);
    case (f)
        5'd0: pd_ring_hi = 13'd196;
        5'd1: pd_ring_hi = 13'd223;
        5'd2: pd_ring_hi = 13'd252;
        5'd3: pd_ring_hi = 13'd282;
        5'd4: pd_ring_hi = 13'd314;
        5'd5: pd_ring_hi = 13'd348;
        5'd6: pd_ring_hi = 13'd384;
        5'd7: pd_ring_hi = 13'd422;
        5'd8: pd_ring_hi = 13'd461;
        5'd9: pd_ring_hi = 13'd502;
        5'd10: pd_ring_hi = 13'd544;
        5'd11: pd_ring_hi = 13'd589;
        5'd12: pd_ring_hi = 13'd635;
        5'd13: pd_ring_hi = 13'd683;
        5'd14: pd_ring_hi = 13'd733;
        5'd15: pd_ring_hi = 13'd784;
        5'd16: pd_ring_hi = 13'd837;
        5'd17: pd_ring_hi = 13'd892;
        5'd18: pd_ring_hi = 13'd949;
        5'd19: pd_ring_hi = 13'd1007;
        5'd20: pd_ring_hi = 13'd1067;
        5'd21: pd_ring_hi = 13'd1129;
        5'd22: pd_ring_hi = 13'd1193;
        5'd23: pd_ring_hi = 13'd1258;
        5'd24: pd_ring_hi = 13'd1325;
        5'd25: pd_ring_hi = 13'd1394;
        5'd26: pd_ring_hi = 13'd1464;
        5'd27: pd_ring_hi = 13'd1537;
        5'd28: pd_ring_hi = 13'd1611;
        5'd29: pd_ring_hi = 13'd1686;
        default: pd_ring_hi = 13'd0;
    endcase
endfunction

// BLASTER: bossolo al frame `f` dallo sparo (2-25): colonna e riga dalla prima del colpo vuotato
function signed [5:0] pd_case_x(input [4:0] f);
    case (f)
        5'd2: pd_case_x = -7;
        5'd3: pd_case_x = -7;
        5'd4: pd_case_x = -8;
        5'd5: pd_case_x = -8;
        5'd6: pd_case_x = -9;
        5'd7: pd_case_x = -9;
        5'd8: pd_case_x = -9;
        5'd9: pd_case_x = -10;
        5'd10: pd_case_x = -10;
        5'd11: pd_case_x = -11;
        5'd12: pd_case_x = -11;
        5'd13: pd_case_x = -12;
        5'd14: pd_case_x = -12;
        5'd15: pd_case_x = -12;
        5'd16: pd_case_x = -13;
        5'd17: pd_case_x = -13;
        5'd18: pd_case_x = -14;
        5'd19: pd_case_x = -14;
        5'd20: pd_case_x = -14;
        5'd21: pd_case_x = -15;
        5'd22: pd_case_x = -15;
        5'd23: pd_case_x = -16;
        5'd24: pd_case_x = -16;
        5'd25: pd_case_x = -17;
        default: pd_case_x = 6'sd31;
    endcase
endfunction
function signed [5:0] pd_case_y(input [4:0] f);
    case (f)
        5'd2: pd_case_y = 0;
        5'd3: pd_case_y = -1;
        5'd4: pd_case_y = -1;
        5'd5: pd_case_y = -2;
        5'd6: pd_case_y = -2;
        5'd7: pd_case_y = -3;
        5'd8: pd_case_y = -3;
        5'd9: pd_case_y = -4;
        5'd10: pd_case_y = -4;
        5'd11: pd_case_y = -4;
        5'd12: pd_case_y = -4;
        5'd13: pd_case_y = -4;
        5'd14: pd_case_y = -4;
        5'd15: pd_case_y = -4;
        5'd16: pd_case_y = -3;
        5'd17: pd_case_y = -3;
        5'd18: pd_case_y = -3;
        5'd19: pd_case_y = -2;
        5'd20: pd_case_y = -1;
        5'd21: pd_case_y = 0;
        5'd22: pd_case_y = 0;
        5'd23: pd_case_y = 1;
        5'd24: pd_case_y = 2;
        5'd25: pd_case_y = 3;
        default: pd_case_y = 6'sd0;
    endcase
endfunction

// GUARDIAN: spostamento del corso che cade, `d` frame dall'inizio della caduta (0-14)
function signed [4:0] pd_build_dy(input [3:0] d);
    case (d)
        4'd0: pd_build_dy = -14;
        4'd1: pd_build_dy = -14;
        4'd2: pd_build_dy = -13;
        4'd3: pd_build_dy = -13;
        4'd4: pd_build_dy = -12;
        4'd5: pd_build_dy = -10;
        4'd6: pd_build_dy = -9;
        4'd7: pd_build_dy = -8;
        4'd8: pd_build_dy = -6;
        4'd9: pd_build_dy = -5;
        4'd10: pd_build_dy = -4;
        4'd11: pd_build_dy = -2;
        4'd12: pd_build_dy = -1;
        4'd13: pd_build_dy = -1;
        4'd14: pd_build_dy = 0;
        default: pd_build_dy = 5'sd0;
    endcase
endfunction

// GUARDIAN: schegge del corso rotto al frame `a` dalla fine della crepa (0-29): colonna e riga
// (dalla prima del corso) della scheggia j (le pari larghe 2 e scure, le dispari 1 e grigie)
function signed [5:0] pd_chip_x(input [4:0] a, input [1:0] j);
    case ({a, j})
        {5'd0, 2'd0}: pd_chip_x = -7;
        {5'd0, 2'd1}: pd_chip_x = -7;
        {5'd0, 2'd2}: pd_chip_x = -7;
        {5'd0, 2'd3}: pd_chip_x = -7;
        {5'd1, 2'd0}: pd_chip_x = -7;
        {5'd1, 2'd1}: pd_chip_x = -7;
        {5'd1, 2'd2}: pd_chip_x = -7;
        {5'd1, 2'd3}: pd_chip_x = -7;
        {5'd2, 2'd0}: pd_chip_x = -7;
        {5'd2, 2'd1}: pd_chip_x = -7;
        {5'd2, 2'd2}: pd_chip_x = -8;
        {5'd2, 2'd3}: pd_chip_x = -8;
        {5'd3, 2'd0}: pd_chip_x = -7;
        {5'd3, 2'd1}: pd_chip_x = -8;
        {5'd3, 2'd2}: pd_chip_x = -8;
        {5'd3, 2'd3}: pd_chip_x = -8;
        {5'd4, 2'd0}: pd_chip_x = -8;
        {5'd4, 2'd1}: pd_chip_x = -8;
        {5'd4, 2'd2}: pd_chip_x = -8;
        {5'd4, 2'd3}: pd_chip_x = -8;
        {5'd5, 2'd0}: pd_chip_x = -8;
        {5'd5, 2'd1}: pd_chip_x = -8;
        {5'd5, 2'd2}: pd_chip_x = -8;
        {5'd5, 2'd3}: pd_chip_x = -9;
        {5'd6, 2'd0}: pd_chip_x = -8;
        {5'd6, 2'd1}: pd_chip_x = -8;
        {5'd6, 2'd2}: pd_chip_x = -9;
        {5'd6, 2'd3}: pd_chip_x = -9;
        {5'd7, 2'd0}: pd_chip_x = -8;
        {5'd7, 2'd1}: pd_chip_x = -9;
        {5'd7, 2'd2}: pd_chip_x = -9;
        {5'd7, 2'd3}: pd_chip_x = -10;
        {5'd8, 2'd0}: pd_chip_x = -8;
        {5'd8, 2'd1}: pd_chip_x = -9;
        {5'd8, 2'd2}: pd_chip_x = -9;
        {5'd8, 2'd3}: pd_chip_x = -10;
        {5'd9, 2'd0}: pd_chip_x = -8;
        {5'd9, 2'd1}: pd_chip_x = -9;
        {5'd9, 2'd2}: pd_chip_x = -10;
        {5'd9, 2'd3}: pd_chip_x = -10;
        {5'd10, 2'd0}: pd_chip_x = -9;
        {5'd10, 2'd1}: pd_chip_x = -9;
        {5'd10, 2'd2}: pd_chip_x = -10;
        {5'd10, 2'd3}: pd_chip_x = -11;
        {5'd11, 2'd0}: pd_chip_x = -9;
        {5'd11, 2'd1}: pd_chip_x = -10;
        {5'd11, 2'd2}: pd_chip_x = -10;
        {5'd11, 2'd3}: pd_chip_x = -11;
        {5'd12, 2'd0}: pd_chip_x = -9;
        {5'd12, 2'd1}: pd_chip_x = -10;
        {5'd12, 2'd2}: pd_chip_x = -11;
        {5'd12, 2'd3}: pd_chip_x = -11;
        {5'd13, 2'd0}: pd_chip_x = -9;
        {5'd13, 2'd1}: pd_chip_x = -10;
        {5'd13, 2'd2}: pd_chip_x = -11;
        {5'd13, 2'd3}: pd_chip_x = -12;
        {5'd14, 2'd0}: pd_chip_x = -9;
        {5'd14, 2'd1}: pd_chip_x = -10;
        {5'd14, 2'd2}: pd_chip_x = -11;
        {5'd14, 2'd3}: pd_chip_x = -12;
        {5'd15, 2'd0}: pd_chip_x = -9;
        {5'd15, 2'd1}: pd_chip_x = -10;
        {5'd15, 2'd2}: pd_chip_x = -11;
        {5'd15, 2'd3}: pd_chip_x = -12;
        {5'd16, 2'd0}: pd_chip_x = -10;
        {5'd16, 2'd1}: pd_chip_x = -11;
        {5'd16, 2'd2}: pd_chip_x = -12;
        {5'd16, 2'd3}: pd_chip_x = -13;
        {5'd17, 2'd0}: pd_chip_x = -10;
        {5'd17, 2'd1}: pd_chip_x = -11;
        {5'd17, 2'd2}: pd_chip_x = -12;
        {5'd17, 2'd3}: pd_chip_x = -13;
        {5'd18, 2'd0}: pd_chip_x = -10;
        {5'd18, 2'd1}: pd_chip_x = -11;
        {5'd18, 2'd2}: pd_chip_x = -12;
        {5'd18, 2'd3}: pd_chip_x = -14;
        {5'd19, 2'd0}: pd_chip_x = -10;
        {5'd19, 2'd1}: pd_chip_x = -11;
        {5'd19, 2'd2}: pd_chip_x = -13;
        {5'd19, 2'd3}: pd_chip_x = -14;
        {5'd20, 2'd0}: pd_chip_x = -10;
        {5'd20, 2'd1}: pd_chip_x = -12;
        {5'd20, 2'd2}: pd_chip_x = -13;
        {5'd20, 2'd3}: pd_chip_x = -14;
        {5'd21, 2'd0}: pd_chip_x = -10;
        {5'd21, 2'd1}: pd_chip_x = -12;
        {5'd21, 2'd2}: pd_chip_x = -13;
        {5'd21, 2'd3}: pd_chip_x = -15;
        {5'd22, 2'd0}: pd_chip_x = -11;
        {5'd22, 2'd1}: pd_chip_x = -12;
        {5'd22, 2'd2}: pd_chip_x = -14;
        {5'd22, 2'd3}: pd_chip_x = -15;
        {5'd23, 2'd0}: pd_chip_x = -11;
        {5'd23, 2'd1}: pd_chip_x = -12;
        {5'd23, 2'd2}: pd_chip_x = -14;
        {5'd23, 2'd3}: pd_chip_x = -15;
        {5'd24, 2'd0}: pd_chip_x = -11;
        {5'd24, 2'd1}: pd_chip_x = -13;
        {5'd24, 2'd2}: pd_chip_x = -14;
        {5'd24, 2'd3}: pd_chip_x = -16;
        {5'd25, 2'd0}: pd_chip_x = -11;
        {5'd25, 2'd1}: pd_chip_x = -13;
        {5'd25, 2'd2}: pd_chip_x = -14;
        {5'd25, 2'd3}: pd_chip_x = -16;
        {5'd26, 2'd0}: pd_chip_x = -11;
        {5'd26, 2'd1}: pd_chip_x = -13;
        {5'd26, 2'd2}: pd_chip_x = -15;
        {5'd26, 2'd3}: pd_chip_x = -17;
        {5'd27, 2'd0}: pd_chip_x = -11;
        {5'd27, 2'd1}: pd_chip_x = -13;
        {5'd27, 2'd2}: pd_chip_x = -15;
        {5'd27, 2'd3}: pd_chip_x = -17;
        {5'd28, 2'd0}: pd_chip_x = -12;
        {5'd28, 2'd1}: pd_chip_x = -14;
        {5'd28, 2'd2}: pd_chip_x = -15;
        {5'd28, 2'd3}: pd_chip_x = -17;
        {5'd29, 2'd0}: pd_chip_x = -12;
        {5'd29, 2'd1}: pd_chip_x = -14;
        {5'd29, 2'd2}: pd_chip_x = -16;
        {5'd29, 2'd3}: pd_chip_x = -18;
        default: pd_chip_x = 6'sd31;
    endcase
endfunction
function signed [5:0] pd_chip_y(input [4:0] a, input [1:0] j);
    case ({a, j})
        {5'd0, 2'd0}: pd_chip_y = 1;
        {5'd0, 2'd1}: pd_chip_y = 3;
        {5'd0, 2'd2}: pd_chip_y = 4;
        {5'd0, 2'd3}: pd_chip_y = 6;
        {5'd1, 2'd0}: pd_chip_y = 1;
        {5'd1, 2'd1}: pd_chip_y = 2;
        {5'd1, 2'd2}: pd_chip_y = 4;
        {5'd1, 2'd3}: pd_chip_y = 6;
        {5'd2, 2'd0}: pd_chip_y = 1;
        {5'd2, 2'd1}: pd_chip_y = 2;
        {5'd2, 2'd2}: pd_chip_y = 4;
        {5'd2, 2'd3}: pd_chip_y = 6;
        {5'd3, 2'd0}: pd_chip_y = 1;
        {5'd3, 2'd1}: pd_chip_y = 2;
        {5'd3, 2'd2}: pd_chip_y = 4;
        {5'd3, 2'd3}: pd_chip_y = 6;
        {5'd4, 2'd0}: pd_chip_y = 0;
        {5'd4, 2'd1}: pd_chip_y = 2;
        {5'd4, 2'd2}: pd_chip_y = 4;
        {5'd4, 2'd3}: pd_chip_y = 6;
        {5'd5, 2'd0}: pd_chip_y = 0;
        {5'd5, 2'd1}: pd_chip_y = 2;
        {5'd5, 2'd2}: pd_chip_y = 4;
        {5'd5, 2'd3}: pd_chip_y = 6;
        {5'd6, 2'd0}: pd_chip_y = 0;
        {5'd6, 2'd1}: pd_chip_y = 2;
        {5'd6, 2'd2}: pd_chip_y = 4;
        {5'd6, 2'd3}: pd_chip_y = 6;
        {5'd7, 2'd0}: pd_chip_y = 0;
        {5'd7, 2'd1}: pd_chip_y = 2;
        {5'd7, 2'd2}: pd_chip_y = 4;
        {5'd7, 2'd3}: pd_chip_y = 7;
        {5'd8, 2'd0}: pd_chip_y = 0;
        {5'd8, 2'd1}: pd_chip_y = 2;
        {5'd8, 2'd2}: pd_chip_y = 4;
        {5'd8, 2'd3}: pd_chip_y = 7;
        {5'd9, 2'd0}: pd_chip_y = 0;
        {5'd9, 2'd1}: pd_chip_y = 2;
        {5'd9, 2'd2}: pd_chip_y = 4;
        {5'd9, 2'd3}: pd_chip_y = 7;
        {5'd10, 2'd0}: pd_chip_y = 0;
        {5'd10, 2'd1}: pd_chip_y = 2;
        {5'd10, 2'd2}: pd_chip_y = 5;
        {5'd10, 2'd3}: pd_chip_y = 7;
        {5'd11, 2'd0}: pd_chip_y = -1;
        {5'd11, 2'd1}: pd_chip_y = 2;
        {5'd11, 2'd2}: pd_chip_y = 5;
        {5'd11, 2'd3}: pd_chip_y = 7;
        {5'd12, 2'd0}: pd_chip_y = -1;
        {5'd12, 2'd1}: pd_chip_y = 2;
        {5'd12, 2'd2}: pd_chip_y = 5;
        {5'd12, 2'd3}: pd_chip_y = 7;
        {5'd13, 2'd0}: pd_chip_y = -1;
        {5'd13, 2'd1}: pd_chip_y = 2;
        {5'd13, 2'd2}: pd_chip_y = 5;
        {5'd13, 2'd3}: pd_chip_y = 7;
        {5'd14, 2'd0}: pd_chip_y = -1;
        {5'd14, 2'd1}: pd_chip_y = 2;
        {5'd14, 2'd2}: pd_chip_y = 5;
        {5'd14, 2'd3}: pd_chip_y = 8;
        {5'd15, 2'd0}: pd_chip_y = -1;
        {5'd15, 2'd1}: pd_chip_y = 2;
        {5'd15, 2'd2}: pd_chip_y = 5;
        {5'd15, 2'd3}: pd_chip_y = 8;
        {5'd16, 2'd0}: pd_chip_y = -1;
        {5'd16, 2'd1}: pd_chip_y = 2;
        {5'd16, 2'd2}: pd_chip_y = 5;
        {5'd16, 2'd3}: pd_chip_y = 8;
        {5'd17, 2'd0}: pd_chip_y = -2;
        {5'd17, 2'd1}: pd_chip_y = 2;
        {5'd17, 2'd2}: pd_chip_y = 5;
        {5'd17, 2'd3}: pd_chip_y = 8;
        {5'd18, 2'd0}: pd_chip_y = -2;
        {5'd18, 2'd1}: pd_chip_y = 2;
        {5'd18, 2'd2}: pd_chip_y = 5;
        {5'd18, 2'd3}: pd_chip_y = 8;
        {5'd19, 2'd0}: pd_chip_y = -2;
        {5'd19, 2'd1}: pd_chip_y = 2;
        {5'd19, 2'd2}: pd_chip_y = 5;
        {5'd19, 2'd3}: pd_chip_y = 8;
        {5'd20, 2'd0}: pd_chip_y = -2;
        {5'd20, 2'd1}: pd_chip_y = 2;
        {5'd20, 2'd2}: pd_chip_y = 5;
        {5'd20, 2'd3}: pd_chip_y = 9;
        {5'd21, 2'd0}: pd_chip_y = -2;
        {5'd21, 2'd1}: pd_chip_y = 1;
        {5'd21, 2'd2}: pd_chip_y = 5;
        {5'd21, 2'd3}: pd_chip_y = 9;
        {5'd22, 2'd0}: pd_chip_y = -2;
        {5'd22, 2'd1}: pd_chip_y = 1;
        {5'd22, 2'd2}: pd_chip_y = 5;
        {5'd22, 2'd3}: pd_chip_y = 9;
        {5'd23, 2'd0}: pd_chip_y = -2;
        {5'd23, 2'd1}: pd_chip_y = 1;
        {5'd23, 2'd2}: pd_chip_y = 5;
        {5'd23, 2'd3}: pd_chip_y = 9;
        {5'd24, 2'd0}: pd_chip_y = -3;
        {5'd24, 2'd1}: pd_chip_y = 1;
        {5'd24, 2'd2}: pd_chip_y = 5;
        {5'd24, 2'd3}: pd_chip_y = 9;
        {5'd25, 2'd0}: pd_chip_y = -3;
        {5'd25, 2'd1}: pd_chip_y = 1;
        {5'd25, 2'd2}: pd_chip_y = 5;
        {5'd25, 2'd3}: pd_chip_y = 9;
        {5'd26, 2'd0}: pd_chip_y = -3;
        {5'd26, 2'd1}: pd_chip_y = 1;
        {5'd26, 2'd2}: pd_chip_y = 5;
        {5'd26, 2'd3}: pd_chip_y = 9;
        {5'd27, 2'd0}: pd_chip_y = -3;
        {5'd27, 2'd1}: pd_chip_y = 1;
        {5'd27, 2'd2}: pd_chip_y = 5;
        {5'd27, 2'd3}: pd_chip_y = 10;
        {5'd28, 2'd0}: pd_chip_y = -3;
        {5'd28, 2'd1}: pd_chip_y = 1;
        {5'd28, 2'd2}: pd_chip_y = 5;
        {5'd28, 2'd3}: pd_chip_y = 10;
        {5'd29, 2'd0}: pd_chip_y = -3;
        {5'd29, 2'd1}: pd_chip_y = 1;
        {5'd29, 2'd2}: pd_chip_y = 5;
        {5'd29, 2'd3}: pd_chip_y = 10;
        default: pd_chip_y = 6'sd0;
    endcase
endfunction

// muro del GUARDIAN in campo: schegge del blocco al frame `f` dalla fine del lampo (0-26):
// spostamento verso il fondo (per j % 3), caduta e tono del blu (0 pieno, 1 e 2 piu' scuri)
function [3:0] pd_crumble_dx(input [4:0] f, input [1:0] m);
    case ({f, m})
        {5'd0, 2'd0}: pd_crumble_dx = 0;
        {5'd0, 2'd1}: pd_crumble_dx = 0;
        {5'd0, 2'd2}: pd_crumble_dx = 0;
        {5'd1, 2'd0}: pd_crumble_dx = 0;
        {5'd1, 2'd1}: pd_crumble_dx = 0;
        {5'd1, 2'd2}: pd_crumble_dx = 0;
        {5'd2, 2'd0}: pd_crumble_dx = 0;
        {5'd2, 2'd1}: pd_crumble_dx = 0;
        {5'd2, 2'd2}: pd_crumble_dx = 1;
        {5'd3, 2'd0}: pd_crumble_dx = 0;
        {5'd3, 2'd1}: pd_crumble_dx = 1;
        {5'd3, 2'd2}: pd_crumble_dx = 1;
        {5'd4, 2'd0}: pd_crumble_dx = 0;
        {5'd4, 2'd1}: pd_crumble_dx = 1;
        {5'd4, 2'd2}: pd_crumble_dx = 1;
        {5'd5, 2'd0}: pd_crumble_dx = 1;
        {5'd5, 2'd1}: pd_crumble_dx = 1;
        {5'd5, 2'd2}: pd_crumble_dx = 2;
        {5'd6, 2'd0}: pd_crumble_dx = 1;
        {5'd6, 2'd1}: pd_crumble_dx = 1;
        {5'd6, 2'd2}: pd_crumble_dx = 2;
        {5'd7, 2'd0}: pd_crumble_dx = 1;
        {5'd7, 2'd1}: pd_crumble_dx = 2;
        {5'd7, 2'd2}: pd_crumble_dx = 2;
        {5'd8, 2'd0}: pd_crumble_dx = 1;
        {5'd8, 2'd1}: pd_crumble_dx = 2;
        {5'd8, 2'd2}: pd_crumble_dx = 3;
        {5'd9, 2'd0}: pd_crumble_dx = 1;
        {5'd9, 2'd1}: pd_crumble_dx = 2;
        {5'd9, 2'd2}: pd_crumble_dx = 3;
        {5'd10, 2'd0}: pd_crumble_dx = 1;
        {5'd10, 2'd1}: pd_crumble_dx = 2;
        {5'd10, 2'd2}: pd_crumble_dx = 3;
        {5'd11, 2'd0}: pd_crumble_dx = 1;
        {5'd11, 2'd1}: pd_crumble_dx = 2;
        {5'd11, 2'd2}: pd_crumble_dx = 4;
        {5'd12, 2'd0}: pd_crumble_dx = 1;
        {5'd12, 2'd1}: pd_crumble_dx = 3;
        {5'd12, 2'd2}: pd_crumble_dx = 4;
        {5'd13, 2'd0}: pd_crumble_dx = 1;
        {5'd13, 2'd1}: pd_crumble_dx = 3;
        {5'd13, 2'd2}: pd_crumble_dx = 4;
        {5'd14, 2'd0}: pd_crumble_dx = 2;
        {5'd14, 2'd1}: pd_crumble_dx = 3;
        {5'd14, 2'd2}: pd_crumble_dx = 5;
        {5'd15, 2'd0}: pd_crumble_dx = 2;
        {5'd15, 2'd1}: pd_crumble_dx = 3;
        {5'd15, 2'd2}: pd_crumble_dx = 5;
        {5'd16, 2'd0}: pd_crumble_dx = 2;
        {5'd16, 2'd1}: pd_crumble_dx = 4;
        {5'd16, 2'd2}: pd_crumble_dx = 5;
        {5'd17, 2'd0}: pd_crumble_dx = 2;
        {5'd17, 2'd1}: pd_crumble_dx = 4;
        {5'd17, 2'd2}: pd_crumble_dx = 6;
        {5'd18, 2'd0}: pd_crumble_dx = 2;
        {5'd18, 2'd1}: pd_crumble_dx = 4;
        {5'd18, 2'd2}: pd_crumble_dx = 6;
        {5'd19, 2'd0}: pd_crumble_dx = 2;
        {5'd19, 2'd1}: pd_crumble_dx = 4;
        {5'd19, 2'd2}: pd_crumble_dx = 6;
        {5'd20, 2'd0}: pd_crumble_dx = 2;
        {5'd20, 2'd1}: pd_crumble_dx = 4;
        {5'd20, 2'd2}: pd_crumble_dx = 7;
        {5'd21, 2'd0}: pd_crumble_dx = 2;
        {5'd21, 2'd1}: pd_crumble_dx = 5;
        {5'd21, 2'd2}: pd_crumble_dx = 7;
        {5'd22, 2'd0}: pd_crumble_dx = 2;
        {5'd22, 2'd1}: pd_crumble_dx = 5;
        {5'd22, 2'd2}: pd_crumble_dx = 7;
        {5'd23, 2'd0}: pd_crumble_dx = 3;
        {5'd23, 2'd1}: pd_crumble_dx = 5;
        {5'd23, 2'd2}: pd_crumble_dx = 8;
        {5'd24, 2'd0}: pd_crumble_dx = 3;
        {5'd24, 2'd1}: pd_crumble_dx = 5;
        {5'd24, 2'd2}: pd_crumble_dx = 8;
        {5'd25, 2'd0}: pd_crumble_dx = 3;
        {5'd25, 2'd1}: pd_crumble_dx = 6;
        {5'd25, 2'd2}: pd_crumble_dx = 8;
        {5'd26, 2'd0}: pd_crumble_dx = 3;
        {5'd26, 2'd1}: pd_crumble_dx = 6;
        {5'd26, 2'd2}: pd_crumble_dx = 9;
        default: pd_crumble_dx = 4'd0;
    endcase
endfunction
function [3:0] pd_crumble_dy(input [4:0] f);
    case (f)
        5'd0: pd_crumble_dy = 0;
        5'd1: pd_crumble_dy = 0;
        5'd2: pd_crumble_dy = 0;
        5'd3: pd_crumble_dy = 0;
        5'd4: pd_crumble_dy = 0;
        5'd5: pd_crumble_dy = 0;
        5'd6: pd_crumble_dy = 0;
        5'd7: pd_crumble_dy = 1;
        5'd8: pd_crumble_dy = 1;
        5'd9: pd_crumble_dy = 1;
        5'd10: pd_crumble_dy = 1;
        5'd11: pd_crumble_dy = 2;
        5'd12: pd_crumble_dy = 2;
        5'd13: pd_crumble_dy = 2;
        5'd14: pd_crumble_dy = 3;
        5'd15: pd_crumble_dy = 3;
        5'd16: pd_crumble_dy = 4;
        5'd17: pd_crumble_dy = 4;
        5'd18: pd_crumble_dy = 4;
        5'd19: pd_crumble_dy = 5;
        5'd20: pd_crumble_dy = 5;
        5'd21: pd_crumble_dy = 6;
        5'd22: pd_crumble_dy = 7;
        5'd23: pd_crumble_dy = 7;
        5'd24: pd_crumble_dy = 8;
        5'd25: pd_crumble_dy = 9;
        5'd26: pd_crumble_dy = 9;
        default: pd_crumble_dy = 4'd0;
    endcase
endfunction
function [1:0] pd_crumble_tone(input [4:0] f);
    case (f)
        5'd0: pd_crumble_tone = 2'd0;
        5'd1: pd_crumble_tone = 2'd0;
        5'd2: pd_crumble_tone = 2'd0;
        5'd3: pd_crumble_tone = 2'd0;
        5'd4: pd_crumble_tone = 2'd0;
        5'd5: pd_crumble_tone = 2'd0;
        5'd6: pd_crumble_tone = 2'd0;
        5'd7: pd_crumble_tone = 2'd1;
        5'd8: pd_crumble_tone = 2'd1;
        5'd9: pd_crumble_tone = 2'd1;
        5'd10: pd_crumble_tone = 2'd1;
        5'd11: pd_crumble_tone = 2'd1;
        5'd12: pd_crumble_tone = 2'd1;
        5'd13: pd_crumble_tone = 2'd1;
        5'd14: pd_crumble_tone = 2'd1;
        5'd15: pd_crumble_tone = 2'd1;
        5'd16: pd_crumble_tone = 2'd2;
        5'd17: pd_crumble_tone = 2'd2;
        5'd18: pd_crumble_tone = 2'd2;
        5'd19: pd_crumble_tone = 2'd2;
        5'd20: pd_crumble_tone = 2'd2;
        5'd21: pd_crumble_tone = 2'd2;
        5'd22: pd_crumble_tone = 2'd2;
        5'd23: pd_crumble_tone = 2'd2;
        5'd24: pd_crumble_tone = 2'd2;
        5'd25: pd_crumble_tone = 2'd2;
        5'd26: pd_crumble_tone = 2'd2;
        default: pd_crumble_tone = 2'd2;
    endcase
endfunction
