# Before/after samples

Marketing samples for the LabScale product page. Neither contains a person or
anything identifying.

| Pair | Source | LabScale settings | Output |
|---|---|---|---|
| `design_*` | A flat-design poster generated with the Z-Image model on kie.ai (2026-10-14, 1280×720), reduced 4× to `design_source_320px.png` (320×180) | Desain & ilustrasi (`ultramix-balanced-4x`) · 4× · sharpness 30% (default) · Ultra | 1280×720 |
| `photo_*` | `stone.py`: a procedural macro of granite with lichen, made 2026-10-13, reduced 4× to `photo_source_400px.png` (400×250) | Foto (`realesrgan-x4plus`) · 4× · sharpness 30% (default) · Ultra | 1600×1000, both sides shown at 1440×900 to fit 400 KB |

- `*_after` is genuine output of LabScale's own `Pipeline`, not retouched. It
  was only converted to WebP and, for the photo, resized to 1440×900 together
  with its `before`. The design pair comes from 2.2.0 code, the photo pair
  from 2.1.1; the Foto model and its settings did not change between them.
- `*_before` is the same small source enlarged with bicubic to the same size.

The design sample uses UltraMix Balanced, the model behind "Desain &
ilustrasi". It is not bundled: the app downloads it on request, and its
licence (CC BY-NC-SA 4.0) allows non-commercial use only. The photo sample
uses a bundled BSD-licensed model.

## App screenshot

`app_compare_view.webp` is LabScale's real compare viewer (`CompareView`),
rendered offscreen from the app's own widget code with the design pair above
loaded: the 320×180 source on the left, the LabScale result on the right.
It was rendered rather than screen-captured so that no clicks on a shared
desktop were needed. The top bar (file name and "Show in Finder") is cropped
off; the comparison stage below it is untouched.
