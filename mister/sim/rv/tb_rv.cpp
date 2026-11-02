// Banco di prova di pong_logic_rv con Verilator (modello tb_rv_top.v): rigioca le tracce di
// paddws-trace e confronta a ogni tick
// le parole di stato con trace_state.hex e i comandi effettivi (CPU comprese) con trace_input.hex.
// Misura i cicli di clk (20 MHz) di ogni tick (da `step` a `busy` basso) e di 4 tick di fila (un
// frame); il processore gira a `--ratio` volte clk (3 = 60 MHz, il core; 2 = 40 MHz, il ripiego).
//
// Uso: tb_rv.exe [--ticks N] [--ratio 3|2] [--cpu-sides N] [--misses] TRACCIA...   (vedi rv.ps1)

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include "Vtb_rv_top.h"
#include "verilated.h"

double sc_time_stamp() { return 0; }

struct Trace {
    std::string name;
    std::map<std::string, long long> cfg;
    std::vector<uint64_t> inputs;
    std::vector<std::vector<uint32_t>> states;
};

static bool load(const std::string& dir, Trace& t) {
    t.name = dir;
    std::ifstream c(dir + "/trace_config.vh");
    if (!c) return false;
    std::string line;
    while (std::getline(c, line)) {
        const auto cut = line.find("//");
        if (cut != std::string::npos) line = line.substr(0, cut);
        const auto lp = line.find("localparam"), eq = line.find('=');
        if (lp == std::string::npos || eq == std::string::npos) continue;
        std::istringstream lhs(line.substr(lp, eq - lp));
        std::string w, name;
        while (lhs >> w) name = w;
        std::string v = line.substr(eq + 1);
        v = v.substr(0, v.find(';'));
        const auto q = v.find('\'');
        long long value = (q != std::string::npos) ? std::strtoll(v.c_str() + q + 2, nullptr, (v[q + 1] == 'h') ? 16 : 10)
                                                   : std::strtoll(v.c_str(), nullptr, 10);
        t.cfg[name] = value;
    }
    std::ifstream in(dir + "/trace_input.hex");
    while (std::getline(in, line))
        if (!line.empty() && line[0] != '\r') t.inputs.push_back(std::strtoull(line.c_str(), nullptr, 16));
    std::ifstream st(dir + "/trace_state.hex");
    while (std::getline(st, line)) {
        if (line.size() < 8) continue;
        std::vector<uint32_t> w;
        for (size_t i = 0; i + 8 <= line.size(); i += 8)
            w.push_back(uint32_t(std::strtoul(line.substr(i, 8).c_str(), nullptr, 16)));
        t.states.push_back(w);
    }
    return !t.inputs.empty() && t.states.size() >= t.inputs.size();
}

// riempimenti della cache istruzioni per riga (con --misses)
static std::map<uint32_t, long long> g_miss;
static bool g_count_miss = false;

// cicli di clk_cpu per ciclo di clk (60 MHz / 20 MHz; 2 per il ripiego a 40 MHz)
static int g_ratio = 3;

struct Sim {
    Vtb_rv_top top;
    long long cycles = 0;   // cicli di clk (20 MHz)
    // un ciclo di clk: 2 * ratio mezzi periodi di clk_cpu; clk scende a metà e sale alla fine, con i
    // fronti allineati a quelli di clk_cpu (come le uscite della stessa PLL)
    void tick() {
        for (int k = 1; k <= 2 * g_ratio; k++) {
            top.clk_cpu = (k % 2 == 0);
            if (k == g_ratio) top.clk = 0;
            if (k == 2 * g_ratio) top.clk = 1;
            top.eval();
            if (g_count_miss && (k % 2 == 1) && top.irefill_start) g_miss[top.irefill_addr & ~31u]++;
        }
        cycles++;
    }
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    long long max_ticks = -1;
    int force_sides = -1;          // --cpu-sides N: lati della CPU nel firmware (gli altri dalla traccia)
    const long long budget = 26712; // cicli tra l'inizio del vblank e la fotografia del frame (21 righe)
    std::vector<std::string> dirs;
    for (int i = 1; i < argc; i++) {
        const std::string a = argv[i];
        if (a == "--ticks" && i + 1 < argc) max_ticks = std::atoll(argv[++i]);
        else if (a == "--misses") g_count_miss = true;
        else if (a == "--cpu-sides" && i + 1 < argc) force_sides = std::atoi(argv[++i]);
        else if (a == "--ratio" && i + 1 < argc) g_ratio = std::atoi(argv[++i]);
        else if (a[0] != '+') dirs.push_back(a);
    }
    int failed = 0;
    long long worst_tick = 0, worst_frame = 0;
    std::string worst_name;
    for (const auto& dir : dirs) {
        Trace t;
        if (!load(dir, t)) {
            std::printf("FAIL %s: traccia illeggibile\n", dir.c_str());
            failed++;
            continue;
        }
        auto cfg = [&](const char* k) { return t.cfg.count(k) ? t.cfg[k] : 0LL; };
        const bool next = cfg("P_NEXT") != 0;
        const bool kinds = next && cfg("P_KINDS") != 0x3F;
        const bool supers = next && cfg("P_SUPERS") != 0;
        const int base = kinds ? 75 : next ? 45 : 19;
        const int nwords = base + (supers ? 2 : 0);
        const int cpu_sides = force_sides >= 0 ? force_sides : int(cfg("P_CPU_SIDES"));

        // il modello è grande (RAM e cache): sullo heap, non sullo stack
        auto sim = std::make_unique<Sim>();
        Sim& s = *sim;
        auto& top = s.top;
        top.clk = 1;
        top.clk_cpu = 1;
        top.rv_reset = 1;
        top.reset = 0;
        top.step = 0;
        top.two_players = cfg("P_PLAYERS") == 2;
        top.evo_mode = cfg("P_EVO") != 0;
        top.next_mode = next;
        top.loadout0 = uint32_t(cfg("P_LOADOUT0"));
        top.loadout1 = uint32_t(cfg("P_LOADOUT1"));
        top.kinds = uint32_t(cfg("P_KINDS"));
        top.difficulty = uint32_t(cfg("P_DIFFICULTY")) & 3;
        top.super_moves = cfg("P_SUPERS") != 0;
        top.seed = uint32_t(cfg("P_SEED"));
        top.cpu_level0 = uint32_t(cfg("P_CPU_LEVEL0"));
        top.cpu_level1 = uint32_t(cfg("P_CPU_LEVEL1"));
        top.cpu_control = uint32_t(cfg("P_CONTROL"));
        top.inputs = top.offsets = top.specials = top.cpu_sides = 0;
        for (int i = 0; i < 8; i++) s.tick();
        top.rv_reset = 0;
        // reset all'accensione, poi la nuova partita (il firmware la serve dopo l'avvio)
        const long long boot_from = s.cycles;
        top.reset = 1;
        s.tick();
        top.reset = 0;
        s.tick();
        while (top.busy && s.cycles - boot_from < 50000000LL) s.tick();
        if (top.busy || top.fw_panic) {
            std::printf("FAIL %s: il firmware non ha preparato la partita%s\n", t.name.c_str(), top.fw_panic ? " (errore)" : "");
            failed++;
            continue;
        }
        const long long boot = s.cycles - boot_from;

        const uint32_t b_ir = top.n_irefill, b_irc = top.c_irefill, b_dr = top.n_drefill, b_drc = top.c_drefill,
                       b_dw = top.n_dwrite, b_io = top.n_io;
        const long long n = (max_ticks >= 0 && max_ticks < (long long)t.inputs.size()) ? max_ticks : t.inputs.size();
        long long max_c = 0, max_at = 0, sum_c = 0, frame = 0;
        long long win[4] = {0, 0, 0, 0};
        long long frames_over = 0, frames_total = 0, frame_sum = 0, frame_worst = 0;
        std::string err;
        for (long long k = 0; k < n && err.empty(); k++) {
            const uint64_t in = t.inputs[k];
            top.inputs = uint32_t(in & 0xFFFF);
            top.offsets = uint32_t((in >> 16) & 0xFFFF);
            top.specials = uint32_t((in >> 32) & 0xF);
            top.cpu_sides = cpu_sides;
            top.step = 1;
            s.tick();
            top.step = 0;
            const long long from = s.cycles;
            s.tick();   // busy si alza il ciclo dopo lo step
            while (top.busy) {
                s.tick();
                if (s.cycles - from > 2000000) break;
            }
            if (top.busy || top.fw_panic) {
                err = "tick " + std::to_string(k + 1) + ": il firmware non risponde" + (top.fw_panic ? " (errore)" : "");
                break;
            }
            // cicli del firmware (busy)
            const long long c = s.cycles - from;
            sum_c += c;
            if (c > max_c) { max_c = c; max_at = k + 1; }
            win[k % 4] = c;
            frame = std::max(frame, win[0] + win[1] + win[2] + win[3]);
            // frame del core: 4 tick allineati (con i pochi cicli tra un tick e l'altro di pong_top)
            frame_sum += c + 3;
            if (k % 4 == 3) {
                frames_total++;
                frames_over += frame_sum > budget;
                frame_worst = std::max(frame_worst, frame_sum);
                frame_sum = 0;
            }

            // comandi effettivi e parole della traccia
            const uint32_t want_in = uint32_t(in), want_sp = uint32_t((in >> 32) & 0xF);
            if (top.tick_input != want_in || top.tick_special != want_sp) {
                char b[160];
                std::snprintf(b, sizeof b, "tick %lld, comandi: attesi %08x mosse %x, ottenuti %08x mosse %x", k + 1, want_in,
                              want_sp, unsigned(top.tick_input), unsigned(top.tick_special));
                err = b;
                break;
            }
            const auto& want = t.states[k];
            auto word = [&](int i) { return uint32_t(top.words[i]); };
            for (int w = 0; w < nwords; w++) {
                // nelle tracce le mosse speciali seguono direttamente il gruppo presente prima
                const int src = (supers && w >= base) ? 75 + (w - base) : w;
                if (word(src) != want[w]) {
                    char b[160];
                    std::snprintf(b, sizeof b, "tick %lld, parola %d: attesa %08x, ottenuta %08x", k + 1, w, want[w], word(src));
                    err = b;
                    break;
                }
            }
        }
        if (!err.empty()) {
            std::printf("FAIL %s: %s\n", t.name.c_str(), err.c_str());
            failed++;
            continue;
        }
        std::printf("PASS %s: %lld tick; cicli: avvio e nuova partita %lld, tick max %lld (tick %lld) media %lld, "
                    "4 tick max %lld\n",
                    t.name.c_str(), n, boot, max_c, max_at, sum_c / std::max(1LL, n), frame);
        std::fflush(stdout);
        std::printf("  frame (4 tick allineati): peggiore %lld cicli, oltre il budget %lld su %lld\n", frame_worst,
                    frames_over, frames_total);
        std::printf("  per tick: riempimenti cache istruzioni %.1f (%.1f cicli), dati %.1f (%.1f cicli), scritture in RAM %.1f, "
                    "accessi ai registri %.1f\n",
                    double(top.n_irefill - b_ir) / n, double(top.c_irefill - b_irc) / n, double(top.n_drefill - b_dr) / n,
                    double(top.c_drefill - b_drc) / n, double(top.n_dwrite - b_dw) / n, double(top.n_io - b_io) / n);
        if (max_c > worst_tick) { worst_tick = max_c; worst_name = t.name; }
        worst_frame = std::max(worst_frame, frame);
    }
    if (g_count_miss) {
        std::vector<std::pair<long long, uint32_t>> v;
        for (auto& [a, c] : g_miss) v.push_back({c, a});
        std::sort(v.rbegin(), v.rend());
        FILE* f = std::fopen("misses.txt", "w");
        for (auto& [c, a] : v) std::fprintf(f, "%08x %lld\n", a, c);
        std::fclose(f);
    }
    if (!dirs.empty())
        std::printf("tick peggiore: %lld cicli (%s), 4 tick di fila al massimo %lld cicli (budget nel vblank: 26712)\n",
                    worst_tick, worst_name.c_str(), worst_frame);
    if (failed) {
        std::printf("%d tracce non coincidono\n", failed);
        return 1;
    }
    std::printf("pong_logic_rv identico al core Rust su tutte le tracce\n");
    return 0;
}
