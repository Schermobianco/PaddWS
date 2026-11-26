"use strict";
// Service worker della versione web di PADD WS: il gioco parte anche senza rete e il browser lo
// può installare come app (Android e computer con "Installa app", iPhone e iPad con "Aggiungi a
// Home"). Lo registra index.html, solo nelle pagine sicure (https o localhost).
//
// Con la rete i file arrivano sempre dal sito, come senza service worker, e se ne tiene una copia;
// senza rete si usano le copie. Così, uscita una versione nuova, chi è online non gioca mai con
// quella vecchia, e le copie sono proprio i file con cui il gioco è partito l'ultima volta (mai
// un wasm di una versione con il JavaScript di un'altra). All'installazione si copiano tutti i
// file, perché anche la prima partita senza rete trovi tutto.
//
// VERSION la scrive tools/build-web.ps1 (versione del gioco e impronta di paddws.wasm): cambia a
// ogni build, il browser installa il service worker nuovo e questo cancella le copie vecchie.

const VERSION = "4.7.1-5e75fbf3eac6";
const CACHE = "paddws-" + VERSION;
const FILES = [
    "./",
    "index.html",
    "mq_js_bundle.js",
    "sid_audio.js",
    "gamepad.js",
    "storage.js",
    "fullscreen.js",
    "paddws.wasm",
    "manifest.webmanifest",
    "icon-64.png",
    "icon-180.png",
    "icon-192.png",
    "icon-512.png",
];

self.addEventListener("install", (event) => {
    event.waitUntil(
        caches.open(CACHE)
            .then((cache) => cache.addAll(FILES))
            .then(() => self.skipWaiting())
    );
});

// via le copie delle versioni precedenti (solo le nostre: su github.io l'origine è condivisa
// con le pagine degli altri repository)
self.addEventListener("activate", (event) => {
    event.waitUntil(
        caches.keys()
            .then((keys) => Promise.all(keys
                .filter((key) => key.startsWith("paddws-") && key !== CACHE)
                .map((key) => caches.delete(key))))
            .then(() => self.clients.claim())
    );
});

self.addEventListener("fetch", (event) => {
    const request = event.request;
    if (request.method !== "GET" || new URL(request.url).origin !== self.location.origin) {
        return;
    }
    event.respondWith(fromNetworkOrCopy(request));
});

async function fromNetworkOrCopy(request) {
    try {
        const response = await fetch(request);
        if (response.ok) {
            const copy = response.clone();
            caches.open(CACHE).then((cache) => cache.put(request, copy)).catch(() => {});
        }
        return response;
    } catch (e) {
        // senza rete: la copia, e per la pagina (anche con parametri nell'indirizzo) index.html
        const cached = await caches.match(request, { ignoreSearch: true })
            || (request.mode === "navigate" ? await caches.match("index.html") : undefined);
        return cached || Response.error();
    }
}
