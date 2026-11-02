"""Scene: attract, menu e partita."""

from __future__ import annotations

import logging
import math
import time

import arcade

from paddws import __version__
from paddws.app import FONT_SCORE, FONT_TEXT, PaddApp, Scene
from paddws.attract import Attract, View, draw_game_over
from paddws.core import Event, Match, Side
from paddws.core.input import DoubleTap
from paddws.config import save_preferences
from paddws.core.params import DIFFICULTY_NAMES
from paddws.hardware import EncoderAction, EncoderEvent, shutdown_system

log = logging.getLogger(__name__)

PHYSICS_STEP = 1 / 240      # passo fisso della simulazione: input applicato entro ~4 ms
MAX_FRAME_TIME = 0.25       # evita la "spirale della morte" dopo un blocco
FLASH_TIME = 0.05           # lampo bianco quando viene segnato un punto
SNAP_DISTANCE = 40          # spostamenti più lunghi in un passo sono teletrasporti: niente interpolazione

K = arcade.key


def _text(text: str, x: float, y: float, size: float, color, font: str = FONT_TEXT,
          rotation: float = 0, anchor_x: str = "center", anchor_y: str = "center") -> arcade.Text:
    return arcade.Text(text, x, y, color, size, font_name=font,
                       anchor_x=anchor_x, anchor_y=anchor_y, rotation=rotation)


# --------------------------------------------------------------------- attract

START_KEYS = (K.ENTER, K.RETURN, K.SPACE, K.KEY_1)      # come lo Start dei cabinati
COUNTDOWN_TIME = 3.0                                      # 3, 2, 1 prima del primo servizio


def _slide(cur: float, target: float, dt: float, unit: float) -> float:
    """Scatto in avanti a schermo: la racchetta raggiunge la nuova x dimezzando la distanza ogni
    1/60 s (almeno 6 pixel arcade), in circa 5 frame invece di teletrasportarsi, come nel core
    MiSTer. Solo grafica: la logica resta istantanea. `unit` è un pixel dello schermo 320x240."""
    d = target - cur
    if abs(d) > 100 * unit:
        return target  # nuova partita: nessuna animazione
    frames = dt * 60
    step = min(abs(d), max(abs(d) * (1 - 0.5 ** frames), 6 * unit * frames))
    return cur + math.copysign(step, d)


class AttractScene(Scene):
    """Sequenza attract; moneta con il tasto 5, Start per giocare se c'è credito o in Free Play."""

    def __init__(self, app: PaddApp, self_test: bool = False) -> None:
        super().__init__(app)
        self.attract = Attract(app.attract_art, self_test)
        self.view = View(app.params.width, app.params.height)

    def update(self, dt: float) -> None:
        for event in self.attract.update(dt, self.view, self.app.hud()):
            if self.app.cfg.game.attract_sound:
                self.app.play(event)

    def draw(self) -> None:
        self.attract.draw(self.view, self.app.hud())

    def key_press(self, key: int, modifiers: int) -> None:
        if key == K.ESCAPE:
            self.app.close()
        elif key == K.KEY_5:
            self._coin()
        elif key in START_KEYS:
            self._start()

    def encoder(self, event: EncoderEvent) -> None:
        if event.action is EncoderAction.CLICK:
            self._start()

    def _coin(self) -> None:
        app = self.app
        if not app.cfg.game.free_play and app.credits < 9:
            app.credits += 1
            app.play_coin()

    def _start(self) -> None:
        app = self.app
        if app.cfg.game.free_play or app.credits > 0:
            if not app.cfg.game.free_play:
                app.credits -= 1
            app.play(Event.HIT)
            app.show(MenuScene(app))


# ------------------------------------------------------------------------ menu

class MenuScene(Scene):
    def __init__(self, app: PaddApp) -> None:
        super().__init__(app)
        p, colors = app.params, app.cfg.colors
        s = p.scale
        self.items = ["GAME TYPE", "PLAYERS", "DIFFICULTY", "ATTRACT SOUND", "FULLSCREEN", "CRT", "PLAY", "QUIT"]
        if app.on_raspberry:
            self.items.append("SHUTDOWN")
        self.selected = self.items.index("PLAY")

        title_y = p.height - 100 * s
        self.title_box = arcade.LRBT(p.width / 2 - 150 * s, p.width / 2 + 150 * s,
                                     title_y - 30 * s, title_y + 30 * s)
        self.title = _text("MAIN MENU", p.width / 2, title_y, 50 * s, colors.black)

        first = p.height / 2 + 60 * s
        spacing = min(50 * s, (first - 40 * s) / (len(self.items) - 1))
        self.texts = [_text("", p.width / 2, first - i * spacing, 40 * s, colors.lgray)
                      for i in range(len(self.items))]
        # Versione in basso a destra: dice subito cosa gira sul cabinato
        self.version = _text(f"v{__version__}", p.width - 8 * s, 6 * s, 20 * s, colors.lgray,
                             anchor_x="right", anchor_y="bottom")
        self._refresh()

    def enter(self) -> None:
        if self.app.encoders:
            self.app.encoders.configure(0, len(self.items) - 1, 1, self.selected)

    def _label(self, item: str) -> str:
        app = self.app
        if item == "GAME TYPE":
            return f"GAME TYPE : {'EVO' if app.evo else 'CLASSIC'}"
        if item == "PLAYERS":
            return f"PLAYERS : {'TWO' if app.players == 2 else 'ONE'}"
        if item == "DIFFICULTY":
            return f"DIFFICULTY : {DIFFICULTY_NAMES[app.cfg.game.difficulty]}"
        if item == "ATTRACT SOUND":
            return f"ATTRACT SOUND : {'ON' if app.cfg.game.attract_sound else 'OFF'}"
        if item == "FULLSCREEN":
            return f"FULLSCREEN : {'ON' if app.cfg.game.fullscreen else 'OFF'}"
        if item == "CRT":
            return f"CRT FILTER : {'ON' if app.cfg.crt_effects.enabled else 'OFF'}"
        return item

    def _refresh(self) -> None:
        colors = self.app.cfg.colors
        for i, (item, text) in enumerate(zip(self.items, self.texts)):
            text.text = self._label(item)
            text.color = colors.white if i == self.selected else colors.lgray

    def _move(self, delta: int) -> None:
        self.selected = (self.selected + delta) % len(self.items)
        self._refresh()

    def _change(self, item: str) -> bool:
        """Cambia il valore di una voce di opzione; False se la voce è un'azione."""
        app = self.app
        if item == "GAME TYPE":
            app.evo = not app.evo
            if app.evo:
                app.players = 2  # EVO è una modalità a due giocatori
        elif item == "PLAYERS":
            app.players = 1 if app.players == 2 else 2
            if app.players == 1:
                app.evo = False
        elif item == "DIFFICULTY":
            app.next_difficulty()
        elif item == "ATTRACT SOUND":
            app.cfg.game.attract_sound = not app.cfg.game.attract_sound
            save_preferences(app.config_path, app.cfg)
        elif item == "FULLSCREEN":
            app.toggle_fullscreen()
        elif item == "CRT":
            app.toggle_crt()
        else:
            return False
        self._refresh()
        return True

    def _activate(self) -> None:
        item = self.items[self.selected]
        if self._change(item):
            return
        if item == "PLAY":
            self.app.show(GameScene(self.app))
        elif item == "QUIT":
            self.app.close()
        elif item == "SHUTDOWN":
            shutdown_system()

    def draw(self) -> None:
        arcade.draw_rect_filled(self.title_box, self.app.cfg.colors.white)
        self.title.draw()
        for text in self.texts:
            text.draw()
        self.version.draw()

    def key_press(self, key: int, modifiers: int) -> None:
        if key in (K.UP, K.W):
            self._move(-1)
        elif key in (K.DOWN, K.S):
            self._move(1)
        elif key in (K.LEFT, K.RIGHT, K.A, K.D):
            self._change(self.items[self.selected])
        elif key in (K.ENTER, K.RETURN, K.SPACE):
            self._activate()
        elif key == K.ESCAPE:
            self.app.show(AttractScene(self.app))
            return
        else:
            return
        self._refresh()  # i toggle C/F11 sono gestiti dalla finestra

    def encoder(self, event: EncoderEvent) -> None:
        if event.action is EncoderAction.ROTATE:
            self.selected = max(0, min(len(self.items) - 1, event.value))
            self._refresh()
        elif event.action is EncoderAction.CLICK:
            self._activate()


# ---------------------------------------------------------------------- partita

# lato -> (tasto su, tasto giù, tasto avanti)
CONTROLS = {
    Side.LEFT: (K.W, K.S, K.D),
    Side.RIGHT: (K.UP, K.DOWN, K.LEFT),
}


class GameScene(Scene):
    def __init__(self, app: PaddApp) -> None:
        super().__init__(app)
        p, colors = app.params, app.cfg.colors
        s = p.scale
        self.match = Match(p, players=app.players, evo=app.evo)
        self.taps = DoubleTap(app.cfg.paddle.double_click_time)
        self.held: set[int] = set()
        self.accumulator = 0.0
        self.flash = 0.0
        self.paused = False
        self.lives = max(1, app.cfg.game.lives)        # palle a disposizione in singolo
        self.game_over: float | None = None           # secondi rimasti del GAME OVER
        self.world = arcade.LBWH(0, 0, p.width, p.height)
        self.view = View(p.width, p.height)

        # Linea tratteggiata centrale: creata una volta, disegnata in un unico batch
        self.background = arcade.SpriteList(use_spatial_hash=False)
        dash = max(1, int(10 * s))
        line_width = max(1, int(p.pad_width // 2 * p.width / 800))
        for y in range(0, p.height, dash * 2):
            h = min(dash, p.height - y)
            self.background.append(arcade.SpriteSolidColor(line_width, h, p.width / 2, y + h / 2, colors.white))

        self.sprites = arcade.SpriteList()
        self.pad_sprites = [arcade.SpriteSolidColor(int(pad.width), int(pad.height), color=colors.white)
                            for pad in self.match.paddles]
        self.boost_sprites = [arcade.SpriteSolidColor(int(pad.width), 1, color=colors.lgray)
                              for pad in self.match.paddles]
        self.ball_sprite = arcade.SpriteSolidColor(2, 2, color=colors.white)
        self.sprites.extend(self.pad_sprites)
        self.sprites.extend(self.boost_sprites)
        self.sprites.append(self.ball_sprite)
        for sprite in self.boost_sprites:
            sprite.visible = self.match.evo

        # I punteggi sono rivolti ai giocatori, seduti ai lati sinistro e destro del tavolo
        cx = p.width / 2
        offset_x, offset_y = 60 * p.width / 800, 60 * p.height / 480
        self.score_texts = [
            _text("", cx - offset_x, offset_y, 50 * s, colors.white, FONT_SCORE, rotation=90),
            _text("", cx + offset_x, p.height - offset_y, 50 * s, colors.white, FONT_SCORE, rotation=-90),
        ]
        # Record in singolo: abbastanza grande da restare leggibile anche con il filtro CRT.
        # pyglet centra sulla larghezza tipografica, non sull'inchiostro, e i due font hanno
        # metriche diverse: i 14.5 compensano lo scarto misurato e allineano i centri visivi.
        self.best_text = _text("", cx - offset_x - 55 * s, offset_y + 14.5 * s, 32 * s, colors.white, rotation=90)
        # palle rimaste in singolo, accanto al record
        self.balls_text = _text("", cx - offset_x - 85 * s, offset_y + 14.5 * s, 32 * s, colors.white, rotation=90)
        self.pause_text = _text("PAUSE", cx, p.height / 2, 60 * s, colors.white)
        # conto alla rovescia (3, 2, 1) prima del primo servizio: intanto la partita resta ferma
        self.countdown = COUNTDOWN_TIME
        self.countdown_text = _text("3", cx, p.height / 2, 110 * s, colors.white, FONT_SCORE)
        self.countdown_box = arcade.XYWH(cx, p.height / 2, 121 * s, 132 * s)
        # Rasterizza subito tutti i glifi: una cifra nuova a metà partita non deve costare un frame
        for text in (*self.score_texts, self.best_text, self.balls_text):
            text.text = "TOP BALS 0123456789"
        self._shown_score = None
        self._previous = self._snapshot()
        self._pad_draw_x = [pad.x for pad in self.match.paddles]
        self._sync()

    def enter(self) -> None:
        if self.app.encoders:
            travel = self.app.params.height - self.app.params.pad_height
            self.app.encoders.configure(0, travel, 20, travel // 2)

    # ---------------------------------------------------------- aggiornamento

    def update(self, dt: float) -> None:
        if self.game_over is not None:
            self.game_over -= dt
            if self.game_over <= 0:
                self.app.show(AttractScene(self.app))
            return
        if self.paused:
            return
        if self.countdown > 0:
            # un bip a ogni secondo, poi il via; la logica non avanza
            before = math.ceil(self.countdown)
            self.countdown -= dt
            if self.countdown <= 0:
                self.countdown = 0.0
                self.app.play(Event.BOOST)
            elif math.ceil(self.countdown) < before:
                self.app.play(Event.WALL)
            self.countdown_text.text = str(max(1, math.ceil(self.countdown)))
            return
        self.flash = max(0.0, self.flash - dt)
        self.accumulator += min(dt, MAX_FRAME_TIME)
        while self.accumulator >= PHYSICS_STEP:
            self.accumulator -= PHYSICS_STEP
            self._previous = self._snapshot()
            self._handle(self.match.step(PHYSICS_STEP))
            if self._finished():
                self.game_over = self.app.attract_art.game_over_seconds
                break
        unit = self.match.p.height / 240
        self._pad_draw_x = [_slide(x, pad.x, dt, unit) for x, pad in zip(self._pad_draw_x, self.match.paddles)]
        self._sync()

    def _finished(self) -> bool:
        """Fine partita: chi arriva per primo ai punti stabiliti, o le vite finite in singolo."""
        if self.match.players == 2:
            return max(self.match.score) >= max(1, self.app.cfg.game.points_to_win)
        return self.lives == 0

    def _snapshot(self) -> list[tuple[float, float]]:
        m = self.match
        return [(pad.x, pad.y) for pad in m.paddles] + [(m.ball.x, m.ball.y)]

    def _handle(self, events: list[Event]) -> None:
        for event in events:
            self.app.play(event)
            if event is Event.SCORE:
                self.flash = FLASH_TIME
                if self.match.players == 1:
                    self.lives = max(0, self.lives - 1)    # palla mancata contro il muro

    def _sync(self) -> None:
        """Riporta lo stato della simulazione su sprite ed etichette.

        Le posizioni sono interpolate tra gli ultimi due passi di fisica, così il
        movimento è fluido qualunque sia il rapporto tra refresh e passo fisso.
        """
        m = self.match
        alpha = self.accumulator / PHYSICS_STEP
        snap = SNAP_DISTANCE * m.p.scale
        positions = []
        for (x0, y0), (x1, y1) in zip(self._previous, self._snapshot()):
            if abs(x1 - x0) > snap or abs(y1 - y0) > snap:
                positions.append((x1, y1))
            else:
                positions.append((x0 + (x1 - x0) * alpha, y0 + (y1 - y0) * alpha))

        for i, (pad, sprite, boost, pos) in enumerate(zip(m.paddles, self.pad_sprites, self.boost_sprites, positions)):
            sprite.position = boost.position = (self._pad_draw_x[i], pos[1])
            boost.height = max(1, pad.boost_height)
        b = m.ball
        self.ball_sprite.position = positions[-1]
        self.ball_sprite.width = self.ball_sprite.height = 2 * b.radius
        self.ball_sprite.visible = m.serve_timer <= 0 or int(m.serve_timer * 8) % 2 == 0

        score = (*m.score, m.best, self.lives)
        if score != self._shown_score:
            self._shown_score = score
            self.score_texts[0].text = f"{m.score[0]:02d}"
            self.score_texts[1].text = f"{m.score[1]:02d}"
            self.best_text.text = f"TOP {m.best:02d}"
            self.balls_text.text = f"BALLS {self.lives}"

    def draw(self) -> None:
        if self.flash > 0:
            arcade.draw_rect_filled(self.world, self.app.cfg.colors.white)
            return
        self.background.draw()
        self.sprites.draw()
        self.score_texts[0].draw()
        if self.match.players == 2:
            self.score_texts[1].draw()
        else:
            self.best_text.draw()
            self.balls_text.draw()
        if self.countdown > 0:
            arcade.draw_rect_filled(self.countdown_box, arcade.color.BLACK)
            self.countdown_text.draw()
        if self.paused:
            self.pause_text.draw()
        if self.game_over is not None:
            draw_game_over(self.app.attract_art, self.view)

    # ------------------------------------------------------------------ input

    def _active_sides(self):
        return (Side.LEFT, Side.RIGHT) if self.match.players == 2 else (Side.LEFT,)

    def key_press(self, key: int, modifiers: int) -> None:
        if self.game_over is not None:
            return
        if key == K.ESCAPE:
            self.app.show(MenuScene(self.app))
            return
        if key in (K.P, K.PAUSE):
            self.paused = not self.paused
            return
        if self.paused:
            return
        for side in self._active_sides():
            up, down, forward = CONTROLS[side]
            if key in (up, down):
                self.held.add(key)
                fast = self.taps.press(key, time.monotonic() * 1000)
                self.match.paddles[side].set_direction(1 if key == up else -1, fast)
            elif key == forward:
                self._handle(self.match.toggle_forward(side))

    def key_release(self, key: int, modifiers: int) -> None:
        self.held.discard(key)
        for side in self._active_sides():
            up, down, _ = CONTROLS[side]
            if key in (up, down):
                pad = self.match.paddles[side]
                other = down if key == up else up
                if other in self.held:  # il tasto opposto è ancora premuto
                    pad.set_direction(1 if other == up else -1, pad.fast)
                else:
                    pad.set_direction(0)

    def encoder(self, event: EncoderEvent) -> None:
        side = Side(event.player)
        if side not in self._active_sides():
            return
        if event.action is EncoderAction.ROTATE:
            self.match.set_paddle_top(side, event.value)
        elif event.action is EncoderAction.CLICK:
            self._handle(self.match.toggle_forward(side))
        elif event.action is EncoderAction.LONG_CLICK:
            self.app.show(MenuScene(self.app))
