#!/usr/bin/env python3
"""Exercise the actual server rewind helper and speculative-boundary call site.

The checked session mocks verify control flow, prefix ownership, image state,
failure handling and resampling. They do not prove GPU arithmetic or physical
KV restoration; those require the separate real-model/backend regressions.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

from test_server_cancel_rebuild import extract


PRELUDE = r'''
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr,"line %d: %s\n",__LINE__,#x); exit(1); } } while (0)
typedef struct { int len, ids[32]; } ds4_tokens;
typedef struct { int identity; } ds4_vision_span;
typedef struct { ds4_tokens tokens; int pos, logits_pos; bool valid, vision; } ds4_session;
typedef struct { int inference_mu; } server;
typedef struct { ds4_session *session; } server_slot;
typedef struct { const ds4_vision_span *images; size_t image_count; } request;
typedef struct { request req; bool cancelled; } job;
typedef struct { int id; } ds4_cancel_checkpoint;
typedef enum { DS4_SESSION_REWRITE_OK, DS4_SESSION_REWRITE_REBUILD_NEEDED } ds4_session_rewrite_result;
static int snapshot_releases;
static void ds4_session_cancel_checkpoint_free(ds4_cancel_checkpoint *p) {
    if (p) snapshot_releases++;
}
enum { FAST, REBUILD, WRONG_VISION, WRONG_POSITION };
enum { SYNC_OK, SYNC_ERROR, SYNC_BAD_POSITION, SYNC_BAD_VISION, SYNC_INVALID };
static int locked, rewinds, syncs, evals, invalidations, rewind_mode, sync_mode, eval_error;
static int allocations, tests;
static ds4_vision_span image_span = {47};
static void pthread_mutex_lock(int *mu) { (void)mu; CHECK(!locked); locked=1; }
static void pthread_mutex_unlock(int *mu) { (void)mu; CHECK(locked); locked=0; }
static bool job_cancelled(const job *j) { return j->cancelled; }
static void ds4_session_rewind(ds4_session *s,int pos) {
    CHECK(locked && pos>=0 && pos<=s->pos); rewinds++;
    s->pos=pos+(rewind_mode==WRONG_POSITION); s->tokens.len=s->pos;
    s->valid=rewind_mode!=REBUILD; s->vision=rewind_mode!=WRONG_VISION;
    /* Rewind deliberately leaves logits at the old frontier. */
}
static void ds4_tokens_copy(ds4_tokens *dst,const ds4_tokens *src) { CHECK(locked); *dst=*src; allocations++; }
static void ds4_tokens_free(ds4_tokens *t) { (void)t; CHECK(allocations>0); allocations--; }
static const ds4_tokens *ds4_session_tokens(ds4_session *s) { CHECK(locked); return &s->tokens; }
static int ds4_session_pos(ds4_session *s) { CHECK(locked); return s->pos; }
static bool ds4_session_checkpoint_valid(ds4_session *s) { CHECK(locked); return s->valid; }
static int ds4_session_common_prefix(ds4_session *s,const ds4_tokens *p) {
    CHECK(locked); if(!s->valid) return 0;
    int i=0; while(i<s->tokens.len && i<p->len && s->tokens.ids[i]==p->ids[i]) i++; return i;
}
static bool ds4_session_vision_state_matches(ds4_session *s,const ds4_vision_span *images,size_t n) {
    CHECK(locked && images==&image_span && n==1); return s->vision;
}
static void ds4_session_invalidate(ds4_session *s) { CHECK(locked); invalidations++; s->valid=false; }
static int server_session_sync_multimodal(server *srv,server_slot *slot,const ds4_tokens *p,
        const ds4_vision_span *images,size_t n,char *err,size_t errlen) {
    (void)srv; CHECK(!locked && images==&image_span && n==1 && snapshot_releases==1); syncs++;
    if(sync_mode==SYNC_ERROR) { snprintf(err,errlen,"sync failed"); return 1; }
    slot->session->tokens=*p;
    slot->session->pos=p->len+(sync_mode==SYNC_BAD_POSITION);
    slot->session->logits_pos=p->len;
    slot->session->vision=sync_mode!=SYNC_BAD_VISION;
    slot->session->valid=sync_mode!=SYNC_INVALID; return 0;
}
static int server_eval_token(server *srv,server_slot *slot,int token,char *err,size_t errlen) {
    (void)srv; CHECK(!locked); evals++;
    if(eval_error) { snprintf(err,errlen,"eval failed"); return 1; }
    ds4_session *s=slot->session; CHECK(s->valid && s->vision && token==1000+s->pos);
    s->tokens.ids[s->pos++]=token; s->tokens.len=s->pos; s->logits_pos=s->pos; return 0;
}
static void trace_event(server *s,uint64_t id,const char *fmt,...) { (void)s; (void)id; (void)fmt; }
'''

WRAPPER = r'''
static int boundary(server *s,server_slot *slot,job *j,int block_start,int ntok,int kept,
                    bool resample,bool text_stop,bool initial_error) {
    int toks[17]; for(int i=0;i<ntok;i++) toks[i]=1000+block_start+i;
    char err[160]={0}; const char *finish=initial_error?"error":"length";
    bool stop_decode=false; uint64_t trace_id=0;
    ds4_cancel_checkpoint checkpoint={1},*cancel_checkpoint=&checkpoint;
    char cancel_checkpoint_err[160]={0};
    bool cancel_prompt_frontier_preservable=true;
    PRODUCTION_BOUNDARY
    CHECK(snapshot_releases==syncs);
    CHECK((cancel_checkpoint==NULL)==(syncs>0));
    CHECK(cancel_prompt_frontier_preservable==(syncs==0));
    if(stop_decode) { CHECK(!strcmp(finish,"error") && err[0]); return 1; }
    return 0;
}
'''

TESTS = r'''
static ds4_session fresh(int block) {
    CHECK(!locked && !allocations);
    rewinds=syncs=evals=invalidations=eval_error=snapshot_releases=0; rewind_mode=FAST; sync_mode=SYNC_OK;
    ds4_session s={.pos=3+block,.logits_pos=3+block,.valid=true,.vision=true};
    s.tokens.len=s.pos; for(int i=0;i<s.pos;i++) s.tokens.ids[i]=1000+i; return s;
}
static int call(ds4_session *session,int block,int kept,bool resample,bool text_stop,
                bool cancelled,bool error) {
    server s={0}; server_slot slot={session}; job j={{&image_span,1},cancelled};
    int rc=boundary(&s,&slot,&j,3,block,kept,resample,text_stop,error);
    CHECK(!locked && !allocations); tests++; return rc;
}
int main(void) {
    for(int block=1;block<=17;block++) for(int kept=0;kept<=block;kept++) {
        for(int mode=FAST;mode<=WRONG_VISION;mode++) {
            ds4_session s=fresh(block); rewind_mode=mode;
            CHECK(call(&s,block,kept,false,false,false,false)==0);
            CHECK(s.pos==3+kept && s.valid && s.vision && !invalidations);
            CHECK(rewinds==(kept<block) && syncs==((kept<block)&&(mode!=FAST)) && evals==0);
        }
        if(kept>0 && kept<block) for(int mode=FAST;mode<=REBUILD;mode++) {
            ds4_session s=fresh(block); rewind_mode=mode;
            CHECK(call(&s,block,kept,true,false,false,false)==0);
            CHECK(rewinds==1 && evals==1 && syncs==(mode==REBUILD));
            CHECK(s.pos==3+kept && s.logits_pos==s.pos && s.valid && s.vision);
        }
    }
    for(int bypass=0;bypass<3;bypass++) {
        ds4_session s=fresh(4); if(bypass==0) s.valid=false;
        CHECK(call(&s,4,2,false,bypass==0,bypass==1,bypass==2)==0);
        CHECK(!rewinds && !syncs && !evals && s.pos==7);
        CHECK(s.valid==(bypass!=0));
    }
    ds4_session s=fresh(4); rewind_mode=WRONG_POSITION;
    CHECK(call(&s,4,2,false,false,false,false)==1);
    CHECK(rewinds==1 && syncs==0 && invalidations==1 && !s.valid);
    for(int failure=SYNC_ERROR;failure<=SYNC_INVALID;failure++) {
        s=fresh(4); rewind_mode=REBUILD; sync_mode=failure;
        CHECK(call(&s,4,2,false,false,false,false)==1);
        CHECK(rewinds==1 && syncs==1 && !evals && !s.valid);
    }
    s=fresh(4); eval_error=1;
    CHECK(call(&s,4,2,true,false,false,false)==1);
    CHECK(rewinds==1 && evals==1);
    printf("PASS server speculative boundaries: %d cases, actual helper and call site\n",tests);
    return 0;
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1] / 'ds4_server.c')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    raw = args.source.read_bytes()
    source = raw.decode()
    retirement = extract(source, 'begin_destructive_checkpoint_rebuild')
    helper = extract(source, 'server_generation_rewind')
    target = extract(source, 'speculative_tail_rewind_target')
    start = source.index('        const int tail_rewind_to = speculative_tail_rewind_target(', source.index('decode_again:'))
    end = source.index('        if (stop_decode) break;', start)
    boundary = source[start:end]
    code = PRELUDE + retirement + '\n' + target + '\n' + helper + WRAPPER.replace('PRODUCTION_BOUNDARY', boundary) + TESTS
    compiler = shlex.split(os.environ.get('CC', 'cc'))
    if args.output:
        args.output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix='ds4-server-boundary-') as temporary:
        root = args.output or Path(temporary)
        c, binary = root / 'contract.c', root / 'contract'
        c.write_text(code)
        command = compiler + ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror', str(c), '-o', str(binary)]
        build = subprocess.run(command, capture_output=True, text=True, timeout=60)
        report = dict(source_sha256=hashlib.sha256(raw).hexdigest(),
                      helper_sha256=hashlib.sha256(helper.encode()).hexdigest(),
                      boundary_sha256=hashlib.sha256(boundary.encode()).hexdigest(),
                      build_command=command, build_exit=build.returncode,
                      build_stdout=build.stdout, build_stderr=build.stderr)
        rc = build.returncode
        if rc == 0:
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            rc = run.returncode
            report.update(run_exit=rc, stdout=run.stdout, stderr=run.stderr)
        if args.output:
            (root / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report))
        return rc


if __name__ == '__main__':
    raise SystemExit(main())
