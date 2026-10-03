"""Synthetic frame-interpolation scenes with exact midpoint ground truth.

Every scene is rendered at 2x and box-downsampled, with integer per-frame
motions at 1x, so the t=0.5 frame is exact (half-pixel midpoints included)
and object outlines are antialiased like real game frames.

Flow for the shader comes from one of these NVOF stand-ins, on its 4x4 grid
in S10.5 (1/32 px):
  bm     regularised coarse-to-fine block matcher on the frames themselves
  gt     ideal: the majority true motion of each cell
  blend  true motion blurred across outlines (NVOF regularisation look)
  noisy  blend plus vector noise
"""
import numpy as np
from scipy import ndimage
from skimage import data, transform

W, H = 384, 216
S = 2  # supersampling


def _tex(name, scale=1.0):
    img = getattr(data, name)()[..., :3].astype(np.float32) / 255
    if scale != 1.0:
        img = transform.rescale(img, scale, channel_axis=2, anti_aliasing=True).astype(np.float32)
    return img


_cache = {}


def tex(name, scale=1.0):
    k = (name, scale)
    if k not in _cache:
        _cache[k] = _tex(name, scale)
    return _cache[k]


def big(img, h, w):
    """Mirror-tile an image to at least h x w."""
    reps = (h // img.shape[0] + 2, w // img.shape[1] + 2)
    t = np.concatenate([np.concatenate([img, img[:, ::-1]], 1)] * ((reps[1] + 1) // 2), 1)
    t = np.concatenate([t, t[::-1]] * ((reps[0] + 1) // 2), 0)
    return t[:h, :w]


class Layer:
    """A textured layer. mask(yy, xx) gives coverage in layer-local 2x coords
    (None = full-screen). motion is (dx, dy) in 1x pixels per frame."""

    def __init__(self, texture, motion, mask=None, origin=(0, 0), gain=1.0, opacity=1.0):
        self.opacity = opacity
        self.motion = np.array(motion, np.int64)
        self.mask = mask
        self.origin = origin
        pad = 2 * S * (np.abs(self.motion).max() + 8)
        self.pad = int(pad)
        self.texture = big(texture, H * S + 2 * self.pad, W * S + 2 * self.pad)
        self.gain = gain

    def shift(self, t):
        return (self.motion * S * t).round().astype(np.int64)  # 2x pixels

    def render(self, t):
        sx, sy = self.shift(t)
        p = self.pad
        img = self.texture[p - sy:p - sy + H * S, p - sx:p - sx + W * S]
        if self.mask is None:
            a = np.ones((H * S, W * S), np.float32)
        else:
            yy, xx = np.mgrid[0:H * S, 0:W * S].astype(np.float32)
            a = self.mask(yy - sy - self.origin[1] * S, xx - sx - self.origin[0] * S).astype(np.float32)
        return img, a * self.opacity


def down(x):
    if x.ndim == 3:
        return x.reshape(H, S, W, S, x.shape[2]).mean((1, 3))
    return x.reshape(H, S, W, S).mean((1, 3))


def render(layers, t, exposure=1.0):
    out = np.zeros((H * S, W * S, 3), np.float32)
    ids = np.full((H * S, W * S), -1, np.int64)
    for i, L in enumerate(layers):
        img, a = L.render(t)
        out = out * (1 - a[..., None]) + img * a[..., None]
        ids[a > 0.25] = i
    rgb = np.clip(down(out) * exposure, 0, 1)
    ids1 = ids[S // 2::S, S // 2::S]
    return rgb, ids1


# ---- shapes (2x local coords) ----
def rect(x0, y0, w, h, angle=0.0):
    c, s = np.cos(angle), np.sin(angle)
    cx, cy = (x0 + w / 2) * S, (y0 + h / 2) * S

    def m(yy, xx):
        u = (xx - cx) * c + (yy - cy) * s
        v = -(xx - cx) * s + (yy - cy) * c
        return (np.abs(u) <= w * S / 2) & (np.abs(v) <= h * S / 2)
    return m


def ellipse(cx, cy, rx, ry):
    def m(yy, xx):
        return ((xx - cx * S) / (rx * S)) ** 2 + ((yy - cy * S) / (ry * S)) ** 2 <= 1
    return m


def union(*ms):
    def m(yy, xx):
        r = ms[0](yy, xx)
        for q in ms[1:]:
            r = r | q(yy, xx)
        return r
    return m


def crest(cx, top, base_w, height):
    """A tapering spike (helmet crest, sword tip) pointing up."""
    def m(yy, xx):
        y = yy / S
        x = xx / S
        frac = (y - top) / height
        half = base_w / 2 * frac
        return (frac >= 0) & (frac <= 1) & (np.abs(x - cx) <= half)
    return m


def glyphs(x0, y0, text_w, rows=1):
    """Blocky HUD 'text': strokes 2 px wide."""
    rng = np.random.default_rng(7)
    rects = []
    for r in range(rows):
        x = x0
        while x < x0 + text_w:
            gw = rng.integers(5, 8)
            for k in range(rng.integers(2, 4)):
                if rng.random() < 0.5:
                    rects.append(rect(x + rng.integers(0, gw - 2), y0 + r * 12, 2, 9))
                else:
                    rects.append(rect(x, y0 + r * 12 + rng.integers(0, 8), gw, 2))
            x += gw + 2
    return union(*rects)


def flat(color):
    t = np.zeros((64, 64, 3), np.float32)
    t[:] = color
    return t


def gradient_sky():
    y = np.linspace(0, 1, 600)[:, None, None]
    top = np.array([0.35, 0.55, 0.85], np.float32)
    bot = np.array([0.75, 0.82, 0.9], np.float32)
    g = top * (1 - y) + bot * y
    return np.repeat(g, 800, 1).astype(np.float32)


def scenes():
    """name -> (layers, exposure gain of the current frame)."""
    S_ = {}
    S_['pan'] = ([Layer(tex('astronaut'), (24, 0))], 1.0)
    S_['pan_odd_diag'] = ([Layer(tex('coffee'), (13, 5))], 1.0)
    S_['fast_vertical'] = ([Layer(tex('rocket'), (3, 44))], 1.0)
    # Camera turn behind a nearly screen-fixed character with sword and hilt.
    S_['thin_static_over_pan'] = ([
        Layer(tex('chelsea'), (30, 0)),
        Layer(tex('immunohistochemistry'), (0, 0), union(rect(170, 40, 4, 120, 0.45), rect(150, 60, 3, 90, -0.3),
                                                         ellipse(176, 46, 7, 7))),
    ], 1.0)
    # MHW helmet crest: head with a tapering crest moving 2 px, scene 20 px.
    S_['crest'] = ([
        Layer(tex('hubble_deep_field', 0.5), (20, 0)),
        Layer(tex('cat'), (2, 0), union(ellipse(190, 120, 26, 30), crest(190, 40, 10, 60), crest(205, 60, 6, 40))),
    ], 1.0)
    # Character orbit: body moving against the background, blade crossing.
    S_['character_orbit'] = ([
        Layer(tex('coffee'), (26, 2)),
        Layer(tex('astronaut'), (-6, 0), union(ellipse(200, 110, 34, 70), ellipse(200, 40, 16, 18))),
        Layer(tex('rocket'), (-6, 0), rect(225, 30, 4, 130, 0.25)),
    ], 1.0)
    # A thin pole and a wire crossing a static scene (camera still).
    S_['crossing_pole'] = ([
        Layer(tex('chelsea'), (0, 0)),
        Layer(flat((0.15, 0.12, 0.1)), (18, 0), rect(150, 0, 3, 216)),
        Layer(flat((0.05, 0.05, 0.05)), (0, 10), rect(0, 80, 384, 2)),
    ], 1.0)
    # HUD text and a crosshair over a pan.
    S_['hud_over_pan'] = ([
        Layer(tex('astronaut'), (28, 0)),
        Layer(flat((0.95, 0.95, 0.9)), (0, 0), union(glyphs(20, 20, 120, 2), glyphs(260, 180, 90))),
        Layer(flat((0.9, 0.2, 0.2)), (0, 0), union(rect(190, 100, 2, 16), rect(184, 107, 16, 2))),
    ], 1.0)
    # Antialiased HUD text (half-pixel placement), a translucent subtitle
    # panel and a translucent crosshair over a pan.
    S_['hud_aa_translucent'] = ([
        Layer(tex('coffee'), (22, 4)),
        Layer(flat((0.0, 0.0, 0.0)), (0, 0), rect(40, 168, 300, 30), opacity=0.5),
        Layer(flat((0.95, 0.92, 0.8)), (0, 0), union(glyphs(50.5, 172.5, 270, 2), glyphs(20.5, 20.5, 110))),
        Layer(flat((0.2, 1.0, 0.3)), (0, 0), union(rect(190.5, 92.5, 2, 18), rect(182.5, 100.5, 18, 2)), opacity=0.6),
    ], 1.0)
    S_['exposure_pan'] = ([Layer(tex('coffee'), (16, 0))], 1.12)
    # Parallax: near foliage-like blobs over a slower far layer.
    rng = np.random.default_rng(3)
    blobs = union(*[ellipse(float(rng.integers(0, 384)), float(rng.integers(0, 216)), float(rng.integers(6, 20)),
                            float(rng.integers(6, 20))) for _ in range(22)])
    S_['parallax'] = ([
        Layer(tex('rocket'), (8, 0)),
        Layer(tex('immunohistochemistry'), (30, 0), blobs),
    ], 1.0)
    # Roofline over a smooth sky, vertical camera motion.
    roof = lambda yy, xx: (yy / S) > 120 + 25 * np.abs(np.sin(xx / S / 40.0)) + 8 * ((xx / S).astype(np.int64) % 60 < 6)
    S_['roof_over_sky'] = ([
        Layer(gradient_sky(), (0, 18)),
        Layer(tex('chelsea'), (0, 18), roof),
    ], 1.0)
    return S_


# ---- flow ----
def true_flow(layers, ids, forward):
    """Per-pixel true motion at the frame's own pixels (forward: previous
    frame, motion to current; backward: current frame, motion to previous)."""
    f = np.zeros(ids.shape + (2,), np.float32)
    for i, L in enumerate(layers):
        f[ids == i] = L.motion if forward else -L.motion
    return f


def cells_from_pixels(f, mode):
    gh, gw = (H + 3) // 4, (W + 3) // 4
    pad = np.pad(f, ((0, gh * 4 - H), (0, gw * 4 - W), (0, 0)), mode='edge')
    blocks = pad.reshape(gh, 4, gw, 4, 2).transpose(0, 2, 1, 3, 4).reshape(gh, gw, 16, 2)
    if mode == 'mean':
        return blocks.mean(2)
    # majority
    out = np.zeros((gh, gw, 2), np.float32)
    for y in range(gh):
        for x in range(gw):
            v, c = np.unique(blocks[y, x], axis=0, return_counts=True)
            out[y, x] = v[c.argmax()]
    return out


def blend(cells, sigma):
    return np.stack([ndimage.gaussian_filter(cells[..., k], sigma, mode='nearest') for k in range(2)], -1)


def block_match(a, b, radius_cells=18, lam=0.08):
    """Regularised coarse-to-fine block matcher (8x8 support per 4x4 cell)
    finding where content of `a` went in `b`. Returns cell flow in px."""
    gh, gw = (H + 3) // 4, (W + 3) // 4
    ga = a.mean(2)
    gb = b.mean(2)
    levels = [(4, ndimage.zoom(ga, 0.25, order=1), ndimage.zoom(gb, 0.25, order=1)),
              (2, ndimage.zoom(ga, 0.5, order=1), ndimage.zoom(gb, 0.5, order=1)),
              (1, ga, gb)]
    v = np.zeros((gh, gw, 2), np.float32)
    cy, cx = np.mgrid[0:gh, 0:gw]
    for li, (sc, A, B) in enumerate(levels):
        h, w = A.shape
        rad = radius_cells if li == 0 else 2
        Ap = np.pad(A, 64, mode='edge')
        Bp = np.pad(B, 64, mode='edge')
        ccx = (cx * 4 + 1.5) / sc + 64
        ccy = (cy * 4 + 1.5) / sc + 64
        half = max(2, int(4 / sc))
        oy, ox = np.mgrid[-half:half, -half:half]
        py = np.clip((ccy[..., None, None] + oy + 0.5).astype(np.int64), 0, Ap.shape[0] - 1)
        px = np.clip((ccx[..., None, None] + ox + 0.5).astype(np.int64), 0, Ap.shape[1] - 1)
        patchA = Ap[py, px]
        base = np.round(v / sc).astype(np.int64)
        best = np.full((gh, gw), np.inf)
        bestd = np.zeros((gh, gw, 2), np.int64)
        med = np.stack([ndimage.median_filter(base[..., k], 3, mode='nearest') for k in range(2)], -1)
        for dy in range(-rad, rad + 1):
            for dx in range(-rad, rad + 1):
                d = base + np.array([dx, dy])
                qy = np.clip(py + d[..., 1, None, None], 0, Bp.shape[0] - 1)
                qx = np.clip(px + d[..., 0, None, None], 0, Bp.shape[1] - 1)
                cost = np.abs(patchA - Bp[qy, qx]).mean((2, 3))
                cost = cost + (lam * 0.1 * np.abs(d - med).sum(-1) if li > 0 else 0.0)
                m = cost < best
                best[m] = cost[m]
                bestd[m] = d[m]
        v = bestd.astype(np.float32) * sc
        # regularisation: NVOF-like smoothing of the field
        v = np.stack([ndimage.median_filter(v[..., k], 3, mode='nearest') for k in range(2)], -1)
    # light blend across outlines, as hardware flow does
    return 0.6 * v + 0.4 * blend(v, 0.8)


def quantize(cells):
    q = np.clip(np.round(cells * 32), -32768, 32767).astype(np.int16)
    return q


def build_case(name, layers, exposure, model, rng):
    prev, ids0 = render(layers, 0.0)
    mid, idsm = render(layers, 0.5, exposure=np.sqrt(exposure))
    cur, ids1 = render(layers, 1.0, exposure=exposure)
    if model == 'bm':
        fwd = block_match(prev, cur)
        bwd = block_match(cur, prev)
    else:
        fwd = cells_from_pixels(true_flow(layers, ids0, True), 'majority')
        bwd = cells_from_pixels(true_flow(layers, ids1, False), 'majority')
        if model in ('blend', 'noisy'):
            fwd, bwd = blend(fwd, 1.2), blend(bwd, 1.2)
        if model == 'noisy':
            fwd = fwd + rng.normal(0, 0.8, fwd.shape)
            bwd = bwd + rng.normal(0, 0.8, bwd.shape)
    # Regions for the metric: pixels near anything that is not the backmost layer.
    fg = (idsm > 0) | (ids0 > 0) | (ids1 > 0)
    band = ndimage.binary_dilation(fg, iterations=4)
    return dict(prev=prev, mid=mid, cur=cur, fwd=quantize(fwd), bwd=quantize(bwd), band=band)
