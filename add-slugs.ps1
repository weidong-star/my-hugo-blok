# Batch add English slugs to Hugo articles
# UTF-8 encoding to handle Chinese characters

$postsPath = "content\posts"
$processedCount = 0
$skippedCount = 0

# Process each file individually
Write-Host "Starting to add slugs..." -ForegroundColor Cyan

# File 1
$file = "$postsPath\政务系统可观测平台搭建实战SigNoz与OpenTelemetry探针全流程.md"
if (Test-Path $file) {
    $content = Get-Content $file -Raw -Encoding UTF8
    if ($content -notmatch 'slug\s*:') {
        $content = $content -replace '(title:.*?\r?\n)', "`$1slug: signoz-opentelemetry-observability-guide`r`n"
        [System.IO.File]::WriteAllText($file, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "[OK] 政务系统可观测平台..." -ForegroundColor Green
        $processedCount++
    }
}

# File 2
$file = "$postsPath\排队叫号.md"
if (Test-Path $file) {
    $content = Get-Content $file -Raw -Encoding UTF8
    if ($content -notmatch 'slug\s*:') {
        $content = $content -replace '(title:.*?\r?\n)', "`$1slug: queue-system`r`n"
        [System.IO.File]::WriteAllText($file, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "[OK] 排队叫号" -ForegroundColor Green
        $processedCount++
    }
}

# File 3
$file = "$postsPath\navicat激活使用全流程.md"
if (Test-Path $file) {
    $content = Get-Content $file -Raw -Encoding UTF8
    if ($content -notmatch 'slug\s*:') {
        $content = $content -replace '(title:.*?\r?\n)', "`$1slug: navicat-activation-guide`r`n"
        [System.IO.File]::WriteAllText($file, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "[OK] navicat激活使用全流程" -ForegroundColor Green
        $processedCount++
    }
}

# File 4
$file = "$postsPath\一件事系统全流程以及常见问题.md"
if (Test-Path $file) {
    $content = Get-Content $file -Raw -Encoding UTF8
    if ($content -notmatch 'slug\s*:') {
        $content = $content -replace '(title:.*?\r?\n)', "`$1slug: one-thing-system-guide`r`n"
        [System.IO.File]::WriteAllText($file, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "[OK] 一件事系统全流程..." -ForegroundColor Green
        $processedCount++
    }
}

# File 5
$file = "$postsPath\排队叫号用户操作手册.md"
if (Test-Path $file) {
    $content = Get-Content $file -Raw -Encoding UTF8
    if ($content -notmatch 'slug\s*:') {
        $content = $content -replace '(title:.*?\r?\n)', "`$1slug: queue-system-user-manual`r`n"
        [System.IO.File]::WriteAllText($file, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "[OK] 排队叫号用户操作手册" -ForegroundColor Green
        $processedCount++
    }
}

# File 6
$file = "$postsPath\记一次删除服务器文件.md"
if (Test-Path $file) {
    $content = Get-Content $file -Raw -Encoding UTF8
    if ($content -notmatch 'slug\s*:') {
        $content = $content -replace '(title:.*?\r?\n)', "`$1slug: server-file-deletion-experience`r`n"
        [System.IO.File]::WriteAllText($file, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "[OK] 记一次删除服务器文件" -ForegroundColor Green
        $processedCount++
    }
}

# File 7
$file = "$postsPath\PHP自定义函数test_input.md"
if (Test-Path $file) {
    $content = Get-Content $file -Raw -Encoding UTF8
    if ($content -notmatch 'slug\s*:') {
        $content = $content -replace '(title:.*?\r?\n)', "`$1slug: php-test-input-function`r`n"
        [System.IO.File]::WriteAllText($file, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "[OK] PHP自定义函数test_input" -ForegroundColor Green
        $processedCount++
    }
}

# File 8
$file = "$postsPath\PowerShell执行策略修改指南.md"
if (Test-Path $file) {
    $content = Get-Content $file -Raw -Encoding UTF8
    if ($content -notmatch 'slug\s*:') {
        $content = $content -replace '(title:.*?\r?\n)', "`$1slug: powershell-execution-policy-guide`r`n"
        [System.IO.File]::WriteAllText($file, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "[OK] PowerShell执行策略修改指南" -ForegroundColor Green
        $processedCount++
    }
}

# File 9
$file = "$postsPath\完美解决git-push失败Connection-reset与Failed-to-connect终极指南.md"
if (Test-Path $file) {
    $content = Get-Content $file -Raw -Encoding UTF8
    if ($content -notmatch 'slug\s*:') {
        $content = $content -replace '(title:.*?\r?\n)', "`$1slug: git-push-connection-failed-solutions`r`n"
        [System.IO.File]::WriteAllText($file, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "[OK] 完美解决git-push..." -ForegroundColor Green
        $processedCount++
    }
}

# File 10
$file = "$postsPath\uBlock Origin Lite 使用指南.md"
if (Test-Path $file) {
    $content = Get-Content $file -Raw -Encoding UTF8
    if ($content -notmatch 'slug\s*:') {
        $content = $content -replace '(title:.*?\r?\n)', "`$1slug: ublock-origin-lite-guide`r`n"
        [System.IO.File]::WriteAllText($file, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "[OK] uBlock Origin Lite 使用指南" -ForegroundColor Green
        $processedCount++
    }
}

Write-Host ""
Write-Host "Processed first 10 files. Continue with remaining files..." -ForegroundColor Yellow
Write-Host "Successfully processed: $processedCount files" -ForegroundColor Green
