/* Compare complete native DS4 builds through the same public engine API.
 * All timing controls are confined to this external benchmark frontend.
 * No production server, disk KV directory, sampling option or model is edited.
 * Decode is teacher-forced from the same corpus so the two builds do equal work.
 */
#include "ds4.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

enum { CONTEXT = 262144, STEPS = 128, WARMUPS = 2, TRIALS = 4 };
#ifdef __APPLE__
enum { PREFILL = 4096, RESIDENTS = 10 };
#define BACKEND DS4_BACKEND_METAL
#else
enum { PREFILL = 2048, RESIDENTS = 2 };
#define BACKEND DS4_BACKEND_CUDA
#endif
static const int frontiers[] = {32, 512, 2048, 8192};
static char error[512];

static void check(int ok, const char *where) {
    if (!ok) { fprintf(stderr, "FAIL %s: %s\n", where, error); exit(1); }
}
static double now(void) {
    struct timespec t;
    check(clock_gettime(CLOCK_MONOTONIC, &t) == 0, "monotonic clock");
    return (double)t.tv_sec + (double)t.tv_nsec * 1e-9;
}
static FILE *output(const char *dir, const char *name) {
    char path[2048];
    check(snprintf(path, sizeof(path), "%s/%s", dir, name) < (int)sizeof(path), "output path");
    FILE *fp = fopen(path, "wbx");
    check(fp != NULL, "new output file");
    return fp;
}
static void dump(const char *dir, const char *name, const void *values, size_t bytes) {
    FILE *fp = output(dir, name);
    check(fwrite(values, 1, bytes, fp) == bytes, "complete output bytes");
    check(fclose(fp) == 0, "close output");
}
static void logits(ds4_session *s, float *values, int vocab) {
    check(ds4_session_copy_logits(s, values, vocab) == vocab, "complete vocabulary");
    for (int i = 0; i < vocab; i++) check(isfinite(values[i]), "finite logits");
}
static void restore(ds4_session *s, const ds4_session_snapshot *snap, int position) {
    check(!ds4_session_load_snapshot(s, snap, error, sizeof(error)), "restore private snapshot");
    check(ds4_session_pos(s) == position, "restored position");
}
static void progress(void *opaque, const char *event, int current, int total) {
    (void)opaque;
    if (!strcmp(event, "prefill_chunk")) {
        fprintf(stderr, "PREFILL %d/%d\n", current, total);
        fflush(stderr);
    }
}

static void measure_frontier(ds4_session *s, const ds4_tokens *corpus, int pos,
        const char *dir, int vocab, float *values, float *reference,
        FILE *decode, FILE *suffix) {
    ds4_session_snapshot snap = {0};
    check(ds4_session_pos(s) == pos, "input frontier");
    check(!ds4_session_save_snapshot(s, &snap, error, sizeof(error)), "private frontier snapshot");
    check(snap.len > 0, "nonempty snapshot");
    char name[128];
    if (pos == 512 || pos == 8192) {
        snprintf(name, sizeof(name), "prefix-%d.payload", pos);
        dump(dir, name, snap.ptr, snap.len);
    }

    /* Capture the complete untimed trace. Different builds may legitimately
     * differ numerically; analysis records that separately from throughput.
     * Every timed replay must reproduce its own process's terminal vector.
     */
    for (int step = 0; step <= STEPS; step++) {
        logits(s, reference + (size_t)step * vocab, vocab);
        if (step < STEPS)
            check(!ds4_session_eval(s, corpus->v[pos+step], error, sizeof(error)), "reference teacher decode");
    }
    check(ds4_session_pos(s) == pos + STEPS, "reference decode frontier");
    snprintf(name, sizeof(name), "trace-%d.f32", pos);
    dump(dir, name, reference, (size_t)(STEPS+1) * vocab * sizeof(float));

    for (int trial = -WARMUPS; trial < TRIALS; trial++) {
        double before = now();
        restore(s, &snap, pos);
        double start = now();
        check(!ds4_session_eval(s, corpus->v[pos], error, sizeof(error)), "first timed token");
        double first = now();
        for (int step = 1; step < STEPS; step++)
            check(!ds4_session_eval(s, corpus->v[pos+step], error, sizeof(error)), "timed teacher decode");
        double end = now();
        check(ds4_session_pos(s) == pos + STEPS, "timed decode frontier");
        logits(s, values, vocab);
        check(!memcmp(values, reference+(size_t)STEPS*vocab, (size_t)vocab*sizeof(float)), "timed terminal equals own untimed trace");
        fprintf(decode, "%d,%d,%d,%d,%.9f,%.9f,%.9f,%.9f,%.9f\n",
            pos, trial, trial < 0, STEPS, start-before, first-start,
            end-first, end-start, (STEPS-1)/(end-first));
        fflush(decode);
        printf("DECODE context=%d trial=%d warmup=%d tps=%.4f first_ms=%.3f\n",
            pos, trial, trial < 0, (STEPS-1)/(end-first), 1000*(first-start));
        fflush(stdout);
    }

    /* Continued prefill uses 128 tokens, or 127 at the last frontier because
     * the public prefill API requires one token of generation room.
     * This complements the increasing-frontier
     * sweep. Restore/copy/write time is excluded from this engine-only timer.
     * The full prefix and suffix are identical in every build and repeat.
     */
    ds4_tokens continued = *corpus;
    int suffix_steps = pos + STEPS < CONTEXT ? STEPS : CONTEXT - pos - 1;
    check(suffix_steps > 0 && suffix_steps <= STEPS, "valid continued prefill size");
    continued.len = pos + suffix_steps;
    restore(s, &snap, pos);
    check(!ds4_session_sync(s, &continued, error, sizeof(error)), "untimed continued prefill");
    check(ds4_session_pos(s) == pos + suffix_steps, "untimed continued prefill frontier");
    logits(s, reference, vocab);
    snprintf(name, sizeof(name), "suffix-%d.f32", pos);
    dump(dir, name, reference, (size_t)vocab * sizeof(float));
    for (int trial = -WARMUPS; trial < TRIALS; trial++) {
        double before = now();
        restore(s, &snap, pos);
        double start = now();
        check(!ds4_session_sync(s, &continued, error, sizeof(error)), "timed continued prefill");
        double end = now();
        check(ds4_session_pos(s) == pos + suffix_steps, "continued prefill frontier");
        logits(s, values, vocab);
        check(!memcmp(values, reference, (size_t)vocab*sizeof(float)), "continued prefill equals own untimed vector");
        fprintf(suffix, "%d,%d,%d,%d,%.9f,%.9f,%.9f\n",
            pos, trial, trial < 0, suffix_steps, start-before, end-start, suffix_steps/(end-start));
        fflush(suffix);
        printf("SUFFIX context=%d trial=%d warmup=%d tps=%.4f\n",
            pos, trial, trial < 0, suffix_steps/(end-start));
        fflush(stdout);
    }
    restore(s, &snap, pos);
    ds4_session_snapshot_free(&snap);
    printf("PASS frontier=%d internal replay; all measured operations reached their expected position\n", pos);
    fflush(stdout);
}


/* Hold payload and teacher tokens constant, varying only one dispatch switch.
 * Stock instead compares native and imported prefixes within one process.
 * Capture rows only after evaluation: payload restoration does not restore logits.
 */
static ds4_session_snapshot read_snapshot(const char *dir, int pos) {
    char path[2048];
    snprintf(path, sizeof(path), "%s/prefix-%d.payload", dir, pos);
    FILE *f = fopen(path, "rb");
    check(f && !fseek(f, 0, SEEK_END), "open causal snapshot");
    long bytes = ftell(f); check(bytes > 0, "causal snapshot size"); rewind(f);
    ds4_session_snapshot snap = {.len=(uint64_t)bytes, .cap=(uint64_t)bytes};
    snap.ptr = malloc((size_t)bytes);
    check(snap.ptr && fread(snap.ptr, 1, bytes, f) == (size_t)bytes, "read causal snapshot");
    check(!fclose(f), "close causal snapshot");
    return snap;
}
static void select_mode(int raw_control, int mode) {
    if (raw_control && mode) check(!setenv("DS4_METAL_DISABLE_DECODE_RAW_GATHERED_ATTN", "1", 1), "set private control");
    else check(!unsetenv("DS4_METAL_DISABLE_DECODE_RAW_GATHERED_ATTN"), "clear private control");
}
static void causal_pair(ds4_session *s, const ds4_tokens *corpus, int pos,
        const char *dir, const char *import_dir, int vocab, float *values,
        float *reference, FILE *csv) {
    int raw_control = !strcmp(import_dir, "-");
    ds4_session_snapshot snaps[2] = {read_snapshot(dir, pos), {0}};
    if (!raw_control) snaps[1] = read_snapshot(import_dir, pos);
    float *terminal[2] = {malloc((size_t)vocab*sizeof(float)), malloc((size_t)vocab*sizeof(float))};
    check(terminal[0] && terminal[1], "causal terminals");
    char name[128];
    for (int mode = 0; mode < 2; mode++) {
        select_mode(raw_control, mode);
        restore(s, &snaps[raw_control ? 0 : mode], pos);
        for (int step = 0; step < STEPS; step++) {
            check(!ds4_session_eval(s, corpus->v[pos+step], error, sizeof(error)), "causal reference eval");
            logits(s, reference+(size_t)step*vocab, vocab);
        }
        memcpy(terminal[mode], reference+(size_t)(STEPS-1)*vocab, (size_t)vocab*sizeof(float));
        snprintf(name, sizeof(name), "control-%d-mode%d.f32", pos, mode);
        dump(dir, name, reference, (size_t)STEPS*vocab*sizeof(float));
    }
    /* Two ABBA blocks: each mode appears twice in warmup and four times timed. */
    const int order[] = {0,1,1,0};
    for (int trial = -4; trial < 8; trial++) {
        int mode = order[(trial+4)%4];
        select_mode(raw_control, mode);
        double before = now(); restore(s, &snaps[raw_control ? 0 : mode], pos);
        double start = now();
        check(!ds4_session_eval(s, corpus->v[pos], error, sizeof(error)), "causal first eval");
        double first = now();
        for (int step = 1; step < STEPS; step++)
            check(!ds4_session_eval(s, corpus->v[pos+step], error, sizeof(error)), "causal timed eval");
        double end = now();
        check(ds4_session_pos(s)==pos+STEPS, "causal terminal position");
        logits(s, values, vocab);
        check(!memcmp(values, terminal[mode], (size_t)vocab*sizeof(float)), "causal replay equals own reference");
        fprintf(csv, "%d,%s,%d,%d,%d,%.9f,%.9f,%.9f,%.9f\n", pos,
            raw_control ? "raw_dispatch" : "prefix_origin", mode, trial, trial<0,
            start-before, first-start, end-first, (STEPS-1)/(end-first)); fflush(csv);
        printf("CONTROL context=%d kind=%s mode=%d trial=%d tps=%.4f\n", pos,
            raw_control ? "raw_dispatch" : "prefix_origin", mode, trial, (STEPS-1)/(end-first)); fflush(stdout);
    }
    select_mode(raw_control, 0);
    for (int mode=0; mode<2; mode++) { free(terminal[mode]); ds4_session_snapshot_free(&snaps[mode]); }
}

int main(int argc, char **argv) {
    check(argc == 6, "MODEL ENCODER CORPUS OUTPUT_DIRECTORY IMPORT_DIRECTORY_OR_DASH");
    check(!getenv("DS4_METAL_DISABLE_DECODE_RAW_GATHERED_ATTN"), "ordinary starting dispatch");
    ds4_engine_options opt = {
        .model_path=argv[1], .vision_path=argv[2], .backend=BACKEND,
        .context_size=CONTEXT, .placement_ctx_hint=CONTEXT, .prefill_chunk=PREFILL,
        .placement_session_count_hint=RESIDENTS,
        .share_session_prefill_workspace=true, .warm_weights=true,
    };
    ds4_engine *engine = NULL;
    ds4_session *residents[RESIDENTS] = {0};
    double start = now();
    check(!ds4_engine_open(&engine, &opt), "engine open");
    for (int i = 0; i < RESIDENTS; i++)
        check(!ds4_session_create(&residents[i], engine, CONTEXT), "full-capacity resident allocation");
    printf("STARTUP seconds=%.6f context=%d residents=%d active=1 prefill=%d warm_weights=1\n",
        now()-start, CONTEXT, RESIDENTS, PREFILL);
    fflush(stdout);
    FILE *fp = fopen(argv[3], "rb");
    check(fp != NULL && !fseek(fp, 0, SEEK_END), "corpus open/seek");
    long bytes = ftell(fp);
    check(bytes > 0, "corpus length");
    rewind(fp);
    char *text = malloc((size_t)bytes+1);
    check(text != NULL && fread(text, 1, bytes, fp) == (size_t)bytes, "complete corpus read");
    text[bytes] = 0;
    check(!fclose(fp), "corpus close");
    ds4_tokens corpus = {0};
    ds4_tokenize_text(engine, text, &corpus);
    free(text);
    check(corpus.len >= CONTEXT, "sufficient identical teacher tokens");
    dump(argv[4], "corpus.i32", corpus.v, (size_t)CONTEXT*sizeof(*corpus.v));
    int vocab = ds4_engine_vocab_size(engine);
    check(vocab == 129280, "expected model vocabulary");
    float *values = malloc((size_t)vocab*sizeof(float));
    float *reference = malloc((size_t)(STEPS+1)*vocab*sizeof(float));
    check(values && reference, "trace buffers");

    for (int i = 1; i < RESIDENTS; i++) {
        ds4_tokens other = corpus;
        other.v += 1024*i;
        other.len = i == 1 ? 32768 : 2048;
        check(!ds4_session_sync(residents[i], &other, error, sizeof(error)), "occupy preserved resident shape");
        check(ds4_session_pos(residents[i]) == other.len, "occupied resident position");
        printf("RESIDENT index=%d capacity=%d occupied=%d\n", i, CONTEXT, other.len);
        fflush(stdout);
    }
    ds4_session *s = residents[0];
    FILE *decode = output(argv[4], "decode.csv");
    FILE *prefill = output(argv[4], "prefill.csv");
    FILE *suffix = output(argv[4], "suffix.csv");
    fprintf(decode, "context,trial,warmup,tokens,restore_seconds,first_seconds,steady_seconds,decode_seconds,steady_tps\n");
    fprintf(prefill, "context,new_tokens,seconds,tps\n");
    fprintf(suffix, "context,trial,warmup,new_tokens,restore_seconds,seconds,tps\n");
    int previous = 0;
    for (size_t i = 0; i < sizeof(frontiers)/sizeof(frontiers[0]); i++) {
        int pos = frontiers[i];
        ds4_tokens prefix = corpus;
        prefix.len = pos;
        ds4_session_set_display_progress(s, progress, NULL);
        double begin = now();
        check(!ds4_session_sync(s, &prefix, error, sizeof(error)), "incremental prefill");
        double elapsed = now()-begin;
        ds4_session_set_display_progress(s, NULL, NULL);
        check(ds4_session_pos(s) == pos, "prefill frontier");
        fprintf(prefill, "%d,%d,%.9f,%.9f\n", pos, pos-previous, elapsed, (pos-previous)/elapsed);
        fflush(prefill);
        printf("SWEEP context=%d new_tokens=%d tps=%.4f\n", pos, pos-previous, (pos-previous)/elapsed);
        fflush(stdout);
        measure_frontier(s, &corpus, pos, argv[4], vocab, values, reference, decode, suffix);
        for (int j = 1; j < RESIDENTS; j++) {
            check(!ds4_session_eval(residents[j], corpus.v[pos], error, sizeof(error)), "resident remains usable");
            logits(residents[j], values, vocab);
            char name[128];
            snprintf(name, sizeof(name), "resident-%d-at-%d.f32", j, pos);
            dump(argv[4], name, values, (size_t)vocab*sizeof(float));
        }
        previous = pos;
    }
    check(!fclose(decode) && !fclose(prefill) && !fclose(suffix), "close timings");
    FILE *causal = output(argv[4], "causal.csv");
    fprintf(causal, "context,kind,mode,trial,warmup,restore_seconds,first_seconds,steady_seconds,steady_tps\n");
    causal_pair(s, &corpus, 512, argv[4], argv[5], vocab, values, reference, causal);
    causal_pair(s, &corpus, 8192, argv[4], argv[5], vocab, values, reference, causal);
    check(!fclose(causal), "close causal timings");
    for (int i = RESIDENTS-1; i >= 0; i--) ds4_session_free(residents[i]);
    ds4_engine_close(engine);
    ds4_tokens_free(&corpus);
    free(reference);
    free(values);
    puts("PASS bounded causal full-capacity benchmark; production disk KV unused");
    return 0;
}
