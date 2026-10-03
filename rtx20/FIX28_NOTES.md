# SmoothMotion 2.8.5 RTX20/RTX30 Fix 28 — Vulkan, and objects that stay whole

Version `2.8.5-rtx20-rtx30-dx12-preview2-fix28-test`,
`artifact_guard=occlusion_aware_v12`. Nothing here has run on Windows with an
NVIDIA GPU; see "What was tested" for exactly what has.

## 1. Vulkan games (RDR2 in Vulkan mode and others)

Frame generation now works for Vulkan games, with the same optical flow,
synthesis and presentation policy as DX11/DX12.

**How it works**

- When the module loads (ASI loader or `version.dll`), it registers itself as
  a Vulkan layer **for this game's process only**. It writes a small manifest
  to `%LOCALAPPDATA%\SmoothMotion\VulkanLayer\<id>\` and sets
  `VK_ADD_LAYER_PATH`, `VK_LAYER_PATH` and `VK_INSTANCE_LAYERS` in the
  process's own environment. Nothing is installed system-wide and nothing is
  written to the registry.
- The Vulkan loader then inserts the module into the game's instance and
  device call chains (layer interface 2).
- Each eligible swapchain gets a bridge:
  - two D3D11 textures shared with Vulkan (the captured real frame and the
    generated frame);
  - a D3D11 fence shared as a Vulkan timeline semaphore.
- Per present:
  - The real frame is copied on the game's own queue after the game's
    semaphores.
  - The D3D11 interpolator computes the generated frame.
  - The generated frame is copied into a spare swapchain image and presented
    before the game's image.
  - The game's own image is never modified, and it is always presented exactly
    once.

**Requirements and limits**

- RTX 20 or RTX 30 (the D3D11 device is created on the Vulkan device's
  adapter, matched by LUID).
- Vulkan 1.1 or newer. A game that asks for Vulkan 1.0 gets a 1.1 instance;
  if the loader or driver refuses it, the game's own request is used.
- Timeline semaphores and `VK_KHR_external_memory_win32` /
  `VK_KHR_external_semaphore_win32`. NVIDIA drivers have them. If adding them
  fails, the game's device is created unchanged and frames pass through.
- Swapchain:
  - Formats: BGRA8 or RGBA8 (UNORM or sRGB), or A2B10G10R10.
  - Size: 128–3840 x 128–2160.
  - The layer adds transfer usage and one extra image (for the generated
    frame).
- Present modes:
  - FIFO / FIFO_RELAXED (VSync): both frames go on refreshes. The generated
    frame waits up to 25 ms for a free image; after three timeouts in a row it
    falls back to skipping.
  - MAILBOX / IMMEDIATE: timed spacing, as for DX games.
- The module must load **before the game creates its Vulkan instance**.
  `version.dll` or an ASI loader in the game folder does that; the Manager's
  normal install is enough.
- **Not when the game runs as administrator.** The Vulkan loader ignores layer
  paths from the environment in elevated processes. The status line then says
  `registered; ignored by the Vulkan loader because the game runs as
  administrator`. Start the game normally.
- While a Vulkan swapchain is generating, DXGI Presents in the same process
  are passed through (`present_skips.vulkan_generation`). NVIDIA can present
  Vulkan through DXGI underneath, and frames must never be generated twice.
- A program started by the game from another folder inherits the
  registration. There the module only forwards Vulkan calls and starts
  nothing else (`vulkan_layer: layer only`).
- `Vulkan=0` in `[RTX20]` of `nvsmooth30.ini` (or `SM86_VULKAN=0`) turns all
  of this off.

**Status fields** (in the log's runtime status): `vulkan_layer`,
`vulkan_generated_presents`, `vulkan_real_presents`.

**Check it on your PC:** `Test\RTX20_VulkanLayerTest.exe` loads `new.asi`
next to it, opens a small Vulkan window and presents 300 frames (VSync).
Arguments: `[frames] [fifo|immediate|mailbox]`. It prints whether the layer
was registered and listed, and how many generated presents the module made.
`PASS` means every frame was presented. On an RTX 20/30, generated presents
above 0 confirm the bridge works end to end.

## 2. Fewer fragments: optical flow refined against the frames

Two reports describe the same failure in fast camera turns:

- Monster Hunter World (YouTube tutorial footage): the helmet crest broke
  into dark fragments in every generated frame.
- Witcher 3: Geralt's head and sword broke apart.

**Cause.** NVIDIA's optical flow is regularised:

- It blends the motion of a thin or small object with the motion of the scene
  behind it across the outline.
- It drags narrow parts (a crest, a sword tip) to the camera's motion.

Those vectors match neither the object nor the background, so synthesis tore
such objects apart.

**Fix: two new passes** (`RefineForward`, `RefineBackward`) run before all the
others, at the flow grid's resolution:

- **When a vector is re-chosen.** Only where both directions of the flow agree
  on it (a valid correspondence by the flow's own account) but the frames do
  not: the cell's 4x4 pixels do not match the other frame there. A vector that
  already matches costs 33 texture reads per cell, which is most of a frame.
- **Candidates.** The vectors of nearby and more distant cells (1, 2, 4 and
  6 cells away) that show similar content. Repeating textures can match a
  foreign motion by coincidence, so dissimilar cells are not used. A
  candidate that matches well replaces the vector, polished by a pixel.
- **Covered or revealed content.** Where no candidate can match (content just
  covered or revealed), the cell takes the nearest motion that:
  - its own cell confirms, and
  - carries this cell onto differently moving content (the occluder).

  That is the motion an ideal flow reports there. The reported vector is only
  replaced if it explains almost none of the cell. Zero is never adopted this
  way: static HUD elements report zero, and translucent ones match neither
  motion.
- **Kept as reported:**
  - a vector the other direction contradicts (an occlusion by the flow's own
    account);
  - a vector leaving the image;
  - a vector that matches after a plausible brightness change
    (auto-exposure).
- **Switch.** `FlowRefine=0` returns to Fix27 behaviour.

**Measured (production shader code on the CPU, synthetic scenes with exact
truth).** New regression group: a dark crest tapering to a point moves 2 px
over foliage panning 20 px. Wrong crest pixels (of 2,860):

| Flow error model | Fix27 | Fix28 |
|---|---|---|
| Narrow part dragged to the scene's motion | 146 | 56 |
| Motions blended across the outline | 54 | 26 |
| Blended over a wide band (the MHW look) | 252 | 25 |
| Noisy vectors on the object | 133 | 46 |
| Blended and noisy | 179 | 81 |

Dark fragments away from the crest, Fix27 → Fix28:

- dragged: 9 → 0
- blended: 7 → 2
- blended over a wide band: 15 → 1
- noisy: 0 → 0
- blended and noisy: 1 → 5 (the one case that gets slightly worse)

Other groups compared with Fix27:

- **Better:**
  - Crosshair baseline scene: 75 → 111 of 111 core pixels.
  - Translucent crosshair: 42 → 47.
  - Half-resolution parallax: 28 → 23 wrong.
  - Exposure +25%: 161 → 156 wrong.
- **Unchanged:** smeared-silhouette group, 417 wrong in total (worst case
  2.4% → 2.9%).
- **Slightly worse:** exposure +15% parallax, 79 → 87 of 13,824 wrong.
- The suite now has 27 groups, all passing in optimized and ASan/UBSan builds.

Real Witcher 3 triplets from the user's recording, with a regularised block
matcher standing in for NVOF: wrong pixels went down in all ten cases.

- 4-pixel cells: 1,563,114 → 1,558,716 in total.
- 8-pixel cells: 1,182,381 → 1,178,394 in total.
- This metric is dominated by compression and timing differences.
- The refinement changed only 1–3% of the cells on these real frames.

On the Monster Hunter World frames, both versions keep the helmet mostly
whole with this stand-in flow, so that comparison shows no regression rather
than the fix. `FIX28_COMPARE.png` shows the synthetic crest (Fix27 vs Fix28)
and these frames.

**Cost** (estimated from texture reads; not measured on a GPU):

- Grid passes at 1/16 of the pixels: 33 reads per cell where the flow already
  matches; up to about 900 at motion boundaries (the outer rings only when
  the nearer cells hold no clearly good match).
- Roughly 0.2–0.6 ms per pair at 1080p on an RTX 2060 class GPU.
- The GPU budget includes it, as it includes all synthesis.

## 3. Reports

- **RDR2 (Vulkan):** supported from this version. This is untested on
  hardware, so please send `nvsmooth30.log` either way. Use `version.dll` (or
  an ASI loader) in the RDR2 folder, and do not run RDR2 as administrator.
- **Tekken 8, Ninja Gaiden 4, Far Cry New Dawn:** unchanged from
  `FIX27_NOTES.md`. A Fix25+ crash log is needed for Tekken 8, and a new log
  for Far Cry New Dawn.

## 4. What was tested

- **Vulkan layer on Linux.** Mesa lavapipe with the Khronos validation layer
  and the real Vulkan loader. A pure-Vulkan stand-in replaces the D3D11
  generator. Six cases: immediate and FIFO, applications asking for Vulkan
  1.0 (raised to 1.1), 1.1 and 1.2, with and without a Vulkan 1.2 features
  chain. Each case: 120 frames, 120 captures, 118 generated and 120 real
  presents, 0 validation errors.
- **Vulkan layer on Wine 9.0.** The built `normal.asi` loaded by the Khronos
  Windows loader (built from source, v1.3.275) through winevulkan:
  - Registration, manifest discovery, the Win32 dispatch chain and Vulkan 1.0
    → 1.1 all work; all frames were presented.
  - A child process started from another folder loads the module as a
    forwarding layer only.
  - The loader was built to honour layer paths in elevated processes, because
    Wine runs everything elevated; the release loader would ignore them, as
    the module correctly reports.
  - winevulkan has no Win32 external memory, so the D3D11 bridge did not run.
- **Shaders.** All 13 entries compile with `d3dcompiler_47` (O3, no warnings);
  27 shader groups, policy tests and package verification pass.
- **Not tested:** anything on Windows with an NVIDIA GPU. That includes the
  D3D11↔Vulkan interop, NVIDIA's optical flow on Vulkan frames, real
  displayed output, and the GPU cost of the refinement passes.
