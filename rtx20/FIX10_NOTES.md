# Fix 10 — fast-pan and HUD artifact test

Runtime version: `2.8.4-rtx20-dx12-preview2-fix10-motion-hud-test`.

Fix9 removed most of the block artifacts. This build targets the two artifacts
left in the Fix9 Witcher 3 recording (`Test_RTX2080_2026-09-27_02-50-07.mp4`,
`nvsmooth30_34.log`: RTX 2080, 1920x1080, native D3D11 NVOF API5, Fix9 active,
zero transfer or RTX20 failures). It is a test build; Windows/GPU execution
and frame-time cost are still unverified.

## What the recording shows

- The log's counters rise by about 1,800 flow pairs per minute. That is a
  30 FPS base doubled to 60 on the 60 Hz display.
- During the camera orbits, the image moves 15–50 pixels between captured
  frames. Motion between two real frames therefore reaches roughly 60–100
  pixels.
- **Pole top breaking into blocks.** Fix9 lowered confidence from 64 pixels of
  motion and rejected candidates over 128 pixels. Its midpoint projection
  searched only about ±40 pixels of motion. At these pan speeds, thin objects
  lost their motion candidates and the occlusion bands beside them were
  rejected.
- **Quest text and key hints partly erased** ("CONTRACT", "Jump", "Call
  Horse"). The optical flow follows the scene through the HUD. Only the opaque
  glyph cores are identical in both frames, so only they were protected. The
  antialiased edges and semi-transparent outlines were interpolated with the
  background and ripped letters apart.

## Changes

- **Large motion.**
  - Candidates are accepted up to 256 pixels of motion, with confidence fading
    only from 160 pixels.
  - The midpoint projection centres its search on the local motion, so objects
    moving up to 40 pixels relative to a fast pan are still found.
- **Relative occluder test.** One-sided occlusion fill needs the hidden side to
  move differently. That difference is now measured relative to the candidate
  motion rather than scaled with absolute speed, so a pole moving 20 pixels
  against a 90-pixel pan still gets a clean background fill beside it.
- **HUD over moving scenery.** A pixel is flagged as a static overlay when all
  of the following hold:
  - it is identical in both frames and has local contrast;
  - every surrounding flow block moves;
  - the local motion does not explain it.

  Near any flagged pixel, Resolve keeps the real frame. This keeps the glyph
  edges and outlines intact. Pixels of objects that stay fixed on screen during
  a camera orbit, such as Geralt, sit next to zero-motion blocks and are not
  flagged.
- Fix9 runtime hashes are recognized for managed upgrades. Pacing, alpha
  handling and the MEDIUM preset are unchanged.

## Install

1. Close the game. Replace `H:\Games\The Witcher 3\bin\x64_dx12\VERSION.dll`
   with `Manual/Version/version.dll`, keeping the Fix9 file for rollback (or
   use the Manager / `Manual/ASI_Only/new.asi` for those routes).
2. Run `Test/ShaderCheck.exe`: five PASS lines expected.
3. The log must show the version above and `artifact_guard=occlusion_aware_v3`.
4. Repeat the same orbit around Geralt with the pole, quest text and key hints
   in view, and compare with F11 off.

## Limits

- The base frame rate is the main factor. At 30 FPS, each generated frame
  bridges 60–100 pixels in a fast pan. NVIDIA's 4x4 optical flow and the absence
  of game depth, motion-vector or UI buffers leave some fringe or ghosting on
  very fast, thin or transparent detail. A higher base frame rate reduces this
  directly.
- Text over moving scenery is shown as the real frame, not interpolated. The
  background right around the letters therefore moves at the base frame rate.
  HUD elements large enough to own their flow blocks are handled as before.
- GPU cost is about the same as Fix9. It adds one 5x5 alpha gather in Resolve
  and a few samples in Synthesize.

## Validation

Fifteen shader behavior groups pass in optimized and ASan/UBSan host builds.
Two groups are new:

- **HUD text over a panning scene** (opaque cores, blended edges,
  semi-transparent outline). Fix10 keeps 1095/1104 text pixels intact; Fix9
  keeps 914.
- **90-pixel pan with a thin pole moving 70 pixels.** Fix10 shows the pole at
  the midpoint in 184/184 pixels, with RMSE 13% of copying the current frame.
  Fix9 shows 0/184.

The ten-scene development simulation stays at the Fix9 level: 891 against 871
bad pixels with clean flow, 1301 against 1282 with noisy flow. All five entry
points compile with glslang, and with DXC in strict mode for HLSL 2016 and 2021.
