import json

import pytest

from paddws.config import Config, auto_width, config_from_dict, load_config, save_preferences
from paddws.core import Params


@pytest.mark.parametrize("screen, width", [
    ((1024, 768), 640),     # 4:3
    ((640, 480), 640),      # 4:3 CRT
    ((1920, 1080), 853),    # 16:9
    ((2560, 1440), 853),    # 16:9
    ((800, 480), 800),      # display del Raspberry Pi
    ((1280, 1024), 600),    # 5:4
])
def test_auto_width_follows_screen_aspect(screen, width):
    assert auto_width(480, *screen) == width


def test_partial_file_keeps_defaults():
    cfg = config_from_dict({"resolution": {"width": 1600}, "colors": {"white": [1, 2, 3]}})
    assert cfg.resolution.width == 1600
    assert cfg.resolution.height == 480
    assert cfg.colors.white == (1, 2, 3)
    assert cfg.paddle.height == 80


def test_unknown_keys_are_ignored(caplog):
    cfg = config_from_dict({"ball": {"spin": 3}, "extra": 1})
    assert cfg.ball.radius == 5
    assert "ball.spin" in caplog.text


def test_missing_file_is_created(tmp_path):
    path = tmp_path / "cfg.json"
    cfg = load_config(path)
    assert path.exists()
    assert config_from_dict(json.loads(path.read_text())) == cfg


def test_broken_file_is_not_overwritten(tmp_path):
    path = tmp_path / "cfg.json"
    path.write_text("{ not json")
    assert load_config(path) == Config()
    assert path.read_text() == "{ not json"


def test_save_preferences_only_touches_runtime_keys(tmp_path):
    path = tmp_path / "cfg.json"
    path.write_text(json.dumps({"ball": {"radius": 9}, "game": {"fullscreen": False}}))
    cfg = load_config(path)
    cfg.game.fullscreen = True
    cfg.crt_effects.enabled = True
    cfg.game.difficulty = 3
    save_preferences(path, cfg)
    data = json.loads(path.read_text())
    assert data == {"ball": {"radius": 9}, "game": {"fullscreen": True, "difficulty": 3, "attract_sound": True},
                    "crt_effects": {"enabled": True}}


def test_params_scale_with_resolution():
    cfg = config_from_dict({"resolution": {"width": 1600, "height": 960}})
    p = Params.from_config(cfg)
    assert p.pad_height == 160 and p.pad_width == 20 and p.ball_radius == 10
