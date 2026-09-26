# Fix 12 — quality test: lighting changes and edge robustness

Runtime version: `2.8.4-rtx20-dx12-preview2-fix12-quality-test`.
Includes everything in Fix11 (adaptive half-resolution flow, GPU timing) and
Fix10 (fast pans, HUD text).

No new recording was supplied. This build was driven by a harder offline
simulation. It adds zoom, rotation, auto-exposure/brightness changes, sensor
noise, thin wires and line grids, fast pans and high-frequency texture to the
earlier moving-object scenes, all checked against rendered true midpoints.

## What was still wrong in Fix11

- **Lighting changes between the two real frames** broke the matching. Every
  test compared absolute colours. Auto-exposure adapting while you pan between
  dark and bright areas, flickering torches and moving shadows made correct
  motion look wrong. The shader then fell back to the unwarped current frame
  in scattered pixels across the whole image. With a +20% exposure change this
  gave 2768 visibly wrong pixels, versus 38 for the same scene without it.
- **Background beside a moving object's edge** could claim the object's motion
  through the "crossing object" preference when the background texture matched
  loosely.
- **Occlusion fill brightness.** Areas visible in only one frame were copied at
  that frame's brightness. A lighting change then left a light or dark halo
  beside moving objects.

## Changes

- **Exposure-compensated matching.** Each pixel estimates the local exposure
  change from nine colour differences on a 7x7 neighbourhood matched along the
  local motion. The estimate is robust: it keeps only the samples that agree
  with the most consistent one. It is dropped when fewer than about four
  agree, near object edges, or when the offset is larger than a plausible
  lighting change (scene cuts). The same offset applies to every candidate
  motion, so a wrong vector cannot pass a smooth gradient off as brightness.
  The checks for unexplained content and occluders accept a match with or
  without the offset, because a light may not affect every object.
- **Occlusion fill at midpoint exposure.** One-frame fills are shifted by half
  the estimated change, which removes the halo.
- **Crossing objects must be the object.** The thin-object preference applies
  only when both samples are not already explained by the background motion.
- Log marker: `artifact_guard=occlusion_aware_v4`. Fix11 runtime hashes are
  recognized for managed upgrades.

## Results (host simulation, bad = pixels with error > 0.12)

| Flow | Fix11 | Fix12 |
|---|---:|---:|
| Full-resolution, clean flow | 3723 | 1413 |
| Full-resolution, noisy flow | 4256 | 1927 |
| Half-resolution, clean flow | 5949 | 3637 |
| Half-resolution, noisy flow | 6154 | 3846 |

- **+20% exposure scene:** 2768 → 446 bad pixels.
- **Rotation, the thin pole with noisy flow, line grids:** improved.
- **Box, zoom, noise, wire, fast pan and texture scenes:** within a few
  pixels of Fix11.

## Install

Same as before: replace the game's `VERSION.dll` with
`Manual/Version/version.dll` (keep the previous file), run
`Test/ShaderCheck.exe` (five PASS lines), and look for the Fix12 version and
`occlusion_aware_v4` in `nvsmooth30.log`. `nvsmooth30.ini` from Fix11 still
applies.

## Cost and limits

- About 20 more texture reads per pixel for the exposure estimate, plus some
  arithmetic, and a few reads on the thin-object branch. The GPU timing block
  in the log (added in Fix11) will show the effect.
- Lighting changes larger than about 12% per channel between two consecutive
  real frames are not compensated.
- Thin detail without its own flow and fine repeating texture remain the
  hardest cases.
- Windows/GPU execution and in-game quality are unverified.

## Validation

- **Shader tests:** seventeen shader behavior groups pass in optimized and
  ASan/UBSan builds. The new group applies a +15% auto-exposure change during
  two parallax motions. Fix12 passes; Fix11 exceeds the error limit (RMSE
  29–42% of copying the current frame).
- **Shader compilation:** glslang, and DXC in strict mode (HLSL 2016 and
  2021).
