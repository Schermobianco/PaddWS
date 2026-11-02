"""Pipeline del filtro CRT a costo limitato.

Lo shader CRT di Arcade costa per pixel di uscita: a risoluzione nativa su
schermi grandi (1440p, 4K) supera il budget del frame. Il filtro lavora quindi
a una risoluzione interna di al massimo ~720p (le scanline emulate sono ~240,
quindi bastano) e il risultato viene ingrandito
a schermo con filtro lineare; la densità delle scanline viene compensata così
l'aspetto non cambia.
"""

from __future__ import annotations

import math

import arcade
from arcade.experimental.crt_filter import CRTFilter
from arcade.gl import geometry
from pyglet.math import Vec2

from paddws.config import CrtConfig

MAX_PIXELS = 1280 * 720

_VERTEX = """
#version 330
in vec2 in_vert;
in vec2 in_uv;
out vec2 uv;
void main() {
    gl_Position = vec4(in_vert, 0.0, 1.0);
    uv = in_uv;
}
"""

_FRAGMENT = """
#version 330
uniform sampler2D tex;
in vec2 uv;
out vec4 color;
void main() {
    color = texture(tex, uv);
}
"""


class CrtRenderer:
    def __init__(self, window: arcade.Window, cfg: CrtConfig) -> None:
        ctx = window.ctx
        fb_w, fb_h = window.get_framebuffer_size()
        self.scale = min(1.0, math.sqrt(MAX_PIXELS / (fb_w * fb_h)))
        w, h = max(1, round(fb_w * self.scale)), max(1, round(fb_h * self.scale))
        self.filter = CRTFilter(
            w, h,
            resolution_down_scale=cfg.resolution_scale * self.scale,
            hard_scan=cfg.hard_scan,
            hard_pix=cfg.hard_pix,
            display_warp=Vec2(cfg.warp_x, cfg.warp_y),
            mask_dark=cfg.mask_dark,
            mask_light=cfg.mask_light,
        )
        self.output = None
        if self.scale < 1.0:
            texture = ctx.texture((w, h), components=4, filter=(ctx.LINEAR, ctx.LINEAR))
            self.output = ctx.framebuffer(color_attachments=[texture])
            self.program = ctx.program(vertex_shader=_VERTEX, fragment_shader=_FRAGMENT)
            self.program["tex"] = 0
            self.quad = geometry.quad_2d_fs()

    def viewport(self, viewport_px: arcade.types.Rect) -> arcade.types.Rect:
        """Riporta un viewport in pixel dello schermo sulla risoluzione interna del filtro."""
        return arcade.LBWH(*(v * self.scale for v in viewport_px.lbwh))

    def begin(self) -> None:
        """Attiva il buffer in cui va disegnata la scena."""
        self.filter.use()
        self.filter.clear()

    def present(self, window: arcade.Window) -> None:
        """Applica lo shader CRT e mostra il risultato su tutta la finestra."""
        if self.output:
            self.output.use()
            self.filter.draw()
        window.use()
        window.ctx.viewport = (0, 0, window.width, window.height)
        if self.output:
            self.output.color_attachments[0].use(0)
            self.quad.render(self.program)
        else:
            self.filter.draw()
