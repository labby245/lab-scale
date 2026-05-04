"""Watermark auto-detection: spatial (single image) and temporal (video frames)."""

from __future__ import annotations

from typing import Optional, Tuple

import cv2
import numpy as np


def _tight_roi_from_mask(
    mask: np.ndarray,
    offset_x: int, offset_y: int,
    img_w: int, img_h: int,
    pad: int,
) -> Optional[Tuple[int, int, int, int]]:
    ys, xs = np.where(mask > 0)
    if len(xs) == 0:
        return None
    x1 = max(0, int(xs.min()) + offset_x - pad)
    y1 = max(0, int(ys.min()) + offset_y - pad)
    x2 = min(img_w, int(xs.max()) + offset_x + pad + 1)
    y2 = min(img_h, int(ys.max()) + offset_y + pad + 1)
    return (x1, y1, x2 - x1, y2 - y1) if x2 > x1 and y2 > y1 else None


def _corner_signals(
    gray_crop: np.ndarray,
    sat_crop: np.ndarray,
    kw: int,
    kh: int,
) -> np.ndarray:
    """Merge tophat/blackhat + Canny + saturation into one binary mask."""
    k_h = cv2.getStructuringElement(cv2.MORPH_RECT, (kw, kh))
    k_v = cv2.getStructuringElement(cv2.MORPH_RECT, (kh, kw))
    morph = cv2.max(
        cv2.max(
            cv2.morphologyEx(gray_crop, cv2.MORPH_TOPHAT, k_h),
            cv2.morphologyEx(gray_crop, cv2.MORPH_TOPHAT, k_v),
        ),
        cv2.max(
            cv2.morphologyEx(gray_crop, cv2.MORPH_BLACKHAT, k_h),
            cv2.morphologyEx(gray_crop, cv2.MORPH_BLACKHAT, k_v),
        ),
    )
    _, morph_bin = cv2.threshold(morph, 15, 255, cv2.THRESH_BINARY)
    canny_bin = cv2.Canny(cv2.GaussianBlur(gray_crop, (3, 3), 0), 20, 80)
    sat_thr = max(float(np.mean(sat_crop)) + 40.0, 60.0)
    sat_bin = (sat_crop > sat_thr).astype(np.uint8) * 255
    return cv2.max(cv2.max(morph_bin, canny_bin), sat_bin)


def detect_watermark_spatial(image: np.ndarray) -> Optional[Tuple[int, int, int, int]]:
    """Single-image watermark detection — tight corner-edge analysis."""
    h, w = image.shape[:2]
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    sat = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)[:, :, 1]

    tw = max(30, int(w * 0.10))
    tzh = max(20, int(h * 0.08))
    corners = [
        (0,      0,       tw, tzh),
        (w - tw, 0,       tw, tzh),
        (0,      h - tzh, tw, tzh),
        (w - tw, h - tzh, tw, tzh),
    ]
    tkw = max(2, tw // 15)
    tkh = max(2, tzh // 8)

    best_score = -1.0
    best_roi: Optional[Tuple[int, int, int, int]] = None
    edge_limit = max(8, int(min(w, h) * 0.03))

    for cx, cy, crw, crh in corners:
        combined = _corner_signals(
            gray[cy:cy + crh, cx:cx + crw],
            sat[cy:cy + crh, cx:cx + crw],
            tkw, tkh,
        )
        if int(np.count_nonzero(combined)) < 8:
            continue

        ck = cv2.getStructuringElement(
            cv2.MORPH_RECT, (max(3, tkw * 2), max(3, tkh * 2))
        )
        closed = cv2.morphologyEx(combined, cv2.MORPH_CLOSE, ck)
        pad = max(4, min(crw, crh) // 14)
        roi = _tight_roi_from_mask(closed, cx, cy, w, h, pad)
        if roi is None:
            continue

        rx, ry, rw, rh = roi
        if rw * rh > crw * crh * 0.50:
            continue

        near_h = (ry <= edge_limit) or ((h - (ry + rh)) <= edge_limit)
        near_v = (rx <= edge_limit) or ((w - (rx + rw)) <= edge_limit)
        if not (near_h and near_v):
            continue

        roi_fill = (
            np.count_nonzero(combined[ry - cy:ry - cy + rh, rx - cx:rx - cx + rw])
            / max(rw * rh, 1)
        )
        dist_h = min(ry, h - (ry + rh))
        dist_v = min(rx, w - (rx + rw))
        prox = 1.0 - (dist_h / max(h, 1) + dist_v / max(w, 1))
        score = roi_fill * 0.50 + prox * 0.50

        if score > best_score:
            best_score = score
            best_roi = roi

    return best_roi if best_score >= 0.05 else None


def detect_watermark_temporal(
    frames: list,
) -> Optional[Tuple[int, int, int, int]]:
    """Video watermark detection — temporal variance + corner contour."""
    if len(frames) < 2:
        return detect_watermark_spatial(frames[0]) if frames else None

    h, w = frames[0].shape[:2]
    aligned = [
        f if f.shape[:2] == (h, w) else cv2.resize(f, (w, h))
        for f in frames
    ]
    grays_f32 = [cv2.cvtColor(f, cv2.COLOR_BGR2GRAY).astype(np.float32) for f in aligned]
    var_map = np.var(np.stack(grays_f32, axis=0), axis=0)
    median_bgr = np.median(
        np.stack([f.astype(np.float32) for f in aligned], axis=0), axis=0
    ).astype(np.uint8)

    tw = max(30, int(w * 0.10))
    tzh = max(20, int(h * 0.08))
    corners = [
        (0,      0,       tw, tzh, 0,   0  ),
        (w - tw, 0,       tw, tzh, tw,  0  ),
        (0,      h - tzh, tw, tzh, 0,   tzh),
        (w - tw, h - tzh, tw, tzh, tw,  tzh),
    ]
    tkw = max(2, tw // 15)
    tkh = max(2, tzh // 8)
    edge_limit = max(8, int(min(w, h) * 0.03))

    best_score = -1.0
    best_roi: Optional[Tuple[int, int, int, int]] = None

    for cx, cy, crw, crh, corner_rx, corner_ry in corners:
        med_crop = median_bgr[cy:cy + crh, cx:cx + crw]
        gray_z = cv2.cvtColor(med_crop, cv2.COLOR_BGR2GRAY)
        sat_z = cv2.cvtColor(med_crop, cv2.COLOR_BGR2HSV)[:, :, 1]
        spatial = _corner_signals(gray_z, sat_z, tkw, tkh)

        if np.count_nonzero(spatial) < 8:
            continue

        zone_var = var_map[cy:cy + crh, cx:cx + crw]
        var_thresh = max(float(np.percentile(zone_var, 5)), 0.3)
        static_m = (zone_var <= var_thresh).astype(np.uint8) * 255
        filtered = cv2.bitwise_and(spatial, static_m)
        if np.count_nonzero(filtered) < 8:
            continue

        dil_k = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
        dilated = cv2.dilate(filtered, dil_k, iterations=1)
        contours, _ = cv2.findContours(
            dilated, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )
        pad = max(4, min(crw, crh) // 14)

        for cnt in contours:
            bx, by, bw2, bh2 = cv2.boundingRect(cnt)
            area = bw2 * bh2
            if area < 16 or area >= crw * crh * 0.25:
                continue
            density_pre = (
                np.count_nonzero(filtered[by:by + bh2, bx:bx + bw2])
                / max(area, 1)
            )
            if density_pre < 0.25:
                continue

            rx = max(0, cx + bx - pad)
            ry = max(0, cy + by - pad)
            rw = min(w - rx, bw2 + 2 * pad)
            rh = min(h - ry, bh2 + 2 * pad)

            near_h = (ry <= edge_limit) or ((h - (ry + rh)) <= edge_limit)
            near_v = (rx <= edge_limit) or ((w - (rx + rw)) <= edge_limit)
            if not (near_h and near_v):
                continue

            edge_dist_x = (
                bx / max(crw, 1)
                if corner_rx == 0
                else (crw - (bx + bw2)) / max(crw, 1)
            )
            edge_dist_y = (
                by / max(crh, 1)
                if corner_ry == 0
                else (crh - (by + bh2)) / max(crh, 1)
            )
            corner_prox = max(0.0, 1.0 - (edge_dist_x + edge_dist_y))
            density = (
                np.count_nonzero(filtered[by:by + bh2, bx:bx + bw2])
                / max(area, 1)
            )
            score = corner_prox * 0.60 + density * 0.40
            if score > best_score:
                best_score = score
                best_roi = (rx, ry, rw, rh)

    if best_score >= 0.10:
        return best_roi
    result = detect_watermark_spatial(median_bgr)
    if result is not None:
        return result
    return detect_watermark_spatial(aligned[len(aligned) // 2])


def detect_watermark_roi(
    image: np.ndarray,
    extra_frames: Optional[list] = None,
) -> Optional[Tuple[int, int, int, int]]:
    """Auto-detect watermark ROI. Returns (x, y, w, h) or None.

    Strategy: try YOLOv8 model first (if installed and weights present), then
    fall back to the heuristic spatial/temporal detector."""
    from . import yolo_detect

    if yolo_detect.is_available():
        yolo_box = yolo_detect.detect_with_yolo(image)
        if yolo_box is not None:
            return yolo_box

    if extra_frames and len(extra_frames) >= 2:
        return detect_watermark_temporal([image] + extra_frames)
    return detect_watermark_spatial(image)


def get_sample_frames(video_path: str, n: int = 6) -> list:
    """Extract n evenly-spaced frames from a video for watermark detection."""
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return []
    try:
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 0
        if total == 0:
            return []
        positions = [
            int(total * (0.10 + 0.80 * i / max(n - 1, 1))) for i in range(n)
        ]
        frames = []
        for pos in positions:
            cap.set(cv2.CAP_PROP_POS_FRAMES, max(0, pos))
            ret, frame = cap.read()
            if ret:
                frames.append(frame)
        return frames
    finally:
        cap.release()
