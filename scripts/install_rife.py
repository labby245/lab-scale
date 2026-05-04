"""Auto-install rife-ncnn-vulkan binary for the current platform.

Usage:
    python scripts/install_rife.py

Downloads the official release from
https://github.com/nihui/rife-ncnn-vulkan/releases and extracts the binary +
model files to <project>/bin/.

After installation, restart the app — the Setup panel will show RIFE as available.
"""

from __future__ import annotations

import io
import os
import platform
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
BIN_DIR = PROJECT_ROOT / "bin"

VERSION = "20221029"
RELEASE_URLS = {
    "windows": f"https://github.com/nihui/rife-ncnn-vulkan/releases/download/{VERSION}/rife-ncnn-vulkan-{VERSION}-windows.zip",
    "macos":   f"https://github.com/nihui/rife-ncnn-vulkan/releases/download/{VERSION}/rife-ncnn-vulkan-{VERSION}-macos.zip",
    "linux":   f"https://github.com/nihui/rife-ncnn-vulkan/releases/download/{VERSION}/rife-ncnn-vulkan-{VERSION}-ubuntu.zip",
}

BINARY_NAMES = {
    "windows": "rife-ncnn-vulkan.exe",
    "macos":   "rife-ncnn-vulkan",
    "linux":   "rife-ncnn-vulkan",
}


def detect_platform() -> str:
    s = platform.system().lower()
    if s.startswith("win"):
        return "windows"
    if s == "darwin":
        return "macos"
    if s == "linux":
        return "linux"
    raise SystemExit(f"Unsupported platform: {platform.system()}")


def download(url: str) -> bytes:
    print(f"Downloading {url}")
    print("(this is ~50MB and may take a minute)")
    req = urllib.request.Request(url, headers={"User-Agent": "video-wr-up-inter"})
    with urllib.request.urlopen(req, timeout=120) as r:
        size = int(r.headers.get("Content-Length", 0))
        chunks: list = []
        downloaded = 0
        while True:
            chunk = r.read(64 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
            downloaded += len(chunk)
            if size:
                pct = downloaded / size * 100
                sys.stdout.write(f"\r  {downloaded // 1024} / {size // 1024} KiB ({pct:.1f}%)")
                sys.stdout.flush()
        sys.stdout.write("\n")
        return b"".join(chunks)


def extract_to_bin(zip_bytes: bytes, bin_dir: Path) -> None:
    """Extract zip, flattening the top-level release folder into bin/."""
    bin_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        names = zf.namelist()
        if not names:
            raise SystemExit("Zip is empty")
        top = names[0].split("/")[0] + "/"
        for name in names:
            if name.endswith("/"):
                continue
            rel = name[len(top):] if name.startswith(top) else name
            if not rel:
                continue
            target = bin_dir / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(name) as src, open(target, "wb") as dst:
                shutil.copyfileobj(src, dst)
            if os.name != "nt" and rel.startswith("rife-ncnn-vulkan"):
                os.chmod(target, 0o755)


def main() -> int:
    plat = detect_platform()
    binary_name = BINARY_NAMES[plat]
    target_binary = BIN_DIR / binary_name

    if target_binary.is_file():
        print(f"Already installed: {target_binary}")
        print("Delete the file if you want to re-download.")
        return 0

    print(f"Platform: {plat}")
    zip_bytes = download(RELEASE_URLS[plat])

    print(f"Extracting to {BIN_DIR}/")
    extract_to_bin(zip_bytes, BIN_DIR)

    if not target_binary.is_file():
        print("ERROR: extraction succeeded but binary not found at expected path.")
        print("Files extracted to:", BIN_DIR)
        return 1

    model_dirs = [d for d in BIN_DIR.iterdir() if d.is_dir() and d.name.startswith("rife")]
    if not model_dirs:
        print("WARN: no rife-v* model directory found in bin/. RIFE may not work.")

    print()
    print(f"OK RIFE installed at: {target_binary}")
    print(f"  Models found: {[d.name for d in model_dirs]}")
    print()
    print("Restart the app — Setup panel will now show RIFE as available.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
