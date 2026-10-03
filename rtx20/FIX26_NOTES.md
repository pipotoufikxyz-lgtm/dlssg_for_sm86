# Fix 26 — fragments around characters, swords, HUD and roofs

Runtime version: `2.8.5-rtx20-rtx30-dx12-preview2-fix26-test`. The log shows
`artifact_guard=occlusion_aware_v10`. RTX 20 and RTX 30 share all changes.
This is a test build: it has not run on Windows or on an NVIDIA GPU here.

The report behind this build (Witcher 3 next-gen, DX12, RTX 2080, 1080p,
about 30 real FPS, `nvsmooth30_62.log` from 2.8.5 Fix24, and a 60 FPS screen
recording): "artifacting still there, and seems a bit worse in some cases —
around Geralt's head, the sword, the UI, and when moving the camera up and
down over roofs".

## 1. What the recording shows

Stepping the recording frame by frame, every second frame (the generated
one) breaks up while the camera turns:

- the two sword pommels behind Geralt's shoulders shatter into fragments,
  sometimes with a ghost copy beside them;
- pieces of Geralt's face and hair are torn out;
- the HUD labels (`10:07 AM / CLEAR`, the `1016` crowns panel) are smeared
  sideways by the sky moving behind them;
- roof edges and the top screen edge leave light and dark debris.

## 2. Why

The log explains most of it:

| | |
|---|---|
| Synthesis GPU time per pair | about 3.6 ms (32.4 s for 8,901 pairs) |
| GPU budget (`GpuBudget=auto`, 10% of 33 ms) | 3.3 ms |
| Flow mode for most pairs | half resolution (5,919 of 8,902) |
| Measured pair cost: SLOW / MEDIUM / half | 2.4 / 3.9 / 2.2 ms |

Synthesis alone exceeded the whole budget, so every automatic choice ended at
half-resolution optical flow (8-pixel cells), re-measuring SLOW and MEDIUM
every few seconds (the log flips between them all the time). Half resolution
saved almost nothing here, but its cells are wider than the pommels, the hair
strands and the HUD letters. The flow then carries only the sky's motion
there, and the synthesis had no motion that could draw these objects.

The same frames were rebuilt from the recording: the production shader code
runs on the CPU (as in the regression tests) on real frame pairs, with a
regularised block matcher standing in for NVIDIA's optical flow. With 8-pixel
cells it reproduces the in-game fragments; with 4-pixel (full-resolution)
cells the pommels, the face and the HUD labels come out intact with the very
same shader (`FIX26_COMPARE.png`).

What remained at full resolution, and what half resolution still shows:

- **Mixed per-pixel decisions.** Each pixel picks its own interpretation.
  Where several explain it about equally (smooth sky behind detail, noisy
  vectors), neighbouring pixels picked different motions, one-sided fills
  and fallbacks: up to seven motions within a few pixels at one pommel.
- **Sky painted into thin detail.** At a pommel, the sky's motion matches
  (smooth sky matches nearly anywhere) and has flow support; the pommel's
  own motion matches too, but no flow cell supports it. The sky won.
- **Ghost stripes beside thin objects.** In the bands a pommel or grip
  reveals and covers, nothing validated, and Resolve fell back to the
  unwarped current frame, misplaced by half the pan (16-20 px).

## 3. What changed

- **Flow policy (the main fix).**
  - `GpuBudget=auto` is now 20% of the real frame time (6.7 ms at 30 FPS).
  - Half-resolution flow is chosen for the budget only when it was measured
    clearly cheaper than MEDIUM (at least 25% and 0.5 ms less).
  - In the reported case this keeps full-resolution flow: SLOW (2.4 ms) below
    40 FPS, MEDIUM otherwise. Half resolution is still used automatically at
    58 real FPS and above (small motion per frame), and `FlowResolution=half`
    still forces it.
- **New Coherence pass** (after Synthesize, before Resolve). Synthesize now
  also writes, per pixel, the interpretation it used (motion, kind, weight).
  Coherence looks at 32 neighbours:
  - a decision shared by few neighbours, beside a clear majority, is replaced
    by the majority's interpretation — unless it explains the pixel clearly
    better, is a confident crossing object with line support (wires, poles),
    is a static overlay, or is static detail identical in both frames;
  - where no interpretation holds a majority, the result is rendered along
    the neighbourhood's mean motion and lightly low-passed: a soft, motion-
    blur-like patch instead of high-frequency fragments;
  - small motion differences inside one cluster (noisy vectors along soft
    cloud edges) use the cluster's mean motion when it matches as well;
  - pixels without any decision in the bands beside thin objects are filled
    from the real frame along the window's background motion, from the end
    that continues the neighbours (the other end shows the object). Never
    without a valid background motion (corrupted flow, scene cuts), never
    next to static overlays.
- **Textured matches count as evidence.** A tight two-frame match of textured
  content along the window's own foreground motion (the clearly separate
  second motion) counts as a crossing even without flow support; smooth sky
  matching along the background motion no longer outranks it.
- Synthesize has a single return (the helper is inlined into the entry), so
  D3DCompiler47 compiles all eleven entries without warnings.

## 4. Measured

Shader regression suite: 26 groups pass (one new). Numbers that changed:

| Test | Fix25 | Fix26 |
|---|---|---|
| Pommel and grip over a 40 px pan, 8-pixel cells: wrong pixels outside the object | 598 | 428 |
| Same, object pixels | 202 / 360 | 198 / 360 |
| Same, flow blind to the object: outside / object | 958 / 351 | 702 / 351 |
| Character with blade, smeared flow (Fix25 group) | 494 | 417 |
| All other groups | unchanged | unchanged |

The object itself stays hard to draw from 8-pixel cells (see the last rows):
that is why the flow policy now keeps full resolution at low frame rates.

Real Witcher 3 frames from the recording (12 pairs, see
`FIX26_COMPARE.png`): with full-resolution flow the pommels, Geralt's face and
the HUD labels are intact where the in-game Fix24 frames and the
half-resolution reconstructions break them.

Compilation: all eleven entries compile with d3dcompiler_47 (O3, no warnings,
12.5 s for all under Wine). GPU cost of the new pass: 32 neighbour loads per
pixel plus resampling only where a decision is replaced (estimated 0.2-0.4 ms
at 1080p on an RTX 2080; not measured on a GPU).

## 5. Limits

- Nothing here ran on Windows or an NVIDIA GPU. NVOF was replaced by a
  stand-in; real NVOF vectors differ.
- At half resolution (forced, or at 58+ real FPS) objects narrower than
  8 pixels can still lose pieces during fast turns.
- The default budget doubles: in a GPU-bound game, frame generation may take
  up to 20% of each real frame's time. `GpuBudget=10` restores Fix25's limit
  (and its half-resolution flow in such games).
- Reports from the other repository's issue tracker could not be read from
  this session.

Please send `nvsmooth30.log` from Fix26: look for `flow=high (SLOW)` or
`flow=medium` staying put at about 30 FPS, and `occlusion_aware_v10`.
