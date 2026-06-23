# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Type

This is **not a code project**. It is a Chinese-language technical handbook about SDN (Software Defined Networking) authored with [GitBook](https://www.gitbook.com). All content lives in Markdown files; there is no source code, test suite, or linter.

Online reading: <https://tonydeng.gitbooks.io/sdn/> · GitHub mirror: <https://github.com/tonydeng/sdn-handbook>

## Build

The book is built via `gitbook-cli` and deployed by Travis CI to GitHub Pages (`tonydeng.github.io/sdn/`). The build output directory `_book/` and ebook artifacts (`*.epub`, `*.mobi`, `*.pdf`) are gitignored.

Local build:

```bash
npm install -g gitbook-cli
gitbook install            # install plugins declared in book.json
gitbook build              # produces _book/
gitbook serve              # local preview at http://localhost:4000
```

CI configuration: `.travis.yml` runs `gitbook build` on the `master` branch and pushes `_book/` to GitHub Pages.

## Architecture & Content Structure

The book's table of contents is declared in **`SUMMARY.md`** — this is GitBook's navigation source of truth. Every section listed there must resolve to an existing file. The build will fail if a link in `SUMMARY.md` points to a missing `.md` file.

The book is organized by topic (see `SUMMARY.md` for the full tree). Top-level sections:

| Section | Directory | Topic |
|---|---|---|
| 网络基础 | `basic/` | TCP/IP, ARP, ICMP, routing, switching, UDP/TCP, VLAN, Overlay, SNMP, LLDP |
| Linux网络 | `linux/` | Linux networking: iptables, eBPF, XDP, VRF, SR-IOV, traffic control, kernel params, tcpdump/scapy |
| Open vSwitch | `ovs/` | OVS build, internals, OVN (Ubuntu, internals, HA, Kubernetes/Docker/OpenStack plugins) |
| DPDK | `dpdk/` | DPDK intro, install, forwarding model, NUMA, ring/shared mem, PCIe, NIC optimization, multi-queue, offload, virt, OVS+DPDK, SPDK, OpenFastPath |
| 安全设备 | `secure/` | VPN (IPSec, SSL), ICG, Firewall (principle, classify, evolution) |
| SDN&NFV | `sdn/`, `nfv/`, `sdwan/` | SDN controllers (ODL, ONOS, Floodlight, Ryu, NOX/POX), southbound interfaces (OpenFlow, OF-Config, NETCONF, P4), YANG, AAA/Radius, NFV, SD-WAN |
| SDN实践 | `mininet/`, `neutron/`, `practice/` | Mininet, Neutron, Google datacenter case study |
| 业务示例 | `sample/` | SDN controller application scenarios, SCP |

Each section directory contains its own `README.md` as the section landing page, plus topic files and an `images/` subdirectory for figures. The `container/` directory exists but its `SUMMARY.md` entries are commented out — those pages are scaffolded but not yet published.

There is also a commented-out `## 容器网络` block in `SUMMARY.md` showing the planned container networking content (CNI, CNM, Kubernetes networking, etc.).

## Key Files

- `SUMMARY.md` — table of contents; controls navigation. Editing it changes the sidebar.
- `book.json` — GitBook configuration (plugins: `anchors`, `ga`, `github-buttons`).
- `README.md` — front matter / preface.
- `FAQ.md` — troubleshooting tips (packet loss, traffic monitoring on Linux).
- `reference.md` — bibliography and external links.
- `CHANGELOG.md` — auto-generated commit history (not maintained by hand).

## Conventions

### Commit messages

This repo uses a strict conventional-commits-with-gitmoji format enforced by the historical log. Every commit follows:

```
:gitmoji: <type>(1.0): <Chinese description>
```

Observed types: `docs`, `feat`, `fix`, `refactor`, `style`, `chore`. Examples from the log: `:memo: docs(1.0): 添加Radius认证协议部分`, `:bug:fix(1.0): 修复缩写的错误`, `:wrench: chore(1.0): 添加travis ci的配置`.

### File organization

- Images live in a sibling `images/` directory inside each topic directory (e.g. `sdn/sbi/images/`).
- One `README.md` per directory as the section landing page; GitBook resolves both `README.md` and `index.md` to the section root.
- Branch: all work targets `master`; CI only deploys that branch.

### Authoring

- Content is Chinese. Match the surrounding tone when editing prose.
- Diagrams: many `.jpg`/`.png` images were originally created with OmniGraffle and PlantUML (see `sdn/sbi/*.puml` files — these are the sources for PlantUML diagrams and should be regenerated when modifying the rendered images).