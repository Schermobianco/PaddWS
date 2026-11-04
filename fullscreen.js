"use strict";
// Schermo intero sui dispositivi touch: il browser lo concede solo dentro un gesto dell'utente,
// quindi lo si chiede al primo tocco, quando il dito si stacca (e di nuovo al tocco dopo, se lo
// si è lasciato). Quel tocco serve solo a questo: non arriva al gioco, che altrimenti lo
// prenderebbe per un gettone o uno Start prima che la tela abbia preso le nuove misure. In schermo intero si blocca l'orientamento
// in orizzontale (dove il browser lo permette: Android). Finché la pagina è visibile lo schermo
// resta acceso (Screen Wake Lock), anche senza schermo intero.
// Su iPhone Safari lo schermo intero delle pagine non c'è: lo dà "Aggiungi a Home" (manifest).
// La voce FULLSCREEN del menu (rust/game/src/platform.rs) legge lo stato vero e lo cambia; con
// OFF dal menu il tocco non lo richiede più, fino a ON o al prossimo caricamento della pagina.

(function () {
    const root = document.documentElement;
    const request = root.requestFullscreen || root.webkitRequestFullscreen;
    let auto = true; // si chiede lo schermo intero al tocco (OFF dal menu lo ferma)
    let swallowing = false; // il gesto che ha chiesto lo schermo intero, fino all'ultimo dito
    let wakeLock = null;

    function elementFullscreen() {
        return !!(document.fullscreenElement || document.webkitFullscreenElement);
    }

    // a schermo intero davvero: la pagina (Fullscreen API) o l'app da Home con il manifest a
    // schermo intero. Da Home in "standalone" (Android) le barre di sistema restano: lì lo schermo
    // intero si chiede come nel browser. Su iPhone da Home (navigator.standalone) più di così non
    // si può: vale come schermo intero, perché la richiesta lì non c'è.
    function isFullscreen() {
        return elementFullscreen()
            || window.matchMedia("(display-mode: fullscreen)").matches
            || (navigator.standalone === true && !request);
    }

    function enterFullscreen() {
        try {
            const p = request.call(root, { navigationUI: "hide" });
            const lock = () => {
                if (screen.orientation && screen.orientation.lock) {
                    screen.orientation.lock("landscape").catch(() => {});
                }
            };
            if (p && p.then) {
                p.then(lock).catch(refused);
            } else {
                lock();
            }
        } catch (e) {
            refused(e);
        }
    }

    // il browser rifiuta lo schermo intero: il tocco non lo richiede più (altrimenti ogni tocco
    // finirebbe qui e non arriverebbe al gioco); resta la voce del menu
    function refused(e) {
        auto = false;
        console.warn("Schermo intero rifiutato dal browser", e);
    }

    async function keepAwake() {
        if (wakeLock || !navigator.wakeLock || document.visibilityState !== "visible") {
            return;
        }
        try {
            wakeLock = await navigator.wakeLock.request("screen");
            wakeLock.addEventListener("release", () => { wakeLock = null; });
        } catch (e) {
            wakeLock = null; // pagina non sicura (http) o batteria scarica: lo schermo si spegne da sé
        }
    }

    // il gesto che chiede lo schermo intero non arriva a miniquad (stopPropagation) e non diventa
    // un click del mouse (preventDefault, che altrimenti fa miniquad): il gioco non lo vede
    function swallow(e) {
        e.stopPropagation();
        e.preventDefault();
    }

    function onTouchStart(e) {
        keepAwake();
        if (!swallowing && auto && request && !isFullscreen()) {
            swallowing = true;
        }
        if (swallowing) {
            swallow(e);
        }
    }

    function onTouchOther(e) {
        if (!swallowing) {
            return;
        }
        swallow(e);
        if (e.type !== "touchmove" && e.touches.length === 0) {
            swallowing = false;
            // Chrome concede lo schermo intero al distacco del dito, non all'appoggio
            if (e.type === "touchend") {
                enterFullscreen();
                // il tocco non è arrivato agli ascoltatori dell'audio (audio.js, sid_audio.js)
                if (typeof audio_context !== "undefined" && audio_context && audio_context.state !== "running") {
                    audio_context.resume();
                }
            }
        }
    }

    // in cattura sulla finestra: si arriva prima degli ascoltatori di miniquad sulla tela
    window.addEventListener("touchstart", onTouchStart, { capture: true, passive: false });
    for (const type of ["touchmove", "touchend", "touchcancel"]) {
        window.addEventListener(type, onTouchOther, { capture: true, passive: false });
    }
    // voce FULLSCREEN del menu: lo stato vero e il cambio (dentro il gesto che ha scelto la voce)
    function paddws_is_fullscreen() {
        return isFullscreen();
    }

    function paddws_set_fullscreen(on) {
        auto = !!on;
        if (on && request && !isFullscreen()) {
            enterFullscreen();
        } else if (!on && elementFullscreen()) {
            const exit = document.exitFullscreen || document.webkitExitFullscreen;
            try {
                const p = exit.call(document);
                if (p && p.catch) {
                    p.catch(() => {});
                }
            } catch (e) {
                // già uscito
            }
        }
    }

    // telefono o tablet: il puntatore principale è il dito (il gioco ci regola i volumi)
    function paddws_touch_device() {
        return window.matchMedia("(pointer: coarse)").matches;
    }

    function register_plugin(importObject) {
        importObject.env.paddws_is_fullscreen = paddws_is_fullscreen;
        importObject.env.paddws_touch_device = paddws_touch_device;
        importObject.env.paddws_set_fullscreen = paddws_set_fullscreen;
    }

    miniquad_add_plugin({ register_plugin, version: 1, name: "paddws_screen" });

    // il blocco dello schermo acceso cade quando la pagina va in secondo piano: lo si riprende
    document.addEventListener("visibilitychange", () => {
        if (document.visibilityState === "visible" && "ontouchstart" in window) {
            keepAwake();
        }
    });
})();
