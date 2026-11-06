import random

import pytest

from paddws.config import Config
from paddws.core import TICK, Event, Match, Params, Side
from paddws.core.input import DoubleTap


@pytest.fixture
def params() -> Params:
    cfg = Config()
    cfg.resolution.width = 800
    cfg.game.serve_delay = 0
    return Params.from_config(cfg)


def make_match(params, players=2, evo=False, seed=1) -> Match:
    return Match(params, players=players, evo=evo, rng=random.Random(seed))


def run(match: Match, ticks: int, dt: float = TICK) -> list[Event]:
    events = []
    for _ in range(ticks):
        events += match.step(dt)
    return events


def aim_at_paddle(match: Match, side: Side, vx: float, offset_y: float = 0.0) -> None:
    pad, ball = match.paddles[side], match.ball
    pad.y = match.p.height / 2
    ball.y = pad.y + offset_y
    ball.x = match.p.width / 2
    ball.vx = -abs(vx) if side is Side.LEFT else abs(vx)
    ball.vy = 0


def test_scaling_matches_reference_resolution(params):
    assert (params.width, params.height) == (800, 480)
    assert params.pad_height == 80 and params.ball_radius == 5


def test_paddle_returns_ball_and_speeds_it_up(params):
    m = make_match(params)
    aim_at_paddle(m, Side.LEFT, vx=3)
    events = run(m, 200)
    assert Event.HIT in events
    assert m.score == [0, 0]
    assert m.ball.vx > 0 and abs(m.ball.vx) == pytest.approx(3 * params.kspeed_2p)


@pytest.mark.parametrize("side", [Side.LEFT, Side.RIGHT])
def test_fast_ball_does_not_tunnel_through_paddle(params, side):
    m = make_match(params)
    aim_at_paddle(m, side, vx=60)  # 60 px per tick, molto più della racchetta larga 10 px
    events = run(m, 20)
    assert Event.HIT in events
    assert Event.SCORE not in events


def test_miss_gives_point_to_opponent_and_serves_to_loser(params):
    m = make_match(params)
    aim_at_paddle(m, Side.LEFT, vx=4)
    m.paddles[Side.LEFT].y = m.paddles[Side.LEFT].height / 2  # fuori traiettoria
    m.ball.y = params.height - 50
    events = run(m, 200)
    assert Event.SCORE in events
    assert m.score == [0, 1]
    assert m.ball.vx < 0  # la battuta successiva va verso chi ha subito il punto


def test_single_player_wall_does_not_speed_up_ball(params):
    m = make_match(params, players=1)
    aim_at_paddle(m, Side.RIGHT, vx=3)
    run(m, 150)
    assert m.ball.vx == pytest.approx(-3)
    aim_at_paddle(m, Side.LEFT, vx=3)
    run(m, 150)
    assert m.ball.vx == pytest.approx(3 * params.kspeed_1p)


@pytest.mark.parametrize("level", range(3))
def test_difficulty_levels_grow_harder(level):
    def at(difficulty):
        cfg = Config()
        cfg.resolution.width = 800
        cfg.game.difficulty = difficulty
        return Params.from_config(cfg)
    easy, hard = at(level), at(level + 1)
    assert easy.kspeed_1p < hard.kspeed_1p and easy.max_ball_speed_1p < hard.max_ball_speed_1p
    assert easy.kspeed_2p <= hard.kspeed_2p and easy.max_ball_speed_2p < hard.max_ball_speed_2p


def test_single_player_scores_on_wall_and_records_best(params):
    m = make_match(params, players=1)
    assert m.paddles[Side.RIGHT].height == params.height
    aim_at_paddle(m, Side.RIGHT, vx=3)
    run(m, 150)
    assert m.score[Side.LEFT] == 1
    # ora la palla sfugge a sinistra
    aim_at_paddle(m, Side.LEFT, vx=4)
    m.paddles[Side.LEFT].y = m.paddles[Side.LEFT].height / 2
    m.ball.y = params.height - 50
    run(m, 200)
    assert m.score[Side.LEFT] == 0
    assert m.best == 1


def test_evo_center_hit_boosts_and_shrinks_area(params):
    m = make_match(params, evo=True)
    pad = m.paddles[Side.LEFT]
    ratio_before = pad.boost_ratio
    aim_at_paddle(m, Side.LEFT, vx=3)
    events = run(m, 200)
    assert Event.BOOST in events
    assert m.ball.boost == params.boost_mul
    assert pad.boost_ratio > ratio_before


def test_evo_requires_two_players(params):
    assert not make_match(params, players=1, evo=True).evo


def test_forward_move_catches_ball(params):
    m = make_match(params, evo=True)
    pad = m.paddles[Side.LEFT]
    m.ball.x = (pad.home_x + pad.fwd_x) / 2
    m.ball.y = pad.y
    m.ball.vx, m.ball.vy = -3, 0
    events = m.toggle_forward(Side.LEFT)
    assert events == [Event.BOOST]
    assert m.ball.vx > 0
    assert not pad.at_home
    assert m.toggle_forward(Side.LEFT) == [] and pad.at_home


def test_ball_never_leaves_the_field_vertically(params):
    m = make_match(params, seed=7)
    for _ in range(5000):
        m.step(TICK / 4)
        assert 0 <= m.ball.bottom and m.ball.top <= params.height


def test_simulation_is_frame_rate_independent(params):
    """Lo stesso secondo di gioco a 60 Hz e a 240 Hz deve finire quasi nello stesso punto."""
    a, b = make_match(params), make_match(params)
    for m in (a, b):
        m.ball.x, m.ball.y, m.ball.vx, m.ball.vy = 400, 240, 2, 1
    run(a, 60, TICK)
    run(b, 240, TICK / 4)
    assert a.ball.x == pytest.approx(b.ball.x)
    assert a.ball.y == pytest.approx(b.ball.y)


def test_paddle_acceleration_and_bounds(params):
    m = make_match(params)
    pad = m.paddles[Side.LEFT]
    pad.set_direction(1)
    run(m, 600)
    assert pad.top == params.height and pad.speed == 0
    pad.set_direction(-1, fast=True)
    run(m, 600)
    assert pad.bottom == 0


def test_serve_delay_holds_ball():
    cfg = Config()
    cfg.resolution.width = 800
    cfg.game.serve_delay = 0.5
    m = make_match(Params.from_config(cfg))
    x = m.ball.x
    run(m, 20)
    assert m.ball.x == x
    run(m, 20)
    assert m.ball.x != x


def test_encoder_positions_paddle_from_top(params):
    m = make_match(params)
    m.set_paddle_top(Side.LEFT, 0)
    assert m.paddles[Side.LEFT].top == params.height
    m.set_paddle_top(Side.LEFT, 10_000)
    assert m.paddles[Side.LEFT].bottom == 0


def test_double_tap():
    tap = DoubleTap(300)
    assert not tap.press("w", 0)
    assert tap.press("w", 200)
    assert not tap.press("w", 600)
    assert not tap.press("s", 650)
