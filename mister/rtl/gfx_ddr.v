// Grafica nella DDR3: i ritratti grandi e medi e le astronavi (tools/gen_mister_ui.py, file
// paddws_gfx.rom) non stanno nelle M10K ma nella DDR3 della DE10-Nano.
//
// Caricamento: il .mra fa caricare il file all'avvio del core (ioctl, indice 0): i byte arrivano nel
// dominio di clk_sys, uno per impulso di ioctl_wr; ogni 8 byte (una parola a 64 bit) si scrive nella
// DDR3, e intanto ioctl_wait ferma il prossimo byte. Finito il caricamento `gfx_ok` resta alto.
//
// Copia (DMA): il firmware delle schermate (rust/mister-ui, `Win`) scrive nei registri a 0xE00 dello
// schermo a oggetti la sorgente (parola a 32 bit nel file), la destinazione (parola nella finestra
// di ui_render) e il numero di parole, che fa partire la copia; `dma_busy` resta alto finché non è
// finita. Le parole a 32 bit del file sono in coppie nelle parole a 64 bit della DDR3 (la prima nei
// bit bassi): da una lettura si scrivono nella finestra una o due parole.
//
// Tutto nel dominio di clk_cpu (60 MHz), come la finestra e il firmware; DDRAM_CLK = clk_cpu. Il file
// sta da 0x3000_0000 (l'inizio della DDR3 riservata ai core).

`timescale 1ns / 1ps

module gfx_ddr (
    input  wire        clk_sys,
    input  wire        clk_cpu,
    input  wire        reset,             // (clk_cpu) ferma la copia; il caricamento e gfx_ok restano

    // caricamento dalla SD (dominio di clk_sys, da hps_io)
    input  wire        ioctl_download,
    input  wire [15:0] ioctl_index,
    input  wire        ioctl_wr,
    input  wire [26:0] ioctl_addr,
    input  wire [7:0]  ioctl_dout,
    output reg         ioctl_wait = 1'b0,

    // registri del firmware (come cpu_wr di ui_render)
    input  wire        cpu_wr,
    input  wire [13:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    output wire        dma_busy,
    output reg         gfx_ok = 1'b0,

    // scrittura nella finestra di ui_render
    output reg         win_we = 1'b0,
    output reg  [12:0] win_addr = 13'd0,
    output reg  [31:0] win_data = 32'd0,

    // DDR3 (Avalon, parole a 64 bit)
    input  wire        DDRAM_BUSY,
    output wire [7:0]  DDRAM_BURSTCNT,
    output reg  [28:0] DDRAM_ADDR = 29'd0,
    input  wire [63:0] DDRAM_DOUT,
    input  wire        DDRAM_DOUT_READY,
    output reg         DDRAM_RD = 1'b0,
    output reg  [63:0] DDRAM_DIN = 64'd0,
    output wire [7:0]  DDRAM_BE,
    output reg         DDRAM_WE = 1'b0
);

localparam [28:0] BASE = 29'h0600_0000;   // 0x3000_0000 / 8
localparam [7:0]  INDEX = 8'd0;           // indice del file nel .mra

assign DDRAM_BURSTCNT = 8'd1;
assign DDRAM_BE = 8'hFF;

// ------------------------------------------------------------------ caricamento

// ioctl_wr dura un ciclo di clk_sys (tre di clk_cpu, stesso PLL): il fronte di salita, campionato in
// clk_cpu, prende il byte una volta sola; ioctl_addr e ioctl_dout restano fermi fino al byte dopo
reg        wr_q1 = 1'b0, wr_q2 = 1'b0, dl_q1 = 1'b0, dl_q2 = 1'b0;
reg [63:0] buf64 = 64'd0;
reg        wr_pend = 1'b0;                // parola a 64 bit da scrivere
reg [23:0] wr_word = 24'd0;
reg        loaded_any = 1'b0;
wire       mine = ioctl_index[7:0] == INDEX;

always @(posedge clk_cpu) begin
    wr_q1 <= ioctl_wr;
    wr_q2 <= wr_q1;
    dl_q1 <= ioctl_download && mine;
    dl_q2 <= dl_q1;
    if (wr_q1 && !wr_q2 && dl_q1) begin
        buf64[{ioctl_addr[2:0], 3'd0} +: 8] <= ioctl_dout;
        loaded_any <= 1'b1;
        if (ioctl_addr[2:0] == 3'd7) begin
            wr_pend <= 1'b1;
            wr_word <= ioctl_addr[26:3];
        end
    end
    // fine del caricamento: la grafica c'è
    if (dl_q2 && !dl_q1 && loaded_any) gfx_ok <= 1'b1;
    if (wr_done) wr_pend <= 1'b0;
end

// ioctl_wait nel dominio di clk_sys (clock legati): fermo finché la parola non è scritta
always @(posedge clk_sys) ioctl_wait <= wr_pend;

// ------------------------------------------------------------------ copia e accesso alla DDR3

reg [19:0] src = 20'd0;                   // parola a 32 bit nel file
reg [12:0] dst = 13'd0;                   // parola nella finestra
reg [13:0] cnt = 14'd0;                   // parole che restano
reg [63:0] beat = 64'd0;

localparam [2:0] S_IDLE = 3'd0, S_WRITE = 3'd1, S_READ = 3'd2, S_WAIT = 3'd3, S_LO = 3'd4, S_HI = 3'd5;
reg [2:0] state = S_IDLE;
reg       wr_done = 1'b0;

assign dma_busy = state != S_IDLE || cnt != 14'd0;

always @(posedge clk_cpu) begin
    win_we <= 1'b0;
    wr_done <= 1'b0;
    if (cpu_wr && cpu_addr[13:10] == 4'd3 && cpu_addr[9]) begin
        case (cpu_addr[1:0])
            2'd0: src <= cpu_wdata[19:0];
            2'd1: dst <= cpu_wdata[12:0];
            2'd2: cnt <= cpu_wdata[13:0];   // parte la copia
            default: ;
        endcase
    end
    if (reset) begin
        state <= S_IDLE;
        cnt <= 14'd0;
        DDRAM_RD <= 1'b0;
        DDRAM_WE <= 1'b0;
    end else case (state)
        S_IDLE: begin
            if (wr_pend && !wr_done) begin
                // caricamento: una parola a 64 bit
                DDRAM_ADDR <= BASE + {5'd0, wr_word};
                DDRAM_DIN <= buf64;
                DDRAM_WE <= 1'b1;
                state <= S_WRITE;
            end else if (cnt != 14'd0 && gfx_ok) begin
                DDRAM_ADDR <= BASE + {10'd0, src[19:1]};
                DDRAM_RD <= 1'b1;
                state <= S_READ;
            end
        end
        S_WRITE: if (!DDRAM_BUSY) begin
            DDRAM_WE <= 1'b0;
            wr_done <= 1'b1;
            state <= S_IDLE;
        end
        S_READ: if (!DDRAM_BUSY) begin
            DDRAM_RD <= 1'b0;
            state <= S_WAIT;
        end
        S_WAIT: if (DDRAM_DOUT_READY) begin
            beat <= DDRAM_DOUT;
            state <= src[0] ? S_HI : S_LO;
        end
        S_LO: begin
            win_we <= 1'b1;
            win_addr <= dst;
            win_data <= beat[31:0];
            src <= src + 20'd1;
            dst <= dst + 13'd1;
            cnt <= cnt - 14'd1;
            state <= (cnt == 14'd1) ? S_IDLE : S_HI;
        end
        S_HI: begin
            win_we <= 1'b1;
            win_addr <= dst;
            win_data <= beat[63:32];
            src <= src + 20'd1;
            dst <= dst + 13'd1;
            cnt <= cnt - 14'd1;
            state <= S_IDLE;
        end
        default: state <= S_IDLE;
    endcase
end

endmodule
