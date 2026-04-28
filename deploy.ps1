# Hugo 站点部署脚本
# 编码: UTF-8 BOM

# 1. 清理旧的构建文件
Write-Host "正在清理旧的构建文件..." -ForegroundColor Green
if (Test-Path public) { Remove-Item -Path public -Recurse -Force }

# 2. 检查 Hugo 是否安装
$hugo = "bin/hugo.exe"
if (-not (Test-Path $hugo)) {
    Write-Host "错误: 未找到 Hugo 可执行文件 ($hugo)" -ForegroundColor Red
    exit 1
}

# 3. 执行 Hugo 构建
Write-Host "正在构建站点..." -ForegroundColor Green
& $hugo --gc --minify

# 4. 检查构建结果
if ($LASTEXITCODE -eq 0) {
    Write-Host "构建成功！" -ForegroundColor Green
    Write-Host "生成的文件位于 public/ 目录。" -ForegroundColor Cyan
} else {
    Write-Host "错误: 站点构建失败。" -ForegroundColor Red
    exit 1
}

# 执行完后暂停，方便查看结果
Read-Host "按回车键退出..."