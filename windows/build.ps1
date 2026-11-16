param([string]$OutDir = (Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference = 'Stop'
$taskOutput = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Path $taskOutput,(Join-Path $taskOutput 'bin'),(Join-Path $taskOutput 'tests'),(Join-Path $PSScriptRoot 'obj') -Force | Out-Null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) { throw 'Install Visual Studio C++ build tools with x86/x64 and Windows SDK.' }
$vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvarsall.bat'
foreach ($arch in @('x86','x64')) {
    $suffix = if ($arch -eq 'x86') { '32' } else { '64' }
    $objectDir = Join-Path $PSScriptRoot "obj\$arch"
    New-Item -ItemType Directory -Path $objectDir -Force | Out-Null
    $export = if ($arch -eq 'x86') { '/EXPORT:CaptureHook=_CaptureHook@12' } else { '/EXPORT:CaptureHook' }
    $commands = @(
        '@echo off',
        ('call "{0}" {1} >nul' -f $vcvars,$arch),
        'if errorlevel 1 exit /b 1',
        ('cd /d "{0}"' -f $objectDir),
        ('cl /nologo /std:c++17 /O2 /MT /W4 /utf-8 /DUNICODE /D_UNICODE /DWINVER=0x0A00 /D_WIN32_WINNT=0x0A00 /LD "{0}\src\hook.cpp" /link user32.lib {1} /OUT:"{2}\bin\CaptureHook{3}.dll"' -f $PSScriptRoot,$export,$taskOutput,$suffix),
        'if errorlevel 1 exit /b 1',
        ('cl /nologo /std:c++17 /O2 /MT /W4 /utf-8 /DUNICODE /D_UNICODE /DWINVER=0x0A00 /D_WIN32_WINNT=0x0A00 "{0}\src\helper.cpp" /link user32.lib bcrypt.lib /OUT:"{1}\bin\CaptureHelper{2}.exe"' -f $PSScriptRoot,$taskOutput,$suffix),
        'if errorlevel 1 exit /b 1',
        ('cl /nologo /std:c++17 /O2 /MT /W4 /utf-8 /DUNICODE /D_UNICODE /DWINVER=0x0A00 /D_WIN32_WINNT=0x0A00 "{0}\src\demo.cpp" /link user32.lib gdi32.lib /SUBSYSTEM:WINDOWS /OUT:"{1}\tests\Demo{2}.exe"' -f $PSScriptRoot,$taskOutput,$suffix),
        'if errorlevel 1 exit /b 1'
    )
    $batch = Join-Path $objectDir 'compile.cmd'
    [System.IO.File]::WriteAllLines($batch,$commands,[System.Text.Encoding]::Default)
    & $env:ComSpec /d /c $batch
    if ($LASTEXITCODE -ne 0) { throw "Native compilation failed: $arch" }
}
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
& $csc /nologo /target:winexe /platform:anycpu /optimize+ /utf8output "/win32manifest:$PSScriptRoot\src\app.manifest" "/out:$taskOutput\CaptureAccess.exe" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Core.dll /reference:System.Web.Extensions.dll "$PSScriptRoot\src\App.cs"
if ($LASTEXITCODE -ne 0) { throw 'GUI compilation failed.' }
Write-Output "Build complete: $taskOutput"
