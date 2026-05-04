"""LabelsStore tests — verify dedup, append, stats, and graceful rejection."""

import json
import os

import numpy as np

from utils.labels_store import LabelsStore


def _img(seed: int = 0, h: int = 100, w: int = 200) -> np.ndarray:
    rng = np.random.default_rng(seed)
    return rng.integers(0, 255, (h, w, 3), dtype=np.uint8)


def test_add_sample_creates_image_and_annotation(tmp_path):
    store = LabelsStore(root=str(tmp_path))
    digest = store.add_sample(_img(1), {"x": 10, "y": 5, "width": 30, "height": 20})
    assert digest is not None
    assert os.path.isfile(store.image_path(digest))
    assert os.path.isfile(store.annotations_path)


def test_dedup_same_image_writes_one_jpeg(tmp_path):
    store = LabelsStore(root=str(tmp_path))
    img = _img(2)
    d1 = store.add_sample(img, {"x": 10, "y": 5, "width": 30, "height": 20})
    d2 = store.add_sample(img, {"x": 50, "y": 25, "width": 40, "height": 30})
    assert d1 == d2  # same hash for identical bytes
    files = [f for f in os.listdir(store.raw_dir) if f.endswith(".jpg")]
    assert len(files) == 1
    lines = open(store.annotations_path).read().strip().splitlines()
    assert len(lines) == 2


def test_invalid_roi_rejected(tmp_path):
    store = LabelsStore(root=str(tmp_path))
    img = _img(3)
    assert store.add_sample(img, {"x": 0, "y": 0, "width": 0, "height": 10}) is None
    assert store.add_sample(img, {"x": 0, "y": 0, "width": 10, "height": 0}) is None
    assert store.add_sample(img, {"x": 999, "y": 999, "width": 10, "height": 10}) is None


def test_stats_counts_and_unique_images(tmp_path):
    store = LabelsStore(root=str(tmp_path))
    img_a = _img(10)
    img_b = _img(11)
    store.add_sample(img_a, {"x": 1, "y": 1, "width": 10, "height": 10})
    store.add_sample(img_a, {"x": 2, "y": 2, "width": 12, "height": 12})
    store.add_sample(img_b, {"x": 3, "y": 3, "width": 20, "height": 20}, source="auto")

    stats = store.stats()
    assert stats["total"] == 3
    assert stats["unique_images"] == 2
    assert stats["sources"].get("manual", 0) == 2
    assert stats["sources"].get("auto", 0) == 1


def test_iter_samples_yields_records(tmp_path):
    store = LabelsStore(root=str(tmp_path))
    store.add_sample(_img(20), {"x": 1, "y": 1, "width": 10, "height": 10})
    records = list(store.iter_samples())
    assert len(records) == 1
    r = records[0]
    assert r["roi"] == {"x": 1, "y": 1, "w": 10, "h": 10}
    assert r["source"] == "manual"
    assert "ts" in r
    assert r["img_w"] > 0 and r["img_h"] > 0


def test_stats_handles_corrupt_lines(tmp_path):
    store = LabelsStore(root=str(tmp_path))
    store.add_sample(_img(30), {"x": 1, "y": 1, "width": 10, "height": 10})
    with open(store.annotations_path, "a", encoding="utf-8") as fh:
        fh.write("not json{\n")
        fh.write("\n")
    stats = store.stats()
    assert stats["total"] == 1


def test_stats_handles_missing_file(tmp_path):
    store = LabelsStore(root=str(tmp_path))
    stats = store.stats()
    assert stats["total"] == 0
    assert stats["unique_images"] == 0


def test_annotation_record_shape(tmp_path):
    store = LabelsStore(root=str(tmp_path))
    store.add_sample(
        _img(40, h=480, w=640),
        {"x": 100, "y": 200, "width": 50, "height": 40},
        source="correction",
    )
    line = open(store.annotations_path).read().strip()
    record = json.loads(line)
    assert set(record.keys()) >= {"hash", "roi", "img_w", "img_h", "ts", "source"}
    assert record["img_w"] == 640
    assert record["img_h"] == 480
    assert record["source"] == "correction"
