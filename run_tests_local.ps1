#!/usr/bin/env pwsh
# PowerShell script to run Docker tests locally on Windows with coverage

param(
    [switch]$NoCoverage,
    [switch]$NoBuild
)

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Raspberry Pi Maintenance Suite - Local Tests" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# Determine coverage mode
$coverageEnabled = -not $NoCoverage

# Get script directory and project root
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = $scriptDir

# Build Docker  image unless --NoBuild is specified
if (-not $NoBuild) {
    Write-Host "[1/3] Building test Docker image..." -ForegroundColor Yellow
    docker build -t rpi-maintenance-test -f Dockerfile.test .
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Docker build failed!" -ForegroundColor Red
        exit 1
    }
    Write-Host "Docker image built successfully`n" -ForegroundColor Green
}
else {
    Write-Host "[1/3] Skipping Docker build (--NoBuild specified)`n" -ForegroundColor Yellow
}

# Prepare coverage directory
if ($coverageEnabled) {
    $coverageDir = Join-Path $projectRoot "coverage"
    if (Test-Path $coverageDir) {
        Write-Host "[2/3] Cleaning previous coverage data..." -ForegroundColor Yellow
        Remove-Item -Path $coverageDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $coverageDir -Force | Out-Null
    Write-Host "Coverage directory prepared`n" -ForegroundColor Green
}
else {
    Write-Host "[2/3] Coverage reporting disabled`n" -ForegroundColor Yellow
}

# Run tests
Write-Host "[3/3] Running tests in Docker..." -ForegroundColor Yellow

if ($coverageEnabled) {
    $volumeMount = "${coverageDir}:/home/pi/coverage_output"
    docker run --rm `
        --security-opt seccomp=unconfined `
        --cap-add SYS_PTRACE `
        -e COVERAGE=1 `
        -e COVERAGE_OUTPUT=/home/pi/coverage_output `
        -v $volumeMount `
        rpi-maintenance-test
}
else {
    docker run --rm rpi-maintenance-test
}

$testExitCode = $LASTEXITCODE

Write-Host ""
if ($testExitCode -eq 0) {
    Write-Host "All tests passed!" -ForegroundColor Green
    
    if ($coverageEnabled) {
        Write-Host ""
        Write-Host "==================================================" -ForegroundColor Cyan
        Write-Host "  Coverage Report Summary" -ForegroundColor Cyan
        Write-Host "==================================================" -ForegroundColor Cyan
        
        # Find coverage.json files
        $mergedCovFile = Join-Path $coverageDir "html_report/kcov-merged/coverage.json"
        if (-not (Test-Path $mergedCovFile)) {
            # Fallback: look for any coverage.json
            $coverageFiles = Get-ChildItem -Path $coverageDir -Filter "coverage.json" -Recurse | Where-Object { $_.FullName -notmatch "html_report" }
            if ($coverageFiles.Count -gt 0) {
                $mergedCovFile = $coverageFiles[0].FullName
            }
        }
        
        if (Test-Path $mergedCovFile) {
            Write-Host "Coverage report found: $mergedCovFile" -ForegroundColor White
            Write-Host ""
            
            $jsonContent = Get-Content $mergedCovFile | ConvertFrom-Json
            $percent = $jsonContent.percent_covered
            Write-Host "  Overall Merged Coverage: $percent%" -ForegroundColor Cyan
            
            # Display file coverage
            Write-Host ""
            Write-Host "  File Coverage:" -ForegroundColor White
            foreach ($file in $jsonContent.files) {
                $fileName = $file.file -replace '/home/pi/', '' -replace '/app/', ''
                $filePct = $file.percent_covered
                $coveredLines = $file.covered_lines
                $totalLines = $file.total_lines
                Write-Host "    - ${fileName} : ${filePct}% (${coveredLines}/${totalLines} lines)" -ForegroundColor Gray
            }
            Write-Host ""
            
            Write-Host "  Open coverage/index.html in a browser for detailed report" -ForegroundColor Yellow
            
            # Enforce 90% threshold
            if ($percent -lt 90) {
                Write-Host ""
                Write-Host "CRITICAL: Overall coverage ($percent%) is below the 90% threshold!" -ForegroundColor Red
                $testExitCode = 1
            }
            else {
                Write-Host ""
                Write-Host "SUCCESS: Coverage threshold (90%) met!" -ForegroundColor Green
            }
        }
        else {
            Write-Host "No coverage reports found" -ForegroundColor Yellow
        }
    }
}
else {
    Write-Host "Tests failed with exit code: $testExitCode" -ForegroundColor Red
}

Write-Host ""
exit $testExitCode
