---

title: CentOS 安装 MySQL 终极指南：从 YUM 到离线包，总有一款适合你
date: 2025-05-19T16:00:00+08:00
# thumbnail: /images/blokImg/mysql.png
showComments: true
categories:
  - 个人分享/技术分享
tags: 
  - CentOS
  - MySQL
  - 数据库
  - 服务器配置
  - Linux
excerpt: 在CentOS系统上安装MySQL有多种方式，从官方YUM源到离线RPM包，再到二进制包。本文详细介绍三种主流安装方法，包含详细步骤和常见问题解决方案，帮助你在不同环境下成功部署MySQL数据库。
# show: false
---

## 前言

在 Linux 服务器上，MySQL 无疑是应用最广泛的关系型数据库。然而，对于许多初次接触 CentOS 的朋友来说，如何正确、干净地安装 MySQL 却是一个不大不小的挑战。是使用 `yum` 命令一键安装，还是去官网下载离线包？不同的方式有什么区别？

这篇指南将为你详细解析在 CentOS 7/8 系统上安装 MySQL 的三种主流方法，并附上每一步的详细操作指令和常见问题排查，无论你是新手还是老手，都能在这里找到最适合你的安装路径。

## 方法一：【强烈推荐】使用 MySQL 官方 YUM Repository

这是官方首推的安装方式，也是最省心、最不容易出错的方法。它能确保你安装的是官方发布的最新、最稳定的版本，并且可以方便地通过 `yum` 或 `dnf` 管理后续的更新。

**优点：**
  - 安装、升级、卸载都非常方便
  - 自动处理复杂的依赖关系
  - 与系统结合紧密，管理规范

**缺点：**
  - 需要全程联网

### 步骤 1: 安装 MySQL YUM 源

首先，我们需要告诉系统的包管理器（YUM/DNF）MySQL 官方仓库的地址。

**对于 CentOS 8 / RHEL 8:**
```bash
# 安装 MySQL 官方源的 RPM 包
sudo dnf install https://dev.mysql.com/get/mysql80-community-release-el8-1.noarch.rpm

# 检查是否安装成功
sudo dnf repolist enabled | grep "mysql.*-community.*"
```

**对于 CentOS 7 / RHEL 7:**
```bash
# 安装 MySQL 官方源的 RPM 包
sudo yum install https://dev.mysql.com/get/mysql80-community-release-el7-3.noarch.rpm

# 检查是否安装成功
sudo yum repolist enabled | grep "mysql.*-community.*"
```

### 步骤 2: (可选) 切换 MySQL 版本

官方源默认启用的是最新的 MySQL 版本（如 8.0）。如果你需要安装旧版本（如 5.7），需要手动切换。

**CentOS 8 (使用 dnf):**
```bash
# 查看所有可用的 MySQL 版本模块
sudo dnf module list mysql

# 禁用默认的 8.0 模块
sudo dnf module disable mysql

# 启用你想要的版本，例如 5.7
sudo dnf module enable mysql:5.7

# 验证一下当前启用的版本
sudo dnf module list mysql
```

**CentOS 7 (使用 yum-config-manager):**
```bash
# 如果没有 yum-config-manager, 先安装它
sudo yum install -y yum-utils

# 禁用默认的 8.0 源
sudo yum-config-manager --disable mysql80-community

# 启用你想要的 5.7 源
sudo yum-config-manager --enable mysql57-community

# 验证一下当前启用的源
yum repolist enabled | grep mysql
```

### 步骤 3: 安装 MySQL Server

配置好源之后，就可以像安装普通软件一样来安装 MySQL 了。

```bash
# CentOS 8
sudo dnf install mysql-community-server

# CentOS 7
sudo yum install mysql-community-server
```

### 步骤 4: 启动并初始化 MySQL

安装完成后，需要启动 MySQL 服务并进行基础的安全设置。

**启动 MySQL 服务:**
```bash
sudo systemctl start mysqld
```

**设置开机自启:**
```bash
sudo systemctl enable mysqld
```

**获取临时密码并进行安全设置:**

MySQL 8.0 在初始化时会为 root 用户生成一个临时密码。

```bash
# 找到临时密码
sudo grep 'temporary password' /var/log/mysqld.log

# 运行安全脚本，过程中会提示你输入临时密码，并设置新密码
sudo mysql_secure_installation
```

按照提示完成设置即可，包括设置新密码、删除匿名用户、禁止 root 远程登录等。

## 方法二：使用 RPM 包进行离线安装

如果你需要在内网或无法联网的环境中安装 MySQL，或者对版本有非常精确的要求，那么下载 RPM 包手动安装是最佳选择。

**优点：**
  - 完全离线，不依赖网络
  - 版本控制精确

**缺点：**
  - 需要手动下载，并处理可能的依赖问题
  - 升级相对繁琐

### 步骤 1: 下载 RPM Bundle

1. 访问 [MySQL Community Server 官方下载页面](https://dev.mysql.com/downloads/mysql/)
2. **Select Operating System:** 选择 Red Hat Enterprise Linux / Oracle Linux
3. **Select OS Version:** 根据你的 CentOS 版本选择 EL8 (x86, 64-bit) 或 EL7 (x86, 64-bit)
4. 在下载选项中，找到 **RPM Bundle** 并下载。这是一个 .tar 压缩包，包含了安装所需的所有核心 RPM 文件，可以避免我们手动解决依赖的麻烦。

### 步骤 2: 准备环境并安装

**上传并解压：**
将下载好的 .tar 文件上传到服务器，然后解压。

```bash
# 假设下载的文件是 mysql-8.0.x-1.el7.x86_64.rpm-bundle.tar
tar -xvf mysql-8.0.x-1.el7.x86_64.rpm-bundle.tar
```

**卸载冲突的包：**
CentOS 系统可能预装了 mariadb-libs，它会与 MySQL 的库文件冲突，需要先卸载。

```bash
sudo yum remove mariadb-libs
```

**安装 RPM 包：**
进入解压后的文件夹，使用 yum 或 dnf 的 localinstall 功能来安装所有 RPM 包，它可以自动处理这些包之间的依赖顺序。

```bash
# CentOS 8
sudo dnf localinstall mysql-community-*.rpm

# CentOS 7
sudo yum localinstall mysql-community-*.rpm
```

系统会提示你安装，输入 `y` 确认即可。

### 步骤 3: 启动并初始化

这一步与方法一的步骤 4 完全相同，请参考上文进行启动、获取临时密码和安全设置。

## 方法三：使用通用二进制包 (高手向)

这种方式类似 Windows 上的"绿色版"，提供了最大的灵活性，但配置也最为复杂，适合需要深度定制环境的数据库管理员（DBA）或高级用户。

**优点：**
  - 不污染系统目录，所有文件都在一个目录下
  - 可以在同一台服务器上轻松安装和运行多个不同版本的 MySQL 实例

**缺点：**
  - 配置极其繁琐，每一步都需要手动操作，容易出错

由于此方法步骤繁多且不适合大多数常规用户，这里只列出关键流程，具体请参考 MySQL 官方文档。

1. **下载：** 在官网下载 Linux - Generic 版本的二进制压缩包
2. **创建用户：** 创建一个专门运行 MySQL 的系统用户和组（如 mysql）
3. **解压：** 将压缩包解压到指定安装目录（如 /usr/local/mysql）
4. **创建数据目录：** 创建数据目录（如 /data/mysql）并授权给 mysql 用户
5. **编写配置文件：** 创建 my.cnf 文件，指定安装目录、数据目录、端口等核心参数
6. **初始化数据库：** 执行 `mysqld --initialize` 命令
7. **配置启动脚本：** 将 support-files/mysql.server 脚本复制到 /etc/init.d/ 并配置
8. **启动服务并设置密码**

## 常见问题 (FAQ)

### Q1: 安装时提示 mariadb-libs 冲突怎么办？

**A:** 这是因为系统自带的 MariaDB 库与 MySQL 冲突。在安装 MySQL 前，执行 `sudo yum remove mariadb-libs` 卸载它即可。

### Q2: MySQL 8.0 的密码策略太强，我想设置一个简单的密码怎么办？

**A:** 你可以在 `mysql_secure_installation` 过程中选择不启用密码验证插件（VALIDATE PASSWORD component）。如果已经安装，可以登录 MySQL 后执行以下命令修改：

```sql
-- 卸载密码验证插件
UNINSTALL COMPONENT 'file://component_validate_password';

-- 或者降低密码策略等级
SET GLOBAL validate_password.policy = LOW;
```

### Q3: 忘记了 root 密码怎么办？

**A:** 可以通过"跳过授权表"的方式来重置密码。

1. 编辑 `/etc/my.cnf`，在 `[mysqld]` 部分下添加 `skip-grant-tables`
2. 重启 MySQL 服务: `sudo systemctl restart mysqld`
3. 免密登录: `mysql -u root`
4. 执行 `FLUSH PRIVILEGES;` 然后 `ALTER USER 'root'@'localhost' IDENTIFIED BY 'YourNewPassword';`

> **重要：** 修改完后，务必删除 `/etc/my.cnf` 中添加的 `skip-grant-tables` 并重启 MySQL。

### Q4: 如何允许远程连接 MySQL？

**A:** 出于安全考虑，MySQL 默认只允许本地连接。要开启远程连接，你需要：

1. 确保你的云服务器或物理防火墙已经开放了 MySQL 的端口（默认为 3306）
2. 登录 MySQL，执行以下命令，将特定用户的访问权限从 localhost 改为 IP地址 或 % (任意地址)

```sql
-- 例子：允许 root 用户从任何 IP 地址连接
CREATE USER 'root'@'%' IDENTIFIED BY 'YourPassword';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
```

> **安全警告：** 在生产环境中，不建议直接对 root 用户开放所有 IP 的访问权限。最好是创建一个专用的用户，并限制其只能从特定的 IP 地址访问。

## 性能优化建议

### 1. 基础配置优化

```bash
# 编辑 MySQL 配置文件
sudo vim /etc/my.cnf

# 添加以下基础优化配置
[mysqld]
# 缓冲池大小（建议设置为内存的 70-80%）
innodb_buffer_pool_size = 1G

# 日志文件大小
innodb_log_file_size = 256M

# 连接数
max_connections = 200

# 查询缓存（MySQL 8.0 已移除）
# query_cache_size = 64M
```

### 2. 系统级优化

```bash
# 调整文件描述符限制
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf

# 调整内核参数
echo "vm.swappiness = 1" >> /etc/sysctl.conf
sysctl -p
```

### 3. 监控和维护

```bash
# 查看 MySQL 状态
sudo systemctl status mysqld

# 查看 MySQL 进程
ps aux | grep mysql

# 查看 MySQL 端口监听
netstat -tlnp | grep 3306

# 查看 MySQL 日志
sudo tail -f /var/log/mysqld.log
```

## 安全加固建议

### 1. 基础安全设置

```sql
-- 删除匿名用户
DELETE FROM mysql.user WHERE User='';

-- 删除测试数据库
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- 限制 root 用户只能本地登录
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
```

### 2. 创建专用用户

```sql
-- 创建专用数据库用户
CREATE USER 'appuser'@'%' IDENTIFIED BY 'StrongPassword123!';

-- 只授权必要的权限
GRANT SELECT, INSERT, UPDATE, DELETE ON myapp.* TO 'appuser'@'%';

-- 刷新权限
FLUSH PRIVILEGES;
```

### 3. 定期备份

```bash
# 创建备份脚本
sudo vim /usr/local/bin/mysql_backup.sh

#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backup/mysql"
mkdir -p $BACKUP_DIR

mysqldump -u root -p --all-databases > $BACKUP_DIR/full_backup_$DATE.sql

# 保留最近7天的备份
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete

# 设置执行权限
sudo chmod +x /usr/local/bin/mysql_backup.sh

# 添加到 crontab 定时执行
echo "0 2 * * * /usr/local/bin/mysql_backup.sh" | sudo crontab -
```

## 总结

对于绝大多数用户，**方法一（YUM/DNF）** 是安装和管理 MySQL 的最佳选择。它在便利性、稳定性和安全性之间取得了完美的平衡。只有在特殊的离线或定制化场景下，才需要考虑后两种方法。

### 选择建议

| 场景 | 推荐方法 | 原因 |
|------|----------|------|
| 生产环境 | YUM/DNF 安装 | 稳定、易维护、官方支持 |
| 内网环境 | RPM 包安装 | 离线、版本可控 |
| 开发测试 | YUM/DNF 安装 | 快速、便捷 |
| 多版本共存 | 二进制包安装 | 灵活、独立 |

### 安装后检查清单

  - [ ] MySQL 服务正常运行
  - [ ] 可以正常登录
  - [ ] 密码策略符合要求
  - [ ] 远程连接配置正确（如需要）
  - [ ] 基础安全设置完成
  - [ ] 备份策略已制定
  - [ ] 监控告警已配置

希望这篇指南能帮助你在 CentOS 上顺利地驾驭 MySQL！


> 💡 **提示**：如果遇到其他 MySQL 相关问题，欢迎联系：weidong_321@163.com 
