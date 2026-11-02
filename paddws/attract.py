"""Sequenza "attract" in stile cabinato anni '80: auto-test, strisce, logo, titolo.

Tempi, posizioni e bitmap vengono da assets/attract/ (tools/gen_attract_assets.py),
gli stessi della versione Rust e del core MiSTer. Tutto è definito su uno schermo
virtuale 320x240 (y verso il basso) ingrandito di altezza/240 intorno al centro del
campo; le strisce arrivano ai bordi anche sugli schermi più larghi. La demo di gioco
esiste solo nel core MiSTer.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from enum import Enum

import arcade
from PIL import Image

from paddws import paths
from paddws.core import Event

FRAME = 1 / 60
VW, VH = 320, 240
DIGITS = [f"digit_{d}" for d in range(10)]


class AttractArt:
    """Spec e bitmap della sequenza: texture per il disegno, pixel per i rimbalzi."""

    def __init__(self) -> None:
        self.spec = json.loads((paths.ATTRACT / "attract.json").read_text(encoding="utf-8"))
        self.textures: dict[str, arcade.Texture] = {}
        self.masks: dict[str, tuple[int, int, bytes]] = {}
        for png in paths.ATTRACT.glob("*.png"):
            self.textures[png.stem] = arcade.load_texture(png)
            alpha = Image.open(png).convert("RGBA").getchannel("A")
            self.masks[png.stem] = (alpha.width, alpha.height, alpha.tobytes())

    def size(self, name: str) -> tuple[int, int]:
        w, h, _ = self.masks[name]
        return w, h

    def lit(self, name: str, x: int, y: int) -> bool:
        w, h, data = self.masks[name]
        return 0 <= x < w and 0 <= y < h and data[y * w + x] > 127

    def color(self, name: str) -> arcade.types.Color:
        return arcade.types.Color(*self.spec["colors"][name])

    @property
    def game_over_seconds(self) -> float:
        return self.spec["frames"]["game_over"] * FRAME


class View:
    """Schermo virtuale 320x240 ingrandito sul campo (y del campo verso l'alto)."""

    def __init__(self, world_w: float, world_h: float) -> None:
        self.k = world_h / VH
        self.cx = world_w / 2
        self.world_h = world_h
        half = world_w / 2 / self.k
        self.left = VW / 2 - half
        self.right = VW / 2 + half

    def lbwh(self, x: float, y: float, w: float, h: float) -> arcade.types.Rect:
        k = self.k
        return arcade.LBWH(self.cx + (x - VW / 2) * k, self.world_h - (y + h) * k, w * k, h * k)

    def rect(self, x: float, y: float, w: float, h: float, color) -> None:
        arcade.draw_rect_filled(self.lbwh(x, y, w, h), color)

    def bitmap(self, art: AttractArt, name: str, x: float, y: float, scale: float, color) -> None:
        w, h = art.size(name)
        arcade.draw_texture_rect(art.textures[name], self.lbwh(x, y, w * scale, h * scale), color=color, pixelated=True)


@dataclass(frozen=True)
class Hud:
    """Scritte del titolo che dipendono dai crediti; credits None = Free Play."""

    credits: int | None

    @property
    def label(self) -> str:
        return "insert_coin" if self.credits == 0 else "press_start"


class Phase(Enum):
    BOOT = "boot"
    STRIPES = "stripes"
    LOGO = "logo"
    TITLE = "title"


class Attract:
    def __init__(self, art: AttractArt, self_test: bool) -> None:
        self.art = art
        self.acc = 0.0
        self._enter(Phase.BOOT if self_test else Phase.STRIPES)

    def _enter(self, phase: Phase) -> None:
        self.phase = phase
        self.frame = 0
        self.fired: set[int] = set()
        b = self.art.spec["title"]["ball"]
        self.ball = [b["x"], b["y"], b["vx"], b["vy"]]

    def _once(self, key: int, event: Event, sounds: list[Event]) -> None:
        if key not in self.fired:
            self.fired.add(key)
            sounds.append(event)

    # ------------------------------------------------------------- avanzamento

    def update(self, dt: float, view: View, hud: Hud) -> list[Event]:
        """Avanza la sequenza del tempo reale dt; restituisce i suoni da riprodurre."""
        sounds: list[Event] = []
        self.acc += min(dt, 0.25)
        while self.acc >= FRAME:
            self.acc -= FRAME
            self.step(view, hud, sounds)
        return sounds

    def step(self, view: View, hud: Hud, sounds: list[Event]) -> None:
        """Un frame a 60 Hz."""
        s, f = self.art.spec, self.frame
        if self.phase is Phase.BOOT:
            b = s["boot"]
            if f < b["grid_from"]:
                shown = min(len(b["lines"]), f // b["line_frames"] + 1)
                for i in range(shown):
                    if b["lines"][i]:
                        self._once(i, Event.HIT if i == 0 else Event.WALL, sounds)
            else:
                self._once(99, Event.BOOST, sounds)
        elif self.phase is Phase.STRIPES:
            last = len(s["stripes"]["slide"]) - 1
            for i in range(6):
                if f >= i * s["stripes"]["start_step"] + last:
                    self._once(i, Event.HIT, sounds)
        elif self.phase is Phase.LOGO:
            if f >= s["logo"]["wipe_frames"]:
                self._once(0, Event.BOOST, sounds)
        elif self._step_ball(view, hud):
            sounds.append(Event.WALL)

        self.frame += 1
        if self.frame >= s["frames"][self.phase.value]:
            following = {Phase.BOOT: Phase.STRIPES, Phase.STRIPES: Phase.LOGO,
                         Phase.LOGO: Phase.TITLE, Phase.TITLE: Phase.STRIPES}
            self._enter(following[self.phase])

    # ------------------------------------------------------------------ pallina

    def _label_visible(self) -> bool:
        t = self.art.spec["title"]
        return self.frame > t["label_from"] and self.frame % t["blink_period"] < t["blink_on"]

    def _black(self, hud: Hud, x: int, y: int) -> bool:
        """Il pixel virtuale (x, y) del titolo è nero? Strisce, logo e scritte, esclusa la pallina."""
        art, s = self.art, self.art.spec
        st = s["stripes"]
        for row in st["rows"]:
            if row <= y < row + st["height"] and (x < st["left_end"] or x >= st["right_start"]):
                return not art.lit("ws", x - s["ws"]["x"], y - s["ws"]["y"])     # "WS" è giallo
        if art.lit("logo", x - s["logo"]["x"], y - s["logo"]["y"]):
            return True
        t = s["title"]
        if self._label_visible() and _centered_lit(art, hud.label, t["label_scale"], t["label_y"], x, y):
            return True
        if any(art.lit(name, x - x0, y - t["credit_y"]) for name, x0 in _credit_line(art, hud)):
            return True
        return _centered_lit(art, "copyright", 1, t["copyright_y"], x, y)

    def _blocked(self, view: View, hud: Hud, x: float, y: float) -> bool:
        size = self.art.spec["title"]["ball"]["size"]
        ix, iy = round(x), round(y)
        if ix < math.ceil(view.left) or ix > math.floor(view.right) - size or iy < 0 or iy > VH - size:
            return True                                                     # i bordi dello schermo
        return any(self._black(hud, ix + dx, iy + dy) for dy in range(size) for dx in range(size))

    def _step_ball(self, view: View, hud: Hud) -> bool:
        """La pallina rimbalza contro i bordi e contro qualunque pixel nero, un asse alla volta."""
        x, y, vx, vy = self.ball
        size = self.art.spec["title"]["ball"]["size"]
        if self._blocked(view, hud, x, y):
            # una scritta è comparsa sopra la pallina: la si lascia uscire
            self.ball = [min(max(x + vx, math.ceil(view.left)), math.floor(view.right) - size),
                         min(max(y + vy, 0), VH - size), vx, vy]
            return False
        bounced = False
        nx = x + vx
        if self._blocked(view, hud, nx, y):
            nx, vx, bounced = x, -vx, True
        ny = y + vy
        if self._blocked(view, hud, nx, ny):
            ny, vy, bounced = y, -vy, True
        self.ball = [nx, ny, vx, vy]
        return bounced

    # ------------------------------------------------------------------ disegno

    def draw(self, view: View, hud: Hud) -> None:
        art, s, f = self.art, self.art.spec, self.frame
        yellow, black, white = art.color("yellow"), art.color("black"), art.color("white")
        full = (view.left, 0, view.right - view.left, VH)
        if self.phase is Phase.BOOT:
            view.rect(*full, black)
            b = s["boot"]
            if f < b["grid_from"]:
                phosphor = art.color("phosphor")
                shown = min(len(b["lines"]), f // b["line_frames"] + 1)
                cursor_x = b["x"]
                for i, name in enumerate(b["lines"][:shown]):
                    cursor_x = b["x"]
                    if name:
                        view.bitmap(art, name, b["x"], b["y"] + i * b["line_step"], 1, phosphor)
                        cursor_x = b["x"] + art.size(name)[0]
                if (f // (b["cursor_period"] // 2)) % 2 == 0:
                    view.rect(cursor_x + 2, b["y"] + (shown - 1) * b["line_step"], *b["cursor"], phosphor)
            else:
                # reticolo di test dei vecchi cabinati
                step = b["grid_step"]
                x = math.floor(view.left / step) * step
                while x <= view.right:
                    view.rect(x, 0, 1, VH, white)
                    x += step
                for y in range(0, VH, step):
                    view.rect(view.left, y, view.right - view.left, 1, white)
                view.rect(view.left, VH - 1, view.right - view.left, 1, white)
        elif self.phase is Phase.STRIPES:
            view.rect(*full, yellow)
            st = s["stripes"]
            last = len(st["slide"]) - 1
            progress = [st["slide"][min(last, max(0, f - i * st["start_step"]))] / 1000 for i in range(6)]
            _draw_stripes(art, view, progress, black)
        elif self.phase is Phase.LOGO:
            view.rect(*full, yellow)
            _draw_stripes(art, view, [1] * 6, black)
            view.bitmap(art, "ws", s["ws"]["x"], s["ws"]["y"], 1, yellow)
            lg = s["logo"]
            w, h = art.size("logo")
            view.bitmap(art, "logo", lg["x"], lg["y"], 1, black)
            if f < lg["wipe_frames"]:
                rows = math.floor(h * f / lg["wipe_frames"])
                view.rect(lg["x"], lg["y"] + rows, w, h - rows, yellow)      # righe non ancora disegnate
                view.rect(lg["x"], lg["y"] + rows + 1, w, 1, white)           # il raster che scende
            elif f < lg["wipe_frames"] + lg["flash_frames"]:
                view.rect(*full, white)                                       # lampo
        else:
            t = s["title"]
            view.rect(*full, yellow)
            _draw_stripes(art, view, [1] * 6, black)
            if not any(a <= f < b for a, b in s["ws"]["off"]):
                view.bitmap(art, "ws", s["ws"]["x"], s["ws"]["y"], 1, yellow)
            view.bitmap(art, "logo", s["logo"]["x"], s["logo"]["y"], 1, black)
            if self._label_visible():
                _draw_centered(art, view, hud.label, t["label_scale"], t["label_y"], black)
            for name, x0 in _credit_line(art, hud):
                view.bitmap(art, name, x0, t["credit_y"], 1, black)
            _draw_centered(art, view, "copyright", 1, t["copyright_y"], black)
            size = t["ball"]["size"]
            view.rect(round(self.ball[0]), round(self.ball[1]), size, size, black)


def draw_game_over(art: AttractArt, view: View) -> None:
    """"GAME OVER" al centro, su un riquadro nero sopra la partita."""
    w, h = art.size("game_over")
    y = art.spec["game_over"]["label_y"]
    box_w, box_h = w * 2 + 12, h * 2 + 10
    view.rect(round((VW - box_w) / 2), y - 5, box_w, box_h, art.color("black"))
    _draw_centered(art, view, "game_over", 2, y, art.color("white"))


def _draw_stripes(art: AttractArt, view: View, progress: list[float], color) -> None:
    st = art.spec["stripes"]
    for i, row in enumerate(st["rows"]):
        # la striscia sinistra arriva al bordo sinistro, la destra a quello destro
        len_l = st["left_end"] - view.left
        right_edge = view.left + len_l * progress[i * 2]
        view.rect(right_edge - len_l, row, len_l, st["height"], color)
        len_r = view.right - st["right_start"]
        left_edge = view.right - len_r * progress[i * 2 + 1]
        view.rect(left_edge, row, len_r + 1, st["height"], color)


def _centered_x(art: AttractArt, name: str, scale: float) -> int:
    return round((VW - art.size(name)[0] * scale) / 2)


def _draw_centered(art: AttractArt, view: View, name: str, scale: float, y: float, color) -> None:
    view.bitmap(art, name, _centered_x(art, name, scale), y, scale, color)


def _centered_lit(art: AttractArt, name: str, scale: int, y0: int, x: int, y: int) -> bool:
    x0 = _centered_x(art, name, scale)
    return x >= x0 and y >= y0 and art.lit(name, (x - x0) // scale, (y - y0) // scale)


def _credit_line(art: AttractArt, hud: Hud) -> list[tuple[str, int]]:
    """"CREDIT n" (o "FREE PLAY") centrato: bitmap e posizione x di ogni pezzo."""
    parts = ["free_play"] if hud.credits is None else ["credit", DIGITS[min(hud.credits, 9)]]
    x = round((VW - sum(art.size(p)[0] for p in parts)) / 2)
    out = []
    for p in parts:
        out.append((p, x))
        x += art.size(p)[0]
    return out
