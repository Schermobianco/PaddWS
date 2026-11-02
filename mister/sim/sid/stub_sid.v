// SID finto per writes.cpp: al posto del SID del core C64 stampa ogni scrittura nei registri
// ("W indirizzo valore"), così si registra la sequenza del player senza simulare il suono.

`timescale 1ns / 1ps

module sid_top #(
    parameter MULTI_FILTERS = 0,
    parameter DUAL = 0
) (
    input  wire        reset,
    input  wire        clk,
    input  wire        ce_1m,
    input  wire        cs,
    input  wire        we,
    input  wire [4:0]  addr,
    input  wire [7:0]  data_in,
    output wire [7:0]  data_out,
    input  wire [12:0] fc_offset_l,
    input  wire [7:0]  pot_x_l,
    input  wire [7:0]  pot_y_l,
    input  wire [17:0] ext_in_l,
    output wire [17:0] audio_l,
    input  wire [12:0] fc_offset_r,
    input  wire [7:0]  pot_x_r,
    input  wire [7:0]  pot_y_r,
    input  wire [17:0] ext_in_r,
    output wire [17:0] audio_r,
    input  wire        filter_en,
    input  wire        mode,
    input  wire [1:0]  cfg,
    input  wire        ld_clk,
    input  wire [11:0] ld_addr,
    input  wire [15:0] ld_data,
    input  wire        ld_wr
);

assign data_out = 8'd0;
assign audio_l = 18'd0;
assign audio_r = 18'd0;

always @(posedge clk)
    if (we && cs) $display("W %02x %02x", addr, data_in);

endmodule
