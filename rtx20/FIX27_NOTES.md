# Fix 27 — DX12 games adopted at Present (World of Warcraft), better flow

Runtime version: `2.8.5-rtx20-rtx30-dx12-preview2-fix27-test`. The log shows
`artifact_guard=occlusion_aware_v11`. Everything in Fix26 is included. This is
a test build: it has not run on Windows or on an NVIDIA GPU here.

## Reports and logs

| Log | Game, card | Build | What the log shows |
|---|---|---|---|
| 63 | World of Warcraft, RTX 3080 | Fix24 | DX12 swapchain adopted at Present, `presentation queue unavailable; passthrough` |
| 64 | Tekken 8, RTX 3080 | Fix24 | 10-bit DX12 swapchain; NvPresent creates a 100x100 swapchain; the log ends right after shader compilation |
| 65 | Ninja Gaiden 4, RTX 3090 | Fix24 | Generation ran, then the guard paused it (77 real / 154 shown vs 148 native) |
| 66 | Ninja Gaiden 4, RTX 3090 | 2.8.2 GP9 | NVIDIA's own Smooth Motion model, patched for RTX 30 |
| 67 | Far Cry New Dawn, RTX 3060 Ti | Fix21 | No graphics call was ever intercepted |

## 1. World of Warcraft: DX12 only worked after switching DX11 → DX12

WoW creates its D3D12 swapchain before any creation hook can see it (its
executable's import tables are unreadable, `creation hooks ready: 0 imports`).
The Fix23 present-table probe then finds the swapchain at its first Present,
but a D3D12 swapchain needs its command queue, which only the creation call
carries; DXGI does not return it. Interpolation stayed off until the game
re-created its renderer (DX12 → DX11 → DX12), when the creation hook saw it.

Fix27: while such a swapchain waits, `ID3D12CommandQueue::ExecuteCommandLists`
counts the game's DIRECT queues on the swapchain's device; the one submitting
most (ties: from the presenting thread) is validated like a creation queue and
used. The hook is installed only when a swapchain needs it (a temporary D3D12
device reveals the queue table) and only forwards once the queue is found.
The log says `Swapchain presentation queue found from the game's submissions`.
The queue contract also takes the swapchain's device from its backbuffer when
the swapchain does not return a device.

## 2. Better optical flow

- **Temporal hints.** NVIDIA's optical flow now seeds each pair's search with
  the previous pair's vectors (NVIDIA recommends this for successive video
  frames). Fast camera turns are tracked from the motion of the previous
  frame. Only when the same flow session ran the immediately preceding pair
  within 250 ms; a driver that rejects hints is retried without them at once
  (`Temporal hints rejected by the driver`), and they stay off.
- **SLOW preset up to 55 real FPS** (Fix14-26: 40) whenever its measured cost
  fits the GPU budget. Half resolution still takes over at 58 FPS.
- Checked and not adopted: NVOF's 2-pixel output grid on RTX 30. On the
  Witcher 3 frames it looked the same as full-resolution 4-pixel cells, at
  about four times the vector count.

## 3. The other reports

- **Tekken 8 (log 64).** The log ends right after shader compilation, before
  the DX12 transfer is set up for the game's 10-bit swapchain; no specific
  fault could be found from it. NVIDIA's NvPresent layer (most likely loaded
  because Smooth Motion is enabled in NVIDIA Profile Inspector) also created a
  100x100 swapchain inside the game's Present. Since Fix25 a fatal crash is
  written to `nvsmooth30.log` with the modules on the stack: please send a
  Fix27 log. Worth trying meanwhile: Smooth Motion **off** in Profile
  Inspector for Tekken 8 (this build does not need it; only the 2.8.2 GP9
  route does).
- **Ninja Gaiden 4 (logs 65/66).** Fix24 did generate frames; at 1440p and
  148 native FPS each pair cost 7.7 ms, so with generation the game ran at
  77 real FPS (154 shown) — about the same as without. The guard therefore
  paused it, by design. 2.8.2 GP9 uses NVIDIA's own model through a driver
  patch, a different route that this package does not contain. On RTX 30
  with a supported driver (617.14) that route remains the one to use for
  high-frame-rate games; this build's generation helps most from about 30 to
  70 real FPS. `GenerateAboveRefresh=1` disables the guard.
- **Far Cry New Dawn, "doesn't work in 10 games" (log 67).** That log is from
  Fix21: no graphics call was ever seen. Fix23 added the present-table probe
  for exactly this; please retry with Fix27 and send the new log.
- **RDR2 with Vulkan.** Not supported: this build interpolates DirectX 11 and
  12 only. Use RDR2's DX12 renderer.

## Validation

- New policy tests (queue selection; SLOW threshold); all host tests and the
  26 shader groups pass in optimized and ASan/UBSan builds; package
  verification passes. All eleven shader entries compile with d3dcompiler_47.
- The queue discovery and temporal hints need a Windows PC with an NVIDIA GPU
  to confirm; nothing here ran there.
