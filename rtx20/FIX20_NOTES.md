# Fix 20 — GPU-bound games (God of War, RTX 2060)

Runtime version: `2.8.4-rtx20-rtx30-dx12-preview2-fix20-test`.

Everything in Fix19 is included. This is a test build: nothing here has run
on Windows or a GPU.

## The report

"My GPU can hit a solid 70 FPS, but it drops to 35 here and doubles it with
fake frames just to reach 70." `nvsmooth30_46.log` (Fix16, God of War,
RTX 2060, 1080p, 144 Hz, uncapped, DX11, 10-bit) confirms it:

- **Fix16 works in God of War.** The 10-bit path runs and there are no
  errors. The repeated "backend ready" lines at start are resizes during
  loading.
- **The real rate while generating was 35–45 FPS**, against about 70
  native. Displayed: about 70–90, no better than native but with twice the
  latency.
- **Why so much for a pair costing only about 2–4 ms of GPU time:**
  - The DX11 path waited, inside the game's Present, for the GPU to show
    the generated frame, so the frames could be evenly spaced.
  - In an uncapped, GPU-bound game the GPU is a frame behind. The wait
    therefore drained the GPU every frame: the game could not prepare its
    next frame while the GPU worked, so CPU and GPU time added up instead
    of overlapping. The rate roughly halved.
- **Stutter every ~30 s.** The budget retried the SLOW flow preset (about
  20 ms per pair) because the lowered real rate was under 40 FPS. Fix17
  already stopped this by using the native rate for that rule.
- **Nonsense cost measurements at start** (MEDIUM "166 ms") pushed the flow
  to half resolution.
- **The Fix17 guard would not have caught it.** It paused only if the
  displayed rate was not 10% above native, and 40 real / 80 displayed
  passes that check.

## Changes

- **No GPU drain when GPU-bound.** When waiting for the generated frame to
  become visible averages over 3 ms, spacing is timed from the Present call
  instead. The log says `GPU-bound: ...`. One pair in 120 still measures,
  so it switches back when the game is no longer GPU-bound.
- **Base-rate floor.** Generation also pauses when the real rate falls
  below 65% of the native rate (`MinimumBaseRate`, default 65; `0` = off).
  The guard line now shows real, displayed and native rates.
- **Budget.** GPU timings over 50 ms (warm-up, loading) are ignored.

## Policy model

- **God of War-like** (native ~70, generating ~40 real): paused, running at
  native ~70. With `MinimumBaseRate=0`, it keeps generating as Fix17 did.
- **A cheaper pair** (~55 real of 70 native): keeps generating (about 110
  displayed).
- **Earlier cases unchanged:** capped 30, RE3, the uncapped heavy game
  (39 of 57 native, 68%), VSync pairs, Genshin laptop.

## What to expect in God of War on an RTX 2060

- **Uncapped at ~70:** generation either keeps at least ~46 real FPS
  (about 90+ displayed) or pauses by itself and leaves native 70. It no
  longer turns 70 into 35 + 35.
- **For real gains, cap the game** a little below what it holds in heavy
  scenes, e.g. 50 FPS in RTSS or in-game. The GPU then has spare time for
  generation: 50 real → 100 displayed with even spacing.
- **Check the log** for `native rate:`, a `guard:` line if it paused, and
  `GPU-bound:` if the wait was skipped.

## Limits

- Timed from the Present call, the spacing in GPU-bound games is less even
  than GPU-timed spacing. The generated and real frames may be shown for
  unequal times.
- The floor compares rates, not frame times. A game that swings between
  heavy and light scenes may pause and resume generation (retries back off
  as in Fix17).
