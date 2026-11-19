// Finale della CHALLENGE, quando si batte l'ultimo avversario (come rust/game/src/ending_ui.rs, su uno
// schermo 320x240), al posto della schermata CHAMPION e prima delle iniziali. Sei parti in sequenza:
// 0 CONGRATULATIONS! (lampeggia) e, dopo un secondo, YOU WIN! (la voce la fa partire pong_top);
// 1 la sfilata degli avversari (i sette della scala, poi OMEGA), uno al secondo, con il timbro DEFEATED
// mezzo secondo dopo (OMEGA non battuto arriva in sagoma, senza timbro);
// 2 il punteggio: SCORE che sale in 3 s, CHAMPION BONUS in 1 s, poi TOTAL;
// 3 YOU ARE THE PADD WS CHAMPION con i fuochi d'artificio;
// 4 i titoli di coda, che salgono dal basso; 5 THE END (lampeggia).
//
// Qui restano i tempi (parti, battute della sfilata, conteggi, scorrimento dei titoli: pong_top ne usa
// gli impulsi per voce, suoni e cambio di modo) e i fuochi d'artificio; scritte, cifre, ritratti e
// timbri della sfilata le disegna lo schermo a oggetti (rust/mister-ui, ending.rs) dallo stato `st_*`.
//
// Fuochi d'artificio (tools/gen_ending_assets.py, ending_fw.hex): i punti di ending_ui.rs per ogni fuoco
// e frame a 15 Hz, già sulla griglia di celle 2x2 pixel. Un disegnatore li scrive in un framebuffer
// 160x120 a 2 bit con due pagine: a ogni frame dei fuochi (4 frame video) cancella la pagina nascosta e
// la ridisegna (circa 21.000 cicli), poi le pagine si scambiano all'inizio del vblank. L'uscita (due
// cicli di ritardo, un pixel dura 3 cicli) è il colore dei fuochi o il nero.

`timescale 1ns / 1ps

module ending_render #(
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
    input  wire        omega,          // OMEGA battuto: anche lui ha il timbro nella sfilata
    output reg  [23:0] rgb,            // fuochi d'artificio (o nero)
    output reg         say,            // impulso: la voce "YOU WIN!"
    output reg  [1:0]  beat,           // impulso della sfilata: bit 0 entra un avversario, bit 1 un timbro
    output wire        skip_ok,        // Start può saltare il finale
    output reg         done,           // impulso: finale concluso
    // stato per lo schermo a oggetti: parte, frame della parte, battute, scritte a comparsa, lampeggio,
    // SCORE e premio che salgono, scorrimento dei titoli
    output wire [31:0] st_seq,
    output wire [23:0] st_score,
    output wire [23:0] st_bonus,
    output wire [9:0]  st_scroll
);

`include "pong_ending.vh"

localparam [23:0] BLACK = 24'h000000, WHITE = 24'hFFFFFF, YELLOW = 24'hFFD225, RED = 24'hE62828;
localparam [2:0]  P_CONGRATS = 3'd0, P_PARADE = 3'd1, P_SCORE = 3'd2, P_CHAMPION = 3'd3, P_CREDITS = 3'd4,
                  P_THE_END = 3'd5;
localparam integer FB_CELLS = 160 * 120;             // una pagina del framebuffer

// ------------------------------------------------------------------ parti e tempi (una volta per frame)

reg  [2:0]  part = P_CONGRATS;
reg  [10:0] pf = 11'd0;              // frame dall'inizio della parte
reg  [1:0]  stage = 2'd0;            // scritte a comparsa visibili (gruppo <= stage)
reg  [5:0]  fl_cnt = 6'd0;           // lampeggio: frame nella fase, fase (0 giallo, 1 bianco)
reg         fl = 1'b0;
reg  [4:0]  beat_sub = 5'd0;         // sfilata: frame nella battuta e battute (avversari + timbri)
reg  [4:0]  beats = 5'd0;
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
        beats <= 5'd0;
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
        // sfilata: una battuta ogni mezzo secondo, dispari = entra un avversario, pari = il suo timbro;
        // otto avversari, l'ultimo (OMEGA) senza timbro se non è stato battuto
        if (part_n == P_PARADE) begin
            if (pf_n == 11'd0) begin
                beat_sub <= 5'd0;
                beats <= 5'd1;
                beat <= 2'b01;
            end else if (beat_sub == END_BEAT - 1) begin
                beat_sub <= 5'd0;
                if (beats != (omega ? 5'd16 : 5'd15)) begin
                    beats <= beats + 5'd1;
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

assign st_seq = {10'd0, fl, stage, beats, part, pf};
assign st_score = disp_s;
assign st_bonus = disp_b;
assign st_scroll = scroll;

// ------------------------------------------------------------------ fuochi a schermo

reg [15:0] from [0:END_FW_SIZE-1];
initial $readmemh(FW_ROM, from);
// framebuffer dei fuochi: due pagine da 160x120 celle, 0 niente, 1 bianco, 2 giallo, 3 rosso
reg [1:0]  fb [0:2*FB_CELLS-1];

wire [8:0] x = hc;
wire [8:0] y = vc;
// la pagina mostrata, cella (x / 2, y / 2)
wire [15:0] fa = (front ? FB_CELLS : 0) + {y[8:1], 7'd0} + {2'd0, y[8:1], 5'd0} + {8'd0, x[8:1]};
reg  [1:0]  fq = 2'd0;
reg         q_fw = 1'b0;
always @(posedge clk) begin
    fq <= fb[fa];
    q_fw <= active && part == P_CHAMPION && x < 9'd320 && y < 9'd240;
end
always @(posedge clk)
    rgb <= (q_fw && fq != 2'd0) ? ((fq == 2'd1) ? WHITE : (fq == 2'd2) ? YELLOW : RED) : BLACK;

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
