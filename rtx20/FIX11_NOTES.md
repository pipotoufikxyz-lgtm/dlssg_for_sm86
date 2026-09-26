# Fix 11 — frame-generation performance test

Runtime version: `2.8.4-rtx20-dx12-preview2-fix11-performance-test`.
Includes all Fix10 artifact changes.

## What the logs show

`nvsmooth30_35.log` (Blackwood, DX11, 1920x1200, RTX 2070 SUPER, Fix9):

| F11 | Real frames per second | Displayed |
|---|---:|---:|
| off | about 118 | 118 |
| on | 66–84 | 133–168 |

With interpolation on, each real Present waited about 5.4 ms on average. CPU
processing was about 1.6 ms. The GPU was already fully loaded, and frame
generation added roughly 4–7 ms of GPU work per real frame. That time comes
directly out of the base frame rate, so the result cannot double.

`nvsmooth30_36.log` (RE3 demo, DX12, same GPU): real Presents return in about
0.5 ms. The GPU had spare time, so frame generation's cost was mostly hidden
(125 → about 200).

The largest cost is NVIDIA optical flow run at full resolution in both
directions for every real frame. Synthesis shaders come next.

## Changes

- **Adaptive half-resolution optical flow.** A second NVOF session runs on
  2x2-averaged copies of the frames. That is a quarter of the pixels, and
  roughly a quarter of the optical-flow GPU time. Synthesis still matches
  candidates per pixel at full resolution.
  - Automatic mode switches to half resolution when the real frame rate is
    58 FPS or more, and back to full resolution below 45 FPS.
  - At high frame rates, motion per frame is small and GPU time decides the
    generated frame rate. At low frame rates (e.g. Witcher 3 at 30 FPS), full
    resolution keeps thin detail.
  - The log records each switch as `flow_resolution=half` or
    `flow_resolution=full`.
- **Setting.** `nvsmooth30.ini` beside the game executable, section `[RTX20]`,
  `FlowResolution=auto|full|half`. The default is auto; see
  `nvsmooth30.example.ini`. The environment variable `SM86_FLOW_RESOLUTION`
  overrides the file.
- **GPU timing in the log.** Runtime status now includes `performance_gpu_us`.
  It gives capture, optical-flow and synthesis GPU time from non-blocking D3D11
  timestamp queries, plus `flow_pairs_full` / `flow_pairs_half`. The next log
  shows exactly where the milliseconds go.
- Fix10 runtime hashes are recognized for managed upgrades.

## Install and test

1. Close the game. Replace the game's `VERSION.dll` with
   `Manual/Version/version.dll` (Blackwood:
   `F:\SteamLibrary\steamapps\common\BLACKWOOD\`; Witcher 3:
   `H:\Games\The Witcher 3\bin\x64_dx12\`). Keep the previous file.
2. Run `Test/ShaderCheck.exe` (five PASS lines).
3. Play for a minute with F11 on. The log should show the Fix11 version, a
   `flow_resolution setting=auto; half-resolution flow ready` line, and
   `flow_resolution=half` once the real frame rate reaches 58.
4. Compare the displayed FPS with Fix9/Fix10, and send the log. The
   `performance_gpu_us` block is the data needed for any further speedup.
5. For comparison, `FlowResolution=full` restores the previous behaviour.

## Expectations and limits

- A GPU-bound game cannot double. The Blackwood base frame rate of 118 was
  already using the whole GPU. Frame generation needs GPU time too, even at
  half resolution. The improvement should be visible, but its size is not
  measured: nothing here has run on Windows or a GPU.
- In half-resolution mode, detail thinner than about 8 pixels may lose its own
  motion. It is then shown at its current position instead of interpolated.
  At 58+ FPS the per-frame motion is small, so this is rarely visible. Use
  `FlowResolution=full` if it bothers you.
- Games with spare GPU time (RE3 demo) already come close to doubling, and
  gain less from this change.

## Validation

- Sixteen shader behavior groups pass in optimized and ASan/UBSan builds.
- The new group covers half-resolution flow:
  - analytical motion (more than 95% error reduction);
  - occlusion bands (bad pixels 431–541 of 13,824 against 164–395 at full
    resolution);
  - HUD text (1095/1104 pixels intact);
  - corrupted fields.
- The flow-resolution policy has host tests for explicit settings, hysteresis
  and frame-interval averaging.
- Shaders compile with glslang and with DXC in strict mode.
- D3D11 timestamp and NVOF behaviour on Windows remain unverified.
