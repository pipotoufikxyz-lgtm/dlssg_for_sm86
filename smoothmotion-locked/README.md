# SmoothMotion 2.8.5 Fix28 qua2 + locked 2x pacing (`fix28-qua2-lock`)

This build adds a presentation mode, `Pacing=locked`, that always presents
exactly one generated frame per real frame, with every frame on screen for
the same time. It also fixes a Vulkan frame-order bug and makes Vulkan
games use the same locked pacing.

- Runtime version: `2.8.5-rtx20-rtx30-dx12-preview2-fix28-qua2-lock`
- Synthesis shader: the `fix28-qua2` shader from `smoothmotion-quality/`
  (`artifact_guard=occlusion_aware_v14`), unchanged.
- Built from the Fix28 source in this repository's history
  (`rtx20/SmoothMotion-2.8.5-RTX20-RTX30-DX12-Preview2-Fix28-Test.zip`) with
  LLVM-MinGW 20250924 (clang 21.1.2), the same compiler as Fix28.

> **Not tested on Windows with an NVIDIA GPU.** Host tests and a Vulkan run
> on Mesa lavapipe pass (see "What was tested"). Please send
> `nvsmooth30.log` after a session either way.

## What "always 2x" means here

Displayed frames = 2 × the game's real frames, on every frame. It does not
mean 2 × the frame rate the game had without generation. Generation costs
GPU time (optical flow + synthesis), and locked pacing holds the game at
half the refresh rate:

| Display | Game (real) | Shown |
|---|---|---|
| 60 Hz | 30 | 60 |
| 120 Hz | 60 | 120 |
| 144 Hz | 72 | 144 |
| 165 Hz | 82.5 | 165 |

The game must be able to hold that rate **with generation running**. If it
cannot, a frame misses its refresh and the display repeats one: a stutter.
The log counts these (`locked_late_frames`). Then:

1. set `LockedBaseRate=quarter` (DXGI games: 36 real / 72 shown at 144 Hz,
   every frame two refreshes), or
2. lower the Windows refresh rate (for example 144 Hz → 120 Hz or 60 Hz), or
3. lower the game's settings, or set `FlowResolution=half`.

## Why Fix28/qua2 was not always 2x

Measured against the Fix28 source, these paths lowered the rate or broke
the cadence:

| Cause in Fix28 | Effect | Locked mode |
|---|---|---|
| Cost guard (`MinimumBaseRate`, +10% displayed rule) | generation paused for 30–300 s, retries cost seconds of low FPS | off |
| Refresh-rate pause (real rate ≥ refresh) | generation off at high frame rates | off: the game is held at refresh/2 |
| Native + measuring phases after every reset (resize, F11, a rejected Present, any gap > 250 ms) | 0.5 s with no generation, then 0.75 s of unspaced pairs (generated frame barely visible) | none: generation resumes on the next frame |
| CPU spacing controller (`auto`/`low_latency`) | the wait shrinks whenever it slows the game, so spacing drifts between 0 and half a frame | not used: the display's refreshes space the frames |
| `DO_NOT_WAIT` generated Present | generated frame dropped when the queue is full | VSync Present, never dropped |
| Automatic flow switching (SLOW/MEDIUM by FPS, half resolution by budget, re-measured every 30–300 s) | cost per pair jumps; each re-measurement was a hitch (Fix23 notes) | one mode for the session (full/MEDIUM unless set) |
| A frame without a pair (first after a reset) | shown immediately with the game's own interval | held for both slots: the cadence is unchanged |

## Vulkan

Vulkan support comes from Fix28 (`Vulkan=1`, the module registers itself as
a Vulkan layer for the game's process). The qua2 binaries already had it.
This build changes three things for Vulkan:

- **Locked pacing on Vulkan.** Generating swapchains are created with FIFO
  (VSync, always supported) whatever the game asked for. MAILBOX replaced
  the generated image before it was shown; IMMEDIATE showed it for a
  fraction of a refresh. The log shows `[vulkan] Pacing=locked: present
  mode N replaced by FIFO`.
- **The generated image's acquire stays blocking** (25 ms bound). Fix28
  switched to a nonblocking acquire for the rest of the session after three
  timeouts in a row, and then dropped generated frames whenever no image was
  free.
- **Frame-order bug fixed** (any Pacing). The Vulkan bridge always presents
  the game's current image after the generated one; it cannot restore the
  previous real frame. With `Pacing=smooth`, or `auto` after it learned the
  pipelined order on a MAILBOX/IMMEDIATE swapchain, the pipelined order then
  showed frame N, the pair (N−2, N−1), then N+1: a step backwards on every
  frame. The pipelined order is now off for Vulkan swapchains.

`LockedBaseRate=quarter` does not apply to Vulkan (FIFO has no per-present
interval); Vulkan always runs at half the refresh.

Unchanged from Fix28: the module must load before the game creates its
Vulkan instance (`version.dll` or an ASI loader), and the game must not run
as administrator.

## Known limits

- **Latency.** VSync pairs queue frames. Expect roughly one to two refreshes
  more latency than Fix28's `auto`. `Pacing=auto` restores Fix28 behaviour.
- **G-Sync/FreeSync.** With VRR, VSync presents are not held to the
  refresh: the generated frame is shown for one maximum-refresh interval,
  the real frame for the rest. It is even only while the game holds half the
  maximum refresh. Below that, use a lower refresh rate in Windows (so half
  of it is reachable) or `LockedBaseRate=quarter` with VRR off.
- **Games with their own interval 3** (20 FPS lock at 60 Hz) keep a 1:2
  cadence, as in Fix28.
- **GPU cost is unchanged.** Locked pacing does not make generation cheaper;
  qua2's synthesis is heavier than Fix28's (more texture reads).
- **qua2 shader vs Fix28's own CPU regression test.** Running Fix28's
  `source/rtx20/test_shader.py` on the qua2 shader fails 7 of its checks that
  Fix28's shader passes, for example "overlay text intact" 1032/1104
  (93.5%) where 98% is required (Fix28: 1086/1104), plus checks on
  translucent crosshairs, doubled edges and object fragments. qua2 is better
  on the parallax cases of the same test. This is a property of the qua2
  shader, not of this pacing change; see the summary in "What was tested".
  To build with Fix28's shader instead, see "Rebuild".

## Install

Same as qua2. Close the game, keep copies of the files you replace.

- **ASI loader route:** replace the game's `new.asi` with `bin/new.asi`.
- **Standalone route:** replace the game's `version.dll` with
  `bin/version.dll`.
- Optional: copy `nvsmooth30.ini` beside the game executable. Without it,
  `Pacing=locked` and `LockedBaseRate=half` are the defaults.
- The first start compiles the shaders (10–30 s pass-through); later starts
  use the cache.

| File | SHA-256 |
|---|---|
| `bin/new.asi` | `c4d34ba372916f81cc7221efd64afd09ff4a5df9ba9e845c4bf207a93960c654` |
| `bin/version.dll` | `48a8f771818235d05ee27b2053653996146f2abc268f8e557e72e49d1df53f06` |

The Fix28 Manager and `Install.exe` check Fix28's hashes and will not
install these files; copy them by hand.

## Check it in the log

`nvsmooth30.log` should show:

```
[rtx20] Pacing=locked: flow fixed at resolution=full quality=medium for the session (no automatic switching); GPU budget not used.
[rtx20] presentation: display 144 Hz; Pacing=locked: always 2x, generated and real frame 1 refresh(es) each, game held at 72.0 real FPS (LockedBaseRate=half), 144.0 displayed; never paused, no cost guard.
[rtx20] presentation=locked at ... real FPS, 144 Hz display; locked 2x: generated and real frame on refreshes of their own, every frame.
```

Runtime status fields (in `performance_gpu_us`):

- `locked_pairs`: generated + real pairs presented.
- `locked_held_frames`: real frames without a pair, held for both slots
  (one per reset; should stay small).
- `locked_late_frames`: real frames that took more than 1.5× their refreshes.
  **This is the stutter counter.** If it keeps rising during play, the game
  cannot hold the locked rate: see the options at the top.
- `guard_pauses` and `generation_paused_frames` stay 0.

## What was tested

- **Build:** `normal.asi` and `version.dll` cross-compiled without warnings.
- **Host tests (Fix28 suite, 21 suites × optimized and ASan/UBSan):** 42/42
  PASS, including new policy tests: locked state from the first frame and
  after every reset; never paused at 300 FPS or at 20 FPS; VSync pairs for
  tearing games (flag removed, generated Present blocking); held frames take
  both slots without a restore; quarter intervals 2+2; late-frame rule.
- **Vulkan layer on Mesa lavapipe with the Khronos validation layer:** 8/8
  PASS, including two new cases: IMMEDIATE replaced by FIFO, FIFO kept;
  118/120 generated presents (the first frames have no pair). The 2026
  validation layer also reports the test app's own swapchain-semaphore reuse
  with no layer loaded (14 errors for the IMMEDIATE case without the layer,
  10 with the layer in locked mode, 12 in other modes). The test now
  requires the layer to add no error to that baseline.
- **Not run:** Windows, NVIDIA optical flow, real displays, the D3D11/D3D12
  smoke tests, `verify.py` (it requires Fix28's shader regression to pass,
  which the qua2 shader does not).

## Rebuild

From the Fix28 package root (`rtx20/SmoothMotion-2.8.5-RTX20-RTX30-DX12-Preview2-Fix28-Test.zip`):

```sh
patch -p1 < source/fix28-to-lock.patch        # this folder's patch
cp <repo>/smoothmotion-quality/shader/shaders.hlsl source/rtx20/shaders.hlsl
python3 source/rtx20/build.py --cxx /path/to/llvm-mingw-20250924-ucrt/bin/x86_64-w64-mingw32-clang++
python3 source/rtx20/test.py
python3 source/rtx20/test_vulkan.py            # needs mesa-vulkan-drivers + vulkan-validationlayers
```

Skip the `cp` line to build with Fix28's own shader. The binaries are in
`payload/native/` (`normal.asi` is `new.asi`).

## Files

- `bin/new.asi`, `bin/version.dll`: the build.
- `nvsmooth30.ini`: settings with comments.
- `source/fix28-to-lock.patch`: all source changes against Fix28.
- `source/build-report.json`: compiler, artifact hashes and source hashes.
