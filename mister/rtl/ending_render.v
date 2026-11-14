// Finale della CHALLENGE, quando si batte l'ultimo avversario (come rust/game/src/ending_ui.rs, su uno
// schermo 320x240), al posto della schermata CHAMPION e prima delle iniziali. Sei parti in sequenza:
// 0 CONGRATULATIONS! (lampeggia) e, dopo un secondo, YOU WIN! (la voce la fa partire pong_top);
// 1 la sfilata dei sette avversari, uno al secondo, con il K.O. rosso mezzo secondo dopo (su PC e
//   C64 il timbro inclinato DEFEATED, che a 320x240 su colonne di 45 pixel non sta); le racchette e
//   i nomi li disegna next_render (ingressi `parade`, e `parade_ko` per spegnere le battute); qui il
//   titolo e i K.O.;
// 2 il punteggio: SCORE che sale in 3 s, CHAMPION BONUS in 1 s, poi TOTAL;
// 3 YOU ARE THE PADD WS CHAMPION con i fuochi d'artificio;
// 4 i titoli di coda, che salgono dal basso; 5 THE END (lampeggia).
// Solo bianco, giallo e rosso sul nero: le scintille si diradano invece di scurirsi.
//
// Grafica da tools/gen_ending_assets.py (pong_ending.vh):
// - scritte: righe di bitmap a 1 bit in Munro 10 px (ending_text.hex, 160 pixel per riga), ingrandite
//   2 o 3 volte qui, con le cifre "0123456789+" e il timbro già ruotato in fondo; la mappa delle righe
//   (ending_map.hex), letta una volta per riga nella cancellazione orizzontale, dice per ogni riga
//   dello schermo quale riga di bitmap, dove, a che scala, di che colore e se è una riga del
//   punteggio. Le parti fisse hanno una finestra di righe nella mappa, i titoli di coda una finestra
//   che scorre;
// - fuochi d'artificio: i punti di ending_ui.rs per ogni fuoco e frame a 15 Hz, già sulla griglia di
//   celle 2x2 pixel (ending_fw.hex). Un disegnatore li scrive in un framebuffer 160x120 a 2 bit con
//   due pagine: a ogni frame dei fuochi (4 frame video) cancella la pagina nascosta e la ridisegna
//   (circa 21.000 cicli), poi le pagine si scambiano all'inizio del vblank.
// Nessuna divisione: scala 3 con il reciproco (d * 171) >> 9, esatto fino a 511; i conteggi a tempo
// con contatori. Pipeline di due cicli come howto_render: indirizzi delle memorie dai contatori video,
// poi i colori (un pixel dura 3 cicli).

`timescale 1ns / 1ps

module ending_render #(
    parameter TEXT_ROM = "rtl/gen/ending_text.hex",
    parameter MAP_ROM = "rtl/gen/ending_map.hex",
    parameter FW_ROM = "rtl/gen/ending_fw.hex"
) (
    input  wire        clk,
    input  wire        start,          // impulso: il finale comincia (parte 0, frame 0)
    input  wire        active,         // il finale è in corso (modo M_ENDING di pong_top)
    input  wire        frame_start,    // inizio del vblank
    input  wire [8:0]  hc,
    input  wire [8:0]  vc,
    input  wire [23:0] score,          // punti prima del premio del campione
    input  wire [23:0] bonus,          // premio del campione (vittoria e partita perfetta dell'ultimo livello)
    output reg  [23:0] rgb,
    output reg         top,            // pixel del K.O.: sopra le racchette di next_render
    output wire        parade,         // sfilata in corso: racchette e nomi di next_render
    output wire [2:0]  parade_n,       // avversari già entrati nella sfilata (0-7)
    output wire [2:0]  parade_ko,      // ... e quanti hanno già il K.O. (racchetta spenta)
    output reg         say,            // impulso: la voce "YOU WIN!"
    output reg  [1:0]  beat,           // impulso della sfilata: bit 0 entra un avversario, bit 1 un timbro
    output wire        skip_ok,        // Start può saltare il finale
    output reg         done            // impulso: finale concluso
);

`include "pong_ending.vh"

localparam [23:0] BLACK = 24'h000000, WHITE = 24'hFFFFFF, YELLOW = 24'hFFD225, RED = 24'hE62828;
localparam [2:0]  P_CONGRATS = 3'd0, P_PARADE = 3'd1, P_SCORE = 3'd2, P_CHAMPION = 3'd3, P_CREDITS = 3'd4,
                  P_THE_END = 3'd5;
localparam integer ROW_BYTES = 20;                   // 160 pixel per riga di bitmap
localparam integer FB_CELLS = 160 * 120;             // una pagina del framebuffer

// ------------------------------------------------------------------ parti e tempi (una volta per frame)

reg  [2:0]  part = P_CONGRATS;
reg  [10:0] pf = 11'd0;              // frame dall'inizio della parte
reg  [1:0]  stage = 2'd0;            // scritte a comparsa visibili (gruppo <= stage)
reg  [5:0]  fl_cnt = 6'd0;           // lampeggio: frame nella fase, fase (0 giallo, 1 bianco)
reg         fl = 1'b0;
reg  [4:0]  beat_sub = 5'd0;         // sfilata: frame nella battuta e battute (avversari + timbri)
reg  [3:0]  beats = 4'd0;
reg  [23:0] disp_s = 24'd0, disp_b = 24'd0;    // SCORE e CHAMPION BONUS che salgono
reg  [9:0]  scroll = 10'd0;          // titoli: pixel di scorrimento, 7/12 di pixel per frame
reg  [3:0]  scroll_acc = 4'd0;
reg         front = 1'b0;            // pagina del framebuffer mostrata
reg         plot_go = 1'b0;
reg  [6:0]  plot_n = 7'd0;           // frame dei fuochi da disegnare

function [10:0] part_len(input [2:0] p);
    case (p)
        3'd0: part_len = END_LEN0;
        3'd1: part_len = END_LEN1;
        3'd2: part_len = END_LEN2;
        3'd3: part_len = END_LEN3;
        3'd4: part_len = END_LEN4;
        default: part_len = END_LEN5;
    endcase
endfunction

wire        last_f = pf == part_len(part) - 11'd1;
wire [2:0]  part_n = last_f ? part + 3'd1 : part;          // valori del frame che comincia
wire [10:0] pf_n = last_f ? 11'd0 : pf + 11'd1;
// passi di SCORE (1/180 al frame, con shift) e del premio (1/60)
wire [23:0] step_s = (score >> 8) + (score >> 9) - (score >> 12);
wire [23:0] step_b = (bonus >> 6) + (bonus >> 10);

assign parade = active && part == P_PARADE;
assign parade_n = (beats + 4'd1) >> 1;
assign parade_ko = beats[3:1];
assign skip_ok = part != P_CONGRATS || pf >= END_SKIP_AFTER;

always @(posedge clk) begin
    say <= 1'b0;
    beat <= 2'b00;
    done <= 1'b0;
    plot_go <= 1'b0;
    if (start) begin
        part <= P_CONGRATS;
        pf <= 11'd0;
        stage <= 2'd0;
        fl_cnt <= 6'd0;
        fl <= 1'b0;
        beats <= 4'd0;
    end else if (active && frame_start) begin
        if (last_f && part == P_THE_END) begin
            done <= 1'b1;                              // resta sull'ultimo frame finché pong_top cambia modo
        end else begin
            part <= part_n;
            pf <= pf_n;
        end
        // lampeggio di CONGRATULATIONS! (0,5 s) e THE END (0,66 s), dal giallo
        if (pf_n == 11'd0) begin
            fl_cnt <= 6'd0;
            fl <= 1'b0;
        end else if (fl_cnt == ((part_n == P_THE_END) ? END_FLASH5 - 1 : END_FLASH0 - 1)) begin
            fl_cnt <= 6'd0;
            fl <= !fl;
        end else
            fl_cnt <= fl_cnt + 6'd1;
        // scritte a comparsa: YOU WIN! dopo un secondo, CHAMPION BONUS e TOTAL dopo il conteggio
        stage <= (part_n == P_CONGRATS) ? {1'b0, pf_n >= END_YOU_WIN_AT} :
                 (part_n == P_SCORE) ? {1'b0, pf_n >= END_SCORE_COUNT} + {1'b0, pf_n >= END_TOTAL_AT} : 2'd0;
        if (part_n == P_CONGRATS && pf_n == END_YOU_WIN_AT) say <= 1'b1;
        // sfilata: una battuta ogni mezzo secondo, dispari = entra un avversario, pari = il suo timbro
        if (part_n == P_PARADE) begin
            if (pf_n == 11'd0) begin
                beat_sub <= 5'd0;
                beats <= 4'd1;
                beat <= 2'b01;
            end else if (beat_sub == END_BEAT - 1) begin
                beat_sub <= 5'd0;
                if (beats != 4'd14) begin
                    beats <= beats + 4'd1;
                    beat <= beats[0] ? 2'b10 : 2'b01;
                end
            end else
                beat_sub <= beat_sub + 5'd1;
        end
        // punteggio: SCORE sale fino a END_SCORE_COUNT, poi il premio fino a END_BONUS_END
        if (part_n == P_SCORE) begin
            if (pf_n == 11'd0) begin
                disp_s <= 24'd0;
                disp_b <= 24'd0;
            end else if (pf_n < END_SCORE_COUNT)
                disp_s <= (disp_s + step_s > score) ? score : disp_s + step_s;
            else begin
                disp_s <= score;
                if (pf_n < END_BONUS_END)
                    disp_b <= (disp_b + step_b > bonus) ? bonus : disp_b + step_b;
                else
                    disp_b <= bonus;
            end
        end
        // titoli: 35 pixel al secondo fino all'ultima riga al centro
        if (part_n == P_CREDITS) begin
            if (pf_n == 11'd0) begin
                scroll <= 10'd0;
                scroll_acc <= 4'd0;
            end else if (scroll != END_CRED_SMAX) begin
                if (scroll_acc >= 4'd5) begin
                    scroll_acc <= scroll_acc - 4'd5;
                    scroll <= scroll + 10'd1;
                end else
                    scroll_acc <= scroll_acc + 4'd7;
            end
        end
        // fuochi: il frame n (pf / 4 della parte del campione) si disegna nel frame video prima e si
        // mostra con lo scambio delle pagine; il primo nell'ultimo frame del punteggio
        if (part_n == P_SCORE && pf_n == END_LEN2 - 1) begin
            plot_go <= 1'b1;
            plot_n <= 7'd0;
        end else if (part_n == P_CHAMPION && pf_n[1:0] == 2'd3) begin
            plot_go <= 1'b1;
            plot_n <= pf_n[8:2] + 7'd1;
        end
        if (part_n == P_CHAMPION && pf_n[1:0] == 2'd0) front <= !front;
    end
end

// ------------------------------------------------------------------ cifre del punteggio (BCD)

// doppio dabble a turno su SCORE, premio e totale, un bit per ciclo (come bin_to_bcd di
// challenge_render): ogni valore si aggiorna ogni 75 cicli
reg  [1:0]  bsel = 2'd0;
reg  [23:0] bsh = 24'd0;
reg  [27:0] bacc = 28'd0;
reg  [4:0]  bcount = 5'd0;
reg  [27:0] bcd_s = 28'd0, bcd_b = 28'd0, bcd_t = 28'd0;
reg  [27:0] badj;
wire [23:0] total = score + bonus;
integer     bd;
always @(*) begin
    badj = bacc;
    for (bd = 0; bd < 7; bd = bd + 1)
        if (bacc[4 * bd +: 4] >= 4'd5) badj[4 * bd +: 4] = bacc[4 * bd +: 4] + 4'd3;
end
always @(posedge clk) begin
    if (bcount == 5'd0) begin
        bsh <= (bsel == 2'd0) ? disp_s : (bsel == 2'd1) ? disp_b : total;
        bacc <= 28'd0;
        bcount <= 5'd24;
    end else begin
        {bacc, bsh} <= {badj[26:0], bsh, 1'b0};
        bcount <= bcount - 5'd1;
        if (bcount == 5'd1) begin
            case (bsel)
                2'd0: bcd_s <= {badj[26:0], bsh[23]};
                2'd1: bcd_b <= {badj[26:0], bsh[23]};
                default: bcd_t <= {badj[26:0], bsh[23]};
            endcase
            bsel <= (bsel == 2'd2) ? 2'd0 : bsel + 2'd1;
        end
    end
end

// ------------------------------------------------------------------ memorie

reg [7:0]  trom [0:END_TEXT_BYTES-1];
reg [31:0] mrom [0:END_MAP_SIZE-1];
reg [15:0] from [0:END_FW_SIZE-1];
initial begin
    $readmemh(TEXT_ROM, trom);
    $readmemh(MAP_ROM, mrom);
    $readmemh(FW_ROM, from);
end
// framebuffer dei fuochi: due pagine da 160x120 celle, 0 niente, 1 bianco, 2 giallo, 3 rosso
reg [1:0]  fb [0:2*FB_CELLS-1];

// ------------------------------------------------------------------ mappa delle righe

// la riga dopo questa (le righe fuori dallo schermo non contano)
wire [8:0] vn = (vc == 9'd261) ? 9'd0 : vc + 9'd1;

// riga della mappa per la riga dello schermo dopo (vn) nella parte in corso (valid = 0: riga vuota)
reg        m_valid;
reg [10:0] m_idx;
reg [10:0] m_c;
always @(*) begin
    m_valid = 1'b0;
    m_idx = 11'd0;
    m_c = {2'd0, vn} + {1'b0, scroll} - END_CRED_C0;
    case (part)
        P_CONGRATS: begin m_valid = vn - END_WIN0_TOP < END_WIN0_H; m_idx = END_WIN0_BASE + vn - END_WIN0_TOP; end
        P_PARADE:   begin m_valid = vn - END_WIN1_TOP < END_WIN1_H; m_idx = END_WIN1_BASE + vn - END_WIN1_TOP; end
        P_SCORE:    begin m_valid = vn - END_WIN2_TOP < END_WIN2_H; m_idx = END_WIN2_BASE + vn - END_WIN2_TOP; end
        P_CHAMPION: begin m_valid = vn - END_WIN3_TOP < END_WIN3_H; m_idx = END_WIN3_BASE + vn - END_WIN3_TOP; end
        P_CREDITS:  begin m_valid = m_c < END_CRED_LEN; m_idx = END_CRED_BASE + m_c; end
        default:    begin m_valid = vn - END_WIN5_TOP < END_WIN5_H; m_idx = END_WIN5_BASE + vn - END_WIN5_TOP; end
    endcase
end
reg [10:0] maddr = 11'd0;
reg [31:0] mdata = 32'd0;
reg        mval = 1'b0;
reg [31:0] ent = 32'd0;              // parola della mappa della riga in corso
always @(posedge clk) begin
    mdata <= mrom[maddr];
    // nella cancellazione orizzontale: indirizzo per la riga dopo, poi la parola (tre cicli dopo)
    if (hc == 9'd340) begin
        maddr <= m_idx;
        mval <= m_valid;
    end
    if (hc == 9'd350) ent <= mval ? mdata : 32'd0;
end

wire [8:0] e_row = ent[8:0];
wire [3:0] e_g = ent[12:9];
wire [8:0] e_x = ent[21:13];
wire [1:0] e_scale = ent[23:22];
wire [1:0] e_color = ent[25:24];
wire [1:0] e_group = ent[27:26];
wire [1:0] e_num = ent[29:28];

// ------------------------------------------------------------------ pixel, primo ciclo: indirizzi

// d / scala (1, 2 o 3), senza divisioni
function [8:0] unscale(input [8:0] d, input [1:0] s);
    reg [17:0] m;
    begin
        m = {9'd0, d} * 18'd171;
        unscale = (s == 2'd1) ? d : (s == 2'd2) ? {1'b0, d[8:1]} : m[17:9];
    end
endfunction

// cifra j (0 = la più a sinistra) di un numero BCD a 7 cifre
function [3:0] bcd_digit(input [27:0] v, input [2:0] j);
    bcd_digit = v[4 * (6 - j) +: 4];
endfunction

function [8:0] col_x(input [2:0] k);
    case (k)
        3'd0: col_x = END_COL0;
        3'd1: col_x = END_COL1;
        3'd2: col_x = END_COL2;
        3'd3: col_x = END_COL3;
        3'd4: col_x = END_COL4;
        3'd5: col_x = END_COL5;
        default: col_x = END_COL6;
    endcase
endfunction

wire [8:0] x = hc;
wire [8:0] y = vc;

reg        t_on;                     // pixel di una scritta o di una cifra (prima del bit della bitmap)
reg [8:0]  t_row;
reg [7:0]  t_col;
reg        digits;                   // pixel nella zona delle cifre di una riga del punteggio
reg [8:0]  u;
reg [2:0]  dj;
reg [3:0]  dv;
reg [7:0]  dx;
// timbri: quello della colonna (porta A) e il vicino dalla parte del pixel (porta B)
reg        s_rows, sa_on, sb_on;
reg [2:0]  sk, sn;
reg [8:0]  sa_x, sb_x;
always @(*) begin
    t_on = 1'b0;
    t_row = e_row;
    t_col = 8'd0;
    dj = 3'd0;
    dv = 4'd0;
    dx = 8'd0;
    // una sola divisione per la scala: dalla x della scritta o da quella della prima cifra
    digits = e_num != 2'd0 && x >= END_DIG_X0;
    u = unscale(x - (digits ? END_DIG_X0 : e_x), e_scale);
    if (e_scale != 2'd0 && e_group <= stage) begin
        if (digits) begin
            // riga del punteggio: sette celle di cifre (il premio con il "+" davanti)
            dj = (u >= END_CELL) + (u >= 2 * END_CELL) + (u >= 3 * END_CELL) + (u >= 4 * END_CELL) +
                 (u >= 5 * END_CELL) + (u >= 6 * END_CELL);
            dx = u - dj * END_CELL;
            dv = (e_num == 2'd1) ? bcd_digit(bcd_s, dj) : (e_num == 2'd2) ? bcd_digit(bcd_b, dj) : bcd_digit(bcd_t, dj);
            if (e_num == 2'd2 && dj == 3'd0) dv = 4'd10;
            t_on = u < 7 * END_CELL;
            t_row = END_STRIP_ROW0 + e_g;
            t_col = dv * END_CELL + dx;
        end else begin
            t_on = x >= e_x && u < ROW_BYTES * 8;
            t_col = u[7:0];
        end
    end
    // colonna del timbro sotto il pixel e il vicino verso cui sta il pixel
    sk = (x >= (END_COL0 + END_COL1) / 2) + (x >= (END_COL1 + END_COL2) / 2) + (x >= (END_COL2 + END_COL3) / 2) +
         (x >= (END_COL3 + END_COL4) / 2) + (x >= (END_COL4 + END_COL5) / 2) + (x >= (END_COL5 + END_COL6) / 2);
    sn = (x >= col_x(sk)) ? sk + 3'd1 : sk - 3'd1;      // 7 o "-1" (7) = nessuno
    s_rows = part == P_PARADE && y - END_STAMP_Y0 < END_STAMP_H;
    sa_x = x - (col_x(sk) - 9'd1 - END_STAMP_W / 2);
    sb_x = x - (col_x(sn) - 9'd1 - END_STAMP_W / 2);
    sa_on = s_rows && sk < beats[3:1] && sa_x < END_STAMP_W;
    sb_on = s_rows && sn != 3'd7 && sn < beats[3:1] && sb_x < END_STAMP_W;
    if (s_rows) begin
        t_row = END_STAMP_ROW0 + (y - END_STAMP_Y0);
        t_col = sa_x[7:0];
    end
end

// bitmap: porta A per scritte, cifre e timbro della colonna, porta B per il timbro vicino
wire [13:0] ta = {t_row, 4'd0} + {t_row, 2'd0} + t_col[7:3];
wire [13:0] tb = {t_row, 4'd0} + {t_row, 2'd0} + sb_x[7:3];
reg  [7:0]  tqa = 8'd0, tqb = 8'd0;
// fuochi: la pagina mostrata, cella (x / 2, y / 2)
wire [15:0] fa = (front ? FB_CELLS : 0) + {y[8:1], 7'd0} + {2'd0, y[8:1], 5'd0} + {8'd0, x[8:1]};
reg  [1:0]  fq = 2'd0;
reg  [2:0]  ca = 3'd0, cb = 3'd0;
reg         q_text = 1'b0, q_sa = 1'b0, q_sb = 1'b0, q_fw = 1'b0;
reg  [1:0]  q_color = 2'd0;
always @(posedge clk) begin
    tqa <= trom[ta];
    tqb <= trom[tb];
    fq <= fb[fa];
    ca <= t_col[2:0];
    cb <= sb_x[2:0];
    q_text <= active && t_on && !s_rows;
    q_sa <= active && sa_on;
    q_sb <= active && sb_on;
    q_fw <= active && part == P_CHAMPION && x < 9'd320 && y < 9'd240;
    q_color <= e_color;
end

// ------------------------------------------------------------------ pixel, secondo ciclo: colori

wire text_px = q_text && tqa[ca];
wire stamp_px = (q_sa && tqa[ca]) || (q_sb && tqb[cb]);
always @(posedge clk) begin
    top <= stamp_px;
    if (text_px)
        rgb <= (q_color == 2'd0) ? WHITE : (q_color == 2'd1) ? YELLOW : (q_color == 2'd2) ? RED : (fl ? WHITE : YELLOW);
    else if (stamp_px)
        rgb <= RED;
    else if (q_fw && fq != 2'd0)
        rgb <= (fq == 2'd1) ? WHITE : (fq == 2'd2) ? YELLOW : RED;
    else
        rgb <= BLACK;
end

// ------------------------------------------------------------------ disegnatore dei fuochi

localparam [2:0] D_IDLE = 3'd0, D_CLEAR = 3'd1, D_FW = 3'd2, D_I0 = 3'd3, D_I1 = 3'd4, D_I2 = 3'd5,
                 D_DOT0 = 3'd6, D_DOT1 = 3'd7;
reg  [2:0]  dstate = D_IDLE;
reg  [12:0] faddr = 13'd0;
reg  [15:0] fdata = 16'd0;
reg  [14:0] clr = 15'd0;            // cancellazione: cella della pagina nascosta
reg  [3:0]  fi = 4'd0;               // fuoco in corso
reg  [6:0]  pn = 7'd0;
reg  [7:0]  dleft = 8'd0;            // punti rimasti
reg  [7:0]  fcx = 8'd0;
reg  [6:0]  fcy = 7'd0;
reg         we = 1'b0;
reg  [15:0] waddr = 16'd0;
reg  [1:0]  wdata = 2'd0;
wire [7:0]  age = {1'b0, pn} - {1'b0, fw_start(fi)};
// punto: cella dello scoppio più lo scostamento (dx 6 bit e dy 8 bit con segno)
wire signed [9:0] px = $signed({2'b0, fcx}) + $signed({{4{fdata[5]}}, fdata[5:0]});
wire signed [9:0] py = $signed({3'b0, fcy}) + $signed({{2{fdata[13]}}, fdata[13:6]});
wire [15:0] back = front ? 16'd0 : FB_CELLS;

always @(posedge clk) begin
    fdata <= from[faddr];
    if (we) fb[waddr] <= wdata;
end

always @(posedge clk) begin
    we <= 1'b0;
    case (dstate)
        D_IDLE: if (plot_go) begin
            pn <= plot_n;
            clr <= 15'd0;
            dstate <= D_CLEAR;
        end
        // pagina nascosta tutta nera
        D_CLEAR: begin
            we <= 1'b1;
            waddr <= back + {1'b0, clr};
            wdata <= 2'd0;
            clr <= clr + 15'd1;
            if (clr == FB_CELLS - 1) begin
                fi <= 4'd0;
                dstate <= D_FW;
            end
        end
        // fuoco fi: se è in cielo, inizio e numero dei punti del suo frame dall'indice
        D_FW: begin
            if (fi == END_FWS) dstate <= D_IDLE;
            else if (!age[7] && age < END_FW_STRIDE) begin
                faddr <= {{1'b0, fi, 6'd0} + {3'd0, fi, 4'd0} + {4'd0, age}, 1'b0};   // (fi * 80 + age) * 2
                fcx <= fw_cx(fi);
                fcy <= fw_cy(fi);
                dstate <= D_I0;
            end else
                fi <= fi + 4'd1;
        end
        D_I0: begin faddr <= faddr + 13'd1; dstate <= D_I1; end
        D_I1: begin faddr <= fdata[12:0]; dstate <= D_I2; end        // inizio dei punti
        D_I2: begin
            dleft <= fdata[7:0];
            if (fdata[7:0] == 8'd0) begin
                fi <= fi + 4'd1;
                dstate <= D_FW;
            end else
                dstate <= D_DOT0;
        end
        D_DOT0: dstate <= D_DOT1;                                       // il punto arriva dalla ROM
        D_DOT1: begin
            if (px >= 0 && px < 160 && py >= 0 && py < 120) begin
                we <= 1'b1;
                waddr <= back + {py[6:0], 7'd0} + {2'd0, py[6:0], 5'd0} + {8'd0, px[7:0]};
                wdata <= fdata[15:14];
            end
            faddr <= faddr + 13'd1;
            dleft <= dleft - 8'd1;
            if (dleft == 8'd1) begin
                fi <= fi + 4'd1;
                dstate <= D_FW;
            end else
                dstate <= D_DOT0;
        end
        default: dstate <= D_IDLE;
    endcase
end

endmodule
