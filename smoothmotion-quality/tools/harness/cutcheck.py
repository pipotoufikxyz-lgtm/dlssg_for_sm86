import numpy as np, subprocess, sys
for lab in sys.argv[1:]:
    subprocess.run(['wine','harness.exe','run',f'../work/{lab}.hlsl','cuts.txt'],capture_output=True)
    res=[]
    for dd in ['cut','cut2']:
        o=np.fromfile(dd+'/out.raw',np.uint8).reshape(216,384,4)[...,:3].astype(float)
        c=np.fromfile(dd+'/cur.raw',np.uint8).reshape(216,384,4)[...,:3].astype(float); p=np.fromfile(dd+'/prev.raw',np.uint8).reshape(216,384,4)[...,:3].astype(float)
        bad=(np.abs(o-c).max(2)>25)&(np.abs(o-p).max(2)>25)&(np.abs(o-0.5*(c+p)).max(2)>25)
        res.append(f'garbage {bad.mean()*100:.1f}%')
    print(lab,'scene cuts:',' | '.join(res))
