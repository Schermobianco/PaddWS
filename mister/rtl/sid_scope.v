// Oscilloscopi delle tre voci del SID per il firmware (rete di OMEGA e JUKEBOX, come
// rust/game/src/scope.rs): l'uscita di ogni voce (pong_sid, `scope`) si somma per 1024 campioni a
// 1 MHz (1,024 ms, la media di `smooth` sulla rete) e la media va in un anello di 256 posti per voce
// (262 ms: la finestra di 120 ms più i 50 ms della ricerca dell'aggancio); nello stesso posto di un
// secondo anello il campione dell'ultimo microsecondo, senza media (gli oscilloscopi del JUKEBOX, come
// `trace`, che non ammorbidisce: il rumore della batteria si vede). `wptr` è il prossimo posto da
// scrivere: il firmware lo legge nella foto dello stato e va indietro da lì.
//
// Lettura dal processore (clk_cpu), sincrona come la sua RAM: indirizzo {campione, voce, posto} (11
// bit: 0 la media, 1 il campione), il dato il ciclo dopo, con il segno esteso a 32 bit.

`timescale 1ns / 1ps

module sid_scope (
    input  wire        clk,            // 20 MHz
    input  wire [47:0] scope,          // {voce 3, voce 2, voce 1}, 16 bit con segno
    output reg  [7:0]  wptr = 8'd0,
    input  wire        clk_cpu,
    input  wire [10:0] raddr,
    output wire [31:0] rdata
);

localparam integer DIV = 20;           // cicli di clk per campione (1 MHz)

reg [4:0]  div = 5'd0;
reg [9:0]  n = 10'd0;
reg signed [25:0] acc [0:2];
reg signed [15:0] avg [0:2];
reg signed [15:0] inst [0:2];
reg [2:0]  wr_v = 3'd7;                // da scrivere: media delle voci 0-2, campione delle voci 4-6 (7 = niente)
reg [15:0] mem [0:2047];
integer    i;
initial begin
    for (i = 0; i < 3; i = i + 1) begin
        acc[i] = 26'sd0;
        avg[i] = 16'sd0;
        inst[i] = 16'sd0;
    end
    for (i = 0; i < 2048; i = i + 1) mem[i] = 16'd0;
end

always @(posedge clk) begin
    div <= (div == DIV - 1) ? 5'd0 : div + 5'd1;
    if (div == 5'd0) begin
        n <= n + 10'd1;
        for (i = 0; i < 3; i = i + 1)
            if (n == 10'd1023) begin
                avg[i] <= (acc[i] + $signed(scope[16 * i +: 16])) >>> 10;
                inst[i] <= scope[16 * i +: 16];
                acc[i] <= 26'sd0;
            end else
                acc[i] <= acc[i] + $signed(scope[16 * i +: 16]);
        if (n == 10'd1023) wr_v <= 3'd0;
    end
    // le tre medie e i tre campioni negli anelli, uno per ciclo, poi il posto dopo
    if (wr_v != 3'd7) begin
        mem[{wr_v[2], wr_v[1:0], wptr}] <= wr_v[2] ? inst[wr_v[1:0]] : avg[wr_v[1:0]];
        wr_v <= (wr_v == 3'd2) ? 3'd4 : (wr_v == 3'd6) ? 3'd7 : wr_v + 3'd1;
        if (wr_v == 3'd6) wptr <= wptr + 8'd1;
    end
end

reg [15:0] q = 16'd0;
always @(posedge clk_cpu) q <= mem[raddr];
assign rdata = {{16{q[15]}}, q};

endmodule
