#include "example.h"

#include <device_launch_parameters.h>
#include <cuda.h>
#include <cuda_runtime.h>

template <class T>
__global__ void VectorAddKernel(T* val1, T* val2, int n) {
  unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) {
    val1[i] = val1[i] + val2[i];
  }
}

template <class T>
void VectorAdd(T* val1, T* val2, int n) {
  const int thread_num = 128;
  dim3 block(thread_num);
  dim3 grid((n + thread_num - 1) / thread_num);
  VectorAddKernel<<<grid, block>>>(val1, val2, n);
}

template void VectorAdd(int* val1, int* val2, int n);
template void VectorAdd(unsigned int* val1, unsigned int* val2, int n);