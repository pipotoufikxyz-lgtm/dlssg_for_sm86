# Fix 15 — roofline slivers, GPU budget and older DX11 games

Runtime version: `2.8.4-rtx20-dx12-preview2-fix15-test`.

This build fixes the dark slivers next to moving roofs and walls. It also
lowers the GPU time of frame generation and admits DX11 games that Fix14
passed through untouched. All Fix14 changes are included. It is a test build:
Windows/GPU execution, displayed frames and utilisation still need checking
on your PC.

## Roof artifacts

This was diagnosed from the Witcher 3 recording (`Test2_RTX2080`, RTX 2080,
1080p, 30 to 60) and `nvsmooth30_42.log`.

- **What the recording shows.** The camera pans and a dark building edge moves
  about 23 pixels per real frame over bright, almost featureless sky. In the
  generated frames, thin dark vertical lines and small blocks float in the sky
  about 11 pixels ahead of the edge. That is exactly where the edge will be in
  the next real frame. The edge itself is placed correctly.
- **Reproduced.** The production shader was run on the real frames through
  the CPU shader model, with block-matched flow standing in for NVOF. It
  produced the same lines at the same places.
- **Two causes, both fixed:**
  1. **HUD protection false positive.** Sky right beside the edge's new
     position is identical in both real frames, because the sky is flat. It
     contrasts only with the building in the next frame. The HUD-text test
     took it for on-screen text, and Resolve then pasted the next frame
     around it. That paste is the vertical line. Text detail must now stand
     out in both real frames.
  2. **Unwarped fallback in flat sky.** Optical flow has nothing to lock onto
     in clear sky, so its forward and backward vectors disagree by many
     pixels. Every interpretation failed validation, and the pixel fell back
     to the next real frame, which already shows the building there. A pair
     of flat, tightly matching samples along a candidate motion now counts
     as "visible in both frames". Such pixels are no longer treated as seen
     in one frame only, and they are filled from that flat pair. Only a
     current pixel that clearly differs from it is replaced; in smooth
     shading the fallback is already correct.
- **On the real frames** (crop around the edge in the video), dark pixels in
  the sky went from 150 to 9. On a HUD crop (minimap and quest text),
  stationary HUD pixels altered went from 400 to 376.
- **New test.** A textured roof moves 23 pixels over flat sky moving 21, with
  noisy sky flow. Roof pixels ending up in the sky: Fix14 288 of 2,288,
  Fix15 1. All other shader groups give the same numbers as Fix14.

## GPU utilisation

**Your log** (Fix14, 30 FPS base) measured about **5.7 ms of GPU time per
generated frame**: SLOW optical flow about 3.1 ms and synthesis about 2.6 ms.
Fix13, with the MEDIUM preset, measured about 1.4 + 1.7 ms (RTX 2070 SUPER).
Fix14's automatic SLOW preset below 40 FPS nearly doubled the cost per frame.
In a light scene like the character-select screen, that is as much GPU time
as rendering the frame itself. This is why 30 to 60 showed the same
utilisation as native 60.

- **GPU budget.** The GPU time of each pair (flow + synthesis) is measured per
  flow mode. Automatic settings use the best mode whose cost fits
  `GpuBudget`, in percent of the real frame time (default 10%, i.e. 3.3 ms at
  30 FPS): SLOW, then MEDIUM, then half-resolution flow.
  - A rejected mode is measured again after 30 seconds, because the cost
    depends on the scene.
  - With your log's numbers, SLOW (5.7 ms) is over budget and MEDIUM is used.
  - `GpuBudget=0` restores Fix14. `FlowQuality=high` always uses SLOW.
- **Flat fast path in synthesis.** In sky, walls and fog the flow is noisy, so
  the candidate motions spread far apart. Fix14 then sent 66–89% of the
  pixels in these scenes through the full path (about 350–450 texture reads
  each, against about 100 on the fast path). Flat, tightly matching pixels
  now take a fast path, unless a nearby motion carries distinct matching
  content (a pole or wire crossing the sky).
  - Texture reads counted on your frames, weighting each 32-pixel wave by its
    slowest pixel: −34% (sky and roof edge), −39% (roofs), −12% (HUD over
    clouds).
  - These are counts in the shader model, not GPU measurements.
- **In the log.**
  - A `flow=` line appears whenever the mode changes, with the measured
    milliseconds per mode and the budget.
  - The status block has `gpu_budget_percent`, `flow_mode` and
    `pair_gpu_us` (slow/medium/half).

## DX11 games that were passed through

Fix14 interpolated only windowed/borderless, single-sample swapchains
presenting with sync interval 0 or 1. Fix15 admits the following as well:

- **Sync interval 2–4.** Many console ports lock to 30 FPS by presenting with
  interval 2 on 60 Hz (NFS Most Wanted 2012 is locked to 30). The generated
  and real frames now share those refreshes: 1 + 1 for interval 2.
- **Exclusive fullscreen** (DX11 and DX12). `ExclusiveFullscreen=0` restores
  the pass-through.
- **Multisampled DX11 backbuffers** (MSAA / edge smoothing drawn directly
  into the backbuffer, common in older DX11 engines). Frames are resolved for
  capture and written back by drawing into every sample. sRGB backbuffers
  round-trip exactly (tested in the shader model).
- **Clearer log.**
  - The first admitted Present reports `windowed=`.
  - Sync intervals above 1 are reported.
  - Unsupported backbuffer formats are logged with their numbers.

The actual reason NFS Most Wanted 2012 and The Sims 4 did not work is not
known yet: no logs from those games were available. If either still fails,
please send its `nvsmooth30.log`, from the game's EXE folder. Useful lines:

- `game swapchain created: ... format= buffers= effect= windowed= samples=`
- `Present bypass: reason=...`
- `Session disabled: ...`

If no `nvsmooth30.log` appears at all, the game did not load the carrier.
Then try another route in the Manager, or the Dinput8/Winmm kits. The Sims 4
must use its DirectX 11 mode, and its 64-bit EXE is in `Game\Bin`.

Other known limits:
- 10-bit and HDR backbuffers are still unsupported.
- Vulkan and OpenGL are still unsupported.
- DX11 devices below feature level 11.0 are still unsupported.

## Settings (`nvsmooth30.ini`, `[RTX20]`, or environment variables)

| Key | Environment | Default | Values |
|---|---|---|---|
| `GpuBudget` | `SM86_GPU_BUDGET` | `auto` (10) | percent of the real frame time; `0`/`off` = unlimited |
| `ExclusiveFullscreen` | `SM86_EXCLUSIVE_FULLSCREEN` | `1` | `1`, `0` |
| `FlowQuality` | `SM86_FLOW_QUALITY` | `auto` | `auto` (now within the budget), `high`, `medium` |
| `FlowResolution` | `SM86_FLOW_RESOLUTION` | `auto` | `auto` (half also when MEDIUM is over budget), `full`, `half` |
| `Pacing`, `GenerateAboveRefresh` | unchanged | | see FIX14_NOTES.md |

## Install and check

1. Close the game. Replace the previous file with `Manual/Version/version.dll`
   (standalone) or `Manual/ASI_Only/new.asi` (ASI), or use the Manager (it
   recognizes exact Fix14 binaries).
2. The log must show the version above and `artifact_guard=occlusion_aware_v6`.
3. Look for the `GPU budget:` line and, after a few seconds, a `flow=` line.
4. Record the same Witcher 3 pan and compare the roof edges. Compare GPU
   utilisation at 30 to 60 with Fix14. If you prefer Fix14's flow quality
   regardless of cost, set `GpuBudget=0`.
5. Optional: `Test/Test_DX11_Legacy_MSAA.cmd` runs the DX11 hardware test as an
   older game would present: DISCARD swapchain, 4x MSAA backbuffer, 10 s at
   interval 2 (30 FPS lock), then 10 s uncapped. Its report is
   `Test/rtx20-legacy-test-report.txt`. Nonzero `flow_pairs` and
   `generated_present_accepted` show the new paths ran.

## Limits

- **Flat-region fill.** It assumes untextured areas have no hidden detail. A
  very faint object crossing clear sky, with less than about 2% contrast per
  pixel, may be drawn as sky in the generated frame.
- **GPU budget.** The budget uses D3D11 timestamps. Optical flow runs on its
  own engine and synthesis waits for it, so the flow share of "GPU time" is
  partly latency, not shader load. The utilisation shown by overlays may drop
  less than the per-pair milliseconds suggest.
- **Exclusive fullscreen and MSAA** paths have not run on Windows here. If
  one misbehaves, `ExclusiveFullscreen=0` or disabling in-game MSAA returns
  to the Fix14 behaviour for that game.

## Validation

- Shader model: 20 behaviour groups pass in optimized and ASan/UBSan builds,
  including two new ones: roof edge over flat sky with noisy flow, and the
  MSAA sRGB write-back round trip.
- All seven HLSL entry points (Fullscreen, Capture, Project, Synthesize,
  Resolve, Blit, BlitSrgb) compile with glslang 15.1.0.
- Policy tests (optimized and ASan/UBSan) cover:
  - sync interval 2–4 admission and paired intervals;
  - paced pairs submitting the planned intervals;
  - GpuBudget parsing;
  - the flow-mode choice (unknown cost, the log's 5.7 ms SLOW case,
    hysteresis, forced settings, 30-second re-measure, FPS rules, unlimited
    budget, implausible samples).
- The D3DCompiler warning X4000 about `candidateMotion`, seen in your log, is
  removed. The function now has one return path.
