[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '..')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($RepositoryRoot)
$errors = New-Object System.Collections.ArrayList

function Add-ValidationError {
    param([Parameter(Mandatory)][string]$Message)
    [void]$script:errors.Add($Message)
}

$forbiddenTopLevelDirectories = @(
    'source',
    'sources',
    'workshop',
    'Steam',
    'staging',
    'quarantine',
    'unreviewed-assets'
)

foreach ($directory in $forbiddenTopLevelDirectories) {
    if (Test-Path -LiteralPath (Join-Path $root $directory) -PathType Container) {
        Add-ValidationError "Forbidden source or staging directory is present: $directory"
    }
}

$forbiddenArchiveExtensions = @('.zip', '.7z', '.rar')
$files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object {
    $_.FullName -notmatch '[\\/]\.git[\\/]'
})

foreach ($file in $files) {
    $relative = $file.FullName.Substring($root.Length).TrimStart('\', '/')

    if ($forbiddenArchiveExtensions -contains $file.Extension.ToLowerInvariant()) {
        Add-ValidationError "Archive files may not be committed: $relative"
    }

    if ($file.Length -gt 95MB) {
        Add-ValidationError "File exceeds the repository safety limit of 95 MB: $relative ($($file.Length) bytes)"
    }

    if ($relative -like 'audit\generated\*' -or $relative -like 'audit/generated/*') {
        if ($file.Extension.ToLowerInvariant() -in @('.csv', '.md', '.json', '.txt')) {
            try {
                $content = [System.IO.File]::ReadAllText($file.FullName)
                if ($content -match '(?i)[a-z]:\\(?:steam|star-wars-air-combat|users)\\') {
                    Add-ValidationError "Generated audit report leaks an absolute local path: $relative"
                }
            }
            catch {
                Add-ValidationError "Unable to inspect generated audit report: $relative"
            }
        }
    }
}

$requiredFiles = @(
    'README.md',
    '.gitignore',
    'docs\scope.md',
    'docs\extraction-workflow.md',
    'docs\air-combat-manifest.md',
    'docs\fighter-manifest.md',
    'docs\credits-and-permissions.md'
)

foreach ($required in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)) {
        Add-ValidationError "Required project file is missing: $required"
    }
}

$powerShellFiles = @($files | Where-Object Extension -eq '.ps1')
foreach ($scriptFile in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )

    foreach ($parseError in @($parseErrors)) {
        $relative = $scriptFile.FullName.Substring($root.Length).TrimStart('\', '/')
        Add-ValidationError "PowerShell parse error in $relative at line $($parseError.Extent.StartLineNumber): $($parseError.Message)"
    }
}

if ($errors.Count -gt 0) {
    Write-Error ("Repository hygiene validation failed:`n- " + ($errors -join "`n- "))
    exit 1
}

Write-Host "Repository hygiene validation passed. Inspected $($files.Count) files."
