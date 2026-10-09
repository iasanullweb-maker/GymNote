param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('codex/ux-coordinator', 'codex/ux-capture', 'codex/ux-scenarios', 'codex/ux-runner')]
    [string]$SourceBranch
)

$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Get-GitText([string]$Repository, [string[]]$Arguments) {
    $output = & git -C $Repository @Arguments
    if ($LASTEXITCODE -ne 0) { throw ('Git command failed: ' + ($Arguments -join ' ')) }
    return (($output -join [Environment]::NewLine).Trim())
}

$commonGit = Get-GitText $sourceRoot @('rev-parse', '--path-format=absolute', '--git-common-dir')
$mainRoot = Split-Path -Parent $commonGit
$currentBranch = Get-GitText $sourceRoot @('branch', '--show-current')
if ($currentBranch -ne $SourceBranch) { throw ('Run from the assigned source worktree. Current branch: ' + $currentBranch) }
if (Get-GitText $sourceRoot @('status', '--porcelain')) { throw 'Source worktree has uncommitted changes. Review and commit only your task files first.' }
$sourceCommit = Get-GitText $sourceRoot @('rev-parse', 'HEAD')

$lockDirectory = Join-Path $mainRoot '.validation-tools'
[IO.Directory]::CreateDirectory($lockDirectory) | Out-Null
$lockPath = Join-Path $lockDirectory 'ux-integration.lock'
try {
    $lockStream = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
} catch [IO.IOException] {
    throw ('Another integration owns the lock, or the lock path is unavailable. Do not delete it: ' + $lockPath)
}

try {
    $owner = [Text.Encoding]::UTF8.GetBytes(($SourceBranch + ' ' + $sourceCommit + ' pid=' + $PID))
    $lockStream.Write($owner, 0, $owner.Length)
    $lockStream.Flush()
    if ((Get-GitText $mainRoot @('branch', '--show-current')) -ne 'main') { throw 'Original workspace is not on main. Preserve its state and coordinate integration.' }
    if (Get-GitText $mainRoot @('status', '--porcelain', '--untracked-files=no')) { throw 'Original workspace has uncommitted changes to tracked files. Preserve them; no reset or stash is performed.' }
    # Untracked files are preserved. Git merge itself refuses any overwrite collision.
    Get-GitText $sourceRoot @('diff', '--check', 'main...HEAD') | Out-Null
    if ((Get-GitText $sourceRoot @('rev-parse', 'HEAD')) -ne $sourceCommit) { throw 'Source HEAD changed during integration preparation.' }
    & git -C $mainRoot -c user.name=Codex -c user.email=codex@users.noreply.github.com merge --no-edit $sourceCommit
    if ($LASTEXITCODE -ne 0) { throw 'Merge did not complete. Preserve any conflict state; inspect and resolve it before another integration.' }
    Get-GitText $mainRoot @('diff', '--check') | Out-Null
    Write-Output ('Integrated ' + $SourceBranch + ' (' + $sourceCommit + ') into local main.')
    Write-Output 'No remote push or deployment was performed.'
} finally {
    $lockStream.Dispose()
    Remove-Item -LiteralPath $lockPath
}
