# SDN Handbook

> 一份关于 `SDN`（Software Defined Networking）的中文实战手册，整理了网络基础、Linux 内核网络、Open vSwitch、DPDK、SDN 控制器与南向协议、安全设备、NFV/SD-WAN 等方面的原理与实践。

## 关于本书

`SDN` 作为当前最重要的热门技术之一，目前已经普遍得到大家的共识。有关 SDN 的资料和书籍非常丰富，但入门和学习 `SDN` 依然非常困难。本书整理了 SDN 实践中的一些基本理论和实践案例心得，希望能给大家带来启发，也欢迎大家关注和贡献。

本书内容包括：

- 网络基础（TCP/IP、ARP、ICMP、路由、交换机、UDP/TCP、VLAN、Overlay、SNMP、LLDP）
- Linux 网络（iptables、eBPF、XDP、SR-IOV、VRF、流量控制、内核调优）
- Open vSwitch 与 OVN
- DPDK 与高性能包处理
- 安全设备（VPN、Firewall、ICG）
- SDN 控制器与南向接口（OpenFlow、NETCONF、P4、YANG）
- NFV 与 SD-WAN
- 实践案例（Mininet、Neutron、Google 数据中心网络）

## 项目源码

项目源码存放于 Github 上：[DevopsBooklet/sdn-handbook](https://github.com/lilinji/DevopsBooklet/sdn-handbook)

---

## 目录

> 本书共分为 **八篇**：网络基础、Linux 网络、Open vSwitch、DPDK、安全设备、SDN & NFV、SDN 实践、业务示例。每篇文章都列出对应链接，点击即可跳转阅读。

### 一、网络基础

> TCP/IP、ARP、ICMP、路由、交换机、UDP/TCP、VLAN、Overlay、SNMP、LLDP 等基础网络协议与设备原理。

[章节首页 →](basic/README.md)

| 主题 | 链接 |
| --- | --- |
| TCP/IP 网络模型 | [basic/tcpip.md](basic/tcpip.md) |
| ARP 协议 | [basic/arp.md](basic/arp.md) |
| ICMP 协议 | [basic/icmp.md](basic/icmp.md) |
| 路由 | [basic/route.md](basic/route.md) |
| 交换机 | [basic/switch.md](basic/switch.md) |
| UDP | [basic/udp.md](basic/udp.md) |
| DHCP / DNS | [basic/dhcp.md](basic/dhcp.md) |
| TCP | [basic/tcp.md](basic/tcp.md) |
| VLAN | [basic/vlan.md](basic/vlan.md) |
| Overlay | [basic/overlay.md](basic/overlay.md) |
| SNMP | [basic/snmp.md](basic/snmp.md) |
| LLDP | [basic/lldp.md](basic/lldp.md) |

### 二、Linux 网络

> Linux 网络配置、iptables/netfilter、负载均衡、流量控制、SR-IOV、内核 VRF、eBPF/XDP 等内核态网络技术。

[章节首页 →](linux/README.md)

| 主题 | 链接 |
| --- | --- |
| Linux 网络配置 | [linux/config.md](linux/config.md) |
| 虚拟网络设备 | [linux/virtual-device.md](linux/virtual-device.md) |
| iptables / netfilter | [linux/iptables.md](linux/iptables.md) |
| 负载均衡 | [linux/loadbalance.md](linux/loadbalance.md) |
| 流量控制（tc） | [linux/tc.md](linux/tc.md) |
| SR-IOV | [linux/sr-iov.md](linux/sr-iov.md) |
| 内核 VRF | [linux/vrf.md](linux/vrf.md) |
| eBPF 概览 | [linux/bpf/README.md](linux/bpf/README.md) |
| bcc | [linux/bpf/bcc.md](linux/bpf/bcc.md) |
| eBPF 故障排查 | [linux/bpf/troubleshooting.md](linux/bpf/troubleshooting.md) |
| XDP 概览 | [linux/XDP/README.md](linux/XDP/README.md) |
| XDP 架构 | [linux/XDP/design.md](linux/XDP/design.md) |
| XDP 使用场景 | [linux/XDP/use-cases.md](linux/XDP/use-cases.md) |
| 常用网络工具 | [linux/tools.md](linux/tools.md) |
| tcpdump 抓包 | [linux/tcpdump.md](linux/tcpdump.md) |
| scapy | [linux/scapy.md](linux/scapy.md) |
| 内核网络参数 | [linux/kernel-network-params.md](linux/kernel-network-params.md) |

### 三、Open vSwitch

> OVS 介绍、编译、内部原理；OVN 编译、实践、高可用，以及与 Kubernetes / Docker / OpenStack 的集成。

[章节首页 →](ovs/README.md)

| 主题 | 链接 |
| --- | --- |
| OVS 编译 | [ovs/build.md](ovs/build.md) |
| OVS 内部原理 | [ovs/internal.md](ovs/internal.md) |
| OVN（Open Virtual Network） | [ovs/ovn.md](ovs/ovn.md) |
| OVN 在 Ubuntu 编译 | [ovs/ovn-ubuntu.md](ovs/ovn-ubuntu.md) |
| OVN 内部实践 | [ovs/ovn-internal.md](ovs/ovn-internal.md) |
| OVN 高可用 | [ovs/ovn-ha.md](ovs/ovn-ha.md) |
| OVN Kubernetes 插件 | [ovs/ovn-kubernetes.md](ovs/ovn-kubernetes.md) |
| OVN Docker 插件 | [ovs/ovn-docker.md](ovs/ovn-docker.md) |
| OVN OpenStack | [ovs/ovn-openstack.md](ovs/ovn-openstack.md) |

### 四、DPDK

> DPDK 简介、安装、报文转发模型、NUMA、Ring 与共享内存、PCIe、网卡性能优化、多队列、硬件 offload、虚拟化、OVS+DPDK、SPDK、OpenFastPath 等高性能数据包处理技术。

[章节首页 →](dpdk/README.md)

| 主题 | 链接 |
| --- | --- |
| DPDK 简介 | [dpdk/introduction.md](dpdk/introduction.md) |
| DPDK 安装 | [dpdk/install.md](dpdk/install.md) |
| 报文转发模型 | [dpdk/forwarding.md](dpdk/forwarding.md) |
| NUMA | [dpdk/numa.md](dpdk/numa.md) |
| Ring 与共享内存（ivshmem） | [dpdk/ivshmem.md](dpdk/ivshmem.md) |
| PCIe | [dpdk/PCIe.md](dpdk/PCIe.md) |
| 网卡性能优化 | [dpdk/hardware.md](dpdk/hardware.md) |
| 多队列 | [dpdk/queue.md](dpdk/queue.md) |
| 硬件 offload | [dpdk/offload.md](dpdk/offload.md) |
| I/O 虚拟化 | [dpdk/io-virtualization.md](dpdk/io-virtualization.md) |
| OVS + DPDK | [dpdk/ovs-dpdk.md](dpdk/ovs-dpdk.md) |
| SPDK | [dpdk/spdk.md](dpdk/spdk.md) |
| OpenFastPath | [dpdk/OpenFastPath.md](dpdk/OpenFastPath.md) |

### 五、安全设备

> VPN（IPSec / SSL）、ICG、Firewall（工作原理、分类、演进）等网络安全设备与技术。

[章节首页 →](secure/README.md)

| 主题 | 链接 |
| --- | --- |
| VPN 概览 | [secure/vpn/README.md](secure/vpn/README.md) |
| IPSec VPN | [secure/vpn/ipsecvpn.md](secure/vpn/ipsecvpn.md) |
| SSL VPN | [secure/vpn/sslvpn.md](secure/vpn/sslvpn.md) |
| ICG | [secure/icg/README.md](secure/icg/README.md) |
| Firewall 概览 | [secure/fw/README.md](secure/fw/README.md) |
| Firewall 工作原理 | [secure/fw/principle.md](secure/fw/principle.md) |
| Firewall 常见分类 | [secure/fw/classify.md](secure/fw/classify.md) |
| Firewall 演进过程 | [secure/fw/evolution.md](secure/fw/evolution.md) |

### 六、SDN & NFV

> SDN 控制器（OpenDaylight / ONOS / Floodlight / Ryu / NOX-POX）、南向接口（OpenFlow / OF-Config / NETCONF / P4）、YANG、AAA / Radius、数据平面；以及 NFV、SD-WAN。

[SDN 章节首页 →](sdn/README.md) · [NFV 章节首页 →](nfv/README.md) · [SD-WAN 章节首页 →](sdwan/README.md)

#### SDN

| 主题 | 链接 |
| --- | --- |
| YANG Language | [sdn/yang-language.md](sdn/yang-language.md) |
| SDN 控制器概览 | [sdn/controller/README.md](sdn/controller/README.md) |
| OpenDaylight | [sdn/controller/odl/README.md](sdn/controller/odl/README.md) |
| OpenDaylight 子项目 | [sdn/controller/odl/projects.md](sdn/controller/odl/projects.md) |
| OpenDaylight DataStore | [sdn/controller/odl/datastore.md](sdn/controller/odl/datastore.md) |
| ONOS | [sdn/controller/onos.md](sdn/controller/onos.md) |
| Floodlight | [sdn/controller/floodlight.md](sdn/controller/floodlight.md) |
| Ryu | [sdn/controller/ryu.md](sdn/controller/ryu.md) |
| NOX / POX | [sdn/controller/pox.md](sdn/controller/pox.md) |
| 南向接口（SBI）概览 | [sdn/sbi/README.md](sdn/sbi/README.md) |
| OpenFlow | [sdn/sbi/openflow.md](sdn/sbi/openflow.md) |
| OF-Config | [sdn/sbi/of-config.md](sdn/sbi/of-config.md) |
| NETCONF | [sdn/sbi/netconf.md](sdn/sbi/netconf.md) |
| NETCONF Call Home | [sdn/sbi/netconf-call-home.md](sdn/sbi/netconf-call-home.md) |
| YANG Module for NETCONF Monitoring | [sdn/sbi/yang-module-for-netconf-monitoring.md](sdn/sbi/yang-module-for-netconf-monitoring.md) |
| NETCONF 请求/响应中的标签 | [sdn/sbi/netconf-tags.md](sdn/sbi/netconf-tags.md) |
| P4 | [sdn/sbi/p4.md](sdn/sbi/p4.md) |
| AAA | [sdn/aaa/README.md](sdn/aaa/README.md) |
| Radius | [sdn/aaa/radius.md](sdn/aaa/radius.md) |
| 数据平面 | [sdn/dataplane.md](sdn/dataplane.md) |

#### NFV & SD-WAN

| 主题 | 链接 |
| --- | --- |
| NFV | [nfv/README.md](nfv/README.md) |
| SD-WAN | [sdwan/README.md](sdwan/README.md) |

### 七、SDN 实践

> Mininet 仿真、Neutron、SDN 实践案例（含 Google 数据中心网络）。

[Mininet →](mininet/README.md) · [Neutron →](neutron/README.md) · [实践案例 →](practice/README.md)

| 主题 | 链接 |
| --- | --- |
| Mininet | [mininet/README.md](mininet/README.md) |
| Neutron | [neutron/README.md](neutron/README.md) |
| SDN 实践案例 | [practice/README.md](practice/README.md) |
| Google 数据中心网络 | [practice/google.md](practice/google.md) |

### 八、业务示例

> SDN 控制器应用场景、业务控制平台 SCP。

[章节首页 →](sample/README.md)

| 主题 | 链接 |
| --- | --- |
| SDN 控制器应用场景 | [sample/application-scenarios.md](sample/application-scenarios.md) |
| 业务控制平台 SCP | [sample/scp.md](sample/scp.md) |

### 附录

| 主题 | 链接 |
| --- | --- |
| FAQ 常见问题 | [FAQ.md](FAQ.md) |
| 参考文档 | [reference.md](reference.md) |
| 更新日志 | [CHANGELOG.md](CHANGELOG.md) |