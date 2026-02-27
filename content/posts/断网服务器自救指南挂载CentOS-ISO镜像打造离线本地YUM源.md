---

title: 断网服务器自救指南：挂载 CentOS ISO 镜像，打造离线本地 YUM 源
date: 2024-12-19T18:00:00+08:00
# thumbnail: /images/blokImg/centos.png
categories:
  - 技术分享
tags:
  - CentOS
  - YUM
  - 离线安装
  - 服务器运维
  - Linux
excerpt: 在断网环境下如何安装软件？本文详细介绍如何通过挂载CentOS ISO镜像创建离线本地YUM源，让断网服务器也能正常使用yum命令安装软件，解决内网环境下的软件安装难题。
---

## 前言：为何需要本地 YUM 源？

在日常的 Linux 服务器运维中，`yum`（或 `dnf`）命令是我们安装、更新软件的得力助手。它通过连接互联网上的远程仓库（Repository），自动下载软件包并解决复杂的依赖关系。

但想象一下这些场景：
  - 你正在一个与外网物理隔离的**安全内网**中部署服务器
  - 你的服务器放置在没有网络连接的**机房或实验室**
  - 因为网络策略，服务器**无法访问外部 YUM 源**

在这些"断网"状态下，`yum` 命令会因为找不到可用的仓库而完全失效。怎么办？难道只能回到手动下载 RPM 包、再一个个解决依赖的"石器时代"吗？

当然不是！答案就藏在你安装系统时使用的那个 **CentOS ISO 镜像文件**里。这个镜像不仅包含了完整的操作系统，还自带了一个包含数千个常用软件包的仓库。我们只需要将它挂载到服务器上，并告诉 YUM："以后装软件，就从这个本地目录里找！"，问题就迎刃而解了。

这篇教程将手把手教你如何在 CentOS 7/8 系统上，通过挂载 ISO 镜像创建一个稳定、高效的离线本地 YUM 源。

## 准备工作

### 1. 获取 CentOS 的 ISO 镜像文件

首先，你需要一个与你服务器操作系统版本相匹配的 ISO 镜像文件。

**查看当前系统版本：**
在你的服务器上运行 `cat /etc/redhat-release` 来确认版本号，例如 `CentOS Linux release 7.9.2009 (Core)` 或 `CentOS Stream 8`。

**下载 ISO 镜像：**
由于 CentOS Linux 项目已经停止维护，推荐从官方的归档镜像站或国内的镜像源下载，速度更快。**通常下载 `DVD.iso` 版本**，因为它包含了最完整的软件包。

  - **阿里云开源镜像站 (推荐国内用户):**
  - **CentOS 归档:** [https://mirrors.aliyun.com/centos-vault/](https://mirrors.aliyun.com/centos-vault/)
  - **CentOS 7 (例如 7.9.2009):** [https://mirrors.aliyun.com/centos-vault/7.9.2009/isos/x86_64/](https://mirrors.aliyun.com/centos-vault/7.9.2009/isos/x86_64/)
  - **CentOS 8 (例如 8.5.2111):** [https://mirrors.aliyun.com/centos-vault/8.5.2111/isos/x86_64/](https://mirrors.aliyun.com/centos-vault/8.5.2111/isos/x86_64/)

  - **CentOS 官方归档镜像:**
  - **主页:** [https://vault.centos.org](https://vault.centos.org)
  - 你可以在这个站点上根据版本号逐级目录找到对应的 ISO 文件

  - **对于 CentOS Stream:**
  - **官网下载页:** [https://www.centos.org/centos-stream/](https://www.centos.org/centos-stream/)

下载完成后，你需要将这个 ISO 文件上传到你的服务器上，或者通过虚拟化平台的"挂载光盘"功能加载它。

### 2. 获取 Root 权限

以下所有操作都需要 `root` 用户或拥有 `sudo` 权限的用户来执行。

## 操作步骤

### 第一步：上传并挂载 ISO 镜像

首先，我们需要让服务器能够访问到 ISO 文件中的内容。这通过 `mount` 命令实现。

#### 1. 上传 ISO 文件

通过 SCP、FTP 或其他方式，将你的 CentOS ISO 文件上传到服务器的某个目录下，例如 `/opt/iso/`。

```bash
# 如果目录不存在，先创建
sudo mkdir -p /opt/iso
# (这里假设你已经通过其他方式把 ISO 文件放到了这个目录)
```

#### 2. 创建挂载点

挂载点就是一个空目录，我们将把 ISO 文件的内容"映射"到这个目录上。

```bash
sudo mkdir -p /mnt/cdrom
```

#### 3. 执行挂载

使用 `mount` 命令将 ISO 文件挂载到我们创建的挂载点。`-o loop` 参数是挂载 ISO 文件所必需的。

```bash
# 将下面的路径替换成你自己的 ISO 文件路径
sudo mount -o loop /opt/iso/CentOS-7-x86_64-DVD-2009.iso /mnt/cdrom
```

> **提示**：如果你使用的是虚拟机（如 VMware, VirtualBox），可以直接在虚拟机设置中将 ISO 文件作为虚拟光驱加载。这样，设备路径通常是 `/dev/cdrom` 或 `/dev/sr0`，挂载命令就变成了：
> `sudo mount /dev/cdrom /mnt/cdrom`

#### 4. 验证挂载

执行 `df -h` 或 `ls /mnt/cdrom`，如果你能看到 ISO 文件里的内容（如 `Packages`, `repodata` 等文件夹），说明挂载成功了。

```bash
df -h
# 或者
ls /mnt/cdrom
```

#### 5. (可选) 设置开机自动挂载

为了避免服务器重启后挂载失效，我们可以将其写入 `/etc/fstab` 文件。

```bash
# 在文件末尾添加一行，注意路径要正确
# 使用 nano 或 vim 打开 /etc/fstab
sudo nano /etc/fstab

# 添加以下内容 (路径请根据你的实际情况修改)
/opt/iso/CentOS-7-x86_64-DVD-2009.iso  /mnt/cdrom  iso9660  loop  0 0
```

### 第二步：配置本地 YUM 源文件

现在，我们需要告诉 YUM 系统，抛弃那些遥远的互联网仓库，转而使用我们本地的这个"宝库"。

#### 1. 备份并移动现有的 YUM 源配置

为了避免干扰，我们先把系统默认的、需要联网的 `.repo` 文件移走。

```bash
# 创建一个备份目录
sudo mkdir /etc/yum.repos.d/repo_bak

# 将所有默认的 repo 文件移入备份目录
sudo mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/repo_bak/
```

#### 2. 创建新的本地源配置文件

在 `/etc/yum.repos.d/` 目录下创建一个新的配置文件，名字可以任意取，但必须以 `.repo` 结尾。

```bash
sudo nano /etc/yum.repos.d/local.repo
```

#### 3. 编辑配置文件

将以下内容复制粘贴到 `local.repo` 文件中。请注意 `baseurl` 的路径必须指向你之前挂载的目录。

**对于 CentOS 7:**
```ini
[local-base]
name=CentOS-$releasever - Base - local
baseurl=file:///mnt/cdrom
gpgcheck=1
enabled=1
gpgkey=file:///mnt/cdrom/RPM-GPG-KEY-CentOS-7
```

**对于 CentOS 8:**
ISO 镜像中通常包含两个主要的仓库：`BaseOS` 和 `AppStream`。我们需要同时配置它们。

```ini
[local-baseos]
name=CentOS-$releasever - BaseOS - local
baseurl=file:///mnt/cdrom/BaseOS
gpgcheck=1
enabled=1
gpgkey=file:///mnt/cdrom/RPM-GPG-KEY-centosofficial

[local-appstream]
name=CentOS-$releasever - AppStream - local
baseurl=file:///mnt/cdrom/AppStream
gpgcheck=1
enabled=1
gpgkey=file:///mnt/cdrom/RPM-GPG-KEY-centosofficial
```

**配置说明：**
  - `[local-base]`：仓库的唯一ID
  - `name`：仓库的描述性名称
  - `baseurl`：**核心配置**，指向软件包的存放位置。`file://` 表示这是一个本地文件路径
  - `gpgcheck=1`：开启 GPG 密钥校验，确保软件包的完整性和安全性
  - `enabled=1`：启用这个仓库
  - `gpgkey`：指定 GPG 密钥文件的位置

### 第三步：清理缓存并验证

最后，我们来清理旧的 YUM 缓存，并让系统重新生成基于新配置的缓存。

#### 1. 清理 YUM 缓存

```bash
sudo yum clean all
```

#### 2. 生成新缓存

```bash
sudo yum makecache
```

如果一切顺利，你应该能看到系统正在从你的 `local` 源创建元数据缓存。

#### 3. 验证本地源是否生效

使用 `yum repolist` 命令查看当前可用的仓库列表。

```bash
sudo yum repolist
```

输出结果应该只显示你刚刚配置的本地仓库（如 `local-base`, `local-baseos` 等）。

#### 4. 尝试安装一个软件

现在，你可以像在联网状态下一样使用 `yum` 了！试试安装一个常用的工具，比如 `lrzsz` 或 `htop`。

```bash
sudo yum install -y lrzsz
```

如果能成功安装，恭喜你，你的离线本地 YUM 源已经搭建成功！

## 高级配置技巧

### 1. 创建完整的本地镜像

如果你需要更多的软件包，可以创建包含多个 ISO 的完整镜像：

```bash
# 创建镜像目录
sudo mkdir -p /opt/local-repo

# 复制 ISO 内容到本地目录
sudo cp -r /mnt/cdrom/* /opt/local-repo/

# 修改 repo 配置指向本地目录
sudo nano /etc/yum.repos.d/local.repo
```

### 2. 添加额外的软件包

你可以将额外的 RPM 包添加到本地源中：

```bash
# 创建自定义包目录
sudo mkdir -p /opt/local-repo/custom

# 复制 RPM 包到该目录
sudo cp *.rpm /opt/local-repo/custom/

# 创建仓库元数据
sudo createrepo /opt/local-repo/custom/

# 在 repo 配置中添加自定义源
sudo nano /etc/yum.repos.d/local.repo
```

添加以下内容：
```ini
[local-custom]
name=Custom Packages
baseurl=file:///opt/local-repo/custom
gpgcheck=0
enabled=1
```

### 3. 配置多个 ISO 源

如果你有多个版本的 ISO，可以配置多个源：

```bash
# 挂载多个 ISO
sudo mount -o loop /opt/iso/CentOS-7-x86_64-DVD-2009.iso /mnt/cdrom1
sudo mount -o loop /opt/iso/CentOS-7-x86_64-Everything-2009.iso /mnt/cdrom2

# 配置多个源
sudo nano /etc/yum.repos.d/local.repo
```

```ini
[local-base]
name=CentOS-7 - Base - local
baseurl=file:///mnt/cdrom1
gpgcheck=1
enabled=1
gpgkey=file:///mnt/cdrom1/RPM-GPG-KEY-CentOS-7

[local-everything]
name=CentOS-7 - Everything - local
baseurl=file:///mnt/cdrom2
gpgcheck=1
enabled=1
gpgkey=file:///mnt/cdrom2/RPM-GPG-KEY-CentOS-7
```

## 常见问题解决

### 问题1：挂载失败

**错误信息：** `mount: wrong fs type, bad option, bad superblock`

**解决方案：**
```bash
# 检查 ISO 文件是否完整
ls -lh /opt/iso/CentOS-*.iso

# 尝试不同的挂载选项
sudo mount -o loop,ro /opt/iso/CentOS-*.iso /mnt/cdrom

# 或者使用 iso9660 文件系统类型
sudo mount -t iso9660 -o loop /opt/iso/CentOS-*.iso /mnt/cdrom
```

### 问题2：YUM 源配置错误

**错误信息：** `Cannot find a valid baseurl for repo`

**解决方案：**
```bash
# 检查挂载点内容
ls -la /mnt/cdrom/

# 检查 repo 文件语法
sudo yum-config-manager --dump /etc/yum.repos.d/local.repo

# 重新生成缓存
sudo yum clean all
sudo yum makecache
```

### 问题3：GPG 密钥验证失败

**错误信息：** `GPG key retrieval failed`

**解决方案：**
```bash
# 临时禁用 GPG 检查
sudo yum install --nogpgcheck package-name

# 或者修改 repo 配置
sudo nano /etc/yum.repos.d/local.repo
# 将 gpgcheck=1 改为 gpgcheck=0
```

### 问题4：软件包依赖问题

**错误信息：** `Error: Package requires X but it is not installable`

**解决方案：**
```bash
# 查看可用包
sudo yum list available | grep package-name

# 查看包信息
sudo yum info package-name

# 使用 --skip-broken 跳过损坏的依赖
sudo yum install --skip-broken package-name
```

## 性能优化建议

### 1. 使用本地存储

将 ISO 内容复制到本地硬盘而不是直接挂载 ISO 文件：

```bash
# 复制到本地目录
sudo cp -r /mnt/cdrom/* /opt/local-repo/

# 修改 repo 配置指向本地目录
sudo nano /etc/yum.repos.d/local.repo
# 将 baseurl 改为 file:///opt/local-repo
```

### 2. 配置 YUM 缓存

```bash
# 编辑 YUM 配置
sudo nano /etc/yum.conf

# 添加或修改以下配置
[main]
cachedir=/var/cache/yum/$basearch/$releasever
keepcache=1
debuglevel=2
logfile=/var/log/yum.log
exactarch=1
obsoletes=1
gpgcheck=1
plugins=1
installonly_limit=3
```

### 3. 定期清理缓存

```bash
# 创建清理脚本
sudo nano /usr/local/bin/clean-yum-cache.sh

#!/bin/bash
# 清理过期缓存
yum clean all
# 保留最近 7 天的缓存
find /var/cache/yum -type f -mtime +7 -delete

# 设置执行权限
sudo chmod +x /usr/local/bin/clean-yum-cache.sh

# 添加到 crontab
echo "0 2 * * 0 /usr/local/bin/clean-yum-cache.sh" | sudo crontab -
```

## 安全注意事项

### 1. 文件权限控制

```bash
# 设置适当的文件权限
sudo chmod 755 /mnt/cdrom
sudo chown root:root /mnt/cdrom

# 保护 repo 配置文件
sudo chmod 644 /etc/yum.repos.d/local.repo
sudo chown root:root /etc/yum.repos.d/local.repo
```

### 2. 定期更新镜像

```bash
# 检查 ISO 文件的完整性
md5sum -c CentOS-*.iso.md5

# 定期验证软件包签名
sudo rpm --checksig /mnt/cdrom/Packages/*.rpm
```

### 3. 监控使用情况

```bash
# 查看 YUM 日志
sudo tail -f /var/log/yum.log

# 监控磁盘使用情况
df -h /mnt/cdrom
df -h /opt/local-repo
```

## 总结

通过挂载 ISO 镜像文件，我们成功地为一台离线服务器赋予了使用 `yum` 的能力。这个方法不仅解决了燃眉之急，而且非常稳定可靠，因为所有的软件包都来自于官方发行的镜像，安全性和兼容性都有保障。

### 配置检查清单

  - [ ] ISO 镜像文件已上传到服务器
  - [ ] ISO 镜像已成功挂载
  - [ ] 原有 YUM 源已备份
  - [ ] 本地源配置文件已创建
  - [ ] YUM 缓存已清理并重新生成
  - [ ] 本地源已通过测试安装验证
  - [ ] 开机自动挂载已配置（可选）

### 适用场景

| 场景 | 推荐配置 | 说明 |
|------|----------|------|
| 临时断网 | 直接挂载 ISO | 简单快速 |
| 长期离线 | 复制到本地目录 | 性能更好 |
| 多版本需求 | 配置多个源 | 灵活性高 |
| 生产环境 | 完整镜像 + 监控 | 稳定可靠 |

下次再遇到断网的服务器，不要再为如何安装软件而烦恼了。记住，你手中的那张系统光盘，就是一个功能完备的离线软件宝库！


> 💡 **提示**：如果遇到其他离线安装相关问题，欢迎联系：weidong_321@163.com 