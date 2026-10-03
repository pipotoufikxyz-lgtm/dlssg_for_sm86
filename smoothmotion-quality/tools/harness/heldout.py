"""Held-out scenes: textures, motions and layouts not used while tuning."""
import numpy as np
import scenes as S
from scenes import Layer, tex, rect, ellipse, union, crest, glyphs, flat, gradient_sky

def heldout():
    H = {}
    H['h_pan_left_up'] = ([Layer(tex('retina', 0.3), (-17, -9))], 1.0)
    H['h_slow_pan'] = ([Layer(tex('cat'), (3, 1))], 1.0)
    H['h_very_fast'] = ([Layer(tex('immunohistochemistry'), (61, 0))], 1.0)
    H['h_static'] = ([Layer(tex('astronaut'), (0, 0))], 1.0)
    H['h_runner'] = ([
        Layer(tex('rocket'), (-14, 0)),
        Layer(tex('coffee'), (10, -2), union(ellipse(120, 120, 18, 45), ellipse(120, 62, 12, 13), rect(100, 110, 5, 60, 0.4), rect(135, 110, 5, 60, -0.4))),
    ], 1.0)
    H['h_sword_swing'] = ([
        Layer(tex('chelsea'), (12, 0)),
        Layer(flat((0.8, 0.8, 0.85)), (-20, 6), rect(230, 40, 3, 110, 0.7)),
        Layer(tex('astronaut'), (0, 0), ellipse(250, 150, 30, 50)),
    ], 1.0)
    rng = np.random.default_rng(99)
    leaves = union(*[ellipse(float(rng.integers(0, 384)), float(rng.integers(0, 216)), float(rng.integers(4, 12)), float(rng.integers(3, 9))) for _ in range(40)])
    H['h_foliage'] = ([Layer(tex('coffee'), (5, 0)), Layer(tex('cat'), (19, 3), leaves)], 1.0)
    H['h_night_lights'] = ([Layer(tex('hubble_deep_field', 0.7), (0, 26))], 1.0)
    H['h_subtitles'] = ([
        Layer(tex('chelsea'), (-25, 0)),
        Layer(flat((1.0, 1.0, 0.6)), (0, 0), union(glyphs(60.5, 185.5, 260, 1), glyphs(10, 10, 60))),
    ], 1.0)
    H['h_fade_exposure'] = ([Layer(tex('rocket'), (9, -4))], 0.88)
    H['h_poles_fence'] = ([
        Layer(tex('astronaut'), (22, 0)),
        Layer(flat((0.1, 0.1, 0.12)), (8, 0), union(*[rect(40 + 37 * i, 0, 2, 216) for i in range(9)])),
    ], 1.0)
    return H

S.scenes = heldout
