# SmoothMotion RTX20 Fix 9 — occlusion-aware synthesis test

`SmoothMotion-2.8.4-RTX20-DX12-Preview2-Fix9-Occlusion-Test.zip` is the complete
rebuilt package (runtime carriers, Manager, installer, tests, source, symbols).
It replaces the Fix8 artifact-test build for RTX 20-series (Turing) GPUs.

- `FIX9_NOTES.md`: cause of the Fix8 block artifacts, changes, install steps for
  the Witcher 3 DX12 standalone `VERSION.dll` route, cost and limits.
- `DX12-Preview2-Fix9.patch`: source and document difference from Fix8
  (binaries and generated reports excluded).
- `.sha256`: checksum of the ZIP.

Windows/GPU execution and in-game image quality are not yet verified. Run
`Test/ShaderCheck.exe` (five PASS lines), then compare F11 off/on in the same scene.
