# Fix 22 — no more freezes and repeated FPS drops (God of War, RTX 2060)

Runtime version: `2.8.4-rtx20-rtx30-dx12-preview2-fix22-test`.

Everything in Fix21, including the image-quality improvements, is kept. This
is a test build: it has not run on Windows or a GPU here.

## What your log shows

`nvsmooth30_48.log`: Fix20, God of War, RTX 2060, 1080p, 144 Hz, 10-bit
backbuffer.

- **The frame-generation session was rebuilt 20 times in about 10 minutes.**
  - A rebuild follows each swapchain resize or fullscreen change by the game.
    Several of them came back to back.
  - Each rebuild recompiled all shaders on the game's own Present thread,
    which took **6–8 seconds**. The game froze for that long; the longest
    single stall in the log was 7.9 s.
  - In total, 139 s of the session were spent inside this step.
- **Every rebuild forgot the performance guard's decision.**
  - The guard correctly paused generation when it cost too much (for
    example 61 real / 122 shown against 112 native).
  - After the next rebuild, the native rate was measured again and
    generation started again at once. The FPS tanked, the guard paused it,
    and the cycle repeated.
  - That is the "smooth, then tanks again" pattern you saw.

## Changes

1. **Shaders are compiled once per process, on a worker thread.**
   - This starts at the first Present. Frames pass through unchanged for
     the few seconds it takes.
   - Swapchain resizes reuse the compiled shaders. A rebuild now only
     recreates textures and optical-flow sessions (well under a second in
     the log: about 80 ms for three sessions) instead of freezing for
     6–8 s.
   - Log lines: `Compiling shaders on a worker thread` and `Shaders compiled
     in X s`.
2. **The guard's decisions survive rebuilds and discarded frames.**
   - These are kept: the native rate, a running pause with its retry
     backoff (30 s, 60 s, … up to 300 s), and the measured GPU cost per
     flow mode.
   - A paused session stays paused until its retry time. After a rebuild the
     log says `Session rebuilt (swapchain resize); the guard's pause
     continues for N s`.

## What to expect on an RTX 2060 in God of War

- Uncapped at 75–112 FPS native, generation costs this card about as much as
  it gains. The guard will often pause it, and the game then runs at native
  rate with no stutter.
- For steady generation, cap the game (RTSS, which you already have, or the
  NVIDIA control panel) at a rate your card holds with headroom. For example,
  60 FPS gives 120 shown on your 144 Hz display.

## Tests

- New policy test:
  - After a guard pause, a rebuild keeps the pause, its retry time and its
    backoff.
  - The pause ends only when it expires.
  - A generating session still measures again after a rebuild.
- All shader groups (22), host tests (optimized and ASan/UBSan) and package
  verification pass. All HLSL entry points compile with glslang 15.1.0.
- The worker-thread compile and the rebuild timing need your PC to confirm.

## Install

Replace the previous file with `Manual/Version/version.dll` or
`Manual/ASI_Only/new.asi`, or use the Manager. It recognizes exact Fix20 and
Fix21 binaries. The log must show the version above.
