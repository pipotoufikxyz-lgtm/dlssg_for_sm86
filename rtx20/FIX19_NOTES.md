# Fix 19 — steady crosshairs and HUD during pans

Runtime version: `2.8.4-rtx20-rtx30-dx12-preview2-fix19-test`
(`artifact_guard=occlusion_aware_v7`).

Everything in Fix18 is included, for RTX 20 and RTX 30. This is a test build:
nothing here has run on Windows or a GPU.

## The recording

`Desktop_2026.09.27_-_22.29.35.01.mp4` shows a YouTube video of the RTX 30
mod (GP9, NVIDIA's model) in Assassin's Creed Origins:

- Copies of the crosshair's dot and dash pieces are dragged along with the
  camera pan.
- Pieces fade or vanish over bright walls.
- It looks like flicker at 60 FPS.

GP9's model cannot be changed. The same situation was tested on this
package's own backend, which RTX 30 now uses (Fix18).

## What the backend did (Fix18)

A new shader test puts a crosshair over a panning scene: two white dashes
and a dot with a dark outline, opaque or translucent, over textured or
near-white background.

- **Gentle pan:** the crosshair stayed whole, with no ghosts.
- **Fast pan** (34, 12 px per real frame): the crosshair stayed, but 480–551
  pixels of misplaced background appeared around it.
  - Cause: for pixels near the crosshair, one end of the motion path lands
    on the crosshair.
  - The crosshair is fixed on screen, so the two frames do not match there,
    and the pixel fell back to the unwarped next frame.
- **Translucent crosshairs** were not recognised as HUD at all. The scene
  shows through them, so they are never identical in both frames.

## Changes

- **Full-frame overlay mask.** A new pass marks static overlay detail for
  the whole frame, and a second pass grows the mask by two pixels to cover
  outlines. It uses the same test the shader used per pixel, plus a new
  case for translucent overlays: their edges stay the same in both frames
  even though their colour changes.
- **The scene behind the crosshair comes from the other frame.** When one
  end of a motion path lies on the mask, that part of the scene is taken
  from the frame where it is visible.
- **Scene revealed from behind the HUD is not "new content"**, so it is no
  longer frozen in place.
- **Cost.** Synthesis reads the mask instead of recomputing the test per
  pixel. The two new passes are small (8-bit textures, one test per pixel,
  then a 5x5 maximum).

## Results (shader model, true midpoint)

| Case (textured background) | Fix18 | Fix19 |
|---|---|---|
| Fast pan, opaque crosshair: misplaced pixels around it (of 1385) | 480 | 101 |
| Fast pan, 80% opacity: misplaced pixels / crosshair core kept (of 111) | 480 / 15 | 117 / 111 |
| Fast pan, 60% opacity: misplaced pixels / core kept | 480 / 9 | 248 / 71 |
| Gentle pan: outline pixels exact (of 232), opaque / 80% / 60% | 226 / 210 / 210 | 208 / 209 / 189 |
| Roof over flat sky (Fix15 test): roof pixels in sky | 1 | 1 |
| Witcher 3 real frames: roof slivers / HUD pixels altered | 9 / 376 | 8 / 371 |

On bright (near-white) backgrounds both builds keep the crosshair intact.
The gentle-pan outline is slightly less exact than in Fix18: the outline
now more often keeps the real frame's background (at most two pixels
wide). In exchange, see-through crosshairs no longer vanish in fast pans,
and far less misplaced background appears around them.

All 21 shader behaviour groups pass, including the new crosshair group.
Every earlier test gives the same or better numbers.

## Limits

- The remaining misplaced pixels in the fast-pan case sit within about four
  pixels of the crosshair. That is where the HUD protection keeps the real
  frame so that antialiased HUD text stays intact.
- Crosshairs that move or animate (spread, hit markers) are not static
  overlays and are interpolated like the scene.
- If the optical flow locks onto the crosshair itself (zero motion in the
  cells it covers), its outline is less clean (tested: 108 of 232 outline
  pixels exact). The crosshair itself stays whole.
