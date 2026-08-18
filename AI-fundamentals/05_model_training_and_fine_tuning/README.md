# 模型训练与微调

![SFT](https://img.shields.io/badge/SFT-Supervised%20Fine%20Tuning-orange) ![LoRA](https://img.shields.io/badge/LoRA-Efficient%20Tuning-purple) ![AIOps](https://img.shields.io/badge/AIOps-Post%20Training-blue)

> **章节定位**：开源基座只是起点——后训练、SFT、评估与基准生成，才是模型真正跑进业务的那段路。
>
> **学完能做**：用 Qwen2 + LoRA 跑完一次完整指令微调；理解 70B 从零训练的数据清洗与基础设施；搭建 AIOps 场景的模型评估与基准生成框架。
>
> **本章核心**：训完了到底行不行，评测数据从哪儿来，一次讲清。

---

开源基座模型只是起点——真正决定它能否在业务里跑起来的，是预训练之后的那一段路：用领域数据做后训练、用 SFT 把能力对齐到具体任务、再用基准评测量化它在目标场景的真实水平。本目录围绕这条链路展开：一侧是运维（AIOps）场景下的后训练方法论与评估/基准生成框架，另一侧是一份可以跑起来的 SFT 实战样例，涵盖从理论到落地的完整闭环。

---

## 1. AIOps 后训练与评估（`ai_ops_design`）

这三份文档是一条连续的工程线：先讨论怎么把通用大模型后训练成 AIOps 专家，再回答「训完了到底行不行」，最后解决「评测数据从哪儿来」。完整索引见 [`ai_ops_design/README.md`](ai_ops_design/README.md)。

- [AIOps 后训练技术](ai_ops_design/aiops_post_training.md) — 给出从基座模型选型到后训练全流程的方法论，拆解告警理解、根因推断、工具调用等七项核心能力的训练路径。
- [Kubernetes AIOps 模型评估框架](ai_ops_design/kubernetes_model_evaluation_framework.md) — 以「知识验证 / 推理评估 / 场景测试」三位一体为骨架，覆盖控制面、Pod、节点、网络、存储、自动化运维、安全合规 7 个维度的能力指标体系。
- [Kubernetes AIOps 基准测试生成框架](ai_ops_design/kubernetes_aiops_benchmark_generation_framework.md) — 用 GPT-5 / DeepSeek 等模型驱动基准用例的自动生成流水线，把评估标准编码为可复现的 prompt 模板，解决测试集规模化与多样性问题。

---

## 2. SFT 实战（`sft_example`）

从「读懂理论」到「跑出一个自己的微调模型」之间隔着一堆工程细节：数据格式、LoRA 配置、显存预算、推理验证。下面的材料把这些细节压在一个可运行的样例里。

- [SFT 实战指南](sft_example/README.md) — 实战项目的入口页，包含环境、数据、运行步骤与理论速览。
- [Qwen2 指令微调 Notebook](sft_example/train_qwen2.ipynb) — 基于 Qwen2-1.5B-Instruct + LoRA，用 ModelScope 数据集和 SwanLab 监控跑完一次完整的指令微调。
- [一文入门垂域模型 SFT 微调](sft_example/一文入门垂域模型SFT微调.md) — 以金融「企业年报分析助手」为案例，串起数据构建、基座选型、训练配置、评估与灰度上线的全链路。
