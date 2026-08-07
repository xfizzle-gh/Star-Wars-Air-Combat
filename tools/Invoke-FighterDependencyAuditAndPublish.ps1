[CmdletBinding()]
param(
    [Parameter()]
    [string]$ShatteredGalaxySource,

    [Parameter()]
    [string]$BranchName = 'audit/fighter-dependency-closure',

    [Parameter()]
    [switch]$SkipPush
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workshopContentRoot = Split-Path -Parent $repositoryRoot
$resolver = Join-Path $PSScriptRoot 'Resolve-ModDependencies.ps1'
$hygieneScript = Join-Path $PSScriptRoot 'Test-RepositoryHygiene.ps1'
$pullRequestScript = Join-Path $PSScriptRoot 'Invoke-AuditPullRequest.ps1'
$outputRoot = Join-Path $repositoryRoot 'audit\generated\fighter-dependency-closure'

$roots = @(
    'resource\entity\-vehicle_star_wars\airborne\tie_ln\tie_ln.def',
    'resource\entity\-vehicle_star_wars\airborne\xwing\xwing.def'
)

function Select-ExistingDirectory {
    param(
        [Parameter(Mandatory)][string]$Purpose,
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Candidates
    )

    $checked = @()
    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $checked += $candidate
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $candidate).Path)
        }
    }

    throw "$Purpose folder was not found. Checked: $($checked -join '; ')"
}

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments)

    & git -C $repositoryRoot @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "git command failed with exit code ${exitCode}: git $($Arguments -join ' ')"
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git was not found on PATH.'
}
if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot '.git'))) {
    throw "This script must run from a cloned Git repository: $repositoryRoot"
}

$dirtyLines = @(& git -C $repositoryRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect the Git working tree.'
}
$unexpectedChanges = @($dirtyLines | Where-Object {
    $line = [string]$_
    $path = if ($line.Length -gt 3) { $line.Substring(3).Replace('/', '\') } else { '' }
    -not $path.StartsWith('audit\generated\', [System.StringComparison]::OrdinalIgnoreCase)
})
if ($unexpectedChanges.Count -gt 0) {
    throw "The repository has changes outside audit/generated. Commit or discard them first.`n$($unexpectedChanges -join "`n")"
}

Invoke-Git -Arguments @('fetch', 'origin', 'main')

$currentBranch = (& git -C $repositoryRoot branch --show-current).Trim()
& git -C $repositoryRoot show-ref --verify --quiet "refs/heads/$BranchName"
$branchExists = $LASTEXITCODE -eq 0

if ($currentBranch -ne $BranchName) {
    if ($branchExists) {
        Invoke-Git -Arguments @('checkout', $BranchName)
    }
    else {
        Invoke-Git -Arguments @('checkout', '-b', $BranchName, 'origin/main')
    }
}
Invoke-Git -Arguments @('rebase', 'origin/main')

$sourceRoot = Select-ExistingDirectory -Purpose 'Shattered Galaxy source' -Candidates @(
    $ShatteredGalaxySource,
    (Join-Path $repositoryRoot 'sources\shattered-galaxy'),
    (Join-Path $repositoryRoot 'sources\2984016031'),
    (Join-Path $workshopContentRoot '2984016031'),
    'E:\Star-Wars-Air-Combat\sources\shattered-galaxy',
    'E:\Steam\steamapps\workshop\content\400750\2984016031'
)

Write-Host "Repository root: $repositoryRoot"
Write-Host "Shattered Galaxy source: $sourceRoot"
Write-Host 'Roots:'
$roots | ForEach-Object { Write-Host "  $_" }
Write-Host ''
Write-Host 'Indexing the local source and tracing quoted/resource references. No source assets will be copied.'

& $resolver `
    -SourceRoot $sourceRoot `
    -RootRelativePath $roots `
    -OutputRoot $outputRoot
if ($LASTEXITCODE -ne 0) {
    throw "Dependency resolver failed with exit code $LASTEXITCODE"
}

& $hygieneScript -RepositoryRoot $repositoryRoot
if ($LASTEXITCODE -ne 0) {
    throw "Repository hygiene validation failed with exit code $LASTEXITCODE"
}

Invoke-Git -Arguments @('add', '--', 'audit/generated/fighter-dependency-closure')
& git -C $repositoryRoot diff --cached --quiet
$hasChanges = $LASTEXITCODE -ne 0

if ($hasChanges) {
    Invoke-Git -Arguments @('commit', '-m', 'audit: trace TIE and X-wing dependency closure')
}
else {
    Write-Host 'No dependency-audit changes need to be committed.'
}

if ($SkipPush) {
    Write-Host 'Push skipped by request.'
    exit 0
}

Invoke-Git -Arguments @('push', '--set-upstream', 'origin', $BranchName)

& $pullRequestScript `
    -BranchName $BranchName `
    -Title 'audit: trace TIE/LN and X-wing dependency closure'

Write-Host ''
Write-Host 'Fighter dependency audit completed and pushed.'
