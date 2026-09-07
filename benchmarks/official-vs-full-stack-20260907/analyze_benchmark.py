"""Analyze completed native runs without loading a model or changing evidence."""
from pathlib import Path
import argparse,csv,hashlib,json,statistics
import numpy as np

VOCAB=129280
STEPS=128
FRONTIERS=[32,512,2048,8192,32768,131072,262016]
ORDER=['0-stock','1-full','2-full','3-stock']

def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()

def rows(p):
    with p.open() as f:return list(csv.DictReader(f))

def vectors(p):
    assert p.stat().st_size%(VOCAB*4)==0,str(p)
    return np.memmap(p,dtype='<f4',mode='r').reshape(-1,VOCAB)

def compare(a,b):
    av,bv=vectors(a),vectors(b)
    assert av.shape==bv.shape,(str(a),str(b))
    total=neq=argmax_neq=0
    max_abs=max_rel=ss=0.
    for x,y in zip(av,bv):
        assert np.isfinite(x).all() and np.isfinite(y).all()
        d=x.astype(np.float64)-y.astype(np.float64)
        total+=x.size
        neq+=int(np.count_nonzero(x.view(np.uint32)!=y.view(np.uint32)))
        argmax_neq+=int(np.argmax(x)!=np.argmax(y))
        max_abs=max(max_abs,float(np.abs(d).max()))
        max_rel=max(max_rel,float((np.abs(d)/np.maximum(1.,np.maximum(np.abs(x),np.abs(y)))).max()))
        ss+=float(d@d)
    return dict(elements=total,bitwise_different=neq,bitwise_equal=neq==0,
        max_abs=max_abs,max_relative_with_unit_floor=max_rel,rmse=(ss/total)**.5,
        vectors=av.shape[0],argmax_different=argmax_neq)

def nll(trace,tokens,pos):
    a=vectors(trace)
    assert a.shape==(STEPS+1,VOCAB),a.shape
    result=[]
    for step in range(STEPS):
        x=a[step].astype(np.float64)
        peak=x.max()
        result.append(float(peak+np.log(np.exp(x-peak).sum())-x[tokens[pos+step]]))
    return result

def summarize_timing(base, order=None):
    order = ORDER if order is None else order
    assert order in (ORDER, ORDER[:2]), order
    stock_names = [n for n in order if n.endswith("stock")]
    full_names = [n for n in order if n.endswith("full")]
    out={}
    for kind,field in [('decode','steady_tps'),('suffix','tps'),('prefill','tps')]:
        by_run={}
        for name in order:
            data=rows(base/name/(kind+'.csv'))
            if kind!='prefill':data=[r for r in data if int(r['warmup'])==0]
            assert sorted(set(int(r['context']) for r in data))==FRONTIERS
            grouped={}
            for pos in FRONTIERS:
                selected=[r for r in data if int(r['context'])==pos]
                assert len(selected)==(1 if kind=='prefill' else 4)
                vals=[float(r[field]) for r in selected]
                assert all(x>0 and np.isfinite(x) for x in vals)
                row=dict(median_tps=statistics.median(vals),minimum_tps=min(vals),maximum_tps=max(vals),trial_tps=vals)
                if kind=='decode':
                    row['median_restore_ms']=1000*statistics.median(float(r['restore_seconds']) for r in selected)
                    row['median_first_token_ms']=1000*statistics.median(float(r['first_seconds']) for r in selected)
                    row['median_all_token_tps']=statistics.median(STEPS/float(r['decode_seconds']) for r in selected)
                if kind=='decode':
                    assert all(int(x['tokens'])==STEPS for x in selected)
                elif kind=='suffix':
                    expected=min(STEPS,262144-pos-1)
                    assert all(int(x['new_tokens'])==expected for x in selected)
                    row['new_tokens']=expected
                else:
                    row['new_tokens']=int(selected[0]['new_tokens'])
                grouped[str(pos)]=row
            by_run[name]=grouped
        aggregated={}
        for pos in FRONTIERS:
            p=str(pos)
            stock=statistics.mean(by_run[n][p]['median_tps'] for n in stock_names)
            full=statistics.mean(by_run[n][p]['median_tps'] for n in full_names)
            paired=[100*(by_run[b][p]['median_tps']/by_run[a][p]['median_tps']-1) for a,b in zip(stock_names,full_names)]
            aggregated[p]=dict(stock_tps=stock,full_tps=full,throughput_gain_percent=100*(full/stock-1),
                time_reduction_percent=100*(1-stock/full),paired_gain_percent=paired,
                stock_repeat_change_percent=None if len(order)==2 else 100*(by_run['3-stock'][p]['median_tps']/by_run['0-stock'][p]['median_tps']-1),
                full_repeat_change_percent=None if len(order)==2 else 100*(by_run['2-full'][p]['median_tps']/by_run['1-full'][p]['median_tps']-1))
        out[kind]=dict(process_results=by_run,summary=aggregated)
    return out

def analyze(base,out,pair=False):
    order = ORDER[:2] if pair else ORDER
    completion = base/("pair-complete.json" if pair and (base/"pair-complete.json").exists() else "benchmark-complete.json")
    done=json.loads(completion.read_text())
    assert len(done["process_results"])==len(order)
    assert done['passed']
    tokens=None
    for name in order:
        arm=base/name
        assert json.loads((arm/'complete.json').read_text())['passed']
        for file,row in json.loads((arm/'captured-files.json').read_text()).items():
            p=arm/file
            assert p.stat().st_size==row['bytes'] and sha(p)==row['sha256'],str(p)
        t=np.fromfile(arm/'corpus.i32',dtype='<i4')
        assert t.shape==(262144,) and (t>=0).all() and (t<VOCAB).all()
        if tokens is None:tokens=t
        else:assert np.array_equal(tokens,t)
    result=dict(upstream=done['upstream'],candidate=done['candidate'],order=order,
        method=('One process per build; median of four timed trials per shape after two warmups. No independent process repeat or reversed order was run. ' if pair else 'Mean of two independent process medians per build; four timed trials per shape after two warmups. ')+'Prefill sweep is one observation per shape per process. Decode excludes first-token and snapshot restore time; both are separately recorded.',
        scope='Complete runtime stack versus pristine upstream; not individual-PR attribution. Fixed teacher tokens. These small held-out continuations do not establish general model quality.',
        timing=summarize_timing(base,order),numerical={},nll={})
    comparisons=[('pair_ab','0-stock','1-full')] if pair else [('stock_repeat','0-stock','3-stock'),('full_repeat','1-full','2-full'),('pair_ab','0-stock','1-full'),('pair_ba','3-stock','2-full')]
    for label,a,b in comparisons:
        comparison={}
        files=sorted(p.name for p in (base/a).glob('*.f32'))
        assert files==sorted(p.name for p in (base/b).glob('*.f32'))
        for file in files:comparison[file]=compare(base/a/file,base/b/file)
        result['numerical'][label]=comparison
        print('Compared',label,len(files),'complete vectors files',flush=True)
    for name in order:
        by_pos={str(pos):nll(base/name/('trace-'+str(pos)+'.f32'),tokens,pos) for pos in FRONTIERS}
        values=[x for v in by_pos.values() for x in v]
        result['nll'][name]=dict(token_count=len(values),mean_nll=statistics.mean(values),
            frontier_mean_nll={p:statistics.mean(v) for p,v in by_pos.items()},token_nll=by_pos)
    with out.open('x') as f:json.dump(result,f,indent=2);f.write('\n')
    print('PASS',out,flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('evidence',type=Path);p.add_argument('output',type=Path);p.add_argument('--pair',action='store_true')
    a=p.parse_args();analyze(a.evidence,a.output,a.pair)
