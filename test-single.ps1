# Add slug to a single file (test first)
$file = "content\posts\政务系统可观测平台搭建实战SigNoz与OpenTelemetry探针全流程.md"
$slug = "signoz-opentelemetry-observability-guide"

Write-Host "Processing file..." -ForegroundColor Cyan

# Read file content
$content = [System.IO.File]::ReadAllText($file, [System.Text.UTF8Encoding]::new($false))

# Check if slug exists
if ($content -match 'slug\s*:') {
    Write-Host "Slug already exists, skipping..." -ForegroundColor Yellow
} else {
    # Find the title line and add slug after it
    if ($content -match 'title:.*?\r?\n') {
        $titleMatch = $matches[0]
        $replacement = $titleMatch + "slug: $slug`n"
        
        $newContent = $content.Replace($titleMatch, $replacement)
        
        # Save file
        [System.IO.File]::WriteAllText($file, $newContent, [System.Text.UTF8Encoding]::new($false))
        
        Write-Host "Successfully added slug: $slug" -ForegroundColor Green
        
        # Verify
        $verify = [System.IO.File]::ReadAllText($file, [System.Text.UTF8Encoding]::new($false))
        if ($verify -match 'slug:') {
            Write-Host "Verification: OK" -ForegroundColor Green
            
            # Show the updated front matter
            if ($verify -match '(?s)^---(.*?)---') {
                Write-Host "`nUpdated Front Matter:" -ForegroundColor Cyan
                Write-Host $matches[1]
            }
        } else {
            Write-Host "Verification: FAILED" -ForegroundColor Red
        }
    } else {
        Write-Host "Could not find title line" -ForegroundColor Red
    }
}
