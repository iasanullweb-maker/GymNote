$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Invoke-Git([string[]]$Arguments) {
    $output = & git -C $repository @Arguments
    if ($LASTEXITCODE -ne 0) { throw ('Git command failed: ' + ($Arguments -join ' ')) }
    return $output
}

if ((Invoke-Git @('branch', '--show-current')) -ne 'main') { throw 'Run setup from the original main workspace.' }
$commonGit = ((Invoke-Git @('rev-parse', '--path-format=absolute', '--git-common-dir')) -join '')
if ([IO.Path]::GetFullPath((Split-Path -Parent $commonGit)) -ne $repository) { throw 'Setup must run in the original repository, not a linked worktree.' }

$ownedFiles = @(
    '.gitignore', 'HANDOFF.md',
    'docs/ux-simulation/PARALLEL_WORK.md', 'docs/ux-simulation/CONTRACT.md',
    'docs/ux-simulation/workspaces.json',
    'docs/ux-simulation/prompts/A-coordinator.md', 'docs/ux-simulation/prompts/B-capture.md',
    'docs/ux-simulation/prompts/C-scenarios.md', 'docs/ux-simulation/prompts/D-runner.md',
    'simulation/contracts/persona.schema.json', 'simulation/contracts/scenario.schema.json',
    'simulation/contracts/capture-manifest.schema.json', 'simulation/contracts/session.schema.json',
    'simulation/contracts/examples/persona.json', 'simulation/contracts/examples/scenario.json',
    'simulation/contracts/examples/capture-manifest.json', 'simulation/contracts/examples/session.json',
    'scripts/ux_simulation_integrate.ps1', 'scripts/ux_simulation_setup.ps1'
)
$changes = @(Invoke-Git @('status', '--porcelain', '--untracked-files=all'))
foreach ($line in $changes) {
    if ($line.Length -gt 3 -and $ownedFiles -notcontains $line.Substring(3)) {
        if ($line.StartsWith('?? ')) { continue }
        throw ('Another task has tracked uncommitted changes; preserve and coordinate before setup: ' + $line)
    }
}

$tasks = @('coordinator', 'capture', 'scenarios', 'runner')
$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $repository '.worktrees'))
$workspacePrefix = $workspaceRoot + [IO.Path]::DirectorySeparatorChar
$plans = @()
foreach ($task in $tasks) {
    $target = [IO.Path]::GetFullPath((Join-Path $workspaceRoot ('ux-' + $task)))
    if (-not $target.StartsWith($workspacePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Worktree target escapes the intended workspace root.' }
    if (Test-Path -LiteralPath $target) { throw ('Worktree target already exists; do not overwrite: ' + $target) }
    $branch = 'codex/ux-' + $task
    $existing = @(Invoke-Git @('branch', '--list', $branch))
    if ($existing.Count -gt 0) { throw ('Branch already exists; inspect before reusing: ' + $branch) }
    $plans += [PSCustomObject]@{ Path = $target; Branch = $branch }
}

Invoke-Git @('diff', '--check') | Out-Null
if ($changes.Count -gt 0) {
    Invoke-Git (@('add', '--') + $ownedFiles) | Out-Null
    Invoke-Git (@('-c', 'user.name=Codex', '-c', 'user.email=codex@users.noreply.github.com',
        'commit', '--only', '-m', 'docs: prepare four parallel UX simulation workspaces [skip ci]', '--') + $ownedFiles) | Write-Output
}
if (Invoke-Git @('status', '--porcelain', '--untracked-files=no')) { throw 'Original workspace has tracked changes after setup. Preserve them before creating worktrees.' }
$seedCommit = ((Invoke-Git @('rev-parse', 'HEAD')) -join '')
foreach ($plan in $plans) {
    Invoke-Git @('worktree', 'add', '-b', $plan.Branch, $plan.Path, $seedCommit) | Write-Output
}
Write-Output ('All four worktrees start from ' + $seedCommit + '. Integration target: local main.')
Invoke-Git @('worktree', 'list') | Write-Output
