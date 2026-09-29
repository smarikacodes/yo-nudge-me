# yo-nudge-me Windows playback: play.ps1 -Path sound.wav -Volume 0.5
# Tries WPF MediaPlayer (volume control), falls back to SoundPlayer (full volume).

param(
    [Parameter(Mandatory = $true)][string]$Path,
    [double]$Volume = 0.5
)

$ErrorActionPreference = 'SilentlyContinue'
if (-not (Test-Path -LiteralPath $Path)) { exit 0 }
if ($Volume -lt 0) { $Volume = 0 }
if ($Volume -gt 1) { $Volume = 1 }

$played = $false
try {
    Add-Type -AssemblyName PresentationCore
    $player = New-Object System.Windows.Media.MediaPlayer
    $player.Open([Uri](Resolve-Path -LiteralPath $Path).Path)

    # Wait until the file is opened and its length is known (up to 3 s).
    $deadline = (Get-Date).AddSeconds(3)
    while (-not $player.NaturalDuration.HasTimeSpan -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 50
    }

    if ($player.NaturalDuration.HasTimeSpan) {
        $player.Volume = $Volume
        $player.Play()
        $ms = [int]$player.NaturalDuration.TimeSpan.TotalMilliseconds + 300
        Start-Sleep -Milliseconds $ms
        $player.Close()
        $played = $true
    }
    else {
        $player.Close()
    }
}
catch { }

if (-not $played) {
    try {
        $sp = New-Object System.Media.SoundPlayer $Path
        $sp.PlaySync()
    }
    catch { }
}
exit 0
