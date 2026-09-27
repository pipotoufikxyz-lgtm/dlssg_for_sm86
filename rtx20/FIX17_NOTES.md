# Fix 17 — performance guard and stutter fix (Genshin Impact, RTX 20 laptops)

Runtime version: `2.8.4-rtx20-dx12-preview2-fix17-test`.

Everything in Fix16 is included. This is a test build: nothing here has run on
Windows or a GPU.

## Was the report true?

Yes. `nvsmooth30_45.log` (Fix14, Genshin Impact, RTX 2070 with Max-Q Design,
1080p, 144 Hz, DX11):

- **Native rate.** Without generation (paused or measuring phases) the game
  ran at 119–123 FPS.
- **With generation**, the real rate fell to 12–35 FPS.
  - A pair cost about 17 ms of GPU time: capture about 8.8 ms, flow about
    2.6 ms and synthesis about 6.0 ms on average, with peaks of 44 ms. The
    game's own frame took about 8 ms.
  - Generation therefore could not help. It roughly halved or quartered the
    displayed frame rate.
- **The slowdown fed itself.** The SLOW flow preset is chosen below 40 real
  FPS. Generation pushed the real rate below 40, which selected the slower
  preset.
- **Stutter came from bad measurements.** The spacing reference was an
  average over measurements that included loading hitches (`reference 2.8
  real FPS, wait 100.0 ms`, `reference 7.8, wait 63.9 ms`).
  - Every frame then waited up to 100 ms. The controller only recovered over
    several seconds.
  - This repeated whenever generation paused and resumed (menus, loading,
    rates above 144 Hz).
- **Likely a hybrid laptop.** The Max-Q laptop probably shows the image
  through the integrated GPU. Every Present is then copied across GPUs, and
  generation doubles those copies. This build logs it when it detects that
  case.

Fix15 had already reduced part of this: its GPU budget avoids SLOW when it
does not fit. It did not prevent the overall regression or the stutter.

## Changes

- **The game's own rate is measured first.** Generation stays off for about
  0.5 s at start and after every resume (`presentation=native`, then
  `native rate: N FPS`).
- **Performance guard.** While generating, the displayed rate is checked
  every half second. It is twice the real rate, capped at the refresh.
  - If it is not at least 10% above the native rate for 2 s, generation
    pauses:
    `guard: generation paused; displayed X FPS with it vs Y native`.
  - It retries after 30 s, then 60, 120 and up to 300 s. It retries at once
    if the game becomes much slower by itself (a heavier scene may benefit).
  - A capped 30 FPS game (60 displayed vs 30 native) is never paused.
  - `GenerateAboveRefresh=1` disables the guard.
- **Hitch-proof measurements.** The native, reference and paused-rate
  measurements use the median frame interval. Any gap over 0.1 s (loading,
  shader compilation, alt-tab) restarts them. A reference that turns out
  much too slow is corrected in the next half second, instead of about
  1.5 s per step.
- **Flow presets follow the native rate.** A rate lowered by generation no
  longer selects the slower SLOW preset.
- **Status.** `native_fps` and `guard_pauses` are added.

## Policy model (game-loop simulation)

- **Genshin-like laptop** (native ~118 FPS, pair cost 20 ms, 144 Hz):
  - Fix14: stays generating at ~35 real / 70 displayed.
  - Fix17: pauses after about 2 s, runs at the native ~118 FPS, retries
    after 30 s, pauses again and waits 60 s next.
- **Loading hitch of 2 s during measurement:**
  - Fix14: reference about 2.8 FPS and 100 ms waits.
  - Fix17: reference exactly 30 FPS.
- **Unchanged:**
  - RE3-like capped 30 (pipelined, 30 FPS, even spacing).
  - Light capped 30.
  - low_latency, uncapped GPU-bound, VSync pairs, slowing scene.
  - Refresh pauses.

## What to tell Genshin users

- The log should show `native rate: ~120 FPS`. On that laptop at 144 Hz,
  generation is expected to pause (the `guard:` line), leaving the game at
  its normal rate with no stutter.
- Smooth Motion helps when the game runs well below the refresh rate and
  the GPU has spare time. Examples: a 30–60 FPS cap, or a heavy scene on a
  desktop GPU.
- On this laptop, capping Genshin at 60 FPS may let generation reach
  120 displayed. The guard decides from the measured result.

## Limits

- The guard needs about 3 s after each start or resume (0.5 s native,
  0.75 s measuring, 2 s of checks). A short slowdown remains visible when it
  retries.
- The guard compares frame rates, not latency. Generation still adds about
  half to one real frame of latency where it is kept.
