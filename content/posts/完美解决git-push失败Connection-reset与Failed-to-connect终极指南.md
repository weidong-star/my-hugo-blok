---

title: 完美解决 git push 失败："Connection reset" 与 "Failed to connect" 终极指南
date: 2024-01-19T14:30:00+08:00
# thumbnail: /images/blokImg/git.png
categories:
  - 个人分享/技术分享
tags:
  - Git
  - GitHub
  - SSH
  - 网络配置
  - 问题解决
excerpt: 在使用Git推送代码时遇到"Connection reset"和"Failed to connect"错误？本文提供完整的SSH配置解决方案，让你彻底告别git push失败的烦恼，实现稳定可靠的多设备代码同步。
---

## 前言

作为一名开发者（或者像我一样的博客作者），我们经常需要在不同的电脑上同步代码。`Git` + `GitHub` 无疑是实现这一目标的最佳工具。但最近，当我在新电脑上配置好我的 Hexo 博客，准备通过 `git push` 将新文章推送到远程仓库时，却遭遇了两个经典的拦路虎：

```bash
# 错误一
fatal: unable to access 'https://github.com/your-name/your-repo.git/': Recv failure: Connection was reset

# 错误二
fatal: unable to access 'https://github.com/your-name/your-repo.git/': Failed to connect to github.com port 443 after 21085 ms: Could not connect to server
```

如果你也遇到了这两个错误，别慌！这通常不是你的代码或 Git 命令出了问题，而是纯粹的网络连接问题。这篇文章将带你从根源上解决它，让你从此告别 push 失败的烦恼。

## 问题诊断：为什么会失败？

这两个错误信息都指向同一个核心原因：你的电脑无法通过 HTTPS 协议稳定地连接到 GitHub 服务器。

  - **Connection was reset**：连接刚建立就被中断，好比电话刚接通就被挂断。
  - **Failed to connect to... port 443**：连接请求压根就没成功，好比电话都拨不出去。

这在中国大陆地区尤其常见，主要原因可能是网络波动或防火墙（GFW）的干扰。

既然 HTTPS 这条路（走 443 端口）被堵了，我们就得换一条更稳定、更通畅的路——**SSH 协议**。

## 解决方案：切换到 SSH 协议

SSH (Secure Shell) 是一种加密的网络传输协议，它不仅更安全，而且在复杂的网络环境下通常比 HTTPS 更稳定。配置一次，终身受益。

下面是详细的配置步骤，请务必在 **Git Bash** 环境下操作（在项目文件夹右键，选择 "Git Bash Here"）。

### 第一步：检查并生成 SSH 密钥对

首先，我们需要在你的电脑上创建一对专属的"钥匙"——SSH 密钥对。

#### 检查现有密钥

打开 Git Bash，输入以下命令：

```bash
ls -al ~/.ssh
```

如果列表里能看到 `id_rsa.pub` 或 `id_ed25519.pub` 这样的文件，说明你已经有密钥了，可以跳到第二步。

#### 生成新密钥

如果没有，就运行下面的命令来生成一对新的密钥。推荐使用 ed25519 算法，它更现代、更安全。

```bash
# 把引号里的邮箱换成你自己的 GitHub 注册邮箱
ssh-keygen -t ed25519 -C "weidong_321@163.com"
```

执行后，系统会询问你几个问题，你只需要连续按三次回车键，使用所有默认设置即可。

### 第二步：将公钥添加到 GitHub

"钥匙"造好了，现在需要把"锁"（公钥）安装到 GitHub 的"大门"上。

#### 复制公钥

在 Git Bash 中，运行以下命令来显示并复制你的公钥内容：

```bash
cat ~/.ssh/id_ed25519.pub
```

用鼠标完整地选中并复制终端里输出的所有内容（它以 `ssh-ed25519` 开头）。

#### 添加到 GitHub 网站

1. 登录你的 GitHub 账号
2. 点击右上角你的头像 → **Settings**
3. 在左侧菜单栏，点击 **SSH and GPG keys**
4. 点击绿色的 **New SSH key** 按钮
5. 在 **Title** 栏里，为这个密钥取个名字，方便你识别是哪台电脑的，比如 `My-Home-PC`
6. 在 **Key** 的大文本框里，粘贴你刚刚复制的公钥内容
7. 点击 **Add SSH key** 保存

### 第三步：修改本地仓库的远程地址

现在，我们需要告诉本地的 Git 仓库："以后别走 HTTPS 那条老路了，改走 SSH 这条新路！"

回到你的 Git Bash 窗口，进入你的项目目录，执行以下命令：

```bash
# 把 your-name 和 your-repo 换成你自己的 GitHub 用户名和仓库名
git remote set-url origin git@github.com:your-name/your-repo.git
```

> 💡 **小技巧**：你可以用 `git remote -v` 命令来检查远程地址是否已经成功修改为 `git@...` 的格式。

### 第四步：测试连接并推送

万事俱备，只欠东风！

#### 测试 SSH 连接

在 Git Bash 中运行：

```bash
ssh -T git@github.com
```

第一次连接时，系统可能会询问你是否信任这个连接，大胆输入 `yes` 并回车。如果看到 `Hi your-name! You've successfully authenticated...` 的提示，恭喜你，配置成功！

#### 再次尝试 git push

现在，回到你的项目，再次执行推送命令：

```bash
git push
```

这一次，代码应该能顺畅无阻地推送到 GitHub 了！

## 常见问题与解决方案

### 问题1：SSH 连接超时

如果 `ssh -T git@github.com` 连接超时，可以尝试：

```bash
# 设置 SSH 连接超时时间
ssh -o ConnectTimeout=10 -T git@github.com

# 或者使用代理（如果你有代理的话）
ssh -o ProxyCommand="nc -X connect -x 127.0.0.1:7890 %h %p" -T git@github.com
```

### 问题2：密钥权限问题

在 Linux/Mac 系统上，如果遇到权限问题：

```bash
# 设置正确的文件权限
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

### 问题3：多个 SSH 密钥管理

如果你有多个 GitHub 账号或多个 SSH 密钥，可以创建 `~/.ssh/config` 文件：

```bash
# GitHub 账号1
Host github.com-account1
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_account1

# GitHub 账号2
Host github.com-account2
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_account2
```

然后使用对应的 Host 名称：

```bash
git remote set-url origin git@github.com-account1:username/repo.git
```

## 性能优化建议

### 1. 启用 SSH 连接复用

在 `~/.ssh/config` 文件中添加：

```bash
Host github.com
    HostName github.com
    User git
    ControlMaster auto
    ControlPath ~/.ssh/control-%h-%p-%r
    ControlPersist 1h
```

### 2. 使用压缩传输

```bash
git config --global core.compression 9
```

### 3. 设置合适的缓冲区大小

```bash
git config --global http.postBuffer 524288000
```

## 安全注意事项

### 1. 密钥保护
  - 不要将私钥文件分享给任何人
  - 定期更换 SSH 密钥对
  - 在公共电脑上使用后及时删除密钥

### 2. 访问控制
  - 定期检查 GitHub 中的 SSH 密钥列表
  - 删除不再使用的设备密钥
  - 为不同设备使用不同的密钥

### 3. 监控异常
  - 关注 GitHub 的安全通知
  - 定期检查登录活动
  - 发现异常及时处理

## 总结：关于多台电脑的操作

如果你像我一样经常更换电脑，该怎么办？

非常简单！只需要在每一台新电脑上，都完整地重复一遍上面的四个步骤即可。

一个 GitHub 账户可以关联多个公钥。你为家里的电脑配一把钥匙（公钥），为公司的电脑配一把，为出差的笔记本再配一把... 这样，无论你身在何处，使用哪台设备，都能通过 SSH 安全、稳定地连接到 GitHub。

## 验证配置是否成功

配置完成后，可以通过以下命令验证：

```bash
# 检查远程仓库地址
git remote -v

# 测试 SSH 连接
ssh -T git@github.com

# 尝试推送（如果成功，说明配置完成）
git push
```

## 故障排除清单

如果仍然遇到问题，请按以下清单检查：

  - [ ] SSH 密钥是否正确生成
  - [ ] 公钥是否已添加到 GitHub
  - [ ] 远程仓库地址是否已更改为 SSH 格式
  - [ ] 网络连接是否正常
  - [ ] 防火墙是否阻止了 SSH 连接
  - [ ] SSH 密钥权限是否正确设置


从此，**Connection reset** 不再是噩梦！通过 SSH 协议，你将拥有一个稳定、安全、高效的 Git 工作环境。

> 💡 **提示**：如果遇到其他 Git 相关问题，欢迎联系：weidong_321@163.com 
