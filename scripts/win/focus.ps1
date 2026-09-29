# yo-nudge-me Windows focus check.
# Prints one word: focused | unfocused | headless | unknown.

$ErrorActionPreference = 'Stop'
try {
    Add-Type -Namespace YoNudge -Name Win32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
'@

    $hwnd = [YoNudge.Win32]::GetForegroundWindow()
    if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'unknown'; exit 0 }

    [uint32]$fg = 0
    [void][YoNudge.Win32]::GetWindowThreadProcessId($hwnd, [ref]$fg)
    if ($fg -eq 0) { Write-Output 'unknown'; exit 0 }

    # One snapshot of the process table: pid -> (parent pid, name)
    $parent = @{}
    $name = @{}
    Get-CimInstance -ClassName Win32_Process -Property ProcessId, ParentProcessId, Name | ForEach-Object {
        $parent[[int]$_.ProcessId] = [int]$_.ParentProcessId
        $name[[int]$_.ProcessId] = [string]$_.Name
    }

    $fgName = $name[[int]$fg]
    $p = [int]$PID
    $seen = @{}
    $n = 0
    $anyWindow = $false
    while ($p -gt 0 -and $n -lt 40 -and -not $seen.ContainsKey($p)) {
        if ($p -eq [int]$fg) { Write-Output 'focused'; exit 0 }
        if ($fgName -and $name.ContainsKey($p) -and $name[$p] -eq $fgName) { Write-Output 'focused'; exit 0 }
        if (-not $anyWindow) {
            $proc = Get-Process -Id $p -ErrorAction SilentlyContinue
            if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) { $anyWindow = $true }
        }
        $seen[$p] = $true
        if (-not $parent.ContainsKey($p)) { break }
        $p = $parent[$p]
        $n++
    }
    if ($anyWindow) { Write-Output 'unfocused' } else { Write-Output 'headless' }
}
catch {
    Write-Output 'unknown'
}
exit 0
