# SmoothMotion 2.8.5 Fix28: quality update (`fix28-qual`)

This folder holds a quality update to the frame synthesis of
**SmoothMotion 2.8.5 RTX20/RTX30 DX12 Preview2 Fix28-Test**. Optical flow,
pacing, the Vulkan layer and every other part of Fix28 are unchanged. Only the
synthesis shader that Fix28 compiles at start-up was changed.

- Runtime version: `2.8.5-rtx20-rtx30-dx12-preview2-fix28-qual`
- Log tag: `artifact_guard=occlusion_aware_v13`

> **Not tested on Windows with an NVIDIA GPU.** The new shader was compiled
> with Microsoft's `d3dcompiler_47` using the binary's exact flags. It was run
> through Fix28's full pass chain on D3D11 under Wine, on synthetic frames
> with exact ground truth. Real NVOF vectors and real games differ. Please
> compare F11 on/off in the same scene and send `nvsmooth30.log` either way.

## What changed and why

The improvements stay within the design of NVIDIA's Smooth Motion style:
motion-compensated midpoint frames from hardware optical flow, protecting
UI, with no hallucinated content. Each change fixes a failure traced to a
specific rule in the Fix28 shader, and each one was kept only after it
measured better than Fix28 without making any test case worse.

1. **Moving detail is no longer frozen as "UI"** (stars, lights, sparks,
   specular glints during camera pans).
   - Resolve keeps the real frame wherever a pixel is identical in both real
     frames and has contrast nearby, because that is what screen-fixed UI
     looks like.
   - A dark-sky or plain-wall pixel that a light passes over between the two
     frames also looks like that. The midpoint, which Synthesize had
     reconstructed correctly, was then replaced by the empty background.
   - Such pixels are now told apart from UI: the motion explains their own
     content in both directions (exact 5-sample patches), which static UI
     never satisfies.
   - This is the largest gain: a plain pan with clean flow improved from
     37.7 to 45.0 dB.
2. **No ghost of a thin object at its next-frame position over a still
   scene.** Coherence fills pixels that nothing validated from the
   background, but only when the background moved at least 2 px. With the
   camera still (a pole, wire or sword crossing a static view), those pixels
   kept the next frame, object included. The fill now also works for a
   static background.
3. **Cleaner scene between HUD glyphs.**
   - Resolve forced the unwarped current frame on every pixel within 2 px of
     an overlay pixel. Two pixels out, that pixel is the moving background,
     misplaced by half the motion.
   - Pixels that changed between the frames are now protected only within
     1 px (antialiased glyph edges).
   - Unchanged pixels (the glyph strokes, of which OverlayMask flags only
     some) keep the 2 px reach, so text itself is protected as before.

## Measured

The real shader ran on D3D11 under Wine and was compared pixel by pixel
with the exact midpoint. A pixel counts as "wrong" when it is off by more
than 10% in any channel.

The test frames are real photographs composed into scenes:
- camera pans;
- thin static detail over a pan;
- a helmet crest over a starfield;
- a character orbit with a blade;
- poles and wires crossing a still scene;
- crisp, antialiased and translucent HUD;
- exposure changes, parallax and roofs over sky.

Each scene runs with four NVOF stand-ins:
- a regularised block matcher on the frames themselves;
- ideal per-cell flow;
- flow blurred across outlines;
- noisy flow.

| Set | Fix28 wrong px | fix28-qual | Mean PSNR |
|---|---|---|---|
| Development set (12 scenes × 4 flows) | 74,188 | 69,011 (**−7.0%**) | 31.96 → **32.82 dB** |
| Held-out set (11 new scenes × 4 flows, never tuned on) | 136,710 | 134,687 (**−1.5%**) | 33.08 → **33.20 dB** |

- **No case got worse.** That holds for all 48 development cases and all
  44 held-out cases.
- **The held-out set includes these checks:**
  - night lights: +0.9 dB;
  - subtitles: up to −16% wrong;
  - a fence of poles, foliage, a runner, a sword swing, a very fast pan
    and an exposure fade;
  - a static scene, which is still bit-exact.
- **HUD glyph pixels themselves** are unchanged from Fix28 within a few
  pixels per scene.
- **Scene cut** (unrelated frames, garbage flow): the output matches Fix28
  on all but 17 of 82,944 pixels.
- **Shader compilation:**
  - all 13 entries compile under `D3DCOMPILE_ENABLE_STRICTNESS | OPTIMIZATION_LEVEL3` with no warnings;
  - Synthesize takes about 1 s longer to compile, once per version on the
    worker thread, before the result is cached.
- **GPU cost:** the new work runs only in rare branches, so per-frame cost
  is essentially unchanged.

`QUALITY_COMPARE.png` shows truth, Fix28 and fix28-qual for four of the
cases, with their error maps.

### Tried and rejected

These were measured and dropped because they made things worse or traded
quality in the wrong place:

- **Accept one-directional occluders:** +1.0% wrong; it let background
  fills beat crossing objects.
- **Ring-based overlay detector:** finds 6× more glyphs but no net gain.
- **Occlusion-ordered dominant motion:** +1.4% wrong; the ordering
  diagnosis was wrong.
- **Looser crossing veto:** +2.1% wrong with block-matched flow.
- **Looser Resolve confidence ramp:** −1.0% overall but worse next to
  objects.
- **Removing Coherence's soften branch:** fewer wrong pixels but lower
  PSNR. That branch trades error for fewer fragments on purpose.

## Install

Use the manual route of Fix28 (see Fix28's `MANUAL_INSTALL.md`). Close the
game first, and keep a copy of the files you replace.

- **ASI loader route** (`dinput8.dll`, `winmm.dll` or another loader):
  replace the game's `new.asi` with `bin/new.asi` and keep the loader.
- **Standalone route:** replace the game's `version.dll` with
  `bin/version.dll`.
- **Check the log.** `nvsmooth30.log` must show
  `2.8.5-rtx20-rtx30-dx12-preview2-fix28-qual` and `occlusion_aware_v13`.
  The first start compiles the new shader (frames pass through for about
  10-30 s); later starts load it from the shader cache. The cache key hashes
  the shader source, so Fix28's cached bytecode is never reused.

The Fix28 `SmoothMotion_Manager.exe` and `Install.exe` check the SHA-256 of
the Fix28 binaries, so they will not install these files. Copy them by hand.
The Manager's uninstall receipts are not updated by manual copying (as in
Fix28). Restore your saved originals before uninstalling with the Manager.

| File | SHA-256 |
|---|---|
| `bin/new.asi` | `91e429372109a779d015c28ba04cc52d1755f530bc93447954bcf28333f2a789` |
| `bin/version.dll` | `206d1dd82572bbb5a2d49e76e85fe818d2b3c4a5a32bd6663b934ca08c4c6d88` |

## Files

- `bin/`: Fix28 `new.asi` and `version.dll` with the new shader. Only the
  embedded shader text and the version and log tags differ from Fix28
  (verified byte by byte).
- `shader/shaders_fix28.hlsl`: the shader as extracted from Fix28.
- `shader/shaders.hlsl`: the improved shader.
- `shader/fix28-to-quality.patch`: the difference between the two.
- `shader/shaders_embedded.hlsl`: the exact text in the binaries.
  - It is the improved shader with leading indentation removed and
    trailing spaces added.
  - Fix28 passes the shader to `D3DCompile` with a fixed length of 77,819
    bytes, so the text must be exactly that long.
  - Every comment is kept, and the rendered output is pixel-identical.
- `tools/patch_binary.py`: rebuilds `bin/` from an original Fix28 package.
  It refuses to write unless exactly the expected bytes change:

  ```
  python3 tools/patch_binary.py <Fix28>/Manual/ASI_Only/new.asi new.asi shader/shaders_fix28.hlsl shader/shaders_embedded.hlsl
  ```

- `tools/harness/`: the test rig.
  - `harness.cpp` runs the Fix28 pass chain:
    1. RefineForward / RefineBackward
    2. Project
    3. DominantMotion
    4. OverlayMask
    5. OverlayGrow
    6. Synthesize
    7. Coherence
    8. Resolve
  - `scenes.py` and `heldout.py` build the scenes and flows.
  - `run.py` scores a shader.
  - It needs Wine, MinGW, Xvfb, numpy, scipy, scikit-image and Microsoft's
    `d3dcompiler_47.dll`, renamed `d3dcompiler_47_ms.dll`, next to
    `harness.exe`.

## Limits

- **Flow-blind objects.** Thin objects the optical flow does not see in
  either direction still cannot be drawn at the midpoint. Examples: a 2 px
  wire, or a pole whose flow is blurred away. No candidate motion exists for
  them.
- **Mixed edge pixels.** An antialiased pixel that is part object and part
  background has no single correct motion, so it stays approximate.
- **NVIDIA's proprietary Smooth Motion neural model** is not part of this
  package, as in Fix28. This remains NVOF hardware flow with hand-written
  synthesis.
