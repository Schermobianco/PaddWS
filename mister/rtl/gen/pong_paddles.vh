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
localparam [23:0] PD_OM_MARK = 24'hE040FF, PD_OM_MARK_DARK = 24'h862699, PD_OM_MARK_LIGHT = 24'hEE96FF;
localparam [23:0] PD_WHITE_SH = 24'hD4D6E0;
localparam [23:0] PD_GRAY_SH = 24'h96979E;
localparam [23:0] PD_ACCENT_SH = 24'hD4B021;
localparam [23:0] PD_SHADOW = 24'h30303A;
localparam [23:0] PD_GRAY = 24'hB4B4B4;
localparam [23:0] PD_GRAY_LIGHT = 24'hE2E2E6;
localparam [23:0] PD_DARK = 24'h5C5C62;
localparam [23:0] PD_DARK_DEEP = 24'h34343C;
localparam [23:0] PD_SHADOW_TITAN = 24'h12121A;
localparam [23:0] PD_RUSH_GHOST1 = 24'h0B2428;
localparam [23:0] PD_RUSH_GHOST2 = 24'h16484F;
localparam [23:0] PD_RUSH_GHOST3 = 24'h206C77;
localparam [23:0] PD_WALL = 24'h5A96FF, PD_WALL_LIGHT = 24'hBED6FF, PD_WALL1 = 24'h4878CC, PD_WALL2 = 24'h365A99;

// ------------------------------------------------- sprite delle astronavi
// Righe dello sprite del tipo k (assets/ships/sprites) sulle colonne del MiSTer (u con la faccia a 0;
// la colonna del PC subito dietro la faccia e' tolta): 4 bit per pixel, il ruolo KR_*, la colonna
// SP_U0_k nei bit 3:0. Gli agganci sono gia' tolti (sono le costanti piu' sotto).
localparam integer SP_U0_0 = -15, SP_W_0 = 16, SP_H_0 = 32;
function [63:0] sp_row0(input [5:0] v);
    case (v)
        6'd0: sp_row0 = 64'h0677760000000000;
        6'd1: sp_row0 = 64'h0777776000000000;
        6'd2: sp_row0 = 64'h8777777800000000;
        6'd3: sp_row0 = 64'h8777777800000000;
        6'd4: sp_row0 = 64'h9999999900000000;
        6'd5: sp_row0 = 64'h6112111200000000;
        6'd6: sp_row0 = 64'h8111111200000000;
        6'd7: sp_row0 = 64'h8111111200000000;
        6'd8: sp_row0 = 64'h8111117666800000;
        6'd9: sp_row0 = 64'h6222218777690000;
        6'd10: sp_row0 = 64'h8111116666690000;
        6'd11: sp_row0 = 64'h8111111888800000;
        6'd12: sp_row0 = 64'h8688882200000000;
        6'd13: sp_row0 = 64'h6335548200000000;
        6'd14: sp_row0 = 64'h8493488200000000;
        6'd15: sp_row0 = 64'h8493488200000000;
        6'd16: sp_row0 = 64'h8493488200000000;
        6'd17: sp_row0 = 64'h8493488200000000;
        6'd18: sp_row0 = 64'h6335548200000000;
        6'd19: sp_row0 = 64'h8688882200000000;
        6'd20: sp_row0 = 64'h8111111888800000;
        6'd21: sp_row0 = 64'h8111116666690000;
        6'd22: sp_row0 = 64'h6222218777690000;
        6'd23: sp_row0 = 64'h8111117666800000;
        6'd24: sp_row0 = 64'h8111111200000000;
        6'd25: sp_row0 = 64'h8111111200000000;
        6'd26: sp_row0 = 64'h6112111200000000;
        6'd27: sp_row0 = 64'h9999999900000000;
        6'd28: sp_row0 = 64'h8777777800000000;
        6'd29: sp_row0 = 64'h8777777800000000;
        6'd30: sp_row0 = 64'h0777776000000000;
        6'd31: sp_row0 = 64'h0677760000000000;
        default: sp_row0 = 64'd0;
    endcase
endfunction
localparam integer SP_U0_1 = -15, SP_W_1 = 16, SP_H_1 = 48;
function [63:0] sp_row1(input [5:0] v);
    case (v)
        6'd0: sp_row1 = 64'h0111116000000000;
        6'd1: sp_row1 = 64'h6111111600000000;
        6'd2: sp_row1 = 64'h2121211200000000;
        6'd3: sp_row1 = 64'h2121211200000000;
        6'd4: sp_row1 = 64'h2111111200000000;
        6'd5: sp_row1 = 64'h9888888800000000;
        6'd6: sp_row1 = 64'h2222222200000000;
        6'd7: sp_row1 = 64'h2111111200000000;
        6'd8: sp_row1 = 64'h2111112266660000;
        6'd9: sp_row1 = 64'h2111128666666000;
        6'd10: sp_row1 = 64'h21112A8869896A00;
        6'd11: sp_row1 = 64'h21112A8869896800;
        6'd12: sp_row1 = 64'h21112A8869896A00;
        6'd13: sp_row1 = 64'h2111128666666000;
        6'd14: sp_row1 = 64'h2222112266660000;
        6'd15: sp_row1 = 64'h2111111200000000;
        6'd16: sp_row1 = 64'h2222221200000000;
        6'd17: sp_row1 = 64'h2111111200000000;
        6'd18: sp_row1 = 64'h2111111200000000;
        6'd19: sp_row1 = 64'h4333333300000000;
        6'd20: sp_row1 = 64'h4333333430000000;
        6'd21: sp_row1 = 64'h4555668893000000;
        6'd22: sp_row1 = 64'h4555696663000000;
        6'd23: sp_row1 = 64'h4555696663000000;
        6'd24: sp_row1 = 64'h4555696663000000;
        6'd25: sp_row1 = 64'h4555696663000000;
        6'd26: sp_row1 = 64'h4555668893000000;
        6'd27: sp_row1 = 64'h4333333430000000;
        6'd28: sp_row1 = 64'h4333333300000000;
        6'd29: sp_row1 = 64'h2111111200000000;
        6'd30: sp_row1 = 64'h2111111200000000;
        6'd31: sp_row1 = 64'h2222221200000000;
        6'd32: sp_row1 = 64'h2111111200000000;
        6'd33: sp_row1 = 64'h2222112266660000;
        6'd34: sp_row1 = 64'h2111128666666000;
        6'd35: sp_row1 = 64'h21112A8869896A00;
        6'd36: sp_row1 = 64'h21112A8869896800;
        6'd37: sp_row1 = 64'h21112A8869896A00;
        6'd38: sp_row1 = 64'h2111128666666000;
        6'd39: sp_row1 = 64'h2111112266660000;
        6'd40: sp_row1 = 64'h2111111200000000;
        6'd41: sp_row1 = 64'h2222222200000000;
        6'd42: sp_row1 = 64'h9888888800000000;
        6'd43: sp_row1 = 64'h2111111200000000;
        6'd44: sp_row1 = 64'h2121211200000000;
        6'd45: sp_row1 = 64'h2121211200000000;
        6'd46: sp_row1 = 64'h6111111600000000;
        6'd47: sp_row1 = 64'h0111116000000000;
        default: sp_row1 = 64'd0;
    endcase
endfunction
localparam integer SP_U0_2 = -13, SP_W_2 = 14, SP_H_2 = 40;
function [55:0] sp_row2(input [5:0] v);
    case (v)
        6'd0: sp_row2 = 56'h03366000000000;
        6'd1: sp_row2 = 56'h83366600000000;
        6'd2: sp_row2 = 56'h83366600000000;
        6'd3: sp_row2 = 56'h99999900000000;
        6'd4: sp_row2 = 56'h63333300000000;
        6'd5: sp_row2 = 56'h63333300000000;
        6'd6: sp_row2 = 56'h63333300000000;
        6'd7: sp_row2 = 56'h61113300000000;
        6'd8: sp_row2 = 56'h62113300000000;
        6'd9: sp_row2 = 56'h62113300000000;
        6'd10: sp_row2 = 56'h62113300000000;
        6'd11: sp_row2 = 56'h62113300000000;
        6'd12: sp_row2 = 56'h62113300000000;
        6'd13: sp_row2 = 56'h62113300000000;
        6'd14: sp_row2 = 56'h62113300000000;
        6'd15: sp_row2 = 56'h62113300000000;
        6'd16: sp_row2 = 56'h62113300000000;
        6'd17: sp_row2 = 56'h62116A00099800;
        6'd18: sp_row2 = 56'h62126AA69889A0;
        6'd19: sp_row2 = 56'h62166556889990;
        6'd20: sp_row2 = 56'h62166556889990;
        6'd21: sp_row2 = 56'h62128AA69889A0;
        6'd22: sp_row2 = 56'h62118A00099800;
        6'd23: sp_row2 = 56'h62113300000000;
        6'd24: sp_row2 = 56'h62113300000000;
        6'd25: sp_row2 = 56'h62113300000000;
        6'd26: sp_row2 = 56'h62113300000000;
        6'd27: sp_row2 = 56'h62113300000000;
        6'd28: sp_row2 = 56'h62113300000000;
        6'd29: sp_row2 = 56'h62113300000000;
        6'd30: sp_row2 = 56'h62113300000000;
        6'd31: sp_row2 = 56'h62113300000000;
        6'd32: sp_row2 = 56'h62113300000000;
        6'd33: sp_row2 = 56'h62113300000000;
        6'd34: sp_row2 = 56'h62113300000000;
        6'd35: sp_row2 = 56'h62113300000000;
        6'd36: sp_row2 = 56'h99999900000000;
        6'd37: sp_row2 = 56'h66666600000000;
        6'd38: sp_row2 = 56'h66666600000000;
        6'd39: sp_row2 = 56'h06666000000000;
        default: sp_row2 = 56'd0;
    endcase
endfunction
localparam integer SP_U0_3 = -9, SP_W_3 = 10, SP_H_3 = 40;
function [39:0] sp_row3(input [5:0] v);
    case (v)
        6'd0: sp_row3 = 40'h0760000000;
        6'd1: sp_row3 = 40'h0760000000;
        6'd2: sp_row3 = 40'h6881000000;
        6'd3: sp_row3 = 40'h8111000000;
        6'd4: sp_row3 = 40'h8111000000;
        6'd5: sp_row3 = 40'h2111000000;
        6'd6: sp_row3 = 40'h2111100000;
        6'd7: sp_row3 = 40'h6111100000;
        6'd8: sp_row3 = 40'h6211133400;
        6'd9: sp_row3 = 40'h6211135360;
        6'd10: sp_row3 = 40'h6211133380;
        6'd11: sp_row3 = 40'h6211133480;
        6'd12: sp_row3 = 40'h6211144400;
        6'd13: sp_row3 = 40'h6211100000;
        6'd14: sp_row3 = 40'h6211100000;
        6'd15: sp_row3 = 40'h6211100000;
        6'd16: sp_row3 = 40'h6211100000;
        6'd17: sp_row3 = 40'h6213340000;
        6'd18: sp_row3 = 40'h6245544080;
        6'd19: sp_row3 = 40'h6244443380;
        6'd20: sp_row3 = 40'h6244443380;
        6'd21: sp_row3 = 40'h6245544080;
        6'd22: sp_row3 = 40'h6213340000;
        6'd23: sp_row3 = 40'h6211100000;
        6'd24: sp_row3 = 40'h6211100000;
        6'd25: sp_row3 = 40'h6211100000;
        6'd26: sp_row3 = 40'h6211100000;
        6'd27: sp_row3 = 40'h6211144400;
        6'd28: sp_row3 = 40'h6211133480;
        6'd29: sp_row3 = 40'h6211133380;
        6'd30: sp_row3 = 40'h6211135360;
        6'd31: sp_row3 = 40'h6211133400;
        6'd32: sp_row3 = 40'h6111100000;
        6'd33: sp_row3 = 40'h2111100000;
        6'd34: sp_row3 = 40'h2111000000;
        6'd35: sp_row3 = 40'h8111000000;
        6'd36: sp_row3 = 40'h8111000000;
        6'd37: sp_row3 = 40'h6881000000;
        6'd38: sp_row3 = 40'h0760000000;
        6'd39: sp_row3 = 40'h0760000000;
        default: sp_row3 = 40'd0;
    endcase
endfunction
localparam integer SP_U0_4 = -22, SP_W_4 = 26, SP_H_4 = 44;
function [103:0] sp_row4(input [5:0] v);
    case (v)
        6'd0: sp_row4 = 104'h00000622220000000000000000;
        6'd1: sp_row4 = 104'h000A6662222000000000000000;
        6'd2: sp_row4 = 104'h00006621112200000000000000;
        6'd3: sp_row4 = 104'h00066211111220000000000000;
        6'd4: sp_row4 = 104'h00066211111122000000000000;
        6'd5: sp_row4 = 104'h00062211111122000000000000;
        6'd6: sp_row4 = 104'h00066211111122000000000000;
        6'd7: sp_row4 = 104'h00066211111122000000000000;
        6'd8: sp_row4 = 104'h00062211111122000000000000;
        6'd9: sp_row4 = 104'h00066211111126000000000000;
        6'd10: sp_row4 = 104'h000662122AAAA8000000000000;
        6'd11: sp_row4 = 104'h0588A999888888000000000000;
        6'd12: sp_row4 = 104'h0399A99A988898000000000000;
        6'd13: sp_row4 = 104'h000622266A3AA9000000000000;
        6'd14: sp_row4 = 104'h000621111226A9A88000000000;
        6'd15: sp_row4 = 104'h0006211111112A988A00000000;
        6'd16: sp_row4 = 104'h000621111111AAA88800000000;
        6'd17: sp_row4 = 104'h00062111111129988888000000;
        6'd18: sp_row4 = 104'h00062341114429A44AA9000000;
        6'd19: sp_row4 = 104'h00062333133328A334A0000000;
        6'd20: sp_row4 = 104'h000621333331283333A0000000;
        6'd21: sp_row4 = 104'h000621133311283333A0000000;
        6'd22: sp_row4 = 104'h000621133311283333A0000000;
        6'd23: sp_row4 = 104'h000621333331283333A0000000;
        6'd24: sp_row4 = 104'h00062333133328A334A0000000;
        6'd25: sp_row4 = 104'h00062341114429A44AA9000000;
        6'd26: sp_row4 = 104'h00062111111129988888000000;
        6'd27: sp_row4 = 104'h000621111111AAA88800000000;
        6'd28: sp_row4 = 104'h0006211111112A988A00000000;
        6'd29: sp_row4 = 104'h000621111226A9A88000000000;
        6'd30: sp_row4 = 104'h000622266A3AA9000000000000;
        6'd31: sp_row4 = 104'h0399A99A988898000000000000;
        6'd32: sp_row4 = 104'h0588A999888888000000000000;
        6'd33: sp_row4 = 104'h000662122AAAA8000000000000;
        6'd34: sp_row4 = 104'h00066211111126000000000000;
        6'd35: sp_row4 = 104'h00062211111122000000000000;
        6'd36: sp_row4 = 104'h00066211111122000000000000;
        6'd37: sp_row4 = 104'h00066211111122000000000000;
        6'd38: sp_row4 = 104'h00062211111122000000000000;
        6'd39: sp_row4 = 104'h00066211111122000000000000;
        6'd40: sp_row4 = 104'h00066211111220000000000000;
        6'd41: sp_row4 = 104'h00006621112200000000000000;
        6'd42: sp_row4 = 104'h000A6662222000000000000000;
        6'd43: sp_row4 = 104'h00000622220000000000000000;
        default: sp_row4 = 104'd0;
    endcase
endfunction
localparam integer SP_U0_5 = -10, SP_W_5 = 11, SP_H_5 = 34;
function [43:0] sp_row5(input [5:0] v);
    case (v)
        6'd0: sp_row5 = 44'h03330000000;
        6'd1: sp_row5 = 44'h01233330000;
        6'd2: sp_row5 = 44'h21122223300;
        6'd3: sp_row5 = 44'h21111633330;
        6'd4: sp_row5 = 44'h21121120030;
        6'd5: sp_row5 = 44'h21121120000;
        6'd6: sp_row5 = 44'h21111120000;
        6'd7: sp_row5 = 44'h21111120000;
        6'd8: sp_row5 = 44'h21111120000;
        6'd9: sp_row5 = 44'h21111120000;
        6'd10: sp_row5 = 44'h21111120000;
        6'd11: sp_row5 = 44'h21111120000;
        6'd12: sp_row5 = 44'h21111120000;
        6'd13: sp_row5 = 44'h21111120000;
        6'd14: sp_row5 = 44'h21111120000;
        6'd15: sp_row5 = 44'h211AA826600;
        6'd16: sp_row5 = 44'h26333386660;
        6'd17: sp_row5 = 44'h26333386660;
        6'd18: sp_row5 = 44'h211AA826600;
        6'd19: sp_row5 = 44'h21111120000;
        6'd20: sp_row5 = 44'h21111120000;
        6'd21: sp_row5 = 44'h21111120000;
        6'd22: sp_row5 = 44'h21111120000;
        6'd23: sp_row5 = 44'h21111120000;
        6'd24: sp_row5 = 44'h21111120000;
        6'd25: sp_row5 = 44'h21111120000;
        6'd26: sp_row5 = 44'h21111120000;
        6'd27: sp_row5 = 44'h21111120000;
        6'd28: sp_row5 = 44'h21121120000;
        6'd29: sp_row5 = 44'h21121120030;
        6'd30: sp_row5 = 44'h21111633330;
        6'd31: sp_row5 = 44'h21122223300;
        6'd32: sp_row5 = 44'h01233330000;
        6'd33: sp_row5 = 44'h03330000000;
        default: sp_row5 = 44'd0;
    endcase
endfunction
localparam integer SP_U0_6 = -9, SP_W_6 = 10, SP_H_6 = 32;
function [39:0] sp_row6(input [5:0] v);
    case (v)
        6'd0: sp_row6 = 40'h2219000000;
        6'd1: sp_row6 = 40'h1119000000;
        6'd2: sp_row6 = 40'h1119000000;
        6'd3: sp_row6 = 40'h1119000000;
        6'd4: sp_row6 = 40'h1119000000;
        6'd5: sp_row6 = 40'h1119000000;
        6'd6: sp_row6 = 40'h3339000000;
        6'd7: sp_row6 = 40'h1119000000;
        6'd8: sp_row6 = 40'h1119000000;
        6'd9: sp_row6 = 40'h111A044400;
        6'd10: sp_row6 = 40'h111AA46A00;
        6'd11: sp_row6 = 40'h1119666690;
        6'd12: sp_row6 = 40'h3339666690;
        6'd13: sp_row6 = 40'h1119666660;
        6'd14: sp_row6 = 40'h1119668860;
        6'd15: sp_row6 = 40'h1119688860;
        6'd16: sp_row6 = 40'h1119688860;
        6'd17: sp_row6 = 40'h1119668860;
        6'd18: sp_row6 = 40'h1119666660;
        6'd19: sp_row6 = 40'h3339666690;
        6'd20: sp_row6 = 40'h1119666690;
        6'd21: sp_row6 = 40'h111AA46A00;
        6'd22: sp_row6 = 40'h111A044400;
        6'd23: sp_row6 = 40'h1119000000;
        6'd24: sp_row6 = 40'h1119000000;
        6'd25: sp_row6 = 40'h3339000000;
        6'd26: sp_row6 = 40'h1119000000;
        6'd27: sp_row6 = 40'h1119000000;
        6'd28: sp_row6 = 40'h1119000000;
        6'd29: sp_row6 = 40'h1119000000;
        6'd30: sp_row6 = 40'h1119000000;
        6'd31: sp_row6 = 40'h2219000000;
        default: sp_row6 = 40'd0;
    endcase
endfunction
localparam integer SP_WMAX = 26;
// ruolo dello sprite del tipo `kind` al pixel (u, v), KR_NONE fuori
function [3:0] sp_px(input [2:0] kind, input signed [11:0] u, input signed [11:0] v);
    reg [4*SP_WMAX-1:0] row;
    reg signed [11:0] c;
    reg in;
    begin
        row = {4*SP_WMAX{1'b0}};
        c = 12'sd0;
        in = 1'b0;
        case (kind)
            3'd0: begin c = u - SP_U0_0; in = c >= 0 && c < SP_W_0 && v >= 0 && v < SP_H_0; row = sp_row0(v[5:0]); end
            3'd1: begin c = u - SP_U0_1; in = c >= 0 && c < SP_W_1 && v >= 0 && v < SP_H_1; row = sp_row1(v[5:0]); end
            3'd2: begin c = u - SP_U0_2; in = c >= 0 && c < SP_W_2 && v >= 0 && v < SP_H_2; row = sp_row2(v[5:0]); end
            3'd3: begin c = u - SP_U0_3; in = c >= 0 && c < SP_W_3 && v >= 0 && v < SP_H_3; row = sp_row3(v[5:0]); end
            3'd4: begin c = u - SP_U0_4; in = c >= 0 && c < SP_W_4 && v >= 0 && v < SP_H_4; row = sp_row4(v[5:0]); end
            3'd5: begin c = u - SP_U0_5; in = c >= 0 && c < SP_W_5 && v >= 0 && v < SP_H_5; row = sp_row5(v[5:0]); end
            3'd6: begin c = u - SP_U0_6; in = c >= 0 && c < SP_W_6 && v >= 0 && v < SP_H_6; row = sp_row6(v[5:0]); end
            default: in = 1'b0;
        endcase
        sp_px = in ? row[{c[5:0], 2'b00} +: 4] : 4'd0;
    end
endfunction
// agganci dei motori e speciali (TWIST: getti di manovra, RUSH: scie alari), dall'alto: numero,
// colonna dell'ugello (quella subito davanti all'aggancio), prima riga e righe del getto
function [1:0] sp_eng_n(input [2:0] kind);
    case (kind)
        3'd0: sp_eng_n = 2'd2;
        3'd1: sp_eng_n = 2'd2;
        3'd2: sp_eng_n = 2'd1;
        3'd3: sp_eng_n = 2'd1;
        3'd4: sp_eng_n = 2'd2;
        3'd5: sp_eng_n = 2'd1;
        3'd6: sp_eng_n = 2'd2;
        default: sp_eng_n = 2'd0;
    endcase
endfunction
function signed [11:0] sp_eng_x(input [2:0] kind, input [1:0] i);
    case ({kind, i})
        {3'd0, 2'd0}: sp_eng_x = -11;
        {3'd0, 2'd1}: sp_eng_x = -11;
        {3'd1, 2'd0}: sp_eng_x = -13;
        {3'd1, 2'd1}: sp_eng_x = -13;
        {3'd2, 2'd0}: sp_eng_x = -12;
        {3'd3, 2'd0}: sp_eng_x = -8;
        {3'd4, 2'd0}: sp_eng_x = -16;
        {3'd4, 2'd1}: sp_eng_x = -16;
        {3'd5, 2'd0}: sp_eng_x = -9;
        {3'd6, 2'd0}: sp_eng_x = -8;
        {3'd6, 2'd1}: sp_eng_x = -8;
        default: sp_eng_x = 12'sd0;
    endcase
endfunction
function signed [11:0] sp_eng_y(input [2:0] kind, input [1:0] i);
    case ({kind, i})
        {3'd0, 2'd0}: sp_eng_y = 9;
        {3'd0, 2'd1}: sp_eng_y = 21;
        {3'd1, 2'd0}: sp_eng_y = 10;
        {3'd1, 2'd1}: sp_eng_y = 35;
        {3'd2, 2'd0}: sp_eng_y = 18;
        {3'd3, 2'd0}: sp_eng_y = 19;
        {3'd4, 2'd0}: sp_eng_y = 17;
        {3'd4, 2'd1}: sp_eng_y = 25;
        {3'd5, 2'd0}: sp_eng_y = 16;
        {3'd6, 2'd0}: sp_eng_y = 11;
        {3'd6, 2'd1}: sp_eng_y = 19;
        default: sp_eng_y = 12'sd0;
    endcase
endfunction
function signed [11:0] sp_eng_r(input [2:0] kind, input [1:0] i);
    case ({kind, i})
        {3'd0, 2'd0}: sp_eng_r = 2;
        {3'd0, 2'd1}: sp_eng_r = 2;
        {3'd1, 2'd0}: sp_eng_r = 3;
        {3'd1, 2'd1}: sp_eng_r = 3;
        {3'd2, 2'd0}: sp_eng_r = 4;
        {3'd3, 2'd0}: sp_eng_r = 2;
        {3'd4, 2'd0}: sp_eng_r = 2;
        {3'd4, 2'd1}: sp_eng_r = 2;
        {3'd5, 2'd0}: sp_eng_r = 2;
        {3'd6, 2'd0}: sp_eng_r = 2;
        {3'd6, 2'd1}: sp_eng_r = 2;
        default: sp_eng_r = 12'sd0;
    endcase
endfunction
function [1:0] sp_spc_n(input [2:0] kind);
    case (kind)
        3'd3: sp_spc_n = 2'd2;
        3'd5: sp_spc_n = 2'd2;
        default: sp_spc_n = 2'd0;
    endcase
endfunction
function signed [11:0] sp_spc_x(input [2:0] kind, input [1:0] i);
    case ({kind, i})
        {3'd3, 2'd0}: sp_spc_x = -8;
        {3'd3, 2'd1}: sp_spc_x = -8;
        {3'd5, 2'd0}: sp_spc_x = -9;
        {3'd5, 2'd1}: sp_spc_x = -9;
        default: sp_spc_x = 12'sd0;
    endcase
endfunction
function signed [11:0] sp_spc_y(input [2:0] kind, input [1:0] i);
    case ({kind, i})
        {3'd3, 2'd0}: sp_spc_y = 10;
        {3'd3, 2'd1}: sp_spc_y = 28;
        {3'd5, 2'd0}: sp_spc_y = 4;
        {3'd5, 2'd1}: sp_spc_y = 29;
        default: sp_spc_y = 12'sd0;
    endcase
endfunction
function signed [11:0] sp_spc_r(input [2:0] kind, input [1:0] i);
    case ({kind, i})
        {3'd3, 2'd0}: sp_spc_r = 2;
        {3'd3, 2'd1}: sp_spc_r = 2;
        {3'd5, 2'd0}: sp_spc_r = 1;
        {3'd5, 2'd1}: sp_spc_r = 1;
        default: sp_spc_r = 12'sd0;
    endcase
endfunction
// BLASTER: agganci delle armi (colonna e righe, davanti alle bocche), colonne delle canne, prima
// riga accesa dell'indicatore dei colpi (il verde fino alla faccia) per i colpi nel caricatore e
// distanza dei due fasci dal centro della racchetta
localparam integer SP_GUN_X0 = 3, SP_GUN_Y0 = 11, SP_GUN_R0 = 2,
                   SP_GUN_X1 = 3, SP_GUN_Y1 = 31, SP_GUN_R1 = 2, SP_BARREL = 2, BGUN_DY = 10;
function signed [11:0] bl_lit(input [2:0] ammo);
    case (ammo)
        3'd0: bl_lit = 31;
        3'd1: bl_lit = 28;
        3'd2: bl_lit = 25;
        3'd3: bl_lit = 22;
        3'd4: bl_lit = 19;
        3'd5: bl_lit = 16;
        3'd6: bl_lit = 13;
        default: bl_lit = 13;
    endcase
endfunction
// ARCADE: prima colonna della cabina (i pixel nel colore del personaggio)
localparam integer SP_CAB_U0 = -5;
// GUARDIAN: righe [y0, y1) delle cinque piastre (i pezzi tra le giunture dello sprite); le giunture
// tra una piastra e l'altra vanno con quella sotto
function signed [11:0] gs_y0(input [2:0] c);
    case (c)
        3'd0: gs_y0 = 0;
        3'd1: gs_y0 = 7;
        3'd2: gs_y0 = 13;
        3'd3: gs_y0 = 20;
        3'd4: gs_y0 = 26;
        default: gs_y0 = 12'sd0;
    endcase
endfunction
function signed [11:0] gs_y1(input [2:0] c);
    case (c)
        3'd0: gs_y1 = 6;
        3'd1: gs_y1 = 12;
        3'd2: gs_y1 = 19;
        3'd3: gs_y1 = 25;
        3'd4: gs_y1 = 32;
        default: gs_y1 = 12'sd0;
    endcase
endfunction

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
