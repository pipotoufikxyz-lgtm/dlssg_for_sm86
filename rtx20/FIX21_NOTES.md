# Fix 21 — less ghosting and fewer wrong pixels (RTX 20 and RTX 30)

Runtime version: `2.8.4-rtx20-rtx30-dx12-preview2-fix21-test`.

Fix21 improves the generated frames themselves. RTX 30 and RTX 20 use the
same synthesis, so both cards get it. Nothing else changes: pacing, the
performance guard, the GPU budget and settings are the same as Fix20. This is
a test build: it has not run on Windows or a GPU here.

## How it was measured: real game frames

- **Frames.** They come from the Witcher 3 recording (1080p, 30 to 60). In
  that recording every other frame is real. Frames 113–125 are used, where
  the real/generated order was verified.
- **Method.** For each triplet of real frames n-2, n and n+2, frame n is
  generated from n-2 and n+2, then compared with the real frame n.
  - This runs the production shader in the CPU shader model.
  - Optical flow comes from OpenCV DIS, reduced to NVOF's 4x4 grid. This
    stands in for NVIDIA's hardware flow.
- **Crops.** 5 triplets × 5 crops = 25 cases (480x320 each):
  - `edge`: building edge against sky
  - `roofs`: roofs and chimney
  - `right`: right-hand buildings
  - `hud`: minimap, coins, quest text over clouds
  - `ground`
- **Metric.** "Wrong pixels" are output colours that do not appear anywhere
  within ±2 pixels in the real frame. Ghosts, pasted blocks and missing
  pieces count; a small overall shift does not.

| Crop | Fix20 | Fix21 |
|---|---|---|
| Building edge | 5,373 | 5,013 |
| Roofs / chimney | 2,275 | 320 (−86%) |
| Right buildings | 1,372 | 1,118 |
| HUD over clouds | 7,892 | 6,681 |
| Ground | 355 | 81 |
| **Total wrong pixels** | **17,267** | **13,213 (−23%)** |
| Mean PSNR | 29.70 dB | 30.30 dB |
| Mean abs. error | 0.0159 | 0.0155 |

`FIX21_COMPARE.png` shows three cases: the real frame, then Fix20 and Fix21
with wrong pixels in red.

## What changed

1. **Static-looking flat areas no longer paste the next frame.**
   - Resolve keeps the real frame wherever both real frames are identical at
     a pixel, to protect HUD and UI. Clear sky and flat walls are also
     identical in both frames. When a thin object (a chimney, pole or window
     frame) passes over them in between, Fix20 pasted sky over it. The
     object then vanished or flickered in every generated frame.
   - This override now also needs local detail, which UI has and flat sky
     does not, or a result that is close to the real frame anyway.
   - This was the biggest source of wrong pixels in the Witcher frames.
2. **Unexplained pixels follow the motion instead of lagging behind.**
   - Where no motion interpretation fully validated, Fix20 blended toward
     the unwarped next frame. That places moving content half a step ahead:
     a ghost or double edge.
   - It now falls back to the midpoint along the local motion when the scene
     clearly moves (at least 1 pixel) and both frames match there as a
     patch.
   - This fallback is not used at crosshairs and HUD, which keep their Fix19
     protection.

Costs about 4 extra texture reads per pixel in Resolve, plus a patch match
only on pixels that were not fully explained. The GPU budget still applies.

## Tests

- New shader behaviour group "thin object crossing flat stationary-looking
  sky":
  - A chimney pans 16 pixels over nearly flat sky.
  - Missing chimney pixels: Fix20 272 of 408; Fix21 passes (at most 2%).
- All 21 earlier groups pass with the same numbers as Fix20. That includes
  the crosshair and HUD groups, the newly appearing object, and the roof over
  flat sky. There are 22 groups in total, run in optimized and ASan/UBSan
  builds.
- All nine HLSL entry points compile with glslang 15.1.0.

## Limits

- The flow here is a stand-in for NVOF. On your card, NVIDIA's hardware
  flow is used, so absolute numbers will differ. The direction of the change
  should hold.
- Remaining wrong pixels are mostly at:
  - the minimap rim (the minimap content rotates, which no motion vector
    describes);
  - HUD panel edges over moving clouds;
  - one-sided fills along building edges.
- Very thin details (under about 2 pixels) that move fast can still soften.

## Install and check

1. Replace the previous file with `Manual/Version/version.dll` or
   `Manual/ASI_Only/new.asi`, or use the Manager. It recognizes exact Fix20
   binaries.
2. The log must show the version above.
3. Compare slow camera pans across rooftops, poles and thin objects over sky
   with Fix20. Also check that the crosshair and HUD still stay steady.
