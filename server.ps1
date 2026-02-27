# server.ps1 - Windows 一键启动 Hugo 预览服务

$hugo = ".\bin\hugo.exe"

if (-not (Test-Path $hugo)) {
    Write-Host "未找到 Hugo，正在尝试自动安装..." -ForegroundColor Yellow
    .\install_hugo.ps1
}

Write-Host "正在启动 Hugo 预览服务..." -ForegroundColor Green
Write-Host "请访问: http://localhost:1313" -ForegroundColor Cyan
Write-Host "按 Ctrl+C 停止服务" -ForegroundColor Yellow

& $hugo server -D --minify --gc