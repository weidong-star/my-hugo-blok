# update.ps1 - 一键更新博客到 Vercel
# 使用方法: .\update.ps1 "提交信息"

param(
    [string]$message = "Update blog content"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  博客更新脚本 - Vercel 自动部署" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 检查是否有未提交的更改
Write-Host "检查文件更改..." -ForegroundColor Yellow
$status = git status --porcelain

if ([string]::IsNullOrEmpty($status)) {
    Write-Host "没有需要提交的更改。" -ForegroundColor Green
    exit 0
}

# 显示更改的文件
Write-Host "以下文件已更改:" -ForegroundColor Green
git status --short

Write-Host ""
Write-Host "准备提交更改..." -ForegroundColor Yellow

# 添加所有更改
git add .

# 提交更改
Write-Host "提交信息: $message" -ForegroundColor Cyan
git commit -m "$message"

# 推送到 GitHub
Write-Host ""
Write-Host "正在推送到 GitHub..." -ForegroundColor Yellow
git push origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  ✓ 更新成功！" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Vercel 将自动部署你的更改，请稍等 1-2 分钟。" -ForegroundColor Cyan
    Write-Host "访问: https://vercel.com/dashboard 查看部署状态" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "推送失败，请检查网络连接或 Git 配置。" -ForegroundColor Red
    exit 1
}

