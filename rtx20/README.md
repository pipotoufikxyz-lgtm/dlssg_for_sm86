# SmoothMotion RTX20 builds (Turing / RTX 20-series)

## Fix 11 — frame-generation performance test (current)

`SmoothMotion-2.8.4-RTX20-DX12-Preview2-Fix11-Performance-Test.zip`: all Fix10
artifact changes plus adaptive half-resolution optical flow (automatic at 58+
real FPS) and per-stage GPU timing in the log.

- `FIX11_NOTES.md`: Blackwood/RE3 log analysis, changes, install and limits.
- `nvsmooth30.example.ini`: optional `FlowResolution=auto|full|half` setting.
- `DX12-Preview2-Fix11.patch`: source and document difference from Fix10.

## Fix 10 — fast-pan and HUD artifact test (previous)

`SmoothMotion-2.8.4-RTX20-DX12-Preview2-Fix10-Motion-HUD-Test.zip` is the complete
rebuilt package (runtime carriers, Manager, installer, tests, source, symbols).

- `FIX10_NOTES.md`: what the Fix9 recording showed (30 FPS base, 60–100 px pans,
  pole-top breakup, erased HUD text), the changes, install steps and limits.
- `DX12-Preview2-Fix10.patch`: source and document difference from Fix9.

## Fix 9 — occlusion-aware synthesis test (previous, kept for rollback)

- `SmoothMotion-2.8.4-RTX20-DX12-Preview2-Fix9-Occlusion-Test.zip`, `FIX9_NOTES.md`,
  `DX12-Preview2-Fix9.patch` (difference from the supplied Fix8 package).

`.sha256` files hold the ZIP checksums. Windows/GPU execution and in-game image
quality are verified only by your own testing: run `Test/ShaderCheck.exe` (five
PASS lines), then compare F11 off/on in the same scene.
