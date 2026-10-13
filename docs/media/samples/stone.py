# Macro "photo" of weathered granite with lichen, 1600x1000, made from
# scratch: a fractal height map lit from the upper left (hillshade), mineral
# speckle, lichen patches. Fine crystals and cracks are what a 4x downscale
# wipes out.
import numpy as np
from PIL import Image
W, H = 1600, 1000
rng = np.random.default_rng(11)

def octave(scale, seed):
    r = np.random.default_rng(seed)
    gh, gw = H // scale + 2, W // scale + 2
    g = Image.fromarray(r.random((gh, gw)).astype(np.float32), mode='F')
    return np.asarray(g.resize((gw * scale, gh * scale), Image.BICUBIC))[:H, :W]

def fbm(scales, seed, gain=0.55):
    out = np.zeros((H, W), np.float32); amp = 1.0; tot = 0
    for i, s in enumerate(scales):
        out += amp * octave(s, seed + i); tot += amp; amp *= gain
    return out / tot

height = fbm([256, 128, 64, 32, 16, 8, 4, 2], 3)
# Cracks: thin dark valleys along a warped noise contour.
crack_n = fbm([180, 90, 45, 20], 40)
# Width and depth vary along the crack, and only part of the contour opens
# up, so it reads as a fracture rather than a drawn line.
width = 0.002 + 0.006 * fbm([120, 40], 50)
depth = np.clip((fbm([200, 100], 60) - 0.45) / 0.15, 0, 1)
cracks = np.exp(-((crack_n - 0.5) / width) ** 2) * depth
cracks = cracks * 0  # fractures read as drawn lines at this scale; left out
height = height - 0.05 * cracks
# Hillshade.
gy, gx = np.gradient(height * 260)
nx, ny, nz = -gx, -gy, np.ones_like(gx)
n = np.sqrt(nx**2 + ny**2 + nz**2)
lx, ly, lz = -0.6, -0.5, 0.62
shade = np.clip((nx * lx + ny * ly + nz * lz) / n, 0, 1)
# Granite: grey base, black mica and white feldspar crystals.
speck = rng.random((H, W))
mica = Image.fromarray(((speck > 0.93) * 255).astype(np.uint8)).resize((W // 2, H // 2)).resize((W, H), Image.NEAREST)
felds = Image.fromarray(((speck < 0.05) * 255).astype(np.uint8)).resize((W // 3, H // 3)).resize((W, H), Image.NEAREST)
mica = np.asarray(mica, np.float32) / 255; felds = np.asarray(felds, np.float32) / 255
base = np.array([138, 132, 124], np.float32)
col = base[None, None] * (0.75 + 0.5 * fbm([64, 16, 4], 70))[..., None]
col = col * (1 - 0.55 * mica[..., None]) + 60 * felds[..., None]
# Lichen: soft yellow-green patches with ragged edges.
lich = fbm([160, 80, 40, 10, 3], 90)
lmask = np.clip((lich - 0.6) / 0.08, 0, 1) * (0.55 + 0.45 * fbm([6, 2], 97))
lcol = np.array([150, 150, 104], np.float32) * (0.75 + 0.5 * fbm([8, 3], 95))[..., None]
col = col * (1 - lmask[..., None]) + lcol * lmask[..., None]
col = col * (0.35 + 0.85 * shade)[..., None] * (1 - 0.45 * cracks)[..., None]
# Lens falloff and mild sensor noise.
yy, xx = np.mgrid[0:H, 0:W]
vign = 1 - 0.25 * (((xx - W / 2) / W) ** 2 + ((yy - H / 2) / H) ** 2) * 2
col = col * vign[..., None] + rng.normal(0, 2.0, col.shape)
Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).save('photo_truth.png')
