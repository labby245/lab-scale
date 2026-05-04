"""Train YOLOv8 watermark detector from labels/ corpus.

Usage:
    python scripts/train_watermark_yolo.py
    python scripts/train_watermark_yolo.py --epochs 200 --imgsz 640 --model yolov8s.pt

Pipeline:
    1. Read labels/annotations.jsonl
    2. Convert to YOLO format: labels/yolo/{train,val}/{images,labels}/
    3. Generate labels/yolo/data.yaml
    4. Run ultralytics training (uses GPU automatically when available)
    5. Copy best.pt → models/watermark_yolo.pt

Requirements:
    pip install ultralytics
"""

from __future__ import annotations

import argparse
import random
import shutil
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from utils.labels_store import LabelsStore  # noqa: E402
from utils.logging_config import configure, get  # noqa: E402

configure(str(PROJECT_ROOT))
log = get(__name__)


def to_yolo_label(roi: dict, img_w: int, img_h: int) -> str:
    """Return YOLO-format line: `0 cx cy w h` (normalized)."""
    cx = (roi["x"] + roi["w"] / 2.0) / img_w
    cy = (roi["y"] + roi["h"] / 2.0) / img_h
    w = roi["w"] / img_w
    h = roi["h"] / img_h
    return f"0 {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}"


def export_yolo_dataset(
    store: LabelsStore,
    out_dir: Path,
    val_split: float = 0.2,
    seed: int = 42,
) -> Path:
    """Export annotations to YOLO format. Returns path to data.yaml."""
    if out_dir.exists():
        shutil.rmtree(out_dir)
    for split in ("train", "val"):
        (out_dir / split / "images").mkdir(parents=True, exist_ok=True)
        (out_dir / split / "labels").mkdir(parents=True, exist_ok=True)

    by_hash: dict[str, list] = {}
    for record in store.iter_samples():
        by_hash.setdefault(record["hash"], []).append(record)

    if not by_hash:
        raise RuntimeError(
            f"No labeled samples found. Check {store.annotations_path}"
        )

    hashes = sorted(by_hash.keys())
    rng = random.Random(seed)
    rng.shuffle(hashes)
    n_val = max(1, int(len(hashes) * val_split))
    val_set = set(hashes[:n_val])

    n_train, n_val_actual = 0, 0
    for digest, records in by_hash.items():
        src_img = Path(store.image_path(digest))
        if not src_img.is_file():
            log.warning("missing image %s — skipping", src_img)
            continue
        split = "val" if digest in val_set else "train"
        dst_img = out_dir / split / "images" / f"{digest}.jpg"
        shutil.copy2(src_img, dst_img)

        first = records[-1]
        lines = [
            to_yolo_label(r["roi"], first["img_w"], first["img_h"])
            for r in records
        ]
        (out_dir / split / "labels" / f"{digest}.txt").write_text(
            "\n".join(lines) + "\n", encoding="utf-8"
        )
        if split == "train":
            n_train += 1
        else:
            n_val_actual += 1

    log.info("Exported %d train + %d val images", n_train, n_val_actual)

    data_yaml = out_dir / "data.yaml"
    data_yaml.write_text(
        f"path: {out_dir.resolve().as_posix()}\n"
        "train: train/images\n"
        "val: val/images\n"
        "names:\n  0: watermark\n",
        encoding="utf-8",
    )
    return data_yaml


def train(
    data_yaml: Path,
    out_models_dir: Path,
    base_model: str = "yolov8n.pt",
    epochs: int = 100,
    imgsz: int = 640,
) -> Path:
    """Run ultralytics training and copy best weights to models/watermark_yolo.pt."""
    try:
        from ultralytics import YOLO  # type: ignore
    except ImportError as e:
        raise RuntimeError(
            "ultralytics tidak terinstal. Jalankan: pip install ultralytics"
        ) from e

    model = YOLO(base_model)
    log.info("Training YOLOv8 (%s, epochs=%d, imgsz=%d)…", base_model, epochs, imgsz)
    results = model.train(
        data=str(data_yaml),
        epochs=epochs,
        imgsz=imgsz,
        project=str(out_models_dir.parent / "yolo_runs"),
        name="watermark",
        exist_ok=True,
        verbose=True,
    )
    save_dir = Path(
        getattr(results, "save_dir", out_models_dir.parent / "yolo_runs" / "watermark")
    )
    best = save_dir / "weights" / "best.pt"
    if not best.is_file():
        raise RuntimeError(f"Training finished but best.pt not found at {best}")

    out_models_dir.mkdir(parents=True, exist_ok=True)
    final = out_models_dir / "watermark_yolo.pt"
    shutil.copy2(best, final)
    log.info("Saved trained weights → %s", final)
    return final


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--model", default="yolov8n.pt", help="Base YOLO model")
    parser.add_argument("--val-split", type=float, default=0.2)
    parser.add_argument(
        "--min-samples", type=int, default=20,
        help="Refuse to train with fewer unique images than this",
    )
    args = parser.parse_args()

    store = LabelsStore()
    stats = store.stats()
    log.info("LabelsStore stats: %s", stats)
    if stats["unique_images"] < args.min_samples:
        log.error(
            "Only %d unique labeled images — need at least %d. Use the app to "
            "collect more samples (Auto-Detect + manual ROI confirmation).",
            stats["unique_images"], args.min_samples,
        )
        return 1

    yolo_dir = PROJECT_ROOT / "labels" / "yolo"
    data_yaml = export_yolo_dataset(store, yolo_dir, val_split=args.val_split)

    final_weights = train(
        data_yaml,
        PROJECT_ROOT / "models",
        base_model=args.model,
        epochs=args.epochs,
        imgsz=args.imgsz,
    )
    print(f"Done. New model at: {final_weights}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
