// Banco di prova di pong_logic_rv (Verilator, comandato da tb_rv.cpp): la logica sul RISC-V con gli
// ingressi delle tracce di paddws-trace; tb_rv.cpp ne confronta le uscite con le tracce.

`timescale 1ns / 1ps

/* verilator lint_off UNUSEDSIGNAL */
module tb_rv_top #(
    parameter integer TICK_HZ = 240,
    // immagine del firmware, dalla cartella di tb_rv.exe (mister/sim/rv)
    parameter FW_ROM0 = "../../rtl/gen/pong_fw_b0.hex",
    parameter FW_ROM1 = "../../rtl/gen/pong_fw_b1.hex",
    parameter FW_ROM2 = "../../rtl/gen/pong_fw_b2.hex",
    parameter FW_ROM3 = "../../rtl/gen/pong_fw_b3.hex"
) (
    input  wire        clk,
    input  wire        clk_cpu,     // clock del processore (tb_rv.cpp: 3 o 2 volte clk, fronti allineati)
    input  wire        rv_reset,
    input  wire        reset,
    input  wire        two_players,
    input  wire        evo_mode,
    input  wire        next_mode,
    input  wire [8:0]  loadout0,
    input  wire [8:0]  loadout1,
    input  wire [5:0]  kinds,
    input  wire [1:0]  difficulty,
    input  wire        super_moves,
    input  wire [31:0] seed,
    input  wire [3:0]  cpu_level0,
    input  wire [3:0]  cpu_level1,
    input  wire [3:0]  cpu_control,
    input  wire        step,        // tick per pong_logic_rv
    input  wire [15:0] inputs,      // comandi della traccia (pong_logic_rv: le CPU li sostituiscono)
    input  wire [15:0] offsets,
    input  wire [3:0]  specials,
    input  wire [1:0]  cpu_sides,
    output wire        busy,
    output wire        fw_panic,
    output wire [31:0] tick_input,
    output wire [3:0]  tick_special,
    // parole delle tracce da pong_logic_rv (77 da 32 bit, parola 0 nei bit bassi)
    output wire [32*77-1:0] words,
    // contatori del bus del processore (cicli di clk_cpu): riempimenti della cache istruzioni e dati, scritture
    // in RAM, accessi ai registri
    output reg  [31:0] n_irefill = 0,
    output reg  [31:0] c_irefill = 0,
    output reg  [31:0] n_drefill = 0,
    output reg  [31:0] c_drefill = 0,
    output reg  [31:0] n_dwrite = 0,
    output reg  [31:0] n_io = 0,
    output wire        irefill_start,   // inizio di un riempimento della cache istruzioni...
    output wire [31:0] irefill_addr     // ...e indirizzo della riga
);
assign irefill_start = dut.i_cyc && !i_cyc_q;
assign irefill_addr = {dut.i_adr, 2'b00};

reg i_cyc_q = 1'b0, d_rd_q = 1'b0;
wire d_rd = dut.d_req && !dut.d_we && !dut.d_io;
always @(posedge clk_cpu) begin
    i_cyc_q <= dut.i_cyc;
    d_rd_q <= d_rd;
    if (dut.i_cyc) c_irefill <= c_irefill + 1;
    if (dut.i_cyc && !i_cyc_q) n_irefill <= n_irefill + 1;
    if (d_rd) c_drefill <= c_drefill + 1;
    if (d_rd && !d_rd_q) n_drefill <= n_drefill + 1;
    if (dut.d_req && dut.d_we && !dut.d_io) n_dwrite <= n_dwrite + 1;
    if (dut.d_req && dut.d_io && dut.d_ack) n_io <= n_io + 1;
end

// ------------------------------------------------------------------ uscite della logica

`define LOGIC_WIRES(p) \
    wire [15:0] p``events; \
    wire signed [31:0] p``ball_x, p``ball_y, p``ball_vx, p``ball_vy, p``ball_boost, p``ball_r; \
    wire signed [31:0] p``pad0_x, p``pad0_y, p``pad0_speed, p``pad1_x, p``pad1_y, p``pad1_speed; \
    wire signed [31:0] p``pad0_boost_h, p``pad1_boost_h; \
    wire [31:0] p``pad0_flags, p``pad1_flags, p``serve_timer, p``rng; \
    wire [15:0] p``score0, p``score1, p``best; \
    wire p``two, p``evo, p``nxt; \
    wire [31:0] p``spawn_timer, p``slow_timer, p``next_flags, p``player0, p``player1, p``tick; \
    wire [15:0] p``bullet_timer; \
    wire signed [31:0] p``curve; \
    wire [127:0] p``caps_x, p``caps_y, p``caps_vx, p``caps_vy; \
    wire [15:0] p``caps_flags; \
    wire [31:0] p``kind0, p``kind1, p``aux0, p``aux1; \
    wire [255:0] p``shots_x, p``shots_y, p``shots_vx; \
    wire signed [31:0] p``pad0_motion, p``pad1_motion, p``pad0_h, p``pad1_h; \
    wire p``sup; \
    wire [31:0] p``super0, p``super1; \
    wire signed [31:0] p``ball_dx;

`define LOGIC_PORTS(p) \
    .events(p``events), \
    .ball_x(p``ball_x), .ball_y(p``ball_y), .ball_vx(p``ball_vx), .ball_vy(p``ball_vy), .ball_boost(p``ball_boost), .ball_r(p``ball_r), \
    .pad0_x(p``pad0_x), .pad0_y(p``pad0_y), .pad0_speed(p``pad0_speed), .pad0_flags(p``pad0_flags), \
    .pad1_x(p``pad1_x), .pad1_y(p``pad1_y), .pad1_speed(p``pad1_speed), .pad1_flags(p``pad1_flags), \
    .pad0_boost_h(p``pad0_boost_h), .pad1_boost_h(p``pad1_boost_h), \
    .score0(p``score0), .score1(p``score1), .best(p``best), .serve_timer(p``serve_timer), .rng(p``rng), \
    .two(p``two), .evo(p``evo), .nxt(p``nxt), \
    .spawn_timer(p``spawn_timer), .slow_timer(p``slow_timer), .bullet_timer(p``bullet_timer), .curve(p``curve), \
    .next_flags(p``next_flags), .player0(p``player0), .player1(p``player1), \
    .caps_x(p``caps_x), .caps_y(p``caps_y), .caps_vx(p``caps_vx), .caps_vy(p``caps_vy), .caps_flags(p``caps_flags), \
    .kind0(p``kind0), .kind1(p``kind1), .aux0(p``aux0), .aux1(p``aux1), \
    .shots_x(p``shots_x), .shots_y(p``shots_y), .shots_vx(p``shots_vx), \
    .pad0_motion(p``pad0_motion), .pad1_motion(p``pad1_motion), .pad0_h(p``pad0_h), .pad1_h(p``pad1_h), \
    .sup(p``sup), .super0(p``super0), .super1(p``super1), .ball_dx(p``ball_dx), .tick(p``tick)

`LOGIC_WIRES(n_)

pong_logic_rv #(.TICK_HZ(TICK_HZ), .FW_ROM0(FW_ROM0), .FW_ROM1(FW_ROM1), .FW_ROM2(FW_ROM2), .FW_ROM3(FW_ROM3)) dut (
    .clk(clk), .clk_cpu(clk_cpu), .rv_reset(rv_reset), .reset(reset), .two_players(two_players), .evo_mode(evo_mode),
    .next_mode(next_mode), .loadout0(loadout0), .loadout1(loadout1), .kinds(kinds), .difficulty(difficulty),
    .super_moves(super_moves), .seed(seed),
    .cpu_level0(cpu_level0), .cpu_level1(cpu_level1), .cpu_control(cpu_control),
    .cpu_seed0(seed), .cpu_seed1(seed ^ 32'd1),
    .step(step), .inputs(inputs), .offsets(offsets), .specials(specials), .cpu_sides(cpu_sides),
    .busy(busy), .tick_input(tick_input), .tick_special(tick_special), .fw_panic(fw_panic),
    `LOGIC_PORTS(n_)
);

// ------------------------------------------------------------------ parole delle tracce

genvar g;
assign words[32*0 +: 32*6] = {n_ball_r, n_ball_boost, n_ball_vy, n_ball_vx, n_ball_y, n_ball_x};
assign words[32*6 +: 32*8] = {n_pad1_flags, n_pad1_speed, n_pad1_y, n_pad1_x, n_pad0_flags, n_pad0_speed, n_pad0_y, n_pad0_x};
assign words[32*14 +: 32*5] = {n_rng, 16'd0, n_events, n_serve_timer, 16'd0, n_best, n_score1, n_score0};
assign words[32*19 +: 32*6] = {n_player1, n_player0, n_next_flags, n_curve, n_bullet_timer, n_slow_timer[15:0], n_spawn_timer};
generate
    for (g = 0; g < 4; g = g + 1) begin : wcaps
        assign words[32*(25+5*g) +: 32*5] = {28'd0, n_caps_flags[4*g +: 4], n_caps_vy[32*g +: 32], n_caps_vx[32*g +: 32],
                                             n_caps_y[32*g +: 32], n_caps_x[32*g +: 32]};
    end
    for (g = 0; g < 8; g = g + 1) begin : wshots
        assign words[32*(49+3*g) +: 32*3] = {n_shots_vx[32*g +: 32], n_shots_y[32*g +: 32], n_shots_x[32*g +: 32]};
    end
endgenerate
assign words[32*45 +: 32*4] = {n_aux1, n_aux0, n_kind1, n_kind0};
assign words[32*73 +: 32*4] = {n_super1, n_super0, n_pad1_motion, n_pad0_motion};

endmodule
/* verilator lint_on UNUSEDSIGNAL */
