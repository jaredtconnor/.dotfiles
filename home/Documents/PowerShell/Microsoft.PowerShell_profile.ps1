. $env:USERPROFILE\.config\powershell\user_profile.ps1

# mise (cached activation)
$_miseCache = Join-Path $env:LOCALAPPDATA "mise-activate-$($PSVersionTable.PSVersion).ps1"
# Concurrent shell starts (terminal tab restore) race on this file: Windows refuses
# to open it while another shell is replacing it, and refuses the replace while
# another shell has it open. Serialize the refresh and the read under one mutex;
# the 10s timeout keeps a hung `mise activate` from blocking every new shell.
$_miseLock = [System.Threading.Mutex]::new($false, 'Local\mise-activate-cache')
try { $_miseOwned = $_miseLock.WaitOne(10000) } catch [System.Threading.AbandonedMutexException] { $_miseOwned = $true }
$_miseScript = $null
try {
    if (-not (Test-Path $_miseCache) -or
        (Get-Date) - (Get-Item $_miseCache).LastWriteTime -gt [timespan]::FromHours(12)) {
        $miseExe = Get-Command mise -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
        if ($miseExe) {
            # Temp file then rename, so a shell killed mid-write can't leave a truncated cache.
            $_miseTmp = "$_miseCache.$PID.tmp"
            & $miseExe activate pwsh | Set-Content $_miseTmp -Encoding utf8NoBOM
            Move-Item $_miseTmp $_miseCache -Force
        }
    }
    if (Test-Path $_miseCache) { $_miseScript = [System.IO.File]::ReadAllText($_miseCache) }
} finally {
    if ($_miseOwned) { $_miseLock.ReleaseMutex() }
    $_miseLock.Dispose()
}
# Run outside the lock so shells don't queue behind each other's mise hook-env.
if ($_miseScript) { . ([scriptblock]::Create($_miseScript)) }

if (Get-Command git-wt -ErrorAction SilentlyContinue) { Invoke-Expression (& git-wt config shell init powershell | Out-String) }
