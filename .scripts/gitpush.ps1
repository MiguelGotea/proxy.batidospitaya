Set-Location (Split-Path $PSScriptRoot -Parent)
Write-Host "Iniciando proceso de envio..." -ForegroundColor Cyan
git add .
$msg = "proxy.batidospitaya.com Update $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
git commit -m "$msg" 2>$null
git pull origin main --rebase
if ($LASTEXITCODE -ne 0) {
    git rebase --abort 2>$null
    git pull origin main --no-rebase -X ours
    git add .
    git commit -m "$msg (Manual Conflict Resolve)" 2>$null
}
git push origin main
Write-Host "Deploy automatico comenzara ahora." -ForegroundColor Green
