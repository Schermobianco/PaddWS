// Classifica di CHALLENGE sulla SD: la NVRAM dei core arcade del MiSTer.
//
// Il file PaddWS.mra ha <nvram index="4" size="192"/>: all'avvio il MiSTer manda al core il file
// /media/fat/config/nvram/PaddWS.nvm, se c'è, come un download di hps_io con indice 4; per salvarlo
// legge l'immagine dal core con un upload sullo stesso indice. Il salvataggio parte dalla voce
// "Save settings" dell'OSD o, con l'opzione Autosave scores, all'apertura dell'OSD dopo una
// modifica della classifica (`upload_req`, come i core arcade con hiscore.v).
//
// Immagine (192 byte):
//   0-3      "PWS" e la versione del formato (1)
//   4-15     zero
//   16+16*i  posto i (0 = il primo): tre codici del font delle iniziali (la prima lettera per prima),
//            livello raggiunto (0-7, 8 = scala finita), punti (24 bit, dal byte basso), punti in BCD
//            (7 cifre, 4 byte dal basso), cinque byte a zero
//   176-190  zero
//   191      somma di controllo: la somma di tutti i 192 byte, modulo 256, è 0x5A
//
// Un file letto vale solo se arriva intero, con l'intestazione giusta, la somma giusta, i campi
// nei limiti (codici fino a 36 o 40, il "!", livello fino a 8, cifre BCD fino a 9) e i punti in
// ordine non crescente: solo allora passa alla classifica (`ld_go`, un posto alla volta). Altrimenti, e se il
// file manca, resta la classifica iniziale. Il download va prima in una piccola RAM, così un
// file guasto non tocca la classifica.
//
// In upload il byte di `ioctl_addr` esce dalla classifica com'è adesso; la somma di controllo la
// calcola di continuo un contatore che ripassa tutti i byte quando non c'è un upload.

`timescale 1ns / 1ps

module ch_nvram (
    input  wire        clk,
    // hps_io (download e upload di file, 8 bit)
    input  wire        ioctl_download,
    input  wire        ioctl_upload,
    input  wire [15:0] ioctl_index,
    input  wire        ioctl_wr,
    input  wire [26:0] ioctl_addr,
    input  wire [7:0]  ioctl_dout,
    output reg  [7:0]  ioctl_din = 8'd0,
    output wire        upload_req,       // ioctl_upload_req: c'è da salvare (con l'autosave)
    // classifica attuale: 10 posti, il primo nei bit bassi
    input  wire [179:0] names,
    input  wire [239:0] scores,
    input  wire [279:0] bcds,
    input  wire [39:0]  levels,
    input  wire        changed,          // la classifica è cambiata (un posto inserito in partita)
    input  wire        autosave,
    // posto letto dal file, da scrivere nella classifica (senza spostare gli altri)
    output reg         ld_go = 1'b0,
    input  wire        ld_busy,          // la classifica sta già scrivendo: si aspetta
    output reg  [3:0]  ld_at = 4'd0,
    output reg  [17:0] ld_name = 18'd0,
    output reg  [23:0] ld_score = 24'd0,
    output reg  [27:0] ld_bcd = 28'd0,
    output reg  [3:0]  ld_level = 4'd0
);

localparam [7:0] INDEX = 8'd4, SIZE = 8'd192, SUM = 8'h5A, VERSION = 8'd1;

wire mine = ioctl_index[7:0] == INDEX;

// ------------------------------------------------------------------ upload e somma di controllo

reg [7:0] scan = 8'd0, acc = 8'd0, chk = SUM;
wire [7:0] rd_addr = ioctl_upload ? ioctl_addr[7:0] : scan;

// byte `rd_addr` dell'immagine della classifica attuale (senza la somma, che è a parte): prima il
// posto (un multiplexer da 10 a 1 sui 74 bit del posto: iniziali, livello, punti, BCD), poi il byte
reg [73:0] ent;
reg [7:0]  rd_byte;
integer    k;
always @(*) begin
    ent = 74'd0;
    for (k = 0; k < 10; k = k + 1)
        if (rd_addr[7:4] == k + 1)
            ent = {bcds[28 * k +: 28], scores[24 * k +: 24], levels[4 * k +: 4], names[18 * k +: 18]};
    rd_byte = 8'd0;
    if (rd_addr[7:4] == 4'd0)
        case (rd_addr[3:0])
            4'd0: rd_byte = "P";
            4'd1: rd_byte = "W";
            4'd2: rd_byte = "S";
            4'd3: rd_byte = VERSION;
            default: rd_byte = 8'd0;
        endcase
    else
        case (rd_addr[3:0])
            4'd0: rd_byte = {2'd0, ent[5:0]};
            4'd1: rd_byte = {2'd0, ent[11:6]};
            4'd2: rd_byte = {2'd0, ent[17:12]};
            4'd3: rd_byte = {4'd0, ent[21:18]};
            4'd4: rd_byte = ent[29:22];
            4'd5: rd_byte = ent[37:30];
            4'd6: rd_byte = ent[45:38];
            4'd7: rd_byte = ent[53:46];
            4'd8: rd_byte = ent[61:54];
            4'd9: rd_byte = ent[69:62];
            4'd10: rd_byte = {4'd0, ent[73:70]};
            default: rd_byte = 8'd0;
        endcase
end
always @(posedge clk) begin
    ioctl_din <= (ioctl_addr[7:0] == SIZE - 8'd1) ? chk : rd_byte;
    if (!ioctl_upload) begin
        if (scan == SIZE - 8'd2) begin
            chk <= SUM - (acc + rd_byte);
            acc <= 8'd0;
            scan <= 8'd0;
        end else begin
            acc <= acc + rd_byte;
            scan <= scan + 8'd1;
        end
    end
end

// da salvare: dalla modifica all'inizio del salvataggio (una modifica durante un salvataggio
// resta da salvare)
reg dirty = 1'b0, up_q = 1'b0;
always @(posedge clk) begin
    up_q <= ioctl_upload && mine;
    if (changed) dirty <= 1'b1;
    else if (ioctl_upload && mine && !up_q) dirty <= 1'b0;
end
assign upload_req = dirty && autosave;

// ------------------------------------------------------------------ download

reg [7:0] img [0:255];
reg       dl_q = 1'b0, ok = 1'b0;
reg [7:0] sum = 8'd0, last = 8'd0;
reg [23:0] prev = 24'd0;                // punti del posto prima
reg [15:0] lo = 16'd0;                  // byte bassi dei punti del posto in arrivo
wire [7:0] wa = ioctl_addr[7:0];
wire [7:0] wd = ioctl_dout;
wire       in_entry = wa >= 8'd16 && wa < 8'd176;
// il byte in arrivo è nei limiti del suo campo
reg        field_ok;
always @(*) begin
    field_ok = 1'b1;
    if (ioctl_addr[26:8] != 19'd0 || wa >= SIZE) field_ok = 1'b0;
    else if (wa == 8'd0) field_ok = wd == "P";
    else if (wa == 8'd1) field_ok = wd == "W";
    else if (wa == 8'd2) field_ok = wd == "S";
    else if (wa == 8'd3) field_ok = wd == VERSION;
    else if (in_entry)
        case (wa[3:0])
            4'd0, 4'd1, 4'd2: field_ok = wd <= 8'd36 || wd == 8'd40;   // lettere, cifre, spazio, "!"
            4'd3: field_ok = wd <= 8'd8;
            4'd6: field_ok = wa[7:4] == 4'd1 || {wd, lo} <= prev;
            4'd7, 4'd8, 4'd9: field_ok = wd[3:0] <= 4'd9 && wd[7:4] <= 4'd9;
            4'd10: field_ok = wd <= 8'd9;
            default: field_ok = 1'b1;
        endcase
end

// lettura dell'immagine valida verso la classifica: posto `ld_e`, byte `ld_b` (0-10)
reg        ld_run = 1'b0, ld_wait = 1'b0, ld_val = 1'b0;
reg [3:0]  ld_e = 4'd0, ld_b = 4'd0, ld_bq = 4'd0;
reg [7:0]  ld_q = 8'd0;
always @(posedge clk) begin
    ld_q <= img[{ld_e + 4'd1, ld_b}];
end

always @(posedge clk) begin
    dl_q <= ioctl_download && mine;
    ld_go <= 1'b0;
    if (ioctl_download && mine && !dl_q) begin
        ok <= 1'b1;
        sum <= 8'd0;
        last <= 8'd0;
        ld_run <= 1'b0;
        ld_wait <= 1'b0;
        ld_val <= 1'b0;
    end
    if (ioctl_download && mine && ioctl_wr) begin
        if (wa < SIZE && ioctl_addr[26:8] == 19'd0) img[wa] <= wd;
        sum <= sum + wd;
        last <= wa;
        if (!field_ok) ok <= 1'b0;
        if (in_entry && wa[3:0] == 4'd4) lo[7:0] <= wd;
        if (in_entry && wa[3:0] == 4'd5) lo[15:8] <= wd;
        if (in_entry && wa[3:0] == 4'd6) prev <= {wd, lo};
    end
    // fine del download: se l'immagine è buona la si copia nella classifica
    if (!(ioctl_download && mine) && dl_q && ok && sum == SUM && last == SIZE - 8'd1) begin
        ld_run <= 1'b1;
        ld_e <= 4'd0;
        ld_b <= 4'd0;
        ld_val <= 1'b0;
    end
    if (ld_run && !ld_wait) begin
        // un byte per ciclo: quello letto arriva il ciclo dopo (ld_bq)
        ld_val <= 1'b1;
        ld_bq <= ld_b;
        if (ld_b != 4'd11) ld_b <= ld_b + 4'd1;
        if (ld_val)
            case (ld_bq)
                4'd0: ld_name[5:0] <= ld_q[5:0];
                4'd1: ld_name[11:6] <= ld_q[5:0];
                4'd2: ld_name[17:12] <= ld_q[5:0];
                4'd3: ld_level <= ld_q[3:0];
                4'd4: ld_score[7:0] <= ld_q;
                4'd5: ld_score[15:8] <= ld_q;
                4'd6: ld_score[23:16] <= ld_q;
                4'd7: ld_bcd[7:0] <= ld_q;
                4'd8: ld_bcd[15:8] <= ld_q;
                4'd9: ld_bcd[23:16] <= ld_q;
                4'd10: begin
                    ld_bcd[27:24] <= ld_q[3:0];
                    ld_at <= ld_e;
                    ld_wait <= 1'b1;
                end
                default: ;
            endcase
    end
    // posto pronto: si scrive appena la classifica è libera, poi il posto dopo
    if (ld_wait && !ld_busy && !ld_go) begin
        ld_go <= 1'b1;
        ld_wait <= 1'b0;
        ld_val <= 1'b0;
        ld_b <= 4'd0;
        if (ld_e == 4'd9) ld_run <= 1'b0;
        else ld_e <= ld_e + 4'd1;
    end
end

endmodule
