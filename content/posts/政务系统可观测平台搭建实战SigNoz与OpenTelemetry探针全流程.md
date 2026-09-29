---
title: 政务系统可观测平台搭建实战：SigNoz + OpenTelemetry 探针，从零到 9 个应用上线
date: 2026-09-28T20:30:00+08:00
categories:
    - 个人分享/技术分享
tags:
    - SigNoz
    - OpenTelemetry
    - 可观测性
    - JMX
    - 应用监控
    - 链路追踪
    - 服务器运维
    - Windows
    - Linux
excerpt: 一次完整的政务系统监控接入实战记录。从搞懂"可观测性、SigNoz、探针"这三个词开始，到给 Linux/Windows 服务器装探针、接数据库和中间件、给 Tomcat 和 Spring Boot 应用挂 JMX 和链路 agent，最后 5 台服务器 9 个应用全部上线。文中所有命令都逐条解释了"这条命令是干什么的"，并完整记录了踩过的每一个坑。
---

## 写在前面

这篇文章记录的是一次真实的工作经历，从头到尾半个月的活儿。

事情的起因很简单：**公司要求我们安装signoz，以及探针，但是我从来没了解过，上网了解了一下，原来是进行监控的，主要监控内容是服务器以及应用程序、数据库。**
大概应用场景就是

- 服务器 CPU 飙到 100%，没人知道，直到"系统卡了"
- 数据库连接池满了，没人知道，直到用户投诉"提交不了"
- 某个 Java 应用内存泄漏，没人知道，直到某天它自己 OOM 挂掉
- 用户反馈"这个页面很慢"，我们只能说"我看看"，然后登录服务器 `tail -f` 看日志，两眼一抹黑

由于我不是一名专业的服务器运维，所有这种状态之前也有过发生。所以当公司说要上一套监控平台时，我是很积极的。

**但是过程比我想象的曲折得多。** 中间踩了一堆坑，有一次还因为误杀进程把生产环境的 ZooKeeper 搞挂了，导致一整台服务器上所有业务系统起不来——那半小时我手心全是汗。

所以我把整个过程完整写下来，包括踩的坑。**如果你也要做类似的事，希望你能少走点弯路。**

这篇文章会非常长，因为我想把它写成一份"照着做就能成"的手册。我会： 

1. **先讲清楚概念**——可观测性是什么、SigNoz 是什么、探针是什么，这些词你在任何文档里都能看到，但很少有人用大白话解释
2. **再讲清楚架构**——数据从服务器到平台，中间经过哪些环节
3. **然后才是动手**——每一步做什么、执行什么命令、**这条命令是干什么的**
4. **最后是踩坑记录**——那些文档里不会写、但实际一定会遇到的问题

---

## 第一章 先搞懂三个词：可观测性、SigNoz、探针

我刚开始接触这个项目时，拿到手的文档里全是术语，看得云里雾里。所以我先花一章把这些词讲清楚。

### 1.1 什么是"可观测性"

**监控**和**可观测性**是两回事，但很多人混着说。

**监控（Monitoring）** 是"我提前知道要看什么，所以我盯着它"。比如我知道要关注 CPU，就装个工具看 CPU，超过 80% 就报警。这是**已知问题**的防范。

**可观测性（Observability）** 是"我不知道会出什么问题，但我能从系统输出的数据里**推断**出来"。这是**未知问题**的排查。

举个具体的例子你就明白了：

> 业务说："用户提交表单很慢。"
>
> **只有监控的情况**：你看 CPU 正常、内存正常、磁盘正常、网络正常——然后你就卡住了，因为你要看的指标你都看了，都是正常的，但问题确实存在。
>
> **有可观测性的情况**：你打开链路追踪，搜索"提交表单"这个请求，看到一棵调用树：
> ```
> POST /approve/submit          3200ms   ← 整个请求 3.2 秒
>   ├─ 权限校验                   15ms
>   ├─ 查询事项配置                8ms
>   ├─ 保存表单数据               42ms
>   ├─ 调用工作流引擎           3100ms   ← 问题在这里！
>   │    └─ 写数据库             3050ms   ← 真正的原因：数据库慢
>   └─ 返回响应                    5ms
> ```
> 你立刻就知道：**问题在调用工作流引擎时写数据库慢**。不用猜，不用登录服务器翻日志。

这就是可观测性的价值。它由三根支柱组成：

| 支柱 | 英文 | 回答什么问题 | 数据特点 |
|---|---|---|---|
| **指标** | Metrics | "系统现在什么状态？" | 数值型、定时采集、**量小** |
| **链路** | Traces | "这一个请求去哪了、慢在哪？" | 请求驱动、**量大** |
| **日志** | Logs | "具体发生了什么？" | 文本、**量最大** |

**划重点**：这三者的**数据量差异巨大**。指标一天可能几百 MB，链路一天可能几十 GB，日志可能上百 GB。这也是为什么我们后面做链路时要配"采样率"——后面会细讲。

### 1.2 SigNoz 是什么

**SigNoz 是一个开源的可观测性平台。** 你可以把它理解成"自己部署的、免费的 Datadog"或者"国产的阿里云 ARMS"。

它把这些数据统一收集、存储、展示： 

https://signoz.io/

```
┌─────────────────────────────────────────────────────┐
│                    SigNoz 平台                       │
│                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │  指标页  │  │  服务页  │  │  链路页  │          │
│  └──────────┘  └──────────┘  └──────────┘          │
│         ▲             ▲             ▲              │
│         └─────────────┴─────────────┘              │
│                       │                            │
│              ┌────────▼────────┐                   │
│              │   ClickHouse    │  ← 存数据的地方    │
│              │   （数据库）     │                   │
│              └─────────────────┘                   │
└─────────────────────────────────────────────────────┘
                       ▲
                       │  探针把数据发上来
                       │
              ┌────────┴────────┐
              │   各地服务器     │
              └─────────────────┘
```

**我们这套环境的具体情况：**

| 项目 | 值 |
|---|---|
| SigNoz 版本 | v0.126.1（社区版） |
| 访问地址 | `http://IP:8086` |
| 底层数据库 | ClickHouse 25.5.6 |
| 数据盘 | 2TB，挂载在 `/home/docker` |
| 部署方式 | Docker（Docker 26.1.2） |

**为什么选 SigNoz 而不是 Zabbix/Prometheus+Grafana？**

- Zabbix：擅长主机和网络设备监控，但**应用层和链路追踪很弱**
- Prometheus + Grafana：指标很强，但**链路追踪要另配 Jaeger，日志要另配 Loki**，三套系统拼起来维护成本高
- SigNoz：**指标 + 链路 + 日志一套搞定**，用的是 OpenTelemetry 标准协议

对我们这种"什么都想监控一点"的需求来说，SigNoz 是最省事的。

### 1.3 探针是什么

**探针 = 部署在每台被监控服务器上的一个采集程序。**

它的职责是：

1. **采集**：从本机采集各种数据（CPU、内存、磁盘、数据库状态、应用指标……）
2. **加工**：给数据打上标签（这是哪台机器、哪个应用、什么环境）
3. **上报**：通过标准协议发送给 SigNoz 平台

打个比方：

> **SigNoz 是医院，探针是派驻到各个社区的健康检查员。**
>
> 检查员每天到社区（服务器）里，量血压、测血糖（采集数据）、在体检表上写上"张三、男、45岁"（打标签），然后把表送回医院（上报）。医院汇总所有体检表，出报告（展示）。

**我们用的探针叫 `otelcol-contrib`**，全称是 OpenTelemetry Collector Contrib。它是 CNCF（云原生计算基金会）的官方项目，也是目前业界事实上的标准。

为什么用它：
- **一个程序什么都能采**：主机、MySQL、Redis、Oracle、Memcached、JMX、日志文件、HTTP 探活……不用装一堆 Agent
- **开源、免费、跨平台**：Linux、Windows 都有
- **标准化**：数据格式是 OpenTelemetry 标准，以后想换平台（比如换成 Elastic）不用重做采集

**`contrib` 是什么意思？** 是 "contributions" 的缩写。OpenTelemetry Collector 有两个版本：
- `otelcol`（核心版）：只有最基础的采集器
- `otelcol-contrib`（扩展版）：包含社区贡献的所有采集器，**功能全得多**

我们要采 Oracle、Redis、JMX，必须用 `contrib` 版。

### 1.4 四层监控：我们要监控什么

在动手之前，先想清楚"监控什么"。我们把监控对象分成四层：

```
第一层：主机       —— 这台服务器本身还好吗？
   ↓
第二层：中间件/数据库 —— Redis、MySQL、Oracle、Memcached 还好吗？
   ↓
第三层：应用       —— 我的 Java 应用还好吗？（内存、GC、线程）
   ↓
第四层：链路       —— 用户的一次操作，在各个系统间是怎么流转的？
```

**这四层的重要性是递增的，但实现难度和数据量也是递增的。**

| 层 | 价值 | 实现难度 | 数据量 | 我们的进度 |
|---|---|---|---|---|
| ① 主机 | 中 | 低 | 小 | ✅ 全部完成 |
| ② 中间件/数据库 | 中 | 中 | 小 | ✅ 已完成 |
| ③ 应用（JMX） | **高** | 中 | 小 | ✅ 已完成 |
| ④ 链路 | **最高** | 中 | **大** | ✅ 已完成（采样 10%） |

**注意第四层的"数据量大"**。这是整个项目里最需要小心的地方——链路数据量和**用户请求量成正比**。如果系统每天有 100 万次请求，每个请求产生 1 条链路、每条链路 10 个片段，那就是每天 1000 万条记录。如果不做采样，平台很快就被打爆。

这也是为什么我在项目一开始就考虑到"**先弄应用吧，怕弄上链路并且不限制服务器被打爆**"——后面会讲怎么用采样率解决这个问题。

### 1.5 一张图看懂整个架构

把前面讲的串起来，我们的架构长这样：

```
                    ┌──────────────────────────────────┐
                    │      SigNoz 平台                  │
                    │        IP:8086             │
                    │                                  │
                    │  ┌────────────┐                  │
                    │  │ ClickHouse │ ← 存所有数据     │
                    │  └────────────┘                  │
                    └───────▲──────────▲───────────────┘
                            │          │
              4317端口      │          │      4318端口
           （指标，gRPC）    │          │   （链路，HTTP）
                            │          │
        ┌───────────────────┘          └──────────────────┐
        │                                                  │
┌───────┴────────┐                            ┌────────────┴─────────┐
│  探针 otelcol   │                            │  应用（链路 agent）    │
│                │                            │                     │
│  ├ 主机指标     │                            │  opentelemetry-     │
│  ├ 数据库指标   │                            │  javaagent.jar      │
│  ├ 中间件指标   │                            │                     │
│  └ 应用 JMX指标 │                            │  直接发到 4318       │
└───────▲────────┘                            └──────────▲──────────┘
        │                                                │
        │ 每 60 秒抓一次                                  │ 有请求就产生
        │                                                │
┌───────┴────────────────────────────────────────────────┴──────────┐
│                         被监控的服务器                              │
│                                                                    │
│   主机 ── Redis ── MySQL ── Oracle ── Java应用(JMX端口)             │
└────────────────────────────────────────────────────────────────────┘
```

**这里有一个非常关键的设计点，一定要记住：**

> **指标走探针，链路不走探针。**
>
> - **指标**：探针定时去"抓"（比如每 60 秒抓一次），然后由探针统一上报到 4317
> - **链路**：应用里的 agent **直接**把数据发到平台的 4318，**不经过探针**

为什么这么设计？因为链路数据量太大，如果先发给探针再转发，探针自己就成了瓶颈。让应用直接发，省一道中转。

**理解这一点非常重要**，后面配置链路时你会发现：链路的上报地址是写在**应用启动参数**里的，而不是写在探针配置里的。

---

## 第二章 动手之前：把环境和规划搞清楚

**同步部署的时候，我们有一些同事上来就`tar -zxvf` 或者`unzip`，然后`./install.sh`，结果装到一半发现网络不通、端口被占、版本不对。** 
所以这一章是"规划章"，看起来没干货，但能省你一天时间。

### 2.1 网络分区：A 区还是 B 区（这里最容易翻车）

我们的环境有**两个网络区域**，它们**互相不通**：

| 区域 | 内网网段 | 平台地址 | 说明 |
|---|---|---|---|
| **A 区** | `政务网.x`、`政务网.x` | `政务网.x` | 平台自己所在区域 |
| **B 区** | `192.168.140.x` | `192.168.140.*` | 通过一台转发机接入 |

**平台的 4317 端口在两台机器上都开放了**：
- A 区机器 → 连 `政务网:4317`
- B 区机器 → 连 `内网:4317`

**怎么判断一台服务器该用哪个地址？**

不要看它的"政务网 IP"，要看它**实际能连通哪个**。判断方法（后面会详细讲）：

```powershell
Test-NetConnection -ComputerName 政务网 -Port 4318
Test-NetConnection -ComputerName 内网 -Port 4318
```

**⚠️ 这是我们踩的最大的坑之一。**

我们有一台服务器 `112`，从 IP 看是 `*.*.*.112`（像是 A 区），但它的实际出口是 `192.168.140.2`（B 区）。**我一开始按 IP 判断，配了 `*.*.*.238:4318`，结果链路数据一条都上不去。**

后面测了才发现，**`*.*.*.112` 这一整段全都是走 B 区的**。所以：

> **判断标准：看测试命令输出的 `SourceAddress` 是什么。**
>
> - `SourceAddress` 是 `192.168.140.x` → 走 B 区 → 用 `192.168.140.60`
> - `SourceAddress` 是 `*.*.*.238` → 走 A 区 → 用 `*.*.*.238`

**这条经验值一千块。**

### 2.2 采集器版本：为什么我用 0.88.0 而不是最新的 0.150.1

公司文档里写的采集器版本是 **v0.150.1**（一个比较新的版本），但我最后用的是 **v0.88.0**（一个老版本）。

**为什么降级？因为公司文档不兼容我的主机版本：**

公司手册里写着：


> Windows Server x64 | **Windows Server 2016 / 2019 / 2022（64 位）** | otelcol-contrib_0.150.1_windows_amd64.tar.gz

而我们项目上这 **\* 台 Windows 服务器全是 Windows Server 2012 R2**——**按公司文档，根本不在支持范围内。**

我在 2012 R2 上试装 0.150.1，跑不起来（缺依赖 / 不兼容）。换成 0.88.0 就能跑。

使用 0.88.0 版本时，不支持 `tcpcheck` 采集器，配置会报错：


$ otelcol-contrib.exe validate --config=后台生成.yaml
Error: failed to get config: cannot unmarshal the configuration: 1 error(s) decoding:
 error decoding 'receivers': unknown type: "tcpcheck" for id: "tcpcheck/oracle"
exit code = 1


**降级的代价（必须知道）：**

| 能力 | 0.150.1 | 0.88.0 | 影响 |
|---|---|---|---|
| `tcpcheck`（TCP 端口探活） | ✅ 有 | ❌ **没有** | 不能用它探测"某个端口通不通" |
| `hostmetrics`（主机指标） | ✅ | ✅ | 无影响 |
| `mysql` / `redis` / `oracledb` | ✅ | ✅ | 无影响 |
| `prometheus`（抓 JMX） | ✅ | ✅ | 无影响 |
| `httpcheck`（HTTP 探活） | ✅ | ✅ | 无影响 |
| `filelog`（日志采集） | ✅ | ✅ | 无影响 |

**结论：只损失了 `tcpcheck` 一个能力，其他都有。** 这是可以接受的。


### 2.3 端口规划：别让小端口毁了大事情

这次涉及 5 类端口，必须先规划好：

| 端口 | 用途 | 说明 |
|---|---|---|
| **4317** | OTLP gRPC | 探针上报**指标**用 |
| **4318** | OTLP HTTP | 应用上报**链路**用 |
| **18888** | 探针自身监控 | 查看探针自己的运行状态（接收/发送了多少数据） |
| **9999 起** | JMX 指标端口 | 每个 Java 应用一个，**同机多应用必须错开** |
| **8086** | SigNoz Web 界面 | 你平时打开看的那个页面 |

**JMX 端口分配规则（重要）：**

```
一台机器上第 N 个应用 → 用 10000 - N 端口
  第 1 个应用 → 9999
  第 2 个应用 → 9998
  第 3 个应用 → 9997
  第 4 个应用 → 9996
```
如果是多台服务器，就每台服务器上都用9999就行了

**⚠️ 但一定要先检查端口是否被占用！** 我们有台机器 `*.*.*.127`，上面跑了一个 Jetty，**Jetty 自己就占用了 9999**，所以那台机器的 QYSL 应用只能用 9998。

检查方法后面会讲。

---

## 第三章 第一步：给 Linux 服务器装探针

我们有三台 Linux 服务器（`*.*.*.241`、`*.*.*.237`、`*.*.*.131`），Windows 有十台。

这一章先讲 Linux，因为 **Linux 是标准做法，Windows 是特殊情况**。

### 3.1 把安装包传上去

**要传的文件：**

| 文件 | 大小 | 干什么用的 |
|---|---|---|
| `otelcol-contrib_0.88.0_linux_amd64.tar.gz` | 约 60MB | 探针主程序 |

**传文件的命令：**

```bash
scp -P 37210 otelcol-contrib_0.88.0_linux_amd64.tar.gz root@*.*.*.241:/tmp/
```

**这条命令拆开看：**

| 部分 | 含义 |
|---|---|
| `scp` | secure copy，基于 SSH 的加密文件传输 |
| `-P 37210` | **大写的 P**，指定 SSH 端口。注意：`scp` 用大写 `-P`，而 `ssh` 用小写 `-p`，这两个很容易搞混 |
| `otelcol-...tar.gz` | 本地要传的文件 |
| `root@*.*.*.241:/tmp/` | 目标：以 root 身份传到那台机器的 `/tmp/` 目录 |

**为什么先传到 `/tmp`？** 因为 `/tmp` 是临时目录，权限宽松，先放这儿再解压到正式位置，是个好习惯（万一版本不对，直接删掉 `/tmp` 里的就行，不会污染系统）。

### 3.2 解压到正式目录

```bash
mkdir -p /opt/otelcol
tar -zxvf /tmp/otelcol-contrib_0.88.0_linux_amd64.tar.gz -C /opt/otelcol
ls -la /opt/otelcol/
```

**逐条解释：**

**第一条 `mkdir -p /opt/otelcol`**
- `mkdir` = make directory，创建目录
- `-p` = parents，如果父目录不存在就一起创建；如果目录已存在**不报错**
- **为什么加 `-p`？** 不加的话，如果 `/opt/otelcol` 已存在，命令会报错 `File exists`，脚本就中断了。加了 `-p` 就安全了，**写脚本时这是个好习惯**

**第二条 `tar -zxvf ... -C /opt/otelcol`**

`tar` 是 Linux 最常用的打包/解包工具，四个参数各有含义：

| 参数 | 含义 | 记忆方法 |
|---|---|---|
| `z` | 用 gzip 解压 | 因为文件是 `.gz` 结尾 |
| `x` | extract，解压（而不是打包） | **x = 提取** |
| `v` | verbose，显示过程 | 会打印出每个文件名 |
| `f` | file，指定文件 | **f 必须放最后，紧跟文件名** |
| `-C` | 切换到指定目录再解压 | Change directory |

**⚠️ `-C` 这个参数非常有用。** 不加 `-C` 的话，tar 会解压到**当前目录**，如果当前目录是 `/root`，你就把一堆文件解压到 root 家目录里了，很乱。

**第三条 `ls -la /opt/otelcol/`**
- `ls` = list，列出文件
- `-l` = long，长格式（显示权限、大小、时间）
- `-a` = all，显示所有文件（包括以 `.` 开头的隐藏文件）
- **为什么加 `-a`？** 有些解压出来的文件是隐藏的（比如 `.env`），不加 `-a` 看不到

**期望输出**，你应该看到：

```
-rwxr-xr-x 1 root root 123456789 Sep 28 10:00 otelcol-contrib
```

**`-rwxr-xr-x` 这串东西是什么意思？**

```
-  rwx  r-x  r-x
│   │    │    │
│   │    │    └── 其他人：可读、可执行
│   │    └─────── 同组用户：可读、可执行
│   └──────────── 文件所有者：可读、可写、可执行
└──────────────── 文件类型：- 表示普通文件，d 表示目录
```

**看到 `x`（可执行）很重要**——如果解压出来的程序没有 `x` 权限，你运行时会报 `Permission denied`。补权限的方法：

```bash
chmod +x /opt/otelcol/otelcol-contrib
```

### 3.3 先别急着启动：用"本地测试配置"验证

**这是我最想强调的一步。**

很多人的做法是：解压 → 直接启动 → 报错 → 看日志 → 改配置 → 再启动 → 再报错……来回折腾。

**正确的做法是：先用一个最简配置验证程序本身能不能跑，再逐步加上正式配置。**

**第一步：让程序告诉你它支持哪些采集器**

```bash
/opt/otelcol/otelcol-contrib --help
```

这会打印所有支持的子命令和参数。你能看到 `validate`、`start` 等。

**第二步：查看这个版本支持的所有组件（很关键）**

```bash
/opt/otelcol/otelcol-contrib components
```

**这条命令的价值巨大**：它会列出这个版本**实际支持**的所有采集器（receivers）、处理器（processors）、导出器（exporters）。

**为什么重要？** 因为我们就是靠它发现 **0.88.0 里没有 `tcpcheck`** 这个采集器的。公司的配置生成器会生成 `tcpcheck` 配置，但那个版本根本没有，**启动时直接报错**：

```
Error: failed to get config: cannot unmarshal the configuration: 1 error(s) decoding:
* error decoding 'receivers': unknown type: "tcpcheck" for id: "tcpcheck/oracle"
```

**这个报错我翻译一下**：
- `failed to get config` = 读取配置失败
- `unknown type: "tcpcheck"` = 不认识 `tcpcheck` 这个类型
- **解决办法：要么升级版本，要么去掉这段配置**

**第三步：写一个"最小可用"的测试配置**

新建文件 `/tmp/test-config.yaml`：

```yaml
receivers:
  hostmetrics:
    collection_interval: 60s
    scrapers:
      cpu: {}
      memory: {}

exporters:
  logging:
    verbosity: detailed

service:
  pipelines:
    metrics:
      receivers: [hostmetrics]
      exporters: [logging]
```

**这个配置在干什么？**

| 段落 | 含义 |
|---|---|
| `receivers` | 采集器：采主机指标，只采 CPU 和内存，每 60 秒一次 |
| `exporters` | 导出器：**`logging` 表示把数据打印到屏幕上，不发到任何地方** |
| `service.pipelines` | 管道：把 receivers 采到的数据，交给 exporters 处理 |

**为什么用 `logging` 导出器？** 因为这样数据只在本地打印，**不依赖网络**。如果这一步能跑通，说明程序本身没问题；如果跑不通，那肯定是程序或配置的问题，跟网络无关。

**这就是"隔离变量"的排查思路**——一次只验证一个东西。

**第四步：验证配置语法**

```bash
/opt/otelcol/otelcol-contrib validate --config=/tmp/test-config.yaml
```

- `validate` = 校验，只检查配置对不对，**不启动程序**
- **输出为空 = 校验通过**（这是 OpenTelemetry Collector 的特点，成功了什么都不说）
- 有输出 = 有错误

**这个习惯一定要养成**：改完配置先 `validate`，再重启。**能省掉 80% 的"重启后服务挂了"的事故。**

**第五步：真跑一下看看**

```bash
/opt/otelcol/otelcol-contrib --config=/tmp/test-config.yaml
```

你会看到屏幕上哗哗地打印出指标数据，类似：

```
ResourceMetrics #0
Resource SchemaURL:
Resource attributes:
     -> host.name: Str(nc-ucb-1-05)
     -> os.type: Str(linux)
ScopeMetrics #0
Metric #0
Descriptor:
     -> Name: system.cpu.utilization
     -> Unit: 1
     -> DataType: Gauge
NumberDataPoints #0
Data point attributes:
     -> cpu: Str(0)
     -> state: Str(user)
Value: 0.0234
```

**看到这个就说明探针工作正常了！** 按 `Ctrl+C` 退出。

**这一步的意义**：你现在**已经证明**了——程序能跑、配置语法对、采集功能正常。**接下来如果出问题，就只可能是网络或正式配置的问题了。** 排查范围一下子缩小了。

### 3.4 生成正式配置

正式配置用一个 Python 脚本生成（脚本是我们自己写的，下一章讲）。生成的配置长这样（简化版）：

```yaml
receivers:
  hostmetrics:
    collection_interval: 60s
    scrapers:
      cpu:
        metrics:
          system.cpu.utilization:
            enabled: true
      disk: {}
      filesystem:
        metrics:
          system.filesystem.utilization:
            enabled: true
      memory:
        metrics:
          system.memory.utilization:
            enabled: true
      network: {}
      paging: {}
      processes: {}

  redis:
    collection_interval: 60s
    endpoint: "127.0.0.1:6379"

processors:
  resourcedetection:
    detectors: [env, system]
    override: false

  resource/host_inject:
    attributes:
      - key: host.ip
        value: "*.*.*.241"
        action: upsert
      - key: host.name
        value: "nc-ucb-1-05-241"
        action: upsert
      - key: os.type
        value: "linux"
        action: upsert
      - key: deployment.environment
        value: "production"
        action: upsert

  resource/host:
    attributes:
      - key: service.name
        value: "nc-ucb-1-05"
        action: upsert
      - key: service.instance.id
        value: "*.*.*.241"
        action: upsert
      - key: service.type
        value: "host"
        action: upsert
      - key: service.subtype
        value: "server"
        action: upsert

  attributes/redis:
    actions:
      - key: service.name
        value: "Redis缓存"
        action: upsert
      - key: service.instance.id
        value: "*.*.*.*:6379"
        action: upsert
      - key: service.type
        value: "middleware"
        action: upsert
      - key: service.subtype
        value: "redis"
        action: upsert

  batch:
    timeout: 10s
    send_batch_size: 1024

exporters:
  otlp:
    endpoint: "*.*.*.238:4317"
    tls:
      insecure: true

service:
  telemetry:
    logs:
      level: info
    metrics:
      address: "0.0.0.0:18888"
      level: detailed
  pipelines:
    metrics/host:
      receivers: [hostmetrics]
      processors: [resourcedetection, resource/host_inject, resource/host, batch]
      exporters: [otlp]
    metrics/redis:
      receivers: [redis]
      processors: [resourcedetection, resource/host_inject, attributes/redis, batch]
      exporters: [otlp]
```

**这个配置里的每一段都在干什么？我逐个讲。**

#### receivers（采集器）

```yaml
hostmetrics:
  collection_interval: 60s        # 每 60 秒采一次
  scrapers:                        # scrapers = 采集器下面的子采集器
    cpu: {}
    disk: {}
    filesystem: {}
    memory: {}
    network: {}
    paging: {}
    processes: {}
```

**为什么要分开写 `scrapers`？** 因为 `hostmetrics` 是个"大礼包"，里面按类别分了子采集器。你可以只开你需要的，减少数据量。

| scraper | 采什么 | 我们是否启用 |
|---|---|---|
| `cpu` | CPU 使用率 | ✅ |
| `memory` | 内存 | ✅ |
| `disk` | 磁盘 IO | ✅ |
| `filesystem` | 磁盘空间使用率 | ✅ |
| `network` | 网络流量 | ✅ |
| `paging` | 交换分区（虚拟内存） | ✅ |
| `processes` | 进程数 | ✅ |
| `load` | 系统负载 | ⚠️ **只在 Linux 开** |

**`load` 为什么只在 Linux 开？** 因为 **Windows 没有 load average 这个概念**。如果在 Windows 上启用 `load` scraper，探针启动时会报错：

```
Error: scraper "load" is not supported on this platform
```

**这就是"配置要分平台"的原因**——同一份配置模板，Linux 和 Windows 会有些差异。

**关于 `metrics` 下面的 `system.cpu.utilization.enabled: true`：**

这是**手动开启某个具体指标**。默认情况下，`hostmetrics` 只采集"原始值"（比如 CPU 累计用了多少纳秒），不采集"利用率"（百分比）。要利用率就得显式打开。

```yaml
cpu:
  metrics:
    system.cpu.utilization:
      enabled: true      # 打开利用率指标
```

**为什么要这个？** 因为**看百分比比看累计值直观**。`system.cpu.utilization = 0.85` 一眼就知道是 85%，而 `system.cpu.time = 12345678` 你得算半天。

#### processors（处理器）

处理器是**数据的加工车间**。数据从采集器出来、到导出器之前，会依次经过处理器。

**① `resourcedetection`（资源探测）**

```yaml
resourcedetection:
  detectors: [env, system]
  override: false
```

- `detectors: [env, system]` = 用两种探测器：从环境变量读、从系统信息读
- `override: false` = **不覆盖已有的属性**

**这里有个大坑，必须讲：**

我们原本指望它能自动识别主机名、操作系统、架构。**实测发现 0.88.0 的 `system` 探测器在 Windows 上什么都不加！**

结果是：SigNoz 的「基础设施 → 主机」页面左侧的"操作系统"筛选栏**永远是空值**，因为 `os.type` 这个属性根本不存在。

**解决办法：不要指望自动探测，全部手动注入。** 这就是下面 `resource/host_inject` 存在的原因。

**② `resource/host_inject`（主机标识注入）**

```yaml
resource/host_inject:
  attributes:
    - key: host.ip
      value: "*.*.*.241"
      action: upsert
    - key: host.name
      value: "nc-ucb-1-05-241"
      action: upsert
    - key: os.type
      value: "linux"              # ← 手动注入，因为自动探测不可靠
      action: upsert
    - key: deployment.environment
      value: "production"
      action: upsert
```

**`action: upsert` 是什么意思？**

`upsert` = **up**date + in**sert**，如果属性已存在就覆盖，不存在就新建。这是最常用的 action。

其他可选的 action：
- `insert`：只在不存在时添加（已存在则跳过）
- `update`：只在已存在时覆盖（不存在则跳过）
- `delete`：删除
- `hash`：把值哈希化（用于脱敏）

**`host.name` 的命名规范（我们自己定的）：**

```
格式：<主机名>-<IP 最后一段>
例子：nc-ucb-1-05-241
      WIN-BLK3HH5RG2Q-100
```

**为什么要加 IP 后缀？** 因为**不同环境的主机名可能重复**。我们做测试时有台机器的默认主机名是 `WIN-BLK3HH5RG2Q`，如果生产环境还有一台同名机器，在平台上就分不清了。加上 IP 后缀就唯一了。

**③ `resource/host`（主机服务标签）**

```yaml
resource/host:
  attributes:
    - key: service.name
      value: "nc-ucb-1-05"        # 服务名
      action: upsert
    - key: service.instance.id
      value: "*.*.*.241"      # 实例 ID = IP
      action: upsert
    - key: service.type
      value: "host"                # 类型：主机
      action: upsert
    - key: service.subtype
      value: "server"              # 子类型：服务器
      action: upsert
```

**这四个标签是我们自己定义的一套"分类体系"，全平台统一：**

| 属性 | 作用 | 取值范围 |
|---|---|---|
| `service.name` | **这个监控对象叫什么**（SigNoz 里按它分组） | 主机名 / 应用编码 |
| `service.instance.id` | **这个实例是哪一个**（同名的不同实例靠它区分） | `IP:端口` |
| `service.type` | **它是哪一类** | `host` / `middleware` / `database` / `application` |
| `service.subtype` | **更细的分类** | `server` / `redis` / `mysql` / `jvm` … |

**为什么要这么细？** 因为后面在 SigNoz 里，我们要靠这些标签做筛选和分组：

- 想看**所有主机** → 过滤 `service.type = 'host'`
- 想看**所有数据库** → 过滤 `service.type = 'database'`
- 想看**某个 Redis** → 过滤 `service.name = 'Redis缓存'`

**没有这套标签体系，平台上的数据就是一堆没有分类的数字，没法用。**

**④ `attributes/xxx`（具体服务的标签）**

```yaml
attributes/redis:
  actions:
    - key: service.name
      value: "Redis缓存"
      action: upsert
    - key: service.instance.id
      value: "*.*.*.241:6379"
      action: upsert
    - key: service.type
      value: "middleware"
      action: upsert
    - key: service.subtype
      value: "redis"
      action: upsert
```

**为什么每个服务一个处理器，而不是一个处理器搞定所有？**

因为**每类服务的标签值不一样**（Redis 的 service.type 是 `middleware`，MySQL 是 `database`），而且**管道是分开的**（每个服务一条管道），所以每个服务得有自己的处理器。

**命名习惯**：`attributes/` 后面跟服务名，比如 `attributes/redis`、`attributes/mysql`。这样在 `service.pipelines` 里引用时一目了然。

**⑤ `batch`（批处理）**

```yaml
batch:
  timeout: 10s
  send_batch_size: 1024
```

- `timeout: 10s` = 最多攒 10 秒就发一次
- `send_batch_size: 1024` = 攒够 1024 条就发一次

**为什么要批处理？** 因为**网络请求是有开销的**。如果不批处理，每条数据发一次请求，那就是每秒成千上万次网络往返，效率极低。攒一批发一次，效率高几十倍。

**这两个参数是"或"的关系**：谁先满足就发（攒够 1024 条 或者 过了 10 秒）。

#### exporters（导出器）

```yaml
exporters:
  otlp:
    endpoint: "*.*.*.*:4317"
    tls:
      insecure: true
```

- `otlp` = OpenTelemetry Protocol，标准上报协议
- `endpoint` = 平台地址（A 区机器填 `*.*.*.238:4317`，B 区填 `192.168.140.60:4317`）
- `tls.insecure: true` = **不加密**

**⚠️ `insecure: true` 必须写！** 因为我们的平台在内网，没有配 HTTPS 证书。如果不写这一行，探针会尝试用 TLS 连接，然后报错：

```
rpc error: code = Unavailable desc = connection error:
desc = "transport: authentication handshake failed: tls: first record does not look like a TLS handshake"
```

**这个报错的翻译**：我用 TLS 握手，但对方回的数据不像 TLS。**意思就是对方没开 TLS，你别用。** 加上 `insecure: true` 就好了。

#### service（服务定义）

```yaml
service:
  telemetry:
    logs:
      level: info          # 探针自己的日志级别
    metrics:
      address: "0.0.0.0:18888"    # ← 探针自身的监控端口
      level: detailed
  pipelines:
    metrics/host:
      receivers: [hostmetrics]
      processors: [resourcedetection, resource/host_inject, resource/host, batch]
      exporters: [otlp]
    metrics/redis:
      receivers: [redis]
      processors: [resourcedetection, resource/host_inject, attributes/redis, batch]
      exporters: [otlp]
```

**`telemetry.metrics.address: "0.0.0.0:18888"` 是什么？**

这是**探针自己的运行状态接口**。打开它之后，你可以访问 `http://127.0.0.1:18888/metrics` 看到：

- 探针从各个采集器收了多少条数据
- 往平台成功发送了多少条
- 发送失败了多少条
- 队列里积压了多少

**这个接口是排查问题的神器。** 后面我会反复用：

```bash
curl -s http://127.0.0.1:18888/metrics | grep otelcol_exporter_sent
```

**`pipelines` 的写法说明：**

```
metrics/host:
   ↑      ↑
   │      └── 管道名字（自己起，要唯一）
   └───────── 数据类型：metrics（指标）/ traces（链路）/ logs（日志）
```

**为什么每条管道要分开？** 因为**不同的数据要打不同的标签**。主机数据打"主机标签"，Redis 数据打"Redis标签"。如果混在一条管道里，就分不开了。

**管道的方向永远是**：`receivers → processors → exporters`

**注意 processors 的顺序是有讲究的：**

```
resourcedetection, resource/host_inject, attributes/xxx, batch
```

1. `resourcedetection` 先跑（尝试自动探测）
2. `resource/host_inject` 覆盖/补充（保证属性一定存在）
3. `attributes/xxx` 打业务标签
4. `batch` 最后攒批

**如果顺序反了会怎样？** 比如 `batch` 放在最前面，数据先被攒起来，后面的处理器就处理不到已经发走的数据了。**顺序不能乱。**

### 3.5 装成 systemd 服务（开机自启 + 崩溃自动拉起）

前面都是手工跑，一关终端就没了。要让它常驻，得装成系统服务。

**创建服务文件：**

```bash
cat > /etc/systemd/system/otelcol-contrib.service << 'EOF'
[Unit]
Description=OpenTelemetry Collector Contrib
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/otelcol/otelcol-contrib --config=/opt/otelcol/config.yaml
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
```

**逐段解释：**

| 段落 | 内容 | 含义 |
|---|---|---|
| `[Unit]` | `Description=` | 服务描述（`systemctl status` 时显示） |
| | `After=network.target` | **等网络就绪后再启动**（重要！否则可能连不上平台） |
| `[Service]` | `Type=simple` | 简单类型（前台一直跑） |
| | `User=root` | 以 root 用户运行 |
| | `ExecStart=` | **启动命令** |
| | `Restart=always` | **挂了自动重启**（很重要） |
| | `RestartSec=10` | 挂了等 10 秒再重启 |
| | `StandardOutput=journal` | 输出到系统日志（`journalctl` 能看） |
| `[Install]` | `WantedBy=multi-user.target` | **开机自启**（多用户模式 = 正常启动模式） |

**`Restart=always` 为什么重要？** 因为探针是个长期运行的程序，万一因为网络抖动或内存问题挂了，**没有自动重启的话它就永远不工作了，而且没人知道**。加上这一行，挂了 10 秒后自动回来。

**关于 `cat > 文件 << 'EOF'` 这个写法：**

这是 Linux 里的"**heredoc**"（Here Document）语法，用来**把一大段内容写进文件**。

拆开看：
- `cat > 文件` = 把输入内容写入这个文件（`>` 是覆盖，`>>` 是追加）
- `<< 'EOF'` = 从这里开始，直到遇到单独一行的 `EOF` 为止，中间所有内容都是输入
- **`'EOF'` 加单引号很关键**：加了引号表示**内部内容不做变量替换**。如果不加引号，`$JAVA_HOME` 这样的字符串会被 shell 展开成实际值，可能出错

**这是一个非常实用的技巧**，比用 `vi` 编辑方便多了，特别是写脚本时。

**启用服务（三条命令缺一不可）：**

```bash
systemctl daemon-reload                        # ① 重新加载服务定义
systemctl enable otelcol-contrib               # ② 设置开机自启
systemctl start otelcol-contrib                # ③ 立即启动
```

**为什么要 `daemon-reload`？**

因为 systemd **不会自动发现**你新加的服务文件。它把所有服务定义缓存在内存里，你新建了 `.service` 文件后，必须**显式告诉它"重新读一遍"**。

**忘了这一步的典型症状**：

```
# systemctl start otelcol-contrib
Failed to start otelcol-contrib.service: Unit otelcol-contrib.service not found.
```

**明明文件就在那里，它说找不到——就是没 reload。**

**三条命令各自的作用：**

| 命令 | 作用 | 类比 |
|---|---|---|
| `daemon-reload` | 重新读取服务定义 | 把新员工登记到花名册 |
| `enable` | 开机自启 | 设置"每天自动上班" |
| `start` | 立即启动 | "现在就来上班" |

**注意 `enable` 和 `start` 是两件事**：
- 只 `start` 不 `enable`：现在跑，但**重启服务器后就不会自动起来**了
- 只 `enable` 不 `start`：下重启会起来，但**现在不跑**

**两个都要做。**

### 3.6 验证探针工作正常（三层验证法）

**验证要一层一层来，不要跳。** 跳着验证的话，出问题时你不知道是哪一层坏了。

**第一层：进程在不在**

```bash
systemctl status otelcol-contrib
```

**期望输出**（关键看这几个词）：

```
● otelcol-contrib.service - OpenTelemetry Collector Contrib
     Loaded: loaded (/etc/systemd/system/otelcol-contrib.service; enabled; ...)
     Active: active (running) since Sun 2026-09-28 10:00:00 CST; 5min ago
   Main PID: 12345 (otelcol-contrib)
```

| 关键词 | 含义 |
|---|---|
| `loaded ... enabled` | 服务已加载，**开机自启已开启** |
| **`active (running)`** | **正在运行**（这是你要看到的） |
| `Main PID: 12345` | 进程号 |

**如果看到 `failed` 或 `inactive (dead)`**，说明启动失败，看第二层。

**第二层：看日志有没有报错**

```bash
journalctl -u otelcol-contrib -n 50 --no-pager
```

**这条命令拆开看：**

| 部分 | 含义 |
|---|---|
| `journalctl` | 查看 systemd 日志的工具 |
| `-u otelcol-contrib` | `-u` = unit，只看这个服务的日志 |
| `-n 50` | 最后 50 行 |
| `--no-pager` | **不要用分页器**（否则会卡在 `less` 里，要按 `q` 退出，脚本里必须加） |

**常用变体：**

```bash
journalctl -u otelcol-contrib -f                    # 实时跟踪（像 tail -f）
journalctl -u otelcol-contrib --since "10 minutes ago"  # 最近10分钟
journalctl -u otelcol-contrib -p err                # 只看错误级别
```

**第三层（最重要）：看探针自己的统计接口**

```bash
curl -s http://127.0.0.1:18888/metrics | grep '^otelcol_receiver_accepted_metric_points'
```

**这条命令拆开看：**

| 部分 | 含义 |
|---|---|
| `curl` | 命令行 HTTP 客户端 |
| `-s` | silent，**不显示进度条**（脚本里必须加，否则输出里混着进度信息） |
| `http://127.0.0.1:18888/metrics` | 探针的自身监控接口 |
| `\|` | 管道，把输出交给下一个命令 |
| `grep '^otelcol_receiver...'` | 过滤出接收器统计行 |

**`^` 是什么？** 是正则里的"行首锚点"，表示"这一行必须以这个开头"。不加 `^` 的话，连 `# HELP otelcol_receiver...` 这种注释行也会被匹配出来。

**期望输出：**

```
otelcol_receiver_accepted_metric_points{receiver="hostmetrics",...} 670
otelcol_receiver_accepted_metric_points{receiver="redis",...} 480
```

**这一行的含义：**
- `receiver="hostmetrics"` = 主机采集器
- 数值 `670` = **累计接收了 670 个数据点**

**再验证发送端：**

```bash
curl -s http://127.0.0.1:18888/metrics | grep '^otelcol_exporter_sent_metric_points'
```

**期望输出：**

```
otelcol_exporter_sent_metric_points{exporter="otlp",...} 1150
```

**⭐ 关键的验证逻辑：接收数应该 ≈ 发送数**

```
接收：hostmetrics 670 + redis 480 = 1150
发送：otlp 1150
      ↑ 完全相等 → 数据一条没丢 ✅
```

**再看失败数：**

```bash
curl -s http://127.0.0.1:18888/metrics | grep 'otelcol_exporter_send_failed'
```

**期望：什么都不输出**（表示 0 次失败）。

**如果这里有输出，说明数据发送失败**，常见原因：
1. 网络不通（平台地址填错，或防火墙）
2. 平台端满了/挂了

**这三个数字（接收、发送、失败）是我每次验证时的"铁三角"**，只要发送=接收且失败=0，就说明**这条链路是通的**。

---

## 第四章 Windows 服务器：麻烦开始的地方

我们的环境里 **10 台是 Windows Server 2012 R2**，只有 3 台是 Linux。所以 Windows 才是主战场。

Windows 上装探针，比 Linux 麻烦不少，主要因为：

1. **版本受限**：2012 R2 太老，只能用 0.88.0
2. **没有 systemd**：不能像 Linux 那样做成系统服务（公司文档里"Windows 服务注册方式待补充"，等于没给方案）
3. **命令行不统一**：`cmd` 和 `PowerShell` 是两套东西，命令完全不同

### 4.1 Windows 版探针的安装

**安装包**：`otelcol-contrib_0.88.0_windows_amd64.tar.gz`

**安装目录**：`C:\otelcol\`（这是公司文档规定的，我们照做）

**解压**：Windows 上 `tar` 命令从 Windows 10/Server 2019 才自带。2012 R2 没有。所以用 7-Zip 或者 PowerShell 解压：

```powershell
# 用 PowerShell 解压 tar.gz（Windows 10+ 可用）
tar -zxvf .\otelcol-contrib_0.88.0_windows_amd64.tar.gz -C C:\otelcol
```

**验证程序能不能跑：**

```powershell
& "C:\otelcol\otelcol-contrib.exe" --version
```

**这条命令里的 `&` 是什么意思？**

在 PowerShell 里，`&` 叫**调用运算符**（call operator）。

**为什么必须加？** 因为 PowerShell 把带引号的字符串当成**纯文本**，不当命令。看这个例子：

```powershell
# ❌ 这样不行
"C:\otelcol\otelcol-contrib.exe" --version
# 报错：无法将"C:\otelcol\otelcol-contrib.exe"项识别为 cmdlet...

# ✅ 这样才行
& "C:\otelcol\otelcol-contrib.exe" --version
```

**`&` 就是在告诉 PowerShell："后面这个字符串不是文本，是个命令，去执行它。"**

**这个坑我踩过无数次**，特别是路径里带空格的时候（比如 `D:\Program Files\...`），必须加引号，加了引号就必须加 `&`。

### 4.2 ⚠️ cmd 和 PowerShell 是两回事（这个坑太常见了）

**这是我在带人做这个项目时遇到最多的困惑。**

看这段真实的对话（当时我让对方执行 PowerShell 命令，结果他在 cmd 里敲）：

```
C:\>Get-Process -Name java
'Get-Process' 不是内部或外部命令，也不是可运行的程序或批处理文件。

C:\>Test-Path "C:\app-discovery.ps1"
'Test-Path' 不是内部或外部命令，也不是可运行的程序或批处理文件。
```

**为什么报错？** 因为他**在 cmd 里敲 PowerShell 的命令**。

**两者的区别：**

| | cmd（命令提示符） | PowerShell |
|---|---|---|
| 窗口外观 | 黑底白字，提示符 `C:\>` | 蓝底白字，提示符 `PS C:\>` |
| 列进程 | `tasklist` | `Get-Process` |
| 列文件 | `dir` | `Get-ChildItem`（也能用 `dir`，是别名） |
| 看文件内容 | `type 文件` | `Get-Content 文件` |
| 找字符串 | `findstr` | `Select-String` |
| 判断文件存在 | `if exist 文件` | `Test-Path 文件` |
| 网络测试 | `ping` / `telnet` | `Test-NetConnection` |

**怎么分辨自己在哪个环境里？**

**看提示符**：
- `C:\>` → **cmd**
- `PS C:\>` → **PowerShell**

**怎么切换？**

```powershell
# 在 cmd 里进入 PowerShell
C:\> powershell

# 在 PowerShell 里回到 cmd
PS C:\> exit
```

**或者直接**：开始菜单 → 搜索 `PowerShell` → 右键"以管理员身份运行"。

**为什么强调"以管理员身份"？** 因为后面很多操作要：
- 杀掉别的用户的进程
- 写 `C:\otelcol\` 和 `D:\app\` 这样的系统目录
- 改 Tomcat 的配置文件

**非管理员权限会各种"拒绝访问"，白白浪费时间。**

**顺带说一个 PowerShell 的贴心设计**：它的很多命令有"别名"，兼容老习惯：

```powershell
dir        # 等价于 Get-ChildItem
ls         # 等价于 Get-ChildItem
cd         # 等价于 Set-Location
type       # 等价于 Get-Content
cat        # 等价于 Get-Content
```

**所以 `dir` 在 PowerShell 里也能用**，但 `findstr`、`tasklist` 这些外部程序虽然也能调用，风格不统一。**建议在 PowerShell 里就用 PowerShell 的命令。**

### 4.3 查看 Java 进程：找到要监控的应用

这是每次接入新应用的第一步：**搞清楚这台机器上有哪些 Java 进程。**

**方法一（推荐）：用 CIM 查，能看到完整命令行**

```powershell
Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Select-Object ProcessId,CommandLine | Format-List
```

**拆开看：**

| 部分 | 含义 |
|---|---|
| `Get-CimInstance` | 获取 CIM（原来叫 WMI）实例，能拿到系统底层信息 |
| `Win32_Process` | 进程类 |
| `-Filter "Name='java.exe'"` | **在系统层面过滤**，只返回 java.exe 进程 |
| `\| Select-Object ProcessId,CommandLine` | 只挑出进程号和命令行两列 |
| `\| Format-List` | **竖着显示**（因为命令行很长，横着会被截断） |

**⭐ `Format-List` 很关键。** 默认的表格格式会把长命令行截断成 `...`，你就看不到关键的 `-jar` 参数了。换成 `Format-List` 就能看全。

**方法二：`jps`（JDK 自带，但不一定有）**

```powershell
jps -lv
```

- `jps` = Java Process Status，JDK 自带的工具
- `-l` = 显示完整的包名/主类
- `-v` = 显示 JVM 参数

**为什么"不一定有"？**

因为 `jps` 在 **JDK 的 `bin` 目录**里。如果：
- 服务器装的是 **JRE**（不是 JDK）→ 没有 `jps`
- 装了 JDK 但 **`bin` 目录没加到 PATH** → 直接敲 `jps` 会报"不是内部或外部命令"

**我们就遇到过这个情况**，服务器上明明装了 `jdk1.8.0_131`，但敲 `jps` 提示找不到。解决办法是用**完整路径**：

```powershell
& "D:\Program Files\Java\jdk1.8.0_131\bin\jps.exe" -lv
```

**或者干脆用方法一（`Get-CimInstance`）**，不依赖 JDK 环境，更省事。**我后来都直接用它了。**

**方法三：`wmic`（老系统上可用）**

```cmd
wmic process where "name='java.exe'" get ProcessId,CommandLine /format:list
```

`wmic` 在 Windows Server 2012 R2 上还能用（新版本 Windows 已经弃用了）。**`/format:list` 就是竖排显示的意思**，同 `Format-List`。

### 4.4 我们写的应用发现脚本（app-discovery.ps1）

**为什么写这个脚本？**

因为手工排查一台机器要执行七八条命令，看半天输出。我们有 13 台机器，手工做太慢，而且容易漏。

所以我写了一个脚本，**一条命令把这些事全干了**：

1. 列出所有 Java 进程的完整命令行
2. 找出每个 Tomcat 的目录
3. 找出每个 Tomcat 里部署了哪些 web 应用（`webapps` 下的子目录）
4. **自动读每个应用的配置文件，找出 `app.code` 和 `service.name`**
5. 结果同时打印到屏幕 + 存成文件

**怎么用：**

```powershell
powershell -ExecutionPolicy Bypass -File C:\app-discovery.ps1
```

**这条命令拆开看：**

| 部分 | 含义 |
|---|---|
| `powershell` | 启动 PowerShell |
| `-ExecutionPolicy Bypass` | **绕过执行策略**（见下） |
| `-File C:\app-discovery.ps1` | 要执行的脚本文件 |

**⚠️ `-ExecutionPolicy Bypass` 是什么？为什么要加？**

PowerShell 有个安全机制叫"执行策略"（Execution Policy），**默认禁止运行 `.ps1` 脚本文件**，防止恶意脚本。直接运行会报错：

```
无法加载文件 C:\app-discovery.ps1，因为在此系统上禁止运行脚本。
```

**`-ExecutionPolicy Bypass` 就是"这一次执行，绕过这个限制"**。注意它只影响这一次执行，**不会永久修改系统设置**，比较安全。

**想永久改的话**（需要在管理员 PowerShell 里执行）：

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

- `RemoteSigned` = 本地脚本可以跑，从网上下载的脚本需要签名
- `-Scope CurrentUser` = 只对当前用户生效（比改全局安全）

**脚本输出的样子：**

```
=== APP DISCOVERY BEGIN ===
HOST=WIN-44QOJ4RLAU0
TIME=2026-09-28 14:30:34
JAVA_COUNT=4
--- pid=4528
    cmd: "D:\Program Files\Java\jdk1.8.0_131\bin\java.exe"  -Djava.util.logging.config.file="D:\Server\apache-tomcat-9.0.115 - BPM\conf\logging.properties" ...
--- pid=8284
    cmd: "D:\Program Files\Java\jdk1.8.0_131\bin\java.exe"  -Djava.util.logging.config.file="D:\Server\apache-tomcat-9.0.115 - DDGL\conf\logging.properties" ...
TOMCAT_HOMES=5
=== TOMCAT D:\Server\apache-tomcat-9.0.115 - BPM
--- APP ROOT   (context=/ROOT)
      [ROOT] 目录内未找到配置里的 name/code
=== TOMCAT D:\Server\apache-tomcat-9.0.115 - DDGL
--- APP Inspur.Dzzw.DispatchSystem   (context=/Inspur.Dzzw.DispatchSystem)
      [Inspur.Dzzw.DispatchSystem] 目录内未找到配置里的 name/code
=== APP DISCOVERY END ===
```

**怎么读这个输出？**

| 输出行 | 含义 |
|---|---|
| `HOST=WIN-44QOJ4RLAU0` | 这台机器的主机名（后面配置里要填） |
| `JAVA_COUNT=4` | 有 4 个 Java 进程 |
| `--- pid=4528` | 第 1 个进程，进程号 4528 |
| `cmd: ...` | **它的完整启动命令**（能看出是哪个 Tomcat） |
| `TOMCAT_HOMES=5` | 找到 5 个 Tomcat 目录 |
| `=== TOMCAT D:\Server\...- BPM` | 第 1 个 Tomcat 的路径 |
| `--- APP ROOT (context=/ROOT)` | 里面部署了一个应用，访问路径是 `/ROOT` |
| `[ROOT] 目录内未找到配置里的 name/code` | **⚠️ 没读到 app.code，需要手工查** |

**看到"目录内未找到配置里的 name/code"怎么办？**

这说明应用没有用标准的 Spring Boot 配置格式（`application.yml` 里的 `spring.application.name`）。**浪潮的这套系统大多不是标准 Spring Boot**，而是用 `.properties` 文件，而且文件名五花八门。

**这时候就得手工查。** 下一章讲怎么查。

---

## 第五章 找 `app.code`：这个活比想象中难

### 5.1 为什么必须找到 app.code

因为**平台上的数据要能对应到业务系统**。

如果你把一个应用的名字随便起成"应用1"、"应用2"，那么：

- 报警的时候说"应用1 内存满了"——**谁听得懂？**
- 出报表的时候"应用1 的可用率 99.2%"——**报给谁看？**
- 巡检的时候"这两个应用编码对不上公司清单"——**你解释不清**

**所以必须用应用自己声明的名字。**

### 5.2 怎么找？四种办法，从快到慢

**办法一：在 `constant.properties` 里找（命中率最高）**

浪潮的应用基本都有这个文件，里面写着 `app.code`：

```powershell
Get-Content "D:\Server\apache-tomcat-9.0.115 - BPM\webapps\ROOT\WEB-INF\classes\constant.properties" | Select-String "code"
```

**输出的样子：**

```
app.code=INSPUR-DZZW-BPM
app.mode=devtest
app.run.mode=devtest
```

**⭐ `app.code=INSPUR-DZZW-BPM` 就是我们要的！**

**这条命令拆开看：**

| 部分 | 含义 |
|---|---|
| `Get-Content "文件路径"` | 读文件内容 |
| `\| Select-String "code"` | 过滤出**包含 "code" 的行** |

**`Select-String` 相当于 Linux 的 `grep`。** 用它可以快速从一大段配置里挑出你要的行。

**办法二：在 `auth.properties` 里找**

有些应用没有 `constant.properties`，但 `auth.properties` 里有 `app.id`：

```powershell
Get-Content "D:\server\apache-tomcat-9.0.87-XZSP\webapps\Inspur.Dzzw.WebApproval\WEB-INF\classes\auth.properties"
```

**输出：**

```
app.id=INSPUR-DZZW-BSP
app.secret= ASMIQM5C8O64P9COLH6I
app.callback=http://localhost:8282/bsp/web/callback
```

**⚠️ 注意！这个结果有问题！**

我们在配置 XZSP（行政审批系统）时，读到 `app.id=INSPUR-DZZW-BSP`——**这是 BSP 的编码！**

但 XZSP 的 Tomcat 目录是 `apache-tomcat-9.0.87-XZSP`，应用名是 `Inspur.Dzzw.WebApproval`，**怎么可能是 BSP？**

**这明显是配置文件从 BSP 复制过来时没改干净。**

**遇到这种情况怎么办？**

1. **不要直接用它**——用了就串台了，XZSP 的数据会算到 BSP 头上
2. **用目录名 / 应用名推断一个合理的编码**——我们用了 `INSPUR-DZZW-XZSP`
3. **记录下来，事后找应用负责人确认**

**这就是"配置不能全信，要交叉验证"的道理。** 如果我只用 `auth.properties`，就会把 XZSP 的数据错误地标成 BSP。

**办法三：搜整个 classes 目录（最全，但输出多）**

```powershell
Get-ChildItem "D:\server\apache-tomcat-9.0.115 - BPM\webapps\ROOT\WEB-INF\classes" -Recurse -Include *.properties,*.yml,*.yaml | ForEach-Object { Write-Host "--- $($_.FullName)"; Get-Content $_.FullName | Select-String -Pattern "name|code|app|service" -CaseSensitive:$false | Select-Object -First 5 }
```

**这条命令比较长，拆开看：**

| 部分 | 含义 |
|---|---|
| `Get-ChildItem "目录" -Recurse` | **递归**列出目录下所有文件 |
| `-Include *.properties,*.yml,*.yaml` | 只要这几种后缀的文件 |
| `\| ForEach-Object { ... }` | **对每个文件执行一次 `{ }` 里的操作** |
| `Write-Host "--- $($_.FullName)"` | 先打印文件名（`$_` 表示当前文件，`$($_.FullName)` 取它的完整路径） |
| `Get-Content $_.FullName` | 读这个文件 |
| `\| Select-String -Pattern "name\|code\|app\|service"` | 过滤出含这些关键词的行 |
| `-CaseSensitive:$false` | **不区分大小写**（这样 `App`、`APP`、`app` 都能匹配） |
| `\| Select-Object -First 5` | 每个文件最多显示 5 行（**防止刷屏**） |

**`$_` 是什么？** 是 PowerShell 里的"当前对象"变量。在 `ForEach-Object` 里，`$_` 就代表"正在处理的那个文件"。

**为什么要 `-First 5`？** 因为有些配置文件（比如 `log4j.properties`）里有几百行，不限制的话屏幕会被刷爆。**先看前 5 行，不够再加。**

**办法四：从 Tomcat 日志里找**

如果配置文件里真找不到，看应用启动时打印的日志：

```powershell
Get-Content "D:\server\apache-tomcat-9.0.115-BPM\logs\catalina.2026-09-28.log" -Tail 200 | Select-String -Pattern "application|app.name" -CaseSensitive:$false
```

- `-Tail 200` = 只看**最后 200 行**（日志文件可能几百 MB，全读会很慢）

### 5.3 找不到时的兜底方案

**如果四种办法都找不到 `app.code`，怎么办？**

用**目录名或应用名**当标识，比如：

| 应用 | 兜底 service.name |
|---|---|
| WebDisk | `INSPUR-DZZW-DISK` |
| QYSL | `INSPUR-DZZW-QYSL` |
| XZSP | `INSPUR-DZZW-XZSP` |


## 第六章 用脚本生成配置（别手工复制粘贴）

### 6.1 为什么要写脚本

我们 13 台服务器，每台的配置都不一样：

- 主机名不同
- IP 不同
- 装的数据库/中间件不同（有的有 Redis，有的有 MySQL，有的什么都没有）
- 有的机器上一个应用，有的机器上四个

**手工复制粘贴配置的后果**：

- 改漏一个 IP → 数据上报到错误的机器名下
- 改漏一个应用名 → 数据串台
- 花括号/缩进错一个 → 探针起不来

**所以我写了个 Python 脚本 `make_config.py`，按参数生成配置。**

### 6.2 脚本怎么用

**最基本的用法（只采主机）：**

```bash
python make_config.py --name nc-ucb-1-05 --gov-ip *.*.*.241 --endpoint 192.168.140.60:4317 --objects host
```

**带数据库和中间件的：**

```bash
python make_config.py --name WIN-BLK3HH5RG2Q --gov-ip *.*.*.100 \
    --endpoint *.*.*.238:4317 --objects redis,memcached \
    --redis-endpoint 127.0.0.1:6379 --memcached-endpoint 127.0.0.1:11211 \
    --note "4个Java应用；Redis无密码"
```

**带应用 JMX 的（这是后面加的）：**

```bash
python make_config.py --name nc-ucb-1-05 --gov-ip *.*.*.241 \
    --endpoint 192.168.140.60:4317 --objects jmx \
    --jmx-endpoint 127.0.0.1:9999 \
    --jmx-name ONE-POLICY-MANAGE-CB \
    --jmx-appcode ONE-POLICY-MANAGE \
    --os-type linux --host-arch amd64 \
    --note "应用JMX监控"
```

**参数含义：**

| 参数 | 含义 | 例子 |
|---|---|---|
| `--name` | 主机名（用于生成文件名和 host.name） | `nc-ucb-1-05` |
| `--gov-ip` | 政务网 IP | `*.*.*.241` |
| `--endpoint` | 上报地址（**A 区/B 区要选对！**） | `192.168.140.60:4317` |
| `--objects` | 要采集哪些对象（逗号分隔） | `host,redis,mysql,jmx` |
| `--redis-endpoint` | Redis 地址 | `127.0.0.1:6379` |
| `--mysql-endpoint` | MySQL 地址 | `127.0.0.1:3306` |
| `--oracle-endpoint` | Oracle 地址 | `127.0.0.1:1521` |
| `--jmx-endpoint` | JMX 端口 | `127.0.0.1:9999` |
| `--jmx-name` | 应用的 service.name | `INSPUR-DZZW-BPM` |
| `--jmx-appcode` | 应用的 app.code | `INSPUR-DZZW-BPM` |
| `--note` | 备注（会写进配置头部的注释） | 随便写 |

**输出：**

```
OK -> D:\...\configs\config-*.*.*.241-nc-ucb-1-05.yaml
host.name = nc-ucb-1-05-241
objects   = jmx, host
```

**⭐ `--note` 这个参数别小看。** 它会把备注写进配置文件头部：

```yaml
# ==============================================================================
# otelcol-contrib 探针配置（适配 0.88.0）
# 主机名    : WIN-44QOJ4RLAU0
# 政务网 IP  : *.*.*.113
# 数据上报   : 192.168.140.60:4317
# 采集对象   : 主机、BPM应用JMX、Schedule应用JMX
# 备注       : 3个Tomcat(jdk1.8.0_131)+ZooKeeper3.8.4；ZK mntr被白名单挡、AdminServer /metrics 404
# 生成时间   : 2026-09-28 14:45:00
# ==============================================================================
```

**半年后你再看这个文件，一眼就知道这是哪台机器、采了什么、当时有什么特殊情况。** 这个习惯值得养。

**为什么用脚本生成而不是手工写？**

因为**生成后必须校验**：

```bash
# 本地先用探针程序校验生成的配置
& "C:\otelcol\otelcol-contrib.exe" validate --config="C:\otelcol\config.yaml"
```

**生成 → 校验 → 部署**，这个流程能保证配置一定是合法的。手工写的配置，你没法保证。

### 6.3 一个真实的脚本 bug（记录下来提醒自己）

脚本是在 Windows 上跑的（我的笔记本），但配置要部署到 Linux 服务器上。

**问题**：Windows 和 Linux 的**换行符不一样**：

| 系统 | 换行符 | 叫法 |
|---|---|---|
| Windows | `\r\n`（回车+换行） | CRLF |
| Linux | `\n`（只有换行） | LF |

**如果配置文件里是 Windows 换行符，拿到 Linux 上会出问题**——某些解析器会把 `\r` 当成内容的一部分。

**解决办法**：写文件时显式指定换行符：

```python
with open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(L))
```

**`newline="\n"` 就是强制用 Linux 换行符。**

**这个小细节不注意，会浪费你半天时间**——因为报错信息不会直接告诉你"换行符不对"，只会说配置解析失败。

### 6.4 批量远程执行的脚本（ssh_run.py）

配置生成好了，还要传到每台服务器上、重启探针、验证。**手工做 13 台太累。**

所以我写了 `ssh_run.py`，封装了 SSH 操作：

```bash
# 上传文件
python ssh_run.py put *.*.*.241 "..\configs\config.yaml" /tmp/probe-config.yaml

# 执行命令
python ssh_run.py exec *.*.*.241 'bash /tmp/upd.sh'
```

**输出：**

```
PUT OK  config.yaml -> /tmp/probe-config.yaml  (4228 bytes, md5=d073638a2f8660b39ee35503f7b52b08)
validate OK
systemd=active
```

**⭐ 注意输出里的 `md5=...`**

上传后打印 MD5 值，**这是为了验证文件传完整了**。

**MD5 是什么？** 是文件的"指纹"。同一个文件，MD5 一定相同；差一个字节，MD5 就完全不同。

**为什么要验证？** 因为网络传输可能出错（虽然少见），**传了个半截的文件上去，程序读不了，报一堆莫名其妙的错**。对比 MD5 就能立刻发现。

**这个技巧在传重要文件时特别有用**：

```powershell
# Windows 上算 MD5
Get-FileHash "D:\app\jmx_prometheus\jmx_prometheus_javaagent-0.15.0.jar" -Algorithm MD5

# Linux 上算 MD5
md5sum /opt/app/jmx_prometheus/jmx_prometheus_javaagent-0.15.0.jar
```

**两个值一样 = 文件传对了。**

---

## 第七章 主机监控和数据库/中间件监控

### 7.1 主机监控采了什么

`hostmetrics` 采集器输出的指标名都是 `system.` 开头的：

| 指标名 | 含义 | 单位 |
|---|---|---|
| `system.cpu.utilization` | CPU 使用率 | 0~1（乘 100 是百分比） |
| `system.memory.utilization` | 内存使用率 | 0~1 |
| `system.memory.usage` | 内存使用量 | 字节 |
| `system.filesystem.utilization` | 磁盘使用率 | 0~1 |
| `system.disk.io` | 磁盘读写量 | 字节 |
| `system.network.io` | 网络流量 | 字节 |
| `system.paging.utilization` | 交换分区使用率 | 0~1 |
| `system.processes.count` | 进程数 | 个 |

**在 SigNoz 里怎么看：**

左侧菜单 → 「基础设施」→「主机」，选一台机器，就能看到 CPU/内存/磁盘的曲线图。

**还可以在「指标」页面直接搜指标名：**

```
搜索框输入：system.cpu.utilization
过滤条件：service.name = 'nc-ucb-1-05'
```

### 7.2 主机监控踩的坑：`load` 在 Windows 上不可用

前面提过，这里详细说。

**我一开始的配置里带了 `load`：**

```yaml
scrapers:
  load: {}          # ← Windows 上会报错
```

**在 Linux 上跑得好好的，一到 Windows 就起不来：**

```
Error: invalid configuration: scraper "load" is not supported on this platform
```

**为什么？** 因为 `load average`（系统负载）是 **Unix 特有**的概念。Windows 没有这个东西。

**解决办法**：配置生成脚本里加了个参数 `--os-type`，Windows 就不生成 `load`：

```python
def hostmetrics_block(include_load=True):
    """hostmetrics 采集块。
    
    为什么 Linux 一定要开 load：
    Linux 的 load average 能反映"有多少进程在排队等 CPU"，
    这是判断系统是否过载的重要指标。Windows 没有这个概念。
    """
```

**这个教训是**：**跨平台的配置一定要分平台测试**。Linux 上能跑不代表 Windows 上能跑。

### 7.3 Redis 监控

**采什么：** Redis 的性能指标。

**探针配置：**

```yaml
receivers:
  redis:
    collection_interval: 60s
    endpoint: "127.0.0.1:6379"
    # 有密码的话加这行：
    # password: "你的密码"
```

**实测采集到的指标（29 个）：**

| 指标名 | 含义 |
|---|---|
| `redis.uptime` | 运行时长（秒） |
| `redis.clients.connected` | 当前连接数 |
| `redis.clients.blocked` | 被阻塞的连接数 |
| `redis.memory.used` | 已用内存 |
| `redis.memory.peak` | 内存峰值 |
| `redis.memory.rss` | 物理内存占用 |
| `redis.memory.fragmentation_ratio` | 内存碎片率 |
| `redis.keyspace.hits` | 命中次数 |
| `redis.keyspace.misses` | 未命中次数 |
| `redis.keyspace.expires` | 过期 key 数 |
| `redis.commands.processed` | 处理的命令总数 |
| `redis.net.input` | 网络入流量 |
| `redis.net.output` | 网络出流量 |
| `redis.connections.received` | 累计接收连接数 |
| `redis.connections.rejected` | **被拒绝的连接数**（重要！） |
| `redis.cpu.time` | CPU 时间 |
| `redis.rdb.changes_since_last_save` | 距上次保存的变更数 |
| `redis.persistence.rdb_last_bgsave_time_sec` | RDB 保存耗时 |
| `redis.replication.*` | 主从复制相关 |

**⭐ 重点看这几个：**

| 指标 | 为什么重要 |
|---|---|
| `redis.clients.connected` | 连接数暴涨 → 应用有连接泄漏 |
| `redis.memory.fragmentation_ratio` | 碎片率 > 1.5 → 内存碎片严重，需要重启 |
| `redis.keyspace.hits / misses` | 命中率低 → 缓存设计有问题 |
| `redis.connections.rejected` | **有值 → 连接被打满了！这是事故信号** |

**我们的环境情况：**

- `*.*.*.100` 上有一台 Redis 5.0.10，**无密码**，`127.0.0.1:6379`
- 其他几台也有 Redis，都是本地连接

### 7.4 MySQL 监控

**探针配置：**

```yaml
receivers:
  mysql:
    collection_interval: 60s
    endpoint: "127.0.0.1:3306"
    username: "监控用户"
    password: "密码"
    # 也可以用配置文件方式：
    # database: "数据库名"
```

**实测采集到的指标（38 个），重点的几个：**

| 指标名 | 含义 |
|---|---|
| `mysql.connection.count` | 当前连接数 |
| `mysql.connection.max` | 最大连接数 |
| `mysql.connection.errors` | **连接错误数**（重要） |
| `mysql.threads.connected` | 已连接线程数 |
| `mysql.threads.running` | 正在运行的线程数 |
| `mysql.buffer_pool.pages` | 缓冲池页数 |
| `mysql.buffer_pool.data_pages` | 数据页数 |
| `mysql.buffer_pool.usage` | 缓冲池使用量 |
| `mysql.buffer_pool.dirty_pages` | 脏页数 |
| `mysql.operations` | 各类操作次数（按 operation 标签分） |
| `mysql.buffer_pool.operations` | 缓冲池读写次数 |
| `mysql.row_operations` | 行操作次数 |
| `mysql.locks` | 锁等待次数 |
| `mysql.handlers` | 各类 handler 调用次数 |
| `mysql.tmp_resources` | 临时表相关 |
| `mysql.commands` | 各类命令执行次数 |
| `mysql.log_operations` | 日志操作 |
| `mysql.page_operations` | 页操作 |
| `mysql.joins` | JOIN 次数 |
| `mysql.qcache` | 查询缓存 |
| `mysql.replica.*` | 主从相关 |
| `mysql.uptime` | 运行时长 |

**⭐ 重点看：**

| 指标 | 说明 |
|---|---|
| `mysql.connection.count` 对比 `mysql.connection.max` | 连接数接近上限 → 要扩容 |
| `mysql.connection.errors` | **有增长 → 有连接失败，应用可能有报错** |
| `mysql.operations{operation="read"}` | 读操作频率 |
| `mysql.buffer_pool.usage` | 缓冲池使用率低 → 内存给少了 |
| `mysql.locks` | **锁等待 → 有慢查询或死锁** |

### 7.5 Oracle 监控

**探针配置：**

```yaml
receivers:
  oracledb:
    collection_interval: 60s
    endpoint: "127.0.0.1:1521"
    username: "监控用户"
    password: "密码"
    service: "ORCL"          # 服务名
```

**实测采集到的指标（25 个）：**

| 指标名 | 含义 |
|---|---|
| `oracledb.sessions.usage` | 会话使用情况（按 status/type 分） |
| `oracledb.sessions.limit` | 会话上限 |
| `oracledb.logons` | 累计登录次数 |
| `oracledb.transactions` | 事务数（按 type 分） |
| `oracledb.user_commits` | 用户提交次数 |
| `oracledb.user_rollbacks` | 用户回滚次数 |
| `oracledb.cursor.count` | 当前游标数 |
| `oracledb.cursor.limit` | 游标上限 |
| `oracledb.physical_reads` | 物理读次数 |
| `oracledb.physical_writes` | 物理写次数 |
| `oracledb.logical_reads` | 逻辑读次数 |
| `oracledb.buffer_cache` | 缓冲缓存命中率 |
| `oracledb.library_cache` | 库缓存命中率 |
| `oracledb.shared_pool` | 共享池使用 |
| `oracledb.exchange_deadlocks` | **死锁次数**（重要！） |
| `oracledb.enqueue_deadlocks` | 队列死锁 |
| `oracledb.enqueue_locks` | 队列锁 |
| `oracledb.enqueue_resources` | 队列资源 |
| `oracledb.process.count` | 进程数 |
| `oracledb.process.limit` | 进程上限 |
| `oracledb.dml_locks` | DML 锁 |
| `oracledb.tablespace_size` | 表空间大小 |
| `oracledb.tablespace_usage` | 表空间使用 |
| `oracledb.executions` | 执行次数 |
| `oracledb.uptime` | 运行时长 |

**⭐ 重点看：**

| 指标 | 说明 |
|---|---|
| `oracledb.sessions.usage` 对比 `limit` | 会话快满了 → 连接池配置有问题 |
| `oracledb.exchange_deadlocks` | **有值 → 有死锁！** 要查业务逻辑 |
| `oracledb.tablespace_usage` | 表空间快满 → 数据库要爆了 |
| `oracledb.buffer_cache` 命中率 | 低于 90% → 内存不够 |
| `oracledb.cursor.count` 对比 `limit` | 游标泄漏的典型信号 |

### 7.6 为什么这些指标不用"猜"

**这里要特别说明一件事：上面这些指标名，我不是从文档抄的，是实测出来的。**

**为什么强调这个？**

因为**文档经常和实际不符**：

1. 文档可能写的是**新版本**的指标名，你用的老版本指标名不一样
2. 文档可能写的是**理论支持**，但实际那个版本还没实现
3. 文档可能有**拼写错误**

**正确的做法是实测：**

```bash
# 采一份数据，把指标名全部列出来
curl -s http://127.0.0.1:18888/metrics | grep '^otelcol_receiver_accepted'
```

**或者更直接——在 SigNoz 的「指标」页面，搜索框里输入 `mysql.` 看它自动提示出哪些指标名。** 平台里有的一定是真的。

**我们就是靠这个方法发现**：

- MySQL 实际输出 38 个指标（不是文档说的 50 多个）
- Redis 实际输出 29 个
- Oracle 实际输出 25 个

**所以做看板时，指标名要从平台上"抄"，不要从文档里"抄"。** 用文档里的名字做看板，很可能一块面板都出不来数据。

### 7.7 做看板（Dashboard）

指标采上来了，默认是在「指标」页面一条一条搜着看的，不直观。

**看板就是把多个指标图放到一页上。**

我们做了几块看板：

| 看板名 | 内容 | 状态 |
|---|---|---|
| Oracle 监控 | 14 个面板（会话、事务、死锁、表空间、缓存命中率…） | ✅ 已生成 JSON |
| Redis 监控 | 14 个面板（连接数、内存、命中率、碎片率…） | ✅ 已生成 JSON |
| 监控对象总览 | 表格形式列出所有被监控对象 | ✅ 已生成 JSON |
| MySQL 监控 | 待做 | ⏳ |
| 应用监控（JVM） | 待做 | ⏳ |

**看板的 JSON 文件可以直接导入 SigNoz。**

**这里有个注意点**：SigNoz 的看板导入功能在不同版本位置不一样。如果没有"导入 JSON"按钮，就得手工建面板，或者调用 API：

```bash
curl -X POST http://*.*.*.238:8086/api/v1/dashboards \
  -H "Content-Type: application/json" \
  -d @dashboard.json
```

**做看板的一个原则**：

> **一块看板只回答一类问题。**
>
> - 「主机健康」看板 → 回答"服务器有没有问题"
> - 「数据库健康」看板 → 回答"数据库有没有问题"
> - 「应用健康」看板 → 回答"应用有没有问题"

**把所有东西堆在一块看板上，等于没有看板。**

---

## 第八章 应用监控（JMX）—— 整个项目最核心的部分

前面几章都是"配菜"：主机指标、数据库指标、中间件指标。**这一章才是"主菜"。**

### 8.1 为什么主机和数据库指标不够

先看一个真实的场景：

> 早上 9 点，业务高峰。用户打电话说"系统好慢"。
>
> 你打开监控：
> - **主机指标**：CPU 65%、内存 70%、磁盘 40% —— **全都正常**
> - **数据库指标**：连接数 45/200、无死锁、缓冲池命中率 98% —— **也全都正常**
>
> 那问题在哪？**你不知道。**

**为什么不知道？**

因为**主机和数据库指标是"宏观"的**。CPU 65% 说明"整台机器还行"，但不代表"某个应用还行"。

真实情况可能是：

- 这台机器上跑了 4 个 Java 应用，**其中 1 个的 JVM 堆内存快满了，GC 疯狂回收**，占用了大量 CPU —— 但摊到整台机器的 CPU 上，只显示 65%
- 数据库连接数 45/200 看着很健康，但**某个应用的连接池配置是 10，已经用满了** —— 数据库层面根本看不出来

**所以必须深入到"应用层"，看每个应用自己的 JVM 状态。**

**应用层能回答这些问题：**

| 问题 | 对应的 JVM 指标 |
|---|---|
| 这个应用内存够不够？ | 堆内存使用量 / 最大值 |
| 有没有内存泄漏？ | 堆内存使用量的**趋势**（一直涨不降 = 泄漏） |
| GC 是不是太频繁？ | GC 次数 / GC 耗时 |
| GC 有没有造成卡顿？ | GC 耗时的**峰值** |
| 线程有没有暴涨？ | 当前线程数 |
| 有没有死锁？ | 死锁线程数 |
| 加载了多少类？ | 已加载类数 |
| 这个应用占多少 CPU？ | 进程 CPU 使用率 |

**这些问题，主机指标一个都回答不了。** 这就是要做应用监控的原因。

### 8.2 JMX 是什么

**JMX = Java Management Extensions**，是 Java 平台自带的一套**管理接口标准**。

**用大白话说**：**每一个 Java 程序启动后，都会自动开放一个"内部仪表盘"，里面有几百个读数**——内存用了多少、GC 跑了几次、有多少线程、加载了多少类……

**这个"仪表盘"就是 JMX。**

**怎么看到它？**

Java 自带两个工具：

```bash
# 命令行工具：看某个 Java 进程的 JMX 数据
jconsole

# 或者
jvisualvm
```

它们能连上本地或远程的 Java 进程，图形化显示所有 JMX 指标。

**但这两个工具的问题是**：

1. **只能一个人看**——你打开 `jconsole` 连上去，别人看不到
2. **没有历史数据**——关掉就没了，看不到"昨天这个时候内存是多少"
3. **不能告警**——你得一直盯着

**所以我们要做的是：把 JMX 的数据"取出来"，变成一个 HTTP 接口，让监控系统定时去抓。**

**这就是 `jmx_prometheus_javaagent` 干的事。**

### 8.3 jmx_prometheus_javaagent 是什么

**它是一个 Java Agent。**

**Java Agent 是什么？** 是一种能在**不改一行业务代码**的情况下，给 Java 程序"加装外挂"的技术。它通过 JVM 的 `-javaagent` 参数加载，能在程序启动时和运行时介入。

**`jmx_prometheus_javaagent` 的作用**（名字就说明了）：

```
jmx_  +  prometheus  +  javaagent
 ↑           ↑             ↑
读JMX     转成Prometheus   以Java Agent方式
的数据      格式的HTTP接口     加载
```

**完整链条：**

```
Java 应用（内部有 JMX 数据）
        │
        │ ① jmx_prometheus_javaagent 读 JMX
        ▼
   HTTP 接口 http://127.0.0.1:9999/metrics
        │
        │ ② 探针每 60 秒来抓一次
        ▼
     探针 otelcol
        │
        │ ③ 打上标签后上报
        ▼
     SigNoz 平台
```

**这个 agent 是一个 jar 文件**，公司放在 `app.zip` 里，文件名：

```
jmx_prometheus_javaagent-0.15.0.jar
```

**大小 418240 字节**（很重要，传完要核对）。

### 8.4 ⚠️ 公司给的规则文件，绝对不能直接用

**这是整个项目里我最有"技术判断"的一次决定，值得详细讲。**

**agent 需要一个"规则文件"（config.yaml），告诉它"要暴露哪些 JMX 数据"。**

公司给的规则文件**只有 88 字节**，内容核心就一行：

```yaml
rules:
  - pattern: ".*"
```

**`pattern: ".*"` 是什么意思？**

- `pattern` = 要匹配的 JMX 对象名（MBean 名字）
- `.*` = **正则表达式，匹配"所有东西"**

**翻译成人话：把这个 JVM 里所有的 JMX 数据，全部暴露出来。**

**听起来很美好？实际上是个灾难。**

**为什么？**

一个 Tomcat 应用里的 JMX MBean 有几类：

| MBean 类型 | 数量级 |
|---|---|
| JVM 基础（内存、GC、线程、类加载） | 约 60 个 |
| Tomcat（连接器、线程池、Session、Servlet…） | 几十到几百个 |
| 应用的业务 MBean | **可能有几千个** |
| 第三方框架（HikariCP、Dubbo、Redis 客户端…） | 几十到几百个 |

**`pattern: ".*"` 会把"业务 MBean"也全部暴露。**

**业务 MBean 为什么会有几千个？** 因为有些框架会**给每个业务对象注册一个 MBean**。比如：

- 一个审批系统，每个审批流程模板注册一个 MBean
- 一个表单系统，每个表单注册一个 MBean
- 结果就是：**MBean 数量 = 业务数据量**

**我们的实际情况：**

一台服务器上有 4 个应用，每个应用如果真的产生几千条时间序列：

```
4 个应用 × 2000 条序列 = 8000 条序列/台
8000 条 × 13 台服务器 = 104000 条序列
每分钟采集一次 → 每天 1.5 亿个数据点
```

**SigNoz 的 ClickHouse 会被这个数据量拖垮**——查询变慢、磁盘写满、整个平台不可用。

**而且这些业务 MBean 的指标名是"动态"的**（名字里带着业务对象的 ID），**根本没法做看板、没法做告警**，只有存储成本，没有任何价值。

**所以我自己写了一份精简规则文件**，只保留**真正有用**的指标。

### 8.5 精简规则文件：从几千条压到 89 条

**精简原则：只保留"和 JVM 健康相关"的指标。**

我保留了这些类别：

| 类别 | 保留的指标 | 为什么 |
|---|---|---|
| **内存** | 堆内存 used/committed/max、非堆内存、各内存池 | 看内存够不够、有没有泄漏 |
| **GC** | GC 次数、GC 耗时 | 看 GC 是否频繁、是否卡顿 |
| **线程** | 当前线程数、守护线程、峰值、死锁数 | 看线程泄漏、死锁 |
| **类加载** | 已加载类数、已卸载类数 | 看类加载泄漏 |
| **缓冲区** | 直接内存缓冲区 | 看 NIO 内存 |
| **OS** | 进程 CPU 负载、系统 CPU 负载、文件描述符 | 看资源占用 |
| **进程** | 进程 CPU 时间、物理内存、虚拟内存、打开的文件数 | 看进程级资源 |

**精简后的效果（实测）：**

| 方案 | 指标名数量 | 时间序列数量 |
|---|---|---|
| 公司通配规则 `pattern: ".*"` | 估算 1000+ | **估算 2000+** |
| **我们的精简规则** | **61** | **89 行（105 条序列）** |

**压缩比约 1/20 到 1/50。**

**在 `*.*.*.241` 上实测 `one-manage-1.0.0.jar` 的完整指标清单（89 行 `jvm_` 指标）：**

```
jvm_buffer_pool_capacity_bytes
jvm_buffer_pool_used_buffers
jvm_buffer_pool_used_bytes
jvm_classes_loaded
jvm_classes_loaded_total
jvm_classes_unloaded_total
jvm_gc_collection_seconds_count
jvm_gc_collection_seconds_sum
jvm_info
jvm_memory_bytes_committed
jvm_memory_bytes_init
jvm_memory_bytes_max
jvm_memory_bytes_used
jvm_memory_heap_committed_bytes
jvm_memory_heap_init_bytes
jvm_memory_heap_max_bytes
jvm_memory_heap_used_bytes
jvm_memory_nonheap_committed_bytes
jvm_memory_nonheap_init_bytes
jvm_memory_nonheap_max_bytes
jvm_memory_nonheap_used_bytes
jvm_memory_pool_bytes_committed
jvm_memory_pool_bytes_init
jvm_memory_pool_bytes_max
jvm_memory_pool_bytes_used
jvm_os_availableprocessors
jvm_os_maxfiledescriptorcount
jvm_os_openfiledescriptorcount
jvm_os_processcpuload
jvm_os_systemcpuload
jvm_threads_current
jvm_threads_daemon
jvm_threads_deadlocked
jvm_threads_peak
jvm_threads_started_total
jvm_threads_state
jvm_uptime_millis
process_cpu_seconds_total
process_max_fds
process_open_fds
process_resident_memory_bytes
process_start_time_seconds
process_virtual_memory_bytes
```

**这是一份"够用而不臃肿"的清单。**

**⭐ 一个意外的发现**：`jmx_prometheus_javaagent` 会**自动附加一套内置的默认规则**（就是 `jvm_memory_bytes_used`、`jvm_gc_collection_seconds_count` 这些标准名）。所以你写的规则是**追加**在默认规则之上的，不是替换。

**这解释了两个现象**：

1. 我们只有约 40 条自定义 pattern，但输出了 61 个指标名 —— 多出来的是内置的
2. 同时存在 `jvm_memory_heap_used_bytes`（我们的规则）和 `jvm_memory_bytes_used`（内置规则）—— **两套命名并存，略有冗余但无害**

**知道这一点很重要**：你**没法把指标压到比内置规则更少**。89 条基本就是这个版本的下限了。

**所以我把规则文件正式命名并归档：**

```
浪潮可观测部署/应用接入/jmx-prometheus-rules-精简版.yaml
```

以后每台机器都用这一份，**不要用公司那份 88 字节的**。

### 8.6 给 Spring Boot 应用（jar 启动）加 agent

**第一步：搞清楚这个应用是怎么启动的**

这一步**不能跳**，因为不同启动方式改的文件完全不同：

| 启动方式 | 改哪个文件 |
|---|---|
| 命令行脚本（`restart.sh` / `start.sh` / `start.bat`） | 改那个脚本 |
| Tomcat | 改 `bin\setenv.bat` |
| Windows 服务 / NSSM / WinSW | 改服务配置里的启动参数 |
| Java Service Wrapper | 改 wrapper 配置 |

**怎么查？**

```bash
# Linux：看进程和它的父进程
ps -eo pid,ppid,args | grep '[j]ava'

# 看它的工作目录（通常是应用目录）
readlink /proc/<PID>/cwd
```

```powershell
# Windows：看进程的父进程
Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Select-Object ProcessId,ParentProcessId,CommandLine | Format-List
```

**为什么要看父进程？** 因为如果是被某个脚本或服务拉起来的，**你直接改 java 命令是没用的**（下次重启又被覆盖）。必须找到那个"真正的源头"。

**第二步：备份启动脚本（血的教训）**

```bash
cp -a restart.sh restart.sh.bak.$(date +%Y%m%d%H%M%S)
```

**这条命令拆开看：**

| 部分 | 含义 |
|---|---|
| `cp` | copy，复制 |
| `-a` | archive，**保留所有属性**（权限、时间、所有者） |
| `restart.sh` | 源文件 |
| `restart.sh.bak.$(date +%Y%m%d%H%M%S)` | 目标文件名，**带时间戳** |
| `$(date +%Y%m%d%H%M%S)` | 命令替换，插入当前时间，比如 `20260928100155` |

**`-a` 为什么重要？** 因为如果用 `cp` 不加 `-a`，复制出来的文件**权限可能变了**（比如从可执行变成不可执行），回滚时就会出问题。

**为什么文件名要带时间戳？** 因为**你可能要改好几次**。不带时间戳的话，第二次备份会把第一次的覆盖掉，**你就失去了"回退到更早版本"的能力**。

**我们实际操作时的效果：**

```bash
ls -la restart.sh*
-rwxr-xr-x 1 root root 276 Sep  9 17:11 restart.sh
-rwxr-xr-x 1 root root 276 Sep 28 10:01 restart.sh.bak.20260928100155
-rw-r--r-- 1 root root 789 Sep 28 09:57 restart.sh.new
```

**一眼就能看出**：原版 276 字节、备份是 10:01 做的、新版本 789 字节。

**第三步：改启动脚本**

**原来的脚本长这样：**

```bash
#!/bin/bash
#定时任务，每天晚上12点自动执行重启和日志清除操作

# 停止进程
kill -9 $(pgrep -f "java -jar ./one-manage-1.0.0.jar")

# 清除日志
sudo truncate -s 0 /opt/server/manage/nohup.out

# 启动进程
nohup java -jar ./one-manage-1.0.0.jar &
```

**改成这样：**

```bash
#!/bin/bash
#定时任务，每天晚上12点自动执行重启和日志清除操作

# 停止进程
kill -9 $(pgrep -f "one-manage-1.0.0.jar")

# 清除日志
sudo truncate -s 0 /opt/server/manage/nohup.out

# 启动进程
nohup java \
  -javaagent:/opt/app/jmx_prometheus/jmx_prometheus_javaagent-0.15.0.jar=9999:/opt/app/jmx_prometheus/config.yaml \
  -jar ./one-manage-1.0.0.jar &
```

**我们实际改了两处，第二处很多人会漏掉，漏了会出大事。**

**改动一：加 `-javaagent` 参数**

```bash
-javaagent:<agent jar 路径>=<端口>:<规则文件路径>
```

**拆开看：**

| 部分 | 值 | 含义 |
|---|---|---|
| `-javaagent:` | 固定前缀 | 告诉 JVM 加载一个 agent |
| agent jar 路径 | `/opt/app/jmx_prometheus/jmx_prometheus_javaagent-0.15.0.jar` | agent 程序 |
| `=` | 分隔符 | |
| 端口 | `9999` | **指标 HTTP 接口监听的端口** |
| `:` | 分隔符 | |
| 规则文件路径 | `/opt/app/jmx_prometheus/config.yaml` | 精简规则 |

**⚠️ 位置要求：`-javaagent` 必须写在 `-jar` 之前！**

```bash
# ✅ 正确
java -javaagent:xxx.jar=9999:yyy.yaml -jar app.jar

# ❌ 错误（会当成应用的参数，agent 不生效）
java -jar app.jar -javaagent:xxx.jar=9999:yyy.yaml
```

**为什么？** 因为 `-jar` 之后的参数是**传给应用程序的**（叫"程序参数"），而 `-jar` 之前的参数是**传给 JVM 的**（叫"JVM 参数"）。`-javaagent` 是 JVM 参数。

**改动二（⚠️ 最容易漏）：修改 `pgrep` 的匹配模式**

**这个坑必须重点讲。**

原脚本里：

```bash
kill -9 $(pgrep -f "java -jar ./one-manage-1.0.0.jar")
```

**加上 agent 之后，进程的实际命令行变成了：**

```
java -javaagent:/opt/app/jmx_prometheus/jmx_prometheus_javaagent-0.15.0.jar=9999:/opt/app/jmx_prometheus/config.yaml -jar ./one-manage-1.0.0.jar
```

**这时候 `pgrep -f "java -jar ./one-manage-1.0.0.jar"` 还能匹配到吗？**

**不能了！** 因为实际命令行里 `java` 和 `-jar` 中间**插入了 `-javaagent:...`**，字符串 `java -jar ./one-manage-1.0.0.jar` **不再连续出现**。

**`pgrep -f` 的匹配规则是什么？**

- `pgrep` = process grep，按名字找进程
- `-f` = full，**匹配完整的命令行**（不加 `-f` 只匹配进程名，那就只能匹配到 `java`）
- 匹配方式是**"包含"**（子串匹配），不是精确匹配

**所以 `pgrep -f "java -jar ./one-manage-1.0.0.jar"` 的意思是：找到命令行里包含这个字符串的进程。**

**匹配失败会导致什么后果？**

```bash
kill -9 $(pgrep -f "java -jar ...")     # pgrep 没匹配到 → 返回空
                                        # → 命令变成 kill -9（没有参数）
                                        # → 报错 "kill: usage: ..."
```

**老进程杀不掉，然后脚本继续执行启动命令 → 启动第二个进程。**

**结果**：

- 第一次重启：老进程还在 + 新进程起来 → **两个进程抢同一个端口** → 新的起不来
- 第二次重启：还是杀不掉 → 还是起不来
- **而且老进程还在跑，看起来"服务正常"，所以你可能半天发现不了**

**我们的修复：**

```bash
# 改成只匹配 jar 名（这个字符串在两种情况下都存在）
kill -9 $(pgrep -f "one-manage-1.0.0.jar")
```

**为什么这样改就对了？**

因为不管有没有 `-javaagent`，**jar 文件名一定在命令行里**。所以匹配 jar 名是**最稳定的做法**。

**⚠️ 但要注意一个副作用**：如果同一个 jar 名被启动多次，`pgrep` 会返回多个 PID，`kill -9` 会把它们全杀掉。**这通常是我们想要的行为**（清理干净），但如果你有"多实例部署"的场景，就要小心了。

**⭐ 这条经验总结成一句话：**

> **凡是"按命令行匹配进程"的地方，加参数后一定要回头检查匹配模式还成不成立。**

**我们实际改动的 diff：**

```diff
--- restart.sh	2026-09-09 17:11:04
+++ restart.sh.new	2026-09-28 09:57:59
@@ -2,10 +2,16 @@
 #定时任务，每天晚上12点自动执行重启和日志清除操作
 
 # 停止进程
-kill -9 $(pgrep -f "java -jar ./one-manage-1.0.0.jar")
+# 改动1：加上 -javaagent 后，命令行变成 "java -javaagent:... -jar ./one-manage-1.0.0.jar"
+#        原来的 pgrep -f "java -jar ./one-manage-1.0.0.jar" 匹配不到
+#        改成只匹配 jar 名最稳
+kill -9 $(pgrep -f "one-manage-1.0.0.jar")
 
 # 清除日志
 sudo truncate -s 0 /opt/server/manage/nohup.out
 
 # 启动进程
-nohup java -jar ./one-manage-1.0.0.jar &
+# 改动2：加一个 -javaagent，必须在 -jar 之前，把 JMX 指标暴露到 9999 端口
+nohup java \
+  -javaagent:/opt/app/jmx_prometheus/jmx_prometheus_javaagent-0.15.0.jar=9999:/opt/app/jmx_prometheus/config.yaml \
+  -jar ./one-manage-1.0.0.jar &
```

**⭐ 强烈建议：改完脚本，一定要跑一次 diff。**

```bash
diff -u restart.sh restart.sh.new
```

**`diff -u` 的输出格式**：
- `-` 开头 = 原来的内容（要被删掉的）
- `+` 开头 = 新的内容（要加进去的）
- `@@ -2,10 +2,16 @@` = 从第 2 行开始，原来 10 行、新的是 16 行

**为什么要 diff？** 因为**你能一眼看出"到底改了什么"**。如果改错了，你能及时发现；如果改对了，你心里有底。**这也是给别人 review 的标准方式。**

### 8.7 给 Tomcat 应用加 agent

**Tomcat 的情况不一样**，因为它自己的启动脚本 `startup.bat` / `catalina.sh` 是**Tomcat 自带的，不该直接改**（升级 Tomcat 时会被覆盖）。

**正确做法：用 `setenv.bat`（Windows）/ `setenv.sh`（Linux）。**

**`setenv` 是什么？**

Tomcat 的启动脚本里有一段逻辑：

```bat
# catalina.bat 里的逻辑（简化）
if exist "%CATALINA_BASE%\bin\setenv.bat" call "%CATALINA_BASE%\bin\setenv.bat"
```

**意思是**：如果 `bin` 目录下**存在** `setenv.bat`，就调用它。

**这是一个"官方预留的扩展点"**，专门用来放自定义的 JVM 参数。**你的改动不会和 Tomcat 自身的文件冲突。**

**⚠️ 我们的 Tomcat 目录里没有 `setenv.bat`。**

```
bootstrap.jar
catalina.bat
catalina.sh
catalina-tasks.xml
ciphers.bat
...
service.bat
setclasspath.bat
setclasspath.sh
shutdown.bat
shutdown.sh
startup.bat
startup.sh
```

**没有就新建一个**，Tomcat 会自动加载。

**在 PowerShell 里创建：**

```powershell
@"
set "JAVA_OPTS=%JAVA_OPTS% -javaagent:D:\app\jmx_prometheus\jmx_prometheus_javaagent-0.15.0.jar=9999:D:\app\jmx_prometheus\config.yaml"
set "JAVA_OPTS=%JAVA_OPTS% -javaagent:D:\app\opentelemetry-javaagent\opentelemetry-javaagent.jar"
set "JAVA_OPTS=%JAVA_OPTS% -Dotel.service.name=INSPUR-DZZW-BSP"
set "JAVA_OPTS=%JAVA_OPTS% -Dotel.exporter.otlp.endpoint=http://192.168.140.60:4318"
set "JAVA_OPTS=%JAVA_OPTS% -Dotel.exporter.otlp.protocol=http/protobuf"
set "JAVA_OPTS=%JAVA_OPTS% -Dotel.traces.exporter=otlp"
set "JAVA_OPTS=%JAVA_OPTS% -Dotel.resource.attributes=app.code=INSPUR-DZZW-BSP,deployment.environment=production,environment=production"
set "JAVA_OPTS=%JAVA_OPTS% -Dotel.traces.sampler=parentbased_traceidratio"
set "JAVA_OPTS=%JAVA_OPTS% -Dotel.traces.sampler.arg=0.1"
set "JAVA_OPTS=%JAVA_OPTS% -Dotel.logs.exporter=none"
"@ | Out-File -FilePath "D:\server\apache-tomcat-9.0.115-BSP\bin\setenv.bat" -Encoding ASCII
```

**这段 PowerShell 有几个地方要解释：**

**① `@"..."@` 是什么？**

这是 PowerShell 的**"Here String"**（对应 Linux 的 heredoc），用来表示**多行字符串**。

- `@"` 开始（`@` 后面必须**紧跟换行**）
- `"@` 结束（`"@` 必须**在行首**）

**⚠️ 两个规则很容易踩坑**：
- `@"` 后面不能有内容，必须直接换行
- `"@` 前面不能有缩进，必须在行首

**② `set "JAVA_OPTS=%JAVA_OPTS% ..."` 里的引号位置**

**这是 cmd 批处理的一个讲究。**

```bat
# ✅ 推荐写法（引号包住整个赋值）
set "JAVA_OPTS=%JAVA_OPTS% -javaagent:..."

# ⚠️ 不推荐的写法
set JAVA_OPTS=%JAVA_OPTS% -javaagent:...
```

**为什么？** 因为不把引号放前面的话，如果路径里有空格或特殊字符（比如 `D:\Program Files\...`），**cmd 会把空格后面的内容当成额外参数**，导致变量被截断。

**把引号放在 `set "` 后面、最后闭合**，是 cmd 里的标准安全写法。

**③ `%JAVA_OPTS%` 为什么要"自己引用自己"？**

```bat
set "JAVA_OPTS=%JAVA_OPTS% -javaagent:..."
```

**这是"追加"的写法**：取原来的值，加上新内容，再存回去。

**为什么不用 `+=` 或者多次赋值？**

因为如果用 `set "JAVA_OPTS=-javaagent:..."`（不带 `%JAVA_OPTS%`），**会把 Tomcat 原本设置的内存参数（`-Xms`、`-Xmx`）全部覆盖掉！**

**后果**：应用的内存上限变成默认值（通常是物理内存的 1/4），可能比你原来配的小得多，**高峰时段直接 OOM**。

**⚠️ 这是一个非常危险的坑。** 我们检查过一遍所有 `setenv.bat`，确认都用的是 `%JAVA_OPTS%` 追加模式。

**④ `-Encoding ASCII` 为什么要加？**

`Out-File` 默认的编码在 PowerShell 5.1（Windows Server 2012 R2 自带的就是 5.1）里是 **UTF-16 LE**。

**UTF-16 的 bat 文件，cmd 根本不认识**，执行时会报各种乱码错误。

**所以必须指定 `-Encoding ASCII`**（bat 文件里只有英文，用 ASCII 就够了）。

**如果 bat 文件里有中文**，那要用 `-Encoding Default`（对应系统的 ANSI 编码，中文 Windows 上是 GBK）。

**这个坑也很典型**：**Windows 上写脚本文件，一定要注意编码。**

**⑤ `-Dotel.resource.attributes=app.code=xxx,deployment.environment=production,environment=production`**

**注意这里同时写了 `deployment.environment` 和 `environment` 两个属性。**

**为什么？** 因为公司的配置生成器就是这么写的（两个都写，值相同）。我们照着做，**保证和公司口径一致**，避免巡检时被挑刺。

**代价**：多一个属性，多一点点存储空间。**这点代价换来合规，值。**

### 8.8 探针侧：怎么去抓 JMX 接口

应用侧的 agent 把指标暴露在 `127.0.0.1:9999` 上了，接下来**探针要定时去抓**。

**用 `prometheus` 采集器**：

```yaml
receivers:
  prometheus/jmx_bsp:
    config:
      scrape_configs:
        - job_name: 'INSPUR-DZZW-BSP'
          scrape_interval: 60s
          metrics_path: /metrics
          static_configs:
            - targets: ['127.0.0.1:9999']
```

**逐行解释：**

| 行 | 含义 |
|---|---|
| `prometheus/jmx_bsp:` | 采集器类型是 `prometheus`，**实例名**叫 `jmx_bsp` |
| `config:` | 下面就是标准的 Prometheus 抓取配置 |
| `job_name: 'INSPUR-DZZW-BSP'` | 任务名（**会被当成一个标签**，我们填服务编码） |
| `scrape_interval: 60s` | **每 60 秒抓一次** |
| `metrics_path: /metrics` | 抓取的 URL 路径 |
| `static_configs.targets` | **抓取目标地址** |

**`prometheus/jmx_bsp` 这个名字里的斜杠是什么意思？**

OpenTelemetry 的组件 ID 格式是 `<类型>/<实例名>`：

- `prometheus` = 组件类型
- `jmx_bsp` = 这个实例的名字（自己起，**同一台机器上多个实例必须不同名**）

**为什么一台机器上要多个 `prometheus` 采集器实例？**

因为**每个应用一个端口**：

```yaml
prometheus/jmx_bpm:      # 抓 9999
prometheus/jmx_schedule: # 抓 9998
prometheus/jmx_ddgl:     # 抓 9997
prometheus/jmx_sxgl:     # 抓 9996
```

**4 个应用就是 4 个采集器实例。** 一个采集器只能抓一个 `targets` 列表（虽然可以放多个地址，但那样标签就区分不了了）。

**⭐ 这是"一个应用一个实例"的关键原因**：因为**每个应用要打不同的标签**（服务名不同），而标签是在采集器后面的处理器里打的，**一条管道只能打一套标签**。

### 8.9 ⚠️ 0.88.0 的大坑：带点的标签名不能写在 `static_configs.labels`

**这个坑是"配置能通过校验、但探针直接起不来"的类型，很隐蔽。**

**我最初的想法**（很自然）：既然要给指标打标签，那就写在采集器的配置里：

```yaml
# ❌ 这样写，0.88.0 会报错
receivers:
  prometheus/jmx_bsp:
    config:
      scrape_configs:
        - job_name: 'INSPUR-DZZW-BSP'
          static_configs:
            - targets: ['127.0.0.1:9999']
              labels:
                app.code: "INSPUR-DZZW-BSP"
                service.name: "INSPUR-DZZW-BSP"
```

**看起来完全合理**，Prometheus 标准语法就是这样。**但 0.88.0 的采集器拒绝了这个配置。**

**报什么错？**

```
Error: failed to get config: cannot unmarshal the configuration: 
1 error(s) decoding:
* error decoding 'receivers': error reading configuration for "prometheus": 
  error reading configuration for "config": ...
```

**为什么？**

因为 `labels` 里的 **key 名不能包含点号**。而 `app.code`、`service.name`、`deployment.environment` **全都有点号**。

**这是 0.88.0 做的一个校验**（防止和 OpenTelemetry 的属性命名规范冲突），后续版本放宽了。

**解决办法：不用 `labels`，改用 `attributes` 处理器。**

```yaml
# ✅ 正确做法
receivers:
  prometheus/jmx_bsp:
    config:
      scrape_configs:
        - job_name: 'INSPUR-DZZW-BSP'
          scrape_interval: 60s
          metrics_path: /metrics
          static_configs:
            - targets: ['127.0.0.1:9999']

processors:
  attributes/jmx_bsp:
    actions:
      - key: app.code
        value: "INSPUR-DZZW-BSP"
        action: upsert
      - key: service.name
        value: "INSPUR-DZZW-BSP"
        action: upsert
      - key: service.instance.id
        value: "*.*.*.112:9999"
        action: upsert
      - key: service.type
        value: "application"
        action: upsert
      - key: service.subtype
        value: "jvm"
        action: upsert

service:
  pipelines:
    metrics/jmx_bsp:
      receivers: [prometheus/jmx_bsp]
      processors: [resourcedetection, resource/host_inject, attributes/jmx_bsp, batch]
      exporters: [otlp]
```

**区别在哪？**

| | `static_configs.labels` | `attributes` 处理器 |
|---|---|---|
| 打标签的时机 | **抓取时**（在采集器内部） | **抓取后**（作为数据的加工步骤） |
| key 能带点号吗 | ❌ 不能 | ✅ 能 |
| 灵活性 | 低 | 高（能做增删改） |

**⭐ 这个坑的教训**：

> **配置语法"看起来对"不等于"这个版本支持"。遇到启动报错，一定要 `validate` + 看 `components`，确认这个版本到底支持什么。**

### 8.10 验证应用监控是否成功

**第一步：验证 agent 起来了（在应用服务器上）**

```bash
curl -s http://127.0.0.1:9999/metrics | grep -c '^jvm_'
```

**期望输出：`89` 左右。**

**如果输出 `0` 或连接失败，说明 agent 没起来。** 检查：

1. **jar 文件在不在？** `ls -la /opt/app/jmx_prometheus/`（应该是 418240 字节）
2. **启动命令里有没有 `-javaagent`？** 看进程命令行
3. **端口是不是被占了？** `ss -lnt | grep ':9999 '`
4. **应用启动日志有没有报错？** 搜 `BindException`、`Address already in use`、`FATAL ERROR`

**第二步：验证探针抓到了（在应用服务器上）**

```bash
curl -s http://127.0.0.1:18888/metrics | grep '^otelcol_receiver_accepted_metric_points'
```

**期望输出**（多了一路 `prometheus/jmx_xxx`）：

```
otelcol_receiver_accepted_metric_points{receiver="hostmetrics",...} 3064
otelcol_receiver_accepted_metric_points{receiver="prometheus/jmx_one_policy_manage_cb",...} 864
```

**第三步：验证发送成功**

```bash
curl -s http://127.0.0.1:18888/metrics | grep '^otelcol_exporter_sent_metric_points'
curl -s http://127.0.0.1:18888/metrics | grep '^otelcol_exporter_send_failed'
```

**期望**：发送数 = 接收数之和，**失败那一行没有输出**。

**我们实测的一次结果：**

```
接收：hostmetrics 3064 + jmx 864 = 3928
发送：otlp 3928          ← 完全相等 ✅
失败：（无输出）          ← 0 失败 ✅
```

**第四步：验证探针日志里采集器启动成功**

```bash
journalctl -u otelcol-contrib -n 200 --no-pager | grep -i 'jmx\|prometheus'
```

**期望看到：**

```
Starting discovery manager  {"kind": "receiver", "name": "prometheus/jmx_one_policy_manage_cb"}
Scrape job added  {"jobName": "ONE-POLICY-MANAGE-CB"}
Starting scrape manager  {"name": "prometheus/jmx_one_policy_manage_cb"}
```

**这三行说明**：采集器启动 → 抓取任务注册 → 开始抓取。**看到这三行，应用侧就没问题了。**

**第五步：去 SigNoz 看数据**

「指标」页面搜索：

```
jvm_memory_bytes_used
```

过滤条件：

```
service.name = 'INSPUR-DZZW-BSP'
```

**能看到曲线，就成功了。**

---

## 第九章 链路追踪（Traces）—— 数据量的深渊

### 9.1 什么是"链路"

前面讲的指标都是"单点"的：这台机器 CPU 多少、这个应用内存多少。

**链路追踪解决的是另一个问题：一次请求，在各个系统之间是怎么流转的、每一段花了多久。**

**举个真实的例子：**

用户在政务网提交一个审批件，这个操作背后可能是：

```
用户点"提交"
   ↓
① 浏览器 → 门户系统（Nginx）
   ↓
② 门户系统 → 审批系统（HTTP 接口）
   ↓
③ 审批系统 → 权限服务（校验有没有权限）
   ↓
④ 审批系统 → 工作流引擎（启动流程）
   ↓
⑤ 工作流引擎 → Oracle 数据库（写流程实例）
   ↓
⑥ 审批系统 → Redis（清缓存）
   ↓
⑦ 返回给用户
```

**这 7 步里某一步慢，用户就感觉"系统卡"。**

**只有指标，你只知道"审批系统 CPU 高了"，但不知道是哪一步慢。**

**有了链路，你能看到：**

```
Trace ID: 7f3a9b2c1d4e5f60
  
  POST /approve/submit                      3200ms  ← 总耗时
    ├─ HTTP 门户转发                          8ms
    ├─ 权限校验                              15ms
    ├─ 工作流引擎启动                      3100ms  ← 罪魁祸首
    │    ├─ 查流程图定义                     20ms
    │    ├─ 写流程实例                   3050ms  ← 真正的原因
    │    │    └─ INSERT INTO WF_INSTANCE   3040ms
    │    └─ 发消息                           30ms
    └─ 清缓存                                 5ms
```

**一眼就知道：`INSERT INTO WF_INSTANCE` 这条 SQL 花了 3 秒。**

**这就是链路的价值——它把"一个请求"拆解成"一串有父子关系的片段"，每一段都有耗时。**

**术语说明：**

| 术语 | 英文 | 含义 |
|---|---|---|
| 链路 | Trace | 一次完整请求的全过程 |
| 片段 | Span | 链路里的一个步骤 |
| 父片段/子片段 | Parent/Child Span | 层级关系（像调用栈） |
| Trace ID | | 一次请求的唯一标识（贯穿所有片段） |
| Span ID | | 单个片段的唯一标识 |

### 9.2 opentelemetry-javaagent：链路也是 Agent

**好消息**：链路用的技术**和 JMX 是一样的**——**Java Agent**。

**文件名**：

```
opentelemetry-javaagent.jar
```

**大小 13408423 字节（约 13.4 MB）**（传完要核对）。

**版本**：1.16.0（启动日志里会打印）

**它做什么？**

它通过**字节码增强**技术，自动给这些常见组件"埋点"：

| 组件 | 自动埋点内容 |
|---|---|
| **Servlet / Spring MVC** | 每个 HTTP 请求产生一个 Span |
| **JDBC / 数据库驱动** | 每条 SQL 产生一个 Span（含 SQL 语句、耗时） |
| **Redis 客户端** | 每次 Redis 操作产生一个 Span |
| **HTTP 客户端** | 每次外部调用产生一个 Span |
| **Dubbo / gRPC** | 每次 RPC 调用产生一个 Span |
| **消息队列** | 生产/消费消息产生 Span |

**⭐ 这就是 Agent 技术的厉害之处：不用改一行业务代码，自动就有了全链路的埋点。**

**对老系统（比如我们这些 2018 年的政务系统）来说，这是唯一可行的方案**——你不可能让开发团队去给几十个系统改代码加埋点。

### 9.3 ⚠️ 采样率：不配这个参数，平台会被打爆

**这是链路部分最重要的知识点。**

**`opentelemetry-javaagent` 的默认采样率是 100%。**

**100% 是什么意思？**

> **每一个请求，都完整上报一条链路。**

**为什么这是灾难？**

假设审批系统每天有 50 万次请求，每次请求产生 1 条链路、每条链路平均 10 个 Span：

```
50 万 × 10 = 500 万个 Span/天
```

**每个 Span 在 ClickHouse 里占大约 500 字节**（含索引）：

```
500 万 × 500 字节 = 2.5 GB/天
```

**看起来还能接受？** 但别忘了：

- 我们**有 9 个应用**要接
- 有些应用的请求量比审批系统大得多（比如门户）
- 高峰期请求量可能是均值的 10 倍

**保守估计，9 个应用全开 100% 采样，每天 20~50 GB。**

**一个月就是 600 GB ~ 1.5 TB。** 我们给平台的磁盘是 2TB。**两个月就写满了。**

**写满之后会发生什么？**

- ClickHouse 写入失败 → 数据丢失
- 查询变慢 → 看板打不开
- **严重的话整个 SigNoz 平台不可用**

**所以采样率是"必须配"的，不是"可选优化"。**

**怎么配？**

```bash
-Dotel.traces.sampler=parentbased_traceidratio
-Dotel.traces.sampler.arg=0.1
```

**这两个参数的含义：**

| 参数 | 含义 |
|---|---|
| `otel.traces.sampler` | **采样器类型** |
| `otel.traces.sampler.arg` | **采样参数（比例）** |

**`parentbased_traceidratio` 这个采样器名字，拆开看：**

```
parent  based  _  traceid  ratio
  ↑       ↑         ↑        ↑
按父片段  基于    按TraceID  按比例
的采样决定         的哈希值   采样
```

**它的行为：**

1. **如果请求带着"父片段的采样决定"**（比如上游服务已经决定采样了），**就跟随父片段的决定**——这样一条完整链路要么全采、要么全不采，**不会出现"只采到一半"的残缺链路**
2. **如果没有父片段**（这是链路的起点），**就按 `traceid ratio` 采样**——用 Trace ID 的哈希值决定，保证**同一个 Trace ID 的采样决定是稳定的**

**为什么用 `traceid ratio` 而不是"随机采样"？**

因为用**哈希**的话，**同一个 Trace ID 每次计算结果都一样**。如果用纯随机，"决定采不采"这件事在不同环节可能得到不同答案，链路就断了。

**`arg=0.1` 就是采样 10%。**

**比例怎么选？**

| 采样率 | 数据量 | 适用场景 |
|---|---|---|
| `1.0`（100%） | 最大 | 只适合请求量极小的系统 |
| `0.5`（50%） | 一半 | 调试排查期，短期开 |
| **`0.1`（10%）** | **1/10** | **我们选的，常规起点** |
| `0.05`（5%） | 1/20 | 请求量较大的系统 |
| `0.01`（1%） | 1/100 | 高流量系统 |

**我们的选择过程：**

**第一天**用了 10%，观察了一天数据量。发现：

- 链路页面翻页时，每分钟有几十条记录
- 平台响应正常
- 磁盘增长在可接受范围

**所以保持 10%。** 如果数据量太大，改成 0.05 或 0.01 就行——**只改这一个数字，重启应用即可。**

**⭐ 怎么"观察数据量"？**

最直接的方法：**打开 SigNoz 的「链路」页面，看单位时间内的记录条数。**

或者估算：

```
数据量 = 请求量 × 采样率 × 每条链路的平均 Span 数 × 每个 Span 的存储开销
```

### 9.4 完整的启动参数

**在已有的 JMX agent 后面，追加这一段：**

```bash
-javaagent:/opt/app/opentelemetry-javaagent/opentelemetry-javaagent.jar \
-Dotel.service.name=INSPUR-DZZW-BSP \
-Dotel.exporter.otlp.endpoint=http://192.168.140.60:4318 \
-Dotel.exporter.otlp.protocol=http/protobuf \
-Dotel.traces.exporter=otlp \
-Dotel.resource.attributes=app.code=INSPUR-DZZW-BSP,deployment.environment=production,environment=production \
-Dotel.traces.sampler=parentbased_traceidratio \
-Dotel.traces.sampler.arg=0.1 \
-Dotel.logs.exporter=none \
```

**参数逐个解释：**

| 参数 | 作用 | 备注 |
|---|---|---|
| `-javaagent:...jar` | 加载链路 agent | 和 JMX agent 并存，互不影响 |
| `-Dotel.service.name=` | **服务名** | SigNoz「服务」页面按它分组 |
| `-Dotel.exporter.otlp.endpoint=` | **上报地址** | **注意是 4318，不是 4317** |
| `-Dotel.exporter.otlp.protocol=` | 传输协议 | `http/protobuf`（因为走 HTTP 端口） |
| `-Dotel.traces.exporter=otlp` | 链路用 OTLP 协议导出 | |
| `-Dotel.resource.attributes=` | 资源属性 | 打 `app.code` 等标签 |
| `-Dotel.traces.sampler=` | 采样器 | **必配！** |
| `-Dotel.traces.sampler.arg=0.1` | 采样比例 | **必配！** |
| `-Dotel.logs.exporter=none` | **关闭日志导出** | 见下 |

**⚠️ 三个关键点：**

**① endpoint 是 4318，不是 4317**

- `4317` = gRPC 协议（指标走这个）
- `4318` = HTTP 协议（链路走这个）

**为什么链路用 HTTP 而不是 gRPC？**

因为 bytecode 增强的 agent 在**应用进程内**运行，用 HTTP 实现更简单、依赖更少。而且**链路数据量大，用 HTTP 更容易做压缩和批处理**。

**如果填错端口会怎样？** agent 会尝试用 gRPC 连 4318，或者用 HTTP 连 4317，**握手失败，链路数据一条都上不去**。

**我们还踩过这个坑的另一面**：地址的**网络区域**搞错了（填了 A 区的 IP，但机器在 B 区）。现象是：

- 应用日志里**没有任何报错**（agent 是异步发送的，失败只记 debug 日志）
- SigNoz 里**一条链路都没有**
- 排查起来很费劲

**排查方法**：

```powershell
Test-NetConnection -ComputerName 192.168.140.60 -Port 4318
```

**看 `TcpTestSucceeded` 是不是 `True`。**

**② `-Dotel.logs.exporter=none` 为什么关掉日志**

**公司的配置生成器默认是 `-Dotel.logs.exporter=otlp`，也就是"把应用日志也发到平台"。**

**我把它改成了 `none`。为什么？**

因为**日志的数据量可能比链路还大**：

| 数据类型 | 数据量对比 |
|---|---|
| 链路（采样 10%） | 中等 |
| **日志（全量）** | **可能是链路的 5~10 倍** |

**看我们实际的应用日志：**

```
2026-09-28 10:26:03,305 DubboServerHandler-192.168.140.2:20882-thread-200 ERROR [FormServiceImp:306] 
-------formId is CongYeRenYuanJianKangJianChaBi formDataId is2026092810102831290020260928101028312900
java.lang.NullPointerException
2026-09-28 10:26:47,776 DubboServerHandler-192.168.140.2:20882-thread-200 ERROR [FormServiceImp:306] 
-------formId is CongYeRenYuanJianKangJianChaBi formDataId is2026092809312030880020260928093120308800
java.lang.NullPointerException
```

**注意时间戳**：10:26:03、10:26:47、10:26:59、10:27:06、10:27:10……

**平均每几秒就有一条 ERROR 日志！** 而且这个应用还在**不停报同一个错误**（`NullPointerException`）。

**如果把这些日志全量发到平台：**

```
每条日志约 500 字节
每天假设 5 万条 → 25 MB/天/应用
9 个应用 → 225 MB/天
```

**看起来还能接受。但问题是：**

1. **日志的增长是不可控的**——出问题时日志量可能瞬间放大 100 倍
2. **日志里可能含敏感信息**——身份证号、手机号、业务数据，发到监控平台有合规风险
3. **一期不需要**——我们当前的目标是"看清楚系统状态"，日志是二期的事

**所以决定：先关掉日志，专注链路和指标。** 等链路跑稳了，再单独开日志，并且要配好脱敏规则。

**③ 两个 `-javaagent` 的顺序**

**我们的顺序是**：先 JMX agent，后链路 agent。

```bash
-javaagent:jmx_prometheus_javaagent.jar=9999:config.yaml \
-javaagent:opentelemetry-javaagent.jar \
```

**这个顺序有关系吗？**

**技术上，两个 agent 互不干扰**（一个读 JMX 暴露 HTTP，一个做字节码增强）。**顺序不影响功能。**

**但有个实践建议**：**把 JMX agent 放前面。**

因为 JMX agent 是"只读"的（只读 JMX 数据），而链路 agent 会**修改字节码**（增强业务代码）。先加载只读的，能减少"增强过程影响 JMX 读取"的可能性。

**如果顺序反了出了怪问题，先试着换顺序。**

### 9.5 链路不走探针（重要的架构区别）

**再强调一次这个架构点**（第一章提过，这里展开）：

```
指标：应用/主机 → 探针采集 → 探针上报 4317 → 平台
链路：应用 agent → 直接上报 4318 → 平台     ← 不经过探针！
```

**为什么链路要直连平台？**

**① 数据量问题**

链路数据量是指标的几十倍。如果先发给探针，探针要：

- 接收（占用网络带宽）
- 缓冲（占用内存）
- 转发（又占用一次带宽）

**探针会变成瓶颈。**

**② 实时性问题**

链路数据是"请求驱动"的，高峰期瞬间产生大量数据。**经过探针中转会增加延迟。**

**③ 职责分离**

- 探针负责"定时采集"（pull 模式）
- 应用 agent 负责"实时推送"（push 模式）

**两种模式混在一个进程里，设计上不清晰。**

**⚠️ 这个区别带来的实际影响：**

1. **配置位置不同**：链路的上报地址在**应用启动参数**里，不在探针配置里
2. **排查路径不同**：
   - 指标不通 → 查探针（18888 端口的统计）
   - **链路不通 → 查应用日志和网络连通性**（探针帮不上忙）
3. **网络要求不同**：**应用服务器要能直接连平台的 4318**

**第 3 点特别重要。** 如果应用服务器和平台之间**有防火墙只放通了 4317**，那指标能上去、链路上去不。**这需要提前确认。**

### 9.6 验证链路是否成功

**链路验证比指标"玄"一点**，因为它**依赖有请求进来**。

**第一步：确认 agent 加载了（看应用启动日志）**

```powershell
Get-Content "D:\server\apache-tomcat-9.0.115-BSP\logs\catalina.2026-09-28.log" | Select-String "opentelemetry|otel"
```

**期望看到：**

```
[otel.javaagent 2026-09-28 13:39:52:839 +0800] [main] INFO io.opentelemetry.javaagent.tooling.VersionLogger 
- opentelemetry-javaagent - version: 1.16.0
```

**⭐ 看到 `version: 1.16.0` 就说明 agent 加载成功了。**

**注意这行日志出现的位置很有意思**：它在 Tomcat **停止**的时候打印的（因为我们执行 `shutdown.bat` 时，Java 进程启动 → 加载 agent → 打印版本 → 然后执行停止逻辑）。

**为什么？** 因为 Tomcat 的 `shutdown.bat` 也是启动一个 Java 进程，**这个进程也会加载 agent**。所以你在 shutdown 的输出里也能看到 agent 版本。

**第二步：确认启动参数生效（看 Tomcat 日志）**

Tomcat 启动时会打印所有 JVM 参数：

```powershell
Get-Content "D:\server\apache-tomcat-9.0.115-BSP\logs\catalina.2026-09-28.log" -Tail 300 | Select-String "Dotel.exporter.otlp.endpoint" | Select-Object -Last 1
```

**期望输出：**

```
28-Sep-2026 13:40:20.246 信息 [main] org.apache.catalina.startup.VersionLoggerListener.log 命令行参数：
 -Dotel.exporter.otlp.endpoint=http://192.168.140.60:4318
```

**⭐ 这一步能验证"地址改对了没有"。** 我们第一次就是靠这个发现有台机器的地址还是 A 区的。

**第三步：确认网络能通**

```powershell
Test-NetConnection -ComputerName 192.168.140.60 -Port 4318
```

**看这两个值：**

| 字段 | 期望值 | 含义 |
|---|---|---|
| `SourceAddress` | `192.168.140.x` | 本机用哪个网卡出去的 |
| `TcpTestSucceeded` | **`True`** | TCP 能连上 |

**`Test-NetConnection` 这个 cmdlet 的用法：**

| 参数 | 含义 |
|---|---|
| `-ComputerName` | 目标主机（IP 或域名） |
| `-Port` | 目标端口 |
| `-InformationLevel Quiet` | 只返回 True/False（适合写脚本） |

**⚠️ 一个小问题**：在 Windows Server 2012 R2 上，`Test-NetConnection` 会报一个无害的错误：

```
Find-NetIPsecRule : 无法将"Find-NetIPsecRule"项识别为 cmdlet...
```

**这是 2012 R2 的已知问题**（缺一个模块）。**结果照常输出，不影响判断。**

**嫌烦的话用 `-InformationLevel Quiet`：**

```powershell
Test-NetConnection -ComputerName 192.168.140.60 -Port 4318 -InformationLevel Quiet
```

**只输出 `True` 或 `False`，干净。**

**第四步：⭐ 触发业务请求（这一步最容易忘）**

**链路是"请求驱动"的——没人访问应用，就没有链路数据。**

**这是和指标最大的区别：**

| | 指标 | 链路 |
|---|---|---|
| 产生方式 | 探针定时采集 | **请求触发** |
| 有没有数据 | **一定有**（只要探针在跑） | **必须有请求才有** |

**我们第一次验证链路时，等了半天 SigNoz 里什么都没有，以为是配置错了。后来才想起来：这个应用当时没人在用！**

**所以验证链路，必须先"制造一点流量"：**

- 打开应用的页面，点几下
- 登录一下
- 查一条数据
- 提交一个表单

**怎么确认"真的产生流量了"？** 看应用的访问日志，或者直接在浏览器里操作一遍。

**第五步：去 SigNoz 看**

**「服务」页面**：应该出现你的 `service.name`。

**我们第一次成功时看到的：**

```
INSPUR-DZZW-BSP
INSPUR-DZZW-FORM
```

**「链路」页面**：应该能看到请求列表。

**我们第一次成功时看到的（真实数据）：**

| 时间 | 服务 | 操作 | 耗时 | 方法 | 状态 |
|---|---|---|---|---|---|
| 10:31:54.733 | `ONE-POLICY-MANAGE-CB` | `ResourceHttpRequestHandler.handleRequest` | 11.85ms | — | — |
| 10:31:54.705 | `ONE-POLICY-MANAGE-CB` | `/policymanage/**` | 41.37ms | GET | 200 |
| 10:31:51.891 | `ONE-POLICY-MANAGE-CB` | `/policymanage/**` | 18.66ms | GET | 200 |

**⭐ 这里有个"读数据"的技巧，值得学：**

**看到 `ResourceHttpRequestHandler.handleRequest` 这个操作名，说明什么？**

`ResourceHttpRequestHandler` 是 Spring MVC 里**专门处理静态资源文件**（js、css、图片）的处理器。

**所以这些链路是"加载页面静态文件"，不是"业务操作"。**

**为什么会有这种链路？** 因为当时测试的人只是在**刷新页面**，而刷新页面会产生大量的静态资源请求。

**这提示我们**：

> **想看"有价值的链路"，必须走一次真正的业务逻辑**（查询数据、提交表单），而不是刷新页面。

**真正的业务链路里，你会看到**：

- `SELECT ...` 这样的数据库 Span
- `SET/GET` 这样的 Redis Span
- HTTP 调用其他服务的 Span

**这些才是链路的真正价值所在。**

---

## 第十章 单应用接入标准流程（六步法）

把前面所有知识串起来，**接入一个新应用的标准流程**是这样：

```
第 0 步  摸清情况：有几个应用？怎么启动的？各叫什么名字？
   │
第 1 步  准备文件：两个 agent jar + 规则文件（每台机器只做一次）
   │
第 2 步  【应用侧】加 JMX agent → 重启 → 验证 9999 有数据
   │        ⚠️ 需要停机窗口
第 3 步  【探针侧】探针加一路抓取 → 重启探针 → 验证 0 失败
   │        ✅ 不用碰应用
第 4 步  【可选】加链路 agent → 再重启一次 → 验证服务和链路
   │        ⚠️ 需要采样率决策
第 5 步  收尾：补登记 + 记台账 + 观察数据量
```

### 第 0 步：摸清情况（别跳过）

**要查清三件事：**

| 查什么 | 命令 | 为什么要 |
|---|---|---|
| 有哪些 Java 应用 | `Get-CimInstance Win32_Process -Filter "Name='java.exe'"` | 别漏了，也别把 Nacos 这种中间件当业务应用 |
| 怎么启动的 | 看进程命令行 + 父进程 | **决定改哪个文件** |
| 叫什么名字 | 读 `constant.properties` / `auth.properties` | 决定 `service.name` 和 `app.code` |

**⚠️ 特别提醒：一定要区分"业务应用"和"中间件"。**

**Nacos 也是 Java 进程，但它是注册中心/配置中心，不是业务应用。**

**怎么区分？**

| 特征 | 业务应用 | 中间件 |
|---|---|---|
| 启动方式 | `-jar 业务名.jar` 或 Tomcat 部署 war | `nacos-server.jar`、`zookeeper` 等 |
| 有无 webapps | Tomcat 有多个 webapps | 一般没有 |
| 名字 | 有 `app.code` | 没有 |

**我们对这几类都做了明确标注**：

- ✅ 业务应用：BSP、Form、BPM、Schedule、DDGL、SXGL、DISK、QYSL、XZSP
- ❌ 中间件：Nacos、ZooKeeper、Redis、Memcached（单独按中间件监控）

### 第 1 步：准备文件

**每台机器需要的文件（放在 `D:\app\` 下）：**

```
D:\app\
├── jmx_prometheus\
│   ├── jmx_prometheus_javaagent-0.15.0.jar   (418240 字节)
│   └── config.yaml                            (4228 字节，精简规则)
└── opentelemetry-javaagent\
    └── opentelemetry-javaagent.jar            (13408423 字节)
```

**⚠️ 三个文件的字节数一定要核对！** 传半截的文件会导致莫名其妙的错误。

**核对方法：**

```powershell
Get-ChildItem "D:\app\jmx_prometheus\", "D:\app\opentelemetry-javaagent\" | Select-Object Name, Length
```

**期望输出：**

```
Name                                      Length
----                                      ------
config.yaml                                 4228
jmx_prometheus_javaagent-0.15.0.jar       418240
opentelemetry-javaagent.jar             13408423
```

**⭐ 为什么路径用 `D:\app\`？** 因为：

1. **不放在 Tomcat 目录里** —— 这样多个 Tomcat 可以共用一份 agent，不用每个都传一遍
2. **不放在 C 盘** —— 因为 C 盘经常空间紧张
3. **`app` 这个名字** —— 一看就知道是"放应用的公共依赖"

**Linux 上用 `/opt/app/`，逻辑一样。**

### 第 2 步：加 JMX agent

**① 先分配端口，并确认端口空闲**

```bash
# Linux
ss -lnt | grep ':9999 '

# Windows
netstat -ano | findstr ":9999 "
```

**`ss` 命令解释：**

| 参数 | 含义 |
|---|---|
| `-l` | listening，只看监听状态的 |
| `-n` | numeric，**用数字显示端口**（不加的话会尝试解析成服务名，比如 `9999` 可能显示成别的） |
| `-t` | tcp，只看 TCP |

**`netstat -ano` 解释：**

| 参数 | 含义 |
|---|---|
| `-a` | all，所有连接 |
| `-n` | numeric，数字显示 |
| `-o` | **显示进程号 PID**（重要，能定位是哪个进程占了端口） |

**`findstr ":9999 "` 里的空格很重要！**

- `findstr ":9999"` → 会匹配 `:99990`、`:19999` 等
- `findstr ":9999 "` → **只匹配端口号后面跟空格的**（netstat 输出里端口后面是空格或地址）

**空闲的话输出为空。**

**② 备份启动脚本**

```bash
cp -a restart.sh restart.sh.bak.$(date +%Y%m%d%H%M%S)
```

**③ 改脚本：加 `-javaagent` + 修 `pgrep` 模式**（见 8.6 节）

**④ 检查改动**

```bash
# 确认 agent 参数加上了
grep -c javaagent restart.sh     # 期望输出 1

# 看完整脚本
cat restart.sh

# 和备份对比（最直观）
diff -u restart.sh.bak.* restart.sh
```

**⑤ 重启应用**

**⑥ 验证（三条铁律）**

```bash
# ① 进程只有一个
ps -ef | grep '[o]ne-manage-1.0.0.jar'

# ② JMX 端口有数据
curl -s http://127.0.0.1:9999/metrics | grep -c '^jvm_'    # 期望 89 左右

# ③ 应用日志没报错
tail -50 /opt/server/manage/nohup.out
```

**⭐ `grep '[o]ne-manage'` 里的方括号是什么意思？**

这是 Linux 里**排除 grep 自己**的经典技巧。

**不加方括号会怎样？**

```bash
ps -ef | grep 'one-manage'
# 输出里会多出一行：
# root  12345  6789  0 10:00 pts/0  00:00:00 grep --color=auto one-manage
#                    ↑ 这是 grep 命令自己！
```

因为 `grep` 的命令行里也包含 `one-manage` 这个字符串，所以它把自己也匹配出来了。

**加方括号 `[o]ne-manage` 就解决了**：

- 正则 `[o]ne-manage` 匹配的是 `one-manage`
- 但 **grep 进程自己的命令行里是 `[o]ne-manage`**（带方括号的原始字符串）
- 所以它匹配不到自己

**这个小技巧非常实用**，写脚本时经常用到。

### 第 3 步：探针侧抓取（这部分不用碰应用）

**你只需要提供 4 个信息：**

| 信息 | 例子 |
|---|---|
| 服务器 IP | `*.*.*.112` |
| 服务编码 `service.name` | `INSPUR-DZZW-BSP` |
| 应用编码 `app.code` | `INSPUR-DZZW-BSP` |
| JMX 端口 | `9999` |

**然后生成配置 → 上传 → 重启探针 → 验证。**

**验证（三个数字）：**

```bash
curl -s http://127.0.0.1:18888/metrics | grep '^otelcol_receiver_accepted_metric_points'   # 多了一路
curl -s http://127.0.0.1:18888/metrics | grep '^otelcol_exporter_sent_metric_points'       # 等于接收之和
curl -s http://127.0.0.1:18888/metrics | grep '^otelcol_exporter_send_failed'              # 无输出
```

### 第 4 步：加链路 agent（可选）

**加参数 → 重启 → 触发业务请求 → 验证「服务」和「链路」。**

**⚠️ 必须先确认采样率和网络区域。**

### 第 5 步：收尾（最容易漏）

| # | 事项 | 说明 |
|---|---|---|
| 1 | **补登记** | `app.code` 不在公司清单里的，找应用负责人补 |
| 2 | **记台账** | 记下：IP / 应用 / 端口 / 服务编码 / 应用编码 / 接入日期 |
| 3 | **观察数据量** | 观察一天：链路每分钟多少条？磁盘增长多少？ |

**⭐ 台账模板（我们用的 CSV，20 列）：**

```csv
序号,IP,服务器类型,操作系统,架构,平台,配置文件,采集对象,主机标识,host.name,中间件,应用服务编码,JMX端口,探针托管方式,开机自启,部署状态,连通性验证,数据验证,巡检核对,备注
```

**为什么要有台账？**

1. **别人接手时能看懂**（你休假了，同事知道每台机器采了什么）
2. **巡检时有据可查**
3. **出问题时能快速定位**（"哦，这台机器的 JMX 端口是 9998，因为 9999 被 Jetty 占了"）

**台账的每一列都有意义**，比如 `JMX端口` 这列——半年后你看到某台机器是 9998，会想"为什么不是 9999"，一看 `备注` 列写着"9999 被 Jetty 占用"，就明白了。

---

## 第十一章 实战记录：5 台服务器、9 个应用

前面讲了"应该怎么做"，这一章讲"实际怎么做的"。

### 11.1 战果总览

| 服务器 IP | 主机名 | 应用数 | 应用编码 | 状态 |
|---|---|---|---|---|
| `*.*.*.112` | WIN-64FKLGNHKI9 | 2 | `INSPUR-DZZW-BSP`、`INSPUR-DZZW-FORM` | ✅ |
| `*.*.*.113` | WIN-44QOJ4RLAU0 | 4 | `INSPUR-DZZW-BPM`、`INSPUR-DZZW-TASK`、`INSPUR-DZZW-DISSYSTEM`、`INSPUR-DZZW-SXGL` | ✅ |
| `*.*.*.114` | WIN-GB4AGGI5P1L | 1 | `INSPUR-DZZW-DISK` | ✅ |
| `*.*.*.127` | WIN-SGH1TA25OHG | 1 | `INSPUR-DZZW-QYSL` | ✅ |
| `*.*.*.115` | WIN-JKJLPPSSRSE | 1 | `INSPUR-DZZW-XZSP` | ✅ |
| **合计** | | **9 个应用** | | |

**加上更早完成的 Linux 机器 `*.*.*.241`（`ONE-POLICY-MANAGE-CB`），一共 10 个应用。**

### 11.2 应用名对照表（这个表一定要留着）

**为什么需要这张表？** 因为**应用自己声明的名字，和业务上叫的名字，往往对不上**。

| 应用编码（平台里显示的） | 业务上叫什么 | 说明 |
|---|---|---|
| `INSPUR-DZZW-BSP` | BSP | 基础支撑平台 |
| `INSPUR-DZZW-FORM` | Form | 表单系统 |
| `INSPUR-DZZW-BPM` | BPM | 流程管理系统 |
| **`INSPUR-DZZW-TASK`** | **Schedule** | **定时任务系统**（注意：编码里是 TASK，不是 SCHEDULE） |
| **`INSPUR-DZZW-DISSYSTEM`** | **DDGL** | **调度管理系统**（注意：编码里是 DISSYSTEM） |
| `INSPUR-DZZW-SXGL` | SXGL | 事项管理系统 |
| `INSPUR-DZZW-DISK` | WebDisk | 网盘/文件管理系统 |
| `INSPUR-DZZW-QYSL` | QYSL | 企业设立并联审批平台 |
| `INSPUR-DZZW-XZSP` | XZSP | 行政审批系统 |
| `ONE-POLICY-MANAGE-CB` | one-manage | 一网通办管理端 |

**⭐ 重点说 `TASK` 和 `DISSYSTEM` 这两个。**

当时配置 Schedule 和 DDGL 时，看到平台上显示 `INSPUR-DZZW-TASK` 和 `INSPUR-DZZW-DISSYSTEM`，我的第一反应是："**这两个名字太不直观了，改成 `INSPUR-DZZW-SCHEDULE` 和 `INSPUR-DZZW-DDGL` 不是更好吗？**"

**但是不能改。** 因为：

1. 这两个名字是**从应用的配置文件里读出来的**，是应用自己声明的
   - `INSPUR-DZZW-TASK` 来自 `constant.properties` 的 `app.code=INSPUR-DZZW-TASK`
   - `INSPUR-DZZW-DISSYSTEM` 来自 `sso.properties` 的 `app.sso.app.code=INSPUR-DZZW-DISSYSTEM`
2. 应用在**连 ZooKeeper、做 SSO 单点登录**时，用的就是这两个名字
3. **如果你在监控平台上改成别的名字，就会和应用实际注册的名字对不上**，后面对账、排查都麻烦

**正确的处理方式是在文档/看板里加备注**：

```
INSPUR-DZZW-TASK        → Schedule（定时任务系统）
INSPUR-DZZW-DISSYSTEM   → DDGL（调度管理系统）
```

**这条经验很重要：**

> **监控平台上的标识，应该"跟随被监控对象"，而不是"你觉得哪个好看"。**

### 11.3 112：第一个吃螃蟹的（也是最折腾的）

**环境情况：**

- Tomcat × 3：`apache-tomcat-9.0.115-BSP`、`apache-tomcat-9.0.115-Form`、`Screen`
- ZooKeeper 3.8.4（**所有应用都依赖它**）
- Memcached 1.4.13
- JDK 1.8.0_131

**要接入的：BSP 和 Form。**

**端口分配：**

| 应用 | JMX 端口 |
|---|---|
| BSP | 9999 |
| Form | 9998 |

**过程：**

**① 摸底**

由于应用不是标准 Spring Boot，`app-discovery.ps1` 报告"目录内未找到配置里的 name/code"。手工查 `constant.properties`：

```
app.code=INSPUR-DZZW-BSP
app.code=INSPUR-DZZW-FORM
```

**② 建 `setenv.bat`**

两个 Tomcat 都没有 `setenv.bat`，新建。

**③ 重启时踩了第一个坑：`CATALINA_HOME` 未定义**

```powershell
& "D:\server\apache-tomcat-9.0.115-BSP\bin\shutdown.bat"
# 报错：The CATALINA_HOME environment variable is not defined correctly
```

**为什么？** 因为用 `&` 直接调用 bat 时，PowerShell 的**当前工作目录**不是 Tomcat 的 `bin` 目录，而 `shutdown.bat` 需要靠"自己所在的目录"来推导 `CATALINA_HOME`。

**解决办法：先 `Set-Location` 到 bin 目录，再用 `cmd /c` 执行。**

```powershell
Set-Location "D:\server\apache-tomcat-9.0.115-BSP\bin"
cmd /c shutdown.bat
Start-Sleep 10
cmd /c startup.bat
```

**为什么要用 `cmd /c` 而不是直接 `.\shutdown.bat`？**

- **`.bat` 文件本质是 cmd 的脚本**，不是 PowerShell 的脚本
- PowerShell 执行 `.bat` 时，是**启动一个 cmd 子进程**来跑它
- 用 `cmd /c` 是**显式地**这么干，行为更可控
- **`/c`** = 执行完就退出（`/k` = 执行完保留窗口）

**④ 第四个坑：`BindException`**

第一次重启后，JMX 端口起不来：

```
Caused by: java.net.BindException: Address already in use: bind
        at io.prometheus.jmx.shaded.io.prometheus.client.exporter.HTTPServer.<init>
        at io.prometheus.jmx.shaded.io.prometheus.jmx.JavaAgent.premain
FATAL ERROR in native method: processing of -javaagent failed
```

**报错解读：**

| 部分 | 含义 |
|---|---|
| `BindException: Address already in use` | **端口已被占用** |
| `HTTPServer.<init>` | JMX agent 想启动 HTTP 服务（监听 9999）时失败 |
| `processing of -javaagent failed` | **agent 加载失败** |
| `FATAL ERROR` | JVM **直接退出**（不是"继续跑但没监控"，是"整个应用起不来"） |

**原因**：`shutdown.bat` 没成功（因为 `CATALINA_HOME` 问题），**老进程还活着，占着 9999**。

**解决办法**：先确认端口空闲，再启动：

```powershell
# 看是谁占了 9999
netstat -ano | findstr ":9999 "

# 用 PID 反查进程
Get-Process -Id <PID>
```

**⑤ 第五个坑（最严重）：误杀 ZooKeeper**

**这个坑我要详细讲，因为影响最大。**

当时发现端口被占，我执行了：

```powershell
Stop-Process -Name java -Force
```

**注意：`-Name java` 会杀掉所有 Java 进程！**

**这台机器上的 Java 进程有：**

| 进程 | 是什么 |
|---|---|
| Tomcat × 3 | 业务应用 |
| **ZooKeeper × 2** | **中间件！** |

**结果：ZooKeeper 被杀，所有应用启动失败。**

**为什么 ZooKeeper 挂了，应用就起不来？**

因为**这些应用都依赖 ZooKeeper**：

- Dubbo 用 ZooKeeper 做**服务注册与发现**
- 应用启动时要**从 ZooKeeper 拉取配置和服务列表**
- ZK 不在 → 应用启动卡住/失败

**正确的杀进程方式：**

```powershell
# ✅ 方式一：只杀指定 PID
Stop-Process -Id 1234, 5678 -Force

# ✅ 方式二：按命令行过滤，只杀 Tomcat
Get-CimInstance Win32_Process -Filter "Name='java.exe'" | 
    Where-Object { $_.CommandLine -like "*tomcat*" } | 
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

# ✅ 方式三：按端口找进程（最精准）
$pid9999 = (netstat -ano | Select-String ":9999 .*LISTENING").ToString().Split()[-1]
Stop-Process -Id $pid9999 -Force

# ❌ 千万不要
Stop-Process -Name java -Force
```

**重启 ZooKeeper 时又踩了坑：ZK 数据文件损坏**

用 `zkServer.cmd start` 启动失败：

```
java.lang.NumberFormatException: For input string: "D:\server\zookeeper\...\zoo.cfg"
```

**这个错是因为 `start` 参数被当成了端口号**（ZK 的启动脚本参数解析有歧义）。**去掉 `start` 直接跑**：

```powershell
Set-Location "D:\server\zookeeper\apache-zookeeper-3.8.4-bin\bin"
.\zkServer.cmd
```

**然后报了一个更严重的错：**

```
java.io.IOException: Unreasonable length = 77959356
        at org.apache.jute.BinaryInputArchive.checkLength
        at org.apache.zookeeper.server.persistence.Util.readTxnBytes
        at org.apache.zookeeper.server.persistence.FileTxnSnapLog.restore
```

**报错解读：**

| 部分 | 含义 |
|---|---|
| `Unreasonable length = 77959356` | **读到一个"不合理的长度"（7700 万字节）** |
| `readTxnBytes` | **在读事务日志（transaction log）** |
| `FileTxnSnapLog.restore` | **在恢复数据快照** |

**为什么会这样？**

**因为 `kill -9`（强杀）导致正在写事务日志的 ZK 进程突然中断，日志文件写了一半，损坏了。**

**`kill -9` 的危险性**：它**不给进程任何清理的机会**（不能保存数据、不能关闭文件），直接杀掉。**对于数据库、ZooKeeper 这类会写日志的中间件，`kill -9` 是危险的。**

**正确的做法是"优雅停止"**：

```bash
# ZooKeeper
zkServer.sh stop

# Tomcat
shutdown.bat / shutdown.sh

# 万不得已才用 kill -9，而且要等优雅停止超时之后再杀
```

**解决办法：**

**由于 ZK 里存的只是"服务注册信息"（不是业务数据），可以清空数据目录重建：**

```powershell
# 1. 读取 ZK 的数据目录（从 zoo.cfg 里读）
$zooConfig = "D:\server\zookeeper\apache-zookeeper-3.8.4-bin\conf\zoo.cfg"
$dataDir = (Get-Content $zooConfig | Select-String "^dataDir").ToString().Split("=")[1].Trim()
Write-Host "ZK 数据目录: $dataDir"

# 2. 备份！（万一里面有重要数据）
$backupDir = "$dataDir.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
Copy-Item -Recurse -Path $dataDir -Destination $backupDir

# 3. 清空数据目录
Remove-Item "$dataDir\*" -Recurse -Force

# 4. 重新启动 ZK
Set-Location "D:\server\zookeeper\apache-zookeeper-3.8.4-bin\bin"
.\zkServer.cmd
```

**⭐ 这里的操作要点：**

1. **从 `zoo.cfg` 里读 `dataDir`，不要硬编码路径**（不同环境路径可能不同）
2. **先备份再清空**（`Copy-Item -Recurse`）
3. **文件复制比移动安全**（清了原目录，备份还在）

**清空后重新启动，ZK 正常了。应用也陆续起来了。**

**⑥ 链路不通：地址填错了**

应用起来后，JMX 指标正常，但 SigNoz 里**看不到任何链路**。

排查发现：

```powershell
Test-NetConnection -ComputerName *.*.*.238 -Port 4318
# 结果：TcpTestSucceeded : False     ← 不通！
```

**而 B 区地址是通的：**

```powershell
Test-NetConnection -ComputerName 192.168.140.60 -Port 4318
# 结果：TcpTestSucceeded : True      ← 通！
# SourceAddress : 192.168.140.2      ← 注意这个！
```

**⭐ 关键发现：`SourceAddress` 是 `192.168.140.2`。**

**虽然这台机器的"政务网 IP"是 `*.*.*.112`，但它实际走的是 B 区网络。**

**修正：把 4 个 `setenv.bat` 里的地址全改成 `192.168.140.60:4318`。**

```powershell
foreach ($dir in @("BSP", "Form")) {
    $file = "D:\Server\apache-tomcat-9.0.115 - $dir\bin\setenv.bat"
    (Get-Content $file) -replace 'http://*.*.*.238:4318', 'http://192.168.140.60:4318' | Set-Content $file
}
```

**改完重启，链路就上来了。**

**⑦ 最终验证结果**

```
接收器：hostmetrics 268 + memcached 22 + jmx_bsp 510 + jmx_form 510
导出器：otlp 1681
失败：  （无输出 = 0 失败）✅
```

**「服务」页面出现了 `INSPUR-DZZW-BSP` 和 `INSPUR-DZZW-FORM`。**

### 11.4 113：一口气接 4 个应用

**环境：**

- Tomcat × 4：`- BPM`、`- Schedule`、`- DDGL`、`- SXGL`
- ZooKeeper 3.8.4
- JDK 1.8.0_131

**端口分配：**

| 应用 | Tomcat 目录 | app.code | JMX 端口 |
|---|---|---|---|
| BPM | `apache-tomcat-9.0.115 - BPM` | `INSPUR-DZZW-BPM` | 9999 |
| Schedule | `apache-tomcat-9.0.115 - Schedule` | `INSPUR-DZZW-TASK` | 9998 |
| DDGL | `apache-tomcat-9.0.115 - DDGL` | `INSPUR-DZZW-DISSYSTEM` | 9997 |
| SXGL | `apache-tomcat-9.0.115 - SXGL` | `INSPUR-DZZW-SXGL` | 9996 |

**⭐ 注意 `app.code` 的三种来源：**

| 应用 | 从哪个文件读到 | 内容 |
|---|---|---|
| BPM | `constant.properties` | `app.code=INSPUR-DZZW-BPM` |
| Schedule | `constant.properties` | `app.code=INSPUR-DZZW-TASK` |
| DDGL | `sso.properties` | `app.sso.app.code=INSPUR-DZZW-DISSYSTEM` |
| SXGL | `constant.properties` | `app.code=INSPUR-DZZW-SXGL` |

**DDGL 是从 `sso.properties` 里读到的！** 所以**不能只查 `constant.properties`**，要多个文件都看看。

**最终验证结果：**

```
接收器：
  hostmetrics              1148
  prometheus/jmx_bpm        510
  prometheus/jmx_schedule   510
  prometheus/jmx_ddgl       510
  prometheus/jmx_sxgl       510
导出器：otlp（等于接收之和）
失败：（无输出 = 0 失败）✅
```

**⭐ 5 路接收器，说明 4 个应用 + 主机都采到了。这个"接收器路数"就是最直观的验证方式。**

### 11.5 114：网盘系统（应用没声明编码）

**环境：**

- 一个 Tomcat：`apache-tomcat-9.0.87-WebDisk`
- 里面 3 个 web 应用：`ROOT`、`WebDiskDemo`、`WebDiskServerDemo`

**问题：3 个应用都没有 `app.code`。**

翻遍了所有 `.properties` 文件，只看到 `app.conf=rc/xxx`（配置路径），**没有 `app.code` 或 `app.id`**。

**这家的框架和其他几家不一样。**

**决策：**

**按"一个 Tomcat = 一个应用"来做，统一叫 `INSPUR-DZZW-DISK`。**

**为什么不分 3 个？**

1. **3 个 web 应用在同一个 JVM 里** —— JVM 指标（内存、GC、线程）本来就是**共享的**，你分不出"这是 WebDiskDemo 的内存"还是"ROOT 的内存"
2. **JMX 端口也只能开一个**（在同一个 JVM 里）
3. **链路可以分开**（按 URL 路径区分 `/WebDiskDemo` 和 `/WebDiskServerDemo`），但 JVM 指标分不开

**所以用 1 个 service.name 最清晰。**

**⭐ 这个决策的思考过程值得记录：**

> **监控的粒度不能细于"技术边界"。**
>
> - 一个 JVM 里的多个 web 应用，**JVM 层面是一体的**（同一个堆、同一个 GC）
> - 硬要分成 3 个监控对象，只会产生 3 份一模一样的 JVM 指标，**没有增量信息**
> - **能在链路层面分开就够了**

**验证结果：**

```
接收器：hostmetrics 218 + prometheus/jmx_disk 204
失败：  （无输出）✅
```

### 11.6 127：端口冲突的处理

**环境：**

- Tomcat × 2：`apache-tomcat-9.0.87-QYSL`（要接）、`apache-tomcat-8.5.69-SGHD-CS`（不接）
- **Jetty（`java -jar start.jar jetty.port=9999`）** ← 注意这个！
- `es-1.0.0-SNAPSHOT.jar`（另一个 jar 应用）

**⭐ 关键发现：9999 端口已经被 Jetty 占用了。**

**这就是"端口规划"章节强调"先检查端口"的原因。**

**处理：QYSL 用 9998。**

**`app.code` 的来源：**

```powershell
Get-Content "...\Inspur.Dzzw.Base.EnterpriseFound\WEB-INF\classes\auth.properties"
```

```
app.id=INSPUR-DZZW-QYSL
app.secret=TYYCEFWX6A57L4YLOXOH
app.callback=http://10.17.48.58:8055/web/callback
```

**这次读对了**（`INSPUR-DZZW-QYSL` 和 Tomcat 目录名 `QYSL` 对得上）。

**⭐ 对比 115 的 XZSP，那里读到的 `app.id` 是错的（读到了 BSP 的值）。**

**所以每次都要"交叉验证"**：

> **把读到的编码，和 Tomcat 目录名、应用名对一下。对不上就要怀疑。**

**验证结果：**

```
接收器：hostmetrics 340 + prometheus/jmx_qysl 102
失败：  （无输出）✅
```

**⚠️ 一个观察：`jmx_qysl` 只有 102 个数据点，而 113 上的应用是 510。**

**为什么差这么多？**

因为 113 上的应用已经跑了半小时（累计了多次采集），而 QYSL 刚重启完（只采集了 1~2 次）。

**⭐ 这说明"数据点数量"是累计值，不能直接横向比较。** 看它"有没有在增长"才是关键。

### 11.7 115：行政审批系统

**环境：**

- Tomcat × 4：`- Parallel`、`- ACCEPT`、`- WebSite`、`- XZSP`（只接 XZSP）
- Nacos（中间件）
- JDK 1.8.0_181

**只接 XZSP**，其他三个不动（业务上还没到优先级）。

**⭐ 这里发现了一个重要的配置问题：**

```powershell
Get-Content "...\Inspur.Dzzw.WebApproval\WEB-INF\classes\auth.properties"
```

```
app.id=INSPUR-DZZW-BSP          ← 这是 BSP 的编码！
app.secret= ASMIQM5C8O64P9COLH6I
app.callback=http://localhost:8282/bsp/web/callback    ← 回调地址也是 bsp
```

**XZSP（行政审批）的配置里写着 BSP 的编码和回调地址。**

**这明显是"从 BSP 复制配置时没改干净"的历史遗留问题。**

**决策：不用这个值，改用 `INSPUR-DZZW-XZSP`**（从 Tomcat 目录名 `- XZSP` 推断）。

**验证结果：**

```
接收器：hostmetrics 340 + prometheus/jmx_xzsp 102
失败：  （无输出）✅
```

### 11.8 接入 9 个应用后的整体数据量

**指标方面：**

| 项 | 数据量 |
|---|---|
| 单应用 JMX 指标 | 61 个指标名，89 条序列 |
| 单机主机指标 | 约 200~300 个数据点/分钟 |
| 9 个应用合计 | 约 800 条序列 |
| 每分钟总数据点 | 约 4000~5000 个 |

**换算成存储：**

```
5000 个点/分钟 × 1440 分钟/天 = 720 万个点/天
每个点约 20 字节（压缩后）→ 约 144 MB/天
```

**一个月约 4.3 GB。完全可以接受。**

**链路方面（采样 10%）：**

**这个和业务请求量强相关**，必须实地观察。我们的做法是：

1. **第一天只开 1~2 个应用**，观察数据量
2. **确认平台无压力后，再逐步铺开**
3. **每个应用都从 10% 开始**

**⭐ 为什么不一次性全开？**

因为**链路的数据量是"不可预测"的**——它取决于业务请求量，而这个你事先不知道（特别是政府系统，流量有明显的时段性和季节性）。

**"先小范围试，再逐步铺开"是稳妥的做法。**

---

## 第十二章 踩坑全集（17 个坑）

把这次踩过的坑全部列出来。**每一个都是真金白银换来的。**

### 坑 1：按 IP 判断网络区域，结果全错

**现象**：链路数据一条都上不去，应用日志里**没有任何报错**。

**原因**：`*.*.*.x` 这个网段的机器，**实际出口是 `192.168.140.x`（B 区）**，不是它 IP 看起来的 A 区。

**教训**：

> **判断网络区域，不要看 IP，要看 `Test-NetConnection` 输出的 `SourceAddress`。**

**正确做法**：

```powershell
Test-NetConnection -ComputerName 192.168.140.60 -Port 4318
# 看两个值：
#   SourceAddress    → 本机用哪个网段出去的
#   TcpTestSucceeded → 能不能连上
```

### 坑 2：公司通配规则会导致数据量灾难

**现象**：还没发生（我提前拦住了）。

**如果用了会怎样**：单应用 2000+ 条时间序列，13 台机器 × 4 个应用 = 每天 1.5 亿个数据点，**ClickHouse 被拖垮**。

**教训**：

> **公司给的配置不一定适合你的环境。特别是"通配符"类配置，一定要估算数据量。**

### 坑 3：`tcpcheck` 在 0.88.0 里不存在

**现象**：配置校验失败。

```
Error: failed to get config: cannot unmarshal the configuration: 
* error decoding 'receivers': unknown type: "tcpcheck" for id: "tcpcheck/oracle"
```

**原因**：公司配置生成器按 0.150.1 生成，但 0.88.0 没有这个采集器。

**教训**：

> **装完采集器，第一件事是跑 `components` 看它到底支持什么。**

```bash
/opt/otelcol/otelcol-contrib components | grep -i tcpcheck
# 没有输出 = 不支持
```

### 坑 4：Windows 2012 R2 跑不了 0.150.1

**现象**：安装包解压后跑不起来。

**原因**：公司文档写"支持 Windows Server 2016/2019/2022"，**2012 R2 不在支持范围**。

**教训**：

> **装之前先对一下"公司文档支持的环境"和"你的实际环境"。**
>
> **对不上就提前找公司要，别装到一半才发现。**

### 坑 5：带点的标签名不能写在 `static_configs.labels`

**现象**：探针启动失败。

**原因**：0.88.0 的 prometheus 采集器不允许 `labels` 的 key 里含点号。

**解决**：改用 `attributes` 处理器。

**教训**：

> **"语法看起来对"不等于"这个版本支持"。**

### 坑 6：加参数后 `pgrep` 匹配失效（最阴险的坑）

**现象**：重启后出现两个进程，新的抢不到端口。

**原因**：`pgrep -f "java -jar xxx.jar"` 匹配不到 `java -javaagent:... -jar xxx.jar`。

**教训**：

> **凡是"按命令行匹配进程"的地方，加参数后一定要回头检查匹配模式。**
>
> **最稳的做法是匹配"不变的部分"（比如 jar 文件名）。**

### 坑 7：误杀 ZooKeeper 导致全线崩溃（最严重的坑）

**现象**：所有业务系统起不来，报 `Could not connect to ZooKeeper`。

**原因**：`Stop-Process -Name java -Force` 把所有 Java 进程都杀了，**包括 ZK**。

**教训**：

> **绝对不要用 `Stop-Process -Name java -Force`！**
>
> **一定要按 PID 或按命令行特征精确杀。**

**正确的杀进程方式**：

```powershell
# 按命令行特征过滤（推荐）
Get-CimInstance Win32_Process -Filter "Name='java.exe'" | 
    Where-Object { $_.CommandLine -like "*one-manage*" } | 
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

```bash
# Linux 上同理（pkill 也要小心）
kill -9 $(pgrep -f "one-manage-1.0.0.jar")
```

### 坑 8：`kill -9` 损坏了 ZooKeeper 的事务日志

**现象**：ZK 启动失败。

```
java.io.IOException: Unreasonable length = 77959356
        at org.apache.zookeeper.server.persistence.Util.readTxnBytes
```

**原因**：强杀时 ZK 正在写事务日志，文件写了一半。

**解决**：清空数据目录重建（先备份）。

**教训**：

> **对于会写日志的中间件（ZK、MySQL、Kafka…），要用"优雅停止"，不要 `kill -9`。**

### 坑 9：`BindException` —— 旧进程没杀干净

**现象**：

```
Caused by: java.net.BindException: Address already in use: bind
FATAL ERROR in native method: processing of -javaagent failed
```

**原因**：旧进程还在，占着 JMX 端口。

**教训**：

> **重启前先确认端口空闲。看到 `BindException` 就是"有东西占着端口"。**

**排查命令**：

```bash
# Linux
ss -lntp | grep ':9999 '

# Windows（-o 参数显示 PID）
netstat -ano | findstr ":9999 "
```

**⚠️ 特别注意**：JMX agent 的 `BindException` 会导致 **JVM 直接退出**（不是"应用起来了但没监控"）。**这是致命的**——应用直接不可用。

### 坑 10：删了 agent jar，应用下次重启就起不来

**现象**：误删了 `/opt/app` 目录。

- **当时没事**：应用还在跑（agent 已经加载到内存里了），9999 端口还在正常输出指标
- **定时炸弹**：应用**下次重启就会失败**，因为 JVM 找不到那个 jar

```
Error opening zip file or JAR manifest missing : /opt/app/jmx_prometheus/xxx.jar
```

**解决**：重新上传（对比 MD5 确认和原文件一致），**然后重启一次验证**。

**⭐ 为什么要"重启验证"？**

因为"文件传上去了" ≠ "应用能起来"。只有**真的重启一次**，才能证明恢复成功。

**我们的处理：**

1. 重新上传两个文件
2. 对比 MD5（`ac475ee988c8a52d2310f073e67aca61` 和原文件一致）
3. **重启一次**，确认：
   - 新进程起来了（PID 变了）
   - 进程数 = 1
   - 9999 端口有 89 个指标
   - 启动日志无报错
   - 探针侧发送 = 接收，0 失败

**教训**：

> **agent 的 jar 文件是"应用启动的必要条件"，不是"可选的外挂"。**
>
> **要像对待应用的配置文件一样对待它——不能删、不能移。**

### 坑 11：在 cmd 里敲 PowerShell 命令

**现象**：`'Get-Process' 不是内部或外部命令`。

**原因**：cmd 和 PowerShell 是两套命令体系。

**教训**：

> **看提示符：`C:\>` 是 cmd，`PS C:\>` 是 PowerShell。**

### 坑 12：`Out-File` 写 bat 文件编码错误

**现象**：bat 文件执行乱码或报错。

**原因**：PowerShell 5.1 的 `Out-File` 默认用 UTF-16 LE，cmd 不认。

**解决**：加 `-Encoding ASCII`。

**教训**：

> **在 Windows 上写脚本文件（.bat / .cmd），一定要注意编码。**

### 坑 13：CSV 台账里的逗号

**现象**：CSV 文件列数校验失败，某一行多了一列。

**原因**：备注里写了 `(采样10%,日志暂关)`，**中文里的英文逗号被 CSV 当成了列分隔符**。

**解决**：把英文逗号改成中文分号 `(采样10%；日志暂关)`。

**教训**：

> **CSV 的字段里如果含逗号，要么用引号包起来，要么换成别的符号。**
>
> **写中文备注时特别容易踩这个坑。**

**验证 CSV 列数的方法（PowerShell）：**

```powershell
$lines = Get-Content "台账.csv" -Encoding UTF8
$head = ($lines[0] -split ',').Count
$i = 0
foreach ($l in $lines) {
    $i++
    if ($i -eq 1) { continue }
    if (($l -split ',').Count -ne $head) {
        "行 $i 列数=" + ($l -split ',').Count
    }
}
"表头=$head 列"
```

### 坑 14：`load` scraper 在 Windows 上不可用

**现象**：`Error: scraper "load" is not supported on this platform`

**原因**：`load average` 是 Unix 特有概念。

**教训**：

> **跨平台配置要分平台测试。Linux 能跑 ≠ Windows 能跑。**

### 坑 15：链路是"请求驱动"的，没请求就没数据

**现象**：配置看起来都对，但 SigNoz 里一条链路都没有。

**原因**：**应用当时没人在用。**

**教训**：

> **验证链路之前，一定要先"制造流量"（打开页面、点几下、走一遍业务）。**
>
> **指标是定时采集的，一定有；链路是请求驱动的，必须有请求。**

### 坑 16：`ResourceHttpRequestHandler` 说明你只是在刷页面

**现象**：链路有了，但操作名全是 `ResourceHttpRequestHandler.handleRequest`。

**原因**：这是在加载静态资源（js/css/图片），不是业务操作。

**教训**：

> **想看有价值的链路，必须走真正的业务逻辑**（查询、提交），而不是刷新页面。
>
> **真正的业务链路里会有数据库 Span（`SELECT ...`）、Redis Span、HTTP 调用 Span。**

### 坑 17（额外）：应用配置里的编码可能是错的

**现象**：XZSP（行政审批）的 `auth.properties` 里写着 `app.id=INSPUR-DZZW-BSP`。

**原因**：从 BSP 复制配置时没改干净。

**教训**：

> **不要盲目相信配置文件里的值。**
>
> **要和 Tomcat 目录名、应用名交叉验证。对不上就要怀疑。**

---

## 第十三章 SigNoz 使用指南

数据采上来了，**怎么在平台上看**是另一门学问。

### 13.1 界面地图

SigNoz 左侧菜单的主要几项：

| 菜单 | 英文 | 看什么 | 数据来源 |
|---|---|---|---|
| **服务** | Services | 有哪些服务在跑 | **链路** |
| **链路** | Traces | 每次请求的调用树 | 链路 |
| **指标** | Metrics | 所有指标原始数据 | 指标 |
| **基础设施** | Infrastructure | 主机、K8s 集群 | 指标 |
| **仪表盘** | Dashboards | 自定义看板 | 指标 |
| **日志** | Logs | 应用日志 | 日志 |
| **告警** | Alerts | 告警规则 | 全部 |

**⚠️ 一个重要的认知：**

> **「服务」和「链路」页面是靠"链路数据"驱动的。**
>
> **如果你没装链路 agent（只装了 JMX），这两个页面就是空的！**

**我们遇到的困惑**：装完 JMX 后，有人问"**我的应用怎么在平台上找不到？**"

**答案**：因为它只有指标，没有链路。**去「指标」页面搜指标名能找到，但「服务」页面不会出现。**

**如果你想让应用出现在「服务」页面，就必须装链路 agent。**

### 13.2 看指标（最常用）

**路径**：左侧菜单 →「指标」

**操作**：

1. **搜索框输入指标名**（比如 `jvm_memory_bytes_used`）
2. **点「Add filter」加过滤条件**
3. **选 `service.name`，填你的服务编码**
4. **选时间范围**

**常用的 JVM 指标查询：**

| 想看什么 | 搜什么指标 |
|---|---|
| **JVM 内存使用** | `jvm_memory_bytes_used`（加 filter `area = heap`） |
| **堆内存上限** | `jvm_memory_bytes_max` |
| **GC 次数** | `jvm_gc_collection_seconds_count` |
| **GC 耗时** | `jvm_gc_collection_seconds_sum` |
| **线程数** | `jvm_threads_current` |
| **死锁线程** | `jvm_threads_deadlocked` |
| **已加载类** | `jvm_classes_loaded` |
| **进程 CPU** | `jvm_os_processcpuload` |
| **进程物理内存** | `process_resident_memory_bytes` |
| **运行时长** | `jvm_uptime_millis` |

**⭐ 一个实用技巧：`service.name` 的过滤条件支持多选。**

比如想看 113 上 4 个应用的内存对比：

```
service.name IN ('INSPUR-DZZW-BPM', 'INSPUR-DZZW-TASK', 'INSPUR-DZZW-DISSYSTEM', 'INSPUR-DZZW-SXGL')
```

**这样一张图就能对比 4 个应用的曲线**，很容易看出哪个应用内存涨得快。

**⭐ 另一个技巧：把"累计值"变成"速率"。**

像 `jvm_gc_collection_seconds_count` 是**累计值**（从启动到现在一共 GC 了多少次），直接看是一条一直上升的直线，**没有信息量**。

**要把它变成"每分钟 GC 次数"：**

在查询里用 `rate()` 函数：

```
rate(jvm_gc_collection_seconds_count[5m])
```

**`rate(...[5m])` 的含义**：过去 5 分钟内的**平均每秒增长率**。

**这样你就能看到"GC 频率的变化"**——突然飙升就说明有问题。

### 13.3 看服务

**路径**：左侧菜单 →「服务」

**这个页面列出所有有链路数据的服务**，每个服务显示：

| 列 | 含义 |
|---|---|
| **Service Name** | 服务名（就是你的 `service.name`） |
| **P99 Latency** | 99% 的请求在这个耗时内完成 |
| **Error Rate** | 错误率 |
| **Operations** | 每秒操作数（吞吐量） |

**⭐ P99 是什么？**

假设有 100 个请求，按耗时排序：

- **P50（中位数）** = 第 50 个请求的耗时（一半请求比它快）
- **P95** = 第 95 个请求的耗时（95% 的请求比它快）
- **P99** = 第 99 个请求的耗时（99% 的请求比它快）

**为什么看 P99 而不是平均值？**

**因为平均值会骗人。**

举例：100 个请求，99 个用了 10ms，1 个用了 5 秒。

```
平均值 = (99 × 10 + 5000) / 100 = 59.9ms     ← 看起来还行
P99    = 5000ms 左右                          ← 暴露了真相：有请求卡了 5 秒
```

**用户投诉的往往是"那一个慢请求"**，所以要看 P99 甚至 P999。

**怎么看**：点服务名进去，选「Operations」标签，能看到每个操作的 P50/P95/P99。

### 13.4 看链路

**路径**：左侧菜单 →「链路」

**这个页面列出所有被采集的请求**，每一行是一条 Trace。

**列表的列：**

| 列 | 含义 |
|---|---|
| **Timestamp** | 请求发生的时间 |
| **Service Name** | 哪个服务 |
| **Operation / Name** | 操作名（比如 `/approve/submit`） |
| **Duration** | 耗时 |
| **HTTP Method** | GET/POST 等 |
| **Status Code** | HTTP 状态码（200 成功、500 错误） |

**⭐ 最强大的功能：点进去看调用树。**

点任意一行，会展开这棵调用树：

```
POST /approve/submit                        3200ms
  ├─ ApprovalController.submit                15ms
  ├─ PermissionService.check                   8ms
  ├─ WorkflowService.startFlow              3100ms   ← 找最宽的那一段
  │    ├─ WorkflowDao.insertInstance        3050ms   ← 再往里找
  │    │    └─ INSERT INTO WF_INSTANCE      3040ms   ← 找到根因
  │    └─ MQService.send                      30ms
  └─ CacheService.clear                        5ms
```

**怎么看这棵树：**

1. **看缩进层级** —— 越往里缩，越是"被调用的子操作"
2. **看耗时** —— 父操作的耗时**包含**子操作的耗时
3. **找"最宽的那一段"** —— 那就是瓶颈
4. **看有没有红色/错误的 Span** —— 那是报错的地方

**⭐ 一个"读懂调用树"的技巧：**

**父 Span 的耗时 = 它自己的耗时 + 所有子 Span 的耗时。**

所以你要找的是：

- **"占了父 Span 大部分时间的那一个子 Span"** —— 那就是问题所在
- 上面例子里：`WorkflowService.startFlow` 占了 3100ms，而父 Span 是 3200ms，**说明瓶颈就在这里面**

**一层一层往下钻，直到找到最底层的那个慢操作。**

### 13.5 看主机

**路径**：左侧菜单 →「基础设施」→「主机」

**这个页面列出所有上报主机指标的主机**，左侧可以按筛选条件过滤：

| 筛选器 | 依据的属性 |
|---|---|
| 主机名 | `host.name` |
| **操作系统** | `os.type` |
| 部署环境 | `deployment.environment` |

**⭐ 这里踩过一个坑：**

**「操作系统」筛选栏一开始是空的，显示"未找到值"。**

**原因**：0.88.0 的 `resourcedetection` 处理器在 Windows 上**没有自动注入 `os.type` 属性**。

**解决**：在 `resource/host_inject` 处理器里**手工注入**：

```yaml
resource/host_inject:
  attributes:
    - key: os.type
      value: "windows"      # ← 手工写死
      action: upsert
```

**改完之后，「操作系统」筛选栏就有值了。**

**主机页面能看到：**

- CPU 使用率曲线
- 内存使用率曲线
- 磁盘 IO
- 网络流量
- 磁盘空间使用率

### 13.6 几个实用查询示例

**① 找出内存持续增长的应用（内存泄漏的信号）**

```
指标：jvm_memory_bytes_used
过滤：area = heap
分组：service.name
观察：看哪条曲线是"一直涨不降"的
```

**② 找出 GC 最频繁的应用**

```
指标：rate(jvm_gc_collection_seconds_count[5m])
分组：service.name
观察：哪条曲线最高
```

**③ 找出 P99 最慢的服务**

```
页面：服务
排序：按 P99 Latency 降序
```

**④ 找出错误率高的服务**

```
页面：服务
排序：按 Error Rate 降序
```

**⑤ 查看某个应用的所有指标**

```
指标页面，过滤：service.name = 'INSPUR-DZZW-BPM'
搜索框留空 → 会列出这个服务的所有指标名
```

**⭐ 第 5 个技巧特别有用**：**它能告诉你"这个服务到底有哪些指标"**。做看板之前，先用这个方法确认指标名，**避免用错名字做出一块空白面板**。

---

## 第十四章 合规与巡检：怎么保护自己

### 14.1 我们和公司文档的偏离（诚实清单）

这次实施，**大体上按公司文档做了，但有 4 处有意偏离**。我把它们列出来，**因为巡检时一定会被问**。

| # | 项目 | 公司文档要求 | 我们的做法 | 为什么 |
|---|---|---|---|---|
| 1 | **采集器版本** | v0.150.1 | **v0.88.0** | **2012 R2 跑不了 0.150.1** |
| 2 | **配置生成方式** | 用离线工具生成 | 脚本生成 + 手工调整 | 工具产出含 `tcpcheck`，0.88.0 没有 |
| 3 | **JMX 规则** | `pattern: ".*"` 通配 | 精简规则 | 通配会产生几千条序列，拖垮平台 |
| 4 | 运行环境标识 | 默认 `development` | `production` | 生产环境不该标 development |

**其余全部一致**：

- 安装目录（Linux `/opt/otelcol`、Windows `C:\otelcol`）✅
- Linux 用 systemd 托管、服务名 `otelcol-contrib`、开机自启 ✅
- 采集对象覆盖（主机/数据库/中间件/应用）✅
- 上报链路（OTLP → 平台）✅

### 14.2 为什么必须写一份《偏离说明》

**这不是"甩锅文档"，是"工作留痕"。**

**三个理由：**

**① 巡检时你是主动的**

巡检的人拿着文档来对，看到你的配置和文档不符，**第一反应是"你有问题"**。

**但如果你能立刻拿出一份文档说**："这里我们偏离了，原因是 X，我们做了 Y 验证，建议 Z 处理"——**你的角色就从"被检查者"变成了"问题发现者"**。

**② 公司需要知道这些约束**

公司写文档时，可能**根本不知道**客户的环境是 2012 R2、用的是浪潮的老框架。

**你不反馈，公司永远不知道**，下个版本还是这样。

**③ 半年后你自己也需要看**

半年后你可能会想"当时为什么用 0.88.0 来着？"——**有文档就不用重新推一遍。**

### 14.3 《偏离说明》应该包含什么

**我们写的那份，结构是这样的：**

```markdown
# 与公司文档的偏离说明（合规核对）

## 一、核对总表
（一张表：项目 / 文档要求 / 实际做法 / 判定 / 依据）

## 二、必须让公司答复的一条：采集器版本
（详细说明问题、代价量化、请示公司的三个选项）

## 三、建议在巡检前完成的三件事

## 附录 A：tcpcheck 不可用的实测证据
（附上报错原文和执行命令）

## 附录 B：JMX 规则精简前后对比
（附上实测数据）

## 附录 C：待确认的问题
## 附录 D：需补登记的服务清单
```

**⭐ 关键写作原则：**

| 原则 | 说明 |
|---|---|
| **附证据** | 每处偏离都附上"实测报错原文"或"实测数据" |
| **量化影响** | 不说"数据量会大"，说"估算 2000+ 条序列，13 台机器每天 1.5 亿个点" |
| **给出选项** | 不只说问题，要给"怎么办"的选项（A/B/C） |
| **不推卸责任** | 用"因环境限制做了调整"，不用"公司文档有问题" |

### 14.4 巡检前应该准备的三样东西

| # | 准备什么 | 内容 |
|---|---|---|
| 1 | **《偏离说明》** | 上面那份文档，**提前发给公司确认** |
| 2 | **《部署台账》** | 每台机器的：IP、应用、端口、编码、接入日期、备注 |
| 3 | **《应用名对照表》** | 服务编码 ↔ 业务名称的映射（因为 `TASK` 这种名字别人看不懂） |

**有了这三样，巡检基本不会被动。**

### 14.5 不存在的服务名单

**这些服务编码，不在公司《数字政府应用清单》的 57 条里**，：

| 服务器 | 应用 | app.code | service.name |
|---|---|---|---|
| *.*.*.112 | BSP | `INSPUR-DZZW-BSP` | `INSPUR-DZZW-BSP` |
| *.*.*.112 | Form | `INSPUR-DZZW-FORM` | `INSPUR-DZZW-FORM` |
| *.*.*.113 | BPM | `INSPUR-DZZW-BPM` | `INSPUR-DZZW-BPM` |
| *.*.*.113 | Schedule | `INSPUR-DZZW-TASK` | `INSPUR-DZZW-TASK` |
| *.*.*.113 | DDGL | `INSPUR-DZZW-DISSYSTEM` | `INSPUR-DZZW-DISSYSTEM` |
| *.*.*.113 | SXGL | `INSPUR-DZZW-SXGL` | `INSPUR-DZZW-SXGL` |
| *.*.*.114 | WebDisk | `INSPUR-DZZW-DISK` | `INSPUR-DZZW-DISK` |
| *.*.*.127 | QYSL | `INSPUR-DZZW-QYSL` | `INSPUR-DZZW-QYSL` |
| *.*.*.115 | XZSP | `INSPUR-DZZW-XZSP` | `INSPUR-DZZW-XZSP` |

**⭐ 补登记的注意事项：**

1. **不是"改个名字就行"** —— 要和应用负责人确认"这个系统应该用哪个编码"
2. **可能牵涉改应用配置** —— 如果确认要改编码，那应用自己的 `constant.properties` 也要改，**并且要重启**
3. **改完监控配置要跟着改** —— 探针配置里的 `service.name` 要同步更新

**所以，最省事的做法是"补登记"（在清单里加一条），而不是"改应用的编码"。**

---

## 第十五章 命令速查表

**这一章是"工具书"，用的时候直接翻。**

### 15.1 Linux 常用命令

**文件操作**

| 命令 | 作用 |
|---|---|
| `ls -la 目录` | 列出所有文件（含隐藏），长格式 |
| `mkdir -p 目录` | 创建目录（父目录不存在则一起创建，已存在不报错） |
| `cp -a 源 目标` | 复制并保留权限/时间 |
| `cp -r 目录1 目录2` | 递归复制目录 |
| `mv 源 目标` | 移动/重命名 |
| `rm -rf 目录` | **强制递归删除（危险！）** |
| `tar -zxvf 包.tar.gz -C 目录` | 解压到指定目录 |
| `diff -u 文件1 文件2` | 对比两个文件的差异 |
| `md5sum 文件` | 计算 MD5 |
| `chmod +x 文件` | 加可执行权限 |

**进程与服务**

| 命令 | 作用 |
|---|---|
| `ps -ef \| grep '[x]xx'` | 查进程（方括号排除 grep 自己） |
| `ps -eo pid,ppid,args` | 列出 PID、父 PID、完整命令 |
| `pgrep -f "关键字"` | **按完整命令行**找进程，返回 PID |
| `kill -9 PID` | 强制杀进程 |
| `systemctl start 服务` | 启动服务 |
| `systemctl stop 服务` | 停止服务 |
| `systemctl restart 服务` | 重启服务 |
| `systemctl status 服务` | 看服务状态 |
| `systemctl enable 服务` | 开机自启 |
| `systemctl daemon-reload` | **重新加载服务定义（新建服务后必须执行）** |
| `journalctl -u 服务 -n 50 --no-pager` | 看服务最后 50 行日志 |
| `journalctl -u 服务 -f` | 实时跟踪日志 |

**网络与端口**

| 命令 | 作用 |
|---|---|
| `ss -lntp` | 列出所有监听端口（含进程） |
| `ss -lnt \| grep ':9999 '` | 查特定端口 |
| `netstat -tunlp` | 同上（老系统可能只有 netstat） |
| `curl -s URL` | 发 HTTP 请求（-s 静默） |
| `curl -s URL \| grep 'xxx'` | 取内容并过滤 |
| `ping 目标` | 测连通性（但很多机器禁 ping） |
| `telnet 目标 端口` | 测端口（老工具） |

**文本处理**

| 命令 | 作用 |
|---|---|
| `grep '关键字' 文件` | 搜索 |
| `grep -c '关键字' 文件` | **只输出匹配的行数** |
| `grep -i '关键字'` | 忽略大小写 |
| `grep -v '关键字'` | **反向匹配（排除）** |
| `grep -E '正则'` | 用扩展正则 |
| `head -20 文件` | 前 20 行 |
| `tail -50 文件` | 后 50 行 |
| `tail -f 文件` | **实时跟踪（看日志神器）** |
| `wc -l` | 统计行数 |
| `sort -u` | 排序并去重 |
| `awk '{print $1}'` | 取第 1 列 |
| `sed 's/旧/新/g'` | 替换 |

### 15.2 Windows PowerShell 常用命令

**文件操作**

| 命令 | 作用 |
|---|---|
| `Test-Path "路径"` | **判断文件/目录是否存在** |
| `Get-ChildItem "目录" -Recurse` | 递归列目录（`ls` / `dir`） |
| `New-Item -Path "目录" -ItemType Directory -Force` | 建目录（`-Force` 相当于 `-p`） |
| `Copy-Item 源 目标` | 复制 |
| `Remove-Item "路径" -Recurse -Force` | 删除 |
| `Get-Content "文件"` | 读文件（`type` / `cat`） |
| `Get-Content "文件" -Tail 50` | 后 50 行 |
| `Get-Content "文件" \| Select-String "关键字"` | **搜索（相当于 grep）** |
| `Get-Content "文件" \| Select-String "关键字" -CaseSensitive:$false` | 忽略大小写 |
| `Get-Content "文件" \| Select-Object -First 5` | 前 5 行 |
| `Out-File -FilePath "文件" -Encoding ASCII` | 写文件（**注意编码**） |
| `Get-FileHash "文件" -Algorithm MD5` | 算 MD5 |
| `notepad "文件"` | 用记事本打开 |

**进程**

| 命令 | 作用 |
|---|---|
| `Get-Process -Name java` | 按名字查进程 |
| `Get-Process -Id 1234` | 按 PID 查进程 |
| `Get-CimInstance Win32_Process -Filter "Name='java.exe'"` | **查进程（能拿到命令行）** |
| `... \| Select-Object ProcessId,CommandLine \| Format-List` | 竖排显示进程信息 |
| `Stop-Process -Id 1234 -Force` | 按 PID 杀进程 |
| `Start-Process -FilePath "程序" -ArgumentList "参数"` | 启动程序 |
| `Start-Process -FilePath "cmd.exe" -ArgumentList "/k 脚本.bat"` | 启动 bat 脚本并保留窗口 |

**⚠️ 千万不要用 `Stop-Process -Name java -Force`（会杀掉所有 Java 进程，包括中间件）。**

**网络**

| 命令 | 作用 |
|---|---|
| `Test-NetConnection -ComputerName IP -Port 端口` | **测端口连通性（看 SourceAddress 和 TcpTestSucceeded）** |
| `Test-NetConnection ... -InformationLevel Quiet` | 只返回 True/False |
| `netstat -ano` | 所有连接（`-o` 显示 PID） |
| `netstat -ano \| findstr ":9999 "` | 查端口占用 |
| `Invoke-WebRequest -Uri URL -UseBasicParsing` | **发 HTTP 请求** |
| `(Invoke-WebRequest -Uri URL -UseBasicParsing).Content` | 取响应内容 |
| `(Invoke-WebRequest -Uri URL).StatusCode` | 取状态码 |

**其他**

| 命令 | 作用 |
|---|---|
| `Set-Location "目录"` | 切换目录（`cd`） |
| `Select-Object -Property 列1,列2` | 选列 |
| `Where-Object { $_.属性 -like "*关键字*" }` | 过滤行 |
| `ForEach-Object { ... }` | 对每个元素执行（`$_` 是当前元素） |
| `Measure-Object` | 统计（配合 `-Line`/`-Word` 用） |
| `Get-Service \| Where-Object { $_.Name -like "*otel*" }` | 查服务 |
| `Get-ChildItem ... \| Select-Object Name,Length` | 看文件大小 |

### 15.3 本项目的关键端口速查

| 端口 | 用途 | 谁用 |
|---|---|---|
| `4317` | OTLP gRPC | **探针上报指标** |
| `4318` | OTLP HTTP | **应用上报链路** |
| `18888` | 探针自身监控 | 查看探针运行状态 |
| `9999~9996` | JMX 指标 | 应用侧 agent 暴露 |
| `8086` | SigNoz Web | 你打开看的界面 |

### 15.4 三个地址速查

| 用途 | A 区 | B 区 |
|---|---|---|
| 指标上报（探针） | `*.*.*.238:4317` | `192.168.140.60:4317` |
| 链路上报（应用） | `*.*.*.238:4318` | `192.168.140.60:4318` |
| SigNoz 界面 | `http://*.*.*.238:8086` | 同左 |

**⚠️ 怎么判断用哪个？跑这个命令：**

```powershell
Test-NetConnection -ComputerName 192.168.140.60 -Port 4318
```

**`SourceAddress` 是 `192.168.140.x` → 用 B 区地址。**

### 15.5 验证"铁三角"（每次都要查）

```bash
# ① 接收（应有多路）
curl -s http://127.0.0.1:18888/metrics | grep '^otelcol_receiver_accepted_metric_points'

# ② 发送（应等于接收之和）
curl -s http://127.0.0.1:18888/metrics | grep '^otelcol_exporter_sent_metric_points'

# ③ 失败（应无输出）
curl -s http://127.0.0.1:18888/metrics | grep '^otelcol_exporter_send_failed'
```

**Windows 版本：**

```powershell
$content = (Invoke-WebRequest -Uri "http://127.0.0.1:18888/metrics" -UseBasicParsing).Content

Write-Host "=== 接收 ==="
$content -split "`n" | Where-Object { $_ -match "otelcol_receiver_accepted_metric_points" }

Write-Host "=== 发送 ==="
$content -split "`n" | Where-Object { $_ -match "otelcol_exporter_sent_metric_points" }

Write-Host "=== 失败（应为空）==="
$content -split "`n" | Where-Object { $_ -match "otelcol_exporter_send_failed" }
```

**⭐ 为什么用 `-split "\`n"` 而不是 `Select-String`？**

因为在 PowerShell 5.1 里，`Select-String` 处理从 `Invoke-WebRequest` 拿到的多行字符串时**有时匹配不到**（涉及行尾符的处理）。

**用 `-split` 手动拆成数组，再用 `Where-Object -match` 过滤，更可靠。**

**这个坑我们也踩过**：一开始用 `Select-String` 什么都搜不到，以为探针没数据，其实是匹配方式的问题。

---

## 结语：这次工作教会我的事

写了这么长，最后说几句"心得"。

### 一、文档和现实永远有差距

公司文档写"支持 Windows 2016/2019/2022"，但客户环境是 2012 R2。
文档写"JMX 规则用通配"，但通配会把平台打爆。
文档写"配置用工具生成"，但工具产出的配置在目标版本上跑不起来。

**这不是公司故意坑人**，而是**他们不知道你的实际情况**。

**所以做实施的人，价值就在于"把文档翻译成能跑的东西"。**

### 二、"看起来对"和"实际能跑"是两回事

- 配置语法看起来对 → 但版本不支持那个字段
- 端口分配看起来对 → 但被别的服务占了
- 网络地址看起来对 → 但实际路由走的是另一条线

**唯一可靠的办法是"实测"**：

- 配置要 `validate`
- 端口要 `netstat`
- 网络要 `Test-NetConnection`

**"我以为"是事故之源。**

### 三、备份是第一位的

这次改 `restart.sh` 之前先备份，改 `setenv.bat` 之前先备份，清空 ZK 数据目录之前先备份。

**没有任何一次备份是多余的。**

**而且备份要"带时间戳"**——因为你可能要改好几次，需要能回退到任意一个版本。

### 四、破坏性操作要格外小心

`Stop-Process -Name java -Force` 这一条命令，让我经历了整个项目里最紧张的半小时。

**凡是带 `Force`、`-f`、`-9`、`rm -rf` 的命令，执行前都要停下来想三秒：**

> **这会影响到哪些东西？还有谁在依赖它？**

**在动"共享资源"（ZooKeeper、Nacos、数据库）之前，一定要先查清楚"谁在用它"。**

### 五、数据量是监控系统的头号敌人

- **主机指标**：小
- **数据库指标**：小
- **应用 JMX 指标**：小（精简后 89 条）
- **链路**：**大**（和请求量成正比）
- **日志**：**最大**

**做监控规划时，"要采什么"和"采多少"是两个必须同时回答的问题。**

**只回答前一个，平台迟早会被打爆。**

### 六、监控的粒度不能细于技术边界

一个 JVM 里的多个 web 应用，JVM 指标是一体的，**硬要拆只会产生重复数据**。

**做监控设计时，要先问"这个边界技术上分得开吗"，再问"业务上需要分开吗"。**

### 七、标识要"跟随被监控对象"

应用自己叫 `INSPUR-DZZW-TASK`，你就得用这个名字，**不能因为"我觉得 SCHEDULE 更好看"就改**。

**改了之后，平台上的名字和应用在注册中心注册的名字对不上，后面对账就是一场灾难。**

**"统一、准确、可追溯"比"好看"重要一万倍。**

### 八、留痕很重要

- **台账**（每台机器采了什么）
- **偏离说明**（哪里和文档不一样、为什么）
- **应用名对照表**（编码和业务名怎么对应）
- **配置文件的头部注释**（这台机器当时有什么特殊情况）

**这些东西平时看着没用，巡检、交接、半年后回头看的时候，能救命。**

### 九、先小范围验证，再铺开

我们没有一次性给 13 台机器全配上链路，而是：

1. **先在一台机器上做通**（`*.*.*.241`，Linux）
2. **观察数据量**
3. **再铺到 112**（第一台 Windows）
4. **再一口气做 113（4 个应用）**
5. **最后收尾 114 / 127 / 115**

**每一步都验证，每一步都总结，每一步的坑都在下一步避免。**

**这就是为什么 112 花了最久（踩了所有坑），而 115 只花了半小时。**

---

## 附：这次工作的最终成果清单

**监控覆盖：**

| 层次 | 内容 | 状态 |
|---|---|---|
| ① 主机 | 13 台服务器（10 Windows + 3 Linux） | ✅ |
| ② 中间件/数据库 | Redis、Memcached、MySQL、Oracle | ✅ |
| ③ 应用（JMX） | 10 个 Java 应用 | ✅ |
| ④ 链路 | 10 个应用（采样 10%） | ✅ |
| ⑤ 日志 | 暂未接入（二期） | ⏸️ |

---

**如果这篇文章能帮你少踩一个坑，那文章就没白写。**

**祝你的监控项目顺利。**

