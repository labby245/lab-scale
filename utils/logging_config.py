"""Centralised logging setup for the app.

Writes to logs/app.log with rotation, plus console at INFO+. Idempotent."""

import logging
import logging.handlers
import os

_CONFIGURED = False


def configure(app_root: str, level: int = logging.INFO) -> None:
    """Configure root + app logger. Safe to call multiple times."""
    global _CONFIGURED
    if _CONFIGURED:
        return

    log_dir = os.path.join(app_root, "logs")
    os.makedirs(log_dir, exist_ok=True)

    fmt = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    file_h = logging.handlers.RotatingFileHandler(
        os.path.join(log_dir, "app.log"),
        maxBytes=5 * 1024 * 1024,
        backupCount=3,
        encoding="utf-8",
    )
    file_h.setFormatter(fmt)
    file_h.setLevel(level)

    console_h = logging.StreamHandler()
    console_h.setFormatter(fmt)
    console_h.setLevel(level)

    root = logging.getLogger()
    root.setLevel(level)
    root.handlers.clear()
    root.addHandler(file_h)
    root.addHandler(console_h)

    logging.getLogger("werkzeug").setLevel(logging.WARNING)
    _CONFIGURED = True


def get(name: str) -> logging.Logger:
    return logging.getLogger(name)
