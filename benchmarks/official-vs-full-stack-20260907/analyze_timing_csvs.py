"""Summarize complete raw timing CSVs; model-run validation is separate."""
from pathlib import Path
import argparse,json
from analyze_benchmark import summarize_timing

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('evidence',type=Path,help='Parent of 0-stock, 1-full, 2-full and 3-stock')
    p.add_argument('output',type=Path)
    p.add_argument('--pair',action='store_true',help='One stock/full process pair')
    a=p.parse_args()
    result={'scope':'Timing CSV arithmetic only; confirm each benchmark process completed successfully separately.',
            'timing':summarize_timing(a.evidence,["0-stock","1-full"] if a.pair else None)}
    with a.output.open('x') as f:json.dump(result,f,indent=2);f.write('\n')
    print(a.output)
