# Fix 25 — character edges, faster frame generation, games that closed

Runtime version: `2.8.5-rtx20-rtx30-dx12-preview2-fix25-test`. The log shows
`artifact_guard=occlusion_aware_v9`. RTX 20 and RTX 30 share all changes.
This is a test build: it has not run on Windows or on an NVIDIA GPU here.

The reports behind this build:

- A Monster Hunter World recording: broken fragments and copies around the
  hunter, the sword and the helmet.
- God of War on an RTX 2060: "only about 1.4x instead of nearly 2x".
- An RTX 3060 Ti, driver 617.14: "doesn't work in 10 games" (Helldivers 2 log,
  Far Cry New Dawn log).
- Every log: 41–46 s after starting a game before any frame was generated.

## 1. Artifacts around the character and the sword

### What was wrong

The recording was stepped frame by frame, and the same cases were rebuilt on
real frames. Two causes produced almost all of the artifacts:

- **Silhouettes took the background's side.** At the edge of the hunter, the
  flow between blocks mixes the hunter's motion and the scene's motion. Fix24
  compared "crossing" objects against that mixed motion, so the hunter and
  the scene both counted as crossing. The better colour match then won, and
  that was often the scene, painted over the helmet crest or the blade.
- **Revealed and covered bands used the character's motion.** Optical flow
  (NVIDIA's and every other) smears a moving character's motion one or two
  blocks into the background beside it. In the band the character reveals or
  covers, Fix24 trusted that smeared motion. It pasted misplaced copies of
  the character and the blade beside it, cut off the trailing edge, and kept
  pieces of the next frame there.

### What changed

- **New pass, `DominantMotion`.** For every 8×8 flow cells (32×32 px), it
  finds the motion most of the window moves with (the scene behind the
  character) and the best-supported clearly different one (the character).
  Only motions the flow confirms in both directions count.
- **Crossings and "belongs to the object" tests** use that window motion
  instead of the mixed flow, so only the minority motion (the blade, the
  character) can claim to cross.
- **Revealed/covered bands:**
  - a block vector at the visible end counts only where the other flow
    direction confirms it;
  - the window's motion counts as support where the block vectors are smeared;
  - the surface that dominates the window is preferred for what continues
    behind the character.
- **Smeared silhouettes.** NVOF often smears the character's motion
  symmetrically, in both flow directions, where no consistency test can see
  it. Where the character's own motion fails to match at a pixel, an end that
  carries it no longer counts against the scene's motion. This applies only
  beside a clearly separate second motion.
- **Trailing edge kept.** New content is protected by keeping the current
  frame where nothing explains a pixel. That protection kept revealed
  background over the character's trailing edge when the smeared vectors hid
  it. Fix25 also traces the pixel back along the window's motions.

### Measured

Wrong pixels (lower is better):

| Test | Fix24 | Fix25 |
|---|---|---|
| Real Monster Hunter World frames (8 cases, 2 flow models): whole frame | 120,047 | 94,040 (−22%) |
| Same, character region | 48,032 | 31,629 (−34%) |
| Same, silhouette band | 32,474 | 19,663 (−39%) |
| Synthetic hunter with exact truth (6 cases): whole frame | 57,790 | 37,242 (−36%) |
| Same, character region | 33,148 | 21,116 (−36%) |
| New regression group: character + blade, smeared flow (3 motions) | 3,973 | 494 (−88%) |

How the cases were built:

- **Real frames.** Real frames were taken from the recording, 2 apart, with
  OpenCV DIS flow standing in for NVIDIA's (with and without variational
  refinement). Scoring is midpoint-aware, as in Fix24.
- **Synthetic hunter.** The hunter was cut out of the recording (GrabCut)
  and moved across an inpainted, panning background at 19, 38 and 57 px per
  pair.

`FIX25_COMPARE.png` shows the real middle frame, Fix24 and Fix25 with wrong
pixels in red, plus the new regression scene.

All 24 earlier shader groups still pass their limits, and a 25th group was
added (the smeared-flow character above):

- Parallax bands: bad pixels 193/324/187/259 → 36/8/2/51 per case.
- Half-resolution flow: 479/372/483/522 → 30/37/17/61.
- Static crosshair limits hold (the translucent crosshair's ghost pixels are
  26 of 1,385, limit 27).

## 2. Performance

### Why it was about 1.4x

The God of War log (RTX 2060, 1080p) shows where the time went:

- **The optical-flow call blocked the game.** It held the game's Present
  thread for 8.2 ms per pair (241 calls, 1.97 s), while the flow itself took
  1.35 ms of GPU time. The D3D11 optical-flow interface waits on the CPU until
  the GPU has finished the frame it reads. The game could not prepare its next
  frame meanwhile.
- **Synthesis cost 4.0 ms of GPU time per pair.** In a GPU-bound game, this
  directly lowers the real frame rate.

### What changed

- **Asynchronous optical flow (new; `AsyncFlow=1`, the default).**
  - The flow runs on a private D3D11 device on the same GPU, from its own
    thread. The frames and flow textures are shared with it.
  - Two shared GPU fences order the work: game capture, then flow, then
    synthesis. The Present thread only queues the work and returns.
  - Any setup failure (a driver that cannot share fences or these textures)
    falls back to the Fix24 path. `AsyncFlow=0` forces it.
  - The log says `Asynchronous flow ready` or names the failing step.
- **Cheaper synthesis.** Measured in texture reads per pixel, including the
  new pass:

  | Scene | Fix24 | Fix25 |
  |---|---|---|
  | Real Monster Hunter World frame | 463 | 403 (−13%) |
  | Synthetic pan | 249 | 185 (−26%) |

  - A textured fast path: detailed surfaces whose flow is noisy by a pixel or
    two no longer take the full evaluation. It is guarded against thin
    crossing objects in the same way as the flat fast path.
  - The third step of the midpoint search runs only where the second step
    still moved it.
  - Motions already evaluated are not evaluated twice (bit-identical result).
  - Resolve reads half as much (the overlay count comes from OverlayGrow).

How much of the 2x comes back depends on the game:

- **CPU-bound games,** or games with GPU headroom, gain the most (the 8 ms
  stall is gone).
- **GPU-bound games** still pay the synthesis and flow time on the GPU. For
  example, a game rendering 85 FPS in 11.8 ms on an RTX 2060 cannot reach a
  full 2x.
- **The guard is unchanged.** It still pauses generation when generation
  would lower the displayed rate.

### Start-up: 41–46 s of pass-through (fixed after the first start)

- **Shader cache.** Compiled shaders are cached in
  `%LOCALAPPDATA%\SmoothMotion\ShaderCache`:
  - The cache is keyed by a SHA-256 of the shader source, the entries, the
    flags, the compiler file and the build.
  - It is written atomically and its contents are checked on load.
  - Caches of older versions are removed.
  - Only the first start of a new version compiles. Later starts load the
    shaders in milliseconds (checked under Wine with the real
    `d3dcompiler_47.dll`: 13.1 s to compile, then 0.00 s; a corrupted cache
    file is detected and rebuilt).
  - `ShaderCache=0` disables it.
- **Faster compile.** The big shader compiles in about 14 s instead of about
  20 s on the reference machine (user PCs were about 2x slower).

## 3. "Doesn't work" (RTX 3060 Ti, driver 617.14)

- **Helldivers 2.**
  - The log ends 4 seconds after the game's first Present, right after a
    `reason=reentrant` bypass.
  - The periodic status line never followed, so the game had closed.
  - At start-up, the import scan had patched GameGuard's own module
    (`GameGuard\npsc64.des`). GameGuard checks its own code and imports, and
    closes the game when they change.
- **Far Cry New Dawn.** The attached `nvsmooth30.log` is from 2.8.4 **Fix21**
  (written 28 September, 01:53 UTC), not 2.8.5. Fix21 never hooked this game
  (`not_initialized`); Fix23 added the probe swapchain for exactly this case.
  A 2.8.5 or Fix25 log is needed. If there is none beside the game EXE, look
  in `%LOCALAPPDATA%\SmoothMotion`.

What Fix25 changes:

- **Protected modules are never patched.** This covers:
  - GameGuard (`*.des`, the `GameGuard` folder, `npgg*`);
  - EasyAntiCheat, BattlEye, XIGNCODE (`*.xem`) and AhnLab HackShield;
  - Microsoft Defender's in-process modules (`MpOav.dll`, `MpClient.dll`).

  Their graphics probes also cannot start or attach the backend.
- **Present hook cycles are broken.**
  - If our Present hook is entered a third time on the same thread, another
    tool's hook is calling back into ours. The call then goes to the
    swapchain's own Present.
  - That address is read from the module file on disk, relocated to the
    loaded image, and checked to lie in executable code. It works even when
    every in-memory table entry is hooked.
  - The log names the module that had replaced Present before us.
  - `hook_cycles` in the status line counts cycles.
- **Crash report in the log.** A fatal exception in this module, or a stack
  overflow anywhere in the game, is now written to the log. The report
  includes the modules found on the faulting stack, which shows a hook loop.
  Handling is unchanged: the exception continues to the game and Windows.
  (Tested under Wine with a stack overflow and an access violation.)

Anti-cheat systems may still refuse any injected DLL. Use offline or
anti-cheat-free modes where a game offers them.

## Settings

New in `nvsmooth30.ini` (see `nvsmooth30.example.ini`):

- `AsyncFlow=1` (default); `0` restores Fix24's flow path.
- `ShaderCache=1` (default); `0` compiles at every start.

## Limits

- Not run on Windows with an NVIDIA GPU. The asynchronous flow in particular
  (shared fences, NVOF on shared textures) is new code; its fallback covers
  setup failures, not a driver misbehaving at run time. If a game regresses,
  `AsyncFlow=0` returns to the Fix24 path.
- Quality was measured with DIS optical flow and on synthetic scenes; NVIDIA's
  flow differs in detail.
- Managed upgrades recognize the released 2.8.5 Fix24 binaries.
