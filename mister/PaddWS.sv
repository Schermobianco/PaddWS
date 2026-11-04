//============================================================================
//
//  PADD WS per MiSTer - collegamento tra il core (rtl/pong_top.v) e il framework (sys/).
//  Derivato da Template_MiSTer.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Porte non usate da questo core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign LED_USER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"PaddWS;;",
	"-;",
	"O[13:12],Game type,Classic,EVO,NEXT,Challenge;",
	"O[15:14],Players,Two,One,Vs CPU;",
	"O[25],Super moves,Off,On;",
	"O[7],Free play,Off,On;",
	"O[9:8],Difficulty,Normal,Hard,Expert,Easy;",
	"O[10],Scores,Upright,Facing players;",
	"O[11],Attract sound,On,Off;",
	"O[23],Sound,SID 8580,SID 6581;",
	"O[26],Music,On,Off;",
	"O[27],Autosave scores,On,Off;",
	"O[17:16],White level,100%,87%,75%,62%;",
	"O[19:18],Paddle control,Joystick,Paddle,Spinner;",
	"O[21:20],Spinner speed,Normal,Fast,Faster,Slow;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[6:4],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"J1,Forward,Fast,Select bonus,Use bonus,Start,Coin;",
	"jn,A,B,X,Y,Start,Select;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire        forced_scandoubler;
wire  [1:0] buttons;
wire [127:0] status;
wire [31:0] joy0, joy1;
wire [7:0]  paddle0, paddle1;
wire [8:0]  spinner0, spinner1;
wire [10:0] ps2_key;
wire [21:0] gamma_bus;
// file della NVRAM (classifica di CHALLENGE, indice 4 nel PaddWS.mra)
wire        ioctl_download, ioctl_upload, ioctl_wr, ioctl_upload_req;
wire [15:0] ioctl_index;
wire [26:0] ioctl_addr;
wire [7:0]  ioctl_dout, ioctl_din;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask(16'd0),

	.joystick_0(joy0),
	.joystick_1(joy1),
	.paddle_0(paddle0),
	.paddle_1(paddle1),
	.spinner_0(spinner0),
	.spinner_1(spinner1),
	.ps2_key(ps2_key),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_upload_index(8'd4),
	.ioctl_wait(1'b0)
);

///////////////////////   CLOCK   ////////////////////////////////

// PLL del template: 20 MHz, pixel clock = 20 MHz / 3; seconda uscita a 60 MHz (stesso VCO, fronti
// allineati) per il processore RISC-V della logica di gioco (rtl/pong_logic_rv.v)
wire clk_sys, clk_cpu;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_cpu)
);

///////////////////////   PARTITA   //////////////////////////////

wire [1:0] game_type = status[13:12];      // 0 Classic, 1 EVO, 2 NEXT, 3 CHALLENGE
wire [1:0] players_mode = status[15:14];   // 0 due, 1 uno, 2 contro la CPU (3 da un CFG vecchio: pong_top)
wire free_play = status[7];
wire [1:0] difficulty = status[9:8] + 2'd1;   // l'OSD parte da Normal (0): 0 facile .. 3 esperto
wire upright = !status[10];       // di default dritti: non si presume un tavolo
wire attract_mute = status[11];
wire music_off = status[26];                 // nessuna canzone del SID (effetti e voci sì)
// Sound è il bit 23: un CFG di prima con Samples (bit 24:23 = 2) suona con il SID 8580. Il bit 24
// resta libero ma nei CFG vecchi può valere 1: non va riusato
wire sid_6581 = status[23];
wire super_moves = status[25];               // mosse speciali in NEXT e CHALLENGE (dalla partita successiva)

// cambiare modalità o numero di giocatori riporta all'attract
reg [3:0] mode_q = 4'b0000;
reg       mode_changed = 1'b0;
always @(posedge clk_sys) begin
	mode_q <= status[15:12];
	mode_changed <= mode_q != status[15:12];
end

wire reset = RESET | status[0] | buttons[1] | mode_changed;

wire        ce_pix;
wire [23:0] rgb;
wire       hblank, vblank, hsync, vsync;
wire signed [15:0] audio;

pong_top pong
(
	.clk(clk_sys),
	.clk_cpu(clk_cpu),
	.reset(reset),
	.egg_clear(RESET | status[0] | buttons[1]),   // il cambio di Game type non spegne l'easter egg
	.game_type(game_type),
	.players_mode(players_mode),
	.free_play(free_play),
	.difficulty(difficulty),
	.super_moves(super_moves),
	.upright(upright),
	.attract_mute(attract_mute),
	.music_off(music_off),
	.sid_6581(sid_6581),
	.joy0(joy0),
	.joy1(joy1),
	.ps2_key(ps2_key),
	.control(status[19:18]),
	.spin_speed(status[21:20]),
	.paddle0(paddle0),
	.paddle1(paddle1),
	.spinner0(spinner0),
	.spinner1(spinner1),
	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_upload_req(ioctl_upload_req),
	.nv_autosave(!status[27]),
	.ce_pix(ce_pix),
	.rgb(rgb),
	.hblank(hblank),
	.vblank(vblank),
	.hsync(hsync),
	.vsync(vsync),
	.audio(audio)
);

///////////////////////   VIDEO   ////////////////////////////////

// Luminosità del bianco dall'OSD: tutta l'immagine scala in proporzione, così il grigio resta
// distinguibile dal bianco; solo shift e somme, nessun DSP
wire [1:0] white_level = status[17:16];   // 0 100%, 1 87%, 2 75%, 3 62%
function [7:0] dim(input [7:0] c, input [1:0] lvl);
	case (lvl)
		2'd1: dim = c - (c >> 3);
		2'd2: dim = c - (c >> 2);
		2'd3: dim = (c >> 1) + (c >> 3);
		default: dim = c;
	endcase
endfunction
wire [23:0] rgb_out = {dim(rgb[23:16], white_level), dim(rgb[15:8], white_level), dim(rgb[7:0], white_level)};

arcade_video #(.WIDTH(320), .DW(24)) arcade_video
(
	.clk_video(clk_sys),
	.ce_pix(ce_pix),

	.RGB_in(rgb_out),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hsync),
	.VSync(vsync),

	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_DE(VGA_DE),
	.VGA_SL(VGA_SL),

	.fx(status[6:4]),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus)
);

///////////////////////   AUDIO   ////////////////////////////////

assign AUDIO_S = 1;          // campioni con segno
assign AUDIO_L = audio;
assign AUDIO_R = audio;
assign AUDIO_MIX = 0;

endmodule
