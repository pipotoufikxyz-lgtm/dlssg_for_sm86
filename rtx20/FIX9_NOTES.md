# Fix 9 — occlusion-aware synthesis test

Runtime version: `2.8.4-rtx20-dx12-preview2-fix9-occlusion-test`.

This update targets the broken rooflines, blocky patches beside the character
and fragments around thin objects in the Fix8 Witcher 3 DX12 screenshot
(`nvsmooth30_23.log`: RTX 2080, 1920x1080, native D3D11 NVOF API5, zero transfer
or RTX20 failures). It is a test build. Windows/GPU execution, displayed image
quality and frame-time cost are still unverified.

## Why Fix8 still showed blocks

The log rules out transfer or API failure, so the synthesis shader was the cause.
Fix8 rejected every pixel whose correspondence it could not fully verify and
showed the **unwarped current frame** there. It then widened each rejection with
a 3x3 minimum filter at 2-pixel spacing. Each foreground/background boundary has
an occlusion band, and a 4x4 flow grid mixes vectors at edges, so nearly all edge
pixels were rejected. The current frame is displaced by half the motion relative
to the generated midpoint. Pasting it into those rejected, grid-shaped regions
produces the misaligned blocks along rooflines, the pole and Geralt's outline.

A host simulation of moving objects over moving backgrounds with NVOF-like
4x4 block vectors reproduces this. Fix8 output was barely closer to the true
midpoint than copying the current frame (RMSE 0.093 against 0.106), and a
3.5-pixel pole was absent from the midpoint.

## Changes

- **Per-pixel candidate matching.** Each output pixel evaluates unmixed block
  vectors around both midpoint correspondences, motions projected through its
  own cell, and zero. It picks the best by a symmetric patch match plus
  forward/backward flow support. Object edges follow image content, not the
  4x4 flow grid, and bilinear foreground/background mixtures are no longer used
  as motion.
- **Midpoint motion projection (new pass).** A small pass on the flow grid moves
  every block vector to the cell it crosses at t=0.5, and keeps the nearest
  motion plus the nearest clearly different one. This finds thin objects whose
  own vectors sit several pixels away from where they appear in the generated
  frame.
- **Crossing preference.** Sometimes two motions both match: a thin object and
  the background behind it, still visible in both real frames. If the flow
  supports the object's motion at both ends, that motion wins because the object
  occludes the background at the midpoint. Otherwise poles and wires vanish.
- **One-sided occlusion fill instead of the current frame.** Background being
  covered or revealed is visible in one real frame only. It is warped from that
  frame alone. A different, self-consistent occluding motion (cycle-consistent
  and photometrically matched) must cover the hidden side, or the hidden side
  must lie off-screen with border flow that agrees. Fabricated flow, scene cuts
  and one-directional flow still fall back.
- **Unexplained content stays intact.** A current pixel with no match in the
  previous frame is kept where the real frame shows it: a new object, or detail
  too thin for the flow grid. Revealed background is excluded. Thin detail found
  in both frames within a pixel is also kept when a background match would erase
  it.
- **Narrow feathering.** The 2-pixel-spaced minimum filter is replaced by
  3x3 neighbourhood support. Isolated confident samples are still removed, but
  fallback now feathers about one pixel instead of cutting blocks.
- Screen-stationary UI protection, alpha preservation, the MEDIUM preset and
  the uncapped presentation policy are unchanged. No FPS cap or VSync is added.
- Fix8 runtime hashes are recognized for managed upgrades.

## Install for the supplied Witcher 3 setup

1. Close the game and extract the complete package into a new folder.
2. The supplied log shows the standalone carrier
   `H:\Games\The Witcher 3\bin\x64_dx12\VERSION.dll`. Replace it with
   `Manual/Version/version.dll` and keep the Fix8 file for rollback. Use
   `SmoothMotion_Manager.exe` instead for a managed installation; ASI installs
   replace `new.asi` from `Manual/ASI_Only/`.
3. Keep the graphics, limiter and VSync settings used for the Fix8 screenshot.
4. The new log must show the Fix9 version above and
   `artifact_guard=occlusion_aware_v2`.
5. Run `Test/ShaderCheck.exe` first. It must report PASS for all five entry
   points (`Fullscreen`, `Capture`, `Project`, `Synthesize`, `Resolve`) with this
   PC's D3DCompiler47.
6. Repeat the same camera pan with F11 off/on. Watch the rooflines, the pole,
   Geralt's outline and quest text. If artifacts remain, keep the fresh log and
   a short recording or screenshot of the same movement.

## Cost and remaining limits

- GPU cost is higher and has not been measured. Regions with uniform motion take
  a fast path: all nearby vectors agree, the match is confident and the current
  pixel moves with the same motion. Counting both full-resolution passes, this
  path uses about 125 texture fetches per pixel. Motion boundaries use about
  310, against about 70 for Fix8. The projection pass runs at 1/16 resolution.
  The extra RGBA32F grid is 2 MiB at 1080p.
- Accuracy is still limited by NVIDIA's 4x4 optical-flow grid, with no depth,
  motion-vector or UI buffers from the game. The following can still show at
  most a small displacement, a brief ghost or a one-pixel fringe: detail thinner
  than a flow block with no usable vector, heavy flow noise, transparency,
  particles and animated UI.
- Content without any correspondence is shown at its current position, so it
  is not interpolated and may judder at the base frame rate.
- Immediate back-to-back generated submissions may still be displayed unevenly
  on a 60 Hz display. `interpolation_verified` remains false.

## Validation

Production HLSL bodies run on the existing CPU texture model, in optimized and
ASan/UBSan builds. Thirteen behavior groups pass. New groups cover four parallax
occlusion cases with block-quantized flow and a thin crossing pole. Fix8 fails
both new groups: 791–1515 bad pixels of 13,824 per parallax case, and 0/184
visible pole pixels. Fix9 has 164–395 bad pixels and 184/184 visible pixels.
Two existing groups were tightened to exact midpoint expectations: screen
borders, and the area beside a newly appearing object. All five entry points
compile with glslang (HLSL to SPIR-V). They also compile with Microsoft DXC in
strict mode for both HLSL 2016 and 2021. D3DCompiler47/DXBC compilation on
Windows is not run here; use `Test/ShaderCheck.exe`. See `VALIDATION.md` and
`validation/fix9-review.json`.
