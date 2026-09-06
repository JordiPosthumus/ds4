/* Lossless short-prefill dispatch regression, using deterministic MXFP4
 * weights. Compare every populated intermediate/output byte against the
 * rollback, poison writable tensors, and protect their surrounding storage.
 * This same source can also dump an independently linked baseline oracle. */
#define _DARWIN_C_SOURCE
#include "ds4_gpu.h"
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum { DIM=256, TOTAL=8, USED=6, GUARD=128, MXFP4=39 };
typedef struct { uint8_t e,qs[16]; } block_mxfp4;
typedef struct { ds4_gpu_tensor *base,*view; uint64_t bytes; } guarded;
static const char *rollback="DS4_METAL_DISABLE_PRE_M5_MXFP4_MOE_SMALL_PREFILL";
static void check(int ok,const char *label) {
    if(!ok) { fprintf(stderr,"FAIL small-prefill: %s\n",label); exit(1); }
}
bool ds4_log_is_tty(FILE *f) { (void)f; return false; }
static uint64_t align_up(uint64_t n,uint64_t a) { return (n+a-1)/a*a; }
static void fill_matrix(block_mxfp4 *matrix,uint32_t salt) {
    for(uint32_t expert=0;expert<TOTAL;expert++) for(uint32_t row=0;row<DIM;row++)
        for(uint32_t block=0;block<DIM/32;block++) {
            block_mxfp4 *b=matrix+((uint64_t)expert*DIM+row)*(DIM/32)+block;
            b->e=120+(salt+expert*3+row+block*5)%6;
            for(uint32_t i=0;i<16;i++) {
                uint8_t lo=(salt+expert*7+row*3+block+i)&15;
                uint8_t hi=(salt*3+expert+row*5+block*7+i*3)&15;
                b->qs[i]=lo|(hi<<4);
            }
        }
}
static guarded allocate(uint64_t bytes) {
    guarded g={.bytes=bytes}; g.base=ds4_gpu_tensor_alloc(bytes+2*GUARD); check(g.base!=NULL,"base allocation");
    g.view=ds4_gpu_tensor_view(g.base,GUARD,bytes); check(g.view!=NULL,"offset view");
    unsigned char canary[GUARD]; memset(canary,0x59,sizeof(canary));
    check(ds4_gpu_tensor_write(g.base,0,canary,GUARD)&&ds4_gpu_tensor_write(g.base,GUARD+bytes,canary,GUARD),"guard initialization");
    return g;
}
static void guards(guarded *g) {
    unsigned char before[GUARD],after[GUARD],canary[GUARD]; memset(canary,0x59,sizeof(canary));
    check(ds4_gpu_tensor_read(g->base,0,before,GUARD)&&ds4_gpu_tensor_read(g->base,GUARD+g->bytes,after,GUARD),"guard read");
    check(!memcmp(before,canary,GUARD)&&!memcmp(after,canary,GUARD),"unchanged tensor guards");
}
static void release(guarded *g) { guards(g); ds4_gpu_tensor_free(g->view); ds4_gpu_tensor_free(g->base); }
static void finite_mid(const void *data,uint64_t count,bool half) {
    for(uint64_t i=0;i<count;i++) {
        /* Integer exponent checks remain meaningful with the project's
         * -ffast-math build flags, which may optimize isfinite() away. */
        if (half) {
            uint16_t bits; memcpy(&bits,(const unsigned char *)data+i*2,2);
            check((bits&0x7c00u)!=0x7c00u,"finite half intermediate");
        } else {
            uint32_t bits; memcpy(&bits,(const unsigned char *)data+i*4,4);
            check((bits&0x7f800000u)!=0x7f800000u,"finite float intermediate");
        }
    }
}
static void run_case(const void *model,uint64_t model_size,uint64_t up_offset,uint64_t down_offset,
        uint32_t n,int routing,int quality,FILE *dump,int index) {
    uint64_t pairs=(uint64_t)n*USED*DIM,out_count=(uint64_t)n*DIM;
    uint64_t mid_bytes=pairs*sizeof(float),out_bytes=out_count*sizeof(float);
    float *x=malloc(out_bytes),*weights=malloc((size_t)n*USED*sizeof(float));
    int32_t *selected=malloc((size_t)n*USED*sizeof(int32_t));
    unsigned char *poison=malloc(mid_bytes),*mid_ref=malloc(mid_bytes),*mid_actual=malloc(mid_bytes);
    float *experts_ref=malloc(mid_bytes),*experts_actual=malloc(mid_bytes),*out_ref=malloc(out_bytes),*out_actual=malloc(out_bytes);
    check(x&&weights&&selected&&poison&&mid_ref&&mid_actual&&experts_ref&&experts_actual&&out_ref&&out_actual,"host allocations");
    for(uint32_t t=0;t<n;t++) {
        for(uint32_t d=0;d<DIM;d++) x[(uint64_t)t*DIM+d]=((int)((t*19+d*13)%67)-33)/137.0f;
        for(uint32_t slot=0;slot<USED;slot++) {
            selected[(uint64_t)t*USED+slot]=(slot+(routing?(t*3)%TOTAL:0))%TOTAL;
            weights[(uint64_t)t*USED+slot]=(float)(slot+1)/21.0f;
        }
    }
    guarded tensors[8]={allocate(out_bytes),allocate((uint64_t)n*USED*4),allocate((uint64_t)n*USED*4),
        allocate(mid_bytes),allocate(mid_bytes),allocate(mid_bytes),allocate(mid_bytes),allocate(out_bytes)};
    check(ds4_gpu_tensor_write(tensors[0].view,0,x,out_bytes),"input write");
    check(ds4_gpu_tensor_write(tensors[1].view,0,selected,(uint64_t)n*USED*4),"selected write");
    check(ds4_gpu_tensor_write(tensors[2].view,0,weights,(uint64_t)n*USED*4),"weight write");
    ds4_gpu_set_quality(quality!=0); ds4_gpu_test_set_flags(0);
    bool reference_half=false; const int modes[]={0,1,1,0};
    for(int repeat=0;repeat<4;repeat++) {
        if(modes[repeat]) check(!unsetenv(rollback),"enable isolated candidate");
        else check(!setenv(rollback,"1",1),"rollback selection");
        memset(poison,(repeat&1)?0xa5:0x5a,mid_bytes);
        for(int t=3;t<8;t++) check(ds4_gpu_tensor_write(tensors[t].view,0,poison,tensors[t].bytes),"poison writable storage");
        bool half=false; uint64_t row_bytes=(DIM/32)*sizeof(block_mxfp4),expert_bytes=DIM*row_bytes;
        check(ds4_gpu_routed_moe_batch_tensor(tensors[7].view,tensors[3].view,tensors[4].view,tensors[5].view,tensors[6].view,
            model,model_size,0,up_offset,down_offset,MXFP4,MXFP4,expert_bytes,row_bytes,expert_bytes,row_bytes,
            DIM,DIM,DIM,tensors[1].view,tensors[2].view,TOTAL,USED,7.0f,tensors[0].view,0,n,&half,true),"routed MoE call");
        uint64_t populated_mid=pairs*(half?sizeof(_Float16):sizeof(float));
        check(ds4_gpu_tensor_read(tensors[5].view,0,mid_actual,populated_mid),"intermediate read");
        check(ds4_gpu_tensor_read(tensors[6].view,0,experts_actual,mid_bytes),"expert read");
        check(ds4_gpu_tensor_read(tensors[7].view,0,out_actual,out_bytes),"output read");
        finite_mid(mid_actual,pairs,half); finite_mid(experts_actual,pairs,false); finite_mid(out_actual,out_count,false);
        for(int t=0;t<8;t++) guards(&tensors[t]);
        if(!repeat) {
            reference_half=half; memcpy(mid_ref,mid_actual,populated_mid); memcpy(experts_ref,experts_actual,mid_bytes); memcpy(out_ref,out_actual,out_bytes);
            if(dump) {
                uint32_t header[]={n,(uint32_t)routing,(uint32_t)quality,(uint32_t)half};
                check(fwrite(header,1,sizeof(header),dump)==sizeof(header),"dump header");
                check(fwrite(mid_ref,1,populated_mid,dump)==populated_mid&&fwrite(experts_ref,1,mid_bytes,dump)==mid_bytes&&
                    fwrite(out_ref,1,out_bytes,dump)==out_bytes,"dump independent outputs");
            }
        } else {
            if(reference_half!=half||memcmp(mid_ref,mid_actual,populated_mid)||memcmp(experts_ref,experts_actual,mid_bytes)||memcmp(out_ref,out_actual,out_bytes)) {
                fprintf(stderr,"case=%d n=%u routing=%d quality=%d repetition=%d enabled=%d\n",index,n,routing,quality,repeat,modes[repeat]);
                check(0,"all populated output and intermediate bytes exact");
            }
        }
    }
    for(int t=7;t>=0;t--) release(&tensors[t]);
    free(out_actual);free(out_ref);free(experts_actual);free(experts_ref);free(mid_actual);free(mid_ref);free(poison);free(selected);free(weights);free(x);
    printf("PASS case=%d tokens=%u routing=%d quality=%d exact_mid_experts_output=yes guards=yes\n",index,n,routing,quality); fflush(stdout);
}
int main(int argc,char **argv) {
    check(argc==1||argc==2,"optional independent oracle output path");
    FILE *dump=argc==2?fopen(argv[1],"wbx"):NULL; check(argc==1||dump,"exclusive oracle file");
    uint64_t page=getpagesize(),row_bytes=(DIM/32)*sizeof(block_mxfp4),tensor_bytes=TOTAL*DIM*row_bytes;
    uint64_t up=align_up(tensor_bytes,page),down=align_up(up+tensor_bytes,page),bytes=align_up(down+tensor_bytes,page);
    void *model=NULL; check(!posix_memalign(&model,page,bytes),"model allocation"); memset(model,0,bytes);
    fill_matrix(model,1);fill_matrix((block_mxfp4 *)((char *)model+up),5);fill_matrix((block_mxfp4 *)((char *)model+down),9);
    check(ds4_gpu_init()&&ds4_gpu_set_model_map(model,bytes),"Metal model map");
    const uint32_t counts[]={31,32,33,47,48,63,64,65,91,127,128,129,255,256,257,511,512,513,1023,1024,1025,2047,2048,2049,4096};
    int index=0;
    for(int quality=0;quality<2;quality++) for(int routing=0;routing<2;routing++)
        for(size_t i=0;i<sizeof(counts)/sizeof(counts[0]);i++) run_case(model,bytes,up,down,counts[i],routing,quality,dump,index++);
    check(!unsetenv(rollback),"clear fixture switch"); ds4_gpu_set_quality(false);
    if(dump) check(!fclose(dump),"oracle close");
    printf("PASS %d small-prefill boundary cases; 4 ordered calls each\n",index); return 0;
}
