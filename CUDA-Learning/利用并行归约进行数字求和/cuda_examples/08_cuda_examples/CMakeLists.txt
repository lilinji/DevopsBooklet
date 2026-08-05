cmake_minimum_required(VERSION 3.10)
PROJECT(reduce LANGUAGES C CXX CUDA)

find_package(CUDA REQUIRED)
list(APPEND ALL_LIBS 
  ${CUDA_LIBRARIES} 
  ${CUDA_cublas_LIBRARY} 
  ${CUDA_nppc_LIBRARY} ${CUDA_nppig_LIBRARY} ${CUDA_nppidei_LIBRARY} ${CUDA_nppial_LIBRARY})
list(APPEND INCLUDE_DRIS ${CUDA_INCLUDE_DIRS})


file(GLOB ALL_CU_SOURCES *.cu)

message(STATUS "ALL_LIBS:${ALL_LIBS}")

include_directories(${CMAKE_CURRENT_SOURCE_DIR} ${INCLUDE_DRIS})
add_executable(${PROJECT_NAME} ${ALL_CU_SOURCES} main.cpp)
target_link_libraries(${PROJECT_NAME}  ${ALL_LIBS})

set_property(TARGET ${PROJECT_NAME} PROPERTY CUDA_ARCHITECTURES 50 61 72 75)
target_compile_options(${PROJECT_NAME} PUBLIC 
  $<$<COMPILE_LANGUAGE:CUDA>:--default-stream per-thread -lineinfo; --use_fast_math --disable-warnings>)

# add_executable(main main.cpp)
# target_link_libraries(main ${PROJECT_NAME} ${ALL_LIBS})