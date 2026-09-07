# Link new external frontends against byte-verified existing runtime objects.
$(CAUSAL_OBJECT): $(STACK_BENCH_SOURCE) ds4.h
	$(CC) $(filter-out -ffast-math,$(CFLAGS)) -fno-fast-math -I. -c -o $@ $(STACK_BENCH_SOURCE)
$(CAUSAL_BINARY): $(CAUSAL_OBJECT) ds4_help.o ds4_gpu_args.o $(CORE_OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(METAL_LDLIBS)
