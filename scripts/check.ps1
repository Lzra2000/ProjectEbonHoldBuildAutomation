#Requires -Version 5.0
<#
.SYNOPSIS
  Windows-friendly wrapper around scripts/check.sh (Git Bash).

.DESCRIPTION
  Locates Git Bash and invokes the same check suite CI runs. Prefer this from
  PowerShell instead of hand-rolling lua paths.

.EXAMPLE
  .\scripts\check.ps1
  .\scripts\check.ps1 --full
  .\scripts\check.ps1 --only architecture
  .\scripts\check.ps1 -VerboseCheck --only tests
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $CheckArgs,

    [switch] $Full,
    [string] $Only,
    [Alias('VerboseCheck')]
    [switch] $CheckVerbose
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

function Find-GitBash {
    $candidates = @(
        $env:EBB_BASH,
        (Join-Path ${env:ProgramFiles} 'Git\bin\bash.exe'),
        (Join-Path ${env:ProgramFiles} 'Git\usr\bin\bash.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    if ($candidates) { return $candidates[0] }

    $cmd = Get-Command bash -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Ensure-LuaOnPath {
    # Prefer an already-working lua5.1. Otherwise prepend repo .cache/bin if present
    # (populated by copying CI-like binaries, or a local cache — not committed).
    $lua = Get-Command lua5.1 -ErrorAction SilentlyContinue
    if ($lua) { return }

    $cacheBin = Join-Path $repoRoot '.cache\bin'
    $cacheLua = Join-Path $cacheBin 'lua5.1.exe'
    $cacheLuaNoExt = Join-Path $cacheBin 'lua5.1'
    if (Test-Path -LiteralPath $cacheLua) {
        $env:Path = "$cacheBin;$env:Path"
        return
    }
    if (Test-Path -LiteralPath $cacheLuaNoExt) {
        $env:Path = "$cacheBin;$env:Path"
        return
    }
}

$bash = Find-GitBash
if (-not $bash) {
    Write-Error @"
Git Bash not found. Install Git for Windows, or set EBB_BASH to bash.exe.

Alternatively run under WSL:
  wsl -e sh scripts/check.sh @CheckArgs
See docs/dev-testing.md.
"@
}

Ensure-LuaOnPath

$forward = New-Object System.Collections.Generic.List[string]
if ($Full) { [void]$forward.Add('--full') }
if ($CheckVerbose) { [void]$forward.Add('--verbose') }
if ($Only) {
    [void]$forward.Add('--only')
    [void]$forward.Add($Only)
}
foreach ($a in $CheckArgs) {
    if ($null -ne $a -and $a -ne '') { [void]$forward.Add($a) }
}

$checkSh = Join-Path $repoRoot 'scripts/check.sh'
# Convert Windows path to a form Git Bash understands (/c/Users/...).
$bashRepo = & $bash -lc "cygpath -u '$($repoRoot -replace '''', '''\''')'" 2>$null
if (-not $bashRepo) {
    # Fallback when cygpath is unavailable: rewrite drive letter.
    if ($repoRoot -match '^([A-Za-z]):\\(.*)$') {
        $bashRepo = '/' + $Matches[1].ToLowerInvariant() + '/' + ($Matches[2] -replace '\\', '/')
    } else {
        $bashRepo = $repoRoot -replace '\\', '/'
    }
}

$argLine = ($forward | ForEach-Object {
    if ($_ -match '\s') { "'" + ($_ -replace "'", "'\''") + "'" } else { $_ }
}) -join ' '

Write-Host "Using bash: $bash"
Write-Host "Repo:       $bashRepo"
if ($forward.Count -gt 0) {
    Write-Host "Args:       $($forward -join ' ')"
}

# Export Path so lua5.1/luac5.1 resolved inside bash see the same prepend.
$env:EBB_LOG_DIR = if ($env:EBB_LOG_DIR) { $env:EBB_LOG_DIR } else { '.cache/check-logs' }

$cacheBin = Join-Path $repoRoot '.cache\bin'
$pathPrefix = ''
if (Test-Path -LiteralPath $cacheBin) {
    if ($cacheBin -match '^([A-Za-z]):\\(.*)$') {
        $pathPrefix = '/' + $Matches[1].ToLowerInvariant() + '/' + ($Matches[2] -replace '\\', '/')
    }
}

$bashCmd = if ($pathPrefix) {
    "export PATH='$pathPrefix':`"\$PATH`" && cd '$bashRepo' && sh scripts/check.sh $argLine"
} else {
    "cd '$bashRepo' && sh scripts/check.sh $argLine"
}
& $bash -lc $bashCmd
exit $LASTEXITCODE
