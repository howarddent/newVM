<#
.SYNOPSIS
  Installs the runtime DLLs newVM needs on Windows: Intel MKL, Intel IPP,
  OpenBLAS, and FFTW3 (double + single precision).

.DESCRIPTION
  All four libraries are bound by newVM at RUNTIME via LoadLibrary/
  GetProcAddress (see CLAUDE.md's "Cross-platform library binding" section,
  and the LoadAddresses/TryInitializeCBLAS code in cblas.pas / fftw3.pas) -
  no import libraries or headers are needed to *build* newVMtest.exe, the
  four libraries just need to be discoverable DLLs at *run* time. This
  script gets them onto disk and onto PATH without requiring the full,
  multi-GB Intel oneAPI installer:

    1. Creates an isolated Python venv and `pip install`s Intel's own
       "mkl" and "ipp" runtime wheels (published by Intel Corporation on
       PyPI) into it, then copies every DLL that lands in the venv over
       to one shared libs folder. This also picks up mkl_rt's own
       dependencies (mkl_core, mkl_*_thread, libiomp5md, ...) since pip
       installs "intel-openmp" alongside "mkl" and everything lands in
       the same folder.
    2. Downloads OpenBLAS's own prebuilt Windows x64 release zip and
       copies its libopenblas.dll into the same folder, renamed to
       openblas.dll - the exact name cblas.pas's Windows CBLASLib
       constant looks for (no "lib" prefix). Deliberately not built via
       vcpkg: vcpkg's openblas port compiles from source and requires a
       full MSVC/Visual Studio C++ toolchain, which this script has no
       need to install just to obtain a runtime-loaded DLL.
    3. Downloads FFTW3's official precompiled Windows DLL zip and copies
       libfftw3-3.dll / libfftw3f-3.dll into the same folder - the exact
       names fftw3.pas's FFTWDoubleLib/FFTWSingleLib look for.
    4. Adds that folder to the current user's PATH permanently, so any
       terminal or IDE opened afterwards (including the Lazarus IDE, for
       running newVMtest.exe) can find all four libraries.

  Safe to re-run any time to update/repair the install - every step skips
  work that's already done (existing venv is reused, downloads aren't
  repeated, PATH is only appended once).

.NOTES
  Requires Python 3 (with venv+pip) discoverable on PATH.

  Does NOT install Lazarus/FPC itself, and does not regenerate
  newVMConfig.inc - re-run newvmconfigure.exe from the repo root
  afterwards (see CLAUDE.md's "newvmconfigure.lpr" section) so it picks
  up these newly-installed libraries.
#>

[CmdletBinding()]
param(
    [string]$LibsDir = (Join-Path $env:LOCALAPPDATA 'newVM\libs'),
    [string]$WorkDir = (Join-Path $env:LOCALAPPDATA 'newVM\_setup')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Assert-Command {
    param([string]$Name, [string]$Hint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "'$Name' was not found on PATH. $Hint"
    }
}

Assert-Command python "Install Python 3 from https://www.python.org/downloads/ (check 'Add python.exe to PATH' during install) and re-run this script."

New-Item -ItemType Directory -Force -Path $LibsDir | Out-Null
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# ---------------------------------------------------------------------------
# 1. MKL + IPP via pip, into a dedicated venv
# ---------------------------------------------------------------------------
Write-Step "MKL + IPP (pip runtime wheels)"

$PyEnvDir = Join-Path $WorkDir 'pyenv'
$venvPy = Join-Path $PyEnvDir 'Scripts\python.exe'
if (-not (Test-Path $venvPy)) {
    python -m venv $PyEnvDir
}

& $venvPy -m pip install --upgrade pip --quiet
& $venvPy -m pip install --upgrade mkl intel-openmp ipp

$mklDlls = Get-ChildItem -Path $PyEnvDir -Recurse -Filter '*.dll' -ErrorAction SilentlyContinue
if (-not $mklDlls) {
    throw "pip install completed but no DLLs were found under $PyEnvDir - check the pip output above."
}
$mklDlls | Copy-Item -Destination $LibsDir -Force
Write-Host "Copied $($mklDlls.Count) MKL/IPP/OpenMP DLLs into $LibsDir."

# ---------------------------------------------------------------------------
# 2. OpenBLAS (prebuilt release zip - renamed to match cblas.pas's Windows
#    CBLASLib constant, which expects "openblas.dll" with no "lib" prefix)
# ---------------------------------------------------------------------------
Write-Step "OpenBLAS (prebuilt release)"

$openblasVersion = '0.3.34'
$openblasZip     = Join-Path $WorkDir "OpenBLAS-$openblasVersion-x64.zip"
$openblasExtract = Join-Path $WorkDir "OpenBLAS-$openblasVersion-x64"
if (-not (Test-Path $openblasZip)) {
    Invoke-WebRequest -Uri "https://github.com/OpenMathLib/OpenBLAS/releases/download/v$openblasVersion/OpenBLAS-$openblasVersion-x64.zip" -OutFile $openblasZip
}
Expand-Archive -Path $openblasZip -DestinationPath $openblasExtract -Force

$openblasDll = Join-Path $openblasExtract 'bin\libopenblas.dll'
if (-not (Test-Path $openblasDll)) {
    throw "libopenblas.dll wasn't found under $openblasExtract\bin - OpenBLAS's release zip layout may have changed since this script was written."
}
Copy-Item $openblasDll (Join-Path $LibsDir 'openblas.dll') -Force
Write-Host "Copied libopenblas.dll into $LibsDir as openblas.dll."

# ---------------------------------------------------------------------------
# 3. FFTW3 (precompiled DLLs from fftw.org)
# ---------------------------------------------------------------------------
Write-Step "FFTW3 (precompiled DLLs)"

$fftwZip     = Join-Path $WorkDir 'fftw-3.3.5-dll64.zip'
$fftwExtract = Join-Path $WorkDir 'fftw-3.3.5-dll64'
if (-not (Test-Path $fftwZip)) {
    Invoke-WebRequest -Uri 'https://fftw.org/pub/fftw/fftw-3.3.5-dll64.zip' -OutFile $fftwZip
}
Expand-Archive -Path $fftwZip -DestinationPath $fftwExtract -Force

foreach ($name in 'libfftw3-3.dll', 'libfftw3f-3.dll') {
    $src = Join-Path $fftwExtract $name
    if (-not (Test-Path $src)) {
        throw "$name wasn't found in the FFTW3 zip - fftw.org's layout may have changed since this script was written."
    }
    Copy-Item $src $LibsDir -Force
}
Write-Host "Copied libfftw3-3.dll and libfftw3f-3.dll into $LibsDir."

# ---------------------------------------------------------------------------
# 4. Put LibsDir on the user's PATH permanently
# ---------------------------------------------------------------------------
Write-Step "PATH"

$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
$parts = @()
if ($userPath) { $parts = $userPath -split ';' | Where-Object { $_ -ne '' } }
if ($parts -notcontains $LibsDir) {
    [Environment]::SetEnvironmentVariable('PATH', (($parts + $LibsDir) -join ';'), 'User')
    Write-Host "Added $LibsDir to your user PATH."
} else {
    Write-Host "$LibsDir is already on your user PATH."
}
$env:PATH = "$env:PATH;$LibsDir"

Write-Step "Done"
Write-Host "All DLLs are in: $LibsDir"
Get-ChildItem $LibsDir -Filter *.dll | Select-Object -ExpandProperty Name | Sort-Object | Write-Host
Write-Host "`nOpen a NEW terminal (or restart the Lazarus IDE) before building/running newVMtest.exe, so it picks up the updated PATH."
Write-Host "Then re-run newvmconfigure.exe from the repo root to refresh newVMConfig.inc for these newly-installed libraries."
