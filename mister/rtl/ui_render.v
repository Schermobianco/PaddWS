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
// Griglia in prospettiva (schermate prima della partita): con [9] di 0xB00 acceso il pixel che nessun
// oggetto copre (colore 0) è, dove la regola `grid_cell` lo dice, una riga di muro o di pavimento, che
// dove passa un impulso di luce va dal suo grigio al colore dello sfidante (scritto a 0xB05, 24 bit RGB:
// l'indice 255 e il colore dalla logica, senza tavolozza). Gli impulsi (3 insieme) partono a ogni
// secondo colpo del basso della musica (`bass_note`) o, senza musica, ogni GRID_IDLE frame. Stessa
// regola di rust/game/src/grid.rs (`cell` e `blend`), pixel per pixel.
//
// Registri del firmware (indirizzi in parole, scritture): 0x000 oggetti, 0x400 caratteri ([7:0]
// codice del font, [15:8] colore), 0x800 tabella delle righe (16 bit), 0xA00 tavolozza (24 bit),
// 0xB00 fine del frame ([7:0] numero di oggetti, [8] scambio, [9] griglia), 0xC00-0xDFF immagine scrivibile
// (GRAM_WORDS parole, per gli oscilloscopi del JUKEBOX: un'immagine con la base da 0xC000 la legge
// qui invece che nella ROM grafica; non ha due banchi, il firmware la riscrive nel vblank), 0xE00-0xE02
// registri della copia dalla DDR3 (gfx_ddr: sorgente, destinazione, parole). Lettura di stato: [0]
// banco mostrato, [1] scambio in attesa (in pong_top anche [2] copia in corso, [3] grafica caricata).
// Immagini da 0x8000: la finestra della DDR3 (UI_WIN_WORDS parole, ritratti grandi e medi e
// astronavi copiati dal firmware).

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
    input  wire        bass_note,      // un ciclo di clk: parte una nota del basso (pong_sid): impulso della griglia
    // scritture del firmware (dominio di clk_cpu)
    input  wire        cpu_wr,
    input  wire [13:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    output wire [31:0] status,
    // finestra della DDR3 (dominio di clk_cpu): la scrive gfx_ddr, copiando dalla DDR3 i ritratti
    // grandi e medi e le astronavi; un'immagine con la base da UI_WIN_BASE (0x8000) la legge qui
    input  wire        win_we,
    input  wire [12:0] win_addr,
    input  wire [31:0] win_data,
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
reg        grid_b [0:1];           // griglia accesa in ogni banco
initial begin
    count[0] = 8'd0;
    count[1] = 8'd0;
    grid_b[0] = 1'b0;
    grid_b[1] = 1'b0;
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
    // colore dell'impulso della griglia
    if (cpu_wr && cpu_addr == 14'h0B05) grid_rgb <= cpu_wdata[23:0];
    // fine del frame del firmware: oggetti del banco nascosto e richiesta di scambio
    if (cpu_wr && cpu_addr == 14'h0B00) begin
        count[~front] <= cpu_wdata[7:0];
        grid_b[~front] <= cpu_wdata[9];
        if (cpu_wdata[8]) flip_req <= 1'b1;
    end
    if (clear_q) begin
        count[0] <= 8'd0;
        count[1] <= 8'd0;
        grid_b[0] <= 1'b0;
        grid_b[1] <= 1'b0;
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
// finestra della DDR3: base da UI_WIN_BASE (0x8000-0xBFFF)
reg [31:0] wram [0:UI_WIN_WORDS-1];
reg [31:0] wram_q;
reg        wram_sel = 1'b0;
always @(posedge clk_cpu) if (win_we) wram[win_addr] <= win_data;
always @(posedge clk_cpu) begin
    wram_q <= wram[p2_ga[12:0]];
    wram_sel <= p2_ga[15:14] == 2'b10;
end
assign gfx_d = gram_sel ? gram_q : wram_sel ? wram_q : gfx_q;
always @(posedge clk_cpu) font_q <= font_rom[{tile_q[7:0], p3_vlo}];
always @(posedge clk_cpu) if (lb_we) lb[lb_wa] <= lb_wd;

// ------------------------------------------------------------------ video (clk)

// pixel dopo quello in corso (all'ultimo della riga: il primo della riga dopo, nell'altra metà)
wire [8:0] xn = (hc == 9'd423) ? 9'd0 : hc + 9'd1;
wire       lsel = (hc == 9'd423) ? ~vc[0] : vc[0];
reg  [9:0] lb_q = 10'd0;
reg        lb_ok = 1'b0;
reg        grid_q = 1'b0;              // griglia accesa nel banco mostrato (clk_cpu -> clk, registro a registro)
reg [7:0]  gp0 = 8'd255, gp1 = 8'd255, gp2 = 8'd255;  // fase (frame da quando è partito) dei 3 impulsi; >= GRID_PULSE: finito
reg [1:0]  g_next = 2'd0;              // impulso che parte al prossimo
reg        g_odd = 1'b0;               // note del basso: ne parte uno ogni due
reg [7:0]  g_idle = 8'd0;              // frame dall'ultimo impulso partito
reg        bass_q = 1'b0;
reg [11:0] g_cell = 12'd0;            // pixel letto: [7:0] grigio della riga (0 se non è su una riga), [11:8] impulso 0..8
reg [23:0] grid_rgb = 24'hC0C0C0;      // colore dell'impulso (clk_cpu)
reg [23:0] grid_rgb_q = 24'hC0C0C0;    // e in clk (registro a registro)
always @(posedge clk) grid_q <= grid_b[front];

// ------------------------------------------------------------------ griglia

localparam integer GRID_PULSE = 80, GRID_IDLE = 90;
// 131072 / (y - 96) arrotondato, per la riga y = 128 + r del pavimento
function [12:0] grid_step(input [6:0] r);
    case (r)
        7'd0: grid_step = 13'd4096;
        7'd1: grid_step = 13'd3972;
        7'd2: grid_step = 13'd3855;
        7'd3: grid_step = 13'd3745;
        7'd4: grid_step = 13'd3641;
        7'd5: grid_step = 13'd3542;
        7'd6: grid_step = 13'd3449;
        7'd7: grid_step = 13'd3361;
        7'd8: grid_step = 13'd3277;
        7'd9: grid_step = 13'd3197;
        7'd10: grid_step = 13'd3121;
        7'd11: grid_step = 13'd3048;
        7'd12: grid_step = 13'd2979;
        7'd13: grid_step = 13'd2913;
        7'd14: grid_step = 13'd2849;
        7'd15: grid_step = 13'd2789;
        7'd16: grid_step = 13'd2731;
        7'd17: grid_step = 13'd2675;
        7'd18: grid_step = 13'd2621;
        7'd19: grid_step = 13'd2570;
        7'd20: grid_step = 13'd2521;
        7'd21: grid_step = 13'd2473;
        7'd22: grid_step = 13'd2427;
        7'd23: grid_step = 13'd2383;
        7'd24: grid_step = 13'd2341;
        7'd25: grid_step = 13'd2300;
        7'd26: grid_step = 13'd2260;
        7'd27: grid_step = 13'd2222;
        7'd28: grid_step = 13'd2185;
        7'd29: grid_step = 13'd2149;
        7'd30: grid_step = 13'd2114;
        7'd31: grid_step = 13'd2081;
        7'd32: grid_step = 13'd2048;
        7'd33: grid_step = 13'd2016;
        7'd34: grid_step = 13'd1986;
        7'd35: grid_step = 13'd1956;
        7'd36: grid_step = 13'd1928;
        7'd37: grid_step = 13'd1900;
        7'd38: grid_step = 13'd1872;
        7'd39: grid_step = 13'd1846;
        7'd40: grid_step = 13'd1820;
        7'd41: grid_step = 13'd1796;
        7'd42: grid_step = 13'd1771;
        7'd43: grid_step = 13'd1748;
        7'd44: grid_step = 13'd1725;
        7'd45: grid_step = 13'd1702;
        7'd46: grid_step = 13'd1680;
        7'd47: grid_step = 13'd1659;
        7'd48: grid_step = 13'd1638;
        7'd49: grid_step = 13'd1618;
        7'd50: grid_step = 13'd1598;
        7'd51: grid_step = 13'd1579;
        7'd52: grid_step = 13'd1560;
        7'd53: grid_step = 13'd1542;
        7'd54: grid_step = 13'd1524;
        7'd55: grid_step = 13'd1507;
        7'd56: grid_step = 13'd1489;
        7'd57: grid_step = 13'd1473;
        7'd58: grid_step = 13'd1456;
        7'd59: grid_step = 13'd1440;
        7'd60: grid_step = 13'd1425;
        7'd61: grid_step = 13'd1409;
        7'd62: grid_step = 13'd1394;
        7'd63: grid_step = 13'd1380;
        7'd64: grid_step = 13'd1365;
        7'd65: grid_step = 13'd1351;
        7'd66: grid_step = 13'd1337;
        7'd67: grid_step = 13'd1324;
        7'd68: grid_step = 13'd1311;
        7'd69: grid_step = 13'd1298;
        7'd70: grid_step = 13'd1285;
        7'd71: grid_step = 13'd1273;
        7'd72: grid_step = 13'd1260;
        7'd73: grid_step = 13'd1248;
        7'd74: grid_step = 13'd1237;
        7'd75: grid_step = 13'd1225;
        7'd76: grid_step = 13'd1214;
        7'd77: grid_step = 13'd1202;
        7'd78: grid_step = 13'd1192;
        7'd79: grid_step = 13'd1181;
        7'd80: grid_step = 13'd1170;
        7'd81: grid_step = 13'd1160;
        7'd82: grid_step = 13'd1150;
        7'd83: grid_step = 13'd1140;
        7'd84: grid_step = 13'd1130;
        7'd85: grid_step = 13'd1120;
        7'd86: grid_step = 13'd1111;
        7'd87: grid_step = 13'd1101;
        7'd88: grid_step = 13'd1092;
        7'd89: grid_step = 13'd1083;
        7'd90: grid_step = 13'd1074;
        7'd91: grid_step = 13'd1066;
        7'd92: grid_step = 13'd1057;
        7'd93: grid_step = 13'd1049;
        7'd94: grid_step = 13'd1040;
        7'd95: grid_step = 13'd1032;
        7'd96: grid_step = 13'd1024;
        7'd97: grid_step = 13'd1016;
        7'd98: grid_step = 13'd1008;
        7'd99: grid_step = 13'd1001;
        7'd100: grid_step = 13'd993;
        7'd101: grid_step = 13'd986;
        7'd102: grid_step = 13'd978;
        7'd103: grid_step = 13'd971;
        7'd104: grid_step = 13'd964;
        7'd105: grid_step = 13'd957;
        7'd106: grid_step = 13'd950;
        7'd107: grid_step = 13'd943;
        7'd108: grid_step = 13'd936;
        7'd109: grid_step = 13'd930;
        7'd110: grid_step = 13'd923;
        7'd111: grid_step = 13'd917;
        default: grid_step = 13'd0;
    endcase
endfunction

// pixel (gx, gy) al frame t, la stessa regola di `cell` in rust/game/src/grid.rs: {livello dell'impulso
// (8 in testa, uno in meno ogni 4 righe di coda), grigio della riga: muro 32, pavimento 80; 0 se niente}
function [3:0] grid_pulse(input [8:0] gy, input [7:0] t);
    reg signed [10:0] behind;
    begin
        behind = (gy < 9'd128) ? $signed({2'b0, gy}) + $signed({2'b0, t, 1'b0}) - 11'sd128
                               : 11'sd128 + $signed({2'b0, t, 1'b0}) - $signed({2'b0, gy});
        // distanza dalla testa (0..31 righe): 8 in testa, un livello in meno ogni 4 righe di coda
        grid_pulse = (t < GRID_PULSE && behind >= 11'sd0 && behind < 11'sd32) ? 4'd8 - {1'b0, behind[4:2]} : 4'd0;
    end
endfunction

function [11:0] grid_cell(input [8:0] gx, input [8:0] gy, input [7:0] t0, input [7:0] t1, input [7:0] t2);
    reg signed [9:0] dx;
    reg [8:0]  ax;
    reg [6:0]  r;
    reg [12:0] st;
    reg [19:0] q;
    reg        on;
    reg [3:0]  k, k1, k2;
    begin
        dx = $signed({1'b0, gx}) - 10'sd160;
        ax = dx[9] ? -dx[8:0] : dx[8:0];
        r = gy[6:0] - 7'd0;
        st = grid_step(gy[6:0]);
        q = ax * st;
        if (gy < 9'd128) begin
            on = gy[3:0] == 4'd0 || gx[3:0] == 4'd0;
        end else begin
            on = gy == 9'd128 || gy == 9'd133 || gy == 9'd139 || gy == 9'd147 || gy == 9'd160 || gy == 9'd181 ||
                 gy == 9'd224 || q[15:0] < {3'd0, st};
        end
        // il più luminoso dei tre impulsi
        k = grid_pulse(gy, t0);
        k1 = grid_pulse(gy, t1);
        k2 = grid_pulse(gy, t2);
        if (k1 > k) k = k1;
        if (k2 > k) k = k2;
        grid_cell = !on ? 12'd0 : {k, (gy < 9'd128) ? 8'd32 : 8'd80};
    end
endfunction

always @(posedge clk) begin
    if (ce_pix) begin
        lb_q <= lb[{lsel, xn}];
        lb_ok <= xn < 9'd320;
        g_cell <= grid_cell(xn, vc, gp0, gp1, gp2);
    end
end

// impulsi: un frame in più per ogni impulso in volo; ne parte uno a ogni secondo colpo del basso, o
// da solo dopo GRID_IDLE frame senza note
wire g_note = bass_note && !bass_q;
wire g_frame = ce_pix && hc == 9'd0 && vc == 9'd0;
wire g_spawn = (g_note && !g_odd) || (g_frame && g_idle >= GRID_IDLE - 1 && !g_note);
always @(posedge clk) begin
    bass_q <= bass_note;
    if (g_frame) begin
        if (gp0 < 8'd200) gp0 <= gp0 + 8'd1;
        if (gp1 < 8'd200) gp1 <= gp1 + 8'd1;
        if (gp2 < 8'd200) gp2 <= gp2 + 8'd1;
        if (g_idle != 8'd255) g_idle <= g_idle + 8'd1;
    end
    if (g_note) g_odd <= ~g_odd;
    if (g_spawn) begin
        case (g_next)
            2'd0: gp0 <= 8'd0;
            2'd1: gp1 <= 8'd0;
            default: gp2 <= 8'd0;
        endcase
        g_next <= (g_next == 2'd2) ? 2'd0 : g_next + 2'd1;
        g_idle <= 8'd0;
    end
end
wire       grid_px = grid_q && lb_ok && lb_q[7:0] == 8'd0 && g_cell[7:0] != 8'd0;

// canale del colore di una riga: dal grigio `base` al colore `c` in proporzione k / 8 (scorrimento aritmetico)
function [7:0] grid_chan(input [7:0] base, input [7:0] c, input [3:0] k);
    reg signed [13:0] m, sh;
    begin
        m = ($signed({1'b0, c}) - $signed({1'b0, base})) * $signed({1'b0, k});
        sh = m >>> 3;
        grid_chan = base + sh[7:0];
    end
endfunction
wire [23:0] grid_col = {grid_chan(g_cell[7:0], grid_rgb_q[23:16], g_cell[11:8]),
                        grid_chan(g_cell[7:0], grid_rgb_q[15:8], g_cell[11:8]),
                        grid_chan(g_cell[7:0], grid_rgb_q[7:0], g_cell[11:8])};
assign px_idx = grid_px ? 8'd255 : lb_ok ? lb_q[7:0] : 8'd0;
assign px_class = lb_q[9:8];
always @(posedge clk) begin
    grid_rgb_q <= grid_rgb;
    px_rgb <= grid_px ? grid_col : pal_ram[px_idx];
end

endmodule
