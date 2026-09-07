"""Recompute native and interleaved medians from the published CSVs."""
from pathlib import Path
import csv,json,statistics
root=Path(__file__).resolve().parent
result={}
for path in sorted((root/'raw').glob('*/*.csv')):
    if path.name not in ('decode.csv','causal.csv'): continue
    groups={}
    with path.open() as f:
        for row in csv.DictReader(f):
            if row['warmup']!='0': continue
            key=(int(row['context']),int(row.get('mode',0)))
            groups.setdefault(key,[]).append(float(row['steady_tps']))
    assert all(len(values)==4 for values in groups.values())
    result[str(path.relative_to(root))]=[dict(context=k[0],mode=k[1],trials=v,median=statistics.median(v)) for k,v in sorted(groups.items())]
print(json.dumps(result,indent=2))
