// Registra le scritture nei registri del SID del player Verilog (rtl/pong_sid.v), frame per
// frame, con un programma fisso di canzoni ed effetti: è il riferimento del player in 6502 della
// versione C64 e del player Rust (c64/test/sid_reference.txt, verificato da paddws-c64 sid e da
// cargo test -p paddws-sid). Li registra writes.ps1, anche quelli della musica dinamica.
//
// Uso: writes.exe [fast|slow|both] > riferimento.txt
// Formato: "F n" inizio del frame n; "S c" canzone c; "X e" eventi e (effetto); "W r v" il
// player scrive v nel registro r. Comandi e scritture di un frame vengono prima del suo tick.
//
// Musica dinamica (writes.exe fast|slow|both, per il confronto con il player Rust di rust/sid):
// "fast" match point dall'inizio (un passo della canzone ogni 320.000 cicli, il "frame" qui è il
// passo della canzone), solo canzoni; "slow" tempo normale, canzoni ed effetti e il bullet time
// che si accende e si spegne ("L 1", "L 0" prima del passo); "both" le due cose insieme, solo
// canzoni. Senza argomento il riferimento del C64 e del player Rust.

#include <cstdint>
#include <cstdio>
#include <string>

#include "Vpong_sid.h"
#include "verilated.h"

double sc_time_stamp() { return 0; }

static const uint64_t FRAME = 400000;   // cicli per frame del player (50 Hz a 20 MHz)
static const uint64_t FAST_FRAME = 320000;   // passo della canzone al match point (62,5 Hz)
static const int FRAMES = 5600;
static const int DYN_FRAMES = 1700;   // musica dinamica

struct Sim {
    Vpong_sid top;
    uint64_t cycle = 0;
    void tick() {
        top.clk = 0; top.eval();
        top.clk = 1; top.eval();
        cycle++;
    }
    void run_to(uint64_t c) {
        while (cycle < c) tick();
    }
};

// canzone da impostare all'inizio del frame (-1 = nessun cambio)
static int song_at(int f) {
    switch (f) {
        case 5: return 1;       // titolo
        case 820: return 2;     // presentazione
        case 900: return 3;     // livello superato
        case 1010: return 4;    // continue (in ripetizione)
        case 1400: return 5;    // game over
        case 1620: return 6;    // campione
        case 2500: return 0;    // silenzio
        case 2560: return 1;
        case 2700: return 5;    // cambio a metà canzone
        case 2900: return 4;
        // temi di CHALLENGE (canzoni 7-13): il BLASTER per più di un giro (ripetizione), poi
        // gli altri, uno dopo l'altro (cambio di tema), con il silenzio e una canzone in mezzo
        case 3200: return 11;
        case 3850: return 7;
        case 4070: return 8;
        case 4290: return 9;
        case 4510: return 10;
        case 4730: return 12;
        case 4950: return 13;
        case 5170: return 0;
        case 5230: return 13;
        case 5400: return 3;
        default: return -1;
    }
}

// eventi del frame: effetti sparsi, anche più eventi insieme (vale il più importante)
static int fx_at(int f) {
    static const int ev[] = {1, 2, 4, 8, 16, 3, 12, 6, 2, 1, 24, 5};
    if (f % 37 == 11) return ev[(f / 37) % 12];
    if (f >= 2400 && f < 2440 && f % 4 == 0) return 2;     // effetti fitti
    if (f >= 3300 && f < 3360 && f % 3 == 0) return 6;     // anche sopra un tema
    return 0;
}

// musica dinamica: canzoni (-1 = nessun cambio), con temi, silenzio e cambi durante il bullet time
static int dyn_song_at(int f) {
    switch (f) {
        case 5: return 9;       // HAMMER: arpeggi e batteria
        case 600: return 11;    // BLASTER
        case 800: return 0;     // silenzio nel bullet time
        case 850: return 12;    // RUSH, parte nel bullet time
        case 1200: return 7;
        case 1450: return 13;   // cambio insieme all'uscita dal bullet time
        default: return -1;
    }
}

// bullet time: 1 entra, 0 esce, -1 nessun cambio (anche un'entrata e un'uscita di fila)
static int dyn_slow_at(int f) {
    switch (f) {
        case 200: case 700: case 1001: case 1300: return 1;
        case 450: case 1000: case 1002: case 1450: return 0;
        default: return -1;
    }
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    const std::string mode = argc > 1 ? argv[1] : "";
    const bool dyn = mode == "fast" || mode == "slow" || mode == "both";
    const bool fast = mode == "fast" || mode == "both";
    const bool slow = mode == "slow" || mode == "both";
    Sim s;
    s.top.reset = 1;
    s.top.song = 0;
    s.top.trigger = 0;
    s.top.events = 0;
    s.top.mode_8580 = 1;
    s.top.slow = 0;
    s.top.music_fast = fast;
    s.top.music_slow = 0;
    s.run_to(10);
    s.top.reset = 0;
    if (dyn) {
        // il primo passo della canzone è al ciclo FRAME - 1, poi ogni FAST_FRAME al match point
        const uint64_t step = fast ? FAST_FRAME : FRAME;
        for (int f = 0; f < DYN_FRAMES; f++) {
            uint64_t at = f == 0 ? 1000 : FRAME - 1 + (uint64_t)(f - 1) * step + 1000;
            s.run_to(at);
            printf("F %d\n", f);
            int song = dyn_song_at(f);
            if (song >= 0) {
                printf("S %d\n", song);
                s.top.song = song;
            }
            int l = slow ? dyn_slow_at(f) : -1;
            if (l >= 0) {
                printf("L %d\n", l);
                s.top.music_slow = l;
            }
            int ev = fast ? 0 : fx_at(f);
            if (ev) {
                printf("X %d\n", ev);
                fflush(stdout);
                s.top.events = ev;
                s.top.trigger = 1;
                s.tick();
                s.top.trigger = 0;
            }
            fflush(stdout);
        }
        s.run_to(FRAME - 1 + (uint64_t)(DYN_FRAMES - 1) * step + 1000);
        fflush(stdout);
        return 0;
    }
    // il primo tick del player è al ciclo FRAME - 1; i comandi del frame f arrivano 1000 cicli
    // dopo il tick precedente (o dopo il reset), finita l'elaborazione di quel tick
    for (int f = 0; f < FRAMES; f++) {
        uint64_t at = f == 0 ? 1000 : (uint64_t)f * FRAME - 1 + 1000;
        s.run_to(at);
        printf("F %d\n", f);
        fflush(stdout);
        int song = song_at(f);
        if (song >= 0) {
            printf("S %d\n", song);
            fflush(stdout);
            s.top.song = song;
        }
        int ev = fx_at(f);
        if (ev) {
            printf("X %d\n", ev);
            fflush(stdout);
            s.top.events = ev;
            s.top.trigger = 1;
            s.tick();
            s.top.trigger = 0;
        }
    }
    s.run_to((uint64_t)FRAMES * FRAME - 1 + 1000);
    fflush(stdout);
    return 0;
}
