# SmoothMotion RTX20/RTX30 builds (Turing and Ampere)

## 2.8.5 Fix 28 — Vulkan, and objects that stay whole (current)

`SmoothMotion-2.8.5-RTX20-RTX30-DX12-Preview2-Fix28-Test.zip`: everything in
Fix27, plus:

- **Vulkan games** (e.g. Red Dead Redemption 2 in Vulkan mode).
  - The module registers itself as a Vulkan layer for the game's process only.
    Nothing is installed system-wide or written to the registry.
  - A D3D11 bridge (shared textures and a shared fence) runs the same optical
    flow and synthesis as for DX11/DX12.
  - Requirements: install as usual (`version.dll` or an ASI loader), and do not
    run the game as administrator.
  - `Vulkan=0` turns it off.
  - `Test\RTX20_VulkanLayerTest.exe` checks the Vulkan path on your PC.
- **Fewer fragments in camera turns.** NVIDIA's optical flow drags thin or
  small objects (helmet crests, sword tips, heads) to the camera's motion and
  blends motions across their outlines, so synthesis tore them apart.
  - Two new passes check every flow vector against the frames and replace
    such vectors with a nearby motion that matches.
  - Test of a thin crest over a 20-pixel pan, wrong crest pixels: 252 → 25
    (blended flow), 146 → 56 (dragged flow).
  - `FlowRefine=0` turns it off.
- Details, limits and exactly what was tested: `FIX28_NOTES.md`,
  `FIX28_COMPARE.png`.
- Not run on Windows or a GPU here.

## 2.8.5 Fix 27 — DX12 games adopted at Present, better flow (previous)

`SmoothMotion-2.8.5-RTX20-RTX30-DX12-Preview2-Fix27-Test.zip`: everything in
Fix26, plus:

- **World of Warcraft (DX12) works from the start** (log 63). The game creates
  its swapchain before the hooks can see it; the swapchain was found at its
  first Present but without its command queue, so generation only began after
  switching DX12 → DX11 → DX12. The queue is now taken from the game's own
  command submissions.
- **Better optical flow.** Temporal hints (each pair's search starts from the
  previous pair's vectors, as NVIDIA recommends for video), and the SLOW
  preset up to 55 real FPS when its cost fits the GPU budget (was 40).
- **Other reports** (Tekken 8 crash, Ninja Gaiden 4, Far Cry New Dawn, RDR2
  Vulkan): what the logs show and what to send next is in `FIX27_NOTES.md`.
- Not run on Windows or a GPU here.

## 2.8.5 Fix 26 — fragments around characters, swords, HUD, roofs (previous)

`SmoothMotion-2.8.5-RTX20-RTX30-DX12-Preview2-Fix26-Test.zip`: everything in
Fix25, plus fixes for the Witcher 3 report on Fix24 (RTX 2080, about 30 FPS):
sword pommels and Geralt's face breaking into fragments, HUD labels smeared,
debris along roofs during fast camera turns. RTX 20 and RTX 30 alike.

- **Full-resolution optical flow at low frame rates (the main cause).**
  Synthesis alone used the whole 10% GPU budget, so automatic flow fell to
  half resolution, whose 8-pixel cells are wider than the pommels, hair and
  HUD letters; it saved almost nothing (2.2 ms against SLOW's 2.4 ms per pair
  in the log). `GpuBudget=auto` is now 20%, and half resolution is chosen for
  the budget only when measured clearly cheaper than MEDIUM. `GpuBudget=10`
  restores the old limit.
- **New Coherence pass.** Isolated per-pixel decisions are replaced by their
  neighbourhood's; regions without a majority become a soft patch instead of
  fragments; the bands beside thin objects are filled from the background
  instead of the misplaced current frame.
- **Textured matches count as evidence**, so smooth sky no longer paints over
  thin detail that the flow cannot see.
- Rebuilt from the recording (production shader code on the CPU, a stand-in
  for NVIDIA's flow): with full-resolution flow the pommels, the face and the
  HUD labels stay intact. New regression group: 598 → 428 wrong pixels beside
  a pommel over a fast pan with 8-pixel cells.
- Not run on Windows or a GPU here. Please send `nvsmooth30.log` (look for
  `occlusion_aware_v10` and `flow=high (SLOW)`/`flow=medium` at ~30 FPS).

Files:

- `FIX26_NOTES.md`: causes, changes, measurements, limits.
- `FIX26_COMPARE.png`: in-game Fix24 frames from the recording, Fix25 and
  Fix26 reconstructions at half and full flow resolution.
- `DX12-Preview2-Fix26.patch`: source and document difference from Fix25.

## 2.8.5 Fix 25 — character edges, speed, compatibility (previous)

`SmoothMotion-2.8.5-RTX20-RTX30-DX12-Preview2-Fix25-Test.zip`: everything in
Fix24, plus fixes for the three reports on it (RTX 20 and RTX 30 alike).

- **Fewer artifacts around characters and swords.** Real Monster Hunter World
  frames: wrong pixels −34% in the character region, −39% on its silhouette,
  −22% over the frame. A character with a blade and smeared (NVOF-like)
  flow: 3,973 → 494.
  - Silhouettes are judged against the motion that dominates the window
    around them.
  - Bands the character reveals or covers no longer take its smeared motion.
  - The trailing edge is kept.
- **Faster.**
  - Optical flow runs on a private D3D11 device and worker thread, ordered
    by GPU fences. The game's Present thread no longer waits for it (8.2 ms
    per pair in God of War on an RTX 2060). `AsyncFlow=0` restores the old
    path; setup failures fall back to it automatically.
  - Synthesis reads 13–26% fewer texels.
  - Shaders are cached in `%LOCALAPPDATA%\SmoothMotion\ShaderCache`. Only
    the first start of a new version waits for compilation (41–46 s before).
- **Games that closed.**
  - Anti-cheat and Defender modules are never patched: GameGuard (Helldivers
    2), EasyAntiCheat, BattlEye, XIGNCODE, AhnLab, MpOav/MpClient.
  - Present hook cycles call the swapchain's own Present, read from the DLL
    on disk.
  - Fatal crashes are written to `nvsmooth30.log` with the modules on the
    stack.
- Not run on Windows or a GPU here. The attached Far Cry New Dawn log was
  from 2.8.4 Fix21; please send a Fix25 log (beside the game EXE or in
  `%LOCALAPPDATA%\SmoothMotion`).

Files:

- `FIX25_NOTES.md`: causes, changes, measurements, limits.
- `FIX25_COMPARE.png`: real middle frame / Fix24 / Fix25, wrong pixels in red,
  and the smeared-flow test.
- `DX12-Preview2-Fix25.patch`: source and document difference from Fix24.

## 2.8.5 Fix 24 — image quality (previous)

2.8.5 is Fix24 under a new version number. Fix24 was first published here as
2.8.4 and that ZIP is replaced. Frame generation is unchanged. The Manager
upgrades the 2.8.4 Fix24 binaries, and its sidebar now shows Fix 24 and 2.8.5.

`SmoothMotion-2.8.5-RTX20-RTX30-DX12-Preview2-Fix24-Test.zip`: everything in
Fix23, with better generated frames on RTX 20 and RTX 30. Measured on a new
real-frame benchmark: 47 triplets of real Witcher 3 frames, found
automatically, 120 cases, midpoint-aware metric. Wrong pixels fell 17%
(35,586 → 29,690), and 21% for small motions.

- Soft content (clouds, fog, smooth shading) dissolves instead of jumping
  ahead where no motion validates.
- HUD text over a moving scene stays intact.
- Static thin detail (sword hilts, hair) keeps more of itself.
- Costs about 2–3% more texture reads per pixel.

Files:

- `FIX24_NOTES.md`: benchmark method, results per crop and motion, changes,
  limits.
- `FIX24_COMPARE.png`: real frame / Fix23 / Fix24, wrong pixels in red.
- `DX12-Preview2-Fix24.patch`: source and document difference from Fix23.

## Fix 23 — fewer retry drops, more games hooked

`SmoothMotion-2.8.4-RTX20-RTX30-DX12-Preview2-Fix23-Test.zip`: everything in
Fix22, plus:

- **Predicted guard retries.** From the measured cost per frame, a retry
  that cannot win is skipped (God of War RTX 2060, `nvsmooth30_49.log`: no
  more periodic drops).
- **No periodic SLOW-flow hitches** (Monster Hunter World,
  `nvsmooth30_51.log`).
- **Present-table probe** for games whose device creation is never
  intercepted (RTX 3060 Ti, Far Cry New Dawn, `nvsmooth30_50.log`).
- **Log fallback** to `%LOCALAPPDATA%\SmoothMotion` when the game folder is
  read-only.
- **Better thin detail.** More of a nearly screen-fixed character's sword
  hilts and hair is kept over a fast sky (Witcher 3).

Files:

- `FIX23_NOTES.md`: log analyses, changes, results and limits.
- `FIX23_SWORD.png`: synthetic sword-over-sky scene, real frame / Fix22 /
  Fix23.
- `DX12-Preview2-Fix23.patch`: source and document difference from Fix22.

## Fix 22 — no freezes on swapchain resizes (previous)

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
