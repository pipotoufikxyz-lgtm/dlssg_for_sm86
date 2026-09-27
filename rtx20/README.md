# SmoothMotion RTX20/RTX30 builds (Turing and Ampere)

## Fix 22 — no freezes on swapchain resizes (current)

`SmoothMotion-2.8.4-RTX20-RTX30-DX12-Preview2-Fix22-Test.zip`: everything in
Fix21. `nvsmooth30_48.log` (God of War, RTX 2060) showed 20 session rebuilds.
Each recompiled the shaders on the game thread for 6–8 s (freezes). Each also
forgot the guard's pause, so generation restarted and the FPS tanked again.
Shaders are now compiled once on a worker thread, and the guard's pause and
backoff survive rebuilds.

- `FIX22_NOTES.md`: log analysis, changes, what to expect on an RTX 2060.
- `DX12-Preview2-Fix22.patch`: source and document difference from Fix21.

## Fix 21 — image quality: less ghosting (previous)

`SmoothMotion-2.8.4-RTX20-RTX30-DX12-Preview2-Fix21-Test.zip`: everything in
Fix20, with better generated frames on RTX 30 and RTX 20 (same synthesis).
Measured on real Witcher 3 frames against the real in-between frame, wrong
pixels went from 17,267 to 13,213 (roofs and chimney −86%). Mean PSNR rose
from 29.70 to 30.30 dB. Thin objects over flat sky no longer vanish or
flicker, and unexplained pixels follow the motion instead of ghosting ahead.

- `FIX21_NOTES.md`: method, results per crop, changes, limits.
- `FIX21_COMPARE.png`: truth / Fix20 / Fix21, with wrong pixels in red.
- `DX12-Preview2-Fix21.patch`: source and document difference from Fix20.

## Fix 20 — GPU-bound games (previous)

`SmoothMotion-2.8.4-RTX20-RTX30-DX12-Preview2-Fix20-Test.zip`: everything in
Fix19. `nvsmooth30_46.log` (God of War, RTX 2060, uncapped 70 FPS) showed the
real rate halving to 35-45 while generating: the DX11 wait for the generated
frame's visibility drained the GPU every frame. That wait is now skipped
while GPU-bound, and generation pauses below 65% of the native rate
(`MinimumBaseRate`).

- `FIX20_NOTES.md`: log analysis, changes, what to expect, capping advice.
- `nvsmooth30.example.ini`: adds `MinimumBaseRate`.
- `DX12-Preview2-Fix20.patch`: source and document difference from Fix19.

## Fix 19 — steady crosshairs and HUD (previous)

`SmoothMotion-2.8.4-RTX20-RTX30-DX12-Preview2-Fix19-Test.zip`: everything in
Fix18, plus a full-frame static overlay mask (opaque and translucent HUD
detail). The scene behind a crosshair is taken from the other frame instead
of pasting misplaced blocks around it during pans (Assassin's Creed Origins
recording). Fast-pan test: misplaced pixels 480 -> 101; translucent
crosshairs no longer vanish.

- `FIX19_NOTES.md`: recording, cause, changes, results table, limits.
- `DX12-Preview2-Fix19.patch`: source and document difference from Fix18.

## Fix 18 — RTX 30 support (previous)

`SmoothMotion-2.8.4-RTX20-RTX30-DX12-Preview2-Fix18-Test.zip`: everything in
Fix17, and the same NVOF + synthesis backend now also runs on RTX 30 (Ampere
SM86). For RTX 30 it replaces GP9 (2.8.2 R3 GP9 Fixes1), which ran NVIDIA's
closed driver model through patches; the Manager replaces owned GP9 installs.

- `FIX18_NOTES.md`: differences from GP9, install, what to expect.
- `DX12-Preview2-Fix18.patch`: source and document difference from Fix17.

## Fix 17 — performance guard and stutter fix (previous)

`SmoothMotion-2.8.4-RTX20-DX12-Preview2-Fix17-Test.zip`: everything in Fix16,
plus a guard that never lets generation lower the displayed frame rate.
`nvsmooth30_45.log` (Genshin Impact, RTX 2070 Max-Q) showed native ~120 FPS
falling to 12–35 while generating, and 100 ms waits from a reference measured
across loading hitches. The native rate is now measured first, generation
pauses when it loses (retrying with growing delays), and measurements use
hitch-proof medians.

- `FIX17_NOTES.md`: log analysis, changes, policy-model results, limits.
- `DX12-Preview2-Fix17.patch`: source and document difference from Fix16.

## Fix 16 — 10-bit SDR games (previous)

`SmoothMotion-2.8.4-RTX20-DX12-Preview2-Fix16-Test.zip`: everything in Fix15,
plus RGB10A2 backbuffers. God of War (2018) uses one in SDR; Fix15 and
earlier disabled the session there (`nvsmooth30_44.log`: `format=24`).
Synthesis reads full-precision 10-bit frame copies, so generated frames do
not band.

- `FIX16_NOTES.md`: log analysis, change, checks, limits.
- `DX12-Preview2-Fix16.patch`: source and document difference from Fix15.

## Fix 15 — roofline slivers, GPU budget and older DX11 games (previous)

`SmoothMotion-2.8.4-RTX20-DX12-Preview2-Fix15-Test.zip`: everything in Fix14,
plus:

- no slivers of the next frame's roof or wall edge in the sky ahead of a
  moving edge (Witcher 3 recording, RTX 2080). The HUD protection no longer
  mistakes flat sky beside a new edge for text, and flat, matching pixels
  are filled instead of falling back to the next frame;
- a GPU budget (`GpuBudget`, default 10% of the real frame time) choosing
  SLOW, MEDIUM or half-resolution optical flow by measured cost. Fix14's
  automatic SLOW preset cost about 5.7 ms per generated frame in the user
  log. Flat areas now also take a cheaper synthesis path (12–39% fewer
  texture reads on the recorded frames, in the shader model);
- DX11 games using sync interval 2–4 (30 FPS locks), exclusive fullscreen
  (`ExclusiveFullscreen=1`, default) or multisampled backbuffers are
  interpolated instead of passed through;
- `Test/Test_DX11_Legacy_MSAA.cmd`, a DX11 hardware test of those paths.

Files:

- `FIX15_NOTES.md`: recording and log analysis, changes, settings, limits.
- `nvsmooth30.example.ini`: adds `GpuBudget` and `ExclusiveFullscreen`.
- `DX12-Preview2-Fix15.patch`: source and document difference from Fix14.

## Fix 14 — smooth presentation, quality and glass UI test (previous)

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
quality are verified only by your own testing: run `Test/ShaderCheck.exe` (seven
PASS lines in Fix15, five before), then compare F11 off/on in the same scene.
