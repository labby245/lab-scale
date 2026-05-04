"""Bootstrap a YOLOv8 watermark detector with synthetic data.

Usage:
    python scripts/install_yolo.py
    python scripts/install_yolo.py --samples 300 --epochs 30 --imgsz 640

Pipeline:
    1. Generate ~200 synthetic images with watermark-like overlays in random corners
    2. Auto-label each with YOLO bounding box
    3. Train YOLOv8n for ~30 epochs (~3-5 min on a 12GB GPU)
    4. Save best weights to models/watermark_yolo.pt

The resulting model is a "starter" — it knows roughly where AI-style watermarks
sit (corners, small, text/logo-shaped). The self-improving loop in the app
will refine it as users confirm real ROIs.

Requirements:  pip install ultralytics
"""

from __future__ import annotations

import argparse
import random
import shutil
import sys
from pathlib import Path

import cv2
import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from utils.logging_config import configure, get  # noqa: E402

configure(str(PROJECT_ROOT))
log = get(__name__)

WATERMARK_TEXTS = [
    "Veo", "Sora", "Gemini", "Pika", "Runway", "Luma", "Kling",
    "@user", "AI Video", "GenAI", "DALL-E", "Midjourney",
    "Veo *", "* Gemini", "Created with AI",
]

CORNERS = ["tl", "tr", "bl", "br"]


def _random_background(rng: random.Random, w: int, h: int) -> np.ndarray:
    """Generate varied background: gradient + color blocks + noise."""
    img = np.zeros((h, w, 3), dtype=np.uint8)

    c1 = np.array([rng.randint(20, 235) for _ in range(3)], dtype=np.float32)
    c2 = np.array([rng.randint(20, 235) for _ in range(3)], dtype=np.float32)
    direction = rng.choice(["v", "h", "d"])

    ys = np.arange(h, dtype=np.float32).reshape(-1, 1)
    xs = np.arange(w, dtype=np.float32).reshape(1, -1)
    if direction == "v":
        t = ys / max(h, 1)
        t = np.broadcast_to(t, (h, w))
    elif direction == "h":
        t = xs / max(w, 1)
        t = np.broadcast_to(t, (h, w))
    else:
        t = (xs + ys) / max(w + h, 1)
    t = t[..., None]
    grad = (c1 * (1 - t) + c2 * t)
    img = grad.astype(np.uint8)

    for _ in range(rng.randint(2, 6)):
        bx = rng.randint(0, w - 80)
        by = rng.randint(0, h - 80)
        bw = rng.randint(40, 200)
        bh = rng.randint(40, 200)
        color = tuple(rng.randint(20, 235) for _ in range(3))
        cv2.rectangle(img, (bx, by), (bx + bw, by + bh), color, -1)

    noise = (np.random.default_rng(rng.randint(0, 1 << 31))
             .normal(0, 12, (h, w, 3))).astype(np.float32)
    img = np.clip(img.astype(np.float32) + noise, 0, 255).astype(np.uint8)

    if rng.random() < 0.3:
        k = rng.choice([3, 5, 7])
        img = cv2.GaussianBlur(img, (k, k), 0)

    return img


def _draw_watermark(
    img: np.ndarray,
    rng: random.Random,
) -> tuple[int, int, int, int]:
    """Composite a fake watermark in a random corner; return (x,y,w,h) bbox."""
    h, w = img.shape[:2]
    text = rng.choice(WATERMARK_TEXTS)
    corner = rng.choice(CORNERS)

    font = rng.choice([
        cv2.FONT_HERSHEY_SIMPLEX,
        cv2.FONT_HERSHEY_DUPLEX,
        cv2.FONT_HERSHEY_TRIPLEX,
        cv2.FONT_HERSHEY_COMPLEX,
    ])
    font_scale = rng.uniform(0.6, 1.4)
    thickness = rng.randint(1, 3)
    (tw, th), _ = cv2.getTextSize(text, font, font_scale, thickness)
    pad = 10

    if corner == "tl":
        x, y = pad, pad + th
    elif corner == "tr":
        x, y = w - tw - pad, pad + th
    elif corner == "bl":
        x, y = pad, h - pad
    else:
        x, y = w - tw - pad, h - pad

    color_kind = rng.choice(["white", "light", "vivid"])
    if color_kind == "white":
        color = (255, 255, 255)
    elif color_kind == "light":
        v = rng.randint(180, 240)
        color = (v, v, v)
    else:
        color = (rng.randint(200, 255), rng.randint(80, 200), rng.randint(150, 255))

    if rng.random() < 0.5:
        cv2.putText(img, text, (x + 2, y + 2), font, font_scale,
                    (0, 0, 0), thickness + 1, cv2.LINE_AA)
    cv2.putText(img, text, (x, y), font, font_scale, color, thickness, cv2.LINE_AA)

    bx = max(0, x - 4)
    by = max(0, y - th - 4)
    bw = min(w - bx, tw + 8)
    bh = min(h - by, th + 8)
    return (bx, by, bw, bh)


def _yolo_label_line(bbox: tuple, img_w: int, img_h: int) -> str:
    x, y, w, h = bbox
    cx = (x + w / 2.0) / img_w
    cy = (y + h / 2.0) / img_h
    return f"0 {cx:.6f} {cy:.6f} {w / img_w:.6f} {h / img_h:.6f}"


def generate_dataset(out_dir: Path, n_samples: int, seed: int = 42) -> Path:
    if out_dir.exists():
        shutil.rmtree(out_dir)
    for split in ("train", "val"):
        (out_dir / split / "images").mkdir(parents=True, exist_ok=True)
        (out_dir / split / "labels").mkdir(parents=True, exist_ok=True)

    rng = random.Random(seed)
    n_val = max(1, n_samples // 5)
    log.info("Generating %d synthetic samples (%d train + %d val)…",
             n_samples, n_samples - n_val, n_val)

    for i in range(n_samples):
        w, h = rng.choice([(640, 480), (800, 600), (1024, 576), (640, 360)])
        img = _random_background(rng, w, h)
        bbox = _draw_watermark(img, rng)

        split = "val" if i < n_val else "train"
        stem = f"syn_{i:05d}"
        cv2.imwrite(str(out_dir / split / "images" / f"{stem}.jpg"), img,
                    [cv2.IMWRITE_JPEG_QUALITY, 88])
        (out_dir / split / "labels" / f"{stem}.txt").write_text(
            _yolo_label_line(bbox, w, h) + "\n", encoding="utf-8",
        )
        if (i + 1) % 50 == 0:
            log.info("  generated %d/%d", i + 1, n_samples)

    data_yaml = out_dir / "data.yaml"
    data_yaml.write_text(
        f"path: {out_dir.resolve().as_posix()}\n"
        "train: train/images\n"
        "val: val/images\n"
        "names:\n  0: watermark\n",
        encoding="utf-8",
    )
    return data_yaml


def train(data_yaml: Path, out_path: Path, base: str = "yolov8n.pt",
          epochs: int = 30, imgsz: int = 640) -> Path:
    try:
        from ultralytics import YOLO  # type: ignore
    except ImportError as e:
        raise SystemExit("ultralytics not installed. Run: pip install ultralytics") from e

    log.info("Training YOLOv8 (%s, epochs=%d, imgsz=%d)…", base, epochs, imgsz)
    model = YOLO(base)
    results = model.train(
        data=str(data_yaml),
        epochs=epochs,
        imgsz=imgsz,
        project=str(PROJECT_ROOT / "yolo_runs"),
        name="synthetic-bootstrap",
        exist_ok=True,
        verbose=True,
    )
    save_dir = Path(getattr(results, "save_dir",
                            PROJECT_ROOT / "yolo_runs" / "synthetic-bootstrap"))
    best = save_dir / "weights" / "best.pt"
    if not best.is_file():
        raise SystemExit(f"Training finished but best.pt not found at {best}")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(best, out_path)
    return out_path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", type=int, default=200)
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--model", default="yolov8n.pt")
    parser.add_argument("--force", action="store_true",
                        help="Overwrite existing models/watermark_yolo.pt")
    args = parser.parse_args()

    out_path = PROJECT_ROOT / "models" / "watermark_yolo.pt"
    if out_path.is_file() and not args.force:
        print(f"Already exists: {out_path}")
        print("Use --force to re-train, or run scripts/train_watermark_yolo.py")
        return 0

    syn_dir = PROJECT_ROOT / "labels" / "synthetic"
    data_yaml = generate_dataset(syn_dir, args.samples)

    final = train(data_yaml, out_path, base=args.model,
                  epochs=args.epochs, imgsz=args.imgsz)
    print()
    print(f"OK YOLO bootstrap weights at: {final}")
    print()
    print("This is a STARTER trained on synthetic data. Refine with real labels:")
    print("    python scripts/train_watermark_yolo.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
