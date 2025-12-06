Write-Host "=== Moving everything to project folder ===" -ForegroundColor Cyan

$projectPath = ".\project"

# Maak project folder structuur compleet
$folders = @(
    "$projectPath\Config",
    "$projectPath\Modules\Migration",
    "$projectPath\Modules\Analysis",
    "$projectPath\Modules\Reporting",
    "$projectPath\Modules\SQLite",
    "$projectPath\data",
    "$projectPath\lib",
    "$projectPath\Output",
    "$projectPath\TestData",
    "$projectPath\Tests"
)

Write-Host "Creating folder structure..." -ForegroundColor Yellow
foreach ($folder in $folders) {
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Write-Host "  ✓ $folder" -ForegroundColor Green
    }
}

# Verplaats bestanden uit root naar project
Write-Host "`nMoving files to project folder..." -ForegroundColor Yellow

# Modules
if (Test-Path ".\Modules") {
    Get-ChildItem ".\Modules" -Recurse -File | ForEach-Object {
        $relativePath = $_.FullName.Replace((Get-Location).Path + "\Modules\", "")
        $targetPath = Join-Path "$projectPath\Modules" $relativePath
        $targetDir = Split-Path $targetPath -Parent
        
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        
        Copy-Item $_.FullName -Destination $targetPath -Force
        Write-Host "  ✓ Modules\$relativePath" -ForegroundColor Green
    }
}

# Config
if (Test-Path ".\Config") {
    Get-ChildItem ".\Config" -File | ForEach-Object {
        Copy-Item $_.FullName -Destination "$projectPath\Config\" -Force
        Write-Host "  ✓ Config\$($_.Name)" -ForegroundColor Green
    }
}

# Test scripts (alle .ps1 files in root)
Get-ChildItem "." -Filter "*.ps1" | Where-Object { $_.Name -ne "Move-To-Project.ps1" } | ForEach-Object {
    Copy-Item $_.FullName -Destination "$projectPath\" -Force
    Write-Host "  ✓ $($_.Name)" -ForegroundColor Green
}

# TestData
if (Test-Path ".\TestData") {
    Copy-Item ".\TestData\*" -Destination "$projectPath\TestData\" -Force -ErrorAction SilentlyContinue
    Write-Host "  ✓ TestData files" -ForegroundColor Green
}

# Output
if (Test-Path ".\Output") {
    Copy-Item ".\Output\*" -Destination "$projectPath\Output\" -Force -ErrorAction SilentlyContinue
    Write-Host "  ✓ Output files" -ForegroundColor Green
}

# lib folder
if (Test-Path ".\lib") {
    Copy-Item ".\lib\*" -Destination "$projectPath\lib\" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  ✓ lib files" -ForegroundColor Green
}

Write-Host "`n✓ All files moved to project folder!" -ForegroundColor Green
Write-Host "`nNow working directory should be: $projectPath" -ForegroundColor Cyan
Write-Host "Run: cd project" -ForegroundColor Yellow