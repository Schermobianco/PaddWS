// Timing video 320x240 progressivo a 15,72 kHz / 60,01 Hz (240p NTSC).
// Pixel clock = clk / 3 (6,667 MHz con clk a 20 MHz); 424 pixel per riga, 262 righe.

`timescale 1ns / 1ps

module video_timing (
    input  wire       clk,
    output reg        ce_pix,
    output reg  [8:0] hc,          // 0..423
    output reg  [8:0] vc,          // 0..261
    output wire       hblank,
    output wire       vblank,
    output wire       hsync,
    output wire       vsync
);

localparam H_ACTIVE = 320, H_SYNC_START = 332, H_SYNC_END = 364, H_TOTAL = 424;
localparam V_ACTIVE = 240, V_SYNC_START = 243, V_SYNC_END = 246, V_TOTAL = 262;

reg [1:0] div = 2'd0;

initial begin
    ce_pix = 1'b0;
    hc = 9'd0;
    vc = 9'd0;
end

always @(posedge clk) begin
    div <= (div == 2'd2) ? 2'd0 : div + 2'd1;
    ce_pix <= (div == 2'd2);
    if (ce_pix) begin
        if (hc == H_TOTAL - 1) begin
            hc <= 9'd0;
            vc <= (vc == V_TOTAL - 1) ? 9'd0 : vc + 9'd1;
        end else begin
            hc <= hc + 9'd1;
        end
    end
end

assign hblank = hc >= H_ACTIVE;
assign vblank = vc >= V_ACTIVE;
assign hsync = hc >= H_SYNC_START && hc < H_SYNC_END;
assign vsync = vc >= V_SYNC_START && vc < V_SYNC_END;

endmodule
