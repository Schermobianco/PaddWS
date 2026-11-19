// Disegno della modalità NEXT in partita: le aggiunte sopra il campo di pong_render (riserve,
// capsule, icona del bonus armato, racchetta che ruota con il SUPER, salto del TELEPORT, palla guidata
// con STEER, palla cometa e scie, alone di SLOW, scritta del bonus attivato, segni dei tipi di
// racchetta, colpi e munizioni del BLASTER, immagini dello scatto del RUSH, muro a settori del GUARDIAN) e, con le mosse speciali, la barra di ciascun giocatore nella banda in alto
// sotto la riserva, la racchetta con la mossa armata (segno accanto, gialla al livello 2), il tiro
// della mossa in volo, il punto dove RISING STRIKE s'impenna e il nome della mossa ("MAX" al livello
// 2). Le schermate (scelta di bonus e racchetta, HOW TO PLAY, presentazione, sfilata del finale) sono
// dello schermo a oggetti (ui_render, rust/mister-ui).
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
    // OMEGA: lato della sua racchetta (rossa, viola con l'easter egg), lampo bianco alla trasformazione
    input  wire [1:0]  omega_pad,
    input  wire        omega_flash,
    input  wire        omega_egg,
    input  wire [31:0] kind0,
    input  wire [31:0] kind1,
    input  wire [255:0] shots_x,           // colpi del BLASTER, 4 per giocatore (prima il sinistro)
    input  wire [255:0] shots_y,
    input  wire signed [31:0] pad0_motion,
    input  wire signed [31:0] pad1_motion,
    input  wire [3:0]  rush_fade,           // RUSH: intensità delle immagini dello scatto (2 bit per lato, 0 = niente)
    // racchette dei personaggi (contatori di pong_top, frame che restano, 5 o 6 bit per lato): rottura
    // dell'ultimo settore del muro del GUARDIAN, sparo del BLASTER, colpo della racchetta (scintille
    // dell'HAMMER, onda del TWIST, corso del GUARDIAN che rientra) con la riga del colpo dalla cima;
    // conto alla rovescia (il GUARDIAN costruisce il muro) e frame dall'inizio
    input  wire [11:0] barrier_age,
    input  wire [9:0]  fire_age,
    input  wire [9:0]  hit_age,
    input  wire [11:0] hit_rows,
    input  wire        building,
    input  wire [7:0]  build_f,
    input  wire [4:0]  wall0,               // GUARDIAN: settori del muro in piedi (5, bit 0 in alto)
    input  wire [4:0]  wall1,
    input  wire [4:0]  wall_hit0,           // GUARDIAN: settore dell'ultima rottura (con barrier_age)
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
`include "pong_paddles.vh"

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
// immagini gialle a 18, 36 e 54% (come su PC, alpha 0,18 * k sul nero): le immagini della MAX
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
// OMEGA: il rosso del gioco e, con l'easter egg RED (giallo e rosso scambiati), il viola
localparam [6:0] OMEGA_RED = 7'd81, OMEGA_PURPLE = 7'd82;
localparam [23:0] RGB_OMEGA_RED = 24'hE62828, RGB_OMEGA_PURPLE = 24'hA040E0;
// racchette dei personaggi (pong_paddles.vh): ombra portata, corpo in ombra (bianco, grigio, giallo,
// rosso e viola di OMEGA), grigi, i tre toni di ogni personaggio (P_MARK + 3 * tipo), le immagini
// dello scatto del RUSH e il muro del GUARDIAN in campo
localparam [6:0] P_SHADOW = 7'd83, P_WHITE_SH = 7'd84, P_GRAY_SH = 7'd85, P_ACCENT_SH = 7'd86, P_RED_SH = 7'd87,
                 P_PURPLE_SH = 7'd88, P_GRAY = 7'd89, P_GRAY_LIGHT = 7'd90, P_DARK = 7'd91, P_DARK_DEEP = 7'd92,
                 P_MARK = 7'd93, P_RGHOST1 = 7'd114, P_RGHOST2 = 7'd115, P_RGHOST3 = 7'd116,
                 P_WALL = 7'd117, P_WALL_LIGHT = 7'd118, P_WALL1 = 7'd119, P_WALL2 = 7'd120;
// TWIST: inclinazione a gradini (fino a circa 20 gradi) dalla velocità della racchetta
localparam signed [31:0] TILT1 = P_PAD_MAX_SPEED / 6, TILT2 = P_PAD_MAX_SPEED / 2,
                         TILT3 = P_PAD_MAX_SPEED * 5 / 6;
localparam integer BARRIER_X = P_GUARDIAN_BARRIER_X >>> 16;
// GUARDIAN: muro a 5 settori da WALL_TOP (sotto la banda delle riserve) al fondo, confini WALL_B1..4,
// in righe dello schermo (i parametri sono y del core, verso l'alto, pixel interi). In campo non si
// vede: dove la palla lo colpisce, il blocco del settore lampeggia e si sbriciola (come next_ui.rs)
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
// presentazione di CHALLENGE: riga del centro della racchetta; munizioni del BLASTER (caricatore
// pieno, 4 righe per colpo come in partita)
localparam integer INTRO_Y = 82, AMMO_ROWS = 4 * P_BLASTER_SHOTS;
// schermate di scelta (Press Start 2P, tutto a scala 1): titolo, secondi rimasti (due celle di 8
// pixel al centro), scostamento delle scritte nelle righe delle racchette (20 pixel) e dei bonus
// (18), frase del tipo e READY! in basso
localparam integer PICK_TITLE_Y = 8, SECS_X1 = W / 2 - 8, SECS_X2 = W / 2;
localparam integer KIND_TEXT_DY = 5, PICK_TEXT_DY = 5, TAG_Y = 218, READY_Y = 230;

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
            OMEGA_RED: pal = RGB_OMEGA_RED;
            OMEGA_PURPLE: pal = RGB_OMEGA_PURPLE;
            P_SHADOW:     pal = PD_SHADOW;
            P_WHITE_SH:   pal = PD_WHITE_SH;
            P_GRAY_SH:    pal = PD_GRAY_SH;
            P_ACCENT_SH:  pal = PD_ACCENT_SH;
            P_RED_SH:     pal = PD_OMEGA_RED_SH;
            P_PURPLE_SH:  pal = PD_OMEGA_PURPLE_SH;
            P_GRAY:       pal = PD_GRAY;
            P_GRAY_LIGHT: pal = PD_GRAY_LIGHT;
            P_DARK:       pal = PD_DARK;
            P_DARK_DEEP:  pal = PD_DARK_DEEP;
            P_MARK:       pal = PD_MARK0;
            P_MARK + 7'd1:  pal = PD_MARK_DARK0;
            P_MARK + 7'd2:  pal = PD_MARK_LIGHT0;
            P_MARK + 7'd3:  pal = PD_MARK1;
            P_MARK + 7'd4:  pal = PD_MARK_DARK1;
            P_MARK + 7'd5:  pal = PD_MARK_LIGHT1;
            P_MARK + 7'd6:  pal = PD_MARK2;
            P_MARK + 7'd7:  pal = PD_MARK_DARK2;
            P_MARK + 7'd8:  pal = PD_MARK_LIGHT2;
            P_MARK + 7'd9:  pal = PD_MARK3;
            P_MARK + 7'd10: pal = PD_MARK_DARK3;
            P_MARK + 7'd11: pal = PD_MARK_LIGHT3;
            P_MARK + 7'd12: pal = PD_MARK4;
            P_MARK + 7'd13: pal = PD_MARK_DARK4;
            P_MARK + 7'd14: pal = PD_MARK_LIGHT4;
            P_MARK + 7'd15: pal = PD_MARK5;
            P_MARK + 7'd16: pal = PD_MARK_DARK5;
            P_MARK + 7'd17: pal = PD_MARK_LIGHT5;
            P_MARK + 7'd18: pal = PD_MARK6;
            P_MARK + 7'd19: pal = PD_MARK_DARK6;
            P_MARK + 7'd20: pal = PD_MARK_LIGHT6;
            P_RGHOST1:    pal = PD_RUSH_GHOST1;
            P_RGHOST2:    pal = PD_RUSH_GHOST2;
            P_RGHOST3:    pal = PD_RUSH_GHOST3;
            P_WALL:       pal = PD_WALL;
            P_WALL_LIGHT: pal = PD_WALL_LIGHT;
            P_WALL1:      pal = PD_WALL1;
            P_WALL2:      pal = PD_WALL2;
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

// larghezza del nome nella scritta: bonus o mossa speciale (con "MAX " davanti al livello 2). Le
// parole sono nella griglia di 8 pixel del font: dopo una parola (larga 8 n - 1) lo spazio è 9 pixel
wire       label_mx = label_move != 2'd0 && label_max;
wire [7:0] label_name_w = (label_move != 2'd0) ? {1'b0, move_w({2'd0, label_move == 2'd2})} + (label_mx ? NX_MAX_W + 9 : 0)
                                               : {2'b0, name_w(label_bonus)};
// larghezza di tutta la scritta ("P1 " + nome + "!") in pixel del font, a scala 1
wire [7:0] label_w_n = NX_P1_W + 9 + label_name_w + 1 + NX_BANG_W;

// Tipi della scritta (`label_kind`), come rust/game/src/next_ui.rs:
// - LK_BONUS, "P1 SMASH!": si accende e si spegne come un vecchio televisore. In 72 frame: una riga
//   bianca che si allarga (4 frame), l'immagine che si apre in altezza con i bordi bianchi (4), ferma,
//   che si richiude (3), la riga che si stringe (4), il puntino;
// la scritta è a scala 1 (righe del font 40-47, lettere 40-46), su un riquadro di 20 righe, sotto i
// punteggi come nel gioco Rust (in fondo al campo ci sono i punti della scalata);
// - LK_ARMED, mossa armata: solo i trattini sotto le lettere (due righe con la MAX), che si
//   disegnano dal lato del giocatore, una lettera (8 pixel) ogni 2 frame, e si accendono di giallo mentre la
//   palla arriva verso di lui;
// - LK_HIT, colpo della mossa (60 frame): per 2 frame blocchi bianchi al posto delle lettere, poi la
//   scritta, bianca fino al frame 4; i trattini accesi fino al 24; dal 44 lampeggia.
localparam [1:0] LK_BONUS = 2'd0, LK_ARMED = 2'd1, LK_HIT = 2'd2;
localparam integer LABEL_TOP = 40;      // prima riga del font della scritta
localparam integer LABEL_MID = 46;      // riga centrale del riquadro (36-55)
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
reg [7:0]  label_w;
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
reg [4:0]  khit [0:1];                // GUARDIAN: settore dell'ultima rottura (con kba)
reg        kgray [0:1];
// racchette dei personaggi: frame che restano (rottura del muro, sparo, colpo), riga del colpo e
// corso del GUARDIAN che ci sta; posa (8 al secondo, dal tick) e gettone dell'ARCADE (pose 0-23);
// conto alla rovescia con i corsi del muro che cadono (visibile, spostamento)
reg [5:0]  kba [0:1];
reg [4:0]  kfa [0:1];
reg [4:0]  kha [0:1];
reg [5:0]  khr [0:1];
reg [2:0]  krc [0:1];
reg [7:0]  kpose = 8'd0;
reg [4:0]  coin_s = 5'd0;
reg        kbuild = 1'b0;
reg        gbv [0:4];
reg signed [11:0] gbd [0:4];
// TITAN: polvere del passo, 8 per lato (4 per estremità): colonna, riga, grande (2x2 grigio), c'è
reg signed [11:0] dpx [0:15];
reg signed [11:0] dpy [0:15];
reg        dpb [0:15];
reg        dpv [0:15];
// RUSH e BLASTER: lembi, riga di ogni segmento (10 per lato: 5 della striscia alta, 5 della bassa) e
// segmenti per striscia (2 per lato), calcolati da un piccolo sequenziatore dopo la fotografia
reg signed [11:0] tdy [0:19];
reg [2:0]  ktn [0:3];
reg        kdash [0:1];
reg signed [11:0] tbend [0:1];        // piega dei lembi (1/256 di pixel per segmento)
reg [9:0]  tamp [0:1];                // ampiezza dello sventolio (1/256)
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
            kba[i] <= i ? barrier_age[11:6] : barrier_age[5:0];
            kfa[i] <= i ? fire_age[9:5] : fire_age[4:0];
            kha[i] <= i ? hit_age[9:5] : hit_age[4:0];
            khr[i] <= i ? hit_rows[11:6] : hit_rows[5:0];
            krc[i] <= hit_course(i ? hit_rows[11:6] : hit_rows[5:0]);
            // lembi: piega (verso opposto alla velocità, 0,6 px per segmento per px/frame, fino a
            // 1,2) e sventolio (pieno da ferma); nello scatto del RUSH 2 segmenti in più, dritti
            tbend[i] <= tail_bend(i ? pad1_motion : pad0_motion);
            tamp[i] <= tail_amp(tail_bend(i ? pad1_motion : pad0_motion));
            kdash[i] <= (i ? rush_fade[3:2] : rush_fade[1:0]) != 2'd0;
            ktn[2 * i] <= ((i ? rush_fade[3:2] : rush_fade[1:0]) != 2'd0) ? 3'd5 : 3'd3;
            ktn[2 * i + 1] <= ((i ? rush_fade[3:2] : rush_fade[1:0]) != 2'd0) ? 3'd4 : 3'd2;
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
        // posa a 8 al secondo (il tick va a 240 Hz: 32 tick sono 7,5 pose al secondo) e gettone
        kpose <= tick[12:5];
        if (tick[5] != kpose[0]) coin_s <= (coin_s == 5'd23) ? 5'd0 : coin_s + 5'd1;
        // GUARDIAN: nel conto alla rovescia i corsi cadono dal basso, uno ogni 18 frame
        kbuild <= nxt && building;
        for (i = 0; i < 5; i = i + 1) begin
            gbv[i] <= build_course_v(build_f, 8'd24 + 8'd18 * (8'd4 - i));
            gbd[i] <= build_course_dy(build_f, 8'd24 + 8'd18 * (8'd4 - i));
        end
        for (i = 0; i < 16; i = i + 1) begin
            dpx[i] <= dust_x[i];
            dpy[i] <= dust_y[i];
            dpb[i] <= dust_b[i];
            dpv[i] <= dust_v[i];
        end
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
        // scritta del bonus o della mossa: "P1 " + nome + "!" a scala 1, centrata in basso
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
            crt_lw <= quarters({1'b0, label_w_n[7:1]} + 8'd4, label_age[2:0] + 3'd1);
        end else if (label_age < 7'd8) begin
            crt_hh <= crt_open(label_age[1:0]);                                   // 3, 5, 8, 10
            crt_edge <= 1'b1;
        end else if (label_age >= 7'd64 && label_age < 7'd67) begin
            crt_hh <= crt_open(2'd2 - label_age[1:0]);                            // 8, 5, 3
            crt_edge <= 1'b1;
        end else if (label_age >= 7'd67 && label_age < 7'd71) begin
            crt_line <= 1'b1;
            crt_lw <= quarters({1'b0, label_w_n[7:1]} + 8'd4, 3'd7 - label_age[2:0]);  // 4/4 .. 1/4
        end else if (label_age >= 7'd71) begin
            crt_dot <= 1'b1;
        end
        // trattini della mossa armata: una lettera (8 pixel) ogni 2 frame, e quelli accesi
        dash_rev <= {1'b0, label_age, 2'b0};
        dash_lit <= arm_lit[15:8];
    end
end


// GUARDIAN: corso della riga `row` dalla cima (floor(row * 5 / h)), quello che rientra al colpo
function [2:0] hit_course(input [5:0] row);
    hit_course = ({row, 2'b0} + row < HT_G) ? 3'd0 : ({row, 2'b0} + row < 2 * HT_G) ? 3'd1 :
                 ({row, 2'b0} + row < 3 * HT_G) ? 3'd2 : ({row, 2'b0} + row < 4 * HT_G) ? 3'd3 : 3'd4;
endfunction
// GUARDIAN: corso che cade nel conto alla rovescia, `f` frame dall'inizio, che si posa al frame `land`:
// visibile da 15 frame prima, poi rimbalza di 1 pixel per 6 frame
function build_course_v(input [7:0] f, input [7:0] land);
    build_course_v = f + 8'd15 >= land;
endfunction
function signed [11:0] build_course_dy(input [7:0] f, input [7:0] land);
    reg [7:0] d;
    begin
        d = f + 8'd15 - land;
        // pd_build_dy è con segno: nel condizionale con segno si estende da sé
        build_course_dy = (f + 8'd15 < land) ? 12'sd0 : (f < land) ? pd_build_dy(d[3:0]) :
                          (f < land + 8'd6) ? -12'sd1 : 12'sd0;
    end
endfunction
// lembi: piega per segmento in 1/256 di pixel dalla velocità (motion: px/tick in Q16.16, verso l'alto):
// -0,6 * vy con vy = -4 * motion px/frame, fino a +-1,2
function signed [11:0] tail_bend(input signed [31:0] m);
    reg signed [47:0] b;
    begin
        b = (m * 48'sd615) >>> 16;
        tail_bend = (b > 48'sd307) ? 12'sd307 : (b < -48'sd307) ? -12'sd307 : b[11:0];
    end
endfunction
// ampiezza dello sventolio in 1/256: (0,3 + 0,7 * calma) * 1,4, con calma = 1 - min(|piega|, 1)
function [9:0] tail_amp(input signed [11:0] b);
    reg [8:0] calm;
    reg [17:0] t;
    begin
        calm = (b >= 256 || b <= -256) ? 9'd0 : 9'd256 - ((b < 0) ? -b : b);
        t = (18'd77 + ((calm * 18'd179) >> 8)) * 18'd359;
        tail_amp = t[17:8];
    end
endfunction

// TITAN: polvere del passo, dalla posa e dal movimento (in movimento 4 per estremità, ferma 2): la
// particella k di un'estremità è a p = frac(posa * 0,1125 + k / m (+ 0,37 in alto)), si allontana
// dietro (fino a 9 pixel) e in fuori (fino a 4); grigia 2x2 fino a 0,45, poi un puntino scuro;
// sparisce oltre 0,85. Indice: 8 * lato + 4 * estremità (0 in basso, 1 in alto) + k
reg signed [11:0] dust_x [0:15];
reg signed [11:0] dust_y [0:15];
reg        dust_b [0:15];
reg        dust_v [0:15];
reg [7:0]  dust_p;
reg [11:0] dust_o;
reg        dust_m;
integer    dk;
always @(*) begin
    for (dk = 0; dk < 16; dk = dk + 1) begin
        dust_m = ((dk >= 8) ? pad1_motion : pad0_motion) > 32'sd8192 ||
                 ((dk >= 8) ? pad1_motion : pad0_motion) < -32'sd8192;
        dust_p = tick[12:5] * 8'd29 + (dust_m ? (dk % 4) * 64 : (dk % 4) * 128) + ((dk % 8 >= 4) ? 8'd95 : 8'd0);
        dust_o = ((dust_p + 12'd32) >> 6) + ((dk % 2 == 1) ? 12'd2 : 12'd0);
        dust_v[dk] = (dust_m || dk % 4 < 2) && dust_p <= 8'd217;
        dust_b[dk] = dust_p < 8'd115;
        dust_x[dk] = -12'sd8 - $signed({4'd0, (({4'd0, dust_p} * 12'd9 + 12'd128) >> 8)});
        dust_y[dk] = (dk % 8 >= 4) ? 12'sd2 - $signed(dust_o) : HT_T - 3 + $signed(dust_o);
    end
end

// lembi: riga di ogni segmento, uno per ciclo dopo la fotografia (20 in tutto: lato, striscia,
// segmento j da 1 a 5). Come tails di paddle_ui.rs: dal nodo (riga 3), la striscia alta sale di 0,5
// pixel per segmento, la bassa parte 2 righe sotto e scende di 0,6 (un quarto nello scatto), più la
// piega e lo sventolio sin(posa * 5/8 + 1,3 j + 2 striscia) * ampiezza * j / n
reg [4:0]  tq = 5'd31;
reg        tp, ti;
reg [2:0]  tj, tn;
reg signed [15:0] tbase, twave, tsum;
reg signed [23:0] tmul;
reg [8:0]  tjn;
reg [5:0]  tph;
always @(*) begin
    tp = tq >= 5'd10;
    ti = (tq >= 5'd10 ? tq - 5'd10 : tq) >= 5'd5;
    tj = (tq >= 5'd10 ? tq - 5'd10 : tq) - (ti ? 5'd5 : 5'd0) + 3'd1;
    tn = ktn[{tp, ti}];
    tbase = ti ? (16'sd1280 + (kdash[tp] ? 16'sd38 : 16'sd154) * $signed({13'd0, tj}))
               : (16'sd768 - (kdash[tp] ? 16'sd32 : 16'sd128) * $signed({13'd0, tj}));
    // j / n in 1/256 (n = 3 o 2: nello scatto niente sventolio)
    tjn = (tn == 3'd3) ? ((tj == 3'd1) ? 9'd85 : (tj == 3'd2) ? 9'd171 : 9'd256) : ((tj == 3'd1) ? 9'd128 : 9'd256);
    tph = ((kpose * 16'd51) >> 3) + 6'd13 * tj + (ti ? 6'd20 : 6'd0);
    tmul = $signed({1'b0, ({8'd0, tamp[tp]} * {9'd0, tjn}) >> 8}) * sin_q8(tph);
    twave = kdash[tp] ? 16'sd0 : {{4{tmul[19]}}, tmul[19:8]};
    tsum = tbase + $signed({{4{tbend[tp][11]}}, tbend[tp]}) * $signed({13'd0, tj}) + twave + 16'sd128;
end
always @(posedge clk) begin
    if (snapshot)
        tq <= 5'd0;
    else if (tq < 5'd20) begin
        tdy[{tp, 1'b0} * 5 + (ti ? 5 : 0) + tj - 1] <= tsum >>> 8;
        tq <= tq + 5'd1;
    end
end
// ------------------------------------------------- racchette dei personaggi
// Come draw_paddle e kind_ops di rust/game/src/paddle_ui.rs, sul corpo largo 4 (tools/paddle_shapes.py,
// il modello in Python con le stesse regole). Coordinate del tipo: u la colonna, 0 la faccia, il corpo
// da -3 a 0, negativa verso il retro (la racchetta destra è speculare); v la riga dall'alto. Un pixel
// prende il ruolo dell'ultimo pezzo che lo copre; sopra vanno le luci e le ombre dei bordi dei pezzi
// alti e larghi almeno 2 (l'ultimo vince): retro e fondo del corpo in ombra, bordo alto schiarito e
// basso scurito sui segni e sui grigi; poi il bordo scuro di HAMMER. Fuori dalla forma, l'ombra portata
// (la stessa forma 1 pixel verso il retro e 1 in basso: una seconda chiamata). Le animazioni usano i
// contatori di pong_top e le tabelle di pong_paddles.vh (tools/gen_mister_paddles.py).
localparam [3:0] KR_NONE = 4'd0, KR_BODY = 4'd1, KR_SHADE = 4'd2, KR_MARK = 4'd3, KR_MARK_DARK = 4'd4,
                 KR_MARK_LIGHT = 4'd5, KR_GRAY = 4'd6, KR_GRAY_LIGHT = 4'd7, KR_DARK = 4'd8, KR_DARK_DEEP = 4'd9,
                 KR_BLACK = 4'd10, KR_SIGNAL = 4'd11, KR_SHADOW = 4'd12;
// altezze dei tipi (pixel)
localparam integer HT_A = kind_px_h(3'd0), HT_T = kind_px_h(3'd1), HT_H = kind_px_h(3'd2), HT_W = kind_px_h(3'd3),
                   HT_B = kind_px_h(3'd4), HT_R = kind_px_h(3'd5), HT_G = kind_px_h(3'd6);
// GUARDIAN: righe dei 5 corsi (round(h * i / 5)), come paddle_ui.rs
localparam integer GY1 = (HT_G * 2 + 5) / 10, GY2 = (HT_G * 4 + 5) / 10, GY3 = (HT_G * 6 + 5) / 10,
                   GY4 = (HT_G * 8 + 5) / 10;
// BLASTER: metà altezza e prima riga della cinghia; TITAN: riga della cintura; HAMMER: centro dell'occhio
localparam integer BMID = HT_B / 2, BSTRAP = HT_B / 2 - 9, TBELT = (HT_T + 1) / 2 - 2, HEYE = (HT_H + 1) / 2;

// il pixel (u, v) è nel rettangolo [X0, X0 + WW) x [Y0, Y0 + HH)
`define KIN(X0, Y0, WW, HH) ((u) >= (X0) && (u) < (X0) + (WW) && (v) >= (Y0) && (v) < (Y0) + (HH))
// pezzo senza bordi (largo o alto 1, o un colore senza toni: nero, giallo, schiarito)
`define KF(X0, Y0, WW, HH, R) if (`KIN(X0, Y0, WW, HH)) fill = R;
// corpo: colonna del retro (se è il retro della racchetta) e fondo in ombra
`define KB(X0, Y0, WW, HH) if (`KIN(X0, Y0, WW, HH)) begin fill = KR_BODY; \
    if (((X0) <= -3 && (u) == (X0)) || ((v) == (Y0) + (HH) - 1 && (u) > (X0) && (u) < (X0) + (WW) - 1)) rel = KR_SHADE; end
// pezzo con il bordo alto in luce e il basso in ombra (largo e alto almeno 2)
`define KT(X0, Y0, WW, HH, R, RL, RD) if (`KIN(X0, Y0, WW, HH)) begin fill = R; \
    if ((v) == (Y0)) rel = RL; else if ((v) == (Y0) + (HH) - 1) rel = RD; end
`define KM(X0, Y0, WW, HH) `KT(X0, Y0, WW, HH, KR_MARK, KR_MARK_LIGHT, KR_MARK_DARK)
`define KG(X0, Y0, WW, HH) `KT(X0, Y0, WW, HH, KR_GRAY, KR_GRAY_LIGHT, KR_DARK)
`define KD(X0, Y0, WW, HH) `KT(X0, Y0, WW, HH, KR_DARK, KR_GRAY, KR_DARK_DEEP)

// TWIST e BLASTER: lembi della fascia e della bandana, segmento del pixel della colonna u (0: nessuno)
function [2:0] tail_seg(input signed [11:0] u, input wide);
    tail_seg = wide ? ((u >= -6 && u < -3) ? 3'd1 : (u >= -9 && u < -6) ? 3'd2 : (u >= -12 && u < -9) ? 3'd3 :
                       (u >= -15 && u < -12) ? 3'd4 : (u >= -18 && u < -15) ? 3'd5 : 3'd0)
                    : ((u >= -5 && u < -3) ? 3'd1 : (u >= -7 && u < -5) ? 3'd2 : (u >= -9 && u < -7) ? 3'd3 :
                       (u >= -11 && u < -9) ? 3'd4 : (u >= -13 && u < -11) ? 3'd5 : 3'd0);
endfunction

// TWIST: il pixel (du, dv) dal centro dell'estremità è sull'onda (anello fra lo e hi, arco fra due
// direzioni: in alto da 150 a 300 gradi, in basso da 60 a 210, con la y verso il basso)
function ring_px(input signed [11:0] du, input signed [11:0] dv, input top, input [12:0] lo, input [12:0] hi);
    reg [12:0] d2;
    begin
        d2 = (du * du + dv * dv) << 4;
        ring_px = du > -16 && du < 16 && dv > -16 && dv < 16 && d2 >= lo && d2 < hi &&
                  (top ? (-7 * dv - 4 * du >= 0 && -7 * du - 4 * dv >= 0)
                       : (4 * dv - 7 * du >= 0 && 7 * dv - 4 * du >= 0));
    end
endfunction

// Ruolo del pixel (u0, v0) della racchetta del lato p, del tipo kind (KR_NONE fuori dalla forma).
function [3:0] kind_px(input p, input [2:0] kind, input signed [11:0] u0, input signed [11:0] v0);
    reg signed [11:0] u, v, d, sh, ff, row, slot, y0, y1, ys, hh;
    reg [3:0] fill, rel, late;
    reg [2:0] m, sg;
    reg [4:0] f;
    reg [5:0] ka, ca;
    reg [2:0] alive;
    reg        hit, fire, recent;
    integer    c, j;
    begin
        fill = KR_NONE;
        rel = KR_NONE;
        late = KR_NONE;
        u = u0;
        v = v0;
        hit = kha[p] != 5'd0;
        f = PD_HIT_FRAMES - kha[p];                 // frame dal colpo
        fire = kfa[p] != 5'd0;
        ff = PD_FIRE_FRAMES - $signed({7'd0, kfa[p]});   // frame dallo sparo
        row = $signed({6'd0, khr[p]});
        case (kind)
            K_ARCADE: begin
                `KB(-3, 0, 4, HT_A)
                // fessura della gettoniera e gettone che ci entra (pose 0-5 giù, 6-8 di taglio, 10-13 lampi)
                `KF(-1, HT_A / 2 - 4, 1, 8, (coin_s == 5'd10 || coin_s == 5'd12) ? KR_MARK : KR_DARK)
                if (coin_s <= 5'd5) begin
                    `KF(-2, HT_A / 2 - 10 + $signed({7'd0, coin_s}), 2, 1, KR_MARK)
                    `KF(-1, HT_A / 2 - 11 + $signed({7'd0, coin_s}), 1, 3, KR_MARK)
                end else if (coin_s <= 5'd8) begin
                    `KF(-1, HT_A / 2 - 4, 1, (coin_s == 5'd6) ? 6 : (coin_s == 5'd7) ? 4 : 2, KR_MARK)
                end
            end
            K_TITAN: begin
                // più spessa verso il retro, cintura con i fori, fibbia che sporge, polvere del passo
                `KB(-6, 0, 7, HT_T)
                `KM(-6, TBELT, 6, 4)
                `KF(-4, TBELT + 1, 1, 1, KR_MARK_DARK)
                `KF(-2, TBELT + 1, 1, 1, KR_MARK_DARK)
                `KG(-9, TBELT - 1, 3, 6)
                `KF(-8, TBELT, 1, 4, KR_DARK)
                for (c = 0; c < 8; c = c + 1)
                    if (dpv[8 * p + c]) begin
                        if (dpb[8 * p + c]) begin
                            `KG(dpx[8 * p + c] - 1, dpy[8 * p + c], 2, 2)
                        end else begin
                            `KF(dpx[8 * p + c], dpy[8 * p + c], 1, 1, KR_DARK)
                        end
                    end
            end
            K_HAMMER: begin
                // testa della mazza dall'alto: piano bianco, occhio con la punta del manico e il cuneo;
                // il bordo scuro del retro dopo il rilievo; scintille dalla faccia al colpo potente
                `KB(-6, 0, 7, HT_H)
                `KD(-4, HEYE - 4, 4, 8)
                `KM(-3, HEYE - 3, 2, 6)
                `KF(-3, HEYE - 1, 2, 1, KR_MARK_DARK)
                if (hit && pd_spark(pd_spark_pose(f), u, v - row))
                    fill = (pd_spark_pose(f) >= 2'd2) ? KR_MARK_DARK : KR_MARK;
                if (u == -6 && v >= 0 && v < HT_H) late = KR_DARK;
            end
            K_TWIST: begin
                // inclinata: righe spostate di (v - h/2) * tilt / 8 verso la faccia
                d = v - HT_W / 2;
                m = ktilt[p][2] ? -ktilt[p] : ktilt[p];
                sh = (m[0] ? d : 12'sd0) + (m[1] ? d <<< 1 : 12'sd0);
                sh = ktilt[p][2] ? -(sh >>> 3) : (sh >>> 3);
                u = u0 - sh;
                `KB(-3, 0, 4, HT_W)
                `KF(-1, 2, 1, HT_W - 4, KR_MARK)
                `KM(-2, HT_W / 2 - 2, 2, 4)
                // onda del colpo attorno alle due estremità, mai sul corpo
                if (hit && !(u >= -3 && u <= 0 && v >= 0 && v < HT_W) &&
                    (ring_px(u + 1, v - 2, 1'b1, pd_ring_lo(f), pd_ring_hi(f)) ||
                     ring_px(u + 1, v - (HT_W - 2), 1'b0, pd_ring_lo(f), pd_ring_hi(f))))
                    fill = (f < 5'd15) ? KR_MARK : KR_MARK_DARK;
            end
            K_BLASTER: begin
                // allo sparo tutta la racchetta arretra di 1 pixel per 3 frame, le canne rientrano e
                // tornano in 8, lampo alla bocca, il bossolo vola dietro
                if (fire && ff < 3) u = u0 + 1;
                `KB(-3, 0, 3, HT_B)
                `KF(0, 2, 1, HT_B - 4, KR_BODY)
                if (fire && ff < 3) begin
                    `KF(1, BMID - 3, 1, 2, KR_GRAY)
                    `KF(1, BMID + 1, 1, 2, KR_GRAY)
                    `KF(2, BMID - 4, 1, 3, KR_SIGNAL)
                    `KF(2, BMID + 1, 1, 3, KR_SIGNAL)
                    `KF(3, BMID - 2, 2, 4, KR_SIGNAL)
                    `KF(5, BMID - 1, 1, 2, KR_SIGNAL)
                end else if (fire && ff < 8) begin
                    `KG(1, BMID - 3, 2, 2)
                    `KG(1, BMID + 1, 2, 2)
                end else begin
                    `KG(1, BMID - 3, 3, 2)
                    `KG(1, BMID + 1, 3, 2)
                end
                // lembi della bandana
                sg = tail_seg(u, 1'b0);
                if (sg != 3'd0) begin
                    if (sg <= ktn[2 * p] && v == tdy[10 * p + sg - 1]) fill = KR_MARK;
                    if (sg <= ktn[2 * p + 1] && v == tdy[10 * p + 4 + sg])
                        fill = (sg == ktn[2 * p + 1]) ? KR_MARK_DARK : KR_MARK;
                end
                // cinghia e cartuccera (dal basso), poi il bossolo del colpo appena vuotato
                `KF(-4, BSTRAP, 1, 21, KR_DARK)
                for (c = 0; c < 4; c = c + 1)
                    if (c + kammo[p] >= 4) begin
                        `KF(-6, BSTRAP + 1 + 5 * c, 2, 3, KR_SIGNAL)
                    end
                slot = (kammo[p] >= 3'd3) ? 12'sd0 : 12'sd3 - $signed({9'd0, kammo[p]});
                if (fire && ff >= 2) begin
                    `KF(pd_case_x(ff[4:0]), BSTRAP + 1 + 5 * slot + pd_case_y(ff[4:0]), 2, 1, KR_SIGNAL)
                end
            end
            K_RUSH: begin
                // fascia in cima con i lembi che escono dietro dal nodo
                `KB(-3, 0, 4, HT_R)
                `KM(-3, 3, 3, 2)
                sg = tail_seg(u, 1'b1);
                if (sg != 3'd0) begin
                    if (sg <= ktn[2 * p] && v == tdy[10 * p + sg - 1]) fill = KR_MARK;
                    if (sg <= ktn[2 * p + 1] && v == tdy[10 * p + 4 + sg])
                        fill = (sg == ktn[2 * p + 1]) ? KR_MARK_DARK : KR_MARK;
                end
            end
            K_GUARDIAN: begin
                // tutta la racchetta è un muro: 5 corsi (uno per settore) con le fughe nel suo colore e
                // i giunti sfalsati; il corso del settore perso si crepa, poi è grigio e perde le schegge;
                // l'ultimo rimasto lampeggia; il corso colpito rientra; nel conto alla rovescia i corsi
                // cadono dal basso
                alive = {2'd0, kwall[p][0]} + kwall[p][1] + kwall[p][2] + kwall[p][3] + kwall[p][4];
                ka = PD_BARRIER_FRAMES - kba[p];               // frame dalla rottura dell'ultimo settore
                ca = ka - PD_CRACK_FRAMES;
                for (c = 0; c < 5; c = c + 1) begin
                    // il corso, spostato dal rientro (verso il retro) e dalla caduta
                    u = u0 + ((hit && f < 5'd6 && krc[p] == c) ? 12'sd1 : 12'sd0);
                    v = v0 - (kbuild ? gbd[c] : 12'sd0);
                    y0 = (c == 0) ? 0 : (c == 1) ? GY1 : (c == 2) ? GY2 : (c == 3) ? GY3 : GY4;
                    y1 = (c == 0) ? GY1 : (c == 1) ? GY2 : (c == 2) ? GY3 : (c == 3) ? GY4 : HT_G;
                    ys = (c > 0) ? y0 + 1 : y0;                // righe sotto la fuga
                    hh = y1 - ys;
                    recent = !kwall[p][c] && khit[p][c] && kba[p] != 6'd0;
                    if (!kbuild || gbv[c]) begin
                        `KB(-6, y0, 7, y1 - y0)
                        if (kwall[p][c] || (recent && ka < PD_CRACK_FRAMES)) begin
                            if (kwall[p][c] && alive == 3'd1 && !kpose[1]) begin
                                `KF(-6, ys, 7, hh, KR_MARK_LIGHT)
                            end
                            // giunti sfalsati
                            if (c % 2 == 1) begin
                                `KF(-5, ys, 1, hh, KR_MARK)
                                `KF(-1, ys, 1, hh, KR_MARK)
                            end else begin
                                `KF(-3, ys, 1, hh, KR_MARK)
                            end
                        end else begin
                            `KD(-6, ys, 7, hh)
                        end
                        if (!kwall[p][c]) begin
                            // crepa, poi le schegge che saltano via dietro
                            `KF(-4, ys + 1, 1, 2, KR_BLACK)
                            `KF(-3, ys + 3, 1, 1, KR_BLACK)
                            `KF(-2, ys + 4, 1, 2, KR_BLACK)
                            if (recent && ka >= PD_CRACK_FRAMES && ka < PD_BREAK_FRAMES)
                                for (j = 0; j < 4; j = j + 1) begin
                                    if (j % 2 == 1) begin
                                        `KF(pd_chip_x(ca[4:0], j), ys + pd_chip_y(ca[4:0], j), 1, 1, KR_GRAY)
                                    end else begin
                                        `KF(pd_chip_x(ca[4:0], j), ys + pd_chip_y(ca[4:0], j), 2, 1, KR_DARK)
                                    end
                                end
                        end
                        if (c > 0) begin
                            `KF(-6, y0, 7, 1, KR_MARK)                 // fuga, anche sulla faccia
                        end
                    end
                end
                u = u0;
                v = v0;
            end
            default: begin
                // senza tipo (solo con una mossa di livello 2: la racchetta gialla)
                `KF(-3, 0, 4, $signed({2'b0, kh[p]}), KR_BODY)
            end
        endcase
        kind_px = (late != KR_NONE) ? late : (rel != KR_NONE) ? rel : fill;
    end
endfunction

// colore del ruolo r della racchetta del lato p: il corpo come la racchetta di prima (grigio con un
// bonus armato o dell'avversario nel bullet time, giallo con la mossa di livello 2, rosso o viola di
// OMEGA) e il suo tono in ombra; i segni nel colore del personaggio
function [6:0] kr_col(input [3:0] r, input p);
    reg [2:0] b;
    begin
        b = mmax[p] ? (bcold[p] ? 3'd1 : 3'd2) : kgray[p] ? 3'd1 :
            (!omega_pad[p] || omega_flash) ? 3'd0 : omega_egg ? 3'd4 : 3'd3;
        case (r)
            KR_BODY:       kr_col = (b == 3'd0) ? WHITE : (b == 3'd1) ? GRAY : (b == 3'd2) ? ACCENT :
                                    (b == 3'd4) ? OMEGA_PURPLE : OMEGA_RED;
            KR_SHADE:      kr_col = (b == 3'd0) ? P_WHITE_SH : (b == 3'd1) ? P_GRAY_SH : (b == 3'd2) ? P_ACCENT_SH :
                                    (b == 3'd4) ? P_PURPLE_SH : P_RED_SH;
            KR_MARK:       kr_col = P_MARK + 7'd3 * kd[p];
            KR_MARK_DARK:  kr_col = P_MARK + 7'd3 * kd[p] + 7'd1;
            KR_MARK_LIGHT: kr_col = P_MARK + 7'd3 * kd[p] + 7'd2;
            KR_GRAY:       kr_col = P_GRAY;
            KR_GRAY_LIGHT: kr_col = P_GRAY_LIGHT;
            KR_DARK:       kr_col = P_DARK;
            KR_DARK_DEEP:  kr_col = P_DARK_DEEP;
            KR_SIGNAL:     kr_col = ACCENT;
            KR_SHADOW:     kr_col = P_SHADOW;
            default:       kr_col = BLACK;
        endcase
    end
endfunction

// muro del GUARDIAN in campo: prima e ultima riga dei settori, e righe delle schegge del blocco (j da 0 a 7)
function [9:0] wall_s0(input [2:0] k);
    wall_s0 = (k == 3'd0) ? WALL_TOP : (k == 3'd1) ? WALL_B1 : (k == 3'd2) ? WALL_B2 : (k == 3'd3) ? WALL_B3 : WALL_B4;
endfunction
function [9:0] wall_s1(input [2:0] k);
    wall_s1 = (k == 3'd0) ? WALL_B1 : (k == 3'd1) ? WALL_B2 : (k == 3'd2) ? WALL_B3 : (k == 3'd3) ? WALL_B4 : H;
endfunction
function [9:0] wall_chip_y(input [2:0] k, input [2:0] j);
    case (k)
        3'd0: wall_chip_y = WALL_TOP + 5 + j * (WALL_B1 - WALL_TOP - 10) / 7;
        3'd1: wall_chip_y = WALL_B1 + 5 + j * (WALL_B2 - WALL_B1 - 10) / 7;
        3'd2: wall_chip_y = WALL_B2 + 5 + j * (WALL_B3 - WALL_B2 - 10) / 7;
        3'd3: wall_chip_y = WALL_B3 + 5 + j * (WALL_B4 - WALL_B3 - 10) / 7;
        default: wall_chip_y = WALL_B4 + 5 + j * (H - WALL_B4 - 10) / 7;
    endcase
endfunction

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
reg [9:0]  dx, dy, sx;
reg [TEXT_W-1:0] trow;
reg signed [10:0] sdx, sdy;
reg signed [21:0] u8, v8;
reg signed [11:0] sy;
reg        w_col, w_line;
reg signed [11:0] kx, ky, kq, kr, ka;
reg signed [11:0] ke, kf, kv, kb, ko;  // colpo di una mossa: frame dal colpo, davanti, dal centro, dietro
integer    k, p, r;
// mosse speciali: nome della mossa nella scritta e barre dei due giocatori (un solo confronto per pixel)
reg        mv_code, mv_on, hb_p;
reg [9:0]  mv_dx, mv_dy, bq_x, bq_y;
reg [7:0]  bq_lvl;
reg [1:0]  bq;
// riserve in partita: lato e posto del pixel, il suo bonus, se è il selezionato, e il pixel che ne esce
reg        rv_p, rv_sel, rv_on;
reg [1:0]  rv_k;
reg [3:0]  rv_b;
reg [6:0]  rv_col;
// chiamate condivise tra le schermate (vedi il pixel)
reg        sh_name;
reg        sh_p, sh_occ;
reg [3:0]  sh_kr;
reg signed [11:0] sh_u, sh_v;
// pixel delle due racchette in partita: ruolo (kind_px, con l'ombra portata) e dentro il rettangolo
reg [3:0]  kcp [0:1];
reg        kin [0:1];
// muro del GUARDIAN in campo: frame dalla rottura, settore, colonna del blocco, schegge
reg [5:0]  wa;
reg [2:0]  wk;
reg [9:0]  ws0, ws1, wbx, wy;
reg [4:0]  wf;
reg [3:0]  wdx, wdy;
reg [1:0]  wsz;
integer    wj;

always @(*) begin
    on = 1'b0;
    col = WHITE;
    gray_px = 1'b0;
    lb = 1'b0;
    trow = 5'd0;
    dx = 10'd0;
    dy = 10'd0;
    sx = 10'd0;
    sdx = 11'sd0;
    sdy = 11'sd0;
    u8 = 22'sd0;
    v8 = 22'sd0;
    sy = $signed({2'b0, y});
    kx = 12'sd0;
    ky = 12'sd0;
    kq = 12'sd0;
    ka = 12'sd0;
    kr = 12'sd0;
    w_col = x - (wx - PW / 2) < PW;
    w_line = x - (wx - WARP_LINE_HALF) < 2 * WARP_LINE_HALF;
    hb_p = x >= W / 2;
    mv_code = label_move == 2'd2;
    mv_dx = x - label_x - (NX_P1_W + 9) - (label_mx ? NX_MAX_W + 9 : 0);
    mv_dy = y - LABEL_TOP;
    ldx = x - label_x;
    lbox = 1'b0;
    ltext = 1'b0;
    lcol = 1'b0;
    ldash = 1'b0;
    lpos = 10'd0;
    pad_box = 1'b0;
    rv_p = 1'b0;
    rv_k = 2'd0;
    rv_b = 4'd0;
    rv_sel = 1'b0;
    rv_on = 1'b0;
    rv_col = BLACK;
    kcp[0] = KR_NONE;
    kcp[1] = KR_NONE;
    wa = 6'd0;
    wk = 3'd0;
    ws0 = 10'd0;
    ws1 = 10'd0;
    wbx = 10'd0;
    wy = 10'd0;
    wf = 5'd0;
    wdx = 4'd0;
    wdy = 4'd0;
    wsz = 2'd0;
    kin[0] = 1'b0;
    kin[1] = 1'b0;
    // barre nella banda in alto: la sinistra da BAR_X, la destra speculare
    bq_x = hb_p ? (W - 1 - BAR_X) - x : x - BAR_X;
    bq_y = y - (BAR_Y - 2);
    bq_lvl = mtr[hb_p];
    mv_on = move_lit({2'd0, mv_code}, mv_dx, mv_dy);
    bq = bar_px(bq_x, bq_y, bq_lvl);

    // pixel delle racchette in partita: le due stanno ciascuna nella sua metà dello schermo, quindi una
    // sola chiamata a kind_px (quella del lato del pixel), più quella dell'ombra portata (la forma 1
    // pixel verso il retro e 1 in basso); e nome del bonus della scritta
    sh_p = x >= W / 2;
    sh_u = sh_p ? kl[1] - $signed({2'b0, x}) : $signed({2'b0, x}) - kl[0] - 12'sd3;
    sh_v = $signed({2'b0, y}) - kt[sh_p];
    sh_kr = kind_px(sh_p, kd[sh_p], sh_u, sh_v);
    sh_occ = sh_kr != KR_NONE && kd[sh_p] != K_NONE;
    if (!sh_occ && kd[sh_p] != K_NONE && sh_up)
        sh_kr = KR_SHADOW;
    sh_name = name_lit(label_bonus, ldx - (NX_P1_W + 9), y - LABEL_TOP);

    if (nxt) begin
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
            kcp[k] = (sh_p == k) ? sh_kr : KR_NONE;
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
            // racchette dei personaggi (pong_render non le disegna): tutti i pixel della forma, l'ombra
            // portata compresa; non durante la rotazione del SUPER e il salto del TELEPORT; con una
            // mossa di livello 2 armata la racchetta è gialla (anche senza tipo)
            if ((kd[p] != K_NONE || mmax[p]) && !spin[p] && !(wv && wsd == p) && kcp[p] != KR_NONE) begin
                on = 1'b1;
                col = kr_col(kcp[p], p);
            end
            // BLASTER: i colpi in volo, due tratti gialli paralleli (la cartuccera è nella racchetta)
            if (kd[p] == K_BLASTER) begin
                for (k = 0; k < 4; k = k + 1)
                    if (kshot[4*p + k] && span(x, ksx[4*p + k], 3, 7) && (y == ksy[4*p + k] - 2 || y == ksy[4*p + k] + 2)) begin
                        on = 1'b1;
                        col = ACCENT;
                    end
            end
            // RUSH: tre immagini della racchetta tra casa e dove si trova mentre scatta in avanti, più
            // scure verso casa e che sfumano (kfade da 3 a 1); non sopra la racchetta
            if (kd[p] == K_RUSH && kfade[p] != 2'd0 && !spin[p] && !(wv && wsd == p) && (kcp[p] == KR_NONE || kcp[p] == KR_SHADOW) &&
                sy - kt[p] >= 0 && sy - kt[p] < $signed({2'b0, kh[p]}) &&
                !($signed({2'b0, x}) - kl[p] >= 0 && $signed({2'b0, x}) - kl[p] < PW))
                for (k = 0; k < 3; k = k + 1)
                    if ($signed({2'b0, x}) - kg[3*p + k] >= 0 && $signed({2'b0, x}) - kg[3*p + k] < PW &&
                        k + kfade[p] >= 3) begin
                        on = 1'b1;
                        col = (k + kfade[p] == 5) ? P_RGHOST3 : (k + kfade[p] == 4) ? P_RGHOST2 : P_RGHOST1;
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
            // GUARDIAN: il muro in campo non si vede (è nei corsi della racchetta); dove la palla lo
            // colpisce, sulla sua linea, il blocco del settore lampeggia (PD_BLINK_FRAMES), poi si
            // sbriciola in 8 schegge che vanno verso il fondo e cadono
            if (kd[p] == K_GUARDIAN && kba[p] != 6'd0) begin
                wa = PD_BARRIER_FRAMES - kba[p];
                wk = khit[p][0] ? 3'd0 : khit[p][1] ? 3'd1 : khit[p][2] ? 3'd2 : khit[p][3] ? 3'd3 : 3'd4;
                ws0 = wall_s0(wk);
                ws1 = wall_s1(wk);
                wbx = (p == 0) ? BARRIER_X - 2 : W - BARRIER_X - 2;
                if (wa < PD_BLINK_FRAMES) begin
                    if (x - wbx < 4 && y >= ws0 + 3 && y < ws1 - 3) begin
                        on = 1'b1;
                        col = (y == ws0 + 11 || y == ws0 + 20 || y == ws0 + 29 || y == ws0 + 38) ? BLACK :
                              wa[2] ? P_WALL : P_WALL_LIGHT;
                    end
                end else begin
                    wf = wa - PD_BLINK_FRAMES;
                    wdy = pd_crumble_dy(wf);
                    for (wj = 0; wj < 8; wj = wj + 1) begin
                        wdx = pd_crumble_dx(wf, wj % 3);
                        wsz = (wj % 2 == 1) ? 2'd1 : 2'd2;
                        wy = wall_chip_y(wk, wj) + wdy;
                        if (x - ((p == 0) ? BARRIER_X - 1 - wdx : W - BARRIER_X + 1 + wdx - wsz) < wsz &&
                            y - wy < wsz) begin
                            on = 1'b1;
                            col = (pd_crumble_tone(wf) == 2'd0) ? P_WALL : (pd_crumble_tone(wf) == 2'd1) ? P_WALL1 : P_WALL2;
                        end
                    end
                end
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
                (label_mx && nx_max_lit(ldx - (NX_P1_W + 9), y - LABEL_TOP)) ||
                (label_move != 2'd0 ? mv_on : sh_name) ||
                nx_bang_lit(ldx - (NX_P1_W + 9 + label_name_w + 1), y - LABEL_TOP);
        // colonne con una lettera (solo per le mosse): sotto di loro i trattini, al colpo i blocchi
        lcol = x - label_x < label_w &&
               ((label_player ? nx_p2_col(ldx) : nx_p1_col(ldx)) ||
                (label_mx && nx_max_col(ldx - (NX_P1_W + 9))) ||
                (label_move == 2'd2 ? nx_move1_col(ldx - (NX_P1_W + 9) - (label_mx ? NX_MAX_W + 9 : 0))
                                    : nx_move0_col(ldx - (NX_P1_W + 9) - (label_mx ? NX_MAX_W + 9 : 0))) ||
                nx_bang_col(ldx - (NX_P1_W + 9 + label_name_w + 1)));
        ldash = lcol && (y == LABEL_TOP + 9 || (label_mx && y == LABEL_TOP + 11));
        // distanza dal lato del giocatore che ha fatto la mossa
        lpos = label_player ? label_x + label_w - 1 - x : x - label_x;
        // le racchette stanno sopra alla scritta: sui pixel della racchetta (il rettangolo di
        // pong_render e quelli del suo tipo, anche la HAMMER più spessa) la scritta non si disegna e
        // restano pong_render e i segni qui sopra; accanto la scritta resta intera
        pad_box = kcp[0] != KR_NONE || kin[0] || kcp[1] != KR_NONE || kin[1];
        if (pad_box) ;
        else if (label_on && label_kind == LK_ARMED) begin
            // solo i trattini: l'ultimo disegnato bianco, poi grigi che si accendono mentre la palla arriva
            if (ldash && lpos < dash_rev) begin
                on = 1'b1;
                lb = 1'b1;
                col = (lpos + 8 >= dash_rev && dash_rev < label_w) ? WHITE : (lpos < dash_lit) ? ACCENT : DIM;
            end
        end else if (label_on && label_kind == LK_HIT) begin
            // colpo: blocchi bianchi, poi la scritta e i trattini accesi; nell'ultima parte lampeggia
            if (lbox && !(label_age >= 7'd44 && label_age[2])) begin
                on = 1'b1;
                lb = 1'b1;
                col = BLACK;
                if (label_age < 7'd2 ? (lcol && y >= LABEL_TOP && y < LABEL_TOP + 7) : ltext)
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

// ombra portata delle racchette: la forma nella riga sopra, 1 pixel verso il retro (x + 1 per la
// sinistra, x - 1 per la destra). Un bit per pixel della forma (sh_occ) in due righe alternate;
// sh_up si legge durante il pixel x (hc resta fermo 3 cicli) e vale per lo stesso pixel (con x + 2
// e x l'ombra veniva 2 pixel a sinistra della racchetta sinistra e sotto la destra)
reg        sh_lb0 [0:511];
reg        sh_lb1 [0:511];
reg        sh_up = 1'b0;
wire [9:0] sh_rx = (x >= W / 2) ? x - 10'd1 : x + 10'd1;
always @(posedge clk) begin
    if (y[0]) begin
        sh_lb1[x[8:0]] <= sh_occ;
        sh_up <= sh_lb0[sh_rx[8:0]] && y != 10'd0;
    end else begin
        sh_lb0[x[8:0]] <= sh_occ;
        sh_up <= sh_lb1[sh_rx[8:0]] && y != 10'd0;
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
