"""JobStore + NameMap tests."""

import os
import time

from utils.jobs import JobStore, NameMap


def test_job_store_basic_lifecycle():
    s = JobStore()
    s.start("j1")
    s.log("j1", "hello")
    s.log("j1", "world")
    info = s.get("j1")
    assert info["done"] is False
    assert len(info["logs"]) == 2
    assert "hello" in info["logs"][0]
    s.done("j1")
    assert s.get("j1")["done"] is True


def test_job_store_unknown_job_returns_none():
    s = JobStore()
    assert s.get("nope") is None


def test_job_store_empty_id_is_noop():
    s = JobStore()
    s.start("")
    s.log("", "x")
    s.done("")
    assert s.get("") is None


def test_job_store_has_active():
    s = JobStore()
    assert s.has_active() is False
    s.start("a")
    assert s.has_active() is True
    s.done("a")
    assert s.has_active() is False


def test_job_store_ttl_purge():
    s = JobStore(ttl_seconds=0)
    s.start("a")
    s.done("a")
    time.sleep(0.05)
    s.gc()
    assert s.get("a") is None


def test_job_store_max_jobs():
    s = JobStore(ttl_seconds=999, max_jobs=3)
    for i in range(5):
        s.start(f"j{i}")
        time.sleep(0.001)
    s.gc()
    assert s.get("j0") is None
    assert s.get("j4") is not None


def test_name_map_persistence(tmp_path):
    p = tmp_path / "nm.json"
    nm1 = NameMap(str(p))
    nm1.set("clip_abc.mp4", "clip")
    nm1.set("photo_xyz.png", "photo")
    assert nm1.get("clip_abc.mp4") == "clip"

    nm2 = NameMap(str(p))
    assert nm2.get("clip_abc.mp4") == "clip"
    assert nm2.get("photo_xyz.png") == "photo"


def test_name_map_remove(tmp_path):
    p = tmp_path / "nm.json"
    nm = NameMap(str(p))
    nm.set("a.mp4", "a")
    nm.remove("a.mp4")
    assert nm.get("a.mp4") is None


def test_name_map_prune_missing(tmp_path):
    p = tmp_path / "nm.json"
    nm = NameMap(str(p))
    nm.set("keep.mp4", "keep")
    nm.set("gone.mp4", "gone")
    nm.prune_missing({"keep.mp4"})
    assert nm.get("keep.mp4") == "keep"
    assert nm.get("gone.mp4") is None


def test_name_map_handles_corrupt_file(tmp_path):
    p = tmp_path / "nm.json"
    p.write_text("not json{", encoding="utf-8")
    nm = NameMap(str(p))
    assert nm.get("anything") is None
    nm.set("a.mp4", "a")
    assert nm.get("a.mp4") == "a"


def test_name_map_default_value(tmp_path):
    p = tmp_path / "nm.json"
    nm = NameMap(str(p))
    assert nm.get("unknown") is None
    assert nm.get("unknown", "fallback") == "fallback"


def test_name_map_persists_to_disk(tmp_path):
    p = tmp_path / "nm.json"
    nm = NameMap(str(p))
    nm.set("foo.mp4", "foo")
    assert os.path.isfile(p)
