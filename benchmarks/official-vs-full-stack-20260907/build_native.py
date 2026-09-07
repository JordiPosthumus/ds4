"""Build isolated stock/full trees. No model, service or GPU test is invoked."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import platform
import subprocess
import time

ROOT = Path(__file__).resolve().parent

def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024*1024), b''):
            h.update(block)
    return h.hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('build_directory')
    args = parser.parse_args()
    build = Path(args.build_directory).resolve()
    assert build.is_relative_to(ROOT)
    assert not (build/'build-passed.json').exists()
    linux = platform.system() == 'Linux'
    environment = {k:v for k,v in os.environ.items()
                   if not k.startswith(('DS4_', 'MTL_', 'CUDA_', 'NVIDIA_'))}
    arch = ['CUDA_ARCH=sm_121a'] if linux else []
    results = []
    for label in ('stock', 'full'):
        tree = build/label
        assert (tree/'Makefile').is_file()
        assert not list(tree.glob('*.o')), 'Must start from a clean source export'
        commands = [
            ['make', '-j2', *arch, 'ds4', 'ds4-server', 'ds4-bench', 'ds4-eval', 'ds4-agent'],
            ['make', '-j2', *arch, '-f', 'Makefile', '-f', str(ROOT/'benchmark.mk'),
             'STACK_BENCH_SOURCE='+str(ROOT/'stack_bench.c'), 'stack-bench'],
            ['make', '-j2', *arch, 'test-frontends'],
        ]
        records = []
        for i, command in enumerate(commands):
            print('BUILD', label, i, ' '.join(command), flush=True)
            start = time.monotonic()
            with (build/f'{label}-{i}.log').open('xb') as f:
                p = subprocess.run(command, cwd=tree, env=environment,
                                   stdout=f, stderr=subprocess.STDOUT)
            row = dict(command=command, exit=p.returncode, seconds=time.monotonic()-start)
            records.append(row)
            (build/f'{label}-{i}-exit.json').write_text(json.dumps(row,indent=2)+'\n')
            assert p.returncode == 0, (label, i)
        result = dict(label=label, commands=records,
                      executables={p.name:sha(p) for p in (tree/'ds4',tree/'ds4-server',tree/'ds4-bench',tree/'stack-bench')},
                      objects={str(p.relative_to(tree)):sha(p) for p in sorted(tree.rglob('*.o'))})
        results.append(result)
        (build/f'{label}-build-passed.json').write_text(json.dumps(result,indent=2)+'\n')
        print('PASS native build and host frontends',label,flush=True)
    (build/'build-passed.json').write_text(json.dumps(dict(
        passed=True, machine=platform.uname()._asdict(), gpu_or_model_executed=False,
        source_sha256=sha(ROOT/'stack_bench.c'), makefile_sha256=sha(ROOT/'benchmark.mk'),
        corpus_sha256=sha(ROOT/'corpus.txt'), results=results),indent=2)+'\n')

if __name__ == '__main__':
    main()
