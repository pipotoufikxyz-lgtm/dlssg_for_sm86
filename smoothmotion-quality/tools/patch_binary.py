"""Write the improved synthesis shader into a SmoothMotion Fix28 binary.

The shader is embedded as text and passed to D3DCompile with its exact length
(0x12ffb = 77819 bytes) as an immediate, so the replacement has the same length.
The shader cache key hashes the source, so no stale Fix28 bytecode is reused.
"""
import sys
src, dst, orig_shader, new_shader = sys.argv[1:5]
data = bytearray(open(src, 'rb').read())
old = open(orig_shader, 'rb').read()
new = open(new_shader, 'rb').read()
assert len(old) == len(new) == 77819, (len(old), len(new))
assert data.count(old) == 1, 'shader not found exactly once'
start = data.find(old)
data[start:start + len(old)] = new
edits = [(b'2.8.5-rtx20-rtx30-dx12-preview2-fix28-test', b'2.8.5-rtx20-rtx30-dx12-preview2-fix28-qual', 4),
         (b'occlusion_aware_v12', b'occlusion_aware_v13', 1)]
spans = [(start, start + len(old))]
for a, b, n in edits:
    assert len(a) == len(b)
    assert data.count(a) == n, (a, data.count(a))
    i = 0
    while True:
        i = data.find(a, i)
        if i < 0:
            break
        data[i:i + len(a)] = b
        spans.append((i, i + len(a)))
        i += len(a)
orig = open(src, 'rb').read()
assert len(orig) == len(data)
changed = [i for i in range(len(orig)) if orig[i] != data[i]]
assert all(any(s <= i < e for s, e in spans) for i in changed), 'unexpected change'
open(dst, 'wb').write(data)
print(f'{dst}: {len(changed)} bytes changed, all inside the shader and version strings')
