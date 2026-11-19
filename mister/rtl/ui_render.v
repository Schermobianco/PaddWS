// Schermo a oggetti del core MiSTer: un solo motore che disegna le schermate e le scritte preparate
// dal firmware RISC-V (rust/mister-ui), come gli sprite dei cabinati.
//
// Il firmware scrive, per ogni frame, una lista di al più 128 oggetti, una RAM di caratteri e una
// tabella delle righe nel banco nascosto, poi chiede lo scambio: il motore scambia i banchi all'inizio
// della riga 261, prima di disegnare la riga 0, e solo se il firmware ha finito (niente strappi).
// Il motore gira a 60 MHz (`clk_cpu`): durante la riga L-1 pulisce e disegna la riga L in un line
// buffer, un pixel per ciclo (circa 3.800 cicli per riga, più di dieci volte lo schermo), nell'ordine
// della lista: l'ultimo oggetto sta sopra. La parte video (20 MHz) legge il pixel al ciclo del
// `ce_pix` (quello dopo: hc + 1) e la tavolozza al ciclo dopo, nei tre cicli del pixel come i renderer
// di prima.
//
// Oggetto, 8 parole (rust/mister-ui/src/dl.rs scrive lo stesso formato):
//   w0  [8:0] prima riga visibile, [17:9] riga dopo l'ultima (già ritagliate dal firmware)
//   w1  [10:0] x0 e [21:11] y0 con segno (angolo del rettangolo), [31:22] larghezza w
//   w2  [9:0] altezza h, [10] specchio x, [11] specchio y, [12] scambio x/y, [14:13] e [16:15]
//       ingrandimento (scorrimento) in x e in y, [17] tabella delle righe, [18] fondo opaco,
//       [20:19] tipo (0 rettangolo, 1 caratteri, 2 immagine), [22:21] classe di priorità, [23] la
//       tabella delle righe dà la riga della sorgente (immagine: parola dalla base) invece dello
//       scostamento in x
//   w3  [8:0] e [17:9] colonne del ritaglio [cx0, cx1)
//   w4  base della sorgente (caratteri: indice nel banco; immagine: parola della ROM grafica),
//       [19:16] passo delle righe (scorrimento: caratteri per riga, parole per riga), [21:20] bit per
//       pixel dell'immagine (scorrimento: 1, 2, 4, 8)
//   w5  [9:0] u0 e [19:10] v0: origine nella sorgente (pixel)
//   w6  [7:0] colore A (rettangolo; immagine a 1 bit; base della tavolozza delle altre immagini),
//       [15:8] colore B (fondo opaco)
//   w7  [8:0] prima voce della tabella delle righe per la riga j = y - y0: scostamento in x con segno
//       (10 bit) o, con w2[23], la riga della sorgente (16 bit, in parole dalla base: le scritte di
//       HOW TO PLAY e del finale, righe di 320 pixel una dopo l'altra)
// Pixel (i, j) del rettangolo, con gli specchi in i' e j': (a, b) = (i' >> sx, j' >> sy), poi
// (u, v) = scambio ? (b, a) : (a, b), più l'origine. Colore 0 = trasparente.
//
// Registri del firmware (indirizzi in parole, scritture): 0x000 oggetti, 0x400 caratteri ([7:0]
// codice del font, [15:8] colore), 0x800 tabella delle righe (16 bit), 0xA00 tavolozza (24 bit),
// 0xB00 fine del frame ([7:0] numero di oggetti, [8] scambio), 0xC00-0xDFF immagine scrivibile
// (GRAM_WORDS parole, per gli oscilloscopi del JUKEBOX: un'immagine con la base da 0xC000 la legge
// qui invece che nella ROM grafica; non ha due banchi, il firmware la riscrive nel vblank). Lettura di
// stato: [0] banco mostrato, [1] scambio in attesa.

`timescale 1ns / 1ps

module ui_render #(
    parameter FONT_ROM = "rtl/gen/ui_font.hex",
    parameter GFX_ROM = "rtl/gen/ui_gfx.hex",
    parameter GFX_ROM2 = "rtl/gen/ui_gfx2.hex"
) (
    input  wire        clk,            // 20 MHz: video
    input  wire        clk_cpu,        // 60 MHz dalla stessa PLL: firmware e motore
    input  wire        clear,          // il firmware riparte (reset dell'OSD): niente oggetti finché non
                                       // ne prepara di nuovi, invece di un frame vecchio
    input  wire        ce_pix,
    input  wire [8:0]  hc,
    input  wire [8:0]  vc,
    // scritture del firmware (dominio di clk_cpu)
    input  wire        cpu_wr,
    input  wire [13:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    output wire [31:0] status,
    // pixel (dominio di clk): indice del colore (0 = niente), classe, colore vero (un ciclo dopo)
    output wire [7:0]  px_idx,
    output wire [1:0]  px_class,
    output reg  [23:0] px_rgb
);

`include "ui_gfx.vh"

// ------------------------------------------------------------------ memorie

reg [31:0] obj_ram  [0:2047];      // {banco, oggetto, parola}
reg [15:0] tile_ram [0:2047];      // {banco, indice}
reg [15:0] lt_ram   [0:1023];      // {banco, voce}
reg [23:0] pal_ram  [0:255];
reg [7:0]  font_rom [0:2047];      // {codice, riga}
// ROM grafica in due memorie (tools/gen_mister_ui.py): con una sola oltre l'indirizzo a 15 bit
// Quartus metteva in logica le RAM del framework
reg [31:0] gfx_rom  [0:UI_GFX1_WORDS-1];
reg [31:0] gfx_rom2 [0:UI_GFX2_WORDS-1];
reg [9:0]  lb       [0:1023];      // line buffer: {riga pari/dispari, x} -> {classe, colore}
localparam integer GRAM_WORDS = 512;
reg [31:0] gram     [0:GRAM_WORDS-1];  // immagine scrivibile dal firmware (base 0xC000)
integer    n;
initial begin
    $readmemh(FONT_ROM, font_rom);
    $readmemh(GFX_ROM, gfx_rom);
    $readmemh(GFX_ROM2, gfx_rom2);
    for (n = 0; n < 1024; n = n + 1) lb[n] = 10'd0;
    for (n = 0; n < 256; n = n + 1) pal_ram[n] = 24'd0;
    for (n = 0; n < 2048; n = n + 1) obj_ram[n] = 32'd0;
    for (n = 0; n < GRAM_WORDS; n = n + 1) gram[n] = 32'd0;
end

// ------------------------------------------------------------------ firmware e banchi

reg        front = 1'b0;           // banco che il motore disegna
reg        flip_req = 1'b0;
reg [7:0]  count [0:1];            // oggetti di ogni banco
initial begin
    count[0] = 8'd0;
    count[1] = 8'd0;
end
assign status = {30'd0, flip_req, front};

always @(posedge clk_cpu) begin
    if (cpu_wr) begin
        case (cpu_addr[13:10])
            4'd0: obj_ram[{~front, cpu_addr[9:0]}] <= cpu_wdata;
            4'd1: tile_ram[{~front, cpu_addr[9:0]}] <= cpu_wdata[15:0];
            4'd2: if (!cpu_addr[9]) lt_ram[{~front, cpu_addr[8:0]}] <= cpu_wdata[15:0];
                  else if (cpu_addr[9:8] == 2'b10) pal_ram[cpu_addr[7:0]] <= cpu_wdata[23:0];
            4'd3: if (!cpu_addr[9]) gram[cpu_addr[8:0]] <= cpu_wdata;
            default: ;
        endcase
    end
end

// ------------------------------------------------------------------ inizio delle righe

// dominio di clk: all'inizio di ogni riga si chiede di disegnare la successiva
reg        go_tog = 1'b0;
reg [8:0]  go_line = 9'd0;
always @(posedge clk) begin
    if (ce_pix && hc == 9'd0) begin
        go_tog <= ~go_tog;
        go_line <= (vc == 9'd261) ? 9'd0 : vc + 9'd1;
    end
end

// ------------------------------------------------------------------ motore (clk_cpu)

localparam [3:0] S_IDLE = 4'd0, S_CLEAR = 4'd1, S_SCAN = 4'd2, S_LOAD = 4'd3, S_LT = 4'd4, S_SET1 = 4'd5,
                 S_SET2 = 4'd6, S_DRAW = 4'd7, S_DRAIN = 4'd8;
reg [3:0]  st = S_IDLE;
reg        go_seen = 1'b0, go_d = 1'b0;
reg [8:0]  line = 9'd0;
reg [8:0]  cx = 9'd0;              // pulizia / pixel in corso
reg [7:0]  k = 8'd0;               // oggetto letto (scansione)
reg [7:0]  kh = 8'd0;              // oggetto trovato
reg [3:0]  wi = 4'd0;              // parola in lettura
reg [10:0] obj_a = 11'd0;
reg [31:0] obj_q;
reg [2:0]  drain = 3'd0;
reg        sv = 1'b0;              // obj_q è la parola 0 dell'oggetto k - 1

// campi dell'oggetto
reg signed [10:0] o_x0, o_y0;
reg [9:0]  o_w, o_h;
reg        o_fx, o_fy, o_swap, o_lt, o_opq, o_ltrow;
reg [1:0]  o_sx, o_sy, o_type, o_class;
reg [8:0]  o_cx0, o_cx1;
reg [15:0] o_base;
reg [3:0]  o_ssh;
reg [1:0]  o_bpp;
reg [9:0]  o_u0, o_v0;
reg [7:0]  o_ca, o_cb;
reg [8:0]  o_ltb;
reg [15:0] lt_q;
reg [15:0] rowoff;                 // riga della sorgente dalla tabella (o_ltrow)
reg [9:0]  lt_a;

// valori della riga
reg signed [11:0] xorg, xa, xb, ii;
reg [9:0]  jp, bj;                 // j' e j' >> sy
reg [9:0]  ip;                     // i' del pixel in corso
wire signed [11:0] jj = $signed({3'b0, line}) - $signed({o_y0[10], o_y0});

always @(posedge clk_cpu) obj_q <= obj_ram[obj_a];
always @(posedge clk_cpu) lt_q <= lt_ram[{front, lt_a[8:0]}];

// tubo dei pixel: P1 coordinate nella sorgente, P2 indirizzo, P3 dati, P4 colore, P5 scrittura
reg        p1_v = 1'b0, p2_v = 1'b0, p3_v = 1'b0, p4_v = 1'b0;
reg [8:0]  p1_x, p2_x, p3_x, p4_x;
reg [9:0]  p1_u, p1_v_;
reg [2:0]  p2_ulo, p2_vlo, p3_ulo;
reg [4:0]  p2_ub;                  // bit del pixel nella parola dell'immagine
reg [10:0] p2_ta;                  // indirizzo dei caratteri
reg [15:0] p2_ga;                  // indirizzo della ROM grafica
reg [15:0] tile_q;
wire [31:0] gfx_q;
reg  [31:0] gfx_q1, gfx_q2;
reg         gfx_hi;
wire [31:0] gfx_d;                 // la parola dell'immagine (ROM grafica o immagine scrivibile)
reg [4:0]  p3_ub;
reg [2:0]  p3_vlo;
reg [7:0]  p3_attr;
reg [7:0]  font_q;
reg [7:0]  p4_val;                 // valore del pixel dell'immagine
reg [2:0]  p4_ulo;
reg [7:0]  p4_attr;
reg [7:0]  p5_col;
reg        p5_v = 1'b0;
reg [8:0]  p5_x;
reg        lb_we;
reg [9:0]  lb_wa, lb_wd;

wire       ui_go = go_d != go_seen;
reg        clear_q = 1'b0;
always @(posedge clk_cpu) clear_q <= clear;

always @(posedge clk_cpu) begin
    go_d <= go_tog;
    lb_we <= 1'b0;
    // fine del frame del firmware: oggetti del banco nascosto e richiesta di scambio
    if (cpu_wr && cpu_addr == 14'h0B00) begin
        count[~front] <= cpu_wdata[7:0];
        if (cpu_wdata[8]) flip_req <= 1'b1;
    end
    if (clear_q) begin
        count[0] <= 8'd0;
        count[1] <= 8'd0;
        flip_req <= 1'b0;
    end
    if (ui_go) begin
        // nuova riga: si ricomincia anche se la precedente non era finita (non deve succedere)
        go_seen <= go_d;
        line <= go_line;
        if (go_line == 9'd0 && flip_req) begin
            front <= ~front;
            flip_req <= 1'b0;
        end
        cx <= 9'd0;
        st <= (go_line < 9'd240) ? S_CLEAR : S_IDLE;
    end else begin
        case (st)
            S_CLEAR: begin
                lb_we <= 1'b1;
                lb_wa <= {line[0], cx};
                lb_wd <= 10'd0;
                cx <= cx + 9'd1;
                if (cx == 9'd319) begin
                    st <= S_SCAN;
                    k <= 8'd0;
                    sv <= 1'b0;
                    obj_a <= {front, 7'd0, 3'd0};
                end
            end
            S_SCAN: begin
                // un oggetto per ciclo: con sv, obj_q è la parola 0 dell'oggetto k - 1
                sv <= 1'b1;
                if (sv && obj_q[8:0] <= line && line < obj_q[17:9]) begin
                    kh <= k - 8'd1;
                    st <= S_LOAD;
                    wi <= 4'd1;
                    obj_a <= {front, k[6:0] - 7'd1, 3'd1};
                end else if (k >= count[front]) begin
                    st <= S_IDLE;
                end else begin
                    k <= k + 8'd1;
                    obj_a <= {front, k[6:0] + 7'd1, 3'd0};
                end
            end
            S_LOAD: begin
                // parole 1..7: obj_q arriva un ciclo dopo l'indirizzo
                obj_a <= {front, kh[6:0], wi[2:0] + 3'd1};
                wi <= wi + 4'd1;
                case (wi)
                    4'd2: begin o_x0 <= obj_q[10:0]; o_y0 <= obj_q[21:11]; o_w <= obj_q[31:22]; end
                    4'd3: begin
                        o_h <= obj_q[9:0]; o_fx <= obj_q[10]; o_fy <= obj_q[11]; o_swap <= obj_q[12];
                        o_sx <= obj_q[14:13]; o_sy <= obj_q[16:15]; o_lt <= obj_q[17]; o_opq <= obj_q[18];
                        o_type <= obj_q[20:19]; o_class <= obj_q[22:21]; o_ltrow <= obj_q[23];
                    end
                    4'd4: begin o_cx0 <= obj_q[8:0]; o_cx1 <= obj_q[17:9]; end
                    4'd5: begin o_base <= obj_q[15:0]; o_ssh <= obj_q[19:16]; o_bpp <= obj_q[21:20]; end
                    4'd6: begin o_u0 <= obj_q[9:0]; o_v0 <= obj_q[19:10]; end
                    4'd7: begin o_ca <= obj_q[7:0]; o_cb <= obj_q[15:8]; end
                    4'd8: begin o_ltb <= obj_q[8:0]; st <= S_LT; end
                    default: ;
                endcase
            end
            S_LT: begin
                lt_a <= {1'b0, o_ltb} + jj[9:0];
                st <= S_SET1;
                wi <= 4'd0;
            end
            S_SET1: begin
                // il dato della tabella arriva due cicli dopo lt_a
                wi <= wi + 4'd1;
                if (wi == 4'd1) begin
                    xorg <= $signed({o_x0[10], o_x0}) + ((o_lt && !o_ltrow) ? $signed({{2{lt_q[9]}}, lt_q[9:0]}) : 12'sd0);
                    rowoff <= (o_lt && o_ltrow) ? lt_q : 16'd0;
                    jp <= o_fy ? o_h - 10'd1 - jj[9:0] : jj[9:0];
                    st <= S_SET2;
                end
            end
            S_SET2: begin
                xa = (xorg > $signed({3'b0, o_cx0})) ? xorg : $signed({3'b0, o_cx0});
                xb = xorg + $signed({2'b0, o_w});
                if (xb > $signed({3'b0, o_cx1})) xb = $signed({3'b0, o_cx1});
                if (xb > 12'sd320) xb = 12'sd320;
                bj <= jp >> o_sy;
                ii = xa - xorg;
                ip <= o_fx ? o_w - 10'd1 - ii[9:0] : ii[9:0];
                cx <= xa[8:0];
                if (xa >= xb || xa < 0) begin
                    st <= S_SCAN;
                    k <= kh + 8'd1;
                    sv <= 1'b0;
                    obj_a <= {front, kh[6:0] + 7'd1, 3'd0};
                end else
                    st <= S_DRAW;
            end
            S_DRAW: begin
                cx <= cx + 9'd1;
                ip <= o_fx ? ip - 10'd1 : ip + 10'd1;
                if ($signed({3'b0, cx}) + 12'sd1 >= xb) begin
                    st <= S_DRAIN;
                    drain <= 3'd0;
                end
            end
            S_DRAIN: begin
                drain <= drain + 3'd1;
                if (drain == 3'd5) begin
                    st <= S_SCAN;
                    k <= kh + 8'd1;
                    sv <= 1'b0;
                    obj_a <= {front, kh[6:0] + 7'd1, 3'd0};
                end
            end
            default: ;
        endcase
    end

    // ---- tubo dei pixel
    // P1: coordinate nella sorgente
    p1_v <= st == S_DRAW && !ui_go;
    p1_x <= cx;
    p1_u <= (o_swap ? bj : (ip >> o_sx)) + o_u0;
    p1_v_ <= (o_swap ? (ip >> o_sx) : bj) + o_v0;
    // P2: indirizzi
    p2_v <= p1_v;
    p2_x <= p1_x;
    p2_ulo <= p1_u[2:0];
    p2_vlo <= p1_v_[2:0];
    p2_ta <= o_base[10:0] + ({1'b0, p1_v_[9:3]} << o_ssh) + {4'd0, p1_u[9:3]};
    p2_ga <= o_base + (o_ltrow ? rowoff : ({6'd0, p1_v_} << o_ssh)) + ({6'd0, p1_u} >> (3'd5 - {1'b0, o_bpp}));
    p2_ub <= p1_u[4:0] << o_bpp;
    // P3: dati di caratteri e grafica
    p3_v <= p2_v;
    p3_x <= p2_x;
    p3_ulo <= p2_ulo;
    p3_vlo <= p2_vlo;
    p3_ub <= p2_ub;
    // P4: glifo del font e valore del pixel dell'immagine
    p4_v <= p3_v;
    p4_x <= p3_x;
    p4_ulo <= p3_ulo;
    p4_attr <= tile_q[15:8];
    case (o_bpp)
        2'd0: p4_val <= {7'd0, gfx_d[5'd31 - p3_ub]};
        2'd1: p4_val <= {6'd0, gfx_d[5'd30 - p3_ub +: 2]};
        2'd2: p4_val <= {4'd0, gfx_d[5'd28 - p3_ub +: 4]};
        default: p4_val <= gfx_d[5'd24 - p3_ub +: 8];
    endcase
    // P5: colore
    p5_v <= p4_v;
    p5_x <= p4_x;
    case (o_type)
        2'd0: p5_col <= o_ca;
        2'd1: p5_col <= font_q[3'd7 - p4_ulo] ? p4_attr : (o_opq ? o_cb : 8'd0);
        default: p5_col <= (p4_val == 8'd0) ? (o_opq ? o_cb : 8'd0) : (o_bpp == 2'd0) ? o_ca : o_ca + p4_val;
    endcase
    // scrittura nel line buffer (la pulizia scrive qui sopra)
    if (p5_v && p5_col != 8'd0 && st != S_CLEAR) begin
        lb_we <= 1'b1;
        lb_wa <= {line[0], p5_x};
        lb_wd <= {o_class, p5_col};
    end
end

always @(posedge clk_cpu) tile_q <= tile_ram[{front, p2_ta[9:0]}];
always @(posedge clk_cpu) begin
    gfx_q1 <= gfx_rom[p2_ga[14:0]];
    gfx_q2 <= gfx_rom2[p2_ga[UI_GFX2_AW-1:0]];
    gfx_hi <= UI_GFX_AW > 15 && p2_ga[15];
end
assign gfx_q = gfx_hi ? gfx_q2 : gfx_q1;
// immagine scrivibile: base da 0xC000
reg [31:0] gram_q;
reg        gram_sel = 1'b0;
always @(posedge clk_cpu) begin
    gram_q <= gram[p2_ga[8:0]];
    gram_sel <= p2_ga[15:14] == 2'b11;
end
assign gfx_d = gram_sel ? gram_q : gfx_q;
always @(posedge clk_cpu) font_q <= font_rom[{tile_q[7:0], p3_vlo}];
always @(posedge clk_cpu) if (lb_we) lb[lb_wa] <= lb_wd;

// ------------------------------------------------------------------ video (clk)

// pixel dopo quello in corso (all'ultimo della riga: il primo della riga dopo, nell'altra metà)
wire [8:0] xn = (hc == 9'd423) ? 9'd0 : hc + 9'd1;
wire       lsel = (hc == 9'd423) ? ~vc[0] : vc[0];
reg  [9:0] lb_q = 10'd0;
reg        lb_ok = 1'b0;
always @(posedge clk) begin
    if (ce_pix) begin
        lb_q <= lb[{lsel, xn}];
        lb_ok <= xn < 9'd320;
    end
end
assign px_idx = lb_ok ? lb_q[7:0] : 8'd0;
assign px_class = lb_q[9:8];
always @(posedge clk) px_rgb <= pal_ram[px_idx];

endmodule
