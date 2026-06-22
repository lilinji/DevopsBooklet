# Engineer pamphlet operation

![DevOps](https://img.shields.io/badge/DevOps-Practices-blue)
![SRE](https://img.shields.io/badge/SRE-Reliability-green)
![Linux](https://img.shields.io/badge/Linux-Operations-orange)
![Kubernetes](https://img.shields.io/badge/Kubernetes-CloudNative-326CE5)
![Docker](https://img.shields.io/badge/Docker-Containers-2496ED)
![Security](https://img.shields.io/badge/Security-Baseline-red)
![Automation](https://img.shields.io/badge/Automation-Ansible%20%7C%20Shell%20%7C%20Python-purple)

## Project Introduction

**Engineer Operation Booklet** is a knowledge base project for IT operations, DevOps, SRE, security operations, and cloud-native platform engineers.

This project primarily collects and organizes server operation standards, common Linux operations, automated operations, database operations, security baselines, troubleshooting, cloud platforms, containerization, CI/CD, monitoring and alerting, backup and recovery, etc., helping engineers form standardized, streamlined, and engineering-oriented operational habits in production environments.

Core objectives of the project:

- Establish a systematic operations knowledge system;
- Summarize common operation standards for Linux / Bash / Python / MySQL / Redis / Nginx / Docker / Kubernetes;
- Summarize high-risk operations, risk scenarios, and incident prevention measures in production environments;
- Provide reusable Runbooks, Checklists, troubleshooting procedures, and security baselines;
- Help operations engineers, DevOps engineers, and SRE engineers improve their engineering practice capabilities.

## Suitable Careers

### The following roles or learning directions are suitable for this project:

- Linux Operations Engineer
- DevOps Engineer
- SRE Engineer
- Cloud Computing Engineer
- Cloud-Native Platform Engineer
- Operations Development Engineer
- Security Operations Engineer
- Database Operations Engineer
- Operations Manager / Operations Lead
- Development engineers who wish to systematically learn production environment operations standards

### Current Status

Currently, most online operations engineers face three main issues:

- Server operation and maintenance commands lack fine-grained summaries;
- Memory or configuration of database operation commands is incomplete;
- Server security is important, and security settings are all implemented, but there is forgetfulness in actual operations, and security awareness is weak.

- For example: At 18:00 UTC on 2017/01/31, GitLab abroad experienced a failure, losing 6 hours of production data! The GitLab database finally recovered successfully at 0:14 on February 2 Beijing time (18:14 UTC on 02/01). During operations, the Ops engineer did not check which server was being operated on, resulting in the accidental deletion of normal data.
- [GitLab Failure Article Link](https://www.oschina.net/news/81560/gitlab-707-users-lost-data)

## Server Security: What to Do and What Not to Do

- Should security settings be implemented? Should we do security or not? Or just do some basic setup?
- If security-related work can make servers and server clusters more secure, then it should be done.
- Security-related work should be done as much as possible; if you don't know how, find a way to do it. If it's really impossible, then postpone it for now. Perhaps it can't be done now, but it may be possible later. If you want to do it, you can always find a way.
- Security is no trivial matter. Think about the consequences of insecurity. If a security incident occurs, data is leaked, or the database is compromised, the consequences are very serious. There are many such cases on the Internet, so I won't elaborate.

- The project's slogan is: Use server security operation and maintenance specifications to avoid pitfalls and avoid taking the blame!

## Join Us: Contribute to the Linux Common Operations Specification Manual

- If you want to contribute or exchange ideas, please join the QQ group: (313682642)
- Email: golucklee@gmail.com

## Technical Directions

This project covers but is not limited to the following technical areas:

| Category | Content |
|---|---|
| Linux Operations | User permissions, system services, disk, network, logs, processes, performance troubleshooting |
| Shell / Bash | Automation scripts, batch tasks, inspection scripts, log processing |
| Python Operations Development | API calls, batch management, automation tools, operation platform scripts |
| Database Operations | MySQL, PostgreSQL, Redis, backup and recovery, permission control |
| Web Services | Nginx, Apache, load balancing, TLS, reverse proxy |
| Container Technology | Docker, Containerd, image building, container security |
| Kubernetes | Pod, Deployment, Service, Ingress, Helm, RBAC, cluster troubleshooting |
| Automation Operations | Ansible, Terraform, SaltStack, configuration management |
| CI/CD | Jenkins, GitLab CI, GitHub Actions, Argo CD |
| Cloud Platforms | AWS, Azure, Alibaba Cloud, Tencent Cloud, cloud resource governance |
| Observability | Prometheus, Grafana, Alertmanager, logging, distributed tracing |
| Security Operations | Linux security baseline, SSH hardening, vulnerability scanning, intrusion investigation |
| Fault Handling | Incident response, emergency plan, RCA, postmortem mechanism |
| Backup and Recovery | Data backup, snapshots, disaster recovery, recovery drills |
| Operations Standards | Runbook, Checklist, change process, release process |

Recommended reading on operations security:

**Project** (Click to Preview) | **Author ID** | **Article Link** |**Learning Resources**
-------------- | ---- | -------- | ---- |
[**# Security Operations Standards #**](https://github.com/aqzt/sso/blob/master/Server_security_operation.md)|[@ppabc](https://github.com/ppabc/)｜Security Operations Standards Initiator |[Original Link](https://github.com/aqzt/sso/blob/master/Server_security_operation.md)|[Recommend](https://github.com/aqzt/sso)｜Archive
|[- Internal Vulnerability Scanner Tool - XunFeng](https://github.com/ysrc/xunfeng)|[@ysrc](https://github.com/ysrc)｜Tongcheng Security Emergency Response Center|[Original Link](http://www.freebuf.com/articles/security-management/126254.html)|[Recommend](https://github.com/ysrc)｜Archive
|[- Honeypot System for Docker](https://github.com/atiger77/Dionaea)|[@atiger77](https://github.com/atiger77)｜atiger77|[Original Link](http://www.freebuf.com/articles/security-management/126254.html)|[Recommend](https://github.com/ysrc)｜Archive
|[- Jumpserver Bastion Host](https://github.com/jumpserver/jumpserver)|[@jumpserver](https://github.com/jumpserver)｜jumpserver|[Original Link](https://github.com/jumpserver)|[Recommend](https://github.com/jumpserver)｜Archive
|[- Script Automated Security Baseline Check](https://github.com/ppabc/security_check/tree/master/checklinux2.0)|[@ppabc](https://github.com/ppabc)｜Security Operations Standards Initiator|[Reprint Link](http://www.freebuf.com/sectool/123094.html)|[Recommend](https://github.com/ppabc/security_check)｜Archive
|[- Server Security Incident Emergency Response Investigation](https://aqzt.com/1313.html)|[@ppabc](https://github.com/ppabc)｜Security Operations Standards Initiator|[Reprint Link](https://aqzt.com/1313.html)|[Recommend](https://aqzt.com/1313.html)｜Archive
|[- Reflections on the GitLab Accidental Database Deletion Incident](http://mt.sohu.com/20170203/n479805598.shtml)|[@左耳朵耗子](http://weibo.com/haoel)｜Programmer, CoolShell Blogger|[Reprint Link](http://mt.sohu.com/20170203/n479805598.shtml)|[Recommend](http://mt.sohu.com/20170203/n479805598.shtml)｜Archive
|[- GitLab from Deletion to Recovery: Lost 6 Hours of Production Data](http://mp.weixin.qq.com/s?__biz=MzA4Nzg5Nzc5OA==&mid=2651663996&idx=1&sn=7c1eb9a34993ea50a943c73caa8bf4cb&chksm=8bcbedd5bcbc64c34f506c843d56180c65a64d36c1d9f5361d5f0e8445f8ebff57ff94db82da&scene=21#wechat_redirect)|龙井、萧田国|[Reprint Link](http://mp.weixin.qq.com/s?__biz=MzA4Nzg5Nzc5OA==&mid=2651663996&idx=1&sn=7c1eb9a34993ea50a943c73caa8bf4cb&chksm=8bcbedd5bcbc64c34f506c843d56180c65a64d36c1d9f5361d5f0e8445f8ebff57ff94db82da&scene=21#wechat_redirect)|[Recommend](http://mp.weixin.qq.com/s?__biz=MzA4Nzg5Nzc5OA==&mid=2651663996&idx=1&sn=7c1eb9a34993ea50a943c73caa8bf4cb&chksm=8bcbedd5bcbc64c34f506c843d56180c65a64d36c1d9f5361d5f0e8445f8ebff57ff94db82da&scene=21#wechat_redirect)｜Archive
|[- Operations 36 Stratagems](http://mp.weixin.qq.com/s?__biz=MzA4Nzg5Nzc5OA==&mid=2651663842&idx=1&sn=faab6acb4bd87a1f1cfe6eb8d3dc5dec&chksm=8bcbee4bbcbc675db19a57aae5eb5307f91f2656bcb39be0e98fc132be22fd5813a84855f6ed&scene=21#wechat_redirect)|梁定安、周小军|[Reprint Link](http://mp.weixin.qq.com/s?__biz=MzA4Nzg5Nzc5OA==&mid=2651663842&idx=1&sn=faab6acb4bd87a1f1cfe6eb8d3dc5dec&chksm=8bcbee4bbcbc675db19a57aae5eb5307f91f2656bcb39be0e98fc132be22fd5813a84855f6ed&scene=21#wechat_redirect)|[Recommend](http://mp.weixin.qq.com/s?__biz=MzA4Nzg5Nzc5OA==&mid=2651663842&idx=1&sn=faab6acb4bd87a1f1cfe6eb8d3dc5dec&chksm=8bcbee4bbcbc675db19a57aae5eb5307f91f2656bcb39be0e98fc132be22fd5813a84855f6ed&scene=21#wechat_redirect)｜Archive

## Acknowledgments

# IT

Learning IT Resource Collection Continuously Updated
https://github.com/lilinji/IT/wiki

<p align="center">
  <img
    src="https://raw.githubusercontent.com/lilinji/DevopsBooklet/master/WechatIMG701.jpeg"
    alt="Engineer Operation Booklet"
    width="420"
  />
</p>