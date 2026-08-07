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

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Add-ValidationError 'Git is required for repository hygiene validation.'
    $trackedRelativePaths = @()
}
else {
    $trackedRelativePaths = @(& git -C $root ls-files)
    if ($LASTEXITCODE -ne 0) {
        Add-ValidationError 'Unable to enumerate tracked repository files.'
        $trackedRelativePaths = @()
    }
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
    $normalizedPrefix = $directory.ToLowerInvariant() + '/'
    $trackedMatch = @($trackedRelativePaths | Where-Object {
        $normalized = $_.Replace('\', '/').ToLowerInvariant()
        $normalized -eq $directory.ToLowerInvariant() -or $normalized.StartsWith($normalizedPrefix)
    })

    if ($trackedMatch.Count -gt 0) {
        Add-ValidationError "Forbidden source or staging directory contains tracked files: $directory"
    }
}

$files = @(
    foreach ($relativePath in $trackedRelativePaths) {
        $nativeRelativePath = $relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $fullPath = Join-Path $root $nativeRelativePath
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            Get-Item -LiteralPath $fullPath -Force
        }
    }
)

$forbiddenArchiveExtensions = @('.zip', '.7z', '.rar')
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

$powerShellFiles = @($files | Where-Object { $_.Extension -eq '.ps1' })
foreach ($scriptFile in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )

    foreach ($parseError in @($parseErrors | Where-Object { $null -ne $_ })) {
        $relative = $scriptFile.FullName.Substring($root.Length).TrimStart('\', '/')
        Add-ValidationError "PowerShell parse error in $relative at line $($parseError.Extent.StartLineNumber): $($parseError.Message)"
    }
}

if ($errors.Count -gt 0) {
    Write-Error ("Repository hygiene validation failed:`n- " + ($errors -join "`n- "))
    exit 1
}

Write-Host "Repository hygiene validation passed. Inspected $($files.Count) tracked files."
