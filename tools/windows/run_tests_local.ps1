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

# Quality gates (industry-standard McCabe guidance)
$coverageThreshold = 90
$maxComplexityOverall = 15
$maxComplexityPerFile = 15

# Get script directory and project root
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
$dockerfilePath = Join-Path $projectRoot "docker/Dockerfile.test"

# Build Docker  image unless --NoBuild is specified
if (-not $NoBuild) {
    Write-Host "[1/3] Building test Docker image..." -ForegroundColor Yellow
    docker build -t rpi-maintenance-test -f "$dockerfilePath" "$projectRoot"
    
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
        -v "${projectRoot}/assets:/home/pi/assets" `
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
        Write-Host "  Coverage and Complexity Summary" -ForegroundColor Cyan
        Write-Host "==================================================" -ForegroundColor Cyan
        
        $coberturaFile = Join-Path $coverageDir "cobertura.xml"
        if (Test-Path $coberturaFile) {
            Write-Host "Coverage report found: $coberturaFile" -ForegroundColor White
            Write-Host ""

            [xml]$coverageXml = Get-Content $coberturaFile
            $overallPercent = [math]::Round(([double]$coverageXml.coverage.'line-rate') * 100, 2)
            $overallComplexity = [math]::Round([double]$coverageXml.coverage.complexity, 2)

            Write-Host "  Overall Merged Coverage: $overallPercent%" -ForegroundColor Cyan
            Write-Host "  Overall Complexity: $overallComplexity" -ForegroundColor Cyan

            # Display per-file coverage and complexity
            Write-Host ""
            Write-Host "  File Coverage and Complexity:" -ForegroundColor White

            $complexityOffenders = @()

            $packages = @($coverageXml.coverage.packages.package)
            foreach ($package in $packages) {
                $classes = @($package.classes.class)
                foreach ($class in $classes) {
                    $fileName = $class.filename
                    $fileCoverage = [math]::Round(([double]$class.'line-rate') * 100, 2)
                    $fileComplexity = [math]::Round([double]$class.complexity, 2)

                    $lines = @($class.lines.line)
                    $totalLines = $lines.Count
                    $coveredLines = @($lines | Where-Object { $_.hits -ne '0' }).Count

                    if ($fileComplexity -gt $maxComplexityPerFile) {
                        $complexityOffenders += "${fileName}: ${fileComplexity}"
                    }

                    Write-Host "    - ${fileName} : ${fileCoverage}% (${coveredLines}/${totalLines} lines), complexity=${fileComplexity}" -ForegroundColor Gray
                }
            }
            Write-Host ""
            
            Write-Host "  Open coverage/index.html in a browser for detailed report" -ForegroundColor Yellow
            
            # Enforce coverage threshold
            if ($overallPercent -lt $coverageThreshold) {
                Write-Host ""
                Write-Host "CRITICAL: Overall coverage ($overallPercent%) is below the $coverageThreshold% threshold!" -ForegroundColor Red
                $testExitCode = 1
            }
            else {
                Write-Host ""
                Write-Host "SUCCESS: Coverage threshold ($coverageThreshold%) met!" -ForegroundColor Green
            }

            # Enforce complexity thresholds
            if ($overallComplexity -gt $maxComplexityOverall) {
                Write-Host "CRITICAL: Overall complexity ($overallComplexity) exceeds max $maxComplexityOverall!" -ForegroundColor Red
                $testExitCode = 1
            }
            else {
                Write-Host "SUCCESS: Overall complexity ($overallComplexity) is within max $maxComplexityOverall." -ForegroundColor Green
            }

            if ($complexityOffenders.Count -gt 0) {
                Write-Host "CRITICAL: Per-file complexity threshold exceeded (max=$maxComplexityPerFile):" -ForegroundColor Red
                foreach ($offender in $complexityOffenders) {
                    Write-Host "  - $offender" -ForegroundColor Red
                }
                $testExitCode = 1
            }
            else {
                Write-Host "SUCCESS: Per-file complexity threshold (max=$maxComplexityPerFile) met." -ForegroundColor Green
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
