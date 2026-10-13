# Flat-design poster, 1600x1000, drawn from scratch (clean rights). Rendered
# at 2x and downsampled so edges are smooth, as a real design export would be.
import numpy as np
from PIL import Image, ImageDraw, ImageFont
S = 2; W, H = 1600*S, 1000*S
top, bot = np.array([27, 31, 74]), np.array([91, 75, 214])
t = np.linspace(0, 1, H)[:, None, None]
img = Image.fromarray((top*(1-t) + bot*t).repeat(W, 1).astype(np.uint8))
d = ImageDraw.Draw(img)
F = '/System/Library/Fonts/Supplemental/'
bold = ImageFont.truetype(F + 'Arial Bold.ttf', 120*S)
reg = ImageFont.truetype(F + 'Arial.ttf', 38*S)
small = ImageFont.truetype(F + 'Arial.ttf', 22*S)
def p(*pts): return [(x*S, y*S) for x, y in pts]
# Sun with a halftone dot pattern.
cx, cy, r = 1150, 330, 190
d.ellipse(p((cx-r, cy-r), (cx+r, cy+r)), fill=(255, 209, 102))
for yy in range(cy-r, cy+r, 14):
    for xx in range(cx-r, cx+r, 14):
        if (xx-cx)**2 + (yy-cy)**2 < (r-6)**2:
            d.ellipse(p((xx+1.4, yy+1.4), (xx+4.6, yy+4.6)), fill=(233, 160, 60))
for i, w in enumerate([420, 300, 360]):
    d.line(p((60, 140+20*i), (60+w, 140+20*i)), fill=(150, 150, 210), width=2*S)
d.polygon(p((0,760),(260,520),(430,650),(640,420),(900,700),(1100,560),(1600,820),(1600,1000),(0,1000)), fill=(46,196,182))
d.polygon(p((0,860),(300,680),(520,800),(760,640),(1040,860),(1300,720),(1600,900),(1600,1000),(0,1000)), fill=(11,110,117))
for x0 in (120, 900):
    for k in range(4 if x0 == 120 else 3):
        d.arc(p((x0+80*k, 920), (x0+80*k+80, 980)), 200, 340, fill=(11, 61, 74), width=3*S)
d.text((60*S, 180*S), 'LABSTORY', font=bold, fill='white')
d.text((64*S, 318*S), 'SPACE OF MEMORIES · SEMARANG', font=reg, fill=(255, 209, 102))
# Text under ~10 px at the 4x-reduced source size is gone before any
# upscaler sees it, so the sample keeps to type a real low-res source could
# still carry.
img.resize((1600, 1000), Image.LANCZOS).save('design_truth.png')
