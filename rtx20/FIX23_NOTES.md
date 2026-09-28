# Fix 23 — fewer retry drops, no SLOW-flow hitches, games that were never hooked

Runtime version: `2.8.4-rtx20-rtx30-dx12-preview2-fix23-test`.

Everything in Fix22 is kept. This is a test build: it has not run on
Windows or a GPU here.

## 1. God of War (RTX 2060): "still drops FPS occasionally, then smooth again"

**Log `nvsmooth30_49.log` (Fix22).** The freezes are gone. Shaders were
compiled on the worker thread in 24.9 s while the game loaded.

What remains:

- The guard paused generation at 34 real / 67 displayed against 79 native.
  It then retried after 30, 60, 120 and 240 s.
- Every retry generated for about 3 seconds at about 30 real FPS before
  pausing again. Those are the drops you saw.
- Generation costs this card about 17 ms per real frame in this game (half
  resolution flow, 10-bit backbuffer), so it cannot win at 70–80 FPS native.

**Change: predictive retries.**

- At each pause, the guard stores how much time generation added per real
  frame: 1/real − 1/native, measured, not estimated.
- While paused it keeps measuring the game's own rate. At retry time it
  predicts the result from that rate and the stored cost:

  | Native rate | Predicted real | Predicted displayed | Needed displayed | Minimum real (65%) | Decision |
  |---|---|---|---|---|---|
  | 79 FPS | 34 | 68 | 87 | 51 | Retry skipped, silently |

- A retry that is predicted to win (for example a much heavier scene, or a
  cheaper game) happens at once.
- A real attempt still happens at least every 300 s, in case the cost
  changed.
- The log shows `guard: retry skipped (...)` with the prediction.

## 2. Monster Hunter World (RTX 2080, `nvsmooth30_51.log`, Fix21)

Generation worked, 30 to 60, with no guard pauses. It had two sources of
periodic hitches:

- **SLOW flow chosen with an unknown frame interval.**
  - Right after a session rebuild, the log showed `budget 0.0 ms`: the
    unknown interval read as an unlimited budget.
  - SLOW flow was chosen for a few pairs, at 13–15 ms each.
  - Fix: the game's rate stands in until the interval is measured.
- **Re-measuring rejected flow modes every 30 s.**
  - Each re-measurement ran 4 expensive pairs.
  - Now a mode far over budget (twice the limit) is rejected after 2 pairs.
  - Each failed re-measurement doubles the wait: 30 s, 60 s, up to 300 s.
- The 5.8 s freezes at session rebuilds in that log were fixed in Fix22.

## 3. RTX 3060 Ti: "doesn't work in any game" (`nvsmooth30_50.log`, Far Cry New Dawn, Fix21)

The log shows `initialization_status: not_initialized` and
`graphics_entries: 0`. The game created its device through a path the
import hooks never saw, so no swapchain was hooked and nothing ran. This is
typical for protected or repacked executables.

**New: Present-table probe.**

- If no game swapchain appeared 4 s after `dxgi.dll` loaded, the mod creates
  a hidden 64x64 swapchain once.
- That swapchain reveals DXGI's swapchain function tables and hooks them,
  the way overlays find them.
- The game's swapchains share those tables, and they are adopted at their
  first Present.
- The log shows `Present-table probe: ...`.
- `PresentTableProbe=0` in `nvsmooth30.ini` turns it off.

If a game still does nothing, please send the new log.

## 4. Red Dead Redemption 2: "doesn't open, no log"

**No log.** Games under `Program Files` cannot write beside the exe. The log
now falls back to `%LOCALAPPDATA%\SmoothMotion\<exe name>-nvsmooth30.log`,
with a note at the top of the file.

**Not opening.** There is not enough information to fix this yet. Please
check:

- the game uses its **DirectX 12** renderer, not Vulkan (Vulkan is
  unsupported);
- trying the ASI/Dinput8 kit instead of `version.dll`.

Then send the log from the fallback folder.

## 5. Witcher 3: sword hilts and hair smeared over a fast sky

**Reproduced.** I built a Witcher-like scene: a nearly screen-fixed
character with thin sword hilts and hair strands over bright clouds that
move 20–40 px per frame. Motion came from real optical flow (OpenCV DIS) at
4-pixel and half-resolution cells. The output showed the same kind of
damage: hilts partly painted over with sky, and pale sword-shaped copies
beside them.

**Cause.** The hilts are thinner than a flow cell, so they carry the sky's
motion. The synthesis then found a confident "sky at both ends" match
across them.

**Changes:**

- A one-sided (occlusion) fill no longer takes a sample that is static
  detail in both frames. Such detail did not move, so it cannot be at the
  pixel.
- Content identical in both frames (up to a one-pixel shift) that sits
  beside its own static outline is kept when the only alternative is the
  background moving along the pan. A crossing object can still pass over it.

**Result.**

| Measure | Fix22 | Fix23 |
|---|---|---|
| Erased hilt/hair pixels (synthetic scene) | 2,274 | 1,878 (−17%) |
| Wrong pixels, real Witcher frames (Fix21 method) | 13,213 | 13,237 |

The change on the real Witcher frames is within noise. `FIX23_SWORD.png`
compares them.

**Limits.** This is an improvement, not a cure. Pale copies remain around
the hilt tips. The UI/minimap area over motion is also not solved. A short
recording of that scene (both the real and the generated frames, like the
Test2 recording) would allow a real-frame benchmark for it.

## Tests

- Policy tests:
  - Genshin model: the retry after a pause is skipped when it is predicted
    to lose, and a real attempt is still made within 300 s.
  - Prediction with a cheaper pair: it wins at 100 native and loses at 140
    on 144 Hz.
  - The rebuilt-pause case from Fix22.
  - Flow budget: a mode far over budget is rejected after 2 pairs, the
    re-measure wait doubles, and a mode within budget resets it.
- All 22 shader behaviour groups pass unchanged.
- The package verifier and all host tests pass (optimized and ASan/UBSan).
- The probe swapchain and the log fallback are Windows-only paths that did
  not run here.
