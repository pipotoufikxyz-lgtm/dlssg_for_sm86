# SmoothMotion RTX20 builds (Turing / RTX 20-series)

## Fix 14 — smooth presentation, quality and glass UI test (current)

`SmoothMotion-2.8.4-RTX20-DX12-Preview2-Fix14-Smooth-Test.zip`: everything in
Fix13, plus:

- each generated frame shown for half a real-frame interval before the real
  frame, so 30 to 60 looks like 60 (timed or pipelined, chosen automatically);
- about half the artifacts of Fix13 in simulation: validated occlusion fill,
  exposure gain model, thin objects and lines over flat background, sharp
  resampling, and the SLOW optical-flow preset below 40 FPS;
- a liquid-glass Manager interface.

Files:

- `FIX14_NOTES.md`: log 38 and video analysis, changes, settings, limits.
- `UI_FIX14_PREVIEW.png`: Manager before and after (rendered under Wine).
- `nvsmooth30.example.ini`: `Pacing=auto|low_latency|smooth|vblank|off`,
  `FlowQuality=auto|high|medium`.
- `DX12-Preview2-Fix14.patch`: source and document difference from Fix13.

## Fix 13 — pacing and performance test (previous)

`SmoothMotion-2.8.4-RTX20-DX12-Preview2-Fix13-Pacing-Test.zip`: everything in
Fix12, plus:

- generated and real frames shown on consecutive refreshes instead of back to
  back;
- generation paused while the game already reaches the display refresh rate;
- a synthesis pass with about 35% fewer texture fetches per pixel.

Files:

- `FIX13_NOTES.md`: why log 37 did not feel smoother, changes, settings, limits.
- `nvsmooth30.example.ini`: adds `Pacing=on|off` and `GenerateAboveRefresh=0|1`.
- `DX12-Preview2-Fix13.patch`: source and document difference from Fix12.

## Fix 12 — quality test (previous)

`SmoothMotion-2.8.4-RTX20-DX12-Preview2-Fix12-Quality-Test.zip`: everything in
Fix11 plus exposure-compensated matching (auto-exposure, flicker, moving
shadows), exposure-corrected occlusion fill and a stricter thin-object test.

- `FIX12_NOTES.md`: what was still wrong, changes, simulation results, limits.
- `DX12-Preview2-Fix12.patch`: source and document difference from Fix11.

## Fix 11 — frame-generation performance test (previous)

`SmoothMotion-2.8.4-RTX20-DX12-Preview2-Fix11-Performance-Test.zip`: all Fix10
artifact changes plus adaptive half-resolution optical flow (automatic at 58+
real FPS) and per-stage GPU timing in the log.

- `FIX11_NOTES.md`: Blackwood/RE3 log analysis, changes, install and limits.
- `nvsmooth30.example.ini`: optional `FlowResolution=auto|full|half` setting.
- `DX12-Preview2-Fix11.patch`: source and document difference from Fix10.

## Fix 10 — fast-pan and HUD artifact test (previous)

`SmoothMotion-2.8.4-RTX20-DX12-Preview2-Fix10-Motion-HUD-Test.zip` is the complete
rebuilt package (runtime carriers, Manager, installer, tests, source, symbols).

- `FIX10_NOTES.md`: what the Fix9 recording showed (30 FPS base, 60–100 px pans,
  pole-top breakup, erased HUD text), the changes, install steps and limits.
- `DX12-Preview2-Fix10.patch`: source and document difference from Fix9.

## Fix 9 — occlusion-aware synthesis test (previous, kept for rollback)

- `SmoothMotion-2.8.4-RTX20-DX12-Preview2-Fix9-Occlusion-Test.zip`, `FIX9_NOTES.md`,
  `DX12-Preview2-Fix9.patch` (difference from the supplied Fix8 package).

`.sha256` files hold the ZIP checksums. Windows/GPU execution and in-game image
quality are verified only by your own testing: run `Test/ShaderCheck.exe` (five
PASS lines), then compare F11 off/on in the same scene.
