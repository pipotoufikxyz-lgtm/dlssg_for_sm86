"""Make the text embedded in the binary: the commented shader without comments,
indentation or blank lines, padded with spaces to Fix28's fixed length."""
import re, sys
src, dst, length = sys.argv[1], sys.argv[2], int(sys.argv[3])
s = open(src).read()
lines = []
for line in s.split('\n'):
    line = re.sub(r'//.*$', '', line).strip()
    assert '"' not in line, 'string literal in code: needs a real tokenizer'
    if line:
        lines.append(line)
header = '// SmoothMotion fix28-qua2 synthesis. Commented source: smoothmotion-quality/shader/shaders.hlsl (dlssg_for_sm86).\n'
out = header + '\n'.join(lines) + '\n'
assert len(out) <= length, (len(out), length)
out += ' ' * (length - len(out))
open(dst, 'w').write(out)
print(dst, 'code bytes', len(header + '\n'.join(lines)) , 'padded to', len(out))
