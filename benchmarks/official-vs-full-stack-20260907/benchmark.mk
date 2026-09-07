# External benchmark rule; included after the unmodified native Makefile.
stack-bench.o: $(STACK_BENCH_SOURCE) ds4.h
	$(CC) $(filter-out -ffast-math,$(CFLAGS)) -fno-fast-math -I. -c -o $@ $(STACK_BENCH_SOURCE)

stack-bench: stack-bench.o ds4_help.o ds4_gpu_args.o $(CORE_OBJS)
ifeq ($(UNAME_S),Darwin)
	$(CC) $(CFLAGS) -o $@ $^ $(METAL_LDLIBS)
else
	$(DS4_LINK) -o $@ $^ $(DS4_LINK_LIBS)
endif
