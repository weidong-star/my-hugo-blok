# deploy.ps1 - Windows 一键部署 Hugo 博客

$hugo = ".\bin\hugo.exe"

if (-not (Test-Path $hugo)) {
    Write-Host "未找到本地 Hugo，尝试使用系统 Hugo..." -ForegroundColor Yellow
    $hugo = "hugo"
}

Write-Host "正在构建 Hugo 站点..." -ForegroundColor Green
& $hugo -D   # 如果你不想发布草稿，改成 & $hugo

Write-Host "正在上传到服务器..." -ForegroundColor Green
scp -r public/* root@wdblok.vip:/var/www/wdblok.vip/

Write-Host "部署完成！" -ForegroundColor Green
Write-Host "请访问：https://wdblok.vip" -ForegroundColor Yellow


# 执行的时候直接运行
# .\deploy.ps1