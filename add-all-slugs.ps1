# Batch add slugs to all Hugo posts
# 批量为所有文章添加英文 slug

# Define file-to-slug mapping
$mappings = @(
    @{File="政务系统可观测平台搭建实战SigNoz与OpenTelemetry探针全流程.md"; Slug="signoz-opentelemetry-observability-guide"}
    @{File="排队叫号.md"; Slug="queue-system"}
    @{File="navicat激活使用全流程.md"; Slug="navicat-activation-guide"}
    @{File="一件事系统全流程以及常见问题.md"; Slug="one-thing-system-guide"}
    @{File="排队叫号用户操作手册.md"; Slug="queue-system-user-manual"}
    @{File="记一次删除服务器文件.md"; Slug="server-file-deletion-experience"}
    @{File="PHP自定义函数test_input.md"; Slug="php-test-input-function"}
    @{File="PowerShell执行策略修改指南.md"; Slug="powershell-execution-policy-guide"}
    @{File="完美解决git-push失败Connection-reset与Failed-to-connect终极指南.md"; Slug="git-push-connection-failed-solutions"}
    @{File="uBlock Origin Lite 使用指南.md"; Slug="ublock-origin-lite-guide"}
    @{File="如何激活win10.md"; Slug="windows10-activation-guide"}
    @{File="断网服务器自救指南挂载CentOS-ISO镜像打造离线本地YUM源.md"; Slug="centos-offline-yum-repo-guide"}
    @{File="网页视频控速工具使用指南.md"; Slug="video-speed-controller-guide"}
    @{File="CentOS安装MySQL终极指南从YUM到离线包总有一款适合你.md"; Slug="centos-mysql-installation-guide"}
    @{File="PyCharm激活工具使用指南.md"; Slug="pycharm-activation-guide"}
    @{File="好差评常见问题.md"; Slug="review-system-faq"}
    @{File="Excel2024调用接口获取电子证照数据.md"; Slug="excel-api-ecertificate-guide"}
    @{File="office下载以及激活.md"; Slug="office-download-activation-guide"}
    @{File="Oracle数据库ORA-12518错误处理指南.md"; Slug="oracle-ora-12518-troubleshooting"}
    @{File="Oracle数据库ORA-12541错误排查：监听日志过大导致连接失败.md"; Slug="oracle-ora-12541-listener-log-issue"}
    @{File="【WechatRealFriends】一个检测微信单向好友工具.md"; Slug="wechat-real-friends-tool"}
    @{File="临时邮箱使用指南.md"; Slug="temp-email-guide"}
    @{File="公文材料格式.md"; Slug="official-document-format"}
    @{File="排队叫号全流程操作手册.md"; Slug="queue-system-complete-manual"}
    @{File="数据库常见操作.md"; Slug="database-common-operations"}
    @{File="浏览器截图工具完全指南.md"; Slug="browser-screenshot-tools-guide"}
    @{File="该长大了孩儿歌词分享.md"; Slug="grow-up-kid-lyrics"}
    @{File="Charles抓包工具使用.md"; Slug="charles-proxy-guide"}
    @{File="linux服务器下载oracle全流程.md"; Slug="linux-oracle-download-guide"}
    @{File="电子监察常见问题分析.md"; Slug="esupervision-faq"}
    @{File="窗口变更操作指南.md"; Slug="window-change-operation-guide"}
    @{File="蒙速办常见问题解决方案汇总.md"; Slug="mengsuban-solutions"}
    @{File="本地部署Ollama+deepseek，并修改ollama部署位置.md"; Slug="ollama-deepseek-local-deployment"}
    @{File="基础平台常见操作手册.md"; Slug="base-platform-operation-manual"}
    @{File="审批超期办件解决办法.md"; Slug="overdue-approval-solutions"}
    @{File="电子证照常见问题解答.md"; Slug="ecertificate-faq"}
    @{File="Codex中使用DeepSeek完整指南.md"; Slug="codex-deepseek-guide"}
    @{File="电子签章.md"; Slug="esignature-guide"}
    @{File="ADB安卓调试桥完整操作指南.md"; Slug="adb-android-debug-bridge-guide"}
    @{File="西安三天两夜旅游攻略.md"; Slug="xian-3days-travel-guide"}
    @{File="融合平台常见问题.md"; Slug="integration-platform-faq"}
    @{File="Windows桌面美化四件套巨应壁纸RainmeterTranslucentTBNeXuS实战指南.md"; Slug="windows-desktop-customization-guide"}
    @{File="链条系统常见问题.md"; Slug="chain-system-faq"}
    @{File="平遥两天一夜攻略.md"; Slug="pingyao-2days-guide"}
    @{File="平遥两天一夜旅游攻略.md"; Slug="pingyao-2days-travel-guide"}
)

$postsPath = "content\posts"
$processedCount = 0
$skippedCount = 0
$errorCount = 0

Write-Host "========================================" -ForegroundColor Magenta
Write-Host "开始批量添加 slug..." -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host ""

foreach ($mapping in $mappings) {
    $fileName = $mapping.File
    $slug = $mapping.Slug
    $filePath = Join-Path $postsPath $fileName
    
    try {
        if (Test-Path $filePath) {
            $file = Get-Item $filePath
            
            # Read content
            $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.UTF8Encoding]::new($false))
            
            # Check if slug exists
            if ($content -match 'slug\s*:') {
                Write-Host "[SKIP] $fileName (已有 slug)" -ForegroundColor Yellow
                $skippedCount++
            } else {
                # Add slug after title line
                if ($content -match 'title:.*?[\r\n]+') {
                    $titleMatch = $matches[0]
                    $replacement = $titleMatch + "slug: $slug`n"
                    
                    $newContent = $content.Replace($titleMatch, $replacement)
                    
                    # Save file
                    [System.IO.File]::WriteAllText($file.FullName, $newContent, [System.Text.UTF8Encoding]::new($false))
                    
                    Write-Host "[OK] $fileName -> $slug" -ForegroundColor Green
                    $processedCount++
                } else {
                    Write-Host "[ERROR] $fileName (找不到 title 行)" -ForegroundColor Red
                    $errorCount++
                }
            }
        } else {
            Write-Host "[ERROR] $fileName (文件不存在)" -ForegroundColor Red
            $errorCount++
        }
    }
    catch {
        Write-Host "[ERROR] $fileName - $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "处理完成！" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "成功: $processedCount 篇" -ForegroundColor Green
Write-Host "跳过: $skippedCount 篇" -ForegroundColor Yellow
Write-Host "失败: $errorCount 篇" -ForegroundColor Red
Write-Host ""
Write-Host "提示: 运行 'hugo server' 查看效果" -ForegroundColor Cyan
