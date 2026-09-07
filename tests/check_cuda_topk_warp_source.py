#!/usr/bin/env python3
"""Keep the adversarial top-k fixture tied to the actual runtime kernels."""
from pathlib import Path


def function(source, signature):
    assert source.count(signature) == 1, signature
    start = source.index(signature)
    end = source.index("\n}\n", start) + 3
    return source[start:end]


def check(source, fixture):
    reference = (fixture / "reference-kernels.cuh").read_text()
    candidate = (fixture / "candidate-kernels.cuh").read_text()
    comparator = "__device__ __forceinline__ static bool topk_score_better("
    assert function(source, comparator) == function(reference, comparator)
    for signature in (
        "__device__ __forceinline__ static void topk_warp_step(",
        "template <uint32_t SORT_N>\n__device__ __forceinline__ static void topk_sort_warp_tail(",
    ):
        assert function(source, signature) == function(candidate, signature), signature
    for name in ("chunk", "merge", "tree_merge"):
        runtime_name = "indexer_topk_" + name + "_pow2_kernel"
        fixture_name = "candidate_topk_" + name + "_pow2_kernel"
        signature = "template <uint32_t SORT_N>\n__global__ static void "
        actual = function(source, signature + runtime_name + "(")
        expected = function(candidate, signature + fixture_name + "(")
        assert actual.replace(runtime_name, fixture_name) == expected, runtime_name


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    check((root / "ds4_cuda.cu").read_text(), root / "tests/cuda_topk_warp")
    print("PASS actual comparator, warp helpers and all three runtime kernels match the fixture")
