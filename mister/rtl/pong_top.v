// PADD WS per MiSTer: attract, partite a gettoni, logica di gioco, video 320x240p, audio.
//
// Modi: auto-test (solo all'accensione) -> strisce -> logo -> titolo -> demo -> strisce...
// Con una moneta (o in Free Play) Start avvia una partita (in NEXT prima la scelta dei bonus
// e poi quella della racchetta);
// a fine partita (11 punti in due, 3 vite in singolo) GAME OVER e ritorno all'attract.
// CHALLENGE (Players: Challenge): scelta di bonus e racchetta, poi 7 livelli contro avversari CPU
// (presentazione, partita a 7, livello superato o continue a gettoni), iniziali per la
// classifica dei 10 migliori, che compare anche nell'attract tra il titolo e la demo. Battuto l'ultimo
// avversario, il finale (M_ENDING, ending_render: circa 57 s, Start lo salta) prima delle iniziali.
// Durante la scalata (presentazione, partita, livello superato) un secondo giocatore può entrare con
// un credito premendo Start dal lato libero (joystick 2 o tasto 2 con il campione a sinistra):
// HERE COMES A NEW CHALLENGER!, la sua scelta di bonus e racchetta, poi una partita NEXT tra i due a
// rung_points punti. Il vincitore continua la scalata dal suo lato (la CPU anche a sinistra), il
// perdente inserisce le iniziali se il suo miglior punteggio entra in classifica.
// A ogni frame, all'inizio del vblank, la logica esegue 4 tick (240 Hz) nella demo e in
// partita. La logica è il core Rust eseguito dal processore RISC-V di pong_logic_rv, che a ogni tick
// calcola anche i comandi delle CPU (demo e avversario).
// Joystick MiSTer: bit 0 destra, 1 sinistra, 2 giù, 3 su, 4 avanti (A, anche per confermare le
// scelte di NEXT), 5 rapido (B), 6 seleziona bonus (X), 7 usa bonus (Y), 8 start, 9 moneta. Tastiera: 5 = moneta,
// 1 = start, come nei core arcade.
// Come nel gioco originale un doppio tocco veloce su o giù dà l'accelerazione rapida.
// Mosse speciali (NEXT e CHALLENGE, sempre accese da PaddWS.sv): prima della partita la schermata HOW TO
// PLAY (howto_render, con i comandi del controllo scelto nell'OSD), in partita i gesti dei giocatori
// (modulo move_gesture in fondo) diventano il codice della mossa per un tick; barra, nomi delle mosse
// ed effetti li disegna next_render.

`timescale 1ns / 1ps

module pong_top #(
    parameter SID_ROM = "rtl/gen/sid_music.hex",
    parameter VOICE_ROM = "rtl/gen/sid_voices.hex",
    // firmware del processore di pong_logic_rv (tools/gen_mister_fw.py), un file per byte
    parameter FW_ROM0 = "rtl/gen/pong_fw_b0.hex",
    parameter FW_ROM1 = "rtl/gen/pong_fw_b1.hex",
    parameter FW_ROM2 = "rtl/gen/pong_fw_b2.hex",
    parameter FW_ROM3 = "rtl/gen/pong_fw_b3.hex",
    // schermata HOW TO PLAY (tools/gen_howto_assets.py): scritte, mappa delle righe, figurine
    parameter HOWTO_TEXT_ROM = "rtl/gen/howto_text.hex",
    parameter HOWTO_ROWS_ROM = "rtl/gen/howto_rows.hex",
    parameter HOWTO_SPRITE_ROM = "rtl/gen/howto_sprites.hex",
    // finale della CHALLENGE (tools/gen_ending_assets.py): scritte, mappa delle righe, fuochi
    parameter ENDING_TEXT_ROM = "rtl/gen/ending_text.hex",
    parameter ENDING_MAP_ROM = "rtl/gen/ending_map.hex",
    parameter ENDING_FW_ROM = "rtl/gen/ending_fw.hex"
) (
    input  wire        clk,            // 20 MHz
    input  wire        clk_cpu,        // 60 MHz dalla stessa PLL: processore di pong_logic_rv
    input  wire        reset,          // torna all'attract (reset dall'OSD, cambio di opzioni)
    input  wire        egg_clear,      // reset vero (caricamento del core, Reset dell'OSD), non il
                                       // cambio di Game type: spegne l'easter egg delle iniziali
    input  wire [1:0]  game_type,      // 0 Classic, 1 EVO, 2 NEXT, 3 CHALLENGE (sempre in NEXT)
    input  wire [1:0]  players_mode,   // 0 due giocatori, 1 uno (in NEXT: contro la CPU), 2 contro la CPU
                                       // (3, da un CFG di prima, quando CHALLENGE era qui: contro la CPU)
    input  wire        free_play,
    input  wire [1:0]  difficulty,     // 0 facile .. 3 esperto, dalla partita successiva
    input  wire        super_moves,    // mosse speciali in NEXT e CHALLENGE (anche nella loro demo)
    input  wire        upright,        // punteggi e scritte dritti invece che verso i giocatori
    input  wire        attract_mute,   // attract e demo senza suoni (gettone e Start si sentono)
    input  wire [3:0]  music_vol,      // volume della musica: passo dell'OSD, 0 = 100% .. 10 = 0% (nessuna canzone)
    input  wire [3:0]  fx_vol,         // volume degli effetti e delle voci, come music_vol
    input  wire        sid_6581,       // filtro del SID: 0 8580, 1 6581
    input  wire [31:0] joy0,
    input  wire [31:0] joy1,
    input  wire [10:0] ps2_key,
    input  wire [1:0]  control,        // racchette: 0 joystick, 1 paddle, 2 spinner
    input  wire [1:0]  spin_speed,     // spinner: 0 normale, 1 veloce, 2 velocissimo, 3 lento
    input  wire [7:0]  paddle0,        // paddle 0..255 (hps_io)
    input  wire [7:0]  paddle1,
    input  wire [8:0]  spinner0,       // spinner: bit 0-7 spostamento con segno, bit 8 cambia a ogni dato
    input  wire [8:0]  spinner1,
    // classifica di CHALLENGE sulla SD: file della NVRAM da hps_io (ch_nvram.v), salvataggio
    // automatico all'apertura dell'OSD se `nv_autosave`
    input  wire        ioctl_download,
    input  wire        ioctl_upload,
    input  wire [15:0] ioctl_index,
    input  wire        ioctl_wr,
    input  wire [26:0] ioctl_addr,
    input  wire [7:0]  ioctl_dout,
    output wire [7:0]  ioctl_din,
    output wire        ioctl_upload_req,
    input  wire        nv_autosave,

    output wire        ce_pix,
    output wire [23:0] rgb,
    output reg         hblank,
    output reg         vblank,
    output reg         hsync,
    output reg         vsync,
    output wire signed [15:0] audio
);

`include "pong_params.vh"
`include "pong_attract.vh"
`include "sid_music.vh"
`include "sid_voices.vh"

localparam integer TICKS_PER_FRAME = 4;
localparam integer POINTS_TO_WIN = 11;
localparam [1:0]   LIVES = 2'd3;
localparam [4:0]   DOUBLE_TAP_FRAMES = 5'd12;   // secondo tocco entro 200 ms dal rilascio
localparam [4:0]   TAP_HOLD_FRAMES = 5'd8;      // il primo tocco dura al massimo ~130 ms
localparam [1:0]   DEMO_DIFFICULTY = 2'd1;
localparam [10:0]  COUNTDOWN_FRAMES = 11'd180;  // 3, 2, 1 prima del primo servizio

localparam [3:0] M_BOOT = 4'd0, M_STRIPES = 4'd1, M_LOGO = 4'd2, M_TITLE = 4'd3,
                 M_DEMO = 4'd4, M_GAME = 4'd5, M_GAME_OVER = 4'd6, M_PICK = 4'd7,
                 // CHALLENGE: presentazione, livello superato, continue, iniziali, classifica
                 M_INTRO = 4'd8, M_CLEAR = 4'd9, M_CONT = 4'd10, M_INITIALS = 4'd11, M_SCORES = 4'd12,
                 // mosse speciali: comandi prima della partita (dopo la scelta di bonus e racchetta)
                 M_HOWTO = 4'd13,
                 // CHALLENGE: entra un secondo giocatore
                 M_CHALLENGER = 4'd14,
                 // CHALLENGE: finale, battuto l'ultimo avversario (al posto del livello superato)
                 M_ENDING = 4'd15;
localparam [10:0]  CH_NEWCH_FRAMES = 11'd180;   // 3 s di HERE COMES A NEW CHALLENGER!
// Il premio della sfida vinta è Score::duel_bonus del core: il premio di vittoria del livello in corso
// (ch_win_bonus, WIN_POINTS x livello, da tabella), al campione in più, allo sfidante da zero.
localparam [10:0]  HOWTO_FRAMES = 11'd480;      // 8 s, poi la partita parte da sola
localparam [10:0]  HOWTO_SKIP_FRAMES = 11'd20;  // Start o A la saltano dopo un terzo di secondo
localparam [10:0]  CH_INTRO_FRAMES = 11'd240;   // 4 s di presentazione
localparam [10:0]  CH_CLEAR_FRAMES = 11'd240;
localparam [10:0]  CH_CONT_FRAMES = 11'd600;    // 10 s per continuare
localparam [10:0]  CH_INITIALS_FRAMES = 11'd1800;
localparam [10:0]  CH_SCORES_FRAMES = 11'd480;
localparam [10:0]  CH_SKIP_FRAMES = 11'd60;     // prima non si salta (niente salti per sbaglio)
// la voce dice il nome dell'avversario 0,5 s dopo l'inizio della presentazione (ANNOUNCE_AFTER del
// gioco Rust): parte 4 frame prima per i 70 ms in cui sale il DC del SID (pong_sid)
localparam [10:0]  CH_VOICE_FRAME = 11'd26;
localparam [10:0]  PICK_FRAMES = 11'd600;       // 10 s per scegliere i bonus
localparam [10:0]  READY_FRAMES = 11'd72;       // "READY!" prima della partita

// opzioni dell'OSD
wire [1:0] players = (players_mode == 2'd3) ? 2'd2 : players_mode;          // 3 di un CFG vecchio = contro la CPU
wire want_challenge = game_type == 2'd3;                                         // sempre in NEXT
wire want_next = game_type == 2'd2 || want_challenge;
wire want_evo = game_type == 2'd1;
wire want_cpu = players == 2'd2 || want_challenge || (want_next && players == 2'd1);   // NEXT è sempre in due
wire want_two = players != 2'd1 || want_next;

// eventi sonori (bit come quelli della logica): 0 ping, 1 pong, 2 boost, 3 punto, 4 gettone
localparam [7:0] SND_PING = 8'h01, SND_PONG = 8'h02, SND_BOOST = 8'h04, SND_COIN = 8'h10;

// ------------------------------------------------------------------- video

wire [8:0] hc, vc;
wire hb, vb, hs, vs;

video_timing timing (
    .clk(clk), .ce_pix(ce_pix), .hc(hc), .vc(vc),
    .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs)
);

// il colore del pixel esce dal renderer un ciclo dopo: sync e blank vanno ritardati uguale
always @(posedge clk) begin
    hblank <= hb;
    vblank <= vb;
    hsync <= hs;
    vsync <= vs;
end

wire frame_start = ce_pix && hc == 9'd0 && vc == 9'd240;   // inizio del vblank
wire snapshot = ce_pix && hc == 9'd0 && vc == 9'd261;      // ultima riga: logica ferma da tempo

// ---------------------------------------------------------- moneta e start

// seme: contatore libero, campionato all'avvio di ogni partita
reg [31:0] seed_counter = 32'd1;
always @(posedge clk) seed_counter <= seed_counter + 32'd1;

reg [1:0] btn_q = 2'b00;
reg       key_toggle_q = 1'b0;
reg       coin_press = 1'b0, start_press = 1'b0;
reg [2:0] ui_q = 3'b000;                  // {su, giù, A} di tutti e due i joystick al ciclo prima
reg       a_press = 1'b0, up_press = 1'b0, down_press = 1'b0;
reg [1:0] st_q = 2'b00;                   // Start di ciascun joystick al ciclo prima
reg [1:0] side_start = 2'b00;             // Start di un solo lato: joystick 1 o tasto 1, joystick 2 o tasto 2
wire [1:0] ui_sel;                        // joystick che comandano le schermate (le iniziali del perdente: il suo)
wire      key_event = ps2_key[10] != key_toggle_q && ps2_key[9] && !ps2_key[8];
wire      ui_up = (joy0[3] & ui_sel[0]) | (joy1[3] & ui_sel[1]);
wire      ui_down = (joy0[2] & ui_sel[0]) | (joy1[2] & ui_sel[1]);
wire      ui_a = (joy0[4] & ui_sel[0]) | (joy1[4] & ui_sel[1]);

always @(posedge clk) begin
    btn_q <= {joy0[9] | joy1[9], joy0[8] | joy1[8]};
    st_q <= {joy1[8], joy0[8]};
    key_toggle_q <= ps2_key[10];
    coin_press <= ((joy0[9] | joy1[9]) & ~btn_q[1]) | (key_event && ps2_key[7:0] == 8'h2E);   // tasto 5
    start_press <= ((joy0[8] | joy1[8]) & ~btn_q[0]) | (key_event && ps2_key[7:0] == 8'h16);  // tasto 1
    side_start <= {(joy1[8] & ~st_q[1]) | (key_event && ps2_key[7:0] == 8'h1E),               // tasto 2
                   (joy0[8] & ~st_q[0]) | (key_event && ps2_key[7:0] == 8'h16)};
    ui_q <= {ui_up, ui_down, ui_a};
    up_press <= ui_up & ~ui_q[2];
    down_press <= ui_down & ~ui_q[1];
    a_press <= ui_a & ~ui_q[0];
end

// ------------------------------------------------------------------ logica

wire        busy;
wire [15:0] tick_events;
wire signed [31:0] ball_x, ball_y, ball_vx, ball_vy, ball_boost, ball_r;
wire signed [31:0] pad0_x, pad0_y, pad0_speed, pad1_x, pad1_y, pad1_speed, pad0_boost_h, pad1_boost_h;
wire [31:0] pad0_flags, pad1_flags, serve_timer, rng;
wire [15:0] score0, score1, best;
wire        two, evo, nxt;
wire [31:0] spawn_timer, slow_timer, next_flags, player0, player1, logic_tick;
wire [15:0] bullet_timer;           // BULLET: tick di rampa rimasti; armato, lato e scattato in next_flags[11:13]
wire signed [31:0] curve;
wire [127:0] caps_x, caps_y, caps_vx, caps_vy;
wire [15:0] caps_flags;
wire [31:0] kind0, kind1, aux0, aux1;
wire [255:0] shots_x, shots_y, shots_vx;    // colpi del BLASTER, 4 per giocatore
wire signed [31:0] pad0_motion, pad1_motion, pad0_h, pad1_h;
wire        sup;                    // mosse speciali accese nella partita in corso
wire        ghost_hide;             // palla nascosta dal GHOST, calcolata dal firmware
wire [31:0] super0, super1;         // barra, livelli delle mosse armate (e del tiro in volo: super0)
wire signed [31:0] ball_dx;

reg         step = 1'b0;
reg  [15:0] tick_inputs = 16'd0;
reg  [1:0]  tick_cpu = 2'b00;       // lati comandati dalla CPU nel tick (bit 0 sinistra)
wire        ch_cpu_left;            // CHALLENGE con il campione a destra (assegnato più sotto)
reg  [15:0] tick_offsets = 16'd0;   // posizioni da paddle o spinner (bit 6 di ogni giocatore in tick_inputs)
reg         match_reset = 1'b0;
reg         match_two = 1'b1, match_evo = 1'b1, match_next = 1'b0, match_cpu = 1'b0;
reg  [8:0]  match_lo0 = 9'd0, match_lo1 = 9'd0;
reg  [5:0]  match_kinds = 6'h3F;   // tipi di racchetta NEXT, 3 bit per lato (7 = senza tipo)
reg         match_supers = 1'b0;   // mosse speciali (opzione dell'OSD all'avvio della partita)
reg  [3:0]  tick_specials = 4'd0;  // mossa del tick, 2 bit per giocatore
reg  [1:0]  match_level = DEMO_DIFFICULTY;
reg  [3:0]  match_cpu_level = {2'd0, DEMO_DIFFICULTY};   // livello della CPU di destra (CHALLENGE: 4-10)
// modalità della demo: quella scelta nell'OSD quando la demo comincia
localparam [1:0] DEMO_CLASSIC = 2'd0, DEMO_EVO = 2'd1, DEMO_NEXT = 2'd2, DEMO_CHALLENGE = 2'd3;
reg  [1:0]  demo_kind = DEMO_CLASSIC;
wire [1:0]  demo_new = want_challenge ? DEMO_CHALLENGE : want_next ? DEMO_NEXT :
                       want_evo ? DEMO_EVO : DEMO_CLASSIC;
wire [2:0]  demo_rung = (seed_counter[24:22] == 3'd7) ? 3'd6 : seed_counter[24:22];   // livello di CHALLENGE

// la CPU di sinistra gioca nella demo e in CHALLENGE con il campione a destra (allora con il livello
// dell'avversario), quella di destra anche contro un giocatore; tutte e due con il joystick
pong_logic_rv #(.FW_ROM0(FW_ROM0), .FW_ROM1(FW_ROM1), .FW_ROM2(FW_ROM2), .FW_ROM3(FW_ROM3)) logic_core (
    .clk(clk), .clk_cpu(clk_cpu), .rv_reset(reset), .reset(match_reset), .two_players(match_two), .evo_mode(match_evo),
    .next_mode(match_next), .loadout0(match_lo0), .loadout1(match_lo1), .kinds(match_kinds),
    .difficulty(match_level), .super_moves(match_supers), .seed(seed_counter),
    .cpu_level0(ch_cpu_left ? match_cpu_level : {2'd0, match_level}), .cpu_level1(match_cpu_level),
    .cpu_control(4'd0), .cpu_seed0(seed_counter ^ 32'd1), .cpu_seed1(seed_counter),
    .step(step), .inputs(tick_inputs), .offsets(tick_offsets), .specials(tick_specials), .cpu_sides(tick_cpu),
    .busy(busy),
    .events(tick_events),
    .ball_x(ball_x), .ball_y(ball_y), .ball_vx(ball_vx), .ball_vy(ball_vy), .ball_boost(ball_boost), .ball_r(ball_r),
    .pad0_x(pad0_x), .pad0_y(pad0_y), .pad0_speed(pad0_speed), .pad0_flags(pad0_flags),
    .pad1_x(pad1_x), .pad1_y(pad1_y), .pad1_speed(pad1_speed), .pad1_flags(pad1_flags),
    .pad0_boost_h(pad0_boost_h), .pad1_boost_h(pad1_boost_h),
    .score0(score0), .score1(score1), .best(best), .serve_timer(serve_timer), .rng(rng),
    .two(two), .evo(evo), .nxt(nxt),
    .spawn_timer(spawn_timer), .slow_timer(slow_timer), .bullet_timer(bullet_timer), .curve(curve),
    .next_flags(next_flags), .player0(player0), .player1(player1),
    .caps_x(caps_x), .caps_y(caps_y), .caps_vx(caps_vx), .caps_vy(caps_vy), .caps_flags(caps_flags),
    .kind0(kind0), .kind1(kind1), .aux0(aux0), .aux1(aux1),
    .shots_x(shots_x), .shots_y(shots_y), .shots_vx(shots_vx),
    .pad0_motion(pad0_motion), .pad1_motion(pad1_motion), .pad0_h(pad0_h), .pad1_h(pad1_h),
    .sup(sup), .ghost_hide(ghost_hide), .super0(super0), .super1(super1), .ball_dx(ball_dx),
    .tick(logic_tick), .tick_input(), .tick_special(), .fw_panic()
);

// --------------------------------------------------- scelta dei bonus (NEXT)

// le 20 scelte possibili di 3 bonus su 6, per la CPU (bit = riga della scelta)
function [5:0] cpu_pick(input [4:0] i);
    case (i)
        5'd0: cpu_pick = 6'b000111;  5'd1: cpu_pick = 6'b001011;  5'd2: cpu_pick = 6'b010011;
        5'd3: cpu_pick = 6'b100011;  5'd4: cpu_pick = 6'b001101;  5'd5: cpu_pick = 6'b010101;
        5'd6: cpu_pick = 6'b100101;  5'd7: cpu_pick = 6'b011001;  5'd8: cpu_pick = 6'b101001;
        5'd9: cpu_pick = 6'b110001;  5'd10: cpu_pick = 6'b001110;  5'd11: cpu_pick = 6'b010110;
        5'd12: cpu_pick = 6'b100110;  5'd13: cpu_pick = 6'b011010;  5'd14: cpu_pick = 6'b101010;
        5'd15: cpu_pick = 6'b110010;  5'd16: cpu_pick = 6'b011100;  5'd17: cpu_pick = 6'b101100;
        5'd18: cpu_pick = 6'b110100;
        default: cpu_pick = 6'b111000;
    endcase
endfunction

// una delle 20 scelte da 5 bit a caso, e un tipo di racchetta a caso: due tentativi a 3 bit
// (7 vuol dire nessun tipo), poi ARCADE
function [4:0] pick20(input [4:0] r);
    pick20 = (r >= 5'd20) ? r - 5'd20 : r;
endfunction
function [2:0] rand_kind(input [2:0] a, input [2:0] b);
    rand_kind = (a != 3'd7) ? a : (b != 3'd7) ? b : 3'd0;
endfunction

function [2:0] count6(input [5:0] m);
    count6 = m[0] + m[1] + m[2] + m[3] + m[4] + m[5];
endfunction

// tempo scaduto: si completa con SMASH, TELEPORT, SLOW e poi gli altri, come su PC
function [5:0] fill_pick(input [5:0] m);
    reg [5:0] r;
    begin
        r = m;
        if (count6(r) < 3 && !r[1]) r[1] = 1'b1;
        if (count6(r) < 3 && !r[0]) r[0] = 1'b1;
        if (count6(r) < 3 && !r[2]) r[2] = 1'b1;
        if (count6(r) < 3 && !r[3]) r[3] = 1'b1;
        if (count6(r) < 3 && !r[4]) r[4] = 1'b1;
        if (count6(r) < 3 && !r[5]) r[5] = 1'b1;
        fill_pick = r;
    end
endfunction

// i tre bonus presi, in ordine di riga, come loadout della logica (3 bit ciascuno): le righe
// sono i codici dei bonus, tranne l'ultima, STEER, che ha il codice 6 (il 5 è il SUPER)
function [8:0] loadout_of(input [5:0] m);
    reg [8:0] r;
    reg [1:0] n;
    integer b;
    begin
        r = 9'd0;
        n = 2'd0;
        for (b = 0; b < 6; b = b + 1)
            if (m[b] && n < 2'd3) begin
                r[3*n +: 3] = (b == 5) ? 3'd6 : b[2:0];
                n = n + 2'd1;
            end
        loadout_of = r;
    end
endfunction

reg [2:0]  pick_cur [0:1];
reg [5:0]  pick_mask [0:1];
reg        pick_ready = 1'b0;
reg        pick_cpu = 1'b0;     // a destra la CPU (scritta CPU invece di P2)
reg [1:0]  pick_lock = 2'b00;   // lati che non scelgono: la CPU, o il campione quando entra uno sfidante
reg [10:0] ready_at = 11'd0;
reg [2:0]  pk_q [0:1];          // {su, giù, A} al ciclo precedente, per i fronti
reg        pick_go = 1'b0;      // scelta finita: parte la partita
// scelta della racchetta, dopo quella dei bonus (stesso modo M_PICK, con il timer da capo)
reg        pick_paddle = 1'b0;
reg        pick_restart = 1'b0;  // inizio della scelta della racchetta: il timer riparte
reg [2:0]  kind_cur [0:1];
reg [1:0]  kind_chosen = 2'b00;
integer    pp;

initial begin
    for (pp = 0; pp < 2; pp = pp + 1) begin
        pick_cur[pp] = 3'd0;
        pick_mask[pp] = 6'd0;
        pk_q[pp] = 3'd0;
        kind_cur[pp] = 3'd0;
    end
end

// ------------------------------------------------- modi, crediti, pallina

reg [3:0]  mode = M_BOOT;
reg [10:0] mframe = 11'd0;      // frame dall'inizio del modo
reg [5:0]  blink = 6'd0;        // frame % 60, per le scritte lampeggianti
reg [3:0]  credits = 4'd0;
reg [1:0]  lives = LIVES;
reg [7:0]  attract_sound = 8'd0;
reg        booted = 1'b0;       // auto-test già mostrato (solo all'accensione)
reg        attract_trigger = 1'b0;
reg        attract_auto = 1'b0;   // il suono dell'attract è automatico, non un'azione del giocatore

wire in_attract = mode <= M_DEMO || mode == M_SCORES;    // anche la classifica: Start gioca
// conto alla rovescia all'inizio della partita: la logica resta ferma (niente tick)
wire counting = mode == M_GAME && mframe < COUNTDOWN_FRAMES;
wire [1:0] countdown = !counting ? 2'd0 : mframe < 11'd60 ? 2'd3 : mframe < 11'd120 ? 2'd2 : 2'd1;
wire playing = mode == M_DEMO || (mode == M_GAME && !counting);   // non nella scelta dei bonus

// pallina del titolo in 9.8 a virgola fissa, angolo in alto a sinistra
localparam integer BALL_SIZE = 4;
reg signed [17:0] tb_x = 18'sd2560, tb_y = 18'sd15360;
reg signed [15:0] tb_vx = 16'sd410, tb_vy = 16'sd299;         // 1,6 e 1,17 pixel per frame
reg        hit_x = 1'b0, hit_y = 1'b0, stuck = 1'b0;
wire signed [17:0] nx = tb_x + tb_vx, ny = tb_y + tb_vy;
wire signed [9:0]  cur_ix = (tb_x + 18'sd128) >>> 8, cur_iy = (tb_y + 18'sd128) >>> 8;
wire signed [9:0]  nx_ix = (nx + 18'sd128) >>> 8, ny_iy = (ny + 18'sd128) >>> 8;
wire nx_out = nx_ix < 0 || nx_ix > 320 - BALL_SIZE;
wire ny_out = ny_iy < 0 || ny_iy > 240 - BALL_SIZE;

function in_box(input [8:0] px, input [8:0] py, input signed [9:0] bx, input signed [9:0] by);
    in_box = $signed({1'b0, px}) >= bx && $signed({1'b0, px}) < bx + BALL_SIZE &&
             $signed({1'b0, py}) >= by && $signed({1'b0, py}) < by + BALL_SIZE;
endfunction

wire attract_solid;
wire game_over_now;              // fine partita rilevata dopo i tick del frame
// scelta finita: con le mosse speciali si passa prima dalla schermata HOW TO PLAY (in CHALLENGE una
// volta per lato nella partita: lo sfidante la vede solo se il suo lato non l'ha ancora vista)
reg  [1:0] howto_seen = 2'b00;
wire howto_side;                 // lato di chi ha appena scelto (lo sfidante, nella sfida)
wire want_howto = super_moves && !howto_seen[howto_side];
wire howto_done = mode == M_HOWTO && ((frame_start && mframe >= HOWTO_FRAMES) ||
                                      ((a_press || start_press) && mframe >= HOWTO_SKIP_FRAMES));
wire pick_done = (pick_go && mode == M_PICK && !want_howto) || howto_done;

function [10:0] mode_frames(input [3:0] m);
    case (m)
        M_BOOT:    mode_frames = AT_BOOT_FRAMES;
        M_STRIPES: mode_frames = AT_STRIPES_FRAMES;
        M_LOGO:    mode_frames = AT_LOGO_FRAMES;
        M_TITLE:   mode_frames = AT_TITLE_FRAMES;
        M_DEMO:    mode_frames = AT_DEMO_FRAMES;
        M_SCORES:  mode_frames = CH_SCORES_FRAMES;
        default:   mode_frames = AT_GAME_OVER_FRAMES;
    endcase
endfunction

// suoni dell'attract nel frame f del modo m
function [7:0] attract_events(input [3:0] m, input [10:0] f);
    begin
        attract_events = 8'd0;
        case (m)
            M_BOOT:
                if (f == 0) attract_events = SND_PONG;
                else if (f == 2 * AT_BOOT_LINE_FRAMES || f == 3 * AT_BOOT_LINE_FRAMES ||
                         f == 4 * AT_BOOT_LINE_FRAMES || f == 5 * AT_BOOT_LINE_FRAMES) attract_events = SND_PING;
                else if (f == AT_BOOT_GRID_FROM) attract_events = SND_BOOST;
            M_STRIPES:
                if (f >= AT_SLIDE_LAST && f <= AT_SLIDE_LAST + 5 * AT_STRIPE_START_STEP &&
                    ((f - AT_SLIDE_LAST) % AT_STRIPE_START_STEP) == 0) attract_events = SND_PONG;
            M_LOGO:
                if (f == AT_WIPE_FRAMES) attract_events = SND_BOOST;
            default: attract_events = 8'd0;
        endcase
    end
endfunction

reg [10:0] next_frame;
reg [3:0]  next_mode;

// -------------------------------------------------------------- CHALLENGE

reg        ch_active = 1'b0;          // partita CHALLENGE in corso
reg        ch_scores_attract = 1'b0;  // classifica mostrata dall'attract: poi la demo
reg [2:0]  ch_level = 3'd0;
reg [8:0]  ch_lo = 9'd0;              // bonus e racchetta scelti dal giocatore (il campione)
reg [2:0]  ch_kind = 3'd0;
reg        ch_side = 1'b0;            // lato del campione: 0 sinistra, 1 destra (la CPU dall'altro)
// Sfida tra due giocatori: dalla schermata del nuovo sfidante alla ripresa della scalata (iniziali
// del perdente comprese). Le scelte dei due restano in pick_mask e kind_cur, un lato per giocatore.
reg        duel = 1'b0;
reg        duel_end = 1'b0;           // impulso: la scalata riprende con il vincitore...
reg        cont_over = 1'b0;          // continue scaduto: GAME OVER nella schermata, poi iniziali
reg        duel_champ = 1'b0;         // ...che è il campione (altrimenti lo sfidante)
wire       duel_w = score1 > score0;  // lato del vincitore della sfida (punteggi fermi fino alla partita dopo)
// lo sfidante entra dal lato libero, con un credito, mentre la scalata è in corso (non nelle
// iniziali, nella classifica, nel continue e dopo l'ultimo livello); uno solo per volta
wire       ch_join = side_start[!ch_side] && ch_active && !duel && !reset && (free_play || credits != 4'd0) &&
                     (mode == M_INTRO || mode == M_GAME || (mode == M_CLEAR && ch_level != CH_LEVELS - 1));
// la CPU di CHALLENGE gioca a sinistra (il campione è a destra)
assign     ch_cpu_left = ch_active && ch_side;
assign     ui_sel = (duel && mode == M_INITIALS) ? (ch_side ? 2'b10 : 2'b01) : 2'b11;
assign     howto_side = duel && !ch_side;
reg [3:0]  ch_highlight = 4'd15;      // posto appena inserito in classifica
reg [1:0]  ch_pos = 2'd0;             // iniziali: lettera in corso, indice della lettera, scelte
reg [5:0]  ch_letter = 6'd0;
reg [17:0] ch_name = 18'd0;
// Easter egg (come egg_after di rust/game/src/challenge_ui.rs): le iniziali "WS!" confermate lo
// accendono, la volta dopo lo spengono. Giallo e rosso si scambiano su tutto lo schermo (egg_swap,
// in fondo) e al posto della canzone del titolo suona quella del finale. Resta acceso fino a
// egg_clear e non si salva: né nella classifica (il record con "WS!" si salva come gli altri) né
// nell'OSD
reg        egg = 1'b0;
localparam [17:0] EGG_NAME = {6'd40, 6'd28, 6'd32};   // "WS!" (W 32, S 28, "!" 40; la prima nei bit bassi)
wire [17:0] ini_name;                 // iniziali complete alla conferma (anche a tempo scaduto)
// classifica dei 10 migliori: iniziali (codici del font), punti, punti in BCD, livello raggiunto
reg [17:0] tb_name [0:9];
reg [23:0] tb_score [0:9];
reg [27:0] tb_bcd [0:9];
reg [3:0]  tb_level [0:9];
// posto da inserire (a fine CHALLENGE): entra in classifica il ciclo dopo, nel blocco della
// classifica più sotto, che scrive anche i posti letti dalla SD
reg        ins_go = 1'b0;
reg [3:0]  ins_at = 4'd0;
reg [17:0] ins_name = 18'd0;
reg [23:0] ins_score = 24'd0;
reg [27:0] ins_bcd = 28'd0;
reg [3:0]  ins_level = 4'd0;
wire [23:0] ch_best;                  // miglior punteggio della sessione (dai punti arcade, sotto)
wire [3:0]  ch_best_level;
wire [27:0] ch_best_bcd;
// finale (ending_render, più sotto): concluso, Start lo può saltare, voce "YOU WIN!", colpi della sfilata
wire        end_done, end_skip_ok, end_say;
wire [1:0]  end_beat;
wire        end_parade;               // sfilata: racchette e nomi di next_render, i primi end_parade_n
wire [2:0]  end_parade_n;
integer    ti, tj;
initial begin
    for (ti = 0; ti < 10; ti = ti + 1) begin
        tb_name[ti] = {6'd28, 6'd32, 6'd25};      // "PWS" (codici: P 25, W 32, S 28; prima lettera nei bit bassi)
        tb_score[ti] = ch_default_score(ti[3:0]);
        tb_bcd[ti] = ch_default_bcd(ti[3:0]);
        tb_level[ti] = ch_default_level(ti[3:0]);
    end
end

// lettera delle iniziali: A-Z, 0-9, spazio, "!" -> codice del font (0-9 cifre, 10-35 lettere, 36
// spazio, 40 "!"). Il "!" è in fondo, dopo lo spazio, come nelle altre versioni: i codici di prima
// non cambiano e le classifiche salvate restano valide
localparam [5:0] LETTER_LAST = 6'd37;
function [5:0] letter_code(input [5:0] i);
    letter_code = (i < 6'd26) ? i + 6'd10 : (i < 6'd36) ? i - 6'd26 : (i == 6'd36) ? 6'd36 : 6'd40;
endfunction
assign ini_name = (ch_pos == 2'd0) ? {3{letter_code(ch_letter)}} :
                  (ch_pos == 2'd1) ? {{2{letter_code(ch_letter)}}, ch_name[5:0]} :
                  {letter_code(ch_letter), ch_name[11:0]};

// posto in classifica del punteggio (il primo che batte); 15 = fuori
reg [3:0] ch_rank;
integer   ri;
always @(*) begin
    ch_rank = 4'd15;
    for (ri = 9; ri >= 0; ri = ri - 1)
        if (ch_best > tb_score[ri]) ch_rank = ri[3:0];
end

// velocità della palla del livello: un gradino in più o in meno ogni livello di difficoltà da NORMAL
function [1:0] speed_at(input [1:0] base, input [1:0] d);
    reg [2:0] s;
    begin
        s = {1'b0, base} + {1'b0, d};
        speed_at = (s == 3'd0) ? 2'd0 : (s - 3'd1 > 3'd3) ? 2'd3 : s[1:0] - 2'd1;
    end
endfunction

always @(posedge clk) begin
    match_reset <= 1'b0;
    attract_trigger <= 1'b0;
    duel_end <= 1'b0;
    ins_go <= 1'b0;

    // rimbalzi della pallina del titolo: pixel neri campionati durante la scansione
    if (ce_pix && hc < 9'd320 && vc < 9'd240 && attract_solid) begin
        if (in_box(hc, vc, nx_ix, cur_iy)) hit_x <= 1'b1;
        if (in_box(hc, vc, cur_ix, ny_iy)) hit_y <= 1'b1;
        if (in_box(hc, vc, cur_ix, cur_iy)) stuck <= 1'b1;
    end

    if (coin_press && !free_play && credits < 4'd9) begin
        credits <= credits + 4'd1;
        attract_sound <= SND_COIN;
        attract_trigger <= 1'b1;
        attract_auto <= 1'b0;
    end

    // il MiSTer tiene il reset mentre carica il core: l'auto-test riparte da capo finché dura,
    // i reset successivi (OSD, cambio di opzioni) tornano alle strisce
    if (mode != M_BOOT) booted <= 1'b1;

    if (reset) begin
        mode <= booted ? M_STRIPES : M_BOOT;
        mframe <= 11'd0;
        blink <= 6'd0;
        credits <= 4'd0;                                 // il reset azzera anche i crediti
        ch_active <= 1'b0;
        duel <= 1'b0;
        if (egg_clear) egg <= 1'b0;
    end else if (start_press && in_attract && (free_play || credits != 4'd0)) begin
        // nuova partita con le opzioni dell'OSD; NEXT passa prima dalla scelta dei bonus
        if (!free_play) credits <= credits - 4'd1;
        mframe <= 11'd0;
        match_cpu <= want_cpu;
        ch_active <= want_challenge;
        ch_level <= 3'd0;
        ch_side <= 1'b0;                                 // in CHALLENGE si comincia a sinistra
        duel <= 1'b0;
        howto_seen <= 2'b00;
        if (want_next) begin
            mode <= M_PICK;
            attract_sound <= SND_PONG;
        end else begin
            mode <= M_GAME;
            match_two <= want_two;
            match_evo <= want_evo && want_two;
            match_next <= 1'b0;
            match_level <= difficulty;
            match_cpu_level <= {2'd0, difficulty};
            match_reset <= 1'b1;
            attract_sound <= SND_PING;                   // il "3" del conto alla rovescia
        end
        attract_trigger <= 1'b1;
        attract_auto <= 1'b0;
    end else if (ch_join) begin
        // HERE COMES A NEW CHALLENGER! La partita contro la CPU si interrompe; dal livello superato
        // la sfida vale già per il livello dopo
        if (!free_play) credits <= credits - 4'd1;
        duel <= 1'b1;
        match_cpu <= 1'b0;
        if (mode == M_CLEAR) ch_level <= ch_level + 3'd1;
        mode <= M_CHALLENGER;
        mframe <= 11'd0;
        blink <= 6'd0;
        attract_sound <= SND_BOOST;
        attract_trigger <= 1'b1;
        attract_auto <= 1'b0;
    end else if (mode == M_CHALLENGER && frame_start && mframe >= CH_NEWCH_FRAMES) begin
        // la scelta dello sfidante (il campione tiene la sua)
        mode <= M_PICK;
        mframe <= 11'd0;
        attract_sound <= SND_PONG;
        attract_trigger <= 1'b1;
        attract_auto <= 1'b0;
    end else if (pick_go && mode == M_PICK && want_howto) begin
        if (ch_active) howto_seen[howto_side] <= 1'b1;
        mode <= M_HOWTO;
        mframe <= 11'd0;
        blink <= 6'd0;                               // PRESS START TO SKIP acceso da subito
        attract_sound <= SND_PONG;
        attract_trigger <= 1'b1;
        attract_auto <= 1'b0;
    end else if (pick_done && ch_active && !duel) begin
        // CHALLENGE: bonus e racchetta valgono per tutta la scala; prima l'avversario
        mode <= M_INTRO;
        mframe <= 11'd0;
        ch_lo <= loadout_of(pick_mask[0]);
        ch_kind <= kind_cur[0];
    end else if (mode == M_INTRO && ((frame_start && mframe >= CH_INTRO_FRAMES) ||
                                     ((a_press || start_press) && mframe >= CH_SKIP_FRAMES))) begin
        // partita del livello: racchetta, bonus e livello della CPU, velocità della palla; il
        // giocatore dal suo lato, la CPU dall'altro
        mode <= M_GAME;
        mframe <= 11'd0;
        match_two <= 1'b1;
        match_evo <= 1'b0;
        match_next <= 1'b1;
        match_cpu <= 1'b1;
        match_lo0 <= ch_side ? rung_loadout(ch_level) : ch_lo;
        match_lo1 <= ch_side ? ch_lo : rung_loadout(ch_level);
        match_kinds <= ch_side ? {ch_kind, rung_kind(ch_level)} : {rung_kind(ch_level), ch_kind};
        match_level <= speed_at(rung_speed(ch_level), difficulty);
        match_cpu_level <= rung_cpu(ch_level);
        match_supers <= super_moves;
        match_reset <= 1'b1;
        attract_sound <= SND_PING;
        attract_trigger <= 1'b1;
        attract_auto <= 1'b0;
    end else if (mode == M_CLEAR && ((frame_start && mframe >= CH_CLEAR_FRAMES) ||
                                     ((a_press || start_press) && mframe >= CH_SKIP_FRAMES))) begin
        // livello superato: il prossimo avversario, o la fine della scala
        mframe <= 11'd0;
        if (ch_level == CH_LEVELS - 1) begin
            ch_active <= 1'b0;
            mode <= (ch_rank != 4'd15) ? M_INITIALS : M_SCORES;
            ch_highlight <= 4'd15;
            ch_scores_attract <= 1'b0;
            ch_pos <= 2'd0;
            ch_letter <= 6'd0;
        end else begin
            ch_level <= ch_level + 3'd1;
            mode <= M_INTRO;
        end
    end else if (mode == M_ENDING && (end_done || (start_press && end_skip_ok))) begin
        // finale concluso o saltato con Start: iniziali se il punteggio entra in classifica
        ch_active <= 1'b0;
        mframe <= 11'd0;
        blink <= 6'd0;
        mode <= (ch_rank != 4'd15) ? M_INITIALS : M_SCORES;
        ch_highlight <= 4'd15;
        ch_scores_attract <= 1'b0;
        ch_pos <= 2'd0;
        ch_letter <= 6'd0;
    end else if (mode == M_CONT && !cont_over && start_press && mframe >= CH_SKIP_FRAMES && (free_play || credits != 4'd0)) begin
        // continue: stesso livello, punti da zero (li azzera il conteggio qui sotto)
        if (!free_play) credits <= credits - 4'd1;
        mode <= M_INTRO;
        mframe <= 11'd0;
    end else if (mode == M_CONT && !cont_over && frame_start && mframe >= CH_CONT_FRAMES) begin
        // niente continue: GAME OVER, la partita è finita davvero
        cont_over <= 1'b1;
        mframe <= 11'd0;
    end else if (mode == M_CONT && cont_over && frame_start && mframe + 11'd1 >= AT_GAME_OVER_FRAMES) begin
        // dopo il GAME OVER le iniziali, se il miglior punteggio entra in classifica
        cont_over <= 1'b0;
        ch_active <= 1'b0;
        mframe <= 11'd0;
        mode <= (ch_rank != 4'd15) ? M_INITIALS : M_SCORES;
        ch_highlight <= 4'd15;
        ch_scores_attract <= 1'b0;
        ch_pos <= 2'd0;
        ch_letter <= 6'd0;
    end else if (mode == M_INITIALS && (a_press || (frame_start && mframe >= CH_INITIALS_FRAMES))) begin
        // lettera confermata (a tempo scaduto valgono tutte quella sotto il cursore); dopo la terza
        // il punteggio entra in classifica
        ch_name[6 * ch_pos +: 6] <= letter_code(ch_letter);
        if (ch_pos == 2'd2 || !a_press) begin
            ins_go <= 1'b1;
            ins_at <= ch_rank;
            ins_name <= ini_name;
            // "WS!" accende o spegne l'easter egg: la classifica che segue ha già i colori nuovi
            if (ini_name == EGG_NAME) egg <= !egg;
            ins_score <= ch_best;
            ins_bcd <= ch_best_bcd;
            ins_level <= ch_best_level;
            ch_highlight <= ch_rank;
            mframe <= 11'd0;
            if (duel) begin
                // iniziali del campione che ha perso la sfida: la scalata riprende con lo sfidante
                mode <= M_INTRO;
                duel <= 1'b0;
                duel_end <= 1'b1;
                duel_champ <= 1'b0;
                ch_side <= !ch_side;
                ch_lo <= loadout_of(pick_mask[!ch_side]);
                ch_kind <= kind_cur[!ch_side];
            end else
                mode <= M_SCORES;
        end else
            ch_pos <= ch_pos + 2'd1;
        attract_sound <= SND_PONG;
        attract_trigger <= 1'b1;
        attract_auto <= 1'b0;
    end else if (mode == M_INITIALS && (up_press || down_press)) begin
        ch_letter <= up_press ? ((ch_letter == 6'd0) ? LETTER_LAST : ch_letter - 6'd1)
                              : ((ch_letter == LETTER_LAST) ? 6'd0 : ch_letter + 6'd1);
    end else if (pick_done) begin
        // bonus scelti: parte la partita NEXT, con il conto alla rovescia (la sfida di CHALLENGE con
        // la velocità della palla del livello in corso)
        mode <= M_GAME;
        mframe <= 11'd0;
        match_two <= 1'b1;
        match_evo <= 1'b0;
        match_next <= 1'b1;
        match_lo0 <= loadout_of(pick_mask[0]);
        match_lo1 <= loadout_of(pick_mask[1]);
        match_kinds <= {kind_cur[1], kind_cur[0]};
        match_level <= duel ? speed_at(rung_speed(ch_level), difficulty) : difficulty;
        match_cpu_level <= {2'd0, difficulty};
        match_supers <= super_moves;
        match_reset <= 1'b1;
        attract_sound <= SND_PING;
        attract_trigger <= 1'b1;
        attract_auto <= 1'b0;
    end else if (pick_restart && mode == M_PICK) begin
        // bonus scelti: ora la racchetta, con il timer da capo
        mframe <= 11'd0;
        attract_sound <= SND_PONG;
        attract_trigger <= 1'b1;
        attract_auto <= 1'b0;
    end else if (game_over_now && mode == M_GAME) begin
        mode <= M_GAME_OVER;
        mframe <= 11'd0;
    end else if (duel && mode == M_GAME_OVER && frame_start && mframe + 11'd1 >= AT_GAME_OVER_FRAMES) begin
        // fine della sfida: se perde il campione e il suo miglior punteggio entra in classifica, prima
        // le sue iniziali; altrimenti la scalata riprende subito con il vincitore, dal suo lato
        mframe <= 11'd0;
        blink <= 6'd0;
        if (duel_w != ch_side && ch_rank != 4'd15) begin
            mode <= M_INITIALS;
            ch_highlight <= 4'd15;
            ch_pos <= 2'd0;
            ch_letter <= 6'd0;
        end else begin
            mode <= M_INTRO;
            duel <= 1'b0;
            duel_end <= 1'b1;
            duel_champ <= duel_w == ch_side;
            ch_side <= duel_w;
            ch_lo <= loadout_of(pick_mask[duel_w]);
            ch_kind <= kind_cur[duel_w];
        end
    end else if (frame_start) begin
        blink <= (blink == AT_BLINK_PERIOD - 1) ? 6'd0 : blink + 6'd1;
        next_mode = mode;
        // in partita il contatore si ferma al massimo: il conto alla rovescia non ricompare
        next_frame = (mode == M_GAME && mframe == 11'h7FF) ? mframe : mframe + 11'd1;
        // le schermate di CHALLENGE (tranne la classifica) cambiano qui sopra
        if (mode != M_GAME && mode != M_PICK && mode != M_INTRO && mode != M_CLEAR && mode != M_CONT &&
            mode != M_INITIALS && mode != M_HOWTO && mode != M_CHALLENGER && mode != M_ENDING &&
            next_frame >= mode_frames(mode)) begin
            next_frame = 11'd0;
            case (mode)
                M_BOOT: next_mode = M_STRIPES;
                M_TITLE: next_mode = M_SCORES;           // dopo il titolo la classifica, poi la demo
                M_STRIPES: next_mode = M_LOGO;
                M_LOGO: next_mode = M_TITLE;
                M_SCORES: next_mode = ch_scores_attract ? M_DEMO : M_STRIPES;
                // CHALLENGE: livello vinto (l'ultimo: il finale) o continue; demo e GAME OVER tornano
                // alle strisce (la fine della sfida tra due giocatori è qui sopra)
                M_GAME_OVER: next_mode = !ch_active ? M_STRIPES : ((score0 > score1) == ch_side) ? M_CONT :
                                         (ch_level == CH_LEVELS - 1) ? M_ENDING : M_CLEAR;
                default: next_mode = M_STRIPES;
            endcase
            if (next_mode == M_SCORES) begin
                ch_scores_attract <= 1'b1;
                ch_highlight <= 4'd15;
            end
        end
        if (next_mode != mode) blink <= 6'd0;
        mode <= next_mode;
        mframe <= next_frame;

        if (next_mode == M_DEMO && mode != M_DEMO) begin
            // la demo, CPU contro CPU, nella modalità scelta nell'OSD (sempre in due). In NEXT bonus
            // e racchette a caso per tutti e due; in CHALLENGE a destra l'avversario di un livello
            // a caso, con i suoi bonus, la sua racchetta e la sua CPU
            demo_kind <= demo_new;
            match_two <= 1'b1;
            match_evo <= demo_new == DEMO_EVO;
            match_next <= demo_new >= DEMO_NEXT;
            match_lo0 <= loadout_of(cpu_pick(pick20(seed_counter[4:0])));
            match_supers <= super_moves;
            if (demo_new == DEMO_CHALLENGE) begin
                match_lo1 <= rung_loadout(demo_rung);
                match_kinds <= {rung_kind(demo_rung), rand_kind(seed_counter[15:13], seed_counter[18:16])};
                match_level <= speed_at(rung_speed(demo_rung), DEMO_DIFFICULTY);
                match_cpu_level <= rung_cpu(demo_rung);
            end else begin
                match_lo1 <= loadout_of(cpu_pick(pick20(seed_counter[9:5])));
                match_kinds <= {rand_kind(seed_counter[12:10], seed_counter[21:19]),
                                rand_kind(seed_counter[15:13], seed_counter[18:16])};
                match_level <= DEMO_DIFFICULTY;
                match_cpu_level <= {2'd0, DEMO_DIFFICULTY};
            end
            match_reset <= 1'b1;
        end

        if (attract_events(mode, mframe) != 8'd0) begin
            attract_sound <= attract_events(mode, mframe);
            attract_trigger <= 1'b1;
            attract_auto <= 1'b1;
        end
        // conto alla rovescia: un bip a ogni secondo, poi il via (in CHALLENGE il via è la voce "GO!",
        // `call_go` qui sotto)
        if (mode == M_GAME && (next_frame == 11'd60 || next_frame == 11'd120 ||
                               (next_frame == COUNTDOWN_FRAMES && !ch_active))) begin
            attract_sound <= next_frame == COUNTDOWN_FRAMES ? SND_BOOST : SND_PING;
            attract_trigger <= 1'b1;
            attract_auto <= 1'b0;
        end

        // pallina del titolo: un asse alla volta, rimbalzo contro bordi e pixel neri
        if (next_mode == M_TITLE && mode != M_TITLE) begin
            tb_x <= 18'sd2560;  tb_y <= 18'sd15360;      // (10, 60)
            tb_vx <= 16'sd410;  tb_vy <= 16'sd299;
        end else if (mode == M_TITLE) begin
            if (stuck) begin
                // una scritta è comparsa sopra la pallina: la si lascia uscire
                if (!nx_out) tb_x <= nx;
                if (!ny_out) tb_y <= ny;
            end else begin
                if (hit_x || nx_out) tb_vx <= -tb_vx; else tb_x <= nx;
                if (hit_y || ny_out) tb_vy <= -tb_vy; else tb_y <= ny;
                if (hit_x || nx_out || hit_y || ny_out) begin
                    attract_sound <= SND_PING;
                    attract_trigger <= 1'b1;
                    attract_auto <= 1'b1;
                end
            end
        end
        hit_x <= 1'b0;
        hit_y <= 1'b0;
        stuck <= 1'b0;
    end
    // finale: un colpo sul muro per ogni avversario che entra nella sfilata, un colpo di racchetta per
    // ogni timbro, come su PC
    if (end_beat != 2'b00) begin
        attract_sound <= end_beat[0] ? SND_PING : SND_PONG;
        attract_trigger <= 1'b1;
        attract_auto <= 1'b0;
    end
end

// --------------------------------------------------------------- scelta dei bonus

// su e giù muovono il cursore, A prende o lascia il bonus; la CPU sceglie subito, a caso.
// Dopo 10 s (o con tutti e due a 3 bonus) si completa con le scelte predefinite e "READY!".
// Poi la racchetta: su e giù scorrono i tipi, A conferma o annulla; la CPU sceglie a caso;
// dopo 10 s vale quella sotto il cursore.
always @(posedge clk) begin
    pick_go <= 1'b0;
    pick_restart <= 1'b0;
    pk_q[0] <= {joy0[3], joy0[2], joy0[4]};
    pk_q[1] <= {joy1[3], joy1[2], joy1[4]};
    if (start_press && in_attract && want_next) begin
        pick_cur[0] <= 3'd0;
        pick_cur[1] <= 3'd0;
        pick_mask[0] <= 6'd0;
        pick_mask[1] <= want_challenge ? rung_pick(3'd0) :
                        want_cpu ? cpu_pick(seed_counter[4:0] >= 5'd20 ? seed_counter[4:0] - 5'd20 : seed_counter[4:0]) : 6'd0;
        pick_cpu <= want_cpu;
        pick_lock <= {want_cpu, 1'b0};
        pick_ready <= 1'b0;
        pick_paddle <= 1'b0;
        kind_cur[0] <= 3'd0;
        // tipo a caso per la CPU, da bit del contatore diversi da quelli dei bonus
        kind_cur[1] <= want_challenge ? rung_kind(3'd0) : !want_cpu ? 3'd0 : (seed_counter[12:10] != 3'd7) ? seed_counter[12:10] :
                       (seed_counter[15:13] != 3'd7) ? seed_counter[15:13] : 3'd0;
        kind_chosen <= {want_cpu, 1'b0};
    end else if (ch_join) begin
        // nuovo sfidante: sceglie solo lui, dal lato libero; il lato del campione resta com'è
        pick_cur[!ch_side] <= 3'd0;
        pick_mask[!ch_side] <= 6'd0;
        kind_cur[!ch_side] <= 3'd0;
        pick_cpu <= 1'b0;
        pick_lock <= ch_side ? 2'b10 : 2'b01;
        kind_chosen <= ch_side ? 2'b10 : 2'b01;
        pick_ready <= 1'b0;
        pick_paddle <= 1'b0;
    end else if (mode == M_PICK && pick_paddle) begin
        for (pp = 0; pp < 2; pp = pp + 1) begin
            if (!pick_lock[pp] && !pick_ready) begin
                if ((pp == 0 ? joy0[3] : joy1[3]) && !pk_q[pp][2] && !kind_chosen[pp])
                    kind_cur[pp] <= (kind_cur[pp] == 3'd0) ? 3'd6 : kind_cur[pp] - 3'd1;
                if ((pp == 0 ? joy0[2] : joy1[2]) && !pk_q[pp][1] && !kind_chosen[pp])
                    kind_cur[pp] <= (kind_cur[pp] == 3'd6) ? 3'd0 : kind_cur[pp] + 3'd1;
                if ((pp == 0 ? joy0[4] : joy1[4]) && !pk_q[pp][0])
                    kind_chosen[pp] <= !kind_chosen[pp];
            end
        end
        if (frame_start && !pick_ready && (kind_chosen == 2'b11 || mframe >= PICK_FRAMES)) begin
            kind_chosen <= 2'b11;
            pick_ready <= 1'b1;
            ready_at <= mframe;
        end
        if (frame_start && pick_ready && mframe >= ready_at + READY_FRAMES) pick_go <= 1'b1;
    end else if (mode == M_PICK) begin
        for (pp = 0; pp < 2; pp = pp + 1) begin
            if (!pick_lock[pp] && !pick_ready) begin
                if ((pp == 0 ? joy0[3] : joy1[3]) && !pk_q[pp][2])
                    pick_cur[pp] <= (pick_cur[pp] == 3'd0) ? 3'd5 : pick_cur[pp] - 3'd1;
                if ((pp == 0 ? joy0[2] : joy1[2]) && !pk_q[pp][1])
                    pick_cur[pp] <= (pick_cur[pp] == 3'd5) ? 3'd0 : pick_cur[pp] + 3'd1;
                if ((pp == 0 ? joy0[4] : joy1[4]) && !pk_q[pp][0]) begin
                    if (pick_mask[pp][pick_cur[pp]])
                        pick_mask[pp][pick_cur[pp]] <= 1'b0;
                    else if (count6(pick_mask[pp]) < 3'd3)
                        pick_mask[pp][pick_cur[pp]] <= 1'b1;
                end
            end
        end
        if (frame_start && !pick_ready &&
            ((count6(pick_mask[0]) == 3'd3 && count6(pick_mask[1]) == 3'd3) || mframe >= PICK_FRAMES)) begin
            pick_mask[0] <= fill_pick(pick_mask[0]);
            pick_mask[1] <= fill_pick(pick_mask[1]);
            pick_ready <= 1'b1;
            ready_at <= mframe;
        end
        if (frame_start && pick_ready && mframe >= ready_at + READY_FRAMES) begin
            pick_paddle <= 1'b1;
            pick_ready <= 1'b0;
            pick_restart <= 1'b1;
        end
    end
end

// secondi rimasti: (600 - frame) / 60, con il reciproco
wire [10:0] pick_left = (mframe >= PICK_FRAMES) ? 11'd0 : PICK_FRAMES - mframe + 11'd59;
wire [3:0]  pick_secs = (pick_left * 22'd1093) >> 16;

// ------------------------------------------------------------------- bonus

// parole dei giocatori della logica: riserva nei bit 0-11 (codici a 4 bit, 8 = vuoto), selezionato
// 12-13, animazione del SUPER 14-15, armato 16-19 (8 = nessuno), pausa 20-31
function [1:0] reserve_count(input [31:0] pw);
    reserve_count = {1'b0, !pw[3]} + {1'b0, !pw[7]} + {1'b0, !pw[11]};
endfunction

// --------------------------------------------------------- tick del frame

// doppio tocco: un tocco breve (al massimo ~130 ms) e una nuova pressione della stessa
// direzione entro 200 ms dal rilascio danno l'accelerazione rapida, che resta finché si tiene
// una direzione. Con il joystick le piccole correzioni (tenere, lasciare, ripremere) non contano.
// Indici: giocatore * 2 + (0 su, 1 giù).
reg [1:0] dir_q [0:1];            // {su, giù} al ciclo precedente, per giocatore
reg [4:0] hold_age [0:3];         // frame da cui la direzione è premuta
reg [4:0] gap_age [0:3];          // frame dal rilascio
reg [3:0] tap_short = 4'b0000;    // l'ultima pressione è stata un tocco breve
reg [1:0] tap_fast = 2'b00;
integer   pl, k;

initial begin
    dir_q[0] = 2'b00;
    dir_q[1] = 2'b00;
    for (pl = 0; pl < 4; pl = pl + 1) begin
        hold_age[pl] = 5'd31;
        gap_age[pl] = 5'd31;
    end
end

always @(posedge clk) begin
    for (pl = 0; pl < 2; pl = pl + 1) begin
        dir_q[pl] <= pl == 0 ? {joy0[3], joy0[2]} : {joy1[3], joy1[2]};
        for (k = 2 * pl; k < 2 * pl + 2; k = k + 1) begin
            // direzione k: su (bit 3) per k pari, giù (bit 2) per k dispari
            if ((pl == 0 ? joy0[3 - k % 2] : joy1[3 - k % 2]) && !dir_q[pl][1 - k % 2]) begin
                // nuova pressione: doppio tocco se la precedente era breve e il rilascio recente
                tap_fast[pl] <= tap_short[k] && gap_age[k] <= DOUBLE_TAP_FRAMES;
                hold_age[k] <= 5'd0;
            end else if (!(pl == 0 ? joy0[3 - k % 2] : joy1[3 - k % 2]) && dir_q[pl][1 - k % 2]) begin
                tap_short[k] <= hold_age[k] <= TAP_HOLD_FRAMES;          // rilascio
                gap_age[k] <= 5'd0;
            end else if (frame_start) begin
                if (hold_age[k] != 5'd31) hold_age[k] <= hold_age[k] + 5'd1;
                if (gap_age[k] != 5'd31) gap_age[k] <= gap_age[k] + 5'd1;
            end
        end
        if (!(pl == 0 ? joy0[3] | joy0[2] : joy1[3] | joy1[2]))
            tap_fast[pl] <= 1'b0;                                           // racchetta lasciata
    end
end

// comandi di un giocatore per un tick: bit 0 su, 1 giù, 2 rapido (B o doppio tocco), 3 avanti,
// 4 seleziona e 5 usa il bonus (NEXT)
function [7:0] player_bits(input [31:0] joy, input fast, input forward, input select, input activate);
    player_bits = {2'd0, activate, select, forward, joy[5] | fast, joy[2] & ~joy[3], joy[3]};
endfunction

// ------------------------------------------------------- paddle e spinner
//
// La logica riceve la distanza in pixel tra il bordo alto e la racchetta (Match::set_paddle_top),
// da 0 alla corsa della racchetta, che in NEXT dipende dal suo tipo (altezza). Paddle: posizione assoluta 0..255 a ogni tick. Spinner: gli spostamenti del frame
// si sommano alla posizione attuale della racchetta al primo tick del frame e la posizione resta
// per gli altri tick, così il joystick continua a funzionare quando la manopola è ferma. Mentre si
// guida una palla STEER la racchetta è ferma: con lo spinner il verso della rotazione vale come su
// o giù (con il paddle la logica confronta la manopola con la racchetta). Solo shift e somme.

localparam [1:0] C_PADDLE = 2'd1, C_SPINNER = 2'd2;

// corsa della racchetta del giocatore `who` in pixel: 200 a 320x240 per la racchetta normale
function [7:0] travel_of(input who);
    reg [31:0] t;
    begin
        t = (P_HEIGHT - (who ? pad1_h : pad0_h)) >>> 16;
        travel_of = t[7:0];
    end
endfunction

// paddle 0..255 -> 0..corsa-1: p * corsa / 256 con somme e shift (nessun moltiplicatore)
function [7:0] paddle_px(input [7:0] p, input [7:0] travel);
    reg [15:0] s;
    integer b;
    begin
        s = 16'd0;
        for (b = 0; b < 8; b = b + 1)
            if (travel[b]) s = s + ({8'd0, p} << b);
        paddle_px = s[15:8];
    end
endfunction

// pixel tra il bordo alto e la racchetta (y del centro in Q16.16)
function signed [11:0] pad_top_px(input signed [31:0] y, input signed [31:0] h);
    reg signed [31:0] d;
    begin
        d = P_HEIGHT - (h >>> 1) - y;
        pad_top_px = d[27:16];
    end
endfunction

reg  [1:0]        spin_q = 2'b00;              // bit 8 degli spinner al ciclo precedente
reg  signed [11:0] spin_acc [0:1];             // spostamenti dall'ultimo frame
reg  signed [11:0] spin_step [0:1];            // spostamento del frame, già scalato
reg  [7:0]        spin_off [0:1];              // posizione dello spinner per i tick del frame
reg  [1:0]        spin_on = 2'b00;             // lo spinner si è mosso in questo frame
reg  signed [11:0] t_spin;
integer           sp;

// spostamento arrivato in questo ciclo (0 se lo spinner non ha mandato dati)
wire signed [11:0] spin_in0 = (spinner0[8] != spin_q[0]) ? {{4{spinner0[7]}}, spinner0[7:0]} : 12'sd0;
wire signed [11:0] spin_in1 = (spinner1[8] != spin_q[1]) ? {{4{spinner1[7]}}, spinner1[7:0]} : 12'sd0;

initial begin
    spin_acc[0] = 12'sd0;
    spin_acc[1] = 12'sd0;
    spin_step[0] = 12'sd0;
    spin_step[1] = 12'sd0;
    spin_off[0] = 8'd0;
    spin_off[1] = 8'd0;
end

function signed [11:0] spin_scale(input signed [11:0] a, input [1:0] speed);
    case (speed)
        2'd1: spin_scale = a <<< 1;
        2'd2: spin_scale = a <<< 2;
        2'd3: spin_scale = a >>> 1;
        default: spin_scale = a;
    endcase
endfunction

// il giocatore `who` guida la palla con STEER
function steering(input who);
    steering = nxt && next_flags[5] && next_flags[6] == who;
endfunction

// comandi da paddle e spinner, uniti a quelli del joystick: bit 6 e posizione, oppure su/giù
function [7:0] enc_bits(input [7:0] bits, input who);
    begin
        enc_bits = bits;
        if (control == C_PADDLE) begin
            enc_bits[6] = 1'b1;
        end else if (control == C_SPINNER && spin_on[who]) begin
            if (steering(who)) begin
                enc_bits[0] = spin_step[who] < 0;          // manopola verso l'alto
                enc_bits[1] = spin_step[who] > 0;
            end else begin
                enc_bits[6] = 1'b1;
            end
        end
    end
endfunction

function [7:0] enc_off(input who);
    enc_off = (control == C_PADDLE) ? paddle_px(who ? paddle1 : paddle0, travel_of(who)) : spin_off[who];
endfunction

// scatto in avanti e bonus si attivano sul fronte del tasto e valgono per un solo tick
reg [1:0] fwd_q = 2'b00, sel_q = 2'b00, act_q = 2'b00;
reg [1:0] fwd_pending = 2'b00, sel_pending = 2'b00, act_pending = 2'b00;
wire [1:0] fwd_edge = {joy1[4], joy0[4]} & ~fwd_q;

// --------------------------------------------------------- gesti delle mosse speciali
//
// Un riconoscitore per giocatore (move_gesture): joystick sempre, manopola con Paddle control su
// paddle o spinner. Lo scatto che completa un gesto diventa la mossa (codice per il prossimo tick, al
// posto dello scatto) solo se la mossa può partire adesso; il core comunque, nello stesso tick,
// farebbe prima l'eventuale colpo con lo scatto e poi la mossa.
reg  [16:0] g_div = 17'd0;                     // età delle direzioni del joystick: passi di 6,6 ms
reg  [7:0]  g_pad_prev [0:1];                  // paddle al frame prima
reg  signed [11:0] g_spin [0:1];               // spinner: spostamenti del frame
reg  [1:0]  spc_pending [0:1];                 // mossa riconosciuta, per il prossimo tick
wire [1:0]  g_code [0:1];
initial begin
    g_pad_prev[0] = 8'd0;
    g_pad_prev[1] = 8'd0;
    g_spin[0] = 12'sd0;
    g_spin[1] = 12'sd0;
    spc_pending[0] = 2'd0;
    spc_pending[1] = 2'd0;
end

// spostamento della manopola nel frame, positivo verso il basso, limitato a 9 bit e segno
function signed [9:0] knob_delta(input who);
    reg signed [12:0] d;
    reg signed [11:0] sc;
    begin
        sc = spin_scale(g_spin[who], spin_speed);
        if (control == C_PADDLE)
            d = $signed({5'd0, who ? paddle1 : paddle0}) - $signed({5'd0, g_pad_prev[who]});
        else
            d = {sc[11], sc};
        knob_delta = (d > 13'sd511) ? 10'sd511 : (d < -13'sd511) ? -10'sd511 : d[9:0];
    end
endfunction

// la mossa può partire adesso per il giocatore umano `who` (come Match::next_special e special_ready)
function move_ready(input who);
    reg [31:0] sw;
    begin
        sw = who ? super1 : super0;
        move_ready = sup && mode == M_GAME && !counting && serve_timer == 32'd0 && !(match_cpu && who != ch_cpu_left) &&
                     sw[7:0] >= P_SUPER_COST && sw[11:8] == 4'd0 &&
                     (who ? player1[19:16] : player0[19:16]) == 4'd8;
    end
endfunction

always @(posedge clk) begin
    g_div <= g_div + 17'd1;
    if (frame_start) begin
        g_pad_prev[0] <= paddle0;
        g_pad_prev[1] <= paddle1;
        g_spin[0] <= spin_in0;
        g_spin[1] <= spin_in1;
    end else begin
        g_spin[0] <= g_spin[0] + spin_in0;
        g_spin[1] <= g_spin[1] + spin_in1;
    end
end

move_gesture gesture_left (
    .clk(clk), .reset(match_reset), .slow(g_div == 17'd0), .frame(frame_start), .facing_left(1'b0),
    .joy(joy0[3:0]), .knob_on(control != 2'd0), .knob_d(knob_delta(1'b0)),
    .press(fwd_edge[0]), .allow(move_ready(1'b0)), .code(g_code[0])
);
move_gesture gesture_right (
    .clk(clk), .reset(match_reset), .slow(g_div == 17'd0), .frame(frame_start), .facing_left(1'b1),
    .joy(joy1[3:0]), .knob_on(control != 2'd0), .knob_d(knob_delta(1'b1)),
    .press(fwd_edge[1]), .allow(move_ready(1'b1)), .code(g_code[1])
);
// lati comandati dalla CPU: tutti e due nella demo, contro un giocatore quello opposto al suo
wire      cpu_l = mode == M_DEMO || (mode == M_GAME && match_cpu && ch_cpu_left);
wire      cpu_r = mode == M_DEMO || (mode == M_GAME && match_cpu && !ch_cpu_left);

reg [2:0] ticks_left = 3'd0;
reg       wait_start = 1'b0;      // il core alza busy un ciclo dopo lo step
reg [15:0] frame_events = 16'd0;
reg       events_ready = 1'b0;

always @(posedge clk) begin
    step <= 1'b0;
    events_ready <= 1'b0;
    fwd_q <= {joy1[4], joy0[4]};
    sel_q <= {joy1[6], joy0[6]};
    act_q <= {joy1[7], joy0[7]};
    // lo scatto che completa un gesto diventa la mossa
    fwd_pending <= fwd_pending | (fwd_edge & ~{g_code[1] != 2'd0, g_code[0] != 2'd0});
    if (g_code[0] != 2'd0) spc_pending[0] <= g_code[0];
    if (g_code[1] != 2'd0) spc_pending[1] <= g_code[1];
    sel_pending <= sel_pending | ({joy1[6], joy0[6]} & ~sel_q);
    act_pending <= act_pending | ({joy1[7], joy0[7]} & ~act_q);
    // spinner: si sommano gli spostamenti a ogni nuovo dato
    spin_q <= {spinner1[8], spinner0[8]};
    spin_acc[0] <= spin_acc[0] + spin_in0;
    spin_acc[1] <= spin_acc[1] + spin_in1;

    if (match_reset) begin
        ticks_left <= 3'd0;
        wait_start <= 1'b0;
        fwd_pending <= 2'b00;
        sel_pending <= 2'b00;
        act_pending <= 2'b00;
        spc_pending[0] <= 2'd0;
        spc_pending[1] <= 2'd0;
    end else if (frame_start) begin
        ticks_left <= playing ? TICKS_PER_FRAME : 3'd0;
        frame_events <= 16'd0;
    end else if (wait_start) begin
        wait_start <= 1'b0;
    end else if (!busy && ticks_left != 3'd0) begin
        if (ticks_left != TICKS_PER_FRAME)
            frame_events <= frame_events | tick_events;   // eventi del tick appena finito
        if (ticks_left == TICKS_PER_FRAME) begin
            // primo tick del frame: lo spostamento dello spinner diventa la posizione per tutto il frame
            // (lo spostamento arrivato proprio ora resta per il frame dopo)
            for (sp = 0; sp < 2; sp = sp + 1) begin
                t_spin = spin_scale(spin_acc[sp], spin_speed);
                spin_step[sp] <= t_spin;
                spin_on[sp] <= t_spin != 0;
                t_spin = pad_top_px(sp ? pad1_y : pad0_y, sp ? pad1_h : pad0_h) + t_spin;
                spin_off[sp] <= (t_spin < 0) ? 8'd0 : (t_spin > $signed({4'd0, travel_of(sp[0])})) ? travel_of(sp[0]) :
                                t_spin[7:0];
                spin_acc[sp] <= sp ? spin_in1 : spin_in0;
            end
        end
        // per i lati della CPU i comandi li calcola la logica (Cpu::input), dallo stato prima del tick
        tick_inputs <= {(cpu_r ? 8'd0 : enc_bits(player_bits(joy1, tap_fast[1], fwd_pending[1], sel_pending[1], act_pending[1]), 1'b1)),
                        (cpu_l ? 8'd0 : enc_bits(player_bits(joy0, tap_fast[0], fwd_pending[0], sel_pending[0], act_pending[0]), 1'b0))};
        tick_offsets <= {cpu_r ? 8'd0 : enc_off(1'b1), cpu_l ? 8'd0 : enc_off(1'b0)};
        tick_specials <= {cpu_r ? 2'd0 : spc_pending[1], cpu_l ? 2'd0 : spc_pending[0]};
        tick_cpu <= {cpu_r, cpu_l};
        spc_pending[0] <= 2'd0;
        spc_pending[1] <= 2'd0;
        fwd_pending <= 2'b00;
        sel_pending <= 2'b00;
        act_pending <= 2'b00;
        step <= 1'b1;
        wait_start <= 1'b1;
        ticks_left <= ticks_left - 3'd1;
        if (ticks_left == 3'd1) events_ready <= 1'b1;
    end
end

// eventi dell'ultimo tick del frame, raccolti quando il core torna libero
reg collect_last = 1'b0;
reg [15:0] sound_events = 16'd0;
reg sound_trigger = 1'b0;

always @(posedge clk) begin
    sound_trigger <= 1'b0;
    if (events_ready) collect_last <= 1'b1;
    if (collect_last && !busy && !wait_start && !step) begin
        collect_last <= 1'b0;
        sound_events <= frame_events | tick_events;
        sound_trigger <= 1'b1;
    end
end

// fine partita: chi arriva per primo a 11 in due, vite finite in singolo
always @(posedge clk) begin
    if (match_reset) lives <= LIVES;
    else if (sound_trigger && mode == M_GAME && !two && sound_events[3] && lives != 2'd0) lives <= lives - 2'd1;
end
wire [15:0] points_to_win = ch_active ? {11'd0, rung_points(ch_level)} : POINTS_TO_WIN;
assign game_over_now = sound_trigger &&
    (two ? (score0 >= points_to_win || score1 >= points_to_win) : (sound_events[3] && lives == 2'd1));

// Punti arcade di CHALLENGE (Score::on_tick): alla fine di ogni tick colpi del giocatore (la palla
// ora si allontana dal suo lato), scatti, SUPER e punti segnati, per il moltiplicatore dello
// scambio (1 + colpi / 4, al massimo 8); premi a livello vinto. Moltiplicazioni con shift e somme.
// Nella sfida tra due giocatori non si contano punti: alla fine (Score::after_duel) il campione che
// vince prende il premio del livello, lo sfidante che vince parte da quel premio (e da un miglior
// punteggio nuovo).
reg        busy_q = 1'b0;
reg [3:0]  mode_q2 = M_BOOT;
reg        ch_active_q = 1'b0;
reg [15:0] score0_q = 16'd0;              // punti del giocatore prima del tick
wire [15:0] score_me = ch_side ? score1 : score0;    // punti del giocatore e della CPU
wire [15:0] score_cpu = ch_side ? score0 : score1;
reg [7:0]  ch_rally = 8'd0;
reg [23:0] ch_score = 24'd0;
reg [23:0] ch_best_r = 24'd0;
reg [3:0]  ch_best_lvl = 4'd1;
reg        ch_perfect = 1'b0;
reg [23:0] end_score = 24'd0, end_bonus = 24'd0;   // finale: punti prima del premio del campione, premio
reg [7:0]  rally_n;
reg [3:0]  m_n;
reg [23:0] gained, total;
function [3:0] mult_of(input [7:0] rally);
    mult_of = (rally >= 8'd28) ? 4'd8 : 4'd1 + {1'b0, rally[4:2]};
endfunction
wire [3:0] ch_mult = mult_of(ch_rally);
always @(posedge clk) begin
    busy_q <= busy;
    mode_q2 <= mode;
    ch_active_q <= ch_active;
    if (ch_active && !ch_active_q) begin
        // nuova partita CHALLENGE
        ch_score <= 24'd0;
        ch_best_r <= 24'd0;
        ch_best_lvl <= 4'd1;
    end else if (match_reset) begin
        ch_rally <= 8'd0;
        score0_q <= 16'd0;
    end else if (duel_end) begin
        // la scalata riprende dopo la sfida
        if (duel_champ)
            ch_score <= ch_score + ch_win_bonus(ch_level);
        else begin
            ch_score <= {8'd0, ch_win_bonus(ch_level)};
            ch_best_r <= 24'd0;
            ch_best_lvl <= {1'b0, ch_level} + 4'd1;
        end
    end else if (ch_active && !duel && mode == M_GAME && busy_q && !busy) begin
        // tick finito
        rally_n = ch_rally;
        gained = 24'd0;
        if (tick_events[1] || tick_events[2] || tick_events[6]) begin
            if (rally_n != 8'hFF) rally_n = rally_n + 8'd1;
            m_n = mult_of(rally_n);
            if ((ball_vx > 0) != ch_side) begin
                gained = gained + {17'd0, m_n, 3'd0} + {19'd0, m_n, 1'b0};               // 10 x
                if (tick_events[2]) gained = gained + CH_BOOST;
                if (tick_events[6]) gained = gained + CH_SUPER;
            end
        end
        m_n = mult_of(rally_n);
        if (tick_events[3]) begin
            if (score_me > score0_q) gained = gained + {14'd0, m_n, 6'd0} + {15'd0, m_n, 5'd0} + {18'd0, m_n, 2'd0};  // 100 x
            rally_n = 8'd0;
        end
        ch_rally <= rally_n;
        score0_q <= score_me;
        ch_score <= ch_score + gained;
    end else if (mode != mode_q2 && ch_active) begin
        if (mode == M_CLEAR || mode == M_ENDING) begin
            // livello vinto: premi, e il miglior punteggio con il livello raggiunto. Nel finale il
            // premio dell'ultimo livello è il CHAMPION BONUS (Score::win_bonus, come su PC): il
            // finale mostra i punti prima, il premio e il totale
            ch_perfect <= score_cpu == 16'd0;
            total = ch_score + ch_win_bonus(ch_level) + (score_cpu == 16'd0 ? ch_perfect_bonus(ch_level) : 16'd0);
            end_score <= ch_score;
            end_bonus <= total - ch_score;
            ch_score <= total;
            if (total > ch_best_r) begin
                ch_best_r <= total;
                ch_best_lvl <= (ch_level == CH_LEVELS - 1) ? 4'd8 : {1'b0, ch_level} + 4'd2;
            end
        end else if (mode == M_CONT || mode == M_CHALLENGER) begin
            // continue, o sfida: il punteggio del campione conta per la classifica (se perde la sfida)
            if (ch_score > ch_best_r) begin
                ch_best_r <= ch_score;
                ch_best_lvl <= {1'b0, ch_level} + 4'd1;
            end
        end else if (mode == M_INTRO && mode_q2 == M_CONT) begin
            ch_score <= 24'd0;                               // continue: punti da zero
        end
    end
end
assign ch_best = ch_best_r;

// secondi del continue: da 9 a 0, un passo ogni 60 frame (niente divisioni)
reg [3:0] ch_cont_digit = 4'd9;
reg [5:0] ch_cont_sub = 6'd0;
always @(posedge clk) begin
    if (mode != M_CONT) begin
        ch_cont_digit <= 4'd9;
        ch_cont_sub <= 6'd0;
    end else if (frame_start) begin
        if (ch_cont_sub == 6'd59) begin
            ch_cont_sub <= 6'd0;
            if (ch_cont_digit != 4'd0) ch_cont_digit <= ch_cont_digit - 4'd1;
        end else
            ch_cont_sub <= ch_cont_sub + 6'd1;
    end
end
assign ch_best_level = ch_best_lvl;

// punti in BCD per il disegno (doppio dabble, un bit per ciclo: shift e somme)
wire [27:0] ch_score_bcd;
bin_to_bcd score_digits (.clk(clk), .bin(ch_score), .bcd(ch_score_bcd));
bin_to_bcd best_digits (.clk(clk), .bin(ch_best_r), .bcd(ch_best_bcd));

// lampo bianco di 3 frame quando viene segnato un punto
reg [1:0] flash_count = 2'd0;
always @(posedge clk) begin
    if (match_reset) flash_count <= 2'd0;
    else if (sound_trigger && sound_events[3]) flash_count <= 2'd3;
    else if (frame_start && flash_count != 2'd0) flash_count <= flash_count - 2'd1;
end

// palla che lampeggia in attesa della battuta (come nel gioco desktop: 8 cambi al secondo);
// in NEXT la palla fantasma si vede solo a lampi e la cometa la disegna next_render
wire [31:0] blink_phase = (serve_timer * 32'd2185) >> 16;     // serve_timer / 30
// (il firmware calcola Next::ball_hidden: il modulo del tick in HDL sforava il clock di sistema)
wire ghost_hidden = nxt && ghost_hide;
wire comet = nxt && next_flags[2] && next_flags[4:3] == 2'd2;
wire ball_visible = (serve_timer == 32'd0 || !blink_phase[0]) && !ghost_hidden && !comet;

// NEXT: hit-stop del SUPER (schermo invertito, poi scossa), racchette armate o che ruotano
wire [15:0] freeze = next_flags[31:16];
wire hit_flash = nxt && freeze != 16'd0 && freeze * 3 > P_HITSTOP_TICKS * 2;
wire signed [9:0] shake = (nxt && freeze != 16'd0) ? (freeze[3] ? -10'sd2 : 10'sd2) : 10'sd0;
wire [1:0] pad_spin = {nxt && player1[19:16] == 4'd5 && player1[15:14] == 2'd0,
                       nxt && player0[19:16] == 4'd5 && player0[15:14] == 2'd0};
wire armed_blink = !logic_tick[4];                             // (tick / 16) % 2 == 0
// BULLET: armato (in attesa della palla) la racchetta di chi l'ha attivato ha un bordo giallo che
// lampeggia piano; scattato (bullet time, bul_on) il bordo resta fisso e ciò che è bianco diventa
// grigio (palla, linea centrale, punteggi, capsule, racchetta dell'avversario), con un alone grigio
// che sfuma attorno a palla, racchetta avversaria, linea centrale e capsule: uno sfocato
// approssimato, profondo bul_blur pixel (sale da 1 a 3 durante la rampa d'entrata, bul_ramp)
wire       bul_arm = nxt && next_flags[11];
wire       bul_on = nxt && next_flags[13];
wire       bul_side = next_flags[12];
wire       bul_ramp = bullet_timer != 16'd0;
wire [1:0] bul_blur = !bul_on ? 2'd0 :
                      ({16'd0, bullet_timer} > (P_BULLET_RAMP_TICKS * 2) / 3) ? 2'd1 :
                      ({16'd0, bullet_timer} > P_BULLET_RAMP_TICKS / 3) ? 2'd2 : 2'd3;
wire [1:0] bul_cold = {bul_on && !bul_side, bul_on && bul_side};
wire [1:0] pad_gray = {nxt && player1[19:16] != 4'd8 && armed_blink,
                       nxt && player0[19:16] != 4'd8 && armed_blink} | bul_cold;

// scritta "P1 SMASH!" per 1,2 s quando un giocatore attiva un bonus; con le mosse speciali "P1
// STRAIGHT SHOT!" quando la mossa parte (1,2 s) e di nuovo al colpo (0,8 s), con "MAX" davanti al
// livello 2 (come special_title di next_ui.rs). La mossa partita nel frame è quella pagata: la barra
// è scesa di almeno mezza mossa (spende uno o due settori, 32 o 64; nel frame cresce al più di 12),
// e la mossa e il livello sono quelli che il giocatore ha armato adesso. Quando RISING STRIKE
// s'impenna (bit 14 di super0 che torna a zero con la mossa ancora in volo) next_render mostra un
// quadrato nel punto per 12 frame.
reg [1:0] prev_count [0:1];
reg       label_player = 1'b0;
reg [2:0] label_bonus = 3'd0;
// BULLET appena attivato dal giocatore `who`: armato adesso e non alla fine del frame prima
reg       prev_bullet = 1'b0;
function bullet_new(input who);
    bullet_new = next_flags[11] && next_flags[12] == who && !prev_bullet;
endfunction
reg [1:0] label_move = 2'd0;               // 0 bonus, 1 STRAIGHT SHOT, 2 RISING STRIKE
reg       label_max = 1'b0;                // mossa di livello 2: "MAX" davanti al nome
reg [6:0] label_frames = 7'd0;
reg [7:0] prev_meter [0:1];
reg       prev_rise = 1'b0;                // RISING STRIKE in volo, impennata da arrivare
reg [3:0] rise_frames = 4'd0;              // quadrato dove s'è impennata
wire [1:0] paid = {super1[7:0] + (P_SUPER_COST >>> 1) <= prev_meter[1], super0[7:0] + (P_SUPER_COST >>> 1) <= prev_meter[0]};
always @(posedge clk) begin
    if (match_reset) begin
        label_frames <= 7'd0;
        prev_count[0] <= 2'd0;
        prev_count[1] <= 2'd0;
        prev_meter[0] <= 8'd0;
        prev_meter[1] <= 8'd0;
        prev_bullet <= 1'b0;
        prev_rise <= 1'b0;
        rise_frames <= 4'd0;
    end else begin
        if (frame_start && label_frames != 7'd0) label_frames <= label_frames - 7'd1;
        if (frame_start && rise_frames != 4'd0) rise_frames <= rise_frames - 4'd1;
        if (sound_trigger) begin
            prev_count[0] <= reserve_count(player0);
            prev_count[1] <= reserve_count(player1);
            prev_meter[0] <= super0[7:0];
            prev_meter[1] <= super1[7:0];
            prev_bullet <= next_flags[11];
            prev_rise <= super0[14];
            if (sup && prev_rise && !super0[14] && next_flags[10:9] == 2'd2) rise_frames <= 4'd12;
            if (sup && sound_events[12]) begin
                // colpo con la mossa: chi ha colpito manda la palla verso l'altro; livello del tiro in volo
                label_player <= ball_vx < 0;
                label_move <= next_flags[10:9];
                label_max <= super0[13];
                label_frames <= 7'd48;
            end else if (sup && (sound_events[10] || sound_events[11]) && paid != 2'b00) begin
                // livelli armati: STRAIGHT SHOT nei bit 8-9, RISING STRIKE nei bit 10-11 (2 = MAX)
                label_player <= !paid[0];
                label_move <= ((paid[0] ? super0[9:8] : super1[9:8]) != 2'd0) ? 2'd1 : 2'd2;
                label_max <= paid[0] ? (super0[9] || super0[11]) : (super1[9] || super1[11]);
                label_frames <= 7'd72;
            end else if (nxt && sound_events[5]) begin
                label_move <= 2'd0;
                label_player <= reserve_count(player0) < prev_count[0] ? 1'b0 : 1'b1;
                // SLOW e BULLET non restano armati nel giocatore: il BULLET si riconosce da chi lo
                // ha da questo frame
                label_bonus <= (reserve_count(player0) < prev_count[0])
                    ? (player0[19:16] == 4'd8 ? (bullet_new(1'b0) ? 3'd7 : 3'd2) : player0[18:16])
                    : (player1[19:16] == 4'd8 ? (bullet_new(1'b1) ? 3'd7 : 3'd2) : player1[18:16]);
                label_frames <= 7'd72;
            end
        end
    end
end

// salto del TELEPORT: animazione dei portali dalla y della racchetta alla fine del frame
// precedente (la logica la sposta in un tick solo); l'avanzamento segue la palla (next_render) e
// il salto finisce quando la racchetta è tutta fuori (palla a 2/10 del campo dal suo bordo), al
// colpo o al punto
localparam integer WARP_OUT_PX = 64;
reg       warp_on = 1'b0;
reg       warp_side = 1'b0;
reg signed [31:0] warp_from = 32'sd0, last_y0 = 32'sd0, last_y1 = 32'sd0;
function warp_done(input who);
    reg [9:0] d;
    begin
        d = who ? FIELD_W - ball_x[25:16] : ball_x[25:16];
        warp_done = d <= WARP_OUT_PX || (who ? player1[19:16] : player0[19:16]) != 4'd0 ||
                    (who ? ball_vx <= 0 : ball_vx >= 0);
    end
endfunction
always @(posedge clk) begin
    if (match_reset) begin
        warp_on <= 1'b0;
    end else if (sound_trigger) begin
        last_y0 <= pad0_y;
        last_y1 <= pad1_y;
        if (!warp_on && nxt && sound_events[7]) begin
            warp_on <= !warp_done(ball_vx > 0);
            warp_side <= ball_vx > 0;                      // salta la racchetta verso cui va la palla
            warp_from <= (ball_vx > 0) ? last_y1 : last_y0;
        end else if (warp_on && warp_done(warp_side)) begin
            warp_on <= 1'b0;
        end
    end
end
wire [1:0] warp_hide = {warp_on && warp_side, warp_on && !warp_side};

// Tipi di racchetta a schermo: RUSH, quando scatta in avanti, lascia per 15 frame (0,25 s) le
// immagini della racchetta tra casa e dove si trova, che sfumano in tre passi, e vibra di un pixel; il settore del muro del GUARDIAN che rimanda la palla lampeggia per
// 18 frame, poi non c'è più: è quello sparito dalla maschera (aux, bit 0-4) nel frame dell'evento;
// TWIST, inclinata, la disegna next_render.
localparam [2:0] K_TWIST = 3'd3, K_RUSH = 3'd5;
reg [3:0] rush_frames [0:1];
reg [1:0] rush_home = 2'b11;
reg [4:0] barrier_frames [0:1];
reg [4:0] wall_last [0:1];      // maschera dei 5 settori al frame prima
reg [4:0] wall_hit [0:1];       // settore appena colpito (lampeggia)
wire [4:0] wall0 = aux0[4:0], wall1 = aux1[4:0];
// lo scatto che ha intercettato la palla nel frame: la racchetta a schermo arriva subito
reg [1:0] dash_snap = 2'b00;
integer   rk;
always @(posedge clk) begin
    if (match_reset) begin
        for (rk = 0; rk < 2; rk = rk + 1) begin
            rush_frames[rk] <= 4'd0;
            barrier_frames[rk] <= 5'd0;
        end
        rush_home <= 2'b11;
        dash_snap <= 2'b00;
    end else begin
        if (frame_start) begin
            dash_snap <= 2'b00;
            for (rk = 0; rk < 2; rk = rk + 1) begin
                if (rush_frames[rk] != 4'd0) rush_frames[rk] <= rush_frames[rk] - 4'd1;
                if (barrier_frames[rk] != 5'd0) barrier_frames[rk] <= barrier_frames[rk] - 5'd1;
            end
        end
        if (sound_trigger) begin
            rush_home <= {pad1_x == P_WIDTH - P_PAD_START_POS, pad0_x == P_PAD_START_POS};
            if (sound_events[1] || sound_events[2])
                dash_snap <= {rush_home[1] && pad1_x != P_WIDTH - P_PAD_START_POS && ball_vx < 0,
                              rush_home[0] && pad0_x != P_PAD_START_POS && ball_vx > 0};
            if (rush_home[0] && pad0_x != P_PAD_START_POS) rush_frames[0] <= 4'd15;
            if (rush_home[1] && pad1_x != P_WIDTH - P_PAD_START_POS) rush_frames[1] <= 4'd15;
            wall_last[0] <= wall0;
            wall_last[1] <= wall1;
            if (nxt && sound_events[9] && (wall_last[0] & ~wall0) != 5'd0) begin
                barrier_frames[0] <= 5'd18;
                wall_hit[0] <= wall_last[0] & ~wall0;
            end
            if (nxt && sound_events[9] && (wall_last[1] & ~wall1) != 5'd0) begin
                barrier_frames[1] <= 5'd18;
                wall_hit[1] <= wall_last[1] & ~wall1;
            end
        end
    end
end
wire [1:0] rush_kind = {nxt && kind1[2:0] == K_RUSH, nxt && kind0[2:0] == K_RUSH};
wire [1:0] twist_kind = {nxt && kind1[2:0] == K_TWIST, nxt && kind0[2:0] == K_TWIST};
// intensità delle immagini del RUSH: 3 appena partito, poi 2, 1 e 0 (niente)
function [1:0] rush_level(input [3:0] f);
    rush_level = (f > 4'd10) ? 2'd3 : (f > 4'd5) ? 2'd2 : (f != 4'd0) ? 2'd1 : 2'd0;
endfunction
wire [3:0] rush_fade = {rush_kind[1] ? rush_level(rush_frames[1]) : 2'd0,
                        rush_kind[0] ? rush_level(rush_frames[0]) : 2'd0};
wire [1:0] barrier_flash = {barrier_frames[1] != 5'd0, barrier_frames[0] != 5'd0};
wire [4:0] wall_hit0 = wall_hit[0], wall_hit1 = wall_hit[1];
// vibrazione del RUSH: un pixel avanti e indietro, (tick / 8) % 2 come nel gioco Rust
wire signed [31:0] rush_shake = logic_tick[3] ? 32'sd65536 : 32'sd0;

// NEXT: la COMETA spacca la rete come su PC. I trattini della mezzeria vicini alla palla
// schizzano di lato nel verso del tiro e tornano al loro posto in circa un secondo: lo
// scostamento è in quarti di pixel e cala di un quarto a ogni frame.
localparam integer DASHES = 30, FIELD_W = P_WIDTH >>> 16, FIELD_H = P_HEIGHT >>> 16;
reg signed [7:0]  dash_kick [0:DASHES-1];
reg signed [10:0] comet_prev_x = 11'sd0;
reg signed [10:0] d_dy, d_abs;
wire signed [10:0] comet_x = $signed({1'b0, ball_x[25:16]});
wire signed [10:0] comet_y = FIELD_H - $signed({1'b0, ball_y[25:16]});
// la palla passa la mezzeria fra due frame, o ci sta sopra
wire comet_on_net = comet && ((comet_prev_x < FIELD_W / 2) != (comet_x < FIELD_W / 2) ||
                              (comet_x - FIELD_W / 2 < 6 && comet_x - FIELD_W / 2 > -6));
wire [179:0] dash_off;
integer di;
always @(posedge clk) begin
    if (match_reset) begin
        for (di = 0; di < DASHES; di = di + 1) dash_kick[di] <= 8'sd0;
    end else if (frame_start) begin
        comet_prev_x <= comet_x;
        for (di = 0; di < DASHES; di = di + 1) begin
            d_dy = di * 8 + 2 - comet_y;                  // centro del trattino meno la palla
            d_abs = (d_dy < 0) ? -d_dy : d_dy;
            if (comet_on_net && d_abs < 16 && dash_kick[di] == 8'sd0)
                dash_kick[di] <= (ball_vx > 0) ? (8'sd13 - (d_abs >>> 1)) <<< 2 : -((8'sd13 - (d_abs >>> 1)) <<< 2);
            else if (dash_kick[di] > 8'sd0)
                dash_kick[di] <= dash_kick[di] - 8'sd1;
            else if (dash_kick[di] < 8'sd0)
                dash_kick[di] <= dash_kick[di] + 8'sd1;
        end
    end
end
genvar dg;
generate
    for (dg = 0; dg < DASHES; dg = dg + 1) begin : dash_bus
        assign dash_off[6 * dg +: 6] = dash_kick[dg][7:2];
    end
endgenerate

// ------------------------------------------------------------------ disegno

// Scatto in avanti a schermo: la racchetta raggiunge la nuova x in circa 5 frame, dimezzando
// la distanza a ogni frame (almeno 6 pixel). Solo grafica: la logica resta istantanea come
// nel core Rust. Distanze oltre 100 pixel (nuova partita) si saltano subito, e lo scatto che
// intercetta la palla arriva subito (dash_snap), altrimenti la palla rimbalzerebbe prima.
localparam signed [31:0] SLIDE_MIN = 32'sd6 <<< 16;
localparam signed [31:0] SLIDE_SNAP = 32'sd100 <<< 16;

function signed [31:0] slide(input signed [31:0] cur, input signed [31:0] target);
    reg signed [31:0] d, delta;
    begin
        d = target - cur;
        delta = d >>> 1;
        if (d > SLIDE_SNAP || d < -SLIDE_SNAP) delta = d;
        else if (d > 0 && delta < SLIDE_MIN) delta = (d < SLIDE_MIN) ? d : SLIDE_MIN;
        else if (d < 0 && delta > -SLIDE_MIN) delta = (d > -SLIDE_MIN) ? d : -SLIDE_MIN;
        slide = cur + delta;
    end
endfunction

reg signed [31:0] draw0_x = 32'sd0, draw1_x = 32'sd0;
wire signed [31:0] next0_x = dash_snap[0] ? pad0_x : slide(draw0_x, pad0_x);
wire signed [31:0] next1_x = dash_snap[1] ? pad1_x : slide(draw1_x, pad1_x);
// colpo di una mossa speciale (come KICK_SECONDS di next_ui.rs): per KICK_FRAMES frame la
// racchetta di chi l'ha fatto rincula verso il fondo e torna; lampo, onda d'urto e (MAX) immagini
// della racchetta li disegna next_render
localparam [4:0] KICK_FRAMES = 5'd18;
reg [4:0] kick_t [0:1];
reg       kick_rise [0:1], kick_max [0:1];
initial begin
    kick_t[0] = 5'd0;
    kick_t[1] = 5'd0;
end
always @(posedge clk) begin
    if (match_reset) begin
        kick_t[0] <= 5'd0;
        kick_t[1] <= 5'd0;
    end else begin
        if (frame_start && kick_t[0] != 5'd0) kick_t[0] <= kick_t[0] - 5'd1;
        if (frame_start && kick_t[1] != 5'd0) kick_t[1] <= kick_t[1] - 5'd1;
        // chi ha colpito manda la palla verso l'altro
        if (sound_trigger && sup && sound_events[12]) begin
            kick_t[ball_vx < 0] <= KICK_FRAMES;
            kick_rise[ball_vx < 0] <= next_flags[10:9] == 2'd2;
            kick_max[ball_vx < 0] <= super0[13];
        end
    end
end
// rinculo in pixel: ampiezza (3, 5 con la MAX) per (frame rimasti / KICK_FRAMES)^2, circa
function [3:0] recoil(input [4:0] t, input mx);
    reg [11:0] q;
    begin
        q = {7'd0, t} * {7'd0, t};
        q = mx ? (q << 2) + q : (q << 1) + q;
        recoil = q[11:8];
    end
endfunction
wire signed [31:0] kick0_dx = -$signed({12'd0, recoil(kick_t[0], kick_max[0]), 16'd0});
wire signed [31:0] kick1_dx = $signed({12'd0, recoil(kick_t[1], kick_max[1]), 16'd0});
wire signed [31:0] show0_x = next0_x + (rush_kind[0] ? rush_shake : 32'sd0) + (nxt ? kick0_dx : 32'sd0);
wire signed [31:0] show1_x = next1_x + (rush_kind[1] ? rush_shake : 32'sd0) + (nxt ? kick1_dx : 32'sd0);
always @(posedge clk) begin
    if (snapshot) begin
        draw0_x <= next0_x;
        draw1_x <= next1_x;
    end
end

// barra evidenziata: la mossa si può fare adesso (come move_ready, anche per la CPU e nella demo)
function move_avail(input who);
    reg [31:0] sw;
    begin
        sw = who ? super1 : super0;
        move_avail = sup && serve_timer == 32'd0 && sw[7:0] >= P_SUPER_COST && sw[11:8] == 4'd0 &&
                     (who ? player1[19:16] : player0[19:16]) == 4'd8;
    end
endfunction

wire [23:0] game_rgb, attract_rgb, next_rgb;
wire        next_opaque, game_top, game_bg;
wire [1:0]  next_halo;
wire [8:0]  game_hc = hc + shake[8:0];                    // scossa dell'hit-stop
// GAME OVER: in due chi ha vinto, contro la CPU dal punto di vista del giocatore (in CHALLENGE
// anche a destra): 1 P1 WINS, 2 P2 WINS, 3 YOU WIN, 4 CPU WINS
wire [2:0]  over_winner = !two ? 3'd0 : match_cpu ? (((score0 >= score1) != ch_cpu_left) ? 3'd3 : 3'd4) :
                          (score0 >= score1 ? 3'd1 : 3'd2);

pong_render render (
    .clk(clk), .snapshot(snapshot), .hc(game_hc), .vc(vc),
    .two(two), .evo(evo), .flash(flash_count != 2'd0 || hit_flash),
    .ball_x(ball_x), .ball_y(ball_y), .ball_r(ball_r), .ball_visible(ball_visible),
    .pad0_x(show0_x), .pad0_y(pad0_y), .pad1_x(show1_x), .pad1_y(pad1_y),
    .pad0_h(pad0_h), .pad1_h(pad1_h),
    .pad0_boost_h(pad0_boost_h), .pad1_boost_h(pad1_boost_h),
    .score0(score0), .score1(score1), .best(best),
    .lives(lives), .show_lives(!two && (mode == M_GAME || mode == M_GAME_OVER)),
    .overlay(mode == M_DEMO ? 2'd1 : mode == M_GAME_OVER ? 2'd2 : 2'd0), .demo_mode(demo_kind),
    .winner(over_winner), .win_solo(over_winner == 3'd3 || (ch_active && !duel && over_winner == 3'd4)),
    .winner_accent(nxt), .ball_accent(nxt && (next_flags[2] || next_flags[10:9] != 2'd0)),
    .free_play(free_play), .credits(credits), .blink(blink), .upright(upright), .countdown(countdown),
    .pad_hide(pad_spin | warp_hide | twist_kind), .pad_gray(pad_gray), .dash_off(dash_off), .field_gray(bul_on),
    .blur(bul_blur), .blur_pads(bul_cold),
    .rgb(game_rgb), .top(game_top), .bg(game_bg)
);

next_render next_draw (
    .clk(clk), .snapshot(snapshot), .hc({1'b0, (mode == M_INTRO || mode == M_ENDING) ? hc : game_hc}), .vc({1'b0, vc}),
    .pick(mode == M_PICK), .pick_cursor0(pick_cur[0]), .pick_cursor1(pick_cur[1]),
    .pick_mask0(pick_mask[0]), .pick_mask1(pick_mask[1]), .pick_secs(pick_secs), .pick_ready(pick_ready),
    .cpu(pick_cpu), .lock(pick_lock), .blink(blink),
    .pick_paddle(pick_paddle), .kind_cursor0(kind_cur[0]), .kind_cursor1(kind_cur[1]), .kind_chosen(kind_chosen),
    // presentazione di CHALLENGE: la racchetta dell'avversario, rivolta verso il giocatore
    .intro(mode == M_INTRO), .intro_kind(rung_kind(ch_level)), .intro_right(ch_side),
    .parade(end_parade), .parade_n(end_parade_n),
    .nxt(nxt && (mode == M_GAME || mode == M_GAME_OVER || mode == M_DEMO)),
    .ball_x(ball_x), .ball_y(ball_y), .ball_r(ball_r), .ball_boost(ball_boost), .ball_vx(ball_vx),
    .kick0({kick_max[0], kick_rise[0], kick_t[0]}), .kick1({kick_max[1], kick_rise[1], kick_t[1]}),
    .pad0_x(show0_x), .pad0_y(pad0_y), .pad1_x(show1_x), .pad1_y(pad1_y),
    .slow_timer(slow_timer), .curve(curve), .next_flags(next_flags), .player0(player0), .player1(player1),
    .caps_x(caps_x), .caps_y(caps_y), .caps_flags(caps_flags), .tick(logic_tick),
    .label_on(label_frames != 7'd0), .label_player(label_player), .label_bonus(label_bonus),
    .warp_on(warp_on), .warp_side(warp_side), .warp_from(warp_from),
    .kind0(kind0), .kind1(kind1), .shots_x(shots_x), .shots_y(shots_y),
    .pad0_motion(pad0_motion), .pad1_motion(pad1_motion), .rush_fade(rush_fade), .barrier_flash(barrier_flash),
    .wall0(wall0), .wall1(wall1), .wall_hit0(wall_hit0), .wall_hit1(wall_hit1),
    .sup(sup), .super0(super0), .super1(super1), .move_ok({move_avail(1'b1), move_avail(1'b0)}),
    .rise_flash(rise_frames != 4'd0), .label_move(label_move), .label_max(label_max),
    .bullet(bul_on), .bullet_armed(bul_arm), .bullet_side(bul_side), .bullet_ramp(bul_ramp),
    .ball_hidden(ghost_hidden),
    .bullet_blur(bul_blur),
    .rgb(next_rgb), .opaque(next_opaque), .halo(next_halo)
);

// schermata HOW TO PLAY delle mosse speciali: due cicli di ritardo, il pixel ne dura tre
wire [23:0] howto_rgb;
howto_render #(.TEXT_ROM(HOWTO_TEXT_ROM), .ROWS_ROM(HOWTO_ROWS_ROM), .SPRITE_ROM(HOWTO_SPRITE_ROM)) howto_draw (
    .clk(clk), .active(mode == M_HOWTO), .frame_start(frame_start), .hc(hc), .vc(vc),
    .control(control), .blink(blink),
    .rgb(howto_rgb)
);

// finale della CHALLENGE: parti, scritte, timbri e fuochi; le racchette della sfilata sono di next_render
wire [23:0] end_rgb;
wire        end_top;
reg         end_q = 1'b0;
always @(posedge clk) end_q <= mode == M_ENDING;
ending_render #(.TEXT_ROM(ENDING_TEXT_ROM), .MAP_ROM(ENDING_MAP_ROM), .FW_ROM(ENDING_FW_ROM)) ending_draw (
    .clk(clk), .start(mode == M_ENDING && !end_q), .active(mode == M_ENDING), .frame_start(frame_start),
    .hc(hc), .vc(vc), .score(end_score), .bonus(end_bonus),
    .rgb(end_rgb), .top(end_top), .parade(end_parade), .parade_n(end_parade_n),
    .say(end_say), .beat(end_beat), .skip_ok(end_skip_ok), .done(end_done)
);

attract_render attract (
    .clk(clk), .hc(hc), .vc(vc), .phase(mode[1:0]), .frame(mframe), .blink(blink),
    .free_play(free_play), .credits(credits),
    .ball_x(cur_ix[8:0]), .ball_y(cur_iy[8:0]),
    .rgb(attract_rgb), .solid(attract_solid)
);

// CHALLENGE: schermate a tutto schermo e punti arcade in partita
wire [23:0] ch_rgb;
wire        ch_opaque;
wire [179:0] tb_names_bus;
wire [279:0] tb_bcd_bus;
wire [39:0]  tb_levels_bus;
wire [239:0] tb_scores_bus;
genvar tg;
generate
    for (tg = 0; tg < 10; tg = tg + 1) begin : table_bus
        assign tb_names_bus[18 * tg +: 18] = tb_name[tg];
        assign tb_scores_bus[24 * tg +: 24] = tb_score[tg];
        assign tb_bcd_bus[28 * tg +: 28] = tb_bcd[tg];
        assign tb_levels_bus[4 * tg +: 4] = tb_level[tg];
    end
endgenerate

// classifica sulla SD (NVRAM del MiSTer): legge il file all'avvio e lo riscrive quando il MiSTer lo
// chiede; i posti letti arrivano qui uno alla volta (nv_go), ciascuno al suo posto
wire        nv_go;
wire [3:0]  nv_at, nv_level;
wire [17:0] nv_name;
wire [23:0] nv_score;
wire [27:0] nv_bcd;
ch_nvram nvram (
    .clk(clk),
    .ioctl_download(ioctl_download), .ioctl_upload(ioctl_upload), .ioctl_index(ioctl_index),
    .ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout), .ioctl_din(ioctl_din),
    .upload_req(ioctl_upload_req),
    .names(tb_names_bus), .scores(tb_scores_bus), .bcds(tb_bcd_bus), .levels(tb_levels_bus),
    .changed(ins_go), .autosave(nv_autosave),
    .ld_go(nv_go), .ld_busy(ins_go), .ld_at(nv_at), .ld_name(nv_name), .ld_score(nv_score),
    .ld_bcd(nv_bcd), .ld_level(nv_level)
);

// scrittura della classifica: il posto inserito a fine CHALLENGE (quelli sotto scendono di uno) o un
// posto letto dalla SD (solo lui); nello stesso ciclo vince l'inserimento e il posto letto si scrive
// il ciclo dopo (ch_nvram tiene i suoi dati per più cicli)
reg         nv_pend = 1'b0;
wire        nv_write = (nv_go || nv_pend) && !ins_go;
wire [3:0]  tb_at = ins_go ? ins_at : nv_at;
always @(posedge clk) begin
    nv_pend <= (nv_go || nv_pend) && ins_go;
    if (ins_go || nv_write) begin
        for (tj = 9; tj > 0; tj = tj - 1)
            if (ins_go && tj > ins_at) begin
                tb_name[tj] <= tb_name[tj - 1];
                tb_score[tj] <= tb_score[tj - 1];
                tb_bcd[tj] <= tb_bcd[tj - 1];
                tb_level[tj] <= tb_level[tj - 1];
            end
        tb_name[tb_at] <= ins_go ? ins_name : nv_name;
        tb_score[tb_at] <= ins_go ? ins_score : nv_score;
        tb_bcd[tb_at] <= ins_go ? ins_bcd : nv_bcd;
        tb_level[tb_at] <= ins_go ? ins_level : nv_level;
    end
end

challenge_render challenge_draw (
    .clk(clk), .hc({1'b0, hc}), .vc({1'b0, vc}),
    .screen(mode == M_INTRO ? 3'd1 : mode == M_CLEAR ? 3'd2 : mode == M_CONT ? 3'd3 :
            mode == M_INITIALS ? 3'd4 : mode == M_SCORES ? 3'd5 : mode == M_CHALLENGER ? 3'd7 :
            (ch_active && !duel && (mode == M_GAME || mode == M_GAME_OVER)) ? 3'd6 : 3'd0),
    .side(ch_side), .join_prompt(ch_active && !duel), .level(ch_level), .kind(rung_kind(ch_level)), .loadout(rung_loadout(ch_level)),
    .score_bcd(mode == M_INITIALS ? ch_best_bcd : ch_score_bcd), .hi_bcd(tb_bcd[0]),
    .perfect(ch_perfect), .coin_prompt(!free_play && credits == 4'd0), .blink(blink),
    .cont_digit(ch_cont_digit), .cont_over(cont_over),
    .name(ch_name), .name_pos(ch_pos), .letter(letter_code(ch_letter)),
    .table_names(tb_names_bus), .table_bcd(tb_bcd_bus), .table_levels(tb_levels_bus),
    .highlight(ch_highlight), .mult(ch_mult),
    .rgb(ch_rgb), .opaque(ch_opaque)
);

// il lampo bianco (punto o hit-stop) copre anche le aggiunte di NEXT, come nel gioco Rust; l'alone
// delle capsule del bullet time va solo sullo sfondo nero del campo (gli stessi grigi di pong_render)
reg flash_q = 1'b0;
always @(posedge clk) flash_q <= flash_count != 2'd0 || hit_flash;
wire [23:0] halo_rgb = (next_halo == 2'd1) ? 24'h6E6E6E : (next_halo == 2'd2) ? 24'h404040 : 24'h1E1E1E;
wire [23:0] rgb_mix;
assign rgb_mix = (mode <= M_TITLE) ? attract_rgb :
                 (mode == M_HOWTO) ? howto_rgb :
                 (mode == M_INTRO && next_opaque) ? next_rgb :
                 // finale: i timbri sopra le racchette della sfilata, le racchette sopra il resto
                 (mode == M_ENDING) ? ((end_top || !next_opaque) ? end_rgb : next_rgb) :
                 (mode >= M_INTRO || (ch_opaque && !flash_q)) ? ch_rgb :
                 (next_opaque && !game_top && (mode == M_PICK || !flash_q)) ? next_rgb :
                 (game_bg && next_halo != 2'd0) ? halo_rgb : game_rgb;
// easter egg: giallo e rosso scambiati sull'uscita, dopo la scelta del renderer
egg_swap swap (.on(egg), .rgb_in(rgb_mix), .rgb_out(rgb));

// -------------------------------------------------------------------- audio

// con l'opzione "Attract sound: Off" tacciono l'attract e la demo, non gettone e Start
wire game_sound = sound_trigger && !(attract_mute && mode == M_DEMO);
wire attract_play = attract_trigger && !(attract_mute && attract_auto);

// capsula e muro del GUARDIAN = muro, sparo del BLASTER = colpo, bonus attivato e TELEPORT = boost,
// SUPER = punto; le mosse speciali hanno i loro effetti: bit 5 mossa attivata, bit 6 colpo della mossa
wire [7:0] sid_events = (game_sound ? {1'b0, sound_events[12], sound_events[10] | sound_events[11], 1'b0,
                                       sound_events[3] | sound_events[6],
                                       sound_events[2] | sound_events[5] | sound_events[7],
                                       sound_events[1] | sound_events[8], sound_events[0] | sound_events[4] | sound_events[9]} : 8'd0) |
                        (attract_play ? attract_sound : 8'd0);
wire signed [15:0] sid_sample;

// nel bullet time gli effetti del gioco suonano un'ottava sotto e lenti il doppio, come su PC
// (il gettone no)
wire sfx_slow = bul_on && game_sound && (mode == M_GAME || mode == M_DEMO) && !sid_events[4];

// musica del SID: il titolo nell'attract (se ha i suoni) e nella scelta di NEXT, il game over a
// fine partita; in partita e nella demo solo gli effetti, tranne in CHALLENGE contro la CPU (non
// nella sfida tra due giocatori), dove suona in ripetizione il tema dell'avversario del livello;
// voci 1 e 2, la 3 resta agli effetti
// (all'arrivo dello sfidante un ciclo di silenzio: la musica riparte anche se era già quella)
// il numero del tema è in un registro, così la tabella dei livelli resta fuori dal percorso.
// Opzione "Music volume: 0%" (`music_off`): nessuna canzone, ovunque; restano gli effetti, la voce del
// nome dell'avversario e le voci di partita. Gli altri volumi li applica pong_sid. "Attract sound: Off"
// (`attract_mute`) toglie invece tutto l'audio dell'attract e della demo (musica ed effetti, non
// gettone e Start): le due si sommano
wire       music_off = music_vol >= 4'd10;
reg  [3:0] theme_song = SID_SONG_THEME0;
reg        theme_on = 1'b0;
always @(posedge clk) begin
    theme_song <= SID_SONG_THEME0 + {1'b0, rung_kind(ch_level)};
    theme_on <= ch_active && !duel;
end
// musica dinamica (come la musica del gioco Rust): al match point, quando uno dei due è a un punto
// dalla vittoria, la canzone accelera fino alla fine della partita; nel bullet time rallenta
reg        music_fast = 1'b0;
always @(posedge clk) music_fast <= mode == M_GAME && two &&
                                    (score0 + 16'd1 >= points_to_win || score1 + 16'd1 >= points_to_win);
wire [3:0] sid_song = ch_join || music_off ? 4'd0 :
                      mode == M_GAME ? (theme_on ? theme_song : 4'd0) :
                      mode == M_GAME_OVER ? (ch_active ? 4'd0 : SID_SONG_GAME_OVER) :
                      mode == M_INTRO || mode == M_CHALLENGER ? SID_SONG_INTRO :
                      mode == M_CLEAR ? (ch_level == CH_LEVELS - 1 ? SID_SONG_CHAMPION : SID_SONG_CLEAR) :
                      mode == M_CONT ? (cont_over ? SID_SONG_GAME_OVER : SID_SONG_CONTINUE) :
                      mode == M_ENDING ? SID_SONG_ENDING :
                      mode == M_INITIALS ? SID_SONG_CHAMPION :
                      mode == M_PICK || mode == M_HOWTO || ((mode == M_STRIPES || mode == M_LOGO || mode == M_TITLE ||
                                          (mode == M_SCORES && ch_scores_attract)) && !attract_mute) ||
                      (mode == M_SCORES && !ch_scores_attract)
                          ? (egg ? SID_SONG_ENDING : SID_SONG_TITLE) : 4'd0;   // easter egg: il finale

// Voci di partita, come su PC: l'urlo della mossa speciale attivata (anche nella demo, come gli
// effetti) e in CHALLENGE (contro la CPU e nella sfida) "READY?" all'inizio del conto alla rovescia
// e "GO!" al via, al posto del suo effetto. "YOU WIN!" quando un giocatore batte la CPU (Classic, EVO,
// NEXT e i livelli della CHALLENGE), con la scritta del GAME OVER; dopo l'ultimo livello la dice invece
// il finale, un secondo dopo CONGRATULATIONS!. Non passano per il SID: musica ed effetti continuano.
reg        call_go = 1'b0;
reg  [3:0] call_id = VOICE_READY;
wire [3:0] call_level;
wire [6:0] fx_gain;                    // volume degli effetti (pong_sid), 64 = 1: anche per le voci di partita
wire       you_win = game_over_now && mode == M_GAME && two && match_cpu && ((score0 >= score1) != ch_cpu_left) &&
                     !(ch_active && ch_level == CH_LEVELS - 1);
always @(posedge clk) begin
    call_go <= 1'b0;
    if (you_win || end_say) begin
        call_go <= 1'b1;
        call_id <= VOICE_YOU_WIN;
    end else if (game_sound && (sound_events[10] || sound_events[11])) begin
        call_go <= 1'b1;
        call_id <= sound_events[10] ? VOICE_STRAIGHT : VOICE_RISE;
    end else if (frame_start && mode == M_GAME && ch_active &&
                 (mframe == 11'd0 || mframe == COUNTDOWN_FRAMES - 11'd1)) begin
        call_go <= 1'b1;
        call_id <= mframe == 11'd0 ? VOICE_READY : VOICE_GO;
    end
end

// CHALLENGE: la voce del SID dice il nome dell'avversario nella presentazione; si ferma se la
// presentazione finisce prima (saltata) o arriva uno sfidante
pong_sid #(.ROM_FILE(SID_ROM), .VOICE_FILE(VOICE_ROM)) sid (
    .clk(clk),
    .reset(reset),
    .mode_8580(!sid_6581),
    .song(sid_song),
    .trigger(game_sound | attract_play),
    .events(sid_events),
    .slow(sfx_slow),
    .music_fast(music_fast),
    .music_slow(bul_on),
    .voice_go(frame_start && mode == M_INTRO && mframe == CH_VOICE_FRAME),
    .voice_id(rung_kind(ch_level)),
    .voice_stop(mode != M_INTRO),
    .voice_on(),
    .call_go(call_go),
    .call_id(call_id),
    .call_level(call_level),
    .music_vol(music_vol),
    .fx_vol(fx_vol),
    .fx_gain(fx_gain),
    .sample(sid_sample)
);

// Uscita: il SID (con il nome dell'avversario già nel suo volume, $D418) più le voci di partita a 4
// bit tenute (±16.384: sopra effetti e musica del SID) per il volume degli effetti (fx_gain / 64), con
// entrambi i filtri. Somma a 18 bit e saturazione.
wire signed [17:0] call_add = (($signed({1'b0, call_level}) - 18'sd8) * $signed({1'b0, fx_gain})) <<< 5;
wire signed [17:0] audio_mix = {{2{sid_sample[15]}}, sid_sample} + call_add;
assign audio = (audio_mix[17:15] == 3'b000 || audio_mix[17:15] == 3'b111) ? audio_mix[15:0] :
               {audio_mix[17], {15{~audio_mix[17]}}};

endmodule

// Gesti delle mosse speciali di un giocatore (NEXT, con super_moves acceso): riconosciuti qui, nei
// comandi, e mai nella logica di gioco, che riceve solo il codice della mossa per un tick.
//
// Joystick, come nei picchiaduro (avanti = verso l'avversario, a destra per il giocatore di sinistra):
// - giù, giù-avanti, avanti + A (mezzaluna) = STRAIGHT SHOT;
// - avanti, giù, giù-avanti + A = RISING STRIKE.
// Per ognuna delle tre direzioni si tiene il tempo dall'ultima volta che era tenuta, in passi di
// 2^17 cicli (6,6 ms): le direzioni devono essere in ordine, a non più di STEP l'una dall'altra
// (0,3 s), e A deve arrivare entro BTN (0,25 s) dall'ultima. Finita in avanti la sequenza vale come
// STRAIGHT SHOT anche se prima c'era un avanti (avanti, giù, giù-avanti, avanti + A).
//
// Paddle e spinner (come rust/game/src/gesture.rs, un campione per frame): un tratto è un movimento
// rapido in un verso, lungo almeno KNOB_MIN pixel (1/8 del campo) e fatto entro STEP_F frame; un
// ritorno indietro più corto di KNOB_DEAD non cambia verso e un fermo di oltre STILL_F frame fa
// ripartire il tratto. Giù poi su + A = STRAIGHT SHOT, su poi giù + A = RISING STRIKE, con i due
// tratti finiti a non più di STEP_F frame l'uno dall'altro e A entro BTN_F frame dalla fine del
// secondo (che può essere ancora in corso).
//
// Lo scatto (A) che completa un gesto diventa la mossa solo se la mossa può partire (`allow`: barra
// sufficiente, nessuna mossa né bonus armato, palla in gioco): allora il tasto non scatta e il gesto
// si consuma. Altrimenti A resta lo scatto normale, così con la barra vuota un movimento rapido seguito
// da A (frequente con il paddle) non toglie lo scatto. Solo confronti, somme e shift.
module move_gesture (
    input  wire       clk,
    input  wire       reset,              // partita nuova: si dimentica tutto
    input  wire       slow,               // un impulso ogni 2^17 cicli: età delle direzioni del joystick
    input  wire       frame,              // inizio del frame: campione della manopola
    input  wire       facing_left,        // giocatore di destra: avanti = sinistra
    input  wire [3:0] joy,                // {su, giù, sinistra, destra}
    input  wire       knob_on,            // la racchetta è comandata da paddle o spinner
    input  wire signed [9:0] knob_d,      // spostamento della manopola nel frame (positivo = giù)
    input  wire       press,              // fronte del tasto A
    input  wire       allow,              // la mossa può partire
    output wire [1:0] code                // 1 STRAIGHT SHOT, 2 RISING STRIKE con questo `press`, 0 niente
);

localparam [7:0] STEP = 8'd46, BTN = 8'd38, AGE_MAX = 8'd255;
localparam [5:0] STEP_F = 6'd18, BTN_F = 6'd15, STILL_F = 6'd5, FR_MAX = 6'd63;
localparam [9:0] KNOB_MIN = 10'd30;
localparam signed [11:0] KNOB_DEAD = 12'sd5;
localparam [1:0] DOWN = 2'd1, UP = 2'd2;

// ---------------------------------------------------------------- joystick
wire fwd = facing_left ? joy[1] : joy[0];
wire is_d = joy[2] && !fwd;
wire is_df = joy[2] && fwd;
wire is_f = fwd && !joy[2] && !joy[3];
reg [7:0] a_d = AGE_MAX, a_df = AGE_MAX, a_f = AGE_MAX;

wire qcf = a_f <= BTN && a_df >= a_f && a_df - a_f <= STEP && a_d >= a_df && a_d - a_df <= STEP;
wire dp = a_df <= BTN && a_d >= a_df && a_d - a_df <= STEP && a_f >= a_d && a_f - a_d <= STEP;

// ------------------------------------------------------------------ manopola
reg  [1:0]  k_dir = 2'd0;          // verso del tratto in corso (0 finché non supera KNOB_DEAD)
reg  signed [11:0] k_acc = 12'sd0; // senza verso: spostamento dall'inizio; con il verso: dal punto più lontano (<= 0)
reg  [9:0]  k_span = 10'd0;        // corsa dall'inizio al punto più lontano
reg  [5:0]  k_start = 6'd0, k_peak = 6'd0, k_still = FR_MAX;   // frame dall'inizio, dal punto più lontano, da fermo
// ultimi due tratti validi: verso e frame dalla fine (1 = il più recente)
reg  [1:0]  s1_dir = 2'd0, s0_dir = 2'd0;
reg  [5:0]  s1_age = FR_MAX, s0_age = FR_MAX;

wire        cur_ok = k_dir != 2'd0 && k_span >= KNOB_MIN && k_start - k_peak <= STEP_F;
wire [1:0]  a_dir = cur_ok ? s1_dir : s0_dir;
wire [5:0]  a_age = cur_ok ? s1_age : s0_age;
wire [1:0]  b_dir = cur_ok ? k_dir : s1_dir;
wire [5:0]  b_age = cur_ok ? k_peak : s1_age;
wire        knob_ok = knob_on && a_dir != 2'd0 && b_dir != 2'd0 && a_dir != b_dir && b_age <= BTN_F &&
                      a_age >= b_age && a_age - b_age <= STEP_F;

assign code = !(press && allow) ? 2'd0 : dp ? 2'd2 : qcf ? 2'd1 : knob_ok ? (a_dir == DOWN ? 2'd1 : 2'd2) : 2'd0;

function [5:0] older(input [5:0] a);
    older = (a == FR_MAX) ? a : a + 6'd1;
endfunction

reg signed [11:0] nd, rel;
reg [10:0] span_n;

always @(posedge clk) begin
    // età delle direzioni: zero finché sono tenute
    if (is_d) a_d <= 8'd0; else if (slow && a_d != AGE_MAX) a_d <= a_d + 8'd1;
    if (is_df) a_df <= 8'd0; else if (slow && a_df != AGE_MAX) a_df <= a_df + 8'd1;
    if (is_f) a_f <= 8'd0; else if (slow && a_f != AGE_MAX) a_f <= a_f + 8'd1;

    if (frame) begin
        s1_age <= older(s1_age);
        s0_age <= older(s0_age);
        k_start <= older(k_start);
        k_peak <= older(k_peak);
        if (knob_d == 10'sd0) begin
            k_still <= older(k_still);
        end else begin
            k_still <= 6'd0;
            if (k_still > STILL_F || k_dir == 2'd0) begin
                // era fermo (il tratto riparte da qui) o non ha ancora un verso
                rel = (k_still > STILL_F ? 12'sd0 : k_acc) + {{2{knob_d[9]}}, knob_d};
                if (k_still > STILL_F) k_start <= 6'd0;
                if (rel >= KNOB_DEAD || rel <= -KNOB_DEAD) begin
                    k_dir <= rel > 0 ? DOWN : UP;
                    k_span <= rel > 0 ? rel[9:0] : -rel;
                    k_acc <= 12'sd0;
                    k_peak <= 6'd0;
                end else begin
                    k_dir <= 2'd0;
                    k_acc <= rel;
                end
            end else begin
                // spostamento nel verso del tratto: oltre il punto più lontano lo sposta avanti
                nd = (k_dir == DOWN) ? {{2{knob_d[9]}}, knob_d} : -{{2{knob_d[9]}}, knob_d};
                rel = k_acc + nd;
                if (rel > 0) begin
                    span_n = {1'b0, k_span} + {1'b0, rel[9:0]};
                    k_span <= span_n[10] ? 10'h3FF : span_n[9:0];
                    k_acc <= 12'sd0;
                    k_peak <= 6'd0;
                end else if (rel < -KNOB_DEAD) begin
                    // cambio di verso: il tratto finisce nel punto più lontano e il nuovo parte da lì
                    if (cur_ok) begin
                        s0_dir <= s1_dir;
                        s0_age <= older(s1_age);
                        s1_dir <= k_dir;
                        s1_age <= older(k_peak);
                    end
                    k_dir <= (k_dir == DOWN) ? UP : DOWN;
                    k_span <= -rel;
                    k_acc <= 12'sd0;
                    k_start <= older(k_peak);
                    k_peak <= 6'd0;
                end else begin
                    k_acc <= rel;
                end
            end
        end
    end

    // gesto usato: si consuma (lo scatto dopo è di nuovo normale)
    if (code != 2'd0) begin
        a_d <= AGE_MAX;
        a_df <= AGE_MAX;
        a_f <= AGE_MAX;
        s1_dir <= 2'd0;
        s0_dir <= 2'd0;
        k_dir <= 2'd0;
        k_acc <= 12'sd0;
        k_span <= 10'd0;
        k_start <= 6'd0;
        k_peak <= 6'd0;
    end
    if (reset || !knob_on) begin
        k_dir <= 2'd0;
        k_acc <= 12'sd0;
        k_span <= 10'd0;
        k_still <= FR_MAX;
        s1_dir <= 2'd0;
        s0_dir <= 2'd0;
    end
    if (reset) begin
        a_d <= AGE_MAX;
        a_df <= AGE_MAX;
        a_f <= AGE_MAX;
    end
end

endmodule

// Easter egg delle iniziali "WS!": giallo e rosso scambiati sull'uscita video, come lo shader di
// rust/game/src/render.rs (swap_color), ma sui colori esatti della palette dei renderer. Il giallo
// d'accento FFD225 diventa il rosso E62828 e il rosso diventa il giallo; le versioni scure del giallo
// (le code di next_render, accento * n / 13 e * n / 23; le immagini del RUSH al 18, 36 e 54%; la
// scia di howto_render al 45%) diventano il rosso scurito allo stesso modo; il rosso scuro e quello
// chiaro delle figurine di howto_render (e della banda del nuovo sfidante) diventano gialli con la
// stessa luce, la tinta riflessa come su PC. Gli altri colori (bianchi, grigi, neri, il verde
// dell'auto-test, i grigi azzurri delle racchette) restano come sono. Solo confronti con costanti
// (due livelli di LUT) e un OR per bit, senza registri: il pixel esce nello stesso ciclo di prima.
module egg_swap (
    input  wire        on,
    input  wire [23:0] rgb_in,
    output wire [23:0] rgb_out
);

localparam [23:0] YELLOW = 24'hFFD225, RED = 24'hE62828;
localparam integer PAIRS = 42;

// colore c * n / d per canale, troncato, come trail_acc e trail_long di next_render
function [23:0] scale(input [23:0] c, input integer n, input integer d);
    reg [7:0] r, g, b;
    begin
        r = c[23:16] * n / d;
        g = c[15:8] * n / d;
        b = c[7:0] * n / d;
        scale = {r, g, b};
    end
endfunction

// coppia i: {colore della palette, colore con l'easter egg}; i colori di partenza sono tutti diversi
function [47:0] pair(input integer i);
    begin
        if (i == 0)
            pair = {YELLOW, RED};
        else if (i <= 12)                       // code da 13 passi (trail_acc)
            pair = {scale(YELLOW, i, 13), scale(RED, i, 13)};
        else if (i <= 34)                       // code lunghe del bullet time (trail_long)
            pair = {scale(YELLOW, i - 12, 23), scale(RED, i - 12, 23)};
        else
            case (i)
                35: pair = {24'h2E2607, 24'h290707};   // immagini del RUSH (next_render: GHOST1-3)
                36: pair = {24'h5C4C0D, 24'h530E0E};
                37: pair = {24'h8A7114, 24'h7C1616};
                38: pair = {24'h735E11, 24'h681212};   // scia di RISING STRIKE (howto_render: TRAIL)
                39: pair = {RED, YELLOW};
                40: pair = {24'h8C1414, 24'h8C7414};   // rosso scuro (figurine, banda del nuovo sfidante)
                41: pair = {24'hFF6E6E, 24'hFFE26E};   // rosso chiaro delle figurine
                default: pair = 48'd0;
            endcase
    end
endfunction

reg        hit;
reg [23:0] swapped;
reg [47:0] pr;
integer    i;
always @(*) begin
    hit = 1'b0;
    swapped = 24'd0;
    for (i = 0; i < PAIRS; i = i + 1) begin
        pr = pair(i);
        if (rgb_in == pr[47:24]) begin
            hit = 1'b1;
            swapped = swapped | pr[23:0];
        end
    end
end

assign rgb_out = (on && hit) ? swapped : rgb_in;

endmodule
