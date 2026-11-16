$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ('capture-access-updates-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
try {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
    $executable = Join-Path $temporaryDirectory 'UpdateTests.exe'
    & $compiler /nologo /target:exe /platform:anycpu /optimize+ /utf8output "/out:$executable" /reference:System.Core.dll /reference:System.Web.Extensions.dll "$projectRoot\src\Updates.cs" "$projectRoot\src\WindowsStartup.cs" "$PSScriptRoot\UpdateTests.cs"
    if ($LASTEXITCODE -ne 0) { throw 'Updater test compilation failed.' }
    & $executable
    if ($LASTEXITCODE -ne 0) { throw 'Updater tests failed.' }
} finally {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
