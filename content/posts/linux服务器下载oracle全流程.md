---

title: CentOS无网络环境Oracle数据库安装完整指南
date: 2025-01-27T10:00:00+08:00
categories:
  - 个人分享/技术分享
tags:
  - Oracle
  - CentOS
  - 数据库
  - 离线安装
  - Linux运维
excerpt: 在无网络环境的CentOS服务器上安装Oracle数据库是一项复杂的任务。本文提供完整的离线安装流程，包括依赖包准备、环境配置、安装步骤和常见问题解决方案，帮助您成功部署Oracle数据库。
---

## 前言

在企业环境中，出于安全考虑，生产服务器通常不允许直接连接互联网。在这种情况下，如何在CentOS服务器上安装Oracle数据库成为了一个常见的技术挑战。本文将从零开始，详细介绍在无网络环境下安装Oracle数据库的完整流程。

## 环境准备

### 系统要求

**硬件要求：**
  - 内存：最少2GB，推荐8GB以上
  - 磁盘空间：至少10GB可用空间
  - CPU：支持64位架构

**操作系统要求：**
  - CentOS 7.x 或 CentOS 8.x（推荐CentOS 7.9）
  - 内核版本：3.10或更高
  - 文件系统：支持大文件（如ext4、xfs）

### 网络环境准备

**有网络环境需要下载的文件：**

1. **Oracle数据库安装包**
   - Oracle Database 19c Enterprise Edition
   - Oracle Database 12c Release 2 Enterprise Edition
   - 根据需求选择合适的版本

2. **系统依赖包**
   - 基础开发工具包
   - 图形界面支持包
   - 系统库文件

3. **传输工具**
   - U盘或移动硬盘
   - 网络传输工具（如scp、rsync）

## 详细安装流程

### 第一步：系统环境检查

在开始安装前，需要检查系统环境是否满足Oracle的要求。

```bash
# 检查系统版本
cat /etc/redhat-release

# 检查内核版本
uname -r

# 检查内存大小
free -h

# 检查磁盘空间
df -h

# 检查CPU架构
uname -m
```

### 第二步：系统依赖包准备

**在有网络的环境中下载以下RPM包：**

```bash
# 创建下载目录
mkdir -p /tmp/oracle-deps
cd /tmp/oracle-deps

# 基础开发工具
yumdownloader --resolve gcc gcc-c++ make binutils compat-libcap1 compat-libstdc++-33

# 图形界面支持
yumdownloader --resolve libX11 libXau libXi libXtst libgcc libnsl libstdc++ libxcb

# 系统库文件
yumdownloader --resolve glibc glibc-devel libaio libaio-devel libXext

# 其他必要包
yumdownloader --resolve ksh numactl numactl-devel smartmontools sysstat

# 下载所有依赖包
yumdownloader --resolve $(cat /tmp/oracle-deps/package-list.txt)
```

**创建完整的依赖包列表：**

```bash
# 创建依赖包列表文件
cat > /tmp/oracle-deps/package-list.txt << 'EOF'
gcc
gcc-c++
make
binutils
compat-libcap1
compat-libstdc++-33
glibc
glibc-devel
libaio
libaio-devel
libX11
libXau
libXi
libXtst
libgcc
libnsl
libstdc++
libxcb
libXext
ksh
numactl
numactl-devel
smartmontools
sysstat
unzip
wget
EOF
```

### 第三步：系统用户和组创建

```bash
# 创建Oracle用户和组
groupadd oinstall
groupadd dba
groupadd oper

# 创建Oracle用户
useradd -g oinstall -G dba,oper oracle

# 设置Oracle用户密码
passwd oracle

# 创建Oracle安装目录
mkdir -p /u01/app/oracle/product/19.3.0/dbhome_1
mkdir -p /u01/app/oraInventory
mkdir -p /u01/app/oracle/oradata
mkdir -p /u01/app/oracle/fast_recovery_area

# 设置目录权限
chown -R oracle:oinstall /u01/app
chmod -R 775 /u01/app
```

### 第四步：系统参数配置

**编辑系统配置文件：**

```bash
# 编辑limits.conf文件
cat >> /etc/security/limits.conf << 'EOF'
oracle soft nproc 2047
oracle hard nproc 16384
oracle soft nofile 1024
oracle hard nofile 65536
oracle soft stack 10240
oracle hard stack 32768
EOF

# 编辑sysctl.conf文件
cat >> /etc/sysctl.conf << 'EOF'
# Oracle数据库内核参数
kernel.shmmax = 68719476736
kernel.shmall = 4294967296
kernel.shmmni = 4096
kernel.sem = 250 32000 100 128
net.ipv4.ip_local_port_range = 9000 65500
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048576
fs.aio-max-nr = 1048576
fs.file-max = 6815744
EOF

# 应用内核参数
sysctl -p
```

### 第五步：环境变量配置

**为Oracle用户配置环境变量：**

```bash
# 切换到Oracle用户
su - oracle

# 编辑.bash_profile文件
cat >> ~/.bash_profile << 'EOF'
# Oracle环境变量
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=$ORACLE_BASE/product/19.3.0/dbhome_1
export ORACLE_SID=orcl
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
EOF

# 重新加载环境变量
source ~/.bash_profile
```

### 第六步：离线安装依赖包

**将下载的RPM包传输到目标服务器：**

```bash
# 在有网络的服务器上打包依赖文件
cd /tmp
tar -czf oracle-deps.tar.gz oracle-deps/

# 传输到目标服务器（使用U盘或其他方式）
# 在目标服务器上解压
tar -xzf oracle-deps.tar.gz -C /tmp/

# 安装所有依赖包
cd /tmp/oracle-deps
rpm -ivh *.rpm --nodeps --force
```

### 第七步：Oracle安装包准备

**下载Oracle安装包：**

在有网络的环境中，从Oracle官网下载以下文件：
  - `LINUX.X64_193000_db_home.zip`（Oracle Database 19c）
  - `LINUX.X64_193000_client.zip`（Oracle Client，可选）

**传输和准备安装包：**

```bash
# 在目标服务器上创建安装目录
mkdir -p /tmp/oracle-install
cd /tmp/oracle-install

# 解压Oracle安装包
unzip LINUX.X64_193000_db_home.zip -d /tmp/oracle-install/

# 设置安装包权限
chown -R oracle:oinstall /tmp/oracle-install/
chmod -R 755 /tmp/oracle-install/
```

### 第八步：图形界面配置

**配置X11转发（如果使用SSH连接）：**

```bash
# 在客户端启用X11转发
ssh -X oracle@server_ip

# 或者使用VNC
# 安装VNC服务器
yum install -y tigervnc-server

# 启动VNC服务
vncserver :1

# 设置DISPLAY环境变量
export DISPLAY=:1
```

**或者使用无图形界面安装：**

```bash
# 创建响应文件进行静默安装
cat > /tmp/oracle-install/db_install.rsp << 'EOF'
oracle.install.responseFileVersion=/oracle/install/rspfmt_dbinstall_response_schema_v19.0.0
oracle.install.option=INSTALL_DB_SWONLY
ORACLE_HOSTNAME=localhost
UNIX_GROUP_NAME=oinstall
INVENTORY_LOCATION=/u01/app/oraInventory
SELECTED_LANGUAGES=en
ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
ORACLE_BASE=/u01/app/oracle
oracle.install.db.InstallEdition=EE
oracle.install.db.OSDBA_GROUP=dba
oracle.install.db.OSOPER_GROUP=oper
oracle.install.db.OSBACKUPDBA_GROUP=dba
oracle.install.db.OSDGDBA_GROUP=dba
oracle.install.db.OSKMDBA_GROUP=dba
oracle.install.db.OSRACDBA_GROUP=dba
oracle.install.db.rootconfig.configMethod=ROOT
oracle.install.db.rootconfig.sudoPath=/usr/bin/sudo
oracle.install.db.rootconfig.sudoUserName=root
EOF
```

### 第九步：执行Oracle安装

**使用图形界面安装：**

```bash
# 切换到Oracle用户
su - oracle

# 启动Oracle安装程序
cd /tmp/oracle-install/database
./runInstaller
```

**使用静默安装：**

```bash
# 切换到Oracle用户
su - oracle

# 执行静默安装
cd /tmp/oracle-install/database
./runInstaller -silent -responseFile /tmp/oracle-install/db_install.rsp -ignorePrereq
```

### 第十步：数据库配置

**创建数据库响应文件：**

```bash
cat > /tmp/oracle-install/dbca.rsp << 'EOF'
responseFileVersion=/oracle/assistants/rspfmt_dbca_response_schema_v19.0.0
gdbName=orcl
sid=orcl
databaseConfigType=SI
policyManaged=false
createServerPool=false
initParams=undo_tablespace=UNDOTBS1,sga_target=2GB,processes=300
sampleSchema=false
memoryPercentage=40
databaseType=MULTIPURPOSE
automaticMemoryManagement=FALSE
totalMemory=2048
EOF
```

**创建数据库：**

```bash
# 使用DBCA创建数据库
dbca -silent -createDatabase -responseFile /tmp/oracle-install/dbca.rsp
```

### 第十一步：配置监听器

**创建监听器配置文件：**

```bash
cat > $ORACLE_HOME/network/admin/listener.ora << 'EOF'
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1521))
    )
  )

SID_LIST_LISTENER =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = orcl)
      (ORACLE_HOME = /u01/app/oracle/product/19.3.0/dbhome_1)
      (SID_NAME = orcl)
    )
  )
EOF

# 启动监听器
lsnrctl start
```

## 常见问题及解决方案

### 问题1：依赖包冲突

**现象：** 安装RPM包时出现依赖冲突

**解决方案：**
```bash
# 强制安装，忽略依赖
rpm -ivh package.rpm --nodeps --force

# 或者使用yum localinstall
yum localinstall package.rpm --nogpgcheck
```

### 问题2：内存不足

**现象：** 安装过程中提示内存不足

**解决方案：**
```bash
# 增加swap空间
dd if=/dev/zero of=/swapfile bs=1M count=2048
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# 永久添加swap
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

### 问题3：图形界面无法显示

**现象：** 无法启动图形安装界面

**解决方案：**
```bash
# 检查DISPLAY变量
echo $DISPLAY

# 设置DISPLAY变量
export DISPLAY=:0

# 或者使用VNC
vncserver :1
export DISPLAY=:1

# 或者使用静默安装
./runInstaller -silent -responseFile response_file.rsp
```

### 问题4：权限问题

**现象：** 安装过程中出现权限错误

**解决方案：**
```bash
# 检查目录权限
ls -la /u01/app/

# 重新设置权限
chown -R oracle:oinstall /u01/app/
chmod -R 775 /u01/app/
```

### 问题5：端口被占用

**现象：** 监听器无法启动，端口1521被占用

**解决方案：**
```bash
# 检查端口占用
netstat -tlnp | grep 1521

# 杀死占用进程
kill -9 process_id

# 或者修改监听器端口
# 编辑listener.ora文件，修改PORT为其他端口
```

### 问题6：字符集问题

**现象：** 数据库创建后出现字符集错误

**解决方案：**
```bash
# 检查当前字符集
sqlplus / as sysdba
SELECT * FROM NLS_DATABASE_PARAMETERS WHERE PARAMETER='NLS_CHARACTERSET';

# 修改字符集（需要重新创建数据库）
# 在dbca.rsp中设置正确的字符集参数
```

## 安装后配置

### 配置自动启动

**创建Oracle服务脚本：**

```bash
cat > /etc/systemd/system/oracle-rdbms.service << 'EOF'
[Unit]
Description=Oracle RDBMS
After=network.target

[Service]
Type=forking
User=oracle
Group=oinstall
Environment=ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
Environment=ORACLE_SID=orcl
ExecStart=/u01/app/oracle/product/19.3.0/dbhome_1/bin/dbstart $ORACLE_HOME
ExecStop=/u01/app/oracle/product/19.3.0/dbhome_1/bin/dbshut $ORACLE_HOME
TimeoutSec=0

[Install]
WantedBy=multi-user.target
EOF

# 启用服务
systemctl daemon-reload
systemctl enable oracle-rdbms
```

### 配置防火墙

```bash
# 开放Oracle端口
firewall-cmd --permanent --add-port=1521/tcp
firewall-cmd --reload

# 或者关闭防火墙（不推荐生产环境）
systemctl stop firewalld
systemctl disable firewalld
```

### 性能优化

**编辑Oracle参数文件：**

```bash
# 连接到数据库
sqlplus / as sysdba

# 修改内存参数
ALTER SYSTEM SET sga_target=2G SCOPE=SPFILE;
ALTER SYSTEM SET pga_aggregate_target=1G SCOPE=SPFILE;
ALTER SYSTEM SET processes=300 SCOPE=SPFILE;

# 重启数据库使参数生效
SHUTDOWN IMMEDIATE;
STARTUP;
```

## 验证安装

### 基本连接测试

```bash
# 本地连接测试
sqlplus / as sysdba

# 远程连接测试
sqlplus system/password@localhost:1521/orcl

# 检查数据库状态
SELECT status FROM v$instance;
```

### 性能测试

```bash
# 检查数据库性能
SELECT name, value FROM v$sysstat WHERE name IN ('user commits', 'user rollbacks');

# 检查表空间使用情况
SELECT tablespace_name, bytes/1024/1024 MB FROM dba_data_files;
```

## 总结

在无网络环境下安装Oracle数据库是一项复杂但可行的任务。通过充分的准备工作、正确的依赖包管理和详细的安装步骤，可以成功在CentOS服务器上部署Oracle数据库。

**关键成功因素：**
1. 完整的依赖包准备
2. 正确的系统参数配置
3. 合适的安装方式选择
4. 详细的错误排查和解决

**建议：**
  - 在生产环境部署前，建议在测试环境完整演练一遍
  - 保留所有安装日志，便于问题排查
  - 建立完整的备份和恢复策略
  - 定期更新和维护系统补丁

通过本文的详细指导，您应该能够在无网络环境下成功安装和配置Oracle数据库。
