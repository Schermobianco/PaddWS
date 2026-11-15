// Schermate della scalata di NEXT (la modalità CHALLENGE fino alla 4.1, come
// rust/game/src/challenge_ui.rs): presentazione dell'avversario, livello superato, continue, iniziali,
// classifica, nuovo sfidante, e in partita i punti arcade in basso dalla parte dell'avversario; sopra
// a tutte, quando serve, "n WINS" (duelli vinti di fila dal campione). Scritte fisse da
// tools/gen_challenge_assets.py; numeri e iniziali con lo stesso font (Press Start 2P) in celle di 8x8
// pixel: per ogni pixel si sceglie al più una cella, poi un solo accesso al font. Tutto a scala 1,
// solo GAME OVER (continue scaduto) alla scala grande della fine partita (1 << BIG_SH).
// I nomi degli avversari nelle presentazioni e HERE COMES A NEW CHALLENGER! sono grafiche disegnate
// a pixel (tools/gen_mister_titles.py, pong_titles.vh): una ROM in M10K con il ruolo del colore di
// ogni pixel, letta da due porte (la seconda per l'immagine gialla dietro al nome del RUSH). Pipeline
// di due cicli: nel primo l'indirizzo della ROM e il colore del resto della schermata, dove il titolo
// lascia un segno (MARK) con il colore che sta sotto; nel secondo il colore del titolo o quello sotto.
// Un pixel dura 3 cicli di clk, quindi il colore arriva in tempo, come in howto_render.

`timescale 1ns / 1ps

module challenge_render #(
    parameter TITLE_ROM = "rtl/gen/title_challenge.hex"
) (
    input  wire        clk,
    input  wire [9:0]  hc,
    input  wire [9:0]  vc,
    input  wire [2:0]  screen,            // 0 niente, 1 presentazione, 2 livello superato, 3 continue,
                                          // 4 iniziali, 5 classifica, 6 punti in partita, 7 nuovo sfidante
    input  wire        side,              // il giocatore è a destra: punti in partita in basso a sinistra
    input  wire        join_prompt,       // presentazione: uno sfidante può entrare dal lato libero
    input  wire        train,             // allenamento: niente punti arcade, nessun livello battuto
    input  wire [2:0]  level,             // livello in corso (0-6)
    input  wire [2:0]  kind,              // racchetta dell'avversario
    input  wire [8:0]  loadout,           // bonus dell'avversario (3 bit ciascuno)
    input  wire [27:0] score_bcd,         // punti arcade, 7 cifre
    input  wire [27:0] hi_bcd,            // primo della classifica
    input  wire        perfect,           // livello vinto senza punti dell'avversario
    input  wire        coin_prompt,       // INSERT COIN invece di PRESS START
    input  wire [5:0]  blink,             // frame % 60
    input  wire [3:0]  cont_digit,        // secondi del continue
    input  wire [5:0]  cont_sub,          // frame dentro il secondo del continue (0-59)
    input  wire        cont_over,         // continue scaduto: GAME OVER al posto della schermata
    input  wire [17:0] name,              // iniziali scelte (codici del font, 6 bit ciascuno)
    input  wire [1:0]  name_pos,          // lettera in corso
    input  wire [5:0]  letter,            // codice della lettera sotto il cursore
    input  wire [179:0] table_names,      // classifica: 10 x 3 codici
    input  wire [279:0] table_bcd,        // 10 x 7 cifre
    input  wire [39:0] table_levels,      // 10 x livello (8 = scala finita)
    input  wire [3:0]  highlight,         // posto appena inserito (15 = nessuno)
    input  wire [3:0]  mult,              // moltiplicatore dello scambio
    input  wire [7:0]  intro_age,         // presentazione: frame dall'inizio (fermi a 255)
    // "n WINS" in giallo, nella metà sinistra o destra: piccolo in alto al centro della metà
    // (presentazione) o in basso verso il bordo (fine del duello, lontano dai punteggi
    // ruotati verso i giocatori); n in BCD, 1-99
    input  wire        wins_on,
    input  wire        wins_right,
    input  wire        wins_big,
    input  wire [7:0]  wins_bcd,
    output reg  [23:0] rgb,
    output reg         opaque
);

`include "pong_params.vh"
`include "pong_next.vh"
`include "pong_challenge.vh"
`include "pong_attract.vh"
`include "pong_titles.vh"
`include "pong_fonts.vh"

localparam integer W = P_WIDTH >>> 16;
localparam [23:0] RGB_WHITE = 24'hFFFFFF, RGB_GRAY = 24'hB4B4B4, RGB_BLACK = 24'h000000, RGB_ACCENT = 24'hFFD225;
localparam [5:0] G_SPACE = 6'd36, G_PLUS = 6'd37, G_DOT = 6'd38, G_X = 6'd39, G_L = 6'd21;
localparam integer C = CH_CELL;
// presentazione: nome della racchetta (grafica centrata che finisce sulla riga NAME_BASE, esclusa;
// TITAN, alto 26, comincia a TITAN_TOP, sotto la sua racchetta, e il motto scende di 3 righe),
// motto TAG_GAP righe sotto il nome, capsule dei bonus (lato 13 come nel gioco PC, l'icona 9x9 con
// un pixel di margine), riga FIRST TO n centrata con una o due cifre
localparam integer NAME_BASE = 131, TITAN_TOP = 108, TAG_GAP = 4;
localparam integer INTRO_CAP = 13, INTRO_CAP_Y = 154, INTRO_FIRST_Y = 190;
localparam integer INTRO_TITLE_Y = 20;
// FIRST TO n: dopo la scritta uno spazio (le parole stanno nella griglia di 8 pixel)
localparam integer FIRST_X1 = (W - (CH_FIRST_W + 1 + 2 * C)) / 2, FIRST_X2 = (W - (CH_FIRST_W + 1 + 3 * C)) / 2;
// punti in partita: in fondo al campo, dalla parte dell'avversario (a destra da HUD_R, a sinistra
// speculari), in grigio per non distrarre; la scritta del bonus di NEXT sta in alto:
// "L1 0000000 x3", celle di 8 pixel con uno spazio fra i gruppi
localparam integer HUD_R = 200, HUD_SPAN = 13 * C - 1, HUD_L = W - HUD_R - HUD_SPAN, HUD_Y = 228;
// nuovo sfidante: banda rossa con la targa disegnata al centro
localparam integer NEW_BAND_Y = 96, NEW_BAND_H = 48;
localparam integer NEW_X = (W - TL_NEWCH_W) / 2, NEW_Y = NEW_BAND_Y + (NEW_BAND_H - TL_NEWCH_H) / 2;
// GAME OVER del continue scaduto: larghezza e altezza dell'inchiostro alla scala grande
localparam integer GO_WB = GAME_OVER_W << BIG_SH, BH = 7 << BIG_SH;
localparam [23:0] RGB_BAND = 24'h8C1414;
// invito allo sfidante, in alto al centro del lato libero: "P2 PRESS START" o "INSERT COIN"
localparam integer JOIN_Y = 2, JOIN_W = 3 * C + CH_PRESS_W;
localparam integer JOIN_XL = W / 4 - JOIN_W / 2, JOIN_XR = 3 * W / 4 - JOIN_W / 2;
localparam integer COIN_XL = W / 4 - CH_COIN_W / 2, COIN_XR = 3 * W / 4 - CH_COIN_W / 2;
localparam [5:0] G_P = 6'd25, G_V = 6'd31;
// classifica: colonne di posizione (due celle), iniziali, punti (7 cifre) e livello ("LV7" o "ALL", 3
// celle), distanziate di due o tre celle; l'elenco centrato sull'inchiostro (l'ultima colonna della
// cella è lo spazio fra i caratteri)
localparam integer TB_NAMES = 4 * C, TB_SCORE = 10 * C, TB_LEVEL = 20 * C, TB_SPAN = TB_LEVEL + 3 * C - 1;
localparam integer TB_X = (W - TB_SPAN) / 2;
// otto righe mostrate, la prima a TB_Y0, ogni TB_STEP pixel
localparam [9:0] TB_Y0 = 10'd40, TB_STEP = 10'd20;

// Colori come indici della tavolozza `pal` (4 bit invece di 24): le scelte del pixel si fanno fra
// indici e il colore vero si legge una volta sola, all'uscita. Per i titoli disegnati il giallo scuro,
// il grigio, il rosso e il rosso scuro (gli stessi di pong_render; egg_swap in pong_top li conosce);
// MARK non è un colore: il pixel va al titolo (secondo ciclo)
localparam [3:0] WHITE = 4'd0, GRAY = 4'd1, BLACK = 4'd2, ACCENT = 4'd3, BAND = 4'd4, DIM = 4'd5, GHOST = 4'd6,
                 TRAIL1 = 4'd7, TRAIL2 = 4'd8, TRAIL3 = 4'd9, T_DKYEL = 4'd10, T_GRAY = 4'd11, T_RED = 4'd12,
                 T_DKRED = 4'd13, MARK = 4'd15;
localparam [23:0] RGB_T_DKYEL = 24'h8A7114, RGB_T_GRAY = 24'h6E6E6E, RGB_T_RED = 24'hE62828, RGB_T_DKRED = 24'h5A0A0A;
function [23:0] pal(input [3:0] i);
    case (i)
        WHITE:  pal = RGB_WHITE;
        GRAY:   pal = RGB_GRAY;
        ACCENT: pal = RGB_ACCENT;
        BAND:   pal = RGB_BAND;
        DIM:    pal = RGB_DIM;
        GHOST:  pal = RGB_GHOST;
        TRAIL1: pal = RGB_TRAIL1;
        TRAIL2: pal = RGB_TRAIL2;
        TRAIL3: pal = RGB_TRAIL3;
        T_DKYEL: pal = RGB_T_DKYEL;
        T_GRAY: pal = RGB_T_GRAY;
        T_RED:  pal = RGB_T_RED;
        T_DKRED: pal = RGB_T_DKRED;
        default: pal = RGB_BLACK;
    endcase
endfunction
// ruolo di un pixel dei titoli -> indice della tavolozza; `hi`: il bianco diventa giallo (lampo)
function [3:0] role_col(input [3:0] r, input hi);
    case (r)
        TL_WHITE:       role_col = hi ? ACCENT : WHITE;
        TL_YELLOW:      role_col = ACCENT;
        TL_DARK_YELLOW: role_col = T_DKYEL;
        TL_GRAY:        role_col = T_GRAY;
        TL_DARK_GRAY:   role_col = DIM;
        TL_RED:         role_col = T_RED;
        TL_DARK_RED:    role_col = T_DKRED;
        default:        role_col = BLACK;
    endcase
endfunction

wire [9:0] x = hc;
wire [9:0] y = vc;

// il pixel p è nel tratto lungo s che parte h pixel prima di c (0 <= p - c + h < s), con i conti a
// 14 bit: come `p - (c - h) < s` con le costanti intere (a 32 bit), che però costa tre volte tanto
function span(input [9:0] p, input [9:0] c, input [10:0] h, input [11:0] s);
    reg signed [13:0] d;
    begin
        d = $signed({4'b0, p}) - $signed({4'b0, c}) + $signed({3'b0, h});
        span = !d[13] && d < $signed({2'b0, s});
    end
endfunction

// cifra i (0 = la più a sinistra) di un numero BCD a 7 cifre
function [5:0] bcd7(input [27:0] v, input [2:0] i);
    bcd7 = {2'd0, v[4 * (6 - i) +: 4]};
endfunction

// cella del font: codice, scostamento (già diviso per la scala) e colore
reg        g_on;
reg [5:0]  g_code;
reg [9:0]  g_dx, g_dy;
reg [3:0]  g_col;                       // indice della tavolozza (pal)
reg [3:0]  col;
reg        on;
reg [3:0]  row;
reg [2:0]  b_sel;                       // presentazione: bonus della colonna sotto il pixel
reg [9:0]  b_cx, b_dx, b_dy, first_x;
reg [4:0]  pts, pts_units;
reg [1:0]  pts_tens;
reg [9:0]  hud_x;
integer    i, j;
// presentazione: nome (riga, origine, colonna, colonna senza il corsivo del BLASTER, lettera del
// GUARDIAN e del BLASTER, riga nella grafica), immagine del RUSH, capsula
reg signed [10:0] n_row, n_x0, n_u, n_us, n_v, g_u, g_v;
reg [2:0]  n_li;
reg        n_ok, g_ok, c_lit;
// titoli: indirizzi delle due porte della ROM, il titolo copre il pixel, colore sotto il titolo
reg [TL_CH_ABITS-1:0] ta_addr, tb_addr;
reg        ta_ok;
reg [3:0]  under;
// "n WINS": pixel dall'inizio della scritta, cella
reg signed [10:0] w_x, w_y, w_u;
reg [2:0]  w_k;

// numero di 7 cifre in (x0, y0), scala 1
task digits7(input [9:0] x0, input [9:0] y0, input [27:0] v, input [3:0] c);
    for (j = 0; j < 7; j = j + 1)
        if (span(x, x0 + C * j, 11'd0, C) && span(y, y0, 11'd0, CH_GLYPH_H)) begin
            g_on = 1'b1; g_code = bcd7(v, j[2:0]); g_dx = x - (x0 + C * j); g_dy = y - y0; g_col = c;
        end
endtask

// una cella in (x0, y0) alla scala 2^s
task put(input [9:0] x0, input [9:0] y0, input [5:0] code, input [1:0] s, input [3:0] c);
    if (span(x, x0, 11'd0, C << s) && span(y, y0, 11'd0, CH_GLYPH_H << s)) begin
        g_on = 1'b1; g_code = code; g_dx = (x - x0) >> s; g_dy = (y - y0) >> s; g_col = c;
    end
endtask

// ------------------------------------------------ presentazione animata
// Come Stage di rust/game/src/challenge_ui.rs, con le distanze dimezzate: in cima il livello e sotto
// la scala dei sette livelli (trattini come quelli della mezzeria: battuti bianchi, quello in corso
// giallo che lampeggia), poi ogni avversario entra a modo suo e porta nome, motto, bonus e FIRST TO.
// La racchetta la disegna next_render (ip_*); qui il resto, con i valori di ogni frame calcolati da
// intro_age (i_*): nel pixel solo confronti e le ROM delle scritte. Le x "verso l'avversario" (ax)
// vanno verso la sua metà campo, da dove entra.
localparam integer IP_Y = 82;                     // centro della racchetta (INTRO_Y di next_render)
localparam integer LADDER_Y = 34, LADDER_X = 76;  // scala: 7 trattini 16x4 ogni 24 pixel
localparam integer NAME_GROUND = TITAN_TOP + 26;  // TITAN: il pavimento sotto il nome (alto 26)
localparam integer WALL_TOP = IP_Y - 36;          // GUARDIAN: 5 settori da 12 righe ogni 14, sopra il nome
localparam [2:0] K_ARCADE = 3'd0, K_TITAN = 3'd1, K_HAMMER = 3'd2, K_TWIST = 3'd3, K_BLASTER = 3'd4,
                 K_RUSH = 3'd5, K_GUARDIAN = 3'd6;
localparam [23:0] RGB_DIM = 24'h3A3A3A, RGB_GHOST = 24'h7F6912, RGB_TRAIL1 = 24'h9A9A9A, RGB_TRAIL2 = 24'h5E5E5E,
                  RGB_TRAIL3 = 24'h303030;

function signed [10:0] ax(input signed [10:0] d);
    ax = W / 2 + (side ? -d : d);
endfunction
// ARCADE: altezza delle capsule della raffica rispetto alla racchetta (come in next_render)
function signed [5:0] arcade_dy(input [3:0] k);
    case (k)
        4'd0: arcade_dy = -6'sd14; 4'd1: arcade_dy = 6'sd10;  4'd2: arcade_dy = -6'sd4; 4'd3: arcade_dy = 6'sd16;
        4'd4: arcade_dy = -6'sd18; 4'd5: arcade_dy = 6'sd2;   4'd6: arcade_dy = 6'sd12; 4'd7: arcade_dy = -6'sd10;
        4'd8: arcade_dy = 6'sd6;   default: arcade_dy = -6'sd2;
    endcase
endfunction
// ARCADE: trattini della mezzeria (6 righe accese ogni 12, dalla riga IP_Y - 28): (y - y0) / 6 pari
function net_dash(input [9:0] yy);
    reg [15:0] m;
    begin
        m = (yy - (IP_Y - 28)) * 43;
        net_dash = !m[8];
    end
endfunction
// TWIST: il nome entra inclinato e oscilla finché non si raddrizza (pixel per riga)
function signed [2:0] twist_shear(input [4:0] t);
    case (t)
        5'd0, 5'd1: twist_shear = 3'sd2;
        5'd5, 5'd6: twist_shear = -3'sd2;
        5'd2, 5'd9, 5'd10, 5'd11, 5'd18: twist_shear = 3'sd1;
        5'd4, 5'd7, 5'd13, 5'd14, 5'd15: twist_shear = -3'sd1;
        default: twist_shear = 3'sd0;
    endcase
endfunction
// ... spostamento della riga r (dal centro del nome, alto 20): s * r / 2 senza moltiplicazioni
function signed [10:0] twist_dx(input signed [2:0] s, input signed [10:0] r);
    case (s)
        3'sd1:   twist_dx = r >>> 1;
        3'sd2:   twist_dx = r;
        -3'sd1:  twist_dx = -(r >>> 1);
        -3'sd2:  twist_dx = -r;
        default: twist_dx = 11'sd0;
    endcase
endfunction
// presentazione: prima riga del nome e riga del motto
function [7:0] name_top(input [2:0] k);
    name_top = (k == K_TITAN) ? TITAN_TOP : NAME_BASE - tl_name_h(k);
endfunction
function [7:0] tag_y(input [2:0] k);
    tag_y = ((k == K_TITAN) ? NAME_GROUND : NAME_BASE) + TAG_GAP;
endfunction
// caduta: frazione della strada fatta (256 = arrivata) dopo t + 1 frame su 5, ((t + 1) / 5)^2
function [8:0] fall_q(input [2:0] t);
    case (t)
        3'd0: fall_q = 9'd10;  3'd1: fall_q = 9'd41;  3'd2: fall_q = 9'd92;  3'd3: fall_q = 9'd164;
        default: fall_q = 9'd256;
    endcase
endfunction
// pixel nel rettangolo w x h con l'angolo in (x0, y0), anche fuori schermo
function in_box(input signed [10:0] x0, input signed [10:0] y0, input [6:0] w, input [6:0] h);
    reg signed [11:0] ddx, ddy;
    begin
        ddx = $signed({2'b0, x}) - x0;
        ddy = $signed({2'b0, y}) - y0;
        in_box = ddx >= 0 && ddx < $signed({5'd0, w}) && ddy >= 0 && ddy < $signed({5'd0, h});
    end
endfunction

// continue: y della pallina (parabola di 60 frame, alta 30 pixel: s (60 - s) * 17 / 512) e GAME OVER
// che si scrive (una lettera ogni 5 frame dal 12, cursore) e si chiude (dal frame 158)
localparam integer CONT_Y = 84;                  // continue: riga della cifra
// la cifra con il font dei punteggi (come sul PC e sul C64), a scala 2: l'inchiostro è largo 11
// pixel nella cella da 22, quindi 22 x 44 centrati
localparam integer CONT_INK = 11, CONT_X0 = W / 2 - CONT_INK, CONT_H = 2 * SCORE_H;
localparam integer CONT_W = 2 * CONT_INK;
reg [21:0] cont_row;
localparam integer CL_X = 80, CL_V = 184;        // livello superato: etichette e numeri
reg signed [10:0] cont_ball_y;
reg [6:0]  go_cols;
reg        go_cur, go_close, go_close_line, go_close_dot, go_close_black;
reg signed [10:0] go_cur_x;
reg [6:0]  go_close_w, go_close_h;
reg [11:0] cb_m;
reg [7:0]  go_a;
reg [3:0]  go_n;
always @(posedge clk) begin
    cb_m = {6'd0, cont_sub} * (12'd60 - {6'd0, cont_sub});
    cont_ball_y <= CONT_Y + CONT_H - 6 - ((cb_m * 17) >> 9);
    go_a = intro_age - 8'd12;
    go_n = (intro_age < 8'd12) ? 4'd0 : (go_a >= 8'd40) ? GAME_OVER_LETTERS : ((go_a * 13) >> 6) + 4'd1;
    go_cols <= (go_n == 4'd0) ? 7'd0 : game_over_l1(go_n - 4'd1);
    go_cur_x <= (W - GO_WB) / 2 + (((go_n == 4'd0) ? 7'd0 : game_over_l1(go_n - 4'd1)) << BIG_SH) + 2;
    go_cur <= intro_age >= 8'd12 && (go_n < GAME_OVER_LETTERS || intro_age[4]);
    go_close <= intro_age >= 8'd158;
    go_close_line <= intro_age >= 8'd166 && intro_age < 8'd174;
    go_close_dot <= intro_age >= 8'd174 && intro_age < 8'd180;
    go_close_black <= intro_age >= 8'd180;     // poi nero fino alla fine (AT_GAME_OVER_BLACK, pong_top)
    go_close_h <= (intro_age >= 8'd165) ? 7'd1 : 7'd120 - 7'd15 * (intro_age[6:0] - 7'd30);   // 158 = 128 + 30
    go_close_w <= (intro_age >= 8'd173) ? 7'd1 : 7'd127 - 7'd16 * (intro_age[6:0] - 7'd38);   // 166 = 128 + 38
end

reg        i_title, i_name, i_nacc, i_ground, i_gline, i_ghost, i_tag, i_first, i_net, i_ball, i_dust, i_wflash;
reg [2:0]  i_lad, i_cap, i_cinv, i_cname, i_trail, i_shot;
reg [3:0]  i_son, i_lmin, i_lmax;     // lettere del nome accese: da i_lmin a i_lmax escluso (BLASTER)
reg [6:0]  i_tcols;
reg signed [10:0] i_ndx, i_ndy, i_gdx, i_tdx, i_bx, i_by, i_netx, i_wx;
reg signed [2:0]  i_shear;
reg signed [10:0] i_cdx [0:2];
reg signed [10:0] i_cdy [0:2];
reg signed [10:0] i_sx [0:3];
reg signed [10:0] i_sy [0:3];
reg signed [10:0] i_tx [0:2];
reg signed [10:0] i_shx [0:2];
reg signed [10:0] i_shy [0:2];
reg signed [10:0] i_ux [0:3];
reg signed [10:0] i_uy [0:3];
reg [7:0]  i_lshow;
reg signed [10:0] i_ldy [0:7];
reg [4:0]  i_wall;
reg signed [10:0] i_wy [0:4];

reg [7:0]  ts, tt;
reg [3:0]  tn;
reg signed [15:0] tm, td, tv, tw;
reg signed [10:0] tx0;
integer    c, q;

// motto scritto da t0, una lettera (8 pixel) per frame
task tag_from(input [7:0] t0);
    begin
        i_tag <= intro_age >= t0;
        tt = intro_age - t0;
        i_tcols <= (tt >= 8'd16) ? 7'd127 : {tt[3:0], 3'b0};
    end
endtask
// capsule che arrivano dalla metà campo dell'avversario (da 180 pixel dal centro), una ogni gap frame
// da t0, a sp pixel per frame; arrivate si accendono in negativo per 4 frame e mostrano il nome
task caps_slide(input [7:0] t0, input [7:0] gap, input [5:0] sp);
    for (c = 0; c < 3; c = c + 1) begin
        ts = t0 + gap * c;
        tv = side ? 16'sd100 + 16'sd80 * c : 16'sd260 - 16'sd80 * c;       // strada fino al posto
        tm = $signed({8'd0, intro_age - ts}) * $signed({10'd0, sp});
        if (intro_age < ts) begin
            i_cap[c] <= 1'b0;
            i_cname[c] <= 1'b0;
        end else if (tm < tv) begin
            i_cdx[c] <= side ? -(tv - tm) : (tv - tm);
            i_cname[c] <= 1'b0;
        end else
            i_cinv[c] <= tm < tv + ($signed({10'd0, sp}) <<< 2);
    end
endtask
// capsule che compaiono al loro posto in negativo, una ogni gap frame da t0
task caps_pop(input [7:0] t0, input [7:0] gap);
    for (c = 0; c < 3; c = c + 1) begin
        ts = t0 + gap * c;
        i_cap[c] <= intro_age >= ts;
        i_cname[c] <= intro_age >= ts;
        i_cinv[c] <= intro_age >= ts && intro_age < ts + 8'd4;
    end
endtask

always @(posedge clk) begin
    // stato finale, tutto fermo; ogni avversario cambia quello che anima
    i_title <= intro_age >= 8'd14 && (level != 3'd6 || !intro_age[3]);
    i_lad <= (intro_age >= 8'd12) ? 3'd7 : intro_age[3:1] + 3'd1;
    i_name <= 1'b1;
    i_ndx <= 11'sd0;
    i_ndy <= 11'sd0;
    i_nacc <= 1'b0;
    i_lmin <= 4'd0;
    i_lmax <= 4'd8;
    i_shear <= 3'sd0;
    i_ground <= 1'b0;
    i_gline <= 1'b0;
    i_ghost <= 1'b0;
    i_gdx <= 11'sd0;
    i_lshow <= 8'hFF;
    for (q = 0; q < 8; q = q + 1) i_ldy[q] <= 11'sd0;
    i_tag <= 1'b1;
    i_tcols <= 7'd127;
    i_tdx <= 11'sd0;
    i_cap <= 3'b111;
    i_cinv <= 3'b000;
    i_cname <= 3'b111;
    for (q = 0; q < 3; q = q + 1) begin
        i_cdx[q] <= 11'sd0;
        i_cdy[q] <= 11'sd0;
    end
    i_first <= 1'b1;
    i_net <= 1'b0;
    i_son <= 4'd0;
    i_ball <= 1'b0;
    i_trail <= 3'd0;
    i_shot <= 3'd0;
    i_dust <= 1'b0;
    i_wall <= 5'd0;
    i_wflash <= 1'b0;
    case (kind)
        K_ARCADE: begin
            // una raffica di capsule dalla mezzeria (a 120 pixel dal centro, dalla parte del
            // giocatore), 20 frame di volo ciascuna, una ogni 6 frame: quattro posti bastano
            i_net <= intro_age >= 8'd6 && intro_age < 8'd84;
            i_netx <= ax(-11'sd120);
            for (q = 0; q < 10; q = q + 1) begin
                ts = 8'd10 + 8'd6 * q;
                if (intro_age >= ts && intro_age < ts + 8'd20) begin
                    i_son[q % 4] <= 1'b1;
                    tv = $signed({8'd0, intro_age - ts}) * 16'sd6;
                    i_sx[q % 4] <= ax(-11'sd120 + tv[10:0]) - 11'sd4;
                    i_sy[q % 4] <= IP_Y + arcade_dy(q) - 4;
                end
            end
            // il nome lampeggia come INSERT COIN, poi i bonus escono dalla racchetta
            tt = intro_age - 8'd84;
            i_name <= intro_age >= 8'd84 && (intro_age >= 8'd108 || !tt[2]);
            tag_from(8'd100);
            for (c = 0; c < 3; c = c + 1) begin
                ts = 8'd120 + 8'd8 * c;
                tt = (intro_age < ts) ? 8'd0 : (intro_age - ts >= 8'd8) ? 8'd8 : intro_age - ts;
                i_cap[c] <= intro_age >= ts;
                i_cdx[c] <= ((11'sd80 - 11'sd80 * c) * $signed({7'd0, 4'd8 - tt[3:0]})) >>> 3;
                i_cdy[c] <= ($signed(IP_Y - 6 - INTRO_CAP_Y) * $signed({7'd0, 4'd8 - tt[3:0]})) >>> 3;
                i_cinv[c] <= intro_age >= ts + 8'd8 && intro_age < ts + 8'd12;
                i_cname[c] <= intro_age >= ts + 8'd8;
            end
            i_first <= intro_age >= 8'd160;
        end
        K_TWIST: begin
            // la palla arriva e la racchetta inclinata la ribatte di sbieco, verso l'alto
            if (intro_age >= 8'd14 && intro_age < 8'd30) begin
                i_ball <= 1'b1;
                i_bx <= ax(-11'sd160 + $signed({3'd0, intro_age - 8'd14}) * 10) - 11'sd2;
                i_by <= IP_Y + 9;
            end else if (intro_age >= 8'd30 && intro_age < 8'd55) begin
                tt = intro_age - 8'd30;
                i_ball <= 1'b1;
                i_bx <= ax(-11'sd8 - $signed({3'd0, tt}) * 7) - 11'sd2;
                i_by <= IP_Y + 9 - $signed({3'd0, tt}) * 4;
            end
            i_name <= intro_age >= 8'd66;
            tt = intro_age - 8'd66;
            i_shear <= (intro_age >= 8'd66 && tt < 8'd24) ? twist_shear(tt[4:0]) : 3'sd0;
            tag_from(8'd92);
            caps_slide(8'd112, 8'd12, 6'd30);
            i_first <= intro_age >= 8'd160;
        end
        K_HAMMER: begin
            // la palla arriva piano, il martello la ribatte fortissimo con la scia
            if (intro_age >= 8'd12 && intro_age < 8'd49) begin
                i_ball <= 1'b1;
                i_bx <= ax(-11'sd10 - $signed({3'd0, 8'd49 - intro_age}) * 4) - 11'sd2;
                i_by <= IP_Y - 2;
            end else if (intro_age >= 8'd49 && intro_age < 8'd59) begin
                tv = -16'sd10 - $signed({8'd0, intro_age - 8'd49}) * 20;
                i_ball <= 1'b1;
                i_bx <= ax(tv[10:0]) - 11'sd2;
                i_by <= IP_Y - 2;
                i_trail <= 3'b111;
                for (q = 0; q < 3; q = q + 1) i_tx[q] <= ax(tv[10:0] + 11'sd8 * (q + 1)) - 11'sd2;
            end
            // il nome cade come un peso (1,3 d^2 pixel sopra) e alza la polvere
            i_name <= intro_age >= 8'd62;
            tt = 8'd72 - intro_age;
            tm = $signed({8'd0, tt}) * $signed({8'd0, tt});
            i_ndy <= (intro_age < 8'd72) ? -(tm + ((tm * 5) >>> 4)) : 16'sd0;
            if (intro_age >= 8'd72 && intro_age < 8'd82) begin
                tt = intro_age - 8'd72;
                tv = $signed({8'd0, tt});
                tm = (tv * tv * 13) >>> 5;
                tw = $signed({9'd0, tl_name_w(K_HAMMER)});
                i_dust <= 1'b1;
                i_ux[0] <= W / 2 - (tw >>> 1) - 5 - tv * 3;
                i_ux[1] <= W / 2 + (tw >>> 1) + 3 + tv * 3;
                i_ux[2] <= W / 2 - (tw >>> 1) - 5 - tv * 5;
                i_ux[3] <= W / 2 + (tw >>> 1) + 3 + tv * 5;
                i_uy[0] <= NAME_BASE - 1 - ((tv * 5) >>> 1) + tm;
                i_uy[1] <= NAME_BASE - 1 - ((tv * 5) >>> 1) + tm;
                i_uy[2] <= NAME_BASE - 1 - ((tv * 3) >>> 1) + tm;
                i_uy[3] <= NAME_BASE - 1 - ((tv * 3) >>> 1) + tm;
            end
            tag_from(8'd88);
            // le capsule cadono pesanti
            for (c = 0; c < 3; c = c + 1) begin
                ts = 8'd106 + 8'd10 * c;
                tt = intro_age - ts;
                tv = 16'sd8 - $signed({8'd0, tt});
                i_cap[c] <= intro_age >= ts;
                i_cdy[c] <= (intro_age >= ts && tt < 8'd8) ? -(tv * tv * 3) : 16'sd0;
                i_cinv[c] <= intro_age >= ts && tt >= 8'd8 && tt < 8'd11;
                i_cname[c] <= intro_age >= ts && tt >= 8'd8;
            end
            i_first <= intro_age >= 8'd150;
        end
        K_TITAN: begin
            // il nome sale da sotto il pavimento, un pixel per frame (26 frame, alto 26)
            i_name <= intro_age >= 8'd84;
            tt = intro_age - 8'd84;
            i_ndy <= (intro_age < 8'd84 || tt >= 8'd26) ? 11'sd0 : 11'sd26 - $signed({3'd0, tt});
            i_ground <= 1'b1;
            i_gline <= intro_age >= 8'd84 && intro_age < 8'd112;
            // il motto si scrive piano: una lettera (8 pixel) ogni 3 frame
            i_tag <= intro_age >= 8'd114;
            tm = ($signed({8'd0, intro_age - 8'd114}) * 85) >>> 5;
            i_tcols <= (intro_age - 8'd114 >= 8'd48) ? 7'd127 : tm[6:0];
            caps_slide(8'd156, 8'd12, 6'd8);
            i_first <= intro_age >= 8'd214;
        end
        K_BLASTER: begin
            // ogni colpo accende una lettera del nome, dalla più vicina alla racchetta (bocca a 112
            // pixel verso l'avversario, colpi a 20 pixel per frame, uno ogni 5 frame dal 12)
            tn = 4'd0;
            tx0 = (W - tl_name_w(K_BLASTER)) / 2;
            for (q = 0; q < 7; q = q + 1) begin
                // centro della lettera j (contata da sinistra) a metà altezza e distanza dalla bocca
                tv = side ? q : 6 - q;
                td = tx0 + TL_BLASTER_CX0 + TL_BLASTER_STEP * tv;
                td = ax(11'sd112) - td;
                td = (td < 0) ? -td : td;
                ts = 8'd12 + 8'd5 * q;
                tm = $signed({8'd0, intro_age - ts}) * 20;
                if (intro_age >= ts && tm >= td) tn = tn + 4'd1;
                if (intro_age >= ts && tm < td) begin
                    i_shot[q % 3] <= 1'b1;
                    i_shx[q % 3] <= ax(11'sd112 - tm[10:0]) - 11'sd3;
                    i_shy[q % 3] <= NAME_BASE - 7;
                end
            end
            // accese le tn lettere più vicine alla racchetta (a destra, o a sinistra con side)
            i_lmin <= side ? 4'd0 : 4'd7 - tn;
            i_lmax <= side ? tn : 4'd8;
            tag_from(8'd56);
            // poi, sceso all'altezza delle capsule (dal frame 76), le colpisce al volo: arrivano
            // dalla parte del giocatore e il colpo, dalla bocca, le ferma al loro posto
            for (c = 0; c < 3; c = c + 1) begin
                ts = 8'd96 + 8'd14 * c;
                if (intro_age < ts) begin
                    tv = $signed({8'd0, ts - intro_age}) * 10;
                    i_cdx[c] <= side ? tv : -tv;
                    i_cap[c] <= tv < 16'sd200;
                    i_cname[c] <= 1'b0;
                    tm = 16'sd10 + $signed({8'd0, ts - intro_age}) * 20;          // colpo, dal posto
                    tw = side ? 16'sd112 + 16'sd80 * (c - 1) : 16'sd112 - 16'sd80 * (c - 1);   // posto-bocca
                    if (intro_age >= 8'd76 && tm <= tw) begin
                        i_shot[c] <= 1'b1;
                        i_shx[c] <= W / 2 - 80 + 80 * c + (side ? -tm : tm) - 3;
                        i_shy[c] <= INTRO_CAP_Y + 6;
                    end
                end else
                    i_cinv[c] <= intro_age < ts + 8'd4;
            end
            i_first <= intro_age >= 8'd150;
        end
        K_RUSH: begin
            // nome, motto e capsule entrano con uno scatto, come la racchetta; il nome con
            // un'immagine gialla dietro
            tt = intro_age - 8'd30;
            tv = (tt == 8'd0) ? 16'sd127 : (tt == 8'd1) ? 16'sd85 : (tt == 8'd2) ? 16'sd42 : 16'sd0;
            i_name <= intro_age >= 8'd30;
            i_ndx <= side ? -tv : tv;
            i_ghost <= intro_age >= 8'd30 && tt < 8'd12;
            i_gdx <= side ? -((16'sd170 + tv) >>> 1) : ((16'sd170 + tv) >>> 1);
            i_nacc <= intro_age >= 8'd34 && intro_age < 8'd36;
            tt = intro_age - 8'd44;
            tv = (tt == 8'd0) ? 16'sd113 : (tt == 8'd1) ? 16'sd57 : 16'sd0;
            i_tag <= intro_age >= 8'd44;
            i_tdx <= side ? -tv : tv;
            for (c = 0; c < 3; c = c + 1) begin
                ts = 8'd58 + 8'd6 * c;
                tt = intro_age - ts;
                tm = side ? 16'sd100 + 16'sd80 * c : 16'sd260 - 16'sd80 * c;
                tv = (tt == 8'd0) ? (tm * 21) >>> 5 : (tt == 8'd1) ? (tm * 11) >>> 5 : 16'sd0;
                i_cap[c] <= intro_age >= ts;
                i_cdx[c] <= side ? -tv : tv;
                i_cinv[c] <= intro_age >= ts && tt >= 8'd3 && tt < 8'd5;
                i_cname[c] <= intro_age >= ts && tt >= 8'd3;
            end
            i_first <= intro_age >= 8'd90;
        end
        K_GUARDIAN: begin
            // i cinque pezzi del muro cadono uno sull'altro, dal basso
            i_wx <= ax(11'sd18);
            for (q = 0; q < 5; q = q + 1) begin
                ts = 8'd10 + 8'd8 * q;
                tt = intro_age - ts;
                tv = WALL_TOP + 14 * (4 - q);
                i_wall[4 - q] <= intro_age >= ts;
                i_wy[4 - q] <= (intro_age >= ts && tt < 8'd5) ?
                               -16'sd15 + (((tv + 16'sd15) * $signed({7'd0, fall_q(tt[2:0])})) >>> 8) : tv;
            end
            i_wflash <= intro_age >= 8'd82 && intro_age < 8'd90 && !intro_age[1];
            // una palla passa sopra la racchetta e il muro la rimanda
            if (intro_age >= 8'd52 && intro_age < 8'd82) begin
                i_ball <= 1'b1;
                i_bx <= ax(-11'sd162 + $signed({3'd0, intro_age - 8'd52}) * 6) - 11'sd2;
                i_by <= WALL_TOP + 4;
            end else if (intro_age >= 8'd82 && intro_age < 8'd112) begin
                i_ball <= 1'b1;
                i_bx <= ax(11'sd16 - $signed({3'd0, intro_age - 8'd82}) * 6) - 11'sd2;
                i_by <= WALL_TOP + 4;
            end
            // il nome si posa lettera per lettera, come i mattoni, da 157 pixel sopra (79 / 128: a 16 bit
            // 157 * 256 non ci sta)
            for (q = 0; q < 8; q = q + 1) begin
                ts = 8'd96 + 8'd3 * q;
                tt = intro_age - ts;
                i_lshow[q] <= intro_age >= ts;
                i_ldy[q] <= (intro_age >= ts && tt < 8'd5) ?
                            -((16'sd79 * (16'sd256 - $signed({7'd0, fall_q(tt[2:0])}))) >>> 7) : 16'sd0;
            end
            tag_from(8'd130);
            caps_pop(8'd152, 8'd10);
            i_first <= intro_age >= 8'd190;
        end
        default: ;
    endcase
end

// grafica del nome (pong_titles.vh): posto (con gli spostamenti dell'entrata), misure, indirizzo nella
// ROM, inizio delle lettere; anche questi fermi durante il frame
reg signed [10:0] i_nx, i_ny, i_gx;
reg [7:0]  i_gy, i_tagy;
reg [6:0]  i_nw;
reg [4:0]  i_nh;
reg [TL_CH_ABITS-1:0] i_nbase;
reg        i_nsh7, i_slant, i_lfall;
reg [6:0]  i_lx [1:7];
integer    lq;
always @(posedge clk) begin
    i_nw <= tl_name_w(kind);
    i_nh <= tl_name_h(kind);
    i_nbase <= tl_name_base(kind);
    i_nsh7 <= tl_name_sh7(kind);
    i_nx <= (W - tl_name_w(kind)) / 2 + i_ndx;
    i_gx <= (W - tl_name_w(kind)) / 2 + i_gdx;
    i_ny <= $signed({3'd0, name_top(kind)}) + i_ndy;
    i_gy <= name_top(kind);
    i_tagy <= tag_y(kind);
    i_slant <= kind == K_BLASTER;
    i_lfall <= kind == K_GUARDIAN;
    for (lq = 1; lq < 8; lq = lq + 1) i_lx[lq] <= tl_letter_x(kind, lq[2:0]);
end

// scritta centrata
`define CENTER1(lit, w, y0) lit(x - (W - (w)) / 2, y - (y0))

// ------------------------------------------------ classifica animata (schermata 5)
// Come Scores::draw di rust/game/src/challenge_ui.rs, con intro_age che conta i frame della schermata:
// la palla parte sopra la prima riga e scende di 1,25 pixel per frame (sc_ball_y) rimbalzando fra
// x = 32 e 288 a 4 pixel per frame (sc_ball_x), con una scia; le righe che ha già toccato si accendono
// e le cifre dei punti girano come un contatore (sc_roll) e si fermano una alla volta da sinistra, una
// ogni SC_LOCK_STEP pixel di discesa dopo i primi SC_LOCK0: grigie mentre girano, poi bianche (gialle
// per il posto appena inserito). Su PC i punti contano davvero; qui servirebbero una moltiplicazione e
// una conversione in decimale per riga. Dal frame SC_MARK due racchette gialle arrivano dai bordi ai
// lati del posto nuovo e, nella prima metà di ogni secondo (blink), un riflesso bianco lo attraversa.
localparam [7:0] SC_MARK = 8'd190;
localparam integer SC_LOCK0 = 8, SC_LOCK_STEP = 6, SC_DONE = SC_LOCK0 + 7 * SC_LOCK_STEP, SC_BOTTOM = 206;
reg [3:0]  sc_roll = 4'd0;              // cifra che gira, avanza a ogni frame
reg [7:0]  sc_age_q = 8'd0;
always @(posedge clk) begin
    sc_age_q <= intro_age;
    if (intro_age != sc_age_q) sc_roll <= (sc_roll == 4'd9) ? 4'd0 : sc_roll + 4'd1;
end
function [9:0] sc_ball_y(input [7:0] f);
    sc_ball_y = 10'd30 + {2'd0, f} + {4'd0, f[7:2]};
endfunction
function [9:0] sc_ball_x(input [7:0] f);
    reg [8:0] p;
    begin
        p = {f[6:0], 2'b0};
        sc_ball_x = 10'd32 + (p[8] ? {2'd0, ~p[7:0]} : {2'd0, p[7:0]});
    end
endfunction
reg  signed [10:0] sc_lit;              // pixel di discesa della palla oltre la riga del pixel
reg  signed [10:0] sc_pl, sc_pr;        // x delle racchette ai lati del posto nuovo
reg  [9:0]  sc_row_y;
reg  [3:0]  ri, hl_row;                 // classifica: posto della riga mostrata, riga del posto nuovo
reg  [27:0] sc_bcd;
reg  [3:0]  sc_rc, sc_lc;               // colori della riga e del livello
reg  [4:0]  sc_t;
reg         sc_glint;
reg  [7:0]  sc_k;
integer     sk;

always @(*) begin
    col = BLACK;
    on = 1'b0;
    g_on = 1'b0;
    sc_lit = 11'sd0;
    sc_pl = 11'sd0;
    sc_pr = 11'sd0;
    sc_row_y = 10'd0;
    ri = 4'd0;
    hl_row = 4'd0;
    sc_bcd = 28'd0;
    sc_rc = WHITE;
    sc_lc = GRAY;
    sc_t = 5'd0;
    sc_glint = 1'b0;
    sc_k = 8'd0;
    g_code = 6'd0;
    g_dx = 10'd0;
    g_dy = 10'd0;
    g_col = WHITE;
    row = 4'd0;
    b_sel = 3'd0;
    b_cx = 10'd0;
    b_dx = 10'd0;
    b_dy = 10'd0;
    first_x = 10'd0;
    pts = 5'd0;
    pts_tens = 2'd0;
    pts_units = 5'd0;
    hud_x = 10'd0;
    n_row = 11'sd0;
    n_x0 = 11'sd0;
    n_u = 11'sd0;
    n_us = 11'sd0;
    n_v = 11'sd0;
    n_li = 3'd0;
    n_ok = 1'b0;
    g_u = 11'sd0;
    g_v = 11'sd0;
    g_ok = 1'b0;
    ta_addr = {TL_CH_ABITS{1'b0}};
    tb_addr = {TL_CH_ABITS{1'b0}};
    ta_ok = 1'b0;
    under = BLACK;
    c_lit = 1'b0;
    case (screen)
        3'd1: begin   // ------------------------------------------------ presentazione
            on = 1'b1;
            // titolo: LEVEL n OF 7 (FINAL LEVEL), nell'allenamento TRAINING come su PC e C64
            if (i_title && (train ? `CENTER1(ch_train_lit, CH_TRAIN_W, INTRO_TITLE_Y)
                                  : ch_intro_lit(level, x - (W - ch_intro_w(level)) / 2, y - INTRO_TITLE_Y)))
                col = ACCENT;
            // la scala dei livelli
            for (j = 0; j < 7; j = j + 1)
                if (j < i_lad && in_box(LADDER_X + 24 * j, LADDER_Y, 7'd16, 7'd4))
                    col = (j < level && !train) ? WHITE : (j == level && !intro_age[3]) ? ACCENT : DIM;
            // nome: spostato, inclinato per riga (TWIST), a colonne (BLASTER), sotto il pavimento
            // (TITAN), lettera per lettera (GUARDIAN); RUSH ha un'immagine gialla dietro
            // (la grafica dalla ROM: qui solo indirizzo e riquadro, il colore al ciclo dopo)
            n_row = $signed({2'b0, y}) - i_ny;
            n_x0 = i_nx + twist_dx(i_shear, n_row - 11'sd10);
            n_u = $signed({2'b0, x}) - n_x0;
            n_us = n_u - (i_slant ? $signed({8'd0, tl_blaster_slant(n_row[4:0])}) : 11'sd0);
            n_li = (n_us >= $signed({4'd0, i_lx[1]})) + (n_us >= $signed({4'd0, i_lx[2]})) +
                   (n_us >= $signed({4'd0, i_lx[3]})) + (n_us >= $signed({4'd0, i_lx[4]})) +
                   (n_us >= $signed({4'd0, i_lx[5]})) + (n_us >= $signed({4'd0, i_lx[6]})) +
                   (n_us >= $signed({4'd0, i_lx[7]}));
            n_v = n_row - (i_lfall ? i_ldy[n_li] : 11'sd0);
            n_ok = i_name && n_u >= 0 && n_u < $signed({4'd0, i_nw}) && n_v >= 0 && n_v < $signed({6'd0, i_nh}) &&
                   {1'b0, n_li} >= i_lmin && {1'b0, n_li} < i_lmax && (!i_lfall || i_lshow[n_li]) &&
                   !(i_ground && y >= NAME_GROUND);
            ta_addr = i_nbase + (i_nsh7 ? {n_v[4:0], n_u[6:0]} : {2'b0, n_v[4:0], n_u[5:0]});
            ta_ok = n_ok;
            g_u = $signed({2'b0, x}) - i_gx;
            g_v = $signed({2'b0, y}) - $signed({3'd0, i_gy});
            g_ok = i_ghost && g_u >= 0 && g_u < $signed({4'd0, i_nw}) && g_v >= 0 && g_v < $signed({6'd0, i_nh});
            tb_addr = i_nbase + (i_nsh7 ? {g_v[4:0], g_u[6:0]} : {2'b0, g_v[4:0], g_u[5:0]});
            if (n_ok || g_ok) begin
                under = col;
                col = MARK;
            end
            if (i_gline && y == NAME_GROUND && in_box(W / 2 - i_nw / 2 - 8, NAME_GROUND, i_nw + 7'd16, 7'd1))
                col = DIM;
            // motto: scritto a colonne, o spostato (RUSH)
            if (i_tag && tag_lit(kind, x - ((W - tag_w(kind)) / 2 + i_tdx), y - i_tagy) &&
                x - ((W - tag_w(kind)) / 2 + i_tdx) < i_tcols)
                col = GRAY;
            // i bonus dell'avversario su tre colonne (centri a 80, 160 e 240): capsula con l'icona di
            // pong_next.vh, spostata o in negativo; il nome sotto, al suo posto
            for (j = 0; j < 3; j = j + 1)
                if (i_cap[j] && in_box(W / 2 - 86 + 80 * j + i_cdx[j], INTRO_CAP_Y + i_cdy[j], INTRO_CAP, INTRO_CAP)) begin
                    b_dx = x - (W / 2 - 86 + 80 * j + i_cdx[j]);
                    b_dy = y - (INTRO_CAP_Y + i_cdy[j]);
                    c_lit = icon_lit(loadout[3 * j +: 3], b_dx - (INTRO_CAP - 9) / 2, b_dy - (INTRO_CAP - 9) / 2);
                    if (i_cinv[j]) col = c_lit ? BLACK : ACCENT;
                    else if (c_lit || b_dx == 0 || b_dy == 0 || b_dx == INTRO_CAP - 1 || b_dy == INTRO_CAP - 1)
                        col = ACCENT;
                end
            if (x < 10'd120) begin
                b_sel = loadout[2:0];
                b_cx = 10'd80;
            end else if (x < 10'd200) begin
                b_sel = loadout[5:3];
                b_cx = 10'd160;
            end else begin
                b_sel = loadout[8:6];
                b_cx = 10'd240;
            end
            if (i_cname[(x < 10'd120) ? 0 : (x < 10'd200) ? 1 : 2] &&
                name_lit(b_sel, x - (b_cx - name_w(b_sel) / 2), y - (INTRO_CAP_Y + INTRO_CAP + 3))) col = ACCENT;
            // FIRST TO n: n da rung_points, una o due cifre del font a celle dopo la scritta
            pts = rung_points(level);
            pts_tens = (pts >= 5'd30) ? 2'd3 : (pts >= 5'd20) ? 2'd2 : (pts >= 5'd10) ? 2'd1 : 2'd0;
            pts_units = pts - {pts_tens, 3'd0} - {pts_tens, 1'b0};
            first_x = (pts_tens != 2'd0) ? FIRST_X2 : FIRST_X1;
            if (i_first) begin
                if (ch_first_lit(x - first_x, y - INTRO_FIRST_Y)) col = GRAY;
                if (pts_tens != 2'd0) begin
                    put(first_x + CH_FIRST_W + 1 + C, INTRO_FIRST_Y, {4'd0, pts_tens}, 2'd0, GRAY);
                    put(first_x + CH_FIRST_W + 1 + 2 * C, INTRO_FIRST_Y, {1'b0, pts_units}, 2'd0, GRAY);
                end else
                    put(first_x + CH_FIRST_W + 1 + C, INTRO_FIRST_Y, {1'b0, pts_units}, 2'd0, GRAY);
            end
            // il resto delle entrate: mezzeria e raffica (ARCADE), palla e scia, colpi (BLASTER),
            // polvere (HAMMER), muro a settori (GUARDIAN)
            if (i_net && (x == i_netx || x == i_netx + 1) && y >= IP_Y - 28 && y < IP_Y + 32 && net_dash(y))
                col = WHITE;
            for (j = 0; j < 4; j = j + 1)
                if (i_son[j] && in_box(i_sx[j], i_sy[j], 7'd8, 7'd8) && !in_box(i_sx[j] + 1, i_sy[j] + 1, 7'd6, 7'd6))
                    col = ACCENT;
            for (j = 0; j < 3; j = j + 1)
                if (i_trail[j] && in_box(i_tx[j], i_by, 7'd4, 7'd4))
                    col = (j == 0) ? TRAIL1 : (j == 1) ? TRAIL2 : TRAIL3;
            if (i_ball && in_box(i_bx, i_by, 7'd4, 7'd4)) col = WHITE;
            for (j = 0; j < 3; j = j + 1)
                if (i_shot[j] && (in_box(i_shx[j], i_shy[j] - 4, 7'd6, 7'd1) || in_box(i_shx[j], i_shy[j] + 3, 7'd6, 7'd1)))
                    col = ACCENT;
            for (j = 0; j < 4; j = j + 1)
                if (i_dust && in_box(i_ux[j], i_uy[j], 7'd2, 7'd2)) col = GRAY;
            for (j = 0; j < 5; j = j + 1)
                if (i_wall[j] && in_box(i_wx, i_wy[j], 7'd2, 7'd12) && !in_box(i_wx, i_wy[j] + 3, 7'd2, 7'd1) &&
                    !in_box(i_wx, i_wy[j] + 7, 7'd2, 7'd1) && !in_box(i_wx, i_wy[j] + 11, 7'd2, 7'd1))
                    col = (j == 0 && i_wflash) ? WHITE : ACCENT;
            if (!train) begin
                if (ch_score_lit(x - 24, y - 216)) col = WHITE;
                digits7(10'd24 + CH_SCORE_W + 1 + C, 10'd216, score_bcd, WHITE);
                if (ch_hi_lit(x - 192, y - 216)) col = WHITE;
                digits7(10'd192 + CH_HI_W + 1 + C, 10'd216, hi_bcd, WHITE);
            end
            // sfidante: invito lampeggiante dal lato libero (P2 con il campione a sinistra)
            if (join_prompt && blink < 6'd30) begin
                if (coin_prompt) begin
                    if (ch_coin_lit(x - (side ? COIN_XL : COIN_XR), y - JOIN_Y)) col = WHITE;
                end else begin
                    put(side ? JOIN_XL : JOIN_XR, JOIN_Y, G_P, 2'd0, WHITE);
                    put((side ? JOIN_XL : JOIN_XR) + C, JOIN_Y, side ? 6'd1 : 6'd2, 2'd0, WHITE);
                    if (ch_press_lit(x - ((side ? JOIN_XL : JOIN_XR) + 3 * C), y - JOIN_Y)) col = WHITE;
                end
            end
        end
        3'd2: begin   // ---------------------------------------------- livello superato
            on = 1'b1;
            if (ch_clear_lit(level, x - (W - ch_clear_w(level)) / 2, y - 44)) col = ACCENT;
            if (level == CH_LEVELS - 1 && `CENTER1(ch_beat_lit, CH_BEAT_W, 72)) col = WHITE;
            // etichette da CL_X, numeri da CL_V (il "+" una cella prima)
            if (ch_win_lit(x - CL_X, y - 100)) col = WHITE;
            // +1000 x livello: cifre "n000"
            put(CL_V - C, 10'd100, G_PLUS, 2'd0, WHITE);
            for (j = 0; j < 4; j = j + 1)
                put(CL_V + C * j, 10'd100, (j == 0) ? {3'd0, level} + 6'd1 : 6'd0, 2'd0, WHITE);
            if (perfect) begin
                if (ch_perfect_lit(x - CL_X, y - 120)) col = ACCENT;
                // +2000 x livello
                put(CL_V - C, 10'd120, G_PLUS, 2'd0, ACCENT);
                if (level >= 3'd4) begin
                    put(CL_V, 10'd120, 6'd1, 2'd0, ACCENT);
                    put(CL_V + C, 10'd120, {2'd0, ({level, 1'b0} + 4'd2) - 4'd10}, 2'd0, ACCENT);
                end else
                    put(CL_V, 10'd120, {2'd0, {level, 1'b0} + 4'd2}, 2'd0, ACCENT);
                for (j = 0; j < 3; j = j + 1)
                    put(CL_V + C * (j + (level >= 3'd4 ? 2 : 1)), 10'd120, 6'd0, 2'd0, ACCENT);
            end
            if (ch_score_lit(x - CL_X, y - 150)) col = WHITE;
            digits7(CL_V, 10'd150, score_bcd, WHITE);
            if (`CENTER1(ch_press_lit, CH_PRESS_W, 200)) col = GRAY;
        end
        3'd3: begin   // ------------------------------------------------------ continue
            on = 1'b1;
            if (cont_over) begin
                // continue scaduto: GAME OVER al centro, come quello sopra la partita ma senza campo
                // da spegnere: si scrive subito con il cursore, poi lo schermo si chiude come un
                // televisore (come OV_TYPE e OV_OFF di pong_render; intro_age conta i frame del GAME OVER)
                if (game_over_lit((x - (W - GO_WB) / 2) >> BIG_SH, (y - AT_GAME_OVER_Y) >> BIG_SH) &&
                    (x - (W - GO_WB) / 2) >> BIG_SH < go_cols)
                    col = WHITE;
                if (go_cur && in_box(go_cur_x, AT_GAME_OVER_Y, 4 << BIG_SH, BH)) col = WHITE;
                if (go_close && !go_close_black && (go_close_dot ? (x == W / 2 - 1 || x == W / 2) && (y == 119 || y == 120) :
                                 go_close_line ? (y == 119 || y == 120) && x >= W / 2 - go_close_w && x < W / 2 + go_close_w :
                                 (y == 120 - go_close_h || y == 119 + go_close_h)))
                    col = WHITE;
                else if (go_close && (go_close_black || go_close_dot || go_close_line || y < 120 - go_close_h || y > 119 + go_close_h))
                    col = BLACK;
            end else begin
                if (`CENTER1(ch_cont_lit, CH_CONT_W, 40)) col = ACCENT;
                // la cifra: font dei punteggi a scala 2
                if (span(x, CONT_X0, 11'd0, 2 * SCORE_W) && span(y, CONT_Y, 11'd0, CONT_H)) begin
                    cont_row = score_glyph(cont_digit, (y - CONT_Y) >> 1);
                    if (cont_row[SCORE_W - 1 - ((x - CONT_X0) >> 1)]) col = WHITE;
                end
                // pallina che rimbalza a destra del numero: tocca terra a ogni secondo, quando il
                // numero cambia; negli ultimi tre secondi diventa gialla
                if (in_box(W / 2 + CONT_W / 2 + 12, cont_ball_y, 7'd6, 7'd6)) col = (cont_digit <= 4'd2) ? ACCENT : WHITE;
                if (in_box(W / 2 + CONT_W / 2 + 9, CONT_Y + CONT_H, 7'd12, 7'd1)) col = GRAY;
                if (blink < 6'd30 &&
                    (coin_prompt ? `CENTER1(ch_coin_lit, CH_COIN_W, 160) : `CENTER1(ch_press_lit, CH_PRESS_W, 160)))
                    col = WHITE;
                if (`CENTER1(ch_reset_lit, CH_RESET_W, 190)) col = GRAY;
            end
        end
        3'd4: begin   // ------------------------------------------------------- iniziali
            on = 1'b1;
            if (`CENTER1(ch_record_lit, CH_RECORD_W, 28)) col = ACCENT;
            // SCORE 0000000 centrato (13 celle)
            if (ch_score_lit(x - (W - 13 * C) / 2, y - 66)) col = WHITE;
            digits7((W - 13 * C) / 2 + 6 * C, 10'd66, score_bcd, WHITE);
            if (`CENTER1(ch_enter_lit, CH_ENTER_W, 92)) col = GRAY;
            // le tre lettere, ogni 16 pixel
            for (i = 0; i < 3; i = i + 1) begin
                if (i < name_pos)
                    put(10'd160 - C / 2 + 16 * (i - 1), 10'd120, name[6 * i +: 6], 2'd0, WHITE);
                else if (i == name_pos) begin
                    if (blink < 6'd40) put(10'd160 - C / 2 + 16 * (i - 1), 10'd120, letter, 2'd0, ACCENT);
                end else
                    put(10'd160 - C / 2 + 16 * (i - 1), 10'd120, G_DOT, 2'd0, WHITE);
            end
            if (`CENTER1(ch_hint_lit, CH_HINT_W, 210)) col = GRAY;
        end
        3'd5: begin   // ----------------------------------------------------- classifica
            on = 1'b1;
            if (`CENTER1(ch_table_lit, CH_TABLE_W, 14)) col = ACCENT;
            // otto righe ogni TB_STEP pixel: si sceglie la riga, poi la cella. La classifica ha dieci
            // posti: se quello nuovo è il 9° o il 10°, l'ultima riga mostra lui (con il suo numero),
            // così chi ha appena scritto le iniziali si vede sempre (come nel gioco Rust)
            for (i = 0; i < 8; i = i + 1)
                if (y - (TB_Y0 + TB_STEP * i) < CH_GLYPH_H) row = i[3:0];
            ri = (row == 4'd7 && (highlight == 4'd8 || highlight == 4'd9)) ? highlight : row;
            hl_row = (highlight >= 4'd8) ? 4'd7 : highlight;
            // la palla, con la scia, finché non ha passato l'ultima riga (sotto le scritte)
            if (sc_ball_y(intro_age) < SC_BOTTOM) begin
                for (sk = 3; sk >= 0; sk = sk - 1) begin
                    sc_k = (intro_age >= 2 * sk) ? intro_age - 2 * sk : 8'd0;
                    if (in_box($signed({1'b0, sc_ball_x(sc_k)}), $signed({1'b0, sc_ball_y(sc_k)}), 7'd4, 7'd4))
                        col = (sk == 0) ? WHITE : (sk == 1) ? TRAIL1 : (sk == 2) ? TRAIL2 : TRAIL3;
                end
            end
            // racchette ai lati del posto nuovo, dai bordi (3 pixel per frame)
            if (highlight < 4'd10 && intro_age >= SC_MARK) begin
                sc_k = intro_age - SC_MARK;
                sc_pl = $signed({3'd0, sc_k}) * 3 - 11'sd4;
                sc_pr = 11'sd320 - $signed({3'd0, sc_k}) * 3;
                if (sc_pl > TB_X - 14) sc_pl = TB_X - 14;
                if (sc_pr < TB_X + TB_SPAN + 10) sc_pr = TB_X + TB_SPAN + 10;
                if (in_box(sc_pl, $signed({1'b0, TB_Y0 - 10'd4 + TB_STEP * hl_row}), 7'd4, 7'd15) ||
                    in_box(sc_pr, $signed({1'b0, TB_Y0 - 10'd4 + TB_STEP * hl_row}), 7'd4, 7'd15))
                    col = ACCENT;
            end
            if (y >= TB_Y0 && y < TB_Y0 + TB_STEP * 8) begin
                // la riga si accende quando la palla la tocca; le cifre girano e si fermano da sinistra
                sc_row_y = TB_Y0 + TB_STEP * row;
                sc_lit = $signed({1'b0, sc_ball_y(intro_age)}) - $signed({1'b0, sc_row_y}) - 11'sd3;
                sc_rc = (sc_lit < 0) ? DIM : (sc_lit < SC_DONE) ? GRAY : (highlight == ri) ? ACCENT : WHITE;
                sc_lc = (sc_lit < 0) ? DIM : (sc_lit < SC_DONE) ? GRAY : (highlight == ri) ? ACCENT : GRAY;
                for (j = 0; j < 7; j = j + 1) begin
                    sc_t = {1'b0, sc_roll} + 3 * j;
                    sc_t = (sc_t >= 5'd20) ? sc_t - 5'd20 : (sc_t >= 5'd10) ? sc_t - 5'd10 : sc_t;
                    sc_bcd[4 * (6 - j) +: 4] = (sc_lit < 0) ? 4'd0 :
                                               (sc_lit >= SC_LOCK0 + SC_LOCK_STEP * j) ? table_bcd[28 * ri + 4 * (6 - j) +: 4]
                                                                                        : sc_t[3:0];
                end
                // riflesso: banda in diagonale larga 12 sulle lettere del posto nuovo
                sc_glint = highlight == ri && intro_age >= SC_MARK + 8'd20 && blink < 6'd30 &&
                           span(x - (y - sc_row_y), TB_X - 20 + {blink, 3'b0}, 11'd0, 12);
                // posizione: 1-10
                if (ri == 4'd9) begin
                    put(TB_X, sc_row_y, 6'd1, 2'd0, sc_rc);
                    put(TB_X + C, sc_row_y, 6'd0, 2'd0, sc_rc);
                end else
                    put(TB_X + C, sc_row_y, {2'd0, ri} + 6'd1, 2'd0, sc_rc);
                for (j = 0; j < 3; j = j + 1)
                    put(TB_X + TB_NAMES + C * j, sc_row_y, table_names[18 * ri + 6 * j +: 6], 2'd0, sc_rc);
                digits7(TB_X + TB_SCORE, sc_row_y, sc_bcd, sc_rc);
                if (table_levels[4 * ri +: 4] > 4'd7) begin
                    // scala finita: ALL
                    put(TB_X + TB_LEVEL, sc_row_y, 6'd10, 2'd0, sc_lc);
                    put(TB_X + TB_LEVEL + C, sc_row_y, G_L, 2'd0, sc_lc);
                    put(TB_X + TB_LEVEL + 2 * C, sc_row_y, G_L, 2'd0, sc_lc);
                end else begin
                    put(TB_X + TB_LEVEL, sc_row_y, G_L, 2'd0, sc_lc);
                    put(TB_X + TB_LEVEL + C, sc_row_y, G_V, 2'd0, sc_lc);
                    put(TB_X + TB_LEVEL + 2 * C, sc_row_y, {2'd0, table_levels[4 * ri +: 4]}, 2'd0, sc_lc);
                end
            end
            if (sc_ball_y(intro_age) >= SC_BOTTOM && blink < 6'd30 &&
                (coin_prompt ? `CENTER1(ch_coin_lit, CH_COIN_W, 226) : `CENTER1(ch_press_lit, CH_PRESS_W, 226)))
                col = GRAY;
        end
        3'd6: begin   // -------------------------------------------- punti in partita
            // in basso dalla parte dell'avversario, lontano dai punteggi e dalla mezzeria: livello,
            // punti, moltiplicatore
            hud_x = side ? HUD_L : HUD_R;
            put(hud_x, HUD_Y, G_L, 2'd0, GRAY);
            put(hud_x + C, HUD_Y, {3'd0, level} + 6'd1, 2'd0, GRAY);
            digits7(hud_x + 3 * C, HUD_Y, score_bcd, GRAY);
            if (mult > 4'd1) begin
                put(hud_x + 11 * C, HUD_Y, G_X, 2'd0, ACCENT);
                put(hud_x + 12 * C, HUD_Y, {2'd0, mult}, 2'd0, ACCENT);
            end
        end
        3'd7: begin   // ----------------------------------- HERE COMES A NEW CHALLENGER!
            // come nei picchiaduro: banda rossa e scritta che lampeggia (8 frame per colore)
            // (la targa disegnata, con il bianco che lampeggia in giallo, dalla ROM come i nomi)
            on = 1'b1;
            if (y - NEW_BAND_Y < NEW_BAND_H) col = BAND;
            if (y - NEW_BAND_Y == 0 || y - NEW_BAND_Y == NEW_BAND_H - 1) col = ACCENT;
            n_u = $signed({2'b0, x}) - NEW_X;
            n_v = $signed({2'b0, y}) - NEW_Y;
            ta_addr = TL_NEWCH_BASE + {n_v[5:0], n_u[7:0]};
            ta_ok = n_u >= 0 && n_u < TL_NEWCH_W && n_v >= 0 && n_v < TL_NEWCH_H;
            if (ta_ok) begin
                under = col;
                col = MARK;
            end
        end
        default: ;
    endcase
    // "n WINS": sette celle (decine, unità, spazio, W, I, N, S) a scala 1, in alto (presentazione) o in
    // basso (fine del duello), una sola sottrazione e confronti con costanti; con una cifra la cella
    // delle decine è vuota e la scritta si sposta di mezza cella, così resta centrata (sull'inchiostro:
    // l'ultima colonna della cella è vuota)
    w_x = $signed({2'b0, x}) - ((wins_big ? (wins_right ? 11'sd256 : 11'sd64) : (wins_right ? 11'sd240 : 11'sd80)) -
                                (wins_bcd[7:4] != 4'd0 ? 11'sd28 : 11'sd32));
    w_y = $signed({2'b0, y}) - (wins_big ? 11'sd226 : 11'sd2);
    w_u = w_x;
    w_k = (w_u >= 8) + (w_u >= 16) + (w_u >= 24) + (w_u >= 32) + (w_u >= 40) + (w_u >= 48);
    if (wins_on && w_x >= 0 && w_u < 56 && w_y >= 0 && w_y < 11'sd8) begin
        g_on = 1'b1;
        g_dx = w_u[9:0] - {4'd0, w_k, 3'b0};
        g_dy = w_y[9:0];
        g_col = ACCENT;
        sc_glint = 1'b0;
        case (w_k)
            3'd0: g_code = (wins_bcd[7:4] != 4'd0) ? {2'd0, wins_bcd[7:4]} : G_SPACE;
            3'd1: g_code = {2'd0, wins_bcd[3:0]};
            3'd2: g_code = G_SPACE;
            3'd3: g_code = 6'd32;     // W
            3'd4: g_code = 6'd18;     // I
            3'd5: g_code = 6'd23;     // N
            default: g_code = 6'd28;  // S
        endcase
    end
    if (g_on && glyph_lit(g_code, g_dx, g_dy)) begin
        on = 1'b1;
        col = sc_glint ? WHITE : g_col;
    end
end

`undef CENTER1

// ROM dei titoli: porta A il nome o la targa, porta B l'immagine dietro al nome del RUSH
reg [3:0] trom [0:TL_CH_DEPTH-1];
initial $readmemh(TITLE_ROM, trom);
reg [3:0] ta_q = 4'd0, tb_q = 4'd0;
always @(posedge clk) ta_q <= trom[ta_addr];
always @(posedge clk) tb_q <= trom[tb_addr];

// primo ciclo: colore del resto (o MARK) e del sotto; secondo: il colore del titolo se il pixel è acceso
reg [3:0] col_q = BLACK, under_q = BLACK;
reg       on_q = 1'b0, ta_ok_q = 1'b0, g_ok_q = 1'b0, hi_q = 1'b0;
always @(posedge clk) begin
    col_q <= col;
    under_q <= under;
    on_q <= on;
    ta_ok_q <= ta_ok;
    g_ok_q <= g_ok;
    hi_q <= (screen == 3'd7) ? !blink[3] : i_nacc;
    rgb <= pal((col_q != MARK) ? col_q : (ta_ok_q && ta_q != TL_CLEAR) ? role_col(ta_q, hi_q) :
               (g_ok_q && tb_q != TL_CLEAR) ? GHOST : under_q);
    opaque <= on_q;
end

endmodule

// Binario -> BCD (7 cifre) con il doppio dabble, un bit per ciclo: si ricomincia di continuo, il
// risultato si aggiorna ogni 25 cicli. Solo confronti, somme e shift.
module bin_to_bcd (
    input  wire        clk,
    input  wire [23:0] bin,
    output reg  [27:0] bcd
);

reg [23:0] sh = 24'd0;
reg [31:0] acc = 32'd0;
reg [4:0]  count = 5'd0;
reg [31:0] adj;
integer    d;

initial bcd = 28'd0;

always @(*) begin
    adj = acc;
    for (d = 0; d < 8; d = d + 1)
        if (acc[4 * d +: 4] >= 4'd5) adj[4 * d +: 4] = acc[4 * d +: 4] + 4'd3;
end

always @(posedge clk) begin
    if (count == 5'd0) begin
        sh <= bin;
        acc <= 32'd0;
        count <= 5'd24;
    end else begin
        {acc, sh} <= {adj[30:0], sh, 1'b0};
        count <= count - 5'd1;
        if (count == 5'd1) bcd <= {adj[26:0], sh[23]};
    end
end

endmodule
