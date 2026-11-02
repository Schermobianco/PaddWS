// Logica di gioco di PADD WS su un processore RISC-V, CPU avversarie comprese: le porte verso
// pong_top.v e i renderer.
//
// Il processore (VexRiscv, RV32IM, rtl/vexriscv) esegue il firmware rust/mister-fw, cioè il core
// Rust vero (paddws-core): `Match::step` e `Cpu::input`. Il firmware è nella BRAM da 64 KB qui
// sotto, caricata dalla sintesi con i file rtl/gen/pong_fw_b0..3.hex (tools/gen_mister_fw.py), con
// le costanti, i dati e lo stack.
//
// Mappa (vedi rust/mister-fw/src/map.rs, che è la specifica):
//   0x0000_0000 - 0x0000_FFFF  RAM (bit 31 dell'indirizzo a zero: con la cache dati)
//   0xF000_0000 - 0xF000_03FF  registri (bit 31 a uno: senza cache)
//     letture   0x000 STATUS (bit 0-7 partite, 8 tick da fare), 0x004 partita, 0x008 seme,
//               0x00C CPU (livelli e comandi), 0x010/0x014 semi delle CPU, 0x018 comandi del tick,
//               0x01C mosse e lati della CPU, 0x020 TICK_HZ, 0x024 campo, 0x040 e 0x080 modifiche
//               di prova (solo simulazione)
//     scritture 0x000 fine (numero della partita servita), 0x004 errore del firmware, 0x008
//               modifiche applicate, 0x100 + 4 * i parola di stato i (rust/mister-fw/src/words.rs)
//
// Protocollo: `reset` (nuova partita) e `step` (un tick) alzano `busy` il ciclo dopo; `busy`
// torna basso quando il firmware ha scritto le parole di stato e la fine con il numero della partita
// in corso. Una nuova partita durante un tick lo annulla (la fine con il numero vecchio non conta).
//
// Due clock dalla stessa PLL: `clk` (20 MHz, quello del core) e `clk_cpu` (60 MHz, o 40 come
// ripiego: rtl/pll/pll_0002.v), con i fronti allineati. Nel dominio di `clk` restano le richieste
// (`step`, `reset` e i loro ingressi, registrati qui), `busy` e le uscite; nel dominio di `clk_cpu`
// il processore, la RAM, le letture dei registri e una copia ombra delle parole di stato, che il
// firmware scrive una alla volta. La fine del firmware è un cambio di `done_tog` con il numero della
// partita: al primo fronte di `clk` dopo, le 86 parole passano tutte insieme alle uscite e `busy` si
// abbassa, poi `done_ack` conferma. Finché la conferma non arriva lo STATUS letto dal firmware non
// mostra il tick da fare: lo stesso tick non si esegue due volte. Le uscite cambiano quindi solo a
// fine tick, tutte nello stesso ciclo.
//
// Tempi: i due clock sono correlati e Quartus analizza ogni passaggio tra domini con la relazione
// vera tra i fronti (al peggio un periodo di `clk_cpu`, 16,7 ns). Tutti i passaggi sono da registro a
// registro (al più un multiplexer o un confronto), quindi non servono eccezioni nel file SDC né
// sincronizzatori: tra clock sincroni non c'è metastabilità, e il protocollo qui sopra garantisce che
// un impulso di un dominio sia visto dall'altro (le richieste restano nei registri finché servono).
//
// Il bus del VexRiscv è Wishbone (classic, con i burst della cache): la RAM risponde in un ciclo e
// nei burst legge in anticipo la parola dopo, così una riga della cache arriva in 9 cicli; le
// scritture finiscono nello stesso ciclo.

`timescale 1ns / 1ps

module pong_logic_rv #(
    parameter integer TICK_HZ = 240,            // frequenza della simulazione (nel core 240)
    parameter integer WIDTH = 320,              // campo di gioco in pixel
    parameter integer HEIGHT = 240,
    parameter FW_ROM0 = "rtl/gen/pong_fw_b0.hex",   // immagine della RAM, un file per byte
    parameter FW_ROM1 = "rtl/gen/pong_fw_b1.hex",
    parameter FW_ROM2 = "rtl/gen/pong_fw_b2.hex",
    parameter FW_ROM3 = "rtl/gen/pong_fw_b3.hex"
) (
    input  wire        clk,        // 20 MHz: richieste e uscite
    input  wire        clk_cpu,    // 60 MHz (o 40) dalla stessa PLL, fronti allineati a clk: processore
    input  wire        rv_reset,   // reset del processore (anche dall'OSD): il firmware riparte da capo
    input  wire        reset,      // nuova partita: battuta iniziale con `seed`
    input  wire        two_players,
    input  wire        evo_mode,
    input  wire        next_mode,  // modalità NEXT (solo in due)
    input  wire [8:0]  loadout0,   // NEXT: tre bonus scelti (3 bit ciascuno) per giocatore
    input  wire [8:0]  loadout1,
    input  wire [5:0]  kinds,      // NEXT: tipo di racchetta (3 bit per lato, 7 = senza tipo)
    input  wire [1:0]  difficulty, // 0 facile .. 3 esperto
    input  wire        super_moves, // NEXT: mosse speciali accese
    input  wire [31:0] seed,
    // CPU avversarie (Cpu::new), lette con `reset`: livello (0-3 la difficoltà, 4-10 CHALLENGE),
    // comando (2 bit per lato: 0 joystick, 1 spinner, 2 tastiera) e seme di ciascuna
    input  wire [3:0]  cpu_level0,
    input  wire [3:0]  cpu_level1,
    input  wire [3:0]  cpu_control,
    input  wire [31:0] cpu_seed0,
    input  wire [31:0] cpu_seed1,
    input  wire        step,       // impulso di un ciclo: esegue un tick
    // come in trace_input.hex: per giocatore bit 0 su, 1 giù, 2 rapido, 3 avanti, 4 seleziona, 5 attiva,
    // 6 posizione da encoder in `offsets`, 7 sparo del BLASTER
    input  wire [15:0] inputs,
    input  wire [15:0] offsets,
    input  wire [3:0]  specials,
    // lati comandati dalla CPU in questo tick (bit 0 sinistra, 1 destra), letti con `step`: per loro
    // contano solo il bit 7 di `inputs` (sparo) e niente altro; i comandi li calcola Cpu::input
    input  wire [1:0]  cpu_sides,
    output reg         busy = 1'b0,
    output wire [15:0] events,

    output wire signed [31:0] ball_x,
    output wire signed [31:0] ball_y,
    output wire signed [31:0] ball_vx,
    output wire signed [31:0] ball_vy,
    output wire signed [31:0] ball_boost,
    output wire signed [31:0] ball_r,
    output wire signed [31:0] pad0_x,
    output wire signed [31:0] pad0_y,
    output wire signed [31:0] pad0_speed,
    output wire [31:0]        pad0_flags,
    output wire signed [31:0] pad1_x,
    output wire signed [31:0] pad1_y,
    output wire signed [31:0] pad1_speed,
    output wire [31:0]        pad1_flags,
    output wire signed [31:0] pad0_boost_h,
    output wire signed [31:0] pad1_boost_h,
    output wire [15:0]        score0,
    output wire [15:0]        score1,
    output wire [15:0]        best,
    output wire [31:0]        serve_timer,
    output wire [31:0]        rng,
    output wire               two,
    output wire               evo,
    output wire               nxt,
    output wire [31:0]        spawn_timer,
    output wire [31:0]        slow_timer,
    output wire [15:0]        bullet_timer,
    output wire signed [31:0] curve,
    output wire [31:0]        next_flags,
    output wire [31:0]        player0,
    output wire [31:0]        player1,
    output wire [127:0]       caps_x,
    output wire [127:0]       caps_y,
    output wire [127:0]       caps_vx,
    output wire [127:0]       caps_vy,
    output wire [15:0]        caps_flags,
    output wire [31:0]        kind0,
    output wire [31:0]        kind1,
    output wire [31:0]        aux0,
    output wire [31:0]        aux1,
    output wire [255:0]       shots_x,     // colpi del BLASTER: 4 per giocatore (prima il sinistro)
    output wire [255:0]       shots_y,
    output wire [255:0]       shots_vx,
    output wire signed [31:0] pad0_motion,
    output wire signed [31:0] pad1_motion,
    output wire signed [31:0] pad0_h,
    output wire signed [31:0] pad1_h,
    output wire               sup,
    output wire               ghost_hide,  // palla nascosta dal GHOST (Next::ball_hidden)
    output wire [31:0]        super0,
    output wire [31:0]        super1,
    output wire signed [31:0] ball_dx,
    output wire [31:0]        tick,
    // comandi effettivi dell'ultimo tick, CPU comprese (come trace_input.hex: tasti e encoder, mosse)
    output wire [31:0]        tick_input,
    output wire [3:0]         tick_special,
    output reg                fw_panic = 1'b0   // il firmware si è fermato (errore): busy resta alto
);

`include "pong_fw.vh"

localparam integer RAM_WORDS = FW_RAM_BYTES / 4;
localparam integer RAM_AW = $clog2(RAM_WORDS);
// parole di stato scritte dal firmware (words::WORDS) e posizioni di quelle fuori dalle tracce
localparam integer WORDS = 86;
localparam integer W_BOOST_H0 = 77, W_HEIGHT0 = 79, W_BALL_DX = 81, W_TICK = 82, W_MODE = 83,
                   W_INPUT = 84, W_SPECIALS = 85;
localparam integer PATCH_MAX = 16;

// ------------------------------------------------------------------ processore

wire        i_cyc, i_stb, i_we;
wire [29:0] i_adr;
wire [2:0]  i_cti;
wire        d_cyc, d_stb, d_we;
wire [29:0] d_adr;
wire [31:0] d_wdata;
wire [3:0]  d_sel;
wire [2:0]  d_cti;
reg         i_ack = 1'b0, d_rack = 1'b0;
reg  [31:0] i_rdata, d_ram_q, io_q;
wire        d_req = d_cyc && d_stb;
wire        d_io = d_adr[29];                 // indirizzi con il bit 31 a uno
wire        d_ack = d_req && (d_we || d_rack);
wire [31:0] d_rdata = d_io ? io_q : d_ram_q;

// reset all'accensione (i registri dell'FPGA partono dal valore iniziale), oppure da rv_reset;
// registrato nel dominio del processore
reg  [3:0]  por = 4'hF;
always @(posedge clk) if (por != 4'd0) por <= por - 4'd1;
wire        cpu_reset_sys = rv_reset || por != 4'd0;
reg         cpu_reset = 1'b1;
always @(posedge clk_cpu) cpu_reset <= cpu_reset_sys;

/* verilator lint_off PINCONNECTEMPTY */
VexRiscv cpu (
    .clk(clk_cpu), .reset(cpu_reset),
    .externalResetVector(32'h0000_0000), .timerInterrupt(1'b0), .softwareInterrupt(1'b0),
    .externalInterruptArray(32'd0),
    .iBusWishbone_CYC(i_cyc), .iBusWishbone_STB(i_stb), .iBusWishbone_ACK(i_ack), .iBusWishbone_WE(i_we),
    .iBusWishbone_ADR(i_adr), .iBusWishbone_DAT_MISO(i_rdata), .iBusWishbone_DAT_MOSI(),
    .iBusWishbone_SEL(), .iBusWishbone_ERR(1'b0), .iBusWishbone_CTI(i_cti), .iBusWishbone_BTE(),
    .dBusWishbone_CYC(d_cyc), .dBusWishbone_STB(d_stb), .dBusWishbone_ACK(d_ack), .dBusWishbone_WE(d_we),
    .dBusWishbone_ADR(d_adr), .dBusWishbone_DAT_MISO(d_rdata), .dBusWishbone_DAT_MOSI(d_wdata),
    .dBusWishbone_SEL(d_sel), .dBusWishbone_ERR(1'b0), .dBusWishbone_CTI(d_cti), .dBusWishbone_BTE()
);
/* verilator lint_on PINCONNECTEMPTY */

// ------------------------------------------------------------------ RAM: 4 BRAM da 8 bit, due porte
//
// Porta A: istruzioni (solo lettura). Porta B: dati. In un burst (CTI = 010) la parola dopo si
// legge mentre si conferma quella attuale: il master passa all'indirizzo seguente al ciclo dopo.

reg [7:0] ram0 [0:RAM_WORDS-1];
reg [7:0] ram1 [0:RAM_WORDS-1];
reg [7:0] ram2 [0:RAM_WORDS-1];
reg [7:0] ram3 [0:RAM_WORDS-1];
initial begin
    // i file coprono l'immagine (FW_IMAGE_WORDS parole): .bss e stack li azzera e li scrive il firmware
    $readmemh(FW_ROM0, ram0);
    $readmemh(FW_ROM1, ram1);
    $readmemh(FW_ROM2, ram2);
    $readmemh(FW_ROM3, ram3);
end

wire              i_req = i_cyc && i_stb;
wire [RAM_AW-1:0] i_addr = i_adr[RAM_AW-1:0] + {{(RAM_AW-1){1'b0}}, i_ack};
wire [RAM_AW-1:0] d_addr = d_adr[RAM_AW-1:0] + {{(RAM_AW-1){1'b0}}, d_rack};
wire              d_wr_ram = d_req && d_we && !d_io;

always @(posedge clk_cpu) begin
    i_ack <= i_req && !(i_ack && i_cti != 3'b010);
    d_rack <= d_req && !d_we && !(d_rack && d_cti != 3'b010);
end

always @(posedge clk_cpu) i_rdata[7:0] <= ram0[i_addr];
always @(posedge clk_cpu) i_rdata[15:8] <= ram1[i_addr];
always @(posedge clk_cpu) i_rdata[23:16] <= ram2[i_addr];
always @(posedge clk_cpu) i_rdata[31:24] <= ram3[i_addr];

always @(posedge clk_cpu) begin
    if (d_wr_ram && d_sel[0]) ram0[d_addr] <= d_wdata[7:0];
    d_ram_q[7:0] <= ram0[d_addr];
end
always @(posedge clk_cpu) begin
    if (d_wr_ram && d_sel[1]) ram1[d_addr] <= d_wdata[15:8];
    d_ram_q[15:8] <= ram1[d_addr];
end
always @(posedge clk_cpu) begin
    if (d_wr_ram && d_sel[2]) ram2[d_addr] <= d_wdata[23:16];
    d_ram_q[23:16] <= ram2[d_addr];
end
always @(posedge clk_cpu) begin
    if (d_wr_ram && d_sel[3]) ram3[d_addr] <= d_wdata[31:24];
    d_ram_q[31:24] <= ram3[d_addr];
end

// ------------------------------------------------------------------ registri

// dominio di clk: richieste, busy e uscite
reg  [7:0]  epoch = 8'd0;         // partite chieste (sale a ogni reset)
reg         step_pend = 1'b0;
reg         reset_pend = 1'b0;    // nuova partita chiesta e non ancora servita
reg  [31:0] r_config = 32'd0, r_seed = 32'd0, r_cpu = 32'd0, r_cpu_seed0 = 32'd0, r_cpu_seed1 = 32'd0;
reg  [31:0] r_input = 32'd0;
reg  [5:0]  r_input2 = 6'd0;
reg         done_ack = 1'b0;      // ultima fine del firmware già vista (copia di done_tog)
reg  [31:0] w [0:WORDS-1];        // parole di stato in uscita
// dominio di clk_cpu: scritture del firmware
reg         done_tog = 1'b0;      // cambia a ogni fine scritta dal firmware...
reg  [7:0]  done_epoch = 8'd0;    // ...con il numero della partita servita
reg  [31:0] shadow [0:WORDS-1];   // parole di stato del tick in corso
// modifiche di prova: le scrive solo il simulatore dei frame (nella sintesi restano a zero)
reg  [7:0]  patch_n = 8'd0;
reg  [31:0] patch [0:2*PATCH_MAX-1];
integer     k;
initial begin
    for (k = 0; k < 2 * PATCH_MAX; k = k + 1) patch[k] = 32'd0;
    for (k = 0; k < WORDS; k = k + 1) begin
        w[k] = 32'd0;
        shadow[k] = 32'd0;
    end
end

wire        io_wr = d_req && d_we && d_io;
wire [7:0]  io_word = d_adr[7:0];      // indirizzo del registro in parole (0xF000_0000 + 4 * io_word)

always @(posedge clk_cpu) begin
    if (io_wr && io_word == 8'h00) begin
        done_tog <= !done_tog;
        done_epoch <= d_wdata[7:0];
    end
    if (io_wr && io_word == 8'h01) fw_panic <= 1'b1;
    if (io_wr && io_word == 8'h02) patch_n <= 8'd0;
    if (io_wr && io_word >= 8'h40 && io_word < 8'h40 + WORDS) shadow[io_word - 8'h40] <= d_wdata;
end

// nuova fine del firmware, vista in questo ciclo di clk
wire        done_new = done_tog != done_ack;

always @(posedge clk) begin
    if (done_new) done_ack <= done_tog;
    if (reset) begin
        // il numero salta lo zero: il firmware appena ripartito (che parte da 0) vede sempre la partita
        epoch <= (epoch == 8'hFF) ? 8'd1 : epoch + 8'd1;
        reset_pend <= 1'b1;
        step_pend <= 1'b0;
        busy <= 1'b1;
        r_config <= {2'd0, kinds, loadout1, loadout0, difficulty, super_moves, next_mode, evo_mode, two_players};
        r_seed <= seed;
        r_cpu <= {20'd0, cpu_control, cpu_level1, cpu_level0};
        r_cpu_seed0 <= cpu_seed0;
        r_cpu_seed1 <= cpu_seed1;
    end else if (cpu_reset_sys) begin
        // il firmware riparte da capo: un tick in corso si perde, una partita chiesta resta da servire
        // (il firmware parte dal numero 0); senza partite in attesa busy torna basso e le uscite
        // restano com'erano
        step_pend <= 1'b0;
        if (!reset_pend) begin
            epoch <= 8'd0;
            busy <= 1'b0;
        end
    end else begin
        if (done_new && done_epoch == epoch && busy) begin
            // fine del tick o della nuova partita: tutte le parole insieme
            for (k = 0; k < WORDS; k = k + 1) w[k] <= shadow[k];
            busy <= 1'b0;
            step_pend <= 1'b0;
            reset_pend <= 1'b0;
        end
        if (step) begin
            step_pend <= 1'b1;
            busy <= 1'b1;
            r_input <= {offsets, inputs};
            r_input2 <= {cpu_sides, specials};
        end
    end
end

// letture dei registri (dominio di clk_cpu): un ciclo, come la RAM. Il tick da fare si vede solo
// dopo la conferma dell'ultima fine
always @(posedge clk_cpu) begin
    if (io_word >= 8'h20 && io_word < 8'h20 + 2 * PATCH_MAX)
        io_q <= patch[io_word[4:0]];
    else case (io_word)
        8'h00: io_q <= {23'd0, step_pend && done_ack == done_tog, epoch};
        8'h01: io_q <= r_config;
        8'h02: io_q <= r_seed;
        8'h03: io_q <= r_cpu;
        8'h04: io_q <= r_cpu_seed0;
        8'h05: io_q <= r_cpu_seed1;
        8'h06: io_q <= r_input;
        8'h07: io_q <= {26'd0, r_input2};
        8'h08: io_q <= TICK_HZ;
        8'h09: io_q <= HEIGHT * 65536 + WIDTH;
        8'h10: io_q <= {24'd0, patch_n};
        default: io_q <= 32'd0;
    endcase
end

// ------------------------------------------------------------------ uscite (formato delle tracce)

assign ball_x = w[0];
assign ball_y = w[1];
assign ball_vx = w[2];
assign ball_vy = w[3];
assign ball_boost = w[4];
assign ball_r = w[5];
assign pad0_x = w[6];
assign pad0_y = w[7];
assign pad0_speed = w[8];
assign pad0_flags = w[9];
assign pad1_x = w[10];
assign pad1_y = w[11];
assign pad1_speed = w[12];
assign pad1_flags = w[13];
assign score0 = w[14][15:0];
assign score1 = w[14][31:16];
assign best = w[15][15:0];
assign serve_timer = w[16];
assign events = w[17][15:0];
assign rng = w[18];
assign spawn_timer = w[19];
assign slow_timer = {16'd0, w[20][15:0]};
assign bullet_timer = w[20][31:16];
assign curve = w[21];
assign next_flags = w[22];
assign player0 = w[23];
assign player1 = w[24];
genvar g;
generate
    for (g = 0; g < 4; g = g + 1) begin : caps
        assign caps_x[32*g +: 32] = w[25 + 5*g];
        assign caps_y[32*g +: 32] = w[26 + 5*g];
        assign caps_vx[32*g +: 32] = w[27 + 5*g];
        assign caps_vy[32*g +: 32] = w[28 + 5*g];
        assign caps_flags[4*g +: 4] = w[29 + 5*g][3:0];
    end
    for (g = 0; g < 8; g = g + 1) begin : shots
        assign shots_x[32*g +: 32] = w[49 + 3*g];
        assign shots_y[32*g +: 32] = w[50 + 3*g];
        assign shots_vx[32*g +: 32] = w[51 + 3*g];
    end
endgenerate
assign kind0 = w[45];
assign kind1 = w[46];
assign aux0 = w[47];
assign aux1 = w[48];
assign pad0_motion = w[73];
assign pad1_motion = w[74];
assign super0 = w[75];
assign super1 = w[76];
assign pad0_boost_h = w[W_BOOST_H0];
assign pad1_boost_h = w[W_BOOST_H0 + 1];
assign pad0_h = w[W_HEIGHT0];
assign pad1_h = w[W_HEIGHT0 + 1];
assign ball_dx = w[W_BALL_DX];
assign tick = w[W_TICK];
assign two = w[W_MODE][0];
assign evo = w[W_MODE][1];
assign nxt = w[W_MODE][2];
assign sup = w[W_MODE][3];
assign ghost_hide = w[W_MODE][4];
assign tick_input = w[W_INPUT];
assign tick_special = w[W_SPECIALS][3:0];

endmodule
