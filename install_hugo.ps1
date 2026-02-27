$version = "0.152.0"
$url = "https://github.com/gohugoio/hugo/releases/download/v$version/hugo_extended_${version}_windows-amd64.zip"
$zip = "hugo.zip"
$dest = "bin"

if (-not (Test-Path $dest)) {
    New-Item -ItemType Directory -Path $dest | Out-Null
}

# Always download to update version
Write-Host "Downloading Hugo v$version from GitHub..."
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    
    Write-Host "Extracting..."
    Expand-Archive -Path $zip -DestinationPath $dest -Force
    
    Remove-Item $zip
    Write-Host "Hugo installed successfully to $PWD/$dest/hugo.exe"
} catch {
    Write-Error "Failed to download Hugo. Please check your network connection or download manually."
    Write-Error $_.Exception.Message
    exit 1
}

& "$dest/hugo.exe" version
