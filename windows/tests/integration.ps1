param([string]$Root = (Join-Path $PSScriptRoot '..\dist'))
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($Root)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class CaptureTestNative {
  [DllImport("user32.dll",SetLastError=true)] public static extern bool GetWindowDisplayAffinity(IntPtr h,out uint a);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
  [DllImport("kernel32.dll")] public static extern bool GetProcessTimes(IntPtr h,out long a,out long b,out long c,out long d);
}
'@
$testResults = [Collections.Generic.List[string]]::new()
$owned = [Collections.Generic.List[Diagnostics.Process]]::new()
function Check([bool]$value,[string]$message) {
    if(-not $value) { throw "FAIL: $message" }
    $testResults.Add("PASS: $message")
}
function Fixture([string]$arch,[string]$arguments='') {
    $start=[Diagnostics.ProcessStartInfo]::new((Join-Path $Root "tests\Demo$arch.exe"),$arguments)
    $start.UseShellExecute=$false
    $process=[Diagnostics.Process]::Start($start)
    $owned.Add($process)
    if(-not $process.WaitForInputIdle(5000)) { throw 'Fixture did not start' }
    for($attempt=0;$attempt -lt 30;$attempt++) {
        $process.Refresh()
        if($process.MainWindowHandle -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 100
    }
    if($process.MainWindowHandle -eq [IntPtr]::Zero) { throw 'Fixture window missing' }
    [long]$created=0; [long]$exit=0; [long]$kernel=0; [long]$user=0
    if(-not [CaptureTestNative]::GetProcessTimes($process.Handle,[ref]$created,[ref]$exit,[ref]$kernel,[ref]$user)) { throw 'Cannot identify fixture' }
    return @{ Process=$process; Window=$process.MainWindowHandle; Created=$created; Arch=$arch }
}
function Flag($fixture) {
    [uint32]$value=0
    if(-not [CaptureTestNative]::GetWindowDisplayAffinity($fixture.Window,[ref]$value)) { throw 'Cannot read display affinity' }
    return $value
}
function Apply($fixture,[uint32]$value,[string]$helperArch=$fixture.Arch,[long]$created=$fixture.Created,[long]$targetPid=$fixture.Process.Id) {
    $arguments='--set {0} {1} {2} {3}' -f $fixture.Window.ToInt64(),$targetPid,$created,$value
    $start=[Diagnostics.ProcessStartInfo]::new((Join-Path $Root "bin\CaptureHelper$helperArch.exe"),$arguments)
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.RedirectStandardOutput=$true
    $helper=[Diagnostics.Process]::Start($start)
    $read=$helper.StandardOutput.ReadToEndAsync()
    if(-not $helper.WaitForExit(6000)) { $helper.Kill(); throw 'Helper hung' }
    $output=$read.GetAwaiter().GetResult()
    $helper.Dispose()
    return $output | ConvertFrom-Json
}
try {
    $one=Fixture '64'
    $two=Fixture '32'
    Check ((Flag $one) -eq 17) 'x64 fixture starts protected (17)'
    Check ((Flag $two) -eq 17) 'x86 fixture starts protected (17)'
    foreach($fixture in @($one,$two)) {
        $r=Apply $fixture 0
        Check ($r.status -eq 'ok' -and $r.ack -eq 1 -and $r.before -eq 17 -and $r.after -eq 0 -and $r.changed -eq 1) "x$($fixture.Arch) in-process disable acknowledged and verified"
        Check ((Flag $fixture) -eq 0) "x$($fixture.Arch) externally reads 0 after disable"
        if($fixture.Arch -eq '64') { Check ((Flag $two) -eq 17) 'unselected process stays protected' }
        $r=Apply $fixture 17
        Check ($r.status -eq 'ok' -and (Flag $fixture) -eq 17) "x$($fixture.Arch) restores 17"
        $r=Apply $fixture 1
        Check ($r.status -eq 'ok' -and (Flag $fixture) -eq 1) "x$($fixture.Arch) supports WDA_MONITOR (1)"
        $r=Apply $fixture 0
        Check ($r.status -eq 'ok' -and $r.before -eq 1 -and (Flag $fixture) -eq 0) "x$($fixture.Arch) clears WDA_MONITOR"
        $r=Apply $fixture 0
        Check ($r.status -eq 'ok' -and $r.changed -eq 0 -and $r.known -eq 1) "x$($fixture.Arch) already-clear operation is idempotent"
        $r=Apply $fixture 17
        Check ($r.status -eq 'ok') "x$($fixture.Arch) final restoration succeeds"
    }
    $r=Apply $one 0 '32'
    Check ($r.status -eq 'architecture' -and (Flag $one) -eq 17) 'wrong helper architecture rejected without changing target'
    $r=Apply $one 0 '64' ($one.Created + 1)
    Check ($r.status -eq 'process_changed' -and (Flag $one) -eq 17) 'stale process identity rejected without change'
    $r=Apply $one 0 '64' $one.Created ($one.Process.Id + 1)
    Check ($r.status -eq 'window_changed' -and (Flag $one) -eq 17) 'mismatched PID rejected without change'
    $r=Apply $one 2
    Check ($r.status -eq 'arguments' -and (Flag $one) -eq 17) 'unsupported affinity argument rejected'
    $repeat=Fixture '64' '--repeat'
    $r=Apply $repeat 0
    Check ($r.status -eq 'ok') 'self-reprotecting fixture can be cleared'
    Start-Sleep -Milliseconds 900
    Check ((Flag $repeat) -eq 17) 'self-reprotection is observable (periodic mode is not a permanent block)'
    $r=Apply $repeat 0
    Check ($r.status -eq 'ok' -and $r.after -eq 0) 'periodic reapplication clears renewed protection'
    Check (-not $one.Process.HasExited -and -not $two.Process.HasExited) 'fixtures remain running after repeated operations'
} finally {
    foreach($process in $owned) {
        if(-not $process.HasExited) {
            [void]$process.CloseMainWindow()
            if(-not $process.WaitForExit(2500)) { $process.Kill() }
        }
        $process.Dispose()
    }
    $testResults | Write-Output
}
