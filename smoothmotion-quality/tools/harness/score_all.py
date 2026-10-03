import sys, os, run, importlib
which=sys.argv[1]; pairs=[a.split('=') for a in sys.argv[2:]]
if which=='held':
    import heldout
    run.CASES=os.path.join(run.HERE,'hcases'); run.RESULTS=os.path.join(run.HERE,'hresults')
if pairs and pairs[0][0]=='BUILD':
    run.build(); pairs=pairs[1:]
for lab,f in pairs: run.score(lab,f)
