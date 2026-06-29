---
title: ADB安卓调试桥完整操作指南
date: 2026-06-29T10:00:00+08:00
categories:
  - 个人分享/技术分享
tags:
  - 工具
  - ADB
  - 安卓调试
  - 抓包
  - logcat
excerpt: ADB（Android Debug Bridge）是安卓开发与调试的核心工具。本文整理了ADB的安装配置、设备连接、日志抓取以及常见问题处理的全流程操作指南，方便在其他电脑上快速上手使用。
---

## 什么是ADB？

ADB（Android Debug Bridge，安卓调试桥）是一个命令行工具，用于电脑与安卓设备之间的通信。通过ADB，你可以安装应用、抓取日志、传输文件、执行shell命令等。

**核心文件说明：**

| 文件 | 作用 |
|------|------|
| `adb.exe` | ADB主程序 |
| `AdbWinApi.dll` | Windows平台API支持库 |
| `AdbWinUsbApi.dll` | Windows USB驱动支持库 |
| `fastboot.exe` | Fastboot刷机工具 |


## 下载 ADB 工具包

本文所需的 ADB 工具（adb.exe、fastboot.exe 等）已打包上传，读者可直接下载使用：

👉 [ADB 工具包下载](https://github.com/weidong-star/my-hugo-blok/releases/download/Blog/ADB.zip)

下载后解压到任意目录（例如 C:\adb-tools），即可按照下文步骤使用。

## 一、环境准备

### 1. 将ADB目录添加到系统PATH（可选，推荐）

将ADB文件夹路径添加到系统环境变量 `Path` 中，之后在任意位置打开CMD/PowerShell都能直接使用 `adb` 命令。

**步骤：**
1. 复制ADB文件夹路径（例如 `C:\adb-tools`）
2. 右键"此电脑" → 属性 → 高级系统设置 → 环境变量
3. 在系统变量中找到 `Path`，双击编辑
4. 新建，粘贴ADB文件夹路径，确定保存

### 2. 打开CMD并切换到ADB目录（临时方案）

如果不配置环境变量，每次使用时先 `cd` 到ADB文件夹：

```cmd
cd /d C:\adb-tools
```

> 注意：CMD窗口标题栏右键 → 属性 → 勾选"快速编辑模式"，可以方便地选中文字右键复制。

## 二、连接设备

### 1. 通过WiFi连接（网络ADB）

```cmd
adb connect 192.168.1.11
```

> 如果报错 `adb` 不是内部或外部命令，请先 `cd` 到你解压 ADB 工具的文件夹，或将其添加到系统 PATH（详见上方「一-1」）。

将 `192.168.1.11` 替换为目标设备的实际IP地址。默认端口为5555。

### 2. 如果连接失败——开放5555端口

先用USB线连接设备，然后执行：

```cmd
adb tcpip 5555
```

这条命令会重启设备上的ADB守护进程，使其监听5555端口。之后拔掉USB线，再用 `adb connect <IP>` 即可通过WiFi连接。

### 3. 查看已连接设备

```cmd
adb devices
```

输出示例：
```
List of devices attached
192.168.1.11:5555    device
```

- `device` —— 连接正常
- `offline` —— 设备未响应
- `unauthorized` —— 需要授权（设备上会弹出确认框）

## 三、抓取设备日志（Logcat）

这是最常用的功能之一，用于调试应用或排查设备问题。

### 基本抓包命令

```cmd
adb logcat -v time > .\logcat.log
```

参数说明：
- `-v time`：日志格式带时间戳，便于追踪
- `> .\logcat.log`：将日志输出重定向到当前目录的 `logcat.log` 文件
- 按 `Ctrl + C` 停止抓包

### 其他常用 logcat 参数

| 命令 | 说明 |
|------|------|
| `adb logcat -v time -s 标签名` | 只抓取指定标签的日志 |
| `adb logcat -v time *:E` | 只抓Error级别及以上的日志 |
| `adb logcat -c` | 清除日志缓冲区 |
| `adb logcat -v time -f /sdcard/log.txt` | 将日志保存在设备端 |

### 日志级别（由低到高）

- `V` — Verbose（详细，所有日志）
- `D` — Debug（调试）
- `I` — Info（信息）
- `W` — Warning（警告）
- `E` — Error（错误）
- `F` — Fatal（致命）

示例：只抓取Warning及以上级别日志
```cmd
adb logcat -v time *:W > .\logcat.log
```

## 四、多设备场景处理

当同时连接了多个设备时，直接使用 `adb` 命令会报错，提示有多个设备/模拟器。

### 解决方案：使用 `-s` 参数指定设备

先查看设备序列号：
```cmd
adb devices
```

输出示例：
```
List of devices attached
192.168.1.11:5555    device
emulator-5554        device
```

然后用 `-s` 指定目标设备：
```cmd
adb -s 192.168.1.11:5555 logcat -v time > .\logcat.log
```

> 所有ADB命令都可以加上 `-s <设备序列号>` 来指定操作哪个设备。

## 五、其他常用ADB命令

### 安装/卸载应用

```cmd
adb install app.apk              # 安装APK
adb install -r app.apk           # 覆盖安装（保留数据）
adb uninstall 包名                # 卸载应用
```

### 文件传输

```cmd
adb push 电脑文件路径 /sdcard/    # 推送文件到设备
adb pull /sdcard/文件路径 .\      # 从设备拉取文件到电脑
```

### Shell命令

```cmd
adb shell                        # 进入设备shell
adb shell pm list packages       # 列出所有已安装应用
adb shell dumpsys battery        # 查看电池信息
adb shell screencap /sdcard/screen.png  # 截屏
```

### 重启相关

```cmd
adb reboot                       # 重启设备
adb reboot bootloader            # 重启到Bootloader模式
adb reboot recovery              # 重启到Recovery模式
```

### Fastboot命令

```cmd
fastboot devices                 # 查看Fastboot设备
fastboot reboot                  # Fastboot模式下重启
fastboot flash recovery xxx.img  # 刷入Recovery镜像
```

## 六、常见问题排查

### 问题1：`adb connect` 提示 "cannot connect to ... 由于目标计算机积极拒绝"

**原因：** 设备的5555端口未开放。

**解决：** 先用USB连接设备，执行 `adb tcpip 5555`，然后拔掉USB再尝试WiFi连接。

### 问题2：`adb devices` 显示 `unauthorized`

**原因：** 设备端未授权此电脑的调试请求。

**解决：** 查看设备屏幕，会弹出"允许USB调试"的对话框，勾选"始终允许"后点击确定。

### 问题3：`adb: more than one device/emulator`

**原因：** 同时连接了多个设备。

**解决：** 使用 `adb -s <设备序列号>` 指定要操作的设备。

### 问题4：`adb` 不是内部或外部命令

**原因：** 未将ADB目录添加到PATH，且当前CMD不在ADB目录下。

**解决：** 
- 方案A：`cd /d C:\adb-tools` 切换到ADB目录再执行命令
- 方案B：将ADB目录添加到系统环境变量PATH中

### 问题5：Logcat日志乱码

**原因：** CMD编码问题。

**解决：** 在CMD中先执行 `chcp 65001` 切换为UTF-8编码。

## 七、完整操作流程总结

从零开始的完整抓包流程：

```cmd
# 1. 切换到ADB目录
cd /d C:\adb-tools

# 2. 连接设备（WiFi方式）
adb connect 192.168.1.11

# 3. 如果连接失败，先USB连接后开放端口
adb tcpip 5555
adb connect 192.168.1.11

# 4. 确认设备已连接
adb devices

# 5. 开始抓包
adb logcat -v time > .\logcat.log

# 6. 多设备时指定序列号
adb -s 192.168.1.11:5555 logcat -v time > .\logcat.log
```
