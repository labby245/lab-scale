"""Thread-safe job log store with TTL cleanup, plus persistent name map."""

from __future__ import annotations

import datetime
import json
import os
import threading
import time
from typing import Optional

from .logging_config import get

log = get(__name__)


class JobStore:
    """In-memory job log store. Bounded by TTL — old jobs are auto-purged."""

    def __init__(self, ttl_seconds: int = 3600, max_jobs: int = 200):
        self._jobs: dict[str, dict] = {}
        self._lock = threading.Lock()
        self._ttl = ttl_seconds
        self._max = max_jobs

    def start(self, job_id: str) -> None:
        if not job_id:
            return
        with self._lock:
            self._jobs[job_id] = {
                "logs": [],
                "done": False,
                "created": time.time(),
            }
            self._gc_locked()

    def log(self, job_id: str, msg: str) -> None:
        if not job_id:
            return
        ts = datetime.datetime.now().strftime("%H:%M:%S")
        line = f"[{ts}] {msg}"
        with self._lock:
            info = self._jobs.get(job_id)
            if info is not None:
                info["logs"].append(line)

    def done(self, job_id: str) -> None:
        if not job_id:
            return
        with self._lock:
            info = self._jobs.get(job_id)
            if info is not None:
                info["done"] = True
                info["finished"] = time.time()

    def get(self, job_id: str) -> Optional[dict]:
        with self._lock:
            info = self._jobs.get(job_id)
            if info is None:
                return None
            return {"logs": list(info["logs"]), "done": info["done"]}

    def has_active(self) -> bool:
        with self._lock:
            return any(not info.get("done") for info in self._jobs.values())

    def gc(self) -> None:
        with self._lock:
            self._gc_locked()

    def _gc_locked(self) -> None:
        now = time.time()
        stale = [
            jid for jid, info in self._jobs.items()
            if info.get("done")
            and (now - info.get("finished", info.get("created", now))) > self._ttl
        ]
        for jid in stale:
            self._jobs.pop(jid, None)
        if len(self._jobs) > self._max:
            ordered = sorted(self._jobs.items(), key=lambda x: x[1].get("created", 0))
            for jid, _ in ordered[: len(self._jobs) - self._max]:
                self._jobs.pop(jid, None)


class NameMap:
    """Persistent stored→original-base mapping. Survives restart."""

    def __init__(self, path: str):
        self._path = path
        self._lock = threading.Lock()
        self._map: dict[str, str] = self._load()

    def _load(self) -> dict[str, str]:
        if not os.path.isfile(self._path):
            return {}
        try:
            with open(self._path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
            return {str(k): str(v) for k, v in data.items()}
        except Exception as e:
            log.warning("name_map load failed (%s): %s", self._path, e)
            return {}

    def _save_locked(self) -> None:
        tmp = self._path + ".tmp"
        try:
            with open(tmp, "w", encoding="utf-8") as fh:
                json.dump(self._map, fh, ensure_ascii=False)
            os.replace(tmp, self._path)
        except Exception as e:
            log.warning("name_map save failed: %s", e)

    def set(self, stored: str, original_base: str) -> None:
        with self._lock:
            self._map[stored] = original_base
            self._save_locked()

    def get(self, stored: str, default: Optional[str] = None) -> Optional[str]:
        with self._lock:
            return self._map.get(stored, default)

    def remove(self, stored: str) -> None:
        with self._lock:
            if stored in self._map:
                self._map.pop(stored, None)
                self._save_locked()

    def prune_missing(self, existing_files: set) -> None:
        with self._lock:
            before = len(self._map)
            self._map = {k: v for k, v in self._map.items() if k in existing_files}
            if len(self._map) != before:
                self._save_locked()
