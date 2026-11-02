"use strict";
// Musica del SID di PADD WS nel browser: il SID Rust (rust/sid) suona in tempo reale dentro il
// wasm, uno ScriptProcessor chiede i campioni a paddws_music_fill (rust/game/src/music.rs).
// Usa lo stesso AudioContext degli effetti (audio.js di quad-snd), che parte al primo gesto
// dell'utente; qui si riprova a farlo partire a ogni gesto finché non suona. Lo ScriptProcessor
// funziona anche dove l'AudioWorklet non c'è (pagine servite in http dalla rete locale).

(function () {
    const BLOCK = 2048; // campioni per richiesta: circa 45 ms a 44,1 o 48 kHz
    let ctx = null;
    let node = null;

    function resume() {
        if (ctx && ctx.state !== "running") {
            ctx.resume();
        }
    }

    function paddws_music_init() {
        try {
            const AC = window.AudioContext || window.webkitAudioContext;
            ctx = (typeof audio_context !== "undefined" && audio_context) ? audio_context : new AC();
            node = ctx.createScriptProcessor(BLOCK, 1, 1);
            node.onaudioprocess = function (e) {
                const out = e.outputBuffer.getChannelData(0);
                const ptr = wasm_exports.paddws_music_fill(out.length);
                if (ptr) {
                    out.set(new Float32Array(wasm_memory.buffer, ptr, out.length));
                } else {
                    out.fill(0);
                }
            };
            node.connect(ctx.destination);
            for (const ev of ["touchstart", "touchend", "mousedown", "keydown", "pointerdown"]) {
                document.addEventListener(ev, resume);
            }
            return ctx.sampleRate;
        } catch (e) {
            console.error("Musica del SID non disponibile", e);
            return 0;
        }
    }

    function register_plugin(importObject) {
        importObject.env.paddws_music_init = paddws_music_init;
    }

    miniquad_add_plugin({ register_plugin, version: 1, name: "paddws_sid" });
})();
