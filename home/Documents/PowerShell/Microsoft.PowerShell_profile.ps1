. $env:USERPROFILE\.config\powershell\user_profile.ps1

# mise (cached activation)
$_miseCache = Join-Path $env:LOCALAPPDATA "mise-activate-$($PSVersionTable.PSVersion).ps1"
if (-not (Test-Path $_miseCache) -or
    (Get-Date) - (Get-Item $_miseCache).LastWriteTime -gt [timespan]::FromHours(12)) {
    $miseExe = Get-Command mise -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if ($miseExe) {
        # Write to a per-process temp file, then rename: concurrent shell starts
        # otherwise interleave writes and leave a truncated, unparseable cache.
        $_miseTmp = "$_miseCache.$PID.tmp"
        & $miseExe activate pwsh | Set-Content $_miseTmp -Encoding utf8NoBOM
        Move-Item $_miseTmp $_miseCache -Force
    }
}
if (Test-Path $_miseCache) { . $_miseCache }

if (Get-Command git-wt -ErrorAction SilentlyContinue) { Invoke-Expression (& git-wt config shell init powershell | Out-String) }
