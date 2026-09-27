# Fix 16 — 10-bit SDR games (God of War 2018)

Runtime version: `2.8.4-rtx20-dx12-preview2-fix16-test`.

Everything in Fix15 is included. This is a test build: nothing here has run on
Windows or a GPU.

## Why God of War did not work

`nvsmooth30_44.log` (Fix14, three sessions):

- The ASI loaded, the DX11 swapchain was found (borderless, 1920x1080,
  single sample, tearing allowed) and Presents were admitted.
- The game creates its swapchain with `format=24`, which is
  `DXGI_FORMAT_R10G10B10A2_UNORM`: a 10-bit backbuffer, used even in SDR.
- Only 8-bit RGBA/BGRA backbuffers were accepted, so every attempt ended in
  `Session disabled: requires windowed/borderless ... single sample` (28 times,
  `flow_pairs=0`). That message was misleading: the window mode and sample
  count were fine; the format was not. DLSS settings were unrelated.

## Change

- **RGB10A2 UNORM backbuffers** are accepted, on DX11 (including MSAA and
  exclusive fullscreen) and DX12. All transfer paths already move 4 bytes
  per pixel, which this format also uses.
- **Full precision where it is visible.**
  - NVIDIA optical flow only accepts 8-bit input, so flow still uses 8-bit
    copies.
  - Synthesis and resolve now read separate full-precision copies of both
    real frames.
  - Generated frames therefore keep the game's 10-bit gradients. With 8-bit
    input they would band in dark fog and sky, alternating with the real
    frames at 60 FPS.
  - Cost: one extra frame copy and two textures (about 16 MB at 1080p).
- **Log.**
  - `10-bit SDR backbuffer (R10G10B10A2)` confirms the new path.
  - Unsupported formats are now named with their number instead of the old
    windowed/single-sample message.

## Check (God of War)

1. Replace `new.asi` with `Manual/ASI_Only/new.asi` (the same route that
   worked for loading), or upgrade with the Manager (recognizes Fix15).
2. The log must show the version above, the `10-bit SDR backbuffer` line and
   then `Turing backend ready`. `flow_pairs` in the status must rise.
3. Keep HDR off in the game. With HDR on, the same format carries HDR10 (PQ)
   values. This build would also interpolate them, but the thresholds are
   tuned for SDR and that case is untested.
4. DLSS (any mode) is fine; the backbuffer after upscaling is what is used.

## Limits

- FP16 (`format=10`) HDR swapchains are still unsupported.
- If a game uses RGB10A2 for HDR10, interpolation quality is unknown (see
  above).

## Validation

- Policy tests: the format list is now exactly 24, 28, 29, 87 and 91.
- All Fix15 host, shader (20 groups) and package checks pass.
- The shaders are unchanged; they already work on normalized colours for
  any UNORM format.
