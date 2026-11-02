// Registra in WAV le canzoni e gli effetti del SID, suonati dal player Verilog (rtl/pong_sid.v)
// simulato con Verilator. Gli effetti vanno negli asset delle versioni PC, Raspberry e web (identici
// al MiSTer); le canzoni le suona in tempo reale il SID Rust (rust/sid), e qui servono solo da
// riferimento per il confronto (paddws-sid compare): render.ps1 le toglie dagli asset.
//
// Uso: render.exe CARTELLA [8580|6581] [voice]
// Ogni file: mono, 16 bit, 44,1 kHz. Le canzoni in ripetizione durano esattamente un giro (si
// possono ripetere senza stacchi); le altre hanno un secondo di coda per il rilascio.
// Con "voice", per la verifica della voce della CHALLENGE: la presentazione (canzone dell'intro) con il
// nome di ogni avversario detto dal SID come in pong_top (0,43 s dopo l'inizio, intro_voice_<nome>.wav),
// una presentazione saltata a 0,8 s (intro_voice_stop.wav) e gli effetti del bullet time di NEXT
// (<effetto>_slow.wav).

#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

#include "Vpong_sid.h"
#include "verilated.h"

// richiesta da Verilator per $time
double sc_time_stamp() { return 0; }

static const double CLK_HZ = 20e6;
static const int OUT_HZ = 44100;   // come il mixer di macroquad: niente ricampionamento
static const uint64_t FRAME = 400000;   // cicli per frame del player (50 Hz)

static void write_wav(const std::string &path, const std::vector<int16_t> &s) {
    FILE *f = fopen(path.c_str(), "wb");
    if (!f) {
        fprintf(stderr, "non riesco a scrivere %s\n", path.c_str());
        exit(1);
    }
    uint32_t data = (uint32_t)s.size() * 2, rate = OUT_HZ, byte_rate = OUT_HZ * 2;
    uint32_t riff = 36 + data, fmt_len = 16;
    uint16_t pcm = 1, mono = 1, align = 2, bits = 16;
    fwrite("RIFF", 1, 4, f); fwrite(&riff, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f);
    fwrite(&fmt_len, 4, 1, f); fwrite(&pcm, 2, 1, f); fwrite(&mono, 2, 1, f);
    fwrite(&rate, 4, 1, f); fwrite(&byte_rate, 4, 1, f); fwrite(&align, 2, 1, f);
    fwrite(&bits, 2, 1, f); fwrite("data", 1, 4, f); fwrite(&data, 4, 1, f);
    fwrite(s.data(), 2, s.size(), f);
    fclose(f);
    printf("%s  %.2f s\n", path.c_str(), s.size() / (double)OUT_HZ);
}

struct Sim {
    Vpong_sid top;
    uint64_t cycle = 0;
    void tick() {
        top.clk = 0; top.eval();
        top.clk = 1; top.eval();
        cycle++;
    }
    // `cycles` cicli; se `out` raccoglie i campioni (media su ogni periodo d'uscita)
    void run(uint64_t cycles, std::vector<int16_t> *out) {
        double acc = 0, next = CLK_HZ / OUT_HZ;
        int n = 0;
        double t = 0;
        for (uint64_t i = 0; i < cycles; i++) {
            tick();
            if (!out) continue;
            if ((cycle % 20) == 0) {   // il SID cambia campione a 1 MHz
                acc += (int16_t)top.sample;
                n++;
            }
            t += 1;
            if (t >= next) {
                next += CLK_HZ / OUT_HZ;
                double v = n ? acc / n : 0;
                acc = 0; n = 0;
                if (v > 32767) v = 32767;
                if (v < -32768) v = -32768;
                out->push_back((int16_t)v);
            }
        }
    }
    void reset(int mode_8580) {
        top.mode_8580 = mode_8580;
        top.song = 0; top.trigger = 0; top.events = 0;
        top.slow = 0; top.voice_go = 0; top.voice_id = 0; top.voice_stop = 0;
        top.reset = 1;
        run(100, nullptr);
        top.reset = 0;
        run(FRAME * 2, nullptr);   // primo frame del player: volume e canali pronti
    }
};

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 2) {
        fprintf(stderr, "uso: render CARTELLA [8580|6581]\n");
        return 2;
    }
    std::string dir = argv[1];
    int mode = (argc > 2 && std::string(argv[2]) == "6581") ? 0 : 1;
    if (argc > 3 && std::string(argv[3]) == "voice") {
        // presentazione: canzone dell'intro e, al frame 26 di pong_top (60 Hz), la voce
        const char *names[] = {"arcade", "titan", "hammer", "twist", "blaster", "rush", "guardian"};
        const uint64_t at = (uint64_t)(26.0 / 60.0 * CLK_HZ);
        for (int k = 0; k <= 7; k++) {
            Sim sim;
            sim.reset(mode);
            sim.top.song = 2;
            std::vector<int16_t> out;
            sim.run(at, &out);
            sim.top.voice_id = k == 7 ? 0 : k;
            sim.top.voice_go = 1;
            sim.run(1, &out);
            sim.top.voice_go = 0;
            if (k == 7) {
                // presentazione saltata a 0,8 s: la voce si ferma, poi l'effetto della partita
                sim.run((uint64_t)(0.8 * CLK_HZ) - at, &out);
                sim.top.voice_stop = 1;
                sim.top.song = 0;
                sim.top.events = 1 << 1;
                sim.top.trigger = 1;
                sim.run(1, &out);
                sim.top.trigger = 0;
                sim.run((uint64_t)(1.5 * CLK_HZ), &out);
            } else {
                sim.run((uint64_t)(2.6 * CLK_HZ), &out);
            }
            write_wav(dir + "/intro_voice_" + (k == 7 ? "stop" : names[k]) + ".wav", out);
        }
        const char *fx[] = {"wall", "hit", "boost", "score"};
        for (int i = 0; i < 4; i++) {
            Sim sim;
            sim.reset(mode);
            sim.top.events = 1 << i;
            sim.top.slow = 1;
            sim.top.trigger = 1;
            std::vector<int16_t> out;
            sim.run(1, &out);
            sim.top.trigger = 0;
            sim.top.slow = 0;
            sim.run((uint64_t)(1.2 * CLK_HZ), &out);
            write_wav(dir + "/" + fx[i] + "_slow.wav", out);
        }
        return 0;
    }
    // (nome, numero, frame di un giro, in ripetizione): numeri e durate da sid_music.vh; un giro è la
    // traccia più lunga della canzone, multiplo delle altre (HAMMER: 536, il basso)
    struct Song { const char *name; int id; int frames; bool loop; };
    const Song songs[] = {
        {"title", 1, 768, true},  {"intro", 2, 72, false},    {"clear", 3, 96, false},
        {"continue", 4, 192, true}, {"game_over", 5, 180, false}, {"champion", 6, 384, true},
        // temi di CHALLENGE, nell'ordine di PaddleKind
        {"theme_arcade", 7, 768, true}, {"theme_titan", 8, 960, true}, {"theme_hammer", 9, 536, true},
        {"theme_twist", 10, 768, true}, {"theme_blaster", 11, 576, true}, {"theme_rush", 12, 576, true},
        {"theme_guardian", 13, 768, true},
    };
    for (const Song &s : songs) {
        Sim sim;
        sim.reset(mode);
        // la canzone parte al primo frame dopo il cambio: si registra da lì
        sim.top.song = s.id;
        uint64_t to_frame = FRAME - (sim.cycle % FRAME);
        sim.run(to_frame, nullptr);
        std::vector<int16_t> out;
        sim.run((uint64_t)s.frames * FRAME + (s.loop ? 0 : 50 * FRAME), &out);
        write_wav(dir + "/" + s.name + ".wav", out);
    }
    const char *fx[] = {"wall", "hit", "boost", "score", "coin", "move", "special"};
    for (int i = 0; i < 7; i++) {
        Sim sim;
        sim.reset(mode);
        sim.top.events = 1 << i;
        sim.top.trigger = 1;
        std::vector<int16_t> out;
        sim.run(1, &out);
        sim.top.trigger = 0;
        sim.run((uint64_t)(0.7 * CLK_HZ), &out);
        write_wav(dir + "/" + fx[i] + ".wav", out);
    }
    return 0;
}
