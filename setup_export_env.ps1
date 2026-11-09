#Requires -Version 5.1
<#
.SYNOPSIS
  Offline PyTorch-to-ONNX export environment for Florence-2-base.
.DESCRIPTION
  1. Removes broken .venv/venv            (Python 3.14 has no compatible wheels)
  2. Detects Python 3.11/3.12 via py launcher
  3. Installs Python 3.12 via winget if missing
  4. Re-creates a clean venv, upgrades pip/setuptools/wheel
  5. Installs CPU torch/torchvision (PyTorch index) + transformers/onnx/... (PyPI)
     NOTE: transformers is NOT on download.pytorch.org -> separate pip call.
  6. Verifies every required package imports cleanly.
#>
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

Write-Host '== 1. Remove stale virtual environments ==' -ForegroundColor Cyan
# Drop any active venv from the current session so its python.exe is not locked
# (we never rely on "python" from PATH inside this script either)
if ($env:VIRTUAL_ENV) {
    Write-Host "Active venv detected and deactivated: $env:VIRTUAL_ENV"
    deactivate 2>$null
    Remove-Item Env:VIRTUAL_ENV -ErrorAction SilentlyContinue
}
foreach ($dir in '.venv', 'venv') {
    if (Test-Path -LiteralPath $dir) {
        Write-Host "Removing $dir ..."
        Remove-Item -LiteralPath $dir -Recurse -Force
    }
}

Write-Host "`n== 2. Installed Python versions (py --list) ==" -ForegroundColor Cyan
py --list | ForEach-Object { Write-Host $_ }

Write-Host "`n== 3. Ensure Python 3.11 or 3.12 is available ==" -ForegroundColor Cyan
$pyList = (py --list) 2>$null | Out-String
$iSpy = @()
foreach ($v in '3.11', '3.12') {
    if ($pyList -match [regex]::Escape("-V:$v") -or $pyList -match [regex]::Escape($v)) {
        $iSpy += $v
    }
}

$pyCmd = $null
if ($iSpy.Count -gt 0) {
    $ver = ($iSpy | Sort-Object -Descending)[0]
    Write-Host "Found Python $ver via py launcher."
    $pyCmd = "py -$ver"
} else {
    Write-Warning 'No Python 3.11/3.12 found. Installing Python 3.12 via winget (per-user, no admin needed)...'
    winget install --id Python.Python.3.12 --scope user --silent `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget failed to install Python 3.12. Install it manually from https://www.python.org/downloads/release/python-31210/" }

    # Re-resolve py launcher; fall back to the direct exe path if registry hasn't refreshed
    $exe = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe" -ErrorAction SilentlyContinue |
           Select-Object -First 1 -ExpandProperty FullName
    if (-not $exe) {
        # py launcher refresh attempt
        $candidates = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python" -Directory -ErrorAction SilentlyContinue
        foreach ($c in $candidates) {
            $p = Join-Path $c.FullName 'python.exe'
            if (Test-Path $p) { $exe = $p; break }
        }
    }
    if (-not $exe) { throw 'Python 3.12 installed but python.exe not found under %LOCALAPPDATA%\Programs\Python.' }
    Write-Host "Using interpreter: $exe"
}

if ($pyCmd) {
    cmd /c "$pyCmd --version" | ForEach-Object { Write-Host "Verified: $_" }
}

Write-Host "`n== 4. Create clean virtual environment ==" -ForegroundColor Cyan
if ($pyCmd) {
    cmd /c "$pyCmd -m venv venv"
} else {
    & $exe -m venv venv
}
if (-not (Test-Path '.\venv\Scripts\python.exe')) { throw 'venv creation failed.' }
Write-Host 'venv created.'

Write-Host "`n== 5. Upgrade pip / setuptools / wheel ==" -ForegroundColor Cyan
& .\venv\Scripts\python.exe -m pip install --upgrade pip setuptools wheel --quiet
& .\venv\Scripts\python.exe -m pip --version

Write-Host "`n== 6. Install packages ==" -ForegroundColor Cyan
# 6a. CPU wheels of torch + torchvision MUST come from the PyTorch index
& .\venv\Scripts\python.exe -m pip install torch torchvision `
    --index-url https://download.pytorch.org/whl/cpu
if ($LASTEXITCODE -ne 0) { throw 'torch/torchvision install failed.' }

# 6b. Everything else comes from PyPI (transformers is NOT on the torch index!)
& .\venv\Scripts\python.exe -m pip install transformers onnx onnxruntime pillow einops
if ($LASTEXITCODE -ne 0) { throw 'transformers/onnx/onnxruntime/pillow/einops install failed.' }

Write-Host "`n== 7. Verify imports ==" -ForegroundColor Cyan
$verify = @'
import importlib, sys
print(f"Python  {sys.version.split()[0]}  ({sys.executable})")
required = {
    "torch":        "torch",
    "torchvision":  "torchvision",
    "transformers": "transformers",
    "onnx":         "onnx",
    "onnxruntime":  "onnxruntime",
    "PIL":          "pillow",
    "einops":       "einops",
}
failed = []
for mod, pkg in required.items():
    try:
        m = importlib.import_module(mod)
        v  = getattr(m, "__version__", "n/a")
        print(f"OK  {mod:<13} {v}")
    except Exception as e:
        failed.append(pkg)
        print(f"FAIL {mod}: {e}")
if failed:
    print(f"MISSING: {failed}")
    sys.exit(1)
import torch
print("CUDA available (expected False on CPU build):", torch.cuda.is_available())
print("All imports clean.")
'@
$verify | Set-Content -LiteralPath .\venv\verify_imports.py -Encoding UTF8
& .\venv\Scripts\python.exe .\venv\verify_imports.py
if ($LASTEXITCODE -ne 0) { throw 'Import verification FAILED.' }

Write-Host "`nSUCCESS. Activate with:  .\venv\Scripts\Activate.ps1" -ForegroundColor Green
