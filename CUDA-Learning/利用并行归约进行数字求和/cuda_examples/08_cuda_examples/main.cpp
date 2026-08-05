#include <iostream>
#include <vector>

#include <cuda.h>
#include <cuda_runtime.h>

#include "example.h"
#include "reduce.h"

void testVectorAdd(int array_length) {
  std::cout << __FUNCTION__ << std::endl;

  unsigned int cpu_sum = 0;
  std::vector<unsigned int> host_arrays;
  std::vector<unsigned int> result;
  for (size_t i = 0; i < array_length; i++) {
    unsigned int val = i % 255;
    host_arrays.push_back(val);
    result.push_back(val + val);
  }
  unsigned int* device_array1 = nullptr;
  cudaMalloc(&device_array1, host_arrays.size() * sizeof(unsigned int));
  cudaMemcpy(device_array1, host_arrays.data(), host_arrays.size() * sizeof(unsigned int),
             cudaMemcpyHostToDevice);

  unsigned int* device_array2 = nullptr;
  cudaMalloc(&device_array2, host_arrays.size() * sizeof(unsigned int));
  cudaMemcpy(device_array2, host_arrays.data(), host_arrays.size() * sizeof(unsigned int),
             cudaMemcpyHostToDevice);

  VectorAdd(device_array1, device_array2, host_arrays.size());

  std::vector<unsigned int> gpu_result(array_length, 0);
  cudaMemcpy(gpu_result.data(), device_array1, host_arrays.size() * sizeof(unsigned int),
             cudaMemcpyDeviceToHost);
  for (int i = 0; i < array_length; i++) {
    if (gpu_result[i] != result[i]) {
    std:
      std::cerr << i << ":" << gpu_result[i] << ", " << result[i] << std::endl;
    }
  }
}
void test_sum(int array_length) {
  std::cout << __FUNCTION__ << std::endl;

  std::vector<unsigned int> host_arrays;
  unsigned int cpu_sum = 0;
  for (size_t i = 0; i < array_length; i++) {
    unsigned int val = i % 255;
    cpu_sum += val;
    host_arrays.push_back(val);
  }
  unsigned int* device_array = nullptr;
  cudaMalloc(&device_array, host_arrays.size() * sizeof(unsigned int));
  cudaMemcpy(device_array, host_arrays.data(), host_arrays.size() * sizeof(unsigned int),
             cudaMemcpyHostToDevice);

  unsigned int *sum_val = 0, host_val = 0;
  cudaMalloc(&sum_val, sizeof(unsigned int));
  cudaEvent_t start, stop;
  cudaEventCreate(&start);  //创建Event
  cudaEventCreate(&stop);
  for (int m = 0; m <= 6; m++) {
    std::cout << "Run method: " << m << std::endl;
    cudaMemset(sum_val, 0, sizeof(int));

    //使用event计算时间
    float time_elapsed = 0;

    cudaEventRecord(start, 0);  //记录当前时间
    sum<unsigned int>(device_array, sum_val, host_arrays.size(), m);
    cudaEventRecord(stop, 0);  //记录当前时间
    cudaEventSynchronize(stop);  // Waits for an event to complete.Record之前的任务
    cudaEventElapsedTime(&time_elapsed, start, stop);  //计算时间差
    cudaMemcpy(&host_val, sum_val, sizeof(unsigned int), cudaMemcpyDeviceToHost);
    std::cout << "sum--> host_val: " << host_val << ", " << cpu_sum << ". time_elapsed: " << time_elapsed << std::endl;
    // assert(host_val == cpu_sum);
    if (host_val != cpu_sum) {
      std::cerr << " xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
                << std::endl;
    }
  }
  cudaEventDestroy(start);
  cudaEventDestroy(stop);
  cudaFree(sum_val);
}

int main(int argc, char* argv[]) {
  int method = 0;
  int array_length = 10;
  if (argc > 1) {
    array_length = std::stoi(argv[1]);
  }

  // warmup
  testVectorAdd(array_length);

  test_sum(array_length);
}