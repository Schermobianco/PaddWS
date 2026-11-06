"""Punto di ingresso: python -m paddws [--config FILE] [--fullscreen | --windowed] [--crt | --no-crt]"""

from __future__ import annotations

import argparse
import gc
import logging
from pathlib import Path

from paddws import __version__, paths
from paddws.config import load_config
from paddws.hardware import enable_dpi_awareness


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="paddws", description="PADD WS")
    parser.add_argument("--config", type=Path, default=paths.DEFAULT_CONFIG, help="configuration file")
    parser.add_argument("--fullscreen", dest="fullscreen", action="store_true", default=None)
    parser.add_argument("--windowed", dest="fullscreen", action="store_false")
    parser.add_argument("--crt", dest="crt", action="store_true", default=None, help="enable the CRT filter")
    parser.add_argument("--no-crt", dest="crt", action="store_false")
    parser.add_argument("--debug", action="store_true", help="verbose logging")
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if args.debug else logging.INFO,
                        format="%(levelname)s %(name)s: %(message)s")

    logging.getLogger("paddws").info("PADD WS %s", __version__)
    paths.migrate_old_name(args.config, "pong_config.json")
    cfg = load_config(args.config)
    if args.fullscreen is not None:
        cfg.game.fullscreen = args.fullscreen
    if args.crt is not None:
        cfg.crt_effects.enabled = args.crt

    enable_dpi_awareness()
    import arcade  # apre il contesto GL in modo lazy: import dopo l'impostazione DPI

    from paddws.app import PaddApp

    PaddApp(cfg, args.config)
    # Tutto ciò che è stato caricato vive per l'intera esecuzione: escluso dalle scansioni del GC
    gc.collect()
    gc.freeze()
    arcade.run()


if __name__ == "__main__":
    main()
