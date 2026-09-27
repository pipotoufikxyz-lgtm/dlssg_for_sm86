# Fix 13 — pacing and performance test

Runtime version: `2.8.4-rtx20-dx12-preview2-fix13-pacing-test`.

Fix12 raised the frame counter but, in Blackwood, did not feel smoother. This
build changes when and how generated frames are presented, and makes the
synthesis shader cheaper. All Fix12 quality changes are kept. It is a test
build: Windows/GPU execution and displayed cadence are still unverified.

## Why it did not feel smoother (`nvsmooth30_37.log`)

- RTX 2070 SUPER, 1920x1200, **92 Hz** display. Blackwood presents with
  tearing (`sync=0 flags=ALLOW_TEARING`).
- With F11 off the game ran at about 117 FPS. That is **already above the
  92 Hz refresh**, so the display can show at most 92 distinct images per
  second. Every generated frame took GPU time (flow about 1.4 ms, synthesis
  about 1.7 ms per pair) and lowered the real rate to 98–108 FPS. None of it
  could appear as extra smoothness.
- Below the refresh rate there was a second problem. The generated frame and
  the real frame were presented **back to back**, a fraction of a millisecond
  apart. The display then shows the generated frame for almost no time, or a
  torn slice of it, and the real frame for the rest. The counter doubles but
  the motion stays uneven.

## Changes

- **Pause at or above the refresh rate.** After a short measurement
  (0.75 s and at least 20 frames), generation pauses while the real frame rate
  is at or above the display refresh rate. The game then runs at its native
  frame rate with no frame-generation cost. Generation resumes when the native
  rate drops below 90% of the refresh rate. In the Blackwood scene above, that
  means about 117 FPS native instead of 98–108 with invisible extra frames.
- **Even frame pacing (paired refresh).** Below the refresh rate, the generated
  frame and the real frame after it are both presented with sync interval 1
  (the tearing flag is removed for the pair). Each is shown for one full
  refresh, so motion advances evenly at the display rate. This holds the game
  at half the refresh rate: 30 real + 30 generated on 60 Hz, 46 + 46 on 92 Hz,
  72 + 72 on 144 Hz.
- **Cheaper synthesis.**
  - The expensive candidate ranking now runs only where the neighbouring
    vectors disagree.
  - The HUD-overlay check runs only on pixels that are identical in both
    frames.
  - The fast path tries a zero exposure shift before estimating one.
  - Distant second motions no longer block the fast path in zooms and
    rotations.

  Counted texture fetches per pixel in the synthesis pass fall from 244 to 159
  (−35%) with full-resolution flow, and from 250 to 166 with half-resolution
  flow. Output is identical to Fix12 in the full-resolution simulation (1413 bad
  pixels clean, 1927 noisy). Half-resolution flow is 3% worse on the line-grid
  scene only.
- Fix12 runtime hashes are recognized for managed upgrades.

## Settings (`nvsmooth30.ini`, `[RTX20]`, or environment variables)

| Key | Environment | Default | Meaning |
|---|---|---|---|
| `Pacing` | `SM86_PACING` | `on` | `off` presents both frames immediately (Fix12 behaviour: higher counter, uneven cadence, no half-refresh cap) |
| `GenerateAboveRefresh` | `SM86_GENERATE_ABOVE_REFRESH` | `0` | `1` keeps generating when the game already reaches the refresh rate |
| `FlowResolution` | `SM86_FLOW_RESOLUTION` | `auto` | Unchanged from Fix11 |

Copy `nvsmooth30.example.ini` beside the game executable as `nvsmooth30.ini`.

## What to expect

- **Blackwood (117 FPS native, 92 Hz):** generation pauses and the log shows
  `presentation=paused`. You get the full native frame rate. Frame generation
  cannot make a game smoother than the display refresh rate.
- **A game at 125 FPS on a display of 120 Hz or less** (for example the 125 to
  200 case): generation also pauses. On a 144 Hz or faster display it keeps
  generating, paced at half the refresh rate.
- **Witcher 3 at 30 FPS on 60 Hz:** unchanged frame rate. Generated and real
  frames now alternate on consecutive refreshes instead of arriving together.
- On a VRR (G-SYNC) display, pacing uses the maximum refresh rate.

## Install and check

1. Close the game. Replace the Fix12 file with `Manual/Version/version.dll`
   (standalone), `Manual/ASI_Only/new.asi` (ASI) or use the Manager.
2. The log must show the version above, then a line starting
   `[rtx20] presentation: display NN Hz`, then after about one second
   `presentation=paced`, `presentation=paused` or `presentation=immediate`.
3. The status line reports `paced_pairs` and `generation_paused_frames`.
4. Compare F11 on/off in the same scene. With pacing, the displayed frame rate
   (not the game's FPS counter) should be the refresh rate, with even motion.

## Limits

- Paced mode holds the game at half the refresh rate, which adds up to about
  one real frame of latency. If a game runs at, say, 100 FPS on a 144 Hz display,
  72 real + 72 generated may feel less responsive than 100 native.
  Try `Pacing=off` or F11 off and choose what you prefer.
- The paced state is kept until F11 is toggled, the window is resized or
  presentation is interrupted. If a scene becomes much lighter than the
  refresh rate during a paced session, generation is not paused automatically.
  Toggle F11 twice to measure again.
- If the game cannot reach half the refresh rate, a real frame stays on screen
  for extra refreshes and cadence becomes uneven again (for example 40 FPS on
  144 Hz). Lower settings or the refresh rate, or use a game limiter at half
  the refresh rate.
- Paced pairs use VSync, so the game's tearing request is not used for them.
- The fetch reduction is counted in the shader model, not measured on a GPU.
  Check `performance_gpu_us` for the actual synthesis time.

## Validation

- **Presentation policy tests:**
  - 30 FPS on 60 Hz → paced;
  - 100 FPS and 92 FPS with generation on 92 Hz → paused;
  - `Pacing=off` → immediate;
  - forced generation, unknown refresh rate and too-short measurements;
  - paced `present_pair` → sync 1 without tearing or DO_NOT_WAIT for both frames.

  These pass in optimized and ASan/UBSan host builds.
- All 17 shader behaviour groups pass unchanged.
- All five entry points compile with glslang, and with DXC strict for HLSL 2016
  and 2021.
- The DX11 and DX12 smoke tests set `SM86_GENERATE_ABOVE_REFRESH=1` (unless
  already set), because their test scene runs far above the refresh rate.
