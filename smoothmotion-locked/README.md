# SmoothMotion 2.8.5 Fix28 qua2 + locked 2x pacing (`fix28-qua2-lock`)

> [!WARNING]
> **Untested build: never run on Windows or on an NVIDIA GPU.**
>
> These binaries were cross-compiled on Linux and tested only with host
> unit tests and a software Vulkan driver (Mesa lavapipe). None of the
> following has been run:
>
> - the module loading in a real game (DirectX 11, DirectX 12 or Vulkan);
> - NVIDIA optical flow, the synthesis shader or D3D11/D3D12 interop on a GPU;
> - presentation on a real display, so **the "always 2x, no stutter" goal is
>   not confirmed**: it is what the code is designed to do, not a measured
>   result;
> - frame pacing, latency, GPU cost, G-Sync/FreeSync behaviour.
>
> The build may fail to start, crash the game, or pace frames differently
> from what this README describes. Keep a copy of the files you replace.
> To check it on your PC, run [the test kit](#test-kit) (about two minutes)
> and, in a game, read the [on-screen pacing line](#check-it-in-the-log)
> in `nvsmooth30.log`.

This build changes presentation and performance only. **The synthesis
shader and the optical-flow model are qua2's, unchanged:** the embedded
shader text is byte-identical to the one in the qua2 binary
(`artifact_guard=occlusion_aware_v14`), and the flow rules (resolution,
SLOW/MEDIUM, GPU budget) work as in qua2.

What it adds:

- `Pacing=locked` (default): exactly one generated frame per real frame,
  every frame on screen for the same number of refreshes.
- DX12: the copies between the game's queue and the interpolation no longer
  make the CPU wait (Fix28 waited three times per real frame).
- The module measures what the display actually showed (DXGI frame
  statistics) and writes it to the log, so "2x without stutter" can be
  checked in any DXGI game.
- Vulkan: locked pacing (FIFO), a frame-order fix, and an acquire fallback
  that recovers instead of staying nonblocking.
- **The full package with `SmoothMotion_Manager.exe`:**
  [`SmoothMotion-2.8.5-RTX20-RTX30-DX12-Preview2-Fix28-qua2-lock.zip`](SmoothMotion-2.8.5-RTX20-RTX30-DX12-Preview2-Fix28-qua2-lock.zip).
  The Manager installs this build and upgrades Fix28, qua1, qua2 or the
  first lock build in place ([Install](#install)).

Runtime version: `2.8.5-rtx20-rtx30-dx12-preview2-fix28-qua2-lock`. Built
from the Fix28 source in this repository's history (commit `e2700a1`,
`rtx20/SmoothMotion-2.8.5-RTX20-RTX30-DX12-Preview2-Fix28-Test.zip`) with
LLVM-MinGW 20250924 (clang 21.1.2), the same compiler as Fix28.

## What "always 2x" means here

Displayed frames = 2 × the game's real frames, on every frame. It does not
mean 2 × the frame rate the game had without generation. Generation costs
GPU time, and locked pacing holds the game at half the refresh rate:

| Display | Game (real) | Shown |
|---|---|---|
| 60 Hz | 30 | 60 |
| 120 Hz | 60 | 120 |
| 144 Hz | 72 | 144 |
| 165 Hz | 82.5 | 165 |

The game must hold that rate **with generation running**. If it cannot, a
frame misses its refresh and the display repeats one: a stutter. The log
reports these (see below). Then:

1. set `LockedBaseRate=quarter` (DXGI games: 36 real / 72 shown at 144 Hz,
   every frame two refreshes), or
2. lower the Windows refresh rate (for example 144 Hz → 120 Hz or 60 Hz), or
3. lower the game's settings, or set `FlowResolution=half`.

## Performance changes

### DX12: no CPU wait per copy

A DX12 game's frame goes through three copies per real frame: the game's
image into a texture shared with the D3D11 interpolation (capture), the
generated frame back into the swapchain, and the saved real frame into the
next buffer. Fix28 waited on the CPU for each of them to finish on the GPU.
The game's render thread stopped three times per frame until the GPU caught
up, so CPU and GPU work could not overlap.

With `Pacing=locked` and `Dx12Transfer=async` (both default) the copies
are ordered by GPU fences between the D3D12 queue and the D3D11 context,
and the CPU does not wait.
Copy command lists come from a ring of 16; one is reused only after its
previous copy finished (normally long done: DXGI's frame latency stops the
CPU first). Resizes and session ends still wait for every copy.
`Dx12Transfer=sync` restores Fix28's behaviour, and the other Pacing modes
always use it (they time the generated frame from the Present call, which
in Fix28 came after completed copies). The log line
`[rtx20-dx12] Transfer mode:` shows which one runs; drivers without
shared D3D12/D3D11 fences fall back to sync.

DX11 games and the Vulkan bridge already synchronised on the GPU in Fix28;
they are unchanged.

### Locked pacing

Measured against the Fix28 source, these paths lowered the rate or broke
the cadence:

| Cause in Fix28 | Effect | Locked mode |
|---|---|---|
| Cost guard (`MinimumBaseRate`, +10% displayed rule) | generation paused for 30–300 s, retries cost seconds of low FPS | off |
| Refresh-rate pause (real rate ≥ refresh) | generation off at high frame rates | off: the game is held at refresh/2 |
| Native + measuring phases after every reset (resize, F11, a rejected Present, any gap > 250 ms) | 0.5 s with no generation, then 0.75 s of unspaced pairs | none: generation resumes on the next frame |
| CPU spacing controller (`auto`/`low_latency`) | spacing drifts between 0 and half a frame | not used: the display's refreshes space the frames |
| `DO_NOT_WAIT` generated Present | generated frame dropped when the queue is full | VSync Present, never dropped |
| A frame without a pair (first after a reset) | shown immediately with the game's own interval | held for both slots: the cadence is unchanged |

## Vulkan

Vulkan support comes from Fix28 (`Vulkan=1`, the module registers itself as
a Vulkan layer for the game's process). This build changes three things:

- **Locked pacing on Vulkan.** Generating swapchains are created with FIFO
  (VSync, always supported) whatever the game asked for. MAILBOX replaced
  the generated image before it was shown; IMMEDIATE showed it for a
  fraction of a refresh. Log: `[vulkan] Pacing=locked: present mode N
  replaced by FIFO`.
- **Acquire fallback that recovers.** The generated image's acquire waits
  at most 25 ms. Fix28 switched to a nonblocking acquire for the rest of
  the session after three timeouts in a row, and from then on dropped a
  generated frame whenever no image was free. Locked mode switches for 300
  generated frames, then blocks again (logged at most three times).
- **Frame-order bug fixed** (any Pacing). The Vulkan bridge always presents
  the game's current image after the generated one, so the pipelined order
  (`Pacing=smooth`, or `auto` on MAILBOX/IMMEDIATE) showed frame N, the pair
  (N−2, N−1), then N+1: a step backwards on every frame. The pipelined order
  is now off for Vulkan swapchains.

`LockedBaseRate=quarter` does not apply to Vulkan (FIFO has no per-present
interval). The on-screen measurement is DXGI-only. As in Fix28, the module
must load before the game creates its Vulkan instance (`version.dll` or an
ASI loader), and the game must not run as administrator.

## Known limits

- **Latency.** VSync pairs queue frames: expect roughly one to two refreshes
  more latency than Fix28's `auto`. `Pacing=auto` restores Fix28 behaviour.
- **G-Sync/FreeSync.** With VRR, VSync presents are not held to the
  refresh: the generated frame is shown for one maximum-refresh interval,
  the real frame for the rest. It is even only while the game holds half the
  maximum refresh. Otherwise use a lower refresh rate in Windows or
  `LockedBaseRate=quarter` with VRR off.
- **Flow switching is qua2's.** With `FlowResolution=auto` /
  `FlowQuality=auto` the flow mode can change during play (cost re-measured
  every 30 seconds). If the pacing line shows repeated refreshes at regular
  intervals, set both to fixed values (for example `full` and `medium`).
- **Games with their own interval 3** (20 FPS lock at 60 Hz) keep a 1:2
  cadence, as in Fix28.
- **GPU cost per pair is qua2's.** These changes remove CPU stalls; they do
  not make optical flow or synthesis cheaper.

## Install

> [!IMPORTANT]
> Untested on Windows/NVIDIA (see the warning at the top).

### With the Manager

1. Download
   [`SmoothMotion-2.8.5-RTX20-RTX30-DX12-Preview2-Fix28-qua2-lock.zip`](SmoothMotion-2.8.5-RTX20-RTX30-DX12-Preview2-Fix28-qua2-lock.zip)
   (26.4 MB) and extract the whole ZIP.
2. Run `SmoothMotion_Manager.exe`, pick the game and install, as with Fix28.

The ZIP is the Fix28 package rebuilt from this source:
`SmoothMotion_Manager.exe`, `Install.exe` and `Collect_Diagnostics.exe`
carry this build. Besides Fix28's earlier releases, they recognise these as
their own files and replace them in place (and the uninstaller removes
them):

- the Fix28 Test package;
- the qua1 and qua2 binaries (`smoothmotion-quality/bin/`, commits
  `4275fe8` and `8eb0089`);
- the first lock build (commit `338c4aa`).

As in Fix28, a `new.asi` or `version.dll` they do not recognise is not
overwritten. The ZIP also holds the manual kits (`Manual\`), the test kit
(`Test\Run_Tests.cmd`), `nvsmooth30.example.ini`, symbols and the full source.

| File | SHA-256 |
|---|---|
| `SmoothMotion-2.8.5-RTX20-RTX30-DX12-Preview2-Fix28-qua2-lock.zip` | `ebe69231ae347b5c112afc517a496f61f76863fb08cee50fb8ed151a12d4098b` |
| `SmoothMotion_Manager.exe` | `fe341e3d96bea30d6b7fed51af2acd421d5971c5e7c417a59e6a7fe7c76d2399` |
| `Install.exe` | `439a9edcd88b87a68e6c8defb260be39676dc034905757dc4fb3862efabedc8b` |

### By hand

Back up the game's current `new.asi` or `version.dll` first. Hand copies
get no uninstall receipt.

- **ASI loader route:** replace the game's `new.asi` with `bin/new.asi`.
- **Standalone route:** replace the game's `version.dll` with
  `bin/version.dll`.

| File | SHA-256 |
|---|---|
| `bin/new.asi` | `60cd80f9106126277501d9214cab1aa595fb27c967312ca64a6ecd220ab68f2b` |
| `bin/version.dll` | `c3d013478c4452c8ce4042110dffc877d95bbb8eed08cc3b993703bfa43553ca` |

These are the same files the Manager installs (`payload/native/normal.asi`
and `payload/native/version.dll` in the ZIP).

### Settings

- Optional: copy `nvsmooth30.ini` beside the game executable. Without it,
  `Pacing=locked`, `LockedBaseRate=half` and `Dx12Transfer=async` are the
  defaults.
- The first start compiles the shaders (10–30 s pass-through); later starts
  use the cache.

## Test kit

`test/` holds Fix28's hardware tests, rebuilt from this source, and
`Run_Tests.cmd` (the ZIP has the same kit in `Test\`). Download the whole
`smoothmotion-locked` folder, then double-click `test\Run_Tests.cmd`. It
copies `bin\new.asi` beside the tests, sets `Pacing=locked`, and runs:

1. `ShaderCheck.exe`: compiles the shaders with this PC's D3DCompiler.
2. `RTX20_TransferTest.exe`: DX12 copy pixel test in the three transfer
   modes (staging, sync, async) plus an async burst of 48 pairs without
   waits (the copy ring wraps nine times). Pixel-exact; with Windows
   Graphics Tools installed, the D3D12 debug layer also checks it. No
   optical flow.
3. `RTX20_SmokeTest.exe`: DX11, 10 s VSync then 10 s uncapped.
4. `RTX20_SmokeTest.exe legacy`: older DX11 setup (blt model, 4x MSAA).
5. `RTX20_DX12_SmokeTest.exe`: DX12 with resize and queue changes.
6. `RTX20_VulkanLayerTest.exe 900 fifo`: Vulkan layer through the bridge.

Results go to `test\results\`, with `0-pacing-summary.txt` collecting the
on-screen pacing lines. The blt-model test may give no frame statistics;
the log then says so. Send the whole folder back for review.

## Check it in the log

Example of a perfect result in `nvsmooth30.log` (144 Hz display, DX12
game; the numbers are illustrative, not measured):

```
[rtx20-dx12] Transfer mode: async (GPU fences between D3D12 and D3D11, no CPU wait per copy).
[rtx20] presentation: display 144 Hz; Pacing=locked: always 2x, generated and real frame 1 refresh(es) each, game held at 72.0 real FPS (LockedBaseRate=half), 144.0 displayed; never paused, no cost guard.
[rtx20] locked pacing, last 10 s (measured on the display): 720 real frames (72.0 FPS), 1440 Presents submitted, 1440 shown (144.0 FPS) on 1440 refreshes; 0 repeated refresh(es) in 0 frame(s), even 2x.
```

The `locked pacing` line comes from DXGI frame statistics: which Presents
the display showed and on which refresh. It is written every 10 s for the
first minute, then every minute.

- **0 repeated refreshes**, with shown ≈ submitted (a few Presents can
  still be queued when the line is written): every real and generated
  frame reached the screen for its own refresh. That is the "2x without
  stutter" result.
- **Repeated refreshes > 0**: a frame stayed on screen longer than its
  share (a stutter). One per reset (resize, F11, loading) is expected: the
  first frame after a reset has no pair yet. More than that during play:
  see the options under [What "always 2x" means here](#what-always-2x-means-here).
- **shown well below submitted, window after window**: Presents were
  never displayed.
- `frame statistics unavailable`: the swapchain gives no statistics (older
  blt-model swapchains); not measured.

Runtime status fields (in `performance_gpu_us`):

- `display`: cumulative `submitted`, `shown`, `refreshes`,
  `repeated_refreshes`, `stutter_frames` from the measurement above.
- `dx12_transfer`: `async`, `sync` or `none` (not a DX12 game).
- `locked_pairs`: generated + real pairs presented.
- `locked_held_frames`: real frames without a pair, held for both slots.
- `locked_late_frames`: real frames that took more than 1.5× their
  refreshes, timed on the CPU.
- `guard_pauses` and `generation_paused_frames` stay 0.

## What was tested

- **Build:** `normal.asi`, `version.dll`, `Install.exe`,
  `SmoothMotion_Manager.exe`, `Collect_Diagnostics.exe` and the five test
  programs cross-compiled without warnings (`source/build_release.py`).
- **Host tests (Fix28 suite, 21 suites × optimized and ASan/UBSan):**
  42/42 PASS. They include the installer's file plans: the four earlier
  builds above are upgraded in place on both routes, and a modified copy is
  never overwritten. Also policy tests for locked pacing (never paused,
  VSync pairs, held frames, quarter intervals, late-frame rule) and for the
  on-screen measurement (lagging and aliased statistics give no false
  repeats; a held refresh counts once; quarter; counter restarts).
- **Shader:** the embedded text is byte-identical to the shader text in the
  qua2 binary; `validate_shaders.py` 13/13 PASS.
- **Vulkan layer on Mesa lavapipe with the Khronos validation layer:**
  8/8 PASS, including IMMEDIATE replaced by FIFO and FIFO kept. The
  validation layer reports the test app's own swapchain-semaphore reuse with
  no layer loaded; the test requires the layer to add no error to that
  baseline.
- **Package check (`verify.py`):** PASS: identities, source hashes, 10
  PE/PDB pairs, manual kits; the payload `Install.exe` was built with and
  the helpers the Manager was built with are the files in the package. Its
  Fix28 shader-regression step is replaced by a check that the shader is
  qua2's exact text: Fix28's regression targets Fix28's shader, and qua2's
  does not meet all of its thresholds.
- **Not run:** anything on Windows or on an NVIDIA GPU (optical flow,
  synthesis, D3D11/D3D12 interop, the async DX12 path, the test kit); the
  Manager and `Install.exe` themselves; a real game; a real display. The
  host tests check the pacing logic and the order and intervals of Present
  calls, not what the display shows.

## Rebuild

The ZIP contains the full source. From its root, with LLVM-MinGW 20250924:

```sh
python3 source/build_release.py --cxx /path/to/llvm-mingw-20250924-ucrt/bin/x86_64-w64-mingw32-clang++
python3 source/package_release.py --output ../SmoothMotion-2.8.5-RTX20-RTX30-DX12-Preview2-Fix28-qua2-lock.zip
```

`build_release.py` needs `glslangValidator`, and `mesa-vulkan-drivers` +
`vulkan-validationlayers` for the Vulkan test. Or from the Fix28 package
root:

```sh
patch -p1 < source/fix28-to-lock.patch        # this folder's patch
cp <repo>/smoothmotion-quality/shader/shaders_embedded.hlsl source/rtx20/shaders.hlsl
rm validation/shader-regression.json          # Fix28's shader record
python3 source/build_release.py --cxx /path/to/llvm-mingw-20250924-ucrt/bin/x86_64-w64-mingw32-clang++
```

The patch covers `source/` only; the ZIP's documents (`LOCK_NOTES.md`,
README, changelog) are not in it.

## Files

- `SmoothMotion-2.8.5-RTX20-RTX30-DX12-Preview2-Fix28-qua2-lock.zip`: the full package with the Manager;
  `SmoothMotion-2.8.5-RTX20-RTX30-DX12-Preview2-Fix28-qua2-lock.zip.sha256`: its checksum.
- `bin/new.asi`, `bin/version.dll`: the build.
- `nvsmooth30.ini`: settings with comments.
- `test/`: test programs and `Run_Tests.cmd`.
- `source/fix28-to-lock.patch`: all source changes against Fix28 (the
  shader is copied, not patched; generated build reports excluded).
- `source/build-report.json`: compiler, artifact hashes and source hashes.
