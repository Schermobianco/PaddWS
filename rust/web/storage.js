"use strict";
// Dati di PADD WS nel browser: la configurazione con le preferenze del menu (padd_config.json) e la
// classifica della CHALLENGE (padd_scores.json) stanno nel localStorage, con il nome del file come
// chiave (rust/game/src/platform.rs, read_text e write_text). Il testo passa per la memoria del wasm
// in UTF-8. Senza localStorage (navigazione privata, blocchi del browser) si gioca con i default e
// le preferenze durano fino alla chiusura della pagina.

(function () {
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();

    function text(ptr, len) {
        return decoder.decode(new Uint8Array(wasm_memory.buffer, ptr, len));
    }

    // valore della chiave copiato in out se ci sta; restituisce la sua lunghezza (-1 se non c'è)
    function paddws_storage_get(key_ptr, key_len, out_ptr, out_len) {
        try {
            const value = window.localStorage.getItem(text(key_ptr, key_len));
            if (value === null) {
                return -1;
            }
            const bytes = encoder.encode(value);
            if (bytes.length <= out_len) {
                new Uint8Array(wasm_memory.buffer, out_ptr, bytes.length).set(bytes);
            }
            return bytes.length;
        } catch (e) {
            return -1;
        }
    }

    function paddws_storage_set(key_ptr, key_len, value_ptr, value_len) {
        try {
            window.localStorage.setItem(text(key_ptr, key_len), text(value_ptr, value_len));
            return true;
        } catch (e) {
            console.warn("localStorage non disponibile", e);
            return false;
        }
    }

    function register_plugin(importObject) {
        importObject.env.paddws_storage_get = paddws_storage_get;
        importObject.env.paddws_storage_set = paddws_storage_set;
    }

    miniquad_add_plugin({ register_plugin, version: 1, name: "paddws_storage" });
})();
