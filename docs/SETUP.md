# Setup, presets and troubleshooting

These fork additions improve installation and configuration around the upstream **Native 0.2.4** runtime. The DLLs, kernels and model are unchanged. They do not add Vulkan support, fix engine-level artifacts, or establish new FPS, latency or VRAM gains. The performance tables in the READMEs are upstream results, not measurements of this fork's changes.

## Before you start

- Windows 10/11 x64, an NVIDIA GPU supported by the upstream route, and a D3D12 game are still required. The helper does not detect your GPU or make an unsupported game compatible.
- Exit the game and identify its **actual rendering EXE**, not its launcher. The helper validates the x64 PE header, but cannot distinguish a rendering executable from an x64 launcher.
- Extract the whole package to a separate folder. Do not run it from the game's folder. Keep the package's `tools` and `config` directories together.
- Do not use DLL proxy mods in anti-cheat-protected multiplayer games unless the game explicitly permits them. The helper cannot determine anti-cheat compatibility.
- Do not disable antivirus or install a self-signed certificate to make this helper work. A matching SHA256 detects changes relative to this checkout; it is **not proof of safety or independent authenticity**.

## Optional PowerShell helper

Open Windows PowerShell 5.1 or PowerShell 7 in the extracted package directory. No Python, CUDA Toolkit or administrator privileges are required by the helper. If the game directory denies writes, use your launcher's supported library-location/permissions workflow rather than automatically elevating the script.

Preview an RTX 30-series/SM86 install first. Replace the example path with your rendering EXE:

```powershell
.\tools\Setup-DLSSG.ps1 -Action Install -GameExe 'D:\Games\MyGame\Game.exe' -Router SM86 -Multiplier 2 -WhatIf
```

Remove `-WhatIf` to install:

```powershell
.\tools\Setup-DLSSG.ps1 -Action Install -GameExe 'D:\Games\MyGame\Game.exe' -Router SM86 -Multiplier 2
```

For RTX 20-series/Turing, use `-Router SM75`. Physical Turing validation remains outstanding in the upstream release. `-Multiplier` accepts **2, 3 or 4** and caps the total multiplier, not the number of extra frames. Omitted options retain the package defaults: SM86, up to 4X, PTX, exact sampling, errors-only logging. The examples explicitly start at 2X for comparison, not because 2X is a proven fix for every game.

If `version.dll` belongs to another mod, preserve it and choose a different entry point **that the game loads**:

```powershell
.\tools\Setup-DLSSG.ps1 -Action Install -GameExe 'D:\Games\MyGame\Game.exe' -Proxy winmm.dll -Router SM86 -Multiplier 2
```

Supported proxy names are `version.dll`, `winmm.dll`, `dinput8.dll`, `winhttp.dll` and `dxgi.dll`. The helper verifies the selected package DLL against `config/binary-hashes.json`, stages it, and refuses to overwrite an existing proxy. It recognizes all five current package DLLs and the archived release by hash, including those copied under another supported proxy name. Unknown versions cannot be identified reliably; warnings about other proxy-name files need manual review. Never knowingly install two copies of this project into the same game.

An existing `dlssg_sm86.ini` is backed up byte for byte, then replaced with a clean five-key configuration. Custom diagnostic settings are not merged. The backup and ownership record live in **`.dlssg-setup` beside the game EXE**. Keep this directory until uninstalling. Normal install failures attempt rollback; do not run multiple installers or edit the destination concurrently.

To try approximate sampling, explicitly add `-Approximate` with `-Router SM86`. It changes generated pixels and can be slower. It is rejected on SM75, where it has no effect. Keep exact sampling as your starting point.

If PowerShell blocks a downloaded script, review it and verify the download source first. Where your policy permits, Windows file Properties may offer **Unblock** for that reviewed file. Do not change machine-wide execution policy or bypass an organization's policy. Manual installation remains supported.

## Read-only setup check

```powershell
.\tools\Setup-DLSSG.ps1 -Action Check -GameExe 'D:\Games\MyGame\Game.exe'
```

Works for helper-managed or manual installations of the current package. It checks:

- One recognized current proxy, with its original filename, beside an x64 EXE.
- Presence and allowed values of all five core INI keys.
- Duplicate sections/keys and malformed INI lines.
- Diagnostic settings left enabled, a disabled mod, known obsolete options, non-PTX selection and ineffective SM75 approximate sampling.

The checker accepts additional sections/keys for documented advanced options, but does not fully validate them. It uses full-line `;` or `#` comments; use those instead of trailing inline comments. It prints the default log directory but does not inspect or upload logs. If you set a custom `Logging.Directory`, look there instead.

A successful check **does not prove** that the game loads the proxy, supports DLSS FG, uses D3D12, has sufficient VRAM, or has a compatible GPU/driver. The tool never launches the game or changes driver settings. Install and Uninstall refuse while a process matching the EXE's name is running. Close the game yourself; the helper never terminates it.

## Uninstall and restore

Exit the game, then:

```powershell
.\tools\Setup-DLSSG.ps1 -Action Uninstall -GameExe 'D:\Games\MyGame\Game.exe' -WhatIf
.\tools\Setup-DLSSG.ps1 -Action Uninstall -GameExe 'D:\Games\MyGame\Game.exe'
```

Uninstall removes only the recorded proxy and generated INI, restores the previous INI if there was one, then removes its backup/record directory. Other mods, original game DLSS DLLs and game logs are left alone. If you edited the generated INI or replaced the proxy, uninstall stops **before changing anything**. Move those changed files to a safe backup directory outside the game directory, then retry. It will not silently discard your edits. A missing or changed original backup also stops restoration, unless that original has already been restored intact.

For an upgrade or different setup options, uninstall first, then install again. Preserve any custom INI edits before uninstalling; reapply only the settings you still need. Existing manual installs are not adopted or automatically removed. Back them up outside the game directory and remove only the files you can identify as this mod before using Install.

### Interrupted operation

If automatic rollback cannot finish, keep `.dlssg-setup` and fix the reported file lock or permissions before retrying Uninstall. Uninstall tolerates missing managed files and an already-restored original INI. If it finds `proxy.pending` or an incomplete record, stop and recover manually:

1. Copy `.dlssg-setup` and the current INI to a safe location outside the game directory.
2. Review `state.json` if present. Identify this helper's proxy by filename and hash before moving it out of the game directory. Never delete an unrelated proxy based only on its filename.
3. If `original.ini` exists, verify it against `OriginalIniHash` when a complete record is available and restore it as `dlssg_sm86.ini`. Otherwise preserve the live INI until you know whether it predates this installation.
4. Remove the leftover helper directory only after recovery. An empty `.dlssg-setup` left by a failed final directory deletion can be removed manually.

## Manual presets

Copy one preset to the rendering EXE directory as `dlssg_sm86.ini`, backing up your existing file first. Restart the game after any change.

| File in `config/presets` | Route | Sampling | Total multiplier cap |
|---|---|---|---|
| `sm86-default.ini` | RTX 30-series / SM86 | Exact | 4X |
| `sm86-2x.ini` | RTX 30-series / SM86 | Exact | 2X |
| `sm75-default.ini` | RTX 20-series / SM75 | Exact | 4X |
| `sm75-2x.ini` | RTX 20-series / SM75 | Exact | 2X |
| `sm86-performance.ini` | SM86 only | Approximate, not necessarily faster | 4X |

The `performance` filename is retained for compatibility; it is not a speed guarantee. All presets use PTX and `Logging.Level=1`. To cap at 3X, set `MaxGeneratedFrames=2`. The game still chooses the actual multiplier within the cap. Lowering the cap mainly reduces generated output buffers; upstream measurements do not support a promise of large VRAM savings.

## Troubleshooting without guessing

| Symptom | First checks |
|---|---|
| FG option missing / no project logs | Actual rendering EXE, one project proxy with a name the game loads, original game DLSSG files still present. Temporarily set `Logging.Level=2` and restart. |
| Stutters despite high displayed FPS | Compare the same scene with FG off and at 2X. Check output resolution, textures, ray tracing and background VRAM usage. Average FPS alone does not establish smooth frame pacing. |
| Ghosting, flicker or HUD artifacts | Start with exact sampling (`HardwareBilinear=0`), PTX and the correct route. Compare FG off/2X/4X in the same scene. Engine-level defects need upstream runtime work. |
| Architecture mismatch / failure with Cubin | Use SM86 for the supported Ampere route or SM75 for Turing, with `KernelImage=PTX`. Cubin requires an exact physical SM/router match. |
| Suspected performance regression | Same scene/settings, warm-up, repeated runs, only one change at a time. Compare frame times and visible artifacts, not just generated-frame FPS. Restore `Logging.Level=1` and remove diagnostic timing after testing. |

When reporting a problem, include GPU/VRAM, driver version, game and version, rendering API, output resolution, DLSS SR mode, FG multiplier, INI, chosen proxy SHA256, and steps to reproduce. Review logs for private paths before sharing. Never describe generated-frame FPS as reduced input latency without measuring latency.

## Testing the helper

```powershell
.\tests\Setup-DLSSG.Tests.ps1
```

Tests use temporary PE-header fixtures and the packaged DLLs without executing them. They exercise install/check/uninstall, byte-preserving backups, conflicts, WhatIf, invalid INIs, path handling, modified-file protection and rollback. CI runs Windows PowerShell 5.1 plus PowerShell 7 on Windows and Linux. These tests do not replace testing with a real Windows game and supported GPU.
