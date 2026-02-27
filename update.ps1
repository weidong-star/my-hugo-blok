# update.ps1 - Update blog to Vercel
# Usage: .\update.ps1 "commit message"

param(
    [string]$message = "Update blog content"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Blog Update Script - Vercel Deploy" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check for uncommitted changes
Write-Host "Checking for changes..." -ForegroundColor Yellow
$status = git status --porcelain

if ([string]::IsNullOrEmpty($status)) {
    Write-Host "No changes to commit." -ForegroundColor Green
    exit 0
}

# Show changed files
Write-Host "Changed files:" -ForegroundColor Green
git status --short

Write-Host ""
Write-Host "Preparing to commit..." -ForegroundColor Yellow

# Add all changes
git add .

# Check if git add succeeded
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to add files!" -ForegroundColor Red
    exit 1
}

# Commit changes
Write-Host "Commit message: $message" -ForegroundColor Cyan
git commit -m "$message"

# Check if commit succeeded
if ($LASTEXITCODE -ne 0) {
    Write-Host "Commit failed! Please check Git configuration." -ForegroundColor Red
    exit 1
}

# Push to GitHub
Write-Host ""
Write-Host "Pushing to GitHub..." -ForegroundColor Yellow
git push origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Success!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Vercel will auto-deploy in 1-2 minutes." -ForegroundColor Cyan
    Write-Host "Visit: https://vercel.com/dashboard" -ForegroundColor Cyan
    Write-Host "Or: https://wdblok.vip" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "Push failed! Check network or Git config." -ForegroundColor Red
    exit 1
}
