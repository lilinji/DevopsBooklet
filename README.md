# 工程师运维小册（Engineer pamphlet operation）

![Image text](https://raw.githubusercontent.com/lilinji/DevopsBooklet/master/WechatIMG701.jpeg)


## 项目简介
- Booklet 主要是汇集整理IT运维规范，包括运维工程师日常的操作、包含 Bash、Python、Mysql、学习服务器运维中注意事项、故障避免手段等文档，帮助运维工程师避免服务器安全和运维故障，方便运维工程师学习成长。


## 适合的职业
- 运维工程师
- 运维经理
- 运维总监
- 资深运维工程师
- 安全运维工程师
- 运维开发工程师
- 安全工程师

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
