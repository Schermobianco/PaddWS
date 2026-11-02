// Musiche ed effetti con il SID (rtl/sid, dal core C64 del MiSTer).
//
// Player in stile C64: quattro canali leggono tracce da una ROM (tools/gen_sid_music.py) e
// scrivono i registri del SID. I canali 0-2 suonano la canzone sulle voci 1-3; il canale 3 suona
// gli effetti sulla voce 3, che intanto la canzone continua a contare senza suonare. Il player
// avanza a 50 Hz; un effetto parte subito, senza aspettare il frame.
//
// Musica dinamica (regole di rust/sid/src/engine.rs e player.rs, che ne è il port: stesse scritture):
// - match point (`music_fast`): i canali della canzone avanzano a 62,5 Hz (un passo ogni 320.000
//   cicli invece di 400.000) con le note alla stessa altezza; gli effetti restano a 50 Hz, con un
//   divisore e una fase degli arpeggi loro. Il periodo cambia dal passo dopo quello in attesa;
// - bullet time (`music_slow`): i canali della canzone sono serviti un passo su due e scrivono le
//   frequenze dimezzate, come gli effetti rallentati (`fx_slow`); a ogni cambio, al passo dopo, le
//   note in corso riscrivono subito la frequenza (S_RT), tranne se la canzone è appena ripartita;
// - le due regole si sommano.
//
// Filtro (formato in tools/gen_sid_music.py, port in rust/sid/src/player.rs e c64/src/sid.s): il
// taglio (0xA0+l, h) e la sua scivolata a ogni passo della canzone (0xB0, 16 bit) sono comandi di
// traccia, con il taglio a 16 bit (5 bit di frazione); $D417 e $D418 sono nei byte 6 e 7 degli
// strumenti nel filtro, che il generatore mette solo nelle voci 1 e 2 (la voce 3, degli effetti,
// non passa mai dal filtro). Il player tiene una copia di $D417 e $D418 (`fres`, `fvm`) e li
// riscrive, con il taglio, solo quando cambiano; a ogni canzone nuova $D418 = $0F e $D417 = 0. Le
// scritture del filtro (S_FW) non tacciono mai per la voce 3.
//
// Formato delle tracce: vedi tools/gen_sid_music.py. Priorità degli effetti: gettone > punto >
// colpo della mossa speciale > boost > mossa attivata > colpo > muro. Con `slow` (bullet time di
// NEXT) l'effetto che parte suona a metà velocità, come i campioni rallentati del gioco Rust:
// frequenze dimezzate (un'ottava sotto) e un passo del player ogni due frame.
//
// Voce digitalizzata (CHALLENGE: il nome dell'avversario nella presentazione), con il trucco del
// registro del volume ($D418) del C64: campioni a 4 bit a VOICE_RATE Hz (tools/gen_voices.py)
// scritti come volume. Il volume moltiplica tutta l'uscita del SID, compreso il suo offset DC: il
// 6581 ne ha uno suo (in rtl/sid, VOICE_DC_6581 e MIXER_DC_6581), l'8580 no, come i chip veri.
// Perché la voce si senta con tutti e due, le voci 2 e 3 danno un DC costante (impulso con il bit
// di test, sustain al massimo), come facevano i player di campioni per l'8580. Intanto la musica
// tace (le sue scritture si saltano, la voce 1 si spegne) e gli effetti aspettano; l'inviluppo
// sale e scende piano (attacco e rilascio) per evitare il colpo del DC all'inizio e alla fine.
// Il filtro durante la voce è spento: all'inizio $D417 = 0 (il DC delle voci 2 e 3 non passa dal
// filtro), i campioni hanno il modo a 0 e alla fine $D418 = $0F; intanto la copia del filtro del
// player resta $D417 = 0 e $D418 = $0F, così la prima nota nel filtro dopo la voce riscrive tutto
// (taglio, $D417, $D418), anche se il tema è partito mentre la voce si spegneva.
//
// Voci di partita (urla delle mosse speciali, READY e GO della CHALLENGE, YOU WIN della vittoria
// contro la CPU e del finale della CHALLENGE): dalla stessa ROM, con un
// secondo player che non tocca il SID. Esce come campione a 4 bit (`call_level`) che pong_top somma
// all'uscita audio, così musica ed effetti continuano; una voce nuova interrompe quella in corso.

`timescale 1ns / 1ps

module pong_sid #(
    parameter ROM_FILE = "rtl/gen/sid_music.hex",
    parameter VOICE_FILE = "rtl/gen/sid_voices.hex"
) (
    input  wire        clk,           // 20 MHz
    input  wire        reset,
    input  wire        mode_8580,     // 0 = 6581, 1 = 8580
    input  wire [3:0]  song,          // canzone (0 = silenzio): quando cambia riparte da capo
    input  wire        trigger,       // impulso: eventi del frame in `events`
    input  wire [7:0]  events,        // bit 0 muro, 1 colpo, 2 boost, 3 punto, 4 gettone, 5 mossa, 6 colpo della mossa
    input  wire        slow,          // con `trigger`: l'effetto suona a metà velocità
    input  wire        music_fast,    // match point: la canzone a 62,5 Hz
    input  wire        music_slow,    // bullet time: la canzone a metà velocità, un'ottava sotto
    // voce: impulso di partenza con il nome (codice di PaddleKind), arresto (livello) e stato
    input  wire        voice_go,
    input  wire [2:0]  voice_id,
    input  wire        voice_stop,
    output wire        voice_on,      // la voce ha il SID (anche durante attacco e rilascio)
    // voce di partita: impulso di partenza con il numero (VOICE_* di sid_voices.vh) e campione in
    // corso (8 = silenzio), da sommare all'uscita
    input  wire        call_go,
    input  wire [3:0]  call_id,
    output reg  [3:0]  call_level,
    output wire signed [15:0] sample
);

`include "sid_music.vh"
`include "sid_voices.vh"

// ------------------------------------------------------------------ ROM

reg [7:0]  rom [0:SID_ROM_SIZE-1];
initial $readmemh(ROM_FILE, rom);
reg [11:0] raddr = 12'd0;
reg [7:0]  rdata = 8'd0;
always @(posedge clk) rdata <= rom[raddr];      // lettura sincrona: un ciclo di attesa

// ------------------------------------------------------------------ tempi

// clock del SID: 1 MHz
reg [4:0] div = 5'd0;
wire ce_1m = div == 5'd19;
always @(posedge clk) div <= ce_1m ? 5'd0 : div + 5'd1;

// frame del player: 50 Hz per gli effetti; per la canzone 50 Hz o, al match point, 62,5 Hz. Il
// periodo della canzone si sceglie a ogni suo passo, per il passo dopo; fuori dal match point dopo
// l'accensione i due passi coincidono, come con un solo divisore
reg [18:0] frame_div = 19'd0;
wire frame_tick = frame_div == 19'd399_999;
always @(posedge clk) frame_div <= frame_tick ? 19'd0 : frame_div + 19'd1;
reg [18:0] song_div = 19'd0;
reg [18:0] song_lim = 19'd399_999;
wire song_tick = song_div == song_lim;
always @(posedge clk) begin
    song_div <= song_tick ? 19'd0 : song_div + 19'd1;
    if (song_tick) song_lim <= music_fast ? 19'd319_999 : 19'd399_999;
end

// ------------------------------------------------------------------ canali

reg [11:0] ptr   [0:3];
reg [11:0] start [0:3];
reg [7:0]  cnt   [0:3];
reg [6:0]  note  [0:3];
reg [3:0]  ins   [0:3];   // strumento: 16, indice a 4 bit
reg [1:0]  arp   [0:3];
reg [7:0]  slide [0:3];
reg [15:0] freq  [0:3];
reg [7:0]  wave  [0:3];      // forma d'onda dello strumento (senza gate)
reg [7:0]  rel   [0:3];      // frame di rilascio prima della fine della nota
reg [3:0]  active = 4'd0;

// effetto da suonare, per priorità
function [2:0] fx_of(input [6:0] e);
    casez (e)
        7'b??1????: fx_of = SID_FX_COIN;
        7'b??01???: fx_of = SID_FX_SCORE;
        7'b1?00???: fx_of = SID_FX_SPECIAL;     // colpo con una mossa speciale
        7'b0?001??: fx_of = SID_FX_BOOST;
        7'b01000??: fx_of = SID_FX_MOVE;        // mossa speciale attivata
        7'b000001?: fx_of = SID_FX_HIT;
        7'b0000001: fx_of = SID_FX_WALL;
        default:    fx_of = 3'd0;
    endcase
endfunction

// arpeggi: semitoni da aggiungere alla nota nel passo 0-2
function [6:0] arp_ofs(input [1:0] mode, input [1:0] phase);
    case ({mode, phase})
        {2'd1, 2'd1}: arp_ofs = 7'd3;
        {2'd1, 2'd2}: arp_ofs = 7'd7;
        {2'd2, 2'd1}: arp_ofs = 7'd4;
        {2'd2, 2'd2}: arp_ofs = 7'd7;
        {2'd3, 2'd1}: arp_ofs = 7'd12;
        {2'd3, 2'd2}: arp_ofs = 7'd12;
        default:      arp_ofs = 7'd0;
    endcase
endfunction

// ------------------------------------------------------------------ sequenza

localparam S_IDLE = 5'd0, S_CH = 5'd1, S_FETCH = 5'd2, S_CMD = 5'd3, S_ARG = 5'd4,
           S_INS = 5'd5, S_INS2 = 5'd6, S_INS3 = 5'd7, S_INS4 = 5'd8, S_INS5 = 5'd9, S_INS6 = 5'd10,
           S_FRQ = 5'd11, S_FRQ2 = 5'd12, S_GATE = 5'd13, S_RUN = 5'd14, S_NEXT = 5'd15,
           S_WAIT = 5'd16, S_FXOFF = 5'd17, S_SLIDE = 5'd18, S_SILENCE = 5'd19, S_FRQ3 = 5'd20,
           S_RT = 5'd21, S_RT2 = 5'd22, S_INS7 = 5'd23, S_INS8 = 5'd24, S_FLT = 5'd25, S_FW = 5'd26,
           S_FRD = 5'd27, S_FOFF = 5'd28, S_SW = 5'd29, S_ARG2 = 5'd30;

reg [4:0]  state = S_IDLE;
reg [4:0]  after = S_IDLE;        // stato dopo l'attesa della ROM
reg [1:0]  ch = 2'd0;
reg [3:0]  mask = 4'd0;           // canali da servire in questo passaggio
reg [1:0]  phase = 2'd0;          // passo degli arpeggi della canzone
reg [1:0]  fx_phase = 2'd0;       // e degli effetti (uguali fuori dal match point)
reg [7:0]  cmd = 8'd0;
reg [7:0]  pw_lo = 8'd0;
reg        freq_write = 1'b0;     // dopo la frequenza: gate (nota nuova) o fine
reg [3:0]  song_q = 4'd0;
reg        song_new = 1'b0;
reg [2:0]  fx_req = 3'd0;
reg        tick_pending = 1'b0;      // passo degli effetti da fare
reg        song_pending = 1'b0;      // passo della canzone da fare
// effetto rallentato: richiesto, in corso, e frame saltato (il canale 3 avanza un frame su due)
reg        slow_req = 1'b0, fx_slow = 1'b0, fx_skip = 1'b0;
// canzone rallentata (bullet time): in corso, passo saltato; cambio appena visto: in quel passo il
// salto si azzera (il primo passo si serve) e le note in corso riscrivono la frequenza
reg        mslow = 1'b0, mskip = 1'b0;
wire       mslow_chg = music_slow != mslow;
wire       mskip_now = !mslow_chg && mskip;
reg        silent_new = 1'b0;     // canzone nuova: è il silenzio

// filtro: taglio a 16 bit (il registro a 11 bit è fcut[15:5]), scivolata del taglio per passo della
// canzone, copia di $D417 e $D418 come sono nel SID; byte 6 e 7 dello strumento della nota
reg [15:0] fcut = 16'd0;
reg [15:0] fsweep = 16'd0;
reg [7:0]  fres = 8'd0;
reg [7:0]  fvm = 8'h0F;
reg [7:0]  ins_filt = 8'd0, ins_vm = 8'd0;
// scritture del filtro (S_FW): dal taglio ($D415, $D416) fino a $D417 o $D418, poi `fafter`
reg [1:0]  fstep = 2'd0, flast = 2'd0;
reg [4:0]  fafter = S_IDLE;

reg        we = 1'b0;
reg [4:0]  addr = 5'd0;
reg [7:0]  data = 8'd0;

// voce del SID del canale: registri da 0, 7 o 14
wire [4:0] vbase = ch == 2'd0 ? 5'd0 : ch == 2'd1 ? 5'd7 : 5'd14;
// la canzone sulla voce 3 tace mentre suona un effetto
wire       mute = ch == 2'd2 && active[3];
// frequenza dopo un passo di scivolata
wire [15:0] slid = freq[ch] + {{8{slide[ch][7]}}, slide[ch]};
// canale in servizio rallentato (effetto o canzone): le frequenze si scrivono dimezzate
wire       half = ch == 2'd3 ? fx_slow : mslow;

// ------------------------------------------------------------------ voce

reg [7:0]  vrom [0:VOICE_ROM_SIZE-1];
initial $readmemh(VOICE_FILE, vrom);
reg [14:0] vaddr = 15'd0;           // la ROM supera i 16 KB (YOU WIN): indirizzi a 15 bit
reg [7:0]  vdata = 8'd0;
always @(posedge clk) vdata <= vrom[vaddr];     // lettura sincrona

localparam [2:0] V_IDLE = 3'd0, V_SETUP = 3'd1, V_PRE = 3'd2, V_PLAY = 3'd3, V_END = 3'd4, V_REL = 3'd5,
                 V_DONE = 3'd6, V_GATE = 3'd7;
localparam [21:0] V_DIV = 20_000_000 / VOICE_RATE;   // cicli per campione
localparam [21:0] V_PRE_CYCLES = 22'd1_400_000;     // 70 ms: attacco 6 (68 ms) del DC
localparam [21:0] V_REL_CYCLES = 22'd2_400_000;     // 120 ms: rilascio 4 (114 ms) del DC
reg [2:0]  vstate = V_IDLE;
reg [3:0]  vstep = 4'd0;          // scrittura della sequenza di preparazione o di chiusura
reg [21:0] vtimer = 22'd0;
reg [12:0] vleft = 13'd0;         // campioni rimasti
reg        vlo = 1'b0;            // prossimo campione nel nibble basso
assign voice_on = vstate != V_IDLE;

// scrittura di un registro della voce del canale (la voce digitalizzata ha la precedenza)
task wr(input [2:0] reg_ofs, input [7:0] value);
    begin
        we <= !mute && !voice_on;
        addr <= vbase + {2'd0, reg_ofs};
        data <= value;
    end
endtask

// scrittura di un registro del filtro: è di tutto il SID, tace solo per la voce digitalizzata
task fw(input [4:0] a, input [7:0] value);
    begin
        we <= !voice_on;
        addr <= a;
        data <= value;
    end
endtask

// lettura dalla ROM: il dato è in `rdata` nello stato `next`
task rd(input [11:0] a, input [4:0] next);
    begin
        raddr <= a;
        after <= next;
        state <= S_WAIT;
    end
endtask

integer c;

always @(posedge clk) begin
    we <= 1'b0;
    song_q <= song;
    if (song != song_q) song_new <= 1'b1;
    if (trigger && fx_of(events[6:0]) != 3'd0) begin
        fx_req <= fx_of(events[6:0]);
        slow_req <= slow;
    end
    if (frame_tick) tick_pending <= 1'b1;
    if (song_tick) song_pending <= 1'b1;

    if (reset) begin
        state <= S_IDLE;
        active <= 4'd0;
        song_new <= 1'b1;
        fx_req <= 3'd0;
        tick_pending <= 1'b0;
        song_pending <= 1'b0;
        for (c = 0; c < 4; c = c + 1) begin
            cnt[c] <= 8'd0;
            wave[c] <= 8'd0;
        end
    end else case (state)
        S_IDLE: begin
            if (fx_req != 3'd0 && !voice_on) begin
                // effetto nuovo: subito, solo sul canale 3; prima si chiude il gate della voce 3
                ptr[3] <= sid_fx_start(fx_req);
                start[3] <= sid_fx_start(fx_req);
                cnt[3] <= 8'd0;
                ins[3] <= 4'd0;
                arp[3] <= 2'd0;
                slide[3] <= 8'd0;
                active[3] <= 1'b1;
                fx_req <= 3'd0;
                fx_slow <= slow_req;
                fx_skip <= 1'b0;
                ch <= 2'd3;
                mask <= 4'b1000;
                we <= 1'b1; addr <= 5'h12; data <= 8'h00;      // controllo della voce 3
                state <= S_FXOFF;
            end else if (tick_pending || song_pending) begin
                // passo degli effetti e/o della canzone (fuori dal match point insieme)
                // (si azzera solo quello servito: l'altro può arrivare proprio adesso)
                if (tick_pending) tick_pending <= 1'b0;
                if (song_pending) song_pending <= 1'b0;
                if (song_pending) phase <= phase == 2'd2 ? 2'd0 : phase + 2'd1;
                if (tick_pending) fx_phase <= fx_phase == 2'd2 ? 2'd0 : fx_phase + 2'd1;
                if (song_pending) begin
                    mslow <= music_slow;
                    mskip <= !mskip_now;
                end
                if (song_pending && song_new) begin
                    // canzone nuova (o silenzio): i canali 0-2 ripartono
                    song_new <= 1'b0;
                    for (c = 0; c < 3; c = c + 1) begin
                        ptr[c] <= sid_song_start(song, c[1:0]);
                        start[c] <= sid_song_start(song, c[1:0]);
                        cnt[c] <= 8'd0;
                        ins[c] <= 4'd0;
                        arp[c] <= 2'd0;
                        slide[c] <= 8'd0;
                    end
                    active[2:0] <= song != 4'd0 ? 3'b111 : 3'b000;
                    // volume al massimo, senza filtro (con la voce lo rimette lei alla fine): modo
                    // spento e nessuna voce nel filtro (S_FOFF); la scivolata del taglio si ferma,
                    // il taglio resta
                    we <= !voice_on; addr <= 5'h18; data <= 8'h0F;
                    fres <= 8'd0;
                    fvm <= 8'h0F;
                    fsweep <= 16'd0;
                    silent_new <= song == 4'd0;
                end
                ch <= 2'd0;
                // l'effetto e la canzone rallentati avanzano un passo su due
                mask <= {tick_pending && !(fx_slow && fx_skip), {3{song_pending && !(music_slow && mskip_now)}}};
                if (tick_pending) fx_skip <= !fx_skip;
                state <= song_pending && mslow_chg && !song_new ? S_RT :
                         song_pending && song_new ? S_FOFF : S_SW;
            end
        end

        // canzone nuova: nessuna voce nel filtro
        S_FOFF: begin
            fw(5'h17, 8'h00);
            state <= silent_new ? S_SILENCE : S_SW;
        end

        // scivolata del taglio, nei passi in cui la canzone avanza, prima dei canali, senza
        // saturazione (il generatore controlla i limiti): il taglio si scrive sempre
        S_SW: begin
            if (mask[0] && fsweep != 16'd0) begin
                fcut <= fcut + fsweep;
                fstep <= 2'd0;
                flast <= 2'd1;
                fafter <= S_CH;
                state <= S_FW;
            end else
                state <= S_CH;
        end

        // registri del filtro, da $D415 a $D415 + flast: taglio, poi $D417 e $D418
        S_FW: begin
            case (fstep)
                2'd0: fw(5'h15, {5'd0, fcut[7:5]});
                2'd1: fw(5'h16, fcut[15:8]);
                2'd2: fw(5'h17, fres);
                default: fw(5'h18, fvm);
            endcase
            fstep <= fstep + 2'd1;
            if (fstep == flast) state <= fafter;
        end

        // dopo il taglio letto dalla traccia: il comando dopo
        S_FRD: rd(ptr[ch], S_CMD);

        // silenzio: si chiude il gate delle voci della canzone, altrimenti l'ultima nota resta
        // tenuta (la voce 3 no se suona un effetto)
        S_SILENCE: begin
            wr(3'd4, wave[ch]);
            if (ch == 2'd2) begin
                ch <= 2'd0;
                state <= S_SW;
            end else
                ch <= ch + 2'd1;
        end

        S_FXOFF: state <= S_CH;          // il gate chiuso resta per un ciclo prima della nota

        // canzone appena rallentata o tornata normale: le note in corso dei canali attivi cambiano
        // ottava subito (dimezzata: prima il byte alto, poi il basso)
        S_RT: begin
            if (active[ch]) wr(half ? 3'd1 : 3'd0, half ? {1'b0, freq[ch][15:9]} : freq[ch][7:0]);
            state <= active[ch] ? S_RT2 : ch == 2'd2 ? S_SW : S_RT;
            if (!active[ch]) ch <= ch == 2'd2 ? 2'd0 : ch + 2'd1;
        end
        S_RT2: begin
            wr(half ? 3'd0 : 3'd1, half ? freq[ch][8:1] : freq[ch][15:8]);
            state <= ch == 2'd2 ? S_SW : S_RT;
            ch <= ch == 2'd2 ? 2'd0 : ch + 2'd1;
        end

        S_CH: begin
            if (!mask[ch] || !active[ch])
                state <= S_NEXT;
            else if (cnt[ch] == 8'd0 || cnt[ch] == 8'd1) begin
                cnt[ch] <= 8'd0;
                rd(ptr[ch], S_CMD);          // nota finita: si legge il comando dopo
            end else begin
                cnt[ch] <= cnt[ch] - 8'd1;
                // rilascio qualche frame prima della fine: la nota dopo riparte con l'attacco
                if (cnt[ch] - 8'd1 == rel[ch]) wr(3'd4, wave[ch]);
                state <= S_RUN;
            end
        end

        S_CMD: begin
            cmd <= rdata;
            if (rdata < 8'h70) begin
                rd(ptr[ch] + 12'd1, S_ARG);              // nota o pausa: durata
            end else if (rdata[7:4] == 4'h7) begin
                ins[ch] <= rdata[3:0];
                ptr[ch] <= ptr[ch] + 12'd1;
                rd(ptr[ch] + 12'd1, S_CMD);
            end else if (rdata == 8'h80) begin
                rd(ptr[ch] + 12'd1, S_ARG);              // scivolata: il valore
            end else if (rdata[7:4] == 4'h9) begin
                arp[ch] <= rdata[1:0];
                ptr[ch] <= ptr[ch] + 12'd1;
                rd(ptr[ch] + 12'd1, S_CMD);
            end else if (rdata[7:4] == 4'hA || rdata == 8'hB0) begin
                rd(ptr[ch] + 12'd1, S_ARG);              // taglio (8 bit alti) o sua scivolata
            end else if (rdata == 8'hFE) begin
                ptr[ch] <= start[ch];
                rd(start[ch], S_CMD);
            end else begin
                // fine della traccia: la voce tace
                active[ch] <= 1'b0;
                wr(3'd4, 8'h00);
                state <= S_NEXT;
            end
        end

        S_ARG: begin
            if (cmd == 8'h80) begin
                slide[ch] <= rdata;
                ptr[ch] <= ptr[ch] + 12'd2;
                rd(ptr[ch] + 12'd2, S_CMD);
            end else if (cmd[7:4] == 4'hA) begin
                // taglio: si scrive subito, poi il comando dopo
                fcut <= {rdata, cmd[2:0], 5'd0};
                ptr[ch] <= ptr[ch] + 12'd2;
                fstep <= 2'd0;
                flast <= 2'd1;
                fafter <= S_FRD;
                state <= S_FW;
            end else if (cmd == 8'hB0) begin
                fsweep[7:0] <= rdata;                    // scivolata del taglio: basso, poi alto
                rd(ptr[ch] + 12'd2, S_ARG2);
            end else begin
                cnt[ch] <= rdata;
                ptr[ch] <= ptr[ch] + 12'd2;
                if (cmd == 8'h60) begin
                    wr(3'd4, wave[ch]);                  // pausa: gate chiuso
                    state <= S_NEXT;
                end else begin
                    note[ch] <= cmd[6:0];
                    rd(SID_INSTR_BASE + {5'd0, ins[ch], 3'd0}, S_INS);
                end
            end
        end

        S_ARG2: begin
            fsweep[15:8] <= rdata;
            ptr[ch] <= ptr[ch] + 12'd3;
            rd(ptr[ch] + 12'd3, S_CMD);
        end

        // strumento: forma d'onda, attacco/decadimento, sostegno/rilascio, impulso, rilascio,
        // filtro e $D418
        S_INS:  begin wave[ch] <= rdata; rd(SID_INSTR_BASE + {5'd0, ins[ch], 3'd1}, S_INS2); end
        S_INS2: begin wr(3'd5, rdata);   rd(SID_INSTR_BASE + {5'd0, ins[ch], 3'd2}, S_INS3); end
        S_INS3: begin wr(3'd6, rdata);   rd(SID_INSTR_BASE + {5'd0, ins[ch], 3'd3}, S_INS4); end
        S_INS4: begin pw_lo <= rdata;    rd(SID_INSTR_BASE + {5'd0, ins[ch], 3'd4}, S_INS5); end
        S_INS5: begin wr(3'd3, rdata);   rd(SID_INSTR_BASE + {5'd0, ins[ch], 3'd5}, S_INS6); end
        S_INS6: begin
            wr(3'd2, pw_lo);
            rel[ch] <= rdata;
            rd(SID_INSTR_BASE + {5'd0, ins[ch], 3'd6}, S_INS7);
        end
        S_INS7: begin ins_filt <= rdata; rd(SID_INSTR_BASE + {5'd0, ins[ch], 3'd7}, S_INS8); end
        S_INS8: begin
            ins_vm <= rdata;
            freq_write <= 1'b1;
            rd(SID_FREQ_BASE + {4'd0, note[ch], 1'b0}, S_FRQ);
        end

        // frequenza della nota (tabella: byte basso, byte alto)
        // (rallentata: prima il byte alto dimezzato, poi il basso con il bit che scende dall'alto)
        S_FRQ: begin
            freq[ch][7:0] <= rdata;
            if (!half) wr(3'd0, rdata);
            rd(raddr + 12'd1, S_FRQ2);
        end
        S_FRQ2: begin
            freq[ch][15:8] <= rdata;
            wr(3'd1, half ? {1'b0, rdata[7:1]} : rdata);
            state <= half ? S_FRQ3 : freq_write ? S_GATE : S_NEXT;
        end
        S_FRQ3: begin
            wr(3'd0, freq[ch][8:1]);
            state <= freq_write ? S_GATE : S_NEXT;
        end
        S_GATE: begin
            freq_write <= 1'b0;
            wr(3'd4, wave[ch] | 8'h01);                  // gate: parte l'inviluppo
            state <= S_FLT;
        end

        // filtro dello strumento della nota nuova: se $D417 o $D418 cambiano si riscrivono taglio,
        // $D417 e $D418
        S_FLT: begin
            if (ins_filt != 8'd0 && (ins_filt != fres || ins_vm != fvm)) begin
                fres <= ins_filt;
                fvm <= ins_vm;
                fstep <= 2'd0;
                flast <= 2'd3;
                fafter <= S_NEXT;
                state <= S_FW;
            end else
                state <= S_NEXT;
        end

        // nota in corso: arpeggio o scivolata
        S_RUN: begin
            if (arp[ch] != 2'd0)
                rd(SID_FREQ_BASE + {4'd0, note[ch] + arp_ofs(arp[ch], ch == 2'd3 ? fx_phase : phase), 1'b0}, S_FRQ);
            else if (slide[ch] != 8'd0) begin
                // dimezzata come sempre: prima il byte alto, poi il basso
                freq[ch] <= slid;
                wr(half ? 3'd1 : 3'd0, half ? {1'b0, slid[15:9]} : slid[7:0]);
                state <= S_SLIDE;
            end else
                state <= S_NEXT;
        end

        S_SLIDE: begin
            wr(half ? 3'd0 : 3'd1, half ? freq[ch][8:1] : freq[ch][15:8]);
            state <= S_NEXT;
        end

        S_WAIT: state <= after;

        default: begin   // S_NEXT
            if (ch == 2'd3) state <= S_IDLE;
            else begin
                ch <= ch + 2'd1;
                state <= S_CH;
            end
        end
    endcase

    // voce digitalizzata: le sue scritture vengono dopo quelle del player (che intanto non scrive)
    if (reset) begin
        vstate <= V_IDLE;
    end else case (vstate)
        V_IDLE: if (voice_go && voice_len({1'b0, voice_id}) != 12'd0) begin
            vaddr <= voice_start({1'b0, voice_id});
            vleft <= {voice_len({1'b0, voice_id}), 1'b0};
            vlo <= 1'b0;
            vstep <= 4'd0;
            vstate <= V_SETUP;
        end
        // voce 1 spenta, volume a metà (il silenzio), voci 2 e 3 a DC costante (impulso con il bit di
        // test), prima con il gate chiuso: l'attacco parte solo dal fronte del gate; nessuna voce
        // nel filtro (il modo è già spento: $D418 = $08)
        V_SETUP: begin
            we <= 1'b1;
            case (vstep)
                4'd0: begin addr <= 5'h0B; data <= 8'h48; end
                4'd1: begin addr <= 5'h12; data <= 8'h48; end
                4'd2: begin addr <= 5'h04; data <= 8'h00; end
                4'd3: begin addr <= 5'h18; data <= 8'h08; end
                4'd4: begin addr <= 5'h0C; data <= 8'h60; end
                4'd5: begin addr <= 5'h0D; data <= 8'hF4; end
                4'd6: begin addr <= 5'h13; data <= 8'h60; end
                4'd7: begin addr <= 5'h14; data <= 8'hF4; end
                default: begin addr <= 5'h17; data <= 8'h00; end
            endcase
            vstep <= vstep + 4'd1;
            vtimer <= 22'd100;                 // il gate chiuso dura qualche passo del SID (1 MHz)
            if (vstep == 4'd8) begin
                vstep <= 4'd0;
                vstate <= voice_stop ? V_END : V_GATE;
            end
        end
        // gate aperto sulle voci 2 e 3: il DC sale con l'attacco
        V_GATE: begin
            if (vtimer != 22'd0)
                vtimer <= vtimer - 22'd1;
            else begin
                we <= 1'b1;
                addr <= vstep[0] ? 5'h12 : 5'h0B;
                data <= 8'h49;
                vstep <= vstep + 4'd1;
                if (vstep[0]) begin
                    vtimer <= V_PRE_CYCLES;
                    vstate <= V_PRE;
                end
            end
        end
        // il DC sale con l'attacco a volume fermo
        V_PRE: begin
            vtimer <= vtimer - 22'd1;
            if (voice_stop) begin
                vstep <= 4'd0;
                vstate <= V_END;
            end else if (vtimer == 22'd0) begin
                vtimer <= 22'd0;
                vstate <= V_PLAY;
            end
        end
        // un campione ogni V_DIV cicli: il volume del SID
        V_PLAY: begin
            if (voice_stop || vleft == 13'd0) begin
                vstep <= 4'd0;
                vstate <= V_END;
            end else if (vtimer == 22'd0) begin
                we <= 1'b1;
                addr <= 5'h18;
                data <= {4'h0, vlo ? vdata[3:0] : vdata[7:4]};
                if (vlo) vaddr <= vaddr + 15'd1;
                vlo <= !vlo;
                vleft <= vleft - 13'd1;
                vtimer <= V_DIV - 22'd1;
            end else
                vtimer <= vtimer - 22'd1;
        end
        // volume di nuovo a metà, gate chiuso: il DC scende con il rilascio
        V_END: begin
            we <= 1'b1;
            case (vstep)
                4'd0: begin addr <= 5'h18; data <= 8'h08; end
                4'd1: begin addr <= 5'h0B; data <= 8'h48; end
                default: begin addr <= 5'h12; data <= 8'h48; end
            endcase
            vstep <= vstep + 4'd1;
            vtimer <= V_REL_CYCLES;
            if (vstep == 4'd2) vstate <= V_REL;
        end
        V_REL: begin
            vtimer <= vtimer - 22'd1;
            if (vtimer == 22'd0) begin
                vstep <= 4'd0;
                vstate <= V_DONE;
            end
        end
        // voci 2 e 3 spente, volume al massimo: il SID torna al player
        default: begin
            we <= 1'b1;
            case (vstep)
                4'd0: begin addr <= 5'h0B; data <= 8'h00; end
                4'd1: begin addr <= 5'h12; data <= 8'h00; end
                default: begin addr <= 5'h18; data <= 8'h0F; end
            endcase
            vstep <= vstep + 4'd1;
            if (vstep == 4'd2) vstate <= V_IDLE;
        end
    endcase

    // la voce ha il SID: il filtro è spento ($D417 = 0 all'inizio, $D418 = $0F alla fine) e la copia
    // del player resta così, e la prima nota nel filtro dopo la voce lo riscrive tutto
    if (voice_on) begin
        fres <= 8'd0;
        fvm <= 8'h0F;
    end
end

// ------------------------------------------------------------------ voce di partita

// secondo porto di lettura della ROM delle voci (le M10K ne hanno due): nessuna memoria in più
reg [14:0] caddr = 15'd0;
reg [7:0]  cdata = 8'd0;
always @(posedge clk) cdata <= vrom[caddr];

reg [12:0] cleft = 13'd0;         // campioni rimasti
reg [11:0] ctimer = 12'd0;
reg        clo = 1'b0;            // prossimo campione nel nibble basso
initial call_level = 4'd8;

always @(posedge clk) begin
    if (reset) begin
        cleft <= 13'd0;
        call_level <= 4'd8;
    end else if (call_go && voice_len(call_id) != 12'd0) begin
        caddr <= voice_start(call_id);
        cleft <= {voice_len(call_id), 1'b0};
        clo <= 1'b0;
        ctimer <= 12'd2;                // il primo byte: due cicli per la lettura della ROM
    end else if (ctimer != 12'd0) begin
        ctimer <= ctimer - 12'd1;
    end else if (cleft == 13'd0) begin
        call_level <= 4'd8;
    end else begin
        // un campione ogni V_DIV cicli, come la voce del SID
        call_level <= clo ? cdata[3:0] : cdata[7:4];
        if (clo) caddr <= caddr + 15'd1;
        clo <= !clo;
        cleft <= cleft - 13'd1;
        ctimer <= V_DIV[11:0] - 12'd1;
    end
end

wire [17:0] sid_audio;

sid_top #(.MULTI_FILTERS(0), .DUAL(0)) sid (
    .reset(reset),
    .clk(clk),
    .ce_1m(ce_1m),
    .cs(1'b1),
    .we(we),
    .addr(addr),
    .data_in(data),
    .data_out(),
    .fc_offset_l(13'd0),
    .pot_x_l(8'd0),
    .pot_y_l(8'd0),
    .ext_in_l(18'd0),
    .audio_l(sid_audio),
    .fc_offset_r(13'd0),
    .pot_x_r(8'd0),
    .pot_y_r(8'd0),
    .ext_in_r(18'd0),
    .audio_r(),
    .filter_en(1'b1),
    .mode(mode_8580),
    .cfg(2'd0),
    .ld_clk(clk),
    .ld_addr(12'd0),
    .ld_data(16'd0),
    .ld_wr(1'b0)
);

// guadagno 2 (le tre voci insieme arrivano a circa un terzo della scala), con saturazione
assign sample = sid_audio[17] == sid_audio[16] ? sid_audio[16:1] : {sid_audio[17], {15{~sid_audio[17]}}};

endmodule
