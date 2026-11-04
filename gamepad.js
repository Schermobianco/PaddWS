"use strict";
// Gamepad e stick arcade di PADD WS nel browser, con la Gamepad API: il gioco chiede a ogni frame
// lo stato dei gamepad collegati (rust/game/src/gamepad.rs, backend web). Per ognuno scrive
// quattro numeri nella memoria del wasm: indice, levetta x e y (y in giù positiva) e i pulsanti
// come bit di `Control` (su, giù, sinistra, destra, A, B, C, Start, Select). Il browser mostra i
// gamepad solo dopo la pressione di un loro pulsante, e solo nelle pagine sicure (https o
// localhost).

(function () {
    const UP = 1, DOWN = 2, LEFT = 4, RIGHT = 8, A = 16, B = 32, C = 64, START = 128, SELECT = 256;
    // mappatura "standard" del browser: 0 A, 1 B, 2 X, 3 Y, 8 Back, 9 Start, 12-15 croce
    const STANDARD = [[0, A], [1, B], [2, C], [3, C], [8, SELECT], [9, START],
                      [12, UP], [13, DOWN], [14, LEFT], [15, RIGHT]];
    // schede encoder e stick senza mappatura: i pulsanti per numero, come raw_button in gamepad.rs
    const RAW = [[0, A], [1, B], [2, C], [8, SELECT], [9, START]];
    // "cappello" della croce come asse unico (Chrome): -1 su, poi a passi di 2/7 in senso orario
    const HAT = [UP, UP | RIGHT, RIGHT, DOWN | RIGHT, DOWN, DOWN | LEFT, LEFT, UP | LEFT];

    function pressed(button) {
        return button && (button.pressed || button.value > 0.5);
    }

    function bits(pad) {
        let out = 0;
        const map = pad.mapping === "standard" ? STANDARD : RAW;
        for (const [i, bit] of map) {
            if (pressed(pad.buttons[i])) {
                out |= bit;
            }
        }
        if (pad.mapping !== "standard" && pad.axes.length > 9) {
            const v = pad.axes[9];
            if (v >= -1.001 && v <= 1.001) {
                out |= HAT[Math.round((v + 1) * 3.5) % 8];
            }
        }
        return out;
    }

    function paddws_gamepads(ptr, max) {
        const pads = navigator.getGamepads ? navigator.getGamepads() : [];
        const out = new Float32Array(wasm_memory.buffer, ptr, max * 4);
        let n = 0;
        for (const pad of pads) {
            if (!pad || !pad.connected || n >= max) {
                continue;
            }
            out[n * 4] = pad.index;
            out[n * 4 + 1] = pad.axes.length > 0 ? pad.axes[0] : 0;
            out[n * 4 + 2] = pad.axes.length > 1 ? pad.axes[1] : 0;
            out[n * 4 + 3] = bits(pad);
            n++;
        }
        return n;
    }

    function register_plugin(importObject) {
        importObject.env.paddws_gamepads = paddws_gamepads;
    }

    miniquad_add_plugin({ register_plugin, version: 1, name: "paddws_pad" });
})();
