"""Build the test cases once, run a shader through harness.exe, score it.

usage: python3 run.py build
       python3 run.py score <label> <shader.hlsl> [norefine]
       python3 run.py compare <labelA> <labelB>
"""
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image

import scenes

HERE = os.path.dirname(os.path.abspath(__file__))
CASES = os.path.join(HERE, 'cases')
RESULTS = os.path.join(HERE, 'results')
MODELS = ['bm', 'gt', 'blend', 'noisy']
WRONG = 0.1  # max-channel error counted as a wrong pixel


def to8(x):
    return (np.clip(x, 0, 1) * 255 + 0.5).astype(np.uint8)


def save_rgba(path, rgb):
    a = np.concatenate([to8(rgb), np.full(rgb.shape[:2] + (1,), 255, np.uint8)], 2)
    a.tofile(path)


def build():
    rng = np.random.default_rng(11)
    os.makedirs(CASES, exist_ok=True)
    lines = []
    for name, (layers, exposure) in scenes.scenes().items():
        for model in MODELS:
            d = os.path.join(CASES, f'{name}__{model}')
            os.makedirs(d, exist_ok=True)
            c = scenes.build_case(name, layers, exposure, model, rng)
            save_rgba(os.path.join(d, 'prev.raw'), c['prev'])
            save_rgba(os.path.join(d, 'cur.raw'), c['cur'])
            np.save(os.path.join(d, 'mid.npy'), to8(c['mid']))
            np.save(os.path.join(d, 'band.npy'), c['band'])
            c['fwd'].tofile(os.path.join(d, 'fwd.raw'))
            c['bwd'].tofile(os.path.join(d, 'bwd.raw'))
            lines.append(f'{d} {scenes.W} {scenes.H}')
            print('built', name, model, flush=True)
    with open(os.path.join(CASES, 'list.txt'), 'w') as f:
        f.write('\n'.join(lines) + '\n')


def score(label, shader, extra=None):
    env = dict(os.environ, WINEPREFIX=os.path.join(HERE, '..', 'wpfx'), WINEDEBUG='-all', DISPLAY=':99')
    cmd = ['wine', os.path.join(HERE, 'harness.exe'), 'run', os.path.abspath(shader), os.path.join(CASES, 'list.txt')]
    if extra:
        cmd.append(extra)
    p = subprocess.run(cmd, cwd=HERE, env=env, capture_output=True, text=True)
    if 'RUN OK' not in p.stdout:
        print(p.stdout[-3000:], p.stderr[-3000:])
        raise SystemExit('harness failed')
    out_dir = os.path.join(RESULTS, label)
    os.makedirs(out_dir, exist_ok=True)
    res = {}
    for line in open(os.path.join(CASES, 'list.txt')):
        d = line.split()[0]
        name = os.path.basename(d)
        out = np.fromfile(os.path.join(d, 'out.raw'), np.uint8).reshape(scenes.H, scenes.W, 4)[..., :3]
        mid = np.load(os.path.join(d, 'mid.npy'))
        band = np.load(os.path.join(d, 'band.npy'))
        err = np.abs(out.astype(np.float32) - mid.astype(np.float32)).max(2) / 255
        wrong = err > WRONG
        res[name] = dict(wrong=int(wrong.sum()), band_wrong=int((wrong & band).sum()),
                         mae=float(np.abs(out.astype(np.float32) - mid).mean() / 255),
                         psnr=float(10 * np.log10(1 / max(1e-10, (((out.astype(np.float32) - mid) / 255) ** 2).mean()))))
        Image.fromarray(out).save(os.path.join(out_dir, name + '.png'))
        np.save(os.path.join(out_dir, name + '.npy'), out)
    json.dump(res, open(os.path.join(out_dir, 'scores.json'), 'w'), indent=1)
    tot = sum(r['wrong'] for r in res.values())
    print(f'{label}: total wrong {tot}, band wrong {sum(r["band_wrong"] for r in res.values())}, '
          f'mean PSNR {np.mean([r["psnr"] for r in res.values()]):.2f}')
    return res


def compare(a, b):
    ra = json.load(open(os.path.join(RESULTS, a, 'scores.json')))
    rb = json.load(open(os.path.join(RESULTS, b, 'scores.json')))
    print(f'{"case":34s} {"wrong " + a:>14s} {"wrong " + b:>14s}   {"psnr " + a:>10s} {"psnr " + b:>10s}')
    for k in ra:
        flag = ''
        if rb[k]['wrong'] > ra[k]['wrong'] * 1.05 + 20:
            flag = '  WORSE'
        elif rb[k]['wrong'] < ra[k]['wrong'] * 0.95 - 20:
            flag = '  better'
        print(f'{k:34s} {ra[k]["wrong"]:14d} {rb[k]["wrong"]:14d}   {ra[k]["psnr"]:10.2f} {rb[k]["psnr"]:10.2f}{flag}')
    for m in MODELS:
        sa = sum(v['wrong'] for k, v in ra.items() if k.endswith('__' + m))
        sb = sum(v['wrong'] for k, v in rb.items() if k.endswith('__' + m))
        print(f'  flow model {m:6s}: {sa:7d} -> {sb:7d} ({(sb - sa) / max(sa, 1) * 100:+.1f}%)')
    ta = sum(v['wrong'] for v in ra.values())
    tb = sum(v['wrong'] for v in rb.values())
    pa = np.mean([v['psnr'] for v in ra.values()])
    pb = np.mean([v['psnr'] for v in rb.values()])
    print(f'TOTAL wrong {ta} -> {tb} ({(tb - ta) / max(ta, 1) * 100:+.1f}%), mean PSNR {pa:.2f} -> {pb:.2f}')


if __name__ == '__main__':
    if sys.argv[1] == 'build':
        build()
    elif sys.argv[1] == 'score':
        score(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None)
    elif sys.argv[1] == 'compare':
        compare(sys.argv[2], sys.argv[3])
