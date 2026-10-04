# SmoothMotion 2.8.5 Fix28: quality update 2 (`fix28-qua2`)

> **Pacing:** for a build of this shader that always presents 2x with even
> frame pacing (DXGI and Vulkan), see [`../smoothmotion-locked`](../smoothmotion-locked/README.md).

This is a quality update to the frame synthesis of **SmoothMotion 2.8.5
RTX20/RTX30 DX12 Preview2 Fix28-Test**. Optical flow, pacing, the Vulkan
layer and every other part of Fix28 are unchanged. Only the synthesis shader
that Fix28 compiles at start-up was changed.

- Runtime version: `2.8.5-rtx20-rtx30-dx12-preview2-fix28-qua2`
- Log tag: `artifact_guard=occlusion_aware_v14`

> **Not tested on Windows with an NVIDIA GPU.** The shader was compiled with
> Microsoft's `d3dcompiler_47`, using the binary's exact flags. It was run
> through the full Fix28 pass chain on D3D11 (under Wine), on frames with
> exact ground truth. Real NVOF vectors and real games differ. Please compare
> F11 on/off in the same scene and send `nvsmooth30.log` either way.

## Fix24 vs Fix28 vs this build

**How it was measured:**
- **Shaders:** the exact shader text from each release. Fix24 was taken from
  its release zip in this repository's history.
- **Pipeline:** each shader ran its own pass chain on D3D11.
- **Frames:** identical frames for every version. Each frame is built from
  real photographs; the moving layers (characters, blades, crests, poles,
  fences, foliage, HUD text, crosshairs, subtitles) are composited over
  them. Frames are rendered at 2× and reduced, so the true midpoint frame is
  exact.
- **Flow:** identical for every version, with four NVOF stand-ins per scene:
  - a regularised block matcher on the frames;
  - ideal per-cell flow;
  - flow blurred across outlines;
  - noisy flow.

  All versions get full-resolution flow. In games, Fix24's GPU budget often
  chose half resolution, so these tables flatter Fix24 if anything.
- **Metric:** "wrong pixels" are output pixels off by more than 10% in any
  channel from the true midpoint. Every scene row sums its four flow models.

### Development set (12 scenes × 4 flow models)

| Scene | Fix24 wrong px | Fix28 wrong px | New wrong px | New vs Fix24 | PSNR Fix24 → New |
|---|---|---|---|---|---|
| Parallax foliage | 25,619 | 16,178 | 14,591 | −43% | 21.0 → 23.9 dB |
| Antialiased/translucent HUD + crosshair | 16,641 | 11,309 | 10,396 | −38% | 26.8 → 28.3 dB |
| Character + blade, camera orbit | 13,470 | 4,830 | 3,766 | −72% | 26.1 → 33.2 dB |
| Pole + wire crossing a still view | 13,339 | 13,716 | 11,836 | −11% | 22.7 → 25.1 dB |
| HUD text over pan | 11,178 | 6,800 | 5,816 | −48% | 24.0 → 26.5 dB |
| Fast vertical pan (44 px) | 10,960 | 8,245 | 7,794 | −29% | 31.1 → 32.2 dB |
| Pan with exposure change | 8,808 | 3,182 | 2,954 | −66% | 33.9 → 37.1 dB |
| Sword hilts over camera turn | 6,907 | 2,611 | 1,390 | −80% | 33.1 → 38.1 dB |
| Diagonal pan (half-pixel) | 6,747 | 4,593 | 4,225 | −37% | 31.3 → 32.8 dB |
| Helmet crest over starfield | 4,919 | 3,090 | 2,078 | −58% | 28.2 → 33.2 dB |
| Camera pan | 4,306 | 1,120 | 606 | −86% | 32.0 → 41.2 dB |
| Roofs over sky | 1,656 | 258 | 142 | −91% | 41.8 → 49.3 dB |
| **Total** | **124,550** | **75,932** | **65,594** | **−47%** | |
| **Mean PSNR** | **29.33 dB** | **31.90 dB** | **33.41 dB** | **+4.07 dB** | |
| Mean abs. error | 0.0108 | 0.0073 | 0.0065 | −40% | |

### Held-out set (11 scenes × 4 flow models, never tuned on)

| Scene | Fix24 wrong px | Fix28 wrong px | New wrong px | New vs Fix24 | PSNR Fix24 → New |
|---|---|---|---|---|---|
| Fence posts | 52,761 | 40,994 | 38,670 | −27% | 16.3 → 18.1 dB |
| Foliage | 18,832 | 14,981 | 14,453 | −23% | 25.4 → 26.9 dB |
| Pan + fade | 11,498 | 9,153 | 8,926 | −22% | 31.4 → 32.2 dB |
| Running character | 10,589 | 6,269 | 5,317 | −50% | 26.4 → 28.9 dB |
| Very fast pan (61 px) | 9,267 | 1,056 | 659 | −93% | 31.6 → 35.8 dB |
| Subtitles over pan | 8,990 | 5,805 | 5,066 | −44% | 29.6 → 30.9 dB |
| Night lights / stars | 8,799 | 7,422 | 5,178 | −41% | 29.5 → 33.3 dB |
| Sword swing | 4,719 | 2,672 | 2,587 | −45% | 32.5 → 34.7 dB |
| Low-contrast pan | 1,328 | 821 | 653 | −51% | 35.5 → 36.8 dB |
| Slow pan | 1,099 | 244 | 181 | −84% | 36.0 → 37.1 dB |
| Still scene | 0 | 0 | 0 | 0 | 60.2 → 60.2 dB |
| **Total** | **127,882** | **89,417** | **81,690** | **−36%** | |
| **Mean PSNR** | **32.21 dB** | **33.50 dB** | **34.09 dB** | **+1.88 dB** | |
| Mean abs. error | 0.0138 | 0.0109 | 0.0102 | −26% | |

### Fades and flashes (ideal flow)

| Case | Fix24 | Fix28 | New |
|---|---|---|---|
| Still scene, gentle fade | 4 px / 48.5 dB | 3 px / 48.5 dB | 2 px / 52.3 dB |
| Still scene, strong fade | 69,091 px / 17.1 dB | 69,091 px / 17.1 dB | **1,783 px / 34.1 dB** |
| Pan, gentle fade | 755 px / 27.6 dB | 682 px / 28.2 dB | 639 px / 28.4 dB |
| Pan, strong fade | 51,350 px / 14.0 dB | 51,317 px / 14.3 dB | 22,736 px / 17.3 dB |
| Flash (brightness +60%) | 79,633 px / 17.8 dB | 79,633 px / 17.8 dB | 31,242 px / 21.7 dB |

### Against Fix28, and safety checks

- **Against Fix28:**
  - development set −13.6% wrong pixels, +1.51 dB;
  - held-out set −8.6%, +0.59 dB.
- **No scene worse.** Every scene is better than or equal to Fix24 and Fix28.
- **HUD and subtitle glyph pixels** (the text itself, all four flow models):

  | | Fix24 | Fix28 | New |
  |---|---|---|---|
  | Subtitles | 654 wrong | 584 wrong | 542 wrong |
  | Antialiased/translucent HUD | 6,684 | 6,007 | 5,663 |
  | Crisp HUD text | 135 | 171 | 180 |

  On crisp HUD text the difference from Fix28 is churn of a few pixels per
  scene (out of 1,315 glyph pixels), with the same mean error.
- **Scene cuts** (unrelated frames, garbage flow). Pixels that match neither
  real frame nor their blend:

  | | Fix24 | Fix28 | New |
  |---|---|---|---|
  | Cut 1 | 12.6% | 13.1% | 13.6% |
  | Cut 2 | 8.9% | 8.3% | 8.6% |

- **Still scene:** still bit-exact.
- **Compilation:**
  - all 13 entries compile with
    `D3DCOMPILE_ENABLE_STRICTNESS | OPTIMIZATION_LEVEL3` and no warnings;
  - Synthesize takes 10.7 s instead of 8.0 s under Wine, once per version on
    the worker thread, before the result is cached.

`FIX24_VS_NEW.png` shows six cases: the true midpoint, Fix24, Fix28, this
build, and the Fix24 and new error maps.

## What changed

Every change targets a failure traced to a specific rule in the Fix28 shader
and was kept only after it measured better on both sets without making any
scene worse. The order follows the size of the effect.

1. **Partly confident results are trusted where the scene's motion is
   consistent.**
   - Resolve blends toward the unwarped real frame below confidence 0.9.
     Measured over both sets, that fallback was worse than the synthesized
     result at every confidence level from 0.2 to 0.8.
   - Synthesize now reports such results on a steeper scale, but only:
     - where the surrounding window moves consistently in both flow
       directions, so not on scene cuts or corrupted flow;
     - and not for one-sided fills along a motion that is not the window's
       (smeared vectors beside thin objects).
   - Result: −2.7% wrong pixels and +0.5 dB on its own.
2. **Optical flow repaired where the two flow directions disagree.**
   - Fix28's refinement only re-chose vectors that both flow directions
     agreed on. Noisy flow often disagrees without any occlusion.
   - Those cells are now searched too. A replacement must match the cell
     near-exactly, on textured content, which a coincidental match in a
     covered band rarely does.
   - Result: about −8% wrong pixels with block-matched flow.
3. **Fades and flashes.**
   - On a still scene, a pixel and its neighbours that change by one
     brightness factor are cross-faded. This needs the same factor 6 px away,
     because a fade is global.
   - During motion, a large brightness change is accepted when it is the same
     12 px away.
   - Before, strong fades fell back to the current frame: the generated frame
     was a whole fade step too dark.
4. **Moving detail is no longer frozen as UI** (stars, lights, sparks during
   pans).
   - Detail passing over content that looks the same in both frames is told
     apart from static UI: its own content follows the motion in both
     directions.
   - Repetitive HUD text, whose glyphs can match each other along the motion,
     is excluded.
5. **Translucent overlays** (crosshairs, HUD glass, subtitle panels, glyph
   antialiasing) are composited.
   - A static layer over moving scene satisfies
     `prev − cur = (1−a)·(cur(p+m) − prev(p−m))`.
   - The opacity fitted across three channels gives the midpoint exactly.
   - Translucent crosshair errors fell about 78%.
6. **Thin objects: poles, wires, fence posts, swords.**
   - Their own motion is judged by the centre and the neighbour pair lying
     along the object. Before, the background beside it rejected its motion.
   - Sparse objects that never register as the window's second motion are
     accepted as crossings when the flow saw their motion at one end.
   - A crossing must not rest at both ends, and must be clearly separate from
     the window's motion before it may lift HUD protection.
7. **No ghost of a thin object at its next position over a still view.**
   Coherence fills pixels that nothing validated from the background only if
   that background moved 2 px or more. It now also fills over a still
   background.
8. **Flow denoising inside one surface.** The mean of the neighbouring cells
   with the same motion replaces a vector where it matches the cell clearly
   better.
9. **Scene behind HUD text.**
   - Fix28's 2 px overlay protection is kept for text.
   - Scene pixels beside glyphs are released when their own value provably
     moved with the scene (one-pixel tolerance, both directions).
   - Antialiased glyph edges hold part of the static glyph and never pass this
     test.

### Tried and rejected (measured worse or traded quality in the wrong place)

- **Looser rules for one-directional occluders:** background beat crossing
  objects.
- **Ring-based overlay detector:** found more glyphs but gave no net gain.
- **Occlusion-ordered window motions:** the diagnosis was wrong.
- **Looser crossing veto:** false crossings with real flow.
- **Lanczos-3 resampling:** −1.3% for 3× the texture reads.
- **Uniformly looser Resolve ramp:** worse on scene cuts.
- **1 px overlay halo for every changed pixel:** damaged antialiased
  subtitles.
- **Unrestricted wide exposure range:** worse on normal content.

## Install

Use the manual route of Fix28 (see Fix28's `MANUAL_INSTALL.md`). Close the
game first, and keep copies of the files you replace.

- **ASI loader route** (`dinput8.dll`, `winmm.dll` or another loader):
  replace the game's `new.asi` with `bin/new.asi` and keep the loader.
- **Standalone route:** replace the game's `version.dll` with
  `bin/version.dll`.
- **Check the log.** `nvsmooth30.log` must show
  `2.8.5-rtx20-rtx30-dx12-preview2-fix28-qua2` and `occlusion_aware_v14`.
  - The first start compiles the new shader (frames pass through for about
    10-30 s); later starts use the shader cache.
  - The cache key hashes the shader source, so older bytecode is never
    reused.

The Fix28 `SmoothMotion_Manager.exe` and `Install.exe` check the SHA-256 of
the Fix28 binaries, so they will not install these files. Copy them by hand.
Restore your originals before uninstalling with the Manager.

| File | SHA-256 |
|---|---|
| `bin/new.asi` | `d2ddf588411b5d5f4ccc689aef40e83094d2f98ac2e560627ac5dd0b31266d6e` |
| `bin/version.dll` | `ec7d81ca00463a168b8385016f0388f230d2477c2d49ac307ef60d58b7225e0f` |

## Files

- `bin/`: Fix28 `new.asi` and `version.dll` with the new shader. Only the
  embedded shader text and the version and log tags differ from Fix28
  (verified byte by byte).
- `shader/shaders.hlsl`: the improved shader, fully commented.
- `shader/shaders_fix28.hlsl`: Fix28's shader, as extracted from its release.
- `shader/shaders_fix24.hlsl`: Fix24's shader, as extracted from its release.
- `shader/fix28-to-quality.patch`: the difference between Fix28 and the new
  shader.
- `shader/shaders_embedded.hlsl`: the exact text inside the binaries.
  - It is `shaders.hlsl` without comments, padded with spaces to 77,819
    bytes, because Fix28 passes the shader to `D3DCompile` with that fixed
    length.
  - Its rendered output is pixel-identical to `shaders.hlsl` on all 92 test
    cases.
  - `tools/strip_shader.py` produces it.
- `tools/patch_binary.py`: rebuilds `bin/` from an original Fix28 package. It
  refuses to write unless exactly the expected bytes change:

  ```
  python3 tools/strip_shader.py shader/shaders.hlsl shader/shaders_embedded.hlsl 77819
  python3 tools/patch_binary.py <Fix28>/Manual/ASI_Only/new.asi new.asi shader/shaders_fix28.hlsl shader/shaders_embedded.hlsl qua2 v14
  ```

- `tools/harness/`: the test rig.
  - `harness.cpp` runs each version's own pass chain on D3D11:
    - Fix28 and this build: Refine → Project → DominantMotion → OverlayMask
      → OverlayGrow → Synthesize → Coherence → Resolve;
    - Fix24: Project → OverlayMask → OverlayGrow → Synthesize → Resolve.
  - `scenes.py` and `heldout.py` build the scenes and flows.
  - `run.py` and `score_all.py` score a shader.
  - `table.py` builds the tables above.
  - `hudcheck.py` and `cutcheck.py` run the text and scene-cut checks.
  - It needs Wine, MinGW, Xvfb, numpy, scipy, scikit-image and Microsoft's
    `d3dcompiler_47.dll`, renamed `d3dcompiler_47_ms.dll`, next to
    `harness.exe`.

## Limits

- **Flow-blind objects.** Thin objects the optical flow does not see in
  either direction cannot be drawn at the midpoint, because no candidate
  motion exists for them. Examples: a 2 px wire, or fence posts whose flow
  is blurred away. The fence scene remains the largest error source.
- **Mixed outline pixels.** A pixel that is part object and part background
  has no single correct motion. These are about 9–16% of the remaining
  errors.
- **Aliased fine detail.** One-pixel lattices that land on half-pixel
  midpoints cannot be resampled exactly.
- **Stand-in flow.** The test flows stand in for NVIDIA's hardware flow, so
  absolute numbers in games will differ.
- **No neural model.** As in Fix28, NVIDIA's proprietary Smooth Motion
  neural model is not part of this package. This is NVOF hardware flow with
  hand-written synthesis.
