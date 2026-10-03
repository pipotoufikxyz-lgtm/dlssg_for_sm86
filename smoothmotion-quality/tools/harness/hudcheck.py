import numpy as np, importlib, sys
labs=sys.argv[1:]
for setname,case,base,res in [('dev','hud_over_pan','cases','results'),('dev','hud_aa_translucent','cases','results'),('held','h_subtitles','hcases','hresults')]:
    import scenes as S; importlib.reload(S)
    if setname=='held':
        import heldout as H; S.scenes=H.heldout
    L,_=S.scenes()[case]; _,ids=S.render(L,0.5); hud=ids>=1
    tot=[0]*len(labs)
    for model in ['gt','bm','blend','noisy']:
        k=f'{case}__{model}'; m=np.load(f'{base}/{k}/mid.npy').astype(float)
        for i,lab in enumerate(labs): tot[i]+=int(((np.abs(np.load(f'{res}/{lab}/{k}.npy').astype(float)-m).max(2)/255>0.1)&hud).sum())
    print(f'{case:22s} wrong on HUD pixels (4 flows) ' + '  '.join(f'{l}={t}' for l,t in zip(labs,tot)))
