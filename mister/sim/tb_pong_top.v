// Testbench del core completo: simula alcuni secondi di partita con due giocatori
// automatici (inseguono la palla), salva alcuni frame come immagini PGM e misura
// le frequenze di riga e di frame. Si esegue da sim/frames (vedi sim/frames.ps1).

`timescale 1ns / 1ps

module tb_pong_top;

parameter integer FRAMES = 300;
parameter integer EVO = 1;
parameter integer TWO = 1;

reg clk = 1'b0;
always #25 clk = ~clk;                 // 20 MHz

reg reset = 1'b1;
reg [31:0] joy0 = 32'd0, joy1 = 32'd0;

wire ce_pix, hblank, vblank, hsync, vsync;
wire [7:0] luma;
wire signed [15:0] audio;

pong_top dut (
    .clk(clk), .reset(reset), .two_players(TWO != 0), .evo_mode(EVO != 0),
    .joy0(joy0), .joy1(joy1),
    .ce_pix(ce_pix), .luma(luma), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync),
    .audio(audio)
);

// ------------------------------------------------ giocatori automatici

// la racchetta insegue la palla con un errore che cambia a ogni frame
function [31:0] chase(input signed [31:0] pad_y, input signed [31:0] ball_y, input integer err);
    reg signed [31:0] diff;
    begin
        diff = (ball_y >>> 16) + err - (pad_y >>> 16);
        chase = (diff > 2) ? 32'h8 : (diff < -2) ? 32'h4 : 32'h0;   // bit 3 su, bit 2 giù
    end
endfunction

integer frame = 0, err0 = 0, err1 = 0, seed = 7;

always @(posedge clk) begin
    if (dut.frame_start) begin
        frame <= frame + 1;
        if (frame % 40 == 0) begin
            err0 <= ($random(seed) % 12);
            err1 <= ($random(seed) % 12);
        end
    end
    joy0 <= chase(dut.pad0_y, dut.ball_y, err0) | ((frame % 97 == 50) ? 32'h10 : 32'h0);
    joy1 <= chase(dut.pad1_y, dut.ball_y, err1) | ((frame % 131 == 70) ? 32'h10 : 32'h0);
end

// ------------------------------------------------- cattura dei frame

reg [7:0] pixels [0:320*240-1];
integer fd, i, hits = 0, boosts = 0, points = 0, walls = 0;

always @(posedge clk) begin
    if (ce_pix && !dut.hb && !dut.vb)
        pixels[dut.vc * 320 + dut.hc] <= luma;
end

task save_frame(input integer n);
    reg [8*32:1] name;
    begin
        $sformat(name, "frame_%0d.pgm", n);
        fd = $fopen(name, "w");
        $fwrite(fd, "P2\n320 240\n255\n");
        for (i = 0; i < 320 * 240; i = i + 1)
            $fwrite(fd, "%0d%s", pixels[i], (i % 320 == 319) ? "\n" : " ");
        $fclose(fd);
    end
endtask

always @(posedge clk) begin
    if (dut.sound_trigger) begin
        walls = walls + dut.sound_events[0];
        hits = hits + dut.sound_events[1];
        boosts = boosts + dut.sound_events[2];
        points = points + dut.sound_events[3];
    end
end

// --------------------------------------------- frequenze di riga e di frame

realtime t_hs = 0, t_vs = 0, line_period = 0, frame_period = 0;
reg hs_q = 1'b0, vs_q = 1'b0;
always @(posedge clk) begin
    hs_q <= hsync;
    vs_q <= vsync;
    if (hsync && !hs_q) begin
        if (t_hs > 0) line_period = $realtime - t_hs;
        t_hs = $realtime;
    end
    if (vsync && !vs_q) begin
        if (t_vs > 0) frame_period = $realtime - t_vs;
        t_vs = $realtime;
    end
end

initial begin
    repeat (10) @(posedge clk);
    reset = 1'b0;
    while (frame < FRAMES) begin
        @(posedge clk);
        if (dut.snapshot && (frame == 2 || frame == 75 || frame == 150 || frame == FRAMES - 1))
            save_frame(frame);
    end
    $display("riga %.3f kHz, frame %.3f Hz", 1.0e6 / line_period, 1.0e9 / frame_period);
    $display("%0d frame: muro %0d colpi %0d boost %0d punti %0d, punteggio %0d-%0d",
             FRAMES, walls, hits, boosts, points, dut.score0, dut.score1);
    $finish;
end

endmodule
