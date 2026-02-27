---

title: 本地部署Ollama+deepseek，安装可视化工具，并修改ollama部署位置
date: 2025-02-10T14:51:22+08:00
thumbnail: /images/blokImg/ollama.png
cover:
  image: "/images/blokImg/ollama.png"
featureimage: "images/blokImg/ollama.png"
categories:
  - 个人分享/技术分享
tags:
  - Deepseek
  - ollama 
---

## 目录
  - [介绍](#介绍)
  - [安装步骤](#安装步骤)
  - [安装 Ollama](#安装-ollama)
  - [下载 Deepseek R1](#下载-deepseek-r1)
  - [安装可视化界面](#安装可视化界面)
  - [修改Ollama部署位置](#修改ollama部署位置)
  - [常见问题与解决方案](#常见问题与解决方案)

## 介绍

**DeepseekR1** 是中国深度求索公司推出的开源AI推理模型，通过强化学习与思维链技术实现高性能推理能力，尤其在数学、编程等复杂任务中表现卓越，且以极低成本对标OpenAI同类产品，支持离线运行和多场景应用。

**Ollama** 是一个开源的本地AI模型服务，它允许用户在本地运行各种AI模型，并提供了一个简单的API来与这些模型进行交互。Ollama的设计目标是提供一个轻量级、高效的解决方案，以便用户可以在自己的设备上运行各种AI模型，而无需依赖外部的云服务。

**cherry** 是一个基于Ollama的AI助手，它提供了一个简单的API来与Ollama进行交互，并且可以使用Ollama的各种模型来进行推理。cherry的设计目标是提供一个简单易用的解决方案，以便用户可以快速地使用Ollama的各种模型来进行推理。


## 安装步骤

### 安装 Ollama

1. 下载安装包：
   - 通过 <a href="https://ollama.com" target="_blank">Ollama官网</a> 下载 Windows 安装器
   - 如果无法访问，可以通过 [点击下载Navicat激活工具](http://wdblok.vip/upload/navicat激活使用全流程.zip) 下载
   > **注意**：这是 Windows 版本，如果需要 Linux 或 macOS 版本，请访问官网下载

2. 安装过程：
   - 下载完成后，按照默认选项安装即可
   - 安装完成后，打开终端，输入以下命令验证安装：
   ```bash
   ollama -V
   ```
如果安装成功，会输出ollama的版本号；

### 下载 Deepseek R1

1. 访问 <a href="https://ollama.com/library/deepseek-r1" target="_blank">Deepseek模型库</a> 选择合适的模型。

2. 可用模型列表：

| 模型名称 | 参数量 | 显存要求 | 运行命令 |
|---------|--------|---------|-----------|
| DeepSeek-R1-Distill-Qwen | 1.5B | 2GB+ | ```ollama run deepseek-r1:1.5b``` |
| DeepSeek-R1-Distill-Qwen | 7B | 8GB+ | ```ollama run deepseek-r1:7b``` |
| DeepSeek-R1-Distill-Llama | 8B | 8GB+ | ```ollama run deepseek-r1:8b``` |
| DeepSeek-R1-Distill-Qwen | 14B | 16GB+ | ```ollama run deepseek-r1:14b``` |
| DeepSeek-R1-Distill-Qwen | 32B | 32GB+ | ```ollama run deepseek-r1:32b``` |
| DeepSeek-R1-Distill-Llama | 70B | 64GB+ | ```ollama run deepseek-r1:70b``` |

3. 选择模型时的注意事项：
   - 确保你的显卡显存满足要求
   - 参数量越大，推理能力越强，但资源消耗也越大
   - 建议先从小模型开始尝试
#### 进入命令行，输入以下命令即可开始使用：
4. 运行示例：
```bash
# 运行 1.5B 模型（适合入门尝试）
ollama run deepseek-r1:1.5b

# 运行 7B 模型（性能与资源的平衡选择）
ollama run deepseek-r1:7b
```
显示sussess，即表示模型下载成功。
就可以与模型开始对话。
如果想退出对话，可以输入
```bash
/bye
```
如果想重新进入对话的话，可以输入
```bash
ollama list
```
命令行会展示出来当前你电脑安装的所有模型。复制你刚才的模型名称，再输入
```bash
ollama run deepseek-r1:7b
```
然后在此对话即可。

### 安装可视化界面

目前有多种可视化工具可以与Ollama配合使用，以下介绍几种常用的选择：

#### 1. ChatBox

1. 访问 <a href="https://chatboxai.app/zh" target="_blank">ChatBox官网</a> 下载适合你系统的版本
2. 安装完成后，打开ChatBox应用
3. 在设置中添加Ollama服务：
   - 点击左下角的设置图标
   - 选择「模型提供商」
   - 添加Ollama服务，地址填写 `http://localhost:11434`
   - 保存设置
4. 在聊天界面选择Ollama下的模型即可开始对话

#### 2. Open WebUI

1. 确保已安装Node.js环境
2. 打开终端，执行以下命令：
```bash
npx open-webui
```
3. 安装完成后，浏览器会自动打开 `http://localhost:3000`
4. 首次使用需要设置密码
5. 在设置中添加Ollama服务地址 `http://localhost:11434`

#### 3. Cherry

1. 访问 <a href="https://github.com/Cherryhqh/Cherry" target="_blank">Cherry GitHub仓库</a>
2. 下载最新版本的安装包
3. 安装完成后，打开Cherry应用
4. 在设置中配置Ollama服务地址为 `http://localhost:11434`
5. 选择已下载的模型开始对话

> **提示**：这些可视化工具都提供了更友好的用户界面，支持历史记录保存、多会话管理等功能，比命令行交互更加方便。

## 修改Ollama部署位置

默认情况下，Ollama会将模型文件存储在用户目录下，占用系统盘空间。如果你的系统盘空间有限，可以按照以下步骤修改Ollama的部署位置：

### Windows系统修改方法

1. 首先停止Ollama服务：
   - 在系统托盘中右键点击Ollama图标
   - 选择「退出」
   - 或者在任务管理器中结束Ollama进程

2. 创建环境变量：
   - 右键「此电脑」，选择「属性」
   - 点击「高级系统设置」
   - 点击「环境变量」
   - 在「系统变量」部分，点击「新建」
   - 变量名填写：`OLLAMA_MODELS`
   - 变量值填写你想存储模型的路径，例如：`D:\Ollama\models`

3. 创建目标文件夹：
   - 确保你已创建了上一步指定的文件夹

4. 迁移现有模型（如果有）：
   - 将 `C:\Users\用户名\.ollama\models` 目录下的文件复制到新位置

5. 重启Ollama服务

### Linux/macOS系统修改方法

1. 停止Ollama服务：
```bash
sudo systemctl stop ollama    # 对于使用systemd的系统
# 或
killall ollama               # 其他系统
```

2. 设置环境变量：
```bash
export OLLAMA_MODELS=/path/to/your/models
```

3. 将此环境变量添加到启动文件中：
```bash
echo 'export OLLAMA_MODELS=/path/to/your/models' >> ~/.bashrc
# 或
echo 'export OLLAMA_MODELS=/path/to/your/models' >> ~/.zshrc
```

4. 迁移现有模型：
```bash
mkdir -p /path/to/your/models
cp -r ~/.ollama/models/* /path/to/your/models/
```

5. 重启Ollama服务：
```bash
sudo systemctl start ollama    # 对于使用systemd的系统
# 或手动启动
ollama serve
```

> **注意**：修改部署位置后，确保新位置有足够的存储空间，并且当前用户对该位置有读写权限。

## 常见问题与解决方案

### 1. 模型下载失败

**问题**：运行 `ollama run` 命令时，模型下载失败或速度极慢。

**解决方案**：
  - 检查网络连接，确保能够访问Ollama服务器
  - 尝试使用代理或VPN
  - 可以手动下载模型文件，然后放置到模型目录中

### 2. 显存不足

**问题**：运行大模型时提示显存不足。

**解决方案**：
  - 选择参数量更小的模型
  - 增加系统虚拟内存
  - 使用量化版本的模型，如添加 `:q4_0` 后缀：
```bash
ollama run deepseek-r1:7b-q4_0
```

### 3. API连接问题

**问题**：可视化工具无法连接到Ollama服务。

**解决方案**：
  - 确保Ollama服务正在运行
  - 检查API地址是否正确（默认为 `http://localhost:11434`）
  - 检查防火墙设置，确保端口11434未被阻止
  - 如果使用自定义端口，确保在可视化工具中使用相同的端口

### 4. 模型响应缓慢

**问题**：模型响应速度非常慢。

**解决方案**：
  - 检查GPU驱动是否最新
  - 关闭其他占用GPU资源的应用
  - 尝试使用更小的模型
  - 调整系统电源计划为高性能模式
