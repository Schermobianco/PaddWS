// Istantanee del core completo con Verilator: segue la sequenza dall'accensione,
// inserisce una moneta, guarda la demo, avvia una partita a un giocatore senza
// toccare la racchetta fino al GAME OVER, e salva in PPM i frame elencati sotto.
// Argomento "up": scritte dritte (opzione OSD "Upright"). Argomento "mute": suoni dell'attract
// spenti dal frame 300 (si contano i cicli con il SID attivo: canzone o effetto), partita a due e
// fine al conto alla rovescia.
// Argomento "music": opzione OSD "Music volume: 0%" dall'accensione, titolo, partita a un giocatore senza
// toccare la racchetta e GAME OVER: si contano i cicli con una canzone del SID (attesi 0) e quelli
// con un effetto (attesi > 0).
// Argomento "next": NEXT contro la CPU; il giocatore sceglie TELEPORT, SMASH e SLOW con il joystick.
// Argomento "warp": come "next" ma più lunga, salva i frame dei primi salti del TELEPORT.
// Argomento "steer": come "warp", ma il giocatore sceglie STEER, TELEPORT e SMASH (salva la scelta
// in pick_*.ppm) e la CPU riceve STEER armato a ogni palla in arrivo: salva i primi due tiri guidati.
// Argomento "kinds": come "next", poi nella scelta della racchetta i tipi dei due lati vengono da
// PONG_KINDS ("4,6" se manca: BLASTER contro GUARDIAN, codici di `PaddleKind`) e il giocatore
// conferma con Y; salva la scelta in kpick_*.ppm e la partita ogni 40 frame in k_*.ppm.
// Argomenti "win" e "winup": partita a due portata a 10-10, salva il GAME OVER con il vincitore
// (punteggi verso i giocatori o dritti).
// Argomenti "paddle" e "spin": partita a un giocatore con la racchetta comandata dal paddle (avanti e
// indietro su tutta la corsa) o dallo spinner (3 passi per frame in un verso, poi nell'altro, poi
// fermo con il joystick su): stampa la posizione attesa e quella della racchetta.
// Prima della partita prova il doppio tocco: su, su di nuovo entro 300 ms -> rapido.
// Argomento "demo": un gettone e nessuno Start; a ogni giro dell'attract l'OSD passa a un'altra
// modalità (NEXT, CHALLENGE, CLASSIC, EVO) e la demo la segue.
// Argomento "supers": NEXT contro la CPU con l'opzione Super moves. Salva la schermata HOW TO PLAY
// col joystick e con la manopola (howto_*.ppm), la salta con Start; in partita il giocatore insegue
// la palla, le barre si riempiono ogni secondo, il giocatore fa la mezzaluna + A (STRAIGHT SHOT) e,
// con la palla in arrivo, avanti-giù-giù/avanti + A (RISING STRIKE, armata per il colpo, che
// s'impenna oltre i 7/8 del campo): salva sup_*.ppm e stampa le mosse.
// Argomento "howto": la schermata HOW TO PLAY delle mosse speciali da subito (niente attract né
// scelte), un giro dell'animazione col joystick, uno con lo spinner e un pezzo col paddle (a ogni cambio
// un frame fuori dalla schermata, così l'animazione riparte): howto_joy_*, howto_spin_* e
// howto_paddle_*.ppm, col numero del frame dall'inizio del giro (circa 260 frame in tutto).
// Argomento "challenge": CHALLENGE contro la CPU, un fotogramma per schermata (ch_*.ppm); nella prima
// presentazione anche le racchette degli avversari di tutti i livelli (ch_lvl1..7.ppm, e due rivolte
// a destra, ch_lvl5_right e ch_lvl6_right).
// Argomento "challenger": CHALLENGE in corso, durante la partita del primo livello gettone e Start sul
// joystick 2: HERE COMES A NEW CHALLENGER!, scelta dello sfidante (solo joystick 2), sfida tra i due
// giocatori automatici vinta dallo sfidante a destra, iniziali del campione (solo joystick 1, il suo
// punteggio si forza alto), poi la scalata riprende con lo sfidante a destra e la CPU a sinistra fino
// al livello superato: salva chl_*.ppm e stampa lato, sfida e punti a ogni cambio di modo.
// In "challenge" e "challenger" si stampa anche la canzone del SID a ogni cambio e, in partita, si
// controlla il tema: quello dell'avversario contro la CPU, silenzio nella sfida tra due giocatori.
// Argomento "bullet": NEXT contro la CPU; il giocatore insegue la palla, riceve un BULLET nella riserva
// (e una capsula BULLET parte verso la CPU) e lo usa con Y con la palla in arrivo ancora nella metà
// della CPU: resta armato finché la palla passa la mezzeria, poi scatta fino alla ribattuta. Salva
// bul_*.ppm ogni 4 frame da armato, nel bullet time e poco dopo, e stampa gli stati del BULLET.
// Argomento "ghost": NEXT contro la CPU; il giocatore insegue la palla (e riceve SLOW armato), la CPU
// riceve GHOST armato a ogni palla verso di sé. Dal primo GHOST la palla risulta potenziata in ogni
// frame (parola visibile del boost), così la coda degli effetti è accesa. Con GHOST in volo salva
// gh1_<frame>.ppm ogni 3 frame e conta i pixel grigi o gialli attorno alla palla, fuori da lei e dal
// suo alone: devono essere zero (niente coda); nei 40 frame dopo GHOST (ghpost_*.ppm) la coda c'è.
// Argomento "nvram": la classifica di CHALLENGE sulla SD (ch_nvram.v) con un hps_io finto. Dal titolo
// manda tre file da scartare (somma sbagliata, punti in ordine crescente, file troncato) e ne rilegge
// ogni volta l'immagine, che deve restare la classifica iniziale; poi un file buono, che deve tornare
// identico, e la classifica (nv_scores.ppm). Controlla anche che senza modifiche non ci sia una
// richiesta di salvataggio; "challenge" controlla che ci sia dopo le iniziali.
// Argomento "ending": il finale della CHALLENGE. Livello 1 vinto (la voce "YOU WIN!" con il GAME OVER),
// poi la presentazione del livello 2 diventa quella dell'ultimo livello (punti forzati a 123456), vinto
// 7-0: niente voce al GAME OVER, poi il finale (modo 15). Salva end_*.ppm in ogni parte; le parti
// lunghe si accorciano portando avanti il contatore del finale (e lo scorrimento dei titoli). In THE END
// Start salta alle iniziali. Stampa le voci "YOU WIN!" (attese 2), la canzone del SID e i punti.
// Argomento "egg": l'easter egg delle iniziali. Dal titolo (giallo) le iniziali di un record forzato:
// il giocatore scrive "WS!" con il joystick (su dalla A porta al "!") e la classifica che segue ha
// giallo e rosso scambiati; poi strisce, logo, titolo, una CHALLENGE (scelta, presentazione del RUSH,
// partita con una capsula BULLET) e di nuovo "WS!", che lo spegne. Salva egg_*.ppm, stampa a ogni
// fotografia i pixel gialli (FFD225) e rossi (E62828) e la canzone del SID (il finale al posto del
// titolo con l'easter egg acceso).
// Dopo lo scenario si possono indicare i frame da salvare al posto di quelli predefiniti, singoli o
// a intervalli ("1300 1400-1420"): la simulazione si ferma all'ultimo. "-f" ignora il checkpoint.
// "-u" mette le scritte dritte (OSD "Scores: Upright", il default del core) in qualunque scenario:
// per le schermate del README.
//
// Checkpoint: al primo frame di partita (modo M_GAME, dopo la scelta dei bonus in NEXT) lo stato
// del modello e di questo programma va in ckpt_<scenario>.bin. Le esecuzioni seguenti ripartono da
// lì se tutti i frame richiesti vengono dopo. La chiave in ckpt_<scenario>.txt è l'hash
// dell'eseguibile, della ROM della musica del SID e dello scenario: cambia a ogni ricompilazione del modello,
// cioè quando cambiano l'RTL o questo file, e allora il checkpoint si rigenera da capo.
//
// Compilazione ed esecuzione: frames.ps1 (da mister/sim/frames, ~3,5 frame al secondo).
// public.vlt rende pubblici solo i segnali usati qui sotto.
//
// Lo stato della partita è nel firmware di pong_logic_rv (il core Rust nella RAM del processore): gli
// scenari lo cambiano con le modifiche di prova del modulo (`patch`, vedi rust/mister-fw/src/map.rs),
// che il firmware applica all'inizio del tick successivo, e aggiornano subito la parola di stato
// visibile (`w`), così il frame che si fotografa in questa riga la mostra già, come quando si
// scrivevano i registri della logica in Verilog.

#include <algorithm>
#include <cctype>
#include <fcntl.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <set>
#include <string>
#include <vector>

#include "Vpong_top.h"
#include "Vpong_top___024root.h"
#include "verilated.h"
#include "verilated_save.h"

static constexpr int W = 320, H = 240;

// clk_cpu (processore di pong_logic_rv) in multipli di clk: 3 = 60 MHz; 2 per il ripiego a 40 MHz
// (-DCPU_RATIO=2 in frames.ps1)
#ifndef CPU_RATIO
#define CPU_RATIO 3
#endif

// campi delle modifiche di prova (rust/mister-fw/src/map.rs) e parole di stato (words.rs)
enum { PATCH_SCORE = 1, PATCH_ARMED, PATCH_RESERVE, PATCH_SELECTED, PATCH_COOLDOWN, PATCH_METER, PATCH_CAPSULE,
       PATCH_CAPSULE_X, PATCH_CAPSULE_Y, PATCH_CAPSULE_VX, PATCH_CAPSULE_VY };
enum { W_SCORES = 14, W_PLAYER0 = 23, W_CAPS = 25, W_SUPER0 = 75 };

// parola di stato i della logica
static uint32_t& word(Vpong_top___024root* r, int i) { return r->pong_top__DOT__logic_core__DOT__w[i]; }

// una modifica di prova per il firmware (al prossimo tick)
static void patch(Vpong_top___024root* r, int field, int index, uint32_t value) {
    auto& n = r->pong_top__DOT__logic_core__DOT__patch_n;
    r->pong_top__DOT__logic_core__DOT__patch[2 * n] = uint32_t(field | index << 8);
    r->pong_top__DOT__logic_core__DOT__patch[2 * n + 1] = value;
    n++;
}

// punteggio di un lato, nel firmware e nella parola visibile
static void set_score(Vpong_top___024root* r, int side, int v) {
    patch(r, PATCH_SCORE, side, v);
    uint32_t& w = word(r, W_SCORES);
    w = side ? (w & 0xFFFF) | uint32_t(v) << 16 : (w & 0xFFFF0000u) | uint32_t(v);
}

// bonus armato di un lato (codice a 4 bit, 8 = nessuno)
static int armed(Vpong_top___024root* r, int side) { return (word(r, W_PLAYER0 + side) >> 16) & 15; }
static void set_armed(Vpong_top___024root* r, int side, int code) {
    patch(r, PATCH_ARMED, side, code);
    uint32_t& w = word(r, W_PLAYER0 + side);
    w = (w & ~0xF0000u) | uint32_t(code) << 16;
}

// barra delle mosse speciali
static int meter(Vpong_top___024root* r, int side) { return word(r, W_SUPER0 + side) & 0xFF; }
static void set_meter(Vpong_top___024root* r, int side, int v) {
    patch(r, PATCH_METER, side, v);
    uint32_t& w = word(r, W_SUPER0 + side);
    w = (w & ~0xFFu) | uint32_t(v);
}

// immagine della NVRAM della classifica (formato in ch_nvram.v): posti {iniziali, punti, livello}
struct NvEntry { const char* name; int score; int level; };
static std::vector<uint8_t> nv_image(const std::vector<NvEntry>& t) {
    std::vector<uint8_t> b(192, 0);
    b[0] = 'P'; b[1] = 'W'; b[2] = 'S'; b[3] = 1;
    for (size_t i = 0; i < t.size() && i < 10; i++) {
        uint8_t* e = &b[16 + 16 * i];
        for (int k = 0; k < 3; k++) {
            const char c = t[i].name[k];
            e[k] = (c >= 'A' && c <= 'Z') ? 10 + (c - 'A') : (c >= '0' && c <= '9') ? c - '0' : 36;
        }
        e[3] = uint8_t(t[i].level);
        for (int k = 0; k < 3; k++) e[4 + k] = uint8_t(t[i].score >> (8 * k));
        uint32_t bcd = 0;
        for (int v = t[i].score, k = 0; k < 7; k++, v /= 10) bcd |= uint32_t(v % 10) << (4 * k);
        for (int k = 0; k < 4; k++) e[7 + k] = uint8_t(bcd >> (8 * k));
    }
    uint8_t sum = 0;
    for (int i = 0; i < 191; i++) sum += b[i];
    b[191] = uint8_t(0x5A - sum);
    return b;
}

// richiesta dalle librerie di Verilator nei programmi senza SystemC
double sc_time_stamp() { return 0; }

// FNV-1a a 64 bit del contenuto di un file, a partire da h; 0 se il file non si legge
static uint64_t hash_file(const std::string& path, uint64_t h) {
    FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) return 0;
    std::vector<unsigned char> buf(1 << 16);
    size_t n;
    while ((n = std::fread(buf.data(), 1, buf.size(), f)) > 0)
        for (size_t i = 0; i < n; i++) h = (h ^ buf[i]) * 0x100000001b3ULL;
    std::fclose(f);
    return h;
}

int main(int argc, char** argv) {
#ifdef _WIN32
    _set_fmode(_O_BINARY);   // VerilatedSave apre i file senza O_BINARY: in modo testo li rovinerebbe
#endif
    Verilated::commandArgs(argc, argv);
    Vpong_top top;
    auto* r = top.rootp;

    std::string arg;
    std::set<int> requested;
    bool fresh = false, upright = false;
    for (int i = 1; i < argc; i++) {
        const std::string a = argv[i];
        int lo, hi;
        if (a == "-f")
            fresh = true;
        else if (a == "-u")
            upright = true;
        else if (!std::isdigit(static_cast<unsigned char>(a[0])))
            arg = a;
        else if (std::sscanf(a.c_str(), "%d-%d", &lo, &hi) == 2)
            for (int n = lo; n <= hi; n++) requested.insert(n);
        else
            requested.insert(std::atoi(a.c_str()));
    }
    const bool mute_test = arg == "mute";
    const bool music_test = arg == "music";
    // "cd" e "cdup": solo fino al conto alla rovescia in singolo, verso il giocatore o dritto
    const bool countdown_only = arg == "cd" || arg == "cdup";
    const bool warp_test = arg == "warp";
    const bool steer_test = arg == "steer";
    const bool ghost_test = arg == "ghost";
    const bool kinds_test = arg == "kinds";
    // "challenge": scelta, presentazione, livello 1 vinto, livello 2 perso, continue scaduto,
    // iniziali e classifica; i punteggi e i tempi lunghi si forzano per fare in fretta
    const bool ch_test = arg == "challenge";
    const bool sup_test = arg == "supers";
    const bool howto_test = arg == "howto";
    const bool chal_test = arg == "challenger";
    const bool bul_test = arg == "bullet";
    const bool end_test = arg == "ending";
    const bool egg_test = arg == "egg";
    int egg_round = 0, egg_paddle = -1, egg_errors = 0;   // "egg": giro delle iniziali, scelta della racchetta, errori
    int end_part = -1, end_at = -1, you_wins = 0;   // "ending": parte del finale, suo inizio, voci "YOU WIN!"
    const bool next_test = arg == "next" || warp_test || steer_test || ghost_test || kinds_test || ch_test || sup_test || chal_test ||
                           bul_test || end_test;
    int ch_at = -1, ch_mode = -1, ch_games = 0;   // "challenge": frame d'inizio del modo, modo, partite
    int ch_voice = 0;                             // "challenge": stato del player della voce del SID
    int sid_song = 0, song_errors = 0;            // "challenge" e "challenger": canzone del SID, errori
    const char* kinds_env = std::getenv("PONG_KINDS");
    const std::string kinds_arg = kinds_env ? kinds_env : "4,6";
    int kind_l = 4, kind_r = 6;
    std::sscanf(kinds_arg.c_str(), "%d,%d", &kind_l, &kind_r);
    int paddle_at = -1, game_at = -1;   // "kinds": inizio della scelta della racchetta e della partita
    int howto_at = -1, qcf_at = -1, dp_at = -1;   // "supers": schermata HOW TO PLAY e gesti
    int bul_at = -1;                              // "bullet": frame in cui il giocatore lo attiva
    int bul_end = -1, bul_state = 0;              // frame in cui finisce, stato al frame prima
    const bool win_test = arg == "win" || arg == "winup";
    const bool paddle_test = arg == "paddle", spin_test = arg == "spin";
    const bool demo_test = arg == "demo";
    const bool nv_test = arg == "nvram";
    int howto_phase = 0, howto_from = 2;          // "howto": 0 joystick, 1 spinner, 2 paddle; inizio del giro
    int over_frames = 0;
    std::set<int> wanted = (mute_test || countdown_only) ? std::set<int>{1650}
                               : (warp_test || steer_test || ghost_test || kinds_test || ch_test || sup_test || chal_test || bul_test || nv_test ||
                                  howto_test || music_test || end_test || egg_test) ? std::set<int>{}
                               : next_test ? std::set<int>{1104, 1136, 1160, 1300, 1700, 2100, 2500, 2900, 3300, 3700}
                                           : std::set<int>{80, 250, 340, 500, 610, 660, 1050, 1650, 1900, 2300, 2400, 2850};
    // "warp", "steer" e "win" saltano l'attract: al frame 2 il core passa direttamente al titolo
    const bool skip_attract = warp_test || steer_test || ghost_test || kinds_test || ch_test || win_test || paddle_test || spin_test ||
                              sup_test || chal_test || bul_test || music_test || end_test;
    const int coin_at = egg_test ? -1 : skip_attract ? 10 : 620,
              start_at = egg_test ? -1 : skip_attract ? 30 : next_test ? 1100 : demo_test ? -1 : 1600;
    int last = (mute_test || countdown_only) ? 1660 : (win_test || music_test) ? 4000 : (warp_test || steer_test || ghost_test || kinds_test || ch_test || sup_test || chal_test || bul_test || end_test) ? 6000
             : demo_test ? 9400 : nv_test ? 60 : egg_test ? 3000 : howto_test ? 400 : next_test ? 3720 : (paddle_test || spin_test) ? start_at + 380 : 2900;
    if (!requested.empty()) {
        wanted = requested;
        last = *requested.rbegin();
    }
    int warps = 0, prev_warp = 0, warp_f = 0;
    int ghosts = 0, prev_ghost = 0, ghost_frames = 0, ghost_px = 0, post_px = 0, post_frames = 0;   // "ghost": GHOST in volo, pixel di coda
    int steers = 0, prev_steer = 0, steer_frames = 0;   // "steer": tiri guidati, guida al frame prima, frame del tiro
    long long loud_muted = 0, loud_coin = 0;   // cicli con il SID attivo con il muto, fuori e dentro il gettone
    long long music_cycles = 0, fx_cycles = 0; // "music": cicli con una canzone del SID e con un effetto
    int enc_prev = 0, pos_prev = 0;   // "paddle" e "spin": valore dato al frame prima, posizione di allora

    // senza input la partita a un giocatore finisce in fretta; NEXT contro la CPU
    // CHALLENGE è il tipo di partita 3 dell'OSD; i giocatori allora non contano
    top.players_mode = (ch_test || chal_test || end_test || egg_test) ? 0 : next_test ? 2 : (mute_test || win_test) ? 0 : 1;
    top.game_type = (ch_test || chal_test || end_test || egg_test) ? 3 : (next_test || howto_test) ? 2 : 0;
    top.free_play = 0;
    top.difficulty = 1;
    top.upright = upright || arg == "up" || arg == "cdup" || arg == "winup";
    top.joy0 = top.joy1 = 0;
    top.ps2_key = 0;
    top.control = paddle_test ? 1 : spin_test ? 2 : 0;
    top.spin_speed = 0;
    top.paddle0 = top.paddle1 = 0;
    top.spinner0 = top.spinner1 = 0;
    top.super_moves = sup_test || howto_test;
    top.music_vol = music_test ? 10 : 0;   // Music volume: 0%
    top.nv_autosave = 1;
    top.ioctl_download = top.ioctl_upload = top.ioctl_wr = 0;
    top.ioctl_index = 0;
    top.ioctl_addr = 0;
    top.ioctl_dout = 0;
    top.reset = 1;   // come il MiSTer al caricamento del core: l'auto-test deve comparire lo stesso

    std::vector<uint8_t> frame(W * H * 3, 0);
    // "nvram": file da mandare (download) o da rileggere (upload), un byte ogni 16 cicli dopo 16 cicli
    // di attesa; byte riletti, immagine iniziale riletta, esito
    const std::vector<NvEntry> nv_table = {{"ACE", 98765, 8}, {"BOB", 87654, 6}, {"CY ", 76543, 6},
                                           {"D2D", 54321, 5}, {"EVE", 43210, 4}, {"FOX", 32100, 3},
                                           {"GUS", 21000, 3}, {"HAL", 12345, 2}, {"IVY", 5000, 1},
                                           {"JO9", 4999, 0}};
    std::vector<uint8_t> nv_data, nv_got(192, 0), nv_default;
    bool nv_on = false, nv_up = false;
    int nv_i = 0, nv_sub = 0, nv_errors = 0;
    auto nv_start = [&](bool up, const std::vector<uint8_t>& data) {
        nv_on = true;
        nv_up = up;
        nv_data = data;
        nv_i = -1;
        nv_sub = 0;
        top.ioctl_index = 4;
        top.ioctl_addr = 0;
        (up ? top.ioctl_upload : top.ioctl_download) = 1;
    };
    int frames = 0, prev_mode = -1;
    long long cycle = 0;

    // variabili di questo programma salvate nel checkpoint insieme al modello
    const auto host_vars = [&](auto&& io) {
        io(&cycle, sizeof cycle); io(&frames, sizeof frames); io(&prev_mode, sizeof prev_mode);
        io(&warps, sizeof warps); io(&prev_warp, sizeof prev_warp); io(&warp_f, sizeof warp_f);
        io(&over_frames, sizeof over_frames);
        io(&loud_muted, sizeof loud_muted); io(&loud_coin, sizeof loud_coin);
        io(&music_cycles, sizeof music_cycles); io(&fx_cycles, sizeof fx_cycles);
        io(&steers, sizeof steers); io(&prev_steer, sizeof prev_steer); io(&steer_frames, sizeof steer_frames);
        io(&enc_prev, sizeof enc_prev); io(&pos_prev, sizeof pos_prev);
        io(&paddle_at, sizeof paddle_at); io(&game_at, sizeof game_at);
        io(&ch_at, sizeof ch_at); io(&ch_mode, sizeof ch_mode); io(&ch_games, sizeof ch_games);
        io(&howto_at, sizeof howto_at); io(&qcf_at, sizeof qcf_at); io(&dp_at, sizeof dp_at);
        io(&bul_at, sizeof bul_at); io(&bul_end, sizeof bul_end); io(&bul_state, sizeof bul_state); io(&ch_voice, sizeof ch_voice);
        io(&sid_song, sizeof sid_song); io(&song_errors, sizeof song_errors);
        io(&end_part, sizeof end_part); io(&end_at, sizeof end_at); io(&you_wins, sizeof you_wins);
        io(&egg_round, sizeof egg_round); io(&egg_paddle, sizeof egg_paddle); io(&egg_errors, sizeof egg_errors);
        io(frame.data(), frame.size());
    };
    const std::string ckpt = "ckpt_" + (arg.empty() ? std::string("base") : arg) +
                             (kinds_test ? "_" + std::to_string(kind_l) + std::to_string(kind_r) : std::string()) +
                             (upright ? "_u" : "");
    uint64_t key = hash_file(argv[0], 0xcbf29ce484222325ULL);
    if (!key) key = hash_file(std::string(argv[0]) + ".exe", 0xcbf29ce484222325ULL);
    key = key ? hash_file("../../rtl/gen/sid_music.hex", key) : 0;
    for (const char c : arg + (kinds_test ? kinds_arg : std::string()))
        key = (key ^ static_cast<unsigned char>(c)) * 0x100000001b3ULL;
    if (!key) std::printf("checkpoint disattivato: eseguibile o ROM della musica illeggibili\n");
    int ckpt_frame = -1;   // frame del checkpoint valido, -1 se manca o non vale più
    if (key && !fresh) {
        if (FILE* f = std::fopen((ckpt + ".txt").c_str(), "r")) {
            unsigned long long k;
            int n;
            if (std::fscanf(f, "%llx %d", &k, &n) == 2 && k == key) ckpt_frame = n;
            std::fclose(f);
        }
    }
    // si riparte dal checkpoint solo se nessun frame richiesto viene prima
    bool ckpt_done = ckpt_frame >= 0 && (wanted.empty() || *wanted.begin() > ckpt_frame);
    bool ckpt_due = false;
    if (ckpt_done) {
        VerilatedRestore is;
        is.open(ckpt + ".bin");
        is >> top;
        host_vars([&](void* p, size_t n) { is.read(p, n); });
        is.close();
        std::printf("ripresa dal checkpoint %s.bin al frame %d\n", ckpt.c_str(), frames);
    }

    while (frames < last) {
        // al primo frame di partita: si salva qui, a fine ciclo di clock e prima delle righe visibili
        if (ckpt_due) {
            ckpt_due = false;
            {
                VerilatedSave os;
                os.open(ckpt + ".bin");
                os << top;
                host_vars([&](void* p, size_t n) { os.write(p, n); });
            }
            if (FILE* f = std::fopen((ckpt + ".txt").c_str(), "w")) {
                std::fprintf(f, "%016llx %d\n", static_cast<unsigned long long>(key), frames);
                std::fclose(f);
            }
            std::printf("checkpoint %s.bin al frame %d\n", ckpt.c_str(), frames);
        }
        top.reset = ++cycle < 400000;   // 20 ms di reset
        top.egg_clear = top.reset;      // come il reset del MiSTer al caricamento del core
        // mezzo ciclo di clk (20 MHz) con i fronti di clk_cpu (60 MHz, CPU_RATIO volte): clk_cpu scende,
        // sale e scende insieme a clk, come le uscite della stessa PLL
        for (int k = 1; k <= CPU_RATIO; k++) {
            top.clk_cpu = (k % 2 == 0);
            if (k == CPU_RATIO) top.clk = 0;
            top.eval();
        }
        if (nv_on) {
            top.ioctl_wr = 0;
            const int n = int(nv_data.size());
            if (nv_i >= 0 && nv_i < n && nv_sub == 0) {
                top.ioctl_addr = nv_i;
                if (!nv_up) {
                    top.ioctl_dout = nv_data[nv_i];
                    top.ioctl_wr = 1;
                }
            }
            if (nv_up && nv_i >= 0 && nv_i < n && nv_sub == 8) nv_got[nv_i] = top.ioctl_din;
            if (++nv_sub == 16) {
                nv_sub = 0;
                if (++nv_i > n) {
                    nv_on = false;
                    top.ioctl_download = top.ioctl_upload = 0;
                }
            }
        }
        const bool ce = top.ce_pix;
        const int hc = r->pong_top__DOT__hc, vc = r->pong_top__DOT__vc;
        if (ce && hc < W && vc < H) {
            const uint32_t c = top.rgb;
            uint8_t* p = &frame[(vc * W + hc) * 3];
            p[0] = c >> 16; p[1] = c >> 8; p[2] = c;
        }
        // canali del player del SID: 0-2 la canzone, 3 gli effetti (dal frame 302: la canzone del
        // titolo si ferma al passo del player dopo il muto)
        const int sid_active = r->pong_top__DOT__sid__DOT__active;
        if (mute_test && frames >= 302 && frames < start_at && sid_active != 0)
            (frames >= coin_at && frames < coin_at + 30 ? loud_coin : loud_muted)++;
        // "ending": la voce "YOU WIN!" parte (impulso di un ciclo)
        if (end_test && r->pong_top__DOT__call_go && r->pong_top__DOT__call_id == 11) {
            you_wins++;
            std::printf("frame %d: voce YOU WIN! nel modo %d\n", frames, int(r->pong_top__DOT__mode));
        }
        if (music_test) {
            if ((sid_active & 7) != 0 || r->pong_top__DOT__sid__DOT__song_q != 0) music_cycles++;
            if (sid_active & 8) fx_cycles++;
        }
        if (ce && hc == 0 && vc == 261) {
            frames++;
            top.attract_mute = mute_test && frames >= 300;
            // "warp": a ogni palla in arrivo, non ancora oltre la mezzeria (anche alla battuta), riceve
            // TELEPORT armato, così salta alla mezzeria (la logica è ferma in questa riga del frame)
            if (warp_test && r->pong_top__DOT__mode == 5 && armed(r, 0) == 8 &&
                int32_t(r->pong_top__DOT__ball_vx) < 0 && int32_t(r->pong_top__DOT__ball_x) >= (W / 2) * 65536)
                set_armed(r, 0, 0);
            // "steer": la CPU di destra riceve STEER armato a ogni palla verso di sé
            const int steer = (r->pong_top__DOT__next_flags >> 5) & 1;
            if (steer_test && r->pong_top__DOT__mode == 5 && armed(r, 1) == 8 &&
                int32_t(r->pong_top__DOT__ball_vx) > 0 && !steer)
                set_armed(r, 1, 6);
            if (steer_test && steer && !prev_steer) {
                steers++;
                steer_frames = 0;
            }
            prev_steer = steer;
            const bool steer_shot = steer_test && steer && steers <= 2 && steer_frames++ % 4 == 0;
            if (steer_test && steers >= 2 && !steer) break;
            // "ghost": GHOST alla CPU, SLOW al giocatore (coda degli effetti); con GHOST in volo, nel frame
            // appena disegnato, pixel grigi o gialli attorno alla palla ma fuori da palla e racchette
            const int ghost = r->pong_top__DOT__next_flags & 1;
            int ghost_joy = 0;
            if (ghost_test && paddle_at < 0 && r->pong_top__DOT__pick_paddle) paddle_at = frames;
            if (ghost_test && r->pong_top__DOT__mode == 5) {
                const int vx = int32_t(r->pong_top__DOT__ball_vx);
                if (armed(r, 1) == 8 && vx > 0 && !ghost) set_armed(r, 1, 4);
                if (armed(r, 0) == 8 && vx < 0) set_armed(r, 0, 2);
                // palla potenziata (parola 4, boost 1,5) nel frame che si fotografa adesso: la coda
                // degli effetti è accesa sempre, con GHOST e dopo
                if (ghosts >= 1 || ghost) word(r, 4) = 0x18000;
                const int by = int32_t(r->pong_top__DOT__ball_y) >> 16, py = int32_t(r->pong_top__DOT__pad0_y) >> 16;
                if (by > py + 4) ghost_joy |= 0x08;
                else if (by < py - 4) ghost_joy |= 0x04;
            }
            if (ghost_test && ghost && !prev_ghost) {
                ghosts++;
                ghost_frames = 0;
            }
            prev_ghost = ghost;
            const bool ghost_shot = ghost_test && ((ghost && ghosts <= 1 && ghost_frames % 3 == 0) || (!ghost && ghosts >= 1 && post_frames % 10 == 0 && post_frames < 40));
            // pixel grigi o gialli (non bianchi) attorno alla palla, fuori dalla palla e dal suo alone, con la
            // palla lontana dalle racchette; con GHOST devono mancare, dopo GHOST (SLOW, boost) di solito no
            auto tail_px = [&]() {
                const int cx = int32_t(r->pong_top__DOT__ball_x) >> 16, cy = H - (int32_t(r->pong_top__DOT__ball_y) >> 16);
                if (cx < 80 || cx > W - 80) return -1;
                int n = 0;
                for (int yy = std::max(30, cy - 40); yy < std::min(H, cy + 40); yy++)
                    for (int xx = cx - 40; xx < cx + 40; xx++) {
                        if (std::abs(xx - cx) <= 12 && std::abs(yy - cy) <= 12) continue;
                        if (xx == W / 2 - 1 || xx == W / 2) continue;   // linea centrale
                        const uint8_t* q = &frame[(yy * W + xx) * 3];
                        if (q[0] != 0 && q[0] != 255 && (q[0] == q[1] || q[0] > q[2] + 40)) n++;
                    }
                return n;
            };
            if (ghost_test && ghost && ghosts <= 1) {
                const int n = tail_px();
                if (n > 0) ghost_px += n;
                ghost_frames++;
            }
            if (ghost_test && !ghost && ghosts >= 1 && post_frames < 40) {
                const int n = tail_px();
                if (n > 0) post_px += n;
                post_frames++;
            }
            if (ghost_test && ghosts >= 1 && !ghost && post_frames >= 40) {
                std::printf("ghost: %d GHOST, pixel di coda attorno alla palla %d (attesi 0); dopo GHOST %d (> 0 se la palla passa al centro del campo)\n",
                            ghosts, ghost_px, post_px);
                break;
            }
            // "win": a partita iniziata il punteggio va a 10-10, il prossimo punto la chiude
            if ((skip_attract || egg_test) && frames == 2) {
                r->pong_top__DOT__mode = 3;   // M_TITLE
                r->pong_top__DOT__mframe = 0;
            }
            // "nvram": file scartati, poi quello buono; ogni volta si rilegge l'immagine
            if (nv_test) {
                if (frames == 2) {
                    r->pong_top__DOT__mode = 3;   // M_TITLE
                    r->pong_top__DOT__mframe = 0;
                }
                const std::vector<uint8_t> good = nv_image(nv_table);
                std::vector<uint8_t> bad_sum = good, ascending, shortened(good.begin(), good.begin() + 100);
                bad_sum[50] ^= 0x01;
                std::vector<NvEntry> asc = nv_table;
                std::swap(asc[3], asc[4]);
                ascending = nv_image(asc);
                auto check = [&](const char* what, const std::vector<uint8_t>& want) {
                    const bool same = nv_got == want;
                    std::printf("nvram, %s: %s\n", what, same ? "OK" : "DIVERSA");
                    if (!same) {
                        nv_errors++;
                        for (int i = 0; i < 192; i++)
                            if (nv_got[i] != want[i]) std::printf("  byte %d: %02x, atteso %02x\n", i, nv_got[i], want[i]);
                    }
                };
                if (frames == 3) nv_start(true, std::vector<uint8_t>(192, 0));
                if (frames == 4) {
                    // classifica iniziale: intestazione, iniziali PWS e somma di controllo giuste
                    nv_default = nv_got;
                    uint8_t sum = 0;
                    for (uint8_t b : nv_got) sum += b;
                    const bool ok = nv_got[0] == 'P' && nv_got[1] == 'W' && nv_got[2] == 'S' && nv_got[3] == 1 &&
                                    nv_got[16] == 25 && nv_got[17] == 32 && nv_got[18] == 28 && sum == 0x5A;
                    std::printf("nvram, classifica iniziale riletta: %s\n", ok ? "OK" : "SBAGLIATA");
                    nv_errors += !ok;
                    nv_start(false, bad_sum);
                }
                if (frames == 5) nv_start(true, std::vector<uint8_t>(192, 0));
                if (frames == 6) { check("somma sbagliata scartata", nv_default); nv_start(false, ascending); }
                if (frames == 7) nv_start(true, std::vector<uint8_t>(192, 0));
                if (frames == 8) { check("punti in ordine crescente scartati", nv_default); nv_start(false, shortened); }
                if (frames == 9) nv_start(true, std::vector<uint8_t>(192, 0));
                if (frames == 10) { check("file troncato scartato", nv_default); nv_start(false, good); }
                if (frames == 11) nv_start(true, std::vector<uint8_t>(192, 0));
                if (frames == 12) {
                    check("file buono riletto identico", good);
                    const int req = top.ioctl_upload_req;
                    std::printf("nvram, richiesta di salvataggio senza modifiche: %d (attesa 0)\n", req);
                    nv_errors += req != 0;
                }
                if (frames == 30) {
                    r->pong_top__DOT__mode = 12;   // M_SCORES
                    r->pong_top__DOT__mframe = 0;
                }
                if (frames == 50) {
                    FILE* f = std::fopen("nv_scores.ppm", "wb");
                    std::fprintf(f, "P6\n%d %d\n255\n", W, H);
                    std::fwrite(frame.data(), 1, frame.size(), f);
                    std::fclose(f);
                    std::printf("nvram: %d errori (attesi 0)\n", nv_errors);
                    break;
                }
            }
            if (win_test && frames == start_at + 400) {
                set_score(r, 0, 10);
                set_score(r, 1, 10);
            }
            if (music_test && r->pong_top__DOT__mode == 6 && ++over_frames == 120) break;
            if (win_test && r->pong_top__DOT__mode == 6 && ++over_frames == 30) {
                const std::string name = "win_" + arg + ".ppm";
                FILE* f = std::fopen(name.c_str(), "wb");
                std::fprintf(f, "P6\n%d %d\n255\n", W, H);
                std::fwrite(frame.data(), 1, frame.size(), f);
                std::fclose(f);
                break;
            }
            const int warp = r->pong_top__DOT__warp_on;
            if (warp_test && std::getenv("WARP_DEBUG") && frames % 20 == 0 && frames > start_at + 130)
                std::printf("f%d modo %d armato %d x %d vx %d warp %d\n", frames, int(r->pong_top__DOT__mode),
                            armed(r, 0), int(int32_t(r->pong_top__DOT__ball_x)) >> 16,
                            int(int32_t(r->pong_top__DOT__ball_vx)), warp);
            // salto del TELEPORT: un fotogramma ogni 2 finché la racchetta non è uscita, per 3 salti
            if (warp_test && warp && !prev_warp) {
                warps++;
                warp_f = 0;
            }
            const bool warp_end = warp_test && !warp && prev_warp;
            prev_warp = warp;
            const bool warp_shot = warp_test && warps <= 3 && warps > 0 && (warp || warp_end) && warp_f % 2 == 0;
            if (warp_test && warps >= 3 && warp_end) break;
            const bool pick_shot = steer_test && (frames == start_at + 25 || frames == start_at + 75);
            // "kinds": tipi imposti all'inizio della scelta della racchetta, poi A del giocatore
            if (kinds_test && paddle_at < 0 && r->pong_top__DOT__pick_paddle) paddle_at = frames;
            if (kinds_test && paddle_at >= 0 && frames == paddle_at + 5) {
                r->pong_top__DOT__kind_cur[0] = kind_l;
                r->pong_top__DOT__kind_cur[1] = kind_r;
            }
            if (kinds_test && game_at < 0 && r->pong_top__DOT__mode == 5) game_at = frames;
            const bool kpick_shot = kinds_test && paddle_at >= 0 && (frames == paddle_at + 20 || frames == paddle_at + 40);
            const bool kgame_shot = kinds_test && game_at >= 0 && frames > game_at + 180 &&
                                    ((frames - game_at) % 40 == 0 || (frames - game_at <= 480 && (frames - game_at) % 10 == 0));
            if (kinds_test && game_at >= 0 && frames > game_at + 1000) break;
            // "challenge": un fotogramma per schermata, poi si passa oltre
            bool ch_shot = false;
            std::string ch_name;
            if (ch_test) {
                const int m = r->pong_top__DOT__mode;
                if (m != ch_mode) {
                    ch_mode = m;
                    ch_at = frames;
                    if (m == 5) ch_games++;
                }
                const int t = frames - ch_at;
                // voce del SID nella presentazione (nome dell'avversario): stato del suo player a ogni
                // cambio (1 preparazione, 7 gate, 2 attacco, 3 campioni, 4-6 chiusura, 0 fermo)
                const int vs = r->pong_top__DOT__sid__DOT__vstate;
                if (vs != ch_voice) {
                    std::printf("frame %d: modo %d (frame %d del modo), voce del SID nello stato %d\n", frames, m, t, vs);
                    ch_voice = vs;
                }
                if (paddle_at < 0 && r->pong_top__DOT__pick_paddle) paddle_at = frames;
                if (m == 8 && t == 65) { ch_shot = true; ch_name = "ch_intro" + std::to_string(ch_games + 1); }
                // nella prima presentazione anche gli avversari degli altri livelli (uno per tipo di
                // racchetta, livello impostato un frame prima della fotografia) e due con il giocatore a
                // destra (racchetta rivolta a destra); poi il livello 1 e il lato sinistro come prima
                if (m == 8 && ch_games == 0 && t >= 66 && t < 84 && t % 2 == 0) {
                    const int k = (t - 66) / 2;
                    r->pong_top__DOT__ch_level = k < 7 ? k : k == 7 ? 4 : 5;
                    r->pong_top__DOT__ch_side = k >= 7;
                }
                if (m == 8 && ch_games == 0 && t >= 67 && t < 85 && t % 2 == 1) {
                    const int k = (t - 67) / 2;
                    ch_shot = true;
                    ch_name = k < 7 ? "ch_lvl" + std::to_string(k + 1) : "ch_lvl" + std::to_string(k == 7 ? 5 : 6) + "_right";
                }
                if (m == 8 && ch_games == 0 && t == 85) {
                    r->pong_top__DOT__ch_level = 0;
                    r->pong_top__DOT__ch_side = 0;
                }
                if (m == 5 && t == 1) r->pong_top__DOT__mframe = 179;          // niente conto alla rovescia
                if (m == 5 && t == 60) { ch_shot = true; ch_name = "ch_game" + std::to_string(ch_games); }
                if (m == 5 && t == 70) {
                    // primo livello vinto, secondo perso
                    if (ch_games == 1) set_score(r, 0, 7);
                    else set_score(r, 1, 7);
                }
                if (m == 6 && t == 3) { ch_shot = true; ch_name = "ch_over" + std::to_string(ch_games); }  // perso: solo CPU WINS
                if (m == 6 && t == 5) r->pong_top__DOT__mframe = 175;          // GAME OVER breve
                if (m == 9 && t == 65) { ch_shot = true; ch_name = "ch_clear"; }
                if (m == 10 && t == 65) { ch_shot = true; ch_name = "ch_continue"; }
                if (m == 10 && t == 70) r->pong_top__DOT__mframe = 595;        // continue scaduto
                if (m == 10 && t == 80) { ch_shot = true; ch_name = "ch_cont_over"; }  // poi GAME OVER
                if (m == 10 && t == 81) r->pong_top__DOT__mframe = 175;        // GAME OVER breve
                if (m == 11 && (t == 20 || t == 75)) { ch_shot = true; ch_name = "ch_initials" + std::to_string(t); }
                if (m == 12 && t == 30) { ch_shot = true; ch_name = "ch_scores"; }
                if (m == 12 && t == 31) break;
            }
            // "supers": HOW TO PLAY con il joystick e con la manopola, poi Start; in partita barre piene
            // ogni secondo, mezzaluna + A e, con la palla vicina, avanti-giù-giù/avanti + A
            bool sup_shot = false;
            std::string sup_name;
            int sup_joy = 0;
            if (sup_test) {
                const int m = r->pong_top__DOT__mode;
                if (paddle_at < 0 && r->pong_top__DOT__pick_paddle) paddle_at = frames;
                if (m == 13 && howto_at < 0) howto_at = frames;
                if (m == 13) {
                    const int t = frames - howto_at;
                    top.control = (t >= 35 && t < 50) ? 2 : 0;
                    if (t == 30 || t == 45 || t == 55) {
                        sup_shot = true;
                        sup_name = t == 30 ? "howto_joy" : t == 45 ? "howto_knob" : "howto_skip";
                    }
                    if (t == 60) sup_joy = 0x100;    // Start salta la schermata
                }
                if (m == 5 && game_at < 0) game_at = frames;
                if (m == 5 && frames == game_at + 1) r->pong_top__DOT__mframe = 179;   // niente conto alla rovescia
                if (m == 5 && game_at >= 0) {
                    const int t = frames - game_at;
                    // il giocatore insegue la palla (y verso l'alto nella logica): anche con RISING STRIKE
                    // armata, che vale per il colpo successivo
                    const int by = int32_t(r->pong_top__DOT__ball_y) >> 16, py = int32_t(r->pong_top__DOT__pad0_y) >> 16;
                    if (by > py + 4) sup_joy |= 0x08;
                    else if (by < py - 4) sup_joy |= 0x04;
                    if (t % 60 == 0) {
                        set_meter(r, 0, 64);
                        set_meter(r, 1, 64);
                    }
                    // mezzaluna + A: giù, giù-avanti, avanti, avanti + A
                    if (qcf_at < 0 && t >= 120 && int32_t(r->pong_top__DOT__ball_vx) > 0) qcf_at = frames;
                    if (qcf_at >= 0) {
                        const int q = frames - qcf_at;
                        if (q < 3) sup_joy = 0x04;
                        else if (q < 6) sup_joy = 0x05;
                        else if (q < 8) sup_joy = 0x01;
                        else if (q == 8) sup_joy = 0x11;
                    }
                    // avanti, giù, giù-avanti + A con la palla vicina e la racchetta lontana da lei
                    const int bx = int32_t(r->pong_top__DOT__ball_x) >> 16;
                    if (dp_at < 0 && qcf_at >= 0 && frames > qcf_at + 300 && int32_t(r->pong_top__DOT__ball_vx) < 0 &&
                        bx < 110 && bx > 60)
                        dp_at = frames;
                    if (dp_at >= 0) {
                        const int q = frames - dp_at;
                        if (q < 3) sup_joy = 0x01;
                        else if (q < 6) sup_joy = 0x04;
                        else if (q < 8) sup_joy = 0x05;
                        else if (q == 8) sup_joy = 0x15;
                    }
                    if (qcf_at >= 0 && frames - qcf_at <= 120 && (frames - qcf_at) % 4 == 0) {
                        sup_shot = true;
                        sup_name = "sup_q" + std::to_string(frames - qcf_at);
                    }
                    // RISING STRIKE armata, il colpo e l'impennata oltre i 7/8 del campo (livello 2)
                    if (dp_at >= 0 && frames - dp_at <= 160 && (frames - dp_at) % 4 == 0) {
                        sup_shot = true;
                        sup_name = "sup_r" + std::to_string(frames - dp_at);
                    }
                    if (t % 40 == 0) { sup_shot = true; sup_name = "sup_t" + std::to_string(t); }
                    const int lm = r->pong_top__DOT__label_move, lf = r->pong_top__DOT__label_frames;
                    if (lm && (lf == 72 || lf == 48))
                        std::printf("frame %d: mossa %d (scritta %d frame), barre %d %d\n", frames, lm, lf,
                                    meter(r, 0), meter(r, 1));
                    if (dp_at >= 0 && frames > dp_at + 400) break;
                }
            }
            // "howto": HOW TO PLAY dal frame 2; i giri dell'animazione durano 145 frame col joystick e 132
            // con la manopola (moves_ui.rs a 60 Hz)
            bool ht_shot = false;
            std::string ht_name;
            if (howto_test) {
                static const int joy_at[] = {4, 17, 30, 43, 48, 56, 66, 110};
                static const int knob_at[] = {4, 17, 30, 35, 44, 56, 100};
                static const char* names[] = {"joy", "spin", "paddle"};
                if (frames == howto_from) {
                    r->pong_top__DOT__mode = 13;   // M_HOWTO
                    r->pong_top__DOT__mframe = 0;
                }
                const int t = frames - howto_from;
                top.control = howto_phase == 0 ? 0 : howto_phase == 1 ? 2 : 1;
                for (const int a : howto_phase == 0 ? std::vector<int>(joy_at, joy_at + 8) : std::vector<int>(knob_at, knob_at + 7))
                    if (t == a && (howto_phase < 2 || a == 44)) {
                        char nm[40];
                        std::snprintf(nm, sizeof nm, "howto_%s_%03d", names[howto_phase], t);
                        ht_shot = true;
                        ht_name = nm;
                    }
                if ((howto_phase == 0 && t == 112) || (howto_phase == 1 && t == 101)) {
                    r->pong_top__DOT__mode = 3;    // un frame di titolo: l'animazione riparte da capo
                    howto_phase++;
                    howto_from = frames + 1;
                }
                if (howto_phase == 2 && t == 45) break;
            }
            // "bullet": il giocatore insegue la palla; BULLET nella riserva e capsula BULLET verso la CPU,
            // poi Y con la palla in arrivo
            bool bul_shot = false;
            std::string bul_name;
            int bul_joy = 0;
            if (bul_test) {
                const int m = r->pong_top__DOT__mode;
                if (paddle_at < 0 && r->pong_top__DOT__pick_paddle) paddle_at = frames;
                if (m == 5 && game_at < 0) game_at = frames;
                if (m == 5 && frames == game_at + 1) r->pong_top__DOT__mframe = 179;   // niente conto alla rovescia
                if (m == 5 && game_at >= 0) {
                    const int t = frames - game_at;
                    const int by = int32_t(r->pong_top__DOT__ball_y) >> 16, py = int32_t(r->pong_top__DOT__pad0_y) >> 16;
                    if (by > py + 4) bul_joy |= 0x08;
                    else if (by < py - 4) bul_joy |= 0x04;
                    auto& lg = *r;
                    if (t == 200) {
                        // codici a 4 bit: 7 BULLET, 1 SMASH, 8 posto vuoto; selezionato il primo
                        const int res[3] = {7, 1, 8};
                        for (int k = 0; k < 3; k++) patch(r, PATCH_RESERVE, k, res[k]);
                        patch(r, PATCH_SELECTED, 0, 0);
                        patch(r, PATCH_ARMED, 0, 8);
                        patch(r, PATCH_COOLDOWN, 0, 0);
                        // parola del giocatore: riserva, selezionato, armato e pausa (resta l'animazione)
                        word(r, W_PLAYER0) = (word(r, W_PLAYER0) & 0xC000u) | 7u | 1u << 4 | 8u << 8 | 8u << 16;
                        // capsula BULLET dalla mezzeria verso la CPU (P_CAPSULE_SPEED, P_CAPSULE_DRIFT)
                        const uint32_t cap[4] = {uint32_t(W / 2) << 16, 70u << 16, 18432u, 2212u};
                        patch(r, PATCH_CAPSULE, 3, 7);
                        for (int k = 0; k < 4; k++) {
                            patch(r, PATCH_CAPSULE_X + k, 3, cap[k]);
                            word(r, W_CAPS + 15 + k) = cap[k];
                        }
                        word(r, W_CAPS + 19) = 8 | 7;
                    }
                    if (bul_at < 0 && t > 200 && lg.pong_top__DOT__serve_timer == 0 &&
                        int32_t(r->pong_top__DOT__ball_vx) < 0 && (int32_t(r->pong_top__DOT__ball_x) >> 16) < 240 &&
                        (int32_t(r->pong_top__DOT__ball_x) >> 16) > W / 2 + 20) {
                        bul_joy |= 0x80;
                        bul_at = frames;
                    }
                    // stato del BULLET: 0 spento, 1 armato, 2 scattato (bit 11 e 13 della parola 22)
                    const int flags = r->pong_top__DOT__next_flags;
                    const int bst = ((flags >> 13) & 1) ? 2 : ((flags >> 11) & 1) ? 1 : 0;
                    if (bul_at >= 0 && bst == 0 && bul_state != 0 && bul_end < 0) bul_end = frames;
                    if (bul_at >= 0 && (frames - bul_at) % 4 == 0 && (bul_end < 0 || frames - bul_end <= 8)) {
                        bul_shot = true;
                        char nm[32];
                        std::snprintf(nm, sizeof nm, "bul_%03d", frames - bul_at);
                        bul_name = nm;
                    }
                    if (bul_at >= 0 && (bst != bul_state || (frames - bul_at) % 20 == 2))
                        std::printf("frame %d (+%d): BULLET %s, rampa %d, lato %d, palla x %d, riserva %d %d %d\n", frames,
                                    frames - bul_at, bst == 2 ? "scattato" : bst == 1 ? "armato" : "spento",
                                    int(lg.pong_top__DOT__bullet_timer), int((flags >> 12) & 1),
                                    int32_t(r->pong_top__DOT__ball_x) >> 16,
                                    int(word(r, W_PLAYER0) & 15), int((word(r, W_PLAYER0) >> 4) & 15),
                                    int((word(r, W_PLAYER0) >> 8) & 15));
                    if (bul_at >= 0) bul_state = bst;
                    if (bul_at >= 0 && ((bul_end >= 0 && frames > bul_end + 10) || frames > bul_at + 600)) break;
                }
            }
            // "challenger": i giocatori automatici inseguono la palla (y verso l'alto nella logica)
            bool chal_shot = false;
            std::string chal_name;
            int chal_joy0 = 0, chal_joy1 = 0;
            if (chal_test) {
                const int m = r->pong_top__DOT__mode;
                if (m != ch_mode) {
                    ch_mode = m;
                    ch_at = frames;
                    if (m == 5) ch_games++;
                    std::printf("frame %d: modo %d, campione a %s, sfida %d, punti %d, bonus %02x %02x\n", frames, m,
                                r->pong_top__DOT__ch_side ? "destra" : "sinistra", int(r->pong_top__DOT__duel),
                                int(r->pong_top__DOT__ch_score), int(r->pong_top__DOT__pick_mask[0]),
                                int(r->pong_top__DOT__pick_mask[1]));
                }
                const int t = frames - ch_at;
                const int by = int32_t(r->pong_top__DOT__ball_y) >> 16;
                const int py0 = int32_t(r->pong_top__DOT__pad0_y) >> 16, py1 = int32_t(r->pong_top__DOT__pad1_y) >> 16;
                const int follow0 = by > py0 + 4 ? 0x08 : by < py0 - 4 ? 0x04 : 0;
                const int follow1 = by > py1 + 4 ? 0x08 : by < py1 - 4 ? 0x04 : 0;
                if (paddle_at < 0 && r->pong_top__DOT__pick_paddle) paddle_at = frames;
                if (m == 5 && t == 1) r->pong_top__DOT__mframe = 179;          // niente conto alla rovescia
                if (m == 5 && ch_games == 1) {
                    // primo livello: il campione a sinistra; poi gettone e Start del secondo giocatore
                    chal_joy0 = follow0;
                    if (t == 60) { chal_shot = true; chal_name = "chl_game1"; }
                    if (t == 80) { r->pong_top__DOT__ch_score = 25000; chal_joy1 = 0x200; }
                    if (t == 90) chal_joy1 = 0x100;
                }
                if (m == 14 && (t == 4 || t == 12 || t == 100)) {
                    chal_shot = true;
                    chal_name = "chl_new" + std::to_string(t);
                }
                if (m == 7 && r->pong_top__DOT__duel) {
                    // scelta dello sfidante col joystick 2 (il joystick 1 prova a cambiare quella del campione)
                    if (!r->pong_top__DOT__pick_paddle) {
                        if (t == 10 || t == 30 || t == 50) chal_joy1 = 0x04;
                        if (t == 20 || t == 40 || t == 60) chal_joy1 = 0x10;
                        if (t == 25) chal_joy0 = 0x10;
                        if (t == 45) { chal_shot = true; chal_name = "chl_pick"; }
                    } else {
                        if (game_at < 0) game_at = frames;
                        const int q = frames - game_at;
                        if (q == 10 || q == 20) chal_joy1 = 0x04;
                        if (q == 25) { chal_shot = true; chal_name = "chl_kind"; }
                        if (q == 30) chal_joy1 = 0x10;
                    }
                }
                if (m == 5 && ch_games == 2) {
                    // sfida: tutti e due inseguono la palla, poi lo sfidante a destra la vince
                    chal_joy0 = follow0;
                    chal_joy1 = follow1;
                    if (t == 60) { chal_shot = true; chal_name = "chl_duel"; }
                    if (t == 120) {
                        set_score(r, 0, 3);
                        set_score(r, 1, 5);
                    }
                }
                if (m == 6 && ch_games == 2 && t == 30) { chal_shot = true; chal_name = "chl_duel_over"; }
                if (m == 6 && t == 35) r->pong_top__DOT__mframe = 175;         // GAME OVER breve
                if (m == 11) {
                    // iniziali del campione: il joystick 2 non conta, il joystick 1 conferma tre lettere
                    if (t == 25) chal_joy1 = 0x10;
                    if (t == 28) std::printf("iniziali: lettera %d dopo A sul joystick 2 (attesa 0)\n",
                                             int(r->pong_top__DOT__ch_pos));
                    if (t == 30 || t == 50 || t == 60) chal_joy0 = 0x10;
                    if (t == 40) chal_joy0 = 0x04;
                    if (t == 45) { chal_shot = true; chal_name = "chl_initials"; }
                }
                if (m == 8 && ch_games >= 2) {
                    if (t == 65) { chal_shot = true; chal_name = "chl_intro2"; }
                    if (t == 70) chal_joy1 = 0x10;
                }
                if (m == 5 && ch_games == 3) {
                    // la scalata riprende: lo sfidante a destra, la CPU a sinistra
                    chal_joy1 = follow1;
                    if (t % 40 == 0) std::printf("frame %d: CPU a sinistra y %d, giocatore a destra y %d, palla y %d, punti %d\n",
                                                 frames, py0, py1, by, int(r->pong_top__DOT__ch_score));
                    if (t == 60 || t == 200 || t == 400) { chal_shot = true; chal_name = "chl_right" + std::to_string(t); }
                    if (t == 420) set_score(r, 1, 5);
                }
                if (m == 6 && ch_games == 3 && t == 20) { chal_shot = true; chal_name = "chl_right_over"; }
                if (m == 9 && t == 65) { chal_shot = true; chal_name = "chl_clear"; }
                if (m == 9 && t == 66) break;
            }
            // "ending": livello 1 vinto, poi l'ultimo livello vinto e il finale
            bool end_shot = false;
            std::string end_name;
            int end_joy = 0;
            if (end_test) {
                const int m = r->pong_top__DOT__mode;
                if (m != ch_mode) {
                    ch_mode = m;
                    ch_at = frames;
                    if (m == 5) ch_games++;
                    std::printf("frame %d: modo %d, livello %d, punti %d\n", frames, m, int(r->pong_top__DOT__ch_level) + 1,
                                int(r->pong_top__DOT__ch_score));
                }
                const int t = frames - ch_at;
                if (paddle_at < 0 && r->pong_top__DOT__pick_paddle) paddle_at = frames;
                if ((m == 8 || m == 9) && t == 70) end_joy = 0x10;                 // A salta la schermata
                if (m == 8 && ch_games == 1 && t == 2) {
                    // la seconda presentazione diventa quella dell'ultimo livello
                    r->pong_top__DOT__ch_level = 6;
                    r->pong_top__DOT__ch_score = 123456;
                }
                if (m == 5 && t == 1) r->pong_top__DOT__mframe = 179;          // niente conto alla rovescia
                if (m == 5 && t == 70) set_score(r, 0, 7);                      // vinto, senza punti della CPU
                if (m == 6 && t == 5) r->pong_top__DOT__mframe = 175;          // GAME OVER breve
                if (m == 6 && t == 4) { end_shot = true; end_name = "end_gameover" + std::to_string(ch_games); }
                if (m == 15) {
                    auto& e = *r;
                    const int part = e.pong_top__DOT__ending_draw__DOT__part, pf = e.pong_top__DOT__ending_draw__DOT__pf;
                    if (part != end_part) {
                        end_part = part;
                        end_at = frames;
                        std::printf("frame %d: parte %d del finale; punti %d + premio %d\n", frames, part,
                                    int(e.pong_top__DOT__end_score), int(e.pong_top__DOT__end_bonus));
                    }
                    // fotografie: (parte, frame della parte)
                    static const int shots[][2] = {{0, 20}, {0, 75}, {1, 35}, {1, 215}, {1, 430}, {2, 90}, {2, 200},
                                                   {2, 300}, {3, 30}, {3, 100}, {3, 170}, {3, 240}, {3, 330},
                                                   {4, 30}, {4, 42}, {4, 52}, {4, 62}, {5, 20}, {5, 45}};
                    for (const auto& sh : shots)
                        if (sh[0] == part && sh[1] == pf) {
                            end_shot = true;
                            end_name = "end_p" + std::to_string(part) + "_" + std::to_string(pf);
                        }
                    // parti accorciate: il contatore a due frame dalla fine (i fuochi si disegnano
                    // nell'ultimo frame del punteggio); i titoli a scorrimento fissato
                    static const int cut[6] = {80, 432, 302, 332, 64, -1};
                    static const int len[6] = {210, 540, 540, 420, 1526, 180};
                    if (cut[part] >= 0 && pf == cut[part]) e.pong_top__DOT__ending_draw__DOT__pf = len[part] - 2;
                    if (part == 4 && (pf == 40 || pf == 50 || pf == 60))
                        e.pong_top__DOT__ending_draw__DOT__scroll = pf == 40 ? 250 : pf == 50 ? 500 : 820;
                    if (part == 5 && pf == 60) end_joy = 0x100;                    // Start salta alle iniziali
                }
                if (m == 11 && t == 20) { end_shot = true; end_name = "end_initials"; }
                if (m == 11 && t == 21) break;
            }
            // "egg": iniziali "WS!" (accende), giro dell'attract e una CHALLENGE, di nuovo "WS!" (spegne)
            bool egg_shot = false;
            std::string egg_name;
            int egg_joy = 0;
            if (egg_test) {
                const int m = r->pong_top__DOT__mode;
                if (m != ch_mode) {
                    ch_mode = m;
                    ch_at = frames;
                }
                const int t = frames - ch_at;
                // iniziali di un record forzato (50000 punti, primo posto), dalla A
                if ((egg_round == 0 && frames == 25) || (egg_round == 1 && m == 5 && t == 110)) {
                    r->pong_top__DOT__ch_best_r = 50000;
                    r->pong_top__DOT__ch_active = 0;
                    r->pong_top__DOT__mode = 11;   // M_INITIALS
                    r->pong_top__DOT__mframe = 0;
                    r->pong_top__DOT__ch_pos = 0;
                    r->pong_top__DOT__ch_letter = 0;
                    egg_round++;
                }
                // "WS!" con il joystick: lettere 0-25 A-Z, 26-35 cifre, 36 spazio, 37 "!". Dalla A 16 volte
                // su (passando dal "!") fino alla W, A; 4 su fino alla S, A; 19 su fino al "!", A (un
                // frame premuto e uno lasciato)
                if (m == 11) {
                    static const int ups[3] = {16, 4, 19};
                    int at = 10;
                    for (int k = 0; k < 3; k++) {
                        if (t >= at && t < at + 2 * ups[k] && (t - at) % 2 == 0) egg_joy |= 0x08;
                        at += 2 * ups[k] + 2;
                        if (t == at) egg_joy |= 0x10;
                        if (k == 2 && t == at - 1 && egg_round == 1) { egg_shot = true; egg_name = "egg_initials"; }
                        at += 4;
                    }
                }
                const int egg_on = r->pong_top__DOT__egg;
                if (egg_round == 0 && frames == 20) { egg_shot = true; egg_name = "egg_title_off"; }
                if (m == 12 && t == 30) {
                    egg_shot = true;
                    egg_name = egg_round == 1 ? "egg_scores_on" : "egg_scores_off";
                    const int want = egg_round == 1;
                    std::printf("frame %d: easter egg %d dopo il giro %d delle iniziali (atteso %d)\n", frames, egg_on,
                                egg_round, want);
                    egg_errors += egg_on != want;
                }
                if (m == 12 && t == 31) {
                    if (egg_round == 2) break;
                    r->pong_top__DOT__mframe = 478;   // classifica breve, poi le strisce
                }
                if (m == 1 && t == 100) { egg_shot = true; egg_name = "egg_stripes"; }
                if (m == 2 && t == 100) { egg_shot = true; egg_name = "egg_logo"; }
                if (m == 3 && egg_round == 1 && t == 60) { egg_shot = true; egg_name = "egg_title_on"; }
                if (m == 3 && egg_round == 1 && t == 70) egg_joy |= 0x200;   // gettone
                if (m == 3 && egg_round == 1 && t == 80) egg_joy |= 0x100;   // Start: CHALLENGE
                // scelta dei bonus come in "challenge", poi la racchetta TITAN (estremità gialle)
                if (m == 7) {
                    if (egg_paddle < 0 && r->pong_top__DOT__pick_paddle) egg_paddle = frames;
                    if (egg_paddle < 0 && (t == 10 || t == 30 || t == 50)) egg_joy |= 0x10;
                    if (egg_paddle < 0 && (t == 20 || t == 40)) egg_joy |= 0x04;
                    if (egg_paddle < 0 && t == 45) { egg_shot = true; egg_name = "egg_pick"; }
                    if (egg_paddle >= 0 && frames == egg_paddle + 5) r->pong_top__DOT__kind_cur[0] = 1;
                    if (egg_paddle >= 0 && frames == egg_paddle + 20) { egg_shot = true; egg_name = "egg_paddle"; }
                    if (egg_paddle >= 0 && frames == egg_paddle + 30) egg_joy |= 0x10;
                }
                // presentazione: l'avversario del livello 6, RUSH (immagini gialle dello scatto)
                if (m == 8 && t == 2) r->pong_top__DOT__ch_level = 5;
                if (m == 8 && t == 65) { egg_shot = true; egg_name = "egg_intro"; }
                if (m == 8 && t == 70) egg_joy |= 0x10;
                // partita: niente conto alla rovescia, una capsula BULLET (accento) verso la CPU
                if (m == 5 && t == 1) r->pong_top__DOT__mframe = 179;
                if (m == 5 && t == 40) {
                    const uint32_t cap[4] = {uint32_t(W / 2) << 16, 70u << 16, 18432u, 2212u};
                    patch(r, PATCH_CAPSULE, 3, 7);
                    for (int k = 0; k < 4; k++) {
                        patch(r, PATCH_CAPSULE_X + k, 3, cap[k]);
                        word(r, W_CAPS + 15 + k) = cap[k];
                    }
                    word(r, W_CAPS + 19) = 8 | 7;
                }
                if (m == 5 && (t == 60 || t == 100)) { egg_shot = true; egg_name = "egg_game" + std::to_string(t); }
                if (egg_shot) {
                    // pixel gialli e rossi del frame appena disegnato: con l'easter egg niente giallo
                    int yel = 0, red = 0;
                    for (int k = 0; k < W * H; k++) {
                        const uint32_t c = uint32_t(frame[3 * k]) << 16 | uint32_t(frame[3 * k + 1]) << 8 | frame[3 * k + 2];
                        yel += c == 0xFFD225;
                        red += c == 0xE62828;
                    }
                    std::printf("frame %d: %s, easter egg %d, pixel gialli %d, rossi %d, canzone %d\n", frames,
                                egg_name.c_str(), egg_on, yel, red, int(r->pong_top__DOT__sid__DOT__song_q));
                    if (egg_on && yel != 0) egg_errors++;
                }
            }
            // canzone del SID: a ogni cambio; in partita (dopo un secondo) il tema dell'avversario del
            // livello, SID_SONG_THEME0 + rung_kind, solo contro la CPU
            if (ch_test || chal_test || end_test || egg_test) {
                const int song = r->pong_top__DOT__sid__DOT__song_q, m = r->pong_top__DOT__mode;
                if (song != sid_song) {
                    std::printf("frame %d: modo %d, canzone del SID %d\n", frames, m, song);
                    sid_song = song;
                }
                if (m == 5 && frames - ch_at == 60) {
                    static const int kinds[7] = {0, 3, 2, 1, 4, 5, 6};   // rung_kind dei livelli
                    const int lvl = r->pong_top__DOT__ch_level;
                    const bool vs_cpu = r->pong_top__DOT__ch_active && !r->pong_top__DOT__duel;
                    const int want = vs_cpu ? 7 + kinds[lvl % 7] : 0;
                    std::printf("frame %d: partita del livello %d %s, canzone %d (attesa %d)%s\n", frames, lvl + 1,
                                vs_cpu ? "contro la CPU" : "tra due giocatori", song, want, song == want ? "" : " ERRORE");
                    if (song != want) song_errors++;
                }
            }
            if (wanted.count(frames) || chal_shot || end_shot || warp_shot || steer_shot || ghost_shot || pick_shot || kpick_shot || kgame_shot || ch_shot ||
                sup_shot || bul_shot || ht_shot || egg_shot) {
                char name[64];
                if (egg_shot)
                    std::snprintf(name, sizeof name, "%s.ppm", egg_name.c_str());
                else if (ht_shot)
                    std::snprintf(name, sizeof name, "%s.ppm", ht_name.c_str());
                else if (end_shot)
                    std::snprintf(name, sizeof name, "%s.ppm", end_name.c_str());
                else if (bul_shot)
                    std::snprintf(name, sizeof name, "%s.ppm", bul_name.c_str());
                else if (chal_shot)
                    std::snprintf(name, sizeof name, "%s.ppm", chal_name.c_str());
                else if (sup_shot)
                    std::snprintf(name, sizeof name, "%s.ppm", sup_name.c_str());
                else if (ch_shot)
                    std::snprintf(name, sizeof name, "%s.ppm", ch_name.c_str());
                else if (kpick_shot)
                    std::snprintf(name, sizeof name, "kpick_%d%d_%d.ppm", kind_l, kind_r, frames - paddle_at);
                else if (kgame_shot)
                    std::snprintf(name, sizeof name, "k_%d%d_%04d.ppm", kind_l, kind_r, frames - game_at);
                else if (warp_shot)
                    std::snprintf(name, sizeof name, "w%d_%02d.ppm", warps, warp_f);
                else if (steer_shot)
                    std::snprintf(name, sizeof name, "s%d_%03d.ppm", steers, steer_frames - 1);
                else if (ghost_shot && ghost)
                    std::snprintf(name, sizeof name, "gh%d_%03d.ppm", ghosts, ghost_frames - 1);
                else if (ghost_shot)
                    std::snprintf(name, sizeof name, "ghpost_%03d.ppm", post_frames - 1);
                else if (pick_shot)
                    std::snprintf(name, sizeof name, "pick_%d.ppm", frames - start_at);
                else
                    std::snprintf(name, sizeof name, "f%04d_mode%d.ppm", frames, int(r->pong_top__DOT__mode));
                FILE* f = std::fopen(name, "wb");
                std::fprintf(f, "P6\n%d %d\n255\n", W, H);
                std::fwrite(frame.data(), 1, frame.size(), f);
                std::fclose(f);
            }
            if (warp_test && (warp || warp_end)) warp_f++;
            // moneta e start come pressioni di un frame sul joystick 1 (bit 9 e 8)
            top.joy0 = (frames == coin_at) ? 0x200 : (frames == start_at) ? 0x100 : 0;
            top.joy0 |= sup_joy | chal_joy0 | bul_joy | ghost_joy | end_joy | egg_joy;
            top.joy1 = chal_joy1;
            if (demo_test) {
                // la demo segue l'OSD: a ogni giro dell'attract (2436 frame, demo dal frame 1524)
                // un'altra modalità, NEXT, CHALLENGE, CLASSIC, EVO
                const int k = frames / 2436 % 4;
                top.game_type = k == 0 ? 2 : k == 1 ? 3 : k == 2 ? 0 : 1;
                top.players_mode = 0;
            }
            if (next_test) {
                // scelta dei bonus: A prende quello sotto il cursore, giù lo sposta
                const int t = frames - start_at;
                // le scelte si confermano con A
                if (steer_test) {
                    // su dalla prima riga porta all'ultima, STEER; poi giù verso TELEPORT e SMASH
                    if (t == 10) top.joy0 |= 0x08;
                    if (t == 20 || t == 40 || t == 60) top.joy0 |= 0x10;
                    if (t == 30 || t == 50) top.joy0 |= 0x04;
                } else {
                    if (t == 10 || t == 30 || t == 50) top.joy0 |= 0x10;
                    if (t == 20 || t == 40) top.joy0 |= 0x04;
                }
                if ((kinds_test || ch_test || sup_test || chal_test || bul_test || ghost_test || end_test) && paddle_at >= 0 &&
                    frames == paddle_at + 30)
                    top.joy0 |= 0x10;
                // "challenge": A salta presentazione e livello superato; iniziali: giù, giù, A, su, A, A
                if (ch_test || (chal_test && ch_games == 0)) {
                    const int m = r->pong_top__DOT__mode, t = frames - ch_at;
                    if ((m == 8 || m == 9) && t == ((ch_test && m == 8 && ch_games == 0) ? 90 : 70)) top.joy0 |= 0x10;
                    if (m == 11 && (t == 30 || t == 40)) top.joy0 |= 0x04;
                    if (m == 11 && t == 55) top.joy0 |= 0x08;
                    if (m == 11 && (t == 50 || t == 65 || t == 80)) top.joy0 |= 0x10;
                }
                // "kinds": una raffica di A (il BLASTER spara quattro colpi e ricarica)
                if (kinds_test && game_at >= 0 && frames > game_at + 300 && frames < game_at + 340 && frames % 6 == 0)
                    top.joy0 |= 0x10;
                // in partita: si usa ogni tanto il bonus (Y) e si scatta in avanti (A)
                if (!ch_test && !sup_test && !chal_test && !bul_test && !end_test && frames > 1400 && frames % 97 == 0) top.joy0 |= 0x80;
                if (!ch_test && !sup_test && !chal_test && !bul_test && !end_test && frames > 1400 && frames % 151 == 0) top.joy0 |= 0x10;
            }
            // "paddle" e "spin", dopo il conto alla rovescia: pixel tra il bordo alto e la racchetta
            if (paddle_test || spin_test) {
                const int t = frames - start_at - 200;
                const int pos = int(((240 - 20) * 65536 - int32_t(r->pong_top__DOT__pad0_y)) >> 16);
                if (paddle_test && t >= 0) {
                    if (t % 12 == 0)
                        std::printf("paddle %3d: attesi %3d pixel, racchetta a %3d\n", enc_prev, (enc_prev * 25) >> 5, pos);
                    const int k = (t * 3) % 510;
                    enc_prev = k < 255 ? k : 510 - k;   // avanti e indietro tra 0 e 255
                    top.paddle0 = enc_prev;
                }
                if (spin_test && t >= 0 && t < 150) {
                    const int d = t < 50 ? 3 : t < 100 ? -3 : 0;
                    if (t % 10 == 0) {
                        std::printf("spinner %+d per frame: racchetta a %3d (%+d in 10 frame)\n", enc_prev, pos, pos - pos_prev);
                        pos_prev = pos;
                    }
                    enc_prev = d;
                    if (d) top.spinner0 = ((top.spinner0 ^ 0x100) & 0x100) | (d & 0xFF);
                    if (t >= 100) top.joy0 |= 0x08;   // spinner fermo, joystick su
                }
            }
            // doppio tocco su nella demo (la racchetta non conta, conta il flag)
            if (!chal_test && !end_test && !egg_test && (frames == 1000 || (frames >= 1010 && frames < 1014))) top.joy0 |= 0x08;
            if (frames == 1012)
                std::printf("doppio tocco: rapido %d (atteso 1)\n", int(r->pong_top__DOT__tap_fast & 1));
            if (frames == 1020)
                std::printf("lasciato: rapido %d (atteso 0)\n", int(r->pong_top__DOT__tap_fast & 1));
            // M_GAME: la partita è cominciata, il checkpoint si salva all'inizio del prossimo ciclo
            if (key && !ckpt_done && r->pong_top__DOT__mode == 5) ckpt_done = ckpt_due = true;
        }
        const int mode = r->pong_top__DOT__mode;
        if (mode != prev_mode) {
            std::printf("frame %4d: modo %d, crediti %d\n", frames, mode, int(r->pong_top__DOT__credits));
            prev_mode = mode;
        }
        for (int k = CPU_RATIO + 1; k <= 2 * CPU_RATIO; k++) {
            top.clk_cpu = (k % 2 == 0);
            if (k == 2 * CPU_RATIO) top.clk = 1;
            top.eval();
        }
    }
    if (ch_test || chal_test || end_test || egg_test)
        std::printf("canzoni del SID in partita: %d errori (attesi 0)\n", song_errors);
    if (egg_test)
        std::printf("easter egg: %d errori (attesi 0)\n", egg_errors);
    if (end_test)
        std::printf("voci YOU WIN!: %d (attese 2: livello 1 vinto e finale)\n", you_wins);
    if (ch_test)
        std::printf("richiesta di salvataggio della classifica dopo le iniziali: %d (attesa 1)\n",
                    int(top.ioctl_upload_req));
    if (mute_test)
        std::printf("muto: %lld cicli con il SID attivo nell'attract (atteso 0), %lld nel gettone (atteso > 0)\n",
                    loud_muted, loud_coin);
    if (music_test)
        std::printf("musica spenta: %lld cicli con una canzone (atteso 0), %lld con un effetto (atteso > 0)\n",
                    music_cycles, fx_cycles);
    std::printf("fine: punteggio %d, record %d, crediti %d\n", int(r->pong_top__DOT__score0),
                int(r->pong_top__DOT__best), int(r->pong_top__DOT__credits));
    return 0;
}
