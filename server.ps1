# Hugo 本地预览脚本
# 编码: UTF-8 BOM

$hugo = "bin/hugo.exe"

# 检查 Hugo 是否存在
if (-not (Test-Path $hugo)) {
    Write-Host "未找到本地 Hugo，正在尝试自动安装..." -ForegroundColor Yellow
    powershell -ExecutionPolicy Bypass -File .\install_hugo.ps1
}

# 启动 Hugo Server
Write-Host "正在启动预览服务器..." -ForegroundColor Green
Write-Host "请访问 http://localhost:1313/" -ForegroundColor Cyan
& $hugo server --buildDrafts --disableFastRender