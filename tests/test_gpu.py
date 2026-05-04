"""GPU helper tests — focused on auto_tile_size which is pure logic."""

import pytest

from utils import gpu


@pytest.mark.parametrize(
    "vram_gb, expected",
    [
        (0.0,  256),  # CPU
        (3.0,  192),  # ≤4GB
        (5.0,  256),  # 4–6GB
        (7.0,  384),  # 6–8GB
        (10.0, 512),  # 8–12GB
        (16.0, 768),  # 12GB+
    ],
)
def test_auto_tile_size_buckets(monkeypatch, vram_gb, expected):
    monkeypatch.setattr(gpu, "_GPU_VRAM_GB", vram_gb)
    monkeypatch.setattr(gpu, "_GPU_ID", 0 if vram_gb > 0 else -1)
    assert gpu.auto_tile_size() == expected


def test_has_encoder_uses_cache(monkeypatch):
    monkeypatch.setattr(gpu, "_AVAILABLE_ENCODERS", {"libx264", "h264_nvenc"})
    assert gpu.has_encoder("libx264") is True
    assert gpu.has_encoder("nonexistent_codec") is False
