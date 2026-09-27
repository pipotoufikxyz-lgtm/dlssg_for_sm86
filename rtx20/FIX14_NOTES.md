# Fix 14 — smooth presentation, quality and glass UI test

Runtime version: `2.8.4-rtx20-dx12-preview2-fix14-smooth-test`.

This build changes how generated frames are presented, so that interpolated
30 to 60 FPS looks like 60 FPS. It also reduces artifacts in the synthesis
shader and redesigns the Manager's glass interface. All Fix13 changes are
included. It is a test build: Windows/GPU execution and the displayed cadence
still need verification on your PC.

## Why 30 to 60 felt less smooth than native 60

This was diagnosed from `nvsmooth30_38.log` and the two RE3 demo recordings
(Fix12, RTX 2070 SUPER, 1920x1200, 92 Hz, tearing enabled).

- **The log:**
  - With F11 on, the game ran at exactly 30.0 real and 30.0 generated Presents
    per second, capped at 30. With F11 off it ran at about 59.
  - The generated frame was submitted only about 1 ms before the real frame.
- **The recordings:**
  - In the 30 to 60 video, every second recorded frame is an exact duplicate.
    The frame-to-frame differences alternate 12, 0, 12, 0.
  - The display therefore showed only 30 distinct images per second: each
    generated frame was replaced by the real one almost immediately.
  - The native 60 video has 60 distinct frames.
- **Fix13's VSync pairs would not have fixed this either.** At 30 FPS on
  92 Hz they show the generated frame for one refresh and the real frame for
  two.

## Presentation changes

- **Spaced presentation.** After the generated Present, the runtime waits until
  the generated frame has been visible for half a real-frame interval, then
  presents the real frame. Both frames are then shown for the same time, as at
  native 60. A high-resolution waitable timer plus a short spin is used, so
  the wait does not overshoot by a Windows timer tick.
- **Two orders, chosen automatically (`Pacing=auto`):**
  - **timed:** generated frame, wait, real frame. This has the lowest latency,
    but the game thread waits through flow, synthesis and the spacing.
  - **pipelined:** the previous pair is presented (its generated frame, then
    that real frame), while flow and synthesis for the next pair run on the
    GPU during the wait. This adds one real frame of latency. The generation
    cost leaves the game thread, so even spacing fits at a 30 FPS base.
  - Auto starts timed. It switches to pipelined for the session when timed
    spacing cannot reach 85% of the ideal without lowering the game's frame
    rate.
- **No deliberate frame-rate loss.** Every half second, the real frame
  interval is compared with the interval measured without spacing. When the
  wait exceeds the game's slack, each frame is late by exactly that excess,
  which is removed in one step. The wait then probes upward by 0.25 ms. A
  scene that slows the game down by itself is re-measured.
- **Unchanged from Fix13:**
  - Games presenting with VSync still pair both frames on consecutive
    refreshes, with no CPU wait.
  - Generation still pauses while the real frame rate is at or above the
    display refresh.
- **Game-loop model results** (`policy_test`, RE3-like: capped at 30, about
  11.5 ms of game work per frame, 8.5 ms of flow and synthesis):

| Setting | Base FPS | Generated shown | Real shown | Input to real frame |
|---|---|---|---|---|
| Fix12 (`Pacing=off`) | 30 | ~0 ms | 33 ms | ~21 ms |
| `low_latency` (timed) | 29.7 | 13.0 ms | 20.6 ms | ~34 ms |
| `auto` → pipelined | 30.0 | 16.7 ms | 16.7 ms | ~61 ms |

## Quality changes (synthesis shader, `occlusion_aware_v5`)

- **Validated occlusion fill.** Background revealed or covered by a moving
  object is filled from the one frame that shows it. Several motions often tie
  before the occluder check. Fix13 validated only the first of them, and often
  lost the correct background motion. Every interpretation that could still
  win is now validated.
- **Exposure as a gain.** Auto-exposure, flicker and light changes are
  estimated as a per-channel gain, not an added offset. Near motion boundaries
  the estimate is retried along the best candidate motion. The retried gain
  must halve the match cost before it is accepted.
- **Thin objects.** A wire or pole thinner than half a flow cell owns no flow
  vector at one end. That motion is now accepted when the other end carries
  the background motion and the photometric match is tight. Contradictory
  (corrupted) flow is still rejected.
- **Crossing objects over flat background.** A thin object passing over sky or
  a plain wall left pixels that look unchanged in both real frames, and the
  static-UI protection erased the object at the midpoint. A confident crossing
  now overrides that protection and stray HUD flags nearby. In the new test,
  a line went from 0% to 100% visible.
- **Moving thin detail kept correctly.** Thin detail is kept from the current
  frame only when it is static at the exact pixel. Before, a one-pixel
  tolerance also caught thin objects that were moving.
- **Sharp resampling.** Output colours use a clamped Catmull-Rom filter (12
  taps) instead of bilinear sampling. Half-pixel motion no longer softens
  generated frames relative to real frames. Sharpness measured against the
  true midpoint: 0.97–1.0 (bilinear: 0.79–0.96).
- **Better optical flow at low frame rates.** Below 40 real FPS (at full
  resolution), NVIDIA's SLOW (best-quality) NVOF preset is used, through a
  second session that shares the textures (`FlowQuality=auto|high|medium`). If
  the driver refuses it, MEDIUM is used as before.

Simulation of 13 scenes against the rendered true midpoint (bad pixels > 0.12):

| Flow | Fix13 | Fix14 | Change |
|---|---|---|---|
| Full resolution, clean flow | 1471 | 749 | −49% |
| Full resolution, noisy flow | 1970 | 1095 | −44% |
| Half resolution, clean flow | 3788 | 3121 | −18% |
| Half resolution, noisy flow | 3998 | 3407 | −15% |

By scene:

- exposure +20%: 505 → 25
- brightness +10%: 88 → 37
- thin wire: 195 → 106
- low-contrast line grid: 225 → 131

Midpoint RMSE falls from 0.0300 to 0.0173. Counted fetches per pixel in the
synthesis pass: 137 → 157 in these scenes, which exercise the slow path
heavily.

Test-model note: the CPU shader model used the C library's integer `abs` for
float arguments. Fix12 and Fix13 simulations therefore never executed the
exposure branches. The model now uses a float `abs`, and all Fix13 figures
above were re-measured with it. The GPU shader was never affected.

## Manager interface

- **Liquid glass material.**
  - Panels refract a frosted (pre-blurred) copy of the backdrop, bending it
    more strongly at their thick rounded rim.
  - Lighting comes from the top left: a specular rim on edges facing the
    light, a soft caustic glow inside the opposite edge, and a sheen that
    fades down the panel.
  - A faint grain prevents banding, and panels cast soft floating shadows.
- **Backdrop.** A vivid aurora is built from each theme's colours and the
  chosen accent.
- **Layout.**
  - The active page has an accent indicator.
  - The home card has a motion glyph.
  - Home and Games show a frosted card when the library is empty.
  - The status panel has a one-line version.
- The frosted field is rendered once, and glass surfaces sample it. Surfaces
  are faster to build than Fix13's (about 90 ms for all home-page panels,
  cached).
- High-contrast mode and the simplified (safe) drawing mode are unchanged.

## Settings (`nvsmooth30.ini`, `[RTX20]`, or environment variables)

| Key | Environment | Default | Values |
|---|---|---|---|
| `Pacing` | `SM86_PACING` | `auto` | `auto`, `low_latency`, `smooth`, `vblank` (Fix13), `off` (Fix12) |
| `FlowQuality` | `SM86_FLOW_QUALITY` | `auto` | `auto`, `high`, `medium` |
| `FlowResolution` | `SM86_FLOW_RESOLUTION` | `auto` | `auto`, `full`, `half` |
| `GenerateAboveRefresh` | `SM86_GENERATE_ABOVE_REFRESH` | `0` | `0`, `1` |

`Pacing=on`, Fix13's value, now selects `auto`. Use `Pacing=vblank` for the
Fix13 behaviour.

## Install and check

1. Close the game. Replace the previous file with `Manual/Version/version.dll`
   (standalone) or `Manual/ASI_Only/new.asi` (ASI), or use the Manager.
2. The log must show the version above and `artifact_guard=occlusion_aware_v5`.
3. After about one second the log shows `presentation=timed` or
   `presentation=pipelined`, followed by a `spacing:` line (reference FPS,
   wait, ideal). With a 30 FPS cap, expect pipelined with a wait of about
   16.7 ms. Also look for `flow_quality=high (SLOW)` below 40 FPS.
4. Keep a frame cap (in-game or RTSS) at the base rate you want, for example 30.
   Record 30 to 60 again. Recorded frames should no longer repeat in pairs.
5. If latency feels too high, try `Pacing=low_latency`.

## Limits

- **Latency.** Pipelined presentation adds about one real frame (about 25–30 ms
  at a 30 FPS base) compared with `low_latency`. Timed presentation adds about
  half a real frame.
- **Uncapped, GPU-bound games** have no slack for the wait. The spacing then
  uses the generation time that left the game thread (pipelined), which is
  partial (in the model, 9 of 13 ms at 39 FPS). Cap the game slightly below
  its steady frame rate for even pacing.
- **Fixed refresh rates.** With tearing, spaced frames show tear lines, as
  native 60 does on a 92 Hz display. VRR (G-SYNC) displays show them without
  tearing.
- **Start-up and F11.** The first 0.75 s after enabling F11 or resizing is
  measured unspaced. Entering pipelined order repeats one frame once.
- **SLOW flow preset.** Its GPU time on Turing is not measured here; the
  status line reports `flow_pairs_high_quality`, and `performance_gpu_us`
  shows the cost.
- **UI.** Verified by running the real Manager under Wine (Direct2D,
  DirectWrite with a substitute font). The Windows 11 DWM backdrop path is not
  reproduced there.

## Validation

- **Presentation policy tests** (optimized and ASan/UBSan):
  - game-loop models: capped RE3-like, light, low-latency, uncapped
    GPU-bound, and a scene that slows down;
  - setting names;
  - the refresh gate;
  - pipelined frame order, which never steps backwards, including history
    breaks;
  - scheduled pairs: wait placement, busy queue, restore-only start,
    interrupted and failed restores, VSync pairs.
- **18 shader behaviour groups pass**, one of them new: the thin wire
  (46% → 56% visible), a +25% exposure gain (5086 → 268 bad pixels), a line
  over flat background (0% → 100% visible) and half-pixel sharpness
  (0.79 → 0.97).
- All five entry points compile with glslang, and with DXC strict for HLSL
  2016 and 2021.
- **An independent review of the runtime change** found and led to these
  fixes, all with tests:
  - The DX11 wait for the generated frame's visibility now runs only for
    spaced pairs (it had also stalled unspaced and VSync presentation).
  - A resize that begins during the spacing wait now ends it within about
    2 ms, and the restored frame is not submitted.
  - One hitch no longer cuts the spacing or selects the pipelined order, and
    VSync pairs do not run the controller.
  - A busy or queue pass-through restarts the pipelined order.
  - The pipelined GPU timer starts where the pair is computed.
