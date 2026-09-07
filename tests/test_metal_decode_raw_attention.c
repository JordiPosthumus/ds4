/* PR954 raw-only attention extraction. Exact caller semantics, including the
 * deferred inverse-RoPE handoff; no model file or production cache is used. */
#define _DARWIN_C_SOURCE
#include "ds4_gpu.h"
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
enum { DIM=512, GUARD=128, RETAIN=6 };
typedef struct { ds4_gpu_tensor *base,*view; uint64_t bytes; } guarded;
typedef struct { uint32_t raw,cap,start,heads,comp,pos; int half,quality,rope,extended; } shape;
extern void ds4_gpu_set_decode_attn_rope_fuse(uint32_t,uint32_t,uint32_t,uint32_t,bool,float,float,float,float,float,float);
extern int ds4_gpu_decode_attn_rope_fuse_available(void);
extern int ds4_gpu_decode_attn_rope_fuse_used(void);
static const char *gather_off="DS4_METAL_DISABLE_DECODE_RAW_GATHERED_ATTN";
static const char *packed_off="DS4_METAL_DISABLE_DECODE_RAW_PACKED32";
static const char *m2_rope_off="DS4_METAL_DISABLE_M2_ATTN_INV_ROPE_FUSE";
static void check(int ok,const char *why) { if(!ok){fprintf(stderr,"FAIL raw attention: %s\n",why);exit(1);} }
static void env(const char *key,bool on) {check(!(on?setenv(key,"1",1):unsetenv(key)),"fixture environment");}
static double now(void) {struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec*1e-9;}
static float value(uint64_t i,uint32_t salt) {return ((int)((i*37+(i>>4)*13+salt*19)%251)-125)/137.0f;}
static guarded alloc(uint64_t bytes) {
    guarded g={.bytes=bytes};g.base=ds4_gpu_tensor_alloc(bytes+2*GUARD);check(g.base!=NULL,"allocation");
    g.view=ds4_gpu_tensor_view(g.base,GUARD,bytes);check(g.view!=NULL,"offset view");
    unsigned char a[GUARD];memset(a,0x69,GUARD);
    check(ds4_gpu_tensor_write(g.base,0,a,GUARD)&&ds4_gpu_tensor_write(g.base,GUARD+bytes,a,GUARD),"guard write");return g;
}
static void guard(guarded *g) {
    unsigned char a[GUARD],b[GUARD],e[GUARD];memset(e,0x69,GUARD);
    check(ds4_gpu_tensor_read(g->base,0,a,GUARD)&&ds4_gpu_tensor_read(g->base,GUARD+g->bytes,b,GUARD),"guard read");
    check(!memcmp(a,e,GUARD)&&!memcmp(b,e,GUARD),"canaries preserved");
}
static void release(guarded *g) {guard(g);ds4_gpu_tensor_free(g->view);ds4_gpu_tensor_free(g->base);}
static void finite(const float *p,uint64_t count) {
    for(uint64_t i=0;i<count;i++){uint32_t u;memcpy(&u,p+i,4);check((u&0x7f800000u)!=0x7f800000u,"finite output");}
}
static int dispatch(const shape *s,guarded *out,guarded *q,guarded *raw,guarded *comp,void *model,uint64_t size) {
    /* This is the Metal caller's actual protocol. The CUDA convenience API
     * does not arm Metal's deferred inverse rotation. */
    const uint32_t orig=s->extended?65536:0;
    const float base=s->extended?160000.0f:10000.0f,scale=s->extended?0.0625f:1.0f;
    const float ext=s->extended?1.0f:0.0f,af=s->extended?1.1f:1.0f;
    bool rejected=s->raw+s->comp>8192u;
    bool armed=!rejected&&s->rope&&!s->quality&&ds4_gpu_decode_attn_rope_fuse_available();
    if(armed)ds4_gpu_set_decode_attn_rope_fuse(DIM,64,s->pos,orig,true,base,scale,ext,af,32.0f,1.0f);
    int ok=ds4_gpu_attention_decode_heads_tensor(out->view,model,size,128,q->view,raw->view,
        s->raw,s->cap,s->start,s->comp?comp->view:NULL,s->half,s->comp,NULL,0,s->heads,DIM);
    if(rejected){check(!ok,"unsupported shape rejected");return -1;}
    check(ok,"attention dispatch");int fused=armed&&ds4_gpu_decode_attn_rope_fuse_used();
    if(s->rope&&!fused)check(ds4_gpu_rope_tail_tensor(out->view,1,s->heads,DIM,64,s->pos,orig,true,
        base,scale,ext,af,32.0f,1.0f),"standalone inverse rotation");
    return fused;
}
static void run(const shape *s,void *model,uint64_t size,int index,bool prove,FILE *dump) {
    bool rejected=s->raw+s->comp>8192u;
    uint64_t qb=(uint64_t)s->heads*DIM*4,rb=(uint64_t)s->cap*DIM*4;
    uint64_t cb=(uint64_t)(s->comp?s->comp:1)*DIM*(s->half?2:4),max=qb>rb?qb:rb;if(cb>max)max=cb;
    float *hq=malloc(qb),*hr=malloc(rb),*ref=malloc(qb),*actual=malloc(qb);void *hc=malloc(cb),*scratch=malloc(max);
    check(hq&&hr&&ref&&actual&&hc&&scratch,"host buffers");
    for(uint64_t i=0;i<qb/4;i++)hq[i]=value(i,index+1);
    for(uint64_t i=0;i<rb/4;i++)hr[i]=value(i,index+5);
    for(uint64_t i=0;i<cb/(s->half?2:4);i++){float v=value(i,index+9);if(s->half)((_Float16*)hc)[i]=(_Float16)v;else((float*)hc)[i]=v;}
    guarded q=alloc(qb),raw=alloc(rb),comp=alloc(cb),outputs[RETAIN];
    for(int i=0;i<RETAIN;i++)outputs[i]=alloc(qb);
    check(ds4_gpu_tensor_write(q.view,0,hq,qb)&&ds4_gpu_tensor_write(raw.view,0,hr,rb)&&ds4_gpu_tensor_write(comp.view,0,hc,cb),"inputs");
    const int modes[]={0,1,2,0,1,2,2,1,0,0,1,2,2,1,0,0,1,2};
    ds4_gpu_set_quality(s->quality!=0);
    for(int j=0;j<18;j++) {
        int mode=modes[j];env(gather_off,mode==0);env(packed_off,mode!=2);env(m2_rope_off,mode!=2);
        guarded *out=&outputs[j%RETAIN];memset(actual,rejected?0xa5:(j&1?0x5a:0xa5),qb);
        if(rejected)memcpy(ref,actual,qb);
        check(ds4_gpu_tensor_write(out->view,0,actual,qb)&&ds4_gpu_synchronize(),"poison and synchronize");
        double begin=now();int fused=dispatch(s,out,&q,&raw,&comp,model,size);check(ds4_gpu_synchronize(),"complete dispatch");
        printf("TIMING case=%d raw=%u mode=%d repeat=%d warmup=%d fused=%d seconds=%.9f\n",index,s->raw,mode,j,j<3,fused,now()-begin);
        check(ds4_gpu_tensor_read(out->view,0,actual,qb),"read output");if(!rejected)finite(actual,qb/4);
        else check(!memcmp(actual,ref,qb),"rejected shape leaves output untouched");
        if(!rejected&&prove&&mode&&s->rope&&!s->quality&&s->heads==64) {
            int available=ds4_gpu_decode_attn_rope_fuse_available();
            if(mode==2)check(available,"fusion available in the explicitly enabled evaluation mode");
            if(available)check(fused,"new raw gathering actually consumes inverse RoPE");
        }
        if(!j) {
            memcpy(ref,actual,qb);uint32_t header[]={s->raw,s->cap,s->start,s->heads,s->comp,s->pos,(uint32_t)s->half,(uint32_t)s->quality,(uint32_t)s->rope,(uint32_t)s->extended};
            check(fwrite(header,1,sizeof(header),dump)==sizeof(header)&&fwrite(ref,1,qb,dump)==qb,"independent dump");
        }
        if(memcmp(actual,ref,qb)) {
            uint64_t n=0,first=0;for(uint64_t i=0;i<qb/4;i++)if(memcmp(actual+i,ref+i,4)){if(!n)first=i;n++;}
            fprintf(stderr,"case=%d raw=%u mode=%d differing=%llu first=%llu old=%a new=%a\n",index,s->raw,mode,(unsigned long long)n,(unsigned long long)first,ref[first],actual[first]);check(0,"byte-exact caller output");
        }
        /* Retain all six outputs across scratch reuse and re-encodes. */
        for(int k=0;k<RETAIN&&k<=j;k++){guard(&outputs[k]);check(ds4_gpu_tensor_read(outputs[k].view,0,scratch,qb)&&!memcmp(scratch,ref,qb),"retained output unchanged");}
        guard(&q);guard(&raw);guard(&comp);
        check(ds4_gpu_tensor_read(q.view,0,scratch,qb)&&!memcmp(scratch,hq,qb),"query preserved");
        check(ds4_gpu_tensor_read(raw.view,0,scratch,rb)&&!memcmp(scratch,hr,rb),"raw ring preserved");
        check(ds4_gpu_tensor_read(comp.view,0,scratch,cb)&&!memcmp(scratch,hc,cb),"compressed input preserved");
    }
    for(int k=RETAIN-1;k>=0;k--)release(&outputs[k]);release(&comp);release(&raw);release(&q);
    free(scratch);free(hc);free(actual);free(ref);free(hr);free(hq);
    printf("PASS case=%d raw=%u heads=%u comp=%u quality=%d rope=%d exact=yes guards=yes rejected=%d\n",index,s->raw,s->heads,s->comp,s->quality,s->rope,rejected);fflush(stdout);
}
int main(int argc,char **argv) {
    check(argc>=1&&argc<=3,"[OUTPUT [--require-selection]]");bool prove=argc==3;check(!prove||!strcmp(argv[2],"--require-selection"),"selection argument");
    FILE *dump=argc==1?tmpfile():fopen(argv[1],"wbx");check(dump!=NULL,"temporary or exclusive dump");uint64_t size=getpagesize();void *model=NULL;
    check(!posix_memalign(&model,size,size),"aligned model map");memset(model,0,size);for(int i=0;i<64;i++)((float*)model)[32+i]=value(i,13);
    check(ds4_gpu_init()&&ds4_gpu_set_model_map(model,size),"initialize");
    const uint32_t counts[]={1,2,15,16,17,31,32,33,63,64,65,96,127,128,129,256,512,1024,1025};int index=0;
    for(size_t i=0;i<sizeof(counts)/sizeof(counts[0]);i++)for(int extended=0;extended<2;extended++) {
        shape s={counts[i],counts[i]+9,counts[i]+6,64,0,extended?65535u:255u,1,0,1,extended};run(&s,model,size,index++,prove,dump);
    }
    shape controls[6];for(int i=0;i<6;i++)controls[i]=(shape){128,137,133,64,0,1023,1,0,1,0};
    controls[0].heads=32;controls[1].quality=1;controls[2].half=0;controls[3].rope=0;controls[4].comp=128;controls[5].comp=128;controls[5].half=0;
    for(int i=0;i<6;i++)run(&controls[i],model,size,index++,prove,dump);
    /* The public unindexed API accepts at most 8192 total rows. Exercise
     * reduction and exact acceptance boundaries, and unchanged-buffer
     * rejection above the limit. Full-model tests cover long engine contexts. */
    const uint32_t compressed[]={255,256,511,512,1023,1024,2047,2048,4095,4096,7935,7936,7937,8191,8192,16383,16384};
    for(size_t i=0;i<sizeof(compressed)/sizeof(compressed[0]);i++)for(int half=0;half<2;half++) {
        shape s={256,265,261,64,compressed[i],65535,half,0,1,1};run(&s,model,size,index++,prove,dump);
    }
    shape mixed_controls[4];for(int i=0;i<4;i++)mixed_controls[i]=(shape){256,265,261,64,16384,65535,1,0,1,1};
    mixed_controls[0].heads=32;mixed_controls[1].quality=1;mixed_controls[2].rope=0;mixed_controls[3].half=0;mixed_controls[3].extended=0;
    for(int i=0;i<4;i++)run(&mixed_controls[i],model,size,index++,prove,dump);
    for(int i=0;i<4;i++){mixed_controls[i].comp=7936;run(&mixed_controls[i],model,size,index++,prove,dump);}
    ds4_gpu_set_quality(false);env(gather_off,false);env(packed_off,false);env(m2_rope_off,false);check(!fclose(dump),"close");
    printf("PASS %d raw attention cases; eighteen dispatches each; exact guarded independent dump\n",index);return 0;
}
