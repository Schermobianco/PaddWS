"use strict";

const AudioContext = window.AudioContext || window.webkitAudioContext;
let audio_context;
let sounds = new Map();
let playbacks = [];
let sound_key_next = 1;
let playback_key_next = 1;

function audio_init() {
    // PADD WS: senza Web Audio (o se il browser lo rifiuta) si gioca senza suoni
    if (audio_context == null && AudioContext) {
        try {
            audio_context = new AudioContext();
        } catch (e) {
            console.warn("Audio non disponibile", e);
            return;
        }
        let audio_listener = audio_context.listener;

        {
            let AudioContext = window.AudioContext || window.webkitAudioContext;
            let ctx = new AudioContext();
            var fixAudioContext = function (e) {
                console.log("fix");

                // On newer Safari AudioContext starts in a suspended state per
                // spec but is only resumable by a call running in an event
                // handler triggered by the user. Do it here. Reference:
                // https://stackoverflow.com/questions/56768576/safari-audiocontext-suspended-even-with-onclick-creation
                audio_context.resume();

                // On older Safari, audio context should be explicitly unpaused
                // in a mouse/touch input event even if it was created after
                // first input event on the page thanks to:
                // https://gist.github.com/kus/3f01d60569eeadefe3a1

                // Create empty buffer
                var buffer = ctx.createBuffer(1, 1, 22050);
                var source = ctx.createBufferSource();
                source.buffer = buffer;
                // Connect to output (speakers)
                source.connect(ctx.destination);
                // Play sound
                if (source.start) {
                    source.start(0);
                } else if (source.play) {
                    source.play(0);
                } else if (source.noteOn) {
                    source.noteOn(0);
                }

                // Remove event handlers
                document.removeEventListener('touchstart', fixAudioContext);
                document.removeEventListener('touchend', fixAudioContext);
                document.removeEventListener('mousedown', fixAudioContext);
                document.removeEventListener('keydown', fixAudioContext);
            };
            // iOS 6-8
            document.addEventListener('touchstart', fixAudioContext);
            // iOS 9
            document.addEventListener('touchend', fixAudioContext);
            // Mac
            document.addEventListener('mousedown', fixAudioContext);
            document.addEventListener('keydown', fixAudioContext);
        }
    }
}

// PADD WS: un WAV PCM a 8 o 16 bit si legge qui, senza decodeAudioData. Su Safari, con
// l'AudioContext ancora sospeso (prima del primo tocco), la decodifica può non finire mai, e
// macroquad aspetta ogni suono prima di partire: la pagina restava nera. Null se non è un WAV PCM.
function wav_buffer(content, content_len) {
    const bytes = new Uint8Array(wasm_memory.buffer, content, content_len);
    const view = new DataView(wasm_memory.buffer, content, content_len);
    const tag = (at) => String.fromCharCode(bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]);
    if (content_len < 12 || tag(0) !== "RIFF" || tag(8) !== "WAVE") {
        return null;
    }
    let fmt = null;
    for (let at = 12; at + 8 <= content_len;) {
        const size = view.getUint32(at + 4, true);
        const body = at + 8;
        if (tag(at) === "fmt " && size >= 16) {
            fmt = {
                format: view.getUint16(body, true),
                channels: view.getUint16(body + 2, true),
                rate: view.getUint32(body + 4, true),
                bits: view.getUint16(body + 14, true),
            };
        } else if (tag(at) === "data" && fmt) {
            if (fmt.format !== 1 || (fmt.bits !== 8 && fmt.bits !== 16) || fmt.channels < 1) {
                return null;
            }
            const width = fmt.bits / 8;
            const step = width * fmt.channels;
            const frames = Math.floor(Math.min(size, content_len - body) / step);
            if (frames < 1) {
                return null;
            }
            // i Safari vecchi vogliono almeno 22050 Hz: allora si ripete ogni campione
            let repeat = 1;
            let buffer;
            for (;;) {
                try {
                    buffer = audio_context.createBuffer(fmt.channels, frames * repeat, fmt.rate * repeat);
                    break;
                } catch (e) {
                    if (fmt.rate * repeat >= 22050) {
                        return null;
                    }
                    repeat *= 2;
                }
            }
            for (let c = 0; c < fmt.channels; c++) {
                const out = buffer.getChannelData(c);
                for (let i = 0; i < frames; i++) {
                    const at2 = body + i * step + c * width;
                    const v = width === 2 ? view.getInt16(at2, true) / 32768 : (bytes[at2] - 128) / 128;
                    out.fill(v, i * repeat, (i + 1) * repeat);
                }
            }
            return buffer;
        }
        at = body + size + (size & 1);
    }
    return null;
}

function audio_add_buffer(content, content_len) {
    let sound_key = sound_key_next;
    sound_key_next += 1;

    // PADD WS: un suono che non si può avere vale come caricato e muto (null), così il gioco
    // parte comunque
    if (audio_context == null) {
        sounds.set(sound_key, null);
        return sound_key;
    }
    try {
        const wav = wav_buffer(content, content_len);
        if (wav) {
            sounds.set(sound_key, wav);
            return sound_key;
        }
    } catch (e) {
        console.warn("WAV non letto, si prova decodeAudioData", e);
    }

    let content_array = wasm_memory.buffer.slice(content, content + content_len);
    audio_context.decodeAudioData(content_array, function(buffer) {
        sounds.set(sound_key, buffer);
    }, function(e) {
        // fail
        console.warn("Failed to decode audio buffer", e);
        sounds.set(sound_key, null);
    });
    // decodifica che non risponde (Safari con l'audio sospeso): dopo 3 s il suono resta muto
    setTimeout(function() {
        if (!sounds.has(sound_key)) {
            sounds.set(sound_key, null);
        }
    }, 3000);
    return sound_key;
}

function audio_source_is_loaded(sound_key) {
    return sounds.has(sound_key);
}

function recycle_playback() {
    let playback = playbacks.find(playback => playback.sound_key === 0);

    if (playback != null) {
        playback.source = audio_context.createBufferSource();
    } else {
        playback = {
            sound_key: 0,
            playback_key: 0,
            source: audio_context.createBufferSource(),
            gain_node: audio_context.createGain(),
            ended: null,
        };

        playbacks.push(playback);
    }

    return playback;
}

function stop(playback) {
    try {
        playback.source.removeEventListener('ended', playback.ended);

        playback.source.disconnect();
        playback.gain_node.disconnect();

        playback.sound_key = 0;
        playback.playback_key = 0;
    } catch (e) {
        console.error("Error stopping sound", e);
    }
}

function audio_play_buffer(sound_key, volume, repeat) {
    let playback_key = playback_key_next++;

    // PADD WS: senza audio, o con un suono muto, non si suona niente
    if (audio_context == null || !sounds.get(sound_key)) {
        return playback_key;
    }

    let pb = recycle_playback();

    pb.sound_key = sound_key;
    pb.playback_key = playback_key;

    pb.source.connect(pb.gain_node);
    pb.gain_node.connect(audio_context.destination);

    pb.gain_node.gain.value = volume;
    pb.source.loop = repeat;

    pb.ended = function() {
        stop(pb);
    };
    pb.source.addEventListener('ended', pb.ended);

    try {
        pb.source.buffer = sounds.get(sound_key);
        pb.source.start(0);
    } catch (e) {
        console.error("Error starting sound", e);
    }

    return playback_key;
}

function audio_source_set_volume(sound_key, volume) {
    playbacks.forEach(playback => {
        if (playback.sound_key === sound_key) {
            playback.gain_node.gain.value = volume;
        }
    });
}

function audio_source_stop(sound_key) {
    playbacks.forEach(playback => {
        playback.sound_key === sound_key && stop(playback);
    });
}

function audio_source_delete(sound_key) {
    audio_source_stop(sound_key);

    sounds.delete(sound_key);
}

function audio_playback_stop(playback_key) {
    let playback = playbacks.find(playback => playback.playback_key === playback_key);

    playback != null && stop(playback);
}

function audio_playback_set_volume(playback_key, volume) {
    let playback = playbacks.find(playback => playback.playback_key === playback_key);

    if (playback != null) {
        playback.gain_node.gain.value = volume;
    }
}

function register_plugin(importObject) {
    importObject.env.audio_init = audio_init;
    importObject.env.audio_add_buffer = audio_add_buffer;
    importObject.env.audio_play_buffer = audio_play_buffer;
    importObject.env.audio_source_is_loaded = audio_source_is_loaded;
    importObject.env.audio_source_set_volume = audio_source_set_volume;
    importObject.env.audio_source_stop = audio_source_stop;
    importObject.env.audio_source_delete = audio_source_delete;
    importObject.env.audio_playback_stop = audio_playback_stop;
    importObject.env.audio_playback_set_volume = audio_playback_set_volume;
}

miniquad_add_plugin({ register_plugin, version: 1, name: "macroquad_audio" });
