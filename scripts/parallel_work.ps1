param(
    [ValidateSet('Status', 'Setup', 'Start', 'Integrate')]
    [string]$Mode = 'Status',
    [ValidateSet('A', 'B', 'C', 'D')]
    [string]$Role = 'A',
    [ValidateSet('codex', 'claude')]
    [string]$Client = 'codex',
    [switch]$Unified
)

$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifest = Get-Content -LiteralPath (Join-Path $sourceRoot 'docs/parallel-work/workspaces.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$mainRoot = [IO.Path]::GetFullPath($manifest.integrationWorkspace)

function Git-Text([string]$Root, [string[]]$Arguments) {
    $output = & git -C $Root @Arguments
    if ($LASTEXITCODE -ne 0) { throw ('Git failed: ' + ($Arguments -join ' ')) }
    return (($output -join [Environment]::NewLine).Trim())
}

function Same-Path([string]$Left, [string]$Right) {
    return [string]::Equals([IO.Path]::GetFullPath($Left), [IO.Path]::GetFullPath($Right), [StringComparison]::OrdinalIgnoreCase)
}

$commonGit = Git-Text $sourceRoot @('rev-parse', '--path-format=absolute', '--git-common-dir')
if (-not (Same-Path $commonGit (Join-Path $mainRoot '.git'))) { throw 'Manifest points to a different repository.' }
if ($manifest.integrationBranch -ne 'main' -or $manifest.lockRelativePath -ne '.validation-tools/ux-integration.lock') { throw 'Unexpected integration branch or lock location.' }
$roleIds = @($manifest.roles | ForEach-Object { $_.id })
if (($roleIds -join ',') -ne 'A,B,C,D') { throw 'Manifest must have exactly A, B, C, D.' }
$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $mainRoot '.worktrees'))
$workspacePrefix = $workspaceRoot + [IO.Path]::DirectorySeparatorChar
foreach ($entry in $manifest.roles) {
    $fullPath = [IO.Path]::GetFullPath($entry.path)
    if ($entry.id -ne 'A' -and -not $fullPath.StartsWith($workspacePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Worker worktree escapes .worktrees.' }
    if ($entry.branch -notmatch '^codex/[a-z0-9-]+$' -or $entry.prompt -ne ('docs/parallel-work/prompts/' + $entry.id + '.md')) { throw 'Unexpected branch or prompt.' }
}
$assigned = @($manifest.roles | Where-Object { $_.id -eq $Role })[0]
if ($Unified) {
    if ($Mode -ne 'Integrate' -or -not $manifest.unified) { throw 'Unified mode is only supported for configured integration.' }
    if ($manifest.unified.branch -notmatch '^codex/[a-z0-9-]+$') { throw 'Invalid unified branch.' }
    $assigned = [pscustomobject]@{
        id = 'Unified'; path = $manifest.unified.path; branch = $manifest.unified.branch;
        prompt = 'docs/parallel-work/prompts/A.md'
    }
}
if ($manifest.state -eq 'unified-implementation' -and $Mode -in @('Setup', 'Start')) {
    throw 'A/B/C/D implementation is now consolidated in the unified chat. Existing worktrees are preserved.'
}

function Confirm-Worktree($Entry) {
    if (-not (Test-Path -LiteralPath $Entry.path)) { throw ('Missing worktree: ' + $Entry.path) }
    if (-not (Same-Path (Git-Text $Entry.path @('rev-parse', '--show-toplevel')) $Entry.path)) { throw 'Target is not a worktree root.' }
    if (-not (Same-Path (Git-Text $Entry.path @('rev-parse', '--path-format=absolute', '--git-common-dir')) $commonGit)) { throw 'Target uses another repository.' }
    if ((Git-Text $Entry.path @('branch', '--show-current')) -ne $Entry.branch) { throw ('Wrong branch at ' + $Entry.path) }
    if (-not (Test-Path -LiteralPath (Join-Path $Entry.path $Entry.prompt))) { throw 'Prompt is missing from worktree.' }
}

function Confirm-NoOperation([string]$Root) {
    foreach ($name in @('MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply')) {
        $operationPath = Git-Text $Root @('rev-parse', '--path-format=absolute', '--git-path', $name)
        if (Test-Path -LiteralPath $operationPath) { throw ('Unfinished Git operation: ' + $operationPath) }
    }
}

if ($Mode -eq 'Setup') {
    $coordinator = $manifest.roles[0]
    Confirm-Worktree $coordinator
    if (-not (Same-Path $sourceRoot $coordinator.path)) { throw 'Setup must run from coordinator worktree.' }
    if (Git-Text $sourceRoot @('status', '--porcelain')) { throw 'Commit coordinator setup files before creating worker worktrees.' }
    Confirm-NoOperation $sourceRoot
    # Preflight every target before creating any new worktree. Never repurpose an existing branch.
    foreach ($entry in $manifest.roles | Where-Object { $_.id -ne 'A' }) {
        if (Test-Path -LiteralPath $entry.path) { Confirm-Worktree $entry }
        elseif (Git-Text $sourceRoot @('branch', '--list', $entry.branch)) { throw ('Branch already exists elsewhere: ' + $entry.branch) }
    }
    $seedCommit = Git-Text $sourceRoot @('rev-parse', 'HEAD')
    foreach ($entry in $manifest.roles | Where-Object { $_.id -ne 'A' }) {
        if (-not (Test-Path -LiteralPath $entry.path)) {
            & git -C $sourceRoot worktree add -b $entry.branch $entry.path $seedCommit
            if ($LASTEXITCODE -ne 0) { throw 'Worktree creation failed. Preserve completed targets and inspect before retry.' }
        }
        Confirm-Worktree $entry
    }
    Write-Output ('Ready. New worktrees use seed ' + $seedCommit + '; existing worktrees preserved.')
}

if ($Mode -eq 'Status' -or $Mode -eq 'Setup') {
    foreach ($entry in $manifest.roles) {
        Confirm-Worktree $entry
        $commit = Git-Text $entry.path @('rev-parse', '--short', 'HEAD')
        $changes = Git-Text $entry.path @('status', '--short')
        Write-Output ($entry.id + ' | ' + $entry.name + ' | ' + $entry.branch + ' | ' + $commit + ' | ' + $entry.path)
        if ($changes) { Write-Output $changes }
    }
    Write-Output ('Target: ' + $mainRoot + ' [' + (Git-Text $mainRoot @('branch', '--show-current')) + ']')
    foreach ($commandName in @('codex', 'claude', 'node', 'python', 'swift', 'xcodebuild')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { Write-Output ($commandName + ': ' + $command.Source) }
        else { Write-Output ($commandName + ': not on PATH') }
    }
    Write-Output 'Executable discovery does not confirm authentication or a working runtime.'
    return
}

if ($Mode -eq 'Start') {
    Confirm-Worktree $assigned
    $command = Get-Command $Client -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { throw ($Client + ' is not installed/on PATH. Open assigned folder and paste the prompt in your app.') }
    Write-Output (Get-Content -LiteralPath (Join-Path $assigned.path $assigned.prompt) -Raw -Encoding UTF8)
    Push-Location -LiteralPath $assigned.path
    try {
        if ($Client -eq 'codex') { & $command.Source --cd $assigned.path }
        else { & $command.Source }
        if ($LASTEXITCODE -ne 0) { throw ('Client exited with code ' + $LASTEXITCODE) }
    } finally { Pop-Location }
    return
}

Confirm-Worktree $assigned
if (-not (Same-Path $sourceRoot $assigned.path)) { throw 'Run Integrate from your assigned worktree script.' }
if (Git-Text $sourceRoot @('status', '--porcelain')) { throw 'Source has uncommitted changes. Commit only your files first.' }
Confirm-NoOperation $sourceRoot
$sourceCommit = Git-Text $sourceRoot @('rev-parse', 'HEAD')
$lockDirectory = Join-Path $mainRoot '.validation-tools'
[IO.Directory]::CreateDirectory($lockDirectory) | Out-Null
$lockPath = Join-Path $lockDirectory 'ux-integration.lock'
$lockStream = $null
try {
    $lockStream = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
} catch [IO.IOException] { throw ('Integration lock busy/unavailable; preserve owner lock: ' + $lockPath) }
try {
    $owner = [Text.Encoding]::UTF8.GetBytes(($assigned.branch + ' ' + $sourceCommit + ' pid=' + $PID))
    $lockStream.Write($owner, 0, $owner.Length)
    $lockStream.Flush()
    if ((Git-Text $mainRoot @('branch', '--show-current')) -ne $manifest.integrationBranch) { throw 'Original workspace is not on main.' }
    Confirm-NoOperation $mainRoot
    if (Git-Text $mainRoot @('status', '--porcelain', '--untracked-files=no')) { throw 'Main has tracked uncommitted changes; preserve them and retry after owner commits.' }
    Git-Text $sourceRoot @('diff', '--check', 'main...HEAD') | Out-Null
    if ((Git-Text $sourceRoot @('rev-parse', 'HEAD')) -ne $sourceCommit) { throw 'Source HEAD changed during preparation.' }
    & git -C $mainRoot -c user.name=Codex -c user.email=codex@users.noreply.github.com merge --no-edit $sourceCommit
    if ($LASTEXITCODE -ne 0) { throw 'Merge incomplete. Preserve conflict state, resolve before another integration.' }
    Git-Text $mainRoot @('diff', '--check') | Out-Null
    Write-Output ('Integrated ' + $assigned.branch + ' (' + $sourceCommit + ') into local main. No push or deployment.')
} finally {
    $lockStream.Dispose()
    Remove-Item -LiteralPath $lockPath
}
