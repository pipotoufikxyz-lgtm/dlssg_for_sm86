# Fix 24 — image quality: skies, HUD text, thin static detail

Runtime version: `2.8.5-rtx20-rtx30-dx12-preview2-fix24-test`.

Fix24 was first published as 2.8.4. Version 2.8.5 is the same build under a new
number: frame generation is unchanged. Only the version, the Manager's sidebar
(it still said Fix 20) and its list of recognized binaries changed.

Fix24 changes only how generated frames are made (the Synthesize and
Resolve shaders). RTX 20 and RTX 30 use the same synthesis.

- Pacing, the performance guard, GPU budget, the probe swapchain and all
  settings are exactly as in Fix23.
- The log shows `artifact_guard=occlusion_aware_v8`.
- This is a test build: it has not run on Windows or a GPU here.

## A bigger, fairer benchmark on real game frames

Fix21 measured quality on 5 frame triplets from one Witcher 3 recording.
This time:

- **Real frames found automatically.** In a frame-generation recording every
  other frame is generated. A generated frame is by construction the exact
  midpoint of its neighbours: its forward and backward motion cancel. Real
  frames are not, because the game renders them unevenly spaced. This
  separates them reliably (about 0.03 against 0.2–0.7), and it confirmed the
  window used before.
- **47 triplets of consecutive real frames** across the recording, instead
  of 5. The benchmark uses 120 cases:
  - 16 triplets × 5 crops with full-resolution flow;
  - 8 triplets × 5 crops with half-resolution flow, which the runtime uses
    above 58 FPS.
  - Crops: HUD/minimap over the sky, Geralt's hair against the roofs, a
    facade, rooflines, and the ground.
- **Midpoint-aware scoring.** Real frames sit 2–12 px away from the true
  midpoint of their neighbours. That offset was counted as an error before.
  Now a pixel counts as wrong only if its colour appears neither near the
  real frame nor near the real frame shifted to the midpoint.
- **Crop edges excluded.** A crop's border acts like a screen edge: content
  moving in from outside cannot be known. A border band scaled to each
  triplet's motion is left out of the count.
- **Limits.**
  - OpenCV DIS optical flow stands in for NVIDIA's hardware flow.
  - A frame is generated from real frames two apart, so motions are twice
    what a 30 FPS base rate gives. This makes the benchmark a stress test.

## Results

Wrong pixels, 120 real-frame cases:

| Crop | Fix23 | Fix24 |
|---|---|---|
| HUD / minimap over sky | 30,677 | 25,258 |
| Geralt's hair against roofs and sky | 1,982 | 1,858 |
| Facade | 245 | 217 |
| Rooflines | 628 | 616 |
| Ground | 2,054 | 1,741 |
| **Total** | **35,586** | **29,690 (−17%)** |

Other measures:

| Measure | Fix23 | Fix24 |
|---|---|---|
| Whole crops, fixed 8 px margin | 53,506 | 45,689 (−15%) |
| Fix21's 25-case benchmark (5 triplets) | 13,237 | 11,706 (−12%) |
| Synthetic sword-hilt and hair scene: wrong pixels | 12,141 | 9,079 (−25%) |
| Synthetic scene: erased hilt/hair pixels | 1,878 | 1,455 (−23%) |
| Synthetic scene: faint ghost pixels | 5,884 | 3,687 (−37%) |

By motion between the real frames (smaller motion is closer to real play at
a 30–60 FPS base):

| Motion | Cases | Fix23 | Fix24 | Change |
|---|---|---|---|---|
| Small | 45 | 6,845 | 5,431 | −21% |
| Medium | 55 | 17,095 | 14,348 | −16% |
| Large | 20 | 11,646 | 9,911 | −15% |

- **Sharpness.** Generated frames keep the same amount of fine detail as the
  real frames around them (ratio 1.007; Fix23 1.004). Nothing got blurrier,
  so there is no sharpness flicker.
- **Cost.** About 2–3% more texture reads per pixel than Fix23, weighting
  each 32-pixel wave by its slowest pixel. These are counts in the shader
  model, not GPU timings.

`FIX24_COMPARE.png` shows the cases with the largest change: the real frame,
then Fix23 and Fix24, with wrong pixels in red.

## What changed

1. **Soft content dissolves instead of jumping ahead.**
   - Where no motion could be validated, Fix23 showed the unwarped next
     frame. In clouds, fog and smooth shading that leaves a patchwork of two
     cloud states, misplaced by half the motion.
   - Such soft content now cross-fades the two frames at that pixel.
   - The cross-fade applies only where it cannot double anything:
     - the content must be low-contrast (textured content keeps the next
       frame);
     - both frames must be close at that pixel (a moved edge or a scene
       cut keeps the next frame);
     - never next to HUD or overlay pixels, and never on stationary pixels.
   - This was the largest single gain.
2. **A better fallback motion.** When a pixel is only partly explained, the
   midpoint fallback now uses the best-matching of the local motion and the
   top-ranked candidates, not the local motion alone. This matters where
   static HUD panels dragged the flow of a large area to zero.
3. **Static text and screen-fixed detail stay put.**
   - Zero motion is now accepted when the pixel is identical in both frames
     and one flow direction supports it. HUD text over a moving scene often
     has zero flow in only one direction, because the other carries the
     scene behind it; before, the scene was painted over the letters.
   - Cores of thick HUD glyphs are kept exactly: identical in both frames,
     standing out 3 px away, next to moving flow that does not explain them.
   - One-sided fills also recognise thick glyph interiors as static detail,
     so they no longer copy fragments of text into the sky below it.
   - The same rules keep more of the sword hilts and hair (the synthetic
     scene above).

## Limits

- Very large, soft motions whose flow itself is wrong remain patchy, though
  softer now. Example: the sky around the HUD, moving 60–90 px between the
  benchmark's frames.
- Text whose colour the moving background also shows nearby, with flow
  carrying the background in both directions, can still lose pixels. In the
  test for this, 292 of 328 stroke pixels stay intact (Fix23: 178).
- Small objects that fly independently (birds) are still shown where the
  next real frame has them.
- **Half-resolution flow.** On the same 8 triplets it gave no worse results
  overall than full resolution (10,892 vs 11,360 wrong pixels): somewhat
  worse on hair, better on the large-motion sky. The automatic choice is
  unchanged.

## Tests

- 24 shader behaviour groups pass in optimized and ASan/UBSan builds. Two
  groups are new:
  - "Soft content dissolves where no motion validates; textured content does
    not": soft content error 0.057 in Fix23, 0.016 now; the unwarped frame
    gives 0.071. Textured content shows no cross-fade.
  - "Static text keeps zero motion supported by one flow direction".
- Two groups (extreme or nonreciprocal flow, and the newly appearing
  object's margins) accept a dissolve at the same pixel as well as the
  current frame. A same-pixel dissolve moves nothing, so it cannot smear or
  misplace content.
- The scene-cut, identity, HUD-text and crosshair groups stay strict.
- All nine HLSL entry points compile with glslang 15.1.0.

## Install

Replace the previous file with `Manual/Version/version.dll` or
`Manual/ASI_Only/new.asi`, or use the Manager. It recognizes exact Fix23
binaries and the Fix24 binaries published as 2.8.4. Check the log for the version above and
`artifact_guard=occlusion_aware_v8`.
