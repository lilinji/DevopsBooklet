# 工程师运维小册（Engineer pamphlet operation）


![DevOps](https://img.shields.io/badge/DevOps-Practices-blue)
![SRE](https://img.shields.io/badge/SRE-Reliability-green)
![Linux](https://img.shields.io/badge/Linux-Operations-orange)
![Kubernetes](https://img.shields.io/badge/Kubernetes-CloudNative-326CE5)
![Docker](https://img.shields.io/badge/Docker-Containers-2496ED)
![Security](https://img.shields.io/badge/Security-Baseline-red)
![Automation](https://img.shields.io/badge/Automation-Ansible%20%7C%20Shell%20%7C%20Python-purple)
![SDN](https://img.shields.io/badge/SDN-Software%20Defined%20Networking-blue)


## 项目简介

**Engineer Operation Booklet｜工程师运维小册** 是一个面向 IT 运维、DevOps、SRE、安全运维、云原生平台工程师的知识库项目。

本项目主要收集和整理服务器运维规范、Linux 常用操作、自动化运维、数据库运维、安全基线、故障排查、云平台、容器化、CI/CD、监控告警、备份恢复等内容，帮助工程师在实际生产环境中形成标准化、流程化、工程化的操作习惯。

项目核心目标：

- 建立系统化的运维知识体系；
- 汇总常见 Linux / Bash / Python / MySQL / Redis / Nginx / Docker / Kubernetes 操作规范；
- 总结生产环境中的高危操作、风险场景与事故预防措施；
- 提供可复用的 Runbook、Checklist、故障排查流程和安全基线；
- 帮助运维工程师、DevOps 工程师和 SRE 工程师提升工程实践能力。


## 适合的职业

### 本项目适合以下岗位或学习方向：
- Linux 运维工程师
- DevOps 工程师
- SRE 工程师
- 云计算工程师
- 云原生平台工程师
- 运维开发工程师
- 安全运维工程师
- 数据库运维工程师
- 运维经理 / 运维负责人
- 希望系统学习生产环境运维规范的开发工程师

### 现状
目前，网上运维工程师，大部分都存在这三方面的问题：

- 服务器运维操作命令没有细粒度总结；
- 数据库操作命令记忆或设置不全面；
- 服务器安全重要，安全设置都有做，但实际操作有遗忘，安全意识不强。

- 比如：在2017/01/31 18:00 UTC国外Gitlab出现故障，丢失了6小时的生产数据！Gitlab 数据库终于在北京时间 2月2日 0:14 恢复成功（18:14 UTC 02/01）。运维工程师操作时。没有检查正在操作的服务器，以至于误删除了正常的数据。
- [GitLab故障文章链接](https://www.oschina.net/news/81560/gitlab-707-users-lost-data)

## 服务器安全那些要做，那些不要做
- 安全设置要不要做？做安全还是不做安全？还是说只做一些基础设置。
- 如果安全相关工作，能让服务器和服务器集群更安全，那就要去做。
- 安全的相关工作尽量做，不会做的想办法做，实在没法做的，那就延后再说，也许现在没办法做，可能以后有办法，想做总能找到办法。
- 安全无小事，要想想不安全的后果，如果出现安全事件，数据泄露，数据库被拖库，后果是很严重的，这样的案例互联网上很多，就不多说了。

- 项目的口号是：使用服务器安全运维规范，不掉坑，不背锅！

## 一起来参与，补充linux常用运维规范手册
- 如果想要贡献或是交流的话，请加 QQ 群： （313682642）
- Email：golucklee@gmail.com

## 技术方向

本项目覆盖但不限于以下技术方向：

| 分类 | 内容 |
|---|---|
| Linux 运维 | 用户权限、系统服务、磁盘、网络、日志、进程、性能排查 |
| Shell / Bash | 自动化脚本、批量任务、巡检脚本、日志处理 |
| Python 运维开发 | API 调用、批量管理、自动化工具、运维平台脚本 |
| 数据库运维 | MySQL、PostgreSQL、Redis、备份恢复、权限控制 |
| Web 服务 | Nginx、Apache、负载均衡、TLS、反向代理 |
| 容器技术 | Docker、Containerd、镜像构建、容器安全 |
| Kubernetes | Pod、Deployment、Service、Ingress、Helm、RBAC、集群排障 |
| 自动化运维 | Ansible、Terraform、SaltStack、配置管理 |
| CI/CD | Jenkins、GitLab CI、GitHub Actions、Argo CD |
| 云平台 | AWS、Azure、阿里云、腾讯云、云资源治理 |
| 可观测性 | Prometheus、Grafana、Alertmanager、日志、链路追踪 |
| 安全运维 | Linux 安全基线、SSH 加固、漏洞扫描、入侵排查 |
| 故障处理 | 事故响应、应急预案、RCA、复盘机制 |
| 备份恢复 | 数据备份、快照、灾备、恢复演练 |
| 运维规范 | Runbook、Checklist、变更流程、发布流程 |

关于运维安全的推荐阅读：

**项目**（点击预览）| **文章作者 ID** | **文章链接** |**学习资源**
-------------- | ---- | -------- | ---- |
[**# 安全运维规范 #**](https://github.com/aqzt/sso/blob/master/Server_security_operation.md)|[@ppabc](https://github.com/ppabc/)｜安全运维规范发起人 |[原创链接](https://github.com/aqzt/sso/blob/master/Server_security_operation.md)|[推荐](https://github.com/aqzt/sso)｜归档
|[- 内部漏扫工具-巡风](https://github.com/ysrc/xunfeng)|[@ysrc](https://github.com/ysrc)｜同程安全应急响应中心|[原创链接](http://www.freebuf.com/articles/security-management/126254.html)|[推荐](https://github.com/ysrc)｜归档
|[- Docker的蜜罐系统](https://github.com/atiger77/Dionaea)|[@atiger77](https://github.com/atiger77)｜atiger77|[原创链接](http://www.freebuf.com/articles/security-management/126254.html)|[推荐](https://github.com/ysrc)｜归档
|[- jumpserver跳板机](https://github.com/jumpserver/jumpserver)|[@jumpserver](https://github.com/jumpserver)｜jumpserver|[原创链接](https://github.com/jumpserver)|[推荐](https://github.com/jumpserver)｜归档
|[- 脚本自动安全检查基线](https://github.com/ppabc/security_check/tree/master/checklinux2.0)|[@ppabc](https://github.com/ppabc)｜安全运维规范发起人|[转载链接](http://www.freebuf.com/sectool/123094.html)|[推荐](https://github.com/ppabc/security_check)｜归档
|[- 服务器安全事件应急响应排查](https://aqzt.com/1313.html)|[@ppabc](https://github.com/ppabc)｜安全运维规范发起人|[转载链接](https://aqzt.com/1313.html)|[推荐](https://aqzt.com/1313.html)｜归档
|[- GitLab误删除数据库事件的几点思考](http://mt.sohu.com/20170203/n479805598.shtml)|[@左耳朵耗子](http://weibo.com/haoel)｜程序员，酷壳博主|[转载链接](http://mt.sohu.com/20170203/n479805598.shtml)|[推荐](http://mt.sohu.com/20170203/n479805598.shtml)｜归档
|[- Gitlab从删库到恢复：丢失6小时生产数据](http://mp.weixin.qq.com/s?__biz=MzA4Nzg5Nzc5OA==&mid=2651663996&idx=1&sn=7c1eb9a34993ea50a943c73caa8bf4cb&chksm=8bcbedd5bcbc64c34f506c843d56180c65a64d36c1d9f5361d5f0e8445f8ebff57ff94db82da&scene=21#wechat_redirect)|龙井、萧田国|[转载链接](http://mp.weixin.qq.com/s?__biz=MzA4Nzg5Nzc5OA==&mid=2651663996&idx=1&sn=7c1eb9a34993ea50a943c73caa8bf4cb&chksm=8bcbedd5bcbc64c34f506c843d56180c65a64d36c1d9f5361d5f0e8445f8ebff57ff94db82da&scene=21#wechat_redirect)|[推荐](http://mp.weixin.qq.com/s?__biz=MzA4Nzg5Nzc5OA==&mid=2651663996&idx=1&sn=7c1eb9a34993ea50a943c73caa8bf4cb&chksm=8bcbedd5bcbc64c34f506c843d56180c65a64d36c1d9f5361d5f0e8445f8ebff57ff94db82da&scene=21#wechat_redirect)｜归档
|[- 运维三十六计](http://mp.weixin.qq.com/s?__biz=MzA4Nzg5Nzc5OA==&mid=2651663842&idx=1&sn=faab6acb4bd87a1f1cfe6eb8d3dc5dec&chksm=8bcbee4bbcbc675db19a57aae5eb5307f91f2656bcb39be0e98fc132be22fd5813a84855f6ed&scene=21#wechat_redirect)|梁定安、周小军|[转载链接](http://mp.weixin.qq.com/s?__biz=MzA4Nzg5Nzc5OA==&mid=2651663842&idx=1&sn=faab6acb4bd87a1f1cfe6eb8d3dc5dec&chksm=8bcbee4bbcbc675db19a57aae5eb5307f91f2656bcb39be0e98fc132be22fd5813a84855f6ed&scene=21#wechat_redirect)|[推荐](http://mp.weixin.qq.com/s?__biz=MzA4Nzg5Nzc5OA==&mid=2651663842&idx=1&sn=faab6acb4bd87a1f1cfe6eb8d3dc5dec&chksm=8bcbee4bbcbc675db19a57aae5eb5307f91f2656bcb39be0e98fc132be22fd5813a84855f6ed&scene=21#wechat_redirect)｜归档




## 鸣谢

# IT
学习IT资源收集持续更新
https://github.com/lilinji/IT/wiki 

<p align="center">
  <img
    src="https://raw.githubusercontent.com/lilinji/DevopsBooklet/master/WechatIMG701.jpeg"
    alt="Engineer Operation Booklet"
    width="420"
  />
</p>
