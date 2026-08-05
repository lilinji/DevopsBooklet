
# CUDA GPU 并行编程学习资料合集

> 📌 本仓库整合了 CUDA 学习所需的权威教材、视频课程配套代码/PPT、以及实战示例，覆盖从入门到进阶的完整学习路径。

---

## 📚 资源总览

```
CUDA-Learning/
├── 📖 8 本 PDF 书籍（入门→进阶→专家）
├── 🎥 罗韵老师 CUDA 视频课程（12 课 PPT + 代码）
├── 🏫 周斌 CUDA 编程课程（6 讲 PDF）
├── 🧵 《CUDA 编程：基础与实践》源码（14 章）
├── 📘 《CUDA C 编程权威指南》源码（10 章 + Solutions）
├── 🖼️ 《基于 CUDA 的 GPU 并行程序开发指南》代码（CPU/CUDA 对照）
├── 🔢 并行归约渐进式优化（7 种算法）
└── 🎬 Cuda 编程（并行计算）视频课程（9 节）
```

---

## 一、📖 书籍 PDF（8 本）

| 序号 | 书名 | 本地路径 | 适合阶段 |
|:---:|------|----------|:---:|
| 1 | **CUDA C 编程权威指南**（含高分辨率版） | `CUDA C编程权威指南/` | 入门→进阶 |
| 2 | **CUDA 编程：基础与实践**（樊哲勇） | `CUDA 编程：基础与实践/` | 入门→进阶 |
| 3 | **CUDA 并行程序设计 GPU 编程指南** | `CUDA并行程序设计-GPU编程指南/` | 进阶 |
| 4 | **基于 CUDA 的 GPU 并行程序开发指南** | `基于CUDA的GPU并行程序开发指南/` | 进阶 |
| 5 | **GPU 高性能编程 CUDA 实战**（Sanders 著） | `[GPU高性能编程CUDA实战].(桑德斯).聂雪军等.pdf` | 入门 |
| 6 | **高性能 CUDA 应用设计与开发 方法与最佳实践** | `高性能CUDA应用设计与开发 方法与最佳实践 (罗布,于玉龙) (Z-Library).pdf` | 进阶 |
| 7 | **CUDA 高性能并行计算** | `CUDA高性能并行计算.pdf` | 进阶 |
| 8 | **CUDA 专家手册：GPU 编程权威指南** | `CUDA专家手册：GPU编程权威指南_迷你书.pdf` | 专家 |

---

## 二、🎥 罗韵老师 CUDA 视频课程（12 课）

📁 `罗韵老师cuda视频PPT及代码/` ｜ B 站视频号：`BV1z4411a7Ny`

| 课次 | 主题 | 代码/资料 |
|:---:|------|------|
| 第1课 | CUDA 概述与环境搭建 | PPT + 参考书 `professional_cuda_c_programming.pdf` |
| 第2课 | CUDA 编程基础 | `square.cu`（第一个 CUDA 程序） |
| 第3课 | 归约（Reduce）、扫描（Scan）、原子操作、内存类型 | `reduce.cu`, `scan.cu`, `atomics.cu`, `memory.cu`, `gputimer.h` |
| 第4课 | 直方图（Histogram） | `histo.cu` + 第三周作业答案 |
| 第5课 | 图像处理：RGB→灰度、模糊 | `rgb2grey.cu`, `blur.cu` |
| 第6课 | 纹理内存与纹理操作 | PPT + `纹理内存与纹理操作.pdf` |
| 第7课 | 矩阵转置优化 | `transpose.cu`, `deviceQuery_simplified.cpp` |
| 第8课 | 多 GPU / CUDA-Aware MPI | `cuda-aware-mpi-example.zip`, AWS 使用指南, `GPU_2.pem` |
| 第9课 | KNN 算法的 CUDA 实现 | `knn_cuda_with_indexes.cu` |
| 第10课 | CUDA-OpenGL 互操作 | `simpleGL.cu`, `test_opengl_cuda.cu`, GTC 参考资料 |
| 第11课 | LK 光流跟踪（计算机视觉实战） | `cudaLK/` 完整项目（`.cu` + `.h` + `main.cc`） |
| 第12课 | 课程总结 | PPT |

---

## 三、🏫 周斌 CUDA 编程课程（6 讲）

📁 `周斌-CUDA编程课程/`

| 讲次 | 内容 |
|:---:|------|
| 01 | CPU 体系架构概述 |
| 02 | 并行程序设计概述 |
| 03 | GPU 架构体系概述 |
| 04 | CUDA-GPU 编程模型 |
| 05 | CUDA 编程（1） |
| 06 | CUDA 编程（2） |

---

## 四、🧵 《CUDA 编程：基础与实践》源码（14 章）

📁 `CUDA 编程：基础与实践/codes/` ｜ 作者：樊哲勇

| 章节 | 主题 | 核心代码 |
|:---:|------|------|
| ch1 | GPU 硬件与 CUDA 开发工具 | README（环境配置说明） |
| ch2 | CUDA 线程组织 | `hello1.cpp` → `hello5.cu`（5 步递进） |
| ch3 | 简单 CUDA 程序的基本框架 | `add.cpp` → `add4device.cu`（CPU→GPU 渐进） |
| ch4 | CUDA 程序的错误检测 | `check1api.cu`, `check2kernel.cu`, `memcheck.cu` |
| ch5 | 获得 GPU 加速的关键 | `add1cpu.cu` vs `add2gpu.cu`（性能对比） |
| ch6 | CUDA 的内存组织 | `query.cu`, `static.cu` + 内存结构图 |
| ch7 | 全局内存的合理使用 | `matrix.cu`（矩阵运算内存优化） |
| ch8 | 共享内存的合理使用 | `reduce1cpu.cu` → `reduce2gpu.cu`, `bank.cu` |
| ch9 | 原子函数的合理使用 | `reduce.cu`, `neighbor1cpu.cu` → `neighbor2gpu.cu` |
| ch10 | 线程束基本函数与协作组 | `reduce` 系列, `warp.cu`（warp shuffle） |
| ch11 | CUDA 流 | kernel-transfer 重叠, HyperQ 深度/广度并发 |
| ch12 | 使用统一内存编程 | `prefetch.cu`, `oversubscription` 系列 |
| ch13 | **分子动力学模拟的 CUDA 程序开发** | `cpp/` `force-only/` `whole-code/` 三个完整版本 |
| ch14 | CUDA 标准库的使用 | `cublas_gemm.cu`, `curand`, `cusolver`, `thrust` |

---

## 五、📘 《CUDA C 编程权威指南》源码（10 章 + 习题解答）

📁 `CUDA C编程权威指南/源代码/CodeSamples/`

| 章节 | 内容 | 代码量 |
|:---:|------|:---:|
| ch01 | Hello World — 第一个 CUDA 程序 | 1 |
| ch02 | 线程/网格/块组织、数组求和、矩阵求和（5 种映射） | 7 |
| ch03 | 嵌套归约、设备查询、分支发散 | 7 |
| ch04 | 全局内存访问模式（AoS/SoA）、矩阵转置、统一/零拷贝内存 | 10 |
| ch05 | 共享内存 Bank、常量内存、shuffle 指令 | 7 |
| ch06 | 异步 API、流回调、HyperQ（深度/广度/OpenMP） | 6 |
| ch07 | 原子操作、浮点精度、N 体问题、内联 PTX | 5 |
| ch08 | cuBLAS、cuFFT、cuSPARSE、OpenACC、drop-in 替换 | 10 |
| ch09 | 多 GPU、P2P 通信、CUDA-Aware MPI、2D 有限差分 | 5 |
| ch10 | 综合案例：DES 密码破解加速 + 调试（segfault/hazard） | 14 |

📁 `Solutions/` — **官方习题解答**（ch02-ch09 + `ExerciseSolutions.pdf`）

📁 `lectures_code/` — **ISO 2D/3D 波动方程模拟**：从 CPU 单线程 → GPU 全局内存 → 共享内存 → 常量内存 → 多 GPU → MPI 的完整性能调优案例（20+ 个版本）

---

## 六、🖼️ 《基于 CUDA 的 GPU 并行程序开发指南》代码

CPU → GPU 迁移对照学习

| 案例 | CPU 版本 | GPU 版本 |
|------|------|------|
| 图像翻转 | `C1-imflip`（单线程）→ `C2-imflipP`（多线程）→ `C3-imflipPM`（MMX） | `imflipG.cu`, `imflipG2.cu`, `imflipGCM.cu` |
| 图像旋转 | `C4-imrotate` | — |
| 边缘检测 | `C5-imedge` | `imedgeG.cu`, `imedgeGCM.cu` |
| 图像拉伸 | — | `imGStr.cu` |

---

## 七、🔢 并行归约渐进式优化（7 种算法）

📁 `利用并行归约进行数字求和/cuda_examples/08_cuda_examples/`

| 版本 | 优化策略 | 关键改进 |
|:---:|------|------|
| reduce0 | 基础交错归约 | 使用取模运算，有 warp divergence 和 bank conflict |
| reduce1 | 索引替代取模 | `index = 2 * s * tid` 消除取模开销 |
| reduce2 | 非交错归约 | 前半部分 ↔ 后半部分配对，避免 bank conflict |
| reduce3 | 一次加载两个元素 | 每个线程预加载 2 个元素，减少 grid 启动量 |
| reduce4 | 展开最后一个 warp | 用 `warpReduceSum` 手动展开 32 线程内的归约 |
| reduce5 | 完全模板化展开 | `reduce5<blockSize>` 编译期决定循环展开 |
| reduce6 | grid-stride loop | 每个线程串行累加多元素，减少 grid 大小 |

---

## 八、🗺️ 推荐学习路线

```
┌─ 入门阶段（1-2 周）──────────────────────────────────┐
│  罗韵第1-2课：环境搭建 + 第一个 CUDA 程序              │
│  《CUDA 编程：基础与实践》ch1-ch3：线程/程序框架        │
│  《CUDA C 编程权威指南》ch01-ch02                      │
│  周斌课程 01-04：体系架构 + 编程模型                    │
├─ 基础阶段（2-4 周）──────────────────────────────────┤
│  罗韵第3-5课：归约/扫描/图像处理                        │
│  《CUDA 编程：基础与实践》ch4-ch8：错误检测 + 内存层次   │
│  《CUDA C 编程权威指南》ch03-ch05                      │
│  并行归约示例 — 深入理解 7 种优化策略                   │
├─ 进阶阶段（4-8 周）──────────────────────────────────┤
│  罗韵第6-10课：纹理/转置/MPI/OpenGL                     │
│  《CUDA 编程：基础与实践》ch9-ch12：原子/流/统一内存     │
│  《CUDA C 编程权威指南》ch06-ch08：库函数               │
│  ISO 2D/3D 波动方程案例                                │
├─ 高级阶段（8-12 周）─────────────────────────────────┤
│  罗韵第11课：LK 光流跟踪（CV 实战）                     │
│  《CUDA 编程：基础与实践》ch13-ch14：分子动力学 + 标准库 │
│  《CUDA C 编程权威指南》ch09-ch10：多GPU + 密码学        │
│  图像处理 CPU→GPU 迁移案例                             │
└──────────────────────────────────────────────────────┘
```

---

## 九、关键技术点索引

| 想学习的内容 | 去哪里找 |
|------|------|
| 第一个 CUDA 程序 / 环境搭建 | 罗韵第1-2课、《基础与实践》ch1-ch3、《权威指南》ch01 |
| 线程/网格/块组织 | 《基础与实践》ch2、《权威指南》ch02 |
| 内存类型与优化（全局/共享/常量/纹理） | 《基础与实践》ch6-ch8、《权威指南》ch04-ch05 |
| 归约算法 7 种优化 | `利用并行归约进行数字求和/` |
| Warp Shuffle / 协作组 | 《基础与实践》ch10、《权威指南》ch05 |
| CUDA Streams / HyperQ 并发 | 《基础与实践》ch11、《权威指南》ch06 |
| 原子操作 | 《基础与实践》ch9、《权威指南》ch07 |
| 矩阵转置优化 | 罗韵第7课、《权威指南》ch04 |
| cuBLAS / cuFFT / cuSPARSE / cuRAND | 《基础与实践》ch14、《权威指南》ch08 |
| 统一内存（Unified Memory） | 《基础与实践》ch12、《权威指南》ch04 |
| 多 GPU / P2P / MPI | 《权威指南》ch09、罗韵第8课、ISO 案例 |
| CUDA-OpenGL 互操作 | 罗韵第10课 |
| LK 光流（计算机视觉） | 罗韵第11课 |
| 分子动力学模拟 | 《基础与实践》ch13（cpp/force-only/whole-code） |
| 密码学加速 | 《权威指南》ch10 |
| N-body 天体模拟 | 《权威指南》ch07 |
| 图像处理 CPU→GPU 迁移 | 《开发指南》CPU-CODE vs CUDA-CODE 对照 |
| **在线参考** | [CUDA C++ Programming Guide](https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html) · [超算习堂](https://easyhpc.net/course) · [CUDA Toolkit 下载](https://developer.nvidia.com/cuda-toolkit-archive) |

---

## ⚠️ 使用须知

- **硬件要求**：大部分源码需要 NVIDIA GPU 才能编译运行
- **软件环境**：安装 [CUDA Toolkit](https://developer.nvidia.com/cuda-toolkit-archive) + 对应显卡驱动
- **编译方式**：各章节目录下均有 `Makefile`，执行 `make` 即可编译；部分 Windows 项目提供 `makefile.windows`
- **代码年代**：部分代码可能需要针对新版 CUDA API 做适配调整
