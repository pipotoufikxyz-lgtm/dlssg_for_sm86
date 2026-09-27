# Fix 18 — RTX 30 (Ampere) support

Runtime version: `2.8.4-rtx20-rtx30-dx12-preview2-fix18-test`.

This package's own frame generation now runs on RTX 30 cards (Ampere SM86:
RTX 3050–3090, laptop variants included) as well as RTX 20. It uses NVIDIA's
optical-flow hardware plus our synthesis shader, the same code that received
every fix so far:

- **Fix14:** frames spaced for real 60 from a 30 FPS base.
- **Fix15:** no roofline slivers, the GPU budget, a cheaper flat-area path,
  30 FPS locks, exclusive fullscreen and MSAA.
- **Fix16:** 10-bit SDR games.
- **Fix17:** the performance guard and hitch-proof pacing.

Nothing else changed. This is a test build: no RTX 30 card has run it yet.

## How this differs from GP9 (2.8.2 R3 GP9 Fixes1)

GP9 has no frame-generation code of its own. It loads NVIDIA's closed Smooth
Motion model from the driver and patches it to run on RTX 30. Its ghosting and
quality come from NVIDIA's model and cannot be changed in that package. Fix18
uses code that can be improved from user logs and recordings.

## Install

1. Close the game.
2. Use the Manager from this ZIP on the same game EXE. It recognizes and
   replaces an owned GP9 installation (both routes) and exact Fix14–17
   installations. Manual kits: remove GP9's `version.dll` or `new.asi`
   first. Never keep both packages in one game folder.
3. The log must show `Ampere backend ready: adapter=NVIDIA GeForce RTX 30..
   SM86`.
4. Use DX11 or DX12, SDR, windowed, borderless or fullscreen. F11 toggles.

## What to expect on RTX 30

- **Optical flow.** Ampere's optical-flow engine is faster than Turing's. The
  GPU budget (`GpuBudget`, default 10% of the frame time) will therefore
  allow the best-quality SLOW preset more often. The `flow=` log lines show
  the measured cost per mode.
- **Performance guard.** If generation would lower the displayed frame rate
  (for example on a laptop already near its refresh rate), it pauses by
  itself. Look for the `guard:` log line.
- **Unsupported.** Vulkan, OpenGL, HDR/FP16, and RTX 40/50 cards: those have
  NVIDIA's own frame generation.

## If quality looks worse than GP9 in some scene

Send a short recording (F11 on, 30 to 60) and `nvsmooth30.log`. Per-scene
fixes (like the Witcher 3 roofline in Fix15) come from exactly that.
