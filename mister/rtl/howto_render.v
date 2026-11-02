// Schermata HOW TO PLAY delle mosse speciali (NEXT e CHALLENGE con l'opzione Super moves), in stile
// Neo Geo come rust/game/src/moves_ui.rs, su uno schermo 320x240: titolo, i riquadri di STRAIGHT
// SHOT e RISING STRIKE con la frase dell'effetto, il gesto del controllo scelto nell'OSD (joystick
// arcade di tre quarti, oppure manopola vista dall'alto con la freccia della rotazione per paddle e
// spinner), "+ A DASH" e a destra il riquadro con la palla che parte dritta o che s'impenna; sotto il
// costo (mezza barra = mossa, barra piena = MAX), la legenda dei pulsanti e PRESS START TO SKIP.
//
// Animazione a ciclo continuo, con i tempi di moves_ui.rs a 60 Hz: i passi del gesto si accendono uno
// dopo l'altro (le freccette tra i passi diventano gialle), poi il pulsante A si abbassa e la palla
// parte; poi una pausa con tutto spento e si ricomincia.
//
// Tre livelli, generati da tools/gen_howto_assets.py:
// - scritte, "+" e barre del costo: righe dello schermo intere a 2 bit per pixel (howto_text.hex),
//   ognuna una volta sola, con la mappa {controllo, y} -> riga (howto_rows.hex), letta una volta per
//   riga durante la cancellazione orizzontale;
// - figurine 32x32 a codici di colore (howto_sprites.hex): joystick inclinati, manopole, pulsante A
//   su e giù, pulsanti della legenda; pallina, bordo della base e freccia della manopola cambiano
//   colore con il passo acceso;
// - in logica le cornici, le freccette, la racchetta e la palla del riquadro del tiro.
// Pipeline di due cicli: indirizzi delle ROM e strato in logica dai contatori video, poi i colori.
// Un pixel dura 3 cicli di clk, quindi il colore arriva in tempo come quello di next_render. Una volta
// per frame (frame_start, nel vblank) l'avanzamento dell'animazione diventa posizioni in pixel:
// durante il frame restano solo confronti con costanti o registri.

`timescale 1ns / 1ps

module howto_render #(
    parameter TEXT_ROM = "rtl/gen/howto_text.hex",
    parameter ROWS_ROM = "rtl/gen/howto_rows.hex",
    parameter SPRITE_ROM = "rtl/gen/howto_sprites.hex"
) (
    input  wire        clk,
    input  wire        active,         // schermata in corso (fuori l'animazione torna all'inizio)
    input  wire        frame_start,    // inizio del vblank
    input  wire [8:0]  hc,
    input  wire [8:0]  vc,
    input  wire [1:0]  control,        // comandi da mostrare: 0 joystick, 1 paddle, 2 spinner
    input  wire [5:0]  blink,          // frame % 60: PRESS START TO SKIP lampeggia
    output reg  [23:0] rgb
);

`include "pong_howto.vh"

localparam [23:0] BLACK = 24'h000000, WHITE = 24'hFFFFFF, GRAY = 24'h969696, ACCENT = 24'hFFD225,
                  FRAME = 24'h464646,
                  TRAIL = 24'h735E11;   // scia di RISING STRIKE: l'accento al 45% sul nero
// colori delle figurine (come moves_ui.rs)
localparam [23:0] C_DARK = 24'h37373C, C_HOLE = 24'h191919, C_SHAFT = 24'hBEBEC3, C_RED = 24'hE62828,
                  C_RED_DARK = 24'h8C1414, C_RED_LIGHT = 24'hFF6E6E, C_EDGE_OFF = 24'h5A5A5F,
                  C_KNOB = 24'h1E1E23, C_KNOB_EDGE = 24'h6E6E73, C_KNOB_TOP = 24'h505058;
// codici dello strato in logica
localparam [2:0] V_NONE = 3'd0, V_FRAME = 3'd1, V_WHITE = 3'd2, V_ACCENT = 3'd3, V_GRAY = 3'd4, V_TRAIL = 3'd5;

// Tempi in frame (moves_ui.rs: STEP 0,22 s, il tiro 0,22 s più 6 passi da 0,11 s, pausa 0,88 s). Il
// ciclo dura PRESS + FLIGHT_F + IDLE_F frame, con PRESS = STEP_F * passi del gesto.
localparam [7:0] STEP_F = 8'd13, FLIGHT_F = 8'd53, IDLE_F = 8'd53;
// riquadro del tiro: colonna della palla alla partenza (racchetta in 208..210), bordo destro (la
// palla sparisce quando lo tocca), colonna dove RISING STRIKE s'impenna, salita massima
localparam [8:0] SHOT_X = 9'd212, SHOT_END = 9'd299, RISE_X = 9'd256;
localparam [3:0] RISE_MAX = 4'd14;

// ------------------------------------------------------------- animazione (una volta per frame)

wire       knob = control != 2'd0;
wire [7:0] press = knob ? 2 * STEP_F : 3 * STEP_F;
reg  [7:0] t = 8'd0;                   // frame dall'inizio del ciclo
always @(posedge clk) begin
    if (!active)
        t <= 8'd0;
    else if (frame_start)
        t <= (t == press + FLIGHT_F + IDLE_F - 8'd1) ? 8'd0 : t + 8'd1;
end

// salita di RISING STRIKE alla colonna c: dritta fino a RISE_X, poi a 45 gradi fino a RISE_MAX
function [3:0] rise_of(input [8:0] c);
    rise_of = (c <= RISE_X) ? 4'd0 : (c - RISE_X >= RISE_MAX) ? RISE_MAX : c[3:0] - RISE_X[3:0];
endfunction

wire [2:0] s_now = (t < STEP_F) ? 3'd0 : (t < 2 * STEP_F) ? 3'd1 : (t < 3 * STEP_F) ? 3'd2 :
                   (t < 4 * STEP_F) ? 3'd3 : 3'd4;
wire       flying = t < press + FLIGHT_F;
wire [7:0] ts = t - press;
wire [9:0] ts11 = {ts[6:0], 3'b000} + {1'b0, ts, 1'b0} + {2'b00, ts};          // 11 * ts (ts < 64 in volo)
wire [8:0] ball_now = SHOT_X + 9'd8 + {1'b0, ts11[9:2]};                          // 8 + 2,75 pixel per frame
reg  [2:0] step_lit = 3'd7;            // passo acceso (passi del gesto, poi il pulsante A), 7 = nessuno
reg  [2:0] done = 3'd0;                // freccetta i gialla con done > i
reg        ball_on = 1'b0, trail_on = 1'b0;
reg  [8:0] ball_x = SHOT_X;
reg  [3:0] ball_rise = 4'd0;           // RISING STRIKE: salita della palla
reg  [8:0] tr_x [0:2];                 // RISING STRIKE: punti della scia (colonna) e salita
reg  [3:0] tr_rise [0:2];
reg  [2:0] tr_on = 3'd0;
integer i;
always @(posedge clk) begin
    // i valori cambiano solo con t, nel vblank
    step_lit <= (flying && s_now <= (knob ? 3'd2 : 3'd3)) ? s_now : 3'd7;
    done <= flying ? s_now : 3'd0;
    ball_on <= flying && t >= press && ball_now < SHOT_END;
    trail_on <= flying && t >= press && ball_now < SHOT_END && ball_now > SHOT_X + 9'd10;
    ball_x <= ball_now;
    ball_rise <= rise_of(ball_now);
    for (i = 0; i < 3; i = i + 1) begin
        tr_x[i] <= ball_now - 9'd4 * (i + 1) + 9'd1;
        tr_rise[i] <= rise_of(ball_now - 9'd4 * (i + 1));
        tr_on[i] <= ball_now - 9'd4 * (i + 1) > SHOT_X;
    end
end

// ------------------------------------------------------------------- ROM

reg [1:0] text_rom [0:HT_TEXT_ROWS * 320 - 1];
reg [8:0] rows_rom [0:1023];
reg [3:0] sprite_rom [0:HT_SPRITES * 1024 - 1];
initial begin
    $readmemh(TEXT_ROM, text_rom);
    $readmemh(ROWS_ROM, rows_rom);
    $readmemh(SPRITE_ROM, sprite_rom);
end

// mappa delle righe: si legge per la riga successiva e si ferma a metà della cancellazione
// orizzontale, così a inizio riga la base dell'indirizzo è già pronta
wire [8:0] ny = (vc == 9'd261) ? 9'd0 : vc + 9'd1;
reg  [8:0] rows_q = 9'd0, trow = 9'd0;
reg [16:0] tbase = 17'd0;               // riga * 320
always @(posedge clk) begin
    rows_q <= rows_rom[{control, ny[7:0]}];
    if (hc == 9'd330) trow <= (ny < 9'd240) ? rows_q : 9'd0;
    tbase <= {1'b0, trow[7:0], 8'd0} + {3'b000, trow[7:0], 6'd0};
end

// --------------------------------------------------------- pixel: stadio 1

wire [8:0] x = hc;
wire [8:0] y = vc;

// figurine: riga del comando di uno dei due riquadri o della legenda, poi il posto lungo la riga
wire [8:0] ly0 = y - (HT_CY0 - HT_AY), ly1 = y - (HT_CY1 - HT_AY), lyl = y - (HT_LEG_CY - HT_AY);
wire       in_c0 = ly0 < 9'd32, in_c1 = ly1 < 9'd32, in_leg = lyl < 9'd32;
wire [8:0] sx0 = x - (HT_JOY_S0 - HT_AX), sx1 = x - (HT_JOY_S1 - HT_AX), sx2 = x - (HT_JOY_S2 - HT_AX);
wire [8:0] sxa = x - ((knob ? HT_KNOB_A : HT_JOY_A) - HT_AX);
wire [8:0] lx0 = x - (HT_LEG_X0 - HT_AX), lx1 = x - (HT_LEG_X1 - HT_AX), lx2 = x - (HT_LEG_X2 - HT_AX);
reg        spr_on, spr_lit;
reg  [3:0] spr_id;
reg  [4:0] spr_lx, spr_ly;
always @(*) begin
    spr_on = 1'b0;
    spr_lit = 1'b0;
    spr_id = 4'd0;
    spr_lx = sx0[4:0];
    spr_ly = in_c1 ? ly1[4:0] : in_leg ? lyl[4:0] : ly0[4:0];
    if (in_c0 || in_c1) begin
        // passi: STRAIGHT SHOT giù, giù-avanti, avanti (manopola: giù, su); RISING STRIKE avanti, giù,
        // giù-avanti (manopola: su, giù)
        if (sx0 < HT_SLOT_W) begin
            spr_on = 1'b1;
            spr_lit = step_lit == 3'd0;
            spr_id = knob ? (in_c1 ? HT_SPIN_U : HT_SPIN_D) : (in_c1 ? HT_STICK_F : HT_STICK_D);
        end
        if (sx1 < HT_SLOT_W) begin
            spr_on = 1'b1;
            spr_lit = step_lit == 3'd1;
            spr_lx = sx1[4:0];
            spr_id = knob ? (in_c1 ? HT_SPIN_D : HT_SPIN_U) : (in_c1 ? HT_STICK_D : HT_STICK_DF);
        end
        if (!knob && sx2 < HT_SLOT_W) begin
            spr_on = 1'b1;
            spr_lit = step_lit == 3'd2;
            spr_lx = sx2[4:0];
            spr_id = in_c1 ? HT_STICK_DF : HT_STICK_F;
        end
        // il pulsante A si abbassa dopo l'ultimo passo
        if (sxa < HT_SLOT_W) begin
            spr_on = 1'b1;
            spr_lx = sxa[4:0];
            spr_id = (step_lit == (knob ? 3'd2 : 3'd3)) ? HT_BTN_A_DOWN : HT_BTN_A;
        end
    end
    if (in_leg) begin
        if (lx0 < HT_SLOT_W) begin
            spr_on = 1'b1;
            spr_lx = lx0[4:0];
            spr_id = HT_SMALL_0;
        end
        if (lx1 < HT_SLOT_W) begin
            spr_on = 1'b1;
            spr_lx = lx1[4:0];
            spr_id = HT_SMALL_1;
        end
        if (lx2 < HT_SLOT_W) begin
            spr_on = 1'b1;
            spr_lx = lx2[4:0];
            spr_id = HT_SMALL_2;
        end
    end
end

// scritte: la riga di questa riga dello schermo; PRESS START TO SKIP lampeggia
wire text_on = trow[8] && x < 9'd320 && !(y >= HT_SKIP_Y0 && y < HT_SKIP_Y1 && blink >= 6'd37);

// strato in logica: dentro un riquadro (b = 1 il secondo) dy conta le righe dall'alto del riquadro
// del tiro (cy - 18), per cui la palla ferma sta nelle righe 15..17
wire       b = y >= 9'd108;
wire [8:0] dy = y - (b ? HT_CY1 - 18 : HT_CY0 - 18);
wire       in_box = (y >= HT_BOX0_Y - 4 && y <= HT_BOX0_Y + 62) || (y >= HT_BOX1_Y - 4 && y <= HT_BOX1_Y + 62);
wire [8:0] ay = y - (b ? HT_CY1 - 3 : HT_CY0 - 3);                 // righe delle freccette
wire [8:0] ax0 = x - (HT_JOY_S0 + HT_ARROW_DX), ax1 = x - (HT_JOY_S1 + HT_ARROW_DX);
wire [4:0] arow = ht_arrow_row(ay[2:0]);
reg  [2:0] vec;
always @(*) begin
    vec = V_NONE;
    if (in_box) begin
        // cornice del riquadro della mossa
        if (x == 9'd8 || x == 9'd311 || y == HT_BOX0_Y - 4 || y == HT_BOX0_Y + 62 ||
            y == HT_BOX1_Y - 4 || y == HT_BOX1_Y + 62)
            if (x >= 9'd8 && x <= 9'd311) vec = V_FRAME;
        // riquadro del tiro: cornice e racchetta
        if (dy <= 9'd30 && x >= 9'd204 && x <= 9'd302 && (dy == 9'd0 || dy == 9'd30 || x == 9'd204 || x == 9'd302))
            vec = V_FRAME;
        if (x >= 9'd208 && x <= 9'd210 && dy >= 9'd10 && dy <= 9'd22) vec = V_WHITE;
        if (!b) begin
            // STRAIGHT SHOT: tre righe di velocità dietro la palla, che va dritta
            if (trail_on && x >= SHOT_X && x <= ball_x - 9'd4 && (dy == 9'd14 || dy == 9'd16 || dy == 9'd18))
                vec = V_ACCENT;
            if (ball_on && x - ball_x < 9'd3 && dy >= 9'd15 && dy <= 9'd17) vec = V_ACCENT;
        end else begin
            // RISING STRIKE: dritta fino a metà riquadro, poi s'impenna; tre punti di scia
            if (ball_on && ((tr_on[0] && x == tr_x[0] && dy == 9'd16 - tr_rise[0]) ||
                            (tr_on[1] && x == tr_x[1] && dy == 9'd16 - tr_rise[1]) ||
                            (tr_on[2] && x == tr_x[2] && dy == 9'd16 - tr_rise[2])))
                vec = V_TRAIL;
            if (ball_on && x - ball_x < 9'd3 && dy >= 9'd15 - ball_rise && dy <= 9'd17 - ball_rise) vec = V_ACCENT;
        end
        // freccette tra i passi, gialle quando il passo prima è fatto
        if (ay < 9'd7) begin
            if (ax0 < 9'd5 && arow[3'd4 - ax0[2:0]]) vec = (done > 3'd0) ? V_ACCENT : V_GRAY;
            if (!knob && ax1 < 9'd5 && arow[3'd4 - ax1[2:0]]) vec = (done > 3'd1) ? V_ACCENT : V_GRAY;
        end
    end
end

reg  [3:0] spr_q;
reg  [1:0] txt_q;
reg        spr_on_q = 1'b0, spr_lit_q = 1'b0, txt_on_q = 1'b0;
reg  [2:0] vec_q = V_NONE;
always @(posedge clk) begin
    spr_q <= sprite_rom[{spr_id, spr_ly, spr_lx}];
    txt_q <= text_rom[tbase + {8'd0, x}];
    spr_on_q <= spr_on;
    spr_lit_q <= spr_lit;
    txt_on_q <= text_on;
    vec_q <= vec;
end

// --------------------------------------------------------- pixel: stadio 2

reg [23:0] spr_col, vec_col;
always @(*) begin
    case (spr_q)
        HS_DARK:      spr_col = C_DARK;
        HS_HOLE:      spr_col = C_HOLE;
        HS_SHAFT:     spr_col = C_SHAFT;
        HS_BALL:      spr_col = spr_lit_q ? C_RED : C_RED_DARK;
        HS_BASE_EDGE: spr_col = spr_lit_q ? ACCENT : C_EDGE_OFF;
        HS_WHITE:     spr_col = WHITE;
        HS_RED:       spr_col = C_RED;
        HS_RED_DARK:  spr_col = C_RED_DARK;
        HS_RED_LIGHT: spr_col = C_RED_LIGHT;
        HS_KNOB:      spr_col = C_KNOB;
        HS_KNOB_EDGE: spr_col = C_KNOB_EDGE;
        HS_KNOB_TOP:  spr_col = C_KNOB_TOP;
        HS_SPIN:      spr_col = spr_lit_q ? ACCENT : GRAY;
        default:      spr_col = BLACK;
    endcase
    case (vec_q)
        V_FRAME:  vec_col = FRAME;
        V_WHITE:  vec_col = WHITE;
        V_ACCENT: vec_col = ACCENT;
        V_GRAY:   vec_col = GRAY;
        V_TRAIL:  vec_col = TRAIL;
        default:  vec_col = BLACK;
    endcase
end

always @(posedge clk)
    rgb <= (spr_on_q && spr_q != 4'd0) ? spr_col :
           (txt_on_q && txt_q != 2'd0) ? (txt_q == 2'd1 ? WHITE : txt_q == 2'd2 ? GRAY : ACCENT) : vec_col;

endmodule
