"""Finestra Arcade: gestisce le scene, lo scaling letterbox, il filtro CRT e l'audio."""

from __future__ import annotations

import logging
import time
from pathlib import Path

import arcade
import pyglet

from paddws import paths
from paddws.config import Config, auto_width, save_preferences
from paddws.core import Event, Params
from paddws.core.params import DIFFICULTY_NAMES
from paddws.hardware import Encoders, is_raspberry_pi

log = logging.getLogger(__name__)

FONT_TEXT = "Munro"
FONT_SCORE = "Pong Score"

SOUND_FILES = {
    Event.WALL: "ping.wav",
    Event.HIT: "pong.wav",
    Event.BOOST: "boost.wav",
    Event.SCORE: "error.wav",
}


class Scene:
    """Una schermata del gioco. La finestra inoltra gli eventi alla scena attiva;
    il disegno avviene in coordinate mondo (params.width x params.height)."""

    def __init__(self, app: PaddApp) -> None:
        self.app = app

    def enter(self) -> None: ...
    def update(self, dt: float) -> None: ...
    def draw(self) -> None: ...
    def key_press(self, key: int, modifiers: int) -> None: ...
    def key_release(self, key: int, modifiers: int) -> None: ...
    def encoder(self, event) -> None: ...


class PaddApp(arcade.Window):
    def __init__(self, cfg: Config, config_path: Path) -> None:
        self.cfg = cfg
        self.config_path = config_path
        if cfg.resolution.width <= 0:
            screen = pyglet.display.get_display().get_default_screen()
            cfg.resolution.width = auto_width(cfg.resolution.height, screen.width, screen.height)
            log.info("World size %dx%d (screen %dx%d)", cfg.resolution.width, cfg.resolution.height,
                     screen.width, screen.height)
        cfg.game.difficulty = max(0, min(len(DIFFICULTY_NAMES) - 1, cfg.game.difficulty))
        self.params = Params.from_config(cfg)
        w, h = self.params.width, self.params.height
        # Con il vsync è lo scambio dei buffer a cadenzare i frame: il disegno viene
        # schedulato più veloce di qualsiasi display, così il timer di pyglet non
        # entra mai in battimento con la frequenza di refresh.
        vsync = cfg.game.vsync
        draw_rate = 1 / 500 if vsync else 1 / max(1, cfg.game.fps)
        self.on_raspberry = is_raspberry_pi()
        # La GPU del Raspberry Pi 4/5 offre OpenGL ES 3.1, non OpenGL desktop 3.3
        gl = {"gl_api": "gles", "gl_version": (3, 1)} if self.on_raspberry else {}
        super().__init__(
            w, h, cfg.game.game_name,
            resizable=cfg.game.title_bar,
            style=None if cfg.game.title_bar else arcade.Window.WINDOW_STYLE_BORDERLESS,
            update_rate=draw_rate, draw_rate=draw_rate, vsync=vsync, center_window=True,
            **gl,
        )
        self._last_frame: float | None = None
        self._frame_times: list[float] = []
        self._pacing_checked = False
        self._gpu_sync = True
        self.background_color = arcade.color.BLACK
        self.set_mouse_visible(False)
        self._set_icon()

        # Opzioni di partita scelte nel menu (mantenute per tutta la sessione)
        self.players = 2
        self.evo = False

        self.encoders = Encoders.create(cfg.encoder)

        from paddws.attract import AttractArt, Hud
        self.attract_art = AttractArt()
        self.credits = 0                # crediti inseriti (contano solo senza Free Play)
        self._hud = Hud

        for font in ("munro.ttf", "pong-score.ttf"):
            arcade.load_font(paths.FONTS / font)
        self.sounds = {event: self._load_sound(name) for event, name in SOUND_FILES.items()}
        self.coin_sound = self._load_sound("coin.wav")
        for sound in filter(None, [*self.sounds.values(), self.coin_sound]):
            sound.play(volume=0)  # apre subito il dispositivo audio, non al primo colpo

        # La camera mappa la dimensione fissa del mondo sull'area (letterbox) della finestra
        self.camera = arcade.Camera2D(position=(w / 2, h / 2), projection=arcade.LRBT(-w / 2, w / 2, -h / 2, h / 2))
        self.crt = None

        if cfg.game.fullscreen:
            self.set_fullscreen(True)
        self._layout()

        from paddws.scenes import AttractScene
        self.scene: Scene = AttractScene(self, self_test=cfg.game.self_test)
        self.scene.enter()

    def _set_icon(self) -> None:
        """Icona della finestra: il sistema sceglie la dimensione più adatta."""
        try:
            self.set_icon(*(pyglet.image.load(paths.ICONS / f"paddws_{n}.png") for n in (16, 32, 48, 256)))
        except Exception as exc:  # icona mancante o formato non supportato: non è un errore fatale
            log.warning("Window icon not available: %s", exc)

    # ------------------------------------------------------------------- scene

    def show(self, scene: Scene) -> None:
        self.scene = scene
        scene.enter()

    def hud(self):
        """Scritte dell'attract che dipendono dai crediti."""
        return self._hud(None if self.cfg.game.free_play else self.credits)

    def play_coin(self) -> None:
        """Gettone inserito."""
        if self.coin_sound:
            self.coin_sound.play()

    def play(self, event: Event) -> None:
        sound = self.sounds.get(event)
        if sound:
            sound.play()

    @staticmethod
    def _load_sound(name: str) -> arcade.Sound | None:
        try:
            return arcade.Sound(paths.SOUNDS / name)
        except Exception as exc:
            log.warning("Sound %s not available: %s", name, exc)
            return None

    # ------------------------------------------------------------------ display

    def toggle_fullscreen(self) -> None:
        self.cfg.game.fullscreen = not self.cfg.game.fullscreen
        self.set_fullscreen(self.cfg.game.fullscreen)
        self._layout()
        save_preferences(self.config_path, self.cfg)

    def toggle_crt(self) -> None:
        self.cfg.crt_effects.enabled = not self.cfg.crt_effects.enabled
        self._layout()
        save_preferences(self.config_path, self.cfg)

    def next_difficulty(self) -> None:
        """Passa al livello di difficoltà successivo (vale dalla prossima partita)."""
        self.cfg.game.difficulty = (self.cfg.game.difficulty + 1) % len(DIFFICULTY_NAMES)
        self.params = Params.from_config(self.cfg)
        save_preferences(self.config_path, self.cfg)

    def _layout(self) -> None:
        """Adatta il mondo alla finestra e (ri)crea il filtro CRT alla sua dimensione.

        Arcade esprime i viewport dello schermo in unità finestra (applica da sé
        il pixel ratio HiDPI) ma quelli dei buffer offscreen in pixel reali:
        il letterbox è quindi calcolato in pixel e conservato in entrambe le unità.
        """
        fb_w, fb_h = self.get_framebuffer_size()
        ratio = self.get_pixel_ratio()
        w, h = self.params.width, self.params.height
        if self.cfg.game.keep_aspect:
            s = min(fb_w / w, fb_h / h)
            vw, vh = round(w * s), round(h * s)
        else:
            vw, vh = fb_w, fb_h
        self._viewport_px = arcade.LBWH((fb_w - vw) // 2, (fb_h - vh) // 2, vw, vh)
        self._viewport_win = arcade.LBWH(*(v / ratio for v in self._viewport_px.lbwh))
        # Un cambio di modalità video può cambiare il ritmo dei frame: si rimisura
        self._frame_times = []
        self._pacing_checked = False

        self.crt = None
        if self.cfg.crt_effects.enabled:
            try:
                from paddws.crt import CrtRenderer
                self.crt = CrtRenderer(self, self.cfg.crt_effects)
            except Exception as exc:  # es. shader non compilabile con il driver GLES
                log.error("CRT filter unavailable: %s", exc)

    def on_resize(self, width: int, height: int) -> None:
        super().on_resize(width, height)
        self._layout()

    # ------------------------------------------------------------------- eventi

    def _tick(self) -> None:
        """Avanza il gioco del tempo reale trascorso dal frame precedente.

        Viene chiamato da on_draw (invece che dal timer di update separato di
        Arcade) così avviene esattamente un aggiornamento per ogni frame
        presentato: nessuno scatto dovuto a due orologi non sincronizzati.
        """
        now = time.perf_counter()
        dt = 0.0 if self._last_frame is None else now - self._last_frame
        self._last_frame = now
        self._check_pacing(dt)
        if self.encoders:
            for event in self.encoders.poll():
                self.scene.encoder(event)
        self.scene.update(dt)

    def _refresh_rate(self) -> float:
        try:
            rate = self.screen.get_mode().rate
        except Exception:
            rate = None
        return max(30.0, min(360.0, rate or 60.0))

    def _check_pacing(self, dt: float) -> None:
        """Verifica il ritmo dei frame dopo l'avvio e dopo ogni cambio di modalità video.

        - Alcuni driver ignorano la richiesta di vsync: i frame non sono più cadenzati
          dallo scambio dei buffer e girerebbero senza limite. Se succede, il frame
          rate viene limitato alla frequenza del monitor.
        - L'attesa della GPU dopo il flip riduce la latenza, ma con alcuni compositor
          (es. fullscreen composto da Windows) fa perdere frame: in quel caso viene
          disattivata, perché la fluidità ha la precedenza.
        """
        if self._pacing_checked:
            return
        self._frame_times.append(dt)
        if len(self._frame_times) < 120:
            return
        self._pacing_checked = True
        refresh = self._refresh_rate()
        samples = sorted(self._frame_times[20:])  # i primi frame sono di riscaldamento
        median = samples[len(samples) // 2]
        if self.cfg.game.vsync and median < 0.75 / refresh:
            log.info("vsync not honored by the driver (%.0f fps): capping at %.0f Hz", 1 / median, refresh)
            self.set_update_rate(1 / refresh)
            self.set_draw_rate(1 / refresh)
        elif self._gpu_sync and median > 1.15 / refresh:
            log.info("frames late with GPU sync (%.0f fps on %.0f Hz): disabling it", 1 / median, refresh)
            self._gpu_sync = False
            self._frame_times = []
            self._pacing_checked = False  # rimisura senza attesa della GPU

    def on_draw(self) -> None:
        self._tick()
        self.clear()
        if self.crt:
            # Lo shader CRT campiona gl_FragCoord su tutta la finestra: la scena va
            # disegnata in un buffer grande quanto la finestra e filtrata a pieno schermo.
            self.crt.begin()
            self.camera.viewport = self.crt.viewport(self._viewport_px)
        else:
            self.camera.viewport = self._viewport_win
        self.camera.use()
        self.scene.draw()
        if self.crt:
            self.crt.present(self)

    def flip(self) -> None:
        super().flip()
        # Attende la GPU dopo lo scambio: il driver non può accodare frame in anticipo,
        # così l'input letto al frame successivo arriva a schermo un refresh dopo.
        if self._gpu_sync:
            self.ctx.finish()

    def on_key_press(self, key: int, modifiers: int) -> None:
        if key == arcade.key.F11:
            self.toggle_fullscreen()
        elif key == arcade.key.C:
            self.toggle_crt()
        else:
            self.scene.key_press(key, modifiers)

    def on_key_release(self, key: int, modifiers: int) -> None:
        self.scene.key_release(key, modifiers)
