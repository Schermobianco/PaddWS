// Generato da tools/gen_mister_ui.py: non modificare a mano.
localparam integer UI_GFX_WORDS = 15581;
localparam integer UI_GFX_AW = 14;
// prima parte (ui_gfx.hex) e seconda (ui_gfx2.hex, dall'indirizzo 32768)
localparam integer UI_GFX1_WORDS = 15581;
localparam integer UI_GFX2_WORDS = 1;
localparam integer UI_GFX2_AW = 1;
// finestra della DDR3: base nello spazio delle immagini e parole
localparam integer UI_WIN_BASE = 32768;
localparam integer UI_WIN_WORDS = 5184;
// file paddws_gfx.rom (parole a 32 bit)
localparam integer UI_DDR_WORDS = 31544;
