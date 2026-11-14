// Disegno della modalità NEXT: schermate di scelta dei bonus e della racchetta e, in partita,
// le aggiunte sopra il campo di pong_render (riserve, capsule, icona del bonus armato, racchetta
// che ruota con il SUPER, salto del TELEPORT, palla guidata con STEER, palla cometa e scie, alone
// di SLOW, scritta del bonus attivato, segni dei tipi di racchetta, colpi e munizioni del BLASTER,
// immagini dello scatto del RUSH,
// muro a settori del GUARDIAN) e, con le mosse speciali, la barra di ciascun giocatore nella banda in alto
// sotto la riserva, la racchetta con la mossa armata (segno accanto, gialla al livello 2), il tiro
// della mossa in volo, il punto dove RISING STRIKE s'impenna e il nome della mossa ("MAX" al livello
// 2). La schermata HOW TO PLAY prima della partita è in howto_render.
// Come rust/game/src/next_ui.rs, su uno schermo 320x240.
//
// Una volta per frame (`snapshot`) lo stato della logica diventa posizioni in pixel; durante
// il frame restano solo confronti e piccole ROM. L'uscita, un ciclo dopo, dice se il pixel è
// di NEXT (`opaque`) e di che colore: pong_top la mette sopra il campo.

`timescale 1ns / 1ps

module next_render (
    input  wire        clk,
    input  wire        snapshot,
    input  wire [9:0]  hc,
    input  wire [9:0]  vc,

    // schermata di scelta
    input  wire        pick,
    input  wire [2:0]  pick_cursor0,
    input  wire [2:0]  pick_cursor1,
    input  wire [5:0]  pick_mask0,          // bonus presi (bit = riga: codici 0..4, poi STEER)
    input  wire [5:0]  pick_mask1,
    input  wire [3:0]  pick_secs,           // secondi rimasti
    input  wire        pick_ready,
    input  wire        cpu,                 // il giocatore di destra è il computer
    input  wire [1:0]  lock,                // lati con la scelta già fatta (CPU, campione di CHALLENGE)
    input  wire [5:0]  blink,               // frame % 60
    // scelta della racchetta (dopo i bonus): cursori e racchette confermate
    input  wire        pick_paddle,
    input  wire [2:0]  kind_cursor0,
    input  wire [2:0]  kind_cursor1,
    input  wire [1:0]  kind_chosen,
    // presentazione dell'avversario di CHALLENGE: la sua racchetta al centro con i segni del tipo,
    // con lo stesso disegno dell'anteprima della scelta (le scritte sono di challenge_render)
    input  wire        intro,
    input  wire [2:0]  intro_kind,
    input  wire        intro_right,         // rivolta a destra (verso il giocatore)
    input  wire [7:0]  intro_age,           // frame dall'inizio della presentazione (fermi a 255)
    // finale della CHALLENGE: la sfilata dei sette avversari battuti (le prime `parade_n` racchette, in
    // colonna, con il nome sotto); solo bianco e giallo, come il resto del finale (ending_render)
    input  wire        parade,
    input  wire [2:0]  parade_n,

    // partita NEXT
    input  wire        nxt,
    input  wire signed [31:0] ball_x,
    input  wire signed [31:0] ball_y,
    input  wire signed [31:0] ball_r,
    input  wire signed [31:0] ball_boost,
    input  wire signed [31:0] ball_vx,      // verso della palla: la coda riparte a ogni colpo
    input  wire [6:0]  kick0,               // colpo di una mossa: {MAX, RISING STRIKE, frame rimasti}
    input  wire [6:0]  kick1,
    input  wire signed [31:0] pad0_x,      // x disegnata (scatto animato) e y del core
    input  wire signed [31:0] pad0_y,
    input  wire signed [31:0] pad1_x,
    input  wire signed [31:0] pad1_y,
    input  wire [31:0] slow_timer,
    input  wire signed [31:0] curve,
    input  wire [31:0] next_flags,
    input  wire [31:0] player0,
    input  wire [31:0] player1,
    input  wire [127:0] caps_x,
    input  wire [127:0] caps_y,
    input  wire [15:0] caps_flags,
    input  wire [31:0] tick,
    input  wire        label_on,            // scritta "P1 SMASH!" del bonus attivato
    input  wire        label_player,
    input  wire [2:0]  label_bonus,
    // tipo della scritta (LK_*: bonus, mossa armata, colpo della mossa) e frame dal suo inizio
    // (fermi a 127)
    input  wire [1:0]  label_kind,
    input  wire [6:0]  label_age,
    input  wire        warp_on,             // salto del TELEPORT in corso (l'avanzamento segue la palla)
    input  wire        warp_side,
    input  wire signed [31:0] warp_from,    // y di partenza della racchetta (core)
    // tipi di racchetta: stato dei giocatori (kind0/1 di pong_logic_rv), colpi del BLASTER, motion
    input  wire [31:0] kind0,
    input  wire [31:0] kind1,
    input  wire [255:0] shots_x,           // colpi del BLASTER, 4 per giocatore (prima il sinistro)
    input  wire [255:0] shots_y,
    input  wire signed [31:0] pad0_motion,
    input  wire signed [31:0] pad1_motion,
    input  wire [3:0]  rush_fade,           // RUSH: intensità delle immagini dello scatto (2 bit per lato, 0 = niente)
    input  wire [1:0]  barrier_flash,       // GUARDIAN: settore del muro appena colpito, lampeggia
    input  wire [4:0]  wall0,               // GUARDIAN: settori del muro in piedi (5, bit 0 in alto)
    input  wire [4:0]  wall1,
    input  wire [4:0]  wall_hit0,           // GUARDIAN: settore che lampeggia (con barrier_flash)
    input  wire [4:0]  wall_hit1,
    // mosse speciali: accese nella partita, stato dei giocatori (super0/1 di pong_logic_rv: barra nei
    // bit 0-7, livello di STRAIGHT SHOT armato nei bit 8-9 e di RISING STRIKE nei bit 10-11, 2 = MAX),
    // mossa possibile adesso, RISING STRIKE appena impennata (quadrato nel punto), nome della mossa
    // nella scritta (0 = bonus) e se è di livello 2
    input  wire        sup,
    input  wire [31:0] super0,
    input  wire [31:0] super1,
    input  wire [1:0]  move_ok,
    input  wire        rise_flash,
    input  wire [1:0]  label_move,
    input  wire        label_max,
    // BULLET: scattato (bullet time), armato o in corso, lato di chi l'ha attivato, rampa di
    // entrata, profondità dell'alone delle capsule (0 = niente)
    input  wire        bullet,
    input  wire        bullet_armed,
    input  wire        bullet_side,
    input  wire        bullet_ramp,
    input  wire [1:0]  bullet_blur,

    // GHOST: la palla è nascosta in questo frame (si vede solo a lampi, pong_top)
    input  wire        ball_hidden,

    output reg  [23:0] rgb,
    output reg         opaque,
    // pixel della scritta del bonus attivato: pong_top ci mette sopra la palla di pong_render
    output reg         label,
    // bullet time: alone delle capsule (1-3 pixel dal bordo, 0 = niente); pong_top lo mette solo
    // sullo sfondo nero di pong_render
    output reg  [1:0]  halo
);

`include "pong_params.vh"
`include "pong_fonts.vh"
`include "pong_next.vh"
`include "pong_ending.vh"

localparam integer W = P_WIDTH >>> 16;
localparam integer H = P_HEIGHT >>> 16;
localparam [23:0] RGB_WHITE = 24'hFFFFFF, RGB_GRAY = 24'hB4B4B4, RGB_BLACK = 24'h000000;
// colore di accento, come `colors.accent` del gioco Rust (il giallo dell'attract): solo per
// titolo, cursore e READY! della scelta, freccetta della riserva, portali, scritta del bonus,
// capsula e palla del SUPER, capsula del BULLET, bordo della racchetta di chi ha il BULLET
localparam [23:0] RGB_ACCENT = 24'hFFD225;
// codici dei bonus a 4 bit come nelle parole dei giocatori di pong_logic_rv (8 = posto vuoto)
localparam [3:0] B_SUPER = 4'd5, B_STEER = 4'd6, B_BULLET = 4'd7, B_NONE = 4'd8;
localparam [23:0] RGB_DETAIL = 24'hA9B0B8, RGB_DIM = 24'h3F3F3F;
// tipi di racchetta (come `PaddleKind`)
localparam [2:0] K_ARCADE = 3'd0, K_TITAN = 3'd1, K_HAMMER = 3'd2, K_TWIST = 3'd3, K_BLASTER = 3'd4,
                 K_RUSH = 3'd5, K_GUARDIAN = 3'd6, K_NONE = 3'd7;
// codici di un pixel di racchetta: corpo, segno del tipo (accento), dettaglio grigio, taglio nero
localparam [2:0] KP_NONE = 3'd0, KP_BODY = 3'd1, KP_MARK = 3'd2, KP_DETAIL = 3'd3, KP_CUT = 3'd4;
// RUSH: immagini della racchetta dietro di lei, dalla più lontana (la più scura) alla più vicina:
// l'accento al 18, 36 e 54% (come su PC, alpha 0,18 * k sul nero)
localparam [2:0] KP_GHOST1 = 3'd5, KP_GHOST2 = 3'd6, KP_GHOST3 = 3'd7;
localparam [23:0] RGB_GHOST1 = 24'h2E2607, RGB_GHOST2 = 24'h5C4C0D, RGB_GHOST3 = 24'h8A7114;
// colpo di una mossa (draw_kick di next_ui.rs), KICK_FRAMES frame come in pong_top: l'onda d'urto
// sfuma con l'accento a 2/3 e 1/3; le immagini della racchetta della MAX all'accento al 50 e 25%
localparam integer KICK_FRAMES = 18;
localparam [23:0] RGB_KICK2 = 24'hAA8C18, RGB_KICK1 = 24'h55460C, RGB_KICK_IMG1 = 24'h806912, RGB_KICK_IMG2 = 24'h403409;
// Colori come indici della tavolozza `pal` (7 bit invece di 24): la catena del pixel sceglie
// fra indici e il colore vero si legge una volta sola, all'uscita. Dopo i colori fissi le code:
// trail_col, trail_acc e trail_long grigia e gialla, una voce per passo (81 in tutto).
localparam [6:0] WHITE = 7'd0, GRAY = 7'd1, BLACK = 7'd2, ACCENT = 7'd3, DETAIL = 7'd4, DIM = 7'd5, GHOST1 = 7'd6,
                 GHOST2 = 7'd7, GHOST3 = 7'd8, KICK2 = 7'd9, KICK1 = 7'd10, KICK_IMG1 = 7'd11, KICK_IMG2 = 7'd12;
localparam [6:0] T_COL = 7'd13, T_ACC = 7'd25, T_LONG_GRAY = 7'd37, T_LONG_ACC = 7'd59;
// TWIST: inclinazione a gradini (fino a circa 20 gradi) dalla velocità della racchetta
localparam signed [31:0] TILT1 = P_PAD_MAX_SPEED / 6, TILT2 = P_PAD_MAX_SPEED / 2,
                         TILT3 = P_PAD_MAX_SPEED * 5 / 6;
localparam integer BARRIER_X = P_GUARDIAN_BARRIER_X >>> 16;
// GUARDIAN: muro a 5 settori da WALL_TOP (sotto la banda delle riserve) al fondo, confini WALL_B1..4,
// in righe dello schermo (i parametri sono y del core, verso l'alto, pixel interi); in ogni settore
// tratti di 5 righe ogni 8 da 2 righe dopo l'inizio a 2 righe prima della fine, così tra un
// settore e l'altro resta uno spazio (come next_ui.rs)
localparam integer WALL_TOP = H - (P_GUARDIAN_TOP >>> 16), WALL_B1 = H - (P_GUARDIAN_BOUND1 >>> 16),
                   WALL_B2 = H - (P_GUARDIAN_BOUND2 >>> 16), WALL_B3 = H - (P_GUARDIAN_BOUND3 >>> 16),
                   WALL_B4 = H - (P_GUARDIAN_BOUND4 >>> 16);
localparam integer CAP = 2 * (P_CAPSULE_HALF >>> 16);       // lato della capsula
localparam integer PW = P_PAD_WIDTH >>> 16;
localparam integer HIST = 12;                                 // posizioni della scia
// coda degli altri effetti: le ultime TRAIL posizioni (0,1 s come i 24 tick di next_ui.rs) più i
// punti a metà tra l'una e l'altra, perché a 60 Hz la palla veloce si sposta più del suo lato
localparam integer TRAIL = 6;
// mosse speciali: barra di METER pixel (uno per unità) più la cornice, tacca al costo; nella banda in
// alto da BAR_X dal bordo, con la cornice da BAR_Y (le tacche sporgono di 2 righe sopra e sotto)
localparam integer METER = P_SUPER_METER_MAX, COST = P_SUPER_COST, BAR_X = 6, BAR_Y = 22;
localparam integer WALL_TOP_SUP = BAR_Y + 7;      // GUARDIAN: primo tratto del muro con le barre
// presentazione di CHALLENGE: riga del centro della racchetta; munizioni del BLASTER (caricatore
// pieno, 4 righe per colpo come in partita)
localparam integer INTRO_Y = 82, AMMO_ROWS = 4 * P_BLASTER_SHOTS;

// grigio della coda al passo j (1 = mezzo frame fa, 2 * TRAIL = il più vecchio): dal grigio verso il nero
function [23:0] trail_col(input integer j);
    reg [7:0] v;
    begin
        v = 8'hB4 * (2 * TRAIL + 1 - j) / (2 * TRAIL + 1);
        trail_col = {v, v, v};
    end
endfunction
// la stessa coda nel colore di accento: il tiro di una mossa speciale
function [23:0] trail_acc(input integer j);
    reg [7:0] r, g, b;
    begin
        r = RGB_ACCENT[23:16] * (2 * TRAIL + 1 - j) / (2 * TRAIL + 1);
        g = RGB_ACCENT[15:8] * (2 * TRAIL + 1 - j) / (2 * TRAIL + 1);
        b = RGB_ACCENT[7:0] * (2 * TRAIL + 1 - j) / (2 * TRAIL + 1);
        trail_acc = {r, g, b};
    end
endfunction
// BULLET: la coda lunga il doppio (TRAIL_LONG posizioni, tutta la storia), con la stessa sfumatura
localparam integer TRAIL_LONG = HIST - 1;
function [23:0] trail_long(input acc, input integer j);
    reg [7:0] r, g, b;
    begin
        r = (acc ? RGB_ACCENT[23:16] : 8'hB4) * (2 * TRAIL_LONG + 1 - j) / (2 * TRAIL_LONG + 1);
        g = (acc ? RGB_ACCENT[15:8] : 8'hB4) * (2 * TRAIL_LONG + 1 - j) / (2 * TRAIL_LONG + 1);
        b = (acc ? RGB_ACCENT[7:0] : 8'hB4) * (2 * TRAIL_LONG + 1 - j) / (2 * TRAIL_LONG + 1);
        trail_long = {r, g, b};
    end
endfunction
// colore della coda al passo j: accento per il tiro di una mossa, lunga nel bullet time
function [6:0] trail_pick(input acc, input lng, input integer j);
    trail_pick = (lng ? (acc ? T_LONG_ACC : T_LONG_GRAY) : (acc ? T_ACC : T_COL)) + j - 1;
endfunction
// tavolozza: i colori fissi e le code (trail_col, trail_acc, trail_long), una voce per passo; con
// j costante le funzioni delle code danno costanti, e il tutto è una piccola ROM
function [23:0] pal(input [6:0] i);
    integer j;
    begin
        case (i)
            WHITE:     pal = RGB_WHITE;
            GRAY:      pal = RGB_GRAY;
            ACCENT:    pal = RGB_ACCENT;
            DETAIL:    pal = RGB_DETAIL;
            DIM:       pal = RGB_DIM;
            GHOST1:    pal = RGB_GHOST1;
            GHOST2:    pal = RGB_GHOST2;
            GHOST3:    pal = RGB_GHOST3;
            KICK2:     pal = RGB_KICK2;
            KICK1:     pal = RGB_KICK1;
            KICK_IMG1: pal = RGB_KICK_IMG1;
            KICK_IMG2: pal = RGB_KICK_IMG2;
            default:   pal = RGB_BLACK;
        endcase
        for (j = 1; j <= 2 * TRAIL; j = j + 1) begin
            if (i == T_COL + j - 1) pal = trail_col(j);
            if (i == T_ACC + j - 1) pal = trail_acc(j);
        end
        for (j = 1; j <= 2 * TRAIL_LONG; j = j + 1) begin
            if (i == T_LONG_GRAY + j - 1) pal = trail_long(1'b0, j);
            if (i == T_LONG_ACC + j - 1) pal = trail_long(1'b1, j);
        end
    end
endfunction
// BULLET: immagini grigie della palla (solo il contorno) ogni GHOST_STEP frame, oltre la coda:
// GHOSTS posizioni prese dalla più vecchia della storia
localparam integer GHOST_STEP = 3, GHOSTS = 4;

// pixel della barra della mossa: bx colonna dall'inizio (0 = cornice), by riga da 2 righe sopra la
// cornice; 1 cornice, 2 parte piena (fino a `level`), 3 tacca del costo, 0 niente
function [1:0] bar_px(input [9:0] bx, input [9:0] by, input [7:0] level);
    begin
        bar_px = 2'd0;
        if (bx <= METER + 1 && by >= 2 && by < 7) begin
            if (bx == 0 || bx == METER + 1 || by == 2 || by == 6) bar_px = 2'd1;
            else if (bx <= level) bar_px = 2'd2;
        end else if ((bx == COST || bx == COST + 1) && by < 9)
            bar_px = 2'd3;
    end
endfunction
// salto del TELEPORT, come in next_ui.rs: con la palla in arrivo la racchetta affonda nel primo
// portale mentre la palla va da metà campo a 4/10 della larghezza (contati dal bordo del giocatore),
// poi esce dal secondo, sul punto d'arrivo, mentre va da 3/10 a 2/10. Un decimo del campo sono 32
// pixel: kind_warp_shift (pong_params.vh) dà il tratto passato per ogni pixel del passo.
localparam integer WARP_STEP = 32, WARP_SUNK = W / 2, WARP_RISE = 3 * WARP_STEP, WARP_LINE_HALF = 9;

wire [9:0] x = hc;
wire [9:0] y = vc;

// Pixel (t, r) di una racchetta di tipo `kind`, larga w e alta h: t è la colonna contata dal
// retro (0) verso la faccia (w - 1, oltre: davanti, sotto 0: dietro), r la riga dall'alto.
// Come draw_paddle in rust/game/src/paddle_ui.rs. `tilt` inclina TWIST (positivo: faccia verso
// l'alto), `preview` il pezzo di muro del GUARDIAN, `ghosts` le immagini del RUSH attaccate dietro
// (il suo segno nella scelta; in partita le disegna il blocco delle immagini dello scatto).
// Solo confronti, shift e somme.
function [2:0] kind_px(input [2:0] kind, input signed [11:0] t, input signed [11:0] r, input [9:0] h,
                       input signed [2:0] tilt, input preview, input ghosts);
    reg signed [11:0] hh, d, sh, ts;
    reg [2:0] m;
    reg body;
    begin
        kind_px = KP_NONE;
        hh = $signed({2'b0, h});
        body = t >= 0 && t < PW && r >= 0 && r < hh;
        case (kind)
            K_TWIST: begin
                // scorrimento orizzontale delle righe: (r - h/2) * tilt / 8
                d = r - (hh >>> 1);
                m = tilt[2] ? -tilt : tilt;
                sh = (m[0] ? d : 12'sd0) + (m[1] ? d <<< 1 : 12'sd0);
                sh = tilt[2] ? -(sh >>> 3) : (sh >>> 3);
                ts = t - sh;
                if (ts >= 0 && ts < PW && r >= 0 && r < hh) kind_px = KP_BODY;
            end
            K_HAMMER: begin
                // più spessa verso il retro, con le bande grigie del peso
                if (t >= -(PW / 2) && t < PW && r >= 0 && r < hh)
                    kind_px = (r == (hh >>> 1) - 10 || r == (hh >>> 1) - 9 ||
                               r == (hh >>> 1) + 8 || r == (hh >>> 1) + 9) ? KP_DETAIL : KP_BODY;
            end
            K_BLASTER: begin
                if (body) begin
                    kind_px = KP_BODY;
                    // spigoli del davanti smussati
                    if (((r == 0 || r == hh - 1) && t >= PW - 2) || ((r == 1 || r == hh - 2) && t == PW - 1))
                        kind_px = KP_CUT;
                end
                // due canne grigie davanti, sopra e sotto il centro
                if (t >= PW && t < PW + 2 &&
                    (r == (hh >>> 1) - 4 || r == (hh >>> 1) - 3 || r == (hh >>> 1) + 2 || r == (hh >>> 1) + 3))
                    kind_px = KP_DETAIL;
            end
            K_TITAN: begin
                if (body) kind_px = (t == 0 && (r < (hh >>> 3) || r >= hh - (hh >>> 3))) ? KP_MARK : KP_BODY;
            end
            K_RUSH: begin
                if (body) kind_px = KP_BODY;
                // tre immagini dietro, più scure verso il retro, con una colonna vuota tra l'una e l'altra
                if (ghosts && r >= 0 && r < hh && t < -1 && t >= -3 * PW && t != -PW - 1 && t != -2 * PW - 1)
                    kind_px = (t >= -PW) ? KP_GHOST3 : (t >= -2 * PW) ? KP_GHOST2 : KP_GHOST1;
            end
            K_GUARDIAN: begin
                if (body) kind_px = KP_BODY;
                // nella scelta un pezzo di muro dietro (in partita è un muro a settori)
                if (preview && (t == -8 || t == -7) && r >= -(hh >>> 2) && r < hh + (hh >>> 2) &&
                    ((r + (hh >>> 2)) & 12'sd7) < 5)
                    kind_px = KP_MARK;
            end
            default: if (body) kind_px = KP_BODY;
        endcase
    end
endfunction

// ------------------------------------------------ presentazione animata della CHALLENGE
// La racchetta dell'avversario entra a modo suo (come Stage::arcade, ... di
// rust/game/src/challenge_ui.rs, distanze dimezzate); il resto lo disegna challenge_render. Per
// ogni frame: spostamento dal centro (x verso la metà campo dell'avversario, da dove entra), altezza
// (TITAN cresce dal pavimento), inclinazione (TWIST), lampo giallo, se si vede, e per lo scatto del
// RUSH le tre immagini tra la partenza e la racchetta con la loro intensità (0 = niente).
// ARCADE: spostamento verticale delle capsule della raffica (come in challenge_render)
function signed [5:0] arcade_dy(input [3:0] k);
    case (k)
        4'd0: arcade_dy = -6'sd14; 4'd1: arcade_dy = 6'sd10;  4'd2: arcade_dy = -6'sd4; 4'd3: arcade_dy = 6'sd16;
        4'd4: arcade_dy = -6'sd18; 4'd5: arcade_dy = 6'sd2;   4'd6: arcade_dy = 6'sd12; 4'd7: arcade_dy = -6'sd10;
        4'd8: arcade_dy = 6'sd6;   default: arcade_dy = -6'sd2;
    endcase
endfunction
reg signed [11:0] ip_dx, ip_dy;        // spostamento (dx verso l'avversario, dy verso il basso)
reg [9:0]  ip_h;
reg signed [2:0] ip_tilt;
reg        ip_flash, ip_show;
reg [1:0]  ip_fade;                    // RUSH: intensità delle immagini dello scatto
reg signed [11:0] ip_gx [1:3];         // ... e loro distanza dal centro (verso l'avversario)
reg signed [11:0] it_a, it_y0, it_y1, it_amp;
reg signed [19:0] it_m;
reg [7:0]  it_t;
reg [3:0]  it_k;
reg [5:0]  it_i;
always @(posedge clk) begin
    ip_dx <= 12'sd0;
    ip_dy <= 12'sd0;
    ip_h <= kind_px_h(intro_kind);
    ip_tilt <= 3'sd0;
    ip_flash <= 1'b0;
    ip_show <= 1'b1;
    ip_fade <= 2'd0;
    ip_gx[1] <= 12'sd0;
    ip_gx[2] <= 12'sd0;
    ip_gx[3] <= 12'sd0;
    it_a = $signed({4'd0, intro_age});
    case (intro_kind)
        K_ARCADE: begin
            // va incontro alla capsula che arriva (arrivo della k-esima al frame 30 + 6k), poi torna
            // (a - 30) / 6 come (a - 30) * 43 / 256, giusto fin dove serve
            it_m = $signed({12'd0, intro_age - 8'd30}) * 43;
            it_k = (intro_age < 8'd30) ? 4'd0 : (intro_age >= 8'd84) ? 4'd10 : it_m[11:8] + 4'd1;
            if (intro_age < 8'd10) ip_dy <= 12'sd0;
            else if (it_k < 4'd10) begin
                it_y0 = (it_k == 4'd0) ? 12'sd0 : arcade_dy(it_k - 4'd1);
                it_y1 = arcade_dy(it_k);
                it_t = (it_k == 4'd0) ? intro_age - 8'd10 : intro_age - (8'd24 + {it_k, 2'b0} + {it_k, 1'b0});
                ip_dy <= (it_t >= 8'd4) ? it_y1 : it_y0 + (((it_y1 - it_y0) * $signed({4'd0, it_t})) >>> 2);
            end else begin
                it_t = intro_age - 8'd84;
                ip_dy <= (it_t >= 8'd8) ? 12'sd0 : (arcade_dy(4'd9) * $signed({4'd0, 8'd8 - it_t})) >>> 3;
            end
            // lampo nei due frame dopo ogni capsula presa
            ip_flash <= intro_age >= 8'd30 && intro_age < 8'd86 &&
                        (intro_age - 8'd30) - ({it_m[11:8], 2'b0} + {it_m[11:8], 1'b0}) < 8'd2;
        end
        K_TWIST: if (intro_age >= 8'd6 && intro_age < 8'd66) begin
            // corre su e giù con un'ampiezza che cala, inclinata con la velocità
            it_t = intro_age - 8'd6;
            it_amp = 12'sd22 - (($signed({4'd0, it_t}) * 3) >>> 3);
            it_i = (it_t * 57) >> 4;
            it_m = it_amp * sin_q8(it_i);
            ip_dy <= it_m >>> 8;
            it_m = it_amp * sin_q8(it_i + 6'd16);
            it_y0 = -(it_m >>> 10);
            ip_tilt <= (it_y0 > 3) ? 3'sd3 : (it_y0 < -3) ? -3'sd3 : it_y0[2:0];
        end
        K_HAMMER: begin
            // carica all'indietro, colpo in avanti, ritorno
            if (intro_age >= 8'd40 && intro_age < 8'd48) ip_dx <= it_a - 12'sd39;
            else if (intro_age >= 8'd49 && intro_age < 8'd55)
                ip_dx <= (intro_age <= 8'd50) ? -12'sd8 : -12'sd8 + ((it_a - 12'sd50) <<< 1);
        end
        K_TITAN: begin
            // cresce dal pavimento a scatti di 1/24 dell'altezza ogni 3 frame
            ip_show <= intro_age >= 8'd6;
            it_k = 4'd0;
            it_t = (intro_age < 8'd6) ? 8'd0 : (((intro_age - 8'd6) * 11) >> 5) + 8'd1;    // / 3
            // altezza 48: un passo di 2 pixel
            if (it_t < 8'd24) begin
                ip_h <= {1'b0, it_t, 1'b0};
                ip_dy <= 12'sd24 - $signed({4'd0, it_t});
            end
            ip_flash <= intro_age >= 8'd78 && intro_age < 8'd82;
        end
        K_BLASTER: begin
            // da una parte, all'altezza del nome; poi scende a quella delle capsule
            ip_show <= intro_age >= 8'd4;
            ip_dx <= 12'sd120;
            ip_dy <= (intro_age < 8'd64) ? 12'sd41 : (intro_age >= 8'd73) ? 12'sd78 : 12'sd41 + ((it_a - 12'sd64) <<< 2);
        end
        K_RUSH: begin
            // carica sul bordo lampeggiando, poi uno scatto lunghissimo con le immagini
            if (intro_age < 8'd16) begin
                it_t = (intro_age * 11) >> 5;                                     // / 3
                ip_show <= intro_age >= 8'd4 && !it_t[0];
                ip_dx <= 12'sd140;
            end else begin
                it_t = intro_age - 8'd16;
                ip_dx <= (it_t >= 8'd3) ? 12'sd0 : 12'sd105 - $signed({4'd0, it_t}) * 35;
                it_y1 = (it_t >= 8'd3) ? 12'sd0 : 12'sd105 - $signed({4'd0, it_t}) * 35;
                ip_gx[1] <= 12'sd140 - ((12'sd140 - it_y1) >>> 2);
                ip_gx[2] <= 12'sd140 - ((12'sd140 - it_y1) >>> 1);
                ip_gx[3] <= 12'sd140 - (((12'sd140 - it_y1) * 3) >>> 2);
                ip_fade <= (it_t < 8'd4) ? 2'd3 : (it_t < 8'd10) ? 2'd2 : (it_t < 8'd16) ? 2'd1 : 2'd0;
            end
        end
        K_GUARDIAN: begin
            ip_show <= intro_age >= 8'd4;
            ip_dx <= -12'sd10;
        end
        default: ;
    endcase
end

// riga dell'elenco della scelta della racchetta (righe di 20 pixel da y = 74), senza divisioni
function integer row20(input [9:0] yy);
    row20 = (yy >= 94) + (yy >= 114) + (yy >= 134) + (yy >= 154) + (yy >= 174) + (yy >= 194);
endfunction

// inclinazione di TWIST dalla velocità della racchetta (motion), a gradini da -3 a 3
function signed [2:0] twist_tilt(input signed [31:0] m);
    reg signed [31:0] a;
    begin
        a = (m < 0) ? -m : m;
        twist_tilt = (a > TILT3) ? 3'sd3 : (a > TILT2) ? 3'sd2 : (a > TILT1) ? 3'sd1 : 3'sd0;
        if (m < 0) twist_tilt = -twist_tilt;
    end
endfunction

// ------------------------------------------------------------- fotografia del frame

// larghezza del nome nella scritta: bonus o mossa speciale (con "MAX " davanti al livello 2)
wire       label_mx = label_move != 2'd0 && label_max;
wire [6:0] label_name_w = (label_move != 2'd0) ? move_w({2'd0, label_move == 2'd2}) + (label_mx ? NX_MAX_W + 3 : 0)
                                               : {1'b0, name_w(label_bonus)};
// larghezza di tutta la scritta ("P1 " + nome + "!") in pixel del font, a scala 1
wire [6:0] label_w_n = NX_P1_W + 3 + label_name_w + 1 + NX_BANG_W;

// Tipi della scritta (`label_kind`), come rust/game/src/next_ui.rs:
// - LK_BONUS, "P1 SMASH!": si accende e si spegne come un vecchio televisore. In 72 frame: una riga
//   bianca che si allarga (4 frame), l'immagine che si apre in altezza con i bordi bianchi (4), ferma,
//   che si richiude (3), la riga che si stringe (4), il puntino;
// la scritta è a scala 1 (righe del font 222-230, lettere 223-229), su un riquadro di 20 righe;
// - LK_ARMED, mossa armata: solo i trattini sotto le lettere (due righe con la MAX), che si
//   disegnano dal lato del giocatore, una lettera (6 pixel) ogni 2 frame, e si accendono di giallo mentre la
//   palla arriva verso di lui;
// - LK_HIT, colpo della mossa (60 frame): per 2 frame blocchi bianchi al posto delle lettere, poi la
//   scritta, bianca fino al frame 4; i trattini accesi fino al 24; dal 44 lampeggia.
localparam [1:0] LK_BONUS = 2'd0, LK_ARMED = 2'd1, LK_HIT = 2'd2;
localparam integer LABEL_TOP = 222;     // prima riga del font della scritta
localparam integer LABEL_MID = 228;     // riga centrale del riquadro (218-237)
// mezza altezza della fascia che si apre (frame 4-7) e si richiude (frame 64-66)
function [3:0] crt_open(input [1:0] k);
    case (k)
        2'd0: crt_open = 4'd3;  2'd1: crt_open = 4'd5;  2'd2: crt_open = 4'd8;  default: crt_open = 4'd10;
    endcase
endfunction
reg        crt_line, crt_dot, crt_edge;
reg [3:0]  crt_hh;                      // mezza altezza della fascia aperta
reg [7:0]  crt_lw;                      // mezza larghezza della riga
reg [9:0]  dash_rev;                    // trattini disegnati: pixel dal lato del giocatore
reg [9:0]  dash_lit;                    // trattini accesi: pixel dal lato del giocatore
// v * n / 4 con n da 1 a 4, senza moltiplicazioni
function [7:0] quarters(input [7:0] v, input [2:0] n);
    case (n)
        3'd1: quarters = v >> 2;
        3'd2: quarters = v >> 1;
        3'd3: quarters = (v >> 1) + (v >> 2);
        default: quarters = v;
    endcase
endfunction
// mossa armata: strada fatta dalla palla verso chi l'ha armata (dalla racchetta avversaria), in pixel
// fino a 255; 0 se va dall'altra parte
wire signed [10:0] arm_d = label_player ? $signed({1'b0, ball_col(ball_x)}) - $signed({1'b0, px_of(pad0_x)})
                                        : $signed({1'b0, px_of(pad1_x)}) - $signed({1'b0, ball_col(ball_x)});
wire       arm_toward = label_player ? ball_vx > 0 : ball_vx < 0;
wire [7:0] arm_p = !arm_toward ? 8'd0 : (arm_d < 0) ? 8'd0 : (arm_d > 255) ? 8'd255 : arm_d[7:0];
// trattini accesi: strada * larghezza della scritta / 256
wire [15:0] arm_lit = arm_p * {1'b0, label_w_n};

reg        cv [0:3];
reg [2:0]  cbon [0:3];
reg [9:0]  csx [0:3];                  // angolo in alto a sinistra della capsula
reg [9:0]  csy [0:3];
reg [3:0]  rs [0:5];                   // riserve (8 = posto vuoto)
reg [1:0]  sl [0:1];
reg [3:0]  arm [0:1];
reg        spin [0:1];
reg [9:0]  pcx [0:1];                  // centro delle racchette
reg [9:0]  pcy [0:1];
reg [9:0]  bx, by, bside;              // palla: centro (arrotondato come in pong_render) e lato
reg        bleft;                      // la palla va verso sinistra
// palla con un effetto (boost, CURVE, STEER, SUPER, SLOW, mossa in volo, BULLET): ha la coda
wire       fx_on = nxt && (ball_boost != 32'sd65536 || curve != 0 || next_flags[5] || next_flags[2] ||
                           slow_timer != 0 || next_flags[10:9] != 2'd0 || bullet);
// la palla ha cambiato verso dal frame prima: un colpo (o una nuova battuta)
wire       vflip = (ball_vx < 0) != bleft;
reg        comet, trail_on, ring_on, cap_blink;
reg        ghost_on, bhide;                // GHOST in corso; palla nascosta in questo frame
reg        steer_on, steer_side;          // STEER: palla guidata e chi la guida
reg [5:0]  angle;
reg [9:0]  hx [0:HIST-1];              // scia: posizioni dei frame precedenti (0 = la più recente)
reg [9:0]  hy [0:HIST-1];
reg [HIST-1:0] hv;
reg [9:0]  mx [1:TRAIL];               // coda: punto a metà tra le posizioni k - 1 e k
reg [9:0]  my [1:TRAIL];
reg [9:0]  label_x;
reg [6:0]  label_w;
integer    i;
// tipi di racchetta
reg [2:0]  kd [0:1];
reg [9:0]  kh [0:1];                  // altezza in pixel
reg signed [11:0] kl [0:1];           // colonna sinistra e riga alta del rettangolo di pong_render
reg signed [11:0] kt [0:1];
reg signed [2:0] ktilt [0:1];
reg        kshot [0:7];               // colpi del BLASTER, 4 * lato + posto
reg [9:0]  ksx [0:7];
reg [9:0]  ksy [0:7];
reg [2:0]  kammo [0:1];               // colpi nel caricatore
reg [1:0]  kfade [0:1];               // RUSH: intensità delle immagini dello scatto
reg signed [11:0] kg [0:5];           // RUSH: colonna sinistra delle immagini, 3 * lato + (k - 1)
reg signed [11:0] gd;
reg [4:0]  kwall [0:1];               // GUARDIAN: settori del muro in piedi
reg [4:0]  khit [0:1];                // GUARDIAN: settore che lampeggia (con kflash)
reg        kflash [0:1];
reg        kgray [0:1];
// mosse speciali
reg        msup;
reg [7:0]  mtr [0:1];                 // barra
reg        marm [0:1];                // mossa armata (STRAIGHT SHOT o RISING STRIKE)
reg        mrise [0:1];               // la mossa armata è RISING STRIKE
reg        mmax [0:1];                // mossa armata di livello 2: racchetta gialla
reg        mok [0:1];                 // mossa possibile adesso
reg [1:0]  mspf;                      // tiro della mossa in volo
reg [4:0]  ckt [0:1];                 // colpo di una mossa: frame rimasti (KICK_FRAMES di pong_top)
reg        ckr [0:1];                 // ... con RISING STRIKE
reg        ckm [0:1];                 // ... con la MAX
reg        rbon;                      // RISING STRIKE impennata: quadrato in (rbx, rby)
reg [9:0]  rbx, rby;

// GUARDIAN: settore del muro della riga y (0 in alto: comprende la banda, dove il muro non si
// disegna), riga del primo tratto e riga dopo l'ultima del settore; la riga è in un tratto del muro.
// Con le mosse speciali la barra sotto la riserva (righe BAR_Y..BAR_Y+4) esce dalla banda: allora il
// primo settore comincia 2 righe sotto la barra, per non toccarla
wire [2:0] wall_sec = (y >= WALL_B4) ? 3'd4 : (y >= WALL_B3) ? 3'd3 : (y >= WALL_B2) ? 3'd2 :
                      (y >= WALL_B1) ? 3'd1 : 3'd0;
reg  [9:0] wall_lo, wall_hi;
always @* begin
    case (wall_sec)
        3'd0: begin wall_lo = msup ? WALL_TOP_SUP : WALL_TOP + 2; wall_hi = WALL_B1 - 2; end
        3'd1: begin wall_lo = WALL_B1 + 2;  wall_hi = WALL_B2 - 2; end
        3'd2: begin wall_lo = WALL_B2 + 2;  wall_hi = WALL_B3 - 2; end
        3'd3: begin wall_lo = WALL_B3 + 2;  wall_hi = WALL_B4 - 2; end
        default: begin wall_lo = WALL_B4 + 2; wall_hi = H - 2; end
    endcase
end
wire [9:0] wall_dy = y - wall_lo;
wire       wall_row = y >= wall_lo && y < wall_hi && wall_dy[2:0] < 3'd5;
// BULLET: scattato, armato, chi l'ha attivato, rampa, alone; immagini della palla (gx, gy, gv) e fase
// del campionamento
reg        bon, barm, bsd, bramp;
reg [1:0]  bblur;
reg [1:0]  bcold;                     // racchette (e oggetti) che diventano grigi
reg [9:0]  gx [0:GHOSTS-1];
reg [9:0]  gy [0:GHOSTS-1];
reg [GHOSTS-1:0] gv;
reg [1:0]  gph;
initial begin
    gv = {GHOSTS{1'b0}};
    gph = 2'd0;
end

// v / 3 per v fino a 31 (le cifre a scala 3, sempre dentro la loro casella), senza divisore
function [3:0] div3(input [9:0] v);
    reg [9:0] t;
    begin
        t = v[4:0] * 10'd11;
        div3 = t[8:5];
    end
endfunction
// v / 5 esatto per v a 14 bit (il lato della cometa), con una moltiplicazione per una costante
function [9:0] div5(input [13:0] v);
    reg [31:0] t;
    begin
        t = v * 32'd52429;
        div5 = t[27:18];
    end
endfunction

// il pixel p è nel tratto lungo s che parte h pixel prima di c (0 <= p - c + h < s), con i conti a
// 14 bit: come `p - (c - h) < s` con le costanti intere (a 32 bit), che però costa tre volte tanto
function span(input [9:0] p, input [9:0] c, input [10:0] h, input [11:0] s);
    reg signed [13:0] d;
    begin
        d = $signed({4'b0, p}) - $signed({4'b0, c}) + $signed({3'b0, h});
        span = !d[13] && d < $signed({2'b0, s});
    end
endfunction

function [9:0] px_of(input signed [31:0] v);
    px_of = v[25:16];
endfunction

// centro della palla in pixel, arrotondato come la disegna pong_render: col_of(x - r) = ball_col(x) - r
// e row_first(y + r) = ball_row(y) - r con il raggio intero. Con px_of (troncato) coda, righe e buco
// della palla finivano un pixel accanto alla palla quando la parte frazionaria superava 0,5
function [9:0] ball_col(input signed [31:0] v);
    reg signed [31:0] t;
    begin
        t = (v + 32'sd32767) >>> 16;
        ball_col = t[9:0];
    end
endfunction

function [9:0] ball_row(input signed [31:0] v);
    reg signed [31:0] t;
    begin
        t = ((P_HEIGHT - 32'sd32768 - v) >>> 16) + 32'sd1;
        ball_row = t[9:0];
    end
endfunction

// bordi del rettangolo di una racchetta come in pong_render (col_of e row_first)
function signed [11:0] left_col(input signed [31:0] v);
    reg signed [31:0] t;
    begin
        t = (v - (P_PAD_WIDTH >>> 1) - 32'sd32768 + 32'sd65535) >>> 16;
        left_col = t[11:0];
    end
endfunction

function signed [11:0] top_row(input signed [31:0] yv, input [9:0] h);
    reg signed [31:0] t;
    begin
        t = ((P_HEIGHT - 32'sd32768 - (yv + ($signed({h, 16'd0}) >>> 1))) >>> 16) + 32'sd1;
        top_row = t[11:0];
    end
endfunction

// Salto del TELEPORT in pixel dello schermo (y verso il basso): per l'entrata e per l'uscita,
// la linea del portale e le righe [lo, hi) di racchetta visibili oltre la linea
reg signed [11:0] w_from, w_to, w_top, en_edge, en_lo, en_hi, ex_edge, ex_lo, ex_hi, PH, w_d;
reg [5:0] w_k, w_sunk, w_out;
reg [2:0] w_kind;
reg w_down;
always @(*) begin
    // avanzamento dalla x della palla contata dal bordo del giocatore: pixel affondati (fino a
    // WARP_STEP) e pixel usciti
    w_d = warp_side ? W - $signed({2'b0, px_of(ball_x)}) : $signed({2'b0, px_of(ball_x)});
    w_sunk = (w_d >= WARP_SUNK) ? 6'd0 : (w_d <= WARP_SUNK - WARP_STEP) ? WARP_STEP : WARP_SUNK - w_d;
    w_out = (w_d >= WARP_RISE) ? 6'd0 : (w_d <= WARP_RISE - WARP_STEP) ? WARP_STEP : WARP_RISE - w_d;
    // la racchetta che salta ha l'altezza del suo tipo
    w_kind = nxt ? (warp_side ? kind1[2:0] : kind0[2:0]) : K_NONE;
    PH = $signed({2'b0, kind_px_h(w_kind)});
    w_from = H - $signed({2'b0, px_of(warp_from)});
    w_to = H - $signed({2'b0, px_of(warp_side ? pad1_y : pad0_y)});
    w_down = w_to > w_from;
    // entrata: la linea sta sul lato verso cui salta la racchetta, che ci affonda dentro
    w_k = w_sunk;
    if (w_down) begin
        en_edge = w_from + (PH >>> 1);
        w_top = w_from - (PH >>> 1) + kind_warp_shift(w_kind, w_k);
        en_lo = w_top;
        en_hi = (w_top + PH < en_edge) ? w_top + PH : en_edge;
    end else begin
        en_edge = w_from - (PH >>> 1);
        w_top = w_from - (PH >>> 1) - kind_warp_shift(w_kind, w_k);
        en_lo = (w_top > en_edge) ? w_top : en_edge;
        en_hi = w_top + PH;
    end
    // uscita: la linea sta sul lato opposto della posizione d'arrivo, la racchetta ne esce
    w_k = w_out;
    if (w_down) begin
        ex_edge = w_to - (PH >>> 1);
        w_top = w_to - (PH >>> 1) - (PH - kind_warp_shift(w_kind, w_k));
        ex_lo = (w_top > ex_edge) ? w_top : ex_edge;
        ex_hi = w_top + PH;
    end else begin
        ex_edge = w_to + (PH >>> 1);
        w_top = w_to - (PH >>> 1) + (PH - kind_warp_shift(w_kind, w_k));
        ex_lo = w_top;
        ex_hi = (w_top + PH < ex_edge) ? w_top + PH : ex_edge;
    end
end

reg        wv, wsd, en_on, ex_on;
reg [9:0]  wx;
reg signed [11:0] wen_edge, wen_lo, wen_hi, wex_edge, wex_lo, wex_hi;
always @(posedge clk) begin
    if (snapshot) begin
        wv <= nxt && warp_on;
        wsd <= warp_side;
        wx <= px_of(warp_side ? pad1_x : pad0_x);
        // il primo portale resta finché la racchetta non è affondata, il secondo si apre a metà
        en_on <= w_sunk < WARP_STEP;
        ex_on <= w_sunk >= WARP_STEP / 2;
        wen_edge <= en_edge;
        wen_lo <= en_lo;
        wen_hi <= en_hi;
        wex_edge <= ex_edge;
        wex_lo <= ex_lo;
        wex_hi <= ex_hi;
    end
end

always @(posedge clk) begin
    if (snapshot) begin
        for (i = 0; i < 4; i = i + 1) begin
            cv[i] <= nxt && caps_flags[4*i + 3];
            cbon[i] <= caps_flags[4*i +: 3];
            csx[i] <= px_of(caps_x[32*i +: 32]) - CAP / 2;
            csy[i] <= H - px_of(caps_y[32*i +: 32]) - CAP / 2;
        end
        for (i = 0; i < 3; i = i + 1) begin
            rs[i] <= player0[4*i +: 4];
            rs[i + 3] <= player1[4*i +: 4];
        end
        sl[0] <= player0[13:12];
        sl[1] <= player1[13:12];
        arm[0] <= nxt ? player0[19:16] : B_NONE;
        arm[1] <= nxt ? player1[19:16] : B_NONE;
        spin[0] <= nxt && player0[19:16] == B_SUPER && player0[15:14] == 2'd0;
        spin[1] <= nxt && player1[19:16] == B_SUPER && player1[15:14] == 2'd0;
        bon <= nxt && bullet;
        barm <= nxt && bullet_armed;
        bsd <= bullet_side;
        bramp <= bullet_ramp;
        bblur <= nxt ? bullet_blur : 2'd0;
        bcold <= {nxt && bullet && !bullet_side, nxt && bullet && bullet_side};
        // immagini della palla: ogni GHOST_STEP frame la posizione più vecchia della storia
        gph <= (gph == GHOST_STEP - 1) ? 2'd0 : gph + 2'd1;
        if (gph == GHOST_STEP - 1) begin
            gx[0] <= hx[HIST - 1];
            gy[0] <= hy[HIST - 1];
            gv[0] <= hv[HIST - 1];
            for (i = 1; i < GHOSTS; i = i + 1) begin
                gx[i] <= gx[i - 1];
                gy[i] <= gy[i - 1];
                gv[i] <= gv[i - 1];
            end
        end
        if (vflip) gv <= {GHOSTS{1'b0}};   // come la coda, ripartono a ogni colpo
        pcx[0] <= px_of(pad0_x);
        pcy[0] <= H - px_of(pad0_y);
        pcx[1] <= px_of(pad1_x);
        pcy[1] <= H - px_of(pad1_y);
        angle <= tick[5:0];
        for (i = 0; i < 2; i = i + 1) begin
            kd[i] <= nxt ? (i ? kind1[2:0] : kind0[2:0]) : K_NONE;
            kh[i] <= kind_px_h(nxt ? (i ? kind1[2:0] : kind0[2:0]) : K_NONE);
            kl[i] <= left_col(i ? pad1_x : pad0_x);
            kt[i] <= top_row(i ? pad1_y : pad0_y, kind_px_h(nxt ? (i ? kind1[2:0] : kind0[2:0]) : K_NONE));
            ktilt[i] <= twist_tilt(i ? pad1_motion : pad0_motion);
            kammo[i] <= i ? kind1[10:8] : kind0[10:8];
            // RUSH: immagini a 1/4, 1/2 e 3/4 della strada da casa a dove si trova
            kfade[i] <= i ? rush_fade[3:2] : rush_fade[1:0];
            gd = left_col(i ? pad1_x : pad0_x) - left_col(i ? P_WIDTH - P_PAD_START_POS : P_PAD_START_POS);
            kg[3*i] <= left_col(i ? P_WIDTH - P_PAD_START_POS : P_PAD_START_POS) + (gd >>> 2);
            kg[3*i + 1] <= left_col(i ? P_WIDTH - P_PAD_START_POS : P_PAD_START_POS) + (gd >>> 1);
            kg[3*i + 2] <= left_col(i ? P_WIDTH - P_PAD_START_POS : P_PAD_START_POS) + gd - (gd >>> 2);
            kwall[i] <= i ? wall1 : wall0;
            khit[i] <= i ? wall_hit1 : wall_hit0;
            kflash[i] <= barrier_flash[i];
            // la racchetta con un bonus armato lampeggia in grigio, come in pong_render; nel bullet
            // time è grigia quella dell'avversario di chi l'ha attivato
            kgray[i] <= (nxt && (i ? player1[19:16] : player0[19:16]) != B_NONE && !tick[4]) ||
                        (nxt && bullet && bullet_side != i);
            // mosse speciali; la scia del salto va dalla y del frame prima a quella di adesso
            mtr[i] <= i ? super1[7:0] : super0[7:0];
            marm[i] <= nxt && sup && (i ? super1[11:8] != 4'd0 : super0[11:8] != 4'd0);
            mrise[i] <= (i ? super1[9:8] : super0[9:8]) == 2'd0;
            mmax[i] <= nxt && sup && (i ? (super1[9] || super1[11]) : (super0[9] || super0[11]));
            mok[i] <= nxt && move_ok[i];
            ckt[i] <= nxt ? (i ? kick1[4:0] : kick0[4:0]) : 5'd0;
            ckr[i] <= i ? kick1[5] : kick0[5];
            ckm[i] <= i ? kick1[6] : kick0[6];
        end
        msup <= nxt && sup;
        // impennata di RISING STRIKE: il punto è dove si trova la palla nel primo frame
        rbon <= nxt && sup && rise_flash;
        if (!rbon) begin
            rbx <= ball_col(ball_x);
            rby <= ball_row(ball_y);
        end
        mspf <= nxt ? next_flags[10:9] : 2'd0;
        for (i = 0; i < 8; i = i + 1) begin
            kshot[i] <= nxt && (i >= 4 ? kind1[i] : kind0[4 + i]);
            ksx[i] <= px_of(shots_x[32*i +: 32]);
            ksy[i] <= H - px_of(shots_y[32*i +: 32]);
        end
        cap_blink <= tick[5];
        // palla cometa più grande, con la scia lunga; scia a puntini per gli altri effetti
        comet <= nxt && next_flags[2] && next_flags[4:3] == 2'd2;
        trail_on <= fx_on;
        steer_on <= nxt && next_flags[5];
        // GHOST: niente code né immagini della palla (la tradirebbero), come su PC; da nascosta neanche
        // la testa della cometa e le righe di STRAIGHT SHOT
        ghost_on <= nxt && next_flags[0];
        bhide <= ball_hidden;
        steer_side <= next_flags[6];
        ring_on <= nxt && slow_timer != 0 && tick[4];
        bside <= (next_flags[2] && next_flags[4:3] == 2'd2) ? div5({px_of(ball_r), 4'd0}) : px_of(ball_r) * 2;
        bx <= ball_col(ball_x);
        by <= ball_row(ball_y);
        bleft <= ball_vx < 0;
        hx[0] <= ball_col(ball_x);
        hy[0] <= ball_row(ball_y);
        // a ogni colpo (la palla cambia verso) la coda riparte da qui: altrimenti per qualche frame
        // resterebbe piegata sul percorso d'arrivo, e nel colore del nuovo tiro
        hv <= vflip ? {{(HIST-1){1'b0}}, fx_on} : {hv[HIST-2:0], fx_on};
        for (i = 1; i < HIST; i = i + 1) begin
            hx[i] <= hx[i - 1];
            hy[i] <= hy[i - 1];
        end
        mx[1] <= (ball_col(ball_x) + hx[0]) >> 1;
        my[1] <= (ball_row(ball_y) + hy[0]) >> 1;
        for (i = 2; i <= TRAIL; i = i + 1) begin
            mx[i] <= mx[i - 1];
            my[i] <= my[i - 1];
        end
        // scritta del bonus o della mossa: "P1 " + nome + "!" a scala 2, centrata in basso
        label_w <= label_w_n;
        label_x <= W / 2 - (label_w_n >> 1);
        // televisore della scritta del bonus (vedi LK_BONUS); la riga è larga quanto il riquadro
        crt_line <= 1'b0;
        crt_dot <= 1'b0;
        crt_edge <= 1'b0;
        crt_hh <= 4'd10;
        crt_lw <= 8'd0;
        if (label_age < 7'd4) begin
            crt_line <= 1'b1;
            crt_lw <= quarters({2'b0, label_w_n[6:1]} + 8'd4, label_age[2:0] + 3'd1);
        end else if (label_age < 7'd8) begin
            crt_hh <= crt_open(label_age[1:0]);                                   // 3, 5, 8, 10
            crt_edge <= 1'b1;
        end else if (label_age >= 7'd64 && label_age < 7'd67) begin
            crt_hh <= crt_open(2'd2 - label_age[1:0]);                            // 8, 5, 3
            crt_edge <= 1'b1;
        end else if (label_age >= 7'd67 && label_age < 7'd71) begin
            crt_line <= 1'b1;
            crt_lw <= quarters({2'b0, label_w_n[6:1]} + 8'd4, 3'd7 - label_age[2:0]);  // 4/4 .. 1/4
        end else if (label_age >= 7'd71) begin
            crt_dot <= 1'b1;
        end
        // trattini della mossa armata: una lettera (6 pixel) ogni 2 frame, e quelli accesi
        dash_rev <= {1'b0, label_age, 1'b0} + {2'b0, label_age};
        dash_lit <= arm_lit[15:8];
    end
end

// ------------------------------------------------------------------- pixel

// capsula di lato CAP con l'angolo in (sx, sy): 1 = bordo o icona, in negativo se `inv`
function cap_px(input [9:0] px, input [9:0] py, input [9:0] sx, input [9:0] sy, input [3:0] b, input inv);
    reg [9:0] dx, dy;
    reg in_cap, on_border, ic;
    begin
        dx = px - sx;
        dy = py - sy;
        in_cap = dx < CAP && dy < CAP;
        on_border = dx == 0 || dy == 0 || dx == CAP - 1 || dy == CAP - 1;
        ic = icon_lit(b[2:0], dx - (CAP - 9) / 2, dy - (CAP - 9) / 2);
        cap_px = in_cap && (inv ? !ic : (on_border || ic));
    end
endfunction

reg        on, gray_px, lb;
reg        lbox, ltext, lcol, ldash;      // scritta del bonus o della mossa
reg        pad_box;                       // pixel di una racchetta: la scritta passa sotto
reg [9:0]  ldx, lpos;
reg [6:0]  col;                        // indice della tavolozza (pal)
reg [9:0]  dx, dy, sx, cxl;
reg [1:0]  t_count;
reg [3:0]  rb;                         // codice del bonus della riga r della scelta
reg [4:0]  trow;
reg signed [10:0] sdx, sdy;
reg signed [21:0] u8, v8;
reg signed [11:0] sy;
reg        w_col, w_line;
reg [2:0]  kc;
reg signed [11:0] kx, ky, kq, kr, ka;
reg signed [11:0] ke, kf, kv, kb, ko;  // colpo di una mossa: frame dal colpo, davanti, dal centro, dietro
reg [2:0]  kcur;
reg [9:0]  kcx;
reg [2:0]  pk;                         // sfilata del finale: colonna e suo centro
reg [9:0]  pdx;
integer    k, p, r;
// mosse speciali: nome della mossa nella scritta e barre dei due giocatori (un solo confronto per pixel)
reg        mv_code, mv_on, hb_p;
reg [9:0]  mv_dx, mv_dy, bq_x, bq_y;
reg [7:0]  bq_lvl;
reg [1:0]  bq;
// scelta dei bonus: lato (1 = destra) e riga del pixel, con la sua prima riga, bonus presi e cursore
reg        bp;
// riserve in partita: lato e posto del pixel, il suo bonus, se è il selezionato, e il pixel che ne esce
reg        rv_p, rv_sel, rv_on;
reg [1:0]  rv_k;
reg [3:0]  rv_b;
reg [6:0]  rv_col;
// chiamate condivise tra le schermate (vedi il pixel)
reg        sh_game, sh_pickb, sh_name, sh_kname;
reg [9:0]  sh_cxb, sh_cxl, sh_kcx;
reg [2:0]  sh_kcur, sh_ka, sh_kb;
integer    sh_p, sh_r;
reg signed [11:0] sh_kx, sh_kq, sh_kr, sh_mx, sh_mq, sh_my, sh_x0, sh_x1;
// pixel delle due racchette in partita: codice del tipo (kind_px) e dentro il rettangolo
reg [2:0]  kcp [0:1];
reg        kin [0:1];
reg [2:0]  br, bcur;
reg [9:0]  by0;
reg [5:0]  bmask;

always @(*) begin
    on = 1'b0;
    col = WHITE;
    gray_px = 1'b0;
    lb = 1'b0;
    trow = 5'd0;
    dx = 10'd0;
    dy = 10'd0;
    sx = 10'd0;
    cxl = 10'd0;
    sdx = 11'sd0;
    sdy = 11'sd0;
    u8 = 22'sd0;
    v8 = 22'sd0;
    t_count = 2'd0;
    rb = 4'd0;
    sy = $signed({2'b0, y});
    kc = KP_NONE;
    kcur = 3'd0;
    kcx = 10'd0;
    kx = 12'sd0;
    ky = 12'sd0;
    kq = 12'sd0;
    ka = 12'sd0;
    kr = 12'sd0;
    w_col = x - (wx - PW / 2) < PW;
    w_line = x - (wx - WARP_LINE_HALF) < 2 * WARP_LINE_HALF;
    hb_p = x >= W / 2;
    mv_code = label_move == 2'd2;
    mv_dx = x - label_x - (NX_P1_W + 3) - (label_mx ? NX_MAX_W + 3 : 0);
    mv_dy = y - LABEL_TOP;
    ldx = x - label_x;
    lbox = 1'b0;
    ltext = 1'b0;
    lcol = 1'b0;
    ldash = 1'b0;
    lpos = 10'd0;
    pad_box = 1'b0;
    bp = 1'b0;
    br = 3'd0;
    bcur = 3'd0;
    by0 = 10'd0;
    bmask = 6'd0;
    rv_p = 1'b0;
    rv_k = 2'd0;
    rv_b = 4'd0;
    rv_sel = 1'b0;
    rv_on = 1'b0;
    rv_col = BLACK;
    kcp[0] = KP_NONE;
    kcp[1] = KP_NONE;
    kin[0] = 1'b0;
    kin[1] = 1'b0;
    // barre nella banda in alto: la sinistra da BAR_X, la destra speculare
    bq_x = hb_p ? (W - 1 - BAR_X) - x : x - BAR_X;
    bq_y = y - (BAR_Y - 2);
    bq_lvl = mtr[hb_p];
    mv_on = move_lit({2'd0, mv_code}, mv_dx, mv_dy);
    bq = bar_px(bq_x, bq_y, bq_lvl);

    // sfilata del finale: colonna sotto il pixel (sette, centri END_COL0..6), solo confronti
    pk = (x >= (END_COL0 + END_COL1) / 2) + (x >= (END_COL1 + END_COL2) / 2) + (x >= (END_COL2 + END_COL3) / 2) +
         (x >= (END_COL3 + END_COL4) / 2) + (x >= (END_COL4 + END_COL5) / 2) + (x >= (END_COL5 + END_COL6) / 2);
    pdx = (pk == 3'd0) ? END_COL0 : (pk == 3'd1) ? END_COL1 : (pk == 3'd2) ? END_COL2 : (pk == 3'd3) ? END_COL3 :
          (pk == 3'd4) ? END_COL4 : (pk == 3'd5) ? END_COL5 : END_COL6;

    // Chiamate condivise. Le schermate di scelta e la partita non sono mai insieme sullo schermo:
    // le funzioni più grandi (due kind_px, il nome del bonus e quello della racchetta) si fanno una
    // volta sola, con gli argomenti della schermata in corso; ogni schermata qui sotto ne usa il
    // risultato (sh_ka, sh_kb, sh_name, sh_kname) al posto della propria chiamata.
    sh_game = !((pick && pick_paddle) || intro || parade) && !pick;
    sh_pickb = !((pick && pick_paddle) || intro || parade) && pick;
    // scelta dei bonus: lato e riga del pixel (vedi la schermata)
    bp = x >= W / 2;
    bmask = bp ? pick_mask1 : pick_mask0;
    bcur = bp ? pick_cursor1 : pick_cursor0;
    br = (y >= 100) + (y >= 124) + (y >= 148) + (y >= 172) + (y >= 196);
    by0 = 76 + {br, 4'd0} + {br, 3'd0};
    rb = (br == 3'd5) ? B_STEER : {1'b0, br};
    sh_cxb = bp ? 3 * W / 4 : W / 4;
    // scelta della racchetta, presentazione e sfilata: anteprima (come la schermata qui sotto) e riga
    // della miniatura
    sh_p = (intro || parade) ? 0 : (x >= W / 2);
    sh_cxl = (sh_p == 0) ? W / 4 : 3 * W / 4;
    sh_kcur = parade ? pk : intro ? intro_kind : (sh_p == 0) ? kind_cursor0 : kind_cursor1;
    sh_kcx = parade ? pdx : intro ? W / 2 + (intro_right ? -ip_dx : ip_dx) : sh_cxl - 60;
    sh_kx = $signed({2'b0, x}) - ($signed({2'b0, sh_kcx}) - PW / 2);
    sh_kq = (parade || (intro ? intro_right : sh_p == 0)) ? sh_kx : PW - 1 - sh_kx;
    sh_kr = $signed({2'b0, y}) - ((parade ? END_PARADE_Y : intro ? INTRO_Y + ip_dy : 12'sd144) -
                                  ($signed({2'b0, intro ? ip_h : kind_px_h(sh_kcur)}) >>> 1));
    sh_r = row20(y);
    sh_mx = $signed({2'b0, x}) - ($signed({2'b0, sh_cxl}) - 25);
    sh_mq = (sh_p == 0) ? sh_mx : 1 - sh_mx;
    sh_my = $signed({2'b0, y}) - (74 + ((sh_r <<< 4) + (sh_r <<< 2)) + 9 - ($signed({2'b0, kind_px_h(sh_r[2:0])}) >>> 2));
    // partita: le due racchette
    sh_x0 = $signed({2'b0, x}) - kl[0];
    sh_x1 = $signed({2'b0, x}) - kl[1];
    // si scelgono gli argomenti e poi si chiama una volta (con due chiamate e la scelta del risultato
    // il circuito resterebbe doppio)
    sh_ka = kind_px(sh_game ? kd[0] : sh_kcur,
                    sh_game ? sh_x0 : sh_kq,
                    sh_game ? $signed({2'b0, y}) - kt[0] : sh_kr,
                    sh_game ? kh[0] : intro ? ip_h : kind_px_h(sh_kcur),
                    sh_game ? ktilt[0] : intro ? ip_tilt : (sh_kcur == K_TWIST) ? 3'sd3 : 3'sd0,
                    !sh_game && !intro, !sh_game && !intro);
    sh_kb = kind_px(sh_game ? kd[1] : sh_r[2:0],
                    sh_game ? PW - 1 - sh_x1 : sh_mq <<< 1,
                    sh_game ? $signed({2'b0, y}) - kt[1] : sh_my <<< 1,
                    sh_game ? kh[1] : kind_px_h(sh_r[2:0]),
                    sh_game ? ktilt[1] : (sh_r == K_TWIST) ? 3'sd3 : 3'sd0,
                    1'b0, !sh_game);
    sh_name = name_lit(sh_pickb ? rb[2:0] : label_bonus,
                       sh_pickb ? (x - (sh_cxb - 34)) >> 1 : ldx - (NX_P1_W + 3),
                       sh_pickb ? (y - by0) >> 1 : y - LABEL_TOP);
    sh_kname = kind_name_lit(parade ? pk : sh_r[2:0],
                             parade ? x - (pdx - kind_name_w(pk) / 2) : (x - (sh_cxl - 14)) >> 1,
                             parade ? y - (END_PARADE_NAME_Y - NX_NAME0_H / 2) : (y - 74 - ((sh_r <<< 4) + (sh_r <<< 2))) >> 1);

    if ((pick && pick_paddle) || intro || parade) begin
        // ------------------------------------------------- scelta della racchetta
        // Con `intro` (presentazione di CHALLENGE) solo l'anteprima della racchetta dell'avversario,
        // al centro e rivolta verso il giocatore, opaca solo sui suoi pixel: stesso disegno (e stessa
        // logica) dell'anteprima del giocatore sinistro, più le munizioni del BLASTER.
        // Con `parade` (sfilata del finale) la stessa anteprima nella colonna del pixel (rivolta a
        // destra, centrata in END_PARADE_Y, solo le prime parade_n) con il nome sotto a scala 1, nei
        // colori del finale: dettagli gialli, immagini del RUSH gialle che si diradano invece di scurirsi
        col = BLACK;
        on = !intro && !parade;
        if (!intro && !parade) begin
            if (nx_ppick_lit((x - (W - 2 * NX_PPICK_W) / 2) >> 1, (y - 6) >> 1)) col = ACCENT;
            trow = text_glyph(pick_secs >= 4'd10 ? 4'd1 : 4'd0, div3(y - 10'd30));
            if (y >= 30 && y < 30 + 3 * TEXT_H && x >= W / 2 - 17 && x < W / 2 - 17 + 3 * TEXT_W &&
                trow[TEXT_W - 1 - div3(x - (W / 2 - 17))]) col = WHITE;
            trow = text_glyph(pick_secs >= 4'd10 ? 4'd0 : pick_secs, div3(y - 10'd30));
            if (y >= 30 && y < 30 + 3 * TEXT_H && x >= W / 2 + 2 && x < W / 2 + 2 + 3 * TEXT_W &&
                trow[TEXT_W - 1 - div3(x - (W / 2 + 2))]) col = WHITE;
            if ((x == W / 2 - 1 || x == W / 2) && y >= 56 && y[2] == 1'b0) col = WHITE;
        end
        // ogni colonna sta nella sua metà dello schermo: il lato viene dal pixel e la colonna si disegna
        // una volta sola; nella presentazione e nella sfilata c'è solo quella di sinistra (p = 0)
        p = (intro || parade) ? 0 : (x >= W / 2);
        begin
            cxl = (p == 0) ? W / 4 : 3 * W / 4;
            kcur = parade ? pk : intro ? intro_kind : (p == 0) ? kind_cursor0 : kind_cursor1;
            if (!intro && !parade) begin
                if (p == 0 ? nx_p1_lit(x - (cxl - 50), y - 58) :
                    (cpu ? nx_cpu_lit(x - (cxl - 50), y - 58) : nx_p2_lit(x - (cxl - 50), y - 58)))
                    col = WHITE;
                if (kind_chosen[p] && nx_ok_lit(x - (cxl + 26), y - 58)) col = ACCENT;
            end
            // anteprima a grandezza reale della racchetta sotto il cursore, verso la mezzeria; nella
            // presentazione animata (ip_*) spostata, alta ip_h, inclinata, senza i segni fissi del
            // RUSH e del GUARDIAN (le immagini dello scatto qui sotto, il muro in challenge_render)
            kcx = parade ? pdx : intro ? W / 2 + (intro_right ? -ip_dx : ip_dx) : cxl - 60;
            kx = $signed({2'b0, x}) - ($signed({2'b0, kcx}) - PW / 2);
            kq = (parade || (intro ? intro_right : p == 0)) ? kx : PW - 1 - kx;
            kr = $signed({2'b0, y}) - ((parade ? END_PARADE_Y : intro ? INTRO_Y + ip_dy : 12'sd144) -
                                       ($signed({2'b0, intro ? ip_h : kind_px_h(kcur)}) >>> 1));
            kc = sh_ka;
            if ((intro || parade) && p != 0) kc = KP_NONE;     // nella presentazione una sola racchetta
            if (parade && pk >= parade_n) kc = KP_NONE;         // avversario non ancora entrato
            if (intro && !ip_show) kc = KP_NONE;
            // RUSH: le tre immagini dello scatto, più scure verso la partenza
            if (intro && p == 0 && ip_fade != 2'd0 && kc == KP_NONE)
                for (k = 1; k <= 3; k = k + 1)
                    if ($signed({2'b0, x}) - (W / 2 + (intro_right ? -ip_gx[k] : ip_gx[k]) - PW / 2) >= 0 &&
                        $signed({2'b0, x}) - (W / 2 + (intro_right ? -ip_gx[k] : ip_gx[k]) - PW / 2) < PW &&
                        kr >= 0 && kr < $signed({2'b0, ip_h}) && ip_fade + k >= 4) begin
                        // intensità: dalla più chiara (vicina alla racchetta, k = 3) alla più scura
                        on = 1'b1;
                        col = (ip_fade + k >= 6) ? GHOST3 : (ip_fade + k == 5) ? GHOST2 : GHOST1;
                    end
            if (kc == KP_BODY) col = (intro && ip_flash) ? ACCENT : WHITE;
            if (kc == KP_MARK) col = ACCENT;
            if (kc == KP_DETAIL) col = parade ? ACCENT : DETAIL;
            if (kc == KP_GHOST1) col = parade ? ((x[0] && y[0]) ? ACCENT : BLACK) : GHOST1;
            if (kc == KP_GHOST2) col = parade ? ((x[0] ^ y[0]) ? ACCENT : BLACK) : GHOST2;
            if (kc == KP_GHOST3) col = parade ? ACCENT : GHOST3;
            if (kc != KP_NONE && kc != KP_CUT) on = 1'b1;
            // BLASTER nella presentazione: il caricatore pieno dietro la racchetta, dal basso, come in
            // partita (2 colonne a 3-4 pixel dal retro, un rettangolino di 3 righe ogni 4 per colpo)
            ka = $signed({2'b0, kind_px_h(kcur)}) - 12'sd2 - kr;   // riga dal basso, da quella sopra il fondo
            if ((intro || (parade && pk < parade_n)) && p == 0 && kcur == K_BLASTER && (kq == -12'sd4 || kq == -12'sd3) &&
                ka >= 0 && ka < AMMO_ROWS && ka[1:0] != 2'd3) begin
                on = 1'b1;
                col = ACCENT;
            end
            // sfilata: il nome sotto la racchetta
            if (parade && p == 0 && pk < parade_n &&
                sh_kname) begin
                on = 1'b1;
                col = WHITE;
            end
            // sette righe ogni 20 pixel: cursore, miniatura e nome
            if (!intro && !parade && y >= 74 && y < 74 + 20 * 7) begin
                r = row20(y);
                if (kcur == r && !kind_chosen[p] && !pick_ready &&
                    nx_cursor_lit((x - (cxl - 42)) >> 1, (y - 74 - ((r <<< 4) + (r <<< 2))) >> 1))
                    col = ACCENT;
                // miniatura a metà grandezza
                kx = $signed({2'b0, x}) - ($signed({2'b0, cxl}) - 25);
                kq = (p == 0) ? kx : 1 - kx;
                ky = $signed({2'b0, y}) - (74 + ((r <<< 4) + (r <<< 2)) + 9 - ($signed({2'b0, kind_px_h(r[2:0])}) >>> 2));
                kc = sh_kb;
                if (kc == KP_BODY) col = (kcur == r) ? WHITE : GRAY;
                if (kc == KP_MARK) col = (kcur == r) ? ACCENT : DIM;
                if (kc == KP_DETAIL) col = (kcur == r) ? DETAIL : DIM;
                if (kc == KP_GHOST1 || (kc == KP_GHOST2 && kcur != r)) col = GHOST1;
                if (kc == KP_GHOST2 && kcur == r) col = GHOST2;
                if (kc == KP_GHOST3) col = (kcur == r) ? GHOST3 : GHOST2;
                if (sh_kname)
                    col = (kcur == r) ? (kind_chosen[p] ? ACCENT : WHITE) : GRAY;
            end
            // frase del tipo sotto la colonna
            if (!intro && !parade && tag_lit(kcur, x - (cxl - tag_w(kcur) / 2), y - 222)) col = GRAY;
        end
        if (!intro && !parade && pick_ready && blink < 6'd37 && nx_ready_lit((x - (W - 2 * NX_READY_W) / 2) >> 1, (y - 220) >> 1))
            col = ACCENT;
    end else if (pick) begin
        // ---------------------------------------------------- scelta dei bonus
        col = BLACK;
        on = 1'b1;                                         // schermo tutto nero
        if (nx_pick_lit((x - (W - 2 * NX_PICK_W) / 2) >> 1, (y - 6) >> 1)) col = ACCENT;
        // secondi rimasti, cifre a scala 3
        trow = text_glyph(pick_secs >= 4'd10 ? 4'd1 : 4'd0, div3(y - 10'd30));
        if (y >= 30 && y < 30 + 3 * TEXT_H && x >= W / 2 - 17 && x < W / 2 - 17 + 3 * TEXT_W &&
            trow[TEXT_W - 1 - div3(x - (W / 2 - 17))]) col = WHITE;
        trow = text_glyph(pick_secs >= 4'd10 ? 4'd0 : pick_secs, div3(y - 10'd30));
        if (y >= 30 && y < 30 + 3 * TEXT_H && x >= W / 2 + 2 && x < W / 2 + 2 + 3 * TEXT_W &&
            trow[TEXT_W - 1 - div3(x - (W / 2 + 2))]) col = WHITE;
        // mezzeria
        if ((x == W / 2 - 1 || x == W / 2) && y >= 56 && y[2] == 1'b0) col = WHITE;
        // ogni colonna sta nella sua metà dello schermo e ogni riga nelle sue 24 righe: lato e riga
        // vengono dal pixel, così cursore, capsula e nome si disegnano una volta sola (e non 12)
        cxl = sh_cxb;
        // intestazione: P1 / P2 / CPU e bonus presi su 3
        if (!bp ? nx_p1_lit(x - (cxl - 50), y - 58) :
            (cpu ? nx_cpu_lit(x - (cxl - 50), y - 58) : nx_p2_lit(x - (cxl - 50), y - 58)))
            col = WHITE;
        t_count = bmask[0] + bmask[1] + bmask[2] + bmask[3] + bmask[4] + bmask[5];
        trow = text_glyph({2'd0, t_count}, y - 59);
        if (y >= 59 && y < 59 + TEXT_H && x >= cxl + 26 && x < cxl + 26 + TEXT_W && trow[TEXT_W - 1 - (x - cxl - 26)])
            col = (t_count == 2'd3) ? WHITE : GRAY;
        if (nx_of3_lit(x - (cxl + 31), y - 58)) col = (t_count == 2'd3) ? WHITE : GRAY;
        // le sei righe, ogni 24 pixel da y = 76, alte 18: cursore, capsula e nome; l'ultima è STEER
        // (codice 6)
        if (y >= by0 && y < by0 + 18) begin
            if (bcur == br && !lock[bp] && t_count != 2'd3 && !pick_ready &&
                nx_cursor_lit((x - (cxl - 66)) >> 1, (y - by0) >> 1))
                col = ACCENT;
            if (cap_px(x, y, cxl - 52, by0 + 2, rb, bmask[br]))
                col = (bmask[br] || bcur == br) ? WHITE : GRAY;
            if (sh_name)
                col = (bmask[br] || bcur == br) ? WHITE : GRAY;
        end
        if (pick_ready && blink < 6'd37 && nx_ready_lit((x - (W - 2 * NX_READY_W) / 2) >> 1, (y - 220) >> 1))
            col = ACCENT;
    end else if (nxt) begin
        // --------------------------------------------------------------- partita
        // riserve in alto: tre posti per lato, il selezionato in negativo con una freccetta. I posti
        // non si toccano (4 pixel tra l'uno e l'altro): il lato e il posto vengono dal pixel e se ne
        // disegna uno solo (rv_on e rv_col), messo al suo turno nel giro dei lati qui sotto
        rv_p = x >= W / 2;
        rv_k = !rv_p ? (x >= 6 + CAP + 2) + (x >= 6 + 2 * (CAP + 4) - 2)
                     : (x < W - 6 - CAP - (CAP + 4) + CAP + 2) + (x < W - 6 - CAP - 2 * (CAP + 4) + CAP + 2);
        sx = !rv_p ? 6 + rv_k * (CAP + 4) : W - 6 - CAP - rv_k * (CAP + 4);
        rv_b = rs[3 * rv_p + rv_k];
        rv_sel = sl[rv_p] == rv_k;
        if (rv_b != B_NONE) begin
            if (cap_px(x, y, sx, 4, rv_b, rv_sel)) begin
                rv_on = 1'b1;
                // i bonus rari (SUPER e BULLET) in giallo
                rv_col = (rv_b == B_SUPER || rv_b == B_BULLET) ? ACCENT : WHITE;
            end
            // in negativo: dentro il riquadro pieno, l'icona resta nera
            if (rv_sel && x - sx < CAP && y - 4 < CAP && !cap_px(x, y, sx, 4, rv_b, 1'b1)) begin
                rv_on = 1'b1;
                rv_col = BLACK;
            end
            if (rv_sel && y >= 4 + CAP + 2 && y < 4 + CAP + 5 &&
                x >= sx + CAP / 2 - (4 + CAP + 4 - y) && x <= sx + CAP / 2 + (4 + CAP + 4 - y)) begin
                rv_on = 1'b1;
                rv_col = ACCENT;
            end
        end else if (x - sx < CAP && y - 4 < CAP && ((x - sx) == 0 || (y - 4) == 0 || (x - sx) == CAP - 1 || (y - 4) == CAP - 1) &&
                     x[0] == y[0]) begin
            rv_on = 1'b1;                                      // posto vuoto: bordo a puntini
            rv_col = GRAY;
        end
        // pixel delle due racchette (rettangolo di pong_render più i segni del tipo): servono ai
        // segni qui sotto e alla scritta, che ci passa sotto
        for (k = 0; k < 2; k = k + 1) begin
            kx = $signed({2'b0, x}) - kl[k];
            kr = $signed({2'b0, y}) - kt[k];
            kcp[k] = (k == 0) ? sh_ka : sh_kb;
            kin[k] = kx >= 0 && kx < PW && kr >= 0 && kr < $signed({2'b0, kh[k]});
        end
        for (p = 0; p < 2; p = p + 1) begin
            if (rv_on && rv_p == p) begin
                on = 1'b1;
                col = rv_col;
            end
            // icona grigia del bonus armato accanto alla racchetta
            if (arm[p] != B_NONE && !(wv && wsd == p) &&
                icon_lit(arm[p][2:0], x - (p == 0 ? pcx[0] + PW / 2 + 3 : pcx[1] - PW / 2 - 12), y - (pcy[p] - 4))) begin
                on = 1'b1;
                col = GRAY;
            end
            // mossa armata: il suo segno giallo nello stesso posto (a destra specchiato), come
            // draw_special_icon di next_ui.rs
            if (marm[p] && !(wv && wsd == p) &&
                special_lit(mrise[p], (p == 0) ? x - (pcx[0] + PW / 2 + 3) : 8 - (x - (pcx[1] - PW / 2 - 12)),
                            y - (pcy[p] - 4))) begin
                on = 1'b1;
                col = bcold[p] ? GRAY : ACCENT;
            end
            // tipi di racchetta: segni sopra il rettangolo di pong_render (TWIST intera, perché è
            // inclinata), non durante la rotazione del SUPER e il salto del TELEPORT; con una mossa
            // di livello 2 armata la racchetta è gialla (anche senza tipo)
            if ((kd[p] != K_NONE || mmax[p]) && !spin[p] && !(wv && wsd == p)) begin
                kc = kcp[p];
                if (kc == KP_BODY && (kd[p] == K_TWIST || kd[p] == K_HAMMER || mmax[p])) begin
                    on = 1'b1;
                    col = mmax[p] ? (bcold[p] ? GRAY : ACCENT) : kgray[p] ? GRAY : WHITE;
                end
                if (kc == KP_MARK) begin
                    on = 1'b1;
                    col = ACCENT;
                end
                if (kc == KP_DETAIL) begin
                    on = 1'b1;
                    col = DETAIL;
                end
                if (kc == KP_CUT) begin
                    on = 1'b1;
                    col = BLACK;
                end
            end
            // BLASTER: munizioni dietro la racchetta, lontano dalla palla: dal basso, una riga sopra il
            // fondo, un rettangolino giallo di 3 righe (passo 4) per colpo nel caricatore, come
            // next_ui.rs; spariscono a ogni colpo e tornano tutti con la ricarica. I colpi in volo
            // sono due tratti gialli paralleli
            if (kd[p] == K_BLASTER) begin
                kx = $signed({2'b0, x}) - ((p == 0) ? kl[p] - 4 : kl[p] + PW + 2);
                ky = kt[p] + $signed({2'b0, kh[p]}) - 2 - sy;          // riga dal basso, da quella sopra il fondo
                if (kx >= 0 && kx < 2 && ky >= 0 && ky < $signed({7'd0, kammo[p], 2'b00}) && ky[1:0] != 2'd3) begin
                    on = 1'b1;
                    col = ACCENT;
                end
                for (k = 0; k < 4; k = k + 1)
                    if (kshot[4*p + k] && span(x, ksx[4*p + k], 3, 7) && (y == ksy[4*p + k] - 2 || y == ksy[4*p + k] + 2)) begin
                        on = 1'b1;
                        col = ACCENT;
                    end
            end
            // RUSH: tre immagini della racchetta tra casa e dove si trova mentre scatta in avanti, più
            // scure verso casa e che sfumano (kfade da 3 a 1); non sopra la racchetta
            if (kd[p] == K_RUSH && kfade[p] != 2'd0 && !spin[p] && !(wv && wsd == p) &&
                sy - kt[p] >= 0 && sy - kt[p] < $signed({2'b0, kh[p]}) &&
                !($signed({2'b0, x}) - kl[p] >= 0 && $signed({2'b0, x}) - kl[p] < PW))
                for (k = 0; k < 3; k = k + 1)
                    if ($signed({2'b0, x}) - kg[3*p + k] >= 0 && $signed({2'b0, x}) - kg[3*p + k] < PW &&
                        k + kfade[p] >= 3) begin
                        on = 1'b1;
                        col = (k + kfade[p] == 5) ? GHOST3 : (k + kfade[p] == 4) ? GHOST2 : GHOST1;
                    end
            // colpo di una mossa (draw_kick di next_ui.rs; il rinculo è già nella x di pong_top):
            // davanti alla faccia l'onda d'urto, due righe per STRAIGHT SHOT o un gallone a 45 gradi
            // per RISING STRIKE, che si allontana e sfuma; con la MAX due immagini gialle della
            // racchetta dietro di lei; nei primi frame la racchetta lampeggia (giallo, con la MAX
            // giallo e bianco a scatti)
            if (ckt[p] != 5'd0 && !spin[p] && !(wv && wsd == p)) begin
                ke = KICK_FRAMES - $signed({7'd0, ckt[p]});
                kf = (p == 0) ? $signed({2'b0, x}) - (kl[p] + PW) : (kl[p] - 1) - $signed({2'b0, x});
                kb = (p == 0) ? kl[p] - 1 - $signed({2'b0, x}) : $signed({2'b0, x}) - (kl[p] + PW);
                kv = $signed({2'b0, y}) - $signed({2'b0, pcy[p]});
                if (ckr[p]) begin
                    ko = 4 + ke + (ke >>> 2) + (ke >>> 4) - kf;          // dietro la punta
                    if (ko >= 0 && ko < 6 + ((ke * 5) >>> 4) && (kv == ko || kv == -ko)) begin
                        on = 1'b1;
                        col = (ckt[p] > 5'd12) ? ACCENT : (ckt[p] > 5'd6) ? KICK2 : KICK1;
                    end
                end else begin
                    ko = kf - (2 + ke + (ke >>> 1) + (ke >>> 3));        // dall'inizio delle righe
                    if (ko >= 0 && ko < 2 + (($signed({7'd0, ckt[p]}) * 11) >>> 4) &&
                        (kv == ($signed({2'b0, kh[p]}) >>> 2) || kv == -($signed({2'b0, kh[p]}) >>> 2))) begin
                        on = 1'b1;
                        col = (ckt[p] > 5'd12) ? ACCENT : (ckt[p] > 5'd6) ? KICK2 : KICK1;
                    end
                end
                if (ckm[p] && sy - kt[p] >= 0 && sy - kt[p] < $signed({2'b0, kh[p]})) begin
                    ko = kb - (ke >>> 2);                                // prima immagine, a 4 pixel
                    if (ko >= 0 && ko < PW) begin
                        on = 1'b1;
                        col = (ckt[p] > 5'd9) ? KICK_IMG1 : KICK_IMG2;
                    end
                    ko = kb - 4 - (ke >>> 1);                            // seconda, a 8
                    if (ko >= 0 && ko < PW) begin
                        on = 1'b1;
                        col = (ckt[p] > 5'd9) ? KICK_IMG2 : GHOST1;
                    end
                end
                if ((ckm[p] ? ke < 8 : ke < 4) && $signed({2'b0, x}) - kl[p] >= 0 && $signed({2'b0, x}) - kl[p] < PW &&
                    sy - kt[p] >= 0 && sy - kt[p] < $signed({2'b0, kh[p]})) begin
                    on = 1'b1;
                    col = (ckm[p] && ke[1]) ? WHITE : ACCENT;
                end
            end
            // GUARDIAN: muro tratteggiato a settori sotto la banda delle riserve, solo i settori in
            // piedi; quello che rimanda la palla lampeggia, poi sparisce
            if (kd[p] == K_GUARDIAN && x - ((p == 0) ? BARRIER_X - 1 : W - BARRIER_X - 1) < 2 && wall_row &&
                (kwall[p][wall_sec] || (kflash[p] && khit[p][wall_sec]))) begin
                on = 1'b1;
                col = (kflash[p] && khit[p][wall_sec]) ? (tick[3] ? ACCENT : DIM) : ACCENT;
            end
            // STEER: chi guida ha la racchetta ferma, grigia, con il volante giallo accanto
            if (steer_on && steer_side == p) begin
                if (span(x, pcx[p], PW / 2, PW) && span(y, pcy[p], kh[p] / 2, kh[p])) begin
                    on = 1'b1;
                    col = GRAY;
                end
                if (icon_lit(B_STEER[2:0], x - (p == 0 ? pcx[0] + PW / 2 + 3 : pcx[1] - PW / 2 - 12), y - (pcy[p] - 4))) begin
                    on = 1'b1;
                    col = ACCENT;
                end
            end
            // racchetta che ruota con il SUPER armato (pong_render non la disegna)
            if (spin[p]) begin
                sdx = $signed({1'b0, x}) - $signed({1'b0, pcx[p]});
                sdy = $signed({1'b0, y}) - $signed({1'b0, pcy[p]});
                if (sdx > -24 && sdx < 24 && sdy > -24 && sdy < 24) begin
                    u8 = sdx * sin_q8(angle + 6'd16) + sdy * sin_q8(angle);
                    v8 = sdy * sin_q8(angle + 6'd16) - sdx * sin_q8(angle);
                    if (u8 > -PW * 128 && u8 < PW * 128 && v8 > -($signed({2'b0, kh[p]}) <<< 7) && v8 < ($signed({2'b0, kh[p]}) <<< 7)) begin
                        on = 1'b1;
                        col = bcold[p] ? GRAY : WHITE;
                    end
                end
            end
            // BULLET: bordo giallo attorno alla racchetta di chi l'ha attivato, a 3 pixel, che lampeggia
            // piano (128 tick acceso, 128 spento) mentre è armato in attesa della palla; nel bullet time
            // no, la racchetta si distingue già perché resta bianca e nitida (come next_ui.rs)
            if (barm && !bon && !tick[7] && bsd == p &&
                $signed({2'b0, x}) - (kl[p] - 4) < PW + 8 && sy - (kt[p] - 4) < $signed({2'b0, kh[p]}) + 8 &&
                $signed({2'b0, x}) - (kl[p] - 4) >= 0 && sy - (kt[p] - 4) >= 0 &&
                ($signed({2'b0, x}) == kl[p] - 4 || $signed({2'b0, x}) == kl[p] + PW + 3 ||
                 sy == kt[p] - 4 || sy == kt[p] + $signed({2'b0, kh[p]}) + 3)) begin
                on = 1'b1;
                col = ACCENT;
            end
        end

        // mosse speciali: barra di ciascun giocatore (grigia sotto il costo, bianca sopra, gialla quando la
        // mossa si può fare, lampeggiante con la mossa armata), racchetta con la mossa armata (faccia
        // gialla che lampeggia) e quadrato giallo dove RISING STRIKE s'impenna
        if (msup) begin
            if (bq == 2'd1) begin
                on = 1'b1;
                col = GRAY;
            end
            if (bq == 2'd2) begin
                on = 1'b1;
                col = marm[hb_p] ? (tick[3] ? ACCENT : WHITE) : mok[hb_p] ? ACCENT : (mtr[hb_p] >= COST) ? WHITE : GRAY;
            end
            if (bq == 2'd3) begin
                on = 1'b1;
                col = WHITE;
            end
            for (p = 0; p < 2; p = p + 1) begin
                if (marm[p] && tick[3] && $signed({2'b0, x}) == ((p == 0) ? kl[0] + PW : kl[1] - 1) &&
                    sy >= kt[p] && sy < kt[p] + $signed({2'b0, kh[p]})) begin
                    on = 1'b1;
                    col = ACCENT;
                end
            end
            if (rbon && span(x, rbx, 7, 15) && span(y, rby, 7, 15) &&
                (x == rbx - 7 || x == rbx + 7 || y == rby - 7 || y == rby + 7)) begin
                on = 1'b1;
                col = ACCENT;
            end
        end

        // STEER: segni sui bordi alto e basso dove finisce la guida (3/4 del campo)
        if (steer_on && (y < 6 || y >= H - 6) &&
            (steer_side ? x - (W / 4 - 1) < 2 : x - (W - W / 4 - 1) < 2)) begin
            on = 1'b1;
            col = ACCENT;
        end

        // salto del TELEPORT (pong_render non disegna la racchetta): le due linee dei portali
        // e i tratti di racchetta che entrano ed escono
        if (wv && ((en_on && w_line && (sy == wen_edge - 1 || sy == wen_edge)) ||
                   (ex_on && w_line && (sy == wex_edge - 1 || sy == wex_edge)))) begin
            on = 1'b1;
            col = ACCENT;
        end
        if (wv && ((en_on && w_col && sy >= wen_lo && sy < wen_hi) || (ex_on && w_col && sy >= wex_lo && sy < wex_hi))) begin
            on = 1'b1;
            col = bcold[wsd] ? GRAY : WHITE;
        end

        // capsule in volo: il SUPER lampeggia in negativo; i bonus rari in giallo, le altre grigie
        // nel bullet time
        for (k = 0; k < 4; k = k + 1)
            if (cv[k] && cap_px(x, y, csx[k], csy[k], {1'b0, cbon[k]}, cbon[k] == B_SUPER[2:0] && cap_blink)) begin
                on = 1'b1;
                col = (cbon[k] == B_SUPER[2:0] || cbon[k] == B_BULLET[2:0]) ? ACCENT : bon ? GRAY : WHITE;
            end
            else if (cv[k] && cbon[k] == B_SUPER[2:0] && cap_blink && span(x, csx[k], 0, CAP) && span(y, csy[k], 0, CAP)) begin
                on = 1'b1;
                col = BLACK;
            end

        // scritta del bonus attivato o della mossa (LK_*), su un riquadro nero in basso, sotto alla
        // palla e alla sua scia: la coprono le scie, le righe dello STRAIGHT, la cometa e l'alone qui
        // sotto, e la palla di pong_render in pong_top (`label`, acceso anche sotto la scia: lì la
        // palla non c'è)
        lbox = x >= label_x - 4 && x < label_x + label_w + 4 && y >= LABEL_MID - 10 && y < LABEL_MID + 10;
        ltext = (label_player ? nx_p2_lit(ldx, y - LABEL_TOP) : nx_p1_lit(ldx, y - LABEL_TOP)) ||
                (label_mx && nx_max_lit(ldx - (NX_P1_W + 3), y - LABEL_TOP)) ||
                (label_move != 2'd0 ? mv_on : sh_name) ||
                nx_bang_lit(ldx - (NX_P1_W + 3 + label_name_w + 1), y - LABEL_TOP);
        // colonne con una lettera (solo per le mosse): sotto di loro i trattini, al colpo i blocchi
        lcol = x - label_x < label_w &&
               ((label_player ? nx_p2_col(ldx) : nx_p1_col(ldx)) ||
                (label_mx && nx_max_col(ldx - (NX_P1_W + 3))) ||
                (label_move == 2'd2 ? nx_move1_col(ldx - (NX_P1_W + 3) - (label_mx ? NX_MAX_W + 3 : 0))
                                    : nx_move0_col(ldx - (NX_P1_W + 3) - (label_mx ? NX_MAX_W + 3 : 0))) ||
                nx_bang_col(ldx - (NX_P1_W + 3 + label_name_w + 1)));
        ldash = lcol && (y == LABEL_TOP + 9 || (label_mx && y == LABEL_TOP + 11));
        // distanza dal lato del giocatore che ha fatto la mossa
        lpos = label_player ? label_x + label_w - 1 - x : x - label_x;
        // le racchette stanno sopra alla scritta: sui pixel della racchetta (il rettangolo di
        // pong_render e quelli del suo tipo, anche la HAMMER più spessa) la scritta non si disegna e
        // restano pong_render e i segni qui sopra; accanto la scritta resta intera
        pad_box = kcp[0] != KP_NONE || kin[0] || kcp[1] != KP_NONE || kin[1];
        if (pad_box) ;
        else if (label_on && label_kind == LK_ARMED) begin
            // solo i trattini: l'ultimo disegnato bianco, poi grigi che si accendono mentre la palla arriva
            if (ldash && lpos < dash_rev) begin
                on = 1'b1;
                lb = 1'b1;
                col = (lpos + 6 >= dash_rev && dash_rev < label_w) ? WHITE : (lpos < dash_lit) ? ACCENT : DIM;
            end
        end else if (label_on && label_kind == LK_HIT) begin
            // colpo: blocchi bianchi, poi la scritta e i trattini accesi; nell'ultima parte lampeggia
            if (lbox && !(label_age >= 7'd44 && label_age[2])) begin
                on = 1'b1;
                lb = 1'b1;
                col = BLACK;
                if (label_age < 7'd2 ? (lcol && y >= LABEL_TOP + 1 && y < LABEL_TOP + 8) : ltext)
                    col = (label_age < 7'd4) ? WHITE : ACCENT;
                if (ldash && label_age < 7'd24)
                    col = (label_age < 7'd4) ? WHITE : ACCENT;
            end
        end else if (label_on) begin
            // bonus: riga, immagine che si apre e si chiude, puntino (vedi LK_BONUS)
            if (crt_dot || crt_line) begin
                if ((y == LABEL_MID - 1 || y == LABEL_MID) &&
                    x - (label_x + (label_w >> 1) - (crt_dot ? 10'd1 : crt_lw)) < (crt_dot ? 10'd2 : {crt_lw, 1'b0})) begin
                    on = 1'b1;
                    lb = 1'b1;
                    col = WHITE;
                end
            end else if (lbox && y - (LABEL_MID - crt_hh) < {crt_hh, 1'b0}) begin
                on = 1'b1;
                lb = 1'b1;
                col = (crt_edge && (y == LABEL_MID - crt_hh || y == LABEL_MID + crt_hh - 1)) ? WHITE :
                      ltext ? ACCENT : BLACK;
            end
        end

        // scie: lunga e piena per la cometa; per gli altri effetti una coda larga quanto la palla che
        // sfuma dal grigio al nero (dalla più vecchia, così le nuove la coprono), fuori dalla palla:
        // questo livello sta sopra a pong_render, che la disegna
        for (k = 1; k < HIST; k = k + 1)
            if (hv[k] && comet && !ghost_on && span(x, hx[k], (bside - k / 2) / 2, bside - k / 2) && span(y, hy[k], (bside - k / 2) / 2, bside - k / 2)) begin
                on = 1'b1;
                col = (k < 4) ? ACCENT : GRAY;
            end
        if (!comet && !ghost_on && !(x - (bx - bside / 2) < bside && y - (by - bside / 2) < bside)) begin
            // BULLET: immagini della palla (contorno grigio) dove è passata, oltre la coda; solo fuori
            // dalle rampe, come su PC
            for (k = GHOSTS - 1; k >= 0; k = k - 1)
                if (bon && !bramp && gv[k] && span(x, gx[k], bside / 2, bside) && span(y, gy[k], bside / 2, bside) &&
                    (x == gx[k] - bside / 2 || x == gx[k] - bside / 2 + bside - 1 ||
                     y == gy[k] - bside / 2 || y == gy[k] - bside / 2 + bside - 1)) begin
                    on = 1'b1;
                    col = GRAY;
                end
            // la coda lunga del bullet time: le posizioni oltre TRAIL, senza i punti a metà
            for (k = TRAIL_LONG; k > TRAIL; k = k - 1)
                if (bon && hv[k] && span(x, hx[k], bside / 2, bside) && span(y, hy[k], bside / 2, bside)) begin
                    on = 1'b1;
                    col = trail_pick(mspf != 2'd0, 1'b1, 2 * k);
                end
            for (k = TRAIL; k >= 1; k = k - 1)
                if (hv[k]) begin
                    if (span(x, hx[k], bside / 2, bside) && span(y, hy[k], bside / 2, bside)) begin
                        on = 1'b1;
                        col = trail_pick(mspf != 2'd0, bon, 2 * k);
                    end
                    if (span(x, mx[k], bside / 2, bside) && span(y, my[k], bside / 2, bside)) begin
                        on = 1'b1;
                        col = trail_pick(mspf != 2'd0, bon, 2 * k - 1);
                    end
                end
        end
        // STRAIGHT SHOT in volo: due righe di velocità gialle dietro la palla, sui suoi bordi alto e basso
        if (mspf == 2'd1 && !bhide && (y == by - bside / 2 || y == by + bside / 2 - 1) &&
            (!bleft ? (bx - bside / 2 - 2) - x < 26 : x - (bx + bside / 2 + 2) < 26)) begin
            on = 1'b1;
            col = ACCENT;
        end
        // palla cometa (pong_render non la disegna), gialla come ogni palla del SUPER
        if (comet && !bhide && span(x, bx, bside / 2, bside) && span(y, by, bside / 2, bside)) begin
            on = 1'b1;
            col = ACCENT;
        end
        // alone di SLOW
        if (ring_on && span(x, bx, bside * 3 / 2, bside * 3) && span(y, by, bside * 3 / 2, bside * 3) &&
            (x == bx - bside * 3 / 2 || x == bx - bside * 3 / 2 + bside * 3 - 1 ||
             y == by - bside * 3 / 2 || y == by - bside * 3 / 2 + bside * 3 - 1)) begin
            on = 1'b1;
            col = GRAY;
        end
    end
end

// alone delle capsule nel bullet time, come quello di pong_render: scarto in x + scarto in y dal
// quadrato della capsula, con dx = x - sx a 10 bit (sotto zero torna a 1023): solo confronti con
// costanti
function [2:0] cap_gap(input [9:0] d);
    cap_gap = (d < CAP) ? 3'd0 : (d < CAP + 3) ? d[2:0] - CAP[2:0] + 3'd1 :
              (d >= 10'd1021) ? {1'b0, ~d[1:0]} + 3'd1 : 3'd4;
endfunction
reg [3:0] cg, cgm;
integer   hk;
always @(*) begin
    cgm = 4'd15;
    for (hk = 0; hk < 4; hk = hk + 1) begin
        cg = {1'b0, cap_gap(x - csx[hk])} + {1'b0, cap_gap(y - csy[hk])};
        if (cv[hk] && cg != 4'd0 && cg < cgm) cgm = cg;
    end
end

always @(posedge clk) begin
    rgb <= pal(col);
    opaque <= on;
    label <= lb;
    halo <= (bon && bblur != 2'd0 && cgm <= {2'd0, bblur}) ? cgm[1:0] : 2'd0;
end

endmodule
