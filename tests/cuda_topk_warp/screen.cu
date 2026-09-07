#include <cuda_runtime.h>
#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "reference-kernels.cuh"
#include "candidate-kernels.cuh"

static cudaStream_t stream;
#define CU(call) do { auto e=(call); if(e!=cudaSuccess) { fprintf(stderr,"CUDA %s:%d %s\n",__FILE__,__LINE__,cudaGetErrorString(e)); exit(2); } } while(0)
static void launch(bool opt,uint32_t *out,uint32_t *scratch,const float *scores,
                   uint32_t n,uint32_t rows,uint32_t top) {
    const uint32_t group=top==512?8:2, chunks=(n+4095)/4096;
    uint32_t sets=chunks,stride=sets*top,*cur=scratch;
    dim3 grid(rows,chunks);
    if(opt) candidate_topk_chunk_pow2_kernel<4096><<<grid,1024,0,stream>>>(cur,scores,n,rows,top,stride);
    else indexer_topk_chunk_pow2_kernel<4096><<<grid,1024,0,stream>>>(cur,scores,n,rows,top,stride);
    while(sets>group) {
        uint32_t nextsets=(sets+group-1)/group,nextstride=nextsets*top;
        uint32_t *next=cur+(uint64_t)rows*stride;
        dim3 merge(rows,nextsets);
        if(opt) candidate_topk_tree_merge_pow2_kernel<4096><<<merge,1024,0,stream>>>(next,cur,scores,n,rows,top,sets,group,stride,nextstride);
        else indexer_topk_tree_merge_pow2_kernel<4096><<<merge,1024,0,stream>>>(next,cur,scores,n,rows,top,sets,group,stride,nextstride);
        cur=next;sets=nextsets;stride=nextstride;
    }
    if(opt) candidate_topk_merge_pow2_kernel<4096><<<rows,1024,0,stream>>>(out,cur,scores,n,rows,top,sets*top,stride);
    else indexer_topk_merge_pow2_kernel<4096><<<rows,1024,0,stream>>>(out,cur,scores,n,rows,top,sets*top,stride);
    CU(cudaGetLastError());
}
static uint32_t mix(uint32_t x) { x^=x>>16; x*=0x7feb352d; x^=x>>15; x*=0x846ca68b; return x^(x>>16); }
static float frombits(uint32_t x) {float v;memcpy(&v,&x,4);return v;}
static float value(uint32_t i,uint32_t n,int p) {
    uint32_t x=mix(i+12347);
    if(p==0) return (int32_t)x*(1.f/2147483648.f);
    if(p==1) return (int)(x%17)-8.f;
    if(p==2) return (i&1)?0.f:-0.f;
    if(p==3) return (i%3==0)?INFINITY:(i%3==1)?-INFINITY:0.f;
    if(p==4) return (i%37==0)?frombits(0x7fc00000u|(x&0x3fffff)):(int)(x%17)-8.f;
    if(p==5) return (i%41==0)?frombits(0xffc00000u|(x&0x3fffff)):(int)(x%17)-8.f;
    if(p==6) return float(i%n);
    if(p==7) return -float(i%n);
    return -INFINITY;
}
int main(int argc,char **argv) {
    CU(cudaStreamCreateWithFlags(&stream,cudaStreamNonBlocking));
    bool quick=argc>1&&!strcmp(argv[1],"--quick");
    const uint32_t widths[]={2048,4096,4097,8192,8193,12289,16384,16385,32768,32769,65536,65537,131073};
    const uint32_t batches[]={1,2,7,31,32};
    FILE *refdump=fopen("reference-selected.u32","wb"),*canddump=fopen("candidate-selected.u32","wb");
    assert(refdump&&canddump);
    size_t total=0,checks=0;
    puts("kind,n_comp,n_tokens,top_k,graph,pass,mode,microseconds");fflush(stdout);
    for(uint32_t top:{512u,2048u}) for(uint32_t rows:batches) for(uint32_t n:widths) {
        if(quick && !(rows==1||rows==7) )continue;
        if(quick && !(n==8193||n==65537))continue;
        uint32_t chunks=(n+4095)/4096,sets=chunks,group=top==512?8:2;
        size_t stride=chunks*top;
        while(sets>group){sets=(sets+group-1)/group;stride+=(size_t)sets*top;}
        float *scores;uint32_t *scratch,*out;
        CU(cudaMalloc(&scores,(size_t)n*rows*4));CU(cudaMalloc(&scratch,stride*rows*4));CU(cudaMalloc(&out,(size_t)top*rows*4));
        std::vector<float> host((size_t)n*rows);
        std::vector<uint32_t> ref((size_t)top*rows),got(ref.size());
        for(int pattern=0;pattern<9;pattern++) {
            for(size_t i=0;i<host.size();i++)host[i]=value((uint32_t)i,n,pattern);
            CU(cudaMemcpy(scores,host.data(),host.size()*4,cudaMemcpyHostToDevice));
            for(int mode:{0,1,1,0}) {
                CU(cudaMemsetAsync(scratch,0xa5,stride*rows*4,stream));CU(cudaMemsetAsync(out,0xa5,got.size()*4,stream));
                launch(mode,out,scratch,scores,n,rows,top);
                CU(cudaDeviceSynchronize());CU(cudaMemcpy(got.data(),out,got.size()*4,cudaMemcpyDeviceToHost));
                if(mode==0) {
                    ref=got;
                    assert(fwrite(ref.data(),4,ref.size(),refdump)==ref.size());
                } else {
                    if(got!=ref) {
                        for(size_t i=0;i<ref.size();i++)if(got[i]!=ref[i]){
                            fprintf(stderr,"MISMATCH n=%u rows=%u top=%u pattern=%d element=%zu ref=%u got=%u\n",n,rows,top,pattern,i,ref[i],got[i]);return 3;}
                    }
                    assert(fwrite(got.data(),4,got.size(),canddump)==got.size());
                }
                checks++;total+=got.size();
            }
            if(pattern!=4&&pattern!=5)for(uint32_t row=0;row<rows;row++) {
                std::vector<uint32_t> order(n);for(uint32_t i=0;i<n;i++)order[i]=i;
                std::partial_sort(order.begin(),order.begin()+top,order.end(),[&](uint32_t a,uint32_t b){float av=host[(size_t)row*n+a],bv=host[(size_t)row*n+b];return av>bv||(av==bv&&a<b);});
                assert(std::equal(order.begin(),order.begin()+top,ref.begin()+(size_t)row*top));
            }
        }
        if(rows==1&&!quick) {
            for(size_t i=0;i<host.size();i++)host[i]=value((uint32_t)i,n,0);
            CU(cudaMemcpy(scores,host.data(),host.size()*4,cudaMemcpyHostToDevice));
            for(int graph:{0,1}) {
                cudaGraphExec_t execs[2]={};
                if(graph) for(int mode=0;mode<2;mode++) {
                    cudaGraph_t capture;CU(cudaStreamBeginCapture(stream,cudaStreamCaptureModeGlobal));
                    for(int i=0;i<21;i++)launch(mode,out,scratch,scores,n,rows,top);
                    CU(cudaStreamEndCapture(stream,&capture));CU(cudaGraphInstantiate(&execs[mode],capture,0));CU(cudaGraphDestroy(capture));
                }
                cudaEvent_t begin,end;CU(cudaEventCreate(&begin));CU(cudaEventCreate(&end));
                int pass=0;
                for(int mode:{0,1,1,0,1,0,0,1}) {
                    for(int i=0;i<8;i++){if(graph)CU(cudaGraphLaunch(execs[mode],stream));else launch(mode,out,scratch,scores,n,rows,top);}
                    CU(cudaEventRecord(begin,stream));
                    for(int i=0;i<100;i++){if(graph)CU(cudaGraphLaunch(execs[mode],stream));else launch(mode,out,scratch,scores,n,rows,top);}
                    CU(cudaEventRecord(end,stream));CU(cudaEventSynchronize(end));float ms;CU(cudaEventElapsedTime(&ms,begin,end));
                    printf("timing,%u,%u,%u,%d,%d,%d,%.6f\n",n,rows,top,graph,pass++,mode,ms*1000/(100*(graph?21:1)));fflush(stdout);
                }
                CU(cudaEventDestroy(begin));CU(cudaEventDestroy(end));
                if(graph){CU(cudaGraphExecDestroy(execs[0]));CU(cudaGraphExecDestroy(execs[1]));}
            }
        }
        CU(cudaFree(out));CU(cudaFree(scratch));CU(cudaFree(scores));
    }
    fclose(refdump);fclose(canddump);
    CU(cudaStreamDestroy(stream));
    fprintf(stderr,"PASS checks=%zu selected_indices=%zu all candidate/reference byte-exact; finite CPU ordering passed\n",checks,total);
}
