---

title: Office下载以及激活教程
date: 2024-01-15T10:30:00+08:00
thumbnail: /images/blokImg/office.png
cover:
  image: "/images/blokImg/office.png"
featureimage: "images/blokImg/office.png"
categories:
  - 个人分享/工具分享
tags:
  - Office
  - 软件安装
  - 系统工具
excerpt: 详细介绍Office LTSC 2021版本的下载和激活流程，包括Office部署工具的使用、配置文件设置和KMS激活方法，帮助用户完成Office的安装和激活。
---

## 前言

本文将详细介绍如何下载和激活Microsoft Office，包括Office部署工具的使用、配置文件的设置以及KMS激活方法。请注意，本教程适用于Office LTSC 2021版本。

## 系统要求

在开始安装之前，请确保您的系统满足以下要求：

1. Windows 10或更高版本
2. 至少4GB RAM
3. 3.0GB可用硬盘空间
4. 管理员权限

## 下载和准备

### 1. 下载Office部署工具

1. 访问官方下载链接：[Office部署工具](https://www.microsoft.com/en-us/download/details.aspx?id=49117)
2. 在D盘创建名为"office"的文件夹
3. 下载并解压部署工具到此文件夹中

### 2. 创建配置文件

1. 访问[Office自定义工具](https://config.office.com/deploymentsettings)
2. 选择系统架构（32位或64位）
3. 在产品选择中，选择"Office LTSC 标准版 2021-批量许可证"
4. 在应用程序选择中，勾选需要的组件：
   - Microsoft Excel
   - Microsoft PowerPoint
   - Microsoft Word
   - Microsoft Outlook
5. 在语言选项中，选择"中文(简体)"
6. 点击右上角的"导出"按钮
7. 将配置文件命名为"config.xml"并保存到D:\office文件夹中

## 安装过程

### 1. 下载Office文件

1. 在D:\office文件夹中，按住Shift键并右键点击空白处
2. 选择"在此处打开PowerShell窗口"
3. 输入以下命令下载Office文件（此步骤可能需要较长时间）：
```powershell
.\setup.exe /download .\config.xml
```

### 2. 安装Office

在同一PowerShell窗口中，输入以下命令开始安装：
```powershell
.\setup.exe /configure .\config.xml
```

## 激活过程

### 1. 定位Office安装目录

1. 默认安装路径通常为：`C:\Program Files\Microsoft Office\Office16`
2. 如果找不到，可以在开始菜单中右键点击任意Office程序，选择"打开文件位置"

### 2. 激活Office

1. 以管理员身份运行PowerShell
2. 切换到Office16目录：
```powershell
cd "C:\Program Files\Microsoft Office\Office16"
```
3. 执行以下命令进行激活：
```powershell
cscript ospp.vbs /sethst:kms.03korg
cscript ospp.vbs /act
```

## 注意事项

1. 安装过程中请确保网络连接稳定
2. 如果已安装其他版本的Office，建议先完全卸载
3. 激活命令必须在管理员权限下运行
4. 如果激活失败，请检查：
   - 是否以管理员身份运行PowerShell
   - 网络连接是否正常
   - 是否正确进入Office16目录

## 常见问题解决

### 1. 安装失败
  - 确保系统满足最低配置要求
  - 检查硬盘剩余空间
  - 尝试清理临时文件后重新安装

### 2. 激活失败
  - 确认是否使用管理员权限
  - 检查网络连接
  - 确保使用了正确的KMS服务器地址

### 3. 配置文件错误
  - 重新访问Office自定义工具创建配置文件
  - 确保配置文件保存为XML格式
  - 检查配置文件内容是否完整

## 结语

完成以上步骤后，您的Office应该已经成功安装并激活。如果在使用过程中遇到任何问题，建议先检查以上提到的常见问题解决方案，如果问题仍然存在，可以查看Microsoft官方支持文档或寻求技术支持。
