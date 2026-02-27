# Weidong's Blok

个人技术博客，基于 Hugo + Blowfish 主题构建。

## 🌐 在线访问

- 主站：https://wdblok.vip
- Vercel：https://your-project.vercel.app

## 🛠️ 技术栈

- **静态网站生成器**：[Hugo](https://gohugo.io/)
- **主题**：[Blowfish](https://blowfish.page/)
- **部署平台**：Vercel
- **评论系统**：Cusdis

## 📦 本地开发

### 前置要求

- Hugo Extended 版本 >= 0.140.0

### 启动预览

```powershell
# Windows
.\server.ps1

# 或直接使用 Hugo
hugo server -D
```

访问 http://localhost:1313

## 🚀 部署

### Vercel 部署（推荐）

1. Fork 本仓库到你的 GitHub
2. 在 Vercel 导入项目
3. Vercel 会自动检测 Hugo 并部署
4. 绑定自定义域名（可选）

### 手动部署

```powershell
# 构建静态文件
hugo --minify

# public/ 目录即为生成的静态网站
```

## 📝 写作

### 创建新文章

```bash
hugo new posts/my-new-post.md
```

### 文章模板

```markdown
---
title: "文章标题"
date: 2025-02-27
categories: ["分类"]
tags: ["标签1", "标签2"]
description: "文章描述"
---

文章内容...
```

## 📂 项目结构

```
MyHugo1103/
├── archetypes/          # 文章模板
├── assets/              # 静态资源（CSS、JS、图片）
├── config/              # 配置文件
│   └── _default/
│       ├── hugo.toml
│       ├── languages.zh.toml
│       ├── menus.zh.toml
│       └── params.toml
├── content/             # 文章内容
│   ├── posts/           # 博客文章
│   ├── about.md         # 关于页面
│   └── privacy.md       # 隐私政策
├── layouts/             # 自定义布局
├── static/              # 静态文件
├── themes/              # 主题
│   └── blowfish/
├── vercel.json          # Vercel 配置
└── README.md
```

## ⚙️ 配置说明

主要配置文件位于 `config/_default/` 目录：

- `hugo.toml` - 站点基础配置
- `params.toml` - 主题参数配置
- `menus.zh.toml` - 导航菜单配置
- `languages.zh.toml` - 语言配置

## 📄 许可证

本博客内容采用 [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) 许可协议。

## 📧 联系方式

- 邮箱：weidong_321@163.com
- 博客：https://wdblok.vip

