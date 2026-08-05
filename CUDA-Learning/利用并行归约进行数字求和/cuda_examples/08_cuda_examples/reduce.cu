#include "reduce.h"

#include <device_launch_parameters.h>
#include <cuda.h>
#include <cuda_runtime.h>

template <class T>
__global__ void reduce0(T* g_idata, T* sum_res, unsigned int n) {
  extern __shared__ T sdata[];

  // load shared mem
  unsigned int tid = threadIdx.x;
  unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
  sdata[tid] = (i < n) ? g_idata[i] : 0;
  __syncthreads();

  // do reduction in shared mem
  for (unsigned int s = 1; s < blockDim.x; s *= 2) {
    // modulo arithmetic is slow!
    if ((tid % (2 * s)) == 0) {
      sdata[tid] += sdata[tid + s];
    }
    __syncthreads();
  }

  // write result for this block to global mem
  if (tid == 0)
    atomicAdd(sum_res, sdata[0]);
}

template <typename T>
__global__ void reduce1(T* input_data, T* sum_res, unsigned int data_size) {
  extern __shared__ T sdata[];

  unsigned int tid = threadIdx.x;
  unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
  sdata[tid] = (i < data_size) ? input_data[i] : 0;
  __syncthreads();

  // do reduction in shared mem
  for (unsigned int s = 1; s < blockDim.x; s *= 2) {
    int index = 2 * s * tid;
    if (index < blockDim.x)
      sdata[index] += sdata[index + s];
    __syncthreads();
  }

  // write result for this block to global mem
  if (tid == 0) {
    atomicAdd(sum_res, sdata[0]);
  }
}

template <class T>
__global__ void reduce2(T* g_idata, T* sum_res, unsigned int n) {
  extern __shared__ T sdata[];

  // load shared mem
  unsigned int tid = threadIdx.x;
  unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;

  sdata[tid] = (i < n) ? g_idata[i] : 0;
  __syncthreads();

  // do reduction in shared mem
  for (unsigned int s = blockDim.x / 2; s > 0; s >>= 1) {
    if (tid < s) {
      sdata[tid] += sdata[tid + s];
    }
    __syncthreads();
  }

  // write result for this block to global mem
  if (tid == 0) {
    atomicAdd(sum_res, sdata[0]);
  }
}

// template <typename T>
// __global__ void reduce2(T* input_data, T* sum_res, unsigned int data_size) {
//   extern __shared__ T sdata[];

//   unsigned int tid = threadIdx.x;
//   unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
//   sdata[tid] = input_data[i];
//   __syncthreads();

//   // do reduction in shared mem
//   for (size_t s = blockDim.x / 2; s > 0; s >>= 1) {
//     if (tid < s) {
//       sdata[tid] += sdata[tid + s];
//     }
//     __syncthreads();
//   }

//   // write result for this block to global mem
//   if (tid == 0) {
//     // sum_res[blockIdx.x] = sdata[0];
//     atomicAdd(sum_res, sdata[0]);
//   }
// }

template <typename T>
__global__ void reduce3(T* input_data, T* sum_res, unsigned int data_size) {
  extern __shared__ T sdata[];

  unsigned int tid = threadIdx.x;

  unsigned int i = blockIdx.x * (blockDim.x * 2) + threadIdx.x;

  T mySum = (i < data_size) ? input_data[i] : 0;
  if (i + blockDim.x < data_size)
    mySum += input_data[i + blockDim.x];

  sdata[tid] = mySum;
  __syncthreads();

  // do reduction in shared mem
  for (size_t s = blockDim.x / 2; s > 0; s >>= 1) {
    if (tid < s) {
      sdata[tid] += sdata[tid + s];
    }
    __syncthreads();
  }

  // write result for this block to global mem
  if (tid == 0) {
    // sum_res[blockIdx.x] = sdata[0];
    atomicAdd(sum_res, sdata[0]);
  }
}

template <typename T>
__device__ void warpReduceSum(volatile T* sdata, int tid) {
  sdata[tid] += sdata[tid + 32];
  sdata[tid] += sdata[tid + 16];
  sdata[tid] += sdata[tid + 8];
  sdata[tid] += sdata[tid + 4];
  sdata[tid] += sdata[tid + 2];
  sdata[tid] += sdata[tid + 1];
}

template <typename T>
__global__ void reduce4(T* input_data, T* sum_res, unsigned int data_size) {
  extern __shared__ T sdata[];

  unsigned int tid = threadIdx.x;
  unsigned int i = blockIdx.x * (blockDim.x * 2) + threadIdx.x;
  T mySum = (i < data_size) ? input_data[i] : 0;
  if (i + blockDim.x < data_size)
    mySum += input_data[i + blockDim.x];

  sdata[tid] = mySum;
  __syncthreads();

  // do reduction in shared mem
  for (size_t s = blockDim.x / 2; s > 32; s >>= 1) {
    if (tid < s) {
      sdata[tid] += sdata[tid + s];
    }
    __syncthreads();
  }
  //  Unroll the Last Warp
  if (tid < 32)
    warpReduceSum(sdata, tid);

  // write result for this block to global mem
  if (tid == 0) {
    // sum_res[blockIdx.x] = sdata[0];
    atomicAdd(sum_res, sdata[0]);
  }
}

template <unsigned int blockSize, typename T>
__device__ void warpReduceSumN(volatile T* sdata, unsigned int tid) {
  // clang-format off
  if (blockSize >= 64) sdata[tid] += sdata[tid + 32];
  if (blockSize >= 32) sdata[tid] += sdata[tid + 16];
  if (blockSize >= 16) sdata[tid] += sdata[tid + 8];
  if (blockSize >= 8) sdata[tid] += sdata[tid + 4];
  if (blockSize >= 4) sdata[tid] += sdata[tid + 2];
  if (blockSize >= 2) sdata[tid] += sdata[tid + 1];
  // clang-format on
}

template <unsigned int blockSize, typename T>
__global__ void reduce5(T* input_data, T* sum_res, unsigned int data_size) {
  extern __shared__ T sdata[];

  unsigned int tid = threadIdx.x;
  unsigned int i = blockIdx.x * (blockDim.x * 2) + threadIdx.x;
  T mySum = (i < data_size) ? input_data[i] : 0;
  if (i + blockDim.x < data_size)
    mySum += input_data[i + blockDim.x];

  sdata[tid] = mySum;
  __syncthreads();

  if (blockSize >= 512) {
    if (tid < 256)
      sdata[tid] += sdata[tid + 256];
    __syncthreads();
  }
  if (blockSize >= 256) {
    if (tid < 128)
      sdata[tid] += sdata[tid + 128];
    __syncthreads();
  }
  if (blockSize >= 128) {
    if (tid < 64)
      sdata[tid] += sdata[tid + 64];
    __syncthreads();
  }

  //  Unroll the Last Warp
  if (tid < 32)
    warpReduceSumN<blockSize, T>(sdata, tid);

  // write result for this block to global mem
  if (tid == 0) {
    // sum_res[blockIdx.x] = sdata[0];
    atomicAdd(sum_res, sdata[0]);
  }
}

template <unsigned int blockSize, typename T>
__global__ void reduce6(T* input_data, T* sum_res, unsigned int data_size) {
  extern __shared__ T sdata[];

  unsigned int tid = threadIdx.x;
  unsigned int i = blockIdx.x * (blockSize * 2) + threadIdx.x;
  unsigned int gridSize = blockSize * 2 * gridDim.x;
  sdata[tid] = 0;
  while (i < data_size) {
    sdata[tid] += input_data[i];
    if (i + blockSize < data_size)
      sdata[tid] += input_data[i + blockSize];
    i += gridSize;
  }
  __syncthreads();

  if (blockSize >= 1024) {
    if (tid < 512)
      sdata[tid] += sdata[tid + 512];
    __syncthreads();
  }

  if (blockSize >= 512) {
    if (tid < 256)
      sdata[tid] += sdata[tid + 256];
    __syncthreads();
  }
  if (blockSize >= 256) {
    if (tid < 128)
      sdata[tid] += sdata[tid + 128];
    __syncthreads();
  }
  if (blockSize >= 128) {
    if (tid < 64)
      sdata[tid] += sdata[tid + 64];
    __syncthreads();
  }

  if (tid < 32)
    warpReduceSumN<blockSize, T>(sdata, tid);

  // write result for this block to global mem
  if (tid == 0) {
    atomicAdd(sum_res, sdata[0]);
  }
}

template <typename T>
void sum(T* input_data, T* sum_res, unsigned int data_size, int method) {
  const int thread_num = 128;
  dim3 block(thread_num);
  dim3 grid((data_size + thread_num - 1) / thread_num);
  dim3 half_grid((data_size / 2 + thread_num - 1) / thread_num);
  dim3 log_grid((data_size / log(data_size) + thread_num - 1) / thread_num);

  switch (method) {
    case 0:
      reduce0<T><<<grid, block, thread_num * sizeof(T)>>>(input_data, sum_res, data_size);
      break;
    case 1:
      reduce1<T><<<grid, block, thread_num * sizeof(T)>>>(input_data, sum_res, data_size);
      break;
    case 2:
      reduce2<T><<<grid, block, thread_num * sizeof(T)>>>(input_data, sum_res, data_size);
      break;
    case 3:
      reduce3<T><<<half_grid, block, thread_num * sizeof(T)>>>(input_data, sum_res, data_size);
      break;
    case 4:
      reduce4<T><<<half_grid, block, thread_num * sizeof(T)>>>(input_data, sum_res, data_size);
      break;
    case 5:
      reduce5<thread_num, T>
          <<<half_grid, block, thread_num * sizeof(T)>>>(input_data, sum_res, data_size);
      break;
    case 6:
      reduce6<thread_num, T>
          <<<log_grid, block, thread_num * sizeof(T)>>>(input_data, sum_res, data_size);
      break;

    default:
      break;
  }
}

template void sum(unsigned int*, unsigned int*, unsigned int, int);