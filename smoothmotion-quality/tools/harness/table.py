import json, numpy as np, subprocess, os
NAMES={'pan':'Camera pan','pan_odd_diag':'Diagonal pan (half-pixel)','fast_vertical':'Fast vertical pan (44 px)',
'thin_static_over_pan':'Sword hilts over camera turn','crest':'Helmet crest over starfield','character_orbit':'Character + blade, camera orbit',
'crossing_pole':'Pole + wire crossing a still view','hud_over_pan':'HUD text over pan','hud_aa_translucent':'Antialiased/translucent HUD + crosshair',
'exposure_pan':'Pan with exposure change','parallax':'Parallax foliage','roof_over_sky':'Roofs over sky',
'h_pan_left_up':'Low-contrast pan','h_slow_pan':'Slow pan','h_very_fast':'Very fast pan (61 px)','h_static':'Still scene',
'h_runner':'Running character','h_sword_swing':'Sword swing','h_foliage':'Foliage','h_night_lights':'Night lights / stars',
'h_subtitles':'Subtitles over pan','h_fade_exposure':'Pan + fade','h_poles_fence':'Fence posts'}
labs=['fix24','fix28','v36']
out=[]
for setname,res,title in [('dev','results','Development set (12 scenes x 4 flow models)'),('held','hresults','Held-out set (11 scenes x 4 flow models, never tuned on)')]:
    R={l:json.load(open(f'{res}/{l}/scores.json')) for l in labs}
    sc={}
    for k in R['v36']:
        s=k.split('__')[0]; sc.setdefault(s,{l:[0,[]] for l in labs})
        for l in labs: sc[s][l][0]+=R[l][k]['wrong']; sc[s][l][1].append(R[l][k]['psnr'])
    out.append(f'\n### {title}\n\n| Scene | Fix24 wrong px | Fix28 wrong px | New wrong px | New vs Fix24 | PSNR Fix24 → New |\n|---|---|---|---|---|---|')
    for s,v in sorted(sc.items(),key=lambda t:-t[1]['fix24'][0]):
        a,b,c=v['fix24'][0],v['fix28'][0],v['v36'][0]
        pct=f'{(c-a)/a*100:+.0f}%' if a else '0'
        out.append(f'| {NAMES[s]} | {a:,} | {b:,} | {c:,} | {pct} | {np.mean(v["fix24"][1]):.1f} → {np.mean(v["v36"][1]):.1f} dB |')
    ta=sum(R['fix24'][k]['wrong'] for k in R['v36']); tb=sum(R['fix28'][k]['wrong'] for k in R['v36']); tc=sum(R['v36'][k]['wrong'] for k in R['v36'])
    pa,pb,pc=[np.mean([R[l][k]['psnr'] for k in R['v36']]) for l in labs]
    ma,mb,mc=[np.mean([R[l][k]['mae'] for k in R['v36']]) for l in labs]
    out.append(f'| **Total** | **{ta:,}** | **{tb:,}** | **{tc:,}** | **{(tc-ta)/ta*100:+.0f}%** | |')
    out.append(f'| **Mean PSNR** | **{pa:.2f} dB** | **{pb:.2f} dB** | **{pc:.2f} dB** | **{pc-pa:+.2f} dB** | |')
    out.append(f'| Mean abs. error | {ma:.4f} | {mb:.4f} | {mc:.4f} | {(mc-ma)/ma*100:+.0f}% | |')
# stress
cases=[l.split()[0] for l in open('stress_gt.txt')]
names={'gtfade_static_moderate':'Still scene, gentle fade','gtfade_static_strong':'Still scene, strong fade','gtfade_pan_moderate':'Pan, gentle fade','gtfade_pan_strong':'Pan, strong fade','gtflash_static':'Flash (brightness +60%)'}
res={}
for lab,f in [('fix24','shaders_fix24'),('fix28','shaders_fix28'),('v36','v36')]:
    subprocess.run(['wine','harness.exe','run',f'../work/{f}.hlsl','stress_gt.txt'],capture_output=True)
    for d in cases:
        o=np.fromfile(d+'/out.raw',np.uint8).reshape(216,384,4)[...,:3].astype(float); m=np.load(d+'/mid.npy').astype(float)
        res[(lab,os.path.basename(d))]=(int(((np.abs(o-m).max(2)/255)>0.1).sum()),10*np.log10(1/(((o-m)/255)**2).mean()))
out.append('\n### Fades and flashes (ideal flow)\n\n| Case | Fix24 | Fix28 | New |\n|---|---|---|---|')
for d in cases:
    n=os.path.basename(d); r=[res[(l,n)] for l in ['fix24','fix28','v36']]
    out.append(f'| {names[n]} | {r[0][0]:,} px / {r[0][1]:.1f} dB | {r[1][0]:,} px / {r[1][1]:.1f} dB | {r[2][0]:,} px / {r[2][1]:.1f} dB |')
open('../out/COMPARISON_TABLES.md','w').write('\n'.join(out)+'\n'); print('\n'.join(out))
