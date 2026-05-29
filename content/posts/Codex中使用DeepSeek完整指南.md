---
title: 两种方式在 Codex 中使用 DeepSeek（CCX + Codex++）
date: 2026-05-29T09:00:00+08:00
categories:
  - 个人分享/工具分享
tags:
  - Codex
  - DeepSeek
  - CCX
  - Codex++
  - AI编程
  - API代理
excerpt: 详细教程：通过 CCX + CC-Switch 和 Codex++ 两种方案，在 Codex 终端中接入 DeepSeek 模型，享受高性价比的 AI 编程体验。
---

# 两种方式在 Codex 中使用 DeepSeek

## 前言

[Codex](https://github.com/openai/codex) 是 OpenAI 开源的终端 AI 编程助手，默认仅对接 OpenAI 官方 API。如果想换成 DeepSeek，需要借助社区工具做一层"翻译"。

本文介绍 **两种方案**，按由繁到简排列：

- **方案一：CCX + CC-Switch** — 功能全面，支持多模型管理，适合想精细化控制 API 路由的用户
- **方案二：Codex++** — 极简快捷，三步搞定，适合追求效率的用户

## 整体架构

两种方案的原理本质相同——都是在 Codex 和 DeepSeek 之间加一个"中间层"，把 DeepSeek 的 API 转成 OpenAI 兼容格式。

<pre class="mermaid">
flowchart LR
    A["🖥️ Codex\n终端 AI 助手"] --> B["🔌 中间层\nCCX / Codex++"]
    B --> C["☁️ DeepSeek API\napi.deepseek.com"]
    B -.->|"方案一"| D["CCX + CC-Switch\nWeb 管理 + 模型切换"]
    B -.->|"方案二"| E["Codex++\n一键配置 + 重启生效"]
</pre>

## 前置准备

无论使用哪种方案，都需要以下准备工作：

- **安装 Codex**（[官方下载](https://github.com/openai/codex)），安装后**暂不登录**
- **注册 DeepSeek**（[官网](https://platform.deepseek.com/)），充值后获取 API Key

> ℹ️ DeepSeek 的 API Key 格式通常为 `sk-xxxxxxxxxxxxxxxxxxxxxxxx`，请妥善保管。

---

## 方案一：CCX + CC-Switch（功能全面）

<pre class="mermaid">
flowchart TD
    A["📥 下载 CCX 和 CC-Switch"] --> B["⚙️ 配置 CCX .env"]
    B --> C["🚀 启动 CCX 代理服务"]
    C --> D["🌐 Web 后台添加 DeepSeek 渠道"]
    D --> E["🔧 CC-Switch 配置模型"]
    E --> F["🔑 Codex 中填入 API Key"]
    F --> G["✅ 完成"]
</pre>

### 第一步：下载所需工具

| 工具 | 下载地址 | 说明 |
|------|----------|------|
| CCX | [GitHub Releases](https://github.com/BenedictKing/ccx/releases) | API 代理服务，我下载的是 `ccx-windows-amd64.exe` |
| CC-Switch | [GitHub Releases](https://github.com/farion1231/cc-switch/releases) | 模型切换 GUI，我下载的是 `CC-Switch-v3.15.0-Windows.msi` |

> macOS/Linux 用户请在 Releases 页面选择对应的版本。

### 第二步：配置并启动 CCX

新建一个文件夹（比如 `D:\CCX`），把下载好的 `ccx-windows-amd64.exe` 放进去，在该目录下创建 `.env` 文件：

```ini
PROXY_ACCESS_KEY=你的强密码
PORT=3000
ENABLE_WEB_UI=true
APP_UI_LANGUAGE=en
```

参数说明：
- **PROXY_ACCESS_KEY**：访问管理后台和 API 的密码，**一定改成自己的**
- **PORT**：服务端口，默认 3000
- **ENABLE_WEB_UI**：启用 Web 管理界面
- **APP_UI_LANGUAGE**：管理界面语言，`en` 为英文

在该目录下打开终端，运行：

```bash
./ccx-windows-amd64.exe
```

启动成功的标志：

```
[Server-Startup] CCX API代理服务器已启动
[Server-Info] 版本: v2.8.14
[Server-Info] 管理界面: http://localhost:3000
[Server-Info] API 地址: http://localhost:3000/v1
[Server-Info] Chat Completions: POST /v1/chat/completions
```

### 第三步：在 CCX 中添加 DeepSeek 渠道

1. 浏览器打开 `http://localhost:3000`，输入 `.env` 中设置的密码
2. 顶部导航点击 **CODEX** → 点击 **+ ADD CHANNEL**
3. 粘贴以下 curl 配置：

```bash
curl https://api.deepseek.com/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${DEEPSEEK_API_KEY}" \
  -d '{
        "model": "deepseek-v4-pro",
        "messages": [
          {"role": "system", "content": "You are a helpful assistant."},
          {"role": "user", "content": "Hello!"}
        ],
        "thinking": {"type": "enabled"},
        "reasoning_effort": "high",
        "stream": false
      }'
```

4. 把 `-H "Authorization: Bearer ${DEEPSEEK_API_KEY}"` 替换为你的真实 Key：

   ```bash
   -H "API key: sk-你的DeepSeek密钥"
   ```

5. 点击右上角的 **DETAILED CONFIG**（详细配置）：
   - **Service type** → 选择 `OpenAI Chat`
   - **Normalize metadata.user id** → 开启 ✅
   - **Normalize non-standard chat roles** → 开启 ✅
6. 下拉到底，点击 **CREATE CHANNEL** 保存

### 第四步：在 CC-Switch 中配置模型

1. 打开 CC-Switch，选择 **GPT** 选项卡，点击右侧 **+** 号
2. 填写配置：
   - **供应商名称**：任意填写，如 `DeepSeek`
   - **API Key**：填入 `.env` 中的 `PROXY_ACCESS_KEY`
   - **API 请求地址**：`http://localhost:3000/v1`
3. 点击 **获取模型列表**，看到 DeepSeek 模型后选择并提交
4. 回到主界面点击 **启动**，然后 **测试模型**，提示正常即配置成功

### 第五步：接入 Codex

1. **重启 Codex**
2. 登录界面选择 **其他方式登录**（Other sign in options）
3. 找到 **OpenAI API 密钥** 字段，填入 `.env` 中的 `PROXY_ACCESS_KEY`
4. 登录成功后即可正常使用

---

## 方案二：Codex++（极简快捷）

<pre class="mermaid">
flowchart TD
    A["📥 下载 Codex++"] --> B["⚙️ 添加供应商配置"]
    B --> C["🔄 重启 Codex"]
    C --> D["✅ 完成"]
</pre>

如果你觉得方案一太繁琐，Codex++ 是最省事的选择——省去了 CCX 代理和 CC-Switch 两个中间环节，直接在 Codex++ 里配置 DeepSeek 即可。

### 第一步：下载安装 Codex++

访问 [Codex++ Releases](https://github.com/BigPizzaV3/CodexPlusPlus/releases)，下载对应系统的版本并安装。

### 第二步：配置供应商

1. 打开 **Codex++ 管理工具**
2. 选择 **供应商配置** → 点击 **添加供应商**
3. 按以下内容填写：

   | 配置项 | 填写内容 |
   |--------|----------|
   | 供应商名称 | 任意填写，如 `DeepSeek` |
   | 接入模式 | **纯 API** |
   | 模型名称 | `deepseek-v4-pro`（或你需要的其他 DeepSeek 模型） |
   | Base URL | `https://api.deepseek.com` |
   | API Key | 你在 DeepSeek 官网获取的 Key |
   | 上游协议 | **Chat Completions** ⚠️ |

   > ⚠️ **重要**：上游协议务必选择 **Chat Completions**，不要选 Responses API，否则无法正常使用！

4. 点击上方 **保存**

### 第三步：重启 Codex

在 Codex++ 管理工具中点击 **重启 Codex** 即可生效，无需额外配置。

---

## 两种方案对比

<pre class="mermaid">
quadrantChart
    title 功能 vs 便捷度
    x-axis "配置繁琐" --> "配置简单"
    y-axis "功能基础" --> "功能强大"
    quadrant-1 "最佳选择"
    quadrant-2 "功能优先"
    quadrant-3 "不推荐"
    quadrant-4 "便捷优先"
    "方案一：CCX+CC-Switch": [0.3, 0.7]
    "方案二：Codex++": [0.75, 0.35]
</pre>

| 对比维度 | 方案一：CCX + CC-Switch | 方案二：Codex++ |
|----------|------------------------|-----------------|
| 配置步骤 | 5 步 | 3 步 |
| 需要额外服务 | ✅ 需运行 CCX 代理 | ❌ 无需 |
| 多模型管理 | ✅ 支持多供应商 | ✅ 支持 |
| Web 管理界面 | ✅ 有 | ❌ 无 |
| 学习成本 | 中等 | 低 |
| 适用人群 | 想深度定制 API 路由的用户 | 追求开箱即用的用户 |

## 常见问题

### Q：端口被占用怎么办？

修改 CCX `.env` 中的 `PORT` 为其他值（如 `3001`），同时将 CC-Switch 中的 API 地址同步修改。

### Q：获取模型列表为空？

- 确认 CCX 服务正在运行
- 检查 API Key 是否正确
- 浏览器访问 `http://localhost:3000/v1/models` 验证连通性

### Q：Codex 登录失败？

- 确保中间层服务已启动（方案一需 CCX，方案二需 Codex++ 已配置保存）
- 确认 API Key 填写一致
- 完全退出 Codex 后重新打开

### Q：上游协议选成 Responses API 了怎么办？

回到 Codex++ 供应商配置页，把上游协议改成 **Chat Completions**，保存并重启 Codex。

## 总结

两种方案核心思路一致：**在 Codex 和 DeepSeek 之间建立一层 OpenAI 兼容的桥梁**。

- 如果你喜欢**掌控细节**、需要同时管理多个 API 供应商 → 选方案一（CCX + CC-Switch）
- 如果你追求**快速上手**、不想维护额外服务 → 选方案二（Codex++）

无论哪种方案，成功后都可以用 DeepSeek 的高性价比 API 享受 Codex 的终端 AI 编程体验。这套思路同样适用于其他兼容 OpenAI 格式的 API 服务（如通义千问、Moonshot 等），举一反三即可。
