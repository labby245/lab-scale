# Before/after samples

Marketing samples for the LabScale product page, made 2026-10-13. Both
sources were made from scratch for this, so the rights are clean, and neither
contains a person or anything identifying.

| Pair | Source | LabScale settings | Output |
|---|---|---|---|
| `design_*` | `poster.py`: a flat-design poster drawn with PIL, reduced 4× to `design_source_400px.png` (400×250) | Anime & manga (`realesrgan-x4plus-anime`) · 4× · sharpness 30% (default) · Ultra | 1600×1000 |
| `photo_*` | `stone.py`: a procedural macro of granite with lichen, reduced 4× to `photo_source_400px.png` (400×250) | Foto realistis (`realesrgan-x4plus`) · 4× · sharpness 30% (default) · Ultra | 1600×1000, both sides shown at 1440×900 to fit 400 KB |

- `*_after` is genuine output of LabScale's own `Pipeline` (v2.1.1 code), not retouched. It was only converted to WebP and, for the photo, resized to 1440×900 together with its `before`.
- `*_before` is the same 400×250 source enlarged with bicubic (Catmull-Rom) to the same size.

The design source leaves out text smaller than ~10 px at source size. That
text is already lost before any upscaler sees it, and showing it garbled would
misrepresent what any upscaler can recover.

Only the bundled BSD-licensed models were used. The optional CC BY-NC-SA
models were not, because these images promote a company's product.
